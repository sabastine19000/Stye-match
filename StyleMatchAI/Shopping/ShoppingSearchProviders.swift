import Foundation

final class CatalogSearchProvider: ProductSearchProvider {
    let sourceName: String

    private let catalogProvider: ProductCatalogProvider
    private let cache = CatalogSearchIndexCache()

    init(sourceName: String = "Catalog", catalogProvider: ProductCatalogProvider = BundledCatalogProvider()) {
        self.sourceName = sourceName
        self.catalogProvider = catalogProvider
    }

    func search(_ query: ProductSearchQuery) async throws -> [AffiliateProduct] {
        let indexedProducts = try await loadIndex()
        let filtered = indexedProducts.filter { indexed in
            matchesText(indexed, query.text)
                && matchesAny(indexed.product.retailer.name, query.retailers)
                && matchesAny(indexed.product.brand, query.brands, requireValueWhenFiltering: true)
                && matchesAny(indexed.product.category, query.categories)
                && matchesAny(indexed.product.colors, query.colors)
                && matchesAny(indexed.product.sizes ?? [], query.sizes)
                && matchesGender(indexed.product, query.genderPresentation)
                && matchesPrice(indexed.product, query.priceRange)
                && matchesAny((indexed.product.occasionTags ?? []) + indexed.product.tags, query.occasions)
                && matchesSale(indexed.product, query.onSaleOnly)
        }.map(\.product)

        return sorted(filtered, by: query.sort)
    }

    private func loadIndex() async throws -> [IndexedCatalogProduct] {
        try await cache.index {
            let products = try await catalogProvider.products()
            return products.map(IndexedCatalogProduct.init(product:))
        }
    }

    private func matchesText(_ indexed: IndexedCatalogProduct, _ text: String?) -> Bool {
        let queryTokens = Self.tokens(from: text ?? "")
        guard !queryTokens.isEmpty else { return true }
        return queryTokens.allSatisfy { indexed.searchTokens.contains($0) }
    }

    private func matchesAny(_ value: String?, _ filters: [String]?, requireValueWhenFiltering: Bool = false) -> Bool {
        let normalizedFilters = Self.normalizedFilters(filters)
        guard !normalizedFilters.isEmpty else { return true }
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return !requireValueWhenFiltering
        }
        let valueTokens = Self.tokens(from: value)
        return normalizedFilters.contains { filter in
            valueTokens.contains(filter) || Self.normalize(value).contains(filter)
        }
    }

    private func matchesAny(_ values: [String], _ filters: [String]?) -> Bool {
        let normalizedFilters = Self.normalizedFilters(filters)
        guard !normalizedFilters.isEmpty else { return true }
        let tokens = Set(values.flatMap(Self.tokens(from:)))
        return normalizedFilters.contains { filter in
            tokens.contains(filter) || values.contains { Self.normalize($0).contains(filter) }
        }
    }

    private func matchesAny(_ value: ProductCategory, _ filters: [ProductCategory]?) -> Bool {
        guard let filters, !filters.isEmpty else { return true }
        return filters.contains(value)
    }

    private func matchesGender(_ product: AffiliateProduct, _ gender: String?) -> Bool {
        guard let gender, !gender.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return true }
        guard let presentation = product.genderPresentation else { return true }
        return Self.normalize(presentation).contains(Self.normalize(gender))
    }

    private func matchesPrice(_ product: AffiliateProduct, _ range: ClosedRange<Decimal>?) -> Bool {
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

    private func matchesSale(_ product: AffiliateProduct, _ onSaleOnly: Bool, now: Date = Date()) -> Bool {
        guard onSaleOnly else { return true }
        return product.salePrice != nil && (product.saleEndsAt ?? .distantFuture) > now
    }

    private func sorted(_ products: [AffiliateProduct], by sort: SearchSort) -> [AffiliateProduct] {
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

    private func sortablePrice(_ product: AffiliateProduct) -> Decimal? {
        guard product.retailer.name.caseInsensitiveCompare("Amazon") != .orderedSame else {
            return nil
        }
        return product.salePrice ?? product.price ?? product.priceRange?.lowerBound
    }

    private static func normalizedFilters(_ filters: [String]?) -> [String] {
        filters?
            .map(normalize)
            .filter { !$0.isEmpty } ?? []
    }

    fileprivate static func tokens(from text: String) -> Set<String> {
        Set(normalize(text)
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init))
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private let highPriceSentinel = Decimal(999_999_999)
    private let lowPriceSentinel = Decimal(-1)
}

private struct IndexedCatalogProduct {
    let product: AffiliateProduct
    let searchTokens: Set<String>

    init(product: AffiliateProduct) {
        self.product = product
        self.searchTokens = CatalogSearchProvider.tokens(from: (
            [product.name, product.brand ?? "", product.subcategory]
            + product.tags
        ).joined(separator: " "))
    }
}

private actor CatalogSearchIndexCache {
    private var cachedIndex: [IndexedCatalogProduct]?

    func index(load: () async throws -> [IndexedCatalogProduct]) async throws -> [IndexedCatalogProduct] {
        if let cachedIndex {
            return cachedIndex
        }

        let loaded = try await load()
        cachedIndex = loaded
        return loaded
    }
}

protocol RetailerSearchAdapter {
    var retailerName: String { get }
    func search(_ query: ProductSearchQuery) async throws -> [AffiliateProduct]
}

struct AggregatedSearchProvider: ProductSearchProvider {
    let sourceName: String
    let adapters: [RetailerSearchAdapter]
    let adapterTimeoutNanoseconds: UInt64

    init(
        sourceName: String = "Retailer Search",
        adapters: [RetailerSearchAdapter],
        adapterTimeoutNanoseconds: UInt64 = 2_000_000_000
    ) {
        self.sourceName = sourceName
        self.adapters = adapters
        self.adapterTimeoutNanoseconds = adapterTimeoutNanoseconds
    }

    func search(_ query: ProductSearchQuery) async throws -> [AffiliateProduct] {
        guard !adapters.isEmpty else {
            return []
        }

        return await withTaskGroup(of: [AffiliateProduct].self) { group in
            for adapter in adapters {
                group.addTask {
                    do {
                        return try await withTimeout(nanoseconds: adapterTimeoutNanoseconds) {
                            try await adapter.search(query)
                        }
                    } catch {
                        #if DEBUG
                        print("[StyleMatch Shopping Search] Skipping \(adapter.retailerName) adapter: \(error.localizedDescription)")
                        #endif
                        return []
                    }
                }
            }

            var merged: [AffiliateProduct] = []
            var seenKeys = Set<String>()
            for await products in group {
                for product in products {
                    let key = Self.dedupeKey(for: product)
                    if seenKeys.insert(key).inserted {
                        merged.append(product)
                    }
                }
            }
            return merged
        }
    }

    private static func dedupeKey(for product: AffiliateProduct) -> String {
        [
            product.brand ?? "",
            product.name,
            product.retailer.name
        ]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        .joined(separator: "|")
    }
}

protocol RetailerAPIRequestBuilding {
    var retailerName: String { get }
    func makeRequest(for query: ProductSearchQuery) throws -> URLRequest
    func decodeProducts(from data: Data) throws -> [AffiliateProduct]
}

struct RetailerAPIAdapter: RetailerSearchAdapter {
    let requestBuilder: RetailerAPIRequestBuilding
    var urlSession: URLSession = .shared

    var retailerName: String { requestBuilder.retailerName }

    func search(_ query: ProductSearchQuery) async throws -> [AffiliateProduct] {
        let request = try requestBuilder.makeRequest(for: query)
        #if DEBUG
        print("[StyleMatch Shopping Adapter Request] \(request.url?.absoluteString ?? "")")
        #endif
        let (data, _) = try await urlSession.data(for: request)
        return try requestBuilder.decodeProducts(from: data)
    }
}

struct FixtureRetailerSearchAdapter: RetailerSearchAdapter {
    let retailerName: String
    let products: [AffiliateProduct]

    func search(_ query: ProductSearchQuery) async throws -> [AffiliateProduct] {
        ShoppingSearchEngine.filter(products: products, query: query)
    }
}

struct BestBuyAdapter: RetailerSearchAdapter {
    let retailerName = "Best Buy"
    let apiKey: String
    var urlSession: URLSession = .shared
    var baseURL: URL? = URL(string: "https://api.bestbuy.com/v1/products")

    func search(_ query: ProductSearchQuery) async throws -> [AffiliateProduct] {
        let request = try makeRequest(for: query)
        #if DEBUG
        print("[StyleMatch Shopping Adapter Request] \(request.url?.absoluteString ?? "")")
        #endif
        let (data, _) = try await urlSession.data(for: request)
        return try decodeProducts(from: data)
    }

    func makeRequest(for query: ProductSearchQuery) throws -> URLRequest {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RetailerAdapterConfigurationError.missingBestBuyAPIKey
        }

        guard let baseURL else {
            throw RetailerAdapterConfigurationError.invalidRequestURL
        }
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "apiKey", value: apiKey),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "show", value: "sku,name,manufacturer,salePrice,regularPrice,image,url,type,color")
        ] + query.safeRetailerQueryItems()
        guard let url = components?.url else {
            throw RetailerAdapterConfigurationError.invalidRequestURL
        }
        return URLRequest(url: url)
    }

    func decodeProducts(from data: Data) throws -> [AffiliateProduct] {
        let response = try JSONDecoder.catalog.decode(BestBuyProductResponse.self, from: data)
        return response.products.compactMap { product in
            guard let url = product.url else {
                return nil
            }

            return AffiliateProduct(
                id: "bestbuy-\(product.sku)",
                name: product.name,
                category: Self.category(for: product.type),
                subcategory: product.type ?? "electronics",
                colors: product.color.map { [$0] } ?? [],
                sizes: nil,
                priceRange: nil,
                occasionTags: nil,
                brand: product.manufacturer,
                imageURL: product.image,
                retailer: Retailer(name: "Best Buy", trackingID: "PENDING-APPROVAL", trackingParamName: "irclickid", disclosureName: "Best Buy"),
                affiliateURL: url,
                price: product.regularPrice,
                salePrice: product.salePrice != product.regularPrice ? product.salePrice : nil,
                saleEndsAt: nil,
                availableColors: nil,
                customerRating: nil,
                reviewCount: nil,
                estimatedShippingText: nil,
                tags: [product.type].compactMap { $0 },
                genderPresentation: nil
            )
        }
    }

    private static func category(for type: String?) -> ProductCategory {
        let normalized = type?.lowercased() ?? ""
        if normalized.contains("watch") || normalized.contains("headphone") || normalized.contains("electronic") {
            return .electronics
        }
        return .styleTools
    }
}

struct AmazonPAAPIAdapter: RetailerSearchAdapter {
    private let proxy: ProxyRetailerSearchAdapter
    var retailerName: String { "Amazon" }

    init(proxyBaseURL: URL, urlSession: URLSession = .shared) {
        proxy = ProxyRetailerSearchAdapter(retailerName: "Amazon", endpointPath: "amazon/search", proxyBaseURL: proxyBaseURL, urlSession: urlSession)
    }

    func search(_ query: ProductSearchQuery) async throws -> [AffiliateProduct] {
        try await proxy.search(query, decode: decodeProducts(from:))
    }

    func makeRequest(for query: ProductSearchQuery) throws -> URLRequest {
        try proxy.makeRequest(for: query)
    }

    func decodeProducts(from data: Data) throws -> [AffiliateProduct] {
        try AmazonPAAPIResponseMapper.decode(data)
    }
}

struct ImpactAdapter: RetailerSearchAdapter {
    private let proxy: ProxyRetailerSearchAdapter
    var retailerName: String { "Impact" }

    init(proxyBaseURL: URL, urlSession: URLSession = .shared) {
        proxy = ProxyRetailerSearchAdapter(retailerName: "Impact", endpointPath: "impact/search", proxyBaseURL: proxyBaseURL, urlSession: urlSession)
    }

    func search(_ query: ProductSearchQuery) async throws -> [AffiliateProduct] {
        try await proxy.search(query, decode: decodeProducts(from:))
    }

    func makeRequest(for query: ProductSearchQuery) throws -> URLRequest {
        try proxy.makeRequest(for: query)
    }

    func decodeProducts(from data: Data) throws -> [AffiliateProduct] {
        try ImpactResponseMapper.decode(data)
    }
}

struct CJAdapter: RetailerSearchAdapter {
    private let proxy: ProxyRetailerSearchAdapter
    var retailerName: String { "CJ" }

    init(proxyBaseURL: URL, urlSession: URLSession = .shared) {
        proxy = ProxyRetailerSearchAdapter(retailerName: "CJ", endpointPath: "cj/search", proxyBaseURL: proxyBaseURL, urlSession: urlSession)
    }

    func search(_ query: ProductSearchQuery) async throws -> [AffiliateProduct] {
        try await proxy.search(query, decode: decodeProducts(from:))
    }

    func makeRequest(for query: ProductSearchQuery) throws -> URLRequest {
        try proxy.makeRequest(for: query)
    }

    func decodeProducts(from data: Data) throws -> [AffiliateProduct] {
        try CJResponseMapper.decode(data)
    }
}

struct RakutenAdapter: RetailerSearchAdapter {
    private let proxy: ProxyRetailerSearchAdapter
    var retailerName: String { "Rakuten" }

    init(proxyBaseURL: URL, urlSession: URLSession = .shared) {
        proxy = ProxyRetailerSearchAdapter(retailerName: "Rakuten", endpointPath: "rakuten/search", proxyBaseURL: proxyBaseURL, urlSession: urlSession)
    }

    func search(_ query: ProductSearchQuery) async throws -> [AffiliateProduct] {
        try await proxy.search(query, decode: decodeProducts(from:))
    }

    func makeRequest(for query: ProductSearchQuery) throws -> URLRequest {
        try proxy.makeRequest(for: query)
    }

    func decodeProducts(from data: Data) throws -> [AffiliateProduct] {
        try RakutenResponseMapper.decode(data)
    }
}

struct SovrnAdapter: RetailerSearchAdapter {
    private let proxy: ProxyRetailerSearchAdapter
    var retailerName: String { "Sovrn" }

    init(proxyBaseURL: URL, urlSession: URLSession = .shared) {
        proxy = ProxyRetailerSearchAdapter(retailerName: "Sovrn", endpointPath: "sovrn/search", proxyBaseURL: proxyBaseURL, urlSession: urlSession)
    }

    func search(_ query: ProductSearchQuery) async throws -> [AffiliateProduct] {
        try await proxy.search(query, decode: decodeProducts(from:))
    }

    func makeRequest(for query: ProductSearchQuery) throws -> URLRequest {
        try proxy.makeRequest(for: query)
    }

    func decodeProducts(from data: Data) throws -> [AffiliateProduct] {
        try SovrnResponseMapper.decode(data)
    }
}

private struct ProxyRetailerSearchAdapter: RetailerSearchAdapter {
    let retailerName: String
    let endpointPath: String
    let proxyBaseURL: URL
    var urlSession: URLSession = .shared

    func search(_ query: ProductSearchQuery) async throws -> [AffiliateProduct] {
        try await search(query) { data in
            try BundledCatalogProvider.decodeProducts(catalogData: data)
        }
    }

    func search(_ query: ProductSearchQuery, decode: (Data) throws -> [AffiliateProduct]) async throws -> [AffiliateProduct] {
        let request = try makeRequest(for: query)
        #if DEBUG
        print("[StyleMatch Shopping Adapter Request] \(request.url?.absoluteString ?? "")")
        #endif
        let (data, _) = try await urlSession.data(for: request)
        return try decode(data)
    }

    func makeRequest(for query: ProductSearchQuery) throws -> URLRequest {
        var components = URLComponents(url: proxyBaseURL.appendingPathComponent(endpointPath), resolvingAgainstBaseURL: false)
        components?.queryItems = query.safeRetailerQueryItems()
        guard let url = components?.url else {
            throw RetailerAdapterConfigurationError.invalidRequestURL
        }
        return URLRequest(url: url)
    }
}

enum RetailerAdapterConfigurationError: Error {
    case missingBestBuyAPIKey
    case invalidRequestURL
}

private struct BestBuyProductResponse: Codable {
    let products: [BestBuyProduct]
}

private struct BestBuyProduct: Codable {
    let sku: Int
    let name: String
    let manufacturer: String?
    let salePrice: Decimal?
    let regularPrice: Decimal?
    let image: URL?
    let url: URL?
    let type: String?
    let color: String?
}

private enum RetailerProductMapping {
    static func product(
        id: String,
        name: String,
        brand: String?,
        retailerName: String,
        categoryText: String?,
        url: URL?,
        imageURL: URL?,
        price: Decimal?,
        salePrice: Decimal?,
        color: String? = nil
    ) -> AffiliateProduct? {
        guard let url else { return nil }
        let category = productCategory(from: categoryText)
        return AffiliateProduct(
            id: id,
            name: name,
            category: category,
            subcategory: categoryText ?? category.displayName.lowercased(),
            colors: color.map { [$0] } ?? [],
            sizes: nil,
            priceRange: nil,
            occasionTags: nil,
            brand: brand,
            imageURL: imageURL,
            retailer: Retailer(name: retailerName, trackingID: "PENDING-APPROVAL", trackingParamName: "affiliate", disclosureName: retailerName),
            affiliateURL: url,
            price: price,
            salePrice: salePrice,
            saleEndsAt: nil,
            availableColors: nil,
            customerRating: nil,
            reviewCount: nil,
            estimatedShippingText: nil,
            tags: [categoryText].compactMap { $0 },
            genderPresentation: nil
        )
    }

    private static func productCategory(from text: String?) -> ProductCategory {
        let value = text?.lowercased() ?? ""
        if value.contains("shoe") || value.contains("sneaker") || value.contains("boot") { return .shoes }
        if value.contains("watch") || value.contains("electronic") || value.contains("headphone") { return .electronics }
        if value.contains("belt") || value.contains("bag") || value.contains("sunglass") || value.contains("jewelry") { return .accessories }
        if value.contains("beauty") || value.contains("makeup") || value.contains("groom") || value.contains("steamer") { return .styleTools }
        return .clothing
    }
}

private enum AmazonPAAPIResponseMapper {
    static func decode(_ data: Data) throws -> [AffiliateProduct] {
        let response = try JSONDecoder.catalog.decode(Response.self, from: data)
        return response.ItemsResult.Items.compactMap { item in
            RetailerProductMapping.product(
                id: "amazon-\(item.ASIN)",
                name: item.ItemInfo.Title.DisplayValue,
                brand: item.ItemInfo.ByLineInfo?.Brand?.DisplayValue,
                retailerName: "Amazon",
                categoryText: item.BrowseNodeInfo?.BrowseNodes?.first?.DisplayName,
                url: item.DetailPageURL,
                imageURL: item.Images.Primary.Medium.URL,
                price: item.Offers?.Listings?.first?.SavingBasis?.Amount,
                salePrice: item.Offers?.Listings?.first?.Price?.Amount
            )
        }
    }

    private struct Response: Codable { let ItemsResult: ItemsResult }
    private struct ItemsResult: Codable { let Items: [Item] }
    private struct Item: Codable {
        let ASIN: String
        let DetailPageURL: URL?
        let ItemInfo: ItemInfo
        let Images: Images
        let Offers: Offers?
        let BrowseNodeInfo: BrowseNodeInfo?
    }
    private struct ItemInfo: Codable { let Title: DisplayValue; let ByLineInfo: ByLineInfo? }
    private struct ByLineInfo: Codable { let Brand: DisplayValue? }
    private struct DisplayValue: Codable { let DisplayValue: String }
    private struct Images: Codable { let Primary: PrimaryImage }
    private struct PrimaryImage: Codable { let Medium: ImageValue }
    private struct ImageValue: Codable { let URL: URL? }
    private struct Offers: Codable { let Listings: [Listing]? }
    private struct Listing: Codable { let Price: Money?; let SavingBasis: Money? }
    private struct Money: Codable { let Amount: Decimal? }
    private struct BrowseNodeInfo: Codable { let BrowseNodes: [BrowseNode]? }
    private struct BrowseNode: Codable { let DisplayName: String? }
}

private enum ImpactResponseMapper {
    static func decode(_ data: Data) throws -> [AffiliateProduct] {
        let response = try JSONDecoder.catalog.decode(Response.self, from: data)
        return response.Items.compactMap { item in
            RetailerProductMapping.product(
                id: "impact-\(item.CatalogItemId)",
                name: item.Name,
                brand: item.Brand,
                retailerName: item.RetailerName,
                categoryText: item.Category,
                url: item.Url,
                imageURL: item.ImageUrl,
                price: item.OriginalPrice,
                salePrice: item.CurrentPrice
            )
        }
    }

    private struct Response: Codable { let Items: [Item] }
    private struct Item: Codable {
        let CatalogItemId: String
        let Name: String
        let Brand: String?
        let RetailerName: String
        let Category: String?
        let Url: URL?
        let ImageUrl: URL?
        let CurrentPrice: Decimal?
        let OriginalPrice: Decimal?
    }
}

private enum CJResponseMapper {
    static func decode(_ data: Data) throws -> [AffiliateProduct] {
        let response = try JSONDecoder.catalog.decode(Response.self, from: data)
        return response.products.compactMap { item in
            RetailerProductMapping.product(
                id: "cj-\(item.id)",
                name: item.name,
                brand: item.brand,
                retailerName: item.advertiserName,
                categoryText: item.catalogName,
                url: item.buyUrl,
                imageURL: item.imageLink,
                price: item.price,
                salePrice: item.salePrice
            )
        }
    }

    private struct Response: Codable { let products: [Item] }
    private struct Item: Codable {
        let id: String
        let name: String
        let advertiserName: String
        let brand: String?
        let buyUrl: URL?
        let imageLink: URL?
        let price: Decimal?
        let salePrice: Decimal?
        let catalogName: String?
    }
}

private enum RakutenResponseMapper {
    static func decode(_ data: Data) throws -> [AffiliateProduct] {
        let response = try JSONDecoder.catalog.decode(Response.self, from: data)
        return response.item.compactMap { item in
            RetailerProductMapping.product(
                id: "rakuten-\(item.sku)",
                name: item.productname,
                brand: item.brand,
                retailerName: item.advertisername,
                categoryText: item.category,
                url: item.linkurl,
                imageURL: item.imageurl,
                price: item.price,
                salePrice: item.saleprice
            )
        }
    }

    private struct Response: Codable { let item: [Item] }
    private struct Item: Codable {
        let sku: String
        let productname: String
        let advertisername: String
        let brand: String?
        let linkurl: URL?
        let imageurl: URL?
        let price: Decimal?
        let saleprice: Decimal?
        let category: String?
    }
}

private enum SovrnResponseMapper {
    static func decode(_ data: Data) throws -> [AffiliateProduct] {
        let response = try JSONDecoder.catalog.decode(Response.self, from: data)
        return response.results.compactMap { item in
            RetailerProductMapping.product(
                id: "sovrn-\(item.id)",
                name: item.name,
                brand: item.brand,
                retailerName: item.merchant,
                categoryText: item.category,
                url: item.url,
                imageURL: item.image,
                price: item.price,
                salePrice: item.sale_price
            )
        }
    }

    private struct Response: Codable { let results: [Item] }
    private struct Item: Codable {
        let id: String
        let name: String
        let merchant: String
        let brand: String?
        let url: URL?
        let image: URL?
        let price: Decimal?
        let sale_price: Decimal?
        let category: String?
    }
}

extension ProductSearchQuery {
    fileprivate func safeRetailerQueryItems() -> [URLQueryItem] {
        var items: [URLQueryItem] = []
        append("q", text, to: &items)
        append("retailer", retailers?.joined(separator: ","), to: &items)
        append("brand", brands?.joined(separator: ","), to: &items)
        append("category", categories?.map(\.rawValue).joined(separator: ","), to: &items)
        append("color", colors?.joined(separator: ","), to: &items)
        append("size", sizes?.joined(separator: ","), to: &items)
        append("gender", genderPresentation, to: &items)
        append("minPrice", priceRange.map { String(describing: $0.lowerBound) }, to: &items)
        append("maxPrice", priceRange.map { String(describing: $0.upperBound) }, to: &items)
        append("occasion", occasions?.joined(separator: ","), to: &items)
        if onSaleOnly {
            items.append(URLQueryItem(name: "onSaleOnly", value: "true"))
        }
        items.append(URLQueryItem(name: "sort", value: sort.rawValue))
        return items
    }

    private func append(_ name: String, _ value: String?, to items: inout [URLQueryItem]) {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return
        }
        items.append(URLQueryItem(name: name, value: value))
    }
}

private func withTimeout<T>(
    nanoseconds: UInt64,
    operation: @escaping () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(nanoseconds: nanoseconds)
            throw SearchTimeoutError()
        }

        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

private struct SearchTimeoutError: Error {}
