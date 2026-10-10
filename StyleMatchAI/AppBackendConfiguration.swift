import Foundation

struct AppBackendConfiguration: Equatable {
    static let defaultAPIBaseURL = URL(string: "https://api.stylematchpro.com")!
    static let defaultShareDomain = "stylematchpro.com"
    static let approvedProductionAPIHost = "api.stylematchpro.com"
    static let approvedStagingAPIHost = "stylematch-affiliate-proxy-staging.sabastine-7000.workers.dev"
    #if DEBUG || OWNER_BETA || TESTFLIGHT_BETA
    /// This host is compiled only into explicit Debug, OwnerBeta, or TestFlight beta artifacts.
    /// It is available only to narrowly scoped Style Friends acceptance lanes.
    static let approvedFriendsAuthTestAPIHost = "stylematch-18038-friends-auth-test.sabastine-7000.workers.dev"
    /// Dedicated Worker/D1 host for the explicitly configured Debug or OwnerBeta
    /// Style Friends lane. This is not a production endpoint or shared test host.
    static let approvedFriendsStagingAPIHost = "stylematch-friends-staging.sabastine-7000.workers.dev"
    #endif

    /// The single authority for the Build 18039 owner-beta Friends/DM/Support
    /// and development-APNs host. Release deliberately compiles this method as
    /// a fail-closed `false` result: a staging host is never a Release route.
    static func isAuthorizedFriendsStagingHost(_ host: String?) -> Bool {
        #if DEBUG || OWNER_BETA || TESTFLIGHT_BETA
        host?.lowercased() == approvedFriendsStagingAPIHost
        #else
        false
        #endif
    }

    let apiBaseURL: URL
    let shareDomain: String

    init(
        apiBaseURL: URL = Self.defaultAPIBaseURL,
        shareDomain: String = Self.defaultShareDomain
    ) {
        self.apiBaseURL = apiBaseURL
        self.shareDomain = shareDomain
    }

    static func production(bundle: Bundle = .main) -> AppBackendConfiguration {
        AppBackendConfiguration(
            apiBaseURL: configuredAPIBaseURL(bundle: bundle),
            shareDomain: configuredShareDomain(bundle: bundle)
        )
    }

    static func configuredAPIBaseURL(bundle: Bundle = .main) -> URL {
        guard let value = bundle.object(forInfoDictionaryKey: "STYLEMATCH_API_BASE_URL") as? String,
              let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "https",
              allowedConfiguredAPIHosts.contains(url.host?.lowercased() ?? "") else {
            return defaultAPIBaseURL
        }
        return url
    }

    private static var allowedConfiguredAPIHosts: Set<String> {
        #if DEBUG || OWNER_BETA || TESTFLIGHT_BETA
        [approvedProductionAPIHost, approvedFriendsStagingAPIHost]
        #else
        [approvedProductionAPIHost]
        #endif
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
        allowsOverride: Bool = compiledDebugOverrideEnabled,
        allowsPrivateLANOverride: Bool = true
    ) -> StyleMatchRuntimeEndpointResolution? {
        guard let defaultURL else { return nil }
        guard allowsOverride,
              let rawValue = environment[overrideEnvironmentKey] else {
            return StyleMatchRuntimeEndpointResolution(
                baseURL: defaultURL,
                overrideActive: false
            )
        }
        guard let overrideURL = validatedOverrideURL(
            rawValue,
            allowsPrivateLANOverride: allowsPrivateLANOverride
        ) else {
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
        resolve(
            defaultURL: defaultURL,
            environment: environment,
            allowsOverride: allowsOverride,
            allowsPrivateLANOverride: false
        )
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
    }
    #endif

    private static var compiledDebugOverrideEnabled: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    private static func validatedOverrideURL(
        _ rawValue: String,
        allowsPrivateLANOverride: Bool = true
    ) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              let host = components.host?.lowercased(),
              components.path.isEmpty || components.path == "/" else {
            return nil
        }

        if components.scheme?.lowercased() == "https",
           components.port == nil,
           approvedDebugHTTPSHosts.contains(host) {
            return components.url
        }

        guard allowsPrivateLANOverride,
              components.scheme?.lowercased() == "http",
              components.port != nil,
              isPrivateLANHost(host) else {
            return nil
        }
        return components.url
    }

    private static var approvedDebugHTTPSHosts: Set<String> {
        #if DEBUG
        [
            AppBackendConfiguration.approvedStagingAPIHost,
            AppBackendConfiguration.approvedFriendsAuthTestAPIHost,
            AppBackendConfiguration.approvedFriendsStagingAPIHost
        ]
        #else
        []
        #endif
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

struct StyleMatchLiveClientEndpointFactory {
    let chatResolution: StyleMatchRuntimeEndpointResolution?
    let accountResolution: StyleMatchRuntimeEndpointResolution?

    init(
        defaultChatConfiguration: StylistChatConfiguration? = .production,
        defaultAccountURL: URL? = AppBackendConfiguration.production().apiBaseURL,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        allowsOverride: Bool
    ) {
        chatResolution = StyleMatchRuntimeEndpoint.chatResolution(
            defaultConfiguration: defaultChatConfiguration,
            environment: environment,
            allowsOverride: allowsOverride
        )
        accountResolution = StyleMatchRuntimeEndpoint.accountResolution(
            defaultURL: defaultAccountURL,
            environment: environment,
            allowsOverride: allowsOverride
        )
    }

    static func current(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> StyleMatchLiveClientEndpointFactory {
        StyleMatchLiveClientEndpointFactory(
            environment: environment,
            allowsOverride: compiledDebugOverrideEnabled
        )
    }

    var chatConfiguration: StylistChatConfiguration? {
        chatResolution.map { StylistChatConfiguration(baseURL: $0.baseURL) }
    }

    var accountBaseURL: URL? {
        accountResolution?.baseURL
    }

    private static var compiledDebugOverrideEnabled: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }
}

/// Retained-data construction is intentionally independent from live network
/// routing. Debug transport selection must never select a different customer
/// data namespace.
struct StyleMatchRetainedDataComposition {
    let defaults: UserDefaults
    let environment: AccountStorageEnvironment

    init(
        defaults: UserDefaults = .standard,
        environment: AccountStorageEnvironment = .canonicalApplicationScope
    ) {
        self.defaults = defaults
        self.environment = environment
    }

    @discardableResult
    func prepareForLaunch() -> Bool {
        AccountScopedStorage.prepareForLaunch(
            defaults: defaults,
            environment: environment
        )
    }

    func makeProfileStore(userID: String? = nil) -> ProfileStore {
        ProfileStore(defaults: defaults, userId: userID)
    }

    func makeOutfitMemoryStore(userID: String? = nil) -> OutfitMemoryStore {
        OutfitMemoryStore(defaults: defaults, userId: userID)
    }

    func makeChatConversationStore(
        fileURL: URL? = nil,
        userID: String? = nil
    ) -> ChatConversationStore {
        ChatConversationStore(fileURL: fileURL, userID: userID)
    }
}

struct StyleMatchApplicationComposition {
    let liveClientEndpoints: StyleMatchLiveClientEndpointFactory
    let retainedData: StyleMatchRetainedDataComposition

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        allowsTransportOverride: Bool,
        defaults: UserDefaults = .standard,
        retainedDataEnvironment: AccountStorageEnvironment = .canonicalApplicationScope
    ) {
        liveClientEndpoints = StyleMatchLiveClientEndpointFactory(
            environment: environment,
            allowsOverride: allowsTransportOverride
        )
        retainedData = StyleMatchRetainedDataComposition(
            defaults: defaults,
            environment: retainedDataEnvironment
        )
    }

    static func current(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaults: UserDefaults = .standard
    ) -> StyleMatchApplicationComposition {
        StyleMatchApplicationComposition(
            environment: environment,
            allowsTransportOverride: compiledDebugOverrideEnabled,
            defaults: defaults
        )
    }

    private static var compiledDebugOverrideEnabled: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }
}
