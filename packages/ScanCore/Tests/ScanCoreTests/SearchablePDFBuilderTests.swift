import CoreGraphics
import Foundation
import PDFKit
import Testing
@testable import ScanCore

struct SearchablePDFBuilderTests {
    func blankImage(width: Int = 850, height: Int = 1100) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(context.makeImage())
    }

    @Test func embedsInvisibleTextThatCanBeExtracted() throws {
        let page = PDFPageInput(image: try blankImage(), lines: [
            RecognizedLine(text: "Dominion Energy Electric Bill", confidence: 0.99, boundingBox: CGRect(x: 0.1, y: 0.8, width: 0.6, height: 0.03)),
            RecognizedLine(text: "Amount due $142.18", confidence: 0.98, boundingBox: CGRect(x: 0.1, y: 0.7, width: 0.4, height: 0.03)),
        ], dpi: 100)
        let data = try SearchablePDFBuilder.build(pages: [page])
        let document = try #require(PDFDocument(data: data))
        let text = document.string ?? ""
        #expect(text.contains("Dominion Energy Electric Bill"))
        #expect(text.contains("Amount due $142.18"))
    }

    @Test func sizesPagesFromPixelsAndDPI() throws {
        let page = PDFPageInput(image: try blankImage(width: 850, height: 1100), lines: [], dpi: 100)
        #expect(SearchablePDFBuilder.pageSize(for: page) == CGSize(width: 612, height: 792))
        let document = try #require(PDFDocument(data: try SearchablePDFBuilder.build(pages: [page])))
        let bounds = try #require(document.page(at: 0)).bounds(for: .mediaBox)
        #expect(abs(bounds.width - 612) < 0.5)
        #expect(abs(bounds.height - 792) < 0.5)
    }

    @Test func buildsOnePDFPagePerInputPage() throws {
        let image = try blankImage()
        let pages = (1...3).map { index in
            PDFPageInput(image: image, lines: [
                RecognizedLine(text: "page number \(index)", confidence: 1, boundingBox: CGRect(x: 0.1, y: 0.5, width: 0.3, height: 0.03)),
            ], dpi: 100)
        }
        let document = try #require(PDFDocument(data: try SearchablePDFBuilder.build(pages: pages)))
        #expect(document.pageCount == 3)
        #expect(document.page(at: 1)?.string?.contains("page number 2") == true)
    }

    @Test func rejectsEmptyInput() {
        #expect(throws: SearchablePDFError.noPages) { try SearchablePDFBuilder.build(pages: []) }
    }

    @Test(arguments: [0.0, -72.0, Double.infinity]) func rejectsNonPositiveOrInfiniteDPI(_ dpi: Double) throws {
        let page = PDFPageInput(image: try blankImage(), lines: [], dpi: dpi)
        #expect(throws: SearchablePDFError.invalidDPI(dpi)) { try SearchablePDFBuilder.build(pages: [page]) }
    }

    @Test func rejectsNaNDPI() throws {
        let page = PDFPageInput(image: try blankImage(), lines: [], dpi: .nan)
        do {
            _ = try SearchablePDFBuilder.build(pages: [page])
            Issue.record("Expected invalidDPI")
        } catch SearchablePDFError.invalidDPI(let value) {
            #expect(value.isNaN)
        }
    }

    @Test func rejectsInvalidDPIOnAnyPage() throws {
        let image = try blankImage()
        let pages = [
            PDFPageInput(image: image, lines: [], dpi: 100),
            PDFPageInput(image: image, lines: [], dpi: 0),
        ]
        #expect(throws: SearchablePDFError.invalidDPI(0)) { try SearchablePDFBuilder.build(pages: pages) }
    }
}
