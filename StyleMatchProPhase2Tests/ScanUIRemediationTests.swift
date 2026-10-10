import XCTest

final class ScanUIRemediationTests: XCTestCase {
    func testScanReceivesMeasuredBottomNavigationClearance() throws {
        let content = try projectSource("StyleMatchAI/ContentView.swift")
        let scan = try projectSource("StyleMatchAI/ScanView.swift")

        XCTAssertTrue(content.contains("bottomNavigationClearance: bottomNavigationClearance"))
        XCTAssertTrue(content.contains("bottomNavigationFrame.height + rootSafeAreaBottomInset + 12"))
        XCTAssertTrue(scan.contains("let bottomNavigationClearance: CGFloat"))
        XCTAssertTrue(scan.contains(".safeAreaInset(edge: .bottom, spacing: 0)"))
        XCTAssertTrue(scan.contains("Color.clear.frame(height: bottomNavigationClearance)"))
        XCTAssertTrue(scan.contains(".padding(.bottom, 24)"))
        XCTAssertFalse(scan.contains(".padding(.bottom, 28)"))
        XCTAssertTrue(scan.contains(".safeAreaInset(edge: .top, spacing: 0)"))
    }

    func testSelectedScanPhotoUsesCenteredAvailableWidth() throws {
        let scan = try projectSource("StyleMatchAI/ScanView.swift")

        XCTAssertTrue(scan.contains(".frame(maxWidth: .infinity, maxHeight: 250, alignment: .center)"))
        XCTAssertTrue(scan.contains(".padding(.horizontal, 16)"))
    }

    func testScoreScreenOffersOneCanonicalTypedStylistAction() throws {
        let scan = try projectSource("StyleMatchAI/ScanView.swift")

        XCTAssertTrue(scan.contains("Ask the Stylist About This Score"))
        XCTAssertFalse(scan.contains("Ask AI About This Score"))
        XCTAssertTrue(scan.contains("onOpenStylistScanConversation"))
        XCTAssertTrue(scan.contains("currentStylistScanHandoff?.issuingRouteToken()"))
        XCTAssertTrue(scan.contains("openScanAIAssist(for analysis: OutfitAnalysisResult)"))
    }

    func testScoreActionsSwitchFromGenerateToOneReanalysisAction() throws {
        let scan = try projectSource("StyleMatchAI/ScanView.swift")

        XCTAssertTrue(scan.contains("if selectedUIImage != nil && result == nil"))
        XCTAssertTrue(scan.contains("if result != nil {\n                        Button {\n                            analyze(forceReanalyze: true)"))
        XCTAssertEqual(scan.components(separatedBy: "analyze(forceReanalyze: true)").count - 1, 1)
    }

    func testSavedHistoryCardsResolveTheirCurrentStableRecordBeforeOpening() throws {
        let scan = try projectSource("StyleMatchAI/ScanView.swift")
        let start = try XCTUnwrap(scan.range(of: "private func openSavedScan("))
        let end = try XCTUnwrap(scan.range(of: "private func publishCurrentStylistScanHandoff", range: start.upperBound..<scan.endIndex))
        let openPath = String(scan[start.lowerBound..<end.lowerBound])

        XCTAssertTrue(openPath.contains("guard let scan = savedScan(for: scan.id) else"))
        XCTAssertTrue(openPath.contains("This saved scan could not be opened. Your other saved scans were not changed."))
        XCTAssertTrue(openPath.contains("result = scan.analysis"))
        XCTAssertTrue(openPath.contains("activeScanFingerprint = scan.id"))
        XCTAssertFalse(openPath.contains("analyze("))
        XCTAssertFalse(openPath.contains("saveScanHistory("))
    }

    func testSavedScanViewerUsesDurableAssetThenTruthfulLegacyFallback() throws {
        let scan = try projectSource("StyleMatchAI/ScanView.swift")

        XCTAssertTrue(scan.contains("savedImageAsset: savedImageAsset(for: image)"))
        XCTAssertTrue(scan.contains("selectedUIImage = scan.savedImage"))
        XCTAssertTrue(scan.contains("Text(\"Saved preview\")"))
        XCTAssertTrue(scan.contains("The original full-resolution photo was not retained for this earlier scan."))
        XCTAssertTrue(scan.contains("Image unavailable"))
        XCTAssertTrue(scan.contains("This scan’s analysis is still available, but no saved image could be restored."))
        XCTAssertTrue(scan.contains("SavedScanImageAssetStore().removeIfUnreferenced"))
    }

    func testScanHistoryUsesLazyRenderingAndClearSavedCountWithoutLegacyTwentyCap() throws {
        let scan = try projectSource("StyleMatchAI/ScanView.swift")

        XCTAssertTrue(scan.contains("LazyVStack(spacing: 14)"))
        XCTAssertTrue(scan.contains("Text(\"\\(scans.count) saved\")"))
        XCTAssertFalse(scan.contains("Text(\"\\(scans.count)/20\")"))
        XCTAssertTrue(scan.contains("SavedScanHistoryCapacity.maximumRecords"))
        XCTAssertTrue(scan.contains("Saved scan limit reached. You can keep up to 500 saved scans."))
    }

    func testDebugOnlyAcceptanceFixtureUsesProductionSavedScanPersistencePath() throws {
        let scan = try projectSource("StyleMatchAI/ScanView.swift")
        let start = try XCTUnwrap(scan.range(of: "#if DEBUG\n    /// Simulator-only acceptance seam."))
        let end = try XCTUnwrap(scan.range(of: "    private func analyze(", range: start.upperBound..<scan.endIndex))
        let hook = String(scan[start.lowerBound..<end.lowerBound])

        XCTAssertTrue(hook.contains("STYLEMATCH_ACCEPTANCE_FIXTURE"))
        XCTAssertTrue(hook.contains("savedScan("))
        XCTAssertTrue(hook.contains("savedScan(for: recordID)"))
        XCTAssertTrue(hook.contains("Build18033PersistenceAcceptanceFixture.image"))
        XCTAssertFalse(hook.contains("validateFashionImage("))
        XCTAssertTrue(scan.contains("#if DEBUG\nprivate enum Build18033PersistenceAcceptanceFixture"))
        XCTAssertFalse(scan.contains("#else\nprivate enum Build18033PersistenceAcceptanceFixture"))
    }

    func testSavedScanMutationsRetainAssetsAndRespectCapacity() throws {
        let scan = try projectSource("StyleMatchAI/ScanView.swift")
        let classificationStart = try XCTUnwrap(scan.range(of: "private func updateOutfitClassification("))
        let classificationEnd = try XCTUnwrap(scan.range(of: "private func formalityMismatch", range: classificationStart.upperBound..<scan.endIndex))
        let classification = String(scan[classificationStart.lowerBound..<classificationEnd.lowerBound])
        XCTAssertTrue(classification.contains("savedImageAsset: stored.savedImageAsset"))

        let duplicateStart = try XCTUnwrap(scan.range(of: "private func duplicateSavedScan("))
        let duplicateEnd = try XCTUnwrap(scan.range(of: "private func moveScanToCloset", range: duplicateStart.upperBound..<scan.endIndex))
        let duplicate = String(scan[duplicateStart.lowerBound..<duplicateEnd.lowerBound])
        XCTAssertTrue(duplicate.contains("SavedScanHistoryCapacity.canInsert"))
        XCTAssertTrue(duplicate.contains("Saved scan limit reached"))
        XCTAssertTrue(duplicate.contains("guard saveScanHistory(history) else { return }"))
    }

    func testScorePresentationAlignsStarsAndUsesNeutralStylistBranding() throws {
        let scan = try projectSource("StyleMatchAI/ScanView.swift")

        XCTAssertTrue(scan.contains("case 86...91:\n            return 4"))
        XCTAssertTrue(scan.contains("case 78...85:\n            return 3"))
        XCTAssertTrue(scan.contains("case 65...77:\n            return 2"))
        XCTAssertTrue(scan.contains("title: \"Stylist Analysis Ready\""))
        XCTAssertFalse(scan.contains("ChatGPT stylist analysis ready"))
        XCTAssertFalse(scan.contains("ChatGPT used the structured scan facts"))
        XCTAssertTrue(scan.contains("\"Stylist Analysis\""))
    }

    func testDetectedStyleRendersPrimaryValueOnceWithoutFabricatedConfidence() throws {
        let scan = try projectSource("StyleMatchAI/ScanView.swift")
        let grounding = try projectSource("StyleMatchAI/RecommendationGrounding.swift")

        XCTAssertTrue(scan.contains("Text(\"Detected Style\")"))
        XCTAssertFalse(scan.contains("Text(primary.customerVisibleConfidence == nil ? \"Detected style\" : \"Style match\")"))
        XCTAssertTrue(scan.contains("if rankings.count > 1"))
        XCTAssertTrue(scan.contains("hasMeasuredStyleConfidence: detectedStyleMeasuredConfidence(for: result) != nil"))
        XCTAssertTrue(grounding.contains("Possible style direction:"))
        XCTAssertTrue(grounding.contains("The photo did not provide measured style-match confidence."))
    }

    func testVoiceInterruptionExplainsExternalAudioSessionAndKeepsRetryPath() throws {
        let voice = try projectSource("StyleMatchAI/Services/VoiceStylistService.swift")
        let scan = try projectSource("StyleMatchAI/ScanView.swift")

        XCTAssertTrue(voice.contains("Another call or audio session interrupted playback. Once it ends, tap Listen to try again."))
        XCTAssertTrue(voice.contains("self.stop(withError:"))
        XCTAssertTrue(scan.contains("if let playbackError = voiceAssistant.playbackErrorMessage"))
        XCTAssertTrue(scan.contains("Listen to Score Summary"))
    }

    func testScanExplanationGuardrailsKeepLegacyV1NarrativeTruthful() throws {
        let scan = try projectSource("StyleMatchAI/ScanView.swift")

        XCTAssertTrue(scan.contains("No occasion was selected. Occasion did not affect this score."))
        XCTAssertTrue(scan.contains("Fit was not evaluated from this flat-lay photo."))
        XCTAssertTrue(scan.contains("A solid or no-pattern outfit can receive full pattern credit"))
        XCTAssertTrue(scan.contains("Under the current beta scoring model, this lowers the accessory component."))
        XCTAssertTrue(scan.contains("Accessories remain an optional styling choice and their absence does not mean the outfit is unsuitable."))
        XCTAssertTrue(scan.contains("Do not recommend buying accessories merely to recover points."))
    }

    func testScanUsesRenderOnlyEvidenceAwareExplanationPresenter() throws {
        let scan = try projectSource("StyleMatchAI/ScanView.swift")
        let grounding = try projectSource("StyleMatchAI/RecommendationGrounding.swift")

        XCTAssertTrue(scan.contains("ScanExplanationPresenter.items("))
        XCTAssertTrue(grounding.contains("enum ScanExplanationAvailability"))
        XCTAssertTrue(grounding.contains("struct ScanExplanationContext"))
        XCTAssertTrue(grounding.contains("Context unavailable"))
        XCTAssertTrue(grounding.contains("does not change the owned KigoStylist score"))
    }

    func testScanDoesNotPromotePlannedOccasionIntoGroundedSelectedOccasion() throws {
        let scan = try projectSource("StyleMatchAI/ScanView.swift")

        XCTAssertTrue(scan.contains("let resolvedOccasion = selectedOccasion?.isEmpty == false ? selectedOccasion : nil"))
        XCTAssertFalse(scan.contains("let resolvedOccasion = (selectedOccasion?.isEmpty == false ? selectedOccasion : nil)\n            ?? {"))
    }

    func testScoreExplanationStaysDistinctFromGroundedAdviceRows() throws {
        let scan = try projectSource("StyleMatchAI/ScanView.swift")
        let scoreExplanation = try XCTUnwrap(
            scan.range(of: "private func scoreExplanationBullets(for result: OutfitAnalysisResult)")
        )
        let categoryItems = try XCTUnwrap(
            scan.range(of: "private func analysisCategoryItems(for result: OutfitAnalysisResult)")
        )
        let body = String(scan[scoreExplanation.lowerBound..<categoryItems.lowerBound])

        XCTAssertFalse(body.contains("for recommendation in groundedRecommendationResult"))
    }

    private func projectSource(_ relativePath: String, filePath: String = #filePath) throws -> String {
        let testURL = URL(fileURLWithPath: filePath)
        let root = testURL.deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath))
    }
}
