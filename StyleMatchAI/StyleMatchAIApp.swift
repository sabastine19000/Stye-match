import SwiftUI
#if canImport(BackgroundTasks) && os(iOS)
import BackgroundTasks
#endif
#if canImport(UserNotifications)
import UserNotifications
#endif
#if canImport(UIKit)
import UIKit
#endif

private enum StartupDataRepair {
    static func run(defaults: UserDefaults = .standard) {
#if DEBUG
        PersonalStylistPhase2Diagnostics.runStorageIsolationSmokeTest()
#endif
        StyleMatchAppLaunchMigrations.run(defaults: defaults)
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
        #if canImport(BackgroundTasks) && os(iOS)
        SaleWatcherBackgroundRefresh.register()
        SaleWatcherBackgroundRefresh.scheduleNextRefresh()
        #endif
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
        return true
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
                withAnimation(.easeInOut(duration: 0.32)) {
                    isShowingSplash = false
                }
            }
        }
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
