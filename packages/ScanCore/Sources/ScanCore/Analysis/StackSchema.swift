import Foundation

/// The strict output schema for the read-stack request (spec §8.2, API reference §2).
public enum StackSchema {
    public static var outputSchema: JSONValue {
        object(["documents": .object(["type": .string("array"), "items": document,
                                      "description": .string("Every document in the pages, in page order.")])])
    }

    static var document: JSONValue {
        object([
            "pages": .object(["type": .string("array"), "items": .object(["type": .string("integer")]),
                              "description": .string("1-based page numbers of this document, consecutive and ascending.")]),
            "split_confidence": typed("number", "From 0 to 1: how sure you are that this document starts and ends on these pages."),
            "doc_type": enumeration(DocType.allCases.map(\.rawValue)),
            "title": typed("string", "Short title such as \"Electric Bill\" or \"Office Supplies Receipt\"."),
            "from": nullable(typed("string", "Sender or issuer such as \"Dominion Energy\".")),
            "doc_date": nullable(date("The document's own date (statement, invoice, or letter date).")),
            "summary": typed("string", "Two to three sentences."),
            "tags": .object(["type": .string("array"), "items": typed("string", "A lowercase hyphenated tag such as \"electric-bill\".")]),
            "key_facts": object([
                "amount_due": nullable(typed("string", "Amount due as a plain decimal such as \"142.18\".")),
                "due_date": nullable(date("Payment due date.")),
                "amount": nullable(typed("string", "Amount paid or charged as a plain decimal such as \"84.17\".")),
                "currency": nullable(typed("string", "Three-letter currency code such as \"USD\".")),
                "account_last4": nullable(typed("string", "Only the last four digits of the account number.")),
            ]),
            "handwritten": .object(["type": .string("array"), "items": object([
                "page": typed("integer", "1-based page number the handwriting is on."),
                "raw_text": typed("string", "The handwriting exactly as written."),
                "paid_on": nullable(date("Payment date the handwriting records.")),
                "amount_paid": nullable(typed("string", "Amount paid as a plain decimal such as \"142.18\".")),
                "payment_method": nullable(typed("string", "Payment method such as \"check\", \"card\", or \"autopay\".")),
                "check_number": nullable(typed("string", "Check number, if written.")),
            ])]),
            "purpose_fit": nullable(object([
                "fits": typed("boolean", "Whether this document belongs to the batch purpose."),
                "reason": typed("string", "One sentence."),
                "tax_year": nullable(typed("integer", "Tax year the document belongs to, such as 2026.")),
                "tax_category": nullable(enumeration(TaxCategory.allCases.map(\.rawValue))),
                "expense_category": nullable(enumeration(ExpenseCategory.allCases.map(\.rawValue))),
            ])),
        ])
    }

    static func object(_ properties: [String: JSONValue]) -> JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object(properties),
            "required": .array(properties.keys.sorted().map(JSONValue.string)),
            "additionalProperties": .bool(false),
        ])
    }

    static func typed(_ type: String, _ description: String) -> JSONValue {
        .object(["type": .string(type), "description": .string(description)])
    }

    static func date(_ description: String) -> JSONValue {
        .object(["type": .string("string"), "format": .string("date"), "description": .string(description)])
    }

    static func enumeration(_ values: [String]) -> JSONValue {
        .object(["type": .string("string"), "enum": .array(values.map(JSONValue.string))])
    }

    static func nullable(_ schema: JSONValue) -> JSONValue {
        .object(["anyOf": .array([schema, .object(["type": .string("null")])])])
    }
}
