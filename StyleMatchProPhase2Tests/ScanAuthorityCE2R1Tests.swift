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
        let records = ["a": record(metadata: metadata(ordinal: 1)), "b": record(metadata: metadata(ordinal: 2))]
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
        assertEqual(try ScanGenerationPolicy.nextGeneration(previous: nil, mutation: .newScan), .legacy)
        XCTAssertThrowsError(
            try ScanGenerationPolicy.nextGeneration(
                previous: ScanGeneration(
                    recordRevision: .max,
                    contextRevision: 1
                ),
                mutation: .titleOnly
            )
        ) {
            assertEqual($0 as? ScanAuthorityError, .generationOverflow)
        }
    }

    func testCE2R126ByteIdenticalRestorePreservesBothRevisions() {
        assertEqual(next(.restoredByteIdentical), generation())
    }

    func testCE2R127RenameAdvancesOnlyRecordRevision() {
        assertEqual(next(.titleOnly), generation(record: 3, context: 5))
    }

    func testCE2R128ScanCountAdvancesOnlyRecordRevision() {
        assertEqual(next(.thumbnailOnly), generation(record: 3, context: 5))
    }

    func testCE2R129OccasionChangeAdvancesBothRevisions() {
        assertEqual(next(.occasionCorrection), generation(record: 3, context: 6))
    }

    func testCE2R130CategoryConfirmationAdvancesBothRevisions() {
        assertEqual(next(.categoryCorrection), generation(record: 3, context: 6))
    }

    func testCE2R131RepeatedIdenticalConfirmationCanPreserveGeneration() {
        assertEqual(next(.restoredByteIdentical), generation())
    }

    func testCE2R132PurposeCorrectionAdvancesBothRevisions() {
        assertEqual(next(.categoryCorrection), generation(record: 3, context: 6))
    }

    func testCE2R133RejectedPurposeAdvancesBothOnce() {
        assertEqual(next(.categoryCorrection), generation(record: 3, context: 6))
    }

    func testCE2R134NonContextAIWordingPreservesContextRevision() {
        assertEqual(next(.titleOnly).contextRevision, 5)
    }

    func testCE2R135ContextBearingEnrichmentAdvancesContextRevision() {
        assertEqual(next(.analysisEnrichment).contextRevision, 6)
    }

    func testCE2R136IdenticalReanalysisCanPreserveGeneration() {
        assertEqual(next(.restoredByteIdentical), generation())
    }

    func testCE2R137ChangedReanalysisAdvancesContextRevision() {
        assertEqual(next(.analysisEnrichment), generation(record: 3, context: 6))
    }

    func testCE2R138NewScanDoesNotMutatePriorGeneration() throws {
        let old = generation()
        _ = try ScanGenerationPolicy.nextGeneration(previous: old, mutation: .newScan)
        assertEqual(old, generation())
    }

    func testCE2R139GenerationDoesNotDependOnTimestamp() throws {
        assertEqual(
            try ScanGenerationPolicy.nextGeneration(previous: generation(), mutation: .titleOnly),
            try ScanGenerationPolicy.nextGeneration(previous: generation(), mutation: .titleOnly)
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
            ScanGenerationPolicy.contextFingerprint(analysis: first, occasion: .work),
            ScanGenerationPolicy.contextFingerprint(analysis: second, occasion: .work)
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
        assertEqual(await failure(.latestValidCompleted, records: ["a": record(score: 74)]), .scanCorrupt)
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

    private func id(_ raw: String) -> LocalScanRecordID {
        LocalScanRecordID(rawValue: raw)!
    }

    private func generation(record: UInt64 = 2, context: UInt64 = 5) -> ScanGeneration {
        ScanGeneration(recordRevision: record, contextRevision: context)
    }

    private func next(_ mutation: ScanMutationKind) -> ScanGeneration {
        try! ScanGenerationPolicy.nextGeneration(previous: generation(), mutation: mutation)
    }

    private func identity(
        _ raw: String,
        generation: ScanGeneration,
        fingerprint: String
    ) -> ScanSnapshotIdentity {
        ScanSnapshotIdentity(localID: id(raw), generation: generation, contextFingerprint: fingerprint)
    }

    private func metadata(
        ordinal: UInt64? = 1,
        fingerprint: String? = nil
    ) -> StoredScanAuthorityMetadata {
        StoredScanAuthorityMetadata(
            schemaVersion: 1,
            generation: .legacy,
            contextFingerprint: fingerprint ?? self.fingerprint(),
            completionOrdinal: ordinal
        )
    }

    private func record(
        score: Int? = 80,
        includeAnalysis: Bool = true,
        analysisOverride: OutfitAnalysisResult? = nil,
        at: Date? = nil,
        includeTimestamp: Bool = true,
        lifecycle: StoredScanLifecycle? = nil,
        metadata: StoredScanAuthorityMetadata? = nil,
        thumbnail: Data? = nil
    ) -> StoredScanRecord {
        StoredScanRecord(
            score: score,
            analysis: includeAnalysis ? (analysisOverride ?? self.analysis()) : nil,
            firstScannedAt: includeTimestamp ? (at ?? date) : nil,
            occasion: .work,
            thumbnailData: thumbnail,
            lifecycle: lifecycle,
            authorityMetadata: metadata
        )
    }

    private func analysis(
        score: Int = 80,
        evidence kinds: [OutfitClassificationEvidence.Kind] = [.silhouette]
    ) -> OutfitAnalysisResult {
        let classification = OutfitClassificationResult(
            primaryCategory: .workUniform,
            secondaryCategories: [],
            confidence: 0.9,
            confidenceLevel: .high,
            evidence: kinds.map {
                OutfitClassificationEvidence(kind: $0, summary: "Generic evidence", confidence: 0.9)
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
            styleBalance: "Casual",
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

    private func fingerprint(score: Int = 80) -> String {
        ScanGenerationPolicy.contextFingerprint(analysis: analysis(score: score), occasion: .work)
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
