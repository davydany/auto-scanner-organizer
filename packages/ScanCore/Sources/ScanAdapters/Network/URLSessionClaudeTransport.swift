import Foundation
import ScanCore

/// Sends Messages API requests with URLSession. Timeouts are long because Sonnet 5 and Opus 5 think before
/// answering and responses are not streamed (API reference §10, gotcha 7).
public struct URLSessionClaudeTransport: ClaudeTransport {
    static let endpoint = "https://api.anthropic.com/v1/messages"

    private let session: URLSession

    public init(session: URLSession = URLSessionClaudeTransport.makeSession()) {
        self.session = session
    }

    public static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 600
        configuration.timeoutIntervalForResource = 900
        return URLSession(configuration: configuration)
    }

    public func post(body: Data, headers: [String: String]) async throws -> HTTPReply {
        guard let url = URL(string: Self.endpoint) else { throw ClaudeTransportError.network("Invalid endpoint") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw ClaudeTransportError.network("Response was not HTTP") }
            var lowercased: [String: String] = [:]
            for (key, value) in http.allHeaderFields {
                if let key = key as? String, let value = value as? String {
                    lowercased[key.lowercased()] = value
                }
            }
            return HTTPReply(status: http.statusCode, headers: lowercased, body: data)
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw ClaudeTransportError.network(error.localizedDescription)
        }
    }
}
