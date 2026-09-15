import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum LivePageError: Error {
    case contextUnavailable
    case encodingFailed
}

/// A synthetic four-page stack: an electric bill, a two-page receipt, and a water service notice.
enum LivePages {
    static let stack: [[String]] = [
        ["DOMINION ENERGY", "Electric Bill", "Statement date: August 28, 2026", "Account ending 7890", "Amount due: $142.18",
         "Please pay by September 18, 2026"],
        ["STAPLES", "Store #1123 Sales Receipt", "September 2, 2026", "Printer paper, 5 reams    $54.99", "Gel pens, 12 pack    $29.18", "Page 1 of 2"],
        ["STAPLES", "Store #1123 Sales Receipt (continued)", "Subtotal    $84.17", "Total USD    $84.17", "Paid with Visa ending 4242", "Page 2 of 2"],
        ["FAIRFAX WATER", "Notice of Scheduled Maintenance", "September 5, 2026", "Water service at your address will be interrupted",
         "on September 20 from 9 AM to 1 PM.", "No action is needed."],
    ]

    static func temporaryFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "LiveTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Writes `page-001.png`… at 200 dpi (1700 × 2200 px) and returns them in page order.
    static func writeStack(to folder: URL) throws -> [URL] {
        try stack.enumerated().map { index, lines in
            let url = folder.appending(path: String(format: "page-%03d.png", index + 1))
            try writePNG(try render(lines), to: url)
            return url
        }
    }

    private static func render(_ lines: [String]) throws -> CGImage {
        let width = 1700
        let height = 2200
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { throw LivePageError.contextUnavailable }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let font = CTFontCreateWithName("Helvetica" as CFString, 56, nil)
        for (index, line) in lines.enumerated() {
            let attributed = NSAttributedString(string: line, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
            context.textPosition = CGPoint(x: 150, y: CGFloat(height) - 250 - CGFloat(index) * 110)
            CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
        }
        guard let image = context.makeImage() else { throw LivePageError.contextUnavailable }
        return image
    }

    private static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw LivePageError.encodingFailed
        }
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyDPIWidth: 200, kCGImagePropertyDPIHeight: 200] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw LivePageError.encodingFailed }
    }
}
