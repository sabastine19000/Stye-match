import Foundation

struct WorkplaceResolution: Equatable {
    let value: EvidenceBackedValue<WorkplaceProfile>
}

enum WorkplaceProfileClassifier {
    static func resolve(
        input: ContextInferenceInput,
        purpose: EvidenceBackedValue<OutfitPurpose>
    ) -> WorkplaceResolution {
        if let confirmed = input.confirmedWorkplaceProfile {
            return WorkplaceResolution(
                value: EvidenceBackedValue(
                    value: confirmed.profile,
                    confidence: ContextConfidence(value: 1, level: .high),
                    evidenceIDs: ["user.confirmedWorkplaceProfile"],
                    origin: .userConfirmed,
                    confirmationState: .confirmed
                )
            )
        }

        guard PurposeClassifier.isWorkPurpose(purpose.value),
              let profile = profile(for: purpose.value),
              !input.rejectedWorkplaceProfileIDs.contains(profile) else {
            return WorkplaceResolution(
                value: EvidenceBackedValue(
                    value: .otherUncertain,
                    confidence: .unknown,
                    evidenceIDs: [],
                    origin: .unknown,
                    confirmationState: .uncertain
                )
            )
        }

        return WorkplaceResolution(
            value: EvidenceBackedValue(
                value: profile,
                confidence: purpose.confidence,
                evidenceIDs: purpose.evidenceIDs,
                origin: .runtimeInferred,
                confirmationState: .proposed
            )
        )
    }

    private static func profile(for purpose: OutfitPurpose) -> WorkplaceProfile? {
        switch purpose {
        case .factoryManufacturing: return .factoryManufacturing
        case .warehouse: return .warehouse
        case .office: return .office
        case .businessCasualOffice: return .businessCasualOffice
        case .businessFormal: return .office
        case .healthcare: return .healthcare
        case .retail: return .retail
        case .hospitality: return .hospitality
        case .construction: return .construction
        case .outdoorWork: return .outdoorWork
        case .remoteWork: return .remoteWork
        default: return nil
        }
    }
}
