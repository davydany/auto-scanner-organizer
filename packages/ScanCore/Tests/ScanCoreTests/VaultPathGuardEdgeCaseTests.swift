import Foundation
import Testing
@testable import ScanCore

struct VaultPathGuardEdgeCaseTests {
    @Test func rejectsSymlinkIntoALookalikeSiblingFolder() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let vault = temp.url.appending(path: "Vault")
        let sibling = temp.url.appending(path: "Vault2")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: vault.appending(path: "sib"), withDestinationURL: sibling)
        let guardian = VaultPathGuard(root: vault)

        #expect(throws: PathGuardError.escapesRoot("sib/x")) { try guardian.resolve("sib/x") }
        #expect(!guardian.contains(sibling.appending(path: "x")))
    }

    @Test func allowsSymlinksThatStayInsideTheVault() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let vault = temp.url.appending(path: "Vault")
        try FileManager.default.createDirectory(at: vault.appending(path: "Personal/Finances"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: vault.appending(path: "shortcut"), withDestinationURL: vault.appending(path: "Personal"))
        let guardian = VaultPathGuard(root: vault)

        let resolved = try guardian.resolve("shortcut/Finances")
        #expect(guardian.contains(resolved))
        #expect(resolved.path(percentEncoded: false).hasSuffix("/Personal/Finances"))
    }

    @Test func dotDotAfterAnEscapingSymlinkStaysInsideTheVault() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let vault = temp.url.appending(path: "Vault")
        let outside = temp.url.appending(path: "Outside")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: vault.appending(path: "link"), withDestinationURL: outside)
        let guardian = VaultPathGuard(root: vault)

        let resolved = try guardian.resolve("link/../x")
        #expect(guardian.contains(resolved))
        #expect(resolved.lastPathComponent == "x")
        #expect(!resolved.path(percentEncoded: false).contains("/Outside"))
    }

    @Test func appendingAFileNameToAResolvedFolderStaysInsideIt() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        try FileManager.default.createDirectory(at: temp.url.appending(path: "Personal"), withIntermediateDirectories: true)
        let guardian = VaultPathGuard(root: temp.url)

        let folder = try guardian.resolve("Personal")
        let file = folder.appending(path: "2026-09-14 Bank - Statement.pdf")
        #expect(file.path(percentEncoded: false) == folder.path(percentEncoded: false) + "/2026-09-14 Bank - Statement.pdf")
        #expect(guardian.contains(file))
    }

    @Test func handlesRealVaultPathCharacters() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let vault = temp.url.appending(path: "Library/Mobile Documents/iCloud~md~obsidian/Documents/David's Vault")
        try FileManager.default.createDirectory(at: vault.appending(path: "Personal/Café 50%"), withIntermediateDirectories: true)
        let guardian = VaultPathGuard(root: vault)

        let resolved = try guardian.resolve("Personal/Café 50%")
        #expect(resolved.path(percentEncoded: false).hasSuffix("/David's Vault/Personal/Café 50%"))
        #expect(guardian.contains(resolved))
    }

    @Test func allowsTildeInsideFolderNamesButRejectsHomeReferences() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let guardian = VaultPathGuard(root: temp.url)

        #expect(guardian.contains(try guardian.resolve("notes~2026")))
        #expect(guardian.contains(try guardian.resolve("~notes")))
        #expect(throws: PathGuardError.absolutePath("~")) { try guardian.resolve("~") }
        #expect(throws: PathGuardError.absolutePath("~/Documents")) { try guardian.resolve("~/Documents") }
    }

    @Test func createNewFileRefusesToWriteThroughADanglingSymlink() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let vault = temp.url.appending(path: "Vault")
        let outside = temp.url.appending(path: "Outside")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let target = outside.appending(path: "missing.pdf")
        try FileManager.default.createSymbolicLink(at: vault.appending(path: "evil.pdf"), withDestinationURL: target)

        #expect(throws: (any Error).self) { try LocalFileSystem().createNewFile(Data("x".utf8), at: vault.appending(path: "evil.pdf")) }
        #expect(!FileManager.default.fileExists(atPath: target.path(percentEncoded: false)))
        #expect(try FileManager.default.contentsOfDirectory(atPath: vault.path(percentEncoded: false)) == ["evil.pdf"])
    }
}
