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
        case .currentTrends: return "Catalog"
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
        case .currentTrends: return "square.grid.2x2.fill"
        case .weather: return "cloud.sun.fill"
        case .calendarEvents: return "calendar"
        }
    }
}

private enum ShoppingBrowseMode: String, CaseIterable, Identifiable {
    case browse
    case deck

    var id: String { rawValue }

    var title: String {
        switch self {
        case .browse: return "Browse"
        case .deck: return "Deck"
        }
    }

    var icon: String {
        switch self {
        case .browse: return "square.grid.2x2"
        case .deck: return "rectangle.stack"
        }
    }
}

private struct RecommendationRationaleSheet: Identifiable {
    let id = UUID()
    let productName: String
    let rationale: RecommendationRationale
}

private struct ShoppingDerivedCatalogContent {
    var trendingProducts: [AffiliateProduct] = []
    var dealProducts: [AffiliateProduct] = []
    var seasonalProducts: [AffiliateProduct] = []
    var completeLookProducts: [AffiliateProduct] = []
    var feedbackRecommendedProducts: [ShoppingFeedbackRankedProduct] = []

    static let empty = ShoppingDerivedCatalogContent()
}

#if DEBUG
private enum ShoppingPerformanceLog {
    static func mark(_ event: String, startedAt: CFAbsoluteTime? = nil) {
        if let startedAt {
            let elapsed = CFAbsoluteTimeGetCurrent() - startedAt
            print("[StyleMatch Shop Perf] \(event) elapsed=\(String(format: "%.3fs", elapsed))")
        } else {
            print("[StyleMatch Shop Perf] \(event)")
        }
    }
}
#endif

private enum ShoppingEngagementDestination: String, Identifiable, Hashable {
    case todaysStyleBrief
    case recommendationInsight
    case recommendedForYou
    case popularPicks
    case deals
    case completeLooks
    case savedHub
    case styleDNA
    case scanHistory
    case favoritesHub
    case wishlist
    case colorProfile
    case styleXP
    case priceAlerts
    case disclosure

    var id: String { rawValue }
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
    @State private var showExpandedDisclosure = false
    @State private var selectedRationaleSheet: RecommendationRationaleSheet?
    @State private var showRecommendationPreferences = false
    @State private var showBrowseFilters = false
    @State private var engagementPath: [ShoppingEngagementDestination] = []
    @State private var browseMode: ShoppingBrowseMode = .browse
    @State private var deckIndex = 0
    @State private var recommendationBasis: Set<ShoppingRecommendationBasis> = Set(ShoppingRecommendationBasis.defaultEnabled)
    @State private var derivedCatalogContent = ShoppingDerivedCatalogContent.empty
    @State private var isLoading = true
    @State private var isCatalogLoadInFlight = false
    @State private var isSearchingLive = false
    @State private var loadError: String?
    @State private var catalogDisclosure = ShoppingCatalogDisclosure.fallback
    @StateObject private var profileStore = ProfileStore()
    @StateObject private var outfitMemoryStore = OutfitMemoryStore()
    @StateObject private var store: ShoppingLocalStore

    private let companionRecommender = CatalogProductComplementaryPieceRecommender()

    init(selectedTab: Binding<AppTab>) {
        self._selectedTab = selectedTab
        self._store = StateObject(wrappedValue: ShoppingLocalStore())
        #if DEBUG
        ShoppingPerformanceLog.mark("ShoppingView init")
        #endif
    }

    var body: some View {
        NavigationStack(path: $engagementPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let loadError, products.isEmpty {
                        retryState(loadError)
                    } else if products.isEmpty {
                        shoppingLoadingShell
                    } else {
                        if isCatalogLoadInFlight {
                            catalogRefreshNotice
                        }
                        stylistFeedCard
                        discoveryShortcutRail

                        if !favoriteSaleEvents.isEmpty {
                            sectionTitle("Your favorites on sale")
                            favoriteSalesSection
                        }

                        if !recommendations.isEmpty {
                            productRail(
                                title: recommendationSectionTitle,
                                subtitle: recommendationSectionSubtitle,
                                recommendations: Array(recommendations.prefix(8))
                            )
                        }

                        if !saleAlerts.isEmpty {
                            sectionTitle("Shopping Deals")
                            saleAlertSections
                        }

                        seasonalCollections
                        completeLookPreview
                        styleProgressCard
                        feedbackRecommendedSection
                        browseHeader
                        if showBrowseFilters, browseMode == .browse {
                            searchControls
                            recommendationBasisControls
                            NavigationLink {
                                StoreSearchView()
                            } label: {
                                Label("Search favorite stores", systemImage: "magnifyingglass")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        if browseMode == .deck {
                            swipeDeckSection
                        } else {
                            categoryChips
                            if isSelectedStoreUnavailable {
                                selectedStoreUnavailableState
                            } else if let relaxedFilter = relaxedSearchResult.relaxedFilter {
                                relaxedFilterNotice(relaxedFilter)
                            }
                            LazyVStack(spacing: 12) {
                                ForEach(searchResults) { product in
                                    productCard(product: product, reasonFacts: nil, rank: nil)
                                }
                            }
                            if searchResults.isEmpty, !products.isEmpty, !isSelectedStoreUnavailable {
                                filteredDiscoveryState
                            }
                        }
                        alertControls
                        disclosureSummary
                        catalogDisclosureFooter
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
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
                        Text(catalogDisclosure)
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
            .navigationDestination(for: ShoppingEngagementDestination.self) { destination in
                shoppingEngagementDestination(destination)
            }
            .onAppear {
                #if DEBUG
                ShoppingPerformanceLog.mark("ShoppingView onAppear products=\(products.count) loading=\(isCatalogLoadInFlight)")
                #endif
                showExpandedDisclosure = store.affiliateDisclosureExpanded
                recommendationBasis = Set(basis(from: RecommendationRationaleBuilder.preferences(from: profileStore.currentProfile)))
            }
        }
    }

    private var shoppingLoadingShell: some View {
        VStack(alignment: .leading, spacing: 18) {
            stylistFeedCard
            discoveryShortcutRail
            catalogLoadingState
            browseHeader
            alertControls
            disclosureSummary
            catalogDisclosureFooter
        }
    }

    private var catalogLoadingState: some View {
        HStack(spacing: 10) {
            ProgressView()
            VStack(alignment: .leading, spacing: 3) {
                Text("Preparing your Shop")
                    .font(.headline)
                Text("Catalog sections will fill in as local or cached products are ready.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .appCard(.shop)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Preparing your shopping catalog")
    }

    private var catalogRefreshNotice: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Refreshing catalog")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Refreshing shopping catalog")
    }

    private var stylistFeedCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                showEngagement(.todaysStyleBrief)
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(Color.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("AI Stylist Feed")
                            .font(.title3)
                            .fontWeight(.bold)
                            .accessibilityAddTraits(.isHeader)
                        Text(stylistGreeting)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open Today's Style Brief")
            .accessibilityHint("Opens Today's Style Brief")

            VStack(alignment: .leading, spacing: 8) {
                ForEach(stylistFeedLines, id: \.self) { line in
                    Button {
                        showEngagement(.recommendationInsight)
                    } label: {
                        Label(line, systemImage: "checkmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .accessibilityHint("Explains why this recommendation appears")
                }
            }

            HStack(spacing: 10) {
                Button {
                    showBrowseFilters = false
                } label: {
                    Label("Shop recommended", systemImage: "wand.and.stars")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    withAnimation(.snappy) {
                        showBrowseFilters.toggle()
                    }
                } label: {
                    Image(systemName: showBrowseFilters ? "slider.horizontal.3" : "line.3.horizontal.decrease.circle")
                        .font(.headline)
                        .frame(width: 44, height: 36)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(showBrowseFilters ? "Hide filters" : "Show filters")
            }
        }
        .padding()
        .appCard(.shop, radius: 14)
    }

    private var discoveryShortcutRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                discoveryShortcut(title: "Recommended", icon: "sparkles", count: recommendations.count, destination: .recommendedForYou)
                discoveryShortcut(title: "Catalog Picks", icon: "square.grid.2x2.fill", count: trendingProducts.count, destination: .popularPicks)
                discoveryShortcut(title: "Deals", icon: "tag.fill", count: dealProducts.count, destination: .deals)
                discoveryShortcut(title: "Complete Looks", icon: "square.grid.2x2.fill", count: completeLookProducts.count, destination: .completeLooks)
                discoveryShortcut(title: "Saved", icon: "heart.fill", count: store.savedFavorites.count + store.wishlistProductIDs.count, destination: .savedHub)
            }
            .padding(.vertical, 1)
        }
    }

    private func discoveryShortcut(title: String, icon: String, count: Int, destination: ShoppingEngagementDestination) -> some View {
        Button {
            showEngagement(destination)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundStyle(Color.orange)
                Text(title)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
                Text("\(count) picks")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 112, alignment: .leading)
            .padding(12)
            .appCard(.shop, radius: 10)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityHint("Opens \(title)")
    }

    private var seasonalCollections: some View {
        productRail(
            title: "Seasonal Collections",
            subtitle: "Quick edits for work, travel, warm weather, and weekends.",
            products: seasonalProducts
        )
    }

    private var completeLookPreview: some View {
        Group {
            if !completeLookProducts.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Button {
                        showEngagement(.completeLooks)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Complete Outfit Shopping")
                                    .font(.headline)
                                    .fontWeight(.bold)
                                Text("Build a full look around the strongest current pick.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("Score-ready")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Color.green.opacity(0.16))
                                .clipShape(Capsule())
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open Complete Looks")
                    .accessibilityHint("Opens Complete Looks")

                    HStack(spacing: 8) {
                        ForEach(completeLookProducts.prefix(5)) { product in
                            Button {
                                openProductExternally(product)
                            } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: categoryIcon(for: product))
                                        .font(.headline)
                                        .foregroundStyle(Color.orange)
                                        .frame(width: 38, height: 38)
                                        .background(Color.orange.opacity(0.12))
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                    Text(product.subcategory.capitalized)
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                        .lineLimit(2)
                                        .minimumScaleFactor(0.75)
                                }
                                .frame(maxWidth: .infinity, minHeight: 78)
                                .padding(8)
                                .background(Color(.secondarySystemBackground).opacity(0.78))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if let lead = completeLookProducts.first {
                        Text(rationale(for: lead, reasonFacts: nil).headline)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding()
                .appCard(.shop, radius: 14)
            }
        }
    }

    private var styleProgressCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                showEngagement(.styleDNA)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Your Style DNA")
                            .font(.headline)
                            .fontWeight(.bold)
                        Text(styleLevelText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("Level \(styleLevel)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.orange.opacity(0.16))
                        .clipShape(Capsule())
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open Your Style DNA")
            .accessibilityHint("Opens Your Style DNA")

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 8)], spacing: 8) {
                statTile(title: "Scans", value: "\(outfitMemoryStore.memories.count)", icon: "camera.viewfinder", destination: .scanHistory)
                statTile(title: "Favorites", value: "\(store.savedFavorites.count)", icon: "heart.fill", destination: .favoritesHub)
                statTile(title: "Wishlist", value: "\(store.wishlistProductIDs.count)", icon: "bookmark.fill", destination: .wishlist)
                statTile(title: "Top color", value: topColorText, icon: "paintpalette.fill", destination: .colorProfile)
            }
        }
        .padding()
        .appCard(.shop, radius: 14)
    }

    private func statTile(title: String, value: String, icon: String, destination: ShoppingEngagementDestination) -> some View {
        Button {
            showEngagement(destination)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(Color.orange)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(value)
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(Color(.secondarySystemBackground).opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel("\(title), \(value)")
    }

    private var browseHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(browseMode == .deck ? "Swipe Products" : "Browse Categories")
                        .font(.headline)
                        .fontWeight(.bold)
                    Text(browseMode == .deck ? "Swipe right to save, left to skip." : (showBrowseFilters ? "Filters are open." : "Search and filters are collapsed until you need them."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    withAnimation(.snappy) {
                        showBrowseFilters.toggle()
                    }
                } label: {
                    Label(showBrowseFilters ? "Hide" : "Filters", systemImage: "slider.horizontal.3")
                        .font(.caption)
                        .fontWeight(.bold)
                }
                .buttonStyle(.bordered)
                .disabled(browseMode == .deck)
            }

            Picker("Browse mode", selection: $browseMode) {
                ForEach(ShoppingBrowseMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.icon)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .styleMatchOnChange(of: browseMode) { _ in
                normalizeDeckIndex()
            }
        }
    }

    private var filteredDiscoveryState: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color.orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Let's widen the styling lens")
                        .font(.headline)
                    Text("Your current filters are narrow. These picks keep the session useful while you adjust them.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            productRail(
                title: "Recommended for You",
                subtitle: "Based on saved scans, favorites, color signals, and budget settings.",
                products: fallbackDiscoveryProducts
            )
        }
        .padding()
    }

    @ViewBuilder
    private func shoppingEngagementDestination(_ destination: ShoppingEngagementDestination) -> some View {
        switch destination {
        case .todaysStyleBrief:
            engagementScroll(title: "Today's Style Brief") {
                engagementSummaryCard(
                    icon: "sparkles",
                    title: stylistGreeting,
                    rows: stylistFeedLines.isEmpty ? ["Scan outfits and save products to personalize this brief."] : stylistFeedLines
                )
                if !recommendations.isEmpty {
                    productRail(
                        title: "Recommended Items",
                        subtitle: recommendationSectionSubtitle,
                        recommendations: Array(recommendations.prefix(8))
                    )
                }
                if !completeLookProducts.isEmpty {
                    productRail(
                        title: "Complete Your Outfit",
                        subtitle: "Built from the current strongest local catalog pick.",
                        products: completeLookProducts
                    )
                }
                if !dealProducts.isEmpty {
                    productRail(
                        title: "Deals",
                        subtitle: "Active sale items from the current safe catalog.",
                        products: Array(dealProducts.prefix(8))
                    )
                }
                if recommendations.isEmpty && completeLookProducts.isEmpty && dealProducts.isEmpty {
                    engagementEmptyState(
                        icon: "bag",
                        title: "Your brief is still warming up",
                        message: "Browse products, scan an outfit, or save favorites to make this feed more personal.",
                        actionTitle: "Browse Products",
                        action: openBrowse
                    )
                }
            }
        case .recommendationInsight:
            engagementScroll(title: "Why This Appears") {
                engagementSummaryCard(
                    icon: "checkmark.circle.fill",
                    title: "Recommendation signals",
                    rows: stylistFeedLines.isEmpty ? ["StyleMatch uses saved scans, favorites, wishlist, budget, and safe catalog data when available."] : stylistFeedLines
                )
                engagementSummaryCard(
                    icon: "lock.shield.fill",
                    title: "What is not used",
                    rows: ["No score changes are made here.", "No new AI call is made from this shopping feed.", "Unsupported trend or price-drop claims are hidden."]
                )
            }
        case .recommendedForYou:
            engagementScroll(title: "Recommended For You") {
                if !recommendations.isEmpty {
                    productRail(
                        title: "Recommended Items",
                        subtitle: recommendationSectionSubtitle,
                        recommendations: Array(recommendations.prefix(8))
                    )
                }
                if !feedbackRecommendedProducts.isEmpty {
                    productRail(
                        title: "Wardrobe Matches",
                        subtitle: "Ranked from outfits you wore, liked, and saved on this device.",
                        products: feedbackRecommendedProducts.map(\.product)
                    )
                }
                if !completeLookProducts.isEmpty {
                    productRail(
                        title: "Complete-the-look Items",
                        subtitle: "Companion pieces from the current safe catalog.",
                        products: completeLookProducts
                    )
                }
                if !dealProducts.isEmpty {
                    productRail(
                        title: "Deals",
                        subtitle: "Sale items that match your current shopping settings.",
                        products: Array(dealProducts.prefix(8))
                    )
                }
                if recommendations.isEmpty && feedbackRecommendedProducts.isEmpty && completeLookProducts.isEmpty && dealProducts.isEmpty {
                    engagementEmptyState(
                        icon: "wand.and.stars",
                        title: "No personalized picks yet",
                        message: "Scan an outfit, save favorites, or browse the catalog to give StyleMatch useful local signals.",
                        actionTitle: "Browse Products",
                        action: openBrowse
                    )
                }
            }
        case .popularPicks:
            engagementScroll(title: "Catalog Picks") {
                if trendingProducts.isEmpty {
                    engagementEmptyState(
                        icon: "flame",
                        title: "No catalog picks available",
                        message: "The safe catalog is still loading or empty.",
                        actionTitle: "Browse Products",
                        action: openBrowse
                    )
                } else {
                    productRail(
                        title: "Catalog Picks",
                        subtitle: "Useful catalog starters while StyleMatch learns more from local wardrobe signals.",
                        products: trendingProducts
                    )
                }
            }
        case .deals:
            engagementScroll(title: "Deals") {
                if !saleAlerts.isEmpty {
                    saleAlertSections
                }
                if !dealProducts.isEmpty {
                    productRail(
                        title: "Active Sale Items",
                        subtitle: "Products with current sale pricing in the safe catalog.",
                        products: Array(dealProducts.prefix(8))
                    )
                }
                if saleAlerts.isEmpty && dealProducts.isEmpty {
                    engagementEmptyState(
                        icon: "tag",
                        title: "No active deals found",
                        message: "Save favorites or wishlist items so sale alerts have something useful to watch.",
                        actionTitle: "Open Price Alerts",
                        action: { showEngagement(.priceAlerts) }
                    )
                }
            }
        case .completeLooks:
            engagementScroll(title: "Complete Looks") {
                if completeLookProducts.isEmpty {
                    engagementEmptyState(
                        icon: "square.grid.2x2",
                        title: "No complete-look set yet",
                        message: "Browse recommendations or scan outfits to help StyleMatch identify useful companion pieces.",
                        actionTitle: "Browse Products",
                        action: openBrowse
                    )
                } else {
                    productRail(
                        title: "Complete Your Outfit",
                        subtitle: "Companion products selected from the current safe catalog.",
                        products: completeLookProducts
                    )
                }
            }
        case .savedHub:
            engagementScroll(title: "Saved Shopping") {
                savedProductsSection(title: "Favorite Products", productIDs: store.savedFavorites)
                savedProductsSection(title: "Wishlist", productIDs: store.wishlistProductIDs)
                if !store.shoppingCardProductIDs.isEmpty {
                    savedProductsSection(title: "Legacy Shopping Cards", productIDs: store.shoppingCardProductIDs)
                }
                if store.savedFavorites.isEmpty && store.wishlistProductIDs.isEmpty && store.shoppingCardProductIDs.isEmpty {
                    engagementEmptyState(
                        icon: "heart",
                        title: "Nothing saved yet",
                        message: "Use Favorite or Wishlist on products you want to revisit.",
                        actionTitle: "Browse Products",
                        action: openBrowse
                    )
                }
            }
        case .styleDNA:
            engagementScroll(title: "Your Style DNA") {
                engagementSummaryCard(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "\(styleLevelText), Level \(styleLevel)",
                    rows: [
                        "\(outfitMemoryStore.memories.count) saved scans",
                        "\(store.savedFavorites.count) favorite products",
                        "\(store.wishlistProductIDs.count) wishlist items",
                        "Top color: \(topColorText)"
                    ]
                )
                NavigationLink(value: ShoppingEngagementDestination.styleXP) {
                    engagementRow(icon: "star.circle.fill", title: "Style XP", detail: "View level progress and milestones.")
                }
                .buttonStyle(.plain)
                NavigationLink(value: ShoppingEngagementDestination.colorProfile) {
                    engagementRow(icon: "paintpalette.fill", title: "Your Color Profile", detail: "See color signals from profile and saved scans.")
                }
                .buttonStyle(.plain)
            }
        case .scanHistory:
            engagementScroll(title: "Scan History") {
                if outfitMemoryStore.memories.isEmpty {
                    engagementEmptyState(
                        icon: "camera.viewfinder",
                        title: "No saved scans yet",
                        message: "Scan an outfit to build your local style history.",
                        actionTitle: "Scan Outfit",
                        action: { selectedTab = .scan }
                    )
                } else {
                    ForEach(outfitMemoryStore.memories.prefix(20)) { memory in
                        engagementRow(
                            icon: "camera.viewfinder",
                            title: memory.detectedStyle,
                            detail: memory.colors.prefix(3).joined(separator: ", ").nilIfEmpty ?? OutfitRecallService.relativeDateText(for: memory.scanDate)
                        )
                    }
                }
            }
        case .favoritesHub:
            engagementScroll(title: "Favorites") {
                savedProductsSection(title: "Favorite Products", productIDs: store.savedFavorites)
                engagementSummaryCard(
                    icon: "heart.fill",
                    title: "Favorite Brands",
                    rows: favoriteBrandRows
                )
            }
        case .wishlist:
            engagementScroll(title: "Wishlist") {
                savedProductsSection(title: "Wishlist Products", productIDs: store.wishlistProductIDs)
                if store.wishlistProductIDs.isEmpty {
                    engagementEmptyState(
                        icon: "bookmark",
                        title: "Your wishlist is empty",
                        message: "Tap Wishlist on products you may want later.",
                        actionTitle: "Browse Products",
                        action: openBrowse
                    )
                }
            }
        case .colorProfile:
            engagementScroll(title: "Your Color Profile") {
                engagementSummaryCard(
                    icon: "paintpalette.fill",
                    title: topColorText == "Learning" ? "Color signals are still learning" : "Top color: \(topColorText)",
                    rows: colorProfileRows
                )
                let matches = productsMatchingTopColor
                if !matches.isEmpty {
                    productRail(
                        title: "Catalog Matches",
                        subtitle: "Products whose available colors overlap your current top color.",
                        products: Array(matches.prefix(8))
                    )
                }
            }
        case .styleXP:
            engagementScroll(title: "Style XP") {
                engagementSummaryCard(
                    icon: "star.circle.fill",
                    title: "\(styleLevelText), Level \(styleLevel)",
                    rows: styleXPRows
                )
                ProgressView(value: Double(styleLevel), total: 20)
                    .tint(Color.orange)
                    .accessibilityLabel("Style level \(styleLevel) of 20")
                engagementSummaryCard(
                    icon: "lock.fill",
                    title: "Milestones",
                    rows: styleMilestoneRows
                )
            }
        case .priceAlerts:
            engagementScroll(title: "Price Alerts") {
                engagementSummaryCard(
                    icon: alertsEnabled ? "bell.badge.fill" : "bell.slash.fill",
                    title: alertsEnabled ? "Sale notifications are on" : "Sale notifications are off",
                    rows: priceAlertRows
                )
                if !saleAlerts.isEmpty {
                    saleAlertSections
                } else {
                    engagementEmptyState(
                        icon: "tag",
                        title: "No alerts ready",
                        message: "Favorite or wishlist products to watch catalog changes locally.",
                        actionTitle: "Browse Products",
                        action: openBrowse
                    )
                }
            }
        case .disclosure:
            engagementScroll(title: "Shopping Through StyleMatch Pro") {
                engagementSummaryCard(
                    icon: "info.circle.fill",
                    title: "How product links work",
                    rows: disclosureRows
                )
            }
        }
    }

    private func engagementScroll<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content()
            }
            .padding()
        }
        .scrollContentBackground(.hidden)
        .appScreenBackground(.shop)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func engagementSummaryCard(icon: String, title: String, rows: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
                .fontWeight(.bold)
            ForEach(rows.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }, id: \.self) { row in
                Label(row, systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .appCard(.shop, radius: 14)
        .accessibilityElement(children: .combine)
    }

    private func engagementRow(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Color.orange)
                .frame(width: 34, height: 34)
                .background(Color.orange.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.bold)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .appCard(.shop, radius: 10)
        .contentShape(Rectangle())
    }

    private func engagementEmptyState(icon: String, title: String, message: String, actionTitle: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color.orange)
            Text(title)
                .font(.headline)
                .fontWeight(.bold)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button(actionTitle, action: action)
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .appCard(.shop, radius: 14)
    }

    @ViewBuilder
    private func savedProductsSection(title: String, productIDs: [String]) -> some View {
        let savedProducts = productIDs.compactMap { id in products.first { $0.id == id } }
        if !savedProducts.isEmpty {
            productRail(
                title: title,
                subtitle: "Saved on this device.",
                products: savedProducts
            )
        }
    }

    private var swipeDeckSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let product = currentDeckProduct {
                swipeProductCard(product)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.orange)
                    Text(products.isEmpty ? "No products available" : "You're caught up")
                        .font(.headline)
                    Text(products.isEmpty ? "The catalog is empty right now. Check back shortly." : "You've reviewed the current catalog. Switch back to Browse anytime.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .appCard(.shop, radius: 14)
            }
        }
    }

    private func swipeProductCard(_ product: AffiliateProduct) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ShoppingProductImage(imageURL: product.remoteImageRequestURL)
                .frame(height: 260)
                .clipShape(RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 6) {
                Text(product.brand ?? product.retailer.name)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(product.name)
                    .font(.title3)
                    .fontWeight(.bold)
                    .lineLimit(3)

                Text(deckPriceText(for: product))
                    .font(.headline)
                    .foregroundStyle(Color.orange)
            }

            HStack(spacing: 12) {
                Button {
                    skipCurrentDeckProduct()
                } label: {
                    Label("Skip", systemImage: "xmark")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 46)
                }
                .buttonStyle(.bordered)

                Button {
                    likeCurrentDeckProduct()
                } label: {
                    Label(store.savedFavorites.contains(product.id) ? "Saved" : "Like", systemImage: "heart.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 46)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .appCard(.shop, radius: 16)
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    if value.translation.width > 72 {
                        likeCurrentDeckProduct()
                    } else if value.translation.width < -72 {
                        skipCurrentDeckProduct()
                    }
                }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(productAccessibilitySummary(product, action: "Like or skip product"))
        .accessibilityHint("Use the Like and Skip buttons, or swipe right to like and left to skip")
    }

    private var feedbackRecommendedSection: some View {
        productRail(
            title: "Recommended for You",
            subtitle: "Ranked from outfits you wore, liked, and saved on this device.",
            products: feedbackRecommendedProducts.map(\.product)
        )
    }

    private func productRail(title: String, subtitle: String, recommendations: [ProductRecommendation]) -> some View {
        productRail(
            title: title,
            subtitle: subtitle,
            products: recommendations.map(\.product),
            reasonFacts: Dictionary(uniqueKeysWithValues: recommendations.map { ($0.product.id, $0.reasonFacts) }),
            ranks: Dictionary(uniqueKeysWithValues: recommendations.map { ($0.product.id, $0.rank) })
        )
    }

    private func productRail(
        title: String,
        subtitle: String,
        products: [AffiliateProduct],
        reasonFacts: [String: ProductRecommendationReasonFacts] = [:],
        ranks: [String: Int] = [:]
    ) -> some View {
        Group {
            if !products.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.headline)
                            .fontWeight(.bold)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(products.prefix(8)) { product in
                                compactProductCard(
                                    product,
                                    reasonFacts: reasonFacts[product.id],
                                    rank: ranks[product.id]
                                )
                            }
                        }
                        .padding(.leading, 2)
                        .padding(.trailing, 16)
                        .padding(.vertical, 1)
                    }
                    .scrollDisabled(products.count <= 1)
                }
            }
        }
    }

    private func compactProductCard(_ product: AffiliateProduct, reasonFacts: ProductRecommendationReasonFacts?, rank: Int?) -> some View {
        let rationale = rationale(for: product, reasonFacts: reasonFacts)
        let viewModel = AffiliateProductViewModel(
            product: product,
            reasonText: rationale.headline,
            matchPercent: matchPercent(for: rank, hasReason: !rationale.isTrendingFallback)
        )

        return Button {
            openProductExternally(product)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ShoppingProductImage(imageURL: product.remoteImageRequestURL)
                    .frame(width: 168, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                Text(viewModel.name)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .frame(minHeight: 52, alignment: .topLeading)
                Text(viewModel.priceText)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                Text(rationale.headline)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack {
                    Text(viewModel.retailerName)
                        .font(.caption2)
                        .fontWeight(.bold)
                    Spacer()
                    if let sale = viewModel.saleBadgeText {
                        Text(sale)
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(.red)
                    }
                }
            }
            .frame(width: 168, alignment: .leading)
            .padding(10)
            .appCard(.shop, radius: 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var disclosureSummary: some View {
        Button {
            showEngagement(.disclosure)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("Shopping through StyleMatch Pro")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Learn more")
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
            }
            .lineLimit(1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open shopping disclosure")
        .accessibilityHint("Opens shopping disclosure")
    }

    private var catalogDisclosureFooter: some View {
        Text(catalogDisclosure)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
            .accessibilityLabel("Affiliate disclosure: \(catalogDisclosure)")
    }

    private var recommendationBasisControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recommendations")
                .font(.subheadline)
                .fontWeight(.bold)
                .accessibilityAddTraits(.isHeader)
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
            Button {
                showEngagement(.priceAlerts)
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: alertsEnabled ? "bell.badge.fill" : "bell.slash.fill")
                        .foregroundStyle(alertsEnabled ? .orange : .secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(alertsEnabled ? "Sale notifications are on" : "Get notified when your favorites go on sale")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundStyle(.primary)
                        Text(notificationDenied ? "Notifications are off in iOS Settings. In-app sale badges will still show." : "StyleMatch Pro checks approved catalog data on this phone and sends local alerts only after new sale changes.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open Price Alerts")
            .accessibilityHint("Shows saved alerts and recent sale changes")
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
                VStack(alignment: .trailing, spacing: 6) {
                    Button("Turn On") {
                        Task { await optInSaleNotifications() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    if notificationDenied {
                        Button("Settings") {
                            #if canImport(UIKit)
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                            #endif
                        }
                        .font(.caption)
                    }
                }
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
                            openProductExternally(product)
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
        let product = products.first { $0.id == alert.productID }
        let content = HStack(alignment: .top, spacing: 10) {
            Image(systemName: alert.trigger == .backInStock ? "shippingbox.fill" : "tag.fill")
                .foregroundStyle(.red)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 6) {
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
                if let product {
                    Label(AffiliateProductViewModel(product: product).actionTitle, systemImage: "arrow.up.forward.app")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.orange)
                }
            }
        }
        .contentShape(Rectangle())

        return Group {
            if let product {
                Button {
                    openProductExternally(product)
                } label: {
                    content
                }
                .buttonStyle(.plain)
            } else {
                content
            }
        }
        .padding()
        .appCard(.shop, radius: 10)
    }

    private var categoryChips: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    categoryButton(nil, title: "All")
                    ForEach(ProductCategory.allCases) { category in
                        categoryButton(category, title: category.displayName)
                    }
                }
                .padding(.trailing, 12)
            }
            Text("\(searchResults.count) \(searchResults.count == 1 ? "item" : "items")")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .accessibilityLabel("\(searchResults.count) products in the selected category")
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
                    ForEach(primarySupportedStores.prefix(20)) { store in
                        storeButton(store.name, title: store.name)
                    }
                    ForEach(comingSoonSupportedStores.prefix(max(0, 20 - primarySupportedStores.count))) { store in
                        storeButton(store.name, title: store.name, isComingSoon: true)
                    }
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: 8)], spacing: 8) {
                filterField("Color", text: bindingString(\.color), relaxedFilter: .color)
                filterField("Size", text: bindingString(\.size), relaxedFilter: .size)
                filterField("Style", text: bindingString(\.style), relaxedFilter: .style)
                filterField("Gender", text: bindingString(\.genderPresentation))
                filterField("Occasion", text: bindingString(\.occasion), relaxedFilter: .occasion)
                filterField("Max $", text: Binding(
                    get: { searchCriteria.maximumPrice.map { "\($0)" } ?? "" },
                    set: { searchCriteria.maximumPrice = Decimal(string: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                ), relaxedFilter: .maxPrice)
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
        relaxedSearchResult.displayedResults
    }

    private var baseSearchProducts: [AffiliateProduct] {
        liveSearchProducts ?? products
    }

    private var searchCatalogProducts: [AffiliateProduct] {
        budgetFiltered(baseSearchProducts)
    }

    private var relaxedSearchResult: ShoppingSearchEngine.RelaxedFilterResult {
        var criteria = searchCriteria
        criteria.category = selectedCategory
        return ShoppingSearchEngine.relaxedFilter(products: searchCatalogProducts, criteria: criteria)
    }

    private var availableStoreNames: Set<String> {
        Set(baseSearchProducts.map { $0.retailer.name.lowercased() })
    }

    private var primarySupportedStores: [SupportedStore] {
        ShoppingSearchEngine
            .filterStores(supportedStores, query: searchCriteria.query)
            .filter { availableStoreNames.contains($0.name.lowercased()) }
    }

    private var comingSoonSupportedStores: [SupportedStore] {
        ShoppingSearchEngine
            .filterStores(supportedStores, query: searchCriteria.query)
            .filter { !availableStoreNames.contains($0.name.lowercased()) }
    }

    private var selectedSupportedStore: SupportedStore? {
        guard let storeName = searchCriteria.storeName, !storeName.isEmpty else { return nil }
        return supportedStores.first { $0.name.caseInsensitiveCompare(storeName) == .orderedSame }
    }

    private var isSelectedStoreUnavailable: Bool {
        guard let storeName = searchCriteria.storeName, !storeName.isEmpty else { return false }
        return relaxedSearchResult.exactResults.isEmpty
            && !availableStoreNames.contains(storeName.lowercased())
    }

    private var recommendationSectionTitle: String {
        recommendations.allSatisfy { rationale(for: $0.product, reasonFacts: $0.reasonFacts).isTrendingFallback } ? "Catalog Picks" : "Recommended for You"
    }

    private var recommendationSectionSubtitle: String {
        recommendations.allSatisfy { rationale(for: $0.product, reasonFacts: $0.reasonFacts).isTrendingFallback }
            ? "A useful starting point while StyleMatch learns more from your wardrobe."
            : "Ranked from saved scans, favorite signals, budget settings, and shopping history."
    }

    private var stylistGreeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:
            return "Good morning. Here is what your wardrobe suggests today."
        case 12..<17:
            return "Good afternoon. Here is what your wardrobe suggests today."
        default:
            return "Good evening. Here is what your wardrobe suggests today."
        }
    }

    private var stylistFeedLines: [String] {
        var lines: [String] = []
        let memories = outfitMemoryStore.memories
        if let color = topColorText.nilIfPlaceholder {
            lines.append("You wear \(color.lowercased()) often, so matching pieces are prioritized.")
        }
        if let gap = closetGapText {
            lines.append(gap)
        }
        if !dealProducts.isEmpty {
            lines.append("\(dealProducts.count) sale picks fit your current shopping settings.")
        }
        if recommendations.contains(where: { $0.reasonFacts.rule == "complement" }) {
            lines.append("Several picks complete outfits you have already scanned.")
        } else if !recommendations.isEmpty {
            lines.append("The first picks are ready before you search.")
        } else if memories.isEmpty {
            lines.append("Scan outfits and save favorites to make this feed more personal.")
        }
        return Array(lines.prefix(4))
    }

    private var topColorText: String {
        if let favorite = profileStore.currentProfile.favoriteColors.first?.trimmingCharacters(in: .whitespacesAndNewlines),
           !favorite.isEmpty {
            return favorite.capitalized
        }
        let colors = outfitMemoryStore.memories.flatMap(\.colors)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        if let top = Dictionary(grouping: colors, by: { $0 })
            .max(by: { first, second in first.value.count < second.value.count })?.key {
            return top.capitalized
        }
        return "Learning"
    }

    private var colorProfileRows: [String] {
        var rows: [String] = []
        if topColorText == "Learning" {
            rows.append("Scan outfits or save favorite colors to build a color profile.")
        } else {
            rows.append("Current top color: \(topColorText)")
        }
        let scanColors = Set(outfitMemoryStore.memories.flatMap(\.colors).map { $0.capitalized })
        if !scanColors.isEmpty {
            rows.append("Seen in scans: \(Array(scanColors).sorted().prefix(4).joined(separator: ", "))")
        }
        let profileColors = profileStore.currentProfile.favoriteColors.map { $0.capitalized }
        if !profileColors.isEmpty {
            rows.append("Profile favorites: \(profileColors.prefix(4).joined(separator: ", "))")
        }
        return rows
    }

    private var productsMatchingTopColor: [AffiliateProduct] {
        guard let topColor = topColorText.nilIfPlaceholder?.lowercased() else { return [] }
        return budgetFiltered(products).filter { product in
            let colors = product.colors + (product.availableColors ?? [])
            return colors.contains { $0.localizedCaseInsensitiveContains(topColor) }
        }
    }

    private var favoriteBrandRows: [String] {
        let brands = store.savedFavorites
            .compactMap { id in products.first { $0.id == id }?.brand }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let grouped = Dictionary(grouping: brands, by: { $0 })
            .map { brand, values in "\(brand): \(values.count)" }
            .sorted()
        return grouped.isEmpty ? ["Favorite brands appear after you save products with brand data."] : grouped
    }

    private var priceAlertRows: [String] {
        var rows = [
            "\(store.savedFavorites.count) favorite products watched",
            "\(store.wishlistProductIDs.count) wishlist products watched",
            "\(store.cartProductIDs.count) legacy cart products watched",
            "\(store.shoppingCardProductIDs.count) legacy shopping cards watched"
        ]
        if !store.recentSaleEvents.isEmpty {
            rows.append("\(store.recentSaleEvents.count) recent sale events on this device")
        }
        if !store.saleNotificationHistory.isEmpty {
            rows.append("\(store.saleNotificationHistory.count) local sale notifications recorded")
        }
        return rows
    }

    private var styleXPRows: [String] {
        [
            "\(outfitMemoryStore.memories.count) saved scans contribute to style XP",
            "\(store.savedFavorites.count) favorites contribute to shopping signal",
            "\(store.wishlistProductIDs.count) wishlist items contribute to planning signal",
            "Progress is local and does not change outfit scores"
        ]
    }

    private var styleMilestoneRows: [String] {
        [
            styleLevel >= 5 ? "Unlocked: Fashion Expert" : "Locked: Fashion Expert at level 5",
            styleLevel >= 12 ? "Unlocked: Advanced wardrobe signals" : "Locked: Advanced wardrobe signals at level 12",
            styleLevel >= 20 ? "Unlocked: Trendsetter" : "Locked: Trendsetter at level 20"
        ]
    }

    private var disclosureRows: [String] {
        [
            catalogDisclosure,
            "StyleMatch uses approved catalog links and local shopping signals.",
            "Retailers handle purchase, fulfillment, returns, support, pricing, and availability.",
            "Recommendations are limited by the current safe catalog and locally available profile, scan, and shopping data."
        ]
    }

    private var closetGapText: String? {
        let scannedCategories = Set(outfitMemoryStore.memories.flatMap(\.garmentRecords).map { $0.garmentCategory.lowercased() })
        if !scannedCategories.contains("shoes") {
            return "Shoes look like the next useful closet gap to fill."
        }
        if !scannedCategories.contains("belt") && products.contains(where: { $0.subcategory.localizedCaseInsensitiveContains("belt") }) {
            return "A belt could help finish more complete looks."
        }
        if !scannedCategories.contains("jacket") && products.contains(where: { $0.subcategory.localizedCaseInsensitiveContains("blazer") || $0.subcategory.localizedCaseInsensitiveContains("jacket") }) {
            return "A lightweight layer would expand your outfit options."
        }
        return nil
    }

    private var trendingProducts: [AffiliateProduct] {
        derivedCatalogContent.trendingProducts
    }

    private var dealProducts: [AffiliateProduct] {
        derivedCatalogContent.dealProducts
    }

    private var seasonalProducts: [AffiliateProduct] {
        derivedCatalogContent.seasonalProducts
    }

    private var completeLookProducts: [AffiliateProduct] {
        derivedCatalogContent.completeLookProducts
    }

    private var fallbackDiscoveryProducts: [AffiliateProduct] {
        let recommended = recommendations.map(\.product)
        let combined = recommended + dealProducts + trendingProducts + seasonalProducts
        var seen = Set<String>()
        return Array(combined.filter { seen.insert($0.id).inserted }.prefix(8))
    }

    private var feedbackRecommendedProducts: [ShoppingFeedbackRankedProduct] {
        derivedCatalogContent.feedbackRecommendedProducts
    }

    private var deckProductIDs: [String] {
        products.map(\.id)
    }

    private var currentDeckProduct: AffiliateProduct? {
        guard deckIndex < products.count else {
            return nil
        }
        return products[deckIndex]
    }

    private var styleLevel: Int {
        min(20, max(1, 1 + outfitMemoryStore.memories.count / 4 + store.savedFavorites.count / 3 + store.wishlistProductIDs.count / 5))
    }

    private var styleLevelText: String {
        switch styleLevel {
        case 1..<5:
            return "Stylist"
        case 5..<12:
            return "Fashion Expert"
        default:
            return "Trendsetter"
        }
    }

    private static func makeDerivedCatalogContent(
        catalog: [AffiliateProduct],
        eligibleCatalog: [AffiliateProduct],
        recommendations: [ProductRecommendation],
        memories: [OutfitMemory]
    ) -> ShoppingDerivedCatalogContent {
        let trending = ShoppingRecommendationEngine.popularFallbackRecommendations(catalog: eligibleCatalog, limit: 8)
            .map(\.product)
        let deals = eligibleCatalog
            .filter { product in
                guard product.salePrice != nil else { return false }
                return (product.saleEndsAt ?? .distantFuture) > Date()
            }
            .sorted { lhs, rhs in
                let lhsDiscount = Self.discountAmountValue(lhs) ?? 0
                let rhsDiscount = Self.discountAmountValue(rhs) ?? 0
                if lhsDiscount == rhsDiscount {
                    return lhs.name < rhs.name
                }
                return lhsDiscount > rhsDiscount
            }
        let seasonalTerms = ["summer", "travel", "vacation", "wedding", "office", "work", "rain", "beach"]
        let filteredSeasonal = eligibleCatalog.filter { product in
            let text = ([product.name, product.subcategory] + product.tags + (product.occasionTags ?? []))
                .joined(separator: " ")
                .lowercased()
            return seasonalTerms.contains { text.contains($0) }
        }
        let seasonal = Array((filteredSeasonal.isEmpty ? trending : filteredSeasonal).prefix(8))

        let completeLook: [AffiliateProduct]
        if let lead = recommendations.first?.product ?? trending.first {
            let companions = CatalogProductComplementaryPieceRecommender().companions(for: lead, catalog: eligibleCatalog, limit: 6)
            var seen = Set<String>()
            completeLook = ([lead] + companions).filter { product in
                seen.insert(product.id).inserted
            }
        } else {
            completeLook = []
        }

        return ShoppingDerivedCatalogContent(
            trendingProducts: trending,
            dealProducts: deals,
            seasonalProducts: seasonal,
            completeLookProducts: completeLook,
            feedbackRecommendedProducts: ShoppingFeedbackProductRanker.positiveRecommendations(
                from: eligibleCatalog,
                memories: memories,
                minimumCount: 3
            )
        )
    }

    private static func discountAmountValue(_ product: AffiliateProduct) -> Decimal? {
        guard let price = product.price,
              let salePrice = product.salePrice,
              price > salePrice else {
            return nil
        }
        return price - salePrice
    }

    private func hasActiveSale(_ product: AffiliateProduct) -> Bool {
        guard product.salePrice != nil else { return false }
        return (product.saleEndsAt ?? .distantFuture) > Date()
    }

    private func openBrowse() {
        engagementPath.removeAll()
        browseMode = .browse
        showBrowseFilters = false
    }

    private func showEngagement(_ destination: ShoppingEngagementDestination) {
        guard engagementPath.last != destination else { return }
        engagementPath.append(destination)
    }

    private func categoryCountText(for category: ProductCategory?) -> String {
        var criteria = searchCriteria
        criteria.category = category
        let count = ShoppingSearchEngine.filter(products: budgetFiltered(liveSearchProducts ?? products), criteria: criteria).count
        return "\(count) \(count == 1 ? "item" : "items")"
    }

    private func discountAmount(_ product: AffiliateProduct) -> Decimal? {
        guard let price = product.price,
              let salePrice = product.salePrice,
              price > salePrice else {
            return nil
        }
        return price - salePrice
    }

    private func likeCurrentDeckProduct() {
        var deck = ShoppingSwipeDeckState(productIDs: deckProductIDs, currentIndex: deckIndex)
        deck.swipeRight(using: store)
        deckIndex = deck.currentIndex
        reloadRecommendations()
    }

    private func skipCurrentDeckProduct() {
        var deck = ShoppingSwipeDeckState(productIDs: deckProductIDs, currentIndex: deckIndex)
        deck.swipeLeft()
        deckIndex = deck.currentIndex
    }

    private func normalizeDeckIndex() {
        deckIndex = min(max(0, deckIndex), products.count)
    }

    private func deckPriceText(for product: AffiliateProduct) -> String {
        if let salePrice = product.salePrice {
            return currency(salePrice)
        }
        if let price = product.price {
            return currency(price)
        }
        return "Price unavailable"
    }

    private func categoryIcon(for product: AffiliateProduct) -> String {
        let text = "\(product.category.displayName) \(product.subcategory) \(product.name)".lowercased()
        if text.contains("shoe") || text.contains("sneaker") || text.contains("boot") {
            return "shoe.2.fill"
        }
        if text.contains("watch") {
            return "applewatch"
        }
        if text.contains("belt") {
            return "circle.grid.cross.fill"
        }
        if text.contains("sunglass") {
            return "sunglasses.fill"
        }
        if text.contains("jacket") || text.contains("blazer") || text.contains("coat") {
            return "jacket.fill"
        }
        if product.category == .accessories {
            return "sparkles"
        }
        return "tshirt.fill"
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .fontWeight(.bold)
    }

    private func relaxedFilterNotice(_ filter: ShoppingSearchEngine.RelaxableFilter) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .foregroundStyle(Color.orange)
            Text("No exact matches — showing results without your \(filter.displayName) filter")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .appCard(.shop, radius: 10)
    }

    private var selectedStoreUnavailableState: some View {
        let storeName = searchCriteria.storeName ?? "This retailer"
        let directoryStore = selectedSupportedStore
        let actionURL = directoryStore?.searchURL(for: searchCriteria.query) ?? directoryStore?.directAccessURL
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "storefront")
                    .foregroundStyle(Color.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text(storeName)
                        .font(.headline)
                    Text(directoryStore?.integrationLabel ?? "Catalog Integration Coming Soon")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.orange)
                    Text("New products are coming soon for \(storeName). StyleMatch Pro does not currently have live catalog products for this retailer, and we will not substitute products from another retailer.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let disclosure = directoryStore?.disclosureText?.nilIfEmpty {
                        Text(disclosure)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack(spacing: 10) {
                Button {
                    searchCriteria.storeName = nil
                } label: {
                    Label("Show All Products", systemImage: "bag")
                }
                .buttonStyle(.borderedProminent)

                if let actionURL {
                    Button {
                        openStoreDirectly(actionURL)
                    } label: {
                        Label("Open \(storeName)", systemImage: "safari")
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        searchCriteria.storeName = nil
                    } label: {
                        Label("Choose Another Store", systemImage: "storefront")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding()
        .appCard(.shop, radius: 10)
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
                .frame(minHeight: 44)
                .background((selectedCategory == category ? Color.orange.opacity(0.22) : Color(.secondarySystemBackground)))
                .clipShape(Capsule())
                .opacity(relaxedSearchResult.relaxedFilter == .category && category != nil && selectedCategory == category ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel("\(title), \(categoryCountText(for: category))")
    }

    private func storeButton(_ storeName: String?, title: String, isComingSoon: Bool = false) -> some View {
        Button {
            searchCriteria.storeName = storeName
        } label: {
            HStack(spacing: 6) {
                Text(title)
                if isComingSoon {
                    Text("Direct")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)
            .fontWeight(.semibold)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background((searchCriteria.storeName == storeName ? Color.orange.opacity(0.22) : Color(.secondarySystemBackground)))
            .clipShape(Capsule())
            .opacity(isComingSoon && searchCriteria.storeName != storeName ? 0.62 : 1)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel(isComingSoon ? "\(title), direct store access, catalog integration coming soon" : title)
    }

    private func openStoreDirectly(_ url: URL) {
        #if canImport(UIKit)
        UIApplication.shared.open(url, options: [:])
        #endif
    }

    private func filterField(_ title: String, text: Binding<String>, relaxedFilter: ShoppingSearchEngine.RelaxableFilter? = nil) -> some View {
        TextField(title, text: text)
            .textFieldStyle(.roundedBorder)
            .font(.caption)
            .opacity(relaxedSearchResult.relaxedFilter == relaxedFilter ? 0.45 : 1)
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
                openProductExternally(product)
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    ShoppingProductImage(imageURL: product.remoteImageRequestURL)
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
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(productAccessibilitySummary(product, action: viewModel.actionTitle))
            .accessibilityHint("Opens this product through the retailer link")

            whyRecommendationButton(product: product, rationale: rationale)

            Button {
                openProductExternally(product)
            } label: {
                Label(viewModel.actionTitle, systemImage: "arrow.up.forward.app")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            completeTheLookSection(for: product)

            HStack(spacing: 8) {
                productActionButton(
                    title: "Favorite",
                    systemImage: isFavoriteProduct(product) ? "heart.fill" : "heart",
                    isActive: isFavoriteProduct(product)
                ) {
                    toggleFavoriteProduct(product)
                }
                productActionButton(
                    title: "Wishlist",
                    systemImage: isWishlistProduct(product) ? "bookmark.fill" : "bookmark",
                    isActive: isWishlistProduct(product)
                ) {
                    toggleWishlistProduct(product)
                }
                productActionButton(
                    title: "Shop on \(viewModel.retailerName)",
                    systemImage: "arrow.up.forward.app",
                    isActive: false
                ) {
                    openProductExternally(product)
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
                        .accessibilityAddTraits(.isHeader)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(suggestions) { suggestion in
                                Button {
                                    openProductExternally(suggestion)
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

    private func isFavoriteProduct(_ product: AffiliateProduct) -> Bool {
        return store.savedFavorites.contains(product.id)
    }

    private func isWishlistProduct(_ product: AffiliateProduct) -> Bool {
        return store.wishlistProductIDs.contains(product.id)
    }

    private func productAccessibilitySummary(_ product: AffiliateProduct, action: String) -> String {
        let viewModel = AffiliateProductViewModel(product: product)
        let saleStatus = viewModel.saleBadgeText ?? (isRecentSaleEvent(productID: product.id) ? "New sale" : nil)
        return StyleMatchAccessibilityText.shoppingProductSummary(
            name: viewModel.name,
            retailer: viewModel.retailerName,
            price: viewModel.priceText,
            saleStatus: saleStatus,
            isFavorite: isFavoriteProduct(product),
            isWishlist: isWishlistProduct(product),
            action: action
        )
    }

    private func toggleFavoriteProduct(_ product: AffiliateProduct) {
        store.toggleFavorite(productID: product.id)
        refreshSaleAlerts()
    }

    private func toggleWishlistProduct(_ product: AffiliateProduct) {
        store.toggleWishlist(productID: product.id)
        refreshSaleAlerts()
    }

    private func productActionButton(title: String, systemImage: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption2)
                .fontWeight(.semibold)
                .labelStyle(.iconOnly)
                .frame(width: 44, height: 44)
                .foregroundStyle(isActive ? .orange : .secondary)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isActive ? "Selected" : "Not selected")
        .shoppingSelectedAccessibility(isActive)
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
                        Label(sheet.rationale.headline, systemImage: "checkmark.circle.fill")
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
                    preferenceToggle(.currentTrends, detail: "Use current catalog picks when your wardrobe history is limited.")
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
        let startedAt = CFAbsoluteTimeGetCurrent()
        let eligibleCatalog = budgetFiltered(products)
        let ranked = ShoppingRecommendationEngine.recommendations(
            currentGarments: [],
            currentColors: [],
            memories: currentRecommendationPreferences().usesWardrobeHistory ? outfitMemoryStore.memories : [],
            weather: nil,
            catalog: eligibleCatalog,
            dismissedProductIDs: store.dismissedProductIDs,
            recentlyViewedProductIDs: store.recentlyViewedProductIDs
        )
        let visibleRecommendations = ranked.isEmpty
            ? ShoppingRecommendationEngine.popularFallbackRecommendations(catalog: eligibleCatalog)
            : ranked
        recommendations = visibleRecommendations
        derivedCatalogContent = Self.makeDerivedCatalogContent(
            catalog: products,
            eligibleCatalog: eligibleCatalog,
            recommendations: visibleRecommendations,
            memories: outfitMemoryStore.memories
        )
        #if DEBUG
        ShoppingPerformanceLog.mark("recommendation derivation", startedAt: startedAt)
        #endif
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
        guard !isCatalogLoadInFlight else {
            #if DEBUG
            ShoppingPerformanceLog.mark("catalog load skipped duplicate")
            #endif
            return
        }
        let loadStartedAt = CFAbsoluteTimeGetCurrent()
        #if DEBUG
        ShoppingPerformanceLog.mark("catalog load start existingProducts=\(products.count)")
        #endif
        isCatalogLoadInFlight = true
        isLoading = products.isEmpty
        loadError = nil
        do {
            let providerStartedAt = CFAbsoluteTimeGetCurrent()
            async let loadedProducts = SharedProductCatalogLoader.shared.products()
            async let loadedStores = BundledStoreDirectoryProvider().stores()
            let loaded = try await loadedProducts
            #if DEBUG
            ShoppingPerformanceLog.mark("catalog provider load products=\(loaded.count)", startedAt: providerStartedAt)
            #endif
            let disclosureStartedAt = CFAbsoluteTimeGetCurrent()
            let disclosure = await SharedProductCatalogLoader.shared.disclosure()
            let stores = (try? await loadedStores) ?? []
            #if DEBUG
            ShoppingPerformanceLog.mark("catalog disclosure/cache read", startedAt: disclosureStartedAt)
            #endif
            let recommendationStartedAt = CFAbsoluteTimeGetCurrent()
            let preferences = currentRecommendationPreferences()
            let profile = profileStore.currentProfile
            let memories = outfitMemoryStore.memories
            let eligibleCatalog = RecommendationRationaleBuilder.budgetFiltered(
                loaded,
                profile: profile,
                preferences: preferences
            )
            let ranked = ShoppingRecommendationEngine.recommendations(
                currentGarments: [],
                currentColors: [],
                memories: preferences.usesWardrobeHistory ? memories : [],
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
            ShoppingPerformanceLog.mark("recommendation derivation", startedAt: recommendationStartedAt)
            #endif
            let derivedStartedAt = CFAbsoluteTimeGetCurrent()
            let derivedContent = Self.makeDerivedCatalogContent(
                catalog: loaded,
                eligibleCatalog: eligibleCatalog,
                recommendations: visibleRecommendations,
                memories: memories
            )
            #if DEBUG
            ShoppingPerformanceLog.mark("C1 derived catalog summary", startedAt: derivedStartedAt)
            #endif
            let dealStartedAt = CFAbsoluteTimeGetCurrent()
            let alertList = makeSaleAlerts(from: loaded)
            let watcher = SaleWatcher()
            let favoriteSales = watcher.currentFavoriteSaleEvents(catalog: loaded)
            #if DEBUG
            ShoppingPerformanceLog.mark("deal and favorite-sale filtering", startedAt: dealStartedAt)
            #endif
            await MainActor.run {
                products = loaded
                catalogDisclosure = disclosure
                supportedStores = stores
                recommendations = visibleRecommendations
                derivedCatalogContent = derivedContent
                alertsEnabled = store.saleNotificationsEnabled
                showExpandedDisclosure = store.affiliateDisclosureExpanded
                saleAlerts = alertList
                favoriteSaleEvents = favoriteSales
                normalizeDeckIndex()
                isCatalogLoadInFlight = false
                isLoading = false
                #if DEBUG
                logCatalogDisplayInvariant(providerCount: loaded.count, eligibleCount: eligibleCatalog.count)
                ShoppingPerformanceLog.mark("Shop final ready state", startedAt: loadStartedAt)
                #endif
            }
            await checkPendingProductRoute()
        } catch {
            await MainActor.run {
                loadError = "We could not load the retailer catalog. Please try again."
                isCatalogLoadInFlight = false
                isLoading = false
            }
        }
    }

    #if DEBUG
    private func logCatalogDisplayInvariant(providerCount: Int, eligibleCount: Int) {
        let filteredCount = searchCatalogProducts.count
        let displayedCount = searchResults.count
        let allSelected = selectedCategory == nil && searchCriteria.isEmpty
        let summary = "remote_count=\(providerCount) provider_count=\(providerCount) shopping_state_count=\(products.count) eligible_count=\(eligibleCount) filtered_count=\(filteredCount) displayed_count=\(displayedCount) all_selected=\(allSelected) in_flight=\(isCatalogLoadInFlight)"
        print("[StyleMatch Shopping Display] \(summary)")
        if providerCount > 0, displayedCount == 0, allSelected {
            print("[StyleMatch Shopping Display Invariant Failure] remote products loaded but displayed zero with All selected: \(summary)")
        }
    }
    #endif

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
        guard let product = products.first(where: { $0.id == productID }) else { return }
        openProductExternally(product)
    }

    private func openProductExternally(_ product: AffiliateProduct) {
        store.markViewed(product.id)
        #if canImport(UIKit)
        UIApplication.shared.open(AffiliateLinkBuilder.outboundURL(for: product), options: [:])
        #endif
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

struct ShoppingProductImage: View {
    let imageURL: URL?

    var body: some View {
        Group {
            if let imageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .empty:
                        imagePlaceholder(systemImage: "photo", title: "Loading image", showsProgress: true)
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        imagePlaceholder(systemImage: "exclamationmark.triangle.fill", title: "Image unavailable", showsProgress: false)
                    @unknown default:
                        imagePlaceholder(systemImage: "photo", title: "Loading image", showsProgress: true)
                    }
                }
            } else {
                imagePlaceholder(systemImage: "photo", title: "No image", showsProgress: false)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(imageURL == nil ? "No product image available" : "Product image")
        .onAppear {
            #if DEBUG
            ShoppingPerformanceLog.mark("product image view appeared hasURL=\(imageURL != nil)")
            #endif
        }
    }

    private func imagePlaceholder(systemImage: String, title: String, showsProgress: Bool) -> some View {
        ZStack {
            Color(.secondarySystemBackground)
            VStack(spacing: 6) {
                if showsProgress {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: systemImage)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 6)
            }
        }
    }
}

private extension View {
    @ViewBuilder
    func shoppingSelectedAccessibility(_ isSelected: Bool) -> some View {
        if isSelected {
            accessibilityAddTraits(.isSelected)
        } else {
            self
        }
    }
}

extension String {
    var nilIfEmpty: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }

    var nilIfPlaceholder: String? {
        self == "Learning" ? nil : self
    }
}
