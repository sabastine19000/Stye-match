import XCTest
@testable import StyleMatchPro

final class StyleMemoryContextTests: XCTestCase {
    func testExplicitSelectionWinsOverOpenedAndActiveScanCandidates() throws {
        let selected = try reference(.savedScan, "selected")
        let opened = try reference(.savedScan, "opened")
        let active = try reference(.activeScan, "active")
        let context = StyleMemoryAuthorityResolver.resolve(
            input(
                scope: .init(kind: .savedScan, stableID: "selected"),
                explicitSelection: fact(selected, .explicitSelection),
                openedSavedScan: fact(opened, .openedSavedScan),
                completedActiveScan: fact(active, .completedActiveScan)
            )
        )

        XCTAssertEqual(context.authority.selectedReference, selected)
        XCTAssertEqual(context.authority.provenance, .explicitSelection)
        XCTAssertEqual(context.selectedScan.value, selected)
    }

    func testSavedScopeNeverFallsBackToDifferentScan() throws {
        let opened = try reference(.savedScan, "other-scan")
        let context = StyleMemoryAuthorityResolver.resolve(
            input(
                scope: .init(kind: .savedScan, stableID: "target-scan"),
                openedSavedScan: fact(opened, .openedSavedScan)
            )
        )

        XCTAssertNil(context.authority.selectedReference)
        XCTAssertFalse(context.authority.isResolved)
        XCTAssertNil(context.selectedScan.value)
    }

    func testGeneralStylistHasNoSelectedScanAuthority() throws {
        let active = try reference(.activeScan, "scan-1")
        let context = StyleMemoryAuthorityResolver.resolve(
            input(
                scope: .generalStylist,
                completedActiveScan: fact(active, .completedActiveScan)
            )
        )

        XCTAssertNil(context.authority.selectedReference)
        XCTAssertNil(context.selectedScan.value)
        XCTAssertTrue(context.isWorkerProjectable, "General Stylist may use a Worker projection, but without a selected Scan.")
    }

    func testManualOccasionWinsOverAuthorizedCalendarOccasion() {
        let context = StyleMemoryAuthorityResolver.resolve(
            input(
                scope: .generalStylist,
                manualOccasion: fact("Interview", .manualOccasion),
                calendarOccasion: StyleMemoryFact(
                    value: "Calendar event",
                    provenance: .authorizedCalendarEvent,
                    confidence: .confirmed,
                    permission: .authorized
                )
            )
        )

        XCTAssertEqual(context.occasion.value, "Interview")
        XCTAssertEqual(context.occasion.provenance, .manualOccasion)
    }

    func testExpiredWeatherIsRemovedBeforeProjection() throws {
        let active = try reference(.activeScan, "scan-1")
        let now = Date()
        let context = StyleMemoryAuthorityResolver.resolve(
            input(
                scope: .init(kind: .activeScan, stableID: "scan-1"),
                completedActiveScan: fact(active, .completedActiveScan),
                weatherSummary: StyleMemoryFact(
                    value: "Rain",
                    provenance: .freshWeather,
                    observedAt: .distantPast,
                    expiresAt: .distantPast,
                    confidence: .confirmed
                )
            ),
            now: now
        )

        XCTAssertNil(context.weather.value)
        XCTAssertNil(StyleMemoryWorkerProjection.project(context: context, now: now).weather)
    }

    func testWorkerProjectionUsesOnlyOpaqueReferencesAndSafeSummaries() throws {
        let scan = try reference(.savedScan, "scan-1")
        let wardrobe = try reference(.wardrobeItem, "item-1")
        let context = StyleMemoryAuthorityResolver.resolve(
            input(
                scope: .init(kind: .savedScan, stableID: "scan-1"),
                openedSavedScan: fact(scan, .openedSavedScan),
                profileSummary: fact("prefers neutral colors", .profile),
                wardrobeReferences: fact([wardrobe], .wardrobe)
            )
        )

        let projection = StyleMemoryWorkerProjection.project(context: context)
        XCTAssertEqual(projection.authorityID, "scan-1")
        XCTAssertEqual(projection.selectedScanID, "scan-1")
        XCTAssertEqual(projection.wardrobeItemIDs, ["item-1"])
        XCTAssertEqual(projection.profileSummary, "prefers neutral colors")
        XCTAssertNil(projection.occasion)
    }

    func testIdentityScopeAndPersistenceBoundaryDoNotCreateSecondStore() {
        let context = StyleMemoryAuthorityResolver.resolve(input(scope: .generalStylist, identity: .apple))

        XCTAssertFalse(StyleMemoryPersistenceBoundary.canPersist(context))
        XCTAssertEqual(StyleMemoryPersistenceBoundary.scopedAuditKey(for: .apple), "styleMemoryContext.audit.apple")
        XCTAssertEqual(StyleMemoryPersistenceBoundary.scopedAuditKey(for: .guest), "styleMemoryContext.audit.guest")
        XCTAssertNotEqual(
            StyleMemoryPersistenceBoundary.scopedAuditKey(for: .apple),
            StyleMemoryPersistenceBoundary.scopedAuditKey(for: .guest)
        )
    }

    func testUnavailableFactCannotBePromotedToAvailable() {
        let unavailable = StyleMemoryFact<String>(
            value: nil,
            provenance: .profile,
            confidence: .confirmed,
            permission: .notRequired
        )

        XCTAssertNil(unavailable.value)
        XCTAssertEqual(unavailable.provenance, .unavailable)
        XCTAssertEqual(unavailable.confidence, .unavailable)
        XCTAssertEqual(unavailable.permission, .notRequired)
    }

    func testSameIDWithWrongScanDomainFailsClosed() throws {
        let active = try reference(.activeScan, "shared")
        let context = StyleMemoryAuthorityResolver.resolve(
            input(
                scope: .init(kind: .savedScan, stableID: "shared"),
                openedSavedScan: fact(active, .openedSavedScan)
            )
        )

        XCTAssertFalse(context.authority.isResolved)
        XCTAssertNil(context.selectedScan.value)
    }

    func testExplicitMissingSelectionCannotFallBackToAnotherCandidate() throws {
        let requested = try reference(.savedScan, "requested")
        let fallback = try reference(.savedScan, "requested")
        let context = StyleMemoryAuthorityResolver.resolve(
            input(
                scope: .init(kind: .savedScan, stableID: "requested"),
                explicitSelection: fact(try reference(.savedScan, "other"), .explicitSelection),
                openedSavedScan: fact(fallback, .openedSavedScan)
            )
        )

        XCTAssertNotEqual(requested, context.authority.selectedReference)
        XCTAssertFalse(context.authority.isResolved)
    }

    func testEqualPriorityResolutionIsDeterministicByCandidateOrder() throws {
        let selected = try reference(.savedScan, "scan")
        let first = StyleMemoryFact(value: selected, provenance: .openedSavedScan, confidence: .confirmed)
        let second = StyleMemoryFact(value: selected, provenance: .openedSavedScan, confidence: .confirmed)
        let firstContext = StyleMemoryAuthorityResolver.resolve(input(scope: .init(kind: .savedScan, stableID: "scan"), openedSavedScan: first, completedActiveScan: second))
        let secondContext = StyleMemoryAuthorityResolver.resolve(input(scope: .init(kind: .savedScan, stableID: "scan"), openedSavedScan: first, completedActiveScan: second))

        XCTAssertEqual(firstContext, secondContext)
        XCTAssertEqual(firstContext.authority.provenance, .openedSavedScan)
    }

    func testGeneralProjectionNeverIncludesStaleScan() throws {
        let stale = try reference(.savedScan, "stale")
        let context = StyleMemoryAuthorityResolver.resolve(
            input(scope: .generalStylist, completedActiveScan: fact(stale, .completedActiveScan))
        )
        let projection = StyleMemoryWorkerProjection.project(context: context)

        XCTAssertEqual(projection.classification, .projectable)
        XCTAssertNil(projection.selectedScanID)
        XCTAssertNil(projection.authorityID)
    }

    func testUnresolvedProjectionStripsEveryContextualField() throws {
        let wrong = try reference(.activeScan, "other")
        let context = StyleMemoryAuthorityResolver.resolve(
            input(
                scope: .init(kind: .savedScan, stableID: "target"),
                openedSavedScan: fact(wrong, .openedSavedScan),
                manualOccasion: fact("Interview", .manualOccasion),
                profileSummary: fact("private profile", .profile),
                workplaceSummary: fact("private workplace", .profile),
                wardrobeReferences: fact([try reference(.wardrobeItem, "wardrobe")], .wardrobe),
                shoppingReference: fact(try reference(.shoppingItem, "shopping"), .explicitSelection)
            )
        )
        let projection = StyleMemoryWorkerProjection.project(context: context)

        XCTAssertEqual(projection.classification, .notProjectable)
        XCTAssertNil(projection.authorityScope)
        XCTAssertNil(projection.authorityID)
        XCTAssertNil(projection.selectedScanID)
        XCTAssertNil(projection.profileSummary)
        XCTAssertNil(projection.occasion)
        XCTAssertNil(projection.weather)
        XCTAssertNil(projection.workplaceSummary)
        XCTAssertTrue(projection.wardrobeItemIDs.isEmpty)
        XCTAssertNil(projection.shoppingItemID)
    }

    func testWorkerProjectionBoundsAndRedactsApprovedStrings() throws {
        let scan = try reference(.savedScan, "scan")
        let profile = String(repeating: "a", count: 400) + "\nprivate"
        let context = StyleMemoryAuthorityResolver.resolve(
            input(
                scope: .init(kind: .savedScan, stableID: "scan"),
                openedSavedScan: fact(scan, .openedSavedScan),
                profileSummary: fact(profile, .profile),
                workplaceSummary: fact("Office\nNorth", .profile)
            )
        )
        let projection = StyleMemoryWorkerProjection.project(context: context)

        XCTAssertLessThanOrEqual(projection.profileSummary?.utf16.count ?? 0, 280)
        XCTAssertFalse(projection.profileSummary?.contains("\n") ?? true)
        XCTAssertEqual(projection.workplaceSummary, "Office North")
    }

    func testCalendarPermissionAndExpirationAreFailClosed() throws {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        let scan = try reference(.savedScan, "scan")
        for permission in [StyleMemoryPermissionState.denied, .restricted, .notDetermined] {
            let context = StyleMemoryAuthorityResolver.resolve(
                input(
                    scope: .init(kind: .savedScan, stableID: "scan"),
                    openedSavedScan: fact(scan, .openedSavedScan),
                    calendarOccasion: StyleMemoryFact(value: "Private event", provenance: .authorizedCalendarEvent, expiresAt: now.addingTimeInterval(1), confidence: .confirmed, permission: permission, lifetime: .expiresAt)
                ), now: now
            )
            XCTAssertNil(context.occasion.value)
        }

        let authorized = StyleMemoryAuthorityResolver.resolve(
            input(
                scope: .init(kind: .savedScan, stableID: "scan"),
                openedSavedScan: fact(scan, .openedSavedScan),
                calendarOccasion: StyleMemoryFact(value: "Dinner", provenance: .authorizedCalendarEvent, expiresAt: now.addingTimeInterval(1), confidence: .confirmed, permission: .authorized, lifetime: .expiresAt)
            ),
            now: now
        )
        XCTAssertEqual(authorized.occasion.value, "Dinner")
        let expired = StyleMemoryAuthorityResolver.resolve(
            input(
                scope: .init(kind: .savedScan, stableID: "scan"),
                openedSavedScan: fact(scan, .openedSavedScan),
                calendarOccasion: StyleMemoryFact(value: "Dinner", provenance: .authorizedCalendarEvent, expiresAt: now, confidence: .confirmed, permission: .authorized, lifetime: .expiresAt)
            ),
            now: now
        )
        XCTAssertNil(expired.occasion.value)
    }

    func testManualOccasionAndPersistentFactContractsAreExplicit() throws {
        let scan = try reference(.savedScan, "scan")
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        let context = StyleMemoryAuthorityResolver.resolve(
            input(
                scope: .init(kind: .savedScan, stableID: "scan"),
                openedSavedScan: fact(scan, .openedSavedScan),
                manualOccasion: fact("Interview", .manualOccasion),
                calendarOccasion: StyleMemoryFact(value: "Dinner", provenance: .authorizedCalendarEvent, expiresAt: now.addingTimeInterval(1), confidence: .confirmed, permission: .authorized, lifetime: .expiresAt)
            ),
            now: now
        )
        XCTAssertEqual(context.occasion.value, "Interview")
        XCTAssertTrue(fact("stable", .profile).isFresh(at: now))
    }

    func testSessionFactsExpireOutsideTheirOriginatingSession() {
        let sessionFact = StyleMemoryFact(
            value: "temporary",
            provenance: .profile,
            confidence: .confirmed,
            lifetime: .session,
            sessionID: "session-a"
        )
        let now = Date(timeIntervalSinceReferenceDate: 1_000)

        XCTAssertTrue(sessionFact.isFresh(at: now, sessionID: "session-a"))
        XCTAssertFalse(sessionFact.isFresh(at: now, sessionID: "session-b"))
        XCTAssertFalse(sessionFact.isFresh(at: now))
    }

    func testIdentityResolutionAndStaleIdentityFactsFailClosed() throws {
        let suite = UserDefaults(suiteName: "StyleMemoryContextTests.identity")!
        suite.removePersistentDomain(forName: "StyleMemoryContextTests.identity")
        defer { suite.removePersistentDomain(forName: "StyleMemoryContextTests.identity") }

        suite.set("Sign in with Apple", forKey: "customerAccountMode")
        suite.set("apple-user", forKey: "customerAppleUserID")
        XCTAssertEqual(StyleMemoryIdentityScope.resolve(defaults: suite), .apple)
        suite.set("apple", forKey: "customerAccountMode")
        XCTAssertEqual(StyleMemoryIdentityScope.resolve(defaults: suite), .apple)
        suite.removeObject(forKey: "customerAppleUserID")
        XCTAssertEqual(StyleMemoryIdentityScope.resolve(defaults: suite), .guest)
        suite.set("malformed", forKey: "customerAccountMode")
        XCTAssertEqual(StyleMemoryIdentityScope.resolve(defaults: suite), .guest)

        let scan = try reference(.savedScan, "scan")
        let guestContext = StyleMemoryAuthorityResolver.resolve(
            input(scope: .init(kind: .savedScan, stableID: "scan"), identity: .guest, openedSavedScan: StyleMemoryFact(value: scan, provenance: .openedSavedScan, confidence: .confirmed, identityScope: .apple))
        )
        XCTAssertFalse(guestContext.authority.isResolved)
        XCTAssertEqual(StyleMemoryWorkerProjection.project(context: guestContext).classification, .notProjectable)
    }

    func testGeneralBuilderStripsStaleScanEvenWithoutConsent() {
        let defaults = isolatedDefaults("general-no-consent")
        let stale = ChatContext(
            profileSummary: "Existing general guidance",
            activeScan: "stale scan facts",
            scoreBreakdown: "stale score",
            authoritativeScan: authoritativeScan(id: "stale")
        )

        let result = StyleMemoryContextBuilder.applying(
            to: stale,
            conversationScope: .generalStylist,
            defaults: defaults
        )

        XCTAssertEqual(result.profileSummary, "Existing general guidance")
        XCTAssertEqual(result.activeScan, "")
        XCTAssertNil(result.scoreBreakdown)
        XCTAssertNil(result.authoritativeScan)
    }

    func testConsentedConfirmedProfileAndWorkplaceAreBoundedIntoGeneralContext() {
        let defaults = isolatedDefaults("consented-profile")
        defaults.set("Sign in with Apple", forKey: "customerAccountMode")
        defaults.set("apple-user", forKey: "customerAppleUserID")
        defaults.set(true, forKey: "shareAppContextWithChatGPT")
        let store = ProfileStore(defaults: defaults, userId: "apple-user")
        store.currentProfile.favoriteColors = ["navy"]
        store.currentProfile.workSetting = "industrial site"
        store.currentProfile.workDressCode = "PPE required"
        store.save()

        let result = StyleMemoryContextBuilder.applying(
            to: ChatContext(profileSummary: "Current request guidance"),
            conversationScope: .generalStylist,
            defaults: defaults
        )

        XCTAssertTrue(result.profileSummary.contains("Confirmed personal preferences:"))
        XCTAssertTrue(result.profileSummary.contains("navy"))
        XCTAssertTrue(result.profileSummary.contains("Confirmed workplace constraints: industrial site; PPE required"))
        XCTAssertLessThanOrEqual(result.profileSummary.utf16.count, 600)
        XCTAssertEqual(result.activeScan, "")
    }

    func testScanBuilderProjectsOnlyTheExactConversationScan() {
        let defaults = isolatedDefaults("exact-scan")
        defaults.set(true, forKey: "shareAppContextWithChatGPT")
        let selected = authoritativeScan(id: "selected")
        let context = ChatContext(
            activeScan: "score 80/100; Good Match",
            authoritativeScan: selected
        )

        let selectedResult = StyleMemoryContextBuilder.applying(
            to: context,
            conversationScope: .savedScan(scanID: "selected"),
            defaults: defaults
        )
        let otherResult = StyleMemoryContextBuilder.applying(
            to: context,
            conversationScope: .savedScan(scanID: "other"),
            defaults: defaults
        )

        XCTAssertTrue(selectedResult.activeScan.contains("Selected scan facts: score 80/100; Good Match"))
        XCTAssertFalse(otherResult.activeScan.contains("Selected scan facts:"))
    }

    func testNoConsentLeavesConfirmedProfileOutsideOutboundContext() {
        let defaults = isolatedDefaults("no-consent-profile")
        defaults.set("Sign in with Apple", forKey: "customerAccountMode")
        defaults.set("apple-user", forKey: "customerAppleUserID")
        let store = ProfileStore(defaults: defaults, userId: "apple-user")
        store.currentProfile.favoriteColors = ["navy"]
        store.save()

        let result = StyleMemoryContextBuilder.applying(
            to: ChatContext(profileSummary: "Current request guidance"),
            conversationScope: .generalStylist,
            defaults: defaults
        )

        XCTAssertEqual(result.profileSummary, "Current request guidance")
        XCTAssertFalse(result.profileSummary.contains("navy"))
    }

    private func input(
        scope: StyleMemoryScope,
        identity: StyleMemoryIdentityScope = .apple,
        explicitSelection: StyleMemoryFact<StyleMemoryReference> = .unavailable,
        openedSavedScan: StyleMemoryFact<StyleMemoryReference> = .unavailable,
        completedActiveScan: StyleMemoryFact<StyleMemoryReference> = .unavailable,
        selectedScanSummary: StyleMemoryFact<StyleMemoryScanSummary> = .unavailable,
        manualOccasion: StyleMemoryFact<String> = .unavailable,
        calendarOccasion: StyleMemoryFact<String> = .unavailable,
        weatherSummary: StyleMemoryFact<String> = .unavailable,
        profileSummary: StyleMemoryFact<String> = .unavailable,
        workplaceSummary: StyleMemoryFact<String> = .unavailable,
        wardrobeReferences: StyleMemoryFact<[StyleMemoryReference]> = .unavailable,
        shoppingReference: StyleMemoryFact<StyleMemoryReference> = .unavailable
    ) -> StyleMemoryContextInput {
        StyleMemoryContextInput(
            identityScope: identity,
            scope: scope,
            explicitSelection: explicitSelection,
            openedSavedScan: openedSavedScan,
            completedActiveScan: completedActiveScan,
            selectedScanSummary: selectedScanSummary,
            manualOccasion: manualOccasion,
            calendarOccasion: calendarOccasion,
            weatherSummary: weatherSummary,
            profileSummary: profileSummary,
            workplaceSummary: workplaceSummary,
            wardrobeReferences: wardrobeReferences,
            shoppingReference: shoppingReference
        )
    }

    private func reference(_ domain: StyleMemoryReferenceDomain, _ id: String) throws -> StyleMemoryReference {
        try XCTUnwrap(StyleMemoryReference(domain: domain, stableID: id))
    }

    private func fact<Value: Codable & Equatable & Sendable>(
        _ value: Value,
        _ provenance: StyleMemoryProvenance
    ) -> StyleMemoryFact<Value> {
        StyleMemoryFact(value: value, provenance: provenance, confidence: .confirmed)
    }

    private func isolatedDefaults(_ name: String) -> UserDefaults {
        let suiteName = "StyleMemoryContextTests.\(name)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return defaults
    }

    private func authoritativeScan(id: String) -> StylistAuthoritativeScanContext {
        StylistAuthoritativeScanContext(
            scanID: id,
            completedAt: Date(timeIntervalSinceReferenceDate: 1_000),
            overallScore: 80,
            scoreBreakdown: nil,
            source: .savedSelection
        )
    }
}
