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
    /// Developer-facing delivery metadata. It deliberately contains no
    /// authorization material or raw conversation contents.
    @Published private(set) var lastDeliveryDiagnostic: StylistChatDeliveryDiagnostic?

    private let store: ChatConversationStore
    private let transport: StylistChatTransport
    private let contextProvider: () -> ChatContext
    private let memoryDefaults: UserDefaults
    private var streamTask: Task<Void, Never>?
    private var pendingAssistantID: UUID?
    private var pendingOutboundMessageCount: Int?
    private var retryableSend: RetryableSend?
    private var sessionChangeCancellable: AnyCancellable?

    private struct RetryableSend {
        let userMessageID: UUID
        let prompt: String
        let context: ChatContext
        let intelligenceSnapshot: StylistIntelligenceSnapshot?
    }

    init(
        store: ChatConversationStore = ChatConversationStore(),
        transport: StylistChatTransport? = nil,
        endpointFactory: StyleMatchLiveClientEndpointFactory = .current(),
        memoryDefaults: UserDefaults = .standard,
        contextProvider: @escaping () -> ChatContext = {
            PersonalizationContextBuilder.chatContext()
        }
    ) {
        self.store = store
        self.transport = transport ?? Self.defaultTransport(endpointFactory: endpointFactory)
        self.contextProvider = contextProvider
        self.memoryDefaults = memoryDefaults
        let initialAuthorizationState = self.transport.authorizationState
        authorizationState = initialAuthorizationState
        requiresSignIn = initialAuthorizationState != .authorized
        let sanitizedConversations = store.conversations.map(Self.removingEmptyAssistantMessages)
        conversations = sanitizedConversations
        activeConversation = sanitizedConversations.first(where: \.isEligibleForAutomaticResume) ?? ChatConversation()
        sessionChangeCancellable = NotificationCenter.default.publisher(
            for: StyleMatchAccountSessionStore.didChangeNotification
        ).sink { [weak self] _ in
            Task { @MainActor in
                self?.refreshAuthorizationState()
            }
        }
        StyleMatchAccountSessionDiagnostics.log(stage: "chat_service_init")
    }

    var resolvedTransportBaseURL: URL? {
        (transport as? LiveChatTransport)?.resolvedBaseURL
    }

    var activeScanConversationContext: StylistConversationScanContext? {
        activeConversation.scanContext
    }

    var canRetryLastFailedSend: Bool {
        retryableSend != nil && !isStreaming
    }

    /// Retries only the most recent failed user turn. The stored turn is
    /// removed before `send` re-adds it, preventing duplicate history or a
    /// second provider request from one explicit Retry action.
    @discardableResult
    func retryLastFailedSend() -> Bool {
        guard !isStreaming,
              let retry = retryableSend,
              activeConversation.messages.last?.id == retry.userMessageID,
              activeConversation.messages.last?.role == .user else {
            return false
        }
        activeConversation.messages.removeLast()
        activeConversation.updatedAt = Date()
        store.save(activeConversation)
        conversations = store.conversations
        retryableSend = nil
        return send(
            retry.prompt,
            forcedContext: retry.context,
            intelligenceSnapshot: retry.intelligenceSnapshot
        )
    }

    func newChat() {
        stopStreaming()
        inlineError = nil
        refreshAuthorizationState()
        activeConversation = ChatConversation()
    }

    func beginContextualConversation() {
        stopStreaming()
        inlineError = nil
        refreshAuthorizationState()
        activeConversation = ChatConversation(scope: .contextualStylist)
    }

    func ensureVerifiedGeneralConversation() {
        guard !activeConversation.isVerifiedGeneral else { return }
        newChat()
    }

    /// Opens only a conversation bound to this exact scan, or creates one. It
    /// intentionally never falls back to an unrelated general conversation.
    @discardableResult
    func openOrCreateScanConversation(context: ChatContext) -> UUID? {
        stopStreaming()
        inlineError = nil
        refreshAuthorizationState()
        guard let authoritative = context.authoritativeScan, authoritative.isComplete else {
            newChat()
            return nil
        }
        let compact = StylistConversationScanContext(authoritativeScan: authoritative)
        let scope: StylistConversationScope = authoritative.source == .savedSelection
            ? .savedScan(scanID: compact.scanID)
            : .activeScan(scanID: compact.scanID)
        if let existing = conversations.first(where: { conversation in
            conversation.scope.scanID == compact.scanID && conversation.scanContext?.scanID == compact.scanID
        }) {
            activeConversation = Self.removingEmptyAssistantMessages(existing)
            return activeConversation.id
        }
        activeConversation = ChatConversation(scope: scope, scanContext: compact)
        return activeConversation.id
    }

    func openConversation(_ conversation: ChatConversation) {
        guard conversation.isSelectableFromHistory else {
            inlineError = "This earlier chat cannot be continued as General Stylist context. Start a new General chat instead."
            return
        }
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
    func send(
        _ text: String,
        forcedContext: ChatContext? = nil,
        intelligenceSnapshot: StylistIntelligenceSnapshot? = nil
    ) -> Bool {
        let prompt = StylistChatMessageLimit.trimmedForSending(text)
        guard !prompt.isEmpty, !isStreaming else { return false }
        retryableSend = nil
        guard StylistChatMessageLimit.isWithinLimit(prompt) else {
            inlineError = StylistChatMessageLimit.limitMessage
            return false
        }

        if case let .savedScan(scanID) = activeConversation.scope,
           !StylistSavedScanAvailability.savedScanIDs(defaults: memoryDefaults).contains(scanID) {
            inlineError = "That saved scan is no longer available. Reopen it from Scan History before asking the Stylist."
            lastDeliveryDiagnostic = StylistChatDeliveryDiagnostic.localValidation(
                scope: activeConversation.scope,
                outboundMessageCount: 0,
                detail: "Saved scan authority was unavailable before the request was assembled."
            )
            return false
        }

        guard validateAuthorization() else { return false }

        let proposedContext = forcedContext ?? contextProvider()
        let scopedContext = StylistRouteContextPipeline.resolving(
            applyingConversationScope(to: proposedContext)
        )
        var context = StyleMemoryContextBuilder.applying(
            to: scopedContext,
            conversationScope: activeConversation.scope,
            defaults: memoryDefaults
        )
        let conversationState = StylistConversationState.reconstructing(
            messages: activeConversation.messages,
            including: prompt
        )
        // Exact active and saved Scan conversations retain their established
        // server-facing authority. The local workplace clarification belongs
        // only to the non-scan global Stylist path.
        let preflight = activeConversation.scope.isScanBound
            ? nil
            : StylistConversationRouter.preflight(
                message: prompt,
                snapshot: StylistConversationSnapshot.from(context.authoritativeScan),
                state: conversationState
            )
        context.aiMemoryResolution = resolvedAIMemory(for: prompt, context: context)
        let orchestration = intelligenceSnapshot.map {
            StylistAIOrchestrator.decide(
                StylistAIOrchestrationInput(
                    snapshot: $0,
                    conversationScope: activeConversation.scope,
                    intent: StylistConversationRouter.classify(prompt),
                    preflight: preflight ?? StylistConversationPreflight(
                        intent: StylistConversationRouter.classify(prompt),
                        localReply: nil,
                        semanticResponseID: nil
                    ),
                    networkContext: context
                )
            )
        }
        let scanContextID = scanContextID(for: context)
        let weatherAttribution = !context.hasExplicitWeatherStylingContext
            ? nil
            : WeatherKitAuthority.loadSnapshot(defaults: .standard)?.attribution
        let userMessage = ChatMessage(role: .user, content: prompt, scanContextID: scanContextID)

        let localPreflightResponse: (reply: String, semanticResponseID: StylistSemanticResponseID)?
        if case let .requiresClarification(_, localReply, semanticResponseID)? = orchestration {
            localPreflightResponse = (localReply, semanticResponseID)
        } else if case let .localResponse(_, localReply, semanticResponseID)? = orchestration {
            localPreflightResponse = (localReply, semanticResponseID)
        } else if intelligenceSnapshot == nil,
                  preflight?.semanticResponseID == .workplaceSafetyClarification,
                  let localReply = preflight?.localReply,
                  let semanticResponseID = preflight?.semanticResponseID {
            // Existing callers without a caller-owned canonical snapshot retain
            // the established local workplace clarification. This reuses the
            // already-calculated preflight rather than constructing authority
            // or duplicating the clarification classification here.
            localPreflightResponse = (localReply, semanticResponseID)
        } else {
            localPreflightResponse = nil
        }

        if let localPreflightResponse {
            activeConversation.messages.append(userMessage)
            activeConversation.messages.append(
                ChatMessage(
                    role: .assistant,
                    content: localPreflightResponse.reply,
                    scanContextID: scanContextID,
                    weatherAttribution: weatherAttribution,
                    localSemanticResponseID: localPreflightResponse.semanticResponseID
                )
            )
            activeConversation.updatedAt = Date()
            store.save(activeConversation)
            conversations = store.conversations
            requiresSignIn = false
            inlineError = nil
            lastDeliveryDiagnostic = nil
            return true
        }

        if case let .unavailable(reason)? = orchestration {
            lastDeliveryDiagnostic = StylistChatDeliveryDiagnostic.localValidation(
                scope: activeConversation.scope,
                outboundMessageCount: 0,
                detail: "Canonical intelligence admission was unavailable: \(reason.rawValue)."
            )
            inlineError = "That context is no longer available. Choose it again from Home, Closet, or Shop."
            return false
        }

        let outboundMessages = requestMessages(
            from: activeConversation.messages + [userMessage],
            authoritativeScan: context.authoritativeScan,
            scope: activeConversation.scope
        )

        requiresSignIn = false
        inlineError = nil
        lastDeliveryDiagnostic = nil

        guard !outboundMessages.isEmpty else {
            lastDeliveryDiagnostic = StylistChatDeliveryDiagnostic.localValidation(
                scope: activeConversation.scope,
                outboundMessageCount: 0,
                detail: "Filtered outbound message array was empty."
            )
            inlineError = StylistChatError.invalidRequest.localizedDescription
            return false
        }

        activeConversation.messages.append(userMessage)

        if let localReply = scanBoundScoreReply(for: prompt, context: context) {
            activeConversation.messages.append(
                ChatMessage(role: .assistant, content: localReply, scanContextID: scanContextID, weatherAttribution: weatherAttribution)
            )
            activeConversation.updatedAt = Date()
            store.save(activeConversation)
            conversations = store.conversations
            return true
        }

        let assistantID = UUID()
        pendingAssistantID = assistantID
        pendingOutboundMessageCount = outboundMessages.count
        retryableSend = RetryableSend(
            userMessageID: userMessage.id,
            prompt: prompt,
            context: context,
            intelligenceSnapshot: intelligenceSnapshot
        )
        activeConversation.messages.append(
            ChatMessage(
                id: assistantID,
                role: .assistant,
                content: "",
                scanContextID: scanContextID,
                weatherAttribution: weatherAttribution
            )
        )
        activeConversation.updatedAt = Date()
        isStreaming = true

        let request = ChatRequest(
            messages: outboundMessages,
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
        if context.authoritativeScan?.isComplete == true {
            openOrCreateScanConversation(context: context)
        } else {
            newChat()
        }
        _ = send(text, forcedContext: context)
    }

    /// Vision requests retain only the customer prompt and sanitized advice in
    /// chat history. The normalized image and selected attachment bytes remain
    /// request-local to the caller and are never stored by this service.
    @discardableResult
    func sendVision(_ request: VisionChatRequestV1, completion: @escaping @MainActor (Bool) -> Void) -> Bool {
        let prompt = StylistChatMessageLimit.trimmedForSending(request.prompt)
        guard prompt == request.prompt,
              !request.attachments.isEmpty,
              !isStreaming,
              validateAuthorization() else { return false }
        let userMessage = ChatMessage(role: .user, content: prompt, scanContextID: activeConversation.scope.scanID)
        let assistantID = UUID()
        activeConversation.messages.append(userMessage)
        activeConversation.messages.append(ChatMessage(id: assistantID, role: .assistant, content: "", scanContextID: activeConversation.scope.scanID))
        activeConversation.updatedAt = Date()
        pendingAssistantID = assistantID
        pendingOutboundMessageCount = 1
        retryableSend = nil
        isStreaming = true
        inlineError = nil
        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await response in transport.sendVision(request) {
                    if Task.isCancelled { break }
                    append(response.advice, to: assistantID)
                }
                finishStreaming()
                completion(true)
            } catch {
                finishStreaming(error: error)
                completion(false)
            }
        }
        return true
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
            lastDeliveryDiagnostic = StylistChatDeliveryDiagnostic(
                error: error,
                scope: activeConversation.scope,
                outboundMessageCount: pendingOutboundMessageCount ?? 0
            )
            activeConversation = Self.removingEmptyAssistantMessages(activeConversation)
            activeConversation.updatedAt = Date()
            store.save(activeConversation)
            inlineError = (chatError ?? StylistChatError.providerError).localizedDescription
            requiresSignIn = chatError == .unauthorized
            pendingAssistantID = nil
            pendingOutboundMessageCount = nil
            if !Self.isRetryableDeliveryFailure(error) {
                retryableSend = nil
            }
            conversations = store.conversations
            return
        }

        activeConversation = Self.removingEmptyAssistantMessages(activeConversation)
        activeConversation.updatedAt = Date()
        store.save(activeConversation)
        conversations = store.conversations
        pendingAssistantID = nil
        pendingOutboundMessageCount = nil
        retryableSend = nil
    }

    private static func isRetryableDeliveryFailure(_ error: Error?) -> Bool {
        let category = (error as? StylistChatError)
            ?? (error as? StylistChatDiagnosticError)?.category
        return category == .network || category == .providerError || category == .rateLimited
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

    private func requestMessages(
        from messages: [ChatMessage],
        authoritativeScan: StylistAuthoritativeScanContext?,
        scope: StylistConversationScope
    ) -> [ChatRequest.RequestMessage] {
        var filtered: [ChatRequest.RequestMessage] = []
        var skipLegacyUserTurn = false

        for message in messages.reversed() {
            guard message.role == .user || message.role == .assistant else { continue }
            let content = message.content
            guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  StylistChatMessageLimit.isWithinLimit(content) else {
                continue
            }

            if let scanID = scope.scanID {
                // Scope, not prompt wording, enforces that legacy/unscoped and
                // other-scan turns cannot leave this device.
                guard message.scanContextID == scanID else { continue }
            } else {
                // General chat cannot inherit a Scan-specific turn either.
                guard message.scanContextID == nil else { continue }
            }
            if let authoritativeScan,
               message.role == .assistant,
               message.scanContextID == nil,
               Self.containsConflictingScore(content, authoritativeScore: authoritativeScan.overallScore) {
                skipLegacyUserTurn = true
                continue
            }
            if message.role == .user, skipLegacyUserTurn {
                skipLegacyUserTurn = false
                continue
            }

            filtered.append(
                ChatRequest.RequestMessage(role: message.role.rawValue, content: content)
            )
        }

        return Array(
            filtered
                .reversed()
                .suffix(StylistChatMessageLimit.retainedConversationMessages)
        )
    }

    private func applyingConversationScope(to proposedContext: ChatContext) -> ChatContext {
        guard activeConversation.scope.isScanBound,
              let scanContext = activeConversation.scanContext,
              scanContext.scanID == activeConversation.scope.scanID else {
            // General Stylist has no scan authority. A current Scan screen can
            // remain visible behind the AI tab, but it must not tag a general
            // turn or leak into the outbound request.
            var general = proposedContext
            let retainsExplicitWeatherContext = general.hasExplicitWeatherStylingContext
            general.activeScan = ""
            general.scoreBreakdown = nil
            general.authoritativeScan = nil
            general.stylistContextSnapshot = .unavailable
            if !retainsExplicitWeatherContext {
                general.weatherConstraint = ""
            }
            // General Stylist clears all inherited screen authority, including
            // any prior explicit Home or Closet route.
            if var screenContext = general.screenContext {
                screenContext.activeScanState = .none
                screenContext.activeScanID = nil
                screenContext.selectedOccasion = nil
                screenContext.visibleOverallScore = nil
                screenContext.surface = nil
                general.screenContext = screenContext
            }
            return general
        }

        // The persisted compact context owns scan identity and score. When the
        // current send carries richer facts for that exact same scan, retain
        // them without allowing a different or stale scan to replace it.
        let authoritative: StylistAuthoritativeScanContext
        if let proposedScan = proposedContext.authoritativeScan,
           proposedScan.isComplete,
           proposedScan.scanID == scanContext.scanID {
            authoritative = proposedScan
        } else {
            authoritative = scanContext.authoritativeScan
        }
        var scoped = proposedContext.applyingAuthoritativeScan(authoritative)
        scoped.screenContext = StylistScreenContext(
            currentTab: .ai,
            activeScanState: activeConversation.scope == .savedScan(scanID: scanContext.scanID) ? .saved : .live,
            activeScanID: scanContext.scanID,
            selectedOccasion: scanContext.selectedOccasion,
            visibleOverallScore: scanContext.score,
            entryPoint: .scanResult,
            closetState: proposedContext.screenContext?.closetState ?? .unavailable
        )
        return scoped.applyingAuthoritativeScan(authoritative)
    }

    /// Only an already explicit, scan-bound handoff receives this bounded
    /// projection. Normal AI-tab entry remains General Stylist and therefore
    /// context-free.
    private func resolvedAIMemory(for prompt: String, context: ChatContext) -> AIMemoryResolution? {
        let persistentStore = AIPersistentMemoryStore(defaults: memoryDefaults)
        let manager = AIMemoryManager()
        guard activeConversation.scope.isScanBound,
              let screen = context.screenContext,
              screen.surface != nil,
              let scan = context.authoritativeScan,
              scan.isComplete else {
            // General Stylist remains isolated from screen and scan authority,
            // but may receive a small set of relevant, confirmed preferences.
            let facts = persistentStore.activeMemories(relevantTo: prompt)
            guard !facts.isEmpty else { return nil }
            return manager.mergingPersistentMemories(
                AIMemoryResolution(
                    facts: [], omittedCategories: [], authoritativeReference: nil,
                    contextGeneration: nil, rejectedStaleContext: false,
                    unavailableReference: false, serializedCharacterCount: 0
                ),
                memories: facts
            )
        }
        let scope: StyleMemoryScope = activeConversation.scope == .savedScan(scanID: scan.scanID)
            ? .init(kind: .savedScan, stableID: scan.scanID)
            : .init(kind: .activeScan, stableID: scan.scanID)
        let domain: StyleMemoryReferenceDomain = scope.kind == .savedScan ? .savedScan : .activeScan
        guard let reference = StyleMemoryReference(domain: domain, stableID: scan.scanID) else { return nil }
        let input = StyleMemoryContextInput(
            identityScope: StyleMemoryIdentityScope.resolve(defaults: memoryDefaults),
            scope: scope,
            explicitSelection: StyleMemoryFact(value: reference, provenance: .explicitSelection, confidence: .confirmed),
            selectedScanSummary: StyleMemoryFact(
                value: StyleMemoryScanSummary(reference: reference, summary: scan.activeScanPrompt),
                provenance: .explicitSelection,
                confidence: .confirmed
            )
        )
        let resolved = manager.resolve(
            AIMemoryResolutionInput(
                userMessage: prompt,
                screenContext: screen,
                expectedContextGeneration: screen.surface?.contextGeneration,
                conversationScope: scope,
                styleMemoryInput: input,
                availableReferences: [reference]
            )
        )
        return manager.mergingPersistentMemories(resolved, memories: persistentStore.activeMemories(relevantTo: prompt))
    }

    private func scanContextID(for context: ChatContext) -> String? {
        guard let expectedScanID = activeConversation.scope.scanID,
              context.authoritativeScan?.scanID == expectedScanID else {
            return nil
        }
        return expectedScanID
    }

    private func scanBoundScoreReply(for prompt: String, context: ChatContext) -> String? {
        guard activeConversation.scope.isScanBound,
              let activeScan = activeConversation.scanContext,
              context.authoritativeScan?.scanID == activeScan.scanID,
              StylistConversationRouter.classify(prompt) == .latestScore else {
            return nil
        }
        return StylistConversationRouter.latestScoreReply(for: activeScan.score)
    }

    private static func containsConflictingScore(_ content: String, authoritativeScore: Int) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: #"\b(\d{1,3})\s*/\s*100\b"#) else {
            return false
        }
        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        return regex.matches(in: content, range: range).contains { match in
            guard let scoreRange = Range(match.range(at: 1), in: content),
                  let score = Int(content[scoreRange]) else {
                return false
            }
            return score != authoritativeScore
        }
    }

    private static func removingEmptyAssistantMessages(_ conversation: ChatConversation) -> ChatConversation {
        var sanitized = conversation
        sanitized.messages.removeAll {
            $0.role == .assistant
                && $0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return sanitized
    }

    private static func defaultTransport(
        endpointFactory: StyleMatchLiveClientEndpointFactory
    ) -> StylistChatTransport {
        guard let configuration = endpointFactory.chatConfiguration else {
            return FailingChatTransport(error: StylistChatError.missingConfiguration)
        }
        return LiveChatTransport(configuration: configuration)
    }
}

/// Consumes an explicit Scan route exactly once for a mounted chat surface.
/// The service remains the single authority for durable conversation lookup.
@MainActor
final class StylistScanConversationHandoffController {
    private(set) var consumedRouteToken: UUID?
    private(set) var selectedConversationID: UUID?

    @discardableResult
    func consume(_ handoff: StylistScanHandoff, using service: StylistChatService) -> UUID? {
        guard let token = handoff.routeToken else { return nil }
        if token == consumedRouteToken {
            return selectedConversationID
        }
        consumedRouteToken = token
        let selectedID = service.openOrCreateScanConversation(context: handoff.aiChatContext)
        selectedConversationID = selectedID
        return selectedID
    }

    /// Opens only the scan that is currently carried by an AI entry from Scan.
    /// A direct AI-tab entry and an explicit General Stylist selection are both
    /// fail-closed so they cannot inherit scan authority.
    @discardableResult
    func openCurrentScanConversation(
        context: ChatContext?,
        screenContext: StylistScreenContext,
        generalStylistSelected: Bool,
        using service: StylistChatService
    ) -> UUID? {
        guard !generalStylistSelected,
              let context,
              let scan = context.authoritativeScan,
              scan.isComplete,
              scan.matches(screenContext) else {
            return nil
        }
        return service.openOrCreateScanConversation(context: context)
    }

    func clearSelection() {
        consumedRouteToken = nil
        selectedConversationID = nil
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
