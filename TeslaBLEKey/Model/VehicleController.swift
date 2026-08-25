import Foundation
import Observation
import Security
import CryptoKit
import LocalAuthentication
@preconcurrency import TeslaBLEKeyKit

@MainActor
@Observable
final class VehicleController {
    enum SceneAction: String, Codable, CaseIterable, Identifiable, Hashable {
        case unlock, lock, climate, defrost, sentry
        var id: String { rawValue }
        var title: String { switch self { case .unlock: "解锁"; case .lock: "上锁"; case .climate: "开启空调"; case .defrost: "最大除霜"; case .sentry: "开启哨兵" } }
    }

    struct AutomationScene: Identifiable, Codable, Hashable {
        var id: UUID
        var name: String
        var symbol: String
        var actions: [SceneAction]
    }

    enum ScheduleKind: String, Identifiable, Hashable { case charging, preconditioning; var id: String { rawValue } }
    struct VehicleSchedule: Identifiable, Hashable {
        let id: UInt64
        let kind: ScheduleKind
        let name: String
        let minutes: Int
        let days: Int32
        let enabled: Bool
    }
    struct ChargingSite: Identifiable, Hashable {
        let id: Int64
        let name: String
        let address: String
        let distanceKilometers: Double
        let availableStalls: Int
        let totalStalls: Int
        let maxPowerKilowatts: Int
        let closed: Bool
    }
    enum FaceIDProtection: String, CaseIterable, Identifiable {
        case off, sensitive, all
        var id: String { rawValue }
        var title: String { switch self { case .off: "关闭"; case .sensitive: "仅敏感操作"; case .all: "全部控制" } }
    }
    enum VehicleAction: String, CaseIterable, Hashable, Identifiable, Sendable {
        case lock, unlock, frunk, trunk, drive, flash, horn, chargePort, climate, windows
        case mediaPrevious, mediaPlayPause, mediaNext
        case charging, chargeLimit, chargeCurrent, defrost, steeringHeater, climateMode, bioweapon, overheat, sentry
        var id: String { rawValue }
    }

    struct CommandRecord: Identifiable, Codable, Hashable {
        let id: UUID
        let name: String
        let date: Date
        let succeeded: Bool
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
    private let managesPassiveKey: Bool
    private var connection: BLEConnection?
    private var tesla: TeslaVehicle?
    private var legacyClient: LegacyVCSECClient?
    private var passiveConnection: BLEConnection?
    private var passiveKeyClient: LegacyVCSECClient?
    private var pendingPairing: (vehicle: NearbyTesla, connection: BLEConnection)?
    private var passiveDisconnectObserver: NSObjectProtocol?
    private var intentionalDisconnect = false

    var vehicleID: String
    var pairedVehicleIDs: [String]
    var isPaired: Bool
    var passiveEntryEnabled: Bool
    var passiveKeyOnline = false
    var vehicleModelName: String?
    var customVehicleName: String?
    var faceIDProtection: FaceIDProtection
    var phase: Phase = .idle
    var showingError = false
    var errorMessage = ""
    var showingVehicleIdentity = false
    var canConfirmPairing = false
    var executingAction: VehicleAction?
    var lastSuccessAction: VehicleAction?
    var isTrunkOpen = false
    var isTrunkMoving = false
    var trunkOperationStatus: String?
    var isLocked: Bool?
    var isChargePortOpen = false
    var isClimateOn = false
    var cabinTemperature: Double?
    var targetTemperature = 22.0
    var minimumCabinTemperature = 15.0
    var maximumCabinTemperature = 28.0
    var areWindowsVented = false
    var batteryLevel: Int?
    var estimatedRangeKilometers: Double?
    var chargeLimit: Int?
    var minimumChargeLimit = 50
    var maximumChargeLimit = 100
    var chargerPowerKilowatts: Int?
    var chargerVoltage: Int?
    var chargerCurrentAmps: Int?
    var maxChargingCurrentAmps: Int?
    var minutesToChargeLimit: Int?
    var chargingStatus: String?
    var isCharging = false
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
    var mediaArtworkURL: URL?
    var isSentryAvailable = false
    var isSentryOn = false
    var isDefrostOn = false
    var isSteeringWheelHeaterOn = false
    var climateKeeperMode = "关闭"
    var isBioweaponModeOn = false
    var isCabinOverheatProtectionOn = false
    var commandHistory: [CommandRecord] = []
    var automationScenes: [AutomationScene] = []
    var alertPreferences: VehicleAlertPreferences
    var vehicleSchedules: [VehicleSchedule] = []
    var nearbyChargingSites: [ChargingSite] = []
    var scheduleLocationName: String?
    private var scheduleLatitude: Float?
    private var scheduleLongitude: Float?
    var lastStateUpdate: Date?
    private var mediaArtworkLookupTask: Task<Void, Never>?
    private var trunkStateRefreshTask: Task<Void, Never>?
    private var lastArtworkLookupKey: String?
    private var isRefreshingVehicleState = false
    private var isRefreshingMediaState = false
    private var successClearTask: Task<Void, Never>?
    private var handshakeTimeoutTask: Task<Void, Never>?
    private var handshakeDidTimeOut = false
    private var passiveReconnectTask: Task<Void, Never>?
    private var passiveRecoveryInProgress = false
    private var foregroundConnectionInProgress = false
    private var sessionNeedsForegroundValidation = false
    private var appIsBackgrounded = false
    private var commandConnectionPausedForBackground = false
    private var authorizedCommandBatchActive = false

    var displayVehicleName: String {
        if let customVehicleName, !customVehicleName.isEmpty { return customVehicleName }
        if let vehicleModelName { return "Tesla \(vehicleModelName)" }
        guard !vehicleID.isEmpty else { return "Tesla Vehicle" }
        return "Tesla · \(String(vehicleID.dropLast().suffix(4)).uppercased())"
    }

    init(managesPassiveKey: Bool = true) {
        self.managesPassiveKey = managesPassiveKey
        let defaults = UserDefaults.standard
        let storedVehicleID = defaults.string(forKey: AppStorageKeys.pairedVehicleID) ?? ""
        vehicleID = storedVehicleID
        var storedIDs = defaults.stringArray(forKey: AppStorageKeys.pairedVehicleIDs) ?? []
        if !storedVehicleID.isEmpty, !storedIDs.contains(storedVehicleID) { storedIDs.insert(storedVehicleID, at: 0) }
        pairedVehicleIDs = storedIDs
        vehicleModelName = defaults.string(forKey: AppStorageKeys.vehicleModelPrefix + storedVehicleID)
        customVehicleName = defaults.string(forKey: AppStorageKeys.customVehicleNamePrefix + storedVehicleID)
        faceIDProtection = FaceIDProtection(rawValue: defaults.string(forKey: AppStorageKeys.faceIDProtectionPrefix + storedVehicleID) ?? "") ?? .sensitive
        let pairingWasVerified = defaults.integer(forKey: AppStorageKeys.pairingSchemaVersion) >= 3
        isPaired = defaults.bool(forKey: AppStorageKeys.paired) && pairingWasVerified
        passiveEntryEnabled = (defaults.object(forKey: AppStorageKeys.passiveEntryEnabled) as? Bool) ?? true
        if let data = defaults.data(forKey: AppStorageKeys.commandHistory),
           let records = try? JSONDecoder().decode([CommandRecord].self, from: data) {
            commandHistory = records
        }
        automationScenes = Self.loadScenes(for: storedVehicleID)
        alertPreferences = Self.loadAlertPreferences(for: storedVehicleID)
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
                      let disconnected = notification.object as? BLEConnection else { return }
                if disconnected === self.passiveConnection {
                    AppDiagnostics.shared.record("ble.passive.disconnected")
                    self.passiveKeyOnline = false
                    guard !self.intentionalDisconnect, self.passiveEntryEnabled else { return }
                    await self.restoreDedicatedPhoneKeyConnection(on: disconnected)
                } else if disconnected === self.connection {
                    AppDiagnostics.shared.record("ble.command.disconnected")
                    if self.passiveConnection == nil { self.passiveKeyOnline = false }
                    guard !self.intentionalDisconnect, self.passiveEntryEnabled,
                          !self.appIsBackgrounded else { return }
                    await self.restoreCommandConnection(on: disconnected)
                }
            }
        }
        // Construct the restorable central at process launch, before SwiftUI
        // has to render a foreground scene. CoreBluetooth may relaunch us only
        // to deliver a door-handle characteristic notification.
        if managesPassiveKey, isPaired, passiveEntryEnabled, !vehicleID.isEmpty {
            Task { [weak self] in await self?.bootstrapPassivePhoneKey() }
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
                vehicleModelName = UserDefaults.standard.string(forKey: AppStorageKeys.vehicleModelPrefix + vehicleID)
                customVehicleName = UserDefaults.standard.string(forKey: AppStorageKeys.customVehicleNamePrefix + vehicleID)
                faceIDProtection = Self.storedFaceIDProtection(for: vehicleID)
                automationScenes = Self.loadScenes(for: vehicleID)
                alertPreferences = Self.loadAlertPreferences(for: vehicleID)
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

    func switchVehicle(to identifier: String) async {
        guard identifier != vehicleID, pairedVehicleIDs.contains(identifier) else { return }
        disconnect()
        vehicleID = identifier
        vehicleModelName = UserDefaults.standard.string(forKey: AppStorageKeys.vehicleModelPrefix + identifier)
        customVehicleName = UserDefaults.standard.string(forKey: AppStorageKeys.customVehicleNamePrefix + identifier)
        faceIDProtection = Self.storedFaceIDProtection(for: identifier)
        automationScenes = Self.loadScenes(for: identifier)
        alertPreferences = Self.loadAlertPreferences(for: identifier)
        vehicleSchedules = []; nearbyChargingSites = []; scheduleLocationName = nil; scheduleLatitude = nil; scheduleLongitude = nil
        UserDefaults.standard.set(identifier, forKey: AppStorageKeys.pairedVehicleID)
        isPaired = true
        await connectFromUI()
    }

    func saveCustomVehicleName(_ input: String) {
        let value = String(input.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24))
        customVehicleName = value.isEmpty ? nil : value
        let key = AppStorageKeys.customVehicleNamePrefix + vehicleID
        if value.isEmpty { UserDefaults.standard.removeObject(forKey: key) }
        else { UserDefaults.standard.set(value, forKey: key) }
    }

    func setFaceIDProtection(_ value: FaceIDProtection) {
        faceIDProtection = value
        UserDefaults.standard.set(value.rawValue, forKey: AppStorageKeys.faceIDProtectionPrefix + vehicleID)
    }

    func saveScene(_ scene: AutomationScene) {
        if let index = automationScenes.firstIndex(where: { $0.id == scene.id }) { automationScenes[index] = scene }
        else { automationScenes.append(scene) }
        persistScenes()
    }

    func setAlertPreferences(_ preferences: VehicleAlertPreferences) {
        alertPreferences = preferences
        if let data = try? JSONEncoder().encode(preferences) {
            UserDefaults.standard.set(data, forKey: AppStorageKeys.alertPreferencesPrefix + vehicleID)
        }
    }

    func deleteScenes(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) { automationScenes.remove(at: index) }
        persistScenes()
    }

    func runScene(_ scene: AutomationScene) async {
        let containsSensitive = scene.actions.contains(.unlock)
        if faceIDProtection == .all || (faceIDProtection == .sensitive && containsSensitive) {
            guard await authenticateVehicleControl(reason: "确认执行场景“\(scene.name)”") else { return }
        }
        authorizedCommandBatchActive = true
        defer { authorizedCommandBatchActive = false }
        for action in scene.actions {
            guard phase == .connected || executingAction != nil else { break }
            switch action {
            case .unlock: await unlock()
            case .lock: await lock()
            case .climate: if !isClimateOn { await toggleClimate() }
            case .defrost: if !isDefrostOn { await toggleDefrost() }
            case .sentry: if isSentryAvailable && !isSentryOn { await toggleSentryMode() }
            }
        }
    }

    func refreshSchedules() async {
        guard !isRefreshingVehicleState, !isRefreshingMediaState,
              let tesla = try? await ensureModernSession() else { return }
        isRefreshingVehicleState = true
        defer { isRefreshingVehicleState = false }
        if let location = await requestVehicleData(from: tesla, configure: { $0.getLocationState = CarServer_GetLocationState() }), location.hasLocationState {
            let state = location.locationState
            if state.optionalLatitude != nil { scheduleLatitude = state.latitude }
            if state.optionalLongitude != nil { scheduleLongitude = state.longitude }
            if state.optionalLocationName != nil { scheduleLocationName = state.locationName }
        }
        var result: [VehicleSchedule] = []
        if let data = await requestVehicleData(from: tesla, configure: { $0.getChargeScheduleState = CarServer_GetChargeScheduleState() }), data.hasChargeScheduleState {
            result += data.chargeScheduleState.chargeSchedules.map {
                VehicleSchedule(id: $0.id, kind: .charging, name: $0.name, minutes: Int($0.startTime), days: $0.daysOfWeek, enabled: $0.enabled)
            }
        }
        if let data = await requestVehicleData(from: tesla, configure: { $0.getPreconditioningScheduleState = CarServer_GetPreconditioningScheduleState() }), data.hasPreconditioningScheduleState {
            result += data.preconditioningScheduleState.preconditionSchedules.map {
                VehicleSchedule(id: $0.id, kind: .preconditioning, name: $0.name, minutes: Int($0.preconditionTime), days: $0.daysOfWeek, enabled: $0.enabled)
            }
        }
        vehicleSchedules = result
    }

    func addSchedule(kind: ScheduleKind, name: String, date: Date, days: Int32) async {
        guard let latitude = scheduleLatitude, let longitude = scheduleLongitude else {
            presentError("车辆尚未返回当前位置，无法创建位置绑定的预约。请唤醒车辆后刷新。")
            return
        }
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        let minutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        let identifier = UInt64(Date().timeIntervalSince1970 * 1000)
        let succeeded = await execute(.charging, name: "添加预约") {
            try await self.performModern { vehicle in
                var action = CarServer_VehicleAction()
                if kind == .charging {
                    var schedule = CarServer_ChargeSchedule()
                    schedule.id = identifier; schedule.name = name; schedule.daysOfWeek = days
                    schedule.startEnabled = true; schedule.startTime = Int32(minutes); schedule.enabled = true
                    schedule.latitude = latitude; schedule.longitude = longitude
                    action.addChargeScheduleAction = schedule
                } else {
                    var schedule = CarServer_PreconditionSchedule()
                    schedule.id = identifier; schedule.name = name; schedule.daysOfWeek = days
                    schedule.preconditionTime = Int32(minutes); schedule.enabled = true
                    schedule.latitude = latitude; schedule.longitude = longitude
                    action.addPreconditionScheduleAction = schedule
                }
                try await self.send(action, to: vehicle)
            }
        }
        if succeeded { await refreshSchedules() }
    }

    func removeSchedule(_ schedule: VehicleSchedule) async {
        let succeeded = await execute(.charging, name: "删除预约") {
            try await self.performModern { vehicle in
                var action = CarServer_VehicleAction()
                if schedule.kind == .charging {
                    var remove = CarServer_RemoveChargeScheduleAction(); remove.id = schedule.id
                    action.removeChargeScheduleAction = remove
                } else {
                    var remove = CarServer_RemovePreconditionScheduleAction(); remove.id = schedule.id
                    action.removePreconditionScheduleAction = remove
                }
                try await self.send(action, to: vehicle)
            }
        }
        if succeeded { await refreshSchedules() }
    }

    func refreshNearbyChargingSites() async {
        guard !isRefreshingVehicleState, !isRefreshingMediaState,
              let tesla = try? await ensureModernSession() else { return }
        isRefreshingVehicleState = true
        defer { isRefreshingVehicleState = false }
        do {
            try? await tesla.wakeVehicle(); try await tesla.startInfotainmentSession()
            let response = try await tesla.getNearbyChargingSites(radius: 200, count: 20)
            nearbyChargingSites = response.superchargers.map {
                ChargingSite(id: $0.id, name: $0.name, address: [$0.streetAddress, $0.city].filter { !$0.isEmpty }.joined(separator: " · "),
                             distanceKilometers: Double($0.distanceMiles) * 1.609344,
                             availableStalls: Int($0.availableStalls), totalStalls: Int($0.totalStalls),
                             maxPowerKilowatts: Int($0.maxPowerKw), closed: $0.siteClosed)
            }.sorted { $0.distanceKilometers < $1.distanceKilometers }
        } catch { presentError(Self.describe(error)) }
    }

    func vehicleDisplayName(for identifier: String) -> String {
        if let name = UserDefaults.standard.string(forKey: AppStorageKeys.customVehicleNamePrefix + identifier), !name.isEmpty { return name }
        if let model = UserDefaults.standard.string(forKey: AppStorageKeys.vehicleModelPrefix + identifier) { return "Tesla \(model)" }
        return "Tesla · \(String(identifier.dropLast().suffix(4)).uppercased())"
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
        vehicleModelName = UserDefaults.standard.string(forKey: AppStorageKeys.vehicleModelPrefix + vehicleID)
        customVehicleName = UserDefaults.standard.string(forKey: AppStorageKeys.customVehicleNamePrefix + vehicleID)
        faceIDProtection = Self.storedFaceIDProtection(for: vehicleID)
        automationScenes = Self.loadScenes(for: vehicleID)
        alertPreferences = Self.loadAlertPreferences(for: vehicleID)
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
        AppDiagnostics.shared.record("ble.connect.begin")
        phase = .connecting
        let key = try keyStore.load(for: vehicleID)
        let vin = cachedVIN()
        let usesModernCommands = vin?.count == 17
        // The command transport and native Phone Key transport have distinct
        // receive streams. Sharing one dispatcher lets replies race each
        // other and a modern command session is not passive-key presence.
        // Command replies and handle-pull authentication challenges must never
        // share an iterator. The passive Phone Key gets its own restorable BLE
        // link even when commands use the VIN-free legacy protocol.
        let link = try BLEConnection(localName: vehicleID)
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
        if let cachedVIN = vin, usesModernCommands {
            try await startModernSession(on: link, key: key, vin: cachedVIN)
            handshakeTimeoutTask?.cancel()
            handshakeTimeoutTask = nil
            guard !handshakeDidTimeOut else { throw LocalError.handshakeTimedOut }
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
        if managesPassiveKey, passiveEntryEnabled, !passiveKeyOnline {
            do { try await recoverDedicatedPhoneKey() }
            catch {
                passiveKeyOnline = false
                schedulePassiveKeyReconnect()
            }
        }
        phase = .connected
        AppDiagnostics.shared.record("ble.connect.ready")
        await refreshVehicleState()
    }

    func connectFromUI() async {
        guard !foregroundConnectionInProgress else { return }
        foregroundConnectionInProgress = true
        defer { foregroundConnectionInProgress = false }
        do {
            try await connect()
        } catch let error as TeslaError {
            guard !appIsBackgrounded else { return }
            switch error {
            case .bluetoothUnavailable, .bluetoothUnsupported:
                // CoreBluetooth can transiently publish an unavailable state
                // while iOS restores a suspended central. Recreate the link
                // once after the state transition instead of claiming that a
                // modern iPhone lacks BLE hardware.
                disconnect()
                try? await Task.sleep(for: .milliseconds(800))
                do { try await connect() }
                catch { presentError(Self.describe(error)) }
            default:
                presentError(Self.describe(error))
            }
        } catch {
            guard !appIsBackgrounded else { return }
            presentError(Self.describe(error))
        }
    }

    /// iOS may suspend BLE work while the app is in the background. Refresh
    /// immediately on return, or rebuild the session if restoration left the
    /// controller disconnected.
    func refreshAfterReturningToForeground() async {
        appIsBackgrounded = false
        AppDiagnostics.shared.record("app.scene.active")
        guard isPaired else { return }
        if commandConnectionPausedForBackground, let link = connection {
            commandConnectionPausedForBackground = false
            await restoreCommandConnection(on: link)
            if managesPassiveKey, passiveEntryEnabled, !passiveKeyOnline {
                try? await recoverDedicatedPhoneKey()
            }
            return
        }
        switch phase {
        case .connected:
            guard sessionNeedsForegroundValidation else { await refreshVehicleState(); return }
            sessionNeedsForegroundValidation = false
            // Block media polling and user commands while the authenticated
            // dispatcher is being validated. MainActor is re-entrant at every
            // await, so leaving phase as connected permits reply-stream races.
            phase = .handshaking
            if let tesla {
                do {
                    // A restored CoreBluetooth link can still leave the phone
                    // key grey in the vehicle until VCSEC receives an
                    // authenticated request. Wake is the only side-effect-free
                    // request that also makes the key immediately present.
                    try await activatePhoneKeySession(tesla)
                    if managesPassiveKey, passiveEntryEnabled, !passiveKeyOnline {
                        do { try await recoverDedicatedPhoneKey() }
                        catch {
                            passiveKeyOnline = false
                            schedulePassiveKeyReconnect()
                        }
                    }
                    phase = .connected
                    await refreshVehicleState()
                } catch {
                    disconnect()
                    await connectFromUI()
                }
            } else {
                // VIN-free legacy sessions cannot be health-checked without
                // consuming a command response. Rebuild after suspension.
                disconnect()
                await connectFromUI()
            }
        case .idle, .failed:
            await connectFromUI()
        default:
            break
        }
    }

    func noteAppMovedToBackground() {
        appIsBackgrounded = true
        AppDiagnostics.shared.record("app.scene.background")
        sessionNeedsForegroundValidation = true
        // CoreBluetooth keeps the outstanding restoration connection. A
        // periodic retry loop while iOS is backgrounded can accumulate timed
        // out continuations and lead to watchdog/jetsam termination.
        passiveReconnectTask?.cancel()
        passiveReconnectTask = nil
        // The VCSEC command channel is not required for a door-handle
        // challenge. Releasing it leaves the vehicle's limited BLE capacity
        // to the restorable native Phone Key link, which is the only session
        // that must survive in the background.
        guard managesPassiveKey, passiveEntryEnabled, connection != nil else { return }
        commandConnectionPausedForBackground = true
        tesla?.disconnect()
        legacyClient?.close()
        tesla = nil
        legacyClient = nil
        phase = .idle
        AppDiagnostics.shared.record("ble.command.paused.background")
    }

    func presentUserError(_ message: String) { presentError(message) }

    func setPassiveEntryEnabled(_ enabled: Bool) async {
        guard managesPassiveKey else { return }
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
        if await execute(.lock, name: "上锁", operation: { try await self.perform(modern: { try await $0.lock() }, legacy: { try await $0.rke(1) }) }) {
            isLocked = true
            await refreshBasicVehicleState()
        }
    }
    func unlock() async {
        if await execute(.unlock, name: "解锁", operation: { try await self.perform(modern: { try await $0.unlock() }, legacy: { try await $0.rke(0) }) }) {
            isLocked = false
            await refreshBasicVehicleState()
        }
    }
    func openTrunk() async {
        guard !isTrunkMoving else { return }
        if await execute(.trunk, name: "开启后备箱", operation: {
            try await self.perform(modern: { try await $0.openTrunk() }, legacy: { try await $0.rke(2) })
        }) {
            isTrunkOpen = true
            isTrunkMoving = true
            trunkOperationStatus = "正在打开"
            scheduleTrunkStateRefresh()
        }
    }
    func closeTrunk() async {
        guard !isTrunkMoving else { return }
        if await execute(.trunk, name: "关闭后备箱", operation: {
            try await self.perform(modern: { try await $0.closeTrunk() }, legacy: { try await $0.closure(field: 5, action: 4) })
        }) {
            isTrunkMoving = true
            trunkOperationStatus = "正在关闭"
            scheduleTrunkStateRefresh()
        }
    }
    func openFrunk() async {
        if await execute(.frunk, name: "开启前备箱", operation: { try await self.perform(modern: { try await $0.openFrunk() }, legacy: { try await $0.rke(3) }) }) {
            await refreshBasicVehicleState()
        }
    }
    func flashLights() async { await execute(.flash, name: "闪灯") { try await self.performInfotainment { try await $0.flashLights() } } }
    func honk() async { await execute(.horn, name: "鸣笛") { try await self.performInfotainment { try await $0.honkHorn() } } }
    func authorizeDrive() async {
        await execute(.drive, name: "启动车辆") {
            try await self.performModern { vehicle in
                do {
                    try await vehicle.remoteDrive()
                } catch where Self.isVCSECAlreadyOn(error) {
                    // Remote-drive authorization is idempotent. Tesla returns
                    // genericerrorAlreadyOn when the grant is already active;
                    // that is the requested end state, not an operation error.
                }
            }
        }
    }

    func toggleChargePort() async {
        let opening = !isChargePortOpen
        if await execute(.chargePort, name: opening ? "打开充电口" : "关闭充电口", operation: {
            try await self.performInfotainment { vehicle in
                if opening { try await vehicle.openChargePort() }
                else { try await vehicle.closeChargePort() }
            }
        }) {
            isChargePortOpen = opening
            await refreshChargeState()
        }
    }

    func toggleCharging() async {
        let starting = !isCharging
        if await execute(.charging, name: starting ? "开始充电" : "停止充电", operation: {
            try await self.performInfotainment { vehicle in
                if starting { try await vehicle.startCharging() }
                else { try await vehicle.stopCharging() }
            }
        }) {
            isCharging = starting
            chargingStatus = starting ? "正在开始充电" : "充电已停止"
            await refreshChargeState(after: .milliseconds(500))
        }
    }

    func setChargeLimit(_ percent: Int) async {
        let value = min(max(percent, minimumChargeLimit), maximumChargeLimit)
        if await execute(.chargeLimit, name: "设置充电上限", operation: {
            try await self.performInfotainment { try await $0.setChargeLimit(percent: Int32(value)) }
        }) {
            chargeLimit = value
            await refreshChargeState()
        }
    }

    func setChargingCurrent(_ amps: Int) async {
        let value = min(max(amps, 1), maxChargingCurrentAmps ?? 48)
        if await execute(.chargeCurrent, name: "设置充电电流", operation: {
            try await self.performInfotainment { try await $0.setChargingAmps(Int32(value)) }
        }) {
            chargerCurrentAmps = value
            await refreshChargeState()
        }
    }

    func toggleClimate() async {
        let turningOn = !isClimateOn
        if await execute(.climate, name: turningOn ? "打开空调" : "关闭空调", operation: {
            try await self.performInfotainment { try await $0.setClimateAuto(enabled: turningOn) }
        }) {
            isClimateOn = turningOn
            await refreshClimateState(after: .milliseconds(500))
        }
    }

    func setCabinTemperature(_ celsius: Double) async {
        let target = min(max(celsius, minimumCabinTemperature), maximumCabinTemperature)
        if await execute(.climate, name: "设置温度", operation: {
            try await self.performInfotainment { try await $0.setTemperature(driverCelsius: Float(target), passengerCelsius: Float(target)) }
        }) {
            targetTemperature = target
            await refreshClimateState()
        }
    }

    func toggleDefrost() async {
        let enabled = !isDefrostOn
        if await execute(.defrost, name: enabled ? "开启最大除霜" : "关闭最大除霜", operation: {
            try await self.performInfotainment { try await $0.setPreconditioningMax(enabled: enabled) }
        }) {
            isDefrostOn = enabled
            await refreshClimateState()
        }
    }

    func toggleSteeringWheelHeater() async {
        let enabled = !isSteeringWheelHeaterOn
        if await execute(.steeringHeater, name: enabled ? "开启方向盘加热" : "关闭方向盘加热", operation: {
            try await self.performInfotainment { try await $0.setSteeringWheelHeater(enabled: enabled) }
        }) {
            isSteeringWheelHeaterOn = enabled
            await refreshClimateState()
        }
    }

    func setClimateKeeper(_ mode: String) async {
        let protocolMode: CarServer_HvacClimateKeeperAction.ClimateKeeperAction_E = switch mode {
        case "保持": .climateKeeperActionOn
        case "爱犬": .climateKeeperActionDog
        case "露营": .climateKeeperActionCamp
        default: .climateKeeperActionOff
        }
        if await execute(.climateMode, name: "设置\(mode)模式", operation: {
            try await self.performInfotainment { try await $0.setClimateKeeper(mode: protocolMode) }
        }) {
            climateKeeperMode = mode
            await refreshClimateState()
        }
    }

    func toggleBioweaponMode() async {
        let enabled = !isBioweaponModeOn
        if await execute(.bioweapon, name: enabled ? "开启生化防御" : "关闭生化防御", operation: {
            try await self.performInfotainment { try await $0.setBioweaponMode(enabled: enabled) }
        }) {
            isBioweaponModeOn = enabled
            await refreshClimateState()
        }
    }

    func toggleCabinOverheatProtection() async {
        let enabled = !isCabinOverheatProtectionOn
        if await execute(.overheat, name: enabled ? "开启座舱过热保护" : "关闭座舱过热保护", operation: {
            try await self.performInfotainment { try await $0.setCabinOverheatProtection(enabled: enabled) }
        }) {
            isCabinOverheatProtectionOn = enabled
            await refreshClimateState()
        }
    }

    func toggleSentryMode() async {
        guard isSentryAvailable else {
            presentError("当前车辆没有提供哨兵模式能力。")
            return
        }
        let enabled = !isSentryOn
        if await execute(.sentry, name: enabled ? "开启哨兵模式" : "关闭哨兵模式", operation: {
            try await self.performInfotainment { try await $0.setSentryMode(enabled: enabled) }
        }) {
            isSentryOn = enabled
            await refreshClosuresState()
        }
    }

    func toggleWindows() async {
        let venting = !areWindowsVented
        if await execute(.windows, name: venting ? "车窗通风" : "关闭车窗", operation: {
            try await self.performInfotainment { vehicle in
                try await vehicle.controlWindows(venting ? .vent : .close)
            }
        }) {
            areWindowsVented = venting
            await refreshClosuresState(after: .milliseconds(500))
        }
    }

    func previousMediaTrack() async {
        if await execute(.mediaPrevious, name: "切换上一首", operation: {
            try await self.performInfotainment { try await $0.mediaPreviousTrack() }
        }) { await refreshMediaAfterTrackChange() }
    }

    func toggleMediaPlayback() async {
        if await execute(.mediaPlayPause, name: mediaPlaybackStatus == "播放中" ? "暂停播放" : "继续播放", operation: {
            try await self.performInfotainment { try await $0.mediaTogglePlayback() }
        }) {
            mediaPlaybackStatus = mediaPlaybackStatus == "播放中" ? "已暂停" : "播放中"
            await refreshMediaAfterTrackChange()
        }
    }

    func nextMediaTrack() async {
        if await execute(.mediaNext, name: "切换下一首", operation: {
            try await self.performInfotainment { try await $0.mediaNextTrack() }
        }) { await refreshMediaAfterTrackChange() }
    }

    private func refreshMediaAfterTrackChange() async {
        try? await Task.sleep(for: .milliseconds(450))
        await refreshMediaState()
    }

    /// Media changes made on the center display are not pushed over the BLE
    /// protocol. Poll only the two small media payloads while the app is active.
    func refreshMediaState() async {
        guard !isRefreshingVehicleState, !isRefreshingMediaState,
              phase == .connected, executingAction == nil, let tesla else { return }
        isRefreshingMediaState = true
        defer { isRefreshingMediaState = false }
        if let data = await requestVehicleData(from: tesla, configure: { $0.getMediaState = CarServer_GetMediaState() }),
           data.hasMediaState { apply(data.mediaState) }
        if let details = await requestVehicleData(from: tesla, configure: { $0.getMediaDetailState = CarServer_GetMediaDetailState() }),
           details.hasMediaDetailState { apply(details.mediaDetailState) }
    }

    func refreshVehicleState() async {
        // The BLE dispatcher is request/response based. Do not let the
        // two-second media poll or a second pull-to-refresh interleave with a
        // full state refresh, otherwise receivers can wait on each other.
        guard !isRefreshingVehicleState, !isRefreshingMediaState, executingAction == nil,
              phase == .connected else { return }
        isRefreshingVehicleState = true
        defer { isRefreshingVehicleState = false }
        await refreshBasicVehicleState()
        guard let tesla else {
            lastStateUpdate = .now
            WatchBridge.shared.publish(name: displayVehicleName, battery: batteryLevel, range: estimatedRangeKilometers, locked: isLocked)
            return
        }
        availableSoftwareVersion = nil
        softwareUpdateStatus = nil
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
        WatchBridge.shared.publish(name: displayVehicleName, battery: batteryLevel, range: estimatedRangeKilometers, locked: isLocked)
        await VehicleAlertManager.evaluate(vehicleID: vehicleID, name: displayVehicleName, preferences: alertPreferences,
                                           battery: batteryLevel, openDoors: openDoorCount, openWindows: openWindowCount,
                                           chargingStatus: chargingStatus)
    }

    private func requestVehicleData(
        from vehicle: TeslaVehicle,
        configure: (inout CarServer_GetVehicleData) -> Void
    ) async -> CarServer_VehicleData? {
        var request = CarServer_GetVehicleData()
        configure(&request)
        var action = CarServer_VehicleAction()
        action.getVehicleData = request
        guard let response = try? await vehicle.sendVehicleAction(action, retryOnFailure: false),
              case .vehicleData(let data)? = response.responseMsg else { return nil }
        return data
    }

    private func refreshBasicVehicleState() async {
        let ownsRefreshLock = !isRefreshingVehicleState
        if ownsRefreshLock {
            guard !isRefreshingMediaState else { return }
            isRefreshingVehicleState = true
        }
        defer { if ownsRefreshLock { isRefreshingVehicleState = false } }
        if let tesla, let status = try? await tesla.vehicleStatus() {
            applyRearTrunkState(status.closureStatuses.rearTrunk)
            if let value = Self.isOpen(status.closureStatuses.frontTrunk) { isFrunkOpen = value }
            if let value = Self.isOpen(status.closureStatuses.chargePort) { isChargePortOpen = value }
            isLocked = status.vehicleLockState == .vehiclelockstateLocked
                || status.vehicleLockState == .vehiclelockstateInternalLocked
            vehicleSleepStatus = switch status.vehicleSleepStatus {
            case .vehicleSleepStatusAwake: "已唤醒"
            case .vehicleSleepStatusAsleep: "休眠"
            default: "状态未知"
            }
        } else if let legacyClient, let status = try? await legacyClient.vehicleStatus() {
            if let rearTrunk = status.rearTrunk { applyRearTrunkState(rawValue: rearTrunk) }
            if let frontTrunk = status.frontTrunk, let value = Self.isOpen(rawValue: frontTrunk) { isFrunkOpen = value }
            if let chargePort = status.chargePort, let value = Self.isOpen(rawValue: chargePort) { isChargePortOpen = value }
            if let lockState = status.lockState { isLocked = lockState == 1 || lockState == 2 }
            if let sleepState = status.sleepState {
                vehicleSleepStatus = sleepState == 1 ? "已唤醒" : (sleepState == 2 ? "休眠" : "状态未知")
            }
        }
    }

    private func refreshChargeState(after delay: Duration = .zero) async {
        guard !isRefreshingVehicleState, !isRefreshingMediaState, let tesla else { return }
        isRefreshingVehicleState = true
        defer { isRefreshingVehicleState = false }
        if delay > .zero { try? await Task.sleep(for: delay) }
        if let data = await requestVehicleData(from: tesla, configure: { $0.getChargeState = CarServer_GetChargeState() }),
           data.hasChargeState { apply(data.chargeState) }
        lastStateUpdate = .now
    }

    private func refreshClimateState(after delay: Duration = .zero) async {
        guard !isRefreshingVehicleState, !isRefreshingMediaState, let tesla else { return }
        isRefreshingVehicleState = true
        defer { isRefreshingVehicleState = false }
        if delay > .zero { try? await Task.sleep(for: delay) }
        if let data = await requestVehicleData(from: tesla, configure: { $0.getClimateState = CarServer_GetClimateState() }),
           data.hasClimateState { apply(data.climateState) }
        lastStateUpdate = .now
    }

    private func refreshClosuresState(after delay: Duration = .zero) async {
        guard !isRefreshingVehicleState, !isRefreshingMediaState, let tesla else { return }
        isRefreshingVehicleState = true
        defer { isRefreshingVehicleState = false }
        if delay > .zero { try? await Task.sleep(for: delay) }
        if let data = await requestVehicleData(from: tesla, configure: { $0.getClosuresState = CarServer_GetClosuresState() }),
           data.hasClosuresState { apply(data.closuresState) }
        lastStateUpdate = .now
    }

    private func scheduleTrunkStateRefresh() {
        trunkStateRefreshTask?.cancel()
        trunkStateRefreshTask = Task { [weak self] in
            for delay in [500, 1_500, 3_000, 5_000] {
                try? await Task.sleep(for: .milliseconds(delay))
                guard let self, !Task.isCancelled else { return }
                await self.refreshBasicVehicleState()
                if !self.isTrunkMoving { return }
            }
            let wasClosing = self?.trunkOperationStatus == "正在关闭"
            self?.isTrunkMoving = false
            self?.trunkOperationStatus = wasClosing ? "车辆未确认关闭" : "状态待确认"
        }
    }

    private func applyRearTrunkState(_ state: VCSEC_ClosureState_E) {
        applyRearTrunkState(rawValue: UInt64(clamping: state.rawValue))
    }

    private func applyRearTrunkState(rawValue: UInt64) {
        switch rawValue {
        case 0:
            isTrunkOpen = false; isTrunkMoving = false; trunkOperationStatus = nil
        case 1:
            isTrunkOpen = true; isTrunkMoving = false; trunkOperationStatus = nil
        case 2:
            isTrunkOpen = true; isTrunkMoving = false; trunkOperationStatus = "后备箱半开"
        case 4:
            isTrunkOpen = false; isTrunkMoving = false; trunkOperationStatus = "无法解锁"
        case 5:
            isTrunkOpen = true; isTrunkMoving = true; trunkOperationStatus = "正在打开"
        case 6:
            isTrunkOpen = true; isTrunkMoving = true; trunkOperationStatus = "正在关闭"
        default:
            isTrunkMoving = false; trunkOperationStatus = "状态未知"
        }
    }

    private func apply(_ state: CarServer_ChargeState) {
        if state.optionalBatteryLevel != nil { batteryLevel = Int(state.batteryLevel) }
        if state.optionalBatteryRange != nil { estimatedRangeKilometers = Double(state.batteryRange) * 1.609344 }
        if state.optionalChargeLimitSoc != nil { chargeLimit = Int(state.chargeLimitSoc) }
        if state.optionalChargeLimitSocMin != nil { minimumChargeLimit = Int(state.chargeLimitSocMin) }
        if state.optionalChargeLimitSocMax != nil { maximumChargeLimit = Int(state.chargeLimitSocMax) }
        if maximumChargeLimit < minimumChargeLimit {
            minimumChargeLimit = 50
            maximumChargeLimit = 100
        }
        if state.optionalChargerPower != nil { chargerPowerKilowatts = Int(state.chargerPower) }
        if state.optionalChargerVoltage != nil { chargerVoltage = Int(state.chargerVoltage) }
        if state.optionalChargerActualCurrent != nil { chargerCurrentAmps = Int(state.chargerActualCurrent) }
        if state.optionalChargeCurrentRequestMax != nil { maxChargingCurrentAmps = Int(state.chargeCurrentRequestMax) }
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
            isCharging = switch state.chargingState.type {
            case .charging?, .starting?: true
            default: false
            }
            if !isCharging {
                if state.optionalChargerPower == nil { chargerPowerKilowatts = 0 }
                if state.optionalChargerActualCurrent == nil { chargerCurrentAmps = 0 }
                if state.optionalMinutesToChargeLimit == nil { minutesToChargeLimit = nil }
            }
        }
    }

    private func apply(_ state: CarServer_ClimateState) {
        if state.optionalIsClimateOn != nil { isClimateOn = state.isClimateOn }
        if state.optionalInsideTempCelsius != nil { cabinTemperature = Double(state.insideTempCelsius) }
        if state.optionalOutsideTempCelsius != nil { outsideTemperature = Double(state.outsideTempCelsius) }
        if state.optionalDriverTempSetting != nil { targetTemperature = Double(state.driverTempSetting) }
        if state.optionalMinAvailTempCelsius != nil { minimumCabinTemperature = Double(state.minAvailTempCelsius) }
        if state.optionalMaxAvailTempCelsius != nil { maximumCabinTemperature = Double(state.maxAvailTempCelsius) }
        if maximumCabinTemperature < minimumCabinTemperature {
            minimumCabinTemperature = 15
            maximumCabinTemperature = 28
        }
        if state.hasDefrostMode {
            isDefrostOn = switch state.defrostMode.type {
            case .max?: true
            default: false
            }
        }
        if state.optionalSteeringWheelHeater != nil { isSteeringWheelHeaterOn = state.steeringWheelHeater }
        if state.optionalBioweaponModeOn != nil { isBioweaponModeOn = state.bioweaponModeOn }
        if state.optionalCabinOverheatProtection != nil {
            isCabinOverheatProtectionOn = state.cabinOverheatProtection != .cabinOverheatProtectionOff
        }
        if state.hasClimateKeeperMode {
            climateKeeperMode = switch state.climateKeeperMode.type {
            case .on?: "保持"
            case .dog?: "爱犬"
            case .party?: "露营"
            default: "关闭"
            }
        }
    }

    private func apply(_ state: CarServer_ClosuresState) {
        if state.optionalSentryModeAvailable != nil {
            isSentryAvailable = state.sentryModeAvailable
        }
        if state.hasSentryModeState {
            isSentryOn = switch state.sentryModeState.type {
            case .off?, nil: false
            default: true
            }
        }
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
        if windowValues.contains(where: { $0.0 }) { areWindowsVented = windowValues.contains { $0.0 && $0.1 } }
        windowStates = [:]
        if state.optionalWindowOpenDriverFront != nil { windowStates["左前窗"] = state.windowOpenDriverFront }
        if state.optionalWindowOpenDriverRear != nil { windowStates["左后窗"] = state.windowOpenDriverRear }
        if state.optionalWindowOpenPassengerFront != nil { windowStates["右前窗"] = state.windowOpenPassengerFront }
        if state.optionalWindowOpenPassengerRear != nil { windowStates["右后窗"] = state.windowOpenPassengerRear }
        if state.optionalDoorOpenTrunkFront != nil { isFrunkOpen = state.doorOpenTrunkFront }
        if state.optionalDoorOpenTrunkRear != nil, !isTrunkMoving { isTrunkOpen = state.doorOpenTrunkRear }
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
        if state.optionalNowPlayingTitle != nil {
            let newTitle = state.nowPlayingTitle.nilIfEmpty
            mediaTitle = newTitle
        }
        if state.optionalNowPlayingArtist != nil { mediaArtist = state.nowPlayingArtist.nilIfEmpty }
        if state.optionalMediaPlaybackStatus != nil {
            mediaPlaybackStatus = switch state.mediaPlaybackStatus {
            case .playing: "播放中"
            case .paused: "已暂停"
            case .stopped: "已停止"
            default: "状态未知"
            }
        }
        refreshMediaArtworkIfNeeded()
    }

    private func refreshMediaArtworkIfNeeded() {
        guard let title = mediaTitle, !title.isEmpty else {
            mediaArtworkLookupTask?.cancel()
            mediaArtworkURL = nil
            lastArtworkLookupKey = nil
            return
        }
        let key = "\(title.lowercased())|\(mediaArtist?.lowercased() ?? "")"
        guard key != lastArtworkLookupKey else { return }
        lastArtworkLookupKey = key
        mediaArtworkURL = nil
        mediaArtworkLookupTask?.cancel()
        let artist = mediaArtist
        mediaArtworkLookupTask = Task { [weak self] in
            let url = await MediaArtworkLookup.artworkURL(title: title, artist: artist)
            guard !Task.isCancelled, self?.lastArtworkLookupKey == key else { return }
            self?.mediaArtworkURL = url
        }
    }

    private func apply(_ state: CarServer_MediaDetailState) {
        if state.optionalNowPlayingAlbum != nil { mediaAlbum = state.nowPlayingAlbum.nilIfEmpty }
        if state.optionalNowPlayingSourceString != nil { mediaSource = state.nowPlayingSourceString.nilIfEmpty }
        if mediaSource == nil, state.optionalA2DpSourceName != nil { mediaSource = state.a2DpSourceName.nilIfEmpty }
    }

    func disconnect() {
        intentionalDisconnect = true
        passiveReconnectTask?.cancel()
        passiveReconnectTask = nil
        handshakeTimeoutTask?.cancel()
        handshakeTimeoutTask = nil
        trunkStateRefreshTask?.cancel()
        trunkStateRefreshTask = nil
        tesla?.disconnect()
        legacyClient?.close()
        passiveKeyClient?.close()
        pendingPairing?.connection.close()
        connection?.close()
        passiveConnection?.close()
        pendingPairing = nil
        canConfirmPairing = false
        tesla = nil
        legacyClient = nil
        passiveKeyClient = nil
        connection = nil
        passiveConnection = nil
        passiveKeyOnline = false
        phase = .idle
    }

    private func restoreCommandConnection(on link: BLEConnection) async {
        guard connection === link, !appIsBackgrounded else { return }
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

    private func startDedicatedPhoneKeyConnection(key: TeslaPrivateKey) async throws {
        guard managesPassiveKey else { return }
        if passiveKeyOnline { return }
        passiveKeyClient?.close()
        passiveConnection?.close()
        passiveKeyClient = nil
        passiveConnection = nil
        passiveKeyOnline = false

        let restorationID = "com.local.teslablekey.phonekey.\(vehicleID)"
        let link = try BLEConnection(localName: vehicleID, restorationIdentifier: restorationID)
        passiveConnection = link
        do {
            try await link.connect(timeout: 30)
            let client = LegacyVCSECClient(connection: link, privateKey: key)
            try await client.startSession()
            client.startPassiveAuthenticationResponder()
            passiveKeyClient = client
            passiveKeyOnline = true
        } catch {
            // Keep the restorable central alive: iOS can complete its pending
            // connection and wake the app when the owner returns to the car.
            throw error
        }
    }

    private func bootstrapPassivePhoneKey() async {
        guard managesPassiveKey, passiveEntryEnabled, isPaired, !vehicleID.isEmpty,
              passiveConnection == nil, !passiveKeyOnline else { return }
        do {
            let key = try keyStore.load(for: vehicleID)
            try await startDedicatedPhoneKeyConnection(key: key)
            AppDiagnostics.shared.record("ble.passive.bootstrap.ready")
        } catch {
            AppDiagnostics.shared.record("ble.passive.bootstrap.pending")
        }
    }

    private func restoreDedicatedPhoneKeyConnection(on link: BLEConnection) async {
        guard managesPassiveKey, passiveEntryEnabled, passiveConnection === link,
              !passiveRecoveryInProgress else { return }
        passiveRecoveryInProgress = true
        AppDiagnostics.shared.record("ble.passive.restore.begin")
        defer { passiveRecoveryInProgress = false }
        passiveKeyClient?.stopPassiveAuthenticationResponder()
        passiveKeyClient = nil
        passiveKeyOnline = false
        do {
            try await link.connect(timeout: 45)
            let key = try keyStore.load(for: vehicleID)
            let client = LegacyVCSECClient(connection: link, privateKey: key)
            try await client.startSession()
            guard passiveConnection === link else { client.close(); return }
            client.startPassiveAuthenticationResponder()
            passiveKeyClient = client
            passiveKeyOnline = true
            AppDiagnostics.shared.record("ble.passive.restore.ready")
        } catch {
            AppDiagnostics.shared.record("ble.passive.restore.failed")
            // Keep this CBCentralManager alive. Replacing it with another
            // manager using the same restoration identifier can strand iOS
            // in a permanent "restoring" state until the app is terminated.
            schedulePassiveKeyReconnect()
        }
    }

    private func recoverDedicatedPhoneKey() async throws {
        guard managesPassiveKey else { return }
        if let existingLink = passiveConnection {
            await restoreDedicatedPhoneKeyConnection(on: existingLink)
            guard passiveKeyOnline else { throw LocalError.handshakeTimedOut }
        } else {
            let key = try keyStore.load(for: vehicleID)
            try await startDedicatedPhoneKeyConnection(key: key)
        }
    }

    private func schedulePassiveKeyReconnect() {
        guard managesPassiveKey, passiveEntryEnabled, isPaired, !passiveKeyOnline,
              !appIsBackgrounded, passiveReconnectTask == nil else { return }
        passiveReconnectTask = Task { [weak self] in
            defer { self?.passiveReconnectTask = nil }
            try? await Task.sleep(for: .seconds(5))
            guard let self, !Task.isCancelled else { return }
            while self.passiveEntryEnabled, self.isPaired, !self.passiveKeyOnline,
                  !self.appIsBackgrounded, !Task.isCancelled {
                if let existingLink = self.passiveConnection {
                    await self.restoreDedicatedPhoneKeyConnection(on: existingLink)
                    if self.passiveKeyOnline { return }
                } else {
                    do {
                        let key = try self.keyStore.load(for: self.vehicleID)
                        try await self.startDedicatedPhoneKeyConnection(key: key)
                        return
                    } catch { }
                }
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    func forgetVehicle() {
        UserDefaults.standard.removeObject(forKey: AppStorageKeys.vehicleVINPrefix + vehicleID)
        UserDefaults.standard.removeObject(forKey: AppStorageKeys.vehicleModelPrefix + vehicleID)
        UserDefaults.standard.removeObject(forKey: AppStorageKeys.customVehicleNamePrefix + vehicleID)
        UserDefaults.standard.removeObject(forKey: AppStorageKeys.faceIDProtectionPrefix + vehicleID)
        UserDefaults.standard.removeObject(forKey: AppStorageKeys.alertPreferencesPrefix + vehicleID)
        let removedID = vehicleID
        disconnect()
        try? keyStore.delete(for: removedID)
        pairedVehicleIDs.removeAll { $0 == removedID }
        UserDefaults.standard.set(pairedVehicleIDs, forKey: AppStorageKeys.pairedVehicleIDs)
        if let next = pairedVehicleIDs.first {
            vehicleID = next
            vehicleModelName = UserDefaults.standard.string(forKey: AppStorageKeys.vehicleModelPrefix + next)
            customVehicleName = UserDefaults.standard.string(forKey: AppStorageKeys.customVehicleNamePrefix + next)
            faceIDProtection = Self.storedFaceIDProtection(for: next)
            automationScenes = Self.loadScenes(for: next)
            alertPreferences = Self.loadAlertPreferences(for: next)
            UserDefaults.standard.set(next, forKey: AppStorageKeys.pairedVehicleID)
            isPaired = true
            Task { await connectFromUI() }
        } else {
            UserDefaults.standard.removeObject(forKey: AppStorageKeys.pairedVehicleID)
            UserDefaults.standard.removeObject(forKey: AppStorageKeys.paired)
            UserDefaults.standard.removeObject(forKey: AppStorageKeys.pairingSchemaVersion)
            vehicleID = ""
            vehicleModelName = nil
            customVehicleName = nil
            faceIDProtection = .sensitive
            automationScenes = []
            alertPreferences = VehicleAlertPreferences()
            isPaired = false
        }
    }

    @discardableResult
    private func execute(_ action: VehicleAction, name: String, operation: () async throws -> Void) async -> Bool {
        guard tesla != nil || legacyClient != nil else { presentError("请先连接车辆。"); return false }
        // Tesla vehicle commands share one authenticated BLE session. Serialize them
        // so a second command cannot replace the first command's presentation state.
        guard executingAction == nil, !isRefreshingVehicleState, !isRefreshingMediaState,
              phase == .connected else { return false }
        let sensitive = action == .unlock || action == .frunk || action == .trunk || action == .drive
        if !authorizedCommandBatchActive && (faceIDProtection == .all || (faceIDProtection == .sensitive && sensitive)) {
            guard await authenticateVehicleControl(reason: "确认\(name)") else { return false }
        }
        successClearTask?.cancel()
        lastSuccessAction = nil
        executingAction = action
        AppDiagnostics.shared.record("command.\(action.rawValue).begin")
        phase = .executing(name)
        do {
            try await operation()
            appendCommandRecord(name: name, succeeded: true)
            executingAction = nil
            lastSuccessAction = action
            phase = .connected
            AppDiagnostics.shared.record("command.\(action.rawValue).success")
            successClearTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(700))
                guard !Task.isCancelled else { return }
                self?.lastSuccessAction = nil
            }
            return true
        } catch {
            AppDiagnostics.shared.record("command.\(action.rawValue).failed")
            appendCommandRecord(name: name, succeeded: false)
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

    private func authenticateVehicleControl(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            presentError("请先在系统设置中启用 Face ID、Touch ID 或设备密码。")
            return false
        }
        do { return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) }
        catch { return false }
    }

    private func appendCommandRecord(name: String, succeeded: Bool) {
        commandHistory.insert(CommandRecord(id: UUID(), name: name, date: .now, succeeded: succeeded), at: 0)
        commandHistory = Array(commandHistory.prefix(20))
        if let data = try? JSONEncoder().encode(commandHistory) {
            UserDefaults.standard.set(data, forKey: AppStorageKeys.commandHistory)
        }
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

    private func performInfotainment(_ operation: (TeslaVehicle) async throws -> Void) async throws {
        let modernVehicle = try await ensureModernSession()
        try? await modernVehicle.wakeVehicle()
        try await modernVehicle.startInfotainmentSession()
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
        // Starting the cryptographic session alone does not always mark the
        // phone key online on a sleeping vehicle. Send an authenticated wake
        // before exposing the connection as ready to the UI.
        try await activatePhoneKeySession(client)
        tesla = client
    }

    private func activatePhoneKeySession(_ vehicle: TeslaVehicle) async throws {
        do {
            try await vehicle.wakeVehicle()
        } catch {
            // A vehicle may finish waking just after the first BLE response.
            // Retry once on the same authenticated session; do not issue an
            // RKE action such as lock/unlock merely to make the key present.
            try? await Task.sleep(for: .milliseconds(500))
            try await vehicle.wakeVehicle()
        }
    }

    private func presentError(_ message: String) {
        errorMessage = message
        phase = .failed(message)
        showingError = true
    }

    private static func isVCSECAlreadyOn(_ error: Error) -> Bool {
        let diagnostic = "\(String(describing: error)) \(error.localizedDescription)"
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
        return diagnostic.contains("genericerroralreadyon") || diagnostic.contains("alreadyon")
    }

    private func markPairingVerified() {
        UserDefaults.standard.set(true, forKey: AppStorageKeys.paired)
        UserDefaults.standard.set(3, forKey: AppStorageKeys.pairingSchemaVersion)
        isPaired = true
        if !pairedVehicleIDs.contains(vehicleID) { pairedVehicleIDs.append(vehicleID) }
        UserDefaults.standard.set(pairedVehicleIDs, forKey: AppStorageKeys.pairedVehicleIDs)
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

    private static func storedFaceIDProtection(for identifier: String) -> FaceIDProtection {
        FaceIDProtection(rawValue: UserDefaults.standard.string(forKey: AppStorageKeys.faceIDProtectionPrefix + identifier) ?? "") ?? .sensitive
    }

    private static func loadScenes(for identifier: String) -> [AutomationScene] {
        guard !identifier.isEmpty,
              let data = UserDefaults.standard.data(forKey: AppStorageKeys.automationScenesPrefix + identifier),
              let scenes = try? JSONDecoder().decode([AutomationScene].self, from: data) else {
            return [
                AutomationScene(id: UUID(), name: "回家", symbol: "house.fill", actions: [.unlock]),
                AutomationScene(id: UUID(), name: "上班", symbol: "briefcase.fill", actions: [.climate]),
                AutomationScene(id: UUID(), name: "离车", symbol: "figure.walk.departure", actions: [.lock, .sentry]),
                AutomationScene(id: UUID(), name: "冬季预热", symbol: "snowflake", actions: [.climate, .defrost])
            ]
        }
        return scenes
    }

    private func persistScenes() {
        if let data = try? JSONEncoder().encode(automationScenes) {
            UserDefaults.standard.set(data, forKey: AppStorageKeys.automationScenesPrefix + vehicleID)
        }
    }

    private static func loadAlertPreferences(for identifier: String) -> VehicleAlertPreferences {
        guard let data = UserDefaults.standard.data(forKey: AppStorageKeys.alertPreferencesPrefix + identifier),
              let value = try? JSONDecoder().decode(VehicleAlertPreferences.self, from: data) else { return VehicleAlertPreferences() }
        return value
    }

    private static func isOpen(_ state: VCSEC_ClosureState_E) -> Bool? {
        switch state {
        case .closurestateClosed: false
        case .closurestateOpen, .closurestateAjar, .closurestateOpening, .closurestateClosing: true
        case .closurestateUnknown, .closurestateFailedUnlatch, .UNRECOGNIZED: nil
        }
    }

    private static func isOpen(rawValue: UInt64) -> Bool? {
        switch rawValue {
        case 0: false
        case 1, 2, 5, 6: true
        default: nil
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
