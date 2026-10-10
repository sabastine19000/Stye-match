import Foundation

struct ContextPurposeConfirmation: Equatable {
    let scanID: String
    let purpose: OutfitPurpose
}

struct ContextWorkplaceConfirmation: Equatable {
    let scanID: String
    let profile: WorkplaceProfile
}

struct ContextInferenceEvidenceAtom: Equatable {
    let kind: ContextEvidenceKind
    let confidence: Double
}

struct CanonicalClassificationEvidence: Equatable {
    let evidence: [ContextInferenceEvidenceAtom]
    let hasAccessoryEvidence: Bool
}

enum ContextInferenceEvidenceCanonicalizer {
    static let confidenceScale = 1_000_000.0

    static func canonicalize(
        _ evidence: [OutfitClassificationEvidence]
    ) -> CanonicalClassificationEvidence? {
        var confidenceByKind: [ContextEvidenceKind: Int] = [:]
        var hasAccessoryEvidence = false
        for item in evidence {
            guard let confidence = normalizedConfidence(item.confidence) else {
                return nil
            }
            if item.kind == .accessory {
                hasAccessoryEvidence = true
            }
            let kind = contextKind(item.kind)
            confidenceByKind[kind] = max(
                confidenceByKind[kind] ?? 0,
                confidence
            )
        }
        let canonicalEvidence = confidenceByKind.keys
            .sorted { $0.rawValue < $1.rawValue }
            .map {
                ContextInferenceEvidenceAtom(
                    kind: $0,
                    confidence: Double(confidenceByKind[$0] ?? 0) / confidenceScale
                )
            }
        return CanonicalClassificationEvidence(
            evidence: canonicalEvidence,
            hasAccessoryEvidence: hasAccessoryEvidence
        )
    }

    static func normalizedConfidence(_ value: Double) -> Int? {
        guard value.isFinite else { return nil }
        return Int((min(1, max(0, value)) * confidenceScale).rounded())
    }

    private static func contextKind(
        _ kind: OutfitClassificationEvidence.Kind
    ) -> ContextEvidenceKind {
        switch kind {
        case .silhouette, .accessory:
            return .garmentSilhouette
        case .construction:
            return .garmentConstruction
        case .visibleText:
            return .textPresence
        case .branding:
            return .brandingPresence
        case .occasion:
            return .selectedOccasion
        case .uncertainty:
            return .uncertainty
        }
    }
}

struct ContextInferenceInput: Equatable {
    let scanID: String
    let recordRevision: UInt64
    let contextGeneration: UInt64
    let contextFingerprint: String
    let completedAt: Date
    let score: Int
    let scoreBreakdown: OutfitScoreBreakdown?
    let garmentCategory: ContextGarmentCategory
    let garmentCategoryConfidence: Double
    let garmentCategoryOrigin: ContextValueOrigin
    let detectedStyle: String?
    let selectedOccasion: ContextOccasion
    let selectedOccasionOrigin: ContextValueOrigin
    let legacyOccasionCompatibility: OutfitOccasionCompatibility
    let environmentLabel: String?
    let weather: WeatherContextReference
    let evidence: [ContextInferenceEvidenceAtom]
    let hasAccessoryEvidence: Bool
    let confirmedPurpose: ContextPurposeConfirmation?
    let confirmedWorkplaceProfile: ContextWorkplaceConfirmation?
    let rejectedPurposeIDs: Set<OutfitPurpose>
    let rejectedWorkplaceProfileIDs: Set<WorkplaceProfile>

    init(
        scanID: String,
        recordRevision: UInt64 = 1,
        contextGeneration: UInt64 = 1,
        contextFingerprint: String = "",
        completedAt: Date,
        analysis: OutfitAnalysisResult,
        selectedOccasion: Occasion? = nil,
        weather: WeatherContextReference? = nil,
        confirmedPurpose: ContextPurposeConfirmation? = nil,
        confirmedWorkplaceProfile: ContextWorkplaceConfirmation? = nil,
        rejectedPurposeIDs: Set<OutfitPurpose> = [],
        rejectedWorkplaceProfileIDs: Set<WorkplaceProfile> = []
    ) {
        let classification = analysis.outfitClassification
        let canonicalEvidence = ContextInferenceEvidenceCanonicalizer
            .canonicalize(classification.evidence)
            ?? CanonicalClassificationEvidence(
                evidence: [
                    ContextInferenceEvidenceAtom(
                        kind: .uncertainty,
                        confidence: 0
                    )
                ],
                hasAccessoryEvidence: false
            )
        let resolvedOccasion = selectedOccasion
            ?? Occasion(label: classification.selectedOccasion)
        self.scanID = scanID
        self.recordRevision = recordRevision
        self.contextGeneration = contextGeneration
        self.contextFingerprint = contextFingerprint
        self.completedAt = completedAt
        self.score = analysis.score
        self.scoreBreakdown = analysis.scoreBreakdown
        self.garmentCategory = ContextGarmentCategory(
            rawValue: classification.effectiveCategory.rawValue
        ) ?? .otherUncertain
        self.garmentCategoryConfidence = classification.userConfirmedCategory == nil
            ? classification.confidence
            : 1
        self.garmentCategoryOrigin = classification.userConfirmedCategory == nil
            ? .scanAuthoritative
            : .userConfirmed
        self.detectedStyle = analysis.styleBalance
        self.selectedOccasion = Self.contextOccasion(resolvedOccasion)
        self.selectedOccasionOrigin = selectedOccasion != nil
            ? .userConfirmed
            : (resolvedOccasion == nil ? .unknown : .scanAuthoritative)
        self.legacyOccasionCompatibility = classification.occasionCompatibility
        self.environmentLabel = analysis.environment
        self.weather = weather ?? .unknown
        self.evidence = canonicalEvidence.evidence
        self.hasAccessoryEvidence = canonicalEvidence.hasAccessoryEvidence
        self.confirmedPurpose = confirmedPurpose
        self.confirmedWorkplaceProfile = confirmedWorkplaceProfile
        self.rejectedPurposeIDs = rejectedPurposeIDs
        self.rejectedWorkplaceProfileIDs = rejectedWorkplaceProfileIDs
    }

    private static func contextOccasion(_ occasion: Occasion?) -> ContextOccasion {
        guard let occasion else {
            return .otherUncertain
        }
        switch occasion {
        case .general: return .general
        case .work: return .work
        case .businessFormal: return .businessFormal
        case .weddingGuest, .wedding: return .weddingGuest
        case .party: return .party
        case .casualDay, .casual: return .casualDay
        case .gym: return .gym
        case .loungewear: return .loungewear
        case .specialEvent, .formalEvent: return .specialEvent
        case .dateNight: return .dateNight
        case .travel: return .travel
        case .other: return .otherUncertain
        }
    }

}
