import Foundation
import Testing
@testable import ScanCore

actor FakeClaudeTransport: ClaudeTransport {
    enum Outcome: Sendable {
        case reply(HTTPReply)
        case networkFailure(String)
    }

    private var outcomes: [Outcome]
    private(set) var bodies: [Data] = []
    private(set) var headers: [[String: String]] = []

    init(_ outcomes: [Outcome]) {
        self.outcomes = outcomes
    }

    func post(body: Data, headers: [String: String]) async throws -> HTTPReply {
        bodies.append(body)
        self.headers.append(headers)
        guard !outcomes.isEmpty else { throw ClaudeTransportError.network("no stubbed outcome") }
        switch outcomes.removeFirst() {
        case .reply(let reply): return reply
        case .networkFailure(let message): throw ClaudeTransportError.network(message)
        }
    }
}

actor SleepRecorder {
    private(set) var durations: [Duration] = []

    func record(_ duration: Duration) {
        durations.append(duration)
    }
}

struct ClaudeClientTests {
    static let okBody = #"{"id":"msg_1","type":"message","role":"assistant","model":"claude-sonnet-5","#
        + #""content":[{"type":"text","text":"hi"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":1}}"#
    let request = MessagesRequest(model: "claude-sonnet-5", maxTokens: 16, messages: [Message(role: .user, content: [.text("hello")])])

    func reply(_ status: Int, _ body: String = okBody, headers: [String: String] = [:]) -> FakeClaudeTransport.Outcome {
        .reply(HTTPReply(status: status, headers: headers, body: Data(body.utf8)))
    }

    func errorBody(_ type: String) -> String {
        #"{"type":"error","error":{"type":"\#(type)","message":"boom"}}"#
    }

    func client(_ transport: FakeClaudeTransport, _ recorder: SleepRecorder, apiKey: String = "sk-test") -> ClaudeClient {
        ClaudeClient(apiKey: apiKey, transport: transport, sleep: { await recorder.record($0) })
    }

    @Test func sendsTheRequiredHeadersAndDecodesTheResponse() async throws {
        let transport = FakeClaudeTransport([reply(200)])
        let recorder = SleepRecorder()

        let response = try await client(transport, recorder).send(request)

        #expect(response.content == [.text("hi")])
        #expect(await transport.headers == [["content-type": "application/json", "x-api-key": "sk-test", "anthropic-version": "2023-06-01"]])
        #expect(await transport.bodies == [try ClaudeWireJSON.encoder().encode(request)])
        #expect(await recorder.durations.isEmpty)
    }

    @Test func retriesRetryableStatusesAndRespectsRetryAfter() async throws {
        let transport = FakeClaudeTransport([
            reply(429, errorBody("rate_limit_error"), headers: ["retry-after": "7"]),
            reply(529, errorBody("overloaded_error")),
            reply(200),
        ])
        let recorder = SleepRecorder()

        _ = try await client(transport, recorder).send(request)

        #expect(await transport.bodies.count == 3)
        #expect(await recorder.durations == [.seconds(7), .seconds(2)])
    }

    @Test func givesUpAfterThreeRetries() async throws {
        let transport = FakeClaudeTransport(Array(repeating: reply(500, errorBody("api_error")), count: 5))
        let recorder = SleepRecorder()

        await #expect(throws: ClaudeError.http(status: 500, type: "api_error", message: "boom")) {
            try await client(transport, recorder).send(request)
        }
        #expect(await transport.bodies.count == 4)
        #expect(await recorder.durations == [.seconds(1), .seconds(2), .seconds(4)])
    }

    @Test(arguments: [400, 401, 403, 404, 413])
    func failsFastOnNonRetryableStatuses(_ status: Int) async throws {
        let transport = FakeClaudeTransport([reply(status, errorBody("invalid_request_error")), reply(200)])
        let recorder = SleepRecorder()

        await #expect(throws: ClaudeError.http(status: status, type: "invalid_request_error", message: "boom")) {
            try await client(transport, recorder).send(request)
        }
        #expect(await transport.bodies.count == 1)
        #expect(await recorder.durations.isEmpty)
    }

    @Test func retriesNetworkFailuresAndCapsRetryAfter() async throws {
        let transport = FakeClaudeTransport([.networkFailure("offline"), reply(503, "<html>", headers: ["retry-after": "600"]), reply(200)])
        let recorder = SleepRecorder()

        _ = try await client(transport, recorder).send(request)

        #expect(await recorder.durations == [.seconds(1), .seconds(60)])
    }

    @Test func reportsNetworkFailureAfterRetriesAndUnparseableBodies() async throws {
        let offline = FakeClaudeTransport(Array(repeating: .networkFailure("offline"), count: 4))
        await #expect(throws: ClaudeError.network("offline")) { try await client(offline, SleepRecorder()).send(request) }

        let garbage = FakeClaudeTransport([reply(200, "not json")])
        await #expect(throws: ClaudeError.self) { try await client(garbage, SleepRecorder()).send(request) }

        let unknownError = FakeClaudeTransport([reply(418, "teapot")])
        await #expect(throws: ClaudeError.http(status: 418, type: "unknown", message: "teapot")) {
            try await client(unknownError, SleepRecorder()).send(request)
        }
    }

    @Test func refusesToSendWithoutAnAPIKey() async throws {
        let transport = FakeClaudeTransport([reply(200)])
        await #expect(throws: ClaudeError.missingAPIKey) { try await client(transport, SleepRecorder(), apiKey: "").send(request) }
        #expect(await transport.bodies.isEmpty)
    }
}
