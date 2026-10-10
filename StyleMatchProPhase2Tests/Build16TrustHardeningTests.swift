import CryptoKit
import XCTest

final class Build16TrustHardeningTests: XCTestCase {
    private func projectSource(_ relativePath: String, filePath: String = #filePath) throws -> String {
        let root = URL(fileURLWithPath: filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    func testScannerPanelDefersConstructionAcrossViewBoundaries() throws {
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
        XCTAssertTrue(panel.contains("ScanRenderSection { scannerPanelContent }"))
        XCTAssertTrue(source.contains("private var scanSourceControl: ScanSourceControl"))
        XCTAssertTrue(panel.contains("ScanRenderSection { AnyView(scanOccasionSelector) }"))
        XCTAssertTrue(panel.contains("scannerInsightTabsSection"))
        XCTAssertTrue(panel.contains("ScanRenderSection { AnyView(scannerInsightCard) }"))
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

    func testScanResultsUseTypedGroundingValidator() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")
        XCTAssertTrue(source.contains("private func groundedRecommendationResult(for result: OutfitAnalysisResult)"))
        XCTAssertTrue(source.contains("RecommendationGroundingValidator.validate(candidates, facts: facts)"))
    }

    func testQuickResultCardRendersOnlyGroundedRecommendations() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")
        guard let start = source.range(of: "private func quickResultCard("),
              let end = source.range(
                of: "private func groundedRecommendationResult(",
                range: start.upperBound..<source.endIndex
              ) else {
            return XCTFail("Expected the quick-result rendering boundary.")
        }

        let card = String(source[start.lowerBound..<end.lowerBound])
        XCTAssertTrue(card.contains("groundedRecommendationResult(for: result)"))
        XCTAssertTrue(card.contains("groundedRecommendationRow("))
        XCTAssertFalse(card.contains("result.suggestions"))
        XCTAssertFalse(card.contains("result.recommendations"))
    }

    func testScanAccessibilitySummaryUsesGroundedPresentations() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")
        guard let start = source.range(of: "private func scanResultAccessibilitySummary("),
              let end = source.range(
                of: "private func",
                range: start.upperBound..<source.endIndex
              ) else {
            return XCTFail("Expected the scan-result accessibility summary.")
        }

        let summary = String(source[start.lowerBound..<end.lowerBound])
        XCTAssertTrue(summary.contains("groundedRecommendationResult(for: result)"))
        XCTAssertFalse(summary.contains("result.suggestions"))
    }

    func testScanRecommendationRenderingHasHonestEmptyState() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")
        XCTAssertTrue(source.contains("RecommendationGroundingResult.honestEmptyState"))
        XCTAssertTrue(source.contains("if let emptyState = groundedResult.emptyStateMessage"))
    }

    func testScanRecommendationsDoNotUseLegacyViewSimilarLabel() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")
        XCTAssertFalse(source.contains("\"View Similar\""))
        XCTAssertTrue(source.contains("\"See examples\""))
        XCTAssertTrue(source.contains("\"Shop similar\""))
    }

    func testScanRecommendationsDoNotUseLegacyTapToShopLabel() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")
        XCTAssertFalse(source.contains("\"Tap to Shop\""))
    }

    func testScanResultsLabelStyleMatchConfidenceExplicitly() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")
        XCTAssertTrue(source.contains("\"Style match\""))
        XCTAssertTrue(source.contains("Text(\"Detected Style\")"))
        XCTAssertTrue(source.contains("detectedStyleTitle(for: result)"))
        XCTAssertTrue(source.contains("primary.customerVisibleConfidence"))
        XCTAssertTrue(source.contains("if let confidence = primary.customerVisibleConfidence"))
        XCTAssertTrue(source.contains("No measured style-match confidence is available for this scan."))
    }

    func testScanRecommendationsDoNotRetainUnsupportedCleanestPartCopy() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")
        XCTAssertFalse(source.localizedCaseInsensitiveContains("Tighten the cleanest part"))
    }

    func testDynamicRecommendationsAreEvidenceLimitedAndCapped() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")
        guard let start = source.range(of: "private func dynamicRecommendations("),
              let end = source.range(
                of: "var body: some View",
                range: start.upperBound..<source.endIndex
              ) else {
            return XCTFail("Expected the dynamic recommendation builder.")
        }

        let builder = String(source[start.lowerBound..<end.lowerBound])
        XCTAssertTrue(builder.contains("CanonicalGarmentReference"))
        XCTAssertTrue(builder.contains("CanonicalColorReference"))
        XCTAssertTrue(builder.contains("Array(recommendations.prefix(2))"))
        XCTAssertFalse(builder.contains("jacket"))
        XCTAssertFalse(builder.contains("chinos"))
        XCTAssertFalse(builder.contains("saved sizes"))
    }

    func testProfileFitAdviceCarriesSavedProfileSource() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")
        guard let start = source.range(of: "private func groundedRecommendationResult("),
              let end = source.range(
                of: "private func groundedRecommendationRow(",
                range: start.upperBound..<source.endIndex
              ) else {
            return XCTFail("Expected the grounded recommendation builder.")
        }

        let builder = String(source[start.lowerBound..<end.lowerBound])
        XCTAssertTrue(builder.contains("id: \"profile-fit\""))
        XCTAssertTrue(builder.contains("sources: [.savedProfile]"))
        XCTAssertTrue(builder.contains("content: .profileFitGuidance"))
    }

    func testWeatherAdviceRequiresReliableWeatherEvidence() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")
        guard let start = source.range(of: "private func groundedRecommendationResult("),
              let end = source.range(
                of: "private func groundedRecommendationRow(",
                range: start.upperBound..<source.endIndex
              ) else {
            return XCTFail("Expected the grounded recommendation builder.")
        }

        let builder = String(source[start.lowerBound..<end.lowerBound])
        XCTAssertTrue(builder.contains("weatherConfidenceScore() >= 90"))
        XCTAssertTrue(builder.contains("canGiveSpecificWeatherClothingAdvice"))
        XCTAssertTrue(builder.contains("sources: [.weather]"))
    }

    func testFitRecommendationDoesNotExposeExactSavedMeasurements() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")
        guard let start = source.range(of: "private func fitRecommendationNote("),
              let end = source.range(
                of: "private func",
                range: start.upperBound..<source.endIndex
              ) else {
            return XCTFail("Expected fit recommendation note.")
        }

        let note = String(source[start.lowerBound..<end.lowerBound])
        XCTAssertFalse(note.contains("shirtSize"))
        XCTAssertFalse(note.contains("pantsSize"))
        XCTAssertFalse(note.contains("shoeSize"))
        XCTAssertFalse(note.contains("waist"))
        XCTAssertFalse(note.contains("inseam"))
    }

    func testGroundedRenderingDoesNotInferAccessoriesFromScore() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")
        guard let start = source.range(of: "private func groundedRecommendationResult("),
              let end = source.range(
                of: "private func groundedRecommendationRow(",
                range: start.upperBound..<source.endIndex
              ) else {
            return XCTFail("Expected the grounded recommendation builder.")
        }

        let builder = String(source[start.lowerBound..<end.lowerBound])
        XCTAssertFalse(builder.contains("watch"))
        XCTAssertFalse(builder.contains("belt"))
        XCTAssertFalse(builder.contains("jewelry"))
        XCTAssertFalse(builder.contains("score >"))
        XCTAssertFalse(builder.contains("score <"))
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
        XCTAssertTrue(openPath.contains("selectedUIImage = scan.savedImage"))
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
        XCTAssertTrue(source.contains("My outfit scored \\(data.overallScore)/100 on KigoStylist. Here is how I can improve it."))
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
        XCTAssertTrue(shareSource.contains("Share Image opens the iPhone Share Sheet with the rendered card."))
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

        XCTAssertTrue(source.contains("Share Image opens the iPhone Share Sheet with the rendered card."))
        XCTAssertTrue(source.contains("Copy Share Link creates a secure KigoStylist link and copies it to your clipboard instead"))
        XCTAssertTrue(source.contains("it does not open the Share Sheet"))
        XCTAssertTrue(source.contains("Secure links expire after 30 days and can be revoked in Profile."))
        XCTAssertTrue(source.contains("Toggle(\"Branding on exported image\", isOn: $includeBranding)"))
        XCTAssertFalse(source.contains("KigoStylist does not upload it"))
    }

    func testPrivateLinkCopiesURLWithoutOpeningSecondShareSheet() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")

        XCTAssertTrue(source.contains("Label(isCreatingShareLink ? \"Creating Link\" : \"Copy Share Link\""))
        XCTAssertTrue(source.contains("UIPasteboard.general.url = response.url"))
        XCTAssertTrue(source.contains("isShowingLinkCopied = true"))
        XCTAssertTrue(source.contains(".alert(\"Link Copied\", isPresented: $isShowingLinkCopied)"))
        XCTAssertFalse(source.contains("isShowingLinkShareSheet"))
        XCTAssertFalse(source.contains("linkShareItems"))
        XCTAssertFalse(source.contains("linkActivityItems("))
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
        XCTAssertTrue(staleGuardPath.contains("selectedUIImage === previewImage"))
        XCTAssertTrue(staleGuardPath.contains("visionAnalysisUIImage === imageToAnalyze"))
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

    func testBoundedRegionEvidenceRunsBeforeCanAnalyzeUnknownRejection() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")
        guard let validationStart = source.range(of: "private func validateFashionImage("),
              let qualityGuard = source.range(
                of: "if let qualityIssue = detectedAttributes.qualityIssue",
                range: validationStart.upperBound..<source.endIndex
              ),
              let canAnalyzeGate = source.range(
                of: "if !detectedAttributes.canAnalyze {",
                range: qualityGuard.upperBound..<source.endIndex
              ),
              let regionFallback = source.range(
                of: "if let regionValidation = regionClothingValidation(",
                range: canAnalyzeGate.upperBound..<source.endIndex
              ),
              let unknownReturn = source.range(
                of: "return .unknown",
                range: regionFallback.upperBound..<source.endIndex
              ) else {
            return XCTFail("Expected quality-first bounded region fallback before the unknown canAnalyze exit.")
        }

        XCTAssertLessThan(qualityGuard.lowerBound, canAnalyzeGate.lowerBound)
        XCTAssertLessThan(canAnalyzeGate.lowerBound, regionFallback.lowerBound)
        XCTAssertLessThan(regionFallback.lowerBound, unknownReturn.lowerBound)

        let gateBlock = String(source[canAnalyzeGate.lowerBound..<unknownReturn.upperBound])
        XCTAssertTrue(gateBlock.contains("wholeImageLabels: detectedAttributes.labels"))
        XCTAssertTrue(gateBlock.contains("return regionValidation"))
        XCTAssertTrue(gateBlock.hasSuffix("return .unknown"))
    }

    func testOCRAndOutfitClassificationRemainAfterAcceptedValidationOnly() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")
        guard let acceptedValidation = source.range(of: "if validation.isAccepted {"),
              let textRecognition = source.range(
                of: "let textObservations = recognizeGarmentText(",
                range: acceptedValidation.upperBound..<source.endIndex
              ),
              let classification = source.range(
                of: "let outfitClassification = classifyOutfit(",
                range: textRecognition.upperBound..<source.endIndex
              ) else {
            return XCTFail("Expected accepted validation to gate OCR and outfit classification.")
        }

        XCTAssertLessThan(acceptedValidation.lowerBound, textRecognition.lowerBound)
        XCTAssertLessThan(textRecognition.lowerBound, classification.lowerBound)
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

    func testScanScrollViewportUsesRuntimeTopSafeArea() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")
        guard let bodyStart = source.range(of: "var body: some View {"),
              let fullScreenCover = source.range(
                of: ".fullScreenCover(isPresented: $isShowingCamera)",
                range: bodyStart.upperBound..<source.endIndex
              ) else {
            return XCTFail("Expected the primary Scan view body.")
        }

        let scanBody = String(source[bodyStart.lowerBound..<fullScreenCover.lowerBound])
        XCTAssertTrue(scanBody.contains(".safeAreaInset(edge: .top, spacing: 0)"))
        XCTAssertTrue(scanBody.contains("Color.clear.frame(height: 8)"))
        XCTAssertFalse(scanBody.contains(".statusBar(hidden: true)"))
        XCTAssertFalse(scanBody.contains(".ignoresSafeArea(edges: .top)"))
    }

    func testScoreDerivedStyleFallbackIsNeverPresentedAsMeasuredConfidence() throws {
        let scanSource = try projectSource("StyleMatchAI/ScanView.swift")
        let engineSource = try projectSource("StyleMatchAI/PersonalStylist/PersonalStylistEngines.swift")

        XCTAssertTrue(engineSource.contains("struct StyleClassificationAuthority"))
        XCTAssertTrue(engineSource.contains("var customerVisibleConfidence: Int?"))
        XCTAssertTrue(engineSource.contains("provenance.mayRenderAsConfidence ? rankingScore : nil"))
        XCTAssertTrue(scanSource.contains("StyleClassificationAuthority.rankedStyles("))
        XCTAssertTrue(scanSource.contains("if let confidence = primary.customerVisibleConfidence"))
        XCTAssertTrue(scanSource.contains("Text(\"Style match\")"))
        XCTAssertTrue(scanSource.contains("Text(\"\\(confidence)%\")"))
        XCTAssertTrue(scanSource.contains("if let confidence = ranking.customerVisibleConfidence"))
        XCTAssertTrue(scanSource.contains("styleConfidence: detectedStyleMeasuredConfidence(for: analysis)"))
        XCTAssertFalse(scanSource.contains("\"style_confidence\": 0-100"))
    }

    func testStyleScoreComputationRemainsByteForByteFrozen() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")
        guard let start = source.range(of: "    private func calculateStyleScore(\n"),
              let end = source.range(
                of: "    private func fitAssessmentSignal",
                range: start.upperBound..<source.endIndex
              ) else {
            return XCTFail("Expected the complete deterministic style-score computation boundary.")
        }

        let scoreSource = String(source[start.lowerBound..<end.lowerBound])
        let digest = SHA256.hash(data: Data(scoreSource.utf8))
            .map { String(format: "%02x", $0) }
            .joined()

        XCTAssertEqual(
            digest,
            "0d4ba98de5b7452cc495f1e7a34d5ba4e8805eddad1e4605b2ae44c2b7f8c972",
            "Style confidence honesty must never alter calculateStyleScore or its scoring helpers."
        )
    }

    func testNewerGallerySelectionRejectsOlderAsyncCompletionBeforeVisionOrClassification() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")
        let modelSource = try projectSource("StyleMatchAI/Models.swift")
        XCTAssertTrue(modelSource.contains("struct ScanImageSelectionCoordinator"))
        XCTAssertTrue(modelSource.contains("mutating func beginSelection() -> UUID"))
        XCTAssertTrue(modelSource.contains("func accepts(_ token: UUID) -> Bool"))
        XCTAssertTrue(source.contains("guard gallerySelectionCoordinator.accepts(selectionToken) else"))
        XCTAssertTrue(source.contains("sourceTokensMatch"))
        XCTAssertTrue(source.contains("visionAnalysisUIImage === imageToAnalyze"))
    }

    func testPersonSegmentationTorsoFallbackDoesNotRequireGenericApparelLabels() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")
        let modelSource = try projectSource("StyleMatchAI/Models.swift")

        XCTAssertTrue(source.contains("VNGeneratePersonSegmentationRequest()"))
        XCTAssertTrue(source.contains("private func defensiblePersonGarmentRegion"))
        XCTAssertTrue(source.contains("personGarmentRegion != nil"))
        XCTAssertTrue(source.contains("visible person clothing region"))
        XCTAssertTrue(source.contains("crop(cgImage, to: personGarmentRegion)"))
        XCTAssertTrue(modelSource.contains("enum PersonGarmentRegionEvidence"))
        XCTAssertTrue(modelSource.contains("torsoAndLowerBodyBox"))
    }

    func testQualityFailureStillPrecedesPersonSegmentationFallback() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")
        guard let validationStart = source.range(of: "private func validateFashionImage("),
              let attributesStart = source.range(
                of: "let detectedAttributes = detectGarmentAttributes(",
                range: validationStart.upperBound..<source.endIndex
              ),
              let qualityGuard = source.range(
                of: "if let qualityIssue = detectedAttributes.qualityIssue",
                range: attributesStart.upperBound..<source.endIndex
              ),
              let humanAcceptance = source.range(
                of: "if hasHuman {",
                range: qualityGuard.upperBound..<source.endIndex
              ) else {
            return XCTFail("Expected quality-first validation before human-region acceptance.")
        }

        XCTAssertLessThan(qualityGuard.lowerBound, humanAcceptance.lowerBound)
        XCTAssertTrue(source.contains("return .poorQuality(qualityIssue)"))
        XCTAssertTrue(source.contains("private func defensiblePersonGarmentRegion"))
    }
}
