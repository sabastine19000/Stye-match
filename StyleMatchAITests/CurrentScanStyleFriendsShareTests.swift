import XCTest
@testable import StyleMatchAI

@MainActor
final class CurrentScanStyleFriendsShareTests: XCTestCase {
    func testCompleteCurrentResultMapsExactImmutableSnapshot() throws {
        let input = StyleFriendsDMTransientShareAuthority.Input(
            title: "Current KigoStylist Scan",
            occasion: nil,
            score: 91,
            summary: "The navy blazer and white shirt make a polished pairing.",
            imagePreview: Data([0x01, 0x02, 0x03]),
            classification: OutfitCategory.businessCasual.rawValue
        )

        let prepared = try XCTUnwrap(
            StyleFriendsDMTransientShareAuthority.preparedShare(from: input, clientShareReference: "share-current-001")
        )

        XCTAssertEqual(prepared.kind, .scanSnapshot)
        XCTAssertEqual(prepared.imagePreview, input.imagePreview)
        XCTAssertEqual(prepared.snapshot.score, 91)
        XCTAssertEqual(prepared.snapshot.classification, OutfitCategory.businessCasual.rawValue)
        XCTAssertEqual(prepared.snapshot.summary, input.summary)
        XCTAssertEqual(prepared.clientShareReference, "share-current-001")
    }

    func testShareEligibilityRejectsMissingOrInvalidRequiredCurrentResultFields() {
        let valid = StyleFriendsDMTransientShareAuthority.Input(
            title: "Current KigoStylist Scan", occasion: nil, score: 89,
            summary: "Complete current result.", imagePreview: Data([0x01]),
            classification: OutfitCategory.businessCasual.rawValue
        )
        XCTAssertNotNil(StyleFriendsDMTransientShareAuthority.preparedShare(from: valid))

        let missingImage = StyleFriendsDMTransientShareAuthority.Input(
            title: valid.title, occasion: valid.occasion, score: valid.score,
            summary: valid.summary, imagePreview: nil, classification: valid.classification
        )
        let malformedClassification = StyleFriendsDMTransientShareAuthority.Input(
            title: valid.title, occasion: valid.occasion, score: valid.score,
            summary: valid.summary, imagePreview: valid.imagePreview, classification: "localized category"
        )
        let missingSummary = StyleFriendsDMTransientShareAuthority.Input(
            title: valid.title, occasion: valid.occasion, score: valid.score,
            summary: "", imagePreview: valid.imagePreview, classification: valid.classification
        )

        XCTAssertNil(StyleFriendsDMTransientShareAuthority.preparedShare(from: missingImage))
        XCTAssertNil(StyleFriendsDMTransientShareAuthority.preparedShare(from: malformedClassification))
        XCTAssertNil(StyleFriendsDMTransientShareAuthority.preparedShare(from: missingSummary))
    }

    func testAuthorizedDestinationAcceptsOnlyAuthenticatedConversationProjection() throws {
        let authorized = try conversation(friendReference: validFriendReference, displayName: "Jordan")
        let destination = try XCTUnwrap(StyleFriendsDMDestination(authorizedConversation: authorized))
        XCTAssertEqual(destination.conversationReference.value, "conversation_current_scan")
        XCTAssertEqual(destination.recipientDisplayName, "Jordan")

        let noAcceptedRecipient = try conversation(friendReference: nil, displayName: "Jordan")
        let blankRecipient = try conversation(friendReference: validFriendReference, displayName: "   ")
        XCTAssertNil(StyleFriendsDMDestination(authorizedConversation: noAcceptedRecipient))
        XCTAssertNil(StyleFriendsDMDestination(authorizedConversation: blankRecipient))
    }

    func testMalformedOpaqueAndBlockedOrUnauthorizedDestinationAreRejected() throws {
        XCTAssertNil(StyleFriendsOpaqueRouteReference("conversation/forged"))
        XCTAssertNil(StyleFriendAccountReference("sf_malformed"))

        // The authenticated conversations projection is the authorization
        // boundary. A blocked or unauthorized account has no accepted friend
        // projection and cannot become a destination.
        let excluded = try conversation(friendReference: nil, displayName: "Blocked account")
        XCTAssertNil(StyleFriendsDMDestination(authorizedConversation: excluded))
    }

    func testPreviewNoteValidationPreservesUnicodeAndEnforces280Characters() {
        let note = "Great fit ✨ 你好 مرحبا"
        XCTAssertTrue(StyleFriendsDMShareNoteValidation.isValid(note))
        XCTAssertEqual(StyleFriendsDMShareNoteValidation.optionalNote(from: note), note)
        XCTAssertNil(StyleFriendsDMShareNoteValidation.optionalNote(from: ""))
        XCTAssertTrue(StyleFriendsDMShareNoteValidation.isValid(String(repeating: "é", count: 280)))
        XCTAssertFalse(StyleFriendsDMShareNoteValidation.isValid(String(repeating: "é", count: 281)))
        XCTAssertFalse(StyleFriendsDMShareNoteValidation.isValid("line\u{0000}break"))
    }

    func testPreviewDraftKeepsDestinationAndAuthoritativeFieldsWithoutDispatch() throws {
        let destination = try authorizedDestination()
        let share = try preparedShare()
        let preview = StyleFriendsDMTransientSharePreviewDraft(destination: destination, share: share)

        XCTAssertEqual(preview.destination, destination)
        XCTAssertEqual(preview.share.snapshot.score, 91)
        XCTAssertEqual(preview.share.snapshot.classification, OutfitCategory.businessCasual.rawValue)
        XCTAssertEqual(preview.share.snapshot.summary, "The navy blazer and white shirt make a polished pairing.")
        XCTAssertEqual(preview.share.imagePreview, Data([0x01, 0x02, 0x03]))
    }

    func testCancelAndPreviewConstructionCauseNoTransportOrPersistenceCalls() async throws {
        let service = RecordingDMService()
        let coordinator = StyleFriendsDMTransientShareDispatchCoordinator(service: service)
        _ = coordinator // Constructing/cancelling a preview has no dispatch boundary call.
        let preview = StyleFriendsDMTransientSharePreviewDraft(destination: try authorizedDestination(), share: try preparedShare())
        XCTAssertEqual(preview.share.clientShareReference, "share-current-001")
        XCTAssertEqual(service.allCallCount, 0)
        XCTAssertEqual(service.persistenceAdjacentCallCount, 0)
    }

    func testExactAndAmbiguousRetryReuseFrozenMessageAndShareReferences() async throws {
        let service = RecordingDMService(createSnapshotFailures: [.networkUnavailable])
        let coordinator = StyleFriendsDMTransientShareDispatchCoordinator(service: service)
        let intent = StyleFriendsDMTransientShareSendIntent(
            destination: try authorizedDestination(), share: try preparedShare(), note: "Looks great ✨"
        )

        let initialSend = await coordinator.send(intent)
        XCTAssertFalse(initialSend)
        let firstMessageReference = try XCTUnwrap(coordinator.failedOperation?.record.draft.clientMessageReference)
        XCTAssertEqual(service.sentDrafts.count, 1)
        XCTAssertEqual(service.snapshotShareReferences, ["share-current-001"])
        let retry = await coordinator.retry()
        XCTAssertTrue(retry)

        XCTAssertEqual(service.sentDrafts.count, 1, "The message phase must not replay after an ambiguous snapshot failure.")
        XCTAssertEqual(service.snapshotShareReferences, ["share-current-001", "share-current-001"])
        XCTAssertEqual(service.sentDrafts.first?.clientMessageReference, firstMessageReference)
        XCTAssertNil(coordinator.failedOperation)
        XCTAssertEqual(service.persistenceAdjacentCallCount, 0)
    }

    func testTransportAuthenticationModerationValidationAnd409FailuresRetainFrozenOperation() async throws {
        for failure in [
            StyleFriendsDMError.networkUnavailable,
            .signInRequired,
            .contentNotAllowed,
            .invalidResponse,
            .idempotencyConflict
        ] {
            let service = RecordingDMService(sendFailure: failure)
            let coordinator = StyleFriendsDMTransientShareDispatchCoordinator(service: service)
            let intent = StyleFriendsDMTransientShareSendIntent(
                destination: try authorizedDestination(), share: try preparedShare(), note: "Retain me"
            )

            let sent = await coordinator.send(intent)
            XCTAssertFalse(sent)
            let failed = try XCTUnwrap(coordinator.failedOperation)
            XCTAssertEqual(failed.record.error, failure)
            XCTAssertFalse(failed.record.draft.clientMessageReference.isEmpty)
            XCTAssertEqual(service.persistenceAdjacentCallCount, 0)
        }
    }

    func testCanonicalSuccessClearsOnlyTransientDispatchStateAndNewIntentGetsNewMessageReference() async throws {
        let service = RecordingDMService()
        let coordinator = StyleFriendsDMTransientShareDispatchCoordinator(service: service)
        let first = StyleFriendsDMTransientShareSendIntent(destination: try authorizedDestination(), share: try preparedShare(reference: "share-first"), note: nil)
        let firstSent = await coordinator.send(first)
        XCTAssertTrue(firstSent)
        XCTAssertNil(coordinator.failedOperation)
        XCTAssertEqual(service.snapshotShareReferences, ["share-first"])

        let second = StyleFriendsDMTransientShareSendIntent(destination: try authorizedDestination(), share: try preparedShare(reference: "share-second"), note: "Deliberately new share")
        let secondSent = await coordinator.send(second)
        XCTAssertTrue(secondSent)
        XCTAssertEqual(service.snapshotShareReferences, ["share-first", "share-second"])
        XCTAssertEqual(Set(service.sentDrafts.map(\.clientMessageReference)).count, 2)
        XCTAssertEqual(service.persistenceAdjacentCallCount, 0)
    }

    func testRecipientSnapshotDecodesClassificationAndLegacyShapeOmitsIt() throws {
        let classified = try attachment(classification: OutfitCategory.businessCasual.rawValue, state: "active")
        XCTAssertEqual(classified.snapshot?.classification, OutfitCategory.businessCasual.rawValue)
        XCTAssertEqual(classified.snapshot?.score, 91)

        let legacy = try attachment(classification: nil, state: "active")
        XCTAssertNil(legacy.snapshot?.classification)
        XCTAssertEqual(legacy.snapshot?.summary, "The navy blazer and white shirt make a polished pairing.")
    }

    func testUnknownClassificationAndRevokedAttachmentRemainSafe() throws {
        let future = try attachment(classification: "future-worker-category", state: "active")
        XCTAssertNil(OutfitCategory(rawValue: try XCTUnwrap(future.snapshot?.classification)))

        let revoked = try attachment(classification: OutfitCategory.businessCasual.rawValue, state: "revoked")
        XCTAssertEqual(revoked.state, "revoked")
        XCTAssertEqual(revoked.attachmentReference.value, "attachment_current_scan")
        XCTAssertEqual(revoked.snapshot?.classification, OutfitCategory.businessCasual.rawValue)
    }

    func testDMReactionUsesCanonicalRefreshForAddChangeRemoveDeleteAndRelaunch() async throws {
        let service = RecordingDMService()
        let controller = StyleFriendsDMChatActionController(service: service)
        let message = try XCTUnwrap(StyleFriendsOpaqueRouteReference("message_current_scan"))
        let conversation = try XCTUnwrap(StyleFriendsOpaqueRouteReference("conversation_current_scan"))

        let added = await controller.react(message: message, reaction: .fire)
        XCTAssertEqual(added?.viewerReaction, .fire)
        XCTAssertEqual(service.reactionPutCount, 1)

        await controller.loadMessages(conversation: conversation)
        XCTAssertEqual(controller.messages.first?.reactionSummary?.viewerReaction, .fire)
        XCTAssertEqual(controller.messages.first?.text, "Nice look ✨")

        let changed = await controller.react(message: message, reaction: .love)
        XCTAssertEqual(changed?.viewerReaction, .love)
        XCTAssertEqual(changed?.count(for: .fire), 0)

        let removed = await controller.react(message: message, reaction: nil)
        XCTAssertNil(removed?.viewerReaction)
        let deleted = await controller.delete(message: message)
        XCTAssertTrue(deleted)
        await controller.loadMessages(conversation: conversation)
        XCTAssertTrue(controller.messages.first?.deletedOrUnavailable == true)
        XCTAssertNil(controller.messages.first?.reactionSummary)

        // A new controller receives the same canonical server projection; it
        // has no sender-only optimistic state to restore.
        let relaunched = StyleFriendsDMChatActionController(service: service)
        await relaunched.loadMessages(conversation: conversation)
        XCTAssertTrue(relaunched.messages.first?.deletedOrUnavailable == true)
        XCTAssertNil(relaunched.messages.first?.reactionSummary)
    }

    func testStyleFriendsServiceBoundsRequestsAndInvalidatesRejectedSession() async throws {
        XCTAssertEqual(StyleFriendsService.requestTimeout, 10)

        StyleFriendsLoadingURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StyleFriendsLoadingURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let account = StyleMatchAccountSession(
            token: "abcdefghijklmnopqrstuvwxyz123456",
            expiresAt: Date().addingTimeInterval(300)
        )
        var invalidationCount = 0
        let service = StyleFriendsService(
            baseURL: URL(string: "https://api.stylematchpro.com")!,
            session: session,
            accountSession: { account },
            invalidateAccountSession: { invalidationCount += 1 }
        )

        do {
            _ = try await service.feed()
            XCTFail("A rejected account session must not leave Style Friends in a loading state.")
        } catch {
            XCTAssertEqual(error as? StyleFriendsServiceError, .signInRequired)
        }

        XCTAssertEqual(invalidationCount, 1)
        let request = try XCTUnwrap(StyleFriendsLoadingURLProtocol.lastRequest)
        XCTAssertEqual(request.timeoutInterval, StyleFriendsService.requestTimeout, accuracy: 0.01)
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
    }

    func testAuthenticatedSavedScanCanonicalSuccessDoesNotMutateScanPersistence() async throws {
        // These stand in for the original authoritative record and its exact
        // scan-history representation. The share boundary receives only a
        // bounded snapshot; no Saved Scan identifier crosses it.
        let savedScanIdentity = "saved_scan_immutable_001"
        let savedScanBefore = Data("{\"id\":\"saved_scan_immutable_001\",\"score\":91}".utf8)
        let historyBefore = Data("{\"saved_scan_immutable_001\":{\"score\":91}}".utf8)
        let service = RecordingDMService()
        let conversation = try XCTUnwrap(StyleFriendsOpaqueRouteReference("conversation_current_scan"))
        let snapshot = try XCTUnwrap(StyleFriendsDMAttachmentSnapshot(title: "Saved Scan", occasion: "Work", score: 91, summary: "A saved KigoStylist scan selected by its owner."))
        let shareReference = "saved-share-success-001"
        let draft = StyleFriendsDMSendDraft(text: "", clientMessageReference: "saved-message-success-001", parentMessageReference: nil)

        let message = try await service.send(conversation: conversation, draft: draft)
        let attachment = try await service.createAttachmentSnapshot(conversation: conversation, kind: .scanSnapshot, snapshot: snapshot, imageAttachmentReference: nil, clientShareReference: shareReference)
        _ = try await service.associateAttachment(conversation: conversation, attachment: attachment.attachmentReference, message: message.messageReference)

        XCTAssertEqual(savedScanIdentity, "saved_scan_immutable_001")
        XCTAssertEqual(savedScanBefore, Data("{\"id\":\"saved_scan_immutable_001\",\"score\":91}".utf8))
        XCTAssertEqual(historyBefore, Data("{\"saved_scan_immutable_001\":{\"score\":91}}".utf8))
        XCTAssertEqual(service.sentDrafts.map(\.clientMessageReference), ["saved-message-success-001"])
        XCTAssertEqual(service.snapshotShareReferences, [shareReference])
        XCTAssertEqual(service.persistenceAdjacentCallCount, 0)
    }

    // MARK: - Fixtures

    private let validFriendReference = "sf_" + String(repeating: "a", count: 43)

    private func authorizedDestination() throws -> StyleFriendsDMDestination {
        try XCTUnwrap(StyleFriendsDMDestination(authorizedConversation: conversation(friendReference: validFriendReference, displayName: "Jordan")))
    }

    private func preparedShare(reference: String = "share-current-001") throws -> StyleFriendsDMPreparedShare {
        try XCTUnwrap(StyleFriendsDMTransientShareAuthority.preparedShare(
            from: .init(
                title: "Current KigoStylist Scan", occasion: nil, score: 91,
                summary: "The navy blazer and white shirt make a polished pairing.",
                imagePreview: Data([0x01, 0x02, 0x03]), classification: OutfitCategory.businessCasual.rawValue
            ),
            clientShareReference: reference
        ))
    }

    private func conversation(friendReference: String?, displayName: String) throws -> StyleFriendsDMConversation {
        var value: [String: Any] = [
            "conversation_ref": "conversation_current_scan",
            "friend_display_name": displayName,
            "unread_count": 0
        ]
        if let friendReference { value["friend_social_reference"] = friendReference }
        return try JSONDecoder().decode(StyleFriendsDMConversation.self, from: JSONSerialization.data(withJSONObject: value))
    }

    private func attachment(classification: String?, state: String) throws -> StyleFriendsDMAttachment {
        var snapshot: [String: Any] = [
            "title": "Current KigoStylist Scan",
            "score": 91,
            "summary": "The navy blazer and white shirt make a polished pairing."
        ]
        if let classification { snapshot["classification"] = classification }
        let value: [String: Any] = [
            "attachment_ref": "attachment_current_scan",
            "schema_version": 2,
            "kind": "scanSnapshot",
            "snapshot": snapshot,
            "state": state
        ]
        return try JSONDecoder().decode(StyleFriendsDMAttachment.self, from: JSONSerialization.data(withJSONObject: value))
    }
}

private final class RecordingDMService: StyleFriendsDirectMessageServing {
    private var createSnapshotFailures: [StyleFriendsDMError]
    private let sendFailure: StyleFriendsDMError?
    private(set) var sentDrafts: [StyleFriendsDMSendDraft] = []
    private(set) var snapshotShareReferences: [String] = []
    private(set) var allCallCount = 0
    /// The service protocol intentionally has no Saved Scan, Scan History,
    /// CloudKit, Cloud Sync V2, importer, or reconciliation operation.
    private(set) var persistenceAdjacentCallCount = 0
    private(set) var reactionPutCount = 0
    private var canonicalReaction = StyleFriendReactionSummary(counts: [:], viewerReaction: nil)
    private var canonicalMessageDeleted = false

    init(createSnapshotFailures: [StyleFriendsDMError] = [], sendFailure: StyleFriendsDMError? = nil) {
        self.createSnapshotFailures = createSnapshotFailures
        self.sendFailure = sendFailure
    }

    func terms() async throws -> StyleFriendsDMTermsState {
        allCallCount += 1
        return .init(requiredTermsVersion: StyleFriendsDMTermsState.canonicalRequiredVersion, acceptedTermsVersion: StyleFriendsDMTermsState.canonicalRequiredVersion, acceptedAt: Date())
    }
    func acceptTerms(version: String) async throws {}
    func conversations(cursor: String?) async throws -> StyleFriendsDMCursorPage<StyleFriendsDMConversation> { .init(items: [], nextCursor: nil) }
    func createConversation(friend: StyleFriendAccountReference) async throws -> StyleFriendsDMConversation { throw StyleFriendsDMError.conversationUnavailable }
    func messages(conversation: StyleFriendsOpaqueRouteReference, cursor: String?) async throws -> StyleFriendsDMCursorPage<StyleFriendsDMMessage> {
        .init(items: [.init(messageReference: .init("message_current_scan")!, clientMessageReference: "client_current_scan", senderRole: "friend", text: canonicalMessageDeleted ? nil : "Nice look ✨", deletedOrUnavailable: canonicalMessageDeleted, deliveryState: canonicalMessageDeleted ? .removed : .sent, recipientVisible: !canonicalMessageDeleted, createdAt: Date(), updatedAt: Date(), parentPreview: nil, reactionSummary: canonicalMessageDeleted ? nil : canonicalReaction, attachment: nil)], nextCursor: nil)
    }
    func send(conversation: StyleFriendsOpaqueRouteReference, draft: StyleFriendsDMSendDraft) async throws -> StyleFriendsDMMessage {
        allCallCount += 1
        if let sendFailure { throw sendFailure }
        sentDrafts.append(draft)
        return message(for: draft)
    }
    func setReaction(message: StyleFriendsOpaqueRouteReference, reaction: StyleFriendReactionKind?) async throws -> StyleFriendReactionSummary {
        guard message.value == "message_current_scan", !canonicalMessageDeleted else { throw StyleFriendsDMError.dmUnavailable }
        reactionPutCount += 1
        canonicalReaction = StyleFriendsReactionProjection.applying(reaction, to: canonicalReaction)
        return canonicalReaction
    }
    func report(message: StyleFriendsOpaqueRouteReference, draft: StyleFriendsReportDraft) async throws {}
    func deleteOwnMessage(_ message: StyleFriendsOpaqueRouteReference) async throws { canonicalMessageDeleted = true; canonicalReaction = .init(counts: [:], viewerReaction: nil) }
    func markRead(conversation: StyleFriendsOpaqueRouteReference, lastReadMessage: StyleFriendsOpaqueRouteReference) async throws {}
    func block(friend: StyleFriendAccountReference) async throws {}
    func operationStatus(context: StyleFriendsDMOperationContext) async throws -> StyleFriendsDMOperationStatus {
        .init(operationID: context.operationID, outcome: .notCommitted)
    }
    func createAttachmentSnapshot(conversation: StyleFriendsOpaqueRouteReference, kind: StyleFriendsDMAttachmentKind, snapshot: StyleFriendsDMAttachmentSnapshot, imageAttachmentReference: StyleFriendsOpaqueRouteReference?, clientShareReference: String, operation: StyleFriendsDMOperationContext?) async throws -> StyleFriendsDMAttachment {
        allCallCount += 1
        snapshotShareReferences.append(clientShareReference)
        if !createSnapshotFailures.isEmpty { throw createSnapshotFailures.removeFirst() }
        return try attachment(snapshot: snapshot)
    }
    func associateAttachment(conversation: StyleFriendsOpaqueRouteReference, attachment: StyleFriendsOpaqueRouteReference, message: StyleFriendsOpaqueRouteReference, operation: StyleFriendsDMOperationContext?) async throws -> StyleFriendsDMAttachment {
        allCallCount += 1
        return try self.attachment(snapshot: nil)
    }
    func attachmentMetadata(conversation: StyleFriendsOpaqueRouteReference, attachment: StyleFriendsOpaqueRouteReference) async throws -> StyleFriendsDMAttachment { try self.attachment(snapshot: nil) }
    func uploadAttachmentPhoto(conversation: StyleFriendsOpaqueRouteReference, jpeg: Data, operation: StyleFriendsDMOperationContext?) async throws -> StyleFriendsDMAttachment { try self.attachment(snapshot: nil) }

    private func message(for draft: StyleFriendsDMSendDraft) -> StyleFriendsDMMessage {
        .init(
            messageReference: StyleFriendsOpaqueRouteReference("message_current_scan")!,
            clientMessageReference: draft.clientMessageReference,
            senderRole: "self", text: draft.text, deletedOrUnavailable: false,
            deliveryState: .sent, recipientVisible: true, createdAt: Date(), updatedAt: Date(),
            parentPreview: nil, reactionSummary: nil, attachment: nil
        )
    }

    private func attachment(snapshot: StyleFriendsDMAttachmentSnapshot?) throws -> StyleFriendsDMAttachment {
        .init(
            attachmentReference: StyleFriendsOpaqueRouteReference("attachment_current_scan")!, schemaVersion: 2,
            kind: .scanSnapshot, snapshot: snapshot,
            imageAttachmentReference: StyleFriendsOpaqueRouteReference("image_current_scan"), state: "active"
        )
    }
}

private final class StyleFriendsLoadingURLProtocol: URLProtocol {
    static var lastRequest: URLRequest?

    static func reset() {
        lastRequest = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        guard let url = request.url,
              let response = HTTPURLResponse(
                url: url,
                statusCode: 401,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
              ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"error":"unauthorized"}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
