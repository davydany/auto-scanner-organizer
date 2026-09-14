import Foundation

/// Minimal YAML scalar formatting for note front matter. Strings are always double-quoted.
enum YAML {
    static func string(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        return "\"\(escaped)\""
    }

    static func list(_ values: [String]) -> String {
        "[" + values.map(string).joined(separator: ", ") + "]"
    }

    static func wikilink(_ name: String) -> String {
        string("[[\(name)]]")
    }

    static func confidence(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}
