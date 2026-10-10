import Foundation

/// Typed payload carried by V2 Closet live mutations. `ClosetItem` remains the
/// sole garment-ownership authority; this envelope adds no inferred fields.
struct ClosetSyncMutationV2Payload: Codable, Sendable {
    let item: ClosetItem
}

enum ClosetSyncMutationV2Error: Error, Equatable {
    case malformedRecordID
    case malformedPayload
    case legacyImportAlreadySuperseded
    case invalidRecoveryMutation
}

/// The only V2 route for sync-eligible Closet changes. This adapter deliberately
/// has no CloudKit client: transport and customer activation remain separately
/// gated. It provides durable local journal/outbox evidence before local state
/// is considered sync-complete.
final class ClosetSyncMutationV2Authority {
    private let closet: ClosetPersistenceAuthority
    private let mutationAuthority: SyncMutationV2Authority

    init(closet: ClosetPersistenceAuthority, mutationAuthority: SyncMutationV2Authority) {
        self.closet = closet
        self.mutationAuthority = mutationAuthority
    }

    var pendingOutbox: [SyncMutationV2] { mutationAuthority.pendingOutbox }
    var isBootstrapped: Bool { mutationAuthority.isBootstrapped }

    func bootstrap(remoteFloor: SyncMutationV2RemoteFloor) throws {
        try mutationAuthority.bootstrap(remoteFloor: remoteFloor)
    }

    @discardableResult
    func createOrEdit(_ item: ClosetItem) throws -> SyncMutationV2 {
        let recordID = try Self.recordID(for: item.id)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let payload = try encoder.encode(ClosetSyncMutationV2Payload(item: item))
        let transaction = try mutationAuthority.beginLive(recordID: recordID, kind: .closetItem, payload: payload)
        try closet.applyV2Live(item)
        try finalizeLocal(transaction)
        return transaction.mutation
    }

    @discardableResult
    func delete(id: UUID) throws -> SyncMutationV2 {
        let transaction = try mutationAuthority.beginTombstone(recordID: try Self.recordID(for: id), kind: .closetItem)
        try closet.applyV2Tombstone(id: id)
        try finalizeLocal(transaction)
        return transaction.mutation
    }

    /// Applies an accepted V2 remote decision only. A stale remote live or
    /// tombstone never reaches the local Closet store.
    func applyRemote(_ mutation: SyncMutationV2) throws -> SyncMutationV2Reconciler.Decision {
        guard mutation.kind == .closetItem else { throw ClosetSyncMutationV2Error.malformedRecordID }
        let itemID = try Self.itemID(from: mutation.recordID)
        let decision = try mutationAuthority.observeAcceptedRemote(mutation)
        guard decision == .useRemote else { return decision }
        switch mutation.mutationKind {
        case .live:
            guard let payload = try? JSONDecoder().decode(ClosetSyncMutationV2Payload.self, from: mutation.payload), payload.item.id == itemID else {
                throw ClosetSyncMutationV2Error.malformedPayload
            }
            try closet.applyV2Live(payload.item)
        case .tombstone:
            try closet.applyV2Tombstone(id: itemID)
        }
        return decision
    }

    /// Imports v1 Closet rows only before any V2 activity exists. Every import
    /// becomes a V2 live mutation, so an old client cannot later overwrite V2
    /// semantics through repeated migration.
    @discardableResult
    func migrateLegacyRecordsOnce() throws -> [SyncMutationV2] {
        guard !mutationAuthority.hasCompletedLegacyImport(for: .closetItem), !mutationAuthority.hasV2Activity else {
            throw ClosetSyncMutationV2Error.legacyImportAlreadySuperseded
        }
        let imported = try closet.enumerate().map { record in
            guard let item = try? JSONDecoder().decode(ClosetItem.self, from: record.payload) else {
                throw ClosetSyncMutationV2Error.malformedPayload
            }
            return try createOrEdit(item)
        }
        try mutationAuthority.markLegacyImportCompleted(for: .closetItem)
        return imported
    }

    /// Replays only journaled Closet transitions after a crash. The mutation
    /// token and payload are never regenerated. A prepared transaction is
    /// reapplied idempotently before it becomes uploadable; later states only
    /// advance their durable journal marker.
    func recoverAfterRelaunch() throws {
        for transaction in mutationAuthority.recoverableTransactions {
            guard transaction.mutation.kind == .closetItem else { continue }
            switch transaction.state {
            case .prepared:
                try applyLocally(transaction.mutation)
                try mutationAuthority.markLocalApplied(transactionID: transaction.id)
                try mutationAuthority.commit(transactionID: transaction.id)
                try mutationAuthority.markUploadPending(transactionID: transaction.id)
            case .localApplied:
                try mutationAuthority.commit(transactionID: transaction.id)
                try mutationAuthority.markUploadPending(transactionID: transaction.id)
            case .committed:
                try mutationAuthority.markUploadPending(transactionID: transaction.id)
            case .uploadPending, .conflictNeedsReconciliation, .supersededByRemote, .integrityFailure, .acknowledged:
                break
            }
        }
    }

    func acknowledge(_ acknowledgement: SyncMutationV2Acknowledgement) throws {
        try mutationAuthority.acknowledge(acknowledgement)
    }

    static func recordID(for itemUUID: UUID) throws -> String {
        let value = "closet:\(itemUUID.uuidString.lowercased())"
        guard (try? itemID(from: value)) != nil else { throw ClosetSyncMutationV2Error.malformedRecordID }
        return value
    }

    static func itemID(from recordID: String) throws -> UUID {
        guard recordID.hasPrefix("closet:"), let id = UUID(uuidString: String(recordID.dropFirst("closet:".count))) else {
            throw ClosetSyncMutationV2Error.malformedRecordID
        }
        return id
    }

    private func finalizeLocal(_ transaction: SyncMutationV2Transaction) throws {
        try mutationAuthority.markLocalApplied(transactionID: transaction.id)
        try mutationAuthority.commit(transactionID: transaction.id)
        try mutationAuthority.markUploadPending(transactionID: transaction.id)
    }

    private func applyLocally(_ mutation: SyncMutationV2) throws {
        let itemID = try Self.itemID(from: mutation.recordID)
        switch mutation.mutationKind {
        case .live:
            guard let payload = try? JSONDecoder().decode(ClosetSyncMutationV2Payload.self, from: mutation.payload), payload.item.id == itemID else {
                throw ClosetSyncMutationV2Error.invalidRecoveryMutation
            }
            try closet.applyV2Live(payload.item)
        case .tombstone:
            try closet.applyV2Tombstone(id: itemID)
        }
    }
}
