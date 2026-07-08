import SwiftUI

private struct StyleMatchNavigationTarget: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let tab: AppTab
    let keywords: [String]
}

private let styleMatchNavigationTargets: [StyleMatchNavigationTarget] = [
    StyleMatchNavigationTarget(id: "scan", title: "Scan Outfit", subtitle: "Open camera or gallery scanner", icon: "camera.viewfinder", tab: .scan, keywords: ["scan", "camera", "photo", "outfit", "analyze"]),
    StyleMatchNavigationTarget(id: "closet", title: "Closet", subtitle: "View saved clothing and sizes", icon: "tshirt.fill", tab: .closet, keywords: ["closet", "clothes", "wardrobe", "saved clothing", "sizes"]),
    StyleMatchNavigationTarget(id: "shopping", title: "Shopping", subtitle: "Find stores, sale items, and matches", icon: "bag.fill", tab: .shop, keywords: ["shop", "shopping", "sale", "deals", "store", "items", "saved items"]),
    StyleMatchNavigationTarget(id: "ai", title: "AI Stylist", subtitle: "Ask your personal stylist", icon: "sparkles", tab: .ai, keywords: ["ai", "stylist", "chat", "ask", "assistant", "advice"]),
    StyleMatchNavigationTarget(id: "profile", title: "Profile", subtitle: "Account, sizes, privacy, settings", icon: "person.crop.circle.fill", tab: .profile, keywords: ["profile", "account", "settings", "privacy", "theme", "sizes"]),
    StyleMatchNavigationTarget(id: "weather", title: "Weather Styling", subtitle: "Refresh weather outfit advice", icon: "cloud.sun.fill", tab: .ai, keywords: ["weather", "forecast", "rain", "temperature", "outfit advice"]),
    StyleMatchNavigationTarget(id: "favorites", title: "Favorites", subtitle: "Open saved looks and favorite items", icon: "heart.fill", tab: .scan, keywords: ["favorites", "favorite outfits", "saved scans", "history"]),
    StyleMatchNavigationTarget(id: "saved", title: "Saved Items", subtitle: "Review saved shopping and closet pieces", icon: "bookmark.fill", tab: .shop, keywords: ["saved", "wishlist", "shopping cards", "favorites", "saved items"])
]

struct HomeView: View {
    @Binding var selectedTab: AppTab
    @AppStorage("preferredAIAssistant") private var preferredAIAssistant = PreferredAIAssistant.siri.rawValue
    @AppStorage("profileName") private var profileName = ""
    @AppStorage("weather") private var weather = "82°"
    @AppStorage("weatherCondition") private var weatherCondition = "Sunny"
    @AppStorage("plannedOccasion") private var plannedOccasion = "Work"
    @AppStorage("dressCode") private var dressCode = "Smart casual"
    @AppStorage("sizeProfile") private var sizeProfile = "Shirt: L; Pants: Men 36x36; Shoes: 10"
    @AppStorage("favoriteColors") private var favoriteColors = "Black, white, navy"
    @AppStorage("shoppingBudget") private var budget = "$50 - $200"
    @AppStorage("favoriteBrands") private var favoriteBrands = "Ralph Lauren, Nike, Levi's"
    @AppStorage("fitPreference") private var fitPreference = "Regular"
    @AppStorage("outfitScanHistoryData") private var outfitScanHistoryData = Data()
    @AppStorage("closetItemsData") private var closetItemsData = Data()
    @AppStorage("wishlistProductNamesData") private var wishlistProductNamesData = Data()
    @State private var navigationQuery = ""

    private var selectedAssistant: PreferredAIAssistant {
        PreferredAIAssistant(rawValue: preferredAIAssistant) ?? .siri
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    premiumHeader

                    smartNavigationCard

                    quickActionsSection

                    styleBriefCard

                    continueCard

                    AIStyleInsightCard(
                        tab: .home,
                        screen: "Home",
                        title: "Personal AI Stylist",
                        prompt: "Give me one warm, respectful style move I should make today using my closet, profile, weather, sizes, and recent scans.",
                        fallbackAdvice: "Your AI Stylist learns your wardrobe, favorite colors, sizes, budget, and style preferences to give personalized outfit recommendations every day.",
                        extraContext: "The customer is deciding where to start."
                    )

                    aiMemoryStatusCard

                    styleProgressCard

                    motivationCard

                    if FeatureGate.shared.isCustomerVisible(.aiAssistantChoice) {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("AI assistant", systemImage: "sparkles")
                                .font(.headline)

                            Text(selectedAssistant.rawValue)
                                .font(.title2)
                                .fontWeight(.bold)

                            Text(selectedAssistant.description)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineSpacing(4)

                            Button {
                                selectedTab = .ai
                            } label: {
                                Label("Choose AI Assistant", systemImage: "sparkles")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding()
                        .appCard(.ai)
                    }
                }
                .padding()
            }
            .scrollContentBackground(.hidden)
            .appScreenBackground(.home)
            .navigationTitle("Style Match Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        selectedTab = .profile
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                    .accessibilityLabel("Open Profile")
                }
            }
        }
    }

    private var smartNavigationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Quick Jump", systemImage: "magnifyingglass")
                .font(.headline)

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Search StyleMatch Pro", text: $navigationQuery)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                if !navigationQuery.isEmpty {
                    Button {
                        navigationQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(12)
            .background(Color(.secondarySystemBackground).opacity(0.78))
            .clipShape(RoundedRectangle(cornerRadius: 14))

            VStack(spacing: 8) {
                ForEach(navigationMatches.prefix(navigationQuery.isEmpty ? 4 : 6)) { target in
                    Button {
                        navigate(to: target)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: target.icon)
                                .font(.headline)
                                .foregroundStyle(target.tab.palette.accent)
                                .frame(width: 34, height: 34)
                                .background(target.tab.palette.accent.opacity(0.14))
                                .clipShape(RoundedRectangle(cornerRadius: 10))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(target.title)
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.primary)

                                Text(target.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .background(Color(.systemBackground).opacity(0.72))
                        .clipShape(RoundedRectangle(cornerRadius: 13))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .appCard(.home, radius: 16)
    }

    private var navigationMatches: [StyleMatchNavigationTarget] {
        let query = navigationQuery
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !query.isEmpty else {
            return styleMatchNavigationTargets
        }

        return styleMatchNavigationTargets.filter { target in
            target.title.lowercased().contains(query)
            || target.subtitle.lowercased().contains(query)
            || target.keywords.contains { $0.lowercased().contains(query) || query.contains($0.lowercased()) }
        }
    }

    private func navigate(to target: StyleMatchNavigationTarget) {
        navigationQuery = ""
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            selectedTab = target.tab
        }
    }

    private var premiumHeader: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(homeGreeting) 👋")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.75)
                    .lineLimit(2)

                Text("Ready to build today's best outfit?")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            topStyleScoreCard

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                homeSignal(icon: "cloud.sun.fill", text: "\(weatherTemperatureText) Today", tint: Color(hex: 0xF5B84B))
                homeSignal(icon: "person.fill.checkmark", text: outfitMoodText, tint: AppTab.closet.palette.accent)
                homeSignal(icon: "tshirt.fill", text: "\(closetItemCountText) Closet Items", tint: AppTab.scan.palette.accent)
                homeSignal(icon: "sparkles", text: "AI Confidence: High", tint: AppTab.ai.palette.accent)
            }
        }
        .padding(18)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 26)
                    .fill(.regularMaterial)
                LinearGradient(
                    colors: [
                        Color(.systemBackground).opacity(0.82),
                        AppTab.home.palette.accent.opacity(0.13),
                        Color(hex: 0xF5B84B).opacity(0.10)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 26))
        .overlay(
            RoundedRectangle(cornerRadius: 26)
                .stroke(Color.white.opacity(0.42), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 18, x: 0, y: 10)
    }

    private var topStyleScoreCard: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Today's Style")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)

                Text(latestScoreText)
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Text(scoreRatingTitle(for: latestScoreValue))
                    .font(.subheadline)
                    .fontWeight(.bold)

                scoreStars(for: latestScoreValue)

                Text("↑ +4 since yesterday")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(.green)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Image(systemName: "star.fill")
                    .font(.title2)
                    .foregroundStyle(AppTab.ai.palette.accent)
                    .frame(width: 44, height: 44)
                    .background(AppTab.ai.palette.accent.opacity(0.14))
                    .clipShape(Circle())

                Text("AI Confidence: High")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemBackground).opacity(0.78))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var styleBriefCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sun.max.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(AppTab.home.palette.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Today's Style Brief")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Your personal stylist checked the day before you get dressed.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()
            }

            VStack(alignment: .leading, spacing: 10) {
                styleBriefRow(icon: "cloud.sun.fill", title: "Weather", detail: "\(weatherConditionText), \(weatherTemperatureText)")
                styleBriefRow(icon: "calendar", title: "Calendar", detail: calendarBriefText)
                styleBriefRow(icon: "sparkles", title: "Outfit", detail: "Navy polo, beige chinos, and white sneakers")
                styleBriefRow(icon: "tshirt.fill", title: "Closet items", detail: closetItemsToWearText)
                styleBriefRow(icon: "washer.fill", title: "Laundry", detail: laundryBriefText)
                styleBriefRow(icon: "plus.circle.fill", title: "Missing pieces", detail: missingPieceText)
                if shouldShowShoppingBrief {
                    styleBriefRow(icon: "bag.fill", title: "Shopping", detail: shoppingBriefText)
                }
            }
        }
        .padding()
        .appCard(.home, radius: 16)
    }

    private func styleBriefRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(AppTab.home.palette.accent)
                .frame(width: 28, height: 28)
                .background(AppTab.home.palette.accent.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)

                Text(detail)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }

    private var motivationCard: some View {
        Button {
            selectedTab = .ai
        } label: {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "lightbulb.fill")
                    .font(.title2)
                    .foregroundStyle(Color(hex: 0xF5B84B))
                    .frame(width: 48, height: 48)
                    .background(Color(hex: 0xF5B84B).opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 5) {
                    Text("Today's Style Tip")
                        .font(.headline)

                    Text("Neutral colors pair well with bold accessories.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Learn More →")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(AppTab.ai.palette.accent)
                }

                Spacer(minLength: 0)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .appCard(.home, radius: 16)
    }

    private var styleProgressCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Style Progress", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.headline)

                Spacer()

                Text("+6 this month")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.green.opacity(0.12))
                    .clipShape(Capsule())
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                progressMetric(title: "Current Score", value: latestScoreText, icon: "star.fill", tint: AppTab.ai.palette.accent)
                progressMetric(title: "Closet", value: "\(progressClosetCountText) items", icon: "tshirt.fill", tint: AppTab.closet.palette.accent)
                progressMetric(title: "Favorite Color", value: favoriteColorText, icon: "paintpalette.fill", tint: .blue)
                progressMetric(title: "Most Worn", value: mostWornText, icon: "shoe.2.fill", tint: Color(hex: 0x5B57D6))
            }
        }
        .padding()
        .appCard(.home, radius: 16)
    }

    private func progressMetric(title: String, value: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(tint)

            Text(title)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var aiMemoryStatusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "brain.head.profile")
                    .font(.title3)
                    .foregroundStyle(AppTab.ai.palette.accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text("AI has learned")
                        .font(.headline)

                    Text("Style Match Pro gets smarter as you scan, save, and shop.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                aiMemoryItem(title: "Favorite Color", value: favoriteColorText)
                aiMemoryItem(title: "Favorite Fit", value: favoriteFitText)
                aiMemoryItem(title: "Budget", value: budgetLevelText)
                aiMemoryItem(title: "Closet Items", value: memoryClosetCountText)
                aiMemoryItem(title: "Favorite Brands", value: favoriteBrandListText)
            }
        }
        .padding()
        .appCard(.ai, radius: 16)
    }

    private func aiMemoryItem(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: "checkmark.circle.fill")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(.primary)
                .lineLimit(3)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
        .padding(12)
        .background(AppTab.ai.palette.accent.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var continueCard: some View {
        let task = continueTask

        return Button {
            selectedTab = task.tab
        } label: {
            HStack(spacing: 14) {
                Image(systemName: task.icon)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(task.tint)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                VStack(alignment: .leading, spacing: 5) {
                    Text("Continue")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)

                    Text(task.title)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)

                    Text(task.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 22)
                        .fill(Color(.systemBackground).opacity(0.92))
                    LinearGradient(
                        colors: [task.tint.opacity(0.14), Color(.systemBackground).opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .stroke(task.tint.opacity(0.30), lineWidth: 1)
            )
            .shadow(color: task.tint.opacity(0.12), radius: 14, x: 0, y: 7)
        }
        .buttonStyle(.plain)
    }

    private func homeSignal(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.14))
                .clipShape(Circle())

            Text(text)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.78)

            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground).opacity(0.78))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.title2)
                .fontWeight(.bold)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                quickAction(icon: "camera.viewfinder", title: "Analyze", tab: .scan, tint: AppTab.scan.palette.accent)
                quickAction(icon: "tshirt.fill", title: "Closet", tab: .closet, tint: AppTab.closet.palette.accent)
                quickAction(icon: "bag.fill", title: "Shop", tab: .shop, tint: AppTab.shop.palette.accent)
                quickAction(icon: "sparkles", title: "Ask AI", tab: .ai, tint: AppTab.ai.palette.accent)
            }
        }
    }

    private func quickAction(icon: String, title: String, tab: AppTab, tint: Color) -> some View {
        Button {
            selectedTab = tab
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(tint)
                    .frame(width: 42, height: 42)
                    .background(tint.opacity(0.14))
                    .clipShape(Circle())

                Text(title)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .frame(minHeight: 74)
        .padding(.horizontal, 14)
        .background(Color(.systemBackground).opacity(0.86))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(tint.opacity(0.28), lineWidth: 1)
        )
        .shadow(color: tint.opacity(0.10), radius: 10, x: 0, y: 5)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())

        switch hour {
        case 5..<12:
            return "Morning"
        case 12..<17:
            return "Afternoon"
        default:
            return "Evening"
        }
    }

    private var displayName: String {
        StyleMatchGreetingBuilder.firstName(from: profileName) ?? ""
    }

    private var homeGreeting: String {
        StyleMatchGreetingBuilder.greetingLine(storedName: profileName)
    }

    private var latestScoreText: String {
        guard !outfitScanHistoryData.isEmpty,
              let history = try? JSONDecoder().decode([String: HomeStoredScan].self, from: outfitScanHistoryData),
              let latestScan = history.values.sorted(by: { $0.firstScannedAt > $1.firstScannedAt }).first else {
            return "92"
        }

        return "\(latestScan.score)"
    }

    private var latestScoreValue: Int {
        Int(latestScoreText) ?? 92
    }

    private func scoreRatingTitle(for score: Int) -> String {
        switch score {
        case 92...100:
            return "Excellent Match"
        case 86...91:
            return "Strong Match"
        case 78...85:
            return "Good Match"
        case 65...77:
            return "Style Tune-Up"
        default:
            return "Needs Styling"
        }
    }

    private func scoreStars(for score: Int) -> some View {
        let filledStars: Int
        switch score {
        case 92...100:
            filledStars = 5
        case 84...91:
            filledStars = 4
        case 72...83:
            filledStars = 3
        case 60...71:
            filledStars = 2
        default:
            filledStars = 1
        }

        return HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { index in
                Image(systemName: index <= filledStars ? "star.fill" : "star")
            }
        }
        .font(.caption)
        .foregroundStyle(AppTab.ai.palette.accent)
        .accessibilityLabel("\(filledStars) out of 5 stars")
    }

    private var latestScan: HomeStoredScan? {
        guard !outfitScanHistoryData.isEmpty,
              let history = try? JSONDecoder().decode([String: HomeStoredScan].self, from: outfitScanHistoryData) else {
            return nil
        }

        return history.values.sorted(by: { $0.firstScannedAt > $1.firstScannedAt }).first
    }

    private var weatherConditionText: String {
        let trimmed = weatherCondition.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == "Mild" ? "Sunny" : trimmed
    }

    private var calendarBriefText: String {
        let event = plannedOccasion.trimmingCharacters(in: .whitespacesAndNewlines)
        let code = dressCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedEvent = event.isEmpty ? "No calendar access yet" : event
        let resolvedCode = code.isEmpty ? "smart casual" : code.lowercased()
        return "\(resolvedEvent), \(resolvedCode)"
    }

    private var closetItemsToWearText: String {
        let names = closetItems
            .prefix(3)
            .map { item in
                let color = item.color.trimmingCharacters(in: .whitespacesAndNewlines)
                let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
                return [color, name].filter { !$0.isEmpty }.joined(separator: " ")
            }
            .filter { !$0.isEmpty }

        return names.isEmpty ? "Navy polo, beige chinos, white sneakers" : names.joined(separator: ", ")
    }

    private var laundryBriefText: String {
        let whiteItems = closetItems.filter { item in
            item.color.localizedCaseInsensitiveContains("white") || item.name.localizedCaseInsensitiveContains("white")
        }.count
        let gymItems = closetItems.filter { $0.occasion.localizedCaseInsensitiveContains("gym") }.count
        let count = whiteItems + gymItems

        if count > 0 {
            return "Check \(count) light or gym item\(count == 1 ? "" : "s") before wearing."
        }

        return "White sneakers and gym pieces may need a quick refresh."
    }

    private var missingPieceText: String {
        let hasJacket = closetItems.contains { item in
            let text = "\(item.category) \(item.name)".lowercased()
            return text.contains("jacket") || text.contains("coat") || text.contains("blazer")
        }

        if !hasJacket && weatherConditionText.localizedCaseInsensitiveContains("cold") {
            return "Add a jacket or light layer."
        }

        let hasAccessories = closetItems.contains { item in
            let text = "\(item.category) \(item.name)".lowercased()
            return text.contains("accessor") || text.contains("belt") || text.contains("watch")
        }

        return hasAccessories ? "No urgent gap today." : "A belt or watch would finish the look."
    }

    private var shouldShowShoppingBrief: Bool {
        missingPieceText != "No urgent gap today." || wishlistCount > 0
    }

    private var shoppingBriefText: String {
        if wishlistCount > 0 {
            return "Review \(wishlistCount) saved item\(wishlistCount == 1 ? "" : "s") before buying anything new."
        }

        return missingPieceText == "No urgent gap today." ? "No shopping needed today." : "Shop only if the missing piece fits at least three outfits."
    }

    private var weatherTemperatureText: String {
        let pieces = "\(weather) \(weatherCondition)"
            .components(separatedBy: CharacterSet.whitespacesAndNewlines)

        if let temperature = pieces.first(where: { $0.contains("°") }) {
            return temperature.contains("F") || temperature.contains("C") ? temperature : "\(temperature)F"
        }

        return "84°F"
    }

    private var outfitMoodText: String {
        let savedOccasion = plannedOccasion.trimmingCharacters(in: .whitespacesAndNewlines)
        let savedDressCode = dressCode.trimmingCharacters(in: .whitespacesAndNewlines)

        if !savedOccasion.isEmpty && savedOccasion != "Work" {
            return savedOccasion
        }

        if savedDressCode.localizedCaseInsensitiveContains("casual") {
            return "Casual Friday"
        }

        return savedDressCode.isEmpty ? "Casual Friday" : savedDressCode
    }

    private var closetItemCountText: String {
        guard !closetItemsData.isEmpty,
              let items = try? JSONDecoder().decode([ClosetItem].self, from: closetItemsData),
              !items.isEmpty else {
            return "147"
        }

        return "\(items.count)"
    }

    private var memoryClosetCountText: String {
        let count = closetItemCount
        return count > 0 ? "\(count)" : "150"
    }

    private var progressClosetCountText: String {
        let count = closetItemCount
        return count > 0 ? "\(count)" : "148"
    }

    private var favoriteColorText: String {
        if let color = closetItems
            .map(\.color)
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .filter({ !$0.isEmpty })
            .reduce(into: [String: Int](), { counts, color in counts[color, default: 0] += 1 })
            .max(by: { $0.value < $1.value })?.key {
            return color
        }

        let savedColor = favoriteColors
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }

        return savedColor ?? "Blue"
    }

    private var favoriteFitText: String {
        let trimmed = fitPreference.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Athletic" : trimmed
    }

    private var budgetLevelText: String {
        let text = budget.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.contains("300") || text.contains("500") || text.localizedCaseInsensitiveContains("premium") {
            return "$$$"
        }
        if text.contains("50") || text.contains("100") || text.contains("200") || text.localizedCaseInsensitiveContains("moderate") {
            return "$$"
        }
        if text.contains("25") || text.localizedCaseInsensitiveContains("budget") {
            return "$"
        }
        return "$$"
    }

    private var favoriteBrandListText: String {
        let closetBrands = closetItems
            .map(\.brand)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let savedBrands = favoriteBrands
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var seenBrands = Set<String>()
        let brands = (closetBrands + savedBrands).filter { brand in
            seenBrands.insert(brand.lowercased()).inserted
        }.prefix(2)

        return brands.isEmpty ? "Nike\nLevi's" : brands.joined(separator: "\n")
    }

    private var mostWornText: String {
        let shoeItem = closetItems.first { item in
            let text = "\(item.category) \(item.name)".lowercased()
            return text.contains("shoe") || text.contains("sneaker")
        }

        if let shoeItem {
            let name = shoeItem.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? "Sneakers" : name
        }

        return "Sneakers"
    }

    private var closetItemCount: Int {
        closetItems.count
    }

    private var closetItems: [ClosetItem] {
        guard !closetItemsData.isEmpty,
              let items = try? JSONDecoder().decode([ClosetItem].self, from: closetItemsData) else {
            return []
        }

        return items
    }

    private var wishlistCount: Int {
        guard !wishlistProductNamesData.isEmpty,
              let names = try? JSONDecoder().decode([String].self, from: wishlistProductNamesData) else {
            return 0
        }

        return names.count
    }

    private var continueTask: HomeContinueTask {
        if closetItemCount == 0 {
            return HomeContinueTask(
                title: "Finish adding your closet",
                detail: "Add shirts, pants, shoes, sizes, colors, and brands so every outfit recommendation feels personal.",
                icon: "tshirt.fill",
                tint: AppTab.closet.palette.accent,
                tab: .closet
            )
        }

        if let latestScan {
            return HomeContinueTask(
                title: "Continue your last outfit",
                detail: "Review the saved \(latestScan.score) \(scoreRatingTitle(for: latestScan.score)) scan and ask your AI Stylist what to improve next.",
                icon: "camera.viewfinder",
                tint: AppTab.scan.palette.accent,
                tab: .scan
            )
        }

        if wishlistCount > 0 {
            return HomeContinueTask(
                title: "Continue shopping",
                detail: "You have \(wishlistCount) saved item\(wishlistCount == 1 ? "" : "s") waiting in Smart Shopping.",
                icon: "bag.fill",
                tint: AppTab.shop.palette.accent,
                tab: .shop
            )
        }

        if selectedAssistant == .chatGPT {
            return HomeContinueTask(
                title: "Open AI conversation",
                detail: "ChatGPT is ready to help build, improve, or shop your next outfit.",
                icon: "sparkles",
                tint: AppTab.ai.palette.accent,
                tab: .ai
            )
        }

        return HomeContinueTask(
            title: "Review today's outfit",
            detail: "Check \(weatherTemperatureText.lowercased()), \(outfitMoodText.lowercased()), and get a smart recommendation.",
            icon: "sun.max.fill",
            tint: Color(hex: 0xF5B84B),
            tab: .ai
        )
    }

    private var recommendedOutfitCount: Int {
        guard !closetItemsData.isEmpty,
              let items = try? JSONDecoder().decode([ClosetItem].self, from: closetItemsData),
              items.count >= 6 else {
            return 2
        }

        return min(5, max(2, items.count / 3))
    }
}

private struct HomeStoredScan: Codable {
    let score: Int
    let firstScannedAt: Date
}

private struct HomeContinueTask {
    let title: String
    let detail: String
    let icon: String
    let tint: Color
    let tab: AppTab
}
