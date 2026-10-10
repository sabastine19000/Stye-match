import Foundation

enum StoreCoverageState: Equatable {
    case unavailable
    case loaded(countsByRetailerID: [String: Int], source: ProductCatalogSource)

    static func loaded(products: [AffiliateProduct], source: ProductCatalogSource) -> StoreCoverageState {
        .loaded(
            countsByRetailerID: Dictionary(
                grouping: products.compactMap { RetailerPreferencePolicy.canonicalID($0.retailerID) },
                by: { $0 }
            ).mapValues(\.count),
            source: source
        )
    }

    func productCount(for retailerID: String) -> Int? {
        guard case let .loaded(countsByRetailerID, _) = self else { return nil }
        guard let canonicalID = RetailerPreferencePolicy.canonicalID(retailerID) else { return 0 }
        return countsByRetailerID[canonicalID, default: 0]
    }
}
