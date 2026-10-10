import XCTest
import CoreGraphics
import ImageIO
@testable import StyleMatchPro

final class StyleMatchRuntimeEndpointTests: XCTestCase {
    private let production = StylistChatConfiguration(
        baseURL: URL(string: "https://api.stylematchpro.com")!
    )

    func testDebugOverrideUsesPrivateLANHTTPURLForStylistButNotAccountAuthority() throws {
        let chatResolution = try XCTUnwrap(StyleMatchRuntimeEndpoint.chatResolution(
            defaultConfiguration: production,
            environment: [
                StyleMatchRuntimeEndpoint.overrideEnvironmentKey: "http://192.168.1.42:8787"
            ],
            allowsOverride: true
        ))
        let accountResolution = StyleMatchRuntimeEndpoint.accountResolution(
            defaultURL: production.baseURL,
            environment: [
                StyleMatchRuntimeEndpoint.overrideEnvironmentKey: "http://192.168.1.42:8787"
            ],
            allowsOverride: true
        )

        XCTAssertTrue(chatResolution.overrideActive)
        XCTAssertNil(accountResolution)
        XCTAssertEqual(chatResolution.baseURL.absoluteString, "http://192.168.1.42:8787")
    }

    func testDebugOverrideUsesExactApprovedStagingHTTPSURL() throws {
        let staging = "https://\(AppBackendConfiguration.approvedStagingAPIHost)"
        let environment = [StyleMatchRuntimeEndpoint.overrideEnvironmentKey: staging]
        let factory = StyleMatchLiveClientEndpointFactory(
            environment: environment,
            allowsOverride: true
        )

        XCTAssertEqual(factory.chatConfiguration?.baseURL.absoluteString, staging)
        XCTAssertEqual(factory.accountBaseURL?.absoluteString, staging)
        XCTAssertTrue(factory.chatResolution?.overrideActive == true)
        XCTAssertTrue(factory.accountResolution?.overrideActive == true)
    }

    func testDebugOverrideUsesExactFriendsAuthTestHTTPSURL() throws {
        let testURL = "https://\(AppBackendConfiguration.approvedFriendsAuthTestAPIHost)"
        let factory = StyleMatchLiveClientEndpointFactory(
            environment: [StyleMatchRuntimeEndpoint.overrideEnvironmentKey: testURL],
            allowsOverride: true
        )

        XCTAssertEqual(factory.chatConfiguration?.baseURL.absoluteString, testURL)
        XCTAssertEqual(factory.accountBaseURL?.absoluteString, testURL)
        XCTAssertTrue(factory.accountResolution?.overrideActive == true)
    }

    @MainActor
    func testActualLiveChatAndAccountConstructionUseApprovedDebugStagingRoute() throws {
        let staging = "https://\(AppBackendConfiguration.approvedStagingAPIHost)"
        let factory = StyleMatchLiveClientEndpointFactory(
            environment: [StyleMatchRuntimeEndpoint.overrideEnvironmentKey: staging],
            allowsOverride: true
        )
        let chatService = StylistChatService(endpointFactory: factory)
        let accountClient = StyleMatchAccountClient(endpointFactory: factory)

        XCTAssertEqual(chatService.resolvedTransportBaseURL?.absoluteString, staging)
        XCTAssertEqual(accountClient.resolvedBaseURL?.absoluteString, staging)
    }

    @MainActor
    func testActualLiveClientsDefaultToProductionWithoutDebugSelection() throws {
        let factory = StyleMatchLiveClientEndpointFactory(
            environment: [:],
            allowsOverride: true
        )

        XCTAssertEqual(
            StylistChatService(endpointFactory: factory).resolvedTransportBaseURL,
            production.baseURL
        )
        XCTAssertEqual(
            StyleMatchAccountClient(endpointFactory: factory).resolvedBaseURL,
            production.baseURL
        )
    }

    @MainActor
    func testReleaseLiveClientsIgnoreStagingSelectionAndRecreation() throws {
        let stagingEnvironment = [
            StyleMatchRuntimeEndpoint.overrideEnvironmentKey:
                "https://\(AppBackendConfiguration.approvedStagingAPIHost)"
        ]
        let factory = StyleMatchLiveClientEndpointFactory(
            environment: stagingEnvironment,
            allowsOverride: false
        )

        for _ in 0..<2 {
            XCTAssertEqual(
                StylistChatService(endpointFactory: factory).resolvedTransportBaseURL,
                production.baseURL
            )
            XCTAssertEqual(
                StyleMatchAccountClient(endpointFactory: factory).resolvedBaseURL,
                production.baseURL
            )
        }
    }

    @MainActor
    func testMalformedOverrideFailsClosedAtActualLiveClientConstruction() {
        let factory = StyleMatchLiveClientEndpointFactory(
            environment: [
                StyleMatchRuntimeEndpoint.overrideEnvironmentKey:
                    "https://\(AppBackendConfiguration.approvedStagingAPIHost).evil.example"
            ],
            allowsOverride: true
        )

        XCTAssertNil(StylistChatService(endpointFactory: factory).resolvedTransportBaseURL)
        XCTAssertNil(StyleMatchAccountClient(endpointFactory: factory).resolvedBaseURL)
    }

    @MainActor
    func testDebugStagingSelectionDoesNotAffectCatalogProductionAuthority() {
        let factory = StyleMatchLiveClientEndpointFactory(
            environment: [
                StyleMatchRuntimeEndpoint.overrideEnvironmentKey:
                    "https://\(AppBackendConfiguration.approvedStagingAPIHost)"
            ],
            allowsOverride: true
        )

        XCTAssertEqual(
            StylistChatService(endpointFactory: factory).resolvedTransportBaseURL?.host,
            AppBackendConfiguration.approvedStagingAPIHost
        )
        XCTAssertEqual(
            AppBackendConfiguration.production().apiBaseURL.host,
            AppBackendConfiguration.approvedProductionAPIHost
        )
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

    func testReleaseModeIgnoresFriendsAuthTestOverride() throws {
        let testURL = "https://\(AppBackendConfiguration.approvedFriendsAuthTestAPIHost)"
        let resolution = try XCTUnwrap(StyleMatchRuntimeEndpoint.accountResolution(
            defaultURL: production.baseURL,
            environment: [StyleMatchRuntimeEndpoint.overrideEnvironmentKey: testURL],
            allowsOverride: false
        ))

        XCTAssertFalse(resolution.overrideActive)
        XCTAssertEqual(resolution.baseURL, production.baseURL)
    }

    func testDebugOverrideRejectsMalformedPublicOrUnscopedHosts() {
        for rawValue in [
            "not a URL",
            "http://example.com:8787",
            "http://192.168.1.42",
            "http://192.168.1.42:8787/v1/chat",
            "https://stylematch-affiliate-proxy-staging.sabastine-7000.workers.dev.evil.example",
            "https://preview.stylematch-affiliate-proxy-staging.sabastine-7000.workers.dev"
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

    func testApprovedStagingTransportKeepsCanonicalRetainedDataScope() throws {
        let suiteName = "StyleMatchRuntimeEndpointTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("production", forKey: AccountScopedStorage.activeEnvironmentMarkerKey)
        let retainedValues: [String: Any] = [
            "profileName": "keep-profile",
            "weatherCondition": "keep-weather",
            "closetItemsData": Data("keep-closet".utf8),
            "outfitScanHistoryData": Data("keep-scans".utf8),
            "aiStylistConversationData": Data("keep-conversations".utf8)
        ]
        retainedValues.forEach { defaults.set($0.value, forKey: $0.key) }

        let composition = StyleMatchApplicationComposition(
            environment: [
                StyleMatchRuntimeEndpoint.overrideEnvironmentKey:
                    "https://\(AppBackendConfiguration.approvedStagingAPIHost)"
            ],
            allowsTransportOverride: true,
            defaults: defaults
        )

        XCTAssertEqual(
            composition.liveClientEndpoints.chatConfiguration?.baseURL.host,
            AppBackendConfiguration.approvedStagingAPIHost
        )
        XCTAssertEqual(composition.retainedData.environment, .production)
        XCTAssertFalse(composition.retainedData.prepareForLaunch())
        XCTAssertEqual(defaults.string(forKey: AccountScopedStorage.activeEnvironmentMarkerKey), "production")
        for (key, expectedValue) in retainedValues {
            switch expectedValue {
            case let value as String:
                XCTAssertEqual(defaults.string(forKey: key), value, key)
            case let value as Data:
                XCTAssertEqual(defaults.data(forKey: key), value, key)
            default:
                XCTFail("Unsupported retained fixture type for \(key)")
            }
        }
        XCTAssertFalse(
            defaults.dictionaryRepresentation().keys.contains {
                $0.contains(AccountStorageEnvironment.localAcceptance.rawValue)
            }
        )
        XCTAssertEqual(
            defaults.integer(forKey: AccountScopedStorage.migrationVersionKey),
            AccountScopedStorage.currentMigrationVersion
        )
    }

    func testPrivateLANTransportKeepsCanonicalRetainedDataScope() {
        let suiteName = "StyleMatchRuntimeEndpointTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let composition = StyleMatchApplicationComposition(
            environment: [
                StyleMatchRuntimeEndpoint.overrideEnvironmentKey: "http://10.0.0.25:8787"
            ],
            allowsTransportOverride: true,
            defaults: defaults
        )

        XCTAssertEqual(
            composition.liveClientEndpoints.chatConfiguration?.baseURL.absoluteString,
            "http://10.0.0.25:8787"
        )
        XCTAssertEqual(composition.retainedData.environment, .production)
    }

    func testMalformedTransportOverrideFailsClosedWithoutChangingCanonicalStorage() {
        let suiteName = "StyleMatchRuntimeEndpointTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("production", forKey: AccountScopedStorage.activeEnvironmentMarkerKey)
        defaults.set("keep-me", forKey: "weatherCondition")

        let composition = StyleMatchApplicationComposition(
            environment: [
                StyleMatchRuntimeEndpoint.overrideEnvironmentKey:
                    "https://\(AppBackendConfiguration.approvedStagingAPIHost).evil.example"
            ],
            allowsTransportOverride: true,
            defaults: defaults
        )

        XCTAssertNil(composition.liveClientEndpoints.chatConfiguration)
        XCTAssertNil(composition.liveClientEndpoints.accountBaseURL)
        XCTAssertEqual(composition.retainedData.environment, .production)
        XCTAssertFalse(composition.retainedData.prepareForLaunch())
        XCTAssertEqual(defaults.string(forKey: "weatherCondition"), "keep-me")
        XCTAssertEqual(
            defaults.string(forKey: AccountScopedStorage.activeEnvironmentMarkerKey),
            AccountStorageEnvironment.production.rawValue
        )
    }

    func testReleaseCompositionIgnoresTransportOverrideAndUsesCanonicalStorage() {
        let composition = StyleMatchApplicationComposition(
            environment: [
                StyleMatchRuntimeEndpoint.overrideEnvironmentKey:
                    "https://\(AppBackendConfiguration.approvedStagingAPIHost)"
            ],
            allowsTransportOverride: false
        )

        XCTAssertEqual(
            composition.liveClientEndpoints.chatConfiguration?.baseURL,
            production.baseURL
        )
        XCTAssertEqual(composition.retainedData.environment, .production)
    }

    func testRetainedDataCompositionConstructsActualStoresWithoutTransportDependency() {
        let suiteName = "StyleMatchRuntimeEndpointTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let conversationURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(suiteName).json")
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: conversationURL)
            try? FileManager.default.removeItem(
                at: conversationURL.deletingLastPathComponent()
                    .appendingPathComponent("\(conversationURL.lastPathComponent).bak")
            )
        }

        let composition = StyleMatchApplicationComposition(
            environment: [
                StyleMatchRuntimeEndpoint.overrideEnvironmentKey:
                    "https://\(AppBackendConfiguration.approvedStagingAPIHost)"
            ],
            allowsTransportOverride: true,
            defaults: defaults
        )

        XCTAssertNotNil(composition.retainedData.makeProfileStore(userID: "fixture-user"))
        XCTAssertNotNil(composition.retainedData.makeOutfitMemoryStore(userID: "fixture-user"))
        XCTAssertNotNil(
            composition.retainedData.makeChatConversationStore(
                fileURL: conversationURL,
                userID: "fixture-user"
            )
        )
        XCTAssertEqual(composition.retainedData.environment, .production)
    }

    func testLocalAcceptanceStorageRequiresExplicitInjection() {
        let suiteName = "StyleMatchRuntimeEndpointTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let retainedData = StyleMatchRetainedDataComposition(
            defaults: defaults,
            environment: .localAcceptance
        )
        _ = retainedData.prepareForLaunch()

        XCTAssertEqual(
            defaults.string(forKey: AccountScopedStorage.activeEnvironmentMarkerKey),
            AccountStorageEnvironment.localAcceptance.rawValue
        )
    }
}

final class StylistConversationContextTests: XCTestCase {
    private func snapshot(
        score: Int? = 80,
        selectedOccasion: String? = "Work",
        workplace: WorkplaceContext = .unknown,
        weather: StylistWeatherContext? = nil
    ) -> StylistConversationSnapshot {
        StylistConversationSnapshot(
            scanID: "scan-current",
            score: score,
            breakdown: StylistScoreBreakdownSnapshot(
                colorHarmony: 25,
                patternBalance: 20,
                fitQuality: 13,
                occasionMatch: 10,
                accessoryUse: 6
            ),
            detectedStyle: "Casual",
            selectedOccasion: selectedOccasion,
            observedGarments: ["polo shirt", "pants"],
            observedColors: ["black", "royal blue"],
            weather: weather,
            workplace: workplace
        )
    }

    func testIntentRouterSeparatesFootwearWorkplaceLatestScoreAndTomorrow() {
        XCTAssertEqual(StylistConversationRouter.classify("What shoes match?"), .footwear)
        XCTAssertEqual(StylistConversationRouter.classify("Dress me for work."), .workplace)
        XCTAssertEqual(StylistConversationRouter.classify("What was my latest score?"), .latestScore)
        XCTAssertEqual(StylistConversationRouter.classify("Can you see my score?"), .latestScore)
        XCTAssertEqual(StylistConversationRouter.classify("How did I do?"), .latestScore)
        XCTAssertEqual(StylistConversationRouter.classify("What should I wear tomorrow?"), .futureOrTomorrow)
    }

    func testUnknownWorkplaceFailsClosedBeforeFootwearRecommendation() {
        let result = StylistConversationRouter.preflight(
            message: "What shoes match for work?",
            snapshot: snapshot(),
            state: StylistConversationState()
        )

        XCTAssertEqual(result.intent, .footwear)
        XCTAssertEqual(result.semanticResponseID, .workplaceSafetyClarification)
        XCTAssertTrue(result.localReply?.contains("safety shoes or PPE") == true)
        XCTAssertFalse(result.localReply?.localizedCaseInsensitiveContains("sneakers") == true)
        XCTAssertFalse(result.localReply?.localizedCaseInsensitiveContains("loafers") == true)
    }

    func testRepeatedWorkplaceClarificationUsesStructuredSemanticState() {
        var state = StylistConversationState()
        state.emittedSemanticResponses.insert(.workplaceSafetyClarification)

        let result = StylistConversationRouter.preflight(
            message: "Dress me for work.",
            snapshot: snapshot(),
            state: state
        )

        XCTAssertEqual(result.semanticResponseID, .workplaceSafetyClarification)
        XCTAssertTrue(result.localReply?.hasPrefix("I still need") == true)
    }

    func testExplicitThreadWorkplaceCorrectionOverridesUnknownScanContext() {
        var state = StylistConversationState()
        state.applyExplicitWorkplaceDetails(
            from: "I work in a factory and need steel toe, slip resistant shoes."
        )

        XCTAssertEqual(state.workplaceOverride?.environment, .factoryOrManufacturing)
        XCTAssertEqual(state.workplaceOverride?.confirmation, .userConfirmed)
        XCTAssertEqual(
            state.workplaceOverride?.footwearConstraints,
            [.safetyToe, .slipResistant]
        )

        let result = StylistConversationRouter.preflight(
            message: "What shoes match for work?",
            snapshot: snapshot(),
            state: state
        )
        XCTAssertNil(result.localReply)
    }

    func testCurrentThreadReconstructionRequiresExplicitCorrectiveWorkplaceEvidence() {
        let incidental = StylistConversationState.reconstructing(messages: [
            ChatMessage(role: .user, content: "Would this work in an office?")
        ])
        let hypothetical = StylistConversationState.reconstructing(messages: [
            ChatMessage(role: .user, content: "If I work in a warehouse, would these shoes be okay?")
        ])
        let assistantAuthored = StylistConversationState.reconstructing(messages: [
            ChatMessage(role: .assistant, content: "You work in a factory.")
        ])
        let confirmed = StylistConversationState.reconstructing(messages: [
            ChatMessage(role: .user, content: "I work in a factory and need steel toe shoes.")
        ])

        XCTAssertNil(incidental.intelligenceThreadCorrection)
        XCTAssertNil(hypothetical.intelligenceThreadCorrection)
        XCTAssertNil(assistantAuthored.intelligenceThreadCorrection)
        XCTAssertEqual(confirmed.intelligenceThreadCorrection?.workplace?.environment, .factoryOrManufacturing)
        XCTAssertTrue(confirmed.intelligenceThreadCorrection?.workplace?.footwearConstraints.contains(.safetyToe) == true)
    }

    func testClarificationSemanticStateIsReconstructedOnlyWithinItsConversation() {
        let firstThread = StylistConversationState.reconstructing(messages: [
            ChatMessage(
                role: .assistant,
                content: "What kind of workplace is this for?",
                localSemanticResponseID: .workplaceSafetyClarification
            )
        ])
        let secondThread = StylistConversationState.reconstructing(messages: [])

        XCTAssertTrue(firstThread.emittedSemanticResponses.contains(.workplaceSafetyClarification))
        XCTAssertFalse(secondThread.emittedSemanticResponses.contains(.workplaceSafetyClarification))
    }

    func testLatestScoreReturnsExactAuthoritativeValue() {
        let result = StylistConversationRouter.preflight(
            message: "What was my score now?",
            snapshot: snapshot(score: 80),
            state: StylistConversationState()
        )

        XCTAssertEqual(result.localReply, "Your latest completed KigoStylist scan scored 80/100 — Good Match.")
    }

    func testWeakestAreaUsesRealBreakdown() {
        let result = StylistConversationRouter.preflight(
            message: "What is my weakest area?",
            snapshot: snapshot(),
            state: StylistConversationState()
        )

        XCTAssertEqual(
            result.localReply,
            "Your lowest scored area in this scan is fit at 13/25."
        )
    }

    func testTomorrowDoesNotReuseCurrentWeather() {
        let currentWeather = StylistWeatherContext(
            target: .current,
            condition: "clear",
            temperatureFahrenheit: 87,
            observedAt: Date(),
            validUntil: Date().addingTimeInterval(3_600)
        )
        let result = StylistConversationRouter.preflight(
            message: "Dress me for work tomorrow.",
            snapshot: snapshot(weather: currentWeather),
            state: StylistConversationState()
        )

        XCTAssertEqual(result.semanticResponseID, .tomorrowWeatherUnavailable)
        XCTAssertTrue(result.localReply?.contains("will not reuse today’s weather") == true)
    }

    func testAuthoritativeScanAdapterSuppressesPreciseWeatherLocation() throws {
        let scan = StylistAuthoritativeScanContext(
            scanID: "scan-80",
            completedAt: Date(),
            overallScore: 80,
            scoreBreakdown: nil,
            detectedStyle: "Casual",
            selectedOccasion: "Work",
            weatherContext: "Clear, 87°F in Fortson",
            source: .latestCompleted
        )

        let context = StylistConversationSnapshot.from(scan)
        XCTAssertEqual(context.weather?.condition, "clear")
        XCTAssertEqual(context.weather?.temperatureFahrenheit, 87)

        let request = try AIInsightChatPromptBuilder.build(
            displayedMessages: [],
            latestQuestion: "What should I wear?",
            cardFacts: AIInsightChatCardFacts(
                screen: "Scan",
                title: "AI Stylist",
                featurePrompt: "Explain this scan.",
                extraContext: "",
                snapshot: context
            )
        )
        XCTAssertFalse(request.primaryMessage.localizedCaseInsensitiveContains("Fortson"))
        XCTAssertTrue(request.primaryMessage.contains("temperature=87F"))
    }

    func testPromptCarriesTypedIntentAndWorkplaceContext() throws {
        let workplace = WorkplaceContext(
            environment: .warehouseOrDistribution,
            dressCode: .safetyWorkwear,
            footwearConstraints: [.closedToe, .safetyToe],
            ppeRequirements: [],
            activityLevel: .mostlyStandingOrWalking,
            exposure: .indoorVariableTemperature,
            floorAndOfficeMix: false,
            source: .explicitThreadCorrection,
            confirmation: .userConfirmed,
            lastConfirmedAt: Date()
        )
        let request = try AIInsightChatPromptBuilder.build(
            displayedMessages: [],
            latestQuestion: "What shoes match?",
            cardFacts: AIInsightChatCardFacts(
                screen: "Scan",
                title: "AI Stylist",
                featurePrompt: "Answer this scan question.",
                extraContext: "",
                snapshot: snapshot(workplace: workplace)
            )
        )

        XCTAssertTrue(request.primaryMessage.contains("Typed query intent: footwear"))
        XCTAssertTrue(request.primaryMessage.contains("warehouseOrDistribution"))
        XCTAssertTrue(request.primaryMessage.contains("safetyToe"))
        XCTAssertTrue(request.primaryMessage.contains("Hard workplace safety constraints override style"))
    }

    func testEncodedSnapshotContainsNoIdentityOrPreciseLocationFields() throws {
        let encoded = try JSONEncoder().encode(snapshot())
        let text = try XCTUnwrap(String(data: encoded, encoding: .utf8)?.lowercased())

        XCTAssertFalse(text.contains("employer"))
        XCTAssertFalse(text.contains("wearer"))
        XCTAssertFalse(text.contains("occupation"))
        XCTAssertFalse(text.contains("city"))
        XCTAssertFalse(text.contains("location"))
        XCTAssertFalse(text.contains("name"))
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
    func testLocalWorkplaceClarificationDoesNotReachTransportAndPersistsSemanticIdentity() {
        let store = ChatConversationStore(fileURL: temporaryStoreURL())
        let transport = MockChatTransport(chunks: ["unexpected"])
        let service = StylistChatService(store: store, transport: transport, contextProvider: { ChatContext() })

        XCTAssertTrue(service.send("Dress me for work."))
        XCTAssertTrue(transport.requests.isEmpty)
        XCTAssertEqual(service.activeConversation.messages.map(\.role), [.user, .assistant])
        XCTAssertEqual(
            service.activeConversation.messages.last?.localSemanticResponseID,
            .workplaceSafetyClarification
        )

        XCTAssertTrue(service.send("I need a work outfit."))
        XCTAssertTrue(transport.requests.isEmpty)
        XCTAssertTrue(service.activeConversation.messages.last?.content.hasPrefix("I still need") == true)
    }

    @MainActor
    func testOrchestratedWorkplaceClarificationRemainsLocalAfterAIMemoryResolution() {
        let store = ChatConversationStore(fileURL: temporaryStoreURL())
        let transport = MockChatTransport(chunks: ["unexpected"])
        let service = StylistChatService(store: store, transport: transport, contextProvider: { ChatContext() })
        let snapshot = StylistIntelligenceSnapshotBuilder.build(
            StylistIntelligenceSnapshotInput(conversationScope: .generalStylist)
        )

        XCTAssertTrue(
            service.send(
                "Dress me for work.",
                forcedContext: snapshot.networkSafeContext(applying: ChatContext()),
                intelligenceSnapshot: snapshot
            )
        )

        XCTAssertTrue(transport.requests.isEmpty)
        XCTAssertEqual(
            service.activeConversation.messages.last?.localSemanticResponseID,
            .workplaceSafetyClarification
        )
    }

    @MainActor
    func testLocalSemanticMetadataNeverSerializesToWorkerRequest() async throws {
        let store = ChatConversationStore(fileURL: temporaryStoreURL())
        let transport = MockChatTransport(chunks: ["done"])
        let service = StylistChatService(store: store, transport: transport, contextProvider: { ChatContext() })

        XCTAssertTrue(service.send("Dress me for work."))
        XCTAssertTrue(service.send("What color shirt works?"))
        try await waitUntil { !service.isStreaming }

        let request = try XCTUnwrap(transport.requests.last)
        let encoded = try JSONEncoder().encode(request)
        let text = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        XCTAssertFalse(text.contains("localSemanticResponseID"))
        XCTAssertFalse(text.contains("workplaceSafetyClarification"))
    }

    @MainActor
    func testExplicitCurrentThreadCorrectionSendsOnceWithoutWorkplaceClarification() async throws {
        let transport = MockChatTransport(chunks: ["Try safety-toe boots."])
        let service = StylistChatService(
            store: ChatConversationStore(fileURL: temporaryStoreURL()),
            transport: transport,
            contextProvider: { ChatContext() }
        )

        XCTAssertTrue(service.send("I work in a factory and need steel toe shoes. What should I wear for work?"))
        try await waitUntil { !service.isStreaming }

        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertFalse(service.activeConversation.messages.contains {
            $0.localSemanticResponseID == .workplaceSafetyClarification
        })
    }

    @MainActor
    func testNewGeneralConversationDoesNotInheritPriorClarificationSuppression() {
        let transport = MockChatTransport(chunks: [])
        let service = StylistChatService(
            store: ChatConversationStore(fileURL: temporaryStoreURL()),
            transport: transport,
            contextProvider: { ChatContext() }
        )

        XCTAssertTrue(service.send("Dress me for work."))
        XCTAssertTrue(service.activeConversation.messages.last?.content.hasPrefix("What kind of workplace") == true)
        service.newChat()

        XCTAssertTrue(service.send("Dress me for work."))
        XCTAssertTrue(service.activeConversation.messages.last?.content.hasPrefix("What kind of workplace") == true)
        XCTAssertTrue(transport.requests.isEmpty)
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

    func testHTTP413RetainsOnlyBoundedStructuredDiagnostics() throws {
        let endpoint = try XCTUnwrap(URL(string: "https://api.stylematchpro.com/v1/chat"))
        let response = try XCTUnwrap(HTTPURLResponse(
            url: endpoint,
            statusCode: 413,
            httpVersion: "HTTP/2",
            headerFields: ["CF-Ray": "request-413-ATL"]
        ))
        let diagnostic = LiveChatTransport.diagnosticError(forHTTPResponse: response)

        XCTAssertEqual(diagnostic.category, .payloadTooLarge)
        XCTAssertEqual(diagnostic.statusCode, 413)
        XCTAssertEqual(diagnostic.requestPhase, .response)
        XCTAssertFalse(diagnostic.debugDescription.contains("request-413-ATL"))
        XCTAssertFalse(diagnostic.debugDescription.contains(endpoint.absoluteString))
        XCTAssertFalse(diagnostic.debugDescription.contains("payload_too_large"))
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

    func testAITransmissionConsentDefaultsToUndecidedAndPersistsExplicitDecision() {
        let suiteName = "AITransmissionConsentDefaults-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = AITransmissionConsentStore(defaults: defaults, userIDProvider: { "test-user" })
        XCTAssertEqual(store.state, .undecided)
        store.accept()
        XCTAssertEqual(store.state, .accepted)
        XCTAssertEqual(
            AITransmissionConsentStore(defaults: defaults, userIDProvider: { "test-user" }).state,
            .accepted
        )
        store.revoke()
        XCTAssertEqual(store.state, .declined)
    }

    func testAITransmissionConsentVersionChangeRequiresNewDecision() {
        let suiteName = "AITransmissionConsentVersion-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let v1 = AITransmissionConsentStore(
            defaults: defaults,
            userIDProvider: { "test-user" },
            disclosureVersion: "v1"
        )
        v1.accept()
        XCTAssertEqual(v1.state, .accepted)
        XCTAssertEqual(
            AITransmissionConsentStore(
                defaults: defaults,
                userIDProvider: { "test-user" },
                disclosureVersion: "v2"
            ).state,
            .undecided
        )
    }

    func testAITransmissionDisclosureNamesVerifiedProcessorsAndBoundedDataContract() throws {
        let disclosure = try projectSource("StyleMatchAI/StylistChat/StylistChatView.swift")
        let transport = try projectSource("StyleMatchAI/StylistChat/StylistChatTransport.swift")

        XCTAssertTrue(disclosure.contains("Cloudflare-hosted API"))
        XCTAssertTrue(disclosure.contains("OpenAI, the downstream AI processor"))
        XCTAssertTrue(disclosure.contains("generate the AI Stylist response you requested"))
        XCTAssertTrue(disclosure.contains("preference or profile summary, selected scan or outfit details, and score breakdown information"))
        XCTAssertTrue(disclosure.contains("raw photos or image bytes, screenshots, precise location, local database IDs, or internal route metadata"))
        XCTAssertTrue(disclosure.contains("Agree & Continue records your acceptance of the current AI-processing consent"))
        XCTAssertTrue(disclosure.contains("Not Now sends no AI request"))
        XCTAssertTrue(disclosure.contains("Profile → Your Privacy → AI Processing Consent"))
        XCTAssertTrue(disclosure.contains("Recording consent…"))
        XCTAssertTrue(disclosure.contains("Button(\"Not Now\", role: .cancel)"))
        XCTAssertTrue(disclosure.contains("recordCurrentConsent"))
        XCTAssertTrue(transport.contains("static let disclosureVersion = \"2026-08-13.ai-processing.v3\""))
        XCTAssertTrue(transport.contains("v1/account/ai-processing-consent"))
        XCTAssertTrue(transport.contains("case 403: .aiTransmissionConsentRequired"))
        XCTAssertFalse(disclosure.contains("Product Context"))
    }

    func testCurrentAIProcessingConsentIsDiscoverableAndFailsClosedUntilServerRecordsIt() throws {
        let chat = try projectSource("StyleMatchAI/StylistChat/StylistChatView.swift")
        let profile = try projectSource("StyleMatchAI/ProfileView.swift")
        let transport = try projectSource("StyleMatchAI/StylistChat/StylistChatTransport.swift")

        XCTAssertTrue(chat.contains("Review AI Consent"))
        XCTAssertTrue(chat.contains("recordCurrentAIProcessingConsent"))
        XCTAssertTrue(chat.contains("AIProcessingConsentService().acceptCurrentConsent()"))
        XCTAssertTrue(chat.contains("We could not record your AI consent. Please try again."))
        XCTAssertTrue(profile.contains("AI Processing Consent"))
        XCTAssertTrue(profile.contains("Review AI Processing Consent"))
        XCTAssertTrue(transport.contains("guard accepted.valid"))
        XCTAssertTrue(transport.contains("AIProcessingConsentServiceError.unavailable"))
    }

    func testAIConsentAndScopedPermissionRequestsUseBoundedNetworkTimeouts() throws {
        let transport = try projectSource("StyleMatchAI/StylistChat/StylistChatTransport.swift")

        XCTAssertTrue(transport.contains("enum AIConsentNetworkPolicy"))
        XCTAssertTrue(transport.contains("static let requestTimeout: TimeInterval = 15"))
        XCTAssertEqual(transport.components(separatedBy: "request.timeoutInterval = AIConsentNetworkPolicy.requestTimeout").count - 1, 2)
    }

    func testScopedFactConsentDefaultsToWorkerAuthorityAndNeverCarriesAccountOrFacts() throws {
        let chat = try projectSource("StyleMatchAI/StylistChat/StylistChatView.swift")
        let transport = try projectSource("StyleMatchAI/StylistChat/StylistChatTransport.swift")

        XCTAssertTrue(chat.contains("scopedConsentStates: [AIScopedConsentScope: AIScopedConsentState] = [:]"))
        XCTAssertTrue(chat.contains("resolvingSelectedFactContextForSend"))
        XCTAssertTrue(chat.contains("case .noneSelected:"))
        XCTAssertTrue(chat.contains("case let .resolved(selectedFactContext):"))
        XCTAssertTrue(chat.contains("Remove selected saved scan"))
        XCTAssertTrue(chat.contains("Remove selected Closet item"))
        XCTAssertTrue(chat.contains("PersonalizationContextBuilder.maximumSavedScans"))
        XCTAssertTrue(chat.contains("PersonalizationContextBuilder.maximumClosetItems"))
        XCTAssertTrue(chat.contains("clearFactSelections()"))
        XCTAssertTrue(transport.contains("v1/account/ai-scopes"))
        XCTAssertTrue(transport.contains("guard states.count == AIScopedConsentScope.allCases.count"))
        XCTAssertFalse(transport.contains("account_id"))
        XCTAssertFalse(transport.contains("localRecordKey"))

        let builder = try projectSource("StyleMatchAI/PersonalStylist/StylistContextBuilder.swift")
        XCTAssertTrue(builder.contains("typealias PersonalizationContextBuilder = StylistContextBuilder"))
        XCTAssertTrue(builder.contains("maximumFactContextBytes"))
        XCTAssertTrue(builder.contains("ISO8601DateFormatter"))
        XCTAssertFalse(transport.contains("data_base64"))
    }

    /// The routing decision must be based on the currently selected canonical
    /// attachment snapshot. This initially characterizes the owner-observed
    /// regression: the view had no selected-scope consent route at all.
    func testSelectedAttachmentConsentRoutesToItsMatchingPermission() throws {
        let chat = try projectSource("StyleMatchAI/StylistChat/StylistChatView.swift")
        let transport = try projectSource("StyleMatchAI/StylistChat/StylistChatTransport.swift")

        XCTAssertTrue(chat.contains("missingScopedConsent"))
        XCTAssertTrue(chat.contains("scope.allowAccessibilityLabel"))
        XCTAssertTrue(transport.contains("Allow Saved Scan Facts"))
        XCTAssertTrue(transport.contains("Allow Selected Closet Items"))
        XCTAssertTrue(transport.contains("Allow Style Preferences"))
        XCTAssertTrue(transport.contains("Allow Selected Image"))
    }

    /// A grant is only locally usable after the Worker-owned state is read
    /// again. Keeping this as a separate test prevents a matching UI label
    /// from being mistaken for authoritative consent recovery.
    func testSelectedAttachmentConsentGrantReloadsAuthoritativeStateBeforeSend() throws {
        let chat = try projectSource("StyleMatchAI/StylistChat/StylistChatView.swift")

        XCTAssertTrue(chat.contains("try await service.currentStates()"))
        XCTAssertTrue(chat.contains("isMutatingScopedConsent"))
        XCTAssertTrue(chat.contains("scopedConsentSheet = nil"))
        XCTAssertTrue(chat.contains(".disabled(isMutatingScopedConsent)"))
        XCTAssertTrue(chat.contains("refreshScopedConsent()"))
        XCTAssertTrue(chat.contains("scopedConsentStates = [:]"))
        XCTAssertTrue(chat.contains("grantScopedConsent(scope)"))
    }

    /// Scope isolation is essential: a style-preference grant must never make
    /// a selected scan, Closet item, or image sendable.
    func testSelectedAttachmentConsentNeverUsesWrongScopeAsAuthorization() throws {
        let chat = try projectSource("StyleMatchAI/StylistChat/StylistChatView.swift")

        XCTAssertTrue(chat.contains("StylistScopedConsentRouter.requiredScopes(for: currentConsentAttachmentSnapshot)"))
        XCTAssertTrue(chat.contains("StylistScopedConsentRouter.missingScopes(from: requiredScopes"))
    }

    func testSelectedAttachmentConsentScopeRoutingUsesOnlyCurrentAttachmentSnapshot() {
        let none = StylistScopedConsentAttachmentSnapshot(
            selectedImage: false, selectedScanFacts: false, stylePreferences: false, selectedClosetItems: false
        )
        XCTAssertEqual(StylistScopedConsentRouter.requiredScopes(for: none), [])

        let cases: [(StylistScopedConsentAttachmentSnapshot, [AIScopedConsentScope])] = [
            (.init(selectedImage: false, selectedScanFacts: true, stylePreferences: false, selectedClosetItems: false), [.selectedScanFacts]),
            (.init(selectedImage: false, selectedScanFacts: false, stylePreferences: false, selectedClosetItems: true), [.selectedClosetItems]),
            (.init(selectedImage: false, selectedScanFacts: false, stylePreferences: true, selectedClosetItems: false), [.stylePreferences]),
            (.init(selectedImage: true, selectedScanFacts: false, stylePreferences: false, selectedClosetItems: false), [.selectedImage]),
            (.init(selectedImage: true, selectedScanFacts: true, stylePreferences: true, selectedClosetItems: true), [.selectedImage, .selectedScanFacts, .stylePreferences, .selectedClosetItems])
        ]
        for (snapshot, expected) in cases {
            XCTAssertEqual(StylistScopedConsentRouter.requiredScopes(for: snapshot), expected)
        }

        let grantedScan = AIScopedConsentState(scope: .selectedScanFacts, granted: true, revision: 3)
        let missing = StylistScopedConsentRouter.missingScopes(
            from: [.selectedScanFacts, .selectedClosetItems],
            states: [.selectedScanFacts: grantedScan]
        )
        XCTAssertEqual(missing, [.selectedClosetItems])
    }

    func testScopedFactConsentLoadsAndMutatesOnlyThroughAuthenticatedWorkerAPI() async throws {
        ScopedConsentURLProtocol.reset([
            .init(status: 200, body: """
            {"scopes":[
              {"scope":"selected_image","granted":false,"revision":0},
              {"scope":"selected_scan_facts","granted":false,"revision":0},
              {"scope":"style_preferences","granted":false,"revision":0},
              {"scope":"selected_closet_items","granted":true,"revision":4}
            ]}
            """),
            .init(status: 200, body: "{\"scope\":\"selected_scan_facts\",\"granted\":true,\"revision\":1}"),
            .init(status: 204, body: "")
        ])
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ScopedConsentURLProtocol.self]
        let service = AIScopedConsentService(
            baseURL: URL(string: "https://worker.example")!,
            session: URLSession(configuration: configuration),
            accountSession: { StyleMatchAccountSession(token: "test-session", expiresAt: .distantFuture) }
        )

        let states = try await service.currentStates()
        XCTAssertEqual(states[.selectedScanFacts]?.granted, false)
        XCTAssertEqual(states[.selectedClosetItems]?.revision, 4)
        let granted = try await service.grant(.selectedScanFacts, expectedRevision: 0)
        XCTAssertEqual(granted.revision, 1)
        try await service.revoke(.selectedClosetItems)

        XCTAssertEqual(ScopedConsentURLProtocol.requests.map(\.httpMethod), ["GET", "POST", "DELETE"])
        XCTAssertTrue(ScopedConsentURLProtocol.requests.allSatisfy { $0.url?.path == "/v1/account/ai-scopes" })
        XCTAssertTrue(ScopedConsentURLProtocol.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer test-session" })
        XCTAssertEqual(ScopedConsentURLProtocol.requests[1].value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    func testUndecidedAndDeclinedAITransmissionNeverReachNetwork() async throws {
        for state in [AITransmissionConsentState.undecided, .declined] {
            NoNetworkURLProtocol.requestCount = 0
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [NoNetworkURLProtocol.self]
            let session = URLSession(configuration: configuration)
            let transport = LiveChatTransport(
                configuration: StylistChatConfiguration(baseURL: URL(string: "https://api.stylematchpro.com")!),
                session: session,
                accountSession: { StyleMatchAccountSession(token: "test", expiresAt: .distantFuture) },
                consentState: { state }
            )

            do {
                for try await _ in transport.send(Self.consentRequest) {}
                XCTFail("Expected consent gate to fail closed for \(state).")
            } catch {
                XCTAssertEqual(error as? StylistChatError, .aiTransmissionConsentRequired)
            }
            XCTAssertEqual(NoNetworkURLProtocol.requestCount, 0, "\(state) must not start a network request")
        }
    }

    func testAcceptedAITransmissionReachesSharedTransport() async throws {
        NoNetworkURLProtocol.requestCount = 0
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NoNetworkURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let transport = LiveChatTransport(
            configuration: StylistChatConfiguration(baseURL: URL(string: "https://api.stylematchpro.com")!),
            session: session,
            accountSession: { StyleMatchAccountSession(token: "test", expiresAt: .distantFuture) },
            consentState: { .accepted }
        )

        do {
            for try await _ in transport.send(Self.consentRequest) {}
            XCTFail("The test URL protocol should end the request.")
        } catch {
            XCTAssertNotEqual(error as? StylistChatError, .aiTransmissionConsentRequired)
        }
        XCTAssertEqual(NoNetworkURLProtocol.requestCount, 1)
    }

    private static let consentRequest = ChatRequest(
        messages: [ChatRequest.RequestMessage(role: "user", content: "Help with this outfit")],
        context: ChatContext(productContext: try! JSONDecoder().decode(
            StylistProductContext.self,
            from: Data("""
            {"version":1,"relationship":"considering","name":"Navy Performance Polo","category":"clothing"}
            """.utf8)
        )),
        stream: true
    )

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

    func testReadAloudRemainsPresentationOnlyAndOutsideChatTransport() throws {
        let chatView = try projectSource("StyleMatchAI/StylistChat/StylistChatView.swift")
        let service = try projectSource("StyleMatchAI/StylistChat/StylistChatService.swift")

        XCTAssertTrue(chatView.contains("private func listen(to message: ChatMessage)"))
        XCTAssertTrue(chatView.contains("private func stopReadingResponse()"))
        XCTAssertTrue(chatView.contains("voiceAssistant.stop()"))
        XCTAssertFalse(chatView.contains("store.save("))
        XCTAssertFalse(service.contains("voiceAssistant"))
        XCTAssertFalse(service.contains("localSemanticResponseID: .readAloud"))
    }

    @MainActor
    func testScanCombinationRequestUsesScanFactsOnlyAndNoOwnershipClaim() async throws {
        let suiteName = "ScanCombinationSavedScan-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(
            try JSONSerialization.data(withJSONObject: ["scan-combination": [:]]),
            forKey: "outfitScanHistoryData"
        )
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
        let authoritative = StylistAuthoritativeScanContext(
            scanID: "scan-combination",
            completedAt: Date(timeIntervalSince1970: 1_000),
            overallScore: 78,
            scoreBreakdown: nil,
            detectedStyle: "Smart Casual",
            source: .savedSelection,
            palette: ["light blue", "tan"],
            evidenceLimitations: ["Slightly blurry"],
            outfitType: "striped shirt"
        )
        let scanContext = PersonalizationContextBuilder.scanStylistContext(
            for: analysis,
            authoritativeScan: authoritative
        )
        let store = ChatConversationStore(fileURL: temporaryStoreURL())
        let transport = MockChatTransport(chunks: ["From this scan: keep the shirt."])
        let service = StylistChatService(
            store: store,
            transport: transport,
            memoryDefaults: defaults
        )
        service.openOrCreateScanConversation(context: scanContext)

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
        XCTAssertTrue(payload.contains("score 78/100"))
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
    func testExplicitRetryReusesFailedQuestionWithoutDuplicatingIt() async throws {
        let transport = FailOnceChatTransport(response: "Try a cream shirt with brown pants.")
        let service = StylistChatService(
            store: ChatConversationStore(fileURL: temporaryStoreURL()),
            transport: transport,
            contextProvider: { ChatContext() }
        )

        XCTAssertTrue(service.send("What goes well with brown pants?"))
        try await waitUntil { !service.isStreaming }
        XCTAssertTrue(service.canRetryLastFailedSend)
        XCTAssertEqual(service.activeConversation.messages.map(\.content), ["What goes well with brown pants?"])

        XCTAssertTrue(service.retryLastFailedSend())
        try await waitUntil { !service.isStreaming }
        XCTAssertFalse(service.canRetryLastFailedSend)
        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertEqual(
            service.activeConversation.messages.map(\.content),
            ["What goes well with brown pants?", "Try a cream shirt with brown pants."]
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
        XCTAssertTrue(source.contains("Button(showsBackControl ? \"General\" : \"General Stylist\")"))
        XCTAssertTrue(source.contains(".accessibilityLabel(\"General Stylist\")"))
        XCTAssertTrue(source.contains("TextField(\"Ask your stylist...\""))
        XCTAssertTrue(source.contains("ForEach(starterPrompts"))
        XCTAssertTrue(source.contains(".disabled(service.isStreaming)"))
        XCTAssertTrue(source.contains("StyleMatchSessionRecoveryCopy.title"))
        XCTAssertTrue(source.contains("StyleMatchSessionRecoveryCopy.actionTitle"))
        XCTAssertFalse(source.contains("SignInWithAppleButton"))
        for prompt in expectedPrompts {
            XCTAssertTrue(source.contains("\"\(prompt)\""), "Missing prompt: \(prompt)")
        }
    }

    func testStylistChatComposerRemainsAnchoredAndKeepsUnauthorizedSendInPlace() throws {
        let source = try projectSource("StyleMatchAI/StylistChat/StylistChatView.swift")
        let contentSource = try projectSource("StyleMatchAI/ContentView.swift")

        XCTAssertTrue(source.contains(".safeAreaInset(edge: .bottom, spacing: 0)"))
        XCTAssertTrue(source.contains("anchoredInputBar"))
        XCTAssertTrue(source.contains(".scrollDismissesKeyboard(.interactively)"))
        XCTAssertTrue(source.contains("TextField(\"Ask your stylist...\", text: $draft, axis: .vertical)"))
        XCTAssertTrue(source.contains(".lineLimit(1...4)"))
        XCTAssertTrue(source.contains(".onSubmit {\n                        sendDraft()"))
        XCTAssertTrue(source.contains("guard service.authorizationState == .authorized else"))
        let submitStart = try XCTUnwrap(source.range(of: "private func submitQuestion(_ question: String) -> Bool")?.lowerBound)
        let submitEnd = try XCTUnwrap(source.range(of: "private func continueAfterAcceptingAITransmission()", range: submitStart..<source.endIndex)?.lowerBound)
        let submitSource = String(source[submitStart..<submitEnd])
        XCTAssertFalse(submitSource.contains("onSignInRequested()"), "A failed send must not dismiss the global Stylist overlay or navigate away.")
        XCTAssertTrue(submitSource.contains("service.inlineError = StylistChatError.unauthorized.localizedDescription"))
        XCTAssertTrue(source.contains("Button(StyleMatchSessionRecoveryCopy.actionTitle)"))
        XCTAssertTrue(source.contains("onSignInRequested()"), "Only the explicit reconnect action should navigate to Profile.")
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
        XCTAssertTrue(contentSource.contains(".safeAreaInset(edge: .bottom, spacing: 0) {\n                bottomNavigation\n            }"))
        XCTAssertFalse(contentSource.contains("if !isSoftwareKeyboardVisible {\n                    bottomNavigation"))
        XCTAssertTrue(contentSource.contains(".scrollDismissesKeyboard(.interactively)"))
        XCTAssertTrue(contentSource.contains("UIResponder.keyboardWillChangeFrameNotification"))
        XCTAssertTrue(contentSource.contains("UIResponder.keyboardWillHideNotification"))
        XCTAssertTrue(contentSource.contains("updateSoftwareKeyboardVisibility(from: notification)"))
        XCTAssertTrue(contentSource.contains("isSoftwareKeyboardVisible = false"))
        XCTAssertTrue(contentSource.contains("#selector(UIResponder.resignFirstResponder)"))
    }

    func testGeneralStylistComposerLifecycleClearsOnlyAfterAcceptedSendAndUsesExplicitRetryState() throws {
        let viewSource = try projectSource("StyleMatchAI/StylistChat/StylistChatView.swift")
        let serviceSource = try projectSource("StyleMatchAI/StylistChat/StylistChatService.swift")

        let sendDraftStart = try XCTUnwrap(viewSource.range(of: "private func sendDraft()")?.lowerBound)
        let sendDraftEnd = try XCTUnwrap(viewSource.range(of: "private func listen(to message:")?.lowerBound)
        let sendDraftSource = String(viewSource[sendDraftStart..<sendDraftEnd])

        XCTAssertTrue(sendDraftSource.contains("let capturedDraft = preparedDraft"))
        XCTAssertTrue(sendDraftSource.contains("guard !capturedDraft.isEmpty, !draftExceedsLimit else { return }"))
        XCTAssertTrue(sendDraftSource.contains("guard submitQuestion(capturedDraft) else { return }"))
        XCTAssertTrue(sendDraftSource.contains("draft = \"\""))
        XCTAssertTrue(sendDraftSource.contains("speechInput.clearTranscript()"))

        let acceptedSubmission = try XCTUnwrap(sendDraftSource.range(of: "guard submitQuestion(capturedDraft) else { return }")?.lowerBound)
        let clearAfterSubmission = try XCTUnwrap(sendDraftSource.range(of: "draft = \"\"", range: acceptedSubmission..<sendDraftSource.endIndex)?.lowerBound)
        XCTAssertLessThan(acceptedSubmission, clearAfterSubmission)

        XCTAssertTrue(viewSource.contains("TextField(\"Ask your stylist...\", text: $draft, axis: .vertical)"))
        XCTAssertTrue(viewSource.contains(".lineLimit(1...4)"))
        XCTAssertTrue(serviceSource.contains("guard !prompt.isEmpty, !isStreaming else { return false }"))
        XCTAssertTrue(serviceSource.contains("activeConversation.messages.removeLast()"))
        XCTAssertTrue(serviceSource.contains("return send(\n            retry.prompt,"))
        XCTAssertTrue(serviceSource.contains("retryableSend = nil"))
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
    func testVoiceInputCanRestartAfterCancellationWithoutLosingDraft() async {
        let controller = MockSpeechRecognitionController()
        let service = StylistSpeechInputService(controller: controller)

        await service.startListening(existingText: "Keep this draft")
        controller.emitPartial("first attempt")
        XCTAssertEqual(service.cancelListening(), "Keep this draft")

        await service.startListening(existingText: service.transcript)
        controller.emitPartial("second attempt")

        XCTAssertEqual(controller.startCount, 2)
        XCTAssertEqual(controller.stopCalls.filter { $0 }.count, 1)
        XCTAssertEqual(service.transcript, "Keep this draft second attempt")
        XCTAssertEqual(service.state, .listening)
    }

    @MainActor
    func testVoiceInputCancelledDuringPermissionRequestCannotStartLater() async {
        let controller = MockSpeechRecognitionController()
        controller.suspendMicrophoneRequest = true
        let service = StylistSpeechInputService(controller: controller)

        let startTask = Task {
            await service.startListening(existingText: "Keep draft")
        }
        await Task.yield()
        XCTAssertEqual(service.state, .requestingPermission)

        XCTAssertEqual(service.cancelListening(), "Keep draft")
        controller.completeSuspendedMicrophoneRequest(with: .authorized)
        await startTask.value

        XCTAssertEqual(controller.startCount, 0)
        XCTAssertEqual(controller.speechRequestCount, 0)
        XCTAssertEqual(service.state, .idle)
        XCTAssertEqual(service.transcript, "Keep draft")
    }

    func testSystemVoiceControllerOwnsOneValidatedTapPerSession() throws {
        let source = try projectSource("StyleMatchAI/StylistChat/StylistSpeechInputService.swift")

        XCTAssertTrue(source.contains("let engine = AVAudioEngine()"))
        XCTAssertTrue(source.contains("recordInstallGuard(\"existing_session\")"))
        XCTAssertTrue(source.contains("recordInstallGuard(\"existing_owned_tap\")"))
        XCTAssertTrue(source.contains("recordInstallGuard(\"invalid_audio_route\")"))
        XCTAssertTrue(source.contains("recordInstallGuard(\"invalid_input_format\")"))
        XCTAssertTrue(source.contains("guard !session.currentRoute.inputs.isEmpty"))
        XCTAssertTrue(source.contains("guard format.sampleRate > 0, format.channelCount > 0"))
        XCTAssertTrue(source.contains("private weak var tappedInputNode: AVAudioInputNode?"))
        XCTAssertTrue(source.contains("if let tappedInputNode {\n            tappedInputNode.removeTap(onBus: 0)"))
        XCTAssertTrue(source.contains("guard self?.activeSessionID == sessionID else { return }"))
        XCTAssertTrue(source.contains("#if DEBUG && canImport(OSLog)"))
        XCTAssertTrue(source.contains("install_tap_guard="))
        XCTAssertFalse(source.contains("audioEngine.inputNode.removeTap(onBus: 0)"))
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

    func testChatConversationStoreRefreshesBackupBeforeEachAtomicWrite() throws {
        let url = temporaryStoreURL()
        let store = ChatConversationStore(fileURL: url)

        for content in ["first", "second", "third"] {
            var conversation = ChatConversation()
            conversation.messages = [ChatMessage(role: .user, content: content)]
            store.save(conversation)
            XCTAssertNil(store.persistenceErrorMessage)
        }

        try Data("not-json".utf8).write(to: url)
        let recovered = ChatConversationStore(fileURL: url)
        let recoveredMessages = recovered.conversations.compactMap { $0.messages.first?.content }

        XCTAssertEqual(recoveredMessages.count, 2)
        XCTAssertTrue(recoveredMessages.contains("first"))
        XCTAssertTrue(recoveredMessages.contains("second"))
        XCTAssertFalse(recoveredMessages.contains("third"))
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

    func testCurrentScanProviderKeepsExplicitLiveScanOverNewerSavedHistory() throws {
        let suiteName = "CurrentScanProvider-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let old = contextSelectionAnalysis(garments: ["shirt"], confidences: [])
        let latest = OutfitAnalysisResult(
            score: 80,
            scoreBreakdown: old.scoreBreakdown,
            colorMatch: old.colorMatch,
            occasionFit: "Work",
            styleBalance: old.styleBalance,
            colorHarmony: old.colorHarmony,
            styleCoordination: old.styleCoordination,
            formality: old.formality,
            seasonalMatch: old.seasonalMatch,
            summary: old.summary,
            outfitDescription: "Work Uniform",
            detectedClothingItems: ["shirt"],
            colorPalette: old.colorPalette,
            environment: "86 F",
            imageQuality: old.imageQuality,
            outfitClassification: OutfitClassificationEngine.classify(
                visualObservations: [.init(identifier: "uniform utility shirt", confidence: 0.95)],
                selectedOccasion: "Work"
            ),
            suggestions: [],
            recommendations: []
        )
        let history: [String: StoredScanFixture] = [
            "scan-74": .init(score: 74, analysis: old, firstScannedAt: Date(timeIntervalSince1970: 74), occasion: .casual, thumbnailData: nil),
            "scan-80": .init(score: 80, analysis: latest, firstScannedAt: Date(timeIntervalSince1970: 80), occasion: .work, thumbnailData: Data([1]))
        ]
        defaults.set(try JSONEncoder().encode(history), forKey: "outfitScanHistoryData")
        let stale = StylistAuthoritativeScanContext(
            scanID: "scan-74",
            completedAt: Date(timeIntervalSince1970: 74),
            overallScore: 74,
            scoreBreakdown: nil,
            source: .liveCompleted
        )

        let resolved = CurrentScanContextProvider.resolve(
            preferred: stale,
            screenContext: nil,
            defaults: defaults
        )

        XCTAssertEqual(resolved?.scanID, "scan-74")
        XCTAssertEqual(resolved?.overallScore, 74)
        XCTAssertEqual(resolved?.source, .liveCompleted)
    }

    func testExplicitOlderSavedScanRemainsAuthoritativeForHistoricalQuestions() {
        let saved = StylistAuthoritativeScanContext(
            scanID: "saved-74",
            completedAt: Date(timeIntervalSince1970: 74),
            overallScore: 74,
            scoreBreakdown: nil,
            selectedOccasion: "Outdoor",
            source: .savedSelection
        )
        let screen = StylistScreenContext(
            currentTab: .scan,
            activeScanState: .saved,
            activeScanID: "saved-74",
            visibleOverallScore: 74,
            entryPoint: .scanResult,
            closetState: .unavailable
        )

        let resolved = CurrentScanContextProvider.resolve(preferred: saved, screenContext: screen)

        XCTAssertEqual(resolved, saved)
    }

    @MainActor
    func testChatRequestUsesAuthoritative80AndDropsStale74AssistantMemory() async throws {
        let transport = MockChatTransport(chunks: ["Your most recent scan scored 80/100."])
        var conversation = ChatConversation()
        conversation.messages = [
            ChatMessage(role: .user, content: "What was my last score?"),
            ChatMessage(role: .assistant, content: "Your last score was 74/100.")
        ]
        let store = ChatConversationStore(fileURL: temporaryStoreURL())
        store.save(conversation)
        let scan = StylistAuthoritativeScanContext(
            scanID: "scan-80",
            completedAt: Date(timeIntervalSince1970: 80),
            overallScore: 80,
            scoreBreakdown: nil,
            selectedOccasion: "Work",
            source: .latestCompleted
        )
        let service = StylistChatService(store: store, transport: transport)
        service.openOrCreateScanConversation(context: ChatContext(
            screenContext: StylistScreenContext(
                currentTab: .scan,
                activeScanState: .saved,
                activeScanID: scan.scanID,
                visibleOverallScore: scan.overallScore,
                entryPoint: .scanResult,
                closetState: .unavailable
            ),
            authoritativeScan: scan
        ))

        XCTAssertTrue(service.send("Help me understand this scan.", forcedContext: ChatContext(authoritativeScan: scan)))
        try await waitUntil { !service.isStreaming }

        let request = try XCTUnwrap(transport.requests.last)
        XCTAssertEqual(request.context.authoritativeScan?.scanID, "scan-80")
        XCTAssertEqual(request.context.authoritativeScan?.overallScore, 80)
        XCTAssertTrue(request.context.activeScan.contains("score 80/100"))
        XCTAssertFalse(request.messages.contains { $0.content.contains("74/100") })
    }

    @MainActor
    func testTypedScanIdentityDropsEntireOlderScanTurnWithoutTextGuessing() async throws {
        let transport = MockChatTransport(chunks: ["The current scan is 80/100."])
        var conversation = ChatConversation()
        conversation.messages = [
            ChatMessage(
                role: .user,
                content: "Why was that outfit weaker?",
                scanContextID: "scan-74"
            ),
            ChatMessage(
                role: .assistant,
                content: "The fit needed improvement.",
                scanContextID: "scan-74"
            )
        ]
        let store = ChatConversationStore(fileURL: temporaryStoreURL())
        store.save(conversation)
        let scan = StylistAuthoritativeScanContext(
            scanID: "scan-80",
            completedAt: Date(timeIntervalSince1970: 80),
            overallScore: 80,
            scoreBreakdown: nil,
            source: .latestCompleted
        )
        let service = StylistChatService(store: store, transport: transport)
        service.openOrCreateScanConversation(context: ChatContext(
            screenContext: StylistScreenContext(
                currentTab: .scan,
                activeScanState: .saved,
                activeScanID: scan.scanID,
                visibleOverallScore: scan.overallScore,
                entryPoint: .scanResult,
                closetState: .unavailable
            ),
            authoritativeScan: scan
        ))

        XCTAssertTrue(service.send("How should I improve this scan?", forcedContext: ChatContext(authoritativeScan: scan)))
        try await waitUntil { !service.isStreaming }

        let request = try XCTUnwrap(transport.requests.last)
        XCTAssertFalse(request.messages.contains { $0.content == "Why was that outfit weaker?" })
        XCTAssertFalse(request.messages.contains { $0.content == "The fit needed improvement." })
        XCTAssertEqual(request.messages.last?.content, "How should I improve this scan?")
    }

    func testLegacyChatMessageDecodesWithoutScanIdentity() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "id": UUID().uuidString,
            "role": "user",
            "content": "Hello",
            "timestamp": Date().timeIntervalSinceReferenceDate
        ])
        let message = try JSONDecoder().decode(ChatMessage.self, from: data)

        XCTAssertNil(message.scanContextID)
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

        XCTAssertNil(decoded.context.screenContext)
        let encodedObject = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        let encodedContext = try XCTUnwrap(encodedObject["context"] as? [String: Any])
        XCTAssertNil(encodedContext["screenContext"])
        XCTAssertNil(encodedContext["visibleAggregates"])
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

    @MainActor
    func testGeneralStylistStripsUnrequestedHomeAndClosetSurfaceContext() async throws {
        let transport = MockChatTransport(chunks: ["How can I help?"])
        let context = ChatContext(
            screenContext: StylistScreenContext(
                currentTab: .closet,
                activeScanState: .none,
                entryPoint: .closetDesigner,
                closetState: .loadedWithItems,
                surface: StylistScreenSurfaceAdapters.closet(itemID: "private-item-id", generation: 4)
            )
        )
        let service = StylistChatService(
            store: ChatConversationStore(fileURL: temporaryStoreURL()),
            transport: transport,
            contextProvider: { context }
        )

        XCTAssertTrue(service.send("Help me choose an outfit."))
        try await waitUntil { !service.isStreaming }

        XCTAssertNil(transport.requests.last?.context.screenContext?.surface)
        let request = try XCTUnwrap(transport.requests.last)
        let payload = String(decoding: try JSONEncoder().encode(request), as: UTF8.self)
        XCTAssertFalse(payload.contains("private-item-id"))
    }

    @MainActor
    func testExplicitClosetContextSendsOnlyCustomerVisibleFacts() async throws {
        let item = ClosetItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            name: "Navy polo",
            category: "Shirt",
            color: "Navy",
            brand: "",
            size: "M",
            occasion: "Work",
            notes: ""
        )
        let route = try XCTUnwrap(ScreenAwarenessSnapshot.closetItem(item, generation: 5))
        let transport = MockChatTransport(chunks: ["Try it with chinos."])
        let service = StylistChatService(
            store: ChatConversationStore(fileURL: temporaryStoreURL()),
            transport: transport,
            contextProvider: { route.requestContext }
        )

        XCTAssertTrue(service.send("How should I style this?"))
        try await waitUntil { !service.isStreaming }

        let request = try XCTUnwrap(transport.requests.last)
        let payload = String(decoding: try JSONEncoder().encode(request), as: UTF8.self)
        XCTAssertTrue(request.context.recentOutfits.contains("Navy polo"))
        XCTAssertNil(request.context.screenContext)
        XCTAssertFalse(payload.contains(item.id.uuidString))
        XCTAssertFalse(payload.contains("contextGeneration"))
    }

    @MainActor
    func testNoScanStylingRequestCarriesExplicitWeatherConstraint() async throws {
        let transport = MockChatTransport(chunks: ["Use breathable layers."])
        let weatherConstraint = AIStylistContextSelection.weatherConstraint(
            fahrenheit: 83,
            condition: "sunny"
        )
        let context = ChatContext(
            weatherConstraint: weatherConstraint,
            screenContext: .aiTab(entryPoint: .weatherStyling)
        )
        let service = StylistChatService(
            store: ChatConversationStore(fileURL: temporaryStoreURL()),
            transport: transport,
            contextProvider: { context }
        )

        XCTAssertTrue(service.send("What should I wear today?"))
        try await waitUntil { !service.isStreaming }

        let attachment = try XCTUnwrap(transport.requests.last?.context.stylistContextSnapshot)
        XCTAssertEqual(attachment.snapshot, .empty)
        XCTAssertEqual(attachment.weather.availability, .available)
        XCTAssertNil(attachment.weather.value)
        XCTAssertEqual(attachment.weather.constraint, weatherConstraint)
    }

    @MainActor
    func testGeneralStylistDoesNotRetainWeatherContextAfterWeatherHandoff() async throws {
        let transport = MockChatTransport(chunks: ["Try a cream shirt with brown pants."])
        let weatherConstraint = AIStylistContextSelection.weatherConstraint(
            fahrenheit: 83,
            condition: "sunny"
        )
        let service = StylistChatService(
            store: ChatConversationStore(fileURL: temporaryStoreURL()),
            transport: transport
        )

        let weatherContext = ChatContext(
            weatherConstraint: weatherConstraint,
            screenContext: .aiTab(entryPoint: .weatherStyling)
        )
        XCTAssertTrue(service.send("What should I wear for the weather?", forcedContext: weatherContext))
        try await waitUntil { !service.isStreaming }
        XCTAssertEqual(transport.requests.last?.context.weatherConstraint, weatherConstraint)

        service.newChat()
        let generalContext = ChatContext(
            weatherConstraint: weatherConstraint,
            screenContext: .aiTab()
        )
        XCTAssertTrue(service.send("What goes well with brown pants?", forcedContext: generalContext))
        try await waitUntil { !service.isStreaming }

        let generalRequest = try XCTUnwrap(transport.requests.last)
        XCTAssertEqual(generalRequest.context.weatherConstraint, "")
        XCTAssertEqual(generalRequest.context.stylistContextSnapshot.weather, .unavailable)
    }

    @MainActor
    func testUnavailableWeatherIsPresentAndNeverDefaulted() async throws {
        let transport = MockChatTransport(chunks: ["Weather is unavailable."])
        let service = StylistChatService(
            store: ChatConversationStore(fileURL: temporaryStoreURL()),
            transport: transport,
            contextProvider: {
                ChatContext(screenContext: .aiTab())
            }
        )

        XCTAssertTrue(service.send("What should I wear today?"))
        try await waitUntil { !service.isStreaming }

        let request = try XCTUnwrap(transport.requests.last)
        XCTAssertEqual(request.context.stylistContextSnapshot.weather, .unavailable)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try JSONEncoder().encode(request)) as? [String: Any]
        )
        let context = try XCTUnwrap(object["context"] as? [String: Any])
        XCTAssertNil(context["stylistContextSnapshot"])
        XCTAssertNil(context["stylist_context"])
        XCTAssertFalse(
            String(data: try JSONEncoder().encode(request), encoding: .utf8)?
                .contains("temperatureFahrenheit") == true
        )
    }

    @MainActor
    func testConfirmedUniformCarriesPresentOrExplicitWorkplaceUniformAndSafetyStates() async throws {
        let suiteName = "ConfirmedUniformSavedScan-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(
            try JSONSerialization.data(withJSONObject: ["uniform-scan": [:]]),
            forKey: "outfitScanHistoryData"
        )
        let transport = MockChatTransport(chunks: ["I need your safety requirements."])
        let classification = OutfitClassificationResult
            .uncertain(selectedOccasion: "Work")
            .confirming(.workUniform)
        let scan = StylistAuthoritativeScanContext(
            scanID: "uniform-scan",
            completedAt: Date(timeIntervalSince1970: 1_000),
            overallScore: 80,
            scoreBreakdown: nil,
            selectedOccasion: "Work",
            outfitClassification: classification,
            source: .savedSelection
        )
        let context = ChatContext(
            screenContext: StylistScreenContext(
                currentTab: .ai,
                activeScanState: .saved,
                activeScanID: "uniform-scan",
                visibleOverallScore: 80,
                entryPoint: .scanResult,
                closetState: .unavailable
            ),
            authoritativeScan: scan
        )
        let service = StylistChatService(
            store: ChatConversationStore(fileURL: temporaryStoreURL()),
            transport: transport,
            memoryDefaults: defaults
        )
        service.openOrCreateScanConversation(context: context)

        XCTAssertTrue(service.send("What shoes are safe?", forcedContext: context))
        try await waitUntil { !service.isStreaming }

        let request = try XCTUnwrap(transport.requests.last)
        let attachment = request.context.stylistContextSnapshot
        XCTAssertEqual(attachment.workplace.availability, .available)
        XCTAssertEqual(attachment.workplace.value.dressCode, .uniform)
        XCTAssertEqual(attachment.uniform.availability, .available)
        XCTAssertEqual(attachment.uniform.dressCode, .uniform)
        XCTAssertEqual(attachment.safety.availability, .unavailable)
        XCTAssertEqual(attachment.safety.footwearConstraints, [.unknown])

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
        )
        let encodedContext = try XCTUnwrap(object["context"] as? [String: Any])
        XCTAssertNil(encodedContext["stylistContextSnapshot"])
        XCTAssertNil(encodedContext["stylist_context"])
    }

    @MainActor
    func testMismatchedScanFailsClosedWithoutChangingScreenContextAuthority() async throws {
        let transport = MockChatTransport(chunks: ["No matching scan is available."])
        let screenContext = StylistScreenContext(
            currentTab: .ai,
            activeScanState: .saved,
            activeScanID: "screen-scan",
            selectedOccasion: "Work",
            visibleOverallScore: 80,
            entryPoint: .scanResult,
            closetState: .unavailable
        )
        let mismatchedScan = StylistAuthoritativeScanContext(
            scanID: "different-scan",
            completedAt: Date(timeIntervalSince1970: 2_000),
            overallScore: 74,
            scoreBreakdown: nil,
            selectedOccasion: "Casual",
            source: .savedSelection
        )
        let context = ChatContext(
            weatherConstraint: AIStylistContextSelection.weatherConstraint(
                fahrenheit: 83,
                condition: "sunny"
            ),
            screenContext: screenContext,
            authoritativeScan: mismatchedScan
        )
        let service = StylistChatService(
            store: ChatConversationStore(fileURL: temporaryStoreURL()),
            transport: transport
        )

        XCTAssertTrue(service.send("What should I wear?", forcedContext: context))
        try await waitUntil { !service.isStreaming }

        let request = try XCTUnwrap(transport.requests.last)
        XCTAssertNil(request.context.authoritativeScan)
        XCTAssertEqual(request.context.screenContext?.activeScanState, StylistActiveScanState.none)
        XCTAssertNil(request.context.screenContext?.activeScanID)
        XCTAssertNil(request.context.screenContext?.visibleOverallScore)
        XCTAssertEqual(request.context.stylistContextSnapshot.snapshot, .empty)
        XCTAssertEqual(request.context.stylistContextSnapshot.workplace, .unavailable)
        XCTAssertEqual(request.context.stylistContextSnapshot.uniform, .unavailable)
        XCTAssertEqual(request.context.stylistContextSnapshot.safety, .unavailable)
        XCTAssertEqual(request.context.stylistContextSnapshot.weather.availability, .unavailable)
    }

    func testLegacyRoutePipelineEncodesAuthoritativeSnapshotEquivalentToCanonicalRoute() throws {
        let classification = OutfitClassificationResult
            .uncertain(selectedOccasion: "Work")
            .confirming(.workUniform)
        let scan = StylistAuthoritativeScanContext(
            scanID: "legacy-work-scan",
            completedAt: Date(timeIntervalSince1970: 1_000),
            overallScore: 74,
            scoreBreakdown: nil,
            detectedStyle: "Casual",
            selectedOccasion: "Work",
            outfitClassification: classification,
            source: .savedSelection
        )
        let screenContext = StylistScreenContext(
            currentTab: .scan,
            activeScanState: .saved,
            activeScanID: scan.scanID,
            selectedOccasion: "Work",
            visibleOverallScore: scan.overallScore,
            entryPoint: .scanResult,
            closetState: .unavailable
        )
        let routeContext = ChatContext(
            activeScan: "pre-resolution value",
            screenContext: screenContext,
            authoritativeScan: scan
        )
        let requestTime = Date(timeIntervalSince1970: 1_100)
        let canonical = StylistRouteContextPipeline.resolving(
            routeContext,
            requestTime: requestTime
        )
        let legacy = StylistRouteContextPipeline.applying(
            routeContext,
            to: ChatContext(profileSummary: "Legacy personalization remains supplemental."),
            requestTime: requestTime
        )

        XCTAssertEqual(legacy.authoritativeScan?.scanID, scan.scanID)
        XCTAssertEqual(legacy.authoritativeScan?.overallScore, 74)
        XCTAssertEqual(legacy.authoritativeScan?.selectedOccasion, "Work")
        XCTAssertEqual(legacy.stylistContextSnapshot, canonical.stylistContextSnapshot)

        let canonicalPayload = try encodedAttachment(from: canonical)
        let legacyPayload = try encodedAttachment(from: legacy)
        XCTAssertEqual(legacyPayload as NSDictionary, canonicalPayload as NSDictionary)
        XCTAssertNil(legacyPayload["schemaVersion"])
        XCTAssertNil(legacyPayload["weather"])
    }

    func testLegacyRoutePipelineFailsClosedForDeletedOrMismatchedScan() throws {
        let staleScan = StylistAuthoritativeScanContext(
            scanID: "deleted-scan",
            completedAt: Date(timeIntervalSince1970: 1_000),
            overallScore: 74,
            scoreBreakdown: nil,
            selectedOccasion: "Work",
            source: .savedSelection
        )
        let noActiveScan = StylistScreenContext(
            currentTab: .scan,
            activeScanState: .none,
            selectedOccasion: "Work",
            entryPoint: .scanTab,
            closetState: .unavailable
        )
        let routeContext = ChatContext(
            activeScan: "stale scan text",
            scoreBreakdown: "stale score breakdown",
            screenContext: noActiveScan,
            authoritativeScan: staleScan
        )

        let resolved = StylistRouteContextPipeline.applying(
            routeContext,
            to: ChatContext(profileSummary: "Supplemental profile text."),
            requestTime: Date(timeIntervalSince1970: 1_100)
        )

        XCTAssertNil(resolved.authoritativeScan)
        XCTAssertEqual(resolved.activeScan, "")
        XCTAssertNil(resolved.scoreBreakdown)
        XCTAssertEqual(resolved.screenContext, noActiveScan)
        XCTAssertEqual(resolved.stylistContextSnapshot, .unavailable)
    }

    func testLegacyRouteRequestAlwaysEncodesSnapshotKey() throws {
        let resolved = StylistRouteContextPipeline.applying(
            ChatContext(
                screenContext: StylistScreenContext(
                    currentTab: .scan,
                    activeScanState: .none,
                    entryPoint: .scanTab,
                    closetState: .unavailable
                )
            ),
            to: ChatContext(profileSummary: "Legacy profile context."),
            requestTime: Date(timeIntervalSince1970: 1_100)
        )
        let request = ChatRequest(
            messages: [.init(role: "user", content: "Why did I get this score?")],
            context: resolved,
            stream: true
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
        )
        let context = try XCTUnwrap(object["context"] as? [String: Any])
        XCTAssertNil(context["stylistContextSnapshot"])
        XCTAssertNil(context["stylist_context"])
    }

    func testLegacyScanRouteUsesSharedTypedContextPipeline() throws {
        let scanSource = try projectSource("StyleMatchAI/ScanView.swift")
        let clientSource = try projectSource("StyleMatchAI/OpenAIStylistClient.swift")
        let serviceSource = try projectSource("StyleMatchAI/StylistChat/StylistChatService.swift")

        XCTAssertTrue(scanSource.contains("routeContext: routeContext"))
        XCTAssertTrue(scanSource.contains("legacyScanStylistRouteContext(for: analysis)"))
        XCTAssertTrue(clientSource.contains("StylistRouteContextPipeline.applying"))
        XCTAssertTrue(serviceSource.contains("StylistRouteContextPipeline.resolving"))
    }

    func testCanonicalFactBuilderUsesRequestAliasesAndNeverSerializesLocalKeys() throws {
        var aliases = ["00000000-0000-0000-0000-000000000011", "00000000-0000-0000-0000-000000000012"]
        let context = try XCTUnwrap(PersonalizationContextBuilder.stylistFactContext(
            selectedCloset: [.init(localRecordKey: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, category: "Jacket", color: "Navy", brand: "Brand", occasion: "Work")],
            selectedScans: [.init(localRecordKey: "local-scan-key", scanDate: Date(timeIntervalSince1970: 1_000), selectedOccasion: "Work", score: 87, scoreBand: nil, detectedStyle: "Business Casual", palette: ["navy"])],
            aliasFactory: { aliases.removeFirst() }
        ))

        XCTAssertEqual(context.version, 1)
        XCTAssertEqual(context.closetItems.map(\.alias), ["00000000-0000-0000-0000-000000000011"])
        XCTAssertEqual(context.savedScans.map(\.alias), ["00000000-0000-0000-0000-000000000012"])
        let body = String(data: try JSONEncoder().encode(context), encoding: .utf8) ?? ""
        XCTAssertFalse(body.contains("local-scan-key"))
        XCTAssertFalse(body.contains("00000000-0000-0000-0000-000000000001"))
    }

    func testCanonicalFactBuilderEncodesOnlyISOScanDatesForWorkerFactContext() throws {
        let context = try XCTUnwrap(PersonalizationContextBuilder.stylistFactContext(
            selectedCloset: [],
            selectedScans: [.init(localRecordKey: "local-scan-key", scanDate: Date(timeIntervalSince1970: 1_000), selectedOccasion: nil, score: 87, scoreBand: nil, detectedStyle: nil, palette: nil)],
            aliasFactory: { "00000000-0000-0000-0000-000000000099" }
        ))

        let body = try XCTUnwrap(String(data: JSONEncoder().encode(context), encoding: .utf8))
        XCTAssertTrue(body.contains("\"scanDate\":\""), "The Worker contract requires an ISO-8601 scan date string, not a local Date encoding.")
        XCTAssertFalse(body.contains("local-scan-key"))
    }

    func testCanonicalFactBuilderProjectsVisionV1WithoutAliasesOrUnsupportedSavedScanFacts() throws {
        var aliases = ["00000000-0000-0000-0000-000000000011", "00000000-0000-0000-0000-000000000012"]
        let factContext = try XCTUnwrap(PersonalizationContextBuilder.stylistFactContext(
            selectedCloset: [.init(localRecordKey: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, category: "Jacket", color: "Navy", brand: "Brand", occasion: "Work")],
            selectedScans: [.init(localRecordKey: "local-scan-key", scanDate: Date(timeIntervalSince1970: 1_000), selectedOccasion: "Work", score: 87, scoreBand: "High", detectedStyle: "Business Casual", palette: ["navy", "white"])],
            aliasFactory: { aliases.removeFirst() }
        ))

        let attachments = try XCTUnwrap(PersonalizationContextBuilder.visionV1Attachments(from: factContext))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(attachments)) as? [String: Any])
        let encoded = try XCTUnwrap(String(data: JSONEncoder().encode(attachments), encoding: .utf8))

        XCTAssertEqual((object["selected_scan_facts"] as? [String: Any])?["palette"] as? [String], ["navy", "white"])
        XCTAssertEqual((object["selected_scan_facts"] as? [String: Any])?["style_tags"] as? [String], ["Business Casual"])
        XCTAssertEqual(((object["selected_closet_items"] as? [[String: Any]])?.first?["colors"] as? [String]), ["Navy"])
        XCTAssertEqual(((object["selected_closet_items"] as? [[String: Any]])?.first?["occasion_tags"] as? [String]), ["Work"])
        for forbidden in ["alias", "local-scan-key", "scanDate", "score", "scoreBand", "selectedOccasion", "00000000-0000-0000-0000-000000000001"] {
            XCTAssertFalse(encoded.contains(forbidden))
        }
    }

    func testCanonicalFactBuilderVisionV1ProjectionPreservesLowConfidencePaletteOmission() throws {
        let factContext = try XCTUnwrap(PersonalizationContextBuilder.stylistFactContext(
            selectedCloset: [],
            selectedScans: [.init(localRecordKey: "local-scan-key", scanDate: Date(timeIntervalSince1970: 1_000), selectedOccasion: nil, score: nil, scoreBand: nil, detectedStyle: nil, palette: nil)],
            aliasFactory: { "00000000-0000-0000-0000-000000000011" }
        ))
        XCTAssertNil(try PersonalizationContextBuilder.visionV1Attachments(from: factContext))
    }

    func testCanonicalBuilderRequiresExplicitCurrentStylePreferenceSelection() throws {
        let profile = StyleProfilePersonalizationContext(
            styleGoals: ["Minimal"], favoriteColors: ["Navy"], avoidedColors: ["Orange"], favoriteBrands: ["Brand"],
            declaredUndertone: nil, preferredFit: .regular, preferredPantFit: nil,
            preferredNeutrals: [], preferredAccentColors: [], preferredPantRise: nil,
            clothingSizes: ClothingSizes(), comfortPreferences: [], budgetRange: nil,
            shoppingFocus: nil, preferredShoppingCategories: [], workSetting: nil,
            travelFrequency: nil, hobbiesActivities: [], stylistVoice: nil
        )
        let selection = PersonalizationContextBuilder.VisionStylePreferenceSelection(
            preferredColors: ["Navy"], avoidedColors: ["Orange"], preferredFits: ["regular"], preferredStyles: ["Minimal"], preferredBrands: ["Brand"]
        )
        let attachment = try XCTUnwrap(PersonalizationContextBuilder.visionV1StylePreferences(selection: selection, currentProfile: profile))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(attachment)) as? [String: Any])
        XCTAssertEqual(object["preferred_colors"] as? [String], ["Navy"])
        XCTAssertEqual(object["avoided_colors"] as? [String], ["Orange"])
        XCTAssertEqual(object["preferred_fits"] as? [String], ["regular"])
        XCTAssertEqual(object["preferred_styles"] as? [String], ["Minimal"])
        XCTAssertEqual(object["preferred_brands"] as? [String], ["Brand"])
        XCTAssertNil(try PersonalizationContextBuilder.visionV1StylePreferences(selection: .empty, currentProfile: profile))
        XCTAssertThrowsError(try PersonalizationContextBuilder.visionV1StylePreferences(
            selection: .init(preferredColors: ["Stale"], avoidedColors: [], preferredFits: [], preferredStyles: [], preferredBrands: []),
            currentProfile: profile
        ))
    }

    func testVisionV1RequestEncodesOnlyAcceptedWireFields() throws {
        let request = VisionChatRequestV1(
            contractVersion: 1,
            requestID: "00000000-0000-4000-8000-000000000001",
            prompt: "Suggest an outfit",
            attachments: .init(
                selectedImage: .init(mediaType: "image/jpeg", dataBase64: "/9j/2Q=="),
                selectedScanFacts: .init(palette: ["navy"], styleTags: ["minimal"]),
                stylePreferences: .init(preferredColors: ["navy"], avoidedColors: ["orange"], preferredFits: ["regular"], preferredStyles: ["minimal"], preferredBrands: ["Brand"]),
                selectedClosetItems: [.init(category: "Jacket", colors: ["navy"], brand: "Brand", occasionTags: ["work"])]
            )
        )
        let data = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["contract_version", "request_id", "prompt", "attachments"])
        let encoded = try XCTUnwrap(String(data: data, encoding: .utf8))
        for forbidden in ["scopes", "consent_", "account", "user_id", "selected_facts", "width", "height", "alias", "localRecordKey", "image_url"] {
            XCTAssertFalse(encoded.contains(forbidden))
        }
        let image = try XCTUnwrap((json["attachments"] as? [String: Any])?["selected_image"] as? [String: Any])
        XCTAssertEqual(Set(image.keys), ["media_type", "data_base64"])
    }

    func testVisionImageNormalizerReencodesSyntheticPNGAsMetadataFreeJPEG() throws {
        let source = try syntheticImageData(uti: "public.png" as CFString, metadata: [
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "SENTINEL_PRIVATE_METADATA"],
            kCGImagePropertyPNGDescription: "SENTINEL_PRIVATE_METADATA"
        ])

        let normalized = try StylistVisionImageNormalizer.normalizeToJPEG(source)
        let output = try XCTUnwrap(Data(base64Encoded: normalized.dataBase64))
        XCTAssertEqual(normalized.mediaType, "image/jpeg")
        XCTAssertTrue(output.starts(with: Data([0xff, 0xd8])))
        XCTAssertLessThanOrEqual(output.count, StylistVisionImageNormalizer.maximumJPEGBytes)
        XCTAssertFalse(String(data: output, encoding: .isoLatin1)?.contains("SENTINEL_PRIVATE_METADATA") == true)
        let imageSource = try XCTUnwrap(CGImageSourceCreateWithData(output as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any])
        XCTAssertEqual(properties[kCGImagePropertyPixelWidth] as? Int, 2)
        XCTAssertEqual(properties[kCGImagePropertyPixelHeight] as? Int, 2)
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        XCTAssertNil(exif?[kCGImagePropertyExifUserComment])
    }

    func testSerializedVisionV1VariantsPassAcceptedWorkerParserWithoutReencoding() throws {
        let imageData = try syntheticImageData(uti: "public.jpeg" as CFString)
        let image = try StylistVisionImageNormalizer.normalizeToJPEG(imageData)
        let scan = StylistContextBuilder.VisionV1Attachments.SelectedScanFacts(palette: ["navy"], styleTags: ["minimal"])
        let closet = StylistContextBuilder.VisionV1Attachments.SelectedClosetItem(category: "Jacket", colors: ["navy"], brand: "Brand", occasionTags: ["work"])
        let preferences = StylistContextBuilder.VisionV1StylePreferences(preferredColors: ["navy"], avoidedColors: nil, preferredFits: ["regular"], preferredStyles: nil, preferredBrands: nil)
        let variants: [VisionChatRequestV1.Attachments] = [
            .init(selectedImage: image, selectedScanFacts: nil, stylePreferences: nil, selectedClosetItems: nil),
            .init(selectedImage: nil, selectedScanFacts: scan, stylePreferences: nil, selectedClosetItems: nil),
            .init(selectedImage: nil, selectedScanFacts: nil, stylePreferences: preferences, selectedClosetItems: nil),
            .init(selectedImage: nil, selectedScanFacts: nil, stylePreferences: nil, selectedClosetItems: [closet]),
            .init(selectedImage: image, selectedScanFacts: scan, stylePreferences: nil, selectedClosetItems: nil),
            .init(selectedImage: image, selectedScanFacts: nil, stylePreferences: preferences, selectedClosetItems: nil),
            .init(selectedImage: image, selectedScanFacts: nil, stylePreferences: nil, selectedClosetItems: [closet]),
            .init(selectedImage: image, selectedScanFacts: scan, stylePreferences: preferences, selectedClosetItems: [closet])
        ]
        for (index, attachments) in variants.enumerated() {
            let request = VisionChatRequestV1(contractVersion: 1, requestID: String(format: "00000000-0000-4000-8000-%012d", index + 1), prompt: "Suggest an outfit", attachments: attachments)
            try assertAcceptedWorkerParserReceivesExactBytes(JSONEncoder().encode(request))
        }
    }

    /// Local synthetic fixture handoff for the Worker parser regression. It
    /// runs only when the explicitly supplied temporary path is present.
    func testExportsSyntheticNormalizedJPEGForLocalWorkerParserFixture() throws {
        guard let path = ProcessInfo.processInfo.environment["STYLEMATCH_VISION_FIXTURE_PATH"] else { return }
        let source = try syntheticImageData(uti: "public.jpeg" as CFString)
        let normalized = try StylistVisionImageNormalizer.normalizeToJPEG(source)
        try XCTUnwrap(Data(base64Encoded: normalized.dataBase64)).write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    private func assertAcceptedWorkerParserReceivesExactBytes(_ bytes: Data) throws {
        guard let worker = ProcessInfo.processInfo.environment["STYLEMATCH_WORKER_PARSER_ROOT"], !worker.isEmpty else {
            throw XCTSkip("The cross-worktree Worker parser harness requires STYLEMATCH_WORKER_PARSER_ROOT.")
        }
        let script = """
        import { readFileSync } from 'node:fs';
        import { parseVisionChatRequestV1 } from '\(worker)/src/vision/visionContractV1.ts';
        parseVisionChatRequestV1(JSON.parse(readFileSync(0, 'utf8')));
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/local/bin/node")
        process.arguments = ["--experimental-strip-types", "--input-type=module", "-e", script]
        let stdin = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardError = stderr
        try process.run()
        stdin.fileHandleForWriting.write(bytes)
        try stdin.fileHandleForWriting.close()
        process.waitUntilExit()
        let error = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertEqual(process.terminationStatus, 0, error)
    }

    private func syntheticImageData(uti: CFString, metadata: [CFString: Any] = [:]) throws -> Data {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 2,
            height: 2,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.1, green: 0.3, blue: 0.7, alpha: 0.5))
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        let image = try XCTUnwrap(context.makeImage())
        let destination = NSMutableData()
        let writer = try XCTUnwrap(CGImageDestinationCreateWithData(destination, uti, 1, nil))
        CGImageDestinationAddImage(writer, image, metadata as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(writer))
        return destination as Data
    }

    func testCanonicalFactBuilderRejectsOverLimitSelectionsWithoutTruncation() throws {
        let closet = (0...PersonalizationContextBuilder.maximumClosetItems).map { index in
            ClosetStylistFacts(localRecordKey: UUID(), category: "Item \(index)", color: nil, brand: nil, occasion: nil)
        }
        XCTAssertThrowsError(try PersonalizationContextBuilder.stylistFactContext(selectedCloset: closet, selectedScans: [])) { error in
            XCTAssertEqual(error as? StylistContextBuilder.FactContextBuildError, .tooManyClosetItems)
        }

        let oversized = ClosetStylistFacts(localRecordKey: UUID(), category: String(repeating: "x", count: 65), color: nil, brand: nil, occasion: nil)
        XCTAssertThrowsError(try PersonalizationContextBuilder.stylistFactContext(selectedCloset: [oversized], selectedScans: [])) { error in
            XCTAssertEqual(error as? StylistContextBuilder.FactContextBuildError, .invalidFact)
        }
    }

    func testConversationAttachmentPreservesExplicitWorkplaceEvidenceWithoutPromotingItToActiveScan() throws {
        let workplace = WorkplaceContext(
            environment: .mixedFloorAndOffice,
            dressCode: .safetyWorkwear,
            footwearConstraints: [.safetyToe, .slipResistant],
            ppeRequirements: ["eye protection"],
            activityLevel: .mixed,
            exposure: .mixed,
            floorAndOfficeMix: true,
            source: .explicitThreadCorrection,
            confirmation: .userConfirmed,
            lastConfirmedAt: Date(timeIntervalSince1970: 1_000)
        )
        let attachment = StylistRouteContextAttachment.resolving(
            snapshot: StylistConversationSnapshot(
                scanID: nil,
                score: nil,
                breakdown: nil,
                detectedStyle: nil,
                selectedOccasion: nil,
                observedGarments: [],
                observedColors: [],
                weather: nil,
                workplace: workplace
            ),
            weatherConstraint: ""
        )
        let context = ChatContext(
            screenContext: .aiTab(),
            stylistContextSnapshot: attachment
        )

        let resolved = StylistRouteContextPipeline.resolving(context)

        XCTAssertNil(resolved.authoritativeScan)
        XCTAssertEqual(resolved.screenContext?.activeScanState, StylistActiveScanState.none)
        XCTAssertEqual(resolved.stylistContextSnapshot.workplace.availability, .available)
        XCTAssertEqual(resolved.stylistContextSnapshot.workplace.value, workplace)
        XCTAssertEqual(resolved.stylistContextSnapshot.safety.footwearConstraints, [.safetyToe, .slipResistant])
    }

    func testConversationAttachmentUsesV1ShapeAndKeepsUnknownWeatherExplicit() throws {
        let attachment = StylistRouteContextAttachment.resolving(
            snapshot: .empty,
            weatherConstraint: ""
        )
        let request = ChatRequest(
            messages: [.init(role: "user", content: "What should I wear tomorrow?")],
            context: ChatContext(screenContext: .aiTab(), stylistContextSnapshot: attachment),
            stream: true
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
        )
        let encodedContext = try XCTUnwrap(object["context"] as? [String: Any])
        XCTAssertNil(encodedContext["stylistContextSnapshot"])
        XCTAssertNil(encodedContext["stylist_context"])
    }

    func testConversationStarterPromptsPrioritizeScanAndFactoryContext() {
        let workplace = WorkplaceContext(
            environment: .mixedFloorAndOffice,
            dressCode: .safetyWorkwear,
            footwearConstraints: [.safetyToe],
            ppeRequirements: ["eye protection"],
            activityLevel: .mixed,
            exposure: .mixed,
            floorAndOfficeMix: true,
            source: .explicitThreadCorrection,
            confirmation: .userConfirmed,
            lastConfirmedAt: Date(timeIntervalSince1970: 1_000)
        )
        let snapshot = StylistConversationSnapshot(
            scanID: "scan-1",
            score: 74,
            breakdown: nil,
            detectedStyle: "Casual",
            selectedOccasion: "Work",
            observedGarments: ["polo"],
            observedColors: ["navy"],
            weather: nil,
            workplace: workplace
        )

        let prompts = StylistConversationStarterPrompts.prompts(snapshot: snapshot)

        XCTAssertEqual(Array(prompts.prefix(3)), [
            "Make this outfit more professional.",
            "What shoes work with this outfit?",
            "Give me a warmer-weather version."
        ])
        XCTAssertTrue(prompts.contains("Build an outfit for a factory-and-office day."))
        XCTAssertTrue(prompts.contains("What should I wear today?"))
        XCTAssertEqual(Set(prompts).count, prompts.count)
    }

    func testStandaloneAssistantUsesTypedRouteContext() throws {
        let source = try projectSource("StyleMatchAI/AIAssistantsView.swift")

        XCTAssertTrue(source.contains("StylistConversationSnapshot.latestCompleted()"))
        XCTAssertTrue(source.contains("StylistRouteContextAttachment.resolving("))
        XCTAssertTrue(source.contains("routeContext: routeContext"))
    }


    private func encodedAttachment(from context: ChatContext) throws -> [String: Any] {
        let request = ChatRequest(
            messages: [.init(role: "user", content: "Why did I get this score?")],
            context: context,
            stream: true
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
        )
        let encodedContext = try XCTUnwrap(object["context"] as? [String: Any])
        XCTAssertNil(encodedContext["stylistContextSnapshot"])
        return [:]
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

    private struct StoredScanFixture: Codable {
        let score: Int
        let analysis: OutfitAnalysisResult?
        let firstScannedAt: Date
        let occasion: Occasion?
        let thumbnailData: Data?
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

    func testLegacyConversationDecodesAsUnverifiedAndDoesNotRewriteOnLoad() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "id": UUID().uuidString,
            "messages": [],
            "createdAt": Date().timeIntervalSinceReferenceDate,
            "updatedAt": Date().timeIntervalSinceReferenceDate
        ])

        let conversation = try JSONDecoder().decode(ChatConversation.self, from: data)

        XCTAssertEqual(conversation.scope, .generalStylist)
        XCTAssertEqual(conversation.classification, .legacyUnverified)
        XCTAssertNil(conversation.scanContext)
    }

    @MainActor
    func testContextualConversationNeverPersistsOrResumesAsGeneral() async throws {
        let url = temporaryStoreURL()
        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: url.appendingPathExtension("bak"))
        }
        let transport = MockChatTransport(chunks: ["Contextual answer"])
        let service = StylistChatService(
            store: ChatConversationStore(fileURL: url),
            transport: transport,
            contextProvider: { ChatContext() }
        )

        service.beginContextualConversation()
        XCTAssertEqual(service.activeConversation.scope, .contextualStylist)
        XCTAssertEqual(service.activeConversation.classification, .contextualEphemeral)
        XCTAssertTrue(service.send("Does this work?", forcedContext: ChatContext(recentOutfits: "Customer chose a closet item.")))
        try await waitUntil { !service.isStreaming }

        XCTAssertTrue(ChatConversationStore(fileURL: url).conversations.isEmpty)

        let restarted = StylistChatService(
            store: ChatConversationStore(fileURL: url),
            transport: MockChatTransport(chunks: []),
            contextProvider: { ChatContext() }
        )
        XCTAssertTrue(restarted.activeConversation.isVerifiedGeneral)
        XCTAssertTrue(restarted.activeConversation.messages.isEmpty)
        XCTAssertFalse(restarted.activeConversation.scope.isContextual)
        XCTAssertEqual(transport.requests.last?.messages.map(\.content), ["Does this work?"])
    }

    @MainActor
    func testVerifiedGeneralConversationPersistsAndResumesOnlyItsOwnHistory() async throws {
        let url = temporaryStoreURL()
        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: url.appendingPathExtension("bak"))
        }
        let service = StylistChatService(
            store: ChatConversationStore(fileURL: url),
            transport: MockChatTransport(chunks: ["General answer"]),
            contextProvider: { ChatContext() }
        )
        let generalID = service.activeConversation.id

        XCTAssertTrue(service.send("Help me plan a dinner outfit."))
        try await waitUntil { !service.isStreaming }

        let restarted = StylistChatService(
            store: ChatConversationStore(fileURL: url),
            transport: MockChatTransport(chunks: []),
            contextProvider: { ChatContext() }
        )
        XCTAssertEqual(restarted.activeConversation.id, generalID)
        XCTAssertTrue(restarted.activeConversation.isVerifiedGeneral)
        XCTAssertEqual(restarted.activeConversation.messages.first?.content, "Help me plan a dinner outfit.")
    }

    @MainActor
    func testLegacyConversationIsQuarantinedFromAutomaticGeneralResumeAndTransport() async throws {
        let url = temporaryStoreURL()
        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: url.appendingPathExtension("bak"))
        }
        var legacy = ChatConversation()
        legacy.messages = [ChatMessage(role: .user, content: "Contextual legacy turn")]
        var serialized = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any])
        serialized.removeValue(forKey: "classification")
        try JSONSerialization.data(withJSONObject: [serialized]).write(to: url)
        let beforeLoad = try Data(contentsOf: url)

        let store = ChatConversationStore(fileURL: url)
        XCTAssertEqual(try Data(contentsOf: url), beforeLoad)
        XCTAssertEqual(store.conversations.first?.classification, .legacyUnverified)

        let transport = MockChatTransport(chunks: ["Fresh general answer"])
        let service = StylistChatService(store: store, transport: transport, contextProvider: { ChatContext() })
        XCTAssertTrue(service.activeConversation.isVerifiedGeneral)
        XCTAssertTrue(service.activeConversation.messages.isEmpty)
        XCTAssertTrue(service.send("Start a new general question."))
        try await waitUntil { !service.isStreaming }

        let outbound = try XCTUnwrap(transport.requests.last?.messages.map(\.content))
        XCTAssertEqual(outbound, ["Start a new general question."])
        XCTAssertFalse(outbound.contains("Contextual legacy turn"))
    }

    func testPriorChatsOnlyPresentsVerifiedGeneralAndScanConversations() throws {
        let source = try projectSource("StyleMatchAI/StylistChat/StylistChatView.swift")

        XCTAssertTrue(source.contains("conversations.filter(\\.isVerifiedGeneral)"))
        XCTAssertFalse(source.contains("conversations.filter { !$0.scope.isScanBound }"))
    }

    func testConsentContinuationRevalidatesTheCapturedAuthorityBeforeTransport() throws {
        let source = try projectSource("StyleMatchAI/StylistChat/StylistChatView.swift")
        let start = try XCTUnwrap(source.range(of: "private func continueAfterAcceptingAITransmission()"))
        let end = try XCTUnwrap(source.range(of: "@discardableResult\n    private func send(", range: start.upperBound..<source.endIndex))
        let continuation = String(source[start.lowerBound..<end.lowerBound])

        XCTAssertTrue(source.contains("enum StylistPendingSendAuthority: Equatable"))
        XCTAssertTrue(source.contains("pendingConsentRequest = PendingConsentRequest(question: question, authority: authority)"))
        XCTAssertTrue(continuation.contains("pendingConsentRequest = nil"))
        XCTAssertTrue(continuation.contains("send(pending.question, authorizedBy: pending.authority)"))
        XCTAssertFalse(continuation.contains("service.send(question, forcedContext: currentConversationContext)"))
        XCTAssertTrue(source.contains("snapshot: validScreenAwarenessSnapshot"))
    }

    @MainActor
    func testScanConversationReusesOnlySameScanAndFiltersStaleHistory() async throws {
        let transport = MockChatTransport(chunks: ["80/100 is a Good Match."])
        let store = ChatConversationStore(fileURL: temporaryStoreURL())
        let current = activeScan(id: "scan-current", score: 80, palette: ["gray", "denim", "cream"])
        let other = activeScan(id: "scan-other", score: 74, palette: ["olive"])
        var persisted = ChatConversation(
            scope: .activeScan(scanID: "scan-current"),
            scanContext: StylistConversationScanContext(authoritativeScan: current)
        )
        persisted.messages = [
            ChatMessage(role: .user, content: "Do olive pants work?"),
            ChatMessage(role: .assistant, content: "Olive pants were from an old chat."),
            ChatMessage(role: .user, content: "What did this scan score?", scanContextID: "scan-current"),
            ChatMessage(role: .assistant, content: "It scored 80/100.", scanContextID: "scan-current"),
            ChatMessage(role: .user, content: "Other scan", scanContextID: "scan-other")
        ]
        store.save(persisted)
        let service = StylistChatService(store: store, transport: transport)
        service.openOrCreateScanConversation(context: scanContext(current))
        let currentConversationID = service.activeConversation.id

        XCTAssertTrue(service.send("What colors work with this scan?", forcedContext: scanContext(other)))
        try await waitUntil { !service.isStreaming }

        let request = try XCTUnwrap(transport.requests.last)
        XCTAssertEqual(request.context.authoritativeScan?.scanID, "scan-current")
        XCTAssertEqual(request.context.authoritativeScan?.overallScore, 80)
        XCTAssertTrue(request.context.activeScan.contains("score 80/100"))
        XCTAssertTrue(request.context.activeScan.contains("Good Match"))
        XCTAssertTrue(request.context.activeScan.contains("gray, denim, cream"))
        XCTAssertFalse(request.messages.contains { $0.content.localizedCaseInsensitiveContains("olive pants") })
        XCTAssertFalse(request.messages.contains { $0.content == "Other scan" })
        XCTAssertTrue(request.messages.contains { $0.content == "What did this scan score?" })

        service.openOrCreateScanConversation(context: scanContext(current))
        XCTAssertEqual(service.activeConversation.id, currentConversationID)
        service.openOrCreateScanConversation(context: scanContext(other))
        XCTAssertNotEqual(service.activeConversation.id, currentConversationID)
        XCTAssertEqual(service.activeConversation.scope, .activeScan(scanID: "scan-other"))
    }

    @MainActor
    func testScanBoundScoreQuestionsUseCanonicalLocalReplyAndNeverReachTransport() {
        let transport = MockChatTransport(chunks: ["legacy generic score response"])
        let store = ChatConversationStore(fileURL: temporaryStoreURL())
        let scan = activeScan(id: "scan-80", score: 80, palette: ["gray", "denim", "cream"])
        let service = StylistChatService(store: store, transport: transport)
        service.openOrCreateScanConversation(context: scanContext(scan))

        for question in [
            "What is my score?",
            "Can you see my score?",
            "How did I do?",
            "What did I score?",
            "Tell me my score.",
            "WHAT IS MY SCORE!!!"
        ] {
            XCTAssertTrue(service.send(question, forcedContext: scanContext(scan)))
            XCTAssertEqual(
                service.activeConversation.messages.last?.content,
                "Your latest completed KigoStylist scan scored 80/100 — Good Match."
            )
        }

        XCTAssertTrue(transport.requests.isEmpty)
    }

    @MainActor
    func testGeneralStylistScoreQuestionDoesNotFabricateScanReply() async throws {
        let transport = MockChatTransport(chunks: ["I need an active scan to answer that."])
        let service = StylistChatService(store: ChatConversationStore(fileURL: temporaryStoreURL()), transport: transport)

        XCTAssertTrue(service.send("What is my score?"))
        try await waitUntil { !service.isStreaming }

        XCTAssertEqual(service.activeConversation.messages.last?.content, "I need an active scan to answer that.")
        XCTAssertEqual(transport.requests.count, 1)
    }

    @MainActor
    func testGeneralStylistStripsStaleScanContextAndSendsTheNewUserTurn() async throws {
        let transport = MockChatTransport(chunks: ["General advice."])
        let service = StylistChatService(store: ChatConversationStore(fileURL: temporaryStoreURL()), transport: transport)
        let staleScan = activeScan(id: "stale-scan", score: 80, palette: ["olive"])

        XCTAssertTrue(service.send("Help me match this shirt.", forcedContext: scanContext(staleScan)))
        try await waitUntil { !service.isStreaming }

        let request = try XCTUnwrap(transport.requests.last)
        XCTAssertNil(service.activeConversation.messages.first?.scanContextID)
        XCTAssertNil(request.context.authoritativeScan)
        XCTAssertTrue(request.context.activeScan.isEmpty)
        XCTAssertEqual(request.context.screenContext?.activeScanState, StylistActiveScanState.none)
        XCTAssertEqual(request.messages.last?.content, "Help me match this shirt.")
    }

    @MainActor
    func testGeneralStylistProjectsOnlyExplicitlyConsentedMemoryAndKeepsCurrentRequest() async throws {
        let suiteName = "StylistChatServiceTests.memory.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("Sign in with Apple", forKey: "customerAccountMode")
        defaults.set("apple-user", forKey: "customerAppleUserID")
        defaults.set(true, forKey: "shareAppContextWithChatGPT")
        let profileStore = ProfileStore(defaults: defaults, userId: "apple-user")
        profileStore.currentProfile.favoriteColors = ["navy"]
        profileStore.currentProfile.workSetting = "PPE required"
        profileStore.save()

        let transport = MockChatTransport(chunks: ["Use the supplied work constraint."])
        let service = StylistChatService(
            store: ChatConversationStore(fileURL: temporaryStoreURL()),
            transport: transport,
            memoryDefaults: defaults
        )
        let stale = activeScan(id: "stale-scan", score: 80, palette: ["olive"])

        XCTAssertTrue(service.send("Ignore navy and suggest black shoes.", forcedContext: scanContext(stale)))
        try await waitUntil { !service.isStreaming }

        let request = try XCTUnwrap(transport.requests.last)
        XCTAssertEqual(request.messages.last?.content, "Ignore navy and suggest black shoes.")
        XCTAssertNil(request.context.authoritativeScan)
        XCTAssertTrue(request.context.activeScan.isEmpty)
        XCTAssertTrue(request.context.profileSummary.contains("Confirmed personal preferences:"))
        XCTAssertTrue(request.context.profileSummary.contains("Confirmed workplace constraints: PPE required"))
        XCTAssertLessThanOrEqual(request.context.profileSummary.utf16.count, 600)
    }

    @MainActor
    func testMalformedScanScopeBlocksEmptyOutboundLocallyAndPreservesDraftTurn() {
        let transport = MockChatTransport(chunks: [])
        let malformed = ChatConversation(scope: .savedScan(scanID: "missing-context"))
        let service = StylistChatService(store: ChatConversationStore(fileURL: temporaryStoreURL()), transport: transport)
        service.openConversation(malformed)

        XCTAssertFalse(service.send("Keep this draft for retry.", forcedContext: ChatContext()))
        XCTAssertTrue(transport.requests.isEmpty)
        XCTAssertTrue(service.activeConversation.messages.isEmpty)
        XCTAssertEqual(
            service.inlineError,
            "That saved scan is no longer available. Reopen it from Scan History before asking the Stylist."
        )
        XCTAssertEqual(service.lastDeliveryDiagnostic?.category, .invalidRequest)
        XCTAssertEqual(service.lastDeliveryDiagnostic?.conversationScope, .savedScan(scanID: "missing-context"))
        XCTAssertEqual(service.lastDeliveryDiagnostic?.outboundMessageCount, 0)
        XCTAssertEqual(service.lastDeliveryDiagnostic?.isLocalValidation, true)
    }

    @MainActor
    func testTransportFailureRetainsBoundedSafeDiagnosticMetadata() async throws {
        let error = StylistChatDiagnosticError(
            category: .invalidRequest,
            statusCode: 400,
            requestPhase: .response
        )
        let service = StylistChatService(
            store: ChatConversationStore(fileURL: temporaryStoreURL()),
            transport: ThrowingChatTransport(error: error)
        )

        XCTAssertTrue(service.send("A valid general question."))
        try await waitUntil { !service.isStreaming }

        XCTAssertEqual(service.lastDeliveryDiagnostic?.category, .invalidRequest)
        XCTAssertEqual(service.lastDeliveryDiagnostic?.statusCode, 400)
        XCTAssertEqual(service.lastDeliveryDiagnostic?.requestPhase, .response)
        XCTAssertFalse(String(describing: service.lastDeliveryDiagnostic).contains("request-400"))
        XCTAssertEqual(service.lastDeliveryDiagnostic?.conversationScope, .generalStylist)
        XCTAssertEqual(service.lastDeliveryDiagnostic?.outboundMessageCount, 1)
        XCTAssertEqual(service.lastDeliveryDiagnostic?.isLocalValidation, false)
    }

    @MainActor
    func testScanConversationPersistsOnlyCompactStructuredFacts() throws {
        let store = ChatConversationStore(fileURL: temporaryStoreURL())
        let service = StylistChatService(store: store, transport: MockChatTransport(chunks: []))
        let scan = activeScan(id: "scan-80", score: 80, palette: ["gray", "denim", "cream"])

        service.openOrCreateScanConversation(context: scanContext(scan))
        store.save(service.activeConversation)
        let encoded = try JSONEncoder().encode(service.activeConversation)
        let text = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        XCTAssertTrue(text.contains("scan-80"))
        XCTAssertTrue(text.contains("gray"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("employee"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("employer"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("ocr"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("imageData"))
        XCTAssertEqual(ChatConversationStore(fileURL: storeURL(from: store)).conversations.first?.scanContext?.score, 80)
    }

    func testPinnedContextCardContainsAccessibleScopeAndNoGeneralAssumptions() throws {
        let source = try projectSource("StyleMatchAI/StylistChat/StylistChatView.swift")

        XCTAssertTrue(source.contains("Discussing this Scan"))
        XCTAssertTrue(source.contains("scanContextAccessibilityLabel"))
        XCTAssertTrue(source.contains("Evidence limitations"))
        XCTAssertTrue(source.contains("scope.isScanBound"))
    }

    func testScanConversationUXHasCollapsedCardQuickActionsAndExplicitGeneralMode() throws {
        let source = try projectSource("StyleMatchAI/StylistChat/StylistChatView.swift")

        XCTAssertTrue(source.contains("@State private var isScanCardExpanded = false"))
        XCTAssertTrue(source.contains("Switch to General Stylist"))
        XCTAssertTrue(source.contains("Discuss this Scan"))
        XCTAssertTrue(source.contains("scanQuickFollowUps"))
        XCTAssertTrue(source.contains("Explain My Score"))
        XCTAssertTrue(source.contains("Shopping Suggestions"))
        XCTAssertTrue(source.contains("Section(\"General Stylist\")"))
        XCTAssertTrue(source.contains("Section(\"Scan Conversations\")"))
        XCTAssertTrue(source.contains("hasExplicitlySelectedGeneralStylist"))
    }

    @MainActor
    func testExplicitSavedScanHandoffSelectsEmptyBoundConversationExactlyOnce() throws {
        let store = ChatConversationStore(fileURL: temporaryStoreURL())
        let service = StylistChatService(store: store, transport: MockChatTransport(chunks: []))
        let scan = StylistAuthoritativeScanContext(
            scanID: "saved-scan-80",
            completedAt: Date(timeIntervalSince1970: 1_700_000_080),
            overallScore: 80,
            scoreBreakdown: nil,
            detectedStyle: "Casual",
            selectedOccasion: nil,
            source: .savedSelection,
            palette: ["gray", "denim", "cream"],
            outfitType: "Other / Uncertain"
        )
        let screen = StylistScreenContext(
            currentTab: .ai,
            activeScanState: .saved,
            activeScanID: scan.scanID,
            visibleOverallScore: scan.overallScore,
            entryPoint: .scanResult,
            closetState: .unavailable
        )
        let handoff = StylistScanHandoff(
            context: ChatContext(screenContext: screen, authoritativeScan: scan),
            screenContext: screen,
            routeToken: UUID()
        )
        let controller = StylistScanConversationHandoffController()

        let firstID = try XCTUnwrap(controller.consume(handoff, using: service))
        XCTAssertEqual(service.activeConversation.id, firstID)
        XCTAssertEqual(service.activeConversation.scope, .savedScan(scanID: "saved-scan-80"))
        XCTAssertEqual(service.activeConversation.scanContext?.scanID, "saved-scan-80")
        XCTAssertTrue(service.activeConversation.messages.isEmpty)

        let secondID = controller.consume(handoff, using: service)
        XCTAssertEqual(secondID, firstID)
        XCTAssertEqual(controller.selectedConversationID, firstID)
        XCTAssertEqual(controller.consumedRouteToken, handoff.routeToken)
    }

    @MainActor
    func testDistinctExplicitHandoffsRemainIsolatedFromGeneralConversation() throws {
        let store = ChatConversationStore(fileURL: temporaryStoreURL())
        let service = StylistChatService(store: store, transport: MockChatTransport(chunks: []))
        service.newChat()
        let generalID = service.activeConversation.id
        let controller = StylistScanConversationHandoffController()

        func handoff(id: String, score: Int) -> StylistScanHandoff {
            let scan = StylistAuthoritativeScanContext(
                scanID: id,
                completedAt: Date(timeIntervalSince1970: TimeInterval(score)),
                overallScore: score,
                scoreBreakdown: nil,
                source: .savedSelection,
                palette: ["gray"]
            )
            let screen = StylistScreenContext(
                currentTab: .ai,
                activeScanState: .saved,
                activeScanID: id,
                visibleOverallScore: score,
                entryPoint: .scanResult,
                closetState: .unavailable
            )
            return StylistScanHandoff(
                context: ChatContext(screenContext: screen, authoritativeScan: scan),
                screenContext: screen,
                routeToken: UUID()
            )
        }

        let firstID = try XCTUnwrap(controller.consume(handoff(id: "saved-80", score: 80), using: service))
        XCTAssertNotEqual(firstID, generalID)
        XCTAssertEqual(service.activeConversation.scope, .savedScan(scanID: "saved-80"))

        let secondID = try XCTUnwrap(controller.consume(handoff(id: "saved-74", score: 74), using: service))
        XCTAssertNotEqual(secondID, firstID)
        XCTAssertEqual(service.activeConversation.scope, .savedScan(scanID: "saved-74"))
        XCTAssertNotEqual(service.activeConversation.id, generalID)
    }

    @MainActor
    func testDeletedSavedScanFailsClosedBeforeMessagePersistenceOrTransport() throws {
        let suiteName = "DeletedSavedScanContext-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let scanID = "saved-scan-deleted-before-send"
        defaults.set(try JSONSerialization.data(withJSONObject: [scanID: [:]]), forKey: "outfitScanHistoryData")

        let transport = MockChatTransport(chunks: [])
        let service = StylistChatService(
            store: ChatConversationStore(fileURL: temporaryStoreURL()),
            transport: transport,
            memoryDefaults: defaults
        )
        let scan = StylistAuthoritativeScanContext(
            scanID: scanID,
            completedAt: Date(timeIntervalSince1970: 1_700_000_000),
            overallScore: 82,
            scoreBreakdown: nil,
            selectedOccasion: "Work",
            source: .savedSelection
        )
        let context = ChatContext(
            screenContext: StylistScreenContext(
                currentTab: .ai,
                activeScanState: .saved,
                activeScanID: scanID,
                visibleOverallScore: 82,
                entryPoint: .scanResult,
                closetState: .unavailable
            ),
            authoritativeScan: scan
        )
        XCTAssertNotNil(service.openOrCreateScanConversation(context: context))

        defaults.removeObject(forKey: "outfitScanHistoryData")

        XCTAssertFalse(service.send("Explain this score.", forcedContext: context))
        XCTAssertTrue(transport.requests.isEmpty)
        XCTAssertTrue(service.activeConversation.messages.isEmpty)
        XCTAssertEqual(
            service.inlineError,
            "That saved scan is no longer available. Reopen it from Scan History before asking the Stylist."
        )
    }

    @MainActor
    func testScanTabEntryOpensOnlyItsExactBoundConversationAndKeepsGeneralScanFree() throws {
        let store = ChatConversationStore(fileURL: temporaryStoreURL())
        let transport = MockChatTransport(chunks: [])
        let service = StylistChatService(store: store, transport: transport)
        let controller = StylistScanConversationHandoffController()
        let first = activeScan(id: "scan-entry-80", score: 80, palette: ["gray"])
        let second = activeScan(id: "scan-entry-74", score: 74, palette: ["navy"])

        let firstID = try XCTUnwrap(
            controller.openCurrentScanConversation(
                context: scanContext(first),
                screenContext: scanContext(first).screenContext!,
                generalStylistSelected: false,
                using: service
            )
        )
        XCTAssertEqual(service.activeConversation.scope, .activeScan(scanID: "scan-entry-80"))
        XCTAssertTrue(service.send("What is my score?", forcedContext: scanContext(first)))
        XCTAssertEqual(
            service.activeConversation.messages.last?.content,
            "Your latest completed KigoStylist scan scored 80/100 — Good Match."
        )
        XCTAssertTrue(transport.requests.isEmpty)

        XCTAssertNil(
            controller.openCurrentScanConversation(
                context: scanContext(first),
                screenContext: scanContext(first).screenContext!,
                generalStylistSelected: true,
                using: service
            )
        )
        XCTAssertEqual(service.activeConversation.id, firstID)

        XCTAssertNil(
            controller.openCurrentScanConversation(
                context: scanContext(second),
                screenContext: scanContext(first).screenContext!,
                generalStylistSelected: false,
                using: service
            )
        )
        XCTAssertEqual(service.activeConversation.id, firstID)

        let secondID = try XCTUnwrap(
            controller.openCurrentScanConversation(
                context: scanContext(second),
                screenContext: scanContext(second).screenContext!,
                generalStylistSelected: false,
                using: service
            )
        )
        XCTAssertNotEqual(secondID, firstID)
        XCTAssertEqual(service.activeConversation.scope, .activeScan(scanID: "scan-entry-74"))
    }

    private func activeScan(id: String, score: Int, palette: [String]) -> StylistAuthoritativeScanContext {
        StylistAuthoritativeScanContext(
            scanID: id,
            completedAt: Date(timeIntervalSince1970: 1_700_000_000),
            overallScore: score,
            scoreBreakdown: nil,
            detectedStyle: "Casual",
            selectedOccasion: nil,
            source: .liveCompleted,
            palette: palette,
            topStyleMatches: ["Casual", "Smart Casual"],
            evidenceLimitations: ["Outfit type is uncertain; do not treat it as confirmed."]
        )
    }

    private func scanContext(_ scan: StylistAuthoritativeScanContext) -> ChatContext {
        ChatContext(
            screenContext: StylistScreenContext(
                currentTab: .scan,
                activeScanState: .live,
                activeScanID: scan.scanID,
                visibleOverallScore: scan.overallScore,
                entryPoint: .scanResult,
                closetState: .unavailable
            ),
            authoritativeScan: scan
        )
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

private final class FailOnceChatTransport: StylistChatTransport {
    private(set) var requests: [ChatRequest] = []
    private let response: String

    init(response: String) {
        self.response = response
    }

    func send(_ request: ChatRequest) -> AsyncThrowingStream<String, Error> {
        requests.append(request)
        return AsyncThrowingStream { continuation in
            if requests.count == 1 {
                continuation.finish(throwing: StylistChatError.providerError)
            } else {
                continuation.yield(response)
                continuation.finish()
            }
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

private final class ScopedConsentURLProtocol: URLProtocol {
    struct Stub { let status: Int; let body: String }
    static var requests: [URLRequest] = []
    static var stubs: [Stub] = []

    static func reset(_ values: [Stub]) {
        requests = []
        stubs = values
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        guard !Self.stubs.isEmpty, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let stub = Self.stubs.removeFirst()
        let response = HTTPURLResponse(url: url, statusCode: stub.status, httpVersion: "HTTP/1.1", headerFields: ["content-type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !stub.body.isEmpty { client?.urlProtocol(self, didLoad: Data(stub.body.utf8)) }
        client?.urlProtocolDidFinishLoading(self)
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
    var suspendMicrophoneRequest = false
    private var microphoneContinuation: CheckedContinuation<StylistSpeechAuthorizationStatus, Never>?

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
        if suspendMicrophoneRequest {
            return await withCheckedContinuation { continuation in
                microphoneContinuation = continuation
            }
        }
        microphoneStatus = microphoneRequestResult
        return microphoneRequestResult
    }

    func completeSuspendedMicrophoneRequest(with status: StylistSpeechAuthorizationStatus) {
        microphoneStatus = status
        microphoneContinuation?.resume(returning: status)
        microphoneContinuation = nil
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
