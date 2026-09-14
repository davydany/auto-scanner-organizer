import Foundation

/// Masks sensitive numbers in note text (spec §10.2). PDFs are never altered.
public enum SensitiveNumberMasker {
    public static func mask(_ text: String) -> String {
        maskLabeledAccountNumbers(maskCardNumbers(maskSocialSecurityNumbers(text)))
    }

    static func maskSocialSecurityNumbers(_ text: String) -> String {
        var result = text
        // Mask SSN in dash or space-separated format: 123-45-6789 or 123 45 6789
        result = result.replacing(/\b\d{3}[- ]\d{2}[- ](\d{4})\b/) { match in
            "•••-••-\(match.1)"
        }
        // Mask bare 9-digit SSN when preceded by specific labels (case-insensitive)
        result = result.replacing(/(?i)\b(SSN|Social\s+Security\s+No\.?|Social\s+Security\s+Number|Social\s+Security|TIN|Taxpayer\s+ID)\s*[:#]?\s*(\d{9})\b/) { match in
            let fullMatch = String(match.0)
            let label = String(match.1)
            let digits = match.2
            let between = fullMatch.dropFirst(label.count).dropLast(9)
            return "\(label)\(between)•••-••-\(digits.suffix(4))"
        }
        return result
    }

    static func maskCardNumbers(_ text: String) -> String {
        text.replacing(/\b(?:\d[ -]{0,3}){12,18}\d\b/) { match in
            let digits = String(match.0.filter(\.isNumber))
            guard (13...19).contains(digits.count), passesLuhn(digits) else { return String(match.0) }
            return "•••• \(digits.suffix(4))"
        }
    }

    static func maskLabeledAccountNumbers(_ text: String) -> String {
        text.replacing(/(?i)\b(acct|account|member|policy|routing)(\s*(?:no\.?|number|#))?\s*[:#]?\s*((?:\d[ -]?){5,}\d)/) { match in
            let number = match.3
            let digits = String(number.filter(\.isNumber))
            let label = String(match.0).dropLast(number.count)
            return "\(label)••••\(digits.suffix(4))"
        }
    }

    static func passesLuhn(_ digits: String) -> Bool {
        var sum = 0
        for (index, character) in digits.reversed().enumerated() {
            guard var value = character.wholeNumberValue else { return false }
            if index % 2 == 1 {
                value *= 2
                if value > 9 { value -= 9 }
            }
            sum += value
        }
        return sum % 10 == 0
    }
}
