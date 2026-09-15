import CoreGraphics
import Foundation
import Testing
@testable import ScanCore

struct BatchOCRTests {
    let folder = URL(filePath: "/tmp/unused-batch")

    func refs(_ count: Int) -> [PageRef] {
        (1...count).map { PageRef(fileName: String(format: "page-%03d.png", $0), pageIndex: 0) }
    }

    @Test func recognizesPagesInOrderWithAtMostFourAtOnce() async throws {
        let probe = ConcurrencyProbe()
        let recognizer = FakeTextRecognizer(probe: probe, delay: { .milliseconds((10 - $0) * 5) })

        let pages = try await BatchOCR.recognize(pages: refs(9), in: folder, source: FakePageSource(), recognizer: recognizer)

        #expect(pages.map(\.page) == refs(9))
        #expect(pages.map(\.text) == (1...9).map { "Page \($0) text" })
        let peak = await probe.peak
        #expect(peak <= BatchOCR.maxConcurrentPages)
        #expect(peak >= 2)
    }

    @Test func joinsLineTextAndPropagatesFailures() async throws {
        let recognizer = FakeTextRecognizer(texts: [1: ["DOMINION ENERGY", "Amount due $142.18"]], failingPages: [3])

        await #expect(throws: FakeOCRError(page: 3)) {
            try await BatchOCR.recognize(pages: refs(3), in: folder, source: FakePageSource(), recognizer: recognizer)
        }
        let pages = try await BatchOCR.recognize(pages: refs(2), in: folder, source: FakePageSource(), recognizer: recognizer)
        #expect(pages[0].text == "DOMINION ENERGY\nAmount due $142.18")
    }

    @Test func cleanupTrimsDropsAndClampsLines() {
        let lines = [
            RecognizedLine(text: "  Total  ", confidence: 0.9, boundingBox: CGRect(x: -0.25, y: 0.75, width: 0.5, height: 0.5)),
            RecognizedLine(text: "   ", confidence: 0.9, boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.1)),
            RecognizedLine(text: "Off page", confidence: 0.5, boundingBox: CGRect(x: 1.5, y: 0.5, width: 0.25, height: 0.25)),
            RecognizedLine(text: "Broken", confidence: 0.5, boundingBox: CGRect(x: Double.nan, y: 0.5, width: 0.25, height: 0.25)),
            RecognizedLine(text: "Kept", confidence: 1, boundingBox: CGRect(x: 0.5, y: 0.25, width: 0.25, height: 0.125)),
        ]

        #expect(OCRCleanup.clean(lines) == [
            RecognizedLine(text: "Total", confidence: 0.9, boundingBox: CGRect(x: 0, y: 0.75, width: 0.25, height: 0.25)),
            RecognizedLine(text: "Kept", confidence: 1, boundingBox: CGRect(x: 0.5, y: 0.25, width: 0.25, height: 0.125)),
        ])
    }

    @Test func pageTextRoundTripsThroughScanCoreJSON() throws {
        let page = PageText(page: PageRef(fileName: "statement.pdf", pageIndex: 2),
                            lines: [RecognizedLine(text: "Hello", confidence: 0.5, boundingBox: CGRect(x: 0.125, y: 0.5, width: 0.25, height: 0.125))])
        let data = try ScanCoreJSON.encoder().encode([page])
        #expect(try ScanCoreJSON.decoder().decode([PageText].self, from: data) == [page])
    }
}
