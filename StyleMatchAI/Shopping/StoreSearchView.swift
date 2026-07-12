import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct StoreSearchView: View {
    @State private var text = ""
    @State private var selectedRetailers = Set<String>()
    @State private var brand = ""
    @State private var selectedCategory: ProductCategory?
    @State private var color = ""
    @State private var size = ""
    @State private var gender = ""
    @State private var occasion = ""
    @State private var maxPrice = 250.0
    @State private var onSaleOnly = false
    @State private var sort: SearchSort = .relevance
    @State private var products: [AffiliateProduct] = []
    @State private var rankedProducts: [RankedProduct] = []
    @State private var retailers: [Retailer] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var partialFailureNote: String?
    @State private var showFilters = false
    @State private var showDisclosure = false
    @State private var searchTask: Task<Void, Never>?

    private let localStore = ShoppingLocalStore()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                disclosureLine
                searchBar
                storePicker

                if isLoading {
                    loadingSkeletons
                } else if let errorMessage {
                    retryState(errorMessage)
                } else {
                    if let partialFailureNote {
                        Text(partialFailureNote)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    LazyVStack(spacing: 12) {
                        ForEach(rankedProducts) { ranked in
                            SearchProductCard(
                                product: ranked.product,
                                reason: ranked.reasonFacts?.oneLineReason,
                                isFavorite: localStore.savedFavorites.contains(ranked.product.id),
                                onFavorite: {
                                    localStore.toggleFavorite(ranked.product.id)
                                    rerank()
                                },
                                onTap: { openProductExternally(ranked.product) }
                            )
                        }
                    }

                    if rankedProducts.isEmpty {
                        Text("No matches - try fewer filters")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding()
                            .appCard(.shop, radius: 10)
                    }
                }

                Text(ShoppingCatalogDisclosure.fallback)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Store Search")
        .appScreenBackground(.shop)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showFilters = true
                } label: {
                    Label("Filters", systemImage: "slider.horizontal.3")
                }
            }
        }
        .task {
            await loadRetailersAndSearch()
        }
        .onChange(of: text) { _ in debouncedSearch() }
        .sheet(isPresented: $showFilters) {
            filterSheet
        }
        .sheet(isPresented: $showDisclosure) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Affiliate Disclosure")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text(ShoppingCatalogDisclosure.fallback)
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

    private var disclosureLine: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("Shopping through StyleMatch Pro")
                    .font(.footnote)
                    .fontWeight(.semibold)
                Button("How affiliate shopping works") { showDisclosure = true }
                    .font(.footnote)
            }
        }
        .padding()
        .appCard(.shop, radius: 10)
    }

    private func openProductExternally(_ product: AffiliateProduct) {
        localStore.markViewed(product.id)
        #if canImport(UIKit)
        UIApplication.shared.open(AffiliateLinkBuilder.outboundURL(for: product), options: [:])
        #endif
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
            TextField("Search clothes, shoes, stores, brands, colors, sizes, occasions", text: $text)
                .textInputAutocapitalization(.never)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var storePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All stores", isSelected: selectedRetailers.isEmpty) {
                    selectedRetailers.removeAll()
                    debouncedSearch()
                }
                ForEach(retailers.map(\.name), id: \.self) { name in
                    chip(name, isSelected: selectedRetailers.contains(name)) {
                        if selectedRetailers.contains(name) {
                            selectedRetailers.remove(name)
                        } else {
                            selectedRetailers.insert(name)
                        }
                        debouncedSearch()
                    }
                }
            }
        }
    }

    private func chip(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isSelected ? Color.orange.opacity(0.22) : Color(.secondarySystemBackground))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var loadingSkeletons: some View {
        VStack(spacing: 12) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.secondarySystemBackground))
                    .frame(height: 118)
                    .redacted(reason: .placeholder)
            }
        }
    }

    private func retryState(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Search unavailable")
                .font(.headline)
            Text(message)
                .foregroundStyle(.secondary)
            Button("Retry") { Task { await runSearch() } }
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .appCard(.shop, radius: 10)
    }

    private var filterSheet: some View {
        NavigationStack {
            Form {
                Section("Brand") {
                    TextField("Brand", text: $brand)
                }
                Section("Category") {
                    Picker("Category", selection: Binding(
                        get: { selectedCategory },
                        set: { selectedCategory = $0 }
                    )) {
                        Text("All").tag(ProductCategory?.none)
                        ForEach(ProductCategory.allCases) { category in
                            Text(category.displayName).tag(ProductCategory?.some(category))
                        }
                    }
                }
                Section("Details") {
                    TextField("Color", text: $color)
                    TextField("Size", text: $size)
                    TextField("Gender", text: $gender)
                    TextField("Occasion", text: $occasion)
                    Toggle("On sale only", isOn: $onSaleOnly)
                    Picker("Sort", selection: $sort) {
                        Text("Relevance").tag(SearchSort.relevance)
                        Text("Price Low-High").tag(SearchSort.priceLowHigh)
                        Text("Price High-Low").tag(SearchSort.priceHighLow)
                        Text("Newest Sale").tag(SearchSort.newestSale)
                    }
                    VStack(alignment: .leading) {
                        Text("Max price: $\(Int(maxPrice))")
                        Slider(value: $maxPrice, in: 25...500, step: 5)
                    }
                }
            }
            .navigationTitle("Filters")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        showFilters = false
                        debouncedSearch()
                    }
                }
            }
        }
    }

    private func loadRetailersAndSearch() async {
        if let configURL = Bundle.main.url(forResource: "RetailerConfig", withExtension: "json"),
           let data = try? Data(contentsOf: configURL),
           let config = try? JSONDecoder.catalog.decode(RetailerConfig.self, from: data) {
            retailers = config.retailers
        }
        await runSearch()
    }

    private func debouncedSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await runSearch()
        }
    }

    private func runSearch() async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
            partialFailureNote = nil
        }

        do {
            let provider: ProductSearchProvider = CatalogSearchProvider(catalogProvider: SharedCatalogProvider())
            let results = try await provider.search(currentQuery())
            await MainActor.run {
                products = results
                rerank()
                isLoading = false
            }
        } catch {
            #if DEBUG
            print("[StyleMatch Store Search] Search failed: \(type(of: error)) \(error.localizedDescription)")
            #endif
            await MainActor.run {
                errorMessage = "We could not search right now. Please try again."
                isLoading = false
            }
        }
    }

    private func rerank() {
        let favoriteProducts = products.filter { localStore.savedFavorites.contains($0.id) }
        rankedProducts = ShoppingRecommendationEngine.rank(
            results: products,
            against: ShoppingRankingContext(
                memories: OutfitMemoryStore().memories,
                savedFavorites: favoriteProducts,
                savedFavoriteProductIDs: Set(localStore.savedFavorites),
                weather: nil,
                dismissedProductIDs: localStore.dismissedProductIDs
            )
        )
    }

    private func currentQuery() -> ProductSearchQuery {
        ProductSearchQuery(
            text: text.isEmpty ? nil : text,
            retailers: selectedRetailers.isEmpty ? nil : Array(selectedRetailers),
            brands: brand.isEmpty ? nil : [brand],
            categories: selectedCategory.map { [$0] },
            colors: color.isEmpty ? nil : [color],
            sizes: size.isEmpty ? nil : [size],
            genderPresentation: gender.isEmpty ? nil : gender,
            priceRange: 0...Decimal(maxPrice),
            occasions: occasion.isEmpty ? nil : [occasion],
            onSaleOnly: onSaleOnly,
            sort: sort
        )
    }
}

private struct SearchProductCard: View {
    let product: AffiliateProduct
    let reason: String?
    let isFavorite: Bool
    let onFavorite: () -> Void
    let onTap: () -> Void

    var body: some View {
        let viewModel = AffiliateProductViewModel(product: product, reasonText: reason)
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                AsyncImage(url: product.imageURL) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    default:
                        ZStack {
                            Color(.secondarySystemBackground)
                            Image(systemName: "bag.fill").foregroundStyle(.secondary)
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
                        Button(action: onFavorite) {
                            Image(systemName: isFavorite ? "heart.fill" : "heart")
                        }
                        .buttonStyle(.plain)
                    }
                    if let brand = viewModel.brandText {
                        Text(brand)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(viewModel.retailerName)
                        .font(.caption)
                        .fontWeight(.bold)
                    Text(viewModel.soldAndShippedText)
                        .font(.caption)
                        .fontWeight(.semibold)
                    HStack(spacing: 8) {
                        Text(viewModel.priceText).fontWeight(.bold)
                        if let original = viewModel.originalPriceText {
                            Text(original).strikethrough().foregroundStyle(.secondary)
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
                    }
                    .font(.subheadline)
                    if let reason {
                        Text(reason).font(.caption).foregroundStyle(.secondary)
                    }
                    if let footnote = viewModel.footnote {
                        Text(footnote).font(.caption2).foregroundStyle(.secondary)
                    }
                    Label(viewModel.actionTitle, systemImage: "arrow.up.forward.app")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.orange)
                }
            }
            .padding()
            .appCard(.shop, radius: 10)
        }
        .buttonStyle(.plain)
    }
}
