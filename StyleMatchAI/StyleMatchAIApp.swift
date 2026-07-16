import SwiftUI
import AuthenticationServices
#if canImport(BackgroundTasks) && os(iOS)
import BackgroundTasks
#endif
#if canImport(UserNotifications)
import UserNotifications
#endif
#if canImport(UIKit)
import UIKit
#endif

#if DEBUG
private struct StyleMatchBuildIdentity {
    static let gitCommit = "not embedded"
    static let buildConfiguration = "Debug"
    static let targetName = "StyleMatchAI"
    static let schemeName = "StyleMatchAI"

    let bundleIdentifier: String
    let version: String
    let build: String
    let gitCommit: String
    let buildDate: Date?
    let buildConfiguration: String
    let targetName: String
    let schemeName: String
    let apiBaseURL: String
    let shareDomain: String

    static var current: StyleMatchBuildIdentity {
        let bundle = Bundle.main
        let backend = AppBackendConfiguration.production(bundle: bundle)
        let executableDate = bundle.executableURL.flatMap {
            try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        }
        return StyleMatchBuildIdentity(
            bundleIdentifier: bundle.bundleIdentifier ?? "unknown",
            version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            gitCommit: gitCommit,
            buildDate: executableDate,
            buildConfiguration: buildConfiguration,
            targetName: targetName,
            schemeName: schemeName,
            apiBaseURL: backend.apiBaseURL.absoluteString,
            shareDomain: backend.shareDomain
        )
    }

    static func logLaunch(at timestamp: Date = Date()) {
        let identity = current
        print("[StyleMatch Build Identity] bundle_id=\(identity.bundleIdentifier) version=\(identity.version) build=\(identity.build) git_commit=\(identity.gitCommit) configuration=\(identity.buildConfiguration) target=\(identity.targetName) scheme=\(identity.schemeName) build_date=\(dateText(identity.buildDate)) launch_timestamp=\(dateText(timestamp)) api_base_url=\(identity.apiBaseURL) share_domain=\(identity.shareDomain)")
    }

    static func dateText(_ date: Date?) -> String {
        guard let date else { return "unknown" }
        return ISO8601DateFormatter().string(from: date)
    }
}

private struct StyleMatchBuildInformationView: View {
    @Environment(\.dismiss) private var dismiss
    private let identity = StyleMatchBuildIdentity.current

    var body: some View {
        NavigationStack {
            List {
                buildRow("Bundle ID", identity.bundleIdentifier)
                buildRow("Version", identity.version)
                buildRow("Build", identity.build)
                buildRow("Git commit", identity.gitCommit)
                buildRow("Build date", StyleMatchBuildIdentity.dateText(identity.buildDate))
                buildRow("Configuration", identity.buildConfiguration)
                buildRow("Target", identity.targetName)
                buildRow("Scheme", identity.schemeName)
                buildRow("API base URL", identity.apiBaseURL)
                buildRow("Share domain", identity.shareDomain)
            }
            .navigationTitle("Build Information")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func buildRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body.monospaced())
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }
}
#endif

private enum StartupDataRepair {
    static func run(defaults: UserDefaults = .standard) {
#if DEBUG
        PersonalStylistPhase2Diagnostics.runStorageIsolationSmokeTest()
#endif
        let shouldRestoreCapturedAccountData = AccountScopedStorage.prepareForLaunch(defaults: defaults)
        StyleMatchAppLaunchMigrations.run(defaults: defaults)
        if shouldRestoreCapturedAccountData {
            AccountScopedStorage.restoreCapturedLaunchData(defaults: defaults)
        }
        runOneTimeCrashRecovery(defaults: defaults)
        repairBoolDefault("hasCompletedOnboarding", fallback: true, defaults: defaults)
        repairBoolDefault("hasChosenAccessMode", fallback: false, defaults: defaults)
        repairDataValue("closetItemsData", defaults: defaults)
        repairDataValue("outfitScanHistoryData", defaults: defaults)
        repairDataValue("wishlistProductNamesData", defaults: defaults)
        repairDataValue("aiStylistConversationData", defaults: defaults)
        repairDataValue("aiStylistArchivedConversationsData", defaults: defaults)
        repairDataValue("aiInsightConversationData", defaults: defaults)
        DeprecatedAIAssistantPreferenceRepair.run(defaults: defaults)
        repairStringValue("customerAccountMode", allowed: CustomerAccountMode.allCases.map(\.rawValue), fallback: CustomerAccountMode.guest.rawValue, defaults: defaults)
        repairStringValue("selectedAppTheme", allowed: StyleMatchAppTheme.allCases.map(\.rawValue), fallback: StyleMatchAppTheme.system.rawValue, defaults: defaults)
        repairDoubleValue("selectedThemeIntensity", fallback: 0.42, closedRange: 0.18...0.82, defaults: defaults)
    }

    private static func runOneTimeCrashRecovery(defaults: UserDefaults) {
        let recoveryVersionKey = "startupCrashRecoveryVersion"
        let currentRecoveryVersion = 2
        guard defaults.integer(forKey: recoveryVersionKey) < currentRecoveryVersion else { return }

        defaults.set(StyleMatchAppTheme.system.rawValue, forKey: "selectedAppTheme")
        defaults.set(0.42, forKey: "selectedThemeIntensity")
        defaults.removeObject(forKey: "aiStylistConversationData")
        defaults.removeObject(forKey: "aiStylistArchivedConversationsData")
        defaults.removeObject(forKey: "aiInsightConversationData")
        defaults.set(currentRecoveryVersion, forKey: recoveryVersionKey)
    }

    private static func repairBoolDefault(_ key: String, fallback: Bool, defaults: UserDefaults) {
        guard defaults.object(forKey: key) != nil else {
            defaults.set(fallback, forKey: key)
            return
        }

        if defaults.object(forKey: key) is Bool {
            return
        }

        defaults.set(fallback, forKey: key)
    }

    private static func repairDataValue(_ key: String, defaults: UserDefaults) {
        guard defaults.object(forKey: key) != nil else { return }

        if let data = defaults.data(forKey: key), data.count <= 1_500_000 {
            return
        }

        defaults.removeObject(forKey: key)
    }

    private static func repairDoubleValue(_ key: String, fallback: Double, closedRange: ClosedRange<Double>, defaults: UserDefaults) {
        guard defaults.object(forKey: key) != nil else {
            defaults.set(fallback, forKey: key)
            return
        }

        guard let value = defaults.object(forKey: key) as? Double,
              value.isFinite else {
            defaults.set(fallback, forKey: key)
            return
        }

        defaults.set(min(max(value, closedRange.lowerBound), closedRange.upperBound), forKey: key)
    }

    private static func repairStringValue(_ key: String, allowed: [String], fallback: String, defaults: UserDefaults) {
        guard defaults.object(forKey: key) != nil else { return }

        if let value = defaults.string(forKey: key), allowed.contains(value) {
            return
        }

        defaults.set(fallback, forKey: key)
    }
}

@main
struct StyleMatchAIApp: App {
    #if canImport(UIKit)
    @UIApplicationDelegateAdaptor(StyleMatchAppDelegate.self) private var appDelegate
    #endif

    init() {
        StartupDataRepair.run()
        SaleWatcherBackgroundRefresh.register()
        SaleWatcherBackgroundRefresh.scheduleNextRefresh()
    }

    var body: some Scene {
        WindowGroup {
            AppLaunchFlowView()
        }
    }
}

#if canImport(UIKit) && canImport(UserNotifications)
final class StyleMatchAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppleCredentialRevoked),
            name: ASAuthorizationAppleIDProvider.credentialRevokedNotification,
            object: nil
        )
        verifyAppleCredentialState()
        StyleMatchAccountSessionDiagnostics.log(stage: "app_launch")
        #if DEBUG
        StyleMatchBuildIdentity.logLaunch()
        #endif
        return true
    }

    @objc private func handleAppleCredentialRevoked() {
        moveRevokedAppleSessionToGuest()
    }

    private func verifyAppleCredentialState() {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: "customerAccountMode") == CustomerAccountMode.apple.rawValue,
              let userID = defaults.string(forKey: "customerAppleUserID"),
              !userID.isEmpty else {
            return
        }

        ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userID) { state, _ in
            #if DEBUG
            let userHash = String(StylistChatAuthHeaders.sha256Hex(userID).prefix(8))
            print("[StyleMatch Account] stage=apple_credential_checked apple_user_hash=\(userHash) credential_state=\(state.rawValue)")
            #endif
            guard state == .revoked || state == .notFound else { return }
            DispatchQueue.main.async {
                self.moveRevokedAppleSessionToGuest()
            }
        }
    }

    private func moveRevokedAppleSessionToGuest() {
        let defaults = UserDefaults.standard
        AccountScopedStorage.switchUser(
            from: AccountScopedStorage.activePresentationUserID(defaults: defaults),
            to: "guest",
            transferSourceData: false,
            defaults: defaults
        )
        StyleMatchAccountSessionStore.delete()
        defaults.set(CustomerAccountMode.guest.rawValue, forKey: "customerAccountMode")
        defaults.removeObject(forKey: "customerAccountEmail")
        defaults.removeObject(forKey: "customerAppleUserID")
        defaults.set(false, forKey: "customerAccountSyncEnabled")
        defaults.set(true, forKey: "hasChosenAccessMode")
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        if let productID = response.notification.request.content.userInfo["stylematchProductID"] as? String {
            SaleWatcherRouteStore.route(to: productID)
        }
    }
}
#endif

private struct EmergencyRecoveryView: View {
    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Image(systemName: "sparkles")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(Color(hex: 0x11101E))
                    .frame(width: 92, height: 92)
                    .background(Color(hex: 0xEED9B5))
                    .clipShape(RoundedRectangle(cornerRadius: 24))

                Text("StyleMatch Pro")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: 0x11101E))

                Text("Recovery screen is working.")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Text("The app can open. Next we will turn screens back on one at a time.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 28)
            }
            .padding(28)
            .background(Color(hex: 0xF7F2E8))
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .padding(24)
        }
    }
}

private struct AppLaunchFlowView: View {
    @AppStorage("hasChosenAccessMode") private var hasChosenAccessMode = false
    @State private var isShowingSplash = true
    @State private var pendingSharedCardToken: String?
    #if DEBUG
    @State private var isShowingBuildInformation = false
    #endif

    var body: some View {
        ZStack {
            if hasChosenAccessMode {
                ContentView()
                    .opacity(isShowingSplash ? 0 : 1)
            } else {
                LoginWelcomeView()
                    .opacity(isShowingSplash ? 0 : 1)
            }

            if isShowingSplash {
                SplashScreenView()
                    .transition(.opacity)
            }
        }
        .onAppear {
            #if DEBUG
            let destination = hasChosenAccessMode ? "ContentView" : "LoginWelcomeView"
            print("[StyleMatch UI Route] root=AppLaunchFlowView splash=SplashScreenView destination=\(destination) has_chosen_access_mode=\(hasChosenAccessMode)")
            #endif
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
                withAnimation(.easeInOut(duration: 0.32)) {
                    isShowingSplash = false
                }
            }
        }
        .onOpenURL { url in
            routeSharedCard(url)
        }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            guard let url = activity.webpageURL else { return }
            routeSharedCard(url)
        }
        .sheet(item: sharedCardSheetBinding) { route in
            SharedScoreCardRecipientView(token: route.token)
        }
        #if DEBUG
        .simultaneousGesture(
            TapGesture(count: 5)
                .onEnded { isShowingBuildInformation = true }
        )
        .sheet(isPresented: $isShowingBuildInformation) {
            StyleMatchBuildInformationView()
        }
        #endif
    }

    private var sharedCardSheetBinding: Binding<ShareableScoreCardRoute?> {
        Binding(
            get: {
                pendingSharedCardToken.map(ShareableScoreCardRoute.init(token:))
            },
            set: { route in
                pendingSharedCardToken = route?.token
            }
        )
    }

    private func routeSharedCard(_ url: URL) {
        guard let route = ShareableScoreCardRoute.parse(url) else { return }
        pendingSharedCardToken = route.token
        hasChosenAccessMode = true
    }
}

private struct SplashScreenView: View {
    private let background = Color(hex: 0x080812)
    private let gold = Color(hex: 0xEED9B5)

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [background, Color(hex: 0x11101E), Color(hex: 0x2B2459).opacity(0.72)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                ZStack {
                    RoundedRectangle(cornerRadius: 28)
                        .fill(gold)
                        .frame(width: 92, height: 92)
                        .shadow(color: gold.opacity(0.36), radius: 24, x: 0, y: 12)

                    Image(systemName: "sparkles")
                        .font(.system(size: 46, weight: .bold))
                        .foregroundStyle(background)
                }

                Text("StyleMatch Pro")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("Your Personal AI Fashion Stylist")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(gold)
            }
            .padding(.horizontal, 28)
        }
        .preferredColorScheme(.dark)
    }
}
