import Foundation
import Testing
@testable import ScanCore

func submitInput(folder: String = "Personal/Finances", newSubfolder: String? = nil, related: [String] = [], confidence: Double = 0.9,
                 alternatives: [(folder: String, confidence: Double)] = [], ledger: String? = nil) -> JSONValue {
    .object([
        "folder": .string(folder),
        "new_subfolder": newSubfolder.map(JSONValue.string) ?? .null,
        "related_notes": .array(related.map(JSONValue.string)),
        "confidence": .number(confidence),
        "reason": .string("Matches earlier utility bills."),
        "alternatives": .array(alternatives.map { .object(["folder": .string($0.folder), "confidence": .number($0.confidence)]) }),
        "ledger_note_name": ledger.map(JSONValue.string) ?? .null,
    ])
}

struct PlacementValidatorTests {
    func messages(_ result: Result<Placement, PlacementValidationError>) -> [String] {
        if case .failure(let error) = result { return error.messages }
        return []
    }

    @Test func acceptsAnExistingFolderAndKeepsOnlyUsableDetails() throws {
        let (temp, vault) = try VaultToolsTests().makeVault()
        defer { temp.remove() }
        let bill = "Personal/Finances/2026-08-28 Dominion Energy - Bill.md"
        let input = submitInput(
            folder: "Personal/Finances/", newSubfolder: "2026",
            related: [bill, "Missing.md", "../Outside/secret.md", "Inbox", "Escape/secret.md", "/\(bill)", bill.uppercased()],
            confidence: 0.82,
            alternatives: [("Work", 0.1), ("Nope", 0.3), ("Work", 7), ("Personal", 0.05), ("Personal/Finances/Taxes", 0.01)],
            ledger: " 2026 Business Receipts "
        )

        let placement = try PlacementValidator(vaultRoot: vault).validate(input).get()

        #expect(placement == Placement(
            folder: "Personal/Finances", newSubfolder: "2026", relatedNotes: ["Personal/Finances/2026-08-28 Dominion Energy - Bill"],
            confidence: 0.82, reason: "Matches earlier utility bills.",
            alternatives: [PlacementAlternative(folder: "Work", confidence: 0.1), PlacementAlternative(folder: "Personal", confidence: 0.05)],
            ledgerNoteName: "2026 Business Receipts"
        ))
    }

    @Test(arguments: ["../Outside", "/Personal", "~", "~/Personal", ".obsidian", "Personal/../..", "Nope", "Inbox.md", "Escape"])
    func rejectsFoldersThatAreNotExistingVaultFolders(_ folder: String) throws {
        let (temp, vault) = try VaultToolsTests().makeVault()
        defer { temp.remove() }

        let found = messages(PlacementValidator(vaultRoot: vault).validate(submitInput(folder: folder)))

        #expect(found.count == 1)
        #expect(found.first?.contains("folder \"\(folder)\"") == true)
    }

    @Test(arguments: ["2026/Q3", ".hidden", "Q3: taxes", "a|b", "#x", "^x", "[x]", "  ", "", "a\\b", "two  spaces"])
    func rejectsInvalidNewSubfolders(_ name: String) throws {
        let (temp, vault) = try VaultToolsTests().makeVault()
        defer { temp.remove() }

        let found = messages(PlacementValidator(vaultRoot: vault).validate(submitInput(newSubfolder: name)))

        #expect(found.count == 1)
        #expect(found.first?.hasPrefix("new_subfolder") == true)
    }

    @Test func rejectsConfidenceOutsideZeroToOneAndSchemaMismatches() throws {
        let (temp, vault) = try VaultToolsTests().makeVault()
        defer { temp.remove() }
        let validator = PlacementValidator(vaultRoot: vault)

        #expect(messages(validator.validate(submitInput(confidence: 1.2))) == ["confidence must be between 0 and 1."])
        #expect(messages(validator.validate(submitInput(confidence: -0.1))) == ["confidence must be between 0 and 1."])
        let mismatch = messages(validator.validate(.object(["folder": .string("Personal")])))
        #expect(mismatch.count == 1)
        #expect(mismatch.first?.hasPrefix("submit_placement input did not match its schema") == true)
    }

    @Test func dropsUnusableLedgerNames() throws {
        let (temp, vault) = try VaultToolsTests().makeVault()
        defer { temp.remove() }
        let validator = PlacementValidator(vaultRoot: vault)

        for name in [".Receipts", "a/b", String(repeating: "x", count: 81), "   ", "Tax: 2026"] {
            #expect(try validator.validate(submitInput(ledger: name)).get().ledgerNoteName == nil)
        }
    }

    @Test func placementRoundTripsTheLedgerNameThroughScanCoreJSON() throws {
        let placement = Placement(folder: "Personal", confidence: 0.5, reason: "r", ledgerNoteName: "2026 Business Receipts")
        let data = try ScanCoreJSON.encoder().encode(placement)
        #expect(String(data: data, encoding: .utf8)?.contains("\"ledger_note_name\":\"2026 Business Receipts\"") == true)
        #expect(try ScanCoreJSON.decoder().decode(Placement.self, from: data) == placement)
    }
}
