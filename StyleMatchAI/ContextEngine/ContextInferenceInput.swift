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
        rejectedPurposeIDs: Set<OutfitPurpose> = []
    ) {
        let classification = analysis.outfitClassification
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
        self.evidence = Self.privacySafeEvidence(from: classification.evidence)
        self.hasAccessoryEvidence = classification.evidence.contains {
            $0.kind == .accessory
        }
        self.confirmedPurpose = confirmedPurpose
        self.confirmedWorkplaceProfile = confirmedWorkplaceProfile
        self.rejectedPurposeIDs = rejectedPurposeIDs
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

    private static func privacySafeEvidence(
        from evidence: [OutfitClassificationEvidence]
    ) -> [ContextInferenceEvidenceAtom] {
        evidence.map { item in
            let kind: ContextEvidenceKind
            switch item.kind {
            case .silhouette:
                kind = .garmentSilhouette
            case .construction:
                kind = .garmentConstruction
            case .visibleText:
                kind = .textPresence
            case .branding:
                kind = .brandingPresence
            case .occasion:
                kind = .selectedOccasion
            case .accessory:
                kind = .garmentSilhouette
            case .uncertainty:
                kind = .uncertainty
            }
            return ContextInferenceEvidenceAtom(
                kind: kind,
                confidence: item.confidence
            )
        }
    }
}
