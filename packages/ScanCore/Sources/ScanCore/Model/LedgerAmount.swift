import Foundation

/// An amount that can go into a purpose ledger: present, with a valid three-letter currency (never defaulted).
public struct LedgerAmount: Sendable, Equatable {
    public var amount: Decimal
    public var currency: String

    public init(amount: Decimal, currency: String) {
        self.amount = amount
        self.currency = currency
    }
}

extension KeyFacts {
    public var ledgerAmount: LedgerAmount? {
        guard let amount, let currency, let code = CurrencyCode.normalized(currency) else { return nil }
        return LedgerAmount(amount: amount, currency: code)
    }
}
