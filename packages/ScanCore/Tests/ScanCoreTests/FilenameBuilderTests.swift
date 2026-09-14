import Testing
@testable import ScanCore

struct FilenameBuilderTests {
    let day = CalendarDay("2026-08-28")!

    @Test func buildsDateFromTitle() {
        #expect(FilenameBuilder.baseName(date: day, from: "Dominion Energy", title: "Electric Bill")
            == "2026-08-28 Dominion Energy - Electric Bill")
    }

    @Test func omitsSenderWhenMissingOrBlank() {
        #expect(FilenameBuilder.baseName(date: day, from: nil, title: "Gutter Note") == "2026-08-28 Gutter Note")
        #expect(FilenameBuilder.baseName(date: day, from: "  ", title: "Gutter Note") == "2026-08-28 Gutter Note")
    }

    @Test func stripsForbiddenCharactersAndCollapsesWhitespace() {
        #expect(FilenameBuilder.sanitize("Q3/Q4: \"Final\" [draft] #2 ^x | a*b?<c>\\d") == "Q3Q4 Final draft 2 x abcd")
        #expect(FilenameBuilder.sanitize("Line one\nLine\ttwo   end") == "Line one Line two end")
    }

    @Test func truncatesAtWordBoundaryWithinLimit() {
        let title = String(repeating: "Word ", count: 40)
        let name = FilenameBuilder.baseName(date: day, from: "Sender", title: title)
        #expect(name.count <= FilenameBuilder.maxLength)
        #expect(name.hasPrefix("2026-08-28 Sender - Word"))
        #expect(!name.hasSuffix(" "))
        #expect(name.hasSuffix("Word"))
    }

    @Test func returnsBaseWhenNoCollision() {
        #expect(FilenameBuilder.uniqueBaseName("2026-08-28 A - B", existingFileNames: ["other.pdf"]) == "2026-08-28 A - B")
    }

    @Test func appendsCounterWhenPdfOrNoteExists() {
        let existing: Set<String> = ["2026-08-28 A - B.pdf", "2026-08-28 A - B (2).md"]
        #expect(FilenameBuilder.uniqueBaseName("2026-08-28 A - B", existingFileNames: existing) == "2026-08-28 A - B (3)")
    }
}
