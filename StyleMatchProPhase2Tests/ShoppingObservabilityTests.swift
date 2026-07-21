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
            "[StyleMatch Shopping Adapter Request]",
            "[StyleMatch Shopping Search]",
            "[StyleMatch Shopping Open]",
            "[StyleMatch Retailer Open]",
            "[StyleMatch Shopping LabelSanitizer]",
            "[StyleMatch SaleWatcher]",
            "[StyleMatch Store Search]"
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
            "[StyleMatch Score Debug]",
            "[StyleMatch Vision Debug]",
            "[StyleMatch Color Debug]",
            "[Scan AI Assist]",
            "[Scan AI Upgrade Prompt]",
            "[Scan ChatGPT Upgrade]"
        ] {
            XCTAssertFalse(source.contains(removedDiagnostic))
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
            "[StyleMatch Build Identity]",
            "[StyleMatch Account]",
            "[StyleMatch Runtime Backend]"
        ] {
            XCTAssertFalse(combined.contains(removedDiagnostic))
        }
    }

    private func context(_ generation: Int) -> ShoppingDiagnosticContext {
        ShoppingDiagnosticContext(routeID: routeID, loadGeneration: generation)
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
