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
            return "That message is too long. Please shorten it and try again."
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
