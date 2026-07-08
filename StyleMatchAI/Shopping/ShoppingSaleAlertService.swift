import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

enum ShoppingSaleAlertTrigger: String, Codable, Equatable {
    case favoriteSale
    case wishlistSale
    case cartPriceDrop
    case shoppingCardSale
    case savedStyleSale
    case pastOutfitMatchSale
    case backInStock

    var priority: Int {
        switch self {
        case .cartPriceDrop: return 100
        case .favoriteSale: return 90
        case .wishlistSale: return 85
        case .shoppingCardSale: return 80
        case .pastOutfitMatchSale: return 70
        case .savedStyleSale: return 60
        case .backInStock: return 50
        }
    }
}

struct ShoppingSaleAlert: Identifiable, Codable, Equatable {
    let id: String
    let productID: String
    let productName: String
    let retailerName: String
    let trigger: ShoppingSaleAlertTrigger
    let title: String
    let message: String
    let discountPercent: Int?
    let salePrice: Decimal?
    let originalPrice: Decimal?
    let saleEndsAt: Date?
}

struct ShoppingSaleStateSnapshot: Codable, Equatable {
    let productID: String
    let salePrice: Decimal?
    let saleEndsAt: Date?
    let isActiveSale: Bool

    static func snapshot(for product: AffiliateProduct, now: Date) -> ShoppingSaleStateSnapshot {
        ShoppingSaleStateSnapshot(
            productID: product.id,
            salePrice: product.salePrice,
            saleEndsAt: product.saleEndsAt,
            isActiveSale: ShoppingSaleAlertService.isActiveSale(product, now: now)
        )
    }
}

struct ShoppingSaleAlertContext {
    let favoriteProductIDs: Set<String>
    let wishlistProductIDs: Set<String>
    let cartProductIDs: Set<String>
    let shoppingCardProductIDs: Set<String>
    let savedStyleProducts: [AffiliateProduct]
    let memories: [OutfitMemory]
    let now: Date

    init(
        favoriteProductIDs: Set<String> = [],
        wishlistProductIDs: Set<String> = [],
        cartProductIDs: Set<String> = [],
        shoppingCardProductIDs: Set<String> = [],
        savedStyleProducts: [AffiliateProduct] = [],
        memories: [OutfitMemory] = [],
        now: Date = Date()
    ) {
        self.favoriteProductIDs = favoriteProductIDs
        self.wishlistProductIDs = wishlistProductIDs
        self.cartProductIDs = cartProductIDs
        self.shoppingCardProductIDs = shoppingCardProductIDs
        self.savedStyleProducts = savedStyleProducts
        self.memories = memories
        self.now = now
    }
}

enum ShoppingSaleAlertService {
    static func alerts(
        catalog: [AffiliateProduct],
        context: ShoppingSaleAlertContext,
        limit: Int = 12
    ) -> [ShoppingSaleAlert] {
        let candidates = catalog.flatMap { product in
            alerts(for: product, context: context)
        }
        .sorted { lhs, rhs in
            if lhs.trigger.priority == rhs.trigger.priority {
                return lhs.productName < rhs.productName
            }
            return lhs.trigger.priority > rhs.trigger.priority
        }

        var seen = Set<String>()
        let deduped = candidates.filter { alert in
            let key = "\(alert.productID)-\(alert.trigger.rawValue)"
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }

        return Array(deduped.prefix(max(0, limit)))
    }

    static func notificationAlerts(
        catalog: [AffiliateProduct],
        context: ShoppingSaleAlertContext,
        previousSnapshots: [String: ShoppingSaleStateSnapshot],
        limit: Int = 3
    ) -> [ShoppingSaleAlert] {
        let changedProductIDs = Set(catalog.compactMap { product -> String? in
            guard let previous = previousSnapshots[product.id],
                  saleStateChanged(for: product, previous: previous, now: context.now) else {
                return nil
            }
            return product.id
        })

        guard !changedProductIDs.isEmpty else { return [] }
        return alerts(catalog: catalog.filter { changedProductIDs.contains($0.id) }, context: context, limit: limit)
            .filter { [.favoriteSale, .savedStyleSale].contains($0.trigger) }
    }

    static func saleStateSnapshots(catalog: [AffiliateProduct], now: Date = Date()) -> [String: ShoppingSaleStateSnapshot] {
        Dictionary(uniqueKeysWithValues: catalog.map { product in
            (product.id, ShoppingSaleStateSnapshot.snapshot(for: product, now: now))
        })
    }

    static func groupedSections(from alerts: [ShoppingSaleAlert]) -> [(title: String, alerts: [ShoppingSaleAlert])] {
        let direct = alerts.filter { [.favoriteSale, .wishlistSale, .cartPriceDrop, .shoppingCardSale].contains($0.trigger) }
        let personalized = alerts.filter { [.savedStyleSale, .pastOutfitMatchSale].contains($0.trigger) }
        let stock = alerts.filter { $0.trigger == .backInStock }

        return [
            ("Saved & Cart Deals", direct),
            ("Matches Your Style", personalized),
            ("Back in Stock", stock)
        ].filter { !$0.alerts.isEmpty }
    }

    private static func alerts(for product: AffiliateProduct, context: ShoppingSaleAlertContext) -> [ShoppingSaleAlert] {
        var alerts: [ShoppingSaleAlert] = []
        let activeSale = isActiveSale(product, now: context.now)
        let backInStock = product.tags.contains { $0.caseInsensitiveCompare("back-in-stock") == .orderedSame }

        if activeSale, context.favoriteProductIDs.contains(product.id) {
            alerts.append(makeAlert(product: product, trigger: .favoriteSale, reason: "you saved it in Favorites", context: context))
        }
        if activeSale, context.wishlistProductIDs.contains(product.id) {
            alerts.append(makeAlert(product: product, trigger: .wishlistSale, reason: "it is on your wishlist", context: context))
        }
        if activeSale, context.cartProductIDs.contains(product.id) {
            alerts.append(makeAlert(product: product, trigger: .cartPriceDrop, reason: "it is in your cart", context: context))
        }
        if activeSale, context.shoppingCardProductIDs.contains(product.id) {
            alerts.append(makeAlert(product: product, trigger: .shoppingCardSale, reason: "you saved its shopping card", context: context))
        }
        if activeSale, matchesSavedStyle(product, context: context) {
            alerts.append(makeAlert(product: product, trigger: .savedStyleSale, reason: "it matches your saved style", context: context))
        }
        if activeSale, let memory = matchingPastOutfit(product: product, memories: context.memories, now: context.now) {
            alerts.append(makePastOutfitAlert(product: product, memory: memory, now: context.now))
        }
        if backInStock && (context.favoriteProductIDs.contains(product.id) || context.wishlistProductIDs.contains(product.id) || context.cartProductIDs.contains(product.id)) {
            alerts.append(makeAlert(product: product, trigger: .backInStock, reason: "you saved it", context: context))
        }

        return alerts
    }

    private static func makeAlert(
        product: AffiliateProduct,
        trigger: ShoppingSaleAlertTrigger,
        reason: String,
        context: ShoppingSaleAlertContext
    ) -> ShoppingSaleAlert {
        let discount = discountPercent(product)
        let title = trigger == .backInStock ? "Back in stock" : "Shopping deal"
        let lead: String
        if let discount {
            lead = "Good news - the \(product.name) is now \(discount)% off."
        } else if trigger == .backInStock {
            lead = "Good news - the \(product.name) is back in stock."
        } else {
            lead = "Good news - the \(product.name) is on sale."
        }
        let deadline = saleDeadlineText(product.saleEndsAt, now: context.now)
        let message = [lead, "This matters because \(reason).", deadline].compactMap { $0 }.joined(separator: " ")

        return ShoppingSaleAlert(
            id: alertID(product: product, trigger: trigger),
            productID: product.id,
            productName: product.name,
            retailerName: product.retailer.name,
            trigger: trigger,
            title: title,
            message: message,
            discountPercent: discount,
            salePrice: product.salePrice,
            originalPrice: product.price,
            saleEndsAt: product.saleEndsAt
        )
    }

    private static func makePastOutfitAlert(product: AffiliateProduct, memory: OutfitMemory, now: Date) -> ShoppingSaleAlert {
        let dateText = OutfitRecallService.relativeDateText(for: memory.scanDate, now: now)
        let outfit = outfitPhrase(garments: memory.detectedGarments, colors: memory.colors)
        let discount = discountPercent(product)
        let saleText = discount.map { "is now \($0)% off" } ?? "is on sale"
        return ShoppingSaleAlert(
            id: alertID(product: product, trigger: .pastOutfitMatchSale),
            productID: product.id,
            productName: product.name,
            retailerName: product.retailer.name,
            trigger: .pastOutfitMatchSale,
            title: "Matches a past outfit",
            message: "This \(product.subcategory) \(saleText) and would match \(outfit) you scanned \(dateText).",
            discountPercent: discount,
            salePrice: product.salePrice,
            originalPrice: product.price,
            saleEndsAt: product.saleEndsAt
        )
    }

    static func isActiveSale(_ product: AffiliateProduct, now: Date) -> Bool {
        guard let salePrice = product.salePrice, salePrice > 0 else { return false }
        if let price = product.price, salePrice >= price { return false }
        return (product.saleEndsAt ?? .distantFuture) > now
    }

    private static func saleStateChanged(for product: AffiliateProduct, previous: ShoppingSaleStateSnapshot, now: Date) -> Bool {
        let current = ShoppingSaleStateSnapshot.snapshot(for: product, now: now)
        guard current.isActiveSale else { return false }
        return previous.isActiveSale == false
            || previous.salePrice != current.salePrice
            || previous.saleEndsAt != current.saleEndsAt
    }

    private static func discountPercent(_ product: AffiliateProduct) -> Int? {
        guard let price = product.price, let sale = product.salePrice, price > 0, sale < price else { return nil }
        let discount = ((price - sale) / price) * 100
        return NSDecimalNumber(decimal: discount).rounding(accordingToBehavior: nil).intValue
    }

    private static func matchesSavedStyle(_ product: AffiliateProduct, context: ShoppingSaleAlertContext) -> Bool {
        let productFamilies = Set(product.colors.map(colorFamily).filter { !$0.isEmpty })
        return context.savedStyleProducts.contains { saved in
            saved.subcategory.caseInsensitiveCompare(product.subcategory) == .orderedSame
                || saved.brand?.caseInsensitiveCompare(product.brand ?? "") == .orderedSame
                || !productFamilies.isDisjoint(with: Set(saved.colors.map(colorFamily).filter { !$0.isEmpty }))
        }
    }

    private static func matchingPastOutfit(product: AffiliateProduct, memories: [OutfitMemory], now: Date) -> OutfitMemory? {
        let cutoff = now.addingTimeInterval(-30 * 24 * 60 * 60)
        let productCategory = garmentCategory(product)
        let productColors = Set(product.colors.map { clean($0).lowercased() }.filter { !$0.isEmpty })

        return memories
            .filter { $0.scanDate >= cutoff }
            .sorted { $0.scanDate > $1.scanDate }
            .first { memory in
                memory.garmentRecords.contains { record in
                    CategoryPairingRules.complementaryCategories(for: record.garmentCategory).contains(productCategory)
                        && !productColors.isDisjoint(with: ColorPairingRules.complementaryColors(for: record.colors.first))
                }
            }
    }

    private static func saleDeadlineText(_ date: Date?, now: Date) -> String? {
        guard let date, date > now else { return nil }
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: now), to: Calendar.current.startOfDay(for: date)).day ?? 0
        if days == 0 { return "The discount ends today." }
        if days == 1 { return "The discount ends tomorrow." }
        if days <= 7 { return "The discount ends in \(days) days." }
        return nil
    }

    private static func alertID(product: AffiliateProduct, trigger: ShoppingSaleAlertTrigger) -> String {
        let saleToken = product.salePrice.map { NSDecimalNumber(decimal: $0).stringValue } ?? "stock"
        return "\(product.id)-\(trigger.rawValue)-\(saleToken)"
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
        if pieces.isEmpty { return "a past outfit" }
        if pieces.count == 1 { return pieces[0] }
        if pieces.count == 2 { return "\(pieces[0]) and \(pieces[1])" }
        return pieces.dropLast().joined(separator: ", ") + ", and \(pieces.last ?? "")"
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
