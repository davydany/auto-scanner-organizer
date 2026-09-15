import Foundation
import Testing

/// Live tests call the real Claude API and cost money; they run only when explicitly enabled.
enum LiveTestGate {
    static var isEnabled: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["SCANCORE_LIVE"] == "1" && environment["ANTHROPIC_API_KEY"]?.isEmpty == false
    }
}

@Test(.enabled(if: LiveTestGate.isEnabled, "Set SCANCORE_LIVE=1 and ANTHROPIC_API_KEY to run live Claude tests"))
func liveTestsRequireAnAPIKey() {
    #expect(ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]?.isEmpty == false)
}
