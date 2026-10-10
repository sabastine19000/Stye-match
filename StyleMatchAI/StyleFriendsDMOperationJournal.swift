import CryptoKit
import Foundation
import Security

protocol StyleFriendsAttachmentJournaling: AnyObject {
    func scopeTag(account: String, environment: String, conversation: String) throws -> String
    func accountEnvironmentTag(account: String, environment: String) throws -> String
    func payloadFingerprint(type: StyleFriendsDMOperationJournalRecord.OperationType, immutablePayload: Data) throws -> String
    func create(accountEnvironmentTag: String, scopeTag: String, operationType: StyleFriendsDMOperationJournalRecord.OperationType, payloadFingerprint: String, now: Date, ttl: TimeInterval) throws -> StyleFriendsDMOperationJournalRecord
    func transition(operationID: UUID, expectedScopeTag: String, to phase: StyleFriendsDMOperationJournalRecord.Phase, opaqueServerReference: String?, now: Date) throws -> StyleFriendsDMOperationJournalRecord
    func load(operationID: UUID, expectedScopeTag: String, now: Date) throws -> StyleFriendsDMOperationJournalRecord?
}

/// Device-local, content-free recovery metadata for a Style Friends outbound
/// operation.  It deliberately has no draft text, image data, route reference,
/// token, account identifier, or conversation identifier.
struct StyleFriendsDMOperationJournalRecord: Codable, Equatable, Sendable {
    enum OperationType: String, Codable, Sendable { case text, preparedAttachment }
    enum Phase: String, Codable, Sendable {
        case created, preparingAttachment, uploadingAttachment, finalizingAttachment
        case submitted, reconciling, committed, notCommitted, unknown, abandoned
    }

    static let schemaVersion = 1
    let schema: Int
    let operationID: UUID
    let accountEnvironmentTag: String
    let scopeTag: String
    let operationType: OperationType
    let payloadFingerprint: String
    var phase: Phase
    let createdAt: Date
    var updatedAt: Date
    let expiresAt: Date
    var reconciliationCount: Int
    var retryCount: Int
    /// Opaque, server-issued correlation material only. It must never be a URL.
    var opaqueServerReference: String?
}

/// Content-free projection of records already read by conversation recovery.
/// It performs no Keychain access, network request, mutation, or persistence.
/// Identifiers, tags, fingerprints and server references are never retained.
struct StyleFriendsDMRecoveryDiagnosticSnapshot: Equatable, Sendable {
    enum Availability: String, Sendable { case notChecked = "Not checked", available = "Available", unavailable = "Unavailable" }
    enum Age: String, Sendable {
        case none = "No pending operations", underHour = "Under 1 hour"
        case underDay = "1–24 hours", underWeek = "1–7 days", older = "7 days or more"
        case future = "Device clock needs checking", invalid = "Unavailable"
    }
    private(set) var availability: Availability = .notChecked
    private(set) var pendingCount = 0
    private(set) var expiredCount = 0
    private(set) var textCount = 0
    private(set) var preparedAttachmentCount = 0
    private(set) var serverReferenceCount = 0
    private(set) var phaseCounts: [String: Int] = [:]
    private(set) var oldestAge: Age = .none

    init() {}

    static var unavailable: Self {
        var value = Self()
        value.availability = .unavailable
        return value
    }

    init(records: [StyleFriendsDMOperationJournalRecord], accountEnvironmentTag: String, scopeTag: String, now: Date) {
        guard !accountEnvironmentTag.isEmpty, !scopeTag.isEmpty else {
            self = .unavailable
            return
        }
        let pending = records.filter {
            $0.accountEnvironmentTag == accountEnvironmentTag && $0.scopeTag == scopeTag
                && ![.committed, .notCommitted, .abandoned].contains($0.phase)
        }
        availability = .available
        pendingCount = pending.count
        expiredCount = pending.filter { $0.expiresAt <= now }.count
        textCount = pending.filter { $0.operationType == .text }.count
        preparedAttachmentCount = pending.filter { $0.operationType == .preparedAttachment }.count
        serverReferenceCount = pending.filter { $0.opaqueServerReference != nil }.count
        phaseCounts = Dictionary(grouping: pending, by: { $0.phase.rawValue }).mapValues { $0.count }
        if let oldest = pending.map(\.createdAt).min() {
            let elapsed = now.timeIntervalSince(oldest)
            if !elapsed.isFinite { oldestAge = .invalid }
            else if elapsed < 0 { oldestAge = .future }
            else if elapsed < 3_600 { oldestAge = .underHour }
            else if elapsed < 86_400 { oldestAge = .underDay }
            else if elapsed < 604_800 { oldestAge = .underWeek }
            else { oldestAge = .older }
        }
    }
}

/// The only operation material permitted to leave the journal. It is opaque to
/// UI and never contains a draft, an attachment reference, or an identity.
struct StyleFriendsDMOperationContext: Equatable, Sendable {
    let protocolVersion: Int
    let operationID: UUID
    let scopeTag: String
    let operationType: StyleFriendsDMOperationJournalRecord.OperationType
    let payloadFingerprint: String

    init(record: StyleFriendsDMOperationJournalRecord) {
        protocolVersion = record.schema; operationID = record.operationID
        scopeTag = record.scopeTag; operationType = record.operationType
        payloadFingerprint = record.payloadFingerprint
    }
}

enum StyleFriendsDMOperationJournalError: Error, Equatable, Sendable {
    case unavailable, invalidRecord, scopeMismatch, invalidTransition, limitReached
}

/// Narrow Keychain seam: production uses Security, while tests can inspect the
/// exact serialized value and protection attributes without touching a device
/// Keychain.  It deliberately exposes no private-key material.
struct StyleFriendsDMOperationKeychainRead {
    let status: OSStatus
    let values: [Data]
}

protocol StyleFriendsDMOperationKeychainServing {
    func add(_ query: [String: Any]) -> OSStatus
    func read(_ query: [String: Any]) -> StyleFriendsDMOperationKeychainRead
    func update(_ query: [String: Any], values: [String: Any]) -> OSStatus
    func delete(_ query: [String: Any]) -> OSStatus
}

private struct StyleFriendsDMOperationSecurityKeychain: StyleFriendsDMOperationKeychainServing {
    func add(_ query: [String: Any]) -> OSStatus { SecItemAdd(query as CFDictionary, nil) }
    func read(_ query: [String: Any]) -> StyleFriendsDMOperationKeychainRead {
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        let values: [Data]
        if let data = item as? Data { values = [data] }
        else if let data = item as? [Data] { values = data }
        else { values = [] }
        return .init(status: status, values: values)
    }
    func update(_ query: [String: Any], values: [String: Any]) -> OSStatus { SecItemUpdate(query as CFDictionary, values as CFDictionary) }
    func delete(_ query: [String: Any]) -> OSStatus { SecItemDelete(query as CFDictionary) }
}

/// This journal is intentionally separate from message presentation.  Its
/// callers must persist before an outbound request and treat every read/write
/// failure as an unknown outcome.  Keychain's item update/delete operations are
/// the local transition boundary; there is no UserDefaults or file fallback.
final class StyleFriendsDMOperationJournal: @unchecked Sendable, StyleFriendsAttachmentJournaling {
    static let shared = StyleFriendsDMOperationJournal()

    private let keychain: any StyleFriendsDMOperationKeychainServing

    private let service = "com.sabastine.stylematchai.stylefriends.dm.operation.v1"
    private let archiveService = "com.sabastine.stylematchai.stylefriends.dm.operation-archive.v1"
    private let keyService = "com.sabastine.stylematchai.stylefriends.dm.operation-key.v1"
    private let keyAccount = "device-only-hmac"
    private let maximumRecords = 32
    private let maximumRetries = 3

    init(keychain: any StyleFriendsDMOperationKeychainServing = StyleFriendsDMOperationSecurityKeychain()) {
        self.keychain = keychain
    }

    func create(
        accountEnvironmentTag: String,
        scopeTag: String,
        operationType: StyleFriendsDMOperationJournalRecord.OperationType,
        payloadFingerprint: String,
        now: Date = Date(),
        ttl: TimeInterval = 24 * 60 * 60
    ) throws -> StyleFriendsDMOperationJournalRecord {
        guard validTag(accountEnvironmentTag), validTag(scopeTag), validTag(payloadFingerprint), ttl > 0 else { throw StyleFriendsDMOperationJournalError.invalidRecord }
        try cleanup(now: now)
        guard try count() < maximumRecords else { throw StyleFriendsDMOperationJournalError.limitReached }
        let record = StyleFriendsDMOperationJournalRecord(
            schema: StyleFriendsDMOperationJournalRecord.schemaVersion,
            operationID: UUID(), accountEnvironmentTag: accountEnvironmentTag, scopeTag: scopeTag, operationType: operationType,
            payloadFingerprint: payloadFingerprint, phase: .created,
            createdAt: now, updatedAt: now, expiresAt: now.addingTimeInterval(ttl),
            reconciliationCount: 0, retryCount: 0, opaqueServerReference: nil
        )
        let data = try encode(record)
        var query = itemQuery(operationID: record.operationID)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        query[kSecAttrSynchronizable as String] = false
        let status = keychain.add(query)
        guard status == errSecSuccess else { throw StyleFriendsDMOperationJournalError.unavailable }
        return record
    }

    /// The only permitted handoff boundary for a newly-created operation.
    /// The callback cannot run until both durable creation and the submitted
    /// transition succeed, so a Keychain failure produces zero network work.
    func persistBeforeNetwork<Result>(
        accountEnvironmentTag: String,
        scopeTag: String,
        operationType: StyleFriendsDMOperationJournalRecord.OperationType,
        payloadFingerprint: String,
        perform: (StyleFriendsDMOperationContext) throws -> Result
    ) throws -> Result {
        let created = try create(accountEnvironmentTag: accountEnvironmentTag, scopeTag: scopeTag, operationType: operationType, payloadFingerprint: payloadFingerprint)
        let submitted = try transition(operationID: created.operationID, expectedScopeTag: scopeTag, to: operationType == .text ? .submitted : .preparingAttachment)
        return try perform(.init(record: submitted))
    }

    func load(operationID: UUID, expectedScopeTag: String, now: Date = Date()) throws -> StyleFriendsDMOperationJournalRecord? {
        var query = itemQuery(operationID: operationID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let read = keychain.read(query)
        let status = read.status
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = read.values.first else { throw StyleFriendsDMOperationJournalError.unavailable }
        let record = try decode(data)
        guard record.scopeTag == expectedScopeTag else { throw StyleFriendsDMOperationJournalError.scopeMismatch }
        if record.expiresAt <= now, [.committed, .notCommitted, .abandoned].contains(record.phase) {
            try delete(operationID: operationID); return nil
        }
        return record
    }

    @discardableResult
    func transition(
        operationID: UUID,
        expectedScopeTag: String,
        to phase: StyleFriendsDMOperationJournalRecord.Phase,
        opaqueServerReference: String? = nil,
        now: Date = Date()
    ) throws -> StyleFriendsDMOperationJournalRecord {
        guard var record = try load(operationID: operationID, expectedScopeTag: expectedScopeTag, now: now) else {
            throw StyleFriendsDMOperationJournalError.unavailable
        }
        guard canTransition(from: record.phase, to: phase) else { throw StyleFriendsDMOperationJournalError.invalidTransition }
        guard opaqueServerReference.map(validOpaqueReference) ?? true else { throw StyleFriendsDMOperationJournalError.invalidRecord }
        record.phase = phase
        record.updatedAt = now
        if phase == .reconciling { record.reconciliationCount += 1 }
        if phase == .submitted { record.retryCount += 1 }
        guard record.retryCount <= maximumRetries else { throw StyleFriendsDMOperationJournalError.invalidTransition }
        if let opaqueServerReference { record.opaqueServerReference = opaqueServerReference }
        let status = keychain.update(itemQuery(operationID: operationID), values: [kSecValueData as String: try encode(record)])
        guard status == errSecSuccess else { throw StyleFriendsDMOperationJournalError.unavailable }
        return record
    }


    /// Compatibility entry point for callers explicitly requiring expiry.
    func archiveExpiredUnknownAttachment(operationID: UUID, accountEnvironmentTag: String, expectedScopeTag: String, now: Date = Date()) throws {
        guard let record = try load(operationID: operationID, expectedScopeTag: expectedScopeTag, now: now),
              record.expiresAt <= now else { throw StyleFriendsDMOperationJournalError.invalidTransition }
        try archiveUnknownAttachment(operationID: operationID, accountEnvironmentTag: accountEnvironmentTag, expectedScopeTag: expectedScopeTag, now: now)
    }

    /// Explicit owner action only. Preserve the exact unknown record before
    /// releasing the local lock. Expiry is not evidence of remote cancellation.
    /// This is neither a delivery outcome nor remote cancellation or retry.
    func archiveUnknownAttachment(operationID: UUID, accountEnvironmentTag: String, expectedScopeTag: String, now: Date = Date()) throws {
        guard let record = try load(operationID: operationID, expectedScopeTag: expectedScopeTag, now: now),
              record.operationID == operationID,
              record.accountEnvironmentTag == accountEnvironmentTag else {
            throw StyleFriendsDMOperationJournalError.scopeMismatch
        }
        guard record.operationType == .preparedAttachment, record.phase == .unknown else {
            throw StyleFriendsDMOperationJournalError.invalidTransition
        }
        var archiveQuery = itemQuery(operationID: operationID)
        archiveQuery[kSecAttrService as String] = archiveService
        var readQuery = archiveQuery
        readQuery[kSecReturnData as String] = true
        readQuery[kSecMatchLimit as String] = kSecMatchLimitOne
        let prior = keychain.read(readQuery)
        var pendingQuery = itemQuery(operationID: operationID)
        pendingQuery[kSecReturnData as String] = true
        pendingQuery[kSecMatchLimit as String] = kSecMatchLimitOne
        let pending = keychain.read(pendingQuery)
        guard pending.status == errSecSuccess, pending.values.count == 1,
              let data = pending.values.first, try decode(data) == record else {
            throw StyleFriendsDMOperationJournalError.unavailable
        }
        if prior.status == errSecSuccess {
            guard let priorData = prior.values.first else { throw StyleFriendsDMOperationJournalError.unavailable }
            let archived = try decode(priorData)
            guard archived.operationID == operationID,
                  archived.accountEnvironmentTag == record.accountEnvironmentTag,
                  archived.scopeTag == record.scopeTag,
                  archived.payloadFingerprint == record.payloadFingerprint,
                  archived.createdAt == record.createdAt,
                  archived.operationType == .preparedAttachment,
                  archived.phase == .unknown else { throw StyleFriendsDMOperationJournalError.invalidRecord }
            guard keychain.update(archiveQuery, values: [kSecValueData as String: data]) == errSecSuccess else {
                throw StyleFriendsDMOperationJournalError.unavailable
            }
        } else {
            guard prior.status == errSecItemNotFound else { throw StyleFriendsDMOperationJournalError.unavailable }
            guard try allRecords(in: archiveService).count < maximumRecords else { throw StyleFriendsDMOperationJournalError.limitReached }
            var addQuery = archiveQuery
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard keychain.add(addQuery) == errSecSuccess else { throw StyleFriendsDMOperationJournalError.unavailable }
        }
        let verified = keychain.read(readQuery)
        guard verified.status == errSecSuccess, verified.values == [data] else {
            throw StyleFriendsDMOperationJournalError.unavailable
        }
        // Recheck the source before moving it out of the active journal.
        // A changed source stays locked; it is never replaced by an older copy.
        let unchanged = keychain.read(pendingQuery)
        guard unchanged.status == errSecSuccess, unchanged.values == [data] else {
            throw StyleFriendsDMOperationJournalError.unavailable
        }
        // If deletion fails, recovery stays locked and the verified archive
        // remains. Repeating the explicit action is safe after a partial write.
        try delete(operationID: operationID)
    }

    static func stoppableUnknownAttachments(_ records: [StyleFriendsDMOperationJournalRecord], accountEnvironmentTag: String, scopeTag: String) -> [UUID] {
        records.filter {
            $0.accountEnvironmentTag == accountEnvironmentTag && $0.scopeTag == scopeTag
                && $0.operationType == .preparedAttachment && $0.phase == .unknown
        }.map(\.operationID)
    }

    static func stoppableExpiredAttachments(_ records: [StyleFriendsDMOperationJournalRecord], accountEnvironmentTag: String, scopeTag: String, now: Date = Date()) -> [UUID] {
        records.filter {
            $0.accountEnvironmentTag == accountEnvironmentTag && $0.scopeTag == scopeTag
                && $0.operationType == .preparedAttachment && $0.phase == .unknown && $0.expiresAt <= now
        }.map(\.operationID)
    }

    func delete(operationID: UUID) throws {
        let status = keychain.delete(itemQuery(operationID: operationID))
        guard status == errSecSuccess || status == errSecItemNotFound else { throw StyleFriendsDMOperationJournalError.unavailable }
    }

    /// Account removal calls this with the newly derived scope tag; it cannot
    /// enumerate or delete another account's records by raw identifier.
    func deleteAll(accountEnvironmentTag: String) throws {
        let records = try allRecords()
        for record in records where record.accountEnvironmentTag == accountEnvironmentTag { try delete(operationID: record.operationID) }
        for record in try allRecords(in: archiveService) where record.accountEnvironmentTag == accountEnvironmentTag {
            var query = itemQuery(operationID: record.operationID)
            query[kSecAttrService as String] = archiveService
            let status = keychain.delete(query)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw StyleFriendsDMOperationJournalError.unavailable }
        }
    }

    /// Session recovery is account/environment-exact. Conversation references
    /// are never persisted; status is sender-scoped by operation ID.
    func unresolved(accountEnvironmentTag: String, now: Date = Date()) throws -> [StyleFriendsDMOperationJournalRecord] {
        try cleanup(now: now)
        return try allRecords().filter { record in
            record.accountEnvironmentTag == accountEnvironmentTag && ![.committed, .notCommitted, .abandoned].contains(record.phase)
        }
    }

    func scopeTag(account: String, environment: String, conversation: String) throws -> String {
        try digest("scope\u{1f}\(account)\u{1f}\(environment)\u{1f}\(conversation)")
    }
    func accountEnvironmentTag(account: String, environment: String) throws -> String { try digest("account-environment\u{1f}\(account)\u{1f}\(environment)") }

    func payloadFingerprint(type: StyleFriendsDMOperationJournalRecord.OperationType, immutablePayload: Data) throws -> String {
        try digest("payload\u{1f}\(type.rawValue)\u{1f}" + immutablePayload.base64EncodedString())
    }

    private func digest(_ input: String) throws -> String {
        let key = SymmetricKey(data: try hmacKey())
        return HMAC<SHA256>.authenticationCode(for: Data(input.utf8), using: key).map { String(format: "%02x", $0) }.joined()
    }

    private func hmacKey() throws -> Data {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keyService, kSecAttrAccount as String: keyAccount, kSecAttrSynchronizable as String: false, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        let read = keychain.read(query)
        let found = read.status
        if found == errSecSuccess, let data = read.values.first, data.count == 32 { return data }
        guard found == errSecItemNotFound else { throw StyleFriendsDMOperationJournalError.unavailable }
        var key = Data(count: 32)
        let randomStatus = key.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }
        guard randomStatus == errSecSuccess else { throw StyleFriendsDMOperationJournalError.unavailable }
        query.removeValue(forKey: kSecReturnData as String); query.removeValue(forKey: kSecMatchLimit as String)
        query[kSecValueData as String] = key
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard keychain.add(query) == errSecSuccess else { throw StyleFriendsDMOperationJournalError.unavailable }
        return key
    }

    private func allRecords(in selectedService: String? = nil) throws -> [StyleFriendsDMOperationJournalRecord] {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: selectedService ?? service, kSecAttrSynchronizable as String: false, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitAll]
        let read = keychain.read(query)
        let status = read.status
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess else { throw StyleFriendsDMOperationJournalError.unavailable }
        return try read.values.map(decode)
    }

    // Expiration ends retry eligibility, not delivery uncertainty. Keep the
    // bounded content-free lock until authoritative reconciliation resolves it
    // or the owner explicitly archives an expired unknown attachment.
    private func cleanup(now: Date) throws {
        for record in try allRecords() where record.expiresAt <= now && [.committed, .notCommitted, .abandoned].contains(record.phase) {
            try delete(operationID: record.operationID)
        }
    }
    private func count() throws -> Int { try allRecords().count }
    private func encode(_ record: StyleFriendsDMOperationJournalRecord) throws -> Data { try JSONEncoder().encode(record) }
    private func decode(_ data: Data) throws -> StyleFriendsDMOperationJournalRecord {
        guard let record = try? JSONDecoder().decode(StyleFriendsDMOperationJournalRecord.self, from: data), record.schema == StyleFriendsDMOperationJournalRecord.schemaVersion, validTag(record.accountEnvironmentTag), validTag(record.scopeTag), validTag(record.payloadFingerprint) else { throw StyleFriendsDMOperationJournalError.invalidRecord }
        return record
    }
    private func itemQuery(operationID: UUID) -> [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: operationID.uuidString, kSecAttrSynchronizable as String: false] }
    private func validTag(_ value: String) -> Bool { value.count == 64 && value.allSatisfy { $0.isHexDigit } }
    private func validOpaqueReference(_ value: String) -> Bool { value.count > 0 && value.count <= 256 && !value.contains("://") && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) }
    private func canTransition(from: StyleFriendsDMOperationJournalRecord.Phase, to: StyleFriendsDMOperationJournalRecord.Phase) -> Bool {
        if from == to { return true }
        switch (from, to) {
        case (.created, .reconciling), (.preparingAttachment, .reconciling),
             (.uploadingAttachment, .reconciling), (.finalizingAttachment, .reconciling): return true
        case (.created, .preparingAttachment), (.created, .submitted), (.created, .unknown),
             (.preparingAttachment, .uploadingAttachment), (.uploadingAttachment, .finalizingAttachment),
             (.finalizingAttachment, .submitted), (.submitted, .reconciling),
             (.reconciling, .committed), (.reconciling, .notCommitted), (.reconciling, .unknown),
             (.submitted, .unknown), (.unknown, .reconciling), (.created, .abandoned), (.unknown, .abandoned), (.notCommitted, .submitted): return true
        default: return false
        }
    }
}

/// Session-readiness recovery coordinator. It owns no payload and makes no
/// outbound mutation: its only network-capable collaborator is status lookup.
@MainActor
final class StyleFriendsDMOperationRecoveryCoordinator {
    enum Resolution: Equatable { case committed(UUID), notCommitted(UUID), unknown(UUID) }
    static let shared = StyleFriendsDMOperationRecoveryCoordinator()
    private let journal: StyleFriendsDMOperationJournal
    private var isReconciling = false

    init(journal: StyleFriendsDMOperationJournal = .shared) { self.journal = journal }

    /// Called only after the accepted account session has become available.
    /// It has no draft payload and cannot perform a send/upload mutation.
    func reconcileCurrentAuthenticatedSession(service: any StyleFriendsDMOperationStatusServing) async -> [Resolution] {
        guard let account = StyleMatchAccountSessionStore.load(),
              let accountScope = account.accountID ?? account.appleSubject,
              let environmentScope = account.endpointHost,
              let accountEnvironmentTag = try? journal.accountEnvironmentTag(account: accountScope, environment: environmentScope) else { return [] }
        return await reconcile(accountEnvironmentTag: accountEnvironmentTag, service: service)
    }

    func reconcile(
        accountEnvironmentTag: String,
        scopeTag: String? = nil,
        service: any StyleFriendsDMOperationStatusServing
    ) async -> [Resolution] {
        guard !isReconciling else { return [] }
        isReconciling = true
        defer { isReconciling = false }
        do {
            let records = try journal.unresolved(accountEnvironmentTag: accountEnvironmentTag)
                .filter { scopeTag == nil || $0.scopeTag == scopeTag }
            return await records.asyncMap { record in
                    let context = StyleFriendsDMOperationContext(record: record)
                    do {
                        // Reconciliation is observation, including after partial attachment
                        // work. Only an exact authoritative response can make it terminal.
                        _ = try journal.transition(operationID: context.operationID, expectedScopeTag: record.scopeTag, to: .reconciling)
                        let status = try await service.operationStatus(context: context)
                        guard status.operationID == context.operationID else {
                            _ = try? journal.transition(operationID: context.operationID, expectedScopeTag: record.scopeTag, to: .unknown)
                            return .unknown(context.operationID)
                        }
                        switch status.outcome {
                        case .committed:
                            try journal.delete(operationID: context.operationID)
                            return .committed(context.operationID)
                        case .notCommitted:
                            _ = try journal.transition(operationID: context.operationID, expectedScopeTag: record.scopeTag, to: .notCommitted)
                            return .notCommitted(context.operationID)
                        case .unknown:
                            _ = try? journal.transition(operationID: context.operationID, expectedScopeTag: record.scopeTag, to: .unknown)
                            return .unknown(context.operationID)
                        }
                    } catch {
                        _ = try? journal.transition(operationID: context.operationID, expectedScopeTag: record.scopeTag, to: .unknown)
                        return .unknown(context.operationID)
                    }
                }
        } catch { return [] }
    }
}

private extension Collection {
    func asyncMap<T>(_ transform: (Element) async -> T) async -> [T] {
        var result: [T] = []; result.reserveCapacity(count)
        for value in self { result.append(await transform(value)) }
        return result
    }
}
