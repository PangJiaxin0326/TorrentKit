import Foundation

public struct SpeedSchedulerEvaluator: Sendable {
    public var calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func isAlternativeLimitTime(
        scheduler: SpeedSchedulerPreferences,
        at date: Date = Date()
    ) -> Bool {
        guard scheduler.isEnabled else {
            return false
        }

        let start = scheduler.startMinuteOfDay
        let end = scheduler.endMinuteOfDay
        guard (0..<1_440).contains(start),
              (0..<1_440).contains(end),
              start != end else {
            return false
        }

        let components = calendar.dateComponents([.hour, .minute, .weekday], from: date)
        let minuteOfDay = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        let weekday = components.weekday ?? 1

        var rangeStart = start
        var rangeEnd = end
        var isInverted = false

        if rangeStart > rangeEnd {
            swap(&rangeStart, &rangeEnd)
            isInverted = true
        }

        if (rangeStart...rangeEnd).contains(minuteOfDay),
           scheduler.days.contains(weekday: weekday) {
            isInverted.toggle()
        }

        return isInverted
    }
}
