// Sources/NotificationCore/MatchFacts.swift
import Foundation

/// A day of the week, as the rules file spells it.
public enum Weekday: String, CaseIterable, Codable, Sendable {
    case mon, tue, wed, thu, fri, sat, sun

    /// From `Calendar`'s numbering, where 1 is Sunday.
    public init(calendarWeekday: Int) {
        self = [.sun, .mon, .tue, .wed, .thu, .fri, .sat][((calendarWeekday - 1) % 7 + 7) % 7]
    }

    public var previous: Weekday {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + all.count - 1) % all.count]
    }
}

/// A stretch of the day, on chosen days, in the Mac's own time.
///
/// `from` is inside it and `to` is not, so 09:00 to 17:00 and 17:00 to 22:00
/// share no minute. When `to` is earlier than `from` the stretch runs past
/// midnight, and it belongs to the day it starts on: 22:00 to 07:00 on Friday
/// covers Friday night and Saturday morning.
public struct TimeWindow: Equatable, Sendable {
    public static let minutesInDay = 24 * 60

    /// Minutes after midnight, 0 to 1439.
    public var from: Int
    public var to: Int
    public var days: Set<Weekday>

    public init(from: Int, to: Int, days: Set<Weekday> = Set(Weekday.allCases)) {
        self.from = from
        self.to = to
        self.days = days
    }

    /// What a new one starts as: the working day, Monday to Friday.
    public static let workingHours = TimeWindow(from: 9 * 60, to: 17 * 60, days: [.mon, .tue, .wed, .thu, .fri])

    public var wrapsMidnight: Bool { to < from }

    public func contains(minute: Int, on day: Weekday) -> Bool {
        if from < to { return days.contains(day) && (from..<to).contains(minute) }
        if from > to {
            return (minute >= from && days.contains(day)) || (minute < to && days.contains(day.previous))
        }
        return false
    }

    /// "09:00", the form the file holds a time in.
    public static func text(forMinute minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }

    /// The minute "HH:MM" names, or nil when it is not a time of day. Exactly
    /// two digits each side, so "9:00", "24:00" and "09:60" are not read as
    /// something near what was written.
    public static func minute(fromText text: String) -> Int? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts.allSatisfy({ $0.count == 2 && $0.allSatisfy(\.isASCIIDigit) }),
              let hour = Int(parts[0]), let minute = Int(parts[1]), hour < 24, minute < 60 else { return nil }
        return hour * 60 + minute
    }
}

extension Character {
    fileprivate var isASCIIDigit: Bool { isASCII && isNumber }
}

/// "This notification's app has sent at least so many in the last so many
/// minutes", this one counted.
public struct AppFrequency: Equatable, Sendable {
    public static let countRange = 2...100
    public static let minutesRange = 1...60

    public var atLeast: Int
    public var withinMinutes: Int

    public init(atLeast: Int, withinMinutes: Int) {
        self.atLeast = atLeast
        self.withinMinutes = withinMinutes
    }

    public static let starting = AppFrequency(atLeast: 5, withinMinutes: 10)
}

/// What was true when a notification arrived that a rule may ask about and
/// the notification does not say: the time on the Mac's clock, whether the
/// screen was locked, and how lately its app had sent others.
///
/// Read once when the notification is captured and kept with it, so the
/// matcher stays a pure function, every rule is asked about the same facts,
/// and a rule tried later on that notification is tried on what was true then.
public struct MatchFacts: Equatable, Sendable {
    /// Minutes after midnight on the Mac's clock, in its time zone.
    public let minuteOfDay: Int
    public let weekday: Weekday
    /// nil when it could not be read. A rule then takes the screen as
    /// unlocked, the state a person is at the Mac in.
    public let screenLocked: Bool?
    /// How long before this notification each earlier one from its app was
    /// captured, in seconds. At most `AppSendTracker.kept` of them, none
    /// older than `AppSendTracker.window`.
    public let earlierSendAges: [TimeInterval]

    public init(minuteOfDay: Int, weekday: Weekday, screenLocked: Bool? = nil, earlierSendAges: [TimeInterval] = []) {
        self.minuteOfDay = minuteOfDay
        self.weekday = weekday
        self.screenLocked = screenLocked
        self.earlierSendAges = earlierSendAges
    }

    public init(date: Date, calendar: Calendar = .autoupdatingCurrent, screenLocked: Bool? = nil, earlierSendAges: [TimeInterval] = []) {
        let parts = calendar.dateComponents([.hour, .minute, .weekday], from: date)
        self.init(minuteOfDay: (parts.hour ?? 0) * 60 + (parts.minute ?? 0),
                  weekday: Weekday(calendarWeekday: parts.weekday ?? 1),
                  screenLocked: screenLocked, earlierSendAges: earlierSendAges)
    }

    /// How many its app sent in the last `minutes`, this one counted.
    public func sends(withinMinutes minutes: Int) -> Int {
        let window = TimeInterval(minutes * 60)
        return 1 + earlierSendAges.filter { $0 <= window }.count
    }
}

/// When each app last sent, for the send-rate condition. In memory only, and
/// bounded: the newest `kept` times of each app, none older than `window`, and
/// at most `appLimit` apps, the longest-quiet dropped first. A count asked of
/// it can be no higher than a rule may ask for, so nothing more is worth
/// keeping.
public struct AppSendTracker {
    public static let window: TimeInterval = TimeInterval(AppFrequency.minutesRange.upperBound * 60)
    public static let kept = AppFrequency.countRange.upperBound
    public static let appLimit = 200

    private var times: [String: [Date]] = [:]

    public init() {}

    /// Notes a notification from `app` at `date`, and returns how long before
    /// it each earlier one inside the window was. A time after `date`, which
    /// a clock set back leaves, is not before it and is dropped.
    ///
    /// A banner whose app could not be read has no app to count: it is the
    /// first of nothing, and is not kept, so unnamed banners from different
    /// apps are never added together.
    public mutating func note(app: String, at date: Date) -> [TimeInterval] {
        let key = Self.key(app)
        guard !key.isEmpty else { return [] }
        // Every app's times that have left the window go now, not when that
        // app next sends, so nothing is kept past the hour by an app's silence.
        times = times.filter { date.timeIntervalSince($0.value.last ?? .distantPast) <= Self.window }
        let earlier = (times[key] ?? []).filter { $0 <= date && date.timeIntervalSince($0) <= Self.window }
        times[key] = Array((earlier + [date]).suffix(Self.kept))
        if times.count > Self.appLimit {
            let quietest = times.filter { $0.key != key }.min { ($0.value.last ?? .distantPast) < ($1.value.last ?? .distantPast) }
            if let quietest { times[quietest.key] = nil }
        }
        return earlier.suffix(Self.kept - 1).map { date.timeIntervalSince($0) }
    }

    /// For another read of the banner last noted for `app`: the ages its first
    /// read was given, as near as can be told, which are those of every time
    /// kept but the newest. Nothing is noted.
    public func agesBeforeNewest(app: String, at date: Date) -> [TimeInterval] {
        (times[Self.key(app)] ?? []).dropLast()
            .filter { $0 <= date && date.timeIntervalSince($0) <= Self.window }
            .suffix(Self.kept - 1).map { date.timeIntervalSince($0) }
    }

    private static func key(_ app: String) -> String {
        Glob.fold(app.trimmingCharacters(in: .whitespaces))
    }

    var appCount: Int { times.count }
}
