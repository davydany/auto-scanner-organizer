import Foundation
import Testing
@testable import ScanAdapters
@testable import ScanCore

@Suite(.serialized)
struct URLSessionClaudeTransportTests {
    init() {
        StubURLProtocol.reset()
    }

    @Test func postsToTheMessagesEndpointAndLowercasesResponseHeaders() async throws {
        StubURLProtocol.enqueue(.reply(status: 429, headers: ["Retry-After": "3", "Content-Type": "application/json"], body: Data("{}".utf8)))
        let transport = URLSessionClaudeTransport(session: StubURLProtocol.makeSession())
        let body = Data(#"{"model":"claude-sonnet-5"}"#.utf8)

        let reply = try await transport.post(body: body, headers: ["x-api-key": "sk-test", "anthropic-version": "2023-06-01", "content-type": "application/json"])

        #expect(reply.status == 429)
        #expect(reply.headers["retry-after"] == "3")
        #expect(reply.body == Data("{}".utf8))
        let captured = try #require(StubURLProtocol.captured.first)
        #expect(captured.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(captured.method == "POST")
        #expect(captured.headers["x-api-key"] == "sk-test")
        #expect(captured.headers["anthropic-version"] == "2023-06-01")
        #expect(captured.body == body)
    }

    @Test func mapsURLErrorsToNetworkFailures() async throws {
        StubURLProtocol.enqueue(.failure(URLError(.notConnectedToInternet)))
        let transport = URLSessionClaudeTransport(session: StubURLProtocol.makeSession())

        await #expect(throws: ClaudeTransportError.self) { try await transport.post(body: Data(), headers: [:]) }
    }
}
