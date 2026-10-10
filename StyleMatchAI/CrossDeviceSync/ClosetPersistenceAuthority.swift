import Foundation

/// Read-only, local-only Closet facts. This deliberately excludes the item
/// name, size, notes, and persistent UUID from any eventual network DTO.
struct ClosetStylistFacts: Equatable, Sendable {
    let localRecordKey: UUID
    let category: String
    let color: String?
    let brand: String?
    let occasion: String?
}

/// Owns the closet key on behalf of sync. Transport receives only typed records.
final class ClosetPersistenceAuthority {
    private static let key = "closetItemsData"
    private static let tombstoneKey = "closetSyncTombstonesV1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func enumerate() throws -> [PersistenceAuthorityRecord] {
        try items().map { item in
            let payload = try JSONEncoder().encode(item)
            return PersistenceAuthorityRecord(id: item.id.uuidString, kind: .closetItem, payload: payload, version: digest(payload), updatedAt: .distantPast, isDeleted: false, persistenceOrigin: .customerPersistent)
        }
    }

    /// Uses the existing decoded Closet authority only. It performs no write,
    /// migration, backfill, or record transformation.
    func enumerateStylistFacts() throws -> [ClosetStylistFacts] {
        try items()
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map { item in
                ClosetStylistFacts(
                    localRecordKey: item.id,
                    category: item.category,
                    color: Self.optionalFact(item.color),
                    brand: Self.optionalFact(item.brand),
                    occasion: Self.optionalFact(item.occasion)
                )
            }
    }

    func apply(_ record: PersistenceAuthorityRecord) throws {
        guard record.kind == .closetItem, !record.isDeleted else { throw PersistenceAuthorityError.invalidRecord }
        let item = try JSONDecoder().decode(ClosetItem.self, from: record.payload)
        guard item.id.uuidString == record.id, record.version == digest(record.payload), tombstones()[record.id] == nil else { throw PersistenceAuthorityError.invalidRecord }
        var current = try items()
        if let index = current.firstIndex(where: { $0.id == item.id }) {
            let existing = try JSONEncoder().encode(current[index])
            if existing == record.payload { return }
            throw PersistenceAuthorityError.conflict
        }
        current.append(item); try save(current)
    }

    func applyTombstone(id: String, version: String) throws {
        guard !id.isEmpty, !version.isEmpty else { throw PersistenceAuthorityError.invalidRecord }
        var current = try items(); var removed = false
        current.removeAll { if $0.id.uuidString == id { removed = true; return true }; return false }
        if removed { try save(current) }
        var marks = tombstones(); marks[id] = version
        defaults.set(try JSONEncoder().encode(marks), forKey: Self.tombstoneKey)
    }

    /// V2 is the only caller allowed to replace or remove an existing Closet
    /// item during cross-device reconciliation. Its Lamport-token decision is
    /// made before this local persistence boundary is entered.
    func applyV2Live(_ item: ClosetItem) throws {
        var current = try items()
        if let index = current.firstIndex(where: { $0.id == item.id }) {
            current[index] = item
        } else {
            current.append(item)
        }
        try save(current)
    }

    func applyV2Tombstone(id: UUID) throws {
        var current = try items()
        current.removeAll { $0.id == id }
        try save(current)
    }

    private func items() throws -> [ClosetItem] {
        guard let data = defaults.data(forKey: Self.key), !data.isEmpty else { return [] }
        guard let decoded = try? JSONDecoder().decode([ClosetItem].self, from: data) else { throw PersistenceAuthorityError.invalidRecord }
        return decoded
    }
    private static func optionalFact(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    private func save(_ values: [ClosetItem]) throws { defaults.set(try JSONEncoder().encode(values), forKey: Self.key) }
    private func tombstones() -> [String: String] { guard let data = defaults.data(forKey: Self.tombstoneKey) else { return [:] }; return (try? JSONDecoder().decode([String:String].self, from: data)) ?? [:] }
    private func digest(_ data: Data) -> String { data.base64EncodedString() }
}
