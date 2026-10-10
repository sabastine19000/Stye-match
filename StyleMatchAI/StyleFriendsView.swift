import AuthenticationServices
import ImageIO
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Colors for the social screens only; existing services and app theme state are unchanged.
enum KigoStyleFriendsPalette {
    static let page = adaptive(0xFAF8F5, 0x15141A)
    static let surface = adaptive(0xFFFFFF, 0x222029)
    static let text = adaptive(0x231F2A, 0xF5F0FA)
    static let secondary = adaptive(0x68616F, 0xC1B8CC)
    static let accent = adaptive(0x7348C6, 0xB795F2)
    static let button = adaptive(0x7040C4, 0x8052CB)
    static let soft = adaptive(0xF0E9FA, 0x322840)
    static let border = adaptive(0xE7E0EC, 0x44374F)

    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let rgb = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((rgb >> 16) & 255) / 255,
                           green: CGFloat((rgb >> 8) & 255) / 255,
                           blue: CGFloat(rgb & 255) / 255, alpha: 1)
        })
    }
}

/// Presentation-only boundary for Build 18038. A Friends post can refer only
/// to an already-approved shared-card representation; it never receives a
/// private scan, Closet item, Profile value, AI Memory, or CloudKit record.
enum StyleFriendsSharePresentationBoundary {
    static let friendsPublishingUnavailableMessage = "Friends-only publishing is not available in this client yet. Your external Share Link remains unchanged."
    static let revokedCardMessage = StyleFriendsPresentationContract.shareRevocationCopy
}

/// A short-lived Home search handoff. It contains only a destination enum and
/// is consumed by Profile before Style Friends is presented.
enum StyleFriendsHomeSearchRoute: String {
    case styleFriends, friends, findFriends, friendRequests, conversations, sharedLooks, feed

    static let storageKey = "styleFriendsHomeSearchRoute.v1"
}

/// Presentation only: actions are supplied by the existing Style Friends owner.
struct StyleFriendsEditorialHero: View {
    let onShareLook: () -> Void
    let onMessages: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var actionsLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 10))
            : AnyLayout(HStackLayout(spacing: 10))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            StyleFriendsEditorialHeading()
            actionsLayout {
                Button(action: onShareLook) {
                    Label("Share a Look", systemImage: "square.and.arrow.up")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .foregroundStyle(.white)
                        .background(KigoStyleFriendsPalette.button, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .accessibilityHint("Opens your existing approved Share Cards or the Scan screen to create one.")
                Button(action: onMessages) {
                    Label("Messages", systemImage: "bubble.left.and.bubble.right")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .foregroundStyle(KigoStyleFriendsPalette.accent)
                        .background(KigoStyleFriendsPalette.soft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(KigoStyleFriendsPalette.border))
                }
                .accessibilityHint("Opens your existing Style Friends conversations.")
            }
            .buttonStyle(.plain)
            Label("Only what you choose to share.", systemImage: "lock")
                .font(.caption)
                .foregroundStyle(KigoStyleFriendsPalette.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [KigoStyleFriendsPalette.surface, KigoStyleFriendsPalette.soft], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(KigoStyleFriendsPalette.border))
        .accessibilityElement(children: .contain)
    }
}

private struct StyleFriendsEditorialHeading: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("KIGOSTYLIST")
                    .font(.caption.weight(.bold))
                    .tracking(2.2)
                Spacer()
                Image(systemName: "person.2.fill")
                    .font(.title3)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(KigoStyleFriendsPalette.accent)
            Text("Good style is better\ntogether.")
                .font(.system(.largeTitle, design: .serif, weight: .semibold))
                .foregroundStyle(KigoStyleFriendsPalette.text)
                .fixedSize(horizontal: false, vertical: true)
            Text("Share your looks. Find inspiration.\nTalk style with your circle.")
                .font(.subheadline)
                .foregroundStyle(KigoStyleFriendsPalette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct StyleFriendsView: View {
    fileprivate enum Section: String, CaseIterable, Identifiable {
        case feed = "Friends Feed"
        case friends = "Friends"
        case requests = "Friend Requests"
        case sharedLooks = "My Shared Looks"
        case profile = "Profile"

        var id: String { rawValue }
        var compactTitle: String {
            switch self {
            case .feed: "Feed"
            case .friends: "Friends"
            case .requests: "Requests"
            case .sharedLooks: "My Looks"
            case .profile: "Profile"
            }
        }
        var icon: String {
            switch self {
            case .feed: "rectangle.stack.fill"
            case .friends: "person.2.fill"
            case .requests: "person.badge.plus"
            case .sharedLooks: "square.and.arrow.up.fill"
            case .profile: "person.crop.circle"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var section: Section
    @State private var socialProfileDraft = SocialProfileDraft()
    @State private var savedSocialProfileDraft = SocialProfileDraft()
    /// A missing server row is an explicit setup state. It is never filled
    /// from private StyleMatch profile, Closet, scan, Calendar, or account data.
    @State private var socialProfileEstablished = false
    /// Absence is authoritative only after the profile endpoint successfully
    /// returns an empty projection. Loading and transient failures must never
    /// be presented as profile creation states.
    @State private var socialProfileLoadState: StyleFriendsProfileLoadState = .loading
    @State private var profileSaveState = StyleFriendsProfileSaveState.unchanged
    @FocusState private var focusedSocialProfileField: SocialProfileField?
    @State private var profileFeedback: String?
    @State private var avatarState: StyleFriendAvatarState = .noPhoto
    @State private var avatarPickerItem: PhotosPickerItem?
    /// Retains only the user-selected picker token in memory while a failed
    /// upload remains retryable; it is never persisted or sent anywhere else.
    @State private var retryAvatarPickerItem: PhotosPickerItem?
    @State private var provisionalAvatar: UIImage?
    @State private var activeAvatarData: Data?
    @State private var activeAvatarReference: String?
    /// Advances before any user-initiated replacement. Every profile/image
    /// response must match it before it is allowed to repaint the avatar.
    @State private var avatarPresentationGeneration = 0
    @State private var avatarFeedback: String?
#if DEBUG
    @State private var avatarDebugStages: [String] = []
#endif
    @State private var actionFeedback: String?
#if DEBUG
    @State private var dmReadinessDebug: String?
#endif
    @State private var relationshipActions: [StyleFriendAccountReference: StyleFriendRelationshipActionState] = [:]
    @State private var requiresAccountReconnect: Bool
    @State private var listRefreshErrors: [Section: String] = [:]
    @State private var feedState: StyleFriendsFeedState
    @State private var friends: [StyleFriendListItem] = []
    @State private var incoming: [StyleFriendListItem] = []
    @State private var outgoing: [StyleFriendListItem] = []
    @State private var sharedLooks: [SharedOutfitPost] = []
    @State private var approvedCards: [CreatedShareableScoreCard] = []
    @State private var selectedFriend: StyleFriendListItem?
    @State private var reviewCard: CreatedShareableScoreCard?
    @State private var selectedPost: SharedOutfitPost?
    @State private var isShowingDiscovery = false
    @State private var discoveryQuery = ""
    @State private var discoveryResults: [StyleFriendDiscoveryItem] = []
    @State private var discoveryFeedback: String?
    @State private var isShowingConversations = false
    @State private var isShowingNotificationSettings = false
    @State private var isShowingSectionNavigation = false
    @State private var isLoading = false
    @ObservedObject private var notificationRoutes = StyleFriendsNotificationRouteStore.shared
    private let service: StyleFriendsService
    private let ownerDeviceAcceptance: StyleFriendsOwnerDeviceAcceptance.State
    private let onCreateShareCard: () -> Void

    init(
        feedState: StyleFriendsFeedState? = nil,
        ownerDeviceAcceptance: StyleFriendsOwnerDeviceAcceptance.State = StyleFriendsOwnerDeviceAcceptance.state(),
        homeSearchRoute: StyleFriendsHomeSearchRoute? = nil,
        onCreateShareCard: @escaping () -> Void = {}
    ) {
        self.ownerDeviceAcceptance = ownerDeviceAcceptance
        self.onCreateShareCard = onCreateShareCard
        switch ownerDeviceAcceptance {
        case let .active(configuration):
            service = StyleFriendsService(
                baseURL: configuration.baseURL,
                accountSession: { configuration.session },
                invalidateAccountSession: {}
            )
        case .unavailable:
            // The acceptance build must never fall back to the owner's normal
            // session or production endpoint when an injected fixture is absent.
            service = StyleFriendsService(
                baseURL: URL(string: "https://invalid.invalid")!,
                accountSession: { nil },
                invalidateAccountSession: {}
            )
        case .inactive:
            service = StyleFriendsService()
        }
        let hasSession = service.hasValidSession
        _requiresAccountReconnect = State(initialValue: !hasSession)
        _feedState = State(initialValue: feedState ?? (hasSession ? .unavailable : .signInRequired))
        switch homeSearchRoute {
        case .friends, .findFriends: _section = State(initialValue: .friends)
        case .friendRequests: _section = State(initialValue: .requests)
        case .sharedLooks: _section = State(initialValue: .sharedLooks)
        case .styleFriends, .feed, .conversations, .none: _section = State(initialValue: .feed)
        }
        _isShowingDiscovery = State(initialValue: homeSearchRoute == .findFriends)
        _isShowingConversations = State(initialValue: homeSearchRoute == .conversations)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let indicator = ownerDeviceAcceptance.visibleIndicator {
                    Label(indicator, systemImage: "testtube.2")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.top, 8)
                }
                StyleFriendsSectionNavigationTrigger(
                    section: section,
                    onSelect: { section = $0 },
                    openNavigation: { isShowingSectionNavigation = true }
                )
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

                if let actionFeedback {
                    Text(actionFeedback)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                        .accessibilityLabel(actionFeedback)
                }
#if DEBUG
                if let dmReadinessDebug {
                    Text(dmReadinessDebug)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                        .accessibilityLabel("Direct message readiness diagnostic")
                }
#endif

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        premiumStyleFriendsHero
                        sectionContent
                    }
                    .frame(maxWidth: 720, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                }
                .scrollDismissesKeyboard(.interactively)
                .refreshable { await refreshFromServer() }
            }
            .background(KigoStyleFriendsPalette.page.ignoresSafeArea())
            .tint(KigoStyleFriendsPalette.accent)
            .appScreenBackground(.profile)
            .navigationTitle("Style Friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Conversations") { isShowingConversations = true }
                        .accessibilityHint("Opens Style Friends human conversations.")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await refreshFromServer() }
        .onReceive(NotificationCenter.default.publisher(for: StyleMatchAccountSessionStore.didChangeNotification)) { _ in
            StyleFriendsNotificationCoordinator.shared.clearForAccountChange()
            Task { await reloadForAccountChange() }
        }
        .onChange(of: notificationRoutes.route) { route in
            guard let route else { return }
            switch route.type {
            case .friendRequestReceived, .friendRequestAccepted: section = .requests
            case .friendPostPublished, .outfitLiked, .outfitCommented, .purchaseDetailsRequested: section = .feed
            case .moderationAccountNotice: section = .profile
            case .directMessage, .directMessageReply, .directMessageReaction:
                isShowingConversations = true
            }
            // A route is only a hint. Feed/profile/post loading remains behind
            // the authenticated server-side authorization checks.
            StyleFriendsNotificationRouteStore.shared.clear()
        }
        .sheet(item: $selectedFriend) { person in
            StyleFriendProfileSheet(
                person: person,
                service: service,
                openConversation: { await startConversation(with: person.socialReference) }
            ) { operation in
                try await service.relationship(target: person.socialReference, operation: operation)
                await refreshFromServer()
            }
        }
        .sheet(item: $reviewCard) { card in
            StyleFriendsPublishReview(card: card) { draft in
                try await publish(draft)
            }
        }
        .sheet(item: $selectedPost) { post in
            StyleFriendsPostDetailsSheet(post: post)
        }
        .sheet(isPresented: $isShowingNotificationSettings) {
            StyleFriendsNotificationsSettingsView()
        }
        .sheet(isPresented: $isShowingConversations) {
            NavigationStack {
                StyleFriendsLiveConversationsHost {
                    isShowingConversations = false
                    DispatchQueue.main.async {
                        isShowingDiscovery = true
                    }
                } onOpenProfile: {
                    openAccountProfile()
                }
            }
        }
        .sheet(isPresented: $isShowingDiscovery) { NavigationStack { discoveryContent } }
        .sheet(isPresented: $isShowingSectionNavigation) {
            StyleFriendsSectionNavigationSheet(selection: $section)
                .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.height(382), .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var premiumStyleFriendsHero: some View {
        StyleFriendsEditorialHero(
            onShareLook: beginShareLook,
            onMessages: {
                isShowingConversations = true
                StyleMatchPremiumFeedback.selection()
            }
        )
    }

    @ViewBuilder
    private var sectionContent: some View {
        if requiresAccountReconnect {
            StyleFriendsSignInCard(onReconnect: openAccountProfile)
        } else if let error = listRefreshErrors[section] {
            unavailableCard(title: "Unable to refresh " + section.rawValue, detail: error, icon: "arrow.clockwise")
            Button("Retry") { Task { await refreshFromServer() } }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading)
        } else {
            switch section {
            case .feed: feedContent
            case .friends: friendsContent
            case .requests: requestsContent
            case .sharedLooks: sharedLooksContent
            case .profile: socialProfileContent
            }
        }
    }

    @MainActor
    private func openAccountProfile() {
        isShowingConversations = false
        dismiss()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: StyleMatchAccountSessionStore.profileReconnectRequestedNotification, object: nil)
        }
    }

    @MainActor
    private func beginShareLook() {
        StyleMatchPremiumFeedback.selection()

        if case .inactive = ownerDeviceAcceptance {
            // Re-read the local approved-card authority at the moment of the
            // tap so a card created earlier in this session is immediately
            // available without waiting for a network refresh.
            approvedCards = ShareableScoreCardLocalStore().cards
        }

        let activeCards = approvedCards.filter { $0.revokedAt == nil }
        if activeCards.count == 1, let card = activeCards.first {
            actionFeedback = nil
            reviewCard = card
            return
        }

        if !activeCards.isEmpty {
            actionFeedback = "Choose an approved Share Card, then tap Share with Friends."
            section = .sharedLooks
            return
        }

        actionFeedback = "Create a Share Card from a saved scan first. Opening Scan now."
        onCreateShareCard()
    }

    private var feedContent: some View {
        Group {
            Label("Friends Feed", systemImage: "rectangle.stack.fill")
                .font(.title2.bold())
            Text("Outfit inspiration from your circle.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            switch feedState {
            case .loading:
                ProgressView("Loading Friends Feed…")
                    .frame(maxWidth: .infinity, minHeight: 180)
            case .refreshing(let page):
                feedCards(page, isRefreshing: true)
            case .loadingMore(let page):
                feedCards(page, isLoadingMore: true)
            case .empty:
                feedEmptyCard
            case .loaded(let page): feedCards(page)
            case .signInRequired:
                StyleFriendsSignInCard(onReconnect: openAccountProfile)
            case .networkUnavailable:
                feedRetryCard(title: "Friends Feed is unavailable", detail: "Check your connection and try again later. No private data is shown while the feed is unavailable.", icon: "wifi.exclamationmark")
            case .serverUnavailable:
                feedRetryCard(title: "Friends Feed is temporarily unavailable", detail: "Try again later. No private data is shown while the service is unavailable.", icon: "exclamationmark.icloud")
            case .unavailable:
                feedRetryCard(title: "Friends Feed is unavailable", detail: "This app configuration cannot load the authenticated Friends Feed. No private data is shown.", icon: "lock.slash")
            }
        }
    }

    @ViewBuilder private func feedCards(_ page: StyleFriendsFeedPage, isRefreshing: Bool = false, isLoadingMore: Bool = false) -> some View {
        if page.items.isEmpty {
            feedEmptyCard
        } else {
            ForEach(page.items) { item in
                StyleFriendsFeedCard(item: item, service: service) { ownerReference in
                    selectedFriend = StyleFriendListItem(
                        socialReference: ownerReference,
                        displayName: item.owner.displayName,
                        avatarReference: item.owner.avatarReference,
                        state: .friends,
                        createdAt: item.createdAt
                    )
                } didBlock: { reference in
                    await performRelationship(target: reference, operation: .block)
                }
            }
            HStack {
                Button(isRefreshing ? "Refreshing…" : "Refresh") { Task { await refreshFeed() } }
                    .disabled(isRefreshing || isLoadingMore)
                Spacer()
                if page.nextCursor != nil {
                    Button(isLoadingMore ? "Loading…" : "Load more") { Task { await loadMoreFeed(from: page) } }
                        .disabled(isRefreshing || isLoadingMore)
                }
            }
            .buttonStyle(.bordered)
        }
    }

    private var feedEmptyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            unavailableCard(title: "No posts yet", detail: "Friends-only posts appear here after you or a friend explicitly publishes an approved look.", icon: "rectangle.stack.badge.minus")
            HStack {
                Button {
                    beginShareLook()
                } label: {
                    Label("Post a Look", systemImage: "square.and.arrow.up.fill")
                }
                .buttonStyle(.borderedProminent)

                Button("Refresh") { Task { await refreshFeed() } }
                    .buttonStyle(.bordered)
            }
        }
    }

    private func feedRetryCard(title: String, detail: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            unavailableCard(title: title, detail: detail, icon: icon)
            Button("Retry") { Task { await refreshFeed() } }
                .buttonStyle(.bordered)
                .accessibilityHint("Reloads only the authenticated Friends Feed.")
        }
    }

    private var friendsContent: some View {
        Group {
            Label("Friends", systemImage: "person.2.fill")
                .font(.title2.bold())
            if isLoading { ProgressView("Loading Friends…") }
            else if friends.isEmpty {
                unavailableCard(title: "No friends yet", detail: "Find another Style Friend by the public social name they chose to share. Contacts, private KigoStylist data, and share links are never used.", icon: "person.2.slash")
                Button("Find Style Friends") { isShowingDiscovery = true }.buttonStyle(.borderedProminent)
            }
            else { ForEach(friends) { person in friendRow(person, actions: [.remove, .block]) } }
        }
    }

    private var requestsContent: some View {
        Group {
            Label("Friend Requests", systemImage: "person.badge.plus")
                .font(.title2.bold())
            if isLoading { ProgressView("Loading requests…") }
            else if incoming.isEmpty && outgoing.isEmpty {
                unavailableCard(title: "No requests to show", detail: "Incoming requests can be accepted or declined; outgoing requests can be cancelled.", icon: "person.crop.circle.badge.questionmark")
                Button("Find Style Friends") { isShowingDiscovery = true }.buttonStyle(.borderedProminent)
            }
            else {
                if !incoming.isEmpty { Text("Incoming").font(.headline); ForEach(incoming) { person in friendRow(person, actions: [.accept, .decline]) } }
                if !outgoing.isEmpty { Text("Outgoing").font(.headline); ForEach(outgoing) { person in friendRow(person, actions: [.cancel]) } }
            }
        }
    }

    private var sharedLooksContent: some View {
        Group {
            Label("My Shared Looks", systemImage: "square.and.arrow.up.fill")
                .font(.title2.bold())
            Text("A Friends-only post is separate from its approved shared card. Deleting a post removes its Friends engagement; revoking its underlying shared card makes every presentation unavailable.")
                .foregroundStyle(.secondary)

            if isLoading { ProgressView("Loading shared looks…") }
            ForEach(approvedCards.filter { $0.revokedAt == nil }) { card in
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Approved Share Card").font(.subheadline)
                        Text("External Share Link remains a separate capability.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Share with Friends") { reviewCard = card }.buttonStyle(.borderedProminent)
                    Button("Revoke Share", role: .destructive) { Task { await revoke(card) } }.buttonStyle(.bordered)
                }
            }
            if sharedLooks.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    unavailableCard(title: "No Friends posts yet", detail: "Publish an approved Share Card to Friends. A post remains separate from its secure external card.", icon: "link.badge.plus")
                    Button {
                        beginShareLook()
                    } label: {
                        Label(approvedCards.contains(where: { $0.revokedAt == nil }) ? "Post a Look" : "Create a Share Card", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            else { ForEach(sharedLooks) { post in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(post.title ?? "Shared Look")
                            .font(.headline)
                        if let score = post.score {
                            Label("KigoStylist score \(score)/100", systemImage: "checkmark.seal")
                                .font(.subheadline)
                        } else {
                            Text("KigoStylist score unavailable in this social projection.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let caption = post.caption, !caption.isEmpty { Text(caption).foregroundStyle(.secondary) }
                        if let occasion = post.occasion, !occasion.isEmpty { Label(occasion, systemImage: "calendar").font(.caption) }
                        Text(post.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(post.availability == .active ? "Available" : "Unavailable after share revocation")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            Button("Open") { selectedPost = post }
                            Button("Delete Post", role: .destructive) { Task { await deletePost(post.postReference) } }
                        }
                        .buttonStyle(.bordered)
                        Text("Revoke Share is available on the approved shared card above. It revokes the representation without deleting this device’s private scan or history.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }

    private var socialProfileContent: some View {
        Group {
            if socialProfileLoadState == .loading && !socialProfileEstablished {
                ProgressView("Loading your public Style Friends profile…")
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else if socialProfileLoadState == .unavailable && !socialProfileEstablished {
                VStack(alignment: .leading, spacing: 12) {
                    unavailableCard(
                        title: "Your public profile could not be refreshed",
                        detail: "KigoStylist did not confirm whether a public Style Friends profile exists. Your private Profile and saved data were not changed.",
                        icon: "wifi.exclamationmark"
                    )
                    Button("Retry profile refresh") { Task { await refreshFromServer() } }
                        .buttonStyle(.bordered)
                }
            } else {
                socialProfileEditor
            }
        }
    }

    private var socialProfileEditor: some View {
        VStack(alignment: .leading, spacing: 16) {
            if socialProfileLoadState == .missing { socialProfileEstablishmentCard }
            socialProfileHero
            avatarControls
            socialProfilePreview

            VStack(alignment: .leading, spacing: 10) {
                Text("Public details")
                    .font(.headline)
                TextField("Display name", text: $socialProfileDraft.displayName)
                    .textInputAutocapitalization(.words)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedSocialProfileField, equals: .displayName)
                    .accessibilityLabel("Style Friends display name")
                    .onChange(of: socialProfileDraft.displayName) { _ in updateSocialProfileSaveReadiness() }
                if socialProfileDraft.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Label("A display name is required before you can save.", systemImage: "exclamationmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                TextField("Public style bio (optional)", text: $socialProfileDraft.styleBio, axis: .vertical)
                    .lineLimit(4...10)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedSocialProfileField, equals: .bio)
                    .accessibilityLabel("Style Friends style bio")
                    .onChange(of: socialProfileDraft.styleBio) { _ in updateSocialProfileSaveReadiness() }
                Text("\(socialProfileDraft.styleBioWordCount)/\(StyleFriendProfileUpdate.maximumStyleBioWords) words · \(socialProfileDraft.styleBio.utf16.count)/\(StyleFriendProfileUpdate.maximumStyleBioUTF16) characters")
                    .font(.caption)
                    .foregroundStyle(socialProfileDraft.isWithinBounds ? Color.secondary : Color.red)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .accessibilityLabel("Style bio uses \(socialProfileDraft.styleBioWordCount) of \(StyleFriendProfileUpdate.maximumStyleBioWords) words and \(socialProfileDraft.styleBio.utf16.count) of \(StyleFriendProfileUpdate.maximumStyleBioUTF16) characters")
            }
            .padding(18)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20))

            VStack(alignment: .leading, spacing: 12) {
                Text("Style identity")
                    .font(.headline)
                Text("Choose any styles that feel like you.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 10)], spacing: 10) {
                    ForEach(StyleFriendStyleCategory.allCases, id: \.self) { category in
                        Button { toggleStyleCategory(category) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: socialProfileDraft.categories.contains(category) ? "checkmark.circle.fill" : "circle")
                                Text(category.displayName).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .padding(.horizontal, 12)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(socialProfileDraft.categories.contains(category) ? KigoStyleFriendsPalette.accent : .primary)
                        .background(socialProfileDraft.categories.contains(category) ? KigoStyleFriendsPalette.soft : Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(socialProfileDraft.categories.contains(category) ? KigoStyleFriendsPalette.accent.opacity(0.55) : .white.opacity(0.06), lineWidth: 1))
                        .accessibilityLabel(category.displayName)
                        .accessibilityValue(socialProfileDraft.categories.contains(category) ? "Selected" : "Not selected")
                        .accessibilityHint("Double tap to \(socialProfileDraft.categories.contains(category) ? "remove" : "add") this style identity.")
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Label("Your Style Friends profile is separate from your private KigoStylist profile.", systemImage: "lock.shield")
                    .font(.headline)
                Text("Only your display name, bio, and selected style identities are shared with Style Friends. Your Closet, scans, AI Memory, sizes, location, and account details stay private.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(18)
            .background(Color.accentColor.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 20))

            Toggle("Let other Style Friends find this public profile", isOn: $socialProfileDraft.isDiscoverable)
                .onChange(of: socialProfileDraft.isDiscoverable) { _ in updateSocialProfileSaveReadiness() }
                .accessibilityHint("Only this profile's display name, bio, and chosen style identities may appear in authenticated Style Friends search.")

            Button { isShowingNotificationSettings = true } label: {
                HStack(spacing: 10) {
                    Label("Style Friends notifications", systemImage: "bell.badge")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityHint(StyleFriendsNotificationDevicePresentation.notificationSettingsHint(for: StyleFriendsNotificationDevicePresentation.currentFormFactor))

            socialProfileSaveControl
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedSocialProfileField = nil }
            }
        }
    }

    private var socialProfileEstablishmentCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Create your Style Friends profile", systemImage: "person.badge.plus")
                .font(.headline)
            Text("Choose a public display name and any optional details you want to share. KigoStylist never copies your private Profile, Closet, scans, AI Memory, Calendar, location, or account information into this profile.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Add a display name") { focusedSocialProfileField = .displayName }
                .buttonStyle(.bordered)
                .accessibilityHint("Starts your intentional Style Friends profile setup.")
        }
        .padding(16)
        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var socialProfileHero: some View {
        HStack(spacing: 14) {
            profileAvatar(size: 76)
                .accessibilityLabel("Style Friends profile image")

            VStack(alignment: .leading, spacing: 5) {
                Text(socialProfileDraft.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Your public profile" : socialProfileDraft.displayName)
                    .font(.title3.weight(.bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Text("Visible only to authorized Style Friends")
                    .font(.subheadline)
                    .foregroundStyle(KigoStyleFriendsPalette.secondary)
                Text(avatarStatusCopy)
                    .font(.caption2)
                    .foregroundStyle(KigoStyleFriendsPalette.accent)
            }
            if StyleFriendsAvatarRuntimeAuthority.allowsAvatarUpload {
                if socialProfileEstablished {
                    PhotosPicker(selection: $avatarPickerItem, matching: .images, photoLibrary: .shared()) {
                        Image(systemName: socialProfileDraft.avatarReference.isEmpty ? "camera.fill" : "camera.rotate.fill")
                            .font(.headline)
                            .frame(width: 42, height: 42)
                            .background(KigoStyleFriendsPalette.soft, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(avatarState == .uploading || avatarState == .removing)
                    .accessibilityLabel(socialProfileDraft.avatarReference.isEmpty ? "Choose profile photo" : "Replace profile photo")
                    .accessibilityHint("Selects a photo for your established public Style Friends profile.")
                    .onChange(of: avatarPickerItem) { item in Task { await selectAvatar(item) } }
                } else {
                    Button {
                        focusedSocialProfileField = .displayName
                        profileFeedback = "Add a display name, then create your public Style Friends profile before choosing a photo."
                    } label: {
                        Image(systemName: "camera.fill")
                            .font(.headline)
                            .frame(width: 42, height: 42)
                            .background(KigoStyleFriendsPalette.soft, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Profile photo unavailable")
                    .accessibilityValue("Create a public Style Friends profile first")
                    .accessibilityHint("Double-tap to focus the Display name field.")
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(KigoStyleFriendsPalette.text)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [KigoStyleFriendsPalette.surface, KigoStyleFriendsPalette.soft],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(KigoStyleFriendsPalette.accent.opacity(0.24), lineWidth: 1))
    }

    private var socialProfilePreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Public preview", systemImage: "eye")
                .font(.headline)
                .foregroundStyle(KigoStyleFriendsPalette.accent)
            HStack(alignment: .top, spacing: 12) {
                profileAvatar(size: 48)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(socialProfileDraft.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Add your display name" : socialProfileDraft.displayName)
                        .font(.headline)
                        .lineLimit(2)
                    Text(socialProfileDraft.styleBio.isEmpty ? "Your public style bio will appear here." : socialProfileDraft.styleBio)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                    if socialProfileDraft.categories.isEmpty {
                        Text("Select style identities to complete your preview.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(socialProfileDraft.categories.sorted { $0.rawValue < $1.rawValue }.map(\.displayName).joined(separator: " · "))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(KigoStyleFriendsPalette.accent)
                            .lineLimit(2)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Style Friends profile preview")
    }

    private func profileAvatar(size: CGFloat) -> some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [KigoStyleFriendsPalette.accent, KigoStyleFriendsPalette.soft], startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().fill(KigoStyleFriendsPalette.surface).padding(3)
            if let preview = provisionalAvatar, avatarState == .selecting || avatarState == .cropping || avatarState == .uploading || avatarState == .replacing {
                Image(uiImage: preview).resizable().scaledToFill().clipShape(Circle()).padding(3)
            } else if activeAvatarReference == socialProfileDraft.avatarReference,
                      let data = activeAvatarData,
                      let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill().clipShape(Circle()).padding(3)
            } else {
                Text(socialProfileDraft.initials)
                    .font(.system(size: size * 0.33, weight: .bold, design: .rounded))
                    .foregroundStyle(KigoStyleFriendsPalette.accent)
            }
        }
        .frame(width: size, height: size)
    }

    private var avatarControls: some View {
        VStack(alignment: .leading, spacing: 8) {
#if DEBUG
            if !avatarDebugStages.isEmpty {
                Text(avatarDebugStages.joined(separator: " · "))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Avatar upload diagnostics")
            }
#endif
            if let avatarFeedback {
                Text(avatarFeedback)
                    .font(.footnote)
                    .foregroundStyle(avatarState == .failed || avatarState == .rejected ? Color.red : .secondary)
            }
            if avatarState == .failed, retryAvatarPickerItem != nil {
                Button("Retry photo upload") { Task { await retryAvatarUpload() } }
                    .buttonStyle(.bordered)
                    .accessibilityHint("Retries the selected profile photo upload once you are connected.")
            }
            if !socialProfileDraft.avatarReference.isEmpty {
                Button(role: .destructive) { Task { await removeAvatar() } } label: {
                    Label(avatarState == .removing ? "Removing photo…" : "Remove photo", systemImage: "trash")
                }
                .disabled(avatarState == .uploading || avatarState == .removing)
                .accessibilityHint("Removes the active public Style Friends avatar and revokes access immediately.")
            }
        }
    }

    private var avatarStatusCopy: String {
        if !socialProfileEstablished { return "Create your public Style Friends profile before adding a photo." }
        switch avatarState {
        case .noPhoto: return StyleFriendsAvatarRuntimeAuthority.allowsAvatarUpload ? "Choose a photo to submit for your public profile." : "Profile photos are unavailable right now. Your initials remain visible to authorized Style Friends."
        case .selecting: return "Preparing your private photo preview…"
        case .cropping: return "Center-square avatar preview is being prepared…"
        case .uploading, .replacing: return "Submitting your photo for safety review…"
        case .underReview: return "Your submitted photo is under review and is not public."
        case .active: return "Your public profile photo is active for authorized Style Friends."
        case .rejected: return "That photo was not approved. Choose a different photo."
        case .failed: return "Photo upload did not complete. Your active photo was not changed."
        case .removing: return "Removing your public profile photo…"
        }
    }

    @MainActor private func selectAvatar(_ item: PhotosPickerItem?) async {
        guard StyleFriendsAvatarRuntimeAuthority.allowsAvatarUpload else { return }
        guard socialProfileEstablished else { return }
        guard let item else { return }
        retryAvatarPickerItem = item
        let uploadGeneration = beginAvatarReplacement()
        recordAvatarDebug("PICKER", "SELECTED")
        avatarFeedback = nil; avatarState = .selecting
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                recordAvatarDebug("DATA_LOAD", "FAILED")
                avatarState = .failed; avatarFeedback = "Choose a supported photo to upload."; return
            }
            recordAvatarDebug("DATA_LOAD", "PASS")
            guard let preparedAvatar = prepareAvatarUpload(from: data) else {
                recordAvatarDebug("JPEG_ENCODE", "FAILED")
                avatarState = .failed; avatarFeedback = "That photo is too large or cannot be prepared safely. Choose a different photo."; return
            }
            recordAvatarDebug("IMAGE_DECODE", "PASS")
            let normalizedJPEG = preparedAvatar.jpegData
            recordAvatarDebug("JPEG_ENCODE", "PASS_\(normalizedJPEG.count)B")
            recordAvatarDebug("CONTENT_TYPE", "IMAGE_JPEG")
            recordAvatarDebug("CLIENT_LIMIT", "7340032B")
            recordAvatarDebug("ENVIRONMENT", StyleFriendsAvatarRuntimeAuthority.allowsAvatarUpload ? "STAGING_AUTHORIZED" : "NOT_AUTHORIZED")
            provisionalAvatar = preparedAvatar.preview
            avatarState = .cropping
            // The server is the canonical crop/normalization authority: it
            // center-crops the submitted image to a metadata-free 512-square WebP.
            avatarState = socialProfileDraft.avatarReference.isEmpty ? .uploading : .replacing
            recordAvatarDebug("SESSION", service.hasValidSession ? "PRESENT" : "MISSING")
            recordAvatarDebug("UPLOAD", "POST_PROFILE_AVATAR")
            let receipt = try await uploadAvatarOnceAfterTransientServiceFailure(normalizedJPEG)
            recordAvatarDebug("UPLOAD_HTTP", "\(receipt.httpStatus)")
            let result = receipt.result
            switch result.avatarState {
            case .active:
                guard let reference = result.avatarReference else { avatarState = .failed; avatarFeedback = "Photo upload did not return an approved public reference."; return }
                recordAvatarDebug("RESPONSE_DECODE", "PASS")
                guard let refreshedProfile = try await service.socialProfile() else {
                    recordAvatarDebug("PROFILE_REFRESH", "EMPTY")
                    avatarState = .failed; avatarFeedback = "Your profile photo could not be confirmed. Try again."; return
                }
                let refreshedDraft = SocialProfileDraft(profile: refreshedProfile)
                guard uploadGeneration == avatarPresentationGeneration else {
                    recordAvatarDebug("PROFILE_REFRESH", "STALE_IGNORED")
                    return
                }
                socialProfileDraft = refreshedDraft
                savedSocialProfileDraft = refreshedDraft
                guard refreshedDraft.avatarReference == reference else {
                    recordAvatarDebug("PROFILE_REFRESH", "REFERENCE_MISMATCH")
                    avatarState = .failed; avatarFeedback = "Your profile photo could not be confirmed. Try again."; return
                }
                recordAvatarDebug("PROFILE_REFRESH", "PASS")
                // Keep the selected image visible until the server image for
                // this exact reference is fetched. This avoids exposing the
                // previous in-memory avatar between the two authorities.
                activeAvatarData = nil
                activeAvatarReference = nil
                await refreshAvatar(reference: reference, generation: uploadGeneration)
                if avatarState == .active { retryAvatarPickerItem = nil }
            case .underReview:
                provisionalAvatar = nil; avatarState = .underReview; retryAvatarPickerItem = nil
            case .rejected:
                provisionalAvatar = nil; avatarState = .rejected; retryAvatarPickerItem = nil
            default:
                provisionalAvatar = nil; avatarState = .failed; avatarFeedback = "Photo upload did not complete."
            }
        } catch is CancellationError {
            recordAvatarDebug("UPLOAD", "CANCELLED")
            provisionalAvatar = nil; avatarState = .failed
            avatarFeedback = "Photo upload was interrupted. Retry to try again."
        } catch {
            recordAvatarDebug("UPLOAD", avatarFailureCategory(error))
            provisionalAvatar = nil; avatarState = .failed
            avatarFeedback = "Photo upload did not complete. Your active photo was not changed."
        }
        avatarPickerItem = nil
    }

    @MainActor private func retryAvatarUpload() async {
        guard let item = retryAvatarPickerItem else {
            avatarState = .failed
            avatarFeedback = "Choose the photo again to retry the upload."
            return
        }
        await selectAvatar(item)
    }

    @MainActor private func beginAvatarReplacement() -> Int {
        avatarPresentationGeneration &+= 1
        return avatarPresentationGeneration
    }

    /// The avatar route only returns 503 after its server-side admission path
    /// has failed closed before publishing a replacement avatar. A single,
    /// short retry is therefore safe for that explicit transient outcome.
    /// Other HTTP failures remain one-shot so authorization and validation
    /// faults cannot be masked or replayed.
    @MainActor private func uploadAvatarOnceAfterTransientServiceFailure(_ data: Data) async throws -> StyleFriendAvatarUploadReceipt {
        do {
            return try await service.uploadProfileAvatar(data, mimeType: "image/jpeg")
        } catch StyleFriendsServiceError.httpStatus(503) {
            recordAvatarDebug("UPLOAD_RETRY", "HTTP_503_ATTEMPT_2")
            try await Task.sleep(for: .milliseconds(350))
            return try await service.uploadProfileAvatar(data, mimeType: "image/jpeg")
        }
    }

    private struct PreparedAvatarUpload {
        let jpegData: Data
        let preview: UIImage
    }

    /// Produces the exact raw JPEG body sent to the Worker. The upload body is
    /// not multipart or JSON/base64, so its byte budget is the body budget.
    /// ImageIO reads pixel metadata first and creates a thumbnail, rather than
    /// decoding a full-resolution camera image into a UIKit bitmap.
    private func prepareAvatarUpload(from sourceData: Data) -> PreparedAvatarUpload? {
        let maximumUploadBytes = 7 * 1024 * 1024
        let maximumPixels = 24_000_000
        guard let source = CGImageSourceCreateWithData(sourceData as CFData, nil),
              CGImageSourceGetCount(source) == 1,
              let sourceType = CGImageSourceGetType(source),
              let decodedType = UTType(sourceType as String),
              decodedType.conforms(to: .image),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let sourceWidth = properties[kCGImagePropertyPixelWidth] as? Int,
              let sourceHeight = properties[kCGImagePropertyPixelHeight] as? Int,
              sourceWidth > 0, sourceHeight > 0 else {
            return nil
        }

        let sourcePixels = Double(sourceWidth) * Double(sourceHeight)
        guard sourcePixels.isFinite, sourcePixels > 0 else { return nil }
        let pixelScale = min(1, sqrt(Double(maximumPixels) / sourcePixels))
        let initialWidth = max(1, Int((Double(sourceWidth) * pixelScale).rounded(.down)))
        let initialHeight = max(1, Int((Double(sourceHeight) * pixelScale).rounded(.down)))
        guard Double(initialWidth) * Double(initialHeight) <= Double(maximumPixels) else { return nil }

        // ImageIO identifies decoded content from the bytes; the picker MIME
        // declaration is never trusted as the image-type authority. Each
        // factor preserves aspect ratio and never upscales. Additional
        // reductions are only for JPEG byte pressure, not a hardcoded edge.
        let sizeFactors: [Double] = [1, 0.85, 0.70, 0.55]
        let qualityCandidates: [CGFloat] = [0.92, 0.88, 0.84, 0.80]
        for factor in sizeFactors {
            let targetWidth = max(1, Int((Double(initialWidth) * factor).rounded(.down)))
            let targetHeight = max(1, Int((Double(initialHeight) * factor).rounded(.down)))
            guard targetWidth <= sourceWidth, targetHeight <= sourceHeight,
                  Double(targetWidth) * Double(targetHeight) <= Double(maximumPixels),
                  let thumbnail = thumbnail(from: source, width: targetWidth, height: targetHeight) else {
                continue
            }
            for quality in qualityCandidates {
                let format = UIGraphicsImageRendererFormat()
                format.scale = 1
                format.opaque = true
                let upright = UIGraphicsImageRenderer(
                    size: CGSize(width: thumbnail.width, height: thumbnail.height),
                    format: format
                ).image { _ in
                    UIImage(cgImage: thumbnail).draw(in: CGRect(x: 0, y: 0, width: thumbnail.width, height: thumbnail.height))
                }
                guard let jpeg = upright.jpegData(compressionQuality: quality),
                      jpeg.count <= maximumUploadBytes,
                      let result = decodedJPEG(jpeg),
                      result.width <= sourceWidth, result.height <= sourceHeight,
                      Double(result.width) * Double(result.height) <= Double(maximumPixels) else {
                    continue
                }
                // UIGraphics re-renders pixels into a fresh JPEG, excluding
                // source EXIF, GPS, orientation, and other image metadata.
                return PreparedAvatarUpload(jpegData: jpeg, preview: upright)
            }
        }
        return nil
    }

    private func thumbnail(from source: CGImageSource, width: Int, height: Int) -> CGImage? {
        let maximumEdge = max(width, height)
        guard maximumEdge > 0 else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumEdge,
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: false
        ] as CFDictionary)
    }

    private func decodedJPEG(_ data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { return nil }
        return (width, height)
    }

    @MainActor private func removeAvatar() async {
        _ = beginAvatarReplacement()
        avatarState = .removing; avatarFeedback = nil
        do {
            try await service.removeProfileAvatar()
            socialProfileDraft.avatarReference = ""; savedSocialProfileDraft.avatarReference = ""
            activeAvatarData = nil; activeAvatarReference = nil; provisionalAvatar = nil; avatarState = .noPhoto
        } catch {
            avatarState = .failed; avatarFeedback = "Photo removal did not complete. Your existing photo may still be active."
        }
    }

    @MainActor private func refreshAvatar() async {
        guard let reference = StyleFriendsSocialImageReference(socialProfileDraft.avatarReference) else {
            activeAvatarData = nil; activeAvatarReference = nil
            if avatarState == .uploading || avatarState == .replacing {
                avatarState = .failed
                avatarFeedback = "Your profile photo could not be confirmed. Try again."
            } else if avatarState != .underReview && avatarState != .failed && avatarState != .rejected {
                avatarState = .noPhoto
            }
            return
        }
        await refreshAvatar(reference: reference.value, generation: avatarPresentationGeneration)
    }

    @MainActor private func refreshAvatar(reference expectedReference: String, generation: Int) async {
        guard let reference = StyleFriendsSocialImageReference(expectedReference) else { return }
        let receipt = await service.socialImageReceipt(reference)
        guard generation == avatarPresentationGeneration,
              socialProfileDraft.avatarReference == expectedReference else {
            recordAvatarDebug("AVATAR_FETCH", "STALE_IGNORED")
            return
        }
        recordAvatarDebug("AVATAR_FETCH", receipt.httpStatus.map(String.init) ?? "NO_HTTP")
        switch receipt.state {
        case let .loaded(data):
            activeAvatarData = data
            activeAvatarReference = expectedReference
            provisionalAvatar = nil
            avatarState = .active
            recordAvatarDebug("AVATAR_RENDER", "PASS")
        case .revoked:
            activeAvatarData = nil; activeAvatarReference = nil; provisionalAvatar = nil
            avatarState = .failed
            avatarFeedback = "Your saved photo is no longer available. It was not removed from this screen."
        case .unauthorized, .unavailable, .failed:
            activeAvatarData = nil; activeAvatarReference = nil; provisionalAvatar = nil
            avatarState = .failed
            avatarFeedback = "Your saved photo could not be loaded. Your profile photo was not removed."
        case .loading: break
        }
    }

    @MainActor private func recordAvatarDebug(_ stage: String, _ value: String) {
#if DEBUG
        avatarDebugStages.append("\(stage):\(value)")
        if avatarDebugStages.count > 12 { avatarDebugStages.removeFirst(avatarDebugStages.count - 12) }
#endif
    }

    private func avatarFailureCategory(_ error: Error) -> String {
        if let error = error as? StyleFriendsServiceError {
            switch error {
            case .signInRequired: return "SESSION_REQUIRED"
            case let .httpStatus(status): return "HTTP_\(status)"
            case .unavailable: return "HTTP_REJECTED"
            case .networkUnavailable: return "NETWORK"
            case .invalidResponse: return "RESPONSE_DECODE"
            case .invalidProfile: return "PROFILE"
            }
        }
        return "UNKNOWN"
    }

    private var discoveryContent: some View {
        VStack(spacing: 16) {
            Text("Search only public Style Friends display names. Contacts, email, private Profile, Closet, scans, AI Memory, and location are never searched.")
                .font(.footnote).foregroundStyle(.secondary).padding(.horizontal)
            HStack {
                TextField("Search public display names", text: $discoveryQuery).textFieldStyle(.roundedBorder).textInputAutocapitalization(.words)
                Button("Search") { Task { await discover() } }.buttonStyle(.borderedProminent).disabled(discoveryQuery.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
            }.padding(.horizontal)
            if let discoveryFeedback { Text(discoveryFeedback).font(.footnote).foregroundStyle(.secondary).padding(.horizontal) }
            if discoveryResults.isEmpty {
                Spacer()
                unavailableCard(title: "Find a Style Friend", detail: "Search for a public Style Friends display name after that person chooses to be discoverable.", icon: "magnifyingglass")
                Spacer()
            } else {
                List(discoveryResults) { person in
                    VStack(alignment: .leading, spacing: 7) {
                        Text(person.displayName).font(.headline)
                        if let bio = person.styleBio, !bio.isEmpty { Text(bio).font(.subheadline).foregroundStyle(.secondary).lineLimit(2) }
                        if !person.styleCategories.isEmpty { Text(person.styleCategories.map(\.displayName).joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }
                        discoveryRelationshipActions(for: person)
                    }.padding(.vertical, 4)
                }.listStyle(.plain)
            }
        }
        .navigationTitle("Find Style Friends")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { isShowingDiscovery = false } } }
    }

    private var socialProfileSaveControl: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { Task { await saveProfile() } } label: {
                HStack {
                    if profileSaveState == .saving { ProgressView().tint(.white) }
                    Text(profileSaveState == .saving ? "Saving Social Profile…" : (socialProfileEstablished ? "Save Social Profile" : "Create Social Profile"))
                    Spacer()
                    if profileSaveState == .success { Image(systemName: "checkmark.circle.fill") }
                }
                .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canSaveSocialProfile)
            .accessibilityHint(socialProfileSaveAccessibilityHint)
            if let message = profileSaveState.message ?? profileFeedback {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(profileSaveState.isFailure ? .red : .secondary)
                    .accessibilityLabel(message)
            }
            if profileSaveState.isFailure {
                Button("Retry Save") { Task { await saveProfile() } }
                    .buttonStyle(.bordered)
                    .disabled(!socialProfileDraft.isValid)
            }
        }
        .padding(.vertical, 4)
    }

    private func friendRow(_ person: StyleFriendListItem, actions: [StyleFriendRelationshipOperation]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { selectedFriend = person } label: {
                HStack {
                    StyleFriendsPublicAvatar(
                        reference: person.avatarReference,
                        displayName: person.displayName ?? "Style Friend",
                        service: service,
                        size: 52
                    )
                    VStack(alignment: .leading) {
                        Text(person.displayName ?? "Style Friend").font(.headline)
                        Text("View social profile").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            HStack {
                if person.state == .friends { Button("Message") { Task { await startConversation(with: person.socialReference) } }.disabled(relationshipActions[person.socialReference] != nil) }
                ForEach(actions, id: \.self) { action in relationshipActionButton(title: action.rawValue.capitalized, target: person.socialReference, operation: action, destructive: action == .remove || action == .block) }
            }
                .buttonStyle(.bordered)
        }.padding(18).background(KigoStyleFriendsPalette.surface).clipShape(RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(KigoStyleFriendsPalette.border))
    }

    @MainActor private func refreshFromServer() async {
        requiresAccountReconnect = !service.hasValidSession
        guard service.hasValidSession else {
            if !socialProfileEstablished {
                socialProfileLoadState = .unavailable
                profileFeedback = "Your public Style Friends profile could not be refreshed until your session is available."
            }
            feedState = ownerDeviceAcceptance.visibleIndicator == nil ? .signInRequired : .unavailable
            isLoading = false
            return
        }
        if case let .active(acceptance) = ownerDeviceAcceptance {
            // An acceptance process sees only its injected synthetic card. It
            // must never surface or append to the owner's local share history.
            approvedCards = acceptance.syntheticCard.map { [$0] } ?? []
        } else {
            approvedCards = ShareableScoreCardLocalStore().cards
        }

        socialProfileLoadState = socialProfileEstablished ? .established : .loading
        isLoading = true
        defer { isLoading = false }

        // Feed loading is independent from relationship/profile loading. A
        // slow profile or friend-list request must never hold the feed spinner.
        async let feedRefresh: Void = refreshFeed()

        let profileGeneration = avatarPresentationGeneration
        async let profileRequest = service.socialProfile()

        let lists = await StyleFriendsListsSnapshot.load(
            friends: { try await service.listFriends() },
            incoming: { try await service.listIncomingRequests() },
            outgoing: { try await service.listOutgoingRequests() },
            posts: { try await service.listMySharedLooks() }
        )
        guard profileGeneration == avatarPresentationGeneration else { return }
        guard service.hasValidSession else {
            requiresAccountReconnect = true
            return
        }
        listRefreshErrors = [:]
        switch lists.friends {
        case .success(let page): friends = page.items
        case .failure: listRefreshErrors[.friends] = "Your friend list could not be loaded. This does not mean your friends were removed. Try again."
        }
        switch lists.incoming {
        case .success(let page): incoming = page.items
        case .failure: listRefreshErrors[.requests] = "Friend requests could not be refreshed. Try again."
        }
        switch lists.outgoing {
        case .success(let page): outgoing = page.items
        case .failure: listRefreshErrors[.requests] = "Friend requests could not be refreshed. Try again."
        }
        switch lists.posts {
        case .success(let page): sharedLooks = page.items
        case .failure: listRefreshErrors[.sharedLooks] = "Shared looks could not be loaded. Try again."
        }
        isLoading = false

        async let hydratedFriends = hydratePublicProfiles(friends)
        async let hydratedIncoming = hydratePublicProfiles(incoming)
        async let hydratedOutgoing = hydratePublicProfiles(outgoing)
        let hydrated = await (hydratedFriends, hydratedIncoming, hydratedOutgoing)
        guard profileGeneration == avatarPresentationGeneration, service.hasValidSession else { return }
        friends = hydrated.0
        incoming = hydrated.1
        outgoing = hydrated.2

        let profileResult: Result<StyleFriendVisibleProfile?, Error>
        do {
            profileResult = .success(try await profileRequest)
        } catch {
            profileResult = .failure(error)
        }

        _ = await feedRefresh
        guard profileGeneration == avatarPresentationGeneration else { return }
        switch profileResult {
            case let .success(.some(profile)):
                let draft = SocialProfileDraft(profile: profile)
                socialProfileDraft = draft
                savedSocialProfileDraft = draft
                socialProfileEstablished = true
                socialProfileLoadState = .established
                profileSaveState = .unchanged
                profileFeedback = nil
                if profile.avatarState == .underReview { avatarState = .underReview }
                await refreshAvatar()
            // Only an authoritative successful empty profile response may enter
            // create-profile mode and clear the prior canonical snapshot.
            case .success(nil):
                socialProfileDraft = SocialProfileDraft()
                savedSocialProfileDraft = SocialProfileDraft()
                socialProfileEstablished = false
                socialProfileLoadState = .missing
                profileSaveState = .unchanged
                profileFeedback = "Create your public Style Friends profile to share a display name, photo, and chosen style details."
            case .failure:
                socialProfileLoadState = .unavailable
                if profileFeedback == nil {
                    profileFeedback = "Your public Style Friends profile could not be refreshed. Your last confirmed public details remain available."
                }
            }
    }

    /// The relationship-list payload is intentionally small. Hydrating an
    /// accepted social profile keeps the name/avatar truthful across screens
    /// without ever importing the account's private StyleMatch data.
    @MainActor private func hydratePublicProfiles(_ rows: [StyleFriendListItem]) async -> [StyleFriendListItem] {
        var hydrated: [StyleFriendListItem] = []
        hydrated.reserveCapacity(rows.count)
        for row in rows {
            do {
                if let profile = try await service.socialProfile(for: row.socialReference) {
                    hydrated.append(row.hydrated(with: profile))
                    continue
                }
            } catch {
                // Keep the server relationship row as a bounded loading/error
                // fallback; the friend profile endpoint is independently
                // authorization-checked by the Worker.
            }
            hydrated.append(row)
        }
        return hydrated
    }

    /// Relationship rows are compact transport projections. After an explicit
    /// public-profile save, rehydrate them from the profile authority so a
    /// cached display name can never win over the confirmed server value.
    @MainActor private func refreshRelationshipPublicProfiles() async {
        guard service.hasValidSession else { return }
        do {
            async let friendPage = service.listFriends()
            async let incomingPage = service.listIncomingRequests()
            async let outgoingPage = service.listOutgoingRequests()
            friends = await hydratePublicProfiles(try await friendPage.items)
            incoming = await hydratePublicProfiles(try await incomingPage.items)
            outgoing = await hydratePublicProfiles(try await outgoingPage.items)
        } catch {
            // The just-confirmed public profile remains authoritative. Keep
            // current relationship rows until their next successful refresh.
        }
    }

    private var feedStagingRuntimeAuthorized: Bool {
        guard StyleFriendsFeedRuntimeAuthority.current == .stagingAuthorized else { return false }
        return StyleFriendsDMStagingTransportConfiguration(baseURL: AppBackendConfiguration.configuredAPIBaseURL(bundle: .main)) != nil
    }

    @MainActor private func refreshFeed() async {
        guard service.hasValidSession else { feedState = .signInRequired; return }
        guard feedStagingRuntimeAuthorized else { feedState = .unavailable; return }
        let prior = currentFeedPage
        feedState = prior.map(StyleFriendsFeedState.refreshing) ?? .loading
        do {
            let page = try await service.feed()
            feedState = page.items.isEmpty ? .empty : .loaded(page)
        } catch let error as StyleFriendsServiceError {
            switch error {
            case .signInRequired: feedState = .signInRequired
            case .networkUnavailable: feedState = .networkUnavailable
            default: feedState = .serverUnavailable
            }
        } catch { feedState = .serverUnavailable }
    }

    @MainActor private func loadMoreFeed(from page: StyleFriendsFeedPage) async {
        guard feedStagingRuntimeAuthorized, let cursor = page.nextCursor else { return }
        feedState = .loadingMore(page)
        do {
            let next = try await service.feed(cursor: cursor)
            let known = Set(page.items.map(\.id))
            let merged = page.items + next.items.filter { !known.contains($0.id) }
            feedState = .loaded(.init(items: merged, nextCursor: next.nextCursor))
        } catch let error as StyleFriendsServiceError {
            switch error {
            case .signInRequired: feedState = .signInRequired
            case .networkUnavailable: feedState = .networkUnavailable
            default: feedState = .serverUnavailable
            }
        } catch { feedState = .serverUnavailable }
    }

    private var currentFeedPage: StyleFriendsFeedPage? {
        switch feedState {
        case .loaded(let page), .refreshing(let page), .loadingMore(let page): page
        default: nil
        }
    }
    @MainActor private func reloadForAccountChange() async {
        clearAccountScopedState()
        await refreshFromServer()
    }
    @MainActor private func clearAccountScopedState() {
        requiresAccountReconnect = !service.hasValidSession
        listRefreshErrors = [:]
        friends = []
        incoming = []
        outgoing = []
        sharedLooks = []
        approvedCards = []
        socialProfileDraft = SocialProfileDraft()
        savedSocialProfileDraft = SocialProfileDraft()
        socialProfileEstablished = false
        socialProfileLoadState = .loading
        profileSaveState = .unchanged
        selectedFriend = nil
        reviewCard = nil
        selectedPost = nil
        profileFeedback = nil
        avatarPickerItem = nil
        retryAvatarPickerItem = nil
        provisionalAvatar = nil
        activeAvatarData = nil
        activeAvatarReference = nil
        avatarPresentationGeneration &+= 1
        avatarFeedback = nil
        avatarState = .noPhoto
        actionFeedback = nil
    }
    @MainActor private func saveProfile() async {
        guard let update = socialProfileDraft.update, socialProfileDraft.isValid else {
            profileSaveState = .failure("Add a display name and keep the bio and style selections within the stated limits.")
            return
        }
        guard socialProfileDraft != savedSocialProfileDraft else {
            profileSaveState = .unchanged
            return
        }
        profileSaveState = .saving
        profileFeedback = nil
        let profileGeneration = avatarPresentationGeneration
        do {
            guard let profile = try await service.saveSocialProfile(update) else {
                profileSaveState = .failure("Style Friends did not return the saved profile. Your edits are still here; try again.")
                return
            }
            guard profileGeneration == avatarPresentationGeneration else {
                profileSaveState = .unchanged
                return
            }
            let refreshed = SocialProfileDraft(profile: profile)
            socialProfileDraft = refreshed
            savedSocialProfileDraft = refreshed
            socialProfileEstablished = true
            profileSaveState = .success
            if profile.avatarState == .underReview { avatarState = .underReview }
            await refreshAvatar()
            await refreshRelationshipPublicProfiles()
        } catch let error as StyleFriendsServiceError {
            profileSaveState = .failure(error.errorDescription ?? "Your Style Friends profile could not be saved. Try again.")
        } catch {
            profileSaveState = .failure("Your Style Friends profile could not be saved. Try again.")
        }
    }

    private var canSaveSocialProfile: Bool {
        socialProfileDraft.isValid && socialProfileDraft != savedSocialProfileDraft && profileSaveState != .saving
    }

    private var socialProfileSaveAccessibilityHint: String {
        if profileSaveState == .saving { return "Saving your public Style Friends profile." }
        if !socialProfileDraft.isValid { return "Add a display name and keep profile details within their limits before saving." }
        if socialProfileDraft == savedSocialProfileDraft { return "No changes to save." }
        return socialProfileEstablished ? "Saves only your public Style Friends profile." : "Creates your intentional public Style Friends profile using only the details shown here."
    }

    private func toggleStyleCategory(_ category: StyleFriendStyleCategory) {
        if socialProfileDraft.categories.contains(category) {
            socialProfileDraft.categories.remove(category)
        } else if socialProfileDraft.categories.count < StyleFriendProfileUpdate.maximumStyleCategories {
            socialProfileDraft.categories.insert(category)
        }
        updateSocialProfileSaveReadiness()
    }

    private func updateSocialProfileSaveReadiness() {
        guard profileSaveState != .saving else { return }
        profileSaveState = socialProfileDraft == savedSocialProfileDraft ? .unchanged : .ready
    }
    @MainActor private func discover() async {
        let query = discoveryQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else { return }
        discoveryFeedback = nil
        do { discoveryResults = try await service.discoverStyleFriends(query: query) }
        catch let error as StyleFriendsServiceError { discoveryFeedback = error.errorDescription }
        catch { discoveryFeedback = "Style Friends discovery is unavailable right now." }
    }
    @MainActor private func sendDiscoveryRequest(to person: StyleFriendDiscoveryItem) async {
        await performRelationship(target: person.socialReference, operation: .send, success: "Friend request sent to \(person.displayName).")
    }

    @ViewBuilder
    private func discoveryRelationshipActions(for person: StyleFriendDiscoveryItem) -> some View {
        switch discoveryRelationshipState(for: person) {
        case .none:
            relationshipActionButton(title: "Add Friend", target: person.socialReference, operation: .send, prominent: true)
        case .outgoingRequest:
            HStack {
                Text("Request Sent").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                relationshipActionButton(title: "Cancel", target: person.socialReference, operation: .cancel)
            }.buttonStyle(.bordered)
        case .incomingRequest:
            HStack {
                relationshipActionButton(title: "Accept", target: person.socialReference, operation: .accept)
                relationshipActionButton(title: "Decline", target: person.socialReference, operation: .decline, destructive: true)
            }.buttonStyle(.bordered)
        case .friends:
            HStack {
                Button("Message") { Task { await startConversation(with: person.socialReference) } }
                Button("View Profile") { selectedFriend = discoveryListItem(person, state: .friends) }
                relationshipActionButton(title: "Remove", target: person.socialReference, operation: .remove, destructive: true)
            }.buttonStyle(.bordered)
        case .blocked:
            Text("Unavailable while blocked").font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private func discoveryRelationshipState(for person: StyleFriendDiscoveryItem) -> StyleFriendRelationshipState {
        if friends.contains(where: { $0.socialReference == person.socialReference }) { return .friends }
        if outgoing.contains(where: { $0.socialReference == person.socialReference }) { return .outgoingRequest }
        if incoming.contains(where: { $0.socialReference == person.socialReference }) { return .incomingRequest }
        return .none
    }

    private func discoveryListItem(_ person: StyleFriendDiscoveryItem, state: StyleFriendRelationshipState) -> StyleFriendListItem {
        .init(socialReference: person.socialReference, displayName: person.displayName, avatarReference: person.avatarReference, state: state, createdAt: person.updatedAt)
    }
    @MainActor private func startConversation(with friend: StyleFriendAccountReference) async -> Bool {
        let binding = StyleFriendsDMRuntimeBinding.current()
        let initialReadiness = binding.readiness
        do {
            _ = try await binding.service.createConversation(friend: friend)
#if DEBUG
            dmReadinessDebug = StyleFriendsDMRuntimeReadiness(
                accountSessionPresent: initialReadiness.accountSessionPresent,
                sessionEnvironmentMatch: initialReadiness.sessionEnvironmentMatch,
                socialAuthorityReady: initialReadiness.socialAuthorityReady,
                dmAuthorityReady: initialReadiness.dmAuthorityReady,
                relationshipIsFriend: true,
                conversationServiceReady: initialReadiness.conversationServiceReady,
                failure: initialReadiness.failure
            ).recordingConversationResult(.success(())).debugSummary
#endif
            isShowingConversations = true
            return true
        } catch let error as StyleFriendsDMError {
#if DEBUG
            dmReadinessDebug = StyleFriendsDMRuntimeReadiness(
                accountSessionPresent: initialReadiness.accountSessionPresent,
                sessionEnvironmentMatch: initialReadiness.sessionEnvironmentMatch,
                socialAuthorityReady: initialReadiness.socialAuthorityReady,
                dmAuthorityReady: initialReadiness.dmAuthorityReady,
                relationshipIsFriend: true,
                conversationServiceReady: initialReadiness.conversationServiceReady,
                failure: initialReadiness.failure
            ).recordingConversationResult(.failure(error)).debugSummary
#endif
            actionFeedback = StyleFriendsDMPresentationMapper.userMessage(for: error)
            return false
        } catch {
            actionFeedback = "Messaging is temporarily unavailable. Please try again later."
            return false
        }
    }
    @MainActor private func publish(_ draft: SharedOutfitPostDraft) async throws {
        _ = try await service.publish(draft)
        await refreshFromServer()
    }
    @ViewBuilder private func relationshipActionButton(title: String, target: StyleFriendAccountReference, operation: StyleFriendRelationshipOperation, destructive: Bool = false, prominent: Bool = false) -> some View {
        let state = relationshipActions[target]
        if prominent {
            Button(state?.visibleLabel ?? title, role: destructive ? .destructive : nil) { Task { await performRelationship(target: target, operation: operation) } }
                .buttonStyle(.borderedProminent)
                .disabled(state != nil)
                .accessibilityLabel(state?.visibleLabel ?? title)
                .accessibilityHint(state == nil ? "Updates this Style Friends relationship." : "Relationship action in progress.")
        } else {
            Button(state?.visibleLabel ?? title, role: destructive ? .destructive : nil) { Task { await performRelationship(target: target, operation: operation) } }
                .buttonStyle(.bordered)
                .disabled(state != nil)
                .accessibilityLabel(state?.visibleLabel ?? title)
                .accessibilityHint(state == nil ? "Updates this Style Friends relationship." : "Relationship action in progress.")
        }
    }
    @MainActor private func performRelationship(target: StyleFriendAccountReference, operation: StyleFriendRelationshipOperation, success: String? = nil) async {
        guard relationshipActions[target] == nil, let action = StyleFriendRelationshipActionState(operation: operation) else { return }
        relationshipActions[target] = action
        defer { relationshipActions[target] = nil }
        do {
            _ = try await service.relationship(target: target, operation: operation)
            actionFeedback = success
            await refreshFromServer()
        } catch {
            actionFeedback = "That Style Friends action could not be completed. Your relationship status was refreshed."
            await refreshFromServer()
        }
    }
    @MainActor private func deletePost(_ reference: StyleFriendsOpaqueRouteReference) async {
        do {
            try await service.deletePost(reference)
            actionFeedback = nil
            await refreshFromServer()
        } catch {
            actionFeedback = "The shared look could not be deleted. Please try again later."
        }
    }
    @MainActor private func revoke(_ card: CreatedShareableScoreCard) async {
        do {
            if let acceptance = ownerDeviceAcceptance.configuration {
                try await ShareableScoreCardClient(
                    configuration: ShareableScoreCardConfiguration(baseURL: acceptance.baseURL),
                    accountSession: { acceptance.session }
                ).revoke(token: card.token)
            } else {
                try await ShareableScoreCardClient(configuration: .current).revoke(token: card.token)
                ShareableScoreCardLocalStore().markRevoked(token: card.token)
            }
            await refreshFromServer()
        }
        catch { profileFeedback = "Unable to revoke the shared card." }
    }

    private func unavailableCard(title: String, detail: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(detail).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

/// Renders only the opaque, explicitly public Style Friends avatar reference
/// returned by the authenticated social service. Private account photos and
/// Profile/Closet image sources are intentionally not consulted.
private struct StyleFriendsPublicAvatar: View {
    let reference: String?
    let displayName: String
    let service: StyleFriendsService
    let size: CGFloat
    @State private var imageData: Data?

    var body: some View {
        ZStack {
            Circle().fill(Color(uiColor: .tertiarySystemFill))
            if let imageData, let image = UIImage(data: imageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipShape(Circle())
            } else {
                Text(initials)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("\(displayName) public Style Friends photo")
        .task(id: reference) {
            imageData = nil
            guard let reference, let opaqueReference = StyleFriendsSocialImageReference(reference) else { return }
            let receipt = await service.socialImageReceipt(opaqueReference)
            guard case let .loaded(data) = receipt.state else { return }
            imageData = data
        }
    }

    private var initials: String {
        let value = displayName.split(whereSeparator: { $0.isWhitespace }).prefix(2).compactMap(\.first).map(String.init).joined()
        return value.isEmpty ? "S" : value.uppercased()
    }
}

/// A dedicated social-navigation surface instead of the system menu picker.
/// It keeps route selection local to this view while providing room for the
/// full, customer-facing names at comfortable Dynamic Type sizes.
private struct StyleFriendsSectionNavigationTrigger: View {
    let section: StyleFriendsView.Section
    let onSelect: (StyleFriendsView.Section) -> Void
    let openNavigation: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(StyleFriendsView.Section.allCases) { item in
                            Button { onSelect(item) } label: {
                                Label(item.compactTitle, systemImage: item.icon)
                                    .font(.subheadline.weight(.semibold))
                                    .fixedSize(horizontal: true, vertical: false)
                                    .padding(.horizontal, 16)
                                    .frame(minHeight: 48)
                                    .foregroundStyle(item == section ? Color.white : KigoStyleFriendsPalette.text)
                                    .background(item == section ? KigoStyleFriendsPalette.button : KigoStyleFriendsPalette.soft, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .id(item.id)
                            .accessibilityLabel(item.rawValue)
                            .accessibilityAddTraits(item == section ? .isSelected : [])
                        }
                    }
                }
                .onChange(of: section) { selected in
                    proxy.scrollTo(selected.id, anchor: .center)
                }
            }
            Button(action: openNavigation) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.body.weight(.semibold))
                    .frame(width: 48, height: 48)
                    .background(Color.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Style Friends section")
            .accessibilityValue(section.rawValue)
            .accessibilityHint("Opens Style Friends navigation.")
        }
    }
}

private struct StyleFriendsSectionNavigationSheet: View {
    @Binding var selection: StyleFriendsView.Section
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("selectedAppTheme") private var selectedAppTheme = StyleMatchAppTheme.system.rawValue
    @AppStorage("styleMatchAppearanceMode") private var appearanceMode = StyleMatchAppearanceMode.manual.rawValue
    @AppStorage("styleMatchAdaptiveTheme") private var adaptiveTheme = ""

    private var labelLineLimit: Int { dynamicTypeSize.isAccessibilitySize ? 2 : 1 }
    private var palette: AppPalette {
        StyleMatchAppearanceResolver.resolve(
            modeRawValue: appearanceMode,
            selectedThemeRawValue: selectedAppTheme,
            adaptiveThemeRawValue: adaptiveTheme
        ).theme.palette(for: .profile)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Style Friends")
                    .font(.title3.weight(.bold))
                Text("Move between your social spaces")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)

            VStack(spacing: 4) {
                ForEach(StyleFriendsView.Section.allCases) { item in
                    Button {
                        selection = item
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: item.icon)
                                .font(.headline.weight(.semibold))
                                .frame(width: 28, height: 28)
                                .foregroundStyle(item == selection ? Color.white : palette.accent)
                                .background {
                                    Circle().fill(item == selection ? palette.accent : palette.accent.opacity(0.12))
                                }
                            Text(item.rawValue)
                                .font(.body.weight(item == selection ? .semibold : .regular))
                                .lineLimit(labelLineLimit)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 12)
                            if item == selection {
                                Image(systemName: "checkmark")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(palette.accent)
                                    .accessibilityHidden(true)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                        .padding(.horizontal, 14)
                        .background {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(item == selection ? palette.accent.opacity(0.15) : Color.clear)
                        }
                        .overlay {
                            if item == selection {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(palette.accent.opacity(0.28))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.rawValue)
                    .accessibilityValue(item == selection ? "Selected" : "")
                    .accessibilityHint("Shows the \(item.rawValue) section.")
                }
            }
            .padding(.horizontal, 14)
        }
        .padding(.top, 10)
        .padding(.bottom, 14)
        .frame(maxWidth: 560, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .top) {
            LinearGradient(
                colors: [palette.accent.opacity(0.10), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 112)
            .allowsHitTesting(false)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Style Friends navigation")
    }
}

/// Uses the one StyleMatch account session authority. Style Friends never
/// creates a parallel social-login identity or retains Apple credentials.
private struct StyleFriendsSignInCard: View {
    let onReconnect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Reconnect to Style Friends", systemImage: "person.crop.circle.badge.plus")
                .font(.title3.weight(.semibold))
            Text("Share looks, connect with friends, and have private conversations using your secure KigoStylist account session.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Label("Reconnect using the same Apple account to reload your friends and conversations.", systemImage: "person.crop.circle.badge.exclamationmark")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Reconnect Account", action: onReconnect)
                .buttonStyle(.borderedProminent)
                .accessibilityHint("Closes Style Friends and opens the main account Profile.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

private struct StyleFriendsFeedCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let item: StyleFriendsFeedItem
    let viewFriendProfile: (StyleFriendAccountReference) -> Void
    let didBlock: (StyleFriendAccountReference) async -> Void
    @State private var engagement: StyleFriendsEngagement
    @State private var reactionSummary: StyleFriendReactionSummary?
    @State private var isShowingComments = false
    @State private var isShowingPostReport = false
    @State private var isShowingUserReport = false
    @State private var feedback: String?
    private let service: StyleFriendsService

    init(item: StyleFriendsFeedItem, service: StyleFriendsService, viewFriendProfile: @escaping (StyleFriendAccountReference) -> Void, didBlock: @escaping (StyleFriendAccountReference) async -> Void) {
        self.item = item
        self.service = service
        self.viewFriendProfile = viewFriendProfile
        self.didBlock = didBlock
        _engagement = State(initialValue: StyleFriendsEngagement(likeCount: item.likeCount ?? 0, viewerHasLiked: item.viewerHasLiked ?? false, commentCount: item.commentCount ?? 0))
        _reactionSummary = State(initialValue: item.reactionSummary)
    }

    private var actionLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(spacing: 10))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.title2)
                    .foregroundStyle(KigoStyleFriendsPalette.accent)
                    .frame(width: 46, height: 46)
                    .background(KigoStyleFriendsPalette.accent.opacity(0.12), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("KIGOSTYLIST LOOK")
                        .font(.caption2.weight(.black))
                        .tracking(1.0)
                        .foregroundStyle(KigoStyleFriendsPalette.accent)
                    Text(item.owner.displayName)
                        .font(.headline)
                        .foregroundStyle(KigoStyleFriendsPalette.text)
                    Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(KigoStyleFriendsPalette.secondary)
                }
                Spacer()
                if let score = item.score {
                    VStack(spacing: 0) {
                        Text("\(score)")
                            .font(.title2.weight(.black))
                            .foregroundStyle(KigoStyleFriendsPalette.accent)
                        Text("/100")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(KigoStyleFriendsPalette.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(KigoStyleFriendsPalette.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("KigoStylist score \(score) out of 100")
                }
            }

            StyleFriendsFeedImage(reference: item.socialImageReference, service: service)

            if let title = item.title, !title.isEmpty {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(KigoStyleFriendsPalette.text)
            }
            if let caption = item.caption, !caption.isEmpty {
                Text(caption)
                    .foregroundStyle(KigoStyleFriendsPalette.text)
            }
            if let occasion = item.occasion, !occasion.isEmpty {
                Label(occasion, systemImage: "calendar")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(KigoStyleFriendsPalette.accent)
            }

            if item.likeCount != nil || item.commentCount != nil {
                HStack(spacing: 12) {
                    Label("\(engagement.likeCount) Likes", systemImage: engagement.viewerHasLiked ? "heart.fill" : "heart")
                    Label("\(engagement.commentCount) Comments", systemImage: "bubble")
                }
                .font(.caption)
                .foregroundStyle(KigoStyleFriendsPalette.secondary)
                .accessibilityLabel("Friends engagement counts")
            }

            if let reactionSummary {
                StyleFriendsReactionBar(summary: reactionSummary) { reaction in Task { await setPostReaction(reaction) } }
            }

            Divider().overlay(KigoStyleFriendsPalette.accent.opacity(0.18))

            actionLayout {
                if reactionSummary == nil {
                    Button(engagement.viewerHasLiked ? "Unlike" : "Like") { Task { await toggleLike() } }
                }
                Button("Comments") { isShowingComments = true }
                Menu("More") {
                    Button("View Friend Profile") {
                        if let reference = item.ownerSocialReference {
                            viewFriendProfile(reference)
                        }
                    }
                    .disabled(item.ownerSocialReference == nil)
                    Button("Report Post") { isShowingPostReport = true }
                    if item.ownerSocialReference != nil {
                        Button("Report Friend") { isShowingUserReport = true }
                        Button("Block Friend", role: .destructive) {
                            guard let reference = item.ownerSocialReference else { return }
                            Task { await didBlock(reference) }
                        }
                    }
                }
            }
            .buttonStyle(.bordered)
            .tint(KigoStyleFriendsPalette.accent)
            .controlSize(.large)

            Button("Ask where this is from") { isShowingComments = true }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(KigoStyleFriendsPalette.accent)
                .frame(minHeight: 44, alignment: .leading)
                .accessibilityHint("Opens comments for this shared look. Purchase details are never assumed or prefilled.")

            if let feedback {
                Text(feedback)
                    .font(.caption)
                    .foregroundStyle(KigoStyleFriendsPalette.secondary)
            }
        }
        .padding(20)
        .background(KigoStyleFriendsPalette.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(KigoStyleFriendsPalette.accent.opacity(0.20), lineWidth: 1)
        )
        .sheet(isPresented: $isShowingComments) {
            StyleFriendsCommentsSheet(postReference: item.postReference, service: service, engagement: $engagement)
        }
        .sheet(isPresented: $isShowingPostReport) {
            StyleFriendsReportSheet(title: "Report Post") { draft in
                try await service.reportPost(postReference: item.postReference, draft: draft)
            }
        }
        .sheet(isPresented: $isShowingUserReport) {
            if let reference = item.ownerSocialReference {
                StyleFriendsReportSheet(title: "Report Friend") { draft in
                    try await service.reportUser(friendReference: reference.value, draft: draft)
                }
            }
        }
    }

    @MainActor private func toggleLike() async {
        do {
            engagement = try await (engagement.viewerHasLiked ? service.unlike(postReference: item.postReference) : service.like(postReference: item.postReference))
            StyleMatchPremiumFeedback.selection()
        } catch {
            feedback = StyleFriendsServiceError.unavailable.errorDescription
        }
    }

    @MainActor private func setPostReaction(_ reaction: StyleFriendReactionKind?) async {
        guard let confirmed = reactionSummary else { return }
        let desired = confirmed.viewerReaction == reaction ? nil : reaction
        reactionSummary = StyleFriendsReactionProjection.applying(desired, to: confirmed)
        do {
            reactionSummary = try await service.setReaction(target: .post(item.postReference), reaction: desired)
            StyleMatchPremiumFeedback.selection()
        } catch {
            reactionSummary = confirmed
            feedback = StyleFriendsServiceError.unavailable.errorDescription
        }
    }

}

/// Renders only the opaque social image the feed API returned for this
/// friends-only post. It never substitutes a local scan, Closet image, or
/// unshared card when the authorized read is unavailable or revoked.
private struct StyleFriendsFeedImage: View {
    let reference: String?
    let service: StyleFriendsService
    @State private var imageData: Data?
    @State private var loadState: StyleFriendsSocialImageState = .failed
    @State private var isLoadingImage = false
    @State private var reloadGeneration = 0

    var body: some View {
        Group {
            if let imageData, let image = UIImage(data: imageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 380)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .accessibilityLabel("Friend-approved shared look image")
            } else if isLoadingImage {
                ProgressView("Loading shared look…")
                    .frame(maxWidth: .infinity, minHeight: 180)
                    .background(Color(uiColor: .tertiarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            } else {
                VStack(spacing: 8) {
                    Image(systemName: loadState == .revoked ? "photo.badge.exclamationmark" : "photo.on.rectangle.angled")
                        .font(.title2)
                    Text(imageStatusTitle)
                        .font(.subheadline.weight(.semibold))
                    Text(imageStatusDetail)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    if reference != nil && loadState == .failed {
                        Button("Retry image") { reloadGeneration &+= 1 }
                            .buttonStyle(.bordered)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(18)
                .background(Color(uiColor: .tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .task(id: "\(reference ?? "missing")|\(reloadGeneration)") {
            imageData = nil
            guard let reference, let opaqueReference = StyleFriendsSocialImageReference(reference) else {
                loadState = .failed
                isLoadingImage = false
                return
            }
            isLoadingImage = true
            defer { isLoadingImage = false }
            let receipt = await service.socialImageReceipt(opaqueReference)
            loadState = receipt.state
            if case let .loaded(data) = receipt.state { imageData = data }
        }
    }

    private var imageStatusTitle: String {
        switch loadState {
        case .revoked: return "Shared look image is no longer available"
        case .unauthorized: return "Sign in again to view this shared look"
        case .unavailable, .loading, .failed, .loaded: return "Shared look image unavailable"
        }
    }

    private var imageStatusDetail: String {
        if reference == nil {
            return "This older Friends post has no authorized social-image reference. No private image is substituted."
        }
        return "This post remains a friends-only projection. No private image is substituted."
    }
}

private struct StyleFriendsCommentsSheet: View {
    let postReference: StyleFriendsOpaqueRouteReference
    let service: StyleFriendsService
    @Binding var engagement: StyleFriendsEngagement
    @Environment(\.dismiss) private var dismiss
    @State private var comments: [StyleFriendsComment] = []
    @State private var draft = ""
    @State private var feedback: String?
    @State private var isLoading = true
    @State private var isSubmitting = false
    @State private var reportTarget: StyleFriendsComment?
    @State private var replyTarget: StyleFriendsComment?
    @FocusState private var isCommentComposerFocused: Bool

    private var normalizedDraft: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSubmit: Bool { !normalizedDraft.isEmpty && normalizedDraft.utf16.count <= StyleFriendsEngagementPolicy.maximumCommentUTF16 }

    var body: some View {
        NavigationStack {
            List {
                if isLoading { ProgressView("Loading comments…") }
                else if comments.isEmpty { Text("No comments yet. Be respectful and keep comments about the shared look.").foregroundStyle(.secondary) }
                ForEach(comments) { comment in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(comment.authorDisplayName ?? "Style Friend").font(.caption).foregroundStyle(.secondary)
                        if let reply = comment.replyPreview { Text(reply.presentationText).font(.caption).foregroundStyle(.secondary).accessibilityLabel("Reply to \(reply.presentationText)") }
                        Text(comment.text)
                        Text(comment.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(.secondary)
                        StyleFriendsReactionBar(summary: reactionSummary(for: comment)) { reaction in
                            Task { await setReaction(for: comment, reaction: reaction) }
                        }
                        Menu("Actions") {
                            Button("Reply") { replyTarget = comment }
                            if comment.isOwner {
                                Button("Delete Comment", role: .destructive) { Task { await delete(comment) } }
                            } else {
                                Button("Report Comment") { reportTarget = comment }
                            }
                        }.buttonStyle(.bordered)
                    }
                }
                Section("Comment or ask about this look") {
                    Text("Ask respectfully where an outfit is from. The post owner chooses whether to share purchase details; KigoStylist never infers a retailer, product source, or ownership.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    TextField("Write a comment or purchase question", text: $draft, axis: .vertical)
                        .lineLimit(2...5)
                        .focused($isCommentComposerFocused)
                        .accessibilityLabel("Comment or purchase question")
                    if let replyTarget { HStack { Text("Replying to \(replyTarget.authorDisplayName ?? "Style Friend")"); Spacer(); Button("Cancel reply") { self.replyTarget = nil } }.font(.caption).foregroundStyle(.secondary) }
                    Button(isSubmitting ? "Posting Comment…" : "Post Comment") { Task { await addComment() } }
                        .disabled(!canSubmit || isSubmitting)
                        .accessibilityHint(isSubmitting ? "Your comment is being submitted." : "Posts a comment after Style Friends safety review.")
                    if let feedback { Text(feedback).font(.footnote).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("Comments")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { isCommentComposerFocused = false }
                }
            }
        }
        .task { await load() }
        .sheet(item: $reportTarget) { comment in
            StyleFriendsReportSheet(title: "Report Comment") { draft in try await service.reportComment(commentReference: comment.commentReference, draft: draft) }
        }
    }

    @MainActor private func load() async {
        defer { isLoading = false }
        do { comments = try await service.comments(postReference: postReference, cursor: nil).items }
        catch { feedback = StyleFriendsServiceError.unavailable.errorDescription }
    }
    @MainActor private func addComment() async {
        guard canSubmit else { return }; isSubmitting = true; defer { isSubmitting = false }
        do {
            let submission = try await service.addComment(postReference: postReference, draft: .init(text: normalizedDraft, parentCommentReference: replyTarget?.commentReference))
            if let comment = submission.comment {
                comments.append(comment)
                engagement = StyleFriendsEngagement(likeCount: engagement.likeCount, viewerHasLiked: engagement.viewerHasLiked, commentCount: engagement.commentCount + 1)
                draft = ""
                replyTarget = nil
                isCommentComposerFocused = false
            } else if submission.deliveryStatus == .underReview {
                feedback = "Your comment is under review and is not visible to friends."
            } else if submission.deliveryStatus == .rejected {
                feedback = "Your comment could not be posted under the Style Friends safety rules."
            } else {
                feedback = StyleFriendsServiceError.invalidResponse.errorDescription
            }
        }
        catch { feedback = StyleFriendsServiceError.unavailable.errorDescription }
    }
    @MainActor private func delete(_ comment: StyleFriendsComment) async {
        do { try await service.deleteOwnComment(commentReference: comment.commentReference); comments.removeAll { $0.id == comment.id }; engagement = StyleFriendsEngagement(likeCount: engagement.likeCount, viewerHasLiked: engagement.viewerHasLiked, commentCount: max(0, engagement.commentCount - 1)) }
        catch { feedback = StyleFriendsServiceError.unavailable.errorDescription }
    }

    private func reactionSummary(for comment: StyleFriendsComment) -> StyleFriendReactionSummary? { comment.reactionSummary }
    @MainActor private func setReaction(for comment: StyleFriendsComment, reaction: StyleFriendReactionKind?) async {
        guard let serverSummary = comment.reactionSummary, let index = comments.firstIndex(where: { $0.id == comment.id }) else { return }
        let desired = serverSummary.viewerReaction == reaction ? nil : reaction
        let optimistic = StyleFriendsReactionProjection.applying(desired, to: serverSummary)
        comments[index] = StyleFriendsComment(commentReference: comment.commentReference, text: comment.text, isOwner: comment.isOwner, createdAt: comment.createdAt, updatedAt: comment.updatedAt, authorDisplayName: comment.authorDisplayName, replyPreview: comment.replyPreview, reactionSummary: optimistic)
        do {
            let confirmed = try await service.setReaction(target: .comment(comment.commentReference), reaction: desired)
            comments[index] = StyleFriendsComment(commentReference: comment.commentReference, text: comment.text, isOwner: comment.isOwner, createdAt: comment.createdAt, updatedAt: comment.updatedAt, authorDisplayName: comment.authorDisplayName, replyPreview: comment.replyPreview, reactionSummary: confirmed)
        } catch {
            comments[index] = comment
            feedback = StyleFriendsServiceError.unavailable.errorDescription
        }
    }
}

private struct StyleFriendsReactionBar: View {
    let summary: StyleFriendReactionSummary?
    let select: (StyleFriendReactionKind?) -> Void
    @State private var isReactionPickerPresented = false

    var body: some View {
        Group {
            if let summary {
                HStack(spacing: 8) {
                    quickReactionButton(summary: summary)
                    StyleFriendReactionSummaryView(summary: summary)
                }
                .font(.caption)
                .popover(isPresented: $isReactionPickerPresented, arrowEdge: .bottom) {
                    StyleFriendReactionPicker(selected: summary.viewerReaction) { reaction in
                        select(reaction)
                        isReactionPickerPresented = false
                    }
                }
            }
        }
    }

    private func quickReactionButton(summary: StyleFriendReactionSummary) -> some View {
        let kind = summary.viewerReaction ?? .like
        let selected = summary.viewerReaction == kind
        return Button { select(kind) } label: {
                Text(kind.emoji)
                .font(.subheadline)
                .scaleEffect(selected ? 1.08 : 1)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
        }
        .buttonStyle(.bordered)
        .tint(selected ? .purple : .secondary)
        .animation(.easeOut(duration: 0.16), value: selected)
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.35).onEnded { _ in isReactionPickerPresented = true })
        .accessibilityLabel("\(kind.displayName) reaction, \(summary.count(for: kind)) reactions")
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityHint("Double tap for a quick Like. Touch and hold to choose a reaction.")
    }

}

private struct StyleFriendReactionPicker: View {
    let selected: StyleFriendReactionKind?
    let onSelect: (StyleFriendReactionKind?) -> Void

    var body: some View {
        HStack(spacing: 14) {
            ForEach(StyleFriendReactionKind.allCases, id: \.self) { reaction in
                Button {
                    onSelect(selected == reaction ? nil : reaction)
                } label: {
                    Text(reaction.emoji)
                        .font(.title2)
                        .scaleEffect(selected == reaction ? 1.18 : 1.0)
                }
                .buttonStyle(.plain)
                .animation(.easeOut(duration: 0.16), value: selected == reaction)
                .accessibilityLabel(reaction.displayName)
                .accessibilityAddTraits(selected == reaction ? .isSelected : [])
                .accessibilityHint(selected == reaction ? "Double tap to remove your reaction" : "Double tap to select")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

private struct StyleFriendReactionSummaryView: View {
    let summary: StyleFriendReactionSummary

    private var visibleReactions: [StyleFriendReactionKind] {
        StyleFriendReactionKind.allCases
            .filter { summary.count(for: $0) > 0 }
            .sorted { summary.count(for: $0) > summary.count(for: $1) }
            .prefix(3)
            .map { $0 }
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(visibleReactions, id: \.self) { reaction in
                HStack(spacing: 3) {
                    Text(reaction.emoji)
                    Text("\(summary.count(for: reaction))")
                        .font(.caption)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(reaction.displayName), \(summary.count(for: reaction)) reactions")
            }
        }
    }
}

private struct StyleFriendsReportSheet: View {
    let title: String
    let submit: (StyleFriendsReportDraft) async throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var category: StyleFriendsReportCategory = .other
    @State private var detail = ""
    @State private var feedback: String?
    @State private var isSubmitting = false
    private var normalizedDetail: String { detail.trimmingCharacters(in: .whitespacesAndNewlines) }
    var body: some View {
        NavigationStack {
            Form {
                Picker("Reason", selection: $category) { ForEach(StyleFriendsReportCategory.allCases, id: \.self) { Text($0.rawValue.replacingOccurrences(of: "_", with: " ").capitalized).tag($0) } }
                TextField("Details (optional)", text: $detail, axis: .vertical).lineLimit(3...5)
                Text("Reports are reviewed under KigoStylist moderation policy. Do not include private account information.").font(.footnote).foregroundStyle(.secondary)
                if let feedback { Text(feedback).foregroundStyle(.secondary) }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Submit") { Task { await send() } }.disabled(isSubmitting || normalizedDetail.utf16.count > StyleFriendsReportDraft.maximumDetailUTF16) }
            }
        }
    }
    @MainActor private func send() async {
        isSubmitting = true; defer { isSubmitting = false }
        do { try await submit(StyleFriendsReportDraft(category: category, detail: normalizedDetail.isEmpty ? nil : normalizedDetail)); dismiss() }
        catch { feedback = StyleFriendsServiceError.unavailable.errorDescription }
    }
}

private struct StyleFriendProfileSheet: View {
    let person: StyleFriendListItem
    let service: StyleFriendsService
    let openConversation: () async -> Bool
    let performRelationship: (StyleFriendRelationshipOperation) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var profile: StyleFriendVisibleProfile?
    @State private var isLoading = true
    @State private var isBioExpanded = false
    #if DEBUG
    @State private var profileFetchDebug: String?
    #endif

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading Style Friend Profile…")
                } else if let profile {
                    ScrollView {
                      VStack(alignment: .leading, spacing: 22) {
                        VStack(alignment: .leading, spacing: 16) {
                            StyleFriendsPublicAvatar(reference: profile.avatarReference, displayName: profile.displayName, service: service, size: 84)
                            Text(profile.displayName)
                                .font(.system(.largeTitle, design: .serif, weight: .semibold))
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Part of your style circle")
                                .font(.subheadline)
                                .foregroundStyle(KigoStyleFriendsPalette.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(24)
                        .background(LinearGradient(colors: [KigoStyleFriendsPalette.soft, KigoStyleFriendsPalette.surface], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 28))
                        .overlay(RoundedRectangle(cornerRadius: 28).stroke(KigoStyleFriendsPalette.border))
                        if let bio = profile.styleBio, !bio.isEmpty {
                            StyleFriendExpandableBio(bio: bio, isExpanded: $isBioExpanded)
                        }
                        if !profile.styleCategories.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack { ForEach(profile.styleCategories, id: \.self) { category in
                                    Text(category.displayName).font(.caption.weight(.semibold))
                                        .padding(.horizontal, 14).padding(.vertical, 9)
                                        .foregroundStyle(KigoStyleFriendsPalette.accent)
                                        .background(KigoStyleFriendsPalette.soft, in: Capsule())
                                } }
                            }
                        }
                        Button {
                            Task {
                                if await openConversation() {
                                    dismiss()
                                }
                            }
                        } label: {
                            Label("Message", systemImage: "bubble.left.and.bubble.right")
                                .font(.headline)
                                .frame(maxWidth: .infinity, minHeight: 52)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(KigoStyleFriendsPalette.button)
                        .accessibilityHint("Opens the existing private conversation with \(profile.displayName).")
                        Divider()
                        HStack {
                            Button("Remove Friend", role: .destructive) { Task { try? await performRelationship(.remove); dismiss() } }
                            Button("Block", role: .destructive) { Task { try? await performRelationship(.block); dismiss() } }
                        }
                        .buttonStyle(.bordered)
                      }
                      .frame(maxWidth: 680, alignment: .leading)
                      .frame(maxWidth: .infinity)
                    }
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "person.crop.circle.badge.questionmark").font(.largeTitle).foregroundStyle(.secondary)
                        Text("Profile unavailable").font(.headline)
                        Text("Only an accepted friend’s social profile can be shown. Private KigoStylist Profile, Closet, AI Memory, account, and location data are never included.")
                            .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        #if DEBUG
                        if let profileFetchDebug {
                            Text("Profile diagnostics: \(profileFetchDebug)")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .accessibilityLabel("Style Friends profile request diagnostics available")
                        }
                        #endif
                    }
                }
            }
            .padding()
            .background(KigoStyleFriendsPalette.page.ignoresSafeArea())
            .tint(KigoStyleFriendsPalette.accent)
            .navigationTitle("Style Friend Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
        .task {
            let receipt = await service.socialProfileReceipt(for: person.socialReference)
            profile = receipt.profile
            #if DEBUG
            profileFetchDebug = receipt.diagnostic ?? receipt.httpStatus.map { "http=\($0)" }
            #endif
            isLoading = false
        }
    }
}

/// Choosing Friends only presents this review; publish is an explicit second action.
struct StyleFriendsPublishReview: View {
    let card: CreatedShareableScoreCard
    let publish: (SharedOutfitPostDraft) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var caption = ""
    @State private var occasion = ""
    @State private var feedback: String?
    @State private var isPublishing = false

    private var isWithinBounds: Bool {
        title.utf16.count <= SharedOutfitPostDraft.maximumTitleUTF16 && caption.utf16.count <= SharedOutfitPostDraft.maximumCaptionUTF16
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Review Shared Look") {
                    Label("Approved shared-card representation", systemImage: "checkmark.seal.fill")
                    Text("Only the already-approved card is attached. This does not attach the private scan, Closet, Profile, AI Memory, CloudKit record, or a reusable share token.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let score = card.overallScore {
                        Label("KigoStylist score \(score)/100", systemImage: "checkmark.seal")
                    } else {
                        Text("KigoStylist score was not included in this approved card.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("Friends-only post") {
                    TextField("Title (optional)", text: $title)
                    TextField("Caption (optional)", text: $caption, axis: .vertical).lineLimit(3...5)
                    TextField("Occasion (optional)", text: $occasion)
                    Label("Audience: Friends", systemImage: "person.2.fill")
                }
                if let feedback { Section { Text(feedback).foregroundStyle(.secondary) } }
            }
            .navigationTitle("Review Shared Look")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Publish") { Task { await submit() } }.disabled(!isWithinBounds || isPublishing)
                }
            }
        }
    }

    @MainActor private func submit() async {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCaption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedOccasion = occasion.trimmingCharacters(in: .whitespacesAndNewlines)
        isPublishing = true; defer { isPublishing = false }
        do {
            try await publish(SharedOutfitPostDraft(cardToken: card.token, title: normalizedTitle.isEmpty ? nil : normalizedTitle, caption: normalizedCaption.isEmpty ? nil : normalizedCaption, occasion: normalizedOccasion.isEmpty ? nil : normalizedOccasion))
            dismiss()
        } catch {
            feedback = StyleFriendsServiceError.unavailable.errorDescription
        }
    }
}

private struct StyleFriendsPostDetailsSheet: View {
    let post: SharedOutfitPost
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Shared Look") {
                    Text(post.title ?? "Shared Look").font(.headline)
                    if let score = post.score { Label("KigoStylist score \(score)/100", systemImage: "checkmark.seal") }
                    if let caption = post.caption, !caption.isEmpty { Text(caption) }
                    if let occasion = post.occasion, !occasion.isEmpty { Label(occasion, systemImage: "calendar") }
                    Text(post.availability == .active ? "Available to Friends" : "Unavailable after share revocation").foregroundStyle(.secondary)
                }
                Section { Text("This is a bounded social projection. It does not reveal the source scan, private Closet, Profile, AI Memory, account, or share token.").font(.footnote).foregroundStyle(.secondary) }
            }
            .navigationTitle("Shared Look")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}

private enum SocialProfileField: Hashable { case displayName, bio }

private enum StyleFriendsProfileSaveState: Equatable {
    case unchanged, ready, saving, success, failure(String)

    var message: String? {
        switch self {
        case .unchanged, .ready: nil
        case .saving: "Saving your public Style Friends profile…"
        case .success: "Social profile saved."
        case let .failure(message): message
        }
    }

    var isFailure: Bool {
        if case .failure = self { return true }
        return false
    }
}

private enum StyleFriendsProfileLoadState: Equatable {
    case loading, established, missing, unavailable
}

private struct SocialProfileDraft: Equatable {
    var displayName = ""
    var styleBio = ""
    var avatarReference = ""
    var categories = Set<StyleFriendStyleCategory>()
    var isDiscoverable = false

    var isWithinBounds: Bool {
        displayName.utf16.count <= StyleFriendProfileUpdate.maximumDisplayNameUTF16
            && styleBio.utf16.count <= StyleFriendProfileUpdate.maximumStyleBioUTF16
            && styleBioWordCount <= StyleFriendProfileUpdate.maximumStyleBioWords
            && categories.count <= StyleFriendProfileUpdate.maximumStyleCategories
    }

    var styleBioWordCount: Int {
        styleBio.split(whereSeparator: { $0.isWhitespace }).count
    }

    var isValid: Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && isWithinBounds
    }

    var initials: String {
        let words = displayName.split(whereSeparator: { $0.isWhitespace })
        let initials = words.prefix(2).compactMap { $0.first }.map(String.init).joined()
        return initials.isEmpty ? "S" : initials.uppercased()
    }

    init() {}
    init(profile: StyleFriendVisibleProfile) { displayName = profile.displayName; styleBio = profile.styleBio ?? ""; avatarReference = profile.avatarReference ?? ""; categories = Set(profile.styleCategories); isDiscoverable = profile.isDiscoverable ?? false }
    var update: StyleFriendProfileUpdate? {
        guard isValid else { return nil }
        let normalizedBio = styleBio.trimmingCharacters(in: .whitespacesAndNewlines)
        return StyleFriendProfileUpdate(
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            avatarReference: avatarReference.isEmpty ? nil : avatarReference,
            styleBio: normalizedBio.isEmpty ? nil : normalizedBio,
            styleCategories: categories.sorted { $0.rawValue < $1.rawValue },
            isDiscoverable: isDiscoverable
        )
    }

}

/// Discovery and profile cards must not expand to a multi-screen biography.
/// The complete, line-break-preserving public bio remains available on the
/// authenticated friend profile after an explicit owner action.
private struct StyleFriendExpandableBio: View {
    let bio: String
    @Binding var isExpanded: Bool

    private var canExpand: Bool { bio.utf16.count > 380 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(bio)
                .font(.body)
                .fixedSize(horizontal: false, vertical: isExpanded)
                .lineLimit(isExpanded ? nil : 6)
            if canExpand {
                Button(isExpanded ? "Show less" : "Read full bio") {
                    isExpanded.toggle()
                }
                .font(.subheadline.weight(.semibold))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private extension StyleFriendStyleCategory {
    var displayName: String {
        switch self {
        case .smartCasual: "Smart casual"
        default: rawValue.capitalized
        }
    }
}
