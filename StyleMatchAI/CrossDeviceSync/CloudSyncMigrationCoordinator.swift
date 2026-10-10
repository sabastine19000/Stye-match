import Foundation

/// Local-first migration state. It contains no raw store keys or broad
/// snapshots: authorities hand it already validated, typed records only.
final class CloudSyncMigrationCoordinator {
    enum Category: String, CaseIterable, Codable {
        case profile, closet, savedScans, savedScanImages, favorites, watchList, aiMemory
    }

    private let defaults: UserDefaults
    private let checkpointKey: String

    init(defaults: UserDefaults = .standard, accountScope: String) {
        self.defaults = defaults
        checkpointKey = "cloudSyncMigrationCheckpointsV1.\(accountScope)"
    }

    func pending(_ records: [PersistenceAuthorityRecord], category: Category) throws -> [PersistenceAuthorityRecord] {
        guard records.allSatisfy(valid) else { throw PersistenceAuthorityError.invalidRecord }
        let checkpoints = loadCheckpoints()
        return records.filter { checkpoints[$0.id] != $0.version }
    }

    /// Acknowledge only the exact object/version that CloudKit confirmed. A
    /// failed object is deliberately left pending without affecting siblings.
    func acknowledge(_ records: [PersistenceAuthorityRecord]) {
        var checkpoints = loadCheckpoints()
        for record in records where valid(record) { checkpoints[record.id] = record.version }
        saveCheckpoints(checkpoints)
    }

    func isComplete(required: [PersistenceAuthorityRecord]) -> Bool {
        let checkpoints = loadCheckpoints()
        return required.allSatisfy { checkpoints[$0.id] == $0.version }
    }

    func resetForAccountChange() { defaults.removeObject(forKey: checkpointKey) }

    private func valid(_ record: PersistenceAuthorityRecord) -> Bool {
        !record.id.isEmpty && !record.version.isEmpty && !record.payload.isEmpty
            && CloudSyncEligibility.allowedRecordKinds.contains(record.kind)
    }
    private func loadCheckpoints() -> [String: String] {
        guard let data = defaults.data(forKey: checkpointKey) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }
    private func saveCheckpoints(_ checkpoints: [String: String]) {
        defaults.set(try? JSONEncoder().encode(checkpoints), forKey: checkpointKey)
    }
}
