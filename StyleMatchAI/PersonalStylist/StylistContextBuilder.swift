import Foundation

enum StyleMatchAIGuardrails {
    static let scoreIntegrityInstruction = "Personalize only; never change StyleMatch Pro scores."
    static let directOpenAIStylistSystemInstruction = """
    You are the live AI fashion assistant inside Style Match Pro.
    Use app-provided facts, style memory, weather, and fashion rules to give accurate outfit advice.
    \(scoreIntegrityInstruction)
    Answer the customer's exact message instead of repeating a generic outfit response.
    For scan follow-up chats, use the previous outfit analysis in app context as screen awareness and answer conversationally, not as JSON.
    Give specific, actionable recommendations with actual brand names, product types, stores, price ranges, or closet-item ideas when relevant.
    Only use garment colors and clothing items provided by StyleMatch Pro. Ignore background colors from walls, floors, doors, cabinets, furniture, appliances, or non-worn objects.
    If the customer greets you, greet them naturally.
    If the customer asks what you know about them, only use the StyleMatch Pro profile, closet, weather, and saved scans below. Do not invent personal details.
    If the current request asks for JSON only, return valid JSON only and do not include conversational text.
    Keep answers helpful, confidence-building, culturally respectful, and shopping-aware. Do not mention technical setup details.
    """
}

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
        screenContext: StylistScreenContext? = nil,
        memoryLimit: Int = 10
    ) -> ChatContext {
        let profile = ProfileStore(defaults: defaults).currentProfile
        let memories = OutfitMemoryStore(defaults: defaults).memories
        return chatContext(
            profile: profile,
            outfitMemories: memories,
            scoreBreakdown: scoreBreakdown,
            screenContext: screenContext,
            memoryLimit: memoryLimit
        )
    }

    static func chatContext(
        profile: StylistProfile,
        outfitMemories: [OutfitMemory],
        scoreBreakdown: String? = nil,
        screenContext: StylistScreenContext? = nil,
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
            scoreBreakdown: scoreBreakdown,
            screenContext: screenContext
        )
    }

    static func conversationalStylistContext(
        screenContext: StylistScreenContext = .aiTab()
    ) -> ChatContext {
        ChatContext(
            profileSummary: """
            Conversational Personal Stylist Phase 3C context.
            Use only the user's current message and any explicit scan facts provided in this request.
            For outfit-combination requests, give concise options with top, bottom, shoes, optional layer/accessories, colors, occasion/formality, and why it works.
            Keep any user-provided anchor item fixed unless they ask for replacements.
            Label items as From this scan, From your closet, Suggested addition, or General styling idea only when that source is explicit.
            Do not change, recalculate, or reinterpret StyleMatch Pro scores.
            Do not use appearance, complexion, undertone, body-shape, weight, BMI, race, ethnicity, attractiveness, hidden profile, or deleted profile data.
            """,
            recentOutfits: outfitCombinationGuidance,
            scoreBreakdown: nil,
            screenContext: screenContext
        )
    }

    static func scanStylistContext(
        for analysis: OutfitAnalysisResult,
        screenContext: StylistScreenContext? = nil,
        authoritativeScan: StylistAuthoritativeScanContext? = nil
    ) -> ChatContext {
        let garments = compactList(analysis.safeDetectedClothingItems, fallback: "outfit")
        let colors = compactList(analysis.colorPalette, fallback: "")
        let colorText = colors.isEmpty ? "not confidently available" : colors
        let breakdown = analysis.scoreBreakdown?.stylistChatSummary

        let context = ChatContext(
            profileSummary: """
            Conversational Personal Stylist Phase 3C scan context.
            Use only these selected scan facts and the user's message.
            For outfit-combination requests, give concise options with top, bottom, shoes, optional layer/accessories, colors, occasion/formality, and why it works.
            Preserve scan-derived items unless the user asks for replacements, and label them From this scan rather than owned.
            If color or garment detection seems uncertain, say so and ask which shade/item is closer.
            Do not change, recalculate, or reinterpret StyleMatch Pro scores.
            Do not use appearance, complexion, undertone, body-shape, weight, BMI, race, ethnicity, attractiveness, hidden profile, or deleted profile data.
            """,
            activeScan: """
            Selected scan: score \(analysis.score)/100; detected garments: \(garments); garment colors: \(colorText); detected style: \(analysis.outfitDescription); occasion/formality: \(analysis.occasionFit), \(analysis.formality); image quality: \(analysis.imageQuality).
            \(outfitCombinationGuidance)
            """,
            scoreBreakdown: breakdown.map { "Existing score only: \($0)" },
            screenContext: screenContext,
            authoritativeScan: authoritativeScan
        )
        return authoritativeScan.map(context.applyingAuthoritativeScan) ?? context
    }

    private static let outfitCombinationGuidance = """
    Outfit combinations: support one or three options, casual/smart/business/elevated/minimal/bold/warm/cool/day/evening modes when requested or implied. Use garment-color reasoning only: neutrals, contrast, warm/cool balance, saturation, earth tones, accent colors, shoe/belt coordination, pattern scale, and fabric/season. Common colors include black, white, cream, gray, charcoal, navy, light blue, olive, khaki, tan, brown, burgundy, rust, red, green, pastels, and denim washes. Never claim ownership, fit guarantee, brand, price, inventory, appearance-based color match, or body effect unless supplied by the user.
    """

    static func promptSection(
        title: String = "PERSONAL STYLIST CONTEXT",
        profile: StylistProfile,
        recentMemories: [OutfitMemory],
        maxMemories: Int = 10,
        currentOccasion: Occasion? = nil
    ) -> String {
        let context = buildContext(
            profile: profile,
            recentMemories: recentMemories,
            maxMemories: maxMemories,
            currentOccasion: currentOccasion
        )
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
        maxMemories: Int = 10,
        currentOccasion: Occasion? = nil
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
        if profile.preferredFit.isSet {
            lines.append("- Preferred overall fit: \(profile.preferredFit.rawValue)")
        }
        if profile.preferredPantFit.isSet {
            lines.append("- Preferred pant fit: \(profile.preferredPantFit.displayName)")
        }
        let pantRise = PantRisePreference.normalized(profile.preferredPantRise)
        if pantRise != "No Preference" {
            lines.append("- Preferred pant rise: \(pantRise)")
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
        lines.append(contentsOf: occasionContextLines(
            recentMemories: Array(recentMemories.prefix(memoryCount)),
            currentOccasion: currentOccasion
        ))

        guard !lines.isEmpty else {
            return ""
        }

        return (["User style context:"] + lines + [
            StyleMatchAIGuardrails.scoreIntegrityInstruction,
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

    static func buildScanUpgradePrompt(
        score: Int,
        tier: String,
        breakdown: [String: Int],
        garments: [String],
        colors: [String],
        patterns: [String],
        fitAssessment: String,
        weatherFacts: [String],
        historyFacts: [String],
        guardrails: [String],
        budget: Int = ScanUpgradePrompt.maximumUTF16Count
    ) -> ScanUpgradePrompt {
        ScanUpgradePrompt.build(
            instruction: ScanUpgradePrompt.initialAdviceInstruction,
            score: score,
            tier: tier,
            breakdown: breakdown,
            garments: garments,
            colors: colors,
            patterns: patterns,
            fitAssessment: fitAssessment,
            evidenceFacts: [],
            weatherFacts: weatherFacts,
            historyFacts: historyFacts,
            guardrails: guardrails,
            budget: budget
        )
    }

    static func buildScanFollowUpPrompt(
        question: String,
        score: Int,
        tier: String,
        breakdown: [String: Int],
        garments: [String],
        colors: [String],
        patterns: [String],
        fitAssessment: String,
        evidenceFacts: [String],
        weatherFacts: [String],
        historyFacts: [String],
        guardrails: [String],
        budget: Int = ScanUpgradePrompt.maximumUTF16Count
    ) -> ScanUpgradePrompt {
        let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let instruction = """
        Answer the user's follow-up conversationally using only the completed StyleMatch scan facts below. Give specific, practical advice without claiming visual access beyond those facts. Keep the completed score objective and separate from personalized advice.
        USER QUESTION:
        \(trimmedQuestion)
        """
        return ScanUpgradePrompt.build(
            instruction: instruction,
            score: score,
            tier: tier,
            breakdown: breakdown,
            garments: garments,
            colors: colors,
            patterns: patterns,
            fitAssessment: fitAssessment,
            evidenceFacts: evidenceFacts,
            weatherFacts: weatherFacts,
            historyFacts: historyFacts,
            guardrails: guardrails,
            budget: budget
        )
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
            let occasion = memory.occasion?.canonical.map { " for \($0.displayName.lowercased())" } ?? ""
            let reason = clean(memory.dislikeReason?.displayName ?? "", fallback: "")
            let reasonText = reason.isEmpty ? "" : ", reason \(reason)"
            return "\(parts.joined(separator: ", "))\(occasion), \(memory.styleScore)/100\(reasonText)"
        }.joined(separator: "; ")

        return summary.isEmpty ? nil : summary
    }

    static func occasionContextLines(
        recentMemories: [OutfitMemory],
        currentOccasion: Occasion?,
        maxCharacters: Int? = nil
    ) -> [String] {
        var lines: [(key: String, value: String)] = []
        if let feedback = feedbackSummary(recentMemories) {
            lines.append(("Feedback signals", feedback))
        }
        if let trend = occasionSignals(recentMemories) {
            lines.append(("Occasion patterns", trend))
        }
        if let occasion = currentOccasion?.canonical {
            lines.append(("Current scan occasion", "The user tagged this outfit for: \(occasion.displayName)."))
        }

        func rendered(_ values: [(key: String, value: String)]) -> [String] {
            values.map { "- \($0.key): \($0.value)" }
        }

        guard let maxCharacters else {
            return rendered(lines)
        }

        var trimmed = lines
        let dropOrder = ["Occasion patterns", "Feedback signals", "Current scan occasion"]
        for key in dropOrder {
            if rendered(trimmed).joined(separator: "\n").count <= maxCharacters {
                break
            }
            if let index = trimmed.firstIndex(where: { $0.key == key }) {
                trimmed.remove(at: index)
            }
        }

        return rendered(trimmed)
    }

    static func occasionSignals(_ memories: [OutfitMemory]) -> String? {
        let canonicalMemories = memories.compactMap { memory -> (occasion: Occasion, memory: OutfitMemory)? in
            guard let occasion = memory.occasion?.canonical else { return nil }
            return (occasion, memory)
        }

        let occasionCounts = Dictionary(grouping: canonicalMemories.map(\.occasion)) { $0 }
            .mapValues(\.count)
            .sorted { first, second in
                if first.value == second.value {
                    return first.key.displayName < second.key.displayName
                }
                return first.value > second.value
            }
        let countSummary = occasionCounts
            .prefix(3)
            .map { "\($0.key.displayName.lowercased()) \($0.value)x" }

        let trendSentence: String?
        if let top = occasionCounts.first {
            let summary = countSummary.isEmpty ? "\(top.key.displayName.lowercased()) \(top.value)x" : countSummary.joined(separator: ", ")
            trendSentence = "Most of the user's recent scans are tagged \(top.key.displayName) (\(summary))."
        } else {
            trendSentence = nil
        }

        let dislikedReasons = canonicalMemories.map(\.memory)
            .filter { $0.wasLiked == false }
            .compactMap { memory -> String? in
                guard let occasion = memory.occasion?.canonical,
                      let reason = memory.dislikeReason?.displayName else {
                    return nil
                }

                return "\(occasion.displayName.lowercased()) disliked for \(reason.lowercased())"
            }
            .prefix(3)

        var parts: [String] = []
        if let trendSentence {
            parts.append(trendSentence)
        } else if !countSummary.isEmpty {
            parts.append(countSummary.joined(separator: ", "))
        }
        if !dislikedReasons.isEmpty {
            parts.append(dislikedReasons.joined(separator: "; "))
        }

        return parts.isEmpty ? nil : parts.joined(separator: "; ")
    }

    static func feedbackSummary(_ memories: [OutfitMemory], maxCharacters: Int = 220) -> String? {
        let feedbackMemories = memories
            .filter { memory in
                memory.feedback != nil
                    || memory.wasWorn != nil
                    || memory.wasLiked != nil
                    || memory.dislikeReason != nil
                    || memory.timesWorn > 0
            }
            .sorted { $0.scanDate > $1.scanDate }

        guard !feedbackMemories.isEmpty else {
            return nil
        }

        let lovedCount = feedbackMemories.filter { $0.feedback?.verdict == .loved || $0.wasLiked == true }.count
        let likedCount = feedbackMemories.filter { $0.feedback?.verdict == .liked }.count
        let notForMeCount = feedbackMemories.filter { $0.feedback?.verdict == .notForMe || $0.wasLiked == false }.count
        let wornCount = feedbackMemories.filter { $0.feedback?.woreIt == true || $0.wasWorn == true || $0.timesWorn > 0 }.count

        var parts: [String] = []
        if lovedCount > 0 {
            parts.append("loved \(lovedCount)")
        }
        if likedCount > 0 {
            parts.append("liked \(likedCount)")
        }
        if notForMeCount > 0 {
            parts.append("not for me \(notForMeCount)")
        }
        if wornCount > 0 {
            parts.append("wore \(wornCount)")
        }
        let reasonSignals = Dictionary(grouping: feedbackMemories.compactMap(\.dislikeReason), by: { $0 })
            .mapValues(\.count)
            .sorted { first, second in
                if first.value == second.value {
                    return first.key.rawValue < second.key.rawValue
                }
                return first.value > second.value
            }
            .prefix(3)
            .map { "\($0.key.displayName.lowercased()) \($0.value)x" }
        if !reasonSignals.isEmpty {
            parts.append("dislike reasons: \(reasonSignals.joined(separator: ", "))")
        }

        let styleSignals = Dictionary(grouping: feedbackMemories, by: { memory in
            clean(memory.detectedStyle, fallback: "outfit").lowercased()
        })
        .mapValues { memories in
            memories.compactMap { feedbackVerdict(for: $0) }.reduce(into: [OutfitFeedback.Verdict: Int]()) { counts, verdict in
                counts[verdict, default: 0] += 1
            }
        }
        .sorted { first, second in
            let firstTotal = first.value.values.reduce(0, +)
            let secondTotal = second.value.values.reduce(0, +)
            if firstTotal == secondTotal {
                return first.key < second.key
            }
            return firstTotal > secondTotal
        }
        .prefix(2)
        .compactMap { style, counts -> String? in
            guard !style.isEmpty else { return nil }
            if let count = counts[.notForMe], count > 0 {
                return "\(style) not for me \(count)x"
            }
            if let count = counts[.loved], count > 0 {
                return "\(style) loved \(count)x"
            }
            if let count = counts[.liked], count > 0 {
                return "\(style) liked \(count)x"
            }
            return nil
        }

        let occasionSignals = Dictionary(grouping: feedbackMemories.compactMap { memory -> (Occasion, OutfitFeedback.Verdict)? in
            guard let occasion = memory.occasion?.canonical,
                  let verdict = feedbackVerdict(for: memory) else {
                return nil
            }
            return (occasion, verdict)
        }, by: { $0.0 })
            .mapValues { values in
                values.reduce(into: [OutfitFeedback.Verdict: Int]()) { counts, value in
                    counts[value.1, default: 0] += 1
                }
            }
            .sorted { first, second in
                let firstTotal = first.value.values.reduce(0, +)
                let secondTotal = second.value.values.reduce(0, +)
                if firstTotal == secondTotal {
                    return first.key.displayName < second.key.displayName
                }
                return firstTotal > secondTotal
            }
            .prefix(2)
            .compactMap { occasion, counts -> String? in
                if let count = counts[.notForMe], count > 0 {
                    return "\(occasion.displayName.lowercased()) not for me \(count)x"
                }
                if let count = counts[.loved], count > 0 {
                    return "\(occasion.displayName.lowercased()) loved \(count)x"
                }
                if let count = counts[.liked], count > 0 {
                    return "\(occasion.displayName.lowercased()) liked \(count)x"
                }
                return nil
            }

        let summary = ([parts.joined(separator: ", ")] + styleSignals + occasionSignals)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "; ")

        guard !summary.isEmpty else {
            return nil
        }

        if summary.count <= maxCharacters {
            return summary
        }

        let end = summary.index(summary.startIndex, offsetBy: max(0, maxCharacters - 1))
        return String(summary[..<end]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    private static func feedbackVerdict(for memory: OutfitMemory) -> OutfitFeedback.Verdict? {
        if let verdict = memory.feedback?.verdict {
            return verdict
        }
        if memory.wasLiked == true {
            return .loved
        }
        if memory.wasLiked == false {
            return .notForMe
        }
        return nil
    }

    private static func sizeSummary(_ sizes: ClothingSizes) -> String? {
        func line(_ label: String, _ value: String?) -> String? {
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else {
                return nil
            }
            return "\(label) \(value)"
        }

        let values = [
            line("shirt", sizes.shirtSize),
            line("pants", sizes.pantSize),
            line("shoes", sizes.shoeSize),
            line("jacket", sizes.jacketSize),
            line("dress", sizes.dressSize)
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

struct ScanUpgradePrompt: Equatable {
    static let maximumUTF16Count = 1_800
    static let initialAdviceInstruction = "Explain this fixed StyleMatch score and give 2-3 practical tips. Use only these facts. Return JSON with score_reasoning, strengths, and improvement_tips."
    static let immutableGuardrails = [
        "<85% garment confidence=uncertain/not fact; ignore background/non-worn; object-only/non-outfit=ask worn photo; insufficient/unrecognized=admit, invent no garment/color/fit/occasion/reason; sleepwear/lounge=home, not work/professional/business casual; occasion needs evidence; no casual-to-business upgrade; weather specifics need high confidence else general; hot=no heavy layers/jackets/blazers/coats/sweaters unless supported/asked; validate profile/budget/closet/weather/outfit facts, omit conflicts/unknowns; final=factual/practical/consistent/nonduplicate/weather-safe; fixed scores: explain only, no recompute/reinterpret/change/contradict; scan facts only, no visual-inspection/unsupported claims"
    ]

    let message: String
    let retainedHistoryCount: Int
    let retainedWeatherCount: Int
    let outfitWasTrimmed: Bool

    var utf16Count: Int { message.utf16.count }

    fileprivate static func build(
        instruction: String,
        score: Int,
        tier: String,
        breakdown: [String: Int],
        garments: [String],
        colors: [String],
        patterns: [String],
        fitAssessment: String,
        evidenceFacts: [String],
        weatherFacts: [String],
        historyFacts: [String],
        guardrails: [String],
        budget: Int
    ) -> ScanUpgradePrompt {
        precondition(budget > 0)

        var retainedHistory = stableUnique(historyFacts)
        let retainedWeather = stableUnique(weatherFacts)
        var retainedEvidence = stableUnique(evidenceFacts)
        var outfit = OutfitFacts(
            garments: stableUnique(garments),
            colors: stableUnique(colors),
            patterns: stableUnique(patterns),
            fitAssessment: fitAssessment
        )
        let retainedGuardrails = stableUnique(immutableGuardrails + guardrails)
        var message = encodedMessage(
            instruction: instruction,
            score: score,
            tier: tier,
            breakdown: breakdown,
            outfit: outfit,
            evidenceFacts: retainedEvidence,
            weatherFacts: retainedWeather,
            historyFacts: retainedHistory,
            guardrails: retainedGuardrails
        )

        while message.utf16.count > budget, !retainedHistory.isEmpty {
            retainedHistory.removeFirst()
            message = encodedMessage(
                instruction: instruction,
                score: score,
                tier: tier,
                breakdown: breakdown,
                outfit: outfit,
                evidenceFacts: retainedEvidence,
                weatherFacts: retainedWeather,
                historyFacts: retainedHistory,
                guardrails: retainedGuardrails
            )
        }

        var outfitWasTrimmed = false
        while message.utf16.count > budget {
            let excess = message.utf16.count - budget
            let candidates: [(Section, Int)] = [
                (.fit, outfit.fitAssessment.utf16.count),
                (.garments, outfit.garments.joined(separator: ", ").utf16.count),
                (.patterns, outfit.patterns.joined(separator: ", ").utf16.count),
                (.evidence, retainedEvidence.joined(separator: ", ").utf16.count)
            ]
            guard let longest = candidates.max(by: { $0.1 < $1.1 }), longest.1 > 0 else {
                break
            }

            let target = max(0, longest.1 - excess - 1)
            switch longest.0 {
            case .fit:
                outfit.fitAssessment = utf16Prefix(outfit.fitAssessment, limit: target)
            case .garments:
                outfit.garments = compact(outfit.garments, limit: target)
            case .patterns:
                outfit.patterns = compact(outfit.patterns, limit: target)
            case .evidence:
                retainedEvidence = compact(retainedEvidence, limit: target)
            }
            outfitWasTrimmed = true
            message = encodedMessage(
                instruction: instruction,
                score: score,
                tier: tier,
                breakdown: breakdown,
                outfit: outfit,
                evidenceFacts: retainedEvidence,
                weatherFacts: retainedWeather,
                historyFacts: retainedHistory,
                guardrails: retainedGuardrails
            )
        }

        return ScanUpgradePrompt(
            message: message,
            retainedHistoryCount: retainedHistory.count,
            retainedWeatherCount: retainedWeather.count,
            outfitWasTrimmed: outfitWasTrimmed
        )
    }

    private enum Section {
        case fit
        case garments
        case patterns
        case evidence
    }

    private struct OutfitFacts: Codable {
        var garments: [String]
        var colors: [String]
        var patterns: [String]
        var fitAssessment: String
    }

    private struct ScoreFacts: Codable {
        let value: Int
        let tier: String
        let breakdown: [String: Int]
    }

    private struct Payload: Codable {
        let score: ScoreFacts
        let outfit: OutfitFacts
        let evidence: [String]?
        let weather: [String]
        let history: [String]
        let guardrails: [String]
    }

    private static func encodedMessage(
        instruction: String,
        score: Int,
        tier: String,
        breakdown: [String: Int],
        outfit: OutfitFacts,
        evidenceFacts: [String],
        weatherFacts: [String],
        historyFacts: [String],
        guardrails: [String]
    ) -> String {
        let payload = Payload(
            score: ScoreFacts(value: score, tier: tier, breakdown: breakdown),
            outfit: outfit,
            evidence: evidenceFacts.isEmpty ? nil : evidenceFacts,
            weather: weatherFacts,
            history: historyFacts,
            guardrails: guardrails
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(payload) else {
            return """
            \(instruction) FACTS_UNAVAILABLE:
            Verified scan context could not be encoded. Do not infer a score, garment, occasion, or weather fact.
            """
        }
        let json = String(decoding: data, as: UTF8.self)
        return "\(instruction) FACTS:\n\(json)"
    }

    private static func compact(_ values: [String], limit: Int) -> [String] {
        guard limit > 0 else { return [] }
        var result: [String] = []
        var remaining = limit
        for value in values where remaining > 0 {
            let separatorCost = result.isEmpty ? 0 : 2
            guard remaining > separatorCost else { break }
            remaining -= separatorCost
            let compacted = utf16Prefix(value, limit: remaining)
            guard !compacted.isEmpty else { break }
            result.append(compacted)
            remaining -= compacted.utf16.count
        }
        return result
    }

    private static func stableUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    private static func utf16Prefix(_ value: String, limit: Int) -> String {
        guard limit > 0, !value.isEmpty else { return "" }
        let nsValue = value as NSString
        guard nsValue.length > limit else { return value }
        var end = limit
        if end > 0 {
            let last = nsValue.character(at: end - 1)
            if (0xD800...0xDBFF).contains(last) {
                end -= 1
            }
        }
        return nsValue.substring(to: end)
    }
}

struct ScanAIFallbackPresentation: Equatable {
    static let friendlyOfflineMessage = "I’m temporarily unavailable online, but here’s my best advice based on your scan."

    let message: String
    let retryPrompt: String?

    static func completed(localAdvice: String) -> ScanAIFallbackPresentation? {
        let advice = localAdvice.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !advice.isEmpty else { return nil }
        return ScanAIFallbackPresentation(
            message: "\(friendlyOfflineMessage)\n\n\(advice)",
            retryPrompt: nil
        )
    }

    static func noAnswer(prompt: String) -> ScanAIFallbackPresentation {
        ScanAIFallbackPresentation(
            message: "I couldn’t produce a useful answer from this scan. Please try again.",
            retryPrompt: prompt
        )
    }
}

typealias StylistContextBuilder = PersonalizationContextBuilder
