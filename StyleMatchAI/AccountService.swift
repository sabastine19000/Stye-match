import CryptoKit
import Foundation
import Security

struct StyleMatchAccountSession: Codable, Equatable {
    let token: String
    let expiresAt: Date
    /// The subject returned by AuthenticationServices. It is never an email
    /// address and is retained only to bind this device session to the Apple
    /// identity which completed the exchange.
    let appleSubject: String?
    /// The Worker may provide an opaque account reference. Older Worker
    /// responses do not, so this remains optional rather than inventing one
    /// from a token, email, or presentation state.
    let accountID: String?
    /// A bearer token is valid only for the exact backend environment that
    /// issued it. This prevents a Debug/staging token being reused elsewhere.
    let endpointHost: String?

    init(
        token: String,
        expiresAt: Date,
        appleSubject: String? = nil,
        accountID: String? = nil,
        endpointHost: String? = nil
    ) {
        self.token = token
        self.expiresAt = expiresAt
        self.appleSubject = appleSubject
        self.accountID = accountID
        self.endpointHost = endpointHost
    }
}

/// The single account authority shared by Profile, Style Friends, sharing,
/// notifications, and live support. A local Apple authorization alone is not
/// an active backend session.
enum StyleMatchAccountSessionAuthority {
    enum State: Equatable {
        case signedOut
        case reauthenticationRequired
        case active(StyleMatchAccountSession)
    }

    static func state(
        session: StyleMatchAccountSession?,
        expectedHost: String?,
        now: Date = Date()
    ) -> State {
        guard let session else { return .signedOut }
        guard session.expiresAt > now else { return .reauthenticationRequired }
        guard let expectedHost,
              session.endpointHost?.lowercased() == expectedHost.lowercased(),
              let subject = session.appleSubject,
              isValidAppleSubject(subject) else {
            return .reauthenticationRequired
        }
        return .active(session)
    }

    static func isValidAppleSubject(_ value: String) -> Bool {
        !value.isEmpty
            && value.count <= 255
            && !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }
}

enum StyleMatchLocalAccountIdentity {
    static func isAppleConnected(defaults: UserDefaults = .standard) -> Bool {
        defaults.string(forKey: "customerAccountMode") == "Sign in with Apple"
            && !(defaults.string(forKey: "customerAppleUserID") ?? "").isEmpty
    }
}

enum StyleMatchAccountError: LocalizedError {
    case authorizationIncomplete
    case configurationUnavailable
    case invalidResponse
    case reauthenticationRequired
    case credentialVerificationFailed
    case serviceUnavailable
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .authorizationIncomplete:
            return "Apple sign-in did not finish. Please try again."
        case .configurationUnavailable, .serviceUnavailable:
            return "Account services are temporarily unavailable. Please try again."
        case .invalidResponse:
            return "We couldn’t verify the account response. Please try again."
        case .reauthenticationRequired:
            return "Please confirm with Apple again before deleting your account."
        case .credentialVerificationFailed:
            return "Apple could not verify this sign-in credential. Please try again."
        case .unauthorized:
            return "Your account session expired. Please sign in with Apple again."
        }
    }
}

enum StyleMatchAppleNonce {
    static func make(length: Int = 32) throws -> String {
        precondition(length > 0)
        let characters = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        result.reserveCapacity(length)

        while result.count < length {
            var random: UInt8 = 0
            guard SecRandomCopyBytes(kSecRandomDefault, 1, &random) == errSecSuccess else {
                throw StyleMatchAccountError.authorizationIncomplete
            }
            if Int(random) < characters.count {
                result.append(characters[Int(random)])
            }
        }
        return result
    }

    static func hash(_ nonce: String) -> String {
        SHA256.hash(data: Data(nonce.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

enum StyleMatchAccountSessionStore {
    private static let service = "com.sabastine.stylematchai.account"
    private static let account = "worker-session"
    static let didChangeNotification = Notification.Name("StyleMatchAccountSessionDidChange")
    static let profileReconnectRequestedNotification = Notification.Name("StyleMatchProfileReconnectRequested")

    static func load() -> StyleMatchAccountSession? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else {
            return nil
        }
        guard let session = try? JSONDecoder().decode(StyleMatchAccountSession.self, from: data) else {
            return nil
        }
        let expectedHost = StyleMatchRuntimeEndpoint.accountResolution()?.baseURL.host
        guard case .active = StyleMatchAccountSessionAuthority.state(
            session: session,
            expectedHost: expectedHost
        ) else {
            return nil
        }
        return session
    }

    static func save(_ session: StyleMatchAccountSession) throws {
        let data = try JSONEncoder().encode(session)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess {
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
            return
        }
        guard status == errSecItemNotFound else { throw StyleMatchAccountError.serviceUnavailable }

        var insertion = baseQuery
        attributes.forEach { insertion[$0.key] = $0.value }
        guard SecItemAdd(insertion as CFDictionary, nil) == errSecSuccess else {
            throw StyleMatchAccountError.serviceUnavailable
        }
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

/// User-facing copy for surfaces that consume the one StyleMatch backend
/// session. These surfaces route to Profile; they never start their own Apple
/// authorization flow.
enum StyleMatchSessionRecoveryCopy {
    static let title = "KigoStylist session required"
    static let actionTitle = "Open Profile"

    static func detail(for feature: String) -> String {
        "\(feature) uses your KigoStylist account. Reconnect once in Profile to continue."
    }
}

/// A narrowly scoped acceptance harness. It imports an already-issued synthetic
/// bearer session only into a Debug Simulator process and never accepts an
/// account key, Apple credential, or production endpoint.
enum StyleMatchSimulatorFriendsAuthTestHarness {
    private static let modeKey = "STYLEMATCH_SIMULATOR_TEST_MODE"
    private static let sessionKey = "STYLEMATCH_SIMULATOR_SYNTHETIC_SESSION"
    private static let cardKey = "STYLEMATCH_SIMULATOR_SYNTHETIC_CARD"
    private static let expectedMode = "friends-auth-test"

    static func applyIfConfigured(environment: [String: String] = ProcessInfo.processInfo.environment) {
        #if DEBUG && targetEnvironment(simulator)
        guard environment[modeKey] == expectedMode,
              StyleMatchRuntimeEndpoint.accountResolution(environment: environment)?.baseURL.host == AppBackendConfiguration.approvedFriendsAuthTestAPIHost,
              let encodedSession = environment[sessionKey],
              let session = decodedSession(encodedSession) else {
            return
        }

        try? StyleMatchAccountSessionStore.save(session)
        UserDefaults.standard.set(true, forKey: "hasChosenAccessMode")
        if let encodedCard = environment[cardKey], let card = decodedCard(encodedCard) {
            ShareableScoreCardLocalStore().saveCreatedCard(
                token: card.token,
                url: URL(string: "https://stylematchpro.com/share/\(card.token)")!,
                expiresAt: card.expiresAt,
                overallScore: card.score
            )
        }
        #endif
    }

    #if DEBUG && targetEnvironment(simulator)
    private static func decodedSession(_ encoded: String) -> StyleMatchAccountSession? {
        let values = encoded.split(separator: "|", maxSplits: 1).map(String.init)
        guard values.count == 2,
              values[0].range(of: "^[A-Za-z0-9_-]{32,128}$", options: .regularExpression) != nil,
              let expiresAt = ISO8601DateFormatter().date(from: values[1]),
              expiresAt > Date() else {
            return nil
        }
        return StyleMatchAccountSession(
            token: values[0],
            expiresAt: expiresAt,
            appleSubject: "simulator-test-subject",
            endpointHost: AppBackendConfiguration.approvedFriendsAuthTestAPIHost
        )
    }

    private static func decodedCard(_ encoded: String) -> (token: String, expiresAt: String, score: Int?)? {
        let values = encoded.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard values.count == 3,
              ShareableScoreCardRoute.isSafeToken(values[0]),
              ISO8601DateFormatter().date(from: values[1]) != nil else {
            return nil
        }
        let score = values[2].isEmpty ? nil : Int(values[2])
        guard score.map({ (0...100).contains($0) }) ?? true else { return nil }
        return (values[0], values[1], score)
    }
    #endif

}

enum StyleMatchAccountSessionDiagnostics {
    static func log(stage: String, defaults: UserDefaults = .standard) {
        _ = stage
        _ = defaults
    }
}

/// A device-local, Keychain-protected diagnostic aid for Apple sign-in.
/// It deliberately stores only lifecycle stages and an opaque random attempt
/// reference: never credentials, Apple identity values, request data, or an
/// account/session identifier. Entries expire after one day and are capped at
/// the three most-recent attempts.
enum StyleMatchAppleSignInDiagnosticBuffer {
    enum Stage: String, Codable, CaseIterable {
        case attemptCreated = "attempt_created"
        case appleAuthorizationResult = "apple_authorization_result"
        case requestDispatched = "request_dispatched"
        case responseReceived = "response_received"
        case sessionSaved = "session_saved"
        case uiObserverUpdated = "ui_observer_updated"
    }

    struct Attempt: Codable, Equatable {
        let reference: UUID
        let createdAt: Date
        var stages: [Stage]
    }

    private static let service = "com.sabastine.stylematchai.apple-signin-diagnostics"
    private static let account = "attempt-ring-v1"
    private static let retention: TimeInterval = 24 * 60 * 60
    private static let capacity = 3
#if targetEnvironment(simulator)
    // XCTest hosts on Simulator do not receive the app's Keychain entitlement.
    // This contains only opaque lifecycle stages, never Apple or backend data.
    private static let simulatorFallbackKey = "com.sabastine.stylematchai.apple-signin-diagnostics.simulator"
#endif

    static func begin(now: Date = Date()) {
        var attempts = retainedAttempts(now: now)
        attempts.append(Attempt(reference: UUID(), createdAt: now, stages: [.attemptCreated]))
        save(Array(attempts.suffix(capacity)))
    }

    static func record(_ stage: Stage, now: Date = Date()) {
        var attempts = retainedAttempts(now: now)
        if attempts.isEmpty {
            attempts.append(Attempt(reference: UUID(), createdAt: now, stages: [.attemptCreated]))
        }
        attempts[attempts.count - 1].stages.append(stage)
        save(Array(attempts.suffix(capacity)))
    }

    static func load(now: Date = Date()) -> [Attempt] {
        retainedAttempts(now: now)
    }

    private static func retainedAttempts(now: Date) -> [Attempt] {
        let attempts = read().filter { now.timeIntervalSince($0.createdAt) < retention }
        save(attempts)
        return attempts
    }

    private static func read() -> [Attempt] {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else {
#if targetEnvironment(simulator)
            guard let fallback = UserDefaults.standard.data(forKey: simulatorFallbackKey) else { return [] }
            return (try? JSONDecoder().decode([Attempt].self, from: fallback)) ?? []
#else
            return []
#endif
        }
        return (try? JSONDecoder().decode([Attempt].self, from: data)) ?? []
    }

    private static func save(_ attempts: [Attempt]) {
        guard let data = try? JSONEncoder().encode(attempts) else { return }
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insertion = baseQuery
            attributes.forEach { insertion[$0.key] = $0.value }
            let insertionStatus = SecItemAdd(insertion as CFDictionary, nil)
#if targetEnvironment(simulator)
            if insertionStatus != errSecSuccess {
                UserDefaults.standard.set(data, forKey: simulatorFallbackKey)
            }
#endif
        } else if status != errSecSuccess {
#if targetEnvironment(simulator)
            UserDefaults.standard.set(data, forKey: simulatorFallbackKey)
#endif
        }
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

struct StyleMatchAccountClient {
    private struct ExchangeResponse: Decodable {
        let sessionToken: String
        let expiresAt: String
        let accountID: String?

        enum CodingKeys: String, CodingKey {
            case sessionToken = "session_token"
            case expiresAt = "expires_at"
            case accountID = "account_id"
        }
    }

    private struct ErrorResponse: Decodable {
        let error: String
    }

    private let baseURL: URL?
    private let session: URLSession

    init(
        session: URLSession = .shared,
        endpointFactory: StyleMatchLiveClientEndpointFactory = .current()
    ) {
        baseURL = endpointFactory.accountBaseURL
        self.session = session
    }

    init(
        baseURL: URL?,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
    }

    var resolvedBaseURL: URL? {
        baseURL
    }

    func exchange(
        authorizationCode: Data?,
        identityToken: Data?,
        nonce: String,
        appleSubject: String? = nil
    ) async throws -> StyleMatchAccountSession {
        guard let authorizationCode = utf8(authorizationCode),
              let identityToken = utf8(identityToken),
              !nonce.isEmpty else {
            throw StyleMatchAccountError.authorizationIncomplete
        }

        var request = try request(path: "/v1/auth/apple/exchange", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(StylistChatAuthHeaders.deviceHash(), forHTTPHeaderField: "X-Device-Hash")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "authorization_code": authorizationCode,
            "identity_token": identityToken,
            "nonce": nonce
        ])

        let (data, response) = try await perform(request)
        guard response.statusCode == 200 else { throw mappedError(data: data, status: response.statusCode) }
        let payload = try JSONDecoder().decode(ExchangeResponse.self, from: data)
        guard payload.sessionToken.count >= 32,
              let expiration = parseISO8601(payload.expiresAt),
              let host = baseURL?.host,
              let appleSubject,
              StyleMatchAccountSessionAuthority.isValidAppleSubject(appleSubject) else {
            throw StyleMatchAccountError.invalidResponse
        }
        return StyleMatchAccountSession(
            token: payload.sessionToken,
            expiresAt: expiration,
            appleSubject: appleSubject,
            accountID: payload.accountID,
            endpointHost: host
        )
    }

    func signOut(session accountSession: StyleMatchAccountSession) async throws {
        var request = try request(path: "/v1/auth/logout", method: "POST")
        request.setValue("Bearer \(accountSession.token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await perform(request)
        guard response.statusCode == 204 else { throw mappedError(data: data, status: response.statusCode) }
    }

    func deleteAccount(session accountSession: StyleMatchAccountSession) async throws {
        var request = try request(path: "/v1/account", method: "DELETE")
        request.setValue("Bearer \(accountSession.token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await perform(request)
        guard response.statusCode == 204 else { throw mappedError(data: data, status: response.statusCode) }
    }

    private func request(path: String, method: String) throws -> URLRequest {
        guard let baseURL else {
            throw StyleMatchAccountError.configurationUnavailable
        }
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return request
    }

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw StyleMatchAccountError.invalidResponse
            }
            return (data, response)
        } catch let error as StyleMatchAccountError {
            throw error
        } catch {
            throw StyleMatchAccountError.serviceUnavailable
        }
    }

    private func mappedError(data: Data, status: Int) -> StyleMatchAccountError {
        let code = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.error
        if code == "apple_reauthentication_required" { return .reauthenticationRequired }
        if code == "apple_credential_invalid" { return .credentialVerificationFailed }
        if status == 401 { return .unauthorized }
        return .serviceUnavailable
    }

    private func utf8(_ data: Data?) -> String? {
        guard let data,
              let value = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    private func parseISO8601(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
