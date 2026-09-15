import Foundation
import Testing
@testable import ScanCore

struct BatchManifestTests {
    @Test func roundTripsThroughScanCoreJSONWithSnakeCaseKeysAndISODates() throws {
        let manifest = BatchManifest(
            id: "2026-09-13-224203", source: .scanner, scanner: "Canon MF4700 Series",
            settings: BatchManifest.Settings(unit: .feeder, dpi: 300, color: .color, duplex: true),
            purpose: "2026 taxes, business receipts", pages: 7,
            startedAt: Date(timeIntervalSince1970: 1_789_353_723), completedAt: Date(timeIntervalSince1970: 1_789_353_758),
            interrupted: nil
        )
        let data = try ScanCoreJSON.encoder().encode(manifest)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"started_at\":\"2026-09-14T02:42:03Z\""))
        #expect(json.contains("\"source\":\"scanner\""))
        #expect(try ScanCoreJSON.decoder().decode(BatchManifest.self, from: data) == manifest)
    }

    @Test func decodesAnInterruptedManifest() throws {
        let json = """
        {"id":"b1","source":"scanner","scanner":"Canon","settings":{"unit":"feeder","dpi":300,"color":"grayscale","duplex":false},
         "purpose":null,"pages":4,"started_at":"2026-09-14T02:42:03Z","completed_at":null,
         "interrupted":{"after_page":4,"reason":"paper jam"}}
        """
        let manifest = try ScanCoreJSON.decoder().decode(BatchManifest.self, from: Data(json.utf8))
        #expect(manifest.interrupted == BatchManifest.Interruption(afterPage: 4, reason: "paper jam"))
        #expect(manifest.settings?.color == .grayscale)
    }
}
