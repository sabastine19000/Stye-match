import Foundation

struct PersonalizationContextBuilder {
    static func promptContext(defaults: UserDefaults = .standard, memoryLimit: Int = 10) -> String {
        let profile = ProfileStore(defaults: defaults).currentProfile
        let memories = OutfitMemoryStore(defaults: defaults).memories
        return buildContext(profile: profile, recentMemories: memories, maxMemories: memoryLimit)
    }

    static func promptContext(profile: StylistProfile, outfitMemories: [OutfitMemory], memoryLimit: Int = 10) -> String {
        buildContext(profile: profile, recentMemories: outfitMemories, maxMemories: memoryLimit)
    }

    static func chatContext(
        defaults: UserDefaults = .standard,
        scoreBreakdown: String? = nil,
        memoryLimit: Int = 10
    ) -> ChatContext {
        let profile = ProfileStore(defaults: defaults).currentProfile
        let memories = OutfitMemoryStore(defaults: defaults).memories
        return chatContext(
            profile: profile,
            outfitMemories: memories,
            scoreBreakdown: scoreBreakdown,
            memoryLimit: memoryLimit
        )
    }

    static func chatContext(
        profile: StylistProfile,
        outfitMemories: [OutfitMemory],
        scoreBreakdown: String? = nil,
        memoryLimit: Int = 10
    ) -> ChatContext {
        let boundedMemoryLimit = max(0, min(memoryLimit, 10))
        let profileSummary = buildContext(
            profile: profile,
            recentMemories: outfitMemories,
            maxMemories: boundedMemoryLimit
        )
        let recentOutfits = outfitMemories
            .sorted { $0.scanDate > $1.scanDate }
            .prefix(boundedMemoryLimit)
            .map { memory in
                var parts: [String] = []
                parts.append(compactList(memory.detectedGarments, fallback: "outfit"))
                if !memory.detectedStyle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    parts.append(memory.detectedStyle)
                }
                if !memory.colors.isEmpty {
                    parts.append("colors \(compactList(memory.colors, fallback: ""))")
                }
                if memory.timesWorn > 0 {
                    parts.append("worn \(memory.timesWorn)x")
                }
                if memory.wasLiked == true {
                    parts.append("liked")
                } else if memory.wasLiked == false {
                    let reason = memory.dislikeReason?.displayName.lowercased()
                    parts.append(reason.map { "disliked: \($0)" } ?? "disliked")
                }
                return parts.joined(separator: ", ")
            }
            .filter { !$0.isEmpty }
            .joined(separator: "; ")

        return ChatContext(
            profileSummary: profileSummary,
            recentOutfits: recentOutfits,
            scoreBreakdown: scoreBreakdown
        )
    }

    static func promptSection(
        title: String = "PERSONAL STYLIST CONTEXT",
        profile: StylistProfile,
        recentMemories: [OutfitMemory],
        maxMemories: Int = 10
    ) -> String {
        let context = buildContext(profile: profile, recentMemories: recentMemories, maxMemories: maxMemories)
        guard !context.isEmpty else {
            return ""
        }

        return """
        \(title):
        \(context)
        """
    }

    static func buildContext(
        profile: StylistProfile,
        recentMemories: [OutfitMemory],
        maxMemories: Int = 10
    ) -> String {
        let topPreferences = StyleFrequencyAnalyzer.topPreferences(from: recentMemories.flatMap(\.garmentRecords))
        let memoryCount = max(0, min(maxMemories, 10))
        let likedMemories = recentMemories
            .filter { $0.wasLiked == true || $0.wouldWearAgain == true || $0.isFavorite }
            .sorted { $0.scanDate > $1.scanDate }
            .prefix(memoryCount)

        let dislikedMemories = recentMemories
            .filter { $0.wasLiked == false || $0.wouldWearAgain == false }
            .sorted { $0.scanDate > $1.scanDate }
            .prefix(memoryCount)

        var lines: [String] = []
        appendLine("Favorite colors", list(profile.favoriteColors), to: &lines)
        appendLine("Avoid colors", list(profile.dislikedColors), to: &lines)
        appendLine("Favorite brands", list(profile.favoriteBrands), to: &lines)
        if profile.preferredFit != .regular {
            lines.append("- Preferred fit: \(profile.preferredFit.rawValue)")
        }
        if isMeaningfulBudget(profile.budgetRange) {
            lines.append("- Budget: \(currency(profile.budgetRange.minPrice))-\(currency(profile.budgetRange.maxPrice))")
        }
        appendLine("Sizes", sizeSummary(profile.clothingSizes), to: &lines)
        appendLine("Learned signals", learnedSignals(profile.stylePreferencesLearned), to: &lines)
        appendLine("Most worn colors", list(topPreferences.colors), to: &lines)
        appendLine("Most worn categories", list(topPreferences.categories), to: &lines)
        appendLine("Most worn styles", list(topPreferences.styleTags), to: &lines)
        appendLine("Recently liked", memorySummary(Array(likedMemories)), to: &lines)
        appendLine("Recently disliked", memorySummary(Array(dislikedMemories)), to: &lines)
        appendLine("Occasion patterns", occasionSignals(Array(recentMemories.prefix(memoryCount))), to: &lines)

        guard !lines.isEmpty else {
            return ""
        }

        return (["User style context:"] + lines + [
            "Personalize only; never change StyleMatch Pro scores.",
            StylistMessageComposer.aiPhrasingInstruction
        ])
            .joined(separator: "\n")
    }

    static func buildPersonalStylistEnginePromptContext(_ context: PersonalStylistEngineContext) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let contextJSON: String
        if let data = try? encoder.encode(context),
           let text = String(data: data, encoding: .utf8) {
            contextJSON = text
        } else {
            contextJSON = "{}"
        }

        return """
        PERSONAL STYLIST ENGINE CONTEXT:
        \(contextJSON)

        AI SYSTEM GUARDRAILS:
        - You may only reference facts explicitly provided in the context object.
        - Do not invent weather conditions, garments, colors, dates, prices, or deals.
        - Do not modify or reinterpret the score.
        - Keep the message under 4 sentences, warm and specific.
        - \(StylistMessageComposer.aiPhrasingInstruction)
        """
    }

    static func buildShoppingRecommendationPromptContext(_ reasonFacts: ProductRecommendationReasonFacts) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let contextJSON: String
        if let data = try? encoder.encode(reasonFacts),
           let text = String(data: data, encoding: .utf8) {
            contextJSON = text
        } else {
            contextJSON = "{}"
        }

        let payload = """
        SHOPPING RECOMMENDATION REASON FACTS:
        \(contextJSON)

        AI PHRASING RULES:
        - Reword only these reason facts.
        - Do not add URLs, tracking IDs, prices, retailers, garments, colors, dates, weather, or personal details not present above.
        - Keep the reason to one short sentence.
        """

        #if DEBUG
        print("[StyleMatch Shopping ReasonFacts Debug]\n\(payload)")
        #endif

        return payload
    }

    private static func learnedSignals(_ preferences: [String: Double]) -> String? {
        let signals = preferences
            .filter { abs($0.value) >= 0.1 }
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key < rhs.key
                }
                return lhs.value > rhs.value
            }
            .prefix(8)
            .map { "\($0.key)=\(String(format: "%.2f", $0.value))" }

        return signals.isEmpty ? nil : signals.joined(separator: ", ")
    }

    private static func memorySummary(_ memories: [OutfitMemory]) -> String? {
        guard !memories.isEmpty else {
            return nil
        }

        let summary = memories.map { memory in
            var parts: [String] = []
            parts.append(compactList(memory.detectedGarments, fallback: "outfit"))
            parts.append(memory.detectedStyle)
            if !memory.colors.isEmpty {
                parts.append("colors \(compactList(memory.colors, fallback: ""))")
            }
            if memory.timesWorn > 0 {
                parts.append("worn \(memory.timesWorn)x")
            }
            let occasion = memory.occasion.map { " for \($0.displayName.lowercased())" } ?? ""
            let reason = clean(memory.dislikeReason?.displayName ?? "", fallback: "")
            let reasonText = reason.isEmpty ? "" : ", reason \(reason)"
            return "\(parts.joined(separator: ", "))\(occasion), \(memory.styleScore)/100\(reasonText)"
        }.joined(separator: "; ")

        return summary.isEmpty ? nil : summary
    }

    private static func occasionSignals(_ memories: [OutfitMemory]) -> String? {
        let occasionCounts = Dictionary(grouping: memories.compactMap(\.occasion)) { $0 }
            .mapValues(\.count)
            .filter { occasion, _ in occasion != .general && occasion != .other }
            .sorted { first, second in
                if first.value == second.value {
                    return first.key.displayName < second.key.displayName
                }
                return first.value > second.value
            }
            .prefix(3)
            .map { "\($0.key.displayName.lowercased()) \($0.value)x" }

        let dislikedReasons = memories
            .filter { $0.wasLiked == false }
            .compactMap { memory -> String? in
                guard let occasion = memory.occasion,
                      occasion != .general,
                      occasion != .other,
                      let reason = memory.dislikeReason?.displayName else {
                    return nil
                }

                return "\(occasion.displayName.lowercased()) disliked for \(reason.lowercased())"
            }
            .prefix(3)

        var parts: [String] = []
        if !occasionCounts.isEmpty {
            parts.append(occasionCounts.joined(separator: ", "))
        }
        if !dislikedReasons.isEmpty {
            parts.append(dislikedReasons.joined(separator: "; "))
        }

        return parts.isEmpty ? nil : parts.joined(separator: "; ")
    }

    private static func sizeSummary(_ sizes: ClothingSizes) -> String? {
        let values = [
            sizes.shirtSize.map { "shirt \($0)" },
            sizes.pantSize.map { "pants \($0)" },
            sizes.shoeSize.map { "shoes \($0)" },
            sizes.jacketSize.map { "jacket \($0)" },
            sizes.dressSize.map { "dress \($0)" }
        ].compactMap { $0 }

        return values.isEmpty ? nil : values.joined(separator: ", ")
    }

    private static func appendLine(_ label: String, _ value: String?, to lines: inout [String]) {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        lines.append("- \(label): \(value)")
    }

    private static func isMeaningfulBudget(_ budget: BudgetRange) -> Bool {
        let defaultMin = 50.0
        let defaultMax = 200.0
        let defaultTier = "Mid"
        return abs(budget.minPrice - defaultMin) > 0.01
            || abs(budget.maxPrice - defaultMax) > 0.01
            || budget.preferredTier.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(defaultTier) != .orderedSame
    }

    private static func list(_ values: [String]) -> String? {
        let cleaned = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return cleaned.isEmpty ? nil : cleaned.prefix(5).joined(separator: ", ")
    }

    private static func compactList(_ values: [String], fallback: String) -> String {
        let cleaned = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return cleaned.isEmpty ? fallback : cleaned.prefix(3).joined(separator: ", ")
    }

    private static func clean(_ value: String, fallback: String) -> String {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? fallback : cleaned
    }

    private static func currency(_ value: Double) -> String {
        "$\(Int(value.rounded()))"
    }
}

typealias StylistContextBuilder = PersonalizationContextBuilder
