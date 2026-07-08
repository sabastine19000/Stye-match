import Foundation

enum PersonalStylistAIContext {
    static func summary(defaults: UserDefaults = .standard) -> String {
        let profile = ProfileStore(defaults: defaults).currentProfile
        let memories = OutfitMemoryStore(defaults: defaults).memories
        let context = PersonalizationContextBuilder.buildContext(profile: profile, recentMemories: memories)

        return context.isEmpty
            ? "No personal stylist context is saved yet. Use generic styling guidance and do not mention missing preferences."
            : context
    }
}
