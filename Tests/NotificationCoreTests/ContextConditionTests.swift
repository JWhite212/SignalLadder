import XCTest
@testable import NotificationCore

/// The three conditions that ask about something a notification does not say:
/// the time on the Mac's clock, the screen lock, and how often its app is
/// sending. Each is held here from the file to the match.
final class ContextConditionTests: XCTestCase {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func note(app: String = "Mail") -> CapturedNotification {
        CapturedNotification(timestamp: Date(timeIntervalSince1970: 1_757_000_000), appNameGuess: app, title: "t",
                             subtitle: "", body: "b", rawText: "\(app), t, b", subrole: "AXNotificationCenterBanner")
    }

    private func facts(_ hour: Int, _ minute: Int = 0, _ day: Weekday = .wed, locked: Bool? = nil,
                       ages: [TimeInterval] = []) -> MatchFacts {
        MatchFacts(minuteOfDay: hour * 60 + minute, weekday: day, screenLocked: locked, earlierSendAges: ages)
    }

    private func matches(_ condition: RuleCondition, _ facts: MatchFacts) -> Bool {
        RuleEvaluator.matches(condition, note(), facts)
    }

    private func decoded(_ json: String) throws -> RuleCondition {
        try JSONDecoder().decode(RuleCondition.self, from: Data(json.utf8))
    }

    private func written(_ condition: RuleCondition) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(condition), as: UTF8.self)
    }

    private func rule(_ condition: RuleCondition) -> Rule {
        Rule(name: "r", condition: condition, isEnabled: true, alert: nil)
    }

    // MARK: - Time of day

    func testAStretchInsideOneDayTakesItsStartAndNotItsEnd() {
        let office = RuleCondition.time(TimeWindow(from: 9 * 60, to: 17 * 60, days: [.mon, .tue, .wed, .thu, .fri]))
        XCTAssertFalse(matches(office, facts(8, 59)))
        XCTAssertTrue(matches(office, facts(9, 0)))
        XCTAssertTrue(matches(office, facts(16, 59)))
        XCTAssertFalse(matches(office, facts(17, 0)))
        XCTAssertFalse(matches(office, facts(12, 0, .sat)), "not one of its days")
    }

    func testAStretchPastMidnightBelongsToTheDayItStartsOn() {
        let fridayNight = RuleCondition.time(TimeWindow(from: 22 * 60, to: 7 * 60, days: [.fri]))
        XCTAssertTrue(matches(fridayNight, facts(22, 0, .fri)))
        XCTAssertTrue(matches(fridayNight, facts(23, 59, .fri)))
        XCTAssertTrue(matches(fridayNight, facts(0, 0, .sat)), "Saturday morning is Friday's night")
        XCTAssertTrue(matches(fridayNight, facts(6, 59, .sat)))
        XCTAssertFalse(matches(fridayNight, facts(7, 0, .sat)))
        XCTAssertFalse(matches(fridayNight, facts(3, 0, .fri)), "Friday morning is Thursday's night")
        XCTAssertFalse(matches(fridayNight, facts(23, 0, .sat)))
        XCTAssertFalse(matches(fridayNight, facts(21, 59, .fri)))
    }

    func testSundayNightRunsIntoMondayMorning() {
        let night = TimeWindow(from: 23 * 60, to: 60, days: [.sun])
        XCTAssertTrue(night.contains(minute: 30, on: .mon))
        XCTAssertFalse(night.contains(minute: 30, on: .sun))
        XCTAssertEqual(Weekday.mon.previous, .sun)
        XCTAssertEqual(Weekday.sun.previous, .sat)
    }

    func testEveryMinuteOfTheWeekIsInAStretchOrItsOtherHalfAndNeverBoth() {
        let night = TimeWindow(from: 22 * 60, to: 7 * 60)
        let day = TimeWindow(from: 7 * 60, to: 22 * 60)
        for weekday in Weekday.allCases {
            for minute in 0..<TimeWindow.minutesInDay {
                XCTAssertNotEqual(night.contains(minute: minute, on: weekday), day.contains(minute: minute, on: weekday))
            }
        }
    }

    func testTheFactsAreReadFromTheDateInTheCalendarGiven() {
        // 2025-09-04 15:33:20 UTC, a Thursday.
        let date = Date(timeIntervalSince1970: 1_757_000_000)
        let read = MatchFacts(date: date, calendar: utc)
        XCTAssertEqual(read.minuteOfDay, 15 * 60 + 33)
        XCTAssertEqual(read.weekday, .thu)
        var tokyo = utc
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        XCTAssertEqual(MatchFacts(date: date, calendar: tokyo).minuteOfDay, 33)
        XCTAssertEqual(MatchFacts(date: date, calendar: tokyo).weekday, .fri, "the Mac's day, not UTC's")
        XCTAssertEqual((1...7).map(Weekday.init(calendarWeekday:)), [.sun, .mon, .tue, .wed, .thu, .fri, .sat])
    }

    func testATimeIsWrittenAndReadAsHoursAndMinutes() throws {
        let all = try decoded(#"{"time": {"from": "22:00", "to": "07:05"}}"#)
        XCTAssertEqual(all, .time(TimeWindow(from: 22 * 60, to: 7 * 60 + 5)))
        XCTAssertEqual(try written(all), #"{"time":{"from":"22:00","to":"07:05"}}"#, "every day is written as no list")
        let some = try decoded(#"{"time": {"from": "09:00", "to": "17:00", "days": ["fri", "mon"]}}"#)
        XCTAssertEqual(some, .time(TimeWindow(from: 540, to: 1020, days: [.mon, .fri])))
        XCTAssertEqual(try written(some), #"{"time":{"days":["mon","fri"],"from":"09:00","to":"17:00"}}"#, "in the week's order")
        XCTAssertEqual(try decoded(try written(some)), some)
    }

    func testATimeThatIsNotATimeOfDayIsRefusedInWords() {
        for bad in ["9:00", "24:00", "09:60", "0900", "09:00:00", "nine", "", "-1:00", "٠٩:٠٠"] {
            XCTAssertNil(TimeWindow.minute(fromText: bad), bad)
            XCTAssertThrowsError(try decoded(#"{"time": {"from": "\#(bad)", "to": "17:00"}}"#), bad) {
                XCTAssertTrue(String(describing: $0).contains("HH:MM"), "\($0)")
            }
        }
        XCTAssertEqual(TimeWindow.minute(fromText: "00:00"), 0)
        XCTAssertEqual(TimeWindow.minute(fromText: "23:59"), 1439)
        XCTAssertThrowsError(try decoded(#"{"time": {"from": "09:00", "to": "17:00", "days": ["monday"]}}"#))
        XCTAssertThrowsError(try decoded(#"{"time": {"from": "09:00", "to": "17:00", "zone": "UTC"}}"#)) {
            XCTAssertTrue(String(describing: $0).contains(#"unknown key "zone""#), "\($0)")
        }
        XCTAssertThrowsError(try decoded(#"{"time": {"from": "09:00"}}"#))
    }

    func testAStretchThatCouldNeverMatchIsAProblemAndNotAGuess() {
        XCTAssertEqual(RuleSetCodec.problems(in: rule(.time(TimeWindow(from: 540, to: 540)))),
                       [#"a "time" condition starts and ends at 09:00, so it could never match"#])
        XCTAssertFalse(matches(.time(TimeWindow(from: 540, to: 540)), facts(9)), "and it does not match the whole day")
        XCTAssertEqual(RuleSetCodec.problems(in: rule(.not(.time(TimeWindow(from: 540, to: 600, days: []))))),
                       [#"a "time" condition names no days, so it could never match"#])
        XCTAssertEqual(RuleSetCodec.problems(in: rule(.time(.workingHours))), [])
    }

    // MARK: - Screen lock

    func testTheLockIsMatchedAsItWasReadAndUnreadIsNotLocked() throws {
        XCTAssertTrue(matches(.screenLocked(true), facts(9, locked: true)))
        XCTAssertFalse(matches(.screenLocked(true), facts(9, locked: false)))
        XCTAssertFalse(matches(.screenLocked(true), facts(9, locked: nil)))
        XCTAssertTrue(matches(.screenLocked(false), facts(9, locked: nil)), "a person is taken to be at the Mac")
        XCTAssertTrue(matches(.screenLocked(false), facts(9, locked: false)))
        XCTAssertEqual(try decoded(#"{"screenLocked": true}"#), .screenLocked(true))
        XCTAssertEqual(try written(.screenLocked(false)), #"{"screenLocked":false}"#)
        XCTAssertThrowsError(try decoded(#"{"screenLocked": "yes"}"#))
    }

    // MARK: - How often the app is sending

    func testTheCountIsThisOneAndTheEarlierOnesInsideTheMinutes() {
        let busy = facts(9, ages: [10, 59, 60, 61, 599, 600, 601, 3000])
        XCTAssertEqual(busy.sends(withinMinutes: 1), 4, "this one, and those up to 60 seconds before")
        XCTAssertEqual(busy.sends(withinMinutes: 10), 7)
        XCTAssertEqual(busy.sends(withinMinutes: 60), 9)
        XCTAssertEqual(facts(9).sends(withinMinutes: 60), 1, "the first is one")
        XCTAssertTrue(matches(.appSent(AppFrequency(atLeast: 4, withinMinutes: 1)), busy))
        XCTAssertFalse(matches(.appSent(AppFrequency(atLeast: 5, withinMinutes: 1)), busy))
    }

    func testARateIsWrittenAndReadAndHeldToItsRanges() throws {
        let rate = try decoded(#"{"appSent": {"atLeast": 5, "withinMinutes": 10}}"#)
        XCTAssertEqual(rate, .appSent(AppFrequency(atLeast: 5, withinMinutes: 10)))
        XCTAssertEqual(try written(rate), #"{"appSent":{"atLeast":5,"withinMinutes":10}}"#)
        XCTAssertThrowsError(try decoded(#"{"appSent": {"atLeast": 5}}"#))
        XCTAssertThrowsError(try decoded(#"{"appSent": {"atLeast": 5.5, "withinMinutes": 10}}"#))
        XCTAssertThrowsError(try decoded(#"{"appSent": {"atLeast": 5, "withinMinutes": 10, "app": "Mail"}}"#))
        XCTAssertEqual(RuleSetCodec.problems(in: rule(.appSent(AppFrequency(atLeast: 1, withinMinutes: 61)))),
                       [#""appSent" atLeast 1 is outside 2 to 100"#, #""appSent" withinMinutes 61 is outside 1 to 60"#])
        XCTAssertEqual(RuleSetCodec.problems(in: rule(.appSent(AppFrequency(atLeast: 2, withinMinutes: 1)))), [])
        XCTAssertEqual(RuleSetCodec.problems(in: rule(.appSent(AppFrequency(atLeast: 100, withinMinutes: 60)))), [])
    }

    func testTheTrackerCountsPerAppInsideTheHourAndKeepsNoMoreThanARuleCanAsk() {
        var tracker = AppSendTracker()
        let t0 = Date(timeIntervalSince1970: 1_757_000_000)
        XCTAssertEqual(tracker.note(app: "Mail", at: t0), [])
        XCTAssertEqual(tracker.note(app: "Slack", at: t0.addingTimeInterval(1)), [], "another app's are not counted")
        XCTAssertEqual(tracker.note(app: " mail ", at: t0.addingTimeInterval(30)), [30], "as rules compare an app's name")
        XCTAssertEqual(tracker.note(app: "Mail", at: t0.addingTimeInterval(3600)), [3600, 3570])
        XCTAssertEqual(tracker.note(app: "Mail", at: t0.addingTimeInterval(3601)), [3571, 1], "the first has left the hour")
        // A clock set back: what is now in the future is not before this one.
        XCTAssertEqual(tracker.note(app: "Mail", at: t0.addingTimeInterval(-10)), [])

        var flood = AppSendTracker()
        var last: [TimeInterval] = []
        for i in 0..<500 { last = flood.note(app: "Pager", at: t0.addingTimeInterval(Double(i))) }
        XCTAssertEqual(last.count, AppSendTracker.kept - 1)
        XCTAssertEqual(MatchFacts(minuteOfDay: 0, weekday: .mon, earlierSendAges: last).sends(withinMinutes: 60),
                       AppFrequency.countRange.upperBound, "enough for the most a rule may ask")
        for i in 0..<1000 { _ = flood.note(app: "app \(i)", at: t0.addingTimeInterval(Double(i))) }
        XCTAssertLessThanOrEqual(flood.appCount, AppSendTracker.appLimit)
        XCTAssertEqual(AppSendTracker.window, 3600)
    }

    // MARK: - With the rest

    func testTheNewKindsSitInGroupsAndUnderNot() throws {
        let condition = try decoded(#"""
        {"and": [{"field": "app", "op": "equals", "value": "Mail"},
                 {"not": {"screenLocked": true}},
                 {"or": [{"time": {"from": "09:00", "to": "17:00"}}, {"appSent": {"atLeast": 3, "withinMinutes": 5}}]}]}
        """#)
        XCTAssertTrue(matches(condition, facts(10, locked: false)))
        XCTAssertFalse(matches(condition, facts(10, locked: true)))
        XCTAssertFalse(matches(condition, facts(20, locked: false)))
        XCTAssertTrue(matches(condition, facts(20, locked: false, ages: [5, 50])))
        XCTAssertTrue(condition.usesVersion6Kinds)
        XCTAssertFalse(RuleCondition.and([.field(.app, .equals, "Mail"), .not(.blank)]).usesVersion6Kinds)
    }

    func testAConditionStillNeedsExactlyOneKind() {
        XCTAssertThrowsError(try decoded(#"{"screenLocked": true, "time": {"from": "09:00", "to": "17:00"}}"#)) {
            XCTAssertTrue(String(describing: $0).contains(#"exactly one of "and", "or", "not", "field", "time", "screenLocked" or "appSent""#), "\($0)")
        }
        XCTAssertThrowsError(try decoded(#"{"screenLocked": true, "value": "x"}"#))
        XCTAssertThrowsError(try decoded(#"{"onCall": true}"#))
    }

    func testARuleWithANewKindIsWrittenAtVersion6AndRefusedInAnOlderFile() throws {
        let timed = rule(.and([.field(.app, .equals, "Mail"), .time(.workingHours)]))
        XCTAssertEqual(RuleSetCodec.version(for: [timed]), 6)
        XCTAssertEqual(RuleSetCodec.version(for: [rule(.field(.app, .equals, "Mail"))]), 1, "nothing else is moved up")
        let json = #"{"name": "r", "condition": {"screenLocked": true}}"#
        XCTAssertEqual(try RuleSetCodec.decode(rulesFile(version: 6, json)).rules.count, 1)
        let older = try RuleSetCodec.decode(rulesFile(version: 5, json))
        XCTAssertEqual(older.rules.count, 0)
        XCTAssertEqual(older.problems.count, 1)
        XCTAssertTrue(older.problems[0].reason.contains(#"needs "version": 6"#), "\(older.problems)")
        let round = try RuleSetCodec.decode(try RuleSetCodec.encode([timed]))
        XCTAssertEqual(round.rules.map(\.condition), [timed.condition])
    }

    func testEveryEditTheBuilderMakesWorksOnANewKind() {
        let lock = RuleCondition.screenLocked(true)
        let root = RuleCondition.and([.field(.app, .equals, "Mail"), lock])
        XCTAssertEqual(root.condition(at: [1]), lock)
        XCTAssertEqual(root.replacing(at: [1], with: .screenLocked(false)), .and([.field(.app, .equals, "Mail"), .screenLocked(false)]))
        XCTAssertEqual(root.removing(at: [1]), .and([.field(.app, .equals, "Mail")]))
        XCTAssertEqual(root.negating(at: [1]), .and([.field(.app, .equals, "Mail"), .not(lock)]))
        XCTAssertEqual(root.wrapping(at: [1], in: .or), .and([.field(.app, .equals, "Mail"), .or([lock])]))
        XCTAssertNil(root.removing(at: [1, 0]), "a leaf has nothing under it")
        XCTAssertNil(root.inserting(.blank, intoGroupAt: [1], at: 0))
        XCTAssertEqual(lock.adding(.appSent(.starting)), .and([lock, .appSent(.starting)]))
        XCTAssertEqual(root.paths, [[], [0], [1]])
        XCTAssertEqual(MuteWalkthrough.appsNamed(by: root), ["Mail"])
    }

    func testEachKindIsSaidInWordsAndOfferedOnceWithAStartThatHasNoProblem() {
        XCTAssertEqual(EditorText.describe(.time(.workingHours)), "Time is 09:00 to 17:00, weekdays")
        XCTAssertEqual(EditorText.describe(.time(TimeWindow(from: 1320, to: 420))), "Time is 22:00 to 07:00, every day")
        XCTAssertEqual(EditorText.describe(.screenLocked(true)), "Screen is locked")
        XCTAssertEqual(EditorText.describe(.screenLocked(false)), "Screen is not locked")
        XCTAssertEqual(EditorText.describe(.appSent(.starting)), "App sent at least 5 in 10 minutes")
        XCTAssertEqual(EditorText.describe(.appSent(AppFrequency(atLeast: 2, withinMinutes: 1))), "App sent at least 2 in 1 minute")
        XCTAssertEqual(EditorText.daysSummary([.sat, .sun]), "weekends")
        XCTAssertEqual(EditorText.daysSummary([.wed, .mon]), "Mon, Wed")
        XCTAssertEqual(EditorText.daysSummary([]), "no days")
        XCTAssertEqual(ConditionKinds.offered.map(\.name), ["Time of Day", "Screen Lock", "How Often the App Is Sending"])
        for kind in ConditionKinds.offered {
            XCTAssertEqual(RuleSetCodec.problems(in: rule(kind.start)), [], kind.name)
            XCTAssertTrue(kind.start.usesVersion6Kinds)
        }
    }

    func testATimePickersDateGivesBackTheMinuteItWasMadeFrom() {
        for minute in [0, 1, 59, 60, 119, 120, 180, 719, 720, 1439] {
            XCTAssertEqual(TimeOfDayPicking.minute(of: TimeOfDayPicking.date(forMinute: minute)), minute)
        }
        var newYork = utc
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        for minute in stride(from: 0, to: TimeWindow.minutesInDay, by: 15) {
            XCTAssertEqual(TimeOfDayPicking.minute(of: TimeOfDayPicking.date(forMinute: minute, calendar: newYork),
                                                   calendar: newYork), minute)
        }
    }
}

/// The same three, from a banner to the rule that takes it.
@MainActor
final class ContextConditionPipelineTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_757_000_000)

    private func feed(_ p: CapturePipeline, _ app: String, _ n: Int, at offset: TimeInterval) -> CapturePipeline.Outcome {
        p.process(RawCapture(timestamp: t0.addingTimeInterval(offset), rawText: "\(app), title \(n), body",
                             subrole: "AXNotificationCenterBanner"), textChildren: ["title \(n)", "body"])
    }

    private func rule(_ name: String, _ condition: RuleCondition) -> Rule {
        Rule(name: name, condition: condition, isEnabled: true, alert: nil)
    }

    func testARateRuleTakesTheThirdInTheMinutesAndNotAnotherAppsOrALaterLoneOne() {
        let p = CapturePipeline.forTest()
        p.setRules([rule("flood", .appSent(AppFrequency(atLeast: 3, withinMinutes: 5)))])
        XCTAssertEqual(feed(p, "Mail", 1, at: 0), .recorded(matchedRule: nil))
        XCTAssertEqual(feed(p, "Slack", 1, at: 10), .recorded(matchedRule: nil))
        XCTAssertEqual(feed(p, "Mail", 2, at: 20), .recorded(matchedRule: nil))
        XCTAssertEqual(feed(p, "Slack", 2, at: 30), .recorded(matchedRule: nil))
        XCTAssertEqual(feed(p, "Mail", 3, at: 40), .recorded(matchedRule: "flood"))
        XCTAssertEqual(feed(p, "Mail", 4, at: 1000), .recorded(matchedRule: nil), "the three before it are more than five minutes old")
        XCTAssertEqual(p.history.entries.first?.context.facts.earlierSendAges, [1000, 980, 960], "newest row first")
    }

    func testARepeatDedupeDropsIsNotASend() {
        let p = CapturePipeline.forTest()
        p.setRules([rule("flood", .appSent(AppFrequency(atLeast: 2, withinMinutes: 5)))])
        let same = RawCapture(timestamp: t0, rawText: "Mail, t, b", subrole: "AXNotificationCenterBanner")
        XCTAssertEqual(p.process(same, textChildren: ["t", "b"]), .recorded(matchedRule: nil))
        let again = RawCapture(timestamp: t0.addingTimeInterval(0.5), rawText: "Mail, t, b", subrole: "AXNotificationCenterBanner")
        XCTAssertNotEqual(p.process(again, textChildren: ["t", "b"]), .recorded(matchedRule: "flood"))
        XCTAssertEqual(p.history.entries.count, 1)
    }

    func testTheLockIsAskedOnceForEachCaptureAndKeptOnItsRow() {
        let p = CapturePipeline.forTest()
        var locked: Bool? = true
        var asked = 0
        p.screenLocked = { asked += 1; return locked }
        p.setRules([rule("away", .screenLocked(true)), rule("here", .screenLocked(false))])
        XCTAssertEqual(feed(p, "Mail", 1, at: 0), .recorded(matchedRule: "away"))
        locked = false
        XCTAssertEqual(feed(p, "Mail", 2, at: 10), .recorded(matchedRule: "here"))
        locked = nil
        XCTAssertEqual(feed(p, "Mail", 3, at: 20), .recorded(matchedRule: "here"), "unread is taken as not locked")
        XCTAssertEqual(asked, 3, "once each, however many rules ask")
        XCTAssertEqual(p.history.entries.reversed().map(\.context.facts.screenLocked), [true, false, nil])
    }

    func testRulesLoadedLaterAreTriedOnWhatWasTrueWhenEachWasCaptured() {
        let p = CapturePipeline.forTest()
        var locked: Bool? = true
        p.screenLocked = { locked }
        _ = feed(p, "Mail", 1, at: 0)
        locked = false
        _ = feed(p, "Mail", 2, at: 10)
        XCTAssertEqual(p.setRules([rule("away", .screenLocked(true))]), 1, "the first, though the screen is unlocked now")
        XCTAssertEqual(p.history.entries.reversed().map { $0.preview?.ruleName }, ["away", nil])
        let report = DryRun.report(forRuleAt: 0, in: [rule("pair", .appSent(AppFrequency(atLeast: 2, withinMinutes: 5)))],
                                   over: Array(p.history.entries.reversed()))
        XCTAssertEqual(report.rows.map(\.verdict), [.notMatched, .matched])
    }

    func testWithNothingSetTheLockIsRecordedAsNotRead() {
        let p = CapturePipeline.forTest()
        _ = feed(p, "Mail", 1, at: 0)
        XCTAssertNil(p.history.entries.first?.context.facts.screenLocked)
    }
}
