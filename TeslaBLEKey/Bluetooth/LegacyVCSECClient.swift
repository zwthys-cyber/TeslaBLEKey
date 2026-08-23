import Foundation
@preconcurrency import TeslaBLEKeyKit

/// VIN-free VCSEC phone-key session used by the vehicle's local BLE endpoint.
/// This is the pre-Universal Message protocol used by phone keys: the vehicle
/// returns an ephemeral P-256 key and counter for the enrolled local key ID.
final class LegacyVCSECClient: @unchecked Sendable {
    enum ClientError: LocalizedError {
        case timeout
        case keyNotWhitelisted
        case malformedSession
        case rejected(Int)
        case unsupportedAction

        var errorDescription: String? {
            switch self {
            case .timeout: "车辆没有回应本地钥匙协议。"
            case .keyNotWhitelisted: "本机密钥尚未出现在车机钥匙列表中。"
            case .malformedSession: "车机返回的钥匙会话数据不完整。"
            case let .rejected(code): "车机拒绝了蓝牙钥匙命令（代码 \(code)）。"
            case .unsupportedAction: "当前 VIN-free 钥匙协议暂不支持此操作。"
            }
        }
    }

    private let connection: BLEConnection
    private let privateKey: TeslaPrivateKey
    private let keyID: Data
    private var sharedKey: Data?
    private var counter: UInt32 = 0
    private var iterator: AsyncStream<Data>.Iterator
    private var passiveAuthenticationTask: Task<Void, Never>?

    init(connection: BLEConnection, privateKey: TeslaPrivateKey) {
        self.connection = connection
        self.privateKey = privateKey
        self.keyID = Data(privateKey.publicKey.sha1Digest().prefix(4))
        self.iterator = connection.receiveMessages().makeAsyncIterator()
    }

    func isKeyWhitelisted() async throws -> Bool {
        // InformationRequest(GET_WHITELIST_INFO=5)
        let unsigned = Self.messageField(1, Self.enumField(1, 5))
        try await connection.send(Self.universalVCSECMessage(unsigned))
        for _ in 0 ..< 5 {
            let response = try await nextMessage(seconds: 2)
            if let whitelist = Self.firstLengthDelimitedField(16, in: response) {
                return Self.lengthDelimitedFields(2, in: whitelist).contains { entry in
                    Self.firstLengthDelimitedField(1, in: entry) == keyID
                }
            }
        }
        throw ClientError.timeout
    }

    func startSession() async throws {
        // The native phone-key bootstrap uses GET_EPHEMERAL_PUBLIC_KEY (3).
        // GET_SESSION_DATA (4) exists in some archived schemas but is not
        // answered consistently by production vehicles.
        let keyIdentifier = Self.bytesField(1, keyID)
        let request = Self.enumField(1, 3) + Self.messageField(2, keyIdentifier)
        try await connection.send(Self.toVCSECUnsigned(Self.messageField(1, request)))

        var sessionBytes: Data?
        for _ in 0 ..< 5 {
            let response = try await nextMessage(seconds: 2)
            if let candidate = Self.firstLengthDelimitedField(2, in: response) {
                sessionBytes = candidate
                break
            }
        }
        guard let sessionBytes,
              let vehiclePublicKey = Self.firstLengthDelimitedField(3, in: sessionBytes),
              vehiclePublicKey.count == 65 else { throw ClientError.keyNotWhitelisted }

        sharedKey = try privateKey.sharedAESKey(with: vehiclePublicKey)
        let vehicleCounter = Self.firstVarintField(2, in: sessionBytes).map(UInt32.init) ?? 0
        let wallClockCounter = UInt32(clamping: Int(Date().timeIntervalSince1970))
        counter = max(max(vehicleCounter &+ 1, wallClockCounter), 1)

        // UnsignedMessage.authenticationResponse(level NONE) is an explicitly
        // present, empty nested message: field 3, length 0.
        try await sendSigned(unsignedMessage: Self.messageField(3, Data()))
        _ = try? await nextMessage(seconds: 3)
    }

    func rke(_ rawAction: UInt64) async throws {
        try await sendSigned(unsignedMessage: Self.enumField(2, rawAction))
        try await awaitCommandResult()
    }

    /// Responds to the token-bound AuthenticationRequest emitted by VCSEC
    /// when a handle is pulled. Merely keeping a whitelisted BLE connection
    /// open is insufficient for passive entry: the vehicle requires a fresh
    /// AES-GCM-TOKEN response at its requested authentication level.
    func startPassiveAuthenticationResponder() {
        guard passiveAuthenticationTask == nil else { return }
        passiveAuthenticationTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    let response = try await self.nextMessage(seconds: 60)
                    try await self.respondToAuthenticationRequest(in: response)
                } catch is CancellationError {
                    return
                } catch {
                    // Idle timeouts are expected while no handle is pulled.
                    // A physical disconnect is reported by BLEConnection and
                    // rebuilt by VehicleController.
                }
            }
        }
    }

    func closure(field: Int, action: UInt64 = 3) async throws {
        let moveRequest = Self.enumField(field, action)
        try await sendSigned(unsignedMessage: Self.messageField(4, moveRequest))
        try await awaitCommandResult()
    }

    func close() {
        passiveAuthenticationTask?.cancel()
        passiveAuthenticationTask = nil
        connection.close()
    }

    private func sendSigned(
        unsignedMessage: Data,
        authenticatedData: Data = Data(),
        signatureType: UInt64 = 0
    ) async throws {
        guard let sharedKey else { throw ClientError.malformedSession }
        let nonce = Data(uint32BigEndian: counter)
        let box = try VariableNonceAESGCM(key: sharedKey).seal(
            plaintext: unsignedMessage,
            authenticatedData: authenticatedData,
            nonce: nonce
        )

        // Legacy SignedMessage fields: encrypted protobuf=2, signature=4,
        // keyId=5, counter=6. Signature type AES_GCM is the default value 0.
        let signed = Self.bytesField(2, box.ciphertext)
            + (signatureType == 0 ? Data() : Self.enumField(3, signatureType))
            + Self.bytesField(4, box.tag)
            + Self.bytesField(5, keyID)
            + Self.enumField(6, UInt64(counter))
        counter &+= 1
        try await connection.send(Self.messageField(1, signed))
    }

    private func respondToAuthenticationRequest(in response: Data) async throws {
        // FromVCSECMessage.authenticationRequest = field 3.
        guard let request = Self.firstLengthDelimitedField(3, in: response),
              let session = Self.firstLengthDelimitedField(2, in: request),
              let token = Self.firstLengthDelimitedField(1, in: session),
              token.count == 20 else { return }

        // Ignore challenges addressed to another enrolled phone key.
        if let identifier = Self.firstLengthDelimitedField(1, in: request),
           let requestedKeyID = Self.firstLengthDelimitedField(1, in: identifier),
           requestedKeyID != keyID { return }

        let requestedLevel = Self.firstVarintField(3, in: request) ?? 0
        guard requestedLevel == 1 || requestedLevel == 2 else { return }
        if let vehicleCounter = Self.firstVarintField(2, in: session) {
            let receivedCounter = UInt32(clamping: vehicleCounter)
            if receivedCounter < UInt32.max {
                counter = max(counter, receivedCounter + 1)
            }
        }

        // AuthenticationResponse.authenticationLevel = field 1;
        // UnsignedMessage.authenticationResponse = field 3.
        let authenticationResponse = Self.enumField(1, requestedLevel)
        let unsigned = Self.messageField(3, authenticationResponse)
        try await sendSigned(
            unsignedMessage: unsigned,
            authenticatedData: token,
            signatureType: 3 // SIGNATURE_TYPE_AES_GCM_TOKEN
        )
    }

    private func awaitCommandResult() async throws {
        let response = try await nextMessage(seconds: 5)
        guard let command = Self.firstLengthDelimitedField(4, in: response),
              let signed = Self.firstLengthDelimitedField(2, in: command) else { return }
        let code = Int(Self.firstVarintField(2, in: signed) ?? 0)
        guard code == 0 else { throw ClientError.rejected(code) }
    }

    private func nextMessage(seconds: Double) async throws -> Data {
        try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask { [iterator] in
                var iterator = iterator
                guard let value = await iterator.next() else { throw ClientError.timeout }
                return value
            }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw ClientError.timeout
            }
            guard let value = try await group.next() else { throw ClientError.timeout }
            group.cancelAll()
            self.iterator = self.connection.receiveMessages().makeAsyncIterator()
            return Self.vcsecPayload(from: value)
        }
    }

    /// Modern unauthenticated VCSEC requests use a Universal Message carrier.
    /// Its payload is VCSEC.UnsignedMessage directly (not ToVCSECMessage).
    /// The enrolled Phone Key session below remains the legacy raw
    /// ToVCSECMessage protocol and therefore does not use this carrier.
    static func universalVCSECMessage(_ unsignedMessage: Data) -> Data {
        // UniversalMessage.RoutableMessage:
        //   to_destination (field 6) { domain (field 1) = VEHICLE_SECURITY (2) }
        //   protobuf_message_as_bytes (field 10) = VCSEC.UnsignedMessage
        messageField(6, enumField(1, 2)) + bytesField(10, unsignedMessage)
    }

    static func vcsecPayload(from message: Data) -> Data {
        firstLengthDelimitedField(10, in: message) ?? message
    }

    static func toVCSECUnsigned(_ unsigned: Data) -> Data {
        messageField(2, unsigned)
    }

    static func enumField(_ field: Int, _ value: UInt64) -> Data {
        var data = varint(UInt64(field << 3))
        data.append(varint(value))
        return data
    }

    static func bytesField(_ field: Int, _ value: Data) -> Data {
        messageField(field, value)
    }

    static func messageField(_ field: Int, _ value: Data) -> Data {
        var data = varint(UInt64((field << 3) | 2))
        data.append(varint(UInt64(value.count)))
        data.append(value)
        return data
    }

    private static func varint(_ value: UInt64) -> Data {
        var value = value
        var bytes: [UInt8] = []
        repeat {
            var byte = UInt8(value & 0x7f)
            value >>= 7
            if value != 0 { byte |= 0x80 }
            bytes.append(byte)
        } while value != 0
        return Data(bytes)
    }

    private static func firstLengthDelimitedField(_ target: Int, in data: Data) -> Data? {
        lengthDelimitedFields(target, in: data).first
    }

    static func lengthDelimitedFields(_ target: Int, in data: Data) -> [Data] {
        var cursor = 0
        let bytes = [UInt8](data)
        var matches: [Data] = []
        while cursor < bytes.count {
            guard let key = readVarint(bytes, &cursor) else { return matches }
            let field = Int(key >> 3), wire = Int(key & 7)
            if wire == 2 {
                guard let length = readVarint(bytes, &cursor), cursor + Int(length) <= bytes.count else { return matches }
                let value = Data(bytes[cursor ..< cursor + Int(length)])
                cursor += Int(length)
                if field == target { matches.append(value) }
            } else if wire == 0 {
                guard readVarint(bytes, &cursor) != nil else { return matches }
            } else { return matches }
        }
        return matches
    }

    private static func firstVarintField(_ target: Int, in data: Data) -> UInt64? {
        var cursor = 0
        let bytes = [UInt8](data)
        while cursor < bytes.count {
            guard let key = readVarint(bytes, &cursor) else { return nil }
            let field = Int(key >> 3), wire = Int(key & 7)
            if wire == 0 {
                guard let value = readVarint(bytes, &cursor) else { return nil }
                if field == target { return value }
            } else if wire == 2 {
                guard let length = readVarint(bytes, &cursor), cursor + Int(length) <= bytes.count else { return nil }
                cursor += Int(length)
            } else { return nil }
        }
        return nil
    }

    private static func readVarint(_ bytes: [UInt8], _ cursor: inout Int) -> UInt64? {
        var value: UInt64 = 0
        var shift: UInt64 = 0
        while cursor < bytes.count, shift < 64 {
            let byte = bytes[cursor]
            cursor += 1
            value |= UInt64(byte & 0x7f) << shift
            if byte & 0x80 == 0 { return value }
            shift += 7
        }
        return nil
    }
}
