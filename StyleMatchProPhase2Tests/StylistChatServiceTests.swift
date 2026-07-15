import XCTest
@testable import StyleMatchPro

final class StylistChatServiceTests: XCTestCase {
    func testChatContextClampsOversizedFields() {
        let context = ChatContext(
            profileSummary: String(repeating: "p", count: 700),
            recentOutfits: String(repeating: "o", count: 900),
            scoreBreakdown: String(repeating: "s", count: 600)
        )

        XCTAssertEqual(context.profileSummary.count, 600)
        XCTAssertEqual(context.recentOutfits.count, 800)
        XCTAssertEqual(context.scoreBreakdown?.count, 500)
    }

    @MainActor
    func testHistoryTrimmingSendsMostRecentTwelveTurns() async throws {
        let store = ChatConversationStore(fileURL: temporaryStoreURL())
        var conversation = ChatConversation()
        for index in 0..<20 {
            conversation.messages.append(
                ChatMessage(
                    role: index.isMultiple(of: 2) ? .user : .assistant,
                    content: "message-\(index)"
                )
            )
        }
        store.save(conversation)

        let transport = MockChatTransport(chunks: ["done"])
        let service = StylistChatService(
            store: store,
            transport: transport,
            contextProvider: { ChatContext() }
        )

        service.send("new question")
        try await waitUntil { !service.isStreaming }

        XCTAssertEqual(transport.requests.last?.messages.count, 12)
        XCTAssertEqual(transport.requests.last?.messages.last?.content, "")
    }

    @MainActor
    func testStreamingAssemblyPersistsAssistantMessage() async throws {
        let store = ChatConversationStore(fileURL: temporaryStoreURL())
        let transport = MockChatTransport(chunks: ["A crisp ", "white shirt works."])
        let service = StylistChatService(
            store: store,
            transport: transport,
            contextProvider: { ChatContext(profileSummary: "likes neutrals") }
        )

        service.send("What matches black pants?")
        try await waitUntil { !service.isStreaming }

        let assistant = service.activeConversation.messages.last
        XCTAssertEqual(assistant?.role, .assistant)
        XCTAssertEqual(assistant?.content, "A crisp white shirt works.")
        XCTAssertEqual(ChatConversationStore(fileURL: storeURL(from: store)).conversations.first?.messages.last?.content, "A crisp white shirt works.")
    }

    @MainActor
    func testCancellationKeepsPartialAssistantContent() async throws {
        let store = ChatConversationStore(fileURL: temporaryStoreURL())
        let transport = MockChatTransport(chunks: ["Partial"], delayNanoseconds: 200_000_000)
        let service = StylistChatService(
            store: store,
            transport: transport,
            contextProvider: { ChatContext() }
        )

        service.send("Start")
        try await waitUntil {
            service.activeConversation.messages.last?.content == "Partial"
        }
        service.stopStreaming()
        try await waitUntil { !service.isStreaming }

        XCTAssertEqual(service.activeConversation.messages.last?.content, "Partial")
    }

    func testDeviceIdentifierHashIsStableAndDoesNotExposeInput() {
        let digest = StylistChatAuthHeaders.sha256Hex("stylematch-device")

        XCTAssertEqual(digest.count, 64)
        XCTAssertEqual(digest, StylistChatAuthHeaders.sha256Hex("stylematch-device"))
        XCTAssertFalse(digest.contains("stylematch-device"))
    }

    func testConversationalStylistDefaultContextExcludesAppearanceAndProfileFields() {
        let context = PersonalizationContextBuilder.conversationalStylistContext()
        let payload = [context.profileSummary, context.recentOutfits, context.scoreBreakdown ?? ""].joined(separator: "\n")

        XCTAssertTrue(payload.contains("Conversational Personal Stylist Phase 3C"))
        XCTAssertFalse(payload.contains("declaredUndertone"))
        XCTAssertFalse(payload.contains("skinToneStyleNote"))
        XCTAssertFalse(payload.contains("BodyProportions"))
        XCTAssertFalse(payload.localizedCaseInsensitiveContains("favorite brands"))
        XCTAssertFalse(payload.localizedCaseInsensitiveContains("favorite colors"))
        XCTAssertFalse(payload.localizedCaseInsensitiveContains("budget"))
    }

    func testOutfitCombinationContextSupportsRequestedModesAndColorPairingWithoutProfileLeakage() {
        let context = PersonalizationContextBuilder.conversationalStylistContext()
        let payload = [context.profileSummary, context.recentOutfits, context.scoreBreakdown ?? ""].joined(separator: "\n")

        XCTAssertTrue(payload.contains("top, bottom, shoes"))
        XCTAssertTrue(payload.contains("Keep any user-provided anchor item fixed"))
        XCTAssertTrue(payload.contains("casual/smart/business/elevated/minimal/bold/warm/cool/day/evening"))
        XCTAssertTrue(payload.contains("neutral"))
        XCTAssertTrue(payload.contains("contrast"))
        XCTAssertTrue(payload.contains("pattern scale"))
        XCTAssertTrue(payload.contains("olive"))
        XCTAssertTrue(payload.contains("burgundy"))
        XCTAssertTrue(payload.contains("denim washes"))
        XCTAssertTrue(payload.contains("Suggested addition"))
        XCTAssertFalse(payload.contains("skinToneStyleNote"))
        XCTAssertFalse(payload.contains("declaredUndertone"))
        XCTAssertFalse(payload.contains("BodyProportions"))
        XCTAssertFalse(payload.localizedCaseInsensitiveContains("saved budget"))
        XCTAssertFalse(payload.localizedCaseInsensitiveContains("favorite brands"))
    }

    func testScanStylistContextUsesSelectedScanFactsOnly() {
        let analysis = OutfitAnalysisResult(
            score: 84,
            scoreBreakdown: OutfitScoreBreakdown(
                colorHarmony: 22,
                patternBalance: 17,
                fitQuality: 21,
                occasionMatch: 16,
                accessoryUse: 8
            ),
            colorMatch: "Strong",
            occasionFit: "Smart Casual",
            styleBalance: "Balanced",
            colorHarmony: "Navy and olive work well.",
            styleCoordination: "Coordinated",
            formality: "Polished",
            seasonalMatch: "Flexible",
            summary: "A balanced outfit.",
            outfitDescription: "Navy shirt with olive chinos",
            detectedClothingItems: ["shirt", "chinos"],
            colorPalette: ["navy", "olive"],
            environment: "Indoor",
            imageQuality: "Clear",
            skinToneStyleNote: "Legacy value must not travel",
            suggestions: ["Add brown loafers."],
            recommendations: []
        )

        let context = PersonalizationContextBuilder.scanStylistContext(for: analysis)
        let payload = [context.profileSummary, context.recentOutfits, context.scoreBreakdown ?? ""].joined(separator: "\n")

        XCTAssertTrue(payload.contains("score 84/100"))
        XCTAssertTrue(payload.contains("shirt"))
        XCTAssertTrue(payload.contains("navy"))
        XCTAssertTrue(payload.contains("olive"))
        XCTAssertTrue(payload.contains("From this scan"))
        XCTAssertTrue(payload.contains("If color or garment detection seems uncertain"))
        XCTAssertTrue(payload.contains("top, bottom, shoes"))
        XCTAssertFalse(payload.contains("Legacy value must not travel"))
        XCTAssertFalse(payload.contains("declaredUndertone"))
        XCTAssertFalse(payload.contains("BodyProportions"))
        XCTAssertFalse(payload.localizedCaseInsensitiveContains("heightInches"))
        XCTAssertFalse(payload.localizedCaseInsensitiveContains("warm undertone"))
    }

    @MainActor
    func testForcedContextPreventsDefaultBroadContextForTypedStylist() async throws {
        let store = ChatConversationStore(fileURL: temporaryStoreURL())
        let transport = MockChatTransport(chunks: ["Try a cream shirt."])
        let broadContext = ChatContext(profileSummary: "Favorite colors: secret profile value")
        let minimizedContext = PersonalizationContextBuilder.conversationalStylistContext()
        let service = StylistChatService(
            store: store,
            transport: transport,
            contextProvider: { broadContext }
        )

        service.send("What goes with olive pants?", forcedContext: minimizedContext)
        try await waitUntil { !service.isStreaming }

        XCTAssertEqual(transport.requests.last?.context, minimizedContext)
        XCTAssertFalse(transport.requests.last?.context.profileSummary.contains("secret profile value") ?? true)
    }

    @MainActor
    func testOutfitCombinationRequestsUseExistingChatMessagePath() async throws {
        let store = ChatConversationStore(fileURL: temporaryStoreURL())
        let transport = MockChatTransport(chunks: ["Option 1 — Clean casual"])
        let context = PersonalizationContextBuilder.conversationalStylistContext()
        let service = StylistChatService(
            store: store,
            transport: transport,
            contextProvider: { ChatContext(profileSummary: "Should not be used") }
        )

        service.send("Give me three outfits with olive pants.", forcedContext: context)
        try await waitUntil { !service.isStreaming }

        XCTAssertEqual(transport.requests.last?.messages.last?.content, "")
        XCTAssertEqual(transport.requests.last?.messages.dropLast().last?.content, "Give me three outfits with olive pants.")
        XCTAssertEqual(transport.requests.last?.context, context)
        XCTAssertTrue(service.activeConversation.messages.contains { $0.role == .assistant && $0.content.contains("Option 1") })
    }

    @MainActor
    func testReplacementAndFollowUpRequestsStayInConversationHistory() async throws {
        let store = ChatConversationStore(fileURL: temporaryStoreURL())
        let transport = MockChatTransport(chunks: ["Done"])
        let service = StylistChatService(
            store: store,
            transport: transport,
            contextProvider: { PersonalizationContextBuilder.conversationalStylistContext() }
        )

        service.send("What other pants work with this burgundy shirt?")
        try await waitUntil { !service.isStreaming }
        service.send("Make option two more casual.")
        try await waitUntil { !service.isStreaming }

        let contents = transport.requests.last?.messages.map(\.content) ?? []
        XCTAssertTrue(contents.contains("What other pants work with this burgundy shirt?"))
        XCTAssertTrue(contents.contains("Make option two more casual."))
        XCTAssertEqual(transport.requests.last?.context, PersonalizationContextBuilder.conversationalStylistContext())
    }

    @MainActor
    func testVoiceTranscriptConvergesOnTypedOutfitCombinationSendPath() async throws {
        let speechController = MockSpeechRecognitionController()
        let speechInput = StylistSpeechInputService(controller: speechController)
        await speechInput.startListening(existingText: "")
        speechController.emitPartial("Build a dinner outfit with white sneakers")
        speechInput.stopListening()

        let store = ChatConversationStore(fileURL: temporaryStoreURL())
        let transport = MockChatTransport(chunks: ["A dinner option"])
        let context = PersonalizationContextBuilder.conversationalStylistContext()
        let chatService = StylistChatService(
            store: store,
            transport: transport,
            contextProvider: { context }
        )

        chatService.send(speechInput.transcript, forcedContext: context)
        try await waitUntil { !chatService.isStreaming }

        XCTAssertEqual(transport.requests.last?.messages.dropLast().last?.content, "Build a dinner outfit with white sneakers")
        XCTAssertEqual(transport.requests.last?.context, context)
    }

    @MainActor
    func testScanCombinationRequestUsesScanFactsOnlyAndNoOwnershipClaim() async throws {
        let analysis = OutfitAnalysisResult(
            score: 78,
            colorMatch: "Good",
            occasionFit: "Business Casual",
            styleBalance: "Balanced",
            colorHarmony: "Light blue and tan are soft neutrals.",
            styleCoordination: "Coordinated",
            formality: "Smart Casual",
            seasonalMatch: "Warm Weather",
            summary: "A slightly blurry scan.",
            outfitDescription: "Light blue striped shirt with tan chinos",
            detectedClothingItems: ["striped shirt", "chinos"],
            colorPalette: ["light blue", "tan"],
            environment: "Indoor",
            imageQuality: "Slightly blurry",
            skinToneStyleNote: "Do not send",
            suggestions: [],
            recommendations: []
        )
        let scanContext = PersonalizationContextBuilder.scanStylistContext(for: analysis)
        let store = ChatConversationStore(fileURL: temporaryStoreURL())
        let transport = MockChatTransport(chunks: ["From this scan: keep the shirt."])
        let service = StylistChatService(store: store, transport: transport)

        service.send("Build a business-casual outfit around this shirt.", forcedContext: scanContext)
        try await waitUntil { !service.isStreaming }

        let payload = [transport.requests.last?.context.profileSummary, transport.requests.last?.context.recentOutfits].compactMap { $0 }.joined(separator: "\n")
        XCTAssertTrue(payload.contains("striped shirt"))
        XCTAssertTrue(payload.contains("light blue"))
        XCTAssertTrue(payload.contains("Slightly blurry"))
        XCTAssertTrue(payload.contains("From this scan"))
        XCTAssertFalse(payload.contains("Do not send"))
        XCTAssertFalse(payload.localizedCaseInsensitiveContains("from your wardrobe"))
    }

    @MainActor
    func testNewConversationResetsScanContextForUnrelatedOutfitCombination() async throws {
        let analysis = OutfitAnalysisResult(
            score: 81,
            colorMatch: "Good",
            occasionFit: "Casual",
            styleBalance: "Balanced",
            colorHarmony: "Olive works as an earth neutral.",
            styleCoordination: "Coordinated",
            formality: "Casual",
            seasonalMatch: "Flexible",
            summary: "Olive pants scan.",
            outfitDescription: "Olive pants",
            detectedClothingItems: ["pants"],
            colorPalette: ["olive"],
            environment: "Indoor",
            imageQuality: "Clear",
            suggestions: [],
            recommendations: []
        )
        let scanContext = PersonalizationContextBuilder.scanStylistContext(for: analysis)
        let defaultContext = PersonalizationContextBuilder.conversationalStylistContext()
        let store = ChatConversationStore(fileURL: temporaryStoreURL())
        let transport = MockChatTransport(chunks: ["OK"])
        let service = StylistChatService(
            store: store,
            transport: transport,
            contextProvider: { defaultContext }
        )

        service.sendPreseededQuestion("What shoes complete this outfit?", context: scanContext)
        try await waitUntil { !service.isStreaming }
        service.newChat()
        service.send("Give me a warm-weather option.")
        try await waitUntil { !service.isStreaming }

        XCTAssertEqual(transport.requests.last?.context, defaultContext)
        XCTAssertFalse(transport.requests.last?.context.recentOutfits.contains("Selected scan") ?? true)
    }

    @MainActor
    func testFailedOutfitCombinationPreservesUserMessageWithoutDuplicateRetryMessage() async throws {
        let store = ChatConversationStore(fileURL: temporaryStoreURL())
        let transport = ThrowingChatTransport(error: StylistChatError.network)
        let service = StylistChatService(
            store: store,
            transport: transport,
            contextProvider: { PersonalizationContextBuilder.conversationalStylistContext() }
        )

        service.send("Build three outfits around olive pants.")
        try await waitUntil { !service.isStreaming }

        let userMessages = service.activeConversation.messages.filter { $0.role == .user }
        XCTAssertEqual(userMessages.map(\.content), ["Build three outfits around olive pants."])
        XCTAssertEqual(service.activeConversation.messages.filter { $0.role == .assistant }.count, 1)
        XCTAssertEqual(service.inlineError, StylistChatError.network.localizedDescription)
    }

    @MainActor
    func testVoiceInputRequestsPermissionOnlyAfterUserStartsListening() async {
        let controller = MockSpeechRecognitionController()
        let service = StylistSpeechInputService(controller: controller)

        XCTAssertEqual(controller.microphoneRequestCount, 0)
        XCTAssertEqual(controller.speechRequestCount, 0)

        await service.startListening(existingText: "")

        XCTAssertEqual(controller.microphoneRequestCount, 1)
        XCTAssertEqual(controller.speechRequestCount, 1)
        XCTAssertEqual(service.state, .listening)
        XCTAssertEqual(controller.startCount, 1)
    }

    @MainActor
    func testVoiceInputHandlesMicrophoneAndSpeechDeniedSeparately() async {
        let microphoneDenied = MockSpeechRecognitionController()
        microphoneDenied.microphoneRequestResult = .denied
        let microphoneService = StylistSpeechInputService(controller: microphoneDenied)

        await microphoneService.startListening(existingText: "")

        XCTAssertEqual(microphoneService.state, .microphoneDenied)
        XCTAssertEqual(microphoneDenied.startCount, 0)

        let speechDenied = MockSpeechRecognitionController()
        speechDenied.speechRequestResult = .denied
        let speechService = StylistSpeechInputService(controller: speechDenied)

        await speechService.startListening(existingText: "")

        XCTAssertEqual(speechService.state, .speechDenied)
        XCTAssertEqual(speechDenied.startCount, 0)
    }

    @MainActor
    func testVoiceInputTranscriptCanBeEditedBeforeTypedSendPath() async throws {
        let controller = MockSpeechRecognitionController()
        let service = StylistSpeechInputService(controller: controller)

        await service.startListening(existingText: "Please")
        controller.emitPartial("match olive pants")

        XCTAssertEqual(service.transcript, "Please match olive pants")
        service.stopListening()
        XCTAssertEqual(service.state, .idle)
    }

    @MainActor
    func testVoiceInputCancelRestoresOriginalDraftAndDoesNotSendEmptyMessage() async {
        let controller = MockSpeechRecognitionController()
        let service = StylistSpeechInputService(controller: controller)

        await service.startListening(existingText: "Keep this")
        controller.emitPartial("discard this")
        let restored = service.cancelListening()

        XCTAssertEqual(restored, "Keep this")
        XCTAssertEqual(service.transcript, "Keep this")
        XCTAssertEqual(controller.stopCalls.last, true)
        XCTAssertEqual(service.state, .idle)
    }

    @MainActor
    func testVoiceInputRepeatedStartsDoNotOverlapRecognitionSessions() async {
        let controller = MockSpeechRecognitionController()
        let service = StylistSpeechInputService(controller: controller)

        await service.startListening(existingText: "")
        await service.startListening(existingText: "")

        XCTAssertEqual(controller.startCount, 1)
    }

    @MainActor
    func testVoiceInputRecognitionUnavailableAndNoSpeechStates() async {
        let unavailable = MockSpeechRecognitionController()
        unavailable.supportsRecognition = false
        let unavailableService = StylistSpeechInputService(controller: unavailable)

        await unavailableService.startListening(existingText: "")
        XCTAssertEqual(unavailableService.state, .recognitionUnavailable)

        let noSpeech = MockSpeechRecognitionController()
        let noSpeechService = StylistSpeechInputService(controller: noSpeech)

        await noSpeechService.startListening(existingText: "")
        noSpeechService.stopListening()

        XCTAssertEqual(noSpeechService.state, .noSpeechDetected)
    }

    func testChatConversationStoreSaveLoadCorruptDeleteAndPrune() throws {
        let url = temporaryStoreURL()
        let store = ChatConversationStore(fileURL: url)
        for index in 0..<12 {
            var conversation = ChatConversation()
            conversation.updatedAt = Date(timeIntervalSince1970: TimeInterval(index))
            conversation.messages = [ChatMessage(role: .user, content: "chat-\(index)")]
            store.save(conversation)
        }

        let loaded = ChatConversationStore(fileURL: url)
        XCTAssertEqual(loaded.conversations.count, 10)
        XCTAssertEqual(loaded.conversations.first?.messages.first?.content, "chat-11")

        try Data("not-json".utf8).write(to: url)
        let recovered = ChatConversationStore(fileURL: url)
        XCTAssertFalse(recovered.conversations.isEmpty, "Corrupt live file should recover from the pre-write backup.")

        recovered.deleteAll()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(ChatConversationStore(fileURL: url).conversations.isEmpty)
    }

    private func temporaryStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("StyleMatchChatTests-\(UUID().uuidString)")
            .appendingPathExtension("json")
    }

    private func storeURL(from store: ChatConversationStore) -> URL {
        Mirror(reflecting: store).children.first { $0.label == "fileURL" }?.value as! URL
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() {
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Timed out waiting for condition.")
    }
}

private final class MockChatTransport: StylistChatTransport {
    private(set) var requests: [ChatRequest] = []
    private let chunks: [String]
    private let delayNanoseconds: UInt64

    init(chunks: [String], delayNanoseconds: UInt64 = 0) {
        self.chunks = chunks
        self.delayNanoseconds = delayNanoseconds
    }

    func send(_ request: ChatRequest) -> AsyncThrowingStream<String, Error> {
        requests.append(request)
        return AsyncThrowingStream { continuation in
            Task {
                for chunk in chunks {
                    continuation.yield(chunk)
                    if delayNanoseconds > 0 {
                        try? await Task.sleep(nanoseconds: delayNanoseconds)
                    }
                }
                continuation.finish()
            }
        }
    }
}

private struct ThrowingChatTransport: StylistChatTransport {
    let error: Error

    func send(_ request: ChatRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: error)
        }
    }
}

private final class MockSpeechRecognitionController: StylistSpeechRecognitionControlling {
    var supportsRecognition = true
    var microphoneStatus: StylistSpeechAuthorizationStatus = .notDetermined
    var speechStatus: StylistSpeechAuthorizationStatus = .notDetermined
    var microphoneRequestResult: StylistSpeechAuthorizationStatus = .authorized
    var speechRequestResult: StylistSpeechAuthorizationStatus = .authorized
    private(set) var microphoneRequestCount = 0
    private(set) var speechRequestCount = 0
    private(set) var startCount = 0
    private(set) var stopCalls: [Bool] = []

    private var partialHandler: (@MainActor (String) -> Void)?
    private var finalHandler: (@MainActor (String) -> Void)?
    private var errorHandler: (@MainActor (Error) -> Void)?

    func microphoneAuthorizationStatus() -> StylistSpeechAuthorizationStatus {
        microphoneStatus
    }

    func speechAuthorizationStatus() -> StylistSpeechAuthorizationStatus {
        speechStatus
    }

    func requestMicrophoneAuthorization() async -> StylistSpeechAuthorizationStatus {
        microphoneRequestCount += 1
        microphoneStatus = microphoneRequestResult
        return microphoneRequestResult
    }

    func requestSpeechAuthorization() async -> StylistSpeechAuthorizationStatus {
        speechRequestCount += 1
        speechStatus = speechRequestResult
        return speechRequestResult
    }

    func startRecognition(
        onPartialTranscript: @escaping @MainActor (String) -> Void,
        onFinalTranscript: @escaping @MainActor (String) -> Void,
        onError: @escaping @MainActor (Error) -> Void
    ) throws {
        startCount += 1
        partialHandler = onPartialTranscript
        finalHandler = onFinalTranscript
        errorHandler = onError
    }

    func stopRecognition(cancel: Bool) {
        stopCalls.append(cancel)
    }

    @MainActor
    func emitPartial(_ text: String) {
        partialHandler?(text)
    }

    @MainActor
    func emitFinal(_ text: String) {
        finalHandler?(text)
    }

    @MainActor
    func emitError(_ error: Error) {
        errorHandler?(error)
    }
}
