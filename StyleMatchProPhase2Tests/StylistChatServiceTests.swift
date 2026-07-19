import XCTest
@testable import StyleMatchPro

final class StyleMatchRuntimeEndpointTests: XCTestCase {
    private let production = StylistChatConfiguration(
        baseURL: URL(string: "https://api.stylematchpro.com")!
    )

    func testDebugOverrideUsesPrivateLANHTTPURL() throws {
        let chatResolution = try XCTUnwrap(StyleMatchRuntimeEndpoint.chatResolution(
            defaultConfiguration: production,
            environment: [
                StyleMatchRuntimeEndpoint.overrideEnvironmentKey: "http://192.168.1.42:8787"
            ],
            allowsOverride: true
        ))
        let accountResolution = try XCTUnwrap(StyleMatchRuntimeEndpoint.accountResolution(
            defaultURL: production.baseURL,
            environment: [
                StyleMatchRuntimeEndpoint.overrideEnvironmentKey: "http://192.168.1.42:8787"
            ],
            allowsOverride: true
        ))

        XCTAssertTrue(chatResolution.overrideActive)
        XCTAssertTrue(accountResolution.overrideActive)
        XCTAssertEqual(chatResolution.baseURL.absoluteString, "http://192.168.1.42:8787")
        XCTAssertEqual(accountResolution.baseURL, chatResolution.baseURL)
    }

    func testUnsetOverridePreservesConfiguredEndpoint() throws {
        let resolution = try XCTUnwrap(StyleMatchRuntimeEndpoint.chatResolution(
            defaultConfiguration: production,
            environment: [:],
            allowsOverride: true
        ))

        XCTAssertFalse(resolution.overrideActive)
        XCTAssertEqual(resolution.baseURL, production.baseURL)
    }

    func testReleaseModeIgnoresOverride() throws {
        let chatResolution = try XCTUnwrap(StyleMatchRuntimeEndpoint.chatResolution(
            defaultConfiguration: production,
            environment: [
                StyleMatchRuntimeEndpoint.overrideEnvironmentKey: "http://10.0.0.25:8787"
            ],
            allowsOverride: false
        ))
        let accountResolution = try XCTUnwrap(StyleMatchRuntimeEndpoint.accountResolution(
            defaultURL: production.baseURL,
            environment: [
                StyleMatchRuntimeEndpoint.overrideEnvironmentKey: "http://10.0.0.25:8787"
            ],
            allowsOverride: false
        ))

        XCTAssertFalse(chatResolution.overrideActive)
        XCTAssertFalse(accountResolution.overrideActive)
        XCTAssertEqual(chatResolution.baseURL, production.baseURL)
        XCTAssertEqual(accountResolution.baseURL, production.baseURL)
    }

    func testDebugOverrideRejectsMalformedPublicOrUnscopedHosts() {
        for rawValue in [
            "not a URL",
            "http://example.com:8787",
            "http://192.168.1.42",
            "http://192.168.1.42:8787/v1/chat"
        ] {
            let chatResolution = StyleMatchRuntimeEndpoint.chatResolution(
                defaultConfiguration: production,
                environment: [StyleMatchRuntimeEndpoint.overrideEnvironmentKey: rawValue],
                allowsOverride: true
            )
            let accountResolution = StyleMatchRuntimeEndpoint.accountResolution(
                defaultURL: production.baseURL,
                environment: [StyleMatchRuntimeEndpoint.overrideEnvironmentKey: rawValue],
                allowsOverride: true
            )
            XCTAssertNil(chatResolution, rawValue)
            XCTAssertNil(accountResolution, rawValue)
        }
    }

    func testStorageEnvironmentClassifiesOnlyApprovedHostsAndOverrides() throws {
        let productionResolution = StyleMatchRuntimeEndpointResolution(
            baseURL: production.baseURL,
            overrideActive: false
        )
        let stagingResolution = StyleMatchRuntimeEndpointResolution(
            baseURL: try XCTUnwrap(URL(string: "https://STYLEMATCH-AFFILIATE-PROXY-STAGING.SABASTINE-7000.WORKERS.DEV")),
            overrideActive: false
        )
        let localResolution = try XCTUnwrap(StyleMatchRuntimeEndpoint.resolve(
            defaultURL: production.baseURL,
            environment: [StyleMatchRuntimeEndpoint.overrideEnvironmentKey: "http://10.0.0.25:8787"],
            allowsOverride: true
        ))

        XCTAssertEqual(AccountStorageEnvironment.classification(for: productionResolution), .production)
        XCTAssertEqual(AccountStorageEnvironment.classification(for: stagingResolution), .staging)
        XCTAssertEqual(AccountStorageEnvironment.classification(for: localResolution), .localAcceptance)
    }

    func testStorageEnvironmentRejectsLookalikeSuffixSubdomainAndUnknownHosts() throws {
        for host in [
            "stylematch-affiliate-proxy-staging.sabastine-7000.workers.dev.evil.example",
            "preview.stylematch-affiliate-proxy-staging.sabastine-7000.workers.dev",
            "stylematch-affiliate-proxy-staging-sabastine-7000.workers.dev",
            "unknown.example"
        ] {
            let resolution = StyleMatchRuntimeEndpointResolution(
                baseURL: try XCTUnwrap(URL(string: "https://\(host)")),
                overrideActive: false
            )
            XCTAssertNil(AccountStorageEnvironment.classification(for: resolution), host)
        }
    }

    func testUnresolvedEndpointDoesNotMutateOrPersistStorageNamespace() {
        let suiteName = "StyleMatchRuntimeEndpointTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("production", forKey: AccountScopedStorage.activeEnvironmentMarkerKey)
        defaults.set("keep-me", forKey: "profileName")

        XCTAssertNil(AccountStorageEnvironment.classification(for: nil))
        XCTAssertFalse(AccountScopedStorage.prepareForLaunch(defaults: defaults, environment: nil))
        XCTAssertEqual(defaults.string(forKey: AccountScopedStorage.activeEnvironmentMarkerKey), "production")
        XCTAssertEqual(defaults.string(forKey: "profileName"), "keep-me")
        XCTAssertNil(defaults.object(forKey: AccountScopedStorage.migrationVersionKey))
    }
}

final class AIInsightChatPromptBuilderTests: XCTestCase {
    private let emptyFacts = AIInsightChatCardFacts(
        screen: "",
        title: "",
        featurePrompt: "",
        extraContext: ""
    )

    func testEightDisplayedMessagesRemainStructuredInsteadOfBecomingOneCompositeQuestion() throws {
        let displayed = (0..<8).map { index in
            AIInsightConversationEntry(
                role: index.isMultiple(of: 2) ? .user : .assistant,
                content: String(repeating: "message-\(index) ", count: 30)
            )
        }

        let request = try AIInsightChatPromptBuilder.build(
            displayedMessages: displayed,
            latestQuestion: "What should I wear today?",
            cardFacts: emptyFacts
        )

        XCTAssertEqual(request.history.map(\.role), displayed.map(\.role))
        XCTAssertEqual(
            request.history.map(\.content),
            displayed.map { $0.content.trimmingCharacters(in: .whitespacesAndNewlines) }
        )
        XCTAssertTrue(request.primaryMessage.contains("What should I wear today?"))
        XCTAssertFalse(request.primaryMessage.contains("message-0"))
        XCTAssertTrue(request.history.allSatisfy {
            $0.content.utf16.count <= AIInsightChatPromptBuilder.maximumMessageUTF16Length
        })
    }

    func testHistoryPreservesStructuredRoles() throws {
        let request = try AIInsightChatPromptBuilder.build(
            displayedMessages: [
                AIInsightConversationEntry(role: .user, content: "I have olive pants."),
                AIInsightConversationEntry(role: .assistant, content: "Try a white or light-blue shirt.")
            ],
            latestQuestion: "Make it more formal.",
            cardFacts: emptyFacts
        )

        XCTAssertEqual(request.history.map(\.role), [.user, .assistant])
        XCTAssertEqual(request.history.map(\.content), [
            "I have olive pants.",
            "Try a white or light-blue shirt."
        ])
    }

    func testRepeatedFailureHistoryIsAlwaysExcludedAndPayloadRemainsBounded() throws {
        let failure = "AI Stylist is having trouble connecting right now. Please try again."
        let displayed = (0..<8).flatMap { index in
            [
                AIInsightConversationEntry(role: .user, content: "Question \(index)"),
                AIInsightConversationEntry(role: .assistant, content: failure)
            ]
        }
        let request = try AIInsightChatPromptBuilder.build(
            displayedMessages: displayed,
            latestQuestion: "What shoes work?",
            cardFacts: emptyFacts
        )

        XCTAssertEqual(request.history.count, 8)
        XCTAssertFalse(request.history.contains { $0.content.localizedCaseInsensitiveContains("trouble connecting") })
        XCTAssertLessThanOrEqual(request.history.count + 1, 20)
        XCTAssertLessThanOrEqual(request.primaryMessage.utf16.count, 1_800)
    }

    func testAllKnownLocalFailureRepliesAreExcluded() throws {
        let request = try AIInsightChatPromptBuilder.build(
            displayedMessages: [
                AIInsightConversationEntry(role: .user, content: "What should I wear today?"),
                AIInsightConversationEntry(
                    role: .assistant,
                    content: "AI Stylist is having trouble connecting right now. Please try again."
                ),
                AIInsightConversationEntry(role: .assistant, content: "A navy overshirt works well."),
                AIInsightConversationEntry(
                    role: .assistant,
                    content: StylistChatMessageLimit.limitMessage
                )
            ],
            latestQuestion: "What shoes should I add?",
            cardFacts: emptyFacts
        )

        XCTAssertEqual(request.history.count, 2)
        XCTAssertFalse(request.history.contains {
            $0.content.contains("trouble connecting") || $0.content == StylistChatMessageLimit.limitMessage
        })
    }

    func testOldestHistoryIsDroppedFirstAtPayloadLimit() throws {
        let displayed = (0..<25).map { index in
            AIInsightConversationEntry(role: .user, content: "message-\(index)")
        }

        let request = try AIInsightChatPromptBuilder.build(
            displayedMessages: displayed,
            latestQuestion: "latest",
            cardFacts: emptyFacts
        )

        XCTAssertEqual(request.history.count, 19)
        XCTAssertEqual(request.history.first?.content, "message-6")
        XCTAssertEqual(request.history.last?.content, "message-24")
    }

    func testProtectedQuestionGuardrailsAndCardFactsSurviveWorstCaseHistoryTrimming() throws {
        let displayed = (0..<40).map { index in
            AIInsightConversationEntry(
                role: index.isMultiple(of: 2) ? .user : .assistant,
                content: String(repeating: "history-\(index) ", count: 200)
            )
        }
        let facts = AIInsightChatCardFacts(
            screen: "Home",
            title: "Morning Brief",
            featurePrompt: "Build from the saved outfit score.",
            extraContext: "The customer wants one practical next step."
        )
        let request = try AIInsightChatPromptBuilder.build(
            displayedMessages: displayed,
            latestQuestion: "What should I wear today?",
            cardFacts: facts
        )

        XCTAssertEqual(request.history.count, 19)
        XCTAssertTrue(request.primaryMessage.contains("What should I wear today?"))
        XCTAssertTrue(request.primaryMessage.contains(StyleMatchAIGuardrails.scoreIntegrityInstruction))
        XCTAssertTrue(request.primaryMessage.contains("- Screen: Home"))
        XCTAssertTrue(request.primaryMessage.contains("- Card: Morning Brief"))
        XCTAssertTrue(request.primaryMessage.contains("- Feature: Build from the saved outfit score."))
        XCTAssertTrue(request.primaryMessage.contains("- Context: The customer wants one practical next step."))
    }

    func testPrimaryMessageAcceptsExactlyEighteenHundredUTF16UnitsAndRejectsBeyondIt() throws {
        let baseline = try AIInsightChatPromptBuilder.build(
            displayedMessages: [],
            latestQuestion: "x",
            cardFacts: emptyFacts
        )
        let overhead = baseline.primaryMessage.utf16.count - 1
        let exactQuestion = String(repeating: "a", count: 1_800 - overhead)
        let exact = try AIInsightChatPromptBuilder.build(
            displayedMessages: [],
            latestQuestion: exactQuestion,
            cardFacts: emptyFacts
        )

        XCTAssertEqual(exact.primaryMessage.utf16.count, 1_800)
        XCTAssertThrowsError(try AIInsightChatPromptBuilder.build(
            displayedMessages: [],
            latestQuestion: exactQuestion + "a",
            cardFacts: emptyFacts
        )) { error in
            XCTAssertEqual(error as? StylistChatError, .payloadTooLarge)
        }
        XCTAssertThrowsError(try AIInsightChatPromptBuilder.build(
            displayedMessages: [],
            latestQuestion: String(repeating: "a", count: 2_000),
            cardFacts: emptyFacts
        )) { error in
            XCTAssertEqual(error as? StylistChatError, .payloadTooLarge)
        }
    }

    func testUTF16AccountingTruncatesOversizedEmojiHistoryWithoutSplittingCharacters() throws {
        let request = try AIInsightChatPromptBuilder.build(
            displayedMessages: [
                AIInsightConversationEntry(
                    role: .assistant,
                    content: String(repeating: "😀", count: 1_000)
                )
            ],
            latestQuestion: "latest",
            cardFacts: emptyFacts
        )

        XCTAssertEqual(request.history.first?.content.utf16.count, 1_800)
        XCTAssertEqual(request.history.first?.content.count, 900)
    }

    func testOutboundPayloadNeverExceedsTwentyMessagesAndReservesPrimaryMessage() throws {
        let displayed = (0..<40).map { index in
            AIInsightConversationEntry(
                role: index.isMultiple(of: 2) ? .user : .assistant,
                content: "message-\(index)"
            )
        }

        let request = try AIInsightChatPromptBuilder.build(
            displayedMessages: displayed,
            latestQuestion: "latest",
            cardFacts: emptyFacts
        )

        XCTAssertEqual(request.history.count, 19)
        XCTAssertEqual(request.history.count + 1, AIInsightChatPromptBuilder.maximumPayloadMessages)
    }

    func testOneOversizedHistoryTurnIsTruncatedInsteadOfAffectingProtectedPrimaryContent() throws {
        let request = try AIInsightChatPromptBuilder.build(
            displayedMessages: [
                AIInsightConversationEntry(role: .assistant, content: String(repeating: "z", count: 2_500))
            ],
            latestQuestion: "Keep this question intact.",
            cardFacts: emptyFacts
        )

        XCTAssertEqual(request.history.first?.content.utf16.count, 1_800)
        XCTAssertTrue(request.primaryMessage.contains("Keep this question intact."))
    }

    func testValidationFailureDoesNotReachNetworkOrRetry() {
        var networkCallCount = 0

        do {
            _ = try AIInsightChatPromptBuilder.build(
                displayedMessages: [],
                latestQuestion: String(repeating: "x", count: 2_000),
                cardFacts: emptyFacts
            )
            networkCallCount += 1
        } catch {
            // A builder rejection occurs before the caller can start transport or retry.
        }

        XCTAssertEqual(networkCallCount, 0)
    }

    func testErrorCopyDistinguishesPayloadValidationFromConnectivityFailure() {
        XCTAssertEqual(
            AIInsightChatErrorPresentation.message(for: StylistChatError.payloadTooLarge),
            StylistChatMessageLimit.limitMessage
        )
        XCTAssertEqual(
            AIInsightChatErrorPresentation.message(for: StylistChatError.network),
            AIInsightChatErrorPresentation.connectivityMessage
        )
    }

    func testShortPromptCompactsOversizedGeneratedContextWithoutTransportRejection() throws {
        let oversizedCloset = (0..<100).map {
            "item-\($0) | Shirt | blue | M | brand | Work | notes"
        }.joined(separator: " ; ")
        let request = try AIInsightChatPromptBuilder.build(
            displayedMessages: [],
            latestQuestion: "What should I wear today?",
            cardFacts: AIInsightChatCardFacts(
                screen: "Closet",
                title: "AI Closet Designer",
                featurePrompt: "Build from my closet.",
                extraContext: "Saved items: \(oversizedCloset)"
            )
        )

        XCTAssertTrue(request.primaryMessage.contains("What should I wear today?"))
        XCTAssertTrue(request.primaryMessage.contains("Saved closet item"))
        XCTAssertLessThanOrEqual(request.primaryMessage.utf16.count, 1_800)
        XCTAssertEqual(request.history.count + 1, 1)
    }

    func testCompactionRetainsGroundedContextSourcesNearLimit() throws {
        let request = try AIInsightChatPromptBuilder.build(
            displayedMessages: [],
            latestQuestion: "Build an outfit.",
            cardFacts: AIInsightChatCardFacts(
                screen: "Closet",
                title: "AI Closet Designer",
                featurePrompt: "Use supplied evidence only.",
                extraContext: """
                Saved items: white shirt | Shirt | white | M | unknown brand | Work | saved
                Latest saved score: 80/100
                Recent scan palette: white, navy
                Weather: cloudy, 79°F
                Size profile: medium
                \(String(repeating: "low priority context ", count: 300))
                """
            )
        )

        XCTAssertTrue(request.primaryMessage.contains("white shirt"))
        XCTAssertTrue(request.primaryMessage.contains("80/100"))
        XCTAssertTrue(request.primaryMessage.contains("white, navy"))
        XCTAssertTrue(request.primaryMessage.contains("cloudy, 79°F"))
        XCTAssertTrue(request.primaryMessage.contains("Size profile: medium"))
        XCTAssertTrue(request.debugMessageSources.last?.contains("closet_context") == true)
        XCTAssertTrue(request.debugMessageSources.last?.contains("score_context") == true)
        XCTAssertTrue(request.debugMessageSources.last?.contains("scan_context") == true)
        XCTAssertTrue(request.debugMessageSources.last?.contains("weather_context") == true)
        XCTAssertTrue(request.debugMessageSources.last?.contains("profile_context") == true)
        XCTAssertLessThanOrEqual(request.primaryMessage.utf16.count, 1_800)
    }

    func testOversizedEmojiGeneratedContextUsesUTF16BudgetAndPreservesQuestion() throws {
        let request = try AIInsightChatPromptBuilder.build(
            displayedMessages: [],
            latestQuestion: "Keep this visible question.",
            cardFacts: AIInsightChatCardFacts(
                screen: "Home",
                title: "Morning Brief",
                featurePrompt: "General guidance",
                extraContext: "Profile notes: \(String(repeating: "😀", count: 1_000))"
            )
        )

        XCTAssertTrue(request.primaryMessage.contains("Keep this visible question."))
        XCTAssertLessThanOrEqual(request.primaryMessage.utf16.count, 1_800)
    }

    func testConsecutiveIdenticalFailureReplyIsNotAppendedTwice() {
        let failure = AIInsightChatErrorPresentation.connectivityMessage

        XCTAssertTrue(AIInsightChatErrorPresentation.shouldAppendFailureReply(failure, after: nil))
        XCTAssertFalse(AIInsightChatErrorPresentation.shouldAppendFailureReply(failure, after: failure))
        XCTAssertTrue(AIInsightChatErrorPresentation.shouldAppendFailureReply(failure, after: "A useful reply."))
    }
}

final class StylistChatServiceTests: XCTestCase {

    func testMessageLimitAcceptsExactlyTwoThousandUTF16CodeUnits() {
        let text = String(repeating: "a", count: 2_000)

        XCTAssertEqual(StylistChatMessageLimit.utf16Length(of: text), 2_000)
        XCTAssertTrue(StylistChatMessageLimit.isWithinLimit(text))
    }

    func testMessageLimitRejectsTwoThousandAndOneUTF16CodeUnits() {
        let text = String(repeating: "a", count: 2_001)

        XCTAssertEqual(StylistChatMessageLimit.utf16Length(of: text), 2_001)
        XCTAssertFalse(StylistChatMessageLimit.isWithinLimit(text))
    }

    func testMessageLimitCountsEmojiAndComposedUnicodeAsUTF16CodeUnits() {
        XCTAssertEqual(StylistChatMessageLimit.utf16Length(of: "😀"), 2)
        XCTAssertEqual(StylistChatMessageLimit.utf16Length(of: "e\u{301}"), 2)
        XCTAssertEqual("😀".count, 1)
        XCTAssertEqual("e\u{301}".count, 1)
    }

    @MainActor
    func testWhitespaceOnlyInputDoesNotSend() {
        let transport = MockChatTransport(chunks: [])
        let service = StylistChatService(
            store: ChatConversationStore(fileURL: temporaryStoreURL()),
            transport: transport
        )

        service.send(" \n\t ")

        XCTAssertTrue(transport.requests.isEmpty)
        XCTAssertTrue(service.activeConversation.messages.isEmpty)
    }

    @MainActor
    func testInputOverLimitBeforeTrimmingSendsWhenTrimmedInputIsValid() async throws {
        let transport = MockChatTransport(chunks: ["done"])
        let service = StylistChatService(
            store: ChatConversationStore(fileURL: temporaryStoreURL()),
            transport: transport
        )
        let input = " " + String(repeating: "a", count: 2_000) + " "

        XCTAssertEqual(StylistChatMessageLimit.utf16Length(of: input), 2_002)
        service.send(input)
        try await waitUntil { !service.isStreaming }

        let sent = try XCTUnwrap(transport.requests.last?.messages.last?.content)
        XCTAssertEqual(StylistChatMessageLimit.utf16Length(of: sent), 2_000)
        XCTAssertEqual(sent, StylistChatMessageLimit.trimmedForSending(input))
    }

    @MainActor
    func testOversizedInputIsRejectedWithoutTruncationOrRequest() {
        let transport = MockChatTransport(chunks: [])
        let service = StylistChatService(
            store: ChatConversationStore(fileURL: temporaryStoreURL()),
            transport: transport
        )
        let input = String(repeating: "a", count: 2_001)

        service.send(input)

        XCTAssertTrue(transport.requests.isEmpty)
        XCTAssertTrue(service.activeConversation.messages.isEmpty)
        XCTAssertEqual(service.inlineError, StylistChatMessageLimit.limitMessage)
    }

    func testHTTP413MapsToPayloadTooLargeDefensively() {
        XCTAssertEqual(LiveChatTransport.error(forHTTPStatusCode: 413), .payloadTooLarge)
        XCTAssertEqual(
            LiveChatTransport.error(forHTTPStatusCode: 413)?.localizedDescription,
            StylistChatMessageLimit.limitMessage
        )
    }

    func testHTTP413RetainsStatusBodyRequestIDAndEndpointDiagnostically() throws {
        let endpoint = try XCTUnwrap(URL(string: "https://api.stylematchpro.com/v1/chat"))
        let response = try XCTUnwrap(HTTPURLResponse(
            url: endpoint,
            statusCode: 413,
            httpVersion: "HTTP/2",
            headerFields: ["CF-Ray": "request-413-ATL"]
        ))
        let diagnostic = LiveChatTransport.diagnosticError(
            forHTTPResponse: response,
            responseBody: "{\"error\":\"payload_too_large\"}",
            endpoint: endpoint
        )

        XCTAssertEqual(diagnostic.category, .payloadTooLarge)
        XCTAssertEqual(diagnostic.statusCode, 413)
        XCTAssertEqual(diagnostic.responseBody, "{\"error\":\"payload_too_large\"}")
        XCTAssertEqual(diagnostic.requestID, "request-413-ATL")
        XCTAssertEqual(diagnostic.endpoint, endpoint)
        XCTAssertNil(diagnostic.underlyingErrorDescription)
        XCTAssertEqual(diagnostic.localizedDescription, StylistChatMessageLimit.limitMessage)
    }

    func testOversizedGeneratedPayloadIsRejectedBeforeTransportStarts() async throws {
        NoNetworkURLProtocol.requestCount = 0
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NoNetworkURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let transport = LiveChatTransport(
            configuration: StylistChatConfiguration(baseURL: URL(string: "https://api.stylematchpro.com")!),
            session: session,
            accountSession: {
                StyleMatchAccountSession(token: String(repeating: "t", count: 64), expiresAt: .distantFuture)
            }
        )
        let request = ChatRequest(
            messages: [
                ChatRequest.RequestMessage(role: "user", content: String(repeating: "x", count: 2_001))
            ],
            context: ChatContext(),
            stream: true
        )

        do {
            for try await _ in transport.send(request) {}
            XCTFail("Expected the local payload limit to reject the request.")
        } catch {
            XCTAssertEqual(error as? StylistChatError, .payloadTooLarge)
        }
        XCTAssertEqual(NoNetworkURLProtocol.requestCount, 0)
    }

    func testPayloadValidationRejectsWhitespaceOnlyGeneratedMessage() {
        let messages = [ChatRequest.RequestMessage(role: "user", content: " \n\t ")]
        XCTAssertEqual(StylistChatMessageLimit.validationError(for: messages), .invalidRequest)
    }

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
        XCTAssertEqual(transport.requests.last?.messages.first?.content, "message-9")
        XCTAssertEqual(transport.requests.last?.messages.last?.content, "new question")
        XCTAssertLessThanOrEqual(
            transport.requests.last?.messages.count ?? .max,
            StylistChatMessageLimit.maximumPayloadMessages
        )
        XCTAssertFalse(transport.requests.last?.messages.contains { $0.content.isEmpty } ?? true)
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
        let payload = [context.profileSummary, context.recentOutfits, context.activeScan, context.scoreBreakdown ?? ""].joined(separator: "\n")

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
        let payload = [context.profileSummary, context.recentOutfits, context.activeScan, context.scoreBreakdown ?? ""].joined(separator: "\n")

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
        let payload = [context.profileSummary, context.recentOutfits, context.activeScan, context.scoreBreakdown ?? ""].joined(separator: "\n")

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

        XCTAssertEqual(transport.requests.last?.messages.last?.content, "Give me three outfits with olive pants.")
        XCTAssertFalse(transport.requests.last?.messages.contains { $0.content.isEmpty } ?? true)
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

        XCTAssertEqual(transport.requests.last?.messages.last?.content, "Build a dinner outfit with white sneakers")
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

        let payload = [
            transport.requests.last?.context.profileSummary,
            transport.requests.last?.context.recentOutfits,
            transport.requests.last?.context.activeScan
        ].compactMap { $0 }.joined(separator: "\n")
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
    func testUnauthorizedSubmissionDoesNotCreateMessagesOrRequest() {
        let store = ChatConversationStore(fileURL: temporaryStoreURL())
        let transport = MockChatTransport(chunks: [], authorizationState: .signInRequired)
        let service = StylistChatService(
            store: store,
            transport: transport,
            contextProvider: { ChatContext() }
        )

        XCTAssertFalse(service.send("Build three outfits around olive pants."))

        XCTAssertTrue(service.activeConversation.messages.isEmpty)
        XCTAssertTrue(transport.requests.isEmpty)
        XCTAssertTrue(service.requiresSignIn)
        XCTAssertEqual(service.inlineError, StylistChatError.unauthorized.localizedDescription)
        XCTAssertTrue(ChatConversationStore(fileURL: storeURL(from: store)).conversations.isEmpty)
    }

    @MainActor
    func testUnauthorizedPreseededQuestionDoesNotReplaceCurrentConversation() {
        let store = ChatConversationStore(fileURL: temporaryStoreURL())
        var existing = ChatConversation()
        existing.messages = [ChatMessage(role: .assistant, content: "Existing advice")]
        store.save(existing)
        let transport = MockChatTransport(chunks: [], authorizationState: .signInRequired)
        let service = StylistChatService(store: store, transport: transport)

        service.sendPreseededQuestion("Build around this scan", context: ChatContext())

        XCTAssertEqual(service.activeConversation.id, existing.id)
        XCTAssertEqual(service.activeConversation.messages, existing.messages)
        XCTAssertTrue(transport.requests.isEmpty)
        XCTAssertTrue(service.requiresSignIn)
    }

    @MainActor
    func testRelaunchRestoresAuthorizedAIStateFromValidBackendSession() {
        let validSession = StyleMatchAccountSession(
            token: String(repeating: "s", count: 40),
            expiresAt: Date().addingTimeInterval(3_600)
        )
        let transport = LiveChatTransport(
            configuration: StylistChatConfiguration(baseURL: URL(string: "https://example.com")!),
            accountSession: { validSession },
            appleAccountIsConnected: { true }
        )

        let service = StylistChatService(
            store: ChatConversationStore(fileURL: temporaryStoreURL()),
            transport: transport
        )

        XCTAssertEqual(service.authorizationState, .authorized)
        XCTAssertFalse(service.requiresSignIn)
    }

    func testExpiredBackendSessionForConnectedAppleAccountRequiresReconnect() {
        let expiredSession = StyleMatchAccountSession(
            token: String(repeating: "s", count: 40),
            expiresAt: Date().addingTimeInterval(-60)
        )
        let transport = LiveChatTransport(
            configuration: StylistChatConfiguration(baseURL: URL(string: "https://example.com")!),
            accountSession: { expiredSession },
            appleAccountIsConnected: { true }
        )

        XCTAssertEqual(transport.authorizationState, .reconnectRequired)
    }

    @MainActor
    func testSuccessfulSessionRefreshSynchronizesAIStateImmediately() async throws {
        let transport = MockChatTransport(chunks: [], authorizationState: .reconnectRequired)
        let service = StylistChatService(
            store: ChatConversationStore(fileURL: temporaryStoreURL()),
            transport: transport
        )
        XCTAssertTrue(service.requiresSignIn)

        transport.authorizationState = .authorized
        NotificationCenter.default.post(name: StyleMatchAccountSessionStore.didChangeNotification, object: nil)
        try await waitUntil { service.authorizationState == .authorized }

        XCTAssertFalse(service.requiresSignIn)
        XCTAssertNil(service.inlineError)
    }

    @MainActor
    func testRapidDuplicateSubmissionStartsOnlyOneRequest() async throws {
        let store = ChatConversationStore(fileURL: temporaryStoreURL())
        let transport = MockChatTransport(chunks: ["One response"], delayNanoseconds: 200_000_000)
        let service = StylistChatService(
            store: store,
            transport: transport,
            contextProvider: { ChatContext() }
        )

        XCTAssertTrue(service.send("What goes with olive pants?"))
        XCTAssertFalse(service.send("What goes with olive pants?"))
        try await waitUntil { !service.isStreaming }

        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(service.activeConversation.messages.filter { $0.role == .user }.count, 1)
        XCTAssertEqual(service.activeConversation.messages.filter { $0.role == .assistant }.count, 1)
    }

    @MainActor
    func testFailedOutfitCombinationKeepsAcceptedUserMessageAndClearsSendingState() async throws {
        let store = ChatConversationStore(fileURL: temporaryStoreURL())
        let transport = ThrowingChatTransport(error: StylistChatError.network)
        let service = StylistChatService(
            store: store,
            transport: transport,
            contextProvider: { PersonalizationContextBuilder.conversationalStylistContext() }
        )

        XCTAssertTrue(service.send("Build three outfits around olive pants."))
        try await waitUntil { !service.isStreaming }

        XCTAssertEqual(service.activeConversation.messages.map(\.content), ["Build three outfits around olive pants."])
        XCTAssertEqual(service.inlineError, StylistChatError.network.localizedDescription)
        XCTAssertFalse(service.requiresSignIn)
        XCTAssertFalse(service.isStreaming)
        XCTAssertEqual(
            ChatConversationStore(fileURL: storeURL(from: store)).conversations.first?.messages.map(\.content),
            ["Build three outfits around olive pants."]
        )
    }

    @MainActor
    func testFailedFollowUpKeepsAcceptedUserMessageWithoutEmptyAssistant() async throws {
        let store = ChatConversationStore(fileURL: temporaryStoreURL())
        var existing = ChatConversation()
        existing.messages = [
            ChatMessage(role: .user, content: "What works with navy?"),
            ChatMessage(role: .assistant, content: "Try white or tan.")
        ]
        store.save(existing)
        let service = StylistChatService(
            store: store,
            transport: ThrowingChatTransport(error: StylistChatError.network),
            contextProvider: { ChatContext() }
        )

        XCTAssertTrue(service.send("What about olive?"))
        try await waitUntil { !service.isStreaming }

        XCTAssertEqual(
            service.activeConversation.messages.map(\.content),
            existing.messages.map(\.content) + ["What about olive?"]
        )
        XCTAssertFalse(service.activeConversation.messages.contains { $0.role == .assistant && $0.content.isEmpty })
        XCTAssertEqual(
            ChatConversationStore(fileURL: storeURL(from: store)).conversations.first?.messages.map(\.content),
            existing.messages.map(\.content) + ["What about olive?"]
        )
    }

    @MainActor
    func testLegacyEmptyAssistantPlaceholderIsRemovedWhenConversationLoads() {
        let url = temporaryStoreURL()
        let store = ChatConversationStore(fileURL: url)
        var conversation = ChatConversation()
        conversation.messages = [
            ChatMessage(role: .assistant, content: ""),
            ChatMessage(role: .assistant, content: "   ")
        ]
        store.save(conversation)

        let service = StylistChatService(
            store: ChatConversationStore(fileURL: url),
            transport: MockChatTransport(chunks: []),
            contextProvider: { ChatContext() }
        )

        XCTAssertTrue(service.activeConversation.messages.isEmpty)
    }

    @MainActor
    func testPreviouslyAcceptedUserMessagesRemainWhenConversationLoads() {
        let url = temporaryStoreURL()
        let store = ChatConversationStore(fileURL: url)
        var conversation = ChatConversation()
        conversation.messages = [
            ChatMessage(role: .user, content: "Completed question"),
            ChatMessage(role: .assistant, content: "Completed response"),
            ChatMessage(role: .user, content: "Dead failed attempt"),
            ChatMessage(role: .user, content: "Duplicate dead attempt")
        ]
        store.save(conversation)

        let service = StylistChatService(
            store: ChatConversationStore(fileURL: url),
            transport: MockChatTransport(chunks: [])
        )

        XCTAssertEqual(
            service.activeConversation.messages.map(\.content),
            ["Completed question", "Completed response", "Dead failed attempt", "Duplicate dead attempt"]
        )
    }

    func testStylistChatViewRetainsBuild17PromptLibraryAndCoreControls() throws {
        let source = try projectSource("StyleMatchAI/StylistChat/StylistChatView.swift")
        let expectedPrompts = [
            "What goes with olive pants?",
            "Build an outfit around this item.",
            "Build three outfits around this item.",
            "What shoes work with this outfit?",
            "Make this look more professional.",
            "Make this outfit business casual.",
            "Give me a casual and an elevated version.",
            "Give me three color combinations.",
            "Suggest another shirt-and-pants combination.",
            "Build a dinner outfit.",
            "Give me a warm-weather option.",
            "What should I wear for dinner?",
            "Help me match this shirt."
        ]

        XCTAssertTrue(source.contains("Button(\"History\")"))
        XCTAssertTrue(source.contains("Button(\"New chat\")"))
        XCTAssertTrue(source.contains("TextField(\"Ask your stylist...\""))
        XCTAssertTrue(source.contains("ForEach(starterPrompts"))
        XCTAssertTrue(source.contains(".disabled(service.isStreaming)"))
        XCTAssertTrue(source.contains("\"Sign in with Apple\""))
        XCTAssertTrue(source.contains("Reconnect with Apple"))
        for prompt in expectedPrompts {
            XCTAssertTrue(source.contains("\"\(prompt)\""), "Missing prompt: \(prompt)")
        }
    }

    func testStylistChatComposerRemainsAnchoredAndRoutesUnauthorizedSendToSignIn() throws {
        let source = try projectSource("StyleMatchAI/StylistChat/StylistChatView.swift")
        let contentSource = try projectSource("StyleMatchAI/ContentView.swift")

        XCTAssertTrue(source.contains(".safeAreaInset(edge: .bottom, spacing: 0)"))
        XCTAssertTrue(source.contains("anchoredInputBar"))
        XCTAssertTrue(source.contains(".scrollDismissesKeyboard(.interactively)"))
        XCTAssertTrue(source.contains("TextField(\"Ask your stylist...\", text: $draft, axis: .vertical)"))
        XCTAssertTrue(source.contains(".lineLimit(1...4)"))
        XCTAssertTrue(source.contains(".onSubmit {\n                        sendDraft()"))
        XCTAssertTrue(source.contains("guard service.authorizationState == .authorized else"))
        XCTAssertTrue(source.contains("onSignInRequested()"))
        XCTAssertTrue(source.contains("let capturedDraft = preparedDraft"))
        XCTAssertTrue(source.contains("guard submitQuestion(capturedDraft) else { return }"))
        XCTAssertTrue(source.contains("draft = \"\""))
        let captureIndex = try XCTUnwrap(source.range(of: "let capturedDraft = preparedDraft")?.lowerBound)
        let submitIndex = try XCTUnwrap(
            source.range(
                of: "guard submitQuestion(capturedDraft) else { return }",
                range: captureIndex..<source.endIndex
            )?.lowerBound
        )
        let clearIndex = try XCTUnwrap(
            source.range(of: "draft = \"\"", range: submitIndex..<source.endIndex)?.lowerBound
        )
        XCTAssertLessThan(captureIndex, submitIndex)
        XCTAssertLessThan(submitIndex, clearIndex)
        XCTAssertTrue(source.contains("StylistChatMessageLimit.utf16Length(of: preparedDraft)"))
        XCTAssertTrue(source.contains("Text(\"\\(draftUTF16Length) / 2,000\")"))
        XCTAssertTrue(source.contains("Text(StylistChatMessageLimit.limitMessage)"))
        XCTAssertTrue(source.contains(".disabled(preparedDraft.isEmpty || draftExceedsLimit)"))
        XCTAssertTrue(contentSource.contains("if !isSoftwareKeyboardVisible {\n                    bottomNavigation"))
        XCTAssertTrue(contentSource.contains(".scrollDismissesKeyboard(.interactively)"))
        XCTAssertTrue(contentSource.contains("UIResponder.keyboardWillChangeFrameNotification"))
        XCTAssertTrue(contentSource.contains("UIResponder.keyboardWillHideNotification"))
        XCTAssertTrue(contentSource.contains("updateSoftwareKeyboardVisibility(from: notification)"))
        XCTAssertTrue(contentSource.contains("isSoftwareKeyboardVisible = false"))
        XCTAssertTrue(contentSource.contains("#selector(UIResponder.resignFirstResponder)"))
    }

    func testStylistChatComposerUsesMeasuredFloatingNavigationClearance() throws {
        let chatSource = try projectSource("StyleMatchAI/StylistChat/StylistChatView.swift")
        let contentSource = try projectSource("StyleMatchAI/ContentView.swift")

        XCTAssertTrue(contentSource.contains("StyleMatchBottomNavigationFramePreferenceKey"))
        XCTAssertTrue(contentSource.contains("value: proxy.frame(in: .global)"))
        XCTAssertTrue(contentSource.contains("return bottomNavigationFrame.height"))
        XCTAssertTrue(contentSource.contains("bottomNavigationClearance: chatBottomNavigationClearance"))
        XCTAssertTrue(chatSource.contains("bottomNavigationClearance: CGFloat = 0"))
        XCTAssertTrue(chatSource.contains(".padding(.bottom, bottomNavigationClearance)"))
        XCTAssertTrue(chatSource.contains("StyleMatchComposerFramePreferenceKey"))
        XCTAssertFalse(chatSource.contains("ignoresSafeArea(.keyboard"))
        XCTAssertFalse(chatSource.contains("keyboardHeight"))
        XCTAssertFalse(chatSource.contains("keyboardOffset"))
    }

    func testStylistChatMeasuredClearancePreservesComposerInteractionContract() throws {
        let source = try projectSource("StyleMatchAI/StylistChat/StylistChatView.swift")

        XCTAssertTrue(source.contains("TextField(\"Ask your stylist...\", text: $draft, axis: .vertical)"))
        XCTAssertTrue(source.contains(".lineLimit(1...4)"))
        XCTAssertTrue(source.contains("sendDraft()"))
        XCTAssertTrue(source.contains("voiceInputButton"))
        XCTAssertTrue(source.contains("Text(\"\\(draftUTF16Length) / 2,000\")"))
        XCTAssertTrue(source.contains("Text(StylistChatMessageLimit.limitMessage)"))
        XCTAssertTrue(source.contains(".scrollDismissesKeyboard(.interactively)"))
    }

    func testStylistChatTabEntryDoesNotAutomaticallyFocusComposerOrPresentKeyboard() throws {
        let source = try projectSource("StyleMatchAI/StylistChat/StylistChatView.swift")

        XCTAssertTrue(source.contains("Button(\"History\")"))
        XCTAssertTrue(source.contains("TextField(\"Ask your stylist...\", text: $draft, axis: .vertical)"))
        XCTAssertFalse(source.contains("@FocusState"))
        XCTAssertFalse(source.contains(".focused("))
        XCTAssertFalse(source.contains("becomeFirstResponder"))
    }

    func testKeyboardFrameVisibilityUsesActiveWindowIntersectionAndSafeResetPaths() throws {
        let source = try projectSource("StyleMatchAI/ContentView.swift")

        XCTAssertTrue(source.contains("UIResponder.keyboardFrameEndUserInfoKey"))
        XCTAssertTrue(source.contains("window.screen.coordinateSpace.convert("))
        XCTAssertTrue(source.contains("to: window.coordinateSpace"))
        XCTAssertTrue(source.contains("windowBounds.intersects(keyboardFrame)"))
        XCTAssertTrue(source.contains("$0.activationState == .foregroundActive || $0.activationState == .foregroundInactive"))
        XCTAssertTrue(source.contains("windows.first(where: \\.isKeyWindow)"))
        XCTAssertTrue(source.contains("phase == .background || phase == .inactive"))
        XCTAssertTrue(source.contains("isSoftwareKeyboardVisible = false"))
    }

    func testRootTabSelectionDismissesKeyboardForSameTabCrossTabAndProgrammaticChanges() throws {
        let source = try projectSource("StyleMatchAI/ContentView.swift")
        let sceneStart = try XCTUnwrap(source.range(of: ".styleMatchOnChange(of: scenePhase)"))
        let selectionStart = try XCTUnwrap(source.range(of: ".styleMatchOnChange(of: selectedTab)", range: sceneStart.upperBound..<source.endIndex))
        let bodyEnd = try XCTUnwrap(source.range(of: "@ViewBuilder\n    private var activeScreen", range: selectionStart.upperBound..<source.endIndex))
        let sceneObserver = String(source[sceneStart.lowerBound..<selectionStart.lowerBound])
        let selectionObserver = String(source[selectionStart.lowerBound..<bodyEnd.lowerBound])
        let selectTabStart = try XCTUnwrap(source.range(of: "private func selectTab(_ tab: AppTab)"))
        let selectTabEnd = try XCTUnwrap(source.range(of: "private func checkForPendingFeedbackPrompt", range: selectTabStart.upperBound..<source.endIndex))
        let selectTab = String(source[selectTabStart.lowerBound..<selectTabEnd.lowerBound])

        XCTAssertTrue(source.contains("private func dismissSoftwareKeyboard()"))
        XCTAssertTrue(source.contains("#selector(UIResponder.resignFirstResponder)"))
        XCTAssertTrue(sceneObserver.contains("phase == .background || phase == .inactive"))
        XCTAssertTrue(sceneObserver.contains("dismissSoftwareKeyboard()"))
        XCTAssertTrue(sceneObserver.contains("isSoftwareKeyboardVisible = false"))
        XCTAssertTrue(source.contains(".onDisappear {\n            dismissSoftwareKeyboard()\n            isSoftwareKeyboardVisible = false"))
        XCTAssertTrue(selectionObserver.contains("dismissSoftwareKeyboard()"))
        XCTAssertTrue(selectTab.contains("guard selectedTab != tab else"))
        XCTAssertTrue(selectTab.contains("dismissSoftwareKeyboard()\n            return"))
        XCTAssertTrue(selectTab.contains("withTransaction(transaction) {\n            selectedTab = tab"))
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

    func testWarmWeatherWithholdsHistoricalJacketRecommendationEvidence() {
        let analysis = contextSelectionAnalysis(
            garments: ["jacket"],
            confidences: [DetectedItemConfidence(item: "jacket", confidence: 96)]
        )

        let context = AIStylistContextSelection.historicalScanContext(
            score: 80,
            analysis: analysis,
            weatherConstraint: AIStylistContextSelection.weatherConstraint(fahrenheit: 79, condition: "cloudy")
        )

        XCTAssertTrue(context.contains("Historical outerwear was withheld"))
        XCTAssertFalse(context.localizedCaseInsensitiveContains("jacket"))
        XCTAssertTrue(AIStylistContextSelection.weatherConstraint(fahrenheit: 79).contains("warm"))
    }

    func testActiveScanAndHistoricalScanRemainSeparateWithActiveAuthority() {
        let active = contextSelectionAnalysis(
            garments: ["shirt"],
            confidences: [DetectedItemConfidence(item: "shirt", confidence: 95)]
        )
        let historical = contextSelectionAnalysis(
            garments: ["pants"],
            confidences: [DetectedItemConfidence(item: "pants", confidence: 95)]
        )
        let context = ChatContext(
            activeScan: AIStylistContextSelection.activeScanContext(active),
            historicalOutfits: AIStylistContextSelection.historicalScanContext(score: 75, analysis: historical)
        )

        XCTAssertTrue(context.activeScan.contains("authoritative for the current outfit"))
        XCTAssertTrue(context.activeScan.contains("shirt"))
        XCTAssertFalse(context.activeScan.contains("pants"))
        XCTAssertTrue(context.historicalOutfits.contains("not the current outfit"))
    }

    func testHistoricalScanNeverMakesPresentTenseCurrentOutfitClaim() {
        let context = AIStylistContextSelection.historicalScanContext(
            score: 77,
            analysis: contextSelectionAnalysis(
                garments: ["pants"],
                confidences: [DetectedItemConfidence(item: "pants", confidence: 94)]
            )
        )

        XCTAssertTrue(context.contains("optional reference"))
        XCTAssertTrue(context.contains("not the current outfit"))
        XCTAssertFalse(context.localizedCaseInsensitiveContains("you are wearing"))
        XCTAssertFalse(context.localizedCaseInsensitiveContains("currently wearing"))
    }

    func testGarmentBelowNinetyPercentIsNotExposedAsFactual() {
        let analysis = contextSelectionAnalysis(
            garments: ["jacket"],
            confidences: [DetectedItemConfidence(item: "jacket", confidence: 89)]
        )

        XCTAssertTrue(AIStylistContextSelection.authoritativeGarments(in: analysis).isEmpty)
        XCTAssertFalse(
            AIStylistContextSelection.historicalScanContext(score: 80, analysis: analysis)
                .localizedCaseInsensitiveContains("jacket")
        )
    }

    func testHistoricalItemsAreLabeledOptionalAndNeverClosetOwned() {
        let context = AIStylistContextSelection.historicalScanContext(
            score: 81,
            analysis: contextSelectionAnalysis(
                garments: ["shirt"],
                confidences: [DetectedItemConfidence(item: "shirt", confidence: 96)]
            )
        )

        XCTAssertTrue(context.contains("optional reference"))
        XCTAssertTrue(context.contains("optional reference, never"))
        XCTAssertFalse(context.localizedCaseInsensitiveContains("from your closet"))
        XCTAssertFalse(context.localizedCaseInsensitiveContains("you already own"))
    }

    func testScanPaletteIsNotBoundToLowConfidenceGarmentLabel() {
        let context = AIStylistContextSelection.historicalScanContext(
            score: 80,
            analysis: contextSelectionAnalysis(
                garments: ["jacket"],
                confidences: [DetectedItemConfidence(item: "jacket", confidence: 72)],
                palette: ["gray", "brown"]
            )
        )

        XCTAssertTrue(context.contains("Scan-level palette (not garment-specific): gray, brown"))
        XCTAssertFalse(context.localizedCaseInsensitiveContains("gray jacket"))
        XCTAssertFalse(context.localizedCaseInsensitiveContains("brown jacket"))
    }

    func testMissingSavedScanBreakdownIsExplicitlyUnavailable() {
        let context = AIStylistContextSelection.scoreContext(
            score: 80,
            analysis: contextSelectionAnalysis(garments: [], confidences: []),
            source: "saved scan"
        )

        XCTAssertTrue(context.contains("Overall score from saved scan: 80/100"))
        XCTAssertTrue(context.contains("Category breakdown unavailable for this saved scan"))
    }

    func testMissingBreakdownDoesNotInventWeakestCategory() {
        let context = AIStylistContextSelection.scoreContext(
            score: 80,
            analysis: contextSelectionAnalysis(garments: [], confidences: []),
            source: "saved scan"
        )

        XCTAssertFalse(context.contains("Weakest persisted category:"))
        XCTAssertTrue(context.contains("Do not identify a weakest category"))
        XCTAssertFalse(context.localizedCaseInsensitiveContains("fit is weakest"))
    }

    func testScanTabWithoutActiveScanKeepsVisibleAggregatesSeparateFromCurrentScore() {
        let context = StylistScreenContext(
            currentTab: .scan,
            activeScanState: .none,
            activeScanID: "must-not-survive",
            selectedOccasion: "general",
            selectedAnalysisSection: "colors",
            visibleOverallScore: nil,
            entryPoint: .scanTab,
            visibleAggregates: StylistVisibleAggregateStatistics(
                averageScore: 88,
                highestScore: 96,
                totalScans: 347
            ),
            closetState: .loadedEmpty
        )

        XCTAssertEqual(context.currentTab, .scan)
        XCTAssertEqual(context.activeScanState, .none)
        XCTAssertNil(context.activeScanID)
        XCTAssertNil(context.visibleOverallScore)
        XCTAssertEqual(context.visibleAggregates?.averageScore, 88)
        XCTAssertEqual(context.visibleAggregates?.highestScore, 96)
        XCTAssertEqual(context.visibleAggregates?.totalScans, 347)
    }

    func testSavedScanScreenContextCarriesOnlyItsVisibleScoreAndIdentity() {
        let context = StylistScreenContext(
            currentTab: .scan,
            activeScanState: .saved,
            activeScanID: "saved-123",
            selectedOccasion: "work",
            selectedAnalysisSection: "fit",
            visibleOverallScore: 80,
            entryPoint: .scanResult,
            closetState: .unavailable
        )

        XCTAssertEqual(context.activeScanState, .saved)
        XCTAssertEqual(context.activeScanID, "saved-123")
        XCTAssertEqual(context.visibleOverallScore, 80)
    }

    func testLiveScanScreenContextIsDistinctFromSavedScan() {
        let context = StylistScreenContext(
            currentTab: .scan,
            activeScanState: .live,
            activeScanID: "live-456",
            visibleOverallScore: 91,
            entryPoint: .scanResult,
            closetState: .loadedWithItems
        )

        XCTAssertEqual(context.activeScanState, .live)
        XCTAssertEqual(context.activeScanID, "live-456")
        XCTAssertEqual(context.visibleOverallScore, 91)
    }

    func testActiveScanStateResolverRequiresACompletedResultAndCurrentSavedIdentity() {
        let savedIDs: Set<String> = ["saved-123"]

        XCTAssertEqual(
            StylistActiveScanStateResolver.resolve(
                hasResult: true,
                hasSelectedImage: false,
                activeScanID: "saved-123",
                savedScanIDs: savedIDs
            ),
            .saved
        )
        XCTAssertEqual(
            StylistActiveScanStateResolver.resolve(
                hasResult: true,
                hasSelectedImage: true,
                activeScanID: "live-456",
                savedScanIDs: savedIDs
            ),
            .live
        )
        XCTAssertEqual(
            StylistActiveScanStateResolver.resolve(
                hasResult: false,
                hasSelectedImage: true,
                activeScanID: "partial-live-scan",
                savedScanIDs: savedIDs
            ),
            .none
        )
        XCTAssertEqual(
            StylistActiveScanStateResolver.resolve(
                hasResult: true,
                hasSelectedImage: false,
                activeScanID: "deleted-scan",
                savedScanIDs: savedIDs
            ),
            .none
        )
    }

    func testDeletedSavedScanIsInvalidatedAtSendTimeAndClearsCurrentScoreEvidence() {
        let selectedScan = StylistScreenContext(
            currentTab: .scan,
            activeScanState: .saved,
            activeScanID: "deleted-scan",
            visibleOverallScore: 80,
            entryPoint: .scanResult,
            closetState: .unavailable
        )
        let invalidated = selectedScan.resolvingSavedScanAvailability(["different-scan"])
        let context = ChatContext(
            activeScan: "Selected scan: score 80/100; jacket.",
            scoreBreakdown: "Existing score only: 80/100.",
            screenContext: selectedScan
        ).applyingCurrentScreenContext(invalidated)

        XCTAssertEqual(invalidated.activeScanState, .none)
        XCTAssertNil(invalidated.activeScanID)
        XCTAssertNil(invalidated.visibleOverallScore)
        XCTAssertEqual(invalidated.entryPoint, .scanTab)
        XCTAssertTrue(context.activeScan.isEmpty)
        XCTAssertNil(context.scoreBreakdown)
    }

    func testSavedScanRemainsAuthoritativeWhileItsIdentityStillExists() {
        let selectedScan = StylistScreenContext(
            currentTab: .scan,
            activeScanState: .saved,
            activeScanID: "saved-123",
            visibleOverallScore: 80,
            entryPoint: .scanResult,
            closetState: .unavailable
        )
        let resolved = selectedScan.resolvingSavedScanAvailability(["saved-123"])
        let context = ChatContext(
            activeScan: "Selected scan: score 80/100.",
            scoreBreakdown: "Existing score only: 80/100.",
            screenContext: selectedScan
        ).applyingCurrentScreenContext(resolved)

        XCTAssertEqual(resolved, selectedScan)
        XCTAssertFalse(context.activeScan.isEmpty)
        XCTAssertNotNil(context.scoreBreakdown)
    }

    func testAITabEntryPointsNeverCarryCurrentOutfitAuthority() {
        for entryPoint in [
            StylistEntryPoint.homeMorningBrief,
            .closetDesigner,
            .profile,
            .scanTab,
            .aiTab
        ] {
            let context = StylistScreenContext.aiTab(entryPoint: entryPoint)
            XCTAssertEqual(context.currentTab, .ai)
            XCTAssertEqual(context.activeScanState, .none)
            XCTAssertNil(context.activeScanID)
            XCTAssertNil(context.visibleOverallScore)
            XCTAssertEqual(context.entryPoint, entryPoint)
        }
    }

    func testClosetStateDistinguishesLoadedEmptyFromUnavailable() {
        XCTAssertEqual(StylistClosetState.fromSerializedClosetData(Data()), .loadedEmpty)
        XCTAssertEqual(StylistClosetState.fromSerializedClosetData(Data("not-json".utf8)), .unavailable)
        XCTAssertEqual(StylistClosetState.fromSerializedClosetData(Data("[]".utf8)), .loadedEmpty)
        XCTAssertEqual(StylistClosetState.fromSerializedClosetData(Data("[{}]".utf8)), .loadedWithItems)
    }

    func testChatRequestEncodesTypedScreenContextWithoutPromotingAggregates() throws {
        let screenContext = StylistScreenContext(
            currentTab: .scan,
            activeScanState: .none,
            selectedOccasion: "general",
            selectedAnalysisSection: "colors",
            visibleOverallScore: nil,
            entryPoint: .scanTab,
            visibleAggregates: StylistVisibleAggregateStatistics(
                averageScore: 88,
                highestScore: 96,
                totalScans: 347
            ),
            closetState: .loadedEmpty
        )
        let request = ChatRequest(
            messages: [.init(role: "user", content: "Improve this score.")],
            context: ChatContext(screenContext: screenContext),
            stream: true
        )
        let decoded = try JSONDecoder().decode(ChatRequest.self, from: JSONEncoder().encode(request))

        XCTAssertEqual(decoded.context.screenContext, screenContext)
        XCTAssertNil(decoded.context.screenContext?.visibleOverallScore)
        XCTAssertEqual(decoded.context.screenContext?.visibleAggregates?.averageScore, 88)
    }

    func testMorningBriefUsesConservativeNoActiveScanScreenContext() {
        let context = StylistScreenContext.morningBrief()

        XCTAssertEqual(context.currentTab, .home)
        XCTAssertEqual(context.activeScanState, .none)
        XCTAssertNil(context.activeScanID)
        XCTAssertEqual(context.entryPoint, .homeMorningBrief)
        XCTAssertEqual(context.closetState, .unavailable)
    }

    @MainActor
    func testStylistServiceTransmitsScreenContextWithLatestPrompt() async throws {
        let transport = MockChatTransport(chunks: ["No active outfit is available."])
        let context = ChatContext(
            screenContext: StylistScreenContext(
                currentTab: .scan,
                activeScanState: .none,
                entryPoint: .scanTab,
                closetState: .loadedEmpty
            )
        )
        let service = StylistChatService(
            store: ChatConversationStore(fileURL: temporaryStoreURL()),
            transport: transport,
            contextProvider: { context }
        )

        XCTAssertTrue(service.send("Improve this score."))
        try await waitUntil { !service.isStreaming }

        XCTAssertEqual(transport.requests.last?.context.screenContext, context.screenContext)
        XCTAssertEqual(transport.requests.last?.messages.last?.content, "Improve this score.")
    }

    private func contextSelectionAnalysis(
        garments: [String],
        confidences: [DetectedItemConfidence],
        palette: [String] = ["navy"],
        breakdown: OutfitScoreBreakdown? = nil
    ) -> OutfitAnalysisResult {
        OutfitAnalysisResult(
            score: 80,
            scoreBreakdown: breakdown,
            colorMatch: "",
            occasionFit: "",
            styleBalance: "",
            colorHarmony: "",
            styleCoordination: "",
            formality: "",
            seasonalMatch: "",
            summary: "",
            outfitDescription: "",
            detectedClothingItems: garments,
            colorPalette: palette,
            environment: "",
            imageQuality: "",
            detectedItemConfidences: confidences,
            suggestions: [],
            recommendations: []
        )
    }

    private func temporaryStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("StyleMatchChatTests-\(UUID().uuidString)")
            .appendingPathExtension("json")
    }

    private func storeURL(from store: ChatConversationStore) -> URL {
        Mirror(reflecting: store).children.first { $0.label == "fileURL" }?.value as! URL
    }

    private func projectSource(_ relativePath: String, filePath: String = #filePath) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
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
    var authorizationState: StylistChatAuthorizationState

    init(
        chunks: [String],
        delayNanoseconds: UInt64 = 0,
        authorizationState: StylistChatAuthorizationState = .authorized
    ) {
        self.chunks = chunks
        self.delayNanoseconds = delayNanoseconds
        self.authorizationState = authorizationState
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

private final class NoNetworkURLProtocol: URLProtocol {
    static var requestCount = 0

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requestCount += 1
        client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
    }

    override func stopLoading() {}
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
