import Foundation
@testable import ScanCore

/// Returns scripted Messages API responses in order and records every request.
actor ScriptedClaude: ClaudeMessaging {
    enum Step: Sendable {
        case respond(MessagesResponse)
        case fail(ClaudeError)
    }

    private var steps: [Step]
    private(set) var requests: [MessagesRequest] = []

    init(_ steps: [Step]) {
        self.steps = steps
    }

    func send(_ request: MessagesRequest) async throws -> MessagesResponse {
        requests.append(request)
        guard !steps.isEmpty else { throw ClaudeError.invalidResponse("no scripted response left") }
        switch steps.removeFirst() {
        case .respond(let response): return response
        case .fail(let error): throw error
        }
    }

    static let defaultUsage = Usage(inputTokens: 1000, outputTokens: 100)

    static func text(_ text: String, stop: StopReason = .endTurn, usage: Usage = defaultUsage) -> Step {
        .respond(MessagesResponse(id: "msg_text", model: "claude-sonnet-5", content: [.thinking(thinking: "", signature: "sig"), .text(text)],
                                  stopReason: stop, usage: usage))
    }

    static func refusal(_ category: String?) -> Step {
        .respond(MessagesResponse(id: "msg_refusal", model: "claude-sonnet-5", content: [], stopReason: .refusal,
                                  stopDetails: StopDetails(type: "refusal", category: category, explanation: nil), usage: .zero))
    }

    struct ToolCall: Sendable {
        let id: String
        let name: String
        let input: JSONValue
    }

    static func toolUse(_ calls: [ToolCall], usage: Usage = defaultUsage) -> Step {
        .respond(MessagesResponse(id: "msg_tools", model: "claude-sonnet-5",
                                  content: calls.map { ContentBlock.toolUse(id: $0.id, name: $0.name, input: $0.input) },
                                  stopReason: .toolUse, usage: usage))
    }

    static func fail(_ error: ClaudeError) -> Step {
        .fail(error)
    }
}
