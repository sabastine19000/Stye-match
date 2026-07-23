import Foundation

actor ScanAuthorityRepository {
    private let source: any ScanRecordDataSource
    private var deletedIDs: Set<LocalScanRecordID> = []

    init(source: any ScanRecordDataSource) {
        self.source = source
    }

    func markDeletedForCurrentProcess(_ id: LocalScanRecordID) {
        deletedIDs.insert(id)
    }

    func resolve(_ selection: ScanSelection) async -> ScanLoadResult {
        if Task.isCancelled { return .failure(.cancelled) }
        let capture: ScanContainerCapture
        do {
            capture = try await source.capture()
        } catch is CancellationError {
            return .failure(.cancelled)
        } catch {
            return .failure(.scanCorrupt)
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
        switch AuthoritativeScanSelector.select(
            selection,
            from: records,
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
            metadata: selected.0.record.authorityMetadata,
            analysis: analysis,
            occasion: selected.0.record.occasion
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
        guard boundary.accountScopeDigest == capture.boundary.accountScopeDigest else {
            return .failure(.accountChanged)
        }
        guard boundary.sourceRevision == capture.boundary.sourceRevision else {
            return .failure(.sourceChanged)
        }
        if Task.isCancelled { return .failure(.cancelled) }

        return .authority(ScanAuthority(
            identity: identity,
            analysis: analysis,
            completedAt: selected.0.record.firstScannedAt,
            completionOrdinal: selected.0.record.authorityMetadata?.completionOrdinal,
            selectedOccasion: selected.0.record.occasion,
            state: .completed,
            reason: selected.1,
            legacyState: legacyState,
            imageReferenceState: selected.0.record.thumbnailData == nil ? .absent : .present
        ))
    }
}
