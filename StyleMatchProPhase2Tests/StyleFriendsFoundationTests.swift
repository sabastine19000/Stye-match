import XCTest
import Security
import Combine
@testable import StyleMatchPro

final class StyleFriendsFoundationTests: XCTestCase {

    func testFriendRefreshSurvivesPostsAndRequestFailures() async throws {
        let reference = try XCTUnwrap(StyleFriendAccountReference("sf_" + String(repeating: "a", count: 43)))
        let friend = StyleFriendListItem(socialReference: reference, displayName: "Existing friend", avatarReference: nil, state: .friends, createdAt: Date(timeIntervalSince1970: 1))
        let expected = StyleFriendListPage(items: [friend], nextCursor: nil)
        let result = await StyleFriendsListsSnapshot.load(
            friends: { expected },
            incoming: { throw StyleFriendsServiceError.networkUnavailable },
            outgoing: { .init(items: [], nextCursor: nil) },
            posts: { throw StyleFriendsServiceError.unavailable }
        )
        XCTAssertEqual(try result.friends.get(), expected)
        XCTAssertTrue(try result.outgoing.get().items.isEmpty)
        XCTAssertThrowsError(try result.incoming.get())
        XCTAssertThrowsError(try result.posts.get())
    }

    func testFriendAuthenticationFailureIsNotAnEmptySuccessfulList() async throws {
        let result = await StyleFriendsListsSnapshot.load(
            friends: { throw StyleFriendsServiceError.signInRequired },
            incoming: { .init(items: [], nextCursor: nil) },
            outgoing: { .init(items: [], nextCursor: nil) },
            posts: { .init(items: [], nextCursor: nil) }
        )
        switch result.friends {
        case .success: XCTFail("Authentication failure must never mean no friends.")
        case .failure(let error): XCTAssertEqual(error as? StyleFriendsServiceError, .signInRequired)
        }
        XCTAssertTrue(try result.posts.get().items.isEmpty)
    }

    private func historyConversation(_ id: String) throws -> StyleFriendsDMConversation {
        let reference = "sf_" + String(repeating: "a", count: 43)
        let json = """
        {"conversation_ref":"\(id)","friend":{"social_reference":"\(reference)"},"friend_display_name":"Existing friend","unread_count":0}
        """
        return try JSONDecoder().decode(StyleFriendsDMConversation.self, from: Data(json.utf8))
    }

    @MainActor func testOlderConversationPagesLoadAndDeduplicateInServerOrder() async throws {
        let newest = try historyConversation("thread_new")
        let older = try historyConversation("thread_old")
        var cursors: [String?] = []
        let rows = try await StyleFriendsConversationHistory.load { cursor in
            cursors.append(cursor)
            if cursor == nil { return .init(items: [newest], nextCursor: "older") }
            return .init(items: [newest, older], nextCursor: nil)
        }
        XCTAssertEqual(rows, [newest, older])
        XCTAssertEqual(cursors, [nil, "older"])
    }

    @MainActor func testRepeatedConversationCursorFailsWithoutLooping() async throws {
        var requests = 0
        do {
            _ = try await StyleFriendsConversationHistory.load { _ in
                requests += 1
                return .init(items: [], nextCursor: "repeated")
            }
            XCTFail("Repeated cursors must fail instead of hiding incomplete history.")
        } catch {
            XCTAssertEqual(error as? StyleFriendsDMError, .invalidResponse)
        }
        XCTAssertEqual(requests, 2)
    }

    @MainActor func testConversationRefreshFailureRetainsPreviouslyLoadedHistory() async throws {
        let service = PagedMessagesFake()
        let newest = try historyConversation("thread_new")
        let older = try historyConversation("thread_old")
        service.conversationFetch = { cursor in
            cursor == nil ? .init(items: [newest], nextCursor: "older") : .init(items: [older], nextCursor: nil)
        }
        let controller = StyleFriendsDMChatActionController(service: service)
        await controller.loadConversations()
        XCTAssertEqual(controller.conversations, [newest, older])
        service.conversationFetch = { cursor in
            if cursor == nil { return .init(items: [newest], nextCursor: "older") }
            throw StyleFriendsDMError.networkUnavailable
        }
        await controller.loadConversations()
        XCTAssertEqual(controller.conversations, [newest, older])
        XCTAssertEqual(controller.lastError, .networkUnavailable)
        XCTAssertFalse(controller.loadingConversations)
    }

    @MainActor func testEmptyConversationHistoryRemainsAnAuthoritativeEmptyResult() async throws {
        let rows = try await StyleFriendsConversationHistory.load { _ in
            .init(items: [], nextCursor: nil)
        }
        XCTAssertTrue(rows.isEmpty)
    }


    func testDeliveryRetryUIAlwaysFinishesItsActivityWithoutResending() throws {
        let ui = try source("StyleMatchAI/StyleFriendsChatUI.swift")
        let start = try XCTUnwrap(ui.range(of: "private func retryFailedSend()"))
        let end = try XCTUnwrap(ui.range(of: "private func abandonFailedSend()", range: start.upperBound..<ui.endIndex))
        let retry = String(ui[start.lowerBound..<end.lowerBound])
        let deferStart = try XCTUnwrap(retry.range(of: "defer {"))
        let statusStart = try XCTUnwrap(retry.range(of: "var statusConfirmedNotCommitted"))
        let cleanup = String(retry[deferStart.lowerBound..<statusStart.lowerBound])
        XCTAssertTrue(cleanup.contains("pending.id == record.id"))
        XCTAssertTrue(cleanup.contains("pending.finishingRetry()"))
        XCTAssertFalse(cleanup.contains("directMessages."))
        XCTAssertFalse(cleanup.contains("journal."))
    }

    func testRecoveryUIConsumesOnlyTheMatchingCommittedFailure() throws {
        let ui = try source("StyleMatchAI/StyleFriendsChatUI.swift")
        let start = try XCTUnwrap(ui.range(of: "private func reconcileUnresolvedOperations()"))
        let end = try XCTUnwrap(ui.range(of: "private func presentSavedShareChoices(", range: start.upperBound..<ui.endIndex))
        let recovery = String(ui[start.lowerBound..<end.lowerBound])
        XCTAssertTrue(recovery.contains("failed.applyingRecovery(resolutions) == nil"))
        XCTAssertTrue(recovery.contains("clearComposerAfterConfirmedDelivery(failed)"))
        XCTAssertTrue(recovery.contains("StyleMatchAccountSessionStore.load() == account"))
        XCTAssertFalse(recovery.contains("directMessages.send("))
        XCTAssertFalse(recovery.contains("abandonFailedSend"))
    }

    func testRetryPresentationCleanupRetainsPayloadAndRetryPolicy() {
        for error in [StyleFriendsDMError.networkUnavailable, .signInRequired, .contentNotAllowed] {
            let draft = StyleFriendsDMSendDraft(text: "Synthetic photo", clientMessageReference: "retry-ui", parentMessageReference: nil, operationID: UUID(), operationProtocolVersion: 1, operationScopeTag: String(repeating: "a", count: 64), operationType: .preparedAttachment)
            let before = StyleFriendsDMFailedDeliveryOperation(draft: draft, error: error, phase: .send(photoAttachment: Data([1, 2]), share: nil), isRetrying: true)
            let after = before.finishingRetry()
            XCTAssertFalse(after.isRetrying)
            XCTAssertEqual(after.record, before.record)
            XCTAssertEqual(after.phase, before.phase)
            XCTAssertEqual(after.id, before.id)
            XCTAssertEqual(after.canRetry, error == .networkUnavailable)
            XCTAssertEqual(after.canRetryAfterReauthentication, error == .signInRequired)
        }
    }

    @MainActor func testRecoveryPresentationRequiresExactCommittedOperation() {
        let id = UUID()
        let draft = StyleFriendsDMSendDraft(text: "Synthetic photo", clientMessageReference: "recover-ui", parentMessageReference: nil, operationID: id, operationProtocolVersion: 1, operationScopeTag: String(repeating: "a", count: 64), operationType: .preparedAttachment)
        let failed = StyleFriendsDMFailedDeliveryOperation(draft: draft, error: .networkUnavailable, phase: .send(photoAttachment: Data([1]), share: nil))
        XCTAssertEqual(failed.applyingRecovery([]), failed)
        XCTAssertEqual(failed.applyingRecovery([.unknown(id)]), failed)
        XCTAssertEqual(failed.applyingRecovery([.notCommitted(id)]), failed)
        XCTAssertEqual(failed.applyingRecovery([.committed(UUID())]), failed)
        XCTAssertNil(failed.applyingRecovery([.unknown(UUID()), .committed(id)]))
        let legacy = StyleFriendsDMFailedDeliveryOperation(draft: .init(text: "Legacy", clientMessageReference: "legacy-ui", parentMessageReference: nil), error: .networkUnavailable, phase: .send(photoAttachment: nil, share: nil))
        XCTAssertEqual(legacy.applyingRecovery([.committed(id)]), legacy)
    }

    func testRecoveryComposerCleanupPreservesNewerTextPhotoReplyAndShare() throws {
        let reply = try XCTUnwrap(StyleFriendsOpaqueRouteReference("synthetic-reply"))
        let draft = StyleFriendsDMSendDraft(text: "Original", clientMessageReference: "composer-ui", parentMessageReference: reply)
        let failed = StyleFriendsDMFailedDeliveryOperation(draft: draft, error: .networkUnavailable, phase: .send(photoAttachment: Data([1]), share: nil))
        XCTAssertTrue(failed.matchesComposer(.init(text: "Original", photo: Data([1]), share: nil, reply: reply)))
        XCTAssertFalse(failed.matchesComposer(.init(text: "New draft", photo: Data([1]), share: nil, reply: reply)))
        XCTAssertFalse(failed.matchesComposer(.init(text: "Original", photo: Data([2]), share: nil, reply: reply)))
        XCTAssertFalse(failed.matchesComposer(.init(text: "Original", photo: Data([1]), share: nil, reply: nil)))
        let share = StyleFriendsDMPreparedShare(kind: .scanSnapshot, snapshot: try XCTUnwrap(.init(title: "Synthetic", occasion: nil, score: 80, summary: "Synthetic snapshot")), imagePreview: nil, clientShareReference: "synthetic-share")
        XCTAssertFalse(failed.matchesComposer(.init(text: "Original", photo: Data([1]), share: share, reply: reply)))
        let ui = try source("StyleMatchAI/StyleFriendsChatUI.swift")
        XCTAssertTrue(ui.contains("guard operation.matchesComposer("))
    }

    @MainActor func testPhotoRecoveryAppliesOnlyExactSameAccountCommitWithoutNetwork() async throws {
        let spy = AttachmentLifecycleSpy()
        spy.associationError = StyleFriendsAttachmentOutcomeError.ambiguousOutcome
        let journal = StyleFriendsDMOperationJournal(keychain: CapturingOperationKeychain())
        var currentAccount = "synthetic-a"
        let coordinator = StyleFriendsAttachmentSendCoordinator(service: spy, conversation: try XCTUnwrap(StyleFriendsOpaqueRouteReference("conversation_test")), journal: journal, accountScope: { (currentAccount, "staging") })
        _ = await coordinator.sendNewPhoto(draft: .init(text: "Original", clientMessageReference: "recover-photo-original", parentMessageReference: nil), jpeg: Data([1]))
        let operation = try XCTUnwrap(coordinator.activeOperation)
        let before = try XCTUnwrap(journal.load(operationID: operation.operationID, expectedScopeTag: operation.scopeTag))
        let calls = [spy.sends, spy.uploads, spy.associations, spy.statuses]
        coordinator.applyRecovery([.unknown(operation.operationID), .committed(UUID())])
        XCTAssertEqual(coordinator.state, .ambiguous)
        coordinator.applyRecovery([.notCommitted(operation.operationID)])
        XCTAssertEqual(coordinator.state, .ambiguous)
        currentAccount = "synthetic-b"
        coordinator.applyRecovery([.committed(operation.operationID)])
        XCTAssertEqual(coordinator.state, .ambiguous)
        currentAccount = "synthetic-a"
        coordinator.applyRecovery([.committed(operation.operationID)])
        XCTAssertEqual(coordinator.state, .sent)
        XCTAssertEqual([spy.sends, spy.uploads, spy.associations, spy.statuses], calls)
        XCTAssertEqual(try journal.load(operationID: operation.operationID, expectedScopeTag: operation.scopeTag), before)
        spy.associationError = nil
        let next = await coordinator.sendNewPhoto(draft: .init(text: "New photo", clientMessageReference: "recover-photo-new", parentMessageReference: nil), jpeg: Data([2]))
        XCTAssertEqual(next, .confirmedAssociationSuccess)
        XCTAssertEqual(spy.sends, 2)
        XCTAssertNotEqual(coordinator.activeOperation?.operationID, operation.operationID)
    }

    func testRecoveryStatusUIKeepsUnknownLockedAndShowsCheckProgress() throws {
        let ui = try source("StyleMatchAI/StyleFriendsChatUI.swift")
        XCTAssertTrue(ui.contains("ProgressView(\"Checking delivery…\")"))
        XCTAssertTrue(ui.contains(".disabled(isSending || isCheckingRecovery)"))
        XCTAssertTrue(ui.contains("guard !isCheckingRecovery, !isSending else"))
        XCTAssertTrue(ui.contains("defer { isCheckingRecovery = false }"))
        XCTAssertTrue(ui.contains("checking does not resend it."))
        XCTAssertTrue(ui.contains("hasFailedSend: failedSend != nil || recoveryPending"))
        XCTAssertTrue(ui.contains("attachmentCoordinator.applyRecovery(resolutions)"))
        XCTAssertTrue(ui.contains("attachmentCoordinator.applyRecovery([.committed(context.operationID)])"))
    }

    func testAcceptedUnknownDiagnosticSurvivesSuccessfulBackgroundRead() {
        StyleFriendsDMOperationDiagnostics.record(operation: "reconciliation", phase: "response", httpStatus: "200", serverCategory: "accepted", reconciliation: "unknown")
        let before = StyleFriendsDMOperationDiagnostics.snapshot
        StyleFriendsDMOperationDiagnostics.record(operation: "recipient_refresh", phase: "response", httpStatus: "200", serverCategory: "accepted")
        XCTAssertEqual(StyleFriendsDMOperationDiagnostics.snapshot, before)
        // An explicit subsequent operation still updates the single latest trace.
        StyleFriendsDMOperationDiagnostics.record(operation: "reconciliation", phase: "response", httpStatus: "200", serverCategory: "accepted", reconciliation: "committed")
        XCTAssertEqual(StyleFriendsDMOperationDiagnostics.snapshot.reconciliation, "committed")
    }

    @MainActor func testPartialAttachmentUnknownKeepsOnlyItsConversationLocked() async throws {
        let journal = StyleFriendsDMOperationJournal(keychain: CapturingOperationKeychain())
        let tag = try journal.accountEnvironmentTag(account: "synthetic", environment: "test")
        let scope = try journal.scopeTag(account: "synthetic", environment: "test", conversation: "one")
        let otherScope = try journal.scopeTag(account: "synthetic", environment: "test", conversation: "two")
        let fingerprint = try journal.payloadFingerprint(type: .preparedAttachment, immutablePayload: Data([1]))
        let partial = try journal.create(accountEnvironmentTag: tag, scopeTag: scope, operationType: .preparedAttachment, payloadFingerprint: fingerprint)
        _ = try journal.transition(operationID: partial.operationID, expectedScopeTag: scope, to: .preparingAttachment)
        _ = try journal.transition(operationID: partial.operationID, expectedScopeTag: scope, to: .uploadingAttachment, opaqueServerReference: "synthetic-message-anchor")
        let other = try journal.create(accountEnvironmentTag: tag, scopeTag: otherScope, operationType: .text, payloadFingerprint: fingerprint)
        let spy = OperationStatusSpy(outcomes: [partial.operationID: .unknown, other.operationID: .committed])
        let recovery = StyleFriendsDMOperationRecoveryCoordinator(journal: journal)
        let result = await recovery.reconcile(accountEnvironmentTag: tag, scopeTag: scope, service: spy)
        XCTAssertEqual(result, [.unknown(partial.operationID)])
        let calls = await spy.callCount()
        XCTAssertEqual(calls, 1)
        let retained = try XCTUnwrap(journal.load(operationID: partial.operationID, expectedScopeTag: scope))
        XCTAssertEqual(retained.phase, .unknown)
        XCTAssertEqual(retained.payloadFingerprint, partial.payloadFingerprint)
        XCTAssertEqual(retained.opaqueServerReference, "synthetic-message-anchor")
        XCTAssertTrue(try journal.unresolved(accountEnvironmentTag: tag).contains { $0.scopeTag == scope })
        XCTAssertEqual(try journal.load(operationID: other.operationID, expectedScopeTag: otherScope)?.phase, .created)
        let final = await recovery.reconcile(accountEnvironmentTag: tag, scopeTag: scope, service: OperationStatusSpy(outcomes: [partial.operationID: .committed]))
        XCTAssertEqual(final, [.committed(partial.operationID)])
        XCTAssertFalse(try journal.unresolved(accountEnvironmentTag: tag).contains { $0.scopeTag == scope })
        XCTAssertNotNil(try journal.load(operationID: other.operationID, expectedScopeTag: otherScope))
    }
    @MainActor func testRecoveryAuthoritativeNonCommitClearsOnlyTheResolvedLock() async throws {
        for type in [StyleFriendsDMOperationJournalRecord.OperationType.text, .preparedAttachment] {
            let journal = StyleFriendsDMOperationJournal(keychain: CapturingOperationKeychain())
            let tag = try journal.accountEnvironmentTag(account: "synthetic", environment: "test")
            let scope = try journal.scopeTag(account: "synthetic", environment: "test", conversation: "one")
            let fingerprint = try journal.payloadFingerprint(type: type, immutablePayload: Data([1]))
            let record = try journal.create(accountEnvironmentTag: tag, scopeTag: scope, operationType: type, payloadFingerprint: fingerprint)
            _ = try journal.transition(operationID: record.operationID, expectedScopeTag: scope, to: type == .text ? .submitted : .preparingAttachment)
            let result = await StyleFriendsDMOperationRecoveryCoordinator(journal: journal).reconcile(accountEnvironmentTag: tag, service: OperationStatusSpy(outcomes: [record.operationID: .notCommitted]))
            XCTAssertEqual(result, [.notCommitted(record.operationID)])
            XCTAssertTrue(try journal.unresolved(accountEnvironmentTag: tag).isEmpty)
            XCTAssertEqual(try journal.load(operationID: record.operationID, expectedScopeTag: scope)?.phase, .notCommitted)
        }
    }
    @MainActor func testPreparedShareAssociationResumeReusesReferencesWithoutMessageOrUpload() async throws {
        let fake = PreparedShareRecordingFake(); let authority = StyleFriendsPreparedShareDeliveryAuthority(service: fake)
        let op = StyleFriendsDMOperationContext(record: .init(schema: 1, operationID: UUID(), accountEnvironmentTag: "a", scopeTag: "s", operationType: .preparedAttachment, payloadFingerprint: "f", phase: .preparingAttachment, createdAt: Date(), updatedAt: Date(), expiresAt: Date().addingTimeInterval(60), reconciliationCount: 0, retryCount: 0, opaqueServerReference: nil))
        _ = try await authority.resumeAssociation(conversation: .init("conversation_share")!, message: fake.msg, attachment: fake.att, operation: op)
        XCTAssertEqual(fake.calls, ["association"]); XCTAssertEqual(fake.operations.first?.operationID, op.operationID)
    }
    private func XCTAssertThrowsAsync<T>(_ operation: @escaping () async throws -> T, file: StaticString = #filePath, line: UInt = #line) async { do { _ = try await operation(); XCTFail("expected throw", file: file, line: line) } catch {} }
    private final class PreparedShareRecordingFake: StyleFriendsPreparedShareServing {
        var calls:[String]=[]; var drafts:[StyleFriendsDMSendDraft]=[]; var operations:[StyleFriendsDMOperationContext]=[]; var kinds:[StyleFriendsDMAttachmentKind]=[]; var failure:String?
        let msg=StyleFriendsOpaqueRouteReference("share_message_1")!, att=StyleFriendsOpaqueRouteReference("share_attachment_1")!
        func send(conversation: StyleFriendsOpaqueRouteReference, draft: StyleFriendsDMSendDraft) async throws -> StyleFriendsDMMessage { calls.append("message"); drafts.append(draft); if failure == "message" { throw StyleFriendsDMError.invalidResponse }; let d=Date(); return .init(messageReference: msg, clientMessageReference: draft.clientMessageReference, senderRole: "self", text: draft.text, deletedOrUnavailable: false, deliveryState: .sent, recipientVisible: true, createdAt: d, updatedAt: d, parentPreview: nil, reactionSummary: nil, attachment: nil) }
        func uploadAttachmentPhoto(conversation: StyleFriendsOpaqueRouteReference, jpeg: Data, operation: StyleFriendsDMOperationContext?) async throws -> StyleFriendsDMAttachment { calls.append("upload"); if let operation { operations.append(operation) }; if failure == "upload" { throw StyleFriendsDMError.invalidResponse }; return .init(attachmentReference: att, schemaVersion: 1, kind: .photo, snapshot: nil, imageAttachmentReference: nil, state: "ready") }
        func createAttachmentSnapshot(conversation: StyleFriendsOpaqueRouteReference, kind: StyleFriendsDMAttachmentKind, snapshot: StyleFriendsDMAttachmentSnapshot, imageAttachmentReference: StyleFriendsOpaqueRouteReference?, clientShareReference: String, operation: StyleFriendsDMOperationContext?) async throws -> StyleFriendsDMAttachment { calls.append("snapshot"); kinds.append(kind); if let operation { operations.append(operation) }; if failure == "snapshot" { throw StyleFriendsDMError.serviceUnavailable }; return .init(attachmentReference: att, schemaVersion: 1, kind: kind, snapshot: snapshot, imageAttachmentReference: imageAttachmentReference, state: "ready") }
        func associateAttachment(conversation: StyleFriendsOpaqueRouteReference, attachment: StyleFriendsOpaqueRouteReference, message: StyleFriendsOpaqueRouteReference, operation: StyleFriendsDMOperationContext?) async throws -> StyleFriendsDMAttachment { calls.append("association"); if let operation { operations.append(operation) }; if failure == "association" { throw StyleFriendsDMError.invalidResponse }; return .init(attachmentReference: attachment, schemaVersion: 1, kind: .scoreSnapshot, snapshot: nil, imageAttachmentReference: nil, state: "associated") }
    }
    @MainActor func testPreparedShareAuthorityPreservesScanAndScoreKindsAndOrder() async throws { for kind in [StyleFriendsDMAttachmentKind.scanSnapshot, .scoreSnapshot] { let fake=PreparedShareRecordingFake(); let authority=StyleFriendsPreparedShareDeliveryAuthority(service: fake); let op=StyleFriendsDMOperationContext(record: .init(schema: 1, operationID: UUID(), accountEnvironmentTag: "a", scopeTag: "s", operationType: .preparedAttachment, payloadFingerprint: "f", phase: .preparingAttachment, createdAt: Date(), updatedAt: Date(), expiresAt: Date().addingTimeInterval(60), reconciliationCount: 0, retryCount: 0, opaqueServerReference: nil)); let share=StyleFriendsDMPreparedShare(kind: kind, snapshot: try XCTUnwrap(.init(title: "Look", occasion: nil, score: 90, summary: "Summary")), imagePreview: Data([1]), clientShareReference: "c"); _ = try await authority.deliver(conversation: .init("conversation_share")!, draft: .init(text: "caption", clientMessageReference: "m", parentMessageReference: nil), share: share, operation: op); XCTAssertEqual(fake.calls, ["message","upload","snapshot","association"]); XCTAssertEqual(fake.kinds, [kind]); XCTAssertTrue(fake.operations.dropFirst().allSatisfy { $0.operationID == op.operationID }) } }
    @MainActor func testPreparedShareAuthorityMessageFailureStopsLifecycle() async throws { let f=PreparedShareRecordingFake(); f.failure="message"; let a=StyleFriendsPreparedShareDeliveryAuthority(service:f); let op=StyleFriendsDMOperationContext(record:.init(schema:1,operationID:UUID(),accountEnvironmentTag:"a",scopeTag:"s",operationType:.preparedAttachment,payloadFingerprint:"f",phase:.preparingAttachment,createdAt:Date(),updatedAt:Date(),expiresAt:Date().addingTimeInterval(60),reconciliationCount:0,retryCount:0,opaqueServerReference:nil)); let share=StyleFriendsDMPreparedShare(kind:.scanSnapshot,snapshot:try XCTUnwrap(.init(title:"S",occasion:nil,score:nil,summary:"s")),imagePreview:Data([1]),clientShareReference:"c"); await XCTAssertThrowsAsync { _=try await a.deliver(conversation:.init("c")!,draft:.init(text:"x",clientMessageReference:"m",parentMessageReference:nil),share:share,operation:op) }; XCTAssertEqual(f.calls,["message"]) }
    @MainActor func testPreparedShareAuthorityUploadFailureStopsAssociation() async throws { let f=PreparedShareRecordingFake(); f.failure="upload"; let a=StyleFriendsPreparedShareDeliveryAuthority(service:f); let op=StyleFriendsDMOperationContext(record:.init(schema:1,operationID:UUID(),accountEnvironmentTag:"a",scopeTag:"s",operationType:.preparedAttachment,payloadFingerprint:"f",phase:.preparingAttachment,createdAt:Date(),updatedAt:Date(),expiresAt:Date().addingTimeInterval(60),reconciliationCount:0,retryCount:0,opaqueServerReference:nil)); let share=StyleFriendsDMPreparedShare(kind:.scoreSnapshot,snapshot:try XCTUnwrap(.init(title:"S",occasion:nil,score:90,summary:"s")),imagePreview:Data([1]),clientShareReference:"c"); await XCTAssertThrowsAsync { _=try await a.deliver(conversation:.init("c")!,draft:.init(text:"x",clientMessageReference:"m",parentMessageReference:nil),share:share,operation:op) }; XCTAssertEqual(f.calls,["message","upload"]) }
    @MainActor func testPreparedShareUploadFailureRetainsAcceptedCaption() async throws {
        let fake = PreparedShareRecordingFake()
        fake.failure = "upload"
        let authority = StyleFriendsPreparedShareDeliveryAuthority(service: fake)
        let op = StyleFriendsDMOperationContext(record: .init(schema: 1, operationID: UUID(), accountEnvironmentTag: "a", scopeTag: "s", operationType: .preparedAttachment, payloadFingerprint: "f", phase: .preparingAttachment, createdAt: Date(), updatedAt: Date(), expiresAt: Date().addingTimeInterval(60), reconciliationCount: 0, retryCount: 0, opaqueServerReference: nil))
        let share = StyleFriendsDMPreparedShare(kind: .scanSnapshot, snapshot: try XCTUnwrap(.init(title: "Scan", occasion: nil, score: 74, summary: "Saved scan")), imagePreview: Data([1]), clientShareReference: "stable-share")
        do {
            _ = try await authority.deliver(conversation: .init("c")!, draft: .init(text: "Caption", clientMessageReference: "stable-caption", parentMessageReference: nil), share: share, operation: op)
            XCTFail("Expected upload failure")
        } catch let failure as StyleFriendsPreparedShareUploadFailure {
            XCTAssertEqual(failure.error, .invalidResponse)
            XCTAssertEqual(failure.message.messageReference, fake.msg)
            XCTAssertEqual(failure.message.clientMessageReference, "stable-caption")
            fake.failure = nil
            _ = try await authority.resumePhotoUpload(conversation: .init("c")!, message: failure.message, share: share, operation: op)
        }
        XCTAssertEqual(fake.calls, ["message", "upload", "upload", "snapshot", "association"])
        XCTAssertEqual(fake.drafts.count, 1)
        XCTAssertTrue(fake.operations.allSatisfy { $0.operationID == op.operationID })
    }

    @MainActor func testPreparedShareAuthorityAssociationFailureRetainsMessageAndAttachment() async throws {
        let f = PreparedShareRecordingFake()
        f.failure = "association"
        let authority = StyleFriendsPreparedShareDeliveryAuthority(service: f)
        let operation = StyleFriendsDMOperationContext(record: .init(schema: 1, operationID: UUID(), accountEnvironmentTag: "a", scopeTag: "s", operationType: .preparedAttachment, payloadFingerprint: "f", phase: .preparingAttachment, createdAt: Date(), updatedAt: Date(), expiresAt: Date().addingTimeInterval(60), reconciliationCount: 0, retryCount: 0, opaqueServerReference: nil))
        let share = StyleFriendsDMPreparedShare(kind: .scanSnapshot, snapshot: try XCTUnwrap(.init(title: "S", occasion: nil, score: nil, summary: "s")), imagePreview: Data([1]), clientShareReference: "c")
        do {
            _ = try await authority.deliver(conversation: .init("c")!, draft: .init(text: "x", clientMessageReference: "m", parentMessageReference: nil), share: share, operation: operation)
            XCTFail("expected association failure")
        } catch let failure as StyleFriendsPreparedShareAssociationFailure {
            XCTAssertEqual(failure.error, .invalidResponse)
            XCTAssertEqual(failure.message.messageReference, f.msg)
            XCTAssertEqual(failure.attachment.attachmentReference, f.att)
        }
        XCTAssertEqual(f.calls, ["message", "upload", "snapshot", "association"])
    }
    @MainActor func testPreparedShareSnapshotRetryReusesUploadedImageWithoutResendingCaption() async throws {
        let fake = PreparedShareRecordingFake()
        fake.failure = "snapshot"
        let authority = StyleFriendsPreparedShareDeliveryAuthority(service: fake)
        let operation = StyleFriendsDMOperationContext(record: .init(schema: 1, operationID: UUID(), accountEnvironmentTag: "a", scopeTag: "s", operationType: .preparedAttachment, payloadFingerprint: "f", phase: .preparingAttachment, createdAt: Date(), updatedAt: Date(), expiresAt: Date().addingTimeInterval(60), reconciliationCount: 0, retryCount: 0, opaqueServerReference: nil))
        let share = StyleFriendsDMPreparedShare(kind: .scanSnapshot, snapshot: try XCTUnwrap(.init(title: "Scan", occasion: nil, score: 83, summary: "Saved scan")), imagePreview: Data([1]), clientShareReference: "stable-snapshot-reference")
        do {
            _ = try await authority.deliver(conversation: .init("conversation")!, draft: .init(text: "Caption", clientMessageReference: "stable-message", parentMessageReference: nil), share: share, operation: operation)
            XCTFail("Expected snapshot failure")
        } catch let checkpoint as StyleFriendsPreparedShareSnapshotFailure {
            XCTAssertEqual(checkpoint.imageReference, fake.att)
            XCTAssertEqual(checkpoint.message.messageReference, fake.msg)
            fake.failure = nil
            _ = try await authority.resumeSnapshot(conversation: .init("conversation")!, message: checkpoint.message, share: share, imageReference: checkpoint.imageReference, operation: operation)
        }
        XCTAssertEqual(fake.calls, ["message", "upload", "snapshot", "snapshot", "association"])
    }

    @MainActor func testPreparedShareResumeCannotDropExpectedImage() async throws {
        let fake = PreparedShareRecordingFake()
        let authority = StyleFriendsPreparedShareDeliveryAuthority(service: fake)
        let op = StyleFriendsDMOperationContext(record: .init(schema: 1, operationID: UUID(), accountEnvironmentTag: "a", scopeTag: "s", operationType: .preparedAttachment, payloadFingerprint: "f", phase: .preparingAttachment, createdAt: Date(), updatedAt: Date(), expiresAt: Date().addingTimeInterval(60), reconciliationCount: 0, retryCount: 0, opaqueServerReference: nil))
        let draft = StyleFriendsDMSendDraft(text: "Caption", clientMessageReference: "m", parentMessageReference: nil)
        let message = try await fake.send(conversation: .init("c")!, draft: draft)
        let share = StyleFriendsDMPreparedShare(kind: .scanSnapshot, snapshot: try XCTUnwrap(.init(title: "Scan", occasion: nil, score: 83, summary: "Saved scan")), imagePreview: Data([1]), clientShareReference: "s")
        do {
            _ = try await authority.resumeSnapshot(conversation: .init("c")!, message: message, share: share, imageReference: nil, operation: op)
            XCTFail("Must not silently omit a selected image")
        } catch let failure as StyleFriendsPreparedShareSnapshotFailure {
            XCTAssertEqual(failure.error, .invalidResponse)
            XCTAssertEqual(failure.message.messageReference, message.messageReference)
        }
        XCTAssertEqual(fake.calls, ["message"])
    }

    @MainActor func testPreparedShareSessionChangeRetainsCompletedSnapshot() async throws {
        let fake = PreparedShareRecordingFake()
        let session = StyleMatchAccountSession(token: "synthetic-session-abcdefghijklmnopqrstuvwxyz", expiresAt: Date().addingTimeInterval(300))
        var reads = 0
        let authority = StyleFriendsPreparedShareDeliveryAuthority(service: fake, accountSession: { reads += 1; return reads < 5 ? session : nil })
        let op = StyleFriendsDMOperationContext(record: .init(schema: 1, operationID: UUID(), accountEnvironmentTag: "a", scopeTag: "s", operationType: .preparedAttachment, payloadFingerprint: "f", phase: .preparingAttachment, createdAt: Date(), updatedAt: Date(), expiresAt: Date().addingTimeInterval(60), reconciliationCount: 0, retryCount: 0, opaqueServerReference: nil))
        let share = StyleFriendsDMPreparedShare(kind: .scoreSnapshot, snapshot: try XCTUnwrap(.init(title: "Score", occasion: nil, score: 80, summary: "Saved score")), imagePreview: nil, clientShareReference: "s")
        do {
            _ = try await authority.deliver(conversation: .init("c")!, draft: .init(text: "Caption", clientMessageReference: "m", parentMessageReference: nil), share: share, operation: op)
            XCTFail("Must stop when session changes")
        } catch let failure as StyleFriendsPreparedShareAssociationFailure {
            XCTAssertEqual(failure.error, .signInRequired)
            XCTAssertEqual(failure.attachment.attachmentReference, fake.att)
            XCTAssertEqual(failure.message.messageReference, fake.msg)
        }
        XCTAssertEqual(fake.calls, ["message", "snapshot"])
    }

    @MainActor func testPreparedShareAssociationResumeFailureRetainsCheckpoint() async throws {
        let f=PreparedShareRecordingFake(); f.failure="association"; let a=StyleFriendsPreparedShareDeliveryAuthority(service:f)
        let op=StyleFriendsDMOperationContext(record:.init(schema:1,operationID:UUID(),accountEnvironmentTag:"a",scopeTag:"s",operationType:.preparedAttachment,payloadFingerprint:"f",phase:.preparingAttachment,createdAt:Date(),updatedAt:Date(),expiresAt:Date().addingTimeInterval(60),reconciliationCount:0,retryCount:0,opaqueServerReference:nil))
        await XCTAssertThrowsAsync { _=try await a.resumeAssociation(conversation:.init("c")!,message:f.msg,attachment:f.att,operation:op) }
        XCTAssertEqual(f.calls,["association"]); XCTAssertEqual(f.operations.first?.operationID,op.operationID)
    }
    @MainActor func testPreparedShareAssociationResumeCompletesAfterAssociation() async throws {
        let f=PreparedShareRecordingFake(); let a=StyleFriendsPreparedShareDeliveryAuthority(service:f)
        let op=StyleFriendsDMOperationContext(record:.init(schema:1,operationID:UUID(),accountEnvironmentTag:"a",scopeTag:"s",operationType:.preparedAttachment,payloadFingerprint:"f",phase:.preparingAttachment,createdAt:Date(),updatedAt:Date(),expiresAt:Date().addingTimeInterval(60),reconciliationCount:0,retryCount:0,opaqueServerReference:nil))
        let result=try await a.resumeAssociation(conversation:.init("c")!,message:f.msg,attachment:f.att,operation:op)
        XCTAssertEqual(f.calls,["association"]); XCTAssertEqual(result.attachmentReference,f.att); XCTAssertEqual(f.operations.first?.operationID,op.operationID)
    }
    func testPreparedShareRetryWrapperIsNetworkFreeOutsideAuthority() throws {
        let source=try source("StyleMatchAI/StyleFriendsChatUI.swift")
        let start=try XCTUnwrap(source.range(of:"private func associatePreparedShareAttachment"))
        let tail=source[start.lowerBound...]; let body=tail.split(separator:"\n    private ",maxSplits:1,omittingEmptySubsequences:false).first.map(String.init) ?? String(tail)
        XCTAssertTrue(body.contains("resumeAssociation")); XCTAssertFalse(body.contains("directMessages.send(")); XCTAssertFalse(body.contains("uploadAttachmentPhoto")); XCTAssertFalse(body.contains("createAttachmentSnapshot")); XCTAssertFalse(body.contains("associateAttachment("))
        XCTAssertTrue(body.contains("try completeOperation(draft)"))
        let retryStart = try XCTUnwrap(source.range(of: "private func retryFailedSend()"))
        let retryTail = source[retryStart.lowerBound...]
        let retryBody = retryTail.split(separator: "\n    /// A separate explicit action", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? String(retryTail)
        XCTAssertTrue(retryBody.contains("if case .associate = record.phase { resumesKnownAssociation = true }"))
        XCTAssertTrue(retryBody.contains("!resumesKnownAssociation"))
    }
    @MainActor func testPhotoMessageReceivesCanonicalOperationMetadata() async throws {
        let spy = AttachmentLifecycleSpy()
        let coordinator = StyleFriendsAttachmentSendCoordinator(service: spy, conversation: try XCTUnwrap(StyleFriendsOpaqueRouteReference("conversation_test")), journal: StyleFriendsDMOperationJournal(keychain: CapturingOperationKeychain()), accountScope: { ("synthetic-a", "staging") })
        let draft = StyleFriendsDMSendDraft(text: "caption", clientMessageReference: "photo-metadata", parentMessageReference: nil)
        await coordinator.sendNewPhoto(draft: draft, jpeg: Data([1, 2, 3]))
        let sent = try XCTUnwrap(spy.sentDrafts.first)
        let operation = try XCTUnwrap(coordinator.activeOperation)
        XCTAssertEqual(sent.operationID, operation.operationID)
        XCTAssertEqual(sent.operationProtocolVersion, operation.protocolVersion)
        XCTAssertEqual(sent.operationScopeTag, operation.scopeTag)
        XCTAssertEqual(sent.operationType, operation.operationType)
        XCTAssertEqual(coordinator.state, .sent)
    }
    @MainActor func testPhotoSubmissionCapturedBeforeAuthorizationSuspension() throws { let r = try XCTUnwrap(StyleFriendsOpaqueRouteReference("reply_capture")); let s = StyleFriendsSubmissionSnapshot(text: "caption", photo: Data([1,2]), share: nil, reply: r); XCTAssertTrue(s.matches(text: "caption", photo: Data([1,2]), reply: r)) }
    @MainActor func testPhotoSubmissionSnapshotPreservesPhotoAndReply() { let s = StyleFriendsSubmissionSnapshot(text: "x", photo: Data([3]), share: nil, reply: nil); XCTAssertEqual(s.photo, Data([3])); XCTAssertNil(s.reply) }
    @MainActor func testPhotoSubmissionSnapshotDoesNotConsumeTextPath() { let s = StyleFriendsSubmissionSnapshot(text: "", photo: Data([4]), share: nil, reply: nil); XCTAssertTrue(s.text.isEmpty); XCTAssertNotNil(s.photo) }
    @MainActor func testNewerTextIsPreservedBySnapshotComparison() { let s = StyleFriendsSubmissionSnapshot(text: "old", photo: Data([1]), share: nil, reply: nil); XCTAssertFalse(s.matches(text: "new", photo: Data([1]), reply: nil)) }
    @MainActor func testNewerPhotoIsPreservedBySnapshotComparison() { let s = StyleFriendsSubmissionSnapshot(text: "x", photo: Data([1]), share: nil, reply: nil); XCTAssertFalse(s.matches(text: "x", photo: Data([2]), reply: nil)) }
    @MainActor func testNewerReplyIsPreservedBySnapshotComparison() throws { let a = try XCTUnwrap(StyleFriendsOpaqueRouteReference("reply_a")); let b = try XCTUnwrap(StyleFriendsOpaqueRouteReference("reply_b")); let s = StyleFriendsSubmissionSnapshot(text: "x", photo: Data([1]), share: nil, reply: a); XCTAssertFalse(s.matches(text: "x", photo: Data([1]), reply: b)) }
    @MainActor func testMatchingSnapshotAllowsComposerCleanup() { let s = StyleFriendsSubmissionSnapshot(text: "x", photo: Data([1]), share: nil, reply: nil); XCTAssertTrue(s.matches(text: "x", photo: Data([1]), reply: nil)) }
    @MainActor func testPhotoFailureSnapshotRetainsRetryPayload() { let s = StyleFriendsSubmissionSnapshot(text: "caption", photo: Data([9]), share: nil, reply: nil); XCTAssertEqual(s.text, "caption"); XCTAssertEqual(s.photo, Data([9])) }
    @MainActor func testTextOnlySubmissionSnapshotHasNoPhoto() { let s = StyleFriendsSubmissionSnapshot(text: "hello", photo: nil, share: nil, reply: nil); XCTAssertNil(s.photo); XCTAssertEqual(s.text, "hello") }
    private actor AssociationRetryGate {
        private var entered = false
        private var waiters: [CheckedContinuation<Void, Never>] = []
        private var releaseRequested = false
        func suspendUntilReleased() async { entered = true; let observers = waiters; waiters.removeAll(); observers.forEach { $0.resume() }; if releaseRequested { return }; await withCheckedContinuation { waiters.append($0) } }
        func waitUntilEntered() async { if entered { return }; await withCheckedContinuation { waiters.append($0) } }
        func release() { releaseRequested = true; let pending = waiters; waiters.removeAll(); pending.forEach { $0.resume() } }
    }
    private actor StatusRetryGate {
        private var entered = false; private var waiters: [CheckedContinuation<Void, Never>] = []; private var releaseRequested = false
        func suspend() async { entered = true; let observers = waiters; waiters.removeAll(); observers.forEach { $0.resume() }; if releaseRequested { return }; await withCheckedContinuation { waiters.append($0) } }
        func waitUntilEntered() async { if entered { return }; await withCheckedContinuation { waiters.append($0) } }
        func release() { releaseRequested = true; let pending = waiters; waiters.removeAll(); pending.forEach { $0.resume() } }
    }
    private final class AttachmentLifecycleSpy: StyleFriendsAttachmentLifecycleServing {
        var sends = 0; var uploads = 0; var associations = 0; var statuses = 0; var sentDrafts: [StyleFriendsDMSendDraft] = []
        var sendError: Error?; var uploadError: Error?; var associationError: Error?
        var sendErrors: [Error] = []; var uploadErrors: [Error] = []
        var messageRetryGate: AssociationRetryGate?; var uploadRetryGate: AssociationRetryGate?
        var associationErrors: [Error] = []
        var associationRetryGate: AssociationRetryGate?
        var statusRetryGate: StatusRetryGate?
        var outcome: StyleFriendsDMOperationStatus.Outcome = .notCommitted
        var onMessageAccepted: (() -> Void)?
        let messageRef = StyleFriendsOpaqueRouteReference("message_test")!
        let attachmentRef = StyleFriendsOpaqueRouteReference("attachment_test")!
        func send(conversation: StyleFriendsOpaqueRouteReference, draft: StyleFriendsDMSendDraft) async throws -> StyleFriendsDMMessage {
            sends += 1; sentDrafts.append(draft); if !sendErrors.isEmpty { throw sendErrors.removeFirst() }; if let sendError { throw sendError }; if let gate = messageRetryGate { messageRetryGate = nil; await gate.suspendUntilReleased() }
            onMessageAccepted?()
            let now = Date(); return .init(messageReference: messageRef, clientMessageReference: draft.clientMessageReference, senderRole: "self", text: draft.text, deletedOrUnavailable: false, deliveryState: .sent, recipientVisible: true, createdAt: now, updatedAt: now, parentPreview: nil, reactionSummary: nil, attachment: nil)
        }
        func uploadAttachmentPhoto(conversation: StyleFriendsOpaqueRouteReference, jpeg: Data, operation: StyleFriendsDMOperationContext?) async throws -> StyleFriendsDMAttachment {
            uploads += 1; if !uploadErrors.isEmpty { throw uploadErrors.removeFirst() }; if let uploadError { throw uploadError }; if let gate = uploadRetryGate { uploadRetryGate = nil; await gate.suspendUntilReleased() }
            return .init(attachmentReference: attachmentRef, schemaVersion: 1, kind: .photo, snapshot: nil, imageAttachmentReference: StyleFriendsOpaqueRouteReference("image_test_reference_123456789012")!, state: "ready")
        }
        func associateAttachment(conversation: StyleFriendsOpaqueRouteReference, attachment: StyleFriendsOpaqueRouteReference, message: StyleFriendsOpaqueRouteReference, operation: StyleFriendsDMOperationContext?) async throws -> StyleFriendsDMAttachment {
            associations += 1; if !associationErrors.isEmpty { throw associationErrors.removeFirst() }; if let associationError { throw associationError }; if let gate = associationRetryGate { associationRetryGate = nil; await gate.suspendUntilReleased() }
            return .init(attachmentReference: attachment, schemaVersion: 1, kind: .photo, snapshot: nil, imageAttachmentReference: StyleFriendsOpaqueRouteReference("image_test_reference_123456789012")!, state: "associated")
        }
        func operationStatus(context: StyleFriendsDMOperationContext) async throws -> StyleFriendsDMOperationStatus { statuses += 1; if let gate = statusRetryGate { statusRetryGate = nil; await gate.suspend() }; return .init(operationID: context.operationID, outcome: outcome) }
    }


    @MainActor func testExplicitExpiredArchiveReleasesPhotoCoordinatorWithoutResendingOldAttachment() async throws {
        let spy = AttachmentLifecycleSpy()
        spy.uploadError = StyleFriendsDMError.networkUnavailable
        let journal = StyleFriendsDMOperationJournal(keychain: CapturingOperationKeychain())
        let coordinator = StyleFriendsAttachmentSendCoordinator(service: spy, conversation: .init("conversation_test")!,
            journal: journal, accountScope: { ("synthetic-a", "staging") })
        let first = await coordinator.sendNewPhoto(draft: .init(text: "old photo", clientMessageReference: "synthetic-old-photo-reference", parentMessageReference: nil), jpeg: Data([1]))
        XCTAssertEqual(first, .confirmedFailure)
        let context = try XCTUnwrap(coordinator.activeOperation)
        coordinator.stopWaitingAfterArchiving(operationID: context.operationID)
        XCTAssertEqual(coordinator.state, .failed("upload"), "A pending record cannot be bypassed.")
        _ = try journal.transition(operationID: context.operationID, expectedScopeTag: context.scopeTag, to: .reconciling)
        let record = try journal.transition(operationID: context.operationID, expectedScopeTag: context.scopeTag, to: .unknown)
        try journal.archiveExpiredUnknownAttachment(operationID: context.operationID, accountEnvironmentTag: record.accountEnvironmentTag,
            expectedScopeTag: context.scopeTag, now: Date().addingTimeInterval(172_800))
        coordinator.stopWaitingAfterArchiving(operationID: UUID())
        XCTAssertNotNil(coordinator.activeOperation)
        coordinator.stopWaitingAfterArchiving(operationID: context.operationID)
        XCTAssertEqual(coordinator.state, .discarded)
        XCTAssertNil(coordinator.activeOperation)
        XCTAssertEqual(spy.sends, 1); XCTAssertEqual(spy.uploads, 1); XCTAssertEqual(spy.associations, 0); XCTAssertEqual(spy.statuses, 0)
        await coordinator.retryPhoto()
        XCTAssertEqual(spy.sends, 1); XCTAssertEqual(spy.uploads, 1); XCTAssertEqual(spy.statuses, 0)
        spy.uploadError = nil
        let next = await coordinator.sendNewPhoto(draft: .init(text: "new photo", clientMessageReference: "synthetic-new-photo-reference", parentMessageReference: nil), jpeg: Data([2]))
        XCTAssertEqual(next, .confirmedAssociationSuccess)
        XCTAssertEqual(spy.sends, 2); XCTAssertEqual(spy.uploads, 2); XCTAssertEqual(spy.associations, 1)
        XCTAssertNotEqual(coordinator.activeOperation?.operationID, context.operationID)
        XCTAssertEqual(spy.sentDrafts.map(\.text), ["old photo", "new photo"])
    }

    @MainActor func testAttachmentCoordinatorSuccessfulPhotoLifecycleUsesOneOperation() async throws {
        let spy = AttachmentLifecycleSpy(); let conversation = try XCTUnwrap(StyleFriendsOpaqueRouteReference("conversation_test"))
        let coordinator = StyleFriendsAttachmentSendCoordinator(service: spy, conversation: conversation, journal: StyleFriendsDMOperationJournal(keychain: CapturingOperationKeychain()), accountScope: { ("synthetic-a", "staging") })
        let draft = StyleFriendsDMSendDraft(text: "photo", clientMessageReference: "client-photo", parentMessageReference: nil)
        await coordinator.sendPhoto(draft: draft, jpeg: Data([1,2,3]), operation: nil)
        XCTAssertEqual(spy.sends, 1); XCTAssertEqual(spy.uploads, 1); XCTAssertEqual(spy.associations, 1); XCTAssertEqual(coordinator.state, .sent)
    }

    @MainActor func testPhotoLostMessageResponseNeverResendsWhileStatusIsUnknown() async throws {
        let spy = AttachmentLifecycleSpy(); spy.sendError = StyleFriendsDMError.networkUnavailable; spy.outcome = .unknown
        let journal = StyleFriendsDMOperationJournal(keychain: CapturingOperationKeychain())
        let coordinator = StyleFriendsAttachmentSendCoordinator(service: spy, conversation: .init("conversation_test")!, journal: journal, accountScope: { ("synthetic-a", "staging") })
        let draft = StyleFriendsDMSendDraft(text: "Shared a photo", clientMessageReference: "synthetic-photo-retry-reference", parentMessageReference: nil)
        _ = await coordinator.sendNewPhoto(draft: draft, jpeg: Data([1]))
        let original = try XCTUnwrap(coordinator.activeDraft)
        await coordinator.retryPhoto()
        XCTAssertEqual(spy.sends, 1); XCTAssertEqual(spy.uploads, 0); XCTAssertEqual(spy.statuses, 1)
        XCTAssertEqual(coordinator.state, .ambiguous)
        XCTAssertEqual(coordinator.activeDraft, original)
        XCTAssertNotNil(original.operationID)
        XCTAssertEqual(coordinator.activeOperation?.scopeTag, try journal.scopeTag(account: "synthetic-a", environment: "staging", conversation: "conversation_test"))
        coordinator.discardPhoto()
        XCTAssertEqual(coordinator.state, .ambiguous)
    }

    @MainActor func testPhotoSuccessAllowsNextDistinctSendButNotReplayOfCompletedDraft() async throws {
        let spy = AttachmentLifecycleSpy()
        let coordinator = StyleFriendsAttachmentSendCoordinator(service: spy, conversation: .init("conversation_test")!, journal: StyleFriendsDMOperationJournal(keychain: CapturingOperationKeychain()), accountScope: { ("synthetic-a", "staging") })
        let first = StyleFriendsDMSendDraft(text: "first", clientMessageReference: "synthetic-first-reference", parentMessageReference: nil)
        _ = await coordinator.sendNewPhoto(draft: first, jpeg: Data([1]))
        let operation = coordinator.activeOperation
        _ = await coordinator.sendNewPhoto(draft: first, jpeg: Data([1]))
        XCTAssertEqual(spy.sends, 1)
        _ = await coordinator.sendNewPhoto(draft: .init(text: "second", clientMessageReference: "synthetic-second-reference", parentMessageReference: nil), jpeg: Data([2]))
        XCTAssertEqual(spy.sends, 2); XCTAssertEqual(spy.associations, 2)
        XCTAssertNotEqual(coordinator.activeOperation, operation)
    }

    @MainActor func testPhotoAccountSwitchBetweenMessageAndUploadStopsPipeline() async {
        let spy = AttachmentLifecycleSpy()
        var account = "synthetic-a"
        spy.onMessageAccepted = { account = "synthetic-b" }
        let coordinator = StyleFriendsAttachmentSendCoordinator(service: spy, conversation: .init("conversation_test")!, journal: StyleFriendsDMOperationJournal(keychain: CapturingOperationKeychain()), accountScope: { (account, "staging") })
        _ = await coordinator.sendNewPhoto(draft: .init(text: "photo", clientMessageReference: "synthetic-reference", parentMessageReference: nil), jpeg: Data([1]))
        XCTAssertEqual(spy.sends, 1); XCTAssertEqual(spy.uploads, 0); XCTAssertEqual(spy.associations, 0)
        await coordinator.retryPhoto()
        XCTAssertEqual(spy.statuses, 0); XCTAssertEqual(coordinator.state, .ambiguous)
    }

    @MainActor func testPhotoMissingAccountScopeFailsBeforeNetwork() async {
        let spy = AttachmentLifecycleSpy()
        let coordinator = StyleFriendsAttachmentSendCoordinator(service: spy, conversation: .init("conversation_test")!, journal: StyleFriendsDMOperationJournal(keychain: CapturingOperationKeychain()), accountScope: { nil })
        _ = await coordinator.sendNewPhoto(draft: .init(text: "photo", clientMessageReference: "synthetic-reference", parentMessageReference: nil), jpeg: Data([1]))
        XCTAssertEqual(spy.sends, 0); XCTAssertNil(coordinator.activeOperation)
    }

    @MainActor func testAttachmentCoordinatorUploadFailureDoesNotAssociateOrDeliver() async throws {
        let spy = AttachmentLifecycleSpy(); spy.uploadError = StyleFriendsDMError.invalidResponse
        let coordinator = StyleFriendsAttachmentSendCoordinator(service: spy, conversation: try XCTUnwrap(StyleFriendsOpaqueRouteReference("conversation_test")), journal: StyleFriendsDMOperationJournal(keychain: CapturingOperationKeychain()), accountScope: { ("synthetic-a", "staging") })
        await coordinator.sendPhoto(draft: .init(text: "photo", clientMessageReference: "client-photo", parentMessageReference: nil), jpeg: Data([1]), operation: nil)
        XCTAssertEqual(spy.sends, 1); XCTAssertEqual(spy.uploads, 1); XCTAssertEqual(spy.associations, 0)
        XCTAssertEqual(coordinator.state, .failed("upload")); XCTAssertEqual(coordinator.activePhoto, Data([1]))
    }

    @MainActor func testAttachmentCoordinatorDuplicateTapsAreSuppressed() async throws {
        let spy = AttachmentLifecycleSpy(); let coordinator = StyleFriendsAttachmentSendCoordinator(service: spy, conversation: try XCTUnwrap(StyleFriendsOpaqueRouteReference("conversation_test")), journal: StyleFriendsDMOperationJournal(keychain: CapturingOperationKeychain()), accountScope: { ("synthetic-a", "staging") })
        let draft = StyleFriendsDMSendDraft(text: "photo", clientMessageReference: "client-photo", parentMessageReference: nil)
        await withTaskGroup(of: Void.self) { group in
            group.addTask { _ = await coordinator.sendPhoto(draft: draft, jpeg: Data([1]), operation: nil) }
            group.addTask { _ = await coordinator.sendPhoto(draft: draft, jpeg: Data([1]), operation: nil) }
        }
        XCTAssertEqual(spy.sends, 1); XCTAssertLessThanOrEqual(spy.uploads, 1); XCTAssertLessThanOrEqual(spy.associations, 1)
    }

    @MainActor func testAttachmentCoordinatorPreparationFailureCreatesNoOperation() async throws {
        let spy = AttachmentLifecycleSpy(); let coordinator = StyleFriendsAttachmentSendCoordinator(service: spy, conversation: try XCTUnwrap(StyleFriendsOpaqueRouteReference("conversation_test")), journal: StyleFriendsDMOperationJournal(keychain: CapturingOperationKeychain()), accountScope: { ("synthetic-a", "staging") })
        await coordinator.sendPhoto(draft: .init(text: "photo", clientMessageReference: "client-empty", parentMessageReference: nil), jpeg: Data(), operation: nil)
        XCTAssertEqual(spy.sends, 0); XCTAssertEqual(spy.uploads, 0); XCTAssertEqual(spy.associations, 0); XCTAssertEqual(coordinator.state, .failed("preparation"))
    }

    @MainActor func testAttachmentCoordinatorAuthorizationOrMessageFailureStopsBeforeUpload() async throws {
        let spy = AttachmentLifecycleSpy(); spy.sendError = StyleFriendsDMError.signInRequired
        let coordinator = StyleFriendsAttachmentSendCoordinator(service: spy, conversation: try XCTUnwrap(StyleFriendsOpaqueRouteReference("conversation_test")), journal: StyleFriendsDMOperationJournal(keychain: CapturingOperationKeychain()), accountScope: { ("synthetic-a", "staging") })
        await coordinator.sendPhoto(draft: .init(text: "photo", clientMessageReference: "client-auth", parentMessageReference: nil), jpeg: Data([2]), operation: nil)
        XCTAssertEqual(spy.sends, 1); XCTAssertEqual(spy.uploads, 0); XCTAssertEqual(spy.associations, 0); XCTAssertNotEqual(coordinator.state, .sent)
    }

    @MainActor func testAttachmentCoordinatorAssociationFailureRetainsCanonicalOperation() async throws {
        let spy = AttachmentLifecycleSpy(); spy.associationError = StyleFriendsDMError.invalidResponse
        let context = StyleFriendsDMOperationContext(record: StyleFriendsDMOperationJournalRecord(schema: 1, operationID: UUID(), accountEnvironmentTag: "test", scopeTag: "scope", operationType: .preparedAttachment, payloadFingerprint: "fingerprint", phase: .preparingAttachment, createdAt: Date(), updatedAt: Date(), expiresAt: Date().addingTimeInterval(60), reconciliationCount: 0, retryCount: 0, opaqueServerReference: nil))
        let coordinator = StyleFriendsAttachmentSendCoordinator(service: spy, conversation: try XCTUnwrap(StyleFriendsOpaqueRouteReference("conversation_test")), journal: StyleFriendsDMOperationJournal(keychain: CapturingOperationKeychain()), accountScope: { ("synthetic-a", "staging") })
        await coordinator.sendPhoto(draft: .init(text: "photo", clientMessageReference: "client-assoc", parentMessageReference: nil), jpeg: Data([3]), operation: context)
        XCTAssertEqual(spy.sends, 1); XCTAssertEqual(spy.uploads, 1); XCTAssertEqual(spy.associations, 1); XCTAssertEqual(coordinator.activeOperation, context); XCTAssertNotEqual(coordinator.state, .sent)
    }

    @MainActor func testAttachmentCoordinatorAmbiguousAssociationReconcilesWithoutResend() async throws {
        let spy = AttachmentLifecycleSpy(); spy.associationError = StyleFriendsAttachmentOutcomeError.ambiguousOutcome; spy.outcome = .unknown
        let coordinator = StyleFriendsAttachmentSendCoordinator(service: spy, conversation: try XCTUnwrap(StyleFriendsOpaqueRouteReference("conversation_test")), journal: StyleFriendsDMOperationJournal(keychain: CapturingOperationKeychain()), accountScope: { ("synthetic-a", "staging") })
        let context = StyleFriendsDMOperationContext(record: .init(schema: 1, operationID: UUID(), accountEnvironmentTag: "test", scopeTag: "scope", operationType: .preparedAttachment, payloadFingerprint: "fingerprint", phase: .preparingAttachment, createdAt: Date(), updatedAt: Date(), expiresAt: Date().addingTimeInterval(60), reconciliationCount: 0, retryCount: 0, opaqueServerReference: nil))
        await coordinator.sendPhoto(draft: .init(text: "photo", clientMessageReference: "client-ambiguous", parentMessageReference: nil), jpeg: Data([4]), operation: context)
        await coordinator.retryPhoto()
        XCTAssertEqual(spy.sends, 1); XCTAssertEqual(spy.uploads, 1); XCTAssertEqual(spy.associations, 1); XCTAssertEqual(spy.statuses, 1); XCTAssertEqual(coordinator.state, .ambiguous)
    }

    @MainActor func testAttachmentCoordinatorConfirmedAssociationFailureRetriesAssociationOnly() async throws {
        let spy = AttachmentLifecycleSpy(); spy.associationErrors = [StyleFriendsAttachmentOutcomeError.confirmedFailure]
        let coordinator = StyleFriendsAttachmentSendCoordinator(service: spy, conversation: try XCTUnwrap(StyleFriendsOpaqueRouteReference("conversation_test")), journal: StyleFriendsDMOperationJournal(keychain: CapturingOperationKeychain()), accountScope: { ("synthetic-a", "staging") })
        let context = StyleFriendsDMOperationContext(record: .init(schema: 1, operationID: UUID(), accountEnvironmentTag: "test", scopeTag: "scope", operationType: .preparedAttachment, payloadFingerprint: "fingerprint", phase: .preparingAttachment, createdAt: Date(), updatedAt: Date(), expiresAt: Date().addingTimeInterval(60), reconciliationCount: 0, retryCount: 0, opaqueServerReference: nil))
        let draft = StyleFriendsDMSendDraft(text: "photo", clientMessageReference: "client-confirmed", parentMessageReference: nil)
        await coordinator.sendPhoto(draft: draft, jpeg: Data([9]), operation: context); await coordinator.retryPhoto()
        XCTAssertEqual(spy.sends, 1); XCTAssertEqual(spy.uploads, 1); XCTAssertEqual(spy.associations, 2); XCTAssertEqual(spy.statuses, 1); XCTAssertEqual(coordinator.state, .sent)
    }

    @MainActor func testAttachmentCoordinatorUnclassifiedAssociationErrorIsAmbiguousAndStatusFirst() async throws {
        let spy = AttachmentLifecycleSpy(); spy.associationError = NSError(domain: "transport", code: -1); spy.outcome = .unknown
        let coordinator = StyleFriendsAttachmentSendCoordinator(service: spy, conversation: try XCTUnwrap(StyleFriendsOpaqueRouteReference("conversation_test")), journal: StyleFriendsDMOperationJournal(keychain: CapturingOperationKeychain()), accountScope: { ("synthetic-a", "staging") })
        let context = StyleFriendsDMOperationContext(record: .init(schema: 1, operationID: UUID(), accountEnvironmentTag: "test", scopeTag: "scope", operationType: .preparedAttachment, payloadFingerprint: "fingerprint", phase: .preparingAttachment, createdAt: Date(), updatedAt: Date(), expiresAt: Date().addingTimeInterval(60), reconciliationCount: 0, retryCount: 0, opaqueServerReference: nil))
        await coordinator.sendPhoto(draft: .init(text: "photo", clientMessageReference: "client-unknown", parentMessageReference: nil), jpeg: Data([8]), operation: context); await coordinator.retryPhoto()
        XCTAssertEqual(spy.sends, 1); XCTAssertEqual(spy.uploads, 1); XCTAssertEqual(spy.associations, 1); XCTAssertEqual(spy.statuses, 1); XCTAssertEqual(coordinator.state, .ambiguous)
    }

    @MainActor func testAttachmentCoordinatorDuplicateAssociationRetryIsSuppressed() async throws {
        let spy = AttachmentLifecycleSpy(); spy.associationErrors = [StyleFriendsAttachmentOutcomeError.confirmedFailure]
        let gate = AssociationRetryGate(); spy.associationRetryGate = gate
        let coordinator = StyleFriendsAttachmentSendCoordinator(service: spy, conversation: try XCTUnwrap(StyleFriendsOpaqueRouteReference("conversation_test")), journal: StyleFriendsDMOperationJournal(keychain: CapturingOperationKeychain()), accountScope: { ("synthetic-a", "staging") })
        let context = StyleFriendsDMOperationContext(record: .init(schema: 1, operationID: UUID(), accountEnvironmentTag: "test", scopeTag: "scope", operationType: .preparedAttachment, payloadFingerprint: "fingerprint", phase: .preparingAttachment, createdAt: Date(), updatedAt: Date(), expiresAt: Date().addingTimeInterval(60), reconciliationCount: 0, retryCount: 0, opaqueServerReference: nil))
        await coordinator.sendPhoto(draft: .init(text: "photo", clientMessageReference: "client-dup-assoc", parentMessageReference: nil), jpeg: Data([7]), operation: context)
        let first = Task { await coordinator.retryPhoto() }
        await gate.waitUntilEntered()
        let second = Task { await coordinator.retryPhoto() }
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(spy.associations, 2)
        await gate.release(); await first.value; await second.value
        XCTAssertEqual(spy.sends, 1); XCTAssertEqual(spy.uploads, 1); XCTAssertEqual(spy.associations, 2); XCTAssertEqual(spy.statuses, 1); XCTAssertEqual(coordinator.state, .sent); XCTAssertEqual(coordinator.activeOperation, context)
    }

    @MainActor func testAttachmentCoordinatorDuplicateAmbiguousStatusRetryIsSuppressed() async throws {
        let spy = AttachmentLifecycleSpy(); spy.associationError = StyleFriendsAttachmentOutcomeError.ambiguousOutcome; spy.outcome = .committed
        let gate = StatusRetryGate(); spy.statusRetryGate = gate
        let coordinator = StyleFriendsAttachmentSendCoordinator(service: spy, conversation: try XCTUnwrap(StyleFriendsOpaqueRouteReference("conversation_test")), journal: StyleFriendsDMOperationJournal(keychain: CapturingOperationKeychain()), accountScope: { ("synthetic-a", "staging") })
        let context = StyleFriendsDMOperationContext(record: .init(schema: 1, operationID: UUID(), accountEnvironmentTag: "test", scopeTag: "scope", operationType: .preparedAttachment, payloadFingerprint: "fingerprint", phase: .preparingAttachment, createdAt: Date(), updatedAt: Date(), expiresAt: Date().addingTimeInterval(60), reconciliationCount: 0, retryCount: 0, opaqueServerReference: nil))
        await coordinator.sendPhoto(draft: .init(text: "photo", clientMessageReference: "client-status", parentMessageReference: nil), jpeg: Data([6]), operation: context)
        let first = Task { await coordinator.retryPhoto() }; await gate.waitUntilEntered(); let second = Task { await coordinator.retryPhoto() }
        try await Task.sleep(nanoseconds: 20_000_000); XCTAssertEqual(spy.statuses, 1); XCTAssertEqual(spy.sends, 1); XCTAssertEqual(spy.uploads, 1); XCTAssertEqual(spy.associations, 1)
        await gate.release(); await first.value; await second.value
        XCTAssertEqual(coordinator.state, .sent); XCTAssertEqual(coordinator.activeOperation, context)
    }

    @MainActor func testAttachmentCoordinatorDuplicateMessageRetryIsSuppressed() async throws {
        let spy = AttachmentLifecycleSpy(); spy.sendErrors = [StyleFriendsAttachmentOutcomeError.confirmedFailure]; let gate = AssociationRetryGate(); spy.messageRetryGate = gate
        let coordinator = StyleFriendsAttachmentSendCoordinator(service: spy, conversation: try XCTUnwrap(StyleFriendsOpaqueRouteReference("conversation_test")), journal: StyleFriendsDMOperationJournal(keychain: CapturingOperationKeychain()), accountScope: { ("synthetic-a", "staging") })
        let context = StyleFriendsDMOperationContext(record: .init(schema: 1, operationID: UUID(), accountEnvironmentTag: "test", scopeTag: "scope", operationType: .preparedAttachment, payloadFingerprint: "fingerprint", phase: .preparingAttachment, createdAt: Date(), updatedAt: Date(), expiresAt: Date().addingTimeInterval(60), reconciliationCount: 0, retryCount: 0, opaqueServerReference: nil))
        await coordinator.sendPhoto(draft: .init(text: "photo", clientMessageReference: "client-msg-retry", parentMessageReference: nil), jpeg: Data([5]), operation: context)
        let first = Task { await coordinator.retryPhoto() }; await gate.waitUntilEntered(); let second = Task { await coordinator.retryPhoto() }; try await Task.sleep(nanoseconds: 20_000_000); XCTAssertEqual(spy.sends, 2); await gate.release(); await first.value; await second.value
        XCTAssertEqual(spy.uploads, 1); XCTAssertEqual(spy.associations, 1); XCTAssertEqual(coordinator.state, .sent); XCTAssertEqual(coordinator.activeOperation, context)
    }

    @MainActor func testAttachmentCoordinatorDuplicateUploadRetryIsSuppressed() async throws {
        let spy = AttachmentLifecycleSpy(); spy.uploadErrors = [StyleFriendsAttachmentOutcomeError.confirmedFailure]; let gate = AssociationRetryGate(); spy.uploadRetryGate = gate
        let coordinator = StyleFriendsAttachmentSendCoordinator(service: spy, conversation: try XCTUnwrap(StyleFriendsOpaqueRouteReference("conversation_test")), journal: StyleFriendsDMOperationJournal(keychain: CapturingOperationKeychain()), accountScope: { ("synthetic-a", "staging") })
        let context = StyleFriendsDMOperationContext(record: .init(schema: 1, operationID: UUID(), accountEnvironmentTag: "test", scopeTag: "scope", operationType: .preparedAttachment, payloadFingerprint: "fingerprint", phase: .preparingAttachment, createdAt: Date(), updatedAt: Date(), expiresAt: Date().addingTimeInterval(60), reconciliationCount: 0, retryCount: 0, opaqueServerReference: nil))
        await coordinator.sendPhoto(draft: .init(text: "photo", clientMessageReference: "client-upload-retry", parentMessageReference: nil), jpeg: Data([4]), operation: context)
        let first = Task { await coordinator.retryPhoto() }; await gate.waitUntilEntered(); let second = Task { await coordinator.retryPhoto() }; try await Task.sleep(nanoseconds: 20_000_000); XCTAssertEqual(spy.uploads, 2); await gate.release(); await first.value; await second.value
        XCTAssertEqual(spy.sends, 1); XCTAssertEqual(spy.associations, 1); XCTAssertEqual(coordinator.state, .sent); XCTAssertEqual(coordinator.activeOperation, context)
    }

    @MainActor func testAttachmentCoordinatorConfirmedFailureCanBeDiscarded() async throws {
        let spy = AttachmentLifecycleSpy(); spy.uploadError = StyleFriendsAttachmentOutcomeError.confirmedFailure
        let coordinator = StyleFriendsAttachmentSendCoordinator(service: spy, conversation: try XCTUnwrap(StyleFriendsOpaqueRouteReference("conversation_test")), journal: StyleFriendsDMOperationJournal(keychain: CapturingOperationKeychain()), accountScope: { ("synthetic-a", "staging") })
        await coordinator.sendNewPhoto(draft: .init(text: "photo", clientMessageReference: "discard", parentMessageReference: nil), jpeg: Data([1]))
        await coordinator.retryPhoto(); coordinator.discardPhoto(); let before = (spy.sends, spy.uploads, spy.associations, spy.statuses); await coordinator.retryPhoto()
        XCTAssertEqual(coordinator.state, .discarded); XCTAssertNil(coordinator.activePhoto); XCTAssertNil(coordinator.activeDraft); XCTAssertNil(coordinator.activeOperation); XCTAssertEqual(spy.sends, before.0); XCTAssertEqual(spy.uploads, before.1); XCTAssertEqual(spy.associations, before.2); XCTAssertEqual(spy.statuses, before.3)
    }

    @MainActor func testAttachmentCoordinatorAmbiguousOutcomeCannotBeDiscarded() async throws {
        let spy = AttachmentLifecycleSpy(); spy.associationError = StyleFriendsAttachmentOutcomeError.ambiguousOutcome
        let coordinator = StyleFriendsAttachmentSendCoordinator(service: spy, conversation: try XCTUnwrap(StyleFriendsOpaqueRouteReference("conversation_test")), journal: StyleFriendsDMOperationJournal(keychain: CapturingOperationKeychain()), accountScope: { ("synthetic-a", "staging") })
        await coordinator.sendNewPhoto(draft: .init(text: "photo", clientMessageReference: "ambiguous-discard", parentMessageReference: nil), jpeg: Data([2])); let operation = coordinator.activeOperation
        coordinator.discardPhoto(); XCTAssertEqual(coordinator.state, .ambiguous); XCTAssertEqual(coordinator.activeOperation, operation); XCTAssertEqual(spy.statuses, 0)
    }

    @MainActor func testAttachmentCoordinatorNewSendAfterDiscardUsesFreshOperation() async throws {
        let spy = AttachmentLifecycleSpy(); spy.uploadError = StyleFriendsAttachmentOutcomeError.confirmedFailure
        let coordinator = StyleFriendsAttachmentSendCoordinator(service: spy, conversation: try XCTUnwrap(StyleFriendsOpaqueRouteReference("conversation_test")), journal: StyleFriendsDMOperationJournal(keychain: CapturingOperationKeychain()), accountScope: { ("synthetic-a", "staging") })
        await coordinator.sendNewPhoto(draft: .init(text: "old", clientMessageReference: "old", parentMessageReference: nil), jpeg: Data([3])); let old = coordinator.activeOperation; coordinator.discardPhoto(); spy.uploadError = nil
        await coordinator.sendNewPhoto(draft: .init(text: "new", clientMessageReference: "new", parentMessageReference: nil), jpeg: Data([4])); XCTAssertNotEqual(coordinator.activeOperation, old); XCTAssertEqual(coordinator.state, .sent); XCTAssertEqual(spy.sends, 2); XCTAssertEqual(spy.uploads, 2); XCTAssertEqual(spy.associations, 1)
    }
    func testOutgoingDeliveryLabelsAreTruthfulAndIncomingShowsReceivedStatus() throws {
        let source = try String(contentsOfFile: "StyleMatchAI/StyleFriendsChatUI.swift", encoding: .utf8)
        XCTAssertTrue(source.contains("Text(\"Sending…\")"))
        XCTAssertTrue(source.contains("Text(\"Sent\")"))
        XCTAssertTrue(source.contains("Text(\"Checking status…\")"))
        XCTAssertTrue(source.contains("Text(\"Failed\")"))
        XCTAssertTrue(source.contains("Text(\"Received\")"))
        XCTAssertFalse(source.contains("if message.sender != .selfUser { Button(\"Reply\""))
        XCTAssertTrue(source.contains("Checking status. No resend performed."))
    }
    private final class CapturingOperationKeychain: StyleFriendsDMOperationKeychainServing {
        var additions: [[String: Any]] = []
        var failOperationAdds = false
        private var values: [String: Data] = [:]
        private func key(_ query: [String: Any]) -> String {
            "\(query[kSecAttrService as String] as? String ?? "")|\(query[kSecAttrAccount as String] as? String ?? "")"
        }
        func add(_ query: [String: Any]) -> OSStatus {
            additions.append(query)
            if failOperationAdds, (query[kSecAttrService as String] as? String)?.contains(".operation.v1") == true { return errSecAuthFailed }
            guard let data = query[kSecValueData as String] as? Data else { return errSecParam }
            let itemKey = key(query); guard values[itemKey] == nil else { return errSecDuplicateItem }
            values[itemKey] = data; return errSecSuccess
        }
        func read(_ query: [String: Any]) -> StyleFriendsDMOperationKeychainRead {
            let service = query[kSecAttrService as String] as? String ?? ""
            let account = query[kSecAttrAccount as String] as? String
            let found = values.compactMap { key, value in key.hasPrefix(service + "|") && (account == nil || key == service + "|" + account!) ? value : nil }
            return .init(status: found.isEmpty ? errSecItemNotFound : errSecSuccess, values: found)
        }
        func update(_ query: [String: Any], values update: [String: Any]) -> OSStatus {
            guard let data = update[kSecValueData as String] as? Data, self.values[key(query)] != nil else { return errSecItemNotFound }
            self.values[key(query)] = data; return errSecSuccess
        }
        func delete(_ query: [String: Any]) -> OSStatus { values.removeValue(forKey: key(query)) == nil ? errSecItemNotFound : errSecSuccess }
        func journalData() -> Data? { values.first { $0.key.contains(".operation.v1|") }?.value }
    }

    private actor OperationStatusSpy: StyleFriendsDMOperationStatusServing {
        private let outcomes: [UUID: StyleFriendsDMOperationStatus.Outcome]
        private(set) var calls = 0
        init(outcomes: [UUID: StyleFriendsDMOperationStatus.Outcome]) { self.outcomes = outcomes }
        func operationStatus(context: StyleFriendsDMOperationContext) async throws -> StyleFriendsDMOperationStatus {
            calls += 1
            try await Task.sleep(nanoseconds: 20_000_000)
            return .init(operationID: context.operationID, outcome: outcomes[context.operationID] ?? .unknown)
        }
        func callCount() -> Int { calls }
    }
    func testAuthenticatedLocalWorkerReactionAndReplyIntegrationWhenConfigured() async throws {
        guard let endpoint = ProcessInfo.processInfo.environment["STYLE_FRIENDS_LOCAL_INTEGRATION_URL"],
              let baseURL = URL(string: endpoint) else {
            throw XCTSkip("Requires the disposable local Style Friends Worker fixture.")
        }
        let session = StyleMatchAccountSession(token: "abcdefghijklmnopqrstuvwxyz123456", expiresAt: Date().addingTimeInterval(300))
        let service = StyleFriendsService(baseURL: baseURL, session: .shared, accountSession: { session })
        let post = try XCTUnwrap(StyleFriendsOpaqueRouteReference("post_abcdefghijklmnopqrstuvwx"))
        let comment = try XCTUnwrap(StyleFriendsOpaqueRouteReference("comment_abcdefghijklmnopqrstuv"))

        for reaction in StyleFriendReactionKind.allCases {
            let summary = try await service.setReaction(target: .post(post), reaction: reaction)
            XCTAssertEqual(summary.viewerReaction, reaction)
            XCTAssertEqual(summary.count(for: reaction), 1)
        }
        let removedPostReaction = try await service.setReaction(target: .post(post), reaction: nil)
        XCTAssertNil(removedPostReaction.viewerReaction)

        for reaction in StyleFriendReactionKind.allCases {
            let summary = try await service.setReaction(target: .comment(comment), reaction: reaction)
            XCTAssertEqual(summary.viewerReaction, reaction)
            XCTAssertEqual(summary.count(for: reaction), 1)
        }
        let reply = try await service.addComment(postReference: post, draft: .init(text: "Local integration reply", parentCommentReference: comment)).comment
        let unwrappedReply = try XCTUnwrap(reply)
        XCTAssertEqual(unwrappedReply.replyPreview?.parentCommentReference, comment)
        XCTAssertTrue(unwrappedReply.replyPreview?.parentAvailable == true)

        let expired = StyleFriendsService(baseURL: baseURL, session: .shared, accountSession: { .init(token: "abcdefghijklmnopqrstuvwxyz123456", expiresAt: .distantPast) })
        do {
            _ = try await expired.setReaction(target: .post(post), reaction: .like)
            XCTFail("Expired local session must fail before a request is sent.")
        } catch {
            XCTAssertEqual(error as? StyleFriendsServiceError, .signInRequired)
        }
        let nonFriend = StyleFriendsService(baseURL: baseURL, session: .shared, accountSession: { .init(token: "zyxwvutsrqponmlkjihgfedcba987654", expiresAt: Date().addingTimeInterval(300)) })
        do {
            _ = try await nonFriend.setReaction(target: .post(post), reaction: .like)
            XCTFail("A current non-friend must not retain an optimistic reaction.")
        } catch {
            XCTAssertEqual(error as? StyleFriendsServiceError, .unavailable)
        }
        let invalid = StyleFriendsService(baseURL: baseURL, session: .shared, accountSession: { .init(token: "0123456789abcdefghijklmnopqrstuv", expiresAt: Date().addingTimeInterval(300)) })
        do {
            _ = try await invalid.setReaction(target: .post(post), reaction: .like)
            XCTFail("An invalid Worker session must be rejected.")
        } catch {
            XCTAssertEqual(error as? StyleFriendsServiceError, .signInRequired)
        }
    }

    func testDirectMessagePresentationFoundationIsFixtureOnlyAndIsolated() throws {
        XCTAssertTrue(StyleFriendsDirectMessagePresentationBoundary.workerAuthorityRequiredBeforeLiveMessaging)
        XCTAssertTrue(StyleFriendsDirectMessagePresentationBoundary.fixturesArePreviewAndTestOnly)
        XCTAssertTrue(StyleFriendsDirectMessagePresentationBoundary.privateCloudKitStorageForbidden)
        XCTAssertTrue(StyleFriendsDirectMessagePresentationBoundary.profileClosetScanAndAIMemoryIsolationRequired)
        XCTAssertTrue(StyleFriendsDirectMessagePresentationBoundary.AIStylistConversationReuseForbidden)
        XCTAssertEqual(StyleFriendsChatPresentationFixtures.label, "Preview/test only")
        XCTAssertEqual(StyleFriendsChatPresentationFixtures.messages.count, 3)
        XCTAssertEqual(StyleFriendsChatPresentationFixtures.messages.last?.delivery, .failed)
    }

    func testDirectMessagePresentationModelsAreTruthfulAndBounded() throws {
        XCTAssertEqual(StyleFriendsConversationPresentationState.populated, .populated)
        XCTAssertEqual(StyleFriendsFriendMessageDelivery.sending.rawValue, "sending")
        XCTAssertEqual(StyleFriendsFriendMessageDelivery.sent.rawValue, "sent")
        XCTAssertEqual(StyleFriendsFriendMessageDelivery.underReview.rawValue, "underReview")
        XCTAssertEqual(StyleFriendsFriendMessageDelivery.removed.rawValue, "removed")
        XCTAssertEqual(StyleFriendsFriendMessageDelivery.failed.rawValue, "failed")
        let unavailable = StyleFriendsFriendMessageParentPreview(senderDisplayName: "Jordan", text: "removed", parentAvailable: false)
        XCTAssertEqual(unavailable.presentationText, "Original message unavailable")
        XCTAssertEqual(StyleFriendsChatPresentationFixtures.messages[1].sharedOutfit?.scoreSnapshot, 92)
        XCTAssertEqual(StyleFriendsChatPresentationFixtures.messages[0].reactionSummary?.topReactions().map(\.kind), [.fire, .love, .stylish])
    }

    func testDMAttachmentSnapshotsAreBoundedAndCannotCarryPrivateSourceReferences() throws {
        let snapshot = try XCTUnwrap(StyleFriendsDMAttachmentSnapshot(
            title: "Dinner outfit", occasion: "Dinner", score: 91,
            summary: "Navy jacket and cream trousers"
        ))
        XCTAssertEqual(snapshot.title, "Dinner outfit")
        XCTAssertEqual(snapshot.score, 91)
        XCTAssertNil(StyleFriendsDMAttachmentSnapshot(title: "", occasion: nil, score: nil, summary: "Share"))
        XCTAssertNil(StyleFriendsDMAttachmentSnapshot(title: "Look", occasion: nil, score: 101, summary: "Share"))

        let source = try source("StyleMatchAI/StyleFriendsDirectMessages.swift")
        XCTAssertTrue(source.contains("no local scan, Closet, CloudKit, account, AI-memory, or location"))
        XCTAssertTrue(source.contains("createAttachmentSnapshot"))
        XCTAssertTrue(source.contains("associateAttachment"))
        XCTAssertFalse(source.contains("CloudKitRecordID"))
    }

    func testTypedDirectMessageDomainIsWorkerShapedAndFailClosedUntilConnected() async throws {
        let reference = try XCTUnwrap(StyleFriendsOpaqueRouteReference("conversation_123"))
        let terms = StyleFriendsDMTermsState(requiredTermsVersion: StyleFriendsDMTermsState.canonicalRequiredVersion, acceptedTermsVersion: nil, acceptedAt: nil)
        XCTAssertFalse(terms.canSend)
        XCTAssertTrue(StyleFriendsDirectMessageBoundary.workerClientRequiresExplicitRuntimeAuthority)
        XCTAssertTrue(StyleFriendsDirectMessageBoundary.noLocalTermsAcceptance)
        XCTAssertTrue(StyleFriendsDirectMessageBoundary.privateDataIsolationRequired)
        XCTAssertEqual(StyleFriendsDMRuntimeAuthority.resolve(rawValue: nil, debugBuild: true), .disabled)
        let service = StyleFriendsUnavailableDirectMessageService()
        do { _ = try await service.messages(conversation: reference, cursor: nil); XCTFail("Unavailable service must not fabricate messages") }
        catch { XCTAssertEqual(error as? StyleFriendsDMError, .dmUnavailable) }
        XCTAssertEqual(StyleFriendsDMPresentationMapper.userMessage(for: .safetyUnavailable), "Messaging is temporarily unavailable. Please try again later.")
        XCTAssertEqual(StyleFriendsDMPresentationMapper.userMessage(for: .signInRequired), "Sign in to Style Friends to continue.")
    }

    func testDirectMessageConversationFailurePresentationKeepsAuthenticationSeparateFromConnectivity() {
        XCTAssertEqual(StyleFriendsDMConversationFailurePresentation.resolve(.signInRequired), .signInRequired)
        XCTAssertEqual(StyleFriendsDMConversationFailurePresentation.resolve(.networkUnavailable), .networkUnavailable)
        XCTAssertEqual(StyleFriendsDMConversationFailurePresentation.resolve(.serviceUnavailable), .serviceUnavailable)
        XCTAssertEqual(StyleFriendsDMConversationFailurePresentation.resolve(.invalidResponse), .serviceUnavailable)
        XCTAssertEqual(StyleFriendsDMConversationFailurePresentation.signInRequired.title, "Your Style Friends session expired")
        XCTAssertEqual(StyleFriendsDMConversationFailurePresentation.signInRequired.detail, "Sign in again to continue with Style Friends.")
    }

    func testDirectMessageReadinessRecordsOnlySafeDependencyStates() {
        let initial = StyleFriendsDMRuntimeReadiness(
            accountSessionPresent: true,
            sessionEnvironmentMatch: true,
            socialAuthorityReady: true,
            dmAuthorityReady: true,
            relationshipIsFriend: true,
            conversationServiceReady: nil,
            failure: nil
        )
        XCTAssertFalse(initial.finalReady)
        let failed = initial.recordingConversationResult(.failure(.dmUnavailable))
        XCTAssertFalse(failed.finalReady)
        XCTAssertEqual(failed.conversationServiceReady, false)
        XCTAssertEqual(failed.failure, .dmUnavailable)
        let passed = initial.recordingConversationResult(.success(()))
        XCTAssertTrue(passed.finalReady)
        XCTAssertNil(passed.failure)
    }

    func testFriendListHydrationUsesOnlyThePublicSocialProjection() throws {
        let reference = try XCTUnwrap(StyleFriendAccountReference("sf_" + String(repeating: "a", count: 43)))
        let item = StyleFriendListItem(
            socialReference: reference,
            displayName: nil,
            avatarReference: nil,
            state: .friends,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let publicProfile = StyleFriendVisibleProfile(
            displayName: "Jordan",
            avatarReference: "social_image_reference_abcdefghijklmnop",
            avatarState: nil,
            styleBio: "Modern workwear",
            styleCategories: [.modern],
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_001),
            isDiscoverable: nil
        )
        let hydrated = item.hydrated(with: publicProfile)
        XCTAssertEqual(hydrated.socialReference, reference)
        XCTAssertEqual(hydrated.state, .friends)
        XCTAssertEqual(hydrated.displayName, "Jordan")
        XCTAssertEqual(hydrated.avatarReference, "social_image_reference_abcdefghijklmnop")
    }

    func testMissingPublicProfileUsesIntentionalSetupAndNeverPrivateProfileFallback() throws {
        let source = try source("StyleMatchAI/StyleFriendsView.swift")
        XCTAssertTrue(source.contains("socialProfileEstablished = false"))
        XCTAssertTrue(source.contains("Create your Style Friends profile"))
        XCTAssertTrue(source.contains("Create Social Profile"))
        XCTAssertTrue(source.contains("Create your public Style Friends profile before adding a photo."))
        XCTAssertTrue(source.contains("KigoStylist never copies your private Profile, Closet, scans, AI Memory, Calendar, location, or account information into this profile."))
        XCTAssertFalse(source.contains("StyleMatchProfileStore"))
        XCTAssertFalse(source.contains("CloudKitRecordID"))
    }

    func testSupportCenterDomainIsDedicatedFailClosedAndDiagnosticBounded() async throws {
        XCTAssertFalse(StyleMatchSupportRuntimeAuthority.enabled)
        XCTAssertNotNil(StyleMatchSupportReference("support_case_abcdefghijklmnopqrstuvwx"))
        XCTAssertNil(StyleMatchSupportReference("raw-account-key"))
        XCTAssertThrowsError(try JSONDecoder().decode(StyleMatchSupportReference.self, from: Data("\"raw-account-key\"".utf8)))
        XCTAssertEqual(SupportCategory.accountDeletion.title, "Account Deletion")
        XCTAssertEqual(SupportCaseStatus.underReview.rawValue, "underReview")
        XCTAssertEqual(SupportEscalationState.humanSupportUnavailable, .humanSupportUnavailable)
        let service = StyleMatchUnavailableSupportService()
        do {
            _ = try await service.cases()
            XCTFail("Unavailable support must not fabricate support cases.")
        } catch {
            XCTAssertEqual(error as? SupportServiceError, .supportUnavailable)
        }
        let diagnostics = SupportDiagnostics.current(errorCategory: "network")
        XCTAssertEqual(diagnostics.platform, "iOS")
        XCTAssertEqual(diagnostics.errorCategory, "network")
    }

    func testSupportRuntimeFactoryRequiresExplicitStagingAuthorityExactHostAndCurrentSession() throws {
        let staging = try XCTUnwrap(URL(string: "https://stylematch-friends-staging.sabastine-7000.workers.dev"))
        let wrongHost = try XCTUnwrap(URL(string: "https://api.stylematchpro.com"))
        let current = StyleMatchAccountSession(token: "abcdefghijklmnopqrstuvwxyz123456", expiresAt: Date().addingTimeInterval(300))

        XCTAssertTrue(StyleMatchSupportServiceFactory.resolve(authority: .stagingAuthorized, baseURL: staging, accountSession: { current }) is StyleMatchHTTPSupportService)
        XCTAssertTrue(StyleMatchSupportServiceFactory.resolve(authority: .disabled, baseURL: staging, accountSession: { current }) is StyleMatchUnavailableSupportService)
        XCTAssertTrue(StyleMatchSupportServiceFactory.resolve(authority: .stagingAuthorized, baseURL: wrongHost, accountSession: { current }) is StyleMatchUnavailableSupportService)
        XCTAssertTrue(StyleMatchSupportServiceFactory.resolve(authority: .stagingAuthorized, baseURL: staging, accountSession: { .init(token: current.token, expiresAt: .distantPast) }) is StyleMatchSignInRequiredSupportService)
        XCTAssertEqual(StyleMatchSupportRuntimeAuthority.resolve(rawValue: "stagingAuthorized"), .stagingAuthorized)
        XCTAssertEqual(StyleMatchSupportRuntimeAuthority.resolve(rawValue: "disabled"), .disabled)
    }

    func testSupportSourceHasTruthfulCasesAndBugReportStatesWithoutSilentSubmission() throws {
        let source = try source("StyleMatchAI/StyleMatchSupportCenter.swift")
        XCTAssertTrue(source.contains("enum CaseListState"))
        XCTAssertTrue(source.contains("enum CaseDetailState"))
        XCTAssertTrue(source.contains("enum BugReportState"))
        XCTAssertTrue(source.contains("AI Customer Service"))
        XCTAssertTrue(source.contains("consentRequired"))
        XCTAssertTrue(source.contains("aiConsentRequired"))
        XCTAssertTrue(source.contains("SupportChatRequirement(title: \"Sign in required\""))
        XCTAssertTrue(source.contains("SupportChatRequirement(title: \"Support-data consent required\""))
        XCTAssertTrue(source.contains("Report a Problem"))
        XCTAssertFalse(source.contains("Automated support is available for this staging beta"))
        XCTAssertTrue(source.contains("func submitBugReport(_ report: SupportBugReport) async"))
        XCTAssertTrue(source.contains("Your case has been marked for escalation. Human contact is not configured."))
        XCTAssertTrue(source.contains("Private messages, photos, Profile, Closet, scans, and AI Memory are not included."))
        XCTAssertFalse(source.contains("try? await model.service.submitBugReport"))
    }

    func testCustomerFacingSupportAndSocialCopyAvoidsInternalEnvironmentTerms() throws {
        let support = try source("StyleMatchAI/StyleMatchSupportCenter.swift")
        let chat = try source("StyleMatchAI/StyleFriendsChatUI.swift")
        let friends = try source("StyleMatchAI/StyleFriendsView.swift")
        let notifications = try source("StyleMatchAI/StyleFriendsNotifications.swift")

        XCTAssertTrue(support.contains("Report a Problem"))
        XCTAssertFalse(support.contains("Report a Bug"))
        XCTAssertTrue(support.contains("AI Customer Service is unavailable right now."))
        XCTAssertTrue(chat.contains("StyleMatchSessionRecoveryCopy.title"))
        XCTAssertTrue(chat.contains("StyleMatchSessionRecoveryCopy.detail(for: \"Style Friends\")"))
        XCTAssertTrue(chat.contains("StyleMatchSessionRecoveryCopy.actionTitle"))
        XCTAssertFalse(chat.contains("staging account authority"))
        XCTAssertTrue(friends.contains("Profile photos are unavailable right now."))
        XCTAssertFalse(friends.contains("unavailable in this beta"))
        XCTAssertFalse(friends.contains("secure feed endpoint"))
        XCTAssertTrue(notifications.contains("Style Friends notifications"))
        XCTAssertFalse(notifications.contains("Section(\"Device Registration\")"))
    }

    func testSupportHomeAndChatConstrainReadableIPadContentWidth() throws {
        let source = try source("StyleMatchAI/StyleMatchSupportCenter.swift")
        XCTAssertEqual(source.components(separatedBy: ".frame(maxWidth: 720)").count - 1, 2)
        XCTAssertTrue(source.contains(".frame(maxWidth: .infinity)\n            .appScreenBackground(.profile)\n            .navigationTitle(\"Support Chat\")"))
    }

    func testSupportCaseMessagesEscalationAndDiagnosticsStayBoundedAndTruthful() throws {
        let source = try source("StyleMatchAI/StyleMatchSupportCenter.swift")
        XCTAssertTrue(source.contains("enum CaseMessageState"))
        XCTAssertTrue(source.contains("enum EscalationState"))
        XCTAssertTrue(source.contains("func appendCaseMessage"))
        XCTAssertTrue(source.contains("await loadCase(reference)"))
        XCTAssertTrue(source.contains("func requestEscalation"))
        XCTAssertTrue(source.contains("This does not confirm that a person will contact you."))
        XCTAssertTrue(source.contains("enum SupportSurface"))
        XCTAssertTrue(source.contains("Private messages, photos, Profile, Closet, scans, AI Memory, location, and account identifiers are not included."))
        XCTAssertFalse(source.contains("A representative will contact you"))
    }

    func testSupportCenterSourceSeparatesSupportFromStylistFriendsAndPrivateData() throws {
        let supportSource = try source("StyleMatchAI/StyleMatchSupportCenter.swift")
        let profile = try source("StyleMatchAI/ProfileView.swift")
        XCTAssertTrue(profile.contains("StyleMatchSupportView(onOpenAccountDeletion:"))
        XCTAssertTrue(supportSource.contains("protocol StyleMatchSupportService"))
        XCTAssertTrue(supportSource.contains("StyleMatchUnavailableSupportService"))
        XCTAssertTrue(supportSource.contains("StyleMatchHTTPSupportService"))
        XCTAssertTrue(supportSource.contains("enum StyleMatchSupportRuntimeAuthority"))
        XCTAssertTrue(supportSource.contains("StyleMatchSupportServiceFactory"))
        XCTAssertTrue(supportSource.contains("/v1/support/cases"))
        XCTAssertTrue(supportSource.contains("/v1/support/chat"))
        XCTAssertTrue(supportSource.contains("/v1/support/bug-reports"))
        XCTAssertTrue(supportSource.contains("Private messages, photos, Profile, Closet, scans, and AI Memory are not included."))
        XCTAssertTrue(supportSource.contains("Screenshots are unavailable until a support upload authority is configured."))
        XCTAssertTrue(supportSource.contains("onOpenAccountDeletion"))
        XCTAssertTrue(supportSource.contains("Opens the existing account deletion confirmation flow."))
        XCTAssertFalse(supportSource.contains("StylistChatView"))
        XCTAssertFalse(supportSource.contains("FriendChatView"))
        XCTAssertFalse(supportSource.contains("CKContainer"))
        XCTAssertFalse(supportSource.contains("AIPersistentMemoryStore"))
        XCTAssertFalse(profile.contains("hello@goodnessoflifeandfun.com"))
    }

    func testSupportContactRemainsAvailableWhenAIIsDisabledOrUnavailable() throws {
        let supportSource = try source("StyleMatchAI/StyleMatchSupportCenter.swift")
        XCTAssertTrue(supportSource.contains("static let email = \"hello@goodnessoflifeandfun.com\""))
        XCTAssertTrue(supportSource.contains("Link(StyleMatchSupportContact.email, destination: StyleMatchSupportContact.mailtoURL)"))
        XCTAssertTrue(supportSource.contains("supportAvailability\n                    humanSupportContact"))
        XCTAssertTrue(supportSource.contains("For help or privacy questions, email KigoStylist Support directly."))
        XCTAssertTrue(supportSource.contains("Opens your email app."))
    }

    func testDirectMessageTransportRequiresExactStagingOrProductionHostAndExplicitAuthority() throws {
        let stagingURL = try XCTUnwrap(URL(string: "https://stylematch-friends-staging.sabastine-7000.workers.dev"))
        let productionURL = try XCTUnwrap(URL(string: "https://api.stylematchpro.com"))
        XCTAssertNotNil(StyleFriendsDMStagingTransportConfiguration(baseURL: stagingURL))
        XCTAssertNotNil(StyleFriendsDMStagingTransportConfiguration(baseURL: productionURL))
        XCTAssertNil(StyleFriendsDMStagingTransportConfiguration(baseURL: URL(string: "http://stylematch-friends-staging.sabastine-7000.workers.dev")!))
        XCTAssertNil(StyleFriendsDMStagingTransportConfiguration(baseURL: URL(string: "https://stylematch-friends-staging.sabastine-7000.workers.dev:443")!))
        XCTAssertNil(StyleFriendsDMStagingTransportConfiguration(baseURL: URL(string: "https://stylematch-friends-staging.sabastine-7000.workers.dev?redirect=elsewhere")!))
        XCTAssertNil(StyleFriendsDMStagingTransportConfiguration(baseURL: URL(string: "https://example.com")!))
        XCTAssertEqual(StyleFriendsDMRuntimeAuthority.resolve(rawValue: "stagingAuthorized", debugBuild: true), .stagingAuthorized)
        XCTAssertEqual(StyleFriendsDMRuntimeAuthority.resolve(rawValue: "productionAuthorized", debugBuild: true), .productionAuthorized)
        XCTAssertEqual(StyleFriendsDMRuntimeAuthority.resolve(rawValue: "productionAuthorized", debugBuild: false), .productionAuthorized)
        XCTAssertEqual(StyleFriendsDMRuntimeAuthority.resolve(rawValue: "stagingAuthorized", debugBuild: false), .disabled)
        XCTAssertTrue(StyleFriendsDMRuntimeAuthority.apnsIndependent)
        XCTAssertEqual(StyleFriendsDMStagingTransportConfiguration.maximumRequestBytes, 16 * 1024)
        XCTAssertEqual(StyleFriendsDMStagingTransportConfiguration.maximumResponseBytes, 128 * 1024)
    }

    func testDirectMessageLiveSourceTransportIsTypedBoundedAndMapsOnlyKnownWorkerErrors() throws {
        let source = try source("StyleMatchAI/StyleFriendsDirectMessages.swift")
        XCTAssertTrue(source.contains("struct StyleFriendsHTTPDirectMessageService"))
        XCTAssertTrue(source.contains("StyleFriendsDMStagingTransportConfiguration.maximumRequestBytes"))
        XCTAssertTrue(source.contains("StyleFriendsDMStagingTransportConfiguration.maximumResponseBytes"))
        XCTAssertTrue(source.contains("request.timeoutInterval"))
        XCTAssertTrue(source.contains("Authorization"))
        XCTAssertTrue(source.contains("/v1/friends/direct-messages/terms"))
        XCTAssertTrue(source.contains("/v1/friends/conversations"))
        XCTAssertTrue(source.contains("/reaction"))
        XCTAssertTrue(source.contains("/report"))
        XCTAssertTrue(source.contains("/read"))
        XCTAssertTrue(source.contains("/block"))
        XCTAssertTrue(source.contains("StyleFriendsDMError(rawValue"))
        XCTAssertFalse(source.contains("print(account.token)"))
        XCTAssertFalse(source.contains("print(accountKey)"))
    }

    func testDirectMessageActionControllerPreservesStableRetryAndPrivateReadAuthority() throws {
        let source = try source("StyleMatchAI/StyleFriendsDirectMessages.swift")
        XCTAssertTrue(source.contains("final class StyleFriendsDMChatActionController"))
        XCTAssertTrue(source.contains("originalDraft: StyleFriendsDMSendDraft"))
        XCTAssertTrue(source.contains("await send(conversation: conversation, draft: originalDraft)"))
        XCTAssertTrue(source.contains("markRead(conversation: StyleFriendsOpaqueRouteReference"))
        XCTAssertTrue(source.contains("func block(friend: StyleFriendAccountReference)"))
        XCTAssertFalse(source.contains("peerRead"))
    }

    func testDirectMessageTermsGateRequiresServerConfirmationAndNeverPersistsLocalConsent() async throws {
        let gate = await MainActor.run { StyleFriendsDMFirstSendTermsGate() }
        let service = StyleFriendsUnavailableDirectMessageService()
        await gate.refresh(using: service)
        let canSend = await MainActor.run { gate.canSend }
        let state = await MainActor.run { gate.state }
        XCTAssertFalse(canSend)
        XCTAssertEqual(state, .unavailable)
        let source = try source("StyleMatchAI/StyleFriendsDirectMessages.swift")
        XCTAssertTrue(source.contains("style-friends-dm-ugc-v1"))
        XCTAssertTrue(source.contains("try await service.acceptTerms"))
        XCTAssertFalse(source.contains("UserDefaults"))
    }

    func testDirectMessageWorkerStatusMappingKeepsReviewAndRemovalTruthful() throws {
        let reference = try XCTUnwrap(StyleFriendsOpaqueRouteReference("message_123"))
        let underReview = StyleFriendsDMMessage(messageReference: reference, clientMessageReference: "client_123456789012345", senderRole: "self", text: "pending", deletedOrUnavailable: false, deliveryState: .underReview, recipientVisible: false, createdAt: .now, updatedAt: .now, parentPreview: nil, reactionSummary: nil, attachment: nil)
        let removed = StyleFriendsDMMessage(messageReference: reference, clientMessageReference: "client_123456789012345", senderRole: "friend", text: nil, deletedOrUnavailable: true, deliveryState: .removed, recipientVisible: false, createdAt: .now, updatedAt: .now, parentPreview: nil, reactionSummary: nil, attachment: nil)
        XCTAssertEqual(StyleFriendsDMPresentationMapper.message(underReview, selfDisplayName: "A", friendDisplayName: "B").delivery, .underReview)
        XCTAssertEqual(StyleFriendsDMPresentationMapper.message(removed, selfDisplayName: "A", friendDisplayName: "B").delivery, .removed)
    }

    func testDirectMessageConversationDecodesWorkerSocialProjectionWithoutRawAccountIdentity() throws {
        let friend = "sf_" + String(repeating: "a", count: 43)
        let json = """
        {"conversation_ref":"conversation_123","friend":{"social_reference":"\(friend)"},"friend_display_name":"Latisha","friend_avatar_reference":"avatar_latisha","latest_message_preview":{"text":"Hi","sender_role":"self"},"unread_count":2}
        """.data(using: .utf8)!
        let conversation = try JSONDecoder().decode(StyleFriendsDMConversation.self, from: json)
        XCTAssertEqual(conversation.friendSocialReference?.value, friend)
        XCTAssertEqual(conversation.friendDisplayName, "Latisha")
        XCTAssertEqual(conversation.friendAvatarReference, "avatar_latisha")
        XCTAssertEqual(conversation.latestPreview, "Hi")
        XCTAssertEqual(conversation.latestPreviewSenderRole, "self")
        XCTAssertEqual(StyleFriendsDMPresentationMapper.conversation(conversation).lastMessagePreview, "You: Hi")
        XCTAssertEqual(StyleFriendsDMPresentationMapper.conversation(conversation).friendSocialReference?.value, friend)
        XCTAssertEqual(StyleFriendsDMPresentationMapper.conversation(conversation).friendDisplayName, "Latisha")
    }

    func testDirectMessageUIUsesHumanOnlyPresentationSeamsAndAccessibleActions() throws {
        let uiSource = try source("StyleMatchAI/StyleFriendsChatUI.swift")
        let friendsShell = try source("StyleMatchAI/StyleFriendsView.swift")
        XCTAssertTrue(uiSource.contains("struct StyleFriendsConversationsView"))
        XCTAssertTrue(uiSource.contains("struct StyleFriendsConversationRow"))
        XCTAssertTrue(uiSource.contains("struct FriendChatView"))
        XCTAssertTrue(uiSource.contains("struct FriendMessageBubble"))
        XCTAssertTrue(uiSource.contains("struct FriendReactionPicker"))
        XCTAssertTrue(uiSource.contains("struct FriendReactionSummary"))
        XCTAssertTrue(uiSource.contains("struct FriendReplyPreview"))
        XCTAssertTrue(uiSource.contains("struct FriendChatComposer"))
        XCTAssertTrue(uiSource.contains("struct SharedOutfitMessageCard"))
        XCTAssertTrue(uiSource.contains("FriendReplyPreview(preview:"))
        XCTAssertTrue(uiSource.contains("Not sent"))
        XCTAssertTrue(uiSource.contains("FriendChatTermsSheet"))
        XCTAssertTrue(uiSource.contains("Accept Community Terms"))
        XCTAssertTrue(uiSource.contains("requestFirstSendAuthorization"))
        XCTAssertTrue(uiSource.contains("Accepting does not send a message"))
        XCTAssertTrue(friendsShell.contains("case .directMessage, .directMessageReply, .directMessageReaction"))
        XCTAssertTrue(uiSource.contains("Where did you get this?"))
        XCTAssertTrue(uiSource.contains("accessibilityAction(named: \"React\""))
        XCTAssertTrue(uiSource.contains("accessibilityReduceMotion"))
        XCTAssertFalse(uiSource.contains("StylistChatView"))
        XCTAssertFalse(uiSource.contains("CKContainer"))
        XCTAssertFalse(uiSource.contains("CloudSync"))
        XCTAssertFalse(uiSource.contains("AIPersistentMemoryStore"))
        XCTAssertTrue(friendsShell.contains("Button(\"Conversations\")"))
        XCTAssertTrue(friendsShell.contains("StyleFriendsLiveConversationsHost {"))
        let dmSource = try source("StyleMatchAI/StyleFriendsDirectMessages.swift")
        XCTAssertTrue(dmSource.contains("StyleFriendsHTTPDirectMessageService"))
        XCTAssertTrue(uiSource.contains("loadConversations()"))
        XCTAssertTrue(uiSource.contains("StyleFriendsAccountRecoveryView"))
        XCTAssertTrue(uiSource.contains("StyleMatchSessionRecoveryCopy.title"))
        XCTAssertTrue(uiSource.contains("StyleMatchSessionRecoveryCopy.actionTitle"))
        XCTAssertFalse(uiSource.contains("Reconnect KigoStylist in Profile"))
        XCTAssertFalse(uiSource.contains("SignInWithAppleButton"))
        XCTAssertTrue(uiSource.contains("StyleFriendsLiveConversationsHost"))
        XCTAssertTrue(uiSource.contains("loadMessages(conversation:"))
        XCTAssertTrue(uiSource.contains("refreshedConversation"))
        XCTAssertTrue(uiSource.contains("markRead("))
        XCTAssertTrue(uiSource.contains("onOperationCompleted"))
        XCTAssertTrue(uiSource.contains("StyleFriendsConversationEmptyStateView"))
        XCTAssertTrue(friendsShell.contains("refreshRelationshipPublicProfiles"))
        XCTAssertTrue(uiSource.contains("Start a conversation with a Style Friend"))
        XCTAssertTrue(uiSource.contains("Find Style Friends"))
        XCTAssertTrue(uiSource.contains("Your conversations are private"))
        XCTAssertTrue(uiSource.contains("case .loading"))
        XCTAssertTrue(uiSource.contains("case .recoverableError"))
    }

    func testPremiumChatRefinementCoversGroupingComposerAndTruthfulFailure() throws {
        let ui = try source("StyleMatchAI/StyleFriendsChatUI.swift")
        XCTAssertTrue(ui.contains("groupsWithPrevious"))
        XCTAssertTrue(ui.contains("messageIsEmojiOnly"))
        XCTAssertTrue(ui.contains(".lineLimit(1...4)"))
        XCTAssertTrue(ui.contains(".safeAreaInset(edge: .bottom"))
        XCTAssertTrue(ui.contains("Replying to \\(target.senderDisplayName)"))
        XCTAssertTrue(ui.contains("Cancel reply"))
        XCTAssertTrue(ui.contains("Not sent"))
        XCTAssertTrue(ui.contains("Retry"))
        XCTAssertTrue(ui.contains("Discard"))
        XCTAssertTrue(ui.contains("@State private var isSending = false"))
        XCTAssertTrue(ui.contains("guard !isSending, failedSend == nil, !recoveryPending else { return }"))
        XCTAssertTrue(ui.contains("Text(isSending ? \"Sending…\" : \"Send\")"))
        XCTAssertFalse(ui.contains("Delivered"))
        XCTAssertFalse(ui.contains("Text(\"Read\")"))
        XCTAssertFalse(ui.contains("Text(\"Seen\")"))
    }

    func testDirectMessageComposerKeepsAnUnsentDraftVisibleAndFocusable() throws {
        let source = try source("StyleMatchAI/StyleFriendsChatUI.swift")
        XCTAssertTrue(source.contains("@FocusState private var composerFocused"))
        XCTAssertTrue(source.contains(".focused($isFocused)"))
        XCTAssertTrue(source.contains(".submitLabel(.send)"))
        XCTAssertTrue(source.contains("hasFailedSend"))
        XCTAssertTrue(source.contains("Retry or discard the unsent message before sending another."))
        XCTAssertTrue(source.contains("Send a message to start this conversation."))
        XCTAssertTrue(source.contains("FriendFailedSendBubble("))

        let failureRange = try XCTUnwrap(source.range(of: "private func requestFirstSendAuthorization"))
        let nextMethodRange = try XCTUnwrap(source.range(of: "private func loadAttachmentPhoto"))
        let failurePath = String(source[failureRange.lowerBound..<nextMethodRange.lowerBound])
        XCTAssertTrue(failurePath.contains("failedSend = .init(draft: pending, error: error, phase: .send"))
        XCTAssertFalse(failurePath.contains("draft = \"\""))
        XCTAssertFalse(failurePath.contains("pendingAttachmentPhoto = nil"))
        XCTAssertTrue(source.contains("private func clearComposerAfterConfirmedHandoff()"))
        let confirmationRange = try XCTUnwrap(source.range(of: "private func clearComposerAfterConfirmedHandoff()"))
        let confirmationPath = String(source[confirmationRange.lowerBound...])
        XCTAssertTrue(confirmationPath.contains("draft = \"\""))
        XCTAssertTrue(confirmationPath.contains("pendingAttachmentPhoto = nil"))
        XCTAssertTrue(confirmationPath.contains("replyTarget = nil"))
    }

    func testConfirmedHandoffClearsOnlyTheStaleStopWaitingBanner() throws {
        let source = try source("StyleMatchAI/StyleFriendsChatUI.swift")
        let start = try XCTUnwrap(source.range(of: "private func clearComposerAfterConfirmedHandoff()"))
        let tail = String(source[start.lowerBound...])
        let end = tail.firstIndex(of: "}") ?? tail.endIndex
        let body = String(tail[..<end])
        XCTAssertTrue(body.contains("stoppedWaiting = false"))
        XCTAssertTrue(source.contains("if stoppedWaiting && !recoveryPending"))
        XCTAssertTrue(source.contains("archiveUnknownAttachment"))
    }

    func testPremiumChatRefinementKeepsReactionAndAccessibilityBoundaries() throws {
        let ui = try source("StyleMatchAI/StyleFriendsChatUI.swift")
        XCTAssertTrue(ui.contains("ViewThatFits(in: .horizontal)"))
        XCTAssertTrue(ui.contains("Swipe to see all seven reactions."))
        XCTAssertTrue(ui.contains("Fashion expression shortcuts"))
        XCTAssertTrue(ui.contains("accessibilityReduceMotion"))
        XCTAssertTrue(ui.contains("Conversation options"))
        XCTAssertTrue(ui.contains("Where’d you get this?"))
        XCTAssertFalse(ui.contains("StylistChatView"))
        XCTAssertFalse(ui.contains("CKContainer"))
        XCTAssertFalse(ui.contains("CloudSync"))
    }

    func testFashionReactionCatalogAndLegacyDislikeCompatibility() throws {
        XCTAssertEqual(StyleFriendReactionKind.allCases, [.like, .love, .fire, .perfect, .stylish, .wantIt, .notForMe])
        XCTAssertEqual(try JSONDecoder().decode(StyleFriendReactionKind.self, from: Data("\"dislike\"".utf8)), .notForMe)
        XCTAssertEqual(try JSONDecoder().decode(StyleFriendReactionKind.self, from: Data("\"want_it\"".utf8)), .wantIt)
        XCTAssertEqual(StyleFriendReactionKind.notForMe.displayName, "Not For Me")
    }

    func testTypedPostCommentReactionRoutesAndReplyPreviewStayBounded() throws {
        let post = try XCTUnwrap(StyleFriendsOpaqueRouteReference("post_123"))
        let comment = try XCTUnwrap(StyleFriendsOpaqueRouteReference("comment_123"))
        XCTAssertEqual(StyleFriendsRoutePath.reaction(.post(post)), "/v1/friends/posts/post_123/reaction")
        XCTAssertEqual(StyleFriendsRoutePath.reaction(.comment(comment)), "/v1/friends/comments/comment_123/reaction")
        XCTAssertEqual(StyleFriendsReplyPreview(parentCommentReference: comment, senderDisplayName: "Ava", text: "Great look", parentAvailable: true).presentationText, "Ava: Great look")
        XCTAssertEqual(StyleFriendsReplyPreview(parentCommentReference: comment, senderDisplayName: "Ava", text: "Private", parentAvailable: false).presentationText, "Original message unavailable")
        XCTAssertFalse(StyleFriendsConversationCapability.typingIndicatorAvailable)
        XCTAssertFalse(StyleFriendsConversationCapability.readReceiptAvailable)
    }

    func testFashionReactionProjectionAndWantItIsolation() {
        let empty = StyleFriendReactionSummary(counts: [.like: 2], viewerReaction: nil)
        for reaction in StyleFriendReactionKind.allCases {
            let selected = StyleFriendsReactionProjection.applying(reaction, to: empty)
            XCTAssertEqual(selected.viewerReaction, reaction)
            XCTAssertEqual(selected.count(for: reaction), empty.count(for: reaction) + 1)
            XCTAssertEqual(StyleFriendsReactionProjection.applying(nil, to: selected), empty)
        }
        XCTAssertTrue(StyleFriendsReactionPolicy.wantItDoesNotCreateShoppingHistory)
    }
    func testCommentReactionProjectionAddsRemovesAndSwitchesOneViewerReaction() {
        let empty = StyleFriendReactionSummary(counts: [.like: 4, .love: 2, .notForMe: 1], viewerReaction: nil)
        let liked = StyleFriendsReactionProjection.applying(.like, to: empty)
        XCTAssertEqual(liked.count(for: .like), 5)
        XCTAssertEqual(liked.viewerReaction, .like)
        XCTAssertEqual(StyleFriendsReactionProjection.applying(nil, to: liked), empty)
        let loved = StyleFriendsReactionProjection.applying(.love, to: liked)
        XCTAssertEqual(loved.count(for: .like), 4)
        XCTAssertEqual(loved.count(for: .love), 3)
        XCTAssertEqual(loved.viewerReaction, .love)
        let disliked = StyleFriendsReactionProjection.applying(.notForMe, to: liked)
        XCTAssertEqual(disliked.count(for: .notForMe), 2)
        XCTAssertEqual(disliked.viewerReaction, .notForMe)
        XCTAssertEqual(StyleFriendsReactionProjection.applying(.love, to: disliked).viewerReaction, .love)
        XCTAssertEqual(StyleFriendsReactionPolicy.maximumActiveReactionsPerViewerAndMessage, 1)
    }

    func testReactionContractUsesOpaqueCommentRouteAndServerAuthorityOnly() throws {
        let reference = try XCTUnwrap(StyleFriendsOpaqueRouteReference("comment_123"))
        XCTAssertEqual(StyleFriendsRoutePath.commentReaction(reference), "/v1/friends/comments/comment_123/reaction")
        XCTAssertTrue(StyleFriendsReactionPolicy.serverAuthoritative)
        XCTAssertTrue(StyleFriendsReactionPolicy.privateCloudKitStorageForbidden)
        XCTAssertTrue(StyleFriendsReactionPolicy.requiresAuthenticatedAuthorizedVisibleContent)
        XCTAssertNil(StyleFriendsOpaqueRouteReference("../comment"))
        XCTAssertNil(StyleFriendsOpaqueRouteReference("comment?x=1"))
    }

    func testReactionAccessibilityAndOptimisticRollbackSourceContract() throws {
        let view = try source("StyleMatchAI/StyleFriendsView.swift")
        let foundation = try source("StyleMatchAI/StyleFriendsFoundation.swift")
        XCTAssertTrue(view.contains("StyleFriendReactionPicker"))
        XCTAssertTrue(view.contains("StyleFriendReactionSummaryView"))
        XCTAssertTrue(view.contains("Touch and hold to choose a reaction"))
        XCTAssertTrue(view.contains("comments[index] = comment"))
        XCTAssertTrue(foundation.contains("func setReaction(target: StyleFriendReactionTarget"))
        XCTAssertTrue(foundation.contains("privateCloudKitStorageForbidden = true"))
        XCTAssertTrue(foundation.contains("StyleFriendsSetReactionRequest"))
    }
    func testRelationshipStatesAreExplicitAndServerContractSafe() {
        XCTAssertEqual(Set(StyleFriendRelationshipState.allCases.map(\.rawValue)),
                       ["none", "outgoingRequest", "incomingRequest", "friends", "blocked"])
    }

    func testOpaqueSocialReferenceIsValidatedAndNeverAnAccountIdentity() {
        let value = "sf_" + String(repeating: "a", count: 43)
        XCTAssertNotNil(StyleFriendAccountReference(value))
        XCTAssertNil(StyleFriendAccountReference("account_key"))
        XCTAssertNil(StyleFriendAccountReference("sf_short"))
    }

    func testPostAndCommentRouteReferencesRejectInjectionAndPreserveSafeRoutes() {
        let post = StyleFriendsOpaqueRouteReference("post_01-ABcd")
        let comment = StyleFriendsOpaqueRouteReference("comment_01-ABcd")
        XCTAssertNotNil(post)
        XCTAssertNotNil(comment)
        XCTAssertEqual(StyleFriendsRoutePath.post(post!, action: "like"), "/v1/friends/posts/post_01-ABcd/like")
        XCTAssertEqual(StyleFriendsRoutePath.post(post!, action: "comments"), "/v1/friends/posts/post_01-ABcd/comments")
        XCTAssertEqual(StyleFriendsRoutePath.post(post!, action: "report"), "/v1/friends/posts/post_01-ABcd/report")
        XCTAssertEqual(StyleFriendsRoutePath.comment(comment!), "/v1/friends/comments/comment_01-ABcd")

        ["", "   ", "post/ref", "..", "post/../like", "post?like=1", "post#fragment", "%2e%2e", "%2F", "post\nref", "post\u{0000}ref"].forEach {
            XCTAssertNil(StyleFriendsOpaqueRouteReference($0), "Expected malformed reference to be rejected: \($0.debugDescription)")
        }
    }

    func testFriendshipNeverGrantsPrivateDataAccess() {
        XCTAssertTrue(StyleFriendsFoundationPolicy.sharesAreObjectLevelAndExplicit)
        XCTAssertTrue(StyleFriendsFoundationPolicy.privateScanOrCloudKitAccessIsNeverGrantedByFriendship)
    }

    func testSocialProfileBoundsAreExplicitAndSeparateFromPrivateProfile() {
        XCTAssertEqual(StyleFriendProfileUpdate.maximumDisplayNameUTF16, 80)
        XCTAssertEqual(StyleFriendProfileUpdate.maximumStyleBioWords, 2_000)
        XCTAssertEqual(StyleFriendProfileUpdate.maximumStyleBioUTF16, 24_000)
        XCTAssertEqual(StyleFriendProfileUpdate.maximumStyleCategories, 8)
        XCTAssertEqual(StyleFriendProfileVisibility.friendsOnly.rawValue, "friendsOnly")
    }

    func testSocialProfileBioBoundaryUsesUTF16AndRetainsMeaningfulLineBreaks() {
        let accepted = Array(repeating: "style", count: 2_000).joined(separator: " ")
        let rejected = Array(repeating: "style", count: 2_001).joined(separator: " ")
        XCTAssertEqual(accepted.split(whereSeparator: { $0.isWhitespace }).count, StyleFriendProfileUpdate.maximumStyleBioWords)
        XCTAssertGreaterThan(rejected.split(whereSeparator: { $0.isWhitespace }).count, StyleFriendProfileUpdate.maximumStyleBioWords)
        XCTAssertEqual(String(repeating: "x", count: 24_000).utf16.count, StyleFriendProfileUpdate.maximumStyleBioUTF16)
        XCTAssertEqual("Modern tailoring\nwith vintage details".trimmingCharacters(in: .whitespacesAndNewlines), "Modern tailoring\nwith vintage details")
    }

    func testSocialProfileUpdateUsesAuthoritativeWorkerWireKeys() throws {
        let update = StyleFriendProfileUpdate(
            displayName: "Taylor",
            avatarReference: nil,
            styleBio: "Minimal tailoring and vintage denim.",
            styleCategories: [.minimal, .vintage],
            isDiscoverable: true
        )
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(update)) as? [String: Any])
        XCTAssertEqual(object["display_name"] as? String, "Taylor")
        XCTAssertEqual(object["style_bio"] as? String, "Minimal tailoring and vintage denim.")
        XCTAssertEqual(object["style_categories"] as? [String], ["minimal", "vintage"])
        XCTAssertNil(object["displayName"])
        XCTAssertNil(object["styleBio"])
        XCTAssertNil(object["styleCategories"])
        XCTAssertEqual(object["is_discoverable"] as? Bool, true)
    }

    func testSocialProfileEditorUsesAuthoritativeSaveAndPublicOnlyPresentation() throws {
        let viewSource = try source("StyleMatchAI/StyleFriendsView.swift")
        XCTAssertTrue(viewSource.contains("let refreshed = SocialProfileDraft(profile: profile)"))
        XCTAssertTrue(viewSource.contains("savedSocialProfileDraft = refreshed"))
        XCTAssertTrue(viewSource.contains("profileSaveState = .saving"))
        XCTAssertTrue(viewSource.contains("Button(\"Retry Save\")"))
        XCTAssertTrue(viewSource.contains("ToolbarItemGroup(placement: .keyboard)"))
        XCTAssertTrue(viewSource.contains("Public preview"))
        XCTAssertTrue(viewSource.contains("toggleStyleCategory(category)"))
        XCTAssertTrue(viewSource.contains("accessibilityValue(socialProfileDraft.categories.contains(category) ? \"Selected\" : \"Not selected\")"))
        XCTAssertTrue(viewSource.contains("Your Closet, scans, AI Memory, sizes, location, and account details stay private."))
        XCTAssertTrue(viewSource.contains("Choose a photo to submit for your public profile."))
        XCTAssertTrue(viewSource.contains("scrollDismissesKeyboard(.interactively)"))
        XCTAssertFalse(viewSource.contains("TextField(\"Avatar reference (optional)\""))
        let foundation = try source("StyleMatchAI/StyleFriendsFoundation.swift")
        XCTAssertTrue(foundation.contains("case signInRequired, invalidProfile"))
        XCTAssertTrue(foundation.contains("path == \"/v1/friends/profile/me\""))
    }

    func testStyleFriendsProfileAndNotificationCompactPresentationGuards() throws {
        let profile = try source("StyleMatchAI/StyleFriendsView.swift")
        let foundation = try source("StyleMatchAI/StyleFriendsFoundation.swift")
        let notifications = try source("StyleMatchAI/StyleFriendsNotifications.swift")
        let chat = try source("StyleMatchAI/StyleFriendsChatUI.swift")

        XCTAssertTrue(foundation.contains("static let maximumStyleBioWords = 2_000"))
        XCTAssertTrue(foundation.contains("static let maximumStyleBioUTF16 = 24_000"))
        XCTAssertTrue(profile.contains("Submitting your photo for safety review…"))
        XCTAssertTrue(profile.contains("StyleFriendsAvatarRuntimeAuthority.allowsAvatarUpload"))
        XCTAssertTrue(profile.contains("Profile photos are unavailable right now."))
        XCTAssertTrue(profile.contains("avatarState != .failed && avatarState != .rejected"))
        XCTAssertTrue(profile.contains("Style Friends notifications"))
        XCTAssertFalse(profile.contains("Label(\"Manage Style Friends notifications\""))
        XCTAssertTrue(notifications.contains("StyleFriendsNewPostModePicker"))
        XCTAssertTrue(notifications.contains("applyServerPreferences"))
        XCTAssertTrue(notifications.contains("selectNewPostsMode"))
        XCTAssertFalse(notifications.contains("Picker(\"New Friend Posts\""))
        XCTAssertTrue(chat.contains("case .empty:\n                ScrollView"))
        XCTAssertFalse(chat.contains("minHeight: 230"))
        XCTAssertTrue(profile.contains("StyleFriendExpandableBio"))
        XCTAssertTrue(profile.contains("Read full bio"))
        XCTAssertTrue(profile.contains("styleBio: normalizedBio.isEmpty ? nil : normalizedBio"))
        XCTAssertTrue(profile.contains("TextField(\"Public style bio (optional)\", text: $socialProfileDraft.styleBio, axis: .vertical)"))
        XCTAssertTrue(profile.contains("lineLimit(4...10)"))
        XCTAssertTrue(profile.contains(".lineLimit(2)"))
    }

    func testFriendJourneyDiscoveryAndMessagingStaySocialOnlyAndSessionBound() throws {
        let foundation = try source("StyleMatchAI/StyleFriendsFoundation.swift")
        let view = try source("StyleMatchAI/StyleFriendsView.swift")
        XCTAssertTrue(foundation.contains("func discoverStyleFriends(query: String)"))
        XCTAssertTrue(foundation.contains("/v1/friends/discovery?q="))
        XCTAssertTrue(view.contains("Let other Style Friends find this public profile"))
        XCTAssertTrue(view.contains("Button(\"Find Style Friends\")"))
        XCTAssertTrue(view.contains("Add Friend"))
        XCTAssertTrue(view.contains("Text(\"Request Sent\")"))
        XCTAssertTrue(view.contains("relationshipActionButton(title: \"Accept\""))
        XCTAssertTrue(view.contains("relationshipActionButton(title: \"Decline\""))
        XCTAssertTrue(view.contains("relationshipActionButton(title: \"Cancel\""))
        XCTAssertTrue(view.contains("operation: .send"))
        XCTAssertTrue(view.contains("Button(\"Message\")"))
        XCTAssertTrue(view.contains("createConversation(friend: friend)"))
        XCTAssertTrue(view.contains("discoveryRelationshipState(for: person)"))
        XCTAssertTrue(view.contains("Unavailable while blocked"))
        XCTAssertTrue(view.contains("Contacts, email, private Profile, Closet, scans, AI Memory, and location are never searched."))
        XCTAssertFalse(view.contains("ProfileStore("))
        XCTAssertFalse(view.contains("AIPersistentMemoryStore"))
        XCTAssertFalse(view.contains("CloudSync"))
    }

    func testFriendsOnlyPostContractHasNoPrivateSourceAuthority() {
        XCTAssertEqual(SharedOutfitPostDraft.maximumTitleUTF16, 120)
        XCTAssertEqual(SharedOutfitPostDraft.maximumCaptionUTF16, 500)
        XCTAssertTrue(SharedOutfitPostPrivacyContract.usesBoundedSharedCardRepresentation)
        XCTAssertTrue(SharedOutfitPostPrivacyContract.rawShareTokenIsNeverPersistedInSocialPost)
        XCTAssertTrue(SharedOutfitPostPrivacyContract.privateSourceScanIsNeverSerialized)
    }

    func testFeedStateIsBoundedToSocialProjection() {
        XCTAssertEqual(StyleFriendsFeedState.empty, .empty)
        XCTAssertEqual(StyleFriendsFeedState.unavailable, .unavailable)
        XCTAssertEqual(StyleFriendsFeedState.serverUnavailable, .serverUnavailable)
    }

    func testFeedRuntimeIsExplicitOwnerBetaStagingOnlyAndUsesTheExistingTypedService() throws {
        let view = try source("StyleMatchAI/StyleFriendsView.swift")
        let debug = try source("Config/StyleMatchDebug.xcconfig")
        let ownerBeta = try source("Config/StyleMatchOwnerBeta.xcconfig")
        let release = try source("Config/StyleMatchRelease.xcconfig")
        XCTAssertTrue(view.contains("StyleFriendsFeedRuntimeAuthority.current == .stagingAuthorized"))
        XCTAssertTrue(view.contains("StyleFriendsDMStagingTransportConfiguration(baseURL:"))
        XCTAssertTrue(view.contains("service.feed()"))
        XCTAssertTrue(view.contains("service.feed(cursor: cursor)"))
        XCTAssertTrue(view.contains("StyleFriendsFeedImage(reference: item.socialImageReference, service: service)"))
        XCTAssertTrue(view.contains("Shared look image is no longer available"))
        XCTAssertFalse(view.contains("Friends Feed is not available yet"))
        XCTAssertTrue(view.contains("No posts yet"))
        XCTAssertTrue(view.contains("Button(\"Retry\")"))
        XCTAssertTrue(view.contains("networkUnavailable"))
        XCTAssertTrue(view.contains("serverUnavailable"))
        XCTAssertTrue(debug.contains("STYLEMATCH_STYLE_FRIENDS_FEED_RUNTIME_AUTHORITY = disabled"))
        XCTAssertTrue(ownerBeta.contains("STYLEMATCH_STYLE_FRIENDS_FEED_RUNTIME_AUTHORITY = stagingAuthorized"))
        XCTAssertTrue(release.contains("STYLEMATCH_STYLE_FRIENDS_FEED_RUNTIME_AUTHORITY = disabled"))
    }

    func testFeedDecodesOnlyOpaqueAuthorizedSocialImageReferences() throws {
        let foundation = try source("StyleMatchAI/StyleFriendsFoundation.swift")
        let view = try source("StyleMatchAI/StyleFriendsView.swift")
        XCTAssertTrue(foundation.contains("socialImageReference = \"social_image_ref\""))
        XCTAssertTrue(foundation.contains("ownerSocialReference = \"owner_social_reference\""))
        XCTAssertTrue(foundation.contains("Worker rechecks friendship, blocking, revocation, and moderation"))
        XCTAssertTrue(view.contains("It never substitutes a local scan, Closet image, or"))
        XCTAssertTrue(view.contains("service.socialImageReceipt(opaqueReference)"))
        XCTAssertTrue(view.contains("item.ownerSocialReference"))
        XCTAssertTrue(view.contains("No private image is substituted."))
    }

    func testPresentationShellHasAllRequiredSocialSectionsAndNoPrivateProjection() {
        XCTAssertEqual(StyleFriendsPresentationContract.rootSections, [
            "Friends Feed", "Friends", "Friend Requests", "My Shared Looks", "My Style Friends Profile"
        ])
        XCTAssertFalse(StyleFriendsPresentationContract.rootSections.contains("Closet"))
        XCTAssertFalse(StyleFriendsPresentationContract.rootSections.contains("AI Memory"))
        XCTAssertFalse(StyleFriendsPresentationContract.rootSections.contains("Private Profile"))
    }

    func testFriendRequestAndFeedActionLabelsRemainTruthful() {
        XCTAssertEqual(StyleFriendsPresentationContract.incomingRequestActions, ["Accept", "Decline"])
        XCTAssertEqual(StyleFriendsPresentationContract.outgoingRequestActions, ["Pending", "Cancel"])
        XCTAssertEqual(StyleFriendsPresentationContract.friendActions, ["Remove", "Block", "Unblock"])
        XCTAssertEqual(StyleFriendsPresentationContract.sharedLookActions, ["Open Shared Look", "View Friend Profile"])
    }

    func testFriendsPostDeletionAndShareRevocationAreExplicitlyDistinct() {
        XCTAssertNotEqual(
            StyleFriendsPresentationContract.friendsPostDeletionCopy,
            StyleFriendsPresentationContract.shareRevocationCopy
        )
        XCTAssertTrue(StyleFriendsPresentationContract.shareRevocationCopy.contains("stops access"))
        XCTAssertTrue(StyleFriendsPresentationContract.friendsPostDeletionCopy.contains("engagement"))
    }

    func testPhaseEEngagementContractsRemainBoundedAndSeparateFromScores() {
        XCTAssertEqual(StyleFriendsEngagementPolicy.maximumCommentUTF16, 500)
        XCTAssertEqual(StyleFriendsReportDraft.maximumDetailUTF16, 500)
        XCTAssertEqual(StyleFriendsEngagementPolicy.commentPageDefault, 20)
        XCTAssertEqual(StyleFriendsEngagementPolicy.commentPageMaximum, 50)
        XCTAssertTrue(StyleFriendsEngagementPolicy.scoreIsNeverModifiedBySocialEngagement)
        XCTAssertTrue(StyleFriendsEngagementPolicy.rawAccountIdentifiersAreNeverPresented)
        XCTAssertTrue(StyleFriendsEngagementPolicy.socialTextIsUntrustedPlainText)
        XCTAssertEqual(Set(StyleFriendsReportCategory.allCases.map(\.rawValue)), ["harassment", "spam", "sexual_inappropriate", "hate_abuse", "impersonation", "unsafe_content", "other"])
    }

    func testPhaseEUIUsesTheExistingAuthenticatedServiceAndHasNoDecorativeEngagementControls() throws {
        let foundation = try source("StyleMatchAI/StyleFriendsFoundation.swift")
        let view = try source("StyleMatchAI/StyleFriendsView.swift")

        XCTAssertTrue(foundation.contains("func like(postReference: StyleFriendsOpaqueRouteReference)"))
        XCTAssertTrue(foundation.contains("func unlike(postReference: StyleFriendsOpaqueRouteReference)"))
        XCTAssertTrue(foundation.contains("func addComment(postReference: StyleFriendsOpaqueRouteReference"))
        XCTAssertTrue(foundation.contains("func deleteOwnComment(commentReference: StyleFriendsOpaqueRouteReference)"))
        XCTAssertTrue(foundation.contains("func reportPost(postReference: StyleFriendsOpaqueRouteReference"))
        XCTAssertTrue(foundation.contains("let isOwner: Bool"))
        XCTAssertTrue(view.contains("Button(engagement.viewerHasLiked ? \"Unlike\" : \"Like\")"))
        XCTAssertTrue(view.contains("StyleFriendsFeedCard(item: item, service: service)"))
        XCTAssertFalse(view.contains("private let service = StyleFriendsService()"))
        XCTAssertTrue(view.contains("Button(\"Comments\")"))
        XCTAssertTrue(view.contains("Button(\"Report Post\")"))
        XCTAssertTrue(view.contains("Button(\"Block Friend\", role: .destructive)"))
        XCTAssertTrue(view.contains("if comment.isOwner"))
        XCTAssertFalse(view.contains("Button(\"Open Shared Look\") { }"))
    }

    func testFeedCommentSafetyStatesRemainTruthfulAndDoNotInflateVisibleCounts() throws {
        let foundation = try source("StyleMatchAI/StyleFriendsFoundation.swift")
        let view = try source("StyleMatchAI/StyleFriendsView.swift")

        XCTAssertTrue(foundation.contains("enum StyleFriendsCommentDeliveryStatus"))
        XCTAssertTrue(foundation.contains("case underReview"))
        XCTAssertTrue(foundation.contains("case rejected"))
        XCTAssertTrue(foundation.contains("acceptedStatusCodes: [201, 202, 422]"))
        XCTAssertTrue(view.contains("Your comment is under review and is not visible to friends."))
        XCTAssertTrue(view.contains("could not be posted under the Style Friends safety rules"))
        XCTAssertTrue(view.contains("if let comment = submission.comment"))
        XCTAssertTrue(view.contains("commentCount: engagement.commentCount + 1"))
        XCTAssertTrue(view.contains("@FocusState private var isCommentComposerFocused: Bool"))
        XCTAssertTrue(view.contains("ToolbarItemGroup(placement: .keyboard)"))
        XCTAssertTrue(view.contains("Posting Comment…"))
    }

    func testPurchaseQuestionUsesTheExistingPostBoundCommentAuthority() throws {
        let view = try source("StyleMatchAI/StyleFriendsView.swift")
        XCTAssertTrue(view.contains("Button(\"Ask where this is from\")"))
        XCTAssertTrue(view.contains("Opens comments for this shared look"))
        XCTAssertTrue(view.contains("Write a comment or purchase question"))
        XCTAssertTrue(view.contains("KigoStylist never infers a retailer, product source, or ownership."))
        XCTAssertTrue(view.contains("StyleFriendsCommentsSheet(postReference: item.postReference"))
    }

    func testProfileRoutesToTheDedicatedFriendsShellWithoutAddingATab() throws {
        let profileSource = try source("StyleMatchAI/ProfileView.swift")
        let contentSource = try source("StyleMatchAI/ContentView.swift")

        XCTAssertTrue(profileSource.contains("isShowingStyleFriends"))
        XCTAssertTrue(profileSource.contains("StyleFriendsView("))
        XCTAssertTrue(profileSource.contains("homeSearchRoute: styleFriendsHomeSearchRoute"))
        XCTAssertTrue(profileSource.contains("onCreateShareCard:"))
        XCTAssertTrue(profileSource.contains("Label(\"Style Friends\", systemImage: \"person.2.fill\")"))
        XCTAssertFalse(contentSource.contains("case styleFriends"))
    }

    func testFriendsShellUsesOnlySocialContractsAndUsesSingleAuthenticatedService() throws {
        let source = try source("StyleMatchAI/StyleFriendsView.swift")

        XCTAssertTrue(source.contains("StyleFriendsFeedState"))
        XCTAssertTrue(source.contains("Button(\"Comments\")"))
        XCTAssertFalse(source.contains("Button(\"Open Shared Look\") { }"))
        XCTAssertTrue(source.contains("View Friend Profile"))
        XCTAssertTrue(source.contains("service.listFriends()"))
        XCTAssertTrue(source.contains("service.listIncomingRequests()"))
        XCTAssertTrue(source.contains("service.listOutgoingRequests()"))
        XCTAssertTrue(source.contains("service.listMySharedLooks()"))
        XCTAssertTrue(source.contains("service.relationship(target: person.socialReference"))
        XCTAssertTrue(source.contains("@State private var relationshipActions: [StyleFriendAccountReference: StyleFriendRelationshipActionState]"))
        XCTAssertTrue(source.contains("guard relationshipActions[target] == nil"))
        XCTAssertTrue(source.contains("state?.visibleLabel ?? title"))
        XCTAssertTrue(source.contains("StyleFriendProfileSheet"))
        XCTAssertTrue(source.contains("service.socialProfile(for: row.socialReference)"))
        XCTAssertTrue(source.contains("openConversation: { await startConversation(with: person.socialReference) }"))
        XCTAssertTrue(source.contains("Button(\"Message\")"))
        XCTAssertTrue(source.contains("Opens the existing private conversation"))
        XCTAssertTrue(source.contains("Review Shared Look"))
        XCTAssertTrue(source.contains("Audience: Friends"))
        XCTAssertTrue(source.contains("Delete Post"))
        XCTAssertTrue(source.contains("Revoke Share is available on the approved shared card"))
        XCTAssertTrue(source.contains("StyleMatchAccountSessionStore.didChangeNotification"))
        XCTAssertTrue(source.contains("clearAccountScopedState()"))
        XCTAssertFalse(source.contains("ProfileStore("))
        XCTAssertFalse(source.contains("AIPersistentMemoryStore"))
        XCTAssertFalse(source.contains("ClosetPersistenceAuthority"))
        XCTAssertFalse(source.contains("CKContainer"))
        XCTAssertFalse(source.contains("CloudSync"))
    }

    func testListContractsUseOpaqueReferencesAndBoundedPages() {
        XCTAssertNotNil(StyleFriendAccountReference("sf_" + String(repeating: "a", count: 43)))
        XCTAssertEqual(StyleFriendRelationshipOperation.accept.rawValue, "accept")
        XCTAssertEqual(StyleFriendRelationshipOperation.block.rawValue, "block")
        XCTAssertEqual(SharedOutfitPost.Availability.active.rawValue, "active")
    }

    func testExistingExternalShareLinkAndFriendsBoundaryRemainSeparate() throws {
        let shareSource = try source("StyleMatchAI/ShareableScoreCardViews.swift")
        XCTAssertTrue(shareSource.contains("Copy Link"))
        XCTAssertTrue(shareSource.contains("Share with Friends"))
        XCTAssertTrue(shareSource.contains("reviewCard = card"))
        XCTAssertTrue(shareSource.contains("StyleFriendsPublishReview"))
        XCTAssertTrue(shareSource.contains("This stops access to this shared outfit. Your original photo, score, and saved KigoStylist data remain in your account."))
    }

    func testFriendProfileTransportUsesOnlyAnOpaqueReference() throws {
        let source = try source("StyleMatchAI/StyleFriendsFoundation.swift")
        XCTAssertTrue(source.contains("socialProfile(for friend: StyleFriendAccountReference)"))
        XCTAssertTrue(source.contains("/v1/friends/profile/\\(friend.value)"))
        XCTAssertFalse(source.contains("account_key"))
    }

    func testFeedOwnerReferenceIsOptionalForCompatibilityAndNeverUsesDisplayNameAsIdentity() throws {
        let foundation = try source("StyleMatchAI/StyleFriendsFoundation.swift")
        let view = try source("StyleMatchAI/StyleFriendsView.swift")
        XCTAssertTrue(foundation.contains("ownerSocialReference = \"owner_social_reference\""))
        XCTAssertTrue(foundation.contains("let ownerSocialReference: StyleFriendAccountReference?"))
        XCTAssertTrue(view.contains("if let reference = item.ownerSocialReference"))
        XCTAssertTrue(view.contains("selectedFriend = StyleFriendListItem("))
        XCTAssertFalse(view.contains("StyleFriendAccountReference(item.owner.displayName"))
    }

    func testApprovedCardScoreSnapshotIsDisplayedOnlyWhenPresent() throws {
        let card = try source("StyleMatchAI/ShareableScoreCard.swift")
        let scan = try source("StyleMatchAI/ScanView.swift")
        let view = try source("StyleMatchAI/StyleFriendsView.swift")
        XCTAssertTrue(card.contains("let overallScore: Int?"))
        XCTAssertTrue(scan.contains("overallScore: payload.overallScore"))
        XCTAssertTrue(view.contains("if let score = card.overallScore"))
        XCTAssertTrue(view.contains("KigoStylist score was not included in this approved card."))
        XCTAssertFalse(view.contains("KigoStylist score 80/100"))
    }

    func testFriendsPublishingRequiresExplicitReviewAndBoundedDraft() throws {
        let source = try source("StyleMatchAI/StyleFriendsView.swift")
        XCTAssertTrue(source.contains("Button(\"Share with Friends\") { reviewCard = card }"))
        XCTAssertTrue(source.contains("Button(\"Publish\")"))
        XCTAssertTrue(source.contains("SharedOutfitPostDraft.maximumTitleUTF16"))
        XCTAssertTrue(source.contains("SharedOutfitPostDraft.maximumCaptionUTF16"))
        XCTAssertFalse(source.contains("publish(card)"))
    }

    func testNotificationPreferencesAreConservativeAndTyped() {
        let preferences = StyleFriendsNotificationPreferences()
        XCTAssertFalse(preferences.masterEnabled)
        XCTAssertFalse(preferences.likesEnabled)
        XCTAssertFalse(preferences.commentsEnabled)
        XCTAssertFalse(preferences.directMessagesEnabled)
        XCTAssertEqual(preferences.newPostsMode, .off)
        XCTAssertEqual(Set(StyleFriendsNotificationEventType.allCases.map(\.rawValue)), [
            "friend_request_received", "friend_request_accepted", "friend_post_published",
            "outfit_liked", "outfit_commented", "purchase_details_requested", "moderation_account_notice",
            "direct_message", "direct_message_reply", "direct_message_reaction"
        ])
    }

    func testNotificationPreferenceContractIncludesRequiredDirectMessageField() throws {
        var preferences = StyleFriendsNotificationPreferences()
        preferences.masterEnabled = true
        preferences.directMessagesEnabled = true
        let payload = try JSONEncoder().encode(preferences)
        let object = try JSONSerialization.jsonObject(with: payload) as? [String: Any]

        XCTAssertEqual(object?["master_enabled"] as? Bool, true)
        XCTAssertEqual(object?["dm_enabled"] as? Bool, true)
        XCTAssertNotNil(object?["friend_requests_enabled"])
        XCTAssertNotNil(object?["request_accepted_enabled"])
        XCTAssertNotNil(object?["new_posts_mode"])
        XCTAssertNotNil(object?["likes_enabled"])
        XCTAssertNotNil(object?["comments_enabled"])
        XCTAssertNotNil(object?["purchase_questions_enabled"])
    }

    func testNotificationPreferencesDecodeOlderServerResponseWithoutDirectMessageField() throws {
        let response = """
        {"master_enabled":true,"friend_requests_enabled":true,"request_accepted_enabled":true,"new_posts_mode":"off","likes_enabled":false,"comments_enabled":false,"purchase_questions_enabled":false}
        """

        let decoded = try JSONDecoder().decode(StyleFriendsNotificationPreferences.self, from: Data(response.utf8))
        XCTAssertTrue(decoded.masterEnabled)
        XCTAssertFalse(decoded.directMessagesEnabled)
    }

    func testNotificationSettingsPresentationHandlesPermissionAndRegistrationStatesTruthfully() {
        XCTAssertEqual(StyleFriendsNotificationSettingsPresentation.permissionTitle(for: .authorized), "Notifications Allowed")
        XCTAssertEqual(StyleFriendsNotificationSettingsPresentation.permissionActionTitle(for: .notDetermined), "Allow Notifications")
        XCTAssertEqual(StyleFriendsNotificationSettingsPresentation.permissionActionTitle(for: .denied, formFactor: .phone), "Open iPhone Settings")
        XCTAssertEqual(StyleFriendsNotificationSettingsPresentation.permissionActionTitle(for: .denied, formFactor: .pad), "Open iPad Settings")
        XCTAssertNil(StyleFriendsNotificationSettingsPresentation.permissionActionTitle(for: .authorized))

        XCTAssertNil(StyleFriendsNotificationSettingsPresentation.registrationActionTitle(permission: .authorized, registration: .registered))
        XCTAssertNil(StyleFriendsNotificationSettingsPresentation.registrationActionTitle(permission: .provisional, registration: .requesting))
        XCTAssertEqual(StyleFriendsNotificationSettingsPresentation.registrationActionTitle(permission: .authorized, registration: .idle, formFactor: .phone), "Register This iPhone")
        XCTAssertEqual(StyleFriendsNotificationSettingsPresentation.registrationActionTitle(permission: .authorized, registration: .idle, formFactor: .pad), "Register This iPad")
        XCTAssertEqual(StyleFriendsNotificationSettingsPresentation.registrationActionTitle(permission: .authorized, registration: .failed), "Try Registration Again")
        XCTAssertNil(StyleFriendsNotificationSettingsPresentation.registrationActionTitle(permission: .denied, registration: .failed))
    }

    func testNotificationsSettingsUsesStagedPreferencesAndTruthfulCompactStates() throws {
        let source = try source("StyleMatchAI/StyleFriendsNotifications.swift")
        XCTAssertTrue(source.contains("private var saveButton"))
        XCTAssertTrue(source.contains(".disabled(!preferencesDraft.hasUnsavedChanges)"))
        XCTAssertTrue(source.contains("Save notification changes?"))
        XCTAssertTrue(source.contains("Your notification preferences have not been saved."))
        XCTAssertTrue(source.contains("Notifications Allowed"))
        XCTAssertTrue(source.contains("StyleFriendsNotificationDevicePresentation.registrationStatusTitle"))
        XCTAssertTrue(source.contains("StyleFriendsNotificationSettingsPresentation.registrationActionTitle"))
        XCTAssertTrue(source.contains("StyleFriendsNotificationDevicePresentation.registrationActionTitle"))
        XCTAssertTrue(source.contains("case .failed: \"Try Registration Again\""))
        XCTAssertTrue(source.contains("notificationGroup(\"Friends\", systemImage: \"person.2\")"))
        XCTAssertTrue(source.contains("notificationGroup(\"Activity\", systemImage: \"sparkles\")"))
        XCTAssertTrue(source.contains("Notification Privacy"))
        XCTAssertTrue(source.contains("KigoStylist rechecks the current Friend, block, and shared-post authorization."))
        XCTAssertTrue(source.contains("Notification delivery permission and authenticated\n                    // Style Friends preferences are independent authorities."))
        XCTAssertTrue(source.contains("preferencesEditor"))
        XCTAssertFalse(source.contains("canManageStyleFriendsPreferences"))
        XCTAssertFalse(source.contains("Allow device notifications first to manage Style Friends notification preferences."))
    }

    func testNewFriendPostsDraftPreservesParentSelectionAcrossLateLoadSaveAndReload() {
        var server = StyleFriendsNotificationPreferences()
        server.masterEnabled = true
        var draft = StyleFriendsNotificationPreferencesDraft()
        draft.applyServerPreferences(server)

        draft.selectNewPostsMode(.all)
        XCTAssertTrue(draft.preferences.masterEnabled)
        XCTAssertEqual(draft.preferences.newPostsMode, .all)

        // A delayed response carrying the old server value cannot turn the
        // parent row back to Off after the child picker selected All.
        draft.applyServerPreferences(server)
        XCTAssertTrue(draft.preferences.masterEnabled)
        XCTAssertEqual(draft.preferences.newPostsMode, .all)

        server.newPostsMode = .all
        let submitted = draft.preferences
        draft.applySaveResult(server, submitted: submitted)
        XCTAssertEqual(draft.preferences, server)

        for mode in StyleFriendsNewPostNotificationMode.allCases {
            draft.selectNewPostsMode(mode)
            XCTAssertTrue(draft.preferences.masterEnabled)
            XCTAssertEqual(draft.preferences.newPostsMode, mode)
            server.newPostsMode = mode
            draft.applySaveResult(server, submitted: draft.preferences)
            draft.applyServerPreferences(server)
            XCTAssertEqual(draft.preferences.newPostsMode, mode)
        }
    }

    func testNotificationRouteAcceptsOnlyBoundedOpaqueReferences() {
        let validFriend = "sf_" + String(repeating: "a", count: 43)
        let validPost = String(repeating: "p", count: 24)
        let route = StyleFriendsNotificationRoute(userInfo: ["style_friends": [
            "event_type": "friend_post_published", "post_ref": validPost, "friend_social_ref": validFriend
        ]])
        XCTAssertEqual(route?.type, .friendPostPublished)
        XCTAssertEqual(route?.postReference?.value, validPost)
        XCTAssertEqual(route?.friendReference?.value, validFriend)
        XCTAssertNil(StyleFriendsNotificationRoute(userInfo: ["style_friends": ["event_type": "unknown"]]))
        let conversation = String(repeating: "c", count: 24)
        let message = String(repeating: "m", count: 24)
        let directMessage = StyleFriendsNotificationRoute(userInfo: ["style_friends": [
            "event_type": "direct_message",
            "conversation_ref": conversation,
            "message_ref": message
        ]])
        XCTAssertEqual(directMessage?.conversationReference?.value, conversation)
        XCTAssertEqual(directMessage?.messageReference?.value, message)
        XCTAssertTrue(directMessage?.isDirectMessageRoute == true)
        XCTAssertTrue(directMessage?.id.contains(conversation) == true)
        XCTAssertTrue(directMessage?.id.contains(message) == true)
        XCTAssertNil(StyleFriendsNotificationRoute(userInfo: ["style_friends": ["event_type": "direct_message"]]))
    }

    func testDirectMessageNotificationTapRoutesFromAppRootToExactMessage() throws {
        let content = try source("StyleMatchAI/ContentView.swift")
        let chat = try source("StyleMatchAI/StyleFriendsChatUI.swift")
        let notifications = try source("StyleMatchAI/StyleFriendsNotifications.swift")

        XCTAssertTrue(content.contains("styleFriendsNotificationRoutes.$route.compactMap"))
        XCTAssertTrue(content.contains("pendingStyleFriendsMessageRoute = route"))
        XCTAssertTrue(content.contains("fullScreenCover(item: $pendingStyleFriendsMessageRoute)"))
        XCTAssertTrue(content.contains("StyleFriendsNotificationMessageHost(route: route)"))

        XCTAssertTrue(chat.contains("route.conversationReference"))
        XCTAssertTrue(chat.contains("binding.service.conversations(cursor: cursor)"))
        XCTAssertTrue(chat.contains("initialMessageReference: route.messageReference"))
        XCTAssertTrue(chat.contains("messages.contains(where: { $0.messageReference == initialMessageReference })"))
        XCTAssertTrue(chat.contains("reader.scrollTo(target, anchor: .center)"))

        XCTAssertTrue(notifications.contains("var isDirectMessageRoute: Bool"))
        XCTAssertTrue(notifications.contains("conversation_ref"))
        XCTAssertTrue(notifications.contains("message_ref"))
    }

    func testNotificationFoundationDoesNotPersistTokensInSocialUIOrCreateNewAuthorization() throws {
        let source = try source("StyleMatchAI/StyleFriendsNotifications.swift")
        XCTAssertTrue(source.contains("UNUserNotificationCenter"))
        XCTAssertTrue(source.contains("registerForRemoteNotifications"))
        XCTAssertTrue(source.contains("StyleMatchAccountSessionStore.load"))
        XCTAssertTrue(source.contains("KigoStylist rechecks the current Friend, block, and shared-post authorization."))
        XCTAssertTrue(source.contains("conversation_ref"))
        XCTAssertTrue(source.contains("StyleFriendsAPNsRuntimeAuthority"))
        XCTAssertEqual(StyleFriendsAPNsRuntimeAuthority.configuredMode, .disabled)
        XCTAssertFalse(StyleFriendsAPNsRuntimeAuthority.allowsRegistration)
        XCTAssertTrue(StyleFriendsAPNsRuntimeAuthority.permitsRegistration(mode: .developmentAuthorized, runtimeEnvironment: "development", signedAPSEnvironment: "development", workerConfigured: true, supportsRemoteNotifications: true))
        XCTAssertTrue(StyleFriendsAPNsRuntimeAuthority.permitsRegistration(mode: .productionAuthorized, runtimeEnvironment: "production", signedAPSEnvironment: "production", workerConfigured: true, supportsRemoteNotifications: true))
        XCTAssertFalse(StyleFriendsAPNsRuntimeAuthority.permitsRegistration(mode: .developmentAuthorized, runtimeEnvironment: "development", signedAPSEnvironment: nil, workerConfigured: true, supportsRemoteNotifications: true))
        XCTAssertEqual(StyleFriendsAPNsRuntimeAuthority.genericPrivateMessagePreview, "New message from a Style Friend")
        XCTAssertFalse(source.contains("UserDefaults.standard.set(deviceToken"))
        XCTAssertFalse(source.contains("CloudKit"))
        XCTAssertFalse(source.contains("Closet"))
        XCTAssertFalse(source.contains("AI Memory"))
    }

    func testAPNsRuntimeGateAcceptsExactStagingForDevelopmentAndExactProductionHostForRelease() {
        let accepted = StyleFriendsAPNsRuntimeAuthority.permitsRegistration(
            mode: .developmentAuthorized,
            runtimeEnvironment: "development",
            signedAPSEnvironment: "development",
            workerConfigured: true,
            supportsRemoteNotifications: true
        )
        XCTAssertTrue(accepted) // Explicit Debug/development authority.
        XCTAssertFalse(StyleFriendsAPNsRuntimeAuthority.permitsRegistration(mode: .disabled, runtimeEnvironment: "development", signedAPSEnvironment: "development", workerConfigured: true, supportsRemoteNotifications: true))
        XCTAssertTrue(StyleFriendsAPNsRuntimeAuthority.permitsRegistration(mode: .productionAuthorized, runtimeEnvironment: "production", signedAPSEnvironment: "production", workerConfigured: true, supportsRemoteNotifications: true))
        XCTAssertFalse(StyleFriendsAPNsRuntimeAuthority.permitsRegistration(mode: .developmentAuthorized, runtimeEnvironment: "production", signedAPSEnvironment: "development", workerConfigured: true, supportsRemoteNotifications: true))
        XCTAssertFalse(StyleFriendsAPNsRuntimeAuthority.permitsRegistration(mode: .productionAuthorized, runtimeEnvironment: "development", signedAPSEnvironment: "production", workerConfigured: true, supportsRemoteNotifications: true))
        XCTAssertFalse(StyleFriendsAPNsRuntimeAuthority.permitsRegistration(mode: .productionAuthorized, runtimeEnvironment: "production", signedAPSEnvironment: "development", workerConfigured: true, supportsRemoteNotifications: true))
        XCTAssertFalse(StyleFriendsAPNsRuntimeAuthority.permitsRegistration(mode: .developmentAuthorized, runtimeEnvironment: "development", signedAPSEnvironment: nil, workerConfigured: true, supportsRemoteNotifications: true))
        XCTAssertFalse(StyleFriendsAPNsRuntimeAuthority.permitsRegistration(mode: .developmentAuthorized, runtimeEnvironment: "development", signedAPSEnvironment: "development", workerConfigured: false, supportsRemoteNotifications: true))
        XCTAssertFalse(StyleFriendsAPNsRuntimeAuthority.permitsRegistration(mode: .developmentAuthorized, runtimeEnvironment: "development", signedAPSEnvironment: "development", workerConfigured: true, supportsRemoteNotifications: false))
        XCTAssertEqual(StyleFriendsAPNsRuntimeAuthority.developmentWorkerURL(rawValue: "https://stylematch-friends-staging.sabastine-7000.workers.dev")?.host, AppBackendConfiguration.approvedFriendsStagingAPIHost)
        XCTAssertEqual(StyleFriendsAPNsRuntimeAuthority.productionWorkerURL(rawValue: "https://api.stylematchpro.com")?.host, AppBackendConfiguration.approvedProductionAPIHost)
        XCTAssertEqual(StyleFriendsAPNsRuntimeAuthority.workerURL(rawValue: "https://api.stylematchpro.com", mode: .productionAuthorized)?.host, AppBackendConfiguration.approvedProductionAPIHost)
        XCTAssertNil(StyleFriendsAPNsRuntimeAuthority.productionWorkerURL(rawValue: "https://stylematch-friends-staging.sabastine-7000.workers.dev"))
        [
            nil,
            "",
            "http://stylematch-friends-staging.sabastine-7000.workers.dev",
            "https://localhost",
            "https://api.stylematchpro.com",
            "https://example.com",
            "https://stylematch-friends-staging.sabastine-7000.workers.dev/path",
            "https://stylematch-friends-staging.sabastine-7000.workers.dev?redirect=bad",
            "https://stylematch-friends-staging.sabastine-7000.workers.dev:8443"
        ].forEach { XCTAssertNil(StyleFriendsAPNsRuntimeAuthority.developmentWorkerURL(rawValue: $0)) }
    }

    func testAPNsTokenLifecycleAndSourceBoundariesAreAccountScopedAndTruthful() throws {
        let notificationSource = try source("StyleMatchAI/StyleFriendsNotifications.swift")
        let debug = try source("Config/StyleMatchDebug.xcconfig")
        let release = try source("Config/StyleMatchRelease.xcconfig")
        let info = try source("StyleMatchAI/Info.plist")
        let project = try source("StyleMatchAI.xcodeproj/project.pbxproj")
        XCTAssertEqual(StyleFriendsNotificationService.normalizedDeviceToken(Data([0x00, 0x0a, 0xff])), "000aff")
        XCTAssertTrue(notificationSource.contains("registeredSession"))
        XCTAssertTrue(notificationSource.contains("removeTokens(session: session)"))
        XCTAssertTrue(notificationSource.contains("No token is persisted locally"))
        XCTAssertTrue(notificationSource.contains("try await deviceRegistration.register(deviceToken: token, session: session)"))
        XCTAssertTrue(notificationSource.contains("guard registrationSession != nil else"))
        XCTAssertTrue(notificationSource.contains("openSystemNotificationSettings"))
        XCTAssertTrue(notificationSource.contains("UIApplication.openSettingsURLString"))
        XCTAssertFalse(notificationSource.contains("Allow device notifications first to manage Style Friends notification preferences."))
        XCTAssertTrue(notificationSource.contains("StyleFriendsNotificationDevicePresentation.registrationActionTitle"))
        XCTAssertTrue(notificationSource.contains("StyleFriendsNotificationDevicePresentation.registrationStatusTitle"))
        XCTAssertTrue(notificationSource.contains("deviceRegistrationCard"))
        XCTAssertTrue(notificationSource.contains(".navigationTitle(\"Notifications\")"))
        XCTAssertFalse(notificationSource.contains("canManageStyleFriendsPreferences"))
        XCTAssertTrue(notificationSource.contains("Style Friends preferences are independent authorities."))
        XCTAssertTrue(notificationSource.contains("KigoStylist rechecks the current Friend, block, and shared-post authorization."))
        XCTAssertTrue(notificationSource.contains("conversation_ref"))
        XCTAssertTrue(notificationSource.contains("message_ref"))
        XCTAssertFalse(notificationSource.contains("print(token"))
        XCTAssertFalse(notificationSource.contains("CloudKit"))
        XCTAssertFalse(notificationSource.contains("APNS_PRIVATE_KEY"))
        XCTAssertFalse(notificationSource.contains("restored message"))
        XCTAssertTrue(debug.contains("STYLEMATCH_APNS_RUNTIME_AUTHORITY = disabled"))
        XCTAssertTrue(debug.contains("STYLEMATCH_APNS_WORKER_URL ="))
        XCTAssertTrue(release.contains("STYLEMATCH_APNS_RUNTIME_AUTHORITY = productionAuthorized"))
        XCTAssertTrue(release.contains("STYLEMATCH_APNS_WORKER_URL = https:/$()/api.stylematchpro.com"))
        XCTAssertTrue(info.contains("<key>STYLEMATCH_APNS_RUNTIME_AUTHORITY</key>"))
        XCTAssertTrue(info.contains("<string>$(STYLEMATCH_APNS_RUNTIME_AUTHORITY)</string>"))
        XCTAssertTrue(info.contains("<key>STYLEMATCH_APNS_WORKER_URL</key>"))
        XCTAssertTrue(info.contains("<string>$(STYLEMATCH_APNS_WORKER_URL)</string>"))
        XCTAssertTrue(info.contains("<key>STYLEMATCH_APS_ENVIRONMENT</key>"))
        XCTAssertTrue(info.contains("<string>$(APS_ENVIRONMENT)</string>"))
        XCTAssertTrue(project.contains("INFOPLIST_KEY_STYLEMATCH_APS_ENVIRONMENT = \"$(APS_ENVIRONMENT)\";"))
        XCTAssertTrue(project.contains("INFOPLIST_KEY_STYLEMATCH_APNS_RUNTIME_AUTHORITY = \"$(STYLEMATCH_APNS_RUNTIME_AUTHORITY)\";"))
    }

    func testAPNsSourceLifecycleIsFailClosedAndUsesOnlyOpaqueDeepLinks() throws {
        let source = try source("StyleMatchAI/StyleFriendsNotifications.swift")
        XCTAssertTrue(source.contains("permissionState()"))
        XCTAssertTrue(source.contains("requestAuthorization(options"))
        XCTAssertTrue(source.contains("didReceiveDeviceToken"))
        XCTAssertTrue(source.contains("removeTokens(session:"))
        XCTAssertTrue(source.contains("conversation_ref"))
        XCTAssertTrue(source.contains("message_ref"))
        XCTAssertTrue(source.contains("StyleFriendsAPNsRuntimeAuthority.allowsRegistration"))
        XCTAssertTrue(source.contains("developmentAuthorized"))
        XCTAssertTrue(source.contains("productionAuthorized"))
        XCTAssertTrue(source.contains("New message from a Style Friend"))
        XCTAssertTrue(source.contains("STYLEMATCH_APS_ENVIRONMENT"))
        XCTAssertFalse(source.contains("CloudKit"))
    }

    func testSimulatorAcceptanceHarnessIsDebugSimulatorOnlyAndRequiresTheExactTestEndpoint() throws {
        let account = try source("StyleMatchAI/AccountService.swift")
        let app = try source("StyleMatchAI/StyleMatchAIApp.swift")
        let friends = try source("StyleMatchAI/StyleFriendsFoundation.swift")

        XCTAssertTrue(account.contains("#if DEBUG && targetEnvironment(simulator)"))
        XCTAssertTrue(account.contains("STYLEMATCH_SIMULATOR_SYNTHETIC_SESSION"))
        XCTAssertTrue(account.contains("approvedFriendsAuthTestAPIHost"))
        XCTAssertTrue(app.contains("StyleMatchSimulatorFriendsAuthTestHarness.applyIfConfigured()"))
        XCTAssertTrue(friends.contains("StyleMatchRuntimeEndpoint.accountResolution()"))
        XCTAssertFalse(account.contains("skip login"))
    }

    func testBuildIdentityIsBuild18055AcrossAppConfigurations() throws {
        let project = try source("StyleMatchAI.xcodeproj/project.pbxproj")
        XCTAssertEqual(project.components(separatedBy: "CURRENT_PROJECT_VERSION = 18039;").count - 1, 0)
        XCTAssertEqual(project.components(separatedBy: "CURRENT_PROJECT_VERSION = 18046;").count - 1, 0)
        XCTAssertEqual(project.components(separatedBy: "CURRENT_PROJECT_VERSION = 18048;").count - 1, 0)
        XCTAssertEqual(project.components(separatedBy: "CURRENT_PROJECT_VERSION = 18049;").count - 1, 0)
        XCTAssertEqual(project.components(separatedBy: "CURRENT_PROJECT_VERSION = 18055;").count - 1, 3)
        XCTAssertEqual(project.components(separatedBy: "MARKETING_VERSION = 1.8.2;").count - 1, 3)
    }

    func testOwnerDeviceAcceptanceIsExplicitlyCompileGatedAndReleaseExcluded() throws {
        let foundation = try source("StyleMatchAI/StyleFriendsFoundation.swift")
        let configuration = try source("StyleMatchAI/AppBackendConfiguration.swift")

        XCTAssertTrue(foundation.contains("#if DEBUG && STYLE_FRIENDS_OWNER_DEVICE_ACCEPTANCE"))
        XCTAssertTrue(foundation.contains("#if targetEnvironment(simulator)"))
        XCTAssertTrue(foundation.contains("STYLEMATCH_OWNER_DEVICE_ACCEPTANCE_MODE"))
        XCTAssertTrue(foundation.contains("STYLEMATCH_OWNER_DEVICE_STYLE_FRIENDS_ENDPOINT"))
        XCTAssertTrue(foundation.contains("STYLEMATCH_OWNER_DEVICE_STYLE_FRIENDS_SYNTHETIC_SESSION"))
        XCTAssertTrue(foundation.contains("return .unavailable"))
        XCTAssertTrue(configuration.contains("#if DEBUG || OWNER_BETA"))
        XCTAssertFalse(foundation.contains("StyleMatchAccountSessionStore.save"))
        XCTAssertFalse(foundation.contains("ShareableScoreCardLocalStore().saveCreatedCard"))
    }

    func testOnlyOwnerBetaCarriesStagingAuthorityWhileReleaseUsesExactProductionDMLane() throws {
        let debug = try source("Config/StyleMatchDebug.xcconfig")
        let release = try source("Config/StyleMatchRelease.xcconfig")
        let configuration = try source("StyleMatchAI/AppBackendConfiguration.swift")
        let dedicatedHost = "stylematch-friends-staging.sabastine-7000.workers.dev"
        let obsoleteHost = "stylematch-18039-friends-dm-staging.sabastine-7000.workers.dev"

        XCTAssertFalse(debug.contains(dedicatedHost))
        XCTAssertTrue(debug.contains("STYLEMATCH_STYLE_FRIENDS_DM_RUNTIME_AUTHORITY = disabled"))
        XCTAssertTrue(debug.contains("STYLEMATCH_STYLE_FRIENDS_FEED_RUNTIME_AUTHORITY = disabled"))
        XCTAssertTrue(debug.contains("STYLEMATCH_SUPPORT_RUNTIME_AUTHORITY = disabled"))
        XCTAssertTrue(debug.contains("STYLEMATCH_SOCIAL_IMAGES_RUNTIME_AUTHORITY = disabled"))
        XCTAssertFalse(debug.contains(obsoleteHost))
        XCTAssertTrue(configuration.contains("static let approvedFriendsStagingAPIHost = \"\(dedicatedHost)\""))
        XCTAssertTrue(configuration.contains("static func isAuthorizedFriendsStagingHost"))
        XCTAssertTrue(configuration.contains("#if DEBUG || OWNER_BETA || TESTFLIGHT_BETA\n        host?.lowercased() == approvedFriendsStagingAPIHost\n        #else\n        false"))
        XCTAssertFalse(configuration.contains(obsoleteHost))
        XCTAssertTrue(release.contains("STYLEMATCH_STYLE_FRIENDS_DM_RUNTIME_AUTHORITY = productionAuthorized"))
        XCTAssertTrue(release.contains("STYLEMATCH_STYLE_FRIENDS_DM_ATTACHMENTS_RUNTIME_AUTHORITY = disabled"))
        XCTAssertTrue(release.contains("STYLEMATCH_STYLE_FRIENDS_FEED_RUNTIME_AUTHORITY = disabled"))
        XCTAssertTrue(release.contains("STYLEMATCH_SUPPORT_RUNTIME_AUTHORITY = disabled"))
        XCTAssertTrue(release.contains("STYLEMATCH_APNS_RUNTIME_AUTHORITY = productionAuthorized"))
        XCTAssertTrue(release.contains("api.stylematchpro.com"))
        XCTAssertFalse(release.contains(dedicatedHost))
    }

    func testOwnerBetaConfigurationIsExplicitAndReleaseRemainsFailClosed() throws {
        let ownerBeta = try source("Config/StyleMatchOwnerBeta.xcconfig")
        let release = try source("Config/StyleMatchRelease.xcconfig")
        let project = try source("StyleMatchAI.xcodeproj/project.pbxproj")
        let scheme = try source("StyleMatchAI.xcodeproj/xcshareddata/xcschemes/StyleMatchAI-OwnerBeta.xcscheme")
        let host = "stylematch-friends-staging.sabastine-7000.workers.dev"

        XCTAssertTrue(ownerBeta.contains("STYLEMATCH_API_BASE_URL = https:/$()/\(host)"))
        XCTAssertTrue(ownerBeta.contains("STYLEMATCH_SOURCE_CHECKPOINT = 400cd982f9cc16df3352f61c6d9430bdbcc1b0d5"))
        XCTAssertTrue(ownerBeta.contains("STYLEMATCH_SUPPORT_RUNTIME_AUTHORITY = stagingAuthorized"))
        XCTAssertTrue(ownerBeta.contains("STYLEMATCH_STYLE_FRIENDS_DM_RUNTIME_AUTHORITY = stagingAuthorized"))
        XCTAssertTrue(ownerBeta.contains("STYLEMATCH_STYLE_FRIENDS_FEED_RUNTIME_AUTHORITY = stagingAuthorized"))
        XCTAssertTrue(ownerBeta.contains("STYLEMATCH_SOCIAL_IMAGES_RUNTIME_AUTHORITY = stagingAuthorized"))
        XCTAssertTrue(ownerBeta.contains("STYLEMATCH_APNS_RUNTIME_AUTHORITY = developmentAuthorized"))
        XCTAssertFalse(release.contains(host))
        XCTAssertTrue(release.contains("STYLEMATCH_SUPPORT_RUNTIME_AUTHORITY = disabled"))
        XCTAssertTrue(project.contains("StyleMatchOwnerBeta.xcconfig"))
        XCTAssertTrue(project.contains("CURRENT_PROJECT_VERSION = 18055;"))
        XCTAssertFalse(project.contains("CURRENT_PROJECT_VERSION = 18046;"))
        XCTAssertTrue(project.contains("SWIFT_ACTIVE_COMPILATION_CONDITIONS = \"OWNER_BETA $(inherited)\";"))
        XCTAssertTrue(scheme.contains("ArchiveAction buildConfiguration=\"OwnerBeta\""))
    }

    func testFriendsStagingHostAuthorityIsCentralizedAndReleaseFailsClosedByConstruction() throws {
        let directMessages = try source("StyleMatchAI/StyleFriendsDirectMessages.swift")
        let support = try source("StyleMatchAI/StyleMatchSupportCenter.swift")
        let notifications = try source("StyleMatchAI/StyleFriendsNotifications.swift")

        XCTAssertTrue(AppBackendConfiguration.isAuthorizedFriendsStagingHost("stylematch-friends-staging.sabastine-7000.workers.dev"))
        XCTAssertFalse(AppBackendConfiguration.isAuthorizedFriendsStagingHost(AppBackendConfiguration.approvedProductionAPIHost))
        XCTAssertTrue(directMessages.contains("AppBackendConfiguration.isAuthorizedFriendsStagingHost"))
        XCTAssertTrue(support.contains("AppBackendConfiguration.isAuthorizedFriendsStagingHost"))
        XCTAssertTrue(notifications.contains("AppBackendConfiguration.isAuthorizedFriendsStagingHost"))
        XCTAssertFalse(directMessages.contains("url.host?.lowercased() == AppBackendConfiguration.approvedFriendsStagingAPIHost"))
        XCTAssertFalse(support.contains("url.host?.lowercased() == AppBackendConfiguration.approvedFriendsStagingAPIHost"))
    }

    func testProfileAvatarLifecycleUsesOnlyAuthenticatedOpaqueRoutes() throws {
        let foundation = try source("StyleMatchAI/StyleFriendsFoundation.swift")
        let view = try source("StyleMatchAI/StyleFriendsView.swift")
        XCTAssertTrue(foundation.contains("static let profileAvatar = \"/v1/friends/profile/avatar\""))
        XCTAssertTrue(foundation.contains("func uploadProfileAvatar"))
        XCTAssertTrue(foundation.contains("func removeProfileAvatar"))
        XCTAssertTrue(foundation.contains("StyleFriendAvatarState"))
        XCTAssertTrue(view.contains("PhotosPicker"))
        XCTAssertTrue(foundation.contains("case avatarState = \"avatar_state\""))
        XCTAssertTrue(view.contains("server is the canonical crop/normalization authority"))
        XCTAssertFalse(foundation.contains("r2.dev"))
    }

    func testMissingProfileAvatarControlExplainsAndFocusesTheSingleRequiredSetupStep() throws {
        let view = try source("StyleMatchAI/StyleFriendsView.swift")
        XCTAssertTrue(view.contains("if socialProfileEstablished {\n                    PhotosPicker"))
        XCTAssertTrue(view.contains("focusedSocialProfileField = .displayName"))
        XCTAssertTrue(view.contains("Add a display name, then create your public Style Friends profile before choosing a photo."))
        XCTAssertTrue(view.contains(".accessibilityLabel(\"Profile photo unavailable\")"))
        XCTAssertTrue(view.contains(".accessibilityValue(\"Create a public Style Friends profile first\")"))
        XCTAssertTrue(view.contains("Double-tap to focus the Display name field."))
        XCTAssertFalse(view.contains(".disabled(!socialProfileEstablished"))
    }

    func testProfileAvatarPreparationUsesDecodedPixelMetadataAndRawBodyBudget() throws {
        let view = try source("StyleMatchAI/StyleFriendsView.swift")
        XCTAssertTrue(view.contains("prepareAvatarUpload(from: data)"))
        XCTAssertTrue(view.contains("CGImageSourceCopyPropertiesAtIndex"))
        XCTAssertTrue(view.contains("kCGImagePropertyPixelWidth"))
        XCTAssertTrue(view.contains("kCGImagePropertyPixelHeight"))
        XCTAssertTrue(view.contains("CGImageSourceCreateThumbnailAtIndex"))
        XCTAssertTrue(view.contains("CGImageSourceGetType(source)"))
        XCTAssertTrue(view.contains("decodedType.conforms(to: .image)"))
        XCTAssertTrue(view.contains("sqrt(Double(maximumPixels) / sourcePixels)"))
        XCTAssertTrue(view.contains("maximumPixels = 24_000_000"))
        XCTAssertTrue(view.contains("maximumUploadBytes = 7 * 1024 * 1024"))
        XCTAssertTrue(view.contains("not multipart or JSON/base64"))
        XCTAssertTrue(view.contains("result.width <= sourceWidth"))
        XCTAssertTrue(view.contains("result.height <= sourceHeight"))
        XCTAssertTrue(view.contains("qualityCandidates: [CGFloat] = [0.92, 0.88, 0.84, 0.80]"))
        XCTAssertTrue(view.contains("jpeg.count <= maximumUploadBytes"))
        XCTAssertTrue(view.contains("source EXIF, GPS, orientation"))
        XCTAssertTrue(view.contains("too large or cannot be prepared safely"))
        XCTAssertFalse(view.contains("image.size.width * image.scale"))
    }

    func testAvatarPixelBudgetFixturesNeverUpscaleAndAlwaysFitTheWorkerLimit() {
        let maximumPixels = 24_000_000.0
        func output(_ width: Int, _ height: Int) -> (Int, Int) {
            let sourcePixels = Double(width) * Double(height)
            let scale = min(1, sqrt(maximumPixels / sourcePixels))
            return (
                max(1, Int((Double(width) * scale).rounded(.down))),
                max(1, Int((Double(height) * scale).rounded(.down)))
            )
        }
        for (width, height) in [(5_712, 4_284), (8_064, 6_048), (8_192, 8_192), (1_200, 900)] {
            let result = output(width, height)
            XCTAssertLessThanOrEqual(result.0 * result.1, 24_000_000)
            XCTAssertLessThanOrEqual(result.0, width)
            XCTAssertLessThanOrEqual(result.1, height)
        }
    }

    func testProfileAvatarIgnoresStaleFetchesAndKeepsPreviewUntilCurrentReferenceLoads() throws {
        let view = try source("StyleMatchAI/StyleFriendsView.swift")
        XCTAssertTrue(view.contains("avatarPresentationGeneration"))
        XCTAssertTrue(view.contains("beginAvatarReplacement()"))
        XCTAssertTrue(view.contains("uploadGeneration == avatarPresentationGeneration"))
        XCTAssertTrue(view.contains("profileGeneration == avatarPresentationGeneration"))
        XCTAssertTrue(view.contains("socialProfileDraft.avatarReference == expectedReference"))
        XCTAssertTrue(view.contains("AVATAR_FETCH\", \"STALE_IGNORED"))
        XCTAssertTrue(view.contains("activeAvatarReference == socialProfileDraft.avatarReference"))
        XCTAssertTrue(view.contains("provisionalAvatar = nil\n            avatarState = .active"))
    }

    func testAvatarFailureIsVisibleAndSurvivesARefreshWithNoReference() throws {
        let view = try source("StyleMatchAI/StyleFriendsView.swift")
        XCTAssertTrue(view.contains("if let avatarFeedback {"))
        XCTAssertFalse(view.contains("if let avatarFeedback, avatarState != .failed && avatarState != .rejected"))
        XCTAssertTrue(view.contains("if avatarState != .underReview && avatarState != .failed && avatarState != .rejected"))
        XCTAssertTrue(view.contains("Photo upload did not complete. Your active photo was not changed."))
        XCTAssertTrue(view.contains("Retry photo upload"))
        XCTAssertTrue(view.contains("Photo upload was interrupted. Retry to try again."))
    }

    func testExistingCanonicalProfileSurvivesAvatarUploadFailure() throws {
        let view = try source("StyleMatchAI/StyleFriendsView.swift")
        XCTAssertTrue(view.contains("case loading, established, missing, unavailable"), "Profile refresh needs an explicit unavailable state rather than treating an error as absence.")
        XCTAssertTrue(view.contains("socialProfileLoadState = .unavailable"))
    }

    func testExistingProfileSurvivesDoneDismissAndImmediateReopen() throws {
        let view = try source("StyleMatchAI/StyleFriendsView.swift")
        XCTAssertTrue(view.contains("if socialProfileLoadState == .loading && !socialProfileEstablished"))
        XCTAssertTrue(view.contains("Loading your public Style Friends profile"))
    }

    func testSessionOrTransportFailureCannotBecomeProfileMissing() throws {
        let view = try source("StyleMatchAI/StyleFriendsView.swift")
        XCTAssertTrue(view.contains("socialProfileLoadState = .unavailable"))
        XCTAssertFalse(view.contains("catch { profileFeedback = StyleFriendsServiceError.unavailable.errorDescription }"))
    }

    func testDraftFieldsRemainIntactWhileCanonicalRefreshIsPending() throws {
        let view = try source("StyleMatchAI/StyleFriendsView.swift")
        XCTAssertTrue(view.contains("socialProfileLoadState = socialProfileEstablished ? .established : .loading"))
        XCTAssertTrue(view.contains("// Only an authoritative successful empty profile response"))
    }

    func testOnlyAuthoritativeProfileMissingMayEnterCreateProfileMode() throws {
        let view = try source("StyleMatchAI/StyleFriendsView.swift")
        XCTAssertTrue(view.contains("socialProfileLoadState = .missing"))
        XCTAssertTrue(view.contains("case .success(nil):"))
    }

    func testBlankTransientStateCannotOverwriteKnownCanonicalProfile() throws {
        let view = try source("StyleMatchAI/StyleFriendsView.swift")
        XCTAssertTrue(view.contains("guard profileGeneration == avatarPresentationGeneration else { return }"))
        XCTAssertTrue(view.contains("case .failure:"))
    }

    func testSuccessfulCanonicalRefreshUpdatesRetainedProfile() throws {
        let view = try source("StyleMatchAI/StyleFriendsView.swift")
        XCTAssertTrue(view.contains("socialProfileLoadState = .established"))
        XCTAssertTrue(view.contains("savedSocialProfileDraft = draft"))
    }

    func testAvatarFailureFeedbackRemainsTruthfulDuringProfileRecovery() throws {
        let view = try source("StyleMatchAI/StyleFriendsView.swift")
        XCTAssertTrue(view.contains("Photo upload did not complete. Your active photo was not changed."))
        XCTAssertTrue(view.contains("Retry profile refresh"))
    }

    func testAuthenticatedAvatarReadFailureDoesNotClearCanonicalReference() throws {
        let view = try source("StyleMatchAI/StyleFriendsView.swift")
        XCTAssertTrue(view.contains("Your saved photo could not be loaded. Your profile photo was not removed."))
        XCTAssertFalse(view.contains("socialProfileDraft.avatarReference = \"\"; savedSocialProfileDraft.avatarReference = \"\"; avatarState = .noPhoto"))
    }

    func testOwnerDeviceAcceptanceCanNeverFallBackToProductionOrTheNormalSession() throws {
        let view = try source("StyleMatchAI/StyleFriendsView.swift")
        let foundation = try source("StyleMatchAI/StyleFriendsFoundation.swift")
        let configuration = try source("StyleMatchAI/AppBackendConfiguration.swift")

        XCTAssertTrue(view.contains("baseURL: URL(string: \"https://invalid.invalid\")!"))
        XCTAssertTrue(view.contains("accountSession: { nil }"))
        XCTAssertTrue(view.contains("baseURL: configuration.baseURL"))
        XCTAssertTrue(view.contains("accountSession: { configuration.session }"))
        XCTAssertTrue(foundation.contains("environment[StyleMatchRuntimeEndpoint.overrideEnvironmentKey] == nil"))
        XCTAssertTrue(foundation.contains("AppBackendConfiguration.approvedFriendsAuthTestAPIHost"))
        XCTAssertTrue(foundation.contains("StyleMatchRuntimeEndpoint.overrideEnvironmentKey"))
        XCTAssertTrue(configuration.contains("stylematch-friends-staging.sabastine-7000.workers.dev"))
        XCTAssertFalse(configuration.contains("stylematch-18039-friends-dm-staging.sabastine-7000.workers.dev"))
        let accountService = try source("StyleMatchAI/AccountService.swift")
        XCTAssertTrue(accountService.contains("StyleMatchAccountSessionStore.save"))
    }

    func testOwnerDeviceAcceptanceKeepsSyntheticCardsAndIndicatorOutsidePrivateStores() throws {
        let view = try source("StyleMatchAI/StyleFriendsView.swift")
        let foundation = try source("StyleMatchAI/StyleFriendsFoundation.swift")

        XCTAssertTrue(foundation.contains("Style Friends Test Environment"))
        XCTAssertTrue(view.contains("if case let .active(acceptance) = ownerDeviceAcceptance"))
        XCTAssertTrue(view.contains("approvedCards = acceptance.syntheticCard.map { [$0] } ?? []"))
        XCTAssertTrue(view.contains("ShareableScoreCardConfiguration(baseURL: acceptance.baseURL)"))
        XCTAssertTrue(view.contains("ShareableScoreCardLocalStore().markRevoked(token: card.token)"))
        XCTAssertFalse(foundation.contains("UserDefaults.standard"))
        XCTAssertFalse(foundation.contains("CKContainer"))
        XCTAssertFalse(foundation.contains("ProfileStore("))
        XCTAssertFalse(foundation.contains("AIPersistentMemoryStore"))
        XCTAssertFalse(foundation.contains("ClosetPersistenceAuthority"))
    }

    func testNormalDebugBuildWithoutTheOwnerAcceptanceConditionIsInert() {
        switch StyleFriendsOwnerDeviceAcceptance.state(environment: [:]) {
        case .inactive:
            break
        case .unavailable, .active:
            XCTFail("Normal Debug and Release builds must not activate owner-device acceptance mode.")
        }
    }

    func testAccountLifecycleCopyDistinguishesSignOutFromPermanentDeletion() throws {
        let source = try source("StyleMatchAI/ProfileView.swift")
        XCTAssertTrue(source.contains("Your account and data remain available when you return."))
        XCTAssertTrue(source.contains("If you return later, you can create a new KigoStylist account, but permanently deleted data will not be restored."))
        XCTAssertFalse(source.contains("recover your deleted account"))
    }

    func testHomeSearchRegistersAndRoutesOnlyExistingStyleFriendsDestinations() throws {
        let home = try source("StyleMatchAI/HomeView.swift")
        let profile = try source("StyleMatchAI/ProfileView.swift")
        let friends = try source("StyleMatchAI/StyleFriendsView.swift")

        for identifier in ["style-friends", "style-friends-friends", "style-friends-find", "style-friends-requests", "style-friends-conversations", "style-friends-shared-looks", "style-friends-feed"] {
            XCTAssertTrue(home.contains("id: \"\(identifier)\""))
        }
        XCTAssertTrue(home.contains("navigationMatchRank(for:"))
        XCTAssertTrue(home.contains("StyleFriendsHomeSearchRoute.storageKey"))
        XCTAssertTrue(home.contains("navigationSearchFocused = false"))
        XCTAssertTrue(profile.contains("consumeStyleFriendsHomeSearchRoute()"))
        XCTAssertTrue(profile.contains("StyleFriendsView("))
        XCTAssertTrue(profile.contains("homeSearchRoute: styleFriendsHomeSearchRoute"))
        XCTAssertTrue(profile.contains("onCreateShareCard:"))
        XCTAssertTrue(friends.contains("homeSearchRoute: StyleFriendsHomeSearchRoute? = nil"))
        XCTAssertTrue(friends.contains("_isShowingDiscovery = State(initialValue: homeSearchRoute == .findFriends)"))
        XCTAssertTrue(friends.contains("_isShowingConversations = State(initialValue: homeSearchRoute == .conversations)"))
    }

    func testReleaseHasNoReusableProviderKeyStorageAuthority() throws {
        let client = try source("StyleMatchAI/OpenAIStylistClient.swift")
        let shop = try source("StyleMatchAI/ShopView.swift")
        let retirement = try source("StyleMatchAI/LegacyProviderCredentialRetirement.swift")
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

        XCTAssertTrue(retirement.contains("SecItemDelete"))
        XCTAssertFalse(retirement.contains("SecItemCopyMatching"))
        XCTAssertFalse(retirement.contains("kSecReturnData"))
        XCTAssertFalse(retirement.contains("SecItemAdd"))
        XCTAssertFalse(retirement.contains("SecItemUpdate"))
        XCTAssertTrue(retirement.contains("kSecClassGenericPassword"))
        XCTAssertTrue(retirement.contains("openai-api-key"))
        XCTAssertFalse(client.contains("var apiKey: String"))
        XCTAssertTrue(client.contains("LiveChatTransport(configuration: configuration)"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("StyleMatchAI/AIProviderAdapters.swift").path))
        XCTAssertFalse(shop.contains("legacyApprovedClientConstruction"))
    }

    func testFailedDMSendRecoveryRetainsOneIdempotentDraftAndClassifiesTruthfully() throws {
        let parent = try XCTUnwrap(StyleFriendsOpaqueRouteReference("message_abcdefghijklmnopqrstuv"))
        let draft = StyleFriendsDMSendDraft(text: "Keep this exact text", clientMessageReference: "client_abcdefghijklmnopqrstuv", parentMessageReference: parent)
        let retryable = StyleFriendsDMFailedSendRecord(draft: draft, error: .networkUnavailable)
        XCTAssertEqual(retryable.draft, draft)
        XCTAssertEqual(retryable.id, draft.clientMessageReference)
        XCTAssertTrue(retryable.canRetry)
        XCTAssertEqual(retryable.draft.parentMessageReference, parent)
        XCTAssertEqual(StyleFriendsDMFailedSendDisposition.resolve(.signInRequired), .requiresReauthentication)
        XCTAssertTrue(StyleFriendsDMFailedSendRecord(draft: draft, error: .signInRequired).canRetryAfterReauthentication)
        XCTAssertEqual(StyleFriendsDMFailedSendDisposition.resolve(.contentNotAllowed), .terminal)
        XCTAssertEqual(StyleFriendsDMFailedSendDisposition.resolve(.conversationUnavailable), .terminal)
        XCTAssertEqual(StyleFriendsDMFailedSendDisposition.resolve(.idempotencyConflict), .terminal)

        let message = StyleFriendsDMMessage(
            messageReference: try XCTUnwrap(StyleFriendsOpaqueRouteReference("message_abcdefghijklmnopqrstuvwxyz")),
            clientMessageReference: draft.clientMessageReference,
            senderRole: "self",
            text: draft.text,
            deletedOrUnavailable: false,
            deliveryState: .sent,
            recipientVisible: true,
            createdAt: .now,
            updatedAt: .now,
            parentPreview: nil,
            reactionSummary: nil,
            attachment: nil
        )
        let sendOperation = StyleFriendsDMFailedDeliveryOperation(draft: draft, error: .networkUnavailable, phase: .send(photoAttachment: Data([1]), share: nil))
        XCTAssertFalse(sendOperation.phase.messageWasPersisted)
        XCTAssertTrue(sendOperation.canRetry)
        let uploadOperation = StyleFriendsDMFailedDeliveryOperation(draft: draft, error: .networkUnavailable, phase: .upload(message: message, jpeg: Data([1])))
        XCTAssertTrue(uploadOperation.phase.messageWasPersisted)
        XCTAssertEqual(uploadOperation.record.draft.parentMessageReference, parent)

        let source = try source("StyleMatchAI/StyleFriendsChatUI.swift")
        XCTAssertTrue(source.contains("case let .send(photoAttachment: attachmentPhoto, share: share)"))
        XCTAssertTrue(source.contains("case let .upload(message, jpeg)"))
        XCTAssertTrue(source.contains("case let .associate(message, attachment)"))
        XCTAssertFalse(source.contains("uploadAndAssociateAttachment"))
        XCTAssertTrue(source.contains("associatePreparedShareAttachment"))
        XCTAssertTrue(source.contains("failedSend = nil"))
        XCTAssertTrue(source.contains("It does not delete a sent Style Friends message."))
        XCTAssertFalse(source.contains("deleteOwnMessage(record"))
    }

    func testPremiumComposerKeepsReplyAttachmentAndCurrentProfileRefreshBounded() throws {
        let source = try source("StyleMatchAI/StyleFriendsChatUI.swift")
        XCTAssertTrue(source.contains("Text(\"Replying to \\(target.senderDisplayName)\")"))
        XCTAssertTrue(source.contains("accessibilityLabel(\"Cancel reply\")"))
        XCTAssertTrue(source.contains("Text(\"Photo attached\")"))
        XCTAssertTrue(source.contains("attachmentThumbnail(data: pendingAttachmentPhoto)"))
        XCTAssertTrue(source.contains("pendingAttachmentPhoto != nil"))
        XCTAssertTrue(source.contains(".layoutPriority(2)"))
        XCTAssertTrue(source.contains(".onChange(of: conversation)"))
        XCTAssertTrue(source.contains("Worker-projected public Style"))
        XCTAssertFalse(source.contains("Photo ready to send"))
    }

    func testDMAttachmentTransportUsesBoundedJPEGAndStageOnlyDiagnostics() throws {
        let directMessages = try source("StyleMatchAI/StyleFriendsDirectMessages.swift")
        let chat = try source("StyleMatchAI/StyleFriendsChatUI.swift")

        XCTAssertTrue(directMessages.contains("enum StyleFriendsDMAttachmentDiagnostics"))
        XCTAssertTrue(directMessages.contains("CLIENT_SIZE_REJECTED"))
        XCTAssertTrue(directMessages.contains("UPLOAD_HTTP_STATUS"))
        XCTAssertTrue(directMessages.contains("CONFIRMED_BY_201"))
        XCTAssertTrue(chat.contains("enum StyleFriendsDMAttachmentPhotoPreparation"))
        XCTAssertTrue(chat.contains("static let maximumUploadBytes = 5 * 1024 * 1024"))
        XCTAssertTrue(chat.contains("normalizedJPEG(from: data)"))
        XCTAssertTrue(chat.contains("PHOTO_NORMALIZATION"))
        XCTAssertTrue(chat.contains(".fixedSize(horizontal: true, vertical: false)"))
        XCTAssertTrue(chat.contains(".frame(width: 64).frame(minHeight: 44)"))
        XCTAssertFalse(directMessages.contains("attachmentReference: String"))
    }

    func testBuild18045OperationJournalUsesDeviceOnlyKeychainQueriesAndNoPrivatePayloadFields() throws {
        let keychain = CapturingOperationKeychain(), journal = StyleFriendsDMOperationJournal(keychain: keychain)
        let account = "account-private-value", environment = "owner-beta-private-value", conversation = "conversation-private-value"
        let accountEnvironment = try journal.accountEnvironmentTag(account: account, environment: environment)
        let scope = try journal.scopeTag(account: account, environment: environment, conversation: conversation)
        let fingerprint = try journal.payloadFingerprint(type: .text, immutablePayload: Data("private message body".utf8))
        let record = try journal.create(accountEnvironmentTag: accountEnvironment, scopeTag: scope, operationType: .text, payloadFingerprint: fingerprint)
        _ = try journal.transition(operationID: record.operationID, expectedScopeTag: scope, to: .unknown, opaqueServerReference: "opaque-server-issued-reference")
        let data = try XCTUnwrap(keychain.journalData())
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["schema", "operationID", "accountEnvironmentTag", "scopeTag", "operationType", "payloadFingerprint", "phase", "createdAt", "updatedAt", "expiresAt", "reconciliationCount", "retryCount", "opaqueServerReference"])
        XCTAssertEqual(object["schema"] as? Int, 1)
        XCTAssertEqual(object["operationType"] as? String, "text")
        XCTAssertEqual(object["phase"] as? String, "unknown")
        XCTAssertEqual(object["opaqueServerReference"] as? String, "opaque-server-issued-reference")
        let serialized = try XCTUnwrap(String(data: data, encoding: .utf8))
        for prohibited in [account, environment, conversation, "private message body", "token-value", "photo-bytes", "https://private.example/image"] {
            XCTAssertFalse(serialized.contains(prohibited), "Journal encoded prohibited private material.")
        }
        let recordQuery = try XCTUnwrap(keychain.additions.first { ($0[kSecAttrService as String] as? String)?.contains(".operation.v1") == true })
        XCTAssertEqual(recordQuery[kSecAttrSynchronizable as String] as? Bool, false)
        XCTAssertEqual(
            recordQuery[kSecAttrAccessible as String] as? String,
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
        )
        XCTAssertNil(recordQuery[kSecAttrAccessGroup as String], "The operation journal must remain in the app-default Keychain boundary.")
    }

    func testExpiredUnknownOperationRemainsRecoveryLockedAndAccountIsolated() throws {
        let journal = StyleFriendsDMOperationJournal(keychain: CapturingOperationKeychain())
        let tag = try journal.accountEnvironmentTag(account: "synthetic-a", environment: "staging")
        let scope = try journal.scopeTag(account: "synthetic-a", environment: "staging", conversation: "synthetic-c")
        let fingerprint = try journal.payloadFingerprint(type: .text, immutablePayload: Data([1]))
        let now = Date().addingTimeInterval(-120)
        let record = try journal.create(accountEnvironmentTag: tag, scopeTag: scope, operationType: .text, payloadFingerprint: fingerprint, now: now, ttl: 60)
        _ = try journal.transition(operationID: record.operationID, expectedScopeTag: scope, to: .unknown, now: now)
        XCTAssertEqual(try journal.unresolved(accountEnvironmentTag: tag).map(\.operationID), [record.operationID])
        XCTAssertNotNil(try journal.load(operationID: record.operationID, expectedScopeTag: scope))
        XCTAssertTrue(try journal.unresolved(accountEnvironmentTag: journal.accountEnvironmentTag(account: "synthetic-b", environment: "staging")).isEmpty)
    }

    func testBuild18045OperationProtocolPersistsBeforeNetworkAndFailsClosed() throws {
        let keychain = CapturingOperationKeychain(), journal = StyleFriendsDMOperationJournal(keychain: keychain)
        let tag = try journal.accountEnvironmentTag(account: "a", environment: "e")
        let scope = try journal.scopeTag(account: "a", environment: "e", conversation: "c")
        let fingerprint = try journal.payloadFingerprint(type: .text, immutablePayload: Data("payload".utf8))
        var networkContexts: [StyleFriendsDMOperationContext] = []
        _ = try journal.persistBeforeNetwork(accountEnvironmentTag: tag, scopeTag: scope, operationType: .text, payloadFingerprint: fingerprint) { context in
            XCTAssertNotNil(keychain.journalData(), "Persistence must complete before the first network call.")
            networkContexts.append(context)
        }
        XCTAssertEqual(networkContexts.count, 1)
        XCTAssertEqual(networkContexts[0].protocolVersion, 1)
        XCTAssertEqual(networkContexts[0].operationType, .text)
        XCTAssertEqual(networkContexts[0].scopeTag, scope)
        XCTAssertNil(StyleFriendsDMSendDraft(text: "legacy", clientMessageReference: "legacy-reference", parentMessageReference: nil).operationID, "Legacy headerless sends must carry no Build 18045 context.")
        XCTAssertEqual(StyleFriendsDMSendDraft(text: "new", clientMessageReference: "new-reference", parentMessageReference: nil, operationID: networkContexts[0].operationID, operationProtocolVersion: networkContexts[0].protocolVersion, operationScopeTag: networkContexts[0].scopeTag, operationType: networkContexts[0].operationType).operationID, networkContexts[0].operationID)

        let failing = CapturingOperationKeychain()
        let failingJournal = StyleFriendsDMOperationJournal(keychain: failing)
        _ = try failingJournal.accountEnvironmentTag(account: "a", environment: "e")
        failing.failOperationAdds = true
        var calls = 0
        XCTAssertThrowsError(try failingJournal.persistBeforeNetwork(accountEnvironmentTag: tag, scopeTag: scope, operationType: .text, payloadFingerprint: fingerprint) { _ in calls += 1 })
        XCTAssertEqual(calls, 0, "Persistence failure must make zero network calls.")
    }

    func testBuild18045RecoveryIsStatusOnlyDeduplicatedAndScopeSafe() async throws {
        let keychain = CapturingOperationKeychain(), journal = StyleFriendsDMOperationJournal(keychain: keychain)
        let accountEnvironment = try journal.accountEnvironmentTag(account: "account", environment: "environment")
        let otherEnvironment = try journal.accountEnvironmentTag(account: "other", environment: "environment")
        let scope = try journal.scopeTag(account: "account", environment: "environment", conversation: "private-conversation")
        let fingerprint = try journal.payloadFingerprint(type: .text, immutablePayload: Data("payload".utf8))
        let committed = try journal.create(accountEnvironmentTag: accountEnvironment, scopeTag: scope, operationType: .text, payloadFingerprint: fingerprint)
        let pending = try journal.transition(operationID: committed.operationID, expectedScopeTag: scope, to: .submitted)
        let other = try journal.create(accountEnvironmentTag: otherEnvironment, scopeTag: scope, operationType: .text, payloadFingerprint: fingerprint)
        _ = try journal.transition(operationID: other.operationID, expectedScopeTag: scope, to: .submitted)
        let service = OperationStatusSpy(outcomes: [pending.operationID: .committed])
        let coordinator = await MainActor.run { StyleFriendsDMOperationRecoveryCoordinator(journal: journal) }
        async let first = coordinator.reconcile(accountEnvironmentTag: accountEnvironment, service: service)
        async let second = coordinator.reconcile(accountEnvironmentTag: accountEnvironment, service: service)
        let results = await [first, second]
        XCTAssertEqual(results.flatMap { $0 }.filter { if case .committed = $0 { return true }; return false }.count, 1)
        let observedCallCount = await service.callCount()
        XCTAssertEqual(observedCallCount, 1, "Concurrent triggers must issue one status-only request.")
        XCTAssertNil(try journal.load(operationID: pending.operationID, expectedScopeTag: scope))
        XCTAssertNotNil(try journal.load(operationID: other.operationID, expectedScopeTag: scope), "Another account/environment scope must not be reconciled.")
        let data = try XCTUnwrap(keychain.journalData())
        XCTAssertFalse(try XCTUnwrap(String(data: data, encoding: .utf8)).contains("private-conversation"))
    }

    func testSocialAndSupportSurfacesUseTheSharedThemePrimitives() throws {
        let friends = try source("StyleMatchAI/StyleFriendsView.swift")
        let conversations = try source("StyleMatchAI/StyleFriendsChatUI.swift")
        let notifications = try source("StyleMatchAI/StyleFriendsNotifications.swift")
        let support = try source("StyleMatchAI/StyleMatchSupportCenter.swift")

        XCTAssertTrue(friends.contains(".appScreenBackground(.profile)"))
        XCTAssertTrue(conversations.contains(".appScreenBackground(.profile)"))
        XCTAssertTrue(conversations.contains(".appCard(.profile"))
        XCTAssertTrue(notifications.contains(".scrollContentBackground(.hidden)"))
        XCTAssertTrue(notifications.contains(".appScreenBackground(.profile)"))
        XCTAssertTrue(support.contains(".appScreenBackground(.profile)"))
        XCTAssertTrue(support.contains(".appCard(.profile"))
    }

    func testStyleFriendsNavigationUsesAnAccessiblePremiumSheetWithoutChangingDestinations() throws {
        let source = try source("StyleMatchAI/StyleFriendsView.swift")

        XCTAssertTrue(source.contains("StyleFriendsSectionNavigationTrigger"))
        XCTAssertTrue(source.contains("StyleFriendsSectionNavigationSheet"))
        XCTAssertTrue(source.contains("dynamicTypeSize.isAccessibilitySize ? [.large] : [.height(382), .large]"))
        XCTAssertTrue(source.contains("Style Friends navigation"))
        XCTAssertTrue(source.contains("dynamicTypeSize.isAccessibilitySize ? 2 : 1"))
        XCTAssertTrue(source.contains(".frame(maxWidth: .infinity, minHeight: 52"))
        XCTAssertTrue(source.contains(".theme.palette(for: .profile)"))
        XCTAssertTrue(source.contains("palette.accent.opacity(0.15)"))
        XCTAssertTrue(source.contains("palette.accent.opacity(0.28)"))
        XCTAssertTrue(source.contains("selection = item"))
        XCTAssertTrue(source.contains("dismiss()"))
        XCTAssertFalse(source.contains("Picker(\"Style Friends section\""))

        for destination in ["Friends Feed", "Friends", "Friend Requests", "My Shared Looks", "Profile"] {
            XCTAssertTrue(source.contains(destination), "The Style Friends navigation must retain \(destination).")
        }
    }

    private func source(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    func testChatComposerExposesSavedScanAndSavedScoreThroughCanonicalAuthority() throws {
        let source = try source("StyleMatchAI/StyleFriendsChatUI.swift")

        XCTAssertTrue(source.contains("Button(\"Saved Scan\")"))
        XCTAssertTrue(source.contains("Button(\"Saved Score\")"))
        XCTAssertTrue(source.contains("StyleFriendsDMShareEligibilityAuthority.Selection"))
        XCTAssertTrue(source.contains("StyleFriendsDMShareEligibilityAuthority()"))
        XCTAssertFalse(source.contains("private final class StyleFriendsChatSavedShareAuthority"))
    }

    @MainActor func testSavedScanWithoutLocalImageSharesSanitizedSnapshot() throws {
        let snapshot = try XCTUnwrap(StyleFriendsDMAttachmentSnapshot(title: "Dinner", occasion: "evening", score: 88, summary: "Navy blazer and dark denim"))
        let share = StyleFriendsDMPreparedShare(kind: .scanSnapshot, snapshot: snapshot, imagePreview: nil, clientShareReference: "share_scan_1")
        XCTAssertEqual(share.kind, .scanSnapshot); XCTAssertNil(share.imagePreview)
        XCTAssertFalse(String(describing: share).contains("/"))
    }

    @MainActor func testSavedScanWithImageUploadsAndAssociatesOnce() throws {
        let snapshot = try XCTUnwrap(StyleFriendsDMAttachmentSnapshot(title: "Weekend", occasion: nil, score: 91, summary: "Clean casual layers"))
        let share = StyleFriendsDMPreparedShare(kind: .scanSnapshot, snapshot: snapshot, imagePreview: Data([1, 2, 3]), clientShareReference: "share_scan_2")
        XCTAssertEqual(share.kind, .scanSnapshot); XCTAssertEqual(share.imagePreview?.count, 3)
        XCTAssertEqual(share.snapshot.title, "Weekend")
    }

    @MainActor func testScoreSharePreservesTypedScoreKind() throws {
        let snapshot = try XCTUnwrap(StyleFriendsDMAttachmentSnapshot(title: "Scorecard", occasion: "work", score: 94, summary: "Strong proportion and contrast"))
        let attachment = StyleFriendsDMAttachment(attachmentReference: try XCTUnwrap(StyleFriendsOpaqueRouteReference("attachment_score_1")), schemaVersion: 1, kind: .scoreSnapshot, snapshot: snapshot, imageAttachmentReference: nil, state: "associated")
        XCTAssertEqual(attachment.kind, .scoreSnapshot); XCTAssertNotEqual(attachment.kind, .scanSnapshot)
        let presentation = StyleFriendsDMPresentationMapper.message(.init(messageReference: try XCTUnwrap(StyleFriendsOpaqueRouteReference("message_score_1")), clientMessageReference: "m", senderRole: "friend", text: nil, deletedOrUnavailable: false, deliveryState: .sent, recipientVisible: true, createdAt: Date(), updatedAt: Date(), parentPreview: nil, reactionSummary: nil, attachment: attachment), selfDisplayName: "You", friendDisplayName: "Friend")
        XCTAssertEqual(presentation.sharedOutfit?.contextLabel, "Score when shared")
    }

    @MainActor func testOutfitSharePreservesTypedOutfitKind() throws {
        let snapshot = try XCTUnwrap(StyleFriendsDMAttachmentSnapshot(title: "Look", occasion: "casual", score: nil, summary: "Relaxed layers"))
        let attachment = StyleFriendsDMAttachment(attachmentReference: try XCTUnwrap(StyleFriendsOpaqueRouteReference("attachment_outfit_1")), schemaVersion: 1, kind: .outfitSnapshot, snapshot: snapshot, imageAttachmentReference: nil, state: "associated")
        XCTAssertEqual(attachment.kind, .outfitSnapshot); XCTAssertNotEqual(attachment.kind, .scoreSnapshot)
        let presentation = StyleFriendsDMPresentationMapper.message(.init(messageReference: try XCTUnwrap(StyleFriendsOpaqueRouteReference("message_outfit_1")), clientMessageReference: "m", senderRole: "friend", text: nil, deletedOrUnavailable: false, deliveryState: .sent, recipientVisible: true, createdAt: Date(), updatedAt: Date(), parentPreview: nil, reactionSummary: nil, attachment: attachment), selfDisplayName: "You", friendDisplayName: "Friend")
        XCTAssertEqual(presentation.sharedOutfit?.contextLabel, "Outfit when shared")
    }

    @MainActor func testLegacyPlaceholderAttachmentRemainsCompatible() throws {
        let message = StyleFriendsDMMessage(messageReference: try XCTUnwrap(StyleFriendsOpaqueRouteReference("legacy_message_1")), clientMessageReference: "legacy", senderRole: "friend", text: "Photo — Private photo attachment", deletedOrUnavailable: false, deliveryState: .sent, recipientVisible: true, createdAt: Date(), updatedAt: Date(), parentPreview: nil, reactionSummary: nil, attachment: nil)
        XCTAssertNil(message.attachment)
        XCTAssertFalse(message.deletedOrUnavailable)
    }
    @MainActor func testPhotoCoordinatorReturnsConfirmedSuccessOnlyAfterAssociation() async throws {
        let spy = AttachmentLifecycleSpy()
        let coordinator = StyleFriendsAttachmentSendCoordinator(service: spy, conversation: try XCTUnwrap(.init("conversation_test")), journal: StyleFriendsDMOperationJournal(keychain: CapturingOperationKeychain()), accountScope: { ("synthetic-a", "staging") })
        let result = await coordinator.sendNewPhoto(draft: .init(text: "caption", clientMessageReference: "photo", parentMessageReference: nil), jpeg: Data([1]))
        XCTAssertEqual(result, StyleFriendsAttachmentDeliveryResult.confirmedAssociationSuccess)
        XCTAssertEqual(coordinator.state, .sent)
        XCTAssertEqual(spy.sends, 1); XCTAssertEqual(spy.uploads, 1); XCTAssertEqual(spy.associations, 1)
    }

    func testPhotoSubmissionCleanupIsSnapshotConditionalAndPrivacySafe() throws {
        let source = try source("StyleMatchAI/StyleFriendsChatUI.swift")
        XCTAssertTrue(source.contains("clearPhotoSubmissionIfUnchanged(snapshot)"))
        XCTAssertTrue(source.contains("if result == .confirmedAssociationSuccess"))
        XCTAssertFalse(source.contains("clearPhotoSubmissionIfUnchanged(snapshot)\n                return"))
    }

    @MainActor func testPhotoCoordinatorReturnsConfirmedFailureAndRetainsPayload() async throws {
        let spy = AttachmentLifecycleSpy()
        spy.uploadError = StyleFriendsAttachmentOutcomeError.confirmedFailure
        let coordinator = StyleFriendsAttachmentSendCoordinator(
            service: spy,
            conversation: try XCTUnwrap(.init("conversation_test")),
            journal: StyleFriendsDMOperationJournal(keychain: CapturingOperationKeychain()),
            accountScope: { ("synthetic-a", "staging") }
        )

        let result = await coordinator.sendNewPhoto(
            draft: .init(text: "caption", clientMessageReference: "photo-failure", parentMessageReference: nil),
            jpeg: Data([2])
        )

        XCTAssertEqual(result, .confirmedFailure)
        XCTAssertEqual(coordinator.state, .failed("upload"))
        XCTAssertEqual(coordinator.activePhoto, Data([2]))
        XCTAssertEqual(spy.associations, 0)
    }

    @MainActor func testPhotoCoordinatorReturnsAmbiguousOutcomeWithoutClearingPayload() async throws {
        let spy = AttachmentLifecycleSpy()
        spy.associationError = StyleFriendsAttachmentOutcomeError.ambiguousOutcome
        let coordinator = StyleFriendsAttachmentSendCoordinator(
            service: spy,
            conversation: try XCTUnwrap(.init("conversation_test")),
            journal: StyleFriendsDMOperationJournal(keychain: CapturingOperationKeychain()),
            accountScope: { ("synthetic-a", "staging") }
        )

        let result = await coordinator.sendNewPhoto(
            draft: .init(text: "caption", clientMessageReference: "photo-ambiguous", parentMessageReference: nil),
            jpeg: Data([3])
        )

        XCTAssertEqual(result, .ambiguousOutcome)
        XCTAssertEqual(coordinator.state, .ambiguous)
        XCTAssertEqual(coordinator.activePhoto, Data([3]))
    }

    @MainActor func testPhotoAssociationResumesAfterServerConfirmsNotCommitted() async throws {
        let spy = AttachmentLifecycleSpy()
        spy.associationErrors = [StyleFriendsAttachmentOutcomeError.ambiguousOutcome]
        let coordinator = StyleFriendsAttachmentSendCoordinator(
            service: spy,
            conversation: try XCTUnwrap(.init("conversation_test")),
            journal: StyleFriendsDMOperationJournal(keychain: CapturingOperationKeychain()),
            accountScope: { ("synthetic-a", "staging") }
        )

        let initial = await coordinator.sendNewPhoto(
            draft: .init(text: "caption", clientMessageReference: "photo-resume", parentMessageReference: nil),
            jpeg: Data([4])
        )
        XCTAssertEqual(initial, .ambiguousOutcome)

        await coordinator.retryPhoto(statusAlreadyConfirmedNotCommitted: true)

        XCTAssertEqual(coordinator.state, .sent)
        XCTAssertEqual(spy.sends, 1)
        XCTAssertEqual(spy.uploads, 1)
        XCTAssertEqual(spy.associations, 2)
        XCTAssertEqual(spy.statuses, 0)
    }

    func testPhotoFailureCreatesReachableStatusFirstRecoveryUI() throws {
        let source = try source("StyleMatchAI/StyleFriendsChatUI.swift")
        XCTAssertTrue(source.contains("phase: .send(photoAttachment: attachmentPhoto, share: nil)"))
        XCTAssertTrue(source.contains("statusAlreadyConfirmedNotCommitted: statusConfirmedNotCommitted"))
        XCTAssertTrue(source.contains("clearComposerAfterConfirmedDelivery(record)"))
        XCTAssertTrue(source.contains("Delivery status is uncertain. Use Retry to check the server before resending."))
        XCTAssertTrue(source.contains("isSending = true\n        Task {\n            defer { isSending = false }"))
        XCTAssertTrue(source.contains("text: photoDraft.text"))
        XCTAssertTrue(source.contains("record.phase == .notCommitted"))
        XCTAssertTrue(source.contains("attachmentCoordinator.discardPhoto()"))
    }
    func testPreparedAttachmentRequestsCarryCompleteOperationHeaders() throws {
        let source = try source("StyleMatchAI/StyleFriendsDirectMessages.swift")
        XCTAssertTrue(source.contains(
            "\"X-StyleMatch-DM-Operation-Type\": operation.operationType.rawValue"
        ))
    }

    func testOwnerBetaOperationDiagnosticsAreContentFreeAndClassifyAllMessagingFlows() throws {
        let source = try source("StyleMatchAI/StyleFriendsDirectMessages.swift")
        XCTAssertTrue(source.contains("enum StyleFriendsDMOperationDiagnostics"))
        XCTAssertTrue(source.contains("var build = \"UNKNOWN\""))
        XCTAssertTrue(source.contains("var operation = \"NOT_STARTED\""))
        XCTAssertTrue(source.contains("var reconciliation = \"NOT_STARTED\""))
        XCTAssertTrue(source.contains("text_message"))
        XCTAssertTrue(source.contains("photo_upload"))
        XCTAssertTrue(source.contains("score_or_scan_share"))
        XCTAssertTrue(source.contains("reconciliation: (result as? StyleFriendsDMOperationStatus)?.outcome.rawValue"))
        XCTAssertTrue(source.contains("#if DEBUG || OWNER_BETA"))
        XCTAssertFalse(source.contains("message text"))
        XCTAssertFalse(source.contains("full URL"))
        XCTAssertFalse(source.contains("response body"))
    }

    @MainActor func testMessageLoadingPublishesNewestPageBeforeOlderHistoryFinishes() async throws {
        let service = PagedMessagesFake()
        let controller = StyleFriendsDMChatActionController(service: service)
        let conversation = try XCTUnwrap(StyleFriendsOpaqueRouteReference("conversation_progressive"))
        var snapshots: [[String]] = []
        let observation = controller.$messages.dropFirst().sink { snapshots.append($0.map(\.id)) }

        await controller.loadMessages(conversation: conversation)

        withExtendedLifetime(observation) {
            XCTAssertEqual(snapshots.first, ["m1", "m2"])
            XCTAssertEqual(snapshots.last, ["m1", "m2", "m3"])
        }
    }

    @MainActor func testMessageLoadingDrainsOlderPagesAndDeduplicates() async throws {
        let service = PagedMessagesFake()
        let controller = StyleFriendsDMChatActionController(service: service)
        let conversation = try XCTUnwrap(StyleFriendsOpaqueRouteReference("conversation_paged"))
        await controller.loadMessages(conversation: conversation)
        XCTAssertEqual(controller.messages.map(\.id), ["m1", "m2", "m3"])
        XCTAssertEqual(service.cursors, [nil, "cursor-1", "cursor-2"])
    }

    @MainActor func testIdenticalForegroundRefreshDoesNotRepublishMessageTimeline() async throws {
        let service = PagedMessagesFake()
        let controller = StyleFriendsDMChatActionController(service: service)
        let conversation = try XCTUnwrap(StyleFriendsOpaqueRouteReference("conversation_stable_refresh"))
        await controller.loadMessages(conversation: conversation)
        var publications = 0
        let observation = controller.$messages.dropFirst().sink { _ in publications += 1 }
        await controller.loadMessages(conversation: conversation)
        withExtendedLifetime(observation) {
            XCTAssertEqual(publications, 0)
            XCTAssertEqual(service.cursors, [nil, "cursor-1", "cursor-2", nil])
        }
    }

    func testMessageLoadingUsesGenerationGuardAndForegroundRefreshLoop() throws {
        let direct = try source("StyleMatchAI/StyleFriendsDirectMessages.swift")
        let ui = try source("StyleMatchAI/StyleFriendsChatUI.swift")
        XCTAssertTrue(direct.contains("private var messageLoadGeneration = 0"))
        XCTAssertTrue(direct.contains("guard generation == messageLoadGeneration else { return }"))
        XCTAssertTrue(ui.contains("private func refreshLoop() async"))
        XCTAssertTrue(ui.contains("scenePhase == .active"))
        XCTAssertTrue(ui.contains("Task.sleep(for: .seconds(20))"))
    }

    func testNotificationRegistrationIsAccountScopedAcrossSwitches() throws {
        let source = try source("StyleMatchAI/StyleFriendsNotifications.swift")
        XCTAssertTrue(source.contains("registeredSession = session"))
        XCTAssertTrue(source.contains("removeTokens(session: session)"))
        XCTAssertTrue(source.contains("guard registrationSession != nil else"))
        XCTAssertFalse(source.contains("UserDefaults.standard.set(deviceToken"))
    }

    func testFriendChatRefreshIsLifecycleBoundAndReconcilesAttachments() throws {
        let source = try source("StyleMatchAI/StyleFriendsChatUI.swift")
        XCTAssertTrue(source.contains(".task(id: conversation.conversationReference.value)"))
        XCTAssertTrue(source.contains("await controller.loadMessages(conversation: conversation.conversationReference)"))
        XCTAssertTrue(source.contains("await controller.loadConversations()"))
        XCTAssertTrue(source.contains("await reconcileUnresolvedOperations()"))
    }

    func testVisibleConversationRemainsMountedDuringRefreshAndFailure() throws {
        let source = try source("StyleMatchAI/StyleFriendsChatUI.swift")
        XCTAssertTrue(source.contains("if controller.loadingMessages && controller.messages.isEmpty { return .loading }"))
        XCTAssertTrue(source.contains("if controller.lastError != nil && controller.messages.isEmpty { return .recoverableError }"))
        XCTAssertTrue(source.contains("messageTimeline(initialScrollID: preferredInitialScrollID)"))
        XCTAssertTrue(source.contains("ScrollViewReader"))
        XCTAssertTrue(source.contains("anchor: initialMessageReference == nil ? .bottom : .center"))
        XCTAssertFalse(source.contains("if controller.loadingMessages { return .loading }") )
    }

    func testReceivedMessagesShowReceivedStatusWithoutInlineReplyLabel() throws {
        let source = try source("StyleMatchAI/StyleFriendsChatUI.swift")
        XCTAssertTrue(source.contains("Text(\"Received\")"))
        XCTAssertTrue(source.contains(".accessibilityLabel(\"Received message\")"))
        XCTAssertFalse(source.contains("if message.sender != .selfUser { Button(\"Reply\", action: onReply)"))
        XCTAssertTrue(source.contains(".contextMenu { Button(\"Reply\", action: onReply)"))
        XCTAssertTrue(source.contains(".accessibilityAction(named: \"Reply\", onReply)"))
    }

    func testDMReopenCacheIsBoundedMemoryOnlyAndClearedAcrossAccountChanges() throws {
        let direct = try source("StyleMatchAI/StyleFriendsDirectMessages.swift")
        let ui = try source("StyleMatchAI/StyleFriendsChatUI.swift")
        XCTAssertTrue(direct.contains("enum StyleFriendsDMSessionMessageCache"))
        XCTAssertTrue(direct.contains("private static let maximumConversationCount = 12"))
        XCTAssertTrue(direct.contains("private static let maximumMessagesPerConversation = 80"))
        XCTAssertTrue(direct.contains("session.accountID ?? session.appleSubject"))
        XCTAssertTrue(direct.contains("StyleFriendsDMSessionMessageCache.store(messages, for: conversation)"))
        XCTAssertTrue(ui.contains("StyleFriendsDMSessionMessageCache.clearAll()"))
        XCTAssertFalse(direct.contains("UserDefaults.standard.set(messages"))
    }

    func testGeneralStylistChatRequestUsesWorkerV2ContextEnvelope() throws {
        let context = ChatContext(profileSummary: "profile", recentOutfits: "outfits", activeScan: "scan", historicalOutfits: "history", weatherConstraint: "weather", stylePreferences: .init(preferredColors: ["black"], avoidedColors: [], preferredBrands: [], styleLabels: [], preferredFit: nil))
        let request = ChatRequest(messages: [.init(role: "user", content: "What do you think")], context: context, stream: true)
        let data = try JSONEncoder().encode(request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["contract_version"] as? Int, 2)
        let wire = try XCTUnwrap(object["context"] as? [String: Any])
        XCTAssertTrue(Set(wire.keys).isSubset(of: ["stylePreferences", "stylist_context", "authoritativeScan", "profileSummary", "recentOutfits", "scoreBreakdown", "activeScan", "historicalOutfits"]))
        XCTAssertNil(wire["weatherConstraint"])
        XCTAssertNil(wire["stylistContextSnapshot"])
        XCTAssertNil(wire["productContext"])
    }

    @MainActor private final class PagedMessagesFake: StyleFriendsDirectMessageServing {
        var conversationFetch: ((String?) async throws -> StyleFriendsDMCursorPage<StyleFriendsDMConversation>)?
        var cursors: [String?] = []
        private func message(_ id: String, _ offset: TimeInterval) -> StyleFriendsDMMessage {
            let ref = StyleFriendsOpaqueRouteReference(id)!
            let date = Date(timeIntervalSince1970: 1_000 + offset)
            return .init(messageReference: ref, clientMessageReference: "client_\(id)", senderRole: "self", text: id, deletedOrUnavailable: false, deliveryState: .sent, recipientVisible: true, createdAt: date, updatedAt: date, parentPreview: nil, reactionSummary: nil, attachment: nil)
        }
        func messages(conversation: StyleFriendsOpaqueRouteReference, cursor: String?) async throws -> StyleFriendsDMCursorPage<StyleFriendsDMMessage> {
            cursors.append(cursor)
            switch cursor { case nil: return .init(items: [message("m1", 1), message("m2", 2)], nextCursor: "cursor-1"); case "cursor-1": return .init(items: [message("m2", 2), message("m3", 3)], nextCursor: "cursor-2"); default: return .init(items: [], nextCursor: nil) }
        }
        func terms() async throws -> StyleFriendsDMTermsState { throw StyleFriendsDMError.dmUnavailable }
        func acceptTerms(version: String) async throws { throw StyleFriendsDMError.dmUnavailable }
        func conversations(cursor: String?) async throws -> StyleFriendsDMCursorPage<StyleFriendsDMConversation> { guard let conversationFetch else { throw StyleFriendsDMError.dmUnavailable }; return try await conversationFetch(cursor) }
        func createConversation(friend: StyleFriendAccountReference) async throws -> StyleFriendsDMConversation { throw StyleFriendsDMError.dmUnavailable }
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
        func attachmentImage(conversation: StyleFriendsOpaqueRouteReference, attachment: StyleFriendsOpaqueRouteReference) async throws -> Data { throw StyleFriendsDMError.dmUnavailable }
        func uploadAttachmentPhoto(conversation: StyleFriendsOpaqueRouteReference, jpeg: Data, operation: StyleFriendsDMOperationContext?) async throws -> StyleFriendsDMAttachment { throw StyleFriendsDMError.dmUnavailable }
    }

}

final class StylePreferencesPersistenceContractTests: XCTestCase {
    private func source() throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("StyleMatchAI/StylistChat/StylistChatView.swift"), encoding: .utf8)
    }
    func testDoneSavesAndRelaunchRestoresAccountScopedPreferences() throws { let s = try source(); XCTAssertTrue(s.contains("saveRememberedStylePreferences()")); XCTAssertTrue(s.contains("loadRememberedStylePreferences()")); XCTAssertTrue(s.contains("rememberedStylePreferences")) }
    func testSuccessfulAndFailedSendsDoNotClearRememberedPreferences() throws { let s = try source(); XCTAssertTrue(s.contains("if accepted { clearTransientFactSelections() }")); XCTAssertFalse(s.contains("if accepted { clearFactSelections() }")) }
    func testDeselectionAndClearPersistEmptySelection() throws { let s = try source(); XCTAssertTrue(s.contains("clearFactSelections()")); XCTAssertTrue(s.contains("saveRememberedStylePreferences()")) }
    func testAccountScopedKeyPreventsCrossAccountExposure() throws { let s = try source(); XCTAssertTrue(s.contains("PersonalStylistStorage.activeUserID()")); XCTAssertTrue(s.contains("PersonalStylistStorage.scopedKey")) }
    func testPermissionRevocationAndProfileRemovalGateTransmission() throws { let s = try source(); XCTAssertTrue(s.contains("routeMissingScopedConsentIfNeeded")); XCTAssertTrue(s.contains("reResolveStylePreferenceSelection")); XCTAssertTrue(s.contains("currentProfile")) }
    func testTransientAttachmentsRemainSeparateFromRememberedPreferences() throws { let s = try source(); XCTAssertTrue(s.contains("clearTransientFactSelections()")); XCTAssertTrue(s.contains("clearVisionImage()")); XCTAssertTrue(s.contains("selectedStylePreferenceSelection")) }
}
