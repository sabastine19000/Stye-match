import Foundation

struct ShoppingLocalStore {
    static let recentlyViewedBaseKey = "shoppingRecentlyViewedProductIDs"
    static let dismissedBaseKey = "shoppingDismissedProductIDs"
    static let savedFavoritesBaseKey = "shoppingSavedFavoriteProductIDs"
    static let wishlistBaseKey = "shoppingWishlistProductIDs"
    static let cartBaseKey = "shoppingCartProductIDs"
    static let shoppingCardsBaseKey = "shoppingCardProductIDs"
    static let saleNotificationsEnabledBaseKey = "shoppingSaleNotificationsEnabled"
    static let saleStateSnapshotsBaseKey = "shoppingSaleStateSnapshots"
    static let lastKnownSaleStateBaseKey = "shoppingLastKnownSaleState"
    static let notifiedSalePairsBaseKey = "shoppingNotifiedSalePairs"
    static let saleNotificationHistoryBaseKey = "shoppingSaleNotificationHistory"
    static let recentSaleEventsBaseKey = "shoppingRecentSaleEvents"
    static let viewedSaleEventIDsBaseKey = "shoppingViewedSaleEventIDs"
    static let affiliateDisclosureExpandedBaseKey = "shoppingAffiliateDisclosureExpanded"
    static let affiliateDisclosureSeenExpandedBaseKey = "shoppingAffiliateDisclosureSeenExpanded"

    let defaults: UserDefaults
    let userID: String

    init(defaults: UserDefaults = .standard, userID: String? = nil) {
        self.defaults = defaults
        self.userID = PersonalStylistStorage.normalizedUserID(userID ?? PersonalStylistStorage.activeUserID(defaults: defaults))
    }

    var recentlyViewedProductIDs: [String] {
        get { defaults.stringArray(forKey: key(Self.recentlyViewedBaseKey)) ?? [] }
        nonmutating set { defaults.set(Array(newValue.prefix(50)), forKey: key(Self.recentlyViewedBaseKey)) }
    }

    var dismissedProductIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: key(Self.dismissedBaseKey)) ?? []) }
        nonmutating set { defaults.set(Array(newValue), forKey: key(Self.dismissedBaseKey)) }
    }

    var savedFavorites: [String] {
        get { defaults.stringArray(forKey: key(Self.savedFavoritesBaseKey)) ?? [] }
        nonmutating set { defaults.set(Array(newValue.prefix(200)), forKey: key(Self.savedFavoritesBaseKey)) }
    }

    var wishlistProductIDs: [String] {
        get { defaults.stringArray(forKey: key(Self.wishlistBaseKey)) ?? [] }
        nonmutating set { defaults.set(Array(newValue.prefix(200)), forKey: key(Self.wishlistBaseKey)) }
    }

    var cartProductIDs: [String] {
        get { defaults.stringArray(forKey: key(Self.cartBaseKey)) ?? [] }
        nonmutating set { defaults.set(Array(newValue.prefix(100)), forKey: key(Self.cartBaseKey)) }
    }

    var shoppingCardProductIDs: [String] {
        get { defaults.stringArray(forKey: key(Self.shoppingCardsBaseKey)) ?? [] }
        nonmutating set { defaults.set(Array(newValue.prefix(200)), forKey: key(Self.shoppingCardsBaseKey)) }
    }

    var saleNotificationsEnabled: Bool {
        get {
            let scoped = key(Self.saleNotificationsEnabledBaseKey)
            guard defaults.object(forKey: scoped) != nil else { return FeatureFlags.saleNotificationsEnabled }
            return defaults.bool(forKey: scoped)
        }
        nonmutating set { defaults.set(newValue, forKey: key(Self.saleNotificationsEnabledBaseKey)) }
    }

    var affiliateDisclosureExpanded: Bool {
        get {
            let seenKey = key(Self.affiliateDisclosureSeenExpandedBaseKey)
            let expandedKey = key(Self.affiliateDisclosureExpandedBaseKey)
            guard defaults.object(forKey: seenKey) != nil else { return false }
            return defaults.bool(forKey: expandedKey)
        }
        nonmutating set {
            defaults.set(true, forKey: key(Self.affiliateDisclosureSeenExpandedBaseKey))
            defaults.set(newValue, forKey: key(Self.affiliateDisclosureExpandedBaseKey))
        }
    }

    var saleStateSnapshots: [String: ShoppingSaleStateSnapshot] {
        get {
            guard let data = defaults.data(forKey: key(Self.saleStateSnapshotsBaseKey)) else { return [:] }
            return (try? JSONDecoder().decode([String: ShoppingSaleStateSnapshot].self, from: data)) ?? [:]
        }
        nonmutating set {
            let data = try? JSONEncoder().encode(newValue)
            defaults.set(data, forKey: key(Self.saleStateSnapshotsBaseKey))
        }
    }

    var lastKnownSaleState: [String: SaleSnapshot] {
        get { decoded([String: SaleSnapshot].self, baseKey: Self.lastKnownSaleStateBaseKey) ?? [:] }
        nonmutating set { encode(newValue, baseKey: Self.lastKnownSaleStateBaseKey) }
    }

    var notifiedSalePairs: [String] {
        get { defaults.stringArray(forKey: key(Self.notifiedSalePairsBaseKey)) ?? [] }
        nonmutating set { defaults.set(Array(newValue.suffix(500)), forKey: key(Self.notifiedSalePairsBaseKey)) }
    }

    var saleNotificationHistory: [Date] {
        get { decoded([Date].self, baseKey: Self.saleNotificationHistoryBaseKey) ?? [] }
        nonmutating set { encode(newValue, baseKey: Self.saleNotificationHistoryBaseKey) }
    }

    var recentSaleEvents: [SaleEvent] {
        get { decoded([SaleEvent].self, baseKey: Self.recentSaleEventsBaseKey) ?? [] }
        nonmutating set { encode(Array(newValue.prefix(50)), baseKey: Self.recentSaleEventsBaseKey) }
    }

    var viewedSaleEventIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: key(Self.viewedSaleEventIDsBaseKey)) ?? []) }
        nonmutating set { defaults.set(Array(newValue), forKey: key(Self.viewedSaleEventIDsBaseKey)) }
    }

    func markViewed(_ productID: String) {
        let cleaned = productID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        recentlyViewedProductIDs = [cleaned] + recentlyViewedProductIDs.filter { $0 != cleaned }
    }

    func dismiss(_ productID: String) {
        let cleaned = productID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        var ids = dismissedProductIDs
        ids.insert(cleaned)
        dismissedProductIDs = ids
    }

    func toggleFavorite(_ productID: String) {
        let cleaned = productID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        if savedFavorites.contains(cleaned) {
            savedFavorites = savedFavorites.filter { $0 != cleaned }
        } else {
            savedFavorites = [cleaned] + savedFavorites.filter { $0 != cleaned }
        }
    }

    func toggleWishlist(_ productID: String) {
        toggle(productID, get: { wishlistProductIDs }, set: { wishlistProductIDs = $0 })
    }

    func toggleCart(_ productID: String) {
        toggle(productID, get: { cartProductIDs }, set: { cartProductIDs = $0 })
    }

    func toggleShoppingCard(_ productID: String) {
        toggle(productID, get: { shoppingCardProductIDs }, set: { shoppingCardProductIDs = $0 })
    }

    func saveSaleStateSnapshots(_ snapshots: [String: ShoppingSaleStateSnapshot]) {
        saleStateSnapshots = snapshots
    }

    func deleteAll() {
        defaults.removeObject(forKey: key(Self.recentlyViewedBaseKey))
        defaults.removeObject(forKey: key(Self.dismissedBaseKey))
        defaults.removeObject(forKey: key(Self.savedFavoritesBaseKey))
        defaults.removeObject(forKey: key(Self.wishlistBaseKey))
        defaults.removeObject(forKey: key(Self.cartBaseKey))
        defaults.removeObject(forKey: key(Self.shoppingCardsBaseKey))
        defaults.removeObject(forKey: key(Self.saleNotificationsEnabledBaseKey))
        defaults.removeObject(forKey: key(Self.saleStateSnapshotsBaseKey))
        defaults.removeObject(forKey: key(Self.lastKnownSaleStateBaseKey))
        defaults.removeObject(forKey: key(Self.notifiedSalePairsBaseKey))
        defaults.removeObject(forKey: key(Self.saleNotificationHistoryBaseKey))
        defaults.removeObject(forKey: key(Self.recentSaleEventsBaseKey))
        defaults.removeObject(forKey: key(Self.viewedSaleEventIDsBaseKey))
        defaults.removeObject(forKey: key(Self.affiliateDisclosureExpandedBaseKey))
        defaults.removeObject(forKey: key(Self.affiliateDisclosureSeenExpandedBaseKey))
    }

    static func deleteShoppingData(for userID: String, defaults: UserDefaults = .standard) {
        ShoppingLocalStore(defaults: defaults, userID: userID).deleteAll()
    }

    private func key(_ base: String) -> String {
        PersonalStylistStorage.scopedKey(base, userID: userID)
    }

    private func decoded<T: Decodable>(_ type: T.Type, baseKey: String) -> T? {
        guard let data = defaults.data(forKey: key(baseKey)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func encode<T: Encodable>(_ value: T, baseKey: String) {
        let data = try? JSONEncoder().encode(value)
        defaults.set(data, forKey: key(baseKey))
    }

    private func toggle(_ productID: String, get: () -> [String], set: ([String]) -> Void) {
        let cleaned = productID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        let existing = get()
        if existing.contains(cleaned) {
            set(existing.filter { $0 != cleaned })
        } else {
            set([cleaned] + existing.filter { $0 != cleaned })
        }
    }
}
