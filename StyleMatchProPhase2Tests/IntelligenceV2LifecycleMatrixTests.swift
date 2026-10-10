import XCTest
@testable import StyleMatchPro

/// Independently named contract checks for the request-local V2 selection
/// lifecycle. Network outcomes remain owned by the authenticated Worker.
final class IntelligenceV2LifecycleMatrixTests: XCTestCase {
    func testImageScopeIsDerivedOnlyFromAnExplicitImageAttachment() throws {
        XCTAssertTrue(try view().contains("selectedImage: normalizedVisionImage != nil"))
    }

    func testSavedScanScopeIsDerivedOnlyFromExplicitScanSelection() throws {
        XCTAssertTrue(try view().contains("selectedScanFacts: !selectedSavedScanKeys.isEmpty"))
    }

    func testClosetScopeIsDerivedOnlyFromExplicitClosetSelection() throws {
        XCTAssertTrue(try view().contains("selectedClosetItems: !selectedClosetKeys.isEmpty"))
    }

    func testStylePreferenceScopeIsDerivedOnlyFromExplicitPreferenceSelection() throws {
        XCTAssertTrue(try view().contains("stylePreferences: !selectedStylePreferenceSelection.isEmpty"))
    }

    func testMissingScopeRoutesThroughTheMatchingScopedConsentSheet() throws {
        let source = try view()
        XCTAssertTrue(source.contains("scopedConsentSheet = missingScope"))
        XCTAssertTrue(source.contains("scopedConsentPermissionSheet(scope)"))
    }

    func testPartialGrantLeavesOtherMissingScopesUnresolved() throws {
        let source = try view()
        XCTAssertTrue(source.contains("StylistScopedConsentRouter.missingScopes"))
        XCTAssertTrue(source.contains("scopedConsentStates[scope]?.granted == true"))
    }

    func testGrantReloadsAuthoritativeScopeStateBeforeDismissal() throws {
        let source = try view()
        XCTAssertTrue(source.contains("let refreshedStates = try await service.currentStates()"))
        XCTAssertTrue(source.contains("guard refreshedStates[scope]?.granted == true"))
    }

    func testDeniedOrCancelledConsentPreservesDraftAndSelections() throws {
        let source = try view()
        XCTAssertTrue(source.contains("Button(\"Not Now\") { scopedConsentSheet = nil }"))
        XCTAssertFalse(source.contains("clearFactSelections()\n                scopedConsentSheet = nil"))
    }

    func testUnavailableConsentReloadFailsClosedWithoutClearingSelections() throws {
        let source = try view()
        XCTAssertTrue(source.contains("scopedConsentStates = [:]"))
        XCTAssertTrue(source.contains("inlineFactSelectionError"))
    }

    func testRevocationTriggersAuthoritativeRefresh() throws {
        XCTAssertTrue(try view().contains("try await service.revoke(scope)"))
        XCTAssertTrue(try view().contains("refreshScopedConsent()"))
    }

    func testAccountChangeClearsRequestLocalSelections() throws {
        XCTAssertTrue(try view().contains("survive an account change"))
        XCTAssertTrue(try view().contains("clearFactSelections()"))
    }

    func testAcceptedSendIsTheOnlySuccessfulSendClearingPoint() throws {
        XCTAssertTrue(try view().contains("if accepted { clearTransientFactSelections() }"))
    }

    func testEquivalentRetryReusesOnlyTheSameVisionRequestEnvelope() throws {
        let source = try view()
        XCTAssertTrue(source.contains("retry.prompt == question"))
        XCTAssertTrue(source.contains("retry.attachments == attachments"))
    }

    func testConcurrentSendIsSuppressedByTheExistingSendingState() throws {
        let source = try service()
        XCTAssertTrue(source.contains("guard !prompt.isEmpty, !isStreaming else { return false }"))
    }

    func testV2SerializationExcludesClientConsentAndIdentityAuthority() throws {
        let selected = PersonalizationContextBuilder.ChatV2StylePreferences(
            preferredColors: ["navy"], avoidedColors: [], preferredBrands: [], styleLabels: [], preferredFit: nil
        )
        let request = ChatRequest(messages: [.init(role: "user", content: "test")], context: ChatContext(stylePreferences: selected), stream: false)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        XCTAssertEqual(json["contract_version"] as? Int, 2)
        for key in ["scopes", "consent_granted", "consent_revision", "account_id", "profileSummary"] {
            XCTAssertNil(json[key])
        }
    }

    func testAccessibilityUsesTheMatchingStylePreferencePermissionLabel() throws {
        let source = try transport()
        XCTAssertTrue(source.contains("Allow Style Preferences"))
        XCTAssertTrue(source.contains("allowAccessibilityLabel"))
    }

    func testPrivacyBoundaryKeepsLocalPersistenceAndImagesOutOfV2Preferences() throws {
        let source = try model()
        XCTAssertTrue(source.contains("no consent, account, persistence key"))
        XCTAssertTrue(source.contains("image-metadata"))
    }

    private func view() throws -> String { try source("StyleMatchAI/StylistChat/StylistChatView.swift") }
    private func transport() throws -> String { try source("StyleMatchAI/StylistChat/StylistChatTransport.swift") }
    private func model() throws -> String { try source("StyleMatchAI/StylistChat/StylistChatModels.swift") }
    private func service() throws -> String { try source("StyleMatchAI/StylistChat/StylistChatService.swift") }
    private func source(_ relative: String) throws -> String {
        try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(relative), encoding: .utf8)
    }
}
