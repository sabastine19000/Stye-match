import XCTest

final class Build16TrustHardeningTests: XCTestCase {
    private func projectSource(_ relativePath: String, filePath: String = #filePath) throws -> String {
        let root = URL(fileURLWithPath: filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    func testScannerPanelUsesExplicitTypeErasureAtConstructionBoundaries() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")
        guard let panelStart = source.range(of: "private var scannerPanel: AnyView"),
              let panelEnd = source.range(
                of: "private var scannerExampleCarousel:",
                range: panelStart.upperBound..<source.endIndex
              ) else {
            return XCTFail("Expected scannerPanel and its construction-boundary helpers.")
        }

        let panel = String(source[panelStart.lowerBound..<panelEnd.lowerBound])
        XCTAssertTrue(panel.contains("scannerPhotoSection"))
        XCTAssertTrue(panel.contains("scannerHeaderSection"))
        XCTAssertTrue(panel.contains("AnyView(scanSourceControl)"))
        XCTAssertTrue(panel.contains("AnyView(scanOccasionSelector)"))
        XCTAssertTrue(panel.contains("scannerInsightTabsSection"))
        XCTAssertTrue(panel.contains("AnyView(scannerInsightCard)"))
        XCTAssertTrue(panel.contains("private var scannerPhotoSection: AnyView"))
        XCTAssertTrue(panel.contains("private var scannerHeaderSection: AnyView"))
        XCTAssertTrue(panel.contains("private var scannerInsightTabsSection: AnyView"))

        guard let panelBodyEnd = panel.range(of: "private var scannerPhotoSection:") else {
            return XCTFail("Expected scanner photo section boundary.")
        }
        let panelBody = String(panel[..<panelBodyEnd.lowerBound])
        XCTAssertFalse(
            panelBody.contains("if let selectedImage"),
            "The image-state conditional must stay behind its erased section boundary."
        )
    }

    func testOutfitSharingOpensPrivacyPreviewBeforeSystemShareSheet() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")

        XCTAssertTrue(source.contains("outfitSharePreview = makeOutfitSharePreview(for: result)"))
        XCTAssertTrue(source.contains(".sheet(item: $outfitSharePreview)"))
        XCTAssertTrue(source.contains("OutfitSharePreviewScreen(data: preview"))
        XCTAssertTrue(source.contains("OutfitShareActivityView("))
        XCTAssertTrue(source.contains("activityItems: activityItems"))
        XCTAssertTrue(source.contains("@State private var includePhoto = false"))
        XCTAssertTrue(source.contains("@State private var includeOverallScore = true"))
        XCTAssertTrue(source.contains("@State private var includeCategoryScores = true"))
        XCTAssertTrue(source.contains("@State private var includeDescription = true"))
        XCTAssertTrue(source.contains("@State private var includeSuggestions = true"))
        XCTAssertTrue(source.contains("@State private var includeBranding = true"))
    }

    func testOutfitSharePreviewBuilderExcludesSensitiveSuggestionContext() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")
        guard let start = source.range(of: "private func makeOutfitSharePreview(for result:"),
              let end = source.range(
                of: "private func updateOccasion(",
                range: start.upperBound..<source.endIndex
              ) else {
            return XCTFail("Expected the outfit-share preview builder.")
        }

        let builder = String(source[start.lowerBound..<end.lowerBound])
        XCTAssertTrue(builder.contains("OutfitShareInsightBuilder.insights(from: analysis)"))
        XCTAssertFalse(builder.contains("result.suggestions"))
        XCTAssertFalse(builder.contains(".reason"))
        XCTAssertFalse(builder.contains(".personalization"))
        XCTAssertFalse(builder.contains("weatherLocationText"))
        XCTAssertFalse(builder.contains("shirtSize"))
        XCTAssertFalse(builder.contains("pantsSize"))
        XCTAssertFalse(builder.contains("shoeSize"))
        XCTAssertFalse(builder.contains("profileName"))
        XCTAssertFalse(builder.contains("analyze("))
        XCTAssertFalse(builder.contains("OpenAI"))
        XCTAssertFalse(builder.contains("StylistClient"))
    }

    func testSavedScanOpenAndShareUseStoredSnapshotWithoutRescoring() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")

        guard let openStart = source.range(of: "private func openSavedScan("),
              let openEnd = source.range(
                of: "private func updateSavedScanOccasion(",
                range: openStart.upperBound..<source.endIndex
              ),
              let shareStart = source.range(of: "private func makeOutfitSharePreview(for savedScan:"),
              let shareEnd = source.range(
                of: "private func makeOutfitSharePreview(\n        analysis:",
                range: shareStart.upperBound..<source.endIndex
              ) else {
            return XCTFail("Expected saved-scan open and share snapshot paths.")
        }

        let openPath = String(source[openStart.lowerBound..<openEnd.lowerBound])
        XCTAssertTrue(openPath.contains("result = scan.analysis"))
        XCTAssertTrue(openPath.contains("preparedAnalysis = scan.analysis"))
        XCTAssertTrue(openPath.contains("selectedUIImage = nil"))
        XCTAssertFalse(openPath.contains("analyze("))
        XCTAssertFalse(openPath.contains("calculateStyleScore"))
        XCTAssertFalse(openPath.contains("saveScanHistory"))

        let sharePath = String(source[shareStart.lowerBound..<shareEnd.lowerBound])
        XCTAssertTrue(sharePath.contains("analysis: savedScan.analysis"))
        XCTAssertTrue(sharePath.contains("photo: savedScan.thumbnailImage"))
        XCTAssertTrue(sharePath.contains("scanDate: savedScan.firstScannedAt"))
        XCTAssertFalse(sharePath.contains("analyze("))
        XCTAssertFalse(sharePath.contains("calculateStyleScore"))
    }

    func testEverySavedScanShareEntryUsesStoredPreviewFlow() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")

        XCTAssertFalse(source.contains("ShareLink(item: scan.shareText)"))
        XCTAssertFalse(source.contains("exportSavedScan("))
        XCTAssertGreaterThanOrEqual(
            source.components(separatedBy: "beginSharingSavedScan(scan)").count - 1,
            3
        )
        XCTAssertTrue(source.contains("outfitSharePreview = makeOutfitSharePreview(for: scan)"))
    }

    func testOutfitShareCardUsesTwoHighResolutionImageRendererFormats() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")

        XCTAssertTrue(source.contains("private enum OutfitShareCardFormat"))
        XCTAssertTrue(source.contains("case square"))
        XCTAssertTrue(source.contains("case portrait"))
        XCTAssertTrue(source.contains("CGSize(width: 360, height: 360)"))
        XCTAssertTrue(source.contains("CGSize(width: 360, height: 640)"))
        XCTAssertTrue(source.contains("var renderScale: CGFloat { 3 }"))
        XCTAssertTrue(source.contains("let renderer = ImageRenderer(content: card)"))
        XCTAssertTrue(source.contains("renderer.scale = cardFormat.renderScale"))
        XCTAssertTrue(source.contains("private enum OutfitShareCardAppearance"))
        XCTAssertTrue(source.contains("case light"))
        XCTAssertTrue(source.contains("case dark"))
        XCTAssertFalse(source.contains("UIGraphicsBeginImageContext"))
        XCTAssertFalse(source.contains("UIGraphicsGetImageFromCurrentImageContext"))
    }

    func testSystemShareReceivesRenderedCardInsteadOfRawOutfitPhoto() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")
        guard let start = source.range(of: "private var activityItems: [Any]"),
              let end = source.range(
                of: "private func renderShareCard()",
                range: start.upperBound..<source.endIndex
              ) else {
            return XCTFail("Expected the outfit-card activity payload.")
        }

        let activityPayload = String(source[start.lowerBound..<end.lowerBound])
        XCTAssertTrue(activityPayload.contains("renderedShareCard"))
        XCTAssertFalse(activityPayload.contains("data.photo"))
    }

    func testNativeShareUsesEditableOptionalCaptionAndConfiguredOfficialLink() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")

        XCTAssertTrue(source.contains("UIActivityViewController(activityItems: activityItems"))
        XCTAssertTrue(source.contains("Toggle(\"Include caption\", isOn: $includeCaption)"))
        XCTAssertTrue(source.contains("TextEditor(text: $captionText)"))
        XCTAssertTrue(source.contains("My outfit scored \\(data.overallScore)/100 on StyleMatch Pro. Here is how I can improve it."))
        XCTAssertTrue(source.contains("Bundle.main.object(forInfoDictionaryKey: \"STYLEMATCH_APP_STORE_URL\")"))
        XCTAssertTrue(source.contains("components.scheme?.lowercased() == \"https\""))
        XCTAssertTrue(source.contains("components.host?.lowercased() == \"apps.apple.com\""))
        XCTAssertTrue(source.contains("Toggle(\"Include App Store link\", isOn: $includeAppStoreLink)"))
        XCTAssertFalse(source.contains("https://apps.apple.com/"))
    }

    func testOutfitShareErrorsAreBoundedAndUserSafe() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")
        guard let shareStart = source.range(of: "private struct OutfitSharePreviewScreen:"),
              let shareEnd = source.range(
                of: "private extension Array where Element == ChatGPTStylistSection",
                range: shareStart.upperBound..<source.endIndex
              ) else {
            return XCTFail("Expected the complete outfit sharing implementation.")
        }
        let shareSource = String(source[shareStart.lowerBound..<shareEnd.lowerBound])

        XCTAssertTrue(shareSource.contains("Photo unavailable. Your score-only card is ready."))
        XCTAssertTrue(shareSource.contains("Category scores are unavailable and will be omitted."))
        XCTAssertTrue(shareSource.contains(".disabled(data.categoryScores.isEmpty)"))
        XCTAssertTrue(source.contains("photo?.shareCardPreparedImage()"))
        XCTAssertTrue(source.contains("maxPixelDimension: CGFloat = 1_600"))
        XCTAssertTrue(shareSource.contains("cardFormat.exportPixelCount <= 2_100_000"))
        XCTAssertTrue(shareSource.contains("return autoreleasepool"))
        XCTAssertTrue(shareSource.contains("UIApplication.didReceiveMemoryWarningNotification"))
        XCTAssertTrue(shareSource.contains("completionWithItemsHandler"))
        XCTAssertTrue(shareSource.contains("completion = completed ? .completed : .cancelled"))
        XCTAssertTrue(shareSource.contains("if completion == .failed"))
        XCTAssertTrue(shareSource.contains("We couldn’t prepare this outfit card. Please try again."))
        XCTAssertFalse(shareSource.contains("error.localizedDescription"))
    }

    func testOutfitSharingSupportsVoiceOverDynamicTypeAndAdaptivePresentation() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")

        XCTAssertTrue(source.contains(".accessibilityLabel(\"Share Outfit\")"))
        XCTAssertTrue(source.contains(".accessibilityLabel(scanResultAccessibilitySummary(result))"))
        XCTAssertTrue(source.contains("StyleMatchAccessibilityText.scanResultSummary("))
        XCTAssertTrue(source.contains(".accessibilityLabel(\"Share outfit card\")"))
        XCTAssertTrue(source.contains(".accessibilityLabel(\"Share card format\")"))
        XCTAssertTrue(source.contains(".accessibilityLabel(\"Share card appearance\")"))
        XCTAssertTrue(source.contains(".accessibilityLabel(cardAccessibilityLabel)"))
        XCTAssertTrue(source.contains(".accessibilityElement(children: .ignore)"))
        XCTAssertTrue(source.contains("@ScaledMetric(relativeTo: .body)"))
        XCTAssertTrue(source.contains(".environment(\\.dynamicTypeSize, dynamicTypeSize)"))
        XCTAssertTrue(source.contains(".aspectRatio(cardFormat.aspectRatio, contentMode: .fit)"))
        XCTAssertTrue(source.contains(".frame(maxWidth: 700"))
        XCTAssertTrue(source.contains("popover.sourceView = controller.view"))
        XCTAssertTrue(source.contains("popover.sourceRect = CGRect("))
        XCTAssertTrue(source.contains("popover.permittedArrowDirections = []"))
    }

    func testOutfitSharingRemainsLocalEphemeralAndDestinationPrivate() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")
        guard let shareStart = source.range(of: "private struct OutfitSharePreviewScreen:"),
              let shareEnd = source.range(
                of: "private extension Array where Element == ChatGPTStylistSection",
                range: shareStart.upperBound..<source.endIndex
              ) else {
            return XCTFail("Expected the complete outfit sharing implementation.")
        }

        let shareSource = String(source[shareStart.lowerBound..<shareEnd.lowerBound])
        XCTAssertTrue(shareSource.contains("let renderer = ImageRenderer(content: card)"))
        XCTAssertTrue(shareSource.contains("completionWithItemsHandler = { _, completed, _, error in"))
        XCTAssertTrue(shareSource.contains("Share Image is created on this device and nothing is uploaded."))
        XCTAssertGreaterThanOrEqual(
            shareSource.components(separatedBy: "renderedShareCard = nil").count - 1,
            4
        )
        XCTAssertFalse(shareSource.contains("URLSession"))
        XCTAssertFalse(shareSource.contains("FileManager"))
        XCTAssertFalse(shareSource.contains("write(to:"))
        XCTAssertFalse(shareSource.contains("pngData("))
        XCTAssertFalse(shareSource.contains("jpegData("))
        XCTAssertFalse(shareSource.contains("trackEvent"))
        XCTAssertFalse(shareSource.contains("selectedActivityType"))
    }

    func testSharePreviewDisclosureDistinguishesImageAndPrivateLinkModes() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")

        XCTAssertTrue(source.contains("Share Image is created on this device and nothing is uploaded."))
        XCTAssertTrue(source.contains("Share as Link securely stores your selected sections and photo, if included, for 30 days."))
        XCTAssertTrue(source.contains("Revoke links anytime in Profile."))
        XCTAssertTrue(source.contains("Toggle(\"Branding on exported image\", isOn: $includeBranding)"))
        XCTAssertFalse(source.contains("StyleMatch Pro does not upload it"))
    }

    func testScanAIUpgradeRequiresExactSessionAndFingerprint() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")

        XCTAssertTrue(source.contains("activeScanSessionID == scanSessionID"))
        XCTAssertTrue(source.contains("activeScanFingerprint == fingerprint"))
        XCTAssertFalse(source.contains("if result?.score == analysis.score"))
    }

    func testScanAIUpgradeCarriesIdentityThroughRequestApplyAndPersistence() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")

        XCTAssertTrue(source.contains("scanSessionID: scanSessionID"))
        XCTAssertTrue(source.contains("fingerprint: fingerprint"))
        XCTAssertTrue(source.contains("saveChatGPTUpgrade(updatedAnalysis, fingerprint: fingerprint)"))
        XCTAssertTrue(source.contains("private func saveChatGPTUpgrade(_ analysis: OutfitAnalysisResult, fingerprint: String)"))
    }

    func testReplacingOrRemovingScanInvalidatesOutstandingAIResponse() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")

        XCTAssertTrue(source.contains("private func invalidateActiveScanSession()"))
        XCTAssertTrue(source.contains("activeScanSessionID = nil"))
        XCTAssertTrue(source.contains("activeScanFingerprint = nil"))
        XCTAssertGreaterThanOrEqual(source.components(separatedBy: "invalidateActiveScanSession()").count - 1, 6)
    }

    func testStaleValidationCallbackDoesNotResetAnalyzingState() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")
        guard let guardStart = source.range(of: "guard activeScanSessionID == scanSessionID,"),
              let nextGuard = source.range(
                of: "guard validation.isAccepted else",
                range: guardStart.upperBound..<source.endIndex
              ) else {
            return XCTFail("Expected the validation callback session guard.")
        }

        let staleGuardPath = String(source[guardStart.lowerBound..<nextGuard.lowerBound])
        XCTAssertTrue(staleGuardPath.contains("selectedUIImage === imageToAnalyze"))
        XCTAssertTrue(staleGuardPath.contains("return"))
        XCTAssertFalse(staleGuardPath.contains("isAnalyzing = false"))
    }

    func testRegionClassificationRunsAtFormerUnknownExitAndBeforeSceneQualifiedRejection() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")
        guard let rejectedPath = source.range(of: "if let rejectedLabel"),
              let sceneGuard = source.range(
                of: "if flatLayRegionScene(in: labels) != nil",
                range: rejectedPath.upperBound..<source.endIndex
              ),
              let preRejectRegionPath = source.range(
                of: "if let regionValidation = regionClothingValidation(",
                range: sceneGuard.upperBound..<source.endIndex
              ),
              let rejectedReturn = source.range(
                of: "return .rejected(rejectedLabel)",
                range: preRejectRegionPath.upperBound..<source.endIndex
              ),
              let unknownRegionPath = source.range(
                of: "if let regionValidation = regionClothingValidation(",
                range: rejectedReturn.upperBound..<source.endIndex
              ),
              let unknownReturn = source.range(
                of: "return .unknown",
                range: unknownRegionPath.upperBound..<source.endIndex
              ) else {
            return XCTFail("Expected scene-qualified pre-reject and ordinary unknown region fallbacks.")
        }

        XCTAssertLessThan(rejectedPath.lowerBound, sceneGuard.lowerBound)
        XCTAssertLessThan(sceneGuard.lowerBound, preRejectRegionPath.lowerBound)
        XCTAssertLessThan(preRejectRegionPath.lowerBound, rejectedReturn.lowerBound)
        XCTAssertLessThan(rejectedReturn.lowerBound, unknownRegionPath.lowerBound)
        XCTAssertLessThan(unknownRegionPath.lowerBound, unknownReturn.lowerBound)
        XCTAssertFalse(source.contains("[ScanGate] REGION-BEFORE-REJECT: attempting regions before rejectedLabel="))
    }

    func testRejectedLabelWithoutEligibleSceneStillRejectsWithoutRegionAttempt() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")
        guard let rejectedPath = source.range(of: "if let rejectedLabel"),
              let rejectedReturn = source.range(
                of: "return .rejected(rejectedLabel)",
                range: rejectedPath.upperBound..<source.endIndex
              ) else {
            return XCTFail("Expected rejected-label branch.")
        }

        let rejectedBlock = String(source[rejectedPath.lowerBound..<rejectedReturn.upperBound])
        XCTAssertTrue(rejectedBlock.contains("if flatLayRegionScene(in: labels) != nil"))
        XCTAssertTrue(rejectedBlock.contains("if let regionValidation = regionClothingValidation("))
        XCTAssertFalse(rejectedBlock.contains("print("))
        XCTAssertTrue(rejectedBlock.hasSuffix("return .rejected(rejectedLabel)"))
    }

    func testRegionClassificationUsesSharedTermsAndSceneThresholds() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")
        guard let functionStart = source.range(of: "private func regionClothingValidation("),
              let nextFunction = source.range(
                of: "private func scanRegionCandidates(",
                range: functionStart.upperBound..<source.endIndex
              ) else {
            return XCTFail("Expected region clothing validation helper.")
        }

        let function = String(source[functionStart.lowerBound..<nextFunction.lowerBound])
        XCTAssertTrue(function.contains("clothingTerms.contains"))
        XCTAssertTrue(function.contains("scene == nil ? 0.30 : 0.24"))
        XCTAssertTrue(function.contains("strongestMatch.label.confidence >= acceptanceThreshold"))
    }

    func testRegionDiagnosticLoggingIsRemoved() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")
        XCTAssertFalse(source.contains("[ScanGate] REGION:"))
        XCTAssertFalse(source.contains("[ScanGate] REGION-VERDICT:"))
        XCTAssertTrue(source.contains("private func regionClothingValidation("))
    }

    func testRegionGenerationUsesObjectnessAndSixCandidateCap() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")

        XCTAssertTrue(source.contains("VNGenerateObjectnessBasedSaliencyImageRequest()"))
        XCTAssertTrue(source.contains("source: \"objectness\""))
        XCTAssertTrue(source.contains("private func scanRegionCandidates(in cgImage: CGImage, limit: Int = 6)"))
    }

    func testOversizedRegionSubdivisionUsesSixtyPercentAreaRule() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")
        let paletteSource = try projectSource("StyleMatchAI/GarmentColorPaletteEngine.swift")

        XCTAssertTrue(source.contains("oversizedAreaThreshold: 0.60"))
        XCTAssertTrue(source.contains("source: \"subdivided\""))
        XCTAssertTrue(paletteSource.contains("let pixelWidth = box.width * imageSize.width"))
        XCTAssertTrue(paletteSource.contains("let pixelHeight = box.height * imageSize.height"))
        XCTAssertTrue(paletteSource.contains("if pixelWidth >= pixelHeight"))
    }

    func testRegionCandidateDeduplicationUsesPointEightIoUAndKeepsSmaller() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")

        XCTAssertTrue(source.contains("overlapThreshold: CGFloat = 0.8"))
        XCTAssertTrue(source.contains("regionIntersectionOverUnion("))
        XCTAssertTrue(source.contains("if candidateArea < existingArea"))
        XCTAssertTrue(source.contains("result[duplicateIndex] = candidate"))
    }
}
