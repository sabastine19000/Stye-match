import Foundation

enum StyleMatchAIProvider: String, Codable {
    case chatGPT
    case claude
    case gemini
    case perplexity

    static func named(_ rawValue: String) -> StyleMatchAIProvider? {
        let provider: StyleMatchAIProvider?
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "chatgpt", "chat_gpt", "openai": provider = .chatGPT
        case "claude", "anthropic": provider = .claude
        case "gemini", "google": provider = .gemini
        case "perplexity": provider = .perplexity
        default: provider = nil
        }
        guard let provider else { return nil }
        return StyleMatchAIProviderAdapters.isProviderReachable(provider) ? provider : nil
    }

    var displayName: String {
        switch self {
        case .chatGPT: "ChatGPT"
        case .claude: "Claude"
        case .gemini: "Gemini"
        case .perplexity: "Perplexity"
        }
    }

    var supportsImageAnalysis: Bool { false }
}

struct StyleMatchAIContext {
    let prompt: String
    let imageBase64: String?
}

struct StyleMatchProviderAPIKeys {
    var chatGPT: String?
    var claude: String?
    var gemini: String?
    var perplexity: String?
}

struct ProviderAdapterOutcome {
    var result: ProviderAnalysisResult?
    var error: Bool
    var message: String?
    var provider: StyleMatchAIProvider?
    var attemptedProviders: [StyleMatchAIProvider]

    static func failure(_ message: String, attemptedProviders: [StyleMatchAIProvider]) -> ProviderAdapterOutcome {
        ProviderAdapterOutcome(result: nil, error: true, message: message, provider: nil, attemptedProviders: attemptedProviders)
    }
}

struct ProviderAnalysisResult: Codable {
    var detectedGarments: [String]
    var garmentColors: [String]
    var detectedStyle: String
    var styleConfidence: Int
    var fitAssessment: String
    var patterns: [String]
    var providerReportedScore: Int?
    var scoreReasoning: String
    var strengths: String
    var improvementTips: [String]
    var occasionMatch: String
    var weatherMatch: String
    var followUpQuestion: String
    var provider: String?

    enum CodingKeys: String, CodingKey {
        case detectedGarments = "detected_garments"
        case garmentColors = "garment_colors"
        case detectedStyle = "detected_style"
        case styleConfidence = "style_confidence"
        case fitAssessment = "fit_assessment"
        case patterns
        case providerReportedScore = "overall_style_score"
        case scoreReasoning = "score_reasoning"
        case strengths
        case improvementTips = "improvement_tips"
        case occasionMatch = "occasion_match"
        case weatherMatch = "weather_match"
        case followUpQuestion = "follow_up_question"
        case provider = "_provider"
    }
}

struct StyleMatchAIProviderAdapters {
    static let imageAnalysisProviders: [StyleMatchAIProvider] = []

    static func isProviderReachable(_ provider: StyleMatchAIProvider) -> Bool {
        provider == .chatGPT
    }

    static func runOutfitScan(
        imageBase64: String,
        context: StyleMatchAIContext,
        preferredProvider: StyleMatchAIProvider = .chatGPT,
        apiKeys: StyleMatchProviderAPIKeys
    ) async -> ProviderAdapterOutcome {
        .failure(
            "StyleMatch Pro analyzes outfit photos on this device. External AI may explain completed scan results, but it does not receive photos or create scores.",
            attemptedProviders: []
        )
    }

    static func runOutfitScan(
        imageBase64: String,
        context: StyleMatchAIContext,
        preferredProviderName: String,
        apiKeys: StyleMatchProviderAPIKeys
    ) async -> ProviderAdapterOutcome {
        await runOutfitScan(imageBase64: imageBase64, context: context, apiKeys: apiKeys)
    }
}

enum AIProviderAdapterError: LocalizedError {
    case imageAnalysisUnavailable(provider: String)

    var errorDescription: String? {
        switch self {
        case .imageAnalysisUnavailable(let provider):
            "\(provider) is not available for image outfit scans."
        }
    }
}
