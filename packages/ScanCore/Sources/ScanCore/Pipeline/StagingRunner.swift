import Foundation

public struct StagingPass: Sendable, Equatable {
    public var processed: [BatchSnapshot]
    /// Scanner batches stopped by a jam or disconnect; the app offers to continue or process them (spec §5).
    public var interrupted: [String]
    public var unreadable: [String]
    /// Batches whose last step failed; they wait for `BatchProcessor.retry`.
    public var skippedFailed: [String]

    public init(processed: [BatchSnapshot] = [], interrupted: [String] = [], unreadable: [String] = [], skippedFailed: [String] = []) {
        self.processed = processed
        self.interrupted = interrupted
        self.unreadable = unreadable
        self.skippedFailed = skippedFailed
    }
}

/// One pass over the staging folder: adopt settled drops, then run every ready batch (spec §6).
public actor StagingRunner {
    public let processor: BatchProcessor
    private let configuration: PipelineConfiguration
    private let services: PipelineServices
    private var tracker = DropTracker()

    public init(configuration: PipelineConfiguration, services: PipelineServices) {
        self.configuration = configuration
        self.services = services
        processor = BatchProcessor(configuration: configuration, services: services)
    }

    public func runOnce() async throws -> StagingPass {
        let scanner = StagingScanner(stagingRoot: configuration.stagingRoot, fileSystem: services.fileSystem)
        let scan = try scanner.scan(now: services.now(), tracker: &tracker)
        var ready = scan.readyBatches
        for drop in scan.stableDrops {
            ready.append(try scanner.adoptDroppedFile(drop, now: services.now(), timeZone: configuration.timeZone))
        }
        var pass = StagingPass(interrupted: scan.interruptedBatches.map(\.id), unreadable: scan.unreadableBatchIDs)
        for batch in ready.sorted(by: { $0.id < $1.id }) {
            let events = try await services.events.events(forBatch: batch.id)
            if case .failed = BatchProjection.snapshot(batchID: batch.id, events: events).status {
                pass.skippedFailed.append(batch.id)
            } else {
                pass.processed.append(try await processor.process(batch))
            }
        }
        return pass
    }
}
