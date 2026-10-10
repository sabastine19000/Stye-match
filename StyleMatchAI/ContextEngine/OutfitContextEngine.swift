import Foundation

enum OutfitContextEngine {
    static let algorithmVersion = "ce2a-runtime-v1"

    static func infer(
        from input: ContextInferenceInput
    ) -> Result<OutfitContextSnapshot, ContextInferenceFailure> {
        if let failure = ContextInferenceValidator.validate(input) {
            return .failure(failure)
        }

        let evidence = makeEvidence(input)
        let environment = environmentType(from: input.environmentLabel)
        let purpose = PurposeClassifier.resolve(
            input: input,
            environment: environment,
            evidence: evidence
        )
        let workplace = WorkplaceProfileClassifier.resolve(
            input: input,
            purpose: purpose.value
        )
        let suitability = SuitabilityEvaluator.evaluate(
            input: input,
            purpose: purpose.value,
            workplace: workplace.value,
            evidence: evidence
        )
        let missing = missingEvidence(
            input: input,
            purpose: purpose.value,
            workplace: workplace.value,
            environment: environment,
            safety: suitability.safety
        )
        let confidence = aggregateConfidence(
            input: input,
            purpose: purpose,
            workplace: workplace.value,
            environment: environment,
            suitability: suitability
        )
        let snapshot = OutfitContextSnapshot(
            schemaVersion: OutfitContextSnapshot.currentSchemaVersion,
            generation: input.contextGeneration,
            scanID: input.scanID,
            completedAt: input.completedAt,
            authoritativeScore: input.score,
            authoritativeBreakdown: input.scoreBreakdown,
            detectedStyle: detectedStyle(input),
            garmentCategory: garmentCategory(input),
            outfitPurpose: purpose.value,
            environmentType: environmentValue(
                environment,
                input: input
            ),
            selectedOccasion: selectedOccasion(input),
            occasionCompatibility: suitability.occasion,
            workplaceProfile: workplace.value,
            workplaceSuitability: suitability.workplace,
            weatherContext: input.weather,
            weatherSuitability: suitability.weather,
            safetyContext: suitability.safetyContext,
            safetySuitability: suitability.safety,
            userConfirmedPurpose: input.confirmedPurpose?.purpose,
            confidence: confidence,
            evidence: evidence,
            missingEvidence: missing,
            scoringProfile: scoringProfile(for: purpose.value.value),
            provenance: provenance(
                input: input,
                purpose: purpose.value,
                workplace: workplace.value,
                environment: environment,
                confidence: confidence
            )
        )
        if let failure = ContextInferenceValidator.validate(
            snapshot: snapshot,
            input: input
        ) {
            return .failure(failure)
        }
        return .success(snapshot)
    }

    private static func detectedStyle(
        _ input: ContextInferenceInput
    ) -> EvidenceBackedValue<String> {
        let trimmed = input.detectedStyle?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            return EvidenceBackedValue(
                value: "Other / Uncertain",
                confidence: .unknown,
                evidenceIDs: [],
                origin: .unknown,
                confirmationState: .uncertain
            )
        }
        return EvidenceBackedValue(
            value: String(trimmed.prefix(120)),
            confidence: ContextConfidence(value: 0.5, level: .low),
            evidenceIDs: ["scan.detectedStyle"],
            origin: .scanAuthoritative,
            confirmationState: .proposed
        )
    }

    private static func garmentCategory(
        _ input: ContextInferenceInput
    ) -> EvidenceBackedValue<ContextGarmentCategory> {
        let uncertain = input.garmentCategory == .otherUncertain
        return EvidenceBackedValue(
            value: input.garmentCategory,
            confidence: uncertain
                ? .unknown
                : boundedConfidence(input.garmentCategoryConfidence),
            evidenceIDs: uncertain ? [] : ["scan.garmentCategory"],
            origin: uncertain ? input.garmentCategoryOrigin : input.garmentCategoryOrigin,
            confirmationState: uncertain
                ? .uncertain
                : (input.garmentCategoryOrigin == .userConfirmed ? .confirmed : .proposed)
        )
    }

    private static func selectedOccasion(
        _ input: ContextInferenceInput
    ) -> EvidenceBackedValue<ContextOccasion> {
        let uncertain = input.selectedOccasion == .otherUncertain
        return EvidenceBackedValue(
            value: input.selectedOccasion,
            confidence: uncertain
                ? .unknown
                : ContextConfidence(value: 1, level: .high),
            evidenceIDs: uncertain ? [] : ["scan.selectedOccasion"],
            origin: uncertain ? .unknown : input.selectedOccasionOrigin,
            confirmationState: uncertain
                ? .uncertain
                : (input.selectedOccasionOrigin == .userConfirmed ? .confirmed : .proposed)
        )
    }

    private static func environmentValue(
        _ environment: EnvironmentType,
        input: ContextInferenceInput
    ) -> EvidenceBackedValue<EnvironmentType> {
        let uncertain = environment == .otherUncertain
        return EvidenceBackedValue(
            value: environment,
            confidence: uncertain
                ? .unknown
                : ContextConfidence(value: 0.5, level: .low),
            evidenceIDs: uncertain ? [] : ["scan.environment"],
            origin: uncertain ? .unknown : .runtimeInferred,
            confirmationState: uncertain ? .uncertain : .proposed
        )
    }

    private static func environmentType(from rawValue: String?) -> EnvironmentType {
        switch rawValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() {
        case "home": return .home
        case "office": return .office
        case "closet": return .closet
        case "bedroom": return .bedroom
        case "store", "retail store": return .retailStore
        case "dressing room": return .dressingRoom
        case "school": return .school
        case "gym": return .gym
        case "beach": return .beach
        case "outdoor", "outdoors": return .outdoors
        case "parking garage": return .parkingGarage
        case "event venue", "wedding venue": return .eventVenue
        case "place of worship": return .placeOfWorship
        default: return .otherUncertain
        }
    }

    private static func makeEvidence(
        _ input: ContextInferenceInput
    ) -> [ContextEvidence] {
        var values: [ContextEvidence] = []
        if let style = input.detectedStyle,
           !style.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            values.append(evidence(
                id: "scan.detectedStyle",
                kind: .visualStyle,
                summary: "Detected visual style is available.",
                confidence: 0.5,
                origin: .scanAuthoritative
            ))
        }
        if input.garmentCategory != .otherUncertain {
            values.append(evidence(
                id: "scan.garmentCategory",
                kind: .garmentSilhouette,
                summary: "Authoritative garment category is available.",
                confidence: input.garmentCategoryConfidence,
                origin: input.garmentCategoryOrigin
            ))
        }
        let grouped = Dictionary(grouping: input.evidence, by: \.kind)
        for kind in grouped.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let confidence = grouped[kind]?.map(\.confidence).max() else {
                continue
            }
            values.append(evidence(
                id: "scan.classification.\(kind.rawValue)",
                kind: kind,
                summary: summary(for: kind),
                confidence: confidence,
                origin: .scanAuthoritative
            ))
        }
        if input.selectedOccasion != .otherUncertain {
            values.append(evidence(
                id: "scan.selectedOccasion",
                kind: .selectedOccasion,
                summary: "Selected occasion evidence is available.",
                confidence: 1,
                origin: input.selectedOccasionOrigin
            ))
        }
        if environmentType(from: input.environmentLabel) != .otherUncertain {
            values.append(evidence(
                id: "scan.environment",
                kind: .environment,
                summary: "Physical environment evidence is available.",
                confidence: 0.5,
                origin: .runtimeInferred
            ))
        }
        if input.weather.hasEvidence {
            values.append(evidence(
                id: "scan.weather",
                kind: .weather,
                summary: "Typed weather evidence is available.",
                confidence: input.weather.confidence.value,
                origin: .scanAuthoritative
            ))
        }
        return Dictionary(uniqueKeysWithValues: values.map { ($0.id, $0) })
            .values
            .sorted { $0.id < $1.id }
    }

    private static func evidence(
        id: String,
        kind: ContextEvidenceKind,
        summary: String,
        confidence: Double,
        origin: ContextValueOrigin
    ) -> ContextEvidence {
        ContextEvidence(
            id: id,
            kind: kind,
            summary: summary,
            confidence: boundedConfidence(confidence),
            origin: origin
        )
    }

    private static func summary(for kind: ContextEvidenceKind) -> String {
        switch kind {
        case .visualStyle:
            return "Detected visual style is available."
        case .garmentSilhouette:
            return "Garment silhouette evidence is present."
        case .garmentConstruction:
            return "Garment construction evidence is present."
        case .textPresence:
            return "Readable text evidence is present; raw text is not retained."
        case .brandingPresence:
            return "Generic branding evidence is present; brand identity is not retained."
        case .selectedOccasion:
            return "Selected occasion evidence is available."
        case .environment:
            return "Physical environment evidence is available."
        case .weather:
            return "Typed weather evidence is available."
        case .safety:
            return "Garment construction evidence is present."
        case .uncertainty:
            return "Classification contains explicit uncertainty."
        }
    }

    private static func missingEvidence(
        input: ContextInferenceInput,
        purpose: EvidenceBackedValue<OutfitPurpose>,
        workplace: EvidenceBackedValue<WorkplaceProfile>,
        environment: EnvironmentType,
        safety: SafetySuitability
    ) -> [MissingContextEvidence] {
        var values: [MissingContextEvidence] = []
        if input.detectedStyle?
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            values.append(missing(
                "missing.detectedStyle",
                .visualStyle,
                "No detected visual style is available."
            ))
        }
        if input.garmentCategory == .otherUncertain {
            values.append(missing(
                "missing.garmentCategory",
                .garmentCategory,
                "No supported garment category is available."
            ))
        }
        if purpose.value == .otherUncertain {
            values.append(missing(
                "missing.purpose",
                .purpose,
                "No supported outfit purpose is available."
            ))
        }
        if input.selectedOccasion == .otherUncertain {
            values.append(missing(
                "missing.occasion",
                .occasion,
                "No selected occasion is available."
            ))
        }
        if workplace.value == .otherUncertain {
            values.append(missing(
                "missing.workplaceProfile",
                .workplaceProfile,
                "No supported workplace profile is available."
            ))
        }
        if environment == .otherUncertain {
            values.append(missing(
                "missing.environment",
                .environment,
                "No supported physical environment is available."
            ))
        }
        if !input.weather.hasEvidence {
            values.append(missing(
                "missing.weather",
                .weather,
                "No typed weather evidence is available."
            ))
        }
        if safety.level == .uncertain {
            values.append(missing(
                "missing.safety",
                .safety,
                "Safety requirements are not verifiable from this scan."
            ))
        }
        if purpose.value != .otherUncertain,
           PurposeClassifier.isSpecialized(purpose.value),
           purpose.confirmationState != .confirmed {
            values.append(missing(
                "missing.confirmation.\(purpose.value.rawValue)",
                .purpose,
                "The specialized purpose requires user confirmation."
            ))
        }
        return Dictionary(uniqueKeysWithValues: values.map { ($0.id, $0) })
            .values
            .sorted { $0.id < $1.id }
    }

    private static func missing(
        _ id: String,
        _ kind: MissingContextKind,
        _ reason: String
    ) -> MissingContextEvidence {
        MissingContextEvidence(id: id, kind: kind, reason: reason)
    }

    private static func aggregateConfidence(
        input: ContextInferenceInput,
        purpose: PurposeResolution,
        workplace: EvidenceBackedValue<WorkplaceProfile>,
        environment: EnvironmentType,
        suitability: SuitabilityResolution
    ) -> ContextConfidence {
        var values: [Double] = [
            input.garmentCategoryConfidence,
            purpose.value.confidence.value
        ]
        if workplace.value != .otherUncertain {
            values.append(workplace.confidence.value)
        }
        if environment != .otherUncertain {
            values.append(0.5)
        }
        if suitability.occasion.level != .uncertain {
            values.append(suitability.occasion.confidence.value)
        }
        let base = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
        let conflictPenalty = Double(
            purpose.candidates.first?.conflictingEvidenceIDs.count ?? 0
        ) * 0.10
        return boundedConfidence(max(0, base - conflictPenalty))
    }

    private static func provenance(
        input: ContextInferenceInput,
        purpose: EvidenceBackedValue<OutfitPurpose>,
        workplace: EvidenceBackedValue<WorkplaceProfile>,
        environment: EnvironmentType,
        confidence: ContextConfidence
    ) -> ContextProvenance {
        let values: [(ContextProvenanceField, ContextValueOrigin)] = [
            (.detectedStyle, input.detectedStyle == nil ? .unknown : .scanAuthoritative),
            (.garmentCategory, input.garmentCategoryOrigin),
            (.outfitPurpose, purpose.origin),
            (.selectedOccasion, input.selectedOccasion == .otherUncertain ? .unknown : input.selectedOccasionOrigin),
            (.workplaceProfile, workplace.origin),
            (.environment, environment == .otherUncertain ? .unknown : .runtimeInferred),
            (.weather, input.weather.hasEvidence ? .scanAuthoritative : .unknown),
            (.safety, .runtimeInferred),
            (.scoringProfile, purpose.value == .otherUncertain ? .unknown : .runtimeInferred),
            (.occasionCompatibility, .runtimeInferred),
            (.workplaceSuitability, .runtimeInferred),
            (.weatherSuitability, .runtimeInferred),
            (.safetySuitability, .runtimeInferred),
            (.overallConfidence, confidence.value == 0 ? .unknown : .runtimeInferred)
        ]
        return ContextProvenance(
            algorithmVersion: algorithmVersion,
            adapterVersion: nil,
            sourceScanID: input.scanID,
            sourceCompletedAt: input.completedAt,
            legacyFallbackUsed: false,
            entries: values.map {
                ContextProvenanceEntry(
                    field: $0.0,
                    source: $0.1,
                    recordedAt: input.completedAt
                )
            }
        )
    }

    private static func scoringProfile(
        for purpose: OutfitPurpose
    ) -> PurposeScoringProfile {
        PurposeScoringProfile(rawValue: purpose.rawValue) ?? {
            switch purpose {
            case .gymTraining: return .gymTraining
            case .everydayCasual: return .everydayCasual
            case .formalEvent: return .formalEvent
            case .otherUncertain: return .uncertain
            default: return .uncertain
            }
        }()
    }

    private static func boundedConfidence(_ value: Double) -> ContextConfidence {
        let bounded = min(1, max(0, value))
        return ContextConfidence(
            value: bounded,
            level: bounded >= 0.82 ? .high : (bounded >= 0.55 ? .medium : .low)
        )
    }
}
