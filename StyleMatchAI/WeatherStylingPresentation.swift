import Foundation

/// A local, request-scoped handoff from Weather Styling to the existing global
/// AI Stylist. It intentionally has no persistence or transport behavior.
struct WeatherStylistRouteRequest: Equatable {
    let snapshot: WeatherSnapshot?
    let recommendation: WeatherStylingRecommendation
    let occasion: String?
    let workplace: String?

    init(
        snapshot: WeatherSnapshot?,
        recommendation: WeatherStylingRecommendation,
        occasion: String,
        workplace: String
    ) {
        self.snapshot = snapshot
        self.recommendation = recommendation
        self.occasion = Self.cleaned(occasion)
        self.workplace = Self.cleaned(workplace)
    }

    private static func cleaned(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(160))
    }
}

/// A bounded projection of a saved scan. It contains only previously saved,
/// customer-owned StyleMatch facts and never claims that a scan item is still
/// present in Closet.
struct WeatherStylingSavedScan: Equatable {
    let id: String
    let score: Int
    let detectedItems: [String]
    let colorPalette: [String]
    let occasion: String?
}

/// A bounded, account-scoped snapshot of only the profile, saved-scan, and
/// Closet facts Weather Styling is allowed to use. It deliberately does not
/// read AI Memory, chat context, or Style Friends data.
struct WeatherStylingPersonalizationInput {
    let accountID: String
    let favoriteColors: [String]
    let favoriteBrands: [String]
    let styleGoals: [String]
    let learnedPreferences: [String]
    let preferredFit: String?
    let workContext: String?
    let clothingSizes: [String]
    let closetItems: [ClosetItem]
    let savedScans: [WeatherStylingSavedScan]

    init(
        accountID: String,
        favoriteColors: [String],
        favoriteBrands: [String],
        styleGoals: [String],
        learnedPreferences: [String],
        preferredFit: String?,
        workContext: String?,
        clothingSizes: [String],
        closetItems: [ClosetItem],
        savedScans: [WeatherStylingSavedScan] = []
    ) {
        self.accountID = accountID
        self.favoriteColors = favoriteColors
        self.favoriteBrands = favoriteBrands
        self.styleGoals = styleGoals
        self.learnedPreferences = learnedPreferences
        self.preferredFit = preferredFit
        self.workContext = workContext
        self.clothingSizes = clothingSizes
        self.closetItems = closetItems
        self.savedScans = savedScans
    }

    static func current(defaults: UserDefaults = .standard) -> Self {
        let accountID = AccountScopedStorage.activePresentationUserID(defaults: defaults)
        let profile = ProfileStore(defaults: defaults, userId: accountID).currentProfile
        guard PersonalStylistStorage.normalizedUserID(profile.userId) == accountID else {
            return Self(accountID: accountID, favoriteColors: [], favoriteBrands: [], styleGoals: [], learnedPreferences: [], preferredFit: nil, workContext: nil, clothingSizes: [], closetItems: [], savedScans: [])
        }
        let context = profile.personalizationContext
        let closetItems = (defaults.data(forKey: "closetItemsData")).flatMap { try? JSONDecoder().decode([ClosetItem].self, from: $0) } ?? []
        let savedScans = ((defaults.data(forKey: "outfitScanHistoryData")).flatMap { try? JSONDecoder().decode([String: StoredOutfitScan].self, from: $0) } ?? [:])
            .map { id, scan in
                WeatherStylingSavedScan(
                    id: id,
                    score: scan.score,
                    detectedItems: scan.deterministicInputs?.detectedItems ?? [],
                    colorPalette: scan.deterministicInputs?.colorPalette ?? [],
                    occasion: scan.occasion?.rawValue
                )
            }
            .sorted { $0.id < $1.id }
        let sizes = [context.clothingSizes.shirtSize, context.clothingSizes.pantSize, context.clothingSizes.shoeSize, context.clothingSizes.jacketSize, context.clothingSizes.dressSize]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Self(
            accountID: accountID,
            favoriteColors: context.favoriteColors,
            favoriteBrands: context.favoriteBrands,
            styleGoals: context.styleGoals,
            learnedPreferences: profile.stylePreferencesLearned
                .filter { $0.value > 0 }
                .map(\.key)
                .sorted(),
            preferredFit: context.preferredFit?.rawValue,
            workContext: context.workSetting,
            clothingSizes: sizes,
            closetItems: closetItems,
            savedScans: savedScans
        )
    }

    var hasProfileEvidence: Bool {
        !favoriteColors.isEmpty || !favoriteBrands.isEmpty || !styleGoals.isEmpty || !learnedPreferences.isEmpty || preferredFit != nil || workContext != nil || !clothingSizes.isEmpty
    }
}

/// Presentation-only, deterministic input for Weather Styling. It reads the
/// canonical WeatherKit snapshot plus explicitly saved, account-scoped profile
/// and Closet values. It owns no persistence, CloudKit state, or AI conversation state.
struct WeatherStylingRecommendation: Equatable {
    enum PersonalizationTier: String, Equatable {
        case closet = "Based on your Closet"
        case savedScan = "Based on your saved outfit history"
        case profile = "Based on your style profile"
        case general = "General recommendations"
    }

    enum ItemSource: Equatable {
        case closetItem
        case savedScan
        case styleProfile
        case generalRecommendation
    }

    struct Item: Equatable, Identifiable {
        let role: String
        let title: String
        let symbol: String
        let source: ItemSource
        var id: String { role }
    }

    let contextTitle: String
    let items: [Item]
    let reasoning: [String]
    let personalizationTier: PersonalizationTier
    let personalizationExplanation: String
    let weatherMatchScore: Int?
    let weatherMatchLabel: String
    let umbrellaGuidance: String?

    static func make(
        snapshot: WeatherSnapshot?,
        occasion: String,
        favoriteColors: String,
        workplace: String = ""
    ) -> Self {
        let colors = favoriteColors.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return make(
            snapshot: snapshot,
            occasion: occasion,
            personalization: WeatherStylingPersonalizationInput(
                accountID: "guest",
                favoriteColors: colors,
                favoriteBrands: [],
                styleGoals: [],
                learnedPreferences: [],
                preferredFit: nil,
                workContext: cleaned(workplace).isEmpty ? nil : cleaned(workplace),
                clothingSizes: [],
                closetItems: [],
                savedScans: []
            )
        )
    }

    static func make(
        snapshot: WeatherSnapshot?,
        occasion: String,
        personalization: WeatherStylingPersonalizationInput
    ) -> Self {
        let occasionText = cleaned(occasion)
        let workplaceText = cleaned(personalization.workContext ?? "")
        let contextTitle = title(for: occasionText, workplace: workplaceText)
        guard let snapshot else {
            return Self(
                contextTitle: contextTitle,
                items: [
                    Item(role: "Top", title: "Choose a comfortable top", symbol: "tshirt.fill", source: .generalRecommendation),
                    Item(role: "Bottom", title: "Choose an occasion-appropriate bottom", symbol: "figure.stand", source: .generalRecommendation),
                    Item(role: "Shoes", title: "Choose footwear for your plans", symbol: "shoe.2.fill", source: .generalRecommendation)
                ],
                reasoning: ["Refresh WeatherKit weather for tailored temperature, rain, and UV guidance."],
                personalizationTier: .general,
                personalizationExplanation: "General recommendations are shown until current weather and saved style information are available.",
                weatherMatchScore: nil,
                weatherMatchLabel: "Weather Match Available After More Context",
                umbrellaGuidance: nil
            )
        }

        let feels = snapshot.feelsLikeFahrenheit
        let wind = snapshot.windMph ?? 0
        let uv = snapshot.uvIndex ?? 0
        let hot = feels >= 80
        let cold = feels <= 52
        let umbrellaAdvisory = WeatherUmbrellaAdvisory.make(snapshot: snapshot)
        // A future-rain advisory is not evidence that the user is wet now.
        let wet = snapshot.hasCurrentPrecipitation
        let safetyFootwear = workplaceText.lowercased().contains("factory")
            || workplaceText.lowercased().contains("safety")
            || workplaceText.lowercased().contains("ppe")

        let generalItems = [
            Item(role: "Top", title: hot ? "Breathable shirt or polo" : (cold ? "Long-sleeve knit or shirt" : "Comfortable shirt or polo"), symbol: "tshirt.fill", source: .generalRecommendation),
            Item(role: "Bottom", title: hot ? "Lightweight trousers or chinos" : "Comfortable trousers or jeans", symbol: "figure.stand", source: .generalRecommendation),
            Item(role: "Shoes", title: safetyFootwear ? "Safety-toe or slip-resistant footwear" : (wet ? "Water-friendly closed shoes" : "Clean closed shoes"), symbol: "shoe.2.fill", source: .generalRecommendation)
        ]
        let closetItems = closetRecommendationItems(
            from: personalization.closetItems,
            favoriteColors: personalization.favoriteColors,
            favoriteBrands: personalization.favoriteBrands,
            clothingSizes: personalization.clothingSizes,
            occasion: occasionText,
            hot: hot,
            cold: cold,
            wet: wet,
            safetyFootwear: safetyFootwear
        )
        let savedScanItems = savedScanRecommendationItems(
            from: personalization.savedScans,
            generalItems: generalItems,
            occasion: occasionText,
            safetyFootwear: safetyFootwear
        )
        let tier: PersonalizationTier
        let explanation: String
        var items: [Item]
        if closetItems.count == 3 {
            tier = .closet
            items = closetItems
            explanation = closetExplanation(items: closetItems, colors: personalization.favoriteColors, occasion: occasionText)
        } else if !savedScanItems.isEmpty {
            tier = .savedScan
            items = savedScanItems
            explanation = savedScanExplanation(items: savedScanItems, occasion: occasionText)
        } else if personalization.hasProfileEvidence {
            tier = .profile
            items = profileRecommendationItems(
                generalItems: generalItems,
                colors: personalization.favoriteColors,
                preferredFit: personalization.preferredFit
            )
            explanation = profileExplanation(personalization: personalization, occasion: occasionText)
        } else {
            tier = .general
            items = generalItems
            explanation = "No verified Closet or saved style preferences are available, so this uses current weather and occasion only."
        }
        if cold || wind >= 18 || wet {
            items.append(Item(role: "Optional Layer", title: wet ? "Light rain layer" : "Removable light layer", symbol: "jacket.fill", source: tier == .general ? .generalRecommendation : .styleProfile))
        }
        if uv >= 7 {
            items.append(Item(role: "Accessories", title: "Sunglasses or a hat for UV protection", symbol: "sunglasses", source: .generalRecommendation))
        }

        var reasoning = ["Based on " + snapshot.condition.lowercased() + " conditions and a feels-like temperature of " + String(feels) + "°F."]
        if hot {
            let humidityText = snapshot.humidityPercent.map { " and " + String($0) + "% humidity" } ?? ""
            reasoning.append("Breathable fabrics help with the current warmth" + humidityText + ".")
        }
        if wind >= 18 { reasoning.append("Wind is " + String(wind) + " mph, so a removable layer can be practical outdoors.") }
        reasoning.append(explanation)
        if safetyFootwear { reasoning.append("Workplace safety footwear takes priority over casual shoe suggestions.") }

        let umbrellaGuidance = umbrellaAdvisory.guidance(for: snapshot)
        if let umbrellaGuidance { reasoning.append(umbrellaGuidance) }

        let score = boundedScore(snapshot: snapshot, hasOccasion: !occasionText.isEmpty, safetyFootwear: safetyFootwear, tier: tier, closetItems: closetItems, hasProfileEvidence: personalization.hasProfileEvidence)
        return Self(
            contextTitle: contextTitle,
            items: items,
            reasoning: reasoning,
            personalizationTier: tier,
            personalizationExplanation: explanation,
            weatherMatchScore: score,
            weatherMatchLabel: score == nil ? "Strong Weather Match" : matchLabel(for: score ?? 0),
            umbrellaGuidance: umbrellaGuidance
        )
    }

    private static func boundedScore(snapshot: WeatherSnapshot, hasOccasion: Bool, safetyFootwear: Bool, tier: PersonalizationTier, closetItems: [Item], hasProfileEvidence: Bool) -> Int? {
        // A numerical score is offered only when the actual weather inputs are
        // sufficiently complete. It is intentionally bounded and explainable.
        guard snapshot.rainChancePercent != nil,
              snapshot.humidityPercent != nil,
              snapshot.windMph != nil,
              snapshot.uvIndex != nil else { return nil }
        var score = 100
        if snapshot.feelsLikeFahrenheit >= 90 || snapshot.feelsLikeFahrenheit <= 32 { score -= 14 }
        if (snapshot.rainChancePercent ?? 0) >= 50 { score -= 10 }
        if (snapshot.humidityPercent ?? 0) >= 85 { score -= 6 }
        if (snapshot.windMph ?? 0) >= 22 { score -= 5 }
        if (snapshot.uvIndex ?? 0) >= 8 { score -= 3 }
        if !hasOccasion { score -= 4 }
        if safetyFootwear { score -= 2 }
        switch tier {
        case .closet:
            score += min(8, closetItems.count * 2)
        case .savedScan:
            score += 5
        case .profile:
            if hasProfileEvidence { score += 3 }
        case .general:
            score -= 6
        }
        return max(0, min(100, score))
    }

    private static func closetRecommendationItems(
        from closet: [ClosetItem],
        favoriteColors: [String],
        favoriteBrands: [String],
        clothingSizes: [String],
        occasion: String,
        hot: Bool,
        cold: Bool,
        wet: Bool,
        safetyFootwear: Bool
    ) -> [Item] {
        let roles: [(String, String, String)] = [("Top", "tshirt.fill", "top"), ("Bottom", "figure.stand", "bottom"), ("Shoes", "shoe.2.fill", "shoes")]
        return roles.compactMap { role, symbol, category in
            guard let item = closet.filter({ closetRole(for: $0) == category }).max(by: { closetScore($0, favoriteColors: favoriteColors, favoriteBrands: favoriteBrands, clothingSizes: clothingSizes, occasion: occasion, hot: hot, cold: cold, wet: wet, safetyFootwear: safetyFootwear) < closetScore($1, favoriteColors: favoriteColors, favoriteBrands: favoriteBrands, clothingSizes: clothingSizes, occasion: occasion, hot: hot, cold: cold, wet: wet, safetyFootwear: safetyFootwear) }) else { return nil }
            return Item(role: role, title: ClosetItemDisplay.displayName(for: item), symbol: symbol, source: .closetItem)
        }
    }

    private static func savedScanRecommendationItems(
        from scans: [WeatherStylingSavedScan],
        generalItems: [Item],
        occasion: String,
        safetyFootwear: Bool
    ) -> [Item] {
        let relevant = scans
            .filter { $0.score >= 60 && (!$0.detectedItems.isEmpty || !$0.colorPalette.isEmpty) }
            .filter { scan in
                guard occasion.localizedCaseInsensitiveContains("work") else { return true }
                return (scan.occasion ?? "").localizedCaseInsensitiveContains("work")
            }
            .sorted {
                let lhsMatchesOccasion = !occasion.isEmpty && ($0.occasion ?? "").localizedCaseInsensitiveContains(occasion)
                let rhsMatchesOccasion = !occasion.isEmpty && ($1.occasion ?? "").localizedCaseInsensitiveContains(occasion)
                if lhsMatchesOccasion != rhsMatchesOccasion { return lhsMatchesOccasion }
                if $0.score != $1.score { return $0.score > $1.score }
                return $0.id < $1.id
            }
        guard let scan = relevant.first else { return [] }
        let color = scan.colorPalette.first?.trimmingCharacters(in: .whitespacesAndNewlines)
        return generalItems.map { base in
            if base.role == "Shoes", safetyFootwear {
                return Item(role: base.role, title: "Safety-toe or slip-resistant footwear", symbol: base.symbol, source: .generalRecommendation)
            }
            let matched = scan.detectedItems.first { savedScanRole(for: $0) == base.role }
            let title: String
            if let matched {
                let colorPrefix = (base.role == "Top" ? color : nil).map { "\($0.capitalized) " } ?? ""
                title = "\(colorPrefix)\(matched.capitalized) inspired by a saved high-scoring outfit"
            } else if base.role == "Top", let color, !color.isEmpty {
                title = "\(color.capitalized) \(base.title.lowercased()) inspired by a saved high-scoring outfit"
            } else {
                title = "\(base.title) aligned with a saved high-scoring outfit"
            }
            return Item(role: base.role, title: title, symbol: base.symbol, source: .savedScan)
        }
    }

    private static func savedScanRole(for item: String) -> String? {
        let value = item.lowercased()
        if ["shirt", "top", "polo", "tee", "t-shirt", "blouse"].contains(where: value.contains) { return "Top" }
        if ["pants", "jeans", "trouser", "chino", "shorts", "bottom", "jogger"].contains(where: value.contains) { return "Bottom" }
        if ["shoe", "sneaker", "loafer", "boot", "sandal"].contains(where: value.contains) { return "Shoes" }
        return nil
    }

    private static func closetRole(for item: ClosetItem) -> String? {
        let value = "\(item.category) \(item.name)".lowercased()
        if ["shirt", "top", "polo", "tee", "t-shirt", "blouse"].contains(where: value.contains) { return "top" }
        if ["pants", "jeans", "trouser", "chino", "shorts", "bottom"].contains(where: value.contains) { return "bottom" }
        if ["shoe", "sneaker", "loafer", "boot", "sandal"].contains(where: value.contains) { return "shoes" }
        return nil
    }

    private static func closetScore(_ item: ClosetItem, favoriteColors: [String], favoriteBrands: [String], clothingSizes: [String], occasion: String, hot: Bool, cold: Bool, wet: Bool, safetyFootwear: Bool) -> Int {
        let text = "\(item.name) \(item.category) \(item.notes)".lowercased()
        var score = 10
        if favoriteColors.contains(where: { item.color.localizedCaseInsensitiveContains($0) || $0.localizedCaseInsensitiveContains(item.color) }) { score += 8 }
        if favoriteBrands.contains(where: { item.brand.localizedCaseInsensitiveContains($0) || $0.localizedCaseInsensitiveContains(item.brand) }) { score += 3 }
        if clothingSizes.contains(where: { $0.caseInsensitiveCompare(item.size) == .orderedSame }) { score += 3 }
        if !occasion.isEmpty, item.occasion.localizedCaseInsensitiveContains(occasion) { score += 6 }
        if hot, ["linen", "polo", "tee", "short", "light"].contains(where: text.contains) { score += 6 }
        if cold, ["wool", "knit", "long", "boot"].contains(where: text.contains) { score += 5 }
        if wet, ["boot", "water", "rain", "leather"].contains(where: text.contains) { score += 5 }
        if safetyFootwear, ["safety", "slip", "toe"].contains(where: text.contains) { score += 10 }
        return score
    }

    private static func profileRecommendationItems(generalItems: [Item], colors: [String], preferredFit: String?) -> [Item] {
        let color = colors.first?.trimmingCharacters(in: .whitespacesAndNewlines)
        return generalItems.map { item in
            var title = item.title
            if item.role == "Top", let color, !color.isEmpty { title = "\(color.capitalized) \(title.lowercased())" }
            if item.role == "Bottom", let fit = preferredFit?.trimmingCharacters(in: .whitespacesAndNewlines), !fit.isEmpty { title = "\(fit.capitalized)-fit \(title.lowercased())" }
            return Item(role: item.role, title: title, symbol: item.symbol, source: .styleProfile)
        }
    }

    private static func closetExplanation(items: [Item], colors: [String], occasion: String) -> String {
        let roles = items.map { $0.role.lowercased() }.joined(separator: ", ")
        let colorNote = colors.first.map { " and your saved \($0) color preference" } ?? ""
        let occasionNote = occasion.isEmpty ? "" : " for \(occasion.lowercased())"
        return "Based on your Closet: verified \(roles) items were ranked for today’s weather\(occasionNote)\(colorNote)."
    }

    private static func profileExplanation(personalization: WeatherStylingPersonalizationInput, occasion: String) -> String {
        var facts: [String] = []
        if let color = personalization.favoriteColors.first { facts.append("your saved \(color) color preference") }
        if let fit = personalization.preferredFit, !fit.isEmpty { facts.append("your \(fit) fit preference") }
        let workRequest = occasion.localizedCaseInsensitiveContains("work")
        if workRequest, let work = personalization.workContext, !work.isEmpty { facts.append("your saved work context") }
        let relevantPreferences = personalization.learnedPreferences.filter { preference in
            let value = preference.lowercased()
            return workRequest && ["work", "office", "factory", "ppe", "safety"].contains(where: value.contains)
        }
        if !relevantPreferences.isEmpty { facts.append("your saved work-style preferences") }
        if !occasion.isEmpty { facts.append("your \(occasion.lowercased()) occasion") }
        return facts.isEmpty ? "Based on your style profile and today’s weather." : "Based on your style profile: \(facts.joined(separator: ", "))."
    }

    private static func savedScanExplanation(items: [Item], occasion: String) -> String {
        let roles = items.filter { $0.source == .savedScan }.map { $0.role.lowercased() }.joined(separator: ", ")
        let occasionNote = occasion.isEmpty ? "" : " for \(occasion.lowercased())"
        return "Based on your saved outfit history: a previously high-scoring \(roles) combination informed today’s guidance\(occasionNote). This does not claim those items are currently in your Closet."
    }

    private static func matchLabel(for score: Int) -> String {
        switch score {
        case 90...: return "Great Match"
        case 75...: return "Strong Match"
        default: return "Weather-Aware Match"
        }
    }

    private static func title(for occasion: String, workplace: String) -> String {
        let value = "\(occasion) \(workplace)".lowercased()
        if value.contains("work") || value.contains("office") { return "Today at Work" }
        if value.contains("dinner") { return "Dinner Tonight" }
        if value.contains("weekend") { return "Weekend Casual" }
        if value.contains("outdoor") { return "Outdoor Plans" }
        return "Styled for Today"
    }

    private static func containsPrecipitation(_ condition: String) -> Bool {
        let value = condition.lowercased()
        return value.contains("rain") || value.contains("storm") || value.contains("drizzle") || value.contains("snow") || value.contains("sleet")
    }

    private static func cleaned(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Home Intelligence

/// A local, typed daily plan used by both the Home summary and its detail
/// workspaces. It deliberately consumes only already-authorized on-device
/// facts; it never treats an absent Closet record, Calendar event, or wear
/// history as a negative customer fact.
enum HomeIntelligenceFocus: String, CaseIterable, Hashable, Identifiable {
    case weather
    case calendar
    case outfitChecklist
    case laundry
    case missingPieces
    case shopping

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weather: "Weather"
        case .calendar: "Your Day"
        case .outfitChecklist: "Outfit Checklist"
        case .laundry: "Laundry"
        case .missingPieces: "Missing Pieces"
        case .shopping: "Shopping"
        }
    }

    var icon: String {
        switch self {
        case .weather: "cloud.sun.fill"
        case .calendar: "calendar"
        case .outfitChecklist: "checklist"
        case .laundry: "washer.fill"
        case .missingPieces: "plus.circle.fill"
        case .shopping: "bag.fill"
        }
    }
}

enum HomeIntelligenceEvidenceState: String, Equatable {
    case confirmed
    case inferred
    case unknown

    var label: String {
        switch self {
        case .confirmed: "Confirmed"
        case .inferred: "Suggested"
        case .unknown: "Needs your input"
        }
    }
}

enum HomeIntelligenceAction: String, CaseIterable, Hashable, Identifiable {
    case viewForecast
    case askStylist
    case buildOutfit
    case openCloset
    case openScan
    case openShop
    case enableCalendar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .viewForecast: "View Forecast"
        case .askStylist: "Ask Stylist"
        case .buildOutfit: "Build an Outfit"
        case .openCloset: "Open Closet"
        case .openScan: "Scan an Item"
        case .openShop: "Open Shop AI"
        case .enableCalendar: "Connect Calendar"
        }
    }

    var icon: String {
        switch self {
        case .viewForecast: "chart.xyaxis.line"
        case .askStylist: "sparkles"
        case .buildOutfit: "hanger"
        case .openCloset: "tshirt.fill"
        case .openScan: "camera.viewfinder"
        case .openShop: "bag.fill"
        case .enableCalendar: "calendar.badge.plus"
        }
    }
}

enum HomeIntelligenceActionPriority: String, Equatable {
    case recommendedNow
    case needsInput
    case optional
    case notRelevantNow

    var label: String {
        switch self {
        case .recommendedNow: "Recommended now"
        case .needsInput: "Needs your input"
        case .optional: "Optional"
        case .notRelevantNow: "Not relevant now"
        }
    }
}

struct HomeIntelligenceActionPlan: Equatable, Identifiable {
    let action: HomeIntelligenceAction
    let priority: HomeIntelligenceActionPriority
    let rationale: String

    var id: String { action.id }
}

struct HomeIntelligenceFact: Equatable, Identifiable {
    let text: String
    let evidence: HomeIntelligenceEvidenceState
    var id: String { "\(evidence.rawValue)-\(text)" }
}

struct HomeIntelligenceChecklistItem: Equatable, Identifiable {
    enum State: String, Equatable {
        case ready
        case needsSelection
        case notFoundInSavedCloset
        case weatherRequired
        case ppeRequired
        case unknown

        var label: String {
            switch self {
            case .ready: "Ready"
            case .needsSelection: "Choose"
            case .notFoundInSavedCloset: "Not found in saved Closet"
            case .weatherRequired: "Weather need"
            case .ppeRequired: "Work requirement"
            case .unknown: "Unknown"
            }
        }
    }

    let role: String
    let state: State
    let detail: String
    var id: String { role }
}

struct HomeIntelligenceDetail: Equatable {
    let focus: HomeIntelligenceFocus
    let headline: String
    let summary: String
    let facts: [HomeIntelligenceFact]
    let checklist: [HomeIntelligenceChecklistItem]
    let actions: [HomeIntelligenceActionPlan]

    var actionKinds: Set<HomeIntelligenceAction> { Set(actions.map(\.action)) }

    var stylistFacts: [String] {
        (["Customer explicitly opened AI Stylist from Home \(focus.title)."] +
            facts.map { "\($0.evidence.label): \($0.text)" } +
            checklist.map { "\($0.role): \($0.state.label). \($0.detail)" })
            .map { String($0.prefix(200)) }
            .prefix(8)
            .map { $0 }
    }
}

struct HomeIntelligenceInput: Equatable {
    struct ClosetItem: Equatable {
        let category: String
        let name: String
    }

    let weather: WeatherSnapshot?
    let calendar: CalendarContextProjection?
    /// Already-sanitized upcoming EventKit categories. Raw EKEvent values never
    /// enter Home Intelligence or the Stylist handoff.
    let calendarEvents: [CalendarContextProjection]
    let calendarAuthorized: Bool
    let plannedOccasion: String
    let dressCode: String
    let workplace: String
    let closetItems: [ClosetItem]
    let savedScanCount: Int
    let savedShoppingCount: Int

    init(
        weather: WeatherSnapshot?,
        calendar: CalendarContextProjection?,
        calendarEvents: [CalendarContextProjection] = [],
        calendarAuthorized: Bool,
        plannedOccasion: String,
        dressCode: String,
        workplace: String,
        closetItems: [ClosetItem],
        savedScanCount: Int,
        savedShoppingCount: Int
    ) {
        self.weather = weather
        self.calendar = calendar
        self.calendarEvents = calendarEvents
        self.calendarAuthorized = calendarAuthorized
        self.plannedOccasion = plannedOccasion
        self.dressCode = dressCode
        self.workplace = workplace
        self.closetItems = closetItems
        self.savedScanCount = savedScanCount
        self.savedShoppingCount = savedShoppingCount
    }

    var normalizedOccasion: String? {
        let candidate = plannedOccasion.trimmingCharacters(in: .whitespacesAndNewlines)
        return candidate.isEmpty ? nil : String(candidate.prefix(80))
    }

    var normalizedWorkplace: String? {
        let candidate = workplace.trimmingCharacters(in: .whitespacesAndNewlines)
        return candidate.isEmpty ? nil : String(candidate.prefix(80))
    }
}

enum HomeIntelligenceAuthority {
    static func make(input: HomeIntelligenceInput) -> [HomeIntelligenceFocus: HomeIntelligenceDetail] {
        Dictionary(uniqueKeysWithValues: HomeIntelligenceFocus.allCases.map { ($0, detail(for: $0, input: input)) })
    }

    static func detail(for focus: HomeIntelligenceFocus, input: HomeIntelligenceInput) -> HomeIntelligenceDetail {
        switch focus {
        case .weather: weather(input)
        case .calendar: calendar(input)
        case .outfitChecklist: checklist(input)
        case .laundry: laundry(input)
        case .missingPieces: missingPieces(input)
        case .shopping: shopping(input)
        }
    }

    private static func action(
        _ action: HomeIntelligenceAction,
        priority: HomeIntelligenceActionPriority,
        rationale: String
    ) -> HomeIntelligenceActionPlan {
        HomeIntelligenceActionPlan(action: action, priority: priority, rationale: rationale)
    }

    private static func weather(_ input: HomeIntelligenceInput) -> HomeIntelligenceDetail {
        guard let weather = input.weather else {
            return HomeIntelligenceDetail(
                focus: .weather,
                headline: "Weather needs a refresh",
                summary: "KigoStylist cannot make weather-specific outfit guidance until current WeatherKit conditions are available.",
                facts: [HomeIntelligenceFact(text: "No current WeatherKit snapshot is available.", evidence: .unknown)],
                checklist: [],
                actions: [
                    action(.viewForecast, priority: .needsInput, rationale: "Refresh conditions before relying on weather-specific guidance."),
                    action(.askStylist, priority: .optional, rationale: "Get a general outfit recommendation while weather is unavailable.")
                ]
            )
        }
        let activity = WeatherContextEngine.inferActivity(
            occasion: input.normalizedOccasion ?? "",
            environment: input.normalizedWorkplace ?? ""
        )
        let context = WeatherContextSnapshot(
            airTemperature: weather.temperatureFahrenheit,
            feelsLikeTemperature: weather.feelsLikeFahrenheit,
            humidityPercent: weather.humidityPercent,
            rainChancePercent: weather.rainChancePercent,
            windMph: weather.windMph,
            uvIndex: weather.uvIndex,
            condition: weather.condition,
            locationText: weather.locationName ?? "",
            activity: activity,
            region: WeatherContextEngine.inferRegion(locationText: weather.locationName ?? ""),
            season: "current",
            timeOfDay: "current",
            confidence: 100
        )
        let recommendation = WeatherContextEngine.recommendation(for: context)
        var facts = [
            HomeIntelligenceFact(text: "\(weather.condition), \(weather.temperatureFahrenheit)°F (feels like \(weather.feelsLikeFahrenheit)°F).", evidence: .confirmed),
            HomeIntelligenceFact(text: recommendation.recommendation, evidence: .inferred)
        ]
        if let rain = weather.rainChancePercent {
            facts.append(HomeIntelligenceFact(text: rain >= 45 ? "Rain risk is \(rain)% — bring an umbrella or rain-ready footwear if you will be outside." : "Rain chance is \(rain)%.", evidence: .confirmed))
        }
        if let humidity = weather.humidityPercent {
            facts.append(HomeIntelligenceFact(text: "Humidity is \(humidity)% — favor breathable fabrics when it is high.", evidence: .confirmed))
        }
        if let wind = weather.windMph, wind >= 18 {
            facts.append(HomeIntelligenceFact(text: "Wind is \(wind) mph — use a removable wind-resistant layer outdoors.", evidence: .confirmed))
        }
        if let uv = weather.uvIndex, uv >= 7 {
            facts.append(HomeIntelligenceFact(text: "UV is \(uv) — add sun coverage such as sunglasses or a hat if appropriate.", evidence: .confirmed))
        }
        return HomeIntelligenceDetail(
            focus: .weather,
            headline: "Dress for \(weather.condition.lowercased())",
            summary: recommendation.recommendation,
            facts: facts,
            checklist: [],
            actions: [
                action(.buildOutfit, priority: .recommendedNow, rationale: "Turn today’s confirmed conditions into a practical look."),
                action(.askStylist, priority: .recommendedNow, rationale: "Use the weather facts already shown here; do not repeat them."),
                action(.viewForecast, priority: .optional, rationale: "Review the forecast if you need to plan beyond the current conditions.")
            ]
        )
    }

    private static func calendar(_ input: HomeIntelligenceInput) -> HomeIntelligenceDetail {
        guard input.calendarAuthorized else {
            return HomeIntelligenceDetail(
                focus: .calendar,
                headline: "Your day is private until you connect Calendar",
                summary: "Connect Calendar to receive outfit preparation guidance. KigoStylist only uses a minimized occasion category, never event titles in this workspace.",
                facts: [HomeIntelligenceFact(text: "Calendar permission is not available.", evidence: .unknown)],
                checklist: [],
                actions: [
                    action(.enableCalendar, priority: .needsInput, rationale: "Connect Calendar only if you want event-aware outfit preparation."),
                    action(.askStylist, priority: .optional, rationale: "Ask using your current saved day plan without sharing Calendar details.")
                ]
            )
        }
        let projections = input.calendarEvents.isEmpty ? (input.calendar.map { [$0] } ?? []) : input.calendarEvents
        guard let projection = projections.first else {
            return HomeIntelligenceDetail(
                focus: .calendar,
                headline: "No recognized event context today",
                summary: "Calendar access is on, but no supported upcoming occasion was found. You can still prepare an outfit from your saved plan.",
                facts: [HomeIntelligenceFact(text: "No minimized event category is available today.", evidence: .unknown)],
                checklist: [],
                actions: [
                    action(.buildOutfit, priority: .recommendedNow, rationale: "Start from the occasion or plan you already saved."),
                    action(.openCloset, priority: .needsInput, rationale: "Choose a known item to make the plan more specific."),
                    action(.askStylist, priority: .optional, rationale: "Get a recommendation without exposing calendar titles.")
                ]
            )
        }
        let category = display(projection.category)
        let timing = projection.isAllDay ? "all day" : projection.timeWindow.rawValue
        let additionalCategories = Array(projections.dropFirst().prefix(2)).map { display($0.category) }
        let additionalEventFact = additionalCategories.isEmpty
            ? []
            : [HomeIntelligenceFact(text: "Also coming up: \(additionalCategories.joined(separator: ", ")).", evidence: .confirmed)]
        return HomeIntelligenceDetail(
            focus: .calendar,
            headline: "Prepare for \(category)",
            summary: "A \(category.lowercased()) is coming up \(timing == "all day" ? "all day" : "in the \(timing)"). Build a look that can transition comfortably through the day.",
            facts: [
                HomeIntelligenceFact(text: "Upcoming occasion: \(category).", evidence: .confirmed),
                HomeIntelligenceFact(text: "Timing: \(timing).", evidence: .confirmed),
                projection.isRecurring ? HomeIntelligenceFact(text: "This is a recurring calendar event.", evidence: .confirmed) : nil,
                HomeIntelligenceFact(text: "KigoStylist uses this minimized category rather than the event title.", evidence: .confirmed)
            ].compactMap { $0 } + additionalEventFact,
            checklist: [],
            actions: [
                action(.buildOutfit, priority: .recommendedNow, rationale: "Prepare an outfit for the confirmed occasion and time window."),
                action(.openCloset, priority: .recommendedNow, rationale: "Select a saved piece that fits the occasion."),
                action(.askStylist, priority: .optional, rationale: "Ask with the minimized occasion category already in context.")
            ]
        )
    }

    private static func checklist(_ input: HomeIntelligenceInput) -> HomeIntelligenceDetail {
        let categories = input.closetItems.map { $0.category.lowercased() }
        let has = { (terms: [String]) in categories.contains { category in terms.contains { category.contains($0) } } }
        func item(_ role: String, _ terms: [String], _ detail: String) -> HomeIntelligenceChecklistItem {
            if has(terms) {
                return HomeIntelligenceChecklistItem(role: role, state: .ready, detail: "A matching item is saved in your Closet.")
            }
            return HomeIntelligenceChecklistItem(role: role, state: input.closetItems.isEmpty ? .unknown : .notFoundInSavedCloset, detail: detail)
        }
        var items = [
            item("Top", ["shirt", "top", "blouse", "polo", "sweater"], "Choose one or add it to your saved Closet."),
            item("Bottom", ["pant", "trouser", "jean", "skirt", "short"], "Choose one or scan a saved option."),
            item("Shoes", ["shoe", "boot", "sneaker", "heel", "sandal"], "Select footwear suited to the day.")
        ]
        if let weather = input.weather, weather.feelsLikeFahrenheit <= 60 {
            items.append(item("Layer", ["jacket", "coat", "blazer", "cardigan", "sweater"], "Current weather calls for a removable layer."))
        }
        if let rain = input.weather?.rainChancePercent, rain >= 45 {
            items.append(HomeIntelligenceChecklistItem(role: "Rain plan", state: .weatherRequired, detail: "Rain chance is \(rain)% — consider an umbrella and water-friendly footwear."))
        }
        if input.normalizedWorkplace?.lowercased().contains("ppe") == true {
            items.append(HomeIntelligenceChecklistItem(role: "Work/PPE", state: .ppeRequired, detail: "Your saved work context mentions PPE; confirm required protective gear before leaving."))
        }
        let summary = input.closetItems.isEmpty
            ? "Start with one saved top, bottom, and pair of shoes so KigoStylist can match a plan to your wardrobe."
            : "Use this as a readiness check; a saved category confirms an option exists, not that it is already selected."
        return HomeIntelligenceDetail(
            focus: .outfitChecklist,
            headline: "Build today’s outfit",
            summary: summary,
            facts: [HomeIntelligenceFact(text: "Checklist combines current weather, your saved Closet, and available day context.", evidence: .inferred)],
            checklist: items,
            actions: checklistActions(for: items)
        )
    }

    private static func laundry(_ input: HomeIntelligenceInput) -> HomeIntelligenceDetail {
        HomeIntelligenceDetail(
            focus: .laundry,
            headline: "Laundry needs wear history",
            summary: "KigoStylist does not mark saved clothing clean or dirty without actual wear or care evidence. Review an item before wearing it, then add the details you want remembered.",
            facts: [
                HomeIntelligenceFact(text: "No verified garment wear or laundry history is available in this Home workspace.", evidence: .unknown),
                HomeIntelligenceFact(text: input.closetItems.isEmpty ? "Add saved Closet items first to compare ready options." : "Your saved Closet can help you choose alternatives after you confirm care status.", evidence: input.closetItems.isEmpty ? .unknown : .confirmed)
            ],
            checklist: [],
            actions: [
                action(.openCloset, priority: input.closetItems.isEmpty ? .needsInput : .recommendedNow, rationale: input.closetItems.isEmpty ? "Save a garment first so KigoStylist can compare alternatives." : "Review an item’s actual care status before wearing it."),
                action(.openScan, priority: .needsInput, rationale: "Scan a piece to create a confirmed wardrobe record; this does not claim laundry status."),
                action(.askStylist, priority: .optional, rationale: "Ask for an outfit alternative without inventing care history.")
            ]
        )
    }

    private static func missingPieces(_ input: HomeIntelligenceInput) -> HomeIntelligenceDetail {
        let plan = checklist(input)
        let gaps = plan.checklist.filter { $0.state == .notFoundInSavedCloset || $0.state == .unknown || $0.state == .weatherRequired || $0.state == .ppeRequired }
        let summary: String
        if input.closetItems.isEmpty {
            summary = "KigoStylist cannot determine ownership until you save or scan wardrobe pieces. That does not mean you do not own them."
        } else if gaps.isEmpty {
            summary = "Your saved Closet covers the core categories in today’s checklist. Confirm the final selections before you leave."
        } else {
            summary = "These are gaps in the saved Closet view, not proof that you do not own the items."
        }
        return HomeIntelligenceDetail(
            focus: .missingPieces,
            headline: gaps.isEmpty ? "Core categories are represented" : "Fill the saved-Closet gaps",
            summary: summary,
            facts: gaps.map { HomeIntelligenceFact(text: "\($0.role): \($0.detail)", evidence: $0.state == .weatherRequired || $0.state == .ppeRequired ? .confirmed : .unknown) },
            checklist: gaps,
            actions: gapActions(for: gaps, hasClosetItems: !input.closetItems.isEmpty)
        )
    }

    private static func shopping(_ input: HomeIntelligenceInput) -> HomeIntelligenceDetail {
        let gaps = missingPieces(input).checklist.filter { $0.state == .notFoundInSavedCloset || $0.state == .unknown }
        let saved = input.savedShoppingCount
        let headline = saved > 0 ? "Start with your \(saved) saved \(saved == 1 ? "item" : "items")" : "Shop from a real need"
        var facts: [HomeIntelligenceFact] = []
        if saved > 0 {
            facts.append(HomeIntelligenceFact(text: "You have \(saved) saved shopping \(saved == 1 ? "item" : "items") to review in Shop AI.", evidence: .confirmed))
        } else {
            facts.append(HomeIntelligenceFact(text: "No saved product is available to recommend yet.", evidence: .unknown))
        }
        if gaps.isEmpty {
            facts.append(HomeIntelligenceFact(text: "Use Shop AI only if you want a complement for your existing saved Closet plan.", evidence: .inferred))
        } else {
            facts.append(HomeIntelligenceFact(text: "Shop AI can help evaluate \(gaps.map(\.role).joined(separator: ", ")) based on this day’s plan. Availability and price are shown only when genuine catalog data is available.", evidence: .inferred))
        }
        return HomeIntelligenceDetail(
            focus: .shopping,
            headline: headline,
            summary: "Shop AI starts from your saved products and known styling gaps; it never invents a price, sale, inventory, or ownership claim.",
            facts: facts,
            checklist: gaps,
            actions: shoppingActions(for: gaps, hasSavedItems: saved > 0)
        )
    }

    private static func checklistActions(for items: [HomeIntelligenceChecklistItem]) -> [HomeIntelligenceActionPlan] {
        let unknownItems = items.contains { $0.state == .unknown || $0.state == .notFoundInSavedCloset }
        return [
            action(.openCloset, priority: unknownItems ? .recommendedNow : .needsInput, rationale: unknownItems ? "Choose a saved item for the unresolved checklist roles." : "Confirm the saved options you want to wear today."),
            action(.openScan, priority: unknownItems ? .needsInput : .optional, rationale: "Scan what you are wearing or own to replace an unknown with a confirmed record."),
            action(.askStylist, priority: .recommendedNow, rationale: "Ask using the current weather, occasion, and checklist facts without re-entering them.")
        ]
    }

    private static func gapActions(for gaps: [HomeIntelligenceChecklistItem], hasClosetItems: Bool) -> [HomeIntelligenceActionPlan] {
        let hasActionableGap = !gaps.isEmpty
        return [
            action(.openCloset, priority: hasActionableGap ? .recommendedNow : .optional, rationale: hasActionableGap ? "Check whether an unsaved item covers the gap before shopping." : "Review the saved options that already cover the plan."),
            action(.openScan, priority: hasActionableGap ? .needsInput : .optional, rationale: "Scan an item you own to turn unknown ownership into a confirmed saved option."),
            action(.askStylist, priority: .recommendedNow, rationale: "Ask for ways to complete today’s look using the gaps already shown."),
            action(.openShop, priority: hasActionableGap ? .optional : .notRelevantNow, rationale: hasActionableGap ? "Explore Shop AI only after checking your Closet or when you want a new complement." : "Shopping is optional because saved categories already cover the core plan.")
        ]
    }

    private static func shoppingActions(for gaps: [HomeIntelligenceChecklistItem], hasSavedItems: Bool) -> [HomeIntelligenceActionPlan] {
        let hasGaps = !gaps.isEmpty
        return [
            action(.openCloset, priority: hasGaps ? .recommendedNow : .optional, rationale: hasGaps ? "Check saved or unsaved pieces before treating a gap as a shopping need." : "Review the saved Closet plan before adding anything new."),
            action(.openScan, priority: hasGaps ? .needsInput : .optional, rationale: "Scan an owned item to avoid shopping for something you already have."),
            action(.openShop, priority: hasGaps || hasSavedItems ? .recommendedNow : .optional, rationale: hasGaps ? "Shop AI receives today’s plan, weather, known saved-Closet gaps, and available profile preferences automatically." : "Shop AI can start from your saved product interests when you choose to browse."),
            action(.askStylist, priority: .optional, rationale: "Ask for a non-product-specific styling recommendation using the same current plan.")
        ]
    }

    private static func display(_ category: CalendarContextCategory) -> String {
        switch category {
        case .workShift: "Work"
        case .businessMeeting: "Business Meeting"
        case .interview: "Interview"
        case .wedding: "Wedding"
        case .birthday: "Birthday"
        case .anniversary: "Anniversary"
        case .holiday: "Holiday"
        case .dinner: "Dinner"
        case .date: "Date"
        case .religiousService: "Religious Service"
        case .travel: "Travel"
        case .vacation: "Vacation"
        case .workout: "Workout"
        case .formalEvent: "Formal Event"
        case .socialGathering: "Social Gathering"
        case .appointment: "Appointment"
        case .concertOrShow: "Concert or Show"
        case .celebration: "Celebration"
        case .ceremony: "Ceremony"
        case .otherSignificantEvent: "Upcoming Event"
        }
    }
}
