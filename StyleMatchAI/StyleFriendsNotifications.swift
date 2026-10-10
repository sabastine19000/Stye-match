import Foundation
import SwiftUI


#if canImport(UserNotifications)
import UserNotifications
#endif

#if canImport(UIKit)
import UIKit
#endif

/// Bounded notification references are navigation hints only. Each destination
/// must use the authenticated Style Friends service to re-authorize content.
enum StyleFriendsNotificationEventType: String, Codable, CaseIterable {
    case friendRequestReceived = "friend_request_received"
    case friendRequestAccepted = "friend_request_accepted"
    case friendPostPublished = "friend_post_published"
    case outfitLiked = "outfit_liked"
    case outfitCommented = "outfit_commented"
    case purchaseDetailsRequested = "purchase_details_requested"
    case moderationAccountNotice = "moderation_account_notice"
    case directMessage = "direct_message"
    case directMessageReply = "direct_message_reply"
    case directMessageReaction = "direct_message_reaction"
}

enum StyleFriendsNewPostNotificationMode: String, Codable, CaseIterable {
    case off, all, selected, important

    var displayName: String {
        switch self {
        case .off: "Off"
        case .all: "All friend posts"
        case .selected: "Selected friends only"
        case .important: "Important posts only"
        }
    }
}

struct StyleFriendsNotificationPreferences: Codable, Equatable {
    var masterEnabled = false
    var friendRequestsEnabled = true
    var requestAcceptedEnabled = true
    var newPostsMode: StyleFriendsNewPostNotificationMode = .off
    var likesEnabled = false
    var commentsEnabled = false
    /// This required wire field is independent from APNs registration. The
    /// server validates the complete preference contract before persistence.
    var directMessagesEnabled = false
    var purchaseQuestionsEnabled = false

    enum CodingKeys: String, CodingKey {
        case masterEnabled = "master_enabled", friendRequestsEnabled = "friend_requests_enabled"
        case requestAcceptedEnabled = "request_accepted_enabled", newPostsMode = "new_posts_mode"
        case likesEnabled = "likes_enabled", commentsEnabled = "comments_enabled"
        case directMessagesEnabled = "dm_enabled"
        case purchaseQuestionsEnabled = "purchase_questions_enabled"
    }

    init() {}

    /// `dm_enabled` was added after older OwnerBeta servers had already
    /// shipped. Decode its absence conservatively while always encoding the
    /// complete current request contract.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        masterEnabled = try values.decodeIfPresent(Bool.self, forKey: .masterEnabled) ?? false
        friendRequestsEnabled = try values.decodeIfPresent(Bool.self, forKey: .friendRequestsEnabled) ?? true
        requestAcceptedEnabled = try values.decodeIfPresent(Bool.self, forKey: .requestAcceptedEnabled) ?? true
        newPostsMode = try values.decodeIfPresent(StyleFriendsNewPostNotificationMode.self, forKey: .newPostsMode) ?? .off
        likesEnabled = try values.decodeIfPresent(Bool.self, forKey: .likesEnabled) ?? false
        commentsEnabled = try values.decodeIfPresent(Bool.self, forKey: .commentsEnabled) ?? false
        directMessagesEnabled = try values.decodeIfPresent(Bool.self, forKey: .directMessagesEnabled) ?? false
        purchaseQuestionsEnabled = try values.decodeIfPresent(Bool.self, forKey: .purchaseQuestionsEnabled) ?? false
    }
}

/// Keeps the notification editor's local selection authoritative until the
/// owner explicitly saves it. A late GET response must never replace a choice
/// made in the pushed New Friend Posts screen.
struct StyleFriendsNotificationPreferencesDraft: Equatable {
    var preferences: StyleFriendsNotificationPreferences
    private var lastServerPreferences: StyleFriendsNotificationPreferences

    init(preferences: StyleFriendsNotificationPreferences = .init()) {
        self.preferences = preferences
        lastServerPreferences = preferences
    }

    var hasUnsavedChanges: Bool { preferences != lastServerPreferences }

    mutating func applyServerPreferences(_ value: StyleFriendsNotificationPreferences) {
        guard !hasUnsavedChanges else { return }
        preferences = value
        lastServerPreferences = value
    }

    mutating func selectNewPostsMode(_ value: StyleFriendsNewPostNotificationMode) {
        preferences.newPostsMode = value
    }

    mutating func applySaveResult(_ value: StyleFriendsNotificationPreferences, submitted: StyleFriendsNotificationPreferences) {
        lastServerPreferences = value
        if preferences == submitted { preferences = value }
    }
}

struct StyleFriendsNotificationRoute: Equatable, Identifiable {
    let type: StyleFriendsNotificationEventType
    let postReference: StyleFriendsOpaqueRouteReference?
    let friendReference: StyleFriendAccountReference?
    let commentReference: StyleFriendsOpaqueRouteReference?
    let conversationReference: StyleFriendsOpaqueRouteReference?
    let messageReference: StyleFriendsOpaqueRouteReference?

    var id: String {
        [
            type.rawValue,
            conversationReference?.value,
            messageReference?.value,
            postReference?.value,
            friendReference?.value
        ]
        .compactMap { $0 }
        .joined(separator: "|")
    }

    var isDirectMessageRoute: Bool {
        switch type {
        case .directMessage, .directMessageReply, .directMessageReaction:
            true
        default:
            false
        }
    }

    init?(userInfo: [AnyHashable: Any]) {
        let values = userInfo["style_friends"] as? [String: Any] ?? userInfo as? [String: Any]
        guard let rawType = values?["event_type"] as? String,
              let type = StyleFriendsNotificationEventType(rawValue: rawType) else { return nil }
        let post = (values?["post_ref"] as? String).flatMap(StyleFriendsOpaqueRouteReference.init)
        let friend = (values?["friend_social_ref"] as? String).flatMap(StyleFriendAccountReference.init)
        let comment = (values?["comment_ref"] as? String).flatMap(StyleFriendsOpaqueRouteReference.init)
        let conversation = (values?["conversation_ref"] as? String).flatMap(StyleFriendsOpaqueRouteReference.init)
        let message = (values?["message_ref"] as? String).flatMap(StyleFriendsOpaqueRouteReference.init)
        if [StyleFriendsNotificationEventType.directMessage, .directMessageReply, .directMessageReaction].contains(type), conversation == nil { return nil }
        self.type = type; postReference = post; friendReference = friend; commentReference = comment; conversationReference = conversation; messageReference = message
    }

}

@MainActor
final class StyleFriendsNotificationRouteStore: ObservableObject {
    static let shared = StyleFriendsNotificationRouteStore()
    @Published private(set) var route: StyleFriendsNotificationRoute?
    private init() {}
    func accept(_ route: StyleFriendsNotificationRoute) { self.route = route }
    func clear() { route = nil }
}

enum StyleFriendsNotificationPermissionState: Equatable {
    case notDetermined, denied, authorized, provisional, unavailable
    var description: String {
        switch self {
        case .notDetermined: "Not requested"
        case .denied: "Disabled in iPhone Settings"
        case .authorized: "Allowed"
        case .provisional: "Delivering quietly"
        case .unavailable: "Notifications unavailable"
        }
    }
}

enum StyleFriendsDeviceRegistrationState: Equatable {
    case idle, requesting, registered, failed, unavailable

    var description: String {
        switch self {
        case .idle: "Not registered"
        case .requesting: "Registering…"
        case .registered: "Registered"
        case .failed: "Registration failed"
        case .unavailable: "Push registration unavailable"
        }
    }
}

/// Customer-facing device labels must follow the current form factor rather
/// than a build lane or a hardcoded phone assumption. Registration semantics
/// remain device-agnostic and continue to use the existing APNs authority.
enum StyleFriendsNotificationDevicePresentation {
    enum FormFactor: Equatable {
        case phone, pad, other
    }

    static var currentFormFactor: FormFactor {
        #if canImport(UIKit)
        switch UIDevice.current.userInterfaceIdiom {
        case .phone: .phone
        case .pad: .pad
        default: .other
        }
        #else
        .other
        #endif
    }

    static func name(for formFactor: FormFactor) -> String {
        switch formFactor {
        case .phone: "iPhone"
        case .pad: "iPad"
        case .other: "device"
        }
    }

    static func icon(for formFactor: FormFactor) -> String {
        switch formFactor {
        case .phone: "iphone"
        case .pad: "ipad"
        case .other: "rectangle.portrait"
        }
    }

    static func notificationSettingsActionTitle(for formFactor: FormFactor) -> String {
        "Open \(name(for: formFactor)) Settings"
    }

    static func registrationActionTitle(for formFactor: FormFactor) -> String {
        "Register This \(name(for: formFactor))"
    }

    static func registrationStatusTitle(
        for state: StyleFriendsDeviceRegistrationState,
        formFactor: FormFactor
    ) -> String {
        let name = name(for: formFactor)
        return switch state {
        case .registered: "This \(name) is registered"
        case .requesting: "Registering this \(name)"
        case .idle: "This \(name) is not registered"
        case .failed: "Registration needs attention"
        case .unavailable: "Registration unavailable"
        }
    }

    static func notificationSettingsHint(for formFactor: FormFactor) -> String {
        "Opens \(name(for: formFactor)) permission and Style Friends notification settings."
    }
}

/// Pure presentation rules keep notification state truthful and directly
/// testable without changing the existing APNs or preference authorities.
enum StyleFriendsNotificationSettingsPresentation {
    static func permissionTitle(for permission: StyleFriendsNotificationPermissionState) -> String {
        switch permission {
        case .authorized: "Notifications Allowed"
        case .provisional: "Notifications Deliver Quietly"
        case .notDetermined: "Notifications Not Yet Allowed"
        case .denied: "Notifications Are Disabled"
        case .unavailable: "Notifications Unavailable"
        }
    }

    static func permissionActionTitle(
        for permission: StyleFriendsNotificationPermissionState,
        formFactor: StyleFriendsNotificationDevicePresentation.FormFactor = StyleFriendsNotificationDevicePresentation.currentFormFactor
    ) -> String? {
        switch permission {
        case .notDetermined: "Allow Notifications"
        case .denied: StyleFriendsNotificationDevicePresentation.notificationSettingsActionTitle(for: formFactor)
        case .authorized, .provisional, .unavailable: nil
        }
    }

    static func registrationActionTitle(
        permission: StyleFriendsNotificationPermissionState,
        registration: StyleFriendsDeviceRegistrationState,
        formFactor: StyleFriendsNotificationDevicePresentation.FormFactor = StyleFriendsNotificationDevicePresentation.currentFormFactor
    ) -> String? {
        guard permission == .authorized || permission == .provisional else { return nil }
        return switch registration {
        case .registered, .requesting, .unavailable: nil
        case .idle: StyleFriendsNotificationDevicePresentation.registrationActionTitle(for: formFactor)
        case .failed: "Try Registration Again"
        }
    }
}

/// Avatar admission is fail-closed unless a separately accepted beta runtime
/// explicitly authorizes it. This prevents a picker path that is guaranteed to
/// fail while the isolated Worker gates remain disabled.
enum StyleFriendsAvatarRuntimeAuthority {
    static var allowsAvatarUpload: Bool {
        Bundle.main.object(forInfoDictionaryKey: "STYLEMATCH_SOCIAL_IMAGES_RUNTIME_AUTHORITY") as? String == "stagingAuthorized"
    }
}

/// APNs is fail-closed by default. A physical-development acceptance build must
/// explicitly carry the development authority value; the APS entitlement alone
/// never enables registration. Release remains disabled pending its own gate.
enum StyleFriendsAPNsRuntimeAuthority {
    enum Mode: String, Equatable {
        case disabled
        case developmentAuthorized
        case productionAuthorized
    }

    static var configuredMode: Mode {
        let value = Bundle.main.object(forInfoDictionaryKey: "STYLEMATCH_APNS_RUNTIME_AUTHORITY") as? String
        return Mode(rawValue: value ?? "disabled") ?? .disabled
    }

    static var currentEnvironment: String {
        #if DEBUG || OWNER_BETA
        return "development"
        #else
        return "production"
        #endif
    }

    static var configuredWorkerURL: URL? {
        workerURL(
            rawValue: Bundle.main.object(forInfoDictionaryKey: "STYLEMATCH_APNS_WORKER_URL") as? String,
            mode: configuredMode
        )
    }

    static var configuredDevelopmentWorkerURL: URL? {
        developmentWorkerURL(
            rawValue: Bundle.main.object(forInfoDictionaryKey: "STYLEMATCH_APNS_WORKER_URL") as? String
        )
    }

    /// Development is pinned to the isolated staging host. Production is pinned
    /// to the canonical StyleMatch API host. Arbitrary notification endpoints
    /// and mixed host fallbacks are rejected.
    static func workerURL(rawValue: String?, mode: Mode) -> URL? {
        switch mode {
        case .developmentAuthorized:
            return developmentWorkerURL(rawValue: rawValue)
        case .productionAuthorized:
            return productionWorkerURL(rawValue: rawValue)
        case .disabled:
            return nil
        }
    }

    static func developmentWorkerURL(rawValue: String?) -> URL? {
        validatedWorkerURL(rawValue: rawValue) {
            AppBackendConfiguration.isAuthorizedFriendsStagingHost($0)
        }
    }

    static func productionWorkerURL(rawValue: String?) -> URL? {
        validatedWorkerURL(rawValue: rawValue) {
            $0?.lowercased() == AppBackendConfiguration.approvedProductionAPIHost
        }
    }

    private static func validatedWorkerURL(
        rawValue: String?,
        hostIsAuthorized: (String?) -> Bool
    ) -> URL? {
        guard let rawURL = rawValue,
              let components = URLComponents(string: rawURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme?.lowercased() == "https",
              components.user == nil,
              components.password == nil,
              components.port == nil,
              components.path.isEmpty || components.path == "/",
              components.query == nil,
              components.fragment == nil,
              hostIsAuthorized(components.host) else {
            return nil
        }
        return components.url
    }

    static var signedAPSEnvironment: String? {
        Bundle.main.object(forInfoDictionaryKey: "STYLEMATCH_APS_ENVIRONMENT") as? String
    }

    static func permitsRegistration(
        mode: Mode,
        runtimeEnvironment: String,
        signedAPSEnvironment: String?,
        workerConfigured: Bool,
        supportsRemoteNotifications: Bool
    ) -> Bool {
        guard workerConfigured, supportsRemoteNotifications else { return false }
        switch mode {
        case .developmentAuthorized:
            return runtimeEnvironment == "development" && signedAPSEnvironment == "development"
        case .productionAuthorized:
            return runtimeEnvironment == "production" && signedAPSEnvironment == "production"
        case .disabled:
            return false
        }
    }

    /// Production authorization is intentionally inert in Build 18039 until a
    /// separate public-release gate proves the provider and governance path.
    static var allowsRegistration: Bool {
        permitsRegistration(
            mode: configuredMode,
            runtimeEnvironment: currentEnvironment,
            signedAPSEnvironment: signedAPSEnvironment,
            workerConfigured: configuredWorkerURL != nil,
            supportsRemoteNotifications: true
        )
    }

    static let genericPrivateMessagePreview = "New message from a Style Friend"
}

/// Device-token registration is a separate authenticated Worker contract. It
/// has no provider credential and is usable only with an exact staging host.
protocol StyleFriendsAPNsDeviceRegistrationServing {
    var isConfigured: Bool { get }
    func register(deviceToken: Data, session: StyleMatchAccountSession) async throws
    func removeTokens(session: StyleMatchAccountSession) async throws
}

struct StyleFriendsUnavailableAPNsDeviceRegistrationService: StyleFriendsAPNsDeviceRegistrationServing {
    let isConfigured = false
    func register(deviceToken: Data, session: StyleMatchAccountSession) async throws { throw StyleFriendsServiceError.unavailable }
    func removeTokens(session: StyleMatchAccountSession) async throws { throw StyleFriendsServiceError.unavailable }
}

@MainActor
final class StyleFriendsNotificationCoordinator: NSObject, ObservableObject {
    static let shared = StyleFriendsNotificationCoordinator()
    @Published private(set) var deviceRegistrationState: StyleFriendsDeviceRegistrationState = .idle
    private var deviceRegistration: any StyleFriendsAPNsDeviceRegistrationServing = StyleFriendsUnavailableAPNsDeviceRegistrationService()
    private var registeredSession: StyleMatchAccountSession?
    private override init() { super.init() }

    private var registrationSession: StyleMatchAccountSession? {
        guard StyleFriendsAPNsRuntimeAuthority.allowsRegistration,
              deviceRegistration.isConfigured,
              let account = StyleMatchAccountSessionStore.load(), account.expiresAt > Date() else { return nil }
        return account
    }

    func prepareForLaunch() async {
        let service = StyleFriendsNotificationService()
        configure(deviceRegistration: service)
        let permission = await permissionState()
        guard permission == .authorized || permission == .provisional,
              registrationSession != nil else {
            return
        }
        #if canImport(UIKit)
        deviceRegistrationState = .requesting
        UIApplication.shared.registerForRemoteNotifications()
        #endif
    }

    func permissionState() async -> StyleFriendsNotificationPermissionState {
        #if canImport(UserNotifications)
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .authorized: .authorized
        case .provisional: .provisional
        case .ephemeral: .authorized
        @unknown default: .unavailable
        }
        #else
        .unavailable
        #endif
    }

    /// Explicit user action only. APNs registration is never performed from a
    /// background refresh or a hidden preference mutation.
    func requestPermissionAndRegister() async -> StyleFriendsNotificationPermissionState {
        #if canImport(UserNotifications) && canImport(UIKit)
        guard registrationSession != nil else {
            deviceRegistrationState = .unavailable
            return .unavailable
        }
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            guard granted else { return await permissionState() }
            deviceRegistrationState = .requesting
            UIApplication.shared.registerForRemoteNotifications()
            return await permissionState()
        } catch {
            deviceRegistrationState = .failed
            return .unavailable
        }
        #else
        deviceRegistrationState = .unavailable
        return .unavailable
        #endif
    }

    func didReceiveDeviceToken(_ token: Data) {
        guard let session = registrationSession else {
            deviceRegistrationState = .unavailable
            return
        }
        registeredSession = session
        // No token is persisted locally; the authenticated Worker owns it.
        Task {
            do {
                try await deviceRegistration.register(deviceToken: token, session: session)
                deviceRegistrationState = .registered
            } catch {
                deviceRegistrationState = .failed
            }
        }
    }

    func didFailToRegisterForRemoteNotifications() { deviceRegistrationState = .failed }

    func openSystemNotificationSettings() {
        #if canImport(UIKit)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        #endif
    }

    func didReceiveNotification(userInfo: [AnyHashable: Any]) {
        guard let route = StyleFriendsNotificationRoute(userInfo: userInfo) else { return }
        accept(route)
    }

    func accept(_ route: StyleFriendsNotificationRoute) {
        StyleFriendsNotificationRouteStore.shared.accept(route)
    }

    func clearForAccountChange() {
        StyleFriendsNotificationRouteStore.shared.clear()
        guard let session = registeredSession, deviceRegistration.isConfigured else { return }
        registeredSession = nil
        // Capture the original authenticated session at token receipt. After a
        // logout/account switch, the newly current session must never remove a
        // different account's registration. If the prior session is expired or
        // revoked, this best-effort request fails closed on the Worker.
        Task { try? await deviceRegistration.removeTokens(session: session) }
    }

    /// Narrow injection seam for source tests and a future explicitly
    /// authorized staging configuration. The default remains unavailable.
    func configure(deviceRegistration service: any StyleFriendsAPNsDeviceRegistrationServing) { deviceRegistration = service }
}

struct StyleFriendsNotificationService: StyleFriendsAPNsDeviceRegistrationServing {
    private let baseURL: URL?
    private let session: URLSession
    private let accountSession: () -> StyleMatchAccountSession?
    var isConfigured: Bool { baseURL != nil }

    init(baseURL: URL? = StyleFriendsAPNsRuntimeAuthority.configuredWorkerURL, session: URLSession = .shared, accountSession: @escaping () -> StyleMatchAccountSession? = StyleMatchAccountSessionStore.load) {
        self.baseURL = baseURL; self.session = session; self.accountSession = accountSession
    }

    func preferences() async throws -> StyleFriendsNotificationPreferences {
        struct Payload: Decodable { let preferences: StyleFriendsNotificationPreferences }
        let payload: Payload = try await send(path: "/v1/friends/notifications/preferences", method: "GET", body: Optional<String>.none)
        return payload.preferences
    }

    func save(preferences: StyleFriendsNotificationPreferences) async throws -> StyleFriendsNotificationPreferences {
        struct Payload: Decodable { let preferences: StyleFriendsNotificationPreferences }
        let payload: Payload = try await send(path: "/v1/friends/notifications/preferences", method: "PUT", body: preferences)
        return payload.preferences
    }

    func register(deviceToken: Data, session: StyleMatchAccountSession) async throws {
        struct Registration: Encodable { let token: String; let environment: String; let categories: [String: Bool] }
        let token = Self.normalizedDeviceToken(deviceToken)
        let categories = ["friend_requests": true, "request_accepted": true, "new_posts": true, "likes": true, "comments": true, "purchase_questions": true]
        let _: EmptyResponse = try await send(path: "/v1/friends/notifications/devices", method: "POST", body: Registration(token: token, environment: Self.apnsEnvironment, categories: categories), accountSessionOverride: session)
    }

    func removeTokens(session: StyleMatchAccountSession) async throws {
        let _: EmptyResponse = try await send(path: "/v1/friends/notifications/devices", method: "DELETE", body: Optional<String>.none, accountSessionOverride: session)
    }

    static func normalizedDeviceToken(_ token: Data) -> String {
        token.map { String(format: "%02x", $0) }.joined()
    }

    private static var apnsEnvironment: String {
        #if DEBUG || OWNER_BETA
        return "development"
        #else
        return "production"
        #endif
    }

    private struct EmptyResponse: Decodable {}
    private func send<T: Decodable, Body: Encodable>(path: String, method: String, body: Body?, accountSessionOverride: StyleMatchAccountSession? = nil) async throws -> T {
        let resolvedSession = accountSessionOverride ?? accountSession()
        guard let account = resolvedSession, account.expiresAt > Date() else { throw StyleFriendsServiceError.signInRequired }
        guard let baseURL, let url = URL(string: path, relativeTo: baseURL) else { throw StyleFriendsServiceError.unavailable }
        var request = URLRequest(url: url); request.httpMethod = method
        request.setValue("Bearer \(account.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body { request.httpBody = try JSONEncoder().encode(body); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), let result = try? JSONDecoder().decode(T.self, from: data) else { throw StyleFriendsServiceError.unavailable }
            return result
        } catch let error as StyleFriendsServiceError { throw error }
        catch { throw StyleFriendsServiceError.networkUnavailable }
    }
}

struct StyleFriendsNotificationsSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var preferencesDraft = StyleFriendsNotificationPreferencesDraft()
    @State private var permission = StyleFriendsNotificationPermissionState.notDetermined
    @State private var feedback: String?
    @State private var isConfirmingDiscard = false
    @ObservedObject private var coordinator = StyleFriendsNotificationCoordinator.shared
    private let service = StyleFriendsNotificationService()

    private var preferences: Binding<StyleFriendsNotificationPreferences> {
        $preferencesDraft.preferences
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Choose what KigoStylist keeps you updated about.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    notificationStatusCard
                    deviceRegistrationCard

                    // Notification delivery permission and authenticated
                    // Style Friends preferences are independent authorities.
                    // A person may keep their server-side choices while
                    // declining APNs permission on this device.
                    preferencesEditor

                    notificationPrivacyCard

                    if let feedback {
                        Label(feedback, systemImage: "exclamationmark.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(14)
                            .appCard(.profile, radius: 16)
                            .accessibilityLabel(feedback)
                    }
                }
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .appScreenBackground(.profile)
            .navigationTitle("Notifications")
#if os(iOS)
            .navigationBarTitleDisplayMode(.large)
#endif
            .toolbar {
                #if os(macOS)
                ToolbarItem { saveButton }
                ToolbarItem { Button("Done") { dismissOrConfirm() } }
                #else
                ToolbarItem(placement: .topBarLeading) { saveButton }
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismissOrConfirm() } }
                #endif
            }
            .alert("Save notification changes?", isPresented: $isConfirmingDiscard) {
                Button("Keep Editing", role: .cancel) {}
                Button("Discard Changes", role: .destructive) { dismiss() }
            } message: {
                Text("Your notification preferences have not been saved.")
            }
            .task { await load() }
        }
    }

    private var saveButton: some View {
        Button("Save") { save() }
            .fontWeight(.semibold)
            .disabled(!preferencesDraft.hasUnsavedChanges)
            .accessibilityHint("Saves your Style Friends notification preferences.")
    }

    private var notificationStatusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Device notifications", systemImage: "bell.badge")
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: permissionStatusSymbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(permissionStatusColor)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text(permissionStatusTitle)
                        .font(.headline)
                    Text(permission.description)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
            }
            if let actionTitle = permissionActionTitle {
                Button(actionTitle) { performPermissionAction() }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .accessibilityHint(permission == .denied ? "Opens this app's notification settings." : "Requests permission for Style Friends notifications.")
            }
        }
        .padding(16)
        .appCard(.profile, radius: 18)
        .accessibilityElement(children: .combine)
    }

    private var deviceRegistrationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel(deviceName, systemImage: deviceIcon)
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: registrationStatusSymbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(registrationStatusColor)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text(registrationStatusTitle)
                        .font(.headline)
                    Text(registrationStatusDetail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
            }
            if let actionTitle = registrationActionTitle {
                Button(actionTitle) { requestRegistration() }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .disabled(coordinator.deviceRegistrationState == .requesting)
                    .accessibilityHint("Registers this device for the notification types you choose below.")
            }
        }
        .padding(16)
        .appCard(.profile, radius: 18)
        .accessibilityElement(children: .combine)
    }

    private var preferencesEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("Style Friends", systemImage: "person.2.fill")
            Text("Select the social activity that deserves an alert.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            notificationToggle("Style Friends Notifications", description: "Master control for Style Friends alerts.", isOn: preferences.masterEnabled)

            notificationGroup("Friends", systemImage: "person.2") {
                notificationToggle("Friend Requests", description: "When someone wants to connect.", isOn: preferences.friendRequestsEnabled)
                notificationToggle("Request Accepted", description: "When a connection request is accepted.", isOn: preferences.requestAcceptedEnabled)
                NavigationLink {
                    StyleFriendsNewPostModePicker(selection: preferencesDraft.preferences.newPostsMode) { mode in
                        preferencesDraft.selectNewPostsMode(mode)
                    }
                } label: {
                    preferenceNavigationRow("New Friend Posts", detail: preferencesDraft.preferences.newPostsMode.displayName)
                }
                .disabled(!preferencesDraft.preferences.masterEnabled)
            }

            notificationGroup("Activity", systemImage: "sparkles") {
                notificationToggle("Likes", description: "Reactions to your shared looks.", isOn: preferences.likesEnabled)
                notificationToggle("Comments", description: "Comments on your shared looks.", isOn: preferences.commentsEnabled)
                notificationToggle("Where did you get this?", description: "Questions about an item you shared.", isOn: preferences.purchaseQuestionsEnabled)
            }

            notificationGroup("Messages", systemImage: "message") {
                notificationToggle("Direct Messages", description: "Replies and reactions in your Style Friends conversations.", isOn: preferences.directMessagesEnabled)
            }
        }
        .padding(16)
        .appCard(.profile, radius: 18)
    }

    private var notificationPrivacyCard: some View {
        DisclosureGroup {
            Text("Notification previews use generic language. Opening one never grants access; KigoStylist rechecks the current Friend, block, and shared-post authorization.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        } label: {
            Label("Notification Privacy", systemImage: "hand.raised.fill")
                .font(.subheadline.weight(.semibold))
        }
        .padding(16)
        .appCard(.profile, radius: 18)
    }

    private func sectionLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.accentColor)
    }

    private func notificationGroup<Content: View>(_ title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 6)
            content()
        }
        .disabled(!preferencesDraft.preferences.masterEnabled)
    }

    private func notificationToggle(_ title: String, description: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 7)
        .disabled(!preferencesDraft.preferences.masterEnabled && title != "Style Friends Notifications")
    }

    private func preferenceNavigationRow(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 7)
    }

    private var permissionStatusTitle: String {
        StyleFriendsNotificationSettingsPresentation.permissionTitle(for: permission)
    }

    private var permissionStatusSymbol: String {
        switch permission {
        case .authorized, .provisional: "checkmark.circle.fill"
        case .notDetermined: "bell.badge"
        case .denied, .unavailable: "exclamationmark.triangle.fill"
        }
    }

    private var permissionStatusColor: Color {
        switch permission {
        case .authorized, .provisional: .green
        case .notDetermined: Color.accentColor
        case .denied, .unavailable: .orange
        }
    }

    private var permissionActionTitle: String? {
        StyleFriendsNotificationSettingsPresentation.permissionActionTitle(for: permission, formFactor: deviceFormFactor)
    }

    private var registrationStatusTitle: String {
        StyleFriendsNotificationDevicePresentation.registrationStatusTitle(
            for: coordinator.deviceRegistrationState,
            formFactor: deviceFormFactor
        )
    }

    private var deviceFormFactor: StyleFriendsNotificationDevicePresentation.FormFactor {
        StyleFriendsNotificationDevicePresentation.currentFormFactor
    }

    private var deviceName: String {
        StyleFriendsNotificationDevicePresentation.name(for: deviceFormFactor)
    }

    private var deviceIcon: String {
        StyleFriendsNotificationDevicePresentation.icon(for: deviceFormFactor)
    }

    private var registrationStatusDetail: String {
        switch coordinator.deviceRegistrationState {
        case .registered: "Style Friends can use this device for the alerts you choose."
        case .requesting: "KigoStylist is securely registering this device."
        case .idle: "Register this device after allowing notifications."
        case .failed: "Try registration again when you are ready."
        case .unavailable: "Device registration is unavailable in this app configuration."
        }
    }

    private var registrationStatusSymbol: String {
        switch coordinator.deviceRegistrationState {
        case .registered: "checkmark.circle.fill"
        case .requesting: "arrow.triangle.2.circlepath.circle"
        case .idle: "iphone"
        case .failed, .unavailable: "exclamationmark.triangle.fill"
        }
    }

    private var registrationStatusColor: Color {
        switch coordinator.deviceRegistrationState {
        case .registered: .green
        case .requesting: Color.accentColor
        case .idle: .secondary
        case .failed, .unavailable: .orange
        }
    }

    private var registrationActionTitle: String? {
        StyleFriendsNotificationSettingsPresentation.registrationActionTitle(
            permission: permission,
            registration: coordinator.deviceRegistrationState
        )
    }

    private func performPermissionAction() {
        if permission == .denied {
            StyleFriendsNotificationCoordinator.shared.openSystemNotificationSettings()
        } else {
            requestRegistration()
        }
    }

    private func requestRegistration() {
        Task { permission = await StyleFriendsNotificationCoordinator.shared.requestPermissionAndRegister() }
    }

    private func dismissOrConfirm() {
        if preferencesDraft.hasUnsavedChanges {
            isConfirmingDiscard = true
        } else {
            dismiss()
        }
    }

    private func load() async {
        StyleFriendsNotificationCoordinator.shared.configure(deviceRegistration: service)
        permission = await StyleFriendsNotificationCoordinator.shared.permissionState()
        if let serverPreferences = try? await service.preferences() {
            preferencesDraft.applyServerPreferences(serverPreferences)
        }
    }
    private func save() {
        let submitted = preferencesDraft.preferences
        Task {
            do {
                let saved = try await service.save(preferences: submitted)
                preferencesDraft.applySaveResult(saved, submitted: submitted)
            } catch {
                feedback = "Notification preferences could not be saved. Your changes are still here."
            }
        }
    }
}

/// A pushed choice list keeps the notification screen legible on compact
/// iPhones. The old menu popover obscured its own controls and made the
/// current selection difficult to review before saving.
private struct StyleFriendsNewPostModePicker: View {
    @Environment(\.dismiss) private var dismiss
    let selection: StyleFriendsNewPostNotificationMode
    let onSelect: (StyleFriendsNewPostNotificationMode) -> Void

    var body: some View {
        List {
            ForEach(StyleFriendsNewPostNotificationMode.allCases, id: \.self) { mode in
                Button {
                    onSelect(mode)
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(mode.displayName)
                            Text(mode.supportingText)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 12)
                        if mode == selection {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .foregroundStyle(.primary)
                .frame(minHeight: 44)
                .accessibilityValue(mode == selection ? "Selected" : "Not selected")
            }
        }
        .scrollContentBackground(.hidden)
        .appScreenBackground(.profile)
        .navigationTitle("New Friend Posts")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }
}

private extension StyleFriendsNewPostNotificationMode {
    var supportingText: String {
        switch self {
        case .off: "Do not send alerts for new looks."
        case .all: "Notify me when any of my Style Friends shares a new look."
        case .selected: "Only notify me about new looks from people I choose."
        case .important: "Limit alerts to higher-priority Style Friends activity."
        }
    }
}
