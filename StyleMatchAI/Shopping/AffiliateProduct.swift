import Foundation

enum ProductCategory: String, Codable, CaseIterable, Identifiable {
    case clothing
    case shoes
    case accessories
    case electronics
    case styleTools

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .clothing: return "Clothing"
        case .shoes: return "Shoes"
        case .accessories: return "Accessories"
        case .electronics: return "Electronics"
        case .styleTools: return "Style Tools"
        }
    }
}

struct Retailer: Codable, Equatable {
    let name: String
    let trackingID: String
    let trackingParamName: String
    let disclosureName: String
    let searchAdapter: String?
    let searchStatus: String?

    init(
        name: String,
        trackingID: String,
        trackingParamName: String,
        disclosureName: String,
        searchAdapter: String? = nil,
        searchStatus: String? = nil
    ) {
        self.name = name
        self.trackingID = trackingID
        self.trackingParamName = trackingParamName
        self.disclosureName = disclosureName
        self.searchAdapter = searchAdapter
        self.searchStatus = searchStatus
    }
}

enum AffiliateProvider: String, Codable, CaseIterable, Equatable {
    case amazon
    case awin
    case impact
    case cj
    case rakuten
    case manual
    case none
}

struct AffiliateProduct: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let category: ProductCategory
    let subcategory: String
    let colors: [String]
    let sizes: [String]?
    let priceRange: ClosedRange<Decimal>?
    let occasionTags: [String]?
    let brand: String?
    let imageURL: URL?
    let retailer: Retailer
    let affiliateURL: URL
    let countryCode: String?
    let merchant: String?
    let merchantRegion: String?
    let affiliateProvider: AffiliateProvider?
    let isAffiliateEligible: Bool?
    let productURL: URL?
    let fallbackURL: URL?
    let price: Decimal?
    let salePrice: Decimal?
    let saleEndsAt: Date?
    let currencyCode: String?
    let availableCountries: [String]?
    let availability: String?
    let availableColors: [String]?
    let customerRating: Double?
    let reviewCount: Int?
    let estimatedShippingText: String?
    let tags: [String]
    let genderPresentation: String?

    init(
        id: String,
        name: String,
        category: ProductCategory,
        subcategory: String,
        colors: [String],
        sizes: [String]? = nil,
        priceRange: ClosedRange<Decimal>? = nil,
        occasionTags: [String]? = nil,
        brand: String? = nil,
        imageURL: URL? = nil,
        retailer: Retailer,
        affiliateURL: URL,
        countryCode: String? = nil,
        merchant: String? = nil,
        merchantRegion: String? = nil,
        affiliateProvider: AffiliateProvider? = nil,
        isAffiliateEligible: Bool? = nil,
        productURL: URL? = nil,
        fallbackURL: URL? = nil,
        price: Decimal?,
        salePrice: Decimal?,
        saleEndsAt: Date?,
        currencyCode: String? = nil,
        availableCountries: [String]? = nil,
        availability: String? = nil,
        availableColors: [String]?,
        customerRating: Double?,
        reviewCount: Int?,
        estimatedShippingText: String?,
        tags: [String],
        genderPresentation: String?
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.subcategory = subcategory
        self.colors = colors
        self.sizes = sizes
        self.priceRange = priceRange
        self.occasionTags = occasionTags
        self.brand = brand
        self.imageURL = ProductImageURLValidator.validated(imageURL)
        self.retailer = retailer
        self.affiliateURL = affiliateURL
        self.countryCode = countryCode
        self.merchant = merchant
        self.merchantRegion = merchantRegion
        self.affiliateProvider = affiliateProvider
        self.isAffiliateEligible = isAffiliateEligible
        self.productURL = productURL
        self.fallbackURL = fallbackURL
        self.price = price
        self.salePrice = salePrice
        self.saleEndsAt = saleEndsAt
        self.currencyCode = currencyCode
        self.availableCountries = availableCountries
        self.availability = availability
        self.availableColors = availableColors
        self.customerRating = customerRating
        self.reviewCount = reviewCount
        self.estimatedShippingText = estimatedShippingText
        self.tags = tags
        self.genderPresentation = genderPresentation
    }

    /// The only URL shopping views may pass to an image loader. Invalid, blank,
    /// relative, and non-HTTP(S) values resolve to nil and therefore cannot start a request.
    var remoteImageRequestURL: URL? {
        ProductImageURLValidator.validated(imageURL)
    }
}

enum ProductImageURLValidator {
    static func validated(_ url: URL?) -> URL? {
        guard let url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              scheme == "https",
              let host = components.host,
              !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return url
    }

    static func validated(_ rawValue: String?) -> URL? {
        guard let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return validated(URL(string: trimmed))
    }
}

struct RetailerConfig: Codable, Equatable {
    let retailers: [Retailer]

    func retailer(named name: String) -> Retailer? {
        retailers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }
}

struct SupportedStore: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let domains: [String]
    let categories: [ProductCategory]
    let affiliateNetwork: String?
    let apiStatus: String
    let isEnabled: Bool
    let websiteURL: URL?
    let searchURLTemplate: String?
    let affiliateTrackingActive: Bool?
    let disclosureText: String?

    init(
        id: String,
        name: String,
        domains: [String],
        categories: [ProductCategory],
        affiliateNetwork: String?,
        apiStatus: String,
        isEnabled: Bool,
        websiteURL: URL? = nil,
        searchURLTemplate: String? = nil,
        affiliateTrackingActive: Bool? = nil,
        disclosureText: String? = nil
    ) {
        self.id = id
        self.name = name
        self.domains = domains
        self.categories = categories
        self.affiliateNetwork = affiliateNetwork
        self.apiStatus = apiStatus
        self.isEnabled = isEnabled
        self.websiteURL = websiteURL
        self.searchURLTemplate = searchURLTemplate
        self.affiliateTrackingActive = affiliateTrackingActive
        self.disclosureText = disclosureText
    }

    var primaryDomain: String? {
        domains.first?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
    }

    var directAccessURL: URL? {
        if let websiteURL,
           websiteURL.scheme?.lowercased() == "https" {
            return websiteURL
        }
        guard let domain = primaryDomain else { return nil }
        return URL(string: "https://www.\(domain)")
    }

    func searchURL(for query: String) -> URL? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let template = searchURLTemplate?.trimmingCharacters(in: .whitespacesAndNewlines),
              !template.isEmpty else {
            return directAccessURL
        }
        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: template.replacingOccurrences(of: "{QUERY}", with: encoded))
    }

    var integrationLabel: String {
        apiStatus.localizedCaseInsensitiveContains("placeholder") || apiStatus.localizedCaseInsensitiveContains("pending")
            ? "Direct Store Access"
            : "Catalog Integration Coming Soon"
    }

    var hasAffiliateTracking: Bool {
        affiliateTrackingActive == true || affiliateNetwork?.localizedCaseInsensitiveContains("amazon") == true
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case domains
        case categories
        case affiliateNetwork
        case apiStatus
        case isEnabled
        case websiteURL
        case searchURLTemplate
        case affiliateTrackingActive
        case disclosureText
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct ShoppingSearchCriteria: Equatable {
    var query: String = ""
    var storeName: String?
    var brand: String?
    var category: ProductCategory?
    var color: String?
    var size: String?
    var style: String?
    var genderPresentation: String?
    var minimumPrice: Decimal?
    var maximumPrice: Decimal?
    var occasion: String?

    var isEmpty: Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && storeName == nil
            && brand == nil
            && category == nil
            && color == nil
            && size == nil
            && style == nil
            && genderPresentation == nil
            && minimumPrice == nil
            && maximumPrice == nil
            && occasion == nil
    }
}

enum SearchSort: String, Equatable {
    case relevance
    case priceLowHigh
    case priceHighLow
    case newestSale
}

struct ProductSearchQuery: Equatable {
    var text: String?
    var retailers: [String]?
    var brands: [String]?
    var categories: [ProductCategory]?
    var colors: [String]?
    var sizes: [String]?
    var genderPresentation: String?
    var priceRange: ClosedRange<Decimal>?
    var occasions: [String]?
    var onSaleOnly: Bool
    var sort: SearchSort

    init(
        text: String? = nil,
        retailers: [String]? = nil,
        brands: [String]? = nil,
        categories: [ProductCategory]? = nil,
        colors: [String]? = nil,
        sizes: [String]? = nil,
        genderPresentation: String? = nil,
        priceRange: ClosedRange<Decimal>? = nil,
        occasions: [String]? = nil,
        onSaleOnly: Bool = false,
        sort: SearchSort = .relevance
    ) {
        self.text = text
        self.retailers = retailers
        self.brands = brands
        self.categories = categories
        self.colors = colors
        self.sizes = sizes
        self.genderPresentation = genderPresentation
        self.priceRange = priceRange
        self.occasions = occasions
        self.onSaleOnly = onSaleOnly
        self.sort = sort
    }
}

struct ShoppingIntegrationConfig: Codable, Equatable {
    let catalogBaseURL: URL?
    let liveSearchProxyBaseURL: URL?
    let allowedClientSideAPIKeyNames: [String]

    init(
        catalogBaseURL: URL? = nil,
        liveSearchProxyBaseURL: URL? = nil,
        allowedClientSideAPIKeyNames: [String] = []
    ) {
        self.catalogBaseURL = catalogBaseURL
        self.liveSearchProxyBaseURL = liveSearchProxyBaseURL
        self.allowedClientSideAPIKeyNames = allowedClientSideAPIKeyNames
    }

    static let empty = ShoppingIntegrationConfig(
        catalogBaseURL: nil,
        liveSearchProxyBaseURL: nil,
        allowedClientSideAPIKeyNames: []
    )
}

enum AffiliateLinkBuilder {
    static let pendingApprovalTrackingID = "PENDING-APPROVAL"

    static func isPlaceholderURL(_ url: URL) -> Bool {
        let normalizedURL = url.absoluteString.uppercased()
        if url.host?.lowercased() == "stylematch.local" {
            return true
        }
        return normalizedURL.contains("PENDING-APPROVAL") || normalizedURL.contains("REPLACE_WITH")
    }

    static func outboundURL(for product: AffiliateProduct) -> URL {
        if product.isAffiliateEligible == false {
            return product.fallbackURL ?? product.productURL ?? product.affiliateURL
        }

        let retailer = product.retailer
        guard retailer.trackingID != pendingApprovalTrackingID,
              !retailer.trackingID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !retailer.trackingParamName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              var components = URLComponents(url: product.affiliateURL, resolvingAgainstBaseURL: false) else {
            return product.fallbackURL ?? product.productURL ?? product.affiliateURL
        }

        var queryItems = components.queryItems ?? []
        queryItems.removeAll { $0.name == retailer.trackingParamName }
        queryItems.append(URLQueryItem(name: retailer.trackingParamName, value: retailer.trackingID))
        components.queryItems = queryItems
        return components.url ?? product.affiliateURL
    }
}

struct AffiliateLinkRequest: Equatable {
    let productID: String
    let countryCode: String
    let currency: String?
    let merchant: String
    let merchantRegion: String?
    let productURL: URL
    let fallbackURL: URL?
    let preferredProvider: AffiliateProvider?

    init(
        productID: String,
        countryCode: String,
        currency: String? = nil,
        merchant: String,
        merchantRegion: String? = nil,
        productURL: URL,
        fallbackURL: URL? = nil,
        preferredProvider: AffiliateProvider? = nil
    ) {
        self.productID = productID
        self.countryCode = countryCode.uppercased()
        self.currency = currency
        self.merchant = merchant
        self.merchantRegion = merchantRegion?.uppercased()
        self.productURL = productURL
        self.fallbackURL = fallbackURL
        self.preferredProvider = preferredProvider
    }
}

struct AffiliateLinkResponse: Codable, Equatable {
    let productID: String
    let countryCode: String
    let currency: String?
    let merchant: String
    let merchantRegion: String?
    let affiliateProvider: AffiliateProvider
    let isAffiliateEligible: Bool
    let productURL: URL
    let affiliateURL: URL?
    let fallbackURL: URL

    var safeOutboundURL: URL {
        isAffiliateEligible ? (affiliateURL ?? fallbackURL) : fallbackURL
    }
}

protocol AffiliateLinkResolvingAdapter {
    var provider: AffiliateProvider { get }
    func canResolve(_ request: AffiliateLinkRequest) -> Bool
    func resolve(_ request: AffiliateLinkRequest) -> AffiliateLinkResponse
}

struct RegionAwareAffiliateLinkService {
    let adapters: [AffiliateLinkResolvingAdapter]

    init(adapters: [AffiliateLinkResolvingAdapter]) {
        self.adapters = adapters
    }

    func resolve(_ request: AffiliateLinkRequest) -> AffiliateLinkResponse {
        let adapter = adapters.first { adapter in
            if let preferred = request.preferredProvider, adapter.provider != preferred {
                return false
            }
            return adapter.canResolve(request)
        } ?? adapters.first { $0.provider == .manual }

        return adapter?.resolve(request) ?? ManualLinkAdapter().resolve(request)
    }
}

struct RegionalAffiliateAdapter: AffiliateLinkResolvingAdapter {
    let provider: AffiliateProvider
    let supportedCountries: Set<String>
    let supportedMerchantRegions: Set<String>

    init(
        provider: AffiliateProvider,
        supportedCountries: Set<String>,
        supportedMerchantRegions: Set<String> = []
    ) {
        self.provider = provider
        self.supportedCountries = Set(supportedCountries.map { $0.uppercased() })
        self.supportedMerchantRegions = Set(supportedMerchantRegions.map { $0.uppercased() })
    }

    func canResolve(_ request: AffiliateLinkRequest) -> Bool {
        let countryAllowed = supportedCountries.contains("*") || supportedCountries.contains(request.countryCode)
        let merchantRegionAllowed = request.merchantRegion.map { supportedMerchantRegions.isEmpty || supportedMerchantRegions.contains($0) } ?? true
        return countryAllowed && merchantRegionAllowed
    }

    func resolve(_ request: AffiliateLinkRequest) -> AffiliateLinkResponse {
        AffiliateLinkResponse(
            productID: request.productID,
            countryCode: request.countryCode,
            currency: request.currency,
            merchant: request.merchant,
            merchantRegion: request.merchantRegion,
            affiliateProvider: provider,
            isAffiliateEligible: true,
            productURL: request.productURL,
            affiliateURL: request.productURL,
            fallbackURL: request.fallbackURL ?? request.productURL
        )
    }
}

struct ManualLinkAdapter: AffiliateLinkResolvingAdapter {
    let provider: AffiliateProvider = .manual

    func canResolve(_ request: AffiliateLinkRequest) -> Bool {
        true
    }

    func resolve(_ request: AffiliateLinkRequest) -> AffiliateLinkResponse {
        AffiliateLinkResponse(
            productID: request.productID,
            countryCode: request.countryCode,
            currency: request.currency,
            merchant: request.merchant,
            merchantRegion: request.merchantRegion,
            affiliateProvider: .manual,
            isAffiliateEligible: false,
            productURL: request.productURL,
            affiliateURL: nil,
            fallbackURL: request.fallbackURL ?? request.productURL
        )
    }
}

enum ShoppingTabVisibility {
    static func shouldShowShoppingTab(shoppingTabEnabled: Bool = FeatureFlags.shoppingTabEnabled) -> Bool {
        shoppingTabEnabled
    }
}

struct AffiliateProductViewModel: Equatable {
    let id: String
    let name: String
    let brandText: String?
    let retailerName: String
    let soldAndShippedText: String
    let priceText: String
    let saleBadgeText: String?
    let originalPriceText: String?
    let footnote: String?
    let reasonText: String?
    let matchText: String?
    let saleCountdownText: String?
    let availableSizesText: String?
    let availableColorsText: String?
    let ratingText: String?
    let shippingText: String?
    let outboundURL: URL
    let actionTitle: String

    init(product: AffiliateProduct, reasonText: String? = nil, matchPercent: Int? = nil, now: Date = Date()) {
        self.id = product.id
        self.name = product.name
        self.brandText = Self.displayBrand(product.brand, retailerName: product.retailer.name)
        self.retailerName = product.retailer.name
        self.soldAndShippedText = "Sold and shipped by \(product.retailer.disclosureName)"
        self.reasonText = reasonText
        self.matchText = matchPercent.map { "\(max(0, min(100, $0)))% Match" }
        self.saleCountdownText = Self.saleCountdown(until: product.saleEndsAt, now: now)
        self.availableSizesText = product.sizes.flatMap { values in
            let clean = values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            return clean.isEmpty ? nil : "Sizes: \(clean.prefix(5).joined(separator: ", "))"
        }
        self.availableColorsText = {
            let values = product.availableColors ?? product.colors
            let clean = values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).capitalized }.filter { !$0.isEmpty }
            return clean.isEmpty ? nil : "Colors: \(clean.prefix(4).joined(separator: ", "))"
        }()
        if let rating = product.customerRating {
            let ratingText = String(format: "%.1f", max(0, min(5, rating)))
            if let reviewCount = product.reviewCount, reviewCount > 0 {
                self.ratingText = "\(ratingText) stars · \(reviewCount) reviews"
            } else {
                self.ratingText = "\(ratingText) stars"
            }
        } else {
            self.ratingText = nil
        }
        self.shippingText = product.estimatedShippingText
        self.outboundURL = AffiliateLinkBuilder.outboundURL(for: product)
        self.actionTitle = product.isAmazonSourced ? "View on Amazon" : "View Product"

        if product.retailer.name.caseInsensitiveCompare("Amazon") == .orderedSame {
            self.priceText = "See price at Amazon"
            self.saleBadgeText = product.salePrice != nil && (product.saleEndsAt ?? .distantFuture) > now ? "Sale" : nil
            self.originalPriceText = nil
            self.footnote = nil
        } else if let salePrice = product.salePrice, (product.saleEndsAt ?? .distantFuture) > now {
            self.priceText = Self.currency(salePrice, code: product.currencyCode)
            self.saleBadgeText = "Sale"
            self.originalPriceText = product.price.map { Self.currency($0, code: product.currencyCode) }
            self.footnote = "Price may vary - confirmed at checkout"
        } else if let price = product.price {
            self.priceText = Self.currency(price, code: product.currencyCode)
            self.saleBadgeText = nil
            self.originalPriceText = nil
            self.footnote = "Price may vary - confirmed at checkout"
        } else if let priceRange = product.priceRange {
            self.priceText = "\(Self.currency(priceRange.lowerBound, code: product.currencyCode))-\(Self.currency(priceRange.upperBound, code: product.currencyCode))"
            self.saleBadgeText = nil
            self.originalPriceText = nil
            self.footnote = "Price may vary - confirmed at checkout"
        } else {
            self.priceText = "See price at retailer"
            self.saleBadgeText = nil
            self.originalPriceText = nil
            self.footnote = "Price may vary - confirmed at checkout"
        }
    }

    private static func currency(_ value: Decimal, code: String?) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "en_US")
        if let code, !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            formatter.currencyCode = code
        }
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }

    private static func displayBrand(_ brand: String?, retailerName: String) -> String? {
        let cleanedBrand = brand?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let cleanedBrand, !cleanedBrand.isEmpty else {
            return nil
        }

        return cleanedBrand.caseInsensitiveCompare(retailerName) == .orderedSame ? nil : cleanedBrand
    }

    private static func saleCountdown(until date: Date?, now: Date) -> String? {
        guard let date, date > now else { return nil }
        let seconds = date.timeIntervalSince(now)
        let days = Int(seconds / 86_400)
        if days > 1 { return "Sale ends in \(days) days" }
        if days == 1 { return "Sale ends tomorrow" }
        let hours = max(1, Int(seconds / 3_600))
        return "Sale ends in \(hours) hr"
    }
}

extension AffiliateProduct {
    var isAmazonSourced: Bool {
        if affiliateProvider == .amazon { return true }
        return retailer.name.caseInsensitiveCompare("Amazon") == .orderedSame
    }
}
