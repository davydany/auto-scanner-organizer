import Foundation

/// Filename rules from spec §10.1.
public enum FilenameBuilder {
    public static let maxLength = 120

    private static let forbidden: Set<Character> = ["/", "\\", ":", "*", "?", "\"", "<", ">", "|", "#", "^", "[", "]"]

    public static func sanitize(_ text: String) -> String {
        var cleaned = ""
        for character in text {
            if character.unicodeScalars.allSatisfy({ CharacterSet.controlCharacters.contains($0) }) {
                cleaned.append(" ")
            } else if !forbidden.contains(character) {
                cleaned.append(character)
            }
        }
        return cleaned.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    public static func baseName(date: CalendarDay, from: String?, title: String) -> String {
        let cleanTitle = sanitize(title).isEmpty ? "Untitled" : sanitize(title)
        let cleanFrom = from.map(sanitize) ?? ""
        let name = cleanFrom.isEmpty ? "\(date) \(cleanTitle)" : "\(date) \(cleanFrom) - \(cleanTitle)"
        return truncate(name)
    }

    /// Names that differ only in letter case collide: the default macOS and iCloud Drive volumes are case-insensitive.
    public static func uniqueBaseName(_ base: String, existingFileNames: Set<String>) -> String {
        let taken = Set(existingFileNames.map { $0.lowercased() })
        func isTaken(_ candidate: String) -> Bool {
            let lowered = candidate.lowercased()
            return taken.contains("\(lowered).pdf") || taken.contains("\(lowered).md")
        }
        guard isTaken(base) else { return base }
        var counter = 2
        while isTaken("\(base) (\(counter))") {
            counter += 1
        }
        return "\(base) (\(counter))"
    }

    private static func truncate(_ name: String) -> String {
        guard name.count > maxLength else { return name }
        let prefix = String(name.prefix(maxLength))
        let trimSet = CharacterSet(charactersIn: " -")
        if let space = prefix.lastIndex(of: " "), prefix.distance(from: prefix.startIndex, to: space) >= maxLength / 2 {
            return String(prefix[..<space]).trimmingCharacters(in: trimSet)
        }
        return prefix.trimmingCharacters(in: trimSet)
    }
}
