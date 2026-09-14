import Foundation

public enum DocType: String, Codable, Sendable, CaseIterable {
    case bill, statement, receipt, tax, insurance, medical, legal, letter, notice, manual
    case handwrittenNote = "handwritten-note"
    case other
}

public enum TaxCategory: String, Codable, Sendable, CaseIterable {
    case businessReceipt = "business-receipt"
    case businessIncome = "business-income"
    case personalDeduction = "personal-deduction"
    case medical
    case charitable
    case propertyTax = "property-tax"
    case other
}

public enum ExpenseCategory: String, Codable, Sendable, CaseIterable {
    case officeSupplies = "office-supplies"
    case travel, meals, software, equipment, utilities
    case professionalServices = "professional-services"
    case other
}

public struct KeyFacts: Codable, Sendable, Equatable {
    public var amountDue: Decimal?
    public var dueDate: CalendarDay?
    public var amount: Decimal?
    public var currency: String?
    public var accountLast4: String?

    public init(amountDue: Decimal? = nil, dueDate: CalendarDay? = nil, amount: Decimal? = nil,
                currency: String? = nil, accountLast4: String? = nil) {
        self.amountDue = amountDue
        self.dueDate = dueDate
        self.amount = amount
        self.currency = currency
        self.accountLast4 = accountLast4
    }
}

public struct HandwrittenAnnotation: Codable, Sendable, Equatable {
    public var page: Int
    public var rawText: String
    public var paidOn: CalendarDay?
    public var amountPaid: Decimal?
    public var paymentMethod: String?
    public var checkNumber: String?

    public init(page: Int, rawText: String, paidOn: CalendarDay? = nil, amountPaid: Decimal? = nil,
                paymentMethod: String? = nil, checkNumber: String? = nil) {
        self.page = page
        self.rawText = rawText
        self.paidOn = paidOn
        self.amountPaid = amountPaid
        self.paymentMethod = paymentMethod
        self.checkNumber = checkNumber
    }
}

public struct PurposeFit: Codable, Sendable, Equatable {
    public var fits: Bool
    public var reason: String
    public var taxYear: Int?
    public var taxCategory: TaxCategory?
    public var expenseCategory: ExpenseCategory?

    public init(fits: Bool, reason: String, taxYear: Int? = nil, taxCategory: TaxCategory? = nil,
                expenseCategory: ExpenseCategory? = nil) {
        self.fits = fits
        self.reason = reason
        self.taxYear = taxYear
        self.taxCategory = taxCategory
        self.expenseCategory = expenseCategory
    }
}

/// One document found by Claude's "read stack" step (spec §8.2).
public struct DocumentAnalysis: Codable, Sendable, Equatable {
    public var pages: [Int]
    public var splitConfidence: Double
    public var docType: DocType
    public var title: String
    public var from: String?
    public var docDate: CalendarDay?
    public var summary: String
    public var tags: [String]
    public var keyFacts: KeyFacts
    public var handwritten: [HandwrittenAnnotation]
    public var purposeFit: PurposeFit?

    public init(pages: [Int], splitConfidence: Double, docType: DocType, title: String, from: String? = nil,
                docDate: CalendarDay? = nil, summary: String, tags: [String] = [], keyFacts: KeyFacts = KeyFacts(),
                handwritten: [HandwrittenAnnotation] = [], purposeFit: PurposeFit? = nil) {
        self.pages = pages
        self.splitConfidence = splitConfidence
        self.docType = docType
        self.title = title
        self.from = from
        self.docDate = docDate
        self.summary = summary
        self.tags = tags
        self.keyFacts = keyFacts
        self.handwritten = handwritten
        self.purposeFit = purposeFit
    }
}

public struct StackAnalysis: Codable, Sendable, Equatable {
    public var documents: [DocumentAnalysis]

    public init(documents: [DocumentAnalysis]) {
        self.documents = documents
    }
}
