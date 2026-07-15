import Foundation

enum ShoppingSearchEngine {
    enum RelaxableFilter: String, CaseIterable, Equatable {
        case occasion
        case style
        case maxPrice
        case color
        case size
        case brand
        case store
        case category

        var displayName: String {
            switch self {
            case .occasion: return "occasion"
            case .style: return "style"
            case .maxPrice: return "max price"
            case .color: return "color"
            case .size: return "size"
            case .brand: return "brand"
            case .store: return "store"
            case .category: return "category"
            }
        }
    }

    struct RelaxedFilterResult: Equatable {
        let exactResults: [AffiliateProduct]
        let relaxedResults: [AffiliateProduct]
        let relaxedFilter: RelaxableFilter?

        var displayedResults: [AffiliateProduct] {
            relaxedFilter == nil ? exactResults : relaxedResults
        }
    }

    static func filter(products: [AffiliateProduct], criteria: ShoppingSearchCriteria) -> [AffiliateProduct] {
        relaxedFilter(products: products, criteria: criteria).displayedResults
    }

    static func relaxedFilter(products: [AffiliateProduct], criteria: ShoppingSearchCriteria) -> RelaxedFilterResult {
        guard !criteria.isEmpty else {
            return RelaxedFilterResult(exactResults: products, relaxedResults: [], relaxedFilter: nil)
        }

        return relaxedFilter(
            products: products,
            predicates: [
                SearchPredicate(kind: nil, isActive: !criteria.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) { matchesQuery($0, criteria.query) },
                SearchPredicate(kind: .store, isActive: active(criteria.storeName)) { matchesStore($0, criteria.storeName) },
                SearchPredicate(kind: .brand, isActive: active(criteria.brand)) { matchesBrand($0, criteria.brand) },
                SearchPredicate(kind: .category, isActive: criteria.category != nil) { matchesCategory($0, criteria.category) },
                SearchPredicate(kind: .color, isActive: active(criteria.color)) { matchesColor($0, criteria.color) },
                SearchPredicate(kind: .size, isActive: active(criteria.size)) { matchesSize($0, criteria.size) },
                SearchPredicate(kind: .style, isActive: active(criteria.style)) { matchesStyle($0, criteria.style) },
                SearchPredicate(kind: nil, isActive: active(criteria.genderPresentation)) { matchesGender($0, criteria.genderPresentation) },
                SearchPredicate(kind: .maxPrice, isActive: criteria.maximumPrice != nil) { matchesPrice($0, min: criteria.minimumPrice, max: criteria.maximumPrice) },
                SearchPredicate(kind: nil, isActive: criteria.minimumPrice != nil && criteria.maximumPrice == nil) { matchesPrice($0, min: criteria.minimumPrice, max: criteria.maximumPrice) },
                SearchPredicate(kind: .occasion, isActive: active(criteria.occasion)) { matchesOccasion($0, criteria.occasion) }
            ]
        )
    }

    static func filter(products: [AffiliateProduct], query: ProductSearchQuery, now: Date = Date()) -> [AffiliateProduct] {
        relaxedFilter(products: products, query: query, now: now).displayedResults
    }

    static func relaxedFilter(products: [AffiliateProduct], query: ProductSearchQuery, now: Date = Date()) -> RelaxedFilterResult {
        let result = relaxedFilter(
            products: products,
            predicates: [
                SearchPredicate(kind: nil, isActive: active(query.text)) { matchesQuery($0, query.text ?? "") },
                SearchPredicate(kind: .store, isActive: active(query.retailers)) { matchesAny($0.retailer.name, query.retailers) },
                SearchPredicate(kind: .brand, isActive: active(query.brands)) { matchesAny($0.brand, query.brands, requireValueWhenFiltering: true) },
                SearchPredicate(kind: .category, isActive: query.categories?.isEmpty == false) { matchesAny($0.category, query.categories) },
                SearchPredicate(kind: .color, isActive: active(query.colors)) { matchesAny($0.colors, query.colors) },
                SearchPredicate(kind: .size, isActive: active(query.sizes)) { matchesAny($0.sizes ?? [], query.sizes) },
                SearchPredicate(kind: nil, isActive: active(query.genderPresentation)) { matchesGender($0, query.genderPresentation) },
                SearchPredicate(kind: .maxPrice, isActive: query.priceRange != nil) { matchesPrice($0, range: query.priceRange) },
                SearchPredicate(kind: .occasion, isActive: active(query.occasions)) { matchesAny(($0.occasionTags ?? []) + $0.tags, query.occasions) },
                SearchPredicate(kind: nil, isActive: query.onSaleOnly) { matchesSale($0, onSaleOnly: query.onSaleOnly, now: now) }
            ],
            sort: { sorted($0, by: query.sort) }
        )

        return result
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

    private static let relaxationPriority: [RelaxableFilter] = [
        .occasion,
        .style,
        .maxPrice,
        .color,
        .size,
        .brand,
        .category
    ]

    private struct SearchPredicate {
        let kind: RelaxableFilter?
        let isActive: Bool
        let matches: (AffiliateProduct) -> Bool
    }

    private static func relaxedFilter(
        products: [AffiliateProduct],
        predicates: [SearchPredicate],
        sort: ([AffiliateProduct]) -> [AffiliateProduct] = { $0 }
    ) -> RelaxedFilterResult {
        let exact = sort(products.filter { product in
            predicates.allSatisfy { !$0.isActive || $0.matches(product) }
        })
        guard exact.isEmpty else {
            return RelaxedFilterResult(exactResults: exact, relaxedResults: [], relaxedFilter: nil)
        }

        for kind in relaxationPriority {
            guard predicates.contains(where: { $0.kind == kind && $0.isActive }) else {
                continue
            }
            let relaxed = sort(products.filter { product in
                predicates.allSatisfy { predicate in
                    !predicate.isActive || predicate.kind == kind || predicate.matches(product)
                }
            })
            if !relaxed.isEmpty {
                return RelaxedFilterResult(exactResults: exact, relaxedResults: relaxed, relaxedFilter: kind)
            }
        }

        return RelaxedFilterResult(exactResults: exact, relaxedResults: [], relaxedFilter: nil)
    }

    private static func active(_ value: String?) -> Bool {
        !(value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    private static func active(_ values: [String]?) -> Bool {
        !(values?.map(normalize).filter { !$0.isEmpty }.isEmpty ?? true)
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
