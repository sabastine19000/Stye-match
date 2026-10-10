import XCTest
@testable import StyleMatchPro

final class SupportConsentUXTests: XCTestCase {
    @MainActor
    func testSuccessfulSupportQuestionKeepsTranscriptAndClearsPendingRetryAuthority() async throws {
        let model = StyleMatchSupportCenterModel(service: SupportChatTestService(result: .success))
        let entryID = try XCTUnwrap(model.beginSupportQuestion("Hello"))

        await model.completeSupportQuestion("Hello", entryID: entryID)

        XCTAssertEqual(model.chatHistory.map(\.sender), [.customer, .assistant])
        XCTAssertEqual(model.chatHistory.map(\.text), ["Hello", "Hello! How can I assist you today?"])
        XCTAssertEqual(model.chatHistory.first?.delivery, .sent)
        XCTAssertNil(model.retryableMessageID)
        XCTAssertNil(model.pendingConsentMessage)
    }

    @MainActor
    func testRetryableFailureKeepsOneOutgoingTranscriptEntryForRetry() async throws {
        let model = StyleMatchSupportCenterModel(service: SupportChatTestService(result: .retryableFailure))
        let entryID = try XCTUnwrap(model.beginSupportQuestion("Can't sign in"))

        await model.completeSupportQuestion("Can't sign in", entryID: entryID)

        XCTAssertEqual(model.chatHistory.count, 1)
        XCTAssertEqual(model.chatHistory.first?.text, "Can't sign in")
        XCTAssertEqual(model.chatHistory.first?.delivery, .retryableFailure)
        XCTAssertEqual(model.retryableMessageID, entryID)
    }

    @MainActor
    func testConsentFailureKeepsQuestionUnsentAndRequiresExplicitRetry() async throws {
        let model = StyleMatchSupportCenterModel(service: SupportChatTestService(result: .consentRequired))
        let entryID = try XCTUnwrap(model.beginSupportQuestion("Hello"))

        await model.completeSupportQuestion("Hello", entryID: entryID)

        XCTAssertEqual(model.chatHistory.count, 1)
        XCTAssertEqual(model.chatHistory.first?.delivery, .consentRequired)
        XCTAssertEqual(model.pendingConsentMessage, "Hello")
        XCTAssertEqual(model.pendingConsentMessageID, entryID)
    }

    func testSupportConsentUsesExistingAccountScopedAuthorityAndCurrentVersion() throws {
        let support = try source("StyleMatchAI/StyleMatchSupportCenter.swift")
        let transport = try source("StyleMatchAI/StylistChat/StylistChatTransport.swift")

        XCTAssertTrue(support.contains("AIProcessingConsentService().acceptCurrentConsent()"))
        XCTAssertTrue(transport.contains("static let disclosureVersion = \"2026-08-13.ai-processing.v3\""))
        XCTAssertTrue(transport.contains("v1/account/ai-processing-consent"))
        XCTAssertTrue(transport.contains("guard accepted.valid"))
    }

    func testSupportConsentRequiredHasVisibleReviewActionAndDoesNotAutoSendSavedQuestion() throws {
        let support = try source("StyleMatchAI/StyleMatchSupportCenter.swift")

        XCTAssertTrue(support.contains("Review Support Data Consent"))
        XCTAssertTrue(support.contains("SupportDataConsentDisclosureView"))
        XCTAssertTrue(support.contains("pendingConsentMessage = message"))
        XCTAssertTrue(support.contains("Your saved question has not been sent."))
        XCTAssertTrue(support.contains("Send Saved Question"))
        XCTAssertTrue(support.contains("func retryPendingConsentMessage() async"))
        XCTAssertTrue(support.contains("guard let entryID = model.beginSupportQuestion(question) else { return }"))
        XCTAssertTrue(support.contains("draft = \"\""))
        XCTAssertTrue(support.contains("SupportChatBubble(entry: entry)"))
        XCTAssertTrue(support.contains("proxy.scrollTo(\"support-chat-bottom\""))
        XCTAssertFalse(support.contains("accepted: { Task { await model.retryPendingConsentMessage() }"))
    }

    func testSupportConsentDisclosureStatesBoundedDataAndPrivacyExclusions() throws {
        let support = try source("StyleMatchAI/StyleMatchSupportCenter.swift")

        XCTAssertTrue(support.contains("Your support question and bounded app details"))
        XCTAssertTrue(support.contains("Private messages, photos or image bytes, Profile details, Closet content, Scan content, AI Memory, precise location, account identifiers, and session tokens are not included."))
        XCTAssertTrue(support.contains("approved KigoStylist support information"))
        XCTAssertTrue(support.contains("Cloudflare routes them to OpenAI, the downstream AI processor."))
    }

    private func source(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }
}

private struct SupportChatTestService: StyleMatchSupportService {
    enum Result { case success, retryableFailure, consentRequired }
    let result: Result

    func askSupportAI(message: String, diagnostics: SupportDiagnostics) async throws -> SupportAIResponse {
        switch result {
        case .success:
            return SupportAIResponse(answer: "Hello! How can I assist you today?", grounding: "approved", action: "none", escalation: false, reasonCode: "synthetic")
        case .retryableFailure:
            throw SupportServiceError.networkUnavailable
        case .consentRequired:
            throw SupportServiceError.consentRequired
        }
    }

    func createCase(category: SupportCategory, summary: String, diagnostics: SupportDiagnostics) async throws -> SupportCase { throw SupportServiceError.supportUnavailable }
    func cases() async throws -> [SupportCase] { throw SupportServiceError.supportUnavailable }
    func supportCase(_ reference: StyleMatchSupportReference) async throws -> (SupportCase, [SupportMessage]) { throw SupportServiceError.supportUnavailable }
    func appendMessage(to reference: StyleMatchSupportReference, text: String) async throws { throw SupportServiceError.supportUnavailable }
    func requestEscalation(for reference: StyleMatchSupportReference) async throws -> SupportEscalationState { throw SupportServiceError.supportUnavailable }
    func submitBugReport(_ report: SupportBugReport) async throws -> StyleMatchSupportReference { throw SupportServiceError.supportUnavailable }
    func contactState() async throws -> SupportContactState { .unavailable }
}
