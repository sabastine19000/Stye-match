import Foundation

enum LegacyContextAdapter {
    static let adapterVersion = "ce1-legacy-v1"
    static let algorithmVersion = "context-contract-v1"

    static func adapt(
        scanID: String,
        completedAt: Date,
        analysis: OutfitAnalysisResult,
        generation: UInt64 = 1,
        selectedOccasion explicitOccasion: Occasion? = nil,
        weatherContext: WeatherContextReference? = nil
    ) -> OutfitContextSnapshot {
        let classification = analysis.outfitClassification
        let garmentCategory = contextGarmentCategory(classification.effectiveCategory)
        let garmentIsUncertain = garmentCategory == .otherUncertain
        let garmentOrigin: ContextValueOrigin = classification.userConfirmedCategory == nil
            ? (garmentIsUncertain ? .unknown : .legacyDerived)
            : .userConfirmed
        let garmentConfirmation: ContextConfirmationState = garmentIsUncertain
            ? .uncertain
            : (classification.userConfirmedCategory == nil ? .proposed : .confirmed)
        let garmentConfidence = garmentIsUncertain
            ? ContextConfidence.unknown
            : ContextConfidence(
                value: classification.confidence,
                level: contextConfidenceLevel(classification.confidenceLevel)
            )
        let styleValue = normalizedStyle(analysis.styleBalance)
        let styleIsKnown = styleValue != "Other / Uncertain"
        let environmentValue = environmentType(from: analysis.environment)
        let occasionResolution = resolveOccasion(
            explicitOccasion: explicitOccasion,
            classificationOccasion: classification.selectedOccasion
        )
        let resolvedWeather = weatherContext ?? .unknown
        let evidence = privacySafeEvidence(from: classification.evidence)
        let missingEvidence = missingEvidence(
            styleIsKnown: styleIsKnown,
            garmentCategory: garmentCategory,
            occasion: occasionResolution.value,
            environment: environmentValue,
            hasWeather: resolvedWeather.hasEvidence
        )

        return OutfitContextSnapshot(
            schemaVersion: OutfitContextSnapshot.currentSchemaVersion,
            generation: generation,
            scanID: scanID,
            completedAt: completedAt,
            authoritativeScore: analysis.score,
            authoritativeBreakdown: analysis.scoreBreakdown,
            detectedStyle: EvidenceBackedValue(
                value: styleValue,
                confidence: styleIsKnown ? ContextConfidence(value: 0.5, level: .low) : .unknown,
                evidenceIDs: styleIsKnown ? ["legacy.detectedStyle"] : [],
                origin: styleIsKnown ? .legacyDerived : .unknown,
                confirmationState: styleIsKnown ? .proposed : .uncertain
            ),
            garmentCategory: EvidenceBackedValue(
                value: garmentCategory,
                confidence: garmentConfidence,
                evidenceIDs: evidence.map(\.id),
                origin: garmentOrigin,
                confirmationState: garmentConfirmation
            ),
            outfitPurpose: EvidenceBackedValue(
                value: .otherUncertain,
                confidence: .unknown,
                evidenceIDs: [],
                origin: .unknown,
                confirmationState: .uncertain
            ),
            environmentType: EvidenceBackedValue(
                value: environmentValue,
                confidence: environmentValue == .otherUncertain
                    ? .unknown
                    : ContextConfidence(value: 0.5, level: .low),
                evidenceIDs: environmentValue == .otherUncertain ? [] : ["legacy.environment"],
                origin: environmentValue == .otherUncertain ? .unknown : .legacyDerived,
                confirmationState: environmentValue == .otherUncertain ? .uncertain : .proposed
            ),
            selectedOccasion: EvidenceBackedValue(
                value: occasionResolution.value,
                confidence: occasionResolution.value == .otherUncertain
                    ? .unknown
                    : ContextConfidence(value: 1, level: .high),
                evidenceIDs: occasionResolution.value == .otherUncertain ? [] : ["legacy.selectedOccasion"],
                origin: occasionResolution.origin,
                confirmationState: occasionResolution.confirmation
            ),
            occasionCompatibility: occasionCompatibility(
                from: classification.occasionCompatibility,
                hasOccasion: occasionResolution.value != .otherUncertain,
                evidenceIDs: evidence.map(\.id)
            ),
            workplaceProfile: EvidenceBackedValue(
                value: .otherUncertain,
                confidence: .unknown,
                evidenceIDs: [],
                origin: .unknown,
                confirmationState: .uncertain
            ),
            workplaceSuitability: .uncertain,
            weatherContext: resolvedWeather,
            weatherSuitability: .uncertain,
            safetyContext: .unverified,
            safetySuitability: .uncertain,
            userConfirmedPurpose: nil,
            confidence: .unknown,
            evidence: evidence,
            missingEvidence: missingEvidence,
            // A legacy garment scoring profile is not an authoritative outfit
            // purpose. CE1 therefore keeps the future purpose profile uncertain.
            scoringProfile: .uncertain,
            provenance: ContextProvenance(
                algorithmVersion: algorithmVersion,
                adapterVersion: adapterVersion,
                sourceScanID: scanID,
                sourceCompletedAt: completedAt,
                legacyFallbackUsed: true,
                entries: provenanceEntries(
                    completedAt: completedAt,
                    styleIsKnown: styleIsKnown,
                    garmentOrigin: garmentOrigin,
                    occasionOrigin: occasionResolution.origin,
                    environmentIsKnown: environmentValue != .otherUncertain,
                    weatherIsKnown: resolvedWeather.hasEvidence,
                    scoringProfileIsKnown: false
                )
            )
        )
    }

    private static func normalizedStyle(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Other / Uncertain" : String(trimmed.prefix(120))
    }

    private static func contextConfidenceLevel(
        _ value: OutfitClassificationConfidence
    ) -> ContextConfidenceLevel {
        switch value {
        case .high: return .high
        case .medium: return .medium
        case .low: return .low
        }
    }

    private static func contextGarmentCategory(
        _ value: OutfitCategory
    ) -> ContextGarmentCategory {
        ContextGarmentCategory(rawValue: value.rawValue) ?? .otherUncertain
    }

    private static func resolveOccasion(
        explicitOccasion: Occasion?,
        classificationOccasion: String?
    ) -> (
        value: ContextOccasion,
        origin: ContextValueOrigin,
        confirmation: ContextConfirmationState
    ) {
        if let explicitOccasion {
            return (
                contextOccasion(explicitOccasion),
                .userConfirmed,
                .confirmed
            )
        }
        if let legacyOccasion = Occasion(label: classificationOccasion) {
            return (
                contextOccasion(legacyOccasion),
                .legacyDerived,
                .proposed
            )
        }
        return (.otherUncertain, .unknown, .uncertain)
    }

    private static func contextOccasion(_ value: Occasion) -> ContextOccasion {
        switch value {
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

    private static func environmentType(from rawValue: String) -> EnvironmentType {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
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
        case "church", "place of worship": return .placeOfWorship
        default: return .otherUncertain
        }
    }

    private static func occasionCompatibility(
        from legacyValue: OutfitOccasionCompatibility,
        hasOccasion: Bool,
        evidenceIDs: [String]
    ) -> OccasionCompatibility {
        guard hasOccasion else {
            return .uncertain
        }
        let level: SuitabilityLevel
        switch legacyValue {
        case .compatible: level = .high
        case .possible: level = .moderate
        case .conflict: level = .low
        case .uncertain: level = .uncertain
        }
        return OccasionCompatibility(
            level: level,
            confidence: level == .uncertain
                ? .unknown
                : ContextConfidence(value: 0.5, level: .low),
            supportingEvidenceIDs: level == .high || level == .moderate ? evidenceIDs : [],
            conflictingEvidenceIDs: level == .low ? evidenceIDs : [],
            missingEvidenceIDs: level == .uncertain ? ["occasionCompatibility"] : [],
            summary: "Legacy occasion compatibility was preserved without recalculation."
        )
    }

    private static func privacySafeEvidence(
        from legacyEvidence: [OutfitClassificationEvidence]
    ) -> [ContextEvidence] {
        legacyEvidence.enumerated().map { index, item in
            let kind: ContextEvidenceKind
            let summary: String
            switch item.kind {
            case .silhouette:
                kind = .garmentSilhouette
                summary = "Legacy garment silhouette evidence is present."
            case .construction:
                kind = .garmentConstruction
                summary = "Legacy garment construction evidence is present."
            case .visibleText:
                kind = .textPresence
                summary = "Readable garment text evidence was recorded; raw text is not retained."
            case .branding:
                kind = .brandingPresence
                summary = "Generic branding-presence evidence was recorded; no identity is retained."
            case .occasion:
                kind = .selectedOccasion
                summary = "Legacy occasion evidence is present."
            case .accessory:
                kind = .garmentSilhouette
                summary = "Legacy accessory evidence is present."
            case .uncertainty:
                kind = .uncertainty
                summary = "Legacy classification contains explicit uncertainty."
            }
            return ContextEvidence(
                id: "legacy.\(item.kind.rawValue).\(index)",
                kind: kind,
                summary: summary,
                confidence: ContextConfidence(
                    value: item.confidence,
                    level: item.confidence >= 0.82 ? .high : (item.confidence >= 0.55 ? .medium : .low)
                ),
                origin: .legacyDerived
            )
        }
    }

    private static func missingEvidence(
        styleIsKnown: Bool,
        garmentCategory: ContextGarmentCategory,
        occasion: ContextOccasion,
        environment: EnvironmentType,
        hasWeather: Bool
    ) -> [MissingContextEvidence] {
        var values: [MissingContextEvidence] = [
            MissingContextEvidence(
                id: "missing.purpose",
                kind: .purpose,
                reason: "Legacy records do not contain an authoritative outfit purpose."
            ),
            MissingContextEvidence(
                id: "missing.workplaceProfile",
                kind: .workplaceProfile,
                reason: "Legacy records do not contain an authoritative workplace profile."
            ),
            MissingContextEvidence(
                id: "missing.safety",
                kind: .safety,
                reason: "Legacy records do not contain verified safety context."
            )
        ]
        if !styleIsKnown {
            values.append(MissingContextEvidence(
                id: "missing.detectedStyle",
                kind: .visualStyle,
                reason: "No detected visual style is available."
            ))
        }
        if garmentCategory == .otherUncertain {
            values.append(MissingContextEvidence(
                id: "missing.garmentCategory",
                kind: .garmentCategory,
                reason: "No supported garment category is available."
            ))
        }
        if occasion == .otherUncertain {
            values.append(MissingContextEvidence(
                id: "missing.occasion",
                kind: .occasion,
                reason: "No selected occasion is available."
            ))
        }
        if environment == .otherUncertain {
            values.append(MissingContextEvidence(
                id: "missing.environment",
                kind: .environment,
                reason: "No supported physical environment is available."
            ))
        }
        if !hasWeather {
            values.append(MissingContextEvidence(
                id: "missing.weather",
                kind: .weather,
                reason: "No typed weather snapshot was supplied for this legacy record."
            ))
        }
        return values
    }

    private static func provenanceEntries(
        completedAt: Date,
        styleIsKnown: Bool,
        garmentOrigin: ContextValueOrigin,
        occasionOrigin: ContextValueOrigin,
        environmentIsKnown: Bool,
        weatherIsKnown: Bool,
        scoringProfileIsKnown: Bool
    ) -> [ContextProvenanceEntry] {
        [
            ContextProvenanceEntry(
                field: .detectedStyle,
                source: styleIsKnown ? .legacyDerived : .unknown,
                recordedAt: completedAt
            ),
            ContextProvenanceEntry(
                field: .garmentCategory,
                source: garmentOrigin,
                recordedAt: completedAt
            ),
            ContextProvenanceEntry(
                field: .outfitPurpose,
                source: .unknown,
                recordedAt: completedAt
            ),
            ContextProvenanceEntry(
                field: .selectedOccasion,
                source: occasionOrigin,
                recordedAt: completedAt
            ),
            ContextProvenanceEntry(
                field: .workplaceProfile,
                source: .unknown,
                recordedAt: completedAt
            ),
            ContextProvenanceEntry(
                field: .environment,
                source: environmentIsKnown ? .legacyDerived : .unknown,
                recordedAt: completedAt
            ),
            ContextProvenanceEntry(
                field: .weather,
                source: weatherIsKnown ? .legacyDerived : .unknown,
                recordedAt: completedAt
            ),
            ContextProvenanceEntry(
                field: .safety,
                source: .unknown,
                recordedAt: completedAt
            ),
            ContextProvenanceEntry(
                field: .scoringProfile,
                source: scoringProfileIsKnown ? .legacyDerived : .unknown,
                recordedAt: completedAt
            )
        ]
    }
}
