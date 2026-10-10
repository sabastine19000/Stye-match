import Foundation

enum RecommendationRationaleBuilder {
    static func build(
        for product: AffiliateProduct,
        reasonFacts: ProductRecommendationReasonFacts?,
        profile: StylistProfile?,
        memories: [OutfitMemory],
        savedFavorites: [AffiliateProduct],
        favoriteProductIDs: Set<String>,
        preferences: ShoppingRecommendationPreferences = .default,
        now: Date = Date()
    ) -> RecommendationRationale {
        if shouldUseTrendingFallback(
            profile: profile,
            memories: memories,
            savedFavorites: savedFavorites,
            favoriteProductIDs: favoriteProductIDs,
            preferences: preferences
        ) {
            return RecommendationRationale(reasons: [], headline: fallbackHeadline(for: product))
        }

        var reasons: [RecommendationRationale.Reason] = []

        if preferences.usesWardrobeHistory, reasonFacts?.referencedOutfit != nil || hasWardrobeAffinity(product, memories: memories) {
            reasons.append(.matchesWardrobe)
        }

        if preferences.usesFavoriteColors, matchesPreferredColors(product, profile: profile, memories: memories) {
            reasons.append(.matchesColors)
        }

        if preferences.usesWardrobeHistory, matchesStyle(product, profile: profile, memories: memories) {
            reasons.append(.matchesStyle)
        }

        if hasActiveSale(product, now: now) {
            reasons.append(.onSaleToday)
        }

        if preferences.usesFavoriteBrands, isSimilarToSaved(product, savedFavorites: savedFavorites, favoriteProductIDs: favoriteProductIDs) {
            reasons.append(.similarToLiked)
        }

        let uniqueReasons = Array(unique(reasons).prefix(3))
        if uniqueReasons.isEmpty {
            return RecommendationRationale(reasons: [], headline: fallbackHeadline(for: product))
        }

        return RecommendationRationale(
            reasons: uniqueReasons,
            headline: headline(for: product, reasons: uniqueReasons, reasonFacts: reasonFacts)
        )
    }

    static func preferences(from profile: StylistProfile) -> ShoppingRecommendationPreferences {
        let learned = profile.stylePreferencesLearned
        func enabled(_ key: String) -> Bool {
            learned["shoppingPreference:\(key)"].map { $0 > 0 } ?? true
        }
        return ShoppingRecommendationPreferences(
            usesWardrobeHistory: enabled("wardrobeHistory"),
            usesFavoriteBrands: enabled("favoriteBrands"),
            usesFavoriteColors: enabled("favoriteColors"),
            usesBudgetRange: enabled("budget"),
            usesCurrentTrends: enabled("currentTrends"),
            usesWeather: enabled("weather"),
            usesCalendarEvents: enabled("calendarEvents")
        )
    }

    static func apply(_ preferences: ShoppingRecommendationPreferences, to profile: inout StylistProfile) {
        profile.stylePreferencesLearned["shoppingPreference:wardrobeHistory"] = preferences.usesWardrobeHistory ? 1 : 0
        profile.stylePreferencesLearned["shoppingPreference:favoriteBrands"] = preferences.usesFavoriteBrands ? 1 : 0
        profile.stylePreferencesLearned["shoppingPreference:favoriteColors"] = preferences.usesFavoriteColors ? 1 : 0
        profile.stylePreferencesLearned["shoppingPreference:budget"] = preferences.usesBudgetRange ? 1 : 0
        profile.stylePreferencesLearned["shoppingPreference:currentTrends"] = preferences.usesCurrentTrends ? 1 : 0
        profile.stylePreferencesLearned["shoppingPreference:weather"] = preferences.usesWeather ? 1 : 0
        profile.stylePreferencesLearned["shoppingPreference:calendarEvents"] = preferences.usesCalendarEvents ? 1 : 0
    }

    static func budgetFiltered(_ products: [AffiliateProduct], profile: StylistProfile?, preferences: ShoppingRecommendationPreferences) -> [AffiliateProduct] {
        guard preferences.usesBudgetRange, let profile else { return products }
        guard profile.budgetRange.isUserConfirmed else { return products }
        let range = Decimal(profile.budgetRange.minPrice)...Decimal(profile.budgetRange.maxPrice)
        let filtered = products.filter { product in
            if let priceRange = product.priceRange {
                return priceRange.overlaps(range)
            }
            let effectivePrice = product.salePrice ?? product.price
            guard let effectivePrice else { return true }
            return range.contains(effectivePrice)
        }
        return filtered.isEmpty && !products.isEmpty ? products : filtered
    }

    private static func shouldUseTrendingFallback(
        profile: StylistProfile?,
        memories: [OutfitMemory],
        savedFavorites: [AffiliateProduct],
        favoriteProductIDs: Set<String>,
        preferences: ShoppingRecommendationPreferences
    ) -> Bool {
        if !preferences.usesWardrobeHistory,
           !preferences.usesFavoriteBrands,
           !preferences.usesFavoriteColors,
           !preferences.usesBudgetRange,
           preferences.usesCurrentTrends {
            return true
        }

        guard let profile else {
            return memories.isEmpty && savedFavorites.isEmpty && favoriteProductIDs.isEmpty
        }

        return memories.isEmpty
            && savedFavorites.isEmpty
            && favoriteProductIDs.isEmpty
            && profile.favoriteColors.isEmpty
            && profile.favoriteBrands.isEmpty
            && profile.totalScansCompleted == 0
            && profile.stylePreferencesLearned.filter { !$0.key.hasPrefix("shoppingPreference:") }.isEmpty
    }

    private static func headline(
        for product: AffiliateProduct,
        reasons: [RecommendationRationale.Reason],
        reasonFacts: ProductRecommendationReasonFacts?
    ) -> String {
        let garment = DisplayLabelSanitizer.displayName(for: product.subcategory)
            ?? DisplayLabelSanitizer.displayName(for: product.name)
            ?? product.category.displayName.lowercased()
        let color = product.colors.compactMap { DisplayLabelSanitizer.safeColorName($0) }.first
        let item = color.map { "\($0) \(garment)" } ?? garment
        let templateIndex = stableIndex(product.id, count: 4)

        if reasons.contains(.matchesWardrobe), let outfit = reasonFacts?.referencedOutfit {
            let recent = WornRecency.text(reasonFacts?.referencedDate ?? "recently")
            let phrase = outfitPhrase(from: outfit, recency: recent)
            let templates = [
                "Recommended because these \(item) work with \(phrase).",
                "A strong pick because these \(item) complement \(phrase).",
                "These \(item) fit naturally with \(phrase).",
                "This works because \(phrase) already gives you a strong base."
            ]
            return templates[templateIndex]
        }

        if reasons.contains(.matchesColors), let color {
            let templates = [
                "You've been wearing a lot of \(color) lately - these pair naturally with it.",
                "Recommended because \(color) already shows up in your wardrobe.",
                "These \(item) keep your color palette consistent.",
                "A smart match for the \(color) tones you wear often."
            ]
            return templates[templateIndex]
        }

        if reasons.contains(.similarToLiked) {
            let templates = [
                "Similar to pieces you've saved before.",
                "Recommended because it lines up with styles you've liked.",
                "This has the same feel as items you've already saved.",
                "A familiar choice based on your saved shopping picks."
            ]
            return templates[templateIndex]
        }

        if reasons.contains(.onSaleToday) {
            return "Worth a look because it is on sale today and fits your style filters."
        }

        return "Recommended because these \(item) fit right into your current style."
    }

    private static func fallbackHeadline(for product: AffiliateProduct) -> String {
        if !product.retailer.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Available from \(product.retailer.name)."
        }
        if let brand = product.brand?.trimmingCharacters(in: .whitespacesAndNewlines), !brand.isEmpty {
            return "Recommended from the current catalog by \(brand)."
        }
        return "Recommended from the current safe catalog."
    }

    private static func outfitPhrase(from value: String, recency: WornRecency) -> String {
        let parts = value
            .components(separatedBy: CharacterSet(charactersIn: ",+&"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if let firstSafe = parts.compactMap({ DisplayLabelSanitizer.wornItemPhrase(rawLabel: $0, colorName: nil, recency: recency) }).first {
            return firstSafe
        }
        return recency == .yesterday ? "what you wore yesterday" : "a recent outfit"
    }

    private static func matchesPreferredColors(_ product: AffiliateProduct, profile: StylistProfile?, memories: [OutfitMemory]) -> Bool {
        let productFamilies = Set(product.colors.map(colorFamily).filter { !$0.isEmpty })
        guard !productFamilies.isEmpty else { return false }
        var preferredColors = profile?.favoriteColors ?? []
        preferredColors.append(contentsOf: memories.flatMap(\.colors))
        let preferredFamilies = Set(preferredColors.map(colorFamily).filter { !$0.isEmpty })
        return !productFamilies.isDisjoint(with: preferredFamilies)
    }

    private static func matchesStyle(_ product: AffiliateProduct, profile: StylistProfile?, memories: [OutfitMemory]) -> Bool {
        let productTags = Set((product.tags + (product.occasionTags ?? []) + [product.subcategory]).map { clean($0).lowercased() }.filter { !$0.isEmpty })
        guard !productTags.isEmpty else { return false }
        let learnedStyles = profile?.stylePreferencesLearned
            .filter { $0.key.hasPrefix("style:") && $0.value > 0 }
            .map { $0.key.replacingOccurrences(of: "style:", with: "").lowercased() } ?? []
        let memoryStyles = memories.map { clean($0.detectedStyle).lowercased() }.filter { !$0.isEmpty }
        return (learnedStyles + memoryStyles).contains { style in
            productTags.contains(style) || productTags.contains(where: { style.contains($0) || $0.contains(style) })
        }
    }

    private static func hasWardrobeAffinity(_ product: AffiliateProduct, memories: [OutfitMemory]) -> Bool {
        let productCategory = clean(product.subcategory).lowercased()
        guard !productCategory.isEmpty else { return false }
        return memories.contains { memory in
            memory.detectedGarments.contains { clean($0).lowercased().contains(productCategory) }
                || memory.garmentRecords.contains { clean($0.garmentCategory).lowercased().contains(productCategory) }
        }
    }

    private static func isSimilarToSaved(
        _ product: AffiliateProduct,
        savedFavorites: [AffiliateProduct],
        favoriteProductIDs: Set<String>
    ) -> Bool {
        if favoriteProductIDs.contains(product.id) { return true }
        let productFamilies = Set(product.colors.map(colorFamily).filter { !$0.isEmpty })
        return savedFavorites.contains { favorite in
            favorite.brand?.caseInsensitiveCompare(product.brand ?? "") == .orderedSame
                || favorite.subcategory.caseInsensitiveCompare(product.subcategory) == .orderedSame
                || !productFamilies.isDisjoint(with: Set(favorite.colors.map(colorFamily).filter { !$0.isEmpty }))
        }
    }

    private static func hasActiveSale(_ product: AffiliateProduct, now: Date) -> Bool {
        product.salePrice != nil && (product.saleEndsAt ?? .distantFuture) > now
    }

    private static func stableIndex(_ value: String, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let sum = value.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return abs(sum) % count
    }

    private static func unique(_ reasons: [RecommendationRationale.Reason]) -> [RecommendationRationale.Reason] {
        var seen = Set<RecommendationRationale.Reason>()
        return reasons.filter { seen.insert($0).inserted }
    }

    private static func colorFamily(_ color: String) -> String {
        let value = clean(color).lowercased()
        if ["black", "charcoal"].contains(value) { return "black" }
        if ["white", "cream"].contains(value) { return "white" }
        if ["gray", "grey", "silver"].contains(value) { return "gray" }
        if ["navy", "blue", "denim"].contains(value) { return "blue" }
        if ["brown", "tan", "beige", "camel"].contains(value) { return "brown" }
        if ["olive", "green"].contains(value) { return "green" }
        return value
    }

    private static func clean(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
