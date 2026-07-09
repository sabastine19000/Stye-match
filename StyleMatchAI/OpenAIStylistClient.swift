import Foundation

struct OpenAIStylistClient {
    var apiKey: String
    var model: String

    static let systemInstruction = StyleMatchAIGuardrails.directOpenAIStylistSystemInstruction

    func askStylist(profile: StyleMatchStylistProfile, question: String) async throws -> String {
        try await askStylist(profile: profile, messages: [], question: question)
    }

    func askStylist(profile: StyleMatchStylistProfile, messages: [AIChatMessage], question: String) async throws -> String {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OpenAIStylistError.missingAPIKey
        }

        var lastError: Error?
        for selectedModel in fallbackModelNames(preferred: resolvedModelName(from: model)) {
            do {
                return try await askChatCompletions(
                    profile: profile,
                    messages: messages,
                    question: question,
                    model: selectedModel,
                    tokenLimitStyle: .maxCompletionTokens
                )
            } catch OpenAIStylistError.api(let message) where shouldRetryWithLegacyMaxTokens(message) {
                do {
                    return try await askChatCompletions(
                        profile: profile,
                        messages: messages,
                        question: question,
                        model: selectedModel,
                        tokenLimitStyle: .maxTokens
                    )
                } catch {
                    lastError = error
                    if !shouldTryFallbackModel(after: error) {
                        throw error
                    }
                }
            } catch {
                lastError = error
                if !shouldTryFallbackModel(after: error) {
                    throw error
                }
            }
        }

        throw lastError ?? OpenAIStylistError.emptyOutput
    }

    private func askChatCompletions(
        profile: StyleMatchStylistProfile,
        messages: [AIChatMessage],
        question: String,
        model selectedModel: String,
        tokenLimitStyle: OpenAIChatCompletionRequest.TokenLimitStyle
    ) async throws -> String {
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            throw OpenAIStylistError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        // Approved live AI dispatch point:
        // ContentView chat/founder verification, ScanView score explanation/design assist,
        // AIAssistantsView main stylist chat, AIStyleAdvisor quick advice, and ShopView sale ranking.
        // Every request receives PersonalizationContextBuilder context plus the canonical score guard here.
        let body = OpenAIChatCompletionRequest(
            model: selectedModel,
            maxTokens: 1_800,
            tokenLimitStyle: tokenLimitStyle,
            temperature: supportsCustomTemperature(selectedModel) ? (question.localizedCaseInsensitiveContains("Return ONLY valid JSON") ? 0.2 : 0.7) : nil,
            messages: chatCompletionMessages(profile: profile, messages: messages, question: question)
        )

        #if DEBUG
        print(debugPromptLog(for: body.messages, model: selectedModel))
        #endif

        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIStylistError.invalidResponse
        }

        if !(200...299).contains(httpResponse.statusCode) {
            let apiError = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data)
            throw OpenAIStylistError.api(message: readableAPIError(statusCode: httpResponse.statusCode, message: apiError?.error.message, model: selectedModel))
        }

        let decoded = try JSONDecoder().decode(OpenAIChatCompletionResponse.self, from: data)
        let text = decoded.choices
            .map(\.message.content)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else {
            throw OpenAIStylistError.emptyOutput
        }

        return text
    }

    private func chatCompletionMessages(profile: StyleMatchStylistProfile, messages: [AIChatMessage], question: String) -> [OpenAIChatCompletionRequest.Message] {
        let profileContext = profileContextBlock(profile: profile, question: question)
        var apiMessages: [OpenAIChatCompletionRequest.Message] = [
            .init(
                role: "system",
                content: Self.systemInstruction
            ),
            .init(
                role: "user",
                content: """
                StyleMatch Pro customer context:
                \(profileContext.isEmpty ? "No saved personalization context. Give general, high-quality styling advice." : profileContext)
                """
            )
        ]

        apiMessages.append(contentsOf: messages.suffix(16).map { message in
            OpenAIChatCompletionRequest.Message(
                role: message.role == .customer ? "user" : "assistant",
                content: message.text
            )
        })

        apiMessages.append(.init(role: "user", content: question))
        return apiMessages
    }

    private func profileContextBlock(profile: StyleMatchStylistProfile, question: String) -> String {
        var lines: [String] = []
        appendContextLine("Favorite colors", profile.favoriteColors, to: &lines)
        appendContextLine("Favorite brands", profile.favoriteBrands, to: &lines)
        appendContextLine("Preferred fit", profile.preferredFit, to: &lines)
        appendContextLine("Budget", profile.budget, to: &lines)
        appendContextLine("Size profile", profile.sizeProfile, to: &lines)
        appendContextLine("Style preferences", profile.stylePreferences, to: &lines)
        appendContextLine("Occasions", profile.occasions, to: &lines)
        appendContextLine("Weather", profile.weather, to: &lines)
        appendContextLine("Weather preferences", profile.weatherPreferences, to: &lines)
        appendContextLine("Dress code", profile.dressCode, to: &lines)
        appendContextLine("Shopping habits", profile.shoppingHabits, to: &lines)
        appendContextLine("Past outfit ratings", profile.pastOutfitRatings, to: &lines)
        appendContextLine("Frequently worn outfits", profile.frequentlyWornOutfits, to: &lines)
        appendContextLine("Past purchases", profile.pastPurchases, to: &lines)
        appendContextLine("Favorite outfits", profile.favoriteOutfits, to: &lines)
        appendContextLine("Closet inventory", profile.closetInventory, to: &lines)

        let existingContextText = ([question] + lines + [profile.appContext]).joined(separator: "\n")
        let alreadyHasPersonalization = existingContextText.contains("User style context:")
            || existingContextText.contains(StyleMatchAIGuardrails.scoreIntegrityInstruction)
        if !alreadyHasPersonalization {
            appendContextLine("Personalization context", PersonalizationContextBuilder.promptContext(), to: &lines)
        }

        if profile.appContextSharingEnabled {
            appendContextLine("App context", profile.appContext, to: &lines)
        }

        return lines.joined(separator: "\n")
    }

    private func appendContextLine(_ label: String, _ value: String, to lines: inout [String]) {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isMeaningfulContextValue(cleaned) else {
            return
        }

        lines.append("- \(label): \(cleaned)")
    }

    private func isMeaningfulContextValue(_ value: String) -> Bool {
        guard !value.isEmpty else {
            return false
        }

        let normalized = value.lowercased()
        let emptyMarkers = [
            "style match pro user",
            "stylematch pro user",
            "not set",
            "none",
            "none saved yet",
            "no personal stylist context is saved yet",
            "no closet items saved yet.",
            "no recent scans saved yet.",
            "no saved outfit ratings yet.",
            "no saved personalization context.",
            "context sharing is off.",
            "app context sharing is off. use only the customer message and manually provided profile fields."
        ]

        return !emptyMarkers.contains(normalized)
    }

    #if DEBUG
    private func debugPromptLog(for messages: [OpenAIChatCompletionRequest.Message], model: String) -> String {
        let prompt = messages
            .map { "[\($0.role)] \($0.content)" }
            .joined(separator: "\n\n")
        return "[StyleMatch AI Prompt Debug] model=\(model)\n\(prompt)"
    }
    #endif

    private func conversationText(from messages: [AIChatMessage]) -> String {
        guard !messages.isEmpty else {
            return "No previous messages."
        }

        return messages.suffix(4).map { message in
            "\(message.role.label): \(message.text)"
        }.joined(separator: "\n")
    }

    private func resolvedModelName(from rawModel: String) -> String {
        let trimmed = rawModel.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "gpt-4o-mini" : trimmed
    }

    private func fallbackModelNames(preferred: String) -> [String] {
        var models: [String] = []
        for candidate in [preferred, "gpt-4o-mini", "gpt-4.1-mini"] {
            if !models.contains(candidate) {
                models.append(candidate)
            }
        }
        return models
    }

    private func supportsCustomTemperature(_ model: String) -> Bool {
        let normalized = model.lowercased()
        return !normalized.hasPrefix("gpt-5") && !normalized.hasPrefix("o1") && !normalized.hasPrefix("o3") && !normalized.hasPrefix("o4")
    }

    private func shouldRetryWithLegacyMaxTokens(_ message: String) -> Bool {
        let lower = message.lowercased()
        return lower.contains("max_completion_tokens") && lower.contains("unsupported")
    }

    private func shouldTryFallbackModel(after error: Error) -> Bool {
        guard let stylistError = error as? OpenAIStylistError else {
            return false
        }

        switch stylistError {
        case .api(let message):
            let lower = message.lowercased()
            return lower.contains("model")
                || lower.contains("not available")
                || lower.contains("unsupported")
                || lower.contains("max_tokens")
                || lower.contains("max_completion_tokens")
        case .emptyOutput:
            return true
        case .missingAPIKey, .invalidResponse:
            return false
        }
    }

    private func readableAPIError(statusCode: Int, message: String?, model: String) -> String {
        let detail = message ?? "OpenAI returned status \(statusCode)."
        switch statusCode {
        case 401:
            return "ChatGPT could not sign in here. Check the ChatGPT setup and try again."
        case 402, 429:
            return "ChatGPT cannot answer right now. Check your ChatGPT account and try again."
        case 404:
            return "This ChatGPT option is not available right now. Try another speed option or check your ChatGPT account."
        default:
            return detail
        }
    }
}

struct StyleMatchStylistProfile {
    var name: String
    var favoriteColors: String
    var favoriteBrands: String
    var preferredFit: String
    var budget: String
    var sizeProfile: String
    var stylePreferences: String
    var occasions: String
    var weather: String
    var weatherPreferences: String
    var dressCode: String
    var shoppingHabits: String
    var pastOutfitRatings: String
    var frequentlyWornOutfits: String
    var pastPurchases: String
    var favoriteOutfits: String
    var closetInventory: String
    var appContextSharingEnabled: Bool
    var appContext: String
}

struct AIChatMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let role: Role
    var text: String
    let createdAt: Date
    var edited: Bool
    var editedAt: Date?

    var isEdited: Bool {
        edited || editedAt != nil
    }

    init(
        id: UUID = UUID(),
        role: Role,
        text: String,
        createdAt: Date = Date(),
        edited: Bool = false,
        editedAt: Date? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
        self.edited = edited || editedAt != nil
        self.editedAt = editedAt
    }

    enum Role: String, Codable {
        case customer
        case assistant

        var label: String {
            switch self {
            case .customer:
                return "Customer"
            case .assistant:
                return "ChatGPT"
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case role
        case text
        case createdAt
        case edited
        case editedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        role = try container.decode(Role.self, forKey: .role)
        text = try container.decode(String.self, forKey: .text)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        editedAt = try container.decodeIfPresent(Date.self, forKey: .editedAt)
        edited = try container.decodeIfPresent(Bool.self, forKey: .edited) ?? (editedAt != nil)
    }
}

private struct OpenAIChatCompletionRequest: Encodable {
    let model: String
    let maxTokens: Int
    let tokenLimitStyle: TokenLimitStyle
    let temperature: Double?
    let messages: [Message]

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case maxCompletionTokens = "max_completion_tokens"
        case temperature
        case messages
    }

    enum TokenLimitStyle {
        case maxCompletionTokens
        case maxTokens
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        switch tokenLimitStyle {
        case .maxCompletionTokens:
            try container.encode(maxTokens, forKey: .maxCompletionTokens)
        case .maxTokens:
            try container.encode(maxTokens, forKey: .maxTokens)
        }
        try container.encodeIfPresent(temperature, forKey: .temperature)
        try container.encode(messages, forKey: .messages)
    }

    struct Message: Encodable {
        let role: String
        let content: String
    }
}

private struct OpenAIChatCompletionResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let content: String
    }
}

private struct OpenAIErrorResponse: Decodable {
    let error: APIError

    struct APIError: Decodable {
        let message: String
    }
}

enum OpenAIStylistError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case emptyOutput
    case api(message: String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Choose ChatGPT as your assistant first."
        case .invalidResponse:
            return "The AI service returned an invalid response."
        case .emptyOutput:
            return "The AI service answered without usable text."
        case .api(let message):
            return message
        }
    }
}
