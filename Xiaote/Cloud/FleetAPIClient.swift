import Foundation

struct FleetVehicle: Codable, Identifiable, Sendable {
    let id: Int64
    let vehicleID: Int64?
    let vin: String
    let displayName: String?
    let state: String?

    enum CodingKeys: String, CodingKey {
        case id, vin, state
        case vehicleID = "vehicle_id"
        case displayName = "display_name"
    }

    var name: String {
        let trimmed = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Tesla Vehicle" : trimmed
    }
}

struct FleetAccountProfile: Codable, Sendable {
    let email: String?
    let fullName: String?
    let firstName: String?
    let lastName: String?
    let profileImageURL: URL?

    enum CodingKeys: String, CodingKey {
        case email
        case fullName = "full_name"
        case firstName = "first_name"
        case lastName = "last_name"
        case profileImageURL = "profile_image_url"
    }

    var displayName: String? {
        let explicit = fullName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !explicit.isEmpty { return explicit }
        let components = [firstName, lastName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return components.isEmpty ? nil : components.joined(separator: " ")
    }
}

struct FleetAccountRegion: Codable, Sendable {
    let region: String?
    let fleetAPIBaseURL: String?

    enum CodingKeys: String, CodingKey {
        case region
        case fleetAPIBaseURL = "fleet_api_base_url"
    }

    var displayName: String? {
        switch region?.lowercased() {
        case "cn": "中国大陆"
        case "eu": "欧洲"
        case "na": "北美"
        case let value?: value.uppercased()
        case nil: nil
        }
    }
}

private struct FleetEnvelope<Value: Decodable>: Decodable {
    let response: Value
}

private struct AuthStartResponse: Decodable {
    let authorizationURL: URL
    enum CodingKeys: String, CodingKey { case authorizationURL = "authorization_url" }
}

private struct AuthExchangeResponse: Decodable {
    let accessToken: String
    let expiresIn: TimeInterval
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
    }
}

struct FleetSession: Codable, Sendable {
    let token: String
    let expiresAt: Date
}

struct FleetCommandResult: Decodable, Sendable {
    struct Response: Decodable, Sendable {
        let result: Bool
        let reason: String?
    }
    let response: Response
}

enum FleetAPIError: LocalizedError {
    case invalidResponse
    case server(String)
    case loginCancelled
    case missingCallbackCode

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "服务器返回了无法识别的数据。"
        case .server(let message): message
        case .loginCancelled: "已取消登录。"
        case .missingCallbackCode: "Tesla 授权回调无效，请重新登录。"
        }
    }
}

actor FleetAPIClient {
    static let shared = FleetAPIClient()
    private let baseURL = URL(string: "https://api.txx.app")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func authorizationURL() async throws -> URL {
        let response: AuthStartResponse = try await request(path: "/v1/auth/start", method: "POST")
        return response.authorizationURL
    }

    func exchange(code: String) async throws -> FleetSession {
        let body = try JSONEncoder().encode(["code": code])
        let response: AuthExchangeResponse = try await request(path: "/v1/auth/exchange", method: "POST", body: body)
        return FleetSession(token: response.accessToken, expiresAt: Date().addingTimeInterval(response.expiresIn))
    }

    func vehicles(token: String) async throws -> [FleetVehicle] {
        let response: FleetEnvelope<[FleetVehicle]> = try await request(path: "/v1/vehicles", token: token)
        return response.response
    }

    func profile(token: String) async throws -> FleetAccountProfile {
        let response: FleetEnvelope<FleetAccountProfile> = try await request(path: "/v1/account/profile", token: token)
        return response.response
    }

    func region(token: String) async throws -> FleetAccountRegion {
        let response: FleetEnvelope<FleetAccountRegion> = try await request(path: "/v1/account/region", token: token)
        return response.response
    }

    func logout(token: String) async throws {
        let _: EmptyResponse = try await request(path: "/v1/auth/session", method: "DELETE", token: token)
    }

    func command(token: String, vin: String, name: String, payload: Data) async throws -> FleetCommandResult {
        let allowed = CharacterSet.lowercaseLetters.union(.decimalDigits).union(CharacterSet(charactersIn: "_"))
        guard name.unicodeScalars.allSatisfy(allowed.contains), !name.isEmpty,
              vin.range(of: "^[A-HJ-NPR-Z0-9]{17}$", options: .regularExpression) != nil,
              (try? JSONSerialization.jsonObject(with: payload)) != nil else {
            throw FleetAPIError.server("车辆命令或参数无效。")
        }
        return try await request(
            path: "/v1/vehicles/\(vin)/commands/\(name)",
            method: "POST", token: token, body: payload
        )
    }

    private struct EmptyResponse: Decodable {}
    private struct ErrorEnvelope: Decodable {
        struct Detail: Decodable { let message: String }
        let error: Detail
    }

    private func request<Value: Decodable>(path: String, method: String = "GET", token: String? = nil, body: Data? = nil) async throws -> Value {
        guard let url = URL(string: path, relativeTo: baseURL) else { throw FleetAPIError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        let (data, rawResponse) = try await session.data(for: request)
        guard let response = rawResponse as? HTTPURLResponse else { throw FleetAPIError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else {
            let message = (try? JSONDecoder().decode(ErrorEnvelope.self, from: data).error.message)
            throw FleetAPIError.server(message ?? "服务器请求失败（\(response.statusCode)）。")
        }
        if Value.self == EmptyResponse.self, data.isEmpty {
            return EmptyResponse() as! Value
        }
        return try JSONDecoder().decode(Value.self, from: data)
    }
}
