import XCTest
@testable import StyleMatchPro

final class AIMemoryManagerTests: XCTestCase {
    func testLegacyScreenContextDecodesWithoutSurface() throws {
        let data = Data("""
        {"currentTab":"ai","activeScanState":"none","entryPoint":"ai_tab","closetState":"unavailable"}
        """.utf8)

        let context = try JSONDecoder().decode(StylistScreenContext.self, from: data)

        XCTAssertNil(context.surface)
        XCTAssertEqual(context.currentTab, .ai)
    }

    func testEverySupportedSurfaceKindRoundTrips() throws {
        for kind in StylistScreenSurfaceKind.allCasesForTesting {
            let surface = StylistScreenSurfaceDescriptor(
                screenKind: kind,
                visibleSheetKind: "detail",
                navigationOrigin: .detail,
                selectedLocalRecordID: "record-1",
                selectedItemID: "item-1",
                selectedProductID: "product-1",
                selectedActionID: "ask_stylist",
                resultState: .saved,
                contextGeneration: 42,
                createdAt: Date(timeIntervalSince1970: 1)
            )
            XCTAssertEqual(try decode(encode(surface)), surface)
        }
    }

    func testGeneralStylistDropsRecordAuthorityByDefault() throws {
        let scan = try reference(.savedScan, "scan-a")
        let output = manager.resolve(input(
            scope: .generalStylist,
            explicit: fact(scan, .explicitSelection),
            available: [scan]
        ))

        XCTAssertNil(output.authoritativeReference)
        XCTAssertFalse(output.facts.contains { $0.category == .authoritativeReference })
    }

    func testExplicitContextAwareRouteResolvesExactAvailableReference() throws {
        let scan = try reference(.savedScan, "scan-a")
        let output = manager.resolve(input(
            scope: .init(kind: .savedScan, stableID: "scan-a"),
            explicit: fact(scan, .explicitSelection),
            summary: fact(StyleMemoryScanSummary(reference: scan, summary: "Saved score 82"), .explicitSelection),
            available: [scan]
        ))

        XCTAssertEqual(output.authoritativeReference, scan)
        XCTAssertTrue(output.facts.contains { $0.category == .scanSummary && $0.value == "Saved score 82" })
    }

    func testRapidNavigationRejectsStaleGeneration() throws {
        let surface = StylistScreenSurfaceDescriptor(screenKind: .savedScan, selectedLocalRecordID: "scan-b", contextGeneration: 2)
        let output = manager.resolve(input(
            screen: screen(surface),
            expectedGeneration: 1
        ))

        XCTAssertTrue(output.rejectedStaleContext)
        XCTAssertNil(output.contextGeneration)
        XCTAssertFalse(output.facts.contains { $0.category == .screen })
    }

    func testSelectedRecordItemAndProductIdentifiersRemainDistinct() {
        let surface = StylistScreenSurfaceDescriptor(
            screenKind: .shopping,
            selectedLocalRecordID: "scan-1",
            selectedItemID: "closet-1",
            selectedProductID: "product-1"
        )

        XCTAssertEqual(surface.selectedLocalRecordID, "scan-1")
        XCTAssertEqual(surface.selectedItemID, "closet-1")
        XCTAssertEqual(surface.selectedProductID, "product-1")
    }

    func testDeletedReferenceIsUnavailableAndNeverReplaced() throws {
        let target = try reference(.savedScan, "deleted")
        let other = try reference(.savedScan, "other")
        let output = manager.resolve(input(
            scope: .init(kind: .savedScan, stableID: "deleted"),
            explicit: fact(target, .explicitSelection),
            available: [other]
        ))

        XCTAssertTrue(output.unavailableReference)
        XCTAssertNil(output.authoritativeReference)
        XCTAssertFalse(output.facts.contains { $0.value.contains("other") })
    }

    func testExpiredCalendarAndWeatherAreExcluded() {
        let expired = Date(timeIntervalSince1970: 1)
        let output = manager.resolve(input(
            calendar: StyleMemoryFact(value: "raw event title", provenance: .authorizedCalendarEvent, observedAt: expired, expiresAt: expired, confidence: .confirmed, permission: .authorized, lifetime: .expiresAt),
            weather: StyleMemoryFact(value: "rain", provenance: .freshWeather, observedAt: expired, expiresAt: expired, confidence: .confirmed, lifetime: .expiresAt)
        ))

        XCTAssertFalse(output.facts.contains { $0.category == .calendar || $0.category == .weather })
    }

    func testManualCorrectionOutranksCalendarProjection() {
        let output = manager.resolve(input(
            manual: fact("Work", .manualOccasion),
            calendar: StyleMemoryFact(value: "Calendar event", provenance: .authorizedCalendarEvent, observedAt: Date(timeIntervalSince1970: 9), expiresAt: Date(timeIntervalSince1970: 20), confidence: .confirmed, permission: .authorized, lifetime: .expiresAt)
        ))
        let direct = StyleMemoryAuthorityResolver.resolve(
            StyleMemoryContextInput(
                identityScope: .guest,
                scope: .generalStylist,
                manualOccasion: fact("Work", .manualOccasion),
                calendarOccasion: StyleMemoryFact(value: "Calendar event", provenance: .authorizedCalendarEvent, observedAt: Date(timeIntervalSince1970: 9), expiresAt: Date(timeIntervalSince1970: 20), confidence: .confirmed, permission: .authorized, lifetime: .expiresAt)
            ), now: Date(timeIntervalSince1970: 10)
        )

        XCTAssertFalse(output.facts.contains { $0.value == "Calendar event" })
        XCTAssertEqual(direct.occasion.value, "Work")
    }

    func testBudgetOmitsLowPriorityFacts() {
        let tight = AIMemoryManager(budget: .init(maximumFactCount: 2, maximumSerializedCharacters: 256), now: { Date(timeIntervalSince1970: 10) })
        let output = tight.resolve(input(profile: fact("profile", .profile), workplace: fact("workplace", .profile)))

        XCTAssertEqual(output.facts.first?.category, .userMessage)
        XCTAssertTrue(output.omittedCategories.contains(.profile) || output.omittedCategories.contains(.workplace))
    }

    func testResolutionDoesNotCreatePersistentMemory() {
        let resolved = manager.resolve(input())
        let context = StyleMemoryAuthorityResolver.resolve(baseMemoryInput())

        XCTAssertFalse(StyleMemoryPersistenceBoundary.canPersist(context))
        XCTAssertFalse(resolved.facts.isEmpty)
    }

    func testTextAndVoiceCanResolveTheSameFactSet() throws {
        let scan = try reference(.activeScan, "live-1")
        let request = input(
            scope: .init(kind: .activeScan, stableID: "live-1"),
            explicit: fact(scan, .explicitSelection),
            available: [scan]
        )

        XCTAssertEqual(manager.resolve(request).facts, manager.resolve(request).facts)
    }

    func testResolvedPayloadCannotContainRawImagesOrOCRFields() throws {
        let payload = try String(decoding: encode(manager.resolve(input())), as: UTF8.self)

        XCTAssertFalse(payload.contains("imageData"))
        XCTAssertFalse(payload.contains("rawOCR"))
        XCTAssertFalse(payload.contains("calendarEvent"))
    }

    func testEverySurfaceAdapterProducesOnlyTheSelectedIdentifier() {
        XCTAssertEqual(StylistScreenSurfaceAdapters.home(cardID: "card", generation: 1).selectedLocalRecordID, "card")
        XCTAssertEqual(StylistScreenSurfaceAdapters.liveScan(scanID: "live", generation: 1).resultState, .live)
        XCTAssertEqual(StylistScreenSurfaceAdapters.savedScan(scanID: "saved", generation: 1).resultState, .saved)
        XCTAssertEqual(StylistScreenSurfaceAdapters.closet(itemID: "closet", generation: 1).selectedItemID, "closet")
        XCTAssertEqual(StylistScreenSurfaceAdapters.shopping(productID: "product", generation: 1).selectedProductID, "product")
        XCTAssertEqual(StylistScreenSurfaceAdapters.profile(sectionID: "appearance", generation: 1).selectedActionID, "appearance")
        XCTAssertEqual(StylistScreenSurfaceAdapters.settings(sectionID: "privacy", generation: 1).screenKind, .settings)
        XCTAssertEqual(StylistScreenSurfaceAdapters.scoreDetails(scanID: "scan", componentID: "fit", generation: 1).selectedActionID, "fit")
        XCTAssertEqual(StylistScreenSurfaceAdapters.sharedOutfit(sharedID: "share", generation: 1).screenKind, .sharedOutfit)
        XCTAssertEqual(StylistScreenSurfaceAdapters.calendar(generation: 1).screenKind, .calendar)
        XCTAssertEqual(StylistScreenSurfaceAdapters.weather(generation: 1).screenKind, .weather)
        XCTAssertEqual(StylistScreenSurfaceAdapters.favorites(itemID: "favorite", generation: 1).selectedItemID, "favorite")
        XCTAssertEqual(StylistScreenSurfaceAdapters.aiStylist(generation: 1).screenKind, .aiStylist)
    }

    func testExplicitRouteRejectsStaleGenerationAndDeletedReference() throws {
        let reference = try reference(.savedScan, "scan-1")
        let surface = StylistScreenSurfaceAdapters.savedScan(scanID: "scan-1", generation: 3)
        let route = try XCTUnwrap(StylistContextAwareRoute(
            screenContext: screen(surface),
            reference: reference
        ))

        XCTAssertFalse(route.isCurrent(generation: 2, availableReferences: [reference]))
        XCTAssertFalse(route.isCurrent(generation: 3, availableReferences: []))
        XCTAssertTrue(route.isCurrent(generation: 3, availableReferences: [reference]))
    }

    func testHomeContextualRoutePublishesOnlyBoundedCustomerVisibleContext() throws {
        let route = ScreenAwarenessSnapshot.home(generation: 7)
        let context = route.requestContext
        let encoded = try String(decoding: encode(context), as: UTF8.self)

        XCTAssertEqual(route.screenContext.surface?.screenKind, .home)
        XCTAssertNil(route.screenContext.surface?.selectedLocalRecordID)
        XCTAssertNil(route.screenContext.surface?.selectedItemID)
        XCTAssertNil(route.screenContext.surface?.selectedProductID)
        XCTAssertNil(context.screenContext)
        XCTAssertFalse(encoded.contains("profileName"))
        XCTAssertFalse(encoded.contains("imageData"))
        XCTAssertFalse(encoded.contains("rawOCR"))
        XCTAssertFalse(encoded.contains("locationName"))
        XCTAssertFalse(encoded.contains("contextGeneration"))
        XCTAssertFalse(encoded.contains("explicitContextualRoute"))
    }

    func testScreenAwarenessSnapshotCarriesOnlyTypedLocalFreshnessMetadata() throws {
        let capturedAt = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let snapshot = ScreenAwarenessSnapshot.home(generation: 7, capturedAt: capturedAt)

        XCTAssertEqual(snapshot.kind, .home)
        XCTAssertEqual(snapshot.displayTitle, "From Home")
        XCTAssertNil(snapshot.selectedSemanticEntityType)
        XCTAssertNil(snapshot.selectedOccasion)
        XCTAssertEqual(snapshot.capturedAt, capturedAt)
        XCTAssertFalse(snapshot.isCurrent(
            generation: 7,
            now: capturedAt.addingTimeInterval(15 * 60 + 1)
        ))
    }

    func testIntelligenceSnapshotGeneralFailsClosedForStaleScreenAndScanAuthority() throws {
        let capturedAt = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let staleHome = ScreenAwarenessSnapshot.home(generation: 3, capturedAt: capturedAt)
        let snapshot = StylistIntelligenceSnapshotBuilder.build(
            StylistIntelligenceSnapshotInput(
                conversationScope: .generalStylist,
                screenAwareness: staleHome,
                screenAwarenessGeneration: 4,
                exactScan: phase1CScan(id: "scan-should-not-leak"),
                generatedAt: capturedAt.addingTimeInterval(1)
            )
        )

        XCTAssertNil(snapshot.screen)
        XCTAssertNil(snapshot.activeScan)
        let encoded = try String(decoding: encode(snapshot.networkSafeContext(applying: ChatContext(
            activeScan: "stale scan text",
            scoreBreakdown: "stale score"
        ))), as: UTF8.self)
        XCTAssertFalse(encoded.contains("scan-should-not-leak"))
        XCTAssertFalse(encoded.contains("stale scan text"))
        XCTAssertFalse(encoded.contains("contextGeneration"))
    }

    func testIntelligenceSnapshotUsesExactScanAndNeverInheritsScreenAwareness() throws {
        var coordinator = StylistAwarenessCoordinator()
        _ = coordinator.publishHome(capturedAt: Date(timeIntervalSinceReferenceDate: 800_000_000))
        let exact = phase1CScan(id: "exact-scan")
        let snapshot = StylistIntelligenceSnapshotBuilder.build(
            StylistIntelligenceSnapshotInput(
                conversationScope: .activeScan(scanID: "exact-scan"),
                screenAwareness: coordinator.snapshot,
                screenAwarenessGeneration: coordinator.generation,
                exactScan: exact,
                generatedAt: Date(timeIntervalSinceReferenceDate: 800_000_001)
            )
        )

        XCTAssertEqual(snapshot.activeScan, exact)
        XCTAssertEqual(snapshot.latestScore?.fitQuality, 20)
        XCTAssertNil(snapshot.screen)
    }

    func testIntelligenceSnapshotReplacesClosetAuthorityAndProjectsNoLocalMetadata() throws {
        let suite = "AIMemoryManagerTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let itemA = ClosetItem(name: "Navy polo", category: "Shirt", color: "Navy", brand: "", size: "M", occasion: "Work", notes: "")
        let itemB = ClosetItem(name: "White shirt", category: "Shirt", color: "White", brand: "", size: "M", occasion: "Work", notes: "")
        defaults.set(try JSONEncoder().encode([itemA, itemB]), forKey: "closetItemsData")

        var coordinator = StylistAwarenessCoordinator()
        _ = try XCTUnwrap(coordinator.publishClosetItem(itemA, capturedAt: Date(timeIntervalSinceReferenceDate: 800_000_000)))
        let current = try XCTUnwrap(coordinator.publishClosetItem(itemB, capturedAt: Date(timeIntervalSinceReferenceDate: 800_000_001)))
        let snapshot = StylistIntelligenceSnapshotBuilder.build(
            StylistIntelligenceSnapshotInput(
                conversationScope: .generalStylist,
                screenAwareness: coordinator.snapshot,
                screenAwarenessGeneration: coordinator.generation,
                defaults: defaults,
                generatedAt: Date(timeIntervalSinceReferenceDate: 800_000_002)
            )
        )

        XCTAssertEqual(snapshot.screen, current)
        let encoded = try String(decoding: encode(snapshot.networkSafeContext(applying: ChatContext())), as: UTF8.self)
        XCTAssertTrue(encoded.contains("White shirt"))
        XCTAssertFalse(encoded.contains("Navy polo"))
        XCTAssertFalse(encoded.contains(itemB.id.uuidString))
        XCTAssertFalse(encoded.contains("selectedItemID"))
        XCTAssertFalse(encoded.contains("contextGeneration"))
        XCTAssertFalse(encoded.contains("workplaceEvidence"))
    }

    func testIntelligenceSnapshotThreadCorrectionOutranksPersistentWorkplace() throws {
        let persisted = phase1CWorkplace(environment: .office, source: .savedProfile)
        let correction = phase1CWorkplace(environment: .warehouseOrDistribution, source: .explicitThreadCorrection)
        let snapshot = StylistIntelligenceSnapshotBuilder.build(
            StylistIntelligenceSnapshotInput(
                conversationScope: .generalStylist,
                threadCorrection: StylistIntelligenceThreadCorrection(
                    workplace: correction,
                    customerVisibleFact: "I need safety-toe shoes at work."
                ),
                persistentWorkplace: persisted
            )
        )

        XCTAssertEqual(snapshot.workplace, correction)
        XCTAssertEqual(snapshot.workplaceEvidence, .userConfirmed)
        let encoded = try String(decoding: encode(snapshot.networkSafeContext(applying: ChatContext())), as: UTF8.self)
        XCTAssertTrue(encoded.contains("I need safety-toe shoes at work."))
        XCTAssertFalse(encoded.contains("explicitThreadCorrection"))
    }

    func testReconstructedThreadCorrectionIsBoundedAndOutranksOnlyWorkplaceProjection() throws {
        let state = StylistConversationState.reconstructing(messages: [
            ChatMessage(role: .user, content: "Actually, I work in a warehouse and need safety toe shoes.")
        ])
        let correction = try XCTUnwrap(state.intelligenceThreadCorrection)
        let persisted = phase1CWorkplace(environment: .office, source: .savedProfile)
        let exact = phase1CScan(id: "scan-exact")
        let snapshot = StylistIntelligenceSnapshotBuilder.build(
            StylistIntelligenceSnapshotInput(
                conversationScope: .activeScan(scanID: "scan-exact"),
                exactScan: exact,
                threadCorrection: correction,
                persistentWorkplace: persisted
            )
        )

        XCTAssertEqual(snapshot.workplace.environment, .warehouseOrDistribution)
        XCTAssertEqual(snapshot.activeScan?.scanID, "scan-exact")
        XCTAssertEqual(snapshot.activeScan?.overallScore, exact.overallScore)
        let encoded = try String(decoding: encode(snapshot.networkSafeContext(applying: ChatContext())), as: UTF8.self)
        XCTAssertTrue(encoded.contains("Workplace: warehouse or distribution"))
        XCTAssertFalse(encoded.contains("Actually, I work"))
        XCTAssertFalse(encoded.contains("localSemanticResponseID"))
    }

    func testIntelligenceSnapshotReadsCanonicalFreshWeatherWithoutPersistenceWrites() throws {
        let suite = "AIMemoryManagerTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let sentinel = Data("unchanged".utf8)
        defaults.set(sentinel, forKey: "profile")
        defaults.set(sentinel, forKey: "outfitScanHistoryData")
        defaults.set(sentinel, forKey: "aiMemory")
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let weather = try XCTUnwrap(phase1CWeather(observedAt: now))
        let fresh = StylistIntelligenceSnapshotBuilder.build(
            StylistIntelligenceSnapshotInput(
                conversationScope: .generalStylist,
                weather: weather,
                defaults: defaults,
                generatedAt: now
            )
        )
        let stale = StylistIntelligenceSnapshotBuilder.build(
            StylistIntelligenceSnapshotInput(
                conversationScope: .generalStylist,
                weather: weather,
                defaults: defaults,
                generatedAt: now.addingTimeInterval(StylistIntelligenceSnapshotBuilder.maximumWeatherAge + 1)
            )
        )

        XCTAssertEqual(fresh.weather, weather)
        XCTAssertEqual(fresh.weatherEvidence, .observed)
        XCTAssertNil(stale.weather)
        XCTAssertEqual(defaults.data(forKey: "profile"), sentinel)
        XCTAssertEqual(defaults.data(forKey: "outfitScanHistoryData"), sentinel)
        XCTAssertEqual(defaults.data(forKey: "aiMemory"), sentinel)

        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let models = try String(contentsOf: root.appendingPathComponent("StyleMatchAI/StylistChat/StylistChatModels.swift"), encoding: .utf8)
        XCTAssertTrue(models.contains("struct StylistIntelligenceSnapshot: Equatable"))
        XCTAssertFalse(models.contains("struct StylistIntelligenceSnapshot: Codable"))
    }

    func testIntelligenceSnapshotAdmissionsPreserveLocalProvenanceWithoutTransportOrPersistence() throws {
        let suite = "AIMemoryManagerTests-Admissions-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let sentinel = Data("unchanged".utf8)
        defaults.set(sentinel, forKey: "aiMemory")

        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let product = phase1DProduct(
            id: "catalog-polo",
            name: "Navy polo",
            colors: ["Navy"],
            price: 65,
            currency: "USD"
        )
        let productScreen = try XCTUnwrap(ScreenAwarenessSnapshot.shoppingProduct(
            product,
            generation: 3,
            capturedAt: now
        ))
        let correction = phase1CWorkplace(
            environment: .warehouseOrDistribution,
            source: .explicitThreadCorrection
        )
        let snapshot = StylistIntelligenceSnapshotBuilder.build(
            StylistIntelligenceSnapshotInput(
                conversationScope: .generalStylist,
                screenAwareness: productScreen,
                screenAwarenessGeneration: 3,
                threadCorrection: StylistIntelligenceThreadCorrection(workplace: correction),
                availableShoppingProductIDs: [product.id],
                weather: try XCTUnwrap(phase1CWeather(observedAt: now)),
                defaults: defaults,
                generatedAt: now
            )
        )

        func admission(_ domain: StylistIntelligenceFactDomain) throws -> StylistIntelligenceAdmission {
            try XCTUnwrap(snapshot.admissions.first(where: { $0.domain == domain }))
        }

        let scan = try admission(.scan)
        XCTAssertEqual(scan.decision, .unavailable)
        XCTAssertEqual(scan.reason, .missingAuthoritativeScan)
        XCTAssertEqual(scan.provenance, .unavailableOrUnverified)
        XCTAssertEqual(scan.invalidationStatus, .unavailable)
        XCTAssertEqual(scan.networkEligibility, .ineligible)

        let productAdmission = try admission(.productConsideration)
        XCTAssertEqual(productAdmission.decision, .admitted)
        XCTAssertNil(productAdmission.reason)
        XCTAssertEqual(productAdmission.sourceCategory, .productContextV1)
        XCTAssertEqual(productAdmission.provenance, .customerConfirmedFact)
        XCTAssertTrue(productAdmission.customerConfirmed)

        let correctionAdmission = try admission(.threadCorrection)
        XCTAssertEqual(correctionAdmission.sourceCategory, .currentThread)
        XCTAssertEqual(correctionAdmission.provenance, .customerConfirmedFact)

        let weatherAdmission = try admission(.weather)
        XCTAssertEqual(weatherAdmission.decision, .admitted)
        XCTAssertEqual(weatherAdmission.sourceCategory, .weatherKit)
        XCTAssertEqual(weatherAdmission.provenance, .currentExternalInformation)
        XCTAssertEqual(weatherAdmission.invalidationStatus, .valid)

        let encoded = try String(decoding: encode(snapshot.networkSafeContext(applying: ChatContext())), as: UTF8.self)
        XCTAssertFalse(encoded.contains("admissions"))
        XCTAssertFalse(encoded.contains("productContextV1"))
        XCTAssertFalse(encoded.contains("currentExternalInformation"))
        XCTAssertEqual(defaults.data(forKey: "aiMemory"), sentinel)
        XCTAssertTrue(snapshot.admissions.allSatisfy {
            $0.persistenceEligibility == StylistIntelligencePersistenceEligibility.neverPersist
        })
    }

    func testHubAdmissionClassifiesExactIncompleteAndMismatchedScanAuthority() throws {
        let exact = phase1CScan(id: "hub-exact-scan")
        let admitted = StylistIntelligenceSnapshotBuilder.build(
            StylistIntelligenceSnapshotInput(
                conversationScope: .activeScan(scanID: "hub-exact-scan"),
                exactScan: exact
            )
        )
        let admittedRecord = try XCTUnwrap(admitted.admissions.first { $0.domain == .scan })
        XCTAssertEqual(admittedRecord.decision, .admitted)
        XCTAssertNil(admittedRecord.reason)

        let mismatched = StylistIntelligenceSnapshotBuilder.build(
            StylistIntelligenceSnapshotInput(
                conversationScope: .activeScan(scanID: "expected-scan"),
                exactScan: exact
            )
        )
        let mismatchedRecord = try XCTUnwrap(mismatched.admissions.first { $0.domain == .scan })
        XCTAssertEqual(mismatchedRecord.decision, .rejected)
        XCTAssertEqual(mismatchedRecord.reason, .scanScopeMismatch)
        XCTAssertNil(mismatched.activeScan)

        let incomplete = StylistIntelligenceSnapshotBuilder.build(
            StylistIntelligenceSnapshotInput(
                conversationScope: .activeScan(scanID: ""),
                exactScan: StylistAuthoritativeScanContext(
                    scanID: "",
                    completedAt: Date(),
                    overallScore: 80,
                    scoreBreakdown: nil,
                    source: .liveCompleted
                )
            )
        )
        let incompleteRecord = try XCTUnwrap(incomplete.admissions.first { $0.domain == .scan })
        XCTAssertEqual(incompleteRecord.decision, .unavailable)
        XCTAssertEqual(incompleteRecord.reason, .incompleteAuthoritativeScan)
    }

    func testHubAdmissionClassifiesStaleScreenAndInvalidatedClosetAndProduct() throws {
        let suite = "AIMemoryManagerTests-HubAdmission-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let item = ClosetItem(name: "Navy polo", category: "Shirt", color: "Navy", brand: "", size: "M", occasion: "Work", notes: "")
        let closet = try XCTUnwrap(ScreenAwarenessSnapshot.closetItem(item, generation: 1, capturedAt: now))
        let missingCloset = StylistIntelligenceSnapshotBuilder.build(
            StylistIntelligenceSnapshotInput(
                conversationScope: .generalStylist,
                screenAwareness: closet,
                screenAwarenessGeneration: 1,
                defaults: defaults,
                generatedAt: now
            )
        )
        let missingClosetRecord = try XCTUnwrap(missingCloset.admissions.first { $0.domain == .screenAwareness })
        XCTAssertEqual(missingClosetRecord.decision, .invalidated)
        XCTAssertEqual(missingClosetRecord.reason, .closetItemUnavailable)

        let product = phase1DProduct(id: "hub-product", name: "Navy polo", colors: ["Navy"], price: 65, currency: "USD")
        let productScreen = try XCTUnwrap(ScreenAwarenessSnapshot.shoppingProduct(product, generation: 3, capturedAt: now))
        let missingProduct = StylistIntelligenceSnapshotBuilder.build(
            StylistIntelligenceSnapshotInput(
                conversationScope: .generalStylist,
                screenAwareness: productScreen,
                screenAwarenessGeneration: 3,
                availableShoppingProductIDs: [],
                generatedAt: now
            )
        )
        let missingProductRecord = try XCTUnwrap(missingProduct.admissions.first { $0.domain == .productConsideration })
        XCTAssertEqual(missingProductRecord.decision, .invalidated)
        XCTAssertEqual(missingProductRecord.reason, .productNoLongerAvailable)
        XCTAssertNil(missingProduct.screen)

        let staleProduct = StylistIntelligenceSnapshotBuilder.build(
            StylistIntelligenceSnapshotInput(
                conversationScope: .generalStylist,
                screenAwareness: productScreen,
                screenAwarenessGeneration: 4,
                availableShoppingProductIDs: [product.id],
                generatedAt: now
            )
        )
        let staleProductRecord = try XCTUnwrap(staleProduct.admissions.first { $0.domain == .productConsideration })
        XCTAssertEqual(staleProductRecord.decision, .stale)
        XCTAssertEqual(staleProductRecord.reason, .staleScreenGeneration)

        let stale = StylistIntelligenceSnapshotBuilder.build(
            StylistIntelligenceSnapshotInput(
                conversationScope: .generalStylist,
                screenAwareness: ScreenAwarenessSnapshot.home(generation: 4, capturedAt: now),
                screenAwarenessGeneration: 5,
                generatedAt: now
            )
        )
        let staleRecord = try XCTUnwrap(stale.admissions.first { $0.domain == .screenAwareness })
        XCTAssertEqual(staleRecord.decision, .stale)
        XCTAssertEqual(staleRecord.reason, .staleScreenGeneration)
        let staleNonProductRecord = try XCTUnwrap(stale.admissions.first { $0.domain == .productConsideration })
        XCTAssertEqual(staleNonProductRecord.decision, .unavailable)
        XCTAssertEqual(staleNonProductRecord.reason, .noActiveProductContext)
    }

    func testHubAdmissionNeverAdmitsProductFromValidHomeClosetOrProfile() throws {
        let suite = "AIMemoryManagerTests-HubNonProduct-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let closetItem = ClosetItem(name: "Navy polo", category: "Shirt", color: "Navy", brand: "", size: "M", occasion: "Work", notes: "")
        defaults.set(try JSONEncoder().encode([closetItem]), forKey: "closetItemsData")
        let profile = StylistProfileContextProjection(stylePreferences: "Tailored navy basics")
        let candidates: [ScreenAwarenessSnapshot] = [
            .home(generation: 1, capturedAt: now),
            try XCTUnwrap(ScreenAwarenessSnapshot.closetItem(closetItem, generation: 2, capturedAt: now)),
            .profile(profile, generation: 3, capturedAt: now)
        ]

        for candidate in candidates {
            let snapshot = StylistIntelligenceSnapshotBuilder.build(
                StylistIntelligenceSnapshotInput(
                    conversationScope: .generalStylist,
                    screenAwareness: candidate,
                    screenAwarenessGeneration: candidate.generation,
                    defaults: defaults,
                    generatedAt: now
                )
            )
            let productRecord = try XCTUnwrap(snapshot.admissions.first { $0.domain == .productConsideration })
            XCTAssertEqual(productRecord.sourceCategory, .unavailable)
            XCTAssertEqual(productRecord.decision, .unavailable)
            XCTAssertEqual(productRecord.reason, .noActiveProductContext)
            XCTAssertFalse(productRecord.customerConfirmed)
        }
    }

    func testHubAdmissionClassifiesWeatherFreshnessWithoutChangingProjection() throws {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let weather = try XCTUnwrap(phase1CWeather(observedAt: now))
        let future = StylistIntelligenceSnapshotBuilder.build(
            StylistIntelligenceSnapshotInput(
                conversationScope: .generalStylist,
                weather: weather,
                generatedAt: now.addingTimeInterval(-1)
            )
        )
        let futureRecord = try XCTUnwrap(future.admissions.first { $0.domain == .weather })
        XCTAssertEqual(futureRecord.decision, .rejected)
        XCTAssertEqual(futureRecord.reason, .weatherObservedInFuture)
        XCTAssertNil(future.weather)

        let stale = StylistIntelligenceSnapshotBuilder.build(
            StylistIntelligenceSnapshotInput(
                conversationScope: .generalStylist,
                weather: weather,
                generatedAt: now.addingTimeInterval(StylistIntelligenceSnapshotBuilder.maximumWeatherAge + 1)
            )
        )
        let staleRecord = try XCTUnwrap(stale.admissions.first { $0.domain == .weather })
        XCTAssertEqual(staleRecord.decision, .stale)
        XCTAssertEqual(staleRecord.reason, .staleWeather)

        let encoded = try String(decoding: encode(stale.networkSafeContext(applying: ChatContext())), as: UTF8.self)
        XCTAssertFalse(encoded.contains("admission"))
        XCTAssertFalse(encoded.contains("staleWeather"))
    }

    func testIntelligenceSnapshotAdmissionsClassifyExactScanAndConfirmedProfile() throws {
        let scan = phase1CScan(id: "admitted-exact-scan")
        let profileWorkplace = phase1CWorkplace(environment: .office, source: .savedProfile)
        let snapshot = StylistIntelligenceSnapshotBuilder.build(
            StylistIntelligenceSnapshotInput(
                conversationScope: .savedScan(scanID: "admitted-exact-scan"),
                exactScan: scan,
                persistentWorkplace: profileWorkplace,
                styleProfileSummary: "Prefers tailored navy basics"
            )
        )

        let scanAdmission = try XCTUnwrap(snapshot.admissions.first { $0.domain == .scan })
        XCTAssertEqual(scanAdmission.sourceCategory, .exactScanAuthority)
        XCTAssertEqual(scanAdmission.provenance, .authoritativeFact)
        XCTAssertEqual(scanAdmission.invalidationStatus, .valid)

        let profileAdmission = try XCTUnwrap(snapshot.admissions.first { $0.domain == .profile })
        XCTAssertEqual(profileAdmission.sourceCategory, .confirmedProfile)
        XCTAssertEqual(profileAdmission.provenance, .customerConfirmedFact)
        XCTAssertTrue(profileAdmission.customerConfirmed)

        let workplaceAdmission = try XCTUnwrap(snapshot.admissions.first { $0.domain == .workplace })
        XCTAssertEqual(workplaceAdmission.sourceCategory, .confirmedProfile)
        XCTAssertEqual(workplaceAdmission.provenance, .customerConfirmedFact)
        XCTAssertTrue(workplaceAdmission.customerConfirmed)
    }

    func testClosetContextualRouteKeepsExactLocalReferenceOutOfOutboundContext() throws {
        let item = ClosetItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "Navy polo",
            category: "Shirt",
            color: "Navy",
            brand: "",
            size: "M",
            occasion: "Work",
            notes: ""
        )
        let route = try XCTUnwrap(ScreenAwarenessSnapshot.closetItem(item, generation: 8))
        let encoded = try String(decoding: encode(route.requestContext), as: UTF8.self)

        XCTAssertEqual(route.localReference?.stableID, item.id.uuidString)
        XCTAssertEqual(route.screenContext.surface?.screenKind, .closet)
        XCTAssertNil(route.requestContext.screenContext)
        XCTAssertTrue(route.requestContext.recentOutfits.contains("Navy polo"))
        XCTAssertFalse(encoded.contains(item.id.uuidString))
        XCTAssertFalse(encoded.contains("selectedItemID"))
        XCTAssertFalse(encoded.contains("contextGeneration"))
    }

    func testShoppingProductContextUsesDedicatedBoundedProjectionAndMatchesV1Fixture() throws {
        let product = phase1DProduct(
            id: "internal-product-id",
            name: "Navy Performance Polo",
            colors: ["Navy"],
            price: 64,
            currency: "USD"
        )
        let route = try XCTUnwrap(ScreenAwarenessSnapshot.shoppingProduct(product, generation: 4))
        let context = route.requestContext
        let encoded = try JSONEncoder().encode(context)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let actual = try XCTUnwrap(root["productContext"] as? [String: Any])
        let fixtureURL = try XCTUnwrap(Bundle.module.url(forResource: "stylist_product_context_v1", withExtension: "json"))
        let expected = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL)) as? [String: Any])

        XCTAssertEqual(actual as NSDictionary, expected as NSDictionary)
        XCTAssertEqual(route.localReference?.stableID, "internal-product-id")
        XCTAssertEqual(route.screenContext.surface?.selectedProductID, "internal-product-id")
        XCTAssertTrue(context.recentOutfits.isEmpty)
        XCTAssertNil(context.screenContext)
    }

    func testShoppingProductContextExcludesLocalAffiliateAndCatalogMetadata() throws {
        let product = phase1DProduct(
            id: "internal-product-id",
            name: "Navy Performance Polo",
            colors: ["Navy", "Blue"],
            price: 64,
            currency: "USD"
        )
        let route = try XCTUnwrap(ScreenAwarenessSnapshot.shoppingProduct(product, generation: 7))
        let encoded = try String(decoding: encode(route.requestContext), as: UTF8.self)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(encoded.utf8)) as? [String: Any])
        let productJSON = try XCTUnwrap(root["productContext"] as? [String: Any])
        let productEncoded = try JSONSerialization.data(withJSONObject: productJSON)
        let productText = String(decoding: productEncoded, as: UTF8.self)

        XCTAssertFalse(encoded.contains("internal-product-id"))
        XCTAssertFalse(productText.contains("affiliate.example"))
        XCTAssertFalse(productText.contains("retailer-internal"))
        XCTAssertFalse(productText.contains("tracking"))
        XCTAssertFalse(productText.contains("availability"))
        XCTAssertFalse(productText.contains("availableColors"))
        XCTAssertFalse(productText.contains("tags"))
        XCTAssertFalse(encoded.contains("selectedProductID"))
        XCTAssertFalse(encoded.contains("contextGeneration"))
        XCTAssertFalse(encoded.contains("displayedColor"), "Ambiguous catalog colors must not imply a selected variant")
    }

    func testShoppingProductReplacementAndDeletionFailClosedWithoutFallback() throws {
        let productA = phase1DProduct(id: "product-a", name: "Navy polo", colors: ["Navy"], price: 64, currency: "USD")
        let productB = phase1DProduct(id: "product-b", name: "White polo", colors: ["White"], price: 72, currency: "USD")
        var coordinator = StylistAwarenessCoordinator()
        let routeA = try XCTUnwrap(coordinator.publishShoppingProduct(productA))
        let routeB = try XCTUnwrap(coordinator.publishShoppingProduct(productB))

        XCTAssertFalse(routeA.isCurrent(generation: coordinator.generation, availableShoppingProductIDs: ["product-a", "product-b"]))
        XCTAssertTrue(routeB.isCurrent(generation: coordinator.generation, availableShoppingProductIDs: ["product-a", "product-b"]))
        XCTAssertFalse(routeB.isCurrent(generation: coordinator.generation, availableShoppingProductIDs: ["product-a"]))
        XCTAssertFalse(routeB.requestContext.recentOutfits.contains("White polo"))
        coordinator.clear()
        XCTAssertNil(coordinator.snapshot)
    }

    func testScanAuthorityClearsShoppingProductContext() throws {
        let product = phase1DProduct(id: "product-a", name: "Navy polo", colors: ["Navy"], price: 64, currency: "USD")
        let productContext = try XCTUnwrap(ScreenAwarenessSnapshot.shoppingProduct(product, generation: 1)).requestContext.productContext
        let scan = phase1CScan(id: "exact-scan")
        let snapshot = StylistIntelligenceSnapshotBuilder.build(
            StylistIntelligenceSnapshotInput(
                conversationScope: .activeScan(scanID: "exact-scan"),
                exactScan: scan
            )
        )
        let context = snapshot.networkSafeContext(applying: ChatContext(productContext: productContext))

        XCTAssertNil(context.productContext)
        XCTAssertTrue(context.activeScan.contains("exact-scan"))
    }

    @MainActor
    func testOverlaySessionKeepsSameRouteInMemoryAndResetsUnrelatedProductAuthority() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("StylistOverlaySessionTests-\(UUID().uuidString).json")
        defer {
            try? FileManager.default.removeItem(at: storeURL)
            try? FileManager.default.removeItem(at: storeURL.appendingPathExtension("bak"))
        }
        let service = StylistChatService(store: ChatConversationStore(fileURL: storeURL))
        let overlay = StylistOverlaySessionCoordinator(service: service)
        let productA = try XCTUnwrap(ScreenAwarenessSnapshot.shoppingProduct(
            phase1DProduct(id: "product-a", name: "Navy polo", colors: ["Navy"], price: 64, currency: "USD"),
            generation: 1
        ))
        let productB = try XCTUnwrap(ScreenAwarenessSnapshot.shoppingProduct(
            phase1DProduct(id: "product-b", name: "White polo", colors: ["White"], price: 72, currency: "USD"),
            generation: 2
        ))

        overlay.presentScreenAwareness(productA)
        let productAConversationID = service.activeConversation.id
        overlay.dismiss()
        overlay.presentScreenAwareness(productA)

        XCTAssertEqual(service.activeConversation.id, productAConversationID)
        XCTAssertEqual(overlay.route, .screenAwareness(generation: 1, reference: productA.localReference))

        overlay.presentScreenAwareness(productB)

        XCTAssertNotEqual(service.activeConversation.id, productAConversationID)
        XCTAssertEqual(overlay.route, .screenAwareness(generation: 2, reference: productB.localReference))
        XCTAssertTrue(ChatConversationStore(fileURL: storeURL).conversations.isEmpty)
    }

    @MainActor
    func testOverlaySessionGeneralReopenIsEphemeralAndDoesNotPersistPresentation() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("StylistOverlayGeneralTests-\(UUID().uuidString).json")
        defer {
            try? FileManager.default.removeItem(at: storeURL)
            try? FileManager.default.removeItem(at: storeURL.appendingPathExtension("bak"))
        }
        let service = StylistChatService(store: ChatConversationStore(fileURL: storeURL))
        let overlay = StylistOverlaySessionCoordinator(service: service)

        overlay.presentGeneral()
        let generalConversationID = service.activeConversation.id
        overlay.dismiss()
        overlay.presentGeneral()

        XCTAssertEqual(service.activeConversation.id, generalConversationID)
        XCTAssertEqual(overlay.route, .general)
        XCTAssertTrue(ChatConversationStore(fileURL: storeURL).conversations.isEmpty)
    }

    @MainActor
    func testOverlaySessionFloatingControlPresentationIsLocalAndDoesNotChangeRouteOrConversation() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("StylistFloatingControlTests-\(UUID().uuidString).json")
        let defaultsSuite = "StylistFloatingControlTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuite))
        defer {
            try? FileManager.default.removeItem(at: storeURL)
            try? FileManager.default.removeItem(at: storeURL.appendingPathExtension("bak"))
            defaults.removePersistentDomain(forName: defaultsSuite)
        }
        let service = StylistChatService(store: ChatConversationStore(fileURL: storeURL))
        let overlay = StylistOverlaySessionCoordinator(service: service, floatingControlEdgeDefaults: defaults)

        overlay.presentGeneral()
        let conversationID = service.activeConversation.id
        let route = overlay.route
        let messages = service.activeConversation.messages

        overlay.collapseFloatingControl(toward: .leading)

        XCTAssertEqual(overlay.floatingControlPresentation, .collapsed(edge: .leading))
        XCTAssertTrue(overlay.isPresented)
        XCTAssertEqual(overlay.route, route)
        XCTAssertEqual(service.activeConversation.id, conversationID)
        XCTAssertEqual(service.activeConversation.messages, messages)
        XCTAssertTrue(ChatConversationStore(fileURL: storeURL).conversations.isEmpty)

        overlay.expandFloatingControl()

        XCTAssertEqual(overlay.floatingControlPresentation, .expanded(edge: .leading))
        XCTAssertTrue(overlay.isPresented)
        XCTAssertEqual(overlay.route, route)
        XCTAssertEqual(service.activeConversation.id, conversationID)
        XCTAssertEqual(service.activeConversation.messages, messages)
        XCTAssertTrue(ChatConversationStore(fileURL: storeURL).conversations.isEmpty)
    }

    @MainActor
    func testOverlaySessionFloatingControlExpansionKeepsSelectedEdge() throws {
        let defaultsSuite = "StylistFloatingExpansionTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuite))
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }
        let overlay = StylistOverlaySessionCoordinator(service: StylistChatService(), floatingControlEdgeDefaults: defaults)

        XCTAssertEqual(overlay.floatingControlPresentation, .expanded(edge: .trailing))
        overlay.collapseFloatingControl(toward: .trailing)
        overlay.expandFloatingControl()

        XCTAssertEqual(overlay.floatingControlPresentation, .expanded(edge: .trailing))
    }

    @MainActor
    func testOverlaySessionFloatingControlCollapseAndExpandPersistAcrossRootReinitialization() throws {
        let defaultsSuite = "StylistFloatingPersistenceTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuite))
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }

        let initial = StylistOverlaySessionCoordinator(service: StylistChatService(), floatingControlEdgeDefaults: defaults)
        XCTAssertEqual(initial.floatingControlPresentation, .expanded(edge: .trailing))

        initial.collapseFloatingControl(toward: .leading)
        let afterCollapse = StylistOverlaySessionCoordinator(service: StylistChatService(), floatingControlEdgeDefaults: defaults)
        XCTAssertEqual(afterCollapse.floatingControlPresentation, .collapsed(edge: .leading))

        afterCollapse.presentGeneral()
        afterCollapse.dismiss()
        XCTAssertEqual(afterCollapse.floatingControlPresentation, .collapsed(edge: .leading))

        afterCollapse.expandFloatingControl()
        let afterExpand = StylistOverlaySessionCoordinator(service: StylistChatService(), floatingControlEdgeDefaults: defaults)
        XCTAssertEqual(afterExpand.floatingControlPresentation, .expanded(edge: .leading))
    }

    @MainActor
    func testOverlaySessionFloatingControlInvalidStoredPreferenceFallsBackToDefault() throws {
        let defaultsSuite = "StylistFloatingInvalidPreferenceTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuite))
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }
        defaults.set(Data("invalid".utf8), forKey: "floatingStylistControlPlacement.v1")

        let overlay = StylistOverlaySessionCoordinator(service: StylistChatService(), floatingControlEdgeDefaults: defaults)
        XCTAssertEqual(overlay.floatingControlPresentation, .expanded(edge: .trailing))
    }

    @MainActor
    func testOverlaySessionFloatingControlMovesBetweenFixedEdgesWithoutChangingRouteOrConversation() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("StylistFixedEdgeTests-\(UUID().uuidString).json")
        defer {
            try? FileManager.default.removeItem(at: storeURL)
            try? FileManager.default.removeItem(at: storeURL.appendingPathExtension("bak"))
        }
        let defaultsSuite = "StylistFixedEdgeTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuite))
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }
        let service = StylistChatService(store: ChatConversationStore(fileURL: storeURL))
        let overlay = StylistOverlaySessionCoordinator(service: service, floatingControlEdgeDefaults: defaults)

        overlay.presentGeneral()
        let conversationID = service.activeConversation.id
        let route = overlay.route
        overlay.moveFloatingControl(to: .leading)

        XCTAssertEqual(overlay.floatingControlPresentation, .expanded(edge: .leading))
        XCTAssertEqual(overlay.route, route)
        XCTAssertEqual(service.activeConversation.id, conversationID)

        overlay.collapseFloatingControl(toward: .leading)
        overlay.moveFloatingControl(to: .trailing)
        XCTAssertEqual(overlay.floatingControlPresentation, .collapsed(edge: .trailing))

        overlay.expandFloatingControl()
        XCTAssertEqual(overlay.floatingControlPresentation, .expanded(edge: .trailing))
        XCTAssertEqual(overlay.route, route)
        XCTAssertEqual(service.activeConversation.id, conversationID)
        XCTAssertTrue(ChatConversationStore(fileURL: storeURL).conversations.isEmpty)

        let restored = StylistOverlaySessionCoordinator(
            service: StylistChatService(store: ChatConversationStore(fileURL: storeURL)),
            floatingControlEdgeDefaults: defaults
        )
        XCTAssertEqual(restored.floatingControlPresentation, .expanded(edge: .trailing))
    }

    @MainActor
    func testEveryScreenAwarenessRouteUsesEphemeralContextualConversation() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("StylistContextualRouteTests-\(UUID().uuidString).json")
        defer {
            try? FileManager.default.removeItem(at: storeURL)
            try? FileManager.default.removeItem(at: storeURL.appendingPathExtension("bak"))
        }
        let service = StylistChatService(store: ChatConversationStore(fileURL: storeURL))
        let overlay = StylistOverlaySessionCoordinator(service: service)
        let closet = try XCTUnwrap(ScreenAwarenessSnapshot.closetItem(
            ClosetItem(name: "Navy polo", category: "Shirt", color: "Navy", brand: "", size: "M", occasion: "Work", notes: ""),
            generation: 2
        ))
        let product = try XCTUnwrap(ScreenAwarenessSnapshot.shoppingProduct(
            phase1DProduct(id: "product-contextual", name: "Navy polo", colors: ["Navy"], price: 64, currency: "USD"),
            generation: 3
        ))
        let profile = ScreenAwarenessSnapshot.profile(
            StylistProfileContextProjection(
                stylePreferences: "Classic",
                styleGoals: "Build a work wardrobe",
                preferredFit: "Relaxed",
                sizeCategory: "Men",
                workplaceCategory: .office
            ),
            generation: 4
        )

        for snapshot in [ScreenAwarenessSnapshot.home(generation: 1), closet, product, profile] {
            overlay.presentScreenAwareness(snapshot)
            XCTAssertEqual(service.activeConversation.scope, .contextualStylist)
            XCTAssertEqual(service.activeConversation.classification, .contextualEphemeral)
            overlay.dismiss()
        }

        XCTAssertTrue(ChatConversationStore(fileURL: storeURL).conversations.isEmpty)
    }

    func testProfileContextualRouteUsesImmutableAllowlistedProfileProjection() throws {
        let profile = StylistProfileContextProjection(
            stylePreferences: "Classic, minimal",
            styleGoals: "Build a work wardrobe",
            preferredFit: "Relaxed",
            sizeCategory: "Men",
            workplaceCategory: .office
        )
        let route = ScreenAwarenessSnapshot.profile(profile, generation: 12)
        let encoded = try String(decoding: encode(route.requestContext), as: UTF8.self)

        XCTAssertEqual(route.kind, .profile)
        XCTAssertEqual(route.screenContext.surface?.screenKind, .profile)
        XCTAssertEqual(route.requestContext.recentOutfits, "")
        XCTAssertTrue(route.requestContext.profileSummary.contains("Classic, minimal"))
        XCTAssertTrue(route.requestContext.profileSummary.contains("Office"))
        XCTAssertFalse(encoded.contains("profileName"))
        XCTAssertFalse(encoded.contains("customerAccountEmail"))
        XCTAssertFalse(encoded.contains("customerAppleUserID"))
        XCTAssertFalse(encoded.contains("waistSize"))
        XCTAssertFalse(encoded.contains("workSetting"))
        XCTAssertFalse(encoded.contains("contextGeneration"))
    }

    func testStyleGoalsRequireExplicitBoundedProfileContextAndRemainAbsentFromGeneralStylist() throws {
        let styleGoal = "Build a work wardrobe"
        let general = StylistIntelligenceSnapshotBuilder.build(
            StylistIntelligenceSnapshotInput(conversationScope: .generalStylist)
        ).networkSafeContext(applying: ChatContext())
        let profile = ScreenAwarenessSnapshot.profile(
            StylistProfileContextProjection(styleGoals: styleGoal),
            generation: 12
        ).requestContext
        let generalEncoded = try String(decoding: encode(general), as: UTF8.self)
        let profileEncoded = try String(decoding: encode(profile), as: UTF8.self)

        XCTAssertFalse(generalEncoded.contains(styleGoal))
        XCTAssertTrue(profileEncoded.contains(styleGoal))
        XCTAssertFalse(profileEncoded.contains("profileName"))
        XCTAssertFalse(profileEncoded.contains("customerAccountEmail"))
        XCTAssertFalse(profileEncoded.contains("customerAppleUserID"))
        XCTAssertFalse(profileEncoded.contains("waistSize"))
        XCTAssertFalse(profileEncoded.contains("workSetting"))
    }

    func testProfileContextualRouteReplacesPriorScreenAuthorityAndRemainsImmutable() throws {
        var coordinator = StylistAwarenessCoordinator()
        _ = coordinator.publishHome()
        let first = StylistProfileContextProjection(stylePreferences: "Navy", preferredFit: "Tailored")
        let route = coordinator.publishProfile(first)
        let changedDraft = StylistProfileContextProjection(stylePreferences: "Orange", preferredFit: "Loose")

        XCTAssertEqual(coordinator.snapshot, route)
        XCTAssertEqual(route.requestContext.profileSummary, ScreenAwarenessSnapshot.profile(first, generation: route.generation).requestContext.profileSummary)
        XCTAssertNotEqual(route.requestContext.profileSummary, ScreenAwarenessSnapshot.profile(changedDraft, generation: route.generation).requestContext.profileSummary)
        coordinator.clear()
        XCTAssertNil(coordinator.snapshot)
    }

    func testProfileStylistEntryBuildsOnlyTheImmutableAllowlistedProjection() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("StyleMatchAI/ProfileView.swift"),
            encoding: .utf8
        )
        let start = try XCTUnwrap(source.range(of: "private var profileStylistContextProjection"))
        let end = try XCTUnwrap(source.range(of: "@ViewBuilder", range: start.upperBound..<source.endIndex))
        let projection = String(source[start.lowerBound..<end.lowerBound])

        XCTAssertTrue(source.contains("onOpenContextualStylist(profileStylistContextProjection)"))
        XCTAssertTrue(projection.contains("profileDraft.stylePreferences"))
        XCTAssertTrue(projection.contains("profileDraft.styleGoals"))
        XCTAssertTrue(projection.contains("profileDraft.fitPreference"))
        XCTAssertTrue(projection.contains("profileDraft.sizeCategory"))
        XCTAssertFalse(projection.contains("ProfileStore"))
        XCTAssertFalse(projection.contains("profileDraft.name"))
        XCTAssertFalse(projection.contains("customerAccountEmail"))
        XCTAssertFalse(projection.contains("customerAppleUserID"))
        XCTAssertFalse(projection.contains("waistSize"))
        XCTAssertFalse(projection.contains("workSetting:"))
    }

    func testDeletedClosetContextualRouteFailsClosedWithoutFallback() throws {
        let suite = "AIMemoryManagerTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let selected = ClosetItem(name: "Navy polo", category: "Shirt", color: "Navy", brand: "", size: "M", occasion: "Work", notes: "")
        let other = ClosetItem(name: "White shirt", category: "Shirt", color: "White", brand: "", size: "M", occasion: "Work", notes: "")
        let route = try XCTUnwrap(ScreenAwarenessSnapshot.closetItem(selected, generation: 9))

        defaults.set(try JSONEncoder().encode([other]), forKey: "closetItemsData")

        XCTAssertFalse(route.isCurrent(generation: 9, defaults: defaults))
        XCTAssertFalse(route.isCurrent(generation: 8, defaults: defaults))
    }

    func testPendingConsentAuthorityIsLocalAndBindsTheOriginallyApprovedRoute() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("StyleMatchAI/StylistChat/StylistChatView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("enum StylistPendingSendAuthority: Equatable"))
        XCTAssertFalse(source.contains("enum StylistPendingSendAuthority: Codable"))
        XCTAssertTrue(source.contains("case general"))
        XCTAssertTrue(source.contains("case scan(StylistConversationScope)"))
        XCTAssertTrue(source.contains("case screen(ScreenAwarenessSnapshot, generation: UInt64)"))
        XCTAssertTrue(source.contains("activeConversationScope == scope"))
        XCTAssertTrue(source.contains("screenAwarenessSnapshot == snapshot"))
        XCTAssertTrue(source.contains("generation == screenAwarenessGeneration"))
        XCTAssertTrue(source.contains("snapshot: validScreenAwarenessSnapshot"))
    }

    func testScreenAwarenessCoordinatorReplacesPriorHomeAuthority() throws {
        var coordinator = StylistAwarenessCoordinator()
        let home = coordinator.publishHome()
        let item = ClosetItem(name: "Navy polo", category: "Shirt", color: "Navy", brand: "", size: "M", occasion: "Work", notes: "")
        let replacement = try XCTUnwrap(coordinator.publishClosetItem(item))

        XCTAssertEqual(coordinator.snapshot, replacement)
        XCTAssertEqual(replacement.kind, .closetItem)
        XCTAssertFalse(home.isCurrent(generation: coordinator.generation))
    }

    func testGeneralStylistClearInvalidatesSharedScreenAwareness() {
        var coordinator = StylistAwarenessCoordinator()
        let home = coordinator.publishHome()

        coordinator.clear()

        XCTAssertNil(coordinator.snapshot)
        XCTAssertFalse(home.isCurrent(generation: coordinator.generation))
    }

    func testRapidHomeClosetHomeNavigationInvalidatesEveryPriorRoute() throws {
        var coordinator = StylistAwarenessCoordinator()
        let firstHome = coordinator.publishHome()
        let item = ClosetItem(name: "Navy polo", category: "Shirt", color: "Navy", brand: "", size: "M", occasion: "Work", notes: "")
        let closet = try XCTUnwrap(coordinator.publishClosetItem(item))
        let finalHome = coordinator.publishHome()

        XCTAssertEqual(coordinator.snapshot, finalHome)
        XCTAssertFalse(firstHome.isCurrent(generation: coordinator.generation))
        XCTAssertFalse(closet.isCurrent(generation: coordinator.generation))
        XCTAssertTrue(finalHome.isCurrent(generation: coordinator.generation))
    }

    func testClosetRouteNeverFallsBackFromItemAToItemB() throws {
        let suite = "AIMemoryManagerTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let itemA = ClosetItem(name: "Navy polo", category: "Shirt", color: "Navy", brand: "", size: "M", occasion: "Work", notes: "")
        let itemB = ClosetItem(name: "White shirt", category: "Shirt", color: "White", brand: "", size: "M", occasion: "Work", notes: "")
        let routeA = try XCTUnwrap(ScreenAwarenessSnapshot.closetItem(itemA, generation: 1))
        let routeB = try XCTUnwrap(ScreenAwarenessSnapshot.closetItem(itemB, generation: 2))
        defaults.set(try JSONEncoder().encode([itemA, itemB]), forKey: "closetItemsData")

        XCTAssertFalse(routeA.isCurrent(generation: 2, defaults: defaults))
        XCTAssertTrue(routeB.isCurrent(generation: 2, defaults: defaults))
        XCTAssertNotEqual(routeA.localReference, routeB.localReference)
    }

    func testContextAdaptersDoNotMutatePersistentDefaults() throws {
        let suite = "AIMemoryManagerTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let item = ClosetItem(name: "Navy polo", category: "Shirt", color: "Navy", brand: "", size: "M", occasion: "Work", notes: "")
        let closetData = try JSONEncoder().encode([item])
        let memoryData = Data("memory".utf8)
        let profileData = Data("profile".utf8)
        defaults.set(closetData, forKey: "closetItemsData")
        defaults.set(memoryData, forKey: "aiMemory")
        defaults.set(profileData, forKey: "profile")

        _ = ScreenAwarenessSnapshot.home(generation: 1).requestContext
        let route = try XCTUnwrap(ScreenAwarenessSnapshot.closetItem(item, generation: 2))
        XCTAssertTrue(route.isCurrent(generation: 2, defaults: defaults))
        _ = route.requestContext
        let product = phase1DProduct(id: "product-a", name: "Navy polo", colors: ["Navy"], price: 64, currency: "USD")
        _ = try XCTUnwrap(ScreenAwarenessSnapshot.shoppingProduct(product, generation: 3)).requestContext

        XCTAssertEqual(defaults.data(forKey: "closetItemsData"), closetData)
        XCTAssertEqual(defaults.data(forKey: "aiMemory"), memoryData)
        XCTAssertEqual(defaults.data(forKey: "profile"), profileData)
    }

    func testCurrentContextControlsRemainAccessibleAndDynamicTypeSafe() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("StyleMatchAI/StylistChat/StylistChatView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("CurrentStylistContextSheet"))
        XCTAssertTrue(source.contains("Button(\"What I’m using\")"))
        XCTAssertTrue(source.contains("Button(\"Use General Stylist instead\")"))
        XCTAssertTrue(source.contains(".fixedSize(horizontal: false, vertical: true)"))
        XCTAssertTrue(source.contains(".frame(minHeight: 44)"))
        XCTAssertTrue(source.contains(".accessibilityLabel(\"Current context."))
        XCTAssertTrue(source.contains("draft = transcript"))
        XCTAssertTrue(source.contains("let assembly = currentConversationAssembly(including: question)"))
        XCTAssertTrue(source.contains("forcedContext: context"))
        XCTAssertTrue(source.contains("intelligenceSnapshot: assembly.snapshot"))
        XCTAssertFalse(source.contains("service.send(question, forcedContext: currentConversationContext(including: question))"))
        XCTAssertTrue(source.contains("StylistIntelligenceSnapshotBuilder.build"))
        XCTAssertTrue(source.contains("threadCorrection: threadState.intelligenceThreadCorrection"))
        XCTAssertTrue(source.contains("WeatherKitAuthority.loadSnapshot(defaults: .standard)"))
    }

    func testHomeAndClosetContextualNavigationUsesOnlyExplicitActions() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let home = try String(contentsOf: root.appendingPathComponent("StyleMatchAI/HomeView.swift"), encoding: .utf8)
        let closet = try String(contentsOf: root.appendingPathComponent("StyleMatchAI/ClosetView.swift"), encoding: .utf8)
        let content = try String(contentsOf: root.appendingPathComponent("StyleMatchAI/ContentView.swift"), encoding: .utf8)

        XCTAssertTrue(home.contains("onOpenContextualStylist()"))
        XCTAssertTrue(closet.contains("onOpenContextualStylist(item)"))
        XCTAssertTrue(content.contains("publishScreenAwareness"))
        XCTAssertTrue(content.contains("clearScreenAwareness"))
        XCTAssertFalse(closet.contains("onOpenContextualStylist(items"))
    }

    func testExplicitRememberPersistsAndCorrectionSupersedesPriorActiveFact() throws {
        let root = temporaryMemoryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AIPersistentMemoryStore(userID: "guest", snapshotRoot: root)

        let original = try XCTUnwrap(store.remember(category: .sizesAndFit, text: "I prefer regular fit work pants."))
        let corrected = try XCTUnwrap(store.edit(original, text: "I prefer slim fit work pants."))

        XCTAssertEqual(store.activeMemories().map(\.id), [corrected.id])
        XCTAssertEqual(store.memories.first(where: { $0.id == original.id })?.invalidationState, .superseded)
        XCTAssertEqual(corrected.source, .userCorrection)
    }

    func testProposalDoesNotPersistUntilConfirmedAndForgetIsScoped() throws {
        let root = temporaryMemoryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AIPersistentMemoryStore(userID: "guest", snapshotRoot: root)
        let proposal = try XCTUnwrap(store.proposal(category: .stylePreferences, text: "I like navy", expiresAt: Date().addingTimeInterval(60)))
        XCTAssertTrue(store.memories.isEmpty)
        XCTAssertNil(store.proposal(category: .stylePreferences, text: "", expiresAt: Date().addingTimeInterval(60)))

        let confirmed = try XCTUnwrap(store.confirm(proposal))
        _ = store.remember(category: .shoppingPreferences, text: "I prefer outlet stores.")
        store.forget(confirmed.id)

        XCTAssertFalse(store.activeMemories().contains { $0.id == confirmed.id })
        XCTAssertEqual(store.activeMemories().map(\.category), [.shoppingPreferences])
    }

    func testForgetPhysicallyRemovesCorrectionLineageFromMainAndRecoverySnapshots() throws {
        let root = temporaryMemoryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AIPersistentMemoryStore(userID: "guest", snapshotRoot: root)
        let original = try XCTUnwrap(store.remember(category: .workAndUniform, text: "Original work preference"))
        let corrected = try XCTUnwrap(store.edit(original, text: "Corrected work preference"))
        let retained = try XCTUnwrap(store.remember(category: .shoppingPreferences, text: "Keep shopping preference"))

        XCTAssertTrue(store.forget(corrected.id))
        XCTAssertEqual(store.activeMemories().map(\.id), [retained.id])
        XCTAssertFalse(store.memories.contains { $0.id == original.id || $0.id == corrected.id })

        for data in aiMemoryFiles(at: root) {
            let text = String(decoding: data, as: UTF8.self)
            XCTAssertFalse(text.contains("Original work preference"))
            XCTAssertFalse(text.contains("Corrected work preference"))
            XCTAssertTrue(text.contains("Keep shopping preference"))
        }
    }

    func testForgetCategoryAndClearAllPhysicallyRemoveOnlyAIRecords() throws {
        let root = temporaryMemoryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AIPersistentMemoryStore(userID: "guest", snapshotRoot: root)
        _ = store.remember(category: .stylePreferences, text: "Navy preference")
        _ = store.remember(category: .workAndUniform, text: "Work preference")

        XCTAssertTrue(store.forget(category: .stylePreferences))
        XCTAssertEqual(store.activeMemories().map(\.value.displayValue), ["Work preference"])
        XCTAssertTrue(aiMemoryFiles(at: root).allSatisfy { !String(decoding: $0, as: UTF8.self).contains("Navy preference") })

        XCTAssertTrue(store.clearAll())
        XCTAssertTrue(store.activeMemories().isEmpty)
        XCTAssertTrue(aiMemoryFiles(at: root).allSatisfy { !String(decoding: $0, as: UTF8.self).contains("Work preference") })
    }

    func testLocalDataDeletionRemovesAIMemoryDocumentAndRecoverySnapshots() throws {
        let root = temporaryMemoryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let suiteName = "AIMemoryDeletionTests.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        defer { suite.removePersistentDomain(forName: suiteName) }
        suite.set("guest", forKey: AccountScopedStorage.activeUserMarkerKey)
        let store = AIPersistentMemoryStore(defaults: suite, userID: "guest", snapshotRoot: root)
        _ = store.remember(category: .stylePreferences, text: "Delete me")
        XCTAssertFalse(aiMemoryFiles(at: root).isEmpty)

        PersonalStylistStorage.deletePersonalization(for: "guest", defaults: suite, snapshotRoot: root)

        XCTAssertTrue(aiMemoryFiles(at: root).isEmpty)
    }

    func testInvalidatedReferenceAndCorruptPersistenceFailSafely() throws {
        let root = temporaryMemoryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let reference = try reference(.savedScan, "scan-a")
        let store = AIPersistentMemoryStore(userID: "guest", snapshotRoot: root)
        _ = store.remember(reference: reference)
        store.invalidate(reference: reference)
        XCTAssertTrue(store.activeMemories().isEmpty)

        try PersonalStylistSnapshotStore.replaceMainDataForTesting(Data("not-json".utf8), store: AIPersistentMemoryStore.storeName, userID: "guest", rootDirectory: root)
        XCTAssertTrue(AIPersistentMemoryStore(userID: "guest", snapshotRoot: root).memories.isEmpty)
    }

    func testPersistentResolutionIsBoundedAndCannotContainForbiddenPayloads() throws {
        let root = temporaryMemoryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AIPersistentMemoryStore(userID: "guest", snapshotRoot: root)
        _ = store.remember(category: .workAndUniform, text: "Approved black safety shoes for work.")
        let output = manager.mergingPersistentMemories(manager.resolve(input()), memories: store.activeMemories(relevantTo: "work shoes"))
        let payload = try String(decoding: encode(output), as: UTF8.self)

        XCTAssertTrue(output.facts.contains { $0.category == .persistentMemory })
        XCTAssertLessThanOrEqual(output.facts.count, 8)
        XCTAssertLessThanOrEqual(output.serializedCharacterCount, 1_600)
        XCTAssertFalse(payload.contains("imageData"))
        XCTAssertFalse(payload.contains("rawOCR"))
        XCTAssertFalse(payload.contains("calendarEvent"))
    }

    func testProfileAIMemoryRowUsesFullWidthAccessibleButtonAndExistingSheetRoute() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("StyleMatchAI/ProfileView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("isShowingAIMemoryManager = true"))
        XCTAssertTrue(source.contains("AIMemoryManagementView(store: aiMemoryStore)"))
        XCTAssertTrue(source.contains("Label(\"AI Memory\", systemImage: \"brain\")"))
        XCTAssertTrue(source.contains("contentShape(Rectangle())"))
        XCTAssertTrue(source.contains("minHeight: 44"))
        XCTAssertTrue(source.contains("Manage remembered preferences and AI memory."))
    }

    func testAIMemoryManagementUIUsesExplicitActionsAndSafeCopy() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("StyleMatchAI/ProfileView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("Nothing remembered yet"))
        XCTAssertTrue(source.contains("Viewing a screen or scanning an outfit does not automatically create a memory."))
        XCTAssertTrue(source.contains("Label(\"Add a Memory\", systemImage: \"plus.circle.fill\")"))
        XCTAssertTrue(source.contains("Button(\"Remember\")"))
        XCTAssertTrue(source.contains("Button(\"Edit Memory\", action: beginEditing)"))
        XCTAssertTrue(source.contains("Button(\"Explain Why\", action: showWhy)"))
        XCTAssertTrue(source.contains("Button(\"Forget Memory\""))
        XCTAssertTrue(source.contains("Clear Temporary AI Context"))
        XCTAssertTrue(source.contains("Clear All AI Memories?"))
        XCTAssertTrue(source.contains("It does not delete your Profile, Saved Scans, Closet items, favorites, or account."))
    }

    func testProfileNavigationIncludesAIMemoryTabAndReusesExistingManager() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("StyleMatchAI/ProfileView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("case aiMemory"))
        XCTAssertTrue(source.contains("case .aiMemory: return \"AI Memory\""))
        XCTAssertTrue(source.contains("if section == .aiMemory"))
        XCTAssertTrue(source.contains("isShowingAIMemoryManager = true"))
        XCTAssertTrue(source.contains("AIMemoryManagementView(store: aiMemoryStore)"))
        XCTAssertTrue(source.contains("selectedProfileNavigationSection == .aiMemory"))
        XCTAssertTrue(source.contains(".accessibilityLabel(section.title)"))
        XCTAssertTrue(source.contains(".accessibilityValue(isSelected ? \"Selected\" : \"Not selected\")"))
        XCTAssertTrue(source.contains(".accessibilityAddTraits(isSelected ? .isSelected : [])"))
        XCTAssertFalse(source.contains("section == .aiMemory ? \"AI Memory\""))
    }

    func testAddMemoryEditorUsesFocusedDraftAndExplicitPersistencePath() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("StyleMatchAI/ProfileView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("@FocusState private var isMemoryTextFocused: Bool"))
        XCTAssertTrue(source.contains("TextEditor(text: $text)"))
        XCTAssertTrue(source.contains(".focused($isMemoryTextFocused)"))
        XCTAssertTrue(source.contains(".frame(minHeight: 88)"))
        XCTAssertTrue(source.contains("Picker(\"Category\", selection: $category)"))
        XCTAssertTrue(source.contains(".disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)"))
        XCTAssertTrue(source.contains("store.rememberResult(category: category, text: text)"))
    }

    func testMemoryDetailCardsReuseEditAndExplainRoutes() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("StyleMatchAI/ProfileView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("AIMemoryDetailCardAction"))
        XCTAssertTrue(source.contains("accessibilityLabel: \"Edit remembered preference\""))
        XCTAssertTrue(source.contains("accessibilityLabel: \"Edit memory category\""))
        XCTAssertTrue(source.contains("accessibilityLabel: \"Explain why KigoStylist remembers this\""))
        XCTAssertTrue(source.contains("Button(\"Edit Memory\", action: beginEditing)"))
        XCTAssertTrue(source.contains("Button(\"Explain Why\", action: showWhy)"))
        XCTAssertTrue(source.contains("Button(\"Forget Memory\", role: .destructive)"))
    }

    func testSuccessfulCorrectionSupersedesOnlyOnPersistAndSurvivesReload() throws {
        let root = temporaryMemoryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AIPersistentMemoryStore(userID: "guest", snapshotRoot: root)
        let original = try XCTUnwrap(store.remember(category: .workAndUniform, text: "Work outfit"))

        XCTAssertEqual(store.activeMemories().map(\.id), [original.id])
        let corrected = try XCTUnwrap(store.edit(original, text: "Approved work outfit"))

        XCTAssertEqual(store.activeMemories().map(\.id), [corrected.id])
        XCTAssertEqual(corrected.source, .userCorrection)
        XCTAssertEqual(AIPersistentMemoryStore(userID: "guest", snapshotRoot: root).activeMemories().map(\.id), [corrected.id])
    }

    func testMemoryExplanationUsesOnlyStoredProvenanceAndBoundedCustomerCopy() throws {
        let root = temporaryMemoryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AIPersistentMemoryStore(userID: "guest", snapshotRoot: root)
        let explicit = try XCTUnwrap(store.remember(category: .stylePreferences, text: "I prefer navy."))
        let corrected = try XCTUnwrap(store.edit(explicit, text: "I prefer charcoal."))
        let profile = try XCTUnwrap(store.remember(category: .sizesAndFit, text: "Medium tops.", source: .confirmedProfile))

        XCTAssertEqual(explicit.explainWhy, "You asked KigoStylist to remember this.")
        XCTAssertEqual(corrected.explainWhy, "You corrected this preference.")
        XCTAssertEqual(profile.explainWhy, "This comes from your confirmed profile.")
        XCTAssertEqual(corrected.explainHowItHelps, "KigoStylist may use this preference when it is relevant to your styling advice.")
        XCTAssertFalse(corrected.explainHowItHelps.localizedCaseInsensitiveContains("identifier"))
        XCTAssertFalse(corrected.explainHowItHelps.localizedCaseInsensitiveContains("database"))
    }

    func testMemoryExplanationUsesOneSharedSheetForWhyRoutes() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("StyleMatchAI/ProfileView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("isShowingMemoryExplanation"))
        XCTAssertTrue(source.contains("AIMemoryExplanationView("))
        XCTAssertTrue(source.contains("action: showWhy"))
        XCTAssertTrue(source.contains("editMemory: editFromExplanation"))
        XCTAssertTrue(source.contains("forgetMemory: forgetFromExplanation"))
        XCTAssertTrue(source.contains("You can edit or forget this memory at any time."))
    }

    func testRememberedSummaryOpensExistingStoreBackedDestination() throws {
        let root = temporaryMemoryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AIPersistentMemoryStore(userID: "guest", snapshotRoot: root)
        XCTAssertTrue(store.activeMemories().isEmpty)
        _ = store.remember(category: .stylePreferences, text: "I prefer navy.")
        XCTAssertEqual(store.activeMemories().count, 1)

        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("StyleMatchAI/ProfileView.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(source.contains("AIMemorySummarySection(count: activeMemories.count)"))
        XCTAssertTrue(source.contains("isShowingRememberedMemories = true"))
        XCTAssertTrue(source.contains("AIMemoryRememberedMemoriesView(store: store, feedback: $feedback)"))
        XCTAssertTrue(source.contains("NavigationLink"))
        XCTAssertTrue(source.contains("AIMemoryDetailView(memory: memory, store: store, feedback: $feedback)"))
        XCTAssertTrue(source.contains("Button(\"Add a Memory\", action: addMemory)"))
        XCTAssertTrue(source.contains("Remembered memories, \\(countDescription)"))
        XCTAssertTrue(source.contains("Shows your saved AI memories."))
    }

    func testOneThousandActiveMemoriesArePreservedAndNextSaveReturnsExplicitFailure() throws {
        let root = temporaryMemoryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AIPersistentMemoryStore(userID: "guest", snapshotRoot: root)

        XCTAssertEqual(AIMemoryPolicy.maximumActiveMemories, 1_000)
        for index in 0..<AIMemoryPolicy.maximumActiveMemories {
            XCTAssertNotNil(store.remember(category: .stylePreferences, text: "Preference \(index)"))
        }
        let activeIDs = store.activeMemories().map(\.id).sorted { $0.uuidString < $1.uuidString }

        XCTAssertEqual(store.rememberResult(category: .stylePreferences, text: "One more preference"), .capacityReached)
        XCTAssertEqual(store.activeMemories().count, AIMemoryPolicy.maximumActiveMemories)
        XCTAssertEqual(store.activeMemories().map(\.id).sorted { $0.uuidString < $1.uuidString }, activeIDs)
    }

    func testCorrectionSucceedsAtOneThousandCapacityAndInvalidEditPreservesPredecessor() throws {
        let root = temporaryMemoryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AIPersistentMemoryStore(userID: "guest", snapshotRoot: root)
        var records: [AIPersistentMemory] = []
        for index in 0..<AIMemoryPolicy.maximumActiveMemories {
            records.append(try XCTUnwrap(store.remember(category: .stylePreferences, text: "Preference \(index)")))
        }
        let predecessor = try XCTUnwrap(records.first)

        guard case let .saved(corrected) = store.editResult(predecessor, text: "Corrected preference") else {
            return XCTFail("A correction must replace its predecessor at active capacity")
        }
        XCTAssertEqual(store.activeMemories().count, AIMemoryPolicy.maximumActiveMemories)
        XCTAssertTrue(store.activeMemories().contains { $0.id == corrected.id })
        XCTAssertFalse(store.activeMemories().contains { $0.id == predecessor.id })

        XCTAssertEqual(store.editResult(corrected, text: String(repeating: "x", count: 281)), .failed)
        XCTAssertTrue(store.activeMemories().contains { $0.id == corrected.id })
    }

    func testExpiredAndForgottenMemoriesFreeCapacityWithoutRemovingActiveRecords() throws {
        let root = temporaryMemoryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        var date = Date(timeIntervalSince1970: 10)
        let store = AIPersistentMemoryStore(userID: "guest", snapshotRoot: root, now: { date })
        let expiring = try XCTUnwrap(store.remember(category: .stylePreferences, text: "Expires", expiresAt: date.addingTimeInterval(1)))
        for index in 1..<AIMemoryPolicy.maximumActiveMemories {
            XCTAssertNotNil(store.remember(category: .stylePreferences, text: "Preference \(index)"))
        }

        date = date.addingTimeInterval(2)
        guard case .saved = store.rememberResult(category: .stylePreferences, text: "Replacement after expiry") else {
            return XCTFail("Expired memory must free one active slot")
        }
        XCTAssertFalse(store.activeMemories().contains { $0.id == expiring.id })
        XCTAssertEqual(store.activeMemories().count, AIMemoryPolicy.maximumActiveMemories)

        let forgotten = try XCTUnwrap(store.activeMemories().first)
        store.forget(forgotten.id)
        XCTAssertFalse(store.activeMemories().contains { $0.id == forgotten.id })
        XCTAssertNotNil(store.remember(category: .stylePreferences, text: "Replacement after forget"))
        XCTAssertEqual(store.activeMemories().count, AIMemoryPolicy.maximumActiveMemories)
        XCTAssertTrue(store.memories.filter(\.isActive).allSatisfy { $0.invalidationState == .active })
    }

    func testInactiveCorrectionHistoryRemainsAvailableForExistingProvenance() throws {
        let root = temporaryMemoryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AIPersistentMemoryStore(userID: "guest", snapshotRoot: root)
        let first = try XCTUnwrap(store.remember(category: .workAndUniform, text: "First work preference"))
        let second = try XCTUnwrap(store.edit(first, text: "Second work preference"))
        let third = try XCTUnwrap(store.edit(second, text: "Third work preference"))

        XCTAssertEqual(store.activeMemories().map(\.id), [third.id])
        XCTAssertTrue(store.memories.contains { $0.id == first.id && $0.invalidationState == .superseded })
        XCTAssertTrue(store.memories.contains { $0.id == second.id && $0.invalidationState == .superseded })
        XCTAssertEqual(store.memories.count, 3)
    }

    func testCapacityUIUsesExplicitFailureAndResolverBudgetsRemainUnchanged() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("StyleMatchAI/ProfileView.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(source.contains("switch store.rememberResult(category: category, text: text)"))
        XCTAssertTrue(source.contains("AI Memory is full"))
        XCTAssertTrue(source.contains("Review Memories"))
        XCTAssertTrue(source.contains("AIMemoryPolicy.maximumActiveMemories.formatted()"))
        XCTAssertTrue(source.contains("This memory was not saved. Please try again."))

        let output = manager.mergingPersistentMemories(manager.resolve(input()), memories: [])
        XCTAssertLessThanOrEqual(output.facts.count, 8)
        XCTAssertLessThanOrEqual(output.serializedCharacterCount, 1_600)
    }

    func testTemporaryContextClearKeepsPersistentMemoryAndProducesAccessibleFeedback() throws {
        let root = temporaryMemoryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AIPersistentMemoryStore(userID: "guest", snapshotRoot: root)
        let saved = try XCTUnwrap(store.remember(category: .workAndUniform, text: "Approved work outfit"))

        AIMemoryTemporaryContext.clear()

        XCTAssertEqual(store.activeMemories().map(\.id), [saved.id])
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("StyleMatchAI/ProfileView.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(source.contains("Temporary AI context cleared. Your saved AI memories were kept."))
        XCTAssertTrue(source.contains("UIAccessibility.post(notification: .announcement, argument: successFeedback)"))
        XCTAssertFalse(source.contains(".accessibilityLiveRegion"))
        XCTAssertTrue(source.contains("store.clearAll()"))
    }

    private let manager = AIMemoryManager(now: { Date(timeIntervalSince1970: 10) })

    private func input(
        screen: StylistScreenContext? = nil,
        expectedGeneration: UInt64? = nil,
        scope: StyleMemoryScope = .generalStylist,
        explicit: StyleMemoryFact<StyleMemoryReference> = .unavailable,
        summary: StyleMemoryFact<StyleMemoryScanSummary> = .unavailable,
        manual: StyleMemoryFact<String> = .unavailable,
        calendar: StyleMemoryFact<String> = .unavailable,
        weather: StyleMemoryFact<String> = .unavailable,
        profile: StyleMemoryFact<String> = .unavailable,
        workplace: StyleMemoryFact<String> = .unavailable,
        available: Set<StyleMemoryReference> = []
    ) -> AIMemoryResolutionInput {
        AIMemoryResolutionInput(
            userMessage: "What should I wear?",
            screenContext: screen,
            expectedContextGeneration: expectedGeneration,
            conversationScope: scope,
            styleMemoryInput: baseMemoryInput(
                scope: scope,
                explicit: explicit,
                summary: summary,
                manual: manual,
                calendar: calendar,
                weather: weather,
                profile: profile,
                workplace: workplace
            ),
            availableReferences: available
        )
    }

    private func baseMemoryInput(
        scope: StyleMemoryScope = .generalStylist,
        explicit: StyleMemoryFact<StyleMemoryReference> = .unavailable,
        summary: StyleMemoryFact<StyleMemoryScanSummary> = .unavailable,
        manual: StyleMemoryFact<String> = .unavailable,
        calendar: StyleMemoryFact<String> = .unavailable,
        weather: StyleMemoryFact<String> = .unavailable,
        profile: StyleMemoryFact<String> = .unavailable,
        workplace: StyleMemoryFact<String> = .unavailable
    ) -> StyleMemoryContextInput {
        StyleMemoryContextInput(
            identityScope: .guest,
            scope: scope,
            explicitSelection: explicit,
            selectedScanSummary: summary,
            manualOccasion: manual,
            calendarOccasion: calendar,
            weatherSummary: weather,
            profileSummary: profile,
            workplaceSummary: workplace
        )
    }

    private func screen(_ surface: StylistScreenSurfaceDescriptor) -> StylistScreenContext {
        StylistScreenContext(currentTab: .scan, activeScanState: .saved, activeScanID: surface.selectedLocalRecordID, entryPoint: .scanResult, closetState: .unavailable, surface: surface)
    }

    private func reference(_ domain: StyleMemoryReferenceDomain, _ id: String) throws -> StyleMemoryReference {
        try XCTUnwrap(StyleMemoryReference(domain: domain, stableID: id))
    }

    private func temporaryMemoryRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("AIPersistentMemoryTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func aiMemoryFiles(at root: URL) -> [Data] {
        let names = [
            "AIPersistentMemoryStore_guest.json",
            "AIPersistentMemoryStore_guest.backup1.json",
            "AIPersistentMemoryStore_guest.backup2.json",
            "AIPersistentMemoryStore_guest.backup3.json"
        ]
        return names.compactMap { try? Data(contentsOf: root.appendingPathComponent($0)) }
    }

    func testUnifiedOrchestratorRoutesExactScanWithoutChangingItsAuthority() throws {
        let scan = phase1CScan(id: "orchestrator-exact-scan")
        let snapshot = StylistIntelligenceSnapshotBuilder.build(
            StylistIntelligenceSnapshotInput(
                conversationScope: .activeScan(scanID: scan.scanID),
                exactScan: scan
            )
        )

        let outcome = StylistAIOrchestrator.decide(
            StylistAIOrchestrationInput(
                snapshot: snapshot,
                conversationScope: .activeScan(scanID: scan.scanID),
                intent: .explainScore,
                preflight: StylistConversationPreflight(intent: .explainScore, localReply: nil, semanticResponseID: nil),
                networkContext: snapshot.networkSafeContext(applying: ChatContext())
            )
        )

        XCTAssertEqual(outcome, .networkRequest(capability: .scanAdvisor))
        XCTAssertEqual(snapshot.activeScan?.scanID, scan.scanID)
        XCTAssertEqual(snapshot.activeScan?.overallScore, scan.overallScore)
    }

    func testUnifiedOrchestratorRoutesOnlyValidProductToPersonalShopper() throws {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let product = phase1DProduct(
            id: "orchestrator-product",
            name: "Navy polo",
            colors: ["Navy"],
            price: 80,
            currency: "USD"
        )
        let screen = try XCTUnwrap(ScreenAwarenessSnapshot.shoppingProduct(product, generation: 3, capturedAt: now))
        let snapshot = StylistIntelligenceSnapshotBuilder.build(
            StylistIntelligenceSnapshotInput(
                conversationScope: .contextualStylist,
                screenAwareness: screen,
                screenAwarenessGeneration: 3,
                availableShoppingProductIDs: [product.id],
                generatedAt: now
            )
        )

        let outcome = StylistAIOrchestrator.decide(
            StylistAIOrchestrationInput(
                snapshot: snapshot,
                conversationScope: .contextualStylist,
                intent: .general,
                preflight: StylistConversationPreflight(intent: .general, localReply: nil, semanticResponseID: nil),
                networkContext: snapshot.networkSafeContext(applying: ChatContext())
            )
        )

        XCTAssertEqual(outcome, .networkRequest(capability: .personalShopper))
        XCTAssertEqual(
            snapshot.networkSafeContext(applying: ChatContext()).productContext?.relationship,
            .considering
        )
    }

    func testUnifiedOrchestratorFailsClosedForStaleContextualClosetAuthority() throws {
        let item = ClosetItem(name: "Navy polo", category: "Shirt", color: "Navy", brand: "", size: "M", occasion: "Work", notes: "")
        let screen = try XCTUnwrap(ScreenAwarenessSnapshot.closetItem(item, generation: 3))
        let snapshot = StylistIntelligenceSnapshotBuilder.build(
            StylistIntelligenceSnapshotInput(
                conversationScope: .contextualStylist,
                screenAwareness: screen,
                screenAwarenessGeneration: 4
            )
        )

        let outcome = StylistAIOrchestrator.decide(
            StylistAIOrchestrationInput(
                snapshot: snapshot,
                conversationScope: .contextualStylist,
                intent: .closet,
                preflight: StylistConversationPreflight(intent: .closet, localReply: nil, semanticResponseID: nil),
                networkContext: ChatContext()
            )
        )

        XCTAssertEqual(outcome, .unavailable(reason: .staleScreenGeneration))
    }

    func testUnifiedOrchestratorMetadataNeverBecomesWorkerContract() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("StyleMatchAI/StylistChat/StylistAIOrchestrator.swift"),
            encoding: .utf8
        )
        XCTAssertFalse(source.contains("Codable"))
        XCTAssertFalse(source.contains("UserDefaults"))
        XCTAssertFalse(source.contains("WeatherKitAuthority"))
        XCTAssertFalse(source.contains("FeatureGate.shared"))

        let snapshot = StylistIntelligenceSnapshotBuilder.build(
            StylistIntelligenceSnapshotInput(conversationScope: .generalStylist)
        )
        let encoded = try String(decoding: encode(snapshot.networkSafeContext(applying: ChatContext())), as: UTF8.self)
        XCTAssertFalse(encoded.contains("StylistAICapability"))
        XCTAssertFalse(encoded.contains("orchestration"))
    }

    private func phase1CScan(id: String) -> StylistAuthoritativeScanContext {
        StylistAuthoritativeScanContext(
            scanID: id,
            completedAt: Date(timeIntervalSinceReferenceDate: 800_000_000),
            overallScore: 84,
            scoreBreakdown: OutfitScoreBreakdown(
                colorHarmony: 22,
                patternBalance: 16,
                fitQuality: 20,
                occasionMatch: 18,
                accessoryUse: 8
            ),
            source: .liveCompleted
        )
    }

    private func phase1CWorkplace(
        environment: WorkplaceEnvironment,
        source: WorkplaceContextSource
    ) -> WorkplaceContext {
        WorkplaceContext(
            environment: environment,
            dressCode: environment == .office ? .businessCasual : .safetyWorkwear,
            footwearConstraints: [.safetyToe],
            ppeRequirements: [],
            activityLevel: .mostlyStandingOrWalking,
            exposure: .indoorVariableTemperature,
            floorAndOfficeMix: false,
            source: source,
            confirmation: .userConfirmed,
            lastConfirmedAt: Date(timeIntervalSinceReferenceDate: 800_000_000)
        )
    }

    private func phase1CWeather(observedAt: Date) -> WeatherSnapshot? {
        guard let attribution = WeatherAttributionMetadata(
            serviceName: "WeatherKit",
            combinedMarkLightURL: URL(string: "https://example.com/weather-light")!,
            combinedMarkDarkURL: URL(string: "https://example.com/weather-dark")!,
            legalPageURL: URL(string: "https://example.com/weather-legal")!
        ) else {
            return nil
        }
        return WeatherSnapshot(
            observedAt: observedAt,
            locationName: "Test City",
            temperatureFahrenheit: 72,
            feelsLikeFahrenheit: 72,
            condition: "Clear",
            rainChancePercent: 0,
            humidityPercent: 40,
            windMph: 4,
            uvIndex: 3,
            hourlySummary: nil,
            dailySummary: nil,
            attribution: attribution
        )
    }

    private func phase1DProduct(
        id: String,
        name: String,
        colors: [String],
        price: Decimal,
        currency: String
    ) -> AffiliateProduct {
        AffiliateProduct(
            id: id,
            name: name,
            category: .clothing,
            subcategory: "Polo",
            colors: colors,
            brand: "Example Brand",
            retailerID: "retailer-internal",
            retailer: Retailer(name: "Example Retailer", trackingID: "tracking", trackingParamName: "tag", disclosureName: "Example Retailer"),
            affiliateURL: URL(string: "https://affiliate.example/product?tracking=secret")!,
            price: price,
            salePrice: nil,
            saleEndsAt: nil,
            currencyCode: currency,
            availableColors: ["Navy", "Blue"],
            customerRating: 4.9,
            reviewCount: 100,
            estimatedShippingText: "Two-day shipping",
            tags: ["raw-tag"],
            genderPresentation: "mens"
        )
    }


    private func fact<T: Codable & Equatable & Sendable>(_ value: T, _ provenance: StyleMemoryProvenance) -> StyleMemoryFact<T> {
        StyleMemoryFact(value: value, provenance: provenance, confidence: .confirmed)
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data { try JSONEncoder().encode(value) }
    private func decode<T: Decodable>(_ data: Data) throws -> T { try JSONDecoder().decode(T.self, from: data) }
}

private extension StylistScreenSurfaceKind {
    static let allCasesForTesting: [Self] = [
        .home, .liveScan, .savedScan, .closet, .shopping, .aiStylist,
        .profile, .settings, .scoreDetails, .sharedOutfit, .calendar,
        .weather, .favorites, .unsupported
    ]
}
