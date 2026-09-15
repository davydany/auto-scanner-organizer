import CoreGraphics
import Foundation
@testable import ScanCore

/// Encodes each page's number in its image width, so fakes downstream can tell pages apart.
struct FakePageSource: PageImageSource {
    static func pageNumber(of fileName: String) -> Int {
        Int(fileName.drop { !$0.isNumber }.prefix { $0.isNumber }) ?? 0
    }

    func pageRefs(for files: [URL]) throws -> [PageRef] {
        files.map { PageRef(fileName: $0.lastPathComponent, pageIndex: 0) }
    }

    func loadImage(_ page: PageRef, in folder: URL) throws -> PageImage {
        let width = 1000 + Self.pageNumber(of: page.fileName)
        guard let context = CGContext(data: nil, width: width, height: 10, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
              let image = context.makeImage()
        else { throw PageImageError.encodingFailed(page.fileName) }
        return PageImage(image: image, dpi: 300)
    }

    func claudeJPEG(_ page: PageRef, in folder: URL, maxLongEdge: Int) throws -> Data {
        Data("jpeg:\(page.fileName)#\(page.pageIndex)@\(maxLongEdge)".utf8)
    }
}

actor ConcurrencyProbe {
    private(set) var peak = 0
    private var current = 0

    func enter() {
        current += 1
        peak = max(peak, current)
    }

    func leave() {
        current -= 1
    }
}

struct FakeOCRError: Error, Equatable {
    let page: Int
}

struct FakeTextRecognizer: TextRecognizer {
    var texts: [Int: [String]] = [:]
    var failingPages: Set<Int> = []
    var probe: ConcurrencyProbe?
    var delay: @Sendable (Int) -> Duration = { _ in .zero }

    func recognize(_ page: PageImage) async throws -> [RecognizedLine] {
        let number = page.image.width - 1000
        await probe?.enter()
        try await Task.sleep(for: delay(number))
        await probe?.leave()
        if failingPages.contains(number) { throw FakeOCRError(page: number) }
        return (texts[number] ?? ["Page \(number) text"]).enumerated().map { index, text in
            RecognizedLine(text: text, confidence: 1, boundingBox: CGRect(x: 0.1, y: 0.875 - Double(index) * 0.125, width: 0.5, height: 0.0625))
        }
    }
}
