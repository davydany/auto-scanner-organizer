import Foundation

/// The owner's answer for a document in Needs review (spec §3). Editing page splits is Milestone 3 (Milestone 2 ADR).
public struct ReviewResolution: Codable, Sendable, Equatable {
    public var folder: String
    public var newSubfolder: String?
    public var title: String?
    public var from: String?
    public var docDate: CalendarDay?
    public var amount: Decimal?
    public var currency: String?
    /// File even though a note with the same date, sender, and title exists.
    public var acceptPossibleDuplicate: Bool

    public init(folder: String, newSubfolder: String? = nil, title: String? = nil, from: String? = nil, docDate: CalendarDay? = nil,
                amount: Decimal? = nil, currency: String? = nil, acceptPossibleDuplicate: Bool = false) {
        self.folder = folder
        self.newSubfolder = newSubfolder
        self.title = title
        self.from = from
        self.docDate = docDate
        self.amount = amount
        self.currency = currency
        self.acceptPossibleDuplicate = acceptPossibleDuplicate
    }

    /// The document with the owner's corrections applied.
    public func applied(to document: DocumentAnalysis) -> DocumentAnalysis {
        var document = document
        if let title { document.title = title }
        if let from { document.from = from }
        if let docDate { document.docDate = docDate }
        if let amount { document.keyFacts.amount = amount }
        if let currency { document.keyFacts.currency = currency }
        return document
    }
}

public enum ReviewError: Error, Equatable, Sendable {
    case documentNotInReview(String)
    case invalidResolution([String])
}
