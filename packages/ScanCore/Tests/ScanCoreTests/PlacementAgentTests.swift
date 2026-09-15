import Foundation
import Testing
@testable import ScanCore

struct PlacementAgentTests {
    let document = DocumentAnalysis(
        pages: [1], splitConfidence: 0.9, docType: .bill, title: "Electric Bill", from: "Dominion Energy", docDate: CalendarDay("2026-08-28"),
        summary: "Monthly electric bill.", tags: ["electric-bill"], keyFacts: KeyFacts(amount: Decimal(string: "142.18"), currency: "USD"),
        purposeFit: PurposeFit(fits: true, reason: "Home office utility.", taxYear: 2026, taxCategory: .businessReceipt, expenseCategory: .utilities)
    )
    let placed = Placement(folder: "Personal/Finances", confidence: 0.9, reason: "Matches earlier utility bills.")

    func call(_ id: String, _ name: String, _ input: JSONValue) -> ScriptedClaude.ToolCall {
        ScriptedClaude.ToolCall(id: id, name: name, input: input)
    }

    @Test func runsReadOnlyToolsThenReturnsTheSubmittedPlacement() async throws {
        let (temp, vault) = try VaultToolsTests().makeVault()
        defer { temp.remove() }
        let claude = ScriptedClaude([
            ScriptedClaude.toolUse([call("t1", "list_folder", .object(["path": .string("Personal")])),
                                    call("t2", "read_note", .object(["path": .string("Inbox.md")]))]),
            ScriptedClaude.toolUse([call("t3", "submit_placement", submitInput())]),
        ])

        let result = try await PlacementAgent(claude: claude, model: .sonnet5, vaultRoot: vault, vaultIndex: "/ (1 note)").place(document, purpose: nil)

        #expect(result.outcome == .placed(placed))
        #expect(result.toolCalls == 2)
        #expect(result.usage == ScriptedClaude.defaultUsage + ScriptedClaude.defaultUsage)
        let requests = await claude.requests
        #expect(requests.count == 2)
        #expect(requests[0].model == "claude-sonnet-5")
        #expect(requests[0].maxTokens == 4096)
        #expect(requests[0].tools?.map(\.name) == ["list_folder", "read_note", "submit_placement"])
        #expect(requests[0].tools?.last?.strict == true)
        #expect(requests[0].toolChoice == .auto)
        #expect(requests[0].system == [.text(PlacementPrompt.system), .text("Vault folders (with note counts):\n/ (1 note)", cacheControl: .ephemeral)])
        #expect(requests[0].messages == [Message(role: .user, content: [.text(PlacementPrompt.userMessage(for: document, purpose: nil))])])
        let followUp = requests[1].messages
        #expect(followUp.count == 3)
        #expect(followUp[1] == Message(role: .assistant, content: [
            .toolUse(id: "t1", name: "list_folder", input: .object(["path": .string("Personal")])),
            .toolUse(id: "t2", name: "read_note", input: .object(["path": .string("Inbox.md")])),
        ]))
        #expect(followUp[2] == Message(role: .user, content: [
            .toolResult(toolUseID: "t1", content: VaultTools(vaultRoot: vault).listFolder("Personal").content),
            .toolResult(toolUseID: "t2", content: "inbox"),
        ]))
    }

    @Test func forcesSubmitPlacementAfterEightToolCalls() async throws {
        let (temp, vault) = try VaultToolsTests().makeVault()
        defer { temp.remove() }
        let nine = (1...9).map { call("t\($0)", "list_folder", .object(["path": .string("")])) }
        let claude = ScriptedClaude([ScriptedClaude.toolUse(nine), ScriptedClaude.toolUse([call("s1", "submit_placement", submitInput())])])

        let result = try await PlacementAgent(claude: claude, model: .opus5, vaultRoot: vault, vaultIndex: "").place(document, purpose: nil)

        #expect(result.outcome == .placed(placed))
        #expect(result.toolCalls == 8)
        let requests = await claude.requests
        #expect(requests[1].toolChoice == .tool("submit_placement"))
        let results = requests[1].messages[2].content
        #expect(results.count == 9)
        #expect(results.last == .toolResult(toolUseID: "t9", content: "Error: the limit of 8 tool calls is reached. Call submit_placement now.", isError: true))
    }

    @Test func sendsValidationErrorsBackOnce() async throws {
        let (temp, vault) = try VaultToolsTests().makeVault()
        defer { temp.remove() }
        let problem = "folder \"Nope\" does not exist in the vault."
        let recovering = ScriptedClaude([
            ScriptedClaude.toolUse([call("s1", "submit_placement", submitInput(folder: "Nope"))]),
            ScriptedClaude.toolUse([call("s2", "submit_placement", submitInput())]),
        ])

        let recovered = try await PlacementAgent(claude: recovering, model: .sonnet5, vaultRoot: vault, vaultIndex: "").place(document, purpose: nil)

        #expect(recovered.outcome == .placed(placed))
        #expect(await recovering.requests[1].messages[2]
            == Message(role: .user, content: [.toolResult(toolUseID: "s1", content: PlacementPrompt.correction([problem]), isError: true)]))

        let stubborn = ScriptedClaude([
            ScriptedClaude.toolUse([call("s1", "submit_placement", submitInput(folder: "Nope"))]),
            ScriptedClaude.toolUse([call("s2", "submit_placement", submitInput(folder: "Nope"))]),
        ])
        let failed = try await PlacementAgent(claude: stubborn, model: .sonnet5, vaultRoot: vault, vaultIndex: "").place(document, purpose: nil)
        #expect(failed.outcome == .invalid(messages: [problem]))
    }

    @Test func nudgesOnceWhenClaudeAnswersWithoutSubmitting() async throws {
        let (temp, vault) = try VaultToolsTests().makeVault()
        defer { temp.remove() }
        let nudged = ScriptedClaude([ScriptedClaude.text("Personal/Finances looks right."),
                                     ScriptedClaude.toolUse([call("s1", "submit_placement", submitInput())])])

        let result = try await PlacementAgent(claude: nudged, model: .sonnet5, vaultRoot: vault, vaultIndex: "").place(document, purpose: nil)

        #expect(result.outcome == .placed(placed))
        let retry = try #require(await nudged.requests.last)
        #expect(retry.toolChoice == .tool("submit_placement"))
        #expect(retry.messages.last == Message(role: .user, content: [.text("Call submit_placement now with your best placement.")]))

        let silent = ScriptedClaude([ScriptedClaude.text("Hmm."), ScriptedClaude.text("Still thinking.")])
        let failed = try await PlacementAgent(claude: silent, model: .sonnet5, vaultRoot: vault, vaultIndex: "").place(document, purpose: nil)
        #expect(failed.outcome == .invalid(messages: ["Claude did not call submit_placement."]))
    }

    @Test func reportsRefusals() async throws {
        let (temp, vault) = try VaultToolsTests().makeVault()
        defer { temp.remove() }
        let claude = ScriptedClaude([ScriptedClaude.refusal("cyber")])

        let result = try await PlacementAgent(claude: claude, model: .sonnet5, vaultRoot: vault, vaultIndex: "").place(document, purpose: nil)

        #expect(result.outcome == .refused(category: "cyber"))
    }

    @Test func userMessageDescribesTheDocumentAndPurpose() {
        #expect(PlacementPrompt.userMessage(for: document, purpose: "2026 taxes, business receipts") == """
        Place this scanned document.
        <document>
        doc_type: bill
        title: Electric Bill
        from: Dominion Energy
        doc_date: 2026-08-28
        summary: Monthly electric bill.
        tags: electric-bill
        amount: 142.18 USD
        purpose_fit: fits (Home office utility.) [tax year 2026, business-receipt, utilities]
        </document>
        Batch purpose: "2026 taxes, business receipts"
        """)
        #expect(PlacementPrompt.userMessage(for: DocumentAnalysis(pages: [1], splitConfidence: 1, docType: .other, title: "Note", summary: "S."), purpose: nil)
            == "Place this scanned document.\n<document>\ndoc_type: other\ntitle: Note\nsummary: S.\n</document>\nNo batch purpose was given, so ledger_note_name is null.")
    }
}
