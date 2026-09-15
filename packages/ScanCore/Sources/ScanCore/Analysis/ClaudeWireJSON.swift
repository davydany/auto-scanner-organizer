import Foundation

/// JSON configuration for the Claude Messages API wire format (Milestone 2 ADR): explicit keys only,
/// no key strategy, sorted and slash-unescaped output so identical requests are byte-identical (prompt caching).
public enum ClaudeWireJSON {
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        JSONDecoder()
    }
}
