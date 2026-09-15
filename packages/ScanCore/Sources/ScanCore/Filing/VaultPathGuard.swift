import Foundation

public enum PathGuardError: Error, Equatable, Sendable {
    case absolutePath(String)
    case escapesRoot(String)
}

/// Keeps every vault path inside the vault root, following symlinks (spec §8.3, §14).
public struct VaultPathGuard: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = Self.canonical(root)
    }

    public func resolve(_ relativePath: String) throws -> URL {
        if relativePath.hasPrefix("/") || relativePath == "~" || relativePath.hasPrefix("~/") {
            throw PathGuardError.absolutePath(relativePath)
        }
        let candidate = Self.canonical(root.appending(path: relativePath))
        guard contains(candidate) else { throw PathGuardError.escapesRoot(relativePath) }
        return candidate
    }

    public func contains(_ url: URL) -> Bool {
        let rootPath = Self.normalizedPath(root)
        let candidatePath = Self.normalizedPath(Self.canonical(url))
        return candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
    }

    /// Resolves symlinks in the longest existing ancestor, then re-appends the not-yet-existing tail.
    static func canonical(_ url: URL) -> URL {
        var existing = url.standardizedFileURL
        var tail: [String] = []
        while !FileManager.default.fileExists(atPath: existing.path(percentEncoded: false)), existing.pathComponents.count > 1 {
            tail.insert(existing.lastPathComponent, at: 0)
            existing.deleteLastPathComponent()
        }
        var resolved = existing.resolvingSymlinksInPath()
        for component in tail {
            resolved.append(path: component)
        }
        // `standardizedFileURL`/`resolvingSymlinksInPath()` set a directory-path hint (trailing "/")
        // for components that exist on disk as directories. Rebuild without that hint so every
        // canonical URL has a consistent, comparable string form regardless of whether it exists yet.
        return URL(filePath: normalizedPath(resolved), directoryHint: .notDirectory)
    }

    private static func normalizedPath(_ url: URL) -> String {
        let path = url.path(percentEncoded: false)
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}
