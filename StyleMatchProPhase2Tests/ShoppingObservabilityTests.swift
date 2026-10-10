import XCTest
@testable import StyleMatchPro

final class ShoppingObservabilityTests: XCTestCase {
    private let routeID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    func testNikeOnlyZeroInventoryEmitsTruthfulSoftFallbackSequenceWithoutChangingProducts() {
        let diagnostics = RecordingShoppingDiagnostics()
        let context = ShoppingDiagnosticContext(routeID: routeID, loadGeneration: 1)
        let products = [makeProduct(id: "amazon-1", retailerID: "amazon")]

        let result = RetailerPreferencePolicy.apply(
            products: products,
            preferredRetailerIDs: ["nike"],
            supportedStores: stores(),
            diagnosticContext: context,
            diagnostics: diagnostics
        )

        XCTAssertEqual(result.products.map(\.id), ["amazon-1"])
        XCTAssertTrue(result.usedFallback)
        XCTAssertEqual(result.requestedRetailerIDs, ["nike"])
        XCTAssertEqual(diagnostics.events.map(\.name), [
            "retailer_selection_snapshot",
            "retailer_filter_completed",
            "fallback_activated"
        ])
        XCTAssertEqual(
            diagnostics.events.last?.payload,
            .fallbackActivated(
                reason: .selectedRetailersZeroInventorySoftFallback,
                inputCount: 1,
                fallbackCount: 1
            )
        )
    }

    func testStrictEmptyResultEmitsZeroMatchesWithoutFalseFallback() {
        let diagnostics = RecordingShoppingDiagnostics()
        let result = RetailerPreferencePolicy.apply(
            products: [],
            preferredRetailerIDs: ["nike"],
            supportedStores: stores(),
            diagnosticContext: context(1),
            diagnostics: diagnostics
        )

        XCTAssertTrue(result.products.isEmpty)
        XCTAssertFalse(result.usedFallback)
        XCTAssertEqual(diagnostics.events.map(\.name), [
            "retailer_selection_snapshot",
            "retailer_filter_completed"
        ])
        XCTAssertFalse(diagnostics.events.contains { $0.name == "fallback_activated" })
        XCTAssertEqual(ShoppingCatalogObservation.fallbackReason(for: result, inputCount: 0), .strictStoreZeroResults)
    }

    func testSelectedStoreInventoryAvailablePreservesOrderAndDoesNotFallback() {
        let diagnostics = RecordingShoppingDiagnostics()
        let products = [
            makeProduct(id: "nike-1", retailerID: "nike"),
            makeProduct(id: "amazon-1", retailerID: "amazon"),
            makeProduct(id: "nike-2", retailerID: "nike")
        ]
        let result = RetailerPreferencePolicy.apply(
            products: products,
            preferredRetailerIDs: ["nike"],
            supportedStores: stores(),
            diagnosticContext: context(1),
            diagnostics: diagnostics
        )

        XCTAssertEqual(result.products.map(\.id), ["nike-1", "nike-2"])
        XCTAssertFalse(result.usedFallback)
        XCTAssertFalse(diagnostics.events.contains { $0.name == "fallback_activated" })
    }

    func testRetailerPolicyParityWithAndWithoutDiagnostics() {
        let products = [
            makeProduct(id: "amazon-1", retailerID: "amazon"),
            makeProduct(id: "nike-1", retailerID: "nike"),
            makeProduct(id: "macys-1", retailerID: "macys")
        ]
        let baseline = RetailerPreferencePolicy.apply(
            products: products,
            preferredRetailerIDs: ["nike", "macys"],
            supportedStores: stores()
        )
        let instrumented = RetailerPreferencePolicy.apply(
            products: products,
            preferredRetailerIDs: ["nike", "macys"],
            supportedStores: stores(),
            diagnosticContext: context(2),
            diagnostics: RecordingShoppingDiagnostics()
        )

        XCTAssertEqual(instrumented, baseline)
        XCTAssertEqual(instrumented.products.map(\.id), baseline.products.map(\.id))
        XCTAssertEqual(instrumented.usedFallback, baseline.usedFallback)
        XCTAssertEqual(
            ShoppingCatalogObservation.fallbackReason(for: instrumented, inputCount: products.count),
            ShoppingCatalogObservation.fallbackReason(for: baseline, inputCount: products.count)
        )
    }

    func testCatalogObservationPreservesCountsAndRecommendationOrdering() {
        let products = [
            makeProduct(id: "one", retailerID: "amazon"),
            makeProduct(id: "two", retailerID: "amazon"),
            makeProduct(id: "three", retailerID: "amazon")
        ]
        let policy = RetailerPreferencePolicy.apply(
            products: products,
            preferredRetailerIDs: [],
            supportedStores: stores()
        )
        let recommendationsBefore = ShoppingRecommendationEngine.popularFallbackRecommendations(catalog: policy.products)
        let observation = ShoppingCatalogObservation.make(
            source: .remote,
            selectedRetailerIDs: [],
            supportedStores: stores(),
            inputProducts: products,
            policyResult: policy,
            eligibleCount: policy.products.count,
            recommendationCount: recommendationsBefore.count,
            displayedCount: recommendationsBefore.count,
            destination: .products
        )
        let recommendationsAfter = ShoppingRecommendationEngine.popularFallbackRecommendations(catalog: policy.products)

        XCTAssertEqual(policy.products.map(\.id), products.map(\.id))
        XCTAssertEqual(recommendationsAfter.map(\.product.id), recommendationsBefore.map(\.product.id))
        XCTAssertEqual(observation.inputCount, 3)
        XCTAssertEqual(observation.eligibleCount, 3)
        XCTAssertEqual(observation.displayedCount, recommendationsBefore.count)
        XCTAssertEqual(observation.fallbackReason, .none)
    }

    func testFreshRemoteLoadEmitsOrderedStartCacheSourceAndCompletion() async {
        let diagnostics = RecordingShoppingDiagnostics()
        let result = loadResult(source: .remote, products: [makeProduct(id: "remote", retailerID: "nike")])
        let loader = SharedProductCatalogLoader(provider: ResultProvider(result: result), timeToLive: 60)

        _ = await loader.loadResult(diagnosticContext: context(1), diagnostics: diagnostics, trigger: .routeEntry)

        XCTAssertEqual(diagnostics.events.map(\.name), [
            "shopping_load_started",
            "catalog_cache_result",
            "catalog_cache_result",
            "catalog_source_selected",
            "shopping_load_completed"
        ])
        XCTAssertEqual(diagnostics.events[3].payload, .catalogSourceSelected(source: .remote))
    }

    func testMemoryCacheHitEmitsHitWithoutChangingResult() async {
        let diagnostics = RecordingShoppingDiagnostics()
        let expected = loadResult(source: .remote, products: [makeProduct(id: "remote", retailerID: "nike")])
        let loader = SharedProductCatalogLoader(provider: ResultProvider(result: expected), timeToLive: 60)
        _ = await loader.loadResult(diagnosticContext: context(1), diagnostics: diagnostics, trigger: .routeEntry)
        diagnostics.reset()

        let second = await loader.loadResult(diagnosticContext: context(2), diagnostics: diagnostics, trigger: .refresh)

        XCTAssertEqual(second, expected)
        XCTAssertEqual(diagnostics.events.map(\.name), [
            "shopping_load_started",
            "catalog_cache_result",
            "catalog_source_selected",
            "shopping_load_completed"
        ])
        XCTAssertEqual(diagnostics.events[1].payload, .catalogCacheResult(layer: .memory, outcome: .hit, count: 1))
    }

    func testDiskCacheRecoveryEmitsDiskHitAndCacheSource() async {
        let diagnostics = RecordingShoppingDiagnostics()
        let expected = loadResult(
            source: .cache,
            products: [makeProduct(id: "cached", retailerID: "nike")],
            classification: .connectivity,
            cacheHit: true
        )
        let loader = SharedProductCatalogLoader(provider: ResultProvider(result: expected), timeToLive: 60)

        _ = await loader.loadResult(diagnosticContext: context(1), diagnostics: diagnostics, trigger: .routeEntry)

        XCTAssertTrue(diagnostics.events.contains { $0.payload == .catalogCacheResult(layer: .disk, outcome: .hit, count: 1) })
        XCTAssertTrue(diagnostics.events.contains { $0.payload == .catalogSourceSelected(source: .cache) })
    }

    func testBundledRecoveryEmitsBundledSource() async {
        let diagnostics = RecordingShoppingDiagnostics()
        let expected = loadResult(
            source: .bundled,
            products: [makeProduct(id: "bundled", retailerID: "amazon")],
            classification: .connectivity
        )
        let loader = SharedProductCatalogLoader(provider: ResultProvider(result: expected), timeToLive: 60)

        _ = await loader.loadResult(diagnosticContext: context(1), diagnostics: diagnostics, trigger: .routeEntry)

        XCTAssertTrue(diagnostics.events.contains { $0.payload == .catalogSourceSelected(source: .bundled) })
        XCTAssertTrue(diagnostics.events.contains {
            $0.payload == .shoppingLoadCompleted(source: .bundled, receivedCount: 1, safeCount: 1, outcome: .recovered)
        })
    }

    func testAllSourcesExhaustedEmitsOneTerminalErrorAndCompletion() async {
        let diagnostics = RecordingShoppingDiagnostics()
        let expected = loadResult(source: .none, products: [], classification: .missingCatalog)
        let loader = SharedProductCatalogLoader(provider: ResultProvider(result: expected), timeToLive: 60)

        _ = await loader.loadResult(diagnosticContext: context(1), diagnostics: diagnostics, trigger: .routeEntry)

        XCTAssertEqual(diagnostics.events.filter { $0.name == "shopping_load_started" }.count, 1)
        XCTAssertEqual(diagnostics.events.filter { $0.name == "shopping_error" }.count, 1)
        XCTAssertEqual(diagnostics.events.filter { $0.name == "shopping_load_completed" }.count, 1)
        XCTAssertEqual(diagnostics.events.filter { $0.name == "catalog_source_selected" }.count, 1)
    }

    func testPreferenceInitializationAndAddRemoveReplaceChangesAreTyped() {
        let defaults = isolatedDefaults()
        let diagnostics = RecordingShoppingDiagnostics()
        let store = ShoppingLocalStore(
            defaults: defaults,
            userID: "test-user",
            supportedStores: stores(),
            diagnostics: diagnostics,
            diagnosticContext: context(1)
        )
        store.setPreferredRetailerIDs(["nike"], supportedStores: stores())
        store.setPreferredRetailerIDs(["nike", "macys"], supportedStores: stores())
        store.setPreferredRetailerIDs(["macys"], supportedStores: stores())
        store.setPreferredRetailerIDs(["amazon"], supportedStores: stores())

        XCTAssertEqual(diagnostics.events.map(\.name), [
            "preferences_initialized",
            "preferences_selection_changed",
            "preferences_selection_changed",
            "preferences_selection_changed",
            "preferences_selection_changed"
        ])
        XCTAssertEqual(diagnostics.events[1].payload, .preferencesSelectionChanged(action: .add, beforeCount: 0, afterCount: 1))
        XCTAssertEqual(diagnostics.events[2].payload, .preferencesSelectionChanged(action: .add, beforeCount: 1, afterCount: 2))
        XCTAssertEqual(diagnostics.events[3].payload, .preferencesSelectionChanged(action: .remove, beforeCount: 2, afterCount: 1))
        XCTAssertEqual(diagnostics.events[4].payload, .preferencesSelectionChanged(action: .replace, beforeCount: 1, afterCount: 1))
    }

    func testRelaunchPersistenceAndSelectedRetailerParity() {
        let defaults = isolatedDefaults()
        let first = ShoppingLocalStore(defaults: defaults, userID: "test-user", supportedStores: stores())
        first.setPreferredRetailerIDs(["nike", "macys"], supportedStores: stores())
        let diagnostics = RecordingShoppingDiagnostics()

        let relaunched = ShoppingLocalStore(
            defaults: defaults,
            userID: "test-user",
            supportedStores: stores(),
            diagnostics: diagnostics,
            diagnosticContext: context(2)
        )

        XCTAssertEqual(relaunched.preferredRetailerIDs, ["nike", "macys"])
        XCTAssertEqual(
            diagnostics.events.first?.payload,
            .preferencesInitialized(selectedCount: 2, source: .persisted, registryReady: true)
        )
    }

    func testObservationConstructionAndRenderRecreationEmitNothing() {
        let diagnostics = RecordingShoppingDiagnostics()
        let products = [makeProduct(id: "one", retailerID: "nike")]
        let policy = RetailerPreferencePolicy.apply(products: products, preferredRetailerIDs: ["nike"], supportedStores: stores())

        _ = ShoppingCatalogObservation.make(
            source: .remote,
            selectedRetailerIDs: ["nike"],
            supportedStores: stores(),
            inputProducts: products,
            policyResult: policy,
            eligibleCount: 1,
            recommendationCount: 1,
            displayedCount: 1,
            destination: .products
        )
        _ = ShoppingCatalogObservation.make(
            source: .remote,
            selectedRetailerIDs: ["nike"],
            supportedStores: stores(),
            inputProducts: products,
            policyResult: policy,
            eligibleCount: 1,
            recommendationCount: 1,
            displayedCount: 1,
            destination: .products
        )

        XCTAssertTrue(diagnostics.events.isEmpty)
    }

    func testDisplayFinalizedEmitsOnlyOnExplicitRecord() {
        let diagnostics = RecordingShoppingDiagnostics()
        let products = [makeProduct(id: "one", retailerID: "nike")]
        let policy = RetailerPreferencePolicy.apply(products: products, preferredRetailerIDs: ["nike"], supportedStores: stores())
        let observation = ShoppingCatalogObservation.make(
            source: .remote,
            selectedRetailerIDs: ["nike"],
            supportedStores: stores(),
            inputProducts: products,
            policyResult: policy,
            eligibleCount: 1,
            recommendationCount: 1,
            displayedCount: 1,
            destination: .products
        )
        observation.recordDisplay(context: context(1), diagnostics: diagnostics)

        XCTAssertEqual(diagnostics.events.map(\.name), ["display_finalized"])
        XCTAssertEqual(diagnostics.events.first?.metadata.loadGeneration, 1)
    }

    func testImpressionDeduplicationAndNewRoute() {
        let diagnostics = RecordingShoppingDiagnostics()
        let tracker = ShoppingImpressionTracker()
        let approved = Set(["nike"])

        XCTAssertTrue(tracker.recordIfNeeded(
            productID: "private-product-id",
            retailerID: "nike",
            approvedRetailerIDs: approved,
            surface: .productCard,
            position: 0,
            source: .remote,
            context: context(1),
            diagnostics: diagnostics
        ))
        XCTAssertFalse(tracker.recordIfNeeded(
            productID: "private-product-id",
            retailerID: "nike",
            approvedRetailerIDs: approved,
            surface: .productCard,
            position: 0,
            source: .remote,
            context: context(1),
            diagnostics: diagnostics
        ))
        let nextRoute = ShoppingDiagnosticContext(routeID: UUID(), loadGeneration: 1)
        XCTAssertTrue(tracker.recordIfNeeded(
            productID: "private-product-id",
            retailerID: "nike",
            approvedRetailerIDs: approved,
            surface: .productCard,
            position: 0,
            source: .remote,
            context: nextRoute,
            diagnostics: diagnostics
        ))

        XCTAssertEqual(diagnostics.events.count, 2)
        XCTAssertFalse(diagnostics.events[0].publicLogLine.contains("private-product-id"))
        XCTAssertNotEqual(diagnostics.events[0].metadata.routeID, diagnostics.events[1].metadata.routeID)
    }

    func testUnapprovedRetailerIDNeverEntersImpressionEvent() {
        let diagnostics = RecordingShoppingDiagnostics()
        _ = ShoppingImpressionTracker().recordIfNeeded(
            productID: "private-id",
            retailerID: "unapproved-retailer",
            approvedRetailerIDs: Set(["nike"]),
            surface: .compactCard,
            position: 1,
            source: .cache,
            context: context(1),
            diagnostics: diagnostics
        )

        XCTAssertEqual(
            diagnostics.events.first?.payload,
            .productImpression(surface: .compactCard, position: 1, retailerID: nil, source: .cache)
        )
    }

    func testPrivacyProhibitedValuesNeverEnterFormattedEvent() {
        let event = ShoppingDiagnosticEvent(
            context: context(1),
            payload: .shoppingError(
                stage: .remoteFetch,
                severity: .recoverable,
                recoverability: .retryable,
                classification: .http,
                errorDomain: "unsafe domain https://example.test?token=secret account@example.test",
                errorCode: 401
            )
        )
        let line = event.publicLogLine

        XCTAssertTrue(line.contains("error_domain=redacted"))
        for prohibited in ["https://", "token=", "secret", "account@example", "private-product-id"] {
            XCTAssertFalse(line.contains(prohibited))
        }
    }

    func testRouteCorrelationAndLoadGenerationArePresentOnEveryEvent() {
        let diagnostics = RecordingShoppingDiagnostics()
        let context = context(7)
        _ = RetailerPreferencePolicy.apply(
            products: [makeProduct(id: "nike", retailerID: "nike")],
            preferredRetailerIDs: ["nike"],
            supportedStores: stores(),
            diagnosticContext: context,
            diagnostics: diagnostics
        )

        XCTAssertFalse(diagnostics.events.isEmpty)
        XCTAssertTrue(diagnostics.events.allSatisfy { $0.metadata.routeID == routeID })
        XCTAssertTrue(diagnostics.events.allSatisfy { $0.metadata.loadGeneration == 7 })
        XCTAssertTrue(diagnostics.events.allSatisfy { $0.metadata.schemaVersion == 1 })
    }

    func testReleaseEnabledAdapterAndInjectableNoOpContracts() {
        XCTAssertTrue(ShoppingDiagnostics.unifiedLoggingEnabled)
        XCTAssertEqual(OSLogShoppingDiagnostics.subsystem, "com.sabastine.stylematchai")
        let noOp = NoOpShoppingDiagnostics()
        noOp.record(
            ShoppingDiagnosticEvent(
                context: context(1),
                payload: .catalogSourceSelected(source: .remote)
            )
        )
    }

    func testO2AShoppingBoundaryContainsNoDirectStdoutDiagnostics() throws {
        for path in [
            "StyleMatchAI/Shopping/ShoppingSearchProviders.swift",
            "StyleMatchAI/Shopping/AffiliateProduct.swift",
            "StyleMatchAI/Shopping/DisplayLabelSanitizer.swift",
            "StyleMatchAI/Shopping/SaleWatcher.swift",
            "StyleMatchAI/Shopping/StoreSearchView.swift"
        ] {
            let source = try projectSource(path)
            for prohibited in ["print(", "debugPrint(", "dump(", "NSLog("] {
                XCTAssertFalse(source.contains(prohibited), "\(path) contains \(prohibited)")
            }
        }
    }

    func testO2ARemovedDiagnosticPayloadsCannotEnterUnifiedLogging() throws {
        let sources = try [
            "StyleMatchAI/Shopping/ShoppingSearchProviders.swift",
            "StyleMatchAI/Shopping/AffiliateProduct.swift",
            "StyleMatchAI/Shopping/DisplayLabelSanitizer.swift",
            "StyleMatchAI/Shopping/SaleWatcher.swift",
            "StyleMatchAI/Shopping/StoreSearchView.swift"
        ].map(projectSource)
        let combined = sources.joined(separator: "\n")

        for removedDiagnostic in [
            "[KigoStylist Shopping Adapter Request]",
            "[KigoStylist Shopping Search]",
            "[KigoStylist Shopping Open]",
            "[KigoStylist Retailer Open]",
            "[KigoStylist Shopping LabelSanitizer]",
            "[KigoStylist SaleWatcher]",
            "[KigoStylist Store Search]"
        ] {
            XCTAssertFalse(combined.contains(removedDiagnostic))
        }

        let diagnosticsSource = try projectSource("StyleMatchAI/Shopping/ShoppingDiagnostics.swift")
        XCTAssertFalse(diagnosticsSource.contains("absoluteString"))
        XCTAssertFalse(diagnosticsSource.contains("localizedDescription"))
        XCTAssertFalse(diagnosticsSource.contains("debugDescription"))
    }

    func testO2BStylistAndChatBoundaryContainsNoDirectStdoutDiagnostics() throws {
        for path in [
            "StyleMatchAI/AIAssistantsView.swift",
            "StyleMatchAI/AIStyleAdvisor.swift",
            "StyleMatchAI/OpenAIStylistClient.swift",
            "StyleMatchAI/PersonalStylist/OutfitMemoryStore.swift",
            "StyleMatchAI/PersonalStylist/PersonalStylistSnapshotStore.swift",
            "StyleMatchAI/PersonalStylist/ProfileStore.swift",
            "StyleMatchAI/PersonalStylist/StylistContextBuilder.swift",
            "StyleMatchAI/StylistChat/ChatConversationStore.swift",
            "StyleMatchAI/StylistChat/StylistChatService.swift",
            "StyleMatchAI/StylistChat/StylistChatTransport.swift",
            "StyleMatchAI/StylistChat/StylistChatView.swift"
        ] {
            let source = try projectSource(path)
            for prohibited in ["print(", "debugPrint(", "dump(", "NSLog("] {
                XCTAssertFalse(source.contains(prohibited), "\(path) contains \(prohibited)")
            }
        }
    }

    func testO2BContentViewContainsNoStylistPayloadDiagnostics() throws {
        let source = try projectSource("StyleMatchAI/ContentView.swift")
        for removedDiagnostic in [
            "[Stylist Scan Handoff]",
            "[AI Stylist Chat]",
            "[Founder Beta AI Save]",
            "[Founder Beta AI Verify]"
        ] {
            XCTAssertFalse(source.contains(removedDiagnostic))
        }
    }

    func testO2CScanAndVisionBoundaryContainsNoStdoutDiagnostics() throws {
        for path in [
            "StyleMatchAI/ScanView.swift",
            "StyleMatchAI/GarmentColorPaletteEngine.swift"
        ] {
            let source = try projectSource(path)
            let lines = source.components(separatedBy: .newlines).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            for prohibitedPrefix in ["print(", "debugPrint(", "dump(", "NSLog("] {
                XCTAssertFalse(
                    lines.contains { $0.hasPrefix(prohibitedPrefix) },
                    "\(path) contains \(prohibitedPrefix)"
                )
            }
            XCTAssertFalse(source.contains("StyleMatchDebugLogEmitter.emit("))
        }
    }

    func testO2CRemovedScanPayloadMarkersAreAbsent() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")
        for removedDiagnostic in [
            "[ScanGate]",
            "[KigoStylist Score Debug]",
            "[KigoStylist Vision Debug]",
            "[KigoStylist Color Debug]",
            "[Scan AI Assist]",
            "[Scan AI Upgrade Prompt]",
            "[Scan ChatGPT Upgrade]"
        ] {
            XCTAssertFalse(source.contains(removedDiagnostic))
        }
    }

    func testO2ExitGateRejectsDirectAndWrappedDebugOutputAcrossApp() throws {
        let directSinkPattern = #"\b(?:print|debugPrint|dump|NSLog)\s*\("#
        let wrapperFunctionPattern = #"\bfunc\s+\w*(?:log\w*debug|debug\w*log|emit\w*debug|debug\w*emit)\w*\s*\("#
        let wrapperTypePattern = #"\b(?:class|struct|enum|actor)\s+\w*(?:debug\w*(?:log|emit)|(?:log|emit)\w*debug)\w*\b"#
        let prohibitedMarkers = [
            "StyleMatchDebugLogEmitter",
            "[KigoStylist Scan Debug]",
            "[KigoStylist AI Prompt Debug]",
            "fingerprintVersion=",
            "imageDigestPrefix="
        ]

        for (path, source) in try applicationSwiftSources() {
            XCTAssertNil(
                source.range(of: directSinkPattern, options: .regularExpression),
                "\(path) contains a direct stdout sink"
            )
            XCTAssertNil(
                source.range(of: wrapperFunctionPattern, options: [.regularExpression, .caseInsensitive]),
                "\(path) contains a debug-output wrapper function"
            )
            XCTAssertNil(
                source.range(of: wrapperTypePattern, options: [.regularExpression, .caseInsensitive]),
                "\(path) contains a debug-output wrapper type"
            )
            for marker in prohibitedMarkers {
                XCTAssertFalse(source.contains(marker), "\(path) contains prohibited marker \(marker)")
            }
        }
    }

    func testO2DAccountProfileAndLifecycleBoundaryContainsNoStdoutDiagnostics() throws {
        for path in [
            "StyleMatchAI/AccountService.swift",
            "StyleMatchAI/AppBackendConfiguration.swift",
            "StyleMatchAI/ContentView.swift",
            "StyleMatchAI/LoginWelcomeView.swift",
            "StyleMatchAI/ProfileView.swift",
            "StyleMatchAI/StyleMatchAIApp.swift"
        ] {
            let source = try projectSource(path)
            let lines = source.components(separatedBy: .newlines).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            for prohibitedPrefix in ["print(", "debugPrint(", "dump(", "NSLog("] {
                XCTAssertFalse(
                    lines.contains { $0.hasPrefix(prohibitedPrefix) },
                    "\(path) contains \(prohibitedPrefix)"
                )
            }
        }
    }

    func testO2DRemovedIdentityMeasurementAndURLMarkersAreAbsent() throws {
        let combined = try [
            "StyleMatchAI/AccountService.swift",
            "StyleMatchAI/AppBackendConfiguration.swift",
            "StyleMatchAI/LoginWelcomeView.swift",
            "StyleMatchAI/ProfileView.swift",
            "StyleMatchAI/StyleMatchAIApp.swift"
        ].map(projectSource).joined(separator: "\n")

        for removedDiagnostic in [
            "[ProfilePantsSize]",
            "[ProfileName]",
            "[KigoStylist Build Identity]",
            "[KigoStylist Account]",
            "[KigoStylist Runtime Backend]"
        ] {
            XCTAssertFalse(combined.contains(removedDiagnostic))
        }
    }

    func testRetailerRegistryUsesCanonicalIDAndStaticRepresentativeTiers() {
        let registry = RetailerCatalogRegistry(stores: retailerFoundationStores())

        XCTAssertEqual(registry.tier(retailerID: "NORDSTROM"), .luxuryMultiBrand)
        XCTAssertEqual(registry.tier(retailerID: "nike"), .athleticStreetwear)
        XCTAssertEqual(registry.tier(retailerID: "target"), .everydayValue)
        XCTAssertNil(registry.store(retailerID: "Nordstrom Flagship"))
    }

    func testTierEnrichmentDoesNotIntroduceDisplayNameIdentityInference() {
        let registry = RetailerCatalogRegistry(stores: retailerFoundationStores())

        XCTAssertEqual(registry.tier(retailerID: "adidas"), .athleticStreetwear)
        XCTAssertEqual(registry.tier(retailerID: "foot-locker"), .athleticStreetwear)
        XCTAssertEqual(registry.tier(retailerID: "macys"), .everydayValue)
        XCTAssertEqual(registry.tier(retailerID: "levis"), .everydayValue)
        XCTAssertEqual(registry.tier(retailerID: "zara"), .everydayValue)
        XCTAssertEqual(registry.tier(retailerID: "hm"), .everydayValue)
        XCTAssertNil(registry.store(retailerID: "Macy's"))
        XCTAssertNil(registry.store(retailerID: "Foot Locker"))
    }

    func testDirectoryPresenceDoesNotImplyVerifiedCommerce() {
        let registry = RetailerCatalogRegistry(stores: retailerFoundationStores())

        XCTAssertEqual(registry.linkCapability(retailerID: "nike"), .linkOnly)
        XCTAssertEqual(registry.commerceDataCapability(retailerID: "nike"), .unavailable)
        XCTAssertEqual(registry.linkCapability(retailerID: "amazon"), .approvedAffiliate)
        XCTAssertEqual(registry.commerceDataCapability(retailerID: "amazon"), .unavailable)
    }

    func testDesignerLuxuryDoesNotFallbackToLowerTier() {
        let registry = RetailerCatalogRegistry(stores: retailerFoundationStores())
        let result = registry.filter(
            products: [makeProduct(id: "target-1", retailerID: "target")],
            for: .designerLuxury
        )

        XCTAssertTrue(result.products.isEmpty)
        XCTAssertEqual(result.eligibility, .noEligibleRetailers)
    }

    func testDesignerLuxuryFilteringAdmitsOnlyLuxuryPilotRetailers() {
        let registry = RetailerCatalogRegistry(stores: retailerFoundationStores())
        let products = [
            makeProduct(id: "gucci-product", retailerID: "gucci"),
            makeProduct(id: "prada-product", retailerID: "prada"),
            makeProduct(id: "burberry-product", retailerID: "burberry"),
            makeProduct(id: "saint-laurent-product", retailerID: "saint-laurent"),
            makeProduct(id: "louis-vuitton-product", retailerID: "louis-vuitton"),
            makeProduct(id: "target-product", retailerID: "target")
        ]

        let result = registry.filter(products: products, for: .designerLuxury)

        XCTAssertEqual(
            Set(result.products.compactMap(\.retailerID)),
            ["gucci", "prada", "burberry", "saint-laurent", "louis-vuitton"]
        )
        XCTAssertEqual(result.eligibility, .eligible)
    }

    func testLuxuryMultiBrandFilteringAdmitsOnlyMultiBrandPilotRetailers() {
        let registry = RetailerCatalogRegistry(stores: retailerFoundationStores())
        let products = [
            makeProduct(id: "nordstrom-product", retailerID: "nordstrom"),
            makeProduct(id: "saks-product", retailerID: "saks-fifth-avenue"),
            makeProduct(id: "neiman-product", retailerID: "neiman-marcus"),
            makeProduct(id: "bloomingdales-product", retailerID: "bloomingdales"),
            makeProduct(id: "bergdorf-product", retailerID: "bergdorf-goodman"),
            makeProduct(id: "ssense-product", retailerID: "ssense"),
            makeProduct(id: "mr-porter-product", retailerID: "mr-porter"),
            makeProduct(id: "gucci-product", retailerID: "gucci"),
            makeProduct(id: "target-product", retailerID: "target")
        ]

        let result = registry.filter(products: products, for: .luxuryMultiBrand)

        XCTAssertEqual(
            Set(result.products.compactMap(\.retailerID)),
            ["nordstrom", "saks-fifth-avenue", "neiman-marcus", "bloomingdales", "bergdorf-goodman", "ssense", "mr-porter"]
        )
        XCTAssertEqual(result.eligibility, .eligible)
    }

    func testLuxuryMultiBrandDoesNotFallbackAcrossTiers() {
        let registry = RetailerCatalogRegistry(stores: retailerFoundationStores())
        let result = registry.filter(
            products: [
                makeProduct(id: "gucci-product", retailerID: "gucci"),
                makeProduct(id: "target-product", retailerID: "target")
            ],
            for: .luxuryMultiBrand
        )

        XCTAssertTrue(result.products.isEmpty)
        XCTAssertEqual(result.eligibility, .noEligibleRetailers)
    }

    func testAthleticStreetwearFilteringAdmitsOnlyAthleticStreetwearRetailers() {
        let registry = RetailerCatalogRegistry(stores: retailerFoundationStores())
        let products = [
            makeProduct(id: "nike-product", retailerID: "nike"),
            makeProduct(id: "adidas-product", retailerID: "adidas"),
            makeProduct(id: "foot-locker-product", retailerID: "foot-locker"),
            makeProduct(id: "gucci-product", retailerID: "gucci"),
            makeProduct(id: "nordstrom-product", retailerID: "nordstrom"),
            makeProduct(id: "target-product", retailerID: "target")
        ]

        let result = registry.filter(products: products, for: .athleticStreetwear)

        XCTAssertEqual(Set(result.products.compactMap(\.retailerID)), ["nike", "adidas", "foot-locker"])
        XCTAssertEqual(result.eligibility, .eligible)
    }

    func testAthleticStreetwearDoesNotFallbackAcrossTiers() {
        let registry = RetailerCatalogRegistry(stores: retailerFoundationStores())
        let result = registry.filter(
            products: [
                makeProduct(id: "gucci-product", retailerID: "gucci"),
                makeProduct(id: "nordstrom-product", retailerID: "nordstrom"),
                makeProduct(id: "target-product", retailerID: "target")
            ],
            for: .athleticStreetwear
        )

        XCTAssertTrue(result.products.isEmpty)
        XCTAssertEqual(result.eligibility, .noEligibleRetailers)
    }

    func testPremiumPreferenceRemainsBroaderThanLuxuryMultiBrand() {
        let registry = RetailerCatalogRegistry(stores: retailerFoundationStores())
        let products = [
            makeProduct(id: "gucci-product", retailerID: "gucci"),
            makeProduct(id: "nordstrom-product", retailerID: "nordstrom"),
            makeProduct(id: "target-product", retailerID: "target")
        ]

        let result = registry.filter(products: products, for: .premium)

        XCTAssertEqual(Set(result.products.compactMap(\.retailerID)), ["gucci", "nordstrom"])
        XCTAssertEqual(result.eligibility, .eligible)
    }

    func testTierPreferenceIsPureAndDoesNotMutateLocalStore() {
        let defaults = isolatedDefaults()
        let localStore = ShoppingLocalStore(defaults: defaults, userID: "tier-preference", supportedStores: stores())
        localStore.setPreferredRetailerIDs(["nike"], supportedStores: stores())
        let preferenceKey = PersonalStylistStorage.scopedKey("shoppingPreferredRetailerIDs", userID: "tier-preference")
        let before = defaults.stringArray(forKey: preferenceKey)

        _ = RetailerCatalogRegistry(stores: retailerFoundationStores()).filter(
            products: [makeProduct(id: "nike-1", retailerID: "nike")],
            for: .premium
        )

        XCTAssertEqual(defaults.stringArray(forKey: preferenceKey), before)
    }

    func testAffiliateCapabilityCannotChangeBestStyleMatchOrdering() {
        let products = [
            makeProduct(id: "alpha", retailerID: "amazon"),
            makeProduct(id: "beta", retailerID: "nike")
        ]
        let context = ShoppingRankingContext(memories: [])
        let first = ShoppingRecommendationEngine.rank(results: products, against: context)
        let second = ShoppingRecommendationEngine.rank(
            results: products,
            against: context,
            registry: RetailerCatalogRegistry(stores: retailerFoundationStores()),
            tierPreference: .unconstrained
        )

        XCTAssertEqual(second.rankedProducts.map(\.id), first.map(\.id))
    }

    func testRecommendationLabelsKeepPriceAndSaleClaimsUnavailable() {
        let registry = RetailerCatalogRegistry(stores: retailerFoundationStores())
        let labels = registry.eligibleLabels(retailerID: "nordstrom", supportsVersatility: true)

        XCTAssertTrue(labels.contains(.bestStyleMatch))
        XCTAssertTrue(labels.contains(.premiumChoice))
        XCTAssertTrue(labels.contains(.bestVersatility))
        XCTAssertTrue(labels.contains(.bestValueUnavailable))
        XCTAssertTrue(labels.contains(.budgetAlternativeUnavailable))
        XCTAssertFalse(labels.contains(.noPurchaseNeeded))
        XCTAssertEqual(registry.eligibleLabels(retailerID: nil, supportsVersatility: false, noPurchaseNeeded: true), [.noPurchaseNeeded])
    }

    func testTierResolvedProductPilotIsBoundedStaticRetailerCoverage() throws {
        let expectedIDs: Set<String> = [
            "gucci-840330aae801066-g75-sneaker",
            "prada-sc810-re-nylon-shirt",
            "ssense-hope-18999901-regular-fit-shirt",
            "ssense-hope-18998871-gray-short-sleeve-shirt",
            "nike-ah8050-005-air-max-270",
            "adidas-b75807-samba-og",
            "target-54190290-goodfellow-every-wear-tee",
            "levis-005010660-501-original-jeans"
        ]
        let products = try bundledProducts()
        let pilot = products.filter { expectedIDs.contains($0.id) }
        let registry = RetailerCatalogRegistry(stores: try bundledStores())

        XCTAssertEqual(products.count, 20)
        XCTAssertEqual(Set(products.map(\.id)).count, products.count)
        XCTAssertEqual(Set(pilot.map(\.id)), expectedIDs)
        XCTAssertEqual(products.filter { $0.retailerID == "amazon" }.count, 2)
        XCTAssertEqual(
            Set(products.filter { !expectedIDs.contains($0.id) }.compactMap(\.retailerID)),
            ["amazon", "best-buy", "foot-locker", "levis", "macys", "nike", "nordstrom", "target"]
        )
        XCTAssertEqual(products.filter { !expectedIDs.contains($0.id) }.map(\.id), legacyCatalogProductIDs)
        XCTAssertTrue(products.allSatisfy { product in
            product.retailerID.map { registry.store(retailerID: $0) != nil } ?? false
        })

        XCTAssertEqual(pilot.filter { registry.tier(retailerID: $0.retailerID) == .designerLuxury }.count, 2)
        XCTAssertEqual(pilot.filter { registry.tier(retailerID: $0.retailerID) == .luxuryMultiBrand }.count, 2)
        XCTAssertEqual(pilot.filter { registry.tier(retailerID: $0.retailerID) == .athleticStreetwear }.count, 2)
        XCTAssertEqual(pilot.filter { registry.tier(retailerID: $0.retailerID) == .everydayValue }.count, 2)

        XCTAssertEqual(pilot.first { $0.id == "gucci-840330aae801066-g75-sneaker" }?.subcategory, "sneakers")
        XCTAssertEqual(pilot.first { $0.id == "prada-sc810-re-nylon-shirt" }?.subcategory, "shirt")
        XCTAssertEqual(pilot.first { $0.id == "levis-005010660-501-original-jeans" }?.subcategory, "pants")
        XCTAssertEqual(pilot.first { $0.id == "nike-ah8050-005-air-max-270" }?.colors, ["black"])
        XCTAssertEqual(pilot.first { $0.id == "adidas-b75807-samba-og" }?.colors, ["black", "white"])

        let rawRecords = try rawCatalogRecords()
        for product in pilot {
            let record = try XCTUnwrap(rawRecords.first { $0["id"] as? String == product.id })
            for mutableKey in [
                "price", "priceRange", "salePrice", "saleEndsAt", "availability", "sizes",
                "shipping", "rating", "ratings", "stock", "imageURL"
            ] {
                XCTAssertNil(record[mutableKey], "\(product.id) unexpectedly includes \(mutableKey)")
            }
            XCTAssertNil(product.imageURL, product.id)
            XCTAssertNil(product.price, product.id)
            XCTAssertNil(product.priceRange, product.id)
            XCTAssertNil(product.salePrice, product.id)
            XCTAssertNil(product.saleEndsAt, product.id)
            XCTAssertNil(product.availability, product.id)
        }

        for tier in [
            ShoppingTierPreference.designerLuxury,
            .luxuryMultiBrand,
            .athleticStreetwear,
            .value
        ] {
            XCTAssertFalse(registry.filter(products: products, for: tier).products.isEmpty, "\(tier)")
        }
    }

    func testTierResolvedProductPilotUsesRetailerNeutralCompanionsAndKeepsValueClaimsUnavailable() throws {
        let products = try bundledProducts()
        let registry = RetailerCatalogRegistry(stores: try bundledStores())
        let gucci = try XCTUnwrap(products.first { $0.id == "gucci-840330aae801066-g75-sneaker" })
        let prada = try XCTUnwrap(products.first { $0.id == "prada-sc810-re-nylon-shirt" })
        let companions = CatalogProductComplementaryPieceRecommender().companions(
            for: gucci,
            catalog: [gucci, prada],
            limit: 6
        )

        XCTAssertEqual(companions.map(\.id), [prada.id])
        XCTAssertNotEqual(gucci.retailerID, prada.retailerID)
        for product in [gucci, prada] {
            let labels = registry.eligibleLabels(retailerID: product.retailerID, supportsVersatility: false)
            XCTAssertTrue(labels.contains(.bestValueUnavailable), product.id)
            XCTAssertTrue(labels.contains(.budgetAlternativeUnavailable), product.id)
        }
    }

    func testRetailerRegistryIsLocalOnlyAndDoesNotCreatePersonalShopperTransport() throws {
        let registry = try projectSource("StyleMatchAI/Shopping/RetailerCatalogRegistry.swift")

        for prohibitedMarker in ["URLSession", "UserDefaults", "ShoppingLocalStore", "ChatRequest", "ChatContext", "StylistAIOrchestrator", "AffiliateLinkBuilder"] {
            XCTAssertFalse(registry.contains(prohibitedMarker), "Registry unexpectedly contains \(prohibitedMarker)")
        }
        XCTAssertTrue(registry.contains("case luxuryMultiBrand"))
        XCTAssertTrue(registry.contains("case athleticStreetwear"))
        XCTAssertFalse(registry.contains("enum ShoppingTierPreference: Codable"))
    }

    func testShopV2PresentationKeepsRecommendationAuthorityAndTransportLocal() throws {
        let source = try projectSource("StyleMatchAI/Shopping/ShoppingView.swift")
        let rationaleStart = try XCTUnwrap(source.range(of: "private func premiumRationalePresentation"))
        let tierTitleStart = try XCTUnwrap(source.range(of: "private func shoppingDirectionTitle", range: rationaleStart.upperBound..<source.endIndex))
        let rationale = String(source[rationaleStart.lowerBound..<tierTitleStart.lowerBound])

        XCTAssertTrue(source.contains("private var shoppingConcierge"))
        XCTAssertTrue(source.contains("private var bestPicksSection"))
        XCTAssertTrue(source.contains("private var exploreSection"))
        XCTAssertTrue(source.contains("DisclosureGroup(\"Why KigoStylist picked this\")"))
        XCTAssertTrue(source.contains("recommendations.prefix(3)"))
        XCTAssertTrue(source.contains("ShoppingProductOpener.live().open("))
        XCTAssertTrue(rationale.contains("case .matchesWardrobe:"))
        XCTAssertTrue(rationale.contains("recommendation.reasonFacts.referencedOutfit"))
        XCTAssertTrue(rationale.contains("case .onSaleToday:"))
        XCTAssertTrue(rationale.contains("recommendation.product.salePrice == nil ? nil"))
        XCTAssertTrue(source.contains("premiumProductFitFacts(for: product)"))
        XCTAssertTrue(source.contains("Color-compatible with"))
        XCTAssertTrue(source.contains("Your saved size"))
        XCTAssertTrue(source.contains("Within your saved budget"))
        XCTAssertFalse(rationale.contains("ShoppingRecommendationEngine."))
        XCTAssertFalse(rationale.contains("ProfileStore("))
        XCTAssertFalse(rationale.contains("StylistChatService"))
        XCTAssertFalse(source.contains("ShoppingTierPreference: Codable"))
    }

    private func context(_ generation: Int) -> ShoppingDiagnosticContext {
        ShoppingDiagnosticContext(routeID: routeID, loadGeneration: generation)
    }

    private var legacyCatalogProductIDs: [String] {
        [
            "macys-white-oxford-001",
            "nike-white-sneaker-001",
            "footlocker-nike-airmax-001",
            "amazon-fabric-steamer-001",
            "bestbuy-smartwatch-001",
            "macys-black-belt-001",
            "target-umbrella-001",
            "nordstrom-navy-blazer-001",
            "levi-dark-denim-001",
            "amazon-sunglasses-001",
            "nike-gym-duffel-001",
            "macys-linen-shirt-001"
        ]
    }

    private func bundledProducts() throws -> [AffiliateProduct] {
        try BundledCatalogProvider.decodeProducts(
            catalogData: Data(contentsOf: projectURL("StyleMatchAI/Shopping/ProductCatalog.json")),
            retailerConfigData: Data(contentsOf: projectURL("StyleMatchAI/Shopping/RetailerConfig.json"))
        )
    }

    private func bundledStores() throws -> [SupportedStore] {
        try BundledStoreDirectoryProvider.decodeStores(
            Data(contentsOf: projectURL("StyleMatchAI/Shopping/SupportedStores.json"))
        )
    }

    private func rawCatalogRecords() throws -> [[String: Any]] {
        let data = try Data(contentsOf: projectURL("StyleMatchAI/Shopping/ProductCatalog.json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    }

    private func loadResult(
        source: ProductCatalogSource,
        products: [AffiliateProduct],
        classification: ProductCatalogFailureClassification? = nil,
        cacheHit: Bool = false
    ) -> ProductCatalogLoadResult {
        ProductCatalogLoadResult(
            products: products,
            source: source,
            diagnostic: ProductCatalogLoadDiagnostic(
                classification: classification,
                remoteProductCount: source == .remote ? products.count : nil,
                cacheHit: cacheHit,
                bundledFallbackCount: source == .bundled ? products.count : nil,
                finalSource: source
            )
        )
    }

    private func stores() -> [SupportedStore] {
        [
            SupportedStore(id: "nike", name: "Nike", domains: ["nike.com"], categories: [.shoes], affiliateNetwork: nil, apiStatus: "approved", isEnabled: true),
            SupportedStore(id: "macys", name: "Macy's", domains: ["macys.com"], categories: [.clothing], affiliateNetwork: nil, apiStatus: "approved", isEnabled: true),
            SupportedStore(id: "amazon", name: "Amazon", domains: ["amazon.com"], categories: [.clothing], affiliateNetwork: nil, apiStatus: "approved", isEnabled: true)
        ]
    }

    private func retailerFoundationStores() -> [SupportedStore] {
        [
            SupportedStore(id: "nordstrom", name: "Nordstrom", domains: ["nordstrom.com"], categories: [.clothing], affiliateNetwork: nil, apiStatus: "direct", isEnabled: true, tier: .luxuryMultiBrand, linkCapability: .linkOnly),
            SupportedStore(id: "nike", name: "Nike", domains: ["nike.com"], categories: [.shoes], affiliateNetwork: nil, apiStatus: "direct", isEnabled: true, tier: .athleticStreetwear, linkCapability: .linkOnly),
            SupportedStore(id: "target", name: "Target", domains: ["target.com"], categories: [.clothing], affiliateNetwork: nil, apiStatus: "direct", isEnabled: true, tier: .everydayValue, linkCapability: .linkOnly),
            SupportedStore(id: "adidas", name: "Adidas", domains: ["adidas.com"], categories: [.shoes], affiliateNetwork: nil, apiStatus: "direct", isEnabled: true, tier: .athleticStreetwear, linkCapability: .linkOnly),
            SupportedStore(id: "foot-locker", name: "Foot Locker", domains: ["footlocker.com"], categories: [.shoes], affiliateNetwork: nil, apiStatus: "direct", isEnabled: true, tier: .athleticStreetwear, linkCapability: .linkOnly),
            SupportedStore(id: "macys", name: "Macy's", domains: ["macys.com"], categories: [.clothing], affiliateNetwork: nil, apiStatus: "direct", isEnabled: true, tier: .everydayValue, linkCapability: .linkOnly),
            SupportedStore(id: "levis", name: "Levi's", domains: ["levi.com"], categories: [.clothing], affiliateNetwork: nil, apiStatus: "direct", isEnabled: true, tier: .everydayValue, linkCapability: .linkOnly),
            SupportedStore(id: "zara", name: "Zara", domains: ["zara.com"], categories: [.clothing], affiliateNetwork: nil, apiStatus: "direct", isEnabled: true, tier: .everydayValue, linkCapability: .linkOnly),
            SupportedStore(id: "hm", name: "H&M", domains: ["hm.com"], categories: [.clothing], affiliateNetwork: nil, apiStatus: "direct", isEnabled: true, tier: .everydayValue, linkCapability: .linkOnly),
            SupportedStore(id: "gucci", name: "Gucci", domains: ["gucci.com"], categories: [.clothing], affiliateNetwork: nil, apiStatus: "needs-approved-feed", isEnabled: true, tier: .designerLuxury, linkCapability: .linkOnly),
            SupportedStore(id: "prada", name: "Prada", domains: ["prada.com"], categories: [.clothing], affiliateNetwork: nil, apiStatus: "needs-approved-feed", isEnabled: true, tier: .designerLuxury, linkCapability: .linkOnly),
            SupportedStore(id: "burberry", name: "Burberry", domains: ["burberry.com"], categories: [.clothing], affiliateNetwork: nil, apiStatus: "needs-approved-feed", isEnabled: true, tier: .designerLuxury, linkCapability: .linkOnly),
            SupportedStore(id: "saint-laurent", name: "Saint Laurent", domains: ["ysl.com"], categories: [.clothing], affiliateNetwork: nil, apiStatus: "needs-approved-feed", isEnabled: true, tier: .designerLuxury, linkCapability: .linkOnly),
            SupportedStore(id: "louis-vuitton", name: "Louis Vuitton", domains: ["louisvuitton.com"], categories: [.clothing], affiliateNetwork: nil, apiStatus: "needs-approved-feed", isEnabled: true, tier: .designerLuxury, linkCapability: .linkOnly),
            SupportedStore(id: "saks-fifth-avenue", name: "Saks Fifth Avenue", domains: ["saksfifthavenue.com"], categories: [.clothing], affiliateNetwork: nil, apiStatus: "needs-approved-feed", isEnabled: true, tier: .luxuryMultiBrand, linkCapability: .linkOnly),
            SupportedStore(id: "neiman-marcus", name: "Neiman Marcus", domains: ["neimanmarcus.com"], categories: [.clothing], affiliateNetwork: nil, apiStatus: "needs-approved-feed", isEnabled: true, tier: .luxuryMultiBrand, linkCapability: .linkOnly),
            SupportedStore(id: "bloomingdales", name: "Bloomingdale's", domains: ["bloomingdales.com"], categories: [.clothing], affiliateNetwork: nil, apiStatus: "needs-approved-feed", isEnabled: true, tier: .luxuryMultiBrand, linkCapability: .linkOnly),
            SupportedStore(id: "bergdorf-goodman", name: "Bergdorf Goodman", domains: ["bergdorfgoodman.com"], categories: [.clothing], affiliateNetwork: nil, apiStatus: "needs-approved-feed", isEnabled: true, tier: .luxuryMultiBrand, linkCapability: .linkOnly),
            SupportedStore(id: "ssense", name: "SSENSE", domains: ["ssense.com"], categories: [.clothing], affiliateNetwork: nil, apiStatus: "needs-approved-feed", isEnabled: true, tier: .luxuryMultiBrand, linkCapability: .linkOnly),
            SupportedStore(id: "mr-porter", name: "MR PORTER", domains: ["mrporter.com"], categories: [.clothing], affiliateNetwork: nil, apiStatus: "needs-approved-feed", isEnabled: true, tier: .luxuryMultiBrand, linkCapability: .linkOnly),
            SupportedStore(id: "amazon", name: "Amazon", domains: ["amazon.com"], categories: [.clothing], affiliateNetwork: "Amazon Associates", apiStatus: "direct", isEnabled: true, linkCapability: .approvedAffiliate)
        ]
    }

    private func makeProduct(id: String, retailerID: String?) -> AffiliateProduct {
        AffiliateProduct(
            id: id,
            name: "Fixture product",
            category: .clothing,
            subcategory: "shirt",
            colors: ["navy"],
            retailerID: retailerID,
            retailer: Retailer(name: "Fixture retailer", trackingID: "fixture", trackingParamName: "tag", disclosureName: "Fixture retailer"),
            affiliateURL: URL(string: "https://api.stylematchpro.com/go/\(id)")!,
            price: 50,
            salePrice: nil,
            saleEndsAt: nil,
            availableColors: nil,
            customerRating: nil,
            reviewCount: nil,
            estimatedShippingText: nil,
            tags: [],
            genderPresentation: nil
        )
    }

    private func isolatedDefaults() -> UserDefaults {
        let suite = "ShoppingObservabilityTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func projectSource(_ relativePath: String) throws -> String {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let repositoryRoot = testFileURL.deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func projectURL(_ relativePath: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relativePath)
    }

    private func applicationSwiftSources() throws -> [(path: String, source: String)] {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let repositoryRoot = testFileURL.deletingLastPathComponent().deletingLastPathComponent()
        let applicationRoot = repositoryRoot.appendingPathComponent("StyleMatchAI", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: applicationRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw CocoaError(.fileReadUnknown)
        }

        return try enumerator.compactMap { entry in
            guard let url = entry as? URL,
                  url.pathExtension == "swift",
                  try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                return nil
            }
            let relativePath = url.path.replacingOccurrences(of: repositoryRoot.path + "/", with: "")
            return (relativePath, try String(contentsOf: url, encoding: .utf8))
        }
    }
}

private struct ResultProvider: ProductCatalogProvider, ProductCatalogSourceProviding {
    let result: ProductCatalogLoadResult

    func products() async throws -> [AffiliateProduct] {
        result.products
    }

    func loadResult() async -> ProductCatalogLoadResult {
        result
    }
}
