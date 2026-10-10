import Foundation

struct OpenAIStylistClient {
    var model: String

    /// The client no longer accepts or stores a provider credential. The active
    /// Stylist path is the authenticated Worker transport.
    init(model: String) {
        self.model = model
    }

    static let systemInstruction = StyleMatchAIGuardrails.directOpenAIStylistSystemInstruction

    func askStylist(
        profile: StyleMatchStylistProfile,
        question: String,
        routeContext: ChatContext? = nil,
        debugRequestLabel: String? = nil,
        debugMessageSources: [String] = []
    ) async throws -> String {
        try await askStylist(
            profile: profile,
            messages: [],
            question: question,
            routeContext: routeContext,
            debugRequestLabel: debugRequestLabel,
            debugMessageSources: debugMessageSources
        )
    }

    func askStylist(
        profile: StyleMatchStylistProfile,
        messages: [AIChatMessage],
        question: String,
        routeContext: ChatContext? = nil,
        debugRequestLabel: String? = nil,
        debugMessageSources: [String] = []
    ) async throws -> String {
        guard let configuration = StylistChatConfiguration.production else {
            throw OpenAIStylistError.invalidResponse
        }

        let preparedQuestion = StylistChatMessageLimit.trimmedForSending(question)
        guard !preparedQuestion.isEmpty else { throw StylistChatError.invalidRequest }
        guard StylistChatMessageLimit.isWithinLimit(preparedQuestion) else {
            throw StylistChatError.payloadTooLarge
        }
        let recentMessages = messages.compactMap { message -> ChatRequest.RequestMessage? in
            let content = StylistChatMessageLimit.trimmedForSending(message.text)
            guard !content.isEmpty, StylistChatMessageLimit.isWithinLimit(content) else { return nil }
            return ChatRequest.RequestMessage(
                role: message.role == .customer ? "user" : "assistant",
                content: content
            )
        }
        let requestMessages = Array(recentMessages.suffix(19))
            + [ChatRequest.RequestMessage(role: "user", content: preparedQuestion)]
        if let validationError = StylistChatMessageLimit.validationError(for: requestMessages) {
            throw validationError
        }
        let supplementalContext = PersonalizationContextBuilder.legacyChatContext(for: profile, question: preparedQuestion)
        let context = routeContext.map {
            StylistRouteContextPipeline.applying($0, to: supplementalContext)
        } ?? supplementalContext
        let request = ChatRequest(messages: requestMessages, context: context, stream: true)
        #if DEBUG
        if let debugRequestLabel {
            _ = debugRequestLabel
            assert(requestMessages.allSatisfy { $0.content.utf16.count <= 2_000 })
        }
        #endif
        let transport = LiveChatTransport(configuration: configuration)
        var response = ""

        do {
            for try await token in transport.send(request) {
                response += token
            }
        } catch let error as StylistChatDiagnosticError {
            throw error
        } catch let error as StylistChatError {
            throw error
        } catch {
            throw OpenAIStylistError.api(message: "The AI Stylist is unavailable right now.")
        }

        let cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw OpenAIStylistError.emptyOutput }
        return cleaned
    }

    private func askChatCompletions(
        profile: StyleMatchStylistProfile,
        messages: [AIChatMessage],
        question: String,
        model selectedModel: String,
        tokenLimitStyle: OpenAIChatCompletionRequest.TokenLimitStyle
    ) async throws -> String {
        // Kept only as a source-compatible private shim for older local tests. Production AI
        // requests are dispatched through LiveChatTransport above.
        throw OpenAIStylistError.invalidResponse
    }

    private func chatCompletionMessages(profile: StyleMatchStylistProfile, messages: [AIChatMessage], question: String) -> [OpenAIChatCompletionRequest.Message] {
        // This source-compatible private shim is inert in production; it must
        // not become a second context assembler.
        let profileContext = ""
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
