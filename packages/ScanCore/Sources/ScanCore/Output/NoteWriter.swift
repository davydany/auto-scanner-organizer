import Foundation

/// Renders the Markdown note for a filed document (spec §10.2).
public enum NoteWriter {
    public static func render(_ note: NoteContent) -> String {
        frontMatter(note) + "\n" + body(note)
    }

    static func frontMatter(_ note: NoteContent) -> String {
        let analysis = note.analysis
        var lines = ["---"]
        lines.append("title: \(YAML.string(analysis.title))")
        lines.append("doc_type: \(analysis.docType.rawValue)")
        lines.append("doc_date: \(note.docDate)")
        if note.docDateEstimated { lines.append("doc_date_estimated: true") }
        if let from = analysis.from, !from.isEmpty { lines.append("from: \(YAML.string(from))") }
        lines.append("pages: \(analysis.pages.count)")
        lines.append("scanned_at: \(timestamp(note.scannedAt, in: note.timeZone))")
        lines.append("source: \(YAML.wikilink(note.baseName + ".pdf"))")
        lines.append("tags: \(YAML.list(tags(analysis.tags)))")
        lines.append("filing_confidence: \(YAML.confidence(note.filingConfidence))")
        if !note.relatedNotes.isEmpty {
            lines.append("related: [" + note.relatedNotes.map(YAML.wikilink).joined(separator: ", ") + "]")
        }
        lines += keyFactProperties(analysis.keyFacts)
        lines += handwrittenProperties(analysis.handwritten)
        if let purpose = note.scanPurpose {
            lines.append("scan_purpose: \(YAML.string(purpose))")
            if let fit = analysis.purposeFit {
                if let year = fit.taxYear { lines.append("tax_year: \(year)") }
                if let category = fit.taxCategory { lines.append("tax_category: \(category.rawValue)") }
                if let category = fit.expenseCategory { lines.append("expense_category: \(category.rawValue)") }
            }
            if let ledger = note.ledgerNoteName { lines.append("ledger: \(YAML.wikilink(ledger))") }
        }
        lines.append("---")
        return lines.joined(separator: "\n") + "\n"
    }

    static func body(_ note: NoteContent) -> String {
        let analysis = note.analysis
        var sections: [String] = []
        let heading: String
        if let from = analysis.from, !from.isEmpty {
            heading = "# \(singleLine(analysis.title)), \(singleLine(from))"
        } else {
            heading = "# \(singleLine(analysis.title))"
        }
        sections.append("\(heading)\n\n![[\(note.baseName).pdf]]")
        sections.append("## Summary\n\n" + SensitiveNumberMasker.mask(analysis.summary))
        if !analysis.handwritten.isEmpty {
            sections.append("## Handwritten notes\n\n" + analysis.handwritten.map(handwrittenLine).joined(separator: "\n"))
        }
        let facts = keyFactLines(analysis.keyFacts)
        if !facts.isEmpty {
            sections.append("## Key facts\n\n" + facts.joined(separator: "\n"))
        }
        if !note.relatedNotes.isEmpty {
            sections.append("## Related\n\n" + note.relatedNotes.map { "- [[\(singleLine($0))]]" }.joined(separator: "\n"))
        }
        var extracted = "## Extracted text"
        for (index, text) in note.pageTexts.enumerated() {
            extracted += "\n\n### Page \(index + 1)\n\n" + SensitiveNumberMasker.mask(text)
        }
        sections.append(extracted)
        return sections.joined(separator: "\n\n") + "\n"
    }

    private static func singleLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).joined(separator: " ")
    }

    private static func tags(_ tags: [String]) -> [String] {
        var seen: Set<String> = []
        return (["scanned"] + tags).filter { seen.insert($0).inserted }
    }

    private static func timestamp(_ date: Date, in timeZone: TimeZone) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private static func keyFactProperties(_ facts: KeyFacts) -> [String] {
        var lines: [String] = []
        if let value = facts.amountDue { lines.append("amount_due: \(Money.format(value))") }
        if let value = facts.dueDate { lines.append("due_date: \(value)") }
        if let value = facts.amount { lines.append("amount: \(Money.format(value))") }
        if let value = facts.currency { lines.append("currency: \(YAML.string(value))") }
        if let value = facts.accountLast4 { lines.append("account_last4: \(YAML.string(value))") }
        return lines
    }

    private static func handwrittenProperties(_ annotations: [HandwrittenAnnotation]) -> [String] {
        guard let annotation = annotations.first(where: {
            $0.paidOn != nil || $0.amountPaid != nil || $0.paymentMethod != nil || $0.checkNumber != nil
        }) else { return [] }
        var lines: [String] = []
        if let value = annotation.paidOn { lines.append("paid_on: \(value)") }
        if let value = annotation.amountPaid { lines.append("amount_paid: \(Money.format(value))") }
        if let value = annotation.paymentMethod { lines.append("payment_method: \(YAML.string(value))") }
        if let value = annotation.checkNumber { lines.append("check_number: \(YAML.string(value))") }
        return lines
    }

    private static func handwrittenLine(_ annotation: HandwrittenAnnotation) -> String {
        var derived: [String] = []
        if let value = annotation.paidOn { derived.append("paid_on \(value)") }
        if let value = annotation.amountPaid { derived.append("amount_paid \(Money.format(value))") }
        if let value = annotation.paymentMethod { derived.append("payment_method \(value)") }
        if let value = annotation.checkNumber { derived.append("check_number \(value)") }
        let quote = "- \"\(singleLine(SensitiveNumberMasker.mask(annotation.rawText)))\""
        return derived.isEmpty ? quote : "\(quote) → " + derived.joined(separator: ", ")
    }

    private static func keyFactLines(_ facts: KeyFacts) -> [String] {
        var lines: [String] = []
        let currency = facts.currency.map { " \($0)" } ?? ""
        if let value = facts.amountDue { lines.append("- Amount due: \(Money.format(value))\(currency)") }
        if let value = facts.dueDate { lines.append("- Due date: \(value)") }
        if let value = facts.amount { lines.append("- Amount: \(Money.format(value))\(currency)") }
        if let value = facts.accountLast4 { lines.append("- Account: ••••\(value)") }
        return lines
    }
}
