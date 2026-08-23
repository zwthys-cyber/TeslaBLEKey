import Foundation
import Observation
import Security
import CryptoKit
@preconcurrency import TeslaBLEKeyKit

@MainActor
@Observable
final class VehicleController {
    enum VehicleAction: String, CaseIterable, Hashable, Identifiable, Sendable {
        case lock, unlock, frunk, trunk, drive, flash, horn, chargePort, climate, windows
        case mediaPrevious, mediaPlayPause, mediaNext
        var id: String { rawValue }
    }

    enum Phase: Equatable {
        case idle, scanning, connecting, pairingAwaitingCard, handshaking, connected
        case executing(String)
        case failed(String)

        var title: String {
            switch self {
            case .idle: "未连接"
            case .scanning: "正在寻找车辆"
            case .connecting: "正在连接"
            case .pairingAwaitingCard: "等待钥匙卡确认"
            case .handshaking: "正在建立安全连接"
            case .connected: "已连接"
            case let .executing(action): "正在\(action)"
            case let .failed(message): message
            }
        }
    }

    private let keyStore = LocalTeslaKeyStore(service: "com.local.teslablekey.keys")
    private var connection: BLEConnection?
    private var tesla: TeslaVehicle?
    private var legacyClient: LegacyVCSECClient?
    private var pendingPairing: (vehicle: NearbyTesla, connection: BLEConnection)?
    private var passiveDisconnectObserver: NSObjectProtocol?
    private var intentionalDisconnect = false

    var vehicleID: String
    var isPaired: Bool
    var passiveEntryEnabled: Bool
    var vehicleModelName: String?
    var phase: Phase = .idle
    var showingError = false
    var errorMessage = ""
    var showingVehicleIdentity = false
    var canConfirmPairing = false
    var executingAction: VehicleAction?
    var lastSuccessAction: VehicleAction?
    var isTrunkOpen = false
    var isLocked: Bool?
    var isChargePortOpen = false
    var isClimateOn = false
    var cabinTemperature: Double?
    var targetTemperature = 22.0
    var areWindowsVented = false
    var batteryLevel: Int?
    var estimatedRangeKilometers: Double?
    var chargeLimit: Int?
    var chargerPowerKilowatts: Int?
    var chargerVoltage: Int?
    var chargerCurrentAmps: Int?
    var minutesToChargeLimit: Int?
    var chargingStatus: String?
    var chargeCableStatus: String?
    var chargePortLatchStatus: String?
    var outsideTemperature: Double?
    var openDoorCount: Int?
    var openWindowCount: Int?
    var doorStates: [String: Bool] = [:]
    var windowStates: [String: Bool] = [:]
    var isFrunkOpen: Bool?
    var vehicleSleepStatus: String?
    var currentGear: String?
    var odometerKilometers: Double?
    var tirePressureFL: Double?
    var tirePressureFR: Double?
    var tirePressureRL: Double?
    var tirePressureRR: Double?
    var hasTirePressureWarning = false
    /// Version offered by a pending software update. Tesla's local BLE
    /// VehicleData schema does not expose the currently installed firmware.
    var availableSoftwareVersion: String?
    var softwareUpdateStatus: String?
    var mediaTitle: String?
    var mediaArtist: String?
    var mediaAlbum: String?
    var mediaSource: String?
    var mediaPlaybackStatus: String?
    var lastStateUpdate: Date?
    private var successClearTask: Task<Void, Never>?
    private var handshakeTimeoutTask: Task<Void, Never>?
    private var handshakeDidTimeOut = false

    var displayVehicleName: String {
        if let vehicleModelName { return "Tesla \(vehicleModelName)" }
        guard !vehicleID.isEmpty else { return "Tesla Vehicle" }
        return "Tesla · \(String(vehicleID.dropLast().suffix(4)).uppercased())"
    }

    init() {
        let defaults = UserDefaults.standard
        let storedVehicleID = defaults.string(forKey: AppStorageKeys.pairedVehicleID) ?? ""
        vehicleID = storedVehicleID
        vehicleModelName = defaults.string(forKey: AppStorageKeys.vehicleModelPrefix + storedVehicleID)
        let pairingWasVerified = defaults.integer(forKey: AppStorageKeys.pairingSchemaVersion) >= 3
        isPaired = defaults.bool(forKey: AppStorageKeys.paired) && pairingWasVerified
        passiveEntryEnabled = (defaults.object(forKey: AppStorageKeys.passiveEntryEnabled) as? Bool) ?? true
        if !pairingWasVerified {
            defaults.set(false, forKey: AppStorageKeys.paired)
        }
        passiveDisconnectObserver = NotificationCenter.default.addObserver(
            forName: BLEConnection.didDisconnectNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self,
                      let disconnected = notification.object as? BLEConnection,
                      disconnected === self.connection else { return }
                if self.intentionalDisconnect {
                    self.intentionalDisconnect = false
                    return
                }
                guard self.passiveEntryEnabled else { return }
                await self.restorePassiveConnection(on: disconnected)
            }
        }
    }

    func pair(with nearby: NearbyTesla) async {
        canConfirmPairing = false
        phase = .connecting
        do {
            let key = try keyStore.loadOrCreate(for: nearby.peripheralName)
            let link = try BLEConnection(localName: nearby.peripheralName)
            connection = link
            try await link.connect(timeout: 30)

            let legacyProbe = LegacyVCSECClient(connection: link, privateKey: key)
            if try await legacyProbe.isKeyWhitelisted() {
                link.close()
                connection = nil
                vehicleID = nearby.peripheralName
                UserDefaults.standard.set(vehicleID, forKey: AppStorageKeys.pairedVehicleID)
                try? await Task.sleep(for: .milliseconds(500))
                try await connect()
                markPairingVerified()
                return
            }

            phase = .pairingAwaitingCard
            let pairing = TeslaPairing(connector: link)
            try await pairing.requestPairing(
                publicKey: key.publicKey,
                role: .owner,
                formFactor: .iosDevice
            )
            // An unauthenticated add-key request can return before the vehicle
            // has committed the physical key-card approval. Wait for an explicit
            // confirmation instead of immediately starting an authenticated session.
            pendingPairing = (nearby, link)
            phase = .pairingAwaitingCard
            canConfirmPairing = true
        } catch {
            disconnect()
            presentError(Self.describe(error))
        }
    }

    func confirmPairingAndConnect() async {
        guard let pendingPairing else {
            presentError("配对会话已失效，请重新搜索车辆。")
            return
        }

        let selectedVehicle = pendingPairing.vehicle
        canConfirmPairing = false
        pendingPairing.connection.close()
        self.pendingPairing = nil
        connection = nil
        vehicleID = selectedVehicle.peripheralName
        UserDefaults.standard.set(vehicleID, forKey: AppStorageKeys.pairedVehicleID)

        // Give VCSEC a brief moment to commit the approved key before reconnecting.
        try? await Task.sleep(for: .milliseconds(800))
        do {
            try await connect()
            markPairingVerified()
        } catch {
            disconnect()
            presentError(Self.describe(error))
        }
    }

    func connect() async throws {
        guard !vehicleID.isEmpty else { throw LocalError.noVehicle }
        intentionalDisconnect = false
        phase = .connecting
        let key = try keyStore.load(for: vehicleID)
        let restorationID = passiveEntryEnabled ? "com.local.teslablekey.passive.\(vehicleID)" : nil
        let link = try BLEConnection(localName: vehicleID, restorationIdentifier: restorationID)
        connection = link
        try await link.connect(timeout: 30)
        phase = .handshaking
        handshakeDidTimeOut = false
        handshakeTimeoutTask?.cancel()
        handshakeTimeoutTask = Task { [weak self, weak link] in
            // VehicleInfo discovery may consume up to ten seconds before the
            // legacy-session fallback starts, so the whole bootstrap needs a
            // wider deadline than either individual operation.
            try? await Task.sleep(for: .seconds(35))
            guard !Task.isCancelled, let self, self.phase == .handshaking else { return }
            self.handshakeDidTimeOut = true
            link?.close()
            self.presentError("安全连接超时。请唤醒车辆、靠近驾驶位后重试。")
        }
        if let cachedVIN = cachedVIN(), cachedVIN.count == 17 {
            try await startModernSession(on: link, key: key, vin: cachedVIN)
        } else {
            let bootstrap = LegacyVCSECClient(connection: link, privateKey: key)
            // Establish the VIN-free phone-key session. Tesla's published
            // VCSEC schema does not expose the VIN; infotainment is upgraded
            // later after the user supplies and locally verifies it once.
            try await bootstrap.startSession()
            legacyClient = bootstrap
        }
        handshakeTimeoutTask?.cancel()
        handshakeTimeoutTask = nil
        guard !handshakeDidTimeOut else { throw LocalError.handshakeTimedOut }
        phase = .connected
        await refreshVehicleState()
    }

    func connectFromUI() async {
        do { try await connect() } catch { presentError(Self.describe(error)) }
    }

    /// iOS may suspend BLE work while the app is in the background. Refresh
    /// immediately on return, or rebuild the session if restoration left the
    /// controller disconnected.
    func refreshAfterReturningToForeground() async {
        guard isPaired else { return }
        switch phase {
        case .connected:
            await refreshVehicleState()
        case .idle, .failed:
            await connectFromUI()
        default:
            break
        }
    }

    func presentUserError(_ message: String) { presentError(message) }

    func setPassiveEntryEnabled(_ enabled: Bool) async {
        guard passiveEntryEnabled != enabled else { return }
        passiveEntryEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: AppStorageKeys.passiveEntryEnabled)
        disconnect()
        await connectFromUI()
    }

    func saveVehicleVIN(_ input: String) async -> String? {
        let vin = input.uppercased().filter { $0.isLetter || $0.isNumber }
        guard vin.count == 17, !vin.contains(where: { "IOQ".contains($0) }) else {
            return "请输入车机「控制 > 软件」中显示的 17 位 VIN。"
        }
        guard Self.beaconName(forVIN: vin).caseInsensitiveCompare(vehicleID) == .orderedSame else {
            return "此 VIN 与当前连接的车辆不匹配，请确认后重试。"
        }

        cacheVehicleIdentity(vin: vin)
        showingVehicleIdentity = false
        disconnect()
        do {
            try await connect()
            return nil
        } catch {
            presentError(Self.describe(error))
            return "车辆身份已保存，请靠近车辆后重新连接。"
        }
    }

    func lock() async {
        if await execute(.lock, name: "上锁", operation: { try await self.perform(modern: { try await $0.lock() }, legacy: { try await $0.rke(1) }) }) { isLocked = true }
    }
    func unlock() async {
        if await execute(.unlock, name: "解锁", operation: { try await self.perform(modern: { try await $0.unlock() }, legacy: { try await $0.rke(0) }) }) { isLocked = false }
    }
    func openTrunk() async {
        if await execute(.trunk, name: "开启后备箱", operation: {
            try await self.perform(modern: { try await self.moveRearTrunk($0, action: .closureMoveTypeMove) }, legacy: { try await $0.rke(2) })
        }) { isTrunkOpen = true }
    }
    func closeTrunk() async {
        if await execute(.trunk, name: "关闭后备箱", operation: {
            try await self.perform(modern: { try await self.moveRearTrunk($0, action: .closureMoveTypeClose) }, legacy: { try await $0.rke(2) })
        }) { isTrunkOpen = false }
    }
    func openFrunk() async { await execute(.frunk, name: "开启前备箱") { try await self.perform(modern: { try await $0.openFrunk() }, legacy: { try await $0.rke(3) }) } }
    func flashLights() async { await execute(.flash, name: "闪灯") { try await self.performModern { try? await $0.wakeVehicle(); try await $0.startInfotainmentSession(); try await $0.flashLights() } } }
    func honk() async { await execute(.horn, name: "鸣笛") { try await self.performModern { try? await $0.wakeVehicle(); try await $0.startInfotainmentSession(); try await $0.honkHorn() } } }
    func authorizeDrive() async {
        await execute(.drive, name: "启动车辆") {
            try await self.performModern { try await self.sendRawRKE(.rkeActionRemoteDrive, to: $0) }
        }
    }

    func toggleChargePort() async {
        let opening = !isChargePortOpen
        if await execute(.chargePort, name: opening ? "打开充电口" : "关闭充电口", operation: {
            try await self.performModern { vehicle in
                var action = CarServer_VehicleAction()
                if opening { action.chargePortDoorOpen = CarServer_ChargePortDoorOpen() }
                else { action.chargePortDoorClose = CarServer_ChargePortDoorClose() }
                try await self.send(action, to: vehicle)
            }
        }) { isChargePortOpen = opening }
    }

    func toggleClimate() async {
        let turningOn = !isClimateOn
        if await execute(.climate, name: turningOn ? "打开空调" : "关闭空调", operation: {
            try await self.performModern { vehicle in
                var hvac = CarServer_HvacAutoAction()
                hvac.powerOn = turningOn
                var action = CarServer_VehicleAction()
                action.hvacAutoAction = hvac
                try await self.send(action, to: vehicle)
            }
        }) { isClimateOn = turningOn }
    }

    func setCabinTemperature(_ celsius: Double) async {
        let target = min(max(celsius, 15), 28)
        if await execute(.climate, name: "设置温度", operation: {
            try await self.performModern { vehicle in
                var temperature = CarServer_HvacTemperatureAdjustmentAction()
                temperature.driverTempCelsius = Float(target)
                temperature.passengerTempCelsius = Float(target)
                var action = CarServer_VehicleAction()
                action.hvacTemperatureAdjustmentAction = temperature
                try await self.send(action, to: vehicle)
            }
        }) { targetTemperature = target }
    }

    func toggleWindows() async {
        let venting = !areWindowsVented
        if await execute(.windows, name: venting ? "车窗通风" : "关闭车窗", operation: {
            try await self.performModern { vehicle in
                var windows = CarServer_VehicleControlWindowAction()
                if venting { windows.vent = CarServer_Void() }
                else { windows.close = CarServer_Void() }
                var action = CarServer_VehicleAction()
                action.vehicleControlWindowAction = windows
                try await self.send(action, to: vehicle)
            }
        }) { areWindowsVented = venting }
    }

    func previousMediaTrack() async {
        if await execute(.mediaPrevious, name: "切换上一首", operation: {
            try await self.performModern { try await $0.mediaPreviousTrack() }
        }) { await refreshMediaAfterTrackChange() }
    }

    func toggleMediaPlayback() async {
        if await execute(.mediaPlayPause, name: mediaPlaybackStatus == "播放中" ? "暂停播放" : "继续播放", operation: {
            try await self.performModern { try await $0.mediaTogglePlayback() }
        }) {
            mediaPlaybackStatus = mediaPlaybackStatus == "播放中" ? "已暂停" : "播放中"
        }
    }

    func nextMediaTrack() async {
        if await execute(.mediaNext, name: "切换下一首", operation: {
            try await self.performModern { try await $0.mediaNextTrack() }
        }) { await refreshMediaAfterTrackChange() }
    }

    private func refreshMediaAfterTrackChange() async {
        try? await Task.sleep(for: .milliseconds(450))
        guard let tesla,
              let data = await requestVehicleData(from: tesla, configure: { $0.getMediaState = CarServer_GetMediaState() }),
              data.hasMediaState else { return }
        apply(data.mediaState)
        if let details = await requestVehicleData(from: tesla, configure: { $0.getMediaDetailState = CarServer_GetMediaDetailState() }),
           details.hasMediaDetailState { apply(details.mediaDetailState) }
    }

    func refreshVehicleState() async {
        guard let tesla = try? await ensureModernSession() else { return }
        availableSoftwareVersion = nil
        softwareUpdateStatus = nil
        if let status = try? await tesla.vehicleStatus() {
            if let value = Self.isOpen(status.closureStatuses.rearTrunk) { isTrunkOpen = value }
            if let value = Self.isOpen(status.closureStatuses.frontTrunk) { isFrunkOpen = value }
            if let value = Self.isOpen(status.closureStatuses.chargePort) { isChargePortOpen = value }
            isLocked = status.vehicleLockState == .vehiclelockstateLocked || status.vehicleLockState == .vehiclelockstateInternalLocked
            vehicleSleepStatus = switch status.vehicleSleepStatus {
            case .vehicleSleepStatusAwake: "已唤醒"
            case .vehicleSleepStatusAsleep: "休眠"
            default: "状态未知"
            }
        }
        try? await tesla.startInfotainmentSession()
        if let data = await requestVehicleData(from: tesla, configure: { $0.getChargeState = CarServer_GetChargeState() }), data.hasChargeState {
            apply(data.chargeState)
        }
        if let data = await requestVehicleData(from: tesla, configure: { $0.getClimateState = CarServer_GetClimateState() }), data.hasClimateState {
            apply(data.climateState)
        }
        if let data = await requestVehicleData(from: tesla, configure: { $0.getClosuresState = CarServer_GetClosuresState() }), data.hasClosuresState {
            apply(data.closuresState)
        }
        if let data = await requestVehicleData(from: tesla, configure: { $0.getTirePressureState = CarServer_GetTirePressureState() }), data.hasTirePressureState {
            apply(data.tirePressureState)
        }
        if let data = await requestVehicleData(from: tesla, configure: { $0.getDriveState = CarServer_GetDriveState() }), data.hasDriveState {
            currentGear = switch data.driveState.shiftState.type {
            case .p?: "P · 已驻车"
            case .r?: "R · 倒车"
            case .n?: "N · 空挡"
            case .d?: "D · 行驶"
            default: "挡位未知"
            }
            if data.driveState.optionalOdometerInHundredthsOfAMile != nil {
                odometerKilometers = Double(data.driveState.odometerInHundredthsOfAMile) / 100 * 1.609344
            }
        }
        if let data = await requestVehicleData(from: tesla, configure: { $0.getSoftwareUpdateState = CarServer_GetSoftwareUpdateState() }), data.hasSoftwareUpdateState {
            apply(data.softwareUpdateState)
        }
        if let data = await requestVehicleData(from: tesla, configure: { $0.getMediaState = CarServer_GetMediaState() }), data.hasMediaState {
            apply(data.mediaState)
        }
        if let data = await requestVehicleData(from: tesla, configure: { $0.getMediaDetailState = CarServer_GetMediaDetailState() }), data.hasMediaDetailState {
            apply(data.mediaDetailState)
        }
        lastStateUpdate = .now
    }

    private func requestVehicleData(
        from vehicle: TeslaVehicle,
        configure: (inout CarServer_GetVehicleData) -> Void
    ) async -> CarServer_VehicleData? {
        var request = CarServer_GetVehicleData()
        configure(&request)
        var action = CarServer_VehicleAction()
        action.getVehicleData = request
        guard let response = try? await vehicle.sendVehicleAction(action),
              case .vehicleData(let data)? = response.responseMsg else { return nil }
        return data
    }

    private func apply(_ state: CarServer_ChargeState) {
        if state.optionalBatteryLevel != nil { batteryLevel = Int(state.batteryLevel) }
        if state.optionalBatteryRange != nil { estimatedRangeKilometers = Double(state.batteryRange) * 1.609344 }
        if state.optionalChargeLimitSoc != nil { chargeLimit = Int(state.chargeLimitSoc) }
        if state.optionalChargerPower != nil { chargerPowerKilowatts = Int(state.chargerPower) }
        if state.optionalChargerVoltage != nil { chargerVoltage = Int(state.chargerVoltage) }
        if state.optionalChargerActualCurrent != nil { chargerCurrentAmps = Int(state.chargerActualCurrent) }
        if state.optionalMinutesToChargeLimit != nil { minutesToChargeLimit = Int(state.minutesToChargeLimit) }
        if state.optionalChargePortDoorOpen != nil { isChargePortOpen = state.chargePortDoorOpen }
        if state.hasConnChargeCable {
            chargeCableStatus = switch state.connChargeCable.type {
            case .sna?: "未连接"
            case .iec?: "IEC 已连接"
            case .sae?: "SAE 已连接"
            case .gbAc?: "国标交流已连接"
            case .gbDc?: "国标直流已连接"
            default: "状态未知"
            }
        }
        if state.hasChargePortLatch {
            chargePortLatchStatus = switch state.chargePortLatch.type {
            case .engaged?: "已锁止"
            case .disengaged?: "未锁止"
            case .blocking?: "锁止受阻"
            default: "状态未知"
            }
        }
        if state.hasChargingState {
            chargingStatus = switch state.chargingState.type {
            case .disconnected?: "未连接充电枪"
            case .noPower?: "已连接 · 无电力"
            case .starting?: "正在开始充电"
            case .charging?: "正在充电"
            case .complete?: "充电完成"
            case .stopped?: "充电已停止"
            case .calibrating?: "正在校准"
            default: "状态未知"
            }
        }
    }

    private func apply(_ state: CarServer_ClimateState) {
        if state.optionalIsClimateOn != nil { isClimateOn = state.isClimateOn }
        if state.optionalInsideTempCelsius != nil { cabinTemperature = Double(state.insideTempCelsius) }
        if state.optionalOutsideTempCelsius != nil { outsideTemperature = Double(state.outsideTempCelsius) }
        if state.optionalDriverTempSetting != nil { targetTemperature = Double(state.driverTempSetting) }
    }

    private func apply(_ state: CarServer_ClosuresState) {
        let doorValues: [(Bool, Bool)] = [
            (state.optionalDoorOpenDriverFront != nil, state.doorOpenDriverFront),
            (state.optionalDoorOpenDriverRear != nil, state.doorOpenDriverRear),
            (state.optionalDoorOpenPassengerFront != nil, state.doorOpenPassengerFront),
            (state.optionalDoorOpenPassengerRear != nil, state.doorOpenPassengerRear)
        ]
        if doorValues.contains(where: { $0.0 }) { openDoorCount = doorValues.filter { $0.0 && $0.1 }.count }
        doorStates = [:]
        if state.optionalDoorOpenDriverFront != nil { doorStates["左前门"] = state.doorOpenDriverFront }
        if state.optionalDoorOpenDriverRear != nil { doorStates["左后门"] = state.doorOpenDriverRear }
        if state.optionalDoorOpenPassengerFront != nil { doorStates["右前门"] = state.doorOpenPassengerFront }
        if state.optionalDoorOpenPassengerRear != nil { doorStates["右后门"] = state.doorOpenPassengerRear }
        let windowValues: [(Bool, Bool)] = [
            (state.optionalWindowOpenDriverFront != nil, state.windowOpenDriverFront),
            (state.optionalWindowOpenDriverRear != nil, state.windowOpenDriverRear),
            (state.optionalWindowOpenPassengerFront != nil, state.windowOpenPassengerFront),
            (state.optionalWindowOpenPassengerRear != nil, state.windowOpenPassengerRear)
        ]
        if windowValues.contains(where: { $0.0 }) { openWindowCount = windowValues.filter { $0.0 && $0.1 }.count }
        windowStates = [:]
        if state.optionalWindowOpenDriverFront != nil { windowStates["左前窗"] = state.windowOpenDriverFront }
        if state.optionalWindowOpenDriverRear != nil { windowStates["左后窗"] = state.windowOpenDriverRear }
        if state.optionalWindowOpenPassengerFront != nil { windowStates["右前窗"] = state.windowOpenPassengerFront }
        if state.optionalWindowOpenPassengerRear != nil { windowStates["右后窗"] = state.windowOpenPassengerRear }
        if state.optionalDoorOpenTrunkFront != nil { isFrunkOpen = state.doorOpenTrunkFront }
        if state.optionalDoorOpenTrunkRear != nil { isTrunkOpen = state.doorOpenTrunkRear }
        if state.optionalLocked != nil { isLocked = state.locked }
    }

    private func apply(_ state: CarServer_TirePressureState) {
        if state.optionalTpmsPressureFl != nil { tirePressureFL = Double(state.tpmsPressureFl) }
        if state.optionalTpmsPressureFr != nil { tirePressureFR = Double(state.tpmsPressureFr) }
        if state.optionalTpmsPressureRl != nil { tirePressureRL = Double(state.tpmsPressureRl) }
        if state.optionalTpmsPressureRr != nil { tirePressureRR = Double(state.tpmsPressureRr) }
        hasTirePressureWarning = state.tpmsHardWarningFl || state.tpmsHardWarningFr
            || state.tpmsHardWarningRl || state.tpmsHardWarningRr
            || state.tpmsSoftWarningFl || state.tpmsSoftWarningFr
            || state.tpmsSoftWarningRl || state.tpmsSoftWarningRr
    }

    private func apply(_ state: CarServer_SoftwareUpdateState) {
        if state.optionalVersion != nil, !state.version.isEmpty {
            availableSoftwareVersion = state.version
        }
        if state.hasStatus {
            softwareUpdateStatus = switch state.status.type {
            case .available?: "有可用更新"
            case .scheduled?: "已安排更新"
            case .installing?: "正在安装"
            case .downloading?: "正在下载"
            case .downloadingWifiWait?: "等待 Wi-Fi"
            default: nil
            }
        }
    }

    private func apply(_ state: CarServer_MediaState) {
        if state.optionalNowPlayingTitle != nil { mediaTitle = state.nowPlayingTitle.nilIfEmpty }
        if state.optionalNowPlayingArtist != nil { mediaArtist = state.nowPlayingArtist.nilIfEmpty }
        if state.optionalMediaPlaybackStatus != nil {
            mediaPlaybackStatus = switch state.mediaPlaybackStatus {
            case .playing: "播放中"
            case .paused: "已暂停"
            case .stopped: "已停止"
            default: "状态未知"
            }
        }
    }

    private func apply(_ state: CarServer_MediaDetailState) {
        if state.optionalNowPlayingAlbum != nil { mediaAlbum = state.nowPlayingAlbum.nilIfEmpty }
        if state.optionalNowPlayingSourceString != nil { mediaSource = state.nowPlayingSourceString.nilIfEmpty }
        if mediaSource == nil, state.optionalA2DpSourceName != nil { mediaSource = state.a2DpSourceName.nilIfEmpty }
    }

    func disconnect() {
        intentionalDisconnect = true
        handshakeTimeoutTask?.cancel()
        handshakeTimeoutTask = nil
        tesla?.disconnect()
        legacyClient?.close()
        pendingPairing?.connection.close()
        connection?.close()
        pendingPairing = nil
        canConfirmPairing = false
        tesla = nil
        legacyClient = nil
        connection = nil
        phase = .idle
    }

    private func restorePassiveConnection(on link: BLEConnection) async {
        guard passiveEntryEnabled, connection === link else { return }
        tesla = nil
        legacyClient = nil
        phase = .connecting
        do {
            try await link.connect(timeout: 45)
            let key = try keyStore.load(for: vehicleID)
            phase = .handshaking
            if let vin = cachedVIN(), vin.count == 17 {
                try await startModernSession(on: link, key: key, vin: vin)
            } else {
                let bootstrap = LegacyVCSECClient(connection: link, privateKey: key)
                try await bootstrap.startSession()
                legacyClient = bootstrap
            }
            phase = .connected
            await refreshVehicleState()
        } catch {
            // A pending CoreBluetooth reconnect is preserved by iOS. Keep the
            // UI neutral here; the physical key card remains the safe fallback.
            phase = .idle
        }
    }

    func forgetVehicle() {
        UserDefaults.standard.removeObject(forKey: AppStorageKeys.vehicleVINPrefix + vehicleID)
        UserDefaults.standard.removeObject(forKey: AppStorageKeys.vehicleModelPrefix + vehicleID)
        disconnect()
        try? keyStore.delete(for: vehicleID)
        UserDefaults.standard.removeObject(forKey: AppStorageKeys.pairedVehicleID)
        UserDefaults.standard.removeObject(forKey: AppStorageKeys.paired)
        UserDefaults.standard.removeObject(forKey: AppStorageKeys.pairingSchemaVersion)
        vehicleID = ""
        vehicleModelName = nil
        isPaired = false
    }

    @discardableResult
    private func execute(_ action: VehicleAction, name: String, operation: () async throws -> Void) async -> Bool {
        guard tesla != nil || legacyClient != nil else { presentError("请先连接车辆。"); return false }
        // Tesla vehicle commands share one authenticated BLE session. Serialize them
        // so a second command cannot replace the first command's presentation state.
        guard executingAction == nil else { return false }
        successClearTask?.cancel()
        lastSuccessAction = nil
        executingAction = action
        phase = .executing(name)
        do {
            try await operation()
            executingAction = nil
            lastSuccessAction = action
            phase = .connected
            successClearTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(700))
                guard !Task.isCancelled else { return }
                self?.lastSuccessAction = nil
            }
            return true
        } catch {
            executingAction = nil
            if case LocalError.vehicleIdentityUnavailable = error {
                phase = .connected
                showingVehicleIdentity = true
                return false
            }
            presentError(Self.describe(error))
            return false
        }
    }

    private func moveRearTrunk(_ vehicle: TeslaVehicle, action: VCSEC_ClosureMoveType_E) async throws {
        var request = VCSEC_ClosureMoveRequest()
        request.rearTrunk = action
        var payload = VCSEC_UnsignedMessage()
        payload.closureMoveRequest = request
        _ = try await vehicle.sendRawVCSEC(payload: payload.serializedData())
    }

    private func sendRawRKE(_ action: VCSEC_RKEAction_E, to vehicle: TeslaVehicle) async throws {
        var payload = VCSEC_UnsignedMessage()
        payload.rkeaction = action
        _ = try await vehicle.sendRawVCSEC(payload: payload.serializedData())
    }

    private func send(_ action: CarServer_VehicleAction, to vehicle: TeslaVehicle) async throws {
        try? await vehicle.wakeVehicle()
        try await vehicle.startInfotainmentSession()
        _ = try await vehicle.sendVehicleAction(action)
    }

    private func perform(
        modern: (TeslaVehicle) async throws -> Void,
        legacy: (LegacyVCSECClient) async throws -> Void
    ) async throws {
        if let tesla { try await modern(tesla); return }
        if let legacyClient { try await legacy(legacyClient); return }
        throw LocalError.noVehicle
    }

    private func performModern(_ operation: (TeslaVehicle) async throws -> Void) async throws {
        let modernVehicle = try await ensureModernSession()
        try await operation(modernVehicle)
    }

    private func ensureModernSession() async throws -> TeslaVehicle {
        if let tesla { return tesla }
        guard let legacyClient, let connection else { throw LocalError.noVehicle }

        // VIN participates in modern domain authentication and cannot be
        // reversed from the SHA-1 identifier in the BLE advertisement.
        // Request the one-time, locally verified identity setup immediately.
        _ = legacyClient
        _ = connection
        throw LocalError.vehicleIdentityUnavailable
    }

    private func cachedVIN() -> String? {
        UserDefaults.standard.string(forKey: AppStorageKeys.vehicleVINPrefix + vehicleID)
    }

    private func cacheVehicleIdentity(vin: String) {
        UserDefaults.standard.set(vin, forKey: AppStorageKeys.vehicleVINPrefix + vehicleID)
        if let model = Self.modelName(fromVIN: vin) {
            vehicleModelName = model
            UserDefaults.standard.set(model, forKey: AppStorageKeys.vehicleModelPrefix + vehicleID)
        }
    }

    private func startModernSession(on link: BLEConnection, key: TeslaPrivateKey, vin: String) async throws {
        link.vin = vin
        let client = try TeslaVehicle(
            connector: link,
            privateKey: key,
            configuration: .standard
        )
        try await client.connect()
        try await client.startVCSECSession()
        tesla = client
    }

    private func presentError(_ message: String) {
        errorMessage = message
        phase = .failed(message)
        showingError = true
    }

    private func markPairingVerified() {
        UserDefaults.standard.set(true, forKey: AppStorageKeys.paired)
        UserDefaults.standard.set(3, forKey: AppStorageKeys.pairingSchemaVersion)
        isPaired = true
    }

    private static func describe(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    static func modelName(fromVIN vin: String) -> String? {
        guard vin.count == 17 else { return nil }
        switch vin[vin.index(vin.startIndex, offsetBy: 3)] {
        case "3": return "Model 3"
        case "Y": return "Model Y"
        case "S": return "Model S"
        case "X": return "Model X"
        default: return nil
        }
    }

    static func beaconName(forVIN vin: String) -> String {
        let digest = Insecure.SHA1.hash(data: Data(vin.uppercased().utf8))
        return "S" + digest.prefix(8).map { String(format: "%02x", $0) }.joined() + "C"
    }

    private static func isOpen(_ state: VCSEC_ClosureState_E) -> Bool? {
        switch state {
        case .closurestateClosed: false
        case .closurestateUnknown, .UNRECOGNIZED: nil
        default: true
        }
    }

    private enum LocalError: LocalizedError {
        case noVehicle, keyMissing, handshakeTimedOut, vehicleIdentityUnavailable
        var errorDescription: String? {
            switch self {
            case .noVehicle: "没有已配对车辆"
            case .keyMissing: "本机车辆密钥已丢失，请重新配对"
            case .handshakeTimedOut: "安全连接超时。请唤醒车辆、靠近驾驶位后重试。"
            case .vehicleIdentityUnavailable: "需要先补全车辆身份以启用完整控制。"
            }
        }
    }

    private struct LocalTeslaKeyStore {
        let service: String

        func loadOrCreate(for identifier: String) throws -> TeslaPrivateKey {
            if let existing = try loadOptional(for: identifier) { return existing }
            let key = TeslaPrivateKey.generate()
            try save(key, for: identifier)
            return key
        }

        func load(for identifier: String) throws -> TeslaPrivateKey {
            guard let key = try loadOptional(for: identifier) else { throw LocalError.keyMissing }
            return key
        }

        private func loadOptional(for identifier: String) throws -> TeslaPrivateKey? {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: identifier,
                kSecReturnData as String: true
            ]
            var result: AnyObject?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            if status == errSecItemNotFound { return nil }
            guard status == errSecSuccess, let data = result as? Data else {
                throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
            }
            return try TeslaPrivateKey(rawRepresentation: data)
        }

        private func save(_ key: TeslaPrivateKey, for identifier: String) throws {
            try? delete(for: identifier)
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: identifier,
                kSecValueData as String: key.rawRepresentation,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            ]
            let status = SecItemAdd(query as CFDictionary, nil)
            guard status == errSecSuccess else {
                throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
            }
        }

        func delete(for identifier: String) throws {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: identifier
            ]
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
            }
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
