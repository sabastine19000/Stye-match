import AuthenticationServices
import PhotosUI
import SwiftUI

import UIKit

/// Opens an authenticated DM notification directly at its conversation.
/// The notification contains only opaque routing hints. StyleMatch re-loads the
/// conversation from the authenticated service before showing any content.
struct StyleFriendsNotificationMessageHost: View {
    @Environment(\.dismiss) private var dismiss
    let route: StyleFriendsNotificationRoute
    private let binding: StyleFriendsDMRuntimeBinding
    @State private var resolvedConversation: StyleFriendsConversationPresentation?
    @State private var isLoading = true
    @State private var failure: StyleFriendsDMError?

    init(
        route: StyleFriendsNotificationRoute,
        binding: StyleFriendsDMRuntimeBinding = .current()
    ) {
        self.route = route
        self.binding = binding
    }

    var body: some View {
        NavigationStack {
            Group {
                if let resolvedConversation {
                    StyleFriendsLiveChatView(
                        conversation: resolvedConversation,
                        directMessages: binding.service,
                        initialMessageReference: route.messageReference
                    )
                } else if isLoading {
                    ProgressView("Opening message…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if failure == .signInRequired {
                    ChatUnavailableState(
                        icon: "person.crop.circle.badge.exclamationmark",
                        title: StyleMatchSessionRecoveryCopy.title,
                        detail: StyleMatchSessionRecoveryCopy.detail(for: "Style Friends")
                    )
                } else {
                    ChatUnavailableState(
                        icon: "bubble.left.and.exclamationmark.bubble.right",
                        title: "Message unavailable",
                        detail: "KigoStylist could not open this notification. The conversation may have changed or no longer be available."
                    )
                }
            }
            .appScreenBackground(.profile)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task(id: route.id) {
            await resolveNotificationDestination()
        }
    }

    @MainActor
    private func resolveNotificationDestination() async {
        guard route.isDirectMessageRoute,
              let target = route.conversationReference else {
            isLoading = false
            failure = .invalidResponse
            return
        }
        guard binding.presentationState == .loading else {
            isLoading = false
            failure = binding.readiness.failure ?? .dmUnavailable
            return
        }

        isLoading = true
        failure = nil
        var cursor: String?
        var seen = Set<String>()
        do {
            repeat {
                let page = try await binding.service.conversations(cursor: cursor)
                if let match = page.items.first(where: { $0.conversationReference == target }) {
                    resolvedConversation = StyleFriendsDMPresentationMapper.conversation(match)
                    isLoading = false
                    return
                }
                guard let next = page.nextCursor, seen.insert(next).inserted else { break }
                cursor = next
            } while true
            failure = .invalidResponse
        } catch let error as StyleFriendsDMError {
            failure = error
        } catch {
            failure = .invalidResponse
        }
        isLoading = false
    }
}

/// Build 18039 human-to-human chat presentation. It deliberately has no
/// AI-chat, CloudKit, Profile, Closet, Scan History, or AI Memory dependency.
/// The only live source is the authenticated, exact-host Worker service.
struct StyleFriendsLiveConversationsView: View {
    private let binding: StyleFriendsDMRuntimeBinding
    let onFindStyleFriends: (() -> Void)?
    let onOpenProfile: (() -> Void)?
    @StateObject private var controller: StyleFriendsDMChatActionController

    init(binding: StyleFriendsDMRuntimeBinding = .current(), onFindStyleFriends: (() -> Void)? = nil, onOpenProfile: (() -> Void)? = nil) {
        self.binding = binding
        self.onFindStyleFriends = onFindStyleFriends
        self.onOpenProfile = onOpenProfile
        _controller = StateObject(wrappedValue: StyleFriendsDMChatActionController(service: binding.service))
    }

    var body: some View {
        StyleFriendsConversationsView(
            state: presentationState,
            conversations: controller.conversations.map(StyleFriendsDMPresentationMapper.conversation),
            directMessages: binding.service,
            unavailableTitle: failurePresentation?.title ?? binding.unavailableTitle,
            unavailableDetail: failurePresentation?.detail ?? binding.unavailableDetail,
            errorTitle: failurePresentation?.title ?? "Conversations temporarily unavailable",
            errorDetail: failurePresentation?.detail ?? "The Style Friends service is temporarily unavailable. Try again later.",
            onFindStyleFriends: onFindStyleFriends,
            onOpenProfile: onOpenProfile
        )
        .task {
            guard binding.presentationState == .loading else { return }
            // Conversation visibility must not wait behind recovery of older
            // unfinished sends. Start both together, render the authoritative
            // conversation list as soon as it returns, then let status-only
            // recovery finish without holding the loading screen open.
            async let recovery = StyleFriendsDMOperationRecoveryCoordinator.shared.reconcileCurrentAuthenticatedSession(service: binding.service)
            await controller.loadConversations()
            _ = await recovery
        }
    }

    private var presentationState: StyleFriendsConversationPresentationState {
        guard binding.presentationState == .loading else { return binding.presentationState }
        if controller.loadingConversations { return .loading }
        if controller.lastError == .signInRequired { return .authorizationUnavailable }
        if controller.lastError != nil { return .recoverableError }
        return controller.conversations.isEmpty ? .empty : .populated
    }

    private var failurePresentation: StyleFriendsDMConversationFailurePresentation? {
        controller.lastError.map(StyleFriendsDMConversationFailurePresentation.resolve)
    }
}

/// Rebuilds the live binding after an account session changes. This is not a
/// local-login shortcut: the Apple exchange remains the sole session authority.
struct StyleFriendsLiveConversationsHost: View {
    let onFindStyleFriends: (() -> Void)?
    let onOpenProfile: (() -> Void)?
    @State private var sessionGeneration = UUID()

    init(onFindStyleFriends: (() -> Void)? = nil, onOpenProfile: (() -> Void)? = nil) {
        self.onFindStyleFriends = onFindStyleFriends
        self.onOpenProfile = onOpenProfile
    }

    var body: some View {
        StyleFriendsLiveConversationsView(onFindStyleFriends: onFindStyleFriends, onOpenProfile: onOpenProfile)
            .id(sessionGeneration)
            .onReceive(NotificationCenter.default.publisher(for: StyleMatchAccountSessionStore.didChangeNotification)) { _ in
                StyleFriendsDMSessionMessageCache.clearAll()
                sessionGeneration = UUID()
            }
    }
}

struct StyleFriendsConversationsView: View {
    let state: StyleFriendsConversationPresentationState
    let conversations: [StyleFriendsConversationPresentation]
    let directMessages: any StyleFriendsDirectMessageServing
    let unavailableTitle: String
    let unavailableDetail: String
    let errorTitle: String
    let errorDetail: String
    let onFindStyleFriends: (() -> Void)?
    let onOpenProfile: (() -> Void)?

    init(
        state: StyleFriendsConversationPresentationState,
        conversations: [StyleFriendsConversationPresentation],
        directMessages: any StyleFriendsDirectMessageServing = StyleFriendsUnavailableDirectMessageService(),
        unavailableTitle: String = "Messaging is not available yet",
        unavailableDetail: String = "Direct messages stay unavailable until the authorized Style Friends service is connected.",
        errorTitle: String = "Conversations temporarily unavailable",
        errorDetail: String = "The Style Friends service is temporarily unavailable. Try again later.",
        onFindStyleFriends: (() -> Void)? = nil,
        onOpenProfile: (() -> Void)? = nil
    ) {
        self.state = state
        self.conversations = conversations
        self.directMessages = directMessages
        self.unavailableTitle = unavailableTitle
        self.unavailableDetail = unavailableDetail
        self.errorTitle = errorTitle
        self.errorDetail = errorDetail
        self.onFindStyleFriends = onFindStyleFriends
        self.onOpenProfile = onOpenProfile
    }

    var body: some View {
        Group {
            switch state {
            case .loading: ProgressView("Loading conversations…").frame(maxWidth: .infinity, minHeight: 220)
            case .empty:
                ScrollView {
                    StyleFriendsConversationEmptyStateView(onFindStyleFriends: onFindStyleFriends)
                        .padding(.top, 28)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 32)
                        .frame(maxWidth: 680)
                        .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
            case .populated:
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        StyleFriendsInboxHeading()
                        ForEach(conversations) { conversation in
                            NavigationLink { StyleFriendsLiveChatView(conversation: conversation, directMessages: directMessages) } label: { StyleFriendsConversationRow(conversation: conversation) }.buttonStyle(.plain)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                }
            case .recoverableError: ChatUnavailableState(icon: "wifi.exclamationmark", title: errorTitle, detail: errorDetail)
            case .authorizationUnavailable:
                VStack(spacing: 16) {
                    ChatUnavailableState(
                        icon: "lock.slash",
                        title: StyleMatchSessionRecoveryCopy.title,
                        detail: StyleMatchSessionRecoveryCopy.detail(for: "Style Friends")
                    )
                    if allowsAccountRecovery {
                        StyleFriendsAccountRecoveryView(onOpenProfile: requestProfileReconnect)
                    }
                }
            }
        }
        .appScreenBackground(.profile)
        .navigationTitle("Conversations")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var allowsAccountRecovery: Bool {
        unavailableTitle == "Sign in to Style Friends" || unavailableTitle == "Your Style Friends session expired"
    }

    private func requestProfileReconnect() {
        if let onOpenProfile {
            onOpenProfile()
        } else {
            NotificationCenter.default.post(name: StyleMatchAccountSessionStore.profileReconnectRequestedNotification, object: nil)
        }
    }
}

private struct StyleFriendsConversationEmptyStateView: View {
    let onFindStyleFriends: (() -> Void)?

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 16) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
                    .frame(width: 72, height: 72)
                    .background(Color.accentColor.opacity(0.12), in: Circle())

                VStack(spacing: 8) {
                    Text("No conversations yet")
                        .font(.title2.weight(.bold))
                        .multilineTextAlignment(.center)
                    Text("Start a conversation with a Style Friend and talk about looks, outfits, and style.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let onFindStyleFriends {
                    Button(action: onFindStyleFriends) {
                        Label("Find Style Friends", systemImage: "person.2.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityHint("Opens the existing Style Friends discovery screen.")
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .appCard(.profile, radius: 24)
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.24), lineWidth: 1)
            }

            DisclosureGroup {
                Text("KigoStylist uses the current authorized relationship, block, and moderation rules whenever a conversation is opened. Notifications use generic previews and never grant access to a chat.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            } label: {
                Label("Your conversations are private", systemImage: "lock.fill")
                    .font(.subheadline.weight(.semibold))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .accessibilityElement(children: .contain)
    }
}

private struct StyleFriendsAccountRecoveryView: View {
    let onOpenProfile: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Label(StyleMatchSessionRecoveryCopy.title, systemImage: "person.crop.circle.badge.exclamationmark")
                .font(.headline)
            Text(StyleMatchSessionRecoveryCopy.detail(for: "Style Friends"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(StyleMatchSessionRecoveryCopy.actionTitle, action: onOpenProfile)
                .buttonStyle(.borderedProminent)
                .accessibilityHint("Opens Profile to reconnect your KigoStylist session.")
        }
        .padding(.horizontal)
    }
}

struct StyleFriendsLiveChatView: View {
    @Environment(\.scenePhase) private var scenePhase
    let conversation: StyleFriendsConversationPresentation
    let directMessages: any StyleFriendsDirectMessageServing
    private let publicProfileService: StyleFriendsService
    private let initialMessageReference: StyleFriendsOpaqueRouteReference?
    @StateObject private var controller: StyleFriendsDMChatActionController
    @State private var refreshedConversation: StyleFriendsConversationPresentation?
    @State private var refreshGeneration = 0
    @State private var refreshInFlight = false

    init(
        conversation: StyleFriendsConversationPresentation,
        directMessages: any StyleFriendsDirectMessageServing,
        publicProfileService: StyleFriendsService = .init(),
        initialMessageReference: StyleFriendsOpaqueRouteReference? = nil
    ) {
        self.conversation = conversation
        self.directMessages = directMessages
        self.publicProfileService = publicProfileService
        self.initialMessageReference = initialMessageReference
        _controller = StateObject(wrappedValue: StyleFriendsDMChatActionController(service: directMessages))
    }

    var body: some View {
        FriendChatView(
            conversation: activeConversation,
            state: presentationState,
            messages: controller.messages.map {
                StyleFriendsDMPresentationMapper.message(
                    $0,
                    selfDisplayName: "You",
                    friendDisplayName: activeConversation.friendDisplayName
                )
            },
            directMessages: directMessages,
            onOperationCompleted: refresh,
            initialMessageReference: initialMessageReference
        )
        .task(id: conversation.conversationReference.value) { await refreshLoop() }
        .onChange(of: conversation) { _ in
            // The list projection is server-authoritative.  Never allow this
            // detail view's earlier navigation snapshot to keep an old public
            // display name after the list has been rehydrated.
            refreshedConversation = nil
            Task { await refresh() }
        }
    }

    private var presentationState: StyleFriendsConversationPresentationState {
        if controller.loadingMessages && controller.messages.isEmpty { return .loading }
        if controller.lastError != nil && controller.messages.isEmpty { return .recoverableError }
        return controller.messages.isEmpty ? .empty : .populated
    }

    private var activeConversation: StyleFriendsConversationPresentation {
        refreshedConversation ?? conversation
    }

    private func refresh() async {
        guard !refreshInFlight else { return }
        refreshInFlight = true
        defer { refreshInFlight = false }
        refreshGeneration &+= 1
        let generation = refreshGeneration
        await controller.loadMessages(conversation: conversation.conversationReference)
        await controller.loadConversations()
        guard generation == refreshGeneration else { return }
        if let current = controller.conversations.first(where: { $0.conversationReference == conversation.conversationReference }) {
            // `friend_display_name` is the Worker-projected public Style
            // Friends profile value, not relationship or message metadata.
            var projection = StyleFriendsDMPresentationMapper.conversation(current)
            if let friend = current.friendSocialReference,
               let profile = try? await publicProfileService.socialProfile(for: friend),
               generation == refreshGeneration {
                // The authenticated friends-only profile is the final identity
                // authority when a historical conversation/list projection is
                // stale. It never reads the private StyleMatch profile.
                projection = .init(
                    conversationReference: projection.conversationReference,
                    friendSocialReference: projection.friendSocialReference,
                    friendDisplayName: profile.displayName,
                    avatarReference: profile.avatarReference,
                    lastMessagePreview: projection.lastMessagePreview,
                    lastActivity: projection.lastActivity
                )
            }
            guard generation == refreshGeneration else { return }
            refreshedConversation = projection
        }
        if let latest = controller.messages.last {
            _ = await controller.markRead(
                conversation: conversation.conversationReference,
                lastReadMessage: latest.messageReference
            )
        }
    }

    private func refreshLoop() async {
        await refresh()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled, scenePhase == .active else { continue }
            await refresh()
        }
    }
}

struct StyleFriendsInboxHeading: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("YOUR STYLE CIRCLE")
                .font(.caption.weight(.bold))
                .tracking(1.6)
                .foregroundStyle(.secondary)
            Text("A little conversation.\nA lot of inspiration.")
                .font(.system(.title, design: .serif, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text("Your looks, photos and shared scores, all in the conversation.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 12)
    }
}

struct StyleFriendsConversationRow: View {
    let conversation: StyleFriendsConversationPresentation
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            StyleFriendsChatAvatar(label: conversation.friendDisplayName, size: 52)
            VStack(alignment: .leading, spacing: 7) {
                Text(conversation.friendDisplayName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(conversation.lastMessagePreview ?? "No messages yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let date = conversation.lastActivity {
                    Text(date, style: .time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Last activity \(date.formatted(date: .abbreviated, time: .shortened))")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.top, 4)
                .accessibilityHidden(true)
        }
        .padding(18)
        .frame(minHeight: 88)
        .appCard(.profile, radius: 24)
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(KigoStyleFriendsPalette.border))
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Conversation with \(conversation.friendDisplayName)")
    }
}

/// Privacy-safe lifecycle instrumentation. Implementations receive fixed phase
/// names and sanitized outcome metadata only; no request or user data crosses
/// this boundary.
protocol StyleFriendsPhotoSendPhaseObserving {
    func photoSendPhase(_ phase: StyleFriendsPhotoSendPhase, outcome: StyleFriendsPhotoSendOutcome?)
}

enum StyleFriendsPhotoSendPhase: String, Sendable { case photo_send_started, authorization_started, authorization_succeeded, authorization_failed, message_started, message_succeeded, message_failed, preparation_started, preparation_succeeded, preparation_failed, upload_started, upload_succeeded, upload_failed, association_started, association_succeeded, association_failed, reconciliation_started, reconciliation_succeeded, reconciliation_failed, reconciliation_ambiguous, photo_send_completed }
enum StyleFriendsPhotoSendOutcome: Equatable, Sendable { case category(String, httpStatus: Int?, retryable: Bool, operationPhase: String) }

#if OWNER_BETA
/// Read-only projection of the existing redacted trace; no service or journal access.
private struct StyleFriendsOwnerBetaOperationSummary: View {
    @Environment(\.dismiss) private var dismiss
    let snapshot: StyleFriendsDMOperationDiagnostics.Snapshot
    let recovery: StyleFriendsDMRecoveryDiagnosticSnapshot

    var body: some View {
        NavigationStack {
            List {
                summaryRow("Build", Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? snapshot.build)
                Section("Current conversation recovery") {
                    summaryRow("Diagnostic revision", "9")
                    summaryRow("Read status", recovery.availability.rawValue)
                    if recovery.availability == .available {
                        summaryRow("Pending operations", String(recovery.pendingCount))
                        summaryRow("Past local expiry", String(recovery.expiredCount))
                        summaryRow("Oldest pending age", recovery.oldestAge.rawValue)
                        summaryRow("Text operations", String(recovery.textCount))
                        summaryRow("Prepared attachments", String(recovery.preparedAttachmentCount))
                        summaryRow("With server reference", String(recovery.serverReferenceCount))
                        summaryRow("Local phases", recovery.phaseCounts.isEmpty ? "None" : recovery.phaseCounts.keys.sorted().map { "\($0): \(recovery.phaseCounts[$0] ?? 0)" }.joined(separator: ", "))
                    }
                }
                Section("Last transport response") {
                    summaryRow("Operation type", snapshot.operation)
                    summaryRow("Phase", snapshot.phase)
                    summaryRow("HTTP status", snapshot.httpStatus)
                    summaryRow("Category", snapshot.serverCategory)
                    summaryRow("Reconciliation", snapshot.reconciliation)
                }
            }
            .navigationTitle("Operation summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(verbatim: value).font(.body.monospaced()).textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }
}
#endif

struct FriendChatView: View {
    let conversation: StyleFriendsConversationPresentation
    let state: StyleFriendsConversationPresentationState
    let messages: [StyleFriendsFriendMessagePresentation]
    let directMessages: any StyleFriendsDirectMessageServing
    let onOperationCompleted: (() async -> Void)?
    let phaseObserver: (any StyleFriendsPhotoSendPhaseObserving)?
    let initialMessageReference: StyleFriendsOpaqueRouteReference?
    @StateObject private var attachmentCoordinator: StyleFriendsAttachmentSendCoordinator
    @State private var draft = ""
    @State private var replyTarget: StyleFriendsFriendMessagePresentation?
    @State private var pickerTarget: StyleFriendsFriendMessagePresentation?
    @StateObject private var termsGate = StyleFriendsDMFirstSendTermsGate()
    @State private var showingTerms = false
    @State private var showingBlockConfirmation = false
    #if OWNER_BETA
    @State private var showingOperationSummary = false
    @State private var operationSummary = StyleFriendsDMOperationDiagnostics.Snapshot()
    @State private var recoveryDiagnostic = StyleFriendsDMRecoveryDiagnosticSnapshot()
    #endif
    @State private var actionError: String?
    @State private var isSending = false
    @State private var failedSend: StyleFriendsDMFailedDeliveryOperation?
    @State private var recoveryPending = true
    @State private var isCheckingRecovery = false
    @State private var stoppableAttachmentIDs: [UUID] = []
    @State private var recoveryAccountSession: StyleMatchAccountSession?
    @State private var showingStopWaiting = false
    @State private var stoppedWaiting = false
    @State private var recoveryFeedback = "A previous send has not been confirmed. Check its delivery status before sending again."
    @State private var selectedAttachmentPhoto: PhotosPickerItem?
    @State private var pendingAttachmentPhoto: Data?
    @State private var pendingShare: StyleFriendsDMPreparedShare?
    private struct SharePickerRequest: Identifiable {
        let id = UUID()
        let choices: [StyleFriendsDMShareEligibilityAuthority.Selection]
    }
    @State private var sharePickerRequest: SharePickerRequest?
    @State private var shareAuthority = StyleFriendsDMShareEligibilityAuthority()
    @State private var attachmentError: String?
    @FocusState private var composerFocused: Bool

    init(
        conversation: StyleFriendsConversationPresentation,
        state: StyleFriendsConversationPresentationState,
        messages: [StyleFriendsFriendMessagePresentation],
        directMessages: any StyleFriendsDirectMessageServing = StyleFriendsUnavailableDirectMessageService(),
        onOperationCompleted: (() async -> Void)? = nil,
        phaseObserver: (any StyleFriendsPhotoSendPhaseObserving)? = nil,
        initialMessageReference: StyleFriendsOpaqueRouteReference? = nil
    ) {
        self.conversation = conversation
        self.state = state
        self.messages = messages
        self.directMessages = directMessages
        self.onOperationCompleted = onOperationCompleted
        self.phaseObserver = phaseObserver
        self.initialMessageReference = initialMessageReference
        _attachmentCoordinator = StateObject(wrappedValue: StyleFriendsAttachmentSendCoordinator(service: directMessages, conversation: conversation.conversationReference, phaseObserver: { [phaseObserver] marker in
            guard let phase = StyleFriendsPhotoSendPhase(rawValue: marker) else { return }
            phaseObserver?.photoSendPhase(phase, outcome: nil)
        }))
    }

    var body: some View {
        chatContent
        .appScreenBackground(.profile)
        .navigationTitle(conversation.friendDisplayName)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
            if recoveryPending {
                Button("Check unresolved delivery status") { composerFocused = false; Task { await reconcileUnresolvedOperations() } }
                    .disabled(isSending || isCheckingRecovery)
                if isCheckingRecovery {
                    ProgressView("Checking delivery…")
                } else {
                    Text(recoveryFeedback)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            if recoveryPending && !stoppableAttachmentIDs.isEmpty {
                Button("Stop waiting for old attachment…") { composerFocused = false; showingStopWaiting = true }
                    .disabled(isSending || isCheckingRecovery)
            }
            if stoppedWaiting && !recoveryPending {
                Text("The old attachment is still unconfirmed. Review your draft before sending a new message.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal)
            }
            FriendChatComposer(
                draft: $draft,
                replyTarget: $replyTarget,
                isFocused: $composerFocused,
                isSending: isSending,
                isAvailable: composerIsAvailable,
                hasFailedSend: failedSend != nil || recoveryPending,
                attachmentsAvailable: StyleFriendsDMAttachmentRuntimeAuthority.isAuthorized,
                selectedAttachmentPhoto: $selectedAttachmentPhoto,
                pendingAttachmentPhoto: pendingAttachmentPhoto,
                pendingShare: pendingShare,
                onRemoveAttachment: { pendingAttachmentPhoto = nil; selectedAttachmentPhoto = nil },
                onChooseShare: presentSavedShareChoices,
                onRemoveShare: { pendingShare = nil },
                onSend: requestFirstSendAuthorization
            )
            }
            .frame(maxWidth: .infinity)
            .background(Color(uiColor: .secondarySystemBackground))
        }
        .toolbar { ToolbarItem(placement: .principal) { HStack(spacing: 8) { StyleFriendsChatAvatar(label: conversation.friendDisplayName, size: 30); VStack(alignment: .leading, spacing: 1) { Text(conversation.friendDisplayName).font(.headline).lineLimit(1).minimumScaleFactor(0.82); Text("Style Friend").font(.caption2.weight(.medium)).foregroundStyle(.secondary) } }.accessibilityLabel("Chat with \(conversation.friendDisplayName), Style Friend") }; ToolbarItem(placement: .topBarTrailing) { Menu {
            #if OWNER_BETA
            Button("Operation summary") {
                composerFocused = false
                operationSummary = StyleFriendsDMOperationDiagnostics.snapshot
                showingOperationSummary = true
            }
            #endif
            if conversation.friendSocialReference != nil { Button("Block", role: .destructive) { showingBlockConfirmation = true }.accessibilityLabel("Block Style Friend") }
        } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("Conversation options") } }
        #if OWNER_BETA
        .sheet(isPresented: $showingOperationSummary) { StyleFriendsOwnerBetaOperationSummary(snapshot: operationSummary, recovery: recoveryDiagnostic) }
        #endif
        .sheet(item: $pickerTarget) { message in FriendReactionPicker(selected: message.reactionSummary?.viewerReaction, onSelect: { reaction in Task { await setReaction(reaction, message: message) } }) }
        .sheet(isPresented: $showingTerms) { FriendChatTermsSheet(gate: termsGate, service: directMessages) }
        .sheet(item: $sharePickerRequest) { request in
            StyleFriendsSavedScanPicker(choices: request.choices) { selection in
                guard let snapshot = shareAuthority.consumeSnapshot(for: selection.id, kind: selection.kind) else { return }
                pendingShare = .init(
                    kind: attachmentKind(for: selection.kind),
                    snapshot: snapshot,
                    imagePreview: selection.imagePreview,
                    clientShareReference: UUID().uuidString.replacingOccurrences(of: "-", with: "")
                )
                pendingAttachmentPhoto = nil
                selectedAttachmentPhoto = nil
                sharePickerRequest = nil
            }
        }
        .confirmationDialog("Stop waiting for the old attachment?", isPresented: $showingStopWaiting, titleVisibility: .visible) {
            Button("Stop waiting") { stopWaitingForUnknownAttachments() }
            Button("Keep waiting", role: .cancel) {}
        } message: {
            Text("We still cannot confirm its delivery. This saves the recovery record and stops this app from retrying the old attachment. It does not cancel anything already sent or remove messages. Your draft stays for you to review before sending a new message.")
        }
        .confirmationDialog("Block this Style Friend?", isPresented: $showingBlockConfirmation, titleVisibility: .visible) { Button("Block", role: .destructive) { Task { await blockFriend() } } } message: { Text("You will no longer be able to use this conversation. KigoStylist does not disclose block direction.") }
        .alert("Messaging unavailable", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) { Button("OK", role: .cancel) { actionError = nil } } message: { Text(actionError ?? "") }
        .alert("Attachment unavailable", isPresented: Binding(get: { attachmentError != nil }, set: { if !$0 { attachmentError = nil } })) { Button("OK", role: .cancel) { attachmentError = nil } } message: { Text(attachmentError ?? "") }
        .onChange(of: selectedAttachmentPhoto) { item in Task { await loadAttachmentPhoto(item) } }
        .task { await reconcileUnresolvedOperations() }
    }

    @ViewBuilder private var chatContent: some View {
        switch state {
        case .loading: ProgressView("Loading messages…").frame(maxWidth: .infinity, maxHeight: .infinity)
        case .empty:
            messageTimeline(initialScrollID: nil) {
                ChatUnavailableState(icon: "bubble.left", title: "No messages yet", detail: "Send a message to start this conversation.")
                    .padding(.top, 18)
            }
        case .populated:
            messageTimeline(initialScrollID: preferredInitialScrollID) {
                ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                    FriendMessageBubble(
                        message: message,
                        groupsWithPrevious: index > 0 && messages[index - 1].sender == message.sender,
                        onReply: { replyTarget = message },
                        onReact: { pickerTarget = message },
                        onDelete: { Task { await delete(message) } },
                        onReport: { Task { await report(message) } },
                        onAskWhere: { draft = "Where did you get this?" },
                        directMessages: directMessages,
                        conversation: conversation.conversationReference
                    )
                    .id(message.id)
                }
            }
        case .recoverableError: ChatUnavailableState(icon: "wifi.exclamationmark", title: "Chat unavailable", detail: "Try again when the connection is available.")
        case .authorizationUnavailable: ChatUnavailableState(icon: "lock.slash", title: "Messaging is not available yet", detail: "This UI does not create local demo messages or pretend a send succeeded.")
        }
    }

    private var preferredInitialScrollID: String? {
        if let initialMessageReference,
           messages.contains(where: { $0.messageReference == initialMessageReference }) {
            return initialMessageReference.value
        }
        return initialMessageReference == nil ? messages.last?.id : nil
    }

    private var composerIsAvailable: Bool {
        switch state {
        case .authorizationUnavailable, .recoverableError:
            false
        case .loading, .empty, .populated:
            true
        }
    }

    @ViewBuilder private func messageTimeline<Content: View>(initialScrollID: String?, @ViewBuilder content: @escaping () -> Content) -> some View {
        ScrollViewReader { reader in
            ScrollView {
            LazyVStack(spacing: 0) {
                content()
                if let failedSendRecord = failedSend {
                    FriendFailedSendBubble(
                        record: failedSendRecord,
                        onRetry: { Task { await retryFailedSend() } },
                        onDiscard: abandonFailedSend
                    )
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 18)
            }
            .onAppear {
                guard let initialScrollID else { return }
                reader.scrollTo(
                    initialScrollID,
                    anchor: initialMessageReference == nil ? .bottom : .center
                )
            }
            .onChange(of: messages.map(\.id)) { _ in
                guard let target = initialMessageReference?.value,
                      messages.contains(where: { $0.id == target }) else { return }
                reader.scrollTo(target, anchor: .center)
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func requestFirstSendAuthorization() {
        guard !isSending, failedSend == nil, !recoveryPending else { return }
        let snapshot = StyleFriendsSubmissionSnapshot(text: draft.trimmingCharacters(in: .whitespacesAndNewlines), photo: pendingAttachmentPhoto, share: pendingShare, reply: replyTarget?.messageReference)
        guard !snapshot.text.isEmpty || snapshot.photo != nil || snapshot.share != nil else { return }
        let submittingSession = StyleMatchAccountSessionStore.load()
        isSending = true
        Task {
            defer { isSending = false }
            emit(.photo_send_started)
            emit(.authorization_started)
            await termsGate.refresh(using: directMessages)
            guard submittingSession != nil, StyleMatchAccountSessionStore.load() == submittingSession else {
                actionError = StyleFriendsDMPresentationMapper.userMessage(for: .signInRequired); return
            }
            if case .acceptanceRequired = termsGate.state { emit(.authorization_failed, category: "consent_required", retryable: false, phase: "authorization"); showingTerms = true; return }
            guard termsGate.canSend else { emit(.authorization_failed, category: "unavailable", retryable: true, phase: "authorization"); actionError = StyleFriendsDMPresentationMapper.userMessage(for: .dmUnavailable); return }
            emit(.authorization_succeeded)
            let enteredText = snapshot.text
            let text = enteredText.isEmpty ? (snapshot.share == nil ? "Shared a photo" : "Shared a KigoStylist scan") : enteredText
            let attachmentPhoto = snapshot.photo
            let share = snapshot.share
            let operationType: StyleFriendsDMOperationJournalRecord.OperationType = (attachmentPhoto != nil || share != nil) ? .preparedAttachment : .text
            if let attachmentPhoto {
                let photoDraft = StyleFriendsDMSendDraft(text: text, clientMessageReference: UUID().uuidString.replacingOccurrences(of: "-", with: ""), parentMessageReference: snapshot.reply)
                let result = await attachmentCoordinator.sendNewPhoto(draft: photoDraft, jpeg: attachmentPhoto)
                if result == .confirmedAssociationSuccess {
                    guard let completed = attachmentCoordinator.activeDraft else { recoveryPending = true; return }
                    do { try completeOperation(completed) } catch { recoveryPending = true; return }
                    clearPhotoSubmissionIfUnchanged(snapshot)
                    await onOperationCompleted?()
                } else if let context = attachmentCoordinator.activeOperation {
                    let recoveryDraft = StyleFriendsDMSendDraft(
                        text: photoDraft.text,
                        clientMessageReference: photoDraft.clientMessageReference,
                        parentMessageReference: snapshot.reply,
                        operationID: context.operationID,
                        operationProtocolVersion: context.protocolVersion,
                        operationScopeTag: context.scopeTag,
                        operationType: context.operationType
                    )
                    failedSend = .init(
                        draft: recoveryDraft,
                        error: .invalidResponse,
                        phase: .send(photoAttachment: attachmentPhoto, share: nil)
                    )
                    if result == .ambiguousOutcome {
                        actionError = "Delivery status is uncertain. Use Retry to check the server before resending."
                    }
                } else {
                    actionError = "The photo could not be prepared for a safe retry. It remains attached."
                }
                return
            }
            guard let account = StyleMatchAccountSessionStore.load(),
                  let accountScope = account.accountID ?? account.appleSubject,
                  let environmentScope = account.endpointHost else {
                actionError = StyleFriendsDMPresentationMapper.userMessage(for: .signInRequired); return
            }
            let operation: StyleFriendsDMOperationJournalRecord
            do {
                let scope = try StyleFriendsDMOperationJournal.shared.scopeTag(account: accountScope, environment: environmentScope, conversation: conversation.conversationReference.value)
                let accountEnvironment = try StyleFriendsDMOperationJournal.shared.accountEnvironmentTag(account: accountScope, environment: environmentScope)
                let immutablePayload = Data((text + "\u{1f}" + (snapshot.reply?.value ?? "") + "\u{1f}" + operationType.rawValue).utf8)
                let fingerprint = try StyleFriendsDMOperationJournal.shared.payloadFingerprint(type: operationType, immutablePayload: immutablePayload)
                // This succeeds before the first send, preparation, or upload
                // request. A Keychain failure is a fail-closed local outcome.
                let created = try StyleFriendsDMOperationJournal.shared.create(accountEnvironmentTag: accountEnvironment, scopeTag: scope, operationType: operationType, payloadFingerprint: fingerprint)
                operation = try StyleFriendsDMOperationJournal.shared.transition(operationID: created.operationID, expectedScopeTag: scope, to: operationType == .text ? .submitted : .preparingAttachment)
            } catch {
                actionError = "Messaging is temporarily unavailable. Please try again later."
                return
            }
            let pending = StyleFriendsDMSendDraft(text: text, clientMessageReference: UUID().uuidString.replacingOccurrences(of: "-", with: ""), parentMessageReference: snapshot.reply, operationID: operation.operationID, operationProtocolVersion: operation.schema, operationScopeTag: operation.scopeTag, operationType: operation.operationType)
            if let share {
                await createAndAssociateShare(draft: pending, share: share)
                return
            }
            // Raw-photo delivery is exclusively owned by the coordinator. Exit
            // before the view performs any message request of its own.
            // Raw photos return through sendNewPhoto above; this path is text or prepared share only.
            // Keep the user-visible payload intact until every required handoff
            // is confirmed.  The stable references below make a retry safe even
            // when the first request completed after a transport interruption.
            do {
                emit(.message_started)
                let message = try await directMessages.send(conversation: conversation.conversationReference, draft: pending)
                try completeOperation(pending)
                emit(.message_succeeded)
                failedSend = nil
                clearComposerAfterConfirmedHandoff()
                await onOperationCompleted?()
            } catch let error as StyleFriendsDMError {
                emit(.message_failed, category: error.rawValue, retryable: true, phase: "message")
                markOperationUnknown(pending)
                failedSend = .init(draft: pending, error: error, phase: .send(photoAttachment: attachmentPhoto, share: share))
            } catch {
                emit(.message_failed, category: "invalid_response", retryable: true, phase: "message")
                markOperationUnknown(pending)
                failedSend = .init(draft: pending, error: .invalidResponse, phase: .send(photoAttachment: attachmentPhoto, share: share))
            }
        }
    }

    private func emit(_ phase: StyleFriendsPhotoSendPhase, category: String? = nil, retryable: Bool = false, phase operationPhase: String = "") {
        let outcome = category.map { StyleFriendsPhotoSendOutcome.category($0, httpStatus: nil, retryable: retryable, operationPhase: operationPhase) }
        phaseObserver?.photoSendPhase(phase, outcome: outcome)
    }

    private func markOperationUnknown(_ draft: StyleFriendsDMSendDraft) {
        guard let operationID = draft.operationID, let scope = draft.operationScopeTag else { return }
        _ = try? StyleFriendsDMOperationJournal.shared.transition(operationID: operationID, expectedScopeTag: scope, to: .unknown)
    }

    private func completeOperation(_ draft: StyleFriendsDMSendDraft) throws {
        guard let context = try operationContext(for: draft) else { throw StyleFriendsDMError.invalidResponse }
        guard let record = try StyleFriendsDMOperationJournal.shared.load(operationID: context.operationID, expectedScopeTag: context.scopeTag) else { throw StyleFriendsDMError.invalidResponse }
        try StyleFriendsDMOperationJournal.shared.delete(operationID: context.operationID)
        let remaining = try StyleFriendsDMOperationJournal.shared.unresolved(accountEnvironmentTag: record.accountEnvironmentTag)
        recoveryPending = remaining.contains { $0.scopeTag == context.scopeTag }
    }

    private func operationContext(for draft: StyleFriendsDMSendDraft) throws -> StyleFriendsDMOperationContext? {
        // Headerless drafts are the frozen Build 18043 compatibility path. A
        // Build 18045 draft must never silently become headerless mid-flow.
        guard let operationID = draft.operationID else { return nil }
        guard let account = StyleMatchAccountSessionStore.load(),
              let accountScope = account.accountID ?? account.appleSubject,
              let environmentScope = account.endpointHost,
              draft.operationScopeTag == (try StyleFriendsDMOperationJournal.shared.scopeTag(account: accountScope, environment: environmentScope, conversation: conversation.conversationReference.value)) else { throw StyleFriendsDMError.signInRequired }
        guard draft.operationProtocolVersion == 1, let scope = draft.operationScopeTag,
              let record = try StyleFriendsDMOperationJournal.shared.load(operationID: operationID, expectedScopeTag: scope),
              record.operationType == draft.operationType else { throw StyleFriendsDMError.invalidResponse }
        return StyleFriendsDMOperationContext(record: record)
    }

    /// Recovery is status-only. It never calls send, upload, snapshot, or
    /// association. A failed/old response deliberately remains unknown.
    private func reconcileUnresolvedOperations() async {
        guard !isCheckingRecovery, !isSending else { return }
        isCheckingRecovery = true
        stoppableAttachmentIDs = []
        recoveryAccountSession = nil
        defer { isCheckingRecovery = false }
        recoveryPending = true
        #if OWNER_BETA
        recoveryDiagnostic = .unavailable
        #endif
        recoveryFeedback = "A previous send has not been confirmed. Sending remains paused."
        emit(.reconciliation_started)
        guard let account = StyleMatchAccountSessionStore.load(),
              let accountScope = account.accountID ?? account.appleSubject,
              let environmentScope = account.endpointHost else { return }
        do {
            let accountEnvironmentTag = try StyleFriendsDMOperationJournal.shared.accountEnvironmentTag(account: accountScope, environment: environmentScope)
            let scope = try StyleFriendsDMOperationJournal.shared.scopeTag(account: accountScope, environment: environmentScope, conversation: conversation.conversationReference.value)
            let resolutions = await StyleFriendsDMOperationRecoveryCoordinator.shared.reconcile(accountEnvironmentTag: accountEnvironmentTag, scopeTag: scope, service: directMessages)
            guard StyleMatchAccountSessionStore.load() == account else { return }
            attachmentCoordinator.applyRecovery(resolutions)
            if let failed = failedSend, failed.applyingRecovery(resolutions) == nil {
                failedSend = nil
                clearComposerAfterConfirmedDelivery(failed)
            }
            let remainingRecords = try StyleFriendsDMOperationJournal.shared.unresolved(accountEnvironmentTag: accountEnvironmentTag).filter { $0.scopeTag == scope }
            recoveryPending = !remainingRecords.isEmpty
            recoveryAccountSession = account
            stoppableAttachmentIDs = StyleFriendsDMOperationJournal.stoppableUnknownAttachments(remainingRecords, accountEnvironmentTag: accountEnvironmentTag, scopeTag: scope)
            #if OWNER_BETA
            recoveryDiagnostic = .init(records: remainingRecords, accountEnvironmentTag: accountEnvironmentTag, scopeTag: scope, now: Date())
            #endif
            if recoveryPending {
                recoveryFeedback = "The previous delivery is still unconfirmed. Sending stays paused to prevent duplicates; checking does not resend it."
            }
            if resolutions.contains(where: { if case .committed = $0 { return true }; return false }) { emit(.reconciliation_succeeded); await onOperationCompleted?() }
            else if resolutions.contains(where: { if case .unknown = $0 { return true }; return false }) { emit(.reconciliation_ambiguous, category: "unknown", retryable: false, phase: "reconciliation") }
            else { emit(.reconciliation_failed, category: "not_committed", retryable: true, phase: "reconciliation") }
        } catch {
            emit(.reconciliation_ambiguous, category: "unavailable", retryable: false, phase: "reconciliation")
            // A transport, decode, old-Worker, or Keychain error is unknown;
            // no retry or automatic mutation is permitted from recovery.
        }
    }

    private func presentSavedShareChoices(_ kind: StyleFriendsDMShareEligibilityAuthority.Kind) {
        guard StyleFriendsDMAttachmentRuntimeAuthority.isAuthorized else { attachmentError = "Attachments are unavailable in this build."; return }
        do {
            let shareChoices = try shareAuthority.choices(for: kind)
            sharePickerRequest = SharePickerRequest(choices: shareChoices)
        } catch let error as StyleFriendsDMShareEligibilityAuthority.AvailabilityError {
            attachmentError = error.message
        } catch {
            attachmentError = "Your saved scans could not be loaded for sharing. Your saved data has not been changed."
        }
    }

    private func attachmentKind(for kind: StyleFriendsDMShareEligibilityAuthority.Kind) -> StyleFriendsDMAttachmentKind {
        switch kind { case .scan: .scanSnapshot; case .score: .scoreSnapshot; case .outfit: .outfitSnapshot }
    }

    private func createAndAssociateShare(draft: StyleFriendsDMSendDraft, share: StyleFriendsDMPreparedShare, checkpoint: (message: StyleFriendsDMMessage, image: StyleFriendsOpaqueRouteReference?)? = nil) async {
        do {
            guard let operation = try operationContext(for: draft) else { throw StyleFriendsDMError.invalidResponse }
            let authority = StyleFriendsPreparedShareDeliveryAuthority(service: directMessages)
            if let checkpoint {
                if share.imagePreview != nil, checkpoint.image == nil {
                    _ = try await authority.resumePhotoUpload(conversation: conversation.conversationReference, message: checkpoint.message, share: share, operation: operation)
                } else {
                    _ = try await authority.resumeSnapshot(conversation: conversation.conversationReference, message: checkpoint.message, share: share, imageReference: checkpoint.image, operation: operation)
                }
            } else {
                _ = try await authority.deliver(conversation: conversation.conversationReference, draft: draft, share: share, operation: operation)
            }
            try completeOperation(draft)
            failedSend = nil
            clearComposerAfterConfirmedHandoff()
            await onOperationCompleted?()
        } catch let failure as StyleFriendsPreparedShareUploadFailure {
            markOperationUnknown(draft)
            failedSend = .init(draft: draft, error: failure.error, phase: .createShare(message: failure.message, share: share, uploadedImageReference: nil))
        } catch let failure as StyleFriendsPreparedShareSnapshotFailure {
            markOperationUnknown(draft)
            failedSend = .init(draft: draft, error: failure.error, phase: .createShare(message: failure.message, share: share, uploadedImageReference: failure.imageReference))
        } catch let failure as StyleFriendsPreparedShareAssociationFailure {
            failedSend = .init(
                draft: draft,
                error: failure.error,
                phase: .associate(message: failure.message, attachment: failure.attachment)
            )
        } catch let error as StyleFriendsDMError {
            failedSend = .init(draft: draft, error: error, phase: .send(photoAttachment: nil, share: share))
        } catch {
            failedSend = .init(draft: draft, error: .invalidResponse, phase: .send(photoAttachment: nil, share: share))
        }
    }

    private func loadAttachmentPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                StyleFriendsDMAttachmentDiagnostics.record("PHOTO_PICKER_LOAD", "FAILED")
                attachmentError = "That photo could not be prepared. Please try another one."; return
            }
            StyleFriendsDMAttachmentDiagnostics.record("PHOTO_PICKER_LOAD", "PASS")
            guard let jpeg = StyleFriendsDMAttachmentPhotoPreparation.normalizedJPEG(from: data) else {
                StyleFriendsDMAttachmentDiagnostics.record("PHOTO_NORMALIZATION", "FAILED")
                attachmentError = "That photo could not be prepared. Please try another one."; return
            }
            StyleFriendsDMAttachmentDiagnostics.record("PHOTO_NORMALIZATION", "JPEG_\(jpeg.count)B")
            pendingAttachmentPhoto = jpeg
        } catch {
            StyleFriendsDMAttachmentDiagnostics.record("PHOTO_PICKER_LOAD", "FAILED")
            attachmentError = "That photo could not be prepared. Please try another one."
        }
    }

    private func clearPhotoSubmissionIfUnchanged(_ snapshot: StyleFriendsSubmissionSnapshot) {
        guard draft.trimmingCharacters(in: .whitespacesAndNewlines) == snapshot.text,
              snapshot.matches(text: draft, photo: pendingAttachmentPhoto, reply: replyTarget?.messageReference) else { return }
        draft = ""; pendingAttachmentPhoto = nil; selectedAttachmentPhoto = nil; replyTarget = nil
    }

    private func clearComposerAfterConfirmedDelivery(
        _ operation: StyleFriendsDMFailedDeliveryOperation
    ) {
        guard operation.matchesComposer(
            .init(text: draft, photo: pendingAttachmentPhoto, share: pendingShare, reply: replyTarget?.messageReference)
        ) else { return }
        clearComposerAfterConfirmedHandoff()
    }

    private func retryFailedSend() async {
        guard var record = failedSend, (record.canRetry || record.canRetryAfterReauthentication), !isSending, !isCheckingRecovery else { return }
        isSending = true
        defer {
            isSending = false
            if let pending = failedSend, pending.id == record.id {
                failedSend = pending.finishingRetry()
            }
        }
        var statusConfirmedNotCommitted = false
        let resumesKnownAssociation: Bool
        if case .associate = record.phase { resumesKnownAssociation = true }
        else if case .createShare = record.phase { resumesKnownAssociation = true }
        else { resumesKnownAssociation = false }
        // A retained canonical caption resumes only the exact operation/photo,
        // snapshot or association. Staging enforces payload-bound photo replay.
        // A phase that could resend the caption still requires an exact
        // sender-scoped non-commitment response first.
        if record.record.draft.operationID != nil, !resumesKnownAssociation {
            do {
                guard let context = try operationContext(for: record.record.draft) else { throw StyleFriendsDMError.invalidResponse }
                let status = try await directMessages.operationStatus(context: context)
                guard status.operationID == context.operationID else { throw StyleFriendsDMError.invalidResponse }
                switch status.outcome {
                case .committed:
                    try StyleFriendsDMOperationJournal.shared.delete(operationID: context.operationID)
                    attachmentCoordinator.applyRecovery([.committed(context.operationID)])
                    failedSend = nil
                    clearComposerAfterConfirmedDelivery(record)
                    await onOperationCompleted?()
                    return
                case .notCommitted:
                    if let local = try StyleFriendsDMOperationJournal.shared.load(operationID: context.operationID, expectedScopeTag: context.scopeTag), local.phase != .notCommitted {
                        _ = try StyleFriendsDMOperationJournal.shared.transition(operationID: context.operationID, expectedScopeTag: context.scopeTag, to: .reconciling)
                        _ = try StyleFriendsDMOperationJournal.shared.transition(operationID: context.operationID, expectedScopeTag: context.scopeTag, to: .notCommitted)
                    }
                    _ = try StyleFriendsDMOperationJournal.shared.transition(operationID: context.operationID, expectedScopeTag: context.scopeTag, to: .submitted)
                    statusConfirmedNotCommitted = true
                case .unknown:
                    throw StyleFriendsDMError.idempotencyConflict
                }
            } catch {
                // The in-memory payload remains visible but the operation is
                // locked. Another explicit Retry may check status again, but
                // neither a failed lookup nor Unknown authorizes a resend.
                failedSend = .init(draft: record.record.draft, error: (error as? StyleFriendsDMError) == .signInRequired ? .signInRequired : .networkUnavailable, phase: record.phase)
                actionError = "The earlier delivery is still unconfirmed. Retry checked its status without sending another copy."
                return
            }
        }
        record.isRetrying = true; failedSend = record
        switch record.phase {
        case let .send(photoAttachment: attachmentPhoto, share: share):
            if let share {
                await createAndAssociateShare(draft: record.record.draft, share: share)
                return
            }
            if let attachmentPhoto {
                await attachmentCoordinator.retryPhoto(
                    statusAlreadyConfirmedNotCommitted: statusConfirmedNotCommitted
                )
                if attachmentCoordinator.state == .sent {
                    do { try completeOperation(record.record.draft) } catch { recoveryPending = true; return }
                    failedSend = nil
                    clearPhotoSubmissionIfUnchanged(
                        .init(
                            text: record.record.draft.text,
                            photo: attachmentPhoto,
                            share: nil,
                            reply: record.record.draft.parentMessageReference
                        )
                    )
                    await onOperationCompleted?()
                }
                return
            }
            do {
                let message = try await directMessages.send(conversation: conversation.conversationReference, draft: record.record.draft)
                try completeOperation(record.record.draft)
                if attachmentPhoto == nil {
                    failedSend = nil
                    clearComposerAfterConfirmedHandoff()
                    await onOperationCompleted?()
                }
            } catch let error as StyleFriendsDMError {
                failedSend = .init(draft: record.record.draft, error: error, phase: .send(photoAttachment: attachmentPhoto, share: share))
            } catch {
                failedSend = .init(draft: record.record.draft, error: .invalidResponse, phase: .send(photoAttachment: attachmentPhoto, share: share))
            }
        case let .upload(message, jpeg):
            _ = message
            _ = jpeg
            await attachmentCoordinator.retryPhoto(
                statusAlreadyConfirmedNotCommitted: statusConfirmedNotCommitted
            )
            if attachmentCoordinator.state == .sent {
                failedSend = nil
                clearComposerAfterConfirmedDelivery(record)
                await onOperationCompleted?()
            }
        case let .createShare(message, share, image):
            await createAndAssociateShare(draft: record.record.draft, share: share, checkpoint: (message, image))
        case let .associate(message, attachment):
            await associatePreparedShareAttachment(draft: record.record.draft, message: message, attachment: attachment)
        }
    }

    /// A separate explicit action, never part of checking or sending.
    private func stopWaitingForUnknownAttachments() {
        guard !isSending, !isCheckingRecovery, !stoppableAttachmentIDs.isEmpty,
              let account = StyleMatchAccountSessionStore.load(),
              account == recoveryAccountSession, account.expiresAt > Date(),
              let accountScope = account.accountID ?? account.appleSubject,
              let environmentScope = account.endpointHost else { return }
        isCheckingRecovery = true
        defer { isCheckingRecovery = false }
        let selectedIDs = stoppableAttachmentIDs
        stoppableAttachmentIDs = []
        do {
            let journal = StyleFriendsDMOperationJournal.shared
            let accountEnvironment = try journal.accountEnvironmentTag(account: accountScope, environment: environmentScope)
            let scope = try journal.scopeTag(account: accountScope, environment: environmentScope, conversation: conversation.conversationReference.value)
            for operationID in selectedIDs {
                try journal.archiveUnknownAttachment(operationID: operationID, accountEnvironmentTag: accountEnvironment, expectedScopeTag: scope)
                attachmentCoordinator.stopWaitingAfterArchiving(operationID: operationID)
                if failedSend?.record.draft.operationID == operationID { failedSend = nil }
            }
            let remaining = try journal.unresolved(accountEnvironmentTag: accountEnvironment).filter { $0.scopeTag == scope }
            recoveryPending = !remaining.isEmpty
            stoppedWaiting = true
            #if OWNER_BETA
            recoveryDiagnostic = .init(records: remaining, accountEnvironmentTag: accountEnvironment, scopeTag: scope, now: Date())
            #endif
        } catch {
            recoveryPending = true
            actionError = "The unfinished attachment could not be safely archived. Sending remains paused. Check its status and try again."
        }
    }

    /// Local-only abandonment. It deliberately has no service collaborator:
    /// no send, upload, status lookup, recall, or remote deletion can occur.
    private func abandonFailedSend() {
        guard !isSending, let failed = failedSend else { return }
        if let operationID = failed.record.draft.operationID {
            do {
                guard let context = try operationContext(for: failed.record.draft),
                      let record = try StyleFriendsDMOperationJournal.shared.load(operationID: operationID, expectedScopeTag: context.scopeTag),
                      record.phase == .notCommitted else {
                    actionError = "Delivery is unresolved. Check its status before discarding."; return
                }
                try StyleFriendsDMOperationJournal.shared.delete(operationID: operationID)
            } catch { actionError = "Delivery is unresolved. Check its status before discarding."; return }
        }
        if case .send(photoAttachment: .some, share: nil) = failed.phase {
            attachmentCoordinator.discardPhoto()
        }
        failedSend = nil
    }

    private func associatePreparedShareAttachment(draft: StyleFriendsDMSendDraft, message: StyleFriendsDMMessage, attachment: StyleFriendsDMAttachment) async {
        do {
            emit(.association_started)
            guard let operation = try operationContext(for: draft) else { throw StyleFriendsDMError.invalidResponse }
            let authority = StyleFriendsPreparedShareDeliveryAuthority(service: directMessages)
            let associated = try await authority.resumeAssociation(conversation: conversation.conversationReference, message: message.messageReference, attachment: attachment.attachmentReference, operation: operation)
            guard associated.attachmentReference == attachment.attachmentReference else { throw StyleFriendsDMError.invalidResponse }
            emit(.association_succeeded)
            emit(.photo_send_completed)
            StyleFriendsDMAttachmentDiagnostics.record("ATTACHMENT_FINALIZE", "PASS")
            StyleFriendsDMAttachmentDiagnostics.record("DM_MESSAGE_LINK", "PASS")
            try completeOperation(draft)
            failedSend = nil
            clearComposerAfterConfirmedHandoff()
            await onOperationCompleted?()
        } catch let error as StyleFriendsDMError {
            emit(.association_failed, category: error.rawValue, retryable: true, phase: "association")
            StyleFriendsDMAttachmentDiagnostics.record("ATTACHMENT_FINALIZE", "ASSOCIATE_\(error.rawValue)")
            failedSend = .init(draft: draft, error: error, phase: .associate(message: message, attachment: attachment))
        } catch {
            StyleFriendsDMAttachmentDiagnostics.record("ATTACHMENT_FINALIZE", "ASSOCIATE_INVALID_RESPONSE")
            failedSend = .init(draft: draft, error: .invalidResponse, phase: .associate(message: message, attachment: attachment))
        }
    }
    private func clearComposerAfterConfirmedHandoff() {
        draft = ""
        pendingAttachmentPhoto = nil
        pendingShare = nil
        selectedAttachmentPhoto = nil
        replyTarget = nil
        // The archived unknown operation remains preserved in the journal.
        // After a separate send is positively confirmed, the old “review your
        // draft” reminder is stale because there is no longer a draft to review.
        stoppedWaiting = false
    }
    private func setReaction(_ reaction: StyleFriendReactionKind?, message: StyleFriendsFriendMessagePresentation) async {
        do {
            _ = try await directMessages.setReaction(message: message.messageReference, reaction: reaction)
            StyleMatchPremiumFeedback.selection()
            pickerTarget = nil
            await onOperationCompleted?()
        } catch let error as StyleFriendsDMError {
            actionError = StyleFriendsDMPresentationMapper.userMessage(for: error)
        } catch {
            actionError = StyleFriendsDMPresentationMapper.userMessage(for: .invalidResponse)
        }
    }
    private func delete(_ message: StyleFriendsFriendMessagePresentation) async { do { try await directMessages.deleteOwnMessage(message.messageReference); await onOperationCompleted?() } catch let error as StyleFriendsDMError { actionError = StyleFriendsDMPresentationMapper.userMessage(for: error) } catch { actionError = StyleFriendsDMPresentationMapper.userMessage(for: .invalidResponse) } }
    private func report(_ message: StyleFriendsFriendMessagePresentation) async { do { try await directMessages.report(message: message.messageReference, draft: .init(category: .other, detail: nil)) } catch let error as StyleFriendsDMError { actionError = StyleFriendsDMPresentationMapper.userMessage(for: error) } catch { actionError = StyleFriendsDMPresentationMapper.userMessage(for: .invalidResponse) } }
    private func blockFriend() async { guard let friend = conversation.friendSocialReference else { return }; do { try await directMessages.block(friend: friend); await onOperationCompleted?() } catch let error as StyleFriendsDMError { actionError = StyleFriendsDMPresentationMapper.userMessage(for: error) } catch { actionError = StyleFriendsDMPresentationMapper.userMessage(for: .invalidResponse) } }
}

/// PhotosPicker can return HEIC, PNG, or JPEG bytes. The attachment route has
/// one explicit contract: a bounded JPEG under 5 MiB. Normalizing here keeps
/// the MIME header truthful and prevents client-side size rejection.
enum StyleFriendsDMAttachmentPhotoPreparation {
    static let maximumUploadBytes = 5 * 1024 * 1024

    static func normalizedJPEG(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let longest = max(image.size.width, image.size.height)
        guard longest > 0 else { return nil }
        for maximumDimension in [1_600, 1_280, 1_024, 800] {
            let scale = min(1, CGFloat(maximumDimension) / longest)
            let target = CGSize(width: max(1, floor(image.size.width * scale)), height: max(1, floor(image.size.height * scale)))
            let renderer = UIGraphicsImageRenderer(size: target)
            let normalized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
            for quality in [CGFloat(0.84), 0.76, 0.68] {
                if let jpeg = normalized.jpegData(compressionQuality: quality), jpeg.count <= maximumUploadBytes {
                    return jpeg
                }
            }
        }
        return nil
    }
}

private struct FriendChatTermsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var gate: StyleFriendsDMFirstSendTermsGate
    let service: any StyleFriendsDirectMessageServing

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("Community Terms").font(.title2.bold())
                Text("Private messages must follow the Style Friends Community and UGC Terms. Accepting is required before your first message is sent.")
                Text("Accepting does not send a message. KigoStylist waits for the authorized service to confirm your acceptance.").font(.footnote).foregroundStyle(.secondary)
                switch gate.state {
                case .acceptanceRequired:
                    Button("Accept Community Terms") { Task { await gate.accept(using: service) } }
                        .buttonStyle(.borderedProminent)
                        .accessibilityHint("Accepts the current Community Terms. Your message remains unsent until the authorized service confirms acceptance.")
                case .accepting, .loading:
                    ProgressView("Confirming terms…")
                case .unavailable:
                    Text("Messaging is temporarily unavailable. Please try again later.").foregroundStyle(.secondary)
                case .accepted:
                    Label("Community Terms accepted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                case .idle:
                    EmptyView()
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Community Terms")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

private struct FriendFailedSendBubble: View {
    let record: StyleFriendsDMFailedDeliveryOperation
    let onRetry: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text(record.phase.messageWasPersisted ? "Photo attachment not sent" : record.record.draft.text).font(.body).foregroundStyle(.white).padding(.horizontal, 16).padding(.vertical, 12)
                .background(Color(red: 0.33, green: 0.18, blue: 0.62), in: UnevenRoundedRectangle(topLeadingRadius: 24, bottomLeadingRadius: 24, bottomTrailingRadius: 24, topTrailingRadius: 6))
            HStack(alignment: .bottom, spacing: 6) {
                if record.isRetrying { ProgressView().controlSize(.small); Text("Retrying…").font(.caption.weight(.semibold)) }
                else if record.record.disposition == .retryable { Button("Retry", action: onRetry).font(.caption.weight(.semibold)).accessibilityLabel("Retry message").accessibilityHint("Retries this exact unsent operation without creating another message.") }
                else if record.record.disposition == .requiresReauthentication { Button("Retry after sign-in", action: onRetry).font(.caption.weight(.semibold)).accessibilityLabel("Retry after signing in").accessibilityHint("After you sign in again, retries this exact operation without creating another message.") }
                else { Text("Not sent").font(.caption.weight(.semibold)) }
                Button("Discard", role: .destructive, action: onDiscard).font(.caption.weight(.semibold)).disabled(record.isRetrying).accessibilityLabel("Discard unsent message").accessibilityHint("Removes only this local retry record. It does not delete a sent Style Friends message.")
            }.foregroundStyle(record.record.disposition == .retryable ? Color.secondary : Color.red)
        }
        .frame(maxWidth: .infinity, alignment: .trailing).padding(.top, 16)
        .accessibilityElement(children: .combine).accessibilityLabel("\(record.phase.messageWasPersisted ? "Photo attachment was not sent." : "Message not sent.") \(record.record.disposition == .retryable ? "Retry or discard available." : record.record.disposition == .requiresReauthentication ? "Sign in again before retrying." : "Discard available.")")
    }
}

struct FriendMessageBubble: View {
    let message: StyleFriendsFriendMessagePresentation
    let groupsWithPrevious: Bool
    let onReply: () -> Void
    let onReact: () -> Void
    let onDelete: () -> Void
    let onReport: () -> Void
    let onAskWhere: () -> Void
    let directMessages: any StyleFriendsDirectMessageServing
    let conversation: StyleFriendsOpaqueRouteReference
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: message.sender == .selfUser ? .trailing : .leading, spacing: 6) {
            if let parent = message.parentPreview { FriendReplyPreview(preview: parent) }
            if let attachment = message.attachment {
                StyleFriendsDMAttachmentCard(attachment: attachment, unavailable: message.deletedOrUnavailable, directMessages: directMessages, conversation: conversation)
                if attachment.kind != .photo && !message.deletedOrUnavailable && attachment.state == "active" {
                    StyleFriendsSharedMessageActions(onReact: onReact, onReply: onReply, onAskWhere: onAskWhere)
                }
            } else if let outfit = message.sharedOutfit {
                SharedOutfitMessageCard(outfit: outfit, onReply: onReply, onReact: onReact, onAskWhere: onAskWhere)
            }
            if !message.renderedText.isEmpty { Text(message.renderedText).font(messageIsEmojiOnly ? .title2 : .body).multilineTextAlignment(.leading).foregroundStyle(message.sender == .selfUser ? .white : .primary).padding(.horizontal, messageIsEmojiOnly ? 18 : 16).padding(.vertical, messageIsEmojiOnly ? 10 : 12).background(bubbleSurface, in: UnevenRoundedRectangle(topLeadingRadius: groupsWithPrevious ? 12 : 24, bottomLeadingRadius: 24, bottomTrailingRadius: 24, topTrailingRadius: message.sender == .selfUser ? 6 : 24)).fixedSize(horizontal: false, vertical: true) }
            if let summary = message.reactionSummary { FriendReactionSummary(summary: summary) }
            HStack(spacing: 9) {
                if let date = message.timestamp {
                    Text(date, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                deliveryLabel
                if message.sender != .selfUser {
                    Text("Received")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Received message")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: message.sender == .selfUser ? .trailing : .leading).padding(.top, groupsWithPrevious ? 4 : 16)
        .contextMenu { Button("Reply", action: onReply); Button("React", action: onReact); Button("Copy") { UIPasteboard.general.string = message.renderedText }; if message.sender == .selfUser { Button("Delete", role: .destructive, action: onDelete) } else { Button("Report", role: .destructive, action: onReport) } }
        .accessibilityElement(children: .contain).accessibilityLabel("\(message.sender == .selfUser ? "You" : message.senderDisplayName). \(message.renderedText). \(deliveryAccessibilityText)")
        .accessibilityAction(named: "Reply", onReply).accessibilityAction(named: "React", onReact)
        .accessibilityAction(named: message.sender == .selfUser ? "Delete" : "Report", message.sender == .selfUser ? onDelete : onReport)
    }

    private var bubbleSurface: some ShapeStyle { message.sender == .selfUser ? AnyShapeStyle(KigoStyleFriendsPalette.button) : AnyShapeStyle(Color(uiColor: .secondarySystemGroupedBackground)) }
    private var messageIsEmojiOnly: Bool { let text = message.renderedText.trimmingCharacters(in: .whitespacesAndNewlines); return !text.isEmpty && text.unicodeScalars.allSatisfy { $0.properties.isEmoji || $0.properties.isEmojiPresentation || $0.properties.generalCategory == .nonspacingMark } }
    @ViewBuilder private var deliveryLabel: some View {
        if message.sender == .selfUser {
            switch message.delivery {
            case .sending: Text("Sending…").font(.caption2).foregroundStyle(.secondary)
            case .sent: Text("Sent").font(.caption2).foregroundStyle(.secondary)
            case .underReview: Text("Checking status…").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            case .removed: Text("Message unavailable").font(.caption2).foregroundStyle(.secondary)
            case .failed: Text("Failed").font(.caption.weight(.semibold)).foregroundStyle(.red)
            }
        }
    }
    private var deliveryAccessibilityText: String {
        guard message.sender == .selfUser else { return "Incoming message" }
        switch message.delivery {
        case .sending: return "Sending"
        case .sent: return "Sent"
        case .underReview: return "Checking status. No resend performed."
        case .removed: return "Message unavailable."
        case .failed: return "Failed. Retry or discard available."
        }
    }
}

struct StyleFriendsSharedMessageActions: View {
    let onReact: () -> Void
    let onReply: () -> Void
    let onAskWhere: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            action("React", symbol: "face.smiling", id: "friends.message.react", perform: onReact)
            action("Reply", symbol: "arrowshape.turn.up.left", id: "friends.message.reply", perform: onReply)
            action("Where’d you get this?", symbol: "questionmark.bubble", id: "friends.message.askWhere", perform: onAskWhere)
        }
        .accessibilityElement(children: .contain)
    }

    private func action(_ title: String, symbol: String, id: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Label(title, systemImage: symbol)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityIdentifier(id)
    }
}

struct FriendReactionPicker: View {
    let selected: StyleFriendReactionKind?
    let onSelect: (StyleFriendReactionKind?) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("selectedAppTheme") private var selectedAppTheme = StyleMatchAppTheme.system.rawValue
    @AppStorage("styleMatchAppearanceMode") private var appearanceMode = StyleMatchAppearanceMode.manual.rawValue
    @AppStorage("styleMatchAdaptiveTheme") private var adaptiveTheme = ""

    private var themeTokens: StyleMatchThemeTokens {
        StyleMatchAppearanceResolver.resolve(
            modeRawValue: appearanceMode,
            selectedThemeRawValue: selectedAppTheme,
            adaptiveThemeRawValue: adaptiveTheme
        ).theme.tokens(for: .profile)
    }

    var body: some View { ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 8) { ForEach(StyleFriendReactionKind.allCases, id: \.self) { reaction in Button { onSelect(selected == reaction ? nil : reaction) } label: { VStack(spacing: 2) { Text(reaction.emoji).font(.title2); Text(reaction.displayName).font(.caption2).lineLimit(1) }.frame(minWidth: 52, minHeight: 54).padding(.horizontal, 4).background(selected == reaction ? themeTokens.socialAccent.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous)).scaleEffect(selected == reaction && !reduceMotion ? 1.08 : 1) }.buttonStyle(.plain).accessibilityLabel(reaction.displayName).accessibilityHint(selected == reaction ? "Selected. Activate to remove." : "Activate to select.").accessibilityAddTraits(selected == reaction ? .isSelected : []) } }.padding(14) }.background(themeTokens.elevatedCardBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous)).accessibilityLabel("Message reactions").accessibilityHint("Swipe to see all seven reactions.") }
}

struct FriendReactionSummary: View {
    let summary: StyleFriendReactionSummary
    var body: some View { ViewThatFits(in: .horizontal) { HStack(spacing: 8) { reactionPills }; VStack(alignment: .leading, spacing: 5) { reactionPills } }.accessibilityElement(children: .contain) }
    @ViewBuilder private var reactionPills: some View { ForEach(summary.topReactions(), id: \.kind) { item in Text("\(item.kind.emoji) \(item.count)").font(.caption.weight(.medium)).padding(.horizontal, 8).padding(.vertical, 5).background(item.kind == summary.viewerReaction ? Color.purple.opacity(0.18) : Color.primary.opacity(0.06), in: Capsule()).accessibilityElement(children: .ignore).accessibilityLabel("\(item.kind.displayName), \(item.count) reactions\(item.kind == summary.viewerReaction ? ", selected" : "")") } }
}

struct FriendReplyPreview: View {
    let preview: StyleFriendsFriendMessageParentPreview
    var body: some View { Text(preview.presentationText).font(.caption).foregroundStyle(.secondary).lineLimit(2).padding(9).background(Color.indigo.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous)).accessibilityLabel("Reply preview. \(preview.presentationText)") }
}

struct FriendChatComposer: View {
    @Binding var draft: String
    @Binding var replyTarget: StyleFriendsFriendMessagePresentation?
    @FocusState.Binding var isFocused: Bool
    let isSending: Bool
    let isAvailable: Bool
    let hasFailedSend: Bool
    let attachmentsAvailable: Bool
    @Binding var selectedAttachmentPhoto: PhotosPickerItem?
    let pendingAttachmentPhoto: Data?
    let pendingShare: StyleFriendsDMPreparedShare?
    let onRemoveAttachment: () -> Void
    let onChooseShare: (StyleFriendsDMShareEligibilityAuthority.Kind) -> Void
    let onRemoveShare: () -> Void
    let onSend: () -> Void
    private let shortcuts = ["🔥", "✨", "👗", "👟", "👜", "💄", "🛍️", "💯"]
    @State private var showingFashionShortcuts = false
    @AppStorage("selectedAppTheme") private var selectedAppTheme = StyleMatchAppTheme.system.rawValue
    @AppStorage("styleMatchAppearanceMode") private var appearanceMode = StyleMatchAppearanceMode.manual.rawValue
    @AppStorage("styleMatchAdaptiveTheme") private var adaptiveTheme = ""

    private var themeTokens: StyleMatchThemeTokens {
        StyleMatchAppearanceResolver.resolve(
            modeRawValue: appearanceMode,
            selectedThemeRawValue: selectedAppTheme,
            adaptiveThemeRawValue: adaptiveTheme
        ).theme.tokens(for: .profile)
    }

    var body: some View {
        VStack(spacing: 6) {
            if let target = replyTarget {
                HStack(spacing: 8) {
                    Image(systemName: "arrowshape.turn.up.left.fill").font(.caption).foregroundStyle(themeTokens.socialAccent)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Replying to \(target.senderDisplayName)").font(.caption.weight(.semibold))
                        Text(target.deletedOrUnavailable ? "Original message unavailable" : target.renderedText).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Button { replyTarget = nil } label: { Image(systemName: "xmark.circle.fill").font(.body) }
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityLabel("Cancel reply")
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(themeTokens.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal)
                .accessibilityElement(children: .combine)
            }

            if let pendingAttachmentPhoto {
                HStack(spacing: 8) {
                    attachmentThumbnail(data: pendingAttachmentPhoto)
                    Text("Photo attached").font(.caption.weight(.semibold)).lineLimit(1)
                    Spacer(minLength: 4)
                    Button { onRemoveAttachment() } label: { Image(systemName: "xmark.circle.fill") }
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityLabel("Remove attached photo")
                }
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(themeTokens.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal)
                .accessibilityElement(children: .combine)
            }

            if let share = pendingShare {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(themeTokens.socialAccent)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(share.snapshot.title).font(.caption.weight(.semibold)).lineLimit(1)
                        if let score = share.snapshot.score { Text("KigoStylist score \(score)").font(.caption2).foregroundStyle(.secondary) }
                    }
                    Spacer(minLength: 4)
                    Button { onRemoveShare() } label: { Image(systemName: "xmark.circle.fill") }
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityLabel("Remove scan share")
                }
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(themeTokens.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal)
                .accessibilityElement(children: .combine)
            }

            if showingFashionShortcuts {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(shortcuts, id: \.self) { emoji in
                            Button(emoji) { draft.append(emoji) }
                                .font(.title3)
                                .frame(minWidth: 44, minHeight: 44)
                                .accessibilityLabel("Insert \(emoji)")
                        }
                    }
                    .padding(.horizontal)
                }
            }

            HStack(spacing: 10) {
                PhotosPicker(selection: $selectedAttachmentPhoto, matching: .images, photoLibrary: .shared()) {
                    Image(systemName: pendingAttachmentPhoto == nil ? "plus.circle" : "paperclip.circle.fill")
                }
                .buttonStyle(.bordered)
                .frame(minWidth: 44, minHeight: 44)
                .disabled(!isAvailable || isSending || !attachmentsAvailable)
                .accessibilityLabel(pendingAttachmentPhoto == nil ? "Add photo attachment" : "Change attachment photo")
                .accessibilityHint(attachmentsAvailable ? "Selects one photo for this private Style Friends conversation." : "Attachments are unavailable in this build.")
                Menu {
                    Button("Saved Scan") { onChooseShare(.scan) }
                        .accessibilityHint("Choose a saved scan to share privately.")
                    Button("Saved Score") { onChooseShare(.score) }
                        .accessibilityHint("Choose a saved KigoStylist score to share privately.")
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .frame(minWidth: 44, minHeight: 44)
                .disabled(!isAvailable || isSending || !attachmentsAvailable)
                .accessibilityLabel("Conversation options")
                .accessibilityHint("Add a photo or a Saved Scan. Current Scan and Score are available from a completed Scan Result.")
                Button { showingFashionShortcuts.toggle() } label: { Image(systemName: "sparkles") }
                    .buttonStyle(.bordered)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Fashion expression shortcuts")
                    .accessibilityValue(showingFashionShortcuts ? "Shown" : "Hidden")

                TextField("Message", text: $draft, axis: .vertical)
                    .focused($isFocused)
                    .lineLimit(1...4)
                    .submitLabel(.send)
                    .onSubmit { if canSend { onSend() } }
                    .padding(12)
                    .background(themeTokens.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .layoutPriority(2)
                    .frame(minWidth: 96, maxWidth: .infinity)
                    .disabled(!isAvailable || isSending)
                    .accessibilityLabel("Message composer")
                    .accessibilityHint(isAvailable ? "Type a message to your Style Friend." : "Messaging is temporarily unavailable.")

                Button(action: onSend) {
                    Text(isSending ? "Sending…" : "Send")
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                    .buttonStyle(.borderedProminent)
                    .tint(themeTokens.socialAccent)
                    .frame(width: 64).frame(minHeight: 44)
                    .fixedSize(horizontal: true, vertical: false)
                    .disabled(!canSend)
                    .accessibilityHint(sendAccessibilityHint)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .background(themeTokens.elevatedCardBackground)
    }

    private var canSend: Bool {
        isAvailable && !isSending && !hasFailedSend && (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || pendingAttachmentPhoto != nil || pendingShare != nil)
    }

    private var sendAccessibilityHint: String {
        if isSending { return "Your message is sending." }
        if hasFailedSend { return "Retry or discard the unsent message before sending another." }
        if !isAvailable { return "Messaging is temporarily unavailable." }
        return "Sends your message to this Style Friend."
    }

    @ViewBuilder private func attachmentThumbnail(data: Data) -> some View {
        if let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFill().frame(width: 36, height: 36).clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        } else {
            Image(systemName: "photo.fill").frame(width: 36, height: 36).foregroundStyle(.secondary)
        }
    }
}

struct SharedOutfitMessageCard: View {
    let outfit: StyleFriendsSharedOutfitMessagePresentation
    let onReply: () -> Void
    let onReact: () -> Void
    let onAskWhere: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("KIGOSTYLIST LOOK")
                    .font(.caption2.weight(.black))
                    .tracking(1.0)
                    .foregroundStyle(StyleMatchPremiumPalette.champagneSoft)
                Spacer()
                Image(systemName: "hanger")
                    .foregroundStyle(StyleMatchPremiumPalette.champagneSoft)
                    .accessibilityHidden(true)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(StyleMatchPremiumPalette.panelRaised)
                Image(systemName: "tshirt.fill")
                    .font(.largeTitle)
                    .foregroundStyle(StyleMatchPremiumPalette.champagneSoft.opacity(0.82))
            }
            .frame(height: 142)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(StyleMatchPremiumPalette.border, lineWidth: 1)
            )
            .accessibilityLabel(outfit.imageProjectionLabel ?? "Shared outfit projection")

            HStack(alignment: .firstTextBaseline) {
                Text(outfit.imageProjectionLabel ?? "Shared outfit")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                if let score = outfit.scoreSnapshot {
                    Text("\(score)/100")
                        .font(.headline.weight(.black))
                        .foregroundStyle(StyleMatchPremiumPalette.champagneSoft)
                }
            }

            if outfit.scoreSnapshot != nil {
                Text(outfit.contextLabel ?? "Score when shared")
                    .font(.caption)
                    .foregroundStyle(StyleMatchPremiumPalette.mutedText)
            }

            if let caption = outfit.caption {
                Text(caption)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.88))
            }

            HStack {
                Button("React", action: onReact)
                Button("Reply", action: onReply)
                Button("Where’d you get this?", action: onAskWhere)
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.bordered)
            .tint(StyleMatchPremiumPalette.champagneSoft)
        }
        .padding(14)
        .background(StyleMatchPremiumPalette.panel, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(StyleMatchPremiumPalette.champagne.opacity(0.20), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Shared outfit message")
        .accessibilityAction(named: "Reply", onReply)
        .accessibilityAction(named: "React", onReact)
        .accessibilityAction(named: "Where’d you get this?", onAskWhere)
    }
}

@MainActor final class StyleFriendsDMAttachmentImageLoader: ObservableObject {
    enum State: Equatable { case idle, loading, loaded(Data), failed, retrying }
    @Published private(set) var state: State = .idle
    private let service: any StyleFriendsDirectMessageServing
    private var task: Task<Void, Never>?
    private static var cache: [String: Data] = [:]
    init(service: any StyleFriendsDirectMessageServing) { self.service = service }
    func load(conversation: StyleFriendsOpaqueRouteReference, attachment: StyleFriendsOpaqueRouteReference) async {
        let key = conversation.value + ":" + attachment.value
        if let data = Self.cache[key] { state = .loaded(data); return }
        guard task == nil else { return }
        state = state == .failed ? .retrying : .loading
        task = Task { [weak self] in
            defer { self?.task = nil }
            do { let data = try await service.attachmentImage(conversation: conversation, attachment: attachment); guard UIImage(data: data) != nil else { throw StyleFriendsDMError.invalidResponse }; Self.cache[key] = data; state = .loaded(data) }
            catch { state = .failed }
        }
        await task?.value
    }
    deinit { task?.cancel() }
}

/// This card renders only the Worker-issued immutable snapshot. It deliberately
/// has no route to the sender's source scan, Closet, CloudKit record, or photo URL.
private struct StyleFriendsDMAttachmentCard: View {
    let attachment: StyleFriendsDMAttachment
    let unavailable: Bool
    let directMessages: any StyleFriendsDirectMessageServing
    let conversation: StyleFriendsOpaqueRouteReference
    @StateObject private var loader: StyleFriendsDMAttachmentImageLoader
    init(attachment: StyleFriendsDMAttachment, unavailable: Bool, directMessages: any StyleFriendsDirectMessageServing, conversation: StyleFriendsOpaqueRouteReference) { self.attachment=attachment; self.unavailable=unavailable; self.directMessages=directMessages; self.conversation=conversation; _loader=StateObject(wrappedValue: StyleFriendsDMAttachmentImageLoader(service: directMessages)) }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(attachment.snapshot == nil ? "STYLE FRIENDS PHOTO" : "KIGOSTYLIST LOOK")
                    .font(.caption2.weight(.black))
                    .tracking(1.0)
                    .foregroundStyle(StyleMatchPremiumPalette.champagneSoft)
                Spacer()
                Image(systemName: icon)
                    .foregroundStyle(StyleMatchPremiumPalette.champagneSoft)
                    .accessibilityHidden(true)
            }

            Text(title)
                .font(.headline)
                .foregroundStyle(.white)

            if unavailable || attachment.state != "active" {
                Text("This shared item is unavailable.")
                    .font(.caption)
                    .foregroundStyle(StyleMatchPremiumPalette.mutedText)
            } else {
                if attachment.imageAttachmentReference != nil {
                    // Read through the authorized parent share, never a private draft photo.
                    let reference = attachment.attachmentReference
                    switch loader.state {
                    case .loaded(let data) where UIImage(data: data) != nil:
                        Image(uiImage: UIImage(data: data)!)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 260)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .accessibilityLabel("Shared photo")
                    case .loading, .retrying:
                        ProgressView("Loading photo…")
                            .tint(StyleMatchPremiumPalette.champagneSoft)
                    case .failed:
                        Button("Retry photo") { Task { await loader.load(conversation: conversation, attachment: reference) } }
                            .buttonStyle(.bordered)
                            .tint(StyleMatchPremiumPalette.champagneSoft)
                    default:
                        ProgressView()
                            .tint(StyleMatchPremiumPalette.champagneSoft)
                            .task { await loader.load(conversation: conversation, attachment: reference) }
                    }
                }

                if let snapshot = attachment.snapshot {
                    HStack(alignment: .firstTextBaseline) {
                        if let score = snapshot.score {
                            Text("\(score)")
                                .font(.system(size: 34, weight: .black, design: .rounded))
                                .foregroundStyle(StyleMatchPremiumPalette.champagneSoft)
                            Text("/100")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(StyleMatchPremiumPalette.mutedText)
                        }
                        Spacer()
                        if let occasion = snapshot.occasion {
                            Label(occasion, systemImage: "calendar")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(StyleMatchPremiumPalette.mutedText)
                        }
                    }

                    if let classification = snapshot.classification {
                        if OutfitCategory(rawValue: classification) != nil {
                            Text("Classification: \(classification)")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(StyleMatchPremiumPalette.mutedText)
                                .accessibilityLabel("Classification \(classification)")
                        } else {
                            // A newer Worker value is not a reason to invent a
                            // local mapping. Keep the legacy card usable while
                            // truthfully withholding an unknown classification.
                            Text("Classification unavailable")
                                .font(.caption)
                                .foregroundStyle(StyleMatchPremiumPalette.mutedText)
                        }
                    }

                    Text(snapshot.summary)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.88))
                        .lineLimit(3)
                } else if attachment.imageAttachmentReference == nil {
                    Text("Photo unavailable")
                        .font(.caption)
                        .foregroundStyle(StyleMatchPremiumPalette.mutedText)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: 310, alignment: .leading)
        .background(StyleMatchPremiumPalette.panel, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(StyleMatchPremiumPalette.champagne.opacity(0.20), lineWidth: 1)
        )
        .onAppear { StyleFriendsDMAttachmentDiagnostics.record("ATTACHMENT_RENDER", unavailable || attachment.state != "active" ? "UNAVAILABLE" : "RENDERED") }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(unavailable || attachment.state != "active" ? "Unavailable." : "Shared privately in this conversation.")")
    }
    private var title: String { attachment.snapshot?.title ?? (attachment.kind == .photo ? "Photo" : "Shared style item") }
    private var icon: String { switch attachment.kind { case .photo: "photo"; case .scanSnapshot: "viewfinder"; case .scoreSnapshot: "checkmark.seal"; case .outfitSnapshot: "hanger" } }
}

/// Payload-independent destination selection for Style Friends shares.  The
/// authenticated conversation endpoint is the authority for both membership
/// and block state; this view neither creates conversations nor accepts raw
/// identifiers from the user.
struct StyleFriendsDMDestinationPicker: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: StyleFriendsDMDestinationPickerModel
    let onSelect: (StyleFriendsDMDestination) -> Void

    init(
        service: any StyleFriendsDirectMessageServing,
        onSelect: @escaping (StyleFriendsDMDestination) -> Void
    ) {
        _model = StateObject(wrappedValue: StyleFriendsDMDestinationPickerModel(service: service))
        self.onSelect = onSelect
    }

    var body: some View {
        NavigationStack {
            Group {
                if model.isLoading && model.destinations.isEmpty {
                    ProgressView("Loading Style Friends…")
                } else if let error = model.error {
                    StyleFriendsDMDestinationEmptyState(
                        title: "Style Friends unavailable",
                        symbol: "person.crop.circle.badge.exclamationmark",
                        detail: error
                    )
                } else if model.destinations.isEmpty {
                    StyleFriendsDMDestinationEmptyState(
                        title: "No share destinations",
                        symbol: "person.2.slash",
                        detail: "Accepted Style Friends conversations appear here."
                    )
                } else {
                    List(model.destinations) { destination in
                        Button {
                            onSelect(destination)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "person.crop.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.tint)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(destination.recipientDisplayName)
                                        .font(.headline)
                                    Text("Authorized Style Friends conversation")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .accessibilityLabel("Share with \(destination.recipientDisplayName)")
                        .accessibilityHint("Selects this authorized Style Friends conversation. No message is sent yet.")
                    }
                }
            }
            .navigationTitle("Share to Style Friends")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityHint("Closes destination selection without sending or saving anything.")
                }
            }
        }
        .task { await model.load() }
    }
}

private struct StyleFriendsDMDestinationEmptyState: View {
    let title: String
    let symbol: String
    let detail: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

@MainActor
private final class StyleFriendsDMDestinationPickerModel: ObservableObject {
    @Published private(set) var destinations: [StyleFriendsDMDestination] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?

    private let service: any StyleFriendsDirectMessageServing

    init(service: any StyleFriendsDirectMessageServing) {
        self.service = service
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            // This endpoint is account-scoped and its response has already
            // excluded blocked and unauthorized relationships on the Worker.
            let page = try await service.conversations(cursor: nil)
            destinations = page.items.compactMap(StyleFriendsDMDestination.init(authorizedConversation:))
            error = nil
        } catch {
            destinations = []
            self.error = "Your authorized Style Friends conversations could not be loaded."
        }
    }
}

/// The local preview is a frozen destination plus the immutable share payload.
/// It contains no Saved Scan identifier and is intentionally separate from the
/// later delivery lifecycle.
struct StyleFriendsDMTransientSharePreviewDraft: Identifiable, Equatable {
    let id: UUID
    let destination: StyleFriendsDMDestination
    let share: StyleFriendsDMPreparedShare

    init(destination: StyleFriendsDMDestination, share: StyleFriendsDMPreparedShare) {
        self.id = UUID()
        self.destination = destination
        self.share = share
    }
}

enum StyleFriendsDMShareNoteValidation {
    /// Reuses the existing immutable snapshot text bound. Unicode is retained
    /// exactly as entered; no case-folding, transliteration, or normalization
    /// is applied in this presentation-only step.
    static let maximumCharacterCount = 280

    static func isValid(_ note: String) -> Bool {
        note.isEmpty || (note.count <= maximumCharacterCount && !note.unicodeScalars.contains(where: { $0.properties.generalCategory == .control && $0 != "\n" && $0 != "\r" && $0 != "\t" }))
    }

    static func optionalNote(from note: String) -> String? {
        note.isEmpty ? nil : note
    }
}

/// Review-only UI for a current-result Style Friends share.  It does not know
/// about transport, persistence, or scan storage; Send emits a typed value to
/// the caller and Cancel only dismisses this in-memory preview.
struct StyleFriendsDMTransientSharePreview: View {
    @Environment(\.dismiss) private var dismiss
    let draft: StyleFriendsDMTransientSharePreviewDraft
    @ObservedObject var dispatch: StyleFriendsDMTransientShareDispatchCoordinator
    let onConfirmedSend: () -> Void
    let onCancel: () -> Void
    @State private var note = ""

    private var noteIsValid: Bool { StyleFriendsDMShareNoteValidation.isValid(note) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Sharing with")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(draft.destination.recipientDisplayName)
                            .font(.title3.weight(.semibold))
                        Text("Authorized Style Friends conversation")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if let data = draft.share.imagePreview, let image = UIImage(data: data) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .accessibilityLabel("Current scan image")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        if let score = draft.share.snapshot.score {
                            Label("KigoStylist score \(score)", systemImage: "checkmark.seal")
                                .font(.headline)
                        }
                        if let classification = draft.share.snapshot.classification {
                            Text("Classification: \(classification)")
                                .font(.subheadline.weight(.semibold))
                                .accessibilityLabel("Classification \(classification)")
                        }
                        Text(draft.share.snapshot.summary)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("KigoStylist summary. \(draft.share.snapshot.summary)")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Optional note")
                            .font(.headline)
                        TextEditor(text: $note)
                            .frame(minHeight: 96)
                            .padding(8)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.35)))
                            .accessibilityLabel("Optional note")
                            .accessibilityHint("Optional note for this Style Friends share. It does not change the KigoStylist summary.")
                        Text("\(note.count)/\(StyleFriendsDMShareNoteValidation.maximumCharacterCount)")
                            .font(.caption)
                            .foregroundStyle(noteIsValid ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
                        if !noteIsValid {
                            Text("Notes are limited to \(StyleFriendsDMShareNoteValidation.maximumCharacterCount) characters and cannot contain control characters.")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }

                    if let failure = dispatch.failedOperation {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(StyleFriendsDMPresentationMapper.userMessage(for: failure.record.error))
                                .font(.subheadline)
                                .foregroundStyle(.red)
                            if failure.canRetry || failure.canRetryAfterReauthentication {
                                Button(failure.canRetryAfterReauthentication ? "Retry after sign-in" : "Retry") {
                                    Task {
                                        if await dispatch.retry() {
                                            onConfirmedSend()
                                            dismiss()
                                        }
                                    }
                                }
                                .disabled(dispatch.isSending)
                                .accessibilityHint("Retries the same frozen share with its original message and share references.")
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding()
            }
            .navigationTitle("Review share")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                    .accessibilityHint("Closes the share preview without sending or saving anything.")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        let intent = StyleFriendsDMTransientShareSendIntent(
                            destination: draft.destination,
                            share: draft.share,
                            note: StyleFriendsDMShareNoteValidation.optionalNote(from: note)
                        )
                        Task {
                            if await dispatch.send(intent) {
                                onConfirmedSend()
                                dismiss()
                            }
                        }
                    }
                    .disabled(!noteIsValid || dispatch.isSending || dispatch.failedOperation != nil)
                    .accessibilityHint("Sends this immutable share through the authenticated Style Friends delivery lifecycle. It does not change the scan result.")
                }
            }
        }
    }
}

private struct StyleFriendsSavedScanPicker: View {
    @Environment(\.dismiss) private var dismiss
    let choices: [StyleFriendsDMShareEligibilityAuthority.Selection]
    let onSelect: (StyleFriendsDMShareEligibilityAuthority.Selection) -> Void

    var body: some View {
        NavigationStack {
            List(choices) { choice in
                Button {
                    onSelect(choice)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        if let data = choice.imagePreview, let image = UIImage(data: data) {
                            Image(uiImage: image).resizable().scaledToFill().frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        } else {
                            Image(systemName: "viewfinder").frame(width: 48, height: 48).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(choice.title).font(.headline).lineLimit(1)
                            if let score = choice.score { Text("KigoStylist score \(score)").font(.subheadline.weight(.semibold)) }
                            if let occasion = choice.occasion { Text(occasion).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
                .accessibilityLabel("Share \(choice.title) with Style Friend")
                .accessibilityHint("Creates an immutable private scan snapshot. It does not modify the saved scan.")
            }
            .navigationTitle(choices.first?.kind == .score ? "Share Saved Score" : "Share Saved Scan")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}


private struct ChatUnavailableState: View { let icon: String; let title: String; let detail: String; var body: some View { VStack(spacing: 12) { Image(systemName: icon).font(.title2).foregroundStyle(.secondary); Text(title).font(.headline); Text(detail).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center) }.frame(maxWidth: .infinity).padding(24).appCard(.profile, radius: 22).accessibilityElement(children: .combine) } }
private struct StyleFriendsChatAvatar: View { let label: String; var size: CGFloat = 44; var body: some View { ZStack { Circle().fill(LinearGradient(colors: [KigoStyleFriendsPalette.soft, KigoStyleFriendsPalette.accent.opacity(0.22)], startPoint: .topLeading, endPoint: .bottomTrailing)); Text(String(label.prefix(1)).uppercased()).font(.system(size: size * 0.40, weight: .bold)).foregroundStyle(KigoStyleFriendsPalette.accent) }.frame(width: size, height: size).accessibilityHidden(true) } }

#if DEBUG && targetEnvironment(simulator)
#Preview("Style Friends chat fixture — preview/test only") { NavigationStack { FriendChatView(conversation: StyleFriendsChatPresentationFixtures.jordan, state: .populated, messages: StyleFriendsChatPresentationFixtures.messages) } }
#endif
