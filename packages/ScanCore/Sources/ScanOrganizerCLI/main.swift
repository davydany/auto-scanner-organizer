import Foundation
import ScanCore

let runner = CLIRunner(environment: ProcessInfo.processInfo.environment, output: { print($0) })
do {
    let command = try CLIArguments.parse(Array(CommandLine.arguments.dropFirst()),
                                         currentDirectory: URL(filePath: FileManager.default.currentDirectoryPath),
                                         home: FileManager.default.homeDirectoryForCurrentUser)
    try await runner.run(command)
} catch let error as CLIUsageError {
    FileHandle.standardError.write(Data("error: \(error)\n\n\(CLIArguments.usage)\n".utf8))
    exit(64)
} catch let error as ReviewError {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(65)
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
