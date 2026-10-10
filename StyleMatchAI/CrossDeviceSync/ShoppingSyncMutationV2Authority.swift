import Foundation

/// Minimal per-product V2 payload. It deliberately excludes all catalog,
/// price, retailer, affiliate, recommendation, and purchase data.
struct ShoppingSyncMutationV2Payload: Codable, Sendable { let productID: String }
enum ShoppingSyncMutationV2Error: Error, Equatable { case malformedProductID, malformedPayload, legacyImportAlreadySuperseded }

final class ShoppingSyncMutationV2Authority {
    private let store: ShoppingLocalStore
    private let mutations: SyncMutationV2Authority
    init(store: ShoppingLocalStore, mutationAuthority: SyncMutationV2Authority) { self.store = store; mutations = mutationAuthority }
    var pendingOutbox: [SyncMutationV2] { mutations.pendingOutbox }
    func bootstrap(remoteFloor: SyncMutationV2RemoteFloor) throws { try mutations.bootstrap(remoteFloor: remoteFloor) }
    static func normalizedProductID(_ value: String) throws -> String {
        let id = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-~")
        guard !id.isEmpty, id.count <= 128, id.unicodeScalars.allSatisfy(allowed.contains) else { throw ShoppingSyncMutationV2Error.malformedProductID }
        return id
    }
    static func recordID(kind: SyncMutationV2Kind, productID: String) throws -> String {
        guard kind == .favorite || kind == .watchListItem else { throw ShoppingSyncMutationV2Error.malformedProductID }
        return kind.recordIDPrefix + (try normalizedProductID(productID))
    }
    @discardableResult func setMembership(_ productID: String, kind: SyncMutationV2Kind, present: Bool) throws -> SyncMutationV2 {
        let id = try Self.normalizedProductID(productID); let record = try Self.recordID(kind: kind, productID: id)
        let tx = present ? try mutations.beginLive(recordID: record, kind: kind, payload: try JSONEncoder().encode(ShoppingSyncMutationV2Payload(productID: id))) : try mutations.beginTombstone(recordID: record, kind: kind)
        store.applyV2Membership(id, kind: kind, present: present); try mutations.markLocalApplied(transactionID: tx.id); try mutations.commit(transactionID: tx.id); try mutations.markUploadPending(transactionID: tx.id); return tx.mutation
    }
    func applyRemote(_ mutation: SyncMutationV2) throws -> SyncMutationV2Reconciler.Decision {
        guard mutation.kind == .favorite || mutation.kind == .watchListItem else { throw ShoppingSyncMutationV2Error.malformedProductID }
        let id = try Self.normalizedProductID(String(mutation.recordID.dropFirst(mutation.kind.recordIDPrefix.count)))
        guard try Self.recordID(kind: mutation.kind, productID: id) == mutation.recordID else { throw ShoppingSyncMutationV2Error.malformedProductID }
        if mutation.mutationKind == .live { guard let payload = try? JSONDecoder().decode(ShoppingSyncMutationV2Payload.self, from: mutation.payload), try Self.normalizedProductID(payload.productID) == id else { throw ShoppingSyncMutationV2Error.malformedPayload } }
        let decision = try mutations.observeAcceptedRemote(mutation); if decision == .useRemote { store.applyV2Membership(id, kind: mutation.kind, present: mutation.mutationKind == .live) }; return decision
    }
    @discardableResult func migrateLegacyRecordsOnce() throws -> [SyncMutationV2] {
        guard !mutations.hasCompletedLegacyImport(for: .favorite), !mutations.hasCompletedLegacyImport(for: .watchListItem), !mutations.hasV2Activity else { throw ShoppingSyncMutationV2Error.legacyImportAlreadySuperseded }
        let favorites = Set(store.savedFavorites.compactMap { try? Self.normalizedProductID($0) }); let watches = Set(store.saleAlertProductIDs.compactMap { try? Self.normalizedProductID($0) })
        let result = try favorites.sorted().map { try setMembership($0, kind: .favorite, present: true) } + watches.sorted().map { try setMembership($0, kind: .watchListItem, present: true) }
        try mutations.markLegacyImportCompleted(for: .favorite); try mutations.markLegacyImportCompleted(for: .watchListItem); return result
    }
    func acknowledge(_ acknowledgement: SyncMutationV2Acknowledgement) throws { try mutations.acknowledge(acknowledgement) }
}
