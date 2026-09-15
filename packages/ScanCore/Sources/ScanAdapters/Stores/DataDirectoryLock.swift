import Darwin
import Foundation
import Synchronization

public enum DataDirectoryLockError: Error, Equatable, Sendable {
    /// Another open lock file holds the lock; the payload is the lock file's path.
    case alreadyLocked(String)
    case unavailable(String)
}

/// An exclusive `flock` on `<data>/scan-organizer.lock`, so only one pipeline command uses a data directory at a time.
/// The event and purpose stores cache their files for the life of the process, and the event log trims a partial line
/// assuming it is the only writer (Milestone 2 ADR).
public final class DataDirectoryLock: Sendable {
    public static let fileName = "scan-organizer.lock"

    private let descriptor: Mutex<Int32?>

    private init(descriptor: Int32) {
        self.descriptor = Mutex(descriptor)
    }

    deinit {
        release()
    }

    /// Creates the directory if needed, then takes the lock without waiting.
    public static func acquire(in directory: URL) throws -> DataDirectoryLock {
        let path = directory.appending(path: fileName).path(percentEncoded: false)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw DataDirectoryLockError.unavailable("can't create \(directory.path(percentEncoded: false)): \(error)")
        }
        let fileDescriptor = open(path, O_CREAT | O_RDWR, 0o644)
        guard fileDescriptor >= 0 else {
            throw DataDirectoryLockError.unavailable("can't open \(path): \(String(cString: strerror(errno)))")
        }
        guard flock(fileDescriptor, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            close(fileDescriptor)
            if code == EWOULDBLOCK { throw DataDirectoryLockError.alreadyLocked(path) }
            throw DataDirectoryLockError.unavailable("can't lock \(path): \(String(cString: strerror(code)))")
        }
        return DataDirectoryLock(descriptor: fileDescriptor)
    }

    /// Closes the lock file, which releases the lock. Safe to call more than once.
    public func release() {
        descriptor.withLock { current in
            guard let fileDescriptor = current else { return }
            close(fileDescriptor)
            current = nil
        }
    }
}
