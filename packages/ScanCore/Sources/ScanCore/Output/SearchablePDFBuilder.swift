import CoreGraphics
import CoreText
import Foundation

public struct RecognizedLine: Codable, Sendable, Equatable {
    public var text: String
    public var confidence: Float
    /// Normalized (0...1) rectangle with a bottom-left origin, as returned by Vision.
    public var boundingBox: CGRect

    public init(text: String, confidence: Float, boundingBox: CGRect) {
        self.text = text
        self.confidence = confidence
        self.boundingBox = boundingBox
    }
}

public struct PDFPageInput: @unchecked Sendable {
    public var image: CGImage
    public var lines: [RecognizedLine]
    public var dpi: Double

    public init(image: CGImage, lines: [RecognizedLine], dpi: Double) {
        self.image = image
        self.lines = lines
        self.dpi = dpi
    }
}

public enum SearchablePDFError: Error, Equatable, Sendable {
    case noPages
    case contextCreationFailed
}

/// Builds a PDF whose pages are the scanned images with an invisible, selectable text layer (spec §10.3).
public enum SearchablePDFBuilder {
    public static func build(pages: [PDFPageInput]) throws -> Data {
        guard !pages.isEmpty else { throw SearchablePDFError.noPages }
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { throw SearchablePDFError.contextCreationFailed }
        var defaultBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(consumer: consumer, mediaBox: &defaultBox, nil) else {
            throw SearchablePDFError.contextCreationFailed
        }
        for page in pages {
            draw(page, in: context)
        }
        context.closePDF()
        return data as Data
    }

    public static func pageSize(for page: PDFPageInput) -> CGSize {
        CGSize(width: Double(page.image.width) * 72 / page.dpi, height: Double(page.image.height) * 72 / page.dpi)
    }

    private static func draw(_ page: PDFPageInput, in context: CGContext) {
        let box = CGRect(origin: .zero, size: pageSize(for: page))
        let boxData = withUnsafeBytes(of: box) { Data($0) } as CFData
        context.beginPDFPage([kCGPDFContextMediaBox as String: boxData] as CFDictionary)
        context.draw(page.image, in: box)
        context.setTextDrawingMode(.invisible)
        for line in page.lines where !line.text.isEmpty {
            drawInvisible(line, pageBox: box, in: context)
        }
        context.endPDFPage()
    }

    private static func drawInvisible(_ line: RecognizedLine, pageBox: CGRect, in context: CGContext) {
        let rect = CGRect(
            x: line.boundingBox.minX * pageBox.width,
            y: line.boundingBox.minY * pageBox.height,
            width: line.boundingBox.width * pageBox.width,
            height: line.boundingBox.height * pageBox.height
        )
        let font = CTFontCreateWithName("Helvetica" as CFString, max(rect.height * 0.9, 1), nil)
        let attributed = NSAttributedString(string: line.text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        let ctLine = CTLineCreateWithAttributedString(attributed)
        let naturalWidth = CTLineGetTypographicBounds(ctLine, nil, nil, nil)
        context.saveGState()
        context.textMatrix = .identity
        context.translateBy(x: rect.minX, y: rect.minY + rect.height * 0.15)
        if naturalWidth > 0 {
            context.scaleBy(x: rect.width / CGFloat(naturalWidth), y: 1)
        }
        context.textPosition = .zero
        CTLineDraw(ctLine, context)
        context.restoreGState()
    }
}
