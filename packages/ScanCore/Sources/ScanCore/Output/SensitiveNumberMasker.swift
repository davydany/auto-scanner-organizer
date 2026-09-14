import Foundation

/// Masks sensitive numbers in note text (spec §10.2). PDFs are never altered.
public enum SensitiveNumberMasker {
    public static func mask(_ text: String) -> String {
        maskLabeledAccountNumbers(maskCardNumbers(maskSocialSecurityNumbers(text)))
    }

    static func maskSocialSecurityNumbers(_ text: String) -> String {
        text.replacing(/\b\d{3}-\d{2}-(\d{4})\b/) { match in
            "•••-••-\(match.1)"
        }
    }

    static func maskCardNumbers(_ text: String) -> String {
        text.replacing(/\b(?:\d[ -]?){12,18}\d\b/) { match in
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
