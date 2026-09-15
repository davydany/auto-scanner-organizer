import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum PageFixtureError: Error {
    case contextUnavailable
    case encodingFailed
}

/// Synthetic scanned pages for adapter tests: white pages with large black Helvetica text.
enum PageFixtures {
    static func textPage(_ lines: [String], width: Int = 2550, height: Int = 3300, fontSize: CGFloat = 80) throws -> CGImage {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { throw PageFixtureError.contextUnavailable }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        draw(lines, in: context, left: CGFloat(width) * 0.08, top: CGFloat(height) * 0.9, fontSize: fontSize)
        guard let image = context.makeImage() else { throw PageFixtureError.contextUnavailable }
        return image
    }

    static func writePNG(_ image: CGImage, to url: URL, dpi: Double? = nil) throws {
        try write(image, to: url, type: .png, properties: dpiProperties(dpi))
    }

    static func writeJPEG(_ image: CGImage, to url: URL, orientation: Int, dpi: Double? = nil) throws {
        var properties = dpiProperties(dpi)
        properties[kCGImagePropertyOrientation as String] = orientation
        try write(image, to: url, type: .jpeg, properties: properties)
    }

    /// A US Letter (612 × 792 pt) PDF with one text line per page.
    static func writePDF(pageTexts: [String], to url: URL) throws {
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else { throw PageFixtureError.contextUnavailable }
        for text in pageTexts {
            context.beginPDFPage(nil)
            draw([text], in: context, left: 72, top: 700, fontSize: 28)
            context.endPDFPage()
        }
        context.closePDF()
    }

    private static func dpiProperties(_ dpi: Double?) -> [String: Any] {
        guard let dpi else { return [:] }
        return [kCGImagePropertyDPIWidth as String: dpi, kCGImagePropertyDPIHeight as String: dpi]
    }

    private static func draw(_ lines: [String], in context: CGContext, left: CGFloat, top: CGFloat, fontSize: CGFloat) {
        let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        for (index, line) in lines.enumerated() {
            let attributed = NSAttributedString(string: line, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
            context.textPosition = CGPoint(x: left, y: top - CGFloat(index) * fontSize * 2)
            CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
        }
    }

    private static func write(_ image: CGImage, to url: URL, type: UTType, properties: [String: Any]) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw PageFixtureError.encodingFailed
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw PageFixtureError.encodingFailed }
    }
}
