import CoreLocation
import SwiftUI
import WeatherKit
#if canImport(UIKit)
import UIKit
#endif

enum StyleMatchKeyboardFrameVisibility {
    static func intersectsActiveWindow(keyboardFrame: CGRect, windowBounds: CGRect) -> Bool {
        guard !keyboardFrame.isNull,
              !keyboardFrame.isEmpty,
              !windowBounds.isNull,
              !windowBounds.isEmpty else {
            return false
        }
        return windowBounds.intersects(keyboardFrame)
    }
}

private struct StyleMatchBottomNavigationFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .null

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if !next.isNull, !next.isEmpty {
            value = next
        }
    }
}

private struct StyleMatchRootSafeAreaBottomPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

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
    @State private var mountedTabs: Set<AppTab> = [.home]
    @State private var homeNavigationResetID = 0
    @StateObject private var liveWeather = StyleMatchLiveWeatherManager()
    @StateObject private var outfitMemoryStore = OutfitMemoryStore()
    @State private var pendingFeedbackPrompt: ScheduledFeedbackPrompt?
    @State private var hasShownFeedbackPromptThisSession = false
    @State private var shoppingSaleUnreadCount = 0
    @State private var isSoftwareKeyboardVisible = false
    @State private var bottomNavigationFrame: CGRect = .null
    @State private var rootSafeAreaBottomInset: CGFloat = 0
    @AppStorage("selectedAppTheme") private var selectedAppTheme = StyleMatchAppTheme.system.rawValue

    private var activeTheme: StyleMatchAppTheme {
        StyleMatchAppTheme(rawValue: selectedAppTheme) ?? .system
    }

    var body: some View {
        activeScreen
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !isSoftwareKeyboardVisible {
                    bottomNavigation
                }
            }
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: StyleMatchRootSafeAreaBottomPreferenceKey.self,
                        value: proxy.safeAreaInsets.bottom
                    )
                }
            }
            .onPreferenceChange(StyleMatchBottomNavigationFramePreferenceKey.self) { frame in
                guard !frame.isNull, !frame.isEmpty, frame != bottomNavigationFrame else { return }
                bottomNavigationFrame = frame
            }
            .onPreferenceChange(StyleMatchRootSafeAreaBottomPreferenceKey.self) { inset in
                guard inset != rootSafeAreaBottomInset else { return }
                rootSafeAreaBottomInset = inset
            }
#if canImport(UIKit)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
            updateSoftwareKeyboardVisibility(from: notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isSoftwareKeyboardVisible = false
        }
#endif
        .tint(activeTheme.palette(for: selectedTab).accent)
        .preferredColorScheme(activeTheme.preferredColorScheme)
        .onAppear {
            liveWeather.refresh()
            checkForPendingFeedbackPrompt()
            refreshSaleWatcher()
        }
        .onDisappear {
            dismissSoftwareKeyboard()
            isSoftwareKeyboardVisible = false
        }
        .styleMatchOnChange(of: scenePhase) { phase in
            if phase == .active {
                checkForPendingFeedbackPrompt()
                refreshSaleWatcher()
            } else if phase == .background || phase == .inactive {
                dismissSoftwareKeyboard()
                isSoftwareKeyboardVisible = false
                dismissActiveFeedbackPrompt()
            }
        }
        .styleMatchOnChange(of: selectedTab) { tab in
            dismissSoftwareKeyboard()
            mountedTabs.insert(tab)
            if tab == .home {
                checkForPendingFeedbackPrompt()
            } else {
                dismissActiveFeedbackPrompt()
            }
        }
    }

#if canImport(UIKit)
    private func updateSoftwareKeyboardVisibility(from notification: Notification) {
        guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let window = activeWindow else {
            isSoftwareKeyboardVisible = false
            return
        }
        let keyboardFrameInWindow = window.screen.coordinateSpace.convert(
            keyboardFrame,
            to: window.coordinateSpace
        )
        isSoftwareKeyboardVisible = StyleMatchKeyboardFrameVisibility.intersectsActiveWindow(
            keyboardFrame: keyboardFrameInWindow,
            windowBounds: window.bounds
        )
    }

    private var activeWindow: UIWindow? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }
            .flatMap(\.windows)
        return windows.first(where: \.isKeyWindow) ?? windows.first(where: { !$0.isHidden })
    }
#endif

    private func dismissSoftwareKeyboard() {
#if canImport(UIKit)
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
#endif
    }

    @ViewBuilder
    private var activeScreen: some View {
        ZStack {
            preservedTab(.home) {
                HomeView(
                    selectedTab: $selectedTab,
                    navigationResetID: homeNavigationResetID,
                    feedbackPrompt: pendingFeedbackPrompt,
                    onHomeAppear: checkForPendingFeedbackPrompt,
                    onFeedbackWornAnswer: answerFeedbackWorn,
                    onFeedbackLikedAnswer: answerFeedbackLiked,
                    onFeedbackDislikeReason: answerFeedbackDislikeReason,
                    onFeedbackDismiss: dismissActiveFeedbackPrompt,
                    onFeedbackComplete: clearActiveFeedbackPrompt,
                    onSelectTab: selectTab
                )
            }

            if mountedTabs.contains(.scan) {
                preservedTab(.scan) {
                    ScanView(selectedTab: $selectedTab)
                }
            }

            if mountedTabs.contains(.closet) {
                preservedTab(.closet) {
                    ClosetView(selectedTab: $selectedTab)
                }
            }

            if mountedTabs.contains(.shop) {
                preservedTab(.shop) {
                    if ShoppingTabVisibility.shouldShowShoppingTab() {
                        ShoppingView(selectedTab: $selectedTab)
                    } else {
                        HomeView(selectedTab: $selectedTab)
                    }
                }
            }

            if mountedTabs.contains(.ai) {
                preservedTab(.ai) {
                    if FeatureFlags.conversationalStylist {
                        StylistChatView(
                            bottomNavigationClearance: chatBottomNavigationClearance,
                            onSignInRequested: { selectedTab = .profile }
                        )
                    } else {
                        StableAIFallbackView(selectedTab: $selectedTab)
                    }
                }
            }

            if mountedTabs.contains(.profile) {
                preservedTab(.profile) {
                    ProfileView(selectedTab: $selectedTab)
                }
            }
        }
    }

    private func preservedTab<Content: View>(_ tab: AppTab, @ViewBuilder content: () -> Content) -> some View {
        content()
            .opacity(selectedTab == tab ? 1 : 0)
            .allowsHitTesting(selectedTab == tab)
            .accessibilityHidden(selectedTab != tab)
    }

    private func selectTab(_ tab: AppTab) {
        if tab == .home {
            homeNavigationResetID &+= 1
        }
        guard selectedTab != tab else {
            dismissSoftwareKeyboard()
            return
        }
        mountedTabs.insert(tab)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            selectedTab = tab
        }
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
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: StyleMatchBottomNavigationFramePreferenceKey.self,
                    value: proxy.frame(in: .global)
                )
            }
        }
    }

    private var chatBottomNavigationClearance: CGFloat {
        guard !isSoftwareKeyboardVisible,
              !bottomNavigationFrame.isNull,
              !bottomNavigationFrame.isEmpty else {
            return 0
        }
        return bottomNavigationFrame.height
    }

    private func bottomTab(_ tab: AppTab, title: String, icon: String, badgeCount: Int = 0) -> some View {
        let isSelected = selectedTab == tab
        let selectedPalette = activeTheme.palette(for: tab)

        return Button {
            selectTab(tab)
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(
            [isSelected ? "Selected" : "Not selected", badgeCount > 0 ? "\(badgeCount) new alerts" : nil]
                .compactMap { $0 }
                .joined(separator: ", ")
        )
        .accessibilityHint("Opens the \(title) tab")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func refreshSaleWatcher() {
        guard FeatureFlags.saleNotificationsEnabled else {
            shoppingSaleUnreadCount = 0
            return
        }
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
    @AppStorage("shareAppContextWithChatGPT") private var shareAppContextWithChatGPT = true
    @AppStorage("shirtSize") private var shirtSize = ""
    @AppStorage("pantsSize") private var pantsSize = ""
    @AppStorage("neckSize") private var neckSize = ""
    @AppStorage("sleeveLength") private var sleeveLength = ""
    @AppStorage("shoeSize") private var shoeSize = ""
    @AppStorage("fitPreference") private var fitPreference = ""
    @AppStorage("shoppingBudget") private var budget = ""
    @AppStorage("favoriteColors") private var favoriteColors = ""
    @AppStorage("favoriteBrands") private var favoriteBrands = ""
    @AppStorage("favoriteOutfits") private var favoriteOutfits = ""
    @AppStorage("weather") private var weather = ""
    @AppStorage("weatherCondition") private var weatherCondition = ""
    @AppStorage("weatherSource") private var weatherSource = ""
    @AppStorage("plannedOccasion") private var plannedOccasion = ""
    @AppStorage("stylePreferences") private var stylePreferences = ""
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
            .alert("StyleMatch Pro AI Awareness", isPresented: $showAwarenessTestResult) {
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
                    .navigationTitle("StyleMatch Pro AI Awareness")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") {
                                showAwarenessDetail = false
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

                    Text("Powered by StyleMatch Pro AI")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppTab.ai.palette.accent)
                }

                Spacer(minLength: 8)
            }

            Text(profileHasSavedData ? "Your personal stylist checks saved weather, closet, sizes, scans, and style memory before suggesting what to wear." : "Add your profile, closet, and scans when you're ready. StyleMatch Pro will use them before suggesting what to wear.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(3)

            HStack(spacing: 10) {
                WeatherStylingButton {
                    aiMiniMetric(title: weatherTemperatureText, detail: weatherConditionText, icon: "cloud.sun.fill")
                }
                aiMiniMetric(title: expectedStyleScoreText, detail: "Expected Score", icon: "star.fill")
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

            Text(dailyStyleBriefText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(4)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                aiMiniMetric(title: plannedOccasionText, detail: "Occasion", icon: "calendar")
                aiMiniMetric(title: "\(savedClosetCount)", detail: "Closet Items", icon: "tshirt.fill")
                aiMiniMetric(title: recentStyleScoreText, detail: "Recent Score", icon: "clock.fill")
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
                    Text("StyleMatch Pro AI Test Access")
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
                    Label("Activate StyleMatch Pro AI", systemImage: "bolt.fill")
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
            VStack(alignment: .leading, spacing: 10) {
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

                AppleWeatherAttributionView()
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

                    Text("\(recommendedStyle) • \(plannedOccasionText) • \(weatherConditionText)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(expectedStyleScoreText)
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

            Text("StyleMatch Pro is your personal AI fashion stylist, powered by StyleMatch Pro AI.")
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

                    Text("Powered by StyleMatch Pro AI")
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
                    Text("StyleMatch Pro AI Awareness")
                        .font(.title3)
                        .fontWeight(.bold)

                    Text("StyleMatch Pro AI can use your StyleMatch Pro memory, closet, sizes, weather, saved scans, and style preferences when helping you.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                }
            }

            Toggle(isOn: $shareAppContextWithChatGPT) {
                Text(shareAppContextWithChatGPT ? "StyleMatch Pro AI Awareness On" : "StyleMatch Pro AI Awareness Off")
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
                    message = shareAppContextWithChatGPT ? "StyleMatch Pro AI Awareness resumed." : "StyleMatch Pro AI Awareness paused."
                }

                aiSmallAction("View Stored Preferences", "list.bullet.rectangle") {
                    showMemoryDetails = true
                }

                aiSmallAction("Clear AI Memory", "trash") {
                    shareAppContextWithChatGPT = false
                    message = "StyleMatch Pro AI memory was cleared for AI use. Profile fields remain editable in Profile."
                }

                aiSmallAction("Reset Style Profile", "arrow.counterclockwise") {
                    favoriteColors = ""
                    favoriteBrands = ""
                    stylePreferences = ""
                    message = "Style profile fields were cleared. Add preferences in Profile when you're ready."
                }
            }

                Button {
                    message = shareAppContextWithChatGPT
                        ? "StyleMatch Pro AI Awareness test completed."
                        : "StyleMatch Pro AI Awareness is off. Turn it on to let StyleMatch Pro AI use your style context."
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
            return "StyleMatch Pro AI Awareness is off. Turn it on so StyleMatch Pro AI can use your style context."
        }

        return """
        StyleMatch Pro AI Awareness is on.

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

                    Text("StyleMatch Pro AI suggests a polished smart-casual look from your saved style profile.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 10) {
                aiAdviceRow(icon: "tshirt.fill", title: "Start with", value: "Navy or white shirt")
                aiAdviceRow(icon: "figure.stand", title: "Pair with", value: "Dark denim or tailored pants")
                aiAdviceRow(icon: "shoe.2.fill", title: "Shoes", value: "Clean white sneakers or black loafers")
                aiAdviceRow(icon: "star.fill", title: "Expected score", value: expectedStyleAdviceText)
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
                                .frame(width: 44, height: 44)
                        }
                        .disabled(isSendingStylistMessage || chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel("Send stylist message")
                        .accessibilityHint("Sends your question to the stylist")
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
            pastOutfitRatings: pastOutfitRatingsContext,
            frequentlyWornOutfits: favoriteOutfits,
            pastPurchases: "",
            favoriteOutfits: favoriteOutfits,
            closetInventory: closetItems.prefix(12).map { "\($0.color) \($0.name)" }.joined(separator: ", "),
            appContextSharingEnabled: shareAppContextWithChatGPT,
            appContext: """
            StyleMatch Pro AI Stylist chat.
            Closet items: \(savedClosetCount)
            Saved scans: \(savedScanCount)
            Recent scan context: \(latestScanContextForAI)
            """
        )

        let client = OpenAIStylistClient(apiKey: "", model: openAIModel)

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
        return trimmed.isEmpty ? "No weather saved" : trimmed
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

    private var profileHasSavedData: Bool {
        FounderProfileDefaultsMigration.hasIntentionalProfileSave()
    }

    private var recentStyleScore: Int {
        latestStoredScan?.score ?? 0
    }

    private var recentStyleScoreText: String {
        latestStoredScan.map { "\($0.score)" } ?? "No scans yet"
    }

    private var expectedStyleScore: Int {
        guard latestStoredScan != nil else { return 0 }
        return min(98, max(82, recentStyleScore + (shareAppContextWithChatGPT ? 2 : 0)))
    }

    private var expectedStyleScoreText: String {
        latestStoredScan == nil ? "No scans yet" : "\(expectedStyleScore)"
    }

    private var expectedStyleAdviceText: String {
        latestStoredScan == nil ? "Scan an outfit to unlock an expected score." : "\(expectedStyleScore) projected from your recent scan."
    }

    private var aiConfidence: Int {
        min(98, 82 + min(savedScanCount, 8) + min(savedClosetCount, 8) + (shareAppContextWithChatGPT ? 4 : 0))
    }

    private var recommendedStyle: String {
        guard profileHasSavedData || latestStoredScan != nil else {
            return "Personalized look"
        }
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

    private var plannedOccasionText: String {
        plannedOccasion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No occasion yet" : plannedOccasion
    }

    private var dailyStyleBriefText: String {
        if profileHasSavedData || latestStoredScan != nil || savedClosetCount > 0 {
            return "Today's weather is \(weatherTemperatureText) and \(weatherConditionText.lowercased()). Based on your saved wardrobe, preferences, and today's occasion, StyleMatch Pro recommends a clean \(plannedOccasionText.lowercased()) look."
        }
        return "Add a profile, closet item, or scan history to unlock a personalized daily style brief."
    }

    private var pastOutfitRatingsContext: String {
        latestStoredScan.map { "\($0.score)/100 recent score, \(savedScanCount) saved scan\(savedScanCount == 1 ? "" : "s")" } ?? "\(savedScanCount) saved scan\(savedScanCount == 1 ? "" : "s")"
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
            return "Add shoes to your closet to improve outfit matching."
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

                Text("Powered by StyleMatch Pro AI")
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

            Label("Model routing is managed securely by StyleMatch Pro.", systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(AppTab.ai.palette.accent.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(AppTab.ai.palette.accent.opacity(0.22), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var betaChatGPTSubtitle: String {
        if betaAIConnectionVerified {
            return "StyleMatch Pro AI is active on this phone."
        }

        if openAIKeyIsSaved {
            return "Founder test key is saved. Tap Activate StyleMatch Pro AI to test the live connection."
        }

        return "Paste your private OpenAI API key to test StyleMatch Pro AI."
    }

    private func loadBetaOpenAIKey() {
        openAIKeyInput = OpenAIKeychain.loadAPIKey() ?? ""
        openAIKeyIsSaved = !openAIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        betaAIConnectionVerified = false
        if openAIModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || openAIModel == "gpt-5.5" {
            openAIModel = "gpt-4o-mini"
        }
        betaAIStatus = openAIKeyIsSaved ? "Key saved. Tap Activate StyleMatch Pro AI to test the live connection." : ""
    }

    private func saveBetaOpenAIKey() {
        do {
            try OpenAIKeychain.saveAPIKey(openAIKeyInput)
            openAIKeyInput = OpenAIKeychain.loadAPIKey() ?? openAIKeyInput
            openAIKeyIsSaved = !openAIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            betaAIConnectionVerified = false
            betaAIStatus = openAIKeyIsSaved ? "Testing StyleMatch Pro AI connection..." : "Paste your key and tap Activate StyleMatch Pro AI."
            verifyBetaOpenAIConnection()
        } catch {
            openAIKeyIsSaved = false
            betaAIConnectionVerified = false
            betaAIStatus = "Could not activate StyleMatch Pro AI right now. Please check the key and try again."
        }
    }

    private func verifyBetaOpenAIConnection() {
        guard let savedKey = OpenAIKeychain.loadAPIKey()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !savedKey.isEmpty else {
            betaAIConnectionVerified = false
            betaAIStatus = "Paste your key and tap Activate StyleMatch Pro AI."
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
            pastOutfitRatings: pastOutfitRatingsContext,
            frequentlyWornOutfits: favoriteOutfits,
            pastPurchases: "",
            favoriteOutfits: favoriteOutfits,
            closetInventory: closetItems.prefix(12).map { "\($0.color) \($0.name)" }.joined(separator: ", "),
            appContextSharingEnabled: false,
            appContext: "StyleMatch Pro AI connection test."
        )

        Task {
            do {
                _ = try await client.askStylist(
                    profile: profile,
                    question: "Reply with one short sentence confirming StyleMatch Pro AI is connected."
                )
                await MainActor.run {
                    betaAIConnectionVerified = true
                    betaAIStatus = "StyleMatch Pro AI tested successfully. Ask My Stylist is ready."
                }
            } catch {
                await MainActor.run {
                    betaAIConnectionVerified = false
                    betaAIStatus = "Key saved, but StyleMatch Pro AI could not answer yet. Please try again."
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
            betaAIStatus = "Founder test key removed from this phone."
        } catch {
            betaAIStatus = "Could not remove key: \(error.localizedDescription)"
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
    @AppStorage("weather") private var weather = ""
    @AppStorage("weatherCondition") private var weatherCondition = ""
    @AppStorage("weatherCity") private var weatherCity = ""
    @AppStorage("weatherSource") private var weatherSource = ""
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
    @AppStorage("plannedOccasion") private var plannedOccasion = ""
    @AppStorage("favoriteColors") private var favoriteColors = ""
    @AppStorage("shoppingBudget") private var budget = ""
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

            AppleWeatherAttributionView()
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
        AppleWeatherDataPolicy.isStale(updatedAt: liveWeatherUpdatedAt)
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
                await loadWeatherKitWeather(for: location, locationName: trimmed)
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
            await loadWeatherKitWeather(for: location, locationName: nil)
            await loadCity(for: location)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.isLive = false
            self.isRefreshing = false
            UserDefaults.standard.set("Saved Apple Weather", forKey: "weatherSource")
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

    private func loadWeatherKitWeather(for location: CLLocation, locationName: String?) async {
        do {
            let weather = try await WeatherService.shared.weather(for: location)
            let current = weather.currentWeather
            let temperature = Int(current.temperature.converted(to: .fahrenheit).value.rounded())
            let condition = current.condition.description.capitalized
            let feelsLike = Int(current.apparentTemperature.converted(to: .fahrenheit).value.rounded())
            let rainChance = weather.hourlyForecast.prefix(6).map { Int(($0.precipitationChance * 100).rounded()) }.max()
            let humidity = Int((current.humidity * 100).rounded())
            let windSpeed = current.wind.speed.converted(to: .milesPerHour).value
            let uvIndex = Double(current.uvIndex.value)
            let hourly = hourlySummary(from: weather)
            let daily = dailySummary(from: weather)
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
                source: "Live Apple Weather"
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
            UserDefaults.standard.set("Saved Apple Weather", forKey: "weatherSource")
            UserDefaults.standard.set("Add a city to receive weather-based outfit advice.", forKey: "weatherErrorMessage")
            return
        }

        refresh(city: city)
    }

    @MainActor
    private func markUnavailable(_ message: String) {
        isLive = false
        isRefreshing = false
        UserDefaults.standard.set("Saved Apple Weather", forKey: "weatherSource")
        UserDefaults.standard.set(message, forKey: "weatherErrorMessage")
    }

    private func hourlySummary(from weather: Weather) -> String {
        let parts = weather.hourlyForecast.prefix(4).map { hour in
            let temperature = Int(hour.temperature.converted(to: .fahrenheit).value.rounded())
            let rain = Int((hour.precipitationChance * 100).rounded())
            return "\(temperature)°F, rain \(rain)%"
        }
        guard !parts.isEmpty else { return "" }
        return "Next hours: " + parts.joined(separator: " | ")
    }

    private func dailySummary(from weather: Weather) -> String {
        guard let day = weather.dailyForecast.first else { return "" }
        let high = Int(day.highTemperature.converted(to: .fahrenheit).value.rounded())
        let low = Int(day.lowTemperature.converted(to: .fahrenheit).value.rounded())
        let rain = Int((day.precipitationChance * 100).rounded())
        return "Today: high \(high)°F, low \(low)°F, rain \(rain)%."
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
