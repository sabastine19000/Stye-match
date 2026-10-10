import Foundation
import XCTest
@testable import StyleMatchPro

final class SavedScanImageAssetStoreTests: XCTestCase {
    private var root: URL!
    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SavedScanImageAssetStoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        root = nil
    }

    func testStoredAssetSurvivesStoreReinitialization() throws {
        let original = Data("accepted-image-bytes".utf8)
        let stored = try XCTUnwrap(
            SavedScanImageAssetStore(rootDirectory: root).storeJPEG(
                original,
                pixelWidth: 1200,
                pixelHeight: 1600
            )
        )

        XCTAssertEqual(stored.formatVersion, SavedScanImageAssetStore.currentFormatVersion)
        XCTAssertEqual(
            SavedScanImageAssetStore(rootDirectory: root).imageData(for: stored.id),
            original
        )
    }

    func testInvalidAndUnreferencedAssetsFailClosedOrAreRemoved() throws {
        let store = SavedScanImageAssetStore(rootDirectory: root)
        XCTAssertNil(store.storeJPEG(Data(), pixelWidth: 1, pixelHeight: 1))
        XCTAssertNil(store.imageData(for: "not-an-opaque-asset-id"))

        let asset = try XCTUnwrap(store.storeJPEG(Data("image".utf8), pixelWidth: 2, pixelHeight: 3))
        store.removeIfUnreferenced(assetID: asset.id, referencedAssetIDs: [asset.id])
        XCTAssertNotNil(store.imageData(for: asset.id))
        store.removeIfUnreferenced(assetID: asset.id, referencedAssetIDs: [])
        XCTAssertNil(store.imageData(for: asset.id))
    }

    func testAccountScopedAssetsAreNotVisibleAcrossUsersAndDeletionIsScoped() throws {
        let accountA = SavedScanImageAssetStore(rootDirectory: root, userID: "account-a")
        let accountB = SavedScanImageAssetStore(rootDirectory: root, userID: "account-b")
        let assetA = try XCTUnwrap(
            accountA.storeJPEG(Data("account-a-image".utf8), pixelWidth: 10, pixelHeight: 10)
        )
        let assetB = try XCTUnwrap(
            accountB.storeJPEG(Data("account-b-image".utf8), pixelWidth: 10, pixelHeight: 10)
        )

        XCTAssertNil(accountB.imageData(for: assetA.id))
        XCTAssertNil(accountA.imageData(for: assetB.id))

        accountA.removeAllAccountAssets()
        XCTAssertNil(accountA.imageData(for: assetA.id))
        XCTAssertEqual(accountB.imageData(for: assetB.id), Data("account-b-image".utf8))
    }

    func testSensitiveAssetStorageUsesAccountHashAndIOSCompleteProtectionPolicy() throws {
        let source = try String(
            contentsOfFile: projectRoot.appendingPathComponent("StyleMatchAI/ScanAuthority/SavedScanImageAssetStore.swift").path,
            encoding: .utf8
        )
        let protection = try String(
            contentsOfFile: projectRoot.appendingPathComponent("StyleMatchAI/PersonalStylist/PersonalStylistStorage.swift").path,
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("PersonalStylistStorage.protectedStorageIdentifier"))
        XCTAssertTrue(source.contains("Self.accountDirectoryName"))
        XCTAssertTrue(protection.contains("SHA256.hash(data: Data(normalized.utf8))"))
        XCTAssertTrue(protection.contains("FileProtectionType.complete"))
        XCTAssertTrue(protection.contains("values.isExcludedFromBackup = backupPolicy.excludesFromBackup"))
    }

    func testSavedScanCapacityAcceptsTheFiveHundredthRecordAndRejectsTheFiveHundredFirst() {
        let firstTwenty = Set((1...20).map { "scan-\($0)" })
        XCTAssertTrue(SavedScanHistoryCapacity.canInsert(recordID: "scan-21", existingRecordIDs: firstTwenty))

        let fiveHundred = Set((1...500).map { "scan-\($0)" })
        XCTAssertFalse(SavedScanHistoryCapacity.canInsert(recordID: "scan-501", existingRecordIDs: fiveHundred))
        XCTAssertTrue(SavedScanHistoryCapacity.canInsert(recordID: "scan-500", existingRecordIDs: fiveHundred))
    }
}
