import Foundation

struct PurposeCandidate: Equatable {
    let purpose: OutfitPurpose
    let confidence: Double
    let evidenceIDs: [String]
    let conflictingEvidenceIDs: [String]
    let requiresConfirmation: Bool
}

struct PurposeResolution: Equatable {
    let value: EvidenceBackedValue<OutfitPurpose>
    let candidates: [PurposeCandidate]
}

enum PurposeClassifier {
    static func resolve(
        input: ContextInferenceInput,
        environment: EnvironmentType,
        evidence: [ContextEvidence]
    ) -> PurposeResolution {
        if let confirmed = input.confirmedPurpose {
            return PurposeResolution(
                value: EvidenceBackedValue(
                    value: confirmed.purpose,
                    confidence: ContextConfidence(value: 1, level: .high),
                    evidenceIDs: ["user.confirmedPurpose"],
                    origin: .userConfirmed,
                    confirmationState: .confirmed
                ),
                candidates: []
            )
        }

        let purposes = eligiblePurposes(
            category: input.garmentCategory,
            occasion: input.selectedOccasion,
            environment: environment,
            evidence: evidence
        )
        let candidates = purposes
            .filter { !input.rejectedPurposeIDs.contains($0) }
            .map {
                candidate(
                    $0,
                    input: input,
                    environment: environment,
                    evidence: evidence
                )
            }
            .filter { $0.confidence >= minimumConfidence(for: $0.purpose) }
            .sorted {
                if $0.confidence == $1.confidence {
                    return $0.purpose.rawValue < $1.purpose.rawValue
                }
                return $0.confidence > $1.confidence
            }

        guard let first = candidates.first else {
            return uncertain(
                origin: purposes.isEmpty ? .unknown : .runtimeInferred,
                evidenceIDs: evidence.map(\.id),
                candidates: []
            )
        }
        if let second = candidates.dropFirst().first,
           first.confidence - second.confidence <= 0.08 {
            return uncertain(
                origin: .runtimeInferred,
                evidenceIDs: Array(Set(
                    first.evidenceIDs + second.evidenceIDs
                )).sorted(),
                candidates: Array(candidates.prefix(3))
            )
        }

        return PurposeResolution(
            value: EvidenceBackedValue(
                value: first.purpose,
                confidence: confidence(first.confidence),
                evidenceIDs: first.evidenceIDs,
                origin: .runtimeInferred,
                confirmationState: .proposed
            ),
            candidates: Array(candidates.prefix(3))
        )
    }

    static func isSpecialized(_ purpose: OutfitPurpose) -> Bool {
        switch purpose {
        case .factoryManufacturing, .warehouse, .healthcare, .retail,
             .hospitality, .construction, .outdoorWork, .school,
             .weddingParty, .weddingDress, .funeral:
            return true
        default:
            return false
        }
    }

    static func isWorkPurpose(_ purpose: OutfitPurpose) -> Bool {
        switch purpose {
        case .factoryManufacturing, .warehouse, .office,
             .businessCasualOffice, .businessFormal, .healthcare,
             .retail, .hospitality, .construction, .outdoorWork,
             .remoteWork:
            return true
        default:
            return false
        }
    }

    private static func uncertain(
        origin: ContextValueOrigin,
        evidenceIDs: [String],
        candidates: [PurposeCandidate]
    ) -> PurposeResolution {
        PurposeResolution(
            value: EvidenceBackedValue(
                value: .otherUncertain,
                confidence: .unknown,
                evidenceIDs: Array(Set(evidenceIDs)).sorted(),
                origin: origin,
                confirmationState: .uncertain
            ),
            candidates: candidates
        )
    }

    private static func eligiblePurposes(
        category: ContextGarmentCategory,
        occasion: ContextOccasion,
        environment: EnvironmentType,
        evidence: [ContextEvidence]
    ) -> [OutfitPurpose] {
        let hasConstruction = evidence.contains { $0.kind == .garmentConstruction }
        switch category {
        case .workUniform:
            guard occasion == .work else { return [] }
            if hasConstruction { return [.factoryManufacturing] }
            switch environment {
            case .retailStore: return [.retail]
            case .outdoors: return [.outdoorWork]
            case .office: return [.office]
            default: return []
            }
        case .brandedWorkwear:
            guard occasion == .work else { return [] }
            if hasConstruction { return [.construction] }
            switch environment {
            case .retailStore: return [.retail]
            case .outdoors: return [.outdoorWork]
            case .office: return [.office]
            default: return []
            }
        case .medicalScrubs:
            return occasion == .work ? [.healthcare] : []
        case .schoolUniform:
            return environment == .school ? [.school] : []
        case .businessCasual, .femaleBusinessDress:
            switch occasion {
            case .work, .businessFormal: return [.businessCasualOffice]
            case .casualDay, .general: return [.everydayCasual]
            default: return []
            }
        case .businessFormal, .mensSuit:
            switch occasion {
            case .work, .businessFormal: return [.businessFormal]
            case .weddingGuest: return [.weddingGuest]
            case .specialEvent, .party: return [.formalEvent]
            default: return []
            }
        case .tuxedo:
            switch occasion {
            case .weddingGuest: return [.weddingGuest]
            case .specialEvent, .party, .businessFormal: return [.formalEvent]
            default: return []
            }
        case .weddingDress:
            return occasion == .weddingGuest || occasion == .specialEvent
                ? [.weddingDress]
                : []
        case .bridesmaidDress:
            return occasion == .weddingGuest ? [.weddingParty, .weddingGuest] : []
        case .cocktailDress, .eveningGown:
            switch occasion {
            case .dateNight: return [.dateNight]
            case .weddingGuest: return [.weddingGuest]
            case .specialEvent, .party: return [.formalEvent]
            default: return []
            }
        case .casualDress, .casualWear:
            switch occasion {
            case .general, .casualDay: return [.everydayCasual]
            case .dateNight: return [.dateNight]
            case .travel: return [.travel]
            default: return []
            }
        case .sportswear:
            return occasion == .gym ? [.sports] : []
        case .activewear:
            return occasion == .gym ? [.gymTraining] : []
        case .swimwear:
            return environment == .beach ? [.vacation] : []
        case .outerwear:
            if occasion == .travel { return [.travel] }
            if occasion == .work && environment == .outdoors { return [.outdoorWork] }
            return []
        case .traditionalCulturalAttire:
            return occasion == .specialEvent ? [.formalEvent] : []
        case .footwear, .accessories, .otherUncertain:
            return []
        }
    }

    private static func candidate(
        _ purpose: OutfitPurpose,
        input: ContextInferenceInput,
        environment: EnvironmentType,
        evidence: [ContextEvidence]
    ) -> PurposeCandidate {
        var value = 0.4 * min(1, max(0, input.garmentCategoryConfidence))
        var ids = ["scan.garmentCategory"]
        var conflicts: [String] = []

        let construction = evidence
            .filter {
                $0.id != "scan.garmentCategory"
                    && ($0.kind == .garmentConstruction || $0.kind == .garmentSilhouette)
            }
            .map(\.confidence.value)
            .max() ?? 0
        if construction > 0 {
            value += 0.15 * construction
            ids.append("scan.classification.structure")
        }

        if occasionSupports(purpose, occasion: input.selectedOccasion) {
            value += 0.15
            ids.append("scan.selectedOccasion")
        } else if input.selectedOccasion != .otherUncertain {
            value -= 0.20
            conflicts.append("conflict.selectedOccasion")
        }

        let hasTextOrBranding = evidence.contains {
            $0.kind == .textPresence || $0.kind == .brandingPresence
        }
        if hasTextOrBranding && isWorkPurpose(purpose) {
            value += 0.10
            ids.append("scan.classification.genericBrandingOrText")
        }

        if input.hasAccessoryEvidence && supportsAccessoryEvidence(purpose) {
            value += 0.05
            ids.append("scan.classification.accessory")
        }

        if environmentSupports(purpose, environment: environment) {
            value += 0.10
            ids.append("scan.environment")
        } else if environmentConflicts(purpose, environment: environment) {
            value -= 0.10
            conflicts.append("conflict.environment")
        }

        if input.legacyOccasionCompatibility == .compatible {
            value += 0.05
            ids.append("scan.occasionCompatibility")
        } else if input.legacyOccasionCompatibility == .conflict {
            value -= 0.20
            conflicts.append("conflict.occasionCompatibility")
        }

        let independentGroups = Set(ids.map { id -> String in
            if id.contains("garmentCategory") { return "category" }
            if id.contains("structure") { return "structure" }
            if id.contains("selectedOccasion") { return "occasion" }
            if id.contains("BrandingOrText") { return "textBranding" }
            if id.contains("accessory") { return "accessory" }
            if id.contains("environment") { return "environment" }
            return "compatibility"
        })
        if independentGroups.count < 2 {
            value = 0
        }

        return PurposeCandidate(
            purpose: purpose,
            confidence: min(1, max(0, value)),
            evidenceIDs: Array(Set(ids)).sorted(),
            conflictingEvidenceIDs: Array(Set(conflicts)).sorted(),
            requiresConfirmation: isSpecialized(purpose)
        )
    }

    private static func minimumConfidence(for purpose: OutfitPurpose) -> Double {
        switch purpose {
        case .factoryManufacturing: return 0.72
        case .healthcare, .construction: return 0.78
        case .weddingDress: return 0.86
        default: return 0.55
        }
    }

    private static func occasionSupports(
        _ purpose: OutfitPurpose,
        occasion: ContextOccasion
    ) -> Bool {
        switch purpose {
        case .factoryManufacturing, .warehouse, .office,
             .businessCasualOffice, .healthcare, .retail, .hospitality,
             .construction, .outdoorWork, .remoteWork:
            return occasion == .work || occasion == .businessFormal
        case .businessFormal:
            return occasion == .businessFormal || occasion == .work
        case .school:
            return occasion == .general
        case .gymTraining, .sports:
            return occasion == .gym
        case .travel:
            return occasion == .travel
        case .vacation:
            return occasion == .travel || occasion == .casualDay
        case .everydayCasual:
            return occasion == .casualDay || occasion == .general
        case .dateNight:
            return occasion == .dateNight
        case .weddingGuest, .weddingParty, .weddingDress:
            return occasion == .weddingGuest || occasion == .specialEvent
        case .formalEvent, .funeral, .church:
            return occasion == .specialEvent || occasion == .party
        case .otherUncertain:
            return false
        }
    }

    private static func environmentSupports(
        _ purpose: OutfitPurpose,
        environment: EnvironmentType
    ) -> Bool {
        switch purpose {
        case .office, .businessCasualOffice, .businessFormal:
            return environment == .office
        case .retail:
            return environment == .retailStore
        case .outdoorWork, .construction:
            return environment == .outdoors || environment == .parkingGarage
        case .remoteWork:
            return environment == .home
        case .school:
            return environment == .school
        case .gymTraining, .sports:
            return environment == .gym
        case .vacation:
            return environment == .beach
        case .weddingGuest, .weddingParty, .weddingDress, .formalEvent:
            return environment == .eventVenue
        case .church:
            return environment == .placeOfWorship
        default:
            return false
        }
    }

    private static func supportsAccessoryEvidence(_ purpose: OutfitPurpose) -> Bool {
        switch purpose {
        case .businessFormal, .dateNight, .weddingGuest, .weddingParty,
             .weddingDress, .formalEvent:
            return true
        default:
            return false
        }
    }

    private static func environmentConflicts(
        _ purpose: OutfitPurpose,
        environment: EnvironmentType
    ) -> Bool {
        guard environment != .otherUncertain else { return false }
        if purpose == .gymTraining || purpose == .sports {
            return environment == .office
        }
        if purpose == .businessFormal || purpose == .office {
            return environment == .beach || environment == .gym
        }
        return false
    }

    private static func confidence(_ value: Double) -> ContextConfidence {
        ContextConfidence(
            value: value,
            level: value >= 0.82 ? .high : (value >= 0.55 ? .medium : .low)
        )
    }
}
