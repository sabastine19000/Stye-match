import Foundation

struct AppBackendConfiguration: Equatable {
    static let defaultAPIBaseURL = URL(string: "https://api.stylematchpro.com")!
    static let defaultShareDomain = "stylematchpro.com"
    static let approvedProductionAPIHost = "api.stylematchpro.com"
    static let approvedStagingAPIHost = "stylematch-affiliate-proxy-staging.sabastine-7000.workers.dev"

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

struct StyleMatchRuntimeEndpointResolution {
    let baseURL: URL
    let overrideActive: Bool
}

enum StyleMatchRuntimeEndpoint {
    static let overrideEnvironmentKey = "STYLEMATCH_API_BASE_URL_OVERRIDE"

    static func resolve(
        defaultURL: URL?,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        allowsOverride: Bool = compiledDebugOverrideEnabled
    ) -> StyleMatchRuntimeEndpointResolution? {
        guard let defaultURL else { return nil }
        guard allowsOverride,
              let rawValue = environment[overrideEnvironmentKey] else {
            return StyleMatchRuntimeEndpointResolution(
                baseURL: defaultURL,
                overrideActive: false
            )
        }
        guard let overrideURL = validatedPrivateLANURL(rawValue) else {
            return nil
        }
        return StyleMatchRuntimeEndpointResolution(
            baseURL: overrideURL,
            overrideActive: true
        )
    }

    static func accountResolution(
        defaultURL: URL? = AppBackendConfiguration.production().apiBaseURL,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        allowsOverride: Bool = compiledDebugOverrideEnabled
    ) -> StyleMatchRuntimeEndpointResolution? {
        resolve(defaultURL: defaultURL, environment: environment, allowsOverride: allowsOverride)
    }

    static func chatResolution(
        defaultConfiguration: StylistChatConfiguration? = StylistChatConfiguration.production,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        allowsOverride: Bool = compiledDebugOverrideEnabled
    ) -> StyleMatchRuntimeEndpointResolution? {
        resolve(
            defaultURL: defaultConfiguration?.baseURL,
            environment: environment,
            allowsOverride: allowsOverride
        )
    }

    #if DEBUG
    static func logLaunchConfiguration() {
        guard let resolution = chatResolution() else {
            print("[StyleMatch Runtime Backend] effective_base_url=missing override_active=false scope=chat+account configuration=Debug")
            return
        }
        print(
            "[StyleMatch Runtime Backend] effective_base_url=\(resolution.baseURL.absoluteString) " +
            "override_active=\(resolution.overrideActive) scope=chat+account configuration=Debug"
        )
    }
    #endif

    private static var compiledDebugOverrideEnabled: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    private static func validatedPrivateLANURL(_ rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "http",
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              components.port != nil,
              let host = components.host?.lowercased(),
              components.path.isEmpty || components.path == "/",
              isPrivateLANHost(host),
              let url = components.url else {
            return nil
        }
        return url
    }

    private static func isPrivateLANHost(_ host: String) -> Bool {
        if host == "localhost" || host == "127.0.0.1" { return true }
        let octets = host.split(separator: ".").compactMap { Int($0) }
        guard octets.count == 4, octets.allSatisfy({ 0...255 ~= $0 }) else { return false }
        if octets[0] == 10 { return true }
        if octets[0] == 172 && (16...31).contains(octets[1]) { return true }
        return octets[0] == 192 && octets[1] == 168
    }
}
