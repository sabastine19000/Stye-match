import Foundation

enum StyleMatchAIProvider: String, Codable {
    case chatGPT
    case claude
    case gemini
    case perplexity

    static func named(_ rawValue: String) -> StyleMatchAIProvider? {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "chatgpt", "chat_gpt", "openai":
            return .chatGPT
        case "claude", "anthropic":
            return .claude
        case "gemini", "google":
            return .gemini
        case "perplexity":
            return .perplexity
        default:
            return nil
        }
    }

    var displayName: String {
        switch self {
        case .chatGPT:
            return "ChatGPT"
        case .claude:
            return "Claude"
        case .gemini:
            return "Gemini"
        case .perplexity:
            return "Perplexity"
        }
    }

    var supportsImageAnalysis: Bool {
        false
    }
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

    func key(for provider: StyleMatchAIProvider) -> String? {
        let value: String?
        switch provider {
        case .chatGPT:
            value = chatGPT
        case .claude:
            value = claude
        case .gemini:
            value = gemini
        case .perplexity:
            value = perplexity
        }

        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

struct ProviderAdapterOutcome {
    var result: ProviderAnalysisResult?
    var error: Bool
    var message: String?
    var provider: StyleMatchAIProvider?
    var attemptedProviders: [StyleMatchAIProvider]

    static func success(_ result: ProviderAnalysisResult, provider: StyleMatchAIProvider, attemptedProviders: [StyleMatchAIProvider]) -> ProviderAdapterOutcome {
        ProviderAdapterOutcome(
            result: result,
            error: false,
            message: nil,
            provider: provider,
            attemptedProviders: attemptedProviders
        )
    }

    static func failure(_ message: String, attemptedProviders: [StyleMatchAIProvider]) -> ProviderAdapterOutcome {
        ProviderAdapterOutcome(
            result: nil,
            error: true,
            message: message,
            provider: nil,
            attemptedProviders: attemptedProviders
        )
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

    static func runOutfitScan(
        imageBase64: String,
        context: StyleMatchAIContext,
        preferredProvider: StyleMatchAIProvider = .claude,
        apiKeys: StyleMatchProviderAPIKeys
    ) async -> ProviderAdapterOutcome {
        return .failure(
            "StyleMatch Pro uses its own local outfit detection and scoring engine. AI providers can explain completed scan results, but they do not analyze images or create scores.",
            attemptedProviders: [preferredProvider]
        )
    }

    static func runOutfitScan(
        imageBase64: String,
        context: StyleMatchAIContext,
        preferredProviderName: String,
        apiKeys: StyleMatchProviderAPIKeys
    ) async -> ProviderAdapterOutcome {
        guard let preferredProvider = StyleMatchAIProvider.named(preferredProviderName) else {
            return .failure("Selected AI provider not available.", attemptedProviders: [])
        }

        return await runOutfitScan(
            imageBase64: imageBase64,
            context: context,
            preferredProvider: preferredProvider,
            apiKeys: apiKeys
        )
    }

    private static func analyzeWithChatGPT(imageBase64: String, context: StyleMatchAIContext, apiKey: String, model: String = "gpt-4o-mini") async throws -> ProviderAnalysisResult {
        let requestBody = OpenAIImageRequest(
            model: model,
            maxCompletionTokens: 1200,
            messages: [
                OpenAIImageRequest.Message(
                    role: "user",
                    content: [
                        .text(OpenAIImageRequest.TextContent(text: context.prompt)),
                        .imageURL(OpenAIImageRequest.ImageURLContent(imageURL: .init(url: "data:image/jpeg;base64,\(imageBase64)")))
                    ]
                )
            ]
        )

        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            throw AIProviderAdapterError.invalidResponse(provider: StyleMatchAIProvider.chatGPT.rawValue)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTPResponse(response, data: data, provider: .chatGPT)
        let decoded = try JSONDecoder().decode(OpenAIImageResponse.self, from: data)
        let text = decoded.choices.map(\.message.content).joined(separator: "\n")
        return try parseAndValidate(text, provider: .chatGPT)
    }

    private static func analyzeWithClaude(imageBase64: String, context: StyleMatchAIContext, apiKey: String, model: String = "claude-sonnet-4-6") async throws -> ProviderAnalysisResult {
        let requestBody = ClaudeMessageRequest(
            model: model,
            maxTokens: 1200,
            messages: [
                ClaudeMessageRequest.Message(
                    role: "user",
                    content: [
                        .image(.init(source: .init(mediaType: "image/jpeg", data: imageBase64))),
                        .text(.init(text: context.prompt))
                    ]
                )
            ]
        )

        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw AIProviderAdapterError.invalidResponse(provider: StyleMatchAIProvider.claude.rawValue)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTPResponse(response, data: data, provider: .claude)
        let decoded = try JSONDecoder().decode(ClaudeMessageResponse.self, from: data)
        let text = decoded.content.compactMap { block -> String? in
            guard block.type == "text" else { return nil }
            return block.text
        }.joined()
        return try parseAndValidate(text, provider: .claude)
    }

    private static func analyzeWithGemini(imageBase64: String, context: StyleMatchAIContext, apiKey: String, model: String = "gemini-1.5-pro") async throws -> ProviderAnalysisResult {
        guard var components = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent") else {
            throw AIProviderAdapterError.invalidResponse(provider: StyleMatchAIProvider.gemini.rawValue)
        }
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]

        let requestBody = GeminiGenerateContentRequest(
            contents: [
                .init(parts: [
                    .text(.init(text: context.prompt)),
                    .inlineData(.init(inlineData: .init(mimeType: "image/jpeg", data: imageBase64)))
                ])
            ]
        )

        guard let url = components.url else {
            throw AIProviderAdapterError.invalidResponse(provider: StyleMatchAIProvider.gemini.rawValue)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTPResponse(response, data: data, provider: .gemini)
        let decoded = try JSONDecoder().decode(GeminiGenerateContentResponse.self, from: data)
        let text = decoded.candidates.first?.content.parts.compactMap(\.text).joined() ?? ""
        return try parseAndValidate(text, provider: .gemini)
    }

    static func askPerplexity(question: String, apiKey: String, model: String = "sonar-pro") async throws -> String {
        let requestBody = PerplexityChatRequest(
            model: model,
            messages: [.init(role: "user", content: question)]
        )

        guard let url = URL(string: "https://api.perplexity.ai/chat/completions") else {
            throw AIProviderAdapterError.invalidResponse(provider: StyleMatchAIProvider.perplexity.rawValue)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTPResponse(response, data: data, provider: .perplexity)
        let decoded = try JSONDecoder().decode(PerplexityChatResponse.self, from: data)
        return decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    static func parseAndValidate(_ rawText: String, provider: StyleMatchAIProvider) throws -> ProviderAnalysisResult {
        let cleaned = rawText
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let jsonText: String
        if let start = cleaned.firstIndex(of: "{"),
           let end = cleaned.lastIndex(of: "}"),
           start <= end {
            jsonText = String(cleaned[start...end])
        } else {
            jsonText = cleaned
        }

        guard let data = jsonText.data(using: .utf8) else {
            throw AIProviderAdapterError.parse(provider: provider.rawValue)
        }

        do {
            var parsed = try JSONDecoder().decode(ProviderAnalysisResult.self, from: data)
            parsed.provider = provider.rawValue
            return validateAnalysis(parsed)
        } catch {
            throw AIProviderAdapterError.parse(provider: provider.rawValue)
        }
    }

    static func validateAnalysis(_ result: ProviderAnalysisResult) -> ProviderAnalysisResult {
        let validColors = [
            "black", "white", "gray", "grey", "navy", "blue", "red", "green",
            "brown", "tan", "beige", "olive", "khaki", "maroon", "burgundy",
            "orange", "yellow", "purple", "pink", "cream", "charcoal", "denim"
        ]
        let filteredColors = result.garmentColors.filter { color in
            validColors.contains { valid in
                color.lowercased().contains(valid)
            }
        }

        return ProviderAnalysisResult(
            detectedGarments: unique(result.detectedGarments),
            garmentColors: filteredColors.isEmpty ? unique(result.garmentColors) : unique(filteredColors),
            detectedStyle: result.detectedStyle,
            styleConfidence: min(100, max(0, result.styleConfidence)),
            fitAssessment: result.fitAssessment,
            patterns: unique(result.patterns),
            providerReportedScore: nil,
            scoreReasoning: result.scoreReasoning,
            strengths: result.strengths,
            improvementTips: Array(unique(result.improvementTips).prefix(3)),
            occasionMatch: result.occasionMatch,
            weatherMatch: result.weatherMatch,
            followUpQuestion: result.followUpQuestion,
            provider: result.provider
        )
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { value in
            let key = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty, !seen.contains(key) else {
                return false
            }
            seen.insert(key)
            return true
        }
    }

    private static func validateHTTPResponse(_ response: URLResponse, data: Data, provider: StyleMatchAIProvider) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIProviderAdapterError.invalidResponse(provider: provider.rawValue)
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw AIProviderAdapterError.api(provider: provider.rawValue, statusCode: httpResponse.statusCode)
        }
    }

    private static func fallbackProviders(preferredProvider: StyleMatchAIProvider, apiKeys: StyleMatchProviderAPIKeys) -> [StyleMatchAIProvider] {
        let providerOrder: [StyleMatchAIProvider] = [
            preferredProvider,
            .claude,
            .chatGPT,
            .gemini
        ]

        var seen = Set<StyleMatchAIProvider>()
        return providerOrder.filter { provider in
            guard provider.supportsImageAnalysis, !seen.contains(provider) else {
                return false
            }
            seen.insert(provider)
            return apiKeys.key(for: provider) != nil || provider == preferredProvider
        }
    }

    private static func analyze(imageBase64: String, context: StyleMatchAIContext, provider: StyleMatchAIProvider, apiKey: String) async throws -> ProviderAnalysisResult {
        switch provider {
        case .chatGPT:
            return try await analyzeWithChatGPT(imageBase64: imageBase64, context: context, apiKey: apiKey)
        case .claude:
            return try await analyzeWithClaude(imageBase64: imageBase64, context: context, apiKey: apiKey)
        case .gemini:
            return try await analyzeWithGemini(imageBase64: imageBase64, context: context, apiKey: apiKey)
        case .perplexity:
            throw AIProviderAdapterError.imageAnalysisUnavailable(provider: provider.rawValue)
        }
    }
}

enum AIProviderAdapterError: LocalizedError {
    case invalidResponse(provider: String)
    case api(provider: String, statusCode: Int)
    case parse(provider: String)
    case imageAnalysisUnavailable(provider: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse(let provider):
            return "\(provider) returned an invalid response."
        case .api(let provider, let statusCode):
            return "\(provider) returned status \(statusCode). Please try again."
        case .parse(let provider):
            return "\(provider) response could not be parsed into StyleMatch Pro analysis JSON."
        case .imageAnalysisUnavailable(let provider):
            return "\(provider) is not available for image outfit scans."
        }
    }
}

private struct OpenAIImageRequest: Encodable {
    let model: String
    let maxCompletionTokens: Int
    let messages: [Message]

    enum CodingKeys: String, CodingKey {
        case model
        case maxCompletionTokens = "max_completion_tokens"
        case messages
    }

    struct Message: Encodable {
        let role: String
        let content: [Content]
    }

    enum Content: Encodable {
        case text(TextContent)
        case imageURL(ImageURLContent)

        func encode(to encoder: Encoder) throws {
            switch self {
            case .text(let content):
                try content.encode(to: encoder)
            case .imageURL(let content):
                try content.encode(to: encoder)
            }
        }
    }

    struct TextContent: Encodable {
        let type = "text"
        let text: String
    }

    struct ImageURLContent: Encodable {
        let type = "image_url"
        let imageURL: ImageURL

        enum CodingKeys: String, CodingKey {
            case type
            case imageURL = "image_url"
        }

        struct ImageURL: Encodable {
            let url: String
        }
    }
}

private struct OpenAIImageResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let content: String
    }
}

private struct ClaudeMessageRequest: Encodable {
    let model: String
    let maxTokens: Int
    let messages: [Message]

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case messages
    }

    struct Message: Encodable {
        let role: String
        let content: [Content]
    }

    enum Content: Encodable {
        case image(ImageContent)
        case text(TextContent)

        func encode(to encoder: Encoder) throws {
            switch self {
            case .image(let content):
                try content.encode(to: encoder)
            case .text(let content):
                try content.encode(to: encoder)
            }
        }
    }

    struct ImageContent: Encodable {
        let type = "image"
        let source: ImageSource
    }

    struct ImageSource: Encodable {
        let type = "base64"
        let mediaType: String
        let data: String

        enum CodingKeys: String, CodingKey {
            case type
            case mediaType = "media_type"
            case data
        }
    }

    struct TextContent: Encodable {
        let type = "text"
        let text: String
    }
}

private struct ClaudeMessageResponse: Decodable {
    let content: [Content]

    struct Content: Decodable {
        let type: String
        let text: String?
    }
}

private struct GeminiGenerateContentRequest: Encodable {
    let contents: [Content]

    struct Content: Encodable {
        let parts: [Part]
    }

    enum Part: Encodable {
        case text(TextPart)
        case inlineData(InlineDataPart)

        func encode(to encoder: Encoder) throws {
            switch self {
            case .text(let part):
                try part.encode(to: encoder)
            case .inlineData(let part):
                try part.encode(to: encoder)
            }
        }
    }

    struct TextPart: Encodable {
        let text: String
    }

    struct InlineDataPart: Encodable {
        let inlineData: InlineData

        enum CodingKeys: String, CodingKey {
            case inlineData = "inline_data"
        }
    }

    struct InlineData: Encodable {
        let mimeType: String
        let data: String

        enum CodingKeys: String, CodingKey {
            case mimeType = "mime_type"
            case data
        }
    }
}

private struct GeminiGenerateContentResponse: Decodable {
    let candidates: [Candidate]

    struct Candidate: Decodable {
        let content: Content
    }

    struct Content: Decodable {
        let parts: [Part]
    }

    struct Part: Decodable {
        let text: String?
    }
}

private struct PerplexityChatRequest: Encodable {
    let model: String
    let messages: [Message]

    struct Message: Encodable {
        let role: String
        let content: String
    }
}

private struct PerplexityChatResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let content: String
    }
}
