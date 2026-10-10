import Foundation
import XCTest
@testable import StyleMatchPro

private func localExportProjectSource(_ relativePath: String, filePath: String = #filePath) throws -> String {
    let root = URL(fileURLWithPath: filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
}

final class LocalDataExportServiceTests: XCTestCase {
    private final class IdentifierSequence {
        private let lock = NSLock()
        private var identifiers: [String]

        init(_ identifiers: [String]) {
            self.identifiers = identifiers
        }

        func next() -> String {
            lock.lock()
            defer { lock.unlock() }
            return identifiers.removeFirst()
        }
    }

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var exportDirectory: URL!

    override func setUp() {
        super.setUp()
        suiteName = "LocalDataExportServiceTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set("guest", forKey: AccountScopedStorage.activeUserMarkerKey)
        defaults.set("guest", forKey: "customerAccountMode")
        exportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalDataExportServiceTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: exportDirectory)
        defaults = nil
        suiteName = nil
        exportDirectory = nil
        super.tearDown()
    }

    func testLocalExportIncludesActiveLocalDataAndProducesJSONAndZIP() throws {
        defaults.set("Taylor", forKey: "profileName")
        defaults.set("blue, green", forKey: "favoriteColors")
        defaults.set(Data("{\"scan\":{\"score\":80}}".utf8), forKey: "outfitScanHistoryData")

        let result = try LocalDataExportService().prepare(defaults: defaults, destinationDirectory: exportDirectory)
        let json = try String(contentsOf: result.jsonURL, encoding: .utf8)
        let zipData = try Data(contentsOf: result.zipURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: result.jsonURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.zipURL.path))
        XCTAssertTrue(json.contains("local-device-only"))
        XCTAssertTrue(json.contains("Taylor"))
        XCTAssertTrue(json.contains("favoriteColors"))
        XCTAssertTrue(json.contains("outfitScanHistoryData"))
        XCTAssertEqual(Array(zipData.prefix(4)), [0x50, 0x4b, 0x03, 0x04])

        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzip.arguments = ["-t", result.zipURL.path]
        try unzip.run()
        unzip.waitUntilExit()
        XCTAssertEqual(unzip.terminationStatus, 0, "The local export must be a readable ZIP archive.")
    }

    func testLocalExportExcludesIdentityCredentialsAndSharedLinkManagementTokens() throws {
        defaults.set("private-apple-identifier", forKey: "customerAppleUserID")
        defaults.set("private@example.com", forKey: "customerAccountEmail")
        ShareableScoreCardLocalStore(defaults: defaults, userID: "guest").saveCreatedCard(
            token: "public-link-token",
            url: URL(string: "https://stylematchpro.com/share/public-link-token")!,
            expiresAt: "2026-08-01T00:00:00Z"
        )

        let result = try LocalDataExportService().prepare(defaults: defaults, destinationDirectory: exportDirectory)
        let json = try String(contentsOf: result.jsonURL, encoding: .utf8)

        XCTAssertTrue(json.contains("public-link-token"))
        XCTAssertFalse(json.contains("private-management-token"))
        XCTAssertFalse(json.contains("private-apple-identifier"))
        XCTAssertFalse(json.contains("private@example.com"))
        XCTAssertFalse(json.contains("not-exportable-key"))
    }

    func testExportsCreatedInTheSameSecondUseDistinctArtifactPaths() throws {
        let timestamp = Date(timeIntervalSince1970: 1_785_859_332.384)
        let identifiers = IdentifierSequence(["request-one", "request-two"])
        let service = LocalDataExportService(identifierGenerator: identifiers.next)

        let first = try service.prepare(
            defaults: defaults,
            now: timestamp,
            destinationDirectory: exportDirectory
        )
        let second = try service.prepare(
            defaults: defaults,
            now: timestamp,
            destinationDirectory: exportDirectory
        )

        XCTAssertNotEqual(first.jsonURL, second.jsonURL)
        XCTAssertNotEqual(first.zipURL, second.zipURL)
        XCTAssertEqual(first.jsonURL.pathExtension, "json")
        XCTAssertEqual(first.zipURL.pathExtension, "zip")
    }

    func testRapidExportsPreserveEarlierArtifactBytesAndUseUniquePaths() throws {
        let timestamp = Date(timeIntervalSince1970: 1_785_859_332.384)
        let identifiers = IdentifierSequence((0..<10).map { "request-\($0)" })
        let service = LocalDataExportService(identifierGenerator: identifiers.next)

        let first = try service.prepare(defaults: defaults, now: timestamp, destinationDirectory: exportDirectory)
        let firstZIPBytes = try Data(contentsOf: first.zipURL)
        let remaining = try (0..<9).map { _ in
            try service.prepare(defaults: defaults, now: timestamp, destinationDirectory: exportDirectory)
        }
        let all = [first] + remaining

        XCTAssertEqual(Set(all.map(\.jsonURL)).count, 10)
        XCTAssertEqual(Set(all.map(\.zipURL)).count, 10)
        XCTAssertEqual(try Data(contentsOf: first.zipURL), firstZIPBytes)
        XCTAssertTrue(all.allSatisfy { $0.jsonURL.lastPathComponent.hasPrefix("StyleMatch-local-export-20260804T160212.384Z-") })
    }

    func testExistingRequestDirectoryIsNeverOverwritten() throws {
        let timestamp = Date(timeIntervalSince1970: 1_785_859_332.384)
        let identifiers = IdentifierSequence(["already-used", "already-used", "replacement"])
        let service = LocalDataExportService(identifierGenerator: identifiers.next)

        let first = try service.prepare(defaults: defaults, now: timestamp, destinationDirectory: exportDirectory)
        let firstBytes = try Data(contentsOf: first.zipURL)
        let second = try service.prepare(defaults: defaults, now: timestamp, destinationDirectory: exportDirectory)

        XCTAssertNotEqual(first.zipURL, second.zipURL)
        XCTAssertEqual(try Data(contentsOf: first.zipURL), firstBytes)
    }

    func testConcurrentExportsUseIsolatedTemporaryDirectories() throws {
        let service = LocalDataExportService()
        let timestamp = Date(timeIntervalSince1970: 1_785_859_332.384)
        let lock = NSLock()
        var results: [LocalDataExportService.Result] = []
        var failures: [Error] = []

        DispatchQueue.concurrentPerform(iterations: 8) { _ in
            do {
                let result = try service.prepare(defaults: defaults, now: timestamp, destinationDirectory: exportDirectory)
                lock.lock()
                results.append(result)
                lock.unlock()
            } catch {
                lock.lock()
                failures.append(error)
                lock.unlock()
            }
        }

        XCTAssertTrue(failures.isEmpty)
        XCTAssertEqual(results.count, 8)
        XCTAssertEqual(Set(results.map(\.jsonURL)).count, 8)
        XCTAssertEqual(Set(results.map(\.zipURL)).count, 8)
        XCTAssertEqual(Set(results.map { $0.jsonURL.deletingLastPathComponent() }).count, 8)
    }

    func testExportFilenameContainsNoCustomerControlledIdentity() throws {
        defaults.set("Taylor Example", forKey: "profileName")
        defaults.set("taylor@example.com", forKey: "customerAccountEmail")
        defaults.set("private-apple-identifier", forKey: "customerAppleUserID")
        let service = LocalDataExportService(identifierGenerator: { "safe-request-id" })

        let result = try service.prepare(
            defaults: defaults,
            now: Date(timeIntervalSince1970: 1_785_859_332.384),
            destinationDirectory: exportDirectory
        )

        for filename in [result.jsonURL.lastPathComponent, result.zipURL.lastPathComponent] {
            XCTAssertFalse(filename.contains("Taylor"))
            XCTAssertFalse(filename.contains("example.com"))
            XCTAssertFalse(filename.contains("private-apple-identifier"))
            XCTAssertTrue(filename.hasPrefix("StyleMatch-local-export-"))
        }
    }

    func testSettingsSourceExplainsLocalOnlyExportAndUnavailableNotifications() throws {
        let source = try localExportProjectSource("StyleMatchAI/ProfileView.swift")
        let sharedLinks = try localExportProjectSource("StyleMatchAI/ShareableScoreCardViews.swift")

        XCTAssertFalse(source.contains("Export local KigoStylist data"))
        XCTAssertFalse(source.contains("Export Data"))
        XCTAssertFalse(source.contains("LocalDataExportService"))
        XCTAssertTrue(source.contains("profileInfoRow(\"Notifications\", \"Coming Soon\", icon: \"bell.slash.fill\")"))
        XCTAssertTrue(source.contains(".accessibilityValue(\"Coming Soon, unavailable\")"))
        XCTAssertFalse(source.contains("NotificationSettingsPreviewView"))
        XCTAssertTrue(sharedLinks.contains("No Shared Links Yet"))
        XCTAssertTrue(sharedLinks.contains("Create Your First Shared Link"))
        XCTAssertTrue(sharedLinks.contains("saved Scan’s Share Outfit preview"))
    }
}
