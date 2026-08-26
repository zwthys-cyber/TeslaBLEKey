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

    func logout(token: String) async throws {
        let _: EmptyResponse = try await request(path: "/v1/auth/session", method: "DELETE", token: token)
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
