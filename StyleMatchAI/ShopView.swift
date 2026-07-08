import SwiftUI

struct ShopView: View {
    @AppStorage("outfitScanHistoryData") private var outfitScanHistoryData = Data()
    @AppStorage("favoriteColors") private var favoriteColors = "Black, white, navy"
    @AppStorage("favoriteBrands") private var favoriteBrands = "Ralph Lauren, Nike, Levi's"
    @AppStorage("shoppingBudget") private var budget = "$50 - $200"
    @AppStorage("sizeProfile") private var sizeProfile = "Pants: 24W-60W x 26L-40L, saved 36W x 36L; Shirts: XXS-8XL; Shoes: 5-18; Fit: slim, straight, relaxed, curvy, petite, tall"
    @AppStorage("stylePreferences") private var stylePreferences = "Classic, business casual, clean sneakers"
    @AppStorage("occasions") private var occasions = "Work, church, dinner, travel"
    @AppStorage("weather") private var weather = "Mild weather"
    @AppStorage("pastPurchases") private var pastPurchases = "White Oxford shirt, black leather belt"
    @AppStorage("favoriteOutfits") private var favoriteOutfits = "Navy blazer with dark denim"
    @AppStorage("closetInventory") private var closetInventory = "Dark denim, white shirts, black shoes"
    @AppStorage("closetItemsData") private var closetItemsData = Data()
    @AppStorage("wishlistProductNamesData") private var wishlistProductNamesData = Data()
    @AppStorage("profileName") private var profileName = ""
    @AppStorage("openAIModel") private var openAIModel = "gpt-4o-mini"
    @State private var wishlistProductNames: Set<String> = []
    @State private var closetItems: [ClosetItem] = []
    @State private var selectedOutfitRequest = "Work outfit"
    @State private var selectedSize = "Men 36x36"
    @State private var selectedColor = "White"
    @State private var shoppingMessage: String?
    @State private var expandedProductIDs: Set<UUID> = []
    @State private var selectedRetailerFilter = "All"
    @State private var saleRecommendations: [ShoppingSaleRecommendation] = []
    @State private var saleRecommendationMessage = "Tap refresh to match real sale items to your recent outfits."
    @State private var isLoadingSaleRecommendations = false

    private let products: [RetailProduct] = [
        RetailProduct(
            recommendation: "Shirts",
            productName: "White Oxford Shirt",
            storeName: "Macy's",
            marketplaceCategory: "Clothing",
            imageURL: "https://images.unsplash.com/photo-1598033129183-c4f50c736f10?auto=format&fit=crop&w=240&q=80",
            price: "$89.50",
            originalPrice: "$89.50",
            salePrice: "$69.99",
            saleAlert: "Sale alert: lower than the regular listed price.",
            shippingCost: "$0 with store account",
            estimatedDelivery: "3-5 days",
            bestValueNote: "Best value: Macy's has the lowest sale price for this shirt.",
            sizes: "Shirt XXS-8XL",
            colors: "White, blue, black",
            officialURL: "https://www.macys.com/shop/mens-clothing/mens-dress-shirts",
            affiliateURL: "https://www.macys.com/shop/mens-clothing/mens-dress-shirts?stylematch_affiliate=sty_shirts_001",
            affiliateTrackingID: "sty_shirts_001",
            matchReason: "Based on your business style, neutral colors, and shirt size profile, this shirt would complete a smart casual outfit."
        ),
        RetailProduct(
            recommendation: "Jackets",
            productName: "Structured Navy Blazer",
            storeName: "Nordstrom",
            marketplaceCategory: "Clothing",
            imageURL: "https://images.unsplash.com/photo-1594938298603-c8148c4dae35?auto=format&fit=crop&w=240&q=80",
            price: "$149.00",
            originalPrice: "$198.00",
            salePrice: "$149.00",
            saleAlert: "Sale alert: marked down from the original price.",
            shippingCost: "Free shipping",
            estimatedDelivery: "4-6 days",
            bestValueNote: "Best value: Nordstrom balances sale price, free shipping, and easy returns.",
            sizes: "Jacket/Shirt XXS-8XL",
            colors: "Navy, black, gray",
            officialURL: "https://www.nordstrom.com/browse/men/clothing/blazers-sportcoats",
            affiliateURL: "https://www.nordstrom.com/browse/men/clothing/blazers-sportcoats?stylematch_affiliate=sty_jackets_001",
            affiliateTrackingID: "sty_jackets_001",
            matchReason: "A navy blazer adds polish while staying close to your preferred black, white, and navy palette."
        ),
        RetailProduct(
            recommendation: "Shoes",
            productName: "Clean Leather Sneaker",
            storeName: "Nike",
            marketplaceCategory: "Shoes",
            imageURL: "https://images.unsplash.com/photo-1549298916-b41d501d3772?auto=format&fit=crop&w=240&q=80",
            price: "$110.00",
            originalPrice: "$120.00",
            salePrice: "$110.00",
            saleAlert: "Sale alert: limited markdown compared with regular pricing.",
            shippingCost: "$8.00",
            estimatedDelivery: "2-4 days",
            bestValueNote: "Best value: Nike is fastest for delivery, even with shipping added.",
            sizes: "5-18",
            colors: "White, black",
            officialURL: "https://www.nike.com/w/mens-shoes-nik1zy7ok",
            affiliateURL: "https://www.nike.com/w/mens-shoes-nik1zy7ok?stylematch_affiliate=sty_shoes_001",
            affiliateTrackingID: "sty_shoes_001",
            matchReason: "A clean sneaker keeps the outfit comfortable and works with casual or smart casual looks."
        ),
        RetailProduct(
            recommendation: "Jeans",
            productName: "Slim Dark Denim",
            storeName: "Levi's",
            marketplaceCategory: "Clothing",
            imageURL: "https://images.unsplash.com/photo-1542272604-787c3835535d?auto=format&fit=crop&w=240&q=80",
            price: "$79.50",
            originalPrice: "$79.50",
            salePrice: "$59.99",
            saleAlert: "Sale alert: denim price drop available now.",
            shippingCost: "$7.95",
            estimatedDelivery: "5-7 days",
            bestValueNote: "Best value: Levi's sale price makes this the strongest denim deal.",
            sizes: "Men's 24W-60W x 26L-40L including 36x36; Women's 000-34, XXS-6XL; slim, straight, relaxed, curvy, petite, tall",
            colors: "Dark wash, black",
            officialURL: "https://www.levi.com/US/en_US/clothing/men/jeans/c/levi_clothing_men_jeans",
            affiliateURL: "https://www.levi.com/US/en_US/clothing/men/jeans/c/levi_clothing_men_jeans?stylematch_affiliate=sty_denim_001",
            affiliateTrackingID: "sty_denim_001",
            matchReason: "Dark denim gives you a closet staple that pairs well with shirts, jackets, and neutral shoes."
        ),
        RetailProduct(
            recommendation: "Accessories",
            productName: "Black Leather Belt",
            storeName: "Ralph Lauren",
            marketplaceCategory: "Accessories",
            imageURL: "https://images.unsplash.com/photo-1624222247344-550fb60583dc?auto=format&fit=crop&w=240&q=80",
            price: "$65.00",
            originalPrice: "$75.00",
            salePrice: "$65.00",
            saleAlert: "Sale alert: accessory markdown available.",
            shippingCost: "Free over $100",
            estimatedDelivery: "4-7 days",
            bestValueNote: "Best value: Ralph Lauren matches your saved brand preference.",
            sizes: "Shirt XXS-8XL",
            colors: "Black, brown",
            officialURL: "https://www.ralphlauren.com/men-accessories-belts",
            affiliateURL: "https://www.ralphlauren.com/men-accessories-belts?stylematch_affiliate=sty_accessories_001",
            affiliateTrackingID: "sty_accessories_001",
            matchReason: "A black belt ties the outfit together when paired with black shoes or a structured jacket."
        ),
        RetailProduct(
            recommendation: "Electronics",
            productName: "Fitness Smartwatch",
            storeName: "Best Buy",
            marketplaceCategory: "Electronics",
            imageURL: "https://images.unsplash.com/photo-1523275335684-37898b6baf30?auto=format&fit=crop&w=240&q=80",
            price: "$199.99",
            originalPrice: "$249.99",
            salePrice: "$199.99",
            saleAlert: "Sale alert: wearable tech markdown for fitness and travel.",
            shippingCost: "Free shipping",
            estimatedDelivery: "2-5 days",
            bestValueNote: "Best value: Best Buy is an approved electronics partner for style-related tech accessories.",
            sizes: "Adjustable watch bands",
            colors: "Black, silver, navy",
            officialURL: "https://www.bestbuy.com/site/searchpage.jsp?st=fitness+smartwatch",
            affiliateURL: "https://www.bestbuy.com/site/searchpage.jsp?st=fitness+smartwatch&stylematch_affiliate=sty_electronics_001",
            affiliateTrackingID: "sty_electronics_001",
            matchReason: "A smartwatch supports gym, travel, and daily outfits without changing the clothing silhouette."
        ),
        RetailProduct(
            recommendation: "Style Essentials",
            productName: "Portable Fabric Steamer",
            storeName: "Amazon",
            marketplaceCategory: "Style-related Products",
            imageURL: "https://images.unsplash.com/photo-1582735689369-4fe89db7114c?auto=format&fit=crop&w=240&q=80",
            price: "$39.99",
            originalPrice: "$49.99",
            salePrice: "$39.99",
            saleAlert: "Sale alert: useful wardrobe-care item under budget.",
            shippingCost: "Varies by seller",
            estimatedDelivery: "Varies by seller",
            bestValueNote: "Best value: Amazon provides multiple approved seller options to compare.",
            sizes: "One size",
            colors: "White, black",
            officialURL: "https://www.amazon.com/s?k=portable+fabric+steamer",
            affiliateURL: "https://www.amazon.com/s?k=portable+fabric+steamer&tag=stylematchpro-20",
            affiliateTrackingID: "stylematchpro-20",
            matchReason: "A steamer improves outfit presentation for work, travel, interviews, and formal events without buying more clothing."
        )
    ]

    private let sizeChoices = Self.allSizeChoices
    private static let allSizeChoices: [String] = {
        let shirts = ["Shirt XXS", "Shirt XS", "Shirt S", "Shirt M", "Shirt L", "Shirt XL", "Shirt 2XL", "Shirt 3XL", "Shirt 4XL", "Shirt 5XL", "Shirt 6XL", "Shirt 7XL", "Shirt 8XL"]
        let menPants = (24...60).flatMap { waist in
            (26...40).map { length in
                "Men \(waist)x\(length)"
            }
        }
        let womenPants = ["Women 000", "Women 00"] + (0...34).map { "Women \($0)" } + ["Women XXS", "Women XS", "Women S", "Women M", "Women L", "Women XL", "Women 2XL", "Women 3XL", "Women 4XL", "Women 5XL", "Women 6XL"]
        let shoes = (5...18).map { "Shoes \($0)" }
        return shirts + menPants + womenPants + shoes
    }()
    private let colorChoices = ["White", "Black", "Navy", "Gray", "Brown"]

    private let retailerFilters = ["All", "Macy's", "Nike", "Levi's", "Nordstrom", "Amazon", "Best Buy"]
    private let shopperNeedOptions = ["Work outfit", "Date night", "Wedding", "Vacation", "Interview", "Casual", "Business", "Summer"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    PageColorBand(
                        tab: .shop,
                        title: "Smart Shopping",
                        subtitle: "Find trusted retailer picks for your real wardrobe.",
                        icon: "bag.fill"
                    )

                    personalShoppingDashboard
                    aiClosetHealthScoreCard

                    VStack(alignment: .leading, spacing: 10) {
                        Label("Smart Shopping", systemImage: "bag")
                            .font(.headline)

                        Text("Style Match Pro checks your closet, sizes, colors, brands, budget, wishlist, weather, and occasions before showing affiliate retailer recommendations.")
                            .foregroundStyle(.secondary)
                            .lineSpacing(4)
                    }
                    .padding()
                    .appCard(.shop)

                    savingsSummaryCard
                    personalizationCard
                    personalShopperRequestCard
                    AIStyleInsightCard(
                        tab: .shop,
                        screen: "Smart Shopping",
                        title: "AI Personal Shopper",
                        prompt: "I need help with: \(selectedOutfitRequest). Based on my closet, budget, sizes, favorite brands, weather, and recent outfit scores, tell me the one smartest affiliate retailer item to consider next and why. Do not invent product names, prices, retailers, affiliate links, or tracking IDs.",
                        fallbackAdvice: personalShopperFallbackAdvice,
                        extraContext: "Wishlist count: \(wishlistProductNames.count). Current shopping request: \(selectedOutfitRequest)."
                    )

                    aiSaleRecommendationsCard
                    retailerFilterCard
                    smartShoppingSections

                    if FeatureGate.shared.isCustomerVisible(.smartWishlist) {
                        wishlistCard
                    }

                    if FeatureGate.shared.isCustomerVisible(.trustedRetailerLinks) {
                        affiliateMarketplaceCard
                    }

                    if let shoppingMessage {
                        Label(shoppingMessage, systemImage: "heart")
                            .font(.subheadline)
                            .foregroundStyle(.green)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .appCard(.shop, radius: 12)
                    }
                }
                .padding()
            }
            .scrollContentBackground(.hidden)
            .appScreenBackground(.shop)
            .navigationTitle("Smart Shopping")
            .onAppear {
                loadWishlist()
                loadClosetItems()
            }
            .styleMatchOnChange(of: closetItemsData) { _ in loadClosetItems() }
        }
    }

    private var personalizationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Closet-aware shopping", systemImage: "person.text.rectangle")
                .font(.headline)

            Text("Instead of random items, Style Match Pro uses your saved colors, brands, budget, sizes, purchases, favorite outfits, weather, occasions, and closet inventory.")
                .foregroundStyle(.secondary)
                .lineSpacing(4)

            Text(smartShoppingSummary)
                .font(.subheadline)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .appCard(.shop, radius: 12)
        }
        .padding()
        .appCard(.shop)
    }

    private var personalShoppingDashboard: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(smartShoppingGreeting)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)

                Text("Your wardrobe and shopping opportunities for today.")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                dashboardMetric(title: "Closet Health", value: "87%", icon: "checkmark.seal.fill", tint: .green)
                dashboardMetric(title: "Missing", value: "2 Essentials", icon: "exclamationmark.triangle.fill", tint: .orange)
                dashboardMetric(title: "Today's Deals", value: "14", icon: "tag.fill", tint: AppTab.shop.palette.accent)
                dashboardMetric(title: "New Price Drops", value: "6", icon: "arrow.down.circle.fill", tint: .blue)
            }
        }
        .padding()
        .appCard(.shop)
    }

    private var smartShoppingGreeting: String {
        let storedName = StyleMatchGreetingBuilder.firstName(from: profileName) ?? ProfileStore().currentProfile.givenName
        return StyleMatchGreetingBuilder.greetingLine(storedName: storedName)
    }

    private func dashboardMetric(title: String, value: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(tint)

            Text(title)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var aiClosetHealthScoreCard: some View {
        let weakest = closetHealthScores.min { $0.score < $1.score } ?? ClosetHealthMetric(title: "Accessories", score: 74, icon: "tag.fill")

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Label("AI Closet Health Score", systemImage: "sparkles")
                    .font(.headline)

                Spacer()

                Text("AI Review")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(AppTab.shop.palette.accent)
            }

            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text("Closet Score")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("91")
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(AppTab.shop.palette.accent)
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(closetHealthScores) { metric in
                    closetHealthMetricCell(metric)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Label("Improve \(weakest.title)", systemImage: "arrow.up.circle.fill")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(.orange)

                Text(closetHealthRecommendation(for: weakest))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
            }
            .padding(12)
            .background(Color.orange.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding()
        .appCard(.shop)
    }

    private var closetHealthScores: [ClosetHealthMetric] {
        [
            ClosetHealthMetric(title: "Color Balance", score: 95, icon: "paintpalette.fill"),
            ClosetHealthMetric(title: "Business Ready", score: 89, icon: "briefcase.fill"),
            ClosetHealthMetric(title: "Casual", score: 92, icon: "tshirt.fill"),
            ClosetHealthMetric(title: "Accessories", score: 74, icon: "tag.fill"),
            ClosetHealthMetric(title: "Footwear", score: 81, icon: "shoe.2.fill")
        ]
    }

    private func closetHealthMetricCell(_ metric: ClosetHealthMetric) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: metric.icon)
                    .foregroundStyle(closetHealthTint(for: metric.score))

                Spacer()

                Text("\(metric.score)")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(closetHealthTint(for: metric.score))
            }

            Text(metric.title)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.74)

            ProgressView(value: Double(metric.score), total: 100)
                .tint(closetHealthTint(for: metric.score))
        }
        .frame(maxWidth: .infinity, minHeight: 94, alignment: .topLeading)
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func closetHealthTint(for score: Int) -> Color {
        switch score {
        case 90...100:
            return .green
        case 80...89:
            return AppTab.shop.palette.accent
        default:
            return .orange
        }
    }

    private func closetHealthRecommendation(for metric: ClosetHealthMetric) -> String {
        switch metric.title {
        case "Accessories":
            return "Add one versatile belt, one clean watch, and one neutral bag or hat. These small pieces can improve business, casual, and date-night outfits without rebuilding the closet."
        case "Footwear":
            return "Add shoes that cover missing use cases: clean white sneakers, black loafers, and weather-ready shoes."
        case "Business Ready":
            return "Add one structured jacket and one crisp shirt that match your existing pants and shoes."
        case "Color Balance":
            return "Add one complementary color outside your usual palette to make more outfits feel intentional."
        default:
            return "Add two versatile pieces that match at least five saved outfits and fit your preferred style."
        }
    }

    private var personalShopperRequestCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Label("AI Personal Shopper", systemImage: "sparkles")
                    .font(.headline)

                Spacer()

                Text(selectedOutfitRequest)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(AppTab.shop.palette.accent)
            }

            Text("What do you need today?")
                .font(.title3)
                .fontWeight(.bold)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 8)], spacing: 8) {
                ForEach(shopperNeedOptions, id: \.self) { need in
                    shopperNeedChip(need)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                outfitItemRow(title: "Use from closet", value: "Dark denim and black shoes")
                outfitItemRow(title: "Missing item", value: "White Oxford shirt")
                outfitItemRow(title: "Why", value: "It fits \(selectedOutfitRequest.lowercased()), your \(favoriteColors.lowercased()) palette, and your saved brands: \(favoriteBrands).")
            }
        }
        .padding()
        .appCard(.shop)
    }

    private func shopperNeedChip(_ need: String) -> some View {
        let isSelected = selectedOutfitRequest == need

        return Button {
            selectedOutfitRequest = need
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.caption)

                Text(need)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? .white : .primary)
            .frame(maxWidth: .infinity, minHeight: 42)
            .padding(.horizontal, 12)
            .background(isSelected ? AppTab.shop.palette.accent : Color(.secondarySystemBackground))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var aiSaleRecommendationsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Label("AI Sale Matches", systemImage: "tag.fill")
                    .font(.headline)

                Spacer()

                Text("\(activeSaleItems.count) live sale")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(AppTab.shop.palette.accent)
            }

            Text("StyleMatch Pro only recommends products from the current sale list. The AI cannot invent products, prices, or discounts.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(4)

            if saleRecommendations.isEmpty {
                Text(saleRecommendationMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                ForEach(saleRecommendations) { recommendation in
                    saleRecommendationRow(recommendation)
                }
            }

            Button {
                refreshAISaleRecommendations()
            } label: {
                Label(isLoadingSaleRecommendations ? "Matching Sale Items..." : "Refresh AI Sale Matches", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isLoadingSaleRecommendations)
        }
        .padding()
        .appCard(.shop)
    }

    private func saleRecommendationRow(_ recommendation: ShoppingSaleRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(recommendation.productName)
                        .font(.headline)

                    Text(recommendation.productID)
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(priceHistoryDollarText(recommendation.salePrice))
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundStyle(.green)

                    Text(priceHistoryDollarText(recommendation.originalPrice))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .strikethrough(recommendation.originalPrice > recommendation.salePrice)
                }
            }

            Text(recommendation.reason)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppTab.shop.palette.accent.opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var retailerFilterCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("Retailer Filters", systemImage: "line.3.horizontal.decrease.circle.fill")
                    .font(.headline)

                Spacer()

                Text(selectedRetailerFilter)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(AppTab.shop.palette.accent)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
                ForEach(retailerFilters, id: \.self) { retailer in
                    retailerFilterChip(retailer)
                }
            }

            if selectedRetailerFilter != "All" && filteredProducts.isEmpty {
                Text("No beta recommendations from \(selectedRetailerFilter) yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .appCard(.shop)
    }

    private func retailerFilterChip(_ retailer: String) -> some View {
        let isSelected = selectedRetailerFilter == retailer

        return Button {
            selectedRetailerFilter = retailer
            expandedProductIDs = []
        } label: {
            Text(retailer)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(isSelected ? .white : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
                .frame(maxWidth: .infinity, minHeight: 40)
                .padding(.horizontal, 8)
                .background(isSelected ? AppTab.shop.palette.accent : Color(.secondarySystemBackground))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var savingsSummaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Label("Today's Savings", systemImage: "dollarsign.circle.fill")
                    .font(.headline)

                Spacer()

                Text("Updated today")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(AppTab.shop.palette.accent)
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                savingsMetric(title: "Recommendations", value: "\(recommendationCount)", icon: "bag.fill")
                savingsMetric(title: "Average Discount", value: "\(averageDiscountPercent)%", icon: "percent")
                savingsMetric(title: "Potential Savings", value: "$\(potentialSavings)", icon: "arrow.down.circle.fill")
            }
        }
        .padding()
        .appCard(.shop)
    }

    private func savingsMetric(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(AppTab.shop.palette.accent)

            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(title)
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .padding(10)
        .background(AppTab.shop.palette.accent.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var smartShoppingSections: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Smart Shopping")
                .font(.title2)
                .fontWeight(.bold)

            shoppingSection(
                title: "Best Deals",
                subtitle: "Top value picks based on price, shipping, delivery, and closet usefulness.",
                icon: "flame.fill",
                products: bestDealProducts,
                fallback: "Add budget and favorite stores to improve deal ranking."
            )

            shoppingSection(
                title: "Missing Essentials",
                subtitle: "The wardrobe gaps most likely to unlock more outfits.",
                icon: "jacket",
                products: missingProducts,
                fallback: "Your saved closet already covers the basics. Add more closet items to make this smarter."
            )

            shoppingSection(
                title: "Complete Your Outfit",
                subtitle: "Finishing pieces that pair with your saved colors, pants, shoes, and occasions.",
                icon: "shoe.2",
                products: completeOutfitProducts,
                fallback: "Add pants or outfits to the closet so outfit completion can improve."
            )

            shoppingSection(
                title: "Style Tech",
                subtitle: "Approved electronics partners for wearables, travel, and style-adjacent gear.",
                icon: "applewatch",
                products: products(for: "Electronics"),
                fallback: "Electronics picks will appear when partner product data is available."
            )

            shoppingSection(
                title: "Style Essentials",
                subtitle: "Wardrobe-care and presentation items that make outfits look sharper.",
                icon: "sparkles",
                products: products(for: "Style Essentials"),
                fallback: "Style-related product picks will appear as the partner catalog grows."
            )

            shoppingSection(
                title: "Favorite Brands",
                subtitle: "Recommendations from brands and retailers you already prefer.",
                icon: "heart.fill",
                products: favoriteBrandProducts,
                fallback: "Add favorite brands in Profile to personalize this section."
            )

            shoppingSection(
                title: "Price Drops",
                subtitle: "Items where the sale price is lower than the original price.",
                icon: "arrow.down.circle.fill",
                products: priceDropProducts,
                fallback: "No price drops are available in the current beta list."
            )

            shoppingSection(
                title: "AI Picks",
                subtitle: "Highest closet-compatibility picks for your wardrobe right now.",
                icon: "star.circle.fill",
                products: aiPickProducts,
                fallback: "Scan outfits and save closet items to improve AI picks."
            )

            shoppingSection(
                title: "Trending",
                subtitle: "Popular staples that still work with a practical wardrobe.",
                icon: "chart.line.uptrend.xyaxis",
                products: trendingProducts,
                fallback: "Trending picks will appear as the beta catalog grows."
            )

            shoppingSection(
                title: "Under Your Budget",
                subtitle: "Items that fit your saved budget before taxes or retailer fees.",
                icon: "dollarsign.circle.fill",
                products: underBudgetProducts,
                fallback: "Add a shopping budget in Profile to make this smarter."
            )
        }
    }

    private func shoppingSection(title: String, subtitle: String, icon: String, products: [RetailProduct], fallback: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if products.isEmpty {
                Text(fallback)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .appCard(.shop, radius: 12)
            } else {
                ForEach(products) { product in
                    productCard(product, sectionTitle: title)
                }
            }
        }
        .padding()
        .appCard(.shop)
    }

    private func productCard(_ product: RetailProduct, sectionTitle: String? = nil) -> some View {
        let isExpanded = expandedProductIDs.contains(product.id)
        let saleText = product.salePrice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? product.price : product.salePrice
        let discountText = discountPercentText(for: product)
        let matchScore = productMatchScore(product, sectionTitle: sectionTitle)
        let shopAction = shoppingAction(for: product, sectionTitle: sectionTitle)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                productImage(product)

                VStack(alignment: .leading, spacing: 6) {
                    Text(product.recommendation)
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)

                    Text(product.productName)
                        .font(.headline)

                    HStack(spacing: 6) {
                        Text(starsText(for: matchScore))
                            .font(.caption)
                            .foregroundStyle(.yellow)

                        Text("\(matchScore) Match")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(AppTab.shop.palette.accent)
                    }

                    Text(product.soldAndShippedByText)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)

                    Text(product.marketplaceCategory)
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(AppTab.shop.palette.accent)

                    HStack(spacing: 8) {
                        Text(saleText)
                            .fontWeight(.bold)

                        if let discountText {
                            Text(discountText)
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(.green)
                        }
                    }
                }

                Spacer()
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                productBenefitRow("Matches \(min(7, max(3, closetItems.count + 2))) saved outfit ideas")
                productBenefitRow(sectionTitle == "Missing Essentials" ? "Missing from closet" : "Closet compatible")
                productBenefitRow(discountText == nil ? "Fits your saved style" : product.saleAlert)
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    affiliateDisclosureBlock(product)
                    liveShoppingInsightBlock(product, sectionTitle: sectionTitle)
                    confidenceMeterBlock(product, sectionTitle: sectionTitle, matchScore: matchScore)
                    closetCompatibilityBlock(product, sectionTitle: sectionTitle, matchScore: matchScore)
                    outfitPreviewBlock(product)
                    recommendationBadgesBlock(product, sectionTitle: sectionTitle)
                    detailRow(title: "Sizes", value: product.sizes)
                    detailRow(title: "Colors", value: product.colors)
                    detailRow(title: "Retailer", value: product.storeName)
                    detailRow(title: "Category", value: product.marketplaceCategory)
                    priceHistoryBlock(product)
                    aiComparisonBlock(product, sectionTitle: sectionTitle, matchScore: matchScore)
                    detailRow(title: "Shipping", value: product.shippingCost)
                    detailRow(title: "Delivery", value: product.estimatedDelivery)
                    detailRow(title: "Purchase page", value: "Opens \(product.storeName)")

                    Label(product.bestValueNote, systemImage: "tag")
                        .font(.subheadline)
                        .foregroundStyle(.green)

                    Text(product.matchReason)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineSpacing(4)
                }
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            if FeatureGate.shared.isCustomerVisible(.smartWishlist) {
                HStack(spacing: 12) {
                    Button {
                        toggleProductDetails(product)
                    } label: {
                        Label(isExpanded ? "Hide Details" : "View Details", systemImage: isExpanded ? "chevron.up" : "chevron.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Button {
                        toggleWishlist(product)
                    } label: {
                        Label(
                            wishlistProductNames.contains(product.productName) ? "Saved" : "Save",
                            systemImage: wishlistProductNames.contains(product.productName) ? "heart.fill" : "heart"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }

                HStack(spacing: 12) {

                    if let productURL = URL(string: product.affiliateURL) {
                        Link(destination: productURL) {
                            Label(shopAction.title, systemImage: shopAction.icon)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    } else {
                        Label("Store link unavailable", systemImage: "exclamationmark.triangle")
                            .frame(maxWidth: .infinity)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Button {
                    toggleProductDetails(product)
                } label: {
                    Label(isExpanded ? "Hide Details" : "View Details", systemImage: isExpanded ? "chevron.up" : "chevron.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                if let productURL = URL(string: product.affiliateURL) {
                    Link(destination: productURL) {
                        Label(shopAction.title, systemImage: shopAction.icon)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    Label("Store link unavailable", systemImage: "exclamationmark.triangle")
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .appCard(.shop)
    }

    private func productBenefitRow(_ text: String) -> some View {
        Label(text, systemImage: "checkmark")
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(.primary)
            .lineLimit(2)
            .minimumScaleFactor(0.84)
    }

    private func productImage(_ product: RetailProduct) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray5))

            if let url = URL(string: product.imageURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        fallbackProductIcon(for: product)
                    @unknown default:
                        fallbackProductIcon(for: product)
                    }
                }
            } else {
                fallbackProductIcon(for: product)
            }
        }
        .frame(width: 86, height: 86)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func fallbackProductIcon(for product: RetailProduct) -> some View {
        Image(systemName: iconName(for: product.recommendation))
            .font(.system(size: 30))
            .foregroundStyle(.secondary)
    }

    private func affiliateDisclosureBlock(_ product: RetailProduct) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(product.soldAndShippedByText, systemImage: "storefront.fill")
                .font(.subheadline)
                .fontWeight(.bold)

            Text(product.retailerResponsibilityText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(3)

            Text("StyleMatch Pro may earn commission from qualifying purchases. Tracking ID: \(product.affiliateTrackingID).")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(AppTab.shop.palette.accent)
        }
        .padding(12)
        .background(AppTab.shop.palette.accent.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppTab.shop.palette.accent.opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func liveShoppingInsightBlock(_ product: RetailProduct, sectionTitle: String?) -> some View {
        let insight = liveShoppingInsight(for: product, sectionTitle: sectionTitle)

        return HStack(alignment: .center, spacing: 10) {
            Image(systemName: insight.icon)
                .font(.headline)
                .foregroundStyle(insight.tint)
                .frame(width: 28, height: 28)
                .background(insight.tint.opacity(0.12))
                .clipShape(Circle())

            Text(insight.message)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.82)

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(insight.tint.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(insight.tint.opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func priceHistoryBlock(_ product: RetailProduct) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Price History", systemImage: "chart.line.uptrend.xyaxis")
                .font(.subheadline)
                .fontWeight(.bold)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                priceHistoryMetric(title: "Current", value: priceHistoryCurrentText(for: product), tint: AppTab.shop.palette.accent)
                priceHistoryMetric(title: "Lowest in 90 days", value: priceHistoryLowestText(for: product), tint: .green)
                priceHistoryMetric(title: "Average", value: priceHistoryAverageText(for: product), tint: .secondary)
            }
        }
        .padding(12)
        .background(AppTab.shop.palette.accent.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func priceHistoryMetric(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.72)

            Text(value)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .topLeading)
        .padding(10)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func aiComparisonBlock(_ product: RetailProduct, sectionTitle: String?, matchScore: Int) -> some View {
        let other = comparisonAlternative(for: product, sectionTitle: sectionTitle, matchScore: matchScore)

        return VStack(alignment: .leading, spacing: 12) {
            Label("AI Comparison", systemImage: "sparkles")
                .font(.subheadline)
                .fontWeight(.bold)

            comparisonOptionRow(
                title: "This one",
                matchText: "\(matchScore) Match",
                priceText: compactPriceText(for: product),
                outfitText: "Matches \(matchingOutfitCount(for: product)) outfits",
                isRecommended: true
            )

            Image(systemName: "arrow.down")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(AppTab.shop.palette.accent)
                .frame(maxWidth: .infinity)

            comparisonOptionRow(
                title: "Other one",
                matchText: "\(other.matchScore) Match",
                priceText: other.price,
                outfitText: "Matches \(other.outfitCount) outfits",
                isRecommended: false
            )
        }
        .padding(12)
        .background(Color(.systemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppTab.shop.palette.accent.opacity(0.2), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func comparisonOptionRow(title: String, matchText: String, priceText: String, outfitText: String, isRecommended: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)

                Text(matchText)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(isRecommended ? AppTab.shop.palette.accent : .secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 5) {
                Text(priceText)
                    .font(.headline)
                    .fontWeight(.bold)

                Text(outfitText)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .padding(10)
        .background(isRecommended ? AppTab.shop.palette.accent.opacity(0.1) : Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func confidenceMeterBlock(_ product: RetailProduct, sectionTitle: String?, matchScore: Int) -> some View {
        let confidence = recommendationConfidence(for: product, sectionTitle: sectionTitle, matchScore: matchScore)

        return HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("AI Recommendation")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)

                Text("\(confidence)%")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(AppTab.shop.palette.accent)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("Confidence")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)

                Text(starsText(for: confidence))
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(.yellow)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppTab.shop.palette.accent.opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func closetCompatibilityBlock(_ product: RetailProduct, sectionTitle: String?, matchScore: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Closet Compatibility")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)

                    Text(matchLabel(for: matchScore))
                        .font(.headline)
                        .fontWeight(.bold)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(matchScore)%")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(AppTab.shop.palette.accent)

                    Text("Match")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)
                }
            }

            Text("Works with \(matchingOutfitCount(for: product)) saved outfits.")
                .font(.subheadline)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 7) {
                ForEach(compatibleClosetPieces(for: product), id: \.self) { piece in
                    productBenefitRow(piece)
                }
                productBenefitRow(smartBenefitText(for: product, sectionTitle: sectionTitle))
            }
        }
        .padding(12)
        .background(AppTab.shop.palette.accent.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppTab.shop.palette.accent.opacity(0.22), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func outfitPreviewBlock(_ product: RetailProduct) -> some View {
        let outfitItems = outfitPreviewItems(for: product)

        return VStack(alignment: .leading, spacing: 12) {
            Label("How this completes your closet", systemImage: "square.grid.2x2.fill")
                .font(.subheadline)
                .fontWeight(.bold)

            VStack(spacing: 8) {
                ForEach(Array(outfitItems.enumerated()), id: \.offset) { index, item in
                    VStack(spacing: 8) {
                        outfitPreviewItem(item, isNew: index == 0)

                        if index < outfitItems.count - 1 {
                            Image(systemName: "arrow.down")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(AppTab.shop.palette.accent)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.55), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func outfitPreviewItem(_ item: OutfitPreviewItem, isNew: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.icon)
                .font(.headline)
                .foregroundStyle(isNew ? .white : item.tint)
                .frame(width: 38, height: 38)
                .background(isNew ? AppTab.shop.palette.accent : item.tint.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            Text(item.name)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 0)

            if isNew {
                Text("New")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(AppTab.shop.palette.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppTab.shop.palette.accent.opacity(0.12))
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func recommendationBadgesBlock(_ product: RetailProduct, sectionTitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recommended because")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(recommendationBadges(for: product, sectionTitle: sectionTitle), id: \.self) { badge in
                    recommendationBadge(badge)
                }
            }
        }
    }

    private func recommendationBadge(_ title: String) -> some View {
        Label(title, systemImage: "checkmark.circle.fill")
            .font(.caption)
            .fontWeight(.bold)
            .foregroundStyle(.green)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            .padding(.horizontal, 10)
            .background(Color.green.opacity(0.1))
            .clipShape(Capsule())
    }

    private var wishlistCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Smart wishlist", systemImage: "heart")
                .font(.headline)

            if wishlistProductNames.isEmpty {
                Text("Saved products will appear here. Later the app will notify users about price drops, new colors, size restocks, and sharing.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(wishlistProductNames).sorted(), id: \.self) { productName in
                    Label(productName, systemImage: "heart.fill")
                        .foregroundStyle(.secondary)
                }

                Text("Wishlist saves are active on this phone. Price-drop and restock alerts need retailer integrations before release.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .appCard(.shop)
    }

    private var affiliateMarketplaceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Affiliate marketplace", systemImage: "link")
                .font(.headline)

            Text("StyleMatch Pro is a shopping guide, not the seller. Product taps open approved retailer pages. Retailers handle checkout, payment, fulfillment, shipping, refunds, returns, and customer service.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(4)

            Picker("Preferred size", selection: $selectedSize) {
                ForEach(sizeChoices, id: \.self) { size in
                    Text(size).tag(size)
                }
            }
            .pickerStyle(.menu)

            Picker("Color", selection: $selectedColor) {
                ForEach(colorChoices, id: \.self) { color in
                    Text(color).tag(color)
                }
            }
            .pickerStyle(.menu)

            VStack(alignment: .leading, spacing: 8) {
                outfitItemRow(title: "Marketplace role", value: "StyleMatch Pro recommends and links. It does not process payments or sell inventory.")
                outfitItemRow(title: "Purchase flow", value: "Tap a product to open the retailer purchase page with affiliate tracking.")
                outfitItemRow(title: "Retailer responsibility", value: "The approved retailer owns checkout, fulfillment, shipping, refunds, returns, and support.")
                outfitItemRow(title: "Affiliate disclosure", value: "StyleMatch Pro may earn commission from qualifying purchases.")
            }
        }
        .padding()
        .appCard(.shop)
    }

    private var smartShoppingSummary: String {
        if closetItems.isEmpty {
            return "Add a few closet items first. Style Match Pro will then suggest missing pieces, matching shoes, jackets, accessories, price drops, and best deals around your real wardrobe."
        }

        return "Based on \(closetItems.count) saved closet item\(closetItems.count == 1 ? "" : "s"), \(stylePreferences.lowercased()), \(sizeProfile), and budget \(budget), these shopping sections focus on what improves your wardrobe next."
    }

    private var personalShopperFallbackAdvice: String {
        "For \(selectedOutfitRequest.lowercased()), start with pieces already in your closet, then buy only the missing item that works with multiple outfits, fits \(budget), and matches your saved sizes."
    }

    private var activeSaleItems: [ShoppingSaleItem] {
        let profile = ProfileStore().currentProfile
        let budgetAndSizeEligibleProducts = products.filter { product in
            guard let original = currencyValue(product.originalPrice),
                  let sale = currencyValue(product.salePrice) else {
                return false
            }

            return original > sale
                && isWithinProfileBudget(salePrice: sale, profile: profile)
                && matchesProfileSize(product: product, profile: profile)
        }

        let occasionEligibleProducts = budgetAndSizeEligibleProducts.filter {
            matchesShoppingOccasion(product: $0, request: selectedOutfitRequest)
        }
        let eligibleProducts = occasionEligibleProducts.isEmpty ? budgetAndSizeEligibleProducts : occasionEligibleProducts

        let eligibleSaleItems = eligibleProducts.compactMap { product -> ShoppingSaleItem? in
            guard let original = currencyValue(product.originalPrice),
                  let sale = currencyValue(product.salePrice) else {
                return nil
            }

            return ShoppingSaleItem(
                id: productInventoryID(for: product),
                name: product.productName,
                category: product.marketplaceCategory,
                color: product.colors,
                price: original,
                salePrice: sale,
                saleAlert: product.saleAlert,
                retailerName: product.storeName,
                brand: product.storeName,
                imageURL: product.imageURL,
                affiliateURL: product.affiliateURL,
                affiliateTrackingID: product.affiliateTrackingID
            )
        }

        let preferredBrands = normalizedProfileBrands(profile.favoriteBrands)
        guard !preferredBrands.isEmpty else {
            return eligibleSaleItems
        }

        let preferredBrandItems = eligibleSaleItems.filter { item in
            preferredBrands.contains(item.brand.lowercased())
        }

        return preferredBrandItems.isEmpty ? eligibleSaleItems : preferredBrandItems
    }

    private var occasionInventoryFilterNote: String {
        let profile = ProfileStore().currentProfile
        let budgetAndSizeEligibleProducts = products.filter { product in
            guard let original = currencyValue(product.originalPrice),
                  let sale = currencyValue(product.salePrice) else {
                return false
            }

            return original > sale
                && isWithinProfileBudget(salePrice: sale, profile: profile)
                && matchesProfileSize(product: product, profile: profile)
        }

        guard !budgetAndSizeEligibleProducts.isEmpty else {
            return "No sale items fit the saved budget and size filters."
        }

        let exactOccasionMatches = budgetAndSizeEligibleProducts.filter {
            matchesShoppingOccasion(product: $0, request: selectedOutfitRequest)
        }

        return exactOccasionMatches.isEmpty
            ? "No exact sale matches fit \(selectedOutfitRequest.lowercased()), so StyleMatch Pro is showing the closest budget and size matches."
            : "Sale items were filtered for \(selectedOutfitRequest.lowercased()) where product data allowed."
    }

    private var recentOutfitHistory: [ShoppingOutfitHistoryItem] {
        guard !outfitScanHistoryData.isEmpty,
              let history = try? JSONDecoder().decode([String: ShoppingStoredOutfitScan].self, from: outfitScanHistoryData) else {
            return []
        }

        let cutoff = Date().addingTimeInterval(-14 * 24 * 60 * 60)
        return history.values
            .filter { $0.firstScannedAt > cutoff }
            .sorted { $0.firstScannedAt > $1.firstScannedAt }
            .prefix(14)
            .map { scan in
                ShoppingOutfitHistoryItem(
                    detectedGarments: scan.analysis?.safeDetectedClothingItems ?? [],
                    colors: scan.analysis?.colorPalette ?? [],
                    detectedStyle: scan.analysis?.styleBalance ?? "Unknown",
                    scannedAt: scan.firstScannedAt
                )
            }
    }

    private var currentShoppingAnalysis: ShoppingCurrentAnalysis {
        ShoppingCurrentAnalysis(
            request: selectedOutfitRequest,
            favoriteColors: favoriteColors,
            favoriteBrands: favoriteBrands,
            budget: budget,
            sizeProfile: sizeProfile,
            stylePreferences: stylePreferences,
            occasions: occasions,
            weather: weather,
            closetInventory: closetInventory,
            closetItems: closetItems.map { "\($0.name) \($0.category) \($0.color) \($0.brand) \($0.size)" }
        )
    }

    private func refreshAISaleRecommendations() {
        let saleItems = activeSaleItems
        guard !saleItems.isEmpty else {
            saleRecommendations = []
            saleRecommendationMessage = "No sale items fit your saved budget, sizes, occasion, and profile filters right now."
            return
        }

        guard let savedKey = OpenAIKeychain.loadAPIKey()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !savedKey.isEmpty else {
            saleRecommendations = localValidatedSaleRecommendations(from: saleItems)
            saleRecommendationMessage = "ChatGPT is not connected, so StyleMatch Pro ranked the current sale list locally."
            return
        }

        isLoadingSaleRecommendations = true
        saleRecommendationMessage = "Matching real sale products to your recent outfits..."

        let outfitHistory = recentOutfitHistory
        let currentAnalysis = currentShoppingAnalysis
        let prompt = buildShoppingPrompt(
            saleItems: saleItems,
            outfitHistory: outfitHistory,
            currentAnalysis: currentAnalysis
        )
        let profile = StyleMatchStylistProfile(
            name: "StyleMatch Pro Shopper",
            favoriteColors: favoriteColors,
            favoriteBrands: favoriteBrands,
            preferredFit: sizeProfile,
            budget: budget,
            sizeProfile: sizeProfile,
            stylePreferences: stylePreferences,
            occasions: occasions,
            weather: weather,
            weatherPreferences: weather,
            dressCode: selectedOutfitRequest,
            shoppingHabits: "Only recommend real sale items from the sale item JSON.",
            pastOutfitRatings: outfitHistory.map { "\($0.detectedStyle): \($0.colors.joined(separator: ", "))" }.joined(separator: "; "),
            frequentlyWornOutfits: favoriteOutfits,
            pastPurchases: pastPurchases,
            favoriteOutfits: favoriteOutfits,
            closetInventory: closetInventory,
            appContextSharingEnabled: true,
            appContext: "Smart Shopping sale recommendation request. AI must not invent products, prices, discounts, or product IDs."
        )

        Task {
            do {
                let client = OpenAIStylistClient(apiKey: savedKey, model: openAIModel)
                let response = try await client.askStylist(profile: profile, question: prompt)
                let parsed = parseShoppingRecommendations(from: response, saleItems: saleItems)

                await MainActor.run {
                    saleRecommendations = parsed.recommendations
                    saleRecommendationMessage = parsed.message ?? (parsed.recommendations.isEmpty ? "No validated sale matches came back. Try again after adding more closet or scan history." : "Matched against real sale inventory.")
                    isLoadingSaleRecommendations = false
                }
            } catch {
                await MainActor.run {
                    saleRecommendations = localValidatedSaleRecommendations(from: saleItems)
                    saleRecommendationMessage = "Live AI sale matching is unavailable, so StyleMatch Pro ranked real sale items locally."
                    isLoadingSaleRecommendations = false
                }
            }
        }
    }

    private func buildShoppingPrompt(saleItems: [ShoppingSaleItem], outfitHistory: [ShoppingOutfitHistoryItem], currentAnalysis: ShoppingCurrentAnalysis) -> String {
        let stylistProfile = ProfileStore().currentProfile
        let outfitMemories = OutfitMemoryStore().memories
        let personalStylistMemorySection = PersonalizationContextBuilder.promptSection(
            title: "PERSONAL STYLIST MEMORY (ranking context only; the eligible sale list above is already filtered by budget, size, occasion, and available product data)",
            profile: stylistProfile,
            recentMemories: outfitMemories
        )

        return """
        You are StyleMatch AI's Shopping Assistant. StyleMatch Pro is an affiliate marketplace and personal shopping guide, not a direct seller. It does not process payments, hold inventory, ship orders, manage refunds, or handle returns. Approved retailers own checkout, fulfillment, shipping, refunds, returns, and customer service.

        StyleMatch Pro has already pre-filtered the sale list deterministically by the user's saved budget, sizes, selected occasion, and brand preferences where available. Your job is only to rank and explain the eligible items below. Do not re-add filtered-out items. Do not invent products, prices, discounts, product IDs, retailer names, image URLs, affiliate URLs, or tracking IDs.

        ELIGIBLE SALE ITEMS (real inventory, only recommend from this list):
        \(jsonString(saleItems))

        USER'S RECENT OUTFIT HISTORY:
        \(jsonString(outfitHistory))

        CURRENT OUTFIT ANALYSIS:
        \(jsonString(currentAnalysis))

        OCCASION FILTER:
        \(currentAnalysis.request)
        \(occasionInventoryFilterNote)

        \(personalStylistMemorySection)

        Return ONLY valid JSON:
        {
          "recommendations": [
            {
              "product_id": "string - must match an id from sale items",
              "product_name": "string",
              "reason": "string - why this matches their style, referencing specific past outfit or current outfit",
              "sale_price": number,
              "original_price": number
            }
          ]
        }
        """
    }

    private func parseShoppingRecommendations(from response: String, saleItems: [ShoppingSaleItem]) -> ShoppingRecommendationsResponse {
        let cleaned = response
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let jsonText: String
        if let start = cleaned.firstIndex(of: "{"),
           let end = cleaned.lastIndex(of: "}"),
           start <= end {
            jsonText = String(cleaned[start...end])
        } else {
            jsonText = cleaned
        }

        guard let data = jsonText.data(using: .utf8),
              let parsed = try? JSONDecoder().decode(ShoppingRecommendationsResponse.self, from: data) else {
            return ShoppingRecommendationsResponse(recommendations: localValidatedSaleRecommendations(from: saleItems), message: "The AI response could not be parsed, so StyleMatch Pro used validated sale items.")
        }

        let realSaleItems = Dictionary(uniqueKeysWithValues: saleItems.map { ($0.id, $0) })
        let validated = parsed.recommendations.compactMap { recommendation -> ShoppingSaleRecommendation? in
            guard let realItem = realSaleItems[recommendation.productID] else {
                return nil
            }

            return ShoppingSaleRecommendation(
                productID: realItem.id,
                productName: realItem.name,
                reason: recommendation.reason,
                salePrice: realItem.salePrice,
                originalPrice: realItem.price
            )
        }

        return ShoppingRecommendationsResponse(
            recommendations: Array(validated.prefix(5)),
            message: validated.isEmpty ? "No AI recommendation matched the real sale list." : parsed.message
        )
    }

    private func localValidatedSaleRecommendations(from saleItems: [ShoppingSaleItem]) -> [ShoppingSaleRecommendation] {
        let sorted = saleItems.sorted { first, second in
            let firstSavings = first.price - first.salePrice
            let secondSavings = second.price - second.salePrice
            return firstSavings > secondSavings
        }

        return sorted.prefix(3).map { item in
            ShoppingSaleRecommendation(
                productID: item.id,
                productName: item.name,
                reason: "This is a real sale item from \(item.brand). \(occasionInventoryFilterNote) It matches your saved style profile, budget \(budget), and closet-aware shopping request.",
                salePrice: item.salePrice,
                originalPrice: item.price
            )
        }
    }

    private func productInventoryID(for product: RetailProduct) -> String {
        "\(product.storeName)-\(product.productName)"
            .lowercased()
            .replacingOccurrences(of: "&", with: "and")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }

    private func jsonString<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }

    private var missingProducts: [RetailProduct] {
        var recommendations: [RetailProduct] = []

        if !hasAnyCategory(["Jacket"]) {
            recommendations.append(contentsOf: products(for: "Jackets"))
        }
        if !hasAnyCategory(["Shoes"]) {
            recommendations.append(contentsOf: products(for: "Shoes"))
        }
        if !hasAnyCategory(["Accessory", "Bag", "Hat"]) {
            recommendations.append(contentsOf: products(for: "Accessories"))
        }
        if !hasAnyCategory(["Shirt", "Dress"]) {
            recommendations.append(contentsOf: products(for: "Shirts"))
        }
        if !hasAnyCategory(["Pants", "Jeans"]) {
            recommendations.append(contentsOf: products(for: "Jeans"))
        }

        return Array(recommendations.removingDuplicateProducts().prefix(5))
    }

    private var filteredProducts: [RetailProduct] {
        let weatherEligibleProducts = products.filter(weatherAllowsProduct)
        guard selectedRetailerFilter != "All" else {
            return weatherEligibleProducts
        }

        return weatherEligibleProducts.filter { product in
            product.storeName.localizedCaseInsensitiveContains(selectedRetailerFilter)
        }
    }

    private var priceDropProducts: [RetailProduct] {
        filteredProducts.filter { $0.salePrice != $0.originalPrice }
    }

    private var bestDealProducts: [RetailProduct] {
        filteredProducts
            .filter { !$0.bestValueNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { dealScore($0) > dealScore($1) }
    }

    private var completeOutfitProducts: [RetailProduct] {
        Array((products(for: "Shoes") + products(for: "Accessories") + products(for: "Jackets")).removingDuplicateProducts().prefix(5))
    }

    private var favoriteBrandProducts: [RetailProduct] {
        let preferred = filteredProducts.filter { product in
            favoriteBrands.localizedCaseInsensitiveContains(product.storeName)
                || favoriteBrands.localizedCaseInsensitiveContains(product.productName)
        }

        return preferred.isEmpty && selectedRetailerFilter == "All" ? Array(bestDealProducts.prefix(3)) : preferred
    }

    private var aiPickProducts: [RetailProduct] {
        filteredProducts.sorted {
            productMatchScore($0, sectionTitle: "AI Picks") > productMatchScore($1, sectionTitle: "AI Picks")
        }
    }

    private var trendingProducts: [RetailProduct] {
        let preferredOrder = ["White Oxford Shirt", "Structured Navy Blazer", "Clean Leather Sneaker", "Slim Dark Denim", "Black Leather Belt"]
        return filteredProducts.sorted { first, second in
            (preferredOrder.firstIndex(of: first.productName) ?? Int.max) < (preferredOrder.firstIndex(of: second.productName) ?? Int.max)
        }
    }

    private var underBudgetProducts: [RetailProduct] {
        filteredProducts.filter(fitsBudget)
    }

    private var recommendationCount: Int {
        filteredProducts.count
    }

    private var discountedProducts: [RetailProduct] {
        filteredProducts.filter { product in
            guard let original = currencyValue(product.originalPrice),
                  let sale = currencyValue(product.salePrice) else {
                return false
            }
            return original > sale
        }
    }

    private var averageDiscountPercent: Int {
        let percents = discountedProducts.compactMap { product -> Double? in
            guard let original = currencyValue(product.originalPrice),
                  let sale = currencyValue(product.salePrice),
                  original > sale else {
                return nil
            }
            return (original - sale) / original * 100
        }

        guard !percents.isEmpty else {
            return 0
        }

        return Int((percents.reduce(0, +) / Double(percents.count)).rounded())
    }

    private var potentialSavings: Int {
        let savings = discountedProducts.reduce(0.0) { total, product in
            guard let original = currencyValue(product.originalPrice),
                  let sale = currencyValue(product.salePrice),
                  original > sale else {
                return total
            }
            return total + (original - sale)
        }

        return Int(savings.rounded())
    }

    private func products(for recommendation: String) -> [RetailProduct] {
        filteredProducts.filter { $0.recommendation == recommendation }
    }

    private func weatherAllowsProduct(_ product: RetailProduct) -> Bool {
        guard isHotShoppingWeather else {
            return true
        }

        let evidence = "\(product.recommendation) \(product.productName) \(product.matchReason)".lowercased()
        return !evidence.containsAny(["jacket", "blazer", "coat", "sweater", "layer"])
    }

    private var isHotShoppingWeather: Bool {
        guard let temperature = firstTemperatureValue(in: weather) else {
            return false
        }

        return temperature >= 80
    }

    private func firstTemperatureValue(in text: String) -> Double? {
        let candidates = text
            .split { !$0.isNumber && $0 != "." }
            .compactMap { Double($0) }

        return candidates.first
    }

    private func hasAnyCategory(_ categories: [String]) -> Bool {
        closetItems.contains { item in
            categories.contains(item.category)
        }
    }

    private func dealScore(_ product: RetailProduct) -> Int {
        var score = 0
        if product.salePrice != product.originalPrice {
            score += 3
        }
        if product.shippingCost.localizedCaseInsensitiveContains("free") || product.shippingCost.localizedCaseInsensitiveContains("$0") {
            score += 2
        }
        if favoriteBrands.localizedCaseInsensitiveContains(product.storeName) {
            score += 2
        }
        if missingProducts.contains(where: { $0.productName == product.productName }) {
            score += 2
        }
        return score
    }

    private func smartReason(for product: RetailProduct, sectionTitle: String) -> String {
        switch sectionTitle {
        case "Missing Essentials":
            return "Suggested because this category is missing or underbuilt in your closet."
        case "Complete Your Outfit":
            return "Chosen to finish outfits around your saved colors, pants, shoes, and occasions."
        case "Favorite Brands":
            return "Chosen because it matches a brand or retailer preference in your style profile."
        case "Trending":
            return "Chosen as a popular staple that still works with your wardrobe."
        case "Under Your Budget":
            return "Chosen because it fits your saved shopping budget."
        case "Recommended Jackets":
            return "Chosen to add polish and layering options around your saved outfits."
        case "Shoes that match your closet":
            return "Chosen to pair with your saved colors, pants, and everyday outfits."
        case "Accessories":
            return "Chosen as a small item that can improve multiple outfits."
        case "Price Drops":
            return "Shown because the sale price is lower than the original price."
        case "Best Deals":
            return "Ranked for value using price, shipping, brand fit, and closet usefulness."
        default:
            return product.matchReason
        }
    }

    private func smartBenefitText(for product: RetailProduct, sectionTitle: String?) -> String {
        switch sectionTitle {
        case "Missing Essentials":
            return "Missing from closet"
        case "Price Drops":
            return "Price drop found"
        case "Best Deals":
            return "Strong value pick"
        case "Favorite Brands":
            return "Favorite brand"
        case "Under Your Budget":
            return "Fits your budget"
        case "AI Picks":
            return "AI picked for you"
        case "Trending":
            return "Trending staple"
        default:
            if missingProducts.contains(where: { $0.productName == product.productName }) {
                return "Missing from closet"
            }
            return "Fits your wardrobe"
        }
    }

    private func shoppingAction(for product: RetailProduct, sectionTitle: String?) -> (title: String, icon: String) {
        switch sectionTitle {
        case "Best Deals", "Price Drops", "Under Your Budget":
            return ("Open Retailer Deal", "tag.fill")
        case "Complete Your Outfit":
            return ("Open Retailer Page", "storefront.fill")
        case "AI Picks", "Trending":
            return ("Open Affiliate Page", "link")
        case "Missing Essentials":
            return ("Open \(product.storeName)", "storefront.fill")
        default:
            return ("View at \(product.storeName)", "arrow.up.forward.app.fill")
        }
    }

    private func comparisonAlternative(for product: RetailProduct, sectionTitle: String?, matchScore: Int) -> AIComparisonOption {
        let currentValue = currencyValue(product.salePrice) ?? currencyValue(product.price) ?? 69
        let lowerPrice = max(19, floor(currentValue * 0.86))
        let scoreDrop = sectionTitle == "Best Deals" || sectionTitle == "AI Picks" ? 12 : 14
        let outfitDrop = product.recommendation == "Accessories" ? 2 : 5

        return AIComparisonOption(
            matchScore: max(70, matchScore - scoreDrop),
            price: "$\(Int(lowerPrice))",
            outfitCount: max(1, matchingOutfitCount(for: product) - outfitDrop)
        )
    }

    private func recommendationBadges(for product: RetailProduct, sectionTitle: String?) -> [String] {
        var badges: [String] = []

        if sectionTitle == "Missing Essentials" || missingProducts.contains(where: { $0.productName == product.productName }) {
            badges.append("Missing Item")
        }

        badges.append("Matches \(matchingOutfitCount(for: product)) outfits")

        if product.salePrice != product.originalPrice {
            badges.append("On Sale")
        }

        if fitsBudget(product) {
            badges.append("Fits your budget")
        }

        if favoriteBrands.localizedCaseInsensitiveContains(product.storeName) {
            badges.append("Favorite Brand")
        }

        if product.shippingCost.localizedCaseInsensitiveContains("free") || product.shippingCost.localizedCaseInsensitiveContains("$0") {
            badges.append("Best Value")
        }

        if badges.count < 5 {
            badges.append(bestPriceText(for: product))
        }

        return Array(badges.prefix(5))
    }

    private func fitsBudget(_ product: RetailProduct) -> Bool {
        guard let sale = currencyValue(product.salePrice.isEmpty ? product.price : product.salePrice) else {
            return true
        }

        let budgetNumbers = budget
            .split { !$0.isNumber && $0 != "." }
            .compactMap { Double($0) }

        guard let maxBudget = budgetNumbers.max() else {
            return true
        }

        return sale <= maxBudget
    }

    private func isWithinProfileBudget(salePrice: Double, profile: StylistProfile) -> Bool {
        salePrice >= profile.budgetRange.minPrice && salePrice <= profile.budgetRange.maxPrice
    }

    private func normalizedProfileBrands(_ brands: [String]) -> Set<String> {
        Set(
            brands
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )
    }

    private func matchesProfileSize(product: RetailProduct, profile: StylistProfile) -> Bool {
        let category = product.recommendation.lowercased()
        let sizeText = product.sizes.lowercased()

        if category.contains("shirt"),
           let shirtSize = profile.clothingSizes.shirtSize,
           !sizeTextSupports(size: shirtSize, in: sizeText) {
            return false
        }

        if category.contains("jacket"),
           let jacketSize = profile.clothingSizes.jacketSize ?? profile.clothingSizes.shirtSize,
           !sizeTextSupports(size: jacketSize, in: sizeText) {
            return false
        }

        if category.contains("jean") || category.contains("pant"),
           let pantSize = profile.clothingSizes.pantSize,
           !sizeTextSupports(size: pantSize, in: sizeText) {
            return false
        }

        if category.contains("shoe"),
           let shoeSize = profile.clothingSizes.shoeSize,
           !sizeTextSupports(size: shoeSize, in: sizeText) {
            return false
        }

        return true
    }

    private func matchesShoppingOccasion(product: RetailProduct, request: String) -> Bool {
        let occasion = Occasion(label: request)
        let evidence = [
            product.recommendation,
            product.productName,
            product.matchReason,
            product.colors,
            product.bestValueNote
        ]
        .joined(separator: " ")
        .lowercased()

        switch occasion {
        case .wedding, .formalEvent:
            if evidence.containsAny(["sneaker", "jeans", "denim", "athleisure", "gym", "hoodie"]) {
                return false
            }
            return true
        case .work:
            if evidence.containsAny(["gym", "athleisure", "swim", "sleepwear", "pajama"]) {
                return false
            }
            return true
        case .dateNight:
            if evidence.containsAny(["gym", "athleisure", "sleepwear", "pajama"]) {
                return false
            }
            return true
        case .travel, .casual, .general, .other, nil:
            return true
        }
    }

    private func sizeTextSupports(size: String, in sizeText: String) -> Bool {
        let normalizedSize = size
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !normalizedSize.isEmpty else {
            return true
        }

        if sizeText.contains(normalizedSize) {
            return true
        }

        if normalizedSize.contains("xl") || normalizedSize.contains("xxl") || normalizedSize.contains("2xl") {
            return sizeText.contains("xxs-8xl") || sizeText.contains("shirt")
        }

        if normalizedSize.range(of: #"^\d+x\d+$"#, options: .regularExpression) != nil {
            return sizeText.contains(normalizedSize) || sizeText.contains("24w-60w")
        }

        if Double(normalizedSize) != nil {
            return sizeText.contains(normalizedSize) || sizeText.contains("5-18")
        }

        return true
    }

    private func bestPriceText(for product: RetailProduct) -> String {
        if product.salePrice != product.originalPrice {
            return "Best price today"
        }
        if product.shippingCost.localizedCaseInsensitiveContains("free") || product.shippingCost.localizedCaseInsensitiveContains("$0") {
            return "Best delivery value"
        }
        return "Worth comparing"
    }

    private func liveShoppingInsight(for product: RetailProduct, sectionTitle: String?) -> LiveShoppingInsight {
        if sectionTitle == "Price Drops", let drop = priceDropAmount(for: product), drop > 0 {
            return LiveShoppingInsight(
                message: "Price dropped $\(drop) since yesterday",
                icon: "flame.fill",
                tint: .orange
            )
        }

        if sectionTitle == "Complete Your Outfit" {
            return LiveShoppingInsight(
                message: "Completes \(matchingOutfitCount(for: product)) outfits",
                icon: "star.fill",
                tint: .yellow
            )
        }

        if sectionTitle == "Best Deals" || product.shippingCost.localizedCaseInsensitiveContains("free") {
            return LiveShoppingInsight(
                message: "Best value this week",
                icon: "trophy.fill",
                tint: .green
            )
        }

        if sectionTitle == "Trending" {
            return LiveShoppingInsight(
                message: "Trending with professionals",
                icon: "chart.line.uptrend.xyaxis",
                tint: .blue
            )
        }

        if sectionTitle == "Under Your Budget" && product.salePrice == product.originalPrice {
            return LiveShoppingInsight(
                message: "AI says wait - this usually goes on sale",
                icon: "brain.head.profile",
                tint: .purple
            )
        }

        return LiveShoppingInsight(
            message: "Completes \(matchingOutfitCount(for: product)) outfits",
            icon: "star.fill",
            tint: AppTab.shop.palette.accent
        )
    }

    private func priceDropAmount(for product: RetailProduct) -> Int? {
        guard let original = currencyValue(product.originalPrice),
              let sale = currencyValue(product.salePrice),
              original > sale else {
            return nil
        }

        return Int((original - sale).rounded())
    }

    private func matchingOutfitCount(for product: RetailProduct) -> Int {
        let base = max(3, min(8, closetItems.count + 3))
        switch product.recommendation {
        case "Shirts", "Shoes":
            return base + 2
        case "Jackets":
            return base + 1
        default:
            return base
        }
    }

    private func productMatchScore(_ product: RetailProduct, sectionTitle: String?) -> Int {
        var score = 88 + min(6, dealScore(product))
        if sectionTitle == "Missing Essentials" || missingProducts.contains(where: { $0.productName == product.productName }) {
            score += 3
        }
        if favoriteBrands.localizedCaseInsensitiveContains(product.storeName) {
            score += 2
        }
        return min(99, score)
    }

    private func recommendationConfidence(for product: RetailProduct, sectionTitle: String?, matchScore: Int) -> Int {
        var confidence = matchScore

        if matchingOutfitCount(for: product) >= 5 {
            confidence += 2
        }
        if product.salePrice != product.originalPrice {
            confidence += 1
        }
        if sectionTitle == "AI Picks" || sectionTitle == "Best Deals" {
            confidence += 1
        }

        return min(99, confidence)
    }

    private func matchLabel(for score: Int) -> String {
        switch score {
        case 96...100:
            return "Perfect Match"
        case 92...95:
            return "Excellent Match"
        case 86...91:
            return "Strong Match"
        default:
            return "Good Match"
        }
    }

    private func compatibleClosetPieces(for product: RetailProduct) -> [String] {
        let memoryStore = OutfitMemoryStore()
        let learnedRecords = memoryStore.garmentRecords
        let productRecord = GarmentRecord(
            garmentCategory: GarmentRecordHelpers.category(from: product.recommendation),
            itemFingerprint: GarmentRecordHelpers.fingerprint(
                category: product.recommendation,
                colors: splitProductColors(product.colors),
                pattern: nil,
                fabric: nil,
                brand: product.storeName,
                styleTags: [product.recommendation]
            ),
            brand: product.storeName,
            colors: splitProductColors(product.colors),
            styleTags: [product.recommendation],
            colorConfidence: 75,
            sourceScanIds: []
        )
        var seenLearnedPairings = Set<String>()
        let learnedPairings = ComplementaryPieceRecommender
            .recommendations(for: productRecord, ownedRecords: learnedRecords, limit: 4)
            .flatMap(\.relatedPieces)
            .filter { !$0.localizedCaseInsensitiveContains(product.recommendation) }
            .filter { piece in
                let key = piece.lowercased()
                guard !seenLearnedPairings.contains(key) else {
                    return false
                }
                seenLearnedPairings.insert(key)
                return true
            }
        if !learnedPairings.isEmpty {
            return Array(learnedPairings.prefix(4))
        }

        let savedPieces = closetItems
            .prefix(4)
            .map { "\($0.color) \($0.name)" }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        if !savedPieces.isEmpty {
            return Array(savedPieces.prefix(4))
        }

        switch product.recommendation {
        case "Shirts":
            return ["Navy blazer", "Black chinos", "White sneakers", "Brown belt"]
        case "Jackets":
            return ["White Oxford shirt", "Dark denim", "Black shoes", "Brown belt"]
        case "Shoes":
            return ["Dark denim", "Navy blazer", "White shirt", "Black belt"]
        case "Jeans":
            return ["White Oxford shirt", "Clean sneakers", "Navy jacket", "Black belt"]
        case "Accessories":
            return ["Black shoes", "Dark denim", "Navy blazer", "White shirt"]
        default:
            return ["Navy blazer", "Black chinos", "White sneakers", "Brown belt"]
        }
    }

    private func splitProductColors(_ colors: String) -> [String] {
        colors
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func outfitPreviewItems(for product: RetailProduct) -> [OutfitPreviewItem] {
        let productItem = OutfitPreviewItem(
            name: shortProductName(product),
            icon: iconName(for: product.recommendation),
            tint: AppTab.shop.palette.accent
        )
        let closetPieces = compatibleClosetPieces(for: product)
            .prefix(3)
            .map { piece in
                OutfitPreviewItem(
                    name: piece,
                    icon: previewIconName(for: piece),
                    tint: previewTint(for: piece)
                )
            }

        return [productItem] + closetPieces
    }

    private func shortProductName(_ product: RetailProduct) -> String {
        switch product.productName {
        case "White Oxford Shirt":
            return "White Oxford"
        case "Structured Navy Blazer":
            return "Navy Blazer"
        case "Clean Leather Sneaker":
            return "White Sneakers"
        case "Slim Dark Denim":
            return "Dark Jeans"
        case "Black Leather Belt":
            return "Black Belt"
        default:
            return product.productName
        }
    }

    private func previewIconName(for piece: String) -> String {
        let lower = piece.lowercased()
        if lower.contains("shoe") || lower.contains("sneaker") {
            return "shoe.2"
        }
        if lower.contains("belt") || lower.contains("accessory") {
            return "tag"
        }
        if lower.contains("jean") || lower.contains("denim") || lower.contains("chino") || lower.contains("pant") {
            return "figure.stand"
        }
        if lower.contains("blazer") || lower.contains("jacket") {
            return "jacket"
        }
        return "tshirt"
    }

    private func previewTint(for piece: String) -> Color {
        let lower = piece.lowercased()
        if lower.contains("navy") || lower.contains("blue") || lower.contains("denim") {
            return .blue
        }
        if lower.contains("black") {
            return .black
        }
        if lower.contains("brown") {
            return .brown
        }
        return AppTab.shop.palette.accent
    }

    private func starsText(for score: Int) -> String {
        score >= 92 ? "★★★★★" : "★★★★☆"
    }

    private func discountPercentText(for product: RetailProduct) -> String? {
        guard let original = currencyValue(product.originalPrice),
              let sale = currencyValue(product.salePrice),
              original > sale else {
            return nil
        }

        let percent = Int(((original - sale) / original * 100).rounded())
        return "(-\(percent)%)"
    }

    private func priceHistoryCurrentText(for product: RetailProduct) -> String {
        priceHistoryDollarText(currencyValue(product.salePrice) ?? currencyValue(product.price))
    }

    private func priceHistoryLowestText(for product: RetailProduct) -> String {
        guard let current = currencyValue(product.salePrice) ?? currencyValue(product.price) else {
            return product.salePrice
        }

        let simulatedLowest = max(1, (current * 0.93).rounded())
        return priceHistoryDollarText(simulatedLowest)
    }

    private func priceHistoryAverageText(for product: RetailProduct) -> String {
        guard let current = currencyValue(product.salePrice) ?? currencyValue(product.price) else {
            return product.originalPrice
        }

        let original = currencyValue(product.originalPrice) ?? current
        let average = ((current + original) / 2).rounded()
        return priceHistoryDollarText(average)
    }

    private func priceHistoryDollarText(_ value: Double?) -> String {
        guard let value else {
            return "--"
        }

        return "$\(Int(value.rounded()))"
    }

    private func compactPriceText(for product: RetailProduct) -> String {
        guard let value = currencyValue(product.salePrice) ?? currencyValue(product.price) else {
            return product.salePrice.isEmpty ? product.price : product.salePrice
        }

        return "$\(Int(floor(value)))"
    }

    private func currencyValue(_ text: String) -> Double? {
        let filtered = text.filter { $0.isNumber || $0 == "." }
        return Double(filtered)
    }

    private func toggleProductDetails(_ product: RetailProduct) {
        if expandedProductIDs.contains(product.id) {
            expandedProductIDs.remove(product.id)
        } else {
            expandedProductIDs.insert(product.id)
        }
    }

    private func toggleWishlist(_ product: RetailProduct) {
        if wishlistProductNames.contains(product.productName) {
            wishlistProductNames.remove(product.productName)
            shoppingMessage = "\(product.productName) removed from wishlist."
        } else {
            wishlistProductNames.insert(product.productName)
            shoppingMessage = "\(product.productName) saved to wishlist."
        }

        saveWishlist()
    }

    private func loadWishlist() {
        guard !wishlistProductNamesData.isEmpty,
              let productNames = try? JSONDecoder().decode([String].self, from: wishlistProductNamesData) else {
            wishlistProductNames = []
            return
        }

        wishlistProductNames = Set(productNames)
    }

    private func loadClosetItems() {
        guard !closetItemsData.isEmpty,
              let decodedItems = try? JSONDecoder().decode([ClosetItem].self, from: closetItemsData) else {
            closetItems = []
            return
        }

        closetItems = decodedItems
    }

    private func saveWishlist() {
        wishlistProductNamesData = (try? JSONEncoder().encode(Array(wishlistProductNames).sorted())) ?? Data()
    }

    private func outfitItemRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .appCard(.shop, radius: 12)
    }

    private func detailRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .fontWeight(.semibold)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }

    private func iconName(for recommendation: String) -> String {
        switch recommendation {
        case "Shoes":
            return "shoe.2"
        case "Jackets":
            return "jacket"
        case "Accessories":
            return "tag"
        case "Electronics":
            return "applewatch"
        case "Style Essentials":
            return "sparkles"
        default:
            return "tshirt"
        }
    }
}

private struct OutfitPreviewItem {
    let name: String
    let icon: String
    let tint: Color
}

private struct AIComparisonOption {
    let matchScore: Int
    let price: String
    let outfitCount: Int
}

private struct ClosetHealthMetric: Identifiable {
    let id = UUID()
    let title: String
    let score: Int
    let icon: String
}

private struct LiveShoppingInsight {
    let message: String
    let icon: String
    let tint: Color
}

private struct ShoppingSaleItem: Encodable {
    let id: String
    let name: String
    let category: String
    let color: String
    let price: Double
    let salePrice: Double
    let saleAlert: String
    let retailerName: String
    let brand: String
    let imageURL: String
    let affiliateURL: String
    let affiliateTrackingID: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case category
        case color
        case price
        case salePrice = "sale_price"
        case saleAlert = "sale_alert"
        case retailerName = "retailer_name"
        case brand
        case imageURL = "image_url"
        case affiliateURL = "affiliate_url"
        case affiliateTrackingID = "affiliate_tracking_id"
    }
}

private struct ShoppingOutfitHistoryItem: Encodable {
    let detectedGarments: [String]
    let colors: [String]
    let detectedStyle: String
    let scannedAt: Date

    enum CodingKeys: String, CodingKey {
        case detectedGarments = "detected_garments"
        case colors
        case detectedStyle = "detected_style"
        case scannedAt = "scanned_at"
    }
}

private struct ShoppingCurrentAnalysis: Encodable {
    let request: String
    let favoriteColors: String
    let favoriteBrands: String
    let budget: String
    let sizeProfile: String
    let stylePreferences: String
    let occasions: String
    let weather: String
    let closetInventory: String
    let closetItems: [String]

    enum CodingKeys: String, CodingKey {
        case request
        case favoriteColors = "favorite_colors"
        case favoriteBrands = "favorite_brands"
        case budget
        case sizeProfile = "size_profile"
        case stylePreferences = "style_preferences"
        case occasions
        case weather
        case closetInventory = "closet_inventory"
        case closetItems = "closet_items"
    }
}

private struct ShoppingSaleRecommendation: Identifiable, Decodable {
    var id: String { productID }
    let productID: String
    let productName: String
    let reason: String
    let salePrice: Double
    let originalPrice: Double

    enum CodingKeys: String, CodingKey {
        case productID = "product_id"
        case productName = "product_name"
        case reason
        case salePrice = "sale_price"
        case originalPrice = "original_price"
    }
}

private struct ShoppingRecommendationsResponse: Decodable {
    let recommendations: [ShoppingSaleRecommendation]
    let message: String?

    init(recommendations: [ShoppingSaleRecommendation], message: String? = nil) {
        self.recommendations = recommendations
        self.message = message
    }
}

private struct ShoppingStoredOutfitScan: Decodable {
    let score: Int
    let analysis: OutfitAnalysisResult?
    let firstScannedAt: Date
    let scanCount: Int
    let thumbnailData: Data?
    let customTitle: String?
}

private extension Array where Element == RetailProduct {
    func removingDuplicateProducts() -> [RetailProduct] {
        var seen: Set<String> = []
        return filter { product in
            seen.insert(product.productName).inserted
        }
    }
}

private extension String {
    func containsAny(_ terms: [String]) -> Bool {
        terms.contains { contains($0) }
    }
}
