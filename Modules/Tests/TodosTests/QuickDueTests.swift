import Foundation
import Testing

@testable import Todos

@Suite struct QuickDueTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }()

    /// Tuesday 3 November 2026.
    private var today: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 3)) ?? Date() }

    private func day(_ query: String) -> String? {
        QuickDue.day(from: query, today: today, calendar: calendar)
    }

    @Test func whatFollowsTwoSlashesIsTheQuery() {
        #expect(QuickDue.query(in: "//") == "")
        #expect(QuickDue.query(in: "Call bank //") == "")
        #expect(QuickDue.query(in: "Call bank //14.10") == "14.10")
        #expect(QuickDue.removingQuery(from: "Call bank //14.10") == "Call bank ")
    }

    @Test func slashesInsideAWordOrBeforeASpaceAreLeftAlone() {
        #expect(QuickDue.query(in: "see https://example.com") == nil)
        #expect(QuickDue.query(in: "Call bank //14.10 ") == nil)
        #expect(QuickDue.query(in: "Call bank /") == nil)
        #expect(QuickDue.removingQuery(from: "see https://x") == "see https://x")
    }

    @Test func aDayAndMonthIsTheNextSuchDay() {
        #expect(day("14.11") == "2026-11-14")
        #expect(day("14.11.") == "2026-11-14")
        #expect(day("14.10") == "2027-10-14")
        #expect(day("3.11") == "2026-11-03")
    }

    @Test func aYearIsTakenAsTyped() {
        #expect(day("14.10.26") == "2026-10-14")
        #expect(day("14.10.2027") == "2027-10-14")
        #expect(day("2026-12-01") == "2026-12-01")
    }

    @Test func aDayAloneIsTheNextOneOfThatNumber() {
        #expect(day("14") == "2026-11-14")
        #expect(day("2") == "2026-12-02")
    }

    @Test func daysNoMonthHasAreRefused() {
        #expect(day("31.11.2026") == nil)
        #expect(day("32") == nil)
        #expect(day("tom") == nil)
        #expect(day("") == nil)
    }

    @Test func theStartOfAQuickChoiceNamesIt() {
        #expect(QuickDue.choice(for: "tom") == .tomorrow)
        #expect(QuickDue.choice(for: "To") == .today)
        #expect(QuickDue.choice(for: "fr") == .thisWeek)
        #expect(QuickDue.choice(for: "") == nil)
        #expect(QuickDue.choice(for: "x") == nil)
    }
}
