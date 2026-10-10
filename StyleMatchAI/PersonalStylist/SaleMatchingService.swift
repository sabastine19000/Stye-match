import Foundation

struct PersonalStylistDealMatch: Codable, Equatable {
    let productName: String
    let retailerName: String
    let category: String
    let salePrice: String
    let reason: String
}

struct Deal: Codable, Equatable {
    let itemName: String
    let category: String
    let colors: [String]
    let salePrice: Decimal
    let originalPrice: Decimal
    let url: URL?
}

struct SaleMatchScanContext: Equatable {
    let detectedGarments: [String]
    let colors: [String]
    let detectedStyle: String
    let occasion: String
}

protocol DealProvider {
    func currentDeals() async throws -> [Deal]
}

struct StaticDealProvider: DealProvider {
    let deals: [Deal]

    func currentDeals() async throws -> [Deal] {
        deals
    }
}

struct MockDealProvider: DealProvider {
    let fixtureURL: URL

    func currentDeals() async throws -> [Deal] {
        let data = try Data(contentsOf: fixtureURL)
        return try JSONDecoder().decode([Deal].self, from: data)
    }
}

struct CatalogDealProvider: DealProvider {
    let catalogProvider: ProductCatalogProvider
    let now: Date
    let similarStyleProducts: [AffiliateProduct]
    let frequentlyWornRecords: [GarmentRecord]

    init(
        catalogProvider: ProductCatalogProvider,
        now: Date = Date(),
        similarStyleProducts: [AffiliateProduct] = [],
        frequentlyWornRecords: [GarmentRecord] = []
    ) {
        self.catalogProvider = catalogProvider
        self.now = now
        self.similarStyleProducts = similarStyleProducts
        self.frequentlyWornRecords = frequentlyWornRecords
    }

    func currentDeals() async throws -> [Deal] {
        let products = try await catalogProvider.products()
        return products.compactMap { product in
            guard let salePrice = product.salePrice,
                  (product.saleEndsAt ?? .distantFuture) > now,
                  matchesSavedStyleIfAvailable(product) else {
                return nil
            }

            return Deal(
                itemName: product.name,
                category: product.subcategory,
                colors: product.colors,
                salePrice: salePrice,
                originalPrice: product.price ?? salePrice,
                url: product.affiliateURL
            )
        }
    }

    private func matchesSavedStyleIfAvailable(_ product: AffiliateProduct) -> Bool {
        guard !similarStyleProducts.isEmpty || !frequentlyWornRecords.isEmpty else {
            return true
        }

        return Self.productMatchesSavedStyle(
            product,
            similarStyleProducts: similarStyleProducts,
            frequentlyWornRecords: frequentlyWornRecords
        )
    }

    static func productMatchesSavedStyle(
        _ product: AffiliateProduct,
        similarStyleProducts: [AffiliateProduct],
        frequentlyWornRecords: [GarmentRecord]
    ) -> Bool {
        let productSubcategory = product.subcategory.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let productFamilies = Set(product.colors.map(colorFamily).filter { !$0.isEmpty })

        if similarStyleProducts.contains(where: { favorite in
            favorite.subcategory.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == productSubcategory
                && !productFamilies.isDisjoint(with: Set(favorite.colors.map(colorFamily).filter { !$0.isEmpty }))
        }) {
            return true
        }

        return frequentlyWornRecords.contains { record in
            let recordCategory = record.garmentCategory.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let recordFamilies = Set(record.colors.map(colorFamily).filter { !$0.isEmpty })
            return (recordCategory == productSubcategory || productSubcategory.contains(recordCategory))
                && !productFamilies.isDisjoint(with: recordFamilies)
        }
    }

    private static func colorFamily(_ color: String) -> String {
        let value = color.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ["black", "charcoal"].contains(value) { return "black" }
        if ["white", "cream"].contains(value) { return "white" }
        if ["gray", "grey", "silver"].contains(value) { return "gray" }
        if ["navy", "blue", "denim"].contains(value) { return "blue" }
        if ["tan", "beige", "khaki", "brown"].contains(value) { return "brown" }
        return value
    }
}

enum SaleMatchingService {
    static func matches(
        for context: SaleMatchScanContext,
        provider: DealProvider,
        saleMatchingEnabled: Bool = FeatureFlags.saleMatchingEnabled,
        limit: Int = 3
    ) async throws -> [PersonalStylistDealMatch] {
        guard saleMatchingEnabled else {
            return []
        }

        let deals = try await provider.currentDeals()
        return Array(
            deals
                .filter { matches(context: context, deal: $0) }
                .filter(isComplete)
                .map(match(from:))
                .prefix(max(0, limit))
        )
    }

    static func dealMessages(
        for memories: [OutfitMemory],
        provider: DealProvider,
        saleMatchingEnabled: Bool = FeatureFlags.saleMatchingEnabled,
        now: Date = Date(),
        limit: Int = 3
    ) async throws -> [String] {
        guard saleMatchingEnabled else {
            return []
        }

        let deals = try await provider.currentDeals()
        let candidates = deals
            .filter(isComplete)
            .compactMap { deal -> (message: String, score: Int)? in
                dealMessage(for: deal, memories: memories, now: now)
            }
            .sorted { $0.score > $1.score }
            .map(\.message)

        return Array(candidates.prefix(max(0, limit)))
    }

    private static func matches(context: SaleMatchScanContext, deal: Deal) -> Bool {
        let categories = Set(context.detectedGarments.map { GarmentRecordHelpers.category(from: $0) })
        let dealCategory = GarmentRecordHelpers.category(from: deal.category)
        let dealNameCategory = GarmentRecordHelpers.category(from: deal.itemName)
        let scanColors = Set(context.colors.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty })
        let dealColors = Set(deal.colors.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty })

        let categoryMatches = categories.contains(dealCategory) || categories.contains(dealNameCategory)
        let colorMatches = scanColors.isEmpty || dealColors.isEmpty || !scanColors.isDisjoint(with: dealColors)
        return categoryMatches && colorMatches
    }

    private static func isComplete(_ deal: Deal) -> Bool {
        !deal.itemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !deal.category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && deal.salePrice > 0
            && deal.originalPrice >= deal.salePrice
    }

    private static func match(from deal: Deal) -> PersonalStylistDealMatch {
        let retailer = deal.url?.host(percentEncoded: false) ?? "approved retailer"
        return PersonalStylistDealMatch(
            productName: deal.itemName,
            retailerName: retailer,
            category: deal.category,
            salePrice: currency(deal.salePrice),
            reason: "Matches the scanned \(deal.category) category and listed deal colors: \(deal.colors.joined(separator: ", "))."
        )
    }

    private static func dealMessage(for deal: Deal, memories: [OutfitMemory], now: Date) -> (message: String, score: Int)? {
        let matches = memories.compactMap { memory -> (message: String, score: Int)? in
            if let score = complementScore(deal: deal, memory: memory), score > 0 {
                return (dealSentence(deal: deal, memory: memory, now: now, reason: "pair well"), score)
            }

            if let score = upgradeScore(deal: deal, memory: memory), score > 0 {
                return (dealSentence(deal: deal, memory: memory, now: now, reason: "upgrade"), score)
            }

            return nil
        }
        .sorted { first, second in
            if first.score == second.score {
                return first.message < second.message
            }
            return first.score > second.score
        }

        return matches.first
    }

    private static func complementScore(deal: Deal, memory: OutfitMemory) -> Int? {
        let dealCategory = GarmentRecordHelpers.category(from: deal.category)
        let dealColors = normalizedColors(deal.colors)
        guard !dealColors.isEmpty else {
            return nil
        }

        let matchedRecord = memory.garmentRecords.first { record in
            CategoryPairingRules.complementaryCategories(for: record.garmentCategory).contains(dealCategory)
                && !dealColors.isDisjoint(with: ColorPairingRules.complementaryColors(for: record.colors.first))
        }

        guard matchedRecord != nil else {
            return nil
        }

        return 80 + min(10, memory.styleScore / 10)
    }

    private static func upgradeScore(deal: Deal, memory: OutfitMemory) -> Int? {
        let isLowSignal = memory.wasLiked == false || memory.wouldWearAgain == false || memory.styleScore < 75
        guard isLowSignal else {
            return nil
        }

        let dealCategory = GarmentRecordHelpers.category(from: deal.category)
        let dealColorFamilies = Set(deal.colors.map(colorFamily).filter { !$0.isEmpty })
        guard !dealColorFamilies.isEmpty else {
            return nil
        }

        let matchesStoredItem = memory.garmentRecords.contains { record in
            let recordFamilies = Set(record.colors.map(colorFamily).filter { !$0.isEmpty })
            return record.garmentCategory == dealCategory && !recordFamilies.isDisjoint(with: dealColorFamilies)
        }

        return matchesStoredItem ? 70 + max(0, 75 - memory.styleScore) : nil
    }

    private static func dealSentence(deal: Deal, memory: OutfitMemory, now: Date, reason: String) -> String {
        let dealDescription = deal.colors.first.map { "\($0) \(deal.category)" } ?? deal.itemName
        let outfitDescription = storedOutfitPhrase(memory)
        let dateText = OutfitRecallService.relativeDateText(for: memory.scanDate, now: now)

        switch reason {
        case "upgrade":
            return "A \(dealDescription) just went on sale\(retailerPhrase(deal)) — it could upgrade the \(outfitDescription) you wore \(dateText)."
        default:
            return "A \(dealDescription) just went on sale\(retailerPhrase(deal)) — it would pair well with the \(outfitDescription) you wore \(dateText)."
        }
    }

    private static func retailerPhrase(_ deal: Deal) -> String {
        guard let host = deal.url?.host?.lowercased() else {
            return ""
        }
        if host.contains("macys") { return " at Macy's" }
        if host.contains("nike") { return " at Nike" }
        if host.contains("bestbuy") { return " at Best Buy" }
        if host.contains("amazon") { return " at Amazon" }
        if host.contains("nordstrom") { return " at Nordstrom" }
        if host.contains("levi") { return " at Levi's" }
        if host.contains("target") { return " at Target" }
        return ""
    }

    private static func storedOutfitPhrase(_ memory: OutfitMemory) -> String {
        let garments = memory.detectedGarments.map(clean).filter { !$0.isEmpty }
        let colors = memory.colors.map(clean).filter { !$0.isEmpty }
        let pieces = garments.enumerated().map { index, garment in
            index < colors.count ? "\(colors[index]) \(garment)" : garment
        }

        if pieces.isEmpty {
            return "outfit"
        }
        if pieces.count == 1 {
            return pieces[0]
        }
        if pieces.count == 2 {
            return "\(pieces[0]) and \(pieces[1])"
        }
        return pieces.dropLast().joined(separator: ", ") + ", and \(pieces.last ?? "")"
    }

    private static func normalizedColors(_ colors: [String]) -> Set<String> {
        Set(colors.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty })
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

    private static func currency(_ value: Decimal) -> String {
        let number = value as NSDecimalNumber
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        formatter.locale = Locale(identifier: "en_US")
        return formatter.string(from: number) ?? "$\(number)"
    }
}
