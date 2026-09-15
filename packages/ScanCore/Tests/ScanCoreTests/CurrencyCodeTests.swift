import Testing
@testable import ScanCore

struct CurrencyCodeTests {
    @Test(arguments: [(" usd ", "USD"), ("EUR", "EUR"), ("gbp", "GBP")])
    func normalizesValidCodes(_ input: String, _ expected: String) {
        #expect(CurrencyCode.normalized(input) == expected)
    }

    @Test(arguments: ["", "US D", "EURO", "€", "U5D", "usd\n1"])
    func rejectsInvalidCodes(_ input: String) {
        #expect(CurrencyCode.normalized(input) == nil)
    }
}
