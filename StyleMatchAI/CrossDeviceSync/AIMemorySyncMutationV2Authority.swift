import Foundation

struct AIMemorySyncMutationV2Payload: Codable, Sendable { let memory: AIPersistentMemory }

enum AIMemorySyncMutationV2Error: Error, Equatable { case malformedRecordID, ineligibleMemory, malformedPayload, legacyImportAlreadySuperseded }

/// V2 source adapter for user-confirmed persistent AI Memory only. It has no
/// transport and does not enable customer Cloud Sync.
final class AIMemorySyncMutationV2Authority {
    private let store: AIPersistentMemoryStore
    private let mutations: SyncMutationV2Authority
    init(store: AIPersistentMemoryStore, mutationAuthority: SyncMutationV2Authority) { self.store = store; mutations = mutationAuthority }
    var pendingOutbox: [SyncMutationV2] { mutations.pendingOutbox }
    func bootstrap(remoteFloor: SyncMutationV2RemoteFloor) throws { try mutations.bootstrap(remoteFloor: remoteFloor) }

    @discardableResult func createOrEdit(_ memory: AIPersistentMemory) throws -> SyncMutationV2 {
        try validate(memory)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let transaction = try mutations.beginLive(recordID: try Self.recordID(for: memory.id), kind: .aiMemory, payload: try encoder.encode(AIMemorySyncMutationV2Payload(memory: memory)), persistenceOrigin: .explicitlySavedAIMemory)
        try store.applyV2Live(memory); try finalize(transaction); return transaction.mutation
    }
    @discardableResult func delete(id: UUID) throws -> SyncMutationV2 {
        let transaction = try mutations.beginTombstone(recordID: try Self.recordID(for: id), kind: .aiMemory, persistenceOrigin: .explicitlySavedAIMemory)
        try store.applyV2Tombstone(id: id); try finalize(transaction); return transaction.mutation
    }
    func applyRemote(_ mutation: SyncMutationV2) throws -> SyncMutationV2Reconciler.Decision {
        guard mutation.kind == .aiMemory, mutation.persistenceOrigin == .explicitlySavedAIMemory else { throw AIMemorySyncMutationV2Error.malformedRecordID }
        let id = try Self.memoryID(from: mutation.recordID)
        let decision = try mutations.observeAcceptedRemote(mutation); guard decision == .useRemote else { return decision }
        if mutation.mutationKind == .tombstone { try store.applyV2Tombstone(id: id) }
        else { guard let payload = try? JSONDecoder().decode(AIMemorySyncMutationV2Payload.self, from: mutation.payload), payload.memory.id == id else { throw AIMemorySyncMutationV2Error.malformedPayload }; try validate(payload.memory); try store.applyV2Live(payload.memory) }
        return decision
    }
    @discardableResult func migrateLegacyRecordsOnce() throws -> [SyncMutationV2] {
        guard !mutations.hasCompletedLegacyImport(for: .aiMemory), !mutations.hasV2Activity else { throw AIMemorySyncMutationV2Error.legacyImportAlreadySuperseded }
        let imported = try store.exportRecords().map(createOrEdit); try mutations.markLegacyImportCompleted(for: .aiMemory); return imported
    }
    func acknowledge(_ acknowledgement: SyncMutationV2Acknowledgement) throws { try mutations.acknowledge(acknowledgement) }
    static func recordID(for id: UUID) throws -> String { let value = "memory:\(id.uuidString.lowercased())"; guard (try? memoryID(from: value)) != nil else { throw AIMemorySyncMutationV2Error.malformedRecordID }; return value }
    static func memoryID(from recordID: String) throws -> UUID { guard recordID.hasPrefix("memory:"), let id = UUID(uuidString: String(recordID.dropFirst("memory:".count))) else { throw AIMemorySyncMutationV2Error.malformedRecordID }; return id }
    private func validate(_ memory: AIPersistentMemory) throws { guard memory.schemaVersion == AIPersistentMemory.currentSchemaVersion, memory.confirmationState == .confirmed, memory.invalidationState == .active else { throw AIMemorySyncMutationV2Error.ineligibleMemory } }
    private func finalize(_ transaction: SyncMutationV2Transaction) throws { try mutations.markLocalApplied(transactionID: transaction.id); try mutations.commit(transactionID: transaction.id); try mutations.markUploadPending(transactionID: transaction.id) }
}
