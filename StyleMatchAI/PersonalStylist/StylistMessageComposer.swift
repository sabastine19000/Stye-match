import Foundation

struct StylistScoreMessageInput {
    let score: Int
    let scoreTier: String
    let scoreBreakdown: OutfitScoreBreakdown?
    let detectedGarments: [String]
    let detectedItemConfidences: [DetectedItemConfidence]
    let colors: [String]
    let groundedRecommendations: [GroundedRecommendation]

    init(
        score: Int,
        scoreTier: String,
        scoreBreakdown: OutfitScoreBreakdown?,
        detectedGarments: [String],
        detectedItemConfidences: [DetectedItemConfidence] = [],
        colors: [String],
        groundedRecommendations: [GroundedRecommendation] = []
    ) {
        self.score = min(100, max(0, score))
        self.scoreTier = scoreTier.trimmingCharacters(in: .whitespacesAndNewlines)
        self.scoreBreakdown = scoreBreakdown
        self.detectedGarments = detectedGarments
        self.detectedItemConfidences = detectedItemConfidences
        self.colors = colors
        self.groundedRecommendations = Array(
            groundedRecommendations.prefix(RecommendationGroundingValidator.maximumRecommendations)
        )
    }
}

enum StylistScoreBand: Equatable {
    case enthusiastic
    case confidentPositive
    case encouragingImprovement
    case constructiveKind

    init(score: Int) {
        switch score {
        case 90...100:
            self = .enthusiastic
        case 75...89:
            self = .confidentPositive
        case 60...74:
            self = .encouragingImprovement
        default:
            self = .constructiveKind
        }
    }
}

enum StylistMessageComposer {
    static let aiPhrasingInstruction = "Do not mention any garment, color, score, or fact not present in the provided context. Do not exaggerate the score."

    static func scoreEncouragement(input: StylistScoreMessageInput) -> PersonalStylistMessageSection {
        let band = StylistScoreBand(score: input.score)
        let attribute = strongestDetectedAttribute(
            garments: input.detectedGarments,
            confidences: input.detectedItemConfidences,
            colors: input.colors
        )
        let groundedImprovement = input.groundedRecommendations.first.map {
            GroundedRecommendationPresenter.presentation(for: $0)
        }
        let scoreText = "\(input.score)/100"

        let body: String
        switch band {
        case .enthusiastic:
            body = "Great outfit choice. Your style score is strong today at \(scoreText), and \(attribute) gives the scan a clear anchor."
        case .confidentPositive:
            body = "This is a strong look at \(scoreText). \(attribute) is working well, and the outfit has a solid foundation."
        case .encouragingImprovement:
            body = "This outfit has a useful base at \(scoreText), especially with \(attribute). \(groundedImprovementText(groundedImprovement))"
        case .constructiveKind:
            body = "This scan landed at \(scoreText), so keep the feedback practical and kind. Start with \(attribute). \(groundedImprovementText(groundedImprovement))"
        }

        return PersonalStylistMessageSection(
            title: "Stylist Encouragement",
            body: body,
            source: .score
        )
    }

    private static func strongestDetectedAttribute(
        garments: [String],
        confidences: [DetectedItemConfidence],
        colors: [String]
    ) -> String {
        let facts = ScanNarrativeFacts(
            palette: colors,
            detectedGarments: garments,
            detectedItemConfidences: confidences
        )
        let garment = reliablePrimaryGarment(garments: garments, confidences: confidences)

        // The palette has no per-garment color association, so never turn its
        // first entry into a dominant color or a color-garment claim.
        if let paletteAnchor = ScanNarrativeConsistencyValidator.paletteAnchor(for: facts) {
            return paletteAnchor
        }
        if let garment { return "the detected \(garment)" }
        return "the score itself"
    }

    private static func reliablePrimaryGarment(
        garments: [String],
        confidences: [DetectedItemConfidence]
    ) -> String? {
        let primaryGarments: Set<String> = [
            "t-shirt", "polo shirt", "button-down shirt", "shirt", "sweater",
            "jacket", "pants", "jeans", "shorts", "dress", "skirt", "suit",
            "robe", "sleepwear"
        ]
        let detected = Set(garments.compactMap(GarmentLabelMapper.humanReadableTerm))
        let candidates = confidences.compactMap { confidence -> (item: String, confidence: Int)? in
            guard let item = GarmentLabelMapper.humanReadableTerm(for: confidence.item),
                  primaryGarments.contains(item),
                  detected.contains(item),
                  confidence.confidence >= ScanNarrativeFacts.authoritativeGarmentConfidence else {
                return nil
            }
            return (item, confidence.confidence)
        }
        .sorted { left, right in
            if left.confidence == right.confidence { return left.item < right.item }
            return left.confidence > right.confidence
        }

        guard let strongest = candidates.first else { return nil }
        if candidates.dropFirst().contains(where: {
            $0.item != strongest.item && $0.confidence >= strongest.confidence - 8
        }) {
            return nil
        }
        return strongest.item
    }

    private static func groundedImprovementText(
        _ presentation: GroundedRecommendationPresentation?
    ) -> String {
        guard let presentation else {
            return RecommendationGroundingResult.honestEmptyState
        }
        return "One grounded next step (\(presentation.sourceLabel)): \(presentation.detail)"
    }

}
