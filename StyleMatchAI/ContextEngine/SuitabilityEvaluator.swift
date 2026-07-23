import Foundation

struct SuitabilityResolution: Equatable {
    let occasion: OccasionCompatibility
    let workplace: WorkplaceSuitability
    let weather: WeatherSuitability
    let safetyContext: SafetyContext
    let safety: SafetySuitability
}

enum SuitabilityEvaluator {
    static func evaluate(
        input: ContextInferenceInput,
        purpose: EvidenceBackedValue<OutfitPurpose>,
        workplace: EvidenceBackedValue<WorkplaceProfile>,
        evidence: [ContextEvidence]
    ) -> SuitabilityResolution {
        SuitabilityResolution(
            occasion: occasion(input: input, purpose: purpose),
            workplace: workplaceSuitability(
                selectedOccasion: input.selectedOccasion,
                purpose: purpose,
                workplace: workplace
            ),
            weather: weather(input: input, purpose: purpose),
            safetyContext: safetyContext(purpose: purpose, evidence: evidence),
            safety: safety(purpose: purpose, evidence: evidence)
        )
    }

    private static func occasion(
        input: ContextInferenceInput,
        purpose: EvidenceBackedValue<OutfitPurpose>
    ) -> OccasionCompatibility {
        guard input.selectedOccasion != .otherUncertain,
              purpose.value != .otherUncertain else {
            return .uncertain
        }
        let compatible = purposeSupportsOccasion(
            purpose.value,
            occasion: input.selectedOccasion
        )
        if !compatible {
            return OccasionCompatibility(
                level: .low,
                confidence: ContextConfidence(value: 0.8, level: .medium),
                supportingEvidenceIDs: [],
                conflictingEvidenceIDs: ["conflict.selectedOccasion"],
                missingEvidenceIDs: [],
                summary: "The selected occasion conflicts with the inferred purpose."
            )
        }
        let confirmed = purpose.confirmationState == .confirmed
        return OccasionCompatibility(
            level: confirmed ? .high : .moderate,
            confidence: purpose.confidence,
            supportingEvidenceIDs: purpose.evidenceIDs,
            conflictingEvidenceIDs: [],
            missingEvidenceIDs: [],
            summary: confirmed
                ? "The confirmed purpose supports the selected occasion."
                : "The proposed purpose may support the selected occasion."
        )
    }

    private static func workplaceSuitability(
        selectedOccasion: ContextOccasion,
        purpose: EvidenceBackedValue<OutfitPurpose>,
        workplace: EvidenceBackedValue<WorkplaceProfile>
    ) -> WorkplaceSuitability {
        guard PurposeClassifier.isWorkPurpose(purpose.value) else {
            if selectedOccasion == .work {
                return .uncertain
            }
            return WorkplaceSuitability(
                level: .notApplicable,
                confidence: .unknown,
                supportingEvidenceIDs: [],
                conflictingEvidenceIDs: [],
                missingEvidenceIDs: [],
                summary: "Workplace suitability is not applicable to this purpose."
            )
        }
        guard workplace.value != .otherUncertain,
              workplace.confirmationState == .confirmed else {
            return .uncertain
        }
        return WorkplaceSuitability(
            level: .moderate,
            confidence: workplace.confidence,
            supportingEvidenceIDs: workplace.evidenceIDs,
            conflictingEvidenceIDs: [],
            missingEvidenceIDs: [],
            summary: "The confirmed workplace profile has supporting visible evidence."
        )
    }

    private static func weather(
        input: ContextInferenceInput,
        purpose: EvidenceBackedValue<OutfitPurpose>
    ) -> WeatherSuitability {
        guard input.weather.hasEvidence,
              input.weather.confidence.value >= 0.55 else {
            return .uncertain
        }
        let confidenceValue = purpose.value == .otherUncertain
            ? min(0.65, input.weather.confidence.value)
            : min(input.weather.confidence.value, purpose.confidence.value)
        return WeatherSuitability(
            level: .moderate,
            confidence: ContextConfidence(
                value: confidenceValue,
                level: confidenceValue >= 0.82 ? .high : .medium
            ),
            supportingEvidenceIDs: ["scan.weather"],
            conflictingEvidenceIDs: [],
            missingEvidenceIDs: purpose.value == .otherUncertain ? ["purpose"] : [],
            summary: purpose.value == .otherUncertain
                ? "Weather evidence is available, but purpose remains uncertain."
                : "Weather evidence is available for the proposed purpose."
        )
    }

    private static func safetyContext(
        purpose: EvidenceBackedValue<OutfitPurpose>,
        evidence: [ContextEvidence]
    ) -> SafetyContext {
        guard isSafetyRelevant(purpose.value) else {
            return .unverified
        }
        let support = evidence
            .filter { $0.kind == .garmentConstruction }
            .map(\.id)
            .sorted()
        return SafetyContext(
            supportingEvidenceIDs: support,
            missingEvidenceIDs: ["safety.requirementsNotVisible"],
            limitations: [
                "Visible cues cannot establish certification or workplace-policy compliance."
            ]
        )
    }

    private static func safety(
        purpose: EvidenceBackedValue<OutfitPurpose>,
        evidence: [ContextEvidence]
    ) -> SafetySuitability {
        guard isSafetyRelevant(purpose.value) else {
            return SafetySuitability(
                level: .notApplicable,
                confidence: .unknown,
                supportingEvidenceIDs: [],
                conflictingEvidenceIDs: [],
                missingEvidenceIDs: [],
                summary: "Safety suitability is not applicable to this purpose."
            )
        }
        guard purpose.confirmationState == .confirmed else {
            return .uncertain
        }
        let support = evidence
            .filter { $0.kind == .garmentConstruction }
            .map(\.id)
            .sorted()
        guard !support.isEmpty else {
            return .uncertain
        }
        return SafetySuitability(
            level: .moderate,
            confidence: ContextConfidence(value: 0.65, level: .medium),
            supportingEvidenceIDs: support,
            conflictingEvidenceIDs: [],
            missingEvidenceIDs: ["safety.requirementsNotVisible"],
            summary: "Visible construction cues support advisory safety context only."
        )
    }

    private static func isSafetyRelevant(_ purpose: OutfitPurpose) -> Bool {
        switch purpose {
        case .factoryManufacturing, .warehouse, .construction, .outdoorWork:
            return true
        default:
            return false
        }
    }

    private static func purposeSupportsOccasion(
        _ purpose: OutfitPurpose,
        occasion: ContextOccasion
    ) -> Bool {
        switch occasion {
        case .work:
            return PurposeClassifier.isWorkPurpose(purpose)
        case .businessFormal:
            return purpose == .businessFormal
                || purpose == .businessCasualOffice
                || purpose == .office
        case .weddingGuest:
            return purpose == .weddingGuest
                || purpose == .weddingParty
                || purpose == .weddingDress
        case .party, .specialEvent:
            return purpose == .formalEvent
                || purpose == .dateNight
                || purpose == .weddingGuest
        case .casualDay, .general:
            return purpose == .everydayCasual
        case .gym:
            return purpose == .gymTraining || purpose == .sports
        case .dateNight:
            return purpose == .dateNight
        case .travel:
            return purpose == .travel || purpose == .vacation
        case .loungewear, .otherUncertain:
            return false
        }
    }
}
