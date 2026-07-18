import Foundation

enum StylistChatRole: String, Codable, Equatable {
    case user
    case assistant
    case system
}

struct ChatMessage: Identifiable, Codable, Equatable {
    var id: UUID
    var role: StylistChatRole
    var content: String
    var timestamp: Date

    init(
        id: UUID = UUID(),
        role: StylistChatRole,
        content: String,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}

struct ChatConversation: Identifiable, Codable, Equatable {
    var id: UUID
    var messages: [ChatMessage]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        messages: [ChatMessage] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        messages = try container.decodeIfPresent([ChatMessage].self, forKey: .messages) ?? []
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }
}

struct ChatContext: Codable, Equatable {
    var profileSummary: String
    var recentOutfits: String
    var scoreBreakdown: String?

    init(
        profileSummary: String = "",
        recentOutfits: String = "",
        scoreBreakdown: String? = nil
    ) {
        self.profileSummary = Self.clamp(profileSummary, max: 600)
        self.recentOutfits = Self.clamp(recentOutfits, max: 800)
        self.scoreBreakdown = scoreBreakdown.map { Self.clamp($0, max: 500) }
    }

    private static func clamp(_ text: String, max: Int) -> String {
        String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(max))
    }
}

struct ChatRequest: Codable, Equatable {
    struct RequestMessage: Codable, Equatable {
        let role: String
        let content: String
    }

    let messages: [RequestMessage]
    let context: ChatContext
    let stream: Bool
}

enum StylistChatMessageLimit {
    static let maximumUTF16Length = 2_000
    static let maximumPayloadMessages = 20
    static let retainedConversationMessages = 12
    static let limitMessage = "Messages are limited to 2,000 characters. Shorten your message before sending."

    static func utf16Length(of text: String) -> Int {
        text.utf16.count
    }

    static func trimmedForSending(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isWithinLimit(_ text: String) -> Bool {
        utf16Length(of: text) <= maximumUTF16Length
    }

    static func validationError(for messages: [ChatRequest.RequestMessage]) -> StylistChatError? {
        guard messages.count <= maximumPayloadMessages else { return .payloadTooLarge }
        for message in messages {
            let trimmed = trimmedForSending(message.content)
            guard !trimmed.isEmpty else { return .invalidRequest }
            guard isWithinLimit(message.content) else { return .payloadTooLarge }
        }
        return nil
    }
}

enum AIInsightConversationRole: Equatable {
    case user
    case assistant
}

struct AIInsightConversationEntry: Equatable {
    let role: AIInsightConversationRole
    let content: String
}

struct AIInsightStructuredRequest: Equatable {
    let history: [AIInsightConversationEntry]
    let latestPrompt: String
}

enum AIInsightStructuredHistoryBuilder {
    private static let genericLocalFailureReplies: Set<String> = [
        "AI Stylist is having trouble connecting right now. Please try again.",
        "The stylist is having trouble replying right now."
    ]

    static func build(
        displayedMessages: [AIInsightConversationEntry],
        latestPrompt: String
    ) throws -> AIInsightStructuredRequest {
        let preparedPrompt = StylistChatMessageLimit.trimmedForSending(latestPrompt)
        guard !preparedPrompt.isEmpty else {
            throw StylistChatError.invalidRequest
        }
        guard StylistChatMessageLimit.isWithinLimit(preparedPrompt) else {
            throw StylistChatError.payloadTooLarge
        }

        let eligibleHistory = displayedMessages.compactMap { entry -> AIInsightConversationEntry? in
            let content = StylistChatMessageLimit.trimmedForSending(entry.content)
            guard !content.isEmpty,
                  StylistChatMessageLimit.isWithinLimit(content) else {
                return nil
            }
            if entry.role == .assistant, genericLocalFailureReplies.contains(content) {
                return nil
            }
            return AIInsightConversationEntry(role: entry.role, content: content)
        }

        let maximumHistoryMessages = StylistChatMessageLimit.maximumPayloadMessages - 1
        return AIInsightStructuredRequest(
            history: Array(eligibleHistory.suffix(maximumHistoryMessages)),
            latestPrompt: preparedPrompt
        )
    }
}

enum StylistChatError: LocalizedError, Equatable {
    case missingConfiguration
    case unauthorized
    case payloadTooLarge
    case rateLimited
    case providerError
    case invalidRequest
    case network

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            return "Chat is not configured yet."
        case .unauthorized:
            return "Sign in with Apple to use the live AI Stylist."
        case .payloadTooLarge:
            return StylistChatMessageLimit.limitMessage
        case .rateLimited:
            return "You have hit the hourly limit. Try again soon."
        case .providerError:
            return "The stylist is having trouble replying right now."
        case .invalidRequest:
            return "That message could not be sent."
        case .network:
            return "Could not connect to the stylist. Check your connection and try again."
        }
    }
}

struct StylistChatDiagnosticError: LocalizedError, Equatable, CustomDebugStringConvertible {
    let category: StylistChatError
    let statusCode: Int?
    let responseBody: String?
    let requestID: String?
    let endpoint: URL
    let underlyingErrorDescription: String?

    var errorDescription: String? { category.errorDescription }

    var debugDescription: String {
        [
            "category=\(category)",
            statusCode.map { "status=\($0)" },
            responseBody.map { "body=\($0)" },
            requestID.map { "request_id=\($0)" },
            "endpoint=\(endpoint.absoluteString)",
            underlyingErrorDescription.map { "underlying=\($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: " ")
    }
}
