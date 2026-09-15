import Foundation
import ScanAdapters
import ScanCore

/// Wires the real adapters to the pipeline for one command. The API key comes only from ANTHROPIC_API_KEY (Milestone 2 ADR).
struct CLIRunner {
    let environment: [String: String]
    let output: @Sendable (String) -> Void

    func run(_ command: CLICommand) async throws {
        switch command {
        case .version:
            output("scan-organizer \(ScanAdapters.version)")
        case .help:
            output(CLIArguments.usage)
        case .status(let data):
            try await status(data: data)
        case let .process(options, watch):
            try await process(options, watch: watch)
        case let .review(options, batchID, documentID, resolution):
            let (configuration, services) = try pipeline(options)
            let batch = try stagedBatch(batchID, in: options.staging)
            let snapshot = try await BatchProcessor(configuration: configuration, services: services)
                .resolveReview(batch, documentID: documentID, resolution: resolution)
            BatchReport.lines(for: snapshot, events: try await services.events.events(forBatch: batchID)).forEach(output)
        case let .retry(options, batchID):
            let (configuration, services) = try pipeline(options)
            let batch = try stagedBatch(batchID, in: options.staging)
            let processor = BatchProcessor(configuration: configuration, services: services)
            try await processor.retry(batchID: batchID)
            let snapshot = try await processor.process(batch)
            BatchReport.lines(for: snapshot, events: try await services.events.events(forBatch: batchID)).forEach(output)
        }
    }

    private func status(data: URL) async throws {
        let events = JSONLinesEventStore(fileURL: data.appending(path: "events.jsonl"))
        let batchIDs = try await events.batchIDs()
        guard !batchIDs.isEmpty else {
            output("No batches yet.")
            return
        }
        for batchID in batchIDs {
            let log = try await events.events(forBatch: batchID)
            BatchReport.lines(for: BatchProjection.snapshot(batchID: batchID, events: log), events: log).forEach(output)
        }
    }

    private func process(_ options: PipelineOptions, watch: Bool) async throws {
        let (configuration, services) = try pipeline(options)
        let runner = StagingRunner(configuration: configuration, services: services)
        var reported: [String: [String]] = [:]
        func report(_ pass: StagingPass) async throws {
            for snapshot in pass.processed {
                let lines = BatchReport.lines(for: snapshot, events: try await services.events.events(forBatch: snapshot.batchID))
                if reported[snapshot.batchID] != lines {
                    lines.forEach(output)
                    reported[snapshot.batchID] = lines
                }
            }
            let notices = pass.interrupted.map { ($0, "interrupted; finish or restart the scan") }
                + pass.unreadable.map { ($0, "batch.json is unreadable") }
                + pass.skippedFailed.map { ($0, "failed; run: scan-organizer retry \($0) --staging … --vault …") }
            for (batchID, notice) in notices where reported[batchID] == nil {
                output("\(batchID)  \(notice)")
                reported[batchID] = [notice]
            }
        }
        guard watch else {
            let pass = try await runner.runOnce()
            if pass == StagingPass() { output("Nothing to process in \(options.staging.path(percentEncoded: false)).") }
            try await report(pass)
            return
        }
        output("Watching \(options.staging.path(percentEncoded: false)). Press Control-C to stop.")
        for await _ in StagingWatcher(root: options.staging).changes() {
            try await report(try await runner.runOnce())
        }
    }

    private func pipeline(_ options: PipelineOptions) throws -> (PipelineConfiguration, PipelineServices) {
        guard let apiKey = environment["ANTHROPIC_API_KEY"], !apiKey.isEmpty else {
            throw CLIRunError(description: "Set ANTHROPIC_API_KEY in the environment to run the pipeline.")
        }
        for (flag, url) in [("--staging", options.staging), ("--vault", options.vault)] {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory), isDirectory.boolValue else {
                throw CLIRunError(description: "\(flag) folder does not exist: \(url.path(percentEncoded: false))")
            }
        }
        let configuration = PipelineConfiguration(stagingRoot: options.staging, vaultRoot: options.vault, model: options.model,
                                                  threshold: options.threshold)
        let services = PipelineServices(
            events: JSONLinesEventStore(fileURL: options.data.appending(path: "events.jsonl")),
            purposes: JSONFilePurposeStore(fileURL: options.data.appending(path: "purposes.json")),
            pages: ImageIOPageSource(), recognizer: VisionTextRecognizer(),
            claude: ClaudeClient(apiKey: apiKey, transport: URLSessionClaudeTransport())
        )
        return (configuration, services)
    }

    private func stagedBatch(_ batchID: String, in staging: URL) throws -> StagedBatch {
        var tracker = DropTracker()
        let scan = try StagingScanner(stagingRoot: staging).scan(now: Date(), tracker: &tracker)
        guard let batch = scan.readyBatches.first(where: { $0.id == batchID }) else {
            throw CLIRunError(description: "batch \(batchID) is not waiting in \(staging.path(percentEncoded: false))")
        }
        return batch
    }
}
