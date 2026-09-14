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
