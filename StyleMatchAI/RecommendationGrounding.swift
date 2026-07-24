import Foundation

enum RecommendationEvidenceSource: String, Codable, CaseIterable, Hashable {
    case photo
    case selectedOccasion
    case weather
    case savedProfile
}

enum RecommendationProducer: String, Codable, CaseIterable, Hashable {
    case deterministicClientRule
    case localModel
    case remoteAI
    case validatedFallback
    case unknown
}

enum RecommendationReferenceRole: String, Codable, CaseIterable, Hashable {
    case observed
    case suggested
    case conditional
}

enum FitObservability: String, Codable, CaseIterable, Hashable {
    case unavailable
    case limited
    case observable
}

enum CanonicalGarmentReference: String, Codable, CaseIterable, Hashable {
    case tshirt
    case poloShirt
    case buttonDownShirt
    case shirt
    case sweater
    case jacket
    case pants
    case jeans
    case shorts
    case dress
    case skirt
    case suit
    case robe
    case sleepwear
    case slippers
    case shoes
    case hat
    case bag
    case belt
    case watch
    case scarf
    case tie
    case accessory

    var displayName: String {
        switch self {
        case .tshirt: return "T-shirt"
        case .poloShirt: return "polo shirt"
        case .buttonDownShirt: return "button-down shirt"
        case .shirt: return "shirt"
        case .sweater: return "sweater"
        case .jacket: return "jacket"
        case .pants: return "pants"
        case .jeans: return "jeans"
        case .shorts: return "shorts"
        case .dress: return "dress"
        case .skirt: return "skirt"
        case .suit: return "suit"
        case .robe: return "robe"
        case .sleepwear: return "sleepwear"
        case .slippers: return "slippers"
        case .shoes: return "shoes"
        case .hat: return "hat"
        case .bag: return "bag"
        case .belt: return "belt"
        case .watch: return "watch"
        case .scarf: return "scarf"
        case .tie: return "tie"
        case .accessory: return "accessory"
        }
    }

    init?(sanitizedGarmentTerm: String) {
        switch sanitizedGarmentTerm.lowercased() {
        case "t-shirt": self = .tshirt
        case "polo shirt": self = .poloShirt
        case "button-down shirt": self = .buttonDownShirt
        case "shirt": self = .shirt
        case "sweater": self = .sweater
        case "jacket": self = .jacket
        case "pants": self = .pants
        case "jeans": self = .jeans
        case "shorts": self = .shorts
        case "dress": self = .dress
        case "skirt": self = .skirt
        case "suit": self = .suit
        case "robe": self = .robe
        case "sleepwear": self = .sleepwear
        case "slippers": self = .slippers
        case "shoes": self = .shoes
        case "hat": self = .hat
        case "bag": self = .bag
        case "belt": self = .belt
        case "watch": self = .watch
        case "scarf": self = .scarf
        case "tie": self = .tie
        case "accessory": self = .accessory
        default: return nil
        }
    }
}

enum CanonicalColorReference: String, Codable, CaseIterable, Hashable {
    case black
    case white
    case gray
    case charcoal
    case silver
    case cream
    case ivory
    case beige
    case tan
    case camel
    case brown
    case chocolate
    case navy
    case blue
    case teal
    case cyan
    case green
    case olive
    case yellow
    case gold
    case orange
    case red
    case burgundy
    case maroon
    case pink
    case purple
    case lavender
    case violet

    var displayName: String { rawValue }

    init?(paletteTerm: String) {
        let normalized = paletteTerm.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.init(rawValue: normalized == "grey" ? "gray" : normalized)
    }
}

enum RecommendationReference: Codable, Equatable, Hashable {
    case garment(CanonicalGarmentReference, role: RecommendationReferenceRole)
    case color(CanonicalColorReference, role: RecommendationReferenceRole)
}

enum GroundedRecommendationCategory: String, Codable, CaseIterable, Hashable {
    case evidence
    case fit
    case coordination
    case occasion
    case weather
    case garment
}

enum GroundedRecommendationAction: String, Codable, CaseIterable, Hashable {
    case seeExamples
    case shopSimilar
    case none
}

enum GroundedRecommendationContent: Codable, Equatable, Hashable {
    case clearerFullOutfitScan
    case profileFitGuidance
    case coordinateObservedPalette
    case refineObservedGarment(CanonicalGarmentReference)
    case considerSuggestedGarment(CanonicalGarmentReference, CanonicalColorReference?)
    case occasionAlignment
    case weatherBreathability
}

struct GroundedRecommendation: Codable, Equatable, Hashable, Identifiable {
    let id: String
    let category: GroundedRecommendationCategory
    let sources: Set<RecommendationEvidenceSource>
    let producer: RecommendationProducer
    let references: Set<RecommendationReference>
    let fitObservability: FitObservability
    let content: GroundedRecommendationContent
    let action: GroundedRecommendationAction

    init(
        id: String,
        category: GroundedRecommendationCategory,
        sources: Set<RecommendationEvidenceSource>,
        producer: RecommendationProducer,
        references: Set<RecommendationReference> = [],
        fitObservability: FitObservability = .unavailable,
        content: GroundedRecommendationContent,
        action: GroundedRecommendationAction = .none
    ) {
        self.id = id
        self.category = category
        self.sources = sources
        self.producer = producer
        self.references = references
        self.fitObservability = fitObservability
        self.content = content
        self.action = action
    }
}

struct RecommendationGroundingFacts: Equatable {
    let observedGarments: Set<CanonicalGarmentReference>
    let observedColors: Set<CanonicalColorReference>
    let fitObservability: FitObservability
    let hasSelectedOccasion: Bool
    let hasWeatherEvidence: Bool
    let hasSavedProfile: Bool

    init(
        observedGarments: Set<CanonicalGarmentReference> = [],
        observedColors: Set<CanonicalColorReference> = [],
        fitObservability: FitObservability = .unavailable,
        hasSelectedOccasion: Bool = false,
        hasWeatherEvidence: Bool = false,
        hasSavedProfile: Bool = false
    ) {
        self.observedGarments = observedGarments
        self.observedColors = observedColors
        self.fitObservability = fitObservability
        self.hasSelectedOccasion = hasSelectedOccasion
        self.hasWeatherEvidence = hasWeatherEvidence
        self.hasSavedProfile = hasSavedProfile
    }
}

enum RecommendationGroundingRejection: String, Codable, Equatable, Hashable {
    case duplicateID
    case missingEvidenceSource
    case unknownProducer
    case unsupportedObservedGarment
    case unsupportedObservedColor
    case missingRequiredReference
    case insufficientFitObservability
    case missingOccasionEvidence
    case missingWeatherEvidence
    case missingProfileEvidence
    case invalidAction
}

struct RejectedGroundedRecommendation: Equatable {
    let recommendation: GroundedRecommendation
    let reason: RecommendationGroundingRejection
}

struct RecommendationGroundingResult: Equatable {
    static let honestEmptyState =
        "Not enough visual evidence for specific suggestions — try a clearer full-outfit scan."

    let accepted: [GroundedRecommendation]
    let rejected: [RejectedGroundedRecommendation]

    var emptyStateMessage: String? {
        accepted.isEmpty ? Self.honestEmptyState : nil
    }
}

enum RecommendationGroundingValidator {
    static let maximumRecommendations = 2

    static func validate(
        _ recommendations: [GroundedRecommendation],
        facts: RecommendationGroundingFacts
    ) -> RecommendationGroundingResult {
        var accepted: [GroundedRecommendation] = []
        var rejected: [RejectedGroundedRecommendation] = []
        var seenIDs = Set<String>()

        for recommendation in recommendations {
            let rejection: RecommendationGroundingRejection?
            if !seenIDs.insert(recommendation.id).inserted {
                rejection = .duplicateID
            } else {
                rejection = validate(recommendation, facts: facts)
            }

            if let rejection {
                rejected.append(
                    RejectedGroundedRecommendation(
                        recommendation: recommendation,
                        reason: rejection
                    )
                )
            } else if accepted.count < maximumRecommendations {
                accepted.append(recommendation)
            }
        }

        return RecommendationGroundingResult(accepted: accepted, rejected: rejected)
    }

    private static func validate(
        _ recommendation: GroundedRecommendation,
        facts: RecommendationGroundingFacts
    ) -> RecommendationGroundingRejection? {
        guard !recommendation.sources.isEmpty else { return .missingEvidenceSource }
        guard recommendation.producer != .unknown else { return .unknownProducer }

        for reference in recommendation.references {
            switch reference {
            case let .garment(garment, role: .observed):
                guard facts.observedGarments.contains(garment) else {
                    return .unsupportedObservedGarment
                }
            case let .color(color, role: .observed):
                guard facts.observedColors.contains(color) else {
                    return .unsupportedObservedColor
                }
            case .garment, .color:
                break
            }
        }

        switch recommendation.content {
        case .clearerFullOutfitScan:
            guard recommendation.sources.contains(.photo) else {
                return .missingEvidenceSource
            }
            guard recommendation.action == .none else { return .invalidAction }

        case .profileFitGuidance:
            guard recommendation.sources.contains(.savedProfile), facts.hasSavedProfile else {
                return .missingProfileEvidence
            }
            guard recommendation.fitObservability != .observable else {
                return .insufficientFitObservability
            }

        case .coordinateObservedPalette:
            guard recommendation.sources.contains(.photo),
                  recommendation.references.contains(where: { reference in
                      if case .color(_, role: .observed) = reference { return true }
                      return false
                  }) else {
                return .missingRequiredReference
            }

        case let .refineObservedGarment(garment):
            guard recommendation.sources.contains(.photo),
                  recommendation.references.contains(.garment(garment, role: .observed)) else {
                return .missingRequiredReference
            }
            guard facts.fitObservability == .observable,
                  recommendation.fitObservability == .observable else {
                return .insufficientFitObservability
            }

        case let .considerSuggestedGarment(garment, color):
            guard recommendation.references.contains(.garment(garment, role: .suggested)) else {
                return .missingRequiredReference
            }
            if let color,
               !recommendation.references.contains(.color(color, role: .suggested)) {
                return .missingRequiredReference
            }
            guard recommendation.action != .none else { return .invalidAction }

        case .occasionAlignment:
            guard recommendation.sources.contains(.selectedOccasion),
                  facts.hasSelectedOccasion else {
                return .missingOccasionEvidence
            }

        case .weatherBreathability:
            guard recommendation.sources.contains(.weather),
                  facts.hasWeatherEvidence else {
                return .missingWeatherEvidence
            }
        }

        return nil
    }
}

struct GroundedRecommendationPresentation: Equatable {
    let title: String
    let detail: String
    let sourceLabel: String
    let actionLabel: String?
}

enum GroundedRecommendationPresenter {
    static func presentation(
        for recommendation: GroundedRecommendation
    ) -> GroundedRecommendationPresentation {
        let title: String
        let detail: String

        switch recommendation.content {
        case .clearerFullOutfitScan:
            title = "Try a clearer full-outfit scan"
            detail = RecommendationGroundingResult.honestEmptyState
        case .profileFitGuidance:
            title = "Review the visible fit"
            detail = "Use your saved size profile as general guidance; the photo does not prove exact measurements."
        case .coordinateObservedPalette:
            let colors = observedColors(in: recommendation).map(\.displayName).sorted()
            title = "Coordinate the detected palette"
            detail = "The scan observed \(joined(colors)); repeat one of those colors intentionally."
        case let .refineObservedGarment(garment):
            title = "Refine the visible \(garment.displayName)"
            detail = "The full outline is visible enough to review how this \(garment.displayName) sits."
        case let .considerSuggestedGarment(garment, color):
            title = "Consider \(suggestedName(garment: garment, color: color))"
            detail = "This is a suggested addition, not an item detected in the photo."
        case .occasionAlignment:
            title = "Check the selected occasion"
            detail = "Use the selected occasion as context; it does not change the owned StyleMatch score."
        case .weatherBreathability:
            title = "Keep the outfit weather-ready"
            detail = "Based on the current weather: favor breathable choices and avoid unnecessary heavy layers."
        }

        return GroundedRecommendationPresentation(
            title: title,
            detail: detail,
            sourceLabel: sourceLabel(for: recommendation.sources),
            actionLabel: actionLabel(for: recommendation.action)
        )
    }

    private static func observedColors(
        in recommendation: GroundedRecommendation
    ) -> [CanonicalColorReference] {
        recommendation.references.compactMap { reference in
            if case let .color(color, role: .observed) = reference { return color }
            return nil
        }
    }

    private static func joined(_ values: [String]) -> String {
        switch values.count {
        case 0: return "the visible colors"
        case 1: return values[0]
        case 2: return values.joined(separator: " and ")
        default: return values.dropLast().joined(separator: ", ") + ", and " + (values.last ?? "")
        }
    }

    private static func suggestedName(
        garment: CanonicalGarmentReference,
        color: CanonicalColorReference?
    ) -> String {
        [color?.displayName, garment.displayName].compactMap { $0 }.joined(separator: " ")
    }

    private static func sourceLabel(
        for sources: Set<RecommendationEvidenceSource>
    ) -> String {
        let labels = sources.sorted { $0.rawValue < $1.rawValue }.map { source in
            switch source {
            case .photo: return "Based on the photo"
            case .selectedOccasion: return "Based on the selected occasion"
            case .weather: return "Based on current weather"
            case .savedProfile: return "Based on your saved size profile"
            }
        }
        return labels.joined(separator: " • ")
    }

    private static func actionLabel(
        for action: GroundedRecommendationAction
    ) -> String? {
        switch action {
        case .seeExamples: return "See examples"
        case .shopSimilar: return "Shop similar"
        case .none: return nil
        }
    }
}
