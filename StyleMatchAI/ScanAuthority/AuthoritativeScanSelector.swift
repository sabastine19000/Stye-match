import Foundation

enum AuthoritativeScanSelector {
    static func select(
        _ selection: ScanSelection,
        from records: [DecodedStoredScan],
        deletedIDs: Set<LocalScanRecordID> = []
    ) -> Result<(DecodedStoredScan, ScanAuthorityReason), ScanAuthorityError> {
        switch selection {
        case .explicitHistorical(let id, _):
            return exact(id, reason: .explicitHistorical, records: records, deletedIDs: deletedIDs)
        case .currentCompleted(let id, _):
            return exact(id, reason: .currentCompleted, records: records, deletedIDs: deletedIDs)
        case .latestValidCompleted:
            return latest(records, deletedIDs: deletedIDs)
        }
    }

    private static func exact(
        _ id: LocalScanRecordID,
        reason: ScanAuthorityReason,
        records: [DecodedStoredScan],
        deletedIDs: Set<LocalScanRecordID>
    ) -> Result<(DecodedStoredScan, ScanAuthorityReason), ScanAuthorityError> {
        guard !deletedIDs.contains(id) else { return .failure(.scanDeleted) }
        guard let candidate = records.first(where: { $0.id == id }) else {
            return .failure(.scanNotFound)
        }
        if let error = exclusion(for: candidate.state) {
            return .failure(error)
        }
        return .success((candidate, reason))
    }

    private static func latest(
        _ records: [DecodedStoredScan],
        deletedIDs: Set<LocalScanRecordID>
    ) -> Result<(DecodedStoredScan, ScanAuthorityReason), ScanAuthorityError> {
        let candidates = records.filter {
            !deletedIDs.contains($0.id)
                && $0.state == .completed
                && $0.record.firstScannedAt != nil
        }
        guard !candidates.isEmpty else { return .failure(.noAuthoritativeScan) }
        let latestDate = candidates.compactMap(\.record.firstScannedAt).max()
        let tied = candidates.filter { $0.record.firstScannedAt == latestDate }
        if tied.count == 1, let result = tied.first {
            return .success((result, .latestValidCompleted))
        }

        let ordered = tied.compactMap { candidate -> (DecodedStoredScan, UInt64)? in
            guard let value = candidate.record.authorityMetadata?.completionOrdinal else {
                return nil
            }
            return (candidate, value)
        }
        guard ordered.count == tied.count,
              let maximum = ordered.map(\.1).max() else {
            return .failure(.ambiguousLatest)
        }
        let winners = ordered.filter { $0.1 == maximum }
        guard winners.count == 1, let result = winners.first?.0 else {
            return .failure(.ambiguousLatest)
        }
        return .success((result, .latestValidCompleted))
    }

    private static func exclusion(for state: ScanAuthorityState) -> ScanAuthorityError? {
        switch state {
        case .completed: return nil
        case .inProgress: return .scanInProgress
        case .failed: return .scanFailed
        case .placeholder: return .scanPartial
        case .deleted: return .scanDeleted
        case .quarantined: return .scanQuarantined
        case .partial: return .scanPartial
        case .corrupt: return .scanCorrupt
        }
    }
}
