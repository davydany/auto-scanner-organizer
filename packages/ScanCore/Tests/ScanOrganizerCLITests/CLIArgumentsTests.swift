import Foundation
import Testing
@testable import ScanCore
@testable import ScanOrganizerCLI

struct CLIArgumentsTests {
    let cwd = URL(filePath: "/Users/owner/work")
    let home = URL(filePath: "/Users/owner")

    func parse(_ arguments: [String]) throws -> CLICommand {
        try CLIArguments.parse(arguments, currentDirectory: cwd, home: home)
    }

    @Test func parsesProcessWithDefaults() throws {
        guard case let .process(options, watch) = try parse(["process", "--staging", "Scans", "--vault", "~/Vault"]) else {
            Issue.record("expected process")
            return
        }
        #expect(options.staging.path(percentEncoded: false) == "/Users/owner/work/Scans")
        #expect(options.vault.path(percentEncoded: false) == "/Users/owner/Vault")
        #expect(options.data.path(percentEncoded: false) == "/Users/owner/Library/Application Support/AutoScannerOrganizer")
        #expect(options.model == .sonnet5)
        #expect(options.threshold == 0.75)
        #expect(!watch)
    }

    @Test func parsesEveryProcessOptionAndModelIDs() throws {
        guard case let .process(options, watch) = try parse(["process", "--staging", "/s", "--vault", "/v", "--data", "/d", "--model", "haiku",
                                                            "--threshold", "0.9", "--watch"]) else {
            Issue.record("expected process")
            return
        }
        #expect(options.data.path(percentEncoded: false) == "/d")
        #expect(options.model == .haiku45)
        #expect(options.threshold == 0.9)
        #expect(watch)
        guard case let .process(opus, _) = try parse(["process", "--staging", "/s", "--vault", "/v", "--model", "claude-opus-5"]) else {
            Issue.record("expected process")
            return
        }
        #expect(opus.model == .opus5)
    }

    @Test func parsesReviewResolutions() throws {
        let arguments = ["review", "2026-09-14-013000", "doc-2", "--staging", "/s", "--vault", "/v", "--folder", "Personal/Finances",
                         "--subfolder", "2026", "--title", "Water Bill", "--from", "Fairfax Water", "--date", "2026-08-28",
                         "--amount", "42.10", "--currency", "USD", "--accept-duplicate"]
        guard case let .review(_, batchID, documentID, resolution) = try parse(arguments) else {
            Issue.record("expected review")
            return
        }
        #expect(batchID == "2026-09-14-013000")
        #expect(documentID == "doc-2")
        #expect(resolution == ReviewResolution(folder: "Personal/Finances", newSubfolder: "2026", title: "Water Bill", from: "Fairfax Water",
                                               docDate: CalendarDay("2026-08-28"), amount: Decimal(string: "42.10"), currency: "USD",
                                               acceptPossibleDuplicate: true))
    }

    @Test func parsesStatusRetryVersionAndHelp() throws {
        guard case .status(let data) = try parse(["status", "--data", "state"]) else {
            Issue.record("expected status")
            return
        }
        #expect(data.path(percentEncoded: false) == "/Users/owner/work/state")
        guard case let .retry(_, batchID) = try parse(["retry", "2026-09-14-013000", "--staging", "/s", "--vault", "/v"]) else {
            Issue.record("expected retry")
            return
        }
        #expect(batchID == "2026-09-14-013000")
        #expect(try parse(["--version"]) == .version)
        #expect(try parse([]) == .help)
        #expect(try parse(["--help"]) == .help)
    }

    @Test(arguments: [
        (["process", "--vault", "/v"], "--staging is required"),
        (["process", "--staging", "/s", "--vault", "/v", "--threshold", "0.3"], "--threshold must be between 0.5 and 1.0"),
        (["process", "--staging", "/s", "--vault", "/v", "--model", "gpt"], "unknown model \"gpt\""),
        (["process", "--staging", "/s", "--vault", "/v", "--folder", "x"], "unknown option --folder for process"),
        (["status", "--watch"], "unknown option --watch for status"),
        (["review", "b", "--staging", "/s", "--vault", "/v", "--folder", "x"], "review expects 2 arguments"),
        (["review", "b", "d", "--staging", "/s", "--vault", "/v"], "--folder is required"),
        (["review", "b", "d", "--staging", "/s", "--vault", "/v", "--folder", "x", "--date", "8/28"], "--date must be YYYY-MM-DD"),
        (["review", "b", "d", "--staging", "/s", "--vault", "/v", "--folder", "x", "--amount", "$5"], "--amount must be a plain decimal such as 12.50"),
        (["retry", "--staging", "/s", "--vault", "/v"], "retry expects 1 argument"),
        (["process", "--staging"], "--staging needs a value"),
        (["scan"], "unknown command \"scan\""),
    ])
    func reportsUsageErrors(_ arguments: [String], _ message: String) {
        #expect(throws: CLIUsageError(description: message)) { try parse(arguments) }
    }
}
