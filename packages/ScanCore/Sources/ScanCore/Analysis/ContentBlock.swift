import Foundation

/// A Messages API content block (API reference §2–§4).
public enum ContentBlock: Codable, Sendable, Equatable {
    case text(String, cacheControl: CacheControl? = nil)
    case image(mediaType: String, base64Data: String)
    case toolUse(id: String, name: String, input: JSONValue)
    case toolResult(toolUseID: String, content: String, isError: Bool = false)
    case thinking(thinking: String, signature: String)
    case redactedThinking(data: String)
    /// A block type this client doesn't model, kept verbatim so a tool loop can echo it back unchanged.
    case other(JSONValue)

    private enum CodingKeys: String, CodingKey {
        case type, text, source, id, name, input, content, thinking, signature, data
        case cacheControl = "cache_control"
        case mediaType = "media_type"
        case toolUseID = "tool_use_id"
        case isError = "is_error"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "text":
            self = .text(try container.decode(String.self, forKey: .text),
                         cacheControl: try container.decodeIfPresent(CacheControl.self, forKey: .cacheControl))
        case "tool_use":
            self = .toolUse(id: try container.decode(String.self, forKey: .id), name: try container.decode(String.self, forKey: .name),
                            input: try container.decode(JSONValue.self, forKey: .input))
        case "thinking":
            self = .thinking(thinking: try container.decode(String.self, forKey: .thinking),
                             signature: try container.decode(String.self, forKey: .signature))
        case "redacted_thinking":
            self = .redactedThinking(data: try container.decode(String.self, forKey: .data))
        case "tool_result":
            self = .toolResult(toolUseID: try container.decode(String.self, forKey: .toolUseID),
                               content: try container.decode(String.self, forKey: .content),
                               isError: try container.decodeIfPresent(Bool.self, forKey: .isError) ?? false)
        case "image":
            let source = try container.nestedContainer(keyedBy: CodingKeys.self, forKey: .source)
            self = .image(mediaType: try source.decode(String.self, forKey: .mediaType),
                          base64Data: try source.decode(String.self, forKey: .data))
        default:
            self = .other(try JSONValue(from: decoder))
        }
    }

    public func encode(to encoder: Encoder) throws {
        if case .other(let value) = self {
            try value.encode(to: encoder)
            return
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .text(text, cacheControl):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
            try container.encodeIfPresent(cacheControl, forKey: .cacheControl)
        case let .image(mediaType, base64Data):
            try container.encode("image", forKey: .type)
            var source = container.nestedContainer(keyedBy: CodingKeys.self, forKey: .source)
            try source.encode("base64", forKey: .type)
            try source.encode(mediaType, forKey: .mediaType)
            try source.encode(base64Data, forKey: .data)
        case let .toolUse(id, name, input):
            try container.encode("tool_use", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            try container.encode(input, forKey: .input)
        case let .toolResult(toolUseID, content, isError):
            try container.encode("tool_result", forKey: .type)
            try container.encode(toolUseID, forKey: .toolUseID)
            try container.encode(content, forKey: .content)
            if isError {
                try container.encode(true, forKey: .isError)
            }
        case let .thinking(thinking, signature):
            try container.encode("thinking", forKey: .type)
            try container.encode(thinking, forKey: .thinking)
            try container.encode(signature, forKey: .signature)
        case let .redactedThinking(data):
            try container.encode("redacted_thinking", forKey: .type)
            try container.encode(data, forKey: .data)
        case .other:
            break
        }
    }
}
