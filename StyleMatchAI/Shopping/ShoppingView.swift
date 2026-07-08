import SafariServices
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ShoppingView: View {
    @Binding var selectedTab: AppTab
    @State private var products: [AffiliateProduct] = []
    @State private var liveSearchProducts: [AffiliateProduct]?
    @State private var supportedStores: [SupportedStore] = []
    @State private var recommendations: [ProductRecommendation] = []
    @State private var saleAlerts: [ShoppingSaleAlert] = []
    @State private var favoriteSaleEvents: [SaleEvent] = []
    @State private var notificationDenied = false
    @State private var alertsEnabled = false
    @State private var selectedCategory: ProductCategory? = nil
    @State private var searchCriteria = ShoppingSearchCriteria()
    @State private var selectedProduct: AffiliateProduct?
    @State private var showDisclosure = false
    @State private var isLoading = true
    @State private var isSearchingLive = false
    @State private var loadError: String?

    private let store = ShoppingLocalStore()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    disclosureBanner
                    alertControls
                    NavigationLink {
                        StoreSearchView()
                    } label: {
                        Label("Search favorite stores", systemImage: "magnifyingglass")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    if let loadError {
                        retryState(loadError)
                    } else {
                        if !favoriteSaleEvents.isEmpty {
                            sectionTitle("Your favorites on sale")
                            favoriteSalesSection
                        }

                        if !recommendations.isEmpty {
                            sectionTitle("For You")
                            LazyVStack(spacing: 12) {
                                ForEach(recommendations) { recommendation in
                                    productCard(
                                        product: recommendation.product,
                                        reason: recommendation.reasonFacts.oneLineReason
                                    )
                                }
                            }
                        }

                        if !saleAlerts.isEmpty {
                            sectionTitle("Shopping Deals")
                            saleAlertSections
                        }

                        sectionTitle(recommendations.isEmpty ? "Browse" : "Browse by Category")
                        searchControls
                        categoryChips
                        LazyVStack(spacing: 12) {
                            ForEach(searchResults) { product in
                                productCard(product: product, reason: nil)
                            }
                        }
                        if searchResults.isEmpty, !products.isEmpty {
                            Text("No products match those filters. Try a different store, color, size, style, price, or occasion.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding()
                                .appCard(.shop, radius: 10)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Shopping")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        selectedTab = .home
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .accessibilityLabel("Back to Home")
                }
            }
            .appScreenBackground(.shop)
            .task {
                await loadCatalog()
            }
            .sheet(item: $selectedProduct) { product in
                NavigationStack {
                    SafariView(url: AffiliateLinkBuilder.outboundURL(for: product))
                        .navigationTitle(product.name)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") {
                                    selectedProduct = nil
                                }
                            }
                        }
                        .onAppear {
                            store.markViewed(product.id)
                        }
                    }
            }
            .onReceive(NotificationCenter.default.publisher(for: SaleWatcherRouteStore.didReceiveProductRoute)) { notification in
                if let productID = notification.object as? String {
                    selectProduct(productID: productID)
                }
            }
            .sheet(isPresented: $showDisclosure) {
                NavigationStack {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Affiliate Disclosure")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("StyleMatch Pro may earn a commission when you buy through retailer links in this app. StyleMatch Pro is not the seller. Checkout, fulfillment, shipping, refunds, returns, and customer service are handled by the retailer.")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding()
                    .navigationTitle("Disclosure")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showDisclosure = false }
                        }
                    }
                }
            }
        }
    }

    private var disclosureBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 6) {
                Text("StyleMatch Pro may earn a commission when you buy through these links. All purchases are completed with the retailer.")
                    .font(.footnote)
                    .fontWeight(.semibold)
                Button("How affiliate shopping works") {
                    showDisclosure = true
                }
                .font(.footnote)
            }
        }
        .padding()
        .appCard(.shop, radius: 10)
    }

    private var alertControls: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: alertsEnabled ? "bell.badge.fill" : "bell.slash.fill")
                .foregroundStyle(alertsEnabled ? .orange : .secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(alertsEnabled ? "Sale notifications are on" : "Get notified when your favorites go on sale")
                    .font(.subheadline)
                    .fontWeight(.bold)
                Text(notificationDenied ? "Notifications are off in iOS Settings. In-app sale badges will still show." : "StyleMatch Pro checks approved catalog data on this phone and sends local alerts only after new sale changes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if notificationDenied {
                    Button("Open Settings") {
                        #if canImport(UIKit)
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                        #endif
                    }
                    .font(.caption)
                }
            }
            Spacer()
            if alertsEnabled {
                Toggle("", isOn: Binding(
                    get: { alertsEnabled },
                    set: { enabled in
                        alertsEnabled = enabled
                        store.saleNotificationsEnabled = enabled
                    }
                ))
                .labelsHidden()
            } else {
                Button("Turn On") {
                    Task { await optInSaleNotifications() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding()
        .appCard(.shop, radius: 10)
    }

    private var favoriteSalesSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(favoriteSaleEvents) { event in
                    if let product = products.first(where: { $0.id == event.productID }) {
                        Button {
                            selectedProduct = product
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(product.name)
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .lineLimit(2)
                                Text(product.retailer.name)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                HStack {
                                    Text(currency(event.salePrice))
                                        .font(.caption)
                                        .fontWeight(.bold)
                                    if isRecentSaleEvent(productID: product.id) {
                                        Text("New sale")
                                            .font(.caption2)
                                            .fontWeight(.bold)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background(Color.red.opacity(0.16))
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                            .frame(width: 180, alignment: .leading)
                            .padding()
                            .appCard(.shop, radius: 10)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .onAppear {
            SaleWatcher().markRecentSaleEventsViewed()
        }
    }

    private var saleAlertSections: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(ShoppingSaleAlertService.groupedSections(from: saleAlerts).enumerated()), id: \.offset) { _, section in
                VStack(alignment: .leading, spacing: 8) {
                    Text(section.title)
                        .font(.subheadline)
                        .fontWeight(.bold)
                    ForEach(section.alerts) { alert in
                        saleAlertCard(alert)
                    }
                }
            }
        }
    }

    private func saleAlertCard(_ alert: ShoppingSaleAlert) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: alert.trigger == .backInStock ? "shippingbox.fill" : "tag.fill")
                .foregroundStyle(.red)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(alert.productName)
                        .font(.subheadline)
                        .fontWeight(.bold)
                    Spacer()
                    Text(alert.retailerName)
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.16))
                        .clipShape(Capsule())
                }
                Text(alert.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let salePrice = alert.salePrice {
                    Text("Sale price: \(currency(salePrice))")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
            }
        }
        .padding()
        .appCard(.shop, radius: 10)
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryButton(nil, title: "All")
                ForEach(ProductCategory.allCases) { category in
                    categoryButton(category, title: category.displayName)
                }
            }
        }
    }

    private var searchControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Search store, product, brand, color, size, style, gender, price, or occasion", text: Binding(
                get: { searchCriteria.query },
                set: { searchCriteria.query = $0 }
            ))
            .textFieldStyle(.roundedBorder)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    storeButton(nil, title: "All Stores")
                    ForEach(ShoppingSearchEngine.filterStores(supportedStores, query: searchCriteria.query).prefix(20)) { store in
                        storeButton(store.name, title: store.name)
                    }
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: 8)], spacing: 8) {
                filterField("Color", text: bindingString(\.color))
                filterField("Size", text: bindingString(\.size))
                filterField("Style", text: bindingString(\.style))
                filterField("Gender", text: bindingString(\.genderPresentation))
                filterField("Occasion", text: bindingString(\.occasion))
                filterField("Max $", text: Binding(
                    get: { searchCriteria.maximumPrice.map { "\($0)" } ?? "" },
                    set: { searchCriteria.maximumPrice = Decimal(string: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                ))
            }

            if FeatureFlags.liveSearchEnabled {
                Button {
                    Task { await runLiveSearch() }
                } label: {
                    Label(isSearchingLive ? "Searching approved retailers..." : "Search approved retailers", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSearchingLive)
            }
        }
        .padding()
        .appCard(.shop, radius: 10)
    }

    private var searchResults: [AffiliateProduct] {
        var criteria = searchCriteria
        criteria.category = selectedCategory
        return ShoppingSearchEngine.filter(products: liveSearchProducts ?? products, criteria: criteria)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .fontWeight(.bold)
    }

    private func categoryButton(_ category: ProductCategory?, title: String) -> some View {
        Button {
            selectedCategory = category
            searchCriteria.category = category
        } label: {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background((selectedCategory == category ? Color.orange.opacity(0.22) : Color(.secondarySystemBackground)))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func storeButton(_ storeName: String?, title: String) -> some View {
        Button {
            searchCriteria.storeName = storeName
        } label: {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background((searchCriteria.storeName == storeName ? Color.orange.opacity(0.22) : Color(.secondarySystemBackground)))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func filterField(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text)
            .textFieldStyle(.roundedBorder)
            .font(.caption)
    }

    private func bindingString(_ keyPath: WritableKeyPath<ShoppingSearchCriteria, String?>) -> Binding<String> {
        Binding(
            get: { searchCriteria[keyPath: keyPath] ?? "" },
            set: { searchCriteria[keyPath: keyPath] = $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        )
    }

    private func productCard(product: AffiliateProduct, reason: String?) -> some View {
        let viewModel = AffiliateProductViewModel(product: product, reasonText: reason)
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                selectedProduct = product
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    AsyncImage(url: product.imageURL) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            ZStack {
                                Color(.secondarySystemBackground)
                                Image(systemName: "bag.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(width: 82, height: 82)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(viewModel.name)
                                .font(.headline)
                                .lineLimit(2)
                            Spacer()
                            Text(viewModel.retailerName)
                                .font(.caption)
                                .fontWeight(.bold)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.orange.opacity(0.16))
                                .clipShape(Capsule())
                        }

                        Text(viewModel.soldAndShippedText)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)

                        HStack(spacing: 8) {
                            Text(viewModel.priceText)
                                .font(.subheadline)
                                .fontWeight(.bold)
                            if let original = viewModel.originalPriceText {
                                Text(original)
                                    .font(.caption)
                                    .strikethrough()
                                    .foregroundStyle(.secondary)
                            }
                        if let sale = viewModel.saleBadgeText {
                            Text(sale)
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color.red.opacity(0.15))
                                .clipShape(Capsule())
                        }
                        if isRecentSaleEvent(productID: product.id) {
                            Text("New sale")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.red.opacity(0.16))
                                .clipShape(Capsule())
                        }
                        }

                        if let reason {
                            Text(reason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        if let footnote = viewModel.footnote {
                            Text(footnote)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                productActionButton(
                    title: "Favorite",
                    systemImage: store.savedFavorites.contains(product.id) ? "heart.fill" : "heart",
                    isActive: store.savedFavorites.contains(product.id)
                ) {
                    store.toggleFavorite(product.id)
                    refreshSaleAlerts()
                }
                productActionButton(
                    title: "Wishlist",
                    systemImage: store.wishlistProductIDs.contains(product.id) ? "bookmark.fill" : "bookmark",
                    isActive: store.wishlistProductIDs.contains(product.id)
                ) {
                    store.toggleWishlist(product.id)
                    refreshSaleAlerts()
                }
                productActionButton(
                    title: "Cart",
                    systemImage: store.cartProductIDs.contains(product.id) ? "cart.fill" : "cart",
                    isActive: store.cartProductIDs.contains(product.id)
                ) {
                    store.toggleCart(product.id)
                    refreshSaleAlerts()
                }
                productActionButton(
                    title: "Card",
                    systemImage: store.shoppingCardProductIDs.contains(product.id) ? "rectangle.stack.fill" : "rectangle.stack",
                    isActive: store.shoppingCardProductIDs.contains(product.id)
                ) {
                    store.toggleShoppingCard(product.id)
                    refreshSaleAlerts()
                }
            }
        }
        .padding()
        .appCard(.shop, radius: 10)
    }

    private func productActionButton(title: String, systemImage: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption2)
                .fontWeight(.semibold)
                .labelStyle(.iconOnly)
                .frame(width: 36, height: 32)
                .foregroundStyle(isActive ? .orange : .secondary)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func retryState(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Catalog unavailable")
                .font(.headline)
            Text(message)
                .foregroundStyle(.secondary)
            Button("Retry") {
                Task { await loadCatalog() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .appCard(.shop)
    }

    private func loadCatalog() async {
        isLoading = true
        loadError = nil
        do {
            let provider: ProductCatalogProvider
            if FeatureFlags.remoteCatalogEnabled,
               let remoteURL = URL(string: "https://example.com/stylematch/ProductCatalog.json") {
                provider = RemoteCatalogProvider(
                    catalogURL: remoteURL,
                    cacheDirectory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0],
                    fallbackProvider: BundledCatalogProvider()
                )
            } else {
                provider = BundledCatalogProvider()
            }

            async let loadedProducts = provider.products()
            async let loadedStores = BundledStoreDirectoryProvider().stores()
            let loaded = try await loadedProducts
            let stores = (try? await loadedStores) ?? []
            let ranked = ShoppingRecommendationEngine.recommendations(
                currentGarments: [],
                currentColors: [],
                memories: OutfitMemoryStore().memories,
                weather: nil,
                catalog: loaded,
                dismissedProductIDs: store.dismissedProductIDs,
                recentlyViewedProductIDs: store.recentlyViewedProductIDs
            )
            #if DEBUG
            ranked.forEach { _ = PersonalizationContextBuilder.buildShoppingRecommendationPromptContext($0.reasonFacts) }
            #endif
            let alertList = makeSaleAlerts(from: loaded)
            let watcher = SaleWatcher(catalogProvider: provider)
            let favoriteSales = watcher.currentFavoriteSaleEvents(catalog: loaded)
            await MainActor.run {
                products = loaded
                supportedStores = stores
                recommendations = ranked
                alertsEnabled = store.saleNotificationsEnabled
                saleAlerts = alertList
                favoriteSaleEvents = favoriteSales
                isLoading = false
            }
            await checkPendingProductRoute()
        } catch {
            await MainActor.run {
                loadError = "We could not load the retailer catalog. Please try again."
                isLoading = false
            }
        }
    }

    private func runLiveSearch() async {
        guard FeatureFlags.liveSearchEnabled else {
            return
        }

        await MainActor.run {
            isSearchingLive = true
            loadError = nil
        }

        do {
            guard let provider = try ShoppingDataSourceResolver.liveProvider() else {
                await MainActor.run { isSearchingLive = false }
                return
            }
            var criteria = searchCriteria
            criteria.category = selectedCategory
            let results = try await provider.search(criteria: criteria)
            await MainActor.run {
                liveSearchProducts = results
                isSearchingLive = false
            }
        } catch {
            await MainActor.run {
                loadError = "Live retailer search is not configured yet. Browse the approved local catalog for now."
                isSearchingLive = false
            }
        }
    }

    private func refreshSaleAlerts() {
        saleAlerts = makeSaleAlerts(from: products)
        favoriteSaleEvents = SaleWatcher().currentFavoriteSaleEvents(catalog: products)
        if store.saleNotificationsEnabled {
            Task { _ = await SaleWatcher().checkForNewSales() }
        }
    }

    private func makeSaleAlerts(from catalog: [AffiliateProduct]) -> [ShoppingSaleAlert] {
        let savedIDs = Set(store.savedFavorites)
        let styleProducts = catalog.filter { savedIDs.contains($0.id) }
        return ShoppingSaleAlertService.alerts(
            catalog: catalog,
            context: ShoppingSaleAlertContext(
                favoriteProductIDs: savedIDs,
                wishlistProductIDs: Set(store.wishlistProductIDs),
                cartProductIDs: Set(store.cartProductIDs),
                shoppingCardProductIDs: Set(store.shoppingCardProductIDs),
                savedStyleProducts: styleProducts,
                memories: OutfitMemoryStore().memories,
                now: Date()
            )
        )
    }

    private func optInSaleNotifications() async {
        let granted = await SaleWatcher().requestNotificationOptIn()
        await MainActor.run {
            alertsEnabled = granted
            notificationDenied = !granted
        }
    }

    private func checkPendingProductRoute() async {
        guard let productID = SaleWatcherRouteStore.consumePendingProductID() else { return }
        await MainActor.run {
            selectProduct(productID: productID)
        }
    }

    private func selectProduct(productID: String) {
        selectedProduct = products.first { $0.id == productID }
    }

    private func isRecentSaleEvent(productID: String) -> Bool {
        let cutoff = Date().addingTimeInterval(-72 * 60 * 60)
        return store.recentSaleEvents.contains { $0.productID == productID && $0.occurredAt >= cutoff }
    }

    private func currency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "en_US")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
