import CryptoKit
import Foundation

enum ScanCorrectionMutation: Equatable, Sendable {
    case purposeConfirmation
    case purposeCorrection
    case purposeRejection
    case purposeReversal
    case workplaceConfirmation
    case workplaceCorrection
    case workplaceRejectionOrClearing
    case categoryCorrection
    case occasionCorrection
    case restorationToInferredOrUncertain
}

enum ScanMutationKind: Equatable, Sendable {
    case newScan
    case titleOnly
    case thumbnailOnly
    case analysisEnrichment
    case correction(ScanCorrectionMutation)
    case restoredByteIdentical
}

struct ScanFingerprintInput: @unchecked Sendable {
    let recordID: LocalScanRecordID
    let generation: ScanGeneration
    let completedAt: Date?
    let analysis: OutfitAnalysisResult
    let selectedOccasion: Occasion?
    let scanBoundContext: ScanBoundContext
    let completionOrdinal: UInt64?

    init(
        recordID: LocalScanRecordID,
        generation: ScanGeneration,
        completedAt: Date? = nil,
        analysis: OutfitAnalysisResult,
        selectedOccasion: Occasion?,
        scanBoundContext: ScanBoundContext,
        completionOrdinal: UInt64?
    ) {
        self.recordID = recordID
        self.generation = generation
        self.completedAt = completedAt
        self.analysis = analysis
        self.selectedOccasion = selectedOccasion
        self.scanBoundContext = scanBoundContext
        self.completionOrdinal = completionOrdinal
    }

    func replacingGeneration(_ value: ScanGeneration) -> Self {
        Self(
            recordID: recordID,
            generation: value,
            completedAt: completedAt,
            analysis: analysis,
            selectedOccasion: selectedOccasion,
            scanBoundContext: scanBoundContext,
            completionOrdinal: completionOrdinal
        )
    }
}

struct ScanMutationRequest: @unchecked Sendable {
    let expectedIdentity: ScanSnapshotIdentity
    let before: ScanFingerprintInput
    let after: ScanFingerprintInput
    let storedRecordChanged: Bool
    let mutation: ScanMutationKind
}

enum ScanGenerationPolicy {
    static let minimumSupportedFingerprintSchemaVersion = 3
    static let currentFingerprintSchemaVersion = 3

    static func resolvedGeneration(
        recordID: LocalScanRecordID,
        metadata: StoredScanAuthorityMetadata?,
        record: StoredScanRecord
    ) -> Result<(ScanGeneration, String, ScanLegacyAuthorityState), ScanAuthorityError> {
        guard let analysis = record.analysis else {
            return .failure(.scanPartial)
        }
        let generation = metadata?.generation ?? .legacy
        let context = record.scanBoundContext ?? .legacyDefault
        guard context.inputSchemaVersion > 0,
              context.inputSchemaVersion <= ScanBoundContext.currentInputSchemaVersion else {
            return .failure(.unsupportedSchema)
        }
        guard validatesStoredContext(context) else {
            return .failure(.scanCorrupt)
        }
        let input = ScanFingerprintInput(
            recordID: recordID,
            generation: generation,
            completedAt: record.firstScannedAt,
            analysis: analysis,
            selectedOccasion: record.occasion,
            scanBoundContext: context,
            completionOrdinal: metadata?.completionOrdinal
        )
        let fingerprint: String
        switch contextFingerprint(input) {
        case .success(let value):
            fingerprint = value
        case .failure(let error):
            return .failure(error)
        }
        guard let metadata else {
            return .success((generation, fingerprint, .transientLegacyGeneration))
        }
        guard StoredScanAuthorityMetadata.supports(
            schemaVersion: metadata.schemaVersion
        ) else {
            return .failure(.unsupportedSchema)
        }
        guard metadata.generation.isValid,
              metadata.contextFingerprint == fingerprint else {
            return .failure(.generationMismatch)
        }
        return .success((generation, fingerprint, .versioned))
    }

    static func apply(
        current: ScanSnapshotIdentity?,
        request: ScanMutationRequest
    ) -> Result<ScanSnapshotIdentity, ScanAuthorityError> {
        guard let current else {
            guard request.mutation == .newScan else {
                return .failure(.generationMismatch)
            }
            let initial = request.after.replacingGeneration(.legacy)
            let fingerprint: String
            switch contextFingerprint(initial) {
            case .success(let value):
                fingerprint = value
            case .failure(let error):
                return .failure(error)
            }
            return .success(ScanSnapshotIdentity(
                localID: initial.recordID,
                generation: .legacy,
                contextFingerprint: fingerprint
            ))
        }
        let beforeFingerprint: String
        switch contextFingerprint(request.before) {
        case .success(let value):
            beforeFingerprint = value
        case .failure(let error):
            return .failure(error)
        }
        guard current == request.expectedIdentity,
              request.before.recordID == current.localID,
              request.after.recordID == current.localID,
              request.before.generation == current.generation,
              request.after.generation == current.generation,
              beforeFingerprint == current.contextFingerprint else {
            return .failure(.generationMismatch)
        }

        let beforeContext: Data
        switch canonicalContextData(request.before) {
        case .success(let value):
            beforeContext = value
        case .failure(let error):
            return .failure(error)
        }
        let afterContext: Data
        switch canonicalContextData(request.after) {
        case .success(let value):
            afterContext = value
        case .failure(let error):
            return .failure(error)
        }
        let contextChanged = beforeContext != afterContext

        // Correction timestamps are audit metadata, not context authority.
        // A repeated correction with identical normalized meaning preserves the
        // first published identity even if an audit layer records a later event.
        if !contextChanged, case .correction = request.mutation {
            return .success(current)
        }
        if !contextChanged, !request.storedRecordChanged {
            return .success(current)
        }
        if request.mutation == .restoredByteIdentical {
            guard !contextChanged else { return .failure(.generationMismatch) }
            return .success(current)
        }
        guard validatesMutation(request.mutation, after: request.after.scanBoundContext) else {
            return .failure(.generationMismatch)
        }

        let nextGeneration: ScanGeneration
        do {
            nextGeneration = try increment(
                current.generation,
                contextChanged: contextChanged
            )
        } catch let error as ScanAuthorityError {
            return .failure(error)
        } catch {
            return .failure(.generationOverflow)
        }
        let nextInput = request.after.replacingGeneration(nextGeneration)
        let nextFingerprint: String
        switch contextFingerprint(nextInput) {
        case .success(let value):
            nextFingerprint = value
        case .failure(let error):
            return .failure(error)
        }
        return .success(ScanSnapshotIdentity(
            localID: current.localID,
            generation: nextGeneration,
            contextFingerprint: nextFingerprint
        ))
    }

    static func contextFingerprint(
        _ input: ScanFingerprintInput,
        schemaVersion: Int = currentFingerprintSchemaVersion
    ) -> Result<String, ScanAuthorityError> {
        guard supportsFingerprintSchemaVersion(schemaVersion) else {
            return .failure(.unsupportedSchema)
        }
        let context: CanonicalContextMaterial
        switch canonicalContext(input) {
        case .success(let value):
            context = value
        case .failure(let error):
            return .failure(error)
        }
        let material = FingerprintMaterial(
            schemaVersion: schemaVersion,
            localIdentityDigest: digest(
                Data(("local-scan:" + input.recordID.rawValue).utf8)
            ),
            recordRevision: input.generation.recordRevision,
            contextRevision: input.generation.contextRevision,
            completionMilliseconds: epochMilliseconds(input.completedAt),
            completionOrdinal: input.completionOrdinal,
            context: context
        )
        switch encode(material) {
        case .success(let data):
            return .success(digest(data))
        case .failure(let error):
            return .failure(error)
        }
    }

    static func canonicalContextData(
        _ input: ScanFingerprintInput
    ) -> Result<Data, ScanAuthorityError> {
        switch canonicalContext(input) {
        case .success(let context):
            return encode(context)
        case .failure(let error):
            return .failure(error)
        }
    }

    static func supportsFingerprintSchemaVersion(_ schemaVersion: Int) -> Bool {
        (minimumSupportedFingerprintSchemaVersion...currentFingerprintSchemaVersion)
            .contains(schemaVersion)
    }

    private static func increment(
        _ previous: ScanGeneration,
        contextChanged: Bool
    ) throws -> ScanGeneration {
        let (recordRevision, recordOverflow) = previous.recordRevision
            .addingReportingOverflow(1)
        let (contextRevision, contextOverflow) = contextChanged
            ? previous.contextRevision.addingReportingOverflow(1)
            : (previous.contextRevision, false)
        guard !recordOverflow, !contextOverflow else {
            throw ScanAuthorityError.generationOverflow
        }
        return ScanGeneration(
            recordRevision: recordRevision,
            contextRevision: contextRevision
        )
    }

    private static func validatesMutation(
        _ mutation: ScanMutationKind,
        after: ScanBoundContext
    ) -> Bool {
        guard validatesStoredContext(after) else { return false }
        switch mutation {
        case .newScan, .titleOnly, .thumbnailOnly, .analysisEnrichment,
             .restoredByteIdentical:
            return true
        case .correction(.purposeConfirmation):
            return after.purpose.disposition == .confirmed
                && validConfirmedPurpose(after.purpose)
        case .correction(.purposeCorrection):
            return after.purpose.disposition == .corrected
                && validConfirmedPurpose(after.purpose)
        case .correction(.purposeRejection):
            return after.purpose.disposition == .rejected
                && !after.purpose.rejected.isEmpty
                && after.purpose.confirmed == nil
        case .correction(.purposeReversal):
            return [.inferred, .uncertain].contains(after.purpose.disposition)
                && after.purpose.confirmed == nil
        case .correction(.workplaceConfirmation):
            return after.workplace.disposition == .confirmed
                && validConfirmedWorkplace(after.workplace)
        case .correction(.workplaceCorrection):
            return after.workplace.disposition == .corrected
                && validConfirmedWorkplace(after.workplace)
        case .correction(.workplaceRejectionOrClearing):
            return [.rejected, .cleared].contains(after.workplace.disposition)
                && after.workplace.confirmed == nil
        case .correction(.categoryCorrection):
            return [.confirmed, .corrected, .inferred, .uncertain]
                .contains(after.categoryDisposition)
        case .correction(.occasionCorrection):
            return [.confirmed, .corrected, .inferred, .uncertain]
                .contains(after.occasionDisposition)
        case .correction(.restorationToInferredOrUncertain):
            return [.inferred, .uncertain].contains(after.purpose.disposition)
                && [.inferred, .uncertain, .cleared]
                .contains(after.workplace.disposition)
        }
    }

    private static func validatesStoredContext(_ context: ScanBoundContext) -> Bool {
        guard context.inputSchemaVersion > 0,
              context.inputSchemaVersion <= ScanBoundContext.currentInputSchemaVersion else {
            return false
        }
        let purposeIsValid: Bool
        switch context.purpose.disposition {
        case .confirmed, .corrected:
            purposeIsValid = validConfirmedPurpose(context.purpose)
        case .rejected:
            purposeIsValid = context.purpose.confirmed == nil
                && !context.purpose.rejected.isEmpty
        case .inferred, .uncertain, .cleared:
            purposeIsValid = context.purpose.confirmed == nil
        }

        let workplaceIsValid: Bool
        switch context.workplace.disposition {
        case .confirmed, .corrected:
            workplaceIsValid = validConfirmedWorkplace(context.workplace)
        case .rejected:
            workplaceIsValid = context.workplace.confirmed == nil
                && !context.workplace.rejected.isEmpty
        case .inferred, .uncertain, .cleared:
            workplaceIsValid = context.workplace.confirmed == nil
        }
        return purposeIsValid && workplaceIsValid
    }

    private static func validConfirmedPurpose(
        _ value: ScanPurposeAuthority
    ) -> Bool {
        guard let confirmed = value.confirmed,
              confirmed != .otherUncertain else {
            return false
        }
        return !value.rejected.contains(confirmed)
    }

    private static func validConfirmedWorkplace(
        _ value: ScanWorkplaceAuthority
    ) -> Bool {
        guard let confirmed = value.confirmed,
              confirmed != .otherUncertain else {
            return false
        }
        return !value.rejected.contains { $0.rawValue == confirmed.rawValue }
    }

    private static func canonicalContext(
        _ input: ScanFingerprintInput
    ) -> Result<CanonicalContextMaterial, ScanAuthorityError> {
        guard (0...100).contains(input.analysis.score) else {
            return .failure(.invalidAnalysisScore)
        }
        guard input.analysis.outfitClassification.confidence.isFinite,
              let classification = FingerprintClassification(
                input.analysis.outfitClassification
              ),
              let weather = WeatherMaterial(input.scanBoundContext.weather) else {
            return .failure(.scanCorrupt)
        }
        return .success(CanonicalContextMaterial(
            inputSchemaVersion: input.scanBoundContext.inputSchemaVersion,
            score: input.analysis.score,
            scoreBreakdown: input.analysis.scoreBreakdown.map {
                ScoreBreakdownMaterial(
                    colorHarmony: $0.colorHarmony,
                    patternBalance: $0.patternBalance,
                    fitQuality: $0.fitQuality,
                    occasionMatch: $0.occasionMatch,
                    accessoryUse: $0.accessoryUse
                )
            },
            detectedStyle: normalized(input.analysis.styleBalance),
            environment: normalized(input.analysis.environment),
            outfitClassification: classification,
            selectedOccasion: input.selectedOccasion?.rawValue,
            purpose: PurposeMaterial(input.scanBoundContext.purpose),
            workplace: WorkplaceMaterial(input.scanBoundContext.workplace),
            categoryDisposition: input.scanBoundContext.categoryDisposition.rawValue,
            occasionDisposition: input.scanBoundContext.occasionDisposition.rawValue,
            weather: weather
        ))
    }

    private static func encode<T: Encodable>(
        _ value: T
    ) -> Result<Data, ScanAuthorityError> {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        do {
            return .success(try encoder.encode(value))
        } catch {
            return .failure(.scanCorrupt)
        }
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let collapsed = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()
        return collapsed.isEmpty ? nil : collapsed
    }

    private static func epochMilliseconds(_ value: Date?) -> Int64? {
        value.map { Int64(($0.timeIntervalSince1970 * 1_000).rounded()) }
    }

    private struct FingerprintMaterial: Encodable {
        let schemaVersion: Int
        let localIdentityDigest: String
        let recordRevision: UInt64
        let contextRevision: UInt64
        let completionMilliseconds: Int64?
        let completionOrdinal: UInt64?
        let context: CanonicalContextMaterial
    }

    private struct CanonicalContextMaterial: Encodable {
        let inputSchemaVersion: Int
        let score: Int
        let scoreBreakdown: ScoreBreakdownMaterial?
        let detectedStyle: String?
        let environment: String?
        let outfitClassification: FingerprintClassification
        let selectedOccasion: String?
        let purpose: PurposeMaterial
        let workplace: WorkplaceMaterial
        let categoryDisposition: String
        let occasionDisposition: String
        let weather: WeatherMaterial
    }

    private struct ScoreBreakdownMaterial: Encodable {
        let colorHarmony: Int
        let patternBalance: Int
        let fitQuality: Int
        let occasionMatch: Int
        let accessoryUse: Int
    }

    private struct PurposeMaterial: Encodable {
        let proposed: String?
        let confirmed: String?
        let rejected: [String]
        let disposition: String

        init(_ value: ScanPurposeAuthority) {
            proposed = value.proposed?.rawValue
            confirmed = value.confirmed?.rawValue
            rejected = value.rejected.map(\.rawValue).sorted()
            disposition = value.disposition.rawValue
        }
    }

    private struct WorkplaceMaterial: Encodable {
        let proposed: String?
        let confirmed: String?
        let rejected: [String]
        let disposition: String

        init(_ value: ScanWorkplaceAuthority) {
            proposed = value.proposed?.rawValue
            confirmed = value.confirmed?.rawValue
            rejected = value.rejected.map(\.rawValue).sorted()
            disposition = value.disposition.rawValue
        }
    }

    private struct WeatherMaterial: Encodable {
        let observedAtMilliseconds: Int64?
        let airTemperature: Int?
        let feelsLikeTemperature: Int?
        let humidityPercent: Int?
        let rainChancePercent: Int?
        let windMph: Int?
        let uvIndex: Int?
        let condition: String?
        let confidence: Int
        let confidenceLevel: String

        init?(_ value: WeatherContextReference) {
            guard let confidenceUnits = ContextInferenceEvidenceCanonicalizer
                .normalizedConfidence(value.confidence.value) else {
                return nil
            }
            observedAtMilliseconds = epochMilliseconds(value.observedAt)
            airTemperature = value.airTemperature
            feelsLikeTemperature = value.feelsLikeTemperature
            humidityPercent = value.humidityPercent
            rainChancePercent = value.rainChancePercent
            windMph = value.windMph
            uvIndex = value.uvIndex
            condition = normalized(value.condition)
            confidence = confidenceUnits
            confidenceLevel = value.confidence.level.rawValue
        }
    }

    private struct FingerprintClassification: Encodable {
        let primaryCategory: String
        let secondaryCategories: [String]
        let confidence: Int
        let confidenceLevel: String
        let evidence: [FingerprintEvidence]
        let hasAccessoryEvidence: Bool
        let selectedOccasion: String?
        let occasionCompatibility: String
        let userConfirmedCategory: String?
        let scoringProfile: String

        init?(_ value: OutfitClassificationResult) {
            guard let confidenceUnits = ContextInferenceEvidenceCanonicalizer
                    .normalizedConfidence(value.confidence),
                  let canonicalEvidence = ContextInferenceEvidenceCanonicalizer
                    .canonicalize(value.evidence) else {
                return nil
            }
            primaryCategory = value.primaryCategory.rawValue
            secondaryCategories = value.secondaryCategories
                .map(\.rawValue)
                .sorted()
            confidence = confidenceUnits
            confidenceLevel = value.confidenceLevel.rawValue
            evidence = canonicalEvidence.evidence
                .map {
                    FingerprintEvidence(
                        kind: $0.kind.rawValue,
                        confidence: ContextInferenceEvidenceCanonicalizer
                            .normalizedConfidence($0.confidence) ?? 0
                    )
                }
            hasAccessoryEvidence = canonicalEvidence.hasAccessoryEvidence
            selectedOccasion = normalized(value.selectedOccasion)
            occasionCompatibility = value.occasionCompatibility.rawValue
            userConfirmedCategory = value.userConfirmedCategory?.rawValue
            scoringProfile = value.scoringProfile.rawValue
        }
    }

    private struct FingerprintEvidence: Encodable {
        let kind: String
        let confidence: Int
    }
}
