import SafariServices
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum ShoppingRecommendationBasis: String, CaseIterable, Identifiable {
    case wardrobeHistory
    case favoriteBrands
    case favoriteColors
    case budget
    case currentTrends
    case weather
    case calendarEvents

    var id: String { rawValue }

    static let defaultEnabled: [ShoppingRecommendationBasis] = [
        .wardrobeHistory,
        .favoriteBrands,
        .favoriteColors,
        .budget,
        .currentTrends
    ]

    var title: String {
        switch self {
        case .wardrobeHistory: return "Wardrobe"
        case .favoriteBrands: return "Brands"
        case .favoriteColors: return "Colors"
        case .budget: return "Budget"
        case .currentTrends: return "Trends"
        case .weather: return "Weather"
        case .calendarEvents: return "Calendar"
        }
    }

    var icon: String {
        switch self {
        case .wardrobeHistory: return "tshirt.fill"
        case .favoriteBrands: return "tag.fill"
        case .favoriteColors: return "paintpalette.fill"
        case .budget: return "dollarsign.circle.fill"
        case .currentTrends: return "flame.fill"
        case .weather: return "cloud.sun.fill"
        case .calendarEvents: return "calendar"
        }
    }
}

private struct RecommendationRationaleSheet: Identifiable {
    let id = UUID()
    let productName: String
    let rationale: RecommendationRationale
}

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
    @State private var showExpandedDisclosure = false
    @State private var selectedRationaleSheet: RecommendationRationaleSheet?
    @State private var showRecommendationPreferences = false
    @State private var recommendationBasis: Set<ShoppingRecommendationBasis> = Set(ShoppingRecommendationBasis.defaultEnabled)
    @State private var isLoading = true
    @State private var isSearchingLive = false
    @State private var loadError: String?
    @StateObject private var profileStore = ProfileStore()
    @StateObject private var outfitMemoryStore = OutfitMemoryStore()

    private let store = ShoppingLocalStore()
    private let companionRecommender = CatalogProductComplementaryPieceRecommender()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    disclosureSummary
                    alertControls
                    recommendationBasisControls
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
                            sectionTitle(recommendationSectionTitle)
                            LazyVStack(spacing: 12) {
                                ForEach(recommendations) { recommendation in
                                    productCard(
                                        product: recommendation.product,
                                        reasonFacts: recommendation.reasonFacts,
                                        rank: recommendation.rank
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
                                productCard(product: product, reasonFacts: nil, rank: nil)
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showRecommendationPreferences = true
                    } label: {
                        Label("Recommendation preferences", systemImage: "gearshape")
                    }
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
            .sheet(item: $selectedRationaleSheet) { sheet in
                recommendationReasonSheet(sheet)
            }
            .sheet(isPresented: $showRecommendationPreferences) {
                recommendationPreferencesSheet
            }
            .sheet(isPresented: $showExpandedDisclosure) {
                NavigationStack {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Shopping through StyleMatch Pro")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("We may earn a small commission from qualifying purchases at no extra cost to you. Orders are completed securely with the retailer.")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding()
                    .navigationTitle("Disclosure")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") {
                                store.affiliateDisclosureExpanded = false
                                showExpandedDisclosure = false
                            }
                        }
                    }
                }
            }
            .onAppear {
                showExpandedDisclosure = store.affiliateDisclosureExpanded
                recommendationBasis = Set(basis(from: RecommendationRationaleBuilder.preferences(from: profileStore.currentProfile)))
            }
        }
    }

    private var disclosureSummary: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Shopping through StyleMatch Pro")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                store.affiliateDisclosureExpanded = true
                showExpandedDisclosure = true
            } label: {
                Text("Learn more")
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Affiliate disclosure")
            Spacer()
        }
        .lineLimit(1)
    }

    private var recommendationBasisControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recommendations")
                .font(.subheadline)
                .fontWeight(.bold)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ShoppingRecommendationBasis.allCases) { basis in
                        Button {
                            if recommendationBasis.contains(basis) {
                                recommendationBasis.remove(basis)
                            } else {
                                recommendationBasis.insert(basis)
                            }
                            persistRecommendationPreferences()
                        } label: {
                            Label(basis.title, systemImage: basis.icon)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(recommendationBasis.contains(basis) ? Color.orange.opacity(0.22) : Color(.secondarySystemBackground))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(12)
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
        return ShoppingSearchEngine.filter(products: budgetFiltered(liveSearchProducts ?? products), criteria: criteria)
    }

    private var recommendationSectionTitle: String {
        recommendations.allSatisfy { rationale(for: $0.product, reasonFacts: $0.reasonFacts).isTrendingFallback } ? "Trending Now" : "For You"
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

    private func productCard(product: AffiliateProduct, reasonFacts: ProductRecommendationReasonFacts?, rank: Int?) -> some View {
        let rationale = rationale(for: product, reasonFacts: reasonFacts)
        let reason = rationale.headline
        let matchPercent = matchPercent(for: rank, hasReason: !rationale.isTrendingFallback)
        let viewModel = AffiliateProductViewModel(product: product, reasonText: reason, matchPercent: matchPercent)
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
                            if let matchText = viewModel.matchText {
                                Text(matchText)
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 4)
                                    .background(Color.green.opacity(0.16))
                                    .clipShape(Capsule())
                            }
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

                        if !reason.isEmpty {
                            Text(reason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                        productMetadata(viewModel)
                        if let footnote = viewModel.footnote {
                            Text(footnote)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .buttonStyle(.plain)

            whyRecommendationButton(product: product, rationale: rationale)

            completeTheLookSection(for: product)

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

    private func productMetadata(_ viewModel: AffiliateProductViewModel) -> some View {
        let values = [
            viewModel.saleCountdownText,
            viewModel.availableSizesText,
            viewModel.availableColorsText,
            viewModel.ratingText,
            viewModel.shippingText
        ].compactMap { $0 }

        return Group {
            if !values.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(values, id: \.self) { value in
                        Text(value)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func whyRecommendationButton(product: AffiliateProduct, rationale: RecommendationRationale) -> some View {
        Button {
            selectedRationaleSheet = RecommendationRationaleSheet(productName: product.name, rationale: rationale)
        } label: {
            Label("Why this recommendation?", systemImage: "checkmark.circle")
                .font(.caption)
                .fontWeight(.semibold)
        }
        .buttonStyle(.plain)
    }

    private func completeTheLookSection(for product: AffiliateProduct) -> some View {
        let suggestions = companionRecommender.companions(for: product, catalog: budgetFiltered(products), limit: 6)
        return Group {
            if suggestions.count >= 2 {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Complete the Look")
                        .font(.caption)
                        .fontWeight(.bold)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(suggestions) { suggestion in
                                Button {
                                    selectedProduct = suggestion
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(suggestion.name)
                                            .font(.caption2)
                                            .fontWeight(.semibold)
                                            .lineLimit(2)
                                        Text(rationale(for: suggestion, reasonFacts: nil).headline)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                    .frame(width: 150, alignment: .leading)
                                    .padding(8)
                                    .background(Color(.secondarySystemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    private func matchPercent(for rank: Int?, hasReason: Bool) -> Int? {
        guard hasReason else { return nil }
        let rank = rank ?? 50
        return max(72, min(98, 72 + rank / 4))
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

    private func recommendationReasonSheet(_ sheet: RecommendationRationaleSheet) -> some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(sheet.productName)
                    .font(.headline)
                Text(sheet.rationale.headline)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 10) {
                    if sheet.rationale.reasons.isEmpty {
                        Label("Trending with shoppers this week", systemImage: "checkmark.circle.fill")
                            .font(.subheadline)
                    } else {
                        ForEach(sheet.rationale.reasons, id: \.self) { reason in
                            Label(reason.displayText, systemImage: "checkmark.circle.fill")
                                .font(.subheadline)
                        }
                    }
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Why this recommendation?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        selectedRationaleSheet = nil
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var recommendationPreferencesSheet: some View {
        NavigationStack {
            List {
                Section {
                    preferenceToggle(.wardrobeHistory, detail: "Use saved scans and closet history.")
                    preferenceToggle(.favoriteBrands, detail: "Favor brands you save or prefer.")
                    preferenceToggle(.favoriteColors, detail: "Lean into colors you wear often.")
                    preferenceToggle(.budget, detail: "Filter catalog picks by your saved budget.")
                    preferenceToggle(.currentTrends, detail: "Use popular catalog picks when your wardrobe history is limited.")
                    preferenceToggle(.weather, detail: "Prepare shopping suggestions for weather-aware outfit planning.")
                    preferenceToggle(.calendarEvents, detail: "Prepare shopping suggestions for upcoming occasions when calendar access is enabled.")
                } footer: {
                    Text("Weather and calendar suggestions only use those signals after you enable the related app permissions.")
                    // FUTURE: Add weather and calendar recommendation controls when those permissions exist.
                }
            }
            .navigationTitle("Recommendations")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        showRecommendationPreferences = false
                    }
                }
            }
        }
    }

    private func preferenceToggle(_ basis: ShoppingRecommendationBasis, detail: String) -> some View {
        Toggle(isOn: Binding(
            get: { recommendationBasis.contains(basis) },
            set: { enabled in
                if enabled {
                    recommendationBasis.insert(basis)
                } else {
                    recommendationBasis.remove(basis)
                }
                persistRecommendationPreferences()
                reloadRecommendations()
            }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Label(basis.title, systemImage: basis.icon)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func rationale(for product: AffiliateProduct, reasonFacts: ProductRecommendationReasonFacts?) -> RecommendationRationale {
        RecommendationRationaleBuilder.build(
            for: product,
            reasonFacts: reasonFacts,
            profile: profileStore.currentProfile,
            memories: outfitMemoryStore.memories,
            savedFavorites: products.filter { store.savedFavorites.contains($0.id) },
            favoriteProductIDs: Set(store.savedFavorites),
            preferences: currentRecommendationPreferences()
        )
    }

    private func currentRecommendationPreferences() -> ShoppingRecommendationPreferences {
        ShoppingRecommendationPreferences(
            usesWardrobeHistory: recommendationBasis.contains(.wardrobeHistory),
            usesFavoriteBrands: recommendationBasis.contains(.favoriteBrands),
            usesFavoriteColors: recommendationBasis.contains(.favoriteColors),
            usesBudgetRange: recommendationBasis.contains(.budget),
            usesCurrentTrends: recommendationBasis.contains(.currentTrends),
            usesWeather: recommendationBasis.contains(.weather),
            usesCalendarEvents: recommendationBasis.contains(.calendarEvents)
        )
    }

    private func basis(from preferences: ShoppingRecommendationPreferences) -> [ShoppingRecommendationBasis] {
        var output: [ShoppingRecommendationBasis] = []
        if preferences.usesWardrobeHistory { output.append(.wardrobeHistory) }
        if preferences.usesFavoriteBrands { output.append(.favoriteBrands) }
        if preferences.usesFavoriteColors { output.append(.favoriteColors) }
        if preferences.usesBudgetRange { output.append(.budget) }
        if preferences.usesCurrentTrends { output.append(.currentTrends) }
        if preferences.usesWeather { output.append(.weather) }
        if preferences.usesCalendarEvents { output.append(.calendarEvents) }
        return output
    }

    private func persistRecommendationPreferences() {
        var profile = profileStore.currentProfile
        RecommendationRationaleBuilder.apply(currentRecommendationPreferences(), to: &profile)
        profileStore.currentProfile = profile
        profileStore.save()
    }

    private func budgetFiltered(_ catalog: [AffiliateProduct]) -> [AffiliateProduct] {
        RecommendationRationaleBuilder.budgetFiltered(
            catalog,
            profile: profileStore.currentProfile,
            preferences: currentRecommendationPreferences()
        )
    }

    private func reloadRecommendations() {
        let ranked = ShoppingRecommendationEngine.recommendations(
            currentGarments: [],
            currentColors: [],
            memories: currentRecommendationPreferences().usesWardrobeHistory ? outfitMemoryStore.memories : [],
            weather: nil,
            catalog: budgetFiltered(products),
            dismissedProductIDs: store.dismissedProductIDs,
            recentlyViewedProductIDs: store.recentlyViewedProductIDs
        )
        recommendations = ranked.isEmpty
            ? ShoppingRecommendationEngine.popularFallbackRecommendations(catalog: budgetFiltered(products))
            : ranked
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
            let config = (try? BundledShoppingIntegrationConfigProvider().config()) ?? .empty
            if FeatureFlags.remoteCatalogEnabled, let remoteURL = config.catalogBaseURL {
                provider = RemoteCatalogProvider(
                    baseURL: remoteURL,
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
            let preferences = await MainActor.run { currentRecommendationPreferences() }
            let eligibleCatalog = RecommendationRationaleBuilder.budgetFiltered(
                loaded,
                profile: await MainActor.run { profileStore.currentProfile },
                preferences: preferences
            )
            let ranked = ShoppingRecommendationEngine.recommendations(
                currentGarments: [],
                currentColors: [],
                memories: preferences.usesWardrobeHistory ? await MainActor.run { outfitMemoryStore.memories } : [],
                weather: nil,
                catalog: eligibleCatalog,
                dismissedProductIDs: store.dismissedProductIDs,
                recentlyViewedProductIDs: store.recentlyViewedProductIDs
            )
            let visibleRecommendations = ranked.isEmpty
                ? ShoppingRecommendationEngine.popularFallbackRecommendations(catalog: eligibleCatalog)
                : ranked
            #if DEBUG
            visibleRecommendations.forEach { _ = PersonalizationContextBuilder.buildShoppingRecommendationPromptContext($0.reasonFacts) }
            #endif
            let alertList = makeSaleAlerts(from: loaded)
            let watcher = SaleWatcher(catalogProvider: provider)
            let favoriteSales = watcher.currentFavoriteSaleEvents(catalog: loaded)
            await MainActor.run {
                products = loaded
                supportedStores = stores
                recommendations = visibleRecommendations
                alertsEnabled = store.saleNotificationsEnabled
                showExpandedDisclosure = store.affiliateDisclosureExpanded
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
