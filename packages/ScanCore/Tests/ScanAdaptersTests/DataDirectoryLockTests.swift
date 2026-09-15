import Foundation
import Testing
@testable import ScanAdapters

struct DataDirectoryLockTests {
    @Test func excludesASecondHolderUntilReleased() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let data = temp.url.appending(path: "AutoScannerOrganizer")
        let lockPath = data.appending(path: "scan-organizer.lock").path(percentEncoded: false)

        let first = try DataDirectoryLock.acquire(in: data)
        #expect(FileManager.default.fileExists(atPath: lockPath))
        // flock locks belong to open file descriptions, so a second open conflicts even within this process.
        #expect(throws: DataDirectoryLockError.alreadyLocked(lockPath)) { try DataDirectoryLock.acquire(in: data) }

        first.release()
        let second = try DataDirectoryLock.acquire(in: data)
        second.release()
        second.release()
        first.release()

        #expect(throws: Never.self) { try DataDirectoryLock.acquire(in: data).release() }
    }
}
