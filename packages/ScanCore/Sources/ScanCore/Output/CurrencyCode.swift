import Foundation

/// Three-letter currency codes as the ledger stores them (spec §10.4, execution decisions ADR).
public enum CurrencyCode {
    /// The trimmed, uppercased code when it is exactly three ASCII letters A–Z; otherwise nil.
    public static func normalized(_ currency: String) -> String? {
        let code = currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard code.unicodeScalars.count == 3, code.unicodeScalars.allSatisfy({ ("A"..."Z").contains($0) }) else {
            return nil
        }
        return code
    }
}
