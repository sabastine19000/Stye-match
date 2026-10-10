import XCTest
@testable import StyleMatchPro

final class StyleFriendsDMRecoveryDiagnosticTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let account = String(repeating: "a", count: 64)
    private let scope = String(repeating: "c", count: 64)

    private func record(type: StyleFriendsDMOperationJournalRecord.OperationType = .text,
                        phase: StyleFriendsDMOperationJournalRecord.Phase = .unknown,
                        age: TimeInterval = 600, ttl: TimeInterval = 3_600,
                        account: String? = nil, scope: String? = nil, reference: String? = nil) -> StyleFriendsDMOperationJournalRecord {
        .init(schema: 1, operationID: UUID(), accountEnvironmentTag: account ?? self.account,
              scopeTag: scope ?? self.scope, operationType: type,
              payloadFingerprint: String(repeating: "f", count: 64), phase: phase,
              createdAt: now.addingTimeInterval(-age), updatedAt: now,
              expiresAt: now.addingTimeInterval(ttl), reconciliationCount: 0,
              retryCount: 0, opaqueServerReference: reference)
    }

    private func snapshot(_ records: [StyleFriendsDMOperationJournalRecord]) -> StyleFriendsDMRecoveryDiagnosticSnapshot {
        .init(records: records, accountEnvironmentTag: account, scopeTag: scope, now: now)
    }

    func testExcludesOtherAccountEnvironmentsAndConversations() {
        let value = snapshot([
            record(type: .preparedAttachment, age: 3 * 86_400, ttl: -1, reference: "opaque-reference"),
            record(account: String(repeating: "b", count: 64)),
            record(scope: String(repeating: "d", count: 64))
        ])
        XCTAssertEqual(value.availability, .available)
        XCTAssertEqual(value.pendingCount, 1)
        XCTAssertEqual(value.expiredCount, 1)
        XCTAssertEqual(value.preparedAttachmentCount, 1)
        XCTAssertEqual(value.textCount, 0)
        XCTAssertEqual(value.serverReferenceCount, 1)
        XCTAssertEqual(value.oldestAge, .underWeek)
        XCTAssertEqual(value.phaseCounts, ["unknown": 1])
    }

    func testExpiredUnknownRemainsPendingWhileTerminalRecordsAreExcluded() {
        let unresolved = record(ttl: -86_400)
        let value = snapshot([unresolved, record(phase: .committed), record(phase: .notCommitted), record(phase: .abandoned)])
        XCTAssertEqual(value.pendingCount, 1)
        XCTAssertEqual(value.expiredCount, 1)
        XCTAssertEqual(value.phaseCounts, ["unknown": 1])
        XCTAssertEqual(unresolved.phase, .unknown)
    }

    func testExpiryBoundaryCountsWithoutInferringCompletion() {
        let value = snapshot([record(ttl: -1), record(ttl: 0), record(ttl: 1)])
        XCTAssertEqual(value.pendingCount, 3)
        XCTAssertEqual(value.expiredCount, 2)
        XCTAssertEqual(value.phaseCounts, ["unknown": 3])
    }

    func testAgeBucketsAndFutureClockAreExplicit() {
        let cases: [(TimeInterval, StyleFriendsDMRecoveryDiagnosticSnapshot.Age)] = [
            (3_599, .underHour), (3_600, .underDay), (86_400, .underWeek),
            (604_800, .older), (-60, .future)
        ]
        for (age, expected) in cases {
            XCTAssertEqual(snapshot([record(age: age)]).oldestAge, expected)
        }
    }

    func testUnavailableAndUncheckedAreDistinctFromAnEmptyConversation() {
        XCTAssertEqual(StyleFriendsDMRecoveryDiagnosticSnapshot().availability, .notChecked)
        XCTAssertEqual(StyleFriendsDMRecoveryDiagnosticSnapshot.unavailable.availability, .unavailable)
        let empty = snapshot([])
        XCTAssertEqual(empty.availability, .available)
        XCTAssertEqual(empty.pendingCount, 0)
        XCTAssertEqual(empty.oldestAge, .none)
        let missingScope = StyleFriendsDMRecoveryDiagnosticSnapshot(records: [record()], accountEnvironmentTag: account, scopeTag: "", now: now)
        XCTAssertEqual(missingScope.availability, .unavailable)
    }

    func testSnapshotDoesNotRetainIdentifiersTagsFingerprintsOrReferences() {
        let pending = record(reference: "private-server-correlation-material")
        let displayed = String(reflecting: snapshot([pending]))
        for forbidden in [pending.operationID.uuidString, pending.accountEnvironmentTag, pending.scopeTag,
                          pending.payloadFingerprint, pending.opaqueServerReference!] {
            XCTAssertFalse(displayed.contains(forbidden))
        }
    }

    func testMixedTypesAndPhasesAreCountedIndependently() {
        let value = snapshot([record(phase: .submitted),
                              record(type: .preparedAttachment, phase: .uploadingAttachment),
                              record(type: .preparedAttachment, reference: "opaque-reference")])
        XCTAssertEqual(value.pendingCount, 3)
        XCTAssertEqual(value.textCount, 1)
        XCTAssertEqual(value.preparedAttachmentCount, 2)
        XCTAssertEqual(value.serverReferenceCount, 1)
        XCTAssertEqual(value.phaseCounts, ["submitted": 1, "uploadingAttachment": 1, "unknown": 1])
    }
}
