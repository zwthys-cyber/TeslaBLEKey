import Foundation
import Observation
import Security
@preconcurrency import TeslaBLEKeyKit

@MainActor
@Observable
final class VehicleController {
    enum VehicleAction: String, CaseIterable, Hashable, Identifiable, Sendable {
        case lock, unlock, frunk, trunk, drive, flash, horn, chargePort, climate, windows
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

    var vehicleID: String
    var isPaired: Bool
    var vehicleModelName: String?
    var phase: Phase = .idle
    var showingError = false
    var errorMessage = ""
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
        if !pairingWasVerified {
            defaults.set(false, forKey: AppStorageKeys.paired)
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
        phase = .connecting
        let key = try keyStore.load(for: vehicleID)
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
        if let cachedVIN = cachedVIN(), cachedVIN.count == 17 {
            try await startModernSession(on: link, key: key, vin: cachedVIN)
        } else {
            let bootstrap = LegacyVCSECClient(connection: link, privateKey: key)
            // Establish the native phone-key session first. VehicleInfo is
            // available on vehicles that expose the full local command stack
            // only after the enrolled key has proved possession.
            try await bootstrap.startSession()
            legacyClient = bootstrap

            if let discoveredVIN = try? await bootstrap.vehicleVIN() {
                cacheVehicleIdentity(vin: discoveredVIN)
                try await startModernSession(on: link, key: key, vin: discoveredVIN)
                legacyClient = nil
            }
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

    func presentUserError(_ message: String) { presentError(message) }

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
    func authorizeDrive() async { await execute(.drive, name: "启动车辆") { try await self.perform(modern: { try await $0.remoteDrive() }, legacy: { try await $0.rke(20) }) } }

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

    func refreshVehicleState() async {
        guard let tesla else { return }
        if let status = try? await tesla.vehicleStatus() {
            isTrunkOpen = status.closureStatuses.rearTrunk != .closurestateClosed
            isChargePortOpen = status.closureStatuses.chargePort != .closurestateClosed
            isLocked = status.vehicleLockState == .vehiclelockstateLocked || status.vehicleLockState == .vehiclelockstateInternalLocked
        }
        try? await tesla.startInfotainmentSession()
        var request = CarServer_GetVehicleData()
        request.getClimateState = CarServer_GetClimateState()
        request.getChargeState = CarServer_GetChargeState()
        var action = CarServer_VehicleAction()
        action.getVehicleData = request
        if let response = try? await tesla.sendVehicleAction(action),
           case .vehicleData(let data)? = response.responseMsg {
            if data.hasClimateState {
                isClimateOn = data.climateState.isClimateOn
                if data.climateState.optionalInsideTempCelsius != nil { cabinTemperature = Double(data.climateState.insideTempCelsius) }
                if data.climateState.optionalDriverTempSetting != nil { targetTemperature = Double(data.climateState.driverTempSetting) }
            }
            if data.hasChargeState { isChargePortOpen = data.chargeState.chargePortDoorOpen }
        }
    }

    func disconnect() {
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

        // Climate, windows, charge-port, horn and lights terminate in the
        // Infotainment domain. A vehicle may omit VehicleInfo while waking and
        // leave the initial connection in the VCSEC-only phone-key session.
        // Wake it through that authenticated session and retry identity
        // discovery before declaring the command unavailable.
        try? await legacyClient.rke(30)
        try? await Task.sleep(for: .milliseconds(700))
        guard let vin = try? await legacyClient.vehicleVIN() else {
            throw LocalError.vehicleIdentityUnavailable
        }

        let key = try keyStore.load(for: vehicleID)
        cacheVehicleIdentity(vin: vin)
        try await startModernSession(on: connection, key: key, vin: vin)
        self.legacyClient = nil
        guard let tesla else { throw LocalError.vehicleIdentityUnavailable }
        return tesla
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

    private enum LocalError: LocalizedError {
        case noVehicle, keyMissing, handshakeTimedOut, vehicleIdentityUnavailable
        var errorDescription: String? {
            switch self {
            case .noVehicle: "没有已配对车辆"
            case .keyMissing: "本机车辆密钥已丢失，请重新配对"
            case .handshakeTimedOut: "安全连接超时。请唤醒车辆、靠近驾驶位后重试。"
            case .vehicleIdentityUnavailable: "车辆已连接，但暂未返回完整控制身份。请打开车门或轻踩刹车唤醒车辆，然后重试。"
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
