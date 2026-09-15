import CoreGraphics
import Foundation

/// Recognizes the text lines on one page image. The Vision adapter lives in ScanAdapters.
public protocol TextRecognizer: Sendable {
    func recognize(_ page: PageImage) async throws -> [RecognizedLine]
}

/// One page's OCR result, stored in the batch's `.scancore/ocr.json` (Milestone 2 ADR).
public struct PageText: Codable, Sendable, Equatable {
    public var page: PageRef
    public var lines: [RecognizedLine]

    public init(page: PageRef, lines: [RecognizedLine]) {
        self.page = page
        self.lines = lines
    }

    public var text: String {
        lines.map(\.text).joined(separator: "\n")
    }
}

public enum OCRCleanup {
    /// Trims text, drops empty lines, and clamps boxes into the unit square; a line whose box is not finite
    /// or has no area left after clamping can't be placed in the PDF's text layer and is dropped.
    public static func clean(_ lines: [RecognizedLine]) -> [RecognizedLine] {
        lines.compactMap { line in
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let box = line.boundingBox
            guard !text.isEmpty, [box.minX, box.minY, box.maxX, box.maxY].allSatisfy(\.isFinite) else { return nil }
            let minX = min(max(box.minX, 0), 1)
            let minY = min(max(box.minY, 0), 1)
            let maxX = min(max(box.maxX, 0), 1)
            let maxY = min(max(box.maxY, 0), 1)
            guard maxX > minX, maxY > minY else { return nil }
            return RecognizedLine(text: text, confidence: line.confidence,
                                  boundingBox: CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY))
        }
    }
}

public enum BatchOCR {
    public static let maxConcurrentPages = 4

    /// Recognizes every page, at most four at a time (spec §7), returning results in page order.
    public static func recognize(pages: [PageRef], in folder: URL, source: any PageImageSource,
                                 recognizer: any TextRecognizer) async throws -> [PageText] {
        try await withThrowingTaskGroup(of: (index: Int, lines: [RecognizedLine]).self) { group in
            var results = [[RecognizedLine]](repeating: [], count: pages.count)
            for (index, page) in pages.enumerated() {
                if index >= maxConcurrentPages, let finished = try await group.next() {
                    results[finished.index] = finished.lines
                }
                group.addTask {
                    let image = try source.loadImage(page, in: folder)
                    return (index, OCRCleanup.clean(try await recognizer.recognize(image)))
                }
            }
            for try await finished in group {
                results[finished.index] = finished.lines
            }
            return zip(pages, results).map { PageText(page: $0, lines: $1) }
        }
    }
}
