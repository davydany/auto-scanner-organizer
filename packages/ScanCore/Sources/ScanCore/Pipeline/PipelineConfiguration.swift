import Foundation

public struct PipelineConfiguration: Sendable {
    public var stagingRoot: URL
    public var vaultRoot: URL
    public var model: ClaudeModel
    /// Out-of-range and non-finite thresholds are handled by `FilingDecider`.
    public var threshold: Double
    public var timeZone: TimeZone

    public init(stagingRoot: URL, vaultRoot: URL, model: ClaudeModel = .sonnet5, threshold: Double = 0.75, timeZone: TimeZone = .current) {
        self.stagingRoot = stagingRoot
        self.vaultRoot = vaultRoot
        self.model = model
        self.threshold = threshold
        self.timeZone = timeZone
    }
}

public struct PipelineServices: Sendable {
    public var fileSystem: any FileSystem & FileAttributesReading
    public var events: any EventStore
    public var purposes: any PurposeStore
    public var pages: any PageImageSource
    public var recognizer: any TextRecognizer
    public var claude: any ClaudeMessaging
    public var now: @Sendable () -> Date

    public init(fileSystem: any FileSystem & FileAttributesReading = LocalFileSystem(), events: any EventStore, purposes: any PurposeStore,
                pages: any PageImageSource, recognizer: any TextRecognizer, claude: any ClaudeMessaging,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.fileSystem = fileSystem
        self.events = events
        self.purposes = purposes
        self.pages = pages
        self.recognizer = recognizer
        self.claude = claude
        self.now = now
    }
}

public enum PipelineError: Error, Equatable, Sendable {
    case noPages
    /// The PDF and note were written but the ledger could not be; a retry updates only the ledger.
    case ledgerWriteFailed(String)
}
