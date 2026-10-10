import XCTest
import Security
@testable import StyleMatchPro

final class IntelligenceV2SelectionTests: XCTestCase {
    private final class KeychainDeleteSpy: LegacyProviderCredentialSecurityClient {
        var statuses: [OSStatus]
        private(set) var queries: [[String: Any]] = []

        init(statuses: [OSStatus]) {
            self.statuses = statuses
        }

        func delete(_ query: [String: Any]) -> OSStatus {
            queries.append(query)
            return statuses.isEmpty ? errSecSuccess : statuses.removeFirst()
        }
    }

    private func encoded(_ context: ChatContext) throws -> [String: Any] {
        let request = ChatRequest(messages: [.init(role: "user", content: "Help me choose an outfit")], context: context, stream: false)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
    }

    func testV1ContextHasNoVersionOrStylePreferencesByDefault() throws {
        let body = try encoded(ChatContext())
        XCTAssertNil(body["contract_version"])
        let context = try XCTUnwrap(body["context"] as? [String: Any])
        XCTAssertNil(context["stylePreferences"])
    }

    func testExplicitStylePreferencesEmitOnlyV2AllowlistedValues() throws {
        let selected = PersonalizationContextBuilder.ChatV2StylePreferences(
            preferredColors: ["navy"], avoidedColors: ["orange"], preferredBrands: ["Acme"], styleLabels: ["minimal"], preferredFit: "tailored"
        )
        let body = try encoded(ChatContext(stylePreferences: selected))
        XCTAssertEqual(body["contract_version"] as? Int, 2)
        let context = try XCTUnwrap(body["context"] as? [String: Any])
        let preferences = try XCTUnwrap(context["stylePreferences"] as? [String: Any])
        XCTAssertEqual(preferences["preferredColors"] as? [String], ["navy"])
        XCTAssertEqual(preferences["avoidedColors"] as? [String], ["orange"])
        XCTAssertEqual(preferences["preferredBrands"] as? [String], ["Acme"])
        XCTAssertEqual(preferences["styleLabels"] as? [String], ["minimal"])
        XCTAssertEqual(preferences["preferredFit"] as? String, "tailored")
        for forbidden in ["profileSummary", "account_id", "localRecordKey", "image", "consent_granted", "scopes"] {
            XCTAssertNil(preferences[forbidden])
        }
    }

    func testStylePreferenceProjectionIsRequestLocalAndDefaultOff() throws {
        let selection = PersonalizationContextBuilder.VisionStylePreferenceSelection.empty
        XCTAssertTrue(selection.isEmpty)
        XCTAssertNil(try PersonalizationContextBuilder.chatV2StylePreferences(selection: selection, currentProfile: profile()))
    }

    func testStaleStylePreferenceSelectionFailsClosed() {
        let selection = PersonalizationContextBuilder.VisionStylePreferenceSelection(
            preferredColors: ["stale"], avoidedColors: [], preferredFits: [], preferredStyles: [], preferredBrands: []
        )
        XCTAssertThrowsError(try PersonalizationContextBuilder.chatV2StylePreferences(selection: selection, currentProfile: profile()))
    }

    func testConsentAndSelectionLifecycleAreExplicitInComposer() throws {
        let source = try String(contentsOf: projectURL("StyleMatchAI/StylistChat/StylistChatView.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("routeMissingScopedConsentIfNeeded"))
        XCTAssertTrue(source.contains("stylePreferences: !selectedStylePreferenceSelection.isEmpty"))
        XCTAssertTrue(source.contains("refreshScopedConsent"))
        XCTAssertTrue(source.contains("if accepted { clearTransientFactSelections() }"))
        let transport = try String(contentsOf: projectURL("StyleMatchAI/StylistChat/StylistChatTransport.swift"), encoding: .utf8)
        XCTAssertTrue(transport.contains("Allow Style Preferences"))
        XCTAssertTrue(source.contains("Remove selected style preferences"))
    }

    func testTransportDoesNotReadProfilePersistenceForV2() throws {
        let transport = try String(contentsOf: projectURL("StyleMatchAI/StylistChat/StylistChatTransport.swift"), encoding: .utf8)
        XCTAssertFalse(transport.contains("ProfileStore"))
        XCTAssertFalse(transport.contains("profileSummary"))
        XCTAssertTrue(transport.contains("case stylePreferences = \"style_preferences\""))
    }

    func testSelectedScanAndClosetWireKeysRemainPresent() throws {
        let context = ChatContext(stylistFactContext: .init(version: 1, closetItems: [.init(alias: "a1b2c3d4", category: "Loafers", color: "brown", brand: nil, occasion: nil)], savedScans: []))
        let body = try encoded(context)
        let nested = try XCTUnwrap(body["context"] as? [String: Any])
        XCTAssertNotNil(nested["stylist_context"])
        XCTAssertNil(body["contract_version"])
    }

    func testLegacyProviderCleanupDeletesOnlyHistoricalGenericPasswordIdentity() {
        let defaults = retirementDefaults()
        let security = KeychainDeleteSpy(statuses: [errSecSuccess])

        LegacyProviderCredentialRetirement.run(bundleIdentifier: "com.sabastine.stylematchai", defaults: defaults, security: security)

        XCTAssertEqual(security.queries.count, 1)
        let query = security.queries[0]
        XCTAssertEqual(query[kSecClass as String] as? String, kSecClassGenericPassword as String)
        XCTAssertEqual(query[kSecAttrService as String] as? String, "com.sabastine.stylematchai.openai")
        XCTAssertEqual(query[kSecAttrAccount as String] as? String, "openai-api-key")
        XCTAssertEqual(query.count, 3)
        XCTAssertTrue(defaults.bool(forKey: "legacyProviderCredentialRetirementV1Complete"))
    }

    func testLegacyProviderCleanupDoesNotIssueAValueReadOperation() throws {
        let source = try String(contentsOf: projectURL("StyleMatchAI/LegacyProviderCredentialRetirement.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("SecItemDelete"))
        XCTAssertFalse(source.contains("SecItemCopyMatching"))
        XCTAssertFalse(source.contains("kSecReturnData"))
        XCTAssertFalse(source.contains("SecItemAdd"))
        XCTAssertFalse(source.contains("SecItemUpdate"))
    }

    func testLegacyProviderCleanupCannotTargetAnotherServiceBecauseItsQueryHasNoWildcard() {
        let defaults = retirementDefaults()
        let security = KeychainDeleteSpy(statuses: [errSecSuccess])

        LegacyProviderCredentialRetirement.run(bundleIdentifier: "com.sabastine.stylematchai", defaults: defaults, security: security)

        let query = security.queries[0]
        XCTAssertNotEqual(query[kSecAttrService as String] as? String, "com.sabastine.stylematchai.session")
        XCTAssertNil(query[kSecAttrAccessGroup as String])
        XCTAssertNil(query[kSecAttrSynchronizable as String])
        XCTAssertEqual(query.count, 3)
    }

    func testLegacyProviderCleanupCannotTargetAnotherAccountBecauseHistoricalAccountIsExact() {
        let defaults = retirementDefaults()
        let security = KeychainDeleteSpy(statuses: [errSecSuccess])

        LegacyProviderCredentialRetirement.run(bundleIdentifier: "com.sabastine.stylematchai", defaults: defaults, security: security)

        XCTAssertEqual(security.queries[0][kSecAttrAccount as String] as? String, "openai-api-key")
        XCTAssertNotEqual(security.queries[0][kSecAttrAccount as String] as? String, "apple-user-token")
    }

    func testLegacyProviderCleanupTreatsItemNotFoundAsCompleteAndNeverRepeats() {
        let defaults = retirementDefaults()
        let security = KeychainDeleteSpy(statuses: [errSecItemNotFound, errSecSuccess])
        defaults.set("nonsecret-fixture", forKey: LegacyProviderCredentialRetirement.legacyFallbackKey)

        LegacyProviderCredentialRetirement.run(bundleIdentifier: "com.sabastine.stylematchai", defaults: defaults, security: security)
        LegacyProviderCredentialRetirement.run(bundleIdentifier: "com.sabastine.stylematchai", defaults: defaults, security: security)

        XCTAssertEqual(security.queries.count, 1)
        XCTAssertTrue(defaults.bool(forKey: "legacyProviderCredentialRetirementV1Complete"))
        XCTAssertNil(defaults.object(forKey: LegacyProviderCredentialRetirement.legacyFallbackKey))
    }

    func testLegacyProviderCleanupDoesNotMarkFailuresAndRetriesExactSameTarget() {
        let defaults = retirementDefaults()
        let security = KeychainDeleteSpy(statuses: [errSecAuthFailed, errSecSuccess])

        LegacyProviderCredentialRetirement.run(bundleIdentifier: "com.sabastine.stylematchai", defaults: defaults, security: security)
        XCTAssertFalse(defaults.bool(forKey: "legacyProviderCredentialRetirementV1Complete"))
        LegacyProviderCredentialRetirement.run(bundleIdentifier: "com.sabastine.stylematchai", defaults: defaults, security: security)

        XCTAssertEqual(security.queries.count, 2)
        XCTAssertEqual(security.queries[0][kSecAttrService as String] as? String, "com.sabastine.stylematchai.openai")
        XCTAssertEqual(security.queries[1][kSecAttrAccount as String] as? String, "openai-api-key")
        XCTAssertTrue(defaults.bool(forKey: "legacyProviderCredentialRetirementV1Complete"))
    }

    func testLegacyProviderCleanupKeepsLockedFailuresRetryable() {
        let defaults = retirementDefaults()
        let security = KeychainDeleteSpy(statuses: [errSecInteractionNotAllowed])

        LegacyProviderCredentialRetirement.run(bundleIdentifier: "com.sabastine.stylematchai", defaults: defaults, security: security)

        XCTAssertEqual(security.queries.count, 1)
        XCTAssertFalse(defaults.bool(forKey: "legacyProviderCredentialRetirementV1Complete"))
    }

    private func projectURL(_ relative: String) -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(relative)
    }

    private func retirementDefaults() -> UserDefaults {
        let suite = "build18044-retirement-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func profile() -> StyleProfilePersonalizationContext {
        StyleProfilePersonalizationContext(
            styleGoals: [], favoriteColors: ["navy"], avoidedColors: [], favoriteBrands: [],
            declaredUndertone: nil, preferredFit: nil, preferredPantFit: nil,
            preferredNeutrals: [], preferredAccentColors: [], preferredPantRise: nil,
            clothingSizes: ClothingSizes(), comfortPreferences: [], budgetRange: nil,
            shoppingFocus: nil, preferredShoppingCategories: [], workSetting: nil,
            travelFrequency: nil, hobbiesActivities: [], stylistVoice: nil
        )
    }
}
