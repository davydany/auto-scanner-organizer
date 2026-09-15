import Testing
@testable import ScanAdapters

@Test func adaptersModuleVersionIsSet() {
    #expect(ScanAdapters.version == "0.2.0")
}
