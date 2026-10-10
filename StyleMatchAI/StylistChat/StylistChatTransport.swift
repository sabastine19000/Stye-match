import CryptoKit
import Combine
import Foundation
#if canImport(UIKit)
import UIKit
#endif

protocol StylistChatTransport {
    var authorizationState: StylistChatAuthorizationState { get }
    var aiTransmissionConsentState: AITransmissionConsentState { get }
    func send(_ request: ChatRequest) -> AsyncThrowingStream<String, Error>
    func sendVision(_ request: VisionChatRequestV1) -> AsyncThrowingStream<VisionChatResponseV1, Error>
}

enum StylistChatAuthorizationState: Equatable {
    case authorized
    case signInRequired
    case reconnectRequired
}

extension StylistChatTransport {
    var authorizationState: StylistChatAuthorizationState { .authorized }
    var aiTransmissionConsentState: AITransmissionConsentState { .accepted }
    func sendVision(_: VisionChatRequestV1) -> AsyncThrowingStream<VisionChatResponseV1, Error> {
        AsyncThrowingStream { $0.finish(throwing: StylistVisionRequestError.providerUnavailable) }
    }
}

/// The only authority for deciding whether StyleMatch may send an AI request.
/// It is deliberately independent from optional app-context sharing controls.
enum AITransmissionConsentState: String, Codable, Equatable {
    case undecided
    case accepted
    case declined
}

private struct AITransmissionConsentRecord: Codable, Equatable {
    let disclosureVersion: String
    let state: AITransmissionConsentState
    let updatedAt: Date
}

final class AITransmissionConsentStore: ObservableObject {
    /// Must match the account-scoped consent version enforced by the Worker.
    /// A local decision alone never authorizes an external AI request.
    static let disclosureVersion = "2026-08-13.ai-processing.v3"
    static let shared = AITransmissionConsentStore()

    @Published private(set) var state: AITransmissionConsentState

    private let defaults: UserDefaults
    private let userIDProvider: () -> String
    private let requiredDisclosureVersion: String

    init(
        defaults: UserDefaults = .standard,
        userIDProvider: @escaping () -> String = { PersonalStylistStorage.activeUserID() },
        disclosureVersion: String = AITransmissionConsentStore.disclosureVersion
    ) {
        self.defaults = defaults
        self.userIDProvider = userIDProvider
        requiredDisclosureVersion = disclosureVersion
        state = Self.readState(
            defaults: defaults,
            userID: userIDProvider(),
            requiredDisclosureVersion: disclosureVersion
        )
    }

    func refresh() {
        state = Self.readState(
            defaults: defaults,
            userID: userIDProvider(),
            requiredDisclosureVersion: requiredDisclosureVersion
        )
    }

    func accept() {
        write(.accepted)
    }

    func decline() {
        write(.declined)
    }

    /// Revocation blocks future transmissions. It intentionally does not erase
    /// local scans, profile data, conversations, or AI Memory.
    func revoke() {
        write(.declined)
    }

    static func deleteConsent(
        for userID: String,
        defaults: UserDefaults = .standard
    ) {
        defaults.removeObject(forKey: storageKey(for: userID))
    }

    private func write(_ newState: AITransmissionConsentState) {
        let record = AITransmissionConsentRecord(
            disclosureVersion: requiredDisclosureVersion,
            state: newState,
            updatedAt: Date()
        )
        guard let data = try? JSONEncoder().encode(record) else { return }
        defaults.set(data, forKey: Self.storageKey(for: userIDProvider()))
        state = newState
    }

    private static func readState(
        defaults: UserDefaults,
        userID: String,
        requiredDisclosureVersion: String
    ) -> AITransmissionConsentState {
        guard let data = defaults.data(forKey: storageKey(for: userID)),
              let record = try? JSONDecoder().decode(AITransmissionConsentRecord.self, from: data),
              record.disclosureVersion == requiredDisclosureVersion else {
            return .undecided
        }
        return record.state
    }

    private static func storageKey(for userID: String) -> String {
        PersonalStylistStorage.scopedKey("aiTransmissionConsent", userID: userID)
    }
}

enum AIConsentNetworkPolicy {
    /// Keep consent UI responsive on stalled transports. A timeout is treated
    /// exactly like any other unavailable network authority and never grants
    /// consent locally.
    static let requestTimeout: TimeInterval = 15
}

enum AIProcessingConsentServiceError: LocalizedError, Equatable {
    case signInRequired
    case unavailable
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .signInRequired: return "Sign in with Apple to review AI consent."
        case .unavailable: return "We could not record your AI consent. Please try again."
        case .invalidResponse: return "We could not confirm your AI consent. Please try again."
        }
    }
}

/// Account-scoped consent authority. It derives the bearer token only from the
/// existing session store and never accepts an account identifier from UI state.
struct AIProcessingConsentService {
    private struct ConsentStatus: Decodable {
        let requiredVersion: String
        let valid: Bool
        enum CodingKeys: String, CodingKey { case requiredVersion = "required_version", valid }
    }

    private let baseURL: URL
    private let session: URLSession
    private let accountSession: () -> StyleMatchAccountSession?

    init(baseURL: URL? = nil, session: URLSession = .shared, accountSession: @escaping () -> StyleMatchAccountSession? = StyleMatchAccountSessionStore.load) {
        self.baseURL = baseURL ?? StyleMatchRuntimeEndpoint.accountResolution()?.baseURL ?? AppBackendConfiguration.production().apiBaseURL
        self.session = session
        self.accountSession = accountSession
    }

    func acceptCurrentConsent() async throws {
        let current = try await request(method: "GET", version: nil)
        guard !current.requiredVersion.isEmpty else { throw AIProcessingConsentServiceError.invalidResponse }
        let accepted = try await request(method: "POST", version: current.requiredVersion)
        guard accepted.valid, accepted.requiredVersion == current.requiredVersion else { throw AIProcessingConsentServiceError.invalidResponse }
    }

    private func request(method: String, version: String?) async throws -> ConsentStatus {
        guard let account = accountSession(), account.expiresAt > Date() else { throw AIProcessingConsentServiceError.signInRequired }
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/account/ai-processing-consent"))
        request.httpMethod = method
        request.timeoutInterval = AIConsentNetworkPolicy.requestTimeout
        request.setValue("Bearer \(account.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let version {
            request.httpBody = try JSONEncoder().encode(["consent_version": version])
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw AIProcessingConsentServiceError.invalidResponse }
            if http.statusCode == 401 { throw AIProcessingConsentServiceError.signInRequired }
            guard (200..<300).contains(http.statusCode) else { throw AIProcessingConsentServiceError.unavailable }
            guard let decoded = try? JSONDecoder().decode(ConsentStatus.self, from: data) else { throw AIProcessingConsentServiceError.invalidResponse }
            return decoded
        } catch let error as AIProcessingConsentServiceError {
            throw error
        } catch {
            throw AIProcessingConsentServiceError.unavailable
        }
    }
}

/// The Worker is authoritative for these granular permissions. Local UI may
/// display a cached state, but a missing or stale cache is always treated as
/// denied and never authorizes a fact-context request.
enum AIScopedConsentScope: String, CaseIterable, Codable, Equatable, Identifiable {
    case selectedImage = "selected_image"
    case selectedScanFacts = "selected_scan_facts"
    case stylePreferences = "style_preferences"
    case selectedClosetItems = "selected_closet_items"

    var id: String { rawValue }

    var permissionTitle: String {
        switch self {
        case .selectedImage: "Selected Image"
        case .selectedScanFacts: "Saved Scan Facts"
        case .stylePreferences: "Style Preferences"
        case .selectedClosetItems: "Selected Closet Items"
        }
    }

    var allowAccessibilityLabel: String {
        switch self {
        case .selectedImage: "Allow Selected Image"
        case .selectedScanFacts: "Allow Saved Scan Facts"
        case .stylePreferences: "Allow Style Preferences"
        case .selectedClosetItems: "Allow Selected Closet Items"
        }
    }
}

/// Presence-only representation of the current canonical attachment
/// selection. It contains neither content nor client consent authority.
struct StylistScopedConsentAttachmentSnapshot: Equatable {
    let selectedImage: Bool
    let selectedScanFacts: Bool
    let stylePreferences: Bool
    let selectedClosetItems: Bool
}

enum StylistScopedConsentRouter {
    static func requiredScopes(for snapshot: StylistScopedConsentAttachmentSnapshot) -> [AIScopedConsentScope] {
        [
            snapshot.selectedImage ? .selectedImage : nil,
            snapshot.selectedScanFacts ? .selectedScanFacts : nil,
            snapshot.stylePreferences ? .stylePreferences : nil,
            snapshot.selectedClosetItems ? .selectedClosetItems : nil
        ].compactMap { $0 }
    }

    static func missingScopes(
        from requiredScopes: [AIScopedConsentScope],
        states: [AIScopedConsentScope: AIScopedConsentState]
    ) -> [AIScopedConsentScope] {
        requiredScopes.filter { states[$0]?.granted != true }
    }
}

struct AIScopedConsentState: Equatable {
    let scope: AIScopedConsentScope
    let granted: Bool
    let revision: Int
}

enum AIScopedConsentServiceError: LocalizedError, Equatable {
    case signInRequired
    case unavailable
    case invalidResponse
    case staleRevision

    var errorDescription: String? {
        switch self {
        case .signInRequired: return "Sign in with Apple to manage what AI Stylist may use."
        case .unavailable: return "We could not confirm that permission. Please try again."
        case .invalidResponse: return "We could not confirm that permission safely. Please try again."
        case .staleRevision: return "That permission changed. Review the current settings and try again."
        }
    }
}

/// A narrow authenticated adapter for the Worker-owned scoped-consent API.
/// It never sends a client account ID, profile, scan, closet, or image value.
struct AIScopedConsentService {
    private struct StateResponse: Decodable {
        struct Item: Decodable { let scope: String; let granted: Bool; let revision: Int }
        let scopes: [Item]
    }

    private struct MutationResponse: Decodable { let scope: String; let granted: Bool; let revision: Int }

    private let baseURL: URL
    private let session: URLSession
    private let accountSession: () -> StyleMatchAccountSession?

    init(baseURL: URL? = nil, session: URLSession = .shared, accountSession: @escaping () -> StyleMatchAccountSession? = StyleMatchAccountSessionStore.load) {
        self.baseURL = baseURL ?? StyleMatchRuntimeEndpoint.accountResolution()?.baseURL ?? AppBackendConfiguration.production().apiBaseURL
        self.session = session
        self.accountSession = accountSession
    }

    func currentStates() async throws -> [AIScopedConsentScope: AIScopedConsentState] {
        let (data, response) = try await request(method: "GET", body: nil)
        guard response.statusCode == 200,
              let decoded = try? JSONDecoder().decode(StateResponse.self, from: data) else {
            throw response.statusCode == 401 ? AIScopedConsentServiceError.signInRequired : AIScopedConsentServiceError.invalidResponse
        }
        var states: [AIScopedConsentScope: AIScopedConsentState] = [:]
        for item in decoded.scopes {
            guard let scope = AIScopedConsentScope(rawValue: item.scope), item.revision >= 0 else { continue }
            states[scope] = AIScopedConsentState(scope: scope, granted: item.granted, revision: item.revision)
        }
        guard states.count == AIScopedConsentScope.allCases.count else { throw AIScopedConsentServiceError.invalidResponse }
        return states
    }

    func grant(_ scope: AIScopedConsentScope, expectedRevision: Int) async throws -> AIScopedConsentState {
        let body: [String: Any] = [
            "action": "grant", "scope": scope.rawValue,
            "client_action_uuid": UUID().uuidString.lowercased(),
            "expected_revision": expectedRevision,
            "contract_version": "2026-08-23.selected-context.v1",
            "notice_digest": "6ef5c9b39d7b9d8219f126f3a4cc99221aa1bb34d6d3f2273ec17cc6c7497c12",
            "locale": "en-US"
        ]
        let (data, response) = try await request(method: "POST", body: body)
        if response.statusCode == 409 { throw AIScopedConsentServiceError.staleRevision }
        guard response.statusCode == 200,
              let decoded = try? JSONDecoder().decode(MutationResponse.self, from: data),
              decoded.scope == scope.rawValue, decoded.granted, decoded.revision > expectedRevision else {
            throw response.statusCode == 401 ? AIScopedConsentServiceError.signInRequired : AIScopedConsentServiceError.invalidResponse
        }
        return AIScopedConsentState(scope: scope, granted: true, revision: decoded.revision)
    }

    func revoke(_ scope: AIScopedConsentScope) async throws {
        let body: [String: Any] = ["action": "revoke", "scope": scope.rawValue, "client_action_uuid": UUID().uuidString.lowercased()]
        let (_, response) = try await request(method: "DELETE", body: body)
        guard response.statusCode == 204 else {
            throw response.statusCode == 401 ? AIScopedConsentServiceError.signInRequired : AIScopedConsentServiceError.unavailable
        }
    }

    private func request(method: String, body: [String: Any]?) async throws -> (Data, HTTPURLResponse) {
        guard let account = accountSession(), account.expiresAt > Date() else { throw AIScopedConsentServiceError.signInRequired }
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/account/ai-scopes"))
        request.httpMethod = method
        request.timeoutInterval = AIConsentNetworkPolicy.requestTimeout
        request.setValue("Bearer \(account.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw AIScopedConsentServiceError.invalidResponse }
            return (data, http)
        } catch let error as AIScopedConsentServiceError {
            throw error
        } catch {
            throw AIScopedConsentServiceError.unavailable
        }
    }
}

struct StylistChatConfiguration {
    let baseURL: URL

    static var production: StylistChatConfiguration? {
        StylistChatConfiguration(baseURL: AppBackendConfiguration.production().apiBaseURL)
    }
}

struct StylistChatAuthHeaders {
    static func deviceHash(defaults: UserDefaults = .standard) -> String {
        let key = "stylistChatDeviceHash"
        if let stored = defaults.string(forKey: key), stored.count == 64 {
            return stored
        }

        let rawIdentifier: String
        #if canImport(UIKit)
        rawIdentifier = UIDevice.current.identifierForVendor?.uuidString ?? persistedFallbackDeviceID(defaults: defaults)
        #else
        rawIdentifier = persistedFallbackDeviceID(defaults: defaults)
        #endif

        let hash = sha256Hex(rawIdentifier)
        defaults.set(hash, forKey: key)
        return hash
    }

    static func sha256Hex(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func persistedFallbackDeviceID(defaults: UserDefaults) -> String {
        let key = "stylistChatFallbackDeviceID"
        if let stored = defaults.string(forKey: key), !stored.isEmpty {
            return stored
        }
        let generated = UUID().uuidString
        defaults.set(generated, forKey: key)
        return generated
    }
}

final class LiveChatTransport: StylistChatTransport {
    private let configuration: StylistChatConfiguration
    private let session: URLSession
    private let accountSession: () -> StyleMatchAccountSession?
    private let appleAccountIsConnected: () -> Bool
    private let consentState: () -> AITransmissionConsentState

    init(
        configuration: StylistChatConfiguration,
        session: URLSession = .shared,
        accountSession: @escaping () -> StyleMatchAccountSession? = StyleMatchAccountSessionStore.load,
        appleAccountIsConnected: @escaping () -> Bool = { StyleMatchLocalAccountIdentity.isAppleConnected() },
        consentState: @escaping () -> AITransmissionConsentState = { AITransmissionConsentStore.shared.state }
    ) {
        self.configuration = configuration
        self.session = session
        self.accountSession = accountSession
        self.appleAccountIsConnected = appleAccountIsConnected
        self.consentState = consentState
#if DEBUG || OWNER_BETA
        let startupLine = "[StyleMatchChatCapture] startup route=chat diagnostics=enabled\n"
        FileHandle.standardOutput.write(Data(startupLine.utf8))
#endif
    }

    var resolvedBaseURL: URL {
        configuration.baseURL
    }

    var authorizationState: StylistChatAuthorizationState {
        guard let session = accountSession(), session.expiresAt > Date() else {
            return appleAccountIsConnected() ? .reconnectRequired : .signInRequired
        }
        return .authorized
    }

    var aiTransmissionConsentState: AITransmissionConsentState {
        consentState()
    }

    func send(_ request: ChatRequest) -> AsyncThrowingStream<String, Error> {
        if let validationError = StylistChatMessageLimit.validationError(for: request.messages) {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: validationError)
            }
        }
        guard aiTransmissionConsentState == .accepted else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: StylistChatError.aiTransmissionConsentRequired)
            }
        }
        return AsyncThrowingStream { continuation in
            let task = Task {
                let endpoint = configuration.baseURL.appendingPathComponent("v1/chat")
#if DEBUG || OWNER_BETA
                let captureID = UUID().uuidString
                let captureStart = Date()
                var dataLineCount = 0
                var tokenCount = 0
                var textBytes = 0
                var doneSeen = false
                var malformedCount = 0
                var unsupportedCount = 0
                let hostClass = configuration.baseURL.host == "api.stylematchpro.com" ? "production" : "staging_or_other"
                let contractClass = request.context.stylePreferences == nil ? "legacy" : "v2"
                let selectedFacts = request.context.authoritativeScan != nil || request.context.stylistFactContext != nil || request.context.stylePreferences != nil
                func record(_ outcome: String, status: Int?, contentType: String = "unknown") {
                    let elapsed = Int(Date().timeIntervalSince(captureStart) * 1000)
                    let line = "[StyleMatchChatCapture] attempt=\(captureID) elapsed_ms=\(elapsed) host=\(hostClass) route=chat contract=\(contractClass) messages=\(request.messages.count) scan=\(request.context.authoritativeScan != nil) selected_facts=\(selectedFacts) status=\(status ?? 0) content_type=\(contentType) data_lines=\(dataLineCount) tokens=\(tokenCount) text_bytes=\(textBytes) done=\(doneSeen) malformed=\(malformedCount) unsupported=\(unsupportedCount) oversized=0 streamed_errors=0 ray=unavailable transport=none provider=none outcome=\(outcome)\n"
                    FileHandle.standardOutput.write(Data(line.utf8))
                }
#endif
                do {
                    var urlRequest = try makeURLRequest(for: request)
                    urlRequest.httpBody = try JSONEncoder().encode(request)
                    let (bytes, response) = try await session.bytes(for: urlRequest)
                    if let http = response as? HTTPURLResponse,
                       Self.error(forHTTPStatusCode: http.statusCode) != nil {
#if DEBUG || OWNER_BETA
                        record("http_rejected", status: http.statusCode, contentType: Self.captureContentType(response))
#endif
                        let diagnostic = Self.diagnosticError(
                            forHTTPResponse: http
                        )
                        if diagnostic.category == .unauthorized {
                            StyleMatchAccountSessionStore.delete()
                        }
                        throw diagnostic
                    }

                    for try await line in bytes.lines {
#if DEBUG || OWNER_BETA
                        dataLineCount += 1
#endif
                        if Task.isCancelled { break }
                        guard let payload = Self.payload(from: line) else { continue }
                        if payload == "[DONE]" {
#if DEBUG || OWNER_BETA
                            doneSeen = true
#endif
                            break
                        }
                        if let token = Self.token(from: payload), !token.isEmpty {
#if DEBUG || OWNER_BETA
                            tokenCount += 1
                            textBytes += token.lengthOfBytes(using: .utf8)
#endif
                            continuation.yield(token)
                        } else if payload.first == "{" {
#if DEBUG || OWNER_BETA
                            unsupportedCount += 1
#endif
                        }
                    }
#if DEBUG || OWNER_BETA
                    record(tokenCount > 0 ? (doneSeen ? "text_done" : "text_eof") : "empty_stream", status: (response as? HTTPURLResponse)?.statusCode, contentType: Self.captureContentType(response))
#endif
                    continuation.finish()
                } catch {
#if DEBUG || OWNER_BETA
                    record(tokenCount > 0 ? "failed_after_text" : "failed_without_text", status: nil)
#endif
                    let mapped = Self.mappedError(error, endpoint: endpoint)
                    continuation.finish(throwing: mapped)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func sendVision(_ request: VisionChatRequestV1) -> AsyncThrowingStream<VisionChatResponseV1, Error> {
        guard authorizationState == .authorized else {
            return AsyncThrowingStream { $0.finish(throwing: StylistChatError.unauthorized) }
        }
        guard aiTransmissionConsentState == .accepted else {
            return AsyncThrowingStream { $0.finish(throwing: StylistVisionRequestError.consentRequired) }
        }
        return AsyncThrowingStream { continuation in
            let task = Task {
                let endpoint = configuration.baseURL.appendingPathComponent("v1/chat/vision")
                do {
                    var urlRequest = try makeURLRequest(for: ChatRequest(messages: [], context: ChatContext(), stream: false))
                    urlRequest.url = endpoint
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
                    urlRequest.httpBody = try JSONEncoder().encode(request)
                    let (data, response) = try await session.data(for: urlRequest)
                    guard let http = response as? HTTPURLResponse else { throw StylistVisionRequestError.providerUnavailable }
                    guard (200..<300).contains(http.statusCode) else { throw Self.visionError(status: http.statusCode, data: data) }
                    guard Self.hasStrictVisionResponseShape(data) else { throw StylistVisionRequestError.invalidResponse }
                    let decoded = try JSONDecoder().decode(VisionChatResponseV1.self, from: data)
                    guard Self.validVisionResponse(decoded, requestID: request.requestID) else { throw StylistVisionRequestError.invalidResponse }
                    continuation.yield(decoded)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func visionError(status: Int, data: Data) -> Error {
        struct Envelope: Decodable { let error: String }
        let code = (try? JSONDecoder().decode(Envelope.self, from: data))?.error
        switch code {
        case "vision_request_mismatch": return StylistVisionRequestError.requestMismatch
        case "vision_request_in_progress": return StylistVisionRequestError.requestInProgress
        case "vision_request_outcome_unknown", "vision_replay_suppressed": return StylistVisionRequestError.outcomeUnknown
        case "vision_image_not_allowed": return StylistVisionRequestError.imageNotAllowed
        case "vision_provider_refused": return StylistVisionRequestError.providerRefused
        case "vision_consent_required": return StylistVisionRequestError.consentRequired
        default:
            switch status {
            case 401: return StylistChatError.unauthorized
            case 409: return StylistVisionRequestError.outcomeUnknown
            default: return StylistVisionRequestError.providerUnavailable
            }
        }
    }

    private static func validVisionResponse(_ response: VisionChatResponseV1, requestID: String) -> Bool {
        let kinds: Set<String> = ["garment", "color", "pattern", "material", "fit", "coordination", "occasion"]
        let sources: Set<String> = ["selected_image", "selected_scan_facts", "style_preferences", "selected_closet_items"]
        return response.contractVersion == 1
            && response.requestID == requestID
            && !response.advice.isEmpty
            && response.advice.lengthOfBytes(using: .utf8) <= 4_000
            && response.observations.count <= 12
            && response.observations.allSatisfy {
                kinds.contains($0.kind)
                    && sources.contains($0.source)
                    && !$0.text.isEmpty
                    && $0.text.lengthOfBytes(using: .utf8) <= 160
                    && ($0.confidence.map { $0.isFinite && $0 >= 0 && $0 <= 1 } ?? true)
            }
    }

    /// `Decodable` deliberately ignores unknown keys. Vision V1 is an
    /// allowlisted contract, so reject any response field the client did not
    /// authorize before decoding it into UI state.
    private static func hasStrictVisionResponseShape(_ data: Data) -> Bool {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(root.keys) == ["contract_version", "request_id", "advice", "observations", "replayed"],
              let observations = root["observations"] as? [[String: Any]] else {
            return false
        }
        return observations.allSatisfy { observation in
            let keys = Set(observation.keys)
            return keys == ["kind", "text", "source"] || keys == ["kind", "text", "source", "confidence"]
        }
    }

    private func makeURLRequest(for request: ChatRequest) throws -> URLRequest {
        guard aiTransmissionConsentState == .accepted else {
            throw StylistChatError.aiTransmissionConsentRequired
        }
        let url = configuration.baseURL.appendingPathComponent("v1/chat")
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        guard let accountSession = accountSession(), accountSession.expiresAt > Date() else {
            throw StylistChatError.unauthorized
        }
        urlRequest.setValue("Bearer \(accountSession.token)", forHTTPHeaderField: "Authorization")
        return urlRequest
    }

    static func error(forHTTPStatusCode statusCode: Int) -> StylistChatError? {
        switch statusCode {
        case 200..<300: nil
        case 401: .unauthorized
        case 403: .aiTransmissionConsentRequired
        case 413: .payloadTooLarge
        case 429: .rateLimited
        case 400: .invalidRequest
        default: .providerError
        }
    }

    static func diagnosticError(
        forHTTPResponse response: HTTPURLResponse
    ) -> StylistChatDiagnosticError {
        StylistChatDiagnosticError(
            category: error(forHTTPStatusCode: response.statusCode) ?? .providerError,
            statusCode: response.statusCode,
            requestPhase: .response
        )
    }

    private static func payload(from line: String) -> String? {
        guard line.hasPrefix("data:") else { return nil }
        return line.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func token(from payload: String) -> String? {
        guard let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = object["choices"] as? [[String: Any]],
              let delta = choices.first?["delta"] as? [String: Any] else {
            return nil
        }
        return delta["content"] as? String
    }

#if DEBUG || OWNER_BETA
    private static func captureContentType(_ response: URLResponse) -> String {
        guard let mime = response.mimeType?.lowercased() else { return "unknown" }
        if mime.contains("event-stream") { return "SSE" }
        if mime.contains("json") { return "JSON" }
        if mime.contains("html") { return "HTML" }
        if mime.hasPrefix("text/") { return "text" }
        return "other"
    }
#endif

    private static func mappedError(_ error: Error, endpoint _: URL) -> Error {
        if error is StylistChatError || error is StylistChatDiagnosticError {
            return error
        }
        return StylistChatDiagnosticError(
            category: .network,
            statusCode: nil,
            requestPhase: .transport
        )
    }
}
