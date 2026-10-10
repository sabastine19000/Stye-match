import XCTest
@testable import StyleMatchPro

final class StyleFriendsDMTransportRegressionTests: XCTestCase {
    private let conversation = StyleFriendsOpaqueRouteReference("synthetic_conversation")!
    private let clientReference = "synthetic-client-reference-123456"
    private var account: StyleMatchAccountSession?
    private var invalidations = 0

    override func setUp() {
        super.setUp()
        account = .init(token: "synthetic-session-a", expiresAt: Date().addingTimeInterval(600))
        invalidations = 0
        DMRegressionURLProtocol.handler = nil
        DMRegressionURLProtocol.requests = []
    }

    private func service() throws -> StyleFriendsHTTPDirectMessageService {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DMRegressionURLProtocol.self]
        return .init(configuration: try XCTUnwrap(.init(baseURL: URL(string: "https://\(AppBackendConfiguration.approvedFriendsStagingAPIHost)")!)), session: URLSession(configuration: config), accountSession: { self.account }, invalidateAccountSession: { self.invalidations += 1; self.account = nil })
    }

    private func operation() -> StyleFriendsDMOperationContext {
        .init(record: .init(schema: 1, operationID: UUID(), accountEnvironmentTag: "synthetic-account", scopeTag: "synthetic-scope", operationType: .text, payloadFingerprint: "synthetic-fingerprint", phase: .submitted, createdAt: Date(), updatedAt: Date(), expiresAt: Date().addingTimeInterval(600), reconciliationCount: 0, retryCount: 0, opaqueServerReference: nil))
    }

    private func draft(_ op: StyleFriendsDMOperationContext) -> StyleFriendsDMSendDraft {
        .init(text: "Synthetic test only", clientMessageReference: clientReference, parentMessageReference: nil, operationID: op.operationID, operationProtocolVersion: 1, operationScopeTag: op.scopeTag, operationType: op.operationType)
    }

    private var messageJSON: String {
        """
        {"message":{"message_ref":"synthetic_message","client_message_ref":"synthetic-client-reference-123456","sender_role":"self","text":"Synthetic test only","deleted_or_unavailable":false,"delivery_status":"sent","recipient_visible":true,"created_at":"2026-08-31T23:29:30.252Z","updated_at":"2026-08-31T23:29:30.252Z"}}
        """
    }

    func testInitialTextUsesVersion100ContractAndDecodesFractionalDatesWithoutStatusCall() async throws {
        let svc = try service(), op = operation()
        DMRegressionURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/v1/friends/conversations/synthetic_conversation/messages")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-StyleMatch-DM-Operation-ID"), op.operationID.uuidString)
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-StyleMatch-DM-Operation-Type"), "text")
            return (201, self.messageJSON)
        }
        let message = try await svc.send(conversation: conversation, draft: draft(op))
        XCTAssertTrue(message.recipientVisible)
        XCTAssertEqual(message.clientMessageReference, clientReference)
        XCTAssertEqual(DMRegressionURLProtocol.requests.count, 1)
    }

    func testLostAcknowledgementReconcilesExactOperationWithoutAnotherSend() async throws {
        let svc = try service(), op = operation()
        DMRegressionURLProtocol.handler = { request in
            if request.httpMethod == "POST" { throw URLError(.networkConnectionLost) }
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/v1/friends/direct-messages/operations/\(op.operationID.uuidString)")
            XCTAssertNil(request.httpBody)
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-StyleMatch-DM-Protocol-Version"), "1")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
            return (200, "{\"operation_id\":\"\(op.operationID)\",\"outcome\":\"committed\"}")
        }
        do { _ = try await svc.send(conversation: conversation, draft: draft(op)); XCTFail("Lost acknowledgement must throw") }
        catch { XCTAssertEqual(error as? StyleFriendsDMError, .networkUnavailable) }
        let status = try await svc.operationStatus(context: op)
        XCTAssertEqual(status.outcome, .committed)
        XCTAssertEqual(DMRegressionURLProtocol.requests.filter { $0.httpMethod == "POST" }.count, 1)
        XCTAssertEqual(StyleFriendsDMOperationDiagnostics.snapshot.httpStatus, "200")
        XCTAssertEqual(StyleFriendsDMOperationDiagnostics.snapshot.reconciliation, "committed")
    }

    func testUnavailableLookupNeverReturnsNotCommittedOrResends() async throws {
        let svc = try service(), op = operation()
        for status in [404, 429, 503] {
            DMRegressionURLProtocol.handler = { _ in (status, "{\"error\":\"dmUnavailable\"}") }
            do { _ = try await svc.operationStatus(context: op); XCTFail("Lookup error is not absence") }
            catch { XCTAssertNotNil(error as? StyleFriendsDMError) }
        }
        XCTAssertTrue(DMRegressionURLProtocol.requests.allSatisfy { $0.httpMethod == "GET" })
    }

    func testUnknownAndMismatchedStatusAreNotCommitAuthority() async throws {
        let svc = try service(), op = operation()
        DMRegressionURLProtocol.handler = { _ in (200, "{\"operation_id\":\"\(op.operationID)\",\"outcome\":\"unknown\"}") }
        let unknown = try await svc.operationStatus(context: op)
        XCTAssertEqual(unknown.outcome, .unknown)
        DMRegressionURLProtocol.handler = { _ in (200, "{\"operation_id\":\"\(UUID())\",\"outcome\":\"committed\"}") }
        do { _ = try await svc.operationStatus(context: op); XCTFail("Foreign operation must fail") }
        catch { XCTAssertEqual(error as? StyleFriendsDMError, .invalidResponse) }
    }

    func testMissingSessionFailsBeforeNetworkAndCurrent401InvalidatesOnlyCurrentSession() async throws {
        let svc = try service()
        account = nil
        do { _ = try await svc.terms(); XCTFail("Session required") }
        catch { XCTAssertEqual(error as? StyleFriendsDMError, .signInRequired) }
        XCTAssertTrue(DMRegressionURLProtocol.requests.isEmpty)
        account = .init(token: "synthetic-session-a", expiresAt: Date().addingTimeInterval(600))
        DMRegressionURLProtocol.handler = { _ in (401, "{\"error\":\"authenticationRequired\"}") }
        do { _ = try await svc.terms(); XCTFail("401 must fail") }
        catch { XCTAssertEqual(error as? StyleFriendsDMError, .signInRequired) }
        XCTAssertEqual(invalidations, 1)
    }

    func testAccountSwitchRejectsOldSuccessAndDoesNotDeleteNewSessionOnOld401() async throws {
        let svc = try service(), op = operation()
        for status in [200, 401] {
            account = .init(token: "synthetic-session-a", expiresAt: Date().addingTimeInterval(600))
            DMRegressionURLProtocol.handler = { _ in
                self.account = .init(token: "synthetic-session-b", expiresAt: Date().addingTimeInterval(600))
                return (status, "{\"operation_id\":\"\(op.operationID)\",\"outcome\":\"committed\"}")
            }
            do { _ = try await svc.operationStatus(context: op); XCTFail("Old session result must not escape") }
            catch { XCTAssertEqual(error as? StyleFriendsDMError, .signInRequired) }
            XCTAssertEqual(account?.token, "synthetic-session-b")
            XCTAssertEqual(invalidations, 0)
        }
    }
}

private final class DMRegressionURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, String))?
    static var requests: [URLRequest] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        do {
            let (status, json) = try XCTUnwrap(Self.handler)(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(json.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

extension StyleFriendsDMTransportRegressionTests {
    func testPhotoUploadFailureRemainsVisibleAfterSuccessfulBackgroundRead() async throws {
        let svc = try service()
        DMRegressionURLProtocol.handler = { _ in (503, "{\"error\":\"attachment_unavailable\"}") }
        do {
            _ = try await svc.uploadAttachmentPhoto(conversation: conversation, jpeg: Data([1]), operation: nil)
            XCTFail("503 must fail")
        } catch { XCTAssertEqual(error as? StyleFriendsDMError, .serviceUnavailable) }
        XCTAssertEqual(StyleFriendsDMOperationDiagnostics.snapshot.operation, "photo_upload")
        XCTAssertEqual(StyleFriendsDMOperationDiagnostics.snapshot.httpStatus, "503")
        StyleFriendsDMOperationDiagnostics.record(operation: "other", phase: "response", httpStatus: "204", serverCategory: "accepted")
        XCTAssertEqual(StyleFriendsDMOperationDiagnostics.snapshot.operation, "photo_upload")
        XCTAssertEqual(StyleFriendsDMOperationDiagnostics.snapshot.httpStatus, "503")
    }
}
