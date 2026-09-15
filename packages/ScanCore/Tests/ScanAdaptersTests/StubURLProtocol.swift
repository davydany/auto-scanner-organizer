import Foundation
import Synchronization

/// Answers URLSession requests from a queue of stubs (Milestone 2 probe E). Tests using it must be `.serialized`.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    enum Stub: Sendable {
        case reply(status: Int, headers: [String: String], body: Data)
        case failure(URLError)
    }

    struct Captured: Sendable {
        var url: URL?
        var method: String?
        var headers: [String: String]
        var body: Data
    }

    private struct State {
        var stubs: [Stub] = []
        var captured: [Captured] = []
    }

    private static let state = Mutex(State())

    static func reset() {
        state.withLock { $0 = State() }
    }

    static func enqueue(_ stub: Stub) {
        state.withLock { $0.stubs.append(stub) }
    }

    static var captured: [Captured] {
        state.withLock { $0.captured }
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override static func canInit(with request: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let captured = Captured(url: request.url, method: request.httpMethod, headers: request.allHTTPHeaderFields ?? [:],
                                body: Self.body(of: request))
        let stub = Self.state.withLock { state -> Stub? in
            state.captured.append(captured)
            return state.stubs.isEmpty ? nil : state.stubs.removeFirst()
        }
        switch stub {
        case let .reply(status, headers, body):
            guard let url = request.url,
                  let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)
            else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        case nil:
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
        }
    }

    override func stopLoading() {}

    /// URLSession delivers the body as a stream inside URLProtocol, not as `httpBody` (probe E).
    private static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
