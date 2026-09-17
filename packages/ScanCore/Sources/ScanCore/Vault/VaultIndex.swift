import Foundation

public struct VaultFolder: Sendable, Equatable {
    /// Vault-relative path; "" is the vault root.
    public var path: String
    public var noteCount: Int

    public init(path: String, noteCount: Int) {
        self.path = path
        self.noteCount = noteCount
    }
}

/// The folder index sent with every placement request (spec §8.3).
public enum VaultIndex {
    /// Every real folder under the root (depth-first, name order) with its direct `.md` count. Dot-folders and
    /// symlinked folders are skipped, so the index has no aliases, loops, or folders outside the vault.
    public static func build(root: URL, fileSystem: any FileSystem = LocalFileSystem()) throws -> [VaultFolder] {
        let vault = VaultPathGuard(root: root)
        let rootPath = vault.root.path(percentEncoded: false)
        var folders: [VaultFolder] = []

        func visit(_ url: URL, path: String) throws {
            let expected = path.isEmpty ? rootPath : "\(rootPath)/\(path)"
            guard VaultPathGuard.canonical(url).path(percentEncoded: false) == expected else { return }
            let children = try fileSystem.contentsOfDirectory(at: url)
            let subfolders = children.filter { fileSystem.isDirectory(at: $0) }
            let noteCount = children.filter { $0.pathExtension.lowercased() == "md" && !fileSystem.isDirectory(at: $0) }.count
            folders.append(VaultFolder(path: path, noteCount: noteCount))
            for child in subfolders {
                try visit(child, path: path.isEmpty ? child.lastPathComponent : "\(path)/\(child.lastPathComponent)")
            }
        }

        try visit(vault.root, path: "")
        return folders
    }

    /// One line per folder, e.g. `Personal/Finances (12 notes)`; the root is shown as `/`.
    public static func render(_ folders: [VaultFolder]) -> String {
        folders.map { folder in
            "\(folder.path.isEmpty ? "/" : folder.path) (\(folder.noteCount) \(folder.noteCount == 1 ? "note" : "notes"))"
        }.joined(separator: "\n")
    }
}
