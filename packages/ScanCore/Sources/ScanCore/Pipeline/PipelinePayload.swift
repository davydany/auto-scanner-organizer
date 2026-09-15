import Foundation

/// Event payload values the pipeline records (spec §8.1 usage, §9 review reasons).
public enum PipelinePayload {
    public static func usage(_ usage: Usage, model: ClaudeModel) -> [String: String] {
        [
            JobPayloadKey.model: model.rawValue,
            JobPayloadKey.inputTokens: String(usage.inputTokens),
            JobPayloadKey.outputTokens: String(usage.outputTokens),
            JobPayloadKey.cacheWriteTokens: String(usage.cacheCreationInputTokens),
            JobPayloadKey.cacheReadTokens: String(usage.cacheReadInputTokens),
            JobPayloadKey.costUsd: "\(model.pricing.estimatedCostUSD(usage))",
        ]
    }

    public static func encodeReasons(_ reasons: [ReviewReason]) -> String {
        (try? ScanCoreJSON.encoder().encode(reasons)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }

    public static func decodeReasons(_ text: String?) -> [ReviewReason] {
        guard let text, let reasons = try? ScanCoreJSON.decoder().decode([ReviewReason].self, from: Data(text.utf8)) else { return [] }
        return reasons
    }
}
