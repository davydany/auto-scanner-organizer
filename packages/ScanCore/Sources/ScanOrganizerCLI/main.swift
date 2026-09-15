import Foundation
import ScanAdapters
import ScanCore

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments == ["--version"] {
    print("scan-organizer \(ScanAdapters.version)")
} else {
    FileHandle.standardError.write(Data("usage: scan-organizer --version\n".utf8))
    exit(64)
}
