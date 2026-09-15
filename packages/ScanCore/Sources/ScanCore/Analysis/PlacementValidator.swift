import Foundation

public struct PlacementValidationError: Error, Equatable, Sendable {
    public var messages: [String]

    public init(messages: [String]) {
        self.messages = messages
    }
}

/// Checks Claude's `submit_placement` answer against the vault before anything is written (spec §8.3, §8.4).
public struct PlacementValidator: Sendable {
    public static let maxLedgerNameLength = 80

    private let vault: VaultPathGuard
    private let fileSystem: any FileSystem

    public init(vaultRoot: URL, fileSystem: any FileSystem = LocalFileSystem()) {
        vault = VaultPathGuard(root: vaultRoot)
        self.fileSystem = fileSystem
    }

    public func validate(_ input: JSONValue) -> Result<Placement, PlacementValidationError> {
        let wire: Wire
        do {
            wire = try input.decode(as: Wire.self)
        } catch {
            return .failure(PlacementValidationError(messages: ["submit_placement input did not match its schema: \(error)"]))
        }
        var messages: [String] = []
        if let problem = folderProblem(wire.folder) { messages.append(problem) }
        if let name = wire.newSubfolder, let problem = subfolderProblem(name) { messages.append(problem) }
        if !Self.isConfidence(wire.confidence) { messages.append("confidence must be between 0 and 1.") }
        guard messages.isEmpty else { return .failure(PlacementValidationError(messages: messages)) }

        let alternatives = wire.alternatives.filter { Self.isConfidence($0.confidence) && folderProblem($0.folder) == nil }.prefix(2)
        return .success(Placement(
            folder: Self.normalized(wire.folder), newSubfolder: wire.newSubfolder, relatedNotes: relatedNotes(wire.relatedNotes),
            confidence: wire.confidence, reason: wire.reason,
            alternatives: alternatives.map { PlacementAlternative(folder: Self.normalized($0.folder), confidence: $0.confidence) },
            ledgerNoteName: ledgerName(wire.ledgerNoteName)
        ))
    }

    /// Nil when `folder` is a relative, non-hidden path to an existing folder inside the vault.
    public func folderProblem(_ folder: String) -> String? {
        if folder.hasPrefix("/") || folder == "~" || folder.hasPrefix("~/") {
            return "folder \"\(folder)\" must be relative to the vault."
        }
        if folder.split(separator: "/").contains(where: { $0.hasPrefix(".") }) {
            return "folder \"\(folder)\" must not contain \"..\" or hidden folders."
        }
        guard let url = try? vault.resolve(Self.normalized(folder)), fileSystem.isDirectory(at: url) else {
            return "folder \"\(folder)\" does not exist in the vault."
        }
        return nil
    }

    func subfolderProblem(_ name: String) -> String? {
        guard !name.isEmpty, !name.hasPrefix("."), FilenameBuilder.sanitize(name) == name else {
            return "new_subfolder \"\(name)\" must be one folder name without / \\ : * ? \" < > | # ^ [ ], extra spaces, or a leading dot."
        }
        return nil
    }

    private func relatedNotes(_ paths: [String]) -> [String] {
        var seen: Set<String> = []
        return paths.compactMap { path in
            let normalized = Self.normalized(path)
            guard !path.hasPrefix("/"), normalized.lowercased().hasSuffix(".md"),
                  !normalized.split(separator: "/").contains(where: { $0.hasPrefix(".") }),
                  let url = try? vault.resolve(normalized), fileSystem.fileExists(at: url), !fileSystem.isDirectory(at: url)
            else { return nil }
            let name = String(normalized.dropLast(3))
            return seen.insert(name.lowercased()).inserted ? name : nil
        }
    }

    private func ledgerName(_ name: String?) -> String? {
        guard let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty, !trimmed.hasPrefix("."),
              FilenameBuilder.sanitize(trimmed) == trimmed, trimmed.count <= Self.maxLedgerNameLength
        else { return nil }
        return trimmed
    }

    private static func normalized(_ path: String) -> String {
        path.split(separator: "/").joined(separator: "/")
    }

    private static func isConfidence(_ value: Double) -> Bool {
        value.isFinite && (0...1).contains(value)
    }

    struct Wire: Decodable {
        struct Alternative: Decodable {
            let folder: String
            let confidence: Double
        }

        let folder: String
        let newSubfolder: String?
        let relatedNotes: [String]
        let confidence: Double
        let reason: String
        let alternatives: [Alternative]
        let ledgerNoteName: String?

        enum CodingKeys: String, CodingKey {
            case folder, confidence, reason, alternatives
            case newSubfolder = "new_subfolder"
            case relatedNotes = "related_notes"
            case ledgerNoteName = "ledger_note_name"
        }
    }
}
