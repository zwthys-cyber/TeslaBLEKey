import Foundation
import Observation
import Security
@preconcurrency import TeslaBLEKeyKit

@MainActor
@Observable
final class VehicleController {
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

    var vehicleID = UserDefaults.standard.string(forKey: AppStorageKeys.pairedVehicleID) ?? ""
    var isPaired = UserDefaults.standard.bool(forKey: AppStorageKeys.paired)
    var phase: Phase = .idle
    var showingError = false
    var errorMessage = ""

    func pair(with nearby: NearbyTesla) async {
        phase = .connecting
        do {
            let key = try keyStore.loadOrCreate(for: nearby.peripheralName)
            let link = try BLEConnection(localName: nearby.peripheralName)
            connection = link
            try await link.connect(timeout: 30)

            phase = .pairingAwaitingCard
            let pairing = TeslaPairing(connector: link)
            try await pairing.requestPairing(
                publicKey: key.publicKey,
                role: .owner,
                formFactor: .iosDevice
            )

            vehicleID = nearby.peripheralName
            UserDefaults.standard.set(vehicleID, forKey: AppStorageKeys.pairedVehicleID)
            UserDefaults.standard.set(true, forKey: AppStorageKeys.paired)
            isPaired = true
            link.close()
            connection = nil
            try await connect()
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
        let client = try TeslaVehicle(
            connector: link,
            privateKey: key,
            configuration: .fourByteNonceBLE
        )
        connection = link
        tesla = client
        try await link.connect(timeout: 30)
        try await client.connect()
        phase = .handshaking
        try await client.startVCSECSession()
        phase = .connected
    }

    func connectFromUI() async {
        do { try await connect() } catch { presentError(Self.describe(error)) }
    }

    func lock() async { await execute("上锁") { try await $0.lock() } }
    func unlock() async { await execute("解锁") { try await $0.unlock() } }
    func openTrunk() async { await execute("开启后备箱") { try await $0.openTrunk() } }
    func openFrunk() async { await execute("开启前备箱") { try await $0.openFrunk() } }
    func flashLights() async { await execute("闪灯") { try await $0.flashLights() } }
    func honk() async { await execute("鸣笛") { try await $0.honkHorn() } }
    func authorizeDrive() async { await execute("启动车辆") { try await $0.remoteDrive() } }

    func disconnect() {
        tesla?.disconnect()
        tesla = nil
        connection = nil
        phase = .idle
    }

    func forgetVehicle() {
        disconnect()
        try? keyStore.delete(for: vehicleID)
        UserDefaults.standard.removeObject(forKey: AppStorageKeys.pairedVehicleID)
        UserDefaults.standard.removeObject(forKey: AppStorageKeys.paired)
        vehicleID = ""
        isPaired = false
    }

    private func execute(_ name: String, operation: (TeslaVehicle) async throws -> Void) async {
        guard let tesla else { presentError("请先连接车辆。"); return }
        phase = .executing(name)
        do {
            try await operation(tesla)
            phase = .connected
        } catch {
            presentError(Self.describe(error))
        }
    }

    private func presentError(_ message: String) {
        errorMessage = message
        phase = .failed(message)
        showingError = true
    }

    private static func describe(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    private enum LocalError: LocalizedError {
        case noVehicle, keyMissing
        var errorDescription: String? {
            switch self {
            case .noVehicle: "没有已配对车辆"
            case .keyMissing: "本机车辆密钥已丢失，请重新配对"
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
