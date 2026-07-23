import Foundation

enum ContextInferenceInputFactory {
    static func make(
        authority: ScanAuthority,
        weather: WeatherContextReference? = nil,
        confirmedPurpose: ContextPurposeConfirmation? = nil,
        confirmedWorkplaceProfile: ContextWorkplaceConfirmation? = nil,
        rejectedPurposeIDs: Set<OutfitPurpose> = []
    ) -> Result<ContextInferenceInput, ScanAuthorityError> {
        guard let completedAt = authority.completedAt else {
            return .failure(.scanPartial)
        }
        return .success(ContextInferenceInput(
            scanID: authority.identity.localID.rawValue,
            contextGeneration: authority.identity.generation.contextRevision,
            completedAt: completedAt,
            analysis: authority.analysis,
            selectedOccasion: authority.selectedOccasion,
            weather: weather,
            confirmedPurpose: confirmedPurpose,
            confirmedWorkplaceProfile: confirmedWorkplaceProfile,
            rejectedPurposeIDs: rejectedPurposeIDs
        ))
    }
}
