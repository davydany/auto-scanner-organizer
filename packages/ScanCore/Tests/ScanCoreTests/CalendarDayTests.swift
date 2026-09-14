import Foundation
import Testing
@testable import ScanCore

struct CalendarDayTests {
    @Test func parsesValidISODay() throws {
        let day = try #require(CalendarDay("2026-08-28"))
        #expect(day.year == 2026)
        #expect(day.month == 8)
        #expect(day.day == 28)
        #expect(day.description == "2026-08-28")
    }

    @Test(arguments: ["2026-02-30", "2026-13-01", "26-08-28", "2026-8-28", "", "2026-08-28T00:00:00"])
    func rejectsInvalidStrings(_ input: String) {
        #expect(CalendarDay(input) == nil)
    }

    @Test func ordersChronologically() throws {
        let earlier = try #require(CalendarDay("2026-01-31"))
        let later = try #require(CalendarDay("2026-02-01"))
        #expect(earlier < later)
    }

    @Test func buildsFromDateInTimeZone() throws {
        // 2026-09-14T02:30:00Z is still Sept 13 in New York (UTC-4).
        let date = Date(timeIntervalSince1970: 1_789_353_000)
        let newYork = try #require(TimeZone(identifier: "America/New_York"))
        #expect(CalendarDay.from(date, timeZone: newYork).description == "2026-09-13")
    }

    @Test func roundTripsThroughJSONAsString() throws {
        let day = try #require(CalendarDay("2026-09-02"))
        let data = try JSONEncoder().encode([day])
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json == "[\"2026-09-02\"]")
        #expect(try JSONDecoder().decode([CalendarDay].self, from: data) == [day])
    }
}
