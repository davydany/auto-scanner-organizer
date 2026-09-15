import CoreServices
import Foundation

/// Signals when the staging folder may have changed (spec §6, Milestone 2 probe D). FSEvents reports changes anywhere
/// under the root, including `batch.json` written inside a batch folder; a periodic tick rechecks dropped files as they settle.
public final class StagingWatcher: Sendable {
    private let root: URL
    private let pollInterval: Duration

    public init(root: URL, pollInterval: Duration = .seconds(2)) {
        self.root = root
        self.pollInterval = pollInterval
    }

    /// Yields once immediately, on every change under the root, and at least every `pollInterval`.
    /// Only the newest signal is kept, so signals collapse into one while the consumer is busy with a pass.
    /// Cancelling the consuming task stops FSEvents and the ticker.
    public func changes() -> AsyncStream<Void> {
        let path = root.path(percentEncoded: false)
        let interval = pollInterval
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            continuation.yield()
            let events = FSEventsSubscription.start(path: path) { continuation.yield() }
            let ticker = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: interval)
                    continuation.yield()
                }
            }
            continuation.onTermination = { _ in
                ticker.cancel()
                events?.stop()
            }
        }
    }
}

/// Owns one FSEventStream. `@unchecked` because the stream reference is only touched in `start` and `stop`.
final class FSEventsSubscription: @unchecked Sendable {
    private final class Callback: Sendable {
        let onChange: @Sendable () -> Void

        init(_ onChange: @escaping @Sendable () -> Void) {
            self.onChange = onChange
        }
    }

    private let stream: FSEventStreamRef

    private init(stream: FSEventStreamRef) {
        self.stream = stream
    }

    static func start(path: String, latency: CFTimeInterval = 0.1, onChange: @escaping @Sendable () -> Void) -> FSEventsSubscription? {
        let info = Unmanaged.passRetained(Callback(onChange)).toOpaque()
        var context = FSEventStreamContext(version: 0, info: info, retain: nil, release: { pointer in
            guard let pointer else { return }
            Unmanaged<Callback>.fromOpaque(pointer).release()
        }, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, pointer, _, _, _, _ in
            guard let pointer else { return }
            Unmanaged<Callback>.fromOpaque(pointer).takeUnretainedValue().onChange()
        }
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagUseCFTypes)
        guard let stream = FSEventStreamCreate(kCFAllocatorDefault, callback, &context, [path] as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags) else {
            Unmanaged<Callback>.fromOpaque(info).release()
            return nil
        }
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.global(qos: .utility))
        FSEventStreamStart(stream)
        return FSEventsSubscription(stream: stream)
    }

    func stop() {
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
