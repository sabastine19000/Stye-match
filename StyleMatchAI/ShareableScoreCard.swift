import CryptoKit
import Foundation
#if canImport(UIKit)
import UIKit
#endif

struct ShareableScoreCardEnabledSections: Codable, Equatable {
    var photo: Bool
    var overallScore: Bool
    var categoryScores: Bool
    var notes: Bool
    var recommendations: Bool
    var scanDate: Bool
}

struct ShareableScoreCardCategoryScore: Codable, Equatable, Identifiable {
    var title: String
    var value: String
    var id: String { "\(title):\(value)" }
}

struct ShareableScoreCardPhoto: Codable, Equatable {
    let mimeType: String
    let base64: String
}

struct ShareableScoreCardCreatePayload: Encodable, Equatable {
    let appCardVersion: String
    let enabledSections: ShareableScoreCardEnabledSections
    let overallScore: Int?
    let scoreTitle: String?
    let categoryScores: [ShareableScoreCardCategoryScore]?
    let outfitDescription: String?
    let recommendations: [String]?
    let scanDate: String?
    let photo: ShareableScoreCardPhoto?

    init(
        appCardVersion: String = "1",
        enabledSections: ShareableScoreCardEnabledSections,
        overallScore: Int?,
        scoreTitle: String?,
        categoryScores: [ShareableScoreCardCategoryScore],
        outfitDescription: String,
        recommendations: [String],
        scanDate: Date,
        photo: ShareableScoreCardPhoto?
    ) {
        self.appCardVersion = appCardVersion
        self.enabledSections = enabledSections
        self.overallScore = enabledSections.overallScore ? overallScore : nil
        self.scoreTitle = enabledSections.overallScore ? scoreTitle : nil
        self.categoryScores = enabledSections.categoryScores ? categoryScores : nil
        self.outfitDescription = enabledSections.notes ? outfitDescription : nil
        self.recommendations = enabledSections.recommendations ? Array(recommendations.prefix(3)) : nil
        self.scanDate = enabledSections.scanDate ? ISO8601DateFormatter().string(from: scanDate) : nil
        self.photo = enabledSections.photo ? photo : nil
    }
}

struct SharedScoreCard: Decodable, Equatable {
    struct Sections: Decodable, Equatable {
        let appCardVersion: String
        let createdWith: String
        let enabledSections: ShareableScoreCardEnabledSections
        let overallScore: Int?
        let scoreTitle: String?
        let categoryScores: [ShareableScoreCardCategoryScore]?
        let outfitDescription: String?
        let recommendations: [String]?
        let scanDate: String?
    }

    let token: String
    let sections: Sections
    let hasPhoto: Bool
    let photoURL: String?
    let createdAt: String
    let expiresAt: String

    enum CodingKeys: String, CodingKey {
        case token
        case sections
        case hasPhoto = "has_photo"
        case photoURL = "photo_url"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
    }
}

struct ShareableScoreCardCreateResponse: Decodable, Equatable {
    let token: String
    let url: URL
    let creatorManagementToken: String
    let expiresAt: String

    enum CodingKeys: String, CodingKey {
        case token
        case url
        case creatorManagementToken = "creator_management_token"
        case expiresAt = "expires_at"
    }
}

enum ShareableScoreCardError: LocalizedError, Equatable {
    case configurationUnavailable
    case unauthorized
    case unavailable
    case rateLimited
    case invalidResponse
    case network

    var errorDescription: String? {
        switch self {
        case .configurationUnavailable:
            return "Link sharing is not configured yet."
        case .unauthorized:
            return "Please try again after reopening StyleMatch Pro."
        case .unavailable:
            return "This shared card is unavailable."
        case .rateLimited:
            return "You’ve shared several cards recently. Please try again later."
        case .invalidResponse, .network:
            return "We couldn’t prepare the share link. Please try again."
        }
    }
}

struct ShareableScoreCardRoute: Equatable {
    let token: String

    static func parse(_ url: URL) -> ShareableScoreCardRoute? {
        guard url.scheme?.lowercased() == "https",
              let host = url.host,
              !host.isEmpty else {
            return nil
        }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 2,
              parts[0] == "share",
              isSafeToken(parts[1]) else {
            return nil
        }
        return ShareableScoreCardRoute(token: parts[1])
    }

    static func isSafeToken(_ token: String) -> Bool {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")
        return token.count >= 32 && token.count <= 128 && token.rangeOfCharacter(from: allowed.inverted) == nil
    }
}

extension ShareableScoreCardRoute: Identifiable {
    var id: String { token }
}

struct ShareableScoreCardConfiguration {
    let baseURL: URL
    let cardAppSharedSecret: String?

    static var production: ShareableScoreCardConfiguration? {
        let backend = AppBackendConfiguration.production()
        return ShareableScoreCardConfiguration(
            baseURL: backend.apiBaseURL,
            cardAppSharedSecret: backend.cardAppSharedSecret
        )
    }
}

struct ShareableScoreCardClient {
    private let configuration: ShareableScoreCardConfiguration
    private let session: URLSession
    private let accountSession: () -> StyleMatchAccountSession?
    private let defaults: UserDefaults

    init(
        configuration: ShareableScoreCardConfiguration,
        session: URLSession = .shared,
        accountSession: @escaping () -> StyleMatchAccountSession? = StyleMatchAccountSessionStore.load,
        defaults: UserDefaults = .standard
    ) {
        self.configuration = configuration
        self.session = session
        self.accountSession = accountSession
        self.defaults = defaults
    }

    func create(_ payload: ShareableScoreCardCreatePayload) async throws -> ShareableScoreCardCreateResponse {
        var request = try makeRequest(path: "/v1/cards", method: "POST", requiresDeviceAuth: true)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)
        let (data, response) = try await perform(request)
        guard response.statusCode == 201 else { throw mappedError(status: response.statusCode) }
        return try JSONDecoder().decode(ShareableScoreCardCreateResponse.self, from: data)
    }

    func fetch(token: String) async throws -> SharedScoreCard {
        guard ShareableScoreCardRoute.isSafeToken(token) else { throw ShareableScoreCardError.unavailable }
        let request = try makeRequest(path: "/v1/cards/\(token)", method: "GET", requiresDeviceAuth: false)
        let (data, response) = try await perform(request)
        guard response.statusCode == 200 else { throw mappedError(status: response.statusCode) }
        return try JSONDecoder().decode(SharedScoreCard.self, from: data)
    }

    func revoke(token: String, managementToken: String) async throws {
        guard ShareableScoreCardRoute.isSafeToken(token), ShareableScoreCardRoute.isSafeToken(managementToken) else {
            throw ShareableScoreCardError.unavailable
        }
        var request = try makeRequest(path: "/v1/cards/\(token)", method: "DELETE", requiresDeviceAuth: true)
        request.setValue(managementToken, forHTTPHeaderField: "X-Card-Management-Token")
        let (_, response) = try await perform(request)
        guard response.statusCode == 200 else { throw mappedError(status: response.statusCode) }
    }

    private func makeRequest(path: String, method: String, requiresDeviceAuth: Bool) throws -> URLRequest {
        var request = URLRequest(url: configuration.baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.timeoutInterval = 18
        request.cachePolicy = .reloadIgnoringLocalCacheData

        if let accountSession = accountSession(), accountSession.expiresAt > Date() {
            request.setValue("Bearer \(accountSession.token)", forHTTPHeaderField: "Authorization")
        }

        if requiresDeviceAuth {
            guard let secret = cleanSecret(configuration.cardAppSharedSecret) else {
                throw ShareableScoreCardError.configurationUnavailable
            }
            let deviceHash = StylistChatAuthHeaders.deviceHash(defaults: defaults)
            let minute = Int(Date().timeIntervalSince1970 / 60)
            let signature = HMAC<SHA256>.authenticationCode(
                for: Data("\(deviceHash).\(minute)".utf8),
                using: SymmetricKey(data: Data(secret.utf8))
            ).map { String(format: "%02x", $0) }.joined()
            request.setValue(deviceHash, forHTTPHeaderField: "X-Device-Hash")
            request.setValue(signature, forHTTPHeaderField: "X-App-Auth")
        }

        return request
    }

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw ShareableScoreCardError.invalidResponse }
            return (data, http)
        } catch let error as ShareableScoreCardError {
            throw error
        } catch {
            throw ShareableScoreCardError.network
        }
    }

    private func mappedError(status: Int) -> ShareableScoreCardError {
        switch status {
        case 401:
            return .unauthorized
        case 404:
            return .unavailable
        case 429:
            return .rateLimited
        default:
            return .invalidResponse
        }
    }

    private func cleanSecret(_ value: String?) -> String? {
        AppBackendConfiguration.cleanSecret(value)
    }
}

struct CreatedShareableScoreCard: Codable, Identifiable, Equatable {
    let token: String
    let url: URL
    let creatorManagementToken: String
    let createdAt: Date
    let expiresAt: Date
    var revokedAt: Date?

    var id: String { token }
}

struct ShareableScoreCardLocalStore {
    static let baseKey = "shareableScoreCards"

    private let defaults: UserDefaults
    private let userID: String

    init(defaults: UserDefaults = .standard, userID: String? = nil) {
        self.defaults = defaults
        self.userID = PersonalStylistStorage.normalizedUserID(userID ?? PersonalStylistStorage.activeUserID(defaults: defaults))
    }

    var cards: [CreatedShareableScoreCard] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([CreatedShareableScoreCard].self, from: data) else {
            return []
        }
        return decoded.sorted { $0.createdAt > $1.createdAt }
    }

    func saveCreatedCard(token: String, url: URL, managementToken: String, expiresAt: String) {
        let parser = ISO8601DateFormatter()
        let expiration = parser.date(from: expiresAt) ?? Date().addingTimeInterval(30 * 86_400)
        var existing = cards.filter { $0.token != token }
        existing.insert(CreatedShareableScoreCard(
            token: token,
            url: url,
            creatorManagementToken: managementToken,
            createdAt: Date(),
            expiresAt: expiration,
            revokedAt: nil
        ), at: 0)
        save(existing)
    }

    func markRevoked(token: String) {
        var updated = cards
        guard let index = updated.firstIndex(where: { $0.token == token }) else { return }
        updated[index].revokedAt = Date()
        save(updated)
    }

    private var key: String {
        PersonalStylistStorage.scopedKey(Self.baseKey, userID: userID)
    }

    private func save(_ cards: [CreatedShareableScoreCard]) {
        guard let data = try? JSONEncoder().encode(cards) else { return }
        defaults.set(data, forKey: key)
    }
}

#if canImport(UIKit)
extension UIImage {
    func shareableScoreCardJPEGData() -> Data? {
        let pixelWidth = size.width * scale
        let pixelHeight = size.height * scale
        let largestPixelDimension = max(pixelWidth, pixelHeight)
        guard largestPixelDimension > 1_600, largestPixelDimension > 0 else {
            return jpegData(compressionQuality: 0.78)
        }

        let resizeScale = 1_600 / largestPixelDimension
        let targetSize = CGSize(width: max(1, pixelWidth * resizeScale), height: max(1, pixelHeight * resizeScale))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let resized = renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return resized.jpegData(compressionQuality: 0.78)
    }
}
#endif
