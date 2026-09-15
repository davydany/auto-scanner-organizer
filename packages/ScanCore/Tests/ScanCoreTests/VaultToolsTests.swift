import Foundation
import Testing
@testable import ScanCore

struct VaultToolsTests {
    /// Inbox.md, Personal/Finances/<bill>.md, Personal/Finances/Taxes/, Personal/Properties/Primary Residence/{Deed.md, scan.pdf},
    /// Work/, .obsidian/app.json, and a symlink Escape -> ../Outside (which holds secret.md).
    func makeVault() throws -> (temp: TemporaryDirectory, vault: URL) {
        let temp = try TemporaryDirectory()
        let vault = temp.url.appending(path: "Vault")
        let manager = FileManager.default
        for folder in ["Personal/Finances/Taxes", "Personal/Properties/Primary Residence", "Work", ".obsidian"] {
            try manager.createDirectory(at: vault.appending(path: folder), withIntermediateDirectories: true)
        }
        try manager.createDirectory(at: temp.url.appending(path: "Outside"), withIntermediateDirectories: true)
        try Data("inbox".utf8).write(to: vault.appending(path: "Inbox.md"))
        try Data(String(repeating: "a", count: 5000).utf8).write(to: vault.appending(path: "Personal/Finances/2026-08-28 Dominion Energy - Bill.md"))
        try Data("deed".utf8).write(to: vault.appending(path: "Personal/Properties/Primary Residence/Deed.md"))
        try Data("pdf".utf8).write(to: vault.appending(path: "Personal/Properties/Primary Residence/scan.pdf"))
        try Data("{}".utf8).write(to: vault.appending(path: ".obsidian/app.json"))
        try Data("TOP SECRET".utf8).write(to: temp.url.appending(path: "Outside/secret.md"))
        try manager.createSymbolicLink(at: vault.appending(path: "Escape"), withDestinationURL: temp.url.appending(path: "Outside"))
        return (temp, vault)
    }

    @Test func indexesRealFoldersWithNoteCounts() throws {
        let (temp, vault) = try makeVault()
        defer { temp.remove() }

        let folders = try VaultIndex.build(root: vault)

        #expect(VaultIndex.render(folders) == """
        / (1 note)
        Personal (0 notes)
        Personal/Finances (1 note)
        Personal/Finances/Taxes (0 notes)
        Personal/Properties (0 notes)
        Personal/Properties/Primary Residence (1 note)
        Work (0 notes)
        """)
    }

    @Test func listsSubfoldersAndNotes() throws {
        let (temp, vault) = try makeVault()
        defer { temp.remove() }
        let tools = VaultTools(vaultRoot: vault)

        #expect(tools.listFolder("") == ToolOutput(content: """
        Folder: /
        Subfolders:
        - Personal
        - Work
        Notes:
        - Inbox.md
        """, isError: false))
        #expect(tools.listFolder("Personal/Properties/Primary Residence/") == ToolOutput(content: """
        Folder: Personal/Properties/Primary Residence
        Subfolders:
        (none)
        Notes:
        - Deed.md
        """, isError: false))
    }

    @Test func readsTheFirst4000CharactersOfANote() throws {
        let (temp, vault) = try makeVault()
        defer { temp.remove() }

        let output = VaultTools(vaultRoot: vault).readNote("Personal/Finances/2026-08-28 Dominion Energy - Bill.md")

        #expect(output == ToolOutput(content: String(repeating: "a", count: 4000), isError: false))
    }

    @Test(arguments: ["../Outside/secret.md", "/etc/hosts", "~/secret.md", "Escape/secret.md", ".obsidian/app.json", "Work", "Missing.md",
                      "Personal/Properties/Primary Residence/scan.pdf"])
    func rejectsNotesOutsideTheRules(_ path: String) throws {
        let (temp, vault) = try makeVault()
        defer { temp.remove() }

        let output = VaultTools(vaultRoot: vault).readNote(path)

        #expect(output.isError)
        #expect(output.content.hasPrefix("Error: "))
        #expect(!output.content.contains("TOP SECRET"))
    }

    @Test(arguments: ["..", "/", "Escape", ".obsidian", "Inbox.md", "Nope"])
    func rejectsFoldersOutsideTheRules(_ path: String) throws {
        let (temp, vault) = try makeVault()
        defer { temp.remove() }

        let output = VaultTools(vaultRoot: vault).listFolder(path)

        #expect(output.isError)
        #expect(!output.content.contains("secret"))
    }

    @Test func dispatchesToolCallsByNameAndReportsBadInput() throws {
        let (temp, vault) = try makeVault()
        defer { temp.remove() }
        let tools = VaultTools(vaultRoot: vault)

        #expect(tools.run(name: "read_note", input: .object(["path": .string("Inbox.md")])) == ToolOutput(content: "inbox", isError: false))
        #expect(tools.run(name: "list_folder", input: .object(["path": .string("Work")])).isError == false)
        #expect(tools.run(name: "list_folder", input: .object([:])) == ToolOutput(content: "Error: input must be {\"path\": string}", isError: true))
        #expect(tools.run(name: "write_note", input: .object([:])) == ToolOutput(content: "Error: unknown tool write_note", isError: true))
    }

    @Test func definesStrictReadOnlyToolSchemas() {
        let definitions = VaultTools.definitions
        #expect(definitions.map(\.name) == ["list_folder", "read_note"])
        for definition in definitions {
            guard case .object(let schema) = definition.inputSchema else {
                Issue.record("schema must be an object")
                continue
            }
            #expect(schema["additionalProperties"] == .bool(false))
            #expect(schema["required"] == .array([.string("path")]))
        }
    }
}
