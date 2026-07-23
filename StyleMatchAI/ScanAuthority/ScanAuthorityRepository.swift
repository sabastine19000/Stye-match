import Foundation

actor ScanAuthorityRepository {
    private let source: any ScanRecordDataSource
    private var deletedIDs: Set<LocalScanRecordID> = []
    private var quarantinedIDs: Set<LocalScanRecordID> = []
    private var invalidationEpoch: UInt64
    private var invalidationEpochExhausted = false

    init(
        source: any ScanRecordDataSource,
        initialInvalidationEpoch: UInt64 = 0
    ) {
        self.source = source
        invalidationEpoch = initialInvalidationEpoch
    }

    @discardableResult
    func markDeletedForCurrentProcess(
        _ id: LocalScanRecordID
    ) -> ScanAuthorityError? {
        deletedIDs.insert(id)
        return advanceInvalidationEpoch()
    }

    @discardableResult
    func markQuarantinedForCurrentProcess(
        _ id: LocalScanRecordID
    ) -> ScanAuthorityError? {
        quarantinedIDs.insert(id)
        return advanceInvalidationEpoch()
    }

    @discardableResult
    func invalidateForAuthorityChange() -> ScanAuthorityError? {
        advanceInvalidationEpoch()
    }

    func resolve(_ selection: ScanSelection) async -> ScanLoadResult {
        if Task.isCancelled { return .failure(.cancelled) }
        guard !invalidationEpochExhausted else {
            return .failure(.invalidationEpochOverflow)
        }
        let capturedEpoch = invalidationEpoch
        let capture: ScanContainerCapture
        do {
            capture = try await source.capture()
        } catch is CancellationError {
            return .failure(.cancelled)
        } catch {
            return .failure(.scanCorrupt)
        }
        if let failure = invalidationFailure(since: capturedEpoch) {
            return .failure(failure)
        }
        guard case .healthy = capture.integrity else {
            return .failure(.scanQuarantined)
        }
        if Task.isCancelled { return .failure(.cancelled) }

        let records: [DecodedStoredScan]
        switch StoredScanRecordDecoder.decode(capture.data) {
        case .success(let value): records = value
        case .failure(let error): return .failure(error)
        }
        let selected: (DecodedStoredScan, ScanAuthorityReason)
        if let quarantinedID = selection.explicitID,
           quarantinedIDs.contains(quarantinedID) {
            return .failure(.scanQuarantined)
        }
        switch AuthoritativeScanSelector.select(
            selection,
            from: records.filter { !quarantinedIDs.contains($0.id) },
            deletedIDs: deletedIDs
        ) {
        case .success(let value): selected = value
        case .failure(let error): return .failure(error)
        }
        guard let analysis = selected.0.record.analysis else {
            return .failure(.scanPartial)
        }
        if let storedScore = selected.0.record.score,
           storedScore != analysis.score {
            return .failure(.scanCorrupt)
        }
        let generation: ScanGeneration
        let fingerprint: String
        let legacyState: ScanLegacyAuthorityState
        switch ScanGenerationPolicy.resolvedGeneration(
            recordID: selected.0.id,
            metadata: selected.0.record.authorityMetadata,
            record: selected.0.record
        ) {
        case .success(let value):
            (generation, fingerprint, legacyState) = value
        case .failure(let error):
            return .failure(error)
        }
        let identity = ScanSnapshotIdentity(
            localID: selected.0.id,
            generation: generation,
            contextFingerprint: fingerprint
        )
        if let expected = selection.expectedIdentity,
           expected != identity {
            return .failure(.generationMismatch)
        }

        if Task.isCancelled { return .failure(.cancelled) }
        let boundary: ScanContainerBoundary
        do {
            boundary = try await source.currentBoundary()
        } catch is CancellationError {
            return .failure(.cancelled)
        } catch {
            return .failure(.sourceChanged)
        }
        if let failure = invalidationFailure(
            since: capturedEpoch,
            selectedID: selected.0.id
        ) {
            return .failure(failure)
        }
        guard boundary.accountScopeDigest == capture.boundary.accountScopeDigest else {
            return .failure(.accountChanged)
        }
        guard boundary.sourceRevision == capture.boundary.sourceRevision else {
            return .failure(.sourceChanged)
        }
        if Task.isCancelled { return .failure(.cancelled) }
        switch AuthoritativeScanSelector.select(
            selection,
            from: records.filter { !quarantinedIDs.contains($0.id) },
            deletedIDs: deletedIDs
        ) {
        case .success(let current)
            where current.0.id == selected.0.id && current.1 == selected.1:
            break
        case .failure(let error):
            return .failure(error)
        default:
            return .failure(.authorityInvalidated)
        }

        return .authority(ScanAuthority(
            identity: identity,
            analysis: analysis,
            completedAt: selected.0.record.firstScannedAt,
            completionOrdinal: selected.0.record.authorityMetadata?.completionOrdinal,
            selectedOccasion: selected.0.record.occasion,
            state: .completed,
            reason: selected.1,
            legacyState: legacyState,
            imageReferenceState: selected.0.record.thumbnailData == nil ? .absent : .present,
            scanBoundContext: selected.0.record.scanBoundContext ?? .legacyDefault,
            invalidationEpoch: ScanInvalidationEpoch(value: capturedEpoch)
        ))
    }

    private func advanceInvalidationEpoch() -> ScanAuthorityError? {
        guard !invalidationEpochExhausted else {
            return .invalidationEpochOverflow
        }
        let (next, overflow) = invalidationEpoch.addingReportingOverflow(1)
        guard !overflow else {
            invalidationEpochExhausted = true
            return .invalidationEpochOverflow
        }
        invalidationEpoch = next
        return nil
    }

    private func invalidationFailure(
        since capturedEpoch: UInt64,
        selectedID: LocalScanRecordID? = nil
    ) -> ScanAuthorityError? {
        if invalidationEpochExhausted {
            return .invalidationEpochOverflow
        }
        if let selectedID {
            if deletedIDs.contains(selectedID) {
                return .scanDeleted
            }
            if quarantinedIDs.contains(selectedID) {
                return .scanQuarantined
            }
        }
        return invalidationEpoch == capturedEpoch ? nil : .authorityInvalidated
    }
}

private extension ScanSelection {
    var explicitID: LocalScanRecordID? {
        switch self {
        case .explicitHistorical(let id, _), .currentCompleted(let id, _):
            return id
        case .latestValidCompleted:
            return nil
        }
    }
}
