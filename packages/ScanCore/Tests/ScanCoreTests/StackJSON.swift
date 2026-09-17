import Foundation

/// Builds read-stack response JSON the way Claude returns it (spec §8.2 field names).
enum StackJSON {
    static func document(pages: [Int], title: String = "Electric Bill", from: String? = "Dominion Energy", docDate: String? = "2026-08-28",
                         splitConfidence: Double = 0.95, docType: String = "bill", amount: String? = nil, currency: String? = nil,
                         handwritten: String = "[]", purposeFit: String = "null") -> String {
        """
        {"pages":[\(pages.map(String.init).joined(separator: ","))],"split_confidence":\(splitConfidence),"doc_type":"\(docType)",\
        "title":"\(title)","from":\(quoted(from)),"doc_date":\(quoted(docDate)),"summary":"A short summary.",\
        "tags":["Electric Bill"," utilities ",""],"key_facts":{"amount_due":null,"due_date":null,"amount":\(quoted(amount)),\
        "currency":\(quoted(currency)),"account_last4":"7890"},"handwritten":\(handwritten),"purpose_fit":\(purposeFit)}
        """
    }

    static func stack(_ documents: String...) -> String {
        #"{"documents":["# + documents.joined(separator: ",") + "]}"
    }

    static func quoted(_ value: String?) -> String {
        value.map { "\"\($0)\"" } ?? "null"
    }
}
