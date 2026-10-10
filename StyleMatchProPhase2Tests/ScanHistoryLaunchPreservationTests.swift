import XCTest
import CryptoKit
@testable import StyleMatchPro

final class ScanHistoryLaunchPreservationTests: XCTestCase {
    private func isolated(_ body: (UserDefaults) throws -> Void) rethrows {
        let suite = "ScanHistoryLaunchPreservationTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    private func payload(score: Int = 83) throws -> Data {
        try JSONEncoder().encode(["preserved-scan": StoredOutfitScan(
            score: score, analysis: nil, firstScannedAt: Date(timeIntervalSinceReferenceDate: 800_000_000),
            scanCount: 1, thumbnailData: Data([1, 2, 3]), customTitle: "Saved result"
        )])
    }

    private func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func launch(_ defaults: UserDefaults, verifiedSubject: String?) {
        AccountAccessRestoration.restore(verifiedAppleSubject: verifiedSubject, defaults: defaults)
        let captured = AccountScopedStorage.prepareForLaunch(defaults: defaults)
        StyleMatchAppLaunchMigrations.run(defaults: defaults)
        if captured { AccountScopedStorage.restoreCapturedLaunchData(defaults: defaults) }
    }

    func testRecoveredSessionKeepsExistingAppleHistoryAcrossRepeatedLaunches() throws {
        try isolated { defaults in
            let data = try payload()
            defaults.set("owner-a", forKey: AccountScopedStorage.activeUserMarkerKey)
            defaults.set("production", forKey: AccountScopedStorage.activeEnvironmentMarkerKey)
            defaults.set(data, forKey: "outfitScanHistoryData")
            defaults.set(false, forKey: "customerAccountSyncEnabled")
            launch(defaults, verifiedSubject: "owner-a")
            launch(defaults, verifiedSubject: "owner-a")
            XCTAssertEqual(defaults.data(forKey: "outfitScanHistoryData"), data)
            XCTAssertEqual(AccountScopedStorage.activePresentationUserID(defaults: defaults), "owner-a")
            XCTAssertNil(defaults.object(forKey: AccountScopedStorage.snapshotKey("outfitScanHistoryData", userID: "guest", environment: .production)))
            XCTAssertFalse(defaults.bool(forKey: "customerAccountSyncEnabled"))
        }
    }

    func testRecoveredSessionCapturesLegacyHistoryUnderAppleBeforeMigrations() throws {
        try isolated { defaults in
            let data = try payload()
            defaults.set(data, forKey: "outfitScanHistoryData")
            launch(defaults, verifiedSubject: "owner-a")
            launch(defaults, verifiedSubject: "owner-a")
            XCTAssertEqual(defaults.data(forKey: "outfitScanHistoryData"), data)
            XCTAssertEqual(defaults.data(forKey: AccountScopedStorage.snapshotKey("outfitScanHistoryData", userID: "owner-a", environment: .production)), data)
            XCTAssertNil(defaults.object(forKey: AccountScopedStorage.snapshotKey("outfitScanHistoryData", userID: "guest", environment: .production)))
        }
    }

    func testGuestChoiceMissingSessionAndConflictingAppleIdentityArePreserved() {
        isolated { defaults in
            defaults.set(true, forKey: "hasChosenAccessMode")
            defaults.set("Guest", forKey: "customerAccountMode")
            XCTAssertFalse(AccountAccessRestoration.restore(verifiedAppleSubject: "owner-a", defaults: defaults))
            XCTAssertEqual(AccountScopedStorage.sessionUserID(defaults: defaults), "guest")
            defaults.set(false, forKey: "hasChosenAccessMode")
            XCTAssertFalse(AccountAccessRestoration.restore(verifiedAppleSubject: nil, defaults: defaults))
            XCTAssertFalse(AccountAccessRestoration.restore(verifiedAppleSubject: "  ", defaults: defaults))
            defaults.set("owner-b", forKey: "customerAppleUserID")
            XCTAssertFalse(AccountAccessRestoration.restore(verifiedAppleSubject: "owner-a", defaults: defaults))
            XCTAssertEqual(defaults.string(forKey: "customerAppleUserID"), "owner-b")
        }
    }

    func testExplicitRecoveryPreservesExactHistoryAndGuestSnapshotAcrossRelaunch() throws {
        try isolated { defaults in
            let data = try payload()
            launch(defaults, verifiedSubject: "owner-a")
            let guestKey = AccountScopedStorage.snapshotKey("outfitScanHistoryData", userID: "guest", environment: .production)
            defaults.set(data, forKey: guestKey)
            let owner = PersonalStylistStorage.protectedStorageIdentifier(for: "owner-a")
            XCTAssertEqual(ScopedScanHistoryRecovery.restore(data: data, expectedSHA256: hash(data), ownerStorageIdentifier: owner, defaults: defaults), .restored)
            launch(defaults, verifiedSubject: "owner-a")
            XCTAssertEqual(defaults.data(forKey: "outfitScanHistoryData"), data)
            XCTAssertEqual(defaults.data(forKey: guestKey), data)
            XCTAssertEqual(ScopedScanHistoryRecovery.restore(data: data, expectedSHA256: hash(data), ownerStorageIdentifier: owner, defaults: defaults), .alreadyPresent)
        }
    }

    func testRecoveryRejectsOtherAccountCorruptionAndNewerHistoryWithoutWrites() throws {
        try isolated { defaults in
            launch(defaults, verifiedSubject: "owner-a")
            let data = try payload()
            let owner = PersonalStylistStorage.protectedStorageIdentifier(for: "owner-a")
            XCTAssertEqual(ScopedScanHistoryRecovery.restore(data: data, expectedSHA256: hash(data), ownerStorageIdentifier: "wrong-owner", defaults: defaults), .wrongAccount)
            XCTAssertEqual(ScopedScanHistoryRecovery.restore(data: data, expectedSHA256: "wrong", ownerStorageIdentifier: owner, defaults: defaults), .invalidPayload)
            XCTAssertNil(defaults.object(forKey: "outfitScanHistoryData"))
            let newer = try payload(score: 91)
            defaults.set(newer, forKey: "outfitScanHistoryData")
            XCTAssertEqual(ScopedScanHistoryRecovery.restore(data: data, expectedSHA256: hash(data), ownerStorageIdentifier: owner, defaults: defaults), .existingHistory)
            XCTAssertEqual(defaults.data(forKey: "outfitScanHistoryData"), newer)
            let snapshot = AccountScopedStorage.snapshotKey("outfitScanHistoryData", userID: "owner-a", environment: .production)
            XCTAssertNil(defaults.object(forKey: snapshot))
        }
    }

    func testRestoreDoesNotAutomaticallyTransferGuestHistoryToSignedInAccount() throws {
        try isolated { defaults in
            let data = try payload()
            defaults.set("guest", forKey: AccountScopedStorage.activeUserMarkerKey)
            defaults.set("production", forKey: AccountScopedStorage.activeEnvironmentMarkerKey)
            defaults.set(data, forKey: "outfitScanHistoryData")
            launch(defaults, verifiedSubject: "owner-a")
            XCTAssertNil(defaults.object(forKey: "outfitScanHistoryData"))
            XCTAssertEqual(defaults.data(forKey: AccountScopedStorage.snapshotKey("outfitScanHistoryData", userID: "guest", environment: .production)), data)
        }
    }
}
