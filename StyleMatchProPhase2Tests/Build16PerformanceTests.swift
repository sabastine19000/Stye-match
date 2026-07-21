import XCTest
@testable import StyleMatchPro

final class Build16PerformanceTests: XCTestCase {
    func testDebugLogEmitterCannotWriteScanContentToStdout() throws {
        let engine = try source(named: "GarmentColorPaletteEngine.swift")
        let scan = try scanViewSource()

        XCTAssertFalse(engine.contains("print(message())"))
        XCTAssertFalse(engine.contains("fflush(stdout)"))
        XCTAssertFalse(engine.contains("StyleMatchDebugLogEmitter"))
        XCTAssertFalse(engine.contains("StyleMatchDebugLogEmitter.emit("))
        XCTAssertFalse(scan.contains("StyleMatchDebugLogEmitter.emit("))
        XCTAssertFalse(scan.contains("logScanDebug("))
        XCTAssertFalse(scan.contains("scanDebugLog("))
        XCTAssertFalse(scan.contains("[StyleMatch Scan Debug]"))
    }

    func testPaletteRuntimeKeepsStageTimingWithoutContentLogging() throws {
        let scan = try scanViewSource()

        XCTAssertTrue(scan.contains("let debugTiming = GarmentPaletteStageTiming()"))
        XCTAssertTrue(scan.contains("debugTiming: debugTiming"))
        XCTAssertFalse(scan.contains("[StyleMatch Color Debug]"))
        XCTAssertFalse(scan.contains("Thread.callStackSymbols.prefix(5)"))
    }

    func testSharedCatalogLoaderCoalescesConcurrentRequests() async throws {
        let provider = DelayedCountingCatalogProvider()
        let loader = SharedProductCatalogLoader(provider: provider, timeToLive: 60)

        async let first = loader.products()
        async let second = loader.products()
        async let third = loader.products()
        _ = try await (first, second, third)

        let callCount = await provider.callCount
        XCTAssertEqual(callCount, 1)
    }

    func testStructuredFactsReuseCompletedScanIdentityWithoutVisionValidation() throws {
        let source = try scanViewSource()
        guard let start = source.range(of: "private func structuredOutfitFacts("),
              let end = source.range(of: "private func inferredPatternFacts", range: start.upperBound..<source.endIndex) else {
            return XCTFail("Could not isolate structuredOutfitFacts")
        }
        let function = String(source[start.lowerBound..<end.lowerBound])
        XCTAssertTrue(function.contains("identity?.fingerprint"))
        XCTAssertFalse(function.contains("validateFashionImage("))
        XCTAssertFalse(function.contains("garmentColorDetection("))
    }

    func testSleepwearVisualSignalConsumesPrimaryPaletteWithoutExtractingAgain() throws {
        let source = try scanViewSource()
        guard let start = source.range(of: "func sleepwearVisualSignalScore(primaryPalette: [String])"),
              let end = source.range(of: "private func redPinkStripeSignalScore", range: start.upperBound..<source.endIndex) else {
            return XCTFail("Could not isolate sleepwearVisualSignalScore")
        }
        let function = String(source[start.lowerBound..<end.lowerBound])

        XCTAssertTrue(source.contains("primaryPalette: resolvedColorPalette"))
        XCTAssertTrue(function.contains("SleepwearPrimaryPaletteSignal.score(for: primaryPalette)"))
        XCTAssertFalse(function.contains("garmentColorPalette()"))
        XCTAssertFalse(function.contains("garmentColorDetection("))
    }

    func testPrimaryPaletteRetainsSleepwearClassificationSignal() {
        XCTAssertEqual(SleepwearPrimaryPaletteSignal.score(for: ["pink", "cream"]), 5)
        XCTAssertEqual(SleepwearPrimaryPaletteSignal.score(for: ["red", "white"]), 5)
        XCTAssertEqual(SleepwearPrimaryPaletteSignal.score(for: ["navy", "black"]), 0)
    }

    func testPaletteNamingReusesOneEvaluationForContributionsAndCalibration() throws {
        let engine = try source(named: "GarmentColorPaletteEngine.swift")
        guard let start = engine.range(of: "private static func weightedColorSummary("),
              let end = engine.range(of: "private static func lowConfidenceReason", range: start.upperBound..<engine.endIndex) else {
            return XCTFail("Could not isolate weightedColorSummary")
        }
        let function = String(engine[start.lowerBound..<end.lowerBound])

        XCTAssertTrue(function.contains("FashionColorCatalog.namingEvaluation("))
        XCTAssertTrue(function.contains("item.evaluation.contributions"))
        XCTAssertTrue(function.contains("$0.evaluation.calibrationDecision"))
        XCTAssertFalse(function.contains("FashionColorCatalog.calibrationDecision("))
    }

    func testCombinedNamingEvaluationMatchesLegacySeparateOutputsForFixture() {
        let fixtures: [(UInt8, UInt8, UInt8, Bool)] = [
            (25, 42, 78, true),
            (172, 208, 226, true),
            (150, 150, 150, false),
            (112, 72, 45, true)
        ]

        var separatePalette = [FashionColorCatalog.NameContribution]()
        var separateDecisions = [String]()
        var combinedPalette = [FashionColorCatalog.NameContribution]()
        var combinedDecisions = [String]()

        for (red, green, blue, hasSpatialEvidence) in fixtures {
            let combined = FashionColorCatalog.namingEvaluation(
                red: red,
                green: green,
                blue: blue,
                hasSpatialEvidence: hasSpatialEvidence
            )
            let separate = FashionColorCatalog.nameContributions(
                red: red,
                green: green,
                blue: blue,
                hasSpatialEvidence: hasSpatialEvidence
            )
            let separateDecision = FashionColorCatalog.calibrationDecision(red: red, green: green, blue: blue)
            separatePalette.append(contentsOf: separate)
            separateDecisions.append(contentsOf: separateDecision.map { [$0] } ?? [])
            combinedPalette.append(contentsOf: combined.contributions)
            combinedDecisions.append(contentsOf: combined.calibrationDecision.map { [$0] } ?? [])
        }

        let separateDebug = "palette=\(separatePalette); calibration=\(separateDecisions.sorted())"
        let combinedDebug = "palette=\(combinedPalette); calibration=\(combinedDecisions.sorted())"
        XCTAssertEqual(combinedPalette, separatePalette)
        XCTAssertEqual(combinedDecisions.sorted(), separateDecisions.sorted())
        XCTAssertEqual(combinedDebug, separateDebug)
    }

    func testTabsMountLazilyAndRemainTrackedAfterSelection() throws {
        let source = try source(named: "ContentView.swift")
        XCTAssertTrue(source.contains("@State private var mountedTabs: Set<AppTab> = [.home]"))
        XCTAssertTrue(source.contains("if mountedTabs.contains(.scan)"))
        XCTAssertTrue(source.contains("if mountedTabs.contains(.shop)"))
        XCTAssertTrue(source.contains("mountedTabs.insert(tab)"))
    }

    func testScanHistoryUsesDecodeCache() throws {
        let source = try scanViewSource()
        XCTAssertTrue(source.contains("scanHistoryCache.history(from: outfitScanHistoryData)"))
        XCTAssertTrue(source.contains("scanHistoryCache.replace(with: limitedHistory, encodedData: data)"))
    }

    private func scanViewSource() throws -> String {
        try source(named: "ScanView.swift")
    }

    private func source(named name: String) throws -> String {
        let testURL = URL(fileURLWithPath: #filePath)
        let root = testURL.deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("StyleMatchAI").appendingPathComponent(name))
    }
}

private actor DelayedCountingCatalogProvider: ProductCatalogProvider {
    private(set) var callCount = 0

    func products() async throws -> [AffiliateProduct] {
        callCount += 1
        try await Task.sleep(nanoseconds: 30_000_000)
        return []
    }
}
