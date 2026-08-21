import Foundation
import Observation
import CryptoKit
import TeslaBLE

@MainActor
@Observable
final class VehicleController {
    enum Phase: Equatable {
        case idle
        case preparingKey
        case scanning
        case connecting
        case pairingAwaitingCard
        case handshaking
        case connected
        case executing(String)
        case failed(String)

        var title: String {
            switch self {
            case .idle: "未连接"
            case .preparingKey: "正在准备设备密钥"
            case .scanning: "正在寻找车辆"
            case .connecting: "正在连接"
            case .pairingAwaitingCard: "请刷钥匙卡并在车机确认"
            case .handshaking: "正在建立安全会话"
            case .connected: "已连接"
            case let .executing(name): "正在\(name)"
            case let .failed(message): message
            }
        }
    }

    private let keyStore = KeychainTeslaKeyStore(service: "com.local.teslablekey.keys")
    private var client: TeslaVehicleClient?
    private var stateTask: Task<Void, Never>?

    var vin = UserDefaults.standard.string(forKey: AppStorageKeys.pairedVIN) ?? ""
    var isPaired = UserDefaults.standard.bool(forKey: AppStorageKeys.paired)
    var phase: Phase = .idle
    var showingError = false
    var errorMessage = ""

    var normalizedVIN: String { VINValidator.normalized(vin) }
    var hasValidVIN: Bool { VINValidator.isValid(normalizedVIN) }

    func matches(_ nearbyVehicle: NearbyTesla) -> Bool {
        VINValidator.bluetoothName(for: normalizedVIN)?.caseInsensitiveCompare(
            nearbyVehicle.peripheralName
        ) == .orderedSame
    }

    func pair() async {
        guard hasValidVIN else {
            presentError("VIN 必须是 17 位，且不能包含 I、O、Q。")
            return
        }

        let targetVIN = normalizedVIN
        vin = targetVIN
        phase = .preparingKey

        do {
            let key: P256.KeyAgreement.PrivateKey
            if let existing = try keyStore.loadPrivateKey(forVIN: targetVIN) {
                key = existing
            } else {
                key = KeyPairFactory.generateKeyPair()
                try keyStore.savePrivateKey(key, forVIN: targetVIN)
            }

            let newClient = TeslaVehicleClient(
                vin: targetVIN,
                keyStore: keyStore,
                logger: OSLogTeslaBLELogger(minimumLevel: .info)
            )
            install(newClient)
            try await newClient.connect(mode: .pairing, timeout: .seconds(45))
            try await newClient.send(
                .security(.addKey(
                    publicKey: KeyPairFactory.publicKeyBytes(of: key),
                    role: .owner,
                    formFactor: .iosDevice
                )),
                timeout: .seconds(15)
            )

            phase = .pairingAwaitingCard
            UserDefaults.standard.set(targetVIN, forKey: AppStorageKeys.pairedVIN)
        } catch {
            await disconnect()
            presentError(Self.describe(error))
        }
    }

    /// Call after the vehicle screen reports that the key was accepted.
    func confirmPairing() async {
        await disconnect()
        do {
            isPaired = true
            UserDefaults.standard.set(true, forKey: AppStorageKeys.paired)
            try await connect()
        } catch {
            isPaired = false
            UserDefaults.standard.set(false, forKey: AppStorageKeys.paired)
            presentError("车辆尚未接受此密钥：\(Self.describe(error))")
        }
    }

    func connect() async throws {
        guard hasValidVIN else { throw LocalError.invalidVIN }
        let newClient = TeslaVehicleClient(
            vin: normalizedVIN,
            keyStore: keyStore,
            logger: OSLogTeslaBLELogger(minimumLevel: .info)
        )
        install(newClient)
        try await newClient.connect(mode: .normal, timeout: .seconds(45))
    }

    func connectFromUI() async {
        do { try await connect() } catch { presentError(Self.describe(error)) }
    }

    func lock() async { await execute("上锁", command: .security(.lock)) }
    func unlock() async { await execute("解锁", command: .security(.unlock)) }
    func openTrunk() async { await execute("开启后备箱", command: .security(.openTrunk)) }
    func openFrunk() async { await execute("开启前备箱", command: .security(.openFrunk)) }
    func flashLights() async { await execute("闪灯", command: .actions(.flashLights)) }
    func honk() async { await execute("鸣笛", command: .actions(.honk)) }

    func disconnect() async {
        stateTask?.cancel()
        stateTask = nil
        await client?.disconnect()
        client = nil
        phase = .idle
    }

    func forgetVehicle() async {
        await disconnect()
        do { try keyStore.deletePrivateKey(forVIN: normalizedVIN) } catch {
            presentError(Self.describe(error))
            return
        }
        UserDefaults.standard.removeObject(forKey: AppStorageKeys.pairedVIN)
        UserDefaults.standard.removeObject(forKey: AppStorageKeys.paired)
        vin = ""
        isPaired = false
    }

    private func install(_ newClient: TeslaVehicleClient) {
        client = newClient
        stateTask?.cancel()
        stateTask = Task { [weak self] in
            for await state in newClient.stateStream {
                guard !Task.isCancelled else { break }
                self?.apply(state)
            }
        }
    }

    private func apply(_ state: ConnectionState) {
        switch state {
        case .disconnected: if phase != .pairingAwaitingCard { phase = .idle }
        case .scanning: phase = .scanning
        case .connecting: phase = .connecting
        case .handshaking: phase = .handshaking
        case .connected:
            if phase != .pairingAwaitingCard { phase = .connected }
        }
    }

    private func execute(_ name: String, command: Command) async {
        guard let client else {
            presentError("请先连接车辆。")
            return
        }
        phase = .executing(name)
        do {
            try await client.send(command, timeout: .seconds(12))
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
        case invalidVIN
        var errorDescription: String? { "VIN 无效" }
    }
}
