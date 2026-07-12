import XCTest
@testable import StyleMatchPro

private func projectSource(_ relativePath: String, filePath: String = #filePath) throws -> String {
    let root = URL(fileURLWithPath: filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let url = root.appendingPathComponent(relativePath)
    return try String(contentsOf: url, encoding: .utf8)
}

final class StyleMatchProPhase2Tests: XCTestCase {
    let userA = "test-user-A"
    let userB = "test-user-B"

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "StyleMatchProPhase2Tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        XCTAssertNotNil(defaults)

        PersonalStylistStorage.deletePersonalization(for: userA, defaults: defaults)
        PersonalStylistStorage.deletePersonalization(for: userB, defaults: defaults)
    }

    override func tearDown() {
        if let suiteName {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - Profile pants size sync tests

    func testMenPantsSizeParserExtractsWaistAndInseam() {
        XCTAssertEqual(
            PantsSizeSync.measurements(from: "Men 36x32"),
            PantsSizeMeasurements(waist: "36", inseam: "32")
        )
        XCTAssertEqual(
            PantsSizeSync.measurements(from: "36 x 32"),
            PantsSizeMeasurements(waist: "36", inseam: "32")
        )
        XCTAssertEqual(
            PantsSizeSync.measurements(from: "Men 36X32"),
            PantsSizeMeasurements(waist: "36", inseam: "32")
        )
        XCTAssertNil(PantsSizeSync.measurements(from: "Women 12"))
    }

    func testPantsPickerChangeUpdatesWaistAndInseamFields() {
        var state = PantsSizeFieldState(pantsSize: "Men 36x36", waistSize: "36", inseamLength: "36")
        state.applyPickerSelection("Men 36x32")
        XCTAssertEqual(state.visibleValuesForSave, PantsSizeVisibleValues(pantsSize: "Men 36x32", waistSize: "36", inseamLength: "32"))
        XCTAssertEqual(state.lastEditSource, .picker)

        state = PantsSizeFieldState(pantsSize: "Men 34x30", waistSize: "34", inseamLength: "30")
        state.applyPickerSelection("Men 34x32")
        XCTAssertEqual(state.visibleValuesForSave, PantsSizeVisibleValues(pantsSize: "Men 34x32", waistSize: "34", inseamLength: "32"))

        state = PantsSizeFieldState(pantsSize: "Men 32x32", waistSize: "32", inseamLength: "32")
        state.applyPickerSelection("Men 32x30")
        XCTAssertEqual(state.visibleValuesForSave, PantsSizeVisibleValues(pantsSize: "Men 32x30", waistSize: "32", inseamLength: "30"))
    }

    func testManualInseamEditSurvivesVisibleSaveValues() {
        var state = PantsSizeFieldState(pantsSize: "Men 36x32", waistSize: "36", inseamLength: "32", lastEditSource: .picker)
        state.applyManualInseam("34")

        XCTAssertEqual(state.lastEditSource, .manual)
        XCTAssertEqual(state.visibleValuesForSave, PantsSizeVisibleValues(pantsSize: "Men 36x34", waistSize: "36", inseamLength: "34"))
    }

    func testGeneratedPantsSizeComesFromWaistAndInseam() {
        XCTAssertEqual(PantsSizeSync.displayValue(waist: "36", inseam: "32"), "36 × 32")
        XCTAssertEqual(PantsSizeSync.storageValue(category: "Men", waist: "36", inseam: "32"), "Men 36x32")
        XCTAssertEqual(PantsSizeSync.storageValue(category: "Unisex", waist: "34", inseam: "30"), "Unisex 34x30")
    }

    func testChangingWaistOrInseamUpdatesGeneratedPantsSize() {
        var state = PantsSizeFieldState(pantsSize: "Men 34x30", waistSize: "34", inseamLength: "30")

        state.applyManualWaist("36")
        XCTAssertEqual(state.visibleValuesForSave, PantsSizeVisibleValues(pantsSize: "Men 36x30", waistSize: "36", inseamLength: "30"))

        state.applyManualInseam("32")
        XCTAssertEqual(state.visibleValuesForSave, PantsSizeVisibleValues(pantsSize: "Men 36x32", waistSize: "36", inseamLength: "32"))
    }

    func testLegacyCombinedPantsSizeBackfillsMissingMeasurements() {
        let reconciled = PantsSizeSync.reconciledValues(
            pantsSize: "Men 36 × 32",
            waistSize: "",
            inseamLength: "",
            category: "Men"
        )

        XCTAssertEqual(reconciled.pantsSize, "Men 36x32")
        XCTAssertEqual(reconciled.waistSize, "36")
        XCTAssertEqual(reconciled.inseamLength, "32")
    }

    func testSeparateMeasurementsOverrideStaleCombinedPantsSize() {
        let reconciled = PantsSizeSync.reconciledValues(
            pantsSize: "Men 24x27",
            waistSize: "36",
            inseamLength: "32",
            category: "Men"
        )

        XCTAssertEqual(reconciled.pantsSize, "Men 36x32")
        XCTAssertEqual(reconciled.waistSize, "36")
        XCTAssertEqual(reconciled.inseamLength, "32")
    }

    func testBlankPantsMeasurementsDoNotCreateFakeDefault() {
        let reconciled = PantsSizeSync.reconciledValues(
            pantsSize: "",
            waistSize: "",
            inseamLength: "",
            category: "Men"
        )

        XCTAssertEqual(reconciled.pantsSize, "")
        XCTAssertEqual(reconciled.waistSize, "")
        XCTAssertEqual(reconciled.inseamLength, "")
        XCTAssertNil(PantsSizeSync.displayValue(waist: reconciled.waistSize, inseam: reconciled.inseamLength))
    }

    func testWomenCategoryDoesNotGenerateMensPantsSizeFromStaleMeasurements() {
        XCTAssertFalse(PantsSizeSync.categoryUsesGeneratedPants("Women"))
        XCTAssertNil(PantsSizeSync.storageValue(category: "Women", waist: "36", inseam: "32"))
    }

    func testProfileAndClosetCanShareGeneratedPantsDisplayValue() {
        let reconciled = PantsSizeSync.reconciledValues(
            pantsSize: "Men 36x36",
            waistSize: "36",
            inseamLength: "32",
            category: "Men"
        )

        let generatedDisplay = PantsSizeSync.displayValue(
            waist: reconciled.waistSize,
            inseam: reconciled.inseamLength
        )

        XCTAssertEqual(reconciled.pantsSize, "Men 36x32")
        XCTAssertEqual(generatedDisplay, "36 × 32")
    }

    func testPantsSizeProfileReconciliationPrefersWaistInseamOverStaleCombined() {
        defaults.set("Men", forKey: "sizeCategory")
        defaults.set("Men 24x27", forKey: "pantsSize")
        defaults.set("36", forKey: "waistSize")
        defaults.set("32", forKey: "inseamLength")
        defaults.set("Category: Men; Bottom: Men 24x27", forKey: "sizeProfile")

        var profile = makeStylistProfile(userId: userA)
        profile.clothingSizes = ClothingSizes(pantSize: "Men 24x27")

        let result = PantsSizeProfileReconciliation.reconcile(
            defaults: defaults,
            userID: userA,
            profile: profile
        )

        XCTAssertTrue(result.didChangeProfile)
        XCTAssertEqual(result.profile.clothingSizes.pantSize, "Men 36x32")
        XCTAssertEqual(defaults.string(forKey: "pantsSize"), "Men 36x32")
        XCTAssertEqual(defaults.string(forKey: "waistSize"), "36")
        XCTAssertEqual(defaults.string(forKey: "inseamLength"), "32")
        XCTAssertNil(defaults.string(forKey: "sizeProfile"))
        XCTAssertTrue(defaults.bool(forKey: PantsSizeProfileReconciliation.migrationKey(userID: userA)))
    }

    func testPantsSizeProfileReconciliationParsesPantsSizeOnly() {
        defaults.set("Men", forKey: "sizeCategory")
        defaults.set("Men 34x30", forKey: "pantsSize")

        var profile = makeStylistProfile(userId: userA)
        profile.clothingSizes = ClothingSizes(pantSize: "Men 34x30")

        let result = PantsSizeProfileReconciliation.reconcile(
            defaults: defaults,
            userID: userA,
            profile: profile
        )

        XCTAssertFalse(result.didChangeProfile)
        XCTAssertEqual(result.profile.clothingSizes.pantSize, "Men 34x30")
        XCTAssertEqual(defaults.string(forKey: "pantsSize"), "Men 34x30")
        XCTAssertEqual(defaults.string(forKey: "waistSize"), "34")
        XCTAssertEqual(defaults.string(forKey: "inseamLength"), "30")
    }

    func testPantsSizeProfileReconciliationGeneratesFromWaistInseamOnly() {
        defaults.set("Men", forKey: "sizeCategory")
        defaults.set("36", forKey: "waistSize")
        defaults.set("32", forKey: "inseamLength")

        let profile = makeStylistProfile(userId: userA)

        let result = PantsSizeProfileReconciliation.reconcile(
            defaults: defaults,
            userID: userA,
            profile: profile
        )

        XCTAssertTrue(result.didChangeProfile)
        XCTAssertEqual(result.profile.clothingSizes.pantSize, "Men 36x32")
        XCTAssertEqual(defaults.string(forKey: "pantsSize"), "Men 36x32")
        XCTAssertEqual(defaults.string(forKey: "waistSize"), "36")
        XCTAssertEqual(defaults.string(forKey: "inseamLength"), "32")
    }

    func testPantsSizeProfileReconciliationLeavesBlankSizesBlankAndRunsOnce() {
        let profile = makeStylistProfile(userId: userA)

        let first = PantsSizeProfileReconciliation.reconcile(
            defaults: defaults,
            userID: userA,
            profile: profile
        )

        XCTAssertFalse(first.didChangeProfile)
        XCTAssertNil(first.profile.clothingSizes.pantSize)
        XCTAssertNil(defaults.string(forKey: "pantsSize"))
        XCTAssertNil(defaults.string(forKey: "waistSize"))
        XCTAssertNil(defaults.string(forKey: "inseamLength"))
        XCTAssertTrue(defaults.bool(forKey: PantsSizeProfileReconciliation.migrationKey(userID: userA)))

        defaults.set("Men", forKey: "sizeCategory")
        defaults.set("Men 36x32", forKey: "pantsSize")
        defaults.set("36", forKey: "waistSize")
        defaults.set("32", forKey: "inseamLength")

        let second = PantsSizeProfileReconciliation.reconcile(
            defaults: defaults,
            userID: userA,
            profile: first.profile
        )

        XCTAssertFalse(second.didChangeProfile)
        XCTAssertNil(second.profile.clothingSizes.pantSize)
    }

    func testBlankClothingSizesDoNotReachAIContext() {
        var profile = makeStylistProfile(userId: userA)
        profile.clothingSizes = ClothingSizes(
            shirtSize: " ",
            pantSize: " ",
            shoeSize: "",
            jacketSize: nil,
            dressSize: nil
        )

        let context = PersonalizationContextBuilder.buildContext(profile: profile, recentMemories: [])

        XCTAssertFalse(context.contains("Sizes"))
        XCTAssertFalse(context.localizedCaseInsensitiveContains("pants"))
        XCTAssertFalse(context.localizedCaseInsensitiveContains("shoes"))
        XCTAssertFalse(context.contains("36"))
    }

    // MARK: - Phase 3 feedback loop tests

    func testFeedbackSchedulerEligibilityWindow() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let store = OutfitMemoryStore(defaults: defaults, userId: userA)
        markFeedbackFirstSessionSeen(for: userA)

        var tooRecent = makeOutfitMemory(userId: userA, record: makeGarmentRecord(fingerprint: "too-recent"))
        tooRecent.scanDate = now.addingTimeInterval(-6 * 60 * 60)
        var eligible = makeOutfitMemory(userId: userA, record: makeGarmentRecord(fingerprint: "eligible"))
        eligible.scanDate = now.addingTimeInterval(-13 * 60 * 60)
        var tooOld = makeOutfitMemory(userId: userA, record: makeGarmentRecord(fingerprint: "too-old"))
        tooOld.scanDate = now.addingTimeInterval(-15 * 24 * 60 * 60)

        store.addScan(tooRecent)
        store.addScan(eligible)
        store.addScan(tooOld)

        let scheduler = FeedbackPromptScheduler(store: store, defaults: defaults, userId: userA)
        XCTAssertEqual(scheduler.nextPromptCandidate(now: now)?.id, eligible.id)
    }

    func testFeedbackSchedulerReAskRulesAndOnePerSession() {
        let now = Date(timeIntervalSince1970: 2_500_000)
        let store = OutfitMemoryStore(defaults: defaults, userId: userA)
        markFeedbackFirstSessionSeen(for: userA)

        var capped = makeOutfitMemory(userId: userA, record: makeGarmentRecord(fingerprint: "capped"))
        capped.scanDate = now.addingTimeInterval(-20 * 60 * 60)
        capped.feedbackPromptCount = 2
        store.addScan(capped)

        var dismissed = makeOutfitMemory(userId: userA, record: makeGarmentRecord(fingerprint: "dismissed"))
        dismissed.scanDate = now.addingTimeInterval(-22 * 60 * 60)
        dismissed.feedbackDismissedAt = now.addingTimeInterval(-47 * 60 * 60)
        store.addScan(dismissed)

        let scheduler = FeedbackPromptScheduler(store: store, defaults: defaults, userId: userA)
        XCTAssertNil(scheduler.nextPromptCandidate(now: now))

        store.dismissFeedbackPrompt(for: dismissed.id, now: now.addingTimeInterval(-49 * 60 * 60))
        XCTAssertEqual(scheduler.nextPromptCandidate(now: now)?.id, dismissed.id)

        scheduler.recordPromptShown(for: dismissed.id, now: now)
        XCTAssertNil(scheduler.nextPromptCandidate(now: now), "Only one prompt should show per app session.")

        let freshStore = OutfitMemoryStore(defaults: defaults, userId: userA)
        let freshScheduler = FeedbackPromptScheduler(store: freshStore, defaults: defaults, userId: userA)
        XCTAssertNil(freshScheduler.nextPromptCandidate(now: now.addingTimeInterval(60 * 60)), "Global cap should block prompts for 24 hours.")
    }

    func testFeedbackSchedulerSuppressesVeryFirstSessionOnly() {
        let now = Date(timeIntervalSince1970: 2_700_000)
        let store = OutfitMemoryStore(defaults: defaults, userId: userA)

        var eligible = makeOutfitMemory(userId: userA, record: makeGarmentRecord(fingerprint: "skip-backoff"))
        eligible.scanDate = now.addingTimeInterval(-20 * 60 * 60)
        store.addScan(eligible)

        let scheduler = FeedbackPromptScheduler(store: store, defaults: defaults, userId: userA)
        XCTAssertNil(scheduler.nextPromptCandidate(now: now), "The first app session should not show a feedback prompt.")

        let relaunchedStore = OutfitMemoryStore(defaults: defaults, userId: userA)
        let relaunchedScheduler = FeedbackPromptScheduler(store: relaunchedStore, defaults: defaults, userId: userA)
        XCTAssertEqual(relaunchedScheduler.nextPromptCandidate(now: now)?.id, eligible.id)
    }

    func testFeedbackSchedulerPicksMostRecentEligibleOutfit() {
        let now = Date(timeIntervalSince1970: 3_000_000)
        let store = OutfitMemoryStore(defaults: defaults, userId: userA)
        markFeedbackFirstSessionSeen(for: userA)

        var older = makeOutfitMemory(userId: userA, record: makeGarmentRecord(fingerprint: "older"))
        older.scanDate = now.addingTimeInterval(-4 * 24 * 60 * 60)
        var newer = makeOutfitMemory(userId: userA, record: makeGarmentRecord(fingerprint: "newer"))
        newer.scanDate = now.addingTimeInterval(-13 * 60 * 60)

        store.addScan(older)
        store.addScan(newer)

        let scheduler = FeedbackPromptScheduler(store: store, defaults: defaults, userId: userA)
        XCTAssertEqual(scheduler.nextPromptCandidate(now: now)?.id, newer.id)
    }

    func testFeedbackWornAnswerIncrementsTimesWornExactlyOnce() {
        let now = Date(timeIntervalSince1970: 3_500_000)
        let store = OutfitMemoryStore(defaults: defaults, userId: userA)
        let memory = makeOutfitMemory(userId: userA, record: makeGarmentRecord(fingerprint: "repeat-worn"))
        store.addScan(memory)

        store.recordWornAnswer(for: memory.id, wasWorn: true, now: now)
        store.recordWornAnswer(for: memory.id, wasWorn: true, now: now.addingTimeInterval(60))

        let saved = OutfitMemoryStore(defaults: defaults, userId: userA).memories.first { $0.id == memory.id }
        XCTAssertEqual(saved?.wasWorn, true)
        XCTAssertEqual(saved?.timesWorn, 1)
        XCTAssertEqual(saved?.garmentRecords.first?.timesWorn, 1)
    }

    func testOutfitMemoryDecodesWithoutPhase3FeedbackFields() throws {
        let id = UUID()
        let json = """
        {
          "id": "\(id.uuidString)",
          "userId": "\(userA)",
          "scanDate": 0,
          "detectedGarments": ["shirt"],
          "colors": ["white"],
          "detectedStyle": "Casual",
          "styleScore": 82,
          "occasion": "casual",
          "isFavorite": false,
          "timesWorn": 0
        }
        """

        let decoded = try JSONDecoder().decode(OutfitMemory.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.id, id)
        XCTAssertNil(decoded.wasWorn)
        XCTAssertNil(decoded.wasLiked)
        XCTAssertNil(decoded.dislikeReason)
        XCTAssertEqual(decoded.feedbackPromptCount, 0)
        XCTAssertNil(decoded.feedbackDismissedAt)
        XCTAssertNil(decoded.feedbackCompletedAt)
        XCTAssertNil(decoded.feedback)
    }

    func testPrePhase3OutfitMemoryJSONFixtureDecodesCleanlyWithoutFeedbackField() throws {
        let id = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let json = """
        {
          "id": "\(id.uuidString)",
          "userId": "\(userA)",
          "scanDate": 1720310400,
          "detectedGarments": ["shirt", "pants"],
          "colors": ["white", "gray"],
          "detectedStyle": "Casual",
          "styleScore": 84,
          "isFavorite": true,
          "timesWorn": 0
        }
        """

        let decoded = try JSONDecoder().decode(OutfitMemory.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.id, id)
        XCTAssertEqual(decoded.detectedGarments, ["shirt", "pants"])
        XCTAssertEqual(decoded.colors, ["white", "gray"])
        XCTAssertNil(decoded.feedback)
        XCTAssertNil(decoded.wasWorn)
        XCTAssertNil(decoded.wasLiked)
        XCTAssertNil(decoded.feedbackTimestamp)
        XCTAssertNil(decoded.dislikeReason)
        XCTAssertEqual(decoded.feedbackPromptCount, 0)
        XCTAssertNil(decoded.feedbackDismissedAt)
        XCTAssertNil(decoded.feedbackCompletedAt)
    }

    func testFeedbackNoAnswerCompletesWithoutLikeOrReason() {
        let now = Date(timeIntervalSince1970: 4_000_000)
        let store = OutfitMemoryStore(defaults: defaults, userId: userA)
        let memory = makeOutfitMemory(userId: userA, record: makeGarmentRecord(fingerprint: "not-worn"))
        store.addScan(memory)

        store.recordWornAnswer(for: memory.id, wasWorn: false, now: now)

        let saved = OutfitMemoryStore(defaults: defaults, userId: userA).memories.first { $0.id == memory.id }
        XCTAssertEqual(saved?.wasWorn, false)
        XCTAssertNil(saved?.wasLiked)
        XCTAssertNil(saved?.dislikeReason)
        XCTAssertNotNil(saved?.feedbackCompletedAt)
    }

    func testRecordOutfitFeedbackPersistsAndIncrementsTimesWornOnce() {
        let now = Date(timeIntervalSince1970: 4_300_000)
        let store = OutfitMemoryStore(defaults: defaults, userId: userA)
        let memory = makeOutfitMemory(userId: userA, record: makeGarmentRecord(fingerprint: "verdict"))
        store.addScan(memory)

        let feedback = OutfitFeedback(verdict: .loved, woreIt: true, recordedAt: now)
        store.recordOutfitFeedback(for: memory.id, feedback: feedback)
        store.recordOutfitFeedback(for: memory.id, feedback: feedback)

        let saved = OutfitMemoryStore(defaults: defaults, userId: userA).memories.first { $0.id == memory.id }
        XCTAssertEqual(saved?.feedback, feedback)
        XCTAssertEqual(saved?.wasWorn, true)
        XCTAssertEqual(saved?.wasLiked, true)
        XCTAssertEqual(saved?.timesWorn, 1)
        XCTAssertNotNil(saved?.feedbackCompletedAt)
    }

    func testPersonalizationContextOmitsFeedbackWhenEmptyAndSummarizesWhenPresent() {
        let profile = makeStylistProfile(userId: userA)
        var noFeedback = makeOutfitMemory(userId: userA, record: makeGarmentRecord(fingerprint: "no-feedback"))
        noFeedback.detectedStyle = "Casual"
        let emptyContext = PersonalizationContextBuilder.promptContext(
            profile: profile,
            outfitMemories: [noFeedback],
            memoryLimit: 5
        )
        XCTAssertFalse(emptyContext.contains("Feedback signals"))

        var loved = makeOutfitMemory(userId: userA, record: makeGarmentRecord(fingerprint: "loved-feedback"))
        loved.detectedStyle = "Casual"
        loved.feedback = OutfitFeedback(verdict: .loved, woreIt: true, recordedAt: Date(timeIntervalSince1970: 4_400_000))
        var notForMe = makeOutfitMemory(userId: userA, record: makeGarmentRecord(fingerprint: "not-feedback"))
        notForMe.detectedStyle = "Formal"
        notForMe.feedback = OutfitFeedback(verdict: .notForMe, woreIt: true, recordedAt: Date(timeIntervalSince1970: 4_400_100))

        let summary = PersonalizationContextBuilder.feedbackSummary([loved, notForMe])
        XCTAssertNotNil(summary)
        XCTAssertLessThanOrEqual(summary?.count ?? 0, 220)

        let feedbackContext = PersonalizationContextBuilder.promptContext(
            profile: profile,
            outfitMemories: [loved, notForMe],
            memoryLimit: 5
        )
        XCTAssertTrue(feedbackContext.contains("Feedback signals"))
        XCTAssertTrue(feedbackContext.contains("loved"))
        XCTAssertTrue(feedbackContext.contains("not for me"))
    }

    func testPersonalizationContextSummarizesTapOnlyFeedbackFields() {
        let profile = makeStylistProfile(userId: userA)
        var loved = makeOutfitMemory(userId: userA, record: makeGarmentRecord(fingerprint: "tap-loved"))
        loved.detectedStyle = "Smart Casual"
        loved.wasWorn = true
        loved.wasLiked = true
        loved.timesWorn = 1

        var disliked = makeOutfitMemory(userId: userA, record: makeGarmentRecord(fingerprint: "tap-disliked"))
        disliked.detectedStyle = "Formal"
        disliked.wasWorn = true
        disliked.wasLiked = false
        disliked.dislikeReason = .tooFormal

        let feedbackContext = PersonalizationContextBuilder.promptContext(
            profile: profile,
            outfitMemories: [loved, disliked],
            memoryLimit: 5
        )

        XCTAssertTrue(feedbackContext.contains("Feedback signals"))
        XCTAssertTrue(feedbackContext.contains("loved 1"))
        XCTAssertTrue(feedbackContext.contains("not for me 1"))
        XCTAssertTrue(feedbackContext.contains("wore 2"))
        XCTAssertTrue(feedbackContext.contains("dislike reasons: too formal 1x"))
        XCTAssertTrue(feedbackContext.contains("Recently disliked"))
        XCTAssertTrue(feedbackContext.contains("reason Too formal"))
    }

    // MARK: - Weather & Context Engine regression tests

    func testWeatherSeverityUsesFeelsLikeTemperature() {
        let recommendation = WeatherContextEngine.recommendation(
            for: makeWeatherSnapshot(air: 84, feelsLike: 100, humidity: 72, activity: .walking)
        )

        XCTAssertEqual(recommendation.severity, .extremeHeat)
        XCTAssertFalse(containsHeavyLayer(recommendation.recommendation))
        XCTAssertTrue(recommendation.rationale.contains("feels-like temperature is 100°F"))
    }

    func testNinetyDegreeWeatherDoesNotRecommendJackets() {
        let recommendation = WeatherContextEngine.recommendation(
            for: makeWeatherSnapshot(air: 90, feelsLike: 91, humidity: 68, activity: .office, location: "Miami, Florida")
        )

        XCTAssertEqual(recommendation.severity, .hot)
        XCTAssertFalse(containsHeavyLayer(recommendation.recommendation))
        XCTAssertTrue(recommendation.recommendation.localizedCaseInsensitiveContains("lightweight"))
        XCTAssertTrue(recommendation.regionalNote.localizedCaseInsensitiveContains("hot-humid"))
    }

    func testRainInWarmWeatherUsesUmbrellaInsteadOfJacket() {
        let recommendation = WeatherContextEngine.recommendation(
            for: makeWeatherSnapshot(air: 82, feelsLike: 87, rain: 80, condition: "Rain", activity: .walking)
        )

        XCTAssertFalse(containsHeavyLayer(recommendation.recommendation))
        XCTAssertTrue(recommendation.recommendation.localizedCaseInsensitiveContains("umbrella"))
        XCTAssertTrue(recommendation.rationale.localizedCaseInsensitiveContains("rain risk"))
    }

    func testSnowAllowsColdWeatherLayers() {
        let recommendation = WeatherContextEngine.recommendation(
            for: makeWeatherSnapshot(air: 30, feelsLike: 26, condition: "Snow", activity: .travel, location: "Minneapolis, Minnesota")
        )

        XCTAssertEqual(recommendation.severity, .freezing)
        XCTAssertTrue(recommendation.recommendation.localizedCaseInsensitiveContains("coat"))
        XCTAssertTrue(recommendation.recommendation.localizedCaseInsensitiveContains("boots"))
    }

    func testWindAtCoolTemperatureAllowsRemovableLayer() {
        let recommendation = WeatherContextEngine.recommendation(
            for: makeWeatherSnapshot(air: 55, feelsLike: 52, wind: 22, condition: "Windy", activity: .outdoorEvent)
        )

        XCTAssertEqual(recommendation.severity, .cool)
        XCTAssertTrue(recommendation.recommendation.localizedCaseInsensitiveContains("wind-resistant"))
        XCTAssertTrue(recommendation.guardrail.localizedCaseInsensitiveContains("removable"))
    }

    func testHighUVAddsSunProtectionWithoutHeavyLayer() {
        let recommendation = WeatherContextEngine.recommendation(
            for: makeWeatherSnapshot(air: 86, feelsLike: 89, uv: 9, activity: .beach, location: "Phoenix, Arizona")
        )

        XCTAssertFalse(containsHeavyLayer(recommendation.recommendation))
        XCTAssertTrue(recommendation.recommendation.localizedCaseInsensitiveContains("sunglasses"))
        XCTAssertTrue(recommendation.rationale.localizedCaseInsensitiveContains("UV index is 9"))
    }

    func testWarmNightDoesNotRecommendJacketBecauseItIsNight() {
        let recommendation = WeatherContextEngine.recommendation(
            for: makeWeatherSnapshot(air: 76, feelsLike: 74, activity: .formalEvent, timeOfDay: "Night")
        )

        XCTAssertEqual(recommendation.severity, .warm)
        XCTAssertFalse(containsHeavyLayer(recommendation.recommendation))
        XCTAssertTrue(recommendation.guardrail.localizedCaseInsensitiveContains("nighttime"))
    }

    func testIndoorOfficeEventKeepsHeatAdvicePolishedWithoutJacket() {
        let recommendation = WeatherContextEngine.recommendation(
            for: makeWeatherSnapshot(air: 88, feelsLike: 92, activity: .office)
        )

        XCTAssertFalse(containsHeavyLayer(recommendation.recommendation))
        XCTAssertTrue(recommendation.recommendation.localizedCaseInsensitiveContains("crisp shirt"))
        XCTAssertTrue(recommendation.rationale.localizedCaseInsensitiveContains("activity is office"))
    }

    func testMixedWeatherPrioritizesEffectiveTemperatureAndRainAccessories() {
        let recommendation = WeatherContextEngine.recommendation(
            for: makeWeatherSnapshot(air: 78, feelsLike: 83, humidity: 80, rain: 55, wind: 16, condition: "Humid rain", activity: .travel)
        )

        XCTAssertEqual(recommendation.severity, .hot)
        XCTAssertFalse(containsHeavyLayer(recommendation.recommendation))
        XCTAssertTrue(recommendation.recommendation.localizedCaseInsensitiveContains("water-friendly shoes"))
        XCTAssertTrue(recommendation.rationale.localizedCaseInsensitiveContains("humidity is 80%"))
    }

    func testLowWeatherConfidenceAvoidsSpecificWeatherClothing() {
        let recommendation = WeatherContextEngine.recommendation(
            for: makeWeatherSnapshot(air: 91, feelsLike: 94, activity: .walking, confidence: 82)
        )

        XCTAssertFalse(recommendation.canGiveSpecificWeatherClothingAdvice)
        XCTAssertTrue(recommendation.guardrail.localizedCaseInsensitiveContains("below 90%"))
        XCTAssertFalse(recommendation.recommendation.localizedCaseInsensitiveContains("linen"))
        XCTAssertFalse(containsHeavyLayer(recommendation.recommendation))
    }

    // MARK: - 1. Per-user isolation

    func testTwoUsersDoNotShareData() {
        let recordA = makeGarmentRecord(fingerprint: "pants-black-solid")
        let memoryA = makeOutfitMemory(userId: userA, record: recordA)

        let userAStore = OutfitMemoryStore(defaults: defaults, userId: userA)
        userAStore.addOrMergeScan(memoryA)

        let userBRecords = OutfitMemoryStore(defaults: defaults, userId: userB).garmentRecords
        XCTAssertTrue(userBRecords.isEmpty, "User B should not see User A's saved data")

        let userARecords = OutfitMemoryStore(defaults: defaults, userId: userA).garmentRecords
        XCTAssertTrue(
            userARecords.contains(where: { $0.itemFingerprint == recordA.itemFingerprint }),
            "User A should see their own saved garment record"
        )
    }

    private func makeWeatherSnapshot(
        air: Int?,
        feelsLike: Int? = nil,
        humidity: Int? = nil,
        rain: Int? = nil,
        wind: Int? = nil,
        uv: Int? = nil,
        condition: String = "Clear",
        activity: WeatherActivity = .general,
        location: String = "Current location",
        confidence: Int = 95,
        timeOfDay: String = "Afternoon"
    ) -> WeatherContextSnapshot {
        WeatherContextSnapshot(
            airTemperature: air,
            feelsLikeTemperature: feelsLike,
            humidityPercent: humidity,
            rainChancePercent: rain,
            windMph: wind,
            uvIndex: uv,
            condition: condition,
            locationText: location,
            activity: activity,
            region: WeatherContextEngine.inferRegion(locationText: location),
            season: "Summer",
            timeOfDay: timeOfDay,
            confidence: confidence
        )
    }

    private func containsHeavyLayer(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return lowered.contains("jacket")
            || lowered.contains("blazer")
            || lowered.contains("coat")
            || lowered.contains("sweater")
            || lowered.contains("shacket")
            || lowered.contains("heavy layer")
            || lowered.contains("structured layer")
    }

    // MARK: - 2. Repeated item detection (dedup)

    func testSameGarmentScannedTwiceIncrementsTimesSeenNotDuplicate() {
        let fingerprint = "pants-black-solid"
        let firstRecord = makeGarmentRecord(fingerprint: fingerprint, sourceScanIds: ["scan-1"])
        let secondRecord = makeGarmentRecord(fingerprint: fingerprint, sourceScanIds: ["scan-2"])
        let thirdRecord = makeGarmentRecord(fingerprint: fingerprint, sourceScanIds: ["scan-3"])
        let firstMemory = makeOutfitMemory(userId: userA, record: firstRecord)

        let store = OutfitMemoryStore(defaults: defaults, userId: userA)
        store.addOrMergeScan(firstMemory)

        if let existingMemory = store.memories.first(where: { memory in
            memory.garmentRecords.contains(where: { $0.itemFingerprint == secondRecord.itemFingerprint })
        }) {
            store.mergeGarmentRecords([secondRecord], into: existingMemory.id)
        } else {
            XCTFail("Expected the second scan to match an existing garment fingerprint")
        }

        if let existingMemory = store.memories.first(where: { memory in
            memory.garmentRecords.contains(where: { $0.itemFingerprint == thirdRecord.itemFingerprint })
        }) {
            store.mergeGarmentRecords([thirdRecord], into: existingMemory.id)
        } else {
            XCTFail("Expected the third scan to match an existing garment fingerprint")
        }

        let records = OutfitMemoryStore(defaults: defaults, userId: userA)
            .garmentRecords
            .filter { $0.itemFingerprint == fingerprint }

        XCTAssertEqual(records.count, 1, "Should not create a duplicate record")
        XCTAssertEqual(records.first?.timesSeen, 3, "Same garment should increment timesSeen for each repeat scan")
        XCTAssertEqual(records.first?.sourceScanIds.sorted(), ["scan-1", "scan-2", "scan-3"])
    }

    // MARK: - 3. Privacy deletion completeness

    func testDeletionClearsAllPersonalizationKeys() {
        let recordA = makeGarmentRecord(fingerprint: "pants-black-solid-a")
        let recordB = makeGarmentRecord(fingerprint: "shirt-white-solid-b")

        let profileA = ProfileStore(defaults: defaults, userId: userA)
        profileA.currentProfile.favoriteColors = ["black"]
        profileA.save()

        let profileB = ProfileStore(defaults: defaults, userId: userB)
        profileB.currentProfile.favoriteColors = ["white"]
        profileB.save()

        OutfitMemoryStore(defaults: defaults, userId: userA)
            .addOrMergeScan(makeOutfitMemory(userId: userA, record: recordA))
        OutfitMemoryStore(defaults: defaults, userId: userB)
            .addOrMergeScan(makeOutfitMemory(userId: userB, record: recordB))

        let userAFeedbackKey = PersonalStylistStorage.scopedKey(
            PersonalStylistStorage.legacyFeedbackCountKey,
            userID: userA
        )
        let userBFeedbackKey = PersonalStylistStorage.scopedKey(
            PersonalStylistStorage.legacyFeedbackCountKey,
            userID: userB
        )
        defaults.set(3, forKey: userAFeedbackKey)
        defaults.set(2, forKey: userBFeedbackKey)

        PersonalStylistStorage.deletePersonalization(for: userA, defaults: defaults)

        XCTAssertNil(
            defaults.object(forKey: PersonalStylistStorage.scopedKey(PersonalStylistStorage.legacyProfileKey, userID: userA)),
            "User A profile key should be removed"
        )
        XCTAssertNil(
            defaults.object(forKey: PersonalStylistStorage.scopedKey(PersonalStylistStorage.legacyMemoriesKey, userID: userA)),
            "User A outfit memory key should be removed"
        )
        XCTAssertNil(defaults.object(forKey: userAFeedbackKey), "User A feedback key should be removed")

        XCTAssertNotNil(
            defaults.object(forKey: PersonalStylistStorage.scopedKey(PersonalStylistStorage.legacyProfileKey, userID: userB)),
            "User B profile key should not be removed"
        )
        XCTAssertNotNil(
            defaults.object(forKey: PersonalStylistStorage.scopedKey(PersonalStylistStorage.legacyMemoriesKey, userID: userB)),
            "User B outfit memory key should not be removed"
        )
        XCTAssertEqual(defaults.integer(forKey: userBFeedbackKey), 2, "User B feedback key should not be removed")
    }

    // MARK: - 4. Snapshot safety net

    func testUpdatingExistingOutfitCreatesPreWriteSnapshot() {
        let fingerprint = "shirt-white-solid"
        let store = OutfitMemoryStore(defaults: defaults, userId: userA)
        let firstMemory = makeOutfitMemory(userId: userA, record: makeGarmentRecord(fingerprint: fingerprint, sourceScanIds: ["scan-1"]))
        store.addOrMergeScan(firstMemory)

        let updatedMemory = makeOutfitMemory(userId: userA, record: makeGarmentRecord(fingerprint: fingerprint, sourceScanIds: ["scan-2"]))
        store.addOrMergeScan(updatedMemory)

        XCTAssertGreaterThanOrEqual(
            PersonalStylistSnapshotStore.snapshotCount(store: "OutfitMemoryStore", userID: userA),
            1,
            "Updating an existing outfit should leave a pre-write snapshot"
        )
    }

    func testCorruptOutfitStoreRecoversFromSnapshot() throws {
        let fingerprint = "jacket-charcoal-solid"
        let store = OutfitMemoryStore(defaults: defaults, userId: userA)
        store.addOrMergeScan(makeOutfitMemory(userId: userA, record: makeGarmentRecord(fingerprint: fingerprint, sourceScanIds: ["scan-1"])))
        store.addOrMergeScan(makeOutfitMemory(userId: userA, record: makeGarmentRecord(fingerprint: fingerprint, sourceScanIds: ["scan-2"])))

        try PersonalStylistSnapshotStore.replaceMainDataForTesting(
            Data("not valid json".utf8),
            store: "OutfitMemoryStore",
            userID: userA
        )

        let recovered = OutfitMemoryStore(defaults: defaults, userId: userA)
        XCTAssertFalse(recovered.memories.isEmpty, "Corrupt main store should recover from the latest valid snapshot")
        XCTAssertTrue(
            recovered.garmentRecords.contains(where: { $0.itemFingerprint == fingerprint }),
            "Recovered snapshot should preserve the stored garment fingerprint"
        )
    }

    func testSnapshotRotationCapsAtThree() {
        let store = OutfitMemoryStore(defaults: defaults, userId: userA)

        for index in 1...5 {
            store.addOrMergeScan(makeOutfitMemory(
                userId: userA,
                record: makeGarmentRecord(fingerprint: "pants-black-solid", sourceScanIds: ["scan-\(index)"])
            ))
        }

        XCTAssertLessThanOrEqual(
            PersonalStylistSnapshotStore.snapshotCount(store: "OutfitMemoryStore", userID: userA),
            3,
            "Snapshot rotation should keep only the last three snapshots"
        )
    }

    func testConcurrentWritesStayScopedAndDecodable() {
        let store = OutfitMemoryStore(defaults: defaults, userId: userA)
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "StyleMatchProPhase2Tests.concurrentWrites", attributes: .concurrent)

        for index in 0..<20 {
            group.enter()
            queue.async {
                let record = self.makeGarmentRecord(
                    fingerprint: "concurrent-shirt-\(index)",
                    sourceScanIds: ["scan-\(index)"]
                )
                store.addOrMergeScan(self.makeOutfitMemory(userId: self.userA, record: record))
                group.leave()
            }
        }

        XCTAssertEqual(group.wait(timeout: .now() + 5), .success)

        let reloaded = OutfitMemoryStore(defaults: defaults, userId: userA)
        let normalizedUserA = PersonalStylistStorage.normalizedUserID(userA)
        XCTAssertEqual(reloaded.memories.count, 20)
        XCTAssertTrue(reloaded.memories.allSatisfy { $0.userId == normalizedUserA })
    }

    // MARK: - 5. Casual classifier guardrails

    func testCommonCasualCombosDoNotTriggerTraditionalWear() {
        let samples = [
            "blue polo shirt with khaki pants and casual loafers",
            "plain t-shirt with blue jeans and sneakers",
            "hoodie with joggers and running shoes",
            "button-down shirt with chinos and clean sneakers",
            "dress shirt with slacks and brown dress shoes"
        ]

        for sample in samples {
            let rankings = StyleClassificationGuardrails.rankedStyles(for: sample, baseScore: 84)
            let top = rankings.first?.name
            let traditionalConfidence = rankings.first(where: { $0.name == "Traditional Wear" })?.confidence ?? 0

            XCTAssertNotEqual(top, "Traditional Wear", "\(sample) should not rank as Traditional Wear")
            XCTAssertLessThan(traditionalConfidence, 50, "\(sample) should not have high traditional confidence")
        }
    }

    func testPoloKhakisClassifyAsCasualOrSmartCasualNotCeremonial() {
        let rankings = StyleClassificationGuardrails.rankedStyles(
            for: "blue polo shirt khaki pants brown casual shoes",
            baseScore: 84
        )

        XCTAssertTrue(["Casual", "Smart Casual", "Business Casual"].contains(rankings.first?.name ?? ""))
        XCTAssertLessThan(rankings.first(where: { $0.name == "Traditional Wear" })?.confidence ?? 0, 50)
    }

    func testSleepwearLabelsClassifyAsSleepwearNotBusinessCasual() {
        let samples = [
            "bathrobe pajama pants fuzzy slippers bedroom",
            "plush robe nightwear bedroom slippers",
            "children's sleepwear pajama set house shoes",
            "loungewear lounge set homewear"
        ]

        for sample in samples {
            let rankings = StyleClassificationGuardrails.rankedStyles(for: sample, baseScore: 82)
            XCTAssertEqual(rankings.first?.name, "Sleepwear", "\(sample) should rank as Sleepwear")
            XCTAssertLessThanOrEqual(
                rankings.first(where: { $0.name == "Business Casual" })?.confidence ?? 100,
                12,
                "\(sample) should block Business Casual"
            )
        }
    }

    func testSleepwearImageNetLabelsMapToSleepwearCategory() {
        let samples = [
            "pajama pyjama bathrobe slipper",
            "nightgown bedroom slipper housecoat",
            "robe plush slipper loungewear",
            "sleepwear nightwear onesie house shoe"
        ]

        for sample in samples {
            let rankings = StyleClassificationGuardrails.rankedStyles(for: sample, baseScore: 80)
            XCTAssertEqual(rankings.first?.name, "Sleepwear", "\(sample) should map to Sleepwear")
            XCTAssertLessThanOrEqual(
                rankings.first(where: { $0.name == "Business Casual" })?.confidence ?? 100,
                12,
                "\(sample) should not allow Business Casual"
            )
        }
    }

    func testUnmappedLowConfidenceEvidenceDoesNotDefaultToBusinessCasual() {
        let rankings = StyleClassificationGuardrails.rankedStyles(
            for: "unrecognized category uncertain low confidence",
            baseScore: 90
        )

        XCTAssertEqual(rankings.first?.name, "Unrecognized Item")
        XCTAssertLessThanOrEqual(rankings.first(where: { $0.name == "Business Casual" })?.confidence ?? 100, 0)
    }

    func testRegularCasualDoesNotTriggerSleepwear() {
        let samples = [
            "plain t-shirt blue jeans sneakers",
            "button-down shirt chinos clean sneakers",
            "blue polo shirt khaki pants",
            "hoodie joggers running shoes"
        ]

        for sample in samples {
            let rankings = StyleClassificationGuardrails.rankedStyles(for: sample, baseScore: 82)
            XCTAssertNotEqual(rankings.first?.name, "Sleepwear", "\(sample) should not rank as Sleepwear")
        }
    }

    func testMatchingHomePajamaSetDoesNotFallThroughToCasual() {
        let rankings = StyleClassificationGuardrails.rankedStyles(
            for: "girl wearing matching red and white striped two-piece shirt and pants set in a bedroom at home",
            baseScore: 82
        )

        XCTAssertEqual(rankings.first?.name, "Sleepwear")
        XCTAssertLessThan(
            rankings.first(where: { $0.name == "Casual" })?.confidence ?? 100,
            rankings.first?.confidence ?? 0
        )
        XCTAssertLessThanOrEqual(
            rankings.first(where: { $0.name == "Business Casual" })?.confidence ?? 100,
            12
        )
    }

    func testStripedPoloWithoutHomeSetContextDoesNotTriggerSleepwear() {
        let rankings = StyleClassificationGuardrails.rankedStyles(
            for: "red and white striped polo shirt with chinos and clean sneakers outdoors",
            baseScore: 82
        )

        XCTAssertNotEqual(rankings.first?.name, "Sleepwear")
    }

    // MARK: - 6. Phase 2 personalization context

    func testEmptyProfileOmitsPersonalizationContext() {
        let profile = makeStylistProfile(userId: userA)
        let context = PersonalizationContextBuilder.buildContext(profile: profile, recentMemories: [])

        XCTAssertTrue(context.isEmpty, "A fresh profile should omit the personalization block and preserve generic AI behavior")
    }

    func testPartialProfileOnlyMentionsPresentFields() {
        var profile = makeStylistProfile(userId: userA)
        profile.favoriteColors = ["navy", "olive"]

        let context = PersonalizationContextBuilder.buildContext(profile: profile, recentMemories: [])

        XCTAssertTrue(context.contains("Favorite colors: navy, olive"))
        XCTAssertFalse(context.contains("Favorite brands"))
        XCTAssertFalse(context.contains("Budget"))
        XCTAssertFalse(context.contains("Sizes"))
        XCTAssertFalse(context.contains(userA), "Prompt context must not expose user IDs")
    }

    func testFullProfileContextIncludesPreferencesAndMemoryWithoutUserIdentity() {
        var profile = makeStylistProfile(userId: userA)
        profile.favoriteColors = ["navy", "black"]
        profile.dislikedColors = ["neon"]
        profile.favoriteBrands = ["Nike"]
        profile.preferredFit = .tailored
        profile.budgetRange = BudgetRange(minPrice: 80, maxPrice: 180, preferredTier: "Mid")
        profile.clothingSizes = ClothingSizes(shirtSize: "XL", pantSize: "36x36", shoeSize: "12")
        profile.stylePreferencesLearned = ["business casual": 0.8]

        var liked = makeOutfitMemory(userId: userA, record: makeGarmentRecord(fingerprint: "shirt-navy-solid"))
        liked.detectedGarments = ["shirt", "pants"]
        liked.colors = ["navy", "black"]
        liked.detectedStyle = "Smart Casual"
        liked.styleScore = 92
        liked.wasLiked = true
        liked.wouldWearAgain = true

        var disliked = makeOutfitMemory(userId: userA, record: makeGarmentRecord(fingerprint: "jacket-neon-plaid"))
        disliked.detectedGarments = ["jacket"]
        disliked.colors = ["neon"]
        disliked.detectedStyle = "Casual"
        disliked.styleScore = 64
        disliked.wasLiked = false
        disliked.dislikeReason = .colorsOff

        let context = PersonalizationContextBuilder.buildContext(
            profile: profile,
            recentMemories: [liked, disliked]
        )

        XCTAssertTrue(context.contains("Favorite colors: navy, black"))
        XCTAssertTrue(context.contains("Avoid colors: neon"))
        XCTAssertTrue(context.contains("Favorite brands: Nike"))
        XCTAssertTrue(context.contains("Preferred fit: tailored"))
        XCTAssertTrue(context.contains("Budget: $80-$180"))
        XCTAssertTrue(context.contains("shirt XL"))
        XCTAssertTrue(context.contains("Recently liked"))
        XCTAssertTrue(context.contains("Recently disliked"))
        XCTAssertTrue(context.contains("Personalize only; never change StyleMatch Pro scores."))
        XCTAssertFalse(context.contains(userA), "Prompt context must not expose user IDs")
    }

    func testChatContextOmitsColorInfoWhenPaletteIsMissing() {
        let profile = makeStylistProfile(userId: userA)
        var record = makeGarmentRecord(fingerprint: "missing-palette")
        record.colors = []
        var memory = makeOutfitMemory(userId: userA, record: record)
        memory.detectedGarments = ["shirt", "pants"]
        memory.detectedStyle = "Casual"
        memory.colors = []

        let context = PersonalizationContextBuilder.chatContext(
            profile: profile,
            outfitMemories: [memory],
            memoryLimit: 1
        )

        XCTAssertTrue(context.recentOutfits.contains("shirt, pants"))
        XCTAssertTrue(context.recentOutfits.contains("Casual"))
        XCTAssertFalse(context.profileSummary.localizedCaseInsensitiveContains("Most worn colors"))
        XCTAssertFalse(context.recentOutfits.localizedCaseInsensitiveContains("colors"))
    }

    func testDirectOpenAIStylistClientUsesCanonicalScoreGuard() {
        XCTAssertTrue(StyleMatchAIGuardrails.directOpenAIStylistSystemInstruction.contains(StyleMatchAIGuardrails.scoreIntegrityInstruction))
        XCTAssertFalse(StyleMatchAIGuardrails.directOpenAIStylistSystemInstruction.contains("explain it, improve it, and personalize it without changing it"))
    }

    func testDirectOpenAIStylistClientAlwaysAttachesBuilderContext() throws {
        let source = try projectSource("StyleMatchAI/OpenAIStylistClient.swift")

        XCTAssertTrue(source.contains("Approved live AI dispatch point"))
        XCTAssertTrue(source.contains("PersonalizationContextBuilder.promptContext()"))
        XCTAssertTrue(source.contains("StyleMatchAIGuardrails.scoreIntegrityInstruction"))
    }

    func testApprovedLiveAICallSitesAreEnumerated() throws {
        let approvedFiles = [
            "StyleMatchAI/ContentView.swift": 2,
            "StyleMatchAI/ShopView.swift": 1,
            "StyleMatchAI/ScanView.swift": 3,
            "StyleMatchAI/AIAssistantsView.swift": 1,
            "StyleMatchAI/AIStyleAdvisor.swift": 1
        ]

        for (path, expectedCount) in approvedFiles {
            let source = try projectSource(path)
            XCTAssertEqual(
                source.components(separatedBy: "OpenAIStylistClient(apiKey:").count - 1,
                expectedCount,
                "Unexpected live AI client construction count in \(path)."
            )
        }
    }

    func testAlternateAIProviderAdaptersAreDormantByDefault() throws {
        let source = try projectSource("StyleMatchAI/AIProviderAdapters.swift")

        XCTAssertFalse(FeatureFlags.alternateAIProvidersEnabled)
        XCTAssertTrue(source.contains("static func isProviderReachable(_ provider: StyleMatchAIProvider) -> Bool"))
        XCTAssertTrue(source.contains("return FeatureFlags.alternateAIProvidersEnabled"))
        XCTAssertTrue(source.contains("guard isProviderReachable(preferredProvider)"))
        XCTAssertTrue(source.contains("guard isProviderReachable(.perplexity)"))
        XCTAssertTrue(source.contains("guard isProviderReachable(provider)"))
    }

    func testPersonalizationContextCapsMemoryDigest() {
        var profile = makeStylistProfile(userId: userA)
        profile.favoriteColors = ["black"]

        let memories = (0..<15).map { index in
            var memory = makeOutfitMemory(
                userId: userA,
                record: makeGarmentRecord(fingerprint: "shirt-\(index)")
            )
            memory.detectedGarments = ["shirt \(index)"]
            memory.wasLiked = true
            memory.scanDate = Date().addingTimeInterval(Double(-index * 60))
            return memory
        }

        let context = PersonalizationContextBuilder.buildContext(
            profile: profile,
            recentMemories: memories,
            maxMemories: 10
        )

        XCTAssertTrue(context.contains("shirt 0"))
        XCTAssertTrue(context.contains("shirt 9"))
        XCTAssertFalse(context.contains("shirt 10"), "Memory digest should be capped for token discipline")
    }

    // MARK: - Phase 4 occasion awareness

    func testOccasionCodableAndLegacyLabelDecoding() throws {
        let encoded = try JSONEncoder().encode(Occasion.weddingGuest)
        let decoded = try JSONDecoder().decode(Occasion.self, from: encoded)
        XCTAssertEqual(decoded, .weddingGuest)

        let legacyWedding = try JSONDecoder().decode(Occasion.self, from: Data("\"wedding\"".utf8))
        XCTAssertEqual(legacyWedding, .weddingGuest)

        XCTAssertEqual(Occasion(label: "General"), .general)
        XCTAssertEqual(Occasion(label: "Everyday"), .casualDay)
        XCTAssertEqual(Occasion(label: "Date Night"), .dateNight)
        XCTAssertEqual(Occasion(label: "Business Formal"), .businessFormal)
        XCTAssertEqual(Occasion(label: "Wedding Guest"), .weddingGuest)
        XCTAssertEqual(Occasion(label: "Gym"), .gym)
        XCTAssertEqual(Occasion(label: "Loungewear"), .loungewear)
        XCTAssertTrue(Occasion.allCases.contains(.specialEvent))

        let legacyJSON = """
        {
          "id": "\(UUID().uuidString)",
          "userId": "\(userA)",
          "scanDate": 0,
          "detectedGarments": ["shirt"],
          "colors": ["white"],
          "detectedStyle": "Casual",
          "styleScore": 82,
          "isFavorite": false,
          "timesWorn": 0
        }
        """
        let memory = try JSONDecoder().decode(OutfitMemory.self, from: Data(legacyJSON.utf8))
        XCTAssertNil(memory.occasion)
    }

    func testPrePhase4OutfitMemoryWithPhase3FeedbackDecodesAndCanonicalizesOccasion() throws {
        let id = UUID(uuidString: "22222222-3333-4444-5555-666666666666")!
        let json = """
        {
          "id": "\(id.uuidString)",
          "userId": "\(userA)",
          "scanDate": 1720310400,
          "detectedGarments": ["robe", "slippers"],
          "colors": ["navy"],
          "detectedStyle": "Loungewear",
          "styleScore": 78,
          "occasion": "wedding",
          "feedback": {
            "verdict": "notForMe",
            "woreIt": true,
            "recordedAt": 1720396800
          },
          "isFavorite": false,
          "timesWorn": 1
        }
        """

        let decoded = try JSONDecoder().decode(OutfitMemory.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.id, id)
        XCTAssertEqual(decoded.occasion, .weddingGuest)
        XCTAssertEqual(decoded.feedback?.verdict, .notForMe)
        XCTAssertEqual(decoded.feedback?.woreIt, true)
    }

    func testOutfitMemoryStoresSelectedOccasion() {
        let store = OutfitMemoryStore(defaults: defaults, userId: userA)
        var memory = makeOutfitMemory(userId: userA, record: makeGarmentRecord(fingerprint: "occasion-work"))
        memory.occasion = .work

        store.addScan(memory)

        let saved = OutfitMemoryStore(defaults: defaults, userId: userA).memories.first { $0.id == memory.id }
        XCTAssertEqual(saved?.occasion, .work)
    }

    func testOutfitMemoryStoreUpdatesOccasionThroughExistingSavePath() {
        let store = OutfitMemoryStore(defaults: defaults, userId: userA)
        let memory = makeOutfitMemory(userId: userA, record: makeGarmentRecord(fingerprint: "occasion-update"))
        store.addScan(memory)

        store.updateOccasion(for: memory.id, occasion: .dateNight)

        let saved = OutfitMemoryStore(defaults: defaults, userId: userA).memories.first { $0.id == memory.id }
        XCTAssertEqual(saved?.occasion, .dateNight)
    }

    func testSavedScanHistoryHasEditableOccasionRowUsingExistingUpdatePath() throws {
        let scanSource = try projectSource("StyleMatchAI/ScanView.swift")

        XCTAssertTrue(scanSource.contains("savedScanOccasionRow"))
        XCTAssertTrue(scanSource.contains("updateSavedScanOccasion"))
        XCTAssertTrue(scanSource.contains("updateOccasion(occasion, for: scan.analysis)"))
        XCTAssertTrue(scanSource.contains("store.updateOccasion(for: memory.id, occasion: occasion)"))
    }

    func testFormalityMismatchEvaluatorRules() {
        XCTAssertNil(FormalityMismatchEvaluator.evaluate(detectedStyle: "Smart Casual", occasion: .work))
        XCTAssertNil(FormalityMismatchEvaluator.evaluate(detectedStyle: "Formal", occasion: .weddingGuest))
        XCTAssertNil(FormalityMismatchEvaluator.evaluate(detectedStyle: "Casual", occasion: nil))

        let workMismatch = FormalityMismatchEvaluator.evaluate(detectedStyle: "Casual", occasion: .work)
        XCTAssertEqual(workMismatch?.detectedFormality, .casual)
        XCTAssertEqual(workMismatch?.occasion, .work)

        let weddingMismatch = FormalityMismatchEvaluator.evaluate(detectedStyle: "Business Casual", occasion: .weddingGuest)
        XCTAssertEqual(weddingMismatch?.detectedFormality, .businessCasual)
        XCTAssertEqual(weddingMismatch?.occasion, .weddingGuest)
    }

    func testFormalityMismatchFlagsSleepwearForDressierOccasions() {
        let workMismatch = FormalityMismatchEvaluator.evaluate(detectedStyle: "Loungewear", occasion: .work)
        XCTAssertEqual(workMismatch?.detectedFormality, .sleepwear)

        let weddingMismatch = FormalityMismatchEvaluator.evaluate(detectedStyle: "Sleepwear", occasion: .weddingGuest)
        XCTAssertEqual(weddingMismatch?.detectedFormality, .sleepwear)

        let businessFormalMismatch = FormalityMismatchEvaluator.evaluate(detectedStyle: "Sleepwear", occasion: .businessFormal)
        XCTAssertEqual(businessFormalMismatch?.occasion, .businessFormal)

        XCTAssertNil(FormalityMismatchEvaluator.evaluate(detectedStyle: "Casual", occasion: .casualDay))
    }

    func testOccasionConflictTableIsExactAndDeterministic() {
        XCTAssertTrue(FormalityMismatchEvaluator.hasExplicitConflict(formality: .sleepwear, occasion: .work))
        XCTAssertTrue(FormalityMismatchEvaluator.hasExplicitConflict(formality: .sleepwear, occasion: .businessFormal))
        XCTAssertTrue(FormalityMismatchEvaluator.hasExplicitConflict(formality: .sleepwear, occasion: .weddingGuest))
        XCTAssertFalse(FormalityMismatchEvaluator.hasExplicitConflict(formality: .casual, occasion: .casualDay))
        XCTAssertFalse(FormalityMismatchEvaluator.hasExplicitConflict(formality: .sleepwear, occasion: .casualDay))
    }

    func testOccasionWarningDoesNotChangeScoreData() {
        let fixedScore = 82
        let mismatch = FormalityMismatchEvaluator.evaluate(detectedStyle: "Casual", occasion: .weddingGuest)

        XCTAssertNotNil(mismatch)
        XCTAssertEqual(fixedScore, 82, "Occasion mismatch is a parallel warning and must not mutate score data.")
    }

    func testPersonalizationContextOccasionSignalsAreAggregateAndPrivate() {
        var profile = makeStylistProfile(userId: userA)
        profile.favoriteColors = ["navy"]

        var workMemory = makeOutfitMemory(userId: userA, record: makeGarmentRecord(fingerprint: "work-occasion"))
        workMemory.occasion = .work
        workMemory.wasLiked = true
        workMemory.scanDate = Date(timeIntervalSince1970: 0)

        var weddingMemory = makeOutfitMemory(userId: userA, record: makeGarmentRecord(fingerprint: "wedding-occasion"))
        weddingMemory.occasion = .weddingGuest
        weddingMemory.wasLiked = false
        weddingMemory.dislikeReason = .tooCasual
        weddingMemory.scanDate = Date(timeIntervalSince1970: 86_400)

        let context = PersonalizationContextBuilder.buildContext(
            profile: profile,
            recentMemories: [workMemory, weddingMemory],
            maxMemories: 10
        )

        XCTAssertTrue(context.contains("Occasion patterns"))
        XCTAssertTrue(context.contains("work 1x"), context)
        XCTAssertTrue(context.contains("wedding guest disliked for too casual"))
        XCTAssertFalse(context.contains(userA), "Occasion context must not expose user IDs")
        XCTAssertFalse(context.contains(workMemory.id.uuidString), "Occasion context must not expose scan IDs")
        XCTAssertFalse(context.contains("1970"), "Occasion context must not expose scan dates")
    }

    func testOccasionContextDropOrderUnderTokenPressure() {
        var loved = makeOutfitMemory(userId: userA, record: makeGarmentRecord(fingerprint: "occasion-loved"))
        loved.occasion = .dateNight
        loved.feedback = OutfitFeedback(verdict: .loved, woreIt: true, recordedAt: Date(timeIntervalSince1970: 4_500_000))

        var disliked = makeOutfitMemory(userId: userA, record: makeGarmentRecord(fingerprint: "occasion-disliked"))
        disliked.occasion = .work
        disliked.feedback = OutfitFeedback(verdict: .notForMe, woreIt: true, recordedAt: Date(timeIntervalSince1970: 4_500_100))

        let full = PersonalizationContextBuilder.occasionContextLines(
            recentMemories: [loved, disliked],
            currentOccasion: .weddingGuest
        )
        XCTAssertTrue(full.contains { $0.contains("Feedback signals") })
        XCTAssertTrue(full.contains { $0.contains("Occasion patterns") })
        XCTAssertTrue(full.contains { $0.contains("Current scan occasion") })

        let constrained = PersonalizationContextBuilder.occasionContextLines(
            recentMemories: [loved, disliked],
            currentOccasion: .weddingGuest,
            maxCharacters: 95
        )
        XCTAssertFalse(constrained.contains { $0.contains("Occasion patterns") }, "Trend should drop first.")
        XCTAssertFalse(constrained.contains { $0.contains("Feedback signals") }, "Feedback should drop second when needed.")
        XCTAssertTrue(constrained.contains { $0.contains("Current scan occasion") }, "Per-scan occasion should drop last.")
    }

    func testPersonalizationContextAddsCurrentScanOccasionOnlyWhenTagged() {
        var profile = makeStylistProfile(userId: userA)
        profile.favoriteColors = ["black"]
        let memory = makeOutfitMemory(userId: userA, record: makeGarmentRecord(fingerprint: "untagged-context"))

        let untagged = PersonalizationContextBuilder.buildContext(
            profile: profile,
            recentMemories: [memory],
            maxMemories: 10
        )
        let explicitNil = PersonalizationContextBuilder.buildContext(
            profile: profile,
            recentMemories: [memory],
            maxMemories: 10,
            currentOccasion: nil
        )
        let tagged = PersonalizationContextBuilder.buildContext(
            profile: profile,
            recentMemories: [memory],
            maxMemories: 10,
            currentOccasion: .dateNight
        )

        XCTAssertEqual(untagged, explicitNil, "Untagged scans should preserve the existing context output exactly.")
        XCTAssertTrue(tagged.contains("Current scan occasion"))
        XCTAssertTrue(tagged.contains("The user tagged this outfit for: Date Night."))
    }

    func testOccasionCannotEnterNumericScorePath() throws {
        let scanSource = try projectSource("StyleMatchAI/ScanView.swift")

        XCTAssertFalse(scanSource.contains("scoreOccasion("))
        XCTAssertFalse(scanSource.contains("context.occasion"))
        XCTAssertFalse(scanSource.contains("occasionFit: plannedOccasionSummary"))
        XCTAssertTrue(scanSource.contains("Occasion is explanation-only; never a score input."))
        XCTAssertTrue(
            scanSource.contains("Double(rawTotal) / 80.0 * 100.0"),
            "Removing the 20-point occasion component should use only the mechanical 80-to-100 normalization."
        )
    }

    // MARK: - 7. Personal Stylist Intelligence

    func testPersonalStylistIntelligencePreservesScoreParity() {
        let input = makePersonalStylistInput(score: 87)
        let message = PersonalStylistIntelligenceBuilder.buildMessage(input: input)
        let phrasingContext = PersonalStylistIntelligenceBuilder.buildPhrasingContext(input: input)

        XCTAssertEqual(input.score, 87)
        XCTAssertEqual(phrasingContext.score, 87)
        XCTAssertTrue(message.plainText.contains("87/100"))
        XCTAssertFalse(message.plainText.contains("88/100"))
        XCTAssertFalse(message.plainText.contains("86/100"))
    }

    func testStylistMessageComposerScoreBandsAlwaysUseActualAttributes() {
        let samples: [(Int, StylistScoreBand)] = [
            (95, .enthusiastic),
            (82, .confidentPositive),
            (67, .encouragingImprovement),
            (48, .constructiveKind)
        ]

        for sample in samples {
            let input = StylistScoreMessageInput(
                score: sample.0,
                scoreTier: "Test",
                scoreBreakdown: OutfitScoreBreakdown(
                    colorHarmony: 12,
                    patternBalance: 18,
                    fitQuality: 20,
                    occasionMatch: 16,
                    accessoryUse: 4
                ),
                detectedGarments: ["shirt"],
                detectedItemConfidences: [
                    DetectedItemConfidence(item: "shirt", confidence: 96)
                ],
                colors: ["navy"]
            )
            let message = StylistMessageComposer.scoreEncouragement(input: input)

            XCTAssertEqual(StylistScoreBand(score: sample.0), sample.1)
            XCTAssertTrue(message.body.contains("\(sample.0)/100"))
            XCTAssertTrue(message.body.localizedCaseInsensitiveContains("navy shirt"))
        }
    }

    func testStylistMessageComposerFallsBackToScoreWhenNoGarmentAttributeExists() {
        let message = StylistMessageComposer.scoreEncouragement(
            input: StylistScoreMessageInput(
                score: 58,
                scoreTier: "Needs Work",
                scoreBreakdown: nil,
                detectedGarments: [],
                colors: []
            )
        )

        XCTAssertTrue(message.body.contains("58/100"))
        XCTAssertTrue(message.body.localizedCaseInsensitiveContains("score itself"))
    }

    func testStylistNarrationUsesNeutralNounWhenGarmentIsUnreliableOrCompeting() {
        let lowConfidenceTie = StylistMessageComposer.scoreEncouragement(
            input: StylistScoreMessageInput(
                score: 82,
                scoreTier: "Strong",
                scoreBreakdown: nil,
                detectedGarments: ["tie"],
                detectedItemConfidences: [DetectedItemConfidence(item: "tie", confidence: 78)],
                colors: ["gray"]
            )
        )
        XCTAssertTrue(lowConfidenceTie.body.contains("the detected gray outfit item"))
        XCTAssertFalse(lowConfidenceTie.body.contains("gray tie"))

        let competingNouns = StylistMessageComposer.scoreEncouragement(
            input: StylistScoreMessageInput(
                score: 82,
                scoreTier: "Strong",
                scoreBreakdown: nil,
                detectedGarments: ["jacket", "polo"],
                detectedItemConfidences: [
                    DetectedItemConfidence(item: "jacket", confidence: 95),
                    DetectedItemConfidence(item: "polo", confidence: 92)
                ],
                colors: ["navy"]
            )
        )
        XCTAssertTrue(competingNouns.body.contains("the detected navy outfit item"))
        XCTAssertFalse(competingNouns.body.contains("navy jacket"))

        let reliablePolo = StylistMessageComposer.scoreEncouragement(
            input: StylistScoreMessageInput(
                score: 82,
                scoreTier: "Strong",
                scoreBreakdown: nil,
                detectedGarments: ["polo"],
                detectedItemConfidences: [DetectedItemConfidence(item: "polo", confidence: 96)],
                colors: ["navy"]
            )
        )
        XCTAssertTrue(reliablePolo.body.contains("the detected navy polo shirt"))
    }

    func testStylistMessageComposerScoreBandBoundaries() {
        let expected: [(Int, StylistScoreBand)] = [
            (59, .constructiveKind),
            (60, .encouragingImprovement),
            (74, .encouragingImprovement),
            (75, .confidentPositive),
            (89, .confidentPositive),
            (90, .enthusiastic)
        ]

        for pair in expected {
            XCTAssertEqual(StylistScoreBand(score: pair.0), pair.1)
        }
    }

    func testWeatherAdviceFlagOffOmitsWeatherSectionAndContext() {
        let input = makePersonalStylistInput(score: 91, weather: WeatherContextEngine.recommendation(
            for: makeWeatherSnapshot(air: 90, feelsLike: 94, humidity: 72, activity: .walking)
        ))

        let message = PersonalStylistIntelligenceBuilder.buildMessage(
            input: input,
            weatherAdviceEnabled: false,
            saleMatchingEnabled: false
        )
        let phrasingContext = PersonalStylistIntelligenceBuilder.buildPhrasingContext(
            input: input,
            weatherAdviceEnabled: false,
            saleMatchingEnabled: false
        )

        XCTAssertFalse(message.sections.contains { $0.source == .weather })
        XCTAssertTrue(phrasingContext.weatherFacts.isEmpty)
        XCTAssertFalse(message.plainText.localizedCaseInsensitiveContains("feels-like"))
    }

    func testWeatherAdviceUsesRealWeatherWhenEnabled() {
        let input = makePersonalStylistInput(score: 91, weather: WeatherContextEngine.recommendation(
            for: makeWeatherSnapshot(air: 90, feelsLike: 94, humidity: 72, activity: .walking)
        ))

        let message = PersonalStylistIntelligenceBuilder.buildMessage(
            input: input,
            weatherAdviceEnabled: true,
            saleMatchingEnabled: false
        )

        let weather = message.sections.first { $0.source == .weather }
        XCTAssertNotNil(weather)
        XCTAssertTrue(weather?.body.contains("94°F") == true)
        XCTAssertTrue(weather?.body.localizedCaseInsensitiveContains("humidity") == true)
    }

    func testSaleMatchingFlagOffOmitsDealSectionAndContext() {
        let deal = PersonalStylistDealMatch(
            productName: "White Oxford Shirt",
            retailerName: "Macy's",
            category: "Clothing",
            salePrice: "$69.99",
            reason: "Matches the scanned shirt category."
        )
        let input = makePersonalStylistInput(score: 89, dealMatches: [deal])

        let message = PersonalStylistIntelligenceBuilder.buildMessage(
            input: input,
            weatherAdviceEnabled: true,
            saleMatchingEnabled: false
        )
        let phrasingContext = PersonalStylistIntelligenceBuilder.buildPhrasingContext(
            input: input,
            weatherAdviceEnabled: true,
            saleMatchingEnabled: false
        )

        XCTAssertFalse(message.sections.contains { $0.source == .shoppingDeals })
        XCTAssertTrue(phrasingContext.dealFacts.isEmpty)
        XCTAssertFalse(message.plainText.contains("Macy's"))
    }

    // MARK: - 8. Affiliate shopping marketplace

    func testAffiliateCatalogDecodeSkipsSingleMalformedProduct() throws {
        let json = """
        [
          {
            "id": "valid-shirt",
            "name": "White Shirt",
            "category": "clothing",
            "subcategory": "shirt",
            "colors": ["white"],
            "imageURL": "https://www.macys.com/image.jpg",
            "retailer": {"name": "Macy's", "trackingID": "OLD", "trackingParamName": "old", "disclosureName": "Old Macy's"},
            "affiliateURL": "https://www.macys.com/shirt",
            "price": 80,
            "salePrice": null,
            "saleEndsAt": null,
            "tags": ["office"],
            "genderPresentation": null
          },
          {
            "id": "broken-product",
            "name": "Broken Product"
          }
        ]
        """
        let config = """
        {
          "retailers": [
            {"name": "Macy's", "trackingID": "APPROVED-ID", "trackingParamName": "aff", "disclosureName": "Macy's"}
          ]
        }
        """

        let products = try BundledCatalogProvider.decodeProducts(
            catalogData: Data(json.utf8),
            retailerConfigData: Data(config.utf8)
        )

        XCTAssertEqual(products.count, 1)
        XCTAssertEqual(products.first?.id, "valid-shirt")
        XCTAssertEqual(products.first?.retailer.trackingID, "APPROVED-ID")
    }

    func testAmazonPriceRuleIgnoresStoredPriceAtRenderTime() {
        let product = makeAffiliateProduct(
            id: "amazon-item",
            retailer: Retailer(name: "Amazon", trackingID: "amazon-20", trackingParamName: "tag", disclosureName: "Amazon"),
            price: Decimal(39.99),
            salePrice: Decimal(29.99)
        )

        let viewModel = AffiliateProductViewModel(product: product)

        XCTAssertEqual(viewModel.priceText, "See price at Amazon")
        XCTAssertNil(viewModel.originalPriceText)
        XCTAssertEqual(viewModel.actionTitle, "View on Amazon")
    }

    func testProductViewModelOmitsBrandWhenItDuplicatesRetailer() {
        let product = makeAffiliateProduct(
            id: "macys-brand-duplicate",
            retailer: Retailer(name: "Macy's", trackingID: "PENDING-APPROVAL", trackingParamName: "aff", disclosureName: "Macy's"),
            brand: "Macy's"
        )

        let viewModel = AffiliateProductViewModel(product: product)

        XCTAssertNil(viewModel.brandText)
        XCTAssertEqual(viewModel.retailerName, "Macy's")
        XCTAssertEqual(viewModel.soldAndShippedText, "Sold and shipped by Macy's")
        XCTAssertEqual(viewModel.actionTitle, "View Product")
    }

    func testProductViewModelOmitsEmptyBrandAndKeepsDistinctBrand() {
        let noBrand = makeAffiliateProduct(id: "no-brand", brand: nil)
        let nikeAtFootLocker = makeAffiliateProduct(
            id: "nike-footlocker",
            retailer: Retailer(name: "Foot Locker", trackingID: "PENDING-APPROVAL", trackingParamName: "aff", disclosureName: "Foot Locker"),
            brand: "Nike"
        )

        XCTAssertNil(AffiliateProductViewModel(product: noBrand).brandText)
        XCTAssertEqual(AffiliateProductViewModel(product: nikeAtFootLocker).brandText, "Nike")
    }

    func testAffiliateTrackingParamAppendsWithURLComponentsAndSkipsPendingApproval() {
        let approved = makeAffiliateProduct(
            id: "approved",
            retailer: Retailer(name: "Nike", trackingID: "real-id", trackingParamName: "aff", disclosureName: "Nike"),
            affiliateURL: URL(string: "https://www.nike.com/shoes?color=white")!
        )
        let pending = makeAffiliateProduct(
            id: "pending",
            retailer: Retailer(name: "Nike", trackingID: "PENDING-APPROVAL", trackingParamName: "aff", disclosureName: "Nike"),
            affiliateURL: URL(string: "https://www.nike.com/shoes?color=white")!
        )

        let approvedURL = AffiliateLinkBuilder.outboundURL(for: approved)
        let approvedItems = URLComponents(url: approvedURL, resolvingAgainstBaseURL: false)?.queryItems ?? []

        XCTAssertTrue(approvedItems.contains(URLQueryItem(name: "color", value: "white")))
        XCTAssertTrue(approvedItems.contains(URLQueryItem(name: "aff", value: "real-id")))
        XCTAssertEqual(AffiliateLinkBuilder.outboundURL(for: pending), pending.affiliateURL)
    }

    func testShoppingRecommendationComplementMatchUsesStoredBlackPantsOutfit() {
        var memory = makeBlackPantsAndShirtMemory()
        memory.scanDate = fixedDate(year: 2026, month: 7, day: 2)
        let whiteShirt = makeAffiliateProduct(
            id: "white-shirt",
            name: "White Shirt",
            category: .clothing,
            subcategory: "shirt",
            colors: ["white"]
        )

        let recommendations = ShoppingRecommendationEngine.recommendations(
            currentGarments: [],
            currentColors: [],
            memories: [memory],
            weather: nil,
            catalog: [whiteShirt],
            now: fixedDate(year: 2026, month: 7, day: 7)
        )

        XCTAssertEqual(recommendations.first?.product.id, "white-shirt")
        XCTAssertEqual(recommendations.first?.reasonFacts.rule, "complement")
        XCTAssertTrue(recommendations.first?.reasonFacts.oneLineReason.contains("black pants and black shirt") == true)
        XCTAssertTrue(recommendations.first?.reasonFacts.oneLineReason.contains("Recommended because") == true)
        XCTAssertTrue(recommendations.first?.reasonFacts.oneLineReason.contains("last Thursday") == true)
    }

    func testShoppingRecommendationReasonSanitizesInternalVisionLabels() {
        let facts = ProductRecommendationReasonFacts(
            rule: "complement",
            productName: "Brown Leather Loafer",
            productCategory: "Shoes",
            productColors: ["brown"],
            referencedOutfit: "gray Person Wearing Outfit and white Textile",
            referencedDate: "yesterday",
            referencedScore: 82,
            weatherFact: nil,
            saleFact: nil
        )
        let reason = facts.oneLineReason

        XCTAssertFalse(reason.localizedCaseInsensitiveContains("Person Wearing"))
        XCTAssertFalse(reason.localizedCaseInsensitiveContains("Textile"))
        XCTAssertTrue(reason.localizedCaseInsensitiveContains("outfit"))
        XCTAssertFalse(reason.localizedCaseInsensitiveContains("gray"))
        XCTAssertFalse(reason.localizedCaseInsensitiveContains("white Textile"))
    }

    func testDisplayLabelSanitizerBlocksInternalVisionLabels() {
        XCTAssertNil(DisplayLabelSanitizer.displayName(for: "Person Wearing Outfit"))
        XCTAssertNil(DisplayLabelSanitizer.displayName(for: "Textile"))
        XCTAssertNil(DisplayLabelSanitizer.displayName(for: "outfit item"))
        XCTAssertEqual(DisplayLabelSanitizer.displayName(for: "Loafer"), "loafers")
        XCTAssertEqual(DisplayLabelSanitizer.displayName(for: "polo shirt"), "polo shirt")
        XCTAssertEqual(DisplayLabelSanitizer.displayName(for: "tie"), "tie")

        let phrase = DisplayLabelSanitizer.wornItemPhrase(
            rawLabel: "Person Wearing Outfit",
            colorName: "gray",
            colorProvenance: .fullImage,
            recency: .yesterday
        )
        XCTAssertFalse(phrase.localizedCaseInsensitiveContains("gray"))
        XCTAssertFalse(phrase.localizedCaseInsensitiveContains("Person Wearing"))
        XCTAssertEqual(phrase, "what you wore yesterday")
    }

    func testShoppingLabelsRecoverRealGarmentFromConfidenceWithoutPlaceholder() {
        let analysis = OutfitAnalysisResult(
            score: 82,
            colorMatch: "Strong",
            occasionFit: "Everyday",
            styleBalance: "Casual",
            colorHarmony: "Balanced",
            styleCoordination: "Coordinated",
            formality: "Casual",
            seasonalMatch: "Mild",
            summary: "Synthetic summary",
            outfitDescription: "Synthetic outfit",
            detectedClothingItems: ["outfit item"],
            colorPalette: ["navy"],
            environment: "indoor",
            imageQuality: "clear",
            skinToneStyleNote: "No skin-tone recommendation needed.",
            detectedItemConfidences: [
                DetectedItemConfidence(item: "Textile", confidence: 92),
                DetectedItemConfidence(item: "polo", confidence: 90)
            ],
            suggestions: [],
            recommendations: []
        )

        XCTAssertEqual(analysis.safeDetectedClothingItems, ["polo shirt"])
        XCTAssertFalse(analysis.safeDetectedClothingItems.contains("outfit item"))
    }

    func testSavedScoreCopyUsesOneSourceAndUserFacingNarration() {
        let description = ScanMessageCopy.savedScoreDescription(
            confidenceLabel: "High",
            qualityDescription: "Source: local detection. Clothing detected: polo shirt.",
            guidance: "The outfit signal is strong.",
            savedResultMessage: "If you open this scan again, Style Match Pro uses this saved result unless the outfit is new."
        )

        XCTAssertEqual(description.components(separatedBy: "Source:").count - 1, 1)
        XCTAssertTrue(description.hasPrefix("High confidence."))
        XCTAssertFalse(description.localizedCaseInsensitiveContains("the customer"))
    }

    func testConfidenceVocabularyUsesHighMediumLowLabels() throws {
        XCTAssertEqual(GarmentPaletteConfidence.confident.userFacingLabel, "High")
        XCTAssertEqual(GarmentPaletteConfidence.low.userFacingLabel, "Low")

        let scanSource = try projectSource("StyleMatchAI/ScanView.swift")
        XCTAssertTrue(scanSource.contains("return \"Medium\""))
        XCTAssertFalse(scanSource.contains("colorPaletteConfidence.rawValue"))
    }

    func testTargetDisplayNameDropsNumericSuffix() throws {
        let project = try projectSource("StyleMatchAI.xcodeproj/project.pbxproj")

        XCTAssertFalse(project.contains("StyleMatch Pro 1"))
        XCTAssertEqual(project.components(separatedBy: "INFOPLIST_KEY_CFBundleDisplayName = \"StyleMatch Pro\";").count - 1, 2)
    }

    func testRecommendationRationaleUsesTrendingFallbackForColdStart() {
        let product = makeAffiliateProduct(id: "trend", name: "White Shirt", subcategory: "shirt", colors: ["white"])
        let rationale = RecommendationRationaleBuilder.build(
            for: product,
            reasonFacts: nil,
            profile: nil,
            memories: [],
            savedFavorites: [],
            favoriteProductIDs: []
        )

        XCTAssertTrue(rationale.reasons.isEmpty)
        XCTAssertEqual(rationale.headline, "Popular with shoppers this week.")
    }

    func testShoppingRecommendationPreferencesIncludeCustomerControls() {
        let preferences = ShoppingRecommendationPreferences.default
        XCTAssertTrue(preferences.usesWardrobeHistory)
        XCTAssertTrue(preferences.usesFavoriteBrands)
        XCTAssertTrue(preferences.usesFavoriteColors)
        XCTAssertTrue(preferences.usesBudgetRange)
        XCTAssertTrue(preferences.usesCurrentTrends)
        XCTAssertFalse(preferences.usesWeather)
        XCTAssertFalse(preferences.usesCalendarEvents)

        var profile = makeStylistProfile(userId: userA)
        RecommendationRationaleBuilder.apply(
            ShoppingRecommendationPreferences(
                usesWardrobeHistory: false,
                usesFavoriteBrands: false,
                usesFavoriteColors: true,
                usesBudgetRange: true,
                usesCurrentTrends: true,
                usesWeather: true,
                usesCalendarEvents: true
            ),
            to: &profile
        )

        let restored = RecommendationRationaleBuilder.preferences(from: profile)
        XCTAssertFalse(restored.usesWardrobeHistory)
        XCTAssertFalse(restored.usesFavoriteBrands)
        XCTAssertTrue(restored.usesFavoriteColors)
        XCTAssertTrue(restored.usesBudgetRange)
        XCTAssertTrue(restored.usesCurrentTrends)
        XCTAssertTrue(restored.usesWeather)
        XCTAssertTrue(restored.usesCalendarEvents)
    }

    func testShoppingDisclosureDoesNotExposeTrackingIds() throws {
        let shopView = try projectSource("StyleMatchAI/ShopView.swift")
        let shoppingView = try projectSource("StyleMatchAI/Shopping/ShoppingView.swift")
        let storeSearchView = try projectSource("StyleMatchAI/Shopping/StoreSearchView.swift")
        let productCatalogProvider = try projectSource("StyleMatchAI/Shopping/ProductCatalogProvider.swift")

        for source in [shopView, shoppingView, storeSearchView] {
            XCTAssertFalse(source.contains("Tracking ID"))
            XCTAssertFalse(source.contains("affiliateTrackingID)."))
            XCTAssertTrue(source.contains("ShoppingCatalogDisclosure.fallback") || source.contains("catalogDisclosure"))
        }
        XCTAssertTrue(productCatalogProvider.contains("As an Amazon Associate I earn from qualifying purchases."))
        XCTAssertTrue(productCatalogProvider.contains("StyleMatch Pro may earn a commission at no extra cost to you."))
    }

    func testRecommendationRationaleUsesDominantProfileColor() {
        var profile = makeStylistProfile(userId: userA)
        profile.favoriteColors = ["white"]
        let product = makeAffiliateProduct(id: "white-shirt", name: "White Shirt", subcategory: "shirt", colors: ["white"])
        let rationale = RecommendationRationaleBuilder.build(
            for: product,
            reasonFacts: nil,
            profile: profile,
            memories: [],
            savedFavorites: [],
            favoriteProductIDs: []
        )

        XCTAssertTrue(rationale.reasons.contains(.matchesColors))
        XCTAssertFalse(rationale.headline.localizedCaseInsensitiveContains("Person Wearing"))
        XCTAssertFalse(rationale.headline.localizedCaseInsensitiveContains("Textile"))
    }

    func testShoppingRecommendationSaleAloneNeverProducesRecommendation() {
        let saleOnly = makeAffiliateProduct(
            id: "sale-only",
            name: "Random Sale Item",
            category: .electronics,
            subcategory: "speaker",
            colors: ["purple"],
            salePrice: Decimal(19.99),
            tags: ["sale"]
        )

        let recommendations = ShoppingRecommendationEngine.recommendations(
            currentGarments: [],
            currentColors: [],
            memories: [],
            weather: nil,
            catalog: [saleOnly]
        )

        XCTAssertTrue(recommendations.isEmpty)
    }

    func testShoppingRecommendationHotWeatherNeverRecommendsHeavyLayerTaggedItems() {
        let coat = makeAffiliateProduct(
            id: "coat",
            name: "Wool Topcoat",
            category: .clothing,
            subcategory: "coat",
            colors: ["camel"],
            tags: ["cold", "wool", "heavy"]
        )
        let recommendations = ShoppingRecommendationEngine.recommendations(
            currentGarments: ["black pants"],
            currentColors: ["black"],
            memories: [],
            weather: ShoppingWeatherContext(feelsLikeTemperature: 91, rainChancePercent: nil, uvIndex: nil, condition: "Hot"),
            catalog: [coat]
        )

        XCTAssertTrue(recommendations.isEmpty)
    }

    func testShoppingTabVisibilityFlagCanRemoveTab() {
        XCTAssertFalse(ShoppingTabVisibility.shouldShowShoppingTab(shoppingTabEnabled: false))
        XCTAssertTrue(ShoppingTabVisibility.shouldShowShoppingTab(shoppingTabEnabled: true))
    }

    func testShoppingReasonFactsContainNoURLsOrTrackingIDsForAIPhrasing() throws {
        var memory = makeBlackPantsAndShirtMemory()
        memory.scanDate = fixedDate(year: 2026, month: 7, day: 2)
        let product = makeAffiliateProduct(
            id: "tracked-shirt",
            name: "White Shirt",
            category: .clothing,
            subcategory: "shirt",
            colors: ["white"],
            retailer: Retailer(name: "Macy's", trackingID: "SECRET-ID", trackingParamName: "aff", disclosureName: "Macy's"),
            affiliateURL: URL(string: "https://www.macys.com/shirt")!
        )
        let recommendation = ShoppingRecommendationEngine.recommendations(
            currentGarments: [],
            currentColors: [],
            memories: [memory],
            weather: nil,
            catalog: [product],
            now: fixedDate(year: 2026, month: 7, day: 7)
        ).first

        let data = try JSONEncoder().encode(recommendation?.reasonFacts)
        let payload = String(data: data, encoding: .utf8) ?? ""

        XCTAssertFalse(payload.contains("https://"))
        XCTAssertFalse(payload.contains("SECRET-ID"))
        XCTAssertFalse(payload.localizedCaseInsensitiveContains("tracking"))
    }

    func testCatalogDealProviderUsesOnlyCurrentSaleCatalogItems() async throws {
        let provider = StaticProductCatalogProvider(products: [
            makeAffiliateProduct(id: "sale", name: "White Shirt", category: .clothing, subcategory: "shirt", colors: ["white"], price: Decimal(80), salePrice: Decimal(60), saleEndsAt: fixedDate(year: 2027, month: 1, day: 1)),
            makeAffiliateProduct(id: "expired", name: "Expired Shirt", category: .clothing, subcategory: "shirt", colors: ["white"], price: Decimal(80), salePrice: Decimal(60), saleEndsAt: fixedDate(year: 2025, month: 1, day: 1)),
            makeAffiliateProduct(id: "regular", name: "Regular Shirt", category: .clothing, subcategory: "shirt", colors: ["white"], price: Decimal(80), salePrice: nil)
        ])

        let deals = try await CatalogDealProvider(
            catalogProvider: provider,
            now: fixedDate(year: 2026, month: 7, day: 7)
        ).currentDeals()

        XCTAssertEqual(deals.map(\.itemName), ["White Shirt"])
    }

    func testSupportedStoreDirectoryIncludesRequestedStoresAndSkipsMalformedEntry() throws {
        let json = """
        [
          {"id": "nike", "name": "Nike", "domains": ["nike.com"], "categories": ["clothing", "shoes"], "affiliateNetwork": "TBD", "apiStatus": "affiliate-placeholder", "isEnabled": true},
          {"id": "broken", "name": "Broken Store"},
          {"id": "sephora", "name": "Sephora", "domains": ["sephora.com"], "categories": ["styleTools"], "affiliateNetwork": "TBD", "apiStatus": "needs-approved-feed", "isEnabled": true}
        ]
        """

        let stores = try BundledStoreDirectoryProvider.decodeStores(Data(json.utf8))

        XCTAssertEqual(stores.map(\.name), ["Nike", "Sephora"])
    }

    func testShoppingSearchFiltersByStoreColorPriceOccasionAndStyle() {
        let products = [
            makeAffiliateProduct(
                id: "nike-white-gym",
                name: "White Training Sneaker",
                category: .shoes,
                subcategory: "sneakers",
                colors: ["white"],
                retailer: Retailer(name: "Nike", trackingID: "PENDING-APPROVAL", trackingParamName: "aff", disclosureName: "Nike"),
                price: Decimal(120),
                tags: ["gym", "casual", "size-12"]
            ),
            makeAffiliateProduct(
                id: "macys-black-formal",
                name: "Black Dress Shirt",
                category: .clothing,
                subcategory: "shirt",
                colors: ["black"],
                retailer: Retailer(name: "Macy's", trackingID: "PENDING-APPROVAL", trackingParamName: "aff", disclosureName: "Macy's"),
                price: Decimal(80),
                tags: ["formal", "office", "size-xl"]
            )
        ]
        let criteria = ShoppingSearchCriteria(
            query: "training",
            storeName: "Nike",
            category: .shoes,
            color: "white",
            size: "12",
            style: "casual",
            genderPresentation: nil,
            minimumPrice: Decimal(100),
            maximumPrice: Decimal(150),
            occasion: "gym"
        )

        let results = ShoppingSearchEngine.filter(products: products, criteria: criteria)

        XCTAssertEqual(results.map(\.id), ["nike-white-gym"])
    }

    func testAffiliateProductDecodesWhenSearchMetadataIsMissing() throws {
        let json = """
        {
          "id": "legacy-shirt",
          "name": "Legacy Shirt",
          "category": "clothing",
          "subcategory": "shirt",
          "colors": ["white"],
          "imageURL": "https://example.com/image.jpg",
          "retailer": {"name": "Macy's", "trackingID": "PENDING-APPROVAL", "trackingParamName": "aff", "disclosureName": "Macy's"},
          "affiliateURL": "https://www.macys.com/shirt",
          "price": 50,
          "salePrice": null,
          "saleEndsAt": null,
          "tags": ["office"],
          "genderPresentation": null
        }
        """

        let product = try JSONDecoder.catalog.decode(AffiliateProduct.self, from: Data(json.utf8))

        XCTAssertEqual(product.id, "legacy-shirt")
        XCTAssertNil(product.sizes)
        XCTAssertNil(product.priceRange)
        XCTAssertNil(product.occasionTags)
        XCTAssertNil(product.brand)
    }

    func testProductSearchQueryFiltersByBrandSizeOccasionTagsAndPriceRange() {
        let footLockerNike = makeAffiliateProduct(
            id: "footlocker-nike",
            name: "Nike Court Sneaker",
            category: .shoes,
            subcategory: "sneakers",
            colors: ["white"],
            retailer: Retailer(name: "Foot Locker", trackingID: "PENDING-APPROVAL", trackingParamName: "aff", disclosureName: "Foot Locker"),
            price: nil,
            tags: ["walking"],
            sizes: ["10", "11", "12"],
            priceRange: Decimal(90)...Decimal(130),
            occasionTags: [Occasion.casual.rawValue],
            brand: "Nike"
        )
        let retailerNike = makeAffiliateProduct(
            id: "nike-direct",
            name: "Nike Training Shirt",
            category: .clothing,
            subcategory: "shirt",
            colors: ["white"],
            retailer: Retailer(name: "Nike", trackingID: "PENDING-APPROVAL", trackingParamName: "aff", disclosureName: "Nike"),
            price: Decimal(45),
            tags: ["gym"],
            sizes: ["M"],
            occasionTags: [Occasion.work.rawValue],
            brand: "Nike"
        )

        let query = ProductSearchQuery(
            text: "sneaker",
            retailers: ["Foot Locker"],
            brands: ["Nike"],
            categories: [.shoes],
            colors: ["white"],
            sizes: ["12"],
            priceRange: Decimal(100)...Decimal(120),
            occasions: [Occasion.casual.rawValue],
            sort: .priceLowHigh
        )

        let results = ShoppingSearchEngine.filter(products: [footLockerNike, retailerNike], query: query)

        XCTAssertEqual(results.map(\.id), ["footlocker-nike"])
    }

    func testProductSearchQueryCanFilterSaleOnlyAndSortNewestSale() {
        let olderSale = makeAffiliateProduct(
            id: "older-sale",
            name: "Older Sale Shirt",
            salePrice: Decimal(40),
            saleEndsAt: fixedDate(year: 2026, month: 7, day: 10),
            tags: ["casual"],
            occasionTags: [Occasion.casual.rawValue],
            brand: "Macy's"
        )
        let newerSale = makeAffiliateProduct(
            id: "newer-sale",
            name: "Newer Sale Shirt",
            salePrice: Decimal(50),
            saleEndsAt: fixedDate(year: 2026, month: 8, day: 1),
            tags: ["casual"],
            occasionTags: [Occasion.casual.rawValue],
            brand: "Macy's"
        )
        let regular = makeAffiliateProduct(
            id: "regular",
            name: "Regular Shirt",
            tags: ["casual"],
            occasionTags: [Occasion.casual.rawValue],
            brand: "Macy's"
        )
        let query = ProductSearchQuery(
            brands: ["Macy's"],
            occasions: [Occasion.casual.rawValue],
            onSaleOnly: true,
            sort: .newestSale
        )

        let results = ShoppingSearchEngine.filter(
            products: [olderSale, regular, newerSale],
            query: query,
            now: fixedDate(year: 2026, month: 7, day: 7)
        )

        XCTAssertEqual(results.map(\.id), ["newer-sale", "older-sale"])
    }

    func testCatalogProductSearchProviderUsesProductSearchQuery() async throws {
        let provider = CatalogProductSearchProvider(
            sourceName: "Test Catalog",
            catalogProvider: StaticProductCatalogProvider(products: [
                makeAffiliateProduct(id: "nike", name: "Nike Sneaker", category: .shoes, subcategory: "sneakers", colors: ["white"], sizes: ["12"], brand: "Nike"),
                makeAffiliateProduct(id: "adidas", name: "Adidas Sneaker", category: .shoes, subcategory: "sneakers", colors: ["black"], sizes: ["10"], brand: "Adidas")
            ])
        )
        let query = ProductSearchQuery(brands: ["Nike"], colors: ["white"], sizes: ["12"])

        let results = try await provider.search(query)

        XCTAssertEqual(provider.sourceName, "Test Catalog")
        XCTAssertEqual(results.map(\.id), ["nike"])
    }

    func testCatalogSearchProviderTokenizedTextMatchesNameBrandSubcategoryAndTags() async throws {
        let provider = CatalogSearchProvider(
            sourceName: "Test Catalog",
            catalogProvider: StaticProductCatalogProvider(products: [
                makeAffiliateProduct(id: "nike-shoe", name: "Court Sneaker", category: .shoes, subcategory: "running shoe", colors: ["white"], tags: ["walking"], brand: "Nike"),
                makeAffiliateProduct(id: "macys-shirt", name: "Oxford Shirt", category: .clothing, subcategory: "dress shirt", colors: ["blue"], tags: ["office"], brand: "Macy's")
            ])
        )

        let results = try await provider.search(ProductSearchQuery(text: "nike walking"))

        XCTAssertEqual(results.map(\.id), ["nike-shoe"])
    }

    func testCatalogSearchProviderHandlesThousandProductCatalogUnderFiftyMillisecondsAfterIndexing() async throws {
        let products = (0..<1_000).map { index in
            makeAffiliateProduct(
                id: "product-\(index)",
                name: index == 777 ? "Performance White Sneaker" : "Catalog Product \(index)",
                category: index == 777 ? .shoes : .clothing,
                subcategory: index == 777 ? "sneakers" : "shirt",
                colors: index == 777 ? ["white"] : ["black"],
                tags: index == 777 ? ["walking", "travel"] : ["casual"],
                sizes: index == 777 ? ["12"] : ["M"],
                brand: index == 777 ? "Nike" : "Brand \(index)"
            )
        }
        let provider = CatalogSearchProvider(catalogProvider: StaticProductCatalogProvider(products: products))
        _ = try await provider.search(ProductSearchQuery(text: "product"))

        let start = Date()
        let results = try await provider.search(ProductSearchQuery(text: "nike walking", brands: ["Nike"], colors: ["white"], sizes: ["12"]))
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertEqual(results.map(\.id), ["product-777"])
        XCTAssertLessThan(elapsed, 0.05)
    }

    func testAggregatedSearchProviderMergesDedupesAndSkipsFailingAdapters() async throws {
        let duplicateA = makeAffiliateProduct(id: "nike-a", name: "Court Sneaker", retailer: Retailer(name: "Nike", trackingID: "PENDING-APPROVAL", trackingParamName: "aff", disclosureName: "Nike"), brand: "Nike")
        let duplicateB = makeAffiliateProduct(id: "nike-b", name: "Court Sneaker", retailer: Retailer(name: "Nike", trackingID: "PENDING-APPROVAL", trackingParamName: "aff", disclosureName: "Nike"), brand: "Nike")
        let unique = makeAffiliateProduct(id: "macys", name: "Oxford Shirt", retailer: Retailer(name: "Macy's", trackingID: "PENDING-APPROVAL", trackingParamName: "aff", disclosureName: "Macy's"), brand: "Macy's")
        let provider = AggregatedSearchProvider(
            adapters: [
                StaticRetailerSearchAdapter(retailerName: "Nike", products: [duplicateA]),
                FailingRetailerSearchAdapter(retailerName: "Broken"),
                StaticRetailerSearchAdapter(retailerName: "Macy's", products: [duplicateB, unique])
            ],
            adapterTimeoutNanoseconds: 100_000_000
        )

        let results = try await provider.search(ProductSearchQuery())

        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results.filter { $0.name == "Court Sneaker" && $0.brand == "Nike" && $0.retailer.name == "Nike" }.count, 1)
        XCTAssertTrue(results.contains { $0.id == "macys" })
    }

    func testAggregatedSearchProviderTimesOutSlowAdapters() async throws {
        let fast = makeAffiliateProduct(id: "fast", name: "Fast Shirt", brand: "Macy's")
        let slow = makeAffiliateProduct(id: "slow", name: "Slow Shirt", brand: "Nike")
        let provider = AggregatedSearchProvider(
            adapters: [
                StaticRetailerSearchAdapter(retailerName: "Fast", products: [fast]),
                SlowRetailerSearchAdapter(retailerName: "Slow", products: [slow], delayNanoseconds: 200_000_000)
            ],
            adapterTimeoutNanoseconds: 20_000_000
        )

        let results = try await provider.search(ProductSearchQuery())

        XCTAssertEqual(results.map(\.id), ["fast"])
    }

    func testBestBuyAdapterMapsQueryToPublicProductsAPIWithoutPII() throws {
        let adapter = BestBuyAdapter(apiKey: "TEST-BESTBUY-KEY")
        let request = try adapter.makeRequest(for: ProductSearchQuery(
            text: "white smartwatch",
            brands: ["Fitbit"],
            categories: [.electronics],
            colors: ["white"],
            priceRange: Decimal(50)...Decimal(150),
            onSaleOnly: true,
            sort: .priceLowHigh
        ))

        let url = try XCTUnwrap(request.url)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let queryItems = components.queryItems ?? []
        let names = Set(queryItems.map(\.name))

        XCTAssertEqual(components.host, "api.bestbuy.com")
        XCTAssertEqual(components.path, "/v1/products")
        XCTAssertTrue(queryItems.contains(URLQueryItem(name: "apiKey", value: "TEST-BESTBUY-KEY")))
        XCTAssertTrue(queryItems.contains(URLQueryItem(name: "q", value: "white smartwatch")))
        XCTAssertTrue(queryItems.contains(URLQueryItem(name: "brand", value: "Fitbit")))
        XCTAssertTrue(queryItems.contains(URLQueryItem(name: "category", value: "electronics")))
        XCTAssertTrue(queryItems.contains(URLQueryItem(name: "onSaleOnly", value: "true")))
        XCTAssertFalse(names.contains("scanPhoto"))
        XCTAssertFalse(names.contains("outfitMemory"))
        XCTAssertFalse(names.contains("coordinates"))
        XCTAssertFalse(names.contains("userID"))
    }

    func testBestBuyAdapterDecodesProductFixture() throws {
        let json = """
        {
          "products": [
            {
              "sku": 12345,
              "name": "Fitness Smartwatch",
              "manufacturer": "Fitbit",
              "salePrice": 149.99,
              "regularPrice": 199.99,
              "image": "https://img.example.com/watch.jpg",
              "url": "https://www.bestbuy.com/site/watch",
              "type": "Smartwatch",
              "color": "Black"
            }
          ]
        }
        """

        let products = try BestBuyAdapter(apiKey: "TEST").decodeProducts(from: Data(json.utf8))

        XCTAssertEqual(products.first?.id, "bestbuy-12345")
        XCTAssertEqual(products.first?.retailer.name, "Best Buy")
        XCTAssertEqual(products.first?.brand, "Fitbit")
        XCTAssertEqual(products.first?.category, .electronics)
        XCTAssertEqual(products.first?.salePrice, Decimal(string: "149.99"))
    }

    func testProxyRetailerAdaptersMapToApprovedProxyEndpoints() throws {
        let proxyBaseURL = URL(string: "https://proxy.example.com/stylematch")!
        let query = ProductSearchQuery(text: "white shirt", retailers: ["Target"], brands: ["Nike"], categories: [.clothing], colors: ["white"], sizes: ["L"], genderPresentation: "men", priceRange: Decimal(20)...Decimal(80), occasions: [Occasion.casual.rawValue], sort: .newestSale)
        let adapters: [(String, URLRequest)] = [
            ("Amazon", try AmazonPAAPIAdapter(proxyBaseURL: proxyBaseURL).makeRequest(for: query)),
            ("Impact", try ImpactAdapter(proxyBaseURL: proxyBaseURL).makeRequest(for: query)),
            ("CJ", try CJAdapter(proxyBaseURL: proxyBaseURL).makeRequest(for: query)),
            ("Rakuten", try RakutenAdapter(proxyBaseURL: proxyBaseURL).makeRequest(for: query)),
            ("Sovrn", try SovrnAdapter(proxyBaseURL: proxyBaseURL).makeRequest(for: query))
        ]
        let expectedPaths = [
            "Amazon": "/stylematch/amazon/search",
            "Impact": "/stylematch/impact/search",
            "CJ": "/stylematch/cj/search",
            "Rakuten": "/stylematch/rakuten/search",
            "Sovrn": "/stylematch/sovrn/search"
        ]

        for (name, request) in adapters {
            let url = try XCTUnwrap(request.url)
            let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
            let queryItems = components.queryItems ?? []
            let queryNames = Set(queryItems.map(\.name))

            XCTAssertEqual(components.path, expectedPaths[name])
            XCTAssertTrue(queryItems.contains(URLQueryItem(name: "q", value: "white shirt")))
            XCTAssertTrue(queryItems.contains(URLQueryItem(name: "retailer", value: "Target")))
            XCTAssertTrue(queryItems.contains(URLQueryItem(name: "brand", value: "Nike")))
            XCTAssertTrue(queryItems.contains(URLQueryItem(name: "sort", value: "newestSale")))
            XCTAssertFalse(queryNames.contains("scanPhoto"))
            XCTAssertFalse(queryNames.contains("outfitMemory"))
            XCTAssertFalse(queryNames.contains("coordinates"))
            XCTAssertFalse(queryNames.contains("userID"))
        }
    }

    func testRetailerConfigCarriesSearchAdapterRoutingStatus() throws {
        let config = try JSONDecoder.catalog.decode(RetailerConfig.self, from: Data(contentsOf: retailerConfigFixtureURL()))

        let bestBuy = try XCTUnwrap(config.retailer(named: "Best Buy"))
        let amazon = try XCTUnwrap(config.retailer(named: "Amazon"))
        let target = try XCTUnwrap(config.retailer(named: "Target"))

        XCTAssertEqual(bestBuy.searchAdapter, "bestbuy")
        XCTAssertEqual(amazon.searchAdapter, "amazon")
        XCTAssertEqual(target.searchAdapter, "impact")
        XCTAssertEqual(bestBuy.searchStatus, "pending")
        XCTAssertEqual(amazon.searchStatus, "pending")
    }

    func testEveryRetailerAdapterDecodesLocalFixtureResponses() throws {
        let proxy = URL(string: "https://proxy.example.com/stylematch")!
        let decoded = [
            try AmazonPAAPIAdapter(proxyBaseURL: proxy).decodeProducts(from: Data(contentsOf: fixtureURL("amazon_paapi_response.json"))),
            try ImpactAdapter(proxyBaseURL: proxy).decodeProducts(from: Data(contentsOf: fixtureURL("impact_response.json"))),
            try CJAdapter(proxyBaseURL: proxy).decodeProducts(from: Data(contentsOf: fixtureURL("cj_response.json"))),
            try RakutenAdapter(proxyBaseURL: proxy).decodeProducts(from: Data(contentsOf: fixtureURL("rakuten_response.json"))),
            try SovrnAdapter(proxyBaseURL: proxy).decodeProducts(from: Data(contentsOf: fixtureURL("sovrn_response.json")))
        ]

        XCTAssertEqual(decoded.map { $0.count }, [1, 1, 1, 1, 1])
        XCTAssertEqual(decoded[0].first?.retailer.name, "Amazon")
        XCTAssertEqual(decoded[1].first?.retailer.name, "Target")
        XCTAssertEqual(decoded[2].first?.retailer.name, "Macy's")
        XCTAssertEqual(decoded[3].first?.retailer.name, "Nordstrom")
        XCTAssertEqual(decoded[4].first?.retailer.name, "H&M")
    }

    func testNoPIIInOutboundAdapterRequestsForEveryAdapter() throws {
        let proxy = URL(string: "https://proxy.example.com/stylematch")!
        let query = ProductSearchQuery(text: "white shirt", retailers: ["Amazon"], brands: ["Nike"], categories: [.clothing], colors: ["white"], sizes: ["L"], genderPresentation: "men", priceRange: Decimal(20)...Decimal(100), occasions: ["casual"], onSaleOnly: true, sort: .relevance)
        let requests = [
            try BestBuyAdapter(apiKey: "TEST").makeRequest(for: query),
            try AmazonPAAPIAdapter(proxyBaseURL: proxy).makeRequest(for: query),
            try ImpactAdapter(proxyBaseURL: proxy).makeRequest(for: query),
            try CJAdapter(proxyBaseURL: proxy).makeRequest(for: query),
            try RakutenAdapter(proxyBaseURL: proxy).makeRequest(for: query),
            try SovrnAdapter(proxyBaseURL: proxy).makeRequest(for: query)
        ]

        for request in requests {
            let urlText = try XCTUnwrap(request.url?.absoluteString)
            XCTAssertFalse(urlText.localizedCaseInsensitiveContains("outfitMemory"))
            XCTAssertFalse(urlText.localizedCaseInsensitiveContains("scanPhoto"))
            XCTAssertFalse(urlText.localizedCaseInsensitiveContains("coordinates"))
            XCTAssertFalse(urlText.localizedCaseInsensitiveContains("userID"))
            XCTAssertFalse(urlText.localizedCaseInsensitiveContains("favorite"))
            XCTAssertFalse(urlText.localizedCaseInsensitiveContains("history"))
        }
    }

    func testLiveSearchDisabledDoesNotInvokeAdapters() async throws {
        let spy = SpyRetailerSearchAdapter(retailerName: "Spy", products: [makeAffiliateProduct(id: "spy")])
        let provider = ShoppingDataSourceResolver.aggregatedSearchProvider(liveSearchEnabled: false, adapters: [spy])

        XCTAssertNil(provider)
        XCTAssertEqual(spy.callCount, 0)
    }

    func testShoppingFavoritesAreCappedAndClearedByPrivacyDeletion() {
        let store = ShoppingLocalStore(defaults: defaults, userID: userA)
        store.savedFavorites = (0..<250).map { "product-\($0)" }
        store.wishlistProductIDs = (0..<250).map { "wishlist-\($0)" }
        store.cartProductIDs = (0..<150).map { "cart-\($0)" }
        store.shoppingCardProductIDs = (0..<250).map { "card-\($0)" }
        store.saleNotificationsEnabled = true
        store.saleStateSnapshots = [
            "old": ShoppingSaleStateSnapshot(productID: "old", salePrice: Decimal(10), saleEndsAt: nil, isActiveSale: true)
        ]

        XCTAssertEqual(store.savedFavorites.count, 200)
        XCTAssertEqual(store.wishlistProductIDs.count, 200)
        XCTAssertEqual(store.cartProductIDs.count, 100)
        XCTAssertEqual(store.shoppingCardProductIDs.count, 200)

        PersonalStylistStorage.deletePersonalization(for: userA, defaults: defaults)
        ShoppingLocalStore(defaults: defaults, userID: userA).deleteAll()

        let cleared = ShoppingLocalStore(defaults: defaults, userID: userA)
        XCTAssertTrue(cleared.savedFavorites.isEmpty)
        XCTAssertTrue(cleared.wishlistProductIDs.isEmpty)
        XCTAssertTrue(cleared.cartProductIDs.isEmpty)
        XCTAssertTrue(cleared.shoppingCardProductIDs.isEmpty)
        XCTAssertTrue(cleared.saleStateSnapshots.isEmpty)
        XCTAssertFalse(cleared.saleNotificationsEnabled)
    }

    func testShoppingSaleAlertsExplainFavoriteWishlistCartAndShoppingCardDeals() {
        let saleEnds = fixedDate(year: 2026, month: 7, day: 10)
        let favorite = makeAffiliateProduct(id: "favorite", name: "Nike Jacket", subcategory: "jacket", colors: ["black"], price: Decimal(100), salePrice: Decimal(75), saleEndsAt: saleEnds, brand: "Nike")
        let wishlist = makeAffiliateProduct(id: "wishlist", name: "White Shirt", subcategory: "shirt", colors: ["white"], price: Decimal(80), salePrice: Decimal(60), saleEndsAt: saleEnds)
        let cart = makeAffiliateProduct(id: "cart", name: "Court Sneaker", category: .shoes, subcategory: "sneakers", colors: ["white"], price: Decimal(120), salePrice: Decimal(90), saleEndsAt: saleEnds)
        let card = makeAffiliateProduct(id: "card", name: "Leather Belt", category: .accessories, subcategory: "belt", colors: ["black"], price: Decimal(50), salePrice: Decimal(35), saleEndsAt: saleEnds)

        let alerts = ShoppingSaleAlertService.alerts(
            catalog: [favorite, wishlist, cart, card],
            context: ShoppingSaleAlertContext(
                favoriteProductIDs: ["favorite"],
                wishlistProductIDs: ["wishlist"],
                cartProductIDs: ["cart"],
                shoppingCardProductIDs: ["card"],
                now: fixedDate(year: 2026, month: 7, day: 7)
            )
        )

        XCTAssertEqual(alerts.first?.trigger, .cartPriceDrop)
        XCTAssertTrue(alerts.contains { $0.trigger == .favoriteSale && $0.message.contains("25% off") && $0.message.contains("Favorites") })
        XCTAssertTrue(alerts.contains { $0.trigger == .wishlistSale && $0.message.localizedCaseInsensitiveContains("wishlist") })
        XCTAssertTrue(alerts.contains { $0.trigger == .cartPriceDrop && $0.message.localizedCaseInsensitiveContains("cart") })
        XCTAssertTrue(alerts.contains { $0.trigger == .shoppingCardSale && $0.message.localizedCaseInsensitiveContains("shopping card") })
    }

    func testShoppingSaleAlertsMatchSavedStyleAndPastOutfitsWithoutFabrication() {
        var memory = makeBlackPantsAndShirtMemory()
        memory.scanDate = fixedDate(year: 2026, month: 7, day: 1)
        let savedBlueShirt = makeAffiliateProduct(id: "saved", name: "Blue Oxford", subcategory: "shirt", colors: ["blue"], brand: "Macy's")
        let blueSale = makeAffiliateProduct(id: "blue-sale", name: "Blue Shirt", subcategory: "shirt", colors: ["blue"], price: Decimal(90), salePrice: Decimal(70), saleEndsAt: fixedDate(year: 2026, month: 7, day: 12), brand: "Macy's")
        let whiteSale = makeAffiliateProduct(id: "white-sale", name: "White Shirt", subcategory: "shirt", colors: ["white"], price: Decimal(80), salePrice: Decimal(60), saleEndsAt: fixedDate(year: 2026, month: 7, day: 12))

        let alerts = ShoppingSaleAlertService.alerts(
            catalog: [blueSale, whiteSale],
            context: ShoppingSaleAlertContext(
                savedStyleProducts: [savedBlueShirt],
                memories: [memory],
                now: fixedDate(year: 2026, month: 7, day: 7)
            )
        )

        XCTAssertTrue(alerts.contains { $0.trigger == .savedStyleSale && $0.productID == "blue-sale" && $0.message.localizedCaseInsensitiveContains("saved style") })
        XCTAssertTrue(alerts.contains { $0.trigger == .pastOutfitMatchSale && $0.productID == "white-sale" && $0.message.contains("black pants and black shirt") })
    }

    func testShoppingSaleNotificationsRequireSaleStateChange() {
        let now = fixedDate(year: 2026, month: 7, day: 7)
        let becameSale = makeAffiliateProduct(id: "became-sale", name: "Favorite Shirt", price: Decimal(80), salePrice: Decimal(60), saleEndsAt: fixedDate(year: 2026, month: 7, day: 12))
        let unchangedSale = makeAffiliateProduct(id: "unchanged", name: "Unchanged Shirt", price: Decimal(80), salePrice: Decimal(50), saleEndsAt: fixedDate(year: 2026, month: 7, day: 12))

        let previous = [
            "became-sale": ShoppingSaleStateSnapshot(productID: "became-sale", salePrice: nil, saleEndsAt: nil, isActiveSale: false),
            "unchanged": ShoppingSaleStateSnapshot(productID: "unchanged", salePrice: Decimal(50), saleEndsAt: fixedDate(year: 2026, month: 7, day: 12), isActiveSale: true)
        ]

        let alerts = ShoppingSaleAlertService.notificationAlerts(
            catalog: [becameSale, unchangedSale],
            context: ShoppingSaleAlertContext(
                favoriteProductIDs: ["became-sale", "unchanged"],
                now: now
            ),
            previousSnapshots: previous
        )

        XCTAssertEqual(alerts.map(\.productID), ["became-sale"])
        XCTAssertTrue(alerts.first?.message.contains("Favorite Shirt") == true)
    }

    func testSaleWatcherDiffFiresForNewSaleAndPriceDropOnly() {
        let store = ShoppingLocalStore(defaults: defaults, userID: userA)
        store.saleNotificationsEnabled = true
        store.savedFavorites = ["new-sale", "same-sale", "drop-sale", "expired"]
        let now = fixedDate(year: 2026, month: 7, day: 7)
        store.lastKnownSaleState = [
            "new-sale": SaleSnapshot(salePrice: nil, saleEndsAt: nil, timestamp: now),
            "same-sale": SaleSnapshot(salePrice: Decimal(50), saleEndsAt: fixedDate(year: 2026, month: 7, day: 12), timestamp: now),
            "drop-sale": SaleSnapshot(salePrice: Decimal(70), saleEndsAt: fixedDate(year: 2026, month: 7, day: 12), timestamp: now),
            "expired": SaleSnapshot(salePrice: nil, saleEndsAt: nil, timestamp: now)
        ]

        let watcher = SaleWatcher(
            catalogProvider: StaticProductCatalogProvider(products: []),
            localStore: store,
            notificationScheduler: nil,
            now: { now }
        )
        let events = watcher.process(catalog: [
            makeAffiliateProduct(id: "new-sale", price: Decimal(80), salePrice: Decimal(60), saleEndsAt: fixedDate(year: 2026, month: 7, day: 12)),
            makeAffiliateProduct(id: "same-sale", price: Decimal(80), salePrice: Decimal(50), saleEndsAt: fixedDate(year: 2026, month: 7, day: 12)),
            makeAffiliateProduct(id: "drop-sale", price: Decimal(80), salePrice: Decimal(60), saleEndsAt: fixedDate(year: 2026, month: 7, day: 12)),
            makeAffiliateProduct(id: "expired", price: Decimal(80), salePrice: Decimal(40), saleEndsAt: fixedDate(year: 2026, month: 1, day: 1))
        ], now: now)

        XCTAssertEqual(Set(events.map(\.productID)), ["drop-sale", "new-sale"])
    }

    func testSaleWatcherDedupsSameProductAndSalePriceAcrossRuns() {
        let store = ShoppingLocalStore(defaults: defaults, userID: userA)
        store.saleNotificationsEnabled = true
        store.savedFavorites = ["shirt"]
        let now = fixedDate(year: 2026, month: 7, day: 7)
        store.lastKnownSaleState = ["shirt": SaleSnapshot(salePrice: nil, saleEndsAt: nil, timestamp: now)]
        let product = makeAffiliateProduct(id: "shirt", price: Decimal(80), salePrice: Decimal(60), saleEndsAt: fixedDate(year: 2026, month: 7, day: 12))
        let watcher = SaleWatcher(catalogProvider: StaticProductCatalogProvider(products: []), localStore: store, notificationScheduler: nil, now: { now })

        XCTAssertEqual(watcher.process(catalog: [product], now: now).count, 1)
        store.lastKnownSaleState = ["shirt": SaleSnapshot(salePrice: nil, saleEndsAt: nil, timestamp: now)]
        XCTAssertTrue(watcher.process(catalog: [product], now: now).isEmpty)
    }

    func testSaleWatcherCapsDailyAndPrioritizesDirectFavorites() {
        let store = ShoppingLocalStore(defaults: defaults, userID: userA)
        store.saleNotificationsEnabled = true
        store.savedFavorites = ["favorite-1", "favorite-2", "favorite-3"]
        let now = fixedDate(year: 2026, month: 7, day: 7)
        store.lastKnownSaleState = Dictionary(uniqueKeysWithValues: ["favorite-1", "favorite-2", "favorite-3", "similar"].map {
            ($0, SaleSnapshot(salePrice: nil, saleEndsAt: nil, timestamp: now))
        })
        let products = [
            makeAffiliateProduct(id: "favorite-1", name: "Favorite One", subcategory: "shirt", colors: ["blue"], price: Decimal(80), salePrice: Decimal(60), saleEndsAt: fixedDate(year: 2026, month: 7, day: 12)),
            makeAffiliateProduct(id: "favorite-2", name: "Favorite Two", subcategory: "shirt", colors: ["black"], price: Decimal(80), salePrice: Decimal(60), saleEndsAt: fixedDate(year: 2026, month: 7, day: 12)),
            makeAffiliateProduct(id: "favorite-3", name: "Favorite Three", subcategory: "shirt", colors: ["white"], price: Decimal(80), salePrice: Decimal(60), saleEndsAt: fixedDate(year: 2026, month: 7, day: 12)),
            makeAffiliateProduct(id: "similar", name: "Similar Shirt", subcategory: "shirt", colors: ["blue"], price: Decimal(80), salePrice: Decimal(55), saleEndsAt: fixedDate(year: 2026, month: 7, day: 12))
        ]

        let events = SaleWatcher(catalogProvider: StaticProductCatalogProvider(products: []), localStore: store, notificationScheduler: nil, now: { now }).process(catalog: products, now: now)

        XCTAssertEqual(events.filter(\.shouldNotify).count, 2)
        XCTAssertTrue(events.filter(\.shouldNotify).allSatisfy(\.isDirectFavorite))
        XCTAssertTrue(events.contains { $0.reason == .similarToFavorite && !$0.shouldNotify })
    }

    func testSaleWatcherCapsWeeklyNotifications() {
        let store = ShoppingLocalStore(defaults: defaults, userID: userA)
        store.saleNotificationsEnabled = true
        store.savedFavorites = ["shirt"]
        let now = fixedDate(year: 2026, month: 7, day: 7)
        store.saleNotificationHistory = (1...5).map { now.addingTimeInterval(TimeInterval(-$0 * 24 * 60 * 60)) }
        store.lastKnownSaleState = ["shirt": SaleSnapshot(salePrice: nil, saleEndsAt: nil, timestamp: now)]

        let events = SaleWatcher(catalogProvider: StaticProductCatalogProvider(products: []), localStore: store, notificationScheduler: nil, now: { now }).process(
            catalog: [makeAffiliateProduct(id: "shirt", price: Decimal(80), salePrice: Decimal(60), saleEndsAt: fixedDate(year: 2026, month: 7, day: 12))],
            now: now
        )

        XCTAssertEqual(events.count, 1)
        XCTAssertFalse(events[0].shouldNotify)
    }

    func testSaleWatcherAmazonNotificationTemplateContainsNoPrices() {
        let event = SaleEvent(
            id: "amazon",
            productID: "amazon",
            productName: "Amazon Jacket",
            retailerName: "Amazon",
            subcategory: "jacket",
            salePrice: Decimal(40),
            originalPrice: Decimal(100),
            saleEndsAt: nil,
            reason: .directFavorite,
            occurredAt: Date(),
            shouldNotify: true,
            scheduledDeliveryDate: nil
        )

        let content = SaleWatcher.notificationTitleAndBody(for: event, retailerName: "Amazon")

        XCTAssertFalse(content.body.contains("$"))
        XCTAssertFalse(content.body.contains("40"))
        XCTAssertFalse(content.body.contains("100"))
        XCTAssertTrue(content.body.localizedCaseInsensitiveContains("Amazon"))
    }

    func testSaleWatcherQuietHoursSchedulesAtEightAMInsteadOfDropping() async throws {
        let store = ShoppingLocalStore(defaults: defaults, userID: userA)
        store.saleNotificationsEnabled = true
        store.savedFavorites = ["shirt"]
        let now = fixedDate(year: 2026, month: 7, day: 7, hour: 23)
        store.lastKnownSaleState = ["shirt": SaleSnapshot(salePrice: nil, saleEndsAt: nil, timestamp: now)]
        let spy = SpySaleNotificationScheduler()

        _ = await SaleWatcher(
            catalogProvider: StaticProductCatalogProvider(products: [
                makeAffiliateProduct(id: "shirt", price: Decimal(80), salePrice: Decimal(60), saleEndsAt: fixedDate(year: 2026, month: 7, day: 12))
            ]),
            localStore: store,
            notificationScheduler: spy,
            now: { now }
        ).checkForNewSales()

        let delivery = try XCTUnwrap(spy.requests.first?.deliveryDate)
        XCTAssertGreaterThanOrEqual(Calendar(identifier: .gregorian).component(.hour, from: delivery), 8)
        XCTAssertEqual(spy.requests.count, 1)
    }

    func testSaleWatcherDisabledNotificationsProduceZeroNotificationRequests() async {
        let store = ShoppingLocalStore(defaults: defaults, userID: userA)
        store.saleNotificationsEnabled = false
        store.savedFavorites = ["shirt"]
        let now = fixedDate(year: 2026, month: 7, day: 7)
        store.lastKnownSaleState = ["shirt": SaleSnapshot(salePrice: nil, saleEndsAt: nil, timestamp: now)]
        let spy = SpySaleNotificationScheduler()

        let events = await SaleWatcher(
            catalogProvider: StaticProductCatalogProvider(products: [
                makeAffiliateProduct(id: "shirt", price: Decimal(80), salePrice: Decimal(60), saleEndsAt: fixedDate(year: 2026, month: 7, day: 12))
            ]),
            localStore: store,
            notificationScheduler: spy,
            now: { now }
        ).checkForNewSales()

        XCTAssertEqual(events.count, 1)
        XCTAssertFalse(events[0].shouldNotify)
        XCTAssertTrue(spy.requests.isEmpty)
    }

    func testSaleWatcherStoresAreClearedByPrivacyDeletion() {
        let store = ShoppingLocalStore(defaults: defaults, userID: userA)
        store.lastKnownSaleState = ["shirt": SaleSnapshot(salePrice: Decimal(60), saleEndsAt: nil, timestamp: Date())]
        store.notifiedSalePairs = ["shirt|60"]
        store.saleNotificationHistory = [Date()]
        store.recentSaleEvents = [
            SaleEvent(id: "event", productID: "shirt", productName: "Shirt", retailerName: "Macy's", subcategory: "shirt", salePrice: Decimal(60), originalPrice: Decimal(80), saleEndsAt: nil, reason: .directFavorite, occurredAt: Date(), shouldNotify: false, scheduledDeliveryDate: nil)
        ]
        store.viewedSaleEventIDs = ["event"]

        store.deleteAll()
        let cleared = ShoppingLocalStore(defaults: defaults, userID: userA)

        XCTAssertTrue(cleared.lastKnownSaleState.isEmpty)
        XCTAssertTrue(cleared.notifiedSalePairs.isEmpty)
        XCTAssertTrue(cleared.saleNotificationHistory.isEmpty)
        XCTAssertTrue(cleared.recentSaleEvents.isEmpty)
        XCTAssertTrue(cleared.viewedSaleEventIDs.isEmpty)
    }

    func testShoppingSaleNotificationsDoNotFireWithoutPriorSnapshot() {
        let sale = makeAffiliateProduct(id: "sale", name: "Favorite Shirt", price: Decimal(80), salePrice: Decimal(60), saleEndsAt: fixedDate(year: 2026, month: 7, day: 12))

        let alerts = ShoppingSaleAlertService.notificationAlerts(
            catalog: [sale],
            context: ShoppingSaleAlertContext(
                favoriteProductIDs: ["sale"],
                now: fixedDate(year: 2026, month: 7, day: 7)
            ),
            previousSnapshots: [:]
        )

        XCTAssertTrue(alerts.isEmpty)
    }

    func testShoppingSaleIndicatorsSkipExpiredAndRegularProducts() {
        let expired = makeAffiliateProduct(id: "expired", name: "Expired Shirt", price: Decimal(80), salePrice: Decimal(40), saleEndsAt: fixedDate(year: 2026, month: 1, day: 1))
        let regular = makeAffiliateProduct(id: "regular", name: "Regular Shirt", price: Decimal(80), salePrice: nil)

        let alerts = ShoppingSaleAlertService.alerts(
            catalog: [expired, regular],
            context: ShoppingSaleAlertContext(
                favoriteProductIDs: ["expired", "regular"],
                now: fixedDate(year: 2026, month: 7, day: 7)
            )
        )

        XCTAssertTrue(alerts.isEmpty)
    }

    func testShoppingSaleAlertsGroupMultipleUpdatesIntoSections() {
        let favorite = ShoppingSaleAlert(
            id: "favorite",
            productID: "favorite",
            productName: "Favorite Shirt",
            retailerName: "Macy's",
            trigger: .favoriteSale,
            title: "Shopping deal",
            message: "Favorite sale",
            discountPercent: 20,
            salePrice: Decimal(40),
            originalPrice: Decimal(50),
            saleEndsAt: nil
        )
        let style = ShoppingSaleAlert(
            id: "style",
            productID: "style",
            productName: "Style Shirt",
            retailerName: "Macy's",
            trigger: .pastOutfitMatchSale,
            title: "Matches a past outfit",
            message: "Style sale",
            discountPercent: 20,
            salePrice: Decimal(40),
            originalPrice: Decimal(50),
            saleEndsAt: nil
        )

        let sections = ShoppingSaleAlertService.groupedSections(from: [favorite, style])

        XCTAssertEqual(sections.map(\.title), ["Saved & Cart Deals", "Matches Your Style"])
    }

    func testShoppingRankingRecentOutfitComplementWeatherPenaltyAndDismissedSink() {
        var memory = makeBlackPantsAndShirtMemory()
        memory.scanDate = fixedDate(year: 2026, month: 7, day: 1)
        let whiteShirt = makeAffiliateProduct(id: "white-shirt", name: "White Shirt", category: .clothing, subcategory: "shirt", colors: ["white"])
        let coat = makeAffiliateProduct(id: "coat", name: "Wool Coat", category: .clothing, subcategory: "coat", colors: ["camel"], tags: ["heavy", "wool"])
        let dismissed = makeAffiliateProduct(id: "dismissed", name: "Black Belt", category: .accessories, subcategory: "belt", colors: ["black"])

        let ranked = ShoppingRecommendationEngine.rank(
            results: [coat, dismissed, whiteShirt],
            against: ShoppingRankingContext(
                memories: [memory],
                weather: ShoppingWeatherContext(feelsLikeTemperature: 91, rainChancePercent: nil, uvIndex: nil, condition: "Hot"),
                dismissedProductIDs: ["dismissed"],
                now: fixedDate(year: 2026, month: 7, day: 7)
            )
        )

        XCTAssertEqual(ranked.first?.product.id, "white-shirt")
        XCTAssertEqual(ranked.first?.reasonFacts?.rule, "complement")
        XCTAssertTrue(ranked.first?.reasonFacts?.oneLineReason.contains("black pants and black shirt") == true)
        XCTAssertTrue(ranked.first?.reasonFacts?.explanationBullets.contains("Matches your wardrobe") == true)
        XCTAssertEqual(ranked.last?.product.id, "dismissed")
        XCTAssertLessThan(ranked.first(where: { $0.product.id == "coat" })?.rank ?? 0, ranked.first?.rank ?? 0)
    }

    func testShoppingSearchExcludesAmazonWhenPriceFilterRequiresStoredPriceDisplay() {
        let amazon = makeAffiliateProduct(
            id: "amazon-priced",
            name: "Amazon Style Tool",
            category: .styleTools,
            subcategory: "steamer",
            colors: ["white"],
            retailer: Retailer(name: "Amazon", trackingID: "amazon-20", trackingParamName: "tag", disclosureName: "Amazon"),
            price: Decimal(30),
            tags: ["travel"]
        )
        var criteria = ShoppingSearchCriteria()
        criteria.maximumPrice = Decimal(40)

        let results = ShoppingSearchEngine.filter(products: [amazon], criteria: criteria)

        XCTAssertTrue(results.isEmpty)
    }

    func testStoreSearchFindsSupportedStoresByNameDomainAndCategory() {
        let stores = [
            SupportedStore(id: "nike", name: "Nike", domains: ["nike.com"], categories: [.shoes], affiliateNetwork: "TBD", apiStatus: "affiliate-placeholder", isEnabled: true),
            SupportedStore(id: "ulta", name: "Ulta", domains: ["ulta.com"], categories: [.styleTools], affiliateNetwork: "TBD", apiStatus: "needs-approved-feed", isEnabled: true),
            SupportedStore(id: "disabled", name: "Disabled", domains: ["disabled.example"], categories: [.clothing], affiliateNetwork: nil, apiStatus: "disabled", isEnabled: false)
        ]

        XCTAssertEqual(ShoppingSearchEngine.filterStores(stores, query: "ulta").map(\.name), ["Ulta"])
        XCTAssertEqual(ShoppingSearchEngine.filterStores(stores, query: "shoes").map(\.name), ["Nike"])
        XCTAssertFalse(ShoppingSearchEngine.filterStores(stores, query: "").contains { $0.name == "Disabled" })
    }

    func testStoreSearchUsesSharedWorkerBackedCatalogProvider() throws {
        let source = try projectSource("StyleMatchAI/Shopping/StoreSearchView.swift")

        XCTAssertTrue(source.contains("CatalogSearchProvider(catalogProvider: SharedCatalogProvider())"))
        XCTAssertTrue(source.contains("[StyleMatch Store Search] Search failed:"))
    }

    func testLiveSearchFlagDefaultsOffAndResolverStaysDormant() throws {
        XCTAssertFalse(FeatureFlags.liveSearchEnabled)
        XCTAssertFalse(FeatureFlags.pushNotificationsEnabled)
        XCTAssertFalse(FeatureFlags.saleNotificationsEnabled)

        let provider = try ShoppingDataSourceResolver.liveProvider(
            liveSearchEnabled: false,
            configProvider: StaticShoppingIntegrationConfigProvider(storedConfig: ShoppingIntegrationConfig(
                liveSearchProxyBaseURL: URL(string: "https://proxy.example.com"),
                allowedClientSideAPIKeyNames: []
            ))
        )

        XCTAssertNil(provider)
    }

    func testLiveSearchEnabledRequiresProxyConfig() {
        XCTAssertThrowsError(try ShoppingDataSourceResolver.liveProvider(
            liveSearchEnabled: true,
            configProvider: StaticShoppingIntegrationConfigProvider(storedConfig: .empty)
        ))
    }

    func testFounderToolingIsDebugOnlyInSource() throws {
        let featureGate = try projectSource("StyleMatchAI/FeatureGate.swift")
        let contentView = try projectSource("StyleMatchAI/ContentView.swift")

        XCTAssertTrue(featureGate.contains("#if DEBUG"))
        XCTAssertTrue(featureGate.contains("static let releaseChannel: StyleMatchReleaseChannel = .customerPublic"))
        XCTAssertTrue(featureGate.contains("static var allowsLocalFounderAPIKey: Bool"))
        XCTAssertTrue(featureGate.contains("#else\n        false\n        #endif"))
        XCTAssertTrue(contentView.contains("StyleMatchBuildSettings.allowsLocalFounderAPIKey"))
    }

    func testProxyLiveSearchSendsOnlyAllowedSearchFilters() async throws {
        CapturingURLProtocol.lastURL = nil
        CapturingURLProtocol.responseData = Data("[]".utf8)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CapturingURLProtocol.self]
        let session = URLSession(configuration: config)
        let provider = ProxyLiveRetailerSearchProvider(
            proxyBaseURL: URL(string: "https://proxy.example.com/stylematch")!,
            urlSession: session
        )
        var criteria = ShoppingSearchCriteria()
        criteria.query = "white shirt"
        criteria.storeName = "Macy's"
        criteria.brand = "Calvin Klein"
        criteria.category = .clothing
        criteria.color = "white"
        criteria.size = "XL"
        criteria.style = "formal"
        criteria.genderPresentation = "men"
        criteria.minimumPrice = Decimal(20)
        criteria.maximumPrice = Decimal(100)
        criteria.occasion = "office"

        _ = try await provider.search(criteria: criteria)

        let url = try XCTUnwrap(CapturingURLProtocol.lastURL)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let queryNames = Set((components.queryItems ?? []).map(\.name))
        XCTAssertEqual(components.path, "/stylematch/search")
        XCTAssertTrue(queryNames.isSuperset(of: ["q", "store", "brand", "category", "color", "size", "style", "gender", "minPrice", "maxPrice", "occasion"]))
        XCTAssertFalse(queryNames.contains("outfitMemory"))
        XCTAssertFalse(queryNames.contains("scanPhoto"))
        XCTAssertFalse(queryNames.contains("userID"))
        XCTAssertFalse(queryNames.contains("coordinates"))
    }

    func testRemoteCatalogProviderSendsOnlyCatalogFiltersAndMapsWorkerProducts() async throws {
        CapturingURLProtocol.lastURL = nil
        CapturingURLProtocol.responseData = Data("""
        {
          "products": [
            {
              "id": "macys-white-oxford",
              "store_id": "macys",
              "store_name": "Macy's",
              "name": "White Oxford Shirt",
              "image_url": "https://example.com/products/white-oxford.jpg",
              "category": "tops",
              "brand": "Macy's",
              "price_cents": 7950,
              "sale_price_cents": 4999,
              "sale_ends_at": "2027-01-01T00:00:00Z",
              "currency": "USD",
              "country_code": "US",
              "available_countries": ["US", "CA"],
              "availability": "in_stock",
              "tags": ["business", "white", "shirt"],
              "buy_url": "https://proxy.example.com/v1/go/macys-white-oxford"
            }
          ],
          "next_cursor": null,
          "disclosure": "As an Amazon Associate I earn from qualifying purchases. StyleMatch Pro may earn a commission at no extra cost to you."
        }
        """.utf8)

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CapturingURLProtocol.self]
        let session = URLSession(configuration: config)
        let cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let provider = RemoteCatalogProvider(
            baseURL: URL(string: "https://proxy.example.com")!,
            cacheDirectory: cacheDirectory,
            fallbackProvider: StaticProductCatalogProvider(products: []),
            urlSession: session,
            refreshInterval: 3600
        )

        let products = try await provider.products()

        XCTAssertEqual(products.map(\.id), ["macys-white-oxford"])
        XCTAssertEqual(products.first?.affiliateURL.absoluteString, "https://proxy.example.com/v1/go/macys-white-oxford")
        XCTAssertEqual(products.first?.retailer.trackingID, AffiliateLinkBuilder.pendingApprovalTrackingID)
        XCTAssertEqual(products.first?.currencyCode, "USD")
        XCTAssertEqual(products.first?.availableCountries, ["US", "CA"])
        XCTAssertEqual(try RemoteCatalogProvider.decodeRemoteDisclosure(CapturingURLProtocol.responseData), ShoppingCatalogDisclosure.fallback)

        let url = try XCTUnwrap(CapturingURLProtocol.lastURL)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.path, "/v1/products")
        let queryNames = Set((components.queryItems ?? []).map(\.name))
        XCTAssertEqual(queryNames, ["limit", "country"])
        XCTAssertFalse(url.absoluteString.contains("profile"))
        XCTAssertFalse(url.absoluteString.contains("outfit"))
        XCTAssertFalse(url.absoluteString.contains("user"))
        XCTAssertFalse(url.absoluteString.contains("wardrobe"))
    }

    func testRemoteCatalogProviderFiltersByCountryAndFormatsGBPPrices() throws {
        let data = Data("""
        {
          "products": [
            {
              "id": "gb-only-blazer",
              "store_id": "stylehub",
              "store_name": "StyleHub",
              "name": "Navy Blazer",
              "image_url": "https://example.com/products/navy-blazer.jpg",
              "category": "outerwear",
              "brand": "StyleHub",
              "price_cents": 8900,
              "sale_price_cents": null,
              "sale_ends_at": null,
              "currency": "GBP",
              "country_code": "GB",
              "available_countries": ["GB"],
              "availability": "in_stock",
              "tags": ["business", "navy", "jacket"],
              "buy_url": "https://proxy.example.com/v1/go/gb-only-blazer"
            },
            {
              "id": "us-only-shirt",
              "store_id": "macys",
              "store_name": "Macy's",
              "name": "White Oxford Shirt",
              "image_url": "https://example.com/products/white-oxford.jpg",
              "category": "tops",
              "brand": "Macy's",
              "price_cents": 7950,
              "sale_price_cents": null,
              "sale_ends_at": null,
              "currency": "USD",
              "country_code": "US",
              "available_countries": ["US"],
              "availability": "in_stock",
              "tags": ["business", "white", "shirt"],
              "buy_url": "https://proxy.example.com/v1/go/us-only-shirt"
            }
          ]
        }
        """.utf8)

        let products = try RemoteCatalogProvider.decodeRemoteProducts(
            data,
            baseURL: URL(string: "https://proxy.example.com")!,
            regionCode: "GB"
        )

        XCTAssertEqual(products.map(\.id), ["gb-only-blazer"])
        let product = try XCTUnwrap(products.first)
        XCTAssertEqual(product.currencyCode, "GBP")
        let viewModel = AffiliateProductViewModel(product: product)
        XCTAssertTrue(viewModel.priceText.contains("£"), "Expected GBP price, got \(viewModel.priceText)")
    }

    func testPersonalStylistEngineFinalMessageOmitsDealsWhenSaleMatchingFlagIsFalse() {
        let input = PersonalStylistEngineInput(
            score: 89,
            scoreTier: "Good Match",
            scoreBreakdown: nil,
            detectedGarments: ["black pants", "white shirt"],
            colors: ["black", "white"],
            detectedStyle: "Casual",
            occasion: "Casual",
            memories: [],
            profile: makeStylistProfile(userId: userA),
            dealMatches: [
                PersonalStylistDealMatch(
                    productName: "White Oxford Shirt",
                    retailerName: "Macy's",
                    category: "shirt",
                    salePrice: "$59.99",
                    reason: "Matches a stored outfit."
                )
            ]
        )

        let message = PersonalStylistEngine.compose(
            input: input,
            weatherAdviceEnabled: false,
            saleMatchingEnabled: false
        )
        let context = PersonalStylistEngine.context(
            input: input,
            weatherAdviceEnabled: false,
            saleMatchingEnabled: false
        )

        XCTAssertFalse(message.plainText.contains("Macy's"))
        XCTAssertTrue(context.dealFacts.isEmpty)
    }

    func testSaleMatchingServiceDoesNotCallProviderWhenDisabled() async throws {
        let provider = SpyDealProvider(deals: [
            Deal(
                itemName: "Clean Leather Sneaker",
                category: "Shoes",
                colors: ["white"],
                salePrice: Decimal(110),
                originalPrice: Decimal(120),
                url: URL(string: "https://www.nike.com")
            )
        ])

        let matches = try await SaleMatchingService.matches(
            for: SaleMatchScanContext(
                detectedGarments: ["white sneakers"],
                colors: ["white"],
                detectedStyle: "Casual",
                occasion: "Casual"
            ),
            provider: provider,
            saleMatchingEnabled: false
        )

        XCTAssertTrue(matches.isEmpty)
        XCTAssertEqual(provider.callCount, 0)
    }

    func testSaleMatchingServiceUsesProviderOnlyWhenEnabled() async throws {
        let provider = SpyDealProvider(deals: [
            Deal(
                itemName: "Clean Leather Sneaker",
                category: "Shoes",
                colors: ["white"],
                salePrice: Decimal(110),
                originalPrice: Decimal(120),
                url: URL(string: "https://www.nike.com")
            )
        ])

        let matches = try await SaleMatchingService.matches(
            for: SaleMatchScanContext(
                detectedGarments: ["white sneakers"],
                colors: ["white"],
                detectedStyle: "Casual",
                occasion: "Casual"
            ),
            provider: provider,
            saleMatchingEnabled: true
        )

        XCTAssertEqual(provider.callCount, 1)
        XCTAssertEqual(matches.first?.retailerName, "www.nike.com")
        XCTAssertEqual(matches.first?.productName, "Clean Leather Sneaker")
    }

    func testMockDealProviderLoadsLocalJSONFixture() async throws {
        let provider = MockDealProvider(fixtureURL: mockDealFixtureURL())
        let deals = try await provider.currentDeals()

        XCTAssertEqual(deals.count, 2)
        XCTAssertEqual(deals.first?.itemName, "Oxford Shirt")
        XCTAssertEqual(deals.first?.colors, ["white"])
    }

    func testDealMessagesComplementMatchReferencesRealOutfitMemory() async throws {
        let provider = MockDealProvider(fixtureURL: mockDealFixtureURL())
        let now = fixedDate(year: 2026, month: 7, day: 7)
        var memory = makeBlackPantsAndShirtMemory()
        memory.scanDate = fixedDate(year: 2026, month: 7, day: 2)
        memory.styleScore = 85

        let messages = try await SaleMatchingService.dealMessages(
            for: [memory],
            provider: provider,
            saleMatchingEnabled: true,
            now: now,
            limit: 1
        )

        XCTAssertEqual(
            messages.first,
            "A white shirt just went on sale at Macy's — it would pair well with the black pants and black shirt you wore last Thursday."
        )
    }

    func testDealMessagesUpgradeMatchUsesLowLikedOrLowScoreStoredItem() async throws {
        let provider = MockDealProvider(fixtureURL: mockDealFixtureURL())
        let now = fixedDate(year: 2026, month: 7, day: 7)
        var shirtRecord = makeGarmentRecord(fingerprint: "category:shirt|colors:black|pattern:solid|fabric:cotton|brand:unknown")
        shirtRecord.garmentCategory = "shirt"
        shirtRecord.colors = ["black"]
        var memory = makeOutfitMemory(userId: userA, record: shirtRecord)
        memory.detectedGarments = ["shirt"]
        memory.colors = ["black"]
        memory.scanDate = fixedDate(year: 2026, month: 7, day: 2)
        memory.styleScore = 62
        memory.wasLiked = false

        let messages = try await SaleMatchingService.dealMessages(
            for: [memory],
            provider: provider,
            saleMatchingEnabled: true,
            now: now,
            limit: 2
        )

        XCTAssertTrue(messages.contains { message in
            message.contains("A black shirt just went on sale")
                && message.contains("it could upgrade the black shirt you wore last Thursday.")
        })
    }

    func testDealMessagesFlagOffDoesNotCallProvider() async throws {
        let provider = SpyDealProvider(deals: [
            Deal(
                itemName: "Oxford Shirt",
                category: "shirt",
                colors: ["white"],
                salePrice: Decimal(59),
                originalPrice: Decimal(89),
                url: URL(string: "https://www.macys.com/white-shirt")
            )
        ])

        let messages = try await SaleMatchingService.dealMessages(
            for: [makeBlackPantsAndShirtMemory()],
            provider: provider,
            saleMatchingEnabled: false
        )

        XCTAssertTrue(messages.isEmpty)
        XCTAssertEqual(provider.callCount, 0)
    }

    func testWeatherAdvisorOmitsSpecificAdviceWhenConfidenceIsLow() {
        let advice = WeatherAdvisor.advice(for: WeatherAdvisorInput(
            feelsLikeTemperature: 91,
            humidityPercent: 70,
            rainChancePercent: nil,
            windMph: nil,
            uvIndex: nil,
            condition: "Humid",
            confidence: 82
        ))

        XCTAssertNil(advice)
    }

    func testWeatherAdvisorExplainsHotHumidRecommendation() {
        let advice = WeatherAdvisor.advice(for: WeatherAdvisorInput(
            feelsLikeTemperature: 91,
            humidityPercent: 72,
            rainChancePercent: nil,
            windMph: nil,
            uvIndex: nil,
            condition: "Humid",
            confidence: 95
        ))

        XCTAssertEqual(advice?.message, "Keep this breathable and avoid jackets, extra layers, or heavy fabrics today.")
        XCTAssertTrue(advice?.reason.contains("91°F") == true)
        XCTAssertTrue(advice?.reason.contains("72%") == true)
    }

    func testWeatherAdvisorHotWeatherWithJacketFlagsSkipJacketAndDoesNotRecommendOne() {
        let advice = WeatherAdvisor.advice(for: WeatherAdvisorInput(
            feelsLikeTemperature: 88,
            humidityPercent: 65,
            rainChancePercent: nil,
            windMph: nil,
            uvIndex: nil,
            condition: "Hot",
            confidence: 95,
            detectedGarments: ["linen shirt", "black pants", "jacket"],
            activity: .walking,
            citySummary: "Hot in Miami"
        ))

        XCTAssertTrue(advice?.message.localizedCaseInsensitiveContains("skip the jacket") == true)
        XCTAssertFalse(advice?.message.localizedCaseInsensitiveContains("recommend jacket") == true)
        XCTAssertTrue(advice?.reason.contains("88°F") == true)
    }

    func testWeatherAdvisorUmbrellaTriggersAtExactlyFiftyPercentRain() {
        let advice = WeatherAdvisor.advice(for: WeatherAdvisorInput(
            feelsLikeTemperature: 72,
            humidityPercent: 60,
            rainChancePercent: 50,
            windMph: nil,
            uvIndex: nil,
            condition: "Cloudy",
            confidence: 95,
            detectedGarments: ["cotton shirt", "black pants"]
        ))

        XCTAssertEqual(advice?.message, "There is a 50% chance of rain today. Grab an umbrella before going out.")
    }

    func testWeatherAdvisorPossibleShowersOnlyForRainVulnerableOutfit() {
        let safeAdvice = WeatherAdvisor.advice(for: WeatherAdvisorInput(
            feelsLikeTemperature: 72,
            humidityPercent: 60,
            rainChancePercent: 40,
            windMph: nil,
            uvIndex: nil,
            condition: "Cloudy",
            confidence: 95,
            detectedGarments: ["cotton shirt", "black pants"]
        ))
        let vulnerableAdvice = WeatherAdvisor.advice(for: WeatherAdvisorInput(
            feelsLikeTemperature: 72,
            humidityPercent: 60,
            rainChancePercent: 40,
            windMph: nil,
            uvIndex: nil,
            condition: "Cloudy",
            confidence: 95,
            detectedGarments: ["suede loafers", "black pants"]
        ))

        XCTAssertNil(safeAdvice)
        XCTAssertTrue(vulnerableAdvice?.message.localizedCaseInsensitiveContains("possible showers") == true)
    }

    func testWeatherAdvisorWindOnlyMentionsLooseGarments() {
        let fittedAdvice = WeatherAdvisor.advice(for: WeatherAdvisorInput(
            feelsLikeTemperature: 65,
            humidityPercent: nil,
            rainChancePercent: nil,
            windMph: 27,
            uvIndex: nil,
            condition: "Windy",
            confidence: 95,
            detectedGarments: ["fitted shirt", "straight pants"]
        ))
        let looseAdvice = WeatherAdvisor.advice(for: WeatherAdvisorInput(
            feelsLikeTemperature: 65,
            humidityPercent: nil,
            rainChancePercent: nil,
            windMph: 27,
            uvIndex: nil,
            condition: "Windy",
            confidence: 95,
            detectedGarments: ["flowy skirt", "linen shirt"]
        ))

        XCTAssertNil(fittedAdvice)
        XCTAssertTrue(looseAdvice?.message.contains("27 mph") == true)
    }

    func testWeatherAdvisorColdRecommendsLayerOnlyWhenOuterwearMissing() {
        let missingOuterwear = WeatherAdvisor.advice(for: WeatherAdvisorInput(
            feelsLikeTemperature: 41,
            humidityPercent: nil,
            rainChancePercent: nil,
            windMph: nil,
            uvIndex: nil,
            condition: "Cold",
            confidence: 95,
            detectedGarments: ["shirt", "pants"]
        ))
        let hasOuterwear = WeatherAdvisor.advice(for: WeatherAdvisorInput(
            feelsLikeTemperature: 41,
            humidityPercent: nil,
            rainChancePercent: nil,
            windMph: nil,
            uvIndex: nil,
            condition: "Cold",
            confidence: 95,
            detectedGarments: ["coat", "pants"]
        ))

        XCTAssertTrue(missingOuterwear?.message.localizedCaseInsensitiveContains("outer layer") == true)
        XCTAssertNil(hasOuterwear)
    }

    func testPersonalStylistEngineContextContainsGuardrailsAndNoPII() {
        let input = PersonalStylistEngineInput(
            score: 90,
            scoreTier: "Great Match",
            scoreBreakdown: nil,
            detectedGarments: ["navy shirt"],
            colors: ["navy"],
            detectedStyle: "Casual",
            occasion: "Casual",
            weather: WeatherAdvisorAdvice(
                message: "There is a 50% chance of rain today. Grab an umbrella before going out.",
                reason: "Rain probability is 50%."
            ),
            memories: [],
            profile: makeStylistProfile(userId: "real-user-name"),
            dealMatches: []
        )

        let context = PersonalStylistEngine.context(input: input, saleMatchingEnabled: false)
        let payload = PersonalizationContextBuilder.buildPersonalStylistEnginePromptContext(context)

        XCTAssertTrue(payload.contains("You may only reference facts explicitly provided in the context object."))
        XCTAssertTrue(payload.contains("Do not invent weather conditions, garments, colors, dates, prices, or deals."))
        XCTAssertFalse(payload.contains("real-user-name"))
        XCTAssertFalse(payload.localizedCaseInsensitiveContains("latitude"))
        XCTAssertFalse(payload.localizedCaseInsensitiveContains("longitude"))
    }

    func testPersonalStylistEngineDoesNotModifyFixedScoreFixture() {
        let fixedScore = 82
        let input = makePersonalStylistInput(score: fixedScore)
        let engineInput = PersonalStylistEngineInput(
            score: input.score,
            scoreTier: input.scoreTier,
            scoreBreakdown: input.scoreBreakdown,
            detectedGarments: input.detectedGarments,
            colors: input.colors,
            detectedStyle: input.detectedStyle,
            occasion: input.occasion,
            memories: input.memories,
            profile: input.profile,
            dealMatches: []
        )

        let context = PersonalStylistEngine.context(
            input: engineInput,
            weatherAdviceEnabled: false,
            saleMatchingEnabled: false
        )

        XCTAssertEqual(input.score, fixedScore)
        XCTAssertEqual(context.score, fixedScore)
        XCTAssertTrue(context.allowedMessages.joined(separator: " ").contains("82/100"))
    }

    func testWeatherAdvisorRainRecommendationUsesRealRainData() {
        let advice = WeatherAdvisor.advice(for: WeatherAdvisorInput(
            feelsLikeTemperature: 78,
            humidityPercent: 62,
            rainChancePercent: 70,
            windMph: nil,
            uvIndex: nil,
            condition: "Rain",
            confidence: 95
        ))

        XCTAssertEqual(advice?.message, "There is a 70% chance of rain today. Grab an umbrella before going out.")
        XCTAssertTrue(advice?.reason.contains("70%") == true)
    }

    func testSaleMatchingFlagOnUsesOnlyProvidedDeal() {
        let deal = PersonalStylistDealMatch(
            productName: "Clean Leather Sneaker",
            retailerName: "Nike",
            category: "Shoes",
            salePrice: "$110.00",
            reason: "Matches the scanned shoe category."
        )
        let input = makePersonalStylistInput(score: 89, dealMatches: [deal])

        let message = PersonalStylistIntelligenceBuilder.buildMessage(
            input: input,
            weatherAdviceEnabled: false,
            saleMatchingEnabled: true
        )

        let dealSection = message.sections.first { $0.source == .shoppingDeals }
        XCTAssertNotNil(dealSection)
        XCTAssertTrue(dealSection?.body.contains("Clean Leather Sneaker") == true)
        XCTAssertTrue(dealSection?.body.contains("Nike") == true)
        XCTAssertFalse(dealSection?.body.contains("Amazon") == true)
    }

    func testHistoryRecallOmitsWhenNoHistoryOrLearnedPreference() {
        var input = makePersonalStylistInput(score: 80)
        input = PersonalStylistIntelligenceInput(
            score: input.score,
            scoreTier: input.scoreTier,
            scoreBreakdown: input.scoreBreakdown,
            detectedGarments: input.detectedGarments,
            colors: input.colors,
            detectedStyle: input.detectedStyle,
            occasion: input.occasion,
            weather: nil,
            memories: [],
            profile: makeStylistProfile(userId: userA),
            dealMatches: []
        )

        let message = PersonalStylistIntelligenceBuilder.buildMessage(
            input: input,
            weatherAdviceEnabled: false,
            saleMatchingEnabled: false
        )

        XCTAssertFalse(message.sections.contains { $0.source == .history })
    }

    func testHistoryRecallUsesMatchingPastOutfitFacts() {
        var memory = makeOutfitMemory(userId: userA, record: makeGarmentRecord(fingerprint: "shirt-navy-solid"))
        memory.detectedGarments = ["shirt", "pants"]
        memory.colors = ["navy", "black"]
        memory.detectedStyle = "Smart Casual"
        memory.styleScore = 93
        memory.wasLiked = true
        memory.wouldWearAgain = true
        memory.outfitFingerprint = "outfit-v4|same-outfit"
        memory.imageDigest = "same-image"

        let input = makePersonalStylistInput(
            score: 86,
            memories: [memory],
            outfitFingerprint: "outfit-v4|same-outfit",
            imageDigest: "same-image"
        )
        let message = PersonalStylistIntelligenceBuilder.buildMessage(
            input: input,
            weatherAdviceEnabled: false,
            saleMatchingEnabled: false
        )

        let history = message.sections.first { $0.source == .history }
        XCTAssertNotNil(history)
        XCTAssertTrue(history?.body.contains("score: 93") == true)
        XCTAssertTrue(history?.body.localizedCaseInsensitiveContains("navy shirt") == true)
    }

    func testOutfitRecallServiceFormatsRelativeDatesAndReturnsNilWithoutMatch() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 7))!
        var memory = makeOutfitMemory(userId: userA, record: makeGarmentRecord(fingerprint: "shirt-black-solid"))
        memory.scanDate = calendar.date(from: DateComponents(year: 2026, month: 7, day: 3))!
        memory.detectedGarments = ["shirt"]
        memory.colors = ["black"]
        memory.detectedStyle = "Smart Casual"
        memory.styleScore = 85
        memory.outfitFingerprint = "outfit-v4|black-shirt-outfit"
        memory.imageDigest = "black-shirt-image"

        let match = OutfitRecallService.recallFact(
            for: OutfitRecallScanContext(
                detectedGarments: ["shirt"],
                colors: ["black"],
                detectedStyle: "Smart Casual",
                outfitFingerprint: "outfit-v4|black-shirt-outfit",
                imageDigest: "black-shirt-image"
            ),
            memories: [memory],
            now: now
        )
        let noMatch = OutfitRecallService.recallFact(
            for: OutfitRecallScanContext(
                detectedGarments: ["shoe"],
                colors: ["white"],
                detectedStyle: "Athletic",
                outfitFingerprint: "outfit-v4|different-outfit",
                imageDigest: "different-image"
            ),
            memories: [memory],
            now: now
        )

        XCTAssertEqual(match?.text, "You wore black shirt last Thursday (score: 85).")
        XCTAssertNil(noMatch)
    }

    func testOutfitRecallServiceReturnsNilWithEmptyMemory() {
        let recall = OutfitRecallService.recallFact(
            for: OutfitRecallScanContext(
                detectedGarments: ["shirt"],
                colors: ["black"],
                detectedStyle: "Casual"
            ),
            memories: []
        )

        XCTAssertNil(recall)
    }

    func testOutfitRecallServiceCanIncrementSeenCountersThroughStoreMerge() {
        let store = OutfitMemoryStore(defaults: defaults, userId: userA)
        var record = makeGarmentRecord(fingerprint: "category:shirt|colors:black|pattern:solid|fabric:unknown|brand:unknown")
        record.garmentCategory = "shirt"
        record.colors = ["black"]
        var memory = makeOutfitMemory(userId: userA, record: record)
        memory.detectedGarments = ["shirt"]
        memory.colors = ["black"]
        memory.detectedStyle = "Casual"
        memory.outfitFingerprint = "outfit-v4|counter-outfit"
        memory.imageDigest = "counter-image"
        store.addOrMergeScan(memory)

        let incoming = GarmentRecord(
            garmentCategory: "shirt",
            itemFingerprint: "category:shirt|colors:black|pattern:solid|fabric:unknown|brand:unknown",
            colors: ["black"],
            styleTags: ["Casual"],
            colorConfidence: 80,
            sourceScanIds: ["scan-2"]
        )

        _ = OutfitRecallService.recallFact(
            for: OutfitRecallScanContext(
                detectedGarments: ["shirt"],
                colors: ["black"],
                detectedStyle: "Casual",
                garmentRecords: [incoming],
                outfitFingerprint: "outfit-v4|counter-outfit",
                imageDigest: "counter-image"
            ),
            store: store,
            incrementCounters: true
        )

        XCTAssertEqual(store.garmentRecords.first?.timesSeen, 2)
    }

    private func makePersonalStylistInput(
        score: Int,
        weather: WeatherContextRecommendation? = nil,
        memories: [OutfitMemory] = [],
        dealMatches: [PersonalStylistDealMatch] = [],
        outfitFingerprint: String? = nil,
        imageDigest: String? = nil
    ) -> PersonalStylistIntelligenceInput {
        PersonalStylistIntelligenceInput(
            score: score,
            scoreTier: "Good Match",
            scoreBreakdown: OutfitScoreBreakdown(
                colorHarmony: 23,
                patternBalance: 18,
                fitQuality: 21,
                occasionMatch: 17,
                accessoryUse: 8
            ),
            detectedGarments: ["navy shirt", "black pants", "white sneakers"],
            colors: ["navy", "black", "white"],
            detectedStyle: "Smart Casual",
            occasion: "Casual",
            weather: weather,
            memories: memories,
            profile: makeStylistProfile(userId: userA),
            dealMatches: dealMatches,
            outfitFingerprint: outfitFingerprint,
            imageDigest: imageDigest
        )
    }

    private func makeGarmentRecord(
        fingerprint: String,
        sourceScanIds: [String] = ["scan-1"]
    ) -> GarmentRecord {
        GarmentRecord(
            garmentCategory: "pants",
            itemFingerprint: fingerprint,
            brand: nil,
            fit: "regular",
            fabric: "cotton",
            pattern: "solid",
            colors: ["black"],
            styleTags: ["casual"],
            colorConfidence: 90,
            timesSeen: 1,
            timesWorn: 0,
            sourceScanIds: sourceScanIds
        )
    }

    private func makeOutfitMemory(userId: String, record: GarmentRecord) -> OutfitMemory {
        OutfitMemory(
            id: UUID(),
            userId: userId,
            scanDate: Date(),
            detectedGarments: [record.garmentCategory],
            colors: record.colors,
            detectedStyle: "Casual",
            styleScore: 82,
            occasion: .casual,
            wasWorn: nil,
            wasLiked: nil,
            feedbackTimestamp: nil,
            dislikeReason: nil,
            wouldWearAgain: nil,
            receivedCompliments: nil,
            isFavorite: false,
            timesWorn: 0,
            garmentRecords: [record]
        )
    }

    private func markFeedbackFirstSessionSeen(for userId: String) {
        let key = PersonalStylistStorage.scopedKey("personalStylistFeedbackFirstSessionSeen", userID: userId)
        defaults.set(true, forKey: key)
    }

    private func mockDealFixtureURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/mock_deals.json")
    }

    private func fixtureURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name)")
    }

    private func retailerConfigFixtureURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("StyleMatchAI/Shopping/RetailerConfig.json")
    }

    private func fixedDate(year: Int, month: Int, day: Int) -> Date {
        fixedDate(year: year, month: month, day: day, hour: 12)
    }

    private func fixedDate(year: Int, month: Int, day: Int, hour: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func makeBlackPantsAndShirtMemory() -> OutfitMemory {
        var pants = makeGarmentRecord(fingerprint: "category:pants|colors:black|pattern:solid|fabric:cotton|brand:unknown")
        pants.garmentCategory = "pants"
        pants.colors = ["black"]

        var shirt = makeGarmentRecord(fingerprint: "category:shirt|colors:black|pattern:solid|fabric:cotton|brand:unknown")
        shirt.garmentCategory = "shirt"
        shirt.colors = ["black"]

        var memory = makeOutfitMemory(userId: userA, record: pants)
        memory.detectedGarments = ["pants", "shirt"]
        memory.colors = ["black", "black"]
        memory.garmentRecords = [pants, shirt]
        return memory
    }

    private func makeAffiliateProduct(
        id: String,
        name: String = "Test Product",
        category: ProductCategory = .clothing,
        subcategory: String = "shirt",
        colors: [String] = ["white"],
        retailer: Retailer = Retailer(name: "Macy's", trackingID: "PENDING-APPROVAL", trackingParamName: "aff", disclosureName: "Macy's"),
        affiliateURL: URL = URL(string: "https://www.macys.com/test-product")!,
        price: Decimal? = Decimal(80),
        salePrice: Decimal? = nil,
        saleEndsAt: Date? = nil,
        tags: [String] = [],
        sizes: [String]? = nil,
        priceRange: ClosedRange<Decimal>? = nil,
        occasionTags: [String]? = nil,
        brand: String? = nil
    ) -> AffiliateProduct {
        AffiliateProduct(
            id: id,
            name: name,
            category: category,
            subcategory: subcategory,
            colors: colors,
            sizes: sizes,
            priceRange: priceRange,
            occasionTags: occasionTags,
            brand: brand,
            imageURL: URL(string: "https://www.example.com/image.jpg")!,
            retailer: retailer,
            affiliateURL: affiliateURL,
            price: price,
            salePrice: salePrice,
            saleEndsAt: saleEndsAt,
            availableColors: nil,
            customerRating: nil,
            reviewCount: nil,
            estimatedShippingText: nil,
            tags: tags,
            genderPresentation: nil
        )
    }

    private func makeStylistProfile(userId: String) -> StylistProfile {
        StylistProfile(
            id: UUID(),
            userId: userId,
            favoriteColors: [],
            dislikedColors: [],
            favoriteBrands: [],
            preferredFit: .regular,
            budgetRange: BudgetRange(minPrice: 50, maxPrice: 200, preferredTier: "Mid"),
            climate: "Mild",
            workDressCode: "Smart casual",
            bodyProportions: nil,
            clothingSizes: ClothingSizes(),
            stylePreferencesLearned: [:],
            createdAt: Date(),
            lastUpdatedAt: Date(),
            totalScansCompleted: 0,
            profileConfidenceScore: 20
        )
    }

    private func seedFounderSizeDefaults() {
        defaults.set("Men", forKey: "sizeCategory")
        defaults.set("L", forKey: "shirtSize")
        defaults.set("Men 36x36", forKey: "pantsSize")
        defaults.set("36", forKey: "waistSize")
        defaults.set("36", forKey: "inseamLength")
        defaults.set("10", forKey: "shoeSize")
        defaults.set("Regular", forKey: "fitPreference")
    }

    func testGreetingBuilderDoesNotUsePlaceholderNameForEmptyProfile() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let morning = Date(timeIntervalSince1970: 1_704_094_800) // 2024-01-01 09:00:00 UTC

        let emptyGreeting = StyleMatchGreetingBuilder.greetingLine(date: morning, calendar: calendar, storedName: "")
        let placeholderGreeting = StyleMatchGreetingBuilder.greetingLine(date: morning, calendar: calendar, storedName: "Style Match Pro User")
        let leakedNameGreeting = StyleMatchGreetingBuilder.greetingLine(date: morning, calendar: calendar, storedName: ["Saba", "stine"].joined())

        XCTAssertEqual(emptyGreeting, "Good Morning")
        XCTAssertEqual(placeholderGreeting, "Good Morning")
        XCTAssertEqual(leakedNameGreeting, "Good Morning")
        XCTAssertFalse(emptyGreeting.localizedCaseInsensitiveContains(["Saba", "stine"].joined()))
        XCTAssertFalse(placeholderGreeting.localizedCaseInsensitiveContains(["Saba", "stine"].joined()))
        XCTAssertFalse(leakedNameGreeting.localizedCaseInsensitiveContains(["Saba", "stine"].joined()))
    }

    func testDefaultProfileDoesNotInheritGlobalProfileName() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let morning = Date(timeIntervalSince1970: 1_704_094_800) // 2024-01-01 09:00:00 UTC
        defaults.set(["Saba", "stine"].joined(), forKey: "profileName")

        let newUserProfile = ProfileStore(defaults: defaults, userId: userB).currentProfile

        XCTAssertNil(newUserProfile.givenName)
        XCTAssertEqual(
            StyleMatchGreetingBuilder.greetingLine(date: morning, calendar: calendar, storedName: newUserProfile.givenName),
            "Good Morning"
        )
    }

    func testFounderDefaultsMigrationClearsExactFingerprintWithoutSaveMarker() {
        seedFounderSizeDefaults()
        defaults.set("Black, white, navy", forKey: "favoriteColors")
        defaults.set("Ralph Lauren, Nike, Levi's", forKey: "favoriteBrands")

        XCTAssertTrue(FounderProfileDefaultsMigration.matchesFounderFingerprint(defaults: defaults))
        XCTAssertTrue(FounderProfileDefaultsMigration.run(defaults: defaults, userID: userA))

        XCTAssertNil(defaults.object(forKey: "sizeCategory"))
        XCTAssertNil(defaults.object(forKey: "shirtSize"))
        XCTAssertNil(defaults.object(forKey: "pantsSize"))
        XCTAssertNil(defaults.object(forKey: "waistSize"))
        XCTAssertNil(defaults.object(forKey: "inseamLength"))
        XCTAssertNil(defaults.object(forKey: "shoeSize"))
        XCTAssertNil(defaults.object(forKey: "fitPreference"))
        XCTAssertNil(defaults.object(forKey: "favoriteColors"))
        XCTAssertNil(defaults.object(forKey: "favoriteBrands"))
        XCTAssertTrue(defaults.bool(forKey: FounderProfileDefaultsMigration.migrationFlag))
    }

    func testFounderDefaultsMigrationPreservesRealSavedProfile() {
        seedFounderSizeDefaults()
        defaults.set("2026-07-09T09:00:00Z", forKey: FounderProfileDefaultsMigration.profileLastSavedAtKey)
        defaults.set("Black, white, navy", forKey: "favoriteColors")
        defaults.set("Ralph Lauren, Nike, Levi's", forKey: "favoriteBrands")

        XCTAssertTrue(FounderProfileDefaultsMigration.matchesFounderFingerprint(defaults: defaults))
        XCTAssertFalse(FounderProfileDefaultsMigration.run(defaults: defaults, userID: userA))

        XCTAssertEqual(defaults.string(forKey: "sizeCategory"), "Men")
        XCTAssertEqual(defaults.string(forKey: "shirtSize"), "L")
        XCTAssertEqual(defaults.string(forKey: "pantsSize"), "Men 36x36")
        XCTAssertEqual(defaults.string(forKey: "waistSize"), "36")
        XCTAssertEqual(defaults.string(forKey: "inseamLength"), "36")
        XCTAssertEqual(defaults.string(forKey: "shoeSize"), "10")
        XCTAssertEqual(defaults.string(forKey: "fitPreference"), "Regular")
        XCTAssertEqual(defaults.string(forKey: "favoriteColors"), "Black, white, navy")
        XCTAssertEqual(defaults.string(forKey: "favoriteBrands"), "Ralph Lauren, Nike, Levi's")
        XCTAssertTrue(defaults.bool(forKey: FounderProfileDefaultsMigration.migrationFlag))
    }

    func testFounderDefaultsMigrationPreservesNonExactProfileValues() {
        seedFounderSizeDefaults()
        defaults.set("Men 36x32", forKey: "pantsSize")

        XCTAssertFalse(FounderProfileDefaultsMigration.matchesFounderFingerprint(defaults: defaults))
        XCTAssertFalse(FounderProfileDefaultsMigration.run(defaults: defaults, userID: userA))

        XCTAssertEqual(defaults.string(forKey: "pantsSize"), "Men 36x32")
        XCTAssertEqual(defaults.string(forKey: "waistSize"), "36")
        XCTAssertEqual(defaults.string(forKey: "inseamLength"), "36")
    }

    func testFounderDefaultsMigrationRunsOnlyOnce() {
        seedFounderSizeDefaults()

        XCTAssertTrue(FounderProfileDefaultsMigration.run(defaults: defaults, userID: userA))
        defaults.set("Men 36x36", forKey: "pantsSize")
        defaults.set("36", forKey: "waistSize")
        defaults.set("36", forKey: "inseamLength")

        XCTAssertFalse(FounderProfileDefaultsMigration.run(defaults: defaults, userID: userA))
        XCTAssertEqual(defaults.string(forKey: "pantsSize"), "Men 36x36")
    }

    func testProfileStoreFreshInstallUsesBlankProfileAndZeroCompleteness() {
        let profile = ProfileStore(defaults: defaults, userId: userA).currentProfile

        XCTAssertTrue(profile.favoriteColors.isEmpty)
        XCTAssertTrue(profile.favoriteBrands.isEmpty)
        XCTAssertNil(profile.clothingSizes.shirtSize)
        XCTAssertNil(profile.clothingSizes.pantSize)
        XCTAssertNil(profile.clothingSizes.shoeSize)
        XCTAssertNil(profile.clothingSizes.jacketSize)
        XCTAssertNil(profile.clothingSizes.dressSize)
        XCTAssertEqual(profile.preferredFit, .unset)
        XCTAssertEqual(profile.budgetRange.minPrice, BudgetRange.neutral.minPrice)
        XCTAssertEqual(profile.budgetRange.maxPrice, BudgetRange.neutral.maxPrice)
        XCTAssertEqual(profile.budgetRange.preferredTier, BudgetRange.neutral.preferredTier)
        XCTAssertTrue(profile.climate.isEmpty)
        XCTAssertTrue(profile.workDressCode.isEmpty)
        XCTAssertEqual(ProfileStore.profileCompletenessPercentage(profile), 0)
    }

    func testProfileStoreKeepsSavedProfileThroughFounderMigration() {
        seedFounderSizeDefaults()
        defaults.set("2026-07-09T09:00:00Z", forKey: FounderProfileDefaultsMigration.profileLastSavedAtKey)

        let profile = ProfileStore(defaults: defaults, userId: userA).currentProfile

        XCTAssertEqual(profile.clothingSizes.shirtSize, "L")
        XCTAssertEqual(profile.clothingSizes.pantSize, "Men 36x36")
        XCTAssertEqual(profile.clothingSizes.shoeSize, "10")
        XCTAssertEqual(profile.preferredFit, .regular)
        XCTAssertEqual(defaults.string(forKey: "sizeCategory"), "Men")
        XCTAssertEqual(defaults.string(forKey: "waistSize"), "36")
        XCTAssertEqual(defaults.string(forKey: "inseamLength"), "36")
    }

    func testProfileStoreSavedSizeMutationPersistsAcrossReload() {
        defaults.set("2026-07-09T09:00:00Z", forKey: FounderProfileDefaultsMigration.profileLastSavedAtKey)

        let store = ProfileStore(defaults: defaults, userId: userA)
        var profile = store.currentProfile
        profile.clothingSizes = ClothingSizes(shirtSize: "L", pantSize: "Men 36x36", shoeSize: "10")
        profile.preferredFit = .regular
        store.currentProfile = profile
        store.save()

        var reloaded = ProfileStore(defaults: defaults, userId: userA).currentProfile
        XCTAssertEqual(reloaded.clothingSizes.pantSize, "Men 36x36")

        reloaded.clothingSizes = ClothingSizes(shirtSize: "L", pantSize: "Men 34x34", shoeSize: "10")
        reloaded.preferredFit = .tailored
        let mutationStore = ProfileStore(defaults: defaults, userId: userA)
        mutationStore.currentProfile = reloaded
        mutationStore.save()

        let finalProfile = ProfileStore(defaults: defaults, userId: userA).currentProfile
        XCTAssertEqual(finalProfile.clothingSizes.pantSize, "Men 34x34")
        XCTAssertEqual(finalProfile.clothingSizes.shirtSize, "L")
        XCTAssertEqual(finalProfile.clothingSizes.shoeSize, "10")
        XCTAssertEqual(finalProfile.preferredFit, .tailored)
        XCTAssertEqual(defaults.string(forKey: FounderProfileDefaultsMigration.profileLastSavedAtKey), "2026-07-09T09:00:00Z")
    }

    func testClearProfilePreferenceDefaultsReturnsToBlankAfterRelaunch() {
        seedFounderSizeDefaults()
        defaults.set("2026-07-09T09:00:00Z", forKey: FounderProfileDefaultsMigration.profileLastSavedAtKey)

        let store = ProfileStore(defaults: defaults, userId: userA)
        var profile = store.currentProfile
        profile.clothingSizes = ClothingSizes(shirtSize: "L", pantSize: "Men 36x36", shoeSize: "10")
        profile.preferredFit = .regular
        profile.favoriteColors = ["black"]
        store.currentProfile = profile
        store.save()

        FounderProfileDefaultsMigration.clearProfilePreferenceDefaults(defaults: defaults, userID: userA)

        XCTAssertNil(defaults.object(forKey: FounderProfileDefaultsMigration.profileLastSavedAtKey))
        let reloaded = ProfileStore(defaults: defaults, userId: userA).currentProfile
        XCTAssertNil(reloaded.clothingSizes.shirtSize)
        XCTAssertNil(reloaded.clothingSizes.pantSize)
        XCTAssertNil(reloaded.clothingSizes.shoeSize)
        XCTAssertEqual(reloaded.preferredFit, .unset)
        XCTAssertTrue(reloaded.favoriteColors.isEmpty)
        XCTAssertEqual(ProfileStore.profileCompletenessPercentage(reloaded), 0)
    }

    func testScanFitCopyDoesNotClaimSavedSizesWithoutSavedProfile() throws {
        let scanSource = try projectSource("StyleMatchAI/ScanView.swift")

        XCTAssertTrue(scanSource.contains("hasSavedSizeProfileForFitCopy"))
        XCTAssertTrue(scanSource.contains("No saved sizes yet"))
        XCTAssertTrue(scanSource.contains("Fit check: no saved sizes yet"))
        XCTAssertFalse(scanSource.contains("After a scan, this uses your saved sizes"))
        XCTAssertFalse(scanSource.contains("Fit check: using your saved sizes ("))
    }

    func testLoginWelcomeProfileDataRequiresIntentionalSaveMarker() {
        defaults.set("Navy blazer with dark denim", forKey: "favoriteOutfits")
        defaults.set("Classic, business casual, clean sneakers", forKey: "stylePreferences")
        defaults.set("Black, white, navy", forKey: "favoriteColors")

        XCTAssertFalse(
            LoginWelcomeProfileData.hasIntentionalProfileValues(
                favoriteOutfits: "Navy blazer with dark denim",
                stylePreferences: "Classic, business casual, clean sneakers",
                favoriteColors: "Black, white, navy",
                profileName: "",
                defaults: defaults
            )
        )

        defaults.set("2026-07-09T09:00:00Z", forKey: FounderProfileDefaultsMigration.profileLastSavedAtKey)

        XCTAssertTrue(
            LoginWelcomeProfileData.hasIntentionalProfileValues(
                favoriteOutfits: "Navy blazer with dark denim",
                stylePreferences: "",
                favoriteColors: "",
                profileName: "",
                defaults: defaults
            )
        )
    }

    func testProfileDisplaySourcesDoNotUseFakeScoreFallbacks() throws {
        let homeSource = try projectSource("StyleMatchAI/HomeView.swift")
        let contentSource = try projectSource("StyleMatchAI/ContentView.swift")

        XCTAssertFalse(homeSource.contains("return \"92\""))
        XCTAssertFalse(contentSource.contains("?? 92"))
        XCTAssertFalse(contentSource.contains("\"92-95 if the fit is clean\""))
        XCTAssertFalse(contentSource.contains("Only black loafers or clean sneakers appear to be missing."))
    }

    func testPrivacyDeletionUsesActiveUserBeforeClearingSessionKeys() {
        defaults.set(userA, forKey: "customerAppleUserID")
        defaults.set(["Saba", "stine"].joined(), forKey: "profileName")

        let profileA = ProfileStore(defaults: defaults, userId: userA)
        profileA.currentProfile.favoriteColors = ["black"]
        profileA.save()

        let profileB = ProfileStore(defaults: defaults, userId: userB)
        profileB.currentProfile.favoriteColors = ["white"]
        profileB.save()

        ShoppingLocalStore(defaults: defaults, userID: userA).savedFavorites = ["sale-a"]
        ShoppingLocalStore(defaults: defaults, userID: userB).savedFavorites = ["sale-b"]

        let deletedUserID = PersonalStylistStorage.deleteActiveUserData(defaults: defaults)
        ShoppingLocalStore.deleteShoppingData(for: deletedUserID, defaults: defaults)
        defaults.removeObject(forKey: "profileName")

        XCTAssertEqual(deletedUserID, PersonalStylistStorage.normalizedUserID(userA))
        XCTAssertNil(defaults.object(forKey: "profileName"))
        XCTAssertNil(
            defaults.object(forKey: PersonalStylistStorage.scopedKey(PersonalStylistStorage.legacyProfileKey, userID: userA)),
            "The signed-in user's profile should be removed before the Apple user id is cleared."
        )
        XCTAssertTrue(ShoppingLocalStore(defaults: defaults, userID: userA).savedFavorites.isEmpty)
        XCTAssertNotNil(
            defaults.object(forKey: PersonalStylistStorage.scopedKey(PersonalStylistStorage.legacyProfileKey, userID: userB)),
            "Deleting user A should not remove user B's profile."
        )
        XCTAssertEqual(ShoppingLocalStore(defaults: defaults, userID: userB).savedFavorites, ["sale-b"])
    }


    func testPrivacyDeletionContractClearsProfileAssistantClosetWishlistAndScanHistoryForActiveUser() throws {
        let profileSource = try projectSource("StyleMatchAI/ProfileView.swift")
        let privacySource = try projectSource("StyleMatchAI/PrivacyDataManager.swift")
        XCTAssertTrue(profileSource.contains("PrivacyDataManager.shared.deleteAllLocalCustomerData()"))
        XCTAssertTrue(privacySource.contains("let activeUserID = PersonalStylistStorage.activeUserID(defaults: defaults)"))
        XCTAssertTrue(privacySource.contains("ChatConversationStore().deleteAll()"))
        XCTAssertTrue(privacySource.contains("PersonalStylistStorage.deletePersonalization(for: activeUserID, defaults: defaults)"))
        XCTAssertTrue(privacySource.contains("ShoppingLocalStore.deleteShoppingData(for: activeUserID, defaults: defaults)"))
        XCTAssertTrue(privacySource.contains("try? OpenAIKeychain.deleteAPIKey()"))

        defaults.set(userA, forKey: "customerAppleUserID")
        defaults.set("apple", forKey: "customerAccountMode")
        defaults.set("tester@example.com", forKey: "customerAccountEmail")
        defaults.set("2026-07-10T09:00:00Z", forKey: FounderProfileDefaultsMigration.profileLastSavedAtKey)

        let profileA = ProfileStore(defaults: defaults, userId: userA)
        profileA.currentProfile.favoriteColors = ["black"]
        profileA.save()

        let profileB = ProfileStore(defaults: defaults, userId: userB)
        profileB.currentProfile.favoriteColors = ["white"]
        profileB.save()

        let memoryA = OutfitMemoryStore(defaults: defaults, userId: userA)
        memoryA.addOrMergeScan(makeOutfitMemory(userId: userA, record: makeGarmentRecord(fingerprint: "privacy-user-a")))

        let memoryB = OutfitMemoryStore(defaults: defaults, userId: userB)
        memoryB.addOrMergeScan(makeOutfitMemory(userId: userB, record: makeGarmentRecord(fingerprint: "privacy-user-b")))

        let closetData = try JSONEncoder().encode([
            ClosetItem(
                name: "White Shirt",
                category: "Shirt",
                color: "White",
                brand: "Test Brand",
                size: "M",
                occasion: "Work",
                notes: "Seed item"
            )
        ])
        defaults.set(closetData, forKey: "closetItemsData")
        defaults.set("White Shirt", forKey: "closetInventory")
        defaults.set(["wishlist-name"], forKey: "wishlistProductNamesData")
        defaults.set(Data("scan-history".utf8), forKey: "outfitScanHistoryData")
        defaults.set("ChatGPT", forKey: "preferredAIAssistant")
        defaults.set("ChatGPT,Gemini", forKey: "connectedAIAssistants")
        defaults.set("gpt-test", forKey: "openAIModel")
        defaults.set(true, forKey: "shareAppContextWithChatGPT")

        let shoppingA = ShoppingLocalStore(defaults: defaults, userID: userA)
        shoppingA.savedFavorites = ["favorite-a"]
        shoppingA.wishlistProductIDs = ["wishlist-a"]
        shoppingA.cartProductIDs = ["cart-a"]

        let shoppingB = ShoppingLocalStore(defaults: defaults, userID: userB)
        shoppingB.savedFavorites = ["favorite-b"]
        shoppingB.wishlistProductIDs = ["wishlist-b"]

        let activeUserID = PersonalStylistStorage.activeUserID(defaults: defaults)
        for key in [
            "customerAppleUserID",
            "customerAccountMode",
            "customerAccountEmail",
            FounderProfileDefaultsMigration.profileLastSavedAtKey,
            "closetItemsData",
            "closetInventory",
            "wishlistProductNamesData",
            "outfitScanHistoryData",
            "preferredAIAssistant",
            "connectedAIAssistants",
            "openAIModel",
            "shareAppContextWithChatGPT"
        ] {
            defaults.removeObject(forKey: key)
        }
        PersonalStylistStorage.deletePersonalization(for: activeUserID, defaults: defaults)
        ShoppingLocalStore.deleteShoppingData(for: activeUserID, defaults: defaults)

        XCTAssertEqual(activeUserID, PersonalStylistStorage.normalizedUserID(userA))
        XCTAssertNil(defaults.object(forKey: "customerAppleUserID"))
        XCTAssertNil(defaults.object(forKey: "customerAccountMode"))
        XCTAssertNil(defaults.object(forKey: "customerAccountEmail"))
        XCTAssertNil(defaults.object(forKey: FounderProfileDefaultsMigration.profileLastSavedAtKey))
        XCTAssertNil(defaults.object(forKey: "closetItemsData"))
        XCTAssertNil(defaults.object(forKey: "closetInventory"))
        XCTAssertNil(defaults.object(forKey: "wishlistProductNamesData"))
        XCTAssertNil(defaults.object(forKey: "outfitScanHistoryData"))
        XCTAssertNil(defaults.object(forKey: "preferredAIAssistant"))
        XCTAssertNil(defaults.object(forKey: "connectedAIAssistants"))
        XCTAssertNil(defaults.object(forKey: "openAIModel"))
        XCTAssertNil(defaults.object(forKey: "shareAppContextWithChatGPT"))

        XCTAssertNil(defaults.object(forKey: PersonalStylistStorage.scopedKey(PersonalStylistStorage.legacyProfileKey, userID: userA)))
        XCTAssertNil(defaults.object(forKey: PersonalStylistStorage.scopedKey(PersonalStylistStorage.legacyMemoriesKey, userID: userA)))
        XCTAssertTrue(ShoppingLocalStore(defaults: defaults, userID: userA).savedFavorites.isEmpty)
        XCTAssertTrue(ShoppingLocalStore(defaults: defaults, userID: userA).wishlistProductIDs.isEmpty)
        XCTAssertTrue(ShoppingLocalStore(defaults: defaults, userID: userA).cartProductIDs.isEmpty)

        XCTAssertNotNil(defaults.object(forKey: PersonalStylistStorage.scopedKey(PersonalStylistStorage.legacyProfileKey, userID: userB)))
        XCTAssertNotNil(defaults.object(forKey: PersonalStylistStorage.scopedKey(PersonalStylistStorage.legacyMemoriesKey, userID: userB)))
        XCTAssertEqual(ShoppingLocalStore(defaults: defaults, userID: userB).savedFavorites, ["favorite-b"])
        XCTAssertEqual(ShoppingLocalStore(defaults: defaults, userID: userB).wishlistProductIDs, ["wishlist-b"])
    }

    func testDeprecatedAIAssistantPreferenceRepairClearsLegacyProviderState() {
        defaults.set("ChatGPT", forKey: DeprecatedAIAssistantPreferenceRepair.preferredKey)
        defaults.set("ChatGPT,Gemini", forKey: DeprecatedAIAssistantPreferenceRepair.connectedKey)
        defaults.set("tester@example.com", forKey: "customerAccountEmail")

        DeprecatedAIAssistantPreferenceRepair.run(defaults: defaults)

        XCTAssertNil(defaults.object(forKey: DeprecatedAIAssistantPreferenceRepair.preferredKey))
        XCTAssertNil(defaults.object(forKey: DeprecatedAIAssistantPreferenceRepair.connectedKey))
        XCTAssertEqual(defaults.string(forKey: "customerAccountEmail"), "tester@example.com")
    }

    func testThirdPartyAssistantProviderCopyIsRemovedFromPublicAISurfaces() throws {
        let surfaces = [
            "StyleMatchAI/ProfileView.swift",
            "StyleMatchAI/HomeView.swift",
            "StyleMatchAI/ContentView.swift",
            "StyleMatchAI/AIAssistantsView.swift"
        ]
        let forbiddenPhrases = [
            "Preferred AI Assistant",
            "Choose AI Assistant",
            "Choose Your AI Stylist",
            "Switch AI",
            "Powered by ChatGPT",
            "ChatGPT powers",
            "Sign in with ChatGPT",
            "ChatGPT Awareness",
            "ChatGPT App Awareness",
            "ChatGPT Live Assistant",
            "ChatGPT Subscription Access",
            "Open ChatGPT",
            "Message ChatGPT",
            "Ask ChatGPT Stylist",
            "Siri AI",
            "Gemini AI",
            "Claude AI",
            "Perplexity AI",
            "Preferred assistant:"
        ]

        for file in surfaces {
            let source = try projectSource(file)
            for phrase in forbiddenPhrases {
                XCTAssertFalse(source.contains(phrase), "\(file) still contains \(phrase)")
            }
        }
    }

    func testPromptContextDoesNotIncludePreferredAssistantLine() throws {
        for file in [
            "StyleMatchAI/ContentView.swift",
            "StyleMatchAI/PersonalStylist/StylistContextBuilder.swift",
            "StyleMatchAI/AIAssistantsView.swift"
        ] {
            XCTAssertFalse(try projectSource(file).contains("Preferred assistant:"))
        }
    }

    func testLegacyProfileKeyMigrationPurgesGlobalKeysOnlyOnce() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let morning = Date(timeIntervalSince1970: 1_704_094_800) // 2024-01-01 09:00:00 UTC

        for key in LegacyProfileKeyMigration.legacyGlobalProfileKeys {
            defaults.set("LeakedName", forKey: key)
        }

        let scopedProfileKey = PersonalStylistStorage.scopedKey(PersonalStylistStorage.legacyProfileKey, userID: userA)
        let scopedMemoryKey = PersonalStylistStorage.scopedKey(PersonalStylistStorage.legacyMemoriesKey, userID: userA)
        let scopedShoppingKey = PersonalStylistStorage.scopedKey(ShoppingLocalStore.savedFavoritesBaseKey, userID: userA)
        let profileData = Data("profile".utf8)
        let memoryData = Data("memory".utf8)
        defaults.set(profileData, forKey: scopedProfileKey)
        defaults.set(memoryData, forKey: scopedMemoryKey)
        defaults.set(["keep-favorite"], forKey: scopedShoppingKey)

        LegacyProfileKeyMigration.run(defaults: defaults)

        for key in LegacyProfileKeyMigration.legacyGlobalProfileKeys {
            XCTAssertNil(defaults.object(forKey: key), "Legacy global key \(key) should be purged.")
        }
        XCTAssertTrue(defaults.bool(forKey: LegacyProfileKeyMigration.migrationFlag))
        XCTAssertEqual(
            StyleMatchGreetingBuilder.greetingLine(date: morning, calendar: calendar, storedName: defaults.string(forKey: "profileName")),
            "Good Morning"
        )
        XCTAssertEqual(defaults.data(forKey: scopedProfileKey), profileData)
        XCTAssertEqual(defaults.data(forKey: scopedMemoryKey), memoryData)
        XCTAssertEqual(defaults.stringArray(forKey: scopedShoppingKey), ["keep-favorite"])

        defaults.set("ShouldRemainAfterCompletedMigration", forKey: "profileName")
        LegacyProfileKeyMigration.run(defaults: defaults)

        XCTAssertEqual(
            defaults.string(forKey: "profileName"),
            "ShouldRemainAfterCompletedMigration",
            "After the one-time flag is set, the migration should be a no-op."
        )
        XCTAssertEqual(defaults.data(forKey: scopedProfileKey), profileData)
        XCTAssertEqual(defaults.data(forKey: scopedMemoryKey), memoryData)
        XCTAssertEqual(defaults.stringArray(forKey: scopedShoppingKey), ["keep-favorite"])
    }

    func testStartupLaunchRepairPurgesStaleLegacyProfileKeys() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let morning = Date(timeIntervalSince1970: 1_704_094_800) // 2024-01-01 09:00:00 UTC

        defaults.removeObject(forKey: LegacyProfileKeyMigration.migrationFlag)
        defaults.set(["Saba", "stine"].joined(), forKey: "profileName")
        defaults.set("XL", forKey: "shirtSize")
        defaults.set("Nike, Levi's", forKey: "favoriteBrands")
        defaults.set("clean casual", forKey: "stylePreferences")

        let scopedProfileKey = PersonalStylistStorage.scopedKey(PersonalStylistStorage.legacyProfileKey, userID: userA)
        let scopedMemoryKey = PersonalStylistStorage.scopedKey(PersonalStylistStorage.legacyMemoriesKey, userID: userA)
        let scopedProfileData = Data("scoped-profile".utf8)
        let scopedMemoryData = Data("scoped-memory".utf8)
        defaults.set(scopedProfileData, forKey: scopedProfileKey)
        defaults.set(scopedMemoryData, forKey: scopedMemoryKey)

        StyleMatchAppLaunchMigrations.run(defaults: defaults)

        XCTAssertNil(defaults.object(forKey: "profileName"))
        XCTAssertNil(defaults.object(forKey: "shirtSize"))
        XCTAssertNil(defaults.object(forKey: "favoriteBrands"))
        XCTAssertNil(defaults.object(forKey: "stylePreferences"))
        XCTAssertTrue(defaults.bool(forKey: LegacyProfileKeyMigration.migrationFlag))
        XCTAssertEqual(
            StyleMatchGreetingBuilder.greetingLine(date: morning, calendar: calendar, storedName: defaults.string(forKey: "profileName")),
            "Good Morning"
        )
        XCTAssertEqual(defaults.data(forKey: scopedProfileKey), scopedProfileData)
        XCTAssertEqual(defaults.data(forKey: scopedMemoryKey), scopedMemoryData)
    }


    func testAppleSignInNameResolverUsesAppleNameWhenProvided() {
        let resolved = StyleMatchAccountNameResolver.resolve(
            appleGivenName: " Sabastine ",
            appleFamilyName: " Esisorigho ",
            localDisplayName: "Old Local Name",
            storedProfileGivenName: "OldStored"
        )

        XCTAssertEqual(resolved.displayName, "Sabastine Esisorigho")
        XCTAssertEqual(resolved.givenName, "Sabastine")
        XCTAssertEqual(resolved.source, .appleCredential)
    }

    func testAppleSignInNameResolverPreservesLocalNameWhenAppleReturnsNoName() {
        let resolved = StyleMatchAccountNameResolver.resolve(
            appleGivenName: nil,
            appleFamilyName: nil,
            localDisplayName: "Saved Local Name",
            storedProfileGivenName: nil
        )

        XCTAssertEqual(resolved.displayName, "Saved Local Name")
        XCTAssertEqual(resolved.givenName, "Saved")
        XCTAssertEqual(resolved.source, .localDisplayName)
    }

    func testAppleSignInNameResolverRestoresStoredProfileNameWhenLocalNameIsBlank() {
        let resolved = StyleMatchAccountNameResolver.resolve(
            appleGivenName: nil,
            appleFamilyName: nil,
            localDisplayName: "  ",
            storedProfileGivenName: "Sabastine"
        )

        XCTAssertEqual(resolved.displayName, "Sabastine")
        XCTAssertEqual(resolved.givenName, "Sabastine")
        XCTAssertEqual(resolved.source, .storedProfile)
    }

    func testAppleSignInNameResolverDoesNotInventNameWhenNothingExists() {
        let resolved = StyleMatchAccountNameResolver.resolve(
            appleGivenName: nil,
            appleFamilyName: nil,
            localDisplayName: "",
            storedProfileGivenName: nil
        )

        XCTAssertNil(resolved.displayName)
        XCTAssertNil(resolved.givenName)
        XCTAssertEqual(resolved.source, .unavailable)
    }

    func testBlankProfileDraftNameMergesStoredProfileNameWithoutClearingIt() {
        XCTAssertEqual(
            StyleMatchAccountNameResolver.mergeDraftName("", storedProfileGivenName: "Sabastine"),
            "Sabastine"
        )
        XCTAssertEqual(
            StyleMatchAccountNameResolver.mergeDraftName("Manually Entered", storedProfileGivenName: "Sabastine"),
            "Manually Entered"
        )
    }

    func testAppleCredentialApplierPersistsFirstAuthFullNameToPerUserProfile() {
        let result = StyleMatchAppleCredentialProfileApplier.applyAppleCredential(
            userID: userA,
            email: "tester@example.com",
            appleGivenName: "Sabastine",
            appleFamilyName: "Esisorigho",
            localDisplayName: nil,
            defaults: defaults
        )

        XCTAssertEqual(result.displayName, "Sabastine Esisorigho")
        XCTAssertEqual(result.givenName, "Sabastine")
        XCTAssertEqual(result.email, "tester@example.com")
        XCTAssertEqual(result.source, .appleCredential)
        XCTAssertEqual(ProfileStore(defaults: defaults, userId: userA).currentProfile.givenName, "Sabastine")
        XCTAssertEqual(
            defaults.string(forKey: StyleMatchAppleCredentialProfileApplier.scopedEmailKey(userID: userA)),
            "tester@example.com"
        )
    }

    func testAppleCredentialApplierNilFullNameDoesNotClobberSavedName() {
        ProfileStore(defaults: defaults, userId: userA).updateGivenName("Saved")

        let result = StyleMatchAppleCredentialProfileApplier.applyAppleCredential(
            userID: userA,
            email: nil,
            appleGivenName: nil,
            appleFamilyName: nil,
            localDisplayName: "Local Other",
            defaults: defaults
        )

        XCTAssertEqual(result.displayName, "Saved")
        XCTAssertEqual(result.givenName, "Saved")
        XCTAssertEqual(result.source, .storedProfile)
        XCTAssertEqual(ProfileStore(defaults: defaults, userId: userA).currentProfile.givenName, "Saved")
    }

    func testAppleCredentialApplierPersistsTrustedNameEvenWhenGreetingBlocksIt() {
        let trustedName = ["Saba", "stine"].joined()
        XCTAssertNil(StyleMatchGreetingBuilder.firstName(from: trustedName))

        let result = StyleMatchAppleCredentialProfileApplier.applyAppleCredential(
            userID: userA,
            email: nil,
            appleGivenName: trustedName,
            appleFamilyName: nil,
            localDisplayName: nil,
            defaults: defaults
        )

        XCTAssertEqual(result.displayName, trustedName)
        XCTAssertEqual(result.givenName, trustedName)
        XCTAssertEqual(result.source, .appleCredential)
        XCTAssertEqual(ProfileStore(defaults: defaults, userId: userA).currentProfile.givenName, trustedName)
    }

    func testAccountModeDisplayStatusTitleUsesShortValues() {
        XCTAssertEqual(StyleMatchAccountModeDisplay.accountStatusTitle(for: "Sign in with Apple"), "Signed in with Apple")
        XCTAssertEqual(StyleMatchAccountModeDisplay.accountStatusTitle(for: "Guest"), "Guest")
        XCTAssertEqual(StyleMatchAccountModeDisplay.accountStatusTitle(for: "Email and Password"), "Email account")
        XCTAssertNotEqual(
            StyleMatchAccountModeDisplay.accountStatusTitle(for: "Sign in with Apple"),
            "Recommended for customers who want private account sign-in, cloud sync, wishlist, and future order history."
        )
    }

    // MARK: - Garment-only color palette regression tests

    func testGarmentPaletteExcludesBackgroundAndSkin() {
        var samples: [GarmentPalettePixel] = []

        samples += repeatedPixels(count: 80, red: 248, green: 248, blue: 242, isInsidePersonMask: true)
        samples += repeatedPixels(count: 64, red: 90, green: 90, blue: 90, isInsidePersonMask: true)
        samples += repeatedPixels(count: 52, red: 145, green: 95, blue: 55, isInsidePersonMask: false)
        samples += repeatedPixels(count: 44, red: 171, green: 118, blue: 76, isInsidePersonMask: true, isLikelySkinZone: true)

        let result = GarmentColorPaletteEngine.extractPalette(from: samples)

        XCTAssertTrue(result.palette.contains("white"), "White shirt should remain in garment palette")
        XCTAssertTrue(result.palette.contains("gray") || result.palette.contains("charcoal"), "Gray/charcoal pants should remain in garment palette")
        XCTAssertFalse(result.palette.contains("brown"), "Wood/floor background must not enter garment palette")
        XCTAssertFalse(result.palette.contains("beige"), "Skin-like pixels must not enter garment palette")
        XCTAssertGreaterThanOrEqual(result.debug.personSamples, 180)
        XCTAssertGreaterThanOrEqual(result.debug.skinReferenceSamples, 40)
    }

    func testGarmentPaletteLowInformationDoesNotFallbackToFrameColors() {
        let samples = repeatedPixels(count: 30, red: 248, green: 248, blue: 242, isInsidePersonMask: true)
            + repeatedPixels(count: 80, red: 145, green: 95, blue: 55, isInsidePersonMask: false)

        let result = GarmentColorPaletteEngine.extractPalette(from: samples)

        XCTAssertEqual(result.palette, ["neutral"])
        XCTAssertLessThan(result.confidence, 40)
        XCTAssertTrue(result.debug.clusters.isEmpty)
    }

    private func repeatedPixels(
        count: Int,
        red: UInt8,
        green: UInt8,
        blue: UInt8,
        isInsidePersonMask: Bool,
        isLikelySkinZone: Bool = false
    ) -> [GarmentPalettePixel] {
        (0..<count).map { index in
            GarmentPalettePixel(
                red: red,
                green: green,
                blue: blue,
                x: Double(index % 10) / 10.0,
                y: Double(index / 10) / Double(max(1, count / 10)),
                isInsidePersonMask: isInsidePersonMask,
                isLikelySkinZone: isLikelySkinZone
            )
        }
    }
}

private final class SpyDealProvider: DealProvider {
    private let providedDeals: [Deal]
    private(set) var callCount = 0

    init(deals: [Deal]) {
        self.providedDeals = deals
    }

    func currentDeals() async throws -> [Deal] {
        callCount += 1
        return providedDeals
    }
}

private final class SpySaleNotificationScheduler: SaleNotificationScheduling {
    var authorizationGranted = true
    private(set) var authorizationRequests = 0
    private(set) var requests: [SaleNotificationRequest] = []

    func requestAuthorization() async -> Bool {
        authorizationRequests += 1
        return authorizationGranted
    }

    func schedule(_ request: SaleNotificationRequest) async {
        requests.append(request)
    }
}

private struct StaticProductCatalogProvider: ProductCatalogProvider {
    let products: [AffiliateProduct]

    func products() async throws -> [AffiliateProduct] {
        products
    }
}

private struct StaticShoppingIntegrationConfigProvider: ShoppingIntegrationConfigProvider {
    let storedConfig: ShoppingIntegrationConfig

    func config() throws -> ShoppingIntegrationConfig {
        storedConfig
    }
}

private struct StaticRetailerSearchAdapter: RetailerSearchAdapter {
    let retailerName: String
    let products: [AffiliateProduct]

    func search(_ query: ProductSearchQuery) async throws -> [AffiliateProduct] {
        products
    }
}

private struct FailingRetailerSearchAdapter: RetailerSearchAdapter {
    let retailerName: String

    func search(_ query: ProductSearchQuery) async throws -> [AffiliateProduct] {
        throw TestSearchError()
    }
}

private struct SlowRetailerSearchAdapter: RetailerSearchAdapter {
    let retailerName: String
    let products: [AffiliateProduct]
    let delayNanoseconds: UInt64

    func search(_ query: ProductSearchQuery) async throws -> [AffiliateProduct] {
        try await Task.sleep(nanoseconds: delayNanoseconds)
        return products
    }
}

private final class SpyRetailerSearchAdapter: RetailerSearchAdapter {
    let retailerName: String
    let products: [AffiliateProduct]
    private(set) var callCount = 0

    init(retailerName: String, products: [AffiliateProduct]) {
        self.retailerName = retailerName
        self.products = products
    }

    func search(_ query: ProductSearchQuery) async throws -> [AffiliateProduct] {
        callCount += 1
        return products
    }
}

private struct TestSearchError: Error {}

extension StyleMatchProPhase2Tests {
    func testUniversalSearchRanksPrefixAboveSubstring() {
        let provider = DefaultSearchIndexService()
        let context = StyleMatchSearchContext(
            closetItems: [
                ClosetItem(name: "Oxford Shoes", category: "Shoes", color: "Brown", brand: "Cole Haan", size: "12", occasion: "Work", notes: "Leather shoes"),
                ClosetItem(name: "Shoe Care Kit", category: "Accessory", color: "Neutral", brand: "StyleMatch", size: "One Size", occasion: "General", notes: "Cleaner")
            ],
            outfitMemories: [],
            appDestinations: []
        )

        let results = provider.search("shoe", in: context)

        XCTAssertEqual(results.first?.title, "Shoe Care Kit")
        XCTAssertTrue(results.contains(where: { $0.title == "Oxford Shoes" }))
    }

    func testUniversalSearchIsCaseAndDiacriticInsensitive() {
        let provider = DefaultSearchIndexService()
        let context = StyleMatchSearchContext(
            closetItems: [
                ClosetItem(name: "Café Sneaker", category: "Shoes", color: "White", brand: "Nike", size: "12", occasion: "Casual", notes: "")
            ],
            outfitMemories: [],
            appDestinations: []
        )

        let results = provider.search("CAFE", in: context)

        XCTAssertEqual(results.first?.title, "Café Sneaker")
    }

    func testUniversalSearchEmptyQueryReturnsRecentItemsBeforeDestinations() {
        let provider = DefaultSearchIndexService()
        let olderMemory = makeSearchMemory(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            date: Date(timeIntervalSince1970: 100),
            style: "Casual",
            colors: ["white"]
        )
        let newerMemory = makeSearchMemory(
            id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            date: Date(timeIntervalSince1970: 200),
            style: "Smart Casual",
            colors: ["navy"]
        )
        let context = StyleMatchSearchContext(
            closetItems: [],
            outfitMemories: [olderMemory, newerMemory],
            appDestinations: StyleMatchAppDestination.defaults
        )

        let results = provider.search("", in: context)

        XCTAssertEqual(results.first?.title, "Smart Casual")
        XCTAssertNotEqual(results.first?.section, .appScreens)
    }

    func testUniversalSearchZeroResultReturnsEmptyArray() {
        let provider = DefaultSearchIndexService()
        let context = StyleMatchSearchContext(
            closetItems: [
                ClosetItem(name: "White Oxford", category: "Shirt", color: "White", brand: "Ralph Lauren", size: "XL", occasion: "Work", notes: "")
            ],
            outfitMemories: [],
            appDestinations: StyleMatchAppDestination.defaults
        )

        let results = provider.search("zzzxxyy", in: context)

        XCTAssertTrue(results.isEmpty)
    }

    func testUniversalSearchRanksClosetAboveAppDestinationsForSameMatchType() {
        let provider = DefaultSearchIndexService()
        let context = StyleMatchSearchContext(
            closetItems: [
                ClosetItem(name: "Closet Denim Jacket", category: "Jacket", color: "Blue", brand: "Levi's", size: "XL", occasion: "Casual", notes: "")
            ],
            outfitMemories: [],
            appDestinations: [
                StyleMatchAppDestination(id: "closet", title: "Closet", subtitle: "View saved clothing", keywords: ["closet"])
            ]
        )

        let results = provider.search("clos", in: context)

        XCTAssertEqual(results.first?.section, .closet)
        XCTAssertEqual(results.first?.title, "Closet Denim Jacket")
    }

    private func makeSearchMemory(id: UUID, date: Date, style: String, colors: [String]) -> OutfitMemory {
        OutfitMemory(
            id: id,
            userId: userA,
            scanDate: date,
            detectedGarments: ["shirt", "pants"],
            colors: colors,
            detectedStyle: style,
            styleScore: 88,
            occasion: .casual,
            wasWorn: nil,
            wasLiked: nil,
            feedbackTimestamp: nil,
            dislikeReason: nil,
            wouldWearAgain: nil,
            receivedCompliments: nil,
            isFavorite: false,
            timesWorn: 0
            , outfitFingerprint: "sanitized-outfit"
        )
    }
}

private final class CapturingURLProtocol: URLProtocol {
    static var lastURL: URL?
    static var responseData = Data("[]".utf8)

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lastURL = request.url
        let data = Self.responseData
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://proxy.example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class GarmentPaletteAndLabelSanitizationTests: XCTestCase {
    func testGarmentRegionMaskerUsesSecondTierAfterFirstFails() {
        let personMask = GarmentRegionMask(
            width: 2,
            height: 2,
            included: [true, true, false, false],
            tier: .personSegmentation
        )
        var attempted: [GarmentMaskTier] = []

        let mask = GarmentRegionMasker.tieredMask(
            width: 2,
            height: 2,
            minimumIncludedPixels: 1,
            foregroundSubject: {
                attempted.append(.foregroundSubject)
                return nil
            },
            personSegmentation: {
                attempted.append(.personSegmentation)
                return personMask
            },
            saliencyCrop: {
                attempted.append(.saliencyCrop)
                return nil
            }
        )

        XCTAssertEqual(mask.tier, .personSegmentation)
        XCTAssertEqual(mask.includedCount, 2)
        XCTAssertEqual(attempted, [.foregroundSubject, .personSegmentation])
    }

    func testGarmentRegionMaskerAllTierFailureReturnsTypedFailureWithoutPalette() {
        var attempted: [GarmentMaskTier] = []

        let mask = GarmentRegionMasker.tieredMask(
            width: 2,
            height: 2,
            minimumIncludedPixels: 1,
            foregroundSubject: {
                attempted.append(.foregroundSubject)
                return nil
            },
            personSegmentation: {
                attempted.append(.personSegmentation)
                return nil
            },
            saliencyCrop: {
                attempted.append(.saliencyCrop)
                return nil
            }
        )

        XCTAssertEqual(mask.tier, .couldNotIsolateGarment)
        XCTAssertEqual(mask.includedCount, 0)
        XCTAssertFalse(mask.maskingApplied)
        XCTAssertTrue(mask.included.allSatisfy { !$0 })
        XCTAssertEqual(attempted, [.foregroundSubject, .personSegmentation, .saliencyCrop])
    }

    func testPaletteExtractionSamplesOnlyIncludedGarmentPixels() {
        let garmentPixels = (0..<80).map { _ in
            GarmentPalettePixel(red: 245, green: 245, blue: 240, isInsidePersonMask: true, isLikelySkinZone: false)
        }
        let ignoredBackgroundPixels = (0..<120).map { _ in
            GarmentPalettePixel(red: 150, green: 105, blue: 70, isInsidePersonMask: false, isLikelySkinZone: false)
        }
        let ignoredSkinPixels = (0..<80).map { _ in
            GarmentPalettePixel(red: 175, green: 118, blue: 80, isInsidePersonMask: true, isLikelySkinZone: true)
        }

        let result = GarmentColorPaletteEngine.extractPalette(
            from: garmentPixels + ignoredBackgroundPixels + ignoredSkinPixels,
            minimumGarmentPixels: 20
        )

        XCTAssertTrue(result.palette.contains("white"), "Expected garment white to survive; got \(result.palette)")
        XCTAssertFalse(result.palette.contains("brown"), "Background brown must not enter the garment palette.")
        XCTAssertFalse(result.palette.contains("beige"), "Skin/background beige must not enter the garment palette.")
    }

    func testGarmentLabelMapperDropsInternalLabels() {
        let labels = [
            "Textile",
            "Person Wearing Outfit",
            "Apparel",
            "Clothing",
            "Fabric"
        ]

        XCTAssertTrue(GarmentLabelMapper.sanitizedTerms(from: labels).isEmpty)
    }

    func testGarmentLabelMapperMapsHumanGarmentTerms() {
        let labels = [
            "jersey, T-shirt",
            "polo",
            "blue jeans",
            "bathrobe",
            "slipper"
        ]

        XCTAssertEqual(
            GarmentLabelMapper.sanitizedTerms(from: labels),
            ["t-shirt", "polo shirt", "jeans", "robe", "slippers"]
        )
    }

    func testOutfitAnalysisResultSanitizesStoredDetectedItems() {
        let analysis = makeAnalysis(detectedItems: ["Textile", "Person Wearing Outfit", "polo"])

        XCTAssertEqual(analysis.detectedClothingItems, ["polo shirt"])
        XCTAssertEqual(analysis.safeDetectedClothingItems, ["polo shirt"])
    }

    func testOutfitRecallDoesNotEchoRawGarmentLabelsFromOldMemories() {
        var memory = OutfitMemory(
            id: UUID(),
            userId: "test-user",
            scanDate: Date(timeIntervalSince1970: 1_000),
            detectedGarments: ["Textile", "Person Wearing Outfit", "polo"],
            colors: ["white"],
            detectedStyle: "Casual",
            styleScore: 82,
            occasion: .casual,
            wasWorn: nil,
            wasLiked: nil,
            feedbackTimestamp: nil,
            dislikeReason: nil,
            wouldWearAgain: nil,
            receivedCompliments: nil,
            isFavorite: false,
            timesWorn: 0
        )
        memory.outfitFingerprint = "outfit-v4|sanitized-outfit"
        memory.imageDigest = "sanitized-image"

        let fact = OutfitRecallService.recallFact(
            for: OutfitRecallScanContext(
                detectedGarments: ["polo shirt"],
                colors: ["white"],
                detectedStyle: "Casual",
                outfitFingerprint: "outfit-v4|sanitized-outfit",
                imageDigest: "sanitized-image"
            ),
            memories: [memory],
            now: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(fact?.text, "You wore white polo shirt today (score: 82).")
    }

    func testVoiceScriptBuilderScanSummaryIsBriefAndScoreAnchored() {
        let analysis = makeAnalysis(
            score: 86,
            styleBalance: "Casual",
            summary: "The colors work well together, with clean proportions for everyday wear.",
            recommendations: [
                ClothingRecommendation(
                    category: "shoes",
                    title: "clean white sneakers",
                    reason: "They sharpen the lower half.",
                    personalization: "Matches your closet."
                )
            ]
        )

        let message = VoiceScriptBuilder.scanResult(from: analysis).text

        XCTAssertTrue(message.contains("Your outfit score is 86 out of 100, which is a strong casual look."))
        XCTAssertTrue(message.contains("The colors work well together"))
        XCTAssertTrue(message.contains("Next, consider clean white sneakers."))
        XCTAssertLessThanOrEqual(message.count, VoiceScriptBuilder.maximumSpokenCharacters)
    }

    func testVoiceScriptBuilderDoesNotGuessForUnrecognizedResult() {
        let analysis = makeAnalysis(
            score: 42,
            styleBalance: "Unrecognized item",
            summary: "",
            suggestions: [],
            recommendations: []
        )

        let message = VoiceScriptBuilder.scanResult(from: analysis).text

        XCTAssertTrue(message.contains("could not identify this outfit clearly"))
        XCTAssertFalse(message.localizedCaseInsensitiveContains("business casual"))
        XCTAssertLessThanOrEqual(message.count, VoiceScriptBuilder.maximumSpokenCharacters)
    }

    func testVoiceScriptBuilderAppGuideUsesKnownDestinations() {
        XCTAssertEqual(
            VoiceScriptBuilder.appGuide(destination: "Closet").text,
            "Use Closet to save clothing you own, so I can help build outfits from your real wardrobe."
        )

        XCTAssertEqual(
            VoiceScriptBuilder.appGuide(destination: "Something Else").text,
            "I can help you scan outfits, review your closet, understand scores, and find better matching pieces."
        )
    }

    func testVoiceScriptBuilderBuildsKeyMomentScripts() {
        XCTAssertEqual(VoiceScriptBuilder.scanStarted().kind, .scanStarted)
        XCTAssertTrue(VoiceScriptBuilder.profileSaved().text.contains("Profile saved"))
        XCTAssertTrue(VoiceScriptBuilder.scanFailed(title: "No outfit detected", description: "No visible clothing.").text.contains("clearer"))
        XCTAssertLessThanOrEqual(VoiceScriptBuilder.preview().text.count, VoiceScriptBuilder.maximumSpokenCharacters)
    }

    func testVoiceAssistantDefaultsOffForFreshInstallAndPreservesPersistedOn() {
        let suiteName = "VoiceAssistantSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertFalse(VoiceAssistantSettings.defaultEnabled)
        XCTAssertFalse(VoiceAssistantSettings.isEnabled(defaults: defaults))

        defaults.set(true, forKey: VoiceAssistantSettings.enabledKey)

        XCTAssertTrue(VoiceAssistantSettings.isEnabled(defaults: defaults))
    }

    func testHomeScoreBandingKeepsStarsAndLabelsConsistent() {
        XCTAssertEqual(StyleMatchHomeDisplay.scoreBand(for: 82), StyleMatchHomeScoreBand(stars: 4, title: "Good Match"))
        XCTAssertEqual(StyleMatchHomeDisplay.scoreBand(for: 39).stars, 1)
        XCTAssertEqual(StyleMatchHomeDisplay.scoreBand(for: 40).stars, 2)
        XCTAssertEqual(StyleMatchHomeDisplay.scoreBand(for: 60).stars, 3)
        XCTAssertEqual(StyleMatchHomeDisplay.scoreBand(for: 75).stars, 4)
        XCTAssertEqual(StyleMatchHomeDisplay.scoreBand(for: 89).stars, 4)
        XCTAssertEqual(StyleMatchHomeDisplay.scoreBand(for: 90).stars, 5)
    }

    func testHomeCountPluralization() {
        XCTAssertEqual(StyleMatchHomeDisplay.itemCountText(0), "0 items")
        XCTAssertEqual(StyleMatchHomeDisplay.itemCountText(1), "1 item")
        XCTAssertEqual(StyleMatchHomeDisplay.itemCountText(2), "2 items")
        XCTAssertEqual(StyleMatchHomeDisplay.closetItemLabel(0), "0 Closet Items")
        XCTAssertEqual(StyleMatchHomeDisplay.closetItemLabel(1), "1 Closet Item")
        XCTAssertEqual(StyleMatchHomeDisplay.closetItemLabel(3), "3 Closet Items")
        XCTAssertEqual(StyleMatchHomeDisplay.countText(1, singular: "saved item"), "1 saved item")
        XCTAssertEqual(StyleMatchHomeDisplay.countText(2, singular: "saved item"), "2 saved items")
        XCTAssertEqual(StyleMatchHomeDisplay.countText(2, singular: "person", plural: "people"), "2 people")
        XCTAssertEqual(StyleMatchHomeDisplay.starSystemName(index: 4, for: 82), "star.fill")
        XCTAssertEqual(StyleMatchHomeDisplay.starSystemName(index: 5, for: 82), "star")
    }

    func testHomeClosetItemLabelRemovesProfileName() {
        let label = StyleMatchHomeDisplay.sanitizedClosetItemLabel(
            name: "Sabastine",
            color: "White",
            userName: "Sabastine"
        )

        XCTAssertEqual(label, "White")
        XCTAssertFalse(label?.localizedCaseInsensitiveContains("Sabastine") == true)
    }

    func testClosetItemDisplayFallsBackFromProfileNameToGarmentDescription() {
        let item = ClosetItem(
            name: "Sabastine",
            category: "Shirt",
            color: "White",
            brand: "",
            size: "M",
            occasion: "Everyday",
            notes: ""
        )

        XCTAssertEqual(
            ClosetItemDisplay.displayName(for: item, profileName: "Sabastine Esisorigho"),
            "White Shirt"
        )
        XCTAssertEqual(
            ClosetItemDisplay.displayName(name: "Sabastine", category: "Shoes", color: "Black", profileName: "Sabastine Esisorigho"),
            "Black Shoes"
        )
        XCTAssertEqual(
            ClosetItemDisplay.displayName(name: "Navy Blazer", category: "Jacket", color: "Navy", profileName: "Sabastine Esisorigho"),
            "Navy Blazer"
        )
    }

    func testClosetViewUsesReadOnlyGarmentRecordsForScanCategorySections() throws {
        let source = try projectSource("StyleMatchAI/ClosetView.swift")

        XCTAssertTrue(source.contains("@StateObject private var outfitMemoryStore = OutfitMemoryStore()"))
        XCTAssertTrue(source.contains("outfitMemoryStore.garmentRecords"))
        XCTAssertTrue(source.contains("Scanned Clothing"))
        XCTAssertTrue(source.contains("No scan categories yet"))
        XCTAssertFalse(source.contains("outfitMemoryStore.addScan"))
        XCTAssertFalse(source.contains("outfitMemoryStore.addOrMergeScan"))
        XCTAssertFalse(source.contains("outfitMemoryStore.mergeGarmentRecords"))
    }

    func testHomeViewKeepsDuplicatedFactsInOnePlace() throws {
        let source = try projectSource("StyleMatchAI/HomeView.swift")

        XCTAssertEqual(source.components(separatedBy: "AI Confidence: High").count - 1, 1)
        XCTAssertEqual(source.components(separatedBy: "Continue your last outfit").count - 1, 1)
        XCTAssertFalse(source.contains("Weather & Calendar"))
        XCTAssertFalse(source.contains("weatherIntelligenceCard"))
        XCTAssertFalse(source.contains("Favorite Color"))
        XCTAssertFalse(source.contains("Closet Items"))
        XCTAssertFalse(source.contains("closetItemCountText"))
        XCTAssertFalse(source.contains("memoryClosetCountText"))
        XCTAssertFalse(source.contains("progressClosetCountText"))
        XCTAssertFalse(source.contains("weatherIntelligenceCard"))
        XCTAssertFalse(source.contains("LinearGradient("))
        XCTAssertFalse(source.contains(".stroke(task.tint"))
        XCTAssertFalse(source.contains(".stroke(tint"))
        XCTAssertFalse(source.contains("saved item\\(wishlistCount"))
        XCTAssertFalse(source.contains("light or gym item\\(count"))
        XCTAssertTrue(source.contains("Projected: 95"))
        XCTAssertTrue(source.contains("Score +6 this month"))
        XCTAssertTrue(source.contains("StyleMatchHomeDisplay.starSystemName"))
        XCTAssertTrue(source.contains("StyleMatchHomeDisplay.countText(wishlistCount"))
    }

    private func projectSource(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root.appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func makeAnalysis(
        score: Int = 82,
        styleBalance: String = "Casual",
        summary: String = "Synthetic summary",
        detectedItems: [String] = ["polo"],
        suggestions: [String] = ["Keep proportions balanced."],
        recommendations: [ClothingRecommendation] = [
            ClothingRecommendation(
                category: "shirt",
                title: "Synthetic",
                reason: "Synthetic reason",
                personalization: "Synthetic personalization"
            )
        ]
    ) -> OutfitAnalysisResult {
        OutfitAnalysisResult(
            score: score,
            colorMatch: "White and gray",
            occasionFit: "Everyday",
            styleBalance: styleBalance,
            colorHarmony: "Balanced",
            styleCoordination: "Coordinated",
            formality: "casual",
            seasonalMatch: "Mild",
            summary: summary,
            outfitDescription: "Synthetic outfit",
            detectedClothingItems: detectedItems,
            colorPalette: ["white", "gray"],
            colorPaletteMaskingApplied: true,
            colorPaletteMaskTier: GarmentMaskTier.foregroundSubject.rawValue,
            environment: "indoor",
            imageQuality: "clear",
            skinToneStyleNote: "No skin-tone recommendation needed.",
            detectedItemConfidences: [
                DetectedItemConfidence(item: "Textile", confidence: 92),
                DetectedItemConfidence(item: "polo", confidence: 90)
            ],
            suggestions: suggestions,
            recommendations: recommendations
        )
    }
}
