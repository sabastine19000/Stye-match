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
    let retailerID: String?
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
        retailerID: String? = nil,
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
        self.retailerID = Self.normalizedRetailerID(retailerID)
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

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case category
        case subcategory
        case colors
        case sizes
        case priceRange
        case occasionTags
        case brand
        case imageURL
        case retailerID
        case retailerIDSnake = "retailer_id"
        case retailer
        case affiliateURL
        case countryCode
        case merchant
        case merchantRegion
        case affiliateProvider
        case isAffiliateEligible
        case productURL
        case fallbackURL
        case price
        case salePrice
        case saleEndsAt
        case currencyCode
        case availableCountries
        case availability
        case availableColors
        case customerRating
        case reviewCount
        case estimatedShippingText
        case tags
        case genderPresentation
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            name: try container.decode(String.self, forKey: .name),
            category: try container.decode(ProductCategory.self, forKey: .category),
            subcategory: try container.decode(String.self, forKey: .subcategory),
            colors: try container.decode([String].self, forKey: .colors),
            sizes: try container.decodeIfPresent([String].self, forKey: .sizes),
            priceRange: try container.decodeIfPresent(ClosedRange<Decimal>.self, forKey: .priceRange),
            occasionTags: try container.decodeIfPresent([String].self, forKey: .occasionTags),
            brand: try container.decodeIfPresent(String.self, forKey: .brand),
            imageURL: try container.decodeIfPresent(URL.self, forKey: .imageURL),
            retailerID: try container.decodeIfPresent(String.self, forKey: .retailerID)
                ?? container.decodeIfPresent(String.self, forKey: .retailerIDSnake),
            retailer: try container.decode(Retailer.self, forKey: .retailer),
            affiliateURL: try container.decode(URL.self, forKey: .affiliateURL),
            countryCode: try container.decodeIfPresent(String.self, forKey: .countryCode),
            merchant: try container.decodeIfPresent(String.self, forKey: .merchant),
            merchantRegion: try container.decodeIfPresent(String.self, forKey: .merchantRegion),
            affiliateProvider: try container.decodeIfPresent(AffiliateProvider.self, forKey: .affiliateProvider),
            isAffiliateEligible: try container.decodeIfPresent(Bool.self, forKey: .isAffiliateEligible),
            productURL: try container.decodeIfPresent(URL.self, forKey: .productURL),
            fallbackURL: try container.decodeIfPresent(URL.self, forKey: .fallbackURL),
            price: try container.decodeIfPresent(Decimal.self, forKey: .price),
            salePrice: try container.decodeIfPresent(Decimal.self, forKey: .salePrice),
            saleEndsAt: try container.decodeIfPresent(Date.self, forKey: .saleEndsAt),
            currencyCode: try container.decodeIfPresent(String.self, forKey: .currencyCode),
            availableCountries: try container.decodeIfPresent([String].self, forKey: .availableCountries),
            availability: try container.decodeIfPresent(String.self, forKey: .availability),
            availableColors: try container.decodeIfPresent([String].self, forKey: .availableColors),
            customerRating: try container.decodeIfPresent(Double.self, forKey: .customerRating),
            reviewCount: try container.decodeIfPresent(Int.self, forKey: .reviewCount),
            estimatedShippingText: try container.decodeIfPresent(String.self, forKey: .estimatedShippingText),
            tags: try container.decode([String].self, forKey: .tags),
            genderPresentation: try container.decodeIfPresent(String.self, forKey: .genderPresentation)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(category, forKey: .category)
        try container.encode(subcategory, forKey: .subcategory)
        try container.encode(colors, forKey: .colors)
        try container.encodeIfPresent(sizes, forKey: .sizes)
        try container.encodeIfPresent(priceRange, forKey: .priceRange)
        try container.encodeIfPresent(occasionTags, forKey: .occasionTags)
        try container.encodeIfPresent(brand, forKey: .brand)
        try container.encodeIfPresent(imageURL, forKey: .imageURL)
        try container.encodeIfPresent(retailerID, forKey: .retailerIDSnake)
        try container.encode(retailer, forKey: .retailer)
        try container.encode(affiliateURL, forKey: .affiliateURL)
        try container.encodeIfPresent(countryCode, forKey: .countryCode)
        try container.encodeIfPresent(merchant, forKey: .merchant)
        try container.encodeIfPresent(merchantRegion, forKey: .merchantRegion)
        try container.encodeIfPresent(affiliateProvider, forKey: .affiliateProvider)
        try container.encodeIfPresent(isAffiliateEligible, forKey: .isAffiliateEligible)
        try container.encodeIfPresent(productURL, forKey: .productURL)
        try container.encodeIfPresent(fallbackURL, forKey: .fallbackURL)
        try container.encodeIfPresent(price, forKey: .price)
        try container.encodeIfPresent(salePrice, forKey: .salePrice)
        try container.encodeIfPresent(saleEndsAt, forKey: .saleEndsAt)
        try container.encodeIfPresent(currencyCode, forKey: .currencyCode)
        try container.encodeIfPresent(availableCountries, forKey: .availableCountries)
        try container.encodeIfPresent(availability, forKey: .availability)
        try container.encodeIfPresent(availableColors, forKey: .availableColors)
        try container.encodeIfPresent(customerRating, forKey: .customerRating)
        try container.encodeIfPresent(reviewCount, forKey: .reviewCount)
        try container.encodeIfPresent(estimatedShippingText, forKey: .estimatedShippingText)
        try container.encode(tags, forKey: .tags)
        try container.encodeIfPresent(genderPresentation, forKey: .genderPresentation)
    }

    static func == (lhs: AffiliateProduct, rhs: AffiliateProduct) -> Bool {
        lhs.id == rhs.id
            && lhs.name == rhs.name
            && lhs.category == rhs.category
            && lhs.subcategory == rhs.subcategory
            && lhs.colors == rhs.colors
            && lhs.sizes == rhs.sizes
            && lhs.priceRange == rhs.priceRange
            && lhs.occasionTags == rhs.occasionTags
            && lhs.brand == rhs.brand
            && lhs.imageURL == rhs.imageURL
            && lhs.retailer == rhs.retailer
            && lhs.affiliateURL == rhs.affiliateURL
            && lhs.countryCode == rhs.countryCode
            && lhs.merchant == rhs.merchant
            && lhs.merchantRegion == rhs.merchantRegion
            && lhs.affiliateProvider == rhs.affiliateProvider
            && lhs.isAffiliateEligible == rhs.isAffiliateEligible
            && lhs.productURL == rhs.productURL
            && lhs.fallbackURL == rhs.fallbackURL
            && lhs.price == rhs.price
            && lhs.salePrice == rhs.salePrice
            && lhs.saleEndsAt == rhs.saleEndsAt
            && lhs.currencyCode == rhs.currencyCode
            && lhs.availableCountries == rhs.availableCountries
            && lhs.availability == rhs.availability
            && lhs.availableColors == rhs.availableColors
            && lhs.customerRating == rhs.customerRating
            && lhs.reviewCount == rhs.reviewCount
            && lhs.estimatedShippingText == rhs.estimatedShippingText
            && lhs.tags == rhs.tags
            && lhs.genderPresentation == rhs.genderPresentation
    }

    static func normalizedRetailerID(_ value: String?) -> String? {
        let cleaned = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned?.isEmpty == false ? cleaned : nil
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

enum ShoppingProductImageFallbackReason: Equatable {
    case missing
    case loadFailure
}

struct ShoppingProductImageFallbackPresentation: Equatable {
    let systemImage: String
    let categoryLabel: String
    let identityText: String
    let statusText: String

    static func make(
        category: ProductCategory?,
        productName: String,
        retailerName: String,
        reason: ShoppingProductImageFallbackReason
    ) -> ShoppingProductImageFallbackPresentation {
        let product = productName.trimmingCharacters(in: .whitespacesAndNewlines)
        let retailer = retailerName.trimmingCharacters(in: .whitespacesAndNewlines)

        return ShoppingProductImageFallbackPresentation(
            systemImage: systemImage(for: category),
            categoryLabel: category?.displayName ?? "Style pick",
            identityText: !retailer.isEmpty ? retailer : (!product.isEmpty ? product : "StyleMatch pick"),
            statusText: reason == .missing ? "Product image coming soon" : "Image unavailable"
        )
    }

    static func accentOpacity(isDarkMode: Bool) -> Double {
        isDarkMode ? 0.26 : 0.14
    }

    private static func systemImage(for category: ProductCategory?) -> String {
        switch category {
        case .clothing: return "tshirt.fill"
        case .shoes: return "figure.walk"
        case .accessories: return "bag.fill"
        case .electronics: return "headphones"
        case .styleTools: return "sparkles"
        case nil: return "shippingbox.fill"
        }
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
