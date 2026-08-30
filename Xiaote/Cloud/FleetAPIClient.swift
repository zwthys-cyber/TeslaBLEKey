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

struct FleetEnergyProduct: Codable, Identifiable, Sendable {
    let energySiteID: Int64?
    let resourceType: String?
    let siteName: String?
    let id: String?

    enum CodingKeys: String, CodingKey {
        case energySiteID = "energy_site_id"
        case resourceType = "resource_type"
        case siteName = "site_name"
        case id
    }

    var stableID: String {
        id ?? energySiteID.map(String.init) ?? "\(resourceType ?? "energy")-\(siteName ?? "site")"
    }

    var name: String {
        let trimmed = siteName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Tesla 能源设备" : trimmed
    }

    var typeName: String {
        switch resourceType?.lowercased() {
        case "battery": "Powerwall"
        case "solar": "太阳能"
        case "wall_connector": "Wall Connector"
        default: "能源站点"
        }
    }
}

struct FleetVehicleSpecs: Codable, Sendable {
    let carType: String?
    let trim: String?
    let exteriorColor: String?
    let wheelType: String?
    let roofColor: String?
    let spoilerType: String?

    enum CodingKeys: String, CodingKey {
        case carType = "car_type"
        case trim
        case exteriorColor = "exterior_color"
        case wheelType = "wheel_type"
        case roofColor = "roof_color"
        case spoilerType = "spoiler_type"
    }

    var rows: [(String, String)] {
        [("车型", carType), ("版本", trim), ("车漆", exteriorColor),
         ("轮毂", wheelType), ("车顶", roofColor), ("扰流板", spoilerType)]
            .compactMap { label, value in
                guard let value, !value.isEmpty else { return nil }
                return (label, value)
            }
    }
}

struct FleetReleaseNotes: Decodable, Sendable {
    struct Note: Decodable, Sendable {
        let title: String?
        let subtitle: String?
        let description: String?
    }

    let releaseNotes: [Note]?
    let deployedVersion: String?
    let version: String?

    enum CodingKeys: String, CodingKey {
        case releaseNotes = "release_notes"
        case deployedVersion = "deployed_version"
        case version
    }

    var displayVersion: String? {
        let value = deployedVersion ?? version
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    var titledNotes: [String] {
        (releaseNotes ?? []).compactMap { note in
            let title = note.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return title.isEmpty ? nil : title
        }
    }
}

// These collection entries intentionally decode without retaining personal or
// invitation-link fields; the product surface only needs privacy-safe counts.
struct FleetDriver: Decodable, Sendable {}
struct FleetShareInvitation: Decodable, Sendable {}

extension FleetEnergyProduct {
    var identifiableID: String { stableID }
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

    func energyProducts(token: String) async throws -> [FleetEnergyProduct] {
        let response: FleetEnvelope<[FleetEnergyProduct]> = try await request(path: "/v1/energy/products", token: token)
        return response.response
    }

    func vehicleSpecs(token: String, vin: String) async throws -> FleetVehicleSpecs {
        try validate(vin: vin)
        let response: FleetEnvelope<FleetVehicleSpecs> = try await request(path: "/v1/vehicles/\(vin)/specs", token: token)
        return response.response
    }

    func releaseNotes(token: String, vin: String) async throws -> FleetReleaseNotes {
        try validate(vin: vin)
        let response: FleetEnvelope<FleetReleaseNotes> = try await request(path: "/v1/vehicles/\(vin)/release-notes", token: token)
        return response.response
    }

    func drivers(token: String, vin: String) async throws -> [FleetDriver] {
        try validate(vin: vin)
        let response: FleetEnvelope<[FleetDriver]> = try await request(path: "/v1/vehicles/\(vin)/drivers", token: token)
        return response.response
    }

    func shareInvitations(token: String, vin: String) async throws -> [FleetShareInvitation] {
        try validate(vin: vin)
        let response: FleetEnvelope<[FleetShareInvitation]> = try await request(path: "/v1/vehicles/\(vin)/share-invites", token: token)
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

    private func validate(vin: String) throws {
        guard vin.range(of: "^[A-HJ-NPR-Z0-9]{17}$", options: .regularExpression) != nil else {
            throw FleetAPIError.server("车辆 VIN 无效。")
        }
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
