import Foundation
import Testing
@testable import ScanAdapters
@testable import ScanCore

/// Calls the real Claude API (spec §15). Costs a few cents per run; enable with `make test-live`.
@Suite(.enabled(if: LiveTestGate.isEnabled, "Set SCANCORE_LIVE=1 and ANTHROPIC_API_KEY to run live Claude tests"), .serialized)
struct LiveClaudeTests {
    let model = ProcessInfo.processInfo.environment["SCANCORE_LIVE_MODEL"].flatMap(ClaudeModel.init(rawValue:)) ?? .sonnet5
    let client = ClaudeClient(apiKey: ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? "", transport: URLSessionClaudeTransport())

    @Test func readsAThreeDocumentStack() async throws {
        let folder = try LivePages.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = ImageIOPageSource()
        let texts = try await BatchOCR.recognize(pages: try source.pageRefs(for: try LivePages.writeStack(to: folder)), in: folder,
                                                 source: source, recognizer: VisionTextRecognizer())
        let pages = try texts.enumerated().map { index, page in
            StackPageInput(number: index + 1, jpeg: try source.claudeJPEG(page.page, in: folder, maxLongEdge: model.maxImageLongEdge),
                           ocrText: page.text)
        }

        let result = try await StackReader(claude: client, model: model).read(pages: pages, purpose: "2026 taxes, business receipts")

        guard case let .read(documents, boundary) = result.outcome else {
            Issue.record("expected the stack to be read, got \(result.outcome)")
            return
        }
        #expect(documents.map(\.pages) == [[1], [2, 3], [4]])
        #expect(boundary.isEmpty)
        #expect(documents[1].docType == .receipt)
        #expect(documents[1].keyFacts.amount == Decimal(string: "84.17"))
        #expect(documents[1].keyFacts.currency?.uppercased() == "USD")
        #expect(documents[1].purposeFit?.fits == true)
        #expect(result.usage.inputTokens + result.usage.cacheReadInputTokens > 0)
    }

    @Test func placesAReceiptNextToEarlierReceipts() async throws {
        let vault = try LivePages.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: vault) }
        for folder in ["Personal/Finances/Receipts", "Personal/Health", "Work/Projects"] {
            try FileManager.default.createDirectory(at: vault.appending(path: folder), withIntermediateDirectories: true)
        }
        try Data("---\ntitle: Printer Ink Receipt\nfrom: Staples\n---\n# Printer Ink Receipt, Staples\n".utf8)
            .write(to: vault.appending(path: "Personal/Finances/Receipts/2026-08-15 Staples - Printer Ink Receipt.md"))
        let document = DocumentAnalysis(pages: [1], splitConfidence: 0.95, docType: .receipt, title: "Office Supplies Receipt", from: "Staples",
                                        docDate: CalendarDay("2026-09-02"), summary: "Receipt for printer paper and gel pens.",
                                        tags: ["office-supplies"], keyFacts: KeyFacts(amount: Decimal(string: "84.17"), currency: "USD"))
        let index = VaultIndex.render(try VaultIndex.build(root: vault))

        let result = try await PlacementAgent(claude: client, model: model, vaultRoot: vault, vaultIndex: index).place(document, purpose: nil)

        guard case .placed(let placement) = result.outcome else {
            Issue.record("expected a placement, got \(result.outcome)")
            return
        }
        #expect(placement.folder == "Personal/Finances/Receipts")
        #expect(placement.newSubfolder == nil)
        #expect(result.toolCalls <= PlacementAgent.maxToolCalls)
    }
}
