import Foundation

struct ShoppingWeatherContext: Equatable {
    let feelsLikeTemperature: Int?
    let rainChancePercent: Int?
    let uvIndex: Int?
    let condition: String
}

struct ProductRecommendation: Identifiable, Equatable {
    let id: String
    let product: AffiliateProduct
    let rank: Int
    let reasonFacts: ProductRecommendationReasonFacts
}

struct RankedProduct: Identifiable, Equatable {
    let id: String
    let product: AffiliateProduct
    let rank: Int
    let reasonFacts: ProductRecommendationReasonFacts?
}

struct ShoppingRankingContext {
    let memories: [OutfitMemory]
    let savedFavorites: [AffiliateProduct]
    let savedFavoriteProductIDs: Set<String>
    let weather: ShoppingWeatherContext?
    let dismissedProductIDs: Set<String>
    let now: Date

    init(
        memories: [OutfitMemory],
        savedFavorites: [AffiliateProduct] = [],
        savedFavoriteProductIDs: Set<String> = [],
        weather: ShoppingWeatherContext? = nil,
        dismissedProductIDs: Set<String> = [],
        now: Date = Date()
    ) {
        self.memories = memories
        self.savedFavorites = savedFavorites
        self.savedFavoriteProductIDs = savedFavoriteProductIDs
        self.weather = weather
        self.dismissedProductIDs = dismissedProductIDs
        self.now = now
    }
}

struct ProductRecommendationReasonFacts: Codable, Equatable {
    let rule: String
    let productName: String
    let productCategory: String
    let productColors: [String]
    let referencedOutfit: String?
    let referencedDate: String?
    let referencedScore: Int?
    let weatherFact: String?
    let saleFact: String?

    var oneLineReason: String {
        switch rule {
        case "complement":
            let outfit = referencedOutfit ?? "a saved outfit"
            let date = referencedDate.map { " you wore \($0)" } ?? ""
            return "\(productName) pairs with \(outfit)\(date)."
        case "upgrade":
            let outfit = referencedOutfit ?? "a lower-scoring saved item"
            return "\(productName) matches the color family of \(outfit) and can upgrade that slot."
        case "weather":
            return weatherFact ?? "\(productName) matches the current weather."
        case "gap":
            return "\(productName) fills a category not yet common in your saved closet history."
        default:
            return "\(productName) matches your saved style facts."
        }
    }
}

enum ShoppingRecommendationEngine {
    static func rank(results: [AffiliateProduct], against context: ShoppingRankingContext) -> [RankedProduct] {
        results.map { product in
            var score = 0
            var facts: ProductRecommendationReasonFacts?

            if let complement = recentComplementFacts(product: product, memories: context.memories, now: context.now) {
                score += 100
                facts = complement
            }

            if favoriteAffinity(product: product, favorites: context.savedFavorites) || context.savedFavoriteProductIDs.contains(product.id) {
                score += 25
                if facts == nil {
                    facts = ProductRecommendationReasonFacts(
                        rule: "favoriteAffinity",
                        productName: product.name,
                        productCategory: product.category.displayName,
                        productColors: product.colors,
                        referencedOutfit: nil,
                        referencedDate: nil,
                        referencedScore: nil,
                        weatherFact: nil,
                        saleFact: nil
                    )
                }
            }

            if let weatherFacts = weatherFacts(product: product, weather: context.weather) {
                score += 20
                if facts == nil { facts = weatherFacts }
            }

            if isHot(context.weather), isHeavyLayer(product) {
                score -= 40
            }

            if styleHistoryAffinity(product: product, memories: context.memories) {
                score += 15
                if facts == nil {
                    facts = ProductRecommendationReasonFacts(
                        rule: "styleHistory",
                        productName: product.name,
                        productCategory: product.category.displayName,
                        productColors: product.colors,
                        referencedOutfit: nil,
                        referencedDate: nil,
                        referencedScore: nil,
                        weatherFact: nil,
                        saleFact: nil
                    )
                }
            }

            if context.dismissedProductIDs.contains(product.id) {
                score -= 1_000
            }

            #if DEBUG
            if let facts {
                _ = PersonalizationContextBuilder.buildShoppingRecommendationPromptContext(facts)
            }
            #endif

            return RankedProduct(id: product.id, product: product, rank: score, reasonFacts: facts)
        }
        .sorted { lhs, rhs in
            if lhs.rank == rhs.rank { return lhs.product.name < rhs.product.name }
            return lhs.rank > rhs.rank
        }
    }

    static func recommendations(
        currentGarments: [String],
        currentColors: [String],
        memories: [OutfitMemory],
        weather: ShoppingWeatherContext?,
        catalog: [AffiliateProduct],
        now: Date = Date(),
        dismissedProductIDs: Set<String> = [],
        recentlyViewedProductIDs: [String] = []
    ) -> [ProductRecommendation] {
        let candidates = catalog.compactMap { product -> ProductRecommendation? in
            guard !dismissedProductIDs.contains(product.id),
                  !isHeavyLayer(product),
                  !(isHot(weather) && isHeavyLayer(product)) else {
                return nil
            }

            var best: (rank: Int, facts: ProductRecommendationReasonFacts)?
            if let complement = complementFacts(product: product, currentGarments: currentGarments, currentColors: currentColors, memories: memories, now: now) {
                best = (100, complement)
            } else if let gap = gapFacts(product: product, memories: memories) {
                best = (65, gap)
            } else if let upgrade = upgradeFacts(product: product, memories: memories, now: now) {
                best = (80, upgrade)
            } else if let weatherFacts = weatherFacts(product: product, weather: weather) {
                best = (70, weatherFacts)
            }

            guard var match = best else {
                return nil
            }

            if hasActiveSale(product, now: now), match.facts.rule == "complement" || match.facts.rule == "upgrade" {
                match.rank += 12
                match.facts = ProductRecommendationReasonFacts(
                    rule: match.facts.rule,
                    productName: match.facts.productName,
                    productCategory: match.facts.productCategory,
                    productColors: match.facts.productColors,
                    referencedOutfit: match.facts.referencedOutfit,
                    referencedDate: match.facts.referencedDate,
                    referencedScore: match.facts.referencedScore,
                    weatherFact: match.facts.weatherFact,
                    saleFact: "\(product.name) is currently on sale."
                )
            }

            if recentlyViewedProductIDs.contains(product.id) {
                match.rank -= 5
            }

            return ProductRecommendation(id: product.id, product: product, rank: match.rank, reasonFacts: match.facts)
        }

        return candidates.sorted { lhs, rhs in
            if lhs.rank == rhs.rank { return lhs.product.name < rhs.product.name }
            return lhs.rank > rhs.rank
        }
    }

    private static func complementFacts(
        product: AffiliateProduct,
        currentGarments: [String],
        currentColors: [String],
        memories: [OutfitMemory],
        now: Date
    ) -> ProductRecommendationReasonFacts? {
        let productCategory = garmentCategory(product)
        let productColors = normalizedColors(product.colors)
        let currentRecords = currentGarments.enumerated().map { index, garment in
            (category: GarmentRecordHelpers.category(from: garment), color: index < currentColors.count ? currentColors[index] : "")
        }

        if currentRecords.contains(where: { record in
            CategoryPairingRules.complementaryCategories(for: record.category).contains(productCategory)
                && !productColors.isDisjoint(with: ColorPairingRules.complementaryColors(for: record.color))
        }) {
            let outfit = outfitPhrase(garments: currentGarments, colors: currentColors)
            return ProductRecommendationReasonFacts(
                rule: "complement",
                productName: product.name,
                productCategory: product.category.displayName,
                productColors: product.colors,
                referencedOutfit: outfit,
                referencedDate: nil,
                referencedScore: nil,
                weatherFact: nil,
                saleFact: nil
            )
        }

        for memory in memories.sorted(by: { $0.scanDate > $1.scanDate }) {
            if memory.garmentRecords.contains(where: { record in
                CategoryPairingRules.complementaryCategories(for: record.garmentCategory).contains(productCategory)
                    && !productColors.isDisjoint(with: ColorPairingRules.complementaryColors(for: record.colors.first))
            }) {
                return ProductRecommendationReasonFacts(
                    rule: "complement",
                    productName: product.name,
                    productCategory: product.category.displayName,
                    productColors: product.colors,
                    referencedOutfit: outfitPhrase(garments: memory.detectedGarments, colors: memory.colors),
                    referencedDate: OutfitRecallService.relativeDateText(for: memory.scanDate, now: now),
                    referencedScore: memory.styleScore,
                    weatherFact: nil,
                    saleFact: nil
                )
            }
        }

        return nil
    }

    private static func recentComplementFacts(product: AffiliateProduct, memories: [OutfitMemory], now: Date) -> ProductRecommendationReasonFacts? {
        let cutoff = now.addingTimeInterval(-14 * 24 * 60 * 60)
        return complementFacts(
            product: product,
            currentGarments: [],
            currentColors: [],
            memories: memories.filter { $0.scanDate >= cutoff },
            now: now
        )
    }

    private static func gapFacts(product: AffiliateProduct, memories: [OutfitMemory]) -> ProductRecommendationReasonFacts? {
        let productSubcategory = clean(product.subcategory).lowercased()
        guard !productSubcategory.isEmpty,
              !memories.contains(where: { memory in
                  memory.detectedGarments.contains { $0.localizedCaseInsensitiveContains(productSubcategory) }
                      || memory.garmentRecords.contains { $0.garmentCategory.localizedCaseInsensitiveContains(productSubcategory) }
              }),
              memories.count >= 2 else {
            return nil
        }

        return ProductRecommendationReasonFacts(
            rule: "gap",
            productName: product.name,
            productCategory: product.category.displayName,
            productColors: product.colors,
            referencedOutfit: nil,
            referencedDate: nil,
            referencedScore: nil,
            weatherFact: nil,
            saleFact: nil
        )
    }

    private static func upgradeFacts(product: AffiliateProduct, memories: [OutfitMemory], now: Date) -> ProductRecommendationReasonFacts? {
        let productCategory = garmentCategory(product)
        let productFamilies = Set(product.colors.map(colorFamily).filter { !$0.isEmpty })
        guard !productFamilies.isEmpty else { return nil }

        for memory in memories where memory.styleScore < 75 || memory.wasLiked == false {
            if memory.garmentRecords.contains(where: { record in
                record.garmentCategory == productCategory
                    && !Set(record.colors.map(colorFamily).filter { !$0.isEmpty }).isDisjoint(with: productFamilies)
            }) {
                return ProductRecommendationReasonFacts(
                    rule: "upgrade",
                    productName: product.name,
                    productCategory: product.category.displayName,
                    productColors: product.colors,
                    referencedOutfit: outfitPhrase(garments: memory.detectedGarments, colors: memory.colors),
                    referencedDate: OutfitRecallService.relativeDateText(for: memory.scanDate, now: now),
                    referencedScore: memory.styleScore,
                    weatherFact: nil,
                    saleFact: nil
                )
            }
        }

        return nil
    }

    private static func weatherFacts(product: AffiliateProduct, weather: ShoppingWeatherContext?) -> ProductRecommendationReasonFacts? {
        guard let weather else { return nil }
        let tags = Set(product.tags.map { $0.lowercased() })

        if (weather.rainChancePercent ?? 0) >= 50,
           !tags.isDisjoint(with: ["rain", "waterproof", "umbrella"]) {
            return ProductRecommendationReasonFacts(
                rule: "weather",
                productName: product.name,
                productCategory: product.category.displayName,
                productColors: product.colors,
                referencedOutfit: nil,
                referencedDate: nil,
                referencedScore: nil,
                weatherFact: "There is a \(weather.rainChancePercent ?? 0)% chance of rain, so \(product.name) matches the weather.",
                saleFact: nil
            )
        }

        if (weather.uvIndex ?? 0) >= 8, tags.contains("sun") || tags.contains("uv") {
            return ProductRecommendationReasonFacts(
                rule: "weather",
                productName: product.name,
                productCategory: product.category.displayName,
                productColors: product.colors,
                referencedOutfit: nil,
                referencedDate: nil,
                referencedScore: nil,
                weatherFact: "UV index is \(weather.uvIndex ?? 0), so \(product.name) matches sun-protection needs.",
                saleFact: nil
            )
        }

        return nil
    }

    private static func favoriteAffinity(product: AffiliateProduct, favorites: [AffiliateProduct]) -> Bool {
        let productFamilies = Set(product.colors.map(colorFamily).filter { !$0.isEmpty })
        return favorites.contains { favorite in
            favorite.brand?.caseInsensitiveCompare(product.brand ?? "") == .orderedSame
                || favorite.subcategory.caseInsensitiveCompare(product.subcategory) == .orderedSame
                || !productFamilies.isDisjoint(with: Set(favorite.colors.map(colorFamily).filter { !$0.isEmpty }))
        }
    }

    private static func styleHistoryAffinity(product: AffiliateProduct, memories: [OutfitMemory]) -> Bool {
        let tags = Set(product.tags.map { clean($0).lowercased() } + (product.occasionTags ?? []).map { clean($0).lowercased() })
        guard !tags.isEmpty else { return false }
        let styles = memories.map { clean($0.detectedStyle).lowercased() }.filter { !$0.isEmpty }
        return styles.contains { style in tags.contains(style) || tags.contains(where: { style.contains($0) || $0.contains(style) }) }
    }

    private static func hasActiveSale(_ product: AffiliateProduct, now: Date) -> Bool {
        guard product.salePrice != nil else { return false }
        return (product.saleEndsAt ?? .distantFuture) > now
    }

    private static func isHot(_ weather: ShoppingWeatherContext?) -> Bool {
        (weather?.feelsLikeTemperature ?? -100) >= 80
    }

    private static func isHeavyLayer(_ product: AffiliateProduct) -> Bool {
        let text = ([product.name, product.subcategory] + product.tags).joined(separator: " ").lowercased()
        return ["jacket", "blazer", "coat", "sweater", "hoodie", "heavy", "wool", "fleece"].contains { text.contains($0) }
    }

    private static func garmentCategory(_ product: AffiliateProduct) -> String {
        switch product.category {
        case .shoes: return "shoes"
        case .accessories: return "accessory"
        default: return GarmentRecordHelpers.category(from: "\(product.subcategory) \(product.name)")
        }
    }

    private static func outfitPhrase(garments: [String], colors: [String]) -> String {
        let pieces = garments.enumerated().map { index, garment in
            let item = clean(garment)
            let color = index < colors.count ? clean(colors[index]) : ""
            return color.isEmpty || item.localizedCaseInsensitiveContains(color) ? item : "\(color) \(item)"
        }.filter { !$0.isEmpty }

        if pieces.isEmpty { return "the outfit" }
        if pieces.count == 1 { return pieces[0] }
        if pieces.count == 2 { return "\(pieces[0]) and \(pieces[1])" }
        return pieces.dropLast().joined(separator: ", ") + ", and \(pieces.last ?? "")"
    }

    private static func normalizedColors(_ colors: [String]) -> Set<String> {
        Set(colors.map { clean($0).lowercased() }.filter { !$0.isEmpty })
    }

    private static func colorFamily(_ color: String) -> String {
        let value = clean(color).lowercased()
        if ["black", "charcoal"].contains(value) { return "black" }
        if ["white", "cream"].contains(value) { return "white" }
        if ["gray", "grey", "silver"].contains(value) { return "gray" }
        if ["navy", "blue", "denim"].contains(value) { return "blue" }
        if ["tan", "beige", "khaki", "brown"].contains(value) { return "brown" }
        return value
    }

    private static func clean(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
