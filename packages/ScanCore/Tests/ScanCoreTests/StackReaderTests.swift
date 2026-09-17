import Foundation
import Testing
@testable import ScanCore

struct StackReaderTests {
    func pages(_ count: Int) -> [StackPageInput] {
        (1...count).map { StackPageInput(number: $0, jpeg: Data("p\($0)".utf8), ocrText: "Page \($0) text") }
    }

    func valid(_ ranges: [[Int]]) -> String {
        ranges.map { StackJSON.document(pages: $0) }.reduce(into: #"{"documents":["#) { result, document in
            result += (result.hasSuffix("[") ? "" : ",") + document
        } + "]}"
    }

    @Test func readsASmallBatchInOneCachedStructuredRequest() async throws {
        let claude = ScriptedClaude([ScriptedClaude.text(valid([[1, 2], [3]]))])

        let result = try await StackReader(claude: claude, model: .sonnet5).read(pages: pages(3), purpose: nil)

        guard case .read(let documents, let boundary) = result.outcome else {
            Issue.record("expected .read, got \(result.outcome)")
            return
        }
        #expect(documents.map(\.pages) == [[1, 2], [3]])
        #expect(boundary.isEmpty)
        #expect(result.usage == ScriptedClaude.defaultUsage)
        let request = try #require(await claude.requests.first)
        #expect(request.model == "claude-sonnet-5")
        #expect(request.maxTokens == 16_000)
        #expect(request.system == [.text(StackPrompt.system, cacheControl: .ephemeral)])
        #expect(request.outputConfig == .jsonSchema(StackSchema.outputSchema))
        #expect(request.messages == [Message(role: .user, content: StackPrompt.userContent(pages: pages(3), totalPages: 3, purpose: nil))])
        #expect(request.tools == nil)
    }

    @Test func retriesOnceWithTheValidationErrorsThenSucceeds() async throws {
        let first = ScriptedClaude.text(valid([[1, 2]]))
        let claude = ScriptedClaude([first, ScriptedClaude.text(valid([[1], [2, 3]]))])

        let result = try await StackReader(claude: claude, model: .opus5).read(pages: pages(3), purpose: "2026 taxes")

        guard case .read(let documents, _) = result.outcome else {
            Issue.record("expected .read, got \(result.outcome)")
            return
        }
        #expect(documents.map(\.pages) == [[1], [2, 3]])
        #expect(result.usage == ScriptedClaude.defaultUsage + ScriptedClaude.defaultUsage)
        let retry = try #require(await claude.requests.last)
        #expect(retry.messages.count == 3)
        guard case .respond(let firstResponse) = first else { return }
        #expect(retry.messages[1] == Message(role: .assistant, content: firstResponse.content))
        #expect(retry.messages[2].role == .user)
        guard case .text(let correction, _) = retry.messages[2].content.first else {
            Issue.record("correction must be text")
            return
        }
        #expect(correction.contains("The documents must cover pages 1–3 exactly once"))
    }

    @Test func givesUpAfterTheCorrectiveRetry() async throws {
        let claude = ScriptedClaude([ScriptedClaude.text("not json"), ScriptedClaude.text(valid([[1]]))])

        let result = try await StackReader(claude: claude, model: .sonnet5).read(pages: pages(2), purpose: nil)

        #expect(result.outcome == .invalid(messages: ["The documents must cover pages 1–2 exactly once, in order; they cover [1]."]))
        #expect(await claude.requests.count == 2)
    }

    @Test func reportsRefusalsWithTheirCategory() async throws {
        let cyber = ScriptedClaude([ScriptedClaude.refusal("cyber")])
        #expect(try await StackReader(claude: cyber, model: .sonnet5).read(pages: pages(1), purpose: nil).outcome == .refused(category: "cyber"))

        let unspecified = ScriptedClaude([ScriptedClaude.refusal(nil)])
        #expect(try await StackReader(claude: unspecified, model: .sonnet5).read(pages: pages(1), purpose: nil).outcome
            == .refused(category: "unspecified"))
        #expect(await unspecified.requests.count == 1)
    }

    @Test func treatsATruncatedResponseAsAFailedAttemptAndAppendsToTheUserTurnWhenContentIsEmpty() async throws {
        let truncated = MessagesResponse(id: "msg_cut", model: "claude-sonnet-5", content: [], stopReason: .maxTokens, usage: .zero)
        let claude = ScriptedClaude([.respond(truncated), ScriptedClaude.text(valid([[1]]))])

        let result = try await StackReader(claude: claude, model: .haiku45).read(pages: pages(1), purpose: nil)

        #expect(result.outcome == .read(documents: try StackResponse.parse(valid([[1]]), pages: 1...1).get(), boundaryDocumentIndices: []))
        let retry = try #require(await claude.requests.last)
        #expect(retry.model == "claude-haiku-4-5")
        #expect(retry.messages.count == 1)
        guard case .text(let correction, _) = retry.messages[0].content.last else {
            Issue.record("correction must be appended as text")
            return
        }
        #expect(correction.contains("stopped early (max_tokens)"))
    }

    @Test func splitsLargeBatchesIntoChunksOfTwentyAndFlagsBoundaryDocuments() async throws {
        let claude = ScriptedClaude([
            ScriptedClaude.text(valid([Array(1...10), Array(11...20)])),
            ScriptedClaude.text(valid([Array(21...40)])),
            ScriptedClaude.text(valid([Array(41...45)])),
        ])

        let result = try await StackReader(claude: claude, model: .sonnet5).read(pages: pages(45), purpose: nil)

        guard case .read(let documents, let boundary) = result.outcome else {
            Issue.record("expected .read, got \(result.outcome)")
            return
        }
        #expect(documents.map { $0.pages.first ?? 0 } == [1, 11, 21, 41])
        #expect(boundary == [1, 2, 3])
        let requests = await claude.requests
        #expect(requests.count == 3)
        let secondContent = requests[1].messages[0].content
        #expect(secondContent.first == .text("Page 21 of 45:"))
        #expect(secondContent.filter { if case .image = $0 { true } else { false } }.count == 20)
        #expect(requests.map(\.system) == Array(repeating: [.text(StackPrompt.system, cacheControl: .ephemeral)], count: 3))
    }

    @Test func propagatesClaudeErrorsAndRejectsEmptyBatches() async throws {
        let failing = ScriptedClaude([ScriptedClaude.fail(.http(status: 500, type: "api_error", message: "boom"))])
        await #expect(throws: ClaudeError.http(status: 500, type: "api_error", message: "boom")) {
            try await StackReader(claude: failing, model: .sonnet5).read(pages: pages(1), purpose: nil)
        }

        let unused = ScriptedClaude([])
        #expect(try await StackReader(claude: unused, model: .sonnet5).read(pages: [], purpose: nil).outcome == .invalid(messages: ["The batch has no pages."]))
        #expect(await unused.requests.isEmpty)
    }
}
