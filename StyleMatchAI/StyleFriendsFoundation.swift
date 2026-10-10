import Foundation
import Combine

struct StyleFriendsSubmissionSnapshot: Equatable, Sendable {
    let text: String
    let photo: Data?
    let share: StyleFriendsDMPreparedShare?
    let reply: StyleFriendsOpaqueRouteReference?
    func matches(text: String, photo: Data?, reply: StyleFriendsOpaqueRouteReference?) -> Bool { self.text == text.trimmingCharacters(in: .whitespacesAndNewlines) && self.photo == photo && self.reply == reply }
}

protocol StyleFriendsAttachmentLifecycleServing {
    func send(conversation: StyleFriendsOpaqueRouteReference, draft: StyleFriendsDMSendDraft) async throws -> StyleFriendsDMMessage
    func uploadAttachmentPhoto(conversation: StyleFriendsOpaqueRouteReference, jpeg: Data, operation: StyleFriendsDMOperationContext?) async throws -> StyleFriendsDMAttachment
    func associateAttachment(conversation: StyleFriendsOpaqueRouteReference, attachment: StyleFriendsOpaqueRouteReference, message: StyleFriendsOpaqueRouteReference, operation: StyleFriendsDMOperationContext?) async throws -> StyleFriendsDMAttachment
    func operationStatus(context: StyleFriendsDMOperationContext) async throws -> StyleFriendsDMOperationStatus
}

protocol StyleFriendsPreparedShareServing {
    func send(conversation: StyleFriendsOpaqueRouteReference, draft: StyleFriendsDMSendDraft) async throws -> StyleFriendsDMMessage
    func uploadAttachmentPhoto(conversation: StyleFriendsOpaqueRouteReference, jpeg: Data, operation: StyleFriendsDMOperationContext?) async throws -> StyleFriendsDMAttachment
    func createAttachmentSnapshot(conversation: StyleFriendsOpaqueRouteReference, kind: StyleFriendsDMAttachmentKind, snapshot: StyleFriendsDMAttachmentSnapshot, imageAttachmentReference: StyleFriendsOpaqueRouteReference?, clientShareReference: String, operation: StyleFriendsDMOperationContext?) async throws -> StyleFriendsDMAttachment
    func associateAttachment(conversation: StyleFriendsOpaqueRouteReference, attachment: StyleFriendsOpaqueRouteReference, message: StyleFriendsOpaqueRouteReference, operation: StyleFriendsDMOperationContext?) async throws -> StyleFriendsDMAttachment
}
struct StyleFriendsPreparedShareUploadFailure: Error, Equatable, Sendable {
    let error: StyleFriendsDMError
    let message: StyleFriendsDMMessage
}

struct StyleFriendsPreparedShareSnapshotFailure: Error, Equatable, Sendable {
    let error: StyleFriendsDMError
    let message: StyleFriendsDMMessage
    let imageReference: StyleFriendsOpaqueRouteReference?
}

struct StyleFriendsPreparedShareAssociationFailure: Error, Equatable, Sendable {
    let error: StyleFriendsDMError
    let message: StyleFriendsDMMessage
    let attachment: StyleFriendsDMAttachment
}

@MainActor
final class StyleFriendsPreparedShareDeliveryAuthority {
    private let service: any StyleFriendsPreparedShareServing
    private let sessionAtCreation: StyleMatchAccountSession?
    private let accountSession: () -> StyleMatchAccountSession?
    init(service: any StyleFriendsPreparedShareServing, accountSession: @escaping () -> StyleMatchAccountSession? = StyleMatchAccountSessionStore.load) { self.service = service; self.accountSession = accountSession; self.sessionAtCreation = accountSession() }
    private func requireSameSession() throws {
        guard accountSession() == sessionAtCreation else { throw StyleFriendsDMError.signInRequired }
    }
    func resumeAssociation(conversation: StyleFriendsOpaqueRouteReference, message: StyleFriendsOpaqueRouteReference, attachment: StyleFriendsOpaqueRouteReference, operation: StyleFriendsDMOperationContext) async throws -> StyleFriendsDMAttachment {
        try requireSameSession()
        return try await service.associateAttachment(conversation: conversation, attachment: attachment, message: message, operation: operation)
    }
    func deliver(conversation: StyleFriendsOpaqueRouteReference, draft: StyleFriendsDMSendDraft, share: StyleFriendsDMPreparedShare, operation: StyleFriendsDMOperationContext) async throws -> StyleFriendsDMAttachment {
        try requireSameSession()
        let message = try await service.send(conversation: conversation, draft: draft)
        return try await resumePhotoUpload(conversation: conversation, message: message, share: share, operation: operation)
    }

    // The staging photo route replays only this operation's exact image bytes.
    // A retained canonical caption is never sent again during this explicit retry.
    func resumePhotoUpload(conversation: StyleFriendsOpaqueRouteReference, message: StyleFriendsDMMessage, share: StyleFriendsDMPreparedShare, operation: StyleFriendsDMOperationContext) async throws -> StyleFriendsDMAttachment {
        let image: StyleFriendsOpaqueRouteReference?
        do {
            try requireSameSession()
            if let jpeg = share.imagePreview {
                image = try await service.uploadAttachmentPhoto(conversation: conversation, jpeg: jpeg, operation: operation).attachmentReference
            } else { image = nil }
        } catch {
            throw StyleFriendsPreparedShareUploadFailure(error: (error as? StyleFriendsDMError) ?? .invalidResponse, message: message)
        }
        return try await resumeSnapshot(conversation: conversation, message: message, share: share, imageReference: image, operation: operation)
    }

    func resumeSnapshot(conversation: StyleFriendsOpaqueRouteReference, message: StyleFriendsDMMessage, share: StyleFriendsDMPreparedShare, imageReference: StyleFriendsOpaqueRouteReference?, operation: StyleFriendsDMOperationContext) async throws -> StyleFriendsDMAttachment {
        let attachment: StyleFriendsDMAttachment
        do {
            try requireSameSession()
            guard share.imagePreview == nil || imageReference != nil else { throw StyleFriendsDMError.invalidResponse }
            StyleFriendsDMAttachmentDiagnostics.record("PREPARED_SHARE_PHASE", "SNAPSHOT_STARTED")
            attachment = try await service.createAttachmentSnapshot(conversation: conversation, kind: share.kind, snapshot: share.snapshot, imageAttachmentReference: imageReference, clientShareReference: share.clientShareReference, operation: operation)
        } catch {
            throw StyleFriendsPreparedShareSnapshotFailure(error: (error as? StyleFriendsDMError) ?? .invalidResponse, message: message, imageReference: imageReference)
        }
        StyleFriendsDMAttachmentDiagnostics.record("PREPARED_SHARE_PHASE", "SNAPSHOT_SUCCEEDED")
        do {
            try requireSameSession()
            StyleFriendsDMAttachmentDiagnostics.record("PREPARED_SHARE_PHASE", "ASSOCIATION_STARTED")
            let associated = try await service.associateAttachment(conversation: conversation, attachment: attachment.attachmentReference, message: message.messageReference, operation: operation)
            StyleFriendsDMAttachmentDiagnostics.record("PREPARED_SHARE_PHASE", "ASSOCIATION_SUCCEEDED")
            return associated
        } catch let error as StyleFriendsDMError {
            StyleFriendsDMAttachmentDiagnostics.record("PREPARED_SHARE_PHASE", "ASSOCIATION_FAILED_\(error.rawValue)")
            throw StyleFriendsPreparedShareAssociationFailure(error: error, message: message, attachment: attachment)
        } catch {
            StyleFriendsDMAttachmentDiagnostics.record("PREPARED_SHARE_PHASE", "ASSOCIATION_FAILED_INVALID_RESPONSE")
            throw StyleFriendsPreparedShareAssociationFailure(error: .invalidResponse, message: message, attachment: attachment)
        }
    }
}
enum StyleFriendsAttachmentOutcomeError: Error, Equatable, Sendable { case confirmedFailure, ambiguousOutcome }
enum StyleFriendsAttachmentDeliveryResult: Equatable, Sendable {
    case confirmedAssociationSuccess
    case confirmedFailure
    case ambiguousOutcome
}

@MainActor final class StyleFriendsAttachmentSendCoordinator: ObservableObject {
    enum State: Equatable { case idle, preparing, sendingMessage, uploading, associating, checkingStatus, sent, failed(String), ambiguous, discarded }
    @Published private(set) var state: State = .idle
    private(set) var pendingPhoto: Data?
    private(set) var pendingShare: StyleFriendsDMPreparedShare?
    private(set) var activeOperation: StyleFriendsDMOperationContext?
    private(set) var activeDraft: StyleFriendsDMSendDraft?
    private(set) var activePhoto: Data?
    private var retainedMessage: StyleFriendsDMMessage?
    private var retainedAttachment: StyleFriendsDMAttachment?
    private var lastFailurePhase: String?
    private var retryInFlight = false
    private var lifecycleInFlight = false
    private var activeAccountBinding: (account: String, environment: String)?
    private let service: any StyleFriendsAttachmentLifecycleServing
    private let conversation: StyleFriendsOpaqueRouteReference
    private let journal: any StyleFriendsAttachmentJournaling
    private let accountScope: () -> (account: String, environment: String)?
    private let phaseObserver: ((String) -> Void)?
    init(service: any StyleFriendsAttachmentLifecycleServing, conversation: StyleFriendsOpaqueRouteReference, journal: any StyleFriendsAttachmentJournaling = StyleFriendsDMOperationJournal.shared, phaseObserver: ((String) -> Void)? = nil, accountScope: @escaping () -> (account: String, environment: String)? = {
        guard let session = StyleMatchAccountSessionStore.load(), session.expiresAt > Date(), let account = session.accountID ?? session.appleSubject, let environment = session.endpointHost else { return nil }
        return (account, environment)
    }) { self.service = service; self.conversation = conversation; self.journal = journal; self.accountScope = accountScope; self.phaseObserver = phaseObserver ?? { marker in StyleFriendsDMAttachmentDiagnostics.record("PHOTO_PHASE", marker) } }
    func operationContext(for draft: StyleFriendsDMSendDraft) throws -> StyleFriendsDMOperationContext? {
        guard let id = draft.operationID else { return nil }
        guard draft.operationProtocolVersion == 1, let scope = draft.operationScopeTag, let record = try journal.load(operationID: id, expectedScopeTag: scope, now: Date()), record.operationType == draft.operationType else { throw StyleFriendsDMError.invalidResponse }
        let context = StyleFriendsDMOperationContext(record: record); activeOperation = context; return context
    }

    func sendPhoto(draft: StyleFriendsDMSendDraft, jpeg: Data, operation: StyleFriendsDMOperationContext?) async -> StyleFriendsAttachmentDeliveryResult {
        guard !lifecycleInFlight else { return .ambiguousOutcome }
        if state == .sent, activeDraft?.clientMessageReference == draft.clientMessageReference {
            guard activeDraft?.text == draft.text, activeDraft?.parentMessageReference == draft.parentMessageReference, activePhoto == jpeg else { return .ambiguousOutcome }
            return .confirmedAssociationSuccess
        }
        guard (state == .idle || state == .discarded || state == .sent) else { return .ambiguousOutcome }
        lifecycleInFlight = true
        defer { lifecycleInFlight = false }
        activeDraft = draft; activePhoto = jpeg
        retainedMessage = nil; retainedAttachment = nil; lastFailurePhase = nil
        state = .preparing
        phaseObserver?("preparation_started")
        guard !jpeg.isEmpty else { state = .failed("preparation"); return .confirmedFailure }
        guard let binding = accountScope() else { state = .failed("preparation"); return .confirmedFailure }
        activeAccountBinding = binding
        let context: StyleFriendsDMOperationContext
        do {
            if let operation { context = operation }
            else {
                let scope = try journal.scopeTag(account: binding.account, environment: binding.environment, conversation: conversation.value)
                let accountEnvironment = try journal.accountEnvironmentTag(account: binding.account, environment: binding.environment)
                let fingerprint = try journal.payloadFingerprint(type: .preparedAttachment, immutablePayload: jpeg)
                let created = try journal.create(accountEnvironmentTag: accountEnvironment, scopeTag: scope, operationType: .preparedAttachment, payloadFingerprint: fingerprint, now: Date(), ttl: 24 * 60 * 60)
                context = .init(record: try journal.transition(operationID: created.operationID, expectedScopeTag: scope, to: .preparingAttachment, opaqueServerReference: nil, now: Date()))
            }
        } catch { state = .failed("preparation"); return .confirmedFailure }
        activeOperation = context; phaseObserver?("preparation_succeeded")
        var failurePhase = "message"
        do {
            state = .sendingMessage
            phaseObserver?("message_started")
            let canonicalDraft = StyleFriendsDMSendDraft(text: draft.text, clientMessageReference: draft.clientMessageReference, parentMessageReference: draft.parentMessageReference, operationID: context.operationID, operationProtocolVersion: context.protocolVersion, operationScopeTag: context.scopeTag, operationType: context.operationType)
            activeDraft = canonicalDraft
            try requireSameAccount()
            let message = try await service.send(conversation: conversation, draft: canonicalDraft)
            retainedMessage = message
            phaseObserver?("message_succeeded")
            failurePhase = "upload"
            state = .uploading
            phaseObserver?("upload_started")
            try requireSameAccount()
            let uploaded = try await service.uploadAttachmentPhoto(conversation: conversation, jpeg: jpeg, operation: context)
            retainedAttachment = uploaded
            phaseObserver?("upload_succeeded")
            failurePhase = "association"
            state = .associating
            phaseObserver?("association_started")
            try requireSameAccount()
            let associated = try await service.associateAttachment(conversation: conversation, attachment: uploaded.attachmentReference, message: message.messageReference, operation: context)
            guard associated.attachmentReference == uploaded.attachmentReference else { throw StyleFriendsDMError.invalidResponse }
            state = .sent
            phaseObserver?("association_succeeded"); phaseObserver?("photo_send_completed")
            return .confirmedAssociationSuccess
        } catch {
            lastFailurePhase = failurePhase
            if failurePhase == "association" {
                if let outcome = error as? StyleFriendsAttachmentOutcomeError, outcome == .confirmedFailure { state = .failed(failurePhase) }
                else { state = .ambiguous }
            } else { state = .failed(failurePhase) }
            phaseObserver?(failurePhase + "_failed")
            if state == .ambiguous {
                return .ambiguousOutcome
            }
            return .confirmedFailure
        }
    }

    /// Fresh composer entry point. Operation creation and journal preparation
    /// are intentionally owned by the coordinator, never by the view.
    func sendNewPhoto(draft: StyleFriendsDMSendDraft, jpeg: Data) async -> StyleFriendsAttachmentDeliveryResult {
        await sendPhoto(draft: draft, jpeg: jpeg, operation: nil)
    }
    func retryPhoto(statusAlreadyConfirmedNotCommitted: Bool = false) async {
        guard !retryInFlight, !lifecycleInFlight else { return }
        let retryable: Bool
        switch state { case .ambiguous: retryable = true; case .failed: retryable = true; default: retryable = false }
        guard let operation = activeOperation, retryable else { return }
        lifecycleInFlight = true
        retryInFlight = true
        defer { retryInFlight = false; lifecycleInFlight = false }
        do { try requireSameAccount() } catch { state = .ambiguous; return }
        if !statusAlreadyConfirmedNotCommitted {
            state = .checkingStatus
            do {
                let status = try await service.operationStatus(context: operation)
                try requireSameAccount()
                guard status.operationID == operation.operationID else { state = .ambiguous; return }
                switch status.outcome {
                case .committed: state = .sent; return
                case .unknown: state = .ambiguous; return
                case .notCommitted: state = .failed(lastFailurePhase ?? "message")
                }
            } catch { state = .ambiguous; return }
        }
        do {
            if lastFailurePhase == "message" {
                guard let draft = activeDraft else { throw StyleFriendsDMError.invalidResponse }
                try requireSameAccount()
                state = .sendingMessage
                retainedMessage = try await service.send(conversation: conversation, draft: draft)
                lastFailurePhase = "upload"
            }
            if lastFailurePhase == "upload" {
                guard let photo = activePhoto else { throw StyleFriendsDMError.invalidResponse }
                try requireSameAccount()
                state = .uploading
                retainedAttachment = try await service.uploadAttachmentPhoto(conversation: conversation, jpeg: photo, operation: operation)
                lastFailurePhase = "association"
            }
            guard lastFailurePhase == "association", let message = retainedMessage, let attachment = retainedAttachment else { throw StyleFriendsDMError.invalidResponse }
            try requireSameAccount()
            state = .associating
            let associated = try await service.associateAttachment(conversation: conversation, attachment: attachment.attachmentReference, message: message.messageReference, operation: operation)
            try requireSameAccount()
            guard associated.attachmentReference == attachment.attachmentReference else { throw StyleFriendsDMError.invalidResponse }
            state = .sent; lastFailurePhase = nil
        } catch {
            state = (error as? StyleFriendsAttachmentOutcomeError) == .confirmedFailure ? .failed(lastFailurePhase ?? "message") : .ambiguous
        }
    }

    /// Applies only an exact authoritative completion already obtained by recovery.
    /// No lookup, journal write, upload, or resend occurs here.
    func applyRecovery(_ resolutions: [StyleFriendsDMOperationRecoveryCoordinator.Resolution]) {
        guard !retryInFlight, !lifecycleInFlight, let operation = activeOperation,
              resolutions.contains(.committed(operation.operationID)) else { return }
        do { try requireSameAccount() } catch { return }
        state = .sent
        lastFailurePhase = nil
    }


    /// Called only after the exact expired journal record has been archived
    /// by the owner's explicit Stop waiting action. No server request occurs.
    func stopWaitingAfterArchiving(operationID: UUID) {
        guard !retryInFlight, !lifecycleInFlight, activeOperation?.operationID == operationID else { return }
        do {
            try requireSameAccount()
            guard let context = activeOperation,
                  try journal.load(operationID: operationID, expectedScopeTag: context.scopeTag, now: Date()) == nil else { return }
        } catch { return }
        activePhoto = nil; activeDraft = nil; activeOperation = nil
        retainedMessage = nil; retainedAttachment = nil; lastFailurePhase = nil
        state = .discarded
    }

    func discardPhoto() {
        guard case .failed = state else { return }
        activePhoto = nil; activeDraft = nil; activeOperation = nil; retainedMessage = nil; retainedAttachment = nil; lastFailurePhase = nil; state = .discarded
    }

    private func requireSameAccount() throws {
        guard let active = activeAccountBinding, let current = accountScope(), active.account == current.account, active.environment == current.environment else { throw StyleFriendsDMError.signInRequired }
    }
}

#if SWIFT_PACKAGE
import SwiftUI

/// SwiftPM intentionally excludes the app-shell Theme Engine so its Foundation
/// verification target stays small. This compile-only shim lets the social and
/// Support source-contract tests compile; the iOS application always resolves
/// these calls through the single production Theme Engine in ContentView.
enum StyleFriendsThemeTestSurface { case profile }

extension View {
    func appScreenBackground(_ surface: StyleFriendsThemeTestSurface) -> some View { self }
    func appCard(_ surface: StyleFriendsThemeTestSurface, radius: CGFloat = 16) -> some View { self }
}
#endif

/// Phase 18038-A only: server-owned relationship state. This does not expose a feed,
/// private scan, Closet, profile, or CloudKit record.
enum StyleFriendRelationshipState: String, Codable, CaseIterable {
    case none
    case outgoingRequest
    case incomingRequest
    case friends
    case blocked
}

/// Opaque, server-issued Style Friends identity. This is neither an account key
/// nor a permission; clients may only serialize and return it to social routes.
struct StyleFriendAccountReference: Codable, Hashable, Identifiable {
    let value: String
    var id: String { value }
    init?(_ value: String) {
        guard value.range(of: "^sf_[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil else { return nil }
        self.value = value
    }
    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        guard let reference = Self(value) else { throw DecodingError.dataCorruptedError(in: try decoder.singleValueContainer(), debugDescription: "Invalid social reference") }
        self = reference
    }
    func encode(to encoder: Encoder) throws { var container = encoder.singleValueContainer(); try container.encode(value) }
}

/// Opaque server-issued identifier used only as a single Friends URL path
/// component. It deliberately has no product-format meaning: URL-unreserved
/// token characters are accepted, while separators, percent escapes,
/// query/fragment markers, whitespace, and control characters are rejected.
struct StyleFriendsOpaqueRouteReference: Codable, Hashable, Identifiable {
    let value: String
    var id: String { value }

    init?(_ value: String) {
        guard value.range(of: "^[A-Za-z0-9_-]{1,128}$", options: .regularExpression) != nil else { return nil }
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        guard let reference = Self(value) else {
            throw DecodingError.dataCorruptedError(in: try decoder.singleValueContainer(), debugDescription: "Invalid opaque route reference")
        }
        self = reference
    }

    func encode(to encoder: Encoder) throws { var container = encoder.singleValueContainer(); try container.encode(value) }
}

/// A server-issued social derivative identifier. It cannot carry a private
/// scan/card/CloudKit path, object-store key, or account identifier.
struct StyleFriendsSocialImageReference: Codable, Hashable, Identifiable {
    let value: String
    var id: String { value }
    init?(_ value: String) {
        guard value.range(of: "^[A-Za-z0-9_-]{24,128}$", options: .regularExpression) != nil else { return nil }
        self.value = value
    }
    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        guard let reference = Self(value) else { throw DecodingError.dataCorruptedError(in: try decoder.singleValueContainer(), debugDescription: "Invalid social image reference") }
        self = reference
    }
}

enum StyleFriendsSocialImageState: Equatable { case unavailable, loading, loaded(Data), revoked, unauthorized, failed }

/// Server-owned lifecycle state for a private staged avatar. A local selection
/// is never represented as active until the Worker returns an opaque reference.
enum StyleFriendAvatarState: String, Codable, Equatable {
    case noPhoto, selecting, cropping, uploading, underReview, active, rejected, failed, replacing, removing
}

struct StyleFriendAvatarUploadResult: Decodable, Equatable {
    let avatarReference: String?
    let avatarState: StyleFriendAvatarState
    enum CodingKeys: String, CodingKey { case avatarReference = "avatar_reference"; case avatarState = "avatar_state" }
}

struct StyleFriendAvatarUploadReceipt: Equatable {
    let result: StyleFriendAvatarUploadResult
    let httpStatus: Int
}

struct StyleFriendsSocialImageFetchReceipt: Equatable {
    let state: StyleFriendsSocialImageState
    let httpStatus: Int?
}

/// Bounded diagnostics for the Debug-only accepted-friend profile route. It
/// never contains a social reference, account identifier, token, URL, or
/// profile value.
struct StyleFriendsProfileFetchReceipt: Equatable {
    let profile: StyleFriendVisibleProfile?
    let httpStatus: Int?
    let diagnostic: String?
}

struct StyleFriendRelationship: Codable, Equatable {
    let state: StyleFriendRelationshipState
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey { case state; case createdAt = "created_at"; case updatedAt = "updated_at" }
}

struct StyleFriendListItem: Codable, Equatable, Identifiable {
    let socialReference: StyleFriendAccountReference
    let displayName: String?
    let avatarReference: String?
    let state: StyleFriendRelationshipState
    let createdAt: Date
    var id: String { socialReference.value }
    enum CodingKeys: String, CodingKey { case socialReference = "social_reference"; case displayName = "display_name"; case avatarReference = "avatar_reference"; case state; case createdAt = "created_at" }

    /// Relationship rows are intentionally a minimal server projection. Once
    /// friendship is confirmed, the authenticated profile route may enrich
    /// that row with the other member's explicitly public social profile.
    /// This never reads from the private StyleMatch profile, Closet, scans,
    /// Calendar, or AI Memory.
    func hydrated(with profile: StyleFriendVisibleProfile) -> Self {
        .init(
            socialReference: socialReference,
            displayName: profile.displayName,
            avatarReference: profile.avatarReference,
            state: state,
            createdAt: createdAt
        )
    }
}

struct StyleFriendListPage: Codable, Equatable { let items: [StyleFriendListItem]; let nextCursor: String?; enum CodingKeys: String, CodingKey { case items; case nextCursor = "next_cursor" } }

/// Each authorized endpoint has its own result. A failed posts/request route
/// must not erase a successfully loaded friend list or masquerade as empty.
struct StyleFriendsListsSnapshot {
    let friends: Result<StyleFriendListPage, Error>
    let incoming: Result<StyleFriendListPage, Error>
    let outgoing: Result<StyleFriendListPage, Error>
    let posts: Result<SharedOutfitPostPage, Error>

    static func load(
        friends: () async throws -> StyleFriendListPage,
        incoming: () async throws -> StyleFriendListPage,
        outgoing: () async throws -> StyleFriendListPage,
        posts: () async throws -> SharedOutfitPostPage
    ) async -> Self {
        async let friendResult = capture(friends)
        async let incomingResult = capture(incoming)
        async let outgoingResult = capture(outgoing)
        async let postResult = capture(posts)
        return await Self(friends: friendResult, incoming: incomingResult, outgoing: outgoingResult, posts: postResult)
    }

    private static func capture<Value>(_ operation: () async throws -> Value) async -> Result<Value, Error> {
        do { return .success(try await operation()) }
        catch { return .failure(error) }
    }
}

/// Explicitly opt-in, authenticated discovery projection. This is never a
/// private StyleMatch profile and never carries an account identifier.
struct StyleFriendDiscoveryItem: Codable, Equatable, Identifiable {
    let socialReference: StyleFriendAccountReference
    let displayName: String
    let avatarReference: String?
    let styleBio: String?
    let styleCategories: [StyleFriendStyleCategory]
    let updatedAt: Date
    var id: String { socialReference.value }
    enum CodingKeys: String, CodingKey { case socialReference = "social_reference"; case displayName = "display_name"; case avatarReference = "avatar_reference"; case styleBio = "style_bio"; case styleCategories = "style_categories"; case updatedAt = "updated_at" }
}

enum StyleFriendRelationshipOperation: String, Codable, CaseIterable {
    case send, accept, decline, cancel, remove, block, unblock
}

/// One row-scoped action authority. It prevents overlapping relationship
/// mutations while leaving every unrelated friend row usable.
enum StyleFriendRelationshipActionState: Equatable {
    case sendingRequest, acceptingRequest, decliningRequest, cancelingRequest, removingFriend, blockingUser, unblockingUser

    init?(operation: StyleFriendRelationshipOperation) {
        switch operation {
        case .send: self = .sendingRequest
        case .accept: self = .acceptingRequest
        case .decline: self = .decliningRequest
        case .cancel: self = .cancelingRequest
        case .remove: self = .removingFriend
        case .block: self = .blockingUser
        case .unblock: self = .unblockingUser
        }
    }

    var visibleLabel: String {
        switch self {
        case .sendingRequest: "Sending…"
        case .acceptingRequest: "Accepting…"
        case .decliningRequest: "Declining…"
        case .cancelingRequest: "Canceling…"
        case .removingFriend: "Removing…"
        case .blockingUser: "Blocking…"
        case .unblockingUser: "Unblocking…"
        }
    }
}

enum StyleFriendsFoundationPolicy {
    /// Social access is deliberately separate from the existing external-card capability.
    static let sharesAreObjectLevelAndExplicit = true
    static let privateScanOrCloudKitAccessIsNeverGrantedByFriendship = true
}

/// Bounded UI contract for the first iOS Friends shell. These labels describe
/// social projections only and intentionally do not carry private-account data.
enum StyleFriendsPresentationContract {
    static let rootSections = [
        "Friends Feed",
        "Friends",
        "Friend Requests",
        "My Shared Looks",
        "My Style Friends Profile"
    ]
    static let incomingRequestActions = ["Accept", "Decline"]
    static let outgoingRequestActions = ["Pending", "Cancel"]
    static let friendActions = ["Remove", "Block", "Unblock"]
    static let sharedLookActions = ["Open Shared Look", "View Friend Profile"]
    static let friendsPostDeletionCopy = "Delete this Friends post and its engagement. Your original photo, score, and saved StyleMatch data remain in your account."
    static let shareRevocationCopy = "This stops access to this shared outfit. Your original photo, score, and saved StyleMatch data remain in your account."
    static let historicalEngagementAfterBlockCopy = "Blocking stops new Friends interaction and hides prior engagement from normal presentation; retained moderation records are not exposed."
}

/// This is an explicit social projection. It is never populated from private Profile storage.
struct StyleFriendVisibleProfile: Codable, Equatable {
    let displayName: String
    let avatarReference: String?
    /// Returned only by the authenticated `/me` projection. Friend-facing
    /// profiles deliberately receive no moderation lifecycle detail.
    let avatarState: StyleFriendAvatarState?
    let styleBio: String?
    let styleCategories: [StyleFriendStyleCategory]
    let createdAt: Date
    let updatedAt: Date
    let isDiscoverable: Bool?
    enum CodingKeys: String, CodingKey { case displayName = "display_name"; case avatarReference = "avatar_reference"; case avatarState = "avatar_state"; case styleBio = "style_bio"; case styleCategories = "style_categories"; case createdAt = "created_at"; case updatedAt = "updated_at"; case isDiscoverable = "is_discoverable" }
}

enum StyleFriendStyleCategory: String, Codable, CaseIterable { case classic, casual, formal, modern, minimal, streetwear, athletic, vintage, workwear, smartCasual }

enum StyleFriendProfileVisibility: String, Codable { case ownerOnly, friendsOnly }

struct StyleFriendProfileUpdate: Codable, Equatable {
    let displayName: String
    let avatarReference: String?
    let styleBio: String?
    let styleCategories: [StyleFriendStyleCategory]
    let isDiscoverable: Bool
    static let maximumDisplayNameUTF16 = 80
    /// Public Style Friends bios are word-bounded. The character ceiling allows
    /// realistic 2,000-word English writing plus Unicode and whitespace while
    /// bounding request, persistence, and moderation work.
    static let maximumStyleBioWords = 2_000
    static let maximumStyleBioUTF16 = 24_000
    static let maximumStyleCategories = 8
    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case avatarReference = "avatar_reference"
        case styleBio = "style_bio"
        case styleCategories = "style_categories"
        case isDiscoverable = "is_discoverable"
    }
}

struct SharedOutfitPost: Codable, Equatable, Identifiable {
    let postReference: StyleFriendsOpaqueRouteReference
    let audience: Audience
    let title: String?
    let caption: String?
    let occasion: String?
    let createdAt: Date
    let updatedAt: Date
    let score: Int?
    let availability: Availability?
    enum Availability: String, Codable { case active, unavailable }
    enum Audience: String, Codable { case friends }
    var id: String { postReference.value }
    enum CodingKeys: String, CodingKey { case postReference = "post_ref"; case audience, title, caption, occasion, score, availability; case createdAt = "created_at"; case updatedAt = "updated_at" }
}

struct SharedOutfitPostPage: Codable, Equatable { let items: [SharedOutfitPost]; let nextCursor: String?; enum CodingKeys: String, CodingKey { case items; case nextCursor = "next_cursor" } }

struct SharedOutfitPostDraft: Codable, Equatable {
    let cardToken: String
    let audience: SharedOutfitPost.Audience = .friends
    let title: String?
    let caption: String?
    let occasion: String?
    static let maximumTitleUTF16 = 120
    static let maximumCaptionUTF16 = 500
}

enum SharedOutfitPostPrivacyContract {
    static let usesBoundedSharedCardRepresentation = true
    static let rawShareTokenIsNeverPersistedInSocialPost = true
    static let privateSourceScanIsNeverSerialized = true
}

struct StyleFriendsFeedItem: Codable, Equatable, Identifiable {
    struct Owner: Codable, Equatable {
        let displayName: String
        let avatarReference: String?
        enum CodingKeys: String, CodingKey {
            case displayName = "display_name"
            case avatarReference = "avatar_reference"
        }
    }
    let postReference: StyleFriendsOpaqueRouteReference
    let owner: Owner
    /// Viewer-safe, opaque owner reference returned beside the public owner
    /// projection. It is deliberately not inferred from a name or image.
    let ownerSocialReference: StyleFriendAccountReference?
    let score: Int?
    /// An opaque, server-authorized social image reference. It never carries
    /// a Closet, scan, account, or storage-object identifier.
    let socialImageReference: String?
    let title: String?
    let caption: String?
    let occasion: String?
    let createdAt: Date
    let updatedAt: Date
    let likeCount: Int?
    let commentCount: Int?
    let viewerHasLiked: Bool?
    /// Server-derived social aggregate. When absent, the client preserves the
    /// legacy Like projection rather than inventing a richer reaction state.
    let reactionSummary: StyleFriendReactionSummary?
    var id: String { postReference.value }
    enum CodingKeys: String, CodingKey { case postReference = "post_ref", owner, ownerSocialReference = "owner_social_reference", score, socialImageReference = "social_image_ref", title, caption, occasion; case createdAt = "created_at"; case updatedAt = "updated_at"; case likeCount = "like_count"; case commentCount = "comment_count"; case viewerHasLiked = "viewer_has_liked"; case reactionSummary = "reaction_summary" }
}

struct StyleFriendsFeedPage: Codable, Equatable { let items: [StyleFriendsFeedItem]; let nextCursor: String?; enum CodingKeys: String, CodingKey { case items; case nextCursor = "next_cursor" } }

enum StyleFriendsFeedState: Equatable {
    case loading, refreshing(StyleFriendsFeedPage), loadingMore(StyleFriendsFeedPage)
    case empty, loaded(StyleFriendsFeedPage), unavailable, signInRequired
    case networkUnavailable, serverUnavailable
}

/// Phase E social engagement remains a bounded server projection. It carries no
/// account identity, private scan reference, share token, or moderation metadata.
struct StyleFriendsEngagement: Codable, Equatable {
    let likeCount: Int
    let viewerHasLiked: Bool
    let commentCount: Int
    enum CodingKeys: String, CodingKey { case likeCount = "like_count"; case viewerHasLiked = "viewer_has_liked"; case commentCount = "comment_count" }
}

struct StyleFriendsComment: Codable, Equatable, Identifiable {
    let commentReference: StyleFriendsOpaqueRouteReference
    let text: String
    /// Viewer-relative only: this supports an own-comment delete affordance
    /// without serializing the comment author's account identity.
    let isOwner: Bool
    let createdAt: Date
    let updatedAt: Date
    let authorDisplayName: String?
    let replyPreview: StyleFriendsReplyPreview?
    /// Server-derived, viewer-relative social projection. It contains no
    /// author/reactor account identity and is never private CloudKit data.
    let reactionSummary: StyleFriendReactionSummary?
    var id: String { commentReference.value }
    enum CodingKeys: String, CodingKey { case commentReference = "comment_ref"; case text; case isOwner = "is_owner"; case createdAt = "created_at"; case updatedAt = "updated_at"; case authorDisplayName = "author_display_name"; case replyPreview = "parent_preview"; case reactionSummary = "reaction_summary" }
}

/// A comment is presented as visible only after the Worker has admitted it.
/// Review and rejection states deliberately carry no comment body back into
/// the social timeline.
enum StyleFriendsCommentDeliveryStatus: String, Codable, Equatable, Sendable {
    case underReview
    case rejected
}

struct StyleFriendsCommentSubmission: Codable, Equatable, Sendable {
    let comment: StyleFriendsComment?
    let deliveryStatus: StyleFriendsCommentDeliveryStatus?

    enum CodingKeys: String, CodingKey {
        case comment
        case deliveryStatus = "delivery_status"
    }
}

/// Legacy server rows using `dislike` decode as the user-facing `notForMe`.
/// Unknown reaction kinds are not interpreted as a known social signal.
enum StyleFriendReactionKind: String, CaseIterable, Hashable, Sendable, Codable {
    case like
    case love
    case fire
    case perfect
    case stylish
    case wantIt
    case notForMe

    var emoji: String {
        switch self {
        case .like: "👍"
        case .love: "❤️"
        case .fire: "🔥"
        case .perfect: "💯"
        case .stylish: "✨"
        case .wantIt: "🛍️"
        case .notForMe: "👎"
        }
    }

    var displayName: String {
        switch self {
        case .like: "Like"
        case .love: "Love"
        case .fire: "Fire"
        case .perfect: "Perfect"
        case .stylish: "Stylish"
        case .wantIt: "Want It"
        case .notForMe: "Not For Me"
        }
    }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let value = Self(wireValue: raw) else {
            throw DecodingError.dataCorruptedError(in: try decoder.singleValueContainer(), debugDescription: "Unknown Style Friends reaction")
        }
        self = value
    }

    fileprivate init?(wireValue raw: String) {
        switch raw {
        case "like": self = .like
        case "love": self = .love
        case "fire": self = .fire
        case "perfect": self = .perfect
        case "stylish": self = .stylish
        case "wantIt", "want_it": self = .wantIt
        case "notForMe", "not_for_me", "dislike": self = .notForMe
        default: return nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// This is a server-derived aggregate plus the viewer's own selected state.
/// Clients never send a counter or reacting account reference.
struct StyleFriendReactionSummary: Codable, Equatable, Sendable {
    let counts: [StyleFriendReactionKind: Int]
    let viewerReaction: StyleFriendReactionKind?

    enum CodingKeys: String, CodingKey { case counts; case viewerReaction = "viewer_reaction" }

    init(counts: [StyleFriendReactionKind: Int], viewerReaction: StyleFriendReactionKind?) {
        self.counts = counts
        self.viewerReaction = viewerReaction
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawCounts = try container.decode([String: Int].self, forKey: .counts)
        var decoded: [StyleFriendReactionKind: Int] = [:]
        for (raw, count) in rawCounts {
            guard let kind = StyleFriendReactionKind(wireValue: raw), count >= 0 else {
                throw DecodingError.dataCorruptedError(forKey: .counts, in: container, debugDescription: "Invalid Style Friends reaction summary")
            }
            decoded[kind, default: 0] += count
        }
        counts = decoded
        viewerReaction = try container.decodeIfPresent(StyleFriendReactionKind.self, forKey: .viewerReaction)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Dictionary(uniqueKeysWithValues: counts.map { ($0.key.rawValue, $0.value) }), forKey: .counts)
        try container.encodeIfPresent(viewerReaction, forKey: .viewerReaction)
    }

    func count(for reaction: StyleFriendReactionKind) -> Int {
        counts[reaction, default: 0]
    }

    /// The compact presentation intentionally omits zero-count reactions.
    func topReactions(limit: Int = 3) -> [(kind: StyleFriendReactionKind, count: Int)] {
        let nonzero: [(kind: StyleFriendReactionKind, count: Int)] = StyleFriendReactionKind.allCases.compactMap { reaction in
            let reactionCount = count(for: reaction)
            return reactionCount > 0 ? (kind: reaction, count: reactionCount) : nil
        }
        let ordered = nonzero.sorted { lhs, rhs in
            lhs.count == rhs.count ? lhs.kind.rawValue < rhs.kind.rawValue : lhs.count > rhs.count
        }
        return Array(ordered.prefix(limit))
    }
}

enum StyleFriendReactionTarget: Hashable, Sendable {
    case post(StyleFriendsOpaqueRouteReference)
    case comment(StyleFriendsOpaqueRouteReference)

    var reference: StyleFriendsOpaqueRouteReference {
        switch self { case let .post(reference), let .comment(reference): reference }
    }
}

struct StyleFriendsReplyPreview: Codable, Equatable, Sendable {
    let parentCommentReference: StyleFriendsOpaqueRouteReference?
    let senderDisplayName: String?
    let text: String?
    let parentAvailable: Bool
    enum CodingKeys: String, CodingKey { case parentCommentReference = "parent_comment_ref"; case senderDisplayName = "sender_display_name"; case text; case parentAvailable = "parent_available" }

    var presentationText: String {
        guard parentAvailable else { return "Original message unavailable" }
        let sender = senderDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let preview = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        return [sender, preview].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: ": ")
    }
}

struct StyleFriendsCommentDraft: Codable, Equatable, Sendable {
    let text: String
    let parentCommentReference: StyleFriendsOpaqueRouteReference?
    enum CodingKeys: String, CodingKey { case text; case parentCommentReference = "parent_comment_ref" }
}

enum StyleFriendsConversationCapability {
    static let typingIndicatorAvailable = false
    static let readReceiptAvailable = false
    static let deliveryReceiptAvailable = false
    static let typingIndicatorReason = "Typing status is unavailable until an authorized ephemeral backend channel exists."
    static let receiptReason = "Delivered and read status are unavailable until the backend provides authoritative receipts."
}

// MARK: - Build 18039 direct-message presentation seam

/// Presentation-only values for the future Worker-owned direct-message service.
/// They are not persisted, do not call a route, and never use AI, CloudKit, a
/// private profile, Closet, scan history, or AI Memory as a data source.
enum StyleFriendsDirectMessagePresentationBoundary {
    static let workerAuthorityRequiredBeforeLiveMessaging = true
    static let fixturesArePreviewAndTestOnly = true
    static let privateCloudKitStorageForbidden = true
    static let profileClosetScanAndAIMemoryIsolationRequired = true
    static let AIStylistConversationReuseForbidden = true
}

enum StyleFriendsConversationPresentationState: Equatable {
    case loading, empty, populated, recoverableError, authorizationUnavailable
}

struct StyleFriendsConversationPresentation: Identifiable, Equatable, Sendable {
    let conversationReference: StyleFriendsOpaqueRouteReference
    let friendSocialReference: StyleFriendAccountReference?
    let friendDisplayName: String
    let avatarReference: String?
    let lastMessagePreview: String?
    let lastActivity: Date?
    var id: String { conversationReference.value }
}

enum StyleFriendsFriendMessageSender: String, Equatable, Sendable { case selfUser, friend }
/// `sending` and `failed` are local presentation states only. The other
/// states originate from the authenticated Worker projection; this UI never
/// invents delivered, read, seen, typing, or presence state.
enum StyleFriendsFriendMessageDelivery: String, Equatable, Sendable {
    case sending, sent, underReview, removed, failed
}

struct StyleFriendsFriendMessageParentPreview: Equatable, Sendable {
    let senderDisplayName: String?
    let text: String?
    let parentAvailable: Bool
    var presentationText: String {
        guard parentAvailable else { return "Original message unavailable" }
        return [senderDisplayName, text].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }.joined(separator: ": ")
    }
}

struct StyleFriendsSharedOutfitMessagePresentation: Equatable, Sendable {
    let imageProjectionLabel: String?
    let scoreSnapshot: Int?
    let caption: String?
    let contextLabel: String?
}

struct StyleFriendsFriendMessagePresentation: Identifiable, Equatable, Sendable {
    let messageReference: StyleFriendsOpaqueRouteReference
    let sender: StyleFriendsFriendMessageSender
    let senderDisplayName: String
    let text: String?
    let timestamp: Date?
    let delivery: StyleFriendsFriendMessageDelivery
    let deletedOrUnavailable: Bool
    let parentPreview: StyleFriendsFriendMessageParentPreview?
    let reactionSummary: StyleFriendReactionSummary?
    let sharedOutfit: StyleFriendsSharedOutfitMessagePresentation?
    let attachment: StyleFriendsDMAttachment?
    var id: String { messageReference.value }
    var renderedText: String { deletedOrUnavailable ? "Original message unavailable" : (text ?? "") }
}

/// Deterministic, explicitly non-runtime samples. The app never substitutes
/// these values for an unavailable conversation service.
enum StyleFriendsChatPresentationFixtures {
    static let label = "Preview/test only"
    static let jordan = StyleFriendsConversationPresentation(
        conversationReference: StyleFriendsOpaqueRouteReference("fixture_jordan")!,
        friendSocialReference: nil,
        friendDisplayName: "Jordan", avatarReference: nil,
        lastMessagePreview: "That bag finishes the whole look ✨", lastActivity: Date(timeIntervalSince1970: 1_800_000_000)
    )
    static let messages: [StyleFriendsFriendMessagePresentation] = [
        .init(messageReference: StyleFriendsOpaqueRouteReference("fixture_message_1")!, sender: .friend, senderDisplayName: "Jordan", text: "Which one do you like better? 🔥", timestamp: Date(timeIntervalSince1970: 1_800_000_000), delivery: .sent, deletedOrUnavailable: false, parentPreview: nil, reactionSummary: .init(counts: [.fire: 8, .love: 4, .stylish: 2], viewerReaction: .fire), sharedOutfit: nil, attachment: nil),
        .init(messageReference: StyleFriendsOpaqueRouteReference("fixture_message_2")!, sender: .selfUser, senderDisplayName: "You", text: "The black jacket with the white sneakers looks cleaner.", timestamp: Date(timeIntervalSince1970: 1_800_000_060), delivery: .sent, deletedOrUnavailable: false, parentPreview: .init(senderDisplayName: "Jordan", text: "That bag finishes the whole look ✨", parentAvailable: true), reactionSummary: nil, sharedOutfit: .init(imageProjectionLabel: "Tonight’s Look", scoreSnapshot: 92, caption: "Black blazer • white top • dark denim", contextLabel: "Score when shared"), attachment: nil),
        .init(messageReference: StyleFriendsOpaqueRouteReference("fixture_message_3")!, sender: .selfUser, senderDisplayName: "You", text: "Where did you get those shoes?", timestamp: Date(timeIntervalSince1970: 1_800_000_120), delivery: .failed, deletedOrUnavailable: false, parentPreview: nil, reactionSummary: nil, sharedOutfit: nil, attachment: nil)
    ]
}

struct StyleFriendsSetReactionRequest: Codable, Equatable, Sendable {
    let reaction: StyleFriendReactionKind?

    enum CodingKeys: String, CodingKey { case reaction }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(reaction, forKey: .reaction)
    }
}

enum StyleFriendsReactionPolicy {
    static let serverAuthoritative = true
    static let maximumActiveReactionsPerViewerAndMessage = 1
    static let privateCloudKitStorageForbidden = true
    static let requiresAuthenticatedAuthorizedVisibleContent = true
    static let requiresCurrentFriendshipAndNoBlock = true
    static let rejectsDeletedRevokedOrUnauthorizedTargets = true
    static let idempotentSetOperationRequired = true
    static let wantItDoesNotCreateShoppingHistory = true
}

/// Pure UI projection only. A failed request must replace this optimistic
/// projection with the last server response, never a local counter mutation.
enum StyleFriendsReactionProjection {
    static func applying(_ kind: StyleFriendReactionKind?, to summary: StyleFriendReactionSummary) -> StyleFriendReactionSummary {
        var counts = summary.counts
        if let current = summary.viewerReaction { counts[current] = max(0, (counts[current] ?? 0) - 1) }
        if let kind { counts[kind] = (counts[kind] ?? 0) + 1 }
        return .init(counts: counts.filter { $0.value > 0 }, viewerReaction: kind)
    }
}

struct StyleFriendsCommentsPage: Codable, Equatable {
    let items: [StyleFriendsComment]
    let nextCursor: String?
    enum CodingKeys: String, CodingKey { case items; case nextCursor = "next_cursor" }
}

enum StyleFriendsReportCategory: String, Codable, CaseIterable {
    case harassment, spam, sexualInappropriate = "sexual_inappropriate", hateAbuse = "hate_abuse", impersonation, unsafeContent = "unsafe_content", other
}

struct StyleFriendsReportDraft: Codable, Equatable {
    let category: StyleFriendsReportCategory
    let detail: String?
    static let maximumDetailUTF16 = 500
}

enum StyleFriendsEngagementPolicy {
    static let maximumCommentUTF16 = 500
    static let commentPageDefault = 20
    static let commentPageMaximum = 50
    static let scoreIsNeverModifiedBySocialEngagement = true
    static let rawAccountIdentifiersAreNeverPresented = true
    static let socialTextIsUntrustedPlainText = true
}

/// Route construction accepts only the opaque-reference type, so callers
/// cannot pass an unvalidated path component into a post or comment action.
enum StyleFriendsRoutePath {
    static func post(_ reference: StyleFriendsOpaqueRouteReference, action: String? = nil) -> String {
        path(["v1", "friends", "posts", reference.value] + (action.map { [$0] } ?? []))
    }

    static func comment(_ reference: StyleFriendsOpaqueRouteReference) -> String {
        path(["v1", "friends", "comments", reference.value])
    }

    static func commentReaction(_ reference: StyleFriendsOpaqueRouteReference) -> String { path(["v1", "friends", "comments", reference.value, "reaction"]) }
    static func socialImage(_ reference: StyleFriendsSocialImageReference) -> String { path(["v1", "friends", "images", reference.value]) }
    static let profileAvatar = "/v1/friends/profile/avatar"

    static func reaction(_ target: StyleFriendReactionTarget) -> String {
        switch target {
        case let .post(reference): return post(reference, action: "reaction")
        case let .comment(reference): return commentReaction(reference)
        }
    }

    private static func path(_ components: [String]) -> String {
        components.reduce(URL(string: "https://stylematch.invalid")!) { url, component in
            url.appendingPathComponent(component)
        }.path
    }
}

/// The concrete transport is intentionally injected by the authenticated account
/// authority. This contract never accepts a caller-supplied actor identifier.
protocol StyleFriendsEngagementServing {
    func like(postReference: StyleFriendsOpaqueRouteReference) async throws -> StyleFriendsEngagement
    func unlike(postReference: StyleFriendsOpaqueRouteReference) async throws -> StyleFriendsEngagement
    func comments(postReference: StyleFriendsOpaqueRouteReference, cursor: String?) async throws -> StyleFriendsCommentsPage
    func addComment(postReference: StyleFriendsOpaqueRouteReference, draft: StyleFriendsCommentDraft) async throws -> StyleFriendsCommentSubmission
    func deleteOwnComment(commentReference: StyleFriendsOpaqueRouteReference) async throws
    func setReaction(target: StyleFriendReactionTarget, reaction: StyleFriendReactionKind?) async throws -> StyleFriendReactionSummary
    func reportPost(postReference: StyleFriendsOpaqueRouteReference, draft: StyleFriendsReportDraft) async throws
    func reportComment(commentReference: StyleFriendsOpaqueRouteReference, draft: StyleFriendsReportDraft) async throws
    func reportUser(friendReference: String, draft: StyleFriendsReportDraft) async throws
}

enum StyleFriendsServiceError: LocalizedError, Equatable {
    case signInRequired, invalidProfile, unavailable, networkUnavailable, invalidResponse, httpStatus(Int)
    var errorDescription: String? { switch self { case .signInRequired: "Sign in with Apple to use Style Friends."; case .invalidProfile: "Check your display name and profile details, then try again."; case .unavailable, .httpStatus: "Style Friends is unavailable right now."; case .networkUnavailable: "Check your connection and try again."; case .invalidResponse: "Style Friends returned an invalid response." } }
}

/// A Debug-only, physical-device acceptance lane. It is deliberately separate
/// from the Simulator fixture harness and never reads or writes the normal
/// account Keychain session, local share-card history, or any private store.
enum StyleFriendsOwnerDeviceAcceptance {
    struct Configuration {
        let baseURL: URL
        let session: StyleMatchAccountSession
        let syntheticCard: CreatedShareableScoreCard?
    }

    enum State {
        case inactive
        case unavailable
        case active(Configuration)

        var configuration: Configuration? {
            guard case let .active(configuration) = self else { return nil }
            return configuration
        }

        var visibleIndicator: String? {
            #if DEBUG && STYLE_FRIENDS_OWNER_DEVICE_ACCEPTANCE
            switch self {
            case .active:
                return "Style Friends Test Environment"
            case .unavailable:
                return "Style Friends Test Environment — session unavailable"
            case .inactive:
                return nil
            }
            #else
            return nil
            #endif
        }
    }

    static func state(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        now: Date = Date()
    ) -> State {
        #if DEBUG && STYLE_FRIENDS_OWNER_DEVICE_ACCEPTANCE
        #if targetEnvironment(simulator)
        return .inactive
        #else
        guard environment["STYLEMATCH_OWNER_DEVICE_ACCEPTANCE_MODE"] == "style-friends-owner-device-acceptance",
              environment[StyleMatchRuntimeEndpoint.overrideEnvironmentKey] == nil,
              let endpoint = endpoint(environment["STYLEMATCH_OWNER_DEVICE_STYLE_FRIENDS_ENDPOINT"]),
              let session = session(environment["STYLEMATCH_OWNER_DEVICE_STYLE_FRIENDS_SYNTHETIC_SESSION"], now: now) else {
            return .unavailable
        }
        return .active(Configuration(
            baseURL: endpoint,
            session: session,
            syntheticCard: card(environment["STYLEMATCH_OWNER_DEVICE_STYLE_FRIENDS_SYNTHETIC_CARD"])
        ))
        #endif
        #else
        return .inactive
        #endif
    }

    private static func endpoint(_ rawValue: String?) -> URL? {
        #if DEBUG && STYLE_FRIENDS_OWNER_DEVICE_ACCEPTANCE
        guard let rawValue,
              let components = URLComponents(string: rawValue.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme?.lowercased() == "https",
              components.user == nil,
              components.password == nil,
              components.port == nil,
              components.query == nil,
              components.fragment == nil,
              components.path.isEmpty || components.path == "/",
              (
                components.host?.lowercased() == AppBackendConfiguration.approvedFriendsAuthTestAPIHost ||
                AppBackendConfiguration.isAuthorizedFriendsStagingHost(components.host)
              ) else {
            return nil
        }
        return components.url
        #else
        return nil
        #endif
    }

    private static func session(_ encoded: String?, now: Date) -> StyleMatchAccountSession? {
        #if DEBUG && STYLE_FRIENDS_OWNER_DEVICE_ACCEPTANCE
        guard let encoded else { return nil }
        let values = encoded.split(separator: "|", maxSplits: 1).map(String.init)
        guard values.count == 2,
              values[0].range(of: "^[A-Za-z0-9_-]{32,128}$", options: .regularExpression) != nil,
              let expiresAt = ISO8601DateFormatter().date(from: values[1]),
              expiresAt > now else {
            return nil
        }
        return StyleMatchAccountSession(token: values[0], expiresAt: expiresAt)
        #else
        return nil
        #endif
    }

    private static func card(_ encoded: String?) -> CreatedShareableScoreCard? {
        #if DEBUG && STYLE_FRIENDS_OWNER_DEVICE_ACCEPTANCE
        guard let encoded else { return nil }
        let values = encoded.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        let score = values.count == 3 && !values[2].isEmpty ? Int(values[2]) : nil
        guard values.count == 3,
              ShareableScoreCardRoute.isSafeToken(values[0]),
              let expiresAt = ISO8601DateFormatter().date(from: values[1]),
              (values[2].isEmpty || score != nil),
              score.map({ (0...100).contains($0) }) ?? true else {
            return nil
        }
        return CreatedShareableScoreCard(
            token: values[0],
            url: URL(string: "https://stylematchpro.com/share/\(values[0])")!,
            createdAt: Date(),
            expiresAt: expiresAt,
            overallScore: score,
            revokedAt: nil
        )
        #else
        return nil
        #endif
    }
}

/// Single authenticated transport boundary. It derives the bearer token only from
/// StyleMatchAccountSessionStore and retains neither response bodies nor account IDs.
struct StyleFriendsService {
    static let requestTimeout: TimeInterval = 10

    private let baseURL: URL
    private let session: URLSession
    private let accountSession: () -> StyleMatchAccountSession?
    private let invalidateAccountSession: () -> Void

    init(
        baseURL: URL? = nil,
        session: URLSession = .shared,
        accountSession: @escaping () -> StyleMatchAccountSession? = StyleMatchAccountSessionStore.load,
        invalidateAccountSession: @escaping () -> Void = StyleMatchAccountSessionStore.delete
    ) {
        self.baseURL = baseURL ?? StyleMatchRuntimeEndpoint.accountResolution()?.baseURL ?? AppBackendConfiguration.production().apiBaseURL
        self.session = session
        self.accountSession = accountSession
        self.invalidateAccountSession = invalidateAccountSession
    }

    var hasValidSession: Bool {
        accountSession()?.expiresAt ?? .distantPast > Date()
    }

    func feed(cursor: String? = nil) async throws -> StyleFriendsFeedPage {
        var path = "/v1/friends/feed"
        if let cursor {
            let encodedCursor = cursor.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            path += "?cursor=\(encodedCursor)"
        }
        return try await send(path: path, method: "GET")
    }
    func socialProfile() async throws -> StyleFriendVisibleProfile? { struct Payload: Decodable { let profile: StyleFriendVisibleProfile? }; let payload: Payload = try await send(path: "/v1/friends/profile/me", method: "GET"); return payload.profile }
    func discoverStyleFriends(query: String) async throws -> [StyleFriendDiscoveryItem] { struct Payload: Decodable { let items: [StyleFriendDiscoveryItem] }; let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""; let payload: Payload = try await send(path: "/v1/friends/discovery?q=\(encoded)", method: "GET"); return payload.items }
    /// The Worker independently verifies that the supplied opaque reference is an
    /// accepted friend before returning this intentionally small social projection.
    func socialProfile(for friend: StyleFriendAccountReference) async throws -> StyleFriendVisibleProfile? { struct Payload: Decodable { let profile: StyleFriendVisibleProfile? }; let payload: Payload = try await send(path: "/v1/friends/profile/\(friend.value)", method: "GET"); return payload.profile }
    func socialProfileReceipt(for friend: StyleFriendAccountReference) async -> StyleFriendsProfileFetchReceipt {
        guard let account = accountSession(), account.expiresAt > Date(),
              let url = URL(string: "/v1/friends/profile/\(friend.value)", relativeTo: baseURL) else {
            return .init(profile: nil, httpStatus: nil, diagnostic: nil)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = Self.requestTimeout
        request.setValue("Bearer \(account.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .init(profile: nil, httpStatus: nil, diagnostic: nil) }
            let diagnostic = Self.safeProfileDiagnostic(http.value(forHTTPHeaderField: "x-style-friends-profile-debug"))
            if http.statusCode == 401 {
                invalidateAccountSession()
                return .init(profile: nil, httpStatus: http.statusCode, diagnostic: diagnostic)
            }
            guard (200..<300).contains(http.statusCode) else { return .init(profile: nil, httpStatus: http.statusCode, diagnostic: diagnostic) }
            struct Payload: Decodable { let profile: StyleFriendVisibleProfile? }
            let profile = try? JSONDecoder.styleFriends.decode(Payload.self, from: data).profile
            return .init(profile: profile, httpStatus: http.statusCode, diagnostic: diagnostic)
        } catch {
            return .init(profile: nil, httpStatus: nil, diagnostic: nil)
        }
    }
    func saveSocialProfile(_ update: StyleFriendProfileUpdate) async throws -> StyleFriendVisibleProfile? { struct Payload: Decodable { let profile: StyleFriendVisibleProfile? }; let payload: Payload = try await send(path: "/v1/friends/profile/me", method: "PUT", body: update); return payload.profile }
    /// Sends image bytes only to the account-authenticated, dedicated social
    /// endpoint. The server supplies any public opaque image reference.
    func uploadProfileAvatar(_ data: Data, mimeType: String) async throws -> StyleFriendAvatarUploadReceipt {
        let response = try await sendRaw(path: StyleFriendsRoutePath.profileAvatar, method: "POST", data: data, mimeType: mimeType, acceptedStatusCodes: [201, 202, 422])
        guard let result = try? JSONDecoder.styleFriends.decode(StyleFriendAvatarUploadResult.self, from: response.0) else { throw StyleFriendsServiceError.invalidResponse }
        return .init(result: result, httpStatus: response.1.statusCode)
    }
    func removeProfileAvatar() async throws { _ = try await sendEmpty(path: StyleFriendsRoutePath.profileAvatar, method: "DELETE") }
    func relationship(target: StyleFriendAccountReference, operation: StyleFriendRelationshipOperation) async throws -> StyleFriendRelationship { struct Payload: Decodable { let relationship: StyleFriendRelationship }; let payload: Payload = try await send(path: "/v1/friends/relationships/\(target.value)/\(operation.rawValue)", method: "POST"); return payload.relationship }
    func listFriends(cursor: String? = nil) async throws -> StyleFriendListPage { try await list("friends", cursor: cursor) }
    func listIncomingRequests(cursor: String? = nil) async throws -> StyleFriendListPage { try await list("incoming", cursor: cursor) }
    func listOutgoingRequests(cursor: String? = nil) async throws -> StyleFriendListPage { try await list("outgoing", cursor: cursor) }
    func listMySharedLooks(cursor: String? = nil) async throws -> SharedOutfitPostPage { try await listPosts(cursor: cursor) }
    func publish(_ draft: SharedOutfitPostDraft) async throws -> SharedOutfitPost { struct Payload: Decodable { let post: SharedOutfitPost }; let payload: Payload = try await send(path: "/v1/friends/posts", method: "POST", body: draft); return payload.post }
    func deletePost(_ reference: StyleFriendsOpaqueRouteReference) async throws { _ = try await sendEmpty(path: StyleFriendsRoutePath.post(reference), method: "DELETE") }
    func like(postReference: StyleFriendsOpaqueRouteReference) async throws -> StyleFriendsEngagement { try await send(path: StyleFriendsRoutePath.post(postReference, action: "like"), method: "POST") }
    func unlike(postReference: StyleFriendsOpaqueRouteReference) async throws -> StyleFriendsEngagement { try await send(path: StyleFriendsRoutePath.post(postReference, action: "like"), method: "DELETE") }
    func comments(postReference: StyleFriendsOpaqueRouteReference, cursor: String? = nil) async throws -> StyleFriendsCommentsPage { try await send(path: cursorPath(StyleFriendsRoutePath.post(postReference, action: "comments"), cursor: cursor), method: "GET") }
    func addComment(postReference: StyleFriendsOpaqueRouteReference, draft: StyleFriendsCommentDraft) async throws -> StyleFriendsCommentSubmission {
        let response = try await sendData(path: StyleFriendsRoutePath.post(postReference, action: "comments"), method: "POST", body: draft, acceptedStatusCodes: [201, 202, 422])
        guard let submission = try? JSONDecoder.styleFriends.decode(StyleFriendsCommentSubmission.self, from: response.0) else { throw StyleFriendsServiceError.invalidResponse }
        return submission
    }
    func deleteOwnComment(commentReference: StyleFriendsOpaqueRouteReference) async throws { _ = try await sendEmpty(path: StyleFriendsRoutePath.comment(commentReference), method: "DELETE") }
    /// Worker contract: authenticate the session, reauthorize post/thread
    /// visibility plus current friendship/block state, reject unavailable
    /// comments, and atomically set/remove the caller's one active reaction.
    func setReaction(target: StyleFriendReactionTarget, reaction: StyleFriendReactionKind?) async throws -> StyleFriendReactionSummary {
        try await send(path: StyleFriendsRoutePath.reaction(target), method: "PUT", body: StyleFriendsSetReactionRequest(reaction: reaction))
    }
    func reportPost(postReference: StyleFriendsOpaqueRouteReference, draft: StyleFriendsReportDraft) async throws { _ = try await sendEmpty(path: StyleFriendsRoutePath.post(postReference, action: "report"), method: "POST", body: draft) }
    func reportComment(commentReference: StyleFriendsOpaqueRouteReference, draft: StyleFriendsReportDraft) async throws { _ = try await sendEmpty(path: StyleFriendsRoutePath.comment(commentReference), method: "POST", body: draft) }
    func reportUser(friendReference: String, draft: StyleFriendsReportDraft) async throws { _ = try await sendEmpty(path: "/v1/friends/users/\(friendReference)/report", method: "POST", body: draft) }
    /// Fetches only an opaque, server-authorized social image projection. The
    /// Worker rechecks friendship, blocking, revocation, and moderation before
    /// it reads R2; a failed or revoked read never falls back to private data.
    func socialImage(_ reference: StyleFriendsSocialImageReference) async -> StyleFriendsSocialImageState {
        await socialImageReceipt(reference).state
    }

    func socialImageReceipt(_ reference: StyleFriendsSocialImageReference) async -> StyleFriendsSocialImageFetchReceipt {
        guard let account = accountSession(), account.expiresAt > Date() else { return .init(state: .unauthorized, httpStatus: nil) }
        guard let url = URL(string: StyleFriendsRoutePath.socialImage(reference), relativeTo: baseURL) else { return .init(state: .failed, httpStatus: nil) }
        var request = URLRequest(url: url)
        request.timeoutInterval = Self.requestTimeout
        request.setValue("Bearer \(account.token)", forHTTPHeaderField: "Authorization")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, response) = try await session.data(for: request); guard let http = response as? HTTPURLResponse else { return .init(state: .failed, httpStatus: nil) }
            if http.statusCode == 401 { invalidateAccountSession() }
            let state: StyleFriendsSocialImageState
            switch http.statusCode { case 200: state = .loaded(data); case 401, 403: state = .unauthorized; case 404: state = .revoked; default: state = .failed }
            return .init(state: state, httpStatus: http.statusCode)
        } catch { return .init(state: .failed, httpStatus: nil) }
    }

    private static func safeProfileDiagnostic(_ value: String?) -> String? {
        #if DEBUG
        guard let value else { return nil }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ=;_")
        guard !value.isEmpty, value.unicodeScalars.allSatisfy(allowed.contains), value.count <= 128 else { return nil }
        return value
        #else
        return nil
        #endif
    }
    private func list(_ route: String, cursor: String?) async throws -> StyleFriendListPage { try await send(path: cursorPath("/v1/friends/relationships/\(route)", cursor: cursor), method: "GET") }
    private func listPosts(cursor: String?) async throws -> SharedOutfitPostPage { try await send(path: cursorPath("/v1/friends/posts/me", cursor: cursor), method: "GET") }
    private func cursorPath(_ path: String, cursor: String?) -> String { guard let cursor else { return path }; return "\(path)?cursor=\(cursor.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }

    private func send<T: Decodable, Body: Encodable>(path: String, method: String, body: Body? = nil) async throws -> T {
        let response = try await sendData(path: path, method: method, body: body); guard let value = try? JSONDecoder.styleFriends.decode(T.self, from: response.0) else { throw StyleFriendsServiceError.invalidResponse }; return value
    }
    private func send<T: Decodable>(path: String, method: String) async throws -> T {
        let response = try await sendData(path: path, method: method, body: Optional<String>.none); guard let value = try? JSONDecoder.styleFriends.decode(T.self, from: response.0) else { throw StyleFriendsServiceError.invalidResponse }; return value
    }
    private func sendEmpty(path: String, method: String) async throws -> HTTPURLResponse { let response: (Data, HTTPURLResponse) = try await sendData(path: path, method: method, body: Optional<String>.none); return response.1 }
    private func sendEmpty<Body: Encodable>(path: String, method: String, body: Body) async throws -> HTTPURLResponse { let response = try await sendData(path: path, method: method, body: body); return response.1 }
    private func sendData<Body: Encodable>(path: String, method: String, body: Body?, acceptedStatusCodes: Set<Int>? = nil) async throws -> (Data, HTTPURLResponse) {
        guard let account = accountSession(), account.expiresAt > Date() else { throw StyleFriendsServiceError.signInRequired }
        guard let url = URL(string: path, relativeTo: baseURL) else { throw StyleFriendsServiceError.unavailable }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = Self.requestTimeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(account.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body { request.httpBody = try JSONEncoder().encode(body); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw StyleFriendsServiceError.invalidResponse }
            if http.statusCode == 401 {
                invalidateAccountSession()
                throw StyleFriendsServiceError.signInRequired
            }
            if http.statusCode == 400 && path == "/v1/friends/profile/me" { throw StyleFriendsServiceError.invalidProfile }
            let accepted = acceptedStatusCodes?.contains(http.statusCode) ?? (200..<300).contains(http.statusCode)
            guard accepted else { throw StyleFriendsServiceError.unavailable }
            return (data, http)
        } catch let error as StyleFriendsServiceError {
            throw error
        } catch {
            throw StyleFriendsServiceError.networkUnavailable
        }
    }
    private func sendRaw(path: String, method: String, data: Data, mimeType: String, acceptedStatusCodes: Set<Int>) async throws -> (Data, HTTPURLResponse) {
        guard let account = accountSession(), account.expiresAt > Date() else { throw StyleFriendsServiceError.signInRequired }
        guard let url = URL(string: path, relativeTo: baseURL) else { throw StyleFriendsServiceError.unavailable }
        var request = URLRequest(url: url); request.httpMethod = method; request.httpBody = data
        request.timeoutInterval = Self.requestTimeout
        request.setValue("Bearer \(account.token)", forHTTPHeaderField: "Authorization")
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (responseData, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw StyleFriendsServiceError.invalidResponse }
            if http.statusCode == 401 {
                invalidateAccountSession()
                throw StyleFriendsServiceError.signInRequired
            }
            guard acceptedStatusCodes.contains(http.statusCode) else { throw StyleFriendsServiceError.httpStatus(http.statusCode) }
            return (responseData, http)
        } catch let error as StyleFriendsServiceError { throw error }
        catch { throw StyleFriendsServiceError.networkUnavailable }
    }
}


private extension JSONDecoder { static var styleFriends: JSONDecoder { let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; return decoder } }
