import XCTest
@testable import StyleMatchPro

final class ContextEngineCE1Tests: XCTestCase {
    private let completedAt = Date(timeIntervalSince1970: 1_753_200_000)

    func testLegacyRecordWithCompleteFieldsProducesTypedSnapshot() {
        let analysis = makeAnalysis(
            score: 80,
            classification: makeClassification(
                category: .businessCasual,
                confidence: 0.91,
                occasion: "Work",
                compatibility: .compatible,
                scoringProfile: .businessProfessional
            ),
            style: "Smart Casual",
            environment: "Office"
        )
        let weather = WeatherContextReference(
            observedAt: completedAt,
            airTemperature: 82,
            feelsLikeTemperature: 86,
            humidityPercent: 76,
            rainChancePercent: 10,
            windMph: 4,
            uvIndex: 5,
            condition: "Partly cloudy",
            confidence: ContextConfidence(value: 0.9, level: .high)
        )

        let snapshot = adapt(analysis, weather: weather)

        XCTAssertEqual(snapshot.authoritativeScore, 80)
        XCTAssertEqual(snapshot.detectedStyle.value, "Smart Casual")
        XCTAssertEqual(snapshot.garmentCategory.value, .businessCasual)
        XCTAssertEqual(snapshot.selectedOccasion.value, .work)
        XCTAssertEqual(snapshot.environmentType.value, .office)
        XCTAssertEqual(snapshot.occasionCompatibility.level, .high)
        XCTAssertEqual(snapshot.weatherContext, weather)
        XCTAssertTrue(snapshot.provenance.legacyFallbackUsed)
    }

    func testMissingOccasionRemainsExplicitlyUncertain() {
        let snapshot = adapt(makeAnalysis(classification: makeClassification(occasion: nil)))

        XCTAssertEqual(snapshot.selectedOccasion.value, .otherUncertain)
        XCTAssertEqual(snapshot.selectedOccasion.origin, .unknown)
        XCTAssertEqual(snapshot.selectedOccasion.confirmationState, .uncertain)
        XCTAssertTrue(snapshot.missingEvidence.contains { $0.kind == .occasion })
    }

    func testMissingWeatherRemainsExplicitlyUncertain() {
        let snapshot = adapt(makeAnalysis())

        XCTAssertFalse(snapshot.weatherContext.hasEvidence)
        XCTAssertEqual(snapshot.weatherSuitability.level, .uncertain)
        XCTAssertTrue(snapshot.missingEvidence.contains { $0.kind == .weather })
    }

    func testLegacyRecordMissingClassificationDecodesAndAdaptsSafely() throws {
        let analysis = makeAnalysis(score: 74)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoder.encode(analysis)) as? [String: Any]
        )
        object.removeValue(forKey: "outfitClassification")
        let legacyData = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        let decoded = try JSONDecoder().decode(OutfitAnalysisResult.self, from: legacyData)

        let snapshot = adapt(decoded)

        XCTAssertEqual(snapshot.garmentCategory.value, .otherUncertain)
        XCTAssertEqual(snapshot.garmentCategory.origin, .unknown)
        XCTAssertTrue(snapshot.missingEvidence.contains { $0.kind == .garmentCategory })
    }

    func testOtherUncertainClassificationStaysUncertain() {
        let proposed = makeClassification(
            category: .workUniform,
            confidence: 0.75,
            occasion: "Work",
            scoringProfile: .uniformWorkwear
        )
        let snapshot = adapt(makeAnalysis(classification: proposed.confirming(.otherUncertain)))

        XCTAssertEqual(snapshot.garmentCategory.value, .otherUncertain)
        XCTAssertEqual(snapshot.garmentCategory.origin, .userConfirmed)
        XCTAssertEqual(snapshot.garmentCategory.confirmationState, .uncertain)
        XCTAssertEqual(snapshot.garmentCategory.confidence, .unknown)
        XCTAssertEqual(snapshot.scoringProfile, .uncertain)
    }

    func testConfirmedGarmentCategoryDoesNotOverwriteDetectedStyle() {
        let proposed = makeClassification(
            category: .brandedWorkwear,
            confidence: 0.86,
            occasion: "Work",
            scoringProfile: .uniformWorkwear
        )
        let corrected = proposed.confirming(.workUniform)
        let snapshot = adapt(makeAnalysis(
            classification: corrected,
            style: "Casual"
        ))

        XCTAssertEqual(snapshot.detectedStyle.value, "Casual")
        XCTAssertEqual(snapshot.garmentCategory.value, .workUniform)
        XCTAssertEqual(snapshot.garmentCategory.origin, .userConfirmed)
        XCTAssertEqual(snapshot.garmentCategory.confirmationState, .confirmed)
    }

    func testUnsupportedLegacyEvidenceDoesNotInventPurpose() {
        let snapshot = adapt(makeAnalysis(
            classification: makeClassification(
                category: .brandedWorkwear,
                confidence: 0.95,
                occasion: "Work",
                scoringProfile: .uniformWorkwear
            )
        ))

        XCTAssertEqual(snapshot.outfitPurpose.value, .otherUncertain)
        XCTAssertEqual(snapshot.outfitPurpose.origin, .unknown)
        XCTAssertNil(snapshot.userConfirmedPurpose)
        XCTAssertEqual(snapshot.scoringProfile, .uncertain)
    }

    func testUnsupportedLegacyEvidenceDoesNotInventWorkplaceProfile() {
        let snapshot = adapt(makeAnalysis(
            classification: makeClassification(
                category: .medicalScrubs,
                confidence: 0.95,
                occasion: "Work",
                scoringProfile: .uniformWorkwear
            )
        ))

        XCTAssertEqual(snapshot.workplaceProfile.value, .otherUncertain)
        XCTAssertEqual(snapshot.workplaceProfile.origin, .unknown)
        XCTAssertEqual(snapshot.workplaceSuitability.level, .uncertain)
    }

    func testLegacyAdapterIsDeterministicForIdenticalInput() {
        let analysis = makeAnalysis(
            classification: makeClassification(
                category: .businessFormal,
                confidence: 0.88,
                occasion: "Business Formal",
                scoringProfile: .businessProfessional
            )
        )

        let first = adapt(analysis)
        let second = adapt(analysis)

        XCTAssertEqual(first, second)
        XCTAssertEqual(try? encoded(first), try? encoded(second))
    }

    func testNewContractEncodeDecodeRoundTrip() throws {
        let original = adapt(makeAnalysis(
            classification: makeClassification(
                category: .casualWear,
                confidence: 0.73,
                occasion: "Casual Day",
                compatibility: .possible,
                scoringProfile: .casualEveryday
            )
        ))

        let decoded = try JSONDecoder().decode(
            OutfitContextSnapshot.self,
            from: encoded(original)
        )

        XCTAssertEqual(decoded, original)
    }

    func testUnknownEnumValuesDecodeToDocumentedSafeFallbacks() throws {
        XCTAssertEqual(
            try JSONDecoder().decode(OutfitPurpose.self, from: Data(#""futurePurpose""#.utf8)),
            .otherUncertain
        )
        XCTAssertEqual(
            try JSONDecoder().decode(WorkplaceProfile.self, from: Data(#""futureWorkplace""#.utf8)),
            .otherUncertain
        )
        XCTAssertEqual(
            try JSONDecoder().decode(EnvironmentType.self, from: Data(#""futureEnvironment""#.utf8)),
            .otherUncertain
        )
        XCTAssertEqual(
            try JSONDecoder().decode(PurposeScoringProfile.self, from: Data(#""futureProfile""#.utf8)),
            .uncertain
        )
        XCTAssertEqual(
            try JSONDecoder().decode(ContextGarmentCategory.self, from: Data(#""futureGarment""#.utf8)),
            .otherUncertain
        )
    }

    func testAdapterPreservesAuthoritativeScoreExactly() {
        let analysis = makeAnalysis(score: 74)

        let snapshot = adapt(analysis)

        XCTAssertEqual(analysis.score, 74)
        XCTAssertEqual(snapshot.authoritativeScore, 74)
    }

    func testAdapterPreservesAuthoritativeBreakdownExactly() {
        let breakdown = OutfitScoreBreakdown(
            colorHarmony: 25,
            patternBalance: 20,
            fitQuality: 13,
            occasionMatch: 0,
            accessoryUse: 6
        )
        let analysis = makeAnalysis(score: 80, breakdown: breakdown)

        let snapshot = adapt(analysis)

        XCTAssertEqual(analysis.scoreBreakdown, breakdown)
        XCTAssertEqual(snapshot.authoritativeBreakdown, breakdown)
    }

    func testAdapterDoesNotPersistRawOCRNamesBrandOrSpeechContent() throws {
        let classification = OutfitClassificationResult(
            primaryCategory: .brandedWorkwear,
            secondaryCategories: [],
            confidence: 0.95,
            confidenceLevel: .high,
            evidence: [
                OutfitClassificationEvidence(
                    kind: .visibleText,
                    summary: "Alex Example Employee 4107 Northwind Textiles",
                    confidence: 0.95
                ),
                OutfitClassificationEvidence(
                    kind: .branding,
                    summary: "Northwind Textiles",
                    confidence: 0.9
                )
            ],
            detectedText: ["Alex Example", "Employee 4107"],
            detectedBranding: ["Northwind Textiles"],
            selectedOccasion: "Work",
            occasionCompatibility: .compatible,
            userConfirmedCategory: nil,
            scoringProfile: .uniformWorkwear
        )

        let data = try encoded(adapt(makeAnalysis(classification: classification)))
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertFalse(json.localizedCaseInsensitiveContains("Alex Example"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("4107"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("Northwind Textiles"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("speech"))
        XCTAssertTrue(json.contains("raw text is not retained"))
    }

    func testAdapterDoesNotAutomaticallyRewriteLegacyRecord() throws {
        let analysis = makeAnalysis(
            classification: makeClassification(
                category: .activewear,
                confidence: 0.83,
                occasion: "Gym",
                scoringProfile: .athleticPerformance
            )
        )
        let before = try encoded(analysis)

        _ = adapt(analysis)

        XCTAssertEqual(try encoded(analysis), before)
    }

    func testCE1HasNoShoppingCatalogOrPersistenceWriteDependency() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURLs = [
            repositoryRoot.appendingPathComponent("StyleMatchAI/ContextEngine/OutfitContextContracts.swift"),
            repositoryRoot.appendingPathComponent("StyleMatchAI/ContextEngine/LegacyContextAdapter.swift")
        ]
        let forbiddenTokens = [
            "UserDefaults",
            "ShoppingView",
            "ProductCatalog",
            "RetailerConfig",
            "setValue(",
            ".set("
        ]

        for sourceURL in sourceURLs {
            let source = try String(contentsOf: sourceURL, encoding: .utf8)
            for token in forbiddenTokens {
                XCTAssertFalse(source.contains(token), "\(sourceURL.lastPathComponent) contains \(token)")
            }
        }
    }

    private func adapt(
        _ analysis: OutfitAnalysisResult,
        weather: WeatherContextReference? = nil
    ) -> OutfitContextSnapshot {
        LegacyContextAdapter.adapt(
            scanID: "scan-ce1",
            completedAt: completedAt,
            analysis: analysis,
            weatherContext: weather
        )
    }

    private func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    private func makeClassification(
        category: OutfitCategory = .otherUncertain,
        confidence: Double = 0,
        occasion: String? = nil,
        compatibility: OutfitOccasionCompatibility = .uncertain,
        scoringProfile: OutfitScoringProfile = .uncertain
    ) -> OutfitClassificationResult {
        OutfitClassificationResult(
            primaryCategory: category,
            secondaryCategories: [],
            confidence: confidence,
            confidenceLevel: confidence >= 0.82 ? .high : (confidence >= 0.55 ? .medium : .low),
            evidence: category == .otherUncertain
                ? [.init(kind: .uncertainty, summary: "Classification is uncertain.", confidence: 1)]
                : [.init(kind: .silhouette, summary: "Garment silhouette evidence is present.", confidence: confidence)],
            detectedText: [],
            detectedBranding: [],
            selectedOccasion: occasion,
            occasionCompatibility: compatibility,
            userConfirmedCategory: nil,
            scoringProfile: scoringProfile
        )
    }

    private func makeAnalysis(
        score: Int = 80,
        breakdown: OutfitScoreBreakdown? = OutfitScoreBreakdown(
            colorHarmony: 25,
            patternBalance: 20,
            fitQuality: 13,
            occasionMatch: 0,
            accessoryUse: 6
        ),
        classification: OutfitClassificationResult = .uncertain(),
        style: String = "Casual",
        environment: String = "Home"
    ) -> OutfitAnalysisResult {
        OutfitAnalysisResult(
            score: score,
            scoreBreakdown: breakdown,
            colorMatch: "Coordinated",
            occasionFit: "Work",
            styleBalance: style,
            colorHarmony: "Strong",
            styleCoordination: "Strong",
            formality: "Casual",
            seasonalMatch: "Warm weather",
            summary: "Completed scan",
            outfitDescription: "Casual outfit",
            detectedClothingItems: ["shirt", "pants"],
            colorPalette: ["gray"],
            environment: environment,
            imageQuality: "Clear",
            outfitClassification: classification,
            suggestions: [],
            recommendations: []
        )
    }
}
