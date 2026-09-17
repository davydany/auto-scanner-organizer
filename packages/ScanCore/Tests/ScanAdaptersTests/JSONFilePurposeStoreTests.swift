import Foundation
import Testing
@testable import ScanAdapters
@testable import ScanCore

struct JSONFilePurposeStoreTests {
    @Test func firstFilingWinsAcrossInstances() async throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let file = temp.url.appending(path: "data/purposes.json")
        let first = PurposeMapping(purpose: "2026 taxes, business receipts", folder: "Personal/Finances/Taxes/2026",
                                   ledgerNoteName: "2026 Business Receipts", createdAt: Date(timeIntervalSince1970: 1))
        let second = PurposeMapping(purpose: "2026 TAXES, business receipts", folder: "Elsewhere", ledgerNoteName: nil,
                                    createdAt: Date(timeIntervalSince1970: 2))

        #expect(try await JSONFilePurposeStore(fileURL: file).saveIfAbsent(first) == first)
        let reopened = JSONFilePurposeStore(fileURL: file)
        #expect(try await reopened.saveIfAbsent(second) == first)
        #expect(try await reopened.mapping(for: "2026  taxes, BUSINESS receipts") == first)
        #expect(try await reopened.mapping(for: "Ashburn rental") == nil)
    }

    @Test func persistsRecentPurposesWithTheSameRulesAsTheInMemoryStore() async throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let file = temp.url.appending(path: "purposes.json")
        let store = JSONFilePurposeStore(fileURL: file)
        for index in 1...10 {
            try await store.recordUse("Purpose \(index)")
        }
        try await store.recordUse("purpose 3")
        try await store.recordUse("   ")

        let recents = try await JSONFilePurposeStore(fileURL: file).recentPurposes()
        #expect(recents.count == InMemoryPurposeStore.recentLimit)
        #expect(recents.first == "purpose 3")
        #expect(!recents.contains("Purpose 1"))
        #expect(!recents.contains("Purpose 2"))
    }

    @Test func missingFileMeansEmptyStore() async throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let store = JSONFilePurposeStore(fileURL: temp.url.appending(path: "none.json"))
        #expect(try await store.recentPurposes().isEmpty)
        #expect(try await store.mapping(for: "anything") == nil)
    }
}
