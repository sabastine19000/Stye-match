import XCTest
@testable import StyleMatchPro

final class RecommendationGroundingTests: XCTestCase {
    private let photoFacts = RecommendationGroundingFacts(
        observedGarments: [.poloShirt, .pants],
        observedColors: [.charcoal, .blue],
        fitObservability: .observable,
        hasSelectedOccasion: true,
        hasWeatherEvidence: true,
        hasSavedProfile: true
    )

    func testEveryEvidenceSourceHasStableRawValue() {
        XCTAssertEqual(
            RecommendationEvidenceSource.allCases.map(\.rawValue),
            ["photo", "selectedOccasion", "workplace", "weather", "savedProfile"]
        )
    }

    func testProducerIsIndependentFromEvidenceSource() {
        let recommendation = recommendation(
            sources: [.photo],
            producer: .remoteAI,
            references: [.color(.blue, role: .observed)],
            content: .coordinateObservedPalette
        )
        XCTAssertEqual(accepted([recommendation]).first?.producer, .remoteAI)
    }

    func testReferenceRolesRemainDistinct() {
        XCTAssertNotEqual(
            RecommendationReference.garment(.jacket, role: .observed),
            RecommendationReference.garment(.jacket, role: .suggested)
        )
    }

    func testCanonicalGarmentMappingUsesSanitizedTerms() {
        XCTAssertEqual(CanonicalGarmentReference(sanitizedGarmentTerm: "polo shirt"), .poloShirt)
        XCTAssertNil(CanonicalGarmentReference(sanitizedGarmentTerm: "person"))
    }

    func testCanonicalColorNormalizesGrey() {
        XCTAssertEqual(CanonicalColorReference(paletteTerm: "Grey"), .gray)
    }

    func testUnknownColorFailsClosed() {
        XCTAssertNil(CanonicalColorReference(paletteTerm: "mystery plaid"))
    }

    func testMissingSourceIsRejected() {
        assertRejected(
            recommendation(
                sources: [],
                references: [.color(.blue, role: .observed)],
                content: .coordinateObservedPalette
            ),
            reason: .missingEvidenceSource
        )
    }

    func testUnknownProducerIsRejected() {
        assertRejected(
            recommendation(
                sources: [.photo],
                producer: .unknown,
                references: [.color(.blue, role: .observed)],
                content: .coordinateObservedPalette
            ),
            reason: .unknownProducer
        )
    }

    func testUnsupportedObservedGarmentIsRejected() {
        assertRejected(
            recommendation(
                sources: [.photo],
                references: [.garment(.jacket, role: .observed)],
                fit: .observable,
                content: .refineObservedGarment(.jacket)
            ),
            reason: .unsupportedObservedGarment
        )
    }

    func testSuggestedGarmentNeedNotBeObserved() {
        let candidate = recommendation(
            sources: [.selectedOccasion],
            references: [.garment(.jacket, role: .suggested)],
            content: .considerSuggestedGarment(.jacket, nil),
            action: .seeExamples
        )
        XCTAssertEqual(accepted([candidate]), [candidate])
    }

    func testUnsupportedObservedColorIsRejected() {
        assertRejected(
            recommendation(
                sources: [.photo],
                references: [.color(.red, role: .observed)],
                content: .coordinateObservedPalette
            ),
            reason: .unsupportedObservedColor
        )
    }

    func testPaletteRecommendationRequiresObservedColorReference() {
        assertRejected(
            recommendation(sources: [.photo], content: .coordinateObservedPalette),
            reason: .missingRequiredReference
        )
    }

    func testObservedPaletteRecommendationPasses() {
        let candidate = recommendation(
            sources: [.photo],
            references: [.color(.blue, role: .observed)],
            content: .coordinateObservedPalette
        )
        XCTAssertEqual(accepted([candidate]), [candidate])
    }

    func testRefineGarmentRequiresMatchingObservedReference() {
        assertRejected(
            recommendation(
                sources: [.photo],
                references: [.garment(.pants, role: .observed)],
                fit: .observable,
                content: .refineObservedGarment(.poloShirt)
            ),
            reason: .missingRequiredReference
        )
    }

    func testRefineGarmentRequiresObservableFit() {
        let candidate = recommendation(
            sources: [.photo],
            references: [.garment(.poloShirt, role: .observed)],
            fit: .limited,
            content: .refineObservedGarment(.poloShirt)
        )
        assertRejected(candidate, reason: .insufficientFitObservability)
    }

    func testRefineGarmentPassesWithObservableFit() {
        let candidate = recommendation(
            sources: [.photo],
            references: [.garment(.poloShirt, role: .observed)],
            fit: .observable,
            content: .refineObservedGarment(.poloShirt)
        )
        XCTAssertEqual(accepted([candidate]), [candidate])
    }

    func testSuggestedGarmentRequiresSuggestedRole() {
        assertRejected(
            recommendation(
                sources: [.selectedOccasion],
                references: [.garment(.jacket, role: .conditional)],
                content: .considerSuggestedGarment(.jacket, nil),
                action: .seeExamples
            ),
            reason: .missingRequiredReference
        )
    }

    func testSuggestedColorRequiresSuggestedRole() {
        assertRejected(
            recommendation(
                sources: [.selectedOccasion],
                references: [
                    .garment(.shirt, role: .suggested),
                    .color(.blue, role: .conditional)
                ],
                content: .considerSuggestedGarment(.shirt, .blue),
                action: .seeExamples
            ),
            reason: .missingRequiredReference
        )
    }

    func testSuggestedGarmentRequiresExplicitAction() {
        assertRejected(
            recommendation(
                sources: [.selectedOccasion],
                references: [.garment(.shirt, role: .suggested)],
                content: .considerSuggestedGarment(.shirt, nil),
                action: .none
            ),
            reason: .invalidAction
        )
    }

    func testProfileFitRequiresProfileEvidence() {
        let facts = RecommendationGroundingFacts(hasSavedProfile: false)
        let candidate = recommendation(
            sources: [.savedProfile],
            content: .profileFitGuidance
        )
        assertRejected(candidate, facts: facts, reason: .missingProfileEvidence)
    }

    func testProfileFitDoesNotClaimObservablePhotoFit() {
        let candidate = recommendation(
            sources: [.savedProfile],
            fit: .observable,
            content: .profileFitGuidance
        )
        assertRejected(candidate, reason: .insufficientFitObservability)
    }

    func testProfileFitPassesAsGeneralGuidance() {
        let candidate = recommendation(
            sources: [.savedProfile],
            fit: .limited,
            content: .profileFitGuidance
        )
        XCTAssertEqual(accepted([candidate]), [candidate])
    }

    func testOccasionAdviceRequiresSelectedOccasion() {
        let facts = RecommendationGroundingFacts(hasSelectedOccasion: false)
        let candidate = recommendation(
            sources: [.selectedOccasion],
            content: .occasionAlignment
        )
        assertRejected(candidate, facts: facts, reason: .missingOccasionEvidence)
    }

    func testWeatherAdviceRequiresWeatherEvidence() {
        let facts = RecommendationGroundingFacts(hasWeatherEvidence: false)
        let candidate = recommendation(
            sources: [.weather],
            content: .weatherBreathability
        )
        assertRejected(candidate, facts: facts, reason: .missingWeatherEvidence)
    }

    func testClearerScanRequiresPhotoSource() {
        let candidate = recommendation(
            sources: [.selectedOccasion],
            content: .clearerFullOutfitScan
        )
        assertRejected(candidate, reason: .missingEvidenceSource)
    }

    func testClearerScanCannotOfferShoppingAction() {
        let candidate = recommendation(
            sources: [.photo],
            content: .clearerFullOutfitScan,
            action: .shopSimilar
        )
        assertRejected(candidate, reason: .invalidAction)
    }

    func testDuplicateIDsAreRejectedDeterministically() {
        let first = recommendation(
            id: "same",
            sources: [.photo],
            references: [.color(.blue, role: .observed)],
            content: .coordinateObservedPalette
        )
        let second = recommendation(
            id: "same",
            sources: [.weather],
            content: .weatherBreathability
        )
        let result = RecommendationGroundingValidator.validate([first, second], facts: photoFacts)
        XCTAssertEqual(result.accepted, [first])
        XCTAssertEqual(result.rejected.map(\.reason), [.duplicateID])
    }

    func testOutputIsCappedAtTwoInInputOrder() {
        let values = [
            recommendation(id: "one", sources: [.weather], content: .weatherBreathability),
            recommendation(id: "two", sources: [.selectedOccasion], content: .occasionAlignment),
            recommendation(
                id: "three",
                sources: [.photo],
                references: [.color(.blue, role: .observed)],
                content: .coordinateObservedPalette
            )
        ]
        XCTAssertEqual(accepted(values).map(\.id), ["one", "two"])
    }

    func testAllRejectedProducesHonestEmptyState() {
        let invalid = recommendation(
            sources: [],
            content: .weatherBreathability
        )
        let result = RecommendationGroundingValidator.validate([invalid], facts: photoFacts)
        XCTAssertTrue(result.accepted.isEmpty)
        XCTAssertEqual(
            result.emptyStateMessage,
            "Not enough visual evidence for specific suggestions — try a clearer full-outfit scan."
        )
    }

    func testAcceptedRecommendationSuppressesEmptyState() {
        let valid = recommendation(sources: [.weather], content: .weatherBreathability)
        XCTAssertNil(
            RecommendationGroundingValidator.validate([valid], facts: photoFacts).emptyStateMessage
        )
    }

    func testPresentationLabelsPhotoSource() {
        let candidate = recommendation(
            sources: [.photo],
            references: [.color(.blue, role: .observed)],
            content: .coordinateObservedPalette
        )
        XCTAssertEqual(
            GroundedRecommendationPresenter.presentation(for: candidate).sourceLabel,
            "Based on the photo"
        )
    }

    func testPresentationLabelsProfileSource() {
        let candidate = recommendation(
            sources: [.savedProfile],
            content: .profileFitGuidance
        )
        let presentation = GroundedRecommendationPresenter.presentation(for: candidate)
        XCTAssertEqual(presentation.sourceLabel, "Based on your saved size profile")
        XCTAssertFalse(presentation.detail.contains("36"))
    }

    func testPresentationLabelsWeatherSource() {
        let candidate = recommendation(sources: [.weather], content: .weatherBreathability)
        XCTAssertEqual(
            GroundedRecommendationPresenter.presentation(for: candidate).sourceLabel,
            "Based on current weather"
        )
    }

    func testPresentationUsesSeeExamplesAction() {
        let candidate = recommendation(
            sources: [.selectedOccasion],
            references: [.garment(.shirt, role: .suggested)],
            content: .considerSuggestedGarment(.shirt, nil),
            action: .seeExamples
        )
        XCTAssertEqual(
            GroundedRecommendationPresenter.presentation(for: candidate).actionLabel,
            "See examples"
        )
    }

    func testPresentationUsesShopSimilarAction() {
        let candidate = recommendation(
            sources: [.selectedOccasion],
            references: [.garment(.shirt, role: .suggested)],
            content: .considerSuggestedGarment(.shirt, nil),
            action: .shopSimilar
        )
        XCTAssertEqual(
            GroundedRecommendationPresenter.presentation(for: candidate).actionLabel,
            "Shop similar"
        )
    }

    func testSuggestedGarmentPresentationAdmitsItWasNotDetected() {
        let candidate = recommendation(
            sources: [.selectedOccasion],
            references: [.garment(.shirt, role: .suggested)],
            content: .considerSuggestedGarment(.shirt, nil),
            action: .seeExamples
        )
        XCTAssertTrue(
            GroundedRecommendationPresenter.presentation(for: candidate).detail
                .contains("not an item detected")
        )
    }

    func testPalettePresentationUsesOnlyTypedObservedColors() {
        let candidate = recommendation(
            sources: [.photo],
            references: [
                .color(.blue, role: .observed),
                .color(.charcoal, role: .observed)
            ],
            content: .coordinateObservedPalette
        )
        let detail = GroundedRecommendationPresenter.presentation(for: candidate).detail
        XCTAssertTrue(detail.contains("blue"))
        XCTAssertTrue(detail.contains("charcoal"))
        XCTAssertFalse(detail.contains("red"))
    }

    func testPalettePresentationUsesSingularCopyForOneObservedColor() {
        let candidate = recommendation(
            sources: [.photo],
            references: [.color(.charcoal, role: .observed)],
            content: .coordinateObservedPalette
        )

        XCTAssertEqual(
            GroundedRecommendationPresenter.presentation(for: candidate).detail,
            "The scan observed charcoal; repeat that color intentionally."
        )
    }

    func testPalettePresentationUsesPluralCopyForMultipleObservedColors() {
        let candidate = recommendation(
            sources: [.photo],
            references: [
                .color(.charcoal, role: .observed),
                .color(.blue, role: .observed)
            ],
            content: .coordinateObservedPalette
        )

        XCTAssertEqual(
            GroundedRecommendationPresenter.presentation(for: candidate).detail,
            "The scan observed blue and charcoal; repeat one of those colors intentionally."
        )
    }

    func testScanExplanationKeepsSavedProfileGuidanceGeneralAndSubjectNeutral() {
        let profile = recommendation(
            id: "profile-fit",
            sources: [.savedProfile],
            fit: .limited,
            content: .profileFitGuidance
        )
        let item = ScanExplanationPresenter.items(
            for: explanationContext(recommendations: [profile])
        ).first { $0.id == "profile-fit" }

        XCTAssertEqual(item?.sourceLabel, "Based on your saved size profile")
        XCTAssertEqual(item?.availability, .limited)
        XCTAssertTrue(item?.detail.contains("general guidance") == true)
        XCTAssertTrue(item?.detail.contains("does not prove exact measurements") == true)
        XCTAssertFalse(item?.detail.localizedCaseInsensitiveContains("your body") == true)
    }

    func testScanExplanationMakesMissingOccasionExplicitlyUnavailable() {
        let item = ScanExplanationPresenter.items(
            for: explanationContext(selectedOccasion: nil)
        ).first { $0.id == "occasion-unavailable" }

        XCTAssertEqual(item?.availability, .unavailable)
        XCTAssertEqual(item?.sourceLabel, "Context unavailable")
        XCTAssertEqual(item?.detail, "No occasion was selected. Occasion did not affect this score. Occasion suitability was not evaluated for this scan.")
    }

    func testScanExplanationAttributesSelectedOccasionWithoutChangingScore() {
        let item = ScanExplanationPresenter.items(
            for: explanationContext(selectedOccasion: "Office")
        ).first { $0.id == "occasion-context" }

        XCTAssertEqual(item?.sourceLabel, "Based on the selected occasion")
        XCTAssertTrue(item?.detail.contains("Selected occasion: Office") == true)
        XCTAssertTrue(item?.detail.contains("does not change the owned KigoStylist score") == true)
    }

    func testScanExplanationWithholdsWeatherAdviceWhenContextIsNotReliable() {
        let item = ScanExplanationPresenter.items(
            for: explanationContext(hasReliableWeather: false, weatherDetail: "Wear a jacket")
        ).first { $0.id == "weather-unavailable" }

        XCTAssertEqual(item?.availability, .unavailable)
        XCTAssertEqual(item?.sourceLabel, "Context unavailable")
        XCTAssertFalse(item?.detail.localizedCaseInsensitiveContains("jacket") == true)
    }

    func testScanExplanationLabelsUnmeasuredStyleAsSuggestion() {
        let item = ScanExplanationPresenter.items(
            for: explanationContext(
                detectedStyle: "Casual",
                hasMeasuredStyleConfidence: false,
                isStyleUncertain: true
            )
        ).first { $0.id == "style-direction" }

        XCTAssertEqual(item?.availability, .limited)
        XCTAssertEqual(item?.sourceLabel, "Stylist suggestion")
        XCTAssertEqual(item?.detail, "Possible style direction: Casual. The photo did not provide measured style-match confidence.")
    }

    func testScanExplanationSuppressesDuplicateRecommendationIDs() {
        let first = recommendation(
            id: "profile-fit",
            sources: [.savedProfile],
            fit: .limited,
            content: .profileFitGuidance
        )
        let duplicate = recommendation(
            id: "profile-fit",
            sources: [.savedProfile],
            fit: .limited,
            content: .profileFitGuidance
        )

        let items = ScanExplanationPresenter.items(
            for: explanationContext(recommendations: [first, duplicate])
        )
        XCTAssertEqual(items.filter { $0.id == "profile-fit" }.count, 1)
    }

    func testContractRoundTripsThroughJSON() throws {
        let candidate = recommendation(
            sources: [.photo, .selectedOccasion],
            references: [
                .garment(.shirt, role: .suggested),
                .color(.blue, role: .suggested)
            ],
            content: .considerSuggestedGarment(.shirt, .blue),
            action: .shopSimilar
        )
        let data = try JSONEncoder().encode(candidate)
        XCTAssertEqual(try JSONDecoder().decode(GroundedRecommendation.self, from: data), candidate)
    }

    func testStylistComposerUsesValidatedTypedAdviceInsteadOfWeakestScoreTemplate() {
        let candidate = recommendation(
            sources: [.photo],
            references: [
                .color(.blue, role: .observed),
                .color(.charcoal, role: .observed)
            ],
            content: .coordinateObservedPalette
        )
        let message = StylistMessageComposer.scoreEncouragement(
            input: StylistScoreMessageInput(
                score: 64,
                scoreTier: "Style Tune-Up",
                scoreBreakdown: OutfitScoreBreakdown(
                    colorHarmony: 20,
                    patternBalance: 18,
                    fitQuality: 3,
                    occasionMatch: 14,
                    accessoryUse: 9
                ),
                detectedGarments: [],
                colors: ["blue", "charcoal"],
                groundedRecommendations: [candidate]
            )
        )

        XCTAssertTrue(message.body.contains("Based on the photo"))
        XCTAssertTrue(message.body.contains("blue"))
        XCTAssertTrue(message.body.contains("charcoal"))
        XCTAssertFalse(message.body.contains("hems"))
        XCTAssertFalse(message.body.contains("sleeves"))
        XCTAssertFalse(message.body.contains("waist"))
    }

    func testStylistComposerFailsClosedWhenNoGroundedAdviceExists() {
        let message = StylistMessageComposer.scoreEncouragement(
            input: StylistScoreMessageInput(
                score: 64,
                scoreTier: "Style Tune-Up",
                scoreBreakdown: nil,
                detectedGarments: [],
                colors: []
            )
        )

        XCTAssertTrue(message.body.contains(RecommendationGroundingResult.honestEmptyState))
        XCTAssertFalse(message.body.localizedCaseInsensitiveContains("jacket"))
        XCTAssertFalse(message.body.localizedCaseInsensitiveContains("shoe"))
        XCTAssertFalse(message.body.localizedCaseInsensitiveContains("accessor"))
    }

    func testAIRecommendationFormatterRetainsEvidenceAttribution() {
        let candidate = recommendation(
            sources: [.savedProfile],
            fit: .limited,
            content: .profileFitGuidance
        )
        let prompt = AIRecommendationContextFormatter.promptFragment(for: [candidate])

        XCTAssertTrue(prompt.contains("Based on your saved size profile"))
        XCTAssertTrue(prompt.contains("does not prove exact measurements"))
    }

    func testAIRecommendationFormatterRejectsUnknownProducer() {
        let candidate = recommendation(
            sources: [.photo],
            producer: .unknown,
            content: .clearerFullOutfitScan
        )
        let prompt = AIRecommendationContextFormatter.promptFragment(for: [candidate])

        XCTAssertTrue(prompt.contains("grounded suggestions unavailable"))
        XCTAssertFalse(prompt.contains("clearer full-outfit"))
    }

    func testAuthoritativeScanPromptCarriesOnlyTypedGroundedAdvice() {
        let candidate = recommendation(
            sources: [.weather],
            content: .weatherBreathability
        )
        let context = StylistAuthoritativeScanContext(
            scanID: "scan-grounded",
            completedAt: Date(timeIntervalSince1970: 10),
            overallScore: 74,
            scoreBreakdown: nil,
            detectedStyle: "Casual",
            groundedRecommendations: [candidate],
            source: .liveCompleted
        )

        XCTAssertTrue(context.activeScanPrompt.contains("Based on current weather"))
        XCTAssertTrue(context.activeScanPrompt.contains("breathable"))
        XCTAssertFalse(context.activeScanPrompt.contains("jacket"))
    }

    private func recommendation(
        id: String = "candidate",
        sources: Set<RecommendationEvidenceSource>,
        producer: RecommendationProducer = .deterministicClientRule,
        references: Set<RecommendationReference> = [],
        fit: FitObservability = .unavailable,
        content: GroundedRecommendationContent,
        action: GroundedRecommendationAction = .none
    ) -> GroundedRecommendation {
        GroundedRecommendation(
            id: id,
            category: .evidence,
            sources: sources,
            producer: producer,
            references: references,
            fitObservability: fit,
            content: content,
            action: action
        )
    }

    private func explanationContext(
        recommendations: [GroundedRecommendation] = [],
        selectedOccasion: String? = nil,
        hasReliableWeather: Bool = false,
        weatherDetail: String? = nil,
        detectedStyle: String? = "Casual",
        hasMeasuredStyleConfidence: Bool = false,
        isStyleUncertain: Bool = true
    ) -> ScanExplanationContext {
        ScanExplanationContext(
            recommendations: recommendations,
            selectedOccasion: selectedOccasion,
            hasReliableWeather: hasReliableWeather,
            weatherDetail: weatherDetail,
            detectedStyle: detectedStyle,
            hasMeasuredStyleConfidence: hasMeasuredStyleConfidence,
            isStyleUncertain: isStyleUncertain
        )
    }

    private func accepted(
        _ recommendations: [GroundedRecommendation]
    ) -> [GroundedRecommendation] {
        RecommendationGroundingValidator.validate(recommendations, facts: photoFacts).accepted
    }

    private func assertRejected(
        _ recommendation: GroundedRecommendation,
        facts: RecommendationGroundingFacts? = nil,
        reason: RecommendationGroundingRejection,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let result = RecommendationGroundingValidator.validate(
            [recommendation],
            facts: facts ?? photoFacts
        )
        XCTAssertTrue(result.accepted.isEmpty, file: file, line: line)
        XCTAssertEqual(result.rejected.map(\.reason), [reason], file: file, line: line)
    }
}
