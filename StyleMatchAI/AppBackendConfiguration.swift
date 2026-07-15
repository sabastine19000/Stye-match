import Foundation

struct AppBackendConfiguration: Equatable {
    static let defaultAPIBaseURL = URL(string: "https://api.stylematchpro.com")!
    static let defaultShareDomain = "stylematchpro.com"

    let apiBaseURL: URL
    let shareDomain: String
    let appSharedSecret: String?
    let cardAppSharedSecret: String?

    init(
        apiBaseURL: URL = Self.defaultAPIBaseURL,
        shareDomain: String = Self.defaultShareDomain,
        appSharedSecret: String? = nil,
        cardAppSharedSecret: String? = nil
    ) {
        self.apiBaseURL = apiBaseURL
        self.shareDomain = shareDomain
        self.appSharedSecret = Self.cleanSecret(appSharedSecret)
        self.cardAppSharedSecret = Self.cleanSecret(cardAppSharedSecret)
    }

    static func production(bundle: Bundle = .main) -> AppBackendConfiguration {
        AppBackendConfiguration(
            apiBaseURL: configuredAPIBaseURL(bundle: bundle),
            shareDomain: configuredShareDomain(bundle: bundle),
            appSharedSecret: bundle.object(forInfoDictionaryKey: "STYLIST_CHAT_APP_SHARED_SECRET") as? String,
            cardAppSharedSecret: bundle.object(forInfoDictionaryKey: "STYLEMATCH_CARD_APP_SHARED_SECRET") as? String
        )
    }

    static func configuredAPIBaseURL(bundle: Bundle = .main) -> URL {
        guard let value = bundle.object(forInfoDictionaryKey: "STYLEMATCH_API_BASE_URL") as? String,
              let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "https",
              url.host == "api.stylematchpro.com" else {
            return defaultAPIBaseURL
        }
        return url
    }

    static func configuredShareDomain(bundle: Bundle = .main) -> String {
        guard let value = bundle.object(forInfoDictionaryKey: "STYLEMATCH_SHARE_DOMAIN") as? String else {
            return defaultShareDomain
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed == defaultShareDomain else {
            return defaultShareDomain
        }
        return trimmed
    }

    static func cleanSecret(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.localizedCaseInsensitiveContains("replace_with"),
              !trimmed.localizedCaseInsensitiveContains("placeholder"),
              !trimmed.localizedCaseInsensitiveContains("pending"),
              !trimmed.localizedCaseInsensitiveContains("changeme") else {
            return nil
        }
        return trimmed
    }
}
