import Foundation
import Combine

@MainActor
final class StylistChatService: ObservableObject {
    @Published private(set) var activeConversation: ChatConversation
    @Published private(set) var conversations: [ChatConversation]
    @Published private(set) var isStreaming = false
    @Published private(set) var requiresSignIn = false
    @Published private(set) var authorizationState: StylistChatAuthorizationState
    @Published var inlineError: String?

    private let store: ChatConversationStore
    private let transport: StylistChatTransport
    private let contextProvider: () -> ChatContext
    private var streamTask: Task<Void, Never>?
    private var pendingAssistantID: UUID?
    private var sessionChangeCancellable: AnyCancellable?

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
        let initialAuthorizationState = self.transport.authorizationState
        authorizationState = initialAuthorizationState
        requiresSignIn = initialAuthorizationState != .authorized
        let sanitizedConversations = store.conversations.map(Self.removingEmptyAssistantMessages)
        conversations = sanitizedConversations
        activeConversation = sanitizedConversations.first ?? ChatConversation()
        sessionChangeCancellable = NotificationCenter.default.publisher(
            for: StyleMatchAccountSessionStore.didChangeNotification
        ).sink { [weak self] _ in
            Task { @MainActor in
                self?.refreshAuthorizationState()
            }
        }
        StyleMatchAccountSessionDiagnostics.log(stage: "chat_service_init")
    }

    func newChat() {
        stopStreaming()
        inlineError = nil
        refreshAuthorizationState()
        activeConversation = ChatConversation()
    }

    func openConversation(_ conversation: ChatConversation) {
        stopStreaming()
        inlineError = nil
        refreshAuthorizationState()
        activeConversation = Self.removingEmptyAssistantMessages(conversation)
    }

    func refreshAuthorizationState() {
        authorizationState = transport.authorizationState
        requiresSignIn = authorizationState != .authorized
        if authorizationState == .authorized,
           inlineError == StylistChatError.unauthorized.localizedDescription {
            inlineError = nil
        }
        StyleMatchAccountSessionDiagnostics.log(stage: "chat_auth_refreshed")
    }

    @discardableResult
    func send(_ text: String, forcedContext: ChatContext? = nil) -> Bool {
        let prompt = StylistChatMessageLimit.trimmedForSending(text)
        guard !prompt.isEmpty, !isStreaming else { return false }
        guard StylistChatMessageLimit.isWithinLimit(prompt) else {
            inlineError = StylistChatMessageLimit.limitMessage
            return false
        }

        guard validateAuthorization() else { return false }

        requiresSignIn = false
        inlineError = nil
        activeConversation.messages.append(ChatMessage(role: .user, content: prompt))
        let assistantID = UUID()
        pendingAssistantID = assistantID
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
                finishStreaming(error: error)
                return
            }
            finishStreaming()
        }
        return true
    }

    func sendPreseededQuestion(_ text: String, context: ChatContext) {
        guard validateAuthorization() else { return }
        newChat()
        _ = send(text, forcedContext: context)
    }

    func stopStreaming() {
        streamTask?.cancel()
        streamTask = nil
        if isStreaming {
            finishStreaming()
        }
    }

    private func finishStreaming(error: Error? = nil) {
        isStreaming = false
        streamTask = nil
        let chatError = (error as? StylistChatError)
            ?? (error as? StylistChatDiagnosticError)?.category
        let hasAssistantResponse = pendingAssistantID.flatMap { assistantID in
            activeConversation.messages.first { $0.id == assistantID }
        }.map {
            !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } ?? false

        if !hasAssistantResponse {
            activeConversation = Self.removingEmptyAssistantMessages(activeConversation)
            activeConversation.updatedAt = Date()
            store.save(activeConversation)
            inlineError = (chatError ?? StylistChatError.providerError).localizedDescription
            requiresSignIn = chatError == .unauthorized
            pendingAssistantID = nil
            conversations = store.conversations
            return
        }

        activeConversation = Self.removingEmptyAssistantMessages(activeConversation)
        activeConversation.updatedAt = Date()
        store.save(activeConversation)
        conversations = store.conversations
        pendingAssistantID = nil
    }

    private func append(_ token: String, to messageID: UUID) {
        guard let index = activeConversation.messages.firstIndex(where: { $0.id == messageID }) else {
            return
        }
        activeConversation.messages[index].content += token
        activeConversation.messages[index].timestamp = Date()
        activeConversation.updatedAt = Date()
    }

    private func validateAuthorization() -> Bool {
        refreshAuthorizationState()
        guard authorizationState == .authorized else {
            requiresSignIn = true
            inlineError = StylistChatError.unauthorized.localizedDescription
            return false
        }
        return true
    }

    private func requestMessages(from messages: [ChatMessage]) -> [ChatRequest.RequestMessage] {
        messages
            .compactMap { message -> ChatRequest.RequestMessage? in
                guard message.role == .user || message.role == .assistant else { return nil }
                let content = message.content
                guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      StylistChatMessageLimit.isWithinLimit(content) else {
                    return nil
                }
                return ChatRequest.RequestMessage(role: message.role.rawValue, content: content)
            }
            .suffix(StylistChatMessageLimit.retainedConversationMessages)
    }

    private static func removingEmptyAssistantMessages(_ conversation: ChatConversation) -> ChatConversation {
        var sanitized = conversation
        sanitized.messages.removeAll {
            $0.role == .assistant
                && $0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return sanitized
    }

    private static func defaultTransport() -> StylistChatTransport {
        guard let configuration = StylistChatConfiguration.production else {
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
