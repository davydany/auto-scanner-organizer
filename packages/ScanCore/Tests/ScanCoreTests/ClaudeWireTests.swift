import Foundation
import Testing
@testable import ScanCore

struct ClaudeWireTests {
    func encoded(_ value: some Encodable) throws -> String {
        try #require(String(data: try ClaudeWireJSON.encoder().encode(value), encoding: .utf8))
    }

    @Test func encodesAStructuredOutputRequestWithSortedExplicitKeys() throws {
        let request = MessagesRequest(
            model: "claude-sonnet-5", maxTokens: 16000,
            system: [.text("Rules", cacheControl: .ephemeral)],
            messages: [Message(role: .user, content: [.text("Page 1:"), .image(mediaType: "image/jpeg", base64Data: "AAAA")])],
            outputConfig: .jsonSchema(.object(["type": .string("object"), "additionalProperties": .bool(false)]))
        )
        let expected = #"{"max_tokens":16000,"messages":[{"content":[{"text":"Page 1:","type":"text"},"#
            + #"{"source":{"data":"AAAA","media_type":"image/jpeg","type":"base64"},"type":"image"}],"role":"user"}],"#
            + #""model":"claude-sonnet-5","output_config":{"format":{"schema":{"additionalProperties":false,"type":"object"},"#
            + #""type":"json_schema"}},"system":[{"cache_control":{"type":"ephemeral"},"text":"Rules","type":"text"}]}"#
        #expect(try encoded(request) == expected)
    }

    @Test func encodesToolsToolChoiceAndToolResults() throws {
        let request = MessagesRequest(
            model: "claude-opus-5", maxTokens: 4096,
            messages: [
                Message(role: .assistant, content: [
                    .thinking(thinking: "", signature: "sig=="),
                    .toolUse(id: "toolu_1", name: "list_folder", input: .object(["path": .string("Personal")])),
                ]),
                Message(role: .user, content: [
                    .toolResult(toolUseID: "toolu_1", content: "Error: not a folder", isError: true),
                    .toolResult(toolUseID: "toolu_2", content: "ok"),
                ]),
            ],
            tools: [ToolDefinition(name: "submit_placement", description: "Final answer.", inputSchema: .object(["type": .string("object")]), strict: true)],
            toolChoice: .tool("submit_placement")
        )
        let json = try encoded(request)
        #expect(json.contains(#"{"signature":"sig==","thinking":"","type":"thinking"}"#))
        #expect(json.contains(#"{"id":"toolu_1","input":{"path":"Personal"},"name":"list_folder","type":"tool_use"}"#))
        #expect(json.contains(#"{"content":"Error: not a folder","is_error":true,"tool_use_id":"toolu_1","type":"tool_result"}"#))
        #expect(json.contains(#"{"content":"ok","tool_use_id":"toolu_2","type":"tool_result"}"#))
        #expect(json.contains(#""tool_choice":{"name":"submit_placement","type":"tool"}"#))
        #expect(json.contains(#""tools":[{"description":"Final answer.","input_schema":{"type":"object"},"name":"submit_placement","strict":true}]"#))
        #expect(!json.contains("output_config"))
        #expect(!json.contains("\"system\""))
    }

    @Test func decodesAToolUseResponseWithThinkingAndCacheUsage() throws {
        let json = """
        {"id":"msg_01","type":"message","role":"assistant","model":"claude-sonnet-5",
         "content":[{"type":"thinking","thinking":"","signature":"abc"},
                    {"type":"text","text":"Checking folders."},
                    {"type":"tool_use","id":"toolu_9","name":"read_note","input":{"path":"Personal/a b.md","depth":2,"deep":{"k":[true,null]}}}],
         "stop_reason":"tool_use","stop_sequence":null,"stop_details":null,
         "usage":{"input_tokens":512,"output_tokens":40,"cache_creation_input_tokens":0,"cache_read_input_tokens":800,
                  "cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":0}}}
        """
        let response = try ClaudeWireJSON.decoder().decode(MessagesResponse.self, from: Data(json.utf8))
        #expect(response.stopReason == .toolUse)
        #expect(response.stopDetails == nil)
        #expect(response.usage == Usage(inputTokens: 512, outputTokens: 40, cacheCreationInputTokens: 0, cacheReadInputTokens: 800))
        #expect(response.content == [
            .thinking(thinking: "", signature: "abc"),
            .text("Checking folders."),
            .toolUse(id: "toolu_9", name: "read_note", input: .object([
                "path": .string("Personal/a b.md"), "depth": .number(2),
                "deep": .object(["k": .array([.bool(true), .null])]),
            ])),
        ])
        struct ReadNoteInput: Decodable { let path: String }
        if case .toolUse(_, _, let input) = response.content[2] {
            #expect(try input.decode(as: ReadNoteInput.self).path == "Personal/a b.md")
        }
    }

    @Test func decodesARefusalWithEmptyContentAndMissingCacheFields() throws {
        let json = """
        {"id":"msg_02","type":"message","role":"assistant","model":"claude-opus-5","content":[],
         "stop_reason":"refusal","stop_details":{"type":"refusal","category":null,"explanation":"Declined."},
         "usage":{"input_tokens":0,"output_tokens":0}}
        """
        let response = try ClaudeWireJSON.decoder().decode(MessagesResponse.self, from: Data(json.utf8))
        #expect(response.stopReason == .refusal)
        #expect(response.stopDetails == StopDetails(type: "refusal", category: nil, explanation: "Declined."))
        #expect(response.content.isEmpty)
        #expect(response.usage == .zero)
    }

    @Test func keepsUnknownBlocksVerbatimForEcho() throws {
        let block = #"{"id":"srvtoolu_1","input":{"query":"x"},"name":"web_search","type":"server_tool_use"}"#
        let decoded = try ClaudeWireJSON.decoder().decode(ContentBlock.self, from: Data(block.utf8))
        guard case .other = decoded else {
            Issue.record("expected .other, got \(decoded)")
            return
        }
        #expect(try encoded(decoded) == block)
        #expect(StopReason(rawValue: "brand_new_reason").rawValue == "brand_new_reason")
    }

    @Test func roundTripsToolResultAndImageBlocksThroughEncodeAndDecode() throws {
        let blocks: [ContentBlock] = [
            .toolResult(toolUseID: "t1", content: "Error: nope", isError: true),
            .toolResult(toolUseID: "t2", content: "ok"),
            .image(mediaType: "image/jpeg", base64Data: "AAAA"),
        ]
        for block in blocks {
            let data = try ClaudeWireJSON.encoder().encode(block)
            let decoded = try ClaudeWireJSON.decoder().decode(ContentBlock.self, from: data)
            #expect(decoded == block)
        }
        #expect(StopReason.stopSequence.rawValue == "stop_sequence")
    }

    @Test func decodesAPIErrorBodiesAndPreservesSnakeCaseKeysInJSONValues() throws {
        let body = #"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"},"request_id":"req_1"}"#
        let error = try ClaudeWireJSON.decoder().decode(APIErrorBody.self, from: Data(body.utf8))
        #expect(error.error == APIErrorBody.Detail(type: "overloaded_error", message: "Overloaded"))

        let schema = try ClaudeWireJSON.decoder().decode(JSONValue.self, from: Data(#"{"split_confidence":{"type":"number"}}"#.utf8))
        #expect(schema == .object(["split_confidence": .object(["type": .string("number")])]))
        #expect(try encoded(schema) == #"{"split_confidence":{"type":"number"}}"#)
    }
}
