import SwiftUI

struct ClosetView: View {
    @Binding var selectedTab: AppTab
    @AppStorage("closetItemsData") private var closetItemsData = Data()
    @AppStorage("closetInventory") private var closetInventory = ""
    @AppStorage("sizeProfile") private var sizeProfile = ""
    @AppStorage("shirtSize") private var shirtSize = ""
    @AppStorage("pantsSize") private var pantsSize = ""
    @AppStorage("waistSize") private var waistSize = ""
    @AppStorage("inseamLength") private var inseamLength = ""
    @AppStorage("neckSize") private var neckSize = ""
    @AppStorage("sleeveLength") private var sleeveLength = ""
    @AppStorage("shoeSize") private var shoeSize = ""
    @AppStorage("fitPreference") private var fitPreference = ""
    @AppStorage("favoriteClosetItemIDs") private var favoriteClosetItemIDs = ""
    @AppStorage("favoriteOutfits") private var savedFavoriteOutfits = ""
    @AppStorage("favoriteColors") private var savedFavoriteColors = ""
    @AppStorage("favoriteBrands") private var savedFavoriteBrands = ""
    @AppStorage("budget") private var budget = ""
    @AppStorage("weatherLocation") private var weatherLocation = ""
    @AppStorage("weather") private var weather = ""
    @AppStorage("weatherCondition") private var weatherCondition = ""
    @AppStorage("weatherRainChance") private var weatherRainChance = ""
    @AppStorage("weatherCity") private var weatherCity = ""
    @AppStorage("sizeCategory") private var sizeCategory = ""
    @State private var items: [ClosetItem] = []
    @State private var name = ""
    @State private var category = "Shirt"
    @State private var color = "White"
    @State private var brand = ""
    @State private var size = "M"
    @State private var occasion = "Everyday"
    @State private var season = "All Season"
    @State private var weatherUse = "Mild"
    @State private var isFavorite = false
    @State private var notes = ""
    @State private var activeSheet: ClosetDashboardSheet?
    @State private var closetActionMessage = ""
    @State private var closetSearchText = ""
    @State private var selectedClosetFilter = "All"
    @State private var selectedSort = "Recently Added"
    @State private var isManualEntryExpanded = false
    @State private var sizeSaveConfirmation = ""
    @State private var isShowingAddItemSheet = false
    @StateObject private var outfitMemoryStore = OutfitMemoryStore()

    private let categories = ["Shirt", "Pants", "Jeans", "Dress", "Jacket", "Shoes", "Accessory", "Bag", "Hat", "Traditional Wear", "Formal Wear", "Casual Wear", "Sportswear"]
    private let colors = ["Black", "White", "Navy", "Gray", "Blue", "Brown", "Tan", "Red", "Green", "Neutral"]
    private let shirtSizes = Self.allShirtSizes
    private let pantSizes = Self.allPantSizes
    private let shoeSizes = Self.allShoeSizes
    private let fitPreferenceOptions = ["Slim", "Regular", "Relaxed", "Oversized", "Tailored"]
    private var availableSizes: [String] {
        switch category {
        case "Pants", "Jeans":
            return pantSizes
        case "Shoes":
            return shoeSizes
        default:
            return shirtSizes
        }
    }
    private func optionsIncludingCurrent(_ options: [String], current: String) -> [String] {
        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !options.contains(trimmed) else {
            return options
        }
        return [trimmed] + options
    }
    private let occasions = ["Everyday", "Work", "Church", "Dinner", "Travel", "Gym", "Formal", "Party", "Wedding", "Date Night"]
    private let seasons = ["All Season", "Spring", "Summer", "Fall", "Winter", "Travel"]
    private let weatherUses = ["Mild", "Hot", "Cold", "Rain", "Wind", "Humid", "Sunny", "Travel"]
    private let closetFilters = ["All", "Favorites", "Shirt", "Pants", "Jeans", "Shoes", "Jacket", "Work", "Hot", "Rain"]
    private let sortOptions = ["Recently Added", "Name", "Category", "Color", "Brand", "Favorites"]
    private let sizeCategories = ["Men", "Women", "Unisex", "Kids/Youth"]

    fileprivate static let allShirtSizes = ["XXS", "XS", "S", "M", "L", "XL", "XXL", "2XL", "3XL", "4XL", "5XL", "6XL", "7XL", "8XL"]
    fileprivate static let allPantSizes: [String] = {
        let menPants = (24...60).flatMap { waist in
            (26...40).map { length in
                "Men \(waist)x\(length)"
            }
        }
        let womenPants = ["Women 000", "Women 00"] + (0...34).map { "Women \($0)" } + ["Women XXS", "Women XS", "Women S", "Women M", "Women L", "Women XL", "Women 2XL", "Women 3XL", "Women 4XL", "Women 5XL", "Women 6XL"]
        return menPants + womenPants
    }()
    fileprivate static let allShoeSizes = (5...18).map { "\($0)" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    itemList
                    scannedClothingSections
                    if needsClosetFoundation {
                        closetOnboardingCard
                    } else {
                        mergedClosetDesignerCard
                    }
                    insightsSection
                    collectionsSection
                    sizeSummaryNavigationRow
                }
                .padding()
                .padding(.bottom, 240)
            }
            .scrollContentBackground(.hidden)
            .appScreenBackground(.closet)
            .navigationTitle("Closet")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        selectedTab = .home
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingAddItemSheet = true
                    } label: {
                        Label("Add Item", systemImage: "plus")
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                loadItems()
                updateSizeProfileSummary()
            }
            .sheet(isPresented: $isShowingAddItemSheet) {
                AddClothingItemView(
                    name: $name,
                    category: $category,
                    color: $color,
                    brand: $brand,
                    size: $size,
                    occasion: $occasion,
                    season: $season,
                    weatherUse: $weatherUse,
                    isFavorite: $isFavorite,
                    notes: $notes,
                    categories: categories,
                    colors: colors,
                    shirtSizes: shirtSizes,
                    pantSizes: pantSizes,
                    shoeSizes: shoeSizes,
                    occasions: occasions,
                    seasons: seasons,
                    weatherUses: weatherUses,
                    colorLabel: colorLabel,
                    sizeLabel: sizeLabel,
                    aiDescriptionSuggestion: aiDescriptionSuggestion,
                    onCategoryChange: updateDefaultSize,
                    onAddPhoto: {
                        selectedTab = .scan
                    },
                    onDescribe: {
                        notes = aiDescriptionSuggestion
                    },
                    onSave: {
                        addItem()
                    }
                )
                .presentationDetents([.large])
            }
            .sheet(item: $activeSheet) { sheet in
                closetSheet(sheet)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Closet")
                .font(.system(size: 42, weight: .bold, design: .rounded))

            Text("\(items.count) item\(items.count == 1 ? "" : "s") saved")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }

    private var closetSearchBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search closet by name, brand, color, or category", text: $closetSearchText)
                    .textInputAutocapitalization(.words)
                if !closetSearchText.isEmpty {
                    Button {
                        closetSearchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(closetFilters, id: \.self) { filter in
                        Button {
                            selectedClosetFilter = filter
                        } label: {
                            Text(filter)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(selectedClosetFilter == filter ? AppTab.closet.palette.accent : Color(.secondarySystemBackground))
                                .foregroundStyle(selectedClosetFilter == filter ? .white : .primary)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var addClothingQuickStart: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Add Clothing", systemImage: "plus.circle.fill")
                    .font(.title3)
                    .fontWeight(.bold)
                Spacer()
                Text("Fast entry")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                quickAddButton("Scan Clothing", icon: "viewfinder") { selectedTab = .scan }
                quickAddButton("Take Photo", icon: "camera.fill") { selectedTab = .scan }
                quickAddButton("Import Photo", icon: "photo.fill") { selectedTab = .scan }
                quickAddButton("Manual Entry", icon: "square.and.pencil") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isManualEntryExpanded.toggle()
                    }
                }
            }

            if isManualEntryExpanded {
                addItemCard
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding()
        .appCard(.closet)
    }

    private func quickAddButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(AppTab.closet.palette.accent)
                    .frame(width: 42, height: 42)
                    .background(AppTab.closet.palette.accent.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                Text(title)
                    .font(.caption)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 92)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var virtualClosetSummary: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Label("Virtual Closet", systemImage: "tshirt.fill")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Your real wardrobe, organized for smarter outfits.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(closetHealthScore)")
                        .font(.system(size: 42, weight: .black))
                    Text("Closet Score")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(AppTab.closet.palette.accent)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                summaryPill("Items", "\(items.count)", "tshirt")
                summaryPill("Favorites", "\(favoriteItemCount)", "heart.fill")
                summaryPill("Recently Added", "\(recentlyAddedItems.count)", "clock.fill")
                summaryPill("Ready Outfits", "\(favoriteOutfits.count)", "sparkles")
            }

            Button {
                activeSheet = .savedClothing
            } label: {
                Label("View Closet", systemImage: "square.grid.2x2.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(AppTab.closet.palette.accent)
        }
        .padding()
        .appCard(.closet)
    }

    private func summaryPill(_ title: String, _ value: String, _ icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(AppTab.closet.palette.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.headline)
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var aiStylistClosetHero: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Personal AI Stylist", systemImage: "sparkles")
                .font(.title3)
                .fontWeight(.bold)

            Text(aiGreeting)
                .font(.title3)
                .fontWeight(.bold)

            HStack(spacing: 10) {
                summaryPill("Weather", weatherTemperatureText, "cloud.sun.fill")
                summaryPill("Closet score", "\(closetHealthScore)", "star.fill")
            }

            AppleWeatherAttributionView()

            VStack(alignment: .leading, spacing: 8) {
                Text("Today's recommended outfit")
                    .font(.headline)
                ForEach(recommendedClosetOutfit, id: \.self) { item in
                    Label(item, systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                }
            }
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Button {
                closetActionMessage = "Wear this outfit: \(recommendedClosetOutfit.joined(separator: ", ")). \(structuredClosetContext)"
                activeSheet = .closetDesigner
            } label: {
                Label("Wear This Outfit", systemImage: "checkmark.seal.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTab.closet.palette.accent)
        }
        .padding()
        .appCard(.closet)
    }

    private var compactStatsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            compactStat("Items", "\(items.count)", "tshirt.fill")
            compactStat("Favorites", "\(favoriteItemCount)", "heart.fill")
            compactStat("Brands", "\(brandSummaryRows.count)", "tag.fill")
            compactStat("Categories", "\(categoryCounts.count)", "square.grid.2x2.fill")
            compactStat("Outfits", "\(favoriteOutfits.count)", "sparkles")
            compactStat("Score", "\(closetHealthScore)", "star.fill")
        }
    }

    private func compactStat(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(AppTab.closet.palette.accent)
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 90, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var closetManagementSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Closet", icon: "cabinet")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                managementButton("Items", icon: "tshirt.fill", sheet: .savedClothing)
                managementButton("Outfits", icon: "sparkles", sheet: .favoriteOutfits)
                managementButton("Favorites", icon: "heart.fill", sheet: .favoriteOutfits)
                managementButton("Shopping", icon: "bag.fill") { selectedTab = .shop }
                managementButton("Recently Added", icon: "clock.fill", sheet: .recentlyAdded)
            }
        }
        .padding()
        .appCard(.closet)
    }

    private func sectionTitle(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.title3)
            .fontWeight(.bold)
    }

    private func managementButton(_ title: String, icon: String, sheet: ClosetDashboardSheet? = nil, action: (() -> Void)? = nil) -> some View {
        Button {
            if let action {
                action()
            } else if let sheet {
                activeSheet = sheet
            }
        } label: {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(AppTab.closet.palette.accent)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var closetHealthDashboard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                sectionTitle("Closet Health", icon: "heart.text.square.fill")
                Spacer()
                Text("\(closetHealthScore)/100")
                    .font(.title2)
                    .fontWeight(.black)
                    .foregroundStyle(AppTab.closet.palette.accent)
            }

            closetHealthRow("Strengths", closetStrengths.joined(separator: ", "), "checkmark.seal.fill")
            closetHealthRow("Missing essentials", missingEssentials.joined(separator: ", "), "exclamationmark.triangle.fill")
            closetHealthRow("Duplicates", duplicateSummary, "square.on.square")
            closetHealthRow("Seasonal readiness", seasonalReadiness, "sun.max.fill")
            closetHealthRow("Shopping idea", shoppingRecommendationText, "bag.fill")

            HStack(spacing: 10) {
                healthAction("Build Outfits", "sparkles")
                healthAction("Analyze Closet", "chart.bar.fill")
                healthAction("Find Missing Pieces", "plus.magnifyingglass")
            }
        }
        .padding()
        .appCard(.closet)
    }

    private func closetHealthRow(_ title: String, _ detail: String, _ icon: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(AppTab.closet.palette.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.bold)
                Text(detail.isEmpty ? "No issue found." : detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func healthAction(_ title: String, _ icon: String) -> some View {
        Button {
            closetActionMessage = "\(title): \(structuredClosetContext)"
            activeSheet = .closetDesigner
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 72)
        }
        .buttonStyle(.bordered)
        .tint(AppTab.closet.palette.accent)
    }

    private var liveWeatherClosetCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionTitle("Weather Styling", icon: "cloud.sun.fill")
                Spacer()
                Text(weatherSourceText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("\(weatherTemperatureText) • \(weatherConditionText)")
                .font(.title3)
                .fontWeight(.bold)
            Text("Rain chance: \(cleanWeatherFact(weatherRainChance, fallback: "not available"))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(weatherClosetAdvice)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
            AppleWeatherAttributionView()
        }
        .padding()
        .appCard(.closet)
    }

    private var closetAnalyticsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Closet Insights", icon: "chart.bar.xaxis")
            analyticsList("Most Worn Colors", rows: colorSummaryRows, icon: "paintpalette.fill")
            analyticsList("Most Worn Brands", rows: brandSummaryRows, icon: "tag.fill")
            analyticsList("Most Worn Categories", rows: categoryCounts, icon: "square.grid.2x2.fill")
            analyticsList("Most Worn Shoes", rows: shoeSummaryRows, icon: "shoeprints.fill")
            closetHealthRow("Usage", usageInsights, "clock.arrow.circlepath")
            closetHealthRow("Wardrobe gaps", missingEssentials.joined(separator: ", "), "target")
            closetHealthRow("Cost per wear", "Add purchase prices later to unlock cost-per-wear insights.", "dollarsign.circle")
            closetHealthRow("Favorite combinations", favoriteOutfits.first?.title ?? "Save more pieces to build favorite combinations.", "heart.fill")
        }
        .padding()
        .appCard(.closet)
    }

    private func analyticsList(_ title: String, rows: [(name: String, count: Int)], icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.subheadline)
                .fontWeight(.bold)
            if rows.isEmpty {
                Text("Add more closet details to unlock this insight.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(rows.prefix(4), id: \.name) { row in
                    HStack {
                        Text(row.name)
                        Spacer()
                        Text("\(row.count)")
                            .fontWeight(.bold)
                            .foregroundStyle(AppTab.closet.palette.accent)
                    }
                    .font(.caption)
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var recentlyAddedTimeline: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Recently Added Timeline", icon: "clock.fill")
            if recentlyAddedItems.isEmpty {
                emptyDashboardState("New clothing will appear here by time added.")
            } else {
                ForEach(Array(recentlyAddedItems.prefix(4).enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: 12) {
                        Text(timelineLabel(for: index))
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(AppTab.closet.palette.accent)
                            .frame(width: 82, alignment: .leading)
                        clothingThumbnail(item)
                            .frame(width: 46, height: 50)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(displayName(for: item))
                                .font(.subheadline)
                                .fontWeight(.bold)
                            Text("\(item.category) • \(item.color)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(10)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding()
        .appCard(.closet)
    }

    private var closetSettingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Closet Settings", icon: "gearshape.fill")
            sizeProfileCard
            settingsRow("Notifications", "Manage closet reminders and sale alerts.", "bell.fill")
            settingsRow("Privacy", "Closet data stays on this device whenever possible.", "lock.shield.fill")
            settingsRow("AI Preferences", "Used to personalize outfit and shopping suggestions.", "brain.head.profile")
        }
    }

    private func settingsRow(_ title: String, _ detail: String, _ icon: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(AppTab.closet.palette.accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var addItemCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Add clothing item", systemImage: "plus.circle")
                .font(.headline)

            TextField("Item name", text: $name)
                .textFieldStyle(.roundedBorder)

            categorySelector

            labeledControl(colorLabel) {
                Picker(colorLabel, selection: $color) {
                    Text("Clear").tag("")
                    ForEach(optionsIncludingCurrent(colors, current: color), id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu)
            }

            HStack(spacing: 12) {
                labeledControl("Brand") {
                    TextField("Brand", text: $brand)
                        .textFieldStyle(.roundedBorder)
                }

                labeledControl(sizeLabel) {
                    if category == "Pants" || category == "Jeans" {
                        TextField("Pants size", text: $size)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        Picker(sizeLabel, selection: $size) {
                            Text("Clear").tag("")
                            ForEach(optionsIncludingCurrent(availableSizes, current: size), id: \.self) { Text($0).tag($0) }
                        }
                        .pickerStyle(.menu)
                    }
                }
            }

            labeledControl("Occasion") {
                Picker("Occasion", selection: $occasion) {
                    Text("Clear").tag("")
                    ForEach(optionsIncludingCurrent(occasions, current: occasion), id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu)
            }

            HStack(spacing: 12) {
                labeledControl("Season") {
                    Picker("Season", selection: $season) {
                        Text("Clear").tag("")
                        ForEach(optionsIncludingCurrent(seasons, current: season), id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                }

                labeledControl("Weather use") {
                    Picker("Weather use", selection: $weatherUse) {
                        Text("Clear").tag("")
                        ForEach(optionsIncludingCurrent(weatherUses, current: weatherUse), id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                }
            }

            Toggle("Mark as favorite", isOn: $isFavorite)
                .toggleStyle(.switch)

            HStack(spacing: 10) {
                Button {
                    selectedTab = .scan
                } label: {
                    Label("Add Photo", systemImage: "camera.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    notes = aiDescriptionSuggestion
                } label: {
                    Label("Let AI Describe", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            TextField("Notes", text: $notes, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)

            Button {
                addItem()
            } label: {
                Label("Save to Closet", systemImage: "tray.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding()
        .appCard(.closet)
    }

    private var colorLabel: String {
        switch category {
        case "Pants", "Jeans":
            return "Pant color"
        case "Shirt":
            return "Shirt color"
        default:
            return "Color"
        }
    }

    private var sizeLabel: String {
        switch category {
        case "Pants", "Jeans":
            return "Pant size"
        case "Shirt":
            return "Shirt size"
        case "Shoes":
            return "Shoe size"
        default:
            return "Size"
        }
    }

    private var categorySelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Category")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 8)], spacing: 8) {
                ForEach(categories, id: \.self) { option in
                    Button {
                        category = option
                        updateDefaultSize(for: option)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: iconName(for: option))
                            Text(closetShortCategoryLabel(option))
                                .lineLimit(2)
                                .minimumScaleFactor(0.75)
                        }
                            .font(.caption)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity, minHeight: 46)
                    }
                    .buttonStyle(.bordered)
                    .tint(category == option ? AppTab.closet.palette.accent : .secondary)
                }
            }
        }
    }

    private func labeledControl<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var closetSummaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("\(items.count) saved items", systemImage: "tshirt")
                .font(.headline)

            Text(closetInventory)
                .foregroundStyle(.secondary)
                .lineSpacing(4)

            Label(sizeProfile, systemImage: "ruler")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(.closet)
    }

    private var closetDashboard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("Closet Dashboard")
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                Text("\(items.count) items")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppTab.closet.palette.accent)
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                dashboardMetric(title: "Items Saved", value: "\(items.count)", icon: "tshirt.fill", tint: AppTab.closet.palette.accent, sheet: .savedClothing)
                dashboardMetric(title: "Favorite Outfits", value: "\(favoriteOutfits.count)", icon: "heart.fill", tint: .pink, sheet: .favoriteOutfits)
                dashboardMetric(title: "Recently Added", value: "\(recentlyAddedItems.count)", icon: "clock.fill", tint: .blue, sheet: .recentlyAdded)
                dashboardMetric(title: "Style Categories", value: "\(categoryCounts.count)", icon: "square.grid.2x2.fill", tint: .purple, sheet: .styleCategories)
            }

            dashboardSection(title: "Favorite Outfits", icon: "heart.fill", sheet: .favoriteOutfits) {
                if favoriteOutfits.isEmpty {
                    emptyDashboardState("Save more clothing to build outfit thumbnails.")
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(favoriteOutfits) { outfit in
                                Button {
                                    activeSheet = .favoriteOutfits
                                } label: {
                                    outfitThumbnailCard(outfit)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            dashboardSection(title: "Recently Added", icon: "clock.fill", sheet: .recentlyAdded) {
                if recentlyAddedItems.isEmpty {
                    emptyDashboardState("Your newest saved items will appear here.")
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(recentlyAddedItems) { item in
                                Button {
                                    activeSheet = .itemDetail(item.id)
                                } label: {
                                    clothingThumbnailCard(item)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            HStack(alignment: .top, spacing: 12) {
                dashboardListCard(title: "Most Worn Colors", icon: "paintpalette.fill", rows: colorSummaryRows, fallback: "Add colors to see your closet palette.", sheet: .colorInsights)
                dashboardListCard(title: "Most Worn Brands", icon: "tag.fill", rows: brandSummaryRows, fallback: "Add brands to see your top labels.", sheet: .brandInsights)
            }

            dashboardSection(title: "Style Categories", icon: "square.grid.2x2.fill", sheet: .styleCategories) {
                if categoryCounts.isEmpty {
                    emptyDashboardState("Shirts, pants, shoes, jackets, and accessories will group here.")
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 10)], spacing: 10) {
                        ForEach(categoryCounts, id: \.name) { category in
                            Button {
                                activeSheet = .category(category.name)
                            } label: {
                                categoryChip(category.name, count: category.count)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            dashboardSection(title: "Seasonal Wardrobe", icon: "sun.max.fill", sheet: .seasonal("All Season")) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    seasonalCard(title: "Warm Weather", detail: seasonalWarmWeatherText, icon: "sun.max.fill", tint: .orange, sheet: .seasonal("Warm Weather"))
                    seasonalCard(title: "Cool Weather", detail: seasonalCoolWeatherText, icon: "wind", tint: .cyan, sheet: .seasonal("Cool Weather"))
                    seasonalCard(title: "Rain Ready", detail: seasonalRainText, icon: "cloud.rain.fill", tint: .blue, sheet: .seasonal("Rain Ready"))
                    seasonalCard(title: "Travel Ready", detail: seasonalTravelText, icon: "suitcase.fill", tint: .purple, sheet: .seasonal("Travel Ready"))
                }
            }

            dashboardSection(title: "Laundry Suggestions", icon: "washer.fill", sheet: .laundry) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(laundrySuggestions, id: \.self) { suggestion in
                        Label(suggestion, systemImage: "checkmark.circle")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                activeSheet = .closetDesigner
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.title3)
                        .foregroundStyle(AppTab.closet.palette.accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("AI Closet Designer")
                            .font(.headline)
                        Text("Build outfits, find gaps, and check your closet before shopping.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("View")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(AppTab.closet.palette.accent)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)

            Label("Your closet stays private and is used only to improve outfit recommendations.", systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .appCard(.closet)
    }

    private func dashboardMetric(title: String, value: String, icon: String, tint: Color, sheet: ClosetDashboardSheet) -> some View {
        Button {
            activeSheet = sheet
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundStyle(tint)
                        .accessibilityHidden(true)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }

                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)

                HStack {
                    Text(title)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    Text("View")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(tint)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: tint.opacity(0.08), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(value)")
        .accessibilityHint("Opens \(title)")
    }

    private func dashboardSection<Content: View>(title: String, icon: String, sheet: ClosetDashboardSheet? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                Spacer()

                if let sheet {
                    Button {
                        activeSheet = sheet
                    } label: {
                    Label("View", systemImage: "chevron.right")
                        .font(.caption)
                        .fontWeight(.bold)
                        .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTab.closet.palette.accent)
                }
            }

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func emptyDashboardState(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func dashboardListCard(title: String, icon: String, rows: [(name: String, count: Int)], fallback: String, sheet: ClosetDashboardSheet) -> some View {
        Button {
            activeSheet = sheet
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(title, systemImage: icon)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if rows.isEmpty {
                    Text(fallback)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                } else {
                    ForEach(rows.prefix(4), id: \.name) { row in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(title.contains("Colors") ? colorSwatch(row.name) : AppTab.closet.palette.accent.opacity(0.2))
                                .frame(width: 12, height: 12)

                            Text(row.name)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .lineLimit(1)

                            Spacer()

                            Text("\(row.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityHint("Opens \(title)")
    }

    private func clothingThumbnailCard(_ item: ClosetItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            clothingThumbnail(item)
                .frame(width: 104, height: 104)

            Text(displayName(for: item))
                .font(.caption)
                .fontWeight(.bold)
                .lineLimit(2)
                .frame(width: 104, alignment: .leading)

            Text(displaySize(for: item))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func outfitThumbnailCard(_ outfit: ClosetDashboardOutfit) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(.secondarySystemBackground))

                HStack(spacing: -8) {
                    ForEach(outfit.items.prefix(3)) { item in
                        clothingThumbnail(item)
                            .frame(width: 56, height: 82)
                            .shadow(color: .black.opacity(0.08), radius: 5, x: 0, y: 3)
                    }
                }
            }
            .frame(width: 168, height: 112)

            Text(outfit.title)
                .font(.subheadline)
                .fontWeight(.bold)
                .lineLimit(2)

            Text(outfit.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(width: 178, alignment: .leading)
        .padding(10)
        .background(Color(.systemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppTab.closet.palette.accent.opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func clothingThumbnail(_ item: ClosetItem) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(colorSwatch(item.color).opacity(0.9))

            Image(systemName: iconName(for: item.category))
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(readableInk(for: item.color))

            VStack {
                Spacer()
                HStack {
                    Text(item.category.prefix(1).uppercased())
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(readableInk(for: item.color))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.16))
                        .clipShape(Capsule())
                    Spacer()
                }
                .padding(7)
            }
        }
    }

    private func categoryChip(_ title: String, count: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: iconName(for: title))
                .foregroundStyle(AppTab.closet.palette.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.bold)
                    .lineLimit(1)
                Text("\(count) saved")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func seasonalCard(title: String, detail: String, icon: String, tint: Color, sheet: ClosetDashboardSheet) -> some View {
        Button {
            activeSheet = sheet
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon)
                        .font(.headline)
                        .foregroundStyle(tint)
                        .accessibilityHidden(true)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }

                Text(title)
                    .font(.caption)
                    .fontWeight(.bold)

                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .padding(10)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(detail)")
        .accessibilityHint("Opens \(title)")
    }

    private var sizeProfileCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Size Profile", systemImage: "ruler")
                .font(.headline)

            Text("Update sizes anytime. These stay private on this phone and are used only for fit and clothing recommendations.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(3)

            labeledControl("Sizing category") {
                Picker("Sizing category", selection: $sizeCategory) {
                    Text("Not set").tag("")
                    ForEach(optionsIncludingCurrent(sizeCategories, current: sizeCategory), id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            labeledControl("Shirt size") {
                Picker("Shirt size", selection: $shirtSize) {
                    Text("Clear").tag("")
                    ForEach(optionsIncludingCurrent(shirtSizes, current: shirtSize), id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu)
            }

            labeledControl("Generated pants size") {
                Text(generatedPantsDisplay ?? "Add waist and inseam")
                    .font(.headline)
                    .foregroundStyle(generatedPantsDisplay == nil ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            HStack(spacing: 12) {
                labeledControl("Waist") {
                    TextField("Waist", text: $waistSize)
                        .keyboardType(.numbersAndPunctuation)
                        .textFieldStyle(.roundedBorder)
                }

                labeledControl("Inseam / length") {
                    TextField("Inseam", text: $inseamLength)
                        .keyboardType(.numbersAndPunctuation)
                        .textFieldStyle(.roundedBorder)
                }
            }

            HStack(spacing: 12) {
                labeledControl("Neck") {
                    TextField("Neck", text: $neckSize)
                        .keyboardType(.numbersAndPunctuation)
                        .textFieldStyle(.roundedBorder)
                }

                labeledControl("Sleeve / arm") {
                    TextField("Sleeve", text: $sleeveLength)
                        .keyboardType(.numbersAndPunctuation)
                        .textFieldStyle(.roundedBorder)
                }
            }

            HStack(spacing: 12) {
                labeledControl("Shoe size") {
                    Picker("Shoe size", selection: $shoeSize) {
                        Text("Clear").tag("")
                        ForEach(optionsIncludingCurrent(shoeSizes, current: shoeSize), id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                }

                labeledControl("Preferred fit") {
                    Picker("Preferred fit", selection: $fitPreference) {
                        Text("Clear").tag("")
                        ForEach(optionsIncludingCurrent(fitPreferenceOptions, current: fitPreference), id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                }
            }

            Text(sizeProfile)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineSpacing(3)

            Button {
                updateSizeProfileSummary()
                sizeSaveConfirmation = "Profile saved successfully."
            } label: {
                Label(sizeSaveConfirmation.isEmpty ? "Save Sizes" : "Saved", systemImage: sizeSaveConfirmation.isEmpty ? "tray.and.arrow.down" : "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTab.closet.palette.accent)

            if !sizeSaveConfirmation.isEmpty {
                Text(sizeSaveConfirmation)
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
        .padding()
        .appCard(.closet)
        .styleMatchOnChange(of: shirtSize) { _ in updateSizeProfileSummary() }
        .styleMatchOnChange(of: sizeCategory) { _ in updateSizeProfileSummary() }
        .styleMatchOnChange(of: waistSize) { _ in updateSizeProfileSummary() }
        .styleMatchOnChange(of: inseamLength) { _ in updateSizeProfileSummary() }
        .styleMatchOnChange(of: neckSize) { _ in updateSizeProfileSummary() }
        .styleMatchOnChange(of: sleeveLength) { _ in updateSizeProfileSummary() }
        .styleMatchOnChange(of: shoeSize) { _ in updateSizeProfileSummary() }
        .styleMatchOnChange(of: fitPreference) { _ in updateSizeProfileSummary() }
    }

    private var itemList: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Your Clothing")
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                Button {
                    isShowingAddItemSheet = true
                } label: {
                    Label("Add Item", systemImage: "plus")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTab.closet.palette.accent)
            }

            categoryFilterChips

            if items.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "tshirt")
                        .font(.system(size: 42))
                        .foregroundStyle(.secondary)

                    Text("Add your first item")
                        .font(.title3)
                        .fontWeight(.bold)

                    Text("Beta testers can start with 5-10 everyday pieces: shirts, pants, shoes, jackets, and accessories.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(24)
                .appCard(.closet)
            } else if filteredSortedItems.isEmpty {
                Text("No closet items match this search or filter.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .appCard(.closet)
            } else {
                HStack {
                    Text("\(filteredSortedItems.count) result\(filteredSortedItems.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker("Sort", selection: $selectedSort) {
                        ForEach(sortOptions, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                }

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(filteredSortedItems) { item in
                        wardrobeItemCard(item)
                    }
                }
            }
        }
    }

    private var categoryFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(visibleClosetFilters, id: \.self) { filter in
                    Button {
                        selectedClosetFilter = filter
                    } label: {
                        Text(filter)
                            .font(.caption)
                            .fontWeight(.bold)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(selectedClosetFilter == filter ? AppTab.closet.palette.accent : Color(.secondarySystemBackground))
                            .foregroundStyle(selectedClosetFilter == filter ? .white : .primary)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .styleMatchOnChange(of: visibleClosetFilters) { filters in
            if !filters.contains(selectedClosetFilter) {
                selectedClosetFilter = "All"
            }
        }
    }

    private var scannedClothingSections: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .lastTextBaseline) {
                Text("Scanned Clothing")
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                if !scannedGarmentRecords.isEmpty {
                    Text("\(scannedGarmentRecords.count) detected")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                }
            }

            if scannedGarmentGroups.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Label("No scan categories yet", systemImage: "camera.viewfinder")
                        .font(.headline)

                    Text("Scan outfits to organize detected garments by category. Saved closet items above still work normally.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .appCard(.closet)
            } else {
                ForEach(scannedGarmentGroups, id: \.category) { group in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label(group.category, systemImage: iconName(for: group.category))
                                .font(.headline)
                            Spacer()
                            Text("\(group.records.count)")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(AppTab.closet.palette.accent)
                        }

                        ForEach(group.records.prefix(4)) { record in
                            scannedGarmentRow(record)
                        }

                        if group.records.count > 4 {
                            Text("+\(group.records.count - 4) more from scan history")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    .appCard(.closet)
                }
            }
        }
    }

    private func scannedGarmentRow(_ record: GarmentRecord) -> some View {
        HStack(spacing: 12) {
            Image(systemName: iconName(for: record.garmentCategory))
                .font(.headline)
                .foregroundStyle(AppTab.closet.palette.accent)
                .frame(width: 34, height: 34)
                .background(AppTab.closet.palette.accent.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                Text(scannedGarmentTitle(record))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                Text(scannedGarmentSubtitle(record))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text("Seen \(record.timesSeen)")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
        }
    }

    private func wardrobeItemCard(_ item: ClosetItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                activeSheet = .itemDetail(item.id)
            } label: {
                clothingThumbnail(item)
                    .frame(maxWidth: .infinity)
                    .frame(height: 118)
                    .overlay(alignment: .topTrailing) {
                        if isFavoriteItem(item) {
                            Image(systemName: "heart.fill")
                                .font(.caption)
                                .foregroundStyle(.pink)
                                .padding(8)
                        }
                    }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(displayName(for: item))
                    .font(.headline)
                    .lineLimit(1)

                Text(item.brand.isEmpty ? item.category : "\(item.brand) • \(item.category)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text("\(item.color) • \(matchesCount(for: item)) outfits")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppTab.closet.palette.accent)
                    .lineLimit(1)

                Text("Last worn: Not tracked")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                Button {
                    activeSheet = .itemDetail(item.id)
                } label: {
                    Label("Edit", systemImage: "pencil")
                        .labelStyle(.iconOnly)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(role: .destructive) {
                    deleteItem(item)
                } label: {
                    Label("Delete", systemImage: "trash")
                        .labelStyle(.iconOnly)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .appCard(.closet)
    }

    private var closetOnboardingCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Build your closet foundation", systemImage: "checklist")
                .font(.headline)

            Text("Add \(missingFoundationCount) more piece\(missingFoundationCount == 1 ? "" : "s") to unlock outfit building.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                foundationStep("Shirt", complete: hasFoundationShirt)
                foundationStep("Pants", complete: hasFoundationPants)
                foundationStep("Shoes", complete: hasFoundationShoes)
                foundationStep("Jacket", complete: hasFoundationJacket)
            }

            Button {
                isShowingAddItemSheet = true
            } label: {
                Label("Add Missing Piece", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTab.closet.palette.accent)
        }
        .padding()
        .appCard(.closet)
    }

    private func foundationStep(_ title: String, complete: Bool) -> some View {
        VStack(spacing: 6) {
            Image(systemName: complete ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(complete ? .green : .secondary)
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var mergedClosetDesignerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("AI Closet Designer", systemImage: "sparkles")
                .font(.headline)

            Text("Build outfits from what you already own before shopping for anything new.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(3)

            Button {
                selectedTab = .ai
            } label: {
                Label("Chat with Stylist", systemImage: "bubble.left.and.bubble.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTab.closet.palette.accent)
        }
        .padding()
        .appCard(.closet)
    }

    @ViewBuilder
    private var insightsSection: some View {
        if !insightCards.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Insights")
                    .font(.title2)
                    .fontWeight(.bold)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(insightCards) { card in
                            compactNavigationCard(card)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    @ViewBuilder
    private var collectionsSection: some View {
        if !collectionCards.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Collections")
                    .font(.title2)
                    .fontWeight(.bold)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(collectionCards) { card in
                            compactNavigationCard(card)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func compactNavigationCard(_ card: ClosetCompactCard) -> some View {
        Button {
            activeSheet = card.sheet
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: card.icon)
                    .font(.title3)
                    .foregroundStyle(card.tint)

                Text(card.title)
                    .font(.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)

                Text(card.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 160, alignment: .topLeading)
            .frame(minHeight: 118, alignment: .topLeading)
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private var sizeSummaryNavigationRow: some View {
        NavigationLink {
            SizeProfileView()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "ruler")
                    .foregroundStyle(AppTab.closet.palette.accent)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Size Profile")
                        .font(.headline)
                    Text(closetSizeSummaryLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .appCard(.closet)
        }
        .buttonStyle(.plain)
    }

    private func itemCard(_ item: ClosetItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            clothingThumbnail(item)
                .frame(maxWidth: .infinity)
                .frame(height: 180)

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(displayName(for: item))
                            .font(.headline)
                        if isFavoriteItem(item) {
                            Image(systemName: "heart.fill")
                                .foregroundStyle(.pink)
                        }
                    }

                    Text("\(item.brand.isEmpty ? "Brand not set" : item.brand) • \(item.category)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text("\(item.color) • \(displaySize(for: item)) • \(item.occasion)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        closetAttribute("Last worn", value: "Not tracked")
                        closetAttribute("Matches", value: "\(matchesCount(for: item)) outfits")
                    }

                    if !item.notes.isEmpty {
                        Text(item.notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer()

                VStack(spacing: 10) {
                    Button {
                        activeSheet = .itemDetail(item.id)
                    } label: {
                        Label("Edit", systemImage: "pencil")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.bordered)

                    Button(role: .destructive) {
                        deleteItem(item)
                    } label: {
                        Label("Delete", systemImage: "trash")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding()
        .appCard(.closet)
    }

    private func closetAttribute(_ title: String, value: String) -> some View {
        Text("\(title): \(value)")
            .font(.caption)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(AppTab.closet.palette.accent.opacity(0.12))
            .foregroundStyle(AppTab.closet.palette.accent)
            .clipShape(Capsule())
    }

    private var recentlyAddedItems: [ClosetItem] {
        Array(items.prefix(8))
    }

    private var colorSummaryRows: [(name: String, count: Int)] {
        rankedCounts(items.map(\.color))
    }

    private var brandSummaryRows: [(name: String, count: Int)] {
        rankedCounts(items.map(\.brand).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }

    private var categoryCounts: [(name: String, count: Int)] {
        rankedCounts(items.map(\.category))
    }

    private var scannedGarmentRecords: [GarmentRecord] {
        outfitMemoryStore.garmentRecords
            .filter { !$0.garmentCategory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.lastSeenAt > $1.lastSeenAt }
    }

    private var scannedGarmentGroups: [(category: String, records: [GarmentRecord])] {
        Dictionary(grouping: scannedGarmentRecords) { record in
            normalizedGarmentCategory(record.garmentCategory)
        }
        .map { category, records in
            (
                category: category,
                records: records.sorted {
                    if $0.lastSeenAt == $1.lastSeenAt {
                        return $0.timesSeen > $1.timesSeen
                    }
                    return $0.lastSeenAt > $1.lastSeenAt
                }
            )
        }
        .sorted {
            if $0.records.count == $1.records.count {
                return $0.category < $1.category
            }
            return $0.records.count > $1.records.count
        }
    }

    private var shoeSummaryRows: [(name: String, count: Int)] {
        rankedCounts(items.filter { $0.category == "Shoes" }.map(\.color))
    }

    private var favoriteItemCount: Int {
        items.filter { isFavoriteItem($0) }.count
    }

    private var visibleClosetFilters: [String] {
        let categoryNames = categoryCounts.map(\.name).filter { !$0.isEmpty }
        return ["All"] + categoryNames
    }

    private var hasFoundationShirt: Bool {
        items.contains { $0.category == "Shirt" }
    }

    private var hasFoundationPants: Bool {
        items.contains { $0.category == "Pants" || $0.category == "Jeans" }
    }

    private var hasFoundationShoes: Bool {
        items.contains { $0.category == "Shoes" }
    }

    private var hasFoundationJacket: Bool {
        items.contains { $0.category == "Jacket" }
    }

    private var needsClosetFoundation: Bool {
        !(hasFoundationShirt && hasFoundationPants && hasFoundationShoes && hasFoundationJacket)
    }

    private var missingFoundationCount: Int {
        [hasFoundationShirt, hasFoundationPants, hasFoundationShoes, hasFoundationJacket].filter { !$0 }.count
    }

    private var insightCards: [ClosetCompactCard] {
        var cards: [ClosetCompactCard] = []
        if let color = colorSummaryRows.first {
            cards.append(ClosetCompactCard(title: "Most Worn Colors", summary: "\(color.name) · \(color.count)", icon: "paintpalette.fill", tint: .white, sheet: .colorInsights))
        }
        if let brand = brandSummaryRows.first {
            cards.append(ClosetCompactCard(title: "Most Worn Brands", summary: "\(brand.name) · \(brand.count)", icon: "tag.fill", tint: .pink, sheet: .brandInsights))
        }
        if let category = categoryCounts.first {
            cards.append(ClosetCompactCard(title: "Style Categories", summary: "\(category.name) · \(category.count)", icon: "square.grid.2x2.fill", tint: .purple, sheet: .styleCategories))
        }
        if !items.isEmpty {
            cards.append(ClosetCompactCard(title: "Laundry Suggestions", summary: "Keep \(colorSummaryRows.first?.name.lowercased() ?? "daily") pieces fresh", icon: "washer.fill", tint: .blue, sheet: .laundry))
        }
        return cards
    }

    private var collectionCards: [ClosetCompactCard] {
        let definitions: [(title: String, icon: String, tint: Color)] = [
            ("Warm Weather", "sun.max.fill", .orange),
            ("Cool Weather", "wind", .cyan),
            ("Rain Ready", "cloud.rain.fill", .blue),
            ("Travel Ready", "suitcase.fill", .purple)
        ]

        return definitions.compactMap { definition in
            let count = seasonalItems(for: definition.title).count
            guard count > 0 else { return nil }
            return ClosetCompactCard(
                title: definition.title,
                summary: "\(count) piece\(count == 1 ? "" : "s") ready",
                icon: definition.icon,
                tint: definition.tint,
                sheet: .seasonal(definition.title)
            )
        }
    }

    private var filteredSortedItems: [ClosetItem] {
        let query = closetSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        var results = items.filter { item in
            let matchesQuery = query.isEmpty
                || displayName(for: item).localizedCaseInsensitiveContains(query)
                || item.brand.localizedCaseInsensitiveContains(query)
                || item.category.localizedCaseInsensitiveContains(query)
                || item.color.localizedCaseInsensitiveContains(query)
                || item.occasion.localizedCaseInsensitiveContains(query)
                || item.notes.localizedCaseInsensitiveContains(query)

            let matchesFilter: Bool
            switch selectedClosetFilter {
            case "All":
                matchesFilter = true
            case "Favorites":
                matchesFilter = isFavoriteItem(item)
            case "Work":
                matchesFilter = item.occasion.localizedCaseInsensitiveContains("work")
            case "Hot", "Rain":
                matchesFilter = item.notes.localizedCaseInsensitiveContains(selectedClosetFilter) || item.occasion.localizedCaseInsensitiveContains(selectedClosetFilter)
            default:
                matchesFilter = item.category == selectedClosetFilter
            }

            return matchesQuery && matchesFilter
        }

        switch selectedSort {
        case "Name":
            results.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case "Category":
            results.sort { $0.category.localizedCaseInsensitiveCompare($1.category) == .orderedAscending }
        case "Color":
            results.sort { $0.color.localizedCaseInsensitiveCompare($1.color) == .orderedAscending }
        case "Brand":
            results.sort { $0.brand.localizedCaseInsensitiveCompare($1.brand) == .orderedAscending }
        case "Favorites":
            results.sort { isFavoriteItem($0) && !isFavoriteItem($1) }
        default:
            break
        }

        return results
    }

    private var closetHealthScore: Int {
        guard !items.isEmpty else { return 20 }
        var score = 35
        score += min(items.count * 5, 25)
        score += min(categoryCounts.count * 4, 20)
        if !missingEssentials.contains("shirt") { score += 5 }
        if !missingEssentials.contains("pants") { score += 5 }
        if !missingEssentials.contains("shoes") { score += 5 }
        if favoriteItemCount > 0 { score += 5 }
        if brandSummaryRows.count > 0 { score += 5 }
        if duplicateGroups.isEmpty { score += 5 }
        return min(score, 100)
    }

    private var closetStrengths: [String] {
        var strengths: [String] = []
        if let color = colorSummaryRows.first?.name {
            strengths.append("\(color) is your strongest color")
        }
        if categoryCounts.count >= 3 {
            strengths.append("good category variety")
        }
        if favoriteItemCount > 0 {
            strengths.append("\(favoriteItemCount) favorite pieces saved")
        }
        return strengths.isEmpty ? ["closet foundation started"] : strengths
    }

    private var missingEssentials: [String] {
        var missing: [String] = []
        if !items.contains(where: { ["Shirt", "Casual Wear", "Formal Wear"].contains($0.category) }) { missing.append("shirt") }
        if !items.contains(where: { ["Pants", "Jeans"].contains($0.category) }) { missing.append("pants") }
        if !items.contains(where: { $0.category == "Shoes" }) { missing.append("shoes") }
        if !items.contains(where: { $0.category == "Jacket" }) { missing.append("jacket") }
        if !items.contains(where: { ["Accessory", "Bag", "Hat"].contains($0.category) }) { missing.append("accessory") }
        return missing
    }

    private var duplicateGroups: [(name: String, count: Int)] {
        rankedCounts(items.map { "\($0.color) \($0.category)" }).filter { $0.count > 1 }
    }

    private var duplicateSummary: String {
        duplicateGroups.isEmpty ? "No obvious duplicates detected." : duplicateGroups.prefix(3).map { "\($0.count)x \($0.name)" }.joined(separator: ", ")
    }

    private var seasonalReadiness: String {
        let ready = [
            seasonalWarmWeatherText.localizedCaseInsensitiveContains("ready"),
            seasonalCoolWeatherText.localizedCaseInsensitiveContains("ready") || seasonalCoolWeatherText.localizedCaseInsensitiveContains("layering"),
            seasonalRainText.localizedCaseInsensitiveContains("weather-friendly"),
            seasonalTravelText.localizedCaseInsensitiveContains("saved")
        ].filter { $0 }.count
        return "\(ready)/4 seasonal areas have useful pieces."
    }

    private var shoppingRecommendationText: String {
        if let firstMissing = missingEssentials.first {
            return "Shop only if a \(firstMissing) completes outfits you already own."
        }
        return "You already have the core pieces; focus on upgrades or replacements."
    }

    private var usageInsights: String {
        if items.isEmpty {
            return "Add pieces to start tracking outfit history and unworn items."
        }
        return "\(items.count) saved pieces, \(favoriteItemCount) favorites, \(recentlyAddedItems.count) recently added."
    }

    private var weatherTemperatureText: String {
        let trimmed = weather.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Weather saved" : trimmed
    }

    private var weatherConditionText: String {
        let trimmed = weatherCondition.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Mild" : trimmed
    }

    private var weatherSourceText: String {
        let city = weatherCity.trimmingCharacters(in: .whitespacesAndNewlines)
        return city.isEmpty ? "Saved weather" : city
    }

    private var weatherClosetAdvice: String {
        let context = "\(weatherTemperatureText) \(weatherConditionText) \(weatherRainChance)".lowercased()
        if context.contains("rain") || context.contains("storm") || context.contains("70%") {
            return "Use rain-ready shoes, a water-friendly jacket, and avoid suede or delicate fabrics."
        }
        if context.contains("90") || context.contains("hot") || context.contains("humid") {
            return "Choose breathable shirts, lighter colors, and low-bulk shoes. Avoid unnecessary jackets."
        }
        if context.contains("cold") || context.contains("40") || context.contains("30") {
            return "Prioritize a jacket, warmer pants, and closed shoes."
        }
        return "Light layers and comfortable shoes should work well today."
    }

    private var aiGreeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let greeting = hour < 12 ? "Good morning" : (hour < 17 ? "Good afternoon" : "Good evening")
        return "\(greeting). Today is \(weatherTemperatureText). We recommend \(recommendedClosetOutfit.joined(separator: ", "))."
    }

    private var recommendedClosetOutfit: [String] {
        if let outfit = favoriteOutfits.first, !outfit.items.isEmpty {
            return outfit.items.map { "\($0.color) \($0.name)" }
        }
        let top = items.first(where: { ["Shirt", "Jacket", "Dress"].contains($0.category) })
        let bottom = items.first(where: { ["Pants", "Jeans"].contains($0.category) })
        let shoe = items.first(where: { $0.category == "Shoes" })
        let pieces = [top, bottom, shoe].compactMap { $0 }.map { "\($0.color) \($0.name)" }
        return pieces.isEmpty ? ["add a shirt", "add pants", "add shoes"] : pieces
    }

    private var favoriteOutfits: [ClosetDashboardOutfit] {
        let tops = items.filter { ["Shirt", "Jacket", "Dress"].contains($0.category) }
        let bottoms = items.filter { ["Pants", "Jeans"].contains($0.category) }
        let shoes = items.filter { $0.category == "Shoes" }
        let accessories = items.filter { ["Accessory", "Bag", "Hat"].contains($0.category) }

        var outfits: [ClosetDashboardOutfit] = []

        if let top = tops.first, let bottom = bottoms.first {
            var outfitItems = [top, bottom]
            if let shoe = shoes.first {
                outfitItems.append(shoe)
            }
            outfits.append(
                ClosetDashboardOutfit(
                    title: "\(top.color) \(top.category) + \(bottom.color) \(bottom.category)",
                    detail: "Ready for \(top.occasion.lowercased())",
                    items: outfitItems
                )
            )
        }

        if let jacket = items.first(where: { $0.category == "Jacket" }), let top = tops.dropFirst().first ?? tops.first {
            var outfitItems = [jacket, top]
            if let accessory = accessories.first {
                outfitItems.append(accessory)
            }
            outfits.append(
                ClosetDashboardOutfit(
                    title: "Layered \(jacket.color) look",
                    detail: "Good for polished styling",
                    items: outfitItems
                )
            )
        }

        if let dress = items.first(where: { $0.category == "Dress" }) {
            var outfitItems = [dress]
            if let shoe = shoes.first {
                outfitItems.append(shoe)
            }
            if let accessory = accessories.first {
                outfitItems.append(accessory)
            }
            outfits.append(
                ClosetDashboardOutfit(
                    title: "\(dress.color) dress outfit",
                    detail: "Best for \(dress.occasion.lowercased())",
                    items: outfitItems
                )
            )
        }

        if outfits.isEmpty && items.count >= 2 {
            outfits.append(
                ClosetDashboardOutfit(
                    title: "Newest closet mix",
                    detail: "Built from recently saved pieces",
                    items: Array(items.prefix(3))
                )
            )
        }

        return Array(outfits.prefix(4))
    }

    private var seasonalWarmWeatherText: String {
        let warmItems = items.filter { ["White", "Tan", "Blue", "Neutral"].contains($0.color) || ["Shirt", "Dress", "Hat"].contains($0.category) }
        return warmItems.isEmpty ? "Add light shirts, breathable shoes, and warm-weather colors." : "\(warmItems.count) light pieces ready"
    }

    private var seasonalCoolWeatherText: String {
        let coolItems = items.filter { ["Jacket", "Jeans", "Pants"].contains($0.category) || ["Black", "Navy", "Gray", "Brown"].contains($0.color) }
        return coolItems.isEmpty ? "Add jackets, denim, and layering pieces." : "\(coolItems.count) layering pieces ready"
    }

    private var seasonalRainText: String {
        let rainItems = items.filter { $0.category == "Jacket" || $0.category == "Shoes" || $0.notes.localizedCaseInsensitiveContains("rain") }
        return rainItems.isEmpty ? "Add rain shoes, jackets, or weather notes." : "\(rainItems.count) weather-friendly pieces"
    }

    private var seasonalTravelText: String {
        let travelItems = items.filter { $0.occasion == "Travel" || $0.notes.localizedCaseInsensitiveContains("travel") }
        return travelItems.isEmpty ? "Mark travel pieces to plan packing faster." : "\(travelItems.count) travel pieces saved"
    }

    private var laundrySuggestions: [String] {
        if items.isEmpty {
            return [
                "Add clothing first so Style Match Pro can suggest care reminders.",
                "White shirts, gym pieces, and shoes will get faster laundry prompts."
            ]
        }

        var suggestions: [String] = []
        let whiteCount = items.filter { $0.color == "White" }.count
        let gymCount = items.filter { $0.occasion == "Gym" }.count
        let shoeCount = items.filter { $0.category == "Shoes" }.count

        if whiteCount > 0 {
            suggestions.append("Keep \(whiteCount) white piece\(whiteCount == 1 ? "" : "s") fresh before outfit planning.")
        }
        if gymCount > 0 {
            suggestions.append("Wash gym pieces after wear so they stay ready.")
        }
        if shoeCount > 0 {
            suggestions.append("Clean shoes before pairing them with a new scan.")
        }
        if suggestions.isEmpty {
            suggestions.append("Rotate recently worn items before repeating the same outfit.")
            suggestions.append("Add care notes to get better laundry reminders.")
        }

        return suggestions
    }

    private func rankedCounts(_ values: [String]) -> [(name: String, count: Int)] {
        Dictionary(grouping: values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }, by: { $0 })
            .map { (name: $0.key, count: $0.value.count) }
            .sorted {
                if $0.count == $1.count {
                    return $0.name < $1.name
                }
                return $0.count > $1.count
            }
    }

    private func matchesCount(for item: ClosetItem) -> Int {
        let compatible = items.filter { other in
            other.id != item.id && (
                other.occasion == item.occasion ||
                other.color == item.color ||
                ["Black", "White", "Navy", "Gray", "Neutral"].contains(other.color) ||
                ["Black", "White", "Navy", "Gray", "Neutral"].contains(item.color)
            )
        }
        return min(max(compatible.count, 1), 12)
    }

    private func timelineLabel(for index: Int) -> String {
        switch index {
        case 0:
            return "Yesterday"
        case 1:
            return "3 Days Ago"
        case 2:
            return "Last Week"
        default:
            return "Last Month"
        }
    }

    private func cleanWeatherFact(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func colorSwatch(_ colorName: String) -> Color {
        switch colorName {
        case "Black":
            return .black
        case "White":
            return .white
        case "Navy":
            return Color(red: 0.03, green: 0.10, blue: 0.28)
        case "Gray":
            return .gray
        case "Blue":
            return .blue
        case "Brown":
            return .brown
        case "Tan":
            return Color(red: 0.72, green: 0.58, blue: 0.38)
        case "Red":
            return .red
        case "Green":
            return .green
        default:
            return AppTab.closet.palette.accent
        }
    }

    private func readableInk(for colorName: String) -> Color {
        switch colorName {
        case "White", "Tan", "Neutral":
            return .black
        default:
            return .white
        }
    }

    private func addItem() {
        let cleanNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let metadata = "Season: \(season); Weather: \(weatherUse)"
        let savedNotes = cleanNotes.isEmpty ? metadata : "\(cleanNotes)\n\(metadata)"
        let item = ClosetItem(
            name: ClosetItemDisplay.displayName(name: name, category: category, color: color),
            category: category,
            color: color,
            brand: brand.trimmingCharacters(in: .whitespacesAndNewlines),
            size: normalizedSizeForSaving(),
            occasion: occasion,
            notes: savedNotes
        )

        items.insert(item, at: 0)
        if isFavorite {
            setFavorite(item, favorite: true)
        }
        saveItems()
        resetForm()
    }

    private func deleteItem(_ item: ClosetItem) {
        items.removeAll { $0.id == item.id }
        setFavorite(item, favorite: false)
        saveItems()
    }

    private func updateItem(_ item: ClosetItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index] = item
        saveItems()
    }

    private func loadItems() {
        updateDefaultSize(for: category)

        guard !closetItemsData.isEmpty,
              let decodedItems = try? JSONDecoder().decode([ClosetItem].self, from: closetItemsData) else {
            items = []
            return
        }

        items = decodedItems
        updateClosetInventory()
    }

    private func saveItems() {
        closetItemsData = (try? JSONEncoder().encode(items)) ?? Data()
        updateClosetInventory()
    }

    private func updateClosetInventory() {
        if items.isEmpty {
            closetInventory = "No saved closet items yet."
            return
        }

        closetInventory = items
            .prefix(12)
            .map { itemInventoryLabel(for: $0) }
            .joined(separator: ", ")
    }

    private func displayName(for item: ClosetItem) -> String {
        ClosetItemDisplay.displayName(for: item)
    }

    private func normalizedGarmentCategory(_ category: String) -> String {
        let cleaned = category.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return "Other" }

        switch cleaned.lowercased() {
        case "top", "tops", "shirt", "shirts", "tee", "t-shirt", "polo":
            return "Shirt"
        case "bottom", "bottoms", "pant", "pants", "jean", "jeans", "shorts":
            return "Pants"
        case "shoe", "shoes", "sneaker", "sneakers", "loafer", "loafers":
            return "Shoes"
        case "outerwear", "jacket", "coat", "blazer":
            return "Jacket"
        case "accessory", "accessories", "belt", "watch", "bag", "hat":
            return "Accessory"
        default:
            return cleaned
        }
    }

    private func scannedGarmentTitle(_ record: GarmentRecord) -> String {
        let category = normalizedGarmentCategory(record.garmentCategory)
        guard let color = record.colors.first?.trimmingCharacters(in: .whitespacesAndNewlines),
              !color.isEmpty else {
            return category
        }
        return color.range(of: category, options: [.caseInsensitive, .diacriticInsensitive]) == nil ? "\(color) \(category)" : color
    }

    private func scannedGarmentSubtitle(_ record: GarmentRecord) -> String {
        var parts: [String] = []
        if let brand = record.brand?.trimmingCharacters(in: .whitespacesAndNewlines), !brand.isEmpty {
            parts.append(brand)
        }
        if let fit = record.fit?.trimmingCharacters(in: .whitespacesAndNewlines), !fit.isEmpty {
            parts.append(fit)
        }
        if let pattern = record.pattern?.trimmingCharacters(in: .whitespacesAndNewlines), !pattern.isEmpty {
            parts.append(pattern)
        }
        if parts.isEmpty, !record.styleTags.isEmpty {
            parts.append(record.styleTags.prefix(2).joined(separator: ", "))
        }
        if parts.isEmpty {
            parts.append("From scan history")
        }
        return parts.joined(separator: " • ")
    }

    private func itemInventoryLabel(for item: ClosetItem) -> String {
        let name = displayName(for: item)
        let color = item.color.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !color.isEmpty else { return name }
        return name.range(of: color, options: [.caseInsensitive, .diacriticInsensitive]) == nil ? "\(color) \(name)" : name
    }

    private func resetForm() {
        name = ""
        brand = ""
        notes = ""
        season = "All Season"
        weatherUse = "Mild"
        isFavorite = false
    }

    private func updateDefaultSize(for category: String) {
        switch category {
        case "Shirt", "Jacket", "Dress":
            if !shirtSizes.contains(size) {
                size = "M"
            }
        case "Pants", "Jeans":
            let trimmed = size.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || !trimmed.localizedCaseInsensitiveContains("x") {
                size = ""
            }
        case "Shoes":
            if !shoeSizes.contains(size) {
                size = "10"
            }
        default:
            if !shirtSizes.contains(size) {
                size = "M"
            }
        }
    }

    private func normalizedSizeForSaving() -> String {
        switch category {
        case "Shirt", "Jacket", "Dress":
            return size.replacingOccurrences(of: "Shirt ", with: "")
        case "Shoes":
            return size.replacingOccurrences(of: "Shoes ", with: "")
        default:
            return size
        }
    }

    private func displaySize(for item: ClosetItem) -> String {
        switch item.category {
        case "Shirt", "Jacket", "Dress":
            return item.size.replacingOccurrences(of: "Shirt ", with: "")
        case "Shoes":
            return item.size.replacingOccurrences(of: "Shoes ", with: "")
        default:
            return item.size
        }
    }

    private var generatedPantsDisplay: String? {
        PantsSizeSync.displayValue(waist: waistSize, inseam: inseamLength)
    }

    private var closetSizeSummaryLine: String {
        let rows = sizeSummaryRows()
        guard !rows.isEmpty else { return "No sizes saved yet" }
        return rows.map { "\($0.label): \($0.value)" }.joined(separator: " · ")
    }

    private func sizeSummaryRows() -> [(label: String, value: String)] {
        var rows: [(String, String)] = []
        let cleanCategory = sizeCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        let category = cleanCategory.isEmpty ? "Men" : cleanCategory
        if !shirtSize.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            rows.append(("Shirt", shirtSize))
        }
        if PantsSizeSync.categoryUsesGeneratedPants(category), let generatedPantsDisplay {
            rows.append(("Pants", generatedPantsDisplay))
        } else if !pantsSize.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            rows.append(("Bottoms", pantsSize))
        }
        if !shoeSize.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            rows.append(("Shoes", shoeSize))
        }
        if !fitPreference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            rows.append(("Fit", fitPreference))
        }
        return rows
    }

    private func updateSizeProfileSummary() {
        sizeSaveConfirmation = ""
        let category = sizeCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        if PantsSizeSync.categoryUsesGeneratedPants(category.isEmpty ? "Men" : category) {
            let reconciled = PantsSizeSync.reconciledValues(
                pantsSize: pantsSize,
                waistSize: waistSize,
                inseamLength: inseamLength,
                category: category.isEmpty ? "Men" : category
            )
            pantsSize = reconciled.pantsSize
            waistSize = reconciled.waistSize
            inseamLength = reconciled.inseamLength
        } else {
            waistSize = ""
            inseamLength = ""
        }
        let rows = sizeSummaryRows()
        sizeProfile = rows.isEmpty ? "No sizes saved yet" : rows.map { "\($0.label): \($0.value)" }.joined(separator: "; ")
    }

    private func iconName(for category: String) -> String {
        switch category {
        case "Pants", "Jeans":
            return "figure.walk"
        case "Shoes":
            return "shoeprints.fill"
        case "Jacket":
            return "person.crop.square"
        case "Dress":
            return "person"
        case "Accessory":
            return "watch.analog"
        case "Bag":
            return "bag"
        case "Hat":
            return "graduationcap"
        case "Traditional Wear":
            return "sparkles"
        case "Formal Wear":
            return "suitcase"
        case "Casual Wear":
            return "figure.wave"
        case "Sportswear":
            return "figure.run"
        default:
            return "tshirt"
        }
    }

    private var aiDescriptionSuggestion: String {
        "\(color) \(category.lowercased()) for \(occasion.lowercased()). Season: \(season); Weather: \(weatherUse). StyleMatch Pro can pair this with saved closet items before recommending anything new."
    }

    private var favoriteIDSet: Set<String> {
        Set(favoriteClosetItemIDs.split(separator: ",").map { String($0) })
    }

    private func isFavoriteItem(_ item: ClosetItem) -> Bool {
        favoriteIDSet.contains(item.id.uuidString)
    }

    private func setFavorite(_ item: ClosetItem, favorite: Bool) {
        var ids = favoriteIDSet
        if favorite {
            ids.insert(item.id.uuidString)
        } else {
            ids.remove(item.id.uuidString)
        }
        favoriteClosetItemIDs = ids.sorted().joined(separator: ",")
    }

    private func items(forCategory category: String) -> [ClosetItem] {
        items.filter { $0.category == category }
    }

    private func seasonalItems(for title: String) -> [ClosetItem] {
        switch title {
        case "Warm Weather":
            return items.filter { ["White", "Tan", "Blue", "Neutral"].contains($0.color) || $0.notes.localizedCaseInsensitiveContains("hot") || $0.notes.localizedCaseInsensitiveContains("mild") || $0.notes.localizedCaseInsensitiveContains("summer") || $0.notes.localizedCaseInsensitiveContains("all season") }
        case "Cool Weather":
            return items.filter { ["Jacket", "Jeans", "Pants"].contains($0.category) || $0.notes.localizedCaseInsensitiveContains("cold") || $0.notes.localizedCaseInsensitiveContains("winter") }
        case "Rain Ready":
            return items.filter { $0.category == "Jacket" || $0.category == "Shoes" || $0.notes.localizedCaseInsensitiveContains("rain") }
        case "Travel Ready":
            return items.filter { $0.occasion == "Travel" || $0.notes.localizedCaseInsensitiveContains("travel") }
        default:
            return items
        }
    }

    private var structuredClosetContext: String {
        """
        Saved items: \(items.map { "\($0.name) | \($0.category) | \($0.color) | \($0.size) | \($0.brand) | \($0.occasion) | \($0.notes)" }.joined(separator: " ; "))
        Favorite outfits: \(savedFavoriteOutfits)
        Most worn colors: \(colorSummaryRows.map { "\($0.name) \($0.count)" }.joined(separator: ", "))
        Most worn brands: \(brandSummaryRows.map { "\($0.name) \($0.count)" }.joined(separator: ", "))
        Size profile: \(sizeProfile)
        Weather preference: \(weatherLocation)
        Budget: \(budget)
        """
    }

    @ViewBuilder
    private func closetSheet(_ sheet: ClosetDashboardSheet) -> some View {
        switch sheet {
        case .savedClothing:
            closetItemListSheet(title: "Saved Clothing", subtitle: "Tap any item to edit, favorite, delete, or ask AI how to style it.", sheetItems: items)
        case .favoriteOutfits:
            favoriteOutfitsSheet
        case .recentlyAdded:
            closetItemListSheet(title: "Recently Added", subtitle: "Newest saved items. Sort mentally by date, category, color, brand, or occasion while beta sorting controls are added.", sheetItems: recentlyAddedItems)
        case .colorInsights:
            colorInsightsSheet
        case .brandInsights:
            brandInsightsSheet
        case .styleCategories:
            styleCategoriesSheet
        case .category(let category):
            closetItemListSheet(title: category, subtitle: "Saved \(category.lowercased()) pieces in your closet.", sheetItems: items(forCategory: category))
        case .seasonal(let title):
            seasonalSheet(title)
        case .laundry:
            laundrySheet
        case .closetDesigner:
            closetDesignerSheet
        case .itemDetail(let id):
            if let item = items.first(where: { $0.id == id }) {
                ClosetItemDetailSheet(
                    item: item,
                    isFavorite: isFavoriteItem(item),
                    onSave: { updatedItem in updateItem(updatedItem) },
                    onDelete: { deleteItem(item); activeSheet = nil },
                    onFavorite: { favorite in setFavorite(item, favorite: favorite) },
                    onAskAI: {
                        closetActionMessage = "Ask AI how to style \(displayName(for: item)): \(structuredClosetContext)"
                        activeSheet = .closetDesigner
                    },
                    onBuildOutfit: {
                        closetActionMessage = "Build outfit with \(displayName(for: item)): \(structuredClosetContext)"
                        activeSheet = .closetDesigner
                    }
                )
            } else {
                emptySheet(title: "Item Not Found", message: "This clothing item may have already been deleted.")
            }
        }
    }

    private func closetItemListSheet(title: String, subtitle: String, sheetItems: [ClosetItem]) -> some View {
        NavigationStack {
            List {
                Section {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if sheetItems.isEmpty {
                    Section {
                        emptySheetState("No clothing saved here yet.")
                    }
                } else {
                    Section {
                        ForEach(sheetItems) { item in
                            Button {
                                activeSheet = .itemDetail(item.id)
                            } label: {
                                HStack(spacing: 12) {
                                    clothingThumbnail(item)
                                        .frame(width: 48, height: 56)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(displayName(for: item))
                                            .font(.headline)
                                        Text("\(item.category) • \(item.color) • \(displaySize(for: item))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { activeSheet = nil }
                }
            }
        }
    }

    private var favoriteOutfitsSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Save clothing items or ask AI to build your first outfit.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button {
                        closetActionMessage = "Build favorite outfits from this closet. Name each outfit and mark occasion: work, church, date night, travel, wedding, casual, gym, or party. \(structuredClosetContext)"
                        activeSheet = .closetDesigner
                    } label: {
                        Label("Build Favorite Outfit", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    if favoriteOutfits.isEmpty {
                        emptySheetState("No favorite outfits yet.")
                    } else {
                        ForEach(favoriteOutfits) { outfit in
                            outfitThumbnailCard(outfit)
                        }
                    }

                    TextField("Favorite outfit names", text: $savedFavoriteOutfits, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...5)
                }
                .padding()
            }
            .navigationTitle("Favorite Outfits")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { activeSheet = nil } } }
        }
    }

    private var colorInsightsSheet: some View {
        insightRowsSheet(
            title: "Color Insights",
            subtitle: "White, navy, black, beige, and denim colors are strong base colors for building outfits.",
            rows: colorSummaryRows,
            empty: "Add colors to see your closet palette.",
            actionTitle: "Ask AI for Color Matches",
            actionPrompt: "Explain my best color combinations from my closet. \(structuredClosetContext)"
        )
    }

    private var brandInsightsSheet: some View {
        insightRowsSheet(
            title: "Brand Insights",
            subtitle: "StyleMatch Pro only recommends brands after checking your saved preferences and budget.",
            rows: brandSummaryRows,
            empty: "Add brands to personalize shopping and outfit matching.",
            actionTitle: "Ask AI for Brand Matches",
            actionPrompt: "Recommend matching brands only if they fit my closet and budget. \(structuredClosetContext)"
        )
    }

    private var styleCategoriesSheet: some View {
        NavigationStack {
            List {
                Section("Categories") {
                    ForEach(categories, id: \.self) { category in
                        Button {
                            activeSheet = .category(category)
                        } label: {
                            HStack {
                                Label(category, systemImage: iconName(for: category))
                                Spacer()
                                Text("\(items(forCategory: category).count)")
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Style Categories")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { activeSheet = nil } } }
        }
    }

    private func seasonalSheet(_ title: String) -> some View {
        let sheetItems = seasonalItems(for: title)
        return NavigationStack {
            List {
                Section {
                    Text(seasonalAdvice(for: title, count: sheetItems.count))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("Matching Closet Items") {
                    if sheetItems.isEmpty {
                        emptySheetState("No matching items yet.")
                    } else {
                        ForEach(sheetItems) { item in
                            Button { activeSheet = .itemDetail(item.id) } label: {
                                Label(itemInventoryLabel(for: item), systemImage: iconName(for: item.category))
                            }
                        }
                    }
                }

                Section {
                    Button {
                        closetActionMessage = "Plan \(title.lowercased()) outfits using live weather and my closet. \(structuredClosetContext)"
                        activeSheet = .closetDesigner
                    } label: {
                        Label("Ask AI For \(title)", systemImage: "sparkles")
                    }
                }
            }
            .navigationTitle(title)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { activeSheet = nil } } }
        }
    }

    private var laundrySheet: some View {
        NavigationStack {
            List {
                Section("Suggestions") {
                    ForEach(laundrySuggestions, id: \.self) { suggestion in
                        Label(suggestion, systemImage: "washer.fill")
                    }
                }

                Section("Quick Tracking") {
                    ForEach(items.prefix(12)) { item in
                        HStack {
                            Label(displayName(for: item), systemImage: iconName(for: item.category))
                            Spacer()
                            Button("Worn") { closetActionMessage = "\(displayName(for: item)) marked worn for laundry planning." }
                            Button("Clean") { closetActionMessage = "\(displayName(for: item)) marked clean." }
                        }
                    }
                }

                if !closetActionMessage.isEmpty {
                    Section {
                        Text(closetActionMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Laundry Tracker")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { activeSheet = nil } } }
        }
    }

    private var closetDesignerSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    AIStyleInsightCard(
                        tab: .closet,
                        screen: "AI Closet Designer",
                        title: "Build From My Closet",
                        prompt: closetActionMessage.isEmpty ? "Analyze my closet first. Tell me what outfits I can build, what is missing, and what I should avoid buying unnecessarily." : closetActionMessage,
                        fallbackAdvice: closetDesignerFallback,
                        extraContext: structuredClosetContext
                    )

                    infoPanel(title: "Closet Completeness", rows: [
                        "Saved items: \(items.count)",
                        "Categories: \(categoryCounts.count)",
                        "Missing essentials: \(missingEssentialsText)",
                        "Top color: \(colorSummaryRows.first?.name ?? "Not set")",
                        "Top brand: \(brandSummaryRows.first?.name ?? "Not set")"
                    ])
                }
                .padding()
                .padding(.bottom, 120)
            }
            .navigationTitle("AI Closet Designer")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { activeSheet = nil } } }
        }
    }

    private func insightRowsSheet(title: String, subtitle: String, rows: [(name: String, count: Int)], empty: String, actionTitle: String, actionPrompt: String) -> some View {
        NavigationStack {
            List {
                Section {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("Breakdown") {
                    if rows.isEmpty {
                        emptySheetState(empty)
                    } else {
                        ForEach(rows, id: \.name) { row in
                            HStack {
                                Text(row.name)
                                Spacer()
                                Text("\(row.count) item\(row.count == 1 ? "" : "s")")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section {
                    Button {
                        closetActionMessage = actionPrompt
                        activeSheet = .closetDesigner
                    } label: {
                        Label(actionTitle, systemImage: "sparkles")
                    }
                }
            }
            .navigationTitle(title)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { activeSheet = nil } } }
        }
    }

    private func infoPanel(title: String, rows: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            ForEach(rows, id: \.self) { row in
                Label(row, systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .appCard(.closet)
    }

    private func emptySheet(title: String, message: String) -> some View {
        NavigationStack {
            emptySheetState(message)
                .padding()
                .navigationTitle(title)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { activeSheet = nil } } }
        }
    }

    private func emptySheetState(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
    }

    private func seasonalAdvice(for title: String, count: Int) -> String {
        if count == 0 {
            return "No \(title.lowercased()) pieces found yet. Add season and weather details to improve planning."
        }
        return "You have \(count) \(title.lowercased()) piece\(count == 1 ? "" : "s") ready. Ask AI to build an outfit from these before shopping."
    }

    private var missingEssentialsText: String {
        let required = ["Shirt", "Pants", "Shoes", "Jacket"]
        let missing = required.filter { category in !items.contains { $0.category == category || (category == "Pants" && $0.category == "Jeans") } }
        return missing.isEmpty ? "None" : missing.joined(separator: ", ")
    }

    private var closetDesignerFallback: String {
        if items.isEmpty {
            return "Add at least one shirt, one pant, one shoe, and one jacket so StyleMatch Pro can build outfits before recommending purchases."
        }
        return "StyleMatch Pro checks your saved closet first. Missing essentials: \(missingEssentialsText). Top colors: \(colorSummaryRows.prefix(3).map(\.name).joined(separator: ", "))."
    }
}

private struct ClosetDashboardOutfit: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let items: [ClosetItem]
}

private struct ClosetCompactCard: Identifiable {
    let id = UUID()
    let title: String
    let summary: String
    let icon: String
    let tint: Color
    let sheet: ClosetDashboardSheet
}

private enum ClosetDashboardSheet: Identifiable, Equatable {
    case savedClothing
    case favoriteOutfits
    case recentlyAdded
    case colorInsights
    case brandInsights
    case styleCategories
    case category(String)
    case seasonal(String)
    case laundry
    case closetDesigner
    case itemDetail(UUID)

    var id: String {
        switch self {
        case .savedClothing:
            return "savedClothing"
        case .favoriteOutfits:
            return "favoriteOutfits"
        case .recentlyAdded:
            return "recentlyAdded"
        case .colorInsights:
            return "colorInsights"
        case .brandInsights:
            return "brandInsights"
        case .styleCategories:
            return "styleCategories"
        case .category(let category):
            return "category-\(category)"
        case .seasonal(let title):
            return "seasonal-\(title)"
        case .laundry:
            return "laundry"
        case .closetDesigner:
            return "closetDesigner"
        case .itemDetail(let id):
            return "itemDetail-\(id.uuidString)"
        }
    }
}

private struct AddClothingItemView: View {
    @Binding var name: String
    @Binding var category: String
    @Binding var color: String
    @Binding var brand: String
    @Binding var size: String
    @Binding var occasion: String
    @Binding var season: String
    @Binding var weatherUse: String
    @Binding var isFavorite: Bool
    @Binding var notes: String

    let categories: [String]
    let colors: [String]
    let shirtSizes: [String]
    let pantSizes: [String]
    let shoeSizes: [String]
    let occasions: [String]
    let seasons: [String]
    let weatherUses: [String]
    let colorLabel: String
    let sizeLabel: String
    let aiDescriptionSuggestion: String
    let onCategoryChange: (String) -> Void
    let onAddPhoto: () -> Void
    let onDescribe: () -> Void
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var availableSizes: [String] {
        switch category {
        case "Pants", "Jeans":
            return pantSizes
        case "Shoes":
            return shoeSizes
        default:
            return shirtSizes
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    TextField("Item name", text: $name)
                        .textFieldStyle(.roundedBorder)

                    categorySelector

                    labeledControl(colorLabel) {
                        Picker(colorLabel, selection: $color) {
                            ForEach(colors, id: \.self) { Text($0).tag($0) }
                        }
                        .pickerStyle(.menu)
                    }

                    HStack(spacing: 12) {
                        labeledControl("Brand") {
                            TextField("Brand", text: $brand)
                                .textFieldStyle(.roundedBorder)
                        }

                        labeledControl(sizeLabel) {
                            if category == "Pants" || category == "Jeans" {
                                TextField("Pants size", text: $size)
                                    .textFieldStyle(.roundedBorder)
                            } else {
                                Picker(sizeLabel, selection: $size) {
                                    ForEach(availableSizes, id: \.self) { Text($0).tag($0) }
                                }
                                .pickerStyle(.menu)
                            }
                        }
                    }

                    labeledControl("Occasion") {
                        Picker("Occasion", selection: $occasion) {
                            ForEach(occasions, id: \.self) { Text($0).tag($0) }
                        }
                        .pickerStyle(.menu)
                    }

                    HStack(spacing: 12) {
                        labeledControl("Season") {
                            Picker("Season", selection: $season) {
                                ForEach(seasons, id: \.self) { Text($0).tag($0) }
                            }
                            .pickerStyle(.menu)
                        }

                        labeledControl("Weather use") {
                            Picker("Weather use", selection: $weatherUse) {
                                ForEach(weatherUses, id: \.self) { Text($0).tag($0) }
                            }
                            .pickerStyle(.menu)
                        }
                    }

                    Toggle("Mark as favorite", isOn: $isFavorite)
                        .toggleStyle(.switch)

                    HStack(spacing: 10) {
                        Button {
                            onAddPhoto()
                            dismiss()
                        } label: {
                            Label("Add Photo", systemImage: "camera.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            onDescribe()
                        } label: {
                            Label("Let AI Describe", systemImage: "sparkles")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }

                    TextField("Notes", text: $notes, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...4)

                    Button {
                        onSave()
                        dismiss()
                    } label: {
                        Label("Save to Closet", systemImage: "tray.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding()
            }
            .navigationTitle("Add Item")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var categorySelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Category")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 8)], spacing: 8) {
                ForEach(categories, id: \.self) { option in
                    Button {
                        category = option
                        onCategoryChange(option)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: iconName(for: option))
                            Text(closetShortCategoryLabel(option))
                        }
                        .font(.caption)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity, minHeight: 46)
                    }
                    .buttonStyle(.bordered)
                    .tint(category == option ? AppTab.closet.palette.accent : .secondary)
                }
            }
        }
    }

    private func labeledControl<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func iconName(for category: String) -> String {
        switch category {
        case "Pants", "Jeans":
            return "figure.walk"
        case "Shoes":
            return "shoeprints.fill"
        case "Jacket":
            return "person.crop.square"
        case "Dress":
            return "person"
        case "Accessory":
            return "watch.analog"
        case "Bag":
            return "bag"
        case "Hat":
            return "graduationcap"
        case "Traditional Wear":
            return "sparkles"
        case "Formal Wear":
            return "suitcase"
        case "Casual Wear":
            return "figure.wave"
        case "Sportswear":
            return "figure.run"
        default:
            return "tshirt"
        }
    }
}

struct SizeProfileView: View {
    @AppStorage("sizeProfile") private var sizeProfile = ""
    @AppStorage("shirtSize") private var shirtSize = ""
    @AppStorage("pantsSize") private var pantsSize = ""
    @AppStorage("waistSize") private var waistSize = ""
    @AppStorage("inseamLength") private var inseamLength = ""
    @AppStorage("neckSize") private var neckSize = ""
    @AppStorage("sleeveLength") private var sleeveLength = ""
    @AppStorage("shoeSize") private var shoeSize = ""
    @AppStorage("fitPreference") private var fitPreference = ""
    @AppStorage("sizeCategory") private var sizeCategory = ""

    @State private var saveConfirmation = ""

    private let shirtSizes = ClosetView.allShirtSizes
    private let pantSizes = ClosetView.allPantSizes
    private let shoeSizes = ClosetView.allShoeSizes
    private let fitPreferenceOptions = ["Slim", "Regular", "Relaxed", "Oversized", "Tailored"]
    private let sizeCategories = ["Men", "Women", "Unisex", "Kids/Youth"]

    var body: some View {
        Form {
            Section {
                Picker("Sizing category", selection: $sizeCategory) {
                    ForEach(sizeCategories, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)

                Picker("Shirt size", selection: $shirtSize) {
                    ForEach(shirtSizes, id: \.self) { Text($0).tag($0) }
                }

                Text(generatedPantsDisplay ?? "Add waist and inseam")
                    .font(.headline)
                    .foregroundStyle(generatedPantsDisplay == nil ? .secondary : .primary)
            } header: {
                Text("Core Sizes")
            } footer: {
                Text("Saved privately on this phone and used only for fit and clothing recommendations.")
            }

            Section("Measurements") {
                TextField("Waist", text: $waistSize)
                    .keyboardType(.numbersAndPunctuation)
                TextField("Inseam / length", text: $inseamLength)
                    .keyboardType(.numbersAndPunctuation)
                TextField("Neck", text: $neckSize)
                    .keyboardType(.numbersAndPunctuation)
                TextField("Sleeve / arm", text: $sleeveLength)
                    .keyboardType(.numbersAndPunctuation)
            }

            Section("Shoes and Fit") {
                Picker("Shoe size", selection: $shoeSize) {
                    ForEach(shoeSizes, id: \.self) { Text($0).tag($0) }
                }

                Picker("Preferred fit", selection: $fitPreference) {
                    ForEach(fitPreferenceOptions, id: \.self) { Text($0).tag($0) }
                }
            }

            Section("Preview") {
                Text(sizeProfile)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Size Profile")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(saveConfirmation.isEmpty ? "Save" : "Saved") {
                    updateSizeProfileSummary()
                    saveConfirmation = "Profile saved successfully."
                }
                .fontWeight(.semibold)
            }
        }
        .styleMatchOnChange(of: shirtSize) { _ in updateSizeProfileSummary() }
        .styleMatchOnChange(of: sizeCategory) { _ in updateSizeProfileSummary() }
        .styleMatchOnChange(of: waistSize) { _ in updateSizeProfileSummary() }
        .styleMatchOnChange(of: inseamLength) { _ in updateSizeProfileSummary() }
        .styleMatchOnChange(of: neckSize) { _ in updateSizeProfileSummary() }
        .styleMatchOnChange(of: sleeveLength) { _ in updateSizeProfileSummary() }
        .styleMatchOnChange(of: shoeSize) { _ in updateSizeProfileSummary() }
        .styleMatchOnChange(of: fitPreference) { _ in updateSizeProfileSummary() }
    }

    private var generatedPantsDisplay: String? {
        PantsSizeSync.displayValue(waist: waistSize, inseam: inseamLength)
    }

    private func sizeSummaryRows() -> [(label: String, value: String)] {
        var rows: [(String, String)] = []
        let cleanCategory = sizeCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        let category = cleanCategory.isEmpty ? "Men" : cleanCategory
        if !shirtSize.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            rows.append(("Shirt", shirtSize))
        }
        if PantsSizeSync.categoryUsesGeneratedPants(category), let generatedPantsDisplay {
            rows.append(("Pants", generatedPantsDisplay))
        } else if !pantsSize.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            rows.append(("Bottoms", pantsSize))
        }
        if !shoeSize.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            rows.append(("Shoes", shoeSize))
        }
        if !fitPreference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            rows.append(("Fit", fitPreference))
        }
        return rows
    }

    private func updateSizeProfileSummary() {
        saveConfirmation = ""
        let category = sizeCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        if PantsSizeSync.categoryUsesGeneratedPants(category.isEmpty ? "Men" : category) {
            let reconciled = PantsSizeSync.reconciledValues(
                pantsSize: pantsSize,
                waistSize: waistSize,
                inseamLength: inseamLength,
                category: category.isEmpty ? "Men" : category
            )
            pantsSize = reconciled.pantsSize
            waistSize = reconciled.waistSize
            inseamLength = reconciled.inseamLength
        } else {
            waistSize = ""
            inseamLength = ""
        }
        let rows = sizeSummaryRows()
        sizeProfile = rows.isEmpty ? "No sizes saved yet" : rows.map { "\($0.label): \($0.value)" }.joined(separator: "; ")
    }
}

private struct ClosetItemDetailSheet: View {
    let item: ClosetItem
    let isFavorite: Bool
    let onSave: (ClosetItem) -> Void
    let onDelete: () -> Void
    let onFavorite: (Bool) -> Void
    let onAskAI: () -> Void
    let onBuildOutfit: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var category: String
    @State private var color: String
    @State private var brand: String
    @State private var size: String
    @State private var occasion: String
    @State private var notes: String
    @State private var favorite: Bool

    init(
        item: ClosetItem,
        isFavorite: Bool,
        onSave: @escaping (ClosetItem) -> Void,
        onDelete: @escaping () -> Void,
        onFavorite: @escaping (Bool) -> Void,
        onAskAI: @escaping () -> Void,
        onBuildOutfit: @escaping () -> Void
    ) {
        self.item = item
        self.isFavorite = isFavorite
        self.onSave = onSave
        self.onDelete = onDelete
        self.onFavorite = onFavorite
        self.onAskAI = onAskAI
        self.onBuildOutfit = onBuildOutfit
        _name = State(initialValue: ClosetItemDisplay.displayName(for: item))
        _category = State(initialValue: item.category)
        _color = State(initialValue: item.color)
        _brand = State(initialValue: item.brand)
        _size = State(initialValue: item.size)
        _occasion = State(initialValue: item.occasion)
        _notes = State(initialValue: item.notes)
        _favorite = State(initialValue: isFavorite)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Clothing Detail") {
                    TextField("Item name", text: $name)
                    TextField("Category", text: $category)
                    TextField("Color", text: $color)
                    TextField("Size", text: $size)
                    TextField("Brand", text: $brand)
                    TextField("Occasion", text: $occasion)
                    TextField("Season, weather, notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                    Toggle("Favorite", isOn: $favorite)
                }

                Section("AI Styling") {
                    Button {
                        onAskAI()
                    } label: {
                        Label("Ask AI how to style this", systemImage: "sparkles")
                    }

                    Button {
                        onBuildOutfit()
                    } label: {
                        Label("Build outfit with this item", systemImage: "wand.and.stars")
                    }
                }

                Section {
                    Button(role: .destructive) {
                        onDelete()
                        dismiss()
                    } label: {
                        Label("Delete Item", systemImage: "trash")
                    }
                }
            }
            .navigationTitle(ClosetItemDisplay.displayName(for: item))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        let updated = ClosetItem(
                            id: item.id,
                            name: ClosetItemDisplay.displayName(name: name, category: category, color: color),
                            category: category.trimmingCharacters(in: .whitespacesAndNewlines),
                            color: color.trimmingCharacters(in: .whitespacesAndNewlines),
                            brand: brand.trimmingCharacters(in: .whitespacesAndNewlines),
                            size: size.trimmingCharacters(in: .whitespacesAndNewlines),
                            occasion: occasion.trimmingCharacters(in: .whitespacesAndNewlines),
                            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                        onSave(updated)
                        onFavorite(favorite)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private func closetShortCategoryLabel(_ category: String) -> String {
    switch category {
    case "Traditional Wear": return "Traditional"
    case "Formal Wear": return "Formal"
    case "Casual Wear": return "Casual"
    case "Sportswear": return "Sport"
    default: return category
    }
}
