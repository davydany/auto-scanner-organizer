import Foundation
import Testing
@testable import ScanCore

struct PurposesTests {
    @Test func normalizesCaseAndWhitespace() {
        #expect(PurposeKey.normalize("  2026 Taxes,\n  Business   Receipts ") == "2026 taxes, business receipts")
    }

    @Test func firstFilingWinsAndLookupIgnoresFormatting() async throws {
        let store = InMemoryPurposeStore()
        let first = PurposeMapping(purpose: "2026 taxes, business receipts", folder: "Personal/Finances/Taxes/2026/Business Receipts",
                                   ledgerNoteName: "2026 Business Receipts", createdAt: Date(timeIntervalSince1970: 1))
        let second = PurposeMapping(purpose: "2026 Taxes, Business Receipts", folder: "Somewhere/Else",
                                    ledgerNoteName: nil, createdAt: Date(timeIntervalSince1970: 2))
        #expect(try await store.saveIfAbsent(first) == first)
        #expect(try await store.saveIfAbsent(second) == first)
        #expect(try await store.mapping(for: "2026  TAXES, business receipts") == first)
        #expect(try await store.mapping(for: "Ashburn rental") == nil)
    }

    @Test func keepsEightMostRecentDistinctPurposes() async throws {
        let store = InMemoryPurposeStore()
        for index in 1...9 {
            try await store.recordUse("Purpose \(index)")
        }
        try await store.recordUse("purpose 3")
        try await store.recordUse("   ")
        let recents = try await store.recentPurposes()
        #expect(recents.count == InMemoryPurposeStore.recentLimit)
        #expect(recents.first == "purpose 3")
        #expect(recents.filter { PurposeKey.normalize($0) == "purpose 3" }.count == 1)
        #expect(!recents.contains("Purpose 1"))
        #expect(!recents.contains("Purpose 2"))
    }
}
