import Foundation

/// A request-scoped shopping intent. This type is deliberately local-only: it
/// is neither Codable nor connected to saved retailer preferences.
enum ShoppingTierPreference: Equatable {
    case designerLuxury
    case luxuryMultiBrand
    case athleticStreetwear
    case premium
    case value
    case underBudget
    case similarForLess
    case unconstrained
}

enum RetailerTierEligibility: Equatable {
    case eligible
    case noEligibleRetailers
}

enum ShoppingRecommendationLabel: Hashable {
    case bestStyleMatch
    case premiumChoice
    case designerUpgrade
    case bestVersatility
    case noPurchaseNeeded
    case bestValueUnavailable
    case budgetAlternativeUnavailable
}

/// Local, deterministic directory policy. It has no network, persistence,
/// catalog-loading, link-building, or AI transport responsibility.
struct RetailerCatalogRegistry: Equatable {
    private let storesByCanonicalID: [String: SupportedStore]

    init(stores: [SupportedStore]) {
        var indexed: [String: SupportedStore] = [:]
        for store in stores {
            guard let id = Self.canonicalRetailerID(store.id), indexed[id] == nil else { continue }
            indexed[id] = store
        }
        self.storesByCanonicalID = indexed
    }

    func store(retailerID: String?) -> SupportedStore? {
        guard let id = Self.canonicalRetailerID(retailerID) else { return nil }
        return storesByCanonicalID[id]
    }

    func tier(retailerID: String?) -> RetailerTier? {
        store(retailerID: retailerID)?.tier
    }

    func linkCapability(retailerID: String?) -> RetailerLinkCapability {
        store(retailerID: retailerID)?.linkCapability ?? .unavailable
    }

    func commerceDataCapability(retailerID: String?) -> RetailerCommerceDataCapability {
        store(retailerID: retailerID)?.commerceDataCapability ?? .unavailable
    }

    func filter(
        products: [AffiliateProduct],
        for preference: ShoppingTierPreference
    ) -> RetailerTierFilterResult {
        let eligibleProducts = products.filter { product in
            isEligible(retailerID: product.retailerID, for: preference)
        }
        return RetailerTierFilterResult(
            products: eligibleProducts,
            eligibility: eligibleProducts.isEmpty && requiresExplicitTier(preference)
                ? .noEligibleRetailers
                : .eligible
        )
    }

    func isEligible(retailerID: String?, for preference: ShoppingTierPreference) -> Bool {
        guard let tier = tier(retailerID: retailerID) else {
            return !requiresExplicitTier(preference)
        }
        switch preference {
        case .designerLuxury:
            return tier == .designerLuxury
        case .luxuryMultiBrand:
            return tier == .luxuryMultiBrand
        case .athleticStreetwear:
            return tier == .athleticStreetwear
        case .premium:
            return [.designerLuxury, .luxuryMultiBrand, .premiumMainstream].contains(tier)
        case .value:
            return tier == .everydayValue
        case .underBudget, .similarForLess, .unconstrained:
            return true
        }
    }

    /// Affiliate/link capability intentionally does not participate here.
    func eligibleLabels(
        retailerID: String?,
        supportsVersatility: Bool,
        noPurchaseNeeded: Bool = false
    ) -> Set<ShoppingRecommendationLabel> {
        if noPurchaseNeeded {
            return [.noPurchaseNeeded]
        }

        var labels: Set<ShoppingRecommendationLabel> = [.bestStyleMatch]
        switch tier(retailerID: retailerID) {
        case .designerLuxury:
            labels.insert(.premiumChoice)
            labels.insert(.designerUpgrade)
        case .luxuryMultiBrand, .premiumMainstream:
            labels.insert(.premiumChoice)
        case .athleticStreetwear, .everydayValue, .none:
            break
        }
        if supportsVersatility {
            labels.insert(.bestVersatility)
        }

        // Static directory data is not a current-price or sale authority.
        labels.insert(.bestValueUnavailable)
        labels.insert(.budgetAlternativeUnavailable)
        return labels
    }

    static func canonicalRetailerID(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    private func requiresExplicitTier(_ preference: ShoppingTierPreference) -> Bool {
        switch preference {
        case .designerLuxury, .luxuryMultiBrand, .athleticStreetwear, .premium, .value:
            return true
        case .underBudget, .similarForLess, .unconstrained:
            return false
        }
    }
}

struct RetailerTierFilterResult: Equatable {
    let products: [AffiliateProduct]
    let eligibility: RetailerTierEligibility
}
