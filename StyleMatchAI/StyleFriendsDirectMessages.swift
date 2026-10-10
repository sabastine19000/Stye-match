import Foundation
import Combine

/// Bounded owner-beta diagnostics for private DM attachments. Values describe
/// only pipeline stages and status classes; they never retain a token, URL,
/// account identifier, image content, or attachment reference.
enum StyleFriendsDMAttachmentDiagnostics {
    struct Snapshot: Equatable, Sendable {
        var pickerLoad = "NOT_STARTED"
        var normalization = "NOT_STARTED"
        var uploadRequest = "NOT_STARTED"
        var uploadAuth = "NOT_STARTED"
        var uploadHTTPStatus = "NOT_STARTED"
        var uploadResponseDecode = "NOT_STARTED"
        var r2Write = "NOT_REPORTED"
        var attachmentFinalize = "NOT_STARTED"
        var messageLink = "NOT_STARTED"
        var attachmentRender = "NOT_STARTED"
    }

    #if DEBUG || OWNER_BETA
    private static let lock = NSLock()
    private static var latest = Snapshot()

    static func record(_ stage: String, _ value: String) {
        lock.lock(); defer { lock.unlock() }
        switch stage {
        case "PHOTO_PICKER_LOAD": latest.pickerLoad = value
        case "PHOTO_NORMALIZATION": latest.normalization = value
        case "UPLOAD_REQUEST": latest.uploadRequest = value
        case "UPLOAD_AUTH": latest.uploadAuth = value
        case "UPLOAD_HTTP_STATUS": latest.uploadHTTPStatus = value
        case "UPLOAD_RESPONSE_DECODE": latest.uploadResponseDecode = value
        case "R2_WRITE": latest.r2Write = value
        case "ATTACHMENT_FINALIZE": latest.attachmentFinalize = value
        case "DM_MESSAGE_LINK": latest.messageLink = value
        case "ATTACHMENT_RENDER": latest.attachmentRender = value
        default: break
        }
    }

    static var snapshot: Snapshot {
        lock.lock(); defer { lock.unlock() }
        return latest
    }
    #else
    static func record(_: String, _: String) {}
    static var snapshot: Snapshot { .init() }
    #endif
}

/// Content-free, Debug/OwnerBeta operation trace for an owner reproduction. It is
/// intentionally a single in-memory latest value: no message, account,
/// conversation, attachment, URL, response payload, credential, or identifier is
/// persisted or emitted.
enum StyleFriendsDMOperationDiagnostics {
    struct Snapshot: Equatable, Sendable {
        var build = "UNKNOWN"
        var operation = "NOT_STARTED"
        var phase = "NOT_STARTED"
        var httpStatus = "NOT_STARTED"
        var serverCategory = "NOT_REPORTED"
        var reconciliation = "NOT_STARTED"
    }

    #if DEBUG || OWNER_BETA
    private static let lock = NSLock()
    private static var latest = Snapshot()

    static func record(
        operation: String,
        phase: String,
        httpStatus: String = "NOT_REPORTED",
        serverCategory: String = "NOT_REPORTED",
        reconciliation: String? = nil
    ) {
        lock.lock(); defer { lock.unlock() }
        // Preserve a recorded send/recovery failure against unrelated successful reads.
        let deliveryOperations = [
            "text_message", "photo_upload", "score_or_scan_share",
            "attachment_association", "reconciliation"
        ]
        let preservesFailure = deliveryOperations.contains(latest.operation)
            && (latest.serverCategory != "accepted" || latest.reconciliation == "unknown")
            && latest.phase != "NOT_STARTED"
        let unrelatedSuccess = ["other", "recipient_refresh"].contains(operation)
            && serverCategory == "accepted"
        if preservesFailure && unrelatedSuccess { return }

        latest.build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "UNKNOWN"
        latest.operation = ["text_message", "photo_upload", "score_or_scan_share", "attachment_association", "recipient_refresh", "reconciliation", "other"].contains(operation) ? operation : "other"
        latest.phase = ["authentication", "authorization", "transport", "response"].contains(phase) ? phase : "NOT_STARTED"
        latest.httpStatus = Int(httpStatus).map { (100...599).contains($0) ? String($0) : "NOT_REPORTED" } ?? "NOT_REPORTED"
        latest.serverCategory = ["authentication", "authorization", "moderation", "conflict", "feature_unavailable", "transport", "validation", "accepted"].contains(serverCategory) ? serverCategory : "NOT_REPORTED"
        latest.reconciliation = reconciliation.flatMap { ["committed", "not_committed", "unknown"].contains($0) ? $0 : nil } ?? "NOT_STARTED"
    }

    static var snapshot: Snapshot {
        lock.lock(); defer { lock.unlock() }
        return latest
    }
    #else
    static func record(operation _: String, phase _: String, httpStatus _: String = "NOT_REPORTED", serverCategory _: String = "NOT_REPORTED", reconciliation _: String? = nil) {}
    static var snapshot: Snapshot { .init() }
    #endif
}

// Worker-owned direct-message domain contract. This file has no persistence,
// CloudKit, AI, Profile, Closet, Scan, or synthetic-runtime data dependency.
enum StyleFriendsDMError: String, Error, Equatable, Codable {
    case termsAcceptanceRequired, safetyUnavailable, contentNotAllowed, dmUnavailable, signInRequired
    case conversationUnavailable, rateLimited, idempotencyConflict, invalidResponse, networkUnavailable, serviceUnavailable
}

/// Maps only typed transport outcomes to customer-facing conversation states.
/// A server authentication rejection is not a connectivity failure.
enum StyleFriendsDMConversationFailurePresentation: Equatable {
    case signInRequired, networkUnavailable, serviceUnavailable

    static func resolve(_ error: StyleFriendsDMError) -> Self {
        switch error {
        case .signInRequired:
            .signInRequired
        case .networkUnavailable:
            .networkUnavailable
        case .termsAcceptanceRequired, .safetyUnavailable, .contentNotAllowed,
             .dmUnavailable, .conversationUnavailable, .rateLimited,
             .idempotencyConflict, .invalidResponse, .serviceUnavailable:
            .serviceUnavailable
        }
    }

    var title: String {
        switch self {
        case .signInRequired: "Your Style Friends session expired"
        case .networkUnavailable: "Conversations unavailable"
        case .serviceUnavailable: "Conversations temporarily unavailable"
        }
    }

    var detail: String {
        switch self {
        case .signInRequired: "Sign in again to continue with Style Friends."
        case .networkUnavailable: "Check your connection and try again. No messages are shown while the connection is unavailable."
        case .serviceUnavailable: "The Style Friends service is temporarily unavailable. Try again later."
        }
    }
}

enum StyleFriendsDMDeliveryState: String, Codable, Equatable, Sendable { case sent, underReview, removed, restored }

struct StyleFriendsDMTermsState: Codable, Equatable, Sendable {
    static let canonicalRequiredVersion = "style-friends-dm-ugc-v1"
    let requiredTermsVersion: String
    let acceptedTermsVersion: String?
    let acceptedAt: Date?
    enum CodingKeys: String, CodingKey { case requiredTermsVersion = "required_terms_version", acceptedTermsVersion = "accepted_terms_version", acceptedAt = "accepted_at" }
    var canSend: Bool { acceptedTermsVersion == requiredTermsVersion }
}

/// The first-send gate receives its state only from the authenticated Worker.
/// It intentionally has no local persistence: closing, scrolling, or merely
/// viewing terms cannot unlock a message send.
@MainActor
final class StyleFriendsDMFirstSendTermsGate: ObservableObject {
    enum State: Equatable { case idle, loading, acceptanceRequired(String), accepting, accepted, unavailable }
    @Published private(set) var state: State = .idle

    func refresh(using service: any StyleFriendsDirectMessageServing) async {
        state = .loading
        do {
            let terms = try await service.terms()
            state = terms.canSend ? .accepted : .acceptanceRequired(terms.requiredTermsVersion)
        } catch {
            state = .unavailable
        }
    }

    func accept(using service: any StyleFriendsDirectMessageServing) async {
        guard case let .acceptanceRequired(version) = state else { return }
        state = .accepting
        do {
            try await service.acceptTerms(version: version)
            let terms = try await service.terms()
            state = terms.canSend ? .accepted : .acceptanceRequired(terms.requiredTermsVersion)
        } catch {
            state = .unavailable
        }
    }

    var canSend: Bool { state == .accepted }
}

struct StyleFriendsDMConversation: Codable, Equatable, Identifiable, Sendable {
    let conversationReference: StyleFriendsOpaqueRouteReference
    let friendSocialReference: StyleFriendAccountReference?
    let friendDisplayName: String
    let friendAvatarReference: String?
    let unreadCount: Int
    let latestPreview: String?
    let latestPreviewSenderRole: String?
    let updatedAt: Date?
    var id: String { conversationReference.value }
    enum CodingKeys: String, CodingKey { case conversationReference = "conversation_ref", friendSocialReference = "friend_social_reference", friendDisplayName = "friend_display_name", friendAvatarReference = "friend_avatar_reference", friend, unreadCount = "unread_count", latestPreview = "latest_message_preview", updatedAt = "updated_at" }

    private struct FriendProjection: Decodable { let socialReference: StyleFriendAccountReference?; enum CodingKeys: String, CodingKey { case socialReference = "social_reference" } }
    private struct PreviewProjection: Decodable {
        let text: String?
        let senderRole: String?
        enum CodingKeys: String, CodingKey { case text; case senderRole = "sender_role" }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        conversationReference = try container.decode(StyleFriendsOpaqueRouteReference.self, forKey: .conversationReference)
        let nestedFriend = try container.decodeIfPresent(FriendProjection.self, forKey: .friend)
        friendSocialReference = try container.decodeIfPresent(StyleFriendAccountReference.self, forKey: .friendSocialReference) ?? nestedFriend?.socialReference
        friendDisplayName = try container.decodeIfPresent(String.self, forKey: .friendDisplayName) ?? "Style Friend"
        friendAvatarReference = try container.decodeIfPresent(String.self, forKey: .friendAvatarReference)
        unreadCount = try container.decodeIfPresent(Int.self, forKey: .unreadCount) ?? 0
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        if let direct = try? container.decode(String.self, forKey: .latestPreview) {
            latestPreview = direct
            latestPreviewSenderRole = nil
        } else {
            let preview = try container.decodeIfPresent(PreviewProjection.self, forKey: .latestPreview)
            latestPreview = preview?.text
            latestPreviewSenderRole = preview?.senderRole
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(conversationReference, forKey: .conversationReference)
        try container.encodeIfPresent(friendSocialReference, forKey: .friendSocialReference)
        try container.encode(friendDisplayName, forKey: .friendDisplayName)
        try container.encodeIfPresent(friendAvatarReference, forKey: .friendAvatarReference)
        try container.encode(unreadCount, forKey: .unreadCount)
        try container.encodeIfPresent(latestPreview, forKey: .latestPreview)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
    }
}

struct StyleFriendsDMParentPreview: Codable, Equatable, Sendable {
    let senderDisplayName: String?
    let text: String?
    let parentAvailable: Bool
    enum CodingKeys: String, CodingKey { case senderDisplayName = "sender_display_name", text; case parentAvailable = "parent_available" }
}

struct StyleFriendsDMMessage: Codable, Equatable, Identifiable, Sendable {
    let messageReference: StyleFriendsOpaqueRouteReference
    let clientMessageReference: String
    let senderRole: String
    let text: String?
    let deletedOrUnavailable: Bool
    let deliveryState: StyleFriendsDMDeliveryState
    let recipientVisible: Bool
    let createdAt: Date
    let updatedAt: Date
    let parentPreview: StyleFriendsDMParentPreview?
    let reactionSummary: StyleFriendReactionSummary?
    /// Immutable recipient-scoped projection; never a private source record.
    let attachment: StyleFriendsDMAttachment?
    var id: String { messageReference.value }
    enum CodingKeys: String, CodingKey { case messageReference = "message_ref", clientMessageReference = "client_message_ref", senderRole = "sender_role", text; case deletedOrUnavailable = "deleted_or_unavailable", deliveryState = "delivery_status", recipientVisible = "recipient_visible", createdAt = "created_at", updatedAt = "updated_at", parentPreview = "parent_preview", reactionSummary = "reaction_summary", attachment }
}

struct StyleFriendsDMCursorPage<Item: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    let items: [Item]
    let nextCursor: String?
    enum CodingKeys: String, CodingKey { case items; case nextCursor = "next_cursor" }
}

struct StyleFriendsDMSendDraft: Equatable, Sendable {
    let text: String
    let clientMessageReference: String
    let parentMessageReference: StyleFriendsOpaqueRouteReference?
    /// Present only for the Build 18045 protocol. Legacy drafts remain
    /// backward-compatible and never become status-correlatable.
    let operationID: UUID?
    let operationProtocolVersion: Int?
    let operationScopeTag: String?
    let operationType: StyleFriendsDMOperationJournalRecord.OperationType?

    init(text: String, clientMessageReference: String, parentMessageReference: StyleFriendsOpaqueRouteReference?, operationID: UUID? = nil, operationProtocolVersion: Int? = nil, operationScopeTag: String? = nil, operationType: StyleFriendsDMOperationJournalRecord.OperationType? = nil) {
        self.text = text
        self.clientMessageReference = clientMessageReference
        self.parentMessageReference = parentMessageReference
        self.operationID = operationID
        self.operationProtocolVersion = operationProtocolVersion
        self.operationScopeTag = operationScopeTag
        self.operationType = operationType
    }
}

struct StyleFriendsDMOperationStatus: Decodable, Equatable, Sendable {
    enum Outcome: String, Decodable, Sendable { case committed, notCommitted = "not_committed", unknown }
    let operationID: UUID
    let outcome: Outcome
    enum CodingKeys: String, CodingKey { case operationID = "operation_id", outcome }
}

/// A deliberately small, immutable presentation snapshot for a DM share.
/// It has no local scan, Closet, CloudKit, account, AI-memory, or location
/// reference; those private records never cross the social boundary.
enum StyleFriendsDMAttachmentKind: String, Codable, CaseIterable, Sendable {
    case photo, scanSnapshot, scoreSnapshot, outfitSnapshot
}

struct StyleFriendsDMAttachmentSnapshot: Codable, Equatable, Sendable {
    let title: String
    let occasion: String?
    let score: Int?
    let summary: String
    let classification: String?

    init?(title: String, occasion: String?, score: Int?, summary: String, classification: String? = nil) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let occasion = occasion?.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 80, !summary.isEmpty, summary.count <= 280,
              occasion?.count ?? 0 <= 48,
              score.map({ (0...100).contains($0) }) ?? true,
              classification.map({ OutfitCategory(rawValue: $0) != nil }) ?? true else { return nil }
        self.title = title
        self.occasion = occasion?.isEmpty == true ? nil : occasion
        self.score = score
        self.summary = summary
        self.classification = classification
    }
}

struct StyleFriendsDMAttachment: Codable, Equatable, Identifiable, Sendable {
    let attachmentReference: StyleFriendsOpaqueRouteReference
    let schemaVersion: Int
    let kind: StyleFriendsDMAttachmentKind
    let snapshot: StyleFriendsDMAttachmentSnapshot?
    let imageAttachmentReference: StyleFriendsOpaqueRouteReference?
    let state: String
    var id: String { attachmentReference.value }
    enum CodingKeys: String, CodingKey {
        case attachmentReference = "attachment_ref", schemaVersion = "schema_version", kind, snapshot
        case imageAttachmentReference = "image_attachment_ref", state
    }
}

/// Local-only share payload retained by the outbound delivery state machine.
/// Its stable reference is serialized only as the Worker idempotency key; no
/// saved-scan, image-asset, CloudKit, or account identifier is included.
struct StyleFriendsDMPreparedShare: Equatable, Sendable {
    let kind: StyleFriendsDMAttachmentKind
    let snapshot: StyleFriendsDMAttachmentSnapshot
    let imagePreview: Data?
    let clientShareReference: String
}

/// A destination returned only by the authenticated Style Friends
/// conversation listing. It is deliberately presentation-independent so the
/// retry-safe delivery lifecycle can remain available to the Foundation-only
/// verification target without importing a SwiftUI view.
struct StyleFriendsDMDestination: Identifiable, Equatable, Sendable {
    let conversation: StyleFriendsDMConversation

    var id: String { conversation.id }
    var conversationReference: StyleFriendsOpaqueRouteReference { conversation.conversationReference }
    var recipientDisplayName: String { conversation.friendDisplayName }
    var recipientAvatarReference: String? { conversation.friendAvatarReference }

    init?(authorizedConversation: StyleFriendsDMConversation) {
        guard authorizedConversation.friendSocialReference != nil,
              !authorizedConversation.friendDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        conversation = authorizedConversation
    }
}

/// Typed handoff from the transient preview into the retry-safe delivery
/// lifecycle. It has no SwiftUI dependency and carries only immutable share
/// content accepted by the authenticated DM service.
struct StyleFriendsDMTransientShareSendIntent: Equatable, Sendable {
    let destination: StyleFriendsDMDestination
    let share: StyleFriendsDMPreparedShare
    let note: String?
}

enum StyleFriendsDMFailedSendDisposition: Equatable, Sendable {
    case retryable, requiresReauthentication, terminal

    static func resolve(_ error: StyleFriendsDMError) -> Self {
        switch error {
        // The Worker idempotency key reconciles an ambiguous completed request.
        case .networkUnavailable, .serviceUnavailable, .safetyUnavailable, .invalidResponse: return .retryable
        case .signInRequired: return .requiresReauthentication
        case .termsAcceptanceRequired, .contentNotAllowed, .dmUnavailable,
             .conversationUnavailable, .rateLimited, .idempotencyConflict: return .terminal
        }
    }
}

/// Deliberately in-memory for Build 18039. The draft never contains credentials;
/// a process relaunch drops it and refreshes canonical Worker messages instead.
struct StyleFriendsDMFailedSendRecord: Identifiable, Equatable, Sendable {
    let id: String
    let draft: StyleFriendsDMSendDraft
    let error: StyleFriendsDMError
    let failedAt: Date
    var disposition: StyleFriendsDMFailedSendDisposition
    var isRetrying: Bool

    init(draft: StyleFriendsDMSendDraft, error: StyleFriendsDMError, failedAt: Date = Date()) {
        self.id = draft.clientMessageReference
        self.draft = draft
        self.error = error
        self.failedAt = failedAt
        self.disposition = .resolve(error)
        self.isRetrying = false
    }

    var canRetry: Bool { disposition == .retryable && !isRetrying }
    var canRetryAfterReauthentication: Bool { disposition == .requiresReauthentication && !isRetrying }
}

/// Represents exactly one outbound operation after it leaves the composer.
/// The phase makes retry idempotent: a message that already reached the Worker
/// can continue its attachment upload/association without sending its text a
/// second time. The optional photo remains local and is never persisted.
enum StyleFriendsDMDeliveryPhase: Equatable, Sendable {
    case send(photoAttachment: Data?, share: StyleFriendsDMPreparedShare?)
    case upload(message: StyleFriendsDMMessage, jpeg: Data)
    case createShare(message: StyleFriendsDMMessage, share: StyleFriendsDMPreparedShare, uploadedImageReference: StyleFriendsOpaqueRouteReference? = nil)
    case associate(message: StyleFriendsDMMessage, attachment: StyleFriendsDMAttachment)

    var messageWasPersisted: Bool {
        switch self {
        case .send: return false
        case .upload, .createShare, .associate: return true
        }
    }
}

struct StyleFriendsDMFailedDeliveryOperation: Identifiable, Equatable, Sendable {
    let record: StyleFriendsDMFailedSendRecord
    let phase: StyleFriendsDMDeliveryPhase
    var isRetrying: Bool

    init(draft: StyleFriendsDMSendDraft, error: StyleFriendsDMError, phase: StyleFriendsDMDeliveryPhase, isRetrying: Bool = false) {
        self.record = .init(draft: draft, error: error)
        self.phase = phase
        self.isRetrying = isRetrying
    }

    var id: String { record.id }
    var canRetry: Bool { record.disposition == .retryable && !isRetrying }
    var canRetryAfterReauthentication: Bool { record.disposition == .requiresReauthentication && !isRetrying }

    /// Presentation cleanup only: this never changes the journal or permits a send.
    func finishingRetry() -> Self {
        var finished = self
        finished.isRetrying = false
        return finished
    }

    @MainActor
    func applyingRecovery(_ resolutions: [StyleFriendsDMOperationRecoveryCoordinator.Resolution]) -> Self? {
        guard let operationID = record.draft.operationID else { return self }
        return resolutions.contains(.committed(operationID)) ? nil : self
    }

    /// Never clear a newer composer draft when an older operation completes.
    func matchesComposer(_ snapshot: StyleFriendsSubmissionSnapshot) -> Bool {
        guard snapshot.text.trimmingCharacters(in: .whitespacesAndNewlines) == record.draft.text,
              snapshot.reply == record.draft.parentMessageReference else { return false }
        switch phase {
        case let .send(photo, share): return snapshot.photo == photo && snapshot.share == share
        case let .upload(_, jpeg): return snapshot.photo == jpeg && snapshot.share == nil
        case let .createShare(_, share, _): return snapshot.photo == nil && snapshot.share == share
        case .associate: return false // No original composer payload remains to compare.
        }
    }
}

protocol StyleFriendsDMOperationStatusServing {
    func operationStatus(context: StyleFriendsDMOperationContext) async throws -> StyleFriendsDMOperationStatus
}

protocol StyleFriendsDirectMessageServing: StyleFriendsDMOperationStatusServing, StyleFriendsAttachmentLifecycleServing, StyleFriendsPreparedShareServing {
    func terms() async throws -> StyleFriendsDMTermsState
    func acceptTerms(version: String) async throws
    func conversations(cursor: String?) async throws -> StyleFriendsDMCursorPage<StyleFriendsDMConversation>
    func createConversation(friend: StyleFriendAccountReference) async throws -> StyleFriendsDMConversation
    func messages(conversation: StyleFriendsOpaqueRouteReference, cursor: String?) async throws -> StyleFriendsDMCursorPage<StyleFriendsDMMessage>
    func send(conversation: StyleFriendsOpaqueRouteReference, draft: StyleFriendsDMSendDraft) async throws -> StyleFriendsDMMessage
    /// Sender-scoped status deliberately needs no persisted raw conversation
    /// reference in the device-only recovery journal.
    func setReaction(message: StyleFriendsOpaqueRouteReference, reaction: StyleFriendReactionKind?) async throws -> StyleFriendReactionSummary
    func report(message: StyleFriendsOpaqueRouteReference, draft: StyleFriendsReportDraft) async throws
    func deleteOwnMessage(_ message: StyleFriendsOpaqueRouteReference) async throws
    func markRead(conversation: StyleFriendsOpaqueRouteReference, lastReadMessage: StyleFriendsOpaqueRouteReference) async throws
    func block(friend: StyleFriendAccountReference) async throws
    func createAttachmentSnapshot(conversation: StyleFriendsOpaqueRouteReference, kind: StyleFriendsDMAttachmentKind, snapshot: StyleFriendsDMAttachmentSnapshot, imageAttachmentReference: StyleFriendsOpaqueRouteReference?, clientShareReference: String, operation: StyleFriendsDMOperationContext?) async throws -> StyleFriendsDMAttachment
    func associateAttachment(conversation: StyleFriendsOpaqueRouteReference, attachment: StyleFriendsOpaqueRouteReference, message: StyleFriendsOpaqueRouteReference, operation: StyleFriendsDMOperationContext?) async throws -> StyleFriendsDMAttachment
    func attachmentMetadata(conversation: StyleFriendsOpaqueRouteReference, attachment: StyleFriendsOpaqueRouteReference) async throws -> StyleFriendsDMAttachment
    func attachmentImage(conversation: StyleFriendsOpaqueRouteReference, attachment: StyleFriendsOpaqueRouteReference) async throws -> Data
    func uploadAttachmentPhoto(conversation: StyleFriendsOpaqueRouteReference, jpeg: Data, operation: StyleFriendsDMOperationContext?) async throws -> StyleFriendsDMAttachment
}

extension StyleFriendsDirectMessageServing {
    func createAttachmentSnapshot(conversation: StyleFriendsOpaqueRouteReference, kind: StyleFriendsDMAttachmentKind, snapshot: StyleFriendsDMAttachmentSnapshot, imageAttachmentReference: StyleFriendsOpaqueRouteReference?, clientShareReference: String) async throws -> StyleFriendsDMAttachment { try await createAttachmentSnapshot(conversation: conversation, kind: kind, snapshot: snapshot, imageAttachmentReference: imageAttachmentReference, clientShareReference: clientShareReference, operation: nil) }
    func associateAttachment(conversation: StyleFriendsOpaqueRouteReference, attachment: StyleFriendsOpaqueRouteReference, message: StyleFriendsOpaqueRouteReference) async throws -> StyleFriendsDMAttachment { try await associateAttachment(conversation: conversation, attachment: attachment, message: message, operation: nil) }
    func uploadAttachmentPhoto(conversation: StyleFriendsOpaqueRouteReference, jpeg: Data) async throws -> StyleFriendsDMAttachment { try await uploadAttachmentPhoto(conversation: conversation, jpeg: jpeg, operation: nil) }
    func attachmentImage(conversation: StyleFriendsOpaqueRouteReference, attachment: StyleFriendsOpaqueRouteReference) async throws -> Data { throw StyleFriendsDMError.dmUnavailable }
}

/// Exact-host configuration for the authenticated Style Friends DM transport.
/// Debug/OwnerBeta may use the isolated staging Worker; public Release may use
/// only the production API host. No arbitrary URL or runtime override is accepted.
struct StyleFriendsDMStagingTransportConfiguration: Equatable, Sendable {
    static let maximumRequestBytes = 16 * 1024
    static let maximumResponseBytes = 128 * 1024
    static let timeout: TimeInterval = 15

    let baseURL: URL

    init?(baseURL: URL) {
        guard baseURL.scheme?.lowercased() == "https",
              Self.isAuthorizedHost(baseURL.host),
              baseURL.user == nil, baseURL.password == nil,
              baseURL.port == nil,
              baseURL.query == nil, baseURL.fragment == nil,
              baseURL.path.isEmpty || baseURL.path == "/" else { return nil }
        self.baseURL = baseURL
    }

    var isProductionHost: Bool {
        baseURL.host?.lowercased() == AppBackendConfiguration.approvedProductionAPIHost
    }

    func authorizes(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https"
            && url.host?.lowercased() == baseURL.host?.lowercased()
            && url.port == nil
            && url.user == nil
            && url.password == nil
    }

    private static func isAuthorizedHost(_ host: String?) -> Bool {
        if host?.lowercased() == AppBackendConfiguration.approvedProductionAPIHost {
            return true
        }
        #if DEBUG || OWNER_BETA || TESTFLIGHT_BETA
        return AppBackendConfiguration.isAuthorizedFriendsStagingHost(host)
        #else
        return false
        #endif
    }
}

enum StyleFriendsDMRuntimeAuthority: String, Equatable, Sendable {
    case disabled, stagingAuthorized, productionAuthorized

    /// Production authorization is accepted only with the exact production
    /// transport host. Staging remains compile-gated to internal/beta builds.
    static func resolve(rawValue: String?, debugBuild: Bool) -> Self {
        if rawValue == Self.productionAuthorized.rawValue { return .productionAuthorized }
        if debugBuild, rawValue == Self.stagingAuthorized.rawValue { return .stagingAuthorized }
        return .disabled
    }

    static var current: Self {
        resolve(
            rawValue: Bundle.main.object(forInfoDictionaryKey: "STYLEMATCH_STYLE_FRIENDS_DM_RUNTIME_AUTHORITY") as? String,
            debugBuild: {
                #if DEBUG || OWNER_BETA || TESTFLIGHT_BETA
                true
                #else
                false
                #endif
            }()
        )
    }

    static var apnsIndependent: Bool { true }
}

/// A second explicit gate prevents attachment UI from becoming live merely
/// because text DM is authorized. Release never gets a fallback authority.
enum StyleFriendsDMAttachmentRuntimeAuthority {
    static var isAuthorized: Bool {
        #if DEBUG || OWNER_BETA || TESTFLIGHT_BETA
        return Bundle.main.object(forInfoDictionaryKey: "STYLEMATCH_STYLE_FRIENDS_DM_ATTACHMENTS_RUNTIME_AUTHORITY") as? String == "stagingAuthorized"
        #else
        return false
        #endif
    }
}

/// Feed delivery has a dedicated runtime authority. OwnerBeta may use the
/// authenticated staging transport; production Release remains fail-closed.
enum StyleFriendsFeedRuntimeAuthority: String, Equatable, Sendable {
    case disabled, stagingAuthorized

    static func resolve(rawValue: String?, ownerBetaOrDebug: Bool) -> Self {
        guard ownerBetaOrDebug, rawValue == Self.stagingAuthorized.rawValue else { return .disabled }
        return .stagingAuthorized
    }

    static var current: Self {
        #if DEBUG || OWNER_BETA || TESTFLIGHT_BETA
        return resolve(
            rawValue: Bundle.main.object(forInfoDictionaryKey: "STYLEMATCH_STYLE_FRIENDS_FEED_RUNTIME_AUTHORITY") as? String,
            ownerBetaOrDebug: true
        )
        #else
        return .disabled
        #endif
    }
}

/// Privacy-safe readiness evidence for the Debug owner build. It deliberately
/// contains no host, token, account identifier, request body, or server body.
/// A successful create-conversation response is the only proof that the
/// server-side DM service is currently ready.
struct StyleFriendsDMRuntimeReadiness: Equatable, Sendable {
    let accountSessionPresent: Bool
    let sessionEnvironmentMatch: Bool
    let socialAuthorityReady: Bool
    let dmAuthorityReady: Bool
    let relationshipIsFriend: Bool
    let conversationServiceReady: Bool?
    let failure: StyleFriendsDMError?

    var finalReady: Bool { conversationServiceReady == true }

    func recordingConversationResult(_ result: Result<Void, StyleFriendsDMError>) -> Self {
        switch result {
        case .success:
            return .init(
                accountSessionPresent: accountSessionPresent,
                sessionEnvironmentMatch: sessionEnvironmentMatch,
                socialAuthorityReady: socialAuthorityReady,
                dmAuthorityReady: dmAuthorityReady,
                relationshipIsFriend: relationshipIsFriend,
                conversationServiceReady: true,
                failure: nil
            )
        case let .failure(error):
            return .init(
                accountSessionPresent: accountSessionPresent,
                sessionEnvironmentMatch: sessionEnvironmentMatch,
                socialAuthorityReady: socialAuthorityReady,
                dmAuthorityReady: dmAuthorityReady,
                relationshipIsFriend: relationshipIsFriend,
                conversationServiceReady: false,
                failure: error
            )
        }
    }

    #if DEBUG
    var debugSummary: String {
        let outcome = conversationServiceReady == nil ? "NOT_CHECKED" : (conversationServiceReady == true ? "READY" : "UNAVAILABLE")
        let failureCategory = failure?.rawValue ?? "none"
        return "DM: session \(accountSessionPresent ? "PRESENT" : "MISSING") · environment \(sessionEnvironmentMatch ? "MATCH" : "MISMATCH") · social \(socialAuthorityReady ? "READY" : "UNAVAILABLE") · authority \(dmAuthorityReady ? "READY" : "UNAVAILABLE") · friendship \(relationshipIsFriend ? "FRIENDS" : "NOT_FRIENDS") · conversation \(outcome) · category \(failureCategory)"
    }
    #endif
}

struct StyleFriendsDMRuntimeBinding {
    let presentationState: StyleFriendsConversationPresentationState
    let unavailableTitle: String
    let unavailableDetail: String
    let service: any StyleFriendsDirectMessageServing
    let readiness: StyleFriendsDMRuntimeReadiness

    static func current(
        bundle: Bundle = .main,
        accountSession: @escaping () -> StyleMatchAccountSession? = StyleMatchAccountSessionStore.load
    ) -> Self {
        let mode = StyleFriendsDMRuntimeAuthority.resolve(
            rawValue: bundle.object(forInfoDictionaryKey: "STYLEMATCH_STYLE_FRIENDS_DM_RUNTIME_AUTHORITY") as? String,
            debugBuild: {
                #if DEBUG || OWNER_BETA || TESTFLIGHT_BETA
                true
                #else
                false
                #endif
            }()
        )
        let configuration = StyleFriendsDMStagingTransportConfiguration(baseURL: AppBackendConfiguration.configuredAPIBaseURL(bundle: bundle))
        let socialAuthorityReady = configuration != nil
        let dmAuthorityReady: Bool
        if let configuration {
            switch mode {
            case .productionAuthorized:
                dmAuthorityReady = configuration.isProductionHost
            case .stagingAuthorized:
                dmAuthorityReady = !configuration.isProductionHost
            case .disabled:
                dmAuthorityReady = false
            }
        } else {
            dmAuthorityReady = false
        }
        let account = accountSession()
        let currentSession = account.map { $0.expiresAt > Date() } ?? false
        guard dmAuthorityReady, let configuration else {
            return .init(
                presentationState: .authorizationUnavailable,
                unavailableTitle: "Messaging is unavailable",
                unavailableDetail: "Direct messages are unavailable in this build.",
                service: StyleFriendsUnavailableDirectMessageService(),
                readiness: .init(accountSessionPresent: currentSession, sessionEnvironmentMatch: socialAuthorityReady && currentSession, socialAuthorityReady: socialAuthorityReady, dmAuthorityReady: false, relationshipIsFriend: false, conversationServiceReady: nil, failure: .dmUnavailable)
            )
        }
        guard let account, currentSession else {
            return .init(
                presentationState: .authorizationUnavailable,
                unavailableTitle: "Sign in to Style Friends",
                unavailableDetail: "Sign in with your current Style Friends account to view conversations.",
                service: StyleFriendsUnavailableDirectMessageService(),
                readiness: .init(accountSessionPresent: false, sessionEnvironmentMatch: false, socialAuthorityReady: socialAuthorityReady, dmAuthorityReady: true, relationshipIsFriend: false, conversationServiceReady: nil, failure: .signInRequired)
            )
        }
        // The Worker remains the final runtime gate for every read/mutation.
        // This client merely enables the already-authorized staging transport.
        return .init(
            presentationState: .loading,
            unavailableTitle: "",
            unavailableDetail: "",
            service: StyleFriendsHTTPDirectMessageService(configuration: configuration, accountSession: { account }),
            readiness: .init(accountSessionPresent: true, sessionEnvironmentMatch: true, socialAuthorityReady: true, dmAuthorityReady: true, relationshipIsFriend: false, conversationServiceReady: nil, failure: nil)
        )
    }
}

/// A typed injection seam, intentionally inert. A future Worker client may
/// use this configuration with the existing account-session authority, but it
/// must never synthesize a session, use production fallback, or log payloads.
struct StyleFriendsDisabledStagingDirectMessageService: StyleFriendsDirectMessageServing {
    let configuration: StyleFriendsDMStagingTransportConfiguration
    let accountSession: () -> StyleMatchAccountSession?

    private func unavailable() throws -> Never { throw StyleFriendsDMError.dmUnavailable }
    func terms() async throws -> StyleFriendsDMTermsState { try unavailable() }
    func acceptTerms(version: String) async throws { try unavailable() }
    func conversations(cursor: String?) async throws -> StyleFriendsDMCursorPage<StyleFriendsDMConversation> { try unavailable() }
    func createConversation(friend: StyleFriendAccountReference) async throws -> StyleFriendsDMConversation { try unavailable() }
    func messages(conversation: StyleFriendsOpaqueRouteReference, cursor: String?) async throws -> StyleFriendsDMCursorPage<StyleFriendsDMMessage> { try unavailable() }
    func send(conversation: StyleFriendsOpaqueRouteReference, draft: StyleFriendsDMSendDraft) async throws -> StyleFriendsDMMessage { try unavailable() }
    func operationStatus(context: StyleFriendsDMOperationContext) async throws -> StyleFriendsDMOperationStatus { try unavailable() }
    func setReaction(message: StyleFriendsOpaqueRouteReference, reaction: StyleFriendReactionKind?) async throws -> StyleFriendReactionSummary { try unavailable() }
    func report(message: StyleFriendsOpaqueRouteReference, draft: StyleFriendsReportDraft) async throws { try unavailable() }
    func deleteOwnMessage(_ message: StyleFriendsOpaqueRouteReference) async throws { try unavailable() }
    func markRead(conversation: StyleFriendsOpaqueRouteReference, lastReadMessage: StyleFriendsOpaqueRouteReference) async throws { try unavailable() }
    func block(friend: StyleFriendAccountReference) async throws { try unavailable() }
    func createAttachmentSnapshot(conversation: StyleFriendsOpaqueRouteReference, kind: StyleFriendsDMAttachmentKind, snapshot: StyleFriendsDMAttachmentSnapshot, imageAttachmentReference: StyleFriendsOpaqueRouteReference?, clientShareReference: String, operation: StyleFriendsDMOperationContext?) async throws -> StyleFriendsDMAttachment { try unavailable() }
    func associateAttachment(conversation: StyleFriendsOpaqueRouteReference, attachment: StyleFriendsOpaqueRouteReference, message: StyleFriendsOpaqueRouteReference, operation: StyleFriendsDMOperationContext?) async throws -> StyleFriendsDMAttachment { try unavailable() }
    func attachmentMetadata(conversation: StyleFriendsOpaqueRouteReference, attachment: StyleFriendsOpaqueRouteReference) async throws -> StyleFriendsDMAttachment { try unavailable() }
    func uploadAttachmentPhoto(conversation: StyleFriendsOpaqueRouteReference, jpeg: Data, operation: StyleFriendsDMOperationContext?) async throws -> StyleFriendsDMAttachment { try unavailable() }
}

/// Typed, authenticated Worker transport.  It is constructible for focused
/// tests and an explicitly authorized staging session only; the normal app
/// remains on `StyleFriendsUnavailableDirectMessageService` while the runtime
/// authority is disabled.
struct StyleFriendsHTTPDirectMessageService: StyleFriendsDirectMessageServing, StyleFriendsAttachmentLifecycleServing {
    private let configuration: StyleFriendsDMStagingTransportConfiguration
    private let session: URLSession
    private let accountSession: () -> StyleMatchAccountSession?
    private let invalidateAccountSession: () -> Void

    init(
        configuration: StyleFriendsDMStagingTransportConfiguration,
        session: URLSession = .shared,
        accountSession: @escaping () -> StyleMatchAccountSession? = StyleMatchAccountSessionStore.load,
        invalidateAccountSession: @escaping () -> Void = StyleMatchAccountSessionStore.delete
    ) {
        self.configuration = configuration
        self.session = session
        self.accountSession = accountSession
        self.invalidateAccountSession = invalidateAccountSession
    }

    func terms() async throws -> StyleFriendsDMTermsState { try await request(path: "/v1/friends/direct-messages/terms", method: "GET", body: Optional<String>.none) }
    func acceptTerms(version: String) async throws { let _: Empty = try await request(path: "/v1/friends/direct-messages/terms", method: "POST", body: TermsBody(termsVersion: version)) }
    func conversations(cursor: String?) async throws -> StyleFriendsDMCursorPage<StyleFriendsDMConversation> {
        let encoded = cursor?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let suffix = encoded.isEmpty ? "" : "?cursor=" + encoded
        return try await request(path: "/v1/friends/conversations\(suffix)", method: "GET", body: Optional<String>.none)
    }
    func createConversation(friend: StyleFriendAccountReference) async throws -> StyleFriendsDMConversation {
        struct Envelope: Decodable { let conversation: StyleFriendsDMConversation }
        let envelope: Envelope = try await request(path: "/v1/friends/conversations/\(friend.value)", method: "POST", body: Optional<String>.none)
        return envelope.conversation
    }
    func messages(conversation: StyleFriendsOpaqueRouteReference, cursor: String?) async throws -> StyleFriendsDMCursorPage<StyleFriendsDMMessage> {
        let encoded = cursor?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let suffix = encoded.isEmpty ? "" : "?cursor=" + encoded
        return try await request(path: "/v1/friends/conversations/\(conversation.value)/messages\(suffix)", method: "GET", body: Optional<String>.none)
    }
    func send(conversation: StyleFriendsOpaqueRouteReference, draft: StyleFriendsDMSendDraft) async throws -> StyleFriendsDMMessage {
        struct Envelope: Decodable { let message: StyleFriendsDMMessage }
        let body = SendBody(text: draft.text, clientMessageReference: draft.clientMessageReference, parentMessageReference: draft.parentMessageReference?.value)
        let headers: [String: String]
        if let operationID = draft.operationID, let operationType = draft.operationType, draft.operationProtocolVersion == 1 {
            headers = ["X-StyleMatch-DM-Operation-ID": operationID.uuidString, "X-StyleMatch-DM-Protocol-Version": "1", "X-StyleMatch-DM-Operation-Type": operationType.rawValue]
        } else { headers = [:] }
        let envelope: Envelope = try await request(path: "/v1/friends/conversations/\(conversation.value)/messages", method: "POST", body: body, headers: headers)
        return envelope.message
    }
    func operationStatus(context: StyleFriendsDMOperationContext) async throws -> StyleFriendsDMOperationStatus {
        guard context.protocolVersion == 1 else { throw StyleFriendsDMError.invalidResponse }
        let result: StyleFriendsDMOperationStatus = try await request(path: "/v1/friends/direct-messages/operations/\(context.operationID.uuidString)", method: "GET", body: Optional<String>.none, headers: ["X-StyleMatch-DM-Protocol-Version": "1"], validate: { status in
            guard status.operationID == context.operationID else { throw StyleFriendsDMError.invalidResponse }
        })
        return result
    }
    func setReaction(message: StyleFriendsOpaqueRouteReference, reaction: StyleFriendReactionKind?) async throws -> StyleFriendReactionSummary {
        try await request(path: "/v1/friends/messages/\(message.value)/reaction", method: "PUT", body: ReactionBody(reaction: reaction))
    }
    func report(message: StyleFriendsOpaqueRouteReference, draft: StyleFriendsReportDraft) async throws {
        let _: Empty = try await request(path: "/v1/friends/messages/\(message.value)/report", method: "POST", body: ReportBody(category: draft.category.rawValue))
    }
    func deleteOwnMessage(_ message: StyleFriendsOpaqueRouteReference) async throws { let _: Empty = try await request(path: "/v1/friends/messages/\(message.value)", method: "DELETE", body: Optional<String>.none) }
    func markRead(conversation: StyleFriendsOpaqueRouteReference, lastReadMessage: StyleFriendsOpaqueRouteReference) async throws { let _: Empty = try await request(path: "/v1/friends/conversations/\(conversation.value)/read", method: "POST", body: ReadBody(lastReadMessageReference: lastReadMessage.value)) }
    func block(friend: StyleFriendAccountReference) async throws { let _: Empty = try await request(path: "/v1/friends/relationships/\(friend.value)/block", method: "POST", body: Optional<String>.none) }
    func createAttachmentSnapshot(conversation: StyleFriendsOpaqueRouteReference, kind: StyleFriendsDMAttachmentKind, snapshot: StyleFriendsDMAttachmentSnapshot, imageAttachmentReference: StyleFriendsOpaqueRouteReference?, clientShareReference: String, operation: StyleFriendsDMOperationContext?) async throws -> StyleFriendsDMAttachment {
        struct Envelope: Decodable { let attachment: StyleFriendsDMAttachment }
        let body = AttachmentSnapshotBody(kind: kind, snapshot: snapshot, imageAttachmentReference: imageAttachmentReference?.value, clientShareReference: clientShareReference)
        let envelope: Envelope = try await request(path: "/v1/friends/conversations/\(conversation.value)/attachments/snapshots", method: "POST", body: body, headers: operationHeaders(operation))
        return envelope.attachment
    }
    func associateAttachment(conversation: StyleFriendsOpaqueRouteReference, attachment: StyleFriendsOpaqueRouteReference, message: StyleFriendsOpaqueRouteReference, operation: StyleFriendsDMOperationContext?) async throws -> StyleFriendsDMAttachment {
        struct Envelope: Decodable { let attachment: StyleFriendsDMAttachment }
        let envelope: Envelope = try await request(path: "/v1/friends/conversations/\(conversation.value)/attachments/\(attachment.value)/associate", method: "POST", body: AttachmentAssociationBody(messageReference: message.value), headers: operationHeaders(operation))
        return envelope.attachment
    }
    func attachmentMetadata(conversation: StyleFriendsOpaqueRouteReference, attachment: StyleFriendsOpaqueRouteReference) async throws -> StyleFriendsDMAttachment {
        struct Envelope: Decodable { let attachment: StyleFriendsDMAttachment }
        let envelope: Envelope = try await request(path: "/v1/friends/conversations/\(conversation.value)/attachments/\(attachment.value)", method: "GET", body: Optional<String>.none)
        return envelope.attachment
    }
    func attachmentImage(conversation: StyleFriendsOpaqueRouteReference, attachment: StyleFriendsOpaqueRouteReference) async throws -> Data {
        guard let account = accountSession(), account.expiresAt > Date() else { throw StyleFriendsDMError.signInRequired }
        guard let url = URL(string: "/v1/friends/conversations/\(conversation.value)/attachments/\(attachment.value)/image", relativeTo: configuration.baseURL), configuration.authorizes(url) else { throw StyleFriendsDMError.dmUnavailable }
        var request = URLRequest(url: url); request.httpMethod = "GET"; request.timeoutInterval = StyleFriendsDMStagingTransportConfiguration.timeout
        request.setValue("Bearer \(account.token)", forHTTPHeaderField: "Authorization"); request.setValue("image/*", forHTTPHeaderField: "Accept")
        let (data,response) = try await session.data(for: request)
        try requireUnchangedSession(account)
        guard let http = response as? HTTPURLResponse else { throw StyleFriendsDMError.invalidResponse }
        if http.statusCode == 401 { invalidateAccountSession(); throw StyleFriendsDMError.signInRequired }
        guard http.statusCode == 200, data.count <= 5 * 1024 * 1024, let mime = http.value(forHTTPHeaderField: "Content-Type"), mime.lowercased().hasPrefix("image/") else { throw StyleFriendsDMError.invalidResponse }
        return data
    }
    func uploadAttachmentPhoto(conversation: StyleFriendsOpaqueRouteReference, jpeg: Data, operation: StyleFriendsDMOperationContext?) async throws -> StyleFriendsDMAttachment {
        struct Envelope: Decodable { let attachment: StyleFriendsDMAttachment }
        guard jpeg.count > 0, jpeg.count <= 5 * 1024 * 1024 else {
            StyleFriendsDMAttachmentDiagnostics.record("UPLOAD_REQUEST", "CLIENT_SIZE_REJECTED")
            throw StyleFriendsDMError.invalidResponse
        }
        guard let account = accountSession(), account.expiresAt > Date() else {
            StyleFriendsDMAttachmentDiagnostics.record("UPLOAD_AUTH", "MISSING_OR_EXPIRED")
            throw StyleFriendsDMError.signInRequired
        }
        guard let url = URL(string: "/v1/friends/conversations/\(conversation.value)/attachments/photos", relativeTo: configuration.baseURL),
              configuration.authorizes(url) else {
            StyleFriendsDMAttachmentDiagnostics.record("UPLOAD_REQUEST", "HOST_REJECTED")
            throw StyleFriendsDMError.dmUnavailable
        }
        StyleFriendsDMAttachmentDiagnostics.record("UPLOAD_REQUEST", "CREATED")
        StyleFriendsDMAttachmentDiagnostics.record("UPLOAD_AUTH", "PRESENT")
        StyleFriendsDMOperationDiagnostics.record(operation: "photo_upload", phase: "transport")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"; request.timeoutInterval = StyleFriendsDMStagingTransportConfiguration.timeout
        request.setValue("Bearer \(account.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        for (name, value) in operationHeaders(operation) { request.setValue(value, forHTTPHeaderField: name) }
        request.httpBody = jpeg
        let data: Data; let response: URLResponse
        do { (data, response) = try await session.data(for: request) } catch {
            StyleFriendsDMAttachmentDiagnostics.record("UPLOAD_HTTP_STATUS", "NETWORK_FAILURE")
            StyleFriendsDMOperationDiagnostics.record(operation: "photo_upload", phase: "transport", serverCategory: "transport")
            throw StyleFriendsDMError.networkUnavailable
        }
        try requireUnchangedSession(account)
        guard data.count <= StyleFriendsDMStagingTransportConfiguration.maximumResponseBytes, let http = response as? HTTPURLResponse else {
            StyleFriendsDMAttachmentDiagnostics.record("UPLOAD_RESPONSE_DECODE", "INVALID_RESPONSE")
            throw StyleFriendsDMError.invalidResponse
        }
        StyleFriendsDMAttachmentDiagnostics.record("UPLOAD_HTTP_STATUS", "\(http.statusCode)")
        let uploadError: StyleFriendsDMError? = (200..<300).contains(http.statusCode) ? nil : http.statusCode == 401 ? .signInRequired : (500...599).contains(http.statusCode) ? .serviceUnavailable : mapError(data)
        StyleFriendsDMOperationDiagnostics.record(operation: "photo_upload", phase: "response", httpStatus: String(http.statusCode), serverCategory: uploadError.map { diagnosticCategory(for: $0) } ?? "accepted")
        if http.statusCode == 401 { invalidateAccountSession(); throw StyleFriendsDMError.signInRequired }
        if (500...599).contains(http.statusCode) { throw StyleFriendsDMError.serviceUnavailable }
        guard (200..<300).contains(http.statusCode), let result = try? JSONDecoder.styleFriends.decode(Envelope.self, from: data) else {
            StyleFriendsDMAttachmentDiagnostics.record("UPLOAD_RESPONSE_DECODE", (200..<300).contains(http.statusCode) ? "FAILED" : "NOT_ATTEMPTED")
            if (200..<300).contains(http.statusCode) {
                StyleFriendsDMOperationDiagnostics.record(operation: "photo_upload", phase: "response", httpStatus: String(http.statusCode), serverCategory: "validation")
            }
            throw (200..<300).contains(http.statusCode) ? StyleFriendsDMError.invalidResponse : mapError(data)
        }
        StyleFriendsDMAttachmentDiagnostics.record("UPLOAD_RESPONSE_DECODE", "PASS")
        // Creation (201) or exact replay (200) confirms the private attachment.
        StyleFriendsDMAttachmentDiagnostics.record("R2_WRITE", http.statusCode == 201 ? "CONFIRMED_BY_201" : "CONFIRMED_BY_REPLAY")
        return result.attachment
    }

    private struct Empty: Decodable {}
    private struct TermsBody: Encodable { let termsVersion: String; enum CodingKeys: String, CodingKey { case termsVersion = "terms_version" } }
    private struct SendBody: Encodable { let text: String; let clientMessageReference: String; let parentMessageReference: String?; enum CodingKeys: String, CodingKey { case text; case clientMessageReference = "client_message_ref"; case parentMessageReference = "parent_message_ref" } }
    private struct ReactionBody: Encodable { let reaction: StyleFriendReactionKind? }
    private struct ReportBody: Encodable { let category: String }
    private struct ReadBody: Encodable { let lastReadMessageReference: String; enum CodingKeys: String, CodingKey { case lastReadMessageReference = "last_read_message_ref" } }
    private struct AttachmentSnapshotBody: Encodable { let kind: StyleFriendsDMAttachmentKind; let snapshot: StyleFriendsDMAttachmentSnapshot; let imageAttachmentReference: String?; let clientShareReference: String; enum CodingKeys: String, CodingKey { case kind, snapshot; case imageAttachmentReference = "image_attachment_ref"; case clientShareReference = "client_share_ref" } }
    private struct AttachmentAssociationBody: Encodable { let messageReference: String; enum CodingKeys: String, CodingKey { case messageReference = "message_ref" } }
    private struct WorkerError: Decodable { let error: String? }
    private func operationHeaders(_ operation: StyleFriendsDMOperationContext?) -> [String: String] {
        guard let operation, operation.protocolVersion == 1 else { return [:] }
        return [
            "X-StyleMatch-DM-Operation-ID": operation.operationID.uuidString,
            "X-StyleMatch-DM-Protocol-Version": "1",
            "X-StyleMatch-DM-Operation-Type": operation.operationType.rawValue
        ]
    }

    private func request<T: Decodable, Body: Encodable>(path: String, method: String, body: Body?, headers: [String: String] = [:], validate: (T) throws -> Void = { _ in }) async throws -> T {
        let operation = diagnosticOperation(path: path, method: method)
        guard let account = accountSession(), account.expiresAt > Date() else {
            StyleFriendsDMOperationDiagnostics.record(operation: operation, phase: "authentication", serverCategory: "authentication")
            throw StyleFriendsDMError.signInRequired
        }
        guard let url = URL(string: path, relativeTo: configuration.baseURL), configuration.authorizes(url) else {
            StyleFriendsDMOperationDiagnostics.record(operation: operation, phase: "authorization", serverCategory: "feature_unavailable")
            throw StyleFriendsDMError.dmUnavailable
        }
        var request = URLRequest(url: url); request.httpMethod = method; request.timeoutInterval = StyleFriendsDMStagingTransportConfiguration.timeout
        request.setValue("Bearer \(account.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        if let body { let data = try JSONEncoder.styleFriends.encode(body); guard data.count <= StyleFriendsDMStagingTransportConfiguration.maximumRequestBytes else { throw StyleFriendsDMError.invalidResponse }; request.httpBody = data; request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            StyleFriendsDMOperationDiagnostics.record(operation: operation, phase: "transport", serverCategory: "transport")
            throw StyleFriendsDMError.networkUnavailable
        }
        try requireUnchangedSession(account)
        guard data.count <= StyleFriendsDMStagingTransportConfiguration.maximumResponseBytes, let http = response as? HTTPURLResponse else {
            StyleFriendsDMOperationDiagnostics.record(operation: operation, phase: "response", serverCategory: "validation")
            throw StyleFriendsDMError.invalidResponse
        }
        let status = String(http.statusCode)
        if http.statusCode == 401 {
            invalidateAccountSession()
            StyleFriendsDMOperationDiagnostics.record(operation: operation, phase: "response", httpStatus: status, serverCategory: "authentication")
            throw StyleFriendsDMError.signInRequired
        }
        if (500...599).contains(http.statusCode) {
            let mapped = mapError(data)
            let error: StyleFriendsDMError = [.safetyUnavailable, .dmUnavailable].contains(mapped) ? mapped : .serviceUnavailable
            StyleFriendsDMOperationDiagnostics.record(operation: operation, phase: "response", httpStatus: status, serverCategory: diagnosticCategory(for: error))
            throw error
        }
        guard (200..<300).contains(http.statusCode) else {
            let error = mapError(data)
            StyleFriendsDMOperationDiagnostics.record(operation: operation, phase: "response", httpStatus: status, serverCategory: diagnosticCategory(for: error))
            throw error
        }
        if T.self == Empty.self {
            StyleFriendsDMOperationDiagnostics.record(operation: operation, phase: "response", httpStatus: status, serverCategory: "accepted")
            return Empty() as! T
        }
        do {
            let result = try JSONDecoder.styleFriends.decode(T.self, from: data)
            try validate(result)
            StyleFriendsDMOperationDiagnostics.record(operation: operation, phase: "response", httpStatus: status, serverCategory: "accepted", reconciliation: (result as? StyleFriendsDMOperationStatus)?.outcome.rawValue)
            return result
        } catch {
            StyleFriendsDMOperationDiagnostics.record(operation: operation, phase: "response", httpStatus: status, serverCategory: "validation")
            throw StyleFriendsDMError.invalidResponse
        }
    }

    /// A delayed response belongs only to the exact session that issued it.
    /// In particular, an old 401 must never delete a newly signed-in account.
    private func requireUnchangedSession(_ issued: StyleMatchAccountSession) throws {
        guard accountSession() == issued, issued.expiresAt > Date() else {
            throw StyleFriendsDMError.signInRequired
        }
    }

    private func diagnosticOperation(path: String, method: String) -> String {
        if path.contains("/direct-messages/operations/") { return "reconciliation" }
        if path.hasSuffix("/messages") && method == "POST" { return "text_message" }
        if path.hasSuffix("/attachments/photos") { return "photo_upload" }
        if path.hasSuffix("/attachments/snapshots") { return "score_or_scan_share" }
        if path.hasSuffix("/associate") { return "attachment_association" }
        if path.hasSuffix("/messages") && method == "GET" { return "recipient_refresh" }
        return "other"
    }

    private func diagnosticCategory(for error: StyleFriendsDMError) -> String {
        switch error {
        case .signInRequired: return "authentication"
        case .termsAcceptanceRequired: return "authorization"
        case .contentNotAllowed: return "moderation"
        case .idempotencyConflict: return "conflict"
        case .dmUnavailable, .conversationUnavailable, .safetyUnavailable: return "feature_unavailable"
        case .networkUnavailable, .serviceUnavailable, .rateLimited: return "transport"
        case .invalidResponse: return "validation"
        }
    }

    private func mapError(_ data: Data) -> StyleFriendsDMError {
        guard let value = try? JSONDecoder.styleFriends.decode(WorkerError.self, from: data) else { return .invalidResponse }
        if value.error == "authenticationRequired" { return .signInRequired }
        return StyleFriendsDMError(rawValue: value.error ?? "") ?? .invalidResponse
    }
}

private extension JSONEncoder { static var styleFriends: JSONEncoder { let value = JSONEncoder(); value.dateEncodingStrategy = .iso8601; return value } }
private extension JSONDecoder { static var styleFriends: JSONDecoder { let value = JSONDecoder(); value.dateDecodingStrategy = .iso8601; return value } }

/// The only runtime implementation until a separately authorized Worker client
/// is wired. It cannot fabricate messages, terms acceptance, or send success.
struct StyleFriendsUnavailableDirectMessageService: StyleFriendsDirectMessageServing {
    func terms() async throws -> StyleFriendsDMTermsState { throw StyleFriendsDMError.dmUnavailable }
    func acceptTerms(version: String) async throws { throw StyleFriendsDMError.dmUnavailable }
    func conversations(cursor: String?) async throws -> StyleFriendsDMCursorPage<StyleFriendsDMConversation> { throw StyleFriendsDMError.dmUnavailable }
    func createConversation(friend: StyleFriendAccountReference) async throws -> StyleFriendsDMConversation { throw StyleFriendsDMError.dmUnavailable }
    func messages(conversation: StyleFriendsOpaqueRouteReference, cursor: String?) async throws -> StyleFriendsDMCursorPage<StyleFriendsDMMessage> { throw StyleFriendsDMError.dmUnavailable }
    func send(conversation: StyleFriendsOpaqueRouteReference, draft: StyleFriendsDMSendDraft) async throws -> StyleFriendsDMMessage { throw StyleFriendsDMError.dmUnavailable }
    func operationStatus(context: StyleFriendsDMOperationContext) async throws -> StyleFriendsDMOperationStatus { throw StyleFriendsDMError.dmUnavailable }
    func setReaction(message: StyleFriendsOpaqueRouteReference, reaction: StyleFriendReactionKind?) async throws -> StyleFriendReactionSummary { throw StyleFriendsDMError.dmUnavailable }
    func report(message: StyleFriendsOpaqueRouteReference, draft: StyleFriendsReportDraft) async throws { throw StyleFriendsDMError.dmUnavailable }
    func deleteOwnMessage(_ message: StyleFriendsOpaqueRouteReference) async throws { throw StyleFriendsDMError.dmUnavailable }
    func markRead(conversation: StyleFriendsOpaqueRouteReference, lastReadMessage: StyleFriendsOpaqueRouteReference) async throws { throw StyleFriendsDMError.dmUnavailable }
    func block(friend: StyleFriendAccountReference) async throws { throw StyleFriendsDMError.dmUnavailable }
    func createAttachmentSnapshot(conversation: StyleFriendsOpaqueRouteReference, kind: StyleFriendsDMAttachmentKind, snapshot: StyleFriendsDMAttachmentSnapshot, imageAttachmentReference: StyleFriendsOpaqueRouteReference?, clientShareReference: String, operation: StyleFriendsDMOperationContext?) async throws -> StyleFriendsDMAttachment { throw StyleFriendsDMError.dmUnavailable }
    func associateAttachment(conversation: StyleFriendsOpaqueRouteReference, attachment: StyleFriendsOpaqueRouteReference, message: StyleFriendsOpaqueRouteReference, operation: StyleFriendsDMOperationContext?) async throws -> StyleFriendsDMAttachment { throw StyleFriendsDMError.dmUnavailable }
    func attachmentMetadata(conversation: StyleFriendsOpaqueRouteReference, attachment: StyleFriendsOpaqueRouteReference) async throws -> StyleFriendsDMAttachment { throw StyleFriendsDMError.dmUnavailable }
    func uploadAttachmentPhoto(conversation: StyleFriendsOpaqueRouteReference, jpeg: Data, operation: StyleFriendsDMOperationContext?) async throws -> StyleFriendsDMAttachment { throw StyleFriendsDMError.dmUnavailable }
}

enum StyleFriendsDMPresentationMapper {
    static func conversation(_ value: StyleFriendsDMConversation) -> StyleFriendsConversationPresentation {
        let preview = value.latestPreview.map { text in
            switch value.latestPreviewSenderRole {
            case "self": return "You: \(text)"
            case "friend": return "\(value.friendDisplayName): \(text)"
            default: return text
            }
        }
        return .init(conversationReference: value.conversationReference, friendSocialReference: value.friendSocialReference, friendDisplayName: value.friendDisplayName, avatarReference: value.friendAvatarReference, lastMessagePreview: preview, lastActivity: value.updatedAt)
    }
    static func message(_ value: StyleFriendsDMMessage, selfDisplayName: String, friendDisplayName: String) -> StyleFriendsFriendMessagePresentation {
        let isSelf = value.senderRole == "self"
        let delivery: StyleFriendsFriendMessageDelivery
        switch value.deliveryState {
        case .sent, .restored: delivery = .sent
        case .underReview: delivery = .underReview
        case .removed: delivery = .removed
        }
        let typedShare: StyleFriendsSharedOutfitMessagePresentation? = value.attachment.flatMap { attachment in
            guard attachment.kind == .scoreSnapshot || attachment.kind == .outfitSnapshot else { return nil }
            return .init(imageProjectionLabel: attachment.snapshot?.title, scoreSnapshot: attachment.snapshot?.score, caption: attachment.snapshot?.summary, contextLabel: attachment.kind == .scoreSnapshot ? "Score when shared" : "Outfit when shared")
        }
        return .init(messageReference: value.messageReference, sender: isSelf ? .selfUser : .friend, senderDisplayName: isSelf ? selfDisplayName : friendDisplayName, text: value.text, timestamp: value.createdAt, delivery: delivery, deletedOrUnavailable: value.deletedOrUnavailable || value.deliveryState == .removed, parentPreview: value.parentPreview.map { .init(senderDisplayName: $0.senderDisplayName, text: $0.text, parentAvailable: $0.parentAvailable) }, reactionSummary: value.reactionSummary, sharedOutfit: typedShare, attachment: value.attachment)
    }
    static func userMessage(for error: StyleFriendsDMError) -> String {
        switch error { case .termsAcceptanceRequired: "Accept the Community Terms before sending."; case .safetyUnavailable, .serviceUnavailable: "Messaging is temporarily unavailable. Please try again later."; case .networkUnavailable: "Check your connection and try again."; case .contentNotAllowed: "This message cannot be sent."; case .dmUnavailable: "Messaging is temporarily unavailable."; case .signInRequired: "Sign in to Style Friends to continue."; case .conversationUnavailable: "This conversation is unavailable."; case .rateLimited: "Please wait before trying again."; case .idempotencyConflict, .invalidResponse: "The message could not be completed." }
    }
}

enum StyleFriendsDirectMessageBoundary {
    static let workerClientRequiresExplicitRuntimeAuthority = true
    static let noLocalTermsAcceptance = true
    static let noProductionFallbackFromStaging = true
    static let privateDataIsolationRequired = true
}

/// Reuses the established DM message, upload, snapshot, and association
/// operations for a transient current-result share. The only retained state is
/// an immutable in-memory operation; it has no Saved Scan or sync dependency.
@MainActor
final class StyleFriendsDMTransientShareDispatchCoordinator: ObservableObject {
    private struct FrozenOperation: Equatable {
        let intent: StyleFriendsDMTransientShareSendIntent
        let draft: StyleFriendsDMSendDraft
    }

    @Published private(set) var failedOperation: StyleFriendsDMFailedDeliveryOperation?
    @Published private(set) var isSending = false
    private let service: any StyleFriendsDirectMessageServing
    private var frozenOperation: FrozenOperation?

    init(service: any StyleFriendsDirectMessageServing) {
        self.service = service
    }

    func send(_ intent: StyleFriendsDMTransientShareSendIntent) async -> Bool {
        guard !isSending, frozenOperation == nil else { return false }
        let text = intent.note?.isEmpty == false ? intent.note! : "Shared a StyleMatch scan"
        let draft = StyleFriendsDMSendDraft(
            text: text,
            clientMessageReference: UUID().uuidString.replacingOccurrences(of: "-", with: ""),
            parentMessageReference: nil
        )
        frozenOperation = .init(intent: intent, draft: draft)
        return await execute(.send(photoAttachment: nil, share: intent.share))
    }

    func retry() async -> Bool {
        guard !isSending, let failedOperation,
              failedOperation.canRetry || failedOperation.canRetryAfterReauthentication else {
            return false
        }
        return await execute(failedOperation.phase)
    }

    private func execute(_ phase: StyleFriendsDMDeliveryPhase) async -> Bool {
        guard let frozenOperation else { return false }
        isSending = true
        defer { isSending = false }
        do {
            switch phase {
            case let .send(_, share):
                let terms = try await service.terms()
                guard terms.canSend else {
                    return fail(frozenOperation, error: .termsAcceptanceRequired, phase: phase)
                }
                let message = try await service.send(
                    conversation: frozenOperation.intent.destination.conversationReference,
                    draft: frozenOperation.draft
                )
                guard let share else { return confirmedSuccess() }
                return await createAndAssociate(share: share, message: message, frozenOperation: frozenOperation)
            case let .createShare(message, share, imageReference):
                return await createAndAssociate(share: share, message: message, frozenOperation: frozenOperation, uploadedImageReference: imageReference)
            case let .associate(message, attachment):
                let associated = try await service.associateAttachment(
                    conversation: frozenOperation.intent.destination.conversationReference,
                    attachment: attachment.attachmentReference,
                    message: message.messageReference
                )
                guard associated.attachmentReference == attachment.attachmentReference else { throw StyleFriendsDMError.invalidResponse }
                return confirmedSuccess()
            case .upload:
                // A transient snapshot uploads its image as part of createShare;
                // this legacy phase is retained for the shared retry model.
                return fail(frozenOperation, error: .invalidResponse, phase: phase)
            }
        } catch let error as StyleFriendsDMError {
            return fail(frozenOperation, error: error, phase: phase)
        } catch {
            return fail(frozenOperation, error: .invalidResponse, phase: phase)
        }
    }

    private func createAndAssociate(
        share: StyleFriendsDMPreparedShare,
        message: StyleFriendsDMMessage,
        frozenOperation: FrozenOperation,
        uploadedImageReference: StyleFriendsOpaqueRouteReference? = nil
    ) async -> Bool {
        var imageReference = uploadedImageReference
        var createdAttachment: StyleFriendsDMAttachment?
        do {
            if imageReference == nil, let image = share.imagePreview {
                imageReference = try await service.uploadAttachmentPhoto(
                    conversation: frozenOperation.intent.destination.conversationReference,
                    jpeg: image
                ).attachmentReference
            }
            let attachment = try await service.createAttachmentSnapshot(
                conversation: frozenOperation.intent.destination.conversationReference,
                kind: share.kind,
                snapshot: share.snapshot,
                imageAttachmentReference: imageReference,
                clientShareReference: share.clientShareReference
            )
            createdAttachment = attachment
            let associated = try await service.associateAttachment(
                conversation: frozenOperation.intent.destination.conversationReference,
                attachment: attachment.attachmentReference,
                message: message.messageReference
            )
            guard associated.attachmentReference == attachment.attachmentReference else { throw StyleFriendsDMError.invalidResponse }
            return confirmedSuccess()
        } catch let error as StyleFriendsDMError {
            return fail(frozenOperation, error: error, phase: createdAttachment.map { .associate(message: message, attachment: $0) } ?? .createShare(message: message, share: share, uploadedImageReference: imageReference))
        } catch {
            return fail(frozenOperation, error: .invalidResponse, phase: createdAttachment.map { .associate(message: message, attachment: $0) } ?? .createShare(message: message, share: share, uploadedImageReference: imageReference))
        }
    }

    private func fail(_ frozenOperation: FrozenOperation, error: StyleFriendsDMError, phase: StyleFriendsDMDeliveryPhase) -> Bool {
        failedOperation = .init(draft: frozenOperation.draft, error: error, phase: phase)
        return false
    }

    private func confirmedSuccess() -> Bool {
        failedOperation = nil
        frozenOperation = nil
        return true
    }
}

/// Bounded, account-scoped, memory-only cache for recently rendered DM history.
/// It exists only to make reopening a conversation immediate. Nothing is
/// persisted to disk, and every network refresh still reconciles against the
/// authenticated Worker before changing delivery or moderation state.
@MainActor
enum StyleFriendsDMSessionMessageCache {
    private struct Entry {
        var messages: [StyleFriendsDMMessage]
        var lastAccess: Date
    }

    private static var entries: [String: Entry] = [:]
    private static let maximumConversationCount = 12
    private static let maximumMessagesPerConversation = 80

    static func messages(for conversation: StyleFriendsOpaqueRouteReference) -> [StyleFriendsDMMessage] {
        guard let key = cacheKey(for: conversation), var entry = entries[key] else { return [] }
        entry.lastAccess = Date()
        entries[key] = entry
        return entry.messages
    }

    static func store(_ messages: [StyleFriendsDMMessage], for conversation: StyleFriendsOpaqueRouteReference) {
        guard let key = cacheKey(for: conversation) else { return }
        entries[key] = Entry(
            messages: Array(messages.suffix(maximumMessagesPerConversation)),
            lastAccess: Date()
        )
        trimIfNeeded()
    }

    static func clearAll() {
        entries.removeAll(keepingCapacity: false)
    }

    private static func cacheKey(for conversation: StyleFriendsOpaqueRouteReference) -> String? {
        guard let session = StyleMatchAccountSessionStore.load(),
              session.expiresAt > Date(),
              let host = session.endpointHost?.lowercased(),
              !host.isEmpty,
              let identity = session.accountID ?? session.appleSubject,
              !identity.isEmpty else {
            return nil
        }
        return "\(host)|\(identity)|\(conversation.value)"
    }

    private static func trimIfNeeded() {
        guard entries.count > maximumConversationCount else { return }
        let overflow = entries.count - maximumConversationCount
        for key in entries.sorted(by: { $0.value.lastAccess < $1.value.lastAccess }).prefix(overflow).map(\.key) {
            entries.removeValue(forKey: key)
        }
    }
}

/// Main-actor source wiring shared by the premium conversation list and chat.
/// Every visible mutation is reconciled from the Worker response; this object
/// deliberately has no local database or optimistic "sent" terminal state.
@MainActor
final class StyleFriendsDMChatActionController: ObservableObject {
    @Published private(set) var conversations: [StyleFriendsDMConversation] = []
    @Published private(set) var messages: [StyleFriendsDMMessage] = []
    @Published private(set) var nextMessageCursor: String?
    @Published private(set) var lastError: StyleFriendsDMError?
    @Published private(set) var blocked = false
    @Published private(set) var loadingConversations = false
    @Published private(set) var loadingMessages = false
    private let service: any StyleFriendsDirectMessageServing
    private var conversationLoadGeneration = 0
    private var messageLoadGeneration = 0
    private var activeMessageConversation: StyleFriendsOpaqueRouteReference?
    private var fullyHydratedMessageConversation: StyleFriendsOpaqueRouteReference?

    init(service: any StyleFriendsDirectMessageServing) { self.service = service }

    func loadConversations() async {
        conversationLoadGeneration &+= 1
        let generation = conversationLoadGeneration
        let exposesLoadingState = conversations.isEmpty && !loadingConversations
        if exposesLoadingState { loadingConversations = true }
        defer { if generation == conversationLoadGeneration { loadingConversations = false } }
        do {
            let nextConversations = try await StyleFriendsConversationHistory.load {
                try await service.conversations(cursor: $0)
            }
            guard generation == conversationLoadGeneration else { return }
            if conversations != nextConversations { conversations = nextConversations }
            if lastError != nil { lastError = nil }
        } catch let error as StyleFriendsDMError {
            guard generation == conversationLoadGeneration else { return }
            if lastError != error { lastError = error }
        } catch {
            guard generation == conversationLoadGeneration else { return }
            if lastError != .invalidResponse { lastError = .invalidResponse }
        }
    }
    func open(friend: StyleFriendAccountReference) async -> StyleFriendsDMConversation? {
        do { let value = try await service.createConversation(friend: friend); lastError = nil; return value } catch let error as StyleFriendsDMError { lastError = error; return nil } catch { lastError = .invalidResponse; return nil }
    }
    func loadMessages(conversation: StyleFriendsOpaqueRouteReference, cursor: String? = nil) async {
        messageLoadGeneration &+= 1
        let generation = messageLoadGeneration

        if cursor == nil, activeMessageConversation != conversation {
            activeMessageConversation = conversation
            fullyHydratedMessageConversation = nil
            nextMessageCursor = nil
            let cached = StyleFriendsDMSessionMessageCache.messages(for: conversation)
            if messages != cached { messages = cached }
        }

        let exposesLoadingState = messages.isEmpty && !loadingMessages
        if exposesLoadingState { loadingMessages = true }
        defer {
            if generation == messageLoadGeneration, loadingMessages {
                loadingMessages = false
            }
        }

        do {
            var page = try await service.messages(conversation: conversation, cursor: cursor)
            guard generation == messageLoadGeneration else { return }

            if cursor == nil {
                // Publish the newest page immediately. Older pages hydrate
                // progressively instead of holding the whole chat behind a
                // full-screen spinner.
                let firstVisibleMessages = mergedMessages(messages, page.items)
                if messages != firstVisibleMessages {
                    messages = firstVisibleMessages
                    StyleFriendsDMSessionMessageCache.store(messages, for: conversation)
                }
                if nextMessageCursor != page.nextCursor { nextMessageCursor = page.nextCursor }

                // Foreground polling only needs the newest page once this
                // conversation has already hydrated its history.
                if fullyHydratedMessageConversation == conversation {
                    if lastError != nil { lastError = nil }
                    return
                }

                var allItems = page.items
                var seenCursors = Set<String>()
                while let next = page.nextCursor, seenCursors.insert(next).inserted {
                    page = try await service.messages(conversation: conversation, cursor: next)
                    guard generation == messageLoadGeneration else { return }
                    allItems.append(contentsOf: page.items)

                    let progressiveMessages = mergedMessages(messages, page.items)
                    if messages != progressiveMessages {
                        messages = progressiveMessages
                        StyleFriendsDMSessionMessageCache.store(messages, for: conversation)
                    }
                    if nextMessageCursor != page.nextCursor { nextMessageCursor = page.nextCursor }
                }

                let authoritativeMessages = sortedUniqueMessages(allItems)
                if messages != authoritativeMessages { messages = authoritativeMessages }
                StyleFriendsDMSessionMessageCache.store(messages, for: conversation)
                fullyHydratedMessageConversation = conversation
            } else {
                let nextMessages = mergedMessages(messages, page.items)
                if messages != nextMessages {
                    messages = nextMessages
                    StyleFriendsDMSessionMessageCache.store(messages, for: conversation)
                }
                if nextMessageCursor != page.nextCursor { nextMessageCursor = page.nextCursor }
            }

            if lastError != nil { lastError = nil }
        } catch let error as StyleFriendsDMError {
            if generation == messageLoadGeneration, lastError != error { lastError = error }
        } catch {
            if generation == messageLoadGeneration, lastError != .invalidResponse { lastError = .invalidResponse }
        }
    }

    private func mergedMessages(
        _ existing: [StyleFriendsDMMessage],
        _ incoming: [StyleFriendsDMMessage]
    ) -> [StyleFriendsDMMessage] {
        var unique = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        incoming.forEach { unique[$0.id] = $0 }
        return unique.values.sorted {
            $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt < $1.createdAt
        }
    }

    private func sortedUniqueMessages(_ values: [StyleFriendsDMMessage]) -> [StyleFriendsDMMessage] {
        var unique: [String: StyleFriendsDMMessage] = [:]
        values.forEach { unique[$0.id] = $0 }
        return unique.values.sorted {
            $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt < $1.createdAt
        }
    }
    func send(conversation: StyleFriendsOpaqueRouteReference, draft: StyleFriendsDMSendDraft) async -> StyleFriendsDMMessage? {
        do { let value = try await service.send(conversation: conversation, draft: draft); lastError = nil; return value } catch let error as StyleFriendsDMError { lastError = error; return nil } catch { lastError = .invalidResponse; return nil }
    }
    func retry(conversation: StyleFriendsOpaqueRouteReference, originalDraft: StyleFriendsDMSendDraft) async -> StyleFriendsDMMessage? { await send(conversation: conversation, draft: originalDraft) }
    func react(message: StyleFriendsOpaqueRouteReference, reaction: StyleFriendReactionKind?) async -> StyleFriendReactionSummary? {
        do { let value = try await service.setReaction(message: message, reaction: reaction); lastError = nil; return value } catch let error as StyleFriendsDMError { lastError = error; return nil } catch { lastError = .invalidResponse; return nil }
    }
    func delete(message: StyleFriendsOpaqueRouteReference) async -> Bool { await mutation { try await self.service.deleteOwnMessage(message) } }
    func report(message: StyleFriendsOpaqueRouteReference, draft: StyleFriendsReportDraft) async -> Bool { await mutation { try await self.service.report(message: message, draft: draft) } }
    func markRead(conversation: StyleFriendsOpaqueRouteReference, lastReadMessage: StyleFriendsOpaqueRouteReference) async -> Bool { await mutation { try await self.service.markRead(conversation: conversation, lastReadMessage: lastReadMessage) } }
    func block(friend: StyleFriendAccountReference) async -> Bool {
        let result = await mutation { try await self.service.block(friend: friend) }
        if result {
            blocked = true
            conversations = []
            messages = []
            StyleFriendsDMSessionMessageCache.clearAll()
        }
        return result
    }
    private func mutation(_ work: @escaping () async throws -> Void) async -> Bool {
        do { try await work(); lastError = nil; return true } catch let error as StyleFriendsDMError { lastError = error; return false } catch { lastError = .invalidResponse; return false }
    }
}

/// Traverse only server-issued cursors through the existing authenticated service.
/// Repeated cursors fail explicitly; partial history never becomes an empty success.
@MainActor enum StyleFriendsConversationHistory {
    static func load(
        fetch: (String?) async throws -> StyleFriendsDMCursorPage<StyleFriendsDMConversation>
    ) async throws -> [StyleFriendsDMConversation] {
        var cursor: String?
        var cursors = Set<String>()
        var references = Set<StyleFriendsOpaqueRouteReference>()
        var result: [StyleFriendsDMConversation] = []
        while true {
            try Task.checkCancellation()
            let page = try await fetch(cursor)
            for item in page.items where references.insert(item.conversationReference).inserted {
                result.append(item)
            }
            guard let next = page.nextCursor else { return result }
            guard cursors.insert(next).inserted else { throw StyleFriendsDMError.invalidResponse }
            cursor = next
        }
    }
}
