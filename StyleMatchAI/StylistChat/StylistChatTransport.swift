import CryptoKit
import Foundation
#if canImport(UIKit)
import UIKit
#endif

protocol StylistChatTransport {
    var authorizationState: StylistChatAuthorizationState { get }
    func send(_ request: ChatRequest) -> AsyncThrowingStream<String, Error>
}

enum StylistChatAuthorizationState: Equatable {
    case authorized
    case signInRequired
    case reconnectRequired
}

extension StylistChatTransport {
    var authorizationState: StylistChatAuthorizationState { .authorized }
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

    init(
        configuration: StylistChatConfiguration,
        session: URLSession = .shared,
        accountSession: @escaping () -> StyleMatchAccountSession? = StyleMatchAccountSessionStore.load,
        appleAccountIsConnected: @escaping () -> Bool = { StyleMatchLocalAccountIdentity.isAppleConnected() }
    ) {
        self.configuration = configuration
        self.session = session
        self.accountSession = accountSession
        self.appleAccountIsConnected = appleAccountIsConnected
    }

    var authorizationState: StylistChatAuthorizationState {
        guard let session = accountSession(), session.expiresAt > Date() else {
            return appleAccountIsConnected() ? .reconnectRequired : .signInRequired
        }
        return .authorized
    }

    func send(_ request: ChatRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let endpoint = configuration.baseURL.appendingPathComponent("v1/chat")
                do {
                    if let validationError = StylistChatMessageLimit.validationError(for: request.messages) {
                        throw validationError
                    }
                    var urlRequest = try makeURLRequest(for: request)
                    urlRequest.httpBody = try JSONEncoder().encode(request)
                    let (bytes, response) = try await session.bytes(for: urlRequest)
                    if let http = response as? HTTPURLResponse,
                       Self.error(forHTTPStatusCode: http.statusCode) != nil {
                        let body = try await Self.responseBody(from: bytes)
                        let diagnostic = Self.diagnosticError(
                            forHTTPResponse: http,
                            responseBody: body,
                            endpoint: endpoint
                        )
                        if diagnostic.category == .unauthorized {
                            StyleMatchAccountSessionStore.delete()
                        }
                        #if DEBUG
                        print("[Stylist Chat HTTP] \(diagnostic.debugDescription)")
                        #endif
                        throw diagnostic
                    }

                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        guard let payload = Self.payload(from: line) else { continue }
                        if payload == "[DONE]" {
                            break
                        }
                        if let token = Self.token(from: payload), !token.isEmpty {
                            continuation.yield(token)
                        }
                    }
                    continuation.finish()
                } catch {
                    let mapped = Self.mappedError(error, endpoint: endpoint)
                    #if DEBUG
                    if let diagnostic = mapped as? StylistChatDiagnosticError {
                        print("[Stylist Chat Transport] \(diagnostic.debugDescription)")
                    }
                    #endif
                    continuation.finish(throwing: mapped)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func makeURLRequest(for request: ChatRequest) throws -> URLRequest {
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
        case 413: .payloadTooLarge
        case 429: .rateLimited
        case 400: .invalidRequest
        default: .providerError
        }
    }

    static func diagnosticError(
        forHTTPResponse response: HTTPURLResponse,
        responseBody: String?,
        endpoint: URL,
        underlyingErrorDescription: String? = nil
    ) -> StylistChatDiagnosticError {
        StylistChatDiagnosticError(
            category: error(forHTTPStatusCode: response.statusCode) ?? .providerError,
            statusCode: response.statusCode,
            responseBody: responseBody,
            requestID: requestID(from: response),
            endpoint: endpoint,
            underlyingErrorDescription: underlyingErrorDescription
        )
    }

    private static func requestID(from response: HTTPURLResponse) -> String? {
        for header in ["x-request-id", "request-id", "openai-request-id", "cf-ray"] {
            if let value = response.value(forHTTPHeaderField: header)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func responseBody(from bytes: URLSession.AsyncBytes, limit: Int = 8_192) async throws -> String? {
        var data = Data()
        data.reserveCapacity(limit)
        for try await byte in bytes {
            guard data.count < limit else { break }
            data.append(byte)
        }
        guard !data.isEmpty else { return nil }
        return String(data: data, encoding: .utf8)
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

    private static func mappedError(_ error: Error, endpoint: URL) -> Error {
        if error is StylistChatError || error is StylistChatDiagnosticError {
            return error
        }
        return StylistChatDiagnosticError(
            category: .network,
            statusCode: nil,
            responseBody: nil,
            requestID: nil,
            endpoint: endpoint,
            underlyingErrorDescription: String(describing: error)
        )
    }
}
