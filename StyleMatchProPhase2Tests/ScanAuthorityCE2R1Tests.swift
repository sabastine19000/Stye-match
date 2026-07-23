import XCTest
@testable import StyleMatchPro

final class ScanAuthorityCE2R1Tests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_753_200_000)

    func testCE2R101AtomicCaptureSuppliesOneAuthority() async throws {
        let authority = try await resolve(.latestValidCompleted, records: ["a": record()])
        assertEqual(authority.identity.localID.rawValue, "a")
        assertEqual(authority.analysis.score, 80)
        assertEqual(authority.selectedOccasion, .work)
        assertEqual(authority.completedAt, date)
    }

    func testCE2R102SourceRevisionChangeFails() async throws {
        let source = FakeSource(data: try data(["a": record()]))
        await source.setBoundary(.init(accountScopeDigest: "account", sourceRevision: "changed"))
        assertEqual(await failure(repository: .init(source: source)), .sourceChanged)
    }

    func testCE2R103AccountBoundaryChangeFails() async throws {
        let source = FakeSource(data: try data(["a": record()]))
        await source.setBoundary(.init(accountScopeDigest: "other", sourceRevision: "revision"))
        assertEqual(await failure(repository: .init(source: source)), .accountChanged)
    }

    func testCE2R104InputFactoryDoesNotReadStorage() async throws {
        let source = FakeSource(data: try data(["a": record()]))
        let authority = try await authority(repository: .init(source: source))
        _ = try input(authority)
        assertEqual(await source.captureCount, 1)
        assertEqual(await source.boundaryCount, 1)
    }

    func testCE2R105CancellationReturnsNoPartialAuthority() async throws {
        let repository = ScanAuthorityRepository(source: FakeSource(data: try data(["a": record()])))
        let task = Task { await repository.resolve(.latestValidCompleted) }
        task.cancel()
        assertEqual(resultFailure(await task.value), .cancelled)
    }

    func testCE2R106MutationDuringResolutionNeverMixesFields() async throws {
        let source = FakeSource(data: try data(["a": record()]))
        await source.setBoundary(.init(accountScopeDigest: "account", sourceRevision: "new"))
        assertEqual(await failure(repository: .init(source: source)), .sourceChanged)
    }

    func testCE2R107ActiveAndLatestSameIDHaveSameIdentity() async throws {
        let records = ["a": record()]
        let latest = try await resolve(.latestValidCompleted, records: records)
        let active = try await resolve(.currentCompleted(id: id("a"), expected: nil), records: records)
        assertEqual(latest.identity, active.identity)
    }

    func testCE2R108HistoricalBeatsNewerCompletedScan() async throws {
        let records = ["a": record(at: date), "b": record(at: date.addingTimeInterval(1))]
        assertEqual(try await resolve(.explicitHistorical(id: id("a"), expected: nil), records: records).identity.localID, id("a"))
    }

    func testCE2R109RepositoryRetainsNoHiddenHistoricalSelection() async throws {
        let records = ["a": record(at: date), "b": record(at: date.addingTimeInterval(1))]
        _ = try await resolve(.explicitHistorical(id: id("a"), expected: nil), records: records)
        assertEqual(try await resolve(.latestValidCompleted, records: records).identity.localID, id("b"))
    }

    func testCE2R110ExplicitCurrentBeatsLatest() async throws {
        let records = ["a": record(at: date), "b": record(at: date.addingTimeInterval(1))]
        assertEqual(try await resolve(.currentCompleted(id: id("a"), expected: nil), records: records).identity.localID, id("a"))
    }

    func testCE2R111InvalidHistoricalDoesNotFallback() async throws {
        assertEqual(await failure(.explicitHistorical(id: id("missing"), expected: nil), records: ["a": record()]), .scanNotFound)
    }

    func testCE2R112InvalidCurrentDoesNotFallback() async throws {
        assertEqual(await failure(.currentCompleted(id: id("missing"), expected: nil), records: ["a": record()]), .scanNotFound)
    }

    func testCE2R113LatestExcludesIncomplete() async throws {
        let records = ["a": record(), "b": record(includeAnalysis: false, at: date.addingTimeInterval(1))]
        assertEqual(try await resolve(.latestValidCompleted, records: records).identity.localID, id("a"))
    }

    func testCE2R114LatestExcludesFailed() async throws {
        let records = ["a": record(), "b": record(at: date.addingTimeInterval(1), lifecycle: .failed)]
        assertEqual(try await resolve(.latestValidCompleted, records: records).identity.localID, id("a"))
    }

    func testCE2R115LatestExcludesPlaceholder() async throws {
        let records = ["a": record(), "b": record(at: date.addingTimeInterval(1), lifecycle: .placeholder)]
        assertEqual(try await resolve(.latestValidCompleted, records: records).identity.localID, id("a"))
    }

    func testCE2R116DecoderIsolatesCorruptCandidate() async throws {
        let valid = try XCTUnwrap(try JSONSerialization.jsonObject(with: data(["a": record()])) as? [String: Any])
        var root = valid
        root["bad"] = "not-a-record"
        let source = FakeSource(data: try JSONSerialization.data(withJSONObject: root))
        assertEqual(try await authority(repository: .init(source: source)).identity.localID, id("a"))
        let explicitSource = FakeSource(data: try JSONSerialization.data(withJSONObject: root))
        assertEqual(
            await failure(
                .explicitHistorical(id: id("bad"), expected: nil),
                repository: ScanAuthorityRepository(source: explicitSource)
            ),
            .scanCorrupt
        )
    }

    func testCE2R117NoEligibleCandidateFails() async throws {
        assertEqual(await failure(.latestValidCompleted, records: ["a": record(includeAnalysis: false)]), .noAuthoritativeScan)
    }

    func testCE2R118NewerScanMakesOldIdentityStale() async throws {
        let old = try await resolve(.latestValidCompleted, records: ["a": record()])
        let new = try await resolve(.latestValidCompleted, records: [
            "a": record(),
            "b": record(at: date.addingTimeInterval(1))
        ])
        XCTAssertTrue(old.identity.isStale(comparedTo: new.identity))
        assertEqual(
            await failure(
                .explicitHistorical(id: id("a"), expected: old.identity),
                records: ["a": record(
                    score: 81,
                    analysisOverride: analysis(score: 81)
                )]
            ),
            .generationMismatch
        )
    }

    func testCE2R119EqualTimestampsUseOrdinals() async throws {
        let records = [
            "a": record(metadata: metadata(id: "a", ordinal: 1)),
            "b": record(metadata: metadata(id: "b", ordinal: 2))
        ]
        assertEqual(try await resolve(.latestValidCompleted, records: records).identity.localID, id("b"))
    }

    func testCE2R120LegacyEqualMaximumTimestampsAreAmbiguous() async throws {
        assertEqual(await failure(.latestValidCompleted, records: ["a": record(), "b": record()]), .ambiguousLatest)
    }

    func testCE2R121ExplicitSelectionOpensEqualTimeLegacyRecords() async throws {
        let records = ["a": record(), "b": record()]
        assertEqual(try await resolve(.explicitHistorical(id: id("a"), expected: nil), records: records).identity.localID, id("a"))
        assertEqual(try await resolve(.explicitHistorical(id: id("b"), expected: nil), records: records).identity.localID, id("b"))
    }

    func testCE2R122MissingTimestampExcludedFromLatest() async throws {
        let records = ["a": record(), "b": record(includeTimestamp: false)]
        assertEqual(try await resolve(.latestValidCompleted, records: records).identity.localID, id("a"))
    }

    func testCE2R123MissingTimestampIsNeverFabricated() async throws {
        let authority = try await resolve(.explicitHistorical(id: id("a"), expected: nil), records: ["a": record(includeTimestamp: false)])
        XCTAssertNil(authority.completedAt)
    }

    func testCE2R124InputFactoryRejectsMissingTimestamp() async throws {
        let authority = try await resolve(.explicitHistorical(id: id("a"), expected: nil), records: ["a": record(includeTimestamp: false)])
        assertEqual(inputFailure(authority), .scanPartial)
    }

    func testCE2R125NewRecordStartsAtOne() throws {
        let after = fingerprintInput(generation: .legacy)
        let request = mutationRequest(
            current: nil,
            before: after,
            after: after,
            storedRecordChanged: true,
            mutation: .newScan
        )
        assertEqual(try ScanGenerationPolicy.apply(current: nil, request: request).get().generation, .legacy)
    }

    func testCE2R126ByteIdenticalRestorePreservesBothRevisions() {
        assertEqual(mutate(.restoredByteIdentical).generation, generation())
    }

    func testCE2R127RenameAdvancesOnlyRecordRevision() {
        assertEqual(mutate(.titleOnly).generation, generation(record: 3, context: 5))
    }

    func testCE2R128ScanCountAdvancesOnlyRecordRevision() {
        assertEqual(mutate(.thumbnailOnly).generation, generation(record: 3, context: 5))
    }

    func testCE2R129OccasionChangeAdvancesBothRevisions() {
        let after = context(occasionDisposition: .corrected)
        assertEqual(
            mutate(.correction(.occasionCorrection), afterContext: after).generation,
            generation(record: 3, context: 6)
        )
    }

    func testCE2R130CategoryConfirmationAdvancesBothRevisions() {
        let after = context(categoryDisposition: .confirmed)
        assertEqual(
            mutate(.correction(.categoryCorrection), afterContext: after).generation,
            generation(record: 3, context: 6)
        )
    }

    func testCE2R131RepeatedIdenticalConfirmationCanPreserveGeneration() {
        let confirmed = context(
            purpose: purpose(confirmed: .office, disposition: .confirmed)
        )
        assertEqual(
            mutate(
                .correction(.purposeConfirmation),
                beforeContext: confirmed,
                afterContext: confirmed,
                storedRecordChanged: false
            ).generation,
            generation()
        )
    }

    func testCE2R132PurposeCorrectionAdvancesBothRevisions() {
        let after = context(
            purpose: purpose(
                proposed: .factoryManufacturing,
                confirmed: .office,
                disposition: .corrected
            )
        )
        assertEqual(
            mutate(.correction(.purposeCorrection), afterContext: after).generation,
            generation(record: 3, context: 6)
        )
    }

    func testCE2R133RejectedPurposeAdvancesBothOnce() {
        let after = context(
            purpose: purpose(
                proposed: .factoryManufacturing,
                rejected: [.factoryManufacturing],
                disposition: .rejected
            )
        )
        assertEqual(
            mutate(.correction(.purposeRejection), afterContext: after).generation,
            generation(record: 3, context: 6)
        )
    }

    func testCE2R134NonContextAIWordingPreservesContextRevision() {
        let before = analysis(summary: "Original explanation")
        let after = analysis(summary: "Reworded explanation")
        assertEqual(
            mutate(
                .analysisEnrichment,
                beforeAnalysis: before,
                afterAnalysis: after
            ).generation,
            generation(record: 3, context: 5)
        )
    }

    func testCE2R135ContextBearingEnrichmentAdvancesContextRevision() {
        assertEqual(
            mutate(
                .analysisEnrichment,
                afterAnalysis: analysis(style: "Business Casual")
            ).generation,
            generation(record: 3, context: 6)
        )
    }

    func testCE2R136IdenticalReanalysisCanPreserveGeneration() {
        assertEqual(
            mutate(
                .analysisEnrichment,
                storedRecordChanged: false
            ).generation,
            generation()
        )
    }

    func testCE2R137ChangedReanalysisAdvancesContextRevision() {
        assertEqual(
            mutate(
                .analysisEnrichment,
                afterAnalysis: analysis(score: 81)
            ).generation,
            generation(record: 3, context: 6)
        )
    }

    func testCE2R138NewScanDoesNotMutatePriorGeneration() {
        let old = generation()
        _ = mutate(.titleOnly)
        assertEqual(old, generation())
    }

    func testCE2R139GenerationDoesNotDependOnTimestamp() {
        assertEqual(
            mutate(.titleOnly).generation,
            mutate(.titleOnly).generation
        )
    }

    func testCE2R140StalenessUsesIDGenerationAndFingerprint() {
        let a = identity("a", generation: generation(), fingerprint: "x")
        XCTAssertTrue(a.isStale(comparedTo: identity("b", generation: generation(), fingerprint: "x")))
        XCTAssertTrue(a.isStale(comparedTo: identity("a", generation: generation(context: 6), fingerprint: "x")))
        XCTAssertTrue(a.isStale(comparedTo: identity("a", generation: generation(), fingerprint: "y")))
    }

    func testCE2R141SameCanonicalContextHasSameFingerprint() {
        assertEqual(fingerprint(), fingerprint())
    }

    func testCE2R142EvidenceOrderingDoesNotChangeCanonicalFingerprint() {
        let first = analysis(evidence: [.silhouette, .branding])
        let second = analysis(evidence: [.branding, .silhouette])
        XCTAssertEqual(
            fingerprint(analysis: first),
            fingerprint(analysis: second)
        )
    }

    func testCE2R143MetadataOutsideContextDoesNotChangeFingerprint() {
        assertEqual(fingerprint(), fingerprint())
    }

    func testCE2R144ContextBearingFieldChangesFingerprint() {
        XCTAssertNotEqual(fingerprint(score: 80), fingerprint(score: 81))
    }

    func testCE2R145ReusedGenerationWithOlderContentFailsFingerprint() async throws {
        let bad = metadata(fingerprint: "wrong")
        assertEqual(await failure(.latestValidCompleted, records: ["a": record(metadata: bad)]), .generationMismatch)
    }

    func testCE2R146ByteIdenticalRestorePreservesIdentity() async throws {
        let records = ["a": record()]
        assertEqual(
            try await resolve(.latestValidCompleted, records: records).identity,
            try await resolve(.latestValidCompleted, records: records).identity
        )
    }

    func testCE2R147CurrentLegacyFixtureDecodesWithoutRewrite() async throws {
        assertEqual(try await resolve(.latestValidCompleted, records: ["a": record()]).analysis.score, 80)
    }

    func testCE2R148LegacyRecordGetsTransientOne() async throws {
        let authority = try await resolve(.latestValidCompleted, records: ["a": record()])
        assertEqual(authority.identity.generation, .legacy)
        assertEqual(authority.legacyState, .transientLegacyGeneration)
    }

    func testCE2R149LegacyReadDoesNotWriteMetadata() async throws {
        let source = FakeSource(data: try data(["a": record()]))
        _ = try await authority(repository: .init(source: source))
        assertEqual(await source.writeCount, 0)
    }

    func testCE2R150LegacyMissingAnalysisUnavailable() async throws {
        assertEqual(await failure(.explicitHistorical(id: id("a"), expected: nil), records: ["a": record(includeAnalysis: false)]), .scanPartial)
    }

    func testCE2R151ScoreAnalysisMismatchFails() async throws {
        assertEqual(
            await failure(
                .latestValidCompleted,
                records: ["a": record(score: 74)]
            ),
            .scoreMismatch
        )
    }

    func testCE2R152FutureSchemaFailsClosed() async throws {
        let future = StoredScanAuthorityMetadata(
            schemaVersion: 2,
            generation: .legacy,
            contextFingerprint: fingerprint(),
            completionOrdinal: 1
        )
        assertEqual(await failure(.latestValidCompleted, records: ["a": record(metadata: future)]), .unsupportedSchema)
    }

    func testCE2R153LegacyDecoderIgnoresAdditiveMetadata() async throws {
        assertEqual(try await resolve(.latestValidCompleted, records: ["a": record(metadata: metadata())]).analysis.score, 80)
    }

    func testCE2R154WitnessedDeletionReturnsDeleted() async throws {
        let repository = ScanAuthorityRepository(source: FakeSource(data: try data(["a": record()])))
        await repository.markDeletedForCurrentProcess(id("a"))
        assertEqual(await failure(.explicitHistorical(id: id("a"), expected: nil), repository: repository), .scanDeleted)
    }

    func testCE2R155AbsentAfterRestartIsMissingNotDeleted() async throws {
        assertEqual(await failure(.explicitHistorical(id: id("a"), expected: nil), records: [:]), .scanNotFound)
    }

    func testCE2R156ContainerQuarantinePreventsDecode() async throws {
        let source = FakeSource(data: Data("private-invalid".utf8), integrity: .quarantined(reference: OpaqueIntegrityReference(value: UUID())))
        assertEqual(await failure(repository: .init(source: source)), .scanQuarantined)
    }

    func testCE2R157DecodeFailureIsCorrupt() async throws {
        let source = FakeSource(data: Data("invalid".utf8))
        assertEqual(await failure(repository: .init(source: source)), .scanCorrupt)
    }

    func testCE2R158RootCorruptionDoesNotWrite() async throws {
        let source = FakeSource(data: Data("invalid".utf8))
        _ = await ScanAuthorityRepository(source: source).resolve(.latestValidCompleted)
        assertEqual(await source.writeCount, 0)
    }

    func testCE2R159AuthorityContainsNoThumbnailBytes() async throws {
        let authority = try await resolve(.latestValidCompleted, records: ["a": record(thumbnail: Data([1, 2, 3]))])
        assertEqual(authority.imageReferenceState, .present)
    }

    func testCE2R160AuthorityContractHasNoRawOCRField() throws {
        XCTAssertFalse(try source("ScanAuthorityContracts.swift").contains("detectedText"))
    }

    func testCE2R161AuthorityContractHasNoSpeechOrIdentityField() throws {
        let value = try source("ScanAuthorityContracts.swift")
        XCTAssertFalse(value.contains("speech"))
        XCTAssertFalse(value.contains("employer"))
        XCTAssertFalse(value.contains("personName"))
    }

    func testCE2R162NoDiagnosticLeaksLocalIDOrScore() throws {
        let value = try source("ScanAuthorityRepository.swift")
        XCTAssertFalse(value.contains("print("))
        XCTAssertFalse(value.contains("Logger"))
    }

    func testCE2R163NeutralModuleHasNoConsumerImports() throws {
        let joined = try scanAuthoritySources().joined(separator: "\n")
        for token in ["StylistChat", "AIAssist", "VoiceAssistant", "Shopping", "Worker"] {
            XCTAssertFalse(joined.contains(token))
        }
    }

    func testCE2R164ContextInputHasNoConsumerModel() throws {
        let value = try String(contentsOf: repositoryRoot().appendingPathComponent("StyleMatchAI/ContextEngine/ContextInferenceInput.swift"))
        XCTAssertFalse(value.contains("StylistChat"))
        XCTAssertFalse(value.contains("VoiceAssistant"))
    }

    func testCE2R165CE2R1CreatesNoWorkerPayload() throws {
        XCTAssertFalse(try scanAuthoritySources().joined().contains("URLRequest"))
    }

    func testCE2R166RemoteReferenceDoesNotContainLocalScanID() throws {
        let encoded = try JSONEncoder().encode(RemoteSafeScanReference(value: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!))
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("scan-local"))
    }

    func testCE2R167RemoteTokenCannotDecodeAsLocalID() throws {
        let encoded = try JSONEncoder().encode(RemoteSafeScanReference(value: UUID()))
        XCTAssertThrowsError(try JSONDecoder().decode(LocalScanRecordID.self, from: encoded))
    }

    func testCE2R168AuthoritativeScoreUnchanged() async throws {
        assertEqual(try await resolve(.latestValidCompleted, records: ["a": record()]).analysis.score, 80)
    }

    func testCE2R169ScoreBreakdownUnchanged() async throws {
        let authority = try await resolve(.latestValidCompleted, records: ["a": record()])
        assertEqual(authority.analysis.scoreBreakdown, analysis().scoreBreakdown)
    }

    func testCE2R170ClassificationUnchanged() async throws {
        let authority = try await resolve(.latestValidCompleted, records: ["a": record()])
        assertEqual(authority.analysis.outfitClassification, analysis().outfitClassification)
    }

    func testCE2R171ResolutionDoesNotChangeRecordCount() async throws {
        let source = FakeSource(data: try data(["a": record(), "b": record(at: date.addingTimeInterval(-1))]))
        _ = await ScanAuthorityRepository(source: source).resolve(.latestValidCompleted)
        assertEqual(await source.recordCount, 2)
    }

    func testCE2R172ResolutionPerformsNoWrite() async throws {
        let source = FakeSource(data: try data(["a": record()]))
        _ = await ScanAuthorityRepository(source: source).resolve(.latestValidCompleted)
        assertEqual(await source.writeCount, 0)
    }

    func testCE2R173ProtectedShoppingFilesAreUntouchedByModule() throws {
        let joined = try scanAuthoritySources().joined()
        XCTAssertFalse(joined.contains("ProductCatalog"))
        XCTAssertFalse(joined.contains("RetailerConfig"))
    }

    func testCE2R174CE1AndCE2AGenerationHandoffIsDeterministic() async throws {
        let authority = try await resolve(.latestValidCompleted, records: ["a": record()])
        let snapshot = try infer(input(authority))
        assertEqual(snapshot.generation, 1)
        assertEqual(snapshot.scanID, "a")
    }

    func testCE2R175NoProductionConsumerAdoptsCE2R1() throws {
        let root = repositoryRoot().appendingPathComponent("StyleMatchAI")
        let allowed = Set([
            "ScanAuthorityContracts.swift", "StoredScanRecord.swift",
            "ScanGenerationPolicy.swift", "AuthoritativeScanSelector.swift",
            "ScanAuthorityRepository.swift", "ContextInferenceInputFactory.swift",
            "ContextInferenceInput.swift", "OutfitContextContracts.swift",
            "OutfitContextEngine.swift", "ContextInferenceValidator.swift",
            "LegacyContextAdapter.swift"
        ])
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" && !allowed.contains($0.lastPathComponent) } ?? []
        for file in files {
            XCTAssertFalse(try String(contentsOf: file).contains("ScanAuthorityRepository"))
        }
    }

    func testCE2R1R01DeletionDuringAwaitedBoundaryFailsClosed() async throws {
        let source = SuspendingSource(data: try data(["a": record()]))
        let repository = ScanAuthorityRepository(source: source)
        let task = Task {
            await repository.resolve(.explicitHistorical(id: id("a"), expected: nil))
        }
        await source.waitUntilBoundaryRequested()
        assertEqual(await repository.markDeletedForCurrentProcess(id("a")), nil)
        await source.releaseBoundary()
        assertEqual(resultFailure(await task.value), .scanDeleted)
    }

    func testCE2R1R02QuarantineDuringAwaitedBoundaryFailsClosed() async throws {
        let source = SuspendingSource(data: try data(["a": record()]))
        let repository = ScanAuthorityRepository(source: source)
        let task = Task {
            await repository.resolve(.explicitHistorical(id: id("a"), expected: nil))
        }
        await source.waitUntilBoundaryRequested()
        assertEqual(await repository.markQuarantinedForCurrentProcess(id("a")), nil)
        await source.releaseBoundary()
        assertEqual(resultFailure(await task.value), .scanQuarantined)
    }

    func testCE2R1R03InvalidationEpochChangeDuringLoadFailsClosed() async throws {
        let source = SuspendingSource(data: try data(["a": record()]))
        let repository = ScanAuthorityRepository(source: source)
        let task = Task { await repository.resolve(.latestValidCompleted) }
        await source.waitUntilBoundaryRequested()
        assertEqual(await repository.invalidateForAuthorityChange(), nil)
        await source.releaseBoundary()
        assertEqual(resultFailure(await task.value), .authorityInvalidated)
    }

    func testCE2R1R04HistoricalSelectionChangeDuringLoadFailsClosed() async throws {
        let source = SuspendingSource(data: try data([
            "a": record(),
            "b": record(at: date.addingTimeInterval(1))
        ]))
        let repository = ScanAuthorityRepository(source: source)
        let task = Task {
            await repository.resolve(.explicitHistorical(id: id("a"), expected: nil))
        }
        await source.waitUntilBoundaryRequested()
        assertEqual(await repository.invalidateForAuthorityChange(), nil)
        await source.releaseBoundary()
        assertEqual(resultFailure(await task.value), .authorityInvalidated)
    }

    func testCE2R1R05StaleCompletionCannotPublishAfterNewerAuthority() async throws {
        let source = SuspendingSource(data: try data(["a": record()]))
        let repository = ScanAuthorityRepository(source: source)
        let task = Task { await repository.resolve(.latestValidCompleted) }
        await source.waitUntilBoundaryRequested()
        assertEqual(await repository.invalidateForAuthorityChange(), nil)
        await source.releaseBoundary()
        guard case .failure(.authorityInvalidated) = await task.value else {
            return XCTFail("A stale completion published authority.")
        }
    }

    func testCE2R1R06CancellationWithoutInvalidationIsCancelled() async throws {
        let source = SuspendingSource(data: try data(["a": record()]))
        let repository = ScanAuthorityRepository(source: source)
        let task = Task { await repository.resolve(.latestValidCompleted) }
        await source.waitUntilBoundaryRequested()
        task.cancel()
        await source.releaseBoundary()
        assertEqual(resultFailure(await task.value), .cancelled)
    }

    func testCE2R1R07InvalidationWithoutCancellationIsDistinct() async throws {
        let source = SuspendingSource(data: try data(["a": record()]))
        let repository = ScanAuthorityRepository(source: source)
        let task = Task { await repository.resolve(.latestValidCompleted) }
        await source.waitUntilBoundaryRequested()
        assertEqual(await repository.invalidateForAuthorityChange(), nil)
        await source.releaseBoundary()
        assertEqual(resultFailure(await task.value), .authorityInvalidated)
        XCTAssertFalse(task.isCancelled)
    }

    func testCE2R1R08EpochOverflowFailsSafelyWithoutWrapping() async throws {
        let repository = ScanAuthorityRepository(
            source: FakeSource(data: try data(["a": record()])),
            initialInvalidationEpoch: .max
        )
        assertEqual(
            await repository.invalidateForAuthorityChange(),
            .invalidationEpochOverflow
        )
        assertEqual(
            await failure(repository: repository),
            .invalidationEpochOverflow
        )
    }

    func testCE2R1R09RecordRevisionOverflowFailsSafely() {
        let generation = ScanGeneration(recordRevision: .max, contextRevision: 1)
        let before = fingerprintInput(generation: generation)
        let current = identity(
            "a",
            generation: generation,
            fingerprint: resolvedFingerprint(before)
        )
        let request = mutationRequest(
            current: current,
            before: before,
            after: before,
            storedRecordChanged: true,
            mutation: .titleOnly
        )
        assertEqual(
            resultFailure(
                ScanGenerationPolicy.apply(current: current, request: request)
            ),
            .generationOverflow
        )
    }

    func testCE2R1R10ContextRevisionOverflowFailsSafely() {
        let generation = ScanGeneration(recordRevision: 1, contextRevision: .max)
        let before = fingerprintInput(generation: generation)
        let after = fingerprintInput(
            generation: generation,
            analysis: analysis(style: "Business Casual")
        )
        let current = identity(
            "a",
            generation: generation,
            fingerprint: resolvedFingerprint(before)
        )
        let request = mutationRequest(
            current: current,
            before: before,
            after: after,
            storedRecordChanged: true,
            mutation: .analysisEnrichment
        )
        assertEqual(
            resultFailure(
                ScanGenerationPolicy.apply(current: current, request: request)
            ),
            .generationOverflow
        )
    }

    func testCE2R1R11PurposeConfirmationUsesTypedMutation() {
        let after = context(
            purpose: purpose(confirmed: .office, disposition: .confirmed)
        )
        assertEqual(
            mutate(.correction(.purposeConfirmation), afterContext: after).generation,
            generation(record: 3, context: 6)
        )
    }

    func testCE2R1R12PurposeCorrectionUsesTypedMutation() {
        let after = context(
            purpose: purpose(
                proposed: .factoryManufacturing,
                confirmed: .office,
                disposition: .corrected,
                correctedAt: date
            )
        )
        assertEqual(
            mutate(.correction(.purposeCorrection), afterContext: after).generation,
            generation(record: 3, context: 6)
        )
    }

    func testCE2R1R13PurposeRejectionUsesTypedMutation() {
        let after = context(
            purpose: purpose(
                proposed: .factoryManufacturing,
                rejected: [.factoryManufacturing],
                disposition: .rejected
            )
        )
        assertEqual(
            mutate(.correction(.purposeRejection), afterContext: after).generation,
            generation(record: 3, context: 6)
        )
    }

    func testCE2R1R14PurposeReversalRestoresInferredState() {
        let before = context(
            purpose: purpose(confirmed: .office, disposition: .confirmed)
        )
        let after = context(
            purpose: purpose(
                proposed: .factoryManufacturing,
                disposition: .inferred
            )
        )
        assertEqual(
            mutate(
                .correction(.purposeReversal),
                beforeContext: before,
                afterContext: after
            ).generation,
            generation(record: 3, context: 6)
        )
    }

    func testCE2R1R15WorkplaceConfirmationUsesTypedMutation() {
        let after = context(
            workplace: workplace(
                confirmed: .factoryManufacturing,
                disposition: .confirmed
            )
        )
        assertEqual(
            mutate(.correction(.workplaceConfirmation), afterContext: after).generation,
            generation(record: 3, context: 6)
        )
    }

    func testCE2R1R16WorkplaceCorrectionUsesTypedMutation() {
        let after = context(
            workplace: workplace(
                proposed: .warehouse,
                confirmed: .office,
                disposition: .corrected,
                correctedAt: date
            )
        )
        assertEqual(
            mutate(.correction(.workplaceCorrection), afterContext: after).generation,
            generation(record: 3, context: 6)
        )
    }

    func testCE2R1R17WorkplaceClearingUsesTypedMutation() {
        let before = context(
            workplace: workplace(confirmed: .office, disposition: .confirmed)
        )
        let after = context(
            workplace: workplace(
                proposed: .office,
                rejected: [.office],
                disposition: .cleared
            )
        )
        assertEqual(
            mutate(
                .correction(.workplaceRejectionOrClearing),
                beforeContext: before,
                afterContext: after
            ).generation,
            generation(record: 3, context: 6)
        )
    }

    func testCE2R1R18RepeatedCorrectionIsIdempotent() {
        let corrected = context(
            purpose: purpose(confirmed: .office, disposition: .corrected)
        )
        assertEqual(
            mutate(
                .correction(.purposeCorrection),
                beforeContext: corrected,
                afterContext: corrected,
                storedRecordChanged: false
            ).generation,
            generation()
        )
    }

    func testCE2R1R19StalePreMutationIdentityFailsClosed() {
        let before = fingerprintInput()
        let current = identity(
            "a",
            generation: before.generation,
            fingerprint: resolvedFingerprint(before)
        )
        let stale = identity(
            "a",
            generation: generation(record: 1, context: 1),
            fingerprint: "stale"
        )
        let request = mutationRequest(
            current: current,
            before: before,
            after: before,
            storedRecordChanged: true,
            mutation: .titleOnly,
            expectedIdentity: stale
        )
        assertEqual(
            resultFailure(
                ScanGenerationPolicy.apply(current: current, request: request)
            ),
            .generationMismatch
        )
    }

    func testCE2R1R20RejectedPurposeRemainsBoundToSameScan() async throws {
        let bound = context(
            purpose: purpose(
                proposed: .factoryManufacturing,
                rejected: [.factoryManufacturing],
                disposition: .rejected
            )
        )
        let authority = try await resolve(
            .latestValidCompleted,
            records: ["a": record(context: bound)]
        )
        let value = try input(authority)
        assertEqual(value.scanID, "a")
        assertEqual(value.rejectedPurposeIDs, [.factoryManufacturing])
        XCTAssertNil(value.confirmedPurpose)
    }

    func testCE2R1R21DetectedStyleRemainsSeparateAfterCorrection() async throws {
        let bound = context(
            purpose: purpose(confirmed: .office, disposition: .corrected)
        )
        let authority = try await resolve(
            .latestValidCompleted,
            records: ["a": record(context: bound)]
        )
        assertEqual(authority.analysis.styleBalance, "Casual")
        assertEqual(try input(authority).detectedStyle, "Casual")
        assertEqual(try input(authority).confirmedPurpose?.purpose, .office)
    }

    func testCE2R1R22OtherUncertainCorrectionRemainsUncertain() {
        let after = context(
            purpose: purpose(
                proposed: .otherUncertain,
                disposition: .uncertain
            )
        )
        XCTAssertNotEqual(
            mutate(
                .correction(.restorationToInferredOrUncertain),
                afterContext: after
            ).generation.contextRevision,
            generation().contextRevision
        )
    }

    func testCE2R1R23FingerprintChangesForConfirmedPurpose() {
        let confirmed = context(
            purpose: purpose(confirmed: .office, disposition: .confirmed)
        )
        XCTAssertNotEqual(fingerprint(), fingerprint(context: confirmed))
    }

    func testCE2R1R24FingerprintChangesForRejectedPurpose() {
        let rejected = context(
            purpose: purpose(
                rejected: [.factoryManufacturing],
                disposition: .rejected
            )
        )
        XCTAssertNotEqual(fingerprint(), fingerprint(context: rejected))
    }

    func testCE2R1R25FingerprintChangesForWorkplaceCorrection() {
        let corrected = context(
            workplace: workplace(confirmed: .office, disposition: .corrected)
        )
        XCTAssertNotEqual(fingerprint(), fingerprint(context: corrected))
    }

    func testCE2R1R26FingerprintChangesForInputSchemaVersion() {
        XCTAssertNotEqual(
            fingerprint(),
            fingerprint(context: context(inputSchemaVersion: 2))
        )
    }

    func testCE2R1R27FingerprintChangesForNormalizedConfidence() {
        XCTAssertNotEqual(
            fingerprint(analysis: analysis(confidence: 0.9)),
            fingerprint(analysis: analysis(confidence: 0.91))
        )
    }

    func testCE2R1R28EquivalentNormalizedInputsPreserveFingerprint() {
        assertEqual(
            fingerprint(
                analysis: analysis(
                    evidence: [.branding, .silhouette],
                    style: " Casual ",
                    confidence: 0.9
                )
            ),
            fingerprint(
                analysis: analysis(
                    evidence: [.silhouette, .branding],
                    style: "casual",
                    confidence: 0.9000000001
                )
            )
        )
    }

    func testCE2R1R29FactorySignatureHasNoExternalScanOverrides() throws {
        let value = try source("ContextInferenceInputFactory.swift")
        let signature = try XCTUnwrap(
            value.range(of: "static func make")?.lowerBound
        )
        let body = try XCTUnwrap(value.range(of: ") ->", range: signature..<value.endIndex))
        let declaration = String(value[signature..<body.upperBound])
        assertEqual(
            declaration,
            "static func make(\n        authority: ScanAuthority\n    ) ->"
        )
    }

    func testCE2R1R30FactoryCopiesExactAuthorityIdentity() async throws {
        let authority = try await resolve(.latestValidCompleted, records: ["a": record()])
        let value = try input(authority)
        assertEqual(value.scanID, authority.identity.localID.rawValue)
        assertEqual(value.recordRevision, authority.identity.generation.recordRevision)
        assertEqual(value.contextGeneration, authority.identity.generation.contextRevision)
        assertEqual(value.contextFingerprint, authority.identity.contextFingerprint)
    }

    func testCE2R1R31FactoryUsesAuthorityWeatherWithoutSecondRead() async throws {
        let weather = WeatherContextReference(
            observedAt: date,
            airTemperature: 82,
            feelsLikeTemperature: 86,
            humidityPercent: 76,
            rainChancePercent: 10,
            windMph: 4,
            uvIndex: 7,
            condition: "Clear",
            confidence: ContextConfidence(value: 0.9, level: .high)
        )
        let source = FakeSource(data: try data([
            "a": record(context: context(weather: weather))
        ]))
        let authority = try await authority(repository: .init(source: source))
        assertEqual(try input(authority).weather, weather)
        assertEqual(await source.captureCount, 1)
        assertEqual(await source.boundaryCount, 1)
    }

    func testCE2R1R32FingerprintExcludesRawOCRAndPrivateIdentity() throws {
        let sourceValue = try source("ScanGenerationPolicy.swift")
        XCTAssertFalse(sourceValue.contains("detectedText"))
        XCTAssertFalse(sourceValue.contains("detectedBranding"))
        XCTAssertFalse(sourceValue.contains("employer"))
        XCTAssertFalse(sourceValue.contains("personName"))
    }

    func testCE2R1R33FingerprintChangesForWeatherContext() {
        let weather = WeatherContextReference(
            observedAt: date,
            airTemperature: 82,
            feelsLikeTemperature: 86,
            humidityPercent: 76,
            rainChancePercent: nil,
            windMph: nil,
            uvIndex: nil,
            condition: "Clear",
            confidence: ContextConfidence(value: 0.9, level: .high)
        )
        XCTAssertNotEqual(
            fingerprint(),
            fingerprint(context: context(weather: weather))
        )
    }

    func testCE2R1R34CorrectionTimestampUsesFixedDeterministicEncoding() {
        let first = context(
            purpose: purpose(
                confirmed: .office,
                disposition: .corrected,
                correctedAt: Date(timeIntervalSince1970: 100.0000001)
            )
        )
        let second = context(
            purpose: purpose(
                confirmed: .office,
                disposition: .corrected,
                correctedAt: Date(timeIntervalSince1970: 100.0000002)
            )
        )
        assertEqual(fingerprint(context: first), fingerprint(context: second))
    }

    func testCE2R1R35NoPersistenceOrConsumerDependencyIntroduced() throws {
        let joined = try scanAuthoritySources().joined(separator: "\n")
        for token in [
            "UserDefaults.standard.set", "URLRequest", "StylistChat",
            "AIAssist", "VoiceAssistant", "ShoppingView"
        ] {
            XCTAssertFalse(joined.contains(token))
        }
    }

    func testCE2R1R36RejectedPurposeCannotReappearConfirmed() {
        let before = fingerprintInput()
        let after = fingerprintInput(context: context(
            purpose: purpose(
                confirmed: .office,
                rejected: [.office],
                disposition: .confirmed
            )
        ))
        let current = identity(
            "a",
            generation: before.generation,
            fingerprint: resolvedFingerprint(before)
        )
        let request = mutationRequest(
            current: current,
            before: before,
            after: after,
            storedRecordChanged: true,
            mutation: .correction(.purposeConfirmation)
        )
        assertEqual(
            resultFailure(
                ScanGenerationPolicy.apply(current: current, request: request)
            ),
            .generationMismatch
        )
    }

    func testCE2R1R37OtherUncertainCannotBecomeConfirmedPurpose() {
        let before = fingerprintInput()
        let after = fingerprintInput(context: context(
            purpose: purpose(
                confirmed: .otherUncertain,
                disposition: .confirmed
            )
        ))
        let current = identity(
            "a",
            generation: before.generation,
            fingerprint: resolvedFingerprint(before)
        )
        let request = mutationRequest(
            current: current,
            before: before,
            after: after,
            storedRecordChanged: true,
            mutation: .correction(.purposeConfirmation)
        )
        assertEqual(
            resultFailure(
                ScanGenerationPolicy.apply(current: current, request: request)
            ),
            .generationMismatch
        )
    }

    func testCE2R1R38FutureContextInputSchemaFailsClosed() async throws {
        let future = context(inputSchemaVersion: 2)
        assertEqual(
            await failure(
                .latestValidCompleted,
                records: ["a": record(context: future)]
            ),
            .unsupportedSchema
        )
    }

    func testCE2R1R39StoredRejectedPurposeCannotAlsoBeConfirmed() async throws {
        let invalid = context(
            purpose: purpose(
                confirmed: .factoryManufacturing,
                rejected: [.factoryManufacturing],
                disposition: .confirmed
            )
        )
        assertEqual(
            await failure(records: ["a": record(context: invalid)]),
            .scanCorrupt
        )
    }

    func testCE2R1R40StoredUncertainPurposeCannotCarryConfirmation() async throws {
        let invalid = context(
            purpose: purpose(
                confirmed: .office,
                disposition: .uncertain
            )
        )
        assertEqual(
            await failure(records: ["a": record(context: invalid)]),
            .scanCorrupt
        )
    }

    func testCE2R1R41StoredRejectedWorkplaceRequiresRejectionEvidence() async throws {
        let invalid = context(
            workplace: workplace(disposition: .rejected)
        )
        assertEqual(
            await failure(records: ["a": record(context: invalid)]),
            .scanCorrupt
        )
    }

    func testCE2R1R42MutationWithFutureContextSchemaFailsClosed() {
        let before = fingerprintInput()
        let current = identity(
            "a",
            generation: before.generation,
            fingerprint: resolvedFingerprint(before)
        )
        let after = fingerprintInput(
            context: context(
                inputSchemaVersion: ScanBoundContext.currentInputSchemaVersion + 1
            )
        )
        let request = mutationRequest(
            current: current,
            before: before,
            after: after,
            storedRecordChanged: true,
            mutation: .analysisEnrichment
        )
        assertEqual(
            resultFailure(
                ScanGenerationPolicy.apply(current: current, request: request)
            ),
            .generationMismatch
        )
    }

    func testCE2R1R2Score01MissingStoredScorePublishesNoAuthority() async {
        assertEqual(
            await failure(records: ["a": record(score: nil)]),
            .missingStoredScore
        )
    }

    func testCE2R1R2Score02MissingAnalysisPublishesNoAuthority() async {
        assertEqual(
            await failure(
                .explicitHistorical(id: id("a"), expected: nil),
                records: ["a": record(includeAnalysis: false)]
            ),
            .scanPartial
        )
    }

    func testCE2R1R2Score03StoredScoreBelowZeroFailsClosed() async {
        assertEqual(
            await failure(records: ["a": record(score: -1)]),
            .invalidStoredScore
        )
    }

    func testCE2R1R2Score04AnalysisScoreBelowZeroFailsClosed() async {
        assertEqual(
            await failure(records: [
                "a": record(score: 0, analysisOverride: analysis(score: -1))
            ]),
            .invalidAnalysisScore
        )
    }

    func testCE2R1R2Score05StoredScoreAboveOneHundredFailsClosed() async {
        assertEqual(
            await failure(records: ["a": record(score: 101)]),
            .invalidStoredScore
        )
    }

    func testCE2R1R2Score06AnalysisScoreAboveOneHundredFailsClosed() async {
        assertEqual(
            await failure(records: [
                "a": record(score: 100, analysisOverride: analysis(score: 101))
            ]),
            .invalidAnalysisScore
        )
    }

    func testCE2R1R2Score07MatchingScoresBelowZeroFailClosed() async {
        assertEqual(
            await failure(records: [
                "a": record(score: -1, analysisOverride: analysis(score: -1))
            ]),
            .invalidStoredScore
        )
    }

    func testCE2R1R2Score08MatchingScoresAboveOneHundredFailClosed() async {
        assertEqual(
            await failure(records: [
                "a": record(score: 101, analysisOverride: analysis(score: 101))
            ]),
            .invalidStoredScore
        )
    }

    func testCE2R1R2Score09ValidMismatchFailsClosed() async {
        assertEqual(
            await failure(records: [
                "a": record(score: 74, analysisOverride: analysis(score: 80))
            ]),
            .scoreMismatch
        )
    }

    func testCE2R1R2Score10ZeroBoundaryIsAuthoritative() async throws {
        let value = try await resolve(
            .latestValidCompleted,
            records: ["a": record(score: 0, analysisOverride: analysis(score: 0))]
        )
        assertEqual(value.analysis.score, 0)
    }

    func testCE2R1R2Score11OneHundredBoundaryIsAuthoritative() async throws {
        let value = try await resolve(
            .latestValidCompleted,
            records: [
                "a": record(score: 100, analysisOverride: analysis(score: 100))
            ]
        )
        assertEqual(value.analysis.score, 100)
    }

    func testCE2R1R2Score12InteriorScoreIsAuthoritative() async throws {
        let value = try await resolve(
            .latestValidCompleted,
            records: ["a": record(score: 80)]
        )
        assertEqual(value.analysis.score, 80)
    }

    func testCE2R1R2Score13MalformedNumericScoreCannotDecodeAsAuthority() async throws {
        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(
                with: data(["a": record()])
            ) as? [String: Any]
        )
        var root = object
        var malformed = try XCTUnwrap(root["a"] as? [String: Any])
        malformed["score"] = "eighty"
        root["a"] = malformed
        let source = FakeSource(
            data: try JSONSerialization.data(withJSONObject: root)
        )
        assertEqual(
            await failure(
                .explicitHistorical(id: id("a"), expected: nil),
                repository: ScanAuthorityRepository(source: source)
            ),
            .scanCorrupt
        )
    }

    func testCE2R1R2Score14InvalidScoreNeverReachesCE2A() async {
        let result = await ScanAuthorityRepository(
            source: FakeSource(
                data: try? data([
                    "a": record(
                        score: 101,
                        analysisOverride: analysis(score: 101)
                    )
                ])
            )
        ).resolve(.latestValidCompleted)
        if case .authority = result {
            XCTFail("Invalid score published partial authority")
        }
        assertEqual(resultFailure(result), .invalidStoredScore)
    }

    func testCE2R1R2Correction01SamePurposeConfirmationIsIdempotent() {
        assertRepeatedCorrectionIsIdempotent(
            mutation: .purposeConfirmation,
            before: context(purpose: purpose(
                confirmed: .office,
                disposition: .confirmed,
                correctedAt: date
            )),
            after: context(purpose: purpose(
                confirmed: .office,
                disposition: .confirmed,
                correctedAt: date.addingTimeInterval(60)
            ))
        )
    }

    func testCE2R1R2Correction02SamePurposeCorrectionIsIdempotent() {
        assertRepeatedCorrectionIsIdempotent(
            mutation: .purposeCorrection,
            before: context(purpose: purpose(
                confirmed: .office,
                disposition: .corrected,
                correctedAt: date
            )),
            after: context(purpose: purpose(
                confirmed: .office,
                disposition: .corrected,
                correctedAt: date.addingTimeInterval(60)
            ))
        )
    }

    func testCE2R1R2Correction03SamePurposeRejectionIsIdempotent() {
        assertRepeatedCorrectionIsIdempotent(
            mutation: .purposeRejection,
            before: context(purpose: purpose(
                proposed: .office,
                rejected: [.office],
                disposition: .rejected,
                correctedAt: date
            )),
            after: context(purpose: purpose(
                proposed: .office,
                rejected: [.office],
                disposition: .rejected,
                correctedAt: date.addingTimeInterval(60)
            ))
        )
    }

    func testCE2R1R2Correction04SameWorkplaceConfirmationIsIdempotent() {
        assertRepeatedCorrectionIsIdempotent(
            mutation: .workplaceConfirmation,
            before: context(workplace: workplace(
                confirmed: .office,
                disposition: .confirmed,
                correctedAt: date
            )),
            after: context(workplace: workplace(
                confirmed: .office,
                disposition: .confirmed,
                correctedAt: date.addingTimeInterval(60)
            ))
        )
    }

    func testCE2R1R2Correction05SameWorkplaceCorrectionIsIdempotent() {
        assertRepeatedCorrectionIsIdempotent(
            mutation: .workplaceCorrection,
            before: context(workplace: workplace(
                confirmed: .office,
                disposition: .corrected,
                correctedAt: date
            )),
            after: context(workplace: workplace(
                confirmed: .office,
                disposition: .corrected,
                correctedAt: date.addingTimeInterval(60)
            ))
        )
    }

    func testCE2R1R2Correction06SameWorkplaceClearingIsIdempotent() {
        assertRepeatedCorrectionIsIdempotent(
            mutation: .workplaceRejectionOrClearing,
            before: context(workplace: workplace(
                proposed: .office,
                rejected: [.office],
                disposition: .cleared,
                correctedAt: date
            )),
            after: context(workplace: workplace(
                proposed: .office,
                rejected: [.office],
                disposition: .cleared,
                correctedAt: date.addingTimeInterval(60)
            ))
        )
    }

    func testCE2R1R2Correction07SameCategoryCorrectionIsIdempotent() {
        assertRepeatedCorrectionIsIdempotent(
            mutation: .categoryCorrection,
            before: context(categoryDisposition: .corrected),
            after: context(categoryDisposition: .corrected)
        )
    }

    func testCE2R1R2Correction08SameOccasionCorrectionIsIdempotent() {
        assertRepeatedCorrectionIsIdempotent(
            mutation: .occasionCorrection,
            before: context(occasionDisposition: .corrected),
            after: context(occasionDisposition: .corrected)
        )
    }

    func testCE2R1R2Correction09NormalizedFormattingIsIdempotent() {
        let corrected = context(
            purpose: purpose(confirmed: .office, disposition: .corrected)
        )
        let value = mutate(
            .correction(.purposeCorrection),
            beforeContext: corrected,
            afterContext: corrected,
            beforeAnalysis: analysis(style: "  Casual  "),
            afterAnalysis: analysis(style: "casual"),
            storedRecordChanged: true
        )
        assertEqual(value.generation, generation())
    }

    func testCE2R1R2Correction10DifferentPurposeChangesAuthority() {
        let before = context(
            purpose: purpose(confirmed: .office, disposition: .corrected)
        )
        let after = context(
            purpose: purpose(
                confirmed: .factoryManufacturing,
                disposition: .corrected
            )
        )
        let value = mutate(
            .correction(.purposeCorrection),
            beforeContext: before,
            afterContext: after
        )
        assertEqual(value.generation, generation(record: 3, context: 6))
        XCTAssertNotEqual(
            fingerprint(context: before),
            fingerprint(context: after)
        )
    }

    func testCE2R1R2Correction11DifferentWorkplaceChangesAuthority() {
        let before = context(
            workplace: workplace(confirmed: .office, disposition: .corrected)
        )
        let after = context(
            workplace: workplace(
                confirmed: .factoryManufacturing,
                disposition: .corrected
            )
        )
        let value = mutate(
            .correction(.workplaceCorrection),
            beforeContext: before,
            afterContext: after
        )
        assertEqual(value.generation, generation(record: 3, context: 6))
    }

    func testCE2R1R2Correction12ReversalChangesThenRepeatsIdempotently() {
        let corrected = context(
            purpose: purpose(confirmed: .office, disposition: .corrected)
        )
        let reversed = context(
            purpose: purpose(disposition: .inferred, correctedAt: date)
        )
        let changed = mutate(
            .correction(.purposeReversal),
            beforeContext: corrected,
            afterContext: reversed
        )
        assertEqual(changed.generation, generation(record: 3, context: 6))
        assertRepeatedCorrectionIsIdempotent(
            mutation: .purposeReversal,
            before: reversed,
            after: context(purpose: purpose(
                disposition: .inferred,
                correctedAt: date.addingTimeInterval(60)
            ))
        )
    }

    func testCE2R1R3Workplace01ConfirmedReversalChangesGenerationAndFingerprint() throws {
        let before = context(workplace: workplace(
            proposed: .factoryManufacturing,
            confirmed: .office,
            disposition: .confirmed,
            correctedAt: date
        ))
        let after = context(workplace: workplace(
            proposed: .factoryManufacturing,
            disposition: .inferred,
            correctedAt: date.addingTimeInterval(60)
        ))
        let value = try workplaceReversalResult(before: before, after: after).get()

        assertEqual(value.generation, generation(record: 3, context: 6))
        XCTAssertNotEqual(value.contextFingerprint, fingerprint(context: before))
        assertEqual(
            value.contextFingerprint,
            fingerprint(
                generation: value.generation,
                context: after,
                ordinal: 1
            )
        )
    }

    func testCE2R1R3Workplace02CorrectedReversalReturnsToUncertain() throws {
        let before = context(workplace: workplace(
            proposed: .warehouse,
            confirmed: .office,
            disposition: .corrected
        ))
        let after = context(workplace: workplace(
            proposed: .warehouse,
            disposition: .uncertain
        ))
        let value = try workplaceReversalResult(before: before, after: after).get()

        assertEqual(value.generation, generation(record: 3, context: 6))
        XCTAssertNotEqual(value.contextFingerprint, fingerprint(context: before))
    }

    func testCE2R1R3Workplace03RepeatedReversalIgnoresLaterAuditTimestamp() {
        let reversed = context(workplace: workplace(
            proposed: .warehouse,
            rejected: [.office],
            disposition: .inferred,
            correctedAt: date
        ))
        assertRepeatedCorrectionIsIdempotent(
            mutation: .workplaceReversal,
            before: reversed,
            after: context(workplace: workplace(
                proposed: .warehouse,
                rejected: [.office],
                disposition: .inferred,
                correctedAt: date.addingTimeInterval(60)
            ))
        )
    }

    func testCE2R1R3Workplace04AlreadyUncertainReversalIsIdempotent() {
        let uncertain = context(workplace: workplace(
            proposed: .warehouse,
            rejected: [.office],
            disposition: .uncertain,
            correctedAt: date
        ))
        assertRepeatedCorrectionIsIdempotent(
            mutation: .workplaceReversal,
            before: uncertain,
            after: uncertain
        )
    }

    func testCE2R1R3Workplace05StaleIdentityGenerationAndFingerprintFailClosed() {
        let before = context(workplace: workplace(
            confirmed: .office,
            disposition: .confirmed
        ))
        let after = context(workplace: workplace(disposition: .inferred))
        let staleIdentities = [
            identity(
                "b",
                generation: generation(),
                fingerprint: fingerprint(context: before)
            ),
            identity(
                "a",
                generation: generation(record: 1, context: 1),
                fingerprint: fingerprint(context: before)
            ),
            identity(
                "a",
                generation: generation(),
                fingerprint: "stale-fingerprint"
            )
        ]

        for stale in staleIdentities {
            assertEqual(
                resultFailure(workplaceReversalResult(
                    before: before,
                    after: after,
                    expectedIdentity: stale
                )),
                .generationMismatch
            )
        }
    }

    func testCE2R1R3Workplace06WrongScanFailsClosed() {
        let before = context(workplace: workplace(
            confirmed: .office,
            disposition: .confirmed
        ))
        let after = context(workplace: workplace(disposition: .inferred))

        assertEqual(
            resultFailure(workplaceReversalResult(
                before: before,
                after: after,
                afterID: "b"
            )),
            .generationMismatch
        )
    }

    func testCE2R1R3Workplace07InvalidLifecycleStatesFailClosed() {
        let before = context(workplace: workplace(
            confirmed: .office,
            disposition: .confirmed
        ))
        let after = context(workplace: workplace(disposition: .inferred))
        for state in [
            ScanAuthorityState.deleted,
            .quarantined,
            .failed,
            .corrupt,
            .partial,
            .inProgress
        ] {
            assertEqual(
                resultFailure(workplaceReversalResult(
                    before: before,
                    after: after,
                    authorityState: state
                )),
                .generationMismatch
            )
        }
        let alreadyReversed = context(
            workplace: workplace(disposition: .inferred)
        )
        assertEqual(
            resultFailure(workplaceReversalResult(
                before: alreadyReversed,
                after: alreadyReversed,
                authorityState: .deleted
            )),
            .generationMismatch
        )
    }

    func testCE2R1R3Workplace08ReversalPreservesRejectionsAndUnrelatedContext() async throws {
        let purposeValue = purpose(
            confirmed: .factoryManufacturing,
            rejected: [.warehouse],
            disposition: .corrected
        )
        let before = context(
            purpose: purposeValue,
            workplace: workplace(
                proposed: .factoryManufacturing,
                confirmed: .office,
                rejected: [.factoryManufacturing],
                disposition: .corrected,
                correctedAt: date
            ),
            categoryDisposition: .corrected,
            occasionDisposition: .confirmed
        )
        let after = context(
            purpose: purposeValue,
            workplace: workplace(
                proposed: .factoryManufacturing,
                rejected: [.factoryManufacturing],
                disposition: .inferred,
                correctedAt: date.addingTimeInterval(60)
            ),
            categoryDisposition: .corrected,
            occasionDisposition: .confirmed
        )
        let identity = try workplaceReversalResult(
            before: before,
            after: after
        ).get()
        let source = FakeSource(data: try data([
            "a": record(
                metadata: metadata(
                    generation: identity.generation,
                    context: after
                ),
                context: after
            )
        ]))
        let authority = try await authority(
            repository: ScanAuthorityRepository(source: source)
        )
        let value = try input(authority)

        assertEqual(value.scanID, identity.localID.rawValue)
        assertEqual(value.contextGeneration, identity.generation.contextRevision)
        assertEqual(value.contextFingerprint, identity.contextFingerprint)
        assertEqual(value.score, 80)
        assertEqual(value.scoreBreakdown, analysis().scoreBreakdown)
        assertEqual(value.detectedStyle, "Casual")
        assertEqual(value.garmentCategory, .workUniform)
        assertEqual(value.selectedOccasion, .work)
        assertEqual(value.confirmedPurpose?.purpose, .factoryManufacturing)
        XCTAssertNil(value.confirmedWorkplaceProfile)
        assertEqual(
            value.rejectedWorkplaceProfileIDs,
            [.factoryManufacturing]
        )
        assertEqual(await source.captureCount, 1)
        assertEqual(await source.boundaryCount, 1)
        assertEqual(await source.writeCount, 0)
    }

    func testCE2R1R3Workplace09RejectedProfileCannotReappearThroughInference() async throws {
        let bound = context(
            purpose: purpose(
                confirmed: .factoryManufacturing,
                disposition: .confirmed
            ),
            workplace: workplace(
                proposed: .factoryManufacturing,
                rejected: [.factoryManufacturing],
                disposition: .inferred
            )
        )
        let authority = try await resolve(
            .latestValidCompleted,
            records: ["a": record(context: bound)]
        )
        let value = try input(authority)
        let snapshot = try infer(value)

        assertEqual(
            value.rejectedWorkplaceProfileIDs,
            [.factoryManufacturing]
        )
        assertEqual(snapshot.workplaceProfile.value, .otherUncertain)
        assertEqual(snapshot.workplaceProfile.confirmationState, .uncertain)
    }

    func testCE2R1R3Workplace10ReversalRejectsUnrelatedContextChanges() {
        let before = context(
            purpose: purpose(confirmed: .office, disposition: .confirmed),
            workplace: workplace(
                confirmed: .office,
                disposition: .confirmed
            ),
            categoryDisposition: .corrected,
            occasionDisposition: .confirmed
        )
        let changedPurpose = context(
            purpose: purpose(
                confirmed: .factoryManufacturing,
                disposition: .confirmed
            ),
            workplace: workplace(disposition: .inferred),
            categoryDisposition: .corrected,
            occasionDisposition: .confirmed
        )
        let changedAnalysis = analysis(style: "Formal")

        assertEqual(
            resultFailure(workplaceReversalResult(
                before: before,
                after: changedPurpose
            )),
            .generationMismatch
        )
        assertEqual(
            resultFailure(workplaceReversalResult(
                before: before,
                after: context(
                    purpose: before.purpose,
                    workplace: workplace(disposition: .inferred),
                    categoryDisposition: .corrected,
                    occasionDisposition: .confirmed
                ),
                afterAnalysis: changedAnalysis
            )),
            .generationMismatch
        )
    }

    func testCE2R1R3Workplace11ReversalCannotRemoveRejectionConstraints() {
        let before = context(workplace: workplace(
            proposed: .factoryManufacturing,
            confirmed: .office,
            rejected: [.factoryManufacturing],
            disposition: .confirmed
        ))
        let after = context(workplace: workplace(
            proposed: .factoryManufacturing,
            disposition: .inferred
        ))

        assertEqual(
            resultFailure(workplaceReversalResult(
                before: before,
                after: after
            )),
            .generationMismatch
        )
    }

    func testCE2R1R3Workplace12ClearingAndGenericRestorationStayDistinct() {
        let before = context(workplace: workplace(
            confirmed: .office,
            disposition: .confirmed
        ))
        let reversed = context(workplace: workplace(disposition: .inferred))
        let cleared = context(workplace: workplace(
            rejected: [.office],
            disposition: .cleared
        ))

        assertEqual(
            resultFailure(ScanGenerationPolicy.apply(
                current: currentIdentity(context: before),
                request: mutationRequest(
                    current: currentIdentity(context: before),
                    before: fingerprintInput(context: before),
                    after: fingerprintInput(context: reversed),
                    storedRecordChanged: true,
                    mutation: .correction(.restorationToInferredOrUncertain)
                )
            )),
            .generationMismatch
        )
        assertEqual(
            resultFailure(workplaceReversalResult(
                before: before,
                after: cleared
            )),
            .generationMismatch
        )
        XCTAssertNoThrow(try ScanGenerationPolicy.apply(
            current: currentIdentity(context: before),
            request: mutationRequest(
                current: currentIdentity(context: before),
                before: fingerprintInput(context: before),
                after: fingerprintInput(context: cleared),
                storedRecordChanged: true,
                mutation: .correction(.workplaceRejectionOrClearing)
            )
        ).get())
    }

    func testCE2R1R3Workplace13PurposeReversalRemainsUnaffected() {
        let before = context(purpose: purpose(
            confirmed: .office,
            disposition: .confirmed
        ))
        let after = context(purpose: purpose(disposition: .inferred))
        let value = mutate(
            .correction(.purposeReversal),
            beforeContext: before,
            afterContext: after
        )

        assertEqual(value.generation, generation(record: 3, context: 6))
    }

    func testCE2R1R3Workplace14ExplicitMutationIsBehaviorInactiveAndLocalOnly() throws {
        let policy = try source("ScanGenerationPolicy.swift")
        XCTAssertTrue(policy.contains("case workplaceReversal"))
        XCTAssertFalse(policy.contains("URLRequest"))
        XCTAssertFalse(policy.contains("RemoteSafeScanReference"))
        let joined = try scanAuthoritySources().joined(separator: "\n")
        for token in [
            "UserDefaults.standard.set", "StylistChat", "AIAssist",
            "VoiceAssistant", "ShoppingView", "Worker"
        ] {
            XCTAssertFalse(joined.contains(token))
        }
    }

    func testCE2R1C101LegacyWorkBeatsConflictingDateNightProse() {
        let original = analysis(score: 80, occasionFit: "Date Night")
        let originalOccasionFit = original.occasionFit
        let originalScore = original.score
        let originalTitle = "Custom Work Attire"
        let projection = RecentHistoryEffectiveOccasionResolver.resolve(
            authority: nil,
            legacyCanonicalOccasion: .work
        )
        assertEqual(projection?.occasion, .work)
        assertEqual(
            RecentHistoryEffectiveOccasionResolver.compactDescriptor(
                legacyDescriptor: "Date Night",
                detectedStyle: "Casual",
                effectiveOccasion: projection
            ),
            "Casual"
        )
        assertEqual(original.occasionFit, originalOccasionFit)
        assertEqual(original.score, originalScore)
        assertEqual(originalTitle, "Custom Work Attire")
    }

    func testCE2R1C102AcceptedAuthorityBeatsLegacyOccasion() async throws {
        let before = context(workplace: workplace(
            proposed: .factoryManufacturing,
            confirmed: .office,
            disposition: .corrected,
            correctedAt: date
        ))
        let after = context(workplace: workplace(
            proposed: .factoryManufacturing,
            disposition: .inferred,
            correctedAt: date.addingTimeInterval(60)
        ))
        let reversedIdentity = try workplaceReversalResult(
            before: before,
            after: after
        ).get()
        let authority = try await resolve(
            .latestValidCompleted,
            records: ["a": record(
                analysisOverride: analysis(occasionFit: "Date Night"),
                metadata: metadata(
                    generation: reversedIdentity.generation,
                    context: after,
                    analysis: analysis(occasionFit: "Date Night")
                ),
                context: after
            )]
        )
        let projection = RecentHistoryEffectiveOccasionResolver.resolve(
            authority: authority,
            legacyCanonicalOccasion: .dateNight
        )
        assertEqual(projection?.occasion, .work)
        assertEqual(projection?.source, .ce2r1(authority.identity))
        assertEqual(authority.identity, reversedIdentity)
        assertEqual(authority.scanBoundContext.workplace.disposition, .inferred)
    }

    func testCE2R1C103RepeatedResolutionIsIdempotent() async throws {
        let authority = try await resolve(
            .latestValidCompleted,
            records: ["a": record()]
        )
        let first = RecentHistoryEffectiveOccasionResolver.resolve(
            authority: authority,
            legacyCanonicalOccasion: .dateNight
        )
        let second = RecentHistoryEffectiveOccasionResolver.resolve(
            authority: authority,
            legacyCanonicalOccasion: .dateNight
        )
        assertEqual(first, second)
    }

    func testCE2R1C104InvalidAuthorityDoesNotFallbackToWork() {
        let rejectedWorkplace = workplace(
            proposed: .factoryManufacturing,
            rejected: [.factoryManufacturing],
            disposition: .rejected,
            correctedAt: date
        )
        let invalid = ScanAuthority(
            identity: identity(
                "a",
                generation: .legacy,
                fingerprint: "invalid"
            ),
            analysis: analysis(),
            completedAt: date,
            completionOrdinal: 1,
            selectedOccasion: .work,
            state: .quarantined,
            reason: .latestValidCompleted,
            legacyState: .versioned,
            imageReferenceState: .absent,
            scanBoundContext: context(workplace: rejectedWorkplace),
            invalidationEpoch: .init(value: 0)
        )
        XCTAssertNil(
            RecentHistoryEffectiveOccasionResolver.resolve(
                authority: invalid,
                legacyCanonicalOccasion: .work
            )
        )
        assertEqual(
            invalid.scanBoundContext.workplace.rejected,
            [.factoryManufacturing]
        )
        XCTAssertNil(invalid.scanBoundContext.workplace.confirmed)
    }

    func testCE2R1C105LegacyRecordWithoutCanonicalOccasionDoesNotInferDateNight() {
        let projection = RecentHistoryEffectiveOccasionResolver.resolve(
            authority: nil,
            legacyCanonicalOccasion: nil
        )
        XCTAssertNil(projection)
        assertEqual(
            RecentHistoryEffectiveOccasionResolver.compactDescriptor(
                legacyDescriptor: "Date Night",
                detectedStyle: "Casual",
                effectiveOccasion: projection
            ),
            "Casual"
        )
    }

    func testCE2R1C106DetectedStyleRemainsSeparateFromEffectiveOccasion() async throws {
        let authority = try await resolve(
            .latestValidCompleted,
            records: ["a": record()]
        )
        let projection = RecentHistoryEffectiveOccasionResolver.resolve(
            authority: authority,
            legacyCanonicalOccasion: nil
        )
        assertEqual(authority.analysis.styleBalance, "Casual")
        assertEqual(projection?.occasion, .work)
        assertEqual(
            RecentHistoryEffectiveOccasionResolver.compactDescriptor(
                legacyDescriptor: "Date Night",
                detectedStyle: authority.analysis.styleBalance,
                effectiveOccasion: projection
            ),
            "Casual"
        )
    }

    func testCE2R1C107ProjectionDoesNotMutateUnrelatedScanFields() async throws {
        let authority = try await resolve(
            .latestValidCompleted,
            records: ["a": record(score: 80)]
        )
        let beforeScore = authority.analysis.score
        let beforeStyle = authority.analysis.styleBalance
        let beforeSummary = authority.analysis.summary
        _ = RecentHistoryEffectiveOccasionResolver.resolve(
            authority: authority,
            legacyCanonicalOccasion: .dateNight
        )
        assertEqual(authority.analysis.score, beforeScore)
        assertEqual(authority.analysis.styleBalance, beforeStyle)
        assertEqual(authority.analysis.summary, beforeSummary)
        assertEqual(beforeScore, 80)
        assertEqual(authority.identity.localID.rawValue, "a")
    }

    func testCE2R1C108VersionedWorkProjectionSurvivesRecordRoundTrip() async throws {
        let originalAnalysis = analysis(occasionFit: "Date Night")
        let original = record(
            analysisOverride: originalAnalysis,
            metadata: metadata(analysis: originalAnalysis),
            context: .legacyDefault
        )
        let encoded = try data(["a": original])
        let source = FakeSource(data: encoded)
        let authority = try await authority(
            repository: ScanAuthorityRepository(source: source)
        )
        let projection = RecentHistoryEffectiveOccasionResolver.resolve(
            authority: authority,
            legacyCanonicalOccasion: .dateNight
        )
        assertEqual(projection?.occasion, .work)
        assertEqual(projection?.source, .ce2r1(authority.identity))
        assertEqual(authority.analysis.occasionFit, "Date Night")
        assertEqual(authority.analysis.score, originalAnalysis.score)
    }

    func testCE2R1C109MatchingLegacyDescriptorHasNoPresentationRegression() {
        let projection = RecentHistoryEffectiveOccasionResolver.resolve(
            authority: nil,
            legacyCanonicalOccasion: .dateNight
        )
        assertEqual(
            RecentHistoryEffectiveOccasionResolver.compactDescriptor(
                legacyDescriptor: "Date Night",
                detectedStyle: "Casual",
                effectiveOccasion: projection
            ),
            "Date Night"
        )
        assertEqual(projection?.occasion, .dateNight)
    }

    func testCE2R1C110ResolverHasNoConsumerOrPersistenceSideEffects() throws {
        let sourceValue = try source("ScanAuthorityContracts.swift")
        let start = try XCTUnwrap(
            sourceValue.range(of: "enum RecentHistoryEffectiveOccasionResolver")
        )
        let end = try XCTUnwrap(
            sourceValue.range(
                of: "\nenum ScanAuthorityError",
                range: start.lowerBound..<sourceValue.endIndex
            )
        )
        let resolver = String(sourceValue[start.lowerBound..<end.lowerBound])
        for forbidden in [
            "UserDefaults", "saveScanHistory", "URLRequest", "StylistChat",
            "Shopping", "Voice", "score ="
        ] {
            XCTAssertFalse(resolver.contains(forbidden), forbidden)
        }
    }

    func testCE2R1R2Schema01MetadataNegativeAndZeroFailClosed() async {
        for version in [-1, 0] {
            assertEqual(
                await failure(records: [
                    "a": record(metadata: StoredScanAuthorityMetadata(
                        schemaVersion: version,
                        generation: .legacy,
                        contextFingerprint: fingerprint(),
                        completionOrdinal: 1
                    ))
                ]),
                .unsupportedSchema
            )
        }
    }

    func testCE2R1R2Schema02MetadataSupportedRangeIsClosed() async throws {
        XCTAssertTrue(StoredScanAuthorityMetadata.supports(schemaVersion: 1))
        XCTAssertFalse(StoredScanAuthorityMetadata.supports(schemaVersion: 0))
        XCTAssertFalse(StoredScanAuthorityMetadata.supports(schemaVersion: 2))
        _ = try await resolve(
            .latestValidCompleted,
            records: ["a": record(metadata: metadata())]
        )
    }

    func testCE2R1R2Schema03FingerprintVersionsFailClosed() {
        for version in [-1, 0, 2, 4] {
            assertEqual(
                fingerprintFailure(
                    ScanGenerationPolicy.contextFingerprint(
                        fingerprintInput(),
                        schemaVersion: version
                    )
                ),
                .unsupportedSchema
            )
        }
        XCTAssertNotNil(
            try? ScanGenerationPolicy.contextFingerprint(
                fingerprintInput(),
                schemaVersion: 3
            ).get()
        )
    }

    func testCE2R1R2Schema04MissingMetadataUsesDocumentedLegacyPolicy() async throws {
        let authority = try await resolve(
            .latestValidCompleted,
            records: ["a": record(metadata: nil)]
        )
        assertEqual(authority.legacyState, .transientLegacyGeneration)
    }

    func testCE2R1R2Schema05MalformedSchemaNeverReachesCE2A() async {
        let malformed = StoredScanAuthorityMetadata(
            schemaVersion: 0,
            generation: .legacy,
            contextFingerprint: fingerprint(),
            completionOrdinal: 1
        )
        let result = await ScanAuthorityRepository(
            source: FakeSource(data: try? data([
                "a": record(metadata: malformed)
            ]))
        ).resolve(.latestValidCompleted)
        if case .authority = result {
            XCTFail("Malformed schema published authority")
        }
        assertEqual(resultFailure(result), .unsupportedSchema)
    }

    func testCE2R1R2Evidence01RedundantDuplicatesDoNotChangeFingerprint() {
        let single = analysis(evidenceItems: [
            (.branding, 0.8, "one")
        ])
        let duplicateSets: [[
            (OutfitClassificationEvidence.Kind, Double, String)
        ]] = [
            [(.branding, 0.8, "one"), (.branding, 0.4, "lower")],
            [(.branding, 0.8, "one"), (.branding, 0.8, "same")],
            [(.branding, 0.4, "lower"), (.branding, 0.8, "one")]
        ]
        for duplicates in duplicateSets {
            assertEqual(
                fingerprint(analysis: single),
                fingerprint(analysis: analysis(evidenceItems: duplicates))
            )
        }
    }

    func testCE2R1R2Evidence02HigherSameKindChangesFingerprint() {
        XCTAssertNotEqual(
            fingerprint(analysis: analysis(evidenceItems: [
                (.branding, 0.7, "brand")
            ])),
            fingerprint(analysis: analysis(evidenceItems: [
                (.branding, 0.8, "brand")
            ]))
        )
    }

    func testCE2R1R2Evidence03DifferentKindChangesFingerprint() {
        XCTAssertNotEqual(
            fingerprint(analysis: analysis(evidenceItems: [
                (.branding, 0.8, "brand")
            ])),
            fingerprint(analysis: analysis(evidenceItems: [
                (.construction, 0.8, "construction")
            ]))
        )
    }

    func testCE2R1R2Evidence04EqualTieAndPrecisionAreDeterministic() {
        let first = analysis(evidenceItems: [
            (.branding, 0.8000000001, "first"),
            (.branding, 0.8, "second")
        ])
        let second = analysis(evidenceItems: [
            (.branding, 0.8, "second"),
            (.branding, 0.8000000002, "first")
        ])
        assertEqual(fingerprint(analysis: first), fingerprint(analysis: second))
    }

    func testCE2R1R2Evidence05FingerprintAndCE2AUseSameCanonicalEvidence() {
        let first = analysis(evidenceItems: [
            (.silhouette, 0.7, "shape"),
            (.accessory, 0.4, "accessory"),
            (.branding, 0.8, "brand"),
            (.branding, 0.3, "lower")
        ])
        let second = analysis(evidenceItems: [
            (.branding, 0.8, "different private summary"),
            (.accessory, 0.4, "accessory"),
            (.silhouette, 0.7, "shape")
        ])
        let firstInput = contextInput(analysis: first)
        let secondInput = contextInput(analysis: second)
        assertEqual(firstInput.evidence, secondInput.evidence)
        assertEqual(
            firstInput.hasAccessoryEvidence,
            secondInput.hasAccessoryEvidence
        )
        assertEqual(fingerprint(analysis: first), fingerprint(analysis: second))
    }

    func testCE2R1R2Evidence06AccessorySignalRemainsSemanticallyDistinct() {
        let silhouette = analysis(evidenceItems: [
            (.silhouette, 0.7, "shape")
        ])
        let accessory = analysis(evidenceItems: [
            (.silhouette, 0.7, "shape"),
            (.accessory, 0.4, "accessory")
        ])
        XCTAssertNotEqual(
            fingerprint(analysis: silhouette),
            fingerprint(analysis: accessory)
        )
        XCTAssertFalse(contextInput(analysis: silhouette).hasAccessoryEvidence)
        XCTAssertTrue(contextInput(analysis: accessory).hasAccessoryEvidence)
    }

    func testCE2R1R2Evidence07CanonicalizationIsRepeatableAndPrivate() {
        let value = analysis(evidenceItems: [
            (.visibleText, 0.6, "PRIVATE NAME"),
            (.branding, 0.7, "PRIVATE EMPLOYER")
        ])
        let fingerprints = (0..<10).map { _ in fingerprint(analysis: value) }
        assertEqual(Set(fingerprints).count, 1)
        XCTAssertFalse(
            contextInput(analysis: value).evidence
                .contains { $0.kind.rawValue.contains("PRIVATE") }
        )
    }

    private func id(_ raw: String) -> LocalScanRecordID {
        LocalScanRecordID(rawValue: raw)!
    }

    private func generation(record: UInt64 = 2, context: UInt64 = 5) -> ScanGeneration {
        ScanGeneration(recordRevision: record, contextRevision: context)
    }

    private func identity(
        _ raw: String,
        generation: ScanGeneration,
        fingerprint: String
    ) -> ScanSnapshotIdentity {
        ScanSnapshotIdentity(localID: id(raw), generation: generation, contextFingerprint: fingerprint)
    }

    private func metadata(
        id rawID: String = "a",
        ordinal: UInt64? = 1,
        fingerprint: String? = nil,
        generation: ScanGeneration = .legacy,
        context: ScanBoundContext = .legacyDefault,
        analysis: OutfitAnalysisResult? = nil
    ) -> StoredScanAuthorityMetadata {
        StoredScanAuthorityMetadata(
            schemaVersion: 1,
            generation: generation,
            contextFingerprint: fingerprint ?? self.fingerprint(
                id: rawID,
                generation: generation,
                context: context,
                analysis: analysis ?? self.analysis(),
                ordinal: ordinal
            ),
            completionOrdinal: ordinal
        )
    }

    private func record(
        score: Int? = 80,
        includeAnalysis: Bool = true,
        analysisOverride: OutfitAnalysisResult? = nil,
        at: Date? = nil,
        includeTimestamp: Bool = true,
        occasion: Occasion? = .work,
        lifecycle: StoredScanLifecycle? = nil,
        metadata: StoredScanAuthorityMetadata? = nil,
        thumbnail: Data? = nil,
        context: ScanBoundContext? = nil
    ) -> StoredScanRecord {
        StoredScanRecord(
            score: score,
            analysis: includeAnalysis ? (analysisOverride ?? self.analysis()) : nil,
            firstScannedAt: includeTimestamp ? (at ?? date) : nil,
            occasion: occasion,
            thumbnailData: thumbnail,
            lifecycle: lifecycle,
            authorityMetadata: metadata,
            scanBoundContext: context
        )
    }

    private func analysis(
        score: Int = 80,
        evidence kinds: [OutfitClassificationEvidence.Kind] = [.silhouette],
        style: String = "Casual",
        summary: String = "Completed",
        occasionFit: String = "Work",
        confidence: Double = 0.9
    ) -> OutfitAnalysisResult {
        let classification = OutfitClassificationResult(
            primaryCategory: .workUniform,
            secondaryCategories: [],
            confidence: confidence,
            confidenceLevel: .high,
            evidence: kinds.map {
                OutfitClassificationEvidence(
                    kind: $0,
                    summary: "Generic evidence",
                    confidence: confidence
                )
            },
            detectedText: [],
            detectedBranding: [],
            selectedOccasion: Occasion.work.rawValue,
            occasionCompatibility: .compatible,
            userConfirmedCategory: nil,
            scoringProfile: .uniformWorkwear
        )
        return OutfitAnalysisResult(
            score: score,
            scoreBreakdown: OutfitScoreBreakdown(
                colorHarmony: 25,
                patternBalance: 20,
                fitQuality: 13,
                occasionMatch: 6,
                accessoryUse: 6
            ),
            colorMatch: "Coordinated",
            occasionFit: occasionFit,
            styleBalance: style,
            colorHarmony: "Strong",
            styleCoordination: "Strong",
            formality: "Casual",
            seasonalMatch: "Warm",
            summary: summary,
            outfitDescription: "Outfit",
            detectedClothingItems: ["shirt", "pants"],
            colorPalette: ["gray"],
            environment: "Factory",
            imageQuality: "Clear",
            outfitClassification: classification,
            suggestions: [],
            recommendations: []
        )
    }

    private func analysis(
        score: Int = 80,
        evidenceItems: [
            (OutfitClassificationEvidence.Kind, Double, String)
        ],
        style: String = "Casual",
        confidence: Double = 0.9
    ) -> OutfitAnalysisResult {
        let classification = OutfitClassificationResult(
            primaryCategory: .workUniform,
            secondaryCategories: [],
            confidence: confidence,
            confidenceLevel: .high,
            evidence: evidenceItems.map {
                OutfitClassificationEvidence(
                    kind: $0.0,
                    summary: $0.2,
                    confidence: $0.1
                )
            },
            detectedText: [],
            detectedBranding: [],
            selectedOccasion: Occasion.work.rawValue,
            occasionCompatibility: .compatible,
            userConfirmedCategory: nil,
            scoringProfile: .uniformWorkwear
        )
        return OutfitAnalysisResult(
            score: score,
            scoreBreakdown: OutfitScoreBreakdown(
                colorHarmony: 25,
                patternBalance: 20,
                fitQuality: 13,
                occasionMatch: 6,
                accessoryUse: 6
            ),
            colorMatch: "Coordinated",
            occasionFit: "Work",
            styleBalance: style,
            colorHarmony: "Strong",
            styleCoordination: "Strong",
            formality: "Casual",
            seasonalMatch: "Warm",
            summary: "Completed",
            outfitDescription: "Outfit",
            detectedClothingItems: ["shirt", "pants"],
            colorPalette: ["gray"],
            environment: "Factory",
            imageQuality: "Clear",
            outfitClassification: classification,
            suggestions: [],
            recommendations: []
        )
    }

    private func contextInput(
        analysis: OutfitAnalysisResult
    ) -> ContextInferenceInput {
        ContextInferenceInput(
            scanID: "a",
            completedAt: date,
            analysis: analysis,
            selectedOccasion: .work
        )
    }

    private func fingerprint(
        id rawID: String = "a",
        generation: ScanGeneration = .legacy,
        context: ScanBoundContext = .legacyDefault,
        analysis: OutfitAnalysisResult? = nil,
        score: Int = 80,
        ordinal: UInt64? = nil
    ) -> String {
        resolvedFingerprint(
            fingerprintInput(
                id: rawID,
                generation: generation,
                context: context,
                analysis: analysis ?? self.analysis(score: score),
                ordinal: ordinal
            )
        )
    }

    private func resolvedFingerprint(
        _ input: ScanFingerprintInput,
        schemaVersion: Int = ScanGenerationPolicy.currentFingerprintSchemaVersion
    ) -> String {
        try! ScanGenerationPolicy.contextFingerprint(
            input,
            schemaVersion: schemaVersion
        ).get()
    }

    private func assertRepeatedCorrectionIsIdempotent(
        mutation: ScanCorrectionMutation,
        before: ScanBoundContext,
        after: ScanBoundContext,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let beforeInput = fingerprintInput(context: before)
        let current = identity(
            "a",
            generation: beforeInput.generation,
            fingerprint: resolvedFingerprint(beforeInput)
        )
        let afterInput = fingerprintInput(context: after)
        let request = mutationRequest(
            current: current,
            before: beforeInput,
            after: afterInput,
            storedRecordChanged: true,
            mutation: .correction(mutation)
        )
        let result = try? ScanGenerationPolicy.apply(
            current: current,
            request: request
        ).get()
        XCTAssertEqual(result, current, file: file, line: line)
        XCTAssertEqual(
            resolvedFingerprint(beforeInput),
            resolvedFingerprint(afterInput),
            file: file,
            line: line
        )
    }

    private func fingerprintInput(
        id rawID: String = "a",
        generation: ScanGeneration = ScanGeneration(
            recordRevision: 2,
            contextRevision: 5
        ),
        context: ScanBoundContext = .legacyDefault,
        analysis: OutfitAnalysisResult? = nil,
        ordinal: UInt64? = 1
    ) -> ScanFingerprintInput {
        ScanFingerprintInput(
            recordID: id(rawID),
            generation: generation,
            completedAt: date,
            analysis: analysis ?? self.analysis(),
            selectedOccasion: .work,
            scanBoundContext: context,
            completionOrdinal: ordinal
        )
    }

    private func context(
        inputSchemaVersion: Int = ScanBoundContext.currentInputSchemaVersion,
        purpose: ScanPurposeAuthority = .inferred,
        workplace: ScanWorkplaceAuthority = .inferred,
        categoryDisposition: ScanCorrectionDisposition = .inferred,
        occasionDisposition: ScanCorrectionDisposition = .inferred,
        weather: WeatherContextReference = .unknown
    ) -> ScanBoundContext {
        ScanBoundContext(
            inputSchemaVersion: inputSchemaVersion,
            purpose: purpose,
            workplace: workplace,
            categoryDisposition: categoryDisposition,
            occasionDisposition: occasionDisposition,
            weather: weather
        )
    }

    private func purpose(
        proposed: OutfitPurpose? = nil,
        confirmed: OutfitPurpose? = nil,
        rejected: [OutfitPurpose] = [],
        disposition: ScanCorrectionDisposition,
        correctedAt: Date? = nil
    ) -> ScanPurposeAuthority {
        ScanPurposeAuthority(
            proposed: proposed,
            confirmed: confirmed,
            rejected: rejected,
            disposition: disposition,
            correctedAt: correctedAt
        )
    }

    private func workplace(
        proposed: WorkplaceProfile? = nil,
        confirmed: WorkplaceProfile? = nil,
        rejected: [WorkplaceProfile] = [],
        disposition: ScanCorrectionDisposition,
        correctedAt: Date? = nil
    ) -> ScanWorkplaceAuthority {
        ScanWorkplaceAuthority(
            proposed: proposed,
            confirmed: confirmed,
            rejected: rejected,
            disposition: disposition,
            correctedAt: correctedAt
        )
    }

    private func currentIdentity(
        id rawID: String = "a",
        context: ScanBoundContext,
        generation: ScanGeneration = ScanGeneration(
            recordRevision: 2,
            contextRevision: 5
        )
    ) -> ScanSnapshotIdentity {
        let input = fingerprintInput(
            id: rawID,
            generation: generation,
            context: context
        )
        return ScanSnapshotIdentity(
            localID: input.recordID,
            generation: generation,
            contextFingerprint: resolvedFingerprint(input)
        )
    }

    private func workplaceReversalResult(
        before: ScanBoundContext,
        after: ScanBoundContext,
        expectedIdentity: ScanSnapshotIdentity? = nil,
        afterID: String = "a",
        authorityState: ScanAuthorityState = .completed,
        afterAnalysis: OutfitAnalysisResult? = nil
    ) -> Result<ScanSnapshotIdentity, ScanAuthorityError> {
        let beforeInput = fingerprintInput(context: before)
        let current = currentIdentity(context: before)
        let afterInput = fingerprintInput(
            id: afterID,
            context: after,
            analysis: afterAnalysis
        )
        return ScanGenerationPolicy.apply(
            current: current,
            request: mutationRequest(
                current: current,
                before: beforeInput,
                after: afterInput,
                storedRecordChanged: true,
                mutation: .correction(.workplaceReversal),
                expectedIdentity: expectedIdentity,
                authorityState: authorityState
            )
        )
    }

    private func mutate(
        _ mutation: ScanMutationKind,
        beforeContext: ScanBoundContext = .legacyDefault,
        afterContext: ScanBoundContext? = nil,
        beforeAnalysis: OutfitAnalysisResult? = nil,
        afterAnalysis: OutfitAnalysisResult? = nil,
        storedRecordChanged: Bool = true,
        generation: ScanGeneration = ScanGeneration(
            recordRevision: 2,
            contextRevision: 5
        ),
        expectedIdentity: ScanSnapshotIdentity? = nil,
        authorityState: ScanAuthorityState = .completed
    ) -> ScanSnapshotIdentity {
        let before = fingerprintInput(
            generation: generation,
            context: beforeContext,
            analysis: beforeAnalysis
        )
        let current = ScanSnapshotIdentity(
            localID: before.recordID,
            generation: generation,
            contextFingerprint: resolvedFingerprint(before)
        )
        let after = fingerprintInput(
            generation: generation,
            context: afterContext ?? beforeContext,
            analysis: afterAnalysis ?? beforeAnalysis
        )
        let request = mutationRequest(
            current: current,
            before: before,
            after: after,
            storedRecordChanged: storedRecordChanged,
            mutation: mutation,
            expectedIdentity: expectedIdentity,
            authorityState: authorityState
        )
        return try! ScanGenerationPolicy.apply(
            current: current,
            request: request
        ).get()
    }

    private func mutationRequest(
        current: ScanSnapshotIdentity?,
        before: ScanFingerprintInput,
        after: ScanFingerprintInput,
        storedRecordChanged: Bool,
        mutation: ScanMutationKind,
        expectedIdentity: ScanSnapshotIdentity? = nil,
        authorityState: ScanAuthorityState = .completed
    ) -> ScanMutationRequest {
        let fallbackIdentity = current ?? ScanSnapshotIdentity(
            localID: before.recordID,
            generation: before.generation,
            contextFingerprint: resolvedFingerprint(before)
        )
        return ScanMutationRequest(
            expectedIdentity: expectedIdentity ?? fallbackIdentity,
            authorityState: authorityState,
            before: before,
            after: after,
            storedRecordChanged: storedRecordChanged,
            mutation: mutation
        )
    }

    private func data(_ records: [String: StoredScanRecord]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(records)
    }

    private func resolve(
        _ selection: ScanSelection,
        records: [String: StoredScanRecord]
    ) async throws -> ScanAuthority {
        try await authority(
            selection,
            repository: ScanAuthorityRepository(source: FakeSource(data: try data(records)))
        )
    }

    private func authority(
        _ selection: ScanSelection = .latestValidCompleted,
        repository: ScanAuthorityRepository
    ) async throws -> ScanAuthority {
        switch await repository.resolve(selection) {
        case .authority(let authority): return authority
        case .failure(let error): throw error
        }
    }

    private func failure(
        _ selection: ScanSelection = .latestValidCompleted,
        records: [String: StoredScanRecord]
    ) async -> ScanAuthorityError? {
        do {
            return await failure(
                selection,
                repository: ScanAuthorityRepository(source: FakeSource(data: try data(records)))
            )
        } catch {
            return .scanCorrupt
        }
    }

    private func failure(
        _ selection: ScanSelection = .latestValidCompleted,
        repository: ScanAuthorityRepository
    ) async -> ScanAuthorityError? {
        resultFailure(await repository.resolve(selection))
    }

    private func resultFailure(_ result: ScanLoadResult) -> ScanAuthorityError? {
        if case .failure(let error) = result { return error }
        return nil
    }

    private func resultFailure(
        _ result: Result<ScanSnapshotIdentity, ScanAuthorityError>
    ) -> ScanAuthorityError? {
        if case .failure(let error) = result { return error }
        return nil
    }

    private func fingerprintFailure(
        _ result: Result<String, ScanAuthorityError>
    ) -> ScanAuthorityError? {
        if case .failure(let error) = result { return error }
        return nil
    }

    private func input(_ authority: ScanAuthority) throws -> ContextInferenceInput {
        switch ContextInferenceInputFactory.make(authority: authority) {
        case .success(let input): return input
        case .failure(let error): throw error
        }
    }

    private func inputFailure(_ authority: ScanAuthority) -> ScanAuthorityError? {
        if case .failure(let error) = ContextInferenceInputFactory.make(authority: authority) {
            return error
        }
        return nil
    }

    private func infer(_ input: ContextInferenceInput) throws -> OutfitContextSnapshot {
        switch OutfitContextEngine.infer(from: input) {
        case .success(let value): return value
        case .failure(let error): throw error
        }
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    private func source(_ name: String) throws -> String {
        try String(contentsOf: repositoryRoot().appendingPathComponent("StyleMatchAI/ScanAuthority/\(name)"))
    }

    private func scanAuthoritySources() throws -> [String] {
        try [
            "ScanAuthorityContracts.swift", "StoredScanRecord.swift",
            "ScanGenerationPolicy.swift", "AuthoritativeScanSelector.swift",
            "ScanAuthorityRepository.swift", "ContextInferenceInputFactory.swift"
        ].map(source)
    }

    private func assertEqual<T: Equatable>(
        _ actual: T,
        _ expected: T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual, expected, file: file, line: line)
    }
}

private actor FakeSource: ScanRecordDataSource {
    private let captured: ScanContainerCapture
    private var boundary: ScanContainerBoundary
    private(set) var captureCount = 0
    private(set) var boundaryCount = 0
    private(set) var writeCount = 0
    private(set) var recordCount = 0

    init(
        data: Data?,
        integrity: ScanContainerIntegrity = .healthy
    ) {
        let initial = ScanContainerBoundary(accountScopeDigest: "account", sourceRevision: "revision")
        captured = ScanContainerCapture(data: data, boundary: initial, integrity: integrity)
        boundary = initial
        if let data,
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            recordCount = object.count
        }
    }

    func setBoundary(_ value: ScanContainerBoundary) {
        boundary = value
    }

    func capture() async throws -> ScanContainerCapture {
        captureCount += 1
        return captured
    }

    func currentBoundary() async throws -> ScanContainerBoundary {
        boundaryCount += 1
        return boundary
    }
}

private actor SuspendingSource: ScanRecordDataSource {
    private let captured: ScanContainerCapture
    private var boundary: ScanContainerBoundary
    private var boundaryRequested = false
    private var requestWaiters: [CheckedContinuation<Void, Never>] = []
    private var boundaryContinuation: CheckedContinuation<Void, Never>?

    init(data: Data?) {
        let initial = ScanContainerBoundary(
            accountScopeDigest: "account",
            sourceRevision: "revision"
        )
        captured = ScanContainerCapture(
            data: data,
            boundary: initial,
            integrity: .healthy
        )
        boundary = initial
    }

    func capture() async throws -> ScanContainerCapture {
        captured
    }

    func currentBoundary() async throws -> ScanContainerBoundary {
        boundaryRequested = true
        requestWaiters.forEach { $0.resume() }
        requestWaiters.removeAll()
        await withCheckedContinuation { continuation in
            boundaryContinuation = continuation
        }
        return boundary
    }

    func waitUntilBoundaryRequested() async {
        if boundaryRequested { return }
        await withCheckedContinuation { continuation in
            requestWaiters.append(continuation)
        }
    }

    func releaseBoundary() {
        boundaryContinuation?.resume()
        boundaryContinuation = nil
    }
}
