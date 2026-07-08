import Foundation

struct StylistScoreMessageInput {
    let score: Int
    let scoreTier: String
    let scoreBreakdown: OutfitScoreBreakdown?
    let detectedGarments: [String]
    let colors: [String]

    init(
        score: Int,
        scoreTier: String,
        scoreBreakdown: OutfitScoreBreakdown?,
        detectedGarments: [String],
        colors: [String]
    ) {
        self.score = min(100, max(0, score))
        self.scoreTier = scoreTier.trimmingCharacters(in: .whitespacesAndNewlines)
        self.scoreBreakdown = scoreBreakdown
        self.detectedGarments = detectedGarments
        self.colors = colors
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
        let attribute = strongestDetectedAttribute(garments: input.detectedGarments, colors: input.colors)
        let improvement = concreteImprovement(input)
        let scoreText = "\(input.score)/100"

        let body: String
        switch band {
        case .enthusiastic:
            body = "Great outfit choice. Your style score is strong today at \(scoreText), and \(attribute) gives the scan a clear anchor."
        case .confidentPositive:
            body = "This is a confident look at \(scoreText). \(attribute) is working well, and the outfit has a solid foundation."
        case .encouragingImprovement:
            body = "This outfit has a useful base at \(scoreText), especially with \(attribute). One concrete improvement: \(improvement)."
        case .constructiveKind:
            body = "This scan landed at \(scoreText), so keep the feedback practical and kind. Start with \(attribute), then make one fix: \(improvement)."
        }

        return PersonalStylistMessageSection(
            title: "Stylist Encouragement",
            body: body,
            source: .score
        )
    }

    private static func strongestDetectedAttribute(garments: [String], colors: [String]) -> String {
        if let garment = garments.map(clean).first(where: { !$0.isEmpty }) {
            if let color = colors.map(clean).first(where: { !$0.isEmpty }) {
                return "the detected \(color) \(garment)"
            }
            return "the detected \(garment)"
        }

        if let color = colors.map(clean).first(where: { !$0.isEmpty }) {
            return "the detected \(color) color"
        }

        return "the score itself"
    }

    private static func concreteImprovement(_ input: StylistScoreMessageInput) -> String {
        guard let breakdown = input.scoreBreakdown else {
            return "tighten one visible detail such as fit, shoe coordination, or accessories"
        }

        let weakest = [
            ("color harmony", breakdown.colorHarmony, 25, "simplify the color mix or repeat one color intentionally"),
            ("pattern balance", breakdown.patternBalance, 20, "keep one pattern as the focus and let the other pieces stay quieter"),
            ("fit quality", breakdown.fitQuality, 25, "adjust the fit so hems, sleeves, and waist sit cleaner"),
            ("occasion match", breakdown.occasionMatch, 20, "swap one piece so the outfit matches the planned occasion more clearly"),
            ("accessories", breakdown.accessoryUse, 10, "add one simple accessory that supports the outfit without overpowering it")
        ]
        .sorted { first, second in
            let firstRatio = Double(first.1) / Double(first.2)
            let secondRatio = Double(second.1) / Double(second.2)
            if firstRatio == secondRatio { return first.0 < second.0 }
            return firstRatio < secondRatio
        }
        .first

        return weakest?.3 ?? "tighten one visible detail such as fit, shoe coordination, or accessories"
    }

    private static func clean(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
