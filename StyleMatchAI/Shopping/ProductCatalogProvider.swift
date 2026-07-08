import Foundation

protocol ProductCatalogProvider {
    func products() async throws -> [AffiliateProduct]
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
        return try Self.decodeProducts(
            catalogData: Data(contentsOf: catalogURL),
            retailerConfigData: configURL.flatMap { try? Data(contentsOf: $0) }
        )
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

struct RemoteCatalogProvider: ProductCatalogProvider {
    let catalogURL: URL
    let cacheDirectory: URL
    let fallbackProvider: ProductCatalogProvider
    var urlSession: URLSession = .shared

    func products() async throws -> [AffiliateProduct] {
        do {
            let response = try await fetchRemoteData()
            try cache(response.data, etag: response.etag)
            if response.notModified, let cached = try? Data(contentsOf: cacheFileURL()) {
                return try BundledCatalogProvider.decodeProducts(catalogData: cached)
            }
            let data = response.data
            return try BundledCatalogProvider.decodeProducts(catalogData: data)
        } catch {
            if let cached = try? Data(contentsOf: cacheFileURL()) {
                return try BundledCatalogProvider.decodeProducts(catalogData: cached)
            }
            return try await fallbackProvider.products()
        }
    }

    private func fetchRemoteData() async throws -> (data: Data, etag: String?, notModified: Bool) {
        var request = URLRequest(url: catalogURL)
        if let etag = try? String(contentsOf: etagFileURL(), encoding: .utf8),
           !etag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        if let attrs = try? FileManager.default.attributesOfItem(atPath: cacheFileURL().path),
           let modified = attrs[.modificationDate] as? Date {
            request.setValue(Self.httpDateFormatter.string(from: modified), forHTTPHeaderField: "If-Modified-Since")
        }
        let (data, response) = try await urlSession.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 304 {
            return (Data(), nil, true)
        }
        return (data, (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "ETag"), false)
    }

    private func cache(_ data: Data, etag: String?) throws {
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try data.write(to: cacheFileURL(), options: .atomic)
        if let etag, !etag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try etag.write(to: etagFileURL(), atomically: true, encoding: .utf8)
        }
    }

    private func cacheFileURL() -> URL {
        cacheDirectory.appendingPathComponent("ProductCatalog.remote.json")
    }

    private func etagFileURL() -> URL {
        cacheDirectory.appendingPathComponent("ProductCatalog.remote.etag")
    }

    private static let httpDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter
    }()
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
