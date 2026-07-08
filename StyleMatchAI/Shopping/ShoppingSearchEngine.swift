import Foundation

enum ShoppingSearchEngine {
    static func filter(products: [AffiliateProduct], criteria: ShoppingSearchCriteria) -> [AffiliateProduct] {
        guard !criteria.isEmpty else {
            return products
        }

        return products.filter { product in
            matchesQuery(product, criteria.query)
                && matchesStore(product, criteria.storeName)
                && matchesBrand(product, criteria.brand)
                && matchesCategory(product, criteria.category)
                && matchesColor(product, criteria.color)
                && matchesSize(product, criteria.size)
                && matchesStyle(product, criteria.style)
                && matchesGender(product, criteria.genderPresentation)
                && matchesPrice(product, min: criteria.minimumPrice, max: criteria.maximumPrice)
                && matchesOccasion(product, criteria.occasion)
        }
    }

    static func filter(products: [AffiliateProduct], query: ProductSearchQuery, now: Date = Date()) -> [AffiliateProduct] {
        let filtered = products.filter { product in
            matchesQuery(product, query.text ?? "")
                && matchesAny(product.retailer.name, query.retailers)
                && matchesAny(product.brand, query.brands, requireValueWhenFiltering: true)
                && matchesAny(product.category, query.categories)
                && matchesAny(product.colors, query.colors)
                && matchesAny(product.sizes ?? [], query.sizes)
                && matchesGender(product, query.genderPresentation)
                && matchesPrice(product, range: query.priceRange)
                && matchesAny((product.occasionTags ?? []) + product.tags, query.occasions)
                && matchesSale(product, onSaleOnly: query.onSaleOnly, now: now)
        }

        return sorted(filtered, by: query.sort)
    }

    static func filterStores(_ stores: [SupportedStore], query: String) -> [SupportedStore] {
        let cleaned = normalize(query)
        guard !cleaned.isEmpty else {
            return stores.filter(\.isEnabled)
        }

        return stores.filter { store in
            store.isEnabled && searchableText(for: store).contains(cleaned)
        }
    }

    private static func matchesQuery(_ product: AffiliateProduct, _ query: String) -> Bool {
        let cleaned = normalize(query)
        guard !cleaned.isEmpty else { return true }
        return searchableText(for: product).contains(cleaned)
    }

    private static func matchesStore(_ product: AffiliateProduct, _ storeName: String?) -> Bool {
        guard let storeName, !storeName.isEmpty else { return true }
        return product.retailer.name.caseInsensitiveCompare(storeName) == .orderedSame
    }

    private static func matchesBrand(_ product: AffiliateProduct, _ brand: String?) -> Bool {
        guard let brand, !brand.isEmpty else { return true }
        guard let productBrand = product.brand, !productBrand.isEmpty else { return false }
        return normalize(productBrand).contains(normalize(brand))
    }

    private static func matchesCategory(_ product: AffiliateProduct, _ category: ProductCategory?) -> Bool {
        guard let category else { return true }
        return product.category == category
    }

    private static func matchesColor(_ product: AffiliateProduct, _ color: String?) -> Bool {
        guard let color, !color.isEmpty else { return true }
        let normalized = normalize(color)
        return product.colors.contains { normalize($0).contains(normalized) }
    }

    private static func matchesSize(_ product: AffiliateProduct, _ size: String?) -> Bool {
        guard let size, !size.isEmpty else { return true }
        let normalized = normalize(size)
        return (product.sizes ?? []).contains { normalize($0).contains(normalized) }
            || product.tags.contains { normalize($0).contains(normalized) }
            || normalize(product.subcategory).contains(normalized)
    }

    private static func matchesStyle(_ product: AffiliateProduct, _ style: String?) -> Bool {
        guard let style, !style.isEmpty else { return true }
        let normalized = normalize(style)
        return product.tags.contains { normalize($0).contains(normalized) }
            || normalize(product.subcategory).contains(normalized)
    }

    private static func matchesGender(_ product: AffiliateProduct, _ gender: String?) -> Bool {
        guard let gender, !gender.isEmpty else { return true }
        guard let presentation = product.genderPresentation else { return true }
        return normalize(presentation).contains(normalize(gender))
    }

    private static func matchesPrice(_ product: AffiliateProduct, min: Decimal?, max: Decimal?) -> Bool {
        guard min != nil || max != nil else { return true }
        guard product.retailer.name.caseInsensitiveCompare("Amazon") != .orderedSame else {
            return false
        }

        if let price = product.salePrice ?? product.price {
            if let min, price < min { return false }
            if let max, price > max { return false }
            return true
        }

        if let priceRange = product.priceRange {
            if let min, priceRange.upperBound < min { return false }
            if let max, priceRange.lowerBound > max { return false }
            return true
        }

        return false
    }

    private static func matchesPrice(_ product: AffiliateProduct, range: ClosedRange<Decimal>?) -> Bool {
        guard let range else { return true }
        guard product.retailer.name.caseInsensitiveCompare("Amazon") != .orderedSame else {
            return false
        }

        if let price = product.salePrice ?? product.price {
            return range.contains(price)
        }

        if let productRange = product.priceRange {
            return productRange.upperBound >= range.lowerBound && productRange.lowerBound <= range.upperBound
        }

        return false
    }

    private static func matchesOccasion(_ product: AffiliateProduct, _ occasion: String?) -> Bool {
        guard let occasion, !occasion.isEmpty else { return true }
        let normalized = normalize(occasion)
        return (product.occasionTags ?? []).contains { normalize($0).contains(normalized) }
            || product.tags.contains { normalize($0).contains(normalized) }
            || searchableText(for: product).contains(normalized)
    }

    private static func searchableText(for product: AffiliateProduct) -> String {
        normalize((
            [
                product.name,
                product.subcategory,
                product.retailer.name,
                product.brand ?? "",
                product.category.displayName,
                product.genderPresentation ?? ""
            ]
            + product.colors
            + (product.sizes ?? [])
            + product.tags
            + (product.occasionTags ?? [])
        ).joined(separator: " "))
    }

    private static func searchableText(for store: SupportedStore) -> String {
        normalize(([store.id, store.name, store.affiliateNetwork ?? "", store.apiStatus] + store.domains + store.categories.map(\.displayName)).joined(separator: " "))
    }

    private static func matchesAny(_ value: String?, _ filters: [String]?, requireValueWhenFiltering: Bool = false) -> Bool {
        guard let filters = normalizedFilters(filters), !filters.isEmpty else { return true }
        guard let value, !value.isEmpty else { return !requireValueWhenFiltering }
        let normalizedValue = normalize(value)
        return filters.contains { normalizedValue.contains($0) }
    }

    private static func matchesAny(_ values: [String], _ filters: [String]?) -> Bool {
        guard let filters = normalizedFilters(filters), !filters.isEmpty else { return true }
        return values.contains { value in
            let normalizedValue = normalize(value)
            return filters.contains { normalizedValue.contains($0) }
        }
    }

    private static func matchesAny(_ value: ProductCategory, _ filters: [ProductCategory]?) -> Bool {
        guard let filters, !filters.isEmpty else { return true }
        return filters.contains(value)
    }

    private static func matchesSale(_ product: AffiliateProduct, onSaleOnly: Bool, now: Date) -> Bool {
        guard onSaleOnly else { return true }
        return product.salePrice != nil && (product.saleEndsAt ?? .distantFuture) > now
    }

    private static func sorted(_ products: [AffiliateProduct], by sort: SearchSort) -> [AffiliateProduct] {
        switch sort {
        case .relevance:
            return products
        case .priceLowHigh:
            return products.sorted { (sortablePrice($0) ?? highPriceSentinel) < (sortablePrice($1) ?? highPriceSentinel) }
        case .priceHighLow:
            return products.sorted { (sortablePrice($0) ?? lowPriceSentinel) > (sortablePrice($1) ?? lowPriceSentinel) }
        case .newestSale:
            return products.sorted { ($0.saleEndsAt ?? .distantPast) > ($1.saleEndsAt ?? .distantPast) }
        }
    }

    private static func sortablePrice(_ product: AffiliateProduct) -> Decimal? {
        guard product.retailer.name.caseInsensitiveCompare("Amazon") != .orderedSame else {
            return nil
        }

        return product.salePrice ?? product.price ?? product.priceRange?.lowerBound
    }

    private static func normalizedFilters(_ filters: [String]?) -> [String]? {
        filters?
            .map(normalize)
            .filter { !$0.isEmpty }
    }

    private static let highPriceSentinel = Decimal(999_999_999)
    private static let lowPriceSentinel = Decimal(-1)

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
