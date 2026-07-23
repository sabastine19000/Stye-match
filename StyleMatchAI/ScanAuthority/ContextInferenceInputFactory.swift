import Foundation

enum ContextInferenceInputFactory {
    static func make(
        authority: ScanAuthority
    ) -> Result<ContextInferenceInput, ScanAuthorityError> {
        guard let completedAt = authority.completedAt else {
            return .failure(.scanPartial)
        }
        let context = authority.scanBoundContext
        return .success(ContextInferenceInput(
            scanID: authority.identity.localID.rawValue,
            recordRevision: authority.identity.generation.recordRevision,
            contextGeneration: authority.identity.generation.contextRevision,
            contextFingerprint: authority.identity.contextFingerprint,
            completedAt: completedAt,
            analysis: authority.analysis,
            selectedOccasion: authority.selectedOccasion,
            weather: context.weather,
            confirmedPurpose: context.purpose.confirmed.map {
                ContextPurposeConfirmation(
                    scanID: authority.identity.localID.rawValue,
                    purpose: $0
                )
            },
            confirmedWorkplaceProfile: context.workplace.confirmed.map {
                ContextWorkplaceConfirmation(
                    scanID: authority.identity.localID.rawValue,
                    profile: $0
                )
            },
            rejectedPurposeIDs: Set(context.purpose.rejected)
        ))
    }
}
