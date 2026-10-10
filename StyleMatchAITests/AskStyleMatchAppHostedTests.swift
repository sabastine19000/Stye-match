import XCTest
@testable import StyleMatchAI

final class AskStyleMatchAppHostedTests: XCTestCase {
    func testAppHostedCorePreparesNonPersistentFashionRequest() throws {
        let request = AskStyleMatchRequest(
            modeSelection: .manual(.fashionStylist),
            question: "Help me choose an outfit",
            localeIdentifier: "en_US",
            grantedScopes: [.profilePreferences]
        )

        let descriptor = try AskStyleMatchIntelligenceCore.providerDescriptor(for: request)

        XCTAssertEqual(descriptor.route.mode, .fashionStylist)
        XCTAssertEqual(descriptor.route.permittedScopes, [.publicFashionKnowledge, .profilePreferences])
        XCTAssertFalse(descriptor.store)
        XCTAssertFalse(descriptor.background)
        XCTAssertNil(descriptor.conversationReference)
    }

    func testAppHostedWritingRequestCannotAcquireFashionContext() throws {
        let request = AskStyleMatchRequest(
            modeSelection: .manual(.writingAssist),
            question: "Polish this message",
            localeIdentifier: "en_US",
            grantedScopes: [.selectedWritingText, .profilePreferences, .closetSummary],
            selectedWritingText: "Nice look ✨"
        )

        let descriptor = try AskStyleMatchIntelligenceCore.providerDescriptor(for: request)

        XCTAssertEqual(descriptor.route.mode, .writingAssist)
        XCTAssertEqual(descriptor.route.permittedScopes, [.selectedWritingText])
    }

    func testPrivacyDisclosurePreviewsOnlyChosenContextBeforeTransmission() {
        let disclosure = AskStyleMatchPrivacyDisclosure.make(for: [.closetSummary, .weatherOccasion])
        XCTAssertEqual(disclosure.selectedScopeLabels, ["Closet summary", "Weather and occasion"])
        XCTAssertTrue(AskStyleMatchPrivacyDisclosure.processorStatement.contains("OpenAI"))
        XCTAssertTrue(AskStyleMatchPrivacyDisclosure.imageStatement.contains("not included"))
        XCTAssertTrue(AskStyleMatchPrivacyDisclosure.revocationStatement.contains("future transmissions"))
        XCTAssertFalse(AskStyleMatchPrivacyDisclosure.revocationStatement.localizedCaseInsensitiveContains("zero retention"))
    }
}
