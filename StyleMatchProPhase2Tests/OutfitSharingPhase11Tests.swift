import XCTest

final class OutfitSharingPhase11Tests: XCTestCase {
    private func projectSource(_ relativePath: String, filePath: String = #filePath) throws -> String {
        let root = URL(fileURLWithPath: filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func sourceSlice(
        in source: String,
        from startMarker: String,
        to endMarker: String
    ) throws -> String {
        guard let start = source.range(of: startMarker),
              let end = source.range(of: endMarker, range: start.upperBound..<source.endIndex) else {
            throw SourceSliceError.missingMarker
        }
        return String(source[start.lowerBound..<end.lowerBound])
    }

    func testShareCardCreatedWithAllScoreCategories() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")
        let builder = try sourceSlice(
            in: source,
            from: "private func makeOutfitSharePreview(\n        analysis:",
            to: "private func updateOccasion("
        )

        XCTAssertTrue(builder.contains("if let breakdown = analysis.scoreBreakdown"))
        XCTAssertTrue(builder.contains("OutfitShareCategoryScore(title: \"Color Harmony\""))
        XCTAssertTrue(builder.contains("OutfitShareCategoryScore(title: \"Pattern Balance\""))
        XCTAssertTrue(builder.contains("OutfitShareCategoryScore(title: \"Fit Quality\""))
        XCTAssertTrue(builder.contains("OutfitShareCategoryScore(title: \"Accessory Use\""))
        XCTAssertTrue(builder.contains("title: \"Score Calculation\""))
        XCTAssertFalse(builder.contains("OutfitShareCategoryScore(title: \"Occasion Match\""))
        XCTAssertTrue(builder.contains("categoryScores: availableCategoryScores"))
    }

    func testShareCardCreatedWithMissingCategoryScores() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")

        XCTAssertTrue(source.contains("let availableCategoryScores = categoryScores.filter"))
        XCTAssertTrue(source.contains("if configuration.includeCategoryScores, !data.categoryScores.isEmpty"))
        XCTAssertTrue(source.contains(".disabled(data.categoryScores.isEmpty)"))
        XCTAssertTrue(source.contains("Category scores are unavailable and will be omitted."))
    }

    func testShareCardCreatedWithoutPhoto() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")

        XCTAssertTrue(source.contains("let photo: UIImage?"))
        XCTAssertTrue(source.contains("if configuration.includePhoto, let photo = data.photo"))
        XCTAssertTrue(source.contains("Toggle(\"Outfit photo\", isOn: $includePhoto)"))
        XCTAssertTrue(source.contains(".disabled(data.photo == nil)"))
        XCTAssertTrue(source.contains("Photo unavailable. Your score-only card is ready."))
    }

    func testRecommendationsAreLimitedToThree() throws {
        let modelSource = try projectSource("StyleMatchAI/Models.swift")
        let viewSource = try projectSource("StyleMatchAI/ScanView.swift")

        XCTAssertTrue(modelSource.contains("Array(insights.prefix(3))"))
        XCTAssertTrue(viewSource.contains("data.suggestions.prefix(3)"))
    }

    func testPrivateProfileDataIsExcluded() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")
        let builder = try sourceSlice(
            in: source,
            from: "private func makeOutfitSharePreview(for result:",
            to: "private func updateOccasion("
        )

        let privateFields = [
            "email", "identityToken", "authorizationCode", "userIdentifier",
            "profileName", "shirtSize", "pantsSize", "shoeSize", "weatherLocationText",
            "latitude", "longitude", "systemPrompt", "API response", "debug"
        ]
        for field in privateFields {
            XCTAssertFalse(builder.localizedCaseInsensitiveContains(field), "Share builder must exclude \(field).")
        }
    }

    func testSavedScanUsesOriginalStoredScore() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")
        let savedBuilder = try sourceSlice(
            in: source,
            from: "private func makeOutfitSharePreview(for savedScan:",
            to: "private func makeOutfitSharePreview(\n        analysis:"
        )
        let openPath = try sourceSlice(
            in: source,
            from: "private func openSavedScan(",
            to: "private func updateSavedScanOccasion("
        )

        XCTAssertTrue(savedBuilder.contains("analysis: savedScan.analysis"))
        XCTAssertTrue(savedBuilder.contains("photo: savedScan.thumbnailImage"))
        XCTAssertTrue(savedBuilder.contains("scanDate: savedScan.firstScannedAt"))
        XCTAssertTrue(source.contains("overallScore: analysis.score"))
        XCTAssertTrue(openPath.contains("result = scan.analysis"))
    }

    func testSharingDoesNotTriggerReanalysis() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")
        let sharingPath = try sourceSlice(
            in: source,
            from: "private func makeOutfitSharePreview(for result:",
            to: "private func updateOccasion("
        )

        XCTAssertFalse(sharingPath.contains("analyze("))
        XCTAssertFalse(sharingPath.contains("calculateStyleScore"))
        XCTAssertFalse(sharingPath.contains("OpenAI"))
        XCTAssertFalse(sharingPath.contains("StylistClient"))
        XCTAssertFalse(sharingPath.contains("saveScanHistory"))
    }

    func testSquareAndPortraitFormatsRenderAtExpectedDimensions() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")

        XCTAssertTrue(source.contains("case square"))
        XCTAssertTrue(source.contains("case portrait"))
        XCTAssertTrue(source.contains("CGSize(width: 360, height: 360)"))
        XCTAssertTrue(source.contains("CGSize(width: 360, height: 640)"))
        XCTAssertTrue(source.contains("var renderScale: CGFloat { 3 }"))
        XCTAssertTrue(source.contains("let renderer = ImageRenderer(content: card)"))
        XCTAssertTrue(source.contains("renderer.proposedSize = ProposedViewSize(width: size.width, height: size.height)"))
    }

    func testLongDescriptionsUseBoundedAdaptiveLayout() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")

        XCTAssertTrue(source.contains(".lineLimit(format.isPortrait ? 3 : 1)"))
        XCTAssertTrue(source.contains(".minimumScaleFactor(0.78)"))
        XCTAssertTrue(source.contains("ScrollView {"))
        XCTAssertTrue(source.contains(".aspectRatio(cardFormat.aspectRatio, contentMode: .fit)"))
    }

    func testIPadShareSheetUsesPopoverAnchor() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")
        let activityView = try sourceSlice(
            in: source,
            from: "private struct OutfitShareActivityView:",
            to: "private extension Array where Element == ChatGPTStylistSection"
        )

        XCTAssertTrue(activityView.contains("if let popover = controller.popoverPresentationController"))
        XCTAssertTrue(activityView.contains("popover.sourceView = controller.view"))
        XCTAssertTrue(activityView.contains("popover.sourceRect = CGRect("))
        XCTAssertTrue(activityView.contains("popover.permittedArrowDirections = []"))
    }

    private enum SourceSliceError: Error {
        case missingMarker
    }
}
