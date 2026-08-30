import AuthenticationServices
import Observation
import Security
import UIKit

@MainActor
@Observable
final class FleetAccountController: NSObject {
    private(set) var session: FleetSession?
    private(set) var profile: FleetAccountProfile?
    private(set) var region: FleetAccountRegion?
    private(set) var energyProducts: [FleetEnergyProduct] = []
    private(set) var vehicleSpecs: [String: FleetVehicleSpecs] = [:]
    private(set) var releaseNotes: [String: FleetReleaseNotes] = [:]
    private(set) var driverCounts: [String: Int] = [:]
    private(set) var invitationCounts: [String: Int] = [:]
    private(set) var mobileAccess: [String: Bool] = [:]
    private(set) var recentAlerts: [String: [FleetVehicleAlert]] = [:]
    private(set) var nearbyChargingSites: [String: [FleetNearbyChargingSites.Site]] = [:]
    private(set) var vehicles: [FleetVehicle] = []
    private(set) var isWorking = false
    var errorMessage: String?

    private let api = FleetAPIClient.shared
    private var authenticationSession: ASWebAuthenticationSession?
    private let keychain = FleetSessionKeychain()

    override init() {
        session = try? keychain.load()
        super.init()
        if let session, session.expiresAt <= Date() {
            self.session = nil
            try? keychain.delete()
        }
    }

    var isSignedIn: Bool { session != nil }

    func signIn() async {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        do {
            let authorizationURL = try await api.authorizationURL()
            let callbackURL = try await authenticate(at: authorizationURL)
            guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
                throw FleetAPIError.missingCallbackCode
            }
            if let error = components.queryItems?.first(where: { $0.name == "error" })?.value {
                throw FleetAPIError.server("Tesla 授权失败：\(error)")
            }
            guard let code = components.queryItems?.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
                throw FleetAPIError.missingCallbackCode
            }
            let newSession = try await api.exchange(code: code)
            try keychain.save(newSession)
            session = newSession
            let remoteVehicles = try await api.vehicles(token: newSession.token)
            apply(remoteVehicles: remoteVehicles)
            profile = try? await api.profile(token: newSession.token)
            region = try? await api.region(token: newSession.token)
            energyProducts = (try? await api.energyProducts(token: newSession.token)) ?? []
        } catch {
            if let authenticationError = error as? ASWebAuthenticationSessionError,
               authenticationError.code == .canceledLogin {
                // Cancellation is an intentional user action, not an app error.
            } else if !Self.isCancellation(error) {
                errorMessage = error.localizedDescription
            }
        }
        authenticationSession = nil
        isWorking = false
    }

    func refreshVehicles() async {
        await refreshAccount()
    }

    func refreshAccount() async {
        guard let session, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        errorMessage = nil
        do {
            let remoteVehicles = try await api.vehicles(token: session.token)
            apply(remoteVehicles: remoteVehicles)
        } catch {
            if !Self.isCancellation(error) {
                errorMessage = error.localizedDescription
            }
        }
        guard !Task.isCancelled else { return }
        profile = try? await api.profile(token: session.token)
        region = try? await api.region(token: session.token)
        energyProducts = (try? await api.energyProducts(token: session.token)) ?? []
    }

    func signOut() async {
        guard let current = session else { return }
        isWorking = true
        try? await api.logout(token: current.token)
        try? keychain.delete()
        session = nil
        profile = nil
        region = nil
        energyProducts = []
        vehicleSpecs = [:]
        releaseNotes = [:]
        driverCounts = [:]
        invitationCounts = [:]
        mobileAccess = [:]
        recentAlerts = [:]
        nearbyChargingSites = [:]
        vehicles = []
        isWorking = false
    }

    func send(command: FleetCommandDefinition, to vehicle: FleetVehicle, payload: Data) async throws {
        guard let session else { throw FleetAPIError.server("请先登录 Tesla 账号。") }
        let result = try await api.command(token: session.token, vin: vehicle.vin.uppercased(), name: command.id, payload: payload)
        guard result.response.result else {
            throw FleetAPIError.server(result.response.reason ?? "车辆拒绝了此命令。")
        }
    }

    func loadSpecs(for vin: String) async {
        let vin = vin.uppercased()
        guard vehicleSpecs[vin] == nil, let session else { return }
        if let specs = try? await api.vehicleSpecs(token: session.token, vin: vin), !specs.rows.isEmpty {
            vehicleSpecs[vin] = specs
        }
    }

    func loadCloudDetails(for vin: String) async {
        let vin = vin.uppercased()
        guard let session else { return }

        if releaseNotes[vin] == nil,
           let notes = try? await api.releaseNotes(token: session.token, vin: vin),
           notes.displayVersion != nil || !notes.titledNotes.isEmpty {
            releaseNotes[vin] = notes
        }
        if driverCounts[vin] == nil,
           let drivers = try? await api.drivers(token: session.token, vin: vin) {
            driverCounts[vin] = drivers.count
        }
        if invitationCounts[vin] == nil,
           let invitations = try? await api.shareInvitations(token: session.token, vin: vin) {
            invitationCounts[vin] = invitations.count
        }
        if mobileAccess[vin] == nil,
           let enabled = try? await api.mobileEnabled(token: session.token, vin: vin) {
            mobileAccess[vin] = enabled
        }
    }

    func loadRecentAlerts(for vin: String) async {
        let vin = vin.uppercased()
        guard let session else { return }
        if let alerts = try? await api.recentAlerts(token: session.token, vin: vin) {
            recentAlerts[vin] = Array(alerts.prefix(10))
        }
    }

    func loadNearbyChargingSites(for vin: String) async {
        let vin = vin.uppercased()
        guard let session else { return }
        if let response = try? await api.nearbyChargingSites(token: session.token, vin: vin) {
            nearbyChargingSites[vin] = (response.superchargers ?? []).sorted {
                ($0.distanceMiles ?? .greatestFiniteMagnitude) < ($1.distanceMiles ?? .greatestFiniteMagnitude)
            }
        }
    }

    private func apply(remoteVehicles: [FleetVehicle]) {
        vehicles = remoteVehicles
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return true }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            return isCancellation(underlying)
        }
        return false
    }

    private func authenticate(at url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let auth = ASWebAuthenticationSession(url: url, callbackURLScheme: "teslablekey") { callback, error in
                if let error { continuation.resume(throwing: error) }
                else if let callback { continuation.resume(returning: callback) }
                else { continuation.resume(throwing: FleetAPIError.missingCallbackCode) }
            }
            auth.presentationContextProvider = self
            auth.prefersEphemeralWebBrowserSession = false
            authenticationSession = auth
            if !auth.start() {
                authenticationSession = nil
                continuation.resume(throwing: FleetAPIError.invalidResponse)
            }
        }
    }
}

extension FleetAccountController: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}

private struct FleetSessionKeychain {
    private let service = "com.local.teslablekey.fleet"
    private let account = "backend-session"

    func save(_ session: FleetSession) throws {
        let data = try JSONEncoder().encode(session)
        try delete()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw FleetAPIError.server("无法安全保存登录状态。") }
    }

    func load() throws -> FleetSession? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw FleetAPIError.server("无法读取登录状态。")
        }
        return try JSONDecoder().decode(FleetSession.self, from: data)
    }

    func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw FleetAPIError.server("无法清除登录状态。")
        }
    }
}
