import Foundation
import Testing
@testable import ScanCore

struct VaultPathGuardTests {
    @Test func resolvesExistingAndNotYetCreatedPathsInsideVault() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        try FileManager.default.createDirectory(at: temp.url.appending(path: "Personal/Finances"), withIntermediateDirectories: true)
        let guardian = VaultPathGuard(root: temp.url)

        let existing = try guardian.resolve("Personal/Finances")
        #expect(existing.path(percentEncoded: false).hasSuffix("/Personal/Finances"))
        let planned = try guardian.resolve("Personal/Finances/Taxes/2026")
        #expect(guardian.contains(planned))
        #expect(try guardian.resolve("") == guardian.root)
    }

    @Test(arguments: ["../outside", "Personal/../../outside", "Personal/Finances/../../../x"])
    func rejectsTraversal(_ path: String) throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let guardian = VaultPathGuard(root: temp.url.appending(path: "Vault"))
        #expect(throws: PathGuardError.escapesRoot(path)) { try guardian.resolve(path) }
    }

    @Test(arguments: ["/etc/passwd", "~/Documents"])
    func rejectsAbsolutePaths(_ path: String) throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let guardian = VaultPathGuard(root: temp.url)
        #expect(throws: PathGuardError.absolutePath(path)) { try guardian.resolve(path) }
    }

    @Test func rejectsSymlinksThatEscapeTheVault() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let vault = temp.url.appending(path: "Vault")
        let outside = temp.url.appending(path: "Outside")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: vault.appending(path: "escape"), withDestinationURL: outside)
        let guardian = VaultPathGuard(root: vault)

        #expect(throws: PathGuardError.escapesRoot("escape")) { try guardian.resolve("escape") }
        #expect(throws: PathGuardError.escapesRoot("escape/new/deeper")) { try guardian.resolve("escape/new/deeper") }
    }
}
