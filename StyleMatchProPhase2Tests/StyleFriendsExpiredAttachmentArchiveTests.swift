import Foundation
import Security
import XCTest
@testable import StyleMatchPro

final class StyleFriendsExpiredAttachmentArchiveTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func pending(_ journal: StyleFriendsDMOperationJournal, account: String = "owner",
                         conversation: String = "thread", type: StyleFriendsDMOperationJournalRecord.OperationType = .preparedAttachment,
                         expired: Bool = true) throws -> StyleFriendsDMOperationJournalRecord {
        let tag = try journal.accountEnvironmentTag(account: account, environment: "synthetic-staging")
        let scope = try journal.scopeTag(account: account, environment: "synthetic-staging", conversation: conversation)
        let fingerprint = try journal.payloadFingerprint(type: type, immutablePayload: Data([1, 2]))
        let createdAt = now.addingTimeInterval(expired ? -172_800 : -10)
        let record = try journal.create(accountEnvironmentTag: tag, scopeTag: scope, operationType: type,
                                        payloadFingerprint: fingerprint, now: createdAt, ttl: 86_400)
        return try journal.transition(operationID: record.operationID, expectedScopeTag: scope, to: .unknown, now: createdAt)
    }

    private func archive(_ record: StyleFriendsDMOperationJournalRecord, in journal: StyleFriendsDMOperationJournal) throws {
        try journal.archiveExpiredUnknownAttachment(operationID: record.operationID, accountEnvironmentTag: record.accountEnvironmentTag,
                                                    expectedScopeTag: record.scopeTag, now: now)
    }

    func testExpiredUnknownStaysLockedUntilExplicitArchiveThenOriginalEvidenceIsPreserved() throws {
        let keychain = ArchiveKeychain(), journal = StyleFriendsDMOperationJournal(keychain: keychain)
        let record = try pending(journal)
        keychain.addWhitespaceToPending(record.operationID)
        let original = try XCTUnwrap(keychain.data(record.operationID, archive: false))
        XCTAssertEqual(try journal.unresolved(accountEnvironmentTag: record.accountEnvironmentTag, now: now), [record])
        try archive(record, in: journal)
        XCTAssertEqual(keychain.data(record.operationID, archive: true), original)
        XCTAssertNil(keychain.data(record.operationID, archive: false))
        XCTAssertTrue(try journal.unresolved(accountEnvironmentTag: record.accountEnvironmentTag, now: now).isEmpty)
        XCTAssertEqual(try JSONDecoder().decode(StyleFriendsDMOperationJournalRecord.self, from: original).phase, .unknown)
        let recreated = StyleFriendsDMOperationJournal(keychain: keychain)
        XCTAssertTrue(try recreated.unresolved(accountEnvironmentTag: record.accountEnvironmentTag, now: now).isEmpty)
        XCTAssertEqual(keychain.data(record.operationID, archive: true), original, "Normal cleanup must retain the archived unknown.")
    }

    func testNewOperationGetsNewIdentityAndArchivedOperationCannotTransitionOrRetry() throws {
        let keychain = ArchiveKeychain(), journal = StyleFriendsDMOperationJournal(keychain: keychain)
        let record = try pending(journal)
        try archive(record, in: journal)
        XCTAssertThrowsError(try journal.transition(operationID: record.operationID, expectedScopeTag: record.scopeTag, to: .reconciling, now: now))
        let fresh = try pending(journal, type: .text, expired: false)
        XCTAssertNotEqual(fresh.operationID, record.operationID)
        XCTAssertEqual(try journal.unresolved(accountEnvironmentTag: record.accountEnvironmentTag, now: now).map(\.operationID), [fresh.operationID])
    }

    func testEligibilityAndArchiveAreExactAccountConversationTypePhaseAndExpiry() throws {
        let journal = StyleFriendsDMOperationJournal(keychain: ArchiveKeychain())
        let target = try pending(journal)
        let otherThread = try pending(journal, conversation: "other-thread")
        let otherAccount = try pending(journal, account: "other-owner")
        let text = try pending(journal, type: .text)
        let fresh = try pending(journal, expired: false)
        let rows = [target, otherThread, otherAccount, text, fresh]
        XCTAssertEqual(StyleFriendsDMOperationJournal.stoppableExpiredAttachments(rows,
            accountEnvironmentTag: target.accountEnvironmentTag, scopeTag: target.scopeTag, now: now), [target.operationID])
        XCTAssertThrowsError(try journal.archiveExpiredUnknownAttachment(operationID: target.operationID,
            accountEnvironmentTag: otherAccount.accountEnvironmentTag, expectedScopeTag: target.scopeTag, now: now))
        XCTAssertThrowsError(try journal.archiveExpiredUnknownAttachment(operationID: target.operationID,
            accountEnvironmentTag: target.accountEnvironmentTag, expectedScopeTag: otherThread.scopeTag, now: now))
        XCTAssertThrowsError(try archive(text, in: journal))
        XCTAssertThrowsError(try archive(fresh, in: journal))
        _ = try journal.transition(operationID: fresh.operationID, expectedScopeTag: fresh.scopeTag, to: .reconciling, now: now)
        XCTAssertThrowsError(try archive(fresh, in: journal))
        try archive(target, in: journal)
        XCTAssertNotNil(try journal.load(operationID: otherThread.operationID, expectedScopeTag: otherThread.scopeTag, now: now))
        XCTAssertNotNil(try journal.load(operationID: otherAccount.operationID, expectedScopeTag: otherAccount.scopeTag, now: now))
    }

    func testUnexpiredUnknownCanBeExplicitlyArchivedWithoutInferringDelivery() throws {
        let keychain = ArchiveKeychain(), journal = StyleFriendsDMOperationJournal(keychain: keychain)
        let record = try pending(journal, expired: false)
        let original = try XCTUnwrap(keychain.data(record.operationID, archive: false))
        XCTAssertGreaterThan(record.expiresAt, now)
        XCTAssertEqual(StyleFriendsDMOperationJournal.stoppableUnknownAttachments([record], accountEnvironmentTag: record.accountEnvironmentTag, scopeTag: record.scopeTag), [record.operationID])
        try journal.archiveUnknownAttachment(operationID: record.operationID, accountEnvironmentTag: record.accountEnvironmentTag, expectedScopeTag: record.scopeTag, now: now)
        XCTAssertEqual(keychain.data(record.operationID, archive: true), original)
        XCTAssertTrue(try journal.unresolved(accountEnvironmentTag: record.accountEnvironmentTag, now: now).isEmpty)
        XCTAssertEqual(try JSONDecoder().decode(StyleFriendsDMOperationJournalRecord.self, from: original).phase, .unknown)
        XCTAssertThrowsError(try journal.transition(operationID: record.operationID, expectedScopeTag: record.scopeTag, to: .reconciling, now: now))
    }

    func testUnexpiredArchiveStillRejectsOtherScopeTextAndInFlightPhase() throws {
        let keychain = ArchiveKeychain(), journal = StyleFriendsDMOperationJournal(keychain: keychain)
        let target = try pending(journal, expired: false), other = try pending(journal, conversation: "other", expired: false)
        let text = try pending(journal, type: .text, expired: false)
        XCTAssertEqual(StyleFriendsDMOperationJournal.stoppableUnknownAttachments([target, other, text], accountEnvironmentTag: target.accountEnvironmentTag, scopeTag: target.scopeTag), [target.operationID])
        XCTAssertThrowsError(try journal.archiveUnknownAttachment(operationID: target.operationID, accountEnvironmentTag: target.accountEnvironmentTag, expectedScopeTag: other.scopeTag, now: now))
        XCTAssertThrowsError(try journal.archiveUnknownAttachment(operationID: target.operationID, accountEnvironmentTag: "wrong-account", expectedScopeTag: target.scopeTag, now: now))
        XCTAssertThrowsError(try journal.archiveUnknownAttachment(operationID: text.operationID, accountEnvironmentTag: text.accountEnvironmentTag, expectedScopeTag: text.scopeTag, now: now))
        _ = try journal.transition(operationID: target.operationID, expectedScopeTag: target.scopeTag, to: .reconciling, now: now)
        XCTAssertThrowsError(try journal.archiveUnknownAttachment(operationID: target.operationID, accountEnvironmentTag: target.accountEnvironmentTag, expectedScopeTag: target.scopeTag, now: now))
        XCTAssertEqual(keychain.pendingDeletes, 0)
    }

    func testArchiveWriteFailureNeverDeletesThePendingRecord() throws {
        let keychain = ArchiveKeychain(), journal = StyleFriendsDMOperationJournal(keychain: keychain)
        let record = try pending(journal)
        let original = keychain.data(record.operationID, archive: false)
        keychain.failArchiveAdd = true
        XCTAssertThrowsError(try archive(record, in: journal))
        XCTAssertEqual(keychain.data(record.operationID, archive: false), original)
        XCTAssertEqual(keychain.pendingDeletes, 0)
    }

    func testArchiveReadbackMismatchNeverReleasesPendingLock() throws {
        let keychain = ArchiveKeychain(), journal = StyleFriendsDMOperationJournal(keychain: keychain)
        let record = try pending(journal)
        keychain.corruptArchiveReadback = true
        XCTAssertThrowsError(try archive(record, in: journal))
        XCTAssertNotNil(keychain.data(record.operationID, archive: false))
        XCTAssertEqual(keychain.pendingDeletes, 0)
    }

    func testDeleteFailureKeepsBothCopiesAndExplicitRetryFinishesSafely() throws {
        let keychain = ArchiveKeychain(), journal = StyleFriendsDMOperationJournal(keychain: keychain)
        let record = try pending(journal)
        keychain.failPendingDelete = true
        XCTAssertThrowsError(try archive(record, in: journal))
        XCTAssertNotNil(keychain.data(record.operationID, archive: false))
        XCTAssertEqual(keychain.data(record.operationID, archive: true), keychain.data(record.operationID, archive: false))
        keychain.failPendingDelete = false
        try archive(record, in: journal)
        XCTAssertNil(keychain.data(record.operationID, archive: false))
        XCTAssertNotNil(keychain.data(record.operationID, archive: true))
    }

    func testArchiveIsDeviceOnlyAndAccountRemovalKeepsOtherAccountsArchive() throws {
        let keychain = ArchiveKeychain(), journal = StyleFriendsDMOperationJournal(keychain: keychain)
        let owner = try pending(journal), other = try pending(journal, account: "other-owner")
        try archive(owner, in: journal); try archive(other, in: journal)
        for query in keychain.archiveAdds {
            XCTAssertEqual(query[kSecAttrAccessible as String] as? String, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
            XCTAssertEqual(query[kSecAttrSynchronizable as String] as? Bool, false)
            XCTAssertNil(query[kSecAttrAccessGroup as String])
        }
        try journal.deleteAll(accountEnvironmentTag: owner.accountEnvironmentTag)
        XCTAssertNil(keychain.data(owner.operationID, archive: true))
        XCTAssertNotNil(keychain.data(other.operationID, archive: true))
    }

    func testArchiveCapacityFailureRetainsNewPendingEvidence() throws {
        let keychain = ArchiveKeychain(), journal = StyleFriendsDMOperationJournal(keychain: keychain)
        for _ in 0..<32 { try archive(pending(journal), in: journal) }
        let last = try pending(journal)
        XCTAssertThrowsError(try archive(last, in: journal)) { XCTAssertEqual($0 as? StyleFriendsDMOperationJournalError, .limitReached) }
        XCTAssertNotNil(keychain.data(last.operationID, archive: false))
        XCTAssertEqual(keychain.archiveAdds.count, 32)
    }

    @MainActor
    func testStatusRecoveryDoesNotQueryArchivedOperation() async throws {
        let keychain = ArchiveKeychain(), journal = StyleFriendsDMOperationJournal(keychain: keychain)
        // Recovery uses real wall time; this record is deliberately older.
        let tag = try journal.accountEnvironmentTag(account: "owner", environment: "synthetic-staging")
        let scope = try journal.scopeTag(account: "owner", environment: "synthetic-staging", conversation: "thread")
        let fingerprint = try journal.payloadFingerprint(type: .preparedAttachment, immutablePayload: Data([1]))
        let old = Date().addingTimeInterval(-172_800)
        let created = try journal.create(accountEnvironmentTag: tag, scopeTag: scope, operationType: .preparedAttachment,
                                          payloadFingerprint: fingerprint, now: old)
        _ = try journal.transition(operationID: created.operationID, expectedScopeTag: scope, to: .unknown, now: old)
        try journal.archiveExpiredUnknownAttachment(operationID: created.operationID, accountEnvironmentTag: tag, expectedScopeTag: scope)
        let spy = StatusSpy()
        let result = await StyleFriendsDMOperationRecoveryCoordinator(journal: journal).reconcile(accountEnvironmentTag: tag, scopeTag: scope, service: spy)
        XCTAssertTrue(result.isEmpty)
        let calls = await spy.calls
        XCTAssertEqual(calls, 0)
    }

    private actor StatusSpy: StyleFriendsDMOperationStatusServing {
        private(set) var calls = 0
        func operationStatus(context: StyleFriendsDMOperationContext) async throws -> StyleFriendsDMOperationStatus {
            calls += 1
            return .init(operationID: context.operationID, outcome: .unknown)
        }
    }

    private final class ArchiveKeychain: StyleFriendsDMOperationKeychainServing {
        private var values: [String: Data] = [:]
        var failArchiveAdd = false, corruptArchiveReadback = false, failPendingDelete = false
        var archiveAdds: [[String: Any]] = []
        var pendingDeletes = 0
        private let pendingService = "com.sabastine.stylematchai.stylefriends.dm.operation.v1"
        private let archiveService = "com.sabastine.stylematchai.stylefriends.dm.operation-archive.v1"
        private func key(_ q: [String: Any]) -> String { "\(q[kSecAttrService as String] as? String ?? "")|\(q[kSecAttrAccount as String] as? String ?? "")" }
        func addWhitespaceToPending(_ id: UUID) {
            let item = "\(pendingService)|\(id.uuidString)"
            if let data = values[item] { values[item] = Data("  ".utf8) + data + Data("  ".utf8) }
        }
        func data(_ id: UUID, archive: Bool) -> Data? { values["\(archive ? archiveService : pendingService)|\(id.uuidString)"] }
        func add(_ query: [String: Any]) -> OSStatus {
            if query[kSecAttrService as String] as? String == archiveService {
                if failArchiveAdd { return errSecAuthFailed }
                archiveAdds.append(query)
            }
            guard let data = query[kSecValueData as String] as? Data else { return errSecParam }
            guard values[key(query)] == nil else { return errSecDuplicateItem }
            values[key(query)] = data
            return errSecSuccess
        }
        func read(_ query: [String: Any]) -> StyleFriendsDMOperationKeychainRead {
            let service = query[kSecAttrService as String] as? String ?? ""
            let account = query[kSecAttrAccount as String] as? String
            var found = values.compactMap { k, v in k.hasPrefix(service + "|") && (account == nil || k == service + "|" + account!) ? v : nil }
            if corruptArchiveReadback && service == archiveService && !found.isEmpty { found = [Data([0])] }
            return .init(status: found.isEmpty ? errSecItemNotFound : errSecSuccess, values: found)
        }
        func update(_ query: [String: Any], values update: [String: Any]) -> OSStatus {
            guard values[key(query)] != nil, let data = update[kSecValueData as String] as? Data else { return errSecItemNotFound }
            values[key(query)] = data
            return errSecSuccess
        }
        func delete(_ query: [String: Any]) -> OSStatus {
            if query[kSecAttrService as String] as? String == pendingService {
                pendingDeletes += 1
                if failPendingDelete { return errSecAuthFailed }
            }
            return values.removeValue(forKey: key(query)) == nil ? errSecItemNotFound : errSecSuccess
        }
    }
}
