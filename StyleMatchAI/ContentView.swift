import CoreLocation
import SwiftUI
import WeatherKit

enum AppTab: Hashable {
    case home
    case scan
    case closet
    case shop
    case ai
    case profile
}

struct AppPalette {
    let start: Color
    let middle: Color
    let end: Color
    let accent: Color
    let card: Color
}

extension AppTab {
    var palette: AppPalette {
        switch self {
        case .home:
            return AppPalette(
                start: Color(hex: 0x071A56),
                middle: Color(hex: 0x0277E8),
                end: Color(hex: 0x18D8FF),
                accent: Color(hex: 0x00C8FF),
                card: Color(.systemBackground)
            )
        case .scan:
            return AppPalette(
                start: Color(hex: 0x0F1022),
                middle: Color(hex: 0x2B2459),
                end: Color(hex: 0xEED9B5),
                accent: Color(hex: 0xEED9B5),
                card: Color(.systemBackground)
            )
        case .closet:
            return AppPalette(
                start: Color(hex: 0x023B38),
                middle: Color(hex: 0x00A86B),
                end: Color(hex: 0x7EE2A8),
                accent: Color(hex: 0x00B978),
                card: Color(.systemBackground)
            )
        case .shop:
            return AppPalette(
                start: Color(hex: 0x421400),
                middle: Color(hex: 0xE85D04),
                end: Color(hex: 0xFFCF70),
                accent: Color(hex: 0xF77F00),
                card: Color(.systemBackground)
            )
        case .ai:
            return AppPalette(
                start: Color(hex: 0x16002E),
                middle: Color(hex: 0x673AB7),
                end: Color(hex: 0x00B8D9),
                accent: Color(hex: 0x7C4DFF),
                card: Color(.systemBackground)
            )
        case .profile:
            return AppPalette(
                start: Color(hex: 0x4B1139),
                middle: Color(hex: 0xC2185B),
                end: Color(hex: 0xFFC1E3),
                accent: Color(hex: 0xD81B60),
                card: Color(.systemBackground)
            )
        }
    }
}

extension Color {
    init(hex: UInt, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

private struct AppScreenBackground: ViewModifier {
    let tab: AppTab
    @AppStorage("selectedAppTheme") private var selectedAppTheme = StyleMatchAppTheme.system.rawValue
    @AppStorage("selectedThemeIntensity") private var selectedThemeIntensity = 0.42

    func body(content: Content) -> some View {
        let activeTheme = StyleMatchAppTheme(rawValue: selectedAppTheme) ?? .system
        let activePalette = activeTheme.palette(for: tab)
        let intensity = max(0.18, min(selectedThemeIntensity, 0.82))

        content
            .background(
                ZStack {
                    if activeTheme == .blackAMOLED {
                        Color.black
                    } else {
                        activePalette.start.opacity(0.08 + intensity * 0.12)
                        LinearGradient(
                            colors: [
                                activePalette.start.opacity(0.14 + intensity * 0.22),
                                activePalette.middle.opacity(0.08 + intensity * 0.16),
                                activePalette.end.opacity(0.10 + intensity * 0.18)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
                }
                    .ignoresSafeArea()
            )
            .tint(activePalette.accent)
    }
}

private struct AppCardBackground: ViewModifier {
    let tab: AppTab
    let radius: CGFloat
    @AppStorage("selectedAppTheme") private var selectedAppTheme = StyleMatchAppTheme.system.rawValue
    @AppStorage("selectedThemeIntensity") private var selectedThemeIntensity = 0.42

    func body(content: Content) -> some View {
        let activeTheme = StyleMatchAppTheme(rawValue: selectedAppTheme) ?? .system
        let activePalette = activeTheme.palette(for: tab)
        let intensity = max(0.18, min(selectedThemeIntensity, 0.82))

        content
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: radius)
                        .fill(activeTheme == .blackAMOLED ? Color(hex: 0x080808) : Color(.systemBackground))
                    RoundedRectangle(cornerRadius: radius)
                        .fill(activePalette.accent.opacity(0.04 + intensity * 0.10))
                    RoundedRectangle(cornerRadius: radius)
                        .fill(activePalette.start.opacity(0.02 + intensity * 0.04))
                }
            )
            .foregroundStyle(.primary)
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .stroke(activePalette.accent.opacity(0.22 + intensity * 0.34), lineWidth: 1)
            )
            .shadow(color: activePalette.accent.opacity(0.04 + intensity * 0.12), radius: 12, x: 0, y: 6)
    }
}

struct PageColorBand: View {
    let tab: AppTab
    let title: String
    let subtitle: String
    let icon: String
    @AppStorage("selectedAppTheme") private var selectedAppTheme = StyleMatchAppTheme.system.rawValue
    @AppStorage("selectedThemeIntensity") private var selectedThemeIntensity = 0.42

    var body: some View {
        let activeTheme = StyleMatchAppTheme(rawValue: selectedAppTheme) ?? .system
        let activePalette = activeTheme.palette(for: tab)
        let intensity = max(0.18, min(selectedThemeIntensity, 0.82))

        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(activePalette.accent.opacity(0.95))
                .clipShape(RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding()
        .background(
            ZStack(
                alignment: .center
            ) {
                if activeTheme == .blackAMOLED {
                    Color(hex: 0x080808)
                } else {
                    LinearGradient(
                        colors: [activePalette.accent.opacity(0.10 + intensity * 0.18), activePalette.end.opacity(0.08 + intensity * 0.16)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }
            }
            )
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(activePalette.accent.opacity(0.24 + intensity * 0.32), lineWidth: 1)
        )
    }
}

extension View {
    func appScreenBackground(_ tab: AppTab) -> some View {
        modifier(AppScreenBackground(tab: tab))
    }

    func appCard(_ tab: AppTab, radius: CGFloat = 16) -> some View {
        modifier(AppCardBackground(tab: tab, radius: radius))
    }
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: AppTab = .home
    @StateObject private var liveWeather = StyleMatchLiveWeatherManager()
    @StateObject private var outfitMemoryStore = OutfitMemoryStore()
    @State private var pendingFeedbackPrompt: ScheduledFeedbackPrompt?
    @State private var hasShownFeedbackPromptThisSession = false
    @State private var shoppingSaleUnreadCount = 0
    @AppStorage("selectedAppTheme") private var selectedAppTheme = StyleMatchAppTheme.system.rawValue

    private var activeTheme: StyleMatchAppTheme {
        StyleMatchAppTheme(rawValue: selectedAppTheme) ?? .system
    }

    var body: some View {
        activeScreen
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomNavigation
            }
        .tint(activeTheme.palette(for: selectedTab).accent)
        .preferredColorScheme(activeTheme.preferredColorScheme)
        .onAppear {
            applyProfileDefaults()
            liveWeather.refresh()
            checkForPendingFeedbackPrompt()
            refreshSaleWatcher()
        }
        .styleMatchOnChange(of: scenePhase) { phase in
            if phase == .active {
                checkForPendingFeedbackPrompt()
                refreshSaleWatcher()
            } else if phase == .background || phase == .inactive {
                dismissActiveFeedbackPrompt()
            }
        }
        .styleMatchOnChange(of: selectedTab) { tab in
            if tab == .home {
                checkForPendingFeedbackPrompt()
            } else {
                dismissActiveFeedbackPrompt()
            }
        }
    }

    @ViewBuilder
    private var activeScreen: some View {
        ZStack {
            preservedTab(.home) {
                SafeHomeView(
                    selectedTab: $selectedTab,
                    feedbackPrompt: pendingFeedbackPrompt,
                    onHomeAppear: checkForPendingFeedbackPrompt,
                    onFeedbackWornAnswer: answerFeedbackWorn,
                    onFeedbackLikedAnswer: answerFeedbackLiked,
                    onFeedbackDislikeReason: answerFeedbackDislikeReason,
                    onFeedbackDismiss: dismissActiveFeedbackPrompt,
                    onFeedbackComplete: clearActiveFeedbackPrompt
                )
            }

            preservedTab(.scan) {
                ScanView(selectedTab: $selectedTab)
            }

            preservedTab(.closet) {
                ClosetView(selectedTab: $selectedTab)
            }

            preservedTab(.shop) {
                if ShoppingTabVisibility.shouldShowShoppingTab() {
                    ShoppingView(selectedTab: $selectedTab)
                } else {
                    SafeHomeView(selectedTab: $selectedTab)
                }
            }

            preservedTab(.ai) {
                if FeatureFlags.conversationalStylist {
                    StylistChatView()
                } else {
                    StableAIFallbackView(selectedTab: $selectedTab)
                }
            }

            preservedTab(.profile) {
                ProfileView(selectedTab: $selectedTab)
            }
        }
    }

    private func preservedTab<Content: View>(_ tab: AppTab, @ViewBuilder content: () -> Content) -> some View {
        content()
            .opacity(selectedTab == tab ? 1 : 0)
            .allowsHitTesting(selectedTab == tab)
            .accessibilityHidden(selectedTab != tab)
    }

    private func checkForPendingFeedbackPrompt() {
        guard !hasShownFeedbackPromptThisSession else {
            return
        }

        guard selectedTab == .home, pendingFeedbackPrompt == nil else {
            return
        }

        let scheduler = FeedbackPromptScheduler(store: outfitMemoryStore)
        guard let memory = scheduler.nextPromptCandidate() else { return }
        let prompt = ScheduledFeedbackPrompt(id: memory.id, memory: memory)
        scheduler.recordPromptShown(for: memory.id)
        hasShownFeedbackPromptThisSession = true
        pendingFeedbackPrompt = prompt
    }

    private func answerFeedbackWorn(
        for prompt: ScheduledFeedbackPrompt,
        wasWorn: Bool
    ) {
        outfitMemoryStore.recordWornAnswer(for: prompt.id, wasWorn: wasWorn)
    }

    private func answerFeedbackLiked(
        for prompt: ScheduledFeedbackPrompt,
        wasLiked: Bool
    ) {
        outfitMemoryStore.recordLikedAnswer(for: prompt.id, wasLiked: wasLiked)
    }

    private func answerFeedbackDislikeReason(
        for prompt: ScheduledFeedbackPrompt,
        reason: DislikeReason
    ) {
        outfitMemoryStore.recordDislikeReason(for: prompt.id, reason: reason)
    }

    private func dismissActiveFeedbackPrompt() {
        guard let prompt = pendingFeedbackPrompt else { return }
        outfitMemoryStore.dismissFeedbackPrompt(for: prompt.id)
        pendingFeedbackPrompt = nil
    }

    private func clearActiveFeedbackPrompt() {
        pendingFeedbackPrompt = nil
    }

    private var bottomNavigation: some View {
        HStack(spacing: 6) {
            bottomTab(.home, title: "Home", icon: "house.fill")
            bottomTab(.scan, title: "Scan", icon: "camera.viewfinder")
            bottomTab(.closet, title: "Closet", icon: "tshirt.fill")
            if ShoppingTabVisibility.shouldShowShoppingTab() {
                bottomTab(.shop, title: "Shop", icon: "bag.fill", badgeCount: shoppingSaleUnreadCount)
            }
            bottomTab(.ai, title: "AI", icon: "sparkles")
            bottomTab(.profile, title: "Profile", icon: "person.crop.circle.fill")
        }
        .padding(.horizontal, 8)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    private func bottomTab(_ tab: AppTab, title: String, icon: String, badgeCount: Int = 0) -> some View {
        let isSelected = selectedTab == tab
        let selectedPalette = activeTheme.palette(for: tab)

        return Button {
            guard selectedTab != tab else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: icon)
                        .font(.system(size: 19, weight: .semibold))
                        .frame(height: 24)
                    if badgeCount > 0 {
                        Text("\(min(badgeCount, 9))")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 15, height: 15)
                            .background(Color.red)
                            .clipShape(Circle())
                            .offset(x: 11, y: -6)
                    }
                }

                Text(title)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)
            }
            .foregroundStyle(isSelected ? selectedPalette.accent : Color.secondary)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(isSelected ? selectedPalette.accent.opacity(0.16) : Color.clear)
            )
            .shadow(color: isSelected ? selectedPalette.accent.opacity(0.18) : Color.clear, radius: 6, x: 0, y: 0)
        }
        .buttonStyle(.plain)
        .zIndex(isSelected ? 1 : 0)
    }

    private func applyProfileDefaults() {
        let savedSize = UserDefaults.standard.string(forKey: "sizeProfile") ?? ""
        guard !savedSize.localizedCaseInsensitiveContains("24W-60W")
                || !savedSize.localizedCaseInsensitiveContains("XXS-8XL") else {
            return
        }

        UserDefaults.standard.set(
            "Pants: 24W-60W x 26L-40L, saved 36W x 36L; Shirts: XXS-8XL; Shoes: 5-18; Fit: slim, straight, relaxed, curvy, petite, tall",
            forKey: "sizeProfile"
        )
    }

    private func refreshSaleWatcher() {
        Task {
            _ = await SaleWatcher().checkForNewSales()
            let unread = SaleWatcher().unreadSaleEventCount()
            await MainActor.run {
                shoppingSaleUnreadCount = unread
            }
        }
    }
}

private struct OutfitFeedbackCard: View {
    let prompt: ScheduledFeedbackPrompt
    let onWornAnswer: (ScheduledFeedbackPrompt, Bool) -> Void
    let onLikedAnswer: (ScheduledFeedbackPrompt, Bool) -> Void
    let onDislikeReason: (ScheduledFeedbackPrompt, DislikeReason) -> Void
    let onDismissPrompt: () -> Void
    let onComplete: () -> Void

    @State private var step: FeedbackStep = .worn
    @State private var isComplete = false

    private enum FeedbackStep {
        case worn
        case liked
        case reason
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "checkmark.bubble.fill")
                    .font(.title2)
                    .foregroundStyle(Color(hex: 0xEED9B5))
                    .frame(width: 52, height: 52)
                    .background(Color(hex: 0x11101E))
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                VStack(alignment: .leading, spacing: 6) {
                    Text("Quick style check")
                        .font(.headline)
                        .fontWeight(.bold)

                    Text(isComplete ? "Thanks - this improves your recommendations." : "Saved outfit: \(prompt.scoreSummary)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    onDismissPrompt()
                } label: {
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
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 10) {
                    switch step {
                    case .worn:
                        Text("Did you end up wearing this outfit?")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        HStack(spacing: 10) {
                            feedbackActionButton(title: "Yes", icon: "checkmark.circle.fill") {
                                onWornAnswer(prompt, true)
                                withAnimation(.snappy) {
                                    step = .liked
                                }
                            }

                            feedbackActionButton(title: "No", icon: "xmark.circle.fill") {
                                onWornAnswer(prompt, false)
                                complete()
                            }
                        }

                    case .liked:
                        Text("How did it work out?")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        HStack(spacing: 10) {
                            feedbackActionButton(title: "Loved it", icon: "hand.thumbsup.fill") {
                                onLikedAnswer(prompt, true)
                                complete()
                            }

                            feedbackActionButton(title: "Not for me", icon: "hand.thumbsdown.fill") {
                                onLikedAnswer(prompt, false)
                                withAnimation(.snappy) {
                                    step = .reason
                                }
                            }
                        }

                    case .reason:
                        Text("What was off?")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        dislikeReasonChips { reason in
                            onDislikeReason(prompt, reason)
                            complete()
                        }
                    }
                }
            }
        }
        .padding(18)
        .appCard(.home, radius: 20)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func feedbackActionButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .frame(width: 24)
                Text(title)
                    .fontWeight(.bold)
                Spacer()
            }
            .foregroundStyle(Color(hex: 0x11101E))
            .padding()
            .background(Color(hex: 0xEED9B5))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private func dislikeReasonChips(onSelect: @escaping (DislikeReason) -> Void) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
            ForEach(DislikeReason.allCases, id: \.self) { reason in
                Button(reason.displayName) {
                    onSelect(reason)
                }
                .font(.caption)
                .fontWeight(.bold)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .foregroundStyle(Color(hex: 0x11101E))
                .background(Color(hex: 0xEED9B5).opacity(0.72))
                .clipShape(Capsule())
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

struct StableAIFallbackView: View {
    @Binding var selectedTab: AppTab
    @AppStorage("profileName") private var profileName = ""
    @AppStorage("preferredAIAssistant") private var preferredAIAssistant = PreferredAIAssistant.chatGPT.rawValue
    @AppStorage("connectedAIAssistants") private var connectedAIAssistants = "\(PreferredAIAssistant.siri.rawValue),\(PreferredAIAssistant.chatGPT.rawValue)"
    @AppStorage("shareAppContextWithChatGPT") private var shareAppContextWithChatGPT = true
    @AppStorage("shirtSize") private var shirtSize = "L"
    @AppStorage("pantsSize") private var pantsSize = "Men 36x36"
    @AppStorage("neckSize") private var neckSize = ""
    @AppStorage("sleeveLength") private var sleeveLength = ""
    @AppStorage("shoeSize") private var shoeSize = "10"
    @AppStorage("fitPreference") private var fitPreference = "Regular"
    @AppStorage("shoppingBudget") private var budget = "$50 - $200"
    @AppStorage("favoriteColors") private var favoriteColors = "Black, white, navy"
    @AppStorage("favoriteBrands") private var favoriteBrands = "Ralph Lauren, Nike, Levi's"
    @AppStorage("favoriteOutfits") private var favoriteOutfits = "Navy blazer with dark denim"
    @AppStorage("weather") private var weather = "Mild weather"
    @AppStorage("weatherCondition") private var weatherCondition = "Sunny"
    @AppStorage("weatherSource") private var weatherSource = "Saved"
    @AppStorage("plannedOccasion") private var plannedOccasion = "Work"
    @AppStorage("stylePreferences") private var stylePreferences = "Classic, business casual, clean sneakers"
    @AppStorage("outfitScanHistoryData") private var outfitScanHistoryData = Data()
    @AppStorage("closetItemsData") private var closetItemsData = Data()
    @AppStorage("aiStylistConversationData") private var aiStylistConversationData = Data()
    @AppStorage("aiStylistArchivedConversationsData") private var aiStylistArchivedConversationsData = Data()
    @AppStorage("openAIModel") private var openAIModel = "gpt-4o-mini"
    @State private var message: String?
    @State private var showTodaysOutfitAdvice = false
    @State private var showStylistChat = false
    @State private var showAwarenessTestResult = false
    @State private var showAwarenessDetail = false
    @State private var showMemoryDetails = false
    @State private var showAISettings = false
    @State private var dashboardAppeared = false
    @State private var chatInput = ""
    @State private var chatMessages: [AIStylistChatMessage] = []
    @State private var isSendingStylistMessage = false
    @State private var openAIKeyInput = ""
    @State private var openAIKeyIsSaved = false
    @State private var betaAIConnectionVerified = false
    @State private var betaAIStatus = ""
    @State private var cachedClosetItems: [ClosetItem] = []
    @State private var cachedLatestStoredScan: SafeHomeStoredScan?
    @State private var cachedSavedScanCount = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    aiDashboardHeader
                    if StyleMatchBuildSettings.allowsLocalFounderAPIKey {
                        betaChatGPTSetupCard
                    }
                    aiWeatherStylingCard
                    dailyStyleBriefDashboard
                    todaysRecommendedLookCard
                    aiConfidenceStrip
                    chatGPTAppAwarenessCard
                    profileCompletenessCard
                    closetIntelligenceCard
                    connectedServicesCard
                    privacyPromiseCard

                    if let message {
                        Label(message, systemImage: "checkmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.green)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .appCard(.ai, radius: 12)
                    }
                }
                .padding()
            }
            .scrollContentBackground(.hidden)
            .appScreenBackground(.ai)
            .navigationTitle("AI Stylist")
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
            .onAppear {
                refreshSavedContextCache()
                loadBetaOpenAIKey()
                loadChatMessages()
                dashboardAppeared = true
            }
            .styleMatchOnChange(of: closetItemsData) { _ in refreshSavedContextCache() }
            .styleMatchOnChange(of: outfitScanHistoryData) { _ in refreshSavedContextCache() }
            .sheet(isPresented: $showStylistChat) {
                aiStylistChatSheet
            }
            .sheet(isPresented: $showTodaysOutfitAdvice) {
                NavigationStack {
                    ScrollView {
                        todaysOutfitAdviceCard
                            .padding()
                    }
                    .scrollContentBackground(.hidden)
                    .appScreenBackground(.ai)
                    .navigationTitle("Today's Outfit")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") {
                                showTodaysOutfitAdvice = false
                            }
                        }
                    }
                }
            }
            .alert("ChatGPT Awareness", isPresented: $showAwarenessTestResult) {
                Button("OK", role: .cancel) {
                }
            } message: {
                Text(appAwarenessTestMessage)
            }
            .sheet(isPresented: $showAwarenessDetail) {
                NavigationStack {
                    ScrollView {
                        appAwarenessDetailScreen
                            .padding()
                    }
                    .scrollContentBackground(.hidden)
                    .appScreenBackground(.ai)
                    .navigationTitle("ChatGPT Awareness")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") {
                                showAwarenessDetail = false
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showAISettings) {
                NavigationStack {
                    ScrollView {
                        aiSettingsScreen
                            .padding()
                    }
                    .scrollContentBackground(.hidden)
                    .appScreenBackground(.ai)
                    .navigationTitle("AI Settings")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") {
                                showAISettings = false
                            }
                        }
                    }
                }
            }
        }
    }

    private var aiDashboardHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Good \(dayGreeting), \(displayName)")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .lineLimit(2)
                        .minimumScaleFactor(0.76)

                    Text("StyleMatch Pro AI Stylist")
                        .font(.title3)
                        .fontWeight(.bold)

                    Text("Powered by \(selectedAssistantDisplayName)")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppTab.ai.palette.accent)
                }

                Spacer(minLength: 8)

                Button {
                    showAISettings = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            Text("Your personal stylist checks weather, closet, sizes, saved scans, and style memory before suggesting what to wear.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(3)

            HStack(spacing: 10) {
                WeatherStylingButton {
                    aiMiniMetric(title: weatherTemperatureText, detail: weatherConditionText, icon: "cloud.sun.fill")
                }
                aiMiniMetric(title: "\(expectedStyleScore)", detail: "Expected Score", icon: "star.fill")
            }
        }
        .padding()
        .appCard(.ai)
        .opacity(dashboardAppeared ? 1 : 0)
        .offset(y: dashboardAppeared ? 0 : 10)
    }

    private var dailyStyleBriefDashboard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Daily Style Brief", systemImage: "sun.max.fill")
                .font(.title2)
                .fontWeight(.bold)

            Text("Today's weather is \(weatherTemperatureText) and \(weatherConditionText.lowercased()). Based on your saved wardrobe, preferences, and today's occasion, StyleMatch Pro recommends a clean \(plannedOccasion.lowercased()) look.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(4)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                aiMiniMetric(title: plannedOccasion, detail: "Occasion", icon: "calendar")
                aiMiniMetric(title: "\(savedClosetCount)", detail: "Closet Items", icon: "tshirt.fill")
                aiMiniMetric(title: "\(recentStyleScore)", detail: "Recent Score", icon: "clock.fill")
                aiMiniMetric(title: "\(savedScanCount)", detail: "Saved Scans", icon: "photo.on.rectangle")
            }
        }
        .padding()
        .appCard(.ai)
    }

    private var betaChatGPTSetupCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: betaAIConnectionVerified ? "checkmark.seal.fill" : "key.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background(betaAIConnectionVerified ? Color.green : AppTab.ai.palette.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 4) {
                    Text("ChatGPT Live Assistant")
                        .font(.title3)
                        .fontWeight(.bold)

                    Text(betaChatGPTSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }

            SecureField("Founder beta access key", text: $openAIKeyInput)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.password)
                .textFieldStyle(.roundedBorder)

            Picker("Response speed", selection: $openAIModel) {
                Text("Fast").tag("gpt-4o-mini")
                Text("Balanced").tag("gpt-4o")
                Text("Best").tag("gpt-4.1")
            }
            .pickerStyle(.segmented)

            HStack(spacing: 10) {
                Button {
                    saveBetaOpenAIKey()
                } label: {
                    Label("Activate ChatGPT", systemImage: "bolt.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(AppTab.ai.palette.accent)

                Button(role: .destructive) {
                    deleteBetaOpenAIKey()
                } label: {
                    Label("Delete", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            if !betaAIStatus.isEmpty {
                Label(betaAIStatus, systemImage: betaAIConnectionVerified ? "checkmark.circle.fill" : "info.circle")
                    .font(.caption)
                    .foregroundStyle(betaAIConnectionVerified ? .green : .secondary)
            }

            Text("Founder beta only. Public builds use the secure StyleMatch Pro AI service instead of on-device keys.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .appCard(.ai)
    }

    private var aiWeatherStylingCard: some View {
        WeatherStylingButton {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "cloud.sun.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background(AppTab.ai.palette.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Weather Styling")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)

                    Text("\(weatherTemperatureText) • \(weatherConditionText)")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)

                    Text("Tap to refresh live weather and outfit advice.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .padding()
            .appCard(.ai)
        }
    }

    private var todaysRecommendedLookCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "wand.and.stars")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background(AppTab.ai.palette.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Today's Recommended Look")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("\(recommendedStyle) • \(plannedOccasion) • \(weatherConditionText)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(expectedStyleScore)")
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                    Text("Expected")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                aiAdviceRow(icon: "tshirt.fill", title: "Top", value: "White Oxford Shirt")
                aiAdviceRow(icon: "figure.stand", title: "Bottom", value: "Dark Denim Jeans")
                aiAdviceRow(icon: "circle.hexagongrid.fill", title: "Belt", value: "Black Leather Belt")
                aiAdviceRow(icon: "shoe.2.fill", title: "Shoes", value: "Black Loafers")
                aiAdviceRow(icon: "watch.analog", title: "Accessory", value: "Silver Watch")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Why this outfit?")
                    .font(.headline)
                    .fontWeight(.bold)
                aiCheckRow("Matches today's weather")
                aiCheckRow("Matches your saved style and favorite colors")
                aiCheckRow("Fits your \(budget) budget")
                aiCheckRow("Works for \(plannedOccasion.lowercased())")
            }

            HStack(spacing: 10) {
                Button {
                    showTodaysOutfitAdvice = true
                    message = nil
                } label: {
                    Label("Ask Why", systemImage: "questionmark.bubble.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    selectedTab = .scan
                } label: {
                    Label("Analyze", systemImage: "camera.viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                aiSmallAction("Save Outfit", "heart.fill") {
                    favoriteOutfits = favoriteOutfits.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "Today's Recommended Look"
                        : "\(favoriteOutfits), Today's Recommended Look"
                    message = "Today's recommended look was saved to favorites."
                }
                aiSmallAction("Compare With Closet", "tshirt.fill") {
                    message = closetCheckText
                }
                aiSmallAction("Replace Item", "arrow.triangle.2.circlepath") {
                    message = "Try replacing the top with a navy polo or crisp white Oxford."
                }
                aiSmallAction("Change Shoes", "shoe.2.fill") {
                    message = "Try clean white sneakers for contrast or black loafers for polish."
                }
                aiSmallAction("Change Accessories", "watch.analog") {
                    message = "Add a silver watch or simple belt to make the look feel finished."
                }
                aiSmallAction("Improve Score", "chart.line.uptrend.xyaxis") {
                    message = "Improve the score by sharpening fit, polishing shoes, and keeping colors intentional."
                }
                aiSmallAction("Explain Score", "questionmark.circle.fill") {
                    showTodaysOutfitAdvice = true
                }
                aiSmallAction("Generate Another", "sparkles") {
                    message = "Alternative look: navy polo, beige chinos, white sneakers, and a lightweight jacket."
                }
            }
        }
        .padding()
        .appCard(.ai)
    }

    private func aiSmallAction(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.caption)
                .fontWeight(.bold)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, minHeight: 38)
        }
        .buttonStyle(.bordered)
    }

    private var aiConfidenceStrip: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Confidence")
                    .font(.title3)
                    .fontWeight(.bold)
                Spacer()
                Label(shareAppContextWithChatGPT ? "Style Memory Active" : "Memory Off", systemImage: shareAppContextWithChatGPT ? "checkmark.seal.fill" : "pause.circle.fill")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(shareAppContextWithChatGPT ? .green : .secondary)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                aiMiniMetric(title: "\(aiConfidence)%", detail: "AI Confidence", icon: "sparkles")
                aiMiniMetric(title: "\(profileCompleteness)%", detail: "Profile", icon: "person.crop.circle")
                aiMiniMetric(title: "\(savedClosetCount)", detail: "Closet Items", icon: "tshirt.fill")
                aiMiniMetric(title: "\(savedScanCount)", detail: "Saved Scans", icon: "photo.stack")
            }
        }
        .padding()
        .appCard(.ai)
    }

    private var aiActionDashboard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What do you need today?")
                .font(.title2)
                .fontWeight(.bold)

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    aiActionCard("Ask My Stylist", icon: "bubble.left.and.bubble.right.fill") {
                        showStylistChat = true
                        message = nil
                    }
                    aiActionCard("Build My Outfit", icon: "sparkles") { selectedTab = .closet }
                }

                HStack(spacing: 10) {
                    aiActionCard("Analyze New Outfit", icon: "camera.viewfinder") { selectedTab = .scan }
                    aiActionCard("Complete My Outfit", icon: "checkmark.seal.fill") { message = closetMissingPieceMessage }
                }

                HStack(spacing: 10) {
                    aiActionCard("Shop My Style", icon: "bag.fill") { selectedTab = .shop }
                    aiActionCard("Pack For My Trip", icon: "suitcase.fill") {
                        message = "Trip planner is ready. StyleMatch Pro will use weather, closet, sizes, and style memory."
                    }
                }

                HStack(spacing: 10) {
                    aiActionCard("Dress Me For Work", icon: "briefcase.fill") {
                        showTodaysOutfitAdvice = true
                        message = "Work outfit request is ready."
                    }
                    aiActionCard("Dress Me For Church", icon: "building.columns.fill") {
                        message = "Church outfit guidance is ready. StyleMatch Pro will keep it respectful and polished."
                    }
                }

                HStack(spacing: 10) {
                    aiActionCard("Dress Me For Wedding", icon: "heart.fill") {
                        message = "Wedding outfit guidance is ready. StyleMatch Pro will check formality, color, shoes, and accessories."
                    }
                    aiActionCard("Date Night", icon: "moon.stars.fill") {
                        message = "Date night outfit guidance is ready."
                    }
                }

                aiActionCard("Vacation Planner", icon: "airplane") {
                    message = "Vacation outfit planner is ready. Add destination weather for stronger recommendations."
                }
            }
        }
        .padding()
        .appCard(.ai)
    }

    private var chooseStylistPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("StyleMatch Pro AI Stylist", systemImage: "sparkles")
                .font(.title2)
                .fontWeight(.bold)

            Text("StyleMatch Pro is your personal AI fashion stylist. ChatGPT powers the experience in the background.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .lineSpacing(5)

            activeChatGPTCard
            chatGPTAppAwarenessCard
            connectedServicesCard

            Label("StyleMatch Pro keeps your stylist memory private.", systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .appCard(.ai)
    }

    private var activeChatGPTCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.title)
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 18))

                VStack(alignment: .leading, spacing: 4) {
                    Text("AI Stylist")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)

                    Text("StyleMatch Pro AI Stylist")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .minimumScaleFactor(0.8)

                    Text("Powered by ChatGPT")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundStyle(.green)
                }

                Spacer(minLength: 0)
            }

            VStack(spacing: 14) {
                aiPillButton(title: "Ask My Stylist", icon: "bubble.left.and.bubble.right.fill") {
                    showStylistChat = true
                    message = nil
                }

                aiPillButton(title: "Build My Outfit", icon: "sparkles") {
                    selectedTab = .closet
                }

                aiPillButton(title: "Find Matching Clothes", icon: "bag.fill") {
                    selectedTab = .shop
                }

                aiPillButton(title: "Analyze a New Outfit", icon: "camera.viewfinder") {
                    selectedTab = .scan
                }

                aiPillButton(title: "Pack For My Trip", icon: "suitcase.fill") {
                    message = "Trip packing is ready. StyleMatch Pro can use your closet, weather, sizes, and travel plans."
                }

                aiPillButton(title: "Dress Me For Work", icon: "briefcase.fill") {
                    showTodaysOutfitAdvice = true
                    message = "Work outfit request is ready."
                }

                aiPillButton(title: "Dress Me For An Event", icon: "heart.fill") {
                    showTodaysOutfitAdvice = true
                    message = "Event outfit request is ready."
                }

                aiPillButton(title: "Shop My Style", icon: "cart.fill") {
                    selectedTab = .shop
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground).opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var chatGPTAppAwarenessCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "brain.head.profile")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(AppTab.ai.palette.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    Text("ChatGPT Awareness")
                        .font(.title3)
                        .fontWeight(.bold)

                    Text("ChatGPT can use your StyleMatch Pro memory, closet, sizes, weather, saved scans, and style preferences when helping you.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                }
            }

            Toggle(isOn: $shareAppContextWithChatGPT) {
                Text(shareAppContextWithChatGPT ? "ChatGPT Awareness On" : "ChatGPT Awareness Off")
                    .font(.headline)
            }
            .tint(AppTab.ai.palette.accent)

            VStack(alignment: .leading, spacing: 8) {
                appAwarenessRow("Sizes", "Saved")
                appAwarenessRow("Favorite Colors", "Saved")
                appAwarenessRow("Favorite Brands", "Saved")
                appAwarenessRow("Budget", "Saved")
                appAwarenessRow("Closet", "\(savedClosetCount) item\(savedClosetCount == 1 ? "" : "s")")
                appAwarenessRow("Scan History", "\(savedScanCount) scan\(savedScanCount == 1 ? "" : "s")")
                appAwarenessRow("Weather", "Saved")
                appAwarenessRow("Occasion Preferences", "Saved")
                appAwarenessRow("Style Preferences", "Saved")
            }
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))

            Button {
                showMemoryDetails = true
            } label: {
                Label("View Details", systemImage: "chevron.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                aiSmallAction(shareAppContextWithChatGPT ? "Pause Memory" : "Resume Memory", shareAppContextWithChatGPT ? "pause.circle.fill" : "play.circle.fill") {
                    shareAppContextWithChatGPT.toggle()
                    message = shareAppContextWithChatGPT ? "ChatGPT Awareness resumed." : "ChatGPT Awareness paused."
                }

                aiSmallAction("View Stored Preferences", "list.bullet.rectangle") {
                    showMemoryDetails = true
                }

                aiSmallAction("Clear AI Memory", "trash") {
                    shareAppContextWithChatGPT = false
                    message = "ChatGPT Awareness memory was cleared for AI use. Profile fields remain editable in Profile."
                }

                aiSmallAction("Reset Style Profile", "arrow.counterclockwise") {
                    favoriteColors = "Black, white, navy"
                    favoriteBrands = "Ralph Lauren, Nike, Levi's"
                    stylePreferences = "Classic, business casual, clean sneakers"
                    message = "Style profile reset to starter preferences."
                }
            }

            Button {
                message = shareAppContextWithChatGPT
                    ? "ChatGPT Awareness test completed."
                    : "ChatGPT Awareness is off. Turn it on to let StyleMatch Pro AI use your style context."
                showAwarenessDetail = true
            } label: {
                Label("Test Awareness", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(AppTab.ai.palette.accent)
        }
        .padding()
        .background(Color(.secondarySystemBackground).opacity(0.72))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(AppTab.ai.palette.accent.opacity(0.32), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .sheet(isPresented: $showMemoryDetails) {
            NavigationStack {
                ScrollView {
                    personalStyleProfileDetail
                        .padding()
                }
                .scrollContentBackground(.hidden)
                .appScreenBackground(.ai)
                .navigationTitle("Style Profile")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            showMemoryDetails = false
                        }
                    }
                }
            }
        }
    }

    private var profileCompletenessCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                Label("Profile Completeness", systemImage: "person.crop.circle.badge.checkmark")
                    .font(.title3)
                    .fontWeight(.bold)
                Spacer()
                Text("\(profileCompleteness)%")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
            }

            ProgressView(value: Double(profileCompleteness), total: 100)
                .tint(AppTab.ai.palette.accent)

            if missingProfileFields.isEmpty {
                Label("Your profile has enough detail for strong recommendations.", systemImage: "checkmark.seal.fill")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.green)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Missing")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)

                    ForEach(missingProfileFields, id: \.self) { field in
                        Label(field, systemImage: "square")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Text("Completing your profile improves recommendation quality.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .appCard(.ai)
    }

    private var closetIntelligenceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Closet Intelligence", systemImage: "tshirt.fill")
                .font(.title3)
                .fontWeight(.bold)

            Text(closetFirstRecommendation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(3)

            VStack(alignment: .leading, spacing: 8) {
                closetInsightRow("Closet check", closetCheckText)
                closetInsightRow("Shopping suggestion", shoppingReasonText)
                closetInsightRow("Favorite outfit", favoriteOutfitText)
                closetInsightRow("Style tip", dailyStyleTip)
            }

            Button {
                selectedTab = .closet
            } label: {
                Label("Open Closet", systemImage: "tshirt.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .padding()
        .appCard(.ai)
    }

    private var privacyPromiseCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Your Privacy", systemImage: "lock.shield.fill")
                .font(.title3)
                .fontWeight(.bold)

            privacyRow("Your data stays on your device whenever possible.")
            privacyRow("Cloud AI is used only when necessary.")
            privacyRow("You control your information.")
            privacyRow("Delete your data anytime.")
            privacyRow("Personal Style Memory can be turned off at any time.")
        }
        .padding()
        .appCard(.ai)
    }

    private var appAwarenessDetailScreen: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: shareAppContextWithChatGPT ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(shareAppContextWithChatGPT ? Color.green : Color.orange)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 5) {
                    Text(shareAppContextWithChatGPT ? "Personal Style Memory Is On" : "Personal Style Memory Is Off")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text(shareAppContextWithChatGPT ? "StyleMatch Pro AI can use your style memory when helping with outfits." : "Turn Personal Style Memory on to let StyleMatch Pro AI use your style context.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                appAwarenessRow("Sizes", "\(shirtSize) shirt, \(pantsSize), shoe \(shoeSize)")
                appAwarenessRow("Style Memory", "\(favoriteColors); \(favoriteBrands)")
                appAwarenessRow("Today", "\(weather), \(plannedOccasion)")
                appAwarenessRow("Saved Data", "\(savedClosetCount) closet item\(savedClosetCount == 1 ? "" : "s"), \(savedScanCount) scan\(savedScanCount == 1 ? "" : "s")")
                appAwarenessRow("Budget", budget)
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))

            Button {
                showAwarenessDetail = false
                showStylistChat = true
                message = "StyleMatch Pro AI is using Personal Style Memory for today's outfit."
            } label: {
                Label("Ask My Stylist Now", systemImage: "bubble.left.and.bubble.right.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(AppTab.ai.palette.accent)

            Button {
                showAwarenessDetail = false
                selectedTab = .closet
            } label: {
                Label("Build Outfit From Closet", systemImage: "tshirt.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Label("StyleMatch Pro uses this memory only for styling, fit, outfit, shopping, and weather recommendations.", systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
        }
        .padding()
        .appCard(.ai)
    }

    private var personalStyleProfileDetail: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Your Style Profile", systemImage: "person.text.rectangle.fill")
                .font(.title2)
                .fontWeight(.bold)

            VStack(alignment: .leading, spacing: 10) {
                styleProfileLine("Classic Style")
                styleProfileLine("Prefers \(favoriteColors)")
                styleProfileLine("Favorite Brands: \(favoriteBrands)")
                styleProfileLine("Budget: \(budget)")
                styleProfileLine("Typical Occasion: \(plannedOccasion)")
                styleProfileLine("Preferred Weather: \(weather)")
                styleProfileLine("Shirt: \(shirtSize)")
                styleProfileLine("Pants: \(pantsSize)")
                styleProfileLine("Shoes: \(shoeSize)")
            }

            Label("You can turn Personal Style Memory off anytime.", systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .appCard(.ai)
    }

    private func styleProfileLine(_ text: String) -> some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(.primary)
    }

    private func appAwarenessRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AppTab.ai.palette.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
            }
            Spacer(minLength: 0)
        }
    }

    private var savedClosetCount: Int {
        cachedClosetItems.count
    }

    private var savedScanCount: Int {
        cachedSavedScanCount
    }

    private func refreshSavedContextCache() {
        if !closetItemsData.isEmpty,
           let items = try? JSONDecoder().decode([ClosetItem].self, from: closetItemsData) {
            cachedClosetItems = items
        } else {
            cachedClosetItems = []
        }

        if !outfitScanHistoryData.isEmpty,
           let history = try? JSONDecoder().decode([String: SafeHomeStoredScan].self, from: outfitScanHistoryData) {
            cachedSavedScanCount = history.count
            cachedLatestStoredScan = history.values.max { $0.firstScannedAt < $1.firstScannedAt }
        } else {
            cachedSavedScanCount = 0
            cachedLatestStoredScan = nil
        }
    }

    private var appAwarenessTestMessage: String {
        if !shareAppContextWithChatGPT {
            return "ChatGPT Awareness is off. Turn it on so StyleMatch Pro AI can use your style context."
        }

        return """
        ChatGPT Awareness is on.

        StyleMatch Pro AI can use:
        Sizes: \(shirtSize) shirt, \(pantsSize), shoe \(shoeSize)
        Style memory: \(favoriteColors); \(favoriteBrands)
        Today: \(weather), \(plannedOccasion)
        Saved data: \(savedClosetCount) closet item\(savedClosetCount == 1 ? "" : "s"), \(savedScanCount) scan\(savedScanCount == 1 ? "" : "s")
        Budget: \(budget)
        """
    }

    private var todaysOutfitAdviceCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(AppTab.ai.palette.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Today's Outfit")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("ChatGPT suggests a polished smart-casual look from your saved style profile.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 10) {
                aiAdviceRow(icon: "tshirt.fill", title: "Start with", value: "Navy or white shirt")
                aiAdviceRow(icon: "figure.stand", title: "Pair with", value: "Dark denim or 36x36 pants")
                aiAdviceRow(icon: "shoe.2.fill", title: "Shoes", value: "Clean white sneakers or black loafers")
                aiAdviceRow(icon: "star.fill", title: "Expected score", value: "92-95 if the fit is clean")
            }

            HStack(spacing: 12) {
                Button {
                    showTodaysOutfitAdvice = false
                    selectedTab = .scan
                } label: {
                    Label("Scan Outfit", systemImage: "camera.viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    showTodaysOutfitAdvice = false
                    selectedTab = .shop
                } label: {
                    Label("Find Missing Piece", systemImage: "bag.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .padding()
        .appCard(.ai)
    }

    private var aiStylistChatSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            if chatMessages.isEmpty {
                                aiChatWelcomeCard
                            }

                            ForEach(Array(chatMessages.enumerated()), id: \.element.id) { index, message in
                                if shouldShowChatTimestamp(at: index) {
                                    Text(chatTimestampText(for: message.createdAt))
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 4)
                                }

                                aiChatBubble(message)
                                    .id(message.id)
                            }

                            if isSendingStylistMessage {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Stylist is thinking...")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 4)
                                .id("main-stylist-thinking")
                            }
                        }
                        .padding()
                    }
                    .styleMatchOnChange(of: chatMessages.count) { _ in
                        guard let lastID = chatMessages.last?.id else { return }
                        withAnimation(.easeInOut(duration: 0.22)) {
                            proxy.scrollTo(lastID, anchor: .bottom)
                        }
                    }
                }

                Divider()

                VStack(spacing: 10) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(chatStarterPrompts, id: \.self) { prompt in
                                Button(prompt) {
                                    sendStylistMessage(prompt)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(isSendingStylistMessage)
                            }
                        }
                        .padding(.horizontal)
                    }

                    HStack(spacing: 10) {
                        TextField("Ask your stylist...", text: $chatInput, axis: .vertical)
                            .lineLimit(1...3)
                            .textFieldStyle(.roundedBorder)

                        Button {
                            sendStylistMessage(chatInput)
                        } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 34))
                        }
                        .disabled(isSendingStylistMessage || chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(.horizontal)
                }
                .padding(.top, 10)
                .padding(.bottom, 12)
                .background(.ultraThinMaterial)
            }
            .appScreenBackground(.ai)
            .navigationTitle("Ask My Stylist")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("New Chat") {
                        archiveCurrentChatAndStartNew()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        showStylistChat = false
                    }
                }
            }
        }
    }

    private var aiChatWelcomeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("StyleMatch Pro AI Stylist", systemImage: "sparkles")
                .font(.title2)
                .fontWeight(.bold)

            Text("Ask about outfits, shoes, shopping, occasions, weather, closet matching, or why a score changed. Your conversation stays on this device for beta testing.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
        }
        .padding()
        .appCard(.ai)
    }

    private func aiChatBubble(_ message: AIStylistChatMessage) -> some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 42)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                Text(message.text)
                    .font(.subheadline)
                    .foregroundStyle(message.role == .user ? .white : .primary)
                    .lineSpacing(2)

                HStack(spacing: 8) {
                    if message.isEdited {
                        Text("Edited")
                            .font(.caption2)
                            .foregroundStyle(message.role == .user ? .white.opacity(0.75) : .secondary)
                    }

                    if let failedPrompt = message.failedPrompt, !failedPrompt.isEmpty {
                        Button("Retry") {
                            retryFailedChatMessage(message)
                        }
                        .font(.caption)
                        .fontWeight(.bold)
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .disabled(isSendingStylistMessage)
                    }
                }
            }
            .padding(12)
            .background(message.role == .user ? AppTab.ai.palette.accent : Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .contentShape(RoundedRectangle(cornerRadius: 16))


            if message.role == .stylist {
                Spacer(minLength: 42)
            }
        }
    }

    private var chatStarterPrompts: [String] {
        let recentText = chatMessages.reversed()
            .first(where: { $0.failedPrompt == nil })?
            .text
            .lowercased() ?? ""

        if recentText.contains("score") || recentText.contains("improve") {
            return [
                "Why did I get this score?",
                "What is the weakest part?",
                "How can I improve it?",
                "Would different shoes help?"
            ]
        }

        if recentText.contains("shop") || recentText.contains("buy") || recentText.contains("match") {
            return [
                "Find matching clothes.",
                "Use my closet first.",
                "Stay under my budget.",
                "What should I avoid buying?"
            ]
        }

        if recentText.contains("church") || recentText.contains("wedding") || recentText.contains("work") {
            return [
                "Make it more polished.",
                "Check occasion fit.",
                "What shoes should I wear?",
                "Build a second option."
            ]
        }

        return [
            "Read my latest style score.",
            "What should I wear today?",
            "Build me an outfit.",
            "What shoes match this?",
            "Improve my style score.",
            "Dress me for church.",
            "Help me shop."
        ]
    }

    private func sendStylistMessage(_ rawText: String) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard !isSendingStylistMessage else { return }

        chatInput = ""
        let userMessage = AIStylistChatMessage(role: .user, text: text)
        chatMessages.append(userMessage)
        isSendingStylistMessage = true
        saveChatMessages()
        let conversation = activeStylistConversationHistory()

        Task {
            await requestStylistReply(for: text, conversation: conversation, retryAttempt: 0)
        }
    }

    private func requestStylistReply(for text: String, conversation: [AIChatMessage], retryAttempt: Int) async {
        do {
            let response = try await liveChatGPTReply(to: text, conversation: conversation)
            await MainActor.run {
                chatMessages.append(AIStylistChatMessage(role: .stylist, text: response))
                isSendingStylistMessage = false
                saveChatMessages()
            }
        } catch {
            logStylistChatFailure(error, prompt: text, retryAttempt: retryAttempt)

            if retryAttempt == 0 {
                try? await Task.sleep(nanoseconds: 750_000_000)
                await requestStylistReply(for: text, conversation: conversation, retryAttempt: 1)
                return
            }

            await MainActor.run {
                chatMessages.append(
                    AIStylistChatMessage(
                        role: .stylist,
                        text: "AI Stylist is having trouble connecting right now. Please try again.",
                        failedPrompt: text,
                        failureReason: stylistFailureReason(error)
                    )
                )
                isSendingStylistMessage = false
                saveChatMessages()
            }
        }
    }

    private func liveChatGPTReply(to text: String, conversation: [AIChatMessage]) async throws -> String {
        guard let savedKey = OpenAIKeychain.loadAPIKey()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !savedKey.isEmpty else {
            throw OpenAIStylistError.missingAPIKey
        }

        let profile = StyleMatchStylistProfile(
            name: displayName,
            favoriteColors: favoriteColors,
            favoriteBrands: favoriteBrands,
            preferredFit: fitPreference,
            budget: budget,
            sizeProfile: "Shirt \(shirtSize); pants \(pantsSize); shoes \(shoeSize)",
            stylePreferences: stylePreferences,
            occasions: plannedOccasion,
            weather: "\(weatherConditionText), \(weatherTemperatureText)",
            weatherPreferences: "\(weatherConditionText), \(weatherTemperatureText)",
            dressCode: plannedOccasion,
            shoppingHabits: "Budget \(budget); favorite brands \(favoriteBrands)",
            pastOutfitRatings: "\(recentStyleScore)/100 recent score, \(savedScanCount) saved scan\(savedScanCount == 1 ? "" : "s")",
            frequentlyWornOutfits: favoriteOutfits,
            pastPurchases: "White Oxford shirt, black leather belt",
            favoriteOutfits: favoriteOutfits,
            closetInventory: closetItems.prefix(12).map { "\($0.color) \($0.name)" }.joined(separator: ", "),
            appContextSharingEnabled: shareAppContextWithChatGPT,
            appContext: """
            StyleMatch Pro AI Stylist chat.
            Closet items: \(savedClosetCount)
            Saved scans: \(savedScanCount)
            Preferred assistant: \(selectedAssistantDisplayName)
            Recent scan context: \(latestScanContextForAI)
            """
        )

        let client = OpenAIStylistClient(apiKey: savedKey, model: openAIModel)

        let guidedQuestion = """
        Answer the customer's exact message as StyleMatch Pro AI Stylist.
        If the customer says hello, greet them naturally.
        If they ask what you know about them, use only saved StyleMatch Pro profile, closet, weather, scan history, and style memory. Do not invent personal details.
        If they ask you to read or explain their score, use the latest saved scan score from app context. Say the score, the match rating, why StyleMatch Pro gave that score, and one or two ways to improve it. Do not create a new score.
        Do not repeat a generic outfit response unless the customer asks what to wear.

        Customer message:
        \(text)
        """

        return try await client.askStylist(
            profile: profile,
            messages: conversation,
            question: guidedQuestion
        )
    }

    private func activeStylistConversationHistory() -> [AIChatMessage] {
        chatMessages
            .filter { $0.failedPrompt == nil }
            .suffix(24)
            .map { message in
                AIChatMessage(
                    role: message.role == .user ? .customer : .assistant,
                    text: message.text,
                    createdAt: message.createdAt,
                    edited: message.isEdited,
                    editedAt: message.editedAt
                )
            }
    }

    private func retryFailedChatMessage(_ message: AIStylistChatMessage) {
        guard let prompt = message.failedPrompt, !isSendingStylistMessage else { return }
        chatMessages.removeAll { $0.id == message.id }
        isSendingStylistMessage = true
        saveChatMessages()
        let conversation = activeStylistConversationHistory()

        Task {
            await requestStylistReply(for: prompt, conversation: conversation, retryAttempt: 0)
        }
    }

    private func shouldShowChatTimestamp(at index: Int) -> Bool {
        guard chatMessages.indices.contains(index) else { return false }
        guard index > 0 else { return true }
        let previous = chatMessages[index - 1].createdAt
        return chatMessages[index].createdAt.timeIntervalSince(previous) > 10 * 60
    }

    private func chatTimestampText(for date: Date) -> String {
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(date) {
            formatter.dateFormat = "h:mm a"
        } else {
            formatter.dateFormat = "MMM d, h:mm a"
        }
        return formatter.string(from: date)
    }

    private func archiveCurrentChatAndStartNew() {
        guard !chatMessages.isEmpty else { return }
        var archives = loadArchivedAIStylistChats()
        archives.append(AIStylistChatArchive(messages: chatMessages))
        if let data = try? JSONEncoder().encode(Array(archives.suffix(20))) {
            aiStylistArchivedConversationsData = data
        }
        chatMessages.removeAll()
        saveChatMessages()
    }

    private func loadArchivedAIStylistChats() -> [AIStylistChatArchive] {
        guard !aiStylistArchivedConversationsData.isEmpty,
              let archives = try? JSONDecoder().decode([AIStylistChatArchive].self, from: aiStylistArchivedConversationsData) else {
            return []
        }
        return archives
    }

    private func logStylistChatFailure(_ error: Error, prompt: String, retryAttempt: Int) {
        #if DEBUG
        print("[AI Stylist Chat] failure=\(stylistFailureReason(error)); retryAttempt=\(retryAttempt); promptLength=\(prompt.count); detail=\(error.localizedDescription)")
        #endif
    }

    private func stylistFailureReason(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return "timeout"
            case .notConnectedToInternet, .networkConnectionLost:
                return "network"
            default:
                return "url_error_\(urlError.code.rawValue)"
            }
        }

        if let stylistError = error as? OpenAIStylistError {
            switch stylistError {
            case .missingAPIKey:
                return "missing_api_key"
            case .invalidResponse:
                return "invalid_response"
            case .emptyOutput:
                return "empty_output"
            case .api(let message):
                let lower = message.lowercased()
                if lower.contains("rate") || lower.contains("429") {
                    return "rate_limit"
                }
                if lower.contains("sign in") || lower.contains("401") {
                    return "api_auth"
                }
                return "api_error"
            }
        }

        if error is DecodingError {
            return "parse_error"
        }

        return "unknown"
    }

    private var latestScanContextForAI: String {
        guard let scan = cachedLatestStoredScan,
              let analysis = scan.analysis else {
            return "No saved outfit scan details available."
        }

        let confidence = analysis.detectedItemConfidences.isEmpty
            ? "No saved item confidence details."
            : analysis.detectedItemConfidences.prefix(6).compactMap { item in
                GarmentLabelMapper.humanReadableTerm(for: item.item).map { "\($0) \(item.confidence)%" }
            }.joined(separator: ", ")

        return """
        Score: \(analysis.score)/100.
        Score rating: \(aiScoreRatingTitle(for: analysis.score)).
        Outfit: \(analysis.outfitDescription)
        Detected clothing: \(analysis.safeDetectedClothingItems.joined(separator: ", "))
        Colors: \(analysis.colorPalette.joined(separator: ", "))
        Occasion/Formality: \(analysis.occasionFit); \(analysis.formality)
        Environment: \(analysis.environment)
        Lighting/Image quality: \(analysis.imageQuality)
        Skin tone style note: \(analysis.skinToneStyleNote)
        Style notes: \(analysis.summary)
        Confidence: \(confidence)
        """
    }

    private func aiScoreRatingTitle(for score: Int) -> String {
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
            return "Needs Work"
        }
    }

    private func stylistReply(to question: String) -> String {
        let lower = question.lowercased()
        let base = "Based on your style memory: \(favoriteColors), \(favoriteBrands), \(budget), shirt \(shirtSize), pants \(pantsSize), shoes \(shoeSize)."

        if lower.contains("shoe") {
            return "\(base) For shoes, start with clean white sneakers for casual looks or black loafers for work/church. If the outfit is dark, a brighter sneaker can improve contrast."
        }

        if lower.contains("shop") || lower.contains("buy") {
            return "\(base) I would check your closet first. Only shop for pieces that complete several outfits, fit your budget, and match your favorite colors."
        }

        if lower.contains("score") || lower.contains("improve") {
            return "\(base) To improve the score, sharpen one fit detail, add one intentional accessory, and make sure the shoes create enough contrast with the pants."
        }

        if lower.contains("church") {
            return "\(base) For church, choose a polished shirt, dark denim or chinos, loafers or clean sneakers, and one simple accessory. Keep the look respectful and comfortable."
        }

        if lower.contains("wedding") || lower.contains("event") {
            return "\(base) For an event, match the dress code first, then choose polished shoes and a clean color palette. If it is traditional wear, accessories and fabric coordination matter more than western casual rules."
        }

        return "\(base) Today I would build around a clean top, dark denim or chinos, polished shoes, and one accessory. Scan the outfit when ready so StyleMatch Pro can score the exact look."
    }

    private func loadChatMessages() {
        guard !aiStylistConversationData.isEmpty,
              let decoded = try? JSONDecoder().decode([AIStylistChatMessage].self, from: aiStylistConversationData) else {
            chatMessages = []
            return
        }

        chatMessages = decoded.filter { !isLegacyPresetChatMessage($0) }
        if chatMessages.count != decoded.count {
            saveChatMessages()
        }
    }

    private func saveChatMessages() {
        let limitedMessages = Array(chatMessages.suffix(100))
        guard let data = try? JSONEncoder().encode(limitedMessages) else { return }
        aiStylistConversationData = data
    }

    private func isLegacyPresetChatMessage(_ message: AIStylistChatMessage) -> Bool {
        guard message.role == .stylist else { return false }
        return message.text.contains("Today I would build around a clean top")
            || message.text.contains("Based on your style memory:")
            || message.text.contains("I’d build from your strongest base")
            || message.text.contains("Tell me the occasion and I’ll tune it")
    }

    private func aiAdviceRow(icon: String, title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(AppTab.ai.palette.accent)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func aiMiniMetric(title: String, detail: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(AppTab.ai.palette.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.bold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(detail)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func aiCheckRow(_ title: String) -> some View {
        Label(title, systemImage: "checkmark.circle.fill")
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(.primary)
    }

    private func compactStatusPill(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(AppTab.ai.palette.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.bold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
                Text(detail)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func briefMetric(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(AppTab.ai.palette.accent)
            Text(value)
                .font(.headline)
                .fontWeight(.bold)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
            Text(title)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func recommendedItem(_ title: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(AppTab.ai.palette.accent)
                .frame(width: 28)
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
            Spacer()
        }
        .padding(10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func reasonRow(_ title: String) -> some View {
        Label(title, systemImage: "checkmark.circle.fill")
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(.primary)
    }

    private func confidenceMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value)
                .font(.system(size: 26, weight: .bold, design: .rounded))
            Text(title)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func aiActionCard(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(AppTab.ai.palette.accent)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.76)
            }
            .frame(maxWidth: .infinity, minHeight: 86, alignment: .topLeading)
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(AppTab.ai.palette.accent.opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func closetInsightRow(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)
            Text(detail)
                .font(.subheadline)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func privacyRow(_ text: String) -> some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .font(.subheadline)
            .foregroundStyle(.primary)
            .lineLimit(2)
            .minimumScaleFactor(0.82)
    }

    private var displayName: String {
        StyleMatchGreetingBuilder.firstName(from: profileName) ?? ""
    }

    private var dayGreeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return "morning" }
        if hour < 17 { return "afternoon" }
        return "evening"
    }

    private var weatherTemperatureText: String {
        let trimmed = weather.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "74°F" : trimmed
    }

    private var weatherConditionText: String {
        let trimmed = weatherCondition.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.localizedCaseInsensitiveContains("mild") {
            return weatherSource.localizedCaseInsensitiveContains("live") ? "Live weather" : "Mild"
        }
        return trimmed
    }

    private var closetItems: [ClosetItem] {
        cachedClosetItems
    }

    private var latestStoredScan: SafeHomeStoredScan? {
        cachedLatestStoredScan
    }

    private var recentStyleScore: Int {
        latestStoredScan?.score ?? 92
    }

    private var expectedStyleScore: Int {
        min(98, max(82, recentStyleScore + (shareAppContextWithChatGPT ? 2 : 0)))
    }

    private var aiConfidence: Int {
        min(98, 82 + min(savedScanCount, 8) + min(savedClosetCount, 8) + (shareAppContextWithChatGPT ? 4 : 0))
    }

    private var recommendedStyle: String {
        if plannedOccasion.localizedCaseInsensitiveContains("church") {
            return "Polished Traditional or Smart Casual"
        }
        if plannedOccasion.localizedCaseInsensitiveContains("work") {
            return "Business Casual"
        }
        if plannedOccasion.localizedCaseInsensitiveContains("wedding") {
            return "Formal Event"
        }
        return "Smart Casual"
    }

    private var profileCompleteness: Int {
        let fields = [
            shirtSize, pantsSize, shoeSize, budget, favoriteColors, favoriteBrands,
            plannedOccasion, stylePreferences, neckSize, sleeveLength
        ]
        let completed = fields.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
        return min(100, max(10, Int((Double(completed) / Double(fields.count)) * 100)))
    }

    private var missingProfileFields: [String] {
        var fields: [String] = []
        if neckSize.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { fields.append("Neck Size") }
        if sleeveLength.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { fields.append("Sleeve Length") }
        if favoriteBrands.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { fields.append("Favorite Stores") }
        if weatherSource.localizedCaseInsensitiveContains("saved") { fields.append("Location") }
        return fields
    }

    private var closetFirstRecommendation: String {
        if savedClosetCount == 0 {
            return "Add a few closet items first so StyleMatch Pro can recommend outfits you already own before suggesting purchases."
        }
        if closetHasShoes && closetHasTop && closetHasPants {
            return "You already own the core pieces for today's outfit. StyleMatch Pro will only suggest shopping when something truly improves the look."
        }
        return "StyleMatch Pro checked your closet first and found one or two gaps before recommending anything new."
    }

    private var closetCheckText: String {
        if closetHasShoes && closetHasTop && closetHasPants {
            return "You already own everything needed for a complete outfit."
        }
        if !closetHasShoes {
            return "Only black loafers or clean sneakers appear to be missing."
        }
        if !closetHasTop {
            return "A crisp shirt would complete more outfits in your closet."
        }
        return "Dark denim or tailored pants would unlock more outfit combinations."
    }

    private var shoppingReasonText: String {
        if savedClosetCount == 0 {
            return "Shopping suggestions become smarter after your closet has a few saved items."
        }
        return "Any recommended item must match your closet, favorite colors, style, and budget."
    }

    private var favoriteOutfitText: String {
        let trimmed = favoriteOutfits.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "No favorite outfit saved yet." : trimmed
    }

    private var dailyStyleTip: String {
        "Neutral colors pair well with one bold accessory. Keep the outfit clean, then let one detail stand out."
    }

    private var closetMissingPieceMessage: String {
        if closetHasShoes && closetHasTop && closetHasPants {
            return "You already own the key pieces. StyleMatch Pro recommends styling what you have before shopping."
        }
        return closetCheckText
    }

    private var closetHasShoes: Bool {
        closetItems.contains { item in
            item.category.localizedCaseInsensitiveContains("shoe") ||
            item.name.localizedCaseInsensitiveContains("shoe") ||
            item.name.localizedCaseInsensitiveContains("sneaker") ||
            item.name.localizedCaseInsensitiveContains("loafer")
        }
    }

    private var closetHasTop: Bool {
        closetItems.contains { item in
            item.category.localizedCaseInsensitiveContains("shirt") ||
            item.category.localizedCaseInsensitiveContains("top") ||
            item.name.localizedCaseInsensitiveContains("shirt") ||
            item.name.localizedCaseInsensitiveContains("polo")
        }
    }

    private var closetHasPants: Bool {
        closetItems.contains { item in
            item.category.localizedCaseInsensitiveContains("pant") ||
            item.category.localizedCaseInsensitiveContains("jean") ||
            item.name.localizedCaseInsensitiveContains("pants") ||
            item.name.localizedCaseInsensitiveContains("jeans") ||
            item.name.localizedCaseInsensitiveContains("chinos")
        }
    }

    private var connectedServicesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("AI Engine", systemImage: "cpu.fill")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(AppTab.ai.palette.accent)

            VStack(alignment: .leading, spacing: 6) {
                Text("StyleMatch Pro AI")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Powered by \(selectedAssistantDisplayName)")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                Text("Future AI engines can be supported internally without making the main experience feel like switching apps.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))

            Button {
                showAISettings = true
            } label: {
                Label("Switch AI", systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .padding()
        .background(AppTab.ai.palette.accent.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(AppTab.ai.palette.accent.opacity(0.22), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var aiSettingsScreen: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Choose AI Assistant", systemImage: "sparkles")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("StyleMatch Pro stays the main experience. You can choose which assistant powers your stylist.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
            }

            ForEach(PreferredAIAssistant.allCases) { assistant in
                aiAssistantChoiceRow(assistant)
            }

            Label("You can change this anytime. Personal Style Memory stays controlled by you.", systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .appCard(.ai)
    }

    private func aiAssistantChoiceRow(_ assistant: PreferredAIAssistant) -> some View {
        let isSelected = assistant.rawValue == preferredAIAssistant
        let isConnected = connectedAssistantSet.contains(assistant.rawValue) || isSelected

        return Button {
            preferredAIAssistant = assistant.rawValue
            var connected = connectedAssistantSet
            connected.insert(assistant.rawValue)
            connectedAIAssistants = connected.sorted().joined(separator: ",")
            message = "\(assistantDisplayName(assistant)) selected for StyleMatch Pro AI."
        } label: {
            HStack(spacing: 12) {
                Image(systemName: assistantIcon(assistant))
                    .font(.title3)
                    .foregroundStyle(assistantTint(assistant))
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 3) {
                    Text(assistantDisplayName(assistant))
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)

                    Text(isSelected ? "Active" : (isConnected ? "Available" : "Set up when ready"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? .green : .secondary)
            }
            .padding(12)
            .background(isSelected ? AppTab.ai.palette.accent.opacity(0.12) : Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private var selectedAssistant: PreferredAIAssistant {
        PreferredAIAssistant(rawValue: preferredAIAssistant) ?? .chatGPT
    }

    private var selectedAssistantDisplayName: String {
        assistantDisplayName(selectedAssistant)
    }

    private var betaChatGPTSubtitle: String {
        if betaAIConnectionVerified {
            return "ChatGPT Live is active on this phone."
        }

        if openAIKeyIsSaved {
            return "ChatGPT key is saved. Tap Activate ChatGPT to test the live connection."
        }

        return "Paste your private OpenAI API key to test live ChatGPT."
    }

    private func loadBetaOpenAIKey() {
        openAIKeyInput = OpenAIKeychain.loadAPIKey() ?? ""
        openAIKeyIsSaved = !openAIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        betaAIConnectionVerified = false
        if openAIModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || openAIModel == "gpt-5.5" {
            openAIModel = "gpt-4o-mini"
        }
        betaAIStatus = openAIKeyIsSaved ? "Key saved. Tap Activate ChatGPT to test ChatGPT Live." : ""
    }

    private func saveBetaOpenAIKey() {
        do {
            try OpenAIKeychain.saveAPIKey(openAIKeyInput)
            preferredAIAssistant = PreferredAIAssistant.chatGPT.rawValue
            var connected = connectedAssistantSet
            connected.insert(PreferredAIAssistant.chatGPT.rawValue)
            connectedAIAssistants = connected.sorted().joined(separator: ",")
            openAIKeyInput = OpenAIKeychain.loadAPIKey() ?? openAIKeyInput
            openAIKeyIsSaved = !openAIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            betaAIConnectionVerified = false
            betaAIStatus = openAIKeyIsSaved ? "Testing ChatGPT Live connection..." : "Paste your key and tap Activate ChatGPT."
            verifyBetaOpenAIConnection()
        } catch {
            #if DEBUG
            print("[Founder Beta ChatGPT Save] \(error.localizedDescription)")
            #endif
            openAIKeyIsSaved = false
            betaAIConnectionVerified = false
            betaAIStatus = "Could not activate ChatGPT right now. Please check the key and try again."
        }
    }

    private func verifyBetaOpenAIConnection() {
        guard let savedKey = OpenAIKeychain.loadAPIKey()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !savedKey.isEmpty else {
            betaAIConnectionVerified = false
            betaAIStatus = "Paste your key and tap Activate ChatGPT."
            return
        }

        let client = OpenAIStylistClient(apiKey: savedKey, model: openAIModel)
        let profile = StyleMatchStylistProfile(
            name: displayName,
            favoriteColors: favoriteColors,
            favoriteBrands: favoriteBrands,
            preferredFit: fitPreference,
            budget: budget,
            sizeProfile: "Shirt \(shirtSize); pants \(pantsSize); shoes \(shoeSize)",
            stylePreferences: stylePreferences,
            occasions: plannedOccasion,
            weather: "\(weatherConditionText), \(weatherTemperatureText)",
            weatherPreferences: "\(weatherConditionText), \(weatherTemperatureText)",
            dressCode: plannedOccasion,
            shoppingHabits: "Budget \(budget); favorite brands \(favoriteBrands)",
            pastOutfitRatings: "\(recentStyleScore)/100 recent score, \(savedScanCount) saved scan\(savedScanCount == 1 ? "" : "s")",
            frequentlyWornOutfits: favoriteOutfits,
            pastPurchases: "White Oxford shirt, black leather belt",
            favoriteOutfits: favoriteOutfits,
            closetInventory: closetItems.prefix(12).map { "\($0.color) \($0.name)" }.joined(separator: ", "),
            appContextSharingEnabled: false,
            appContext: "ChatGPT connection test."
        )

        Task {
            do {
                _ = try await client.askStylist(
                    profile: profile,
                    question: "Reply with one short sentence confirming StyleMatch Pro ChatGPT is connected."
                )
                await MainActor.run {
                    betaAIConnectionVerified = true
                    betaAIStatus = "ChatGPT Live tested successfully. Ask My Stylist will now use it."
                }
            } catch {
                #if DEBUG
                print("[Founder Beta ChatGPT Verify] \(error.localizedDescription)")
                #endif
                await MainActor.run {
                    betaAIConnectionVerified = false
                    betaAIStatus = "Key saved, but ChatGPT could not answer yet. Please try Activate ChatGPT again."
                }
            }
        }
    }

    private func deleteBetaOpenAIKey() {
        do {
            try OpenAIKeychain.deleteAPIKey()
            openAIKeyInput = ""
            openAIKeyIsSaved = false
            betaAIConnectionVerified = false
            betaAIStatus = "ChatGPT key removed from this phone."
        } catch {
            betaAIStatus = "Could not remove key: \(error.localizedDescription)"
        }
    }

    private var connectedAssistantSet: Set<String> {
        Set(connectedAIAssistants.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) })
    }

    private func assistantDisplayName(_ assistant: PreferredAIAssistant) -> String {
        switch assistant {
        case .siri:
            return "Siri AI"
        case .chatGPT:
            return "ChatGPT"
        case .gemini:
            return "Gemini AI"
        case .claude:
            return "Claude AI"
        case .perplexity:
            return "Perplexity AI"
        }
    }

    private func assistantIcon(_ assistant: PreferredAIAssistant) -> String {
        switch assistant {
        case .siri:
            return "waveform.circle.fill"
        case .chatGPT:
            return "bubble.left.and.bubble.right.fill"
        case .gemini:
            return "sparkles"
        case .claude:
            return "text.bubble.fill"
        case .perplexity:
            return "magnifyingglass.circle.fill"
        }
    }

    private func assistantTint(_ assistant: PreferredAIAssistant) -> Color {
        switch assistant {
        case .siri:
            return .blue
        case .chatGPT:
            return .black
        case .gemini:
            return .purple
        case .claude:
            return .orange
        case .perplexity:
            return .teal
        }
    }

    private func serviceRow(title: String, connected: Bool, active: Bool, tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: connected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(connected ? tint : .secondary)

            Text(title)
                .font(.headline)
                .fontWeight(active ? .bold : .semibold)
                .foregroundStyle(connected ? .primary : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Spacer()
        }
    }

    private func aiPillButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.headline)

                Text(title)
                    .font(.headline)
                    .fontWeight(.bold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 58)
            .padding(.horizontal, 20)
            .background(Color.black)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct SafeHomeView: View {
    @Binding var selectedTab: AppTab
    var feedbackPrompt: ScheduledFeedbackPrompt?
    var onHomeAppear: () -> Void = {}
    var onFeedbackWornAnswer: (ScheduledFeedbackPrompt, Bool) -> Void = { _, _ in }
    var onFeedbackLikedAnswer: (ScheduledFeedbackPrompt, Bool) -> Void = { _, _ in }
    var onFeedbackDislikeReason: (ScheduledFeedbackPrompt, DislikeReason) -> Void = { _, _ in }
    var onFeedbackDismiss: () -> Void = {}
    var onFeedbackComplete: () -> Void = {}
    @AppStorage("selectedAppTheme") private var selectedAppTheme = StyleMatchAppTheme.system.rawValue
    @AppStorage("profileName") private var profileName = ""
    @AppStorage("weather") private var weather = "84°F"
    @AppStorage("weatherCondition") private var weatherCondition = "Sunny"
    @AppStorage("weatherSource") private var weatherSource = "Saved"
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
    @State private var selectedProgressDetail: SafeHomeProgressDetail?
    @State private var cachedHomeClosetItems: [ClosetItem] = []
    @State private var cachedHomeLatestScan: SafeHomeStoredScan?
    @State private var cachedHomeWishlistCount = 0
    @State private var navigationSearchText = ""
    @State private var debouncedNavigationSearchText = ""
    @State private var navigationSearchTask: Task<Void, Never>?

    private var activeTheme: StyleMatchAppTheme {
        StyleMatchAppTheme(rawValue: selectedAppTheme) ?? .system
    }

    private var isBlackAMOLED: Bool {
        activeTheme == .blackAMOLED
    }

    private var pageBackground: Color {
        isBlackAMOLED ? .black : Color(red: 0.97, green: 0.94, blue: 0.88)
    }

    private var cardBackground: Color {
        isBlackAMOLED ? Color(hex: 0x080808) : .white
    }

    private var tileBackground: Color {
        isBlackAMOLED ? Color(hex: 0x111111) : Color(red: 0.98, green: 0.96, blue: 0.92)
    }

    private var textColor: Color {
        isBlackAMOLED ? .white : .black
    }

    private var secondaryTextColor: Color {
        isBlackAMOLED ? Color(hex: 0xB8B8B8) : Color(red: 0.34, green: 0.34, blue: 0.38)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Good \(greeting), \(displayName) 👋")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundStyle(textColor)
                                .lineLimit(2)
                                .minimumScaleFactor(0.78)

                            Text("Ready to build today's best outfit?")
                                .font(.headline)
                                .foregroundStyle(secondaryTextColor)
                        }

                        Spacer(minLength: 8)

                        Button {
                            selectedTab = .profile
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .font(.headline)
                                .foregroundStyle(textColor)
                                .frame(width: 44, height: 44)
                                .background(tileBackground)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open Profile")
                    }

                    topStyleScoreCard

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        WeatherStylingButton {
                            safeSignal(icon: "cloud.sun.fill", text: "\(weatherTemperatureText) \(weatherSourceText)", tint: Color(red: 0.86, green: 0.54, blue: 0.12))
                        }
                        safeSignal(icon: "person.fill.checkmark", text: "Casual Friday", tint: AppTab.closet.palette.accent)
                        safeSignal(icon: "tshirt.fill", text: "\(closetItemCountText) Closet Items", tint: AppTab.scan.palette.accent)
                        safeSignal(icon: "sparkles", text: "AI Confidence: High", tint: AppTab.ai.palette.accent)
                    }
                }
                .padding(16)
                .background(cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .padding(.top, 24)

                if let feedbackPrompt {
                    OutfitFeedbackCard(
                        prompt: feedbackPrompt,
                        onWornAnswer: onFeedbackWornAnswer,
                        onLikedAnswer: onFeedbackLikedAnswer,
                        onDislikeReason: onFeedbackDislikeReason,
                        onDismissPrompt: onFeedbackDismiss,
                        onComplete: onFeedbackComplete
                    )
                }

                smartNavigationCard

                homeWeatherStylingCard

                safeQuickActionsSection

                styleBriefCard

                safeContinueCard

                VStack(alignment: .leading, spacing: 4) {
                    Text("Style Match Pro")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(textColor)

                    Text("Your personal outfit command center.")
                        .font(.headline)
                        .foregroundStyle(secondaryTextColor)
                }

                dailyRecommendationCard

                AIStyleInsightCard(
                    tab: .ai,
                    screen: "Home",
                    title: "Personal AI Stylist",
                    prompt: "Give me one warm, respectful style move I should make today using my closet, profile, weather, sizes, and recent scans.",
                    fallbackAdvice: "Your AI Stylist learns your wardrobe, favorite colors, sizes, budget, and style preferences to give personalized outfit recommendations every day.",
                    extraContext: "The customer is on the first screen and needs a confident next step."
                )

                aiMemoryStatusCard

                styleProgressCard

                motivationCard
            }
            .padding(20)
            .padding(.bottom, 150)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(pageBackground.ignoresSafeArea())
        .onAppear {
            refreshHomeCache()
            onHomeAppear()
        }
        .styleMatchOnChange(of: closetItemsData) { _ in refreshHomeCache() }
        .styleMatchOnChange(of: outfitScanHistoryData) { _ in refreshHomeCache() }
        .styleMatchOnChange(of: wishlistProductNamesData) { _ in refreshHomeCache() }
        .sheet(item: $selectedProgressDetail) { detail in
            NavigationStack {
                VStack(alignment: .leading, spacing: 18) {
                    Label(detail.title, systemImage: detail.icon)
                        .font(.title)
                        .fontWeight(.bold)

                    Text(detail.value)
                        .font(.system(size: 44, weight: .bold, design: .rounded))

                    Text(detail.explanation)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineSpacing(4)

                    Button {
                        selectedTab = detail.tab
                        selectedProgressDetail = nil
                    } label: {
                        Label(detail.actionTitle, systemImage: "chevron.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Spacer()
                }
                .padding()
                .appScreenBackground(detail.tab)
                .navigationTitle("Style Progress")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            selectedProgressDetail = nil
                        }
                    }
                }
            }
        }
    }

    private var smartNavigationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.headline)
                    .foregroundStyle(AppTab.home.palette.accent)

                TextField("Search StyleMatch Pro", text: $navigationSearchText)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .font(.headline)
                    .foregroundStyle(textColor)
                    .submitLabel(.search)

                if !navigationSearchText.isEmpty {
                    Button {
                        navigationSearchText = ""
                        debouncedNavigationSearchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(secondaryTextColor)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(12)
            .background(tileBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))

            if navigationSearchResults.isEmpty && !debouncedNavigationSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("No matches yet")
                        .font(.headline)
                        .foregroundStyle(textColor)

                    Text("Try another word, or scan an item so StyleMatch Pro has more to find.")
                        .font(.subheadline)
                        .foregroundStyle(secondaryTextColor)

                    Button {
                        selectedTab = .scan
                    } label: {
                        Label("Scan an item", systemImage: "camera.fill")
                            .font(.subheadline)
                            .fontWeight(.bold)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(StyleMatchSearchSection.allCases, id: \.self) { section in
                        let results = navigationSearchResults.filter { $0.section == section }
                        if !results.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(section.title)
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundStyle(secondaryTextColor)

                                ForEach(results.prefix(4)) { result in
                                    Button {
                                        routeToSearchResult(result)
                                    } label: {
                                        HStack(spacing: 10) {
                                            Image(systemName: searchIcon(for: result))
                                                .font(.subheadline)
                                                .fontWeight(.bold)
                                                .foregroundStyle(AppTab.home.palette.accent)
                                                .frame(width: 30, height: 30)
                                                .background(AppTab.home.palette.accent.opacity(0.12))
                                                .clipShape(Circle())

                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(result.title)
                                                    .font(.subheadline)
                                                    .fontWeight(.bold)
                                                    .foregroundStyle(textColor)
                                                    .lineLimit(1)

                                                Text(result.subtitle)
                                                    .font(.caption)
                                                    .foregroundStyle(secondaryTextColor)
                                                    .lineLimit(1)
                                            }

                                            Spacer(minLength: 0)

                                            Image(systemName: "chevron.right")
                                                .font(.caption)
                                                .foregroundStyle(secondaryTextColor)
                                        }
                                        .padding(10)
                                        .background(tileBackground)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(AppTab.home.palette.accent.opacity(0.24), lineWidth: 1)
        )
        .styleMatchOnChange(of: navigationSearchText) { newValue in
            scheduleNavigationSearch(for: newValue)
        }
    }

    private var homeWeatherStylingCard: some View {
        WeatherStylingButton {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "cloud.sun.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(Color(red: 0.86, green: 0.54, blue: 0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Weather Styling")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(textColor)

                    Text("\(weatherTemperatureText) • \(weatherConditionText) • \(weatherSourceText)")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(textColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    Text("Tap to refresh live weather and get outfit advice.")
                        .font(.subheadline)
                        .foregroundStyle(secondaryTextColor)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(secondaryTextColor)
            }
            .padding()
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color(red: 0.86, green: 0.54, blue: 0.12).opacity(0.28), lineWidth: 1)
            )
        }
    }

    private var topStyleScoreCard: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Today's Style")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(secondaryTextColor)

                Text(latestScoreText)
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(textColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Text(scoreRatingTitle(for: latestScoreValue))
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(textColor)

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
                    .foregroundStyle(secondaryTextColor)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(14)
        .background(tileBackground)
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
                        .foregroundStyle(textColor)

                    Text("Your personal stylist checked the day before you get dressed.")
                        .font(.subheadline)
                        .foregroundStyle(secondaryTextColor)
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(AppTab.home.palette.accent.opacity(0.24), lineWidth: 1)
        )
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
                    .foregroundStyle(secondaryTextColor)

                Text(detail)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(textColor)
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
                    .foregroundStyle(Color(red: 0.86, green: 0.54, blue: 0.12))
                    .frame(width: 48, height: 48)
                    .background(Color(red: 0.86, green: 0.54, blue: 0.12).opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 5) {
                    Text("Today's Style Tip")
                        .font(.headline)
                        .foregroundStyle(textColor)

                    Text("Neutral colors pair well with bold accessories.")
                        .font(.subheadline)
                        .foregroundStyle(secondaryTextColor)
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
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color(red: 0.86, green: 0.54, blue: 0.12).opacity(0.24), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var safeQuickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(textColor)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                safeQuickAction(title: "Scan", icon: "camera.fill", tab: .scan, tint: AppTab.scan.palette.accent)
                safeQuickAction(title: "Ask AI", icon: "sparkles", tab: .ai, tint: AppTab.ai.palette.accent)
                safeQuickAction(title: "Closet", icon: "tshirt.fill", tab: .closet, tint: AppTab.closet.palette.accent)
                safeQuickAction(title: "Shop", icon: "bag.fill", tab: .shop, tint: AppTab.shop.palette.accent)
            }
        }
        .padding()
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func safeQuickAction(title: String, icon: String, tab: AppTab, tint: Color) -> some View {
        Button {
            selectedTab = tab
        } label: {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(tint)
                    .frame(width: 40, height: 40)
                    .background(tint.opacity(0.14))
                    .clipShape(Circle())

                Text(title)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(textColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity, minHeight: 84)
            .background(tileBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private var styleProgressCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Style Progress", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.headline)
                    .foregroundStyle(textColor)

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
                progressMetric(title: "Most Worn", value: mostWornText, icon: "shoe.2.fill", tint: Color(red: 0.36, green: 0.34, blue: 0.86))
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(AppTab.home.palette.accent.opacity(0.24), lineWidth: 1)
        )
    }

    private func progressMetric(title: String, value: String, icon: String, tint: Color) -> some View {
        Button {
            selectedProgressDetail = progressDetail(title: title, value: value, icon: icon)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundStyle(tint)

                Text(title)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(secondaryTextColor)
                    .lineLimit(1)

                Text(value)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(textColor)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
            }
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            .padding(12)
            .background(tileBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private func progressDetail(title: String, value: String, icon: String) -> SafeHomeProgressDetail {
        switch title {
        case "Current Score":
            return SafeHomeProgressDetail(title: title, value: value, icon: icon, explanation: "This is your most recent saved outfit score. Open Scan to review history, compare outfits, rescan, favorite, rename, or delete scans.", actionTitle: "Open Scan History", tab: .scan)
        case "Closet":
            return SafeHomeProgressDetail(title: title, value: value, icon: icon, explanation: "Your closet count helps StyleMatch Pro recommend outfits using pieces you already own before suggesting anything new.", actionTitle: "Open Closet", tab: .closet)
        case "Favorite Color":
            return SafeHomeProgressDetail(title: title, value: value, icon: icon, explanation: "Favorite colors help your AI Stylist build outfits that feel more personal and consistent.", actionTitle: "Ask AI About Colors", tab: .ai)
        default:
            return SafeHomeProgressDetail(title: title, value: value, icon: icon, explanation: "Most worn pieces help StyleMatch Pro understand your real everyday style.", actionTitle: "Ask AI Stylist", tab: .ai)
        }
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
                        .foregroundStyle(textColor)

                    Text("Style Match Pro gets smarter as you scan, save, and shop.")
                        .font(.caption)
                        .foregroundStyle(secondaryTextColor)
                }
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                safeMemoryItem(title: "Favorite Color", value: favoriteColorText)
                safeMemoryItem(title: "Favorite Fit", value: favoriteFitText)
                safeMemoryItem(title: "Budget", value: budgetLevelText)
                safeMemoryItem(title: "Closet Items", value: memoryClosetCountText)
                safeMemoryItem(title: "Favorite Brands", value: favoriteBrandListText)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(AppTab.ai.palette.accent.opacity(0.24), lineWidth: 1)
        )
    }

    private func safeMemoryItem(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: "checkmark.circle.fill")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(secondaryTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(textColor)
                .lineLimit(3)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
        .padding(12)
        .background(AppTab.ai.palette.accent.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var dailyRecommendationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(AppTab.ai.palette.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Today's Recommendation")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(textColor)

                    Text("Ready-made outfit idea")
                        .font(.subheadline)
                        .foregroundStyle(secondaryTextColor)
                }

                Spacer()
            }

            VStack(alignment: .leading, spacing: 9) {
                recommendationLine("Wear your navy polo")
                recommendationLine("Pair with beige chinos")
                recommendationLine("White sneakers")
            }

            HStack(spacing: 10) {
                recommendationPill(title: "Weather", value: "84°", icon: "cloud.sun.fill", tint: Color(red: 0.86, green: 0.54, blue: 0.12))
                recommendationPill(title: "Style Score", value: "95", icon: "star.fill", tint: AppTab.ai.palette.accent)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(AppTab.ai.palette.accent.opacity(0.24), lineWidth: 1)
        )
    }

    private func recommendationLine(_ text: String) -> some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(textColor)
    }

    private func recommendationPill(title: String, value: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(secondaryTextColor)

                Text(value)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(textColor)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 50)
        .padding(.horizontal, 10)
        .background(tileBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var safeContinueCard: some View {
        let task = safeContinueTask

        return Button {
            selectedTab = task.tab
        } label: {
            HStack(spacing: 14) {
                Image(systemName: task.icon)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background(task.tint)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Continue")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(secondaryTextColor)

                    Text(task.title)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(textColor)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)

                    Text(task.detail)
                        .font(.subheadline)
                        .foregroundStyle(secondaryTextColor)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(secondaryTextColor)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(task.tint.opacity(0.24), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func safeSignal(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(tint.opacity(0.14))
                .clipShape(Circle())

            Text(text)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(textColor)
                .lineLimit(2)
                .minimumScaleFactor(0.78)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
        .padding(.horizontal, 10)
        .background(tileBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func safeAction(title: String, subtitle: String, icon: String, tab: AppTab) -> some View {
        Button {
            selectedTab = tab
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(tab.palette.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(textColor)

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(secondaryTextColor)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(secondaryTextColor)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
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

    private var weatherTemperatureText: String {
        let pieces = weather.components(separatedBy: CharacterSet.whitespacesAndNewlines)
        if let temperature = pieces.first(where: { $0.contains("°") }) {
            return temperature.contains("F") || temperature.contains("C") ? temperature : "\(temperature)F"
        }

        return "84°F"
    }

    private var weatherConditionText: String {
        let trimmed = weatherCondition.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == "Mild" ? "Sunny" : trimmed
    }

    private var weatherSourceText: String {
        weatherSource.localizedCaseInsensitiveContains("live") ? "Live" : "Saved"
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

        if whiteItems + gymItems > 0 {
            return "Check \(whiteItems + gymItems) light or gym item\(whiteItems + gymItems == 1 ? "" : "s") before wearing."
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

    private var latestScoreText: String {
        cachedHomeLatestScan.map { "\($0.score)" } ?? "92"
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

    private var latestScan: SafeHomeStoredScan? {
        cachedHomeLatestScan
    }

    private var closetItemCountText: String {
        cachedHomeClosetItems.isEmpty ? "147" : "\(cachedHomeClosetItems.count)"
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
        cachedHomeClosetItems
    }

    private var wishlistCount: Int {
        cachedHomeWishlistCount
    }

    private var navigationSearchResults: [StyleMatchSearchDocument] {
        DefaultSearchIndexService().search(debouncedNavigationSearchText, in: navigationSearchContext)
    }

    private var navigationSearchContext: StyleMatchSearchContext {
        StyleMatchSearchContext(
            closetItems: cachedHomeClosetItems,
            outfitMemories: OutfitMemoryStore().memories
        )
    }

    private func scheduleNavigationSearch(for query: String) {
        navigationSearchTask?.cancel()
        navigationSearchTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                debouncedNavigationSearchText = query
            }
        }
    }

    private func searchIcon(for result: StyleMatchSearchDocument) -> String {
        switch result.section {
        case .closet:
            return "tshirt.fill"
        case .outfitHistory:
            return "clock.arrow.circlepath"
        case .favorites:
            return "heart.fill"
        case .appScreens:
            switch result.routeID {
            case "weather":
                return "cloud.sun.fill"
            case "ai":
                return "sparkles"
            case "shop":
                return "bag.fill"
            case "profile", "settings":
                return "person.crop.circle.fill"
            case "scan":
                return "camera.fill"
            default:
                return "square.grid.2x2.fill"
            }
        }
    }

    private func routeToSearchResult(_ result: StyleMatchSearchDocument) {
        switch result.routeID {
        case "closet":
            selectedTab = .closet
        case "scan":
            selectedTab = .scan
        case "shop":
            selectedTab = .shop
        case "ai", "weather":
            selectedTab = .ai
        case "profile", "settings":
            selectedTab = .profile
        case "favorites":
            selectedTab = .closet
        default:
            selectedTab = .home
        }
    }

    private func refreshHomeCache() {
        if !closetItemsData.isEmpty,
           let items = try? JSONDecoder().decode([ClosetItem].self, from: closetItemsData) {
            cachedHomeClosetItems = items
        } else {
            cachedHomeClosetItems = []
        }

        if !outfitScanHistoryData.isEmpty,
           let history = try? JSONDecoder().decode([String: SafeHomeStoredScan].self, from: outfitScanHistoryData) {
            cachedHomeLatestScan = history.values.max { $0.firstScannedAt < $1.firstScannedAt }
        } else {
            cachedHomeLatestScan = nil
        }

        if !wishlistProductNamesData.isEmpty,
           let names = try? JSONDecoder().decode([String].self, from: wishlistProductNamesData) {
            cachedHomeWishlistCount = names.count
        } else {
            cachedHomeWishlistCount = 0
        }
    }

    private var safeContinueTask: SafeHomeContinueTask {
        if closetItemCount == 0 {
            return SafeHomeContinueTask(
                title: "Finish adding your closet",
                detail: "Save your best pieces so Style Match Pro can style what you already own.",
                icon: "tshirt.fill",
                tint: AppTab.closet.palette.accent,
                tab: .closet
            )
        }

        if let latestScan {
            return SafeHomeContinueTask(
                title: "Continue your last outfit",
                detail: "Open your saved \(latestScan.score) \(scoreRatingTitle(for: latestScan.score)) outfit scan.",
                icon: "camera.viewfinder",
                tint: AppTab.scan.palette.accent,
                tab: .scan
            )
        }

        if wishlistCount > 0 {
            return SafeHomeContinueTask(
                title: "Continue shopping",
                detail: "Review \(wishlistCount) saved item\(wishlistCount == 1 ? "" : "s") in Smart Shopping.",
                icon: "bag.fill",
                tint: AppTab.shop.palette.accent,
                tab: .shop
            )
        }

        return SafeHomeContinueTask(
            title: "Review today's outfit",
            detail: "Ask your AI Stylist what works best for today.",
            icon: "sun.max.fill",
            tint: AppTab.ai.palette.accent,
            tab: .ai
        )
    }
}

private struct SafeHomeStoredScan: Codable {
    let score: Int
    let analysis: OutfitAnalysisResult?
    let firstScannedAt: Date

    private enum CodingKeys: String, CodingKey {
        case score
        case analysis
        case firstScannedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        score = try container.decode(Int.self, forKey: .score)
        analysis = try container.decodeIfPresent(OutfitAnalysisResult.self, forKey: .analysis)
        firstScannedAt = try container.decode(Date.self, forKey: .firstScannedAt)
    }
}

private struct AIStylistChatMessage: Identifiable, Codable {
    enum Role: String, Codable {
        case user
        case stylist
    }

    let id: UUID
    let role: Role
    var text: String
    let createdAt: Date
    var edited: Bool
    var editedAt: Date?
    var failedPrompt: String?
    var failureReason: String?

    var isEdited: Bool {
        edited || editedAt != nil
    }

    init(
        id: UUID = UUID(),
        role: Role,
        text: String,
        createdAt: Date = Date(),
        edited: Bool = false,
        editedAt: Date? = nil,
        failedPrompt: String? = nil,
        failureReason: String? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
        self.edited = edited || editedAt != nil
        self.editedAt = editedAt
        self.failedPrompt = failedPrompt
        self.failureReason = failureReason
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case role
        case text
        case createdAt
        case edited
        case editedAt
        case failedPrompt
        case failureReason
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        role = try container.decode(Role.self, forKey: .role)
        text = try container.decode(String.self, forKey: .text)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        editedAt = try container.decodeIfPresent(Date.self, forKey: .editedAt)
        edited = try container.decodeIfPresent(Bool.self, forKey: .edited) ?? (editedAt != nil)
        failedPrompt = try container.decodeIfPresent(String.self, forKey: .failedPrompt)
        failureReason = try container.decodeIfPresent(String.self, forKey: .failureReason)
    }
}

private struct AIStylistChatArchive: Identifiable, Codable {
    let id: UUID
    let archivedAt: Date
    let messages: [AIStylistChatMessage]

    init(id: UUID = UUID(), archivedAt: Date = Date(), messages: [AIStylistChatMessage]) {
        self.id = id
        self.archivedAt = archivedAt
        self.messages = messages
    }
}

private struct SafeHomeContinueTask {
    let title: String
    let detail: String
    let icon: String
    let tint: Color
    let tab: AppTab
}

private struct SafeHomeProgressDetail: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let icon: String
    let explanation: String
    let actionTitle: String
    let tab: AppTab
}

struct WeatherStylingButton<LabelContent: View>: View {
    @ViewBuilder var label: () -> LabelContent
    @State private var showWeatherPanel = false

    var body: some View {
        Button {
            showWeatherPanel = true
        } label: {
            label()
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showWeatherPanel) {
            WeatherStylingPanel()
        }
    }
}

struct WeatherStylingPanel: View {
    @AppStorage("weather") private var weather = "84°F"
    @AppStorage("weatherCondition") private var weatherCondition = "Sunny"
    @AppStorage("weatherCity") private var weatherCity = ""
    @AppStorage("weatherSource") private var weatherSource = "Saved"
    @AppStorage("weatherFeelsLike") private var weatherFeelsLike = ""
    @AppStorage("weatherRainChance") private var weatherRainChance = ""
    @AppStorage("weatherHumidity") private var weatherHumidity = ""
    @AppStorage("weatherWindSpeed") private var weatherWindSpeed = ""
    @AppStorage("weatherUVIndex") private var weatherUVIndex = ""
    @AppStorage("weatherHourlyForecast") private var weatherHourlyForecast = ""
    @AppStorage("weatherDailyForecast") private var weatherDailyForecast = ""
    @AppStorage("weatherAlert") private var weatherAlert = ""
    @AppStorage("weatherErrorMessage") private var weatherErrorMessage = ""
    @AppStorage("liveWeatherUpdatedAt") private var liveWeatherUpdatedAt = 0.0
    @AppStorage("plannedOccasion") private var plannedOccasion = "Work"
    @AppStorage("favoriteColors") private var favoriteColors = "Black, white, navy"
    @AppStorage("shoppingBudget") private var budget = "$50 - $200"
    @StateObject private var manager = StyleMatchLiveWeatherManager()
    @State private var cityDraft = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    currentWeatherCard
                    forecastCard
                    recommendationCard
                    manualCityCard
                    privacyNote
                }
                .padding()
            }
            .scrollContentBackground(.hidden)
            .appScreenBackground(.ai)
            .navigationTitle("Weather Styling")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                cityDraft = weatherCity
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Weather Styling", systemImage: "cloud.sun.fill")
                .font(.title2)
                .fontWeight(.bold)

            Text(statusMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(3)

            if !weatherErrorMessage.isEmpty {
                Label(weatherErrorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding()
        .appCard(.ai)
    }

    private var currentWeatherCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current Weather")
                        .font(.headline)
                        .fontWeight(.bold)
                    Text(locationText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(weatherSource.localizedCaseInsensitiveContains("live") ? "Live" : "Saved")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(weatherSource.localizedCaseInsensitiveContains("live") ? .green : .orange)
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(weatherTemperatureText)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                Text(weatherConditionText)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                weatherMetric("Feels Like", resolved(weatherFeelsLike, fallback: weatherTemperatureText), "thermometer.medium")
                weatherMetric("Rain Chance", resolved(weatherRainChance, fallback: "Not available"), "cloud.rain.fill")
                weatherMetric("Humidity", resolved(weatherHumidity, fallback: "Not available"), "humidity.fill")
                weatherMetric("Wind", resolved(weatherWindSpeed, fallback: "Not available"), "wind")
                weatherMetric("UV", resolved(weatherUVIndex, fallback: "Not available"), "sun.max.fill")
                weatherMetric("Updated", lastUpdatedText, "clock.fill")
            }

            if isWeatherStale {
                Label("Weather may be outdated. Tap Refresh.", systemImage: "clock.badge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding()
        .appCard(.ai)
    }

    private var forecastCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Today Forecast", systemImage: "calendar")
                .font(.headline)
                .fontWeight(.bold)

            Text(resolved(weatherHourlyForecast, fallback: "Hourly forecast will appear after live weather refresh."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(3)

            Text(resolved(weatherDailyForecast, fallback: "Daily forecast will appear after live weather refresh."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(3)

            if !weatherAlert.isEmpty {
                Label(weatherAlert, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.orange)
            }
        }
        .padding()
        .appCard(.ai)
    }

    private var recommendationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Recommended For Today", systemImage: "tshirt.fill")
                    .font(.headline)
                    .fontWeight(.bold)
                Spacer()
                Text("\(weatherMatchScore)/100")
                    .font(.title2)
                    .fontWeight(.bold)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(weatherRecommendations, id: \.self) { item in
                    Label(item, systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("Why")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)

                ForEach(weatherReasons, id: \.self) { reason in
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                Button {
                    manager.refresh()
                } label: {
                    Label(manager.isRefreshing ? "Refreshing" : "Refresh Weather", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(manager.isRefreshing)

                Button {
                    cityDraft = weatherCity
                } label: {
                    Label("Change City", systemImage: "mappin.and.ellipse")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .padding()
        .appCard(.ai)
    }

    private var manualCityCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Manual City")
                .font(.headline)
                .fontWeight(.bold)

            TextField("City, State", text: $cityDraft)
                .textInputAutocapitalization(.words)
                .textFieldStyle(.roundedBorder)

            Button {
                manager.refresh(city: cityDraft)
            } label: {
                Label("Use This City", systemImage: "location.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Text("If location permission is off, a saved city still gives guest users weather-based outfit advice.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .appCard(.ai)
    }

    private var privacyNote: some View {
        Label("Based on current available weather. Weather can change, so StyleMatch Pro shows the last updated time and avoids promising perfect accuracy.", systemImage: "lock.shield")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineSpacing(3)
            .padding()
            .appCard(.ai, radius: 12)
    }

    private func weatherMetric(_ title: String, _ value: String, _ icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(AppTab.ai.palette.accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func resolved(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private var weatherTemperatureText: String {
        let trimmed = weather.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Not available" : trimmed
    }

    private var weatherConditionText: String {
        let trimmed = weatherCondition.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Weather unavailable" : trimmed
    }

    private var locationText: String {
        let city = weatherCity.trimmingCharacters(in: .whitespacesAndNewlines)
        return city.isEmpty ? "Current location or saved city" : city
    }

    private var lastUpdatedText: String {
        guard liveWeatherUpdatedAt > 0 else {
            return "Not updated yet"
        }

        let date = Date(timeIntervalSince1970: liveWeatherUpdatedAt)
        if Date().timeIntervalSince(date) < 120 {
            return "Updated just now"
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private var isWeatherStale: Bool {
        guard liveWeatherUpdatedAt > 0 else {
            return true
        }

        return Date().timeIntervalSince(Date(timeIntervalSince1970: liveWeatherUpdatedAt)) > 3600
    }

    private var statusMessage: String {
        if weatherSource.localizedCaseInsensitiveContains("live") {
            return "Based on current weather. Last updated: \(lastUpdatedText)."
        }
        if weatherCity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Add a city or allow location to receive weather-based outfit advice."
        }
        return "Live weather is unavailable. Showing last updated weather."
    }

    private var weatherMatchScore: Int {
        let lowered = "\(weatherCondition) \(weatherRainChance) \(weatherWindSpeed) \(weatherUVIndex)".lowercased()
        if lowered.contains("storm") || lowered.contains("severe") { return 76 }
        if lowered.contains("rain") || lowered.contains("snow") || lowered.contains("wind") { return 86 }
        if lowered.contains("hot") || lowered.contains("cold") { return 88 }
        return 94
    }

    private var weatherRecommendations: [String] {
        let context = "\(weatherCondition) \(weather) \(weatherRainChance) \(weatherUVIndex)".lowercased()
        if !weatherAlert.isEmpty {
            return ["Prioritize safety-focused clothing", "Weather-ready shoes", "Protective outer layer", "Avoid delicate fabrics"]
        }
        if context.contains("rain") || context.contains("drizzle") || context.contains("storm") {
            return ["Rain jacket or water-resistant layer", "Dark denim or chinos", "Waterproof shoes", "Umbrella or covered bag"]
        }
        if context.contains("hot") || context.contains("humid") || context.contains("90") {
            return ["Breathable shirt or polo", "Light chinos or shorts", "Loafers, clean sneakers, or sandals", "Lighter colors when possible"]
        }
        if context.contains("cold") || context.contains("snow") || context.contains("40") {
            return ["Sweater, hoodie, jacket, or coat", "Warmer pants", "Boots or closed shoes", "Heavier fabric layers"]
        }
        if context.contains("uv") || context.contains("sunny") {
            return ["Navy polo or white Oxford shirt", "Dark denim or chinos", "Clean sneakers or loafers", "Optional hat or sunglasses"]
        }
        return ["Navy polo or white Oxford shirt", "Dark denim or chinos", "Clean sneakers or loafers", "Optional lightweight jacket"]
    }

    private var weatherReasons: [String] {
        [
            "Light layers match \(weatherConditionText.lowercased()) conditions.",
            "Shoes are chosen for weather practicality and style polish.",
            "Colors fit your saved style profile: \(favoriteColors).",
            "Recommendation respects your \(plannedOccasion.lowercased()) occasion and \(budget) budget."
        ]
    }
}

final class StyleMatchLiveWeatherManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var isLive = false
    @Published var isRefreshing = false

    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
    }

    func refresh() {
        isRefreshing = true
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.requestLocation()
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            isRefreshing = false
            loadSavedCityOrMarkUnavailable()
        @unknown default:
            isRefreshing = false
            loadSavedCityOrMarkUnavailable()
        }
    }

    func refresh(city: String) {
        let trimmed = city.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            UserDefaults.standard.set("Add a city to receive weather-based outfit advice.", forKey: "weatherErrorMessage")
            return
        }

        isRefreshing = true
        UserDefaults.standard.set(trimmed, forKey: "weatherCity")
        Task {
            do {
                let placemarks = try await geocoder.geocodeAddressString(trimmed)
                guard let location = placemarks.first?.location else {
                    throw CLError(.geocodeFoundNoResult)
                }
                await loadOpenMeteoWeather(for: location, locationName: trimmed)
            } catch {
                await markUnavailable("Live weather is unavailable. Showing last updated weather.")
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        default:
            loadSavedCityOrMarkUnavailable()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            return
        }

        Task {
            await loadOpenMeteoWeather(for: location, locationName: nil)
            await loadCity(for: location)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.isLive = false
            self.isRefreshing = false
            UserDefaults.standard.set("Saved", forKey: "weatherSource")
            UserDefaults.standard.set("Live weather is unavailable. Showing last updated weather.", forKey: "weatherErrorMessage")
        }
    }

    @MainActor
    private func saveWeather(
        temperature: Int,
        feelsLike: Int?,
        condition: String,
        rainChance: Int?,
        humidity: Int?,
        windSpeed: Double?,
        uvIndex: Double?,
        hourly: String,
        daily: String,
        alert: String,
        source: String = "Live"
    ) {
        UserDefaults.standard.set("\(temperature)°F", forKey: "weather")
        UserDefaults.standard.set(condition, forKey: "weatherCondition")
        UserDefaults.standard.set(source, forKey: "weatherSource")
        UserDefaults.standard.set(feelsLike.map { "\($0)°F" } ?? "", forKey: "weatherFeelsLike")
        UserDefaults.standard.set(rainChance.map { "\($0)%" } ?? "", forKey: "weatherRainChance")
        UserDefaults.standard.set(humidity.map { "\($0)%" } ?? "", forKey: "weatherHumidity")
        UserDefaults.standard.set(windSpeed.map { "\(Int($0.rounded())) mph" } ?? "", forKey: "weatherWindSpeed")
        UserDefaults.standard.set(uvIndex.map { String(format: "%.0f", $0) } ?? "", forKey: "weatherUVIndex")
        UserDefaults.standard.set(hourly, forKey: "weatherHourlyForecast")
        UserDefaults.standard.set(daily, forKey: "weatherDailyForecast")
        UserDefaults.standard.set(alert, forKey: "weatherAlert")
        UserDefaults.standard.set("", forKey: "weatherErrorMessage")
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "liveWeatherUpdatedAt")
        isLive = true
        isRefreshing = false
    }

    private func loadOpenMeteoWeather(for location: CLLocation, locationName: String?) async {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(location.coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(location.coordinate.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,relative_humidity_2m,apparent_temperature,precipitation,weather_code,wind_speed_10m"),
            URLQueryItem(name: "hourly", value: "temperature_2m,precipitation_probability,weather_code"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,uv_index_max,precipitation_probability_max"),
            URLQueryItem(name: "temperature_unit", value: "fahrenheit"),
            URLQueryItem(name: "wind_speed_unit", value: "mph"),
            URLQueryItem(name: "forecast_days", value: "3"),
            URLQueryItem(name: "timezone", value: "auto")
        ]

        guard let url = components?.url else {
            await markUnavailable("Live weather is unavailable. Showing last updated weather.")
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw URLError(.badServerResponse)
            }

            let decoded = try JSONDecoder().decode(OpenMeteoWeatherResponse.self, from: data)
            let temperature = Int(decoded.current.temperature.rounded())
            let condition = conditionText(forOpenMeteoCode: decoded.current.weatherCode)
            let feelsLike = Int(decoded.current.apparentTemperature.rounded())
            let rainChance = decoded.hourly?.precipitationProbability.prefix(6).max()
            let humidity = decoded.current.relativeHumidity
            let windSpeed = decoded.current.windSpeed
            let uvIndex = decoded.daily?.uvIndexMax.first
            let hourly = hourlySummary(from: decoded)
            let daily = dailySummary(from: decoded)
            let alert = alertSummary(condition: condition, rainChance: rainChance, windSpeed: windSpeed, uvIndex: uvIndex)

            await saveWeather(
                temperature: temperature,
                feelsLike: feelsLike,
                condition: condition,
                rainChance: rainChance,
                humidity: humidity,
                windSpeed: windSpeed,
                uvIndex: uvIndex,
                hourly: hourly,
                daily: daily,
                alert: alert,
                source: "Live"
            )

            if let locationName, !locationName.isEmpty {
                await MainActor.run {
                    UserDefaults.standard.set(locationName, forKey: "weatherCity")
                }
            }
        } catch {
            await markUnavailable("Live weather is unavailable. Showing last updated weather.")
        }
    }

    private func loadSavedCityOrMarkUnavailable() {
        let city = UserDefaults.standard.string(forKey: "weatherCity")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !city.isEmpty else {
            UserDefaults.standard.set("Saved", forKey: "weatherSource")
            UserDefaults.standard.set("Add a city to receive weather-based outfit advice.", forKey: "weatherErrorMessage")
            return
        }

        refresh(city: city)
    }

    @MainActor
    private func markUnavailable(_ message: String) {
        isLive = false
        isRefreshing = false
        UserDefaults.standard.set("Saved", forKey: "weatherSource")
        UserDefaults.standard.set(message, forKey: "weatherErrorMessage")
    }

    private func hourlySummary(from response: OpenMeteoWeatherResponse) -> String {
        guard let hourly = response.hourly,
              !hourly.temperature.isEmpty else {
            return ""
        }

        let parts = hourly.temperature.prefix(4).enumerated().map { index, temp in
            let rain = hourly.precipitationProbability.indices.contains(index) ? hourly.precipitationProbability[index] : 0
            return "\(Int(temp.rounded()))°F, rain \(rain)%"
        }
        return "Next hours: " + parts.joined(separator: " | ")
    }

    private func dailySummary(from response: OpenMeteoWeatherResponse) -> String {
        guard let daily = response.daily,
              let high = daily.temperatureMax.first,
              let low = daily.temperatureMin.first else {
            return ""
        }

        let rain = daily.precipitationProbabilityMax.first ?? 0
        let uv = daily.uvIndexMax.first.map { String(format: "%.0f", $0) } ?? "N/A"
        return "Today: high \(Int(high.rounded()))°F, low \(Int(low.rounded()))°F, rain \(rain)%, UV \(uv)."
    }

    private func alertSummary(condition: String, rainChance: Int?, windSpeed: Double?, uvIndex: Double?) -> String {
        if condition.localizedCaseInsensitiveContains("Storm") {
            return "Severe weather may affect outfit safety. Prioritize protective layers and sturdy shoes."
        }
        if (windSpeed ?? 0) >= 25 {
            return "Wind is elevated. Choose secure layers and avoid loose accessories."
        }
        if (rainChance ?? 0) >= 70 {
            return "Rain is likely. Choose waterproof shoes and avoid suede."
        }
        if (uvIndex ?? 0) >= 8 {
            return "UV is high. Consider sunglasses, a hat, and breathable coverage."
        }
        return ""
    }

    private func conditionText(forOpenMeteoCode code: Int) -> String {
        switch code {
        case 0:
            return "Clear"
        case 1, 2:
            return "Partly Cloudy"
        case 3:
            return "Cloudy"
        case 45, 48:
            return "Foggy"
        case 51, 53, 55, 56, 57:
            return "Drizzle"
        case 61, 63, 65, 66, 67, 80, 81, 82:
            return "Rainy"
        case 71, 73, 75, 77, 85, 86:
            return "Snowy"
        case 95, 96, 99:
            return "Stormy"
        default:
            return "Mild"
        }
    }

    private func loadCity(for location: CLLocation) async {
        guard let placemark = try? await geocoder.reverseGeocodeLocation(location).first else {
            return
        }

        let city = placemark.locality ?? placemark.subAdministrativeArea ?? placemark.administrativeArea ?? ""
        guard !city.isEmpty else {
            return
        }

        await MainActor.run {
            UserDefaults.standard.set(city, forKey: "weatherCity")
        }
    }
}

private struct OpenMeteoWeatherResponse: Decodable {
    let current: Current
    let hourly: Hourly?
    let daily: Daily?

    struct Current: Decodable {
        let temperature: Double
        let relativeHumidity: Int?
        let apparentTemperature: Double
        let weatherCode: Int
        let windSpeed: Double?

        enum CodingKeys: String, CodingKey {
            case temperature = "temperature_2m"
            case relativeHumidity = "relative_humidity_2m"
            case apparentTemperature = "apparent_temperature"
            case weatherCode = "weather_code"
            case windSpeed = "wind_speed_10m"
        }
    }

    struct Hourly: Decodable {
        let temperature: [Double]
        let precipitationProbability: [Int]
        let weatherCode: [Int]

        enum CodingKeys: String, CodingKey {
            case temperature = "temperature_2m"
            case precipitationProbability = "precipitation_probability"
            case weatherCode = "weather_code"
        }
    }

    struct Daily: Decodable {
        let weatherCode: [Int]
        let temperatureMax: [Double]
        let temperatureMin: [Double]
        let uvIndexMax: [Double]
        let precipitationProbabilityMax: [Int]

        enum CodingKeys: String, CodingKey {
            case weatherCode = "weather_code"
            case temperatureMax = "temperature_2m_max"
            case temperatureMin = "temperature_2m_min"
            case uvIndexMax = "uv_index_max"
            case precipitationProbabilityMax = "precipitation_probability_max"
        }
    }
}
