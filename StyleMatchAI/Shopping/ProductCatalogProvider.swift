import Foundation

protocol ProductCatalogProvider {
    func products() async throws -> [AffiliateProduct]
}

enum ProductCatalogSource: String, Equatable {
    case remote
    case cache
    case bundled
    case none
}

enum ProductCatalogFailureClassification: String, Equatable {
    case timeout
    case dns
    case connectivity
    case tls
    case http
    case decoding
    case cancellation
    case missingCatalog
    case unknown
}

struct ProductCatalogLoadDiagnostic: Equatable {
    var effectiveEndpoint: String? = nil
    var requestStartedAt: Date? = nil
    var requestCompletedAt: Date? = nil
    var httpStatus: Int? = nil
    var urlSessionErrorDomain: String? = nil
    var urlSessionErrorCode: Int? = nil
    var classification: ProductCatalogFailureClassification? = nil
    var remoteProductCount: Int? = nil
    var cacheHit: Bool = false
    var cacheAge: TimeInterval? = nil
    var bundledFallbackCount: Int? = nil
    var finalSource: ProductCatalogSource = .none

    static let empty = ProductCatalogLoadDiagnostic()

    var debugSummary: String {
        [
            "endpoint=\(effectiveEndpoint ?? "none")",
            "started=\(requestStartedAt.map(Self.isoString) ?? "none")",
            "completed=\(requestCompletedAt.map(Self.isoString) ?? "none")",
            "http_status=\(httpStatus.map(String.init) ?? "none")",
            "error_domain=\(urlSessionErrorDomain ?? "none")",
            "error_code=\(urlSessionErrorCode.map(String.init) ?? "none")",
            "classification=\(classification?.rawValue ?? "none")",
            "remote_count=\(remoteProductCount.map(String.init) ?? "none")",
            "cache=\(cacheHit ? "hit" : "miss")",
            "cache_age=\(cacheAge.map { String(format: "%.0fs", $0) } ?? "none")",
            "bundled_count=\(bundledFallbackCount.map(String.init) ?? "none")",
            "final_source=\(finalSource.rawValue)"
        ].joined(separator: " ")
    }

    private static func isoString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

struct ProductCatalogLoadResult: Equatable {
    let products: [AffiliateProduct]
    let source: ProductCatalogSource
    let diagnostic: ProductCatalogLoadDiagnostic
}

protocol ProductCatalogSourceProviding {
    func loadResult() async -> ProductCatalogLoadResult
}

private struct RemoteCatalogFetchResult {
    let data: Data
    let startedAt: Date
    let completedAt: Date
    let statusCode: Int?
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
    private var cachedResult: ProductCatalogLoadResult?
    private var cachedAt: Date?
    private var inFlight: Task<ProductCatalogLoadResult, Never>?

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
        let result = await loadResult()
        guard result.source != .none else {
            throw ProductCatalogProviderError.missingCatalog
        }
        return result.products
    }

    func loadResult() async -> ProductCatalogLoadResult {
        #if DEBUG
        let startedAt = Date()
        func logDuration(_ message: String) {
            print("[StyleMatch Shop Perf] catalog loader \(message) elapsed=\(String(format: "%.3fs", Date().timeIntervalSince(startedAt)))")
        }
        #endif
        let currentDate = now()
        if let cachedResult, let cachedAt {
            if currentDate.timeIntervalSince(cachedAt) < timeToLive {
                #if DEBUG
                logDuration("memory-cache hit products=\(cachedResult.products.count) source=\(cachedResult.source.rawValue)")
                #endif
                return cachedResult
            }
            startBackgroundRefreshIfNeeded()
            #if DEBUG
            logDuration("stale memory-cache returned products=\(cachedResult.products.count) source=\(cachedResult.source.rawValue)")
            #endif
            return cachedResult
        }

        if let inFlight {
            let result = await inFlight.value
            #if DEBUG
            logDuration("joined in-flight products=\(result.products.count) source=\(result.source.rawValue)")
            #endif
            return result
        }

        let task = Task { await loadFromProvider() }
        inFlight = task
        let result = await task.value
        cachedResult = result.source == .none ? nil : result
        cachedAt = result.source == .none ? nil : currentDate
        inFlight = nil
        #if DEBUG
        logDuration("provider fetch products=\(result.products.count) source=\(result.source.rawValue)")
        #endif
        return result
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
        let task = Task { await loadFromProvider() }
        inFlight = task
        Task {
            let result = await task.value
            finishBackgroundRefresh(result)
        }
    }

    private func finishBackgroundRefresh(_ result: ProductCatalogLoadResult) {
        inFlight = nil
        guard result.source != .none else { return }
        cachedResult = result
        cachedAt = now()
    }

    private func loadFromProvider() async -> ProductCatalogLoadResult {
        if let sourceProvider = provider as? ProductCatalogSourceProviding {
            return await sourceProvider.loadResult()
        }
        do {
            let products = try await provider.products()
            return ProductCatalogLoadResult(
                products: products,
                source: .bundled,
                diagnostic: ProductCatalogLoadDiagnostic(
                    remoteProductCount: nil,
                    cacheHit: false,
                    bundledFallbackCount: products.count,
                    finalSource: .bundled
                )
            )
        } catch {
            return ProductCatalogLoadResult(
                products: [],
                source: .none,
                diagnostic: ProductCatalogLoadDiagnostic(
                    urlSessionErrorDomain: (error as NSError).domain,
                    urlSessionErrorCode: (error as NSError).code,
                    classification: .missingCatalog,
                    cacheHit: false,
                    finalSource: .none
                )
            )
        }
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

struct BundledCatalogProvider: ProductCatalogProvider, ProductCatalogSourceProviding {
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
        let result = await loadResult()
        guard result.source != .none else {
            throw ProductCatalogProviderError.missingCatalog
        }
        return result.products
    }

    func loadResult() async -> ProductCatalogLoadResult {
        guard let catalogURL = bundle.url(forResource: catalogResourceName, withExtension: "json") else {
            return ProductCatalogLoadResult(
                products: [],
                source: .none,
                diagnostic: ProductCatalogLoadDiagnostic(
                    classification: .missingCatalog,
                    cacheHit: false,
                    bundledFallbackCount: 0,
                    finalSource: .none
                )
            )
        }
        let configURL = bundle.url(forResource: retailerConfigResourceName, withExtension: "json")
        do {
            let decodedProducts = try Self.decodeProducts(
                catalogData: Data(contentsOf: catalogURL),
                retailerConfigData: configURL.flatMap { try? Data(contentsOf: $0) }
            )
            let customerSafeProducts = CatalogProductSafetyValidator.validated(decodedProducts)

            guard !customerSafeProducts.isEmpty else {
                return ProductCatalogLoadResult(
                    products: [],
                    source: .none,
                    diagnostic: ProductCatalogLoadDiagnostic(
                        classification: .missingCatalog,
                        cacheHit: false,
                        bundledFallbackCount: 0,
                        finalSource: .none
                    )
                )
            }

            return ProductCatalogLoadResult(
                products: customerSafeProducts,
                source: .bundled,
                diagnostic: ProductCatalogLoadDiagnostic(
                    cacheHit: false,
                    bundledFallbackCount: customerSafeProducts.count,
                    finalSource: .bundled
                )
            )
        } catch {
            return ProductCatalogLoadResult(
                products: [],
                source: .none,
                diagnostic: ProductCatalogLoadDiagnostic(
                    urlSessionErrorDomain: (error as NSError).domain,
                    urlSessionErrorCode: (error as NSError).code,
                    classification: .decoding,
                    cacheHit: false,
                    bundledFallbackCount: 0,
                    finalSource: .none
                )
            )
        }
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
                        retailerID: decoded.retailerID,
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
                #if DEBUG
                print("[StyleMatch Shopping Catalog] Skipping malformed product: \(error.localizedDescription)")
                #endif
                return nil
            }
        }
    }
}

typealias CatalogProductSearchProvider = CatalogSearchProvider

struct RemoteCatalogProvider: ProductCatalogProvider, CatalogDisclosureProviding, ProductCatalogSourceProviding {
    /// Catalog requests should complete well within this 10-second budget under
    /// normal conditions while still tolerating cellular connection setup.
    static let defaultRequestTimeout: TimeInterval = 10

    let baseURL: URL
    let cacheDirectory: URL
    let fallbackProvider: ProductCatalogProvider
    var urlSession: URLSession = .shared
    var requestTimeout: TimeInterval = Self.defaultRequestTimeout

    func products() async throws -> [AffiliateProduct] {
        let result = await loadResult()
        if result.diagnostic.classification == .cancellation {
            throw CancellationError()
        }
        guard result.source != .none else {
            throw ProductCatalogProviderError.missingCatalog
        }
        return result.products
    }

    func loadResult() async -> ProductCatalogLoadResult {
        var diagnostic = ProductCatalogLoadDiagnostic.empty
        diagnostic.effectiveEndpoint = sanitizedProductsEndpoint()?.absoluteString
        if Task.isCancelled {
            diagnostic.classification = .cancellation
            diagnostic.finalSource = .none
            return ProductCatalogLoadResult(products: [], source: .none, diagnostic: diagnostic)
        }
        do {
            let fetch = try await fetchRemoteData()
            diagnostic.requestStartedAt = fetch.startedAt
            diagnostic.requestCompletedAt = fetch.completedAt
            diagnostic.httpStatus = fetch.statusCode
            if Task.isCancelled {
                diagnostic.classification = .cancellation
                diagnostic.finalSource = .none
                return ProductCatalogLoadResult(products: [], source: .none, diagnostic: diagnostic)
            }
            let decoded = try Self.decodeRemoteProducts(fetch.data, baseURL: baseURL)
            diagnostic.remoteProductCount = decoded.count
            guard !decoded.isEmpty else {
                debugLog("remote decode produced zero safe products")
                diagnostic.classification = .decoding
                throw ProductCatalogProviderError.missingCatalog
            }
            do {
                try cache(fetch.data)
            } catch {
                debugLog(error, prefix: "cache write failed; keeping decoded remote catalog")
            }
            diagnostic.finalSource = .remote
            debugLog("selected source=remote products=\(decoded.count)")
            debugLog(diagnostic.debugSummary)
            return ProductCatalogLoadResult(products: decoded, source: .remote, diagnostic: diagnostic)
        } catch {
            if Self.isCancellation(error) {
                diagnostic.classification = .cancellation
                debugLog(diagnostic.debugSummary)
                return ProductCatalogLoadResult(products: [], source: .none, diagnostic: diagnostic)
            }
            let nsError = error as NSError
            diagnostic.urlSessionErrorDomain = nsError.domain
            diagnostic.urlSessionErrorCode = nsError.code
            diagnostic.classification = diagnostic.classification ?? Self.classification(for: error)
            diagnostic.requestCompletedAt = diagnostic.requestCompletedAt ?? Date()
            debugLog(error, prefix: "remote source failed")
        }

        if Task.isCancelled {
            diagnostic.classification = .cancellation
            diagnostic.finalSource = .none
            return ProductCatalogLoadResult(products: [], source: .none, diagnostic: diagnostic)
        }
        do {
            let cached = try cachedProductsWithMetadata()
            diagnostic.cacheHit = true
            diagnostic.cacheAge = cached.age
            if !cached.products.isEmpty {
                diagnostic.finalSource = .cache
                debugLog("selected source=cache products=\(cached.products.count)")
                debugLog(diagnostic.debugSummary)
                return ProductCatalogLoadResult(products: cached.products, source: .cache, diagnostic: diagnostic)
            }
            debugLog("cache decoded zero safe products")
        } catch {
            if Self.isCancellation(error) {
                diagnostic.classification = .cancellation
                debugLog(diagnostic.debugSummary)
                return ProductCatalogLoadResult(products: [], source: .none, diagnostic: diagnostic)
            }
            debugLog(error, prefix: "cache source failed")
        }

        if Task.isCancelled {
            diagnostic.classification = .cancellation
            diagnostic.finalSource = .none
            return ProductCatalogLoadResult(products: [], source: .none, diagnostic: diagnostic)
        }
        let fallbackResult: ProductCatalogLoadResult
        if let sourceProvider = fallbackProvider as? ProductCatalogSourceProviding {
            fallbackResult = await sourceProvider.loadResult()
        } else {
            do {
                let products = CatalogProductSafetyValidator.validated(try await fallbackProvider.products())
                fallbackResult = ProductCatalogLoadResult(
                    products: products,
                    source: products.isEmpty ? .none : .bundled,
                    diagnostic: ProductCatalogLoadDiagnostic(
                        bundledFallbackCount: products.count,
                        finalSource: products.isEmpty ? .none : .bundled
                    )
                )
            } catch {
                fallbackResult = ProductCatalogLoadResult(
                    products: [],
                    source: .none,
                    diagnostic: ProductCatalogLoadDiagnostic(
                        urlSessionErrorDomain: (error as NSError).domain,
                        urlSessionErrorCode: (error as NSError).code,
                        classification: .missingCatalog,
                        bundledFallbackCount: 0,
                        finalSource: .none
                    )
                )
            }
        }
        diagnostic.bundledFallbackCount = fallbackResult.products.count
        if fallbackResult.source == .bundled, !fallbackResult.products.isEmpty {
            diagnostic.finalSource = .bundled
            debugLog("selected source=bundled products=\(fallbackResult.products.count)")
            debugLog(diagnostic.debugSummary)
            return ProductCatalogLoadResult(products: fallbackResult.products, source: .bundled, diagnostic: diagnostic)
        } else {
            diagnostic.classification = diagnostic.classification ?? fallbackResult.diagnostic.classification ?? .missingCatalog
            debugLog("bundled source failed products=\(fallbackResult.products.count)")
        }

        diagnostic.finalSource = .none
        debugLog("all catalog sources failed")
        debugLog(diagnostic.debugSummary)
        return ProductCatalogLoadResult(products: [], source: .none, diagnostic: diagnostic)
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
                #if DEBUG
                print("[StyleMatch Remote Catalog] Skipping product with invalid buy_url: \(remote.id)")
                #endif
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
                retailerID: remote.storeID,
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

    private func fetchRemoteData() async throws -> RemoteCatalogFetchResult {
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
        #if DEBUG
        print("[StyleMatch Remote Catalog] Fetching catalog from \(url.absoluteString)")
        #endif
        let startedAt = Date()
        do {
            let (data, response) = try await urlSession.data(for: request)
            let completedAt = Date()
            let duration = completedAt.timeIntervalSince(startedAt)
            guard let http = response as? HTTPURLResponse else {
                debugLog("request duration=\(Self.durationText(duration)) status=unavailable")
                throw ProductCatalogProviderError.missingCatalog
            }
            debugLog("request duration=\(Self.durationText(duration)) status=\(http.statusCode)")
            guard (200..<300).contains(http.statusCode) else {
                throw CatalogHTTPError(statusCode: http.statusCode)
            }
            return RemoteCatalogFetchResult(data: data, startedAt: startedAt, completedAt: completedAt, statusCode: http.statusCode)
        } catch {
            let duration = Date().timeIntervalSince(startedAt)
            debugLog(error, prefix: "request duration=\(Self.durationText(duration)) status=unavailable")
            throw error
        }
    }

    private func cachedProducts() throws -> [AffiliateProduct] {
        try cachedProductsWithMetadata().products
    }

    private func cachedProductsWithMetadata() throws -> (products: [AffiliateProduct], age: TimeInterval?) {
        let fileURL = cacheFileURL()
        let data = try Data(contentsOf: fileURL)
        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let modifiedAt = attributes?[.modificationDate] as? Date
        let age = modifiedAt.map { Date().timeIntervalSince($0) }
        return (try Self.decodeRemoteProducts(data, baseURL: baseURL), age)
    }

    private func cache(_ data: Data) throws {
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try data.write(to: cacheFileURL(), options: .atomic)
    }

    private func cacheFileURL() -> URL {
        cacheDirectory.appendingPathComponent("ProductCatalog.worker.remote.json")
    }

    private func sanitizedProductsEndpoint() -> URL? {
        var components = URLComponents(url: baseURL.appendingPathComponent("v1/products"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "limit", value: "100"),
            URLQueryItem(name: "country", value: Self.currentRegionCode)
        ]
        return components?.url
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

    private static func classification(for error: Error) -> ProductCatalogFailureClassification {
        if isCancellation(error) {
            return .cancellation
        }
        if let httpError = error as? CatalogHTTPError {
            return (200..<300).contains(httpError.statusCode) ? .unknown : .http
        }
        if error is DecodingError {
            return .decoding
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return .timeout
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return .dns
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return .connectivity
            case .secureConnectionFailed, .serverCertificateHasBadDate, .serverCertificateUntrusted, .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid, .clientCertificateRejected, .clientCertificateRequired:
                return .tls
            default:
                return .unknown
            }
        }
        if error is ProductCatalogProviderError {
            return .missingCatalog
        }
        return .unknown
    }

    private static func durationText(_ duration: TimeInterval) -> String {
        String(format: "%.3fs", duration)
    }

    private func debugLog(_ message: @autoclosure () -> String) {
        #if DEBUG
        print("[StyleMatch Remote Catalog] \(message())")
        #endif
    }

    private func debugLog(_ error: Error, prefix: String) {
        #if DEBUG
        let nsError = error as NSError
        print("[StyleMatch Remote Catalog] \(prefix) error_domain=\(nsError.domain) error_code=\(nsError.code)")
        #endif
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
