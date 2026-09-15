import Foundation

/// `stop_reason` values are an open set (API reference §4), so unknown values decode instead of failing.
public struct StopReason: RawRepresentable, Codable, Sendable, Equatable, Hashable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        rawValue = try String(from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        try rawValue.encode(to: encoder)
    }

    public static let endTurn = StopReason(rawValue: "end_turn")
    public static let maxTokens = StopReason(rawValue: "max_tokens")
    public static let toolUse = StopReason(rawValue: "tool_use")
    public static let pauseTurn = StopReason(rawValue: "pause_turn")
    public static let refusal = StopReason(rawValue: "refusal")
    public static let modelContextWindowExceeded = StopReason(rawValue: "model_context_window_exceeded")
}

/// Populated only on refusals; `category` is an open set and may be null (API reference §4).
public struct StopDetails: Codable, Sendable, Equatable {
    public var type: String
    public var category: String?
    public var explanation: String?

    public init(type: String, category: String?, explanation: String?) {
        self.type = type
        self.category = category
        self.explanation = explanation
    }
}

/// Token usage for one request. A wire type: record it in event payloads, never through `ScanCoreJSON`.
public struct Usage: Codable, Sendable, Equatable {
    public var inputTokens: Int
    public var outputTokens: Int
    public var cacheCreationInputTokens: Int
    public var cacheReadInputTokens: Int

    public init(inputTokens: Int, outputTokens: Int, cacheCreationInputTokens: Int = 0, cacheReadInputTokens: Int = 0) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheCreationInputTokens = cacheCreationInputTokens
        self.cacheReadInputTokens = cacheReadInputTokens
    }

    public static let zero = Usage(inputTokens: 0, outputTokens: 0)

    public static func + (lhs: Usage, rhs: Usage) -> Usage {
        var sum = lhs
        sum += rhs
        return sum
    }

    public static func += (lhs: inout Usage, rhs: Usage) {
        lhs.inputTokens += rhs.inputTokens
        lhs.outputTokens += rhs.outputTokens
        lhs.cacheCreationInputTokens += rhs.cacheCreationInputTokens
        lhs.cacheReadInputTokens += rhs.cacheReadInputTokens
    }

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheCreationInputTokens = "cache_creation_input_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        inputTokens = try container.decodeIfPresent(Int.self, forKey: .inputTokens) ?? 0
        outputTokens = try container.decodeIfPresent(Int.self, forKey: .outputTokens) ?? 0
        cacheCreationInputTokens = try container.decodeIfPresent(Int.self, forKey: .cacheCreationInputTokens) ?? 0
        cacheReadInputTokens = try container.decodeIfPresent(Int.self, forKey: .cacheReadInputTokens) ?? 0
    }
}

public struct MessagesResponse: Decodable, Sendable, Equatable {
    public var id: String
    public var model: String
    public var content: [ContentBlock]
    public var stopReason: StopReason?
    public var stopDetails: StopDetails?
    public var usage: Usage

    public init(id: String, model: String, content: [ContentBlock], stopReason: StopReason?, stopDetails: StopDetails? = nil, usage: Usage) {
        self.id = id
        self.model = model
        self.content = content
        self.stopReason = stopReason
        self.stopDetails = stopDetails
        self.usage = usage
    }

    enum CodingKeys: String, CodingKey {
        case id, model, content, usage
        case stopReason = "stop_reason"
        case stopDetails = "stop_details"
    }
}

/// Error response body (API reference §5).
public struct APIErrorBody: Decodable, Sendable, Equatable {
    public struct Detail: Decodable, Sendable, Equatable {
        public var type: String
        public var message: String
    }

    public var error: Detail
}
