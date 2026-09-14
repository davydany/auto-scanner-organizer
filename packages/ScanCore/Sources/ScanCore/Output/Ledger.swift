import Foundation

public struct LedgerRow: Sendable, Equatable {
    public var date: CalendarDay
    public var from: String
    public var amount: Decimal
    public var currency: String
    public var category: ExpenseCategory
    public var documentNoteName: String

    public init(date: CalendarDay, from: String, amount: Decimal, currency: String, category: ExpenseCategory,
                documentNoteName: String) {
        self.date = date
        self.from = from
        self.amount = amount
        self.currency = currency
        self.category = category
        self.documentNoteName = documentNoteName
    }
}

public enum LedgerError: Error, Equatable, Sendable {
    case markersMissing
    case markersDuplicated
    case unparseableRow(String)
    case mixedCurrency(existing: String, new: String)
}

/// A purpose ledger note. Only the section between the markers is ever rewritten (spec §10.4).
public struct LedgerDocument: Sendable, Equatable {
    public static let startMarker = "<!-- auto-scanner:ledger:start -->"
    public static let endMarker = "<!-- auto-scanner:ledger:end -->"
    static let header = "| Date | From | Amount | Category | Document |"
    static let separator = "|---|---|---|---|---|"

    public private(set) var rows: [LedgerRow]
    private let prefixLines: [String]
    private let suffixLines: [String]
    private let lineEnding: String

    private init(rows: [LedgerRow], prefixLines: [String], suffixLines: [String], lineEnding: String) {
        self.rows = rows
        self.prefixLines = prefixLines
        self.suffixLines = suffixLines
        self.lineEnding = lineEnding
    }

    public static func new(title: String, purpose: String, taxYear: Int?) -> LedgerDocument {
        var prefix = ["---", "type: ledger", "scan_purpose: \(YAML.string(purpose))"]
        if let taxYear { prefix.append("tax_year: \(taxYear)") }
        prefix += ["---", "", "# \(singleLine(title))", "", "Documents filed by Auto Scanner Organizer for this purpose.", ""]
        return LedgerDocument(rows: [], prefixLines: prefix, suffixLines: [""], lineEnding: "\n")
    }

    public static func parse(_ markdown: String) throws -> LedgerDocument {
        let lineEnding = markdown.contains("\r\n") ? "\r\n" : "\n"
        let lines = markdown.components(separatedBy: lineEnding)
        let starts = lines.indices.filter { lines[$0].trimmingCharacters(in: .whitespaces) == startMarker }
        let ends = lines.indices.filter { lines[$0].trimmingCharacters(in: .whitespaces) == endMarker }
        guard starts.count <= 1, ends.count <= 1 else { throw LedgerError.markersDuplicated }
        guard let start = starts.first, let end = ends.first, start < end else { throw LedgerError.markersMissing }

        var rows: [LedgerRow] = []
        for line in lines[(start + 1)..<end] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed == header || trimmed == separator || trimmed.hasPrefix("| **Total**") {
                continue
            }
            rows.append(try parseRow(trimmed))
        }
        return LedgerDocument(rows: rows, prefixLines: Array(lines[..<start]), suffixLines: Array(lines[(end + 1)...]),
                              lineEnding: lineEnding)
    }

    public var total: Decimal {
        rows.reduce(Decimal(0)) { $0 + $1.amount }
    }

    public mutating func upsert(_ row: LedgerRow) throws {
        if let conflicting = rows.first(where: { $0.documentNoteName != row.documentNoteName && $0.currency != row.currency }) {
            throw LedgerError.mixedCurrency(existing: conflicting.currency, new: row.currency)
        }
        rows.removeAll { $0.documentNoteName == row.documentNoteName }
        rows.append(row)
        rows.sort { ($0.date, $0.documentNoteName) < ($1.date, $1.documentNoteName) }
    }

    public func render() -> String {
        var managed = [Self.startMarker, Self.header, Self.separator]
        for row in rows {
            let from = Self.singleLine(row.from).replacingOccurrences(of: "|", with: "/")
            managed.append("| \(row.date) | \(from) | \(Money.format(row.amount)) \(row.currency) | \(row.category.rawValue) | [[\(row.documentNoteName)]] |")
        }
        let currency = rows.first.map { " \($0.currency)" } ?? ""
        managed.append("| **Total** |  | **\(Money.format(total))\(currency)** |  |  |")
        managed.append(Self.endMarker)
        let prefix = prefixLines.isEmpty ? "" : prefixLines.joined(separator: lineEnding) + lineEnding
        let suffix = suffixLines.isEmpty ? "" : lineEnding + suffixLines.joined(separator: lineEnding)
        return prefix + managed.joined(separator: lineEnding) + suffix
    }

    private static func singleLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).joined(separator: " ")
    }

    private static func parseRow(_ line: String) throws -> LedgerRow {
        let cells = line.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard cells.count == 7, cells[0].isEmpty, cells[6].isEmpty else { throw LedgerError.unparseableRow(line) }
        let amountParts = cells[3].split(separator: " ")
        guard let date = CalendarDay(cells[1]),
              amountParts.count == 2,
              let amount = Decimal(string: String(amountParts[0]), locale: Locale(identifier: "en_US_POSIX")),
              let category = ExpenseCategory(rawValue: cells[4]),
              cells[5].hasPrefix("[["), cells[5].hasSuffix("]]")
        else { throw LedgerError.unparseableRow(line) }
        return LedgerRow(date: date, from: cells[2], amount: amount, currency: String(amountParts[1]),
                         category: category, documentNoteName: String(cells[5].dropFirst(2).dropLast(2)))
    }
}
