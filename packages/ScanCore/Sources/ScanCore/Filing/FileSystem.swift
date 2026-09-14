import Foundation

public protocol FileSystem: Sendable {
    func fileExists(at url: URL) -> Bool
    func isDirectory(at url: URL) -> Bool
    /// Lists direct children, skipping hidden files.
    func contentsOfDirectory(at url: URL) throws -> [URL]
    /// Creates the directory and any missing parents.
    func createDirectory(at url: URL) throws
    func readData(at url: URL) throws -> Data
    /// Writes to a temporary file on the same volume, then renames it into place.
    func writeAtomically(_ data: Data, to url: URL) throws
    /// Writes to a temporary file in the same directory, then moves it into place.
    /// Throws, leaving any existing item untouched, if anything already exists at `url`.
    func createNewFile(_ data: Data, at url: URL) throws
    func moveItem(at source: URL, to destination: URL) throws
    func removeItem(at url: URL) throws
}

public struct LocalFileSystem: FileSystem {
    public init() {}

    public func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    public func isDirectory(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    public func contentsOfDirectory(at url: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    public func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    public func readData(at url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    public func writeAtomically(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }

    public func createNewFile(_ data: Data, at url: URL) throws {
        let temporary = url.deletingLastPathComponent().appending(path: ".\(UUID().uuidString).tmp")
        try data.write(to: temporary, options: .withoutOverwriting)
        do {
            // Unlike a replacing write, moveItem refuses an existing destination
            // (case-insensitively on case-insensitive volumes).
            try FileManager.default.moveItem(at: temporary, to: url)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    public func moveItem(at source: URL, to destination: URL) throws {
        try FileManager.default.moveItem(at: source, to: destination)
    }

    public func removeItem(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }
}
