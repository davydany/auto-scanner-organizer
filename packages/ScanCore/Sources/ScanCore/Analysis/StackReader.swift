import Foundation

public enum StackReadOutcome: Sendable, Equatable {
    /// `boundaryDocumentIndices` are documents next to a chunk boundary; their split always goes to review (spec §8.1).
    case read(documents: [DocumentAnalysis], boundaryDocumentIndices: Set<Int>)
    case refused(category: String)
    case invalid(messages: [String])
}

public struct StackReadResult: Sendable, Equatable {
    public var outcome: StackReadOutcome
    public var usage: Usage

    public init(outcome: StackReadOutcome, usage: Usage) {
        self.outcome = outcome
        self.usage = usage
    }
}

/// Step 1 of spec §8: one structured-output request per chunk of at most 20 pages (Milestone 2 ADR).
public struct StackReader: Sendable {
    public static let pagesPerRequest = 20
    public static let maxTokens = 16_000

    private enum ChunkOutcome {
        case documents([DocumentAnalysis])
        case refused(String)
        case invalid([String])
    }

    private let claude: any ClaudeMessaging
    private let model: ClaudeModel

    public init(claude: any ClaudeMessaging, model: ClaudeModel) {
        self.claude = claude
        self.model = model
    }

    public func read(pages: [StackPageInput], purpose: String?) async throws -> StackReadResult {
        guard !pages.isEmpty else { return StackReadResult(outcome: .invalid(messages: ["The batch has no pages."]), usage: .zero) }
        var documents: [DocumentAnalysis] = []
        var boundary: Set<Int> = []
        var usage = Usage.zero
        for start in stride(from: 0, to: pages.count, by: Self.pagesPerRequest) {
            let chunk = Array(pages[start..<min(start + Self.pagesPerRequest, pages.count)])
            let (outcome, chunkUsage) = try await readChunk(chunk, totalPages: pages.count, purpose: purpose)
            usage += chunkUsage
            switch outcome {
            case .documents(let chunkDocuments):
                if !documents.isEmpty, !chunkDocuments.isEmpty {
                    boundary.formUnion([documents.count - 1, documents.count])
                }
                documents += chunkDocuments
            case .refused(let category):
                return StackReadResult(outcome: .refused(category: category), usage: usage)
            case .invalid(let messages):
                return StackReadResult(outcome: .invalid(messages: messages), usage: usage)
            }
        }
        return StackReadResult(outcome: .read(documents: documents, boundaryDocumentIndices: boundary), usage: usage)
    }

    private func readChunk(_ chunk: [StackPageInput], totalPages: Int, purpose: String?) async throws -> (ChunkOutcome, Usage) {
        let range = (chunk.first?.number ?? 1)...(chunk.last?.number ?? 1)
        var messages = [Message(role: .user, content: StackPrompt.userContent(pages: chunk, totalPages: totalPages, purpose: purpose))]
        var usage = Usage.zero
        var errors: [String] = []
        for attempt in 1...2 {
            let response = try await claude.send(request(messages))
            usage += response.usage
            if response.stopReason == .refusal {
                return (.refused(response.stopDetails?.category ?? "unspecified"), usage)
            }
            if response.stopReason != .endTurn {
                errors = ["The response stopped early (\(response.stopReason?.rawValue ?? "unknown")) before the JSON was complete."]
            } else {
                switch StackResponse.parse(Self.text(of: response), pages: range) {
                case .success(let documents): return (.documents(documents), usage)
                case .failure(let failure): errors = failure.messages
                }
            }
            guard attempt == 1 else { break }
            let correction = ContentBlock.text(StackPrompt.correction(errors))
            if response.content.isEmpty {
                messages[0].content.append(correction)
            } else {
                messages.append(Message(role: .assistant, content: response.content))
                messages.append(Message(role: .user, content: [correction]))
            }
        }
        return (.invalid(errors), usage)
    }

    private func request(_ messages: [Message]) -> MessagesRequest {
        MessagesRequest(model: model.rawValue, maxTokens: Self.maxTokens, system: [.text(StackPrompt.system, cacheControl: .ephemeral)],
                        messages: messages, outputConfig: .jsonSchema(StackSchema.outputSchema))
    }

    /// Structured output arrives as JSON text in `text` blocks (API reference §4).
    private static func text(of response: MessagesResponse) -> String {
        response.content.compactMap { block -> String? in
            if case .text(let text, _) = block { return text }
            return nil
        }.joined()
    }
}
