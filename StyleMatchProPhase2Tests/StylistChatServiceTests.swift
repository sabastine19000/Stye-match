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

    func testHMACHeaderUsesExpectedDigest() {
        let digest = StylistChatAuthHeaders.hmacSHA256Hex(
            message: "The quick brown fox jumps over the lazy dog",
            secret: "key"
        )

        XCTAssertEqual(
            digest,
            "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8"
        )
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
