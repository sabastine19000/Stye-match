import Foundation
#if canImport(BackgroundTasks) && os(iOS)
import BackgroundTasks
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(UserNotifications)
import UserNotifications
#endif

struct SaleSnapshot: Codable, Equatable {
    let salePrice: Decimal?
    let saleEndsAt: Date?
    let timestamp: Date
}

enum SaleEventReason: String, Codable, Equatable {
    case directFavorite
    case similarToFavorite
}

struct SaleEvent: Identifiable, Codable, Equatable {
    let id: String
    let productID: String
    let productName: String
    let retailerName: String
    let subcategory: String
    let salePrice: Decimal
    let originalPrice: Decimal?
    let saleEndsAt: Date?
    let reason: SaleEventReason
    let occurredAt: Date
    var shouldNotify: Bool
    var scheduledDeliveryDate: Date?

    var isDirectFavorite: Bool {
        reason == .directFavorite
    }
}

struct SaleNotificationRequest: Equatable {
    let identifier: String
    let title: String
    let body: String
    let productID: String
    let deliveryDate: Date
}

protocol SaleNotificationScheduling {
    func requestAuthorization() async -> Bool
    func schedule(_ request: SaleNotificationRequest) async
}

struct SaleWatcherRouteStore {
    static let pendingProductIDKey = "shoppingPendingSaleProductID"
    static let didReceiveProductRoute = Notification.Name("StyleMatchSaleWatcherDidReceiveProductRoute")

    static func route(to productID: String, defaults: UserDefaults = .standard) {
        defaults.set(productID, forKey: pendingProductIDKey)
        NotificationCenter.default.post(name: didReceiveProductRoute, object: productID)
    }

    static func consumePendingProductID(defaults: UserDefaults = .standard) -> String? {
        let value = defaults.string(forKey: pendingProductIDKey)
        defaults.removeObject(forKey: pendingProductIDKey)
        return value
    }
}

#if canImport(UserNotifications)
struct LocalSaleNotificationScheduler: SaleNotificationScheduling {
    let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func requestAuthorization() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        @unknown default:
            return false
        }
    }

    func schedule(_ request: SaleNotificationRequest) async {
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        content.sound = .default
        content.userInfo = [
            "stylematchProductID": request.productID,
            "stylematchSaleEventID": request.identifier
        ]

        let interval = max(1, request.deliveryDate.timeIntervalSinceNow)
        let notificationRequest = UNNotificationRequest(
            identifier: request.identifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        )
        try? await center.add(notificationRequest)
    }
}
#endif

struct SaleWatcher {
    static let backgroundRefreshIdentifier = "com.stylematch.salewatcher.refresh"
    static let maxNotificationsPerDay = 2
    static let maxNotificationsPerWeek = 5

    let catalogProvider: ProductCatalogProvider
    let localStore: ShoppingLocalStore
    let notificationScheduler: SaleNotificationScheduling?
    let calendar: Calendar
    let now: () -> Date

    init(
        catalogProvider: ProductCatalogProvider? = nil,
        localStore: ShoppingLocalStore = ShoppingLocalStore(),
        notificationScheduler: SaleNotificationScheduling? = {
            #if canImport(UserNotifications)
            return LocalSaleNotificationScheduler()
            #else
            return nil
            #endif
        }(),
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.catalogProvider = catalogProvider ?? Self.activeCatalogProvider()
        self.localStore = localStore
        self.notificationScheduler = notificationScheduler
        self.calendar = calendar
        self.now = now
    }

    func checkForNewSales() async -> [SaleEvent] {
        let currentDate = now()
        let catalog: [AffiliateProduct]
        do {
            catalog = try await catalogProvider.products()
        } catch {
            #if DEBUG
            print("[StyleMatch SaleWatcher] Catalog refresh failed: \(error.localizedDescription)")
            #endif
            return []
        }

        let events = process(catalog: catalog, now: currentDate)
        await scheduleNotifications(for: events.filter(\.shouldNotify))
        return events
    }

    func process(catalog: [AffiliateProduct], now currentDate: Date) -> [SaleEvent] {
        let favoriteIDs = Set(localStore.savedFavorites)
        let favoriteProducts = catalog.filter { favoriteIDs.contains($0.id) }
        let watchedProducts = watchProducts(catalog: catalog, favoriteProducts: favoriteProducts)
        let oldSnapshots = localStore.lastKnownSaleState
        let oldPairs = localStore.notifiedSalePairs
        let oldHistory = localStore.saleNotificationHistory

        var newSnapshots = oldSnapshots
        watchedProducts.forEach { product in
            newSnapshots[product.id] = SaleSnapshot(
                salePrice: activeSalePrice(for: product, now: currentDate),
                saleEndsAt: product.saleEndsAt,
                timestamp: currentDate
            )
        }

        var candidateEvents = watchedProducts.compactMap { product -> SaleEvent? in
            guard let salePrice = activeSalePrice(for: product, now: currentDate) else { return nil }
            let pair = notifiedPair(productID: product.id, salePrice: salePrice)
            guard !oldPairs.contains(pair),
                  let event = saleEvent(
                    for: product,
                    salePrice: salePrice,
                    favoriteIDs: favoriteIDs,
                    previous: oldSnapshots[product.id],
                    now: currentDate
                  ) else {
                return nil
            }
            return event
        }

        candidateEvents.sort { lhs, rhs in
            if lhs.isDirectFavorite != rhs.isDirectFavorite {
                return lhs.isDirectFavorite
            }
            return lhs.productName < rhs.productName
        }

        var history = oldHistory.filter { isWithinLastSevenDays($0, now: currentDate) }
        var notifiedPairs = oldPairs
        let dayCount = history.filter { calendar.isDate($0, inSameDayAs: currentDate) }.count
        let weekCount = history.count
        var remainingDaySlots = max(0, Self.maxNotificationsPerDay - dayCount)
        var remainingWeekSlots = max(0, Self.maxNotificationsPerWeek - weekCount)

        let cappedEvents = candidateEvents.map { event -> SaleEvent in
            var updated = event
            let pair = notifiedPair(productID: event.productID, salePrice: event.salePrice)
            let canNotify = localStore.saleNotificationsEnabled && remainingDaySlots > 0 && remainingWeekSlots > 0
            updated.shouldNotify = canNotify
            updated.scheduledDeliveryDate = canNotify ? deliveryDate(for: currentDate) : nil
            notifiedPairs.append(pair)
            if canNotify {
                remainingDaySlots -= 1
                remainingWeekSlots -= 1
                history.append(currentDate)
            }
            #if DEBUG
            print("[StyleMatch SaleWatcher] event product=\(event.productName) reason=\(event.reason.rawValue) status=\(canNotify ? "delivered" : "capped-or-in-app-only")")
            #endif
            return updated
        }

        localStore.lastKnownSaleState = newSnapshots
        localStore.notifiedSalePairs = notifiedPairs
        localStore.saleNotificationHistory = history
        localStore.recentSaleEvents = cappedEvents
        return cappedEvents
    }

    func requestNotificationOptIn() async -> Bool {
        guard let notificationScheduler else { return false }
        let granted = await notificationScheduler.requestAuthorization()
        localStore.saleNotificationsEnabled = granted
        if granted {
            let currentDate = now()
            if let catalog = try? await catalogProvider.products() {
                localStore.lastKnownSaleState = saleSnapshots(for: watchProducts(
                    catalog: catalog,
                    favoriteProducts: catalog.filter { Set(localStore.savedFavorites).contains($0.id) }
                ), now: currentDate)
            }
        }
        return granted
    }

    func currentFavoriteSaleEvents(catalog: [AffiliateProduct]) -> [SaleEvent] {
        let currentDate = now()
        let favoriteIDs = Set(localStore.savedFavorites)
        return catalog.compactMap { product in
            guard favoriteIDs.contains(product.id),
                  let salePrice = activeSalePrice(for: product, now: currentDate) else { return nil }
            return SaleEvent(
                id: "current-\(product.id)-\(salePrice)",
                productID: product.id,
                productName: product.name,
                retailerName: product.retailer.name,
                subcategory: product.subcategory,
                salePrice: salePrice,
                originalPrice: product.price,
                saleEndsAt: product.saleEndsAt,
                reason: .directFavorite,
                occurredAt: currentDate,
                shouldNotify: false,
                scheduledDeliveryDate: nil
            )
        }
    }

    func unreadSaleEventCount() -> Int {
        localStore.recentSaleEvents.filter { !localStore.viewedSaleEventIDs.contains($0.id) }.count
    }

    func markRecentSaleEventsViewed() {
        localStore.viewedSaleEventIDs = localStore.viewedSaleEventIDs.union(localStore.recentSaleEvents.map(\.id))
    }

    static func notificationTitleAndBody(for event: SaleEvent, retailerName: String) -> (title: String, body: String) {
        if event.reason == .similarToFavorite {
            return ("Favorite style on sale", "A \(event.subcategory) similar to your favorites is on sale at \(retailerName).")
        }

        if retailerName.caseInsensitiveCompare("Amazon") == .orderedSame {
            return ("Favorite on sale", "Your favorited \(event.productName) just went on sale at Amazon.")
        }

        let sale = currency(event.salePrice)
        let original = event.originalPrice.map(currency) ?? "the original price"
        return ("Favorite on sale", "Your favorited \(event.productName) is now \(sale) at \(retailerName) (was \(original)).")
    }

    static func activeCatalogProvider() -> ProductCatalogProvider {
        if FeatureFlags.remoteCatalogEnabled, let remoteURL = URL(string: "https://example.com/stylematch/ProductCatalog.json") {
            return RemoteCatalogProvider(
                catalogURL: remoteURL,
                cacheDirectory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0],
                fallbackProvider: BundledCatalogProvider()
            )
        }
        return BundledCatalogProvider()
    }

    private func scheduleNotifications(for events: [SaleEvent]) async {
        guard localStore.saleNotificationsEnabled, let notificationScheduler else { return }
        for event in events {
            let content = Self.notificationTitleAndBody(for: event, retailerName: event.retailerName)
            await notificationScheduler.schedule(SaleNotificationRequest(
                identifier: "sale-watcher-\(event.id)",
                title: content.title,
                body: content.body,
                productID: event.productID,
                deliveryDate: event.scheduledDeliveryDate ?? deliveryDate(for: now())
            ))
        }
    }

    private func watchProducts(catalog: [AffiliateProduct], favoriteProducts: [AffiliateProduct]) -> [AffiliateProduct] {
        guard !favoriteProducts.isEmpty else { return [] }
        let favoriteIDs = Set(favoriteProducts.map(\.id))
        let direct = catalog.filter { favoriteIDs.contains($0.id) }
        let similar = catalog.filter { product in
            !favoriteIDs.contains(product.id)
                && CatalogDealProvider.productMatchesSavedStyle(product, similarStyleProducts: favoriteProducts, frequentlyWornRecords: [])
        }
        var seen = Set<String>()
        return (direct + similar).filter { seen.insert($0.id).inserted }
    }

    private func saleEvent(
        for product: AffiliateProduct,
        salePrice: Decimal,
        favoriteIDs: Set<String>,
        previous: SaleSnapshot?,
        now currentDate: Date
    ) -> SaleEvent? {
        let previousSalePrice = previous?.salePrice
        let transitionedIntoSale = previous == nil || previousSalePrice == nil
        let priceDropped = previousSalePrice.map { salePrice < $0 } ?? false
        guard transitionedIntoSale || priceDropped || previousSalePrice != salePrice else { return nil }

        let reason: SaleEventReason = favoriteIDs.contains(product.id) ? .directFavorite : .similarToFavorite
        return SaleEvent(
            id: "\(product.id)-\(salePrice)-\(currentDate.timeIntervalSince1970)",
            productID: product.id,
            productName: product.name,
            retailerName: product.retailer.name,
            subcategory: product.subcategory,
            salePrice: salePrice,
            originalPrice: product.price,
            saleEndsAt: product.saleEndsAt,
            reason: reason,
            occurredAt: currentDate,
            shouldNotify: false,
            scheduledDeliveryDate: nil
        )
    }

    private func activeSalePrice(for product: AffiliateProduct, now currentDate: Date) -> Decimal? {
        guard let salePrice = product.salePrice, salePrice > 0 else { return nil }
        if let price = product.price, salePrice >= price { return nil }
        if let saleEndsAt = product.saleEndsAt, saleEndsAt <= currentDate { return nil }
        return salePrice
    }

    private func saleSnapshots(for products: [AffiliateProduct], now currentDate: Date) -> [String: SaleSnapshot] {
        Dictionary(uniqueKeysWithValues: products.map { product in
            (product.id, SaleSnapshot(salePrice: activeSalePrice(for: product, now: currentDate), saleEndsAt: product.saleEndsAt, timestamp: currentDate))
        })
    }

    private func notifiedPair(productID: String, salePrice: Decimal) -> String {
        "\(productID)|\(NSDecimalNumber(decimal: salePrice).stringValue)"
    }

    private func isWithinLastSevenDays(_ date: Date, now currentDate: Date) -> Bool {
        date >= currentDate.addingTimeInterval(-7 * 24 * 60 * 60)
    }

    private func deliveryDate(for date: Date) -> Date {
        let hour = calendar.component(.hour, from: date)
        if hour >= 22 {
            return calendar.nextDate(after: date, matching: DateComponents(hour: 8, minute: 0), matchingPolicy: .nextTime) ?? date
        }
        if hour < 8 {
            return calendar.date(bySettingHour: 8, minute: 0, second: 0, of: date) ?? date
        }
        return date
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

#if canImport(BackgroundTasks) && os(iOS)
enum SaleWatcherBackgroundRefresh {
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: SaleWatcher.backgroundRefreshIdentifier, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(task)
        }
    }

    static func scheduleNextRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: SaleWatcher.backgroundRefreshIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handle(_ task: BGAppRefreshTask) {
        scheduleNextRefresh()
        let saleTask = Task {
            _ = await SaleWatcher().checkForNewSales()
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = {
            saleTask.cancel()
            task.setTaskCompleted(success: false)
        }
    }
}
#endif
