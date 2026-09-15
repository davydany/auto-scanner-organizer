import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import ScanAdapters
@testable import ScanCore

struct ImageIOPageSourceTests {
    let source = ImageIOPageSource()

    @Test func expandsPDFsIntoOnePageRefPerPage() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let png = temp.url.appending(path: "page-001.png")
        let pdf = temp.url.appending(path: "statement.pdf")
        try PageFixtures.writePNG(try PageFixtures.textPage(["ONE"], width: 850, height: 1100), to: png)
        try PageFixtures.writePDF(pageTexts: ["FIRST", "SECOND"], to: pdf)

        #expect(try source.pageRefs(for: [png, pdf]) == [
            PageRef(fileName: "page-001.png", pageIndex: 0),
            PageRef(fileName: "statement.pdf", pageIndex: 0),
            PageRef(fileName: "statement.pdf", pageIndex: 1),
        ])
    }

    @Test func expandsMultiPageTIFFsIntoOnePageRefPerFrame() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let tiff = temp.url.appending(path: "receipts.tiff")
        try PageFixtures.writeTIFF(frames: [try PageFixtures.textPage(["FIRST"], width: 850, height: 1100),
                                            try PageFixtures.textPage(["SECOND"], width: 1275, height: 1650)], to: tiff)
        let frames = [PageRef(fileName: "receipts.tiff", pageIndex: 0), PageRef(fileName: "receipts.tiff", pageIndex: 1)]

        #expect(try source.pageRefs(for: [tiff]) == frames)
        let sizes = try frames.map { try source.loadImage($0, in: temp.url).image }.map { [$0.width, $0.height] }
        #expect(sizes == [[850, 1100], [1275, 1650]])
    }

    @Test func rendersPDFPagesAt300DPI() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        try PageFixtures.writePDF(pageTexts: ["FIRST", "SECOND"], to: temp.url.appending(path: "statement.pdf"))

        let page = try source.loadImage(PageRef(fileName: "statement.pdf", pageIndex: 1), in: temp.url)

        #expect(page.image.width == 2550)
        #expect(page.image.height == 3300)
        #expect(page.dpi == 300)
    }

    @Test func usesTrustedFileResolutionAndDefaultsTo300() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let image = try PageFixtures.textPage(["DPI"], width: 1275, height: 1650)
        try PageFixtures.writePNG(image, to: temp.url.appending(path: "scan-150.png"), dpi: 150)
        try PageFixtures.writePNG(image, to: temp.url.appending(path: "no-dpi.png"))
        try PageFixtures.writeJPEG(image, to: temp.url.appending(path: "photo.jpg"), orientation: 1, dpi: 72)

        let scanned = try source.loadImage(PageRef(fileName: "scan-150.png", pageIndex: 0), in: temp.url)
        #expect(scanned.dpi == 150)
        #expect(scanned.image.width == 1275)
        #expect(try source.loadImage(PageRef(fileName: "no-dpi.png", pageIndex: 0), in: temp.url).dpi == 300)
        #expect(try source.loadImage(PageRef(fileName: "photo.jpg", pageIndex: 0), in: temp.url).dpi == 300)
    }

    @Test func appliesEXIFOrientationWhenLoading() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        try PageFixtures.writeJPEG(try PageFixtures.textPage(["SIDEWAYS"], width: 400, height: 200), to: temp.url.appending(path: "photo.jpg"), orientation: 6)

        let page = try source.loadImage(PageRef(fileName: "photo.jpg", pageIndex: 0), in: temp.url)

        #expect(page.image.width == 200)
        #expect(page.image.height == 400)
    }

    @Test func downscalesAndEncodesJPEGForClaudeWithoutUpscaling() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        try PageFixtures.writePNG(try PageFixtures.textPage(["BIG"]), to: temp.url.appending(path: "big.png"))
        try PageFixtures.writePNG(try PageFixtures.textPage(["SMALL"], width: 1000, height: 800), to: temp.url.appending(path: "small.png"))

        for (maxEdge, width, height) in [(2576, 1991, 2576), (1568, 1212, 1568)] {
            let data = try source.claudeJPEG(PageRef(fileName: "big.png", pageIndex: 0), in: temp.url, maxLongEdge: maxEdge)
            let decoded = try #require(CGImageSourceCreateWithData(data as CFData, nil))
            #expect(CGImageSourceGetType(decoded) as String? == "public.jpeg")
            let image = try #require(CGImageSourceCreateImageAtIndex(decoded, 0, nil))
            #expect(image.width == width)
            #expect(image.height == height)
        }
        let small = try source.claudeJPEG(PageRef(fileName: "small.png", pageIndex: 0), in: temp.url, maxLongEdge: 2576)
        let smallImage = try #require(CGImageSourceCreateWithData(small as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) })
        #expect(smallImage.width == 1000)
        #expect(smallImage.height == 800)
    }

    @Test func reportsUnreadableFiles() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        try Data("not an image".utf8).write(to: temp.url.appending(path: "bad.png"))
        try Data("not a pdf".utf8).write(to: temp.url.appending(path: "bad.pdf"))
        try Data("not a tiff".utf8).write(to: temp.url.appending(path: "bad.tiff"))

        #expect(throws: PageImageError.unreadable("bad.png")) {
            try source.loadImage(PageRef(fileName: "bad.png", pageIndex: 0), in: temp.url)
        }
        #expect(throws: PageImageError.unreadable("bad.pdf")) { try source.pageRefs(for: [temp.url.appending(path: "bad.pdf")]) }
        #expect(throws: PageImageError.unreadable("bad.tiff")) { try source.pageRefs(for: [temp.url.appending(path: "bad.tiff")]) }
        #expect(throws: PageImageError.unreadable("missing.tiff")) { try source.pageRefs(for: [temp.url.appending(path: "missing.tiff")]) }
    }
}
