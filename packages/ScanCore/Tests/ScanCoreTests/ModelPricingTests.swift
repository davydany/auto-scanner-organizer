import Foundation
import Testing
@testable import ScanCore

struct ModelPricingTests {
    let usage = Usage(inputTokens: 1_000_000, outputTokens: 100_000, cacheCreationInputTokens: 200_000, cacheReadInputTokens: 500_000)

    @Test func estimatesSonnetCostFromUsage() {
        // 1M × $2 + 0.1M × $10 + 0.2M × $2.50 + 0.5M × $0.20 = $3.60
        #expect(ClaudeModel.sonnet5.pricing.estimatedCostUSD(usage) == Decimal(36) / 10)
    }

    @Test func estimatesOpusAndHaikuCost() {
        // Opus: 5 + 2.5 + 1.25 + 0.25 = 9.00; Haiku: 1 + 0.5 + 0.25 + 0.05 = 1.80
        #expect(ClaudeModel.opus5.pricing.estimatedCostUSD(usage) == Decimal(9))
        #expect(ClaudeModel.haiku45.pricing.estimatedCostUSD(usage) == Decimal(18) / 10)
    }

    @Test func addsUsage() {
        let sum = usage + Usage(inputTokens: 1, outputTokens: 2, cacheCreationInputTokens: 3, cacheReadInputTokens: 4)
        #expect(sum == Usage(inputTokens: 1_000_001, outputTokens: 100_002, cacheCreationInputTokens: 200_003, cacheReadInputTokens: 500_004))
        var total = Usage.zero
        total += sum
        #expect(total == sum)
    }
}
