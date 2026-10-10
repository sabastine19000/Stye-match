import CloudKit
import Foundation

/// The outbound private-CloudKit write sequence is callable only by the
/// isolated Debug 18036 validation artifact or the signed 18049 OwnerBeta
/// acceptance lane. App Store/Release customer builds remain fail-closed.
struct CloudSyncOwnerValidationConfiguration: Equatable, Sendable {
    let buildNumber: String
    let isDebugBuild: Bool
    var isOwnerBetaBuild: Bool = false

    var isEnabled: Bool {
        (buildNumber == "18036" && isDebugBuild && !CloudSyncProductContract.customerPublicActivationEnabled)
            || (buildNumber == "18049" && isOwnerBetaBuild && CloudSyncProductContract.ownerBetaActivationEnabled)
    }

    /// Builds 18037 and 18038 may inspect and reconcile existing private
    /// changes solely to surface a bounded local diagnostic. They never
    /// enable the outbound owner-validation write sequence. This explicit
    /// allowlist is Debug-only and does not activate customer/public Cloud
    /// Sync.
    var allowsInboundDiagnosticReconciliation: Bool {
        (isDebugBuild
            && !CloudSyncProductContract.customerPublicActivationEnabled
            && ["18036", "18037", "18038"].contains(buildNumber))
            || (buildNumber == "18049"
                && isOwnerBetaBuild
                && CloudSyncProductContract.ownerBetaActivationEnabled)
    }

    static var runtime: CloudSyncOwnerValidationConfiguration {
        #if DEBUG
        let isDebugBuild = true
        #else
        let isDebugBuild = false
        #endif
        #if OWNER_BETA
        let isOwnerBetaBuild = true
        #else
        let isOwnerBetaBuild = false
        #endif
        return CloudSyncOwnerValidationConfiguration(
            buildNumber: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
            isDebugBuild: isDebugBuild,
            isOwnerBetaBuild: isOwnerBetaBuild
        )
    }
}

protocol CloudSyncOwnerValidationTransport {
    func accountStatus() async throws -> CKAccountStatus
    /// Private CloudKit identity only; never a Sign in with Apple subject.
    func privateDatabaseIdentity() async throws -> CloudSyncPrivateDatabaseIdentity?
    func save(_ record: CloudSyncRecord, asset: CloudSyncAssetUpload?) async throws -> CloudSyncRecord
    func fetch(recordID: String) async throws -> CloudSyncRecord
    func fetchAsset(recordID: String) async throws -> CloudSyncAssetDownload
}

extension CloudSyncCloudKitPrivateDatabaseClient: CloudSyncOwnerValidationTransport {
    func fetch(recordID: String) async throws -> CloudSyncRecord {
        guard let record = try await fetch(recordIDs: [recordID]).first else {
            throw PersistenceAuthorityError.missing
        }
        return record
    }
}

/// Authority-owned local operations. The coordinator never reads a backing
/// key, image directory, AI context, or account subject itself.
struct CloudSyncOwnerValidationSources {
    let profile: () throws -> PersistenceAuthorityRecord
    let savedScans: () throws -> [SavedScanSyncDTO]
    let savedScanImage: (String) throws -> (asset: SavedScanImageAsset, data: Data, sha256: String, byteCount: Int64)?
    let closet: () throws -> [PersistenceAuthorityRecord]
    let shopping: () throws -> [PersistenceAuthorityRecord]
    let aiMemory: () throws -> [PersistenceAuthorityRecord]
    let apply: (PersistenceAuthorityRecord) throws -> Void
    let applySavedScanImage: (SavedScanSyncDTO, SavedScanImageAsset, Data, String, Int64) throws -> Void

    static func live() -> CloudSyncOwnerValidationSources {
        let profileStore = ProfileStore()
        let savedScans = SavedScanPersistenceAuthority()
        let closet = ClosetPersistenceAuthority()
        let shopping = ShoppingLocalStore()
        let aiMemory = AIPersistentMemoryStore()

        return CloudSyncOwnerValidationSources(
            profile: { try profileStore.syncSafeRecord() },
            savedScans: { try savedScans.enumerateSavedScans() },
            savedScanImage: { try savedScans.readValidatedImageAsset(scanID: $0) },
            closet: { try closet.enumerate() },
            shopping: { try shopping.syncSafeRecords() },
            aiMemory: { try aiMemory.syncSafeRecords() },
            apply: { record in
                switch record.kind {
                case .profile: try profileStore.applySyncSafeRecord(record)
                case .savedScan:
                    try savedScans.applyRemoteSavedScan(try JSONDecoder().decode(SavedScanSyncDTO.self, from: record.payload))
                case .closetItem: try closet.apply(record)
                case .favorites, .watchList: try shopping.applySyncSafeRecord(record)
                case .aiMemory: try aiMemory.applySyncSafeRecord(record)
                }
            },
            applySavedScanImage: { dto, asset, data, sha256, byteCount in
                try savedScans.applyRemoteImage(for: dto, asset: asset, data: data, sha256: sha256, byteCount: byteCount)
            }
        )
    }
}

enum CloudSyncValidationDiagnostic: String, Equatable, Sendable {
    case iCloudUnavailable, networkOffline, cloudKitPermission, accountChanged
    case profileMigration, savedScanMetadataIntegrity, savedScanAssetIntegrity
    case closetMigration, shoppingMigration, aiMemoryMigration, conflict
    case cloudKitTransport, unknown
    case inboundAccountGuardMismatch, inboundSavedScanAuthorityConflict
    case inboundMalformedRecord, inboundDecodeFailure, inboundUnsupportedTombstone
    case inboundChangeCursorFailure, inboundCloudKitAccountUnavailable
    case inboundCloudKitError, inboundLocalPersistenceFailure

    var ownerMessage: String {
        switch self {
        case .iCloudUnavailable: return "Needs attention — iCloud account is unavailable. Local data remains on this device."
        case .networkOffline: return "Offline — Cloud Sync will retry when you're online."
        case .cloudKitPermission: return "Needs attention — CloudKit permission could not be confirmed."
        case .accountChanged: return "Needs attention — iCloud account changed. Local data was not moved into another account."
        case .profileMigration: return "Needs attention — Profile sync could not be completed."
        case .savedScanMetadataIntegrity: return "Needs attention — Saved Scan integrity check failed."
        case .savedScanAssetIntegrity: return "Needs attention — Saved Scan image integrity check failed."
        case .closetMigration: return "Needs attention — Closet sync could not be completed."
        case .shoppingMigration: return "Needs attention — Favorites or watch-list sync could not be completed."
        case .aiMemoryMigration: return "Needs attention — Explicitly saved AI Memory sync could not be completed."
        case .conflict: return "Needs attention — Cloud Sync found a conflict that needs resolution."
        case .cloudKitTransport: return "Needs attention — Cloud Sync could not complete with iCloud."
        case .unknown: return "Needs attention — Cloud Sync stopped safely. Local data remains available."
        case .inboundAccountGuardMismatch: return "Needs attention — Cloud Sync stopped because the iCloud account changed."
        case .inboundSavedScanAuthorityConflict: return "Needs attention — A Saved Scan has incompatible local and remote state."
        case .inboundMalformedRecord: return "Needs attention — Cloud Sync received an invalid record."
        case .inboundDecodeFailure: return "Needs attention — Cloud Sync could not read a received record."
        case .inboundUnsupportedTombstone: return "Needs attention — Cloud Sync received a deletion this build cannot safely apply."
        case .inboundChangeCursorFailure: return "Needs attention — Cloud Sync could not safely resume its change history."
        case .inboundCloudKitAccountUnavailable: return "Needs attention — The iCloud account is unavailable for Cloud Sync."
        case .inboundCloudKitError: return "Needs attention — Cloud Sync could not complete with iCloud."
        case .inboundLocalPersistenceFailure: return "Needs attention — Cloud Sync could not safely apply received data locally."
        }
    }
}

enum CloudSyncOwnerValidationOutcome: Equatable, Sendable {
    case disabled
    case off
    case syncing
    case upToDate
    case offline
    case needsAttention(CloudSyncValidationDiagnostic)

    var status: CloudSyncStatus {
        switch self {
        case .disabled, .off: return .off
        case .syncing: return .syncing
        case .upToDate: return .upToDate
        case .offline: return .offline
        case .needsAttention: return .needsAttention
        }
    }
}

/// Optional categories are distinct from malformed authorities. An empty
/// customer-owned category carries no record, tombstone, or remote-delete
/// meaning; it is simply absent from this controlled validation run.
enum CloudSyncOwnerValidationOptionalCategory: String, CaseIterable, Equatable, Sendable {
    case closet
    case favorites
    case watchList
    case aiMemory
}

struct CloudSyncOwnerValidationEvidence: Equatable, Sendable {
    let plannedRecordIDs: [String]
    let skippedOptionalCategories: [CloudSyncOwnerValidationOptionalCategory]

    static let none = CloudSyncOwnerValidationEvidence(
        plannedRecordIDs: [],
        skippedOptionalCategories: []
    )
}

/// Stores only the opaque private-database boundary locally. It contains no
/// customer payload and no Sign in with Apple identity.
final class CloudSyncPrivateAccountGuardStore {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, scope: String = "owner-validation-v1") {
        self.defaults = defaults
        key = "cloudSyncPrivateDatabaseIdentityV1.\(scope)"
    }

    var previousIdentity: CloudSyncPrivateDatabaseIdentity? {
        guard let value = defaults.string(forKey: key), !value.isEmpty else { return nil }
        return CloudSyncPrivateDatabaseIdentity(stableAccountChangeToken: value)
    }

    func recordInitial(_ identity: CloudSyncPrivateDatabaseIdentity) {
        defaults.set(identity.stableAccountChangeToken, forKey: key)
    }
}

/// Opaque durable position in the private-database change stream.  The token
/// is transport metadata only: it contains neither record IDs nor customer
/// payload and is never shown to the customer.
struct CloudSyncDiscoveryCursor: Codable, Equatable, Sendable {
    let databaseToken: Data?
    let zoneTokens: [String: Data]

    static let initial = CloudSyncDiscoveryCursor(databaseToken: nil, zoneTokens: [:])
}

/// A discovered record is deliberately still a typed envelope.  CloudKit
/// discovery never receives permission to decode a backing local store.
struct CloudSyncDiscoveredChange: Equatable, Sendable {
    let record: CloudSyncRecord
    let asset: CloudSyncAssetDownload?
}

struct CloudSyncDiscoveryBatch: Equatable, Sendable {
    let changes: [CloudSyncDiscoveredChange]
    let nextCursor: CloudSyncDiscoveryCursor
    let requiresFullRediscovery: Bool
}

/// Durable private work that has passed envelope validation but is not yet
/// visible locally because its exact saved-scan asset is unavailable or
/// invalid. It contains the minimum scan facts required to resume the same
/// pair after relaunch; diagnostics and account identities are never stored.
struct CloudSyncPendingSavedScan: Codable, Equatable, Sendable, Identifiable {
    let record: CloudSyncRecord
    let dto: SavedScanSyncDTO
    let asset: SavedScanImageAsset

    var id: String { record.id }
}

final class CloudSyncPendingSavedScanStore {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, scope: String = "owner-validation-v1") {
        self.defaults = defaults
        key = "cloudSyncPendingSavedScansV1.\(scope)"
    }

    func pending() throws -> [String: CloudSyncPendingSavedScan] {
        guard let data = defaults.data(forKey: key), !data.isEmpty else { return [:] }
        guard let decoded = try? JSONDecoder().decode([String: CloudSyncPendingSavedScan].self, from: data) else {
            throw CloudSyncInboundError.malformedRecord
        }
        return decoded
    }

    func stage(_ entry: CloudSyncPendingSavedScan) throws {
        var entries = try pending()
        if let existing = entries[entry.id], existing != entry { throw CloudSyncInboundError.conflict }
        entries[entry.id] = entry
        defaults.set(try JSONEncoder().encode(entries), forKey: key)
    }

    func remove(id: String) throws {
        var entries = try pending()
        entries.removeValue(forKey: id)
        defaults.set(try JSONEncoder().encode(entries), forKey: key)
    }
}

enum CloudSyncInboundFailureCategory: String, Codable, CaseIterable, Equatable, Sendable {
    case accountGuardMismatch
    case savedScanAuthorityConflict
    case malformedRecord
    case decodeFailure
    case unsupportedTombstone
    case changeCursorFailure
    case cloudKitAccountUnavailable
    case cloudKitError
    case localPersistenceFailure
    case unknown

    var diagnostic: CloudSyncValidationDiagnostic {
        switch self {
        case .accountGuardMismatch: return .inboundAccountGuardMismatch
        case .savedScanAuthorityConflict: return .inboundSavedScanAuthorityConflict
        case .malformedRecord: return .inboundMalformedRecord
        case .decodeFailure: return .inboundDecodeFailure
        case .unsupportedTombstone: return .inboundUnsupportedTombstone
        case .changeCursorFailure: return .inboundChangeCursorFailure
        case .cloudKitAccountUnavailable: return .inboundCloudKitAccountUnavailable
        case .cloudKitError: return .inboundCloudKitError
        case .localPersistenceFailure: return .inboundLocalPersistenceFailure
        case .unknown: return .unknown
        }
    }
}

enum CloudSyncInboundDiagnosticPresentation {
    static func feedback(for category: CloudSyncInboundFailureCategory?) -> String? {
        guard let category else { return nil }
        return "Inbound Cloud Sync reconciliation: \(category.diagnostic.ownerMessage)"
    }
}

enum CloudSyncInboundError: Error, Equatable {
    case accountChanged
    case malformedRecord
    case assetIncomplete
    case conflict
    case unsupportedTombstone
    case decodeFailure
    case changeCursorFailure
    case localPersistenceFailure

    var failureCategory: CloudSyncInboundFailureCategory {
        switch self {
        case .accountChanged: return .accountGuardMismatch
        case .malformedRecord: return .malformedRecord
        case .assetIncomplete: return .decodeFailure
        case .conflict: return .savedScanAuthorityConflict
        case .unsupportedTombstone: return .unsupportedTombstone
        case .decodeFailure: return .decodeFailure
        case .changeCursorFailure: return .changeCursorFailure
        case .localPersistenceFailure: return .localPersistenceFailure
        }
    }
}

/// Persists only operational state.  In particular, diagnostics, record IDs,
/// hashes, locations and account tokens are intentionally excluded.
final class CloudSyncOperationalStateStore {
    private struct Stored: Codable {
        var status: CloudSyncStatus
        var cursor: CloudSyncDiscoveryCursor
        var lastSuccessfulSync: Date?
        var inboundFailure: CloudSyncInboundFailureCategory?
    }

    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, scope: String = "owner-validation-v1") {
        self.defaults = defaults
        key = "cloudSyncOperationalStateV1.\(scope)"
    }

    func load() -> (status: CloudSyncStatus, cursor: CloudSyncDiscoveryCursor, lastSuccessfulSync: Date?) {
        guard let data = defaults.data(forKey: key), let stored = try? JSONDecoder().decode(Stored.self, from: data) else {
            return (.off, .initial, nil)
        }
        return (stored.status, stored.cursor, stored.lastSuccessfulSync)
    }

    func save(status: CloudSyncStatus, cursor: CloudSyncDiscoveryCursor, lastSuccessfulSync: Date? = nil) {
        let existing = load()
        let stored = Stored(
            status: status,
            cursor: cursor,
            lastSuccessfulSync: lastSuccessfulSync ?? existing.lastSuccessfulSync,
            inboundFailure: loadStored()?.inboundFailure
        )
        defaults.set(try? JSONEncoder().encode(stored), forKey: key)
    }

    func inboundFailureCategory() -> CloudSyncInboundFailureCategory? {
        loadStored()?.inboundFailure
    }

    func recordInboundFailure(_ category: CloudSyncInboundFailureCategory, cursor: CloudSyncDiscoveryCursor) {
        let existing = load()
        let stored = Stored(
            status: .needsAttention,
            cursor: cursor,
            lastSuccessfulSync: existing.lastSuccessfulSync,
            inboundFailure: category
        )
        defaults.set(try? JSONEncoder().encode(stored), forKey: key)
    }

    func clearInboundFailure() {
        guard var stored = loadStored() else { return }
        stored.inboundFailure = nil
        defaults.set(try? JSONEncoder().encode(stored), forKey: key)
    }

    private func loadStored() -> Stored? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Stored.self, from: data)
    }
}

/// The transport supplies private-database discoveries.  A real transport must
/// advance `nextCursor` only after the coordinator acknowledges local apply.
protocol CloudSyncInboundTransport {
    func privateDatabaseIdentity() async throws -> CloudSyncPrivateDatabaseIdentity?
    func discoverChanges(since cursor: CloudSyncDiscoveryCursor) async throws -> CloudSyncDiscoveryBatch
}

/// One authority-only inbound pass. A saved scan remains staged until its
/// matching asset validates, then the saved-scan authority receives both in a
/// single atomic call.
@MainActor
final class CloudSyncInboundReconciliationCoordinator {
    typealias Apply = (PersistenceAuthorityRecord) throws -> Void
    typealias ApplyTombstone = (CloudSyncRecord) throws -> Void
    typealias ApplySavedScanAtomically = (SavedScanSyncDTO, CloudSyncAssetDownload) throws -> Void

    private let transport: any CloudSyncInboundTransport
    private let accountGuard: CloudSyncPrivateAccountGuardStore
    private let state: CloudSyncOperationalStateStore
    private let apply: Apply
    private let applyTombstone: ApplyTombstone
    private let applySavedScanAtomically: ApplySavedScanAtomically
    private let pendingSavedScans: CloudSyncPendingSavedScanStore

    init(
        transport: any CloudSyncInboundTransport,
        accountGuard: CloudSyncPrivateAccountGuardStore,
        state: CloudSyncOperationalStateStore,
        apply: @escaping Apply,
        applyTombstone: @escaping ApplyTombstone,
        applySavedScanAtomically: @escaping ApplySavedScanAtomically,
        pendingSavedScans: CloudSyncPendingSavedScanStore = .init()
    ) {
        self.transport = transport
        self.accountGuard = accountGuard
        self.state = state
        self.apply = apply
        self.applyTombstone = applyTombstone
        self.applySavedScanAtomically = applySavedScanAtomically
        self.pendingSavedScans = pendingSavedScans
    }

    func reconcile() async -> CloudSyncOwnerValidationOutcome {
        let saved = state.load()
        do {
            guard let identity = try await transport.privateDatabaseIdentity() else {
                return recordInboundFailure(.cloudKitAccountUnavailable, cursor: saved.cursor)
            }
            guard CloudSyncAccountGuard.transition(previous: accountGuard.previousIdentity, current: identity) != .changedNeedsAttention else {
                return recordInboundFailure(.accountGuardMismatch, cursor: saved.cursor)
            }
            if accountGuard.previousIdentity == nil { accountGuard.recordInitial(identity) }

            state.save(status: .syncing, cursor: saved.cursor)
            let initialBatch = try await transport.discoverChanges(since: saved.cursor)
            // Resetting a server token is not success. Immediately perform a
            // real full discovery and acknowledge its cursor only after all
            // local authority work below completes.
            let batch = initialBatch.requiresFullRediscovery
                ? try await transport.discoverChanges(since: .initial)
                : initialBatch
            guard !batch.requiresFullRediscovery else { throw CloudSyncInboundError.changeCursorFailure }
            let cursor = batch.nextCursor
            for change in CloudSyncReconciler.deduplicated(batch.changes.map(\.record)) {
                guard let original = batch.changes.first(where: { $0.record == change }) else { throw CloudSyncInboundError.malformedRecord }
                guard CloudSyncEligibility.permits(change) else { throw CloudSyncInboundError.malformedRecord }
                guard let currentIdentity = try await transport.privateDatabaseIdentity(), currentIdentity == identity else {
                    throw CloudSyncInboundError.accountChanged
                }
                if change.isDeleted {
                    try pendingSavedScans.remove(id: change.id)
                    try applyTombstone(change)
                    continue
                }
                let authorityRecord = PersistenceAuthorityRecord(id: change.id, kind: change.kind, payload: change.payload, version: change.version, updatedAt: change.modifiedAt, isDeleted: false, persistenceOrigin: change.persistenceOrigin)
                if change.kind == .savedScan {
                    let pending = try makePendingSavedScan(record: change)
                    try pendingSavedScans.stage(pending)
                    guard let asset = original.asset else { throw CloudSyncInboundError.assetIncomplete }
                    do {
                        try applySavedScanAtomically(pending.dto, asset)
                    } catch {
                        throw normalizedLocalApplyError(error, kind: change.kind)
                    }
                    try pendingSavedScans.remove(id: change.id)
                } else {
                    do {
                        try apply(authorityRecord)
                    } catch {
                        throw normalizedLocalApplyError(error, kind: change.kind)
                    }
                }
            }
            state.save(status: .upToDate, cursor: cursor, lastSuccessfulSync: Date())
            state.clearInboundFailure()
            return .upToDate
        } catch let error as CKError where [.networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited].contains(error.code) {
            state.save(status: .offline, cursor: saved.cursor)
            return .offline
        } catch CloudSyncInboundError.accountChanged {
            return recordInboundFailure(.accountGuardMismatch, cursor: saved.cursor)
        } catch CloudSyncInboundError.assetIncomplete {
            state.save(status: .needsAttention, cursor: saved.cursor)
            return .needsAttention(.savedScanAssetIntegrity)
        } catch let error as CloudSyncInboundError {
            return recordInboundFailure(error.failureCategory, cursor: saved.cursor)
        } catch is CloudSyncCloudKitRecordCodec.DecodeError {
            return recordInboundFailure(.decodeFailure, cursor: saved.cursor)
        } catch let error as CKError where error.code == .notAuthenticated {
            return recordInboundFailure(.cloudKitAccountUnavailable, cursor: saved.cursor)
        } catch is CKError {
            return recordInboundFailure(.cloudKitError, cursor: saved.cursor)
        } catch {
            return recordInboundFailure(.unknown, cursor: saved.cursor)
        }
    }

    private func makePendingSavedScan(record: CloudSyncRecord) throws -> CloudSyncPendingSavedScan {
        guard let dto = try? JSONDecoder().decode(SavedScanSyncDTO.self, from: record.payload),
              dto.id == record.id,
              let scan = try? JSONDecoder().decode(StoredOutfitScan.self, from: dto.persistentAnalysisMetadata) else {
            throw CloudSyncInboundError.decodeFailure
        }
        guard
              let asset = scan.savedImageAsset,
              asset.id == dto.imageAssetID,
              asset.ownerScanID == nil || asset.ownerScanID == dto.id,
              dto.imageSHA256 != nil,
              dto.imageByteCount != nil else {
            throw CloudSyncInboundError.assetIncomplete
        }
        return CloudSyncPendingSavedScan(record: record, dto: dto, asset: asset)
    }

    private func normalizedLocalApplyError(_ error: Error, kind: CloudSyncRecordKind) -> CloudSyncInboundError {
        if let inbound = error as? CloudSyncInboundError { return inbound }
        if let authority = error as? PersistenceAuthorityError,
           authority == .conflict,
           kind == .savedScan {
            return .conflict
        }
        return .localPersistenceFailure
    }

    private func recordInboundFailure(
        _ category: CloudSyncInboundFailureCategory,
        cursor: CloudSyncDiscoveryCursor
    ) -> CloudSyncOwnerValidationOutcome {
        state.recordInboundFailure(category, cursor: cursor)
        return .needsAttention(category.diagnostic)
    }
}

extension CloudSyncInboundReconciliationCoordinator {
    /// The only production construction path. It composes existing typed
    /// authorities; it never decodes backing keys or gives CloudKit direct
    /// access to local persistence.
    static func live(
        transport: any CloudSyncInboundTransport = CloudSyncCloudKitPrivateDatabaseClient(),
        defaults: UserDefaults = .standard,
        scope: String = "owner-validation-v1"
    ) -> CloudSyncInboundReconciliationCoordinator {
        let profile = ProfileStore()
        let savedScans = SavedScanPersistenceAuthority()
        let closet = ClosetPersistenceAuthority()
        let shopping = ShoppingLocalStore()
        let aiMemory = AIPersistentMemoryStore()

        return CloudSyncInboundReconciliationCoordinator(
            transport: transport,
            accountGuard: CloudSyncPrivateAccountGuardStore(defaults: defaults, scope: scope),
            state: CloudSyncOperationalStateStore(defaults: defaults, scope: scope),
            apply: { record in
                if !CloudSyncProductContract.ownerBetaActivationEnabled {
                    switch record.kind {
                    case .profile: try profile.applySyncSafeRecord(record)
                    case .savedScan: throw CloudSyncInboundError.malformedRecord
                    case .closetItem: try closet.apply(record)
                    case .favorites, .watchList: try shopping.applySyncSafeRecord(record)
                    case .aiMemory: try aiMemory.applySyncSafeRecord(record)
                    }
                    return
                }

                switch record.kind {
                case .profile:
                    do { try profile.applySyncSafeRecord(record) }
                    catch PersistenceAuthorityError.stale { /* keep newer local profile; outbound pass republishes it */ }
                case .savedScan:
                    throw CloudSyncInboundError.malformedRecord
                case .closetItem:
                    do { try closet.apply(record) }
                    catch PersistenceAuthorityError.conflict { /* same stable item diverged; keep local in owner beta */ }
                case .favorites, .watchList:
                    try shopping.mergeSyncSafeRecord(record)
                case .aiMemory:
                    do { try aiMemory.applySyncSafeRecord(record) }
                    catch PersistenceAuthorityError.stale { /* keep newer local memory */ }
                    catch PersistenceAuthorityError.conflict { /* keep local; outbound pass republishes it */ }
                }
            },
            applyTombstone: { record in
                if !CloudSyncProductContract.ownerBetaActivationEnabled {
                    guard record.kind == .savedScan else { throw CloudSyncInboundError.unsupportedTombstone }
                    try savedScans.applyRemoteTombstone(id: record.id, version: record.version)
                    return
                }

                switch record.kind {
                case .savedScan:
                    try savedScans.applyRemoteTombstone(id: record.id, version: record.version)
                case .closetItem:
                    try closet.applyTombstone(id: record.id, version: record.version)
                case .aiMemory:
                    guard let id = UUID(uuidString: record.id) else { throw CloudSyncInboundError.malformedRecord }
                    try aiMemory.applyV2Tombstone(id: id)
                case .favorites:
                    let empty = PersistenceAuthorityRecord(
                        id: "favorites",
                        kind: .favorites,
                        payload: try JSONEncoder().encode([String]()),
                        version: "",
                        updatedAt: record.modifiedAt,
                        isDeleted: false,
                        persistenceOrigin: .customerPersistent
                    )
                    try shopping.applySyncSafeRecord(empty)
                case .watchList:
                    let empty = PersistenceAuthorityRecord(
                        id: "watch-list",
                        kind: .watchList,
                        payload: try JSONEncoder().encode([String]()),
                        version: "",
                        updatedAt: record.modifiedAt,
                        isDeleted: false,
                        persistenceOrigin: .customerPersistent
                    )
                    try shopping.applySyncSafeRecord(empty)
                case .profile:
                    throw CloudSyncInboundError.unsupportedTombstone
                }
            },
            applySavedScanAtomically: { dto, download in
                guard let stored = try? JSONDecoder().decode(StoredOutfitScan.self, from: dto.persistentAnalysisMetadata),
                      let asset = stored.savedImageAsset else {
                    throw CloudSyncInboundError.assetIncomplete
                }
                do {
                    try savedScans.applyRemoteSavedScanAtomically(
                        dto,
                        asset: asset,
                        data: download.data,
                        sha256: download.reference.sha256,
                        byteCount: download.reference.byteCount
                    )
                } catch SavedScanPersistenceError.stale {
                    guard CloudSyncProductContract.ownerBetaActivationEnabled else { throw SavedScanPersistenceError.stale }
                    // A newer/deleted local scan wins; the outbound owner-beta pass preserves local.
                } catch SavedScanPersistenceError.conflict {
                    guard CloudSyncProductContract.ownerBetaActivationEnabled else { throw SavedScanPersistenceError.conflict }
                    // Divergent stable IDs fail losslessly by keeping local.
                }
            },
            pendingSavedScans: CloudSyncPendingSavedScanStore(defaults: defaults, scope: scope)
        )
    }
}

/// Separates the one explicit owner validation write sequence from ordinary
/// inbound reconciliation. On relaunch/appearance only reconciliation runs;
/// it never replays the owner validation writes merely to restore a status.
@MainActor
enum CloudSyncRuntimeGate {
    private(set) static var isRunning = false

    static func begin() -> Bool {
        guard !isRunning else { return false }
        isRunning = true
        return true
    }

    static func end() {
        isRunning = false
    }
}

@MainActor
struct CloudSyncOwnerLifecycle {
    let configuration: CloudSyncOwnerValidationConfiguration
    let runValidation: () async -> CloudSyncOwnerValidationOutcome
    let runInbound: () async -> CloudSyncOwnerValidationOutcome

    static func live() -> CloudSyncOwnerLifecycle {
        let scope = CloudSyncProductContract.runtimeScope
        let validation = CloudSyncOwnerValidationCoordinator(scope: scope)
        let inbound = CloudSyncInboundReconciliationCoordinator.live(scope: scope)
        return CloudSyncOwnerLifecycle(
            configuration: .runtime,
            runValidation: { await validation.runControlledValidation() },
            runInbound: { await inbound.reconcile() }
        )
    }

    /// Called only for the deliberate Off -> On owner-validation trigger.
    /// A failed outbound validation never starts inbound application.
    func enableAndValidate() async -> (validation: CloudSyncOwnerValidationOutcome, inbound: CloudSyncOwnerValidationOutcome?) {
        guard configuration.isEnabled else { return (.disabled, nil) }

        if configuration.isOwnerBetaBuild {
            // First reconcile the private database into the local authorities
            // using loss-averse merge rules, then publish the merged local
            // state, then consume the resulting CloudKit changes. This avoids
            // an initial OwnerBeta enable overwriting unique data that already
            // exists on another same-iCloud-account device.
            let firstInbound = await runInbound()
            guard firstInbound == .upToDate || firstInbound == .off else {
                return (firstInbound, firstInbound)
            }
            let validation = await runValidation()
            #if OWNER_BETA
            UserDefaults.standard.set(
                String(describing: validation),
                forKey: "cloudSyncOwnerBetaLastValidationOutcome"
            )
            #endif
            guard validation == .upToDate else { return (validation, firstInbound) }
            return (validation, await runInbound())
        }

        let validation = await runValidation()
        guard validation == .upToDate else { return (validation, nil) }
        return (validation, await runInbound())
    }

    /// Called at a bounded UI lifecycle boundary when the existing owner-only
    /// switch is already enabled. This is incremental and uses the durable
    /// cursor; it never performs validation writes or changes the switch.
    func reconcileOnLifecycleBoundary(isEnabled: Bool) async -> CloudSyncOwnerValidationOutcome {
        guard isEnabled, configuration.allowsInboundDiagnosticReconciliation else { return .disabled }
        return await runInbound()
    }
}

/// A deliberately narrow, non-public first round trip. It demands one typed
/// required object and every present eligible category before writing any
/// record, writes and fetches them in a fixed order, applies only exact
/// replays through the source authority, then checkpoints each confirmed
/// object. Valid empty optional categories are explicitly skipped.
@MainActor
final class CloudSyncOwnerValidationCoordinator {
    private let configuration: CloudSyncOwnerValidationConfiguration
    private let transport: any CloudSyncOwnerValidationTransport
    private let sources: CloudSyncOwnerValidationSources
    private let migration: CloudSyncMigrationCoordinator
    private let accountGuardStore: CloudSyncPrivateAccountGuardStore
    private(set) var latestEvidence: CloudSyncOwnerValidationEvidence = .none

    init(
        configuration: CloudSyncOwnerValidationConfiguration = .runtime,
        transport: any CloudSyncOwnerValidationTransport = CloudSyncCloudKitPrivateDatabaseClient(),
        sources: CloudSyncOwnerValidationSources = .live(),
        migration: CloudSyncMigrationCoordinator,
        accountGuardStore: CloudSyncPrivateAccountGuardStore = .init()
    ) {
        self.configuration = configuration
        self.transport = transport
        self.sources = sources
        self.migration = migration
        self.accountGuardStore = accountGuardStore
    }

    convenience init(scope: String = CloudSyncProductContract.runtimeScope) {
        self.init(
            migration: CloudSyncMigrationCoordinator(defaults: .standard, accountScope: scope),
            accountGuardStore: CloudSyncPrivateAccountGuardStore(defaults: .standard, scope: scope)
        )
    }

    func runControlledValidation() async -> CloudSyncOwnerValidationOutcome {
        guard configuration.isEnabled else { return .disabled }
        do {
            guard try await transport.accountStatus() == .available else {
                return .needsAttention(.iCloudUnavailable)
            }
            try await enforcePrivateAccountGuard()

            let plan = try validationPlan()
            latestEvidence = plan.evidence
            guard !plan.records.isEmpty else {
                return .needsAttention(.unknown)
            }

            // Guard before checkpoint/retry decisions as well as writes.
            try await enforcePrivateAccountGuard()
            _ = try migration.pending(plan.records, category: .profile)
            for item in plan.sequence {
                try await roundTrip(item)
            }

            return migration.isComplete(required: plan.records)
                ? .upToDate
                : .needsAttention(.cloudKitTransport)
        } catch {
            return outcome(for: error)
        }
    }

    private struct ValidationPlan {
        struct Item {
            let authorityRecord: PersistenceAuthorityRecord
            let savedScan: SavedScanSyncDTO?
            let asset: CloudSyncAssetUpload?
        }
        let records: [PersistenceAuthorityRecord]
        let sequence: [Item]
        let evidence: CloudSyncOwnerValidationEvidence
    }

    private enum OptionalCategoryState {
        case empty(CloudSyncOwnerValidationOptionalCategory)
        case ready(ValidationPlan.Item)
        case invalid(OwnerValidationError)
    }

    private func validationPlan() throws -> ValidationPlan {
        if configuration.isOwnerBetaBuild {
            return try ownerBetaValidationPlan()
        }

        let profile = try required(sources.profile, or: .profileMigration)
        let scan = try required(
            { try sources.savedScans().sorted(by: { $0.id < $1.id }).first },
            or: .savedScanMetadataIntegrity
        )
        let image = try required({ try sources.savedScanImage(scan.id) }, or: .savedScanAssetIntegrity)

        let scanRecord = PersistenceAuthorityRecord(
            id: scan.id,
            kind: .savedScan,
            payload: try JSONEncoder().encode(scan),
            version: scan.version,
            updatedAt: scan.savedAt,
            isDeleted: false,
            persistenceOrigin: .customerPersistent
        )
        let reference = CloudSyncAssetReference(
            owningRecordID: scan.id,
            assetIdentifier: image.asset.id,
            sha256: image.sha256,
            byteCount: image.byteCount
        )
        let upload = CloudSyncAssetUpload(reference: reference, data: image.data)
        var sequence = [
            ValidationPlan.Item(authorityRecord: profile, savedScan: nil, asset: nil),
            ValidationPlan.Item(authorityRecord: scanRecord, savedScan: scan, asset: upload)
        ]
        var skipped: [CloudSyncOwnerValidationOptionalCategory] = []
        let optionalStates = [
            optionalClosetState(),
            optionalShoppingState(kind: .favorites, category: .favorites),
            optionalShoppingState(kind: .watchList, category: .watchList),
            optionalAIMemoryState()
        ]

        for state in optionalStates {
            switch state {
            case .empty(let category):
                skipped.append(category)
            case .ready(let item):
                sequence.append(item)
            case .invalid(let error):
                throw error
            }
        }

        return ValidationPlan(
            records: sequence.map(\.authorityRecord),
            sequence: sequence,
            evidence: CloudSyncOwnerValidationEvidence(
                plannedRecordIDs: sequence.map(\.authorityRecord.id),
                skippedOptionalCategories: skipped
            )
        )
    }

    private func ownerBetaValidationPlan() throws -> ValidationPlan {
        let profile = try required(sources.profile, or: .profileMigration)
        var sequence = [
            ValidationPlan.Item(authorityRecord: profile, savedScan: nil, asset: nil)
        ]
        var skipped: [CloudSyncOwnerValidationOptionalCategory] = []

        // OwnerBeta 18049 uploads every eligible saved scan, not only a
        // diagnostic sample. A saved scan is admitted only when its exact
        // persisted image asset can make the same atomic round trip.
        let scans: [SavedScanSyncDTO]
        do { scans = try sources.savedScans().sorted { $0.id < $1.id } }
        catch { throw OwnerValidationError.savedScanMetadataIntegrity }
        for scan in scans {
            let image = try required({ try sources.savedScanImage(scan.id) }, or: .savedScanAssetIntegrity)
            let scanRecord = PersistenceAuthorityRecord(
                id: scan.id,
                kind: .savedScan,
                payload: try JSONEncoder().encode(scan),
                version: scan.version,
                updatedAt: scan.savedAt,
                isDeleted: false,
                persistenceOrigin: .customerPersistent
            )
            let reference = CloudSyncAssetReference(
                owningRecordID: scan.id,
                assetIdentifier: image.asset.id,
                sha256: image.sha256,
                byteCount: image.byteCount
            )
            sequence.append(
                ValidationPlan.Item(
                    authorityRecord: scanRecord,
                    savedScan: scan,
                    asset: CloudSyncAssetUpload(reference: reference, data: image.data)
                )
            )
        }

        let closetRecords: [PersistenceAuthorityRecord]
        do { closetRecords = try sources.closet().sorted { $0.id < $1.id } }
        catch { throw OwnerValidationError.closetMigration }
        guard closetRecords.allSatisfy({ $0.kind == .closetItem && !$0.isDeleted }) else {
            throw OwnerValidationError.closetMigration
        }
        if closetRecords.isEmpty { skipped.append(.closet) }
        sequence.append(contentsOf: closetRecords.map {
            ValidationPlan.Item(authorityRecord: $0, savedScan: nil, asset: nil)
        })

        let shoppingRecords: [PersistenceAuthorityRecord]
        do { shoppingRecords = try sources.shopping().sorted { $0.kind.rawValue < $1.kind.rawValue } }
        catch { throw OwnerValidationError.shoppingMigration }
        for kind in [CloudSyncRecordKind.favorites, .watchList] {
            guard let record = shoppingRecords.first(where: { $0.kind == kind }),
                  (try? JSONDecoder().decode([String].self, from: record.payload)) != nil else {
                throw OwnerValidationError.shoppingMigration
            }
            sequence.append(ValidationPlan.Item(authorityRecord: record, savedScan: nil, asset: nil))
            if let values = try? JSONDecoder().decode([String].self, from: record.payload), values.isEmpty {
                skipped.append(kind == .favorites ? .favorites : .watchList)
            }
        }

        let memoryRecords: [PersistenceAuthorityRecord]
        do { memoryRecords = try sources.aiMemory().sorted { $0.id < $1.id } }
        catch { throw OwnerValidationError.aiMemoryMigration }
        guard memoryRecords.allSatisfy({
            $0.kind == .aiMemory && !$0.isDeleted && $0.persistenceOrigin == .explicitlySavedAIMemory
        }) else { throw OwnerValidationError.aiMemoryMigration }
        if memoryRecords.isEmpty { skipped.append(.aiMemory) }
        sequence.append(contentsOf: memoryRecords.map {
            ValidationPlan.Item(authorityRecord: $0, savedScan: nil, asset: nil)
        })

        return ValidationPlan(
            records: sequence.map(\.authorityRecord),
            sequence: sequence,
            evidence: CloudSyncOwnerValidationEvidence(
                plannedRecordIDs: sequence.map(\.authorityRecord.id),
                skippedOptionalCategories: skipped.sorted { $0.rawValue < $1.rawValue }
            )
        )
    }

    private func optionalClosetState() -> OptionalCategoryState {
        do {
            let records = try sources.closet()
            guard records.allSatisfy({ $0.kind == .closetItem }) else { return .invalid(.closetMigration) }
            guard let record = records.sorted(by: { $0.id < $1.id }).first else { return .empty(.closet) }
            return .ready(ValidationPlan.Item(authorityRecord: record, savedScan: nil, asset: nil))
        } catch {
            return .invalid(.closetMigration)
        }
    }

    private func optionalShoppingState(
        kind: CloudSyncRecordKind,
        category: CloudSyncOwnerValidationOptionalCategory
    ) -> OptionalCategoryState {
        do {
            let records = try sources.shopping()
            guard let record = records.first(where: { $0.kind == kind }) else { return .empty(category) }
            guard let values = try? JSONDecoder().decode([String].self, from: record.payload) else {
                return .invalid(.shoppingMigration)
            }
            guard !values.isEmpty else { return .empty(category) }
            return .ready(ValidationPlan.Item(authorityRecord: record, savedScan: nil, asset: nil))
        } catch {
            return .invalid(.shoppingMigration)
        }
    }

    private func optionalAIMemoryState() -> OptionalCategoryState {
        do {
            let records = try sources.aiMemory()
            guard records.allSatisfy({ $0.kind == .aiMemory && $0.persistenceOrigin == .explicitlySavedAIMemory }) else {
                return .invalid(.aiMemoryMigration)
            }
            guard let record = records.sorted(by: { $0.id < $1.id }).first else { return .empty(.aiMemory) }
            return .ready(ValidationPlan.Item(authorityRecord: record, savedScan: nil, asset: nil))
        } catch {
            return .invalid(.aiMemoryMigration)
        }
    }

    private func roundTrip(_ item: ValidationPlan.Item) async throws {
        try await enforcePrivateAccountGuard()
        let cloudRecord = CloudSyncRecord(
            id: item.authorityRecord.id,
            kind: item.authorityRecord.kind,
            payload: item.authorityRecord.payload,
            version: item.authorityRecord.version,
            modifiedAt: item.authorityRecord.updatedAt,
            isDeleted: item.authorityRecord.isDeleted,
            persistenceOrigin: item.authorityRecord.persistenceOrigin
        )
        let saved: CloudSyncRecord
        let fetched: CloudSyncRecord
        do {
            saved = try await transport.save(cloudRecord, asset: item.asset)
            fetched = try await transport.fetch(recordID: cloudRecord.id)
        } catch {
            #if OWNER_BETA
            if let cloudError = error as? CKError {
                UserDefaults.standard.set(
                    "kind=\(item.authorityRecord.kind.rawValue);ck=\(cloudError.code.rawValue)",
                    forKey: "cloudSyncOwnerBetaLastTransportDiagnostic"
                )
            } else {
                UserDefaults.standard.set(
                    "kind=\(item.authorityRecord.kind.rawValue);error=nonCloudKit",
                    forKey: "cloudSyncOwnerBetaLastTransportDiagnostic"
                )
            }
            #endif
            throw categoryError(for: item.authorityRecord.kind, error: error)
        }
        guard saved == cloudRecord, fetched == cloudRecord else {
            throw item.authorityRecord.kind == .savedScan
                ? OwnerValidationError.savedScanMetadataIntegrity
                : categoryError(for: item.authorityRecord.kind, error: OwnerValidationError.roundTripMismatch)
        }

        try await enforcePrivateAccountGuard()
        do { try sources.apply(item.authorityRecord) }
        catch { throw categoryError(for: item.authorityRecord.kind, error: error) }
        if let scan = item.savedScan, let upload = item.asset {
            try await enforcePrivateAccountGuard()
            let downloaded: CloudSyncAssetDownload
            do { downloaded = try await transport.fetchAsset(recordID: scan.id) }
            catch { throw OwnerValidationError.savedScanAssetIntegrity }
            guard downloaded.reference == upload.reference,
                  downloaded.data == upload.data else {
                throw OwnerValidationError.savedScanAssetMismatch
            }
            guard let localAsset = try sources.savedScanImage(scan.id),
                  localAsset.asset.id == upload.reference.assetIdentifier,
                  localAsset.sha256 == upload.reference.sha256,
                  localAsset.byteCount == upload.reference.byteCount else {
                throw OwnerValidationError.savedScanAssetMismatch
            }
            try await enforcePrivateAccountGuard()
            do {
                try sources.applySavedScanImage(scan, localAsset.asset, downloaded.data, downloaded.reference.sha256, downloaded.reference.byteCount)
            } catch {
                throw OwnerValidationError.savedScanAssetIntegrity
            }
        }
        migration.acknowledge([item.authorityRecord])
    }

    private func required<T>(_ source: () throws -> T?, or diagnostic: OwnerValidationError) throws -> T {
        do {
            guard let value = try source() else { throw diagnostic }
            return value
        } catch let error as OwnerValidationError {
            throw error
        } catch {
            throw diagnostic
        }
    }

    private func outcome(for error: Error) -> CloudSyncOwnerValidationOutcome {
        if let error = error as? CKError,
           [.networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited].contains(error.code) {
            return .offline
        }
        if let error = error as? CKError,
           [.permissionFailure, .notAuthenticated, .badDatabase, .zoneNotFound].contains(error.code) {
            return .needsAttention(.cloudKitPermission)
        }
        return .needsAttention(diagnostic(for: error))
    }

    private enum OwnerValidationError: Error {
        case accountChanged
        case profileMigration
        case savedScanMetadataIntegrity
        case roundTripMismatch
        case savedScanAssetMismatch
        case savedScanAssetIntegrity
        case closetMigration
        case shoppingMigration
        case aiMemoryMigration
    }

    private func enforcePrivateAccountGuard() async throws {
        let current = try await transport.privateDatabaseIdentity()
        switch CloudSyncAccountGuard.transition(previous: accountGuardStore.previousIdentity, current: current) {
        case .unchanged:
            return
        case .initialAccount:
            guard let current else { throw OwnerValidationError.accountChanged }
            accountGuardStore.recordInitial(current)
        case .changedNeedsAttention:
            throw OwnerValidationError.accountChanged
        }
    }

    private func categoryError(for kind: CloudSyncRecordKind, error: Error) -> OwnerValidationError {
        if error is SavedScanPersistenceError { return .savedScanMetadataIntegrity }
        switch kind {
        case .profile: return .profileMigration
        case .savedScan: return .savedScanMetadataIntegrity
        case .closetItem: return .closetMigration
        case .favorites, .watchList: return .shoppingMigration
        case .aiMemory: return .aiMemoryMigration
        }
    }

    private func diagnostic(for error: Error) -> CloudSyncValidationDiagnostic {
        guard let error = error as? OwnerValidationError else { return .unknown }
        switch error {
        case .accountChanged: return .accountChanged
        case .profileMigration: return .profileMigration
        case .savedScanMetadataIntegrity: return .savedScanMetadataIntegrity
        case .savedScanAssetMismatch, .savedScanAssetIntegrity: return .savedScanAssetIntegrity
        case .closetMigration: return .closetMigration
        case .shoppingMigration: return .shoppingMigration
        case .aiMemoryMigration: return .aiMemoryMigration
        case .roundTripMismatch: return .conflict
        }
    }
}
