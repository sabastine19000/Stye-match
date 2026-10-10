import XCTest

final class ScanAssistantCapabilityTests: XCTestCase {
    func testCompletedScoreExposesQuickScanHelpAction() throws {
        let scan = try scanSource()
        XCTAssertTrue(scan.contains("Label(\"Quick Scan Help\", systemImage: \"questionmark.bubble\")"))
    }

    func testQuickScanHelpUsesTheLegacySheetState() throws {
        let scan = try scanSource()
        XCTAssertTrue(scan.contains("openScanAIAssist(for: result)"))
        XCTAssertTrue(scan.contains(".sheet(isPresented: $isShowingScanAIAssist)"))
    }

    func testCompletedScoreExposesTypedStylistAction() throws {
        let scan = try scanSource()
        XCTAssertTrue(scan.contains("Label(\"Ask the Stylist About This Score\", systemImage: \"sparkles\")"))
    }

    func testTypedStylistActionRoutesThroughTheContentOwnedScanHandoff() throws {
        let scan = try scanSource()
        XCTAssertTrue(scan.contains("onOpenStylistScanConversation"))
        XCTAssertTrue(scan.contains("currentStylistScanHandoff?.issuingRouteToken()"))
        XCTAssertFalse(scan.contains("NavigationLink {\n                    let authoritativeScan"))
    }

    func testAssistantControlsHaveDistinctDestinations() throws {
        let scan = try scanSource()
        XCTAssertTrue(scan.contains("openScanAIAssist(for: result)"))
        XCTAssertTrue(scan.contains("onOpenStylistScanConversation"))
    }

    func testQuickScanHelpPreventsDuplicatePresentation() throws {
        let scan = try scanSource()
        XCTAssertTrue(scan.contains("guard !isShowingScanAIAssist else { return }"))
    }

    func testLegacySheetDismissalRestoresScanResult() throws {
        let scan = try scanSource()
        XCTAssertTrue(scan.contains("Button(\"Done\") {"))
        XCTAssertTrue(scan.contains("isShowingScanAIAssist = false"))
    }

    func testVoiceOverDistinguishesAssistantActions() throws {
        let scan = try scanSource()
        XCTAssertTrue(scan.contains("Opens quick help for this scan result."))
        XCTAssertTrue(scan.contains("Opens your Stylist conversation with details from this score."))
    }

    func testLegacyAndTypedRoutesKeepSeparateScanContextContracts() throws {
        let scan = try scanSource()
        XCTAssertTrue(scan.contains("scanAIAssistSheet(for: result)"))
        XCTAssertTrue(scan.contains("authoritativeStylistScanContext("))
    }

    func testClarifiedVoiceInterruptionCopyRemainsPresent() throws {
        let voice = try projectSource("StyleMatchAI/Services/VoiceStylistService.swift")
        XCTAssertTrue(voice.contains("Another call or audio session interrupted playback. Once it ends, tap Listen to try again."))
    }

    private func scanSource() throws -> String {
        try projectSource("StyleMatchAI/ScanView.swift")
    }

    private func projectSource(_ relativePath: String, filePath: String = #filePath) throws -> String {
        let testURL = URL(fileURLWithPath: filePath)
        let root = testURL.deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath))
    }
}
