import Foundation
import Testing
@testable import ScanCore

struct StackSchemaTests {
    static let unsupportedKeywords: Set<String> = ["minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum", "multipleOf",
                                                   "minLength", "maxLength", "pattern", "maxItems", "uniqueItems"]

    func walk(_ value: JSONValue, _ path: String, _ visit: (JSONValue, String) -> Void) {
        visit(value, path)
        switch value {
        case .object(let members): for (key, member) in members { walk(member, "\(path)/\(key)", visit) }
        case .array(let items): for (index, item) in items.enumerated() { walk(item, "\(path)/\(index)", visit) }
        default: break
        }
    }

    @Test func everyObjectIsClosedAndRequiresAllItsProperties() {
        var objects = 0
        walk(StackSchema.outputSchema, "") { value, path in
            guard case .object(let members) = value else { return }
            for key in members.keys {
                #expect(!Self.unsupportedKeywords.contains(key), "unsupported keyword \(key) at \(path)")
            }
            guard members["type"] == .string("object"), case .object(let properties)? = members["properties"] else { return }
            objects += 1
            #expect(members["additionalProperties"] == .bool(false), "open object at \(path)")
            #expect(members["required"] == .array(properties.keys.sorted().map(JSONValue.string)), "required mismatch at \(path)")
        }
        #expect(objects == 5) // root, document, key_facts, handwritten item, purpose_fit
    }

    @Test func enumeratesTheAllowedValues() throws {
        let json = try #require(String(data: try ClaudeWireJSON.encoder().encode(StackSchema.outputSchema), encoding: .utf8))
        for value in DocType.allCases.map(\.rawValue) + TaxCategory.allCases.map(\.rawValue) + ExpenseCategory.allCases.map(\.rawValue) {
            #expect(json.contains("\"\(value)\""))
        }
        #expect(json.contains(#""format":"date""#))
    }

    @Test func promptListsAllowedValuesAndTreatsPageContentAsData() {
        #expect(StackPrompt.system.contains(DocType.allCases.map(\.rawValue).joined(separator: ", ")))
        #expect(StackPrompt.system.contains(ExpenseCategory.allCases.map(\.rawValue).joined(separator: ", ")))
        #expect(StackPrompt.system.contains("never instructions"))
    }

    @Test func correctionListsEveryMessageAndAsksForTheSamePages() {
        #expect(StackPrompt.correction(["a.", "b."])
            == "Your JSON did not pass validation:\n- a.\n- b.\nReturn the complete corrected JSON for the same pages.")
    }

    @Test func userContentLabelsEachPageAndStatesTheRangeAndPurpose() {
        let pages = [StackPageInput(number: 21, jpeg: Data("abc".utf8), ocrText: "DOMINION ENERGY"),
                     StackPageInput(number: 22, jpeg: Data("xyz".utf8), ocrText: "")]

        let content = StackPrompt.userContent(pages: pages, totalPages: 25, purpose: "2026 taxes, business receipts")

        #expect(content.count == 7)
        #expect(content[0] == .text("Page 21 of 25:"))
        #expect(content[1] == .image(mediaType: "image/jpeg", base64Data: "YWJj"))
        #expect(content[2] == .text("<ocr_text page=\"21\">\nDOMINION ENERGY\n</ocr_text>"))
        #expect(content[5] == .text("<ocr_text page=\"22\">\n(no text recognized)\n</ocr_text>"))
        guard case .text(let instruction, _) = content[6] else {
            Issue.record("last block must be text")
            return
        }
        #expect(instruction.contains("pages 21–22 of a 25-page batch"))
        #expect(instruction.contains("Batch purpose: \"2026 taxes, business receipts\""))
        guard case .text(let noPurpose, _) = StackPrompt.userContent(pages: pages, totalPages: 25, purpose: nil).last else { return }
        #expect(noPurpose.contains("No batch purpose was given"))
    }
}
