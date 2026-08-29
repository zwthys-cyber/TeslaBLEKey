import AuthenticationServices
import Observation
import Security
import UIKit

@MainActor
@Observable
final class FleetAccountController: NSObject {
    private(set) var session: FleetSession?
    private(set) var profile: FleetAccountProfile?
    private(set) var vehicles: [FleetVehicle] = []
    private(set) var isDemoMode = false
    private(set) var isWorking = false
    var errorMessage: String?

    private let api = FleetAPIClient.shared
    private var authenticationSession: ASWebAuthenticationSession?
    private let keychain = FleetSessionKeychain()
    private let demoModeKey = "fleet.demoMode"

    override init() {
        session = try? keychain.load()
        isDemoMode = UserDefaults.standard.bool(forKey: demoModeKey)
        super.init()
        if session == nil {
            isDemoMode = false
            UserDefaults.standard.removeObject(forKey: demoModeKey)
        }
        if let session, session.expiresAt <= Date() {
            self.session = nil
            isDemoMode = false
            UserDefaults.standard.removeObject(forKey: demoModeKey)
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
    }

    func signOut() async {
        guard let current = session else { return }
        isWorking = true
        try? await api.logout(token: current.token)
        try? keychain.delete()
        session = nil
        profile = nil
        vehicles = []
        isDemoMode = false
        UserDefaults.standard.removeObject(forKey: demoModeKey)
        isWorking = false
    }

    func enableDemoMode() {
        guard isSignedIn, vehicles.isEmpty else { return }
        isDemoMode = true
        UserDefaults.standard.set(true, forKey: demoModeKey)
        vehicles = [Self.demoVehicle]
    }

    func disableDemoMode() async {
        isDemoMode = false
        UserDefaults.standard.removeObject(forKey: demoModeKey)
        vehicles = []
        await refreshAccount()
    }

    private func apply(remoteVehicles: [FleetVehicle]) {
        if remoteVehicles.isEmpty, isDemoMode {
            vehicles = [Self.demoVehicle]
        } else {
            vehicles = remoteVehicles
            if !remoteVehicles.isEmpty {
                isDemoMode = false
                UserDefaults.standard.removeObject(forKey: demoModeKey)
            }
        }
    }

    private static let demoVehicle = FleetVehicle(
        id: -1,
        vehicleID: nil,
        vin: "DEMO0000000000003",
        displayName: "Model 3",
        state: "online"
    )

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
