import Foundation
import Observation
import Security
@preconcurrency import TeslaBLEKeyKit

@MainActor
@Observable
final class VehicleController {
    enum VehicleAction: String, CaseIterable, Hashable, Identifiable, Sendable {
        case lock, unlock, frunk, trunk, drive, flash, horn
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
    var phase: Phase = .idle
    var showingError = false
    var errorMessage = ""
    var canConfirmPairing = false
    var executingAction: VehicleAction?
    var lastSuccessAction: VehicleAction?
    private var successClearTask: Task<Void, Never>?
    private var handshakeTimeoutTask: Task<Void, Never>?
    private var handshakeDidTimeOut = false

    init() {
        let defaults = UserDefaults.standard
        vehicleID = defaults.string(forKey: AppStorageKeys.pairedVehicleID) ?? ""
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
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled, let self, self.phase == .handshaking else { return }
            self.handshakeDidTimeOut = true
            link?.close()
            self.presentError("安全连接超时。请唤醒车辆、靠近驾驶位后重试。")
        }
        let bootstrap = LegacyVCSECClient(connection: link, privateKey: key)
        do {
            let discoveredVIN = try await bootstrap.vehicleVIN()
            link.vin = discoveredVIN
            let client = try TeslaVehicle(
                connector: link,
                privateKey: key,
                configuration: .standard
            )
            try await client.connect()
            try await client.startVCSECSession()
            tesla = client
        } catch LegacyVCSECClient.ClientError.timeout {
            // Older VCSEC versions may not expose VehicleInfo. Keep the
            // original VIN-free phone-key session as a compatibility path.
            try await bootstrap.startSession()
            legacyClient = bootstrap
        }
        handshakeTimeoutTask?.cancel()
        handshakeTimeoutTask = nil
        guard !handshakeDidTimeOut else { throw LocalError.handshakeTimedOut }
        phase = .connected
    }

    func connectFromUI() async {
        do { try await connect() } catch { presentError(Self.describe(error)) }
    }

    func lock() async { await execute(.lock, name: "上锁") { try await self.perform(modern: { try await $0.lock() }, legacy: { try await $0.rke(1) }) } }
    func unlock() async { await execute(.unlock, name: "解锁") { try await self.perform(modern: { try await $0.unlock() }, legacy: { try await $0.rke(0) }) } }
    func openTrunk() async { await execute(.trunk, name: "开启后备箱") { try await self.perform(modern: { try await $0.openTrunk() }, legacy: { try await $0.rke(2) }) } }
    func openFrunk() async { await execute(.frunk, name: "开启前备箱") { try await self.perform(modern: { try await $0.openFrunk() }, legacy: { try await $0.rke(3) }) } }
    func flashLights() async { await execute(.flash, name: "闪灯") { try await self.performModern { try await $0.flashLights() } } }
    func honk() async { await execute(.horn, name: "鸣笛") { try await self.performModern { try await $0.honkHorn() } } }
    func authorizeDrive() async { await execute(.drive, name: "启动车辆") { try await self.perform(modern: { try await $0.remoteDrive() }, legacy: { try await $0.rke(20) }) } }

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
        disconnect()
        try? keyStore.delete(for: vehicleID)
        UserDefaults.standard.removeObject(forKey: AppStorageKeys.pairedVehicleID)
        UserDefaults.standard.removeObject(forKey: AppStorageKeys.paired)
        UserDefaults.standard.removeObject(forKey: AppStorageKeys.pairingSchemaVersion)
        vehicleID = ""
        isPaired = false
    }

    private func execute(_ action: VehicleAction, name: String, operation: () async throws -> Void) async {
        guard tesla != nil || legacyClient != nil else { presentError("请先连接车辆。"); return }
        // Tesla vehicle commands share one authenticated BLE session. Serialize them
        // so a second command cannot replace the first command's presentation state.
        guard executingAction == nil else { return }
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
        } catch {
            executingAction = nil
            presentError(Self.describe(error))
        }
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
        guard let tesla else { throw LegacyVCSECClient.ClientError.unsupportedAction }
        try await operation(tesla)
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

    private enum LocalError: LocalizedError {
        case noVehicle, keyMissing, handshakeTimedOut
        var errorDescription: String? {
            switch self {
            case .noVehicle: "没有已配对车辆"
            case .keyMissing: "本机车辆密钥已丢失，请重新配对"
            case .handshakeTimedOut: "安全连接超时。请唤醒车辆、靠近驾驶位后重试。"
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
