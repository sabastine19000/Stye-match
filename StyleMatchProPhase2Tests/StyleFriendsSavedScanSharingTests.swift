import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import StyleMatchPro

@MainActor
final class StyleFriendsSavedScanSharingTests: XCTestCase {
    func testLegacyThumbnailCanBeSharedWithoutRewritingHistoryOrAssets() throws {
        let f = try Fixture()
        defer { f.cleanup() }
        try f.save(["legacy": f.scan(thumbnail: f.png)])
        let original = f.historyBytes
        let choices = try f.authority.choices(for: .scan)
        XCTAssertEqual(choices.count, 1)
        XCTAssertNotNil(choices.first?.imagePreview)
        XCTAssertEqual(choices.first?.score, 82)
        XCTAssertEqual(f.historyBytes, original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.root.path))
    }

    func testLegacyRecordDoesNotHideAnotherValidScore() throws {
        let f = try Fixture()
        defer { f.cleanup() }
        try f.save(["older": f.scan(analysisScore: nil), "valid": f.scan()])
        let original = f.historyBytes
        XCTAssertEqual(try f.authority.choices(for: .score).count, 2)
        XCTAssertEqual(f.historyBytes, original)
    }
}

@MainActor
private final class Fixture {
    let suite = "StyleFriendsSavedShareTests-\(UUID().uuidString)"
    let defaults: UserDefaults
    let root: URL
    let images: SavedScanImageAssetStore
    let authority: StyleFriendsDMShareEligibilityAuthority
    let png: Data
    var historyBytes: Data? { defaults.data(forKey: "outfitScanHistoryData") }

    init() throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        images = SavedScanImageAssetStore(rootDirectory: root, userID: "test-owner")
        authority = StyleFriendsDMShareEligibilityAuthority(
            scans: SavedScanPersistenceAuthority(defaults: defaults, images: images)
        )
        let context = try XCTUnwrap(CGContext(data: nil, width: 2, height: 2,
            bitsPerComponent: 8, bytesPerRow: 8, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        png = data as Data
    }
    func save(_ records: [String: StoredOutfitScan]) throws {
        defaults.set(try JSONEncoder().encode(records), forKey: "outfitScanHistoryData")
    }

    func scan(score: Int = 82, analysisScore: Int? = 82, thumbnail: Data? = nil,
              asset: SavedScanImageAsset? = nil) -> StoredOutfitScan {
        let analysis = analysisScore.map { value in
            OutfitAnalysisResult(score: value, colorMatch: "Coordinated", occasionFit: "Work",
                styleBalance: "Balanced", colorHarmony: "Strong", styleCoordination: "Clean",
                formality: "Casual", seasonalMatch: "All season", summary: "Saved analysis",
                outfitDescription: "Shirt and trousers", detectedClothingItems: ["shirt", "trousers"],
                colorPalette: ["navy"], environment: "indoor", imageQuality: "clear",
                suggestions: [], recommendations: [])
        }
        return StoredOutfitScan(score: score, analysis: analysis,
            firstScannedAt: Date(timeIntervalSince1970: 1_700_000_000), scanCount: 3,
            thumbnailData: thumbnail, customTitle: "Saved work outfit", occasion: .work,
            savedImageAsset: asset)
    }

    func cleanup() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }
}

extension StyleFriendsSavedScanSharingTests {
    func testMissingPhotoStillAllowsExactLegacyScoreWithoutMutation() throws {
        let f = try Fixture(); defer { f.cleanup() }
        try f.save(["legacy": f.scan(score: 74, analysisScore: nil)])
        let original = f.historyBytes
        XCTAssertThrowsError(try f.authority.choices(for: .scan)) { error in
            XCTAssertEqual(error as? StyleFriendsDMShareEligibilityAuthority.AvailabilityError, .photosUnavailable)
        }
        let choice = try XCTUnwrap(try f.authority.choices(for: .score).first)
        XCTAssertEqual(choice.score, 74)
        XCTAssertNil(choice.imagePreview)
        XCTAssertEqual(f.authority.consumeSnapshot(for: choice.id, kind: .score)?.score, 74)
        XCTAssertEqual(f.historyBytes, original)
    }

    func testMalformedHistoryIsNotReportedAsEmptyAndIsNotOverwritten() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let original = Data("not-json".utf8)
        f.defaults.set(original, forKey: "outfitScanHistoryData")
        XCTAssertThrowsError(try f.authority.choices(for: .score)) { error in
            XCTAssertEqual(error as? StyleFriendsDMShareEligibilityAuthority.AvailabilityError, .historyUnavailable)
        }
        XCTAssertEqual(f.historyBytes, original)
    }
}

extension StyleFriendsSavedScanSharingTests {
    func testEmptyHistoryAndInvalidScoresHaveDistinctErrors() throws {
        let f = try Fixture(); defer { f.cleanup() }
        XCTAssertThrowsError(try f.authority.choices(for: .score)) { error in
            XCTAssertEqual(error as? StyleFriendsDMShareEligibilityAuthority.AvailabilityError, .noSavedScans)
        }
        try f.save(["bad": f.scan(score: 101, analysisScore: nil), "mismatch": f.scan(analysisScore: 70)])
        let original = f.historyBytes
        XCTAssertThrowsError(try f.authority.choices(for: .score)) { error in
            XCTAssertEqual(error as? StyleFriendsDMShareEligibilityAuthority.AvailabilityError, .noValidScores)
        }
        XCTAssertEqual(f.historyBytes, original)
    }

    func testInvalidScoreCannotHideValidScanWithThumbnail() throws {
        let f = try Fixture(); defer { f.cleanup() }
        try f.save(["bad": f.scan(analysisScore: 70), "good": f.scan(thumbnail: f.png)])
        let original = f.historyBytes
        let choices = try f.authority.choices(for: .scan)
        XCTAssertEqual(choices.count, 1)
        XCTAssertEqual(choices.first?.score, 82)
        XCTAssertEqual(f.historyBytes, original)
    }
}

extension StyleFriendsSavedScanSharingTests {
    func testModernImageAndConsumedSnapshotKeepExactSavedFacts() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let jpeg = try f.jpeg()
        let asset = try XCTUnwrap(f.images.storeJPEG(jpeg, pixelWidth: 2, pixelHeight: 2, ownerScanID: "modern"))
        try f.save(["modern": f.scan(asset: asset)])
        let original = f.historyBytes
        let choice = try XCTUnwrap(try f.authority.choices(for: .scan).first)
        XCTAssertEqual(choice.imagePreview, jpeg)
        try f.save(["modern": f.scan(score: 90, analysisScore: 90, asset: asset)])
        XCTAssertEqual(f.authority.consumeSnapshot(for: choice.id, kind: .scan)?.score, 82)
        XCTAssertNil(f.authority.consumeSnapshot(for: choice.id, kind: .scan))
        f.defaults.set(original, forKey: "outfitScanHistoryData")
        _ = try f.authority.choices(for: .scan)
        XCTAssertEqual(f.historyBytes, original)
        XCTAssertEqual(f.images.imageData(for: asset.id), jpeg)
    }
}

extension StyleFriendsSavedScanSharingTests {
    func testForeignOrUnreadableImageIsNotUsedAsAnotherScansPhoto() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let foreign = try XCTUnwrap(f.images.storeJPEG(try f.jpeg(), pixelWidth: 2, pixelHeight: 2, ownerScanID: "other"))
        try f.save(["mine": f.scan(asset: foreign)])
        XCTAssertThrowsError(try f.authority.choices(for: .scan)) { error in
            XCTAssertEqual(error as? StyleFriendsDMShareEligibilityAuthority.AvailabilityError, .photosUnavailable)
        }
        let corrupt = try XCTUnwrap(f.images.storeJPEG(Data("bad-image".utf8), pixelWidth: 2, pixelHeight: 2, ownerScanID: "mine"))
        try f.save(["mine": f.scan(thumbnail: f.png, asset: corrupt)])
        let original = f.historyBytes
        let choices = try f.authority.choices(for: .scan)
        XCTAssertEqual(choices.count, 1)
        XCTAssertNotNil(choices.first?.imagePreview)
        XCTAssertEqual(f.historyBytes, original)
        XCTAssertEqual(f.images.imageData(for: corrupt.id), Data("bad-image".utf8))
    }
}

extension Fixture {
    func jpeg() throws -> Data {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImageFromSource(destination, source, 0, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
