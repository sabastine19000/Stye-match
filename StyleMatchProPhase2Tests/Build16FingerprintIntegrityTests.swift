import XCTest
@testable import StyleMatchPro

final class Build16FingerprintIntegrityTests: XCTestCase {
    private func projectSource(_ relativePath: String, filePath: String = #filePath) throws -> String {
        let root = URL(fileURLWithPath: filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    func testNormalizedDigestIsStableSHA256() {
        let bytes: [UInt8] = [10, 20, 30, 40, 50, 60]
        let first = ScanImageIdentity.sha256Hex(bytes: bytes)
        let second = ScanImageIdentity.sha256Hex(bytes: bytes)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.count, 64)
        XCTAssertNotEqual(first, ScanImageIdentity.sha256Hex(bytes: bytes + [70]))
    }

    func testDigestAndSemanticFingerprintMustBothMatchToRestore() {
        let fingerprint = "outfit-v4|person|shirt.pants|blue.black"

        XCTAssertTrue(ScanImageIdentity.isExactMatch(
            storedFingerprint: fingerprint,
            storedImageDigest: "digest-a",
            currentFingerprint: fingerprint,
            currentImageDigest: "digest-a"
        ))
        XCTAssertFalse(ScanImageIdentity.isExactMatch(
            storedFingerprint: fingerprint,
            storedImageDigest: "digest-a",
            currentFingerprint: fingerprint,
            currentImageDigest: "digest-b"
        ))
        XCTAssertFalse(ScanImageIdentity.isExactMatch(
            storedFingerprint: "outfit-v3-classifier-calibrated|person|shirt.pants",
            storedImageDigest: "digest-a",
            currentFingerprint: "outfit-v3-classifier-calibrated|person|shirt.pants",
            currentImageDigest: "digest-a"
        ))
        XCTAssertFalse(ScanImageIdentity.isExactMatch(
            storedFingerprint: fingerprint,
            storedImageDigest: nil,
            currentFingerprint: fingerprint,
            currentImageDigest: "digest-a"
        ))
    }

    func testSemanticOnlyMatchRunsFreshAnalysisAndLegacyDecodeIsOptional() throws {
        let scanSource = try projectSource("StyleMatchAI/ScanView.swift")

        XCTAssertTrue(scanSource.contains("let exactStoredScan = history[fingerprint].flatMap"))
        XCTAssertTrue(scanSource.contains("storedImageDigest: storedScan.imageDigest"))
        XCTAssertTrue(scanSource.contains("let storedInputs = exactStoredScan?.deterministicInputs"))
        XCTAssertFalse(scanSource.contains("let storedInputs = history[fingerprint]?.deterministicInputs"))
        XCTAssertTrue(scanSource.contains("imageDigest = try container.decodeIfPresent(String.self, forKey: .imageDigest)"))
    }

    func testStyleMemoryScoreCitationRequiresExactImageDigest() {
        let fingerprint = "outfit-v4|person|shirt|blue"
        var memory = OutfitMemory(
            id: UUID(),
            userId: "fingerprint-test-user",
            scanDate: Date(),
            detectedGarments: ["shirt"],
            colors: ["blue"],
            detectedStyle: "Casual",
            styleScore: 82,
            occasion: .casual,
            wasWorn: true,
            wasLiked: nil,
            feedbackTimestamp: nil,
            dislikeReason: nil,
            wouldWearAgain: nil,
            receivedCompliments: nil,
            isFavorite: false,
            timesWorn: 1,
            outfitFingerprint: fingerprint,
            imageDigest: "digest-a"
        )
        memory.outfitFingerprint = fingerprint

        let matching = OutfitRecallService.recallFact(
            for: OutfitRecallScanContext(
                detectedGarments: ["shirt"],
                colors: ["blue"],
                detectedStyle: "Casual",
                outfitFingerprint: fingerprint,
                imageDigest: "digest-a"
            ),
            memories: [memory]
        )
        let mismatching = OutfitRecallService.recallFact(
            for: OutfitRecallScanContext(
                detectedGarments: ["shirt"],
                colors: ["blue"],
                detectedStyle: "Casual",
                outfitFingerprint: fingerprint,
                imageDigest: "digest-b"
            ),
            memories: [memory]
        )

        XCTAssertTrue(matching?.text.contains("score: 82") == true)
        XCTAssertNil(mismatching)
    }

    func testDeterministicScorerContainsNoNondeterministicInput() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")
        guard let start = source.range(of: "private func calculateStyleScore(\n        validation:"),
              let end = source.range(
                of: "private func calculateStyleScore(detectedAttributes",
                range: start.upperBound..<source.endIndex
              ) else {
            return XCTFail("Expected deterministic score entry points.")
        }

        let scorer = String(source[start.lowerBound..<end.lowerBound])
        XCTAssertFalse(scorer.contains("random"))
        XCTAssertFalse(scorer.contains("UUID"))
        XCTAssertFalse(scorer.contains("Date()"))
        XCTAssertTrue(scorer.contains("calculateStyleScore(detectedAttributes: attributes)"))
    }

    func testScanImagePreprocessingNormalizesBeforeVisionAndDigest() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")
        guard let start = source.range(of: "func scanSizedImage(maxSide: CGFloat = 900) -> UIImage {"),
              let end = source.range(
                of: "func shareCardPreparedImage",
                range: start.upperBound..<source.endIndex
              ) else {
            return XCTFail("Expected scanSizedImage preprocessing helper.")
        }

        let scanSizedImage = String(source[start.lowerBound..<end.lowerBound])
        XCTAssertFalse(scanSizedImage.contains("return self"), "Scan preprocessing must not preserve device-specific image orientation or metadata.")
        XCTAssertTrue(scanSizedImage.contains("format.scale = 1"), "Scan preprocessing should render to stable pixel dimensions.")
        XCTAssertTrue(scanSizedImage.contains("draw(in: CGRect(origin: .zero, size: targetSize))"), "Scan preprocessing should render orientation into pixels before scoring.")

        guard let visionStart = source.range(of: "func fastVisionCGImage(maxSide: CGFloat = 720) -> CGImage? {"),
              let visionEnd = source.range(
                of: "private func sampledRGB",
                range: visionStart.upperBound..<source.endIndex
              ) else {
            return XCTFail("Expected fastVisionCGImage helper.")
        }

        let fastVisionCGImage = String(source[visionStart.lowerBound..<visionEnd.lowerBound])
        XCTAssertTrue(fastVisionCGImage.contains("scanSizedImage(maxSide: maxSide).cgImage"))
        XCTAssertFalse(fastVisionCGImage.contains("return cgImage"), "Vision should not receive an unnormalized raw CGImage for already-small device photos.")
    }

    func testCameraAndGalleryUseNormalizedScanImageBeforeAnalysis() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")
        XCTAssertTrue(source.contains("let scanImage = image.scanSizedImage()"))
        XCTAssertTrue(source.contains("let scanImage = uiImage.scanSizedImage()"))
        XCTAssertTrue(source.contains("selectedUIImage = scanImage"))
        XCTAssertTrue(source.contains("selectedImage = Image(uiImage: scanImage)"))
    }

    func testFlatLayAndWornScoringCalibrationRequiresEvidenceBackedFit() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")
        guard let signalStart = source.range(of: "private func fitAssessmentSignal(validation: ScanValidation"),
              let signalEnd = source.range(
                of: "private func detectedAccessories",
                range: signalStart.upperBound..<source.endIndex
              ) else {
            return XCTFail("Expected fit signal helper.")
        }

        XCTAssertEqual(StyleScoreCalibration.fitScore(for: "fit not evaluated from flat lay"), 13)
        XCTAssertEqual(StyleScoreCalibration.fitScore(for: "worn fit visible but unverified"), 13)
        XCTAssertEqual(StyleScoreCalibration.fitScore(for: "partial fit evidence"), 19)
        XCTAssertEqual(StyleScoreCalibration.fitScore(for: "tailored fit evidence"), 23)
        XCTAssertEqual(StyleScoreCalibration.fitScore(for: "verified excellent fit"), 25)
        XCTAssertLessThan(StyleScoreCalibration.fitScore(for: "fit not evaluated from flat lay"), 18)

        let fitSignal = String(source[signalStart.lowerBound..<signalEnd.lowerBound])
        XCTAssertTrue(fitSignal.contains("validation.isPersonScan"))
        XCTAssertTrue(fitSignal.contains("\"worn fit visible but unverified\""))
        XCTAssertTrue(fitSignal.contains("\"fit not evaluated from flat lay\""))
        XCTAssertFalse(fitSignal.contains("\"regular balanced fit\""))
        XCTAssertFalse(fitSignal.contains("text.contains(\"suit\") || text.contains(\"blazer\")"))
    }

    func testRawScoreNormalizationAndOccasionExclusion() {
        XCTAssertEqual(StyleScoreCalibration.normalizedScore(rawTotal: 59), 74)
        XCTAssertEqual(StyleScoreCalibration.normalizedScore(rawTotal: 67), 84)
        XCTAssertEqual(StyleScoreCalibration.normalizedScore(rawTotal: 80), 100)

        let breakdown = OutfitScoreBreakdown(
            colorHarmony: 20,
            patternBalance: 20,
            fitQuality: 13,
            occasionMatch: 20,
            accessoryUse: 6
        )

        XCTAssertEqual(breakdown.scoredRawTotal, 59)
        XCTAssertEqual(breakdown.normalizedScore, 74)
        XCTAssertTrue(breakdown.stylistChatSummary.contains("occasion is informational and excluded from scoring"))
    }

    func testVisibleBreakdownUsesRealPointsAndExplainsNormalization() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")

        XCTAssertTrue(source.contains("scorePointRow(title: \"Color Harmony\", points: breakdown.colorHarmony, maximum: 25)"))
        XCTAssertTrue(source.contains("scorePointRow(title: \"Fit Quality\", points: breakdown.fitQuality, maximum: 25)"))
        XCTAssertTrue(source.contains("normalizes to \\(normalizedScore(for: breakdown))/100"))
        XCTAssertTrue(source.contains("Occasion is informational and excluded from scoring."))
        XCTAssertFalse(source.contains("private struct StyleScoreBreakdown"))
        XCTAssertFalse(source.contains("styleProgressBar(title: \"Color Harmony\""))
        XCTAssertFalse(source.contains("styleProgressBar(title: \"Fit\""))
        XCTAssertFalse(source.contains("styleProgressBar(title: \"Accessories\""))
        XCTAssertFalse(source.contains("styleProgressBar(title: \"Weather\""))
    }

    func testAccessoryScoringIsGraduatedInsteadOfBinary() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")
        guard let start = source.range(of: "private func scoreAccessories(_ accessories: [String]) -> Int {"),
              let end = source.range(
                of: "private func isPerfectScoreEvidenceBacked",
                range: start.upperBound..<source.endIndex
              ) else {
            return XCTFail("Expected accessory scoring helper.")
        }

        let helper = String(source[start.lowerBound..<end.lowerBound])
        XCTAssertTrue(helper.contains("if count == 0 { return 6 }"))
        XCTAssertTrue(helper.contains("if count == 1 { return 8 }"))
        XCTAssertTrue(helper.contains("return 10"))
        XCTAssertFalse(helper.contains("accessories.isEmpty ? 5 : 10"))
    }

    func testPerfectScoreRequiresEvidenceBackedComponentsAndNoScanConfidenceInput() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")
        guard let scoreStart = source.range(of: "private func calculateStyleScore(detectedAttributes attributes: DetectedStyleAttributes)"),
              let scoreEnd = source.range(
                of: "private func fitAssessmentSignal(validation: ScanValidation",
                range: scoreStart.upperBound..<source.endIndex
              ) else {
            return XCTFail("Expected deterministic score component block.")
        }

        let scoreBlock = String(source[scoreStart.lowerBound..<scoreEnd.lowerBound])
        XCTAssertTrue(scoreBlock.contains("if total == 100 && !isPerfectScoreEvidenceBacked"))
        XCTAssertTrue(scoreBlock.contains("hasPositiveFitEvidence"))
        XCTAssertTrue(scoreBlock.contains("hasStrongAccessoryEvidence"))
        XCTAssertFalse(scoreBlock.contains("acceptedPerson"), "Person detection must not directly increase score.")
        XCTAssertFalse(scoreBlock.contains("qualityScore"), "Scan quality/confidence must stay separate from outfit quality.")
        XCTAssertFalse(scoreBlock.contains("confidenceLevel"), "Confidence must not enter score math.")
    }

    func testScanDebugUsesStableDigestPrefixAndVersion() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")

        XCTAssertTrue(source.contains("fingerprintVersion=\\(fingerprintVersion)"))
        XCTAssertTrue(source.contains("imageDigestPrefix=\\(imageDigestPrefix)"))
        XCTAssertFalse(source.contains("abs(fingerprint.hashValue % 100_000)"))
    }
}
