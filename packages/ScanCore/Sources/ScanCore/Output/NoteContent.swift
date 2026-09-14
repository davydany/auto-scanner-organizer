import Foundation

/// Everything NoteWriter needs to render one filed document's Markdown note.
public struct NoteContent: Sendable, Equatable {
    public var baseName: String
    public var analysis: DocumentAnalysis
    public var docDate: CalendarDay
    public var docDateEstimated: Bool
    public var scannedAt: Date
    public var timeZone: TimeZone
    public var filingConfidence: Double
    public var relatedNotes: [String]
    public var scanPurpose: String?
    public var ledgerNoteName: String?
    public var pageTexts: [String]

    public init(baseName: String, analysis: DocumentAnalysis, docDate: CalendarDay, docDateEstimated: Bool,
                scannedAt: Date, timeZone: TimeZone, filingConfidence: Double, relatedNotes: [String] = [],
                scanPurpose: String? = nil, ledgerNoteName: String? = nil, pageTexts: [String]) {
        self.baseName = baseName
        self.analysis = analysis
        self.docDate = docDate
        self.docDateEstimated = docDateEstimated
        self.scannedAt = scannedAt
        self.timeZone = timeZone
        self.filingConfidence = filingConfidence
        self.relatedNotes = relatedNotes
        self.scanPurpose = scanPurpose
        self.ledgerNoteName = ledgerNoteName
        self.pageTexts = pageTexts
    }
}
