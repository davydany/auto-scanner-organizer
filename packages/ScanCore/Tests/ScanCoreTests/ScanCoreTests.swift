import Testing
@testable import ScanCore

@Test func moduleVersionIsSet() {
    #expect(ScanCore.version == "0.1.0")
}
