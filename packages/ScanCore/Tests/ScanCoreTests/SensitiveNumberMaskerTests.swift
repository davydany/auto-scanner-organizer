import Testing
@testable import ScanCore

struct SensitiveNumberMaskerTests {
    @Test func masksSocialSecurityNumbers() {
        #expect(SensitiveNumberMasker.mask("SSN 123-45-6789 on file") == "SSN •••-••-6789 on file")
        #expect(SensitiveNumberMasker.mask("SSN 123 45 6789") == "SSN •••-••-6789")
    }

    @Test func masksLabeledSSNs() {
        #expect(SensitiveNumberMasker.mask("SSN: 123456789") == "SSN: •••-••-6789")
        #expect(SensitiveNumberMasker.mask("Social Security Number 123456789 on file") == "Social Security Number •••-••-6789 on file")
        #expect(SensitiveNumberMasker.mask("TIN 987654321") == "TIN •••-••-4321")
    }

    @Test func masksLuhnValidCardNumbers() {
        #expect(SensitiveNumberMasker.mask("Card 4111 1111 1111 1111 charged") == "Card •••• 1111 charged")
        #expect(SensitiveNumberMasker.mask("Card 4111-1111-1111-1111") == "Card •••• 1111")
        #expect(SensitiveNumberMasker.mask("4111111111111111") == "•••• 1111")
        #expect(SensitiveNumberMasker.mask("Card 4111  1111  1111  1111 charged") == "Card •••• 1111 charged")
        #expect(SensitiveNumberMasker.mask("Card 4111 - 1111 - 1111 - 1111") == "Card •••• 1111")
    }

    @Test func leavesLuhnInvalidLongNumbersAlone() {
        #expect(SensitiveNumberMasker.mask("Ref 4111 1111 1111 1112") == "Ref 4111 1111 1111 1112")
    }

    @Test func masksLabeledAccountNumbers() {
        #expect(SensitiveNumberMasker.mask("Account number: 1234567890") == "Account number: ••••7890")
        #expect(SensitiveNumberMasker.mask("Acct # 55-1234-99 due") == "Acct # ••••3499 due")
        #expect(SensitiveNumberMasker.mask("August bill, account number 9876543210.") == "August bill, account number ••••3210.")
    }

    @Test(arguments: [
        "Call 703-555-1234",
        "Amount due $142.18 by 2026-09-18",
        "pd 9/3 ck #2217 $180",
        "Policy renews 2026-10-01",
        "Order 123456789 shipped",
    ])
    func leavesOrdinaryNumbersAlone(_ text: String) {
        #expect(SensitiveNumberMasker.mask(text) == text)
    }
}
