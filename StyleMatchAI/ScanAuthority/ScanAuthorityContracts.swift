import Foundation

struct LocalScanRecordID: RawRepresentable, Hashable, Codable, Sendable {
    let rawValue: String

    init?(rawValue: String) {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 256 else { return nil }
        self.rawValue = value
    }
}

enum ScanSelection: Equatable, Sendable {
    case explicitHistorical(
        id: LocalScanRecordID,
        expected: ScanSnapshotIdentity?
    )
    case currentCompleted(
        id: LocalScanRecordID,
        expected: ScanSnapshotIdentity?
    )
    case latestValidCompleted

    var expectedIdentity: ScanSnapshotIdentity? {
        switch self {
        case .explicitHistorical(_, let expected),
             .currentCompleted(_, let expected):
            return expected
        case .latestValidCompleted:
            return nil
        }
    }
}

struct ScanGeneration: Codable, Equatable, Sendable {
    static let legacy = Self(recordRevision: 1, contextRevision: 1)

    let recordRevision: UInt64
    let contextRevision: UInt64

    var isValid: Bool { recordRevision > 0 && contextRevision > 0 }
}

struct ScanSnapshotIdentity: Codable, Equatable, Sendable {
    let localID: LocalScanRecordID
    let generation: ScanGeneration
    let contextFingerprint: String

    func isStale(comparedTo current: Self) -> Bool {
        localID != current.localID
            || generation != current.generation
            || contextFingerprint != current.contextFingerprint
    }
}

enum ScanAuthorityState: String, Codable, Equatable, Sendable {
    case completed
    case inProgress
    case failed
    case placeholder
    case deleted
    case quarantined
    case partial
    case corrupt
}

enum ScanAuthorityReason: String, Codable, Equatable, Sendable {
    case explicitHistorical
    case currentCompleted
    case latestValidCompleted
}

enum ScanLegacyAuthorityState: String, Codable, Equatable, Sendable {
    case versioned
    case transientLegacyGeneration
}

enum ScanImageReferenceState: String, Codable, Equatable, Sendable {
    case present
    case absent
}

struct ScanAuthority: @unchecked Sendable {
    let identity: ScanSnapshotIdentity
    let analysis: OutfitAnalysisResult
    let completedAt: Date?
    let completionOrdinal: UInt64?
    let selectedOccasion: Occasion?
    let state: ScanAuthorityState
    let reason: ScanAuthorityReason
    let legacyState: ScanLegacyAuthorityState
    let imageReferenceState: ScanImageReferenceState
}

enum ScanAuthorityError: Error, Equatable, Sendable {
    case noAuthoritativeScan
    case scanNotFound
    case scanInProgress
    case scanFailed
    case scanDeleted
    case scanQuarantined
    case scanPartial
    case scanCorrupt
    case unsupportedSchema
    case ambiguousLatest
    case generationMismatch
    case generationOverflow
    case accountChanged
    case sourceChanged
    case cancelled
}

enum ScanLoadResult: @unchecked Sendable {
    case authority(ScanAuthority)
    case failure(ScanAuthorityError)
}

struct ScanContainerBoundary: Equatable, Sendable {
    let accountScopeDigest: String
    let sourceRevision: String
}

struct OpaqueIntegrityReference: Equatable, Sendable {
    let value: UUID
}

enum ScanContainerIntegrity: Equatable, Sendable {
    case healthy
    case quarantined(reference: OpaqueIntegrityReference)
}

struct ScanContainerCapture: Sendable {
    let data: Data?
    let boundary: ScanContainerBoundary
    let integrity: ScanContainerIntegrity
}

protocol ScanRecordDataSource: Sendable {
    func capture() async throws -> ScanContainerCapture
    func currentBoundary() async throws -> ScanContainerBoundary
}

struct RemoteSafeScanReference: Codable, Equatable, Sendable {
    let value: UUID

    init(value: UUID) {
        self.value = value
    }
}
