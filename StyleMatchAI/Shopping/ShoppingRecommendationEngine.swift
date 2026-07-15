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
        let item = Self.customerProductName(productName)
        switch rule {
        case "complement":
            let outfit = referencedOutfit.map(Self.customerOutfitPhrase) ?? "a saved outfit"
            let date = referencedDate.map { " you wore \($0)" } ?? ""
            return "Recommended because \(item) complements \(outfit)\(date)."
        case "upgrade":
            let outfit = referencedOutfit.map(Self.customerOutfitPhrase) ?? "a lower-scoring saved outfit"
            return "Recommended because \(item) gives \(outfit) a cleaner, more polished finish."
        case "weather":
            return weatherFact ?? "Recommended because \(item) matches today's weather."
        case "gap":
            return "Recommended because \(item) fills a useful wardrobe gap."
        case "favoriteAffinity":
            return "Recommended because \(item) is similar to styles, colors, or brands you have saved."
        case "styleHistory":
            return "Recommended because \(item) matches styles you wear often."
        case "popular":
            return "Recommended as a popular starting point while StyleMatch learns your wardrobe."
        default:
            return "Recommended because \(item) matches your wardrobe and style preferences."
        }
    }

    var explanationBullets: [String] {
        var bullets: [String] = []
        if referencedOutfit != nil { bullets.append("Matches your wardrobe") }
        if !productColors.isEmpty { bullets.append("Matches your preferred colors") }
        if rule == "styleHistory" || referencedScore != nil { bullets.append("Matches your style") }
        if saleFact != nil { bullets.append("On sale today") }
        if rule == "favoriteAffinity" || rule == "upgrade" { bullets.append("Similar to items you've liked before") }
        if rule == "popular" { bullets.append("Popular product") }
        if bullets.isEmpty { bullets.append("Selected by your shopping filters") }
        return Array(bullets.prefix(5))
    }

    private static func customerProductName(_ value: String) -> String {
        DisplayLabelSanitizer.displayName(for: value) ?? value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func customerOutfitPhrase(_ value: String) -> String {
        let pieces = value
            .components(separatedBy: " and ")
            .flatMap { $0.components(separatedBy: ",") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .compactMap { safePiecePhrase($0) }

        if pieces.isEmpty { return "a recent outfit" }
        if pieces.count == 1 { return pieces[0] }
        if pieces.count == 2 { return "\(pieces[0]) and \(pieces[1])" }
        return pieces.dropLast().joined(separator: ", ") + ", and \(pieces.last ?? "")"
    }

    private static func safePiecePhrase(_ value: String) -> String? {
        let tokens = value.split(separator: " ").map(String.init)
        guard let item = DisplayLabelSanitizer.displayName(for: value) else { return nil }
        let color = tokens.compactMap { DisplayLabelSanitizer.safeColorName($0) }.first
        return color.map { "\($0) \(item)" } ?? item
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

    static func popularFallbackRecommendations(catalog: [AffiliateProduct], limit: Int = 4, now: Date = Date()) -> [ProductRecommendation] {
        catalog
            .filter { !$0.tags.contains(where: { $0.localizedCaseInsensitiveContains("internal") }) }
            .prefix(limit)
            .map { product in
                ProductRecommendation(
                    id: product.id,
                    product: product,
                    rank: 40,
                    reasonFacts: ProductRecommendationReasonFacts(
                        rule: "popular",
                        productName: product.name,
                        productCategory: product.category.displayName,
                        productColors: product.colors,
                        referencedOutfit: nil,
                        referencedDate: nil,
                        referencedScore: nil,
                        weatherFact: nil,
                        saleFact: hasActiveSale(product, now: now) ? "\(product.name) is currently on sale." : nil
                    )
                )
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
            guard let item = DisplayLabelSanitizer.displayName(for: clean(garment)) else { return "" }
            let color = index < colors.count ? clean(colors[index]) : ""
            let safeColor = DisplayLabelSanitizer.safeColorName(color)
            return safeColor == nil || item.localizedCaseInsensitiveContains(safeColor ?? "") ? item : "\(safeColor ?? "") \(item)"
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

struct ShoppingFeedbackRankedProduct: Identifiable, Equatable {
    let product: AffiliateProduct
    let score: Int

    var id: String { product.id }
}

enum ShoppingFeedbackProductRanker {
    static func rankedProducts(
        from products: [AffiliateProduct],
        memories: [OutfitMemory]
    ) -> [ShoppingFeedbackRankedProduct] {
        let signals = FeedbackSignals(memories: memories)
        guard signals.hasFeedback else {
            return products.map { ShoppingFeedbackRankedProduct(product: $0, score: 0) }
        }

        return products.enumerated()
            .map { index, product in
                (
                    index: index,
                    ranked: ShoppingFeedbackRankedProduct(
                        product: product,
                        score: score(product, signals: signals)
                    )
                )
            }
            .sorted { first, second in
                if first.ranked.score == second.ranked.score {
                    return first.index < second.index
                }
                return first.ranked.score > second.ranked.score
            }
            .map(\.ranked)
    }

    static func positiveRecommendations(
        from products: [AffiliateProduct],
        memories: [OutfitMemory],
        minimumCount: Int = 3
    ) -> [ShoppingFeedbackRankedProduct] {
        let positives = rankedProducts(from: products, memories: memories)
            .filter { $0.score > 0 }
        guard positives.count >= minimumCount else {
            return []
        }
        return positives
    }

    private static func score(_ product: AffiliateProduct, signals: FeedbackSignals) -> Int {
        var score = 0
        let colors = Set(product.colors.map(normalize).filter { !$0.isEmpty })
        let categories = productCategorySignals(product)
        let styles = productStyleSignals(product)
        let brand = normalize(product.brand ?? "")

        score += matchingWeight(colors, signals.positiveColors, weight: 8)
        score += matchingWeight(categories, signals.positiveCategories, weight: 10)
        score += matchingWeight(styles, signals.positiveStyles, weight: 7)
        if !brand.isEmpty, signals.positiveBrands.contains(brand) {
            score += 3
        }

        for negative in signals.negativeMemories {
            let colorPenalty = negative.dislikeReason == .colorsOff ? 10 : 5
            let stylePenalty = negative.dislikeReason == .notMyStyle ? 9 : 4
            let categoryPenalty = 4
            let brandPenalty = 2

            if !colors.isDisjoint(with: negative.colors) {
                score -= colorPenalty
            }
            if !categories.isDisjoint(with: negative.categories) {
                score -= categoryPenalty
            }
            if !styles.isDisjoint(with: negative.styles) {
                score -= stylePenalty
            }
            if !brand.isEmpty, negative.brands.contains(brand) {
                score -= brandPenalty
            }
        }

        return score
    }

    private static func matchingWeight(_ productValues: Set<String>, _ signalValues: Set<String>, weight: Int) -> Int {
        guard !productValues.isEmpty, !signalValues.isEmpty else {
            return 0
        }
        return productValues.isDisjoint(with: signalValues) ? 0 : weight
    }

    private static func productCategorySignals(_ product: AffiliateProduct) -> Set<String> {
        Set([
            normalize(product.category.rawValue),
            normalize(product.category.displayName),
            normalize(GarmentRecordHelpers.category(from: "\(product.subcategory) \(product.name)")),
            normalize(product.subcategory)
        ].filter { !$0.isEmpty })
    }

    private static func productStyleSignals(_ product: AffiliateProduct) -> Set<String> {
        Set((product.tags + (product.occasionTags ?? []) + [product.subcategory])
            .map(normalize)
            .filter { !$0.isEmpty })
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private struct FeedbackSignals {
        var positiveColors = Set<String>()
        var positiveCategories = Set<String>()
        var positiveStyles = Set<String>()
        var positiveBrands = Set<String>()
        var negativeMemories: [NegativeMemorySignals] = []
        var hasFeedback = false

        init(memories: [OutfitMemory]) {
            for memory in memories {
                if Self.isPositive(memory) {
                    hasFeedback = true
                    positiveColors.formUnion(Self.colors(memory))
                    positiveCategories.formUnion(Self.categories(memory))
                    positiveStyles.formUnion(Self.styles(memory))
                    positiveBrands.formUnion(Self.brands(memory))
                }

                if Self.isNegative(memory) {
                    hasFeedback = true
                    negativeMemories.append(
                        NegativeMemorySignals(
                            colors: Self.colors(memory),
                            categories: Self.categories(memory),
                            styles: Self.styles(memory),
                            brands: Self.brands(memory),
                            dislikeReason: memory.dislikeReason
                        )
                    )
                }
            }
        }

        private static func isPositive(_ memory: OutfitMemory) -> Bool {
            memory.wasLiked == true
                || memory.wouldWearAgain == true
                || memory.isFavorite
                || memory.wasWorn == true
                || memory.timesWorn > 0
                || memory.feedback?.verdict == .loved
                || memory.feedback?.verdict == .liked
        }

        private static func isNegative(_ memory: OutfitMemory) -> Bool {
            memory.wasLiked == false
                || memory.wouldWearAgain == false
                || memory.feedback?.verdict == .notForMe
        }

        private static func colors(_ memory: OutfitMemory) -> Set<String> {
            Set((memory.colors + memory.garmentRecords.flatMap(\.colors))
                .map(ShoppingFeedbackProductRanker.normalize)
                .filter { !$0.isEmpty })
        }

        private static func categories(_ memory: OutfitMemory) -> Set<String> {
            Set(memory.garmentRecords
                .map(\.garmentCategory)
                .map(ShoppingFeedbackProductRanker.normalize)
                .filter { !$0.isEmpty })
        }

        private static func styles(_ memory: OutfitMemory) -> Set<String> {
            Set(([memory.detectedStyle] + memory.garmentRecords.flatMap(\.styleTags))
                .map(ShoppingFeedbackProductRanker.normalize)
                .filter { !$0.isEmpty })
        }

        private static func brands(_ memory: OutfitMemory) -> Set<String> {
            Set(memory.garmentRecords
                .compactMap(\.brand)
                .map(ShoppingFeedbackProductRanker.normalize)
                .filter { !$0.isEmpty })
        }
    }

    private struct NegativeMemorySignals {
        let colors: Set<String>
        let categories: Set<String>
        let styles: Set<String>
        let brands: Set<String>
        let dislikeReason: DislikeReason?
    }
}

struct ScanCompleteLookAccessoryRecommender {
    static func recommendations(
        for analysis: OutfitAnalysisResult,
        catalog: [AffiliateProduct],
        limit: Int = 2
    ) -> [AffiliateProduct] {
        guard shouldRecommendAccessories(for: analysis) else {
            return []
        }

        let scanColors = Set(analysis.colorPalette.map(normalize).filter { !$0.isEmpty })
        let occasionSignals = Set(occasionTokens(from: analysis.occasionFit))

        let ranked = catalog.enumerated().compactMap { index, product -> (index: Int, product: AffiliateProduct, rank: Int)? in
            guard product.category == .accessories else {
                return nil
            }

            let productColors = Set(product.colors.map(normalize).filter { !$0.isEmpty })
            let productOccasions = Set((product.occasionTags ?? []).flatMap(occasionTokens))
            let colorMatch = !scanColors.isEmpty && !productColors.isDisjoint(with: scanColors)
            let occasionMatch = !occasionSignals.isEmpty && !productOccasions.isDisjoint(with: occasionSignals)

            guard colorMatch || occasionMatch else {
                return nil
            }

            var rank = 0
            if colorMatch { rank += 10 }
            if occasionMatch { rank += 4 }
            return (index, product, rank)
        }

        return ranked
            .sorted { first, second in
                if first.rank == second.rank {
                    return first.index < second.index
                }
                return first.rank > second.rank
            }
            .prefix(limit)
            .map(\.product)
    }

    static func shouldRecommendAccessories(for analysis: OutfitAnalysisResult) -> Bool {
        guard let breakdown = analysis.scoreBreakdown else {
            return false
        }

        let color = Double(breakdown.colorHarmony) / 25.0
        let pattern = Double(breakdown.patternBalance) / 20.0
        let fit = Double(breakdown.fitQuality) / 25.0
        let accessories = Double(breakdown.accessoryUse) / 10.0

        return breakdown.accessoryUse <= 5
            && accessories < color
            && accessories < pattern
            && accessories < fit
    }

    private static func occasionTokens(from value: String) -> [String] {
        value
            .lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count > 2 }
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
