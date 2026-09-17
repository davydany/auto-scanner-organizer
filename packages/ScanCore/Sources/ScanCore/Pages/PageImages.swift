import CoreGraphics
import Foundation

/// One page of a staged batch: an image file, or one page (0-based) of a PDF file.
public struct PageRef: Codable, Sendable, Equatable, Hashable {
    public var fileName: String
    public var pageIndex: Int

    public init(fileName: String, pageIndex: Int) {
        self.fileName = fileName
        self.pageIndex = pageIndex
    }
}

/// A decoded, upright page image and its resolution.
/// `@unchecked` because `CGImage` is an immutable Core Foundation object that is safe to share across tasks.
public struct PageImage: @unchecked Sendable {
    public var image: CGImage
    public var dpi: Double

    public init(image: CGImage, dpi: Double) {
        self.image = image
        self.dpi = dpi
    }
}

public enum PageImageError: Error, Equatable, Sendable {
    case unreadable(String)
    case encodingFailed(String)
}

/// Reads batch pages for OCR, the searchable PDF, and Claude (spec §6, §7, §8.1). The ImageIO adapter lives in ScanAdapters.
public protocol PageImageSource: Sendable {
    /// Page references in file order; each PDF contributes one reference per page.
    func pageRefs(for files: [URL]) throws -> [PageRef]
    func loadImage(_ page: PageRef, in folder: URL) throws -> PageImage
    /// A JPEG at quality 0.85 whose long edge is at most `maxLongEdge` pixels (never upscaled).
    func claudeJPEG(_ page: PageRef, in folder: URL, maxLongEdge: Int) throws -> Data
}
