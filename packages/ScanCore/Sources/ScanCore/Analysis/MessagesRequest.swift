import Foundation

public struct CacheControl: Codable, Sendable, Equatable {
    public var type: String

    public static let ephemeral = CacheControl(type: "ephemeral")
}

public struct Message: Codable, Sendable, Equatable {
    public enum Role: String, Codable, Sendable {
        case user, assistant
    }

    public var role: Role
    public var content: [ContentBlock]

    public init(role: Role, content: [ContentBlock]) {
        self.role = role
        self.content = content
    }
}

public struct ToolDefinition: Codable, Sendable, Equatable {
    public var name: String
    public var description: String
    public var inputSchema: JSONValue
    public var strict: Bool?

    public init(name: String, description: String, inputSchema: JSONValue, strict: Bool? = nil) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
        self.strict = strict
    }

    enum CodingKeys: String, CodingKey {
        case name, description, strict
        case inputSchema = "input_schema"
    }
}

public struct ToolChoice: Codable, Sendable, Equatable {
    public var type: String
    public var name: String?

    public static let auto = ToolChoice(type: "auto", name: nil)

    public static func tool(_ name: String) -> ToolChoice {
        ToolChoice(type: "tool", name: name)
    }
}

public struct OutputConfig: Codable, Sendable, Equatable {
    public struct Format: Codable, Sendable, Equatable {
        public var type: String
        public var schema: JSONValue
    }

    public var format: Format

    public static func jsonSchema(_ schema: JSONValue) -> OutputConfig {
        OutputConfig(format: Format(type: "json_schema", schema: schema))
    }
}

/// `POST /v1/messages` body (API reference §2, §3). No `thinking`, `effort`, or sampling parameters are sent,
/// so the same shape is valid for Sonnet 5, Opus 5, and Haiku 4.5 (Milestone 2 ADR).
public struct MessagesRequest: Encodable, Sendable, Equatable {
    public var model: String
    public var maxTokens: Int
    public var system: [ContentBlock]?
    public var messages: [Message]
    public var tools: [ToolDefinition]?
    public var toolChoice: ToolChoice?
    public var outputConfig: OutputConfig?

    public init(model: String, maxTokens: Int, system: [ContentBlock]? = nil, messages: [Message],
                tools: [ToolDefinition]? = nil, toolChoice: ToolChoice? = nil, outputConfig: OutputConfig? = nil) {
        self.model = model
        self.maxTokens = maxTokens
        self.system = system
        self.messages = messages
        self.tools = tools
        self.toolChoice = toolChoice
        self.outputConfig = outputConfig
    }

    enum CodingKeys: String, CodingKey {
        case model, system, messages, tools
        case maxTokens = "max_tokens"
        case toolChoice = "tool_choice"
        case outputConfig = "output_config"
    }
}
