import Foundation

public struct StackValidationError: Error, Equatable, Sendable {
    public var messages: [String]

    public init(messages: [String]) {
        self.messages = messages
    }
}

/// Decodes and validates the read-stack JSON (spec §8.2). Every problem is reported, so one corrective retry can fix them all.
public enum StackResponse {
    public static func parse(_ text: String, pages: ClosedRange<Int>) -> Result<[DocumentAnalysis], StackValidationError> {
        let wire: Wire
        do {
            wire = try ClaudeWireJSON.decoder().decode(Wire.self, from: Data(text.utf8))
        } catch {
            return .failure(StackValidationError(messages: ["The response did not match the schema: \(error)"]))
        }
        guard !wire.documents.isEmpty else { return .failure(StackValidationError(messages: ["The response contained no documents."])) }

        var messages: [String] = []
        let documents = wire.documents.enumerated().map { index, document in
            map(document, label: "Document \(index + 1)", messages: &messages)
        }
        let covered = wire.documents.flatMap(\.pages)
        if covered != Array(pages) {
            messages.append("The documents must cover pages \(pages.lowerBound)–\(pages.upperBound) exactly once, in order; they cover \(covered).")
        }
        return messages.isEmpty ? .success(documents) : .failure(StackValidationError(messages: messages))
    }

    /// An optional leading "-", ASCII digits, and an optional "." followed by more digits.
    public static func plainDecimal(_ text: String) -> Decimal? {
        let body = text.hasPrefix("-") ? text.dropFirst() : Substring(text)
        let parts = body.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }) else {
            return nil
        }
        return Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func map(_ wire: Wire.Document, label: String, messages: inout [String]) -> DocumentAnalysis {
        if zip(wire.pages, wire.pages.dropFirst()).contains(where: { $1 != $0 + 1 }) {
            messages.append("\(label) pages \(wire.pages) are not consecutive.")
        }
        if !(wire.splitConfidence.isFinite && (0...1).contains(wire.splitConfidence)) {
            messages.append("\(label) split_confidence must be between 0 and 1.")
        }
        let docType = DocType(rawValue: wire.docType)
        if docType == nil {
            messages.append("\(label) has an unknown doc_type \"\(wire.docType)\".")
        }
        let facts = wire.keyFacts
        return DocumentAnalysis(
            pages: wire.pages, splitConfidence: wire.splitConfidence, docType: docType ?? .other, title: wire.title, from: wire.from,
            docDate: day(wire.docDate, "\(label) doc_date", &messages), summary: wire.summary, tags: normalizedTags(wire.tags),
            keyFacts: KeyFacts(amountDue: decimal(facts.amountDue, "\(label) key_facts.amount_due", &messages),
                               dueDate: day(facts.dueDate, "\(label) key_facts.due_date", &messages),
                               amount: decimal(facts.amount, "\(label) key_facts.amount", &messages),
                               currency: facts.currency, accountLast4: facts.accountLast4),
            handwritten: wire.handwritten.map { handwriting($0, pages: wire.pages, label: label, messages: &messages) },
            purposeFit: wire.purposeFit.map { purposeFit($0, label: label, messages: &messages) }
        )
    }

    private static func handwriting(_ wire: Wire.Handwriting, pages: [Int], label: String, messages: inout [String]) -> HandwrittenAnnotation {
        if !pages.contains(wire.page) {
            messages.append("\(label) has handwriting on page \(wire.page), outside its pages.")
        }
        return HandwrittenAnnotation(page: wire.page, rawText: wire.rawText, paidOn: day(wire.paidOn, "\(label) handwritten paid_on", &messages),
                                     amountPaid: decimal(wire.amountPaid, "\(label) handwritten amount_paid", &messages),
                                     paymentMethod: wire.paymentMethod, checkNumber: wire.checkNumber)
    }

    private static func purposeFit(_ wire: Wire.PurposeFit, label: String, messages: inout [String]) -> PurposeFit {
        if let year = wire.taxYear, !(1900...2100).contains(year) {
            messages.append("\(label) purpose_fit.tax_year \(year) is not a plausible year.")
        }
        let taxCategory = wire.taxCategory.flatMap(TaxCategory.init(rawValue:))
        if let raw = wire.taxCategory, taxCategory == nil {
            messages.append("\(label) has an unknown tax_category \"\(raw)\".")
        }
        let expenseCategory = wire.expenseCategory.flatMap(ExpenseCategory.init(rawValue:))
        if let raw = wire.expenseCategory, expenseCategory == nil {
            messages.append("\(label) has an unknown expense_category \"\(raw)\".")
        }
        return PurposeFit(fits: wire.fits, reason: wire.reason, taxYear: wire.taxYear, taxCategory: taxCategory, expenseCategory: expenseCategory)
    }

    private static func day(_ text: String?, _ field: String, _ messages: inout [String]) -> CalendarDay? {
        guard let text else { return nil }
        guard let day = CalendarDay(text) else {
            messages.append("\(field) \"\(text)\" is not YYYY-MM-DD.")
            return nil
        }
        return day
    }

    private static func decimal(_ text: String?, _ field: String, _ messages: inout [String]) -> Decimal? {
        guard let text else { return nil }
        guard let value = plainDecimal(text) else {
            messages.append("\(field) \"\(text)\" is not a plain decimal.")
            return nil
        }
        return value
    }

    private static func normalizedTags(_ tags: [String]) -> [String] {
        tags.map { $0.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: "-") }.filter { !$0.isEmpty }
    }

    struct Wire: Decodable {
        struct Document: Decodable {
            let pages: [Int]
            let splitConfidence: Double
            let docType: String
            let title: String
            let from: String?
            let docDate: String?
            let summary: String
            let tags: [String]
            let keyFacts: KeyFacts
            let handwritten: [Handwriting]
            let purposeFit: PurposeFit?

            enum CodingKeys: String, CodingKey {
                case pages, title, from, summary, tags, handwritten
                case splitConfidence = "split_confidence"
                case docType = "doc_type"
                case docDate = "doc_date"
                case keyFacts = "key_facts"
                case purposeFit = "purpose_fit"
            }
        }

        struct KeyFacts: Decodable {
            let amountDue: String?
            let dueDate: String?
            let amount: String?
            let currency: String?
            let accountLast4: String?

            enum CodingKeys: String, CodingKey {
                case amount, currency
                case amountDue = "amount_due"
                case dueDate = "due_date"
                case accountLast4 = "account_last4"
            }
        }

        struct Handwriting: Decodable {
            let page: Int
            let rawText: String
            let paidOn: String?
            let amountPaid: String?
            let paymentMethod: String?
            let checkNumber: String?

            enum CodingKeys: String, CodingKey {
                case page
                case rawText = "raw_text"
                case paidOn = "paid_on"
                case amountPaid = "amount_paid"
                case paymentMethod = "payment_method"
                case checkNumber = "check_number"
            }
        }

        struct PurposeFit: Decodable {
            let fits: Bool
            let reason: String
            let taxYear: Int?
            let taxCategory: String?
            let expenseCategory: String?

            enum CodingKeys: String, CodingKey {
                case fits, reason
                case taxYear = "tax_year"
                case taxCategory = "tax_category"
                case expenseCategory = "expense_category"
            }
        }

        let documents: [Document]
    }
}
