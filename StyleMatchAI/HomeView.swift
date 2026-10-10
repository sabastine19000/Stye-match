import EventKit
import SwiftUI

private struct StyleMatchNavigationTarget: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let tab: AppTab
    let keywords: [String]
    let styleFriendsRoute: StyleFriendsHomeSearchRoute?
}

private let styleMatchNavigationTargets: [StyleMatchNavigationTarget] = [
    StyleMatchNavigationTarget(id: "style-friends", title: "Style Friends", subtitle: "Discover friends, shared looks, and conversations", icon: "person.2.fill", tab: .profile, keywords: ["style friends", "style friend", "friends", "friend"], styleFriendsRoute: .styleFriends),
    StyleMatchNavigationTarget(id: "style-friends-friends", title: "Friends", subtitle: "View and find Style Friends", icon: "person.2.fill", tab: .profile, keywords: ["friends", "friend", "find friends", "style friends"], styleFriendsRoute: .friends),
    StyleMatchNavigationTarget(id: "style-friends-find", title: "Find Style Friends", subtitle: "Discover people who share your style", icon: "person.badge.plus", tab: .profile, keywords: ["find friends", "find style friends", "friends", "friend", "discovery"], styleFriendsRoute: .findFriends),
    StyleMatchNavigationTarget(id: "style-friends-requests", title: "Friend Requests", subtitle: "Review incoming and outgoing requests", icon: "person.badge.plus", tab: .profile, keywords: ["friend requests", "requests", "request", "friends"], styleFriendsRoute: .friendRequests),
    StyleMatchNavigationTarget(id: "style-friends-conversations", title: "Conversations", subtitle: "Message your Style Friends", icon: "bubble.left.and.bubble.right.fill", tab: .profile, keywords: ["conversations", "conversation", "messages", "message", "chat", "friends"], styleFriendsRoute: .conversations),
    StyleMatchNavigationTarget(id: "style-friends-shared-looks", title: "Shared Looks", subtitle: "Review looks you shared with Style Friends", icon: "square.and.arrow.up.fill", tab: .profile, keywords: ["shared looks", "shared", "looks", "friends"], styleFriendsRoute: .sharedLooks),
    StyleMatchNavigationTarget(id: "style-friends-feed", title: "Friends Feed", subtitle: "See new looks from Style Friends", icon: "rectangle.stack.fill", tab: .profile, keywords: ["feed", "friends feed", "style friends", "friends"], styleFriendsRoute: .feed),
    StyleMatchNavigationTarget(id: "scan", title: "Scan Outfit", subtitle: "Open camera or gallery scanner", icon: "camera.viewfinder", tab: .scan, keywords: ["scan", "camera", "photo", "outfit", "analyze"], styleFriendsRoute: nil),
    StyleMatchNavigationTarget(id: "closet", title: "Closet", subtitle: "View saved clothing and sizes", icon: "tshirt.fill", tab: .closet, keywords: ["closet", "clothes", "wardrobe", "saved clothing", "sizes"], styleFriendsRoute: nil),
    StyleMatchNavigationTarget(id: "shopping", title: "Shopping", subtitle: "Find stores, sale items, and matches", icon: "bag.fill", tab: .shop, keywords: ["shop", "shopping", "sale", "deals", "store", "items", "saved items"], styleFriendsRoute: nil),
    StyleMatchNavigationTarget(id: "ai", title: "AI Stylist", subtitle: "Ask your personal stylist", icon: "sparkles", tab: .ai, keywords: ["ai", "stylist", "chat", "ask", "assistant", "advice"], styleFriendsRoute: nil),
    StyleMatchNavigationTarget(id: "profile", title: "Profile", subtitle: "Account, sizes, privacy, settings", icon: "person.crop.circle.fill", tab: .profile, keywords: ["profile", "account", "settings", "privacy", "theme", "sizes"], styleFriendsRoute: nil),
    StyleMatchNavigationTarget(id: "weather", title: "Weather Styling", subtitle: "Refresh weather outfit advice", icon: "cloud.sun.fill", tab: .ai, keywords: ["weather", "forecast", "rain", "temperature", "outfit advice"], styleFriendsRoute: nil),
    StyleMatchNavigationTarget(id: "favorites", title: "Favorites", subtitle: "Open saved looks and favorite items", icon: "heart.fill", tab: .scan, keywords: ["favorites", "favorite outfits", "saved scans", "history"], styleFriendsRoute: nil),
    StyleMatchNavigationTarget(id: "saved", title: "Saved Items", subtitle: "Review saved shopping and closet pieces", icon: "bookmark.fill", tab: .shop, keywords: ["saved", "wishlist", "shopping cards", "favorites", "saved items"], styleFriendsRoute: nil)
]

private enum HomeEngagementDestination: Hashable, Identifiable {
    case todayRecommendation
    case intelligence(HomeIntelligenceFocus)
    case aiStylistLearning
    case styleProgress

    var id: String {
        switch self {
        case .todayRecommendation:
            return "todayRecommendation"
        case .intelligence(let focus):
            return "home-intelligence-\(focus.rawValue)"
        case .aiStylistLearning:
            return "aiStylistLearning"
        case .styleProgress:
            return "styleProgress"
        }
    }
}

struct HomeView: View {
    @Binding var selectedTab: AppTab
    var navigationResetID = 0
    var feedbackPrompt: ScheduledFeedbackPrompt?
    var onHomeAppear: () -> Void = {}
    var onFeedbackWornAnswer: (ScheduledFeedbackPrompt, Bool) -> Void = { _, _ in }
    var onFeedbackLikedAnswer: (ScheduledFeedbackPrompt, Bool) -> Void = { _, _ in }
    var onFeedbackDislikeReason: (ScheduledFeedbackPrompt, DislikeReason) -> Void = { _, _ in }
    var onFeedbackDismiss: () -> Void = {}
    var onFeedbackComplete: () -> Void = {}
    var onSelectTab: ((AppTab) -> Void)?
    var onOpenScanHistory: () -> Void = {}
    var onOpenClosetAddItem: () -> Void = {}
    var onOpenContextualStylist: () -> Void = {}
    var onOpenHomeIntelligenceStylist: (HomeIntelligenceDetail) -> Void = { _ in }
    var onPrepareHomeIntelligenceShopping: (HomeIntelligenceDetail) -> Void = { _ in }
    /// Non-nil only in the Debug owner-beta composition. Keeping this optional
    /// removes the diagnostic control from customer Release navigation rather
    /// than leaving a no-op button behind.
    var onOpenBuildInformation: (() -> Void)?
    var floatingStylistClearance: CGFloat = 0
    @AppStorage("profileName") private var profileName = ""
    @ObservedObject private var weatherAuthority = WeatherKitAuthority.shared
    @AppStorage("plannedOccasion") private var plannedOccasion = ""
    @AppStorage("dressCode") private var dressCode = ""
    @AppStorage("sizeProfile") private var sizeProfile = ""
    @AppStorage("favoriteColors") private var favoriteColors = ""
    @AppStorage("shoppingBudget") private var budget = ""
    @AppStorage("favoriteBrands") private var favoriteBrands = ""
    @AppStorage("fitPreference") private var fitPreference = ""
    @AppStorage("workSetting") private var workSetting = ""
    @AppStorage("outfitScanHistoryData") private var outfitScanHistoryData = Data()
    @AppStorage("closetItemsData") private var closetItemsData = Data()
    @AppStorage("wishlistProductNamesData") private var wishlistProductNamesData = Data()
    @AppStorage("selectedAppTheme") private var selectedAppTheme = StyleMatchAppTheme.system.rawValue
    @AppStorage("styleMatchAppearanceMode") private var appearanceMode = StyleMatchAppearanceMode.manual.rawValue
    @AppStorage("styleMatchAdaptiveTheme") private var adaptiveTheme = ""
    @State private var navigationQuery = ""
    @FocusState private var navigationSearchFocused: Bool
    @State private var outfitHistoryQuery = ""
    @State private var homeEngagementPath: [HomeEngagementDestination] = []
    /// Forces a fresh bounded EventKit projection after Calendar changes. The
    /// projection, not raw events, remains the only Calendar data Home holds.
    @State private var calendarContextRefreshID = UUID()

    private var themeTokens: StyleMatchThemeTokens {
        StyleMatchAppearanceResolver.resolve(
            modeRawValue: appearanceMode,
            selectedThemeRawValue: selectedAppTheme,
            adaptiveThemeRawValue: adaptiveTheme
        ).theme.tokens(for: .home)
    }

    var body: some View {
        NavigationStack(path: $homeEngagementPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    dailyStyleBriefHero

                    smartNavigationCard

                    if let message = GlobalWeatherAlert.make(snapshot: weatherAuthority.snapshot).message {
                        WeatherStylingButton {
                            Label(message, systemImage: "umbrella.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(AppTab.ai.palette.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
                        }
                        .accessibilityLabel("Weather alert. \(message)")
                        .accessibilityHint("Opens Weather Styling.")
                    }

                    if let feedbackPrompt {
                        HomeOutfitFeedbackCard(
                            prompt: feedbackPrompt,
                            onWornAnswer: onFeedbackWornAnswer,
                            onLikedAnswer: onFeedbackLikedAnswer,
                            onDislikeReason: onFeedbackDislikeReason,
                            onDismissPrompt: onFeedbackDismiss,
                            onComplete: onFeedbackComplete
                        )
                    }

                    quickActionsSection

                    personalStylistDashboard

                    styleProgressCard

                    continueCard

                    outfitHistorySection

                }
                .padding()
                .padding(.bottom, 120)
            }
            .scrollContentBackground(.hidden)
            .appScreenBackground(.home)
            .navigationTitle("KigoStylist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let onOpenBuildInformation {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: onOpenBuildInformation) {
                            Image(systemName: "wrench.adjustable.fill")
                                .frame(width: 44, height: 44)
                        }
                        .contentShape(Rectangle())
                        .accessibilityLabel("Open owner build diagnostics")
                    }
                }
            }
            .navigationDestination(for: HomeEngagementDestination.self) { destination in
                homeEngagementDestination(destination)
            }
            .onAppear(perform: onHomeAppear)
            .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
                // EventKit may change after the customer edits Calendar while
                // StyleMatch is open. Refresh the minimized local snapshot.
                calendarContextRefreshID = UUID()
            }
            .styleMatchOnChange(of: navigationResetID) { _ in
                homeEngagementPath.removeAll()
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let attribution = weatherAuthority.attribution {
                WeatherKitAttributionView(attribution: attribution, surface: .home)
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
            }
        }
    }

    @ViewBuilder
    private func homeEngagementDestination(_ destination: HomeEngagementDestination) -> some View {
        switch destination {
        case .todayRecommendation:
            homeEngagementScroll(title: "Today's Style Brief") {
                homeSummaryCard(
                    icon: "sun.max.fill",
                    title: recommendedOutfitTitle,
                    rows: [
                        "Weather: \(homeWeatherSnapshot.briefText)",
                        "Occasion: \(calendarBriefText)",
                        "Outfit checklist: \(closetItemsToWearText)",
                        "Why this look: \(dailyStyleRecommendation?.rationale ?? "Complete your verified Closet before StyleMatch recommends a wearable look.")",
                        "Missing pieces: \(missingPieceText)"
                    ]
                )
                Button {
                    selectedTab = .closet
                } label: {
                    homeDestinationRow(icon: "tshirt.fill", title: "Open Closet", detail: "Review saved items used in this recommendation.")
                }
                .buttonStyle(.plain)
                Button {
                    selectedTab = .shop
                } label: {
                    homeDestinationRow(icon: "bag.fill", title: "Shop Missing Pieces", detail: shoppingBriefText)
                }
                .buttonStyle(.plain)
            }
        case .intelligence(let focus):
            homeIntelligenceWorkspace(detail: homeIntelligenceDetails[focus] ?? HomeIntelligenceAuthority.detail(for: focus, input: homeIntelligenceInput))
        case .aiStylistLearning:
            homeEngagementScroll(title: "AI Stylist Learning") {
                homeSummaryCard(
                    icon: "sparkles",
                    title: "Learning Progress: \(learningProgressPercent)%",
                    rows: [
                        "Favorite fit: \(favoriteFitText)",
                        "Budget: \(budgetLevelText)",
                        "Brands: \(favoriteBrandListText.replacingOccurrences(of: "\n", with: ", "))",
                        "\(StyleMatchHomeDisplay.countText(homeScans.count, singular: "saved scan"))"
                    ]
                )
                Button {
                    onOpenContextualStylist()
                } label: {
                    homeDestinationRow(icon: "bubble.left.and.bubble.right.fill", title: "Chat with Stylist", detail: "Ask for outfit advice using your current local context.")
                }
                .buttonStyle(.plain)
            }
        case .styleProgress:
            homeEngagementScroll(title: "Style Progress") {
                homeSummaryCard(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "Progress Snapshot",
                    rows: [
                        "Current score: \(latestScoreText)",
                        "Most worn signal: \(mostWornText)",
                        "\(StyleMatchHomeDisplay.countText(homeScans.count, singular: "saved scan"))",
                        "Score history opens in the existing Scan tab."
                    ]
                )
                Button {
                    selectedTab = .scan
                } label: {
                    homeDestinationRow(icon: "clock.arrow.circlepath", title: "Open Scan History", detail: "Review saved scans and compare recent outfits.")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func homeEngagementScroll<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content()
            }
            .padding()
        }
        .scrollContentBackground(.hidden)
        .appScreenBackground(.home)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func homeIntelligenceWorkspace(detail: HomeIntelligenceDetail) -> some View {
        homeEngagementScroll(title: detail.focus.title) {
            VStack(alignment: .leading, spacing: 8) {
                Label(detail.headline, systemImage: detail.focus.icon)
                    .font(.title3.weight(.bold))
                Text(detail.summary)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .appCard(.home, radius: 16)

            if !detail.facts.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("What KigoStylist knows")
                        .font(.headline)
                    ForEach(detail.facts) { fact in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: fact.evidence == .confirmed ? "checkmark.seal.fill" : fact.evidence == .inferred ? "sparkles" : "questionmark.circle.fill")
                                .foregroundStyle(fact.evidence == .confirmed ? .green : fact.evidence == .inferred ? AppTab.ai.palette.accent : .secondary)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(fact.evidence.label)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.secondary)
                                Text(fact.text)
                                    .font(.subheadline)
                            }
                        }
                    }
                }
                .padding()
                .appCard(.home, radius: 14)
            }

            if !detail.checklist.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(detail.focus == .outfitChecklist ? "Today’s checklist" : "Actionable gaps")
                        .font(.headline)
                    ForEach(detail.checklist) { item in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: checklistIcon(item.state))
                                .foregroundStyle(checklistTint(item.state))
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(item.role).font(.subheadline.weight(.bold))
                                    Spacer()
                                    Text(item.state.label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                }
                                Text(item.detail).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 3)
                    }
                }
                .padding()
                .appCard(.home, radius: 14)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("What you can do now")
                    .font(.headline)
                ForEach(detail.actions.filter { $0.priority != .notRelevantNow }) { actionPlan in
                    Button {
                        performHomeIntelligence(actionPlan.action, detail: detail)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Label(actionPlan.action.title, systemImage: actionPlan.action.icon)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(actionPlan.priority.label)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(actionPlan.priority == .recommendedNow ? AppTab.ai.palette.accent : .secondary)
                            }
                            Text(actionPlan.rationale)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .appCard(.home, radius: 14)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                    .contentShape(RoundedRectangle(cornerRadius: 14))
                    .accessibilityIdentifier("home-intelligence-action-\(detail.focus.rawValue)-\(actionPlan.action.rawValue)")
                    .accessibilityLabel(actionPlan.action.title)
                    .accessibilityHint(actionPlan.rationale)
                }
            }
            .padding(.bottom, floatingStylistClearance)
        }
    }

    private func checklistIcon(_ state: HomeIntelligenceChecklistItem.State) -> String {
        switch state {
        case .ready: "checkmark.circle.fill"
        case .needsSelection: "circle"
        case .notFoundInSavedCloset: "magnifyingglass.circle.fill"
        case .weatherRequired: "cloud.rain.fill"
        case .ppeRequired: "cross.case.fill"
        case .unknown: "questionmark.circle.fill"
        }
    }

    private func checklistTint(_ state: HomeIntelligenceChecklistItem.State) -> Color {
        switch state {
        case .ready: .green
        case .weatherRequired, .ppeRequired: AppTab.ai.palette.accent
        case .needsSelection, .notFoundInSavedCloset, .unknown: .secondary
        }
    }

    private func performHomeIntelligence(_ action: HomeIntelligenceAction, detail: HomeIntelligenceDetail) {
        switch action {
        case .viewForecast:
            selectTab(.ai)
        case .askStylist:
            onOpenHomeIntelligenceStylist(detail)
        case .buildOutfit, .openCloset:
            selectTab(.closet)
        case .openScan:
            selectTab(.scan)
        case .openShop:
            onPrepareHomeIntelligenceShopping(detail)
            selectTab(.shop)
        case .enableCalendar:
            selectTab(.profile)
        }
    }

    private func homeSummaryCard(icon: String, title: String, rows: [String]) -> some View {
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
        .appCard(.home, radius: 14)
        .accessibilityElement(children: .combine)
    }

    private func homeDestinationRow(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(AppTab.home.palette.accent)
                .frame(width: 34, height: 34)
                .background(AppTab.home.palette.accent.opacity(0.12))
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
        .appCard(.home, radius: 10)
        .contentShape(Rectangle())
    }

    private var smartNavigationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.primary.opacity(0.62))

                TextField(
                    "",
                    text: $navigationQuery,
                    prompt: Text("Search KigoStylist").foregroundColor(.primary.opacity(0.58))
                )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($navigationSearchFocused)

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
            .background(themeTokens.elevatedCardBackground.opacity(0.9))
            .clipShape(RoundedRectangle(cornerRadius: 14))

            if !navigationQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(spacing: 8) {
                    ForEach(navigationMatches.prefix(5)) { target in
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
                            .background(themeTokens.cardBackground.opacity(0.72))
                            .clipShape(RoundedRectangle(cornerRadius: 13))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var navigationMatches: [StyleMatchNavigationTarget] {
        let query = navigationQuery
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !query.isEmpty else {
            return styleMatchNavigationTargets
        }

        return styleMatchNavigationTargets
            .enumerated()
            .filter { _, target in navigationMatchRank(for: target, query: query) != nil }
            .sorted { lhs, rhs in
                let lhsRank = navigationMatchRank(for: lhs.element, query: query) ?? .max
                let rhsRank = navigationMatchRank(for: rhs.element, query: query) ?? .max
                return lhsRank == rhsRank ? lhs.offset < rhs.offset : lhsRank < rhsRank
            }
            .map(\.element)
    }

    private func navigate(to target: StyleMatchNavigationTarget) {
        navigationQuery = ""
        navigationSearchFocused = false
        selectTab(target.tab)
        if let styleFriendsRoute = target.styleFriendsRoute {
            UserDefaults.standard.set(styleFriendsRoute.rawValue, forKey: StyleFriendsHomeSearchRoute.storageKey)
        }
    }

    private func navigationMatchRank(for target: StyleMatchNavigationTarget, query: String) -> Int? {
        let title = target.title.lowercased()
        if title == query { return 0 }
        if title.hasPrefix(query) { return 1 }
        if target.keywords.contains(where: { $0.lowercased() == query }) { return 2 }
        if target.keywords.contains(where: { $0.lowercased().hasPrefix(query) }) { return 3 }
        if title.contains(query) || target.subtitle.lowercased().contains(query) { return 4 }
        if target.keywords.contains(where: { $0.lowercased().contains(query) || query.contains($0.lowercased()) }) { return 5 }
        return nil
    }

    private func selectTab(_ tab: AppTab) {
        if let onSelectTab {
            onSelectTab(tab)
            return
        }

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            selectedTab = tab
        }
    }

    private func showHomeEngagement(_ destination: HomeEngagementDestination) {
        guard homeEngagementPath.last != destination else { return }
        homeEngagementPath.append(destination)
    }

    private var dailyStyleBriefHero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("DAILY STYLE BRIEF")
                        .font(.caption2.weight(.bold))
                        .tracking(1.4)
                        .foregroundStyle(StyleMatchPremiumPalette.champagneSoft)

                    Text("\(homeGreeting) — here’s your look for today.")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(Date().formatted(date: .abbreviated, time: .omitted))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(StyleMatchPremiumPalette.mutedText)
                }

                Spacer(minLength: 8)

                if latestScan != nil {
                    VStack(spacing: 2) {
                        Text(latestScoreText)
                            .font(.system(size: 30, weight: .black, design: .rounded))
                            .foregroundStyle(StyleMatchPremiumPalette.champagneSoft)
                        Text("LAST SCAN")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(StyleMatchPremiumPalette.mutedText)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(StyleMatchPremiumPalette.border, lineWidth: 1))
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Button {
                    if dailyStyleRecommendation == nil {
                        onOpenClosetAddItem()
                    } else {
                        selectTab(.closet)
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                        Text(dailyStyleRecommendation == nil ? "Build today’s look" : "Recommended from verified Closet")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(StyleMatchPremiumPalette.mutedText)
                        Text(recommendedOutfitTitle)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        if let recommendation = dailyStyleRecommendation {
                            Label(recommendation.evidenceLabel, systemImage: "checkmark.shield.fill")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(StyleMatchPremiumPalette.champagneSoft)
                        }
                    }
                    Spacer()
                        Image(systemName: dailyStyleRecommendation == nil ? "plus.circle.fill" : "checkmark.seal.fill")
                            .font(.title2)
                            .foregroundStyle(StyleMatchPremiumPalette.champagne)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(dailyStyleRecommendation == nil ? "Add closet pieces to build a complete look" : "Open recommended Closet pieces")
                .accessibilityHint(dailyStyleRecommendation == nil ? "Opens Add Item in Closet." : "Opens Closet.")

                HStack(spacing: 10) {
                    ForEach(recommendedOutfitPieces, id: \.title) { piece in
                        Button {
                            if dailyStyleRecommendation == nil {
                                onOpenClosetAddItem()
                            } else {
                                selectTab(.closet)
                            }
                        } label: {
                            VStack(spacing: 7) {
                            Image(systemName: piece.icon)
                                .font(.headline)
                                .foregroundStyle(StyleMatchPremiumPalette.champagneSoft)
                            Text(piece.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                                .minimumScaleFactor(0.72)
                                .multilineTextAlignment(.center)
                        }
                            .frame(maxWidth: .infinity, minHeight: 78)
                            .padding(8)
                            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(dailyStyleRecommendation == nil ? "Opens Add Item in Closet." : "Opens this recommendation in Closet.")
                    }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    premiumBriefChip(icon: "cloud.sun.fill", text: homeWeatherSnapshot.chipText)
                    premiumBriefChip(icon: "calendar", text: dailyCalendarChipText)
                    if !workSetting.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        premiumBriefChip(icon: "briefcase.fill", text: workSetting)
                    } else if !dressCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        premiumBriefChip(icon: "person.fill.checkmark", text: dressCode)
                    }
                }
            }

            HStack(spacing: 10) {
                premiumBriefAction(dailyStyleRecommendation == nil ? "Build Look" : "Wear This", icon: dailyStyleRecommendation == nil ? "plus.circle.fill" : "checkmark.circle.fill") {
                    if dailyStyleRecommendation == nil {
                        onOpenClosetAddItem()
                    } else {
                        StyleMatchPremiumFeedback.success()
                        showHomeEngagement(.todayRecommendation)
                    }
                }
                premiumBriefAction(dailyStyleRecommendation == nil ? "Add Pieces" : "Swap Item", icon: dailyStyleRecommendation == nil ? "tshirt.fill" : "arrow.triangle.2.circlepath") {
                    if dailyStyleRecommendation == nil {
                        onOpenClosetAddItem()
                    } else {
                        selectTab(.closet)
                    }
                }
                premiumBriefAction("Ask Stylist", icon: "sparkles") {
                    onOpenContextualStylist()
                }
            }
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [StyleMatchPremiumPalette.ink, StyleMatchPremiumPalette.panelRaised],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: StyleMatchPremiumPalette.cornerLarge, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: StyleMatchPremiumPalette.cornerLarge, style: .continuous)
                .stroke(StyleMatchPremiumPalette.champagne.opacity(0.24), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 18, y: 10)
        .accessibilityElement(children: .contain)
    }

    private func premiumBriefChip(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.88))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.white.opacity(0.06), in: Capsule())
            .overlay(Capsule().stroke(StyleMatchPremiumPalette.border, lineWidth: 1))
    }

    private func premiumBriefAction(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        let isPrimary = title == "Wear This" || title == "Build Look"
        return Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.headline)
                Text(title)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(isPrimary ? StyleMatchPremiumPalette.ink : .white)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(
                isPrimary ? StyleMatchPremiumPalette.champagneSoft : Color.white.opacity(0.07),
                in: RoundedRectangle(cornerRadius: 15, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(isPrimary ? Color.clear : StyleMatchPremiumPalette.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint(title == "Wear This" ? "Opens today’s verified outfit brief without marking it as worn." : title == "Build Look" ? "Opens Closet so you can add the verified pieces needed for a complete look." : "Opens this styling action.")
    }

    private var premiumHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
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

            smartNavigationCard
        }
    }

    private var topStyleScoreCard: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Today's Style")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)

                Text(latestScoreText)
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Text(latestScan == nil ? "Scan an outfit to get a score" : scoreRatingTitle(for: latestScoreValue))
                    .font(.subheadline)
                    .fontWeight(.bold)

                scoreStars(for: latestScoreValue)

            }

            Spacer()

            VStack(alignment: .center, spacing: 8) {
                ZStack {
                    Circle()
                        .stroke(AppTab.ai.palette.accent.opacity(0.14), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: CGFloat(min(100, max(0, latestScoreValue))) / 100)
                        .stroke(AppTab.ai.palette.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(latestScoreText)
                        .font(.headline)
                        .fontWeight(.bold)
                }
                .frame(width: 64, height: 64)

                Text(latestScan == nil ? "No saved result" : "Latest saved result")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(14)
        .appCard(.home, radius: 16)
    }

    private var homeSnapshotChipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                WeatherStylingButton {
                    homeSignal(icon: "cloud.sun.fill", text: homeWeatherSnapshot.chipText, tint: Color(hex: 0xF5B84B))
                }
                homeStatus(icon: "person.fill.checkmark", text: outfitMoodText, tint: AppTab.closet.palette.accent)
                homeSignal(
                    icon: "tshirt.fill",
                    text: StyleMatchHomeDisplay.closetItemLabel(closetItemCount),
                    tint: AppTab.scan.palette.accent,
                    accessibilityLabel: "Open Virtual Closet, \(closetItemCount) \(closetItemCount == 1 ? "item" : "items")",
                    accessibilityHint: "Opens your saved closet items."
                ) {
                    selectedTab = .closet
                }
            }
        }
    }

    private var styleBriefCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                showHomeEngagement(.todayRecommendation)
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "sun.max.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(AppTab.home.palette.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Today's Recommendation")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("Your personal stylist checked the day before you get dressed.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Spacer()
                }
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open Today's Style Brief")
            .accessibilityHint("Opens Today's Style Brief")

            recommendedOutfitHero

            VStack(alignment: .leading, spacing: 10) {
                styleBriefRow(focus: .weather)
                styleBriefRow(focus: .calendar)
                styleBriefRow(focus: .outfitChecklist)
                styleBriefRow(focus: .laundry)
                styleBriefRow(focus: .missingPieces)
                if shouldShowShoppingBrief {
                    styleBriefRow(focus: .shopping)
                }
            }
        }
        .padding()
        .appCard(.home, radius: 16)
    }

    @ViewBuilder
    private var recommendedOutfitHero: some View {
        switch StyleMatchHomeDisplay.recommendationDestination(closetItemCount: closetItemCount) {
        case .closet:
            Button {
                selectTab(.closet)
            } label: {
                recommendedOutfitHeroContent
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add a closet piece")
            .accessibilityHint("Opens Virtual Closet")
        case nil:
            recommendedOutfitHeroContent
        }
    }

    private var recommendedOutfitHeroContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Wear this first")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)

                    Text(recommendedOutfitTitle)
                        .font(.headline)
                        .fontWeight(.bold)
                        .lineLimit(2)
                }

                Spacer()

                Text(closetItems.isEmpty ? "Closet needed" : "From your closet")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.green.opacity(0.12))
                    .clipShape(Capsule())
            }

            HStack(spacing: 10) {
                ForEach(recommendedOutfitPieces, id: \.title) { piece in
                    VStack(spacing: 8) {
                        Image(systemName: piece.icon)
                            .font(.title3)
                            .foregroundStyle(AppTab.home.palette.accent)
                            .frame(width: 42, height: 42)
                            .background(AppTab.home.palette.accent.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                        Text(piece.title)
                            .font(.caption)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.72)
                    }
                    .frame(maxWidth: .infinity, minHeight: 92)
                    .padding(10)
                    .background(themeTokens.cardBackground.opacity(0.7))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
        }
        .padding(14)
        .background(themeTokens.elevatedCardBackground.opacity(0.52))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func styleBriefRow(focus: HomeIntelligenceFocus) -> some View {
        let detail = homeIntelligenceDetails[focus] ?? HomeIntelligenceAuthority.detail(for: focus, input: homeIntelligenceInput)
        return Button {
            showHomeEngagement(.intelligence(focus))
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: focus.icon)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(AppTab.home.palette.accent)
                    .frame(width: 28, height: 28)
                    .background(AppTab.home.palette.accent.opacity(0.12))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(focus.title)
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)

                    Text(detail.summary)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityHint("Opens detail")
    }

    private var personalStylistDashboard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                showHomeEngagement(.aiStylistLearning)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.title2)
                        .foregroundStyle(AppTab.ai.palette.accent)
                        .frame(width: 44, height: 44)
                        .background(AppTab.ai.palette.accent.opacity(0.14))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("AI Personal Stylist")
                            .font(.title3)
                            .fontWeight(.bold)

                        Text(aiDailySummary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open AI stylist learning details")
            .accessibilityHint("Opens AI stylist learning details")

            AIStyleInsightCard(
                tab: .home,
                screen: "Home",
                title: "Morning Brief",
                prompt: "Give me one warm, respectful style move I should make today using my closet, profile, weather, sizes, and recent scans.",
                fallbackAdvice: "Build around your saved closet first, then shop only for pieces that complete multiple outfits.",
                extraContext: "The customer is deciding where to start."
            )

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Learning Progress")
                        .font(.headline)

                    Spacer()

                    Text("\(learningProgressPercent)%")
                        .font(.headline)
                        .fontWeight(.bold)
                }

                ProgressView(value: Double(learningProgressPercent), total: 100)
                    .tint(AppTab.ai.palette.accent)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    aiMemoryItem(title: "Favorite Fit", value: favoriteFitText)
                    aiMemoryItem(title: "Budget", value: budgetLevelText)
                    aiMemoryItem(title: "Brands", value: favoriteBrandListText)
                }
            }

            Button {
                onOpenContextualStylist()
            } label: {
                Label("Chat with Stylist", systemImage: "bubble.left.and.bubble.right.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTab.ai.palette.accent)
        }
        .padding()
        .appCard(.home, radius: 16)
    }

    private var outfitHistorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Outfit History", systemImage: "clock.arrow.circlepath")
                    .font(.title2)
                    .fontWeight(.bold)
                    .accessibilityAddTraits(.isHeader)

                Spacer()

                Button("See All") {
                    selectedTab = .scan
                }
                .font(.subheadline)
                .fontWeight(.bold)
            }

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField(
                    "",
                    text: $outfitHistoryQuery,
                    prompt: Text("Search outfit history").foregroundColor(.secondary)
                )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .padding(12)
            .background(themeTokens.cardBackground.opacity(0.78))
            .clipShape(RoundedRectangle(cornerRadius: 14))

            if filteredHomeScans.isEmpty {
                Text(homeScans.isEmpty ? "Scan your first outfit to start building history." : "No matching outfits yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(themeTokens.elevatedCardBackground.opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            } else {
                VStack(spacing: 10) {
                    ForEach(filteredHomeScans.prefix(3)) { scan in
                        homeHistoryRow(scan)
                    }
                }
            }
        }
    }

    private func homeHistoryRow(_ scan: HomeStoredScan) -> some View {
        Button {
            selectedTab = .scan
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(AppTab.scan.palette.accent.opacity(0.14))
                    Image(systemName: "photo")
                        .font(.title3)
                        .foregroundStyle(AppTab.scan.palette.accent)
                }
                .frame(width: 54, height: 54)

                VStack(alignment: .leading, spacing: 4) {
                    Text(scan.displayTitle)
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text("\(scan.dateText) • \(scan.styleContextText)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(scan.score)")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(AppTab.ai.palette.accent)
                    Text(StyleMatchHomeDisplay.scoreBand(for: scan.score).title)
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(Color(.systemBackground).opacity(0.86))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private var styleProgressCard: some View {
        Button {
            showHomeEngagement(.styleProgress)
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Style Progress", systemImage: "chart.line.uptrend.xyaxis")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)

                    Spacer()

                    Text(StyleMatchHomeDisplay.countText(homeScans.count, singular: "saved scan"))
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.green.opacity(0.12))
                        .clipShape(Capsule())
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    progressMetric(title: "Latest Score", value: latestScoreText, icon: "star.fill", tint: AppTab.ai.palette.accent)
                    progressMetric(title: "Most Worn", value: mostWornText, icon: "shoe.2.fill", tint: Color(hex: 0x5B57D6))
                }
            }
            .padding()
            .appCard(.home, radius: 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open style progress")
        .accessibilityHint("Opens style progress")
    }

    private func progressMetric(title: String, value: String, icon: String, tint: Color) -> some View {
        Button {
            showHomeEngagement(.styleProgress)
        } label: {
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
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
            }
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            .padding(12)
            .background(themeTokens.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel("\(title), \(value)")
    }

    private var aiDailySummary: String {
        let outfit = closetItemsToWearText.hasPrefix("Add closet pieces") ? "a clean casual base" : closetItemsToWearText
        return "\(homeWeatherSnapshot.chipText) and \(outfitMoodText.lowercased()) today. Start with \(outfit)."
    }

    private var learningProgressPercent: Int {
        min(98, 45 + min(closetItemCount * 8, 24) + min(homeScans.count * 5, 24) + (favoriteBrandListText == "Add brands" ? 0 : 5))
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
            .appCard(.home, radius: 16)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func homeSignal(
        icon: String,
        text: String,
        tint: Color,
        accessibilityLabel: String? = nil,
        accessibilityHint: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        let content = HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.14))
                .clipShape(Circle())
                .accessibilityHidden(true)

            Text(text)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.78)

            Spacer()
        }
        .frame(width: 190, height: 58, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(themeTokens.cardBackground.opacity(0.78))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .contentShape(Rectangle())

        if let action {
            Button(action: action) {
                content
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel ?? text)
            .accessibilityHint(accessibilityHint ?? "")
            .accessibilityAddTraits(.isButton)
        } else {
            content
        }
    }

    private func homeStatus(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.14))
                .clipShape(Circle())
                .accessibilityHidden(true)

            Text(text)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.78)

            Spacer()
        }
        .frame(width: 190, alignment: .leading)
        .frame(minHeight: 58, alignment: .leading)
        .padding(.horizontal, 12)
        .accessibilityElement(children: .combine)
    }

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.title2)
                .fontWeight(.bold)
                .accessibilityAddTraits(.isHeader)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                quickAction(icon: "camera.viewfinder", title: "Analyze", tab: .scan, tint: AppTab.scan.palette.accent)
                quickAction(icon: "tshirt.fill", title: "Closet", tab: .closet, tint: AppTab.closet.palette.accent)
                quickAction(icon: "sparkles", title: "Ask AI", tab: .ai, tint: AppTab.ai.palette.accent)
                quickAction(icon: "bag.fill", title: "Shop", tab: .shop, tint: AppTab.shop.palette.accent)
                quickAction(icon: "heart.fill", title: "Favorites", tab: .scan, tint: .pink)
                quickAction(
                    icon: "clock.fill",
                    title: "History",
                    tab: .scan,
                    tint: Color(hex: 0x5B57D6),
                    accessibilityHint: "Opens recent outfit scores and saved scan history.",
                    action: onOpenScanHistory
                )
            }
        }
    }

    private func quickAction(
        icon: String,
        title: String,
        tab: AppTab,
        tint: Color,
        accessibilityHint: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        let resolvedAction = action ?? { selectTab(tab) }

        return Button(action: resolvedAction) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(tint)
                    .frame(width: 42, height: 42)
                    .background(tint.opacity(0.14))
                    .clipShape(Circle())
                    .accessibilityHidden(true)

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
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(minHeight: 74)
        .padding(.horizontal, 14)
        .appCard(.home, radius: 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityHint(accessibilityHint ?? "Opens the \(title) tab")
    }

    private var greeting: String {
        LocalDateContext().timeBucket.greetingTitle
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
            return "No scans yet"
        }

        return "\(latestScan.score)"
    }

    private var latestScoreValue: Int {
        Int(latestScoreText) ?? 0
    }

    private func scoreRatingTitle(for score: Int) -> String {
        StyleMatchHomeDisplay.scoreBand(for: score).title
    }

    private func scoreStars(for score: Int) -> some View {
        let filledStars = StyleMatchHomeDisplay.scoreBand(for: score).stars

        return HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { index in
                Image(systemName: StyleMatchHomeDisplay.starSystemName(index: index, for: score))
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
        weatherAuthority.snapshot?.condition ?? "Weather unavailable"
    }

    private var homeWeatherSnapshot: HomeWeatherSnapshot {
        HomeWeatherSnapshot(condition: weatherConditionText, temperature: weatherTemperatureText)
    }

    private var homeCalendarAuthorizationIsAvailable: Bool {
        guard CalendarContextConsentStore.isEnabled() else { return false }
        let status = EventKitCalendarContextAccess().authorizationStatus
        if #available(iOS 17.0, macOS 14.0, *) {
            return status == .fullAccess
        }
        return status == .authorized
    }

    private var homeCalendarProjections: [CalendarContextProjection] {
        _ = calendarContextRefreshID
        guard homeCalendarAuthorizationIsAvailable else { return [] }
        let access = EventKitCalendarContextAccess()
        let now = Date()
        let range = CalendarContextWindow.range(from: now)
        // The shared EventKit pipeline is intentionally bounded and returns
        // only minimized projections. It retains unrecognized, nonempty
        // upcoming events as `otherSignificantEvent` instead of misleadingly
        // reporting that no event exists.
        guard let events = try? access.events(from: range.start, to: range.end) else { return [] }
        return CalendarContextBatch.make(events: events, now: now).projections
            .prefix(3)
            .map { $0 }
    }

    private var homeCalendarProjection: CalendarContextProjection? {
        homeCalendarProjections.first
    }

    private var homeIntelligenceInput: HomeIntelligenceInput {
        HomeIntelligenceInput(
            weather: weatherAuthority.snapshot,
            calendar: homeCalendarProjection,
            calendarEvents: homeCalendarProjections,
            calendarAuthorized: homeCalendarAuthorizationIsAvailable,
            plannedOccasion: plannedOccasion,
            dressCode: dressCode,
            workplace: workSetting,
            closetItems: closetItems.map {
                HomeIntelligenceInput.ClosetItem(
                    category: $0.category,
                    name: StyleMatchHomeDisplay.sanitizedClosetItemLabel(name: $0.name, color: $0.color, userName: profileName) ?? $0.name
                )
            },
            savedScanCount: homeScans.count,
            savedShoppingCount: wishlistCount
        )
    }

    private var homeIntelligenceDetails: [HomeIntelligenceFocus: HomeIntelligenceDetail] {
        HomeIntelligenceAuthority.make(input: homeIntelligenceInput)
    }

    private var calendarBriefText: String {
        let event = plannedOccasion.trimmingCharacters(in: .whitespacesAndNewlines)
        let code = dressCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedEvent = event.isEmpty ? "No calendar access yet" : event
        let resolvedCode = code.isEmpty ? "No dress code saved" : code
        return "\(resolvedEvent), \(resolvedCode)"
    }

    private var dailyCalendarChipText: String {
        let event = plannedOccasion.trimmingCharacters(in: .whitespacesAndNewlines)
        if !event.isEmpty { return event }
        return homeCalendarAuthorizationIsAvailable ? "No occasion today" : "Calendar off"
    }

    private var dailyStyleRecommendation: DailyStyleRecommendation? {
        DailyStyleRecommendationEngine.recommend(
            items: closetItems,
            temperatureFahrenheit: weatherAuthority.snapshot?.temperatureFahrenheit,
            condition: weatherAuthority.snapshot?.condition,
            occasion: plannedOccasion,
            dressCode: dressCode,
            workSetting: workSetting
        )
    }

    private var dailyRecommendedItems: [ClosetItem] {
        guard let recommendation = dailyStyleRecommendation else { return [] }
        return recommendation.itemIDs.compactMap { id in
            closetItems.first(where: { $0.id == id })
        }
    }

    private var closetItemsToWearText: String {
        let names = dailyRecommendedItems.map(\.shortHomeTitle).filter { !$0.isEmpty }
        return names.isEmpty ? "Add verified closet pieces to build a complete outfit." : names.joined(separator: ", ")
    }

    private var recommendedOutfitBriefText: String {
        closetItemsToWearText
    }

    private var recommendedOutfitTitle: String {
        dailyStyleRecommendation?.title ?? "Add closet pieces to build a complete look"
    }

    private var recommendedOutfitPieces: [RecommendedOutfitPiece] {
        let pieces = dailyRecommendedItems.map { item in
            RecommendedOutfitPiece(title: item.shortHomeTitle, icon: item.homeIconName)
        }
        return pieces.isEmpty
            ? [RecommendedOutfitPiece(title: "Add a closet piece", icon: "plus.circle.fill")]
            : pieces
    }

    private var laundryBriefText: String {
        let whiteItems = closetItems.filter { item in
            item.color.localizedCaseInsensitiveContains("white") || item.name.localizedCaseInsensitiveContains("white")
        }.count
        let gymItems = closetItems.filter { $0.occasion.localizedCaseInsensitiveContains("gym") }.count
        let count = whiteItems + gymItems

        if count > 0 {
            return "Check \(StyleMatchHomeDisplay.countText(count, singular: "light or gym item")) before wearing."
        }

        return "No laundry cues from your saved closet."
    }

    private var missingPieceText: String {
        let required = DailyStyleRecommendationEngine.missingRequirements(items: closetItems, dressCode: dressCode, workSetting: workSetting)
        if !required.isEmpty {
            return "Add \(required.joined(separator: ", "))."
        }

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

        return hasAccessories ? "No obvious gap in saved items." : "No accessories are saved yet."
    }

    private var shouldShowShoppingBrief: Bool {
        missingPieceText != "No obvious gap in saved items." || wishlistCount > 0
    }

    private var shoppingBriefText: String {
        if wishlistCount > 0 {
            return "Review \(StyleMatchHomeDisplay.countText(wishlistCount, singular: "saved item")) before buying anything new."
        }

        return missingPieceText == "No obvious gap in saved items." ? "No shopping need found in saved items." : "Review your saved items before shopping."
    }

    private var weatherTemperatureText: String {
        guard let snapshot = weatherAuthority.snapshot else { return "Weather unavailable" }
        return "\(snapshot.temperatureFahrenheit)°F"
    }

    private var outfitMoodText: String {
        let savedOccasion = plannedOccasion.trimmingCharacters(in: .whitespacesAndNewlines)
        let savedDressCode = dressCode.trimmingCharacters(in: .whitespacesAndNewlines)

        if !savedOccasion.isEmpty && savedOccasion != "Work" {
            return savedOccasion
        }

        return savedDressCode.isEmpty ? "No occasion saved" : savedDressCode
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

        return savedColor ?? "Not set"
    }

    private var favoriteFitText: String {
        let trimmed = fitPreference.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Not set" : trimmed
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
        return "Not set"
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

        return brands.isEmpty ? "Add brands" : brands.joined(separator: "\n")
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

        return favoriteColorText
    }

    private var homeScans: [HomeStoredScan] {
        guard !outfitScanHistoryData.isEmpty,
              let history = try? JSONDecoder().decode([String: HomeStoredScan].self, from: outfitScanHistoryData) else {
            return []
        }

        return history.values.sorted { $0.firstScannedAt > $1.firstScannedAt }
    }

    private var filteredHomeScans: [HomeStoredScan] {
        let query = outfitHistoryQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return homeScans }
        return homeScans.filter { scan in
            scan.displayTitle.lowercased().contains(query)
            || scan.styleContextText.lowercased().contains(query)
        }
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
                detail: "You have \(StyleMatchHomeDisplay.countText(wishlistCount, singular: "saved item")) waiting in Smart Shopping.",
                icon: "bag.fill",
                tint: AppTab.shop.palette.accent,
                tab: .shop
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
    let analysis: OutfitAnalysisResult?
    let firstScannedAt: Date
    let customTitle: String?

    private enum CodingKeys: String, CodingKey {
        case score
        case analysis
        case firstScannedAt
        case customTitle
    }

    var id: String {
        "\(Int(firstScannedAt.timeIntervalSince1970))-\(score)-\(displayTitle)"
    }

    var displayTitle: String {
        if let customTitle,
           !customTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return customTitle
        }

        if let analysis {
            let text = searchableText(for: analysis)
            let color = analysis.colorPalette
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).capitalized }
                .first { !$0.isEmpty && !["Neutral", "Dark", "Light", "Color", "Colors"].contains($0) }

            if text.contains("polo") {
                return [color, "Polo Outfit"].compactMap { $0 }.joined(separator: " ")
            }
            if text.contains("dress") {
                return [color, "Dress Outfit"].compactMap { $0 }.joined(separator: " ")
            }
            if text.contains("jacket") || text.contains("blazer") {
                return [color, "Layered Outfit"].compactMap { $0 }.joined(separator: " ")
            }
            if text.contains("pajama") || text.contains("robe") || text.contains("sleepwear") {
                return "Cozy Sleepwear"
            }
            if text.contains("business") || text.contains("office") || text.contains("work") {
                return [color, "Work Outfit"].compactMap { $0 }.joined(separator: " ")
            }
            if let color {
                return "\(color) Outfit"
            }
        }

        return "Saved Outfit"
    }

    var styleContextText: String {
        guard let analysis else { return "Style scan" }
        let text = searchableText(for: analysis)
        if text.contains("sleepwear") || text.contains("pajama") || text.contains("robe") {
            return "Loungewear"
        }
        if text.contains("business") || text.contains("office") || text.contains("work") {
            return "Business Casual"
        }
        if text.contains("date") || text.contains("dinner") {
            return "Date Night"
        }
        if text.contains("gym") || text.contains("workout") {
            return "Gym"
        }
        if text.contains("formal") || text.contains("wedding") {
            return "Formal"
        }
        if text.contains("casual") || text.contains("jeans") || text.contains("sneaker") {
            return "Casual"
        }

        let occasion = analysis.occasionFit.trimmingCharacters(in: .whitespacesAndNewlines)
        return occasion.isEmpty ? "Style scan" : occasion
    }

    var dateText: String {
        Self.dateFormatter.string(from: firstScannedAt)
    }

    private func searchableText(for analysis: OutfitAnalysisResult) -> String {
        (
            analysis.outfitDescription + " " +
            analysis.detectedClothingItems.joined(separator: " ") + " " +
            analysis.environment + " " +
            analysis.occasionFit + " " +
            analysis.formality + " " +
            analysis.seasonalMatch + " " +
            analysis.summary
        ).lowercased()
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()
}

private struct HomeContinueTask {
    let title: String
    let detail: String
    let icon: String
    let tint: Color
    let tab: AppTab
}

private struct RecommendedOutfitPiece {
    let title: String
    let icon: String
}

private extension ClosetItem {
    var shortHomeTitle: String {
        let nameText = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let categoryText = category.trimmingCharacters(in: .whitespacesAndNewlines)
        let colorText = color.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = nameText.isEmpty ? categoryText : nameText

        if !colorText.isEmpty,
           !base.localizedCaseInsensitiveContains(colorText) {
            return "\(colorText) \(base)"
        }

        return base.isEmpty ? "Closet Piece" : base
    }

    var homeIconName: String {
        let text = "\(category) \(name)".lowercased()
        if text.contains("shoe") || text.contains("sneaker") || text.contains("boot") {
            return "shoe.2.fill"
        }
        if text.contains("pant") || text.contains("jean") || text.contains("chino") {
            return "figure.stand"
        }
        if text.contains("jacket") || text.contains("coat") || text.contains("blazer") {
            return "jacket.fill"
        }
        if text.contains("dress") {
            return "figure.dress.line.vertical.figure"
        }
        return "tshirt.fill"
    }
}

private struct HomeWeatherSnapshot {
    let condition: String
    let temperature: String

    var chipText: String {
        "\(temperature) \(condition)"
    }

    var briefText: String {
        "\(condition), \(temperature)"
    }
}

private struct HomeOutfitFeedbackCard: View {
    let prompt: ScheduledFeedbackPrompt
    let onWornAnswer: (ScheduledFeedbackPrompt, Bool) -> Void
    let onLikedAnswer: (ScheduledFeedbackPrompt, Bool) -> Void
    let onDislikeReason: (ScheduledFeedbackPrompt, DislikeReason) -> Void
    let onDismissPrompt: () -> Void
    let onComplete: () -> Void

    @State private var step: Step = .worn
    @State private var isComplete = false

    private enum Step {
        case worn
        case liked
        case reason
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "checkmark.bubble.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(AppTab.home.palette.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Quick style check")
                        .font(.headline)
                        .fontWeight(.bold)

                    Text(isComplete ? "Thanks - this improves your recommendations." : "Saved outfit: \(prompt.scoreSummary)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Button(action: onDismissPrompt) {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(Color.primary.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss feedback prompt")
            }

            if isComplete {
                Label("Feedback saved", systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.green)
                    .padding(.vertical, 6)
            } else {
                switch step {
                case .worn:
                    Text("Did you end up wearing this outfit?")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    HStack(spacing: 10) {
                        feedbackButton("Yes", icon: "checkmark.circle.fill") {
                            onWornAnswer(prompt, true)
                            withAnimation(.snappy) {
                                step = .liked
                            }
                        }
                        feedbackButton("No", icon: "xmark.circle.fill") {
                            onWornAnswer(prompt, false)
                            complete()
                        }
                    }

                case .liked:
                    Text("How did it work out?")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    HStack(spacing: 10) {
                        feedbackButton("Loved it", icon: "hand.thumbsup.fill") {
                            onLikedAnswer(prompt, true)
                            complete()
                        }
                        feedbackButton("Not for me", icon: "hand.thumbsdown.fill") {
                            onLikedAnswer(prompt, false)
                            withAnimation(.snappy) {
                                step = .reason
                            }
                        }
                    }

                case .reason:
                    Text("What was off?")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                        ForEach(DislikeReason.allCases, id: \.self) { reason in
                            Button(reason.displayName) {
                                onDislikeReason(prompt, reason)
                                complete()
                            }
                            .font(.caption)
                            .fontWeight(.bold)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .foregroundStyle(AppTab.home.palette.accent)
                            .background(AppTab.home.palette.accent.opacity(0.12))
                            .clipShape(Capsule())
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(16)
        .appCard(.home, radius: 20)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func feedbackButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .foregroundStyle(.white)
                .background(AppTab.home.palette.accent)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private func complete() {
        withAnimation(.snappy) {
            isComplete = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            onComplete()
        }
    }
}

extension HomeStoredScan: Identifiable {}
