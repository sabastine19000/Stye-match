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

    func testScanDebugUsesStableDigestPrefixAndVersion() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")

        XCTAssertTrue(source.contains("fingerprintVersion=\\(fingerprintVersion)"))
        XCTAssertTrue(source.contains("imageDigestPrefix=\\(imageDigestPrefix)"))
        XCTAssertFalse(source.contains("abs(fingerprint.hashValue % 100_000)"))
    }
}
