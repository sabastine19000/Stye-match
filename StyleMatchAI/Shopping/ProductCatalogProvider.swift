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
        let currentDate = now()
        if let cachedProducts, let cachedAt {
            if currentDate.timeIntervalSince(cachedAt) < timeToLive {
                return cachedProducts
            }
            startBackgroundRefreshIfNeeded()
            return cachedProducts
        }

        if let inFlight {
            return try await inFlight.value
        }

        let task = Task { try await provider.products() }
        inFlight = task
        do {
            let products = try await task.value
            cachedProducts = products
            cachedAt = currentDate
            inFlight = nil
            return products
        } catch {
            inFlight = nil
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
                #if DEBUG
                print("[StyleMatch Shopping Stores] Skipping malformed store JSON object.")
                #endif
                return nil
            }

            do {
                return try JSONDecoder.catalog.decode(SupportedStore.self, from: data)
            } catch {
                #if DEBUG
                print("[StyleMatch Shopping Stores] Skipping malformed store: \(error.localizedDescription)")
                #endif
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
        let customerSafeProducts = decodedProducts.filter { product in
            let outboundURL = AffiliateLinkBuilder.outboundURL(for: product)
            return !AffiliateLinkBuilder.isPlaceholderURL(outboundURL)
        }

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
                #if DEBUG
                print("[StyleMatch Shopping Catalog] Skipping malformed product JSON object.")
                #endif
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
                #if DEBUG
                print("[StyleMatch Shopping Catalog] Skipping malformed product: \(error.localizedDescription)")
                #endif
                return nil
            }
        }
    }
}

typealias CatalogProductSearchProvider = CatalogSearchProvider

struct RemoteCatalogProvider: ProductCatalogProvider, CatalogDisclosureProviding {
    let baseURL: URL
    let cacheDirectory: URL
    let fallbackProvider: ProductCatalogProvider
    var urlSession: URLSession = .shared
    var refreshInterval: TimeInterval = 3600

    func products() async throws -> [AffiliateProduct] {
        if let cached = try? cachedProducts(), !cached.isEmpty {
            if shouldRefreshCache() {
                Task {
                    guard let data = try? await fetchRemoteData() else { return }
                    try? cache(data)
                }
            }
            return cached
        }

        do {
            let data = try await fetchRemoteData()
            let decoded: [AffiliateProduct]
            do {
                decoded = try Self.decodeRemoteProducts(data, baseURL: baseURL)
            } catch {
                #if DEBUG
                print("[StyleMatch Remote Catalog] Decode failed: \(type(of: error)) \(error.localizedDescription)")
                #endif
                throw error
            }
            guard !decoded.isEmpty else {
                #if DEBUG
                print("[StyleMatch Remote Catalog] Decode produced zero visible products.")
                #endif
                throw ProductCatalogProviderError.missingCatalog
            }
            try cache(data)
            return decoded
        } catch {
            #if DEBUG
            print("[StyleMatch Remote Catalog] Products load failed: \(type(of: error)) \(error.localizedDescription)")
            #endif
            if let cached = try? cachedProducts(), !cached.isEmpty {
                return cached
            }
            throw ProductCatalogProviderError.missingCatalog
        }
    }

    func disclosure() async -> String? {
        if let data = try? Data(contentsOf: cacheFileURL()),
           let disclosure = try? Self.decodeRemoteDisclosure(data) {
            return disclosure
        }
        guard let data = try? await fetchRemoteData() else {
            return nil
        }
        try? cache(data)
        return try? Self.decodeRemoteDisclosure(data)
    }

    static func decodeRemoteProducts(_ data: Data, baseURL: URL, regionCode: String = Self.currentRegionCode) throws -> [AffiliateProduct] {
        let response = try JSONDecoder.catalog.decode(RemoteProductsResponse.self, from: data)
        let normalizedRegion = regionCode.uppercased()
        return response.products.compactMap { remote in
            if let availableCountries = remote.availableCountries,
               !Self.countryList(availableCountries, contains: normalizedRegion) {
                return nil
            }
            guard let buyURL = URL(string: remote.buyURL, relativeTo: baseURL)?.absoluteURL else {
                #if DEBUG
                print("[StyleMatch Remote Catalog] Skipping product with invalid buy_url: \(remote.id)")
                #endif
                return nil
            }
            let imageURL = remote.imageURL.flatMap(URL.init(string:))
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
                imageURL: imageURL ?? Self.placeholderImageURL,
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
                availableColors: nil,
                customerRating: nil,
                reviewCount: nil,
                estimatedShippingText: nil,
                tags: remote.tags,
                genderPresentation: nil
            )
        }
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
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        #if DEBUG
        print("[StyleMatch Remote Catalog] Fetching catalog from \(url.absoluteString)")
        #endif
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            #if DEBUG
            print("[StyleMatch Remote Catalog] Missing HTTP response for \(url.absoluteString)")
            #endif
            throw ProductCatalogProviderError.missingCatalog
        }
        guard (200..<300).contains(http.statusCode) else {
            #if DEBUG
            let body = String(data: data.prefix(240), encoding: .utf8) ?? "<non-utf8 body>"
            print("[StyleMatch Remote Catalog] HTTP \(http.statusCode) for \(url.absoluteString): \(body)")
            #endif
            throw ProductCatalogProviderError.missingCatalog
        }
        return data
    }

    private func cachedProducts() throws -> [AffiliateProduct] {
        let data = try Data(contentsOf: cacheFileURL())
        return try Self.decodeRemoteProducts(data, baseURL: baseURL)
    }

    private func shouldRefreshCache(now: Date = Date()) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: cacheFileURL().path),
              let modified = attrs[.modificationDate] as? Date else {
            return true
        }
        return now.timeIntervalSince(modified) >= refreshInterval
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

    private static func countryList(_ countries: [String], contains regionCode: String) -> Bool {
        countries.contains("*") || countries.map { $0.uppercased() }.contains(regionCode.uppercased())
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

    private static let placeholderImageURL = URL(string: "https://stylematch.local/product-placeholder.png")!
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
