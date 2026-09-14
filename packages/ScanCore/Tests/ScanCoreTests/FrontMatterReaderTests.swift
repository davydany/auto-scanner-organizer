import Testing
@testable import ScanCore

struct FrontMatterReaderTests {
    @Test func readsTopLevelPropertiesAndUnquotesStrings() {
        let markdown = """
        ---
        title: "He said \\"hi\\""
        doc_date: 2026-08-28
        from: "Dominion Energy"
        tags: ["scanned"]
        ---
        # Body
        title: not front matter
        """
        let properties = FrontMatterReader.properties(of: markdown)
        #expect(properties["title"] == "He said \"hi\"")
        #expect(properties["doc_date"] == "2026-08-28")
        #expect(properties["from"] == "Dominion Energy")
        #expect(properties["tags"] == "[\"scanned\"]")
        #expect(properties.count == 4)
    }

    @Test func returnsEmptyWithoutFrontMatter() {
        #expect(FrontMatterReader.properties(of: "# Just a note\ntitle: x").isEmpty)
    }
}
