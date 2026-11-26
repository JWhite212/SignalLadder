// Sources/NotificationCore/ConditionKinds.swift
import Foundation

/// The kinds of condition that ask about something other than the
/// notification's own text, as the editor's menus offer them: each with its
/// name and what a new one starts as.
public enum ConditionKinds {
    public static let offered: [(name: String, start: RuleCondition)] = [
        (EditorText.addTimeCondition, .time(.workingHours)),
        (EditorText.addScreenLockCondition, .screenLocked(true)),
        (EditorText.addAppSentCondition, .appSent(.starting)),
    ]
}

/// Turns a time of day into a date a time picker can show, and back. The
/// date is 1 January 2001 in the Mac's calendar, a day with no clock change
/// in it, so every minute of the day exists once.
public enum TimeOfDayPicking {
    public static func date(forMinute minute: Int, calendar: Calendar = .autoupdatingCurrent) -> Date {
        calendar.date(from: DateComponents(year: 2001, month: 1, day: 1, hour: minute / 60, minute: minute % 60))
            ?? Date(timeIntervalSinceReferenceDate: TimeInterval(minute * 60))
    }

    public static func minute(of date: Date, calendar: Calendar = .autoupdatingCurrent) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}
