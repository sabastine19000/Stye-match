import CryptoKit
import Foundation
#if canImport(UIKit)
import UIKit
#endif

protocol StylistChatTransport {
    func send(_ request: ChatRequest) -> AsyncThrowingStream<String, Error>
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

    init(
        configuration: StylistChatConfiguration,
        session: URLSession = .shared,
        accountSession: @escaping () -> StyleMatchAccountSession? = StyleMatchAccountSessionStore.load
    ) {
        self.configuration = configuration
        self.session = session
        self.accountSession = accountSession
    }

    func send(_ request: ChatRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var urlRequest = try makeURLRequest(for: request)
                    urlRequest.httpBody = try JSONEncoder().encode(request)
                    let (bytes, response) = try await session.bytes(for: urlRequest)
                    try validate(response: response)

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
                    continuation.finish(throwing: Self.mappedError(error))
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

    private func validate(response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        switch http.statusCode {
        case 200..<300:
            return
        case 401:
            throw StylistChatError.unauthorized
        case 413:
            throw StylistChatError.payloadTooLarge
        case 429:
            throw StylistChatError.rateLimited
        case 400:
            throw StylistChatError.invalidRequest
        default:
            throw StylistChatError.providerError
        }
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

    private static func mappedError(_ error: Error) -> Error {
        if let chatError = error as? StylistChatError {
            return chatError
        }
        return StylistChatError.network
    }
}
