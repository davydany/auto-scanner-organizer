import Foundation

/// `batch.json`: written when a batch is complete and acts as its readiness marker (spec §5, §6).
public struct BatchManifest: Codable, Sendable, Equatable {
    public enum Source: String, Codable, Sendable {
        case scanner, drop
    }

    public struct Settings: Codable, Sendable, Equatable {
        public var unit: ScanSource
        public var dpi: Int
        public var color: ColorMode
        public var duplex: Bool

        public init(unit: ScanSource, dpi: Int, color: ColorMode, duplex: Bool) {
            self.unit = unit
            self.dpi = dpi
            self.color = color
            self.duplex = duplex
        }
    }

    public struct Interruption: Codable, Sendable, Equatable {
        public var afterPage: Int
        public var reason: String

        public init(afterPage: Int, reason: String) {
            self.afterPage = afterPage
            self.reason = reason
        }
    }

    public static let fileName = "batch.json"

    public var id: String
    public var source: Source
    public var scanner: String?
    public var settings: Settings?
    public var purpose: String?
    /// Page count known at scan time; 0 for dropped files until their pages are rendered.
    public var pages: Int
    public var startedAt: Date
    public var completedAt: Date?
    public var interrupted: Interruption?

    public init(id: String, source: Source, scanner: String?, settings: Settings?, purpose: String?, pages: Int,
                startedAt: Date, completedAt: Date?, interrupted: Interruption?) {
        self.id = id
        self.source = source
        self.scanner = scanner
        self.settings = settings
        self.purpose = purpose
        self.pages = pages
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.interrupted = interrupted
    }

    /// The manifest generated for a file dropped into staging by hand (spec §6).
    public static func drop(id: String, at date: Date) -> BatchManifest {
        BatchManifest(id: id, source: .drop, scanner: nil, settings: nil, purpose: nil, pages: 0,
                      startedAt: date, completedAt: date, interrupted: nil)
    }
}
