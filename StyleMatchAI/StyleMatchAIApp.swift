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
    static let buildConfiguration = "Debug"

    let bundleIdentifier: String
    let version: String
    let build: String
    let sourceCheckpoint: String
    let buildDate: Date?
    let buildConfiguration: String
    let backendLane: String

    static var current: StyleMatchBuildIdentity {
        let bundle = Bundle.main
        let executableDate = bundle.executableURL.flatMap {
            try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        }
        return StyleMatchBuildIdentity(
            bundleIdentifier: bundle.bundleIdentifier ?? "unknown",
            version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            sourceCheckpoint: sourceCheckpoint(in: bundle),
            buildDate: executableDate,
            buildConfiguration: buildConfiguration,
            backendLane: diagnosticValue(for: "STYLEMATCH_BACKEND_LANE", in: bundle)
        )
    }

    private static func sourceCheckpoint(in bundle: Bundle) -> String {
        let value = diagnosticValue(for: "STYLEMATCH_SOURCE_CHECKPOINT", in: bundle)
        let isExactGitCommit = value.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil
        return isExactGitCommit ? value : "unavailable"
    }

    private static func diagnosticValue(for key: String, in bundle: Bundle) -> String {
        guard let rawValue = bundle.object(forInfoDictionaryKey: key) as? String else {
            return "unavailable"
        }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty || value.hasPrefix("$(") ? "unavailable" : value
    }

    static func logLaunch(at timestamp: Date = Date()) {
        _ = timestamp
    }

    static func dateText(_ date: Date?) -> String {
        guard let date else { return "unknown" }
        return ISO8601DateFormatter().string(from: date)
    }
}

private struct StyleMatchBuildInformationView: View {
    @Environment(\.dismiss) private var dismiss
    private let identity = StyleMatchBuildIdentity.current
    // This is deliberately calculated only inside the Debug-only owner
    // diagnostics view. It contains aggregate counts/categories and never
    // renders an event title, identifier, calendar name, location, note, or
    // attendee.
    private let calendarDiagnostics = EventKitCalendarContextAccess().runtimeDiagnostics()
    private let dmAttachmentDiagnostics = StyleFriendsDMAttachmentDiagnostics.snapshot

    var body: some View {
        NavigationStack {
            List {
                Section("Owner beta diagnostic") {
                    Text("This information is available only in the Debug owner-beta build. It is not part of the customer Release interface.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                buildRow("Bundle ID", identity.bundleIdentifier)
                buildRow("Version", identity.version)
                buildRow("Build", identity.build)
                buildRow("Source checkpoint", identity.sourceCheckpoint)
                buildRow("Build date", StyleMatchBuildIdentity.dateText(identity.buildDate))
                buildRow("Configuration", identity.buildConfiguration)
                buildRow("Backend environment", identity.backendLane)

                Section("Calendar runtime diagnostic") {
                    Text("Counts only. Calendar titles and other private event details are never shown here.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    buildRow("EVENTKIT_AUTH_STATUS", calendarDiagnostics.authorizationStatus)
                    buildRow("CALENDAR_CONSENT_ENABLED", calendarDiagnostics.consentEnabled ? "YES" : "NO")
                    buildRow("EVENT_QUERY_STATE", calendarDiagnostics.eventQueryState)
                    buildRow("EVENT_CALENDARS_VISIBLE_COUNT", "\(calendarDiagnostics.eventCalendarsVisibleCount)")
                    buildRow("EVENTS_FETCHED_COUNT", "\(calendarDiagnostics.eventsFetchedCount)")
                    buildRow("EVENTS_IN_WINDOW_COUNT", "\(calendarDiagnostics.eventsInWindowCount)")
                    buildRow("EVENTS_MINIMIZED_COUNT", "\(calendarDiagnostics.eventsMinimizedCount)")
                    buildRow("EVENTS_CLASSIFIED_COUNT", "\(calendarDiagnostics.eventsClassifiedCount)")
                    buildRow("EVENTS_REJECTED_COUNT", "\(calendarDiagnostics.eventsRejectedCount)")
                    buildRow("REJECTION_REASON_COUNTS", rejectionSummary)
                    buildRow("UPCOMING_WINDOW_START", StyleMatchBuildIdentity.dateText(calendarDiagnostics.windowStart))
                    buildRow("UPCOMING_WINDOW_END", StyleMatchBuildIdentity.dateText(calendarDiagnostics.windowEnd))
                }

                Section("Style Friends attachment diagnostic") {
                    Text("Stages and bounded status values only. No photo bytes, account identifiers, tokens, URLs, or attachment references are shown.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    buildRow("PHOTO_PICKER_LOAD", dmAttachmentDiagnostics.pickerLoad)
                    buildRow("PHOTO_NORMALIZATION", dmAttachmentDiagnostics.normalization)
                    buildRow("UPLOAD_REQUEST", dmAttachmentDiagnostics.uploadRequest)
                    buildRow("UPLOAD_AUTH", dmAttachmentDiagnostics.uploadAuth)
                    buildRow("UPLOAD_HTTP_STATUS", dmAttachmentDiagnostics.uploadHTTPStatus)
                    buildRow("UPLOAD_RESPONSE_DECODE", dmAttachmentDiagnostics.uploadResponseDecode)
                    buildRow("R2_WRITE", dmAttachmentDiagnostics.r2Write)
                    buildRow("ATTACHMENT_FINALIZE", dmAttachmentDiagnostics.attachmentFinalize)
                    buildRow("DM_MESSAGE_LINK", dmAttachmentDiagnostics.messageLink)
                    buildRow("ATTACHMENT_RENDER", dmAttachmentDiagnostics.attachmentRender)
                }
            }
            .navigationTitle("Owner Build Diagnostics")
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

    private var rejectionSummary: String {
        let values = calendarDiagnostics.rejectionReasonCounts
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { "\($0.key.rawValue)=\($0.value)" }
        return values.isEmpty ? "none" : values.joined(separator: ", ")
    }
}
#endif

#if OWNER_BETA
/// Runs only on an explicitly requested developer launch. No private recovery
/// payload or owner identifier is compiled into the app or Release artifact.
private enum OwnerBetaScanHistoryRecovery {
    static func runIfRequested(defaults: UserDefaults) {
        let environment = ProcessInfo.processInfo.environment
        guard environment["STYLEMATCH_SCAN_HISTORY_RECOVERY"] == "explicit-local-recovery-v1",
              let digest = environment["STYLEMATCH_SCAN_HISTORY_SHA256"],
              let owner = environment["STYLEMATCH_SCAN_HISTORY_OWNER"],
              let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let source = documents.appendingPathComponent("StyleMatchScanHistoryRecovery.json")
        guard let size = try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= 32 * 1024 * 1024,
              let data = try? Data(contentsOf: source) else { return }
        let result = ScopedScanHistoryRecovery.restore(
            data: data, expectedSHA256: digest, ownerStorageIdentifier: owner, defaults: defaults
        )
        // A bounded local result supports verification without logging records.
        defaults.set(result.rawValue, forKey: "ownerRequestedScanRecoveryResult.v1")
        if result == .restored || result == .alreadyPresent {
            try? FileManager.default.removeItem(at: source)
        }
    }
}
#endif

private enum StartupDataRepair {
    static func run(
        composition: StyleMatchApplicationComposition = .current()
    ) {
        let defaults = composition.retainedData.defaults
        AccountAccessRestoration.restore(
            verifiedAppleSubject: StyleMatchAccountSessionStore.load()?.appleSubject,
            defaults: defaults
        )
#if DEBUG
        PersonalStylistPhase2Diagnostics.runStorageIsolationSmokeTest()
#endif
        let shouldRestoreCapturedAccountData = composition.retainedData.prepareForLaunch()
        StyleMatchAppLaunchMigrations.run(defaults: defaults)
        if shouldRestoreCapturedAccountData {
            AccountScopedStorage.restoreCapturedLaunchData(defaults: defaults)
        }
        runOneTimeCrashRecovery(defaults: defaults)
        repairBoolDefault("hasCompletedOnboarding", fallback: true, defaults: defaults)
        repairBoolDefault("hasChosenAccessMode", fallback: false, defaults: defaults)
        repairDataValue("closetItemsData", defaults: defaults)
        repairScanHistoryData(defaults: defaults)
        repairDataValue("wishlistProductNamesData", defaults: defaults)
        repairDataValue("aiStylistConversationData", defaults: defaults)
        repairDataValue("aiStylistArchivedConversationsData", defaults: defaults)
        repairDataValue("aiInsightConversationData", defaults: defaults)
#if OWNER_BETA
        OwnerBetaScanHistoryRecovery.runIfRequested(defaults: defaults)
#endif
        DeprecatedAIAssistantPreferenceRepair.run(defaults: defaults)
        repairStringValue("customerAccountMode", allowed: CustomerAccountMode.allCases.map(\.rawValue), fallback: CustomerAccountMode.guest.rawValue, defaults: defaults)
        repairStringValue("selectedAppTheme", allowed: StyleMatchAppTheme.allCases.map(\.rawValue), fallback: StyleMatchAppTheme.system.rawValue, defaults: defaults)
        repairStringValue("styleMatchAppearanceMode", allowed: StyleMatchAppearanceMode.allCases.map(\.rawValue), fallback: StyleMatchAppearanceMode.manual.rawValue, defaults: defaults)
        repairDoubleValue("selectedThemeIntensity", fallback: 0.42, closedRange: 0.18...0.82, defaults: defaults)
        migrateActiveSavedScanImages(defaults: defaults)
        StyleMatchLocalDataProtection.protectApplicationPreferencesIfPresent()
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

    /// Scan history is user data. A valid large payload must never be removed
    /// merely because thumbnails make it exceed a generic preference-size limit.
    private static func repairScanHistoryData(defaults: UserDefaults) {
        let key = "outfitScanHistoryData"
        guard let value = defaults.object(forKey: key) else { return }
        guard let data = value as? Data else {
            defaults.set("nonDataValuePreserved", forKey: "scanHistoryLaunchValidationStatus.v1")
            return
        }
        guard data.count > 1_500_000 else { return }
        guard let root = try? JSONSerialization.jsonObject(with: data), root is [String: Any] else {
            defaults.set("invalidOversizedPayloadPreserved", forKey: "scanHistoryLaunchValidationStatus.v1")
            return
        }
        defaults.set("validOversizedPayloadPreserved", forKey: "scanHistoryLaunchValidationStatus.v1")
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

    private static func migrateActiveSavedScanImages(defaults: UserDefaults) {
        guard let data = defaults.data(forKey: "outfitScanHistoryData"),
              let history = try? JSONDecoder().decode([String: StoredOutfitScan].self, from: data) else {
            return
        }
        let assetIDs = Set(history.values.compactMap(\.savedImageAssetID))
        SavedScanImageAssetStore(userID: AccountScopedStorage.activePresentationUserID(defaults: defaults))
            .migrateLegacyAssets(named: assetIDs)
    }
}

@main
struct StyleMatchAIApp: App {
    #if canImport(UIKit)
    @UIApplicationDelegateAdaptor(StyleMatchAppDelegate.self) private var appDelegate
    #endif

    init() {
        StartupDataRepair.run()
        StyleMatchSimulatorFriendsAuthTestHarness.applyIfConfigured()
    }

    var body: some Scene {
        WindowGroup {
            AppLaunchFlowView()
        }
    }
}

#if canImport(UIKit)
final class StyleMatchAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    private var defaultsProtectionObserver: NSObjectProtocol?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        defaultsProtectionObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { _ in
            StyleMatchLocalDataProtection.protectApplicationPreferencesIfPresent()
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppleCredentialRevoked),
            name: ASAuthorizationAppleIDProvider.credentialRevokedNotification,
            object: nil
        )
        verifyAppleCredentialState()
        Task { @MainActor in
            await StyleFriendsNotificationCoordinator.shared.prepareForLaunch()
        }
        StyleMatchAccountSessionDiagnostics.log(stage: "app_launch")
        #if DEBUG
        StyleMatchBuildIdentity.logLaunch()
        #endif
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in
            StyleFriendsNotificationCoordinator.shared.didReceiveDeviceToken(deviceToken)
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        _ = error // APNs errors are intentionally not logged with device metadata.
        Task { @MainActor in
            StyleFriendsNotificationCoordinator.shared.didFailToRegisterForRemoteNotifications()
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        await MainActor.run {
            if response.notification.request.identifier == DailyStyleReminder.identifier {
                UserDefaults.standard.set(true, forKey: "kigoOpenDailyBrief")
                NotificationCenter.default.post(name: DailyStyleReminder.openNotification, object: nil)
            } else {
                StyleFriendsNotificationCoordinator.shared.didReceiveNotification(userInfo: response.notification.request.content.userInfo)
            }
        }
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
                #if DEBUG
                ContentView(
                    onShowBuildInformation: {
                        isShowingBuildInformation = true
                    }
                )
                .opacity(isShowingSplash ? 0 : 1)
                #else
                ContentView()
                    .opacity(isShowingSplash ? 0 : 1)
                #endif
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
