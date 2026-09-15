import CoreGraphics
import Foundation
import Testing
@testable import ScanAdapters
@testable import ScanCore

struct VisionTextRecognizerTests {
    @Test func recognizesTextLinesWithNormalizedBottomLeftBoxes() async throws {
        let image = try PageFixtures.textPage(["DOMINION ENERGY", "Account ending 7890", "Amount due $142.18"])

        let lines = try await VisionTextRecognizer().recognize(PageImage(image: image, dpi: 300))

        let top = try #require(lines.first { $0.text.uppercased().contains("DOMINION ENERGY") })
        let bottom = try #require(lines.first { $0.text.contains("142.18") })
        #expect(top.boundingBox.minY > bottom.boundingBox.minY)
        let unit = CGRect(x: 0, y: 0, width: 1, height: 1).insetBy(dx: -0.01, dy: -0.01)
        #expect(lines.allSatisfy { unit.contains($0.boundingBox) && $0.confidence > 0 })
    }

    @Test func recognizesEveryPageOfAStagedBatch() async throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let png = temp.url.appending(path: "page-001.png")
        let pdf = temp.url.appending(path: "receipt.pdf")
        try PageFixtures.writePNG(try PageFixtures.textPage(["PAGE ONE INVOICE"]), to: png, dpi: 300)
        try PageFixtures.writePDF(pageTexts: ["SECOND PAGE RECEIPT"], to: pdf)
        let source = ImageIOPageSource()

        let pages = try await BatchOCR.recognize(pages: try source.pageRefs(for: [png, pdf]), in: temp.url, source: source,
                                                 recognizer: VisionTextRecognizer())

        #expect(pages.count == 2)
        #expect(pages[0].text.uppercased().contains("PAGE ONE INVOICE"))
        #expect(pages[1].text.uppercased().contains("SECOND PAGE RECEIPT"))
    }
}
