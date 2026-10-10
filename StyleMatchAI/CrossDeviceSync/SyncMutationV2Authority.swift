import Foundation
import CryptoKit

/// Version-two mutation records are deliberately separate from the existing
/// v1 CloudKit records. Category adapters opt in later; this foundation alone
/// cannot upload or apply Closet, Shopping, or AI Memory data.
enum SyncMutationV2Kind: String, Codable, CaseIterable, Sendable {
    case closetItem
    case favorite
    case watchListItem
    case aiMemory

    var recordIDPrefix: String {
        switch self {
        case .closetItem: return "closet:"
        case .favorite: return "favorite:"
        case .watchListItem: return "watch:"
        case .aiMemory: return "memory:"
        }
    }
}

enum SyncMutationV2MutationKind: String, Codable, Sendable { case live, tombstone }

struct SyncMutationV2Token: Codable, Equatable, Comparable, Sendable {
    let counter: UInt64
    let replicaID: UUID

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.counter == rhs.counter
            ? lhs.replicaID.uuidString < rhs.replicaID.uuidString
            : lhs.counter < rhs.counter
    }
}

enum SyncMutationV2Error: Error, Equatable {
    case unavailableCounterFloor
    case malformedRecordID
    case kindRecordIDMismatch
    case unsupportedSchema
    case malformedPayload
    case payloadHashMismatch
    case malformedTombstone
    case counterOverflow
    case integrityFailure
    case accountScopeMismatch
    case missingTransaction
    case invalidTransition
    case corruptPersistentState
}

struct SyncMutationV2: Codable, Equatable, Sendable, Identifiable {
    static let schemaVersion = 2

    let recordID: String
    var id: String { recordID }
    let kind: SyncMutationV2Kind
    let schemaVersion: Int
    let mutationKind: SyncMutationV2MutationKind
    let token: SyncMutationV2Token
    let payloadHash: String
    let payload: Data
    let persistenceOrigin: CloudSyncPersistenceOrigin

    static func live(recordID: String, kind: SyncMutationV2Kind, token: SyncMutationV2Token, payload: Data, persistenceOrigin: CloudSyncPersistenceOrigin = .customerPersistent) throws -> Self {
        let mutation = Self(recordID: recordID, kind: kind, schemaVersion: schemaVersion, mutationKind: .live, token: token, payloadHash: Self.hash(payload), payload: payload, persistenceOrigin: persistenceOrigin)
        try mutation.validate()
        return mutation
    }

    static func tombstone(recordID: String, kind: SyncMutationV2Kind, token: SyncMutationV2Token, persistenceOrigin: CloudSyncPersistenceOrigin = .customerPersistent) throws -> Self {
        let mutation = Self(recordID: recordID, kind: kind, schemaVersion: schemaVersion, mutationKind: .tombstone, token: token, payloadHash: "", payload: Data(), persistenceOrigin: persistenceOrigin)
        try mutation.validate()
        return mutation
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion else { throw SyncMutationV2Error.unsupportedSchema }
        guard Self.isValidRecordID(recordID) else { throw SyncMutationV2Error.malformedRecordID }
        guard recordID.hasPrefix(kind.recordIDPrefix) else { throw SyncMutationV2Error.kindRecordIDMismatch }
        switch mutationKind {
        case .live:
            guard !payload.isEmpty else { throw SyncMutationV2Error.malformedPayload }
            guard payloadHash == Self.hash(payload) else { throw SyncMutationV2Error.payloadHashMismatch }
        case .tombstone:
            guard payload.isEmpty, payloadHash.isEmpty else { throw SyncMutationV2Error.malformedTombstone }
        }
    }

    func canonicalDigest() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return Self.hash((try? encoder.encode(self)) ?? Data())
    }

    private static func isValidRecordID(_ value: String) -> Bool {
        guard !value.isEmpty, value.unicodeScalars.allSatisfy({ $0.value < 128 }) else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._:-")
        return value.unicodeScalars.allSatisfy(allowed.contains)
    }

    fileprivate static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

enum SyncMutationV2RecordRecognition: Equatable { case legacyV1, v2, unsupported }

enum SyncMutationV2Codec {
    static func recognize(schemaVersion: Int) -> SyncMutationV2RecordRecognition {
        switch schemaVersion {
        case CloudSyncRecord.currentSchemaVersion: return .legacyV1
        case SyncMutationV2.schemaVersion: return .v2
        default: return .unsupported
        }
    }

    static func encode(_ mutation: SyncMutationV2) throws -> Data {
        try mutation.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(mutation)
    }

    static func decode(_ data: Data) throws -> SyncMutationV2 {
        let mutation = try JSONDecoder().decode(SyncMutationV2.self, from: data)
        try mutation.validate()
        return mutation
    }
}

enum SyncMutationV2Reconciler {
    enum Decision: Equatable { case keepLocal, useRemote, identical }

    static func decision(local: SyncMutationV2, remote: SyncMutationV2) throws -> Decision {
        try local.validate(); try remote.validate()
        guard local.recordID == remote.recordID, local.kind == remote.kind else { throw SyncMutationV2Error.integrityFailure }
        if local.token == remote.token {
            guard local.canonicalDigest() == remote.canonicalDigest() else { throw SyncMutationV2Error.integrityFailure }
            return .identical
        }
        return local.token < remote.token ? .useRemote : .keepLocal
    }
}

enum SyncMutationV2JournalState: String, Codable, Sendable { case prepared, localApplied, committed, uploadPending, conflictNeedsReconciliation, supersededByRemote, integrityFailure, acknowledged }

/// A durable classification deliberately contains no CloudKit error text or
/// server diagnostic. It is sufficient to decide whether a transaction may
/// retry, needs typed reconciliation, or must remain fail-closed.
enum SyncMutationV2ConflictClassification: String, Codable, Sendable {
    case localMutationNewer
    case remoteMutationNewer
    case equalMutationCandidate
    case categoryReconciliationFailed
    case integrityFailure
}

enum SyncMutationV2ReconciliationStatus: String, Codable, Sendable {
    case notRequired
    case awaitingReconciliation
    case applied
    case failed
    case integrityFailure
}

/// The concrete adapters provide these closures at the future transport
/// boundary.  Keeping the cases typed prevents a social or arbitrary record
/// from being reconciled through the V2 mutation authority. Implementations
/// must be idempotent because a crash may occur after local application and
/// before the terminal journal marker is persisted.
enum SyncMutationV2ReconciliationHook {
    case closet((SyncMutationV2) throws -> Void)
    case aiMemory((SyncMutationV2) throws -> Void)
    case shoppingFavorite((SyncMutationV2) throws -> Void)
    case shoppingWatch((SyncMutationV2) throws -> Void)

    var kind: SyncMutationV2Kind {
        switch self {
        case .closet: return .closetItem
        case .aiMemory: return .aiMemory
        case .shoppingFavorite: return .favorite
        case .shoppingWatch: return .watchListItem
        }
    }

    func apply(_ mutation: SyncMutationV2) throws {
        switch self {
        case let .closet(apply), let .aiMemory(apply), let .shoppingFavorite(apply), let .shoppingWatch(apply):
            try apply(mutation)
        }
    }
}

struct SyncMutationV2Transaction: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let mutation: SyncMutationV2
    /// The mutation carries these values too; retaining them in the journal
    /// makes the recovery evidence explicit and protects future migrations.
    let accountScopeFingerprint: String
    let originalToken: SyncMutationV2Token
    let originalCanonicalDigest: String
    var state: SyncMutationV2JournalState
    var conflictAttempts: Int = 0
    var lastConflictClassification: SyncMutationV2ConflictClassification?
    var winningRemote: SyncMutationV2?
    var reconciliationStatus: SyncMutationV2ReconciliationStatus
    private enum CodingKeys: String, CodingKey { case id, mutation, accountScopeFingerprint, originalToken, originalCanonicalDigest, state, conflictAttempts, lastConflictClassification, winningRemote, reconciliationStatus }
    init(id: UUID, mutation: SyncMutationV2, accountScopeFingerprint: String, state: SyncMutationV2JournalState, conflictAttempts: Int = 0, lastConflictClassification: SyncMutationV2ConflictClassification? = nil, winningRemote: SyncMutationV2? = nil, reconciliationStatus: SyncMutationV2ReconciliationStatus = .notRequired) {
        self.id = id; self.mutation = mutation; self.accountScopeFingerprint = accountScopeFingerprint; self.originalToken = mutation.token; self.originalCanonicalDigest = mutation.canonicalDigest(); self.state = state; self.conflictAttempts = conflictAttempts; self.lastConflictClassification = lastConflictClassification; self.winningRemote = winningRemote; self.reconciliationStatus = reconciliationStatus
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id); mutation = try c.decode(SyncMutationV2.self, forKey: .mutation)
        accountScopeFingerprint = try c.decodeIfPresent(String.self, forKey: .accountScopeFingerprint) ?? ""
        originalToken = try c.decodeIfPresent(SyncMutationV2Token.self, forKey: .originalToken) ?? mutation.token
        originalCanonicalDigest = try c.decodeIfPresent(String.self, forKey: .originalCanonicalDigest) ?? mutation.canonicalDigest()
        state = try c.decode(SyncMutationV2JournalState.self, forKey: .state)
        conflictAttempts = try c.decodeIfPresent(Int.self, forKey: .conflictAttempts) ?? 0
        lastConflictClassification = try c.decodeIfPresent(SyncMutationV2ConflictClassification.self, forKey: .lastConflictClassification)
        winningRemote = try c.decodeIfPresent(SyncMutationV2.self, forKey: .winningRemote)
        reconciliationStatus = try c.decodeIfPresent(SyncMutationV2ReconciliationStatus.self, forKey: .reconciliationStatus) ?? .notRequired
    }
}

struct SyncMutationV2Acknowledgement: Codable, Equatable, Sendable {
    let recordID: String
    let token: SyncMutationV2Token
    let canonicalDigest: String

    init(recordID: String, token: SyncMutationV2Token, canonicalDigest: String) {
        self.recordID = recordID
        self.token = token
        self.canonicalDigest = canonicalDigest
    }

    init(mutation: SyncMutationV2) {
        recordID = mutation.recordID
        token = mutation.token
        canonicalDigest = mutation.canonicalDigest()
    }

    func matches(_ mutation: SyncMutationV2) -> Bool {
        recordID == mutation.recordID && token == mutation.token && canonicalDigest == mutation.canonicalDigest()
    }
}

enum SyncMutationV2RemoteFloor: Equatable, Sendable {
    case verified(UInt64)
    case unavailable
}

/// Persisted per private-iCloud-account authority. The scope token is hashed
/// for the local key and never copied into a transport mutation.
final class SyncMutationV2Authority {
    private struct State: Codable {
        let schemaVersion: Int
        let scopeFingerprint: String
        let replicaID: UUID
        var counter: UInt64
        var isBootstrapped: Bool
        var accepted: [String: SyncMutationV2]
        var transactions: [SyncMutationV2Transaction]
        /// Kept per-account with the journal.  A category can consume legacy
        /// input exactly once; a later v1 discovery can never silently become
        /// a second v2 import.
        var completedLegacyImports: Set<SyncMutationV2Kind>

        private enum CodingKeys: String, CodingKey {
            case schemaVersion, scopeFingerprint, replicaID, counter
            case isBootstrapped, accepted, transactions, completedLegacyImports
        }

        init(
            schemaVersion: Int,
            scopeFingerprint: String,
            replicaID: UUID,
            counter: UInt64,
            isBootstrapped: Bool,
            accepted: [String: SyncMutationV2],
            transactions: [SyncMutationV2Transaction],
            completedLegacyImports: Set<SyncMutationV2Kind> = []
        ) {
            self.schemaVersion = schemaVersion
            self.scopeFingerprint = scopeFingerprint
            self.replicaID = replicaID
            self.counter = counter
            self.isBootstrapped = isBootstrapped
            self.accepted = accepted
            self.transactions = transactions
            self.completedLegacyImports = completedLegacyImports
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
            scopeFingerprint = try values.decode(String.self, forKey: .scopeFingerprint)
            replicaID = try values.decode(UUID.self, forKey: .replicaID)
            counter = try values.decode(UInt64.self, forKey: .counter)
            isBootstrapped = try values.decode(Bool.self, forKey: .isBootstrapped)
            accepted = try values.decode([String: SyncMutationV2].self, forKey: .accepted)
            transactions = try values.decode([SyncMutationV2Transaction].self, forKey: .transactions)
            completedLegacyImports = try values.decodeIfPresent(Set<SyncMutationV2Kind>.self, forKey: .completedLegacyImports) ?? []
        }
    }

    private let defaults: UserDefaults
    private let scope: CloudSyncPrivateDatabaseIdentity
    private let key: String
    private var state: State

    init(defaults: UserDefaults = .standard, scope: CloudSyncPrivateDatabaseIdentity, replicaID: UUID = UUID()) throws {
        self.defaults = defaults
        self.scope = scope
        let fingerprint = SyncMutationV2.hash(Data(scope.stableAccountChangeToken.utf8))
        self.key = "cloudSyncMutationV2.\(fingerprint)"
        if let data = defaults.data(forKey: key) {
            guard let decoded = try? JSONDecoder().decode(State.self, from: data), decoded.schemaVersion == 1, decoded.scopeFingerprint == fingerprint else {
                throw SyncMutationV2Error.corruptPersistentState
            }
            self.state = decoded
        } else {
            self.state = State(schemaVersion: 1, scopeFingerprint: fingerprint, replicaID: replicaID, counter: 0, isBootstrapped: false, accepted: [:], transactions: [])
            try persist()
        }
    }

    var replicaID: UUID { state.replicaID }
    var counter: UInt64 { state.counter }
    var isBootstrapped: Bool { state.isBootstrapped }
    var hasV2Activity: Bool { !state.accepted.isEmpty || !state.transactions.isEmpty }
    var pendingOutbox: [SyncMutationV2] {
        state.transactions.filter { $0.state == .uploadPending }.map(\.mutation).sorted { $0.recordID < $1.recordID }
    }
    var journalTransactions: [SyncMutationV2Transaction] {
        state.transactions.sorted { $0.id.uuidString < $1.id.uuidString }
    }
    var recoverableTransactions: [SyncMutationV2Transaction] {
        state.transactions.filter { $0.state != .acknowledged }.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    func hasCompletedLegacyImport(for kind: SyncMutationV2Kind) -> Bool {
        state.completedLegacyImports.contains(kind)
    }

    func markLegacyImportCompleted(for kind: SyncMutationV2Kind) throws {
        state.completedLegacyImports.insert(kind)
        try persist()
    }

    /// The caller must have reconciled the current private database and passed
    /// its highest accepted v2 counter. `unavailable` intentionally leaves the
    /// authority unable to allocate mutations.
    func bootstrap(remoteFloor: SyncMutationV2RemoteFloor) throws {
        guard case let .verified(floor) = remoteFloor else { throw SyncMutationV2Error.unavailableCounterFloor }
        state.counter = max(state.counter, floor)
        state.isBootstrapped = true
        try persist()
    }

    @discardableResult
    func observeAcceptedRemote(_ mutation: SyncMutationV2) throws -> SyncMutationV2Reconciler.Decision {
        try mutation.validate()
        state.counter = max(state.counter, mutation.token.counter)
        if let existing = state.accepted[mutation.recordID] {
            switch try SyncMutationV2Reconciler.decision(local: existing, remote: mutation) {
            case .useRemote:
                state.accepted[mutation.recordID] = mutation
                try persist()
                return .useRemote
            case .keepLocal:
                try persist()
                return .keepLocal
            case .identical:
                try persist()
                return .identical
            }
        } else {
            state.accepted[mutation.recordID] = mutation
            try persist()
            return .useRemote
        }
    }

    func beginLive(recordID: String, kind: SyncMutationV2Kind, payload: Data, persistenceOrigin: CloudSyncPersistenceOrigin = .customerPersistent) throws -> SyncMutationV2Transaction {
        try begin(recordID: recordID, kind: kind, payload: payload, mutationKind: .live, persistenceOrigin: persistenceOrigin)
    }

    func beginTombstone(recordID: String, kind: SyncMutationV2Kind, persistenceOrigin: CloudSyncPersistenceOrigin = .customerPersistent) throws -> SyncMutationV2Transaction {
        try begin(recordID: recordID, kind: kind, payload: Data(), mutationKind: .tombstone, persistenceOrigin: persistenceOrigin)
    }

    func markLocalApplied(transactionID: UUID) throws { try transition(transactionID, from: .prepared, to: .localApplied) }
    func commit(transactionID: UUID) throws { try transition(transactionID, from: .localApplied, to: .committed) }
    func markUploadPending(transactionID: UUID) throws { try transition(transactionID, from: .committed, to: .uploadPending) }

    func acknowledge(_ acknowledgement: SyncMutationV2Acknowledgement) throws {
        guard let index = state.transactions.firstIndex(where: { acknowledgement.matches($0.mutation) }) else { return }
        guard state.transactions[index].state == .uploadPending else { throw SyncMutationV2Error.invalidTransition }
        state.transactions[index].state = .acknowledged
        try persist()
    }

    /// Engineering bound only. A retry needs an explicit fresh server-state
    /// confirmation and never creates or retokens a replacement mutation.
    static let maximumCASConflictAttempts = 3
    func recordCASConflict(
        transactionID: UUID,
        accountScope: CloudSyncPrivateDatabaseIdentity,
        observedRemote: SyncMutationV2?
    ) throws {
        let index = try validatedConflictIndex(transactionID: transactionID, accountScope: accountScope)
        let local = state.transactions[index].mutation
        var classification: SyncMutationV2ConflictClassification = .localMutationNewer
        if let observedRemote {
            try observedRemote.validate()
            guard observedRemote.recordID == local.recordID, observedRemote.kind == local.kind else {
                try persistIntegrityFailure(at: index, observedRemote: observedRemote)
                throw SyncMutationV2Error.integrityFailure
            }
            state.transactions[index].winningRemote = observedRemote
            if observedRemote.token == local.token {
                guard observedRemote.canonicalDigest() == local.canonicalDigest() else {
                    try persistIntegrityFailure(at: index, observedRemote: observedRemote)
                    throw SyncMutationV2Error.integrityFailure
                }
                classification = .equalMutationCandidate
            } else if local.token < observedRemote.token {
                classification = .remoteMutationNewer
            }
        }
        state.transactions[index].conflictAttempts += 1
        state.transactions[index].lastConflictClassification = classification
        state.transactions[index].reconciliationStatus = .awaitingReconciliation
        state.transactions[index].state = .conflictNeedsReconciliation
        try persist()
    }

    /// A transport may resume an existing local winner only after it has read
    /// fresh server state/change-tag evidence. The marker itself is not stored:
    /// it is transport diagnostic data, not durable product state.
    func authorizeRetryAfterFreshServerState(transactionID: UUID, accountScope: CloudSyncPrivateDatabaseIdentity) throws {
        let index = try validatedConflictIndex(transactionID: transactionID, accountScope: accountScope, requiredState: .conflictNeedsReconciliation)
        guard state.transactions[index].conflictAttempts < Self.maximumCASConflictAttempts,
              state.transactions[index].lastConflictClassification == .localMutationNewer else {
            throw SyncMutationV2Error.invalidTransition
        }
        state.transactions[index].reconciliationStatus = .notRequired
        state.transactions[index].state = .uploadPending
        try persist()
    }

    func markIntegrityFailure(transactionID: UUID, accountScope: CloudSyncPrivateDatabaseIdentity, observedRemote: SyncMutationV2?) throws {
        let index = try validatedConflictIndex(transactionID: transactionID, accountScope: accountScope)
        try persistIntegrityFailure(at: index, observedRemote: observedRemote)
    }

    /// Applies a verified newer remote record before terminally superseding the
    /// local transaction. If the typed application fails, the durable journal
    /// retains both identities and remains reconciliation-blocked.
    func supersedePendingMutation(
        transactionID: UUID,
        accountScope: CloudSyncPrivateDatabaseIdentity,
        winningRemote: SyncMutationV2,
        reconciliationHook: SyncMutationV2ReconciliationHook
    ) throws {
        try winningRemote.validate()
        let index = try validatedConflictIndex(transactionID: transactionID, accountScope: accountScope)
        let local = state.transactions[index].mutation
        guard winningRemote.recordID == local.recordID,
              winningRemote.kind == local.kind,
              reconciliationHook.kind == local.kind else {
            try persistIntegrityFailure(at: index, observedRemote: winningRemote)
            throw SyncMutationV2Error.integrityFailure
        }
        guard local.token < winningRemote.token else {
            if local.token == winningRemote.token, local.canonicalDigest() != winningRemote.canonicalDigest() {
                try persistIntegrityFailure(at: index, observedRemote: winningRemote)
            }
            throw SyncMutationV2Error.integrityFailure
        }

        state.transactions[index].winningRemote = winningRemote
        state.transactions[index].lastConflictClassification = .remoteMutationNewer
        state.transactions[index].reconciliationStatus = .awaitingReconciliation
        state.transactions[index].state = .conflictNeedsReconciliation
        try persist()
        do {
            try reconciliationHook.apply(winningRemote)
        } catch {
            state.transactions[index].reconciliationStatus = .failed
            state.transactions[index].lastConflictClassification = .categoryReconciliationFailed
            try persist()
            throw error
        }

        state.accepted[winningRemote.recordID] = winningRemote
        state.counter = max(state.counter, winningRemote.token.counter)
        state.transactions[index].reconciliationStatus = .applied
        state.transactions[index].state = .supersededByRemote
        try persist()
    }

    private func begin(recordID: String, kind: SyncMutationV2Kind, payload: Data, mutationKind: SyncMutationV2MutationKind, persistenceOrigin: CloudSyncPersistenceOrigin) throws -> SyncMutationV2Transaction {
        guard state.isBootstrapped else { throw SyncMutationV2Error.unavailableCounterFloor }
        guard state.counter < UInt64.max else { throw SyncMutationV2Error.counterOverflow }
        state.counter += 1
        let token = SyncMutationV2Token(counter: state.counter, replicaID: state.replicaID)
        let mutation: SyncMutationV2
        switch mutationKind {
        case .live: mutation = try .live(recordID: recordID, kind: kind, token: token, payload: payload, persistenceOrigin: persistenceOrigin)
        case .tombstone: mutation = try .tombstone(recordID: recordID, kind: kind, token: token, persistenceOrigin: persistenceOrigin)
        }
        if let existing = state.accepted[recordID], try SyncMutationV2Reconciler.decision(local: existing, remote: mutation) == .keepLocal {
            throw SyncMutationV2Error.integrityFailure
        }
        state.accepted[recordID] = mutation
        let transaction = SyncMutationV2Transaction(id: UUID(), mutation: mutation, accountScopeFingerprint: state.scopeFingerprint, state: .prepared)
        state.transactions.append(transaction)
        try persist()
        return transaction
    }

    private func transition(_ transactionID: UUID, from: SyncMutationV2JournalState, to: SyncMutationV2JournalState) throws {
        guard let index = state.transactions.firstIndex(where: { $0.id == transactionID }) else { throw SyncMutationV2Error.missingTransaction }
        guard state.transactions[index].state == from else { throw SyncMutationV2Error.invalidTransition }
        state.transactions[index].state = to
        try persist()
    }

    private func validatedConflictIndex(
        transactionID: UUID,
        accountScope: CloudSyncPrivateDatabaseIdentity,
        requiredState: SyncMutationV2JournalState? = nil
    ) throws -> Int {
        guard Self.scopeFingerprint(for: accountScope) == state.scopeFingerprint,
              let index = state.transactions.firstIndex(where: { $0.id == transactionID }),
              state.transactions[index].accountScopeFingerprint == state.scopeFingerprint else {
            throw SyncMutationV2Error.accountScopeMismatch
        }
        let validStates: Set<SyncMutationV2JournalState> = requiredState.map { Set([$0]) } ?? [.uploadPending, .conflictNeedsReconciliation]
        guard validStates.contains(state.transactions[index].state) else { throw SyncMutationV2Error.invalidTransition }
        return index
    }

    private func persistIntegrityFailure(at index: Int, observedRemote: SyncMutationV2?) throws {
        state.transactions[index].state = .integrityFailure
        state.transactions[index].winningRemote = observedRemote
        state.transactions[index].lastConflictClassification = .integrityFailure
        state.transactions[index].reconciliationStatus = .integrityFailure
        try persist()
    }

    private static func scopeFingerprint(for scope: CloudSyncPrivateDatabaseIdentity) -> String {
        SyncMutationV2.hash(Data(scope.stableAccountChangeToken.utf8))
    }

    private func persist() throws {
        guard let data = try? JSONEncoder().encode(state) else { throw SyncMutationV2Error.corruptPersistentState }
        defaults.set(data, forKey: key)
    }
}
