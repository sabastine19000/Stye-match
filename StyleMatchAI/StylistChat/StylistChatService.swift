import Foundation
import Combine

@MainActor
final class StylistChatService: ObservableObject {
    @Published private(set) var activeConversation: ChatConversation
    @Published private(set) var conversations: [ChatConversation]
    @Published private(set) var isStreaming = false
    @Published var inlineError: String?

    private let store: ChatConversationStore
    private let transport: StylistChatTransport
    private let contextProvider: () -> ChatContext
    private var streamTask: Task<Void, Never>?

    init(
        store: ChatConversationStore = ChatConversationStore(),
        transport: StylistChatTransport? = nil,
        contextProvider: @escaping () -> ChatContext = {
            PersonalizationContextBuilder.chatContext()
        }
    ) {
        self.store = store
        self.transport = transport ?? Self.defaultTransport()
        self.contextProvider = contextProvider
        conversations = store.conversations
        activeConversation = store.conversations.first ?? ChatConversation()
    }

    func newChat() {
        stopStreaming()
        inlineError = nil
        activeConversation = ChatConversation()
    }

    func openConversation(_ conversation: ChatConversation) {
        stopStreaming()
        inlineError = nil
        activeConversation = conversation
    }

    func send(_ text: String, forcedContext: ChatContext? = nil) {
        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isStreaming else { return }

        inlineError = nil
        activeConversation.messages.append(ChatMessage(role: .user, content: prompt))
        let assistantID = UUID()
        activeConversation.messages.append(ChatMessage(id: assistantID, role: .assistant, content: ""))
        activeConversation.updatedAt = Date()
        isStreaming = true

        let context = forcedContext ?? contextProvider()
        let request = ChatRequest(
            messages: requestMessages(from: activeConversation.messages),
            context: context,
            stream: true
        )

        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await token in transport.send(request) {
                    if Task.isCancelled { break }
                    append(token, to: assistantID)
                }
            } catch {
                inlineError = (error as? LocalizedError)?.errorDescription ?? StylistChatError.network.localizedDescription
            }
            finishStreaming()
        }
    }

    func sendPreseededQuestion(_ text: String, context: ChatContext) {
        newChat()
        send(text, forcedContext: context)
    }

    func stopStreaming() {
        streamTask?.cancel()
        streamTask = nil
        if isStreaming {
            finishStreaming()
        }
    }

    private func finishStreaming() {
        isStreaming = false
        streamTask = nil
        activeConversation.updatedAt = Date()
        store.save(activeConversation)
        conversations = store.conversations
    }

    private func append(_ token: String, to messageID: UUID) {
        guard let index = activeConversation.messages.firstIndex(where: { $0.id == messageID }) else {
            return
        }
        activeConversation.messages[index].content += token
        activeConversation.messages[index].timestamp = Date()
        activeConversation.updatedAt = Date()
    }

    private func requestMessages(from messages: [ChatMessage]) -> [ChatRequest.RequestMessage] {
        messages
            .filter { $0.role == .user || $0.role == .assistant }
            .suffix(12)
            .map { ChatRequest.RequestMessage(role: $0.role.rawValue, content: $0.content) }
    }

    private static func defaultTransport() -> StylistChatTransport {
        guard let configuration = StylistChatConfiguration.fromSecretsProvider() else {
            return FailingChatTransport(error: StylistChatError.missingConfiguration)
        }
        return LiveChatTransport(configuration: configuration)
    }
}

private struct FailingChatTransport: StylistChatTransport {
    let error: Error

    func send(_ request: ChatRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: error)
        }
    }
}
