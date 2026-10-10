import SwiftUI
import Foundation

// Dedicated customer-support domain. It intentionally has no dependency on
// AI Stylist, Style Friends chat, Profile, Closet, Scan History, AI Memory,
// CloudKit, or Cloud Sync.
struct StyleMatchSupportReference: Codable, Hashable, Sendable, Identifiable {
    let value: String
    init?(_ value: String) {
        guard value.range(of: "^[A-Za-z0-9_-]{24,128}$", options: .regularExpression) != nil else { return nil }
        self.value = value
    }
    var id: String { value }
    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        guard let reference = StyleMatchSupportReference(value) else {
            throw DecodingError.dataCorruptedError(in: try decoder.singleValueContainer(), debugDescription: "Invalid opaque support reference.")
        }
        self = reference
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

enum SupportCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case account, styleFriends, messaging, outfitScan, scores, aiStylist, notifications, privacy, accountDeletion, troubleshooting, bugReport, general
    var id: String { rawValue }
    var title: String {
        switch self {
        case .account: "Account & Sign-In"; case .styleFriends: "Style Friends"; case .messaging: "Style Friends messages"
        case .outfitScan: "Outfit Scan & Scores"; case .scores: "Scores"; case .aiStylist: "AI Stylist"
        case .notifications: "Notifications"; case .privacy: "Privacy & Data"; case .accountDeletion: "Account Deletion"
        case .troubleshooting: "Technical Problem"; case .bugReport: "Report a Problem"; case .general: "Other"
        }
    }
    var icon: String {
        switch self {
        case .account: "person.crop.circle"; case .styleFriends: "person.2.fill"; case .messaging: "bubble.left.and.bubble.right"
        case .outfitScan, .scores: "camera.metering.center"; case .aiStylist: "sparkles"; case .notifications: "bell"
        case .privacy: "hand.raised.fill"; case .accountDeletion: "person.crop.circle.badge.minus"; case .troubleshooting: "wrench.and.screwdriver"
        case .bugReport: "ladybug.fill"; case .general: "questionmark.circle.fill"
        }
    }
}

enum SupportCaseStatus: String, Codable, Sendable { case open, awaitingUser, underReview, resolved, closed }
enum SupportPriority: String, Codable, Sendable { case standard, priority }
enum SupportMessageSender: String, Codable, Sendable { case user, support, system }
enum SupportEscalationState: String, Codable, Sendable { case none, requested, humanSupportUnavailable, configured }
enum SupportContactState: Equatable, Sendable { case unavailable, configured(URL) }
enum StyleMatchSupportContact {
    static let email = "hello@goodnessoflifeandfun.com"
    static let mailtoURL = URL(string: "mailto:\(email)")!
}
enum SupportServiceError: String, Error, Equatable, Codable, Sendable {
    case supportUnavailable, knowledgeUnavailable, authenticationRequired, consentRequired, rateLimited
    case caseUnavailable, humanSupportUnavailable, invalidRequest, invalidResponse
    case networkUnavailable, serverUnavailable

    var isRetryable: Bool {
        switch self {
        case .networkUnavailable, .serverUnavailable, .supportUnavailable, .knowledgeUnavailable, .rateLimited:
            true
        case .authenticationRequired, .consentRequired, .caseUnavailable, .humanSupportUnavailable, .invalidRequest, .invalidResponse:
            false
        }
    }
}

struct SupportCase: Codable, Equatable, Identifiable, Sendable {
    let supportCaseReference: StyleMatchSupportReference
    let category: SupportCategory
    let status: SupportCaseStatus
    let priority: SupportPriority
    let createdAt: Date
    let updatedAt: Date
    let resolvedAt: Date?
    var id: String { supportCaseReference.value }
    enum CodingKeys: String, CodingKey { case supportCaseReference = "support_case_ref", category, status, priority, createdAt = "created_at", updatedAt = "updated_at", resolvedAt = "resolved_at" }
}

struct SupportMessage: Codable, Equatable, Identifiable, Sendable {
    let messageReference: StyleMatchSupportReference
    let sender: SupportMessageSender
    let text: String
    let status: String
    let createdAt: Date
    var id: String { messageReference.value }
    enum CodingKeys: String, CodingKey { case messageReference = "message_ref", sender = "sender_type", text, status, createdAt = "created_at" }
}

struct SupportCaseEvent: Codable, Equatable, Identifiable, Sendable {
    let eventReference: StyleMatchSupportReference
    let actor: SupportMessageSender
    let type: String
    let createdAt: Date
    var id: String { eventReference.value }
    enum CodingKeys: String, CodingKey { case eventReference = "event_ref", actor, type, createdAt = "created_at" }
}

struct SupportAIResponse: Codable, Equatable, Sendable {
    let answer: String
    let grounding: String
    let action: String
    let escalation: Bool
    let reasonCode: String
    enum CodingKeys: String, CodingKey { case answer, grounding, action, escalation, reasonCode = "reason_code" }
}

enum SupportChatSender: Equatable, Sendable { case customer, assistant }
enum SupportChatDelivery: Equatable, Sendable { case sending, sent, retryableFailure, consentRequired, unavailable }

struct SupportChatTranscriptEntry: Identifiable, Equatable, Sendable {
    let id: UUID
    let sender: SupportChatSender
    let text: String
    var delivery: SupportChatDelivery

    init(id: UUID = UUID(), sender: SupportChatSender, text: String, delivery: SupportChatDelivery) {
        self.id = id
        self.sender = sender
        self.text = text
        self.delivery = delivery
    }
}

struct SupportDiagnostics: Codable, Equatable, Sendable {
    let appVersion: String
    let buildNumber: String
    let platform: String
    let osVersion: String
    let signedIn: Bool
    let styleFriendsAvailability: String
    let notificationPermission: String
    let errorCategory: String?
    let featureState: String

    static func current(errorCategory: String? = nil) -> SupportDiagnostics {
        let info = Bundle.main.infoDictionary
        return SupportDiagnostics(
            appVersion: info?["CFBundleShortVersionString"] as? String ?? "unknown",
            buildNumber: info?["CFBundleVersion"] as? String ?? "unknown",
            platform: "iOS",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            signedIn: StyleMatchAccountSessionStore.load()?.expiresAt ?? .distantPast > Date(),
            styleFriendsAvailability: StyleFriendsDMRuntimeAuthority.current == .stagingAuthorized ? "stagingAuthorized" : "unavailable",
            notificationPermission: "notChecked",
            errorCategory: errorCategory,
            featureState: StyleMatchSupportRuntimeAuthority.current == .stagingAuthorized ? "ownerBetaStaging" : "supportUnavailable"
        )
    }

    static func current(surface: SupportSurface, errorCategory: String? = nil) -> SupportDiagnostics {
        let baseline = current(errorCategory: errorCategory)
        return SupportDiagnostics(
            appVersion: baseline.appVersion,
            buildNumber: baseline.buildNumber,
            platform: baseline.platform,
            osVersion: baseline.osVersion,
            signedIn: baseline.signedIn,
            styleFriendsAvailability: baseline.styleFriendsAvailability,
            notificationPermission: baseline.notificationPermission,
            errorCategory: baseline.errorCategory,
            featureState: surface.rawValue
        )
    }
}

/// Bounded values only; the Worker receives no screen contents or personal data.
enum SupportSurface: String, Codable, Sendable {
    case supportHome, styleFriends, feed, requests, conversations, profile, notifications, scan, weatherStyling, aiStylist
}

struct SupportBugReport: Codable, Equatable, Sendable {
    let category: SupportCategory
    let description: String
    let reproductionSteps: String?
    let diagnostics: SupportDiagnostics
    enum CodingKeys: String, CodingKey { case category, description, reproductionSteps = "reproduction_steps", diagnostics }
}

protocol StyleMatchSupportService {
    func createCase(category: SupportCategory, summary: String, diagnostics: SupportDiagnostics) async throws -> SupportCase
    func cases() async throws -> [SupportCase]
    func supportCase(_ reference: StyleMatchSupportReference) async throws -> (SupportCase, [SupportMessage])
    func appendMessage(to reference: StyleMatchSupportReference, text: String) async throws
    func askSupportAI(message: String, diagnostics: SupportDiagnostics) async throws -> SupportAIResponse
    func requestEscalation(for reference: StyleMatchSupportReference) async throws -> SupportEscalationState
    func submitBugReport(_ report: SupportBugReport) async throws -> StyleMatchSupportReference
    func contactState() async throws -> SupportContactState
}

/// The normal application service. Runtime support remains fail-closed until a
/// separately authorized staging endpoint and support provider are available.
struct StyleMatchUnavailableSupportService: StyleMatchSupportService {
    private func unavailable() throws -> Never { throw SupportServiceError.supportUnavailable }
    func createCase(category: SupportCategory, summary: String, diagnostics: SupportDiagnostics) async throws -> SupportCase { try unavailable() }
    func cases() async throws -> [SupportCase] { try unavailable() }
    func supportCase(_ reference: StyleMatchSupportReference) async throws -> (SupportCase, [SupportMessage]) { try unavailable() }
    func appendMessage(to reference: StyleMatchSupportReference, text: String) async throws { try unavailable() }
    func askSupportAI(message: String, diagnostics: SupportDiagnostics) async throws -> SupportAIResponse { try unavailable() }
    func requestEscalation(for reference: StyleMatchSupportReference) async throws -> SupportEscalationState { try unavailable() }
    func submitBugReport(_ report: SupportBugReport) async throws -> StyleMatchSupportReference { try unavailable() }
    func contactState() async throws -> SupportContactState { .unavailable }
}

/// A missing/expired account is a customer action, not a disabled service.
struct StyleMatchSignInRequiredSupportService: StyleMatchSupportService {
    private func unavailable() throws -> Never { throw SupportServiceError.authenticationRequired }
    func createCase(category: SupportCategory, summary: String, diagnostics: SupportDiagnostics) async throws -> SupportCase { try unavailable() }
    func cases() async throws -> [SupportCase] { try unavailable() }
    func supportCase(_ reference: StyleMatchSupportReference) async throws -> (SupportCase, [SupportMessage]) { try unavailable() }
    func appendMessage(to reference: StyleMatchSupportReference, text: String) async throws { try unavailable() }
    func askSupportAI(message: String, diagnostics: SupportDiagnostics) async throws -> SupportAIResponse { try unavailable() }
    func requestEscalation(for reference: StyleMatchSupportReference) async throws -> SupportEscalationState { try unavailable() }
    func submitBugReport(_ report: SupportBugReport) async throws -> StyleMatchSupportReference { try unavailable() }
    func contactState() async throws -> SupportContactState { .unavailable }
}

struct StyleMatchSupportStagingConfiguration: Equatable, Sendable {
    static let maximumRequestBytes = 12_000
    static let maximumResponseBytes = 128_000
    static let timeout: TimeInterval = 15
    let baseURL: URL
    init?(baseURL: URL) {
        guard baseURL.scheme == "https", AppBackendConfiguration.isAuthorizedFriendsStagingHost(baseURL.host),
              baseURL.user == nil, baseURL.password == nil, baseURL.port == nil, baseURL.query == nil, baseURL.fragment == nil,
              baseURL.path.isEmpty || baseURL.path == "/" else { return nil }
        self.baseURL = baseURL
    }
}

enum StyleMatchSupportRuntimeAuthority: String, Equatable, Sendable {
    case disabled, stagingAuthorized
    /// Authority is a signed-build configuration, not a compiler mode. A
    /// release-signed owner-beta build can use the allowlisted staging host,
    /// while ordinary Release remains disabled by its configuration value.
    static func resolve(rawValue: String?) -> Self { rawValue == Self.stagingAuthorized.rawValue ? .stagingAuthorized : .disabled }
    static var current: Self {
        resolve(rawValue: Bundle.main.object(forInfoDictionaryKey: "STYLEMATCH_SUPPORT_RUNTIME_AUTHORITY") as? String)
    }
    /// Compatibility observation only; service construction remains factory-owned.
    static var enabled: Bool { current == .stagingAuthorized }
}

enum StyleMatchSupportServiceFactory {
    static func current(bundle: Bundle = .main, accountSession: @escaping () -> StyleMatchAccountSession? = StyleMatchAccountSessionStore.load) -> any StyleMatchSupportService {
        return resolve(
            authority: StyleMatchSupportRuntimeAuthority.resolve(rawValue: bundle.object(forInfoDictionaryKey: "STYLEMATCH_SUPPORT_RUNTIME_AUTHORITY") as? String),
            baseURL: AppBackendConfiguration.configuredAPIBaseURL(bundle: bundle),
            accountSession: accountSession
        )
    }

    static func resolve(authority: StyleMatchSupportRuntimeAuthority, baseURL: URL?, accountSession: @escaping () -> StyleMatchAccountSession?) -> any StyleMatchSupportService {
        guard authority == .stagingAuthorized,
              let baseURL, let configuration = StyleMatchSupportStagingConfiguration(baseURL: baseURL) else { return StyleMatchUnavailableSupportService() }
        guard let account = accountSession(), account.expiresAt > Date() else { return StyleMatchSignInRequiredSupportService() }
        _ = account
        return StyleMatchHTTPSupportService(configuration: configuration, accountSession: accountSession)
    }
}

struct StyleMatchHTTPSupportService: StyleMatchSupportService {
    let configuration: StyleMatchSupportStagingConfiguration
    let session: URLSession
    let accountSession: () -> StyleMatchAccountSession?
    init(configuration: StyleMatchSupportStagingConfiguration, session: URLSession = .shared, accountSession: @escaping () -> StyleMatchAccountSession? = StyleMatchAccountSessionStore.load) { self.configuration = configuration; self.session = session; self.accountSession = accountSession }
    func createCase(category: SupportCategory, summary: String, diagnostics: SupportDiagnostics) async throws -> SupportCase { struct Body: Encodable { let category: SupportCategory; let summary: String; let diagnostics: SupportDiagnostics }; struct Result: Decodable { let supportCaseReference: StyleMatchSupportReference; let status: SupportCaseStatus; enum CodingKeys: String, CodingKey { case supportCaseReference = "support_case_ref", status } }; let result: Result = try await request("/v1/support/cases", "POST", Body(category: category, summary: summary, diagnostics: diagnostics)); return SupportCase(supportCaseReference: result.supportCaseReference, category: category, status: result.status, priority: .standard, createdAt: Date(), updatedAt: Date(), resolvedAt: nil) }
    func cases() async throws -> [SupportCase] { struct Result: Decodable { let items: [SupportCase] }; let result: Result = try await request("/v1/support/cases", "GET", Optional<String>.none); return result.items }
    func supportCase(_ reference: StyleMatchSupportReference) async throws -> (SupportCase, [SupportMessage]) { struct Result: Decodable { let `case`: SupportCase; let messages: [SupportMessage] }; let result: Result = try await request("/v1/support/cases/\(reference.value)", "GET", Optional<String>.none); return (result.case, result.messages) }
    func appendMessage(to reference: StyleMatchSupportReference, text: String) async throws { struct Body: Encodable { let message: String }; let _: Empty = try await request("/v1/support/cases/\(reference.value)/messages", "POST", Body(message: text)) }
    func askSupportAI(message: String, diagnostics: SupportDiagnostics) async throws -> SupportAIResponse { struct Body: Encodable { let message: String; let diagnostics: SupportDiagnostics }; return try await request("/v1/support/chat", "POST", Body(message: message, diagnostics: diagnostics)) }
    func requestEscalation(for reference: StyleMatchSupportReference) async throws -> SupportEscalationState { struct Result: Decodable { let contact: String }; let result: Result = try await request("/v1/support/cases/\(reference.value)/escalate", "POST", Optional<String>.none); return result.contact == "configured" ? .configured : .humanSupportUnavailable }
    func submitBugReport(_ report: SupportBugReport) async throws -> StyleMatchSupportReference { struct Result: Decodable { let bugReportReference: StyleMatchSupportReference; enum CodingKeys: String, CodingKey { case bugReportReference = "bug_report_ref" } }; let result: Result = try await request("/v1/support/bug-reports", "POST", report); return result.bugReportReference }
    func contactState() async throws -> SupportContactState { .unavailable }
    private struct Empty: Decodable {}
    private struct WorkerError: Decodable { let error: String? }
    private func request<T: Decodable, Body: Encodable>(_ path: String, _ method: String, _ body: Body?) async throws -> T {
        guard let account = accountSession(), account.expiresAt > Date(), let url = URL(string: path, relativeTo: configuration.baseURL), url.scheme == "https", AppBackendConfiguration.isAuthorizedFriendsStagingHost(url.host) else { throw SupportServiceError.authenticationRequired }
        var request = URLRequest(url: url); request.httpMethod = method; request.timeoutInterval = StyleMatchSupportStagingConfiguration.timeout
        request.setValue("Bearer \(account.token)", forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body { let data = try JSONEncoder.support.encode(body); guard data.count <= StyleMatchSupportStagingConfiguration.maximumRequestBytes else { throw SupportServiceError.invalidRequest }; request.httpBody = data; request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is URLError {
            throw SupportServiceError.networkUnavailable
        } catch {
            throw SupportServiceError.serverUnavailable
        }
        guard data.count <= StyleMatchSupportStagingConfiguration.maximumResponseBytes, let http = response as? HTTPURLResponse else { throw SupportServiceError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 { throw SupportServiceError.authenticationRequired }
            let value = try? JSONDecoder.support.decode(WorkerError.self, from: data)
            if value?.error == "aiConsentRequired" { throw SupportServiceError.consentRequired }
            if let error = SupportServiceError(rawValue: value?.error ?? "") { throw error }
            if (500..<600).contains(http.statusCode) { throw SupportServiceError.serverUnavailable }
            throw SupportServiceError.invalidResponse
        }
        if T.self == Empty.self { return Empty() as! T }
        return try JSONDecoder.support.decode(T.self, from: data)
    }
}

private extension JSONEncoder { static var support: JSONEncoder { let value = JSONEncoder(); value.dateEncodingStrategy = .iso8601; return value } }
private extension JSONDecoder { static var support: JSONDecoder { let value = JSONDecoder(); value.dateDecodingStrategy = .iso8601; return value } }

@MainActor final class StyleMatchSupportCenterModel: ObservableObject {
    enum ChatState: Equatable { case ready, sending, answered(SupportAIResponse), signInRequired, consentRequired, retryableFailure(SupportServiceError), providerUnavailable(SupportServiceError), serviceDisabled }
    enum CaseListState: Equatable { case idle, loading, empty, loaded, failed(SupportServiceError) }
    enum CaseDetailState: Equatable { case idle, loading, loaded(SupportCase, [SupportMessage]), notFound, failed(SupportServiceError) }
    enum BugReportState: Equatable { case idle, submitting, submitted(StyleMatchSupportReference), failed(SupportServiceError) }
    enum CaseMessageState: Equatable { case idle, sending, failed(SupportServiceError) }
    enum EscalationState: Equatable { case idle, requesting, markedForEscalation(contactConfigured: Bool), failed(SupportServiceError) }
    @Published var chatState: ChatState = .ready
    @Published var cases: [SupportCase] = []
    @Published var caseListState: CaseListState = .idle
    @Published var caseDetailState: CaseDetailState = .idle
    @Published var bugReportState: BugReportState = .idle
    @Published var caseMessageState: CaseMessageState = .idle
    @Published var escalationState: EscalationState = .idle
    @Published var errorMessage: String?
    @Published private(set) var pendingConsentMessage: String?
    @Published private(set) var chatHistory: [SupportChatTranscriptEntry] = []
    @Published private(set) var retryableMessageID: UUID?
    @Published private(set) var pendingConsentMessageID: UUID?
    let service: any StyleMatchSupportService
    init(service: any StyleMatchSupportService = StyleMatchSupportServiceFactory.current()) { self.service = service }
    func loadCases() async {
        caseListState = .loading
        do {
            cases = try await service.cases()
            caseListState = cases.isEmpty ? .empty : .loaded
            errorMessage = nil
        } catch {
            let typed = typedError(error)
            caseListState = .failed(typed)
            errorMessage = Self.message(for: typed)
        }
    }
    func loadCase(_ reference: StyleMatchSupportReference) async {
        caseDetailState = .loading
        do { let detail = try await service.supportCase(reference); caseDetailState = .loaded(detail.0, detail.1) }
        catch { let typed = typedError(error); caseDetailState = typed == .caseUnavailable ? .notFound : .failed(typed) }
    }
    func beginSupportQuestion(_ message: String) -> UUID? {
        let sanitized = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitized.isEmpty, chatState != .sending else { return nil }
        let entry = SupportChatTranscriptEntry(sender: .customer, text: sanitized, delivery: .sending)
        chatHistory.append(entry)
        chatState = .sending
        return entry.id
    }

    func ask(_ message: String) async {
        guard let entryID = beginSupportQuestion(message) else { return }
        await completeSupportQuestion(message, entryID: entryID)
    }

    func completeSupportQuestion(_ message: String, entryID: UUID) async {
        do {
            let response = try await service.askSupportAI(message: message, diagnostics: .current(surface: .supportHome))
            updateDelivery(for: entryID, to: .sent)
            pendingConsentMessage = nil
            pendingConsentMessageID = nil
            retryableMessageID = nil
            chatHistory.append(.init(sender: .assistant, text: response.answer, delivery: .sent))
            chatState = .answered(response)
        }
        catch {
            let typed = typedError(error)
            switch typed {
            case .authenticationRequired:
                updateDelivery(for: entryID, to: .unavailable)
                chatState = .signInRequired
            case .consentRequired:
                // Keep the question locally. Explicit consent never sends it automatically.
                updateDelivery(for: entryID, to: .consentRequired)
                pendingConsentMessage = message
                pendingConsentMessageID = entryID
                chatState = .consentRequired
            case .supportUnavailable:
                updateDelivery(for: entryID, to: .unavailable)
                chatState = .serviceDisabled
            case .networkUnavailable, .serverUnavailable, .rateLimited:
                updateDelivery(for: entryID, to: .retryableFailure)
                retryableMessageID = entryID
                chatState = .retryableFailure(typed)
            default:
                updateDelivery(for: entryID, to: .unavailable)
                chatState = .providerUnavailable(typed)
            }
        }
    }
    func supportConsentWasRecorded() {
        guard pendingConsentMessage != nil else { return }
        chatState = .ready
    }
    func retryPendingConsentMessage() async {
        guard let pendingConsentMessage, let pendingConsentMessageID else { return }
        updateDelivery(for: pendingConsentMessageID, to: .sending)
        chatState = .sending
        await completeSupportQuestion(pendingConsentMessage, entryID: pendingConsentMessageID)
    }
    func retryFailedMessage() async {
        guard let retryableMessageID,
              let entry = chatHistory.first(where: { $0.id == retryableMessageID }) else { return }
        updateDelivery(for: retryableMessageID, to: .sending)
        chatState = .sending
        await completeSupportQuestion(entry.text, entryID: retryableMessageID)
    }
    private func updateDelivery(for entryID: UUID, to delivery: SupportChatDelivery) {
        guard let index = chatHistory.firstIndex(where: { $0.id == entryID }) else { return }
        chatHistory[index].delivery = delivery
    }
    func submitBugReport(_ report: SupportBugReport) async {
        guard bugReportState != .submitting else { return }
        bugReportState = .submitting
        do { bugReportState = .submitted(try await service.submitBugReport(report)) }
        catch { bugReportState = .failed(typedError(error)) }
    }
    func appendCaseMessage(_ text: String, to reference: StyleMatchSupportReference) async -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, caseMessageState != .sending else { return false }
        caseMessageState = .sending
        do {
            try await service.appendMessage(to: reference, text: text)
            caseMessageState = .idle
            await loadCase(reference)
            return true
        } catch {
            caseMessageState = .failed(typedError(error))
            return false
        }
    }
    func requestEscalation(for reference: StyleMatchSupportReference) async {
        guard escalationState != .requesting else { return }
        escalationState = .requesting
        do {
            let result = try await service.requestEscalation(for: reference)
            escalationState = .markedForEscalation(contactConfigured: result == .configured)
            await loadCase(reference)
        } catch {
            escalationState = .failed(typedError(error))
        }
    }
    private func typedError(_ error: Error) -> SupportServiceError { error as? SupportServiceError ?? .invalidResponse }
    static func message(for error: Error) -> String { switch error as? SupportServiceError { case .knowledgeUnavailable: "Approved support information is temporarily unavailable."; case .authenticationRequired: "Sign in to use AI Customer Service."; case .consentRequired: "Review support-data consent to continue."; case .rateLimited: "Please wait a moment before trying again."; case .caseUnavailable: "This support case is unavailable."; case .humanSupportUnavailable: "Your case has been marked for escalation. Human contact is not configured."; case .invalidRequest: "That support request could not be sent."; case .networkUnavailable: "You appear to be offline. Your message is still here to retry."; case .serverUnavailable: "Support is temporarily unavailable. Please try again."; case .supportUnavailable: "AI Customer Service is unavailable right now."; default: "Support could not understand that response. Please try again." } }
}

struct StyleMatchSupportView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = StyleMatchSupportCenterModel()
    @State private var selectedCategory: SupportCategory?
    @State private var suggestedQuestion: String?
    @State private var showingBugReport = false
    let onOpenAccountDeletion: () -> Void
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("AI Customer Service", systemImage: "lifepreserver.fill").font(.title2.bold()).foregroundStyle(.purple)
                        Text("Helpful answers for getting the most from KigoStylist.").font(.subheadline).foregroundStyle(.secondary)
                        Text("Automated answers use approved KigoStylist support information.").font(.caption).foregroundStyle(.secondary).accessibilityLabel("Support AI disclosure. Automated help using approved KigoStylist support information.")
                    }.padding().appCard(.profile, radius: 18)
                    supportAvailability
                    humanSupportContact
                    suggestedTopics
                    Text("Browse help topics").font(.subheadline.weight(.semibold))
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) { ForEach(SupportCategory.allCases.filter { $0 != .bugReport && $0 != .accountDeletion }) { category in Button { selectedCategory = category } label: { Label(category.title, systemImage: category.icon).frame(maxWidth: .infinity, minHeight: 52, alignment: .leading).padding(10).appCard(.profile, radius: 14) }.buttonStyle(.plain).accessibilityLabel(category.title).accessibilityHint("Opens support for this topic.") } }
                    Button { showingBugReport = true } label: { Label("Report a Problem", systemImage: "ladybug.fill").frame(maxWidth: .infinity, minHeight: 48) }.buttonStyle(.borderedProminent)
                    NavigationLink { SupportCaseListView(model: model) } label: { Label("My Support Cases", systemImage: "tray.full") }
                    Button { onOpenAccountDeletion() } label: { Label("Account & Privacy", systemImage: "hand.raised.fill").frame(maxWidth: .infinity, minHeight: 48) }.accessibilityHint("Opens the existing account deletion confirmation flow.")
                    DisclosureGroup("Support data & privacy") { Text("Your question and bounded app details such as version and feature availability may accompany a support request. Private messages, photos, Profile, Closet, scans, and AI Memory are not included.").font(.caption).foregroundStyle(.secondary).padding(.top, 4) }
                }
                .padding()
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .appScreenBackground(.profile)
            .navigationTitle("Support").toolbar { ToolbarItem(placement: .automatic) { Button("Done") { dismiss() } } }
            .sheet(item: $selectedCategory) { SupportChatView(category: $0, initialQuestion: suggestedQuestion, model: model) }
            .sheet(isPresented: $showingBugReport) { SupportBugReportView(model: model) }
        }
    }
    private var supportAvailability: some View { VStack(alignment: .leading, spacing: 6) { Label(StyleMatchSupportRuntimeAuthority.current == .stagingAuthorized ? "AI Customer Service is ready" : "AI Customer Service is unavailable", systemImage: StyleMatchSupportRuntimeAuthority.current == .stagingAuthorized ? "checkmark.shield.fill" : "exclamationmark.triangle.fill").foregroundStyle(.secondary); Text(StyleMatchSupportRuntimeAuthority.current == .stagingAuthorized ? "Sign in and review support-data consent before asking a question." : "This service is unavailable in the current app configuration.").font(.caption).foregroundStyle(.secondary) }.padding().appCard(.profile, radius: 14).accessibilityElement(children: .combine) }
    private var humanSupportContact: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Contact KigoStylist Support", systemImage: "envelope.fill")
                .font(.subheadline.weight(.semibold))
            Text("For help or privacy questions, email KigoStylist Support directly.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Link(StyleMatchSupportContact.email, destination: StyleMatchSupportContact.mailtoURL)
                .font(.body.weight(.semibold))
                .accessibilityLabel("Email KigoStylist Support at \(StyleMatchSupportContact.email)")
                .accessibilityHint("Opens your email app.")
        }
        .padding()
        .appCard(.profile, radius: 14)
    }
    private var suggestedTopics: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Popular help topics").font(.subheadline.weight(.semibold))
            ForEach(["Help me with Style Friends", "I can't sign in", "My scan result looks wrong", "My weather recommendation looks wrong", "Notifications aren't working"], id: \.self) { topic in
                Button(topic) { suggestedQuestion = topic; selectedCategory = topic.contains("sign in") ? .account : (topic.contains("scan") || topic.contains("weather") ? .outfitScan : (topic.contains("Notifications") ? .notifications : .styleFriends)) }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .buttonStyle(.bordered)
                    .accessibilityHint("Opens a support question for \(topic).")
            }
        }
    }
}

private struct SupportChatView: View {
    let category: SupportCategory
    let initialQuestion: String?
    @ObservedObject var model: StyleMatchSupportCenterModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @StateObject private var consentStore = AITransmissionConsentStore.shared
    @State private var showingSupportConsent = false
    @State private var isRecordingSupportConsent = false
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text(category.title).font(.headline)
                Text("Automated answers use approved KigoStylist support information.").font(.caption).foregroundStyle(.secondary)
                conversation
                HStack(alignment: .bottom) {
                    TextField("Describe what you need help with", text: $draft, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(1...5)
                    Button("Send") { sendDraft() }.disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.chatState == .sending).accessibilityLabel(model.chatState == .sending ? "Sending support question" : "Send support question")
                }
            }
            .padding()
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
            .appScreenBackground(.profile)
            .navigationTitle("Support Chat")
            .onAppear {
                consentStore.refresh()
                if draft.isEmpty, let initialQuestion { draft = initialQuestion }
            }
            .toolbar { ToolbarItem(placement: .automatic) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showingSupportConsent) {
                SupportDataConsentDisclosureView(
                    consentStore: consentStore,
                    recordCurrentConsent: recordCurrentSupportConsent,
                    accepted: { model.supportConsentWasRecorded() }
                )
            }
        }
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(model.chatHistory) { entry in
                        SupportChatBubble(entry: entry)
                            .id(entry.id)
                    }
                    chatStatePresentation
                    Color.clear.frame(height: 1).id("support-chat-bottom")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: model.chatHistory.count) { _ in
                withAnimation { proxy.scrollTo("support-chat-bottom", anchor: .bottom) }
            }
            .onChange(of: model.chatState) { _ in
                withAnimation { proxy.scrollTo("support-chat-bottom", anchor: .bottom) }
            }
            .accessibilityLabel("Support conversation")
        }
    }

    @ViewBuilder private var chatStatePresentation: some View {
        switch model.chatState {
        case .sending:
            ProgressView("KigoStylist Support AI is working…")
                .frame(maxWidth: .infinity, alignment: .leading)
        case .signInRequired:
            SupportChatRequirement(title: "Sign in required", detail: "Sign in to use AI Customer Service.")
        case .consentRequired:
            SupportChatRequirement(title: "Support-data consent required",
                detail: "Review support-data consent before sending your saved question.",
                actionTitle: "Review Support Data Consent",
                action: { showingSupportConsent = true }
            )
        case let .retryableFailure(error):
            SupportChatRequirement(
                title: StyleMatchSupportCenterModel.message(for: error),
                detail: "Your message is saved and has not been sent again.",
                actionTitle: "Try Again",
                action: { Task { await model.retryFailedMessage() } }
            )
        case let .providerUnavailable(error):
            SupportChatRequirement(title: "Support AI is temporarily unavailable", detail: StyleMatchSupportCenterModel.message(for: error))
        case .serviceDisabled:
            SupportChatRequirement(title: "AI Customer Service unavailable", detail: "No message has been sent.")
        case .ready:
            if model.pendingConsentMessage != nil {
                SupportChatRequirement(
                    title: "Your question is ready",
                    detail: "Your saved question has not been sent. Send it when you’re ready.",
                    actionTitle: "Send Saved Question",
                    action: { Task { await model.retryPendingConsentMessage() } }
                )
            }
        case .answered:
            EmptyView()
        }
    }

    private func sendDraft() {
        let question = draft
        guard let entryID = model.beginSupportQuestion(question) else { return }
        draft = ""
        Task { await model.completeSupportQuestion(question, entryID: entryID) }
    }

    private func recordCurrentSupportConsent() async -> Bool {
        guard !isRecordingSupportConsent else { return false }
        isRecordingSupportConsent = true
        defer { isRecordingSupportConsent = false }
        do {
            try await AIProcessingConsentService().acceptCurrentConsent()
            consentStore.accept()
            return true
        } catch {
            return false
        }
    }
}

private struct SupportChatBubble: View {
    let entry: SupportChatTranscriptEntry

    var body: some View {
        VStack(alignment: entry.sender == .customer ? .trailing : .leading, spacing: 4) {
            Text(entry.sender == .customer ? "You" : "KigoStylist Support")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(entry.text)
                .frame(maxWidth: .infinity, alignment: entry.sender == .customer ? .trailing : .leading)
            if entry.delivery == .sending {
                Text("Sending…").font(.caption).foregroundStyle(.secondary)
            } else if entry.delivery == .retryableFailure {
                Text("Not sent — retry available.").font(.caption).foregroundStyle(.secondary)
            } else if entry.delivery == .consentRequired {
                Text("Not sent — support-data consent required.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: entry.sender == .customer ? .trailing : .leading)
        .padding()
        .appCard(.profile, radius: 14)
        .accessibilityElement(children: .combine)
    }
}

private struct SupportChatRequirement: View {
    let title: String
    let detail: String
    let actionTitle: String?
    let action: (() -> Void)?

    init(title: String, detail: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.detail = detail
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(detail).font(.subheadline).foregroundStyle(.secondary)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .frame(minHeight: 44)
                    .accessibilityHint("Opens the consent review before any Support AI request is sent.")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}

/// Support uses the existing account-scoped AI-processing consent authority.
/// It has a narrower disclosure than Stylist because Support sends only the
/// user’s support question plus the bounded diagnostics documented below.
private struct SupportDataConsentDisclosureView: View {
    @ObservedObject var consentStore: AITransmissionConsentStore
    let recordCurrentConsent: () async -> Bool
    let accepted: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isRecordingConsent = false
    @State private var acceptanceError: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("KigoStylist sends information over the network only when you ask AI Customer Service for help.")
                }
                Section("What may be sent") {
                    Text("Your support question and bounded app details needed to troubleshoot it, such as app version, build number, feature availability, and notification permission state.")
                }
                Section("What is not sent") {
                    Text("Private messages, photos or image bytes, Profile details, Closet content, Scan content, AI Memory, precise location, account identifiers, and session tokens are not included.")
                }
                Section("Where it goes") {
                    Text("KigoStylist sends approved requests to its Cloudflare-hosted API. Cloudflare routes them to OpenAI, the downstream AI processor.")
                }
                Section("Why") {
                    Text("This information is used only to provide the Support AI answer you requested using approved KigoStylist support information.")
                }
                Section("Your choice") {
                    Text("Agree & Continue records your acceptance of the current support-data consent before any external AI transmission. Your saved question will remain unsent until you choose Send Saved Question. You can later review or revoke permission in Profile → Your Privacy → AI Processing Consent.")
                        .foregroundStyle(.secondary)
                }
                Section {
                    if let acceptanceError {
                        Text(acceptanceError).foregroundStyle(.red)
                    }
                    Button(isRecordingConsent ? "Recording consent…" : "Agree & Continue") {
                        Task {
                            isRecordingConsent = true
                            acceptanceError = nil
                            if await recordCurrentConsent() {
                                dismiss()
                                accepted()
                            } else {
                                acceptanceError = "We could not record your support-data consent. Please try again."
                            }
                            isRecordingConsent = false
                        }
                    }
                    .disabled(isRecordingConsent)
                    .frame(minHeight: 44)
                    Button("Not Now", role: .cancel) {
                        consentStore.decline()
                        dismiss()
                    }
                    .frame(minHeight: 44)
                }
            }
            .navigationTitle("Support Data Consent")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Not Now") { consentStore.decline(); dismiss() } } }
        }
    }
}

private struct SupportCaseListView: View {
    @ObservedObject var model: StyleMatchSupportCenterModel
    var body: some View { List {
        switch model.caseListState {
        case .loading: ProgressView("Loading support cases")
        case let .failed(error): SupportEmptyState(title: "Support cases unavailable", icon: "exclamationmark.triangle", detail: StyleMatchSupportCenterModel.message(for: error))
        case .idle, .empty: SupportEmptyState(title: "No support cases yet", icon: "tray", detail: "Support cases will appear here after a confirmed submission.")
        case .loaded: ForEach(model.cases) { item in NavigationLink { SupportCaseDetailView(reference: item.supportCaseReference, model: model) } label: { VStack(alignment: .leading) { Text(item.category.title); Text(item.status.rawValue).font(.caption).foregroundStyle(.secondary) } } }
        }
    }.navigationTitle("Your support cases").task { await model.loadCases() } }
}

private struct SupportCaseDetailView: View {
    let reference: StyleMatchSupportReference
    @ObservedObject var model: StyleMatchSupportCenterModel
    @State private var draft = ""
    var body: some View {
        List {
            switch model.caseDetailState {
            case .idle, .loading: ProgressView("Loading support case")
            case .notFound: SupportEmptyState(title: "Support case unavailable", icon: "lock", detail: "It may have been removed or belongs to another account.")
            case let .failed(error): SupportEmptyState(title: "Support case unavailable", icon: "exclamationmark.triangle", detail: StyleMatchSupportCenterModel.message(for: error))
            case let .loaded(item, messages):
                Section("Case") {
                    Text("Case \(item.supportCaseReference.value.prefix(12))…").font(.caption.monospaced())
                    LabeledContent("Category", value: item.category.title)
                    LabeledContent("Status", value: item.status.rawValue)
                    LabeledContent("Created", value: item.createdAt.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Updated", value: item.updatedAt.formatted(date: .abbreviated, time: .shortened))
                }
                Section("Messages") { if messages.isEmpty { Text("No messages yet.").foregroundStyle(.secondary) } else { ForEach(messages) { message in VStack(alignment: .leading, spacing: 4) { Text(message.sender == .user ? "You" : "KigoStylist Support").font(.caption.weight(.semibold)); Text(message.text) } } } }
                Section("Add a message") {
                    TextField("Add details", text: $draft, axis: .vertical).lineLimit(2...6)
                    if case let .failed(error) = model.caseMessageState { Text(StyleMatchSupportCenterModel.message(for: error)).font(.caption).foregroundStyle(.secondary) }
                    Button(model.caseMessageState == .sending ? "Sending…" : "Send message") {
                        let text = draft
                        Task { if await model.appendCaseMessage(text, to: reference) { draft = "" } }
                    }.disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.caseMessageState == .sending)
                        .accessibilityLabel(model.caseMessageState == .sending ? "Sending case message" : "Send case message")
                }
                Section("Escalation") {
                    Text("You can mark this case for escalation. This does not confirm that a person will contact you.").font(.caption).foregroundStyle(.secondary)
                    switch model.escalationState {
                    case .requesting: ProgressView("Marking case for escalation")
                    case let .markedForEscalation(contactConfigured): Text(contactConfigured ? "Case marked for escalation. Contact availability is configured; a response is not promised." : "Case marked for escalation. Human contact is not configured.").foregroundStyle(.secondary)
                    case let .failed(error): Text(StyleMatchSupportCenterModel.message(for: error)).foregroundStyle(.secondary)
                    case .idle: EmptyView()
                    }
                    Button("Mark for escalation") { Task { await model.requestEscalation(for: reference) } }
                        .disabled(model.escalationState == .requesting)
                        .accessibilityHint("Marks this case for escalation without promising human contact.")
                }
            }
        }.navigationTitle("Support case").task { await model.loadCase(reference) }
    }
}

private struct SupportEmptyState: View {
    let title: String
    let icon: String
    let detail: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.title2)
            Text(title).font(.headline)
            Text(detail).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding().accessibilityElement(children: .combine)
    }
}

private struct SupportBugReportView: View {
    @ObservedObject var model: StyleMatchSupportCenterModel
    @Environment(\.dismiss) private var dismiss
    @State private var category: SupportCategory = .bugReport
    @State private var description = ""
    @State private var steps = ""
    var body: some View {
        NavigationStack {
            Form {
                Picker("Category", selection: $category) {
                    ForEach(SupportCategory.allCases) { Text($0.title).tag($0) }
                }
                Section("What happened?") {
                    TextField("Describe the problem", text: $description, axis: .vertical).lineLimit(3...8)
                    TextField("Steps to reproduce (optional)", text: $steps, axis: .vertical).lineLimit(2...6)
                }
                Section {
                    Text("Screenshots are unavailable until a support upload authority is configured. Nothing is captured automatically.").font(.caption).foregroundStyle(.secondary)
                    Text("Build, app version, signed-in state, and bounded feature availability accompany this report. Private messages, photos, Profile, Closet, scans, AI Memory, location, and account identifiers are not included.").font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    switch model.bugReportState {
                    case .idle: EmptyView()
                    case .submitting: ProgressView("Submitting report")
                    case .submitted: Label("Your report was submitted.", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    case let .failed(error):
                        VStack(alignment: .leading, spacing: 8) {
                            Text(StyleMatchSupportCenterModel.message(for: error)).foregroundStyle(.secondary)
                            if error.isRetryable { Text("Your report is still here. You can retry when support is available.").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
            .navigationTitle("Report a Problem")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button(model.bugReportState == .submitting ? "Submitting…" : "Submit") {
                        Task {
                            await model.submitBugReport(SupportBugReport(
                                category: category,
                                description: description,
                                reproductionSteps: steps.isEmpty ? nil : steps,
                                diagnostics: .current(surface: .supportHome)
                            ))
                        }
                    }
                    .disabled(description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.bugReportState == .submitting)
                    .accessibilityLabel(model.bugReportState == .submitting ? "Submitting problem report" : "Submit problem report")
                }
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}
