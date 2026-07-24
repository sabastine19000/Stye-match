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
            ["photo", "selectedOccasion", "weather", "savedProfile"]
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
