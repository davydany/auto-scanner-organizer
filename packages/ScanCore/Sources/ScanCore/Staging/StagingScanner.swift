import Foundation

public struct StagedBatch: Sendable, Equatable {
    public var id: String
    public var folderURL: URL
    public var manifest: BatchManifest

    public init(id: String, folderURL: URL, manifest: BatchManifest) {
        self.id = id
        self.folderURL = folderURL
        self.manifest = manifest
    }
}

/// Remembers the last seen size of each dropped file so stability can be judged across scans.
public struct DropTracker: Sendable, Equatable {
    struct Observation: Sendable, Equatable {
        var size: Int
        var since: Date
    }

    var observations: [String: Observation] = [:]

    public init() {}
}

public struct StagingScanResult: Sendable, Equatable {
    public var readyBatches: [StagedBatch] = []
    public var interruptedBatches: [StagedBatch] = []
    public var stableDrops: [URL] = []
    public var unreadableBatchIDs: [String] = []
}

/// Pure readiness logic for the staging folder (spec §6). The watcher adapter decides when to call `scan`.
public struct StagingScanner: Sendable {
    public static let doneFolderName = "_done"
    public static let adoptableExtensions: Set<String> = ["pdf", "png", "jpg", "jpeg", "heic", "tiff"]
    public static let stabilityInterval: TimeInterval = 5

    public let stagingRoot: URL
    private let fileSystem: any FileSystem & FileAttributesReading

    public init(stagingRoot: URL, fileSystem: any FileSystem & FileAttributesReading = LocalFileSystem()) {
        self.stagingRoot = stagingRoot
        self.fileSystem = fileSystem
    }

    public func scan(now: Date, tracker: inout DropTracker) throws -> StagingScanResult {
        var result = StagingScanResult()
        var seenDrops: Set<String> = []
        // `contentsOfDirectory` skips hidden entries, so `.scancore` and other dot-folders never appear.
        for url in try fileSystem.contentsOfDirectory(at: stagingRoot) {
            let name = url.lastPathComponent
            if name == Self.doneFolderName { continue }
            if fileSystem.isDirectory(at: url) {
                try inspectBatchFolder(url, name: name, now: now, into: &result)
            } else if Self.isAdoptable(url) {
                seenDrops.insert(name)
                let size = try fileSystem.attributes(at: url).size
                if let previous = tracker.observations[name], previous.size == size {
                    if now.timeIntervalSince(previous.since) >= Self.stabilityInterval {
                        result.stableDrops.append(url)
                    }
                } else {
                    tracker.observations[name] = DropTracker.Observation(size: size, since: now)
                }
            }
        }
        tracker.observations = tracker.observations.filter { seenDrops.contains($0.key) }
        return result
    }

    public func adoptDroppedFile(_ fileURL: URL, now: Date, timeZone: TimeZone) throws -> StagedBatch {
        let base = "drop-\(Self.timestamp(now, timeZone: timeZone))"
        var id = base
        var counter = 2
        while fileSystem.fileExists(at: stagingRoot.appending(path: id)) {
            id = "\(base)-\(counter)"
            counter += 1
        }
        let folder = stagingRoot.appending(path: id)
        try fileSystem.createDirectory(at: folder)
        try fileSystem.moveItem(at: fileURL, to: folder.appending(path: fileURL.lastPathComponent))
        let manifest = BatchManifest.drop(id: id, at: now)
        try fileSystem.writeAtomically(ScanCoreJSON.encoder().encode(manifest), to: folder.appending(path: BatchManifest.fileName))
        return StagedBatch(id: id, folderURL: folder, manifest: manifest)
    }

    /// Moves a finished batch to `_done/<id>` (adding `-2`, `-3`, … if needed) and returns its new location.
    public func archive(_ batch: StagedBatch) throws -> URL {
        let done = stagingRoot.appending(path: Self.doneFolderName)
        try fileSystem.createDirectory(at: done)
        var destination = done.appending(path: batch.id)
        var counter = 2
        while fileSystem.fileExists(at: destination) {
            destination = done.appending(path: "\(batch.id)-\(counter)")
            counter += 1
        }
        try fileSystem.moveItem(at: batch.folderURL, to: destination)
        return destination
    }

    /// Page files of a batch in natural order (`page-2` before `page-10`); hidden entries and `batch.json` excluded.
    public func pageFiles(of batch: StagedBatch) throws -> [URL] {
        try pageFiles(in: batch.folderURL)
    }

    private func pageFiles(in folder: URL) throws -> [URL] {
        try fileSystem.contentsOfDirectory(at: folder)
            .filter(Self.isAdoptable)
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private func inspectBatchFolder(_ url: URL, name: String, now: Date, into result: inout StagingScanResult) throws {
        let manifestURL = url.appending(path: BatchManifest.fileName)
        if !fileSystem.fileExists(at: manifestURL) {
            // A drop adoption interrupted between moving the file and writing its manifest is recovered;
            // any other folder without a manifest is still being scanned.
            guard name.hasPrefix("drop-"), try !pageFiles(in: url).isEmpty else { return }
            try fileSystem.writeAtomically(ScanCoreJSON.encoder().encode(BatchManifest.drop(id: name, at: now)), to: manifestURL)
        }
        guard let manifest = try? ScanCoreJSON.decoder().decode(BatchManifest.self, from: fileSystem.readData(at: manifestURL)) else {
            result.unreadableBatchIDs.append(name)
            return
        }
        let batch = StagedBatch(id: name, folderURL: url, manifest: manifest)
        if manifest.interrupted == nil {
            result.readyBatches.append(batch)
        } else {
            result.interruptedBatches.append(batch)
        }
    }

    private static func isAdoptable(_ url: URL) -> Bool {
        adoptableExtensions.contains(url.pathExtension.lowercased())
    }

    static func timestamp(_ date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(format: "%04d-%02d-%02d-%02d%02d%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0,
                      parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)
    }
}
