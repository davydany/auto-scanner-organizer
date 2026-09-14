import Foundation
import Testing
@testable import ScanCore

struct LocalFileSystemTests {
    let fileSystem = LocalFileSystem()

    @Test func writesReadsAndListsFiles() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let folder = temp.url.appending(path: "a/b")
        try fileSystem.createDirectory(at: folder)
        #expect(fileSystem.isDirectory(at: folder))

        let file = folder.appending(path: "note.md")
        try fileSystem.writeAtomically(Data("hello".utf8), to: file)
        try fileSystem.writeAtomically(Data("hidden".utf8), to: folder.appending(path: ".secret"))
        #expect(fileSystem.fileExists(at: file))
        #expect(!fileSystem.isDirectory(at: file))
        #expect(try fileSystem.readData(at: file) == Data("hello".utf8))
        #expect(try fileSystem.contentsOfDirectory(at: folder).map(\.lastPathComponent) == ["note.md"])
    }

    @Test func createsNewFileWithoutLeavingTemporaryFiles() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let file = temp.url.appending(path: "doc.pdf")

        try fileSystem.createNewFile(Data("new".utf8), at: file)

        #expect(try fileSystem.readData(at: file) == Data("new".utf8))
        let names = try FileManager.default.contentsOfDirectory(atPath: temp.url.path(percentEncoded: false))
        #expect(names == ["doc.pdf"])
    }

    @Test func createNewFileRefusesToReplaceAnExistingFile() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let file = temp.url.appending(path: "doc.pdf")
        try Data("original".utf8).write(to: file)

        #expect(throws: (any Error).self) { try fileSystem.createNewFile(Data("replacement".utf8), at: file) }

        #expect(try fileSystem.readData(at: file) == Data("original".utf8))
        let names = try FileManager.default.contentsOfDirectory(atPath: temp.url.path(percentEncoded: false))
        #expect(names == ["doc.pdf"])
    }

    @Test func movesItems() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let source = temp.url.appending(path: "batch")
        try fileSystem.createDirectory(at: source)
        let destination = temp.url.appending(path: "_done/batch")
        try fileSystem.createDirectory(at: destination.deletingLastPathComponent())
        try fileSystem.moveItem(at: source, to: destination)
        #expect(!fileSystem.fileExists(at: source))
        #expect(fileSystem.isDirectory(at: destination))
    }

    @Test func removesItems() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let file = temp.url.appending(path: "note.md")
        try fileSystem.writeAtomically(Data("hello".utf8), to: file)
        #expect(fileSystem.fileExists(at: file))
        try fileSystem.removeItem(at: file)
        #expect(!fileSystem.fileExists(at: file))
    }
}
