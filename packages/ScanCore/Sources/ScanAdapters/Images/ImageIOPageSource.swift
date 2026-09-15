import CoreGraphics
import Foundation
import ImageIO
import ScanCore
import UniformTypeIdentifiers

/// Loads scanned or dropped pages with ImageIO and renders PDF pages with CoreGraphics (Milestone 2 probes B and C).
public struct ImageIOPageSource: PageImageSource {
    public static let pdfRenderDPI = 300.0
    public static let jpegQuality = 0.85
    /// Below this, file DPI metadata is a default (72 for photos), not a scan resolution.
    public static let minimumTrustedDPI = 100.0

    public init() {}

    public func pageRefs(for files: [URL]) throws -> [PageRef] {
        var refs: [PageRef] = []
        for file in files {
            if Self.isPDF(file) {
                guard let document = CGPDFDocument(file as CFURL), document.numberOfPages > 0 else {
                    throw PageImageError.unreadable(file.lastPathComponent)
                }
                refs += (0..<document.numberOfPages).map { PageRef(fileName: file.lastPathComponent, pageIndex: $0) }
            } else {
                refs.append(PageRef(fileName: file.lastPathComponent, pageIndex: 0))
            }
        }
        return refs
    }

    public func loadImage(_ page: PageRef, in folder: URL) throws -> PageImage {
        let url = folder.appending(path: page.fileName)
        if Self.isPDF(url) {
            return try Self.renderPDFPage(url, index: page.pageIndex, name: page.fileName)
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let width = properties[kCGImagePropertyPixelWidth as String] as? Int,
              let height = properties[kCGImagePropertyPixelHeight as String] as? Int
        else { throw PageImageError.unreadable(page.fileName) }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height),
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw PageImageError.unreadable(page.fileName)
        }
        let fileDPI = properties[kCGImagePropertyDPIWidth as String] as? Double ?? 0
        return PageImage(image: image, dpi: fileDPI >= Self.minimumTrustedDPI ? fileDPI : Self.pdfRenderDPI)
    }

    public func claudeJPEG(_ page: PageRef, in folder: URL, maxLongEdge: Int) throws -> Data {
        let image = try Self.downscaled(try loadImage(page, in: folder).image, maxLongEdge: maxLongEdge, name: page.fileName)
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw PageImageError.encodingFailed(page.fileName)
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: Self.jpegQuality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw PageImageError.encodingFailed(page.fileName) }
        return data as Data
    }

    private static func isPDF(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "pdf"
    }

    private static func renderPDFPage(_ url: URL, index: Int, name: String) throws -> PageImage {
        guard let document = CGPDFDocument(url as CFURL), let page = document.page(at: index + 1) else {
            throw PageImageError.unreadable(name)
        }
        let mediaBox = page.getBoxRect(.mediaBox)
        let scale = pdfRenderDPI / 72
        let width = Int((mediaBox.width * scale).rounded())
        let height = Int((mediaBox.height * scale).rounded())
        guard width > 0, height > 0, let context = bitmapContext(width: width, height: height) else {
            throw PageImageError.unreadable(name)
        }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.concatenate(page.getDrawingTransform(.mediaBox, rect: CGRect(origin: .zero, size: mediaBox.size), rotate: 0,
                                                     preserveAspectRatio: true))
        context.drawPDFPage(page)
        guard let image = context.makeImage() else { throw PageImageError.unreadable(name) }
        return PageImage(image: image, dpi: pdfRenderDPI)
    }

    static func downscaled(_ image: CGImage, maxLongEdge: Int, name: String) throws -> CGImage {
        let longEdge = max(image.width, image.height)
        guard longEdge > maxLongEdge else { return image }
        let scale = Double(maxLongEdge) / Double(longEdge)
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        guard let context = bitmapContext(width: width, height: height) else { throw PageImageError.encodingFailed(name) }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let scaled = context.makeImage() else { throw PageImageError.encodingFailed(name) }
        return scaled
    }

    private static func bitmapContext(width: Int, height: Int) -> CGContext? {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    }
}
