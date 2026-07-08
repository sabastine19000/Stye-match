import Foundation

struct VoiceScriptBuilder {
    static let maximumSpokenCharacters = 320

    static func scanStarted() -> VoiceScript {
        VoiceScript(
            id: "scan-started",
            kind: .scanStarted,
            text: "Starting your outfit scan. I’ll keep the summary short and focus on the most useful style details."
        )
    }

    static func scanResult(from analysis: OutfitAnalysisResult) -> VoiceScript {
        let score = min(max(analysis.score, 0), 100)
        let style = spokenStyleName(from: analysis.styleBalance)
        let rating = scoreRating(for: score).lowercased()
        let primaryFeedback = strongestPlainLanguageSignal(from: analysis)
        let nextAction = nextActionSuggestion(from: analysis)

        var sentences: [String] = []
        if style == "unrecognized" {
            sentences.append("I could not identify this outfit clearly enough to give confident style guidance.")
        } else {
            sentences.append("Your outfit score is \(score). This is a \(rating) \(style) look.")
        }

        if let primaryFeedback {
            sentences.append(primaryFeedback)
        }

        if let nextAction {
            sentences.append(nextAction)
        }

        return VoiceScript(
            id: "scan-result-\(score)-\(style)",
            kind: .scanResult,
            text: sentences.joined(separator: " ")
        )
    }

    static func scanFailed(title: String, description: String) -> VoiceScript {
        let message: String
        if title.localizedCaseInsensitiveContains("outfit")
            || description.localizedCaseInsensitiveContains("clothing")
            || description.localizedCaseInsensitiveContains("photo") {
            message = "\(title). Try a clearer, fuller photo with the clothing visible."
        } else {
            message = "\(title). \(description)"
        }

        return VoiceScript(id: "scan-failed", kind: .scanFailed, text: message)
    }

    static func profileSaved() -> VoiceScript {
        VoiceScript(
            id: "profile-saved",
            kind: .profileSaved,
            text: "Profile saved. I’ll use these preferences to keep your style advice more personal."
        )
    }

    static func appGuide(destination: String) -> VoiceScript {
        let normalized = destination.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let text: String
        switch normalized {
        case "scan":
            text = "Use Scan to check an outfit, hear your score, and get one or two improvement ideas."
        case "closet":
            text = "Use Closet to save clothing you own, so I can help build outfits from your real wardrobe."
        case "shop", "shopping":
            text = "Use Shopping to find pieces that match your closet. Purchases still happen with the retailer."
        case "ai", "stylist", "ai stylist":
            text = "Use AI Stylist when you want quick outfit advice or help understanding a score."
        default:
            text = "I can help you scan outfits, review your closet, understand scores, and find better matching pieces."
        }
        return VoiceScript(id: "guide-\(normalized)", kind: .appGuide, text: text)
    }

    static func preview() -> VoiceScript {
        VoiceScript(
            id: "voice-preview",
            kind: .preview,
            text: "Hi, I’m your StyleMatch voice assistant. I’ll keep outfit advice clear, brief, and useful."
        )
    }

    static func trimmedScript(_ text: String) -> String {
        var cleaned = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        while cleaned.contains("  ") {
            cleaned = cleaned.replacingOccurrences(of: "  ", with: " ")
        }

        guard cleaned.count > maximumSpokenCharacters else { return cleaned }
        return String(cleaned.prefix(maximumSpokenCharacters - 3)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    private static func strongestPlainLanguageSignal(from analysis: OutfitAnalysisResult) -> String? {
        for candidate in [analysis.summary, analysis.colorHarmony, analysis.occasionFit] {
            let cleaned = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty {
                return shortSentence(cleaned)
            }
        }
        return nil
    }

    private static func nextActionSuggestion(from analysis: OutfitAnalysisResult) -> String? {
        if let recommendation = analysis.recommendations.first {
            return "Next, consider \(recommendation.title.lowercased())."
        }

        if let suggestion = analysis.suggestions.first {
            return shortSentence(suggestion)
        }

        return "Would you like better matching item ideas?"
    }

    private static func spokenStyleName(from rawStyle: String) -> String {
        let trimmed = rawStyle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "casual" }

        let lowered = trimmed.lowercased()
        if lowered.contains("unknown") || lowered.contains("unrecognized") || lowered.contains("could not") {
            return "unrecognized"
        }

        let firstClause = trimmed
            .split(whereSeparator: { [".", ",", ";", ":", "\n"].contains(String($0)) })
            .first
            .map(String.init) ?? trimmed

        return firstClause.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func scoreRating(for score: Int) -> String {
        if score >= 90 { return "Excellent" }
        if score >= 75 { return "Strong" }
        if score >= 60 { return "Good" }
        return "Needs improvement"
    }

    private static func shortSentence(_ text: String) -> String {
        var cleaned = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let firstSentence = cleaned.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: true).first {
            cleaned = String(firstSentence).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if cleaned.count > 120 {
            cleaned = String(cleaned.prefix(117)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
        }

        if cleaned.last.map({ ".!?".contains($0) }) != true {
            cleaned += "."
        }

        return cleaned
    }
}

