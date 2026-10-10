import XCTest
@testable import StyleMatchPro

final class OutfitClassificationTests: XCTestCase {
    func testSeatedPersonGeometryProvidesBoundedTorsoEvidenceWithoutClassifyingUniform() {
        let torso = PersonGarmentRegionEvidence.torsoAndLowerBodyBox(
            for: CGRect(x: 0.17, y: 0.16, width: 0.66, height: 0.79)
        )

        guard let torso else {
            return XCTFail("Expected a defensible seated-person torso region.")
        }
        XCTAssertEqual(torso.minX, 0.2492, accuracy: 0.0001)
        XCTAssertEqual(torso.minY, 0.3496, accuracy: 0.0001)
        XCTAssertEqual(torso.width, 0.5016, accuracy: 0.0001)
        XCTAssertEqual(torso.height, 0.5214, accuracy: 0.0001)

        let ordinaryCasual = classify(
            [("visible person clothing region", 0.76), ("casual shirt", 0.70)],
            occasion: "Work"
        )
        XCTAssertEqual(ordinaryCasual.primaryCategory, .casualWear)
        XCTAssertNotEqual(ordinaryCasual.primaryCategory, .workUniform)
        XCTAssertNotEqual(ordinaryCasual.primaryCategory, .brandedWorkwear)
    }

    func testLandscapeGeometryCannotBecomePersonGarmentEvidence() {
        XCTAssertNil(
            PersonGarmentRegionEvidence.torsoAndLowerBodyBox(
                for: CGRect(x: 0.02, y: 0.40, width: 0.96, height: 0.13)
            )
        )
        XCTAssertNil(
            PersonGarmentRegionEvidence.torsoAndLowerBodyBox(
                for: CGRect(x: 0.44, y: 0.42, width: 0.10, height: 0.22)
            )
        )
    }

    func testSeatedKiaStyleUniformEvidenceReachesExistingUniformClassifier() {
        let result = classify(
            [
                ("visible person clothing region", 0.76),
                ("embroidered logo", 0.94),
                ("polo work shirt", 0.91),
                ("name patch", 0.89)
            ],
            text: [("Kia", 0.94)],
            occasion: "Work"
        )

        XCTAssertTrue([.workUniform, .brandedWorkwear].contains(result.primaryCategory))
        XCTAssertEqual(result.occasionCompatibility, .compatible)
    }

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

    func testWatchDoesNotClassifyAnOtherwiseApparelOutfitAsAccessories() {
        let result = classify(
            [("casual polo shirt", 0.78), ("work pants", 0.74), ("watch", 0.96)],
            occasion: "Work"
        )

        XCTAssertNotEqual(result.primaryCategory, .accessories)
        XCTAssertTrue([.casualWear, .businessCasual].contains(result.primaryCategory))
        XCTAssertEqual(result.selectedOccasion, "Work")
    }

    func testGenericApparelEvidenceSuppressesWatchAsThePrimaryOutfitType() {
        let result = classify(
            [("visible person clothing region", 0.80), ("watch", 0.96)],
            occasion: "Work"
        )

        XCTAssertEqual(result.primaryCategory, .casualWear)
        XCTAssertNotEqual(result.primaryCategory, .accessories)
        XCTAssertEqual(result.selectedOccasion, "Work")
    }

    func testAdjudicatorTimeoutFallbackNeverLeavesAccessoriesPrimaryWhenApparelIsPresent() {
        let deterministic = classify([("watch", 0.96)], occasion: "Work")
        let input = OutfitClassificationAdjudicationInput(
            deterministic: deterministic,
            detectedGarments: ["watch"],
            apparelPresent: true,
            accessoryPresent: true,
            readableGarmentTextPresent: false,
            visibleMarkingPresent: false,
            personEvidencePresent: true
        )

        let resolved = OutfitClassificationAdjudicator.applying(nil, to: deterministic, input: input)

        XCTAssertEqual(resolved.primaryCategory, .casualWear)
        XCTAssertNotEqual(resolved.primaryCategory, .accessories)
        XCTAssertEqual(resolved.selectedOccasion, "Work")
    }

    func testAdjudicatorAllowsSupportedWorkUniformButWorkAloneCannotForceIt() {
        let deterministic = classify([("watch", 0.96)], occasion: "Work")
        let unsupported = OutfitClassificationAdjudicationInput(
            deterministic: deterministic,
            detectedGarments: ["watch"],
            apparelPresent: true,
            accessoryPresent: true,
            readableGarmentTextPresent: false,
            visibleMarkingPresent: false,
            personEvidencePresent: true
        )
        let forcedUniform = OutfitClassificationAdjudication(
            finalOutfitType: .workUniform,
            confidence: 0.9,
            shouldOverrideDeterministic: true,
            evidenceReasons: [.uniformConstruction, .workOccasion],
            uncertaintyReason: nil
        )

        XCTAssertEqual(
            OutfitClassificationAdjudicator.applying(forcedUniform, to: deterministic, input: unsupported).primaryCategory,
            .casualWear
        )

        let supported = OutfitClassificationAdjudicationInput(
            deterministic: deterministic,
            detectedGarments: ["shirt", "pants", "watch"],
            apparelPresent: true,
            accessoryPresent: true,
            readableGarmentTextPresent: true,
            visibleMarkingPresent: true,
            personEvidencePresent: true,
            confirmedWorkplaceContextPresent: true
        )
        let adjudicated = OutfitClassificationAdjudicator.applying(
            forcedUniform,
            to: deterministic,
            input: supported
        )

        XCTAssertEqual(adjudicated.primaryCategory, .workUniform)
        XCTAssertEqual(adjudicated.selectedOccasion, "Work")
    }

    func testAdjudicatorRejectsMalformedOrAccessoryPrimaryOutput() {
        let deterministic = classify([("watch", 0.96)], occasion: "General")
        let input = OutfitClassificationAdjudicationInput(
            deterministic: deterministic,
            detectedGarments: ["watch"],
            apparelPresent: true,
            accessoryPresent: true,
            readableGarmentTextPresent: false,
            visibleMarkingPresent: false,
            personEvidencePresent: true
        )
        let invalid = OutfitClassificationAdjudication(
            finalOutfitType: .accessories,
            confidence: 0.99,
            shouldOverrideDeterministic: true,
            evidenceReasons: [.accessorySecondary],
            uncertaintyReason: nil
        )

        XCTAssertEqual(
            OutfitClassificationAdjudicator.applying(invalid, to: deterministic, input: input).primaryCategory,
            .casualWear
        )
        XCTAssertNil(OutfitClassificationAdjudicator.decodeBoundedResponse("not JSON"))
        XCTAssertNil(OutfitClassificationAdjudicator.decodeBoundedResponse("{\"finalOutfitType\":\"notACategory\"}"))
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

    func testHighConfidenceStrongEvidenceUniformIsAcceptedWithoutConfirmation() {
        let result = classify(
            [("uniform utility shirt", 0.96), ("embroidered logo", 0.93)],
            text: [("readable", 0.90)],
            occasion: "Work"
        )

        XCTAssertEqual(result.confidenceLevel, .high)
        XCTAssertTrue(result.hasStrongAutoAcceptedWorkUniformEvidence)
        XCTAssertFalse(result.requiresConfirmation)
    }

    func testWorkUniformMakesCasualStyleCompatibleWithWorkAndProvidesGuidance() {
        let result = classify(
            [("uniform utility shirt", 0.96), ("embroidered logo", 0.93)],
            text: [("readable", 0.90)],
            occasion: "Work"
        )

        XCTAssertNil(FormalityMismatchEvaluator.evaluate(
            detectedStyle: "Casual",
            occasion: .work,
            outfitClassification: result
        ))
        XCTAssertEqual(
            FormalityMismatchEvaluator.compatibleWorkUniformGuidance(
                detectedStyle: "Casual",
                occasion: .work,
                outfitClassification: result
            ),
            "This outfit has a casual style but appears to be a work uniform appropriate for work."
        )
    }

    func testBrandedWorkwearAndMedicalScrubsAreCompatibleWithWork() {
        let branded = classify(
            [("utility shirt", 0.96), ("embroidered logo", 0.93)],
            text: [("readable", 0.90)],
            occasion: "Work"
        )
        let scrubs = classify([("medical scrubs", 0.96)], occasion: "Work")

        XCTAssertEqual(branded.primaryCategory, .brandedWorkwear)
        XCTAssertFalse(branded.requiresConfirmation)
        XCTAssertNil(FormalityMismatchEvaluator.evaluate(
            detectedStyle: "Casual",
            occasion: .work,
            outfitClassification: branded
        ))
        XCTAssertEqual(scrubs.primaryCategory, .medicalScrubs)
        XCTAssertFalse(scrubs.requiresConfirmation)
        XCTAssertNil(FormalityMismatchEvaluator.evaluate(
            detectedStyle: "Casual",
            occasion: .work,
            outfitClassification: scrubs
        ))
    }

    func testIndustrialRestaurantAndRetailUniformEvidenceIsWorkCompatible() {
        let cases = ["industrial coverall", "restaurant service shirt", "retail uniform polo"]

        for construction in cases {
            let result = classify(
                [(construction, 0.96), ("embroidered logo", 0.93)],
                text: [("readable", 0.90)],
                occasion: "Work"
            )

            XCTAssertEqual(result.primaryCategory, .brandedWorkwear, construction)
            XCTAssertEqual(result.confidenceLevel, .high, construction)
            XCTAssertFalse(result.requiresConfirmation, construction)
            XCTAssertNil(FormalityMismatchEvaluator.evaluate(
                detectedStyle: "Casual",
                occasion: .work,
                outfitClassification: result
            ), construction)
        }
    }

    func testWeakBrandingOrOCRAloneDoesNotBecomeWorkUniform() {
        let result = classify(
            [("embroidered logo", 0.96)],
            text: [("readable", 0.96)],
            occasion: "Work"
        )

        XCTAssertNotEqual(result.primaryCategory, .workUniform)
        XCTAssertNotEqual(result.primaryCategory, .brandedWorkwear)
        XCTAssertTrue(result.isUncertain)
    }

    func testLowConfidenceUniformStillRequiresConfirmation() {
        let result = classify([("uniform utility shirt", 0.45)], occasion: "Work")

        XCTAssertEqual(result.primaryCategory, .workUniform)
        XCTAssertEqual(result.confidenceLevel, .low)
        XCTAssertTrue(result.requiresConfirmation)
        XCTAssertNotNil(FormalityMismatchEvaluator.evaluate(
            detectedStyle: "Casual",
            occasion: .work,
            outfitClassification: result
        ))
    }

    func testCasualWearAndSwimwearStillWarnForWork() {
        let casual = classify([("casual shirt jeans", 0.94)], occasion: "Work")
        let swimwear = classify([("swimwear swimsuit", 0.94)], occasion: "Work")

        XCTAssertEqual(casual.primaryCategory, .casualWear)
        XCTAssertNotNil(FormalityMismatchEvaluator.evaluate(
            detectedStyle: "Casual",
            occasion: .work,
            outfitClassification: casual
        ))
        XCTAssertEqual(swimwear.primaryCategory, .swimwear)
        XCTAssertNotNil(FormalityMismatchEvaluator.evaluate(
            detectedStyle: "Casual",
            occasion: .work,
            outfitClassification: swimwear
        ))
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
