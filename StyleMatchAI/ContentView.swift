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

/// Shared visual language for the premium pass. Champagne is deliberately an
/// accent rather than a fill so photography, content, and hierarchy stay in
/// control of the experience.
enum StyleMatchPremiumPalette {
    static let ink = Color(red: 0.035, green: 0.035, blue: 0.045)
    static let panel = Color(red: 0.075, green: 0.075, blue: 0.09)
    static let panelRaised = Color(red: 0.105, green: 0.105, blue: 0.125)
    static let champagne = Color(red: 0.84, green: 0.70, blue: 0.42)
    static let champagneSoft = Color(red: 0.94, green: 0.84, blue: 0.63)
    static let border = Color.white.opacity(0.10)
    static let mutedText = Color.white.opacity(0.68)
    static let cornerLarge: CGFloat = 26
    static let cornerMedium: CGFloat = 18
}

/// Small, deliberate feedback moments shared by the premium surfaces. They are
/// never required for an action to complete, so Reduce Motion and non-UIKit
/// environments keep the same functional behavior.
enum StyleMatchPremiumFeedback {
    static func selection() {
        #if canImport(UIKit)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }

    static func success() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
}

/// The semantic rendering contract shared by StyleMatch surfaces. Themes may
/// choose these values, but screens should describe their role rather than
/// hard-code a theme-specific color.
struct StyleMatchThemeTokens {
    let backgroundStart: Color
    let backgroundMiddle: Color
    let backgroundEnd: Color
    let cardBackground: Color
    let elevatedCardBackground: Color
    let primaryText: Color
    let secondaryText: Color
    let accent: Color
    let secondaryAccent: Color
    let premiumAccent: Color
    let divider: Color
    let success: Color
    let warning: Color
    let error: Color
    let aiAccent: Color
    let scanAccent: Color
    let weatherAccent: Color
    let shopAccent: Color
    let socialAccent: Color
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

enum StyleMatchAppearanceMode: String, CaseIterable, Identifiable {
    case manual, system, adaptive
    var id: String { rawValue }

    static func resolve(_ rawValue: String?) -> Self {
        Self(rawValue: rawValue ?? "") ?? .manual
    }
}

struct StyleMatchAdaptiveAccessibility: Equatable {
    let colorScheme: ColorScheme
    let increaseContrast: Bool
    let differentiateWithoutColor: Bool
    let reduceTransparency: Bool
}

struct StyleMatchAdaptiveDecision: Equatable {
    let recommendedTheme: StyleMatchAppTheme
    let reasonCode: String
    let confidence: String
}

enum StyleMatchAdaptiveDecisionEngine {
    static func recommendation(
        hour: Int,
        occasion: String? = nil,
        stylePreference: String? = nil,
        accessibility: StyleMatchAdaptiveAccessibility
    ) -> StyleMatchAdaptiveDecision {
        let candidates = accessibleThemes(for: accessibility)
        let normalizedOccasion = occasion?.lowercased() ?? ""
        let normalizedPreference = stylePreference?.lowercased() ?? ""
        let preferred: StyleMatchAppTheme

        if normalizedOccasion.contains("formal") || normalizedPreference.contains("luxury") {
            preferred = .blackAMOLED
        } else if normalizedPreference.contains("minimal") || normalizedPreference.contains("editorial") {
            preferred = .light
        } else if hour >= 18 || hour < 6 {
            preferred = .dark
        } else if normalizedPreference.contains("ocean") {
            preferred = .blue
        } else {
            preferred = .styleMatchAI
        }

        let theme = candidates.contains(preferred) ? preferred : (candidates.first ?? .system)
        let reason = theme == .dark ? "evening_editorial" : theme == .blackAMOLED ? "elevated_occasion" : theme == .light ? "minimal_editorial" : "daytime_signature"
        return .init(recommendedTheme: theme, reasonCode: reason, confidence: "high")
    }

    static func accessibleThemes(for accessibility: StyleMatchAdaptiveAccessibility) -> [StyleMatchAppTheme] {
        StyleMatchAppTheme.availableThemes.filter { theme in
            if accessibility.increaseContrast && theme == .premiumPink { return false }
            if accessibility.reduceTransparency && theme == .styleMatchAI { return false }
            if accessibility.colorScheme == .dark && theme == .light { return false }
            return true
        }
    }
}

struct StyleMatchResolvedAppearance: Equatable {
    let theme: StyleMatchAppTheme
    let reasonCode: String
}

enum StyleMatchAppearanceResolver {
    static func resolve(modeRawValue: String?, selectedThemeRawValue: String?, adaptiveThemeRawValue: String?) -> StyleMatchResolvedAppearance {
        let selected = StyleMatchAppTheme(rawValue: selectedThemeRawValue ?? "") ?? .system
        switch StyleMatchAppearanceMode.resolve(modeRawValue) {
        case .manual: return .init(theme: selected, reasonCode: "manual_selection")
        case .system: return .init(theme: .system, reasonCode: "system_appearance")
        case .adaptive:
            let adaptive = StyleMatchAppTheme(rawValue: adaptiveThemeRawValue ?? "")
            return .init(theme: adaptive ?? selected, reasonCode: adaptive == nil ? "adaptive_fallback" : "adaptive_local")
        }
    }
}

private struct AppScreenBackground: ViewModifier {
    let tab: AppTab
    @AppStorage("selectedAppTheme") private var selectedAppTheme = StyleMatchAppTheme.system.rawValue
    @AppStorage("styleMatchAppearanceMode") private var appearanceMode = StyleMatchAppearanceMode.manual.rawValue
    @AppStorage("styleMatchAdaptiveTheme") private var adaptiveTheme = ""
    @AppStorage("selectedThemeIntensity") private var selectedThemeIntensity = 0.42

    func body(content: Content) -> some View {
        let activeTheme = StyleMatchAppearanceResolver.resolve(modeRawValue: appearanceMode, selectedThemeRawValue: selectedAppTheme, adaptiveThemeRawValue: adaptiveTheme).theme
        let tokens = activeTheme.tokens(for: tab)
        let intensity = max(0.18, min(selectedThemeIntensity, 0.82))

        content
            .background(
                ZStack {
                    if activeTheme == .blackAMOLED {
                        Color.black
                    } else {
                        tokens.backgroundStart.opacity(0.08 + intensity * 0.12)
                        LinearGradient(
                            colors: [
                                tokens.backgroundStart.opacity(0.14 + intensity * 0.22),
                                tokens.backgroundMiddle.opacity(0.08 + intensity * 0.16),
                                tokens.backgroundEnd.opacity(0.10 + intensity * 0.18)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
                }
                    .ignoresSafeArea()
            )
            .tint(tokens.accent)
    }
}

private struct AppCardBackground: ViewModifier {
    let tab: AppTab
    let radius: CGFloat
    @AppStorage("selectedAppTheme") private var selectedAppTheme = StyleMatchAppTheme.system.rawValue
    @AppStorage("styleMatchAppearanceMode") private var appearanceMode = StyleMatchAppearanceMode.manual.rawValue
    @AppStorage("styleMatchAdaptiveTheme") private var adaptiveTheme = ""
    @AppStorage("selectedThemeIntensity") private var selectedThemeIntensity = 0.42

    func body(content: Content) -> some View {
        let activeTheme = StyleMatchAppearanceResolver.resolve(modeRawValue: appearanceMode, selectedThemeRawValue: selectedAppTheme, adaptiveThemeRawValue: adaptiveTheme).theme
        let tokens = activeTheme.tokens(for: tab)
        let intensity = max(0.18, min(selectedThemeIntensity, 0.82))

        content
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: radius)
                        .fill(tokens.cardBackground)
                    RoundedRectangle(cornerRadius: radius)
                        .fill(tokens.secondaryAccent.opacity(0.04 + intensity * 0.10))
                    RoundedRectangle(cornerRadius: radius)
                        .fill(tokens.backgroundStart.opacity(0.02 + intensity * 0.04))
                }
            )
            .foregroundStyle(.primary)
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .stroke(tokens.divider.opacity(0.22 + intensity * 0.34), lineWidth: 1)
            )
            .shadow(color: tokens.premiumAccent.opacity(0.04 + intensity * 0.12), radius: 12, x: 0, y: 6)
    }
}

struct PageColorBand: View {
    let tab: AppTab
    let title: String
    let subtitle: String
    let icon: String
    @AppStorage("selectedAppTheme") private var selectedAppTheme = StyleMatchAppTheme.system.rawValue
    @AppStorage("styleMatchAppearanceMode") private var appearanceMode = StyleMatchAppearanceMode.manual.rawValue
    @AppStorage("styleMatchAdaptiveTheme") private var adaptiveTheme = ""
    @AppStorage("selectedThemeIntensity") private var selectedThemeIntensity = 0.42

    var body: some View {
        let activeTheme = StyleMatchAppearanceResolver.resolve(modeRawValue: appearanceMode, selectedThemeRawValue: selectedAppTheme, adaptiveThemeRawValue: adaptiveTheme).theme
        let tokens = activeTheme.tokens(for: tab)
        let intensity = max(0.18, min(selectedThemeIntensity, 0.82))

        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(tokens.accent.opacity(0.95))
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
                        colors: [tokens.accent.opacity(0.10 + intensity * 0.18), tokens.premiumAccent.opacity(0.08 + intensity * 0.16)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }
            }
            )
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(tokens.divider.opacity(0.24 + intensity * 0.32), lineWidth: 1)
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
    /// Debug-only build information remains an explicit Home-toolbar action.
    /// It must not be driven by a root gesture because that would compete with
    /// every navigation and content interaction in the application.
    var onShowBuildInformation: (() -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: AppTab = .home
    @State private var previousSelectedTab: AppTab = .home
    @State private var mountedTabs: Set<AppTab> = [.home]
    @State private var homeNavigationResetID = 0
    @State private var scanHistoryScrollRequestID = 0
    @State private var closetAddItemRequestID = 0
    @ObservedObject private var liveWeather = WeatherKitAuthority.shared
    @StateObject private var outfitMemoryStore = OutfitMemoryStore()
    @State private var pendingFeedbackPrompt: ScheduledFeedbackPrompt?
    @State private var hasShownFeedbackPromptThisSession = false
    @State private var shoppingSaleUnreadCount = 0
    @State private var isSoftwareKeyboardVisible = false
    @State private var bottomNavigationFrame: CGRect = .null
    @State private var rootSafeAreaBottomInset: CGFloat = 0
    @State private var stylistRouteAuthority = StylistAIRouteAuthority()
    @State private var stylistAwarenessCoordinator = StylistAwarenessCoordinator()
    @StateObject private var stylistOverlaySession = StylistOverlaySessionCoordinator()
    @State private var availableShoppingProductIDs: Set<String> = []
    @State private var pendingExplicitGlobalAIGeneration: UInt64?
    @State private var scanStylistHandoff: StylistScanHandoff?
    @State private var explicitStylistScanRoute: StylistScanHandoff?
    @State private var isCloudSyncForegroundRefreshInFlight = false
    @ObservedObject private var styleFriendsNotificationRoutes = StyleFriendsNotificationRouteStore.shared
    @State private var pendingStyleFriendsMessageRoute: StyleFriendsNotificationRoute?
    @AppStorage("customerAccountSyncEnabled") private var cloudSyncEnabled = false
    @AppStorage("selectedAppTheme") private var selectedAppTheme = StyleMatchAppTheme.system.rawValue
    @AppStorage("styleMatchAppearanceMode") private var appearanceMode = StyleMatchAppearanceMode.manual.rawValue
    @AppStorage("styleMatchAdaptiveTheme") private var adaptiveTheme = ""

    private var activeTheme: StyleMatchAppTheme {
        StyleMatchAppearanceResolver.resolve(modeRawValue: appearanceMode, selectedThemeRawValue: selectedAppTheme, adaptiveThemeRawValue: adaptiveTheme).theme
    }

    var body: some View {
        activeScreen
            .environment(\.weatherStylistRouteAction, WeatherStylistRouteAction { request in
                openWeatherStylistConversation(request)
            })
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomNavigation
            }
            .overlay(alignment: globalStylistControlAlignment) {
                if shouldShowGlobalStylistControl {
                    globalStylistControl
                        .padding(globalStylistControlHorizontalPadding, 20)
                        .padding(.bottom, bottomNavigationClearance + 16)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        .animation(
                            accessibilityReduceMotion ? nil : .easeInOut(duration: 0.18),
                            value: stylistOverlaySession.floatingControlPresentation
                        )
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
        .onAppear { openPendingDailyBrief() }
        .onReceive(NotificationCenter.default.publisher(for: DailyStyleReminder.openNotification)) { _ in
            openPendingDailyBrief()
        }
        .onReceive(NotificationCenter.default.publisher(for: StyleMatchAccountSessionStore.profileReconnectRequestedNotification)) { _ in
            selectedTab = .profile
        }
        .onReceive(styleFriendsNotificationRoutes.$route.compactMap { $0 }) { route in
            guard route.isDirectMessageRoute else { return }
            pendingStyleFriendsMessageRoute = route
            StyleFriendsNotificationRouteStore.shared.clear()
        }
        .tint(activeTheme.palette(for: selectedTab).accent)
        .preferredColorScheme(activeTheme.preferredColorScheme)
        .fullScreenCover(item: $pendingStyleFriendsMessageRoute) { route in
            StyleFriendsNotificationMessageHost(route: route)
        }
        .sheet(
            isPresented: Binding(
                get: { stylistOverlaySession.isPresented },
                set: { isPresented in
                    if !isPresented {
                        stylistOverlaySession.dismiss()
                    }
                }
            )
        ) {
            globalStylistSheet
        }
        .onAppear {
            liveWeather.refresh()
            checkForPendingFeedbackPrompt()
            refreshSaleWatcher()
            refreshCloudSyncIfNeeded()
        }
        .onDisappear {
            dismissSoftwareKeyboard()
            isSoftwareKeyboardVisible = false
        }
        .styleMatchOnChange(of: scenePhase) { phase in
            if phase == .active {
                checkForPendingFeedbackPrompt()
                refreshSaleWatcher()
                refreshCloudSyncIfNeeded()
            } else if phase == .background || phase == .inactive {
                dismissSoftwareKeyboard()
                isSoftwareKeyboardVisible = false
                dismissActiveFeedbackPrompt()
            }
        }
        .styleMatchOnChange(of: selectedTab) { tab in
            if tab == .ai {
                if pendingExplicitGlobalAIGeneration == stylistRouteAuthority.generation {
                    pendingExplicitGlobalAIGeneration = nil
                } else {
                    stylistRouteAuthority = stylistRouteAuthority.publishingCarriedEntry(
                        stylistEntryPointForAI(from: previousSelectedTab)
                    )
                }
            } else {
                pendingExplicitGlobalAIGeneration = nil
            }
            previousSelectedTab = tab
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
    private func openPendingDailyBrief() {
        guard UserDefaults.standard.bool(forKey: "kigoOpenDailyBrief") else { return }
        UserDefaults.standard.removeObject(forKey: "kigoOpenDailyBrief")
        selectTab(.home)
    }

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
                    onSelectTab: selectTab,
                    onOpenScanHistory: openRecentScoresFromHomeHistory,
                    onOpenClosetAddItem: openClosetAddItemFromHome,
                    onOpenContextualStylist: openHomeStylistConversation,
                    onOpenHomeIntelligenceStylist: openHomeIntelligenceStylistConversation,
                    onPrepareHomeIntelligenceShopping: prepareHomeIntelligenceShopping,
                    onOpenBuildInformation: onShowBuildInformation,
                    floatingStylistClearance: homeFloatingStylistClearance
                )
            }

            if mountedTabs.contains(.scan) {
                preservedTab(.scan) {
                    ScanView(
                        selectedTab: $selectedTab,
                        bottomNavigationClearance: bottomNavigationClearance,
                        recentScoresScrollRequestID: scanHistoryScrollRequestID,
                        onStylistScanHandoffChanged: { handoff in
                            scanStylistHandoff = handoff
                        },
                        onOpenStylistScanConversation: openStylistScanConversation,
                        onOpenStylistComparison: openCompareStylistConversation
                    )
                }
            }

            if mountedTabs.contains(.closet) {
                preservedTab(.closet) {
                    ClosetView(
                        selectedTab: $selectedTab,
                        addItemRequestID: closetAddItemRequestID,
                        onOpenContextualStylist: openClosetItemStylistConversation
                    )
                }
            }

            if mountedTabs.contains(.shop) {
                preservedTab(.shop) {
                    if ShoppingTabVisibility.shouldShowShoppingTab() {
                        ShoppingView(
                            selectedTab: $selectedTab,
                            bottomNavigationClearance: bottomNavigationClearance,
                            onOpenContextualStylist: openShoppingProductStylistConversation,
                            onCatalogProductIDsChanged: { productIDs in
                                guard availableShoppingProductIDs != productIDs else { return }
                                availableShoppingProductIDs = productIDs
                            }
                        )
                    } else {
                        HomeView(
                            selectedTab: $selectedTab,
                            onOpenBuildInformation: onShowBuildInformation
                        )
                    }
                }
            }

            if mountedTabs.contains(.ai) {
                preservedTab(.ai) {
                    if FeatureFlags.conversationalStylist {
                        StylistChatView(
                            initialContext: activeStylistScanHandoff?.aiChatContext,
                            scanHandoff: activeStylistScanHandoff,
                            screenAwarenessSnapshot: activeScreenAwarenessSnapshot,
                            screenAwarenessGeneration: stylistAwarenessCoordinator.generation,
                            availableShoppingProductIDs: availableShoppingProductIDs,
                            screenContext: activeStylistScanHandoff?.aiScreenContext
                                ?? stylistRouteAuthority.screenContext,
                            bottomNavigationClearance: chatBottomNavigationClearance,
                            onSignInRequested: { selectedTab = .profile },
                            onUseGeneralStylist: clearScreenAwareness,
                            showsBackControl: true,
                            onBackRequested: {
                                dismissSoftwareKeyboard()
                                selectTab(.home)
                            }
                        )
                    } else {
                        StableAIFallbackView(selectedTab: $selectedTab)
                    }
                }
            }
            if mountedTabs.contains(.profile) {
                preservedTab(.profile) {
                    ProfileView(
                        selectedTab: $selectedTab,
                        bottomOverlayClearance: bottomNavigationClearance + 72,
                        onOpenContextualStylist: openProfileStylistConversation
                    )
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
        if tab == .ai {
            stylistRouteAuthority = stylistRouteAuthority.publishingGlobalAI()
            stylistAwarenessCoordinator.clear()
            explicitStylistScanRoute = nil
            pendingExplicitGlobalAIGeneration = stylistRouteAuthority.generation
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

    private func openRecentScoresFromHomeHistory() {
        selectTab(.scan)
        scanHistoryScrollRequestID &+= 1
    }

    private func openClosetAddItemFromHome() {
        closetAddItemRequestID &+= 1
        selectTab(.closet)
    }

    private func stylistEntryPointForAI(from sourceTab: AppTab) -> StylistEntryPoint {
        switch sourceTab {
        case .home:
            return .homeMorningBrief
        case .closet:
            return .closetDesigner
        case .shop:
            return .shopping
        case .profile:
            return .profile
        case .scan:
            return scanStylistHandoff == nil ? .scanTab : .scanResult
        case .ai:
            return .aiTab
        }
    }

    private var activeStylistScanHandoff: StylistScanHandoff? {
        guard stylistRouteAuthority.acceptsScanHandoff else { return nil }
        return explicitStylistScanRoute ?? scanStylistHandoff
    }

    private var activeScreenAwarenessSnapshot: ScreenAwarenessSnapshot? {
        stylistAwarenessCoordinator.snapshot
    }

    private var overlayScreenAwarenessSnapshot: ScreenAwarenessSnapshot? {
        guard stylistOverlaySession.usesScreenAwareness,
              let snapshot = activeScreenAwarenessSnapshot else {
            return nil
        }
        return snapshot
    }

    private var overlayScanHandoff: StylistScanHandoff? {
        guard stylistOverlaySession.route == .scan else { return nil }
        return activeStylistScanHandoff
    }

    private var overlayScreenContext: StylistScreenContext {
        overlayScanHandoff?.aiScreenContext
            ?? overlayScreenAwarenessSnapshot?.screenContext
            ?? .aiTab()
    }

    private var shouldShowGlobalStylistControl: Bool {
        // Build 18049 premium interaction rule: no floating AI control may
        // cover tappable content. Every major surface owns an inline,
        // contextual Stylist entry point; Scan exposes its score-specific
        // Stylist action inside the result card.
        false
    }

    private var globalStylistControlAlignment: Alignment {
        switch stylistOverlaySession.floatingControlPresentation.edge {
        case .leading:
            return .bottomLeading
        case .trailing:
            return .bottomTrailing
        }
    }

    private var globalStylistControlHorizontalPadding: Edge.Set {
        switch stylistOverlaySession.floatingControlPresentation.edge {
        case .leading:
            return .leading
        case .trailing:
            return .trailing
        }
    }

    private var homeFloatingStylistClearance: CGFloat {
        guard shouldShowGlobalStylistControl else { return 0 }
        return stylistOverlaySession.floatingControlPresentation.isCollapsed ? 64 : 88
    }

    private func moveGlobalStylistControl(to edge: StylistOverlaySessionCoordinator.FloatingControlEdge) {
        stylistOverlaySession.moveFloatingControl(to: edge)
    }

    private var globalStylistControl: some View {
        Group {
            if stylistOverlaySession.floatingControlPresentation.isCollapsed {
                collapsedGlobalStylistControl
            } else {
                expandedGlobalStylistControl
            }
        }
    }

    private var expandedGlobalStylistControl: some View {
        Button(action: openGlobalStylistOverlay) {
            Label("Ask Stylist", systemImage: "sparkles")
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .tint(AppTab.ai.palette.accent)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Move AI Button to Left", systemImage: "arrow.left.to.line") {
                moveGlobalStylistControl(to: .leading)
            }
            Button("Move AI Button to Right", systemImage: "arrow.right.to.line") {
                moveGlobalStylistControl(to: .trailing)
            }
            Button("Collapse AI Button", systemImage: "arrow.right.to.line") {
                stylistOverlaySession.collapseFloatingControl(
                    toward: stylistOverlaySession.floatingControlPresentation.edge
                )
            }
        }
        .accessibilityLabel("Ask Stylist")
        .accessibilityValue("Expanded")
        .accessibilityHint("Opens the AI Stylist. Use the local context menu to collapse this control.")
        .accessibilityAction(named: "Collapse Ask Stylist") {
            stylistOverlaySession.collapseFloatingControl(toward: stylistOverlaySession.floatingControlPresentation.edge)
        }
        .accessibilityAction(named: "Move to Left") {
            moveGlobalStylistControl(to: .leading)
        }
        .accessibilityAction(named: "Move to Right") {
            moveGlobalStylistControl(to: .trailing)
        }
        .accessibilityAddTraits(.isButton)
    }

    private var collapsedGlobalStylistControl: some View {
        Button(action: stylistOverlaySession.expandFloatingControl) {
            Image(systemName: "sparkles")
                .font(.headline.weight(.semibold))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.borderedProminent)
        .tint(AppTab.ai.palette.accent)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Move AI Button to Left", systemImage: "arrow.left.to.line") {
                moveGlobalStylistControl(to: .leading)
            }
            Button("Move AI Button to Right", systemImage: "arrow.right.to.line") {
                moveGlobalStylistControl(to: .trailing)
            }
        }
        .accessibilityLabel("Ask Stylist")
        .accessibilityValue("Collapsed")
        .accessibilityHint("Double-tap to expand the Ask Stylist control.")
        .accessibilityAction(named: "Expand Ask Stylist") {
            stylistOverlaySession.expandFloatingControl()
        }
        .accessibilityAction(named: "Move to Left") {
            moveGlobalStylistControl(to: .leading)
        }
        .accessibilityAction(named: "Move to Right") {
            moveGlobalStylistControl(to: .trailing)
        }
        .accessibilityAddTraits(.isButton)
    }

    private var globalStylistSheet: some View {
        StylistChatView(
            service: stylistOverlaySession.service,
            initialContext: overlayScanHandoff?.aiChatContext,
            scanHandoff: overlayScanHandoff,
            screenAwarenessSnapshot: overlayScreenAwarenessSnapshot,
            screenAwarenessGeneration: stylistAwarenessCoordinator.generation,
            availableShoppingProductIDs: availableShoppingProductIDs,
            screenContext: overlayScreenContext,
            onSignInRequested: {
                stylistOverlaySession.dismiss()
                selectedTab = .profile
            },
            onUseGeneralStylist: clearScreenAwareness,
            showsDismissControl: true,
            onDismissRequested: stylistOverlaySession.dismiss
        )
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        // Keep the Stylist stable while the keyboard is active. The explicit
        // Done control remains available, but a typing gesture cannot be
        // mistaken for an interactive sheet dismissal.
        .interactiveDismissDisabled(isSoftwareKeyboardVisible)
    }

    private func openGlobalStylistOverlay() {
        if let snapshot = activeScreenAwarenessSnapshot,
           snapshot.isCurrent(
            generation: stylistAwarenessCoordinator.generation,
            availableShoppingProductIDs: availableShoppingProductIDs
           ) {
            stylistOverlaySession.presentScreenAwareness(snapshot)
        } else {
            stylistOverlaySession.presentGeneral()
        }
    }

    private func openHomeStylistConversation() {
        publishScreenAwareness(stylistAwarenessCoordinator.publishHome())
    }

    private func openHomeIntelligenceStylistConversation(_ detail: HomeIntelligenceDetail) {
        publishScreenAwareness(stylistAwarenessCoordinator.publishHomeIntelligence(detail))
    }

    private func prepareHomeIntelligenceShopping(_ detail: HomeIntelligenceDetail) {
        // Keep the Home plan available to Shop's existing global Stylist entry
        // without presenting a second overlay or replacing Shopping navigation.
        _ = stylistAwarenessCoordinator.publishHomeIntelligence(detail)
    }

    private func openClosetItemStylistConversation(_ item: ClosetItem) {
        guard let snapshot = stylistAwarenessCoordinator.publishClosetItem(item) else {
            return
        }
        publishScreenAwareness(snapshot)
    }

    private func openProfileStylistConversation(_ profile: StylistProfileContextProjection) {
        publishScreenAwareness(stylistAwarenessCoordinator.publishProfile(profile))
    }

    private func openWeatherStylistConversation(_ request: WeatherStylistRouteRequest) {
        publishScreenAwareness(stylistAwarenessCoordinator.publishWeatherStyling(request))
    }

    private func openCompareStylistConversation(_ request: CompareStylistRouteRequest) {
        publishScreenAwareness(stylistAwarenessCoordinator.publishScanComparison(request))
    }

    private func openShoppingProductStylistConversation(_ product: AffiliateProduct, availableProductIDs: Set<String>) {
        guard FeatureGate.shared.isCustomerVisible(.aiPersonalShopper) else {
            return
        }
        availableShoppingProductIDs = availableProductIDs
        guard let snapshot = stylistAwarenessCoordinator.publishShoppingProduct(product) else {
            return
        }
        publishScreenAwareness(snapshot)
    }

    private func publishScreenAwareness(_ snapshot: ScreenAwarenessSnapshot) {
        explicitStylistScanRoute = nil
        stylistRouteAuthority = stylistRouteAuthority.publishingCarriedEntry(snapshot.screenContext.entryPoint)
        pendingExplicitGlobalAIGeneration = stylistRouteAuthority.generation
        stylistOverlaySession.presentScreenAwareness(snapshot)
    }

    private func clearScreenAwareness() {
        if stylistAwarenessCoordinator.snapshot != nil {
            stylistAwarenessCoordinator.clear()
        }
        stylistRouteAuthority = stylistRouteAuthority.publishingGlobalAI()
        pendingExplicitGlobalAIGeneration = stylistRouteAuthority.generation
        stylistOverlaySession.useGeneralStylist()
    }

    private func openStylistScanConversation(_ handoff: StylistScanHandoff) {
        stylistAwarenessCoordinator.clear()
        let explicitRoute = handoff.routeToken == nil ? handoff.issuingRouteToken() : handoff
        explicitStylistScanRoute = explicitRoute
        stylistRouteAuthority = StylistAIRouteAuthority(
            generation: stylistRouteAuthority.generation &+ 1,
            screenContext: explicitRoute.aiScreenContext,
            acceptsScanHandoff: true
        )
        pendingExplicitGlobalAIGeneration = stylistRouteAuthority.generation
        stylistOverlaySession.presentScan()
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

    private var bottomNavigationClearance: CGFloat {
        guard !bottomNavigationFrame.isNull,
              !bottomNavigationFrame.isEmpty else {
            return 0
        }
        // The measured frame excludes outer spacing and the home-indicator
        // inset; reserve both so scroll content clears floating navigation.
        return bottomNavigationFrame.height + rootSafeAreaBottomInset + 12
    }

    private var chatBottomNavigationClearance: CGFloat {
        bottomNavigationClearance
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

    private func refreshCloudSyncIfNeeded() {
        guard cloudSyncEnabled,
              CloudSyncProductContract.customerControlsEnabled,
              CloudSyncOwnerValidationConfiguration.runtime.isEnabled,
              !isCloudSyncForegroundRefreshInFlight,
              CloudSyncRuntimeGate.begin() else { return }

        isCloudSyncForegroundRefreshInFlight = true
        Task { @MainActor in
            _ = await CloudSyncOwnerLifecycle.live().enableAndValidate()
            CloudSyncRuntimeGate.end()
            isCloudSyncForegroundRefreshInFlight = false
        }
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

/// Lightweight, decorative-only layer. It has no accessibility elements and
/// only schedules a timeline while this card is visible with live weather.
private struct WeatherConditionAnimationLayer: View {
    let state: WeatherCurrentConditionVisualState
    let isVisible: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let allowsMotion = isVisible && WeatherConditionAnimationPolicy.continuousMotionEnabled(for: state, reduceMotion: reduceMotion)
        ZStack {
            switch state {
            case .rain:
                WeatherPremiumPrecipitationLayer(kind: .rain, isActive: allowsMotion)
            case .drizzle:
                WeatherPremiumPrecipitationLayer(kind: .drizzle, isActive: allowsMotion)
            case .thunderstorm:
                WeatherPremiumPrecipitationLayer(kind: .rain, isActive: allowsMotion)
                if allowsMotion { WeatherLightningAccent() }
            case .thunderstormRisk:
                Image(systemName: "cloud.bolt.fill")
                    .font(.system(size: 54, weight: .light))
                    .foregroundStyle(AppTab.ai.palette.accent.opacity(0.18))
            case .snow:
                WeatherPrecipitationCanvas(kind: .snow, isActive: allowsMotion, depth: .foreground)
            case .clear:
                Circle()
                    .fill(AppTab.ai.palette.accent.opacity(0.10))
                    .frame(width: 90, height: 90)
                    .blur(radius: 10)
            case .cloudy:
                Image(systemName: "cloud.fill")
                    .font(.system(size: 58))
                    .foregroundStyle(AppTab.ai.palette.accent.opacity(0.10))
            case .fog:
                VStack(spacing: 8) {
                    Capsule().fill(.white.opacity(0.13)).frame(width: 106, height: 6)
                    Capsule().fill(.white.opacity(0.09)).frame(width: 76, height: 5)
                }
            case .none:
                EmptyView()
            }
        }
        .frame(width: 138, height: 122)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: state)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Decorative depth layer for observed precipitation only. Forecast risk is
/// intentionally excluded by WeatherConditionAnimationPolicy.
private struct WeatherPremiumPrecipitationLayer: View {
    let kind: WeatherPrecipitationCanvas.Kind
    let isActive: Bool

    var body: some View {
        ZStack {
            WeatherPrecipitationCanvas(kind: kind, isActive: isActive, depth: .background)
            WeatherPrecipitationCanvas(kind: kind, isActive: isActive, depth: .foreground)
        }
    }
}

private struct WeatherPrecipitationCanvas: View {
    enum Kind { case rain, drizzle, snow }
    enum Depth { case background, foreground }
    let kind: Kind
    let isActive: Bool
    let depth: Depth

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: !isActive)) { timeline in
            Canvas { context, size in
                let time = isActive ? timeline.date.timeIntervalSinceReferenceDate : 0
                let count = depth == .background ? 8 : (kind == .drizzle ? 10 : (kind == .snow ? 11 : 13))
                for index in 0..<count {
                    let fraction = (time * speed + Double(index) * 0.137).truncatingRemainder(dividingBy: 1)
                    let x = CGFloat((Double(index) * 0.618).truncatingRemainder(dividingBy: 1)) * size.width
                    let y = CGFloat(fraction) * (size.height + 18) - 9
                    switch kind {
                    case .snow:
                        let diameter: CGFloat = depth == .background ? 2.5 : 3.5
                        context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: diameter, height: diameter)), with: .color(.white.opacity(depth == .background ? 0.24 : 0.52)))
                    case .rain, .drizzle:
                        var drop = Path()
                        let baseLength: CGFloat = kind == .drizzle ? 5 : 10
                        let length = baseLength + CGFloat(index % 3) * (depth == .background ? 1 : 2)
                        drop.move(to: CGPoint(x: x, y: y))
                        drop.addLine(to: CGPoint(x: x - 2, y: y + length))
                        let opacity = depth == .background ? 0.14 : (kind == .drizzle ? 0.24 : 0.38)
                        context.stroke(drop, with: .color(AppTab.ai.palette.accent.opacity(opacity)), lineWidth: depth == .background ? 0.8 : (kind == .drizzle ? 1 : 1.4))
                    }
                }
            }
        }
    }

    private var speed: Double {
        let depthMultiplier = depth == .background ? 0.62 : 1
        switch kind {
        case .rain: return 0.24 * depthMultiplier
        case .drizzle: return 0.11 * depthMultiplier
        case .snow: return 0.055 * depthMultiplier
        }
    }
}

private struct WeatherPremiumAtmosphere: View {
    let state: WeatherCurrentConditionVisualState

    var body: some View {
        ZStack {
            LinearGradient(
                colors: backgroundColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Ellipse()
                .fill(AppTab.ai.palette.accent.opacity(0.18))
                .frame(width: 420, height: 250)
                .blur(radius: 64)
                .offset(x: 130, y: -250)
            Ellipse()
                .fill(.cyan.opacity(state == .clear ? 0.12 : 0.05))
                .frame(width: 360, height: 220)
                .blur(radius: 72)
                .offset(x: -140, y: 310)
        }
        .accessibilityHidden(true)
    }

    private var backgroundColors: [Color] {
        switch state {
        case .thunderstorm, .thunderstormRisk:
            return [Color(red: 0.025, green: 0.075, blue: 0.12), Color(red: 0.07, green: 0.12, blue: 0.18), Color.black]
        case .rain, .drizzle:
            return [Color(red: 0.035, green: 0.11, blue: 0.16), Color(red: 0.08, green: 0.16, blue: 0.22), Color.black]
        case .clear:
            return [Color(red: 0.05, green: 0.09, blue: 0.18), Color(red: 0.13, green: 0.10, blue: 0.24), Color.black]
        case .snow, .fog, .cloudy:
            return [Color(red: 0.04, green: 0.08, blue: 0.12), Color(red: 0.10, green: 0.13, blue: 0.18), Color.black]
        case .none:
            return [Color.black, Color(red: 0.04, green: 0.05, blue: 0.09), Color.black]
        }
    }
}

private struct WeatherLightningAccent: View {
    @State private var isVisible = false

    var body: some View {
        Image(systemName: "bolt.fill")
            .font(.system(size: 26, weight: .light))
            .foregroundStyle(.white.opacity(0.42))
            .offset(x: 28, y: -25)
            .opacity(isVisible ? 1 : 0)
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(8))
                    guard !Task.isCancelled else { break }
                    withAnimation(.easeInOut(duration: 0.16)) { isVisible = true }
                    try? await Task.sleep(for: .milliseconds(160))
                    withAnimation(.easeOut(duration: 0.22)) { isVisible = false }
                }
            }
            .onDisappear { isVisible = false }
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
    @ObservedObject private var weatherAuthority = WeatherKitAuthority.shared
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
    @State private var betaAIConnectionVerified = false
    @State private var betaAIStatus = ""
    @State private var cachedClosetItems: [ClosetItem] = []
    @State private var cachedLatestStoredScan: SafeHomeStoredScan?
    @State private var cachedSavedScanCount = 0

    var body: some View {
        if let attribution = weatherAuthority.attribution {
            panelNavigation.weatherAttributed(attribution, surface: .aiWeatherStylist)
        } else {
            panelNavigation
        }
    }

    private var panelNavigation: some View {
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
                LegacyProviderCredentialRetirement.run()
                betaAIConnectionVerified = true
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
            .alert("KigoStylist AI Awareness", isPresented: $showAwarenessTestResult) {
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
                    .navigationTitle("KigoStylist AI Awareness")
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

                    Text("KigoStylist AI Stylist")
                        .font(.title3)
                        .fontWeight(.bold)

                    Text("Powered by KigoStylist AI")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppTab.ai.palette.accent)
                }

                Spacer(minLength: 8)
            }

            Text(profileHasSavedData ? "Your personal stylist checks saved weather, closet, sizes, scans, and style memory before suggesting what to wear." : "Add your profile, closet, and scans when you're ready. KigoStylist will use them before suggesting what to wear.")
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
                    Text("KigoStylist AI Test Access")
                        .font(.title3)
                        .fontWeight(.bold)

                    Text(betaChatGPTSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }

            if !betaAIStatus.isEmpty {
                Label(betaAIStatus, systemImage: betaAIConnectionVerified ? "checkmark.circle.fill" : "info.circle")
                    .font(.caption)
                    .foregroundStyle(betaAIConnectionVerified ? .green : .secondary)
            }

            Text("Founder beta only. Public builds use the secure KigoStylist AI service instead of on-device keys.")
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
                        message = "Trip planner is ready. KigoStylist will use weather, closet, sizes, and style memory."
                    }
                }

                HStack(spacing: 10) {
                    aiActionCard("Dress Me For Work", icon: "briefcase.fill") {
                        showTodaysOutfitAdvice = true
                        message = "Work outfit request is ready."
                    }
                    aiActionCard("Dress Me For Church", icon: "building.columns.fill") {
                        message = "Church outfit guidance is ready. KigoStylist will keep it respectful and polished."
                    }
                }

                HStack(spacing: 10) {
                    aiActionCard("Dress Me For Wedding", icon: "heart.fill") {
                        message = "Wedding outfit guidance is ready. KigoStylist will check formality, color, shoes, and accessories."
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
            Label("KigoStylist AI Stylist", systemImage: "sparkles")
                .font(.title2)
                .fontWeight(.bold)

            Text("KigoStylist is your personal AI fashion stylist, powered by KigoStylist AI.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .lineSpacing(5)

            activeChatGPTCard
            chatGPTAppAwarenessCard
            connectedServicesCard

            Label("KigoStylist keeps your stylist memory private.", systemImage: "lock.shield")
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

                    Text("KigoStylist AI Stylist")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .minimumScaleFactor(0.8)

                    Text("Powered by KigoStylist AI")
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
                    message = "Trip packing is ready. KigoStylist can use your closet, weather, sizes, and travel plans."
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
                    Text("KigoStylist AI Awareness")
                        .font(.title3)
                        .fontWeight(.bold)

                    Text("KigoStylist AI can use your KigoStylist memory, closet, sizes, weather, saved scans, and style preferences when helping you.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                }
            }

            Toggle(isOn: $shareAppContextWithChatGPT) {
                Text(shareAppContextWithChatGPT ? "KigoStylist AI Awareness On" : "KigoStylist AI Awareness Off")
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
                    message = shareAppContextWithChatGPT ? "KigoStylist AI Awareness resumed." : "KigoStylist AI Awareness paused."
                }

                aiSmallAction("View Stored Preferences", "list.bullet.rectangle") {
                    showMemoryDetails = true
                }

                aiSmallAction("Clear AI Memory", "trash") {
                    shareAppContextWithChatGPT = false
                    message = "KigoStylist AI memory was cleared for AI use. Profile fields remain editable in Profile."
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
                        ? "KigoStylist AI Awareness test completed."
                        : "KigoStylist AI Awareness is off. Turn it on to let KigoStylist AI use your style context."
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

                    Text(shareAppContextWithChatGPT ? "KigoStylist AI can use your style memory when helping with outfits." : "Turn Personal Style Memory on to let KigoStylist AI use your style context.")
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
                message = "KigoStylist AI is using Personal Style Memory for today's outfit."
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

            Label("KigoStylist uses this memory only for styling, fit, outfit, shopping, and weather recommendations.", systemImage: "lock.shield")
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
            return "KigoStylist AI Awareness is off. Turn it on so KigoStylist AI can use your style context."
        }

        return """
        KigoStylist AI Awareness is on.

        KigoStylist AI can use:
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

                    Text("KigoStylist AI suggests a polished smart-casual look from your saved style profile.")
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
            Label("KigoStylist AI Stylist", systemImage: "sparkles")
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
            KigoStylist AI Stylist chat.
            Closet items: \(savedClosetCount)
            Saved scans: \(savedScanCount)
            Recent scan context: \(latestScanContextForAI)
            """
        )

        let client = OpenAIStylistClient(model: openAIModel)

        let guidedQuestion = """
        Answer the customer's exact message as KigoStylist AI Stylist.
        If the customer says hello, greet them naturally.
        If they ask what you know about them, use only saved KigoStylist profile, closet, weather, scan history, and style memory. Do not invent personal details.
        If they ask you to read or explain their score, use the latest saved scan score from app context. Say the score, the match rating, why KigoStylist gave that score, and one or two ways to improve it. Do not create a new score.
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
        _ = error
        _ = prompt
        _ = retryAttempt
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

        return "\(base) Today I would build around a clean top, dark denim or chinos, polished shoes, and one accessory. Scan the outfit when ready so KigoStylist can score the exact look."
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
        LocalDateContext().timeBucket.greetingLowercase
    }

    private var weatherTemperatureText: String {
        weatherAuthority.snapshot.map { "\($0.temperatureFahrenheit)°F" } ?? "Weather unavailable"
    }

    private var weather: String {
        weatherAuthority.snapshot.map { "\($0.temperatureFahrenheit)°F" } ?? "Weather unavailable"
    }

    private var weatherSource: String {
        weatherAuthority.snapshot == nil ? "Unavailable" : "WeatherKit"
    }

    private var weatherConditionText: String {
        weatherAuthority.snapshot?.condition ?? "Weather unavailable"
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
            return "Today's weather is \(weatherTemperatureText) and \(weatherConditionText.lowercased()). Based on your saved wardrobe, preferences, and today's occasion, KigoStylist recommends a clean \(plannedOccasionText.lowercased()) look."
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
            return "Add a few closet items first so KigoStylist can recommend outfits you already own before suggesting purchases."
        }
        if closetHasShoes && closetHasTop && closetHasPants {
            return "You already own the core pieces for today's outfit. KigoStylist will only suggest shopping when something truly improves the look."
        }
        return "KigoStylist checked your closet first and found one or two gaps before recommending anything new."
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
            return "You already own the key pieces. KigoStylist recommends styling what you have before shopping."
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
                Text("KigoStylist AI")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Powered by KigoStylist AI")
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

            Label("Model routing is managed securely by KigoStylist.", systemImage: "lock.shield")
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
            return "KigoStylist AI is active on this phone."
        }

        return "KigoStylist AI uses the authenticated service connection."
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

struct WeatherStylistRouteAction {
    let open: (WeatherStylistRouteRequest) -> Void

    static let unavailable = Self(open: { _ in })
}

private struct WeatherStylistRouteActionKey: EnvironmentKey {
    static let defaultValue = WeatherStylistRouteAction.unavailable
}

private extension EnvironmentValues {
    var weatherStylistRouteAction: WeatherStylistRouteAction {
        get { self[WeatherStylistRouteActionKey.self] }
        set { self[WeatherStylistRouteActionKey.self] = newValue }
    }
}

struct WeatherStylingButton<LabelContent: View>: View {
    @ViewBuilder var label: () -> LabelContent
    @State private var showWeatherPanel = false
    @Environment(\.weatherStylistRouteAction) private var weatherStylistRouteAction

    var body: some View {
        Button {
            showWeatherPanel = true
        } label: {
            label()
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showWeatherPanel) {
            WeatherStylingPanel { request in
                showWeatherPanel = false
                DispatchQueue.main.async {
                    weatherStylistRouteAction.open(request)
                }
            }
        }
    }
}

struct WeatherStylingPanel: View {
    private enum WeatherStylingTab: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case details = "Details"
        var id: Self { self }
        var icon: String { self == .overview ? "sun.max.fill" : "chart.xyaxis.line" }
    }

    private enum WeatherStylingDestination: Identifiable, Equatable {
        case hourly, daily, recommendation
        var id: String {
            switch self {
            case .hourly: return "hourly"
            case .daily: return "daily"
            case .recommendation: return "recommendation"
            }
        }
    }

    @ObservedObject private var weatherAuthority = WeatherKitAuthority.shared
    @AppStorage("plannedOccasion") private var plannedOccasion = ""
    @AppStorage("favoriteColors") private var favoriteColors = ""
    @AppStorage("workSetting") private var workSetting = ""
    @AppStorage("shoppingBudget") private var budget = ""
    @State private var cityDraft = ""
    @State private var showsManualCityControls = false
    @State private var selectedTab: WeatherStylingTab = .overview
    @State private var destination: WeatherStylingDestination?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let onOpenStylist: (WeatherStylistRouteRequest) -> Void

    init(onOpenStylist: @escaping (WeatherStylistRouteRequest) -> Void = { _ in }) {
        self.onOpenStylist = onOpenStylist
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    weatherTabPicker
                    if selectedTab == .overview {
                        currentWeatherCard
                        forecastCard
                        dailyForecastCard
                        recommendationCard
                        changeCityCard
                        if showsManualCityControls {
                            manualCityCard
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    } else {
                        weatherDetailsCard
                    }
                    privacyNote
                }
                .padding()
            }
            .scrollContentBackground(.hidden)
            .background {
                WeatherPremiumAtmosphere(state: weatherVisualState)
                    .ignoresSafeArea()
            }
            .tint(AppTab.ai.palette.accent)
            .navigationTitle("Weather Styling")
            .navigationBarTitleDisplayMode(.inline)
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
            .sheet(item: $destination) { destination in
                weatherDestination(destination)
            }
        }
        .modifier(WeatherAttributionIfAvailable(attribution: weatherAuthority.attribution, surface: .weatherStyling))
    }

    private var weatherTabPicker: some View {
        HStack(spacing: 6) {
            ForEach(WeatherStylingTab.allCases) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedTab = tab }
                } label: {
                    Label(tab.rawValue, systemImage: tab.icon)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .foregroundStyle(selectedTab == tab ? .white : .primary)
                        .background {
                            if selectedTab == tab {
                                Capsule().fill(AppTab.ai.palette.accent.gradient)
                            } else {
                                Capsule().fill(Color.clear)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
        }
        .padding(4)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(.white.opacity(0.12))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Weather Styling section")
    }

    private var currentWeatherCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current Weather")
                        .font(.title3.weight(.bold))
                    Text(locationText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(lastUpdatedText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                weatherStatusBadge(weatherStateLabel, icon: isLiveWeather ? "checkmark.circle.fill" : "exclamationmark.circle.fill", tint: isLiveWeather ? .green : (hasSnapshot ? .orange : .secondary))
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 16) {
                    weatherHeroSymbol
                    Text(weatherTemperatureText)
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    VStack(alignment: .leading, spacing: 5) {
                        Text(weatherConditionText)
                            .font(.title3.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(weatherPrecipitationSummary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .layoutPriority(1)
                }
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 14) {
                        weatherHeroSymbol
                        Text(weatherTemperatureText)
                            .font(.system(size: 60, weight: .bold, design: .rounded))
                            .monospacedDigit()
                    }
                    Text(weatherConditionText)
                        .font(.title3.weight(.semibold))
                    Text(weatherPrecipitationSummary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                weatherMetric("Feels Like", resolved(weatherFeelsLike, fallback: weatherTemperatureText), "thermometer.medium")
                weatherMetric("Precipitation Now", weatherCurrentPrecipitationText, "drop.fill")
                weatherMetric("Rain Chance (Next 6h)", resolved(weatherRainChance, fallback: "Not available"), "cloud.rain.fill")
                weatherMetric("Humidity", resolved(weatherHumidity, fallback: "Not available"), "humidity.fill")
                weatherMetric("Wind", resolved(weatherWindSpeed, fallback: "Not available"), "wind")
                weatherMetric("UV Index", resolved(weatherUVText, fallback: "Not available"), "sun.max.fill")
                weatherMetric("Updated", lastUpdatedText, "clock.fill")
            }

            if isWeatherStale {
                Label("Weather may be outdated. Tap Refresh.", systemImage: "clock.badge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding()
        .background(alignment: .topTrailing) {
            WeatherConditionAnimationLayer(
                state: WeatherCurrentConditionVisualState.make(
                    snapshot: weatherAuthority.snapshot,
                    hasLiveWeather: isLiveWeather
                ),
                isVisible: selectedTab == .overview
            )
            .padding(.trailing, 8)
            .padding(.top, 6)
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(.white.opacity(0.20))
        }
        .shadow(color: AppTab.ai.palette.accent.opacity(0.18), radius: 20, x: 0, y: 10)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: liveWeatherUpdatedAt)
    }

    private var forecastCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Hourly Forecast", systemImage: "clock")
                    .font(.title3.weight(.bold))
                Spacer()
                Button {
                    destination = .hourly
                } label: {
                    HStack(spacing: 4) {
                        Text("View Full Hourly")
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTab.ai.palette.accent)
                .contentShape(Rectangle())
                .accessibilityLabel("View full hourly forecast")
            }

            if weatherHourlyEntries.isEmpty {
                Text("Hourly forecast will appear after live weather refresh.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(weatherHourlyEntries) { hour in
                            hourlyForecastCard(hour)
                        }
                    }
                    .padding(.vertical, 2)
                    .padding(.trailing, 18)
                }
                .accessibilityLabel("Hourly weather forecast")
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
        .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.12)) }
    }

    private var dailyForecastCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("10-Day Forecast", systemImage: "calendar")
                    .font(.title3.weight(.bold))
                Spacer()
                Button {
                    destination = .daily
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTab.ai.palette.accent)
                .contentShape(Rectangle())
                .accessibilityLabel("View full \(dailyForecastDestinationTitle.lowercased())")
            }
            if weatherDailyEntries.isEmpty {
                Text(resolved(weatherDailyForecast, fallback: "Daily forecast will appear after live weather refresh."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(weatherDailyEntries.prefix(5))) { day in
                    HStack(spacing: 10) {
                        Text(day.date, format: .dateTime.weekday(.abbreviated))
                            .frame(width: 48, alignment: .leading)
                        Image(systemName: weatherSymbol(for: day.condition))
                            .foregroundStyle(AppTab.ai.palette.accent)
                            .frame(width: 22)
                            .accessibilityHidden(true)
                        Text(day.condition)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .layoutPriority(1)
                        Spacer(minLength: 8)
                        dailyTemperatureRangeBar(for: day)
                            .frame(width: 72)
                        Text("\(day.highTemperatureFahrenheit)°")
                            .fontWeight(.semibold)
                        Text("\(day.lowTemperatureFahrenheit)°")
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                    .accessibilityElement(children: .combine)
                }
            }

            Button {
                destination = .daily
            } label: {
                HStack(spacing: 4) {
                    Text(dailyForecastActionTitle)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .buttonStyle(.plain)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppTab.ai.palette.accent)
            .contentShape(Rectangle())
            .accessibilityLabel("View full \(dailyForecastDestinationTitle.lowercased())")
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
        .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.12)) }
    }

    private var recommendationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                recommendationHeaderHorizontal
                recommendationHeaderStacked
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(recommendationPreviewItems) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: item.symbol)
                            .foregroundStyle(AppTab.ai.palette.accent)
                            .frame(width: 20)
                            .accessibilityHidden(true)
                        Text(item.role + ":")
                            .fontWeight(.semibold)
                        Text(item.title)
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                    .accessibilityElement(children: .combine)
                }
            }

            Text(weatherRecommendation.personalizationExplanation)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let umbrella = weatherRecommendation.umbrellaGuidance {
                Label(umbrella, systemImage: "umbrella.fill")
                    .font(.caption)
                    .foregroundStyle(AppTab.ai.palette.accent)
            }

            Label(weatherRecommendation.personalizationTier.rawValue, systemImage: personalizationSourceSymbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(weatherRecommendation.personalizationTier == .closet ? AppTab.ai.palette.accent : .secondary)
                .accessibilityHint(weatherRecommendation.personalizationTier == .closet ? "Recommendations use verified Closet items." : "Closet ownership is not claimed without verified Closet evidence.")

            Button {
                onOpenStylist(weatherStylistRouteRequest)
            } label: {
                Label("View Full Outfit Ideas", systemImage: "wand.and.stars")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

        }
        .padding()
        .appCard(.ai)
    }

    private var changeCityCard: some View {
        Button {
            cityDraft = weatherCity
            withAnimation(.easeInOut(duration: 0.2)) { showsManualCityControls.toggle() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.title3)
                    .foregroundStyle(AppTab.ai.palette.accent)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Change City")
                        .font(.headline.weight(.bold))
                    Text("Update location for accurate weather & recommendations")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel("Change city")
        .padding()
        .appCard(.ai)
    }

    private var recommendationHeaderHorizontal: some View {
        HStack(alignment: .top, spacing: 16) {
            recommendationTitle
            Spacer(minLength: 12)
            weatherMatchSummary
            recommendationDetailButton
        }
    }

    private var recommendationHeaderStacked: some View {
        VStack(alignment: .leading, spacing: 10) {
            recommendationTitle
            HStack {
                Spacer()
                weatherMatchSummary
                recommendationDetailButton
            }
        }
    }

    private var recommendationDetailButton: some View {
        Button {
            destination = .recommendation
        } label: {
            Image(systemName: "chevron.right")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel("View recommendation details")
    }

    private var recommendationTitle: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text("Recommended For Today")
                Text(weatherRecommendation.contextTitle)
                    .font(.subheadline)
                    .fontWeight(.regular)
                    .foregroundStyle(.secondary)
            }
                .font(.headline)
                .fontWeight(.bold)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
        } icon: {
            Image(systemName: "tshirt.fill")
        }
        .accessibilityLabel("Recommended for today")
    }

    private var weatherMatchSummary: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text("Weather Match")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            if let score = weatherRecommendation.weatherMatchScore {
                Text("\(score)/100")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.green)
            }
            Text(weatherRecommendation.weatherMatchLabel)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.green)
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(weatherRecommendation.weatherMatchScore.map { "Weather Match, \($0) out of 100, \(weatherRecommendation.weatherMatchLabel)" } ?? weatherRecommendation.weatherMatchLabel)
    }

    private var recommendationPreviewItems: [WeatherStylingRecommendation.Item] {
        let previewRoles = ["Top", "Bottom", "Shoes"]
        return previewRoles.compactMap { role in
            weatherRecommendation.items.first { $0.role == role }
        }
    }

    private var manualCityCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Manual City")
                .font(.headline)
                .fontWeight(.bold)

            TextField("City, State", text: $cityDraft)
                .textInputAutocapitalization(.words)
                .padding(.horizontal, 12)
                .frame(minHeight: 48)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(AppTab.ai.palette.accent.opacity(0.2))
                }

            Button {
                weatherAuthority.refresh(city: cityDraft)
                withAnimation(.easeInOut(duration: 0.2)) {
                    showsManualCityControls = false
                }
            } label: {
                Label("Use This City", systemImage: "location.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)

            Text("If location permission is off, a saved city still gives guest users weather-based outfit advice.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .appCard(.ai)
    }

    private var weatherDetailsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Weather Details", systemImage: "chart.xyaxis.line")
                .font(.headline.weight(.bold))
            Text("Use the current WeatherKit conditions to understand how weather may affect your outfit.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                weatherMetric("Precipitation Now", weatherCurrentPrecipitationText, "drop.fill")
                weatherMetric("Rain Chance (Next 6h)", resolved(weatherRainChance, fallback: "Not available"), "cloud.rain.fill")
                weatherMetric("Humidity", resolved(weatherHumidity, fallback: "Not available"), "humidity.fill")
                weatherMetric("Wind", resolved(weatherWindSpeed, fallback: "Not available"), "wind")
                weatherMetric("UV Index", resolved(weatherUVText, fallback: "Not available"), "sun.max.fill")
                weatherMetric("Feels Like", resolved(weatherFeelsLike, fallback: weatherTemperatureText), "thermometer.medium")
                weatherMetric("Updated", lastUpdatedText, "clock.fill")
            }
            ForEach(weatherRecommendation.reasoning, id: \.self) { reason in
                Label(reason, systemImage: "checkmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            refreshControl
            if let attribution = weatherAuthority.attribution {
                WeatherKitAttributionView(attribution: attribution, surface: .weatherStyling)
            }
        }
        .padding()
        .appCard(.ai)
    }

    @ViewBuilder
    private func weatherDestination(_ destination: WeatherStylingDestination) -> some View {
        NavigationStack {
            List {
                switch destination {
                case .hourly:
                    Section("Hourly Forecast") {
                        ForEach(weatherHourlyEntries) { hour in
                            HStack {
                                Image(systemName: WeatherHourlyPresentationAuthority.symbolName(for: hour))
                                    .foregroundStyle(AppTab.ai.palette.accent)
                                Text(hour.date, format: .dateTime.hour().minute())
                                Spacer()
                                Text(hour.condition).foregroundStyle(.secondary)
                                Text("\(hour.temperatureFahrenheit)°").fontWeight(.semibold)
                            }
                        }
                    }
                case .daily:
                    Section(dailyForecastDestinationTitle) {
                        ForEach(weatherDailyEntries) { day in
                            dailyForecastRow(day)
                            .accessibilityElement(children: .combine)
                        }
                    }
                case .recommendation:
                    Section(weatherRecommendation.contextTitle) {
                        ForEach(weatherRecommendation.items) { item in
                            Label("\(item.role): \(item.title)", systemImage: item.symbol)
                        }
                    }
                    Section("Why this works") {
                        ForEach(weatherRecommendation.reasoning, id: \.self) { Text($0) }
                    }
                    Section("Availability") {
                        Text(weatherRecommendation.personalizationExplanation)
                        Text(weatherRecommendation.personalizationTier == .closet
                             ? "Only the named Closet items are represented as owned. Any weather accessories remain general guidance."
                             : "KigoStylist only labels an item as owned when verified Closet evidence is available.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(destination == .hourly ? "Hourly Forecast" : (destination == .daily ? dailyForecastDestinationTitle : "Outfit Ideas"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { self.destination = nil }
                }
            }
            .appScreenBackground(.ai)
        }
        .modifier(WeatherAttributionIfAvailable(
            attribution: weatherAuthority.attribution,
            surface: destination == .hourly ? .hourlyForecast : (destination == .daily ? .tenDayForecast : .weatherStyling)
        ))
    }

    /// The full 10-Day destination is deliberately vertical: it trades a
    /// brittle one-line grid for readable date, condition, rain, and temps on
    /// narrow iPhone widths and at accessibility Dynamic Type sizes.
    private func dailyForecastRow(_ day: WeatherDailyForecastEntry) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: weatherSymbol(for: day.condition))
                    .foregroundStyle(AppTab.ai.palette.accent)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                Text(day.date, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                    .font(.body.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                Spacer(minLength: 8)
                dailyTemperatureRangeBar(for: day)
                    .frame(width: 76)
                Text("\(day.highTemperatureFahrenheit)° / \(day.lowTemperatureFahrenheit)°")
                    .font(.body.weight(.semibold))
                    .fixedSize(horizontal: true, vertical: false)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(day.condition)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                Spacer(minLength: 8)
                if let precipitation = day.precipitationProbabilityPercent {
                    Text("\(precipitation)% rain")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
        }
        .padding(.vertical, 3)
    }

    private var privacyNote: some View {
        DisclosureGroup {
            Text("Based on current available weather. Weather can change, so KigoStylist shows the last updated time and avoids promising perfect accuracy.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .padding(.top, 4)
        } label: {
            Label("Weather accuracy", systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
    }

    private func weatherMetric(_ title: String, _ value: String, _ icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(AppTab.ai.palette.accent)
                .frame(width: 28, height: 28)
                .background(AppTab.ai.palette.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
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
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.08)) }
        .accessibilityElement(children: .combine)
    }

    private func weatherStatusBadge(_ title: String, icon: String, tint: Color) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(tint.opacity(0.12), in: Capsule())
            .accessibilityElement(children: .combine)
    }

    private var refreshControl: some View {
        Button {
            weatherAuthority.refresh()
        } label: {
            Label(weatherAuthority.isRefreshing ? "Updating Live Weather…" : "Refresh", systemImage: "arrow.clockwise")
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
        .disabled(weatherAuthority.isRefreshing)
        .accessibilityHint("Refreshes current WeatherKit weather")
    }

    private func hourlyForecastCard(_ hour: WeatherHourlyForecastEntry) -> some View {
        VStack(spacing: 9) {
            Text(hour.date, format: .dateTime.hour())
                .font(.caption)
                .foregroundStyle(.secondary)
            Image(systemName: WeatherHourlyPresentationAuthority.symbolName(for: hour))
                .font(.title2)
                .foregroundStyle(AppTab.ai.palette.accent)
                .accessibilityHidden(true)
            Text("\(hour.temperatureFahrenheit)°")
                .font(.headline)
            Text(hour.condition)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(width: 82, alignment: .top)
        .padding(.vertical, 8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.08)) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(hour.date.formatted(date: .omitted, time: .shortened)), \(hour.temperatureFahrenheit) degrees, \(hour.condition)")
    }

    private func weatherSymbol(for condition: String, symbolName: String? = nil) -> String {
        if let symbolName, !symbolName.isEmpty { return symbolName }
        let normalized = condition.lowercased()
        if normalized.contains("thunder") || normalized.contains("storm") { return "cloud.bolt.rain.fill" }
        if normalized.contains("snow") || normalized.contains("sleet") { return "cloud.snow.fill" }
        if normalized.contains("rain") || normalized.contains("drizzle") { return "cloud.rain.fill" }
        if normalized.contains("wind") { return "wind" }
        if normalized.contains("fog") || normalized.contains("haze") { return "cloud.fog.fill" }
        // WeatherKit symbols own clear/sunny day versus night. A legacy daily
        // entry without a provider symbol stays neutral rather than claiming sun.
        if normalized.contains("clear") || normalized.contains("sunny") { return "cloud.fill" }
        if normalized.contains("cloud") { return "cloud.fill" }
        return "cloud.fill"
    }

    private var weatherVisualState: WeatherCurrentConditionVisualState {
        WeatherCurrentConditionVisualState.make(snapshot: weatherAuthority.snapshot, hasLiveWeather: isLiveWeather)
    }

    private var weatherHeroSymbol: some View {
        Image(systemName: weatherSymbol(for: weatherConditionText, symbolName: weatherAuthority.snapshot?.currentSymbolName))
            .font(.system(size: 42, weight: .medium))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(AppTab.ai.palette.accent)
            .frame(width: 70, height: 70)
            .background(AppTab.ai.palette.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 22))
            .accessibilityHidden(true)
    }

    private var weatherPrecipitationSummary: String {
        guard let snapshot = weatherAuthority.snapshot else { return "Weather details unavailable" }
        switch snapshot.currentPrecipitationState() {
        case .rain: return "Rain observed now"
        case .snow: return "Snow observed now"
        case .sleetMixed: return "Mixed precipitation observed now"
        case .precipitation: return "Precipitation observed now at \(snapshot.currentPrecipitationDisplayText)"
        case .unknown: return "Current precipitation unavailable"
        case .none: break
        }
        if let advisory = WeatherUmbrellaAdvisory.make(snapshot: snapshot, now: Date()).guidance {
            return advisory.replacingOccurrences(of: " — ", with: ". ")
        }
        if let chance = snapshot.rainChancePercent, chance > 0 { return "(chance)% chance of rain in the next 6 hours" }
        return "No precipitation observed now"
    }

    private var dailyTemperatureBounds: ClosedRange<Int>? {
        guard let low = weatherDailyEntries.map(\.lowTemperatureFahrenheit).min(),
              let high = weatherDailyEntries.map(\.highTemperatureFahrenheit).max(),
              high > low else { return nil }
        return low...high
    }

    private func dailyTemperatureRangeBar(for day: WeatherDailyForecastEntry) -> some View {
        GeometryReader { geometry in
            if let bounds = dailyTemperatureBounds {
                let span = Double(bounds.upperBound - bounds.lowerBound)
                let lowOffset = CGFloat(Double(day.lowTemperatureFahrenheit - bounds.lowerBound) / span) * geometry.size.width
                let rangeWidth = max(8, CGFloat(Double(day.highTemperatureFahrenheit - day.lowTemperatureFahrenheit) / span) * geometry.size.width)
                Capsule()
                    .fill(.white.opacity(0.15))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(LinearGradient(colors: [AppTab.ai.palette.accent, .orange], startPoint: .leading, endPoint: .trailing))
                            .frame(width: rangeWidth)
                            .offset(x: lowOffset)
                    }
            } else {
                Capsule().fill(.white.opacity(0.15))
            }
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }

    private var weather: String { weatherAuthority.snapshot.map { "\($0.temperatureFahrenheit)°F" } ?? "" }
    private var weatherCondition: String { weatherAuthority.snapshot?.condition ?? "" }
    private var weatherCity: String { weatherAuthority.snapshot?.locationName ?? "" }
    private var hasSnapshot: Bool { weatherAuthority.snapshot != nil }
    private var isLiveWeather: Bool { hasSnapshot && weatherAuthority.hasLiveWeatherForCurrentSession }
    private var weatherStateLabel: String {
        if weatherAuthority.isRefreshing { return "Updating Live Weather" }
        if isLiveWeather { return "Live Weather" }
        return hasSnapshot ? "Saved Weather" : "Unavailable"
    }
    private var weatherFeelsLike: String { weatherAuthority.snapshot.map { "\($0.feelsLikeFahrenheit)°F" } ?? "" }
    private var weatherCurrentPrecipitationText: String {
        guard let snapshot = weatherAuthority.snapshot else { return "Not available" }
        return snapshot.currentPrecipitationDisplayText
    }
    private var weatherRainChance: String { weatherAuthority.snapshot?.rainChancePercent.map { "\($0)%" } ?? "" }
    private var weatherHumidity: String { weatherAuthority.snapshot?.humidityPercent.map { "\($0)%" } ?? "" }
    private var weatherWindSpeed: String {
        guard let snapshot = weatherAuthority.snapshot,
              let windMph = snapshot.windMph else { return "" }
        if let direction = snapshot.windDirection {
            return "\(windMph) mph \(direction)"
        }
        return "\(windMph) mph"
    }
    private var weatherUVIndex: String { weatherAuthority.snapshot?.uvIndex.map(String.init) ?? "" }
    private var weatherUVText: String {
        guard let index = weatherAuthority.snapshot?.uvIndex else { return "" }
        return "\(index)\n\(uvSeverity(for: index))"
    }
    private var weatherHourlyEntries: [WeatherHourlyForecastEntry] {
        WeatherHourlyPresentationAuthority.currentOrFuture(weatherAuthority.snapshot?.hourlyForecast ?? [])
    }
    private var weatherDailyEntries: [WeatherDailyForecastEntry] { weatherAuthority.snapshot?.dailyForecast ?? [] }
    private var dailyForecastDestinationTitle: String {
        let count = weatherDailyEntries.count
        return count > 0 ? "\(count)-Day Forecast" : "Daily Forecast"
    }
    private var dailyForecastActionTitle: String { "View \(dailyForecastDestinationTitle)" }
    private var weatherDailyForecast: String { weatherAuthority.snapshot?.dailySummary ?? "" }
    private var weatherAlert: String { "" }
    private var liveWeatherUpdatedAt: TimeInterval { weatherAuthority.snapshot?.observedAt.timeIntervalSince1970 ?? 0 }

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
        if weatherAuthority.isRefreshing {
            return "Updating Live Weather…"
        }
        if isLiveWeather {
            return "Live Weather. \(lastUpdatedText)."
        }
        if weatherCity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Add a city or allow location to receive weather-based outfit advice."
        }
        return "Live Weather is unavailable. Showing Saved Weather."
    }

    private func uvSeverity(for index: Int) -> String {
        switch index {
        case ..<0: return "Not available"
        case 0...2: return "Low"
        case 3...5: return "Moderate"
        case 6...7: return "High"
        case 8...10: return "Very High"
        default: return "Extreme"
        }
    }

    private var weatherRecommendation: WeatherStylingRecommendation {
        WeatherStylingRecommendation.make(
            snapshot: weatherAuthority.snapshot,
            occasion: plannedOccasion,
            personalization: WeatherStylingPersonalizationInput.current()
        )
    }

    private var personalizationSourceSymbol: String {
        switch weatherRecommendation.personalizationTier {
        case .closet: "hanger"
        case .savedScan: "photo.on.rectangle"
        case .profile: "person.crop.circle"
        case .general: "sparkles"
        }
    }

    private var weatherStylistRouteRequest: WeatherStylistRouteRequest {
        WeatherStylistRouteRequest(
            snapshot: weatherAuthority.snapshot,
            recommendation: weatherRecommendation,
            occasion: plannedOccasion,
            workplace: WeatherStylingPersonalizationInput.current().workContext ?? workSetting
        )
    }
}
