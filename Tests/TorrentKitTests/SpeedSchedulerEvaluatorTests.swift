import Foundation
import Testing
@testable import TorrentKit

struct SpeedSchedulerEvaluatorTests {
    @Test func schedulerMatchesDayWindowAndOvernightInversion() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let evaluator = SpeedSchedulerEvaluator(calendar: calendar)

        let weekdaySchedule = SpeedSchedulerPreferences(
            isEnabled: true,
            startMinuteOfDay: 9 * 60,
            endMinuteOfDay: 17 * 60,
            days: .weekdays
        )

        #expect(evaluator.isAlternativeLimitTime(scheduler: weekdaySchedule, at: date(2026, 5, 4, 10, 0, calendar: calendar)))
        #expect(evaluator.isAlternativeLimitTime(scheduler: weekdaySchedule, at: date(2026, 5, 4, 18, 0, calendar: calendar)) == false)
        #expect(evaluator.isAlternativeLimitTime(scheduler: weekdaySchedule, at: date(2026, 5, 3, 10, 0, calendar: calendar)) == false)
        #expect(evaluator.isAlternativeLimitTime(scheduler: weekdaySchedule, at: date(2026, 5, 4, 8, 59, calendar: calendar)) == false)
        #expect(evaluator.isAlternativeLimitTime(scheduler: weekdaySchedule, at: date(2026, 5, 4, 9, 0, calendar: calendar)))
        #expect(evaluator.isAlternativeLimitTime(scheduler: weekdaySchedule, at: date(2026, 5, 4, 16, 59, calendar: calendar)))
        #expect(evaluator.isAlternativeLimitTime(scheduler: weekdaySchedule, at: date(2026, 5, 4, 17, 0, calendar: calendar)))
        #expect(evaluator.isAlternativeLimitTime(scheduler: weekdaySchedule, at: date(2026, 5, 4, 17, 1, calendar: calendar)) == false)

        let overnightSchedule = SpeedSchedulerPreferences(
            isEnabled: true,
            startMinuteOfDay: 20 * 60,
            endMinuteOfDay: 8 * 60,
            days: .everyDay
        )

        #expect(evaluator.isAlternativeLimitTime(scheduler: overnightSchedule, at: date(2026, 5, 4, 19, 59, calendar: calendar)) == false)
        #expect(evaluator.isAlternativeLimitTime(scheduler: overnightSchedule, at: date(2026, 5, 4, 20, 0, calendar: calendar)) == false)
        #expect(evaluator.isAlternativeLimitTime(scheduler: overnightSchedule, at: date(2026, 5, 4, 20, 1, calendar: calendar)))
        #expect(evaluator.isAlternativeLimitTime(scheduler: overnightSchedule, at: date(2026, 5, 4, 21, 0, calendar: calendar)))
        #expect(evaluator.isAlternativeLimitTime(scheduler: overnightSchedule, at: date(2026, 5, 5, 7, 59, calendar: calendar)))
        #expect(evaluator.isAlternativeLimitTime(scheduler: overnightSchedule, at: date(2026, 5, 5, 8, 0, calendar: calendar)) == false)
        #expect(evaluator.isAlternativeLimitTime(scheduler: overnightSchedule, at: date(2026, 5, 4, 12, 0, calendar: calendar)) == false)
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int,
        calendar: Calendar
    ) -> Date {
        DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ).date!
    }
}
