import XCTest
@testable import NotificationCore

/// The menu's lines about on-call mode (M5 plan, Ruling 18). The weekday comes
/// from a calendar and the time from the closure the menu's other lines use, so
/// both are fixed here and the line is the same on every Mac and in every year.
final class AlertMenuTextTests: XCTestCase {
    private func calendar(timeZone: String = "UTC", locale: String = "en_GB") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZone)!
        calendar.locale = Locale(identifier: locale)
        return calendar
    }

    /// A moment in October 2026, in UTC. The 5th is a Monday.
    private func utcDate(day: Int, hour: Int = 9, minute: Int = 0) -> Date {
        calendar().date(from: DateComponents(timeZone: TimeZone(identifier: "UTC"),
                                             year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func line(since: Date?, allowsSelfTest: Bool? = true, calendar: Calendar? = nil,
                      time: (Date) -> String = { _ in "09:00" }) -> String {
        AlertMenuText.onCallSinceLine(since: since, allowsSelfTest: allowsSelfTest,
                                      calendar: calendar ?? self.calendar(), time: time)
    }

    func testTheSinceLineNamesTheWeekdayAndTheTime() {
        // 5 October 2026 is a Monday.
        XCTAssertEqual(line(since: utcDate(day: 5)), "On call since Mon 09:00 — self-test every 5 min")
    }

    func testTheSinceLineBeginsWithTheStemWhateverFollows() {
        let dates: [Date?] = [utcDate(day: 5), utcDate(day: 9, hour: 23, minute: 59), nil]
        for since in dates {
            for allows in [true, false, nil] as [Bool?] {
                XCTAssertTrue(line(since: since, allowsSelfTest: allows).hasPrefix(OnCallText.sinceStem),
                              "\(String(describing: since)), \(String(describing: allows))")
            }
        }
        XCTAssertEqual(OnCallText.sinceStem, "On call since")
    }

    func testTheLineEndsWithTheCadenceWhileSelfTestsRunAndWithThePauseWhileTheyCannot() {
        XCTAssertEqual(line(since: utcDate(day: 5), allowsSelfTest: true),
                       "On call since Mon 09:00" + OnCallText.cadenceEnding)
        XCTAssertEqual(line(since: utcDate(day: 5), allowsSelfTest: false),
                       "On call since Mon 09:00" + OnCallText.pausedEnding)
    }

    /// Before the first health check has said, neither is claimed.
    func testTheLineSaysNothingOfSelfTestsBeforeItIsKnown() {
        XCTAssertEqual(line(since: utcDate(day: 5), allowsSelfTest: nil), "On call since Mon 09:00")
    }

    func testTheThreeEndingsAreDifferent() {
        let endings = [OnCallText.cadenceEnding, OnCallText.pausedEnding, ""]
        XCTAssertEqual(Set(endings).count, 3)
        XCTAssertTrue(OnCallText.cadenceEnding.hasPrefix(" — "))
        XCTAssertTrue(OnCallText.pausedEnding.hasPrefix(" — "))
    }

    /// The cadence the line names is the on-call interval, so a change to one
    /// that is not made to the other fails here.
    func testTheCadenceEndingNamesTheOnCallInterval() {
        let minutes = Int(HealthEvaluator.onCallSelfTestInterval / 60)
        XCTAssertTrue(OnCallText.cadenceEnding.contains("every \(minutes) min"), OnCallText.cadenceEnding)
    }

    func testTheClockIsAskedAboutTheMomentItWasSwitchedOn() {
        var asked: [Date] = []
        let since = utcDate(day: 6, hour: 14, minute: 30)
        let result = line(since: since) { moment in
            asked.append(moment)
            return "14:30"
        }
        XCTAssertEqual(asked, [since])
        XCTAssertEqual(result, "On call since Tue 14:30" + OnCallText.cadenceEnding)
    }

    func testTheWeekdayFollowsTheDateAcrossAWeek() {
        let expected = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        for (offset, weekday) in expected.enumerated() {
            XCTAssertEqual(line(since: utcDate(day: 5 + offset), allowsSelfTest: nil), "On call since \(weekday) 09:00")
        }
    }

    /// It is the user's own day that is named, not Greenwich's: 23:30 on Monday
    /// in UTC is already Tuesday in Auckland.
    func testTheWeekdayIsTheDayInTheCalendarsTimeZone() {
        let since = utcDate(day: 5, hour: 23, minute: 30)
        XCTAssertEqual(line(since: since, allowsSelfTest: nil, calendar: calendar(timeZone: "UTC")),
                       "On call since Mon 09:00")
        XCTAssertEqual(line(since: since, allowsSelfTest: nil, calendar: calendar(timeZone: "Pacific/Auckland")),
                       "On call since Tue 09:00")
    }

    /// Named by the calendar, so in the language the user's Mac is set to.
    func testTheWeekdayIsNamedByTheCalendarAndNotWrittenIntoTheCode() {
        let since = utcDate(day: 5)
        for locale in ["en_GB", "fr_FR", "de_DE", "ja_JP"] {
            let calendar = calendar(locale: locale)
            let named = calendar.shortWeekdaySymbols[calendar.component(.weekday, from: since) - 1]
            XCTAssertEqual(line(since: since, allowsSelfTest: nil, calendar: calendar), "On call since \(named) 09:00",
                           locale)
        }
    }

    /// Something saved that is not a time: the line says so, and shows none.
    func testAnUnknownTimeIsSaidAndNoTimeIsShown() {
        var asked = false
        let result = line(since: nil, allowsSelfTest: true) { _ in
            asked = true
            return "09:00"
        }
        XCTAssertFalse(asked)
        XCTAssertEqual(result, "On call since a time that could not be read" + OnCallText.cadenceEnding)
        XCTAssertEqual(line(since: nil, allowsSelfTest: nil), "On call since " + OnCallText.sinceUnknown)
    }
}
