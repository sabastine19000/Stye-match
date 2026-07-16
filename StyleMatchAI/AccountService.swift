import CryptoKit
import Foundation
import Security

struct StyleMatchAccountSession: Codable, Equatable {
    let token: String
    let expiresAt: Date
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

    static func load() -> StyleMatchAccountSession? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else {
            return nil
        }
        return try? JSONDecoder().decode(StyleMatchAccountSession.self, from: data)
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

enum StyleMatchAccountSessionDiagnostics {
    static func log(stage: String, defaults: UserDefaults = .standard) {
        #if DEBUG
        let userID = defaults.string(forKey: "customerAppleUserID") ?? ""
        let userHash = userID.isEmpty ? "none" : String(StylistChatAuthHeaders.sha256Hex(userID).prefix(8))
        let session = StyleMatchAccountSessionStore.load()
        let expiration: String
        if let session {
            expiration = session.expiresAt > Date() ? "valid" : "expired"
        } else {
            expiration = "missing"
        }
        let mode = defaults.string(forKey: "customerAccountMode") ?? "unset"
        print("[StyleMatch Account] stage=\(stage) mode=\(mode) apple_user_hash=\(userHash) token_present=\(session != nil) expiration=\(expiration)")
        #endif
    }
}

struct StyleMatchAccountClient {
    private struct ExchangeResponse: Decodable {
        let sessionToken: String
        let expiresAt: String

        enum CodingKeys: String, CodingKey {
            case sessionToken = "session_token"
            case expiresAt = "expires_at"
        }
    }

    private struct ErrorResponse: Decodable {
        let error: String
    }

    private let baseURL: URL?
    private let session: URLSession

    init(
        baseURL: URL? = AppBackendConfiguration.production().apiBaseURL,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
    }

    func exchange(
        authorizationCode: Data?,
        identityToken: Data?,
        nonce: String
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
              let expiration = parseISO8601(payload.expiresAt) else {
            throw StyleMatchAccountError.invalidResponse
        }
        return StyleMatchAccountSession(token: payload.sessionToken, expiresAt: expiration)
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
