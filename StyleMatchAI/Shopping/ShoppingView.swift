import Combine
import SwiftUI
import OSLog
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
        case .deck: return "Swipe"
        }
    }

    var icon: String {
        switch self {
        case .browse: return "square.grid.2x2"
        case .deck: return "rectangle.stack"
        }
    }
}

private enum ShoppingPrimaryDestination: String, CaseIterable, Identifiable {
    case products
    case stores

    var id: String { rawValue }

    var title: String {
        switch self {
        case .products: return "Products"
        case .stores: return "Stores"
        }
    }
}

private struct ShoppingTierIntentPresentation: Identifiable {
    let preference: ShoppingTierPreference
    let title: String
    let icon: String

    var id: String { title }

    static let primary: [Self] = [
        Self(preference: .designerLuxury, title: "Designer Luxury", icon: "diamond.fill"),
        Self(preference: .luxuryMultiBrand, title: "Luxury Multi-Brand", icon: "building.2.fill"),
        Self(preference: .premium, title: "Premium", icon: "sparkles"),
        Self(preference: .athleticStreetwear, title: "Athletic and Streetwear", icon: "figure.run"),
        Self(preference: .value, title: "Everyday and Value", icon: "tag.fill")
    ]
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
    private static let logger = Logger(
        subsystem: OSLogShoppingDiagnostics.subsystem,
        category: ShoppingDiagnosticEvent.Category.display.rawValue
    )

    static func mark(_ event: String, startedAt: CFAbsoluteTime? = nil) {
        if let startedAt {
            let elapsed = CFAbsoluteTimeGetCurrent() - startedAt
            logger.debug("performance event=\(event, privacy: .public) elapsed_seconds=\(elapsed, privacy: .public)")
        } else {
            logger.debug("performance event=\(event, privacy: .public)")
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

/// Stable ownership for a mounted Shopping screen. Keeping this object outside
/// `ShoppingView.init` prevents discarded SwiftUI view values from creating
/// new diagnostic routes or reading preferences as side effects.
@MainActor
private final class ShoppingViewRuntime: ObservableObject {
    let diagnosticContext: ShoppingDiagnosticContext
    let impressionTracker: ShoppingImpressionTracker
    let store: ShoppingLocalStore

    private var storeChangeCancellable: AnyCancellable?

    init() {
        let context = ShoppingDiagnosticContext()
        diagnosticContext = context
        impressionTracker = ShoppingImpressionTracker()
        store = ShoppingLocalStore(
            diagnostics: ShoppingDiagnostics.live,
            diagnosticContext: context
        )
        storeChangeCancellable = store.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }
}

struct ShoppingView: View {
    @Binding var selectedTab: AppTab
    private let bottomNavigationClearance: CGFloat
    private let onOpenContextualStylist: (AffiliateProduct, Set<String>) -> Void
    private let onCatalogProductIDsChanged: (Set<String>) -> Void
    @State private var products: [AffiliateProduct] = []
    @State private var liveSearchProducts: [AffiliateProduct]?
    @State private var supportedStores: [SupportedStore] = []
    @State private var isStoreRegistryLoaded = false
    @State private var recommendations: [ProductRecommendation] = []
    @State private var saleAlerts: [ShoppingSaleAlert] = []
    @State private var favoriteSaleEvents: [SaleEvent] = []
    @State private var selectedCategory: ProductCategory? = nil
    @State private var selectedShopTierPreference: ShoppingTierPreference?
    @State private var searchCriteria = ShoppingSearchCriteria()
    @State private var showExpandedDisclosure = false
    @State private var selectedRationaleSheet: RecommendationRationaleSheet?
    @State private var showRecommendationPreferences = false
    @State private var showMyStores = false
    @State private var showBrowseFilters = false
    @State private var isExploreExpanded = false
    @State private var engagementPath: [ShoppingEngagementDestination] = []
    @State private var browseMode: ShoppingBrowseMode = .browse
    @State private var storeScope: ShoppingStoreScope = .myStores
    @State private var primaryDestination: ShoppingPrimaryDestination = .products
    @State private var directoryStoreScope: ShoppingStoreScope = .allStores
    @State private var directorySearchText = ""
    @State private var deckIndex = 0
    @State private var deckSelectionProductID: String?
    @State private var recommendationBasis: Set<ShoppingRecommendationBasis> = Set(ShoppingRecommendationBasis.defaultEnabled)
    @State private var derivedCatalogContent = ShoppingDerivedCatalogContent.empty
    @State private var isLoading = true
    @State private var isCatalogLoadInFlight = false
    @State private var isSearchingLive = false
    @State private var loadError: String?
    @State private var catalogSource: ProductCatalogSource = .none
    @State private var catalogDiagnostic = ProductCatalogLoadDiagnostic.empty
    @State private var catalogLoadGeneration = 0
    @State private var catalogDisclosure = ShoppingCatalogDisclosure.fallback
    @State private var productOpenAlert: ShoppingProductOpenAlert?
    @State private var retailerOpenAlert: ShoppingRetailerOpenAlert?
    @StateObject private var profileStore = ProfileStore()
    @StateObject private var outfitMemoryStore = OutfitMemoryStore()
    @StateObject private var runtime = ShoppingViewRuntime()
    @AppStorage("closetItemsData") private var closetItemsData = Data()

    private let companionRecommender = CatalogProductComplementaryPieceRecommender()

    init(
        selectedTab: Binding<AppTab>,
        bottomNavigationClearance: CGFloat = 0,
        onOpenContextualStylist: @escaping (AffiliateProduct, Set<String>) -> Void = { _, _ in },
        onCatalogProductIDsChanged: @escaping (Set<String>) -> Void = { _ in }
    ) {
        self._selectedTab = selectedTab
        self.bottomNavigationClearance = max(0, bottomNavigationClearance)
        self.onOpenContextualStylist = onOpenContextualStylist
        self.onCatalogProductIDsChanged = onCatalogProductIDsChanged
        #if DEBUG
        ShoppingPerformanceLog.mark("ShoppingView value initialized")
        #endif
    }

    private var diagnosticContext: ShoppingDiagnosticContext { runtime.diagnosticContext }
    private var impressionTracker: ShoppingImpressionTracker { runtime.impressionTracker }
    private var store: ShoppingLocalStore { runtime.store }

    var body: some View {
        NavigationStack(path: $engagementPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    premiumShopHero
                    primaryDestinationPicker
                    if primaryDestination == .stores {
                        storesDestination
                    } else if let loadError, products.isEmpty {
                        retryState(loadError)
                    } else if products.isEmpty {
                        shoppingLoadingShell
                    } else {
                        if isCatalogLoadInFlight {
                            catalogRefreshNotice
                        }
                        if catalogSource == .bundled {
                            catalogFallbackNotice
                        }
                        if retailerPreferenceResult.usedFallback, storeScope == .myStores {
                            retailerPreferenceFallbackNotice
                        }
                        shoppingConcierge
                        bestPicksSection
                        premiumCompleteTheLook
                        shopYourStyleSection
                        exploreSection
                        productDiscoverySection
                        disclosureSummary
                        catalogDisclosureFooter
                    }
                }
                .padding()
                .padding(.bottom, 24)
            }
            // The root tab bar is a floating overlay. Shrink the Shopping
            // viewport by its measured clearance so product controls never sit
            // underneath the bar while the user is trying to tap them.
            .padding(.bottom, bottomNavigationClearance)
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
                    Menu {
                        Button {
                            showMyStores = true
                        } label: {
                            Label("My Stores", systemImage: "storefront")
                        }
                        Button {
                            showRecommendationPreferences = true
                        } label: {
                            Label("Recommendation preferences", systemImage: "slider.horizontal.3")
                        }
                    } label: {
                        Label("Shopping settings", systemImage: "gearshape")
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
            .sheet(isPresented: $showMyStores) {
                MyStoresManagementView(
                    supportedStores: supportedStores,
                    store: store,
                    coverage: currentStoreCoverage,
                    registryIsLoaded: isStoreRegistryLoaded
                )
            }
            .sheet(isPresented: $showExpandedDisclosure) {
                NavigationStack {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Shopping through KigoStylist")
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
            .alert(item: $productOpenAlert) { alert in
                if alert.allowsRetry {
                    return Alert(
                        title: Text("Unable to Open Product"),
                        message: Text("We couldn’t open this product right now. Please try again."),
                        primaryButton: .default(Text("Try Again")) {
                            openProductExternally(alert.product)
                        },
                        secondaryButton: .cancel()
                    )
                }
                return Alert(
                    title: Text("Unable to Open Product"),
                    message: Text("We couldn’t open this product right now. Please try again."),
                    dismissButton: .default(Text("OK"))
                )
            }
            .alert(item: $retailerOpenAlert) { alert in
                if alert.allowsRetry {
                    return Alert(
                        title: Text("Unable to Open Store"),
                        message: Text("We couldn’t open this store right now. Please try again."),
                        primaryButton: .default(Text("Try Again")) {
                            openStoreDirectly(alert.destinationURL, retailer: alert.retailer)
                        },
                        secondaryButton: .cancel()
                    )
                }
                return Alert(
                    title: Text("Unable to Open Store"),
                    message: Text("This store destination could not be verified."),
                    dismissButton: .default(Text("OK"))
                )
            }
            .onAppear {
                #if DEBUG
                ShoppingPerformanceLog.mark("ShoppingView onAppear products=\(products.count) loading=\(isCatalogLoadInFlight)")
                #endif
                showExpandedDisclosure = store.affiliateDisclosureExpanded
                recommendationBasis = Set(basis(from: RecommendationRationaleBuilder.preferences(from: profileStore.currentProfile)))
                _ = store.normalizePreferredRetailerIDs(
                    supportedStores: supportedStores,
                    registryIsLoaded: isStoreRegistryLoaded
                )
            }
            .styleMatchOnChange(of: store.preferredRetailerIDs) { _ in
                normalizeDeckIndex()
                reloadRecommendations()
            }
        }
        .styleMatchOnChange(of: Set(products.map(\.id))) { productIDs in
            onCatalogProductIDsChanged(productIDs)
        }
    }

    private var primaryDestinationPicker: some View {
        Picker("Shopping destination", selection: $primaryDestination) {
            ForEach(ShoppingPrimaryDestination.allCases) { destination in
                Text(destination.title).tag(destination)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityHint("Choose whether to browse products or stores")
        .accessibilityIdentifier("shopping.primary-destination")
    }

    private var storesDestination: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Browse Stores")
                .font(.title2)
                .fontWeight(.bold)
            Text("Choose an approved retailer, view available catalog products, or open the retailer directly.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                TextField("Search stores", text: $directorySearchText)
                    .textInputAutocapitalization(.never)
                    .accessibilityIdentifier("shopping.store-search")
            }
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Picker("Store scope", selection: $directoryStoreScope) {
                ForEach(ShoppingStoreScope.allCases) { scope in
                    Text(scope.title).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("shopping.store-scope")

            Button {
                showMyStores = true
            } label: {
                Label("Manage My Stores", systemImage: "storefront")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("shopping.manage-stores")

            retailerDirectorySection
        }
    }

    private var shoppingLoadingShell: some View {
        VStack(alignment: .leading, spacing: 18) {
            shoppingConcierge
            catalogLoadingState
            shopYourStyleSection
            exploreSection
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

    private var catalogFallbackNotice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text("Static shopping catalog")
                    .font(.caption)
                    .fontWeight(.bold)
                Text("Live Shopping refresh is unavailable, so these fallback picks may not reflect the latest retailer catalog.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }

    private var retailerPreferenceFallbackNotice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "storefront")
                .foregroundStyle(Color.orange)
            Text(RetailerPreferencePolicy.fallbackCopy(selectedStoreNames: selectedFallbackStoreNames))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .appCard(.shop, radius: 10)
        .accessibilityElement(children: .combine)
    }

    private var premiumShopHero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "bag.fill.badge.plus")
                    .font(.title2)
                    .foregroundStyle(StyleMatchPremiumPalette.champagneSoft)
                    .frame(width: 48, height: 48)
                    .background(StyleMatchPremiumPalette.champagne.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("SHOP AI")
                        .font(.caption2.weight(.black))
                        .tracking(1.2)
                        .foregroundStyle(StyleMatchPremiumPalette.champagneSoft)
                    Text("Buy for your wardrobe, not just the product")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                    Text("KigoStylist ranks current catalog picks against the wardrobe, size and budget signals that are actually available.")
                        .font(.caption)
                        .foregroundStyle(StyleMatchPremiumPalette.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 8) {
                premiumShopSignal("Closet", icon: "tshirt.fill", available: premiumHasSavedCloset)
                premiumShopSignal("Size", icon: "ruler", available: premiumHasSavedSizing)
                premiumShopSignal("Budget", icon: "dollarsign.circle.fill", available: profileStore.currentProfile.budgetRange.isUserConfirmed)
            }
        }
        .padding(16)
        .background(LinearGradient(colors: [StyleMatchPremiumPalette.panelRaised, StyleMatchPremiumPalette.ink], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: StyleMatchPremiumPalette.cornerLarge, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: StyleMatchPremiumPalette.cornerLarge, style: .continuous).stroke(StyleMatchPremiumPalette.champagne.opacity(0.22), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("shopping.premium-hero")
    }

    private var premiumHasSavedCloset: Bool {
        guard !closetItemsData.isEmpty,
              let closet = try? JSONDecoder().decode([ClosetItem].self, from: closetItemsData) else { return false }
        return !closet.isEmpty
    }

    private var premiumHasSavedSizing: Bool {
        let sizes = profileStore.currentProfile.clothingSizes.confirmedOnly
        return [sizes.shirtSize, sizes.pantSize, sizes.jacketSize, sizes.dressSize, sizes.shoeSize]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .contains { !$0.isEmpty }
    }

    private func premiumShopSignal(_ title: String, icon: String, available: Bool) -> some View {
        Label(title, systemImage: available ? "checkmark.circle.fill" : icon)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(available ? StyleMatchPremiumPalette.champagneSoft : StyleMatchPremiumPalette.mutedText)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(.white.opacity(0.05), in: Capsule())
            .overlay(Capsule().stroke(StyleMatchPremiumPalette.border, lineWidth: 1))
    }

    private var shoppingConcierge: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title3)
                    .foregroundStyle(Color.orange)
                    .frame(width: 44, height: 44)
                    .background(Color.orange.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Shopping for you")
                        .font(.title3)
                        .fontWeight(.bold)
                        .accessibilityAddTraits(.isHeader)
                    Text(conciergeMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button {
                if recommendations.isEmpty {
                    withAnimation(shoppingTransition) {
                        isExploreExpanded = true
                    }
                } else {
                    showEngagement(.recommendedForYou)
                }
            } label: {
                Label(recommendations.isEmpty ? "Explore products" : "View all picks", systemImage: "arrow.right")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityHint(recommendations.isEmpty ? "Opens shopping exploration controls." : "Opens all current recommendations.")
        }
        .padding()
        .appCard(.shop, radius: 14)
        .accessibilityIdentifier("shopping.concierge")
    }

    private var shopYourStyleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Label("Shopping direction", systemImage: "sparkles")
                    .font(.headline)
                    .fontWeight(.bold)
                    .accessibilityAddTraits(.isHeader)
                Text("Choose a direction for this shopping session.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                ForEach(ShoppingTierIntentPresentation.primary) { intent in
                    shopTierIntentButton(intent)
                }
            }

            if selectedShopTierPreference != nil {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.green)
                        .accessibilityHidden(true)
                    Text("Applies to this shopping session only.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Button("Clear") {
                        selectShopTierPreference(nil)
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Clear shopping style direction")
                    .accessibilityHint("Returns to normal shopping results.")
                }
            }
        }
        .padding()
        .appCard(.shop, radius: 14)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("shopping.style-direction")
    }

    private func shopTierIntentButton(_ intent: ShoppingTierIntentPresentation) -> some View {
        let isSelected = selectedShopTierPreference == intent.preference
        return Button {
            selectShopTierPreference(isSelected ? nil : intent.preference)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : intent.icon)
                    .foregroundStyle(isSelected ? Color.green : Color.orange)
                    .accessibilityHidden(true)
                Text(intent.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isSelected ? Color.green.opacity(0.14) : Color.primary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.green.opacity(0.7) : Color.secondary.opacity(0.2), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(intent.title)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint("Filters this shopping session to this style direction.")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("shopping.style-direction.\(intent.preference)")
    }

    private func selectShopTierPreference(_ preference: ShoppingTierPreference?) {
        withAnimation(shoppingTransition) {
            selectedShopTierPreference = preference
            normalizeDeckIndex()
            reloadRecommendations()
        }
    }

    private var conciergeMessage: String {
        if recommendations.isEmpty {
            return "I don't have a strong match in the current catalog yet."
        }
        if let selectedShopTierPreference {
            return "You're browsing \(shoppingDirectionTitle(for: selectedShopTierPreference)). Start with these picks."
        }
        return "Start with a curated selection from the current catalog."
    }

    private var bestPicksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Best picks for you")
                .font(.headline)
                .fontWeight(.bold)
                .accessibilityAddTraits(.isHeader)

            if recommendations.isEmpty {
                Text("I don't have a strong match in the current catalog yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(Array(recommendations.prefix(3))) { recommendation in
                    premiumBestPickCard(recommendation)
                }
            }
        }
        .accessibilityIdentifier("shopping.best-picks")
    }

    private func premiumBestPickCard(_ recommendation: ProductRecommendation) -> some View {
        let product = recommendation.product
        let rationale = premiumRationalePresentation(for: recommendation)
        let fitFacts = premiumProductFitFacts(for: product)
        let brand = product.brand?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasVerifiedPrice = product.salePrice != nil || product.price != nil
        let productActionTitle = product.isAmazonSourced ? "View on Amazon" : "View Product"

        return VStack(alignment: .leading, spacing: 10) {
            DisclosureGroup("Do I need this?") {
                Text(StyleExperienceAuthority.purchaseCheck(category: product.subcategory, colors: product.colors, closet: (try? JSONDecoder().decode([ClosetItem].self, from: closetItemsData)) ?? []))
                    .font(.subheadline).fixedSize(horizontal: false, vertical: true)
                Text("Suggestions are optional. Compare existing clothes before opening a retailer.").font(.caption)
            }
            HStack(alignment: .top, spacing: 12) {
                ShoppingProductImage(product: product)
                    .frame(width: 84, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(StyleMatchPremiumPalette.champagne.opacity(0.16), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 5) {
                    Text("STYLEMATCH PICK")
                        .font(.caption2.weight(.black))
                        .tracking(1.1)
                        .foregroundStyle(StyleMatchPremiumPalette.champagneSoft)

                    Text(product.name)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text([brand, product.retailer.name]
                        .compactMap { $0?.isEmpty == false ? $0 : nil }
                        .joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(StyleMatchPremiumPalette.mutedText)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Label(product.category.displayName, systemImage: categoryIcon(for: product))
                        if hasVerifiedPrice {
                            Text("•")
                            Text(deckPriceText(for: product))
                                .fontWeight(.bold)
                        }
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(StyleMatchPremiumPalette.champagneSoft)
                }

                Spacer(minLength: 0)
            }

            Label(rationale.headline, systemImage: "wand.and.stars")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.90))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 13, style: .continuous))

            if !fitFacts.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(fitFacts, id: \.self) { fact in
                        Label(fact, systemImage: "checkmark.seal.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(StyleMatchPremiumPalette.champagneSoft)
                    }
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(StyleMatchPremiumPalette.champagne.opacity(0.06), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }

            if !rationale.reasons.isEmpty {
                DisclosureGroup("Why KigoStylist picked this") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(rationale.reasons, id: \.self) { reason in
                            Label(reason, systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(StyleMatchPremiumPalette.mutedText)
                        }
                    }
                    .padding(.top, 5)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .tint(StyleMatchPremiumPalette.champagneSoft)
                .accessibilityHint("Shows the bounded reasons for this recommendation.")
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }

            HStack(spacing: 8) {
                Button {
                    StyleMatchPremiumFeedback.selection()
                    openProductExternally(product)
                } label: {
                    Label(productActionTitle, systemImage: "arrow.up.forward.app")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderedProminent)
                .tint(StyleMatchPremiumPalette.champagne)
                .foregroundStyle(StyleMatchPremiumPalette.ink)
                .accessibilityHint("Opens this product at \(product.retailer.name).")

                Button {
                    StyleMatchPremiumFeedback.selection()
                    onOpenContextualStylist(product, Set(searchCatalogProducts.map(\.id)))
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "sparkles")
                            .font(.subheadline.weight(.bold))
                        Text("Ask AI")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .frame(width: 54, height: 48)
                }
                .buttonStyle(.bordered)
                .tint(StyleMatchPremiumPalette.champagneSoft)
                .accessibilityLabel("Ask Stylist about \(product.name)")

                Button {
                    toggleFavoriteProduct(product)
                    StyleMatchPremiumFeedback.selection()
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: isFavoriteProduct(product) ? "heart.fill" : "heart")
                            .font(.subheadline.weight(.bold))
                        Text(isFavoriteProduct(product) ? "Saved" : "Save")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .frame(width: 54, height: 48)
                }
                .buttonStyle(.bordered)
                .tint(StyleMatchPremiumPalette.champagneSoft)
                .accessibilityLabel(isFavoriteProduct(product) ? "Saved \(product.name)" : "Save \(product.name)")
            }
        }
        .padding(12)
        .background(
            LinearGradient(
                colors: [StyleMatchPremiumPalette.panelRaised, StyleMatchPremiumPalette.ink],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(StyleMatchPremiumPalette.champagne.opacity(0.20), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.14), radius: 14, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("shopping.best-pick.\(product.id)")
    }

    private var premiumCompleteTheLook: some View {
        Group {
            if let lead = recommendations.first?.product,
               premiumCompleteLookSuggestions.count >= 2 {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Complete the Look")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .accessibilityAddTraits(.isHeader)
                    Text("Companion pieces from the current catalog for \(lead.name).")
                        .font(.caption)
                        .foregroundStyle(StyleMatchPremiumPalette.mutedText)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(premiumCompleteLookSuggestions.prefix(3)) { product in
                        Button {
                            openProductExternally(product)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: categoryIcon(for: product))
                                    .foregroundStyle(StyleMatchPremiumPalette.champagneSoft)
                                    .frame(width: 32, height: 32)
                                    .background(StyleMatchPremiumPalette.champagne.opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(product.name)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.white)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(product.retailer.name)
                                        .font(.caption)
                                        .foregroundStyle(StyleMatchPremiumPalette.mutedText)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.forward.app")
                                    .foregroundStyle(StyleMatchPremiumPalette.champagneSoft)
                                    .accessibilityHidden(true)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("View \(product.name) from \(product.retailer.name)")
                    }
                }
                .padding()
                .background(StyleMatchPremiumPalette.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(StyleMatchPremiumPalette.border, lineWidth: 1)
                )
                .accessibilityIdentifier("shopping.complete-the-look")
            }
        }
    }

    private var premiumCompleteLookSuggestions: [AffiliateProduct] {
        guard let lead = recommendations.first?.product else { return [] }
        return companionRecommender.companions(for: lead, catalog: searchCatalogProducts, limit: 3)
    }

    private var exploreSection: some View {
        DisclosureGroup(isExpanded: $isExploreExpanded) {
            VStack(alignment: .leading, spacing: 16) {
                browseHeader
                if showBrowseFilters, browseMode == .browse {
                    searchControls
                    recommendationBasisControls
                    NavigationLink {
                        StoreSearchView()
                    } label: {
                        Label("Search favorite stores", systemImage: "magnifyingglass")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                }

                if browseMode == .browse {
                    categoryChips
                }

                VStack(alignment: .leading, spacing: 8) {
                    exploreDestination(.todaysStyleBrief, title: "Today’s style brief", icon: "sparkles")
                    exploreDestination(.recommendedForYou, title: "All recommendations", icon: "wand.and.stars")
                    exploreDestination(.savedHub, title: "Saved and wishlist", icon: "heart")
                    exploreDestination(.deals, title: "Deals", icon: "tag")
                    exploreDestination(.popularPicks, title: "Catalog picks", icon: "square.grid.2x2")
                    exploreDestination(.completeLooks, title: "Complete looks", icon: "square.grid.2x2.fill")
                    exploreDestination(.styleDNA, title: "Your Style DNA", icon: "chart.line.uptrend.xyaxis")
                    exploreDestination(.priceAlerts, title: "Price alerts", icon: "bell")
                }
                .font(.subheadline)
                .foregroundStyle(.primary)
            }
            .padding(.top, 8)
        } label: {
            Label("Explore", systemImage: "slider.horizontal.3")
                .font(.headline)
                .fontWeight(.bold)
        }
        .padding()
        .appCard(.shop, radius: 14)
        .accessibilityHint("Shows search, categories, stores, and shopping preferences.")
        .accessibilityIdentifier("shopping.explore")
    }

    private func exploreDestination(_ destination: ShoppingEngagementDestination, title: String, icon: String) -> some View {
        NavigationLink(value: destination) {
            Label(title, systemImage: icon)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .accessibilityHint("Opens \(title).")
    }

    @ViewBuilder
    private var productDiscoverySection: some View {
        if browseMode == .deck {
            swipeDeckSection
        } else {
            if isSelectedTierUnavailable {
                tierIntentEmptyState
            } else if isSelectedStoreUnavailable {
                selectedStoreUnavailableState
            } else if let relaxedFilter = relaxedSearchResult.relaxedFilter {
                relaxedFilterNotice(relaxedFilter)
            }
            if !isSelectedTierUnavailable {
                LazyVStack(spacing: 12) {
                    ForEach(searchResults) { product in
                        productCard(product: product, reasonFacts: nil, rank: nil)
                    }
                }
                if searchResults.isEmpty, !products.isEmpty, !isSelectedStoreUnavailable {
                    filteredDiscoveryState
                }
            }
        }
    }

    private func premiumRationalePresentation(for recommendation: ProductRecommendation) -> (headline: String, reasons: [String]) {
        let rationale = rationale(for: recommendation.product, reasonFacts: recommendation.reasonFacts)
        let safeReasons = rationale.reasons.compactMap { reason -> String? in
            switch reason {
            case .matchesWardrobe:
                return recommendation.reasonFacts.referencedOutfit == nil
                    ? "Matches your wardrobe history"
                    : "Complements a saved outfit"
            case .matchesColors:
                return "Matches your preferred colors"
            case .matchesStyle:
                return "Matches your style preferences"
            case .onSaleToday:
                return recommendation.product.salePrice == nil ? nil : "On sale in the current catalog"
            case .similarToLiked:
                return "Similar to items you have saved"
            }
        }

        if !safeReasons.isEmpty {
            return (recommendation.reasonFacts.oneLineReason, safeReasons)
        }
        if let selectedShopTierPreference {
            return ("Selected from your \(shoppingDirectionTitle(for: selectedShopTierPreference)) direction.", [])
        }
        return (recommendation.reasonFacts.oneLineReason, [])
    }

    private func premiumProductFitFacts(for product: AffiliateProduct) -> [String] {
        var facts: [String] = []

        let closetMatchCount = premiumClosetColorMatchCount(for: product)
        if closetMatchCount > 0 {
            facts.append("Color-compatible with \(closetMatchCount) saved closet piece\(closetMatchCount == 1 ? "" : "s")")
        }

        if let savedSize = premiumSavedSize(for: product),
           let sizes = product.sizes,
           sizes.contains(where: { premiumSize($0, matches: savedSize) }) {
            facts.append("Your saved size \(savedSize) is listed")
        }

        let profile = profileStore.currentProfile
        let budget = profile.budgetRange
        let effectivePrice = product.salePrice ?? product.price
        if budget.isUserConfirmed,
           let effectivePrice,
           (Decimal(budget.minPrice)...Decimal(budget.maxPrice)).contains(effectivePrice) {
            facts.append("Within your saved budget")
        }

        return Array(facts.prefix(3))
    }

    private func premiumClosetColorMatchCount(for product: AffiliateProduct) -> Int {
        guard !closetItemsData.isEmpty,
              let closet = try? JSONDecoder().decode([ClosetItem].self, from: closetItemsData) else {
            return 0
        }
        let productFamilies = Set(product.colors.map(premiumColorFamily).filter { !$0.isEmpty })
        guard !productFamilies.isEmpty else { return 0 }
        return closet.filter { productFamilies.contains(premiumColorFamily($0.color)) }.count
    }

    private func premiumSavedSize(for product: AffiliateProduct) -> String? {
        let sizes = profileStore.currentProfile.clothingSizes.confirmedOnly
        let subcategory = product.subcategory.lowercased()
        let candidate: String?
        switch product.category {
        case .shoes:
            candidate = sizes.shoeSize
        case .clothing:
            if subcategory.contains("pant") || subcategory.contains("jean") || subcategory.contains("trouser") {
                candidate = sizes.pantSize
            } else if subcategory.contains("jacket") || subcategory.contains("coat") {
                candidate = sizes.jacketSize ?? sizes.shirtSize
            } else if subcategory.contains("dress") {
                candidate = sizes.dressSize
            } else {
                candidate = sizes.shirtSize
            }
        case .accessories, .electronics, .styleTools:
            candidate = nil
        }
        let cleaned = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return cleaned.isEmpty ? nil : cleaned
    }

    private func premiumSize(_ productSize: String, matches savedSize: String) -> Bool {
        func normalized(_ value: String) -> String {
            value
                .lowercased()
                .replacingOccurrences(of: "men ", with: "")
                .replacingOccurrences(of: "women ", with: "")
                .replacingOccurrences(of: "×", with: "x")
                .replacingOccurrences(of: " ", with: "")
        }
        return normalized(productSize) == normalized(savedSize)
    }

    private func premiumColorFamily(_ value: String) -> String {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "black", "charcoal": return "black"
        case "white", "cream", "ivory": return "white"
        case "gray", "grey", "silver": return "gray"
        case "navy", "blue", "denim": return "blue"
        case "brown", "tan", "beige", "camel": return "brown"
        case "olive", "green": return "green"
        case "red", "burgundy", "maroon": return "red"
        default: return value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
    }

    private func shoppingDirectionTitle(for preference: ShoppingTierPreference) -> String {
        ShoppingTierIntentPresentation.primary.first(where: { $0.preference == preference })?.title ?? "current shopping direction"
    }

    private var shoppingTransition: Animation? {
        #if canImport(UIKit)
        return UIAccessibility.isReduceMotionEnabled ? nil : .snappy
        #else
        return .snappy
        #endif
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

            Picker("Store scope", selection: $storeScope) {
                ForEach(ShoppingStoreScope.allCases) { scope in
                    Text(scope.title).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .styleMatchOnChange(of: storeScope) { _ in
                normalizeDeckIndex()
                reloadRecommendations()
            }

            Button {
                showMyStores = true
            } label: {
                Label("Manage My Stores", systemImage: "storefront")
                    .font(.caption)
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
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
                    rows: stylistFeedLines.isEmpty ? ["KigoStylist uses saved scans, favorites, wishlist, budget, and safe catalog data when available."] : stylistFeedLines
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
                        message: "Scan an outfit, save favorites, or browse the catalog to give KigoStylist useful local signals.",
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
                        subtitle: "Useful catalog starters while KigoStylist learns more from local wardrobe signals.",
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
                        message: "Browse recommendations or scan outfits to help KigoStylist identify useful companion pieces.",
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
            engagementScroll(title: "Price Watch") {
                engagementSummaryCard(
                    icon: "tag.fill",
                    title: "Price watch activity",
                    rows: priceAlertRows
                )
                if !saleAlerts.isEmpty {
                    saleAlertSections
                } else {
                    engagementEmptyState(
                        icon: "tag",
                        title: "No price watches yet",
                        message: "Favorite or wishlist products to watch catalog changes locally.",
                        actionTitle: "Browse Products",
                        action: openBrowse
                    )
                }
            }
        case .disclosure:
            engagementScroll(title: "Shopping Through KigoStylist") {
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
            ShoppingProductImage(product: product)
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
        .onAppear {
            recordProductImpression(product, surface: .swipeDeck, position: deckIndex)
        }
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
                ShoppingProductImage(product: product)
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
        .onAppear {
            recordProductImpression(product, surface: .compactCard, position: rank ?? 0)
        }
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
                Text("Shopping through KigoStylist")
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
            Picker("Store scope", selection: $storeScope) {
                ForEach(ShoppingStoreScope.allCases) { scope in
                    Text(scope.title).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .styleMatchOnChange(of: storeScope) { _ in
                normalizeDeckIndex()
                reloadRecommendations()
            }

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

    private var retailerDirectorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(directoryStoreScope == .allStores ? "All Stores" : "My Stores")
                .font(.headline)
                .fontWeight(.bold)
            if !isStoreRegistryLoaded {
                Text("Store directory availability is loading.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("shopping.store-directory-loading")
            } else if visibleRetailerDirectory.isEmpty {
                Text("No approved stores match this search.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("shopping.store-directory-empty")
            } else {
                ForEach(visibleRetailerDirectory) { availability in
                    retailerDirectoryRow(availability)
                    if availability.id != visibleRetailerDirectory.last?.id {
                        Divider()
                    }
                }
                Text("Direct store access. KigoStylist does not claim catalog integrations or affiliate relationships for these stores.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                    .accessibilityIdentifier("shopping.store-directory-disclosure")
            }
        }
        .padding(.vertical, 8)
        .accessibilityIdentifier("shopping.store-directory")
    }

    private func retailerDirectoryRow(_ availability: RetailerAvailability) -> some View {
        let retailer = availability.retailer
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(retailer.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(availability.coverageLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(retailer.name)
            .accessibilityValue(availability.coverageLabel)
            Spacer()
            if (availability.productCount ?? 0) > 0 {
                Button("View") {
                    searchCriteria.storeName = retailer.name
                    primaryDestination = .products
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("View \(retailer.name) products")
                .accessibilityIdentifier("shopping.store-action.\(retailer.id)")
            } else if availability.integrationStatus == .directAccessOnly,
                      let url = retailer.searchURL(for: directorySearchText) ?? retailer.directAccessURL {
                Button("Open") {
                    openStoreDirectly(url, retailer: retailer)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Open \(retailer.name)")
                .accessibilityIdentifier("shopping.store-action.\(retailer.id)")
            }
        }
        .frame(minHeight: 56)
        .accessibilityIdentifier("shopping.store-row.\(retailer.id)")
    }

    private var visibleRetailerDirectory: [RetailerAvailability] {
        RetailerDirectoryPolicy.availabilities(
            supportedStores: supportedStores,
            coverage: currentStoreCoverage,
            retailerIDs: directoryStoreScope == .myStores ? activeDirectoryRetailerIDs : nil,
            query: directorySearchText
        )
    }

    private var activeDirectoryRetailerIDs: [String] {
        store.preferredRetailerIDs(
            supportedStores: supportedStores,
            registryIsLoaded: isStoreRegistryLoaded
        )
    }

    private var rawBaseSearchProducts: [AffiliateProduct] {
        liveSearchProducts ?? products
    }

    private var baseSearchProducts: [AffiliateProduct] {
        retailerPreferenceResult.products
    }

    private var selectedTierFilterResult: RetailerTierFilterResult? {
        guard let selectedShopTierPreference else { return nil }
        return RetailerCatalogRegistry(stores: supportedStores).filter(
            products: baseSearchProducts,
            for: selectedShopTierPreference
        )
    }

    private var tierFilteredBaseSearchProducts: [AffiliateProduct] {
        selectedTierFilterResult?.products ?? baseSearchProducts
    }

    private var retailerPreferenceResult: RetailerPreferenceResult {
        RetailerPreferencePolicy.apply(
            products: rawBaseSearchProducts,
            preferredRetailerIDs: activePreferredRetailerIDs,
            supportedStores: supportedStores
        )
    }

    private var activePreferredRetailerIDs: [String] {
        guard storeScope == .myStores,
              searchCriteria.storeName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true else {
            return []
        }
        return store.preferredRetailerIDs(
            supportedStores: supportedStores,
            registryIsLoaded: isStoreRegistryLoaded
        )
    }

    private var searchCatalogProducts: [AffiliateProduct] {
        budgetFiltered(tierFilteredBaseSearchProducts)
    }

    private var relaxedSearchResult: ShoppingSearchEngine.RelaxedFilterResult {
        var criteria = searchCriteria
        criteria.category = selectedCategory
        return ShoppingSearchEngine.relaxedFilter(products: searchCatalogProducts, criteria: criteria)
    }

    private var availableStoreNames: Set<String> {
        Set(rawBaseSearchProducts.map { $0.retailer.name.lowercased() })
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

    private var selectedFallbackStoreNames: [String] {
        storeNames(for: retailerPreferenceResult.requestedRetailerIDs)
    }

    private var currentStoreCoverage: StoreCoverageState {
        catalogSource == .none ? .unavailable : .loaded(products: rawBaseSearchProducts, source: catalogSource)
    }

    private var isSelectedStoreUnavailable: Bool {
        guard let storeName = searchCriteria.storeName, !storeName.isEmpty else { return false }
        return relaxedSearchResult.exactResults.isEmpty
            && !availableStoreNames.contains(storeName.lowercased())
    }

    private var isSelectedTierUnavailable: Bool {
        selectedTierFilterResult?.eligibility == .noEligibleRetailers
    }

    private var tierIntentEmptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("I don't have a strong match in the current catalog for \(selectedShoppingDirectionTitle).", systemImage: "sparkles")
                .font(.headline)
            Text("Choose another direction or browse all products.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button {
                    selectShopTierPreference(nil)
                } label: {
                    Label("Choose another direction", systemImage: "sparkles")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)

                Button {
                    selectShopTierPreference(nil)
                } label: {
                    Label("Browse all products", systemImage: "bag")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .appCard(.shop, radius: 10)
        .accessibilityIdentifier("shopping.style-direction-empty")
    }

    private var selectedShoppingDirectionTitle: String {
        guard let selectedShopTierPreference else { return "this direction" }
        return shoppingDirectionTitle(for: selectedShopTierPreference)
    }

    private var recommendationSectionTitle: String {
        recommendations.allSatisfy { rationale(for: $0.product, reasonFacts: $0.reasonFacts).isTrendingFallback } ? "Catalog Picks" : "Recommended for You"
    }

    private var recommendationSectionSubtitle: String {
        recommendations.allSatisfy { rationale(for: $0.product, reasonFacts: $0.reasonFacts).isTrendingFallback }
            ? "A useful starting point while KigoStylist learns more from your wardrobe."
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
            "KigoStylist uses approved catalog links and local shopping signals.",
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
        searchCatalogProducts.map(\.id)
    }

    private var currentDeckProduct: AffiliateProduct? {
        let deckProducts = searchCatalogProducts
        if let deckSelectionProductID,
           let selectedProduct = deckProducts.first(where: { $0.id == deckSelectionProductID }) {
            return selectedProduct
        }
        guard deckIndex < deckProducts.count else {
            return nil
        }
        return deckProducts[deckIndex]
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
        let count = ShoppingSearchEngine.filter(products: searchCatalogProducts, criteria: criteria).count
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
        deckSelectionProductID = deck.currentProductID
        reloadRecommendations()
    }

    private func skipCurrentDeckProduct() {
        var deck = ShoppingSwipeDeckState(productIDs: deckProductIDs, currentIndex: deckIndex)
        deck.swipeLeft()
        deckIndex = deck.currentIndex
        deckSelectionProductID = deck.currentProductID
    }

    private func normalizeDeckIndex() {
        let currentProductIDs = deckProductIDs
        if let deckSelectionProductID,
           let restoredIndex = currentProductIDs.firstIndex(of: deckSelectionProductID) {
            deckIndex = restoredIndex
            return
        }
        deckIndex = min(max(0, deckIndex), currentProductIDs.count)
        deckSelectionProductID = deckIndex < currentProductIDs.count ? currentProductIDs[deckIndex] : nil
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
                    Text("New products are coming soon for \(storeName). KigoStylist does not currently have live catalog products for this retailer, and we will not substitute products from another retailer.")
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

                if let actionURL, let directoryStore {
                    Button {
                        openStoreDirectly(actionURL, retailer: directoryStore)
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

    private func openStoreDirectly(_ url: URL, retailer: SupportedStore) {
        #if canImport(UIKit)
        Task {
            let result = await ShoppingRetailerDestinationOpener.live().open(url, retailer: retailer)
            if let failure = result.failure {
                retailerOpenAlert = ShoppingRetailerOpenAlert(
                    retailer: retailer,
                    destinationURL: url,
                    failure: failure
                )
            }
        }
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
                    ShoppingProductImage(product: product)
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

            if FeatureGate.shared.isCustomerVisible(.aiPersonalShopper) {
                Button {
                    onOpenContextualStylist(product, Set(products.map(\.id)))
                } label: {
                    Label("Ask Stylist", systemImage: "sparkles")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Ask Stylist about \(viewModel.name)")
                .accessibilityHint("Discusses this product with AI Stylist without opening a retailer link")
            }

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
        .onAppear {
            recordProductImpression(product, surface: .productCard, position: rank ?? 0)
        }
    }

    private func recordProductImpression(
        _ product: AffiliateProduct,
        surface: ShoppingImpressionSurface,
        position: Int
    ) {
        let approvedRetailerIDs = Set(
            supportedStores
                .filter(\.isEnabled)
                .compactMap { RetailerPreferencePolicy.canonicalID($0.id) }
        )
        _ = impressionTracker.recordIfNeeded(
            productID: product.id,
            retailerID: product.retailerID,
            approvedRetailerIDs: approvedRetailerIDs,
            surface: surface,
            position: position,
            source: catalogSource,
            context: diagnosticContext.withLoadGeneration(catalogLoadGeneration),
            diagnostics: ShoppingDiagnostics.live
        )
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
        let suggestions = companionRecommender.companions(for: product, catalog: searchCatalogProducts, limit: 6)
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
        let policyCatalog = tierFilteredBaseSearchProducts
        let eligibleCatalog = budgetFiltered(policyCatalog)
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
            catalog: policyCatalog,
            eligibleCatalog: eligibleCatalog,
            recommendations: visibleRecommendations,
            memories: outfitMemoryStore.memories
        )
        saleAlerts = makeSaleAlerts(from: policyCatalog)
        favoriteSaleEvents = SaleWatcher().currentFavoriteSaleEvents(catalog: policyCatalog)
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
        catalogLoadGeneration += 1
        let loadGeneration = catalogLoadGeneration
        let loadContext = diagnosticContext.withLoadGeneration(loadGeneration)
        #if DEBUG
        ShoppingPerformanceLog.mark("catalog load start existingProducts=\(products.count)")
        #endif
        isCatalogLoadInFlight = true
        isLoading = products.isEmpty
        loadError = nil
        let providerStartedAt = CFAbsoluteTimeGetCurrent()
        async let loadedCatalog = SharedProductCatalogLoader.shared.loadResult(
            diagnosticContext: loadContext,
            diagnostics: ShoppingDiagnostics.live,
            trigger: products.isEmpty ? .routeEntry : .refresh
        )
        async let loadedStores = BundledStoreDirectoryProvider().stores()
        let catalogResult = await loadedCatalog
        guard catalogResult.source != .none else {
            let stores = (try? await loadedStores) ?? []
            await MainActor.run {
                products = []
                supportedStores = stores
                isStoreRegistryLoaded = true
                catalogSource = .none
                catalogDiagnostic = catalogResult.diagnostic
                loadError = "We could not load Shopping from the live catalog, cache, or bundled fallback. Please check your connection and retry."
                isCatalogLoadInFlight = false
                isLoading = false
                #if DEBUG
                ShoppingPerformanceLog.mark("catalog total failure", startedAt: loadStartedAt)
                #endif
            }
            return
        }
        let loaded = catalogResult.products
            #if DEBUG
            ShoppingPerformanceLog.mark("catalog provider load products=\(loaded.count) source=\(catalogResult.source.rawValue)", startedAt: providerStartedAt)
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
            let normalizedPreferredRetailerIDs = storeScope == .myStores
                ? store.preferredRetailerIDs(supportedStores: stores)
                : []
            let retailerPolicyResult = RetailerPreferencePolicy.apply(
                products: loaded,
                preferredRetailerIDs: normalizedPreferredRetailerIDs,
                supportedStores: stores,
                diagnosticContext: loadContext,
                diagnostics: ShoppingDiagnostics.live
            )
            let tierFilterResult = selectedShopTierPreference.map {
                RetailerCatalogRegistry(stores: stores).filter(
                    products: retailerPolicyResult.products,
                    for: $0
                )
            }
            let scopedCatalog = tierFilterResult?.products ?? retailerPolicyResult.products
            let eligibleCatalog = RecommendationRationaleBuilder.budgetFiltered(
                scopedCatalog,
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
                catalog: scopedCatalog,
                eligibleCatalog: eligibleCatalog,
                recommendations: visibleRecommendations,
                memories: memories
            )
            #if DEBUG
            ShoppingPerformanceLog.mark("C1 derived catalog summary", startedAt: derivedStartedAt)
            #endif
            let dealStartedAt = CFAbsoluteTimeGetCurrent()
            let alertList = makeSaleAlerts(from: scopedCatalog)
            let watcher = SaleWatcher()
            let favoriteSales = watcher.currentFavoriteSaleEvents(catalog: scopedCatalog)
            let catalogObservation = ShoppingCatalogObservation.make(
                source: catalogResult.source,
                selectedRetailerIDs: normalizedPreferredRetailerIDs,
                supportedStores: stores,
                inputProducts: loaded,
                policyResult: retailerPolicyResult,
                eligibleCount: eligibleCatalog.count,
                recommendationCount: visibleRecommendations.count,
                displayedCount: visibleRecommendations.count,
                destination: .products
            )
            #if DEBUG
            ShoppingPerformanceLog.mark("deal and favorite-sale filtering", startedAt: dealStartedAt)
            #endif
            await MainActor.run {
                products = loaded
                catalogSource = catalogResult.source
                catalogDiagnostic = catalogResult.diagnostic
                catalogDisclosure = disclosure
                supportedStores = stores
                isStoreRegistryLoaded = true
                _ = store.normalizePreferredRetailerIDs(
                    supportedStores: stores,
                    registryIsLoaded: true
                )
                recommendations = visibleRecommendations
                derivedCatalogContent = derivedContent
                showExpandedDisclosure = store.affiliateDisclosureExpanded
                saleAlerts = alertList
                favoriteSaleEvents = favoriteSales
                normalizeDeckIndex()
                isCatalogLoadInFlight = false
                isLoading = false
                catalogObservation.recordDisplay(
                    context: loadContext,
                    diagnostics: ShoppingDiagnostics.live
                )
                #if DEBUG
                ShoppingPerformanceLog.mark("Shop final ready state", startedAt: loadStartedAt)
                #endif
            }
        await checkPendingProductRoute()
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
                normalizeDeckIndex()
                reloadRecommendations()
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
        if SaleWatcher.notificationsAvailable && store.saleNotificationsEnabled {
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
        let candidateURL = AffiliateLinkBuilder.outboundURL(for: product)
        Task {
            let result = await ShoppingProductOpener.live().open(
                product,
                candidateURL: candidateURL,
                supportedStores: supportedStores
            )
            if let failure = result.failure {
                productOpenAlert = ShoppingProductOpenAlert(product: product, failure: failure)
            }
        }
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

    private func storeNames(for retailerIDs: [String]) -> [String] {
        let namesByID = Dictionary(uniqueKeysWithValues: supportedStores.map { ($0.id, $0.name) })
        return retailerIDs.map { namesByID[$0] ?? $0 }
    }

}

struct MyStoresManagementView: View {
    let supportedStores: [SupportedStore]
    @ObservedObject var store: ShoppingLocalStore
    let coverage: StoreCoverageState
    let registryIsLoaded: Bool
    @Environment(\.dismiss) private var dismiss

    private var enabledStores: [SupportedStore] {
        supportedStores.filter(\.isEnabled)
    }

    private var selectedIDs: Set<String> {
        Set(store.preferredRetailerIDs(
            supportedStores: enabledStores,
            registryIsLoaded: registryIsLoaded
        ))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        store.setPreferredRetailerIDs([], supportedStores: enabledStores)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("All approved stores")
                                    .fontWeight(.semibold)
                                Text("Use the full approved catalog unless you choose specific stores.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if selectedIDs.isEmpty {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.orange)
                            }
                        }
                    }
                }

                Section("My Stores") {
                    ForEach(enabledStores) { supportedStore in
                        Button {
                            toggle(supportedStore)
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(supportedStore.name)
                                        .fontWeight(.semibold)
                                    Text(supportedStore.primaryDomain ?? supportedStore.id)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(availabilityLine(for: supportedStore))
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(availabilityColor(for: supportedStore))
                                }
                                Spacer()
                                Image(systemName: selectedIDs.contains(supportedStore.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedIDs.contains(supportedStore.id) ? Color.orange : Color.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(supportedStore.name), \(selectedIDs.contains(supportedStore.id) ? "selected" : "not selected")")
                    }
                }
            }
            .navigationTitle("My Stores")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear") {
                        store.setPreferredRetailerIDs([], supportedStores: enabledStores)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func toggle(_ supportedStore: SupportedStore) {
        var next = selectedIDs
        if next.contains(supportedStore.id) {
            next.remove(supportedStore.id)
        } else {
            next.insert(supportedStore.id)
        }
        store.setPreferredRetailerIDs(Array(next), supportedStores: enabledStores)
    }

    private func availabilityLine(for supportedStore: SupportedStore) -> String {
        guard let count = coverage.productCount(for: supportedStore.id) else {
            return "Availability unknown"
        }
        if count == 1 { return "1 product" }
        if count > 1 { return "\(count) products" }
        return "No products available yet"
    }

    private func availabilityColor(for supportedStore: SupportedStore) -> Color {
        guard coverage.productCount(for: supportedStore.id) != nil else {
            return .secondary
        }
        return .secondary
    }
}

struct ShoppingProductImage: View {
    let imageURL: URL?
    let productName: String
    let retailerName: String
    let category: ProductCategory?

    @Environment(\.colorScheme) private var colorScheme

    init(product: AffiliateProduct) {
        imageURL = product.remoteImageRequestURL
        productName = product.name
        retailerName = product.retailer.name
        category = product.category
    }

    init(imageURL: URL?, productName: String, retailerName: String, category: ProductCategory?) {
        self.imageURL = imageURL
        self.productName = productName
        self.retailerName = retailerName
        self.category = category
    }

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
                        brandedFallback(reason: .loadFailure)
                    @unknown default:
                        imagePlaceholder(systemImage: "photo", title: "Loading image", showsProgress: true)
                    }
                }
            } else {
                brandedFallback(reason: .missing)
            }
        }
        .accessibilityHidden(true)
        .onAppear {
            #if DEBUG
            ShoppingPerformanceLog.mark("product image view appeared hasURL=\(imageURL != nil)")
            #endif
        }
    }

    private func brandedFallback(reason: ShoppingProductImageFallbackReason) -> some View {
        let presentation = ShoppingProductImageFallbackPresentation.make(
            category: category,
            productName: productName,
            retailerName: retailerName,
            reason: reason
        )

        return GeometryReader { proxy in
            let compact = proxy.size.height < 110 || proxy.size.width < 120

            ZStack {
                LinearGradient(
                    colors: [
                        Color.orange.opacity(
                            ShoppingProductImageFallbackPresentation.accentOpacity(
                                isDarkMode: colorScheme == .dark
                            )
                        ),
                        Color(.secondarySystemBackground)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                VStack(spacing: compact ? 4 : 7) {
                    Image(systemName: presentation.systemImage)
                        .font(compact ? .headline : .title2)
                        .foregroundStyle(StyleMatchPremiumPalette.champagneSoft)
                        .frame(width: compact ? 32 : 44, height: compact ? 32 : 44)
                        .background(StyleMatchPremiumPalette.champagne.opacity(colorScheme == .dark ? 0.18 : 0.10))
                        .clipShape(Circle())

                    Text(presentation.categoryLabel.uppercased())
                        .font(.system(size: compact ? 8 : 9, weight: .bold, design: .rounded))
                        .tracking(0.7)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text(presentation.identityText)
                        .font(compact ? .caption2 : .caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .lineLimit(compact ? 1 : 2)

                    if !compact {
                        Text(presentation.statusText)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(1)
                    }
                }
                .padding(compact ? 6 : 10)
            }
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
