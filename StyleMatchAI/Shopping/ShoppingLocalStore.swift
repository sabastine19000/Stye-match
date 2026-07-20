import Combine
import Foundation

final class ShoppingLocalStore: ObservableObject {
    static let recentlyViewedBaseKey = "shoppingRecentlyViewedProductIDs"
    static let dismissedBaseKey = "shoppingDismissedProductIDs"
    static let savedFavoritesBaseKey = "shoppingSavedFavoriteProductIDs"
    static let wishlistBaseKey = "shoppingWishlistProductIDs"
    static let cartBaseKey = "shoppingCartProductIDs"
    static let shoppingCardsBaseKey = "shoppingCardProductIDs"
    static let preferredRetailerIDsBaseKey = "shoppingPreferredRetailerIDs"
    static let saleAlertProductIDsBaseKey = "shoppingSaleAlertProductIDs"
    static let latestKnownPricesBaseKey = "shoppingLatestKnownPrices"
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

    @Published private var recentlyViewedStorage: [String]
    @Published private var dismissedStorage: Set<String>
    @Published private var savedFavoritesStorage: [String]
    @Published private var wishlistStorage: [String]
    @Published private var cartStorage: [String]
    @Published private var shoppingCardStorage: [String]
    @Published private var preferredRetailerIDStorage: [String]
    @Published private var saleAlertProductIDStorage: Set<String>
    @Published private var latestKnownPricesStorage: [String: Decimal]
    @Published private var saleNotificationsEnabledStorage: Bool
    @Published private var affiliateDisclosureExpandedStorage: Bool
    @Published private var saleStateSnapshotsStorage: [String: ShoppingSaleStateSnapshot]
    @Published private var lastKnownSaleStateStorage: [String: SaleSnapshot]
    @Published private var notifiedSalePairsStorage: [String]
    @Published private var saleNotificationHistoryStorage: [Date]
    @Published private var recentSaleEventsStorage: [SaleEvent]
    @Published private var viewedSaleEventIDStorage: Set<String>

    init(defaults: UserDefaults = .standard, userID: String? = nil, supportedStores: [SupportedStore]? = nil) {
        self.defaults = defaults
        let normalizedUserID = PersonalStylistStorage.normalizedUserID(userID ?? Self.defaultUserID(defaults: defaults))
        self.userID = normalizedUserID

        func scoped(_ base: String) -> String {
            PersonalStylistStorage.scopedKey(base, userID: normalizedUserID)
        }

        self.recentlyViewedStorage = Array((defaults.stringArray(forKey: scoped(Self.recentlyViewedBaseKey)) ?? []).prefix(50))
        self.dismissedStorage = Set(defaults.stringArray(forKey: scoped(Self.dismissedBaseKey)) ?? [])
        self.savedFavoritesStorage = Array((defaults.stringArray(forKey: scoped(Self.savedFavoritesBaseKey)) ?? []).prefix(200))
        self.wishlistStorage = Array((defaults.stringArray(forKey: scoped(Self.wishlistBaseKey)) ?? []).prefix(200))
        self.cartStorage = Array((defaults.stringArray(forKey: scoped(Self.cartBaseKey)) ?? []).prefix(100))
        self.shoppingCardStorage = Array((defaults.stringArray(forKey: scoped(Self.shoppingCardsBaseKey)) ?? []).prefix(200))
        let preferredRetailerKey = scoped(Self.preferredRetailerIDsBaseKey)
        let storedPreferredRetailerIDs = Self.storedPreferredRetailerIDs(
            defaults: defaults,
            primaryKey: preferredRetailerKey,
            normalizedUserID: normalizedUserID
        )
        if let supportedStores, !supportedStores.isEmpty {
            self.preferredRetailerIDStorage = RetailerPreferencePolicy.normalizedPreferredRetailerIDs(
                storedPreferredRetailerIDs,
                supportedStores: supportedStores
            )
        } else {
            self.preferredRetailerIDStorage = RetailerPreferencePolicy.normalizedCandidateRetailerIDs(storedPreferredRetailerIDs)
        }
        self.saleAlertProductIDStorage = Set(defaults.stringArray(forKey: scoped(Self.saleAlertProductIDsBaseKey)) ?? [])
        self.latestKnownPricesStorage = Self.decoded([String: Decimal].self, defaults: defaults, key: scoped(Self.latestKnownPricesBaseKey)) ?? [:]
        if defaults.object(forKey: scoped(Self.saleNotificationsEnabledBaseKey)) == nil {
            self.saleNotificationsEnabledStorage = FeatureFlags.saleNotificationsEnabled
        } else {
            self.saleNotificationsEnabledStorage = defaults.bool(forKey: scoped(Self.saleNotificationsEnabledBaseKey))
        }
        let seenDisclosure = defaults.object(forKey: scoped(Self.affiliateDisclosureSeenExpandedBaseKey)) != nil
        self.affiliateDisclosureExpandedStorage = seenDisclosure ? defaults.bool(forKey: scoped(Self.affiliateDisclosureExpandedBaseKey)) : false
        self.saleStateSnapshotsStorage = Self.decoded([String: ShoppingSaleStateSnapshot].self, defaults: defaults, key: scoped(Self.saleStateSnapshotsBaseKey)) ?? [:]
        self.lastKnownSaleStateStorage = Self.decoded([String: SaleSnapshot].self, defaults: defaults, key: scoped(Self.lastKnownSaleStateBaseKey)) ?? [:]
        self.notifiedSalePairsStorage = Array((defaults.stringArray(forKey: scoped(Self.notifiedSalePairsBaseKey)) ?? []).suffix(500))
        self.saleNotificationHistoryStorage = Self.decoded([Date].self, defaults: defaults, key: scoped(Self.saleNotificationHistoryBaseKey)) ?? []
        self.recentSaleEventsStorage = Array((Self.decoded([SaleEvent].self, defaults: defaults, key: scoped(Self.recentSaleEventsBaseKey)) ?? []).prefix(50))
        self.viewedSaleEventIDStorage = Set(defaults.stringArray(forKey: scoped(Self.viewedSaleEventIDsBaseKey)) ?? [])
        if let supportedStores, !supportedStores.isEmpty,
           preferredRetailerIDStorage != RetailerPreferencePolicy.normalizedCandidateRetailerIDs(storedPreferredRetailerIDs) {
            defaults.set(preferredRetailerIDStorage, forKey: preferredRetailerKey)
        }
        Self.debugLog(
            "init",
            defaults: defaults,
            userID: normalizedUserID,
            key: preferredRetailerKey,
            loadedIDs: storedPreferredRetailerIDs,
            normalizedIDs: preferredRetailerIDStorage,
            supportedStores: supportedStores
        )
    }

    var recentlyViewedProductIDs: [String] {
        get { recentlyViewedStorage }
        set {
            recentlyViewedStorage = Array(newValue.prefix(50))
            defaults.set(recentlyViewedStorage, forKey: key(Self.recentlyViewedBaseKey))
        }
    }

    var dismissedProductIDs: Set<String> {
        get { dismissedStorage }
        set {
            dismissedStorage = newValue
            defaults.set(Array(newValue), forKey: key(Self.dismissedBaseKey))
        }
    }

    var savedFavorites: [String] {
        get { savedFavoritesStorage }
        set {
            savedFavoritesStorage = Array(newValue.prefix(200))
            defaults.set(savedFavoritesStorage, forKey: key(Self.savedFavoritesBaseKey))
        }
    }

    var wishlistProductIDs: [String] {
        get { wishlistStorage }
        set {
            wishlistStorage = Array(newValue.prefix(200))
            defaults.set(wishlistStorage, forKey: key(Self.wishlistBaseKey))
        }
    }

    var cartProductIDs: [String] {
        get { cartStorage }
        set {
            cartStorage = Array(newValue.prefix(100))
            defaults.set(cartStorage, forKey: key(Self.cartBaseKey))
        }
    }

    var shoppingCardProductIDs: [String] {
        get { shoppingCardStorage }
        set {
            shoppingCardStorage = Array(newValue.prefix(200))
            defaults.set(shoppingCardStorage, forKey: key(Self.shoppingCardsBaseKey))
        }
    }

    var preferredRetailerIDs: [String] {
        get { preferredRetailerIDStorage }
        set {
            preferredRetailerIDStorage = RetailerPreferencePolicy.normalizedCandidateRetailerIDs(newValue)
            defaults.set(preferredRetailerIDStorage, forKey: key(Self.preferredRetailerIDsBaseKey))
        }
    }

    func setPreferredRetailerIDs(_ ids: [String], supportedStores: [SupportedStore]) {
        preferredRetailerIDStorage = RetailerPreferencePolicy.normalizedPreferredRetailerIDs(ids, supportedStores: supportedStores)
        defaults.set(preferredRetailerIDStorage, forKey: key(Self.preferredRetailerIDsBaseKey))
        Self.debugLog(
            "setPreferredRetailerIDs",
            defaults: defaults,
            userID: userID,
            key: key(Self.preferredRetailerIDsBaseKey),
            loadedIDs: ids,
            normalizedIDs: preferredRetailerIDStorage,
            supportedStores: supportedStores
        )
    }

    @discardableResult
    func normalizePreferredRetailerIDs(
        supportedStores: [SupportedStore],
        registryIsLoaded: Bool = true
    ) -> [String] {
        let candidates = RetailerPreferencePolicy.normalizedCandidateRetailerIDs(preferredRetailerIDStorage)
        guard registryIsLoaded, !supportedStores.isEmpty else {
            Self.debugLog(
                "normalizePreferredRetailerIDs",
                defaults: defaults,
                userID: userID,
                key: key(Self.preferredRetailerIDsBaseKey),
                loadedIDs: candidates,
                normalizedIDs: candidates,
                supportedStores: supportedStores,
                registryIsLoaded: registryIsLoaded,
                persistenceAction: "skipped"
            )
            return candidates
        }
        let normalized = RetailerPreferencePolicy.normalizedPreferredRetailerIDs(
            candidates,
            supportedStores: supportedStores
        )
        let persistenceAction: String
        if normalized != preferredRetailerIDStorage {
            preferredRetailerIDStorage = normalized
            defaults.set(preferredRetailerIDStorage, forKey: key(Self.preferredRetailerIDsBaseKey))
            persistenceAction = "written"
        } else {
            persistenceAction = "skipped"
        }
        Self.debugLog(
            "normalizePreferredRetailerIDs",
            defaults: defaults,
            userID: userID,
            key: key(Self.preferredRetailerIDsBaseKey),
            loadedIDs: preferredRetailerIDStorage,
            normalizedIDs: normalized,
            supportedStores: supportedStores,
            registryIsLoaded: registryIsLoaded,
            persistenceAction: persistenceAction
        )
        return normalized
    }

    func preferredRetailerIDs(
        supportedStores: [SupportedStore],
        registryIsLoaded: Bool = true
    ) -> [String] {
        normalizePreferredRetailerIDs(
            supportedStores: supportedStores,
            registryIsLoaded: registryIsLoaded
        )
    }

    var saleAlertProductIDs: Set<String> {
        get { saleAlertProductIDStorage }
        set {
            saleAlertProductIDStorage = newValue
            defaults.set(Array(newValue), forKey: key(Self.saleAlertProductIDsBaseKey))
        }
    }

    var latestKnownPrices: [String: Decimal] {
        get { latestKnownPricesStorage }
        set {
            latestKnownPricesStorage = newValue
            encode(newValue, baseKey: Self.latestKnownPricesBaseKey)
        }
    }

    var saleNotificationsEnabled: Bool {
        get { saleNotificationsEnabledStorage }
        set {
            saleNotificationsEnabledStorage = newValue
            defaults.set(newValue, forKey: key(Self.saleNotificationsEnabledBaseKey))
        }
    }

    var affiliateDisclosureExpanded: Bool {
        get { affiliateDisclosureExpandedStorage }
        set {
            affiliateDisclosureExpandedStorage = newValue
            defaults.set(true, forKey: key(Self.affiliateDisclosureSeenExpandedBaseKey))
            defaults.set(newValue, forKey: key(Self.affiliateDisclosureExpandedBaseKey))
        }
    }

    var saleStateSnapshots: [String: ShoppingSaleStateSnapshot] {
        get { saleStateSnapshotsStorage }
        set {
            saleStateSnapshotsStorage = newValue
            encode(newValue, baseKey: Self.saleStateSnapshotsBaseKey)
        }
    }

    var lastKnownSaleState: [String: SaleSnapshot] {
        get { lastKnownSaleStateStorage }
        set {
            lastKnownSaleStateStorage = newValue
            encode(newValue, baseKey: Self.lastKnownSaleStateBaseKey)
        }
    }

    var notifiedSalePairs: [String] {
        get { notifiedSalePairsStorage }
        set {
            notifiedSalePairsStorage = Array(newValue.suffix(500))
            defaults.set(notifiedSalePairsStorage, forKey: key(Self.notifiedSalePairsBaseKey))
        }
    }

    var saleNotificationHistory: [Date] {
        get { saleNotificationHistoryStorage }
        set {
            saleNotificationHistoryStorage = newValue
            encode(newValue, baseKey: Self.saleNotificationHistoryBaseKey)
        }
    }

    var recentSaleEvents: [SaleEvent] {
        get { recentSaleEventsStorage }
        set {
            recentSaleEventsStorage = Array(newValue.prefix(50))
            encode(recentSaleEventsStorage, baseKey: Self.recentSaleEventsBaseKey)
        }
    }

    var viewedSaleEventIDs: Set<String> {
        get { viewedSaleEventIDStorage }
        set {
            viewedSaleEventIDStorage = newValue
            defaults.set(Array(newValue), forKey: key(Self.viewedSaleEventIDsBaseKey))
        }
    }

    func markViewed(_ productID: String) {
        let cleaned = clean(productID)
        guard !cleaned.isEmpty else { return }
        recentlyViewedProductIDs = [cleaned] + recentlyViewedProductIDs.filter { $0 != cleaned }
    }

    func dismiss(_ productID: String) {
        let cleaned = clean(productID)
        guard !cleaned.isEmpty else { return }
        dismissedProductIDs.insert(cleaned)
    }

    func toggleFavorite(_ productID: String) {
        toggle(productID, get: { savedFavorites }, set: { savedFavorites = $0 })
    }

    func toggleFavorite(productID: String) {
        toggleFavorite(productID)
    }

    func toggleWishlist(_ productID: String) {
        toggle(productID, get: { wishlistProductIDs }, set: { wishlistProductIDs = $0 })
    }

    func toggleWishlist(productID: String) {
        toggleWishlist(productID)
    }

    func toggleCart(_ productID: String) {
        toggle(productID, get: { cartProductIDs }, set: { cartProductIDs = $0 })
    }

    func toggleShoppingCard(_ productID: String) {
        toggle(productID, get: { shoppingCardProductIDs }, set: { shoppingCardProductIDs = $0 })
    }

    func setSaleAlert(enabled: Bool, for productID: String) {
        let cleaned = clean(productID)
        guard !cleaned.isEmpty else { return }
        if enabled {
            saleAlertProductIDs.insert(cleaned)
        } else {
            saleAlertProductIDs.remove(cleaned)
        }
    }

    func updateLatestKnownPrice(_ price: Decimal?, for productID: String) {
        let cleaned = clean(productID)
        guard !cleaned.isEmpty else { return }
        guard let price, price > 0 else {
            latestKnownPrices.removeValue(forKey: cleaned)
            return
        }
        latestKnownPrices[cleaned] = price
    }

    func removeProductState(productID: String) {
        let cleaned = clean(productID)
        guard !cleaned.isEmpty else { return }
        savedFavorites.removeAll { $0 == cleaned }
        wishlistProductIDs.removeAll { $0 == cleaned }
        cartProductIDs.removeAll { $0 == cleaned }
        shoppingCardProductIDs.removeAll { $0 == cleaned }
        saleAlertProductIDs.remove(cleaned)
        latestKnownPrices.removeValue(forKey: cleaned)
        dismissedProductIDs.remove(cleaned)
        recentlyViewedProductIDs.removeAll { $0 == cleaned }
        saleStateSnapshots.removeValue(forKey: cleaned)
        lastKnownSaleState.removeValue(forKey: cleaned)
        viewedSaleEventIDs.remove(cleaned)
    }

    func saveSaleStateSnapshots(_ snapshots: [String: ShoppingSaleStateSnapshot]) {
        saleStateSnapshots = snapshots
    }

    func deleteAll() {
        for baseKey in Self.allPersistedBaseKeys {
            defaults.removeObject(forKey: key(baseKey))
        }
        Self.debugLog(
            "deleteAll",
            defaults: defaults,
            userID: userID,
            key: key(Self.preferredRetailerIDsBaseKey),
            loadedIDs: preferredRetailerIDStorage,
            normalizedIDs: [],
            supportedStores: nil
        )
        recentlyViewedStorage = []
        dismissedStorage = []
        savedFavoritesStorage = []
        wishlistStorage = []
        cartStorage = []
        shoppingCardStorage = []
        preferredRetailerIDStorage = []
        saleAlertProductIDStorage = []
        latestKnownPricesStorage = [:]
        saleNotificationsEnabledStorage = FeatureFlags.saleNotificationsEnabled
        affiliateDisclosureExpandedStorage = false
        saleStateSnapshotsStorage = [:]
        lastKnownSaleStateStorage = [:]
        notifiedSalePairsStorage = []
        saleNotificationHistoryStorage = []
        recentSaleEventsStorage = []
        viewedSaleEventIDStorage = []
    }

    static func deleteShoppingData(for userID: String, defaults: UserDefaults = .standard) {
        ShoppingLocalStore(defaults: defaults, userID: userID).deleteAll()
    }

    private static var allPersistedBaseKeys: [String] {
        [
            recentlyViewedBaseKey,
            dismissedBaseKey,
            savedFavoritesBaseKey,
            wishlistBaseKey,
            cartBaseKey,
            shoppingCardsBaseKey,
            preferredRetailerIDsBaseKey,
            saleAlertProductIDsBaseKey,
            latestKnownPricesBaseKey,
            saleNotificationsEnabledBaseKey,
            saleStateSnapshotsBaseKey,
            lastKnownSaleStateBaseKey,
            notifiedSalePairsBaseKey,
            saleNotificationHistoryBaseKey,
            recentSaleEventsBaseKey,
            viewedSaleEventIDsBaseKey,
            affiliateDisclosureExpandedBaseKey,
            affiliateDisclosureSeenExpandedBaseKey
        ]
    }

    private func key(_ base: String) -> String {
        PersonalStylistStorage.scopedKey(base, userID: userID)
    }

    private static func defaultUserID(defaults: UserDefaults) -> String {
        AccountScopedStorage.activePresentationUserID(defaults: defaults)
    }

    private static func storedPreferredRetailerIDs(
        defaults: UserDefaults,
        primaryKey: String,
        normalizedUserID: String
    ) -> [String] {
        if let stored = defaults.stringArray(forKey: primaryKey) {
            return stored
        }

        let legacyUserID = PersonalStylistStorage.activeUserID(defaults: defaults)
        let legacyKey = PersonalStylistStorage.scopedKey(Self.preferredRetailerIDsBaseKey, userID: legacyUserID)
        guard PersonalStylistStorage.normalizedUserID(legacyUserID) != normalizedUserID,
              let legacy = defaults.stringArray(forKey: legacyKey),
              !legacy.isEmpty else {
            return []
        }

        defaults.set(legacy, forKey: primaryKey)
        #if DEBUG
        print("[StyleMatch My Stores Storage] event=legacy_migration from_key=\(redactedKey(legacyKey, userID: legacyUserID)) to_key=\(redactedKey(primaryKey, userID: normalizedUserID)) migrated_count=\(legacy.count)")
        #endif
        return legacy
    }

    private static func debugLog(
        _ event: String,
        defaults: UserDefaults,
        userID: String,
        key: String,
        loadedIDs: [String],
        normalizedIDs: [String],
        supportedStores: [SupportedStore]?,
        registryIsLoaded: Bool? = nil,
        persistenceAction: String? = nil
    ) {
        #if DEBUG
        let supportedIDs = supportedStores?.map(\.id).joined(separator: ",") ?? "not-provided"
        let activeMode = defaults.string(forKey: "customerAccountMode") ?? "unset"
        let activeEnvironment = AccountScopedStorage.activeEnvironment(defaults: defaults).rawValue
        let readiness = registryIsLoaded.map(String.init) ?? "not-provided"
        let persistence = persistenceAction ?? "not-provided"
        print("[StyleMatch My Stores Storage] event=\(event) namespace_present=\(!userID.isEmpty) key=\(redactedKey(key, userID: userID)) registry_ready=\(readiness) candidate_ids=\(loadedIDs.joined(separator: ",")) normalized_ids=\(normalizedIDs.joined(separator: ",")) persistence=\(persistence) supported_ids=\(supportedIDs) account_mode=\(activeMode) account_environment=\(activeEnvironment)")
        #endif
    }

    private static func redactedKey(_ key: String, userID: String) -> String {
        key.replacingOccurrences(of: PersonalStylistStorage.normalizedUserID(userID), with: "<user>")
    }

    private func encode<T: Encodable>(_ value: T, baseKey: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key(baseKey))
    }

    private static func decoded<T: Decodable>(_ type: T.Type, defaults: UserDefaults, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func toggle(_ productID: String, get: () -> [String], set: ([String]) -> Void) {
        let cleaned = clean(productID)
        guard !cleaned.isEmpty else { return }
        let existing = get()
        if existing.contains(cleaned) {
            set(existing.filter { $0 != cleaned })
        } else {
            set([cleaned] + existing.filter { $0 != cleaned })
        }
    }

    private func clean(_ productID: String) -> String {
        productID.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum ShoppingStoreScope: String, CaseIterable, Identifiable {
    case myStores
    case allStores

    var id: String { rawValue }

    var title: String {
        switch self {
        case .myStores: return "My Stores"
        case .allStores: return "All Stores"
        }
    }
}

struct RetailerPreferenceResult: Equatable {
    let products: [AffiliateProduct]
    let usedFallback: Bool
    let requestedRetailerIDs: [String]
}

enum RetailerIntegrationStatus: String, Equatable {
    case integratedCatalog
    case directAccessOnly
    case unavailable
}

struct RetailerAvailability: Identifiable, Equatable {
    let retailer: SupportedStore
    let productCount: Int?
    let integrationStatus: RetailerIntegrationStatus

    var id: String { retailer.id }

    var coverageLabel: String {
        guard let productCount else { return "Availability unknown" }
        if productCount == 1 { return "1 product" }
        if productCount > 1 { return "\(productCount) products" }
        return "No products available yet"
    }
}

enum RetailerDirectoryPolicy {
    static func availabilities(
        supportedStores: [SupportedStore],
        coverage: StoreCoverageState,
        retailerIDs: [String]? = nil,
        query: String = ""
    ) -> [RetailerAvailability] {
        let requestedIDs = retailerIDs.map { Set($0.compactMap(RetailerPreferencePolicy.canonicalID(_:))) }
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return supportedStores
            .filter(\.isEnabled)
            .filter { store in
                guard let requestedIDs else { return true }
                return requestedIDs.contains(store.id)
            }
            .filter { store in
                guard !normalizedQuery.isEmpty else { return true }
                let searchable = ([store.id, store.name] + store.domains).joined(separator: " ").lowercased()
                return searchable.contains(normalizedQuery)
            }
            .map { store in
                let productCount = coverage.productCount(for: store.id)
                let status: RetailerIntegrationStatus
                if (productCount ?? 0) > 0 {
                    status = .integratedCatalog
                } else if store.directAccessURL != nil {
                    status = .directAccessOnly
                } else {
                    status = .unavailable
                }
                return RetailerAvailability(
                    retailer: store,
                    productCount: productCount,
                    integrationStatus: status
                )
            }
            .sorted { lhs, rhs in
                let lhsCount = lhs.productCount ?? 0
                let rhsCount = rhs.productCount ?? 0
                if lhsCount != rhsCount { return lhsCount > rhsCount }
                return lhs.retailer.name.localizedCaseInsensitiveCompare(rhs.retailer.name) == .orderedAscending
            }
    }
}

enum RetailerPreferencePolicy {
    static let maximumPreferredRetailerIDs = 32
    static let fallbackCopy = "No matching products are currently available from your selected stores. Showing recommendations from all approved retailers until more inventory becomes available."

    static func fallbackCopy(selectedStoreNames: [String]) -> String {
        let normalizedNames = selectedStoreNames
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .removingDuplicates()
        guard !normalizedNames.isEmpty else { return fallbackCopy }
        return "\(fallbackCopy) Selected stores: \(normalizedNames.joined(separator: ", "))."
    }

    static func normalizedCandidateRetailerIDs(_ ids: [String], limit: Int = maximumPreferredRetailerIDs) -> [String] {
        Array(Set(ids.compactMap { canonicalID($0) }).sorted().prefix(limit))
    }

    static func normalizedPreferredRetailerIDs(
        _ ids: [String],
        supportedStores: [SupportedStore],
        limit: Int = maximumPreferredRetailerIDs
    ) -> [String] {
        let requested = Set(ids.compactMap(canonicalID(_:)))
        guard !requested.isEmpty else { return [] }
        return Array(
            supportedStores
                .filter(\.isEnabled)
                .compactMap { canonicalID($0.id) }
                .filter { requested.contains($0) }
                .removingDuplicates()
                .prefix(limit)
        )
    }

    static func apply(
        products: [AffiliateProduct],
        preferredRetailerIDs: [String],
        supportedStores: [SupportedStore]
    ) -> RetailerPreferenceResult {
        let requestedIDs = normalizedPreferredRetailerIDs(
            preferredRetailerIDs,
            supportedStores: supportedStores
        )
        guard !requestedIDs.isEmpty else {
            return RetailerPreferenceResult(products: products, usedFallback: false, requestedRetailerIDs: [])
        }

        let requestedSet = Set(requestedIDs)
        let matched = products.filter { product in
            guard let retailerID = canonicalID(product.retailerID) else { return false }
            return requestedSet.contains(retailerID)
        }

        if matched.isEmpty {
            return RetailerPreferenceResult(products: products, usedFallback: !products.isEmpty, requestedRetailerIDs: requestedIDs)
        }

        return RetailerPreferenceResult(products: matched, usedFallback: false, requestedRetailerIDs: requestedIDs)
    }

    static func canonicalID(_ id: String?) -> String? {
        guard let id else { return nil }
        let cleaned = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return cleaned.isEmpty ? nil : cleaned
    }
}

private extension Sequence where Element: Hashable {
    func removingDuplicates() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

struct ShoppingSwipeDeckState: Equatable {
    let productIDs: [String]
    private(set) var currentIndex: Int

    init(productIDs: [String], currentIndex: Int = 0) {
        self.productIDs = productIDs
        self.currentIndex = min(max(0, currentIndex), productIDs.count)
    }

    var isEmpty: Bool {
        productIDs.isEmpty
    }

    var currentProductID: String? {
        guard currentIndex < productIDs.count else {
            return nil
        }
        return productIDs[currentIndex]
    }

    mutating func swipeRight(using store: ShoppingLocalStore) {
        guard let productID = currentProductID else {
            return
        }
        if !store.savedFavorites.contains(productID) {
            store.toggleFavorite(productID)
        }
        advance()
    }

    mutating func swipeLeft() {
        advance()
    }

    private mutating func advance() {
        currentIndex = min(currentIndex + 1, productIDs.count)
    }
}

struct ShoppingPriceDropEvent: Equatable, Identifiable {
    let id: String
    let productID: String
    let previousPrice: Decimal
    let currentPrice: Decimal
    let detectedAt: Date
}

protocol ShoppingNotificationScheduling {
    func schedule(_ event: ShoppingPriceDropEvent) async
}

struct NoopShoppingNotificationScheduler: ShoppingNotificationScheduling {
    func schedule(_ event: ShoppingPriceDropEvent) async {}
}

struct ShoppingPriceDropEvaluator {
    let now: () -> Date

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    func evaluate(catalog: [AffiliateProduct], store: ShoppingLocalStore) -> [ShoppingPriceDropEvent] {
        guard store.saleNotificationsEnabled else { return [] }
        let watchedIDs = store.saleAlertProductIDs
        guard !watchedIDs.isEmpty else { return [] }

        let currentDate = now()
        var events: [ShoppingPriceDropEvent] = []
        var latestPrices = store.latestKnownPrices
        var notifiedPairs = Set(store.notifiedSalePairs)

        for product in catalog where watchedIDs.contains(product.id) {
            guard let currentPrice = comparablePrice(for: product), currentPrice > 0 else { continue }
            defer {
                latestPrices[product.id] = currentPrice
            }

            guard let previousPrice = latestPrices[product.id],
                  currentPrice < previousPrice else {
                continue
            }

            let pair = notifiedPair(productID: product.id, price: currentPrice)
            guard !notifiedPairs.contains(pair) else { continue }
            notifiedPairs.insert(pair)
            events.append(
                ShoppingPriceDropEvent(
                    id: pair,
                    productID: product.id,
                    previousPrice: previousPrice,
                    currentPrice: currentPrice,
                    detectedAt: currentDate
                )
            )
        }

        store.latestKnownPrices = latestPrices
        store.notifiedSalePairs = Array(notifiedPairs).sorted()
        return events
    }

    private func comparablePrice(for product: AffiliateProduct) -> Decimal? {
        if let salePrice = product.salePrice, salePrice > 0 {
            return salePrice
        }
        if let price = product.price, price > 0 {
            return price
        }
        return nil
    }

    private func notifiedPair(productID: String, price: Decimal) -> String {
        "\(productID)|\(price)"
    }
}
