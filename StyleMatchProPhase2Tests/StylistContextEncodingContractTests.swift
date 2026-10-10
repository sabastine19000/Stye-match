import Foundation
import XCTest
@testable import StyleMatchPro

final class StylistContextEncodingContractTests: XCTestCase {
    func testRealEncoderMatchesPairedWorkerFixtureStructurally() throws {
        let encoded = try JSONEncoder().encode(Self.request)
        let fixtureURL = try XCTUnwrap(
            Bundle.module.url(
                forResource: "stylist_context_snapshot_v1",
                withExtension: "json"
            )
        )
        let fixture = try Data(contentsOf: fixtureURL)

        let actual = try XCTUnwrap(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let expected = try XCTUnwrap(try JSONSerialization.jsonObject(with: fixture) as? [String: Any])
        XCTAssertEqual(Set(actual.keys), ["messages", "context", "stream"])
        XCTAssertEqual((actual["messages"] as? [[String: Any]])?.count, (expected["messages"] as? [[String: Any]])?.count)
    }

    func testUnavailableAttachmentIsPresentAndUsesExplicitUnknownValues() throws {
        let request = ChatRequest(
            messages: [.init(role: "user", content: "What should I wear today?")],
            context: ChatContext(),
            stream: true
        )
        let data = try JSONEncoder().encode(request)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let context = try XCTUnwrap(root["context"] as? [String: Any])
        XCTAssertEqual(Set(context.keys), ["profileSummary", "recentOutfits", "activeScan", "historicalOutfits"])
        XCTAssertNil(context["stylistContextSnapshot"])
        XCTAssertNil(context["weatherConstraint"])
    }

    private static let request: ChatRequest = {
        let confirmedAt = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let workplace = WorkplaceContext(
            environment: .factoryOrManufacturing,
            dressCode: .safetyWorkwear,
            footwearConstraints: [.safetyToe],
            ppeRequirements: ["high-visibility vest"],
            activityLevel: .mostlyStandingOrWalking,
            exposure: .indoorVariableTemperature,
            floorAndOfficeMix: false,
            source: .explicitCurrentMessage,
            confirmation: .userConfirmed,
            lastConfirmedAt: confirmedAt
        )
        let weather = StylistWeatherContext(
            target: .current,
            condition: "sunny",
            temperatureFahrenheit: 83,
            observedAt: confirmedAt,
            validUntil: Date(timeIntervalSinceReferenceDate: 800_010_800)
        )
        let snapshot = StylistConversationSnapshot(
            scanID: "paired-fixture-scan",
            score: 80,
            breakdown: StylistScoreBreakdownSnapshot(
                colorHarmony: 22,
                patternBalance: 18,
                fitQuality: 20,
                occasionMatch: 14,
                accessoryUse: 6
            ),
            detectedStyle: "Casual",
            selectedOccasion: "Work",
            observedGarments: ["pants", "polo"],
            observedColors: ["khaki", "silver"],
            weather: weather,
            workplace: workplace
        )
        let attachment = StylistRouteContextAttachment(
            schemaVersion: 1,
            snapshot: snapshot,
            weather: StylistWeatherRequestContext(
                availability: .available,
                value: weather,
                constraint: "Hot-weather constraint: avoid heavy layers."
            ),
            workplace: StylistWorkplaceRequestContext(
                availability: .available,
                value: workplace
            ),
            uniform: StylistUniformRequestContext(
                availability: .available,
                dressCode: .safetyWorkwear,
                confirmation: .userConfirmed
            ),
            safety: StylistSafetyRequestContext(
                availability: .available,
                footwearConstraints: [.safetyToe],
                ppeRequirements: ["high-visibility vest"]
            )
        )
        return ChatRequest(
            messages: [.init(role: "user", content: "What should I wear today?")],
            context: ChatContext(
                weatherConstraint: "Hot-weather constraint: avoid heavy layers.",
                screenContext: .aiTab(),
                stylistContextSnapshot: attachment
            ),
            stream: true
        )
    }()
}
