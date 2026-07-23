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

enum ScanCorrectionDisposition: String, Codable, Equatable, Sendable {
    case inferred
    case confirmed
    case corrected
    case rejected
    case cleared
    case uncertain
}

struct ScanPurposeAuthority: Codable, Equatable, @unchecked Sendable {
    static let inferred = Self(
        proposed: nil,
        confirmed: nil,
        rejected: [],
        disposition: .inferred,
        correctedAt: nil
    )

    let proposed: OutfitPurpose?
    let confirmed: OutfitPurpose?
    let rejected: [OutfitPurpose]
    let disposition: ScanCorrectionDisposition
    let correctedAt: Date?

    init(
        proposed: OutfitPurpose?,
        confirmed: OutfitPurpose?,
        rejected: [OutfitPurpose],
        disposition: ScanCorrectionDisposition,
        correctedAt: Date?
    ) {
        self.proposed = proposed
        self.confirmed = confirmed
        self.rejected = Dictionary(
            uniqueKeysWithValues: rejected.map { ($0.rawValue, $0) }
        ).values.sorted { $0.rawValue < $1.rawValue }
        self.disposition = disposition
        self.correctedAt = correctedAt
    }
}

struct ScanWorkplaceAuthority: Codable, Equatable, @unchecked Sendable {
    static let inferred = Self(
        proposed: nil,
        confirmed: nil,
        rejected: [],
        disposition: .inferred,
        correctedAt: nil
    )

    let proposed: WorkplaceProfile?
    let confirmed: WorkplaceProfile?
    let rejected: [WorkplaceProfile]
    let disposition: ScanCorrectionDisposition
    let correctedAt: Date?

    init(
        proposed: WorkplaceProfile?,
        confirmed: WorkplaceProfile?,
        rejected: [WorkplaceProfile],
        disposition: ScanCorrectionDisposition,
        correctedAt: Date?
    ) {
        self.proposed = proposed
        self.confirmed = confirmed
        self.rejected = Dictionary(
            uniqueKeysWithValues: rejected.map { ($0.rawValue, $0) }
        ).values.sorted { $0.rawValue < $1.rawValue }
        self.disposition = disposition
        self.correctedAt = correctedAt
    }
}

struct ScanBoundContext: Codable, Equatable, @unchecked Sendable {
    static let currentInputSchemaVersion = 1
    static let legacyDefault = Self(
        inputSchemaVersion: currentInputSchemaVersion,
        purpose: .inferred,
        workplace: .inferred,
        categoryDisposition: .inferred,
        occasionDisposition: .inferred,
        weather: .unknown
    )

    let inputSchemaVersion: Int
    let purpose: ScanPurposeAuthority
    let workplace: ScanWorkplaceAuthority
    let categoryDisposition: ScanCorrectionDisposition
    let occasionDisposition: ScanCorrectionDisposition
    let weather: WeatherContextReference
}

struct ScanInvalidationEpoch: Equatable, Sendable {
    let value: UInt64
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
    let scanBoundContext: ScanBoundContext
    let invalidationEpoch: ScanInvalidationEpoch
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
    case authorityInvalidated
    case invalidationEpochOverflow
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
