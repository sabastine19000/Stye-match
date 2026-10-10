import XCTest
@testable import StyleMatchPro

final class AskStyleMatchIntelligenceCoreTests: XCTestCase {
    func testV2FixtureMatchesExactStableWireMapping() throws {
        let request = AskStyleMatchRequest(
            clientRequestReference: UUID(uuidString: "5F0C1D22-7AC2-4C91-A4F6-3B830A2F1C30")!,
            modeSelection: .manual(.fashionStylist),
            question: "How can I style this?",
            localeIdentifier: "en_US",
            grantedScopes: [.scanSummary, .profilePreferences],
            scanFacts: .init(score: 84, classification: "smart_casual", summary: "Balanced outfit")
        )
        let encoded = try JSONEncoder().encode(AskStyleMatchV2WireRequest(request: request))
        let actual = try JSONSerialization.jsonObject(with: encoded) as? NSDictionary
        let url = try XCTUnwrap(Bundle.module.url(forResource: "ask_stylematch_v2_request", withExtension: "json"))
        let expected = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? NSDictionary
        XCTAssertEqual(actual, expected)
    }

    func testV2WriterOmitsAbsentFieldsAndSortsScopes() throws {
        let request = AskStyleMatchRequest(question: "What should I wear?", localeIdentifier: "en_US", grantedScopes: [.weatherOccasion, .budgetBrand])
        let data = try JSONEncoder().encode(AskStyleMatchV2WireRequest(request: request))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(json["scan_facts"])
        XCTAssertNil(json["selected_writing_text"])
        XCTAssertEqual(json["granted_scopes"] as? [String], ["budget_brand", "weather_occasion"])
    }
    func testManualFashionRouteUsesOnlyExplicitGrantedPersonalScopes() throws {
        let request = AskStyleMatchRequest(
            modeSelection: .manual(.fashionStylist),
            question: "Help with this completed scan",
            localeIdentifier: "en_US",
            grantedScopes: [.profilePreferences, .scanSummary],
            scanFacts: AskStyleMatchScanFacts(score: 84, classification: "smart_casual", summary: "Balanced outfit")
        )

        let route = try AskStyleMatchPolicyRouter.route(request)

        XCTAssertEqual(route.mode, .fashionStylist)
        XCTAssertEqual(route.permittedScopes, [.publicFashionKnowledge, .profilePreferences, .scanSummary])
        XCTAssertFalse(route.requiresClarification)
    }

    func testScanFactsRetainAuthoritativeValuesWithoutRecalculation() throws {
        let facts = AskStyleMatchScanFacts(score: 87, classification: "smart_casual", summary: "Exact authority summary")
        let request = AskStyleMatchRequest(
            modeSelection: .manual(.fashionStylist),
            question: "Explain this result",
            localeIdentifier: "en_US",
            grantedScopes: [.scanSummary],
            scanFacts: facts
        )

        _ = try AskStyleMatchIntelligenceCore.providerDescriptor(for: request)
        XCTAssertEqual(request.scanFacts, facts)
        XCTAssertEqual(request.scanFacts?.score, 87)
        XCTAssertEqual(request.scanFacts?.classification, "smart_casual")
        XCTAssertEqual(request.scanFacts?.summary, "Exact authority summary")
    }

    func testWritingAssistRejectsImplicitContextAndRequiresSelectedText() throws {
        let missingText = AskStyleMatchRequest(
            modeSelection: .manual(.writingAssist),
            question: "Rewrite it",
            localeIdentifier: "en_US",
            grantedScopes: [.selectedWritingText]
        )
        XCTAssertThrowsError(try AskStyleMatchPolicyRouter.route(missingText)) { error in
            XCTAssertEqual(error as? AskStyleMatchValidationError, .missingSelectedWritingText)
        }

        let request = AskStyleMatchRequest(
            modeSelection: .manual(.writingAssist),
            question: "Rewrite the selected caption",
            localeIdentifier: "en_US",
            grantedScopes: [.selectedWritingText, .profilePreferences, .scanSummary],
            selectedWritingText: "Nice look ✨"
        )
        let route = try AskStyleMatchPolicyRouter.route(request)
        XCTAssertEqual(route.mode, .writingAssist)
        XCTAssertEqual(route.permittedScopes, [.selectedWritingText])
    }

    func testAutomaticMultiIntentRequestRequiresClarification() throws {
        let request = AskStyleMatchRequest(
            question: "Rewrite my caption and explain these notification settings",
            localeIdentifier: "en_US"
        )

        let route = try AskStyleMatchPolicyRouter.route(request)
        XCTAssertTrue(route.requiresClarification)
    }

    func testCurrentResearchIsExplicitlyUnavailableAndNeverPermitted() throws {
        let request = AskStyleMatchRequest(
            modeSelection: .manual(.fashionStylist),
            question: "Research this season's fashion",
            localeIdentifier: "en_US",
            grantedScopes: [.currentResearch]
        )

        let route = try AskStyleMatchPolicyRouter.route(request)
        XCTAssertFalse(route.permittedScopes.contains(.currentResearch))
        XCTAssertEqual(route.unavailableCapabilityNotice, "Current research is unavailable in this local-only build.")
    }

    func testProviderDescriptorIsNonPersistentAndHasNoConversationReference() throws {
        let reference = UUID()
        let request = AskStyleMatchRequest(
            clientRequestReference: reference,
            question: "What should I wear?",
            localeIdentifier: "en_US"
        )

        let descriptor = try AskStyleMatchIntelligenceCore.providerDescriptor(for: request)
        XCTAssertEqual(descriptor.clientRequestReference, reference)
        XCTAssertFalse(descriptor.store)
        XCTAssertFalse(descriptor.background)
        XCTAssertNil(descriptor.conversationReference)
    }

    func testLocalProviderCannotPerformNetworkResponse() async throws {
        let request = AskStyleMatchRequest(question: "What should I wear?", localeIdentifier: "en_US")
        let descriptor = try AskStyleMatchIntelligenceCore.providerDescriptor(for: request)

        do {
            _ = try await AskStyleMatchLocalOnlyProvider().respond(to: descriptor)
            XCTFail("The local-only provider must not make a network request")
        } catch let error as AskStyleMatchProviderError {
            XCTAssertEqual(error, .unavailableInLocalBuild)
        }
    }

    func testPrivacyDisclosureListsOnlySelectedScopesAndExcludesRawImages() {
        let disclosure = AskStyleMatchPrivacyDisclosure.make(for: [.scanSummary, .profilePreferences])
        XCTAssertEqual(disclosure.selectedScopeLabels, ["Completed scan facts", "Profile preferences"])
        XCTAssertTrue(AskStyleMatchPrivacyDisclosure.imageStatement.contains("not included"))
        XCTAssertTrue(AskStyleMatchPrivacyDisclosure.processorStatement.contains("OpenAI"))
        XCTAssertTrue(AskStyleMatchPrivacyDisclosure.revocationStatement.contains("future transmissions"))
        XCTAssertFalse(AskStyleMatchPrivacyDisclosure.revocationStatement.lowercased().contains("zero retention"))
    }
}
