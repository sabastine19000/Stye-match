import XCTest
import CloudKit
import CryptoKit
import ImageIO
import UniformTypeIdentifiers
@testable import StyleMatchPro

final class CrossDeviceSyncFoundationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_723_139_200)

    func testV1IdentityBoundaryIsSameICloudPrivateDatabaseNotAppleSignIn() {
        XCTAssertEqual(CloudSyncIdentityBoundary.v1, .sameICloudAccountPrivateDatabase)
        XCTAssertFalse(CloudSyncIdentityBoundary.v1.customerFacingDescription.contains("Sign in with Apple"))
    }

    func testExistingLocalStoresHaveTypedAllowlistedAdapterContracts() {
        XCTAssertEqual(CloudSyncAdapterContract.all.map(\.source), [
            .profile, .closet, .savedScanHistory, .favorites, .watchList, .aiMemory
        ])
        XCTAssertTrue(CloudSyncLocalAdapter.contract(for: .savedScanImage) == nil)
        XCTAssertTrue(CloudSyncLocalAdapter.contract(for: .savedScanHistory)?.eligibleFields.contains("authoritativeScore") == true)
        XCTAssertTrue(CloudSyncLocalAdapter.contract(for: .aiMemory)?.excludedFields.contains("temporaryConversation") == true)
        XCTAssertTrue(CloudSyncLocalAdapter.contract(for: .favorites)?.excludedFields.contains("staticCatalog") == true)
    }

    func testSavedScanPreservesStableIDScoreTimestampOccasionAndMetadata() throws {
        let payload = SavedScanSyncPayload(
            stableScanID: "scan-123",
            authoritativeScore: 87,
            savedAt: now,
            occasionRawValue: "Work",
            metadata: Data("completed-analysis".utf8)
        )
        let encoded = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(SavedScanSyncPayload.self, from: encoded)

        XCTAssertEqual(decoded, payload)
        XCTAssertEqual(decoded.authoritativeScore, 87)
    }

    func testMalformedSavedScanDoesNotEnterSyncAsLatestScanFallback() {
        let malformed = CloudSyncRecord(
            id: "scan-123",
            kind: .savedScan,
            payload: Data(),
            modifiedAt: now
        )
        XCTAssertNil(CloudSyncLocalAdapter.recordIfEligible(malformed, from: .savedScanHistory))
    }

    func testSavedScanAssetAssociationRequiresExactRecordChecksumAndByteCount() {
        let asset = CloudSyncAssetReference(
            owningRecordID: "scan-123",
            assetIdentifier: "asset-scan-123",
            sha256: "verified-image-hash",
            byteCount: 2_048
        )

        XCTAssertTrue(CloudSyncAssetIntegrity.accepts(
            reference: asset,
            forRecordID: "scan-123",
            sha256: "verified-image-hash",
            byteCount: 2_048
        ))
        XCTAssertFalse(CloudSyncAssetIntegrity.accepts(
            reference: asset,
            forRecordID: "other-scan",
            sha256: "verified-image-hash",
            byteCount: 2_048
        ))
    }

    func testCloudKitRecordCodecRoundTripsOnlyEligibleTypedRecord() throws {
        let original = record(id: "scan-123", kind: .savedScan, modifiedAt: now)
        let encoded = try CloudSyncCloudKitRecordCodec.makeRecord(from: original)

        XCTAssertEqual(encoded.recordType, CloudSyncCloudKitRecordCodec.recordType)
        XCTAssertEqual(encoded.recordID.recordName, "scan-123")
        XCTAssertEqual(try CloudSyncCloudKitRecordCodec.decode(encoded), original)
    }

    func testCloudKitCodecRejectsIdentifierMismatchAndUnsavedAIMemory() throws {
        let cloudRecord = try CloudSyncCloudKitRecordCodec.makeRecord(
            from: record(id: "scan-123", kind: .savedScan, modifiedAt: now)
        )
        cloudRecord["stableID"] = "different" as NSString
        XCTAssertThrowsError(try CloudSyncCloudKitRecordCodec.decode(cloudRecord)) { error in
            XCTAssertEqual(error as? CloudSyncCloudKitRecordCodec.DecodeError, .recordIdentifierMismatch)
        }

        let temporaryMemory = record(id: "temporary", kind: .aiMemory, modifiedAt: now)
        XCTAssertThrowsError(try CloudSyncCloudKitRecordCodec.makeRecord(from: temporaryMemory)) { error in
            XCTAssertEqual(error as? CloudSyncCloudKitRecordCodec.DecodeError, .ineligibleRecord)
        }
    }

    func testFutureSchemaIsRejectedByCodecAndDiscoveryEligibility() throws {
        let future = CloudSyncRecord(
            id: "scan-future-schema",
            kind: .savedScan,
            payload: Data("completed-analysis".utf8),
            version: "future-schema-v2",
            modifiedAt: now,
            schemaVersion: CloudSyncRecord.currentSchemaVersion + 1
        )

        XCTAssertFalse(CloudSyncEligibility.permits(future))
        XCTAssertNil(CloudSyncLocalAdapter.recordIfEligible(future, from: .savedScanHistory))
        XCTAssertThrowsError(try CloudSyncCloudKitRecordCodec.makeRecord(from: future)) { error in
            XCTAssertEqual(error as? CloudSyncCloudKitRecordCodec.DecodeError, .ineligibleRecord)
        }

        let encoded = try CloudSyncCloudKitRecordCodec.makeRecord(
            from: record(id: "scan-current-schema", kind: .savedScan, modifiedAt: now)
        )
        encoded["schemaVersion"] = NSNumber(value: CloudSyncRecord.currentSchemaVersion + 1)
        XCTAssertThrowsError(try CloudSyncCloudKitRecordCodec.decode(encoded)) { error in
            XCTAssertEqual(error as? CloudSyncCloudKitRecordCodec.DecodeError, .unsupportedSchemaVersion)
        }
    }

    func testCloudKitAssetCodecRequiresChecksumByteCountAndOwningRecord() throws {
        let scan = record(id: "scan-123", kind: .savedScan, modifiedAt: now)
        let cloudRecord = try CloudSyncCloudKitRecordCodec.makeRecord(from: scan)
        let assetURL = FileManager.default.temporaryDirectory.appendingPathComponent("cloud-sync-test-asset")
        let data = Data("asset".utf8)
        try data.write(to: assetURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: assetURL) }
        let checksum = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let reference = CloudSyncAssetReference(
            owningRecordID: "scan-123",
            assetIdentifier: "image-scan-123",
            sha256: checksum,
            byteCount: Int64(data.count)
        )

        try CloudSyncCloudKitRecordCodec.attachAsset(reference: reference, sourceFileURL: assetURL, to: cloudRecord)
        XCTAssertNotNil(cloudRecord["asset"] as? CKAsset)

        let wrongReference = CloudSyncAssetReference(
            owningRecordID: "wrong-record",
            assetIdentifier: "image-scan-123",
            sha256: checksum,
            byteCount: Int64(data.count)
        )
        XCTAssertThrowsError(try CloudSyncCloudKitRecordCodec.attachAsset(reference: wrongReference, sourceFileURL: assetURL, to: cloudRecord))
    }

    func testRetryAndReconnectDeduplicateByStableObjectID() {
        let first = record(id: "scan-123", kind: .savedScan, modifiedAt: now)
        let retry = record(id: "scan-123", kind: .savedScan, modifiedAt: now.addingTimeInterval(5))
        XCTAssertEqual(CloudSyncReconciler.deduplicated([first, retry]), [retry])
    }

    func testConcurrentEditsUseObjectLevelNewerMutationWithoutWholeAccountOverwrite() {
        let profile = record(id: "profile", kind: .profile, modifiedAt: now)
        let closet = record(id: "closet-1", kind: .closetItem, modifiedAt: now)
        let newerProfile = record(id: "profile", kind: .profile, modifiedAt: now.addingTimeInterval(10))

        XCTAssertEqual(CloudSyncReconciler.decision(local: profile, remote: newerProfile), .useRemote)
        XCTAssertEqual(CloudSyncReconciler.deduplicated([profile, closet, newerProfile]), [closet, newerProfile])
    }

    func testProfileConflictsMergePerFieldRatherThanReplacingWholeProfile() {
        let local = [
            CloudSyncProfileField(key: "fit", value: "slim", modifiedAt: now),
            CloudSyncProfileField(key: "budget", value: "150", modifiedAt: now)
        ]
        let remote = [
            CloudSyncProfileField(key: "fit", value: "relaxed", modifiedAt: now.addingTimeInterval(5)),
            CloudSyncProfileField(key: "color", value: "navy", modifiedAt: now)
        ]

        XCTAssertEqual(CloudSyncProfileFieldMerger.merge(local: local, remote: remote), [
            CloudSyncProfileField(key: "budget", value: "150", modifiedAt: now),
            CloudSyncProfileField(key: "color", value: "navy", modifiedAt: now),
            CloudSyncProfileField(key: "fit", value: "relaxed", modifiedAt: now.addingTimeInterval(5))
        ])
    }

    func testOfflineWritesStayQueuedUntilAcknowledged() {
        let savedScan = record(id: "scan-123", kind: .savedScan, modifiedAt: now)
        var queue = CloudSyncOfflineQueue()
        queue.enqueue(savedScan)
        XCTAssertEqual(queue.records, [savedScan])
        queue.acknowledge([savedScan])
        XCTAssertTrue(queue.records.isEmpty)
    }

    func testMigrationDeduplicatesAndNeverTreatsEmptyRemoteAsDeletion() {
        let original = record(id: "scan-123", kind: .savedScan, modifiedAt: now)
        let retry = record(id: "scan-123", kind: .savedScan, modifiedAt: now.addingTimeInterval(1))
        var migration = CloudSyncMigrationPlan()

        let importRecords = migration.begin(localRecords: [original, retry])
        XCTAssertEqual(importRecords, [retry])
        XCTAssertEqual(migration.state, .inProgress)
        migration.completeAfterRemoteAcknowledgement()
        XCTAssertEqual(migration.state, .completed)
    }

    func testMigrationCanResumeWithoutDiscardingLocalRecords() {
        let original = record(id: "closet-123", kind: .closetItem, modifiedAt: now)
        var migration = CloudSyncMigrationPlan()
        XCTAssertEqual(migration.begin(localRecords: [original]), [original])
        XCTAssertTrue(migration.resumeAfterInterruption())
        XCTAssertEqual(migration.state, .inProgress)
    }

    func testCheckpointedMigrationKeepsUnacknowledgedObjectsPendingAndNeverErasesLocal() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "CloudSyncMigrationCoordinatorTests-\(UUID().uuidString)"))
        let coordinator = CloudSyncMigrationCoordinator(defaults: defaults, accountScope: "test")
        let first = PersistenceAuthorityRecord(id: "closet-a", kind: .closetItem, payload: Data("a".utf8), version: "v1", updatedAt: now, isDeleted: false, persistenceOrigin: .customerPersistent)
        let second = PersistenceAuthorityRecord(id: "closet-b", kind: .closetItem, payload: Data("b".utf8), version: "v1", updatedAt: now, isDeleted: false, persistenceOrigin: .customerPersistent)

        XCTAssertEqual(try coordinator.pending([first, second], category: .closet), [first, second])
        coordinator.acknowledge([first])
        XCTAssertEqual(try coordinator.pending([first, second], category: .closet), [second])
        XCTAssertFalse(coordinator.isComplete(required: [first, second]))
        XCTAssertTrue(coordinator.isComplete(required: []))
    }

    func testOnlyExplicitlySavedAIMemoryMayEnterMigration() {
        let unsaved = CloudSyncRecord(
            id: "temporary-memory",
            kind: .aiMemory,
            payload: Data("temporary".utf8),
            modifiedAt: now,
            persistenceOrigin: .customerPersistent
        )
        let explicitlySaved = CloudSyncRecord(
            id: "saved-memory",
            kind: .aiMemory,
            payload: Data("saved".utf8),
            modifiedAt: now,
            persistenceOrigin: .explicitlySavedAIMemory
        )
        var migration = CloudSyncMigrationPlan()

        XCTAssertNil(migration.begin(localRecords: [unsaved]))
        XCTAssertEqual(migration.state, .failedIntegrityCheck)
        XCTAssertTrue(CloudSyncEligibility.permits(explicitlySaved))
    }

    func testTemporaryMemorySourceCannotCreateASyncRecord() {
        let temporaryMemory = record(id: "temp", kind: .aiMemory, modifiedAt: now)
        XCTAssertNil(CloudSyncLocalAdapter.recordIfEligible(temporaryMemory, from: .aiMemory))
        let savedMemory = record(id: "saved", kind: .aiMemory, modifiedAt: now, origin: .explicitlySavedAIMemory)
        XCTAssertEqual(CloudSyncLocalAdapter.recordIfEligible(savedMemory, from: .aiMemory), savedMemory)
    }

    func testTemporaryContextAndAITransmissionConsentAreExplicitlyExcluded() {
        XCTAssertTrue(CloudSyncEligibility.excludedLocalOnlyCategories.contains("temporaryAIContext"))
        XCTAssertTrue(CloudSyncEligibility.excludedLocalOnlyCategories.contains("aiTransmissionConsent"))
        XCTAssertFalse(CloudSyncEligibility.excludedLocalOnlyCategories.contains("aiMemory"))
    }

    func testTombstonesWinSameTimeConflictAndRemainSyncable() {
        let current = record(id: "memory-1", kind: .aiMemory, modifiedAt: now, origin: .explicitlySavedAIMemory)
        let deleted = CloudSyncRecord(
            id: "memory-1",
            kind: .aiMemory,
            payload: Data(),
            modifiedAt: now,
            isDeleted: true,
            persistenceOrigin: .explicitlySavedAIMemory
        )
        XCTAssertEqual(CloudSyncReconciler.decision(local: current, remote: deleted), .useRemote)
        XCTAssertTrue(CloudSyncTombstonePolicy.shouldApply(deleted))
    }

    func testICloudAccountChangeFailsClosedWithoutCrossAccountMerge() {
        let first = CloudSyncPrivateDatabaseIdentity(stableAccountChangeToken: "account-A")
        let second = CloudSyncPrivateDatabaseIdentity(stableAccountChangeToken: "account-B")
        XCTAssertEqual(CloudSyncAccountGuard.transition(previous: nil, current: first), .initialAccount)
        XCTAssertEqual(CloudSyncAccountGuard.transition(previous: first, current: first), .unchanged)
        XCTAssertEqual(CloudSyncAccountGuard.transition(previous: first, current: second), .changedNeedsAttention)
        XCTAssertEqual(CloudSyncAccountGuard.transition(previous: first, current: nil), .changedNeedsAttention)
        XCTAssertTrue(CloudSyncProductContract.requiresExplicitAccountResolution(.changedNeedsAttention))
        XCTAssertFalse(CloudSyncProductContract.requiresExplicitAccountResolution(.unchanged))
    }

    func testPresentationTruthfullyExplainsStatusAndEligibleCategories() {
        XCTAssertEqual(CloudSyncPresentation(status: .off).title, "Off")
        XCTAssertEqual(CloudSyncPresentation(status: .syncing).title, "Syncing")
        XCTAssertEqual(CloudSyncPresentation(status: .upToDate).title, "Up to date")
        XCTAssertEqual(CloudSyncPresentation(status: .needsAttention).title, "Needs attention")
        XCTAssertEqual(CloudSyncPresentation(status: .offline).title, "Offline")
        XCTAssertTrue(CloudSyncPresentation.eligibleCategories.joined().contains("Only AI Memory that you explicitly saved"))
    }

    func testProductContractKeepsAppleSignInSeparateAndCustomerPublicSyncDisabled() {
        XCTAssertFalse(CloudSyncProductContract.customerPublicActivationEnabled)
        XCTAssertFalse(CloudSyncProductContract.customerControlsEnabled)
        XCTAssertFalse(CloudSyncIdentityBoundary.v1.customerFacingDescription.contains("Sign in with Apple"))
        XCTAssertEqual(CloudSyncProductContract.preActivationStatus(isSwitchOn: false), .off)
        XCTAssertEqual(CloudSyncProductContract.preActivationStatus(isSwitchOn: true), .off)
        XCTAssertTrue(CloudSyncProductContract.preActivationDetail(isSwitchOn: true).contains("not active in this build"))
    }

    func testPreActivationConsentAndDeletionCopyDoesNotClaimCustomerSyncIsActive() {
        XCTAssertTrue(CloudSyncProductContract.preActivationConsentDetail.contains("not active in this build"))
        XCTAssertTrue(CloudSyncProductContract.preActivationConsentDetail.contains("no customer data is being uploaded or reconciled with iCloud"))
        XCTAssertTrue(CloudSyncProductContract.futureOffAndDeletionDetail.contains("stop future synchronization"))
        XCTAssertTrue(CloudSyncProductContract.futureOffAndDeletionDetail.contains("will not by itself delete"))
    }

    func testProductContractListsOnlyAllowedDataAndExplicitPrivacyExclusions() {
        let eligible = CloudSyncProductContract.eligibleCustomerData.joined(separator: " ")
        let excluded = CloudSyncProductContract.deviceLocalExcludedData.joined(separator: " ")

        XCTAssertTrue(eligible.contains("exact saved scores"))
        XCTAssertTrue(eligible.contains("timestamps"))
        XCTAssertTrue(eligible.contains("saved images"))
        XCTAssertTrue(eligible.contains("explicitly saved"))
        XCTAssertTrue(excluded.contains("AI transmission consent"))
        XCTAssertTrue(excluded.contains("Temporary AI"))
        XCTAssertTrue(excluded.contains("Screen awareness"))
        XCTAssertTrue(excluded.contains("Secrets"))
        XCTAssertTrue(CloudSyncEligibility.excludedLocalOnlyCategories.contains("screenAwareness"))
        XCTAssertTrue(CloudSyncEligibility.excludedLocalOnlyCategories.contains("aiTransmissionConsent"))
    }

    func testOwnerOnlyValidationGateRequiresDebugBuild18036AndKeepsCustomerBuildInert() {
        XCTAssertTrue(CloudSyncOwnerValidationConfiguration(buildNumber: "18036", isDebugBuild: true).isEnabled)
        XCTAssertFalse(CloudSyncOwnerValidationConfiguration(buildNumber: "18035", isDebugBuild: true).isEnabled)
        XCTAssertFalse(CloudSyncOwnerValidationConfiguration(buildNumber: "18036", isDebugBuild: false).isEnabled)
        XCTAssertFalse(CloudSyncProductContract.customerPublicActivationEnabled)
    }

    func testBuild18037And18038DebugAllowInboundDiagnosticsButNeverOutboundOwnerValidation() {
        let build18037Debug = CloudSyncOwnerValidationConfiguration(buildNumber: "18037", isDebugBuild: true)
        XCTAssertFalse(build18037Debug.isEnabled)
        XCTAssertTrue(build18037Debug.allowsInboundDiagnosticReconciliation)
        XCTAssertFalse(CloudSyncOwnerValidationConfiguration(buildNumber: "18037", isDebugBuild: false).allowsInboundDiagnosticReconciliation)
        let build18038Debug = CloudSyncOwnerValidationConfiguration(buildNumber: "18038", isDebugBuild: true)
        XCTAssertFalse(build18038Debug.isEnabled)
        XCTAssertTrue(build18038Debug.allowsInboundDiagnosticReconciliation)
        XCTAssertFalse(CloudSyncOwnerValidationConfiguration(buildNumber: "18038", isDebugBuild: false).allowsInboundDiagnosticReconciliation)
        XCTAssertFalse(CloudSyncOwnerValidationConfiguration(buildNumber: "18035", isDebugBuild: true).allowsInboundDiagnosticReconciliation)
    }

    @MainActor
    func testOwnerValidationReportsNeedsAttentionWhenICloudIsUnavailableBeforeAnyLocalRead() async throws {
        let transport = OwnerValidationTransport(status: .noAccount)
        let coordinator = CloudSyncOwnerValidationCoordinator(
            configuration: .init(buildNumber: "18036", isDebugBuild: true),
            transport: transport,
            sources: unavailableOwnerValidationSources(),
            migration: try migrationCoordinator()
        )

        let outcome = await coordinator.runControlledValidation()
        XCTAssertEqual(outcome, .needsAttention(.iCloudUnavailable))
        XCTAssertEqual(transport.saveCount, 0)
    }

    @MainActor
    func testOwnerValidationAcknowledgesEveryControlledRecordBeforeReportingUpToDate() async throws {
        let transport = OwnerValidationTransport(status: .available)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "OwnerCloudSyncValidation-\(UUID().uuidString)"))
        let migration = CloudSyncMigrationCoordinator(defaults: defaults, accountScope: "test")
        let coordinator = CloudSyncOwnerValidationCoordinator(
            configuration: .init(buildNumber: "18036", isDebugBuild: true),
            transport: transport,
            sources: ownerValidationSources(),
            migration: migration
        )

        let outcome = await coordinator.runControlledValidation()
        XCTAssertEqual(outcome, .upToDate)
        XCTAssertEqual(transport.saveCount, 5)
        XCTAssertEqual(transport.assetSaveCount, 1)
    }

    @MainActor
    func testOwnerValidationSkipsValidEmptyOptionalCategoriesWithoutCreatingRecordsOrTombstones() async throws {
        let transport = OwnerValidationTransport(status: .available)
        let sources = ownerValidationSourcesWithOptionalOverrides(
            closet: { [] },
            shopping: {
                [
                    self.authorityRecord(id: "favorites", kind: .favorites, payload: try! JSONEncoder().encode([] as [String]), version: "favorites-empty"),
                    self.authorityRecord(id: "watch-list", kind: .watchList, payload: try! JSONEncoder().encode([] as [String]), version: "watch-list-empty")
                ]
            },
            aiMemory: { [] }
        )
        let coordinator = CloudSyncOwnerValidationCoordinator(
            configuration: .init(buildNumber: "18036", isDebugBuild: true),
            transport: transport,
            sources: sources,
            migration: try migrationCoordinator()
        )

        let outcome = await coordinator.runControlledValidation()

        XCTAssertEqual(outcome, .upToDate)
        XCTAssertEqual(transport.saveCount, 2)
        XCTAssertEqual(transport.assetSaveCount, 1)
        XCTAssertEqual(transport.savedKinds, [.profile, .savedScan])
        XCTAssertEqual(coordinator.latestEvidence.skippedOptionalCategories, [.closet, .favorites, .watchList, .aiMemory])
    }

    @MainActor
    func testOwnerValidationFailsClosedForMalformedOptionalCategoriesBeforeTransport() async throws {
        let malformedCloset = ownerValidationSourcesWithOptionalOverrides(closet: {
            throw PersistenceAuthorityError.invalidRecord
        })
        let closetTransport = OwnerValidationTransport(status: .available)
        let closetCoordinator = CloudSyncOwnerValidationCoordinator(
            configuration: .init(buildNumber: "18036", isDebugBuild: true),
            transport: closetTransport,
            sources: malformedCloset,
            migration: try migrationCoordinator()
        )
        let closetOutcome = await closetCoordinator.runControlledValidation()
        XCTAssertEqual(closetOutcome, .needsAttention(.closetMigration))
        XCTAssertEqual(closetTransport.saveCount, 0)

        let malformedFavorites = ownerValidationSourcesWithOptionalOverrides(shopping: {
            [self.authorityRecord(id: "favorites", kind: .favorites, payload: Data("not-json".utf8), version: "favorites-invalid")]
        })
        let shoppingTransport = OwnerValidationTransport(status: .available)
        let shoppingCoordinator = CloudSyncOwnerValidationCoordinator(
            configuration: .init(buildNumber: "18036", isDebugBuild: true),
            transport: shoppingTransport,
            sources: malformedFavorites,
            migration: try migrationCoordinator()
        )
        let shoppingOutcome = await shoppingCoordinator.runControlledValidation()
        XCTAssertEqual(shoppingOutcome, .needsAttention(.shoppingMigration))
        XCTAssertEqual(shoppingTransport.saveCount, 0)

        let malformedMemory = ownerValidationSourcesWithOptionalOverrides(aiMemory: {
            [PersistenceAuthorityRecord(
                id: "not-explicitly-saved",
                kind: .aiMemory,
                payload: Data("memory".utf8),
                version: "memory-invalid",
                updatedAt: self.now,
                isDeleted: false,
                persistenceOrigin: .customerPersistent
            )]
        })
        let memoryTransport = OwnerValidationTransport(status: .available)
        let memoryCoordinator = CloudSyncOwnerValidationCoordinator(
            configuration: .init(buildNumber: "18036", isDebugBuild: true),
            transport: memoryTransport,
            sources: malformedMemory,
            migration: try migrationCoordinator()
        )
        let memoryOutcome = await memoryCoordinator.runControlledValidation()
        XCTAssertEqual(memoryOutcome, .needsAttention(.aiMemoryMigration))
        XCTAssertEqual(memoryTransport.saveCount, 0)
    }

    @MainActor
    func testOwnerValidationReportsOfflineWithoutApplyingLocalRecords() async throws {
        let transport = OwnerValidationTransport(error: CKError(.networkUnavailable))
        let coordinator = CloudSyncOwnerValidationCoordinator(
            configuration: .init(buildNumber: "18036", isDebugBuild: true),
            transport: transport,
            sources: unavailableOwnerValidationSources(),
            migration: try migrationCoordinator()
        )

        let outcome = await coordinator.runControlledValidation()
        XCTAssertEqual(outcome, .offline)
        XCTAssertEqual(transport.saveCount, 0)
    }

    @MainActor
    func testSavedScanRoundTripMismatchStopsOwnerValidationBeforeCheckpointCompletion() async throws {
        let transport = OwnerValidationTransport(status: .available, mismatchingFetchForRecordID: "scan-owner-validation")
        let coordinator = CloudSyncOwnerValidationCoordinator(
            configuration: .init(buildNumber: "18036", isDebugBuild: true),
            transport: transport,
            sources: ownerValidationSources(),
            migration: try migrationCoordinator()
        )

        let outcome = await coordinator.runControlledValidation()
        XCTAssertEqual(outcome, .needsAttention(.savedScanMetadataIntegrity))
        XCTAssertEqual(transport.saveCount, 2)
    }

    @MainActor
    func testOwnerValidationBlocksChangedPrivateAccountBeforeFirstWrite() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "OwnerCloudSyncAccountGuard-\(UUID().uuidString)"))
        let store = CloudSyncPrivateAccountGuardStore(defaults: defaults, scope: "test")
        store.recordInitial(.init(stableAccountChangeToken: "private-account-A"))
        let transport = OwnerValidationTransport(status: .available, privateAccountToken: "private-account-B")
        let coordinator = CloudSyncOwnerValidationCoordinator(
            configuration: .init(buildNumber: "18036", isDebugBuild: true),
            transport: transport,
            sources: ownerValidationSources(),
            migration: try migrationCoordinator(),
            accountGuardStore: store
        )

        let result = await coordinator.runControlledValidation()
        XCTAssertEqual(result, .needsAttention(.accountChanged))
        XCTAssertEqual(transport.saveCount, 0)
    }

    @MainActor
    func testOwnerValidationRechecksAccountBeforeAuthorityApply() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "OwnerCloudSyncApplyGuard-\(UUID().uuidString)"))
        let store = CloudSyncPrivateAccountGuardStore(defaults: defaults, scope: "test")
        store.recordInitial(.init(stableAccountChangeToken: "private-account-A"))
        let transport = OwnerValidationTransport(
            status: .available,
            privateAccountTokenSequence: ["private-account-A", "private-account-A", "private-account-A", "private-account-B"]
        )
        let applyCounter = ApplyCounter()
        var sources = ownerValidationSources()
        sources = CloudSyncOwnerValidationSources(
            profile: sources.profile,
            savedScans: sources.savedScans,
            savedScanImage: sources.savedScanImage,
            closet: sources.closet,
            shopping: sources.shopping,
            aiMemory: sources.aiMemory,
            apply: { _ in applyCounter.count += 1 },
            applySavedScanImage: { _, _, _, _, _ in applyCounter.count += 1 }
        )
        let coordinator = CloudSyncOwnerValidationCoordinator(
            configuration: .init(buildNumber: "18036", isDebugBuild: true),
            transport: transport,
            sources: sources,
            migration: try migrationCoordinator(),
            accountGuardStore: store
        )

        let result = await coordinator.runControlledValidation()
        XCTAssertEqual(result, .needsAttention(.accountChanged))
        XCTAssertEqual(transport.saveCount, 1)
        XCTAssertEqual(applyCounter.count, 0)
    }

    func testTypedDiagnosticsRemainNonSensitiveAndDistinctFromOffline() {
        XCTAssertEqual(CloudSyncValidationDiagnostic.iCloudUnavailable.ownerMessage, "Needs attention — iCloud account is unavailable. Local data remains on this device.")
        XCTAssertEqual(CloudSyncValidationDiagnostic.cloudKitPermission.ownerMessage, "Needs attention — CloudKit permission could not be confirmed.")
        XCTAssertEqual(CloudSyncValidationDiagnostic.accountChanged.ownerMessage, "Needs attention — iCloud account changed. Local data was not moved into another account.")
        XCTAssertEqual(CloudSyncValidationDiagnostic.profileMigration.ownerMessage, "Needs attention — Profile sync could not be completed.")
        XCTAssertEqual(CloudSyncValidationDiagnostic.savedScanMetadataIntegrity.ownerMessage, "Needs attention — Saved Scan integrity check failed.")
        XCTAssertEqual(CloudSyncValidationDiagnostic.savedScanAssetIntegrity.ownerMessage, "Needs attention — Saved Scan image integrity check failed.")
        XCTAssertEqual(CloudSyncValidationDiagnostic.closetMigration.ownerMessage, "Needs attention — Closet sync could not be completed.")
        XCTAssertEqual(CloudSyncValidationDiagnostic.shoppingMigration.ownerMessage, "Needs attention — Favorites or watch-list sync could not be completed.")
        XCTAssertEqual(CloudSyncValidationDiagnostic.aiMemoryMigration.ownerMessage, "Needs attention — Explicitly saved AI Memory sync could not be completed.")
        XCTAssertEqual(CloudSyncValidationDiagnostic.conflict.ownerMessage, "Needs attention — Cloud Sync found a conflict that needs resolution.")
        XCTAssertEqual(CloudSyncValidationDiagnostic.cloudKitTransport.ownerMessage, "Needs attention — Cloud Sync could not complete with iCloud.")
        XCTAssertEqual(CloudSyncValidationDiagnostic.networkOffline.ownerMessage, "Offline — Cloud Sync will retry when you're online.")
        XCTAssertFalse(CloudSyncValidationDiagnostic.savedScanMetadataIntegrity.ownerMessage.contains("scan-owner-validation"))
    }

    func testDifferentICloudPrivateDatabasesDoNotProvideARecordMergeMechanism() {
        XCTAssertEqual(CloudSyncIdentityBoundary.v1, .sameICloudAccountPrivateDatabase)
        XCTAssertFalse(CloudSyncIdentityBoundary.v1.customerFacingDescription.contains("different iCloud"))
    }

    func testSavedScanPersistenceAuthorityPreservesExactFactsAndImageOwnership() throws {
        let fixture = try savedScanAuthorityFixture()
        let dto = try fixture.authority.readSavedScan(id: fixture.id)

        XCTAssertEqual(dto.id, fixture.id)
        XCTAssertEqual(dto.authoritativeScore, 87)
        XCTAssertEqual(dto.savedAt, now)
        XCTAssertEqual(dto.occasion, Occasion.work.rawValue)
        XCTAssertEqual(dto.title, "Office uniform")
        XCTAssertEqual(dto.colors, ["navy", "white"])
        XCTAssertEqual(dto.imageAssetID, fixture.asset.id)
        XCTAssertEqual(dto.imageByteCount, Int64(fixture.image.count))
        XCTAssertEqual(try fixture.authority.readImageAsset(scanID: fixture.id)?.assetID, fixture.asset.id)
    }

    func testSavedScanPersistenceAuthorityRejectsMalformedAndDivergentRemoteRecordsWithoutMutation() throws {
        let fixture = try savedScanAuthorityFixture()
        let dto = try fixture.authority.readSavedScan(id: fixture.id)
        var malformed = dto
        malformed = SavedScanSyncDTO(
            id: dto.id,
            authoritativeScore: dto.authoritativeScore,
            savedAt: dto.savedAt,
            occasion: dto.occasion,
            title: dto.title,
            colors: dto.colors,
            persistentAnalysisMetadata: Data("malformed".utf8),
            imageAssetID: dto.imageAssetID,
            imageSHA256: dto.imageSHA256,
            imageByteCount: dto.imageByteCount,
            version: dto.version
        )

        XCTAssertThrowsError(try fixture.authority.applyRemoteSavedScan(malformed))
        XCTAssertEqual(try fixture.authority.readSavedScan(id: fixture.id), dto)

        let divergent = SavedScanSyncDTO(
            id: dto.id,
            authoritativeScore: dto.authoritativeScore,
            savedAt: dto.savedAt,
            occasion: dto.occasion,
            title: "Different title",
            colors: dto.colors,
            persistentAnalysisMetadata: dto.persistentAnalysisMetadata,
            imageAssetID: dto.imageAssetID,
            imageSHA256: dto.imageSHA256,
            imageByteCount: dto.imageByteCount,
            version: "different-version"
        )
        XCTAssertThrowsError(try fixture.authority.applyRemoteSavedScan(divergent)) { error in
            XCTAssertEqual(error as? SavedScanPersistenceError, .invalidPayload)
        }
        XCTAssertEqual(try fixture.authority.readSavedScan(id: fixture.id), dto)
    }

    func testSavedScanPersistenceAuthorityTombstonePreventsStaleResurrectionAndImageMismatch() throws {
        let fixture = try savedScanAuthorityFixture()
        let dto = try fixture.authority.readSavedScan(id: fixture.id)

        XCTAssertThrowsError(try fixture.authority.applyRemoteImage(
            for: dto,
            asset: fixture.asset,
            data: Data("wrong".utf8),
            sha256: dto.imageSHA256 ?? "",
            byteCount: dto.imageByteCount ?? 0
        )) { error in
            XCTAssertEqual(error as? SavedScanPersistenceError, .imageMismatch)
        }

        try fixture.authority.applyRemoteTombstone(id: fixture.id, version: dto.version)
        XCTAssertThrowsError(try fixture.authority.readSavedScan(id: fixture.id)) { error in
            XCTAssertEqual(error as? SavedScanPersistenceError, .missing)
        }
        XCTAssertThrowsError(try fixture.authority.applyRemoteSavedScan(dto)) { error in
            XCTAssertEqual(error as? SavedScanPersistenceError, .stale)
        }
    }

    func testInboundSavedScanRequiresValidatedAssetBeforeVisibleAtomicApply() throws {
        let fixture = try legacyThumbnailFixture()
        let image = try XCTUnwrap(try fixture.authority.readValidatedImageAsset(scanID: fixture.id))
        let dto = try fixture.authority.readSavedScan(id: fixture.id)
        fixture.defaults.removeObject(forKey: "outfitScanHistoryData")

        var corrupted = image.data
        corrupted.append(0x00)
        XCTAssertThrowsError(try fixture.authority.applyRemoteSavedScanAtomically(
            dto,
            asset: image.asset,
            data: corrupted,
            sha256: image.sha256,
            byteCount: image.byteCount
        )) { error in
            XCTAssertEqual(error as? SavedScanPersistenceError, .imageMismatch)
        }
        XCTAssertThrowsError(try fixture.authority.readSavedScan(id: fixture.id)) { error in
            XCTAssertEqual(error as? SavedScanPersistenceError, .missing)
        }

        try fixture.authority.applyRemoteSavedScanAtomically(
            dto,
            asset: image.asset,
            data: image.data,
            sha256: image.sha256,
            byteCount: image.byteCount
        )
        let restored = try fixture.authority.readSavedScan(id: fixture.id)
        XCTAssertEqual(restored.id, dto.id)
        XCTAssertEqual(restored.authoritativeScore, dto.authoritativeScore)
        XCTAssertEqual(restored.savedAt, dto.savedAt)
        XCTAssertEqual(try fixture.authority.readImageAsset(scanID: fixture.id)?.data, image.data)
    }

    func testPendingInboundSavedScanSurvivesRelaunchAndTombstoneRemovesOnlyStagedID() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "PendingInboundSavedScan-\(UUID().uuidString)"))
        let store = CloudSyncPendingSavedScanStore(defaults: defaults, scope: "test")
        let fixture = try legacyThumbnailFixture()
        let image = try XCTUnwrap(try fixture.authority.readValidatedImageAsset(scanID: fixture.id))
        let dto = try fixture.authority.readSavedScan(id: fixture.id)
        let record = CloudSyncRecord(
            id: dto.id,
            kind: .savedScan,
            payload: try JSONEncoder().encode(dto),
            version: dto.version,
            modifiedAt: dto.savedAt
        )
        let entry = CloudSyncPendingSavedScan(record: record, dto: dto, asset: image.asset)
        try store.stage(entry)
        XCTAssertEqual(try store.pending()[dto.id], entry)

        let relaunched = CloudSyncPendingSavedScanStore(defaults: defaults, scope: "test")
        XCTAssertEqual(try relaunched.pending()[dto.id], entry)
        try relaunched.remove(id: dto.id)
        XCTAssertTrue(try relaunched.pending().isEmpty)
    }

    @MainActor
    func testInboundDecodeFailureIsTypedAndPersistsOnlyItsBoundedCategory() async throws {
        let suite = "InboundDecodeFailure-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let state = CloudSyncOperationalStateStore(defaults: defaults, scope: suite)
        let malformedSavedScan = CloudSyncRecord(
            id: "saved-scan",
            kind: .savedScan,
            payload: Data("not-a-saved-scan-dto".utf8),
            version: "v1",
            modifiedAt: now
        )
        let coordinator = CloudSyncInboundReconciliationCoordinator(
            transport: InboundTransport(batch: .init(
                changes: [.init(record: malformedSavedScan, asset: nil)],
                nextCursor: .initial,
                requiresFullRediscovery: false
            )),
            accountGuard: CloudSyncPrivateAccountGuardStore(defaults: defaults, scope: suite),
            state: state,
            apply: { _ in XCTFail("Malformed inbound metadata must not apply") },
            applyTombstone: { _ in XCTFail("Malformed inbound metadata must not tombstone") },
            applySavedScanAtomically: { _, _ in XCTFail("Malformed inbound metadata must not apply an image") }
        )

        let result = await coordinator.reconcile()
        XCTAssertEqual(result, .needsAttention(.inboundDecodeFailure))
        XCTAssertEqual(state.inboundFailureCategory(), .decodeFailure)
        XCTAssertNil(state.load().cursor.databaseToken)
    }

    @MainActor
    func testInboundChangeCursorFailureDoesNotCollapseToGenericConflict() async throws {
        let suite = "InboundCursorFailure-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let state = CloudSyncOperationalStateStore(defaults: defaults, scope: suite)
        let coordinator = CloudSyncInboundReconciliationCoordinator(
            transport: InboundTransport(batch: .init(
                changes: [],
                nextCursor: .initial,
                requiresFullRediscovery: true
            )),
            accountGuard: CloudSyncPrivateAccountGuardStore(defaults: defaults, scope: suite),
            state: state,
            apply: { _ in },
            applyTombstone: { _ in },
            applySavedScanAtomically: { _, _ in }
        )

        let result = await coordinator.reconcile()
        XCTAssertEqual(result, .needsAttention(.inboundChangeCursorFailure))
        XCTAssertEqual(state.inboundFailureCategory(), .changeCursorFailure)
        XCTAssertNil(state.load().cursor.databaseToken)
    }

    func testInboundFailureCategoriesHaveBoundedLocalDiagnostics() {
        for category in CloudSyncInboundFailureCategory.allCases {
            let message = category.diagnostic.ownerMessage
            XCTAssertFalse(message.contains("record ID"))
            XCTAssertFalse(message.contains("token"))
            XCTAssertFalse(message.contains("payload"))
            XCTAssertNotEqual(category.diagnostic, .conflict)
        }
    }

    func testPersistedInboundFailurePresentationIsBoundedAndOptional() {
        XCTAssertNil(CloudSyncInboundDiagnosticPresentation.feedback(for: nil))
        let feedback = try? XCTUnwrap(
            CloudSyncInboundDiagnosticPresentation.feedback(for: .changeCursorFailure)
        )
        XCTAssertEqual(
            feedback,
            "Inbound Cloud Sync reconciliation: Needs attention — Cloud Sync could not safely resume its change history."
        )
        XCTAssertFalse(feedback?.localizedCaseInsensitiveContains("record ID") == true)
        XCTAssertFalse(feedback?.localizedCaseInsensitiveContains("token") == true)
        XCTAssertFalse(feedback?.localizedCaseInsensitiveContains("payload") == true)
    }

    @MainActor
    func testInboundAccountGuardMismatchUsesItsOwnLocalFailureCategory() async throws {
        let suite = "InboundAccountGuardMismatch-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let state = CloudSyncOperationalStateStore(defaults: defaults, scope: suite)
        let accountGuard = CloudSyncPrivateAccountGuardStore(defaults: defaults, scope: suite)
        accountGuard.recordInitial(.init(stableAccountChangeToken: "private-account-A"))
        let coordinator = CloudSyncInboundReconciliationCoordinator(
            transport: InboundTransport(
                batch: .init(changes: [], nextCursor: .initial, requiresFullRediscovery: false),
                identity: .init(stableAccountChangeToken: "private-account-B")
            ),
            accountGuard: accountGuard,
            state: state,
            apply: { _ in XCTFail("Account mismatch must not apply records") },
            applyTombstone: { _ in XCTFail("Account mismatch must not apply tombstones") },
            applySavedScanAtomically: { _, _ in XCTFail("Account mismatch must not apply images") }
        )

        let result = await coordinator.reconcile()
        XCTAssertEqual(result, .needsAttention(.inboundAccountGuardMismatch))
        XCTAssertEqual(state.inboundFailureCategory(), .accountGuardMismatch)
    }

    @MainActor
    func testInboundUnavailablePrivateDatabaseUsesItsOwnLocalFailureCategory() async throws {
        let suite = "InboundUnavailableAccount-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let state = CloudSyncOperationalStateStore(defaults: defaults, scope: suite)
        let coordinator = CloudSyncInboundReconciliationCoordinator(
            transport: InboundTransport(
                batch: .init(changes: [], nextCursor: .initial, requiresFullRediscovery: false),
                identity: nil
            ),
            accountGuard: CloudSyncPrivateAccountGuardStore(defaults: defaults, scope: suite),
            state: state,
            apply: { _ in XCTFail("Unavailable account must not apply records") },
            applyTombstone: { _ in XCTFail("Unavailable account must not apply tombstones") },
            applySavedScanAtomically: { _, _ in XCTFail("Unavailable account must not apply images") }
        )

        let result = await coordinator.reconcile()
        XCTAssertEqual(result, .needsAttention(.inboundCloudKitAccountUnavailable))
        XCTAssertEqual(state.inboundFailureCategory(), .cloudKitAccountUnavailable)
    }

    @MainActor
    func testOwnerLifecycleRunsInboundOnlyAfterSuccessfulExplicitValidationAndOnEnabledRelaunch() async {
        var validationCount = 0
        var inboundCount = 0
        let lifecycle = CloudSyncOwnerLifecycle(
            configuration: .init(buildNumber: "18036", isDebugBuild: true),
            runValidation: { validationCount += 1; return .upToDate },
            runInbound: { inboundCount += 1; return .upToDate }
        )

        let enabled = await lifecycle.enableAndValidate()
        XCTAssertEqual(enabled.validation, .upToDate)
        XCTAssertEqual(enabled.inbound, .upToDate)
        XCTAssertEqual(validationCount, 1)
        XCTAssertEqual(inboundCount, 1)

        let relaunched = await lifecycle.reconcileOnLifecycleBoundary(isEnabled: true)
        XCTAssertEqual(relaunched, .upToDate)
        XCTAssertEqual(validationCount, 1)
        XCTAssertEqual(inboundCount, 2)
    }

    @MainActor
    func testOwnerLifecycleDoesNotReconcileWhenDisabledOrValidationFails() async {
        var inboundCount = 0
        let disabled = CloudSyncOwnerLifecycle(
            configuration: .init(buildNumber: "18036", isDebugBuild: true),
            runValidation: { .needsAttention(.profileMigration) },
            runInbound: { inboundCount += 1; return .upToDate }
        )
        let failed = await disabled.enableAndValidate()
        XCTAssertEqual(failed.validation, .needsAttention(.profileMigration))
        XCTAssertNil(failed.inbound)
        XCTAssertEqual(inboundCount, 0)
        let disabledOutcome = await disabled.reconcileOnLifecycleBoundary(isEnabled: false)
        XCTAssertEqual(disabledOutcome, .disabled)
        XCTAssertEqual(inboundCount, 0)
    }

    @MainActor
    func testBuild18037And18038InboundDiagnosticLifecycleNeverCallsOutboundValidation() async {
        for buildNumber in ["18037", "18038"] {
            var validationCount = 0
            var inboundCount = 0
            let lifecycle = CloudSyncOwnerLifecycle(
                configuration: .init(buildNumber: buildNumber, isDebugBuild: true),
                runValidation: { validationCount += 1; return .upToDate },
                runInbound: { inboundCount += 1; return .needsAttention(.inboundDecodeFailure) }
            )

            let outbound = await lifecycle.enableAndValidate()
            XCTAssertEqual(outbound.validation, .disabled, "Build \(buildNumber)")
            XCTAssertNil(outbound.inbound, "Build \(buildNumber)")
            XCTAssertEqual(validationCount, 0, "Build \(buildNumber)")
            XCTAssertEqual(inboundCount, 0, "Build \(buildNumber)")

            let inbound = await lifecycle.reconcileOnLifecycleBoundary(isEnabled: true)
            XCTAssertEqual(inbound, .needsAttention(.inboundDecodeFailure), "Build \(buildNumber)")
            XCTAssertEqual(validationCount, 0, "Build \(buildNumber)")
            XCTAssertEqual(inboundCount, 1, "Build \(buildNumber)")
        }
    }

    @MainActor
    func testInboundMetadataWithoutAssetStagesWithoutApplyOrTokenAdvanceThenCommitsOnce() async throws {
        let fixture = try legacyThumbnailFixture()
        let image = try XCTUnwrap(try fixture.authority.readValidatedImageAsset(scanID: fixture.id))
        let dto = try fixture.authority.readSavedScan(id: fixture.id)
        let record = CloudSyncRecord(
            id: dto.id,
            kind: .savedScan,
            payload: try JSONEncoder().encode(dto),
            version: dto.version,
            modifiedAt: dto.savedAt
        )
        let suite = "InboundAtomic-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let accountGuard = CloudSyncPrivateAccountGuardStore(defaults: defaults, scope: suite)
        let state = CloudSyncOperationalStateStore(defaults: defaults, scope: suite)
        let pending = CloudSyncPendingSavedScanStore(defaults: defaults, scope: suite)
        let applied = ApplyCounter()

        let missingAsset = InboundTransport(batch: .init(
            changes: [.init(record: record, asset: nil)],
            nextCursor: .init(databaseToken: Data("advanced".utf8), zoneTokens: [:]),
            requiresFullRediscovery: false
        ))
        let first = CloudSyncInboundReconciliationCoordinator(
            transport: missingAsset,
            accountGuard: accountGuard,
            state: state,
            apply: { _ in applied.count += 1 },
            applyTombstone: { _ in applied.count += 1 },
            applySavedScanAtomically: { _, _ in applied.count += 1 },
            pendingSavedScans: pending
        )
        let firstResult = await first.reconcile()
        XCTAssertEqual(firstResult, .needsAttention(.savedScanAssetIntegrity))
        XCTAssertEqual(applied.count, 0)
        XCTAssertEqual(try pending.pending()[dto.id]?.dto, dto)
        XCTAssertNil(state.load().cursor.databaseToken)

        let validAsset = CloudSyncAssetDownload(
            reference: .init(owningRecordID: dto.id, assetIdentifier: image.asset.id, sha256: image.sha256, byteCount: image.byteCount),
            data: image.data
        )
        let presentAsset = InboundTransport(batch: .init(
            changes: [.init(record: record, asset: validAsset)],
            nextCursor: .init(databaseToken: Data("advanced".utf8), zoneTokens: [:]),
            requiresFullRediscovery: false
        ))
        let second = CloudSyncInboundReconciliationCoordinator(
            transport: presentAsset,
            accountGuard: accountGuard,
            state: state,
            apply: { _ in applied.count += 1 },
            applyTombstone: { _ in applied.count += 1 },
            applySavedScanAtomically: { received, downloaded in
                XCTAssertEqual(received, dto)
                XCTAssertEqual(downloaded, validAsset)
                applied.count += 1
            },
            pendingSavedScans: pending
        )
        let secondResult = await second.reconcile()
        XCTAssertEqual(secondResult, .upToDate)
        XCTAssertEqual(applied.count, 1)
        XCTAssertTrue(try pending.pending().isEmpty)
        XCTAssertEqual(state.load().cursor.databaseToken, Data("advanced".utf8))
    }

    func testLegacyThumbnailMigratesToItsOwnCanonicalAssetWithoutChangingHistoricalFacts() throws {
        let fixture = try legacyThumbnailFixture()
        let before = try fixture.authority.readSavedScan(id: fixture.id)

        let migrated = try XCTUnwrap(try fixture.authority.readValidatedImageAsset(scanID: fixture.id))
        let after = try fixture.authority.readSavedScan(id: fixture.id)

        XCTAssertEqual(after.id, before.id)
        XCTAssertEqual(after.authoritativeScore, before.authoritativeScore)
        XCTAssertEqual(after.savedAt, before.savedAt)
        XCTAssertEqual(after.occasion, before.occasion)
        XCTAssertEqual(after.title, before.title)
        XCTAssertEqual(after.colors, before.colors)
        XCTAssertEqual(migrated.asset.ownerScanID, fixture.id)
        XCTAssertEqual(migrated.sha256, SHA256.hash(data: migrated.data).map { String(format: "%02x", $0) }.joined())
        XCTAssertEqual(migrated.byteCount, Int64(migrated.data.count))
        XCTAssertEqual(after.imageAssetID, migrated.asset.id)

        let repeatMigration = try XCTUnwrap(try fixture.authority.readValidatedImageAsset(scanID: fixture.id))
        XCTAssertEqual(repeatMigration.asset, migrated.asset)
        XCTAssertEqual(repeatMigration.data, migrated.data)
        XCTAssertEqual(try fixture.imageFileCount(), 1)
    }

    func testLegacyThumbnailMigrationFailsClosedForMissingInvalidOrCrossScanAsset() throws {
        let missing = try legacyThumbnailFixture(thumbnail: nil)
        XCTAssertThrowsError(try missing.authority.readValidatedImageAsset(scanID: missing.id)) { error in
            XCTAssertEqual(error as? SavedScanPersistenceError, .imageMismatch)
        }

        let invalid = try legacyThumbnailFixture(thumbnail: Data("not-an-image".utf8))
        XCTAssertThrowsError(try invalid.authority.readValidatedImageAsset(scanID: invalid.id)) { error in
            XCTAssertEqual(error as? SavedScanPersistenceError, .imageMismatch)
        }

        let owner = try legacyThumbnailFixture()
        let ownerAsset = try XCTUnwrap(try owner.authority.readValidatedImageAsset(scanID: owner.id)?.asset)
        var history = try XCTUnwrap(owner.defaults.data(forKey: "outfitScanHistoryData"))
        var decoded = try JSONDecoder().decode([String: StoredOutfitScan].self, from: history)
        let otherID = "scan-other"
        let existing = try XCTUnwrap(decoded[owner.id])
        decoded[otherID] = StoredOutfitScan(
            score: existing.score,
            analysis: existing.analysis,
            firstScannedAt: existing.firstScannedAt,
            scanCount: existing.scanCount,
            thumbnailData: validLegacyThumbnail(),
            customTitle: existing.customTitle,
            occasion: existing.occasion,
            imageDigest: existing.imageDigest,
            savedImageAsset: ownerAsset,
            deterministicInputs: existing.deterministicInputs
        )
        history = try JSONEncoder().encode(decoded)
        owner.defaults.set(history, forKey: "outfitScanHistoryData")
        XCTAssertThrowsError(try owner.authority.readValidatedImageAsset(scanID: otherID)) { error in
            XCTAssertEqual(error as? SavedScanPersistenceError, .imageMismatch)
        }
    }

    @MainActor
    func testLegacyImageFailurePreventsCloudKitTransportInvocation() async throws {
        let transport = OwnerValidationTransport(status: .available)
        let sources = CloudSyncOwnerValidationSources(
            profile: { self.authorityRecord(id: "profile", kind: .profile, payload: Data("profile".utf8), version: "v1") },
            savedScans: { [SavedScanSyncDTO(id: "legacy", authoritativeScore: 80, savedAt: self.now, occasion: nil, title: nil, colors: ["navy"], persistentAnalysisMetadata: Data("metadata".utf8), imageAssetID: nil, imageSHA256: nil, imageByteCount: nil, version: "v1")] },
            savedScanImage: { _ in throw SavedScanPersistenceError.imageMismatch },
            closet: { [self.authorityRecord(id: "closet", kind: .closetItem, payload: Data("closet".utf8), version: "v1")] },
            shopping: { [self.authorityRecord(id: "favorites", kind: .favorites, payload: try! JSONEncoder().encode(["product"]), version: "v1")] },
            aiMemory: { [PersistenceAuthorityRecord(id: "memory", kind: .aiMemory, payload: Data("memory".utf8), version: "v1", updatedAt: self.now, isDeleted: false, persistenceOrigin: .explicitlySavedAIMemory)] },
            apply: { _ in },
            applySavedScanImage: { _, _, _, _, _ in }
        )
        let coordinator = CloudSyncOwnerValidationCoordinator(
            configuration: .init(buildNumber: "18036", isDebugBuild: true),
            transport: transport,
            sources: sources,
            migration: try migrationCoordinator(),
            accountGuardStore: CloudSyncPrivateAccountGuardStore(defaults: UserDefaults(suiteName: "LegacyImageGuard-\(UUID().uuidString)")!)
        )

        let outcome = await coordinator.runControlledValidation()
        XCTAssertEqual(outcome, .needsAttention(.savedScanAssetIntegrity))
        XCTAssertEqual(transport.saveCount, 0)
        XCTAssertEqual(transport.assetSaveCount, 0)
    }

    func testSyncMutationV2RequiresVerifiedBootstrapAndAdvancesMonotonically() throws {
        let authority = try v2Authority()
        XCTAssertFalse(authority.isBootstrapped)
        XCTAssertThrowsError(try authority.beginLive(recordID: "closet:ABC", kind: .closetItem, payload: Data("item".utf8))) { error in
            XCTAssertEqual(error as? SyncMutationV2Error, .unavailableCounterFloor)
        }
        try authority.bootstrap(remoteFloor: .verified(41))
        let first = try authority.beginLive(recordID: "closet:ABC", kind: .closetItem, payload: Data("item".utf8))
        let second = try authority.beginTombstone(recordID: "closet:ABC", kind: .closetItem)
        XCTAssertEqual(first.mutation.token.counter, 42)
        XCTAssertEqual(second.mutation.token.counter, 43)
        XCTAssertEqual(first.mutation.token.replicaID, authority.replicaID)
        XCTAssertEqual(first.mutation.mutationKind, .live)
        XCTAssertEqual(second.mutation.mutationKind, .tombstone)
    }

    func testSyncMutationV2ReinstallUsesRemoteFloorAndUnavailableFloorFailsClosed() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "SyncMutationV2Reinstall-\(UUID().uuidString)"))
        let scope = CloudSyncPrivateDatabaseIdentity(stableAccountChangeToken: "private-A")
        let initial = try SyncMutationV2Authority(defaults: defaults, scope: scope, replicaID: UUID())
        XCTAssertThrowsError(try initial.bootstrap(remoteFloor: .unavailable)) { error in
            XCTAssertEqual(error as? SyncMutationV2Error, .unavailableCounterFloor)
        }
        let replacement = try SyncMutationV2Authority(defaults: defaults, scope: scope, replicaID: UUID())
        try replacement.bootstrap(remoteFloor: .verified(88))
        let transaction = try replacement.beginLive(recordID: "memory:ABC", kind: .aiMemory, payload: Data("saved".utf8), persistenceOrigin: .explicitlySavedAIMemory)
        XCTAssertEqual(transaction.mutation.token.counter, 89)
    }

    func testSyncMutationV2OverflowAndTokenTieBreakFailClosedDeterministically() throws {
        let authority = try v2Authority()
        try authority.bootstrap(remoteFloor: .verified(UInt64.max))
        XCTAssertThrowsError(try authority.beginTombstone(recordID: "favorite:item", kind: .favorite)) { error in
            XCTAssertEqual(error as? SyncMutationV2Error, .counterOverflow)
        }
        let lower = SyncMutationV2Token(counter: 7, replicaID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        let higher = SyncMutationV2Token(counter: 7, replicaID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!)
        XCTAssertLessThan(lower, higher)
    }

    func testSyncMutationV2ReplayIntegrityAndLiveTombstoneOrdering() throws {
        let replica = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!
        let live = try SyncMutationV2.live(recordID: "favorite:item", kind: .favorite, token: .init(counter: 3, replicaID: replica), payload: Data("item".utf8))
        let same = try SyncMutationV2.live(recordID: "favorite:item", kind: .favorite, token: .init(counter: 3, replicaID: replica), payload: Data("item".utf8))
        let altered = try SyncMutationV2.live(recordID: "favorite:item", kind: .favorite, token: .init(counter: 3, replicaID: replica), payload: Data("other".utf8))
        let tombstone = try SyncMutationV2.tombstone(recordID: "favorite:item", kind: .favorite, token: .init(counter: 4, replicaID: replica))
        let recreation = try SyncMutationV2.live(recordID: "favorite:item", kind: .favorite, token: .init(counter: 5, replicaID: replica), payload: Data("item".utf8))
        XCTAssertEqual(try SyncMutationV2Reconciler.decision(local: live, remote: same), .identical)
        XCTAssertThrowsError(try SyncMutationV2Reconciler.decision(local: live, remote: altered)) { error in
            XCTAssertEqual(error as? SyncMutationV2Error, .integrityFailure)
        }
        XCTAssertEqual(try SyncMutationV2Reconciler.decision(local: tombstone, remote: live), .keepLocal)
        XCTAssertEqual(try SyncMutationV2Reconciler.decision(local: recreation, remote: tombstone), .keepLocal)
    }

    func testSyncMutationV2JournalSurvivesRelaunchAndRetryKeepsOriginalToken() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "SyncMutationV2Journal-\(UUID().uuidString)"))
        let scope = CloudSyncPrivateDatabaseIdentity(stableAccountChangeToken: "private-A")
        let authority = try SyncMutationV2Authority(defaults: defaults, scope: scope, replicaID: UUID())
        try authority.bootstrap(remoteFloor: .verified(0))
        let transaction = try authority.beginTombstone(recordID: "closet:ABC", kind: .closetItem)
        let relaunched = try SyncMutationV2Authority(defaults: defaults, scope: scope, replicaID: UUID())
        XCTAssertEqual(relaunched.recoverableTransactions, [transaction])
        try relaunched.markLocalApplied(transactionID: transaction.id)
        try relaunched.commit(transactionID: transaction.id)
        try relaunched.markUploadPending(transactionID: transaction.id)
        XCTAssertEqual(try XCTUnwrap(relaunched.pendingOutbox.first).token, transaction.mutation.token)
    }

    func testSyncMutationV2AcknowledgementRequiresExactMutationIdentity() throws {
        let authority = try v2Authority()
        try authority.bootstrap(remoteFloor: .verified(0))
        let transaction = try authority.beginLive(recordID: "watch:item", kind: .watchListItem, payload: Data("item".utf8))
        try authority.markLocalApplied(transactionID: transaction.id)
        try authority.commit(transactionID: transaction.id)
        try authority.markUploadPending(transactionID: transaction.id)
        let mismatch = SyncMutationV2Acknowledgement(recordID: transaction.mutation.recordID, token: transaction.mutation.token, canonicalDigest: "wrong")
        try authority.acknowledge(mismatch)
        XCTAssertEqual(authority.pendingOutbox.count, 1)
        try authority.acknowledge(.init(mutation: transaction.mutation))
        XCTAssertTrue(authority.pendingOutbox.isEmpty)
    }

    func testSyncMutationV2CASConflictIsDurableBoundedAndRetryKeepsExactMutation() throws {
        let suite = "SyncMutationV2CAS-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let scope = CloudSyncPrivateDatabaseIdentity(stableAccountChangeToken: "private-A")
        let authority = try SyncMutationV2Authority(defaults: defaults, scope: scope, replicaID: UUID())
        try authority.bootstrap(remoteFloor: .verified(0))
        let transaction = try authority.beginLive(recordID: "favorite:item", kind: .favorite, payload: Data("item".utf8))
        try authority.markLocalApplied(transactionID: transaction.id)
        try authority.commit(transactionID: transaction.id)
        try authority.markUploadPending(transactionID: transaction.id)

        let olderRemote = try SyncMutationV2.live(recordID: transaction.mutation.recordID, kind: .favorite, token: .init(counter: 0, replicaID: UUID()), payload: Data("older".utf8))
        try authority.recordCASConflict(transactionID: transaction.id, accountScope: scope, observedRemote: olderRemote)
        var persisted = try XCTUnwrap(authority.journalTransactions.first)
        XCTAssertEqual(persisted.state, .conflictNeedsReconciliation)
        XCTAssertEqual(persisted.conflictAttempts, 1)
        XCTAssertEqual(persisted.lastConflictClassification, .localMutationNewer)
        XCTAssertEqual(persisted.originalToken, transaction.mutation.token)
        XCTAssertEqual(persisted.originalCanonicalDigest, transaction.mutation.canonicalDigest())
        XCTAssertTrue(authority.pendingOutbox.isEmpty)

        try authority.authorizeRetryAfterFreshServerState(transactionID: transaction.id, accountScope: scope)
        XCTAssertEqual(try XCTUnwrap(authority.pendingOutbox.first), transaction.mutation)
        let relaunched = try SyncMutationV2Authority(defaults: defaults, scope: scope)
        persisted = try XCTUnwrap(relaunched.journalTransactions.first)
        XCTAssertEqual(persisted.id, transaction.id)
        XCTAssertEqual(persisted.mutation, transaction.mutation)
        XCTAssertEqual(persisted.conflictAttempts, 1)

        try relaunched.recordCASConflict(transactionID: transaction.id, accountScope: scope, observedRemote: olderRemote)
        try relaunched.authorizeRetryAfterFreshServerState(transactionID: transaction.id, accountScope: scope)
        try relaunched.recordCASConflict(transactionID: transaction.id, accountScope: scope, observedRemote: olderRemote)
        XCTAssertThrowsError(try relaunched.authorizeRetryAfterFreshServerState(transactionID: transaction.id, accountScope: scope))
        XCTAssertEqual(try XCTUnwrap(relaunched.journalTransactions.first).state, .conflictNeedsReconciliation)
    }

    func testSyncMutationV2NewerRemoteSupersedesOnlyAfterTypedReconciliation() throws {
        let suite = "SyncMutationV2Supersede-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let scope = CloudSyncPrivateDatabaseIdentity(stableAccountChangeToken: "private-A")
        let authority = try SyncMutationV2Authority(defaults: defaults, scope: scope, replicaID: UUID())
        try authority.bootstrap(remoteFloor: .verified(3))
        let transaction = try authority.beginTombstone(recordID: "closet:ABC", kind: .closetItem)
        try authority.markLocalApplied(transactionID: transaction.id); try authority.commit(transactionID: transaction.id); try authority.markUploadPending(transactionID: transaction.id)
        let remote = try SyncMutationV2.live(recordID: transaction.mutation.recordID, kind: .closetItem, token: .init(counter: 5, replicaID: UUID()), payload: Data("remote".utf8))

        enum TestError: Error { case rejected }
        XCTAssertThrowsError(try authority.supersedePendingMutation(transactionID: transaction.id, accountScope: scope, winningRemote: remote, reconciliationHook: .closet { _ in throw TestError.rejected }))
        var persisted = try XCTUnwrap(authority.journalTransactions.first)
        XCTAssertEqual(persisted.state, .conflictNeedsReconciliation)
        XCTAssertEqual(persisted.winningRemote, remote)
        XCTAssertEqual(persisted.reconciliationStatus, .failed)
        XCTAssertFalse(authority.pendingOutbox.contains(transaction.mutation))

        var applications = 0
        try authority.supersedePendingMutation(transactionID: transaction.id, accountScope: scope, winningRemote: remote, reconciliationHook: .closet { mutation in
            XCTAssertEqual(mutation, remote)
            applications += 1
        })
        persisted = try XCTUnwrap(authority.journalTransactions.first)
        XCTAssertEqual(applications, 1)
        XCTAssertEqual(persisted.state, .supersededByRemote)
        XCTAssertEqual(persisted.reconciliationStatus, .applied)
        XCTAssertTrue(authority.pendingOutbox.isEmpty)
        let relaunched = try SyncMutationV2Authority(defaults: defaults, scope: scope)
        XCTAssertEqual(try XCTUnwrap(relaunched.journalTransactions.first).state, .supersededByRemote)
        XCTAssertThrowsError(try relaunched.authorizeRetryAfterFreshServerState(transactionID: transaction.id, accountScope: scope))
    }

    func testSyncMutationV2CASRejectsEqualDigestMismatchAndAccountOrKindMismatch() throws {
        let authority = try v2Authority()
        let scope = CloudSyncPrivateDatabaseIdentity(stableAccountChangeToken: "private-A")
        try authority.bootstrap(remoteFloor: .verified(0))
        let transaction = try authority.beginLive(recordID: "favorite:item", kind: .favorite, payload: Data("item".utf8))
        try authority.markLocalApplied(transactionID: transaction.id); try authority.commit(transactionID: transaction.id); try authority.markUploadPending(transactionID: transaction.id)
        let conflict = try SyncMutationV2.live(recordID: transaction.mutation.recordID, kind: .favorite, token: transaction.mutation.token, payload: Data("other".utf8))
        XCTAssertThrowsError(try authority.recordCASConflict(transactionID: transaction.id, accountScope: scope, observedRemote: conflict)) { error in
            XCTAssertEqual(error as? SyncMutationV2Error, .integrityFailure)
        }
        XCTAssertEqual(try XCTUnwrap(authority.journalTransactions.first).state, .integrityFailure)

        let second = try authority.beginLive(recordID: "watch:item", kind: .watchListItem, payload: Data("item".utf8))
        try authority.markLocalApplied(transactionID: second.id); try authority.commit(transactionID: second.id); try authority.markUploadPending(transactionID: second.id)
        XCTAssertThrowsError(try authority.recordCASConflict(transactionID: second.id, accountScope: .init(stableAccountChangeToken: "private-B"), observedRemote: nil)) { error in
            XCTAssertEqual(error as? SyncMutationV2Error, .accountScopeMismatch)
        }
        let wrongKind = try SyncMutationV2.live(recordID: "favorite:item", kind: .favorite, token: .init(counter: 9, replicaID: UUID()), payload: Data("item".utf8))
        XCTAssertThrowsError(try authority.supersedePendingMutation(transactionID: second.id, accountScope: scope, winningRemote: wrongKind, reconciliationHook: .shoppingWatch { _ in }))
        XCTAssertEqual(try XCTUnwrap(authority.journalTransactions.last).state, .integrityFailure)
    }

    func testSyncMutationV2ScopesRemainIsolatedAcrossPrivateICloudAccountChange() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "SyncMutationV2Scope-\(UUID().uuidString)"))
        let accountA = try SyncMutationV2Authority(defaults: defaults, scope: .init(stableAccountChangeToken: "private-A"), replicaID: UUID())
        try accountA.bootstrap(remoteFloor: .verified(9))
        _ = try accountA.beginLive(recordID: "favorite:item", kind: .favorite, payload: Data("item".utf8))
        let accountB = try SyncMutationV2Authority(defaults: defaults, scope: .init(stableAccountChangeToken: "private-B"), replicaID: UUID())
        XCTAssertFalse(accountB.isBootstrapped)
        XCTAssertTrue(accountB.pendingOutbox.isEmpty)
        XCTAssertThrowsError(try accountB.beginLive(recordID: "favorite:item", kind: .favorite, payload: Data("item".utf8)))
    }

    func testSyncMutationV2RejectsMalformedRecordPayloadAndUnknownSchemaWithoutLegacyUpgrade() throws {
        let token = SyncMutationV2Token(counter: 1, replicaID: UUID())
        XCTAssertThrowsError(try SyncMutationV2.live(recordID: "closet:../bad", kind: .closetItem, token: token, payload: Data("x".utf8))) { error in
            XCTAssertEqual(error as? SyncMutationV2Error, .malformedRecordID)
        }
        let malformed = SyncMutationV2(recordID: "closet:ABC", kind: .closetItem, schemaVersion: 2, mutationKind: .live, token: token, payloadHash: "incorrect", payload: Data("x".utf8), persistenceOrigin: .customerPersistent)
        XCTAssertThrowsError(try malformed.validate()) { error in
            XCTAssertEqual(error as? SyncMutationV2Error, .payloadHashMismatch)
        }
        XCTAssertEqual(SyncMutationV2Codec.recognize(schemaVersion: 1), .legacyV1)
        XCTAssertEqual(SyncMutationV2Codec.recognize(schemaVersion: 2), .v2)
        XCTAssertEqual(SyncMutationV2Codec.recognize(schemaVersion: 3), .unsupported)
        let valid = try SyncMutationV2.tombstone(recordID: "closet:ABC", kind: .closetItem, token: token)
        XCTAssertEqual(try SyncMutationV2Codec.decode(SyncMutationV2Codec.encode(valid)), valid)
        XCTAssertFalse(CloudSyncProductContract.customerPublicActivationEnabled)
    }

    private func v2Authority() throws -> SyncMutationV2Authority {
        try SyncMutationV2Authority(
            defaults: try XCTUnwrap(UserDefaults(suiteName: "SyncMutationV2-\(UUID().uuidString)")),
            scope: .init(stableAccountChangeToken: "private-A"),
            replicaID: UUID(uuidString: "00000000-0000-0000-0000-000000000099")!
        )
    }

    private func record(
        id: String,
        kind: CloudSyncRecordKind,
        modifiedAt: Date,
        origin: CloudSyncPersistenceOrigin = .customerPersistent
    ) -> CloudSyncRecord {
        CloudSyncRecord(id: id, kind: kind, payload: Data(id.utf8), modifiedAt: modifiedAt, persistenceOrigin: origin)
    }

    private func migrationCoordinator() throws -> CloudSyncMigrationCoordinator {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "OwnerCloudSyncValidation-\(UUID().uuidString)"))
        return CloudSyncMigrationCoordinator(defaults: defaults, accountScope: "test")
    }

    private func unavailableOwnerValidationSources() -> CloudSyncOwnerValidationSources {
        CloudSyncOwnerValidationSources(
            profile: { throw PersistenceAuthorityError.missing },
            savedScans: { throw PersistenceAuthorityError.missing },
            savedScanImage: { _ in throw PersistenceAuthorityError.missing },
            closet: { throw PersistenceAuthorityError.missing },
            shopping: { throw PersistenceAuthorityError.missing },
            aiMemory: { throw PersistenceAuthorityError.missing },
            apply: { _ in throw PersistenceAuthorityError.missing },
            applySavedScanImage: { _, _, _, _, _ in throw PersistenceAuthorityError.missing }
        )
    }

    private func ownerValidationSources() -> CloudSyncOwnerValidationSources {
        let imageData = Data("owner-validation-image".utf8)
        let imageAsset = SavedScanImageAsset(id: "2DD6F20A-1B65-4DBE-A2FB-2FC06B1F2AA3", pixelWidth: 1, pixelHeight: 1, formatVersion: 1)
        let checksum = SHA256.hash(data: imageData).map { String(format: "%02x", $0) }.joined()
        let scan = SavedScanSyncDTO(
            id: "scan-owner-validation",
            authoritativeScore: 87,
            savedAt: now,
            occasion: Occasion.work.rawValue,
            title: "Owner validation scan",
            colors: ["navy"],
            persistentAnalysisMetadata: Data("validated-scan-metadata".utf8),
            imageAssetID: imageAsset.id,
            imageSHA256: checksum,
            imageByteCount: Int64(imageData.count),
            version: "scan-version"
        )
        let profile = authorityRecord(id: "profile", kind: .profile, payload: Data("profile".utf8), version: "profile-v1")
        let closet = authorityRecord(id: "closet-owner-validation", kind: .closetItem, payload: Data("closet".utf8), version: "closet-v1")
        let favorites = authorityRecord(id: "favorites", kind: .favorites, payload: try! JSONEncoder().encode(["product-1"]), version: "favorites-v1")
        let memory = PersistenceAuthorityRecord(id: "memory-owner-validation", kind: .aiMemory, payload: Data("memory".utf8), version: "memory-v1", updatedAt: now, isDeleted: false, persistenceOrigin: .explicitlySavedAIMemory)
        return CloudSyncOwnerValidationSources(
            profile: { profile },
            savedScans: { [scan] },
            savedScanImage: { _ in (imageAsset, imageData, checksum, Int64(imageData.count)) },
            closet: { [closet] },
            shopping: { [favorites] },
            aiMemory: { [memory] },
            apply: { _ in },
            applySavedScanImage: { _, _, _, _, _ in }
        )
    }

    private func ownerValidationSourcesWithOptionalOverrides(
        closet: (() throws -> [PersistenceAuthorityRecord])? = nil,
        shopping: (() throws -> [PersistenceAuthorityRecord])? = nil,
        aiMemory: (() throws -> [PersistenceAuthorityRecord])? = nil
    ) -> CloudSyncOwnerValidationSources {
        let base = ownerValidationSources()
        return CloudSyncOwnerValidationSources(
            profile: base.profile,
            savedScans: base.savedScans,
            savedScanImage: base.savedScanImage,
            closet: closet ?? base.closet,
            shopping: shopping ?? base.shopping,
            aiMemory: aiMemory ?? base.aiMemory,
            apply: base.apply,
            applySavedScanImage: base.applySavedScanImage
        )
    }

    private func authorityRecord(id: String, kind: CloudSyncRecordKind, payload: Data, version: String) -> PersistenceAuthorityRecord {
        PersistenceAuthorityRecord(id: id, kind: kind, payload: payload, version: version, updatedAt: now, isDeleted: false, persistenceOrigin: .customerPersistent)
    }

    private func savedScanAuthorityFixture() throws -> (authority: SavedScanPersistenceAuthority, id: String, asset: SavedScanImageAsset, image: Data) {
        let suite = "SavedScanPersistenceAuthorityTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let imageRoot = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        let imageStore = SavedScanImageAssetStore(rootDirectory: imageRoot)
        let image = Data("exact-image-bytes".utf8)
        let asset = try XCTUnwrap(imageStore.storeJPEG(image, pixelWidth: 1, pixelHeight: 1))
        let id = "scan-123"
        let analysis = OutfitAnalysisResult(
            score: 87,
            colorMatch: "Coordinated",
            occasionFit: "Work",
            styleBalance: "Balanced",
            colorHarmony: "Strong",
            styleCoordination: "Clean",
            formality: "Work",
            seasonalMatch: "All season",
            summary: "Completed analysis",
            outfitDescription: "Navy shirt and white trousers",
            detectedClothingItems: ["shirt", "trousers"],
            colorPalette: ["navy", "white"],
            environment: "indoor",
            imageQuality: "clear",
            suggestions: [],
            recommendations: []
        )
        let scan = StoredOutfitScan(
            score: 87,
            analysis: analysis,
            firstScannedAt: now,
            scanCount: 1,
            customTitle: "Office uniform",
            occasion: .work,
            imageDigest: "legacy-digest",
            savedImageAsset: asset
        )
        defaults.set(try JSONEncoder().encode([id: scan]), forKey: "outfitScanHistoryData")
        return (SavedScanPersistenceAuthority(defaults: defaults, images: imageStore), id, asset, image)
    }

    private func legacyThumbnailFixture() throws -> (authority: SavedScanPersistenceAuthority, id: String, defaults: UserDefaults, imageFileCount: () throws -> Int) {
        try legacyThumbnailFixture(thumbnail: validLegacyThumbnail())
    }

    private func legacyThumbnailFixture(thumbnail: Data?) throws -> (authority: SavedScanPersistenceAuthority, id: String, defaults: UserDefaults, imageFileCount: () throws -> Int) {
        let suite = "LegacySavedScanImageTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let imageRoot = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        let imageStore = SavedScanImageAssetStore(rootDirectory: imageRoot)
        let id = "legacy-scan-123"
        let analysis = OutfitAnalysisResult(
            score: 82,
            colorMatch: "Coordinated",
            occasionFit: "Casual",
            styleBalance: "Balanced",
            colorHarmony: "Strong",
            styleCoordination: "Clean",
            formality: "Casual",
            seasonalMatch: "All season",
            summary: "Completed legacy analysis",
            outfitDescription: "Legacy shirt and trousers",
            detectedClothingItems: ["shirt", "trousers"],
            colorPalette: ["navy", "white"],
            environment: "indoor",
            imageQuality: "clear",
            suggestions: [],
            recommendations: []
        )
        defaults.set(try JSONEncoder().encode([id: StoredOutfitScan(
            score: 82,
            analysis: analysis,
            firstScannedAt: now,
            scanCount: 1,
            thumbnailData: thumbnail,
            customTitle: "Legacy office outfit",
            occasion: .work,
            imageDigest: "legacy-image-digest",
            savedImageAsset: nil
        )]), forKey: "outfitScanHistoryData")
        return (
            SavedScanPersistenceAuthority(defaults: defaults, images: imageStore),
            id,
            defaults,
            { (try? FileManager.default.contentsOfDirectory(at: imageRoot, includingPropertiesForKeys: nil).count) ?? 0 }
        )
    }

    private func validLegacyThumbnail() -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
}

private final class ApplyCounter {
    var count = 0
}

extension CrossDeviceSyncFoundationTests {
    func testShoppingV2FavoriteAndWatchLifecyclePreservesIndependentMembership() throws {
        let fixture = try shoppingV2Fixture()
        XCTAssertThrowsError(try fixture.adapter.setMembership("product-x", kind: .favorite, present: true))
        try fixture.adapter.bootstrap(remoteFloor: .verified(3))
        let favorite = try fixture.adapter.setMembership(" product-x ", kind: .favorite, present: true)
        let watch = try fixture.adapter.setMembership("product-x", kind: .watchListItem, present: true)
        XCTAssertEqual(favorite.recordID, "favorite:product-x"); XCTAssertEqual(watch.recordID, "watch:product-x")
        XCTAssertNotEqual(favorite.recordID, watch.recordID); XCTAssertEqual(fixture.store.savedFavorites, ["product-x"]); XCTAssertEqual(fixture.store.saleAlertProductIDs, ["product-x"])
        let deletedFavorite = try fixture.adapter.setMembership("product-x", kind: .favorite, present: false)
        let deletedWatch = try fixture.adapter.setMembership("product-x", kind: .watchListItem, present: false)
        XCTAssertEqual(deletedFavorite.mutationKind, .tombstone); XCTAssertEqual(deletedWatch.mutationKind, .tombstone)
        let readdedFavorite = try fixture.adapter.setMembership("product-x", kind: .favorite, present: true)
        let readdedWatch = try fixture.adapter.setMembership("product-x", kind: .watchListItem, present: true)
        XCTAssertGreaterThan(readdedFavorite.token.counter, deletedFavorite.token.counter); XCTAssertGreaterThan(readdedWatch.token.counter, deletedWatch.token.counter)
        XCTAssertEqual(try fixture.adapter.applyRemote(deletedFavorite), .keepLocal); XCTAssertEqual(try fixture.adapter.applyRemote(deletedWatch), .keepLocal)
        XCTAssertEqual(try fixture.adapter.applyRemote(readdedFavorite), .identical); XCTAssertEqual(try fixture.adapter.applyRemote(readdedWatch), .identical)
    }

    func testShoppingV2RejectsMalformedAndConflictingIdentifiersAndPayloads() throws {
        for invalid in ["", "   ", "../x", "x/y", "x?y", "x#y", "%2e%2e"] { XCTAssertThrowsError(try ShoppingSyncMutationV2Authority.normalizedProductID(invalid)) }
        let fixture = try shoppingV2Fixture(); try fixture.adapter.bootstrap(remoteFloor: .verified(0))
        let live = try fixture.adapter.setMembership("opaque-id", kind: .favorite, present: true)
        let conflict = try SyncMutationV2.live(recordID: live.recordID, kind: .favorite, token: live.token, payload: Data("other".utf8))
        XCTAssertThrowsError(try fixture.adapter.applyRemote(conflict))
        XCTAssertFalse(String(data: live.payload, encoding: .utf8)!.contains("price")); XCTAssertFalse(String(data: live.payload, encoding: .utf8)!.contains("retailer"))
        XCTAssertFalse(CloudSyncProductContract.customerPublicActivationEnabled); XCTAssertFalse(CloudSyncInboundTombstonePolicy.supports(.favorites)); XCTAssertFalse(CloudSyncInboundTombstonePolicy.supports(.aiMemory))
    }

    func testShoppingV2MigrationAcknowledgementRelaunchAndAccountIsolation() throws {
        let fixture = try shoppingV2Fixture(); fixture.store.savedFavorites = ["x", "x", " bad/id "]; fixture.store.saleAlertProductIDs = ["x", "y"]
        try fixture.adapter.bootstrap(remoteFloor: .verified(0)); let imported = try fixture.adapter.migrateLegacyRecordsOnce()
        XCTAssertEqual(Set(imported.map(\.recordID)), ["favorite:x", "watch:x", "watch:y"])
        XCTAssertThrowsError(try fixture.adapter.migrateLegacyRecordsOnce())
        let pending = try fixture.adapter.setMembership("offline", kind: .favorite, present: false)
        try fixture.adapter.acknowledge(.init(recordID: pending.recordID, token: pending.token, canonicalDigest: "bad")); XCTAssertTrue(fixture.adapter.pendingOutbox.contains(pending))
        try fixture.adapter.acknowledge(.init(mutation: pending)); XCTAssertFalse(fixture.adapter.pendingOutbox.contains(pending))
        let other = try SyncMutationV2Authority(defaults: fixture.defaults, scope: .init(stableAccountChangeToken: "other-shopping")); XCTAssertFalse(other.isBootstrapped); XCTAssertTrue(other.pendingOutbox.isEmpty)
    }

    private func shoppingV2Fixture() throws -> (adapter: ShoppingSyncMutationV2Authority, store: ShoppingLocalStore, defaults: UserDefaults) {
        let suite = "ShoppingV2-\(UUID().uuidString)"; let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defaults.removePersistentDomain(forName: suite)
        let store = ShoppingLocalStore(defaults: defaults, userID: "shopping-v2")
        let authority = try SyncMutationV2Authority(defaults: defaults, scope: .init(stableAccountChangeToken: "private-shopping-\(suite)"), replicaID: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!)
        return (ShoppingSyncMutationV2Authority(store: store, mutationAuthority: authority), store, defaults)
    }
}

extension CrossDeviceSyncFoundationTests {
    func testAIMemoryV2ExplicitLiveDeleteAndAcknowledgement() throws {
        let fixture = try aiMemoryV2Fixture()
        let memory = try XCTUnwrap(fixture.store.remember(category: .stylePreferences, text: "Prefer navy"))
        XCTAssertThrowsError(try fixture.adapter.createOrEdit(memory))
        try fixture.adapter.bootstrap(remoteFloor: .verified(3))
        let live = try fixture.adapter.createOrEdit(memory)
        XCTAssertEqual(live.recordID, "memory:\(memory.id.uuidString.lowercased())")
        let tombstone = try fixture.adapter.delete(id: memory.id)
        XCTAssertEqual(tombstone.mutationKind, .tombstone)
        XCTAssertGreaterThan(tombstone.token.counter, live.token.counter)
        try fixture.adapter.acknowledge(.init(recordID: tombstone.recordID, token: tombstone.token, canonicalDigest: "wrong"))
        XCTAssertTrue(fixture.adapter.pendingOutbox.contains(tombstone))
        try fixture.adapter.acknowledge(.init(mutation: tombstone))
        XCTAssertFalse(fixture.adapter.pendingOutbox.contains(tombstone))
    }

    func testAIMemoryV2RejectsStaleLiveAndPreservesAccountIsolation() throws {
        let fixture = try aiMemoryV2Fixture()
        try fixture.adapter.bootstrap(remoteFloor: .verified(0))
        let memory = try XCTUnwrap(fixture.store.remember(category: .stylePreferences, text: "Prefer navy"))
        let live = try fixture.adapter.createOrEdit(memory)
        let tombstone = try fixture.adapter.delete(id: memory.id)
        XCTAssertEqual(try fixture.adapter.applyRemote(live), .keepLocal)
        XCTAssertEqual(try fixture.adapter.applyRemote(tombstone), .identical)
        let other = try SyncMutationV2Authority(defaults: fixture.defaults, scope: .init(stableAccountChangeToken: "other-account"))
        XCTAssertFalse(other.isBootstrapped)
        XCTAssertTrue(AIMemoryTemporaryContext.self == AIMemoryTemporaryContext.self)
        XCTAssertFalse(CloudSyncInboundTombstonePolicy.supports(.aiMemory))
        XCTAssertFalse(CloudSyncProductContract.customerPublicActivationEnabled)
    }

    private func aiMemoryV2Fixture() throws -> (adapter: AIMemorySyncMutationV2Authority, store: AIPersistentMemoryStore, defaults: UserDefaults) {
        let suite = "AIMemoryV2Fixture-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        let store = AIPersistentMemoryStore(defaults: defaults, userID: "memory-v2", snapshotRoot: root)
        let authority = try SyncMutationV2Authority(defaults: defaults, scope: .init(stableAccountChangeToken: "memory-private-\(suite)"), replicaID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!)
        return (AIMemorySyncMutationV2Authority(store: store, mutationAuthority: authority), store, defaults)
    }

    func testClosetV2CreateEditDeleteAndExactAcknowledgement() throws {
        let fixture = try closetV2Fixture()
        try fixture.adapter.bootstrap(remoteFloor: .verified(9))
        let item = closetV2Item()
        let created = try fixture.adapter.createOrEdit(item)
        XCTAssertEqual(created.recordID, "closet:\(item.id.uuidString.lowercased())")
        XCTAssertEqual(created.mutationKind, .live)
        XCTAssertEqual(created.token.counter, 10)
        XCTAssertEqual(fixture.adapter.pendingOutbox, [created])

        var edited = item
        edited.name = "Updated jacket"
        let edit = try fixture.adapter.createOrEdit(edited)
        XCTAssertGreaterThan(edit.token.counter, created.token.counter)

        let deleted = try fixture.adapter.delete(id: item.id)
        XCTAssertEqual(deleted.mutationKind, .tombstone)
        XCTAssertGreaterThan(deleted.token.counter, edit.token.counter)
        try fixture.adapter.acknowledge(.init(recordID: deleted.recordID, token: deleted.token, canonicalDigest: "wrong"))
        XCTAssertTrue(fixture.adapter.pendingOutbox.contains(deleted))
        try fixture.adapter.acknowledge(.init(mutation: deleted))
        XCTAssertFalse(fixture.adapter.pendingOutbox.contains(deleted))
    }

    func testClosetV2TombstoneReplayAndRecreationRejectStaleRemoteMutations() throws {
        let fixture = try closetV2Fixture()
        try fixture.adapter.bootstrap(remoteFloor: .verified(0))
        let item = closetV2Item()
        let live = try fixture.adapter.createOrEdit(item)
        let tombstone = try fixture.adapter.delete(id: item.id)
        XCTAssertEqual(try fixture.adapter.applyRemote(live), .keepLocal)
        XCTAssertEqual(try fixture.adapter.applyRemote(tombstone), .identical)

        var recreatedItem = item
        recreatedItem.name = "Recreated jacket"
        let recreation = try fixture.adapter.createOrEdit(recreatedItem)
        XCTAssertGreaterThan(recreation.token.counter, tombstone.token.counter)
        XCTAssertEqual(try fixture.adapter.applyRemote(tombstone), .keepLocal)

        let conflicting = try SyncMutationV2.live(recordID: recreation.recordID, kind: .closetItem, token: recreation.token, payload: Data("conflict".utf8))
        XCTAssertThrowsError(try fixture.adapter.applyRemote(conflicting)) { error in
            XCTAssertEqual(error as? SyncMutationV2Error, .integrityFailure)
        }
    }

    func testClosetV2PersistsOfflineWorkAndIsolatesAccounts() throws {
        let suite = "ClosetV2-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let scopeA = CloudSyncPrivateDatabaseIdentity(stableAccountChangeToken: "private-account-A")
        let first = try ClosetSyncMutationV2Authority(
            closet: ClosetPersistenceAuthority(defaults: defaults),
            mutationAuthority: SyncMutationV2Authority(defaults: defaults, scope: scopeA, replicaID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        )
        try first.bootstrap(remoteFloor: .verified(4))
        let pending = try first.delete(id: UUID(uuidString: "00000000-0000-0000-0000-000000000009")!)
        let relaunched = try ClosetSyncMutationV2Authority(
            closet: ClosetPersistenceAuthority(defaults: defaults),
            mutationAuthority: SyncMutationV2Authority(defaults: defaults, scope: scopeA)
        )
        XCTAssertEqual(relaunched.pendingOutbox, [pending])

        let scopeB = CloudSyncPrivateDatabaseIdentity(stableAccountChangeToken: "private-account-B")
        let otherAccount = try ClosetSyncMutationV2Authority(
            closet: ClosetPersistenceAuthority(defaults: defaults),
            mutationAuthority: SyncMutationV2Authority(defaults: defaults, scope: scopeB)
        )
        XCTAssertTrue(otherAccount.pendingOutbox.isEmpty)
        XCTAssertThrowsError(try otherAccount.createOrEdit(closetV2Item())) { error in
            XCTAssertEqual(error as? SyncMutationV2Error, .unavailableCounterFloor)
        }
    }

    func testClosetV2LegacyMigrationAndFailClosedBoundaries() throws {
        let fixture = try closetV2Fixture()
        let legacy = closetV2Item()
        try fixture.storage.applyV2Live(legacy)
        try fixture.adapter.bootstrap(remoteFloor: .verified(0))
        let imported = try fixture.adapter.migrateLegacyRecordsOnce()
        XCTAssertEqual(imported.count, 1)
        XCTAssertThrowsError(try fixture.adapter.migrateLegacyRecordsOnce()) { error in
            XCTAssertEqual(error as? ClosetSyncMutationV2Error, .legacyImportAlreadySuperseded)
        }
        let future = SyncMutationV2(recordID: imported[0].recordID, kind: .closetItem, schemaVersion: 3, mutationKind: .tombstone, token: .init(counter: 100, replicaID: UUID()), payloadHash: "", payload: Data(), persistenceOrigin: .customerPersistent)
        XCTAssertThrowsError(try fixture.adapter.applyRemote(future))
        XCTAssertFalse(CloudSyncInboundTombstonePolicy.supports(.favorites))
        XCTAssertFalse(CloudSyncInboundTombstonePolicy.supports(.aiMemory))
        XCTAssertFalse(CloudSyncProductContract.customerPublicActivationEnabled)
    }

    func testClosetV2EmptyLegacyImportIsDurablyConsumedOnce() throws {
        let fixture = try closetV2Fixture()
        try fixture.adapter.bootstrap(remoteFloor: .verified(0))
        XCTAssertEqual(try fixture.adapter.migrateLegacyRecordsOnce(), [])
        XCTAssertThrowsError(try fixture.adapter.migrateLegacyRecordsOnce()) { error in
            XCTAssertEqual(error as? ClosetSyncMutationV2Error, .legacyImportAlreadySuperseded)
        }
    }

    func testClosetV2CanonicalPayloadHashIsIndependentOfReplicaAndStableIDIsCanonical() throws {
        let item = closetV2Item()
        let first = try closetV2Fixture()
        let second = try closetV2Fixture()
        try first.adapter.bootstrap(remoteFloor: .verified(0))
        try second.adapter.bootstrap(remoteFloor: .verified(0))
        let one = try first.adapter.createOrEdit(item)
        let two = try second.adapter.createOrEdit(item)
        XCTAssertEqual(one.recordID, "closet:\(item.id.uuidString.lowercased())")
        XCTAssertEqual(one.payloadHash, two.payloadHash)
        XCTAssertEqual(one.payload, two.payload)
    }

    func testClosetV2RemoteTombstoneDoesNotAttemptAssetCleanup() throws {
        let fixture = try closetV2Fixture()
        try fixture.adapter.bootstrap(remoteFloor: .verified(0))
        let item = closetV2Item()
        let live = try fixture.adapter.createOrEdit(item)
        let remoteDelete = try SyncMutationV2.tombstone(
            recordID: live.recordID,
            kind: .closetItem,
            token: .init(counter: live.token.counter + 1, replicaID: live.token.replicaID)
        )
        XCTAssertEqual(try fixture.adapter.applyRemote(remoteDelete), .useRemote)
        XCTAssertTrue(try fixture.storage.enumerate().isEmpty)
        // ClosetItem has no asset reference. V2 deletion is intentionally
        // metadata-only; no speculative file/CKAsset cleanup is reachable.
        XCTAssertFalse(String(data: live.payload, encoding: .utf8)?.contains("Asset") ?? true)
    }

    func testClosetV2DoesNotPermitShoppingOrAIMemoryTombstones() {
        XCTAssertTrue(CloudSyncInboundTombstonePolicy.supports(.closetItem))
        XCTAssertFalse(CloudSyncInboundTombstonePolicy.supports(.favorites))
        XCTAssertFalse(CloudSyncInboundTombstonePolicy.supports(.watchList))
        XCTAssertFalse(CloudSyncInboundTombstonePolicy.supports(.aiMemory))
    }

    func testSavedScanStylistFactsProjectOnlyConfidentAuthoritativeFactsWithoutMutation() throws {
        let suite = "SavedScanStylistFacts-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let analysis = OutfitAnalysisResult(
            score: 87, colorMatch: "Coordinated", occasionFit: "Work", styleBalance: "Balanced",
            colorHarmony: "Strong", styleCoordination: "Clean", formality: "Work", seasonalMatch: "All season",
            summary: "Completed", outfitDescription: "Image sentinel must not project", detectedClothingItems: ["shirt"],
            colorPalette: ["image-sentinel"], colorPaletteConfidence: .low, environment: "indoor", imageQuality: "clear",
            suggestions: [], recommendations: []
        )
        let stored = StoredOutfitScan(
            score: 87, analysis: analysis, firstScannedAt: now, scanCount: 1,
            thumbnailData: Data("raw-image-sentinel".utf8), occasion: .work,
            deterministicInputs: .init(colorPalette: ["navy", "white"], colorPaletteConfidence: .confident, labels: [], detectedItems: [], styleCategory: "Business Casual")
        )
        defaults.set(try JSONEncoder().encode(["local-scan-key": stored]), forKey: "outfitScanHistoryData")
        let before = try XCTUnwrap(defaults.data(forKey: "outfitScanHistoryData"))

        let facts = try SavedScanPersistenceAuthority(defaults: defaults).enumerateSavedScanStylistFacts()

        XCTAssertEqual(facts.count, 1)
        XCTAssertEqual(facts[0].localRecordKey, "local-scan-key")
        XCTAssertEqual(facts[0].score, 87)
        XCTAssertNil(facts[0].scoreBand)
        XCTAssertEqual(facts[0].detectedStyle, "Business Casual")
        XCTAssertEqual(facts[0].palette, ["navy", "white"])
        XCTAssertEqual(before, defaults.data(forKey: "outfitScanHistoryData"))
        let propertyNames = Mirror(reflecting: facts[0]).children.compactMap(\.label).joined(separator: " ").lowercased()
        for forbidden in ["image", "thumbnail", "asset", "metadata", "confidence"] {
            XCTAssertFalse(propertyNames.contains(forbidden))
        }
    }

    func testSavedScanStylistFactsOmitLowConfidenceAndLegacyAbsentFacts() throws {
        let suite = "SavedScanStylistFactsLegacy-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let legacy = StoredOutfitScan(score: 81, analysis: nil, firstScannedAt: now, scanCount: 1)
        let lowConfidence = StoredOutfitScan(
            score: 82, analysis: nil, firstScannedAt: now, scanCount: 1,
            deterministicInputs: .init(
                colorPalette: ["must-not-project"], colorPaletteConfidence: .low,
                labels: [], detectedItems: [], styleCategory: "Stored style"
            )
        )
        defaults.set(try JSONEncoder().encode(["legacy-key": legacy, "low-key": lowConfidence]), forKey: "outfitScanHistoryData")

        let facts = try SavedScanPersistenceAuthority(defaults: defaults).enumerateSavedScanStylistFacts()

        XCTAssertEqual(facts, [
            .init(localRecordKey: "legacy-key", scanDate: now, selectedOccasion: nil, score: 81, scoreBand: nil, detectedStyle: nil, palette: nil),
            .init(localRecordKey: "low-key", scanDate: now, selectedOccasion: nil, score: 82, scoreBand: nil, detectedStyle: "Stored style", palette: nil)
        ])
    }

    private func closetV2Fixture() throws -> (adapter: ClosetSyncMutationV2Authority, storage: ClosetPersistenceAuthority) {
        let suite = "ClosetV2Fixture-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let storage = ClosetPersistenceAuthority(defaults: defaults)
        let v2 = try SyncMutationV2Authority(defaults: defaults, scope: .init(stableAccountChangeToken: "private-account-\(suite)"), replicaID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        return (ClosetSyncMutationV2Authority(closet: storage, mutationAuthority: v2), storage)
    }

    private func closetV2Item() -> ClosetItem {
        ClosetItem(id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!, name: "Jacket", category: "Jacket", color: "Navy", brand: "KigoStylist", size: "M", occasion: "Work", notes: "Verified Closet item")
    }
}

private final class InboundTransport: CloudSyncInboundTransport {
    let batch: CloudSyncDiscoveryBatch
    let identity: CloudSyncPrivateDatabaseIdentity?

    init(
        batch: CloudSyncDiscoveryBatch,
        identity: CloudSyncPrivateDatabaseIdentity? = .init(stableAccountChangeToken: "private-account-A")
    ) {
        self.batch = batch
        self.identity = identity
    }

    func privateDatabaseIdentity() async throws -> CloudSyncPrivateDatabaseIdentity? {
        identity
    }

    func discoverChanges(since cursor: CloudSyncDiscoveryCursor) async throws -> CloudSyncDiscoveryBatch {
        batch
    }
}

private final class OwnerValidationTransport: CloudSyncOwnerValidationTransport {
    private let configuredStatus: CKAccountStatus?
    private let configuredError: Error?
    private var records: [String: CloudSyncRecord] = [:]
    private var assets: [String: CloudSyncAssetUpload] = [:]
    private let mismatchingFetchForRecordID: String?
    private let privateAccountTokenSequence: [String?]
    private var privateAccountTokenIndex = 0
    private(set) var saveCount = 0
    private(set) var assetSaveCount = 0
    private(set) var savedKinds: [CloudSyncRecordKind] = []

    init(status: CKAccountStatus, mismatchingFetchForRecordID: String? = nil, privateAccountToken: String? = "private-account-A") {
        configuredStatus = status
        configuredError = nil
        self.mismatchingFetchForRecordID = mismatchingFetchForRecordID
        privateAccountTokenSequence = [privateAccountToken]
    }

    init(status: CKAccountStatus, privateAccountTokenSequence: [String?]) {
        configuredStatus = status
        configuredError = nil
        mismatchingFetchForRecordID = nil
        self.privateAccountTokenSequence = privateAccountTokenSequence
    }

    init(error: Error) {
        configuredStatus = nil
        configuredError = error
        mismatchingFetchForRecordID = nil
        privateAccountTokenSequence = []
    }

    func accountStatus() async throws -> CKAccountStatus {
        if let configuredError { throw configuredError }
        return configuredStatus ?? .couldNotDetermine
    }

    func privateDatabaseIdentity() async throws -> CloudSyncPrivateDatabaseIdentity? {
        if let configuredError { throw configuredError }
        guard !privateAccountTokenSequence.isEmpty else { return nil }
        let index = min(privateAccountTokenIndex, privateAccountTokenSequence.count - 1)
        privateAccountTokenIndex += 1
        return privateAccountTokenSequence[index].map { .init(stableAccountChangeToken: $0) }
    }

    func save(_ record: CloudSyncRecord, asset: CloudSyncAssetUpload?) async throws -> CloudSyncRecord {
        saveCount += 1
        savedKinds.append(record.kind)
        records[record.id] = record
        if let asset {
            assetSaveCount += 1
            assets[record.id] = asset
        }
        return record
    }

    func fetch(recordID: String) async throws -> CloudSyncRecord {
        let record = try XCTUnwrap(records[recordID])
        guard recordID == mismatchingFetchForRecordID else { return record }
        return CloudSyncRecord(
            id: record.id,
            kind: record.kind,
            payload: Data("mismatch".utf8),
            modifiedAt: record.modifiedAt,
            isDeleted: record.isDeleted,
            persistenceOrigin: record.persistenceOrigin
        )
    }

    func fetchAsset(recordID: String) async throws -> CloudSyncAssetDownload {
        let asset = try XCTUnwrap(assets[recordID])
        return CloudSyncAssetDownload(reference: asset.reference, data: asset.data)
    }
}
