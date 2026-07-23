import CryptoKit
import Foundation

enum ScanMutationKind: Sendable {
    case newScan
    case titleOnly
    case thumbnailOnly
    case analysisEnrichment
    case categoryCorrection
    case occasionCorrection
    case restoredByteIdentical
}

enum ScanGenerationPolicy {
    static func resolvedGeneration(
        metadata: StoredScanAuthorityMetadata?,
        analysis: OutfitAnalysisResult,
        occasion: Occasion?
    ) -> Result<(ScanGeneration, String, ScanLegacyAuthorityState), ScanAuthorityError> {
        let fingerprint = contextFingerprint(analysis: analysis, occasion: occasion)
        guard let metadata else {
            return .success((.legacy, fingerprint, .transientLegacyGeneration))
        }
        guard metadata.schemaVersion <= StoredScanAuthorityMetadata.currentSchemaVersion else {
            return .failure(.unsupportedSchema)
        }
        guard metadata.generation.isValid,
              metadata.contextFingerprint == fingerprint else {
            return .failure(.generationMismatch)
        }
        return .success((metadata.generation, fingerprint, .versioned))
    }

    static func nextGeneration(
        previous: ScanGeneration?,
        mutation: ScanMutationKind
    ) throws -> ScanGeneration {
        guard let previous else { return .legacy }
        switch mutation {
        case .newScan:
            return .legacy
        case .titleOnly, .thumbnailOnly:
            let (recordRevision, overflow) = previous.recordRevision
                .addingReportingOverflow(1)
            guard !overflow else { throw ScanAuthorityError.generationOverflow }
            return ScanGeneration(
                recordRevision: recordRevision,
                contextRevision: previous.contextRevision
            )
        case .analysisEnrichment, .categoryCorrection, .occasionCorrection:
            let (recordRevision, recordOverflow) = previous.recordRevision
                .addingReportingOverflow(1)
            let (contextRevision, contextOverflow) = previous.contextRevision
                .addingReportingOverflow(1)
            guard !recordOverflow, !contextOverflow else {
                throw ScanAuthorityError.generationOverflow
            }
            return ScanGeneration(
                recordRevision: recordRevision,
                contextRevision: contextRevision
            )
        case .restoredByteIdentical:
            return previous
        }
    }

    static func contextFingerprint(
        analysis: OutfitAnalysisResult,
        occasion: Occasion?
    ) -> String {
        let material = FingerprintMaterial(
            version: 1,
            score: analysis.score,
            scoreBreakdown: analysis.scoreBreakdown,
            detectedStyle: analysis.styleBalance,
            environment: analysis.environment,
            outfitClassification: FingerprintClassification(
                analysis.outfitClassification
            ),
            selectedOccasion: occasion
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = (try? encoder.encode(material)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private struct FingerprintMaterial: Encodable {
        let version: Int
        let score: Int
        let scoreBreakdown: OutfitScoreBreakdown?
        let detectedStyle: String
        let environment: String
        let outfitClassification: FingerprintClassification
        let selectedOccasion: Occasion?
    }

    private struct FingerprintClassification: Encodable {
        let primaryCategory: String
        let secondaryCategories: [String]
        let confidence: Double
        let confidenceLevel: String
        let evidence: [FingerprintEvidence]
        let selectedOccasion: String?
        let occasionCompatibility: String
        let userConfirmedCategory: String?
        let scoringProfile: String

        init(_ value: OutfitClassificationResult) {
            primaryCategory = value.primaryCategory.rawValue
            secondaryCategories = value.secondaryCategories
                .map(\.rawValue)
                .sorted()
            confidence = value.confidence
            confidenceLevel = value.confidenceLevel.rawValue
            evidence = value.evidence
                .map {
                    FingerprintEvidence(
                        kind: $0.kind.rawValue,
                        confidence: $0.confidence
                    )
                }
                .sorted {
                    ($0.kind, $0.confidence) < ($1.kind, $1.confidence)
                }
            selectedOccasion = value.selectedOccasion
            occasionCompatibility = value.occasionCompatibility.rawValue
            userConfirmedCategory = value.userConfirmedCategory?.rawValue
            scoringProfile = value.scoringProfile.rawValue
        }
    }

    private struct FingerprintEvidence: Encodable {
        let kind: String
        let confidence: Double
    }
}
