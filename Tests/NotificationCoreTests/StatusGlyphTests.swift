import AppKit
import XCTest
@testable import NotificationCore

/// Which icon the status item shows, and what it says (M5 plan, Rulings 10, 17
/// and 18). The icon is a pure function of the facts the app has read, so every
/// precedence, every source of a problem and every word is reached from facts
/// alone. Nothing here draws an icon: the one test that asks the system for a
/// symbol only asks whether it knows the name.
final class StatusGlyphTests: XCTestCase {
    private typealias Glyph = StatusGlyph

    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    /// Every fact at rest: capture verified, no rule problem, nothing failed, an
    /// audible output and Alert volume with a rule that sounds, nothing escalating,
    /// off call, and self-tests running.
    private func facts(_ edit: (inout Glyph.Facts) -> Void = { _ in }) -> Glyph.Facts {
        var facts = Glyph.Facts(health: .verified, healthAlarmState: HealthAlarmPlan.State(), now: now,
                                ruleStatusProblem: false, shortcutWarningCount: 0, unresolvedAlertFailure: false,
                                unresolvedShortcutFailure: false, outputSilent: false, anEnabledRuleSounds: true,
                                alertVolume: 1, escalationLive: false, onCall: false, selfTestsRunning: true)
        edit(&facts)
        return facts
    }

    /// Capture that has read unknown since `seconds` ago, as the health alarm
    /// remembers it.
    private func unknownFor(_ seconds: TimeInterval) -> HealthAlarmPlan.State {
        HealthAlarmPlan.State(lastReported: .unknown, unknownSince: now.addingTimeInterval(-seconds))
    }

    // MARK: - The precedence

    func testTheStatesAreFourAndTheNormalOneIsWhatRestingFactsGive() {
        XCTAssertEqual(Glyph.State.allCases, [.problem, .escalating, .onCall, .normal])
        XCTAssertEqual(Glyph.state(for: facts()), .normal)
    }

    func testOnCallIsShownWhileNothingAboveItIs() {
        XCTAssertEqual(Glyph.state(for: facts { $0.onCall = true }), .onCall)
    }

    func testAnEscalationOutranksOnCallAndNormal() {
        XCTAssertEqual(Glyph.state(for: facts { $0.escalationLive = true }), .escalating)
        XCTAssertEqual(Glyph.state(for: facts { $0.escalationLive = true; $0.onCall = true }), .escalating)
    }

    /// A working ladder must not look like a broken pipeline, and a broken
    /// pipeline outranks it: the most important fact on screen.
    func testAProblemOutranksAnEscalationAndOnCall() {
        XCTAssertEqual(Glyph.state(for: facts { $0.ruleStatusProblem = true; $0.escalationLive = true }), .problem)
        XCTAssertEqual(Glyph.state(for: facts { $0.ruleStatusProblem = true; $0.onCall = true }), .problem)
        XCTAssertEqual(Glyph.state(for: facts { $0.ruleStatusProblem = true; $0.escalationLive = true; $0.onCall = true }),
                       .problem)
    }

    // MARK: - What makes a problem

    func testEachOfTheFiveProblemSourcesThatHoldWhetherOrNotOnCallIsTheProblemStateAlone() {
        for onCall in [false, true] {
            func state(_ edit: (inout Glyph.Facts) -> Void) -> Glyph.State {
                Glyph.state(for: facts { $0.onCall = onCall; edit(&$0) })
            }
            let normal: Glyph.State = onCall ? .onCall : .normal
            XCTAssertEqual(state { _ in }, normal, "none of them, on call \(onCall)")
            XCTAssertEqual(state { $0.health = .degraded([.selfTestInconclusive]) }, .problem, "degraded")
            XCTAssertEqual(state { $0.health = .blind([.accessibilityNotTrusted]) }, .problem, "blind")
            XCTAssertEqual(state { $0.ruleStatusProblem = true }, .problem, "a rule that is not in effect")
            XCTAssertEqual(state { $0.shortcutWarningCount = 1 }, .problem, "a Shortcut not found")
            XCTAssertEqual(state { $0.shortcutWarningCount = 3 }, .problem, "more than one")
            XCTAssertEqual(state { $0.unresolvedAlertFailure = true }, .problem, "an alert that could not play")
            XCTAssertEqual(state { $0.unresolvedShortcutFailure = true }, .problem, "a Shortcut that did not run")
            XCTAssertEqual(state { $0.shortcutWarningCount = 0 }, normal, "a count of zero is not a problem")
        }
    }

    /// Capture that has stayed unverified past the bound the health alarm sounds
    /// for is a problem while on call, and the bound is asked of that same
    /// function, so the icon and the beep cannot disagree about it.
    func testCaptureUnverifiedPastTheBoundIsAProblemWhileOnCallAndNotWhileOffCall() {
        func state(onCall: Bool, unknownFor seconds: TimeInterval) -> Glyph.State {
            Glyph.state(for: facts { $0.health = .unknown; $0.healthAlarmState = unknownFor(seconds); $0.onCall = onCall })
        }
        XCTAssertEqual(state(onCall: true, unknownFor: 10 * 60), .problem)
        XCTAssertEqual(state(onCall: true, unknownFor: 10 * 3600), .problem)
        XCTAssertEqual(state(onCall: true, unknownFor: 9 * 60 + 59), .onCall, "a second short of the bound")
        XCTAssertEqual(state(onCall: true, unknownFor: 0), .onCall)
        XCTAssertEqual(state(onCall: false, unknownFor: 10 * 3600), .normal, "off call unknown never alarms, however long")
    }

    func testTheUnverifiedBoundIsTheHealthAlarmsAndNotACopyOfIt() {
        for seconds in [0, 100, 300, 599, 600, 601, 3600] as [TimeInterval] {
            let state = unknownFor(seconds)
            let alarm = HealthAlarmPlan.isUnverifiedFault(onCall: true, health: .unknown, state: state, now: now)
            let icon = Glyph.isProblem(facts { $0.health = .unknown; $0.healthAlarmState = state; $0.onCall = true })
            XCTAssertEqual(icon, alarm, "\(seconds) seconds")
        }
        // After a wake, the bound the alarm uses is two minutes, and so is the icon's.
        let woken = HealthAlarmPlan.State(lastReported: .unknown, unknownSince: now.addingTimeInterval(-150),
                                          lastWakeAt: now.addingTimeInterval(-121))
        XCTAssertTrue(Glyph.isProblem(facts { $0.health = .unknown; $0.healthAlarmState = woken; $0.onCall = true }))
        let freshWake = HealthAlarmPlan.State(lastReported: .unknown, unknownSince: now.addingTimeInterval(-150),
                                              lastWakeAt: now.addingTimeInterval(-119))
        XCTAssertFalse(Glyph.isProblem(facts { $0.health = .unknown; $0.healthAlarmState = freshWake; $0.onCall = true }))
    }

    func testAMutedOutputIsAProblemWhileOnCallWithARuleThatSoundsAndNotOtherwise() {
        func state(onCall: Bool = true, silent: Bool = true, sounds: Bool = true) -> Glyph.State {
            Glyph.state(for: facts { $0.onCall = onCall; $0.outputSilent = silent; $0.anEnabledRuleSounds = sounds })
        }
        XCTAssertEqual(state(), .problem)
        XCTAssertEqual(state(onCall: false), .normal, "off call")
        XCTAssertEqual(state(sounds: false), .onCall, "no rule sounds, so silence is what the user chose")
        XCTAssertEqual(state(silent: false), .onCall, "an audible output")
    }

    /// The beeps are the app's own channel and not a rule's, so a silent Alert
    /// volume is a problem whether or not a rule sounds.
    func testAnAlertVolumeAtZeroIsAProblemWhileOnCallWhetherOrNotARuleSounds() {
        func state(onCall: Bool = true, volume: Double?, sounds: Bool) -> Glyph.State {
            Glyph.state(for: facts { $0.onCall = onCall; $0.alertVolume = volume; $0.anEnabledRuleSounds = sounds })
        }
        for sounds in [true, false] {
            XCTAssertEqual(state(volume: 0, sounds: sounds), .problem, "zero, rule sounds \(sounds)")
            XCTAssertEqual(state(volume: 0.01, sounds: sounds), .problem, "0.01, rule sounds \(sounds)")
            XCTAssertEqual(state(volume: 0.02, sounds: sounds), .onCall, "0.02")
            XCTAssertEqual(state(volume: 1, sounds: sounds), .onCall)
            XCTAssertEqual(state(volume: nil, sounds: sounds), .onCall, "unread claims nothing")
            XCTAssertEqual(state(onCall: false, volume: 0, sounds: sounds), .normal, "off call")
        }
    }

    // MARK: - What each state shows

    func testEachStateHasASymbolOfItsOwnAndTheFallbackIsTheNormalOne() {
        let appearances = [
            Glyph.appearance(for: facts { $0.ruleStatusProblem = true }, pulse: false),
            Glyph.appearance(for: facts { $0.escalationLive = true }, pulse: false),
            Glyph.appearance(for: facts { $0.escalationLive = true }, pulse: true),
            Glyph.appearance(for: facts { $0.onCall = true }, pulse: false),
            Glyph.appearance(for: facts(), pulse: false),
        ]
        XCTAssertEqual(appearances.map(\.symbol).count, Set(appearances.map(\.symbol)).count, "no two share a symbol")
        XCTAssertEqual(appearances.map(\.state), [.problem, .escalating, .escalating, .onCall, .normal])
        XCTAssertEqual(Glyph.fallbackSymbol, Glyph.appearance(for: facts(), pulse: false).symbol)
        XCTAssertEqual(appearances.map(\.symbol), ["bell.slash.fill", "bell.and.waves.left.and.right",
                                                   "bell.and.waves.left.and.right.fill", "bell.badge.fill", "bell.badge"])
    }

    /// An unknown symbol name makes `NSImage(systemSymbolName:)` answer nil and the
    /// status item blank, so every name an appearance can hold is one the system
    /// knows (Ruling 17).
    func testEverySymbolAnAppearanceNamesIsOneTheSystemKnows() {
        let names = [StatusGlyphText.problemSymbol, StatusGlyphText.escalatingSymbolBright,
                     StatusGlyphText.escalatingSymbolDim, StatusGlyphText.onCallSymbol, StatusGlyphText.normalSymbol,
                     Glyph.fallbackSymbol]
        for name in names {
            XCTAssertNotNil(NSImage(systemSymbolName: name, accessibilityDescription: nil), name)
        }
    }

    func testThePulseAlternatesOnlyWhileEscalating() {
        let escalating = facts { $0.escalationLive = true }
        XCTAssertNotEqual(Glyph.appearance(for: escalating, pulse: false).symbol,
                          Glyph.appearance(for: escalating, pulse: true).symbol)
        for resting in [facts(), facts { $0.onCall = true }, facts { $0.ruleStatusProblem = true }] {
            XCTAssertEqual(Glyph.appearance(for: resting, pulse: false), Glyph.appearance(for: resting, pulse: true),
                           "\(Glyph.state(for: resting)) does not pulse")
        }
    }

    func testTheDescriptionsAreTheWordsEachStateHadAndOnCallsIsNew() {
        XCTAssertEqual(Glyph.appearance(for: facts(), pulse: false).description, "SignalLadder")
        XCTAssertEqual(Glyph.appearance(for: facts { $0.ruleStatusProblem = true }, pulse: false).description,
                       "SignalLadder — problem")
        XCTAssertEqual(Glyph.appearance(for: facts { $0.escalationLive = true }, pulse: true).description,
                       "SignalLadder — alert escalating")
        XCTAssertEqual(Glyph.appearance(for: facts { $0.onCall = true }, pulse: false).description,
                       "SignalLadder — on call, self-test every 5 minutes")
    }

    /// Saying the cadence while a self-test is blocked would say more than the app
    /// has established (Ruling 17), so it is in the description only while
    /// self-tests are running.
    func testTheCadenceIsInTheOnCallDescriptionOnlyWhileSelfTestsAreRunning() {
        func description(_ running: Bool?) -> String {
            Glyph.appearance(for: facts { $0.onCall = true; $0.selfTestsRunning = running }, pulse: false).description
        }
        XCTAssertEqual(description(true), "SignalLadder — on call, self-test every 5 minutes")
        XCTAssertEqual(description(false), "SignalLadder — on call")
        XCTAssertEqual(description(nil), "SignalLadder — on call", "before the first health check has said")
        XCTAssertFalse(Glyph.appearance(for: facts { $0.selfTestsRunning = true }, pulse: false).description.contains("5 minutes"),
                       "off call there is no cadence to say")
    }

    func testEveryStateHasATooltipThatIsNotEmptyAndNamesTheApp() {
        let appearances = [
            Glyph.appearance(for: facts { $0.ruleStatusProblem = true }, pulse: false),
            Glyph.appearance(for: facts { $0.escalationLive = true }, pulse: false),
            Glyph.appearance(for: facts { $0.onCall = true }, pulse: false),
            Glyph.appearance(for: facts(), pulse: false),
        ]
        for appearance in appearances {
            XCTAssertTrue(appearance.tooltip.hasPrefix("SignalLadder"), appearance.tooltip)
            XCTAssertFalse(appearance.description.isEmpty)
        }
        XCTAssertEqual(Set(appearances.map(\.tooltip)).count, 4, "each state says its own")
    }
}
