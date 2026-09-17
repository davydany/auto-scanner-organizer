import Foundation

/// US dollars per million tokens (API reference §9; cache writes use the 5-minute TTL rate).
public struct ModelPricing: Sendable, Equatable {
    public var input: Decimal
    public var output: Decimal
    public var cacheWrite: Decimal
    public var cacheRead: Decimal

    public func estimatedCostUSD(_ usage: Usage) -> Decimal {
        let weighted = Decimal(usage.inputTokens) * input + Decimal(usage.outputTokens) * output
            + Decimal(usage.cacheCreationInputTokens) * cacheWrite + Decimal(usage.cacheReadInputTokens) * cacheRead
        return weighted / 1_000_000
    }
}

extension ClaudeModel {
    public var pricing: ModelPricing {
        switch self {
        case .sonnet5:
            ModelPricing(input: 2, output: 10, cacheWrite: Decimal(25) / 10, cacheRead: Decimal(2) / 10)
        case .opus5:
            ModelPricing(input: 5, output: 25, cacheWrite: Decimal(625) / 100, cacheRead: Decimal(5) / 10)
        case .haiku45:
            ModelPricing(input: 1, output: 5, cacheWrite: Decimal(125) / 100, cacheRead: Decimal(1) / 10)
        }
    }
}
