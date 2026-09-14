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
        let cleanTitle = sanitize(title)
        let cleanFrom = from.map(sanitize) ?? ""
        let name = cleanFrom.isEmpty ? "\(date) \(cleanTitle)" : "\(date) \(cleanFrom) - \(cleanTitle)"
        return truncate(name)
    }

    public static func uniqueBaseName(_ base: String, existingFileNames: Set<String>) -> String {
        func isTaken(_ candidate: String) -> Bool {
            existingFileNames.contains("\(candidate).pdf") || existingFileNames.contains("\(candidate).md")
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
        let atWordBoundary = prefix.lastIndex(of: " ").map { String(prefix[..<$0]) } ?? prefix
        return atWordBoundary.trimmingCharacters(in: CharacterSet(charactersIn: " -"))
    }
}
