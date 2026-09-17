import Foundation
import ScanCore

struct PipelineOptions: Equatable {
    var staging: URL
    var vault: URL
    var data: URL
    var model: ClaudeModel
    var threshold: Double
}

enum CLICommand: Equatable {
    case version
    case help
    case process(PipelineOptions, watch: Bool)
    case status(data: URL)
    case review(PipelineOptions, batchID: String, documentID: String, resolution: ReviewResolution)
    case retry(PipelineOptions, batchID: String)
}

struct CLIUsageError: Error, Equatable, CustomStringConvertible {
    let description: String
}

struct CLIRunError: Error, Equatable, CustomStringConvertible {
    let description: String
}

enum CLIArguments {
    static let usage = """
    usage:
      scan-organizer process --staging <dir> --vault <dir> [--data <dir>] [--model <id>] [--threshold <0.5-1.0>] [--watch]
      scan-organizer status [--data <dir>]
      scan-organizer review <batch-id> <doc-id> --staging <dir> --vault <dir> --folder <path> [--subfolder <name>]
          [--title <text>] [--from <text>] [--date YYYY-MM-DD] [--amount <decimal>] [--currency <code>] [--accept-duplicate]
      scan-organizer retry <batch-id> --staging <dir> --vault <dir>
      scan-organizer --version
    Models: sonnet (claude-sonnet-5, default), opus (claude-opus-5), haiku (claude-haiku-4-5).
    process, review, and retry also accept --data, --model, and --threshold, and read ANTHROPIC_API_KEY from the environment.
    """

    private static let pipelineOptions: Set<String> = ["--staging", "--vault", "--data", "--model", "--threshold"]
    private static let resolutionOptions: Set<String> = ["--folder", "--subfolder", "--title", "--from", "--date", "--amount", "--currency"]
    private static let switchNames: Set<String> = ["--watch", "--accept-duplicate"]
    private static let modelAliases: [String: ClaudeModel] = ["sonnet": .sonnet5, "opus": .opus5, "haiku": .haiku45]

    private struct Parsed {
        var options: [String: String] = [:]
        var switches: Set<String> = []
        var positionals: [String] = []
    }

    static func parse(_ arguments: [String], currentDirectory: URL, home: URL) throws -> CLICommand {
        guard let command = arguments.first else { return .help }
        let parsed = try split(Array(arguments.dropFirst()))
        let paths = PathResolver(currentDirectory: currentDirectory, home: home)
        switch command {
        case "--version":
            return .version
        case "--help", "-h", "help":
            return .help
        case "status":
            try check(parsed, command: command, options: ["--data"], switches: [], positionals: 0)
            return .status(data: paths.dataDirectory(parsed.options["--data"]))
        case "process":
            try check(parsed, command: command, options: pipelineOptions, switches: ["--watch"], positionals: 0)
            return .process(try pipeline(parsed, paths), watch: parsed.switches.contains("--watch"))
        case "retry":
            try check(parsed, command: command, options: pipelineOptions, switches: [], positionals: 1)
            return .retry(try pipeline(parsed, paths), batchID: parsed.positionals[0])
        case "review":
            try check(parsed, command: command, options: pipelineOptions.union(resolutionOptions), switches: ["--accept-duplicate"], positionals: 2)
            return .review(try pipeline(parsed, paths), batchID: parsed.positionals[0], documentID: parsed.positionals[1],
                           resolution: try resolution(parsed))
        default:
            throw CLIUsageError(description: "unknown command \"\(command)\"")
        }
    }

    private static func split(_ arguments: [String]) throws -> Parsed {
        var parsed = Parsed()
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if switchNames.contains(argument) {
                parsed.switches.insert(argument)
            } else if argument.hasPrefix("--") {
                guard index + 1 < arguments.count else { throw CLIUsageError(description: "\(argument) needs a value") }
                parsed.options[argument] = arguments[index + 1]
                index += 1
            } else {
                parsed.positionals.append(argument)
            }
            index += 1
        }
        return parsed
    }

    private static func check(_ parsed: Parsed, command: String, options: Set<String>, switches: Set<String>, positionals: Int) throws {
        if let unknown = (Set(parsed.options.keys).subtracting(options).union(parsed.switches.subtracting(switches))).sorted().first {
            throw CLIUsageError(description: "unknown option \(unknown) for \(command)")
        }
        guard parsed.positionals.count == positionals else {
            throw CLIUsageError(description: "\(command) expects \(positionals) argument\(positionals == 1 ? "" : "s")")
        }
    }

    private static func pipeline(_ parsed: Parsed, _ paths: PathResolver) throws -> PipelineOptions {
        guard let staging = parsed.options["--staging"] else { throw CLIUsageError(description: "--staging is required") }
        guard let vault = parsed.options["--vault"] else { throw CLIUsageError(description: "--vault is required") }
        var model = ClaudeModel.sonnet5
        if let name = parsed.options["--model"] {
            guard let chosen = ClaudeModel(rawValue: name) ?? modelAliases[name] else { throw CLIUsageError(description: "unknown model \"\(name)\"") }
            model = chosen
        }
        var threshold = AppSettings.default.autoFileThreshold
        if let text = parsed.options["--threshold"] {
            guard let value = Double(text), FilingDecider.thresholdRange.contains(value) else {
                throw CLIUsageError(description: "--threshold must be between 0.5 and 1.0")
            }
            threshold = value
        }
        return PipelineOptions(staging: paths.url(staging), vault: paths.url(vault), data: paths.dataDirectory(parsed.options["--data"]),
                               model: model, threshold: threshold)
    }

    private static func resolution(_ parsed: Parsed) throws -> ReviewResolution {
        guard let folder = parsed.options["--folder"] else { throw CLIUsageError(description: "--folder is required") }
        var resolution = ReviewResolution(folder: folder, newSubfolder: parsed.options["--subfolder"], title: parsed.options["--title"],
                                          from: parsed.options["--from"], currency: parsed.options["--currency"],
                                          acceptPossibleDuplicate: parsed.switches.contains("--accept-duplicate"))
        if let text = parsed.options["--date"] {
            guard let day = CalendarDay(text) else { throw CLIUsageError(description: "--date must be YYYY-MM-DD") }
            resolution.docDate = day
        }
        if let text = parsed.options["--amount"] {
            guard let amount = StackResponse.plainDecimal(text) else { throw CLIUsageError(description: "--amount must be a plain decimal such as 12.50") }
            resolution.amount = amount
        }
        return resolution
    }
}

struct PathResolver {
    let currentDirectory: URL
    let home: URL

    func url(_ path: String) -> URL {
        if path == "~" { return home }
        if path.hasPrefix("~/") { return home.appending(path: String(path.dropFirst(2))) }
        if path.hasPrefix("/") { return URL(filePath: path) }
        return currentDirectory.appending(path: path)
    }

    func dataDirectory(_ path: String?) -> URL {
        path.map(url) ?? home.appending(path: "Library/Application Support/AutoScannerOrganizer")
    }
}
