import Foundation

enum ContextInferenceFailure: Error, Equatable {
    case invalidScanIdentity
    case invalidScore
    case nonFiniteConfidence
    case mismatchedPurposeConfirmation
    case mismatchedWorkplaceConfirmation
    case privacyBoundaryViolation
    case invariantViolation

    var guardID: String {
        switch self {
        case .invalidScanIdentity: return "ce2a.invalidScanIdentity"
        case .invalidScore: return "ce2a.invalidScore"
        case .nonFiniteConfidence: return "ce2a.nonFiniteConfidence"
        case .mismatchedPurposeConfirmation: return "ce2a.mismatchedPurposeConfirmation"
        case .mismatchedWorkplaceConfirmation: return "ce2a.mismatchedWorkplaceConfirmation"
        case .privacyBoundaryViolation: return "ce2a.privacyBoundaryViolation"
        case .invariantViolation: return "ce2a.invariantViolation"
        }
    }
}

enum ContextInferenceValidator {
    private static let approvedSummaries: Set<String> = [
        "Detected visual style is available.",
        "Authoritative garment category is available.",
        "Garment silhouette evidence is present.",
        "Garment construction evidence is present.",
        "Readable text evidence is present; raw text is not retained.",
        "Generic branding evidence is present; brand identity is not retained.",
        "Selected occasion evidence is available.",
        "Physical environment evidence is available.",
        "Typed weather evidence is available.",
        "Classification contains explicit uncertainty."
    ]

    static func validate(_ input: ContextInferenceInput) -> ContextInferenceFailure? {
        if input.scanID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .invalidScanIdentity
        }
        if !(0...100).contains(input.score) {
            return .invalidScore
        }
        if input.contextGeneration == 0 {
            return .invariantViolation
        }
        let confidenceValues = [input.garmentCategoryConfidence]
            + input.evidence.map(\.confidence)
            + [input.weather.confidence.value]
        if confidenceValues.contains(where: { !$0.isFinite }) {
            return .nonFiniteConfidence
        }
        if let confirmation = input.confirmedPurpose,
           confirmation.scanID != input.scanID {
            return .mismatchedPurposeConfirmation
        }
        if let confirmation = input.confirmedWorkplaceProfile,
           confirmation.scanID != input.scanID {
            return .mismatchedWorkplaceConfirmation
        }
        return nil
    }

    static func validate(
        snapshot: OutfitContextSnapshot,
        input: ContextInferenceInput
    ) -> ContextInferenceFailure? {
        guard snapshot.scanID == input.scanID,
              snapshot.authoritativeScore == input.score,
              snapshot.authoritativeBreakdown == input.scoreBreakdown,
              snapshot.generation == input.contextGeneration,
              snapshot.provenance.sourceScanID == input.scanID,
              snapshot.provenance.algorithmVersion == OutfitContextEngine.algorithmVersion,
              !snapshot.provenance.legacyFallbackUsed else {
            return .invariantViolation
        }
        if snapshot.evidence.contains(where: {
            !approvedSummaries.contains($0.summary)
        }) {
            return .privacyBoundaryViolation
        }
        if snapshot.outfitPurpose.confirmationState == .confirmed,
           snapshot.outfitPurpose.origin != .userConfirmed {
            return .invariantViolation
        }
        return nil
    }
}
