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
    let imageURL: URL
    let retailer: Retailer
    let affiliateURL: URL
    let price: Decimal?
    let salePrice: Decimal?
    let saleEndsAt: Date?
    let tags: [String]
    let genderPresentation: String?
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
    let liveSearchProxyBaseURL: URL?
    let allowedClientSideAPIKeyNames: [String]

    static let empty = ShoppingIntegrationConfig(
        liveSearchProxyBaseURL: nil,
        allowedClientSideAPIKeyNames: []
    )
}

enum AffiliateLinkBuilder {
    static let pendingApprovalTrackingID = "PENDING-APPROVAL"

    static func outboundURL(for product: AffiliateProduct) -> URL {
        let retailer = product.retailer
        guard retailer.trackingID != pendingApprovalTrackingID,
              !retailer.trackingID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !retailer.trackingParamName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              var components = URLComponents(url: product.affiliateURL, resolvingAgainstBaseURL: false) else {
            return product.affiliateURL
        }

        var queryItems = components.queryItems ?? []
        queryItems.removeAll { $0.name == retailer.trackingParamName }
        queryItems.append(URLQueryItem(name: retailer.trackingParamName, value: retailer.trackingID))
        components.queryItems = queryItems
        return components.url ?? product.affiliateURL
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
    let retailerName: String
    let soldAndShippedText: String
    let priceText: String
    let saleBadgeText: String?
    let originalPriceText: String?
    let footnote: String?
    let reasonText: String?
    let outboundURL: URL

    init(product: AffiliateProduct, reasonText: String? = nil, now: Date = Date()) {
        self.id = product.id
        self.name = product.name
        self.retailerName = product.retailer.name
        self.soldAndShippedText = "Sold and shipped by \(product.retailer.disclosureName)"
        self.reasonText = reasonText
        self.outboundURL = AffiliateLinkBuilder.outboundURL(for: product)

        if product.retailer.name.caseInsensitiveCompare("Amazon") == .orderedSame {
            self.priceText = "See price at Amazon"
            self.saleBadgeText = product.salePrice != nil && (product.saleEndsAt ?? .distantFuture) > now ? "Sale" : nil
            self.originalPriceText = nil
            self.footnote = nil
        } else if let salePrice = product.salePrice, (product.saleEndsAt ?? .distantFuture) > now {
            self.priceText = Self.currency(salePrice)
            self.saleBadgeText = "Sale"
            self.originalPriceText = product.price.map(Self.currency)
            self.footnote = "Price may vary - confirmed at checkout"
        } else if let price = product.price {
            self.priceText = Self.currency(price)
            self.saleBadgeText = nil
            self.originalPriceText = nil
            self.footnote = "Price may vary - confirmed at checkout"
        } else if let priceRange = product.priceRange {
            self.priceText = "\(Self.currency(priceRange.lowerBound))-\(Self.currency(priceRange.upperBound))"
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

    private static func currency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "en_US")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }
}
