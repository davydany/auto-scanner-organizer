import Foundation

public enum PlacementOutcome: Sendable, Equatable {
    case placed(Placement)
    case refused(category: String)
    case invalid(messages: [String])
}

public struct PlacementResult: Sendable, Equatable {
    public var outcome: PlacementOutcome
    public var usage: Usage
    public var toolCalls: Int

    public init(outcome: PlacementOutcome, usage: Usage, toolCalls: Int) {
        self.outcome = outcome
        self.usage = usage
        self.toolCalls = toolCalls
    }
}

/// Step 2 of spec §8: read-only vault tools, then one strict `submit_placement` call.
public struct PlacementAgent: Sendable {
    public static let maxToolCalls = 8
    public static let maxTokens = 4096
    /// A safety stop for the loop; normal placements finish in two to five requests.
    public static let maxRequests = 12

    private let claude: any ClaudeMessaging
    private let model: ClaudeModel
    private let vaultIndex: String
    private let tools: VaultTools
    private let validator: PlacementValidator

    private struct ToolCall {
        let id: String
        let name: String
        let input: JSONValue
    }

    public init(claude: any ClaudeMessaging, model: ClaudeModel, vaultRoot: URL, vaultIndex: String,
                fileSystem: any FileSystem = LocalFileSystem()) {
        self.claude = claude
        self.model = model
        self.vaultIndex = vaultIndex
        tools = VaultTools(vaultRoot: vaultRoot, fileSystem: fileSystem)
        validator = PlacementValidator(vaultRoot: vaultRoot, fileSystem: fileSystem)
    }

    public func place(_ document: DocumentAnalysis, purpose: String?) async throws -> PlacementResult {
        var messages = [Message(role: .user, content: [.text(PlacementPrompt.userMessage(for: document, purpose: purpose))])]
        var usage = Usage.zero
        var toolCalls = 0
        var nudged = false
        var corrected = false

        func finish(_ outcome: PlacementOutcome) -> PlacementResult {
            PlacementResult(outcome: outcome, usage: usage, toolCalls: toolCalls)
        }

        for _ in 0..<Self.maxRequests {
            let response = try await claude.send(request(messages, forceSubmit: nudged || toolCalls >= Self.maxToolCalls))
            usage += response.usage
            if response.stopReason == .refusal {
                return finish(.refused(category: response.stopDetails?.category ?? "unspecified"))
            }
            let calls = response.content.compactMap { block -> ToolCall? in
                if case let .toolUse(id, name, input) = block { return ToolCall(id: id, name: name, input: input) }
                return nil
            }
            guard !calls.isEmpty else {
                if nudged { return finish(.invalid(messages: ["Claude did not call submit_placement."])) }
                nudged = true
                let nudge = ContentBlock.text("Call submit_placement now with your best placement.")
                if response.content.isEmpty {
                    messages[messages.count - 1].content.append(nudge)
                } else {
                    messages.append(Message(role: .assistant, content: response.content))
                    messages.append(Message(role: .user, content: [nudge]))
                }
                continue
            }
            messages.append(Message(role: .assistant, content: response.content))
            var results: [ContentBlock] = []
            for call in calls {
                if call.name == PlacementPrompt.submitToolName {
                    switch validator.validate(call.input) {
                    case .success(let placement):
                        return finish(.placed(placement))
                    case .failure(let failure):
                        if corrected { return finish(.invalid(messages: failure.messages)) }
                        corrected = true
                        results.append(.toolResult(toolUseID: call.id, content: PlacementPrompt.correction(failure.messages), isError: true))
                    }
                } else if toolCalls >= Self.maxToolCalls {
                    results.append(.toolResult(toolUseID: call.id, content: "Error: the limit of 8 tool calls is reached. Call submit_placement now.",
                                               isError: true))
                } else {
                    toolCalls += 1
                    let output = tools.run(name: call.name, input: call.input)
                    results.append(.toolResult(toolUseID: call.id, content: output.content, isError: output.isError))
                }
            }
            messages.append(Message(role: .user, content: results))
        }
        return finish(.invalid(messages: ["Placement did not finish within \(Self.maxRequests) requests."]))
    }

    private func request(_ messages: [Message], forceSubmit: Bool) -> MessagesRequest {
        MessagesRequest(model: model.rawValue, maxTokens: Self.maxTokens,
                        system: [.text(PlacementPrompt.system), PlacementPrompt.indexBlock(vaultIndex)],
                        messages: messages, tools: VaultTools.definitions + [PlacementPrompt.submitDefinition],
                        toolChoice: forceSubmit ? .tool(PlacementPrompt.submitToolName) : .auto)
    }
}
