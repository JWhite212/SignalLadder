import XCTest
@testable import NotificationCore

/// When the snooze beeps, and what it saves, as the app builds it (M5 plan, Task 4,
/// Ruling 12, O9). The app makes one controller from what the preferences hold, settles
/// it once at launch, and gives it the beep to announce with; the controller's timer, every
/// read the menu, the icon, the pipeline and the on-call switch make, and that launch can
/// each find a snooze over, and each can be the one that announces. These tests run it that
/// way, a launch to a launch, and hold that the beep is made exactly once for a snooze that
/// ran out having held something, whichever of the three finds the end first, and by none
/// of them otherwise.
///
/// Time is `ManualScheduler`'s, and the preferences are a dictionary that keeps what a
/// property list keeps, so that what is read at the next launch is what a real preferences
/// file would hand back, and a saved value that a property list could not hold fails here
/// and not in the app. No sound is made, no real timer is waited on and no real preferences
/// are read or written. Where the app's own wiring is held to say what it says is
/// `SnoozeWiringTests`.
@MainActor
final class SnoozeAnnouncementTests: XCTestCase {
    /// What the preferences hold between runs: a property list, as the real ones are, so that
    /// a value that is not one is a failure here and not an exception there, and what is
    /// handed back is what a property list reads as. The app's store writes to the defaults
    /// with `set` and `removeObject`, and these two do the same to a dictionary.
    @MainActor
    private final class Preferences {
        var values: [String: Any] = [:]
        var failures: [String] = []

        func save(_ key: String, _ value: Any?) {
            guard let value else {
                values[key] = nil
                return
            }
            guard PropertyListSerialization.propertyList(value, isValidFor: .binary) else {
                failures.append("\(key) is not a property list: \(value)")
                return
            }
            do {
                let data = try PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0)
                values[key] = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            } catch {
                failures.append("\(key) could not be kept: \(error)")
            }
        }
    }

    @MainActor
    private final class RunningApp {
        let clock = ManualScheduler()
        let preferences = Preferences()
        var beeps = 0
        var redraws = 0
        var snooze: SnoozeController!

        let pager = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!

        /// A launch, as `applicationDidFinishLaunching` does it: the controller is made from
        /// what the preferences hold, and what it owes is settled once.
        func launch() {
            snooze = SnoozeController(
                scheduler: clock,
                storedUntil: preferences.values[SnoozeController.untilKey],
                storedHeld: preferences.values[SnoozeController.heldKey],
                save: { [preferences] key, value in preferences.save(key, value) },
                changed: { [unowned self] in redraws += 1 },
                announce: { [unowned self] in beeps += 1 })
            snooze.settle()
        }

        /// The app quits, and the Mac goes on.
        func quit(for seconds: TimeInterval = 0) {
            snooze = nil
            clock.sleep(for: seconds)
        }

        func rule(quiet: Bool = true) -> Rule {
            Rule(id: pager, name: "On-call mentions", condition: .field(.app, .equals, "Microsoft Teams"),
                 alert: .sound(name: "Glass", gainDB: 0), quietWhenSnoozed: quiet)
        }

        /// Every way the app reads the snooze, as the menu, the icon, the pipeline and the
        /// switch do, and the one call it makes at launch.
        func readEverything() {
            _ = (snooze.endsAt, snooze.summary, snooze.isActive)
            _ = snooze.holds(Rule(id: UUID(), name: "Other", condition: .field(.app, .equals, "x")))
            snooze.settle()
        }
    }

    private enum Finder: CaseIterable {
        case theTimer, aRead, aLaunch
    }

    /// Exactly one beep for a snooze that ran out having held something, whichever of the
    /// timer, a read and a launch finds the end first, and none from the other two after it:
    /// not at the next read, not when the timer would have fired, and not at the launches
    /// that follow, which restore the summary and owe it nothing.
    func testASnoozeThatRanOutHavingHeldSomethingBeepsExactlyOnceWhicheverFindsTheEndFirst() {
        for finder in Finder.allCases {
            let app = RunningApp()
            app.launch()
            app.snooze.start(.fifteenMinutes)
            XCTAssertTrue(app.snooze.holds(app.rule()), "\(finder)")
            XCTAssertTrue(app.snooze.holds(app.rule()), "\(finder)")
            XCTAssertFalse(app.snooze.holds(app.rule(quiet: false)), "a rule with no tick is not held and is not counted")

            switch finder {
            case .theTimer:
                app.clock.advance(by: 899)
                XCTAssertEqual(app.beeps, 0, "\(finder): not yet")
                app.clock.advance(by: 1)
            case .aRead:
                app.clock.sleep(for: 1000)
                XCTAssertEqual(app.beeps, 0, "\(finder): the timer did not fire and nothing has looked")
                _ = app.snooze.endsAt
            case .aLaunch:
                app.quit(for: 1000)
                XCTAssertEqual(app.beeps, 0, "\(finder): the app was not running")
                app.launch()
            }
            XCTAssertEqual(app.beeps, 1, "\(finder)")

            app.readEverything()
            app.clock.advance(by: 7200)
            app.readEverything()
            app.quit(for: 3600)
            app.launch()
            app.quit()
            app.launch()
            app.readEverything()
            XCTAssertEqual(app.beeps, 1, "\(finder): one, and not again at a read, the timer or a launch")
            XCTAssertEqual(app.snooze.summary.counts, [app.pager: 2], "\(finder): what it held stays until it is dismissed")
            XCTAssertNil(app.preferences.values[SnoozeController.untilKey], "\(finder): and nothing of the snooze is left saved")
            XCTAssertEqual(app.preferences.failures, [], "\(finder)")
        }
    }

    /// A snooze the user ended, and one on-call mode ended, which is the same call, beeps
    /// at no time and by no path, though it held matches: the user is looking at it.
    func testASnoozeEndedByTheUserNeverBeepsAtTheTimerAReadOrALaunch() {
        let app = RunningApp()
        app.launch()
        app.snooze.start(.thirtyMinutes)
        XCTAssertTrue(app.snooze.holds(app.rule()))
        XCTAssertTrue(app.snooze.holds(app.rule()))
        app.snooze.end()
        app.readEverything()
        app.clock.advance(by: 1800)
        app.clock.sleep(for: 7200)
        app.readEverything()
        app.quit(for: 600)
        app.launch()
        app.readEverything()
        app.quit()
        app.launch()
        XCTAssertEqual(app.beeps, 0)
        XCTAssertEqual(app.snooze.summary.counts, [app.pager: 2], "but the summary stays")
        XCTAssertEqual(app.snooze.summary.unannounced, 0, "and nothing is owed for it")
        XCTAssertEqual(app.preferences.failures, [])
    }

    /// Nothing beeps at launch for a snooze that ended while the app was running and was
    /// announced then: the announcement was zeroed and saved before it was made, so the
    /// launch that follows owes nothing, and neither does the one after that.
    func testNothingBeepsAtLaunchForASnoozeThatEndedWhileTheAppRanAndWasAlreadyAnnounced() {
        let app = RunningApp()
        app.launch()
        app.snooze.start(.fifteenMinutes)
        XCTAssertTrue(app.snooze.holds(app.rule()))
        app.clock.advance(by: 900)
        XCTAssertEqual(app.beeps, 1, "announced at the timer, with the app running")
        app.quit(for: 60)
        app.launch()
        XCTAssertEqual(app.beeps, 1, "nothing at the launch that follows")
        app.quit(for: 60)
        app.launch()
        XCTAssertEqual(app.beeps, 1, "nor the one after")
        XCTAssertEqual(app.snooze.summary.unannounced, 0)
        XCTAssertEqual(app.snooze.summary.counts, [app.pager: 1])
    }

    /// A relaunch in the middle of a snooze restores it and beeps at nothing, the settle at
    /// launch finds it running, and the end then beeps once, at its own time.
    func testARelaunchInTheMiddleOfASnoozeRestoresItBeepsNothingAndTheEndBeepsOnce() {
        let app = RunningApp()
        app.launch()
        app.snooze.start(.thirtyMinutes)
        XCTAssertTrue(app.snooze.holds(app.rule()))
        let end = app.snooze.endsAt
        app.quit(for: 300)
        app.launch()
        XCTAssertEqual(app.beeps, 0)
        XCTAssertEqual(app.snooze.endsAt, end, "the same end, from what was saved")
        XCTAssertTrue(app.snooze.holds(app.rule()), "and it holds what it should")
        app.clock.advance(by: 1499)
        XCTAssertEqual(app.beeps, 0)
        app.clock.advance(by: 1)
        XCTAssertEqual(app.beeps, 1)
        app.readEverything()
        app.quit()
        app.launch()
        XCTAssertEqual(app.beeps, 1)
        XCTAssertEqual(app.snooze.summary.counts, [app.pager: 2])
        XCTAssertEqual(app.preferences.failures, [])
    }

    /// A snooze that held nothing says nothing, by any path.
    func testASnoozeThatHeldNothingNeverBeeps() {
        for finder in Finder.allCases {
            let app = RunningApp()
            app.launch()
            app.snooze.start(.fifteenMinutes)
            XCTAssertFalse(app.snooze.holds(app.rule(quiet: false)))
            switch finder {
            case .theTimer: app.clock.advance(by: 900)
            case .aRead:
                app.clock.sleep(for: 1000)
                _ = app.snooze.endsAt
            case .aLaunch:
                app.quit(for: 1000)
                app.launch()
            }
            app.readEverything()
            app.quit(for: 3600)
            app.launch()
            XCTAssertEqual(app.beeps, 0, "\(finder)")
            XCTAssertTrue(app.snooze.summary.isEmpty, "\(finder)")
            XCTAssertNil(app.preferences.values[SnoozeController.heldKey], "\(finder): nothing is saved of a summary with nothing in it")
        }
    }

    /// Every value the controller saves is one a property list can keep, which is what the
    /// defaults keep, and what a property list gives back is read as the same snooze and
    /// the same summary. The two keys are the only ones written. Until now that the preferences
    /// hand back what the controller reads, in the boxes Foundation uses, was assumed.
    func testWhatTheControllerSavesSurvivesAPropertyListAndIsReadBackAsTheSameSnoozeAndSummary() {
        let app = RunningApp()
        app.launch()
        app.snooze.start(.oneHour)
        XCTAssertTrue(app.snooze.holds(app.rule()))
        XCTAssertTrue(app.snooze.holds(app.rule()))
        XCTAssertTrue(app.snooze.holds(Rule(id: UUID(), name: "Other", condition: .field(.app, .equals, "x"),
                                            alert: .sound(name: "Glass", gainDB: 0), quietWhenSnoozed: true)))
        XCTAssertEqual(app.preferences.failures, [], "each save was a property list")
        XCTAssertEqual(Set(app.preferences.values.keys), [SnoozeController.untilKey, SnoozeController.heldKey])
        let (end, summary) = (app.snooze.endsAt, app.snooze.summary)
        XCTAssertNotNil(end)
        XCTAssertEqual(summary.total, 3)

        app.quit(for: 120)
        app.launch()
        XCTAssertEqual(app.snooze.endsAt, end, "the end comes back as it was")
        XCTAssertEqual(app.snooze.summary.counts, summary.counts)
        XCTAssertEqual(app.snooze.summary.firstHeldAt, summary.firstHeldAt)
        XCTAssertEqual(app.snooze.summary.unannounced, summary.unannounced)
        XCTAssertFalse(app.snooze.summary.recordUnreadable, "nothing it saved is a record it cannot read")
    }
}
