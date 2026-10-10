import Foundation

enum AskStyleMatchV2TransportError: Error, Equatable {
    case unauthorized
    case consentRequired
    case idempotencyConflict
    case requestInProgress
    case requestAlreadyCompleted
    case invalidRequest
    case unavailable
}

/// Authenticated V2 transport. It owns no provider credential and streams the
/// established `/v1/chat` SSE framing without persisting user content.
struct AskStyleMatchV2Transport {
    private let baseURL: URL
    private let session: URLSession
    private let accountSession: () -> StyleMatchAccountSession?
    private let consentState: () -> AITransmissionConsentState

    init(baseURL: URL? = nil, session: URLSession = .shared, accountSession: @escaping () -> StyleMatchAccountSession? = StyleMatchAccountSessionStore.load, consentState: @escaping () -> AITransmissionConsentState = { AITransmissionConsentStore.shared.state }) {
        self.baseURL = baseURL ?? StyleMatchRuntimeEndpoint.accountResolution()?.baseURL ?? AppBackendConfiguration.production().apiBaseURL
        self.session = session
        self.accountSession = accountSession
        self.consentState = consentState
    }

    func send(_ request: AskStyleMatchRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard consentState() == .accepted else { throw AskStyleMatchV2TransportError.consentRequired }
                    guard let account = accountSession(), account.expiresAt > Date() else { throw AskStyleMatchV2TransportError.unauthorized }
                    let payload = try AskStyleMatchV2WireRequest(request: request)
                    var outbound = URLRequest(url: baseURL.appendingPathComponent("v1/chat"))
                    outbound.httpMethod = "POST"
                    outbound.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    outbound.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    outbound.setValue("Bearer \(account.token)", forHTTPHeaderField: "Authorization")
                    outbound.httpBody = try JSONEncoder().encode(payload)
                    let (bytes, response) = try await session.bytes(for: outbound)
                    guard let http = response as? HTTPURLResponse else { throw AskStyleMatchV2TransportError.unavailable }
                    guard (200..<300).contains(http.statusCode) else { throw Self.error(status: http.statusCode) }
                    for try await line in bytes.lines where !Task.isCancelled {
                        guard line.hasPrefix("data:") else { continue }
                        let body = line.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
                        if body == "[DONE]" { break }
                        guard let data = body.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let choices = json["choices"] as? [[String: Any]],
                              let delta = choices.first?["delta"] as? [String: Any],
                              let content = delta["content"] as? String else { continue }
                        continuation.yield(content)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func error(status: Int) -> AskStyleMatchV2TransportError {
        switch status {
        case 401: .unauthorized
        case 403: .consentRequired
        case 409: .idempotencyConflict
        case 425: .requestInProgress
        case 410: .requestAlreadyCompleted
        case 400, 413: .invalidRequest
        default: .unavailable
        }
    }
}
