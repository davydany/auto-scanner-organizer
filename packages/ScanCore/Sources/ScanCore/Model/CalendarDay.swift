import Foundation

/// A calendar date with no time or time zone, rendered as `YYYY-MM-DD`.
public struct CalendarDay: Codable, Sendable, Hashable, Comparable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init?(year: Int, month: Int, day: Int) {
        let components = DateComponents(calendar: Calendar(identifier: .gregorian), year: year, month: month, day: day)
        guard year >= 1, components.isValidDate else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    public init?(_ string: String) {
        let parts = string.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else { return nil }
        self.init(year: year, month: month, day: day)
    }

    public static func from(_ date: Date, timeZone: TimeZone) -> CalendarDay {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        // Components from a real Date are always valid.
        return CalendarDay(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
            ?? CalendarDay(year: 1970, month: 1, day: 1)!
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public init(from decoder: Decoder) throws {
        let raw = try String(from: decoder)
        guard let parsed = CalendarDay(raw) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Expected YYYY-MM-DD, got \(raw)"))
        }
        self = parsed
    }

    public func encode(to encoder: Encoder) throws {
        try description.encode(to: encoder)
    }
}
