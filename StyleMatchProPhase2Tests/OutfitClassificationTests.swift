import XCTest
@testable import StyleMatchPro

final class OutfitClassificationTests: XCTestCase {
    func testClearBrandedWorkUniformUsesPrivacySafeEvidenceAndUniformProfile() {
        let result = classify(
            [
                ("embroidered logo", 0.94),
                ("polo work shirt", 0.92),
                ("name badge", 0.88)
            ],
            text: [("Sabastine Example Industries", 0.95)],
            occasion: "Work"
        )

        XCTAssertEqual(result.primaryCategory, .brandedWorkwear)
        XCTAssertEqual(result.confidenceLevel, .high)
        XCTAssertEqual(result.scoringProfile, .uniformWorkwear)
        XCTAssertEqual(result.occasionCompatibility, .compatible)
        XCTAssertEqual(result.detectedText, ["readable garment text present"])
        XCTAssertEqual(result.detectedBranding, ["visible logo, patch, badge, or embroidered branding cue"])
        XCTAssertFalse(result.evidence.map(\.summary).joined().contains("Sabastine"))
        XCTAssertTrue(result.scoringProfile.evaluationCriteria.contains("safety"))
    }

    func testSmallAngledUniformEvidenceRequiresConfirmationInsteadOfGuessing() {
        let result = classify(
            [("small angled embroidered logo", 0.45), ("polo shirt", 0.44)],
            text: [("partial", 0.38)],
            occasion: "Work"
        )

        XCTAssertEqual(result.primaryCategory, .brandedWorkwear)
        XCTAssertEqual(result.confidenceLevel, .medium)
        XCTAssertTrue(result.requiresConfirmation)
    }

    func testUnreadableLogoDoesNotPersistTextOrInventIdentity() {
        let result = classify(
            [("utility shirt", 0.90), ("embroidered logo", 0.72)],
            text: [("blur", 0.20)],
            occasion: "Work"
        )

        XCTAssertEqual(result.primaryCategory, .brandedWorkwear)
        XCTAssertTrue(result.detectedText.isEmpty)
        XCTAssertFalse(result.evidence.map(\.summary).joined().localizedCaseInsensitiveContains("blur"))
    }

    func testOrdinaryBrandedPoloIsNotPromotedToUniformWithoutWorkEvidence() {
        let result = classify(
            [("polo shirt", 0.91), ("brand logo", 0.86)],
            occasion: "General"
        )

        XCTAssertNotEqual(result.primaryCategory, .workUniform)
        XCTAssertNotEqual(result.primaryCategory, .brandedWorkwear)
        XCTAssertEqual(result.primaryCategory, .businessCasual)
    }

    func testRepresentativeSpecializedCategoriesSelectTheirProfiles() {
        let cases: [(String, OutfitCategory, OutfitScoringProfile)] = [
            ("medical scrubs", .medicalScrubs, .uniformWorkwear),
            ("school uniform", .schoolUniform, .uniformWorkwear),
            ("wedding dress", .weddingDress, .weddingParty),
            ("bridesmaid dress", .bridesmaidDress, .weddingParty),
            ("cocktail dress", .cocktailDress, .formalEvent),
            ("evening gown", .eveningGown, .formalEvent),
            ("professional business dress", .femaleBusinessDress, .businessProfessional),
            ("two piece suit jacket", .mensSuit, .businessProfessional),
            ("tuxedo dinner jacket", .tuxedo, .formalEvent),
            ("running tights activewear", .activewear, .athleticPerformance),
            ("traditional cultural attire", .traditionalCulturalAttire, .culturalTraditional),
            ("winter outerwear parka", .outerwear, .protectiveOuterwear),
            ("swimwear swimsuit", .swimwear, .swimwear),
            ("leather footwear boot", .footwear, .accessoriesFootwear),
            ("handbag accessory", .accessories, .accessoriesFootwear)
        ]

        for (label, expectedCategory, expectedProfile) in cases {
            let result = classify([(label, 0.94)], occasion: "General")
            XCTAssertEqual(result.primaryCategory, expectedCategory, label)
            XCTAssertEqual(result.scoringProfile, expectedProfile, label)
        }
    }

    func testSwimsuitDoesNotCollideWithMensSuitSubstring() {
        let result = classify([("swimsuit", 0.94)], occasion: "General")

        XCTAssertEqual(result.primaryCategory, .swimwear)
        XCTAssertEqual(result.scoringProfile, .swimwear)
        XCTAssertFalse(result.secondaryCategories.contains(.mensSuit))
    }

    func testCasualDressUsesCasualEverydayProfile() {
        let result = classify([("casual dress", 0.94)], occasion: "General")

        XCTAssertEqual(result.primaryCategory, .casualDress)
        XCTAssertEqual(result.scoringProfile, .casualEveryday)
    }

    func testHighConfidenceUniformStillRequiresOwnerConfirmation() {
        let result = classify(
            [("uniform utility shirt", 0.96), ("embroidered logo", 0.93)],
            text: [("readable", 0.90)],
            occasion: "Work"
        )

        XCTAssertEqual(result.confidenceLevel, .high)
        XCTAssertTrue(result.requiresConfirmation)
    }

    func testAmbiguousOrMissingEvidenceRemainsUncertain() {
        let ambiguous = classify([("fabric", 0.90)], occasion: "General")
        let empty = classify([], occasion: "Work")

        XCTAssertEqual(ambiguous.primaryCategory, .otherUncertain)
        XCTAssertTrue(ambiguous.isUncertain)
        XCTAssertEqual(empty.primaryCategory, .otherUncertain)
        XCTAssertTrue(empty.requiresConfirmation == false)
    }

    func testUserCorrectionBecomesAuthoritativeWithoutChangingScanScore() throws {
        let suggestion = classify(
            [("uniform utility shirt", 0.58)],
            occasion: "Work"
        )
        let corrected = suggestion.confirming(.businessCasual)
        let analysis = makeAnalysis(score: 80, classification: corrected)

        XCTAssertEqual(corrected.userConfirmedCategory, .businessCasual)
        XCTAssertEqual(corrected.effectiveCategory, .businessCasual)
        XCTAssertEqual(corrected.scoringProfile, .businessProfessional)
        XCTAssertEqual(analysis.score, 80)
        XCTAssertEqual(analysis.outfitClassification, corrected)
    }

    func testOtherUncertainCorrectionRemainsExplicitlyUncertain() {
        let suggestion = classify(
            [("uniform utility shirt", 0.58)],
            occasion: "Work"
        )

        let corrected = suggestion.confirming(.otherUncertain)

        XCTAssertEqual(corrected.effectiveCategory, .otherUncertain)
        XCTAssertTrue(corrected.isUncertain)
        XCTAssertFalse(corrected.requiresConfirmation)
        XCTAssertEqual(corrected.scoringProfile, .uncertain)
    }

    func testCategoryCorrectionPreservesIndependentDetectedStyle() {
        let suggestion = classify(
            [("uniform utility shirt", 0.58)],
            occasion: "Work"
        )
        let original = makeAnalysis(score: 80, classification: suggestion)
        let corrected = suggestion.confirming(.workUniform)

        let updated = original.replacingOutfitClassification(corrected)

        XCTAssertEqual(updated.styleBalance, original.styleBalance)
        XCTAssertEqual(updated.outfitClassification.effectiveCategory, .workUniform)
    }

    func testLegacySavedScanDecodesAsUncertainWithoutMigrationFailure() throws {
        let analysis = makeAnalysis(score: 74, classification: .uncertain(selectedOccasion: "Home"))
        let encoded = try JSONEncoder().encode(analysis)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "outfitClassification")
        let legacy = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(OutfitAnalysisResult.self, from: legacy)

        XCTAssertEqual(decoded.score, 74)
        XCTAssertEqual(decoded.outfitClassification.primaryCategory, .otherUncertain)
    }

    func testAuthoritativeContextCarriesOneScanIdentityAndClassification() {
        let classification = classify([("medical scrubs", 0.96)], occasion: "Work")
        let analysis = makeAnalysis(score: 80, classification: classification)
        let context = CurrentScanContextProvider.make(
            scanID: "scan-80",
            completedAt: Date(timeIntervalSince1970: 80),
            analysis: analysis,
            detectedStyle: "Medical Scrubs",
            styleConfidence: 96,
            selectedOccasion: "Work",
            occasionAssessment: "Compatible",
            weatherContext: "86 F",
            imageReference: .onDeviceOnly,
            source: .liveCompleted
        )

        XCTAssertEqual(context.scanID, "scan-80")
        XCTAssertEqual(context.overallScore, 80)
        XCTAssertEqual(context.outfitClassification?.effectiveCategory, .medicalScrubs)
        XCTAssertTrue(context.activeScanPrompt.contains("scan ID scan-80"))
        XCTAssertTrue(context.activeScanPrompt.contains("score 80/100"))
        XCTAssertTrue(context.activeScanPrompt.contains("selected occasion Work"))
        XCTAssertTrue(context.activeScanPrompt.contains("weather context 86 F"))
    }

    private func classify(
        _ visual: [(String, Double)],
        text: [(String, Double)] = [],
        occasion: String
    ) -> OutfitClassificationResult {
        OutfitClassificationEngine.classify(
            visualObservations: visual.map(OutfitVisualObservation.init),
            textObservations: text.map(OutfitTextObservation.init),
            selectedOccasion: occasion
        )
    }

    private func makeAnalysis(
        score: Int,
        classification: OutfitClassificationResult
    ) -> OutfitAnalysisResult {
        OutfitAnalysisResult(
            score: score,
            scoreBreakdown: OutfitScoreBreakdown(
                colorHarmony: 25,
                patternBalance: 20,
                fitQuality: 13,
                occasionMatch: 0,
                accessoryUse: 6
            ),
            colorMatch: "Coordinated",
            occasionFit: "Work",
            styleBalance: "Balanced",
            colorHarmony: "Strong",
            styleCoordination: "Strong",
            formality: "Casual",
            seasonalMatch: "Warm weather",
            summary: "Completed scan",
            outfitDescription: "Casual",
            detectedClothingItems: ["shirt", "pants"],
            colorPalette: ["gray"],
            environment: "86 F",
            imageQuality: "Clear",
            outfitClassification: classification,
            suggestions: [],
            recommendations: []
        )
    }
}
