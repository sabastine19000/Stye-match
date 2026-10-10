import Foundation
import CloudKit
import CryptoKit

/// The v1 ownership boundary is the customer's CloudKit *private* database.
/// It deliberately does not derive a sync namespace from Sign in with Apple.
/// CloudKit supplies the private-database boundary for the iCloud account that
/// is active on each device; a different iCloud account therefore sees a
/// different private database and cannot be merged by this foundation.
enum CloudSyncIdentityBoundary: Equatable, Sendable {
    case sameICloudAccountPrivateDatabase

    static let v1: CloudSyncIdentityBoundary = .sameICloudAccountPrivateDatabase

    var customerFacingDescription: String {
        "Cloud Sync uses the iCloud account on this device. It is available only on devices signed in to the same iCloud account."
    }
}

/// Product guardrails for the staged Cloud Sync rollout. Sign in with Apple
/// authenticates a StyleMatch customer; it is never a CloudKit namespace or an
/// authorization to transmit data to an AI provider. CloudKit remains private
/// to the iCloud account on the device.
enum CloudSyncProductContract {
    /// This stays false until the signed owner iPhone and iPad validation has
    /// proved migration, integrity, account-change handling, and privacy
    /// exclusions. The Account UI must therefore remain a truthful placeholder.
    static let customerPublicActivationEnabled = false

    /// Build 18049 OwnerBeta is an owner-only physical acceptance lane. It
    /// enables the real private-CloudKit controls without opening Cloud Sync
    /// in App Store/Release builds. Public activation remains independently
    /// closed until two-device acceptance is complete.
    static var ownerBetaActivationEnabled: Bool {
        #if OWNER_BETA
        true
        #else
        false
        #endif
    }

    static var customerControlsEnabled: Bool {
        customerPublicActivationEnabled || ownerBetaActivationEnabled
    }

    static var runtimeScope: String {
        ownerBetaActivationEnabled ? "owner-beta-18049-v1" : "owner-validation-v1"
    }

    static let preActivationOnDetail = "Cross-device Cloud Sync is not active in this build. Your data remains safely on this device."
    static let preActivationOffDetail = "Cloud Sync is off. Your data remains on this device."
    static let preActivationConsentDetail = "Cross-device Cloud Sync is not active in this build, so no customer data is being uploaded or reconciled with iCloud. Before activation, KigoStylist will ask you to review the eligible data, iCloud requirement, controls, and deletion behavior."
    static let futureOffAndDeletionDetail = "Turning Cloud Sync off will stop future synchronization. It will not by itself delete existing iCloud copies. Remote deletion controls remain a separate release requirement."

    static let eligibleCustomerData = [
        "Profile and style preferences",
        "Sizes and measurements",
        "Closet",
        "Saved scans, including exact saved scores, timestamps, and saved images",
        "Favorites and watch list or sale alerts",
        "Only AI Memory that you explicitly saved"
    ]

    static let deviceLocalExcludedData = [
        "Temporary AI conversations and temporary AI context",
        "Screen awareness and AI transmission consent",
        "Camera, photo, microphone, location, and notification permissions",
        "Unsaved scan working state and local caches",
        "Secrets, tokens, diagnostics, and internal routing metadata",
        "Transient UI state"
    ]

    static func preActivationStatus(isSwitchOn: Bool) -> CloudSyncStatus {
        // A persisted owner-validation preference from an older build is not
        // evidence that customer Cloud Sync is unhealthy. While public
        // activation is closed, the truthful customer state is simply Off.
        .off
    }

    static func preActivationDetail(isSwitchOn: Bool) -> String {
        isSwitchOn ? preActivationOnDetail : preActivationOffDetail
    }

    static func requiresExplicitAccountResolution(_ transition: CloudSyncAccountTransition) -> Bool {
        transition == .changedNeedsAttention
    }
}

enum CloudSyncStatus: String, Codable, CaseIterable, Sendable {
    case off
    case syncing
    case upToDate
    case needsAttention
    case offline

    var title: String {
        switch self {
        case .off: return "Off"
        case .syncing: return "Syncing"
        case .upToDate: return "Up to date"
        case .needsAttention: return "Needs attention"
        case .offline: return "Offline"
        }
    }
}

enum CloudSyncRecordKind: String, Codable, CaseIterable, Sendable {
    case profile
    case closetItem
    case savedScan
    case favorites
    case watchList
    case aiMemory
}

/// Record IDs are scoped by the CloudKit private database, not by a StyleMatch
/// account subject. This prevents a Sign in with Apple identity from becoming
/// a cross-iCloud merge key.
struct CloudSyncPrivateDatabaseIdentity: Equatable, Sendable {
    let stableAccountChangeToken: String
}

enum CloudSyncAccountTransition: Equatable, Sendable {
    case unchanged
    case initialAccount
    case changedNeedsAttention
}

enum CloudSyncAccountGuard {
    static func transition(
        previous: CloudSyncPrivateDatabaseIdentity?,
        current: CloudSyncPrivateDatabaseIdentity?
    ) -> CloudSyncAccountTransition {
        guard let current else { return .changedNeedsAttention }
        guard let previous else { return .initialAccount }
        return previous == current ? .unchanged : .changedNeedsAttention
    }
}

enum CloudSyncPersistenceOrigin: String, Codable, Sendable {
    case customerPersistent
    case explicitlySavedAIMemory
}

enum CloudSyncEligibility {
    static let allowedRecordKinds = Set(CloudSyncRecordKind.allCases)

    /// These are intentionally names rather than storage keys. Existing local
    /// account snapshots must never be uploaded as an opaque blob.
    static let excludedLocalOnlyCategories: Set<String> = [
        "temporaryAIConversation",
        "temporaryAIContext",
        "screenAwareness",
        "unsavedScanWorkingState",
        "cameraGalleryPermission",
        "microphonePermission",
        "locationPermission",
        "notificationPermission",
        "devicePermission",
        "aiTransmissionConsent",
        "localCache",
        "weatherCache",
        "secret",
        "token",
        "debugDiagnosticData",
        "internalRouteMetadata",
        "transientUIState"
    ]

    static func permits(_ record: CloudSyncRecord) -> Bool {
        guard allowedRecordKinds.contains(record.kind) else { return false }
        // A record may arrive through discovery before its CloudKit envelope
        // is decoded. Do not let a future or obsolete schema reach an
        // authority merely because its record kind is known.
        guard record.schemaVersion == CloudSyncRecord.currentSchemaVersion else { return false }
        if record.kind == .aiMemory {
            return record.persistenceOrigin == .explicitlySavedAIMemory
        }
        return record.persistenceOrigin == .customerPersistent
    }
}

/// Deliberate, auditable source map for the eventual transport adapter. These
/// are individual local stores, never a serialized account snapshot.
enum CloudSyncLocalSource: String, CaseIterable, Sendable {
    case profile = "PersonalStylist/ProfileStore"
    case closet = "UserDefaults/closetItemsData"
    case savedScanHistory = "ScanAuthority/StoredScanRecord"
    case savedScanImage = "ScanAuthority/SavedScanImageAssetStore"
    case favorites = "ShoppingLocalStore/shoppingSavedFavoriteProductIDs"
    case watchList = "ShoppingLocalStore/shoppingSaleAlertProductIDs"
    case aiMemory = "AIMemoryManager/explicitly-saved-memory"
}

struct CloudSyncAdapterContract: Equatable, Sendable {
    let source: CloudSyncLocalSource
    let recordKind: CloudSyncRecordKind
    let eligibleFields: [String]
    let excludedFields: [String]
    let supportsTombstone: Bool

    static let all: [CloudSyncAdapterContract] = [
        .init(source: .profile, recordKind: .profile,
              eligibleFields: ["sizes", "measurements", "fit", "style", "favoriteColors", "favoriteBrands", "budget", "occasions"],
              excludedFields: ["aiTransmissionConsent", "permissions", "temporaryContext", "debug"], supportsTombstone: false),
        .init(source: .closet, recordKind: .closetItem,
              eligibleFields: ["stableID", "name", "category", "subcategory", "colors", "tags", "favorite", "imageAsset"],
              excludedFields: ["transientUIState", "deviceCache"], supportsTombstone: true),
        .init(source: .savedScanHistory, recordKind: .savedScan,
              eligibleFields: ["stableID", "authoritativeScore", "savedAt", "occasion", "colors", "patterns", "fit", "accessories", "metadata", "title", "savedStatus", "imageAsset"],
              excludedFields: ["workingScan", "recomputedScore", "latestScanFallback"], supportsTombstone: true),
        .init(source: .favorites, recordKind: .favorites,
              eligibleFields: ["productIDs"], excludedFields: ["staticCatalog"], supportsTombstone: true),
        .init(source: .watchList, recordKind: .watchList,
              eligibleFields: ["productIDs", "savedShoppingIntent"], excludedFields: ["staticCatalog"], supportsTombstone: true),
        .init(source: .aiMemory, recordKind: .aiMemory,
              eligibleFields: ["stableID", "savedFact", "memoryState", "timestamps", "version"],
              excludedFields: ["temporaryConversation", "screenContext", "routeAuthority", "aiTransmissionConsent", "unsavedInference"], supportsTombstone: true)
    ]
}

enum CloudSyncLocalAdapter {
    static func contract(for source: CloudSyncLocalSource) -> CloudSyncAdapterContract? {
        CloudSyncAdapterContract.all.first { $0.source == source }
    }

    /// Adapters accept only a record already decoded and validated by its
    /// source store. This rejects malformed or incomplete saved scans rather
    /// than fabricating replacement facts from newer local state.
    static func recordIfEligible(_ record: CloudSyncRecord, from source: CloudSyncLocalSource) -> CloudSyncRecord? {
        guard let contract = contract(for: source), contract.recordKind == record.kind else { return nil }
        guard CloudSyncEligibility.permits(record) else { return nil }
        guard !(record.kind == .savedScan && record.payload.isEmpty) else { return nil }
        return record
    }
}

/// Tombstone acceptance is deliberately narrower than an adapter's eventual
/// deletion capability. Phase 2 authorizes only Closet V2 as a candidate;
/// Shopping and AI Memory remain fail-closed until their own V2 authority
/// phases complete. The legacy inbound coordinator still rejects every V1
/// non-scan tombstone because it lacks a V2 token.
enum CloudSyncInboundTombstonePolicy {
    static func supports(_ kind: CloudSyncRecordKind) -> Bool {
        switch kind {
        case .closetItem: return true
        case .profile, .savedScan, .favorites, .watchList, .aiMemory: return false
        }
    }
}

/// An authority-owned envelope. Cross-device transport can carry this value,
/// but it never decodes the backing UserDefaults or snapshot representation.
struct PersistenceAuthorityRecord: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let kind: CloudSyncRecordKind
    let payload: Data
    let version: String
    let updatedAt: Date
    let isDeleted: Bool
    let persistenceOrigin: CloudSyncPersistenceOrigin
}

enum PersistenceAuthorityError: Error, Equatable {
    case invalidRecord
    case missing
    case stale
    case conflict
}

/// A small envelope used by the local queue and by the CloudKit adapter. The
/// record identifier is stable across retries and devices. It never contains a
/// Sign in with Apple subject, an iCloud account identifier, or AI consent.
struct CloudSyncRecord: Codable, Equatable, Sendable, Identifiable {
    static let currentSchemaVersion = 1

    let id: String
    let kind: CloudSyncRecordKind
    let payload: Data
    /// Authority-owned object version.  It is carried end-to-end so a remote
    /// apply never invents a version from unrelated transport bytes.
    let version: String
    let modifiedAt: Date
    let isDeleted: Bool
    let schemaVersion: Int
    let persistenceOrigin: CloudSyncPersistenceOrigin

    init(
        id: String,
        kind: CloudSyncRecordKind,
        payload: Data,
        version: String? = nil,
        modifiedAt: Date,
        isDeleted: Bool = false,
        schemaVersion: Int = CloudSyncRecord.currentSchemaVersion,
        persistenceOrigin: CloudSyncPersistenceOrigin = .customerPersistent
    ) {
        self.id = id
        self.kind = kind
        self.payload = payload
        self.version = version ?? payload.base64EncodedString()
        self.modifiedAt = modifiedAt
        self.isDeleted = isDeleted
        self.schemaVersion = schemaVersion
        self.persistenceOrigin = persistenceOrigin
    }
}

/// A saved scan is represented independently rather than as a mutable account
/// snapshot. Its stable identifier and completed score are copied exactly; a
/// receiving device has no authority to recalculate the score.
struct SavedScanSyncPayload: Codable, Equatable, Sendable {
    let stableScanID: String
    let authoritativeScore: Int
    let savedAt: Date
    let occasionRawValue: String?
    let metadata: Data

    init(
        stableScanID: String,
        authoritativeScore: Int,
        savedAt: Date,
        occasionRawValue: String?,
        metadata: Data
    ) {
        self.stableScanID = stableScanID
        self.authoritativeScore = authoritativeScore
        self.savedAt = savedAt
        self.occasionRawValue = occasionRawValue
        self.metadata = metadata
    }
}

/// CloudKit assets stay outside ordinary record metadata. A downloaded asset
/// is accepted only when its declared checksum and stable scan association
/// match. The source image remains local after a successful upload.
struct CloudSyncAssetReference: Codable, Equatable, Sendable {
    let owningRecordID: String
    let assetIdentifier: String
    let sha256: String
    let byteCount: Int64
}

/// Typed asset material originating only from a saved-scan authority. It does
/// not contain a photo-library reference, screen capture, or AI request data.
struct CloudSyncAssetUpload: Equatable, Sendable {
    let reference: CloudSyncAssetReference
    let data: Data
}

struct CloudSyncAssetDownload: Equatable, Sendable {
    let reference: CloudSyncAssetReference
    let data: Data
}

/// The CloudKit representation is deliberately a typed envelope rather than a
/// serialized account backup. The client below is private-database-only and is
/// inert until a future, separately approved customer sync action invokes it.
enum CloudSyncCloudKitRecordCodec {
    static let recordType = "StyleMatchCloudSyncRecordV1"

    private enum Field {
        static let stableID = "stableID"
        static let kind = "kind"
        static let payload = "payload"
        static let version = "version"
        static let modifiedAt = "modifiedAt"
        static let isDeleted = "isDeleted"
        static let schemaVersion = "schemaVersion"
        static let persistenceOrigin = "persistenceOrigin"
        static let asset = "asset"
        static let assetIdentifier = "assetIdentifier"
        static let assetSHA256 = "assetSHA256"
        static let assetByteCount = "assetByteCount"
    }

    enum DecodeError: Error, Equatable {
        case missingOrInvalidField(String)
        case recordIdentifierMismatch
        case unsupportedSchemaVersion
        case ineligibleRecord
        case invalidAsset
    }

    static func makeRecord(from record: CloudSyncRecord, zoneID: CKRecordZone.ID? = nil) throws -> CKRecord {
        guard CloudSyncEligibility.permits(record) else { throw DecodeError.ineligibleRecord }

        let recordID = zoneID.map { CKRecord.ID(recordName: record.id, zoneID: $0) }
            ?? CKRecord.ID(recordName: record.id)
        let cloudRecord = CKRecord(
            recordType: recordType,
            recordID: recordID
        )
        cloudRecord[Field.stableID] = record.id as NSString
        cloudRecord[Field.kind] = record.kind.rawValue as NSString
        cloudRecord[Field.payload] = record.payload as NSData
        cloudRecord[Field.version] = record.version as NSString
        cloudRecord[Field.modifiedAt] = record.modifiedAt as NSDate
        cloudRecord[Field.isDeleted] = NSNumber(value: record.isDeleted)
        cloudRecord[Field.schemaVersion] = NSNumber(value: record.schemaVersion)
        cloudRecord[Field.persistenceOrigin] = record.persistenceOrigin.rawValue as NSString
        return cloudRecord
    }

    static func decode(_ cloudRecord: CKRecord) throws -> CloudSyncRecord {
        guard cloudRecord.recordType == recordType else {
            throw DecodeError.missingOrInvalidField("recordType")
        }
        guard let stableID = cloudRecord[Field.stableID] as? String else {
            throw DecodeError.missingOrInvalidField(Field.stableID)
        }
        guard stableID == cloudRecord.recordID.recordName else {
            throw DecodeError.recordIdentifierMismatch
        }
        guard let kindRaw = cloudRecord[Field.kind] as? String,
              let kind = CloudSyncRecordKind(rawValue: kindRaw) else {
            throw DecodeError.missingOrInvalidField(Field.kind)
        }
        guard let payload = cloudRecord[Field.payload] as? Data else {
            throw DecodeError.missingOrInvalidField(Field.payload)
        }
        guard let version = cloudRecord[Field.version] as? String, !version.isEmpty else {
            throw DecodeError.missingOrInvalidField(Field.version)
        }
        guard let modifiedAt = cloudRecord[Field.modifiedAt] as? Date else {
            throw DecodeError.missingOrInvalidField(Field.modifiedAt)
        }
        guard let isDeleted = cloudRecord[Field.isDeleted] as? NSNumber else {
            throw DecodeError.missingOrInvalidField(Field.isDeleted)
        }
        guard let schemaVersion = cloudRecord[Field.schemaVersion] as? NSNumber else {
            throw DecodeError.missingOrInvalidField(Field.schemaVersion)
        }
        guard schemaVersion.intValue == CloudSyncRecord.currentSchemaVersion else {
            throw DecodeError.unsupportedSchemaVersion
        }
        guard let originRaw = cloudRecord[Field.persistenceOrigin] as? String,
              let origin = CloudSyncPersistenceOrigin(rawValue: originRaw) else {
            throw DecodeError.missingOrInvalidField(Field.persistenceOrigin)
        }

        let record = CloudSyncRecord(
            id: stableID,
            kind: kind,
            payload: payload,
            version: version,
            modifiedAt: modifiedAt,
            isDeleted: isDeleted.boolValue,
            schemaVersion: schemaVersion.intValue,
            persistenceOrigin: origin
        )
        guard CloudSyncEligibility.permits(record) else { throw DecodeError.ineligibleRecord }
        return record
    }

    /// Attaches an already validated source file as a CKAsset without changing
    /// the local file or treating it as an AI/network-context payload.
    static func attachAsset(
        reference: CloudSyncAssetReference,
        sourceFileURL: URL,
        to cloudRecord: CKRecord
    ) throws {
        guard reference.owningRecordID == cloudRecord.recordID.recordName else {
            throw DecodeError.recordIdentifierMismatch
        }
        let data = try Data(contentsOf: sourceFileURL)
        let checksum = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard CloudSyncAssetIntegrity.accepts(
            reference: reference,
            forRecordID: cloudRecord.recordID.recordName,
            sha256: checksum,
            byteCount: Int64(data.count)
        ) else {
            throw DecodeError.invalidAsset
        }
        cloudRecord[Field.asset] = CKAsset(fileURL: sourceFileURL)
        cloudRecord[Field.assetIdentifier] = reference.assetIdentifier as NSString
        cloudRecord[Field.assetSHA256] = reference.sha256 as NSString
        cloudRecord[Field.assetByteCount] = NSNumber(value: reference.byteCount)
    }

    static func decodeAssetReference(from cloudRecord: CKRecord) throws -> (CloudSyncAssetReference, URL) {
        guard let asset = cloudRecord[Field.asset] as? CKAsset,
              let fileURL = asset.fileURL,
              let assetIdentifier = cloudRecord[Field.assetIdentifier] as? String,
              let sha256 = cloudRecord[Field.assetSHA256] as? String,
              let byteCount = cloudRecord[Field.assetByteCount] as? NSNumber else {
            throw DecodeError.invalidAsset
        }
        let data = try Data(contentsOf: fileURL)
        let checksum = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let reference = CloudSyncAssetReference(
            owningRecordID: cloudRecord.recordID.recordName,
            assetIdentifier: assetIdentifier,
            sha256: sha256,
            byteCount: byteCount.int64Value
        )
        guard CloudSyncAssetIntegrity.accepts(
            reference: reference,
            forRecordID: cloudRecord.recordID.recordName,
            sha256: checksum,
            byteCount: Int64(data.count)
        ) else {
            throw DecodeError.invalidAsset
        }
        return (reference, fileURL)
    }
}

/// The only CloudKit transport for this phase. It uses the active iCloud
/// account's private database, never a public/shared database, and has no
/// automatic invocation or Sign in with Apple identity dependency.
@available(iOS 15.0, macOS 12.0, *)
final class CloudSyncCloudKitPrivateDatabaseClient {
    private let container: CKContainer
    private let database: CKDatabase
    private let syncZoneID = CKRecordZone.ID(
        zoneName: "StyleMatchSyncV1",
        ownerName: CKCurrentUserDefaultName
    )

    init(container: CKContainer = CKContainer(identifier: "iCloud.com.sabastine.stylematchai")) {
        self.container = container
        database = container.privateCloudDatabase
    }

    private func ensureSyncZone() async throws {
        _ = try await database.save(CKRecordZone(zoneID: syncZoneID))
    }

    func accountStatus() async throws -> CKAccountStatus {
        try await container.accountStatus()
    }

    /// The opaque private-database identity is held only in local guard state.
    /// It is never used as a Sign in with Apple substitute or sent in a record.
    func privateDatabaseIdentity() async throws -> CloudSyncPrivateDatabaseIdentity? {
        guard try await accountStatus() == .available else { return nil }
        let recordID = try await container.userRecordID()
        return CloudSyncPrivateDatabaseIdentity(stableAccountChangeToken: recordID.recordName)
    }

    func save(_ records: [CloudSyncRecord]) async throws -> [CloudSyncRecord] {
        var saved: [CloudSyncRecord] = []
        for record in records where CloudSyncEligibility.permits(record) {
            saved.append(try await save(record, asset: nil))
        }
        return saved
    }

    func save(_ record: CloudSyncRecord, asset: CloudSyncAssetUpload?) async throws -> CloudSyncRecord {
        try await ensureSyncZone()
        let encoded = try CloudSyncCloudKitRecordCodec.makeRecord(from: record, zoneID: syncZoneID)
        var temporaryAssetURL: URL?
        defer {
            if let temporaryAssetURL { try? FileManager.default.removeItem(at: temporaryAssetURL) }
        }

        if let asset {
            guard asset.reference.owningRecordID == record.id else {
                throw CloudSyncCloudKitRecordCodec.DecodeError.recordIdentifierMismatch
            }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("StyleMatchCloudSync-\(UUID().uuidString)")
                .appendingPathExtension("jpg")
            try asset.data.write(to: url, options: .atomic)
            temporaryAssetURL = url
            try CloudSyncCloudKitRecordCodec.attachAsset(
                reference: asset.reference,
                sourceFileURL: url,
                to: encoded
            )
        }

        let persisted = try await database.save(encoded)
        return try CloudSyncCloudKitRecordCodec.decode(persisted)
    }

    func fetch(recordIDs: [String]) async throws -> [CloudSyncRecord] {
        try await ensureSyncZone()
        var fetched: [CloudSyncRecord] = []
        for stableID in Set(recordIDs).sorted() {
            let record = try await database.record(for: CKRecord.ID(recordName: stableID, zoneID: syncZoneID))
            fetched.append(try CloudSyncCloudKitRecordCodec.decode(record))
        }
        return fetched
    }

    func fetchAsset(recordID: String) async throws -> CloudSyncAssetDownload {
        try await ensureSyncZone()
        let record = try await database.record(for: CKRecord.ID(recordName: recordID, zoneID: syncZoneID))
        _ = try CloudSyncCloudKitRecordCodec.decode(record)
        let (reference, url) = try CloudSyncCloudKitRecordCodec.decodeAssetReference(from: record)
        return CloudSyncAssetDownload(reference: reference, data: try Data(contentsOf: url))
    }

    /// Enumerates only the active private database and advances opaque server
    /// tokens. Tokens are retained by the coordinator only after every local
    /// authority application in the batch succeeds.
    func discoverChanges(since cursor: CloudSyncDiscoveryCursor) async throws -> CloudSyncDiscoveryBatch {
        try await ensureSyncZone()

        // StyleMatch owns one private custom zone. Change-token APIs are
        // reliable for custom zones; the CloudKit default zone is not used for
        // incremental synchronization. This also keeps legacy diagnostic
        // records in the default zone isolated from the 18049 OwnerBeta lane.
        let zoneResult: (records: [CKRecord], tokens: [String: Data])
        do {
            zoneResult = try await fetchRecordChanges(
                in: [syncZoneID],
                previousTokens: cursor.zoneTokens
            )
        } catch let error as CKError where error.code == .changeTokenExpired {
            return CloudSyncDiscoveryBatch(
                changes: [],
                nextCursor: .initial,
                requiresFullRediscovery: true
            )
        }

        let changes = try zoneResult.records.map { record -> CloudSyncDiscoveredChange in
            let decoded = try CloudSyncCloudKitRecordCodec.decode(record)
            let asset: CloudSyncAssetDownload?
            if decoded.kind == .savedScan {
                // A record whose metadata arrives before its CKAsset is still
                // a valid discovery event. The reconciliation coordinator
                // stages it and refuses token advancement until a later fetch
                // supplies an exact valid asset.
                asset = try? Self.downloadAsset(from: record)
            } else { asset = nil }
            return CloudSyncDiscoveredChange(record: decoded, asset: asset)
        }
        return CloudSyncDiscoveryBatch(
            changes: changes,
            nextCursor: CloudSyncDiscoveryCursor(
                databaseToken: nil,
                zoneTokens: zoneResult.tokens
            ),
            requiresFullRediscovery: false
        )
    }

    private static func downloadAsset(from record: CKRecord) throws -> CloudSyncAssetDownload {
        let (reference, url) = try CloudSyncCloudKitRecordCodec.decodeAssetReference(from: record)
        return CloudSyncAssetDownload(reference: reference, data: try Data(contentsOf: url))
    }

    private static func encodeToken(_ token: CKServerChangeToken?) -> Data? {
        guard let token else { return nil }
        return try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
    }

    private static func decodeToken(_ data: Data?) -> CKServerChangeToken? {
        guard let data else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
    }

    private func fetchDatabaseChanges(since token: CKServerChangeToken?) async throws -> (zones: Set<CKRecordZone.ID>, token: CKServerChangeToken?) {
        try await withCheckedThrowingContinuation { continuation in
            var zones = Set<CKRecordZone.ID>()
            let operation = CKFetchDatabaseChangesOperation(previousServerChangeToken: token)
            operation.fetchAllChanges = true
            operation.recordZoneWithIDChangedBlock = { zones.insert($0) }
            operation.fetchDatabaseChangesCompletionBlock = { next, _, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: (zones, next)) }
            }
            database.add(operation)
        }
    }

    private func fetchRecordChanges(in zones: [CKRecordZone.ID], previousTokens: [String: Data]) async throws -> (records: [CKRecord], tokens: [String: Data]) {
        try await withCheckedThrowingContinuation { continuation in
            var records: [CKRecord] = []
            var tokens = previousTokens
            var configurations: [CKRecordZone.ID: CKFetchRecordZoneChangesOperation.ZoneConfiguration] = [:]
            for zone in zones {
                let configuration = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
                configuration.previousServerChangeToken = Self.decodeToken(previousTokens[Self.zoneTokenKey(zone)])
                configurations[zone] = configuration
            }
            let operation = CKFetchRecordZoneChangesOperation(recordZoneIDs: zones, configurationsByRecordZoneID: configurations)
            operation.fetchAllChanges = true
            operation.recordChangedBlock = { records.append($0) }
            operation.recordZoneFetchCompletionBlock = { zone, token, _, _, error in
                guard error == nil else { return }
                if let encoded = Self.encodeToken(token) { tokens[Self.zoneTokenKey(zone)] = encoded }
            }
            operation.fetchRecordZoneChangesCompletionBlock = { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: (records, tokens)) }
            }
            database.add(operation)
        }
    }

    private static func zoneTokenKey(_ zone: CKRecordZone.ID) -> String {
        "\(zone.ownerName)|\(zone.zoneName)"
    }
}

extension CloudSyncCloudKitPrivateDatabaseClient: CloudSyncInboundTransport {}

enum CloudSyncAssetIntegrity {
    static func accepts(
        reference: CloudSyncAssetReference,
        forRecordID recordID: String,
        sha256: String,
        byteCount: Int64
    ) -> Bool {
        reference.owningRecordID == recordID
            && reference.sha256 == sha256
            && reference.byteCount == byteCount
    }
}

/// Profile changes merge per allowlisted field. A conflicting field chooses
/// the latest mutation timestamp; ties use a deterministic value comparison.
/// Unrelated fields are never overwritten as a whole-profile side effect.
struct CloudSyncProfileField: Codable, Equatable, Sendable {
    let key: String
    let value: String
    let modifiedAt: Date
}

enum CloudSyncProfileFieldMerger {
    static func merge(
        local: [CloudSyncProfileField],
        remote: [CloudSyncProfileField]
    ) -> [CloudSyncProfileField] {
        var selected: [String: CloudSyncProfileField] = [:]
        for field in local + remote {
            guard let existing = selected[field.key] else {
                selected[field.key] = field
                continue
            }
            if field.modifiedAt > existing.modifiedAt
                || (field.modifiedAt == existing.modifiedAt && field.value > existing.value) {
                selected[field.key] = field
            }
        }
        return selected.values.sorted { $0.key < $1.key }
    }
}

enum CloudSyncMergeDecision: Equatable, Sendable {
    case keepLocal
    case useRemote
    case identical
}

enum CloudSyncReconciler {
    /// Object-level reconciliation only. Different records never overwrite one
    /// another. For the same stable object ID, a newer mutation wins; equal-time
    /// ties are deterministic so retry order cannot produce duplicates.
    static func decision(local: CloudSyncRecord, remote: CloudSyncRecord) -> CloudSyncMergeDecision {
        precondition(local.id == remote.id && local.kind == remote.kind)

        if local == remote { return .identical }
        if local.modifiedAt != remote.modifiedAt {
            return local.modifiedAt > remote.modifiedAt ? .keepLocal : .useRemote
        }
        if local.isDeleted != remote.isDeleted {
            return local.isDeleted ? .keepLocal : .useRemote
        }
        if local.payload == remote.payload { return .identical }
        return local.payload.lexicographicallyPrecedes(remote.payload) ? .useRemote : .keepLocal
    }

    static func deduplicated(_ records: [CloudSyncRecord]) -> [CloudSyncRecord] {
        var selected: [String: CloudSyncRecord] = [:]
        for record in records where CloudSyncEligibility.permits(record) {
            guard let existing = selected[record.id] else {
                selected[record.id] = record
                continue
            }
            precondition(existing.kind == record.kind, "Stable record IDs cannot cross record kinds")
            if decision(local: existing, remote: record) == .useRemote {
                selected[record.id] = record
            }
        }
        return selected.values.sorted { $0.id < $1.id }
    }
}

enum CloudSyncTombstonePolicy {
    /// A deletion marker remains syncable so an old offline device cannot
    /// recreate a deleted record during a later retry.
    static func shouldApply(_ record: CloudSyncRecord) -> Bool {
        record.isDeleted && CloudSyncEligibility.permits(record)
    }
}

/// Queues only allowlisted record mutations. A failed upload is retained until
/// a later reconciliation succeeds; local data is never discarded on failure.
struct CloudSyncOfflineQueue: Equatable, Sendable {
    private(set) var pendingByRecordID: [String: CloudSyncRecord] = [:]

    var records: [CloudSyncRecord] {
        pendingByRecordID.values.sorted { $0.id < $1.id }
    }

    mutating func enqueue(_ record: CloudSyncRecord) {
        guard CloudSyncEligibility.permits(record) else { return }
        guard let existing = pendingByRecordID[record.id] else {
            pendingByRecordID[record.id] = record
            return
        }
        if CloudSyncReconciler.decision(local: existing, remote: record) == .useRemote {
            pendingByRecordID[record.id] = record
        }
    }

    mutating func acknowledge(_ records: [CloudSyncRecord]) {
        for record in records {
            guard let pending = pendingByRecordID[record.id], pending == record else { continue }
            pendingByRecordID.removeValue(forKey: record.id)
        }
    }
}

enum CloudSyncMigrationState: String, Codable, Sendable {
    case notStarted
    case inProgress
    case completed
    case failedIntegrityCheck
}

struct CloudSyncMigrationPlan: Equatable, Sendable {
    private(set) var state: CloudSyncMigrationState = .notStarted

    mutating func begin(localRecords: [CloudSyncRecord]) -> [CloudSyncRecord]? {
        guard state == .notStarted else { return nil }
        guard localRecords.allSatisfy(CloudSyncEligibility.permits) else {
            state = .failedIntegrityCheck
            return nil
        }
        let deduplicated = CloudSyncReconciler.deduplicated(localRecords)
        guard deduplicated.count == Set(deduplicated.map(\.id)).count else {
            state = .failedIntegrityCheck
            return nil
        }
        state = .inProgress
        return deduplicated
    }

    mutating func completeAfterRemoteAcknowledgement() {
        guard state == .inProgress else { return }
        state = .completed
    }

    mutating func resumeAfterInterruption() -> Bool {
        state == .inProgress
    }
}

struct CloudSyncPresentation: Equatable, Sendable {
    let status: CloudSyncStatus

    var title: String { status.title }

    var detail: String {
        switch status {
        case .off:
            return "Cloud Sync is off. Your data remains on this device."
        case .syncing:
            return "Syncing eligible profile, closet, saved scan, favorites, watch-list, and explicitly saved AI Memory data."
        case .upToDate:
            return "Eligible data is up to date for this iCloud account."
        case .needsAttention:
            return "Cloud Sync needs iCloud setup or attention. Local data remains available and is not moved into another iCloud account."
        case .offline:
            return "This device is offline. Eligible local changes are queued until iCloud is available."
        }
    }

    static let eligibleCategories = [
        "Profile preferences, sizes, fit and style settings, and occasions",
        "Closet items",
        "Saved scans with their exact saved score, timestamp, occasion, metadata, and associated image asset when available",
        "Favorites and watch lists",
        "Only AI Memory that you explicitly saved"
    ]
}
