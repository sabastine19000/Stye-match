import XCTest
@testable import StyleMatchPro

final class ScanComparisonFoundationTests: XCTestCase {
    func testCompatibleComparisonOrdersScansAndProducesRealDeltas() throws {
        let newer = scan(80, date: 2, marker: ScanScoreModelVersion.current.rawValue)
        let older = scan(72, date: 1, marker: ScanScoreModelVersion.current.rawValue)
        let result = try XCTUnwrap(ScanComparisonBuilder.make(idA: "new", scanA: newer, idB: "old", scanB: older))
        XCTAssertEqual(result.olderID, "old")
        XCTAssertEqual(result.newerID, "new")
        XCTAssertEqual(result.overallDelta, 8)
        XCTAssertEqual(result.compatibility, .fullyCompatible)
        XCTAssertEqual(result.categoryDeltas.count, 4)
    }
    func testLegacyAndDifferentMarkersNeverFabricateCategoryCompatibility() throws {
        let legacy = scan(72, date: 1, marker: nil)
        let current = scan(80, date: 2, marker: ScanScoreModelVersion.current.rawValue)
        XCTAssertEqual(try XCTUnwrap(ScanComparisonBuilder.make(idA: "a", scanA: legacy, idB: "b", scanB: current)).compatibility, .limitedLegacyUnknown)
        XCTAssertEqual(ScanComparisonBuilder.compatibility("future_v2", ScanScoreModelVersion.current.rawValue), .limitedIncompatibleModel)
    }
    func testHistoryIsReferenceOnlyAndDeleteDoesNotAffectSourceIDs() throws {
        let suite = "compare.\(UUID().uuidString)"; let defaults = UserDefaults(suiteName: suite)!; defer { defaults.removePersistentDomain(forName: suite) }
        let store = ScanComparisonPersistenceAuthority(defaults: defaults, userID: "user")
        let record = StoredScanComparison(id: UUID(), schema: 1, olderScanID: "a", newerScanID: "b", createdAt: Date(), olderScore: 72, newerScore: 80, compatibility: .fullyCompatible, categoryDeltas: [], summary: "")
        try store.save(record, existingScanIDs: ["a", "b"]); XCTAssertEqual(store.comparisons.count, 1); store.delete(id: record.id); XCTAssertTrue(store.comparisons.isEmpty)
    }
    func testCompareContextExcludesStableIDs() throws {
        let result = try XCTUnwrap(ScanComparisonBuilder.make(idA: "private-a", scanA: scan(72, date: 1, marker: ScanScoreModelVersion.current.rawValue), idB: "private-b", scanB: scan(80, date: 2, marker: ScanScoreModelVersion.current.rawValue)))
        let snapshot = ScreenAwarenessSnapshot.scanComparison(.init(comparison: result), generation: 1)
        XCTAssertEqual(snapshot.kind, .scanComparison)
        XCTAssertFalse(snapshot.requestSummary.contains("private-a")); XCTAssertFalse(snapshot.requestSummary.contains("private-b"))
    }
    func testEqualLegacyComparisonRoutesWithTruthfulLimitedFacts() throws {
        let comparison = try XCTUnwrap(ScanComparisonBuilder.make(
            idA: "private-older",
            scanA: scan(80, date: 1, marker: nil),
            idB: "private-newer",
            scanB: scan(80, date: 2, marker: ScanScoreModelVersion.current.rawValue)
        ))
        let request = CompareStylistRouteRequest(comparison: comparison, occasion: "Date Night")
        var coordinator = StylistAwarenessCoordinator()
        let route = coordinator.publishScanComparison(request)

        XCTAssertEqual(comparison.overallDelta, 0)
        XCTAssertEqual(comparison.compatibility, .limitedLegacyUnknown)
        XCTAssertTrue(route.requestSummary.contains("80/100 → 80/100 (+0)"))
        XCTAssertTrue(route.requestSummary.contains("unknown scoring model"))
        XCTAssertTrue(route.requestSummary.contains("Occasion: Date Night."))
        XCTAssertFalse(route.requestSummary.contains("Category changes:"))
        XCTAssertFalse(route.requestSummary.contains("private-older"))
        XCTAssertFalse(route.requestSummary.contains("private-newer"))
    }
    private func scan(_ score: Int, date: TimeInterval, marker: String?) -> StoredOutfitScan { let analysis = OutfitAnalysisResult(score: score, scoreBreakdown: .init(colorHarmony: 20, patternBalance: 16, fitQuality: 16, occasionMatch: 0, accessoryUse: 4), colorMatch: "", occasionFit: "", styleBalance: "", colorHarmony: "", styleCoordination: "", formality: "", seasonalMatch: "", summary: "", outfitDescription: "", detectedClothingItems: [], colorPalette: [], environment: "", imageQuality: "", suggestions: [], recommendations: []); return .init(score: score, analysis: analysis, firstScannedAt: .init(timeIntervalSince1970: date), scanCount: 1, scoreModelVersion: marker) }
}
