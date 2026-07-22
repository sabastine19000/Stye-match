import Foundation

protocol ProductCatalogProvider {
    func products() async throws -> [AffiliateProduct]
}

protocol CatalogDisclosureProviding {
    func disclosure() async -> String?
}

enum ShoppingCatalogDisclosure {
    static let fallback = "As an Amazon Associate I earn from qualifying purchases. StyleMatch Pro may earn a commission at no extra cost to you."
}

protocol ProductSearchProvider {
    var sourceName: String { get }
    func search(_ query: ProductSearchQuery) async throws -> [AffiliateProduct]
}

protocol StoreDirectoryProvider {
    func stores() async throws -> [SupportedStore]
}

protocol ShoppingIntegrationConfigProvider {
    func config() throws -> ShoppingIntegrationConfig
}

protocol LiveRetailerSearchProvider {
    func search(criteria: ShoppingSearchCriteria) async throws -> [AffiliateProduct]
}

enum ProductCatalogRuntime {
    static func activeProvider() -> ProductCatalogProvider {
        let config = (try? BundledShoppingIntegrationConfigProvider().config()) ?? .empty
        if FeatureFlags.remoteCatalogEnabled, let remoteURL = config.catalogBaseURL {
            return RemoteCatalogProvider(
                baseURL: remoteURL,
                cacheDirectory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0],
                fallbackProvider: BundledCatalogProvider()
            )
        }
        return BundledCatalogProvider()
    }
}

actor SharedProductCatalogLoader {
    static let shared = SharedProductCatalogLoader(provider: ProductCatalogRuntime.activeProvider())

    private let provider: ProductCatalogProvider
    private let timeToLive: TimeInterval
    private let now: () -> Date
    private var cachedProducts: [AffiliateProduct]?
    private var cachedAt: Date?
    private var inFlight: Task<[AffiliateProduct], Error>?

    init(
        provider: ProductCatalogProvider,
        timeToLive: TimeInterval = 300,
        now: @escaping () -> Date = Date.init
    ) {
        self.provider = provider
        self.timeToLive = timeToLive
        self.now = now
    }

    func products() async throws -> [AffiliateProduct] {
        #if DEBUG
        func logDuration(_ message: String) { _ = message }
        #endif
        let currentDate = now()
        if let cachedProducts, let cachedAt {
            if currentDate.timeIntervalSince(cachedAt) < timeToLive {
                #if DEBUG
                logDuration("memory-cache hit products=\(cachedProducts.count)")
                #endif
                return cachedProducts
            }
            startBackgroundRefreshIfNeeded()
            #if DEBUG
            logDuration("stale memory-cache returned products=\(cachedProducts.count)")
            #endif
            return cachedProducts
        }

        if let inFlight {
            let products = try await inFlight.value
            #if DEBUG
            logDuration("joined in-flight products=\(products.count)")
            #endif
            return products
        }

        let task = Task { try await provider.products() }
        inFlight = task
        do {
            let products = try await task.value
            cachedProducts = products
            cachedAt = currentDate
            inFlight = nil
            #if DEBUG
            logDuration("provider fetch products=\(products.count)")
            #endif
            return products
        } catch {
            inFlight = nil
            #if DEBUG
            logDuration("provider fetch failed")
            #endif
            throw error
        }
    }

    func disclosure() async -> String {
        guard let disclosureProvider = provider as? CatalogDisclosureProviding else {
            return ShoppingCatalogDisclosure.fallback
        }
        let disclosure = await disclosureProvider.disclosure()?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let disclosure, !disclosure.isEmpty {
            return disclosure
        }
        return ShoppingCatalogDisclosure.fallback
    }

    private func startBackgroundRefreshIfNeeded() {
        guard inFlight == nil else { return }
        let task = Task { try await provider.products() }
        inFlight = task
        Task {
            let result = await task.result
            finishBackgroundRefresh(result)
        }
    }

    private func finishBackgroundRefresh(_ result: Result<[AffiliateProduct], Error>) {
        inFlight = nil
        guard case .success(let products) = result else { return }
        cachedProducts = products
        cachedAt = now()
    }
}

struct SharedCatalogProvider: ProductCatalogProvider {
    let loader: SharedProductCatalogLoader

    init(loader: SharedProductCatalogLoader = .shared) {
        self.loader = loader
    }

    func products() async throws -> [AffiliateProduct] {
        try await loader.products()
    }
}

enum ProductCatalogProviderError: Error {
    case missingCatalog
}

enum StoreDirectoryProviderError: Error {
    case missingStoreDirectory
}

enum ShoppingIntegrationConfigError: Error {
    case missingConfig
    case missingLiveSearchProxy
}

struct BundledShoppingIntegrationConfigProvider: ShoppingIntegrationConfigProvider {
    let bundle: Bundle
    let resourceName: String

    init(bundle: Bundle = .main, resourceName: String = "ShoppingRuntimeConfig") {
        self.bundle = bundle
        self.resourceName = resourceName
    }

    func config() throws -> ShoppingIntegrationConfig {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json") else {
            return .empty
        }
        return try JSONDecoder.catalog.decode(ShoppingIntegrationConfig.self, from: Data(contentsOf: url))
    }
}

struct BundledStoreDirectoryProvider: StoreDirectoryProvider {
    let bundle: Bundle
    let resourceName: String

    init(bundle: Bundle = .main, resourceName: String = "SupportedStores") {
        self.bundle = bundle
        self.resourceName = resourceName
    }

    func stores() async throws -> [SupportedStore] {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json") else {
            throw StoreDirectoryProviderError.missingStoreDirectory
        }
        return try Self.decodeStores(Data(contentsOf: url))
    }

    static func decodeStores(_ data: Data) throws -> [SupportedStore] {
        let rawObjects = try JSONSerialization.jsonObject(with: data) as? [Any] ?? []
        return rawObjects.compactMap { object in
            guard JSONSerialization.isValidJSONObject(object),
                  let data = try? JSONSerialization.data(withJSONObject: object) else {
                return nil
            }

            do {
                return try JSONDecoder.catalog.decode(SupportedStore.self, from: data)
            } catch {
                return nil
            }
        }
    }
}

struct BundledCatalogProvider: ProductCatalogProvider {
    let bundle: Bundle
    let catalogResourceName: String
    let retailerConfigResourceName: String

    init(
        bundle: Bundle = .main,
        catalogResourceName: String = "ProductCatalog",
        retailerConfigResourceName: String = "RetailerConfig"
    ) {
        self.bundle = bundle
        self.catalogResourceName = catalogResourceName
        self.retailerConfigResourceName = retailerConfigResourceName
    }

    func products() async throws -> [AffiliateProduct] {
        guard let catalogURL = bundle.url(forResource: catalogResourceName, withExtension: "json") else {
            throw ProductCatalogProviderError.missingCatalog
        }
        let configURL = bundle.url(forResource: retailerConfigResourceName, withExtension: "json")
        let decodedProducts = try Self.decodeProducts(
            catalogData: Data(contentsOf: catalogURL),
            retailerConfigData: configURL.flatMap { try? Data(contentsOf: $0) }
        )
        let customerSafeProducts = CatalogProductSafetyValidator.validated(decodedProducts)

        guard !customerSafeProducts.isEmpty else {
            throw ProductCatalogProviderError.missingCatalog
        }

        return customerSafeProducts
    }

    static func decodeProducts(catalogData: Data, retailerConfigData: Data? = nil) throws -> [AffiliateProduct] {
        let config = retailerConfigData.flatMap { try? JSONDecoder.catalog.decode(RetailerConfig.self, from: $0) }
        let rawObjects = try JSONSerialization.jsonObject(with: catalogData) as? [Any] ?? []
        return rawObjects.compactMap { object in
            guard JSONSerialization.isValidJSONObject(object),
                  let data = try? JSONSerialization.data(withJSONObject: object) else {
                return nil
            }

            do {
                let decoded = try JSONDecoder.catalog.decode(AffiliateProduct.self, from: data)
                if let configuredRetailer = config?.retailer(named: decoded.retailer.name) {
                    return AffiliateProduct(
                        id: decoded.id,
                        name: decoded.name,
                        category: decoded.category,
                        subcategory: decoded.subcategory,
                        colors: decoded.colors,
                        sizes: decoded.sizes,
                        priceRange: decoded.priceRange,
                        occasionTags: decoded.occasionTags,
                        brand: decoded.brand,
                        imageURL: decoded.imageURL,
                        retailer: configuredRetailer,
                        affiliateURL: decoded.affiliateURL,
                        price: decoded.price,
                        salePrice: decoded.salePrice,
                        saleEndsAt: decoded.saleEndsAt,
                        currencyCode: decoded.currencyCode,
                        availableCountries: decoded.availableCountries,
                        availability: decoded.availability,
                        availableColors: decoded.availableColors,
                        customerRating: decoded.customerRating,
                        reviewCount: decoded.reviewCount,
                        estimatedShippingText: decoded.estimatedShippingText,
                        tags: decoded.tags,
                        genderPresentation: decoded.genderPresentation
                    )
                }
                return decoded
            } catch {
                return nil
            }
        }
    }
}

typealias CatalogProductSearchProvider = CatalogSearchProvider

struct RemoteCatalogProvider: ProductCatalogProvider, CatalogDisclosureProviding {
    /// Catalog requests should complete well within this 10-second budget under
    /// normal conditions while still tolerating cellular connection setup.
    static let defaultRequestTimeout: TimeInterval = 10

    let baseURL: URL
    let cacheDirectory: URL
    let fallbackProvider: ProductCatalogProvider
    var urlSession: URLSession = .shared
    var requestTimeout: TimeInterval = Self.defaultRequestTimeout

    func products() async throws -> [AffiliateProduct] {
        try Task.checkCancellation()
        do {
            let data = try await fetchRemoteData()
            try Task.checkCancellation()
            let decoded = try Self.decodeRemoteProducts(data, baseURL: baseURL)
            guard !decoded.isEmpty else {
                debugLog("remote decode produced zero safe products")
                throw ProductCatalogProviderError.missingCatalog
            }
            do {
                try cache(data)
            } catch {
                debugLog(error, prefix: "cache write failed; keeping decoded remote catalog")
            }
            debugLog("selected source=remote products=\(decoded.count)")
            return decoded
        } catch {
            if Self.isCancellation(error) { throw error }
            debugLog(error, prefix: "remote source failed")
        }

        try Task.checkCancellation()
        do {
            let cached = try cachedProducts()
            if !cached.isEmpty {
                debugLog("selected source=cache products=\(cached.count)")
                return cached
            }
            debugLog("cache decoded zero safe products")
        } catch {
            if Self.isCancellation(error) { throw error }
            debugLog(error, prefix: "cache source failed")
        }

        try Task.checkCancellation()
        do {
            let bundled = CatalogProductSafetyValidator.validated(try await fallbackProvider.products())
            try Task.checkCancellation()
            guard !bundled.isEmpty else {
                debugLog("bundled source produced zero safe products")
                throw ProductCatalogProviderError.missingCatalog
            }
            debugLog("selected source=bundled products=\(bundled.count)")
            return bundled
        } catch {
            if Self.isCancellation(error) { throw error }
            debugLog(error, prefix: "bundled source failed")
        }

        debugLog("all catalog sources failed")
        throw ProductCatalogProviderError.missingCatalog
    }

    func disclosure() async -> String? {
        if let data = try? Data(contentsOf: cacheFileURL()),
           let disclosure = try? Self.decodeRemoteDisclosure(data) {
            return disclosure
        }
        // products() has already attempted the live source. Avoid extending an
        // offline fallback with a second network timeout just for disclosure.
        return nil
    }

    static func decodeRemoteProducts(_ data: Data, baseURL: URL, regionCode: String = Self.currentRegionCode) throws -> [AffiliateProduct] {
        let response = try JSONDecoder.catalog.decode(RemoteProductsResponse.self, from: data)
        let decoded: [AffiliateProduct] = response.products.compactMap { remote -> AffiliateProduct? in
            guard let buyURL = URL(string: remote.buyURL, relativeTo: baseURL)?.absoluteURL else {
                return nil
            }
            let imageURL = ProductImageURLValidator.validated(remote.imageURL)
            return AffiliateProduct(
                id: remote.id,
                name: remote.name,
                category: remote.productCategory,
                subcategory: remote.category,
                colors: remote.tags.filter(Self.isLikelyColor),
                sizes: nil,
                priceRange: nil,
                occasionTags: remote.tags,
                brand: remote.brand,
                imageURL: imageURL,
                retailer: Retailer(
                    name: remote.storeName,
                    trackingID: AffiliateLinkBuilder.pendingApprovalTrackingID,
                    trackingParamName: "stylematch",
                    disclosureName: remote.storeName
                ),
                affiliateURL: buyURL,
                price: remote.priceCents.map(Self.decimalFromCents),
                salePrice: remote.salePriceCents.map(Self.decimalFromCents),
                saleEndsAt: remote.saleEndsAt,
                currencyCode: remote.currency,
                availableCountries: remote.availableCountries,
                availability: remote.availability,
                availableColors: nil,
                customerRating: nil,
                reviewCount: nil,
                estimatedShippingText: nil,
                tags: remote.tags,
                genderPresentation: nil
            )
        }
        return CatalogProductSafetyValidator.validated(decoded, regionCode: regionCode)
    }

    static func decodeRemoteDisclosure(_ data: Data) throws -> String? {
        try JSONDecoder.catalog.decode(RemoteProductsResponse.self, from: data).disclosure
    }

    private func fetchRemoteData() async throws -> Data {
        var components = URLComponents(url: baseURL.appendingPathComponent("v1/products"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "limit", value: "100"),
            URLQueryItem(name: "country", value: Self.currentRegionCode)
        ]
        guard let url = components?.url else {
            throw ProductCatalogProviderError.missingCatalog
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let startedAt = Date()
        do {
            let (data, response) = try await urlSession.data(for: request)
            let duration = Date().timeIntervalSince(startedAt)
            guard let http = response as? HTTPURLResponse else {
                debugLog("request duration=\(Self.durationText(duration)) status=unavailable")
                throw ProductCatalogProviderError.missingCatalog
            }
            debugLog("request duration=\(Self.durationText(duration)) status=\(http.statusCode)")
            guard (200..<300).contains(http.statusCode) else {
                throw CatalogHTTPError(statusCode: http.statusCode)
            }
            return data
        } catch {
            let duration = Date().timeIntervalSince(startedAt)
            debugLog(error, prefix: "request duration=\(Self.durationText(duration)) status=unavailable")
            throw error
        }
    }

    private func cachedProducts() throws -> [AffiliateProduct] {
        let data = try Data(contentsOf: cacheFileURL())
        return try Self.decodeRemoteProducts(data, baseURL: baseURL)
    }

    private func cache(_ data: Data) throws {
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try data.write(to: cacheFileURL(), options: .atomic)
    }

    private func cacheFileURL() -> URL {
        cacheDirectory.appendingPathComponent("ProductCatalog.worker.remote.json")
    }

    private static func decimalFromCents(_ cents: Int) -> Decimal {
        Decimal(cents) / Decimal(100)
    }

    private static func isLikelyColor(_ value: String) -> Bool {
        let colors = Set(["black", "white", "gray", "grey", "navy", "blue", "brown", "tan", "beige", "green", "red", "pink", "purple", "yellow", "orange", "cream", "charcoal"])
        return colors.contains(value.lowercased())
    }

    private static var currentRegionCode: String {
        #if os(iOS) || os(macOS) || os(tvOS) || os(watchOS)
        if #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *) {
            return Locale.current.region?.identifier.uppercased() ?? "US"
        } else {
            return Locale.current.regionCode?.uppercased() ?? "US"
        }
        #else
        return "US"
        #endif
    }

    private static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }

    private static func durationText(_ duration: TimeInterval) -> String {
        String(format: "%.3fs", duration)
    }

    private func debugLog(_ message: @autoclosure () -> String) {
        _ = message
    }

    private func debugLog(_ error: Error, prefix: String) {
        _ = error
        _ = prefix
    }

}

private struct CatalogHTTPError: Error {
    let statusCode: Int
}

enum CatalogProductSafetyValidator {
    static func validated(_ products: [AffiliateProduct], regionCode: String = currentRegionCode) -> [AffiliateProduct] {
        products.filter { product in
            guard countryList(product.availableCountries, contains: regionCode),
                  availabilityAllowsPurchase(product.availability) else {
                return false
            }
            let outboundURL = AffiliateLinkBuilder.outboundURL(for: product)
            guard let components = URLComponents(url: outboundURL, resolvingAgainstBaseURL: false),
                  let scheme = components.scheme?.lowercased(),
                  scheme == "https" || scheme == "http",
                  let host = components.host,
                  !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return false
            }
            return !AffiliateLinkBuilder.isPlaceholderURL(outboundURL)
        }
    }

    private static func countryList(_ countries: [String]?, contains regionCode: String) -> Bool {
        guard let countries, !countries.isEmpty else { return true }
        return countries.contains("*") || countries.map { $0.uppercased() }.contains(regionCode.uppercased())
    }

    private static func availabilityAllowsPurchase(_ availability: String?) -> Bool {
        guard let availability = availability?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !availability.isEmpty else {
            return true
        }
        return ["in_stock", "available", "limited_stock", "preorder", "pre_order"].contains(availability)
    }

    private static var currentRegionCode: String {
        Locale.current.region?.identifier.uppercased() ?? "US"
    }
}

private struct RemoteProductsResponse: Decodable {
    let products: [RemoteProduct]
    let disclosure: String?
}

private struct RemoteProduct: Decodable {
    let id: String
    let storeID: String
    let storeName: String
    let name: String
    let imageURL: String?
    let category: String
    let brand: String?
    let priceCents: Int?
    let salePriceCents: Int?
    let saleEndsAt: Date?
    let currency: String?
    let countryCode: String?
    let availableCountries: [String]?
    let availability: String
    let tags: [String]
    let buyURL: String

    enum CodingKeys: String, CodingKey {
        case id
        case storeID = "store_id"
        case storeName = "store_name"
        case name
        case imageURL = "image_url"
        case category
        case brand
        case priceCents = "price_cents"
        case salePriceCents = "sale_price_cents"
        case saleEndsAt = "sale_ends_at"
        case currency
        case countryCode = "country_code"
        case availableCountries = "available_countries"
        case availability
        case tags
        case buyURL = "buy_url"
    }

    var productCategory: ProductCategory {
        switch category {
        case "shoes": return .shoes
        case "accessories": return .accessories
        case "electronics": return .electronics
        case "styleTools", "style_tools", "style-tools": return .styleTools
        default: return .clothing
        }
    }
}

struct ProxyLiveRetailerSearchProvider: LiveRetailerSearchProvider {
    let proxyBaseURL: URL
    var urlSession: URLSession = .shared

    func search(criteria: ShoppingSearchCriteria) async throws -> [AffiliateProduct] {
        var components = URLComponents(url: proxyBaseURL.appendingPathComponent("search"), resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems(for: criteria)
        guard let url = components?.url else {
            throw ShoppingIntegrationConfigError.missingLiveSearchProxy
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, _) = try await urlSession.data(for: request)
        return try BundledCatalogProvider.decodeProducts(catalogData: data)
    }

    private func queryItems(for criteria: ShoppingSearchCriteria) -> [URLQueryItem] {
        [
            item("q", criteria.query),
            item("store", criteria.storeName),
            item("brand", criteria.brand),
            item("category", criteria.category?.rawValue),
            item("color", criteria.color),
            item("size", criteria.size),
            item("style", criteria.style),
            item("gender", criteria.genderPresentation),
            item("minPrice", criteria.minimumPrice.map(String.init(describing:))),
            item("maxPrice", criteria.maximumPrice.map(String.init(describing:))),
            item("occasion", criteria.occasion)
        ].compactMap { $0 }
    }

    private func item(_ name: String, _ value: String?) -> URLQueryItem? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return URLQueryItem(name: name, value: value)
    }
}

enum ShoppingDataSourceResolver {
    static func liveProvider(
        liveSearchEnabled: Bool = FeatureFlags.liveSearchEnabled,
        configProvider: ShoppingIntegrationConfigProvider = BundledShoppingIntegrationConfigProvider()
    ) throws -> LiveRetailerSearchProvider? {
        guard liveSearchEnabled else {
            return nil
        }
        let config = try configProvider.config()
        guard let url = config.liveSearchProxyBaseURL else {
            throw ShoppingIntegrationConfigError.missingLiveSearchProxy
        }
        return ProxyLiveRetailerSearchProvider(proxyBaseURL: url)
    }

    static func aggregatedSearchProvider(
        liveSearchEnabled: Bool = FeatureFlags.liveSearchEnabled,
        adapters: [RetailerSearchAdapter]
    ) -> ProductSearchProvider? {
        guard liveSearchEnabled else {
            return nil
        }
        return AggregatedSearchProvider(adapters: adapters)
    }
}

extension JSONDecoder {
    static var catalog: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
