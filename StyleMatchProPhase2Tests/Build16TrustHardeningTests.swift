import XCTest

final class Build16TrustHardeningTests: XCTestCase {
    private func projectSource(_ relativePath: String, filePath: String = #filePath) throws -> String {
        let root = URL(fileURLWithPath: filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
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
              let unknownVerdict = source.range(
                of: "[ScanGate] VERDICT: unknown",
                range: unknownRegionPath.upperBound..<source.endIndex
              ) else {
            return XCTFail("Expected scene-qualified pre-reject and ordinary unknown region fallbacks.")
        }

        XCTAssertLessThan(rejectedPath.lowerBound, sceneGuard.lowerBound)
        XCTAssertLessThan(sceneGuard.lowerBound, preRejectRegionPath.lowerBound)
        XCTAssertLessThan(preRejectRegionPath.lowerBound, rejectedReturn.lowerBound)
        XCTAssertLessThan(rejectedReturn.lowerBound, unknownRegionPath.lowerBound)
        XCTAssertLessThan(unknownRegionPath.lowerBound, unknownVerdict.lowerBound)
        XCTAssertTrue(source.contains("[ScanGate] REGION-BEFORE-REJECT: attempting regions before rejectedLabel="))
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
        XCTAssertTrue(rejectedBlock.contains(
            "            }\n\n            #if DEBUG\n            print(\"[ScanGate] FAIL: rejectedLabel"
        ))
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

    func testRegionDiagnosticLoggingIsDebugOnly() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")
        var debugDepth = 0
        var regionLogCount = 0

        for line in source.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "#if DEBUG" {
                debugDepth += 1
            }
            if line.contains("print(\"[ScanGate] REGION") {
                regionLogCount += 1
                XCTAssertGreaterThan(debugDepth, 0, "Region diagnostics must be DEBUG-only: \(trimmed)")
            }
            if trimmed == "#endif" {
                debugDepth = max(0, debugDepth - 1)
            }
        }

        XCTAssertGreaterThan(regionLogCount, 0)
        XCTAssertTrue(source.contains("[ScanGate] REGION:"))
        XCTAssertTrue(source.contains("[ScanGate] REGION-VERDICT:"))
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
