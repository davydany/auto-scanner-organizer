import Foundation

/// An HTTP response from the Messages endpoint. Header names are lowercased.
public struct HTTPReply: Sendable, Equatable {
    public var status: Int
    public var headers: [String: String]
    public var body: Data

    public init(status: Int, headers: [String: String], body: Data) {
        self.status = status
        self.headers = headers
        self.body = body
    }
}

public enum ClaudeTransportError: Error, Equatable, Sendable {
    /// No HTTP response arrived (offline, timeout, connection reset).
    case network(String)
}

/// Posts a JSON body to `POST https://api.anthropic.com/v1/messages`. The URLSession adapter lives in ScanAdapters.
public protocol ClaudeTransport: Sendable {
    func post(body: Data, headers: [String: String]) async throws -> HTTPReply
}

public enum ClaudeError: Error, Equatable, Sendable {
    case missingAPIKey
    case http(status: Int, type: String, message: String)
    case network(String)
    case invalidResponse(String)
}

/// What the analysis steps need from Claude; tests substitute a scripted fake.
public protocol ClaudeMessaging: Sendable {
    func send(_ request: MessagesRequest) async throws -> MessagesResponse
}

/// Sends Messages API requests with the spec §8.1 retry policy (API reference §5).
public struct ClaudeClient: ClaudeMessaging {
    public static let apiVersion = "2023-06-01"
    public static let maxRetries = 3
    static let maxRetryAfterSeconds = 60.0

    private let apiKey: String
    private let transport: any ClaudeTransport
    private let sleep: @Sendable (Duration) async throws -> Void

    public init(apiKey: String, transport: any ClaudeTransport,
                sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.apiKey = apiKey
        self.transport = transport
        self.sleep = sleep
    }

    public func send(_ request: MessagesRequest) async throws -> MessagesResponse {
        guard !apiKey.isEmpty else { throw ClaudeError.missingAPIKey }
        let body = try ClaudeWireJSON.encoder().encode(request)
        let headers = ["content-type": "application/json", "x-api-key": apiKey, "anthropic-version": Self.apiVersion]
        var retries = 0
        while true {
            let reply: HTTPReply
            do {
                reply = try await transport.post(body: body, headers: headers)
            } catch ClaudeTransportError.network(let message) {
                guard retries < Self.maxRetries else { throw ClaudeError.network(message) }
                try await sleep(Self.backoff(retries))
                retries += 1
                continue
            }
            if reply.status == 200 {
                do {
                    return try ClaudeWireJSON.decoder().decode(MessagesResponse.self, from: reply.body)
                } catch {
                    throw ClaudeError.invalidResponse(String(describing: error))
                }
            }
            guard Self.isRetryable(reply.status), retries < Self.maxRetries else { throw Self.error(from: reply) }
            try await sleep(Self.retryAfter(reply) ?? Self.backoff(retries))
            retries += 1
        }
    }

    static func isRetryable(_ status: Int) -> Bool {
        status == 408 || status == 409 || status == 429 || (500...599).contains(status)
    }

    static func backoff(_ retries: Int) -> Duration {
        .seconds(1 << retries)
    }

    static func retryAfter(_ reply: HTTPReply) -> Duration? {
        guard let value = reply.headers["retry-after"], let seconds = Double(value), seconds.isFinite, seconds >= 0 else { return nil }
        return .milliseconds(Int(min(seconds, maxRetryAfterSeconds) * 1000))
    }

    static func error(from reply: HTTPReply) -> ClaudeError {
        if let body = try? ClaudeWireJSON.decoder().decode(APIErrorBody.self, from: reply.body) {
            return .http(status: reply.status, type: body.error.type, message: body.error.message)
        }
        let text = String(data: reply.body.prefix(200), encoding: .utf8) ?? ""
        return .http(status: reply.status, type: "unknown", message: text)
    }
}
