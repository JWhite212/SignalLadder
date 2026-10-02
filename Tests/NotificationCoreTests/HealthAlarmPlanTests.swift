import XCTest
@testable import NotificationCore

/// When the health alarm beeps and posts its banner (M5 plan, Rulings 9 and 10,
/// O5). Time is an argument of every ask, so each of these runs for hours in no
/// time and nothing here sounds a beep or shows a banner.
final class HealthAlarmPlanTests: XCTestCase {
    private typealias Plan = HealthAlarmPlan

    private let origin = Date(timeIntervalSince1970: 1_790_000_000)

    private let degraded = CaptureHealth.degraded([.selfTestInconclusive])
    private let otherDegraded = CaptureHealth.degraded([.ownAlertsNotShown])
    private let blind = CaptureHealth.blind([.accessibilityNotTrusted])

    private func at(_ seconds: TimeInterval) -> Date { origin.addingTimeInterval(seconds) }

    /// Asks the plan as the app does, carrying what it remembers from one ask to
    /// the next, and keeping every answer it has given.
    private final class Asker {
        let origin: Date
        var state: HealthAlarmPlan.State
        var onCall: Bool
        var deliveryHealthy = true
        private(set) var answers: [(seconds: TimeInterval, decision: HealthAlarmPlan.Decision)] = []

        init(origin: Date, onCall: Bool, state: HealthAlarmPlan.State = .init()) {
            self.origin = origin
            self.onCall = onCall
            self.state = state
        }

        @discardableResult
        func ask(_ health: CaptureHealth, at seconds: TimeInterval) -> HealthAlarmPlan.Decision {
            let decision = HealthAlarmPlan.decide(health: health, deliveryHealthy: deliveryHealthy, onCall: onCall,
                                                  now: origin.addingTimeInterval(seconds), state: state)
            state = decision.state
            answers.append((seconds, decision))
            return decision
        }

        func wake(at seconds: TimeInterval) {
            state = state.recordingWake(at: origin.addingTimeInterval(seconds))
        }

        /// Asks about one health every `step` seconds from `from` through `through`.
        func askEvery(_ step: TimeInterval, from: TimeInterval = 0, through: TimeInterval, _ health: CaptureHealth) {
            var seconds = from
            while seconds <= through {
                ask(health, at: seconds)
                seconds += step
            }
        }

        var beeps: [TimeInterval] { answers.filter(\.decision.beep).map(\.seconds) }
        var banners: [TimeInterval] { answers.filter(\.decision.postBanner).map(\.seconds) }
    }

    private func minutes(_ values: [Int]) -> [TimeInterval] { values.map { TimeInterval($0 * 60) } }

    // MARK: - The numbers

    /// Six repeats five minutes apart: the wait after each of the first six beeps
    /// is five minutes, so the seventh beep is the sixth repeat, and the wait
    /// after it and every one from then on is half an hour.
    func testTheScheduleIsSixRepeatsFiveMinutesApartAndThenThirtyMinutes() {
        XCTAssertEqual(Plan.shortRepeatInterval, 300)
        XCTAssertEqual(Plan.longRepeatInterval, 1800)
        XCTAssertEqual(Plan.repeatsAtShortInterval, 6)
        for count in 1...6 {
            XCTAssertEqual(Plan.repeatInterval(afterBeeps: count), 300, "after beep \(count)")
        }
        for count in [7, 8, 20, 1000] {
            XCTAssertEqual(Plan.repeatInterval(afterBeeps: count), 1800, "after beep \(count)")
        }
    }

    /// Three times the self-test's five-second timeout.
    func testTheSlackIsFifteenSeconds() {
        XCTAssertEqual(Plan.beepSlack, 15)
    }

    func testTheBoundsAreTwoIntervalsAndTwoMinutes() {
        XCTAssertEqual(Plan.unverifiedBound, 600)
        XCTAssertEqual(Plan.unverifiedBoundAfterWake, 120)
        XCTAssertEqual(Plan.unverifiedBound(afterWake: false), 600)
        XCTAssertEqual(Plan.unverifiedBound(afterWake: true), 120)
        XCTAssertEqual(Plan.unverifiedBound, 2 * HealthEvaluator.onCallSelfTestInterval)
    }

    // MARK: - Off call: what the alarm has always done

    func testOffCallSoundsOnceForEachChangeIntoAnAlarmingStateAndNeverAgain() {
        let asker = Asker(origin: origin, onCall: false)
        asker.ask(.unknown, at: 0)
        asker.ask(degraded, at: 60)
        asker.askEvery(60, from: 120, through: 36_000, degraded)
        asker.ask(.verified, at: 36_060)
        asker.ask(degraded, at: 36_120)
        asker.ask(blind, at: 36_180)
        XCTAssertEqual(asker.beeps, [60, 36_120, 36_180])
    }

    /// The rule the alarm used before this plan, as it was written: nothing about
    /// time, and one beep for each read that differs from the last and alarms.
    private struct Before {
        var lastReported: CaptureHealth?

        mutating func report(_ health: CaptureHealth, deliveryHealthy: Bool) -> (beep: Bool, banner: Bool) {
            guard health != lastReported else { return (false, false) }
            lastReported = health
            guard health.isAlarming else { return (false, false) }
            return (true, deliveryHealthy)
        }
    }

    /// Off call is the old rule over every run of four reads from ten, with
    /// delivery healthy or not and with gaps of any length between them,
    /// including ones long enough to be due on call.
    func testOffCallIsExactlyTheRuleTheAlarmUsedBefore() {
        let healths: [CaptureHealth] = [.unknown, .verified, degraded, otherDegraded, blind]
        let reads = healths.flatMap { health in [true, false].map { (health, $0) } }
        for gap in [1.0, 61, 400, 5000] {
            for a in reads { for b in reads { for c in reads { for d in reads {
                var before = Before()
                var state = Plan.State()
                for (index, read) in [a, b, c, d].enumerated() {
                    let expected = before.report(read.0, deliveryHealthy: read.1)
                    let decision = Plan.decide(health: read.0, deliveryHealthy: read.1, onCall: false,
                                               now: at(gap * Double(index)), state: state)
                    state = decision.state
                    XCTAssertEqual(decision.beep, expected.beep, "beep, read \(index) of \([a, b, c, d]) at gap \(gap)")
                    XCTAssertEqual(decision.postBanner, expected.banner,
                                   "banner, read \(index) of \([a, b, c, d]) at gap \(gap)")
                }
            } } } }
        }
    }

    func testOffCallTheBannerComesWithTheBeepWhenDeliveryIsHealthyAndNotOtherwise() {
        let healthy = Asker(origin: origin, onCall: false)
        healthy.ask(degraded, at: 0)
        XCTAssertEqual(healthy.banners, [0])

        let unhealthy = Asker(origin: origin, onCall: false)
        unhealthy.deliveryHealthy = false
        unhealthy.ask(degraded, at: 0)
        XCTAssertEqual(unhealthy.beeps, [0], "the beep depends on neither channel")
        XCTAssertTrue(unhealthy.banners.isEmpty, "a banner is useless when delivery is the fault")
    }

    /// `.unknown` is not an alarming health, and off call it never becomes a
    /// fault, however long it stands and whether or not the Mac has woken.
    func testOffCallUnknownForTenHoursNeverSounds() {
        let asker = Asker(origin: origin, onCall: false)
        asker.wake(at: 30)
        asker.askEvery(60, through: 36_000, .unknown)
        XCTAssertTrue(asker.beeps.isEmpty)
        XCTAssertTrue(asker.banners.isEmpty)
    }

    // MARK: - On call: the beep repeats

    /// The first beep and six repeats five minutes apart, which is seven beeps
    /// in the first half hour, then every 30 minutes, and a ten-hour run of
    /// one-minute asks gives exactly those beeps: the beep never stops while the
    /// state stands.
    func testOnCallRepeatsSixTimesAnIntervalApartAndThenEveryThirtyMinutes() {
        let asker = Asker(origin: origin, onCall: true)
        asker.askEvery(60, through: 600 * 60, degraded)
        let expected = minutes([0, 5, 10, 15, 20, 25, 30]) + Array(stride(from: 60.0 * 60, through: 600 * 60, by: 30 * 60))
        XCTAssertEqual(asker.beeps, expected)
        XCTAssertEqual(expected.count, 26, "seven in the first half hour, then one every half hour to the tenth hour")
    }

    /// The sixth repeat is the one at 30 minutes, and it is the last at the short
    /// interval: nothing sounds between it and the hour. This is the line between
    /// the two readings of the plan's "the first six", six beeps in all, which
    /// would stop at 25 minutes and wait until 55, and the first beep and six
    /// repeats, which is what stands.
    func testTheFirstHalfHourHoldsSevenBeepsAndTheEighthIsAnHourIn() {
        let asker = Asker(origin: origin, onCall: true)
        asker.askEvery(60, through: 60 * 60, degraded)
        XCTAssertEqual(asker.beeps, minutes([0, 5, 10, 15, 20, 25, 30, 60]))
        XCTAssertEqual(asker.state.soundedCount, 8)
    }

    /// Timers that wait for a self-test make two asks fall a little more or less
    /// than an interval apart. Compared exactly, a gap of 290 seconds would skip
    /// its beep and wait a whole cycle.
    func testAsksThatDriftTenSecondsEitherSideStillGiveSevenBeepsAboutFiveMinutesApart() {
        let asker = Asker(origin: origin, onCall: true)
        var seconds = 0.0
        asker.ask(degraded, at: seconds)
        for gap in [290.0, 310, 299.99, 300, 295, 305] {
            seconds += gap
            asker.ask(degraded, at: seconds)
        }
        // The first beep, then one for each of the six asks that followed it, and
        // the seventh beep is the last at the short interval.
        XCTAssertEqual(asker.beeps.count, 7, "\(asker.beeps)")
        XCTAssertEqual(asker.beeps, asker.answers.prefix(7).map(\.seconds))
        // The ask after the seventh beep is 305 seconds on, and the wait is now
        // half an hour.
        seconds += 305
        XCTAssertFalse(asker.ask(degraded, at: seconds).beep)
    }

    func testTheThirtyMinuteWaitDriftsTenSecondsEitherSideToo() {
        let asker = Asker(origin: origin, onCall: true)
        asker.askEvery(300, through: 1800, degraded)
        XCTAssertEqual(asker.beeps.count, 7)
        // 1790 seconds after the seventh beep, 10 seconds early, is within the slack.
        asker.ask(degraded, at: 1800 + 1790)
        XCTAssertEqual(asker.beeps.count, 8)
        // And 1810 after the eighth, 10 late.
        asker.ask(degraded, at: 1800 + 1790 + 1810)
        XCTAssertEqual(asker.beeps.count, 9)
    }

    /// The slack is 15 seconds, to the second: 285 seconds after a beep is the
    /// first ask that sounds again.
    func testTheBeepIsDueFifteenSecondsBeforeItsInterval() {
        for (gap, sounds) in [(14.0, false), (284.0, false), (284.99, false), (285.0, true), (300.0, true)] {
            let asker = Asker(origin: origin, onCall: true)
            asker.ask(degraded, at: 0)
            XCTAssertEqual(asker.ask(degraded, at: gap).beep, sounds, "\(gap) seconds after a beep")
        }
    }

    /// The menu opening asks as well, so two asks a few seconds apart are
    /// ordinary, and must not sound twice.
    func testAskingTwiceInsideOneIntervalSoundsOnce() {
        let asker = Asker(origin: origin, onCall: true)
        asker.ask(degraded, at: 0)
        asker.ask(degraded, at: 0)
        asker.ask(degraded, at: 14)
        asker.ask(degraded, at: 100)
        XCTAssertEqual(asker.beeps, [0])
    }

    /// A beep for a state restarts the wait of the next, so a change of health
    /// part way through an interval is not followed by a beep at the old time.
    func testAChangeOfHealthSoundsAtOnceAndBeginsItsOwnSchedule() {
        let asker = Asker(origin: origin, onCall: true)
        asker.askEvery(60, through: 420, degraded)
        asker.ask(blind, at: 480)
        asker.askEvery(60, from: 540, through: 1000, blind)
        XCTAssertEqual(asker.beeps, [0, 300, 480, 780])
    }

    func testAChangeOfHealthBeginsItsCountAfresh() {
        let asker = Asker(origin: origin, onCall: true)
        asker.askEvery(60, through: 1800, degraded)
        XCTAssertEqual(asker.state.soundedCount, 7)
        asker.ask(otherDegraded, at: 1860)
        XCTAssertEqual(asker.state.soundedCount, 1)
        // The first repeats of the new state are an interval apart again, not half
        // an hour, as the seventh beep of the old one would have made them.
        asker.askEvery(60, from: 1920, through: 1860 + 300, otherDegraded)
        XCTAssertEqual(asker.beeps.last, 2160)
    }

    /// What switching on does to the alarm is begin it afresh, so a fault that
    /// was already standing sounds for someone who has just said they are on
    /// call, and not only after a wait that began before they did.
    func testAFreshStateSoundsForAFaultAlreadyStandingAndACarriedOneDoesNot() {
        let carried = Asker(origin: origin, onCall: false)
        carried.ask(degraded, at: 0)
        carried.onCall = true
        XCTAssertFalse(carried.ask(degraded, at: 60).beep)

        let fresh = Asker(origin: origin, onCall: true, state: .init())
        let first = fresh.ask(degraded, at: 60)
        XCTAssertTrue(first.beep)
        XCTAssertTrue(first.postBanner)
        XCTAssertFalse(fresh.ask(degraded, at: 60).postBanner, "the second ask is no change")
    }

    /// Switching off leaves what the alarm remembers alone, so a fault that stood
    /// on call is not told again off call, and the old once-per-change rule holds.
    func testSwitchingOffStopsTheRepeatsAndLeavesTheAlarmToItsOncePerChangeRule() {
        let asker = Asker(origin: origin, onCall: true)
        asker.askEvery(60, through: 360, degraded)
        asker.onCall = false
        asker.askEvery(60, from: 420, through: 36_000, degraded)
        XCTAssertEqual(asker.beeps, [0, 300])
        asker.ask(blind, at: 36_060)
        XCTAssertEqual(asker.beeps, [0, 300, 36_060])
    }

    // MARK: - On call: the banner

    func testOnCallTheBannerIsOncePerChangeAndOnlyWithHealthyDelivery() {
        let asker = Asker(origin: origin, onCall: true)
        asker.ask(degraded, at: 0)
        asker.askEvery(60, from: 60, through: 1200, degraded)
        XCTAssertEqual(asker.banners, [0], "the repeats of the beep post nothing")
        asker.ask(blind, at: 1260)
        XCTAssertEqual(asker.banners, [0, 1260])
        asker.askEvery(60, from: 1320, through: 2500, blind)
        XCTAssertEqual(asker.banners, [0, 1260])
        XCTAssertGreaterThan(asker.beeps.count, 4, "while the beeps went on repeating")
    }

    func testOnCallTheBannerIsSkippedWhenDeliveryIsNotHealthyAndTheBeepIsNot() {
        let asker = Asker(origin: origin, onCall: true)
        asker.deliveryHealthy = false
        asker.ask(degraded, at: 0)
        asker.ask(degraded, at: 300)
        XCTAssertEqual(asker.beeps, [0, 300])
        XCTAssertTrue(asker.banners.isEmpty)
    }

    // MARK: - On call: capture that stays unverified

    func testOnCallUnknownForNineMinutesFiftyNineSecondsDoesNotSoundAndAtTenMinutesDoes() {
        let asker = Asker(origin: origin, onCall: true)
        asker.askEvery(1, through: 599, .unknown)
        XCTAssertTrue(asker.beeps.isEmpty)
        let decision = asker.ask(.unknown, at: 600)
        XCTAssertTrue(decision.beep)
        XCTAssertFalse(decision.postBanner, "there is no cause to put in a banner")
    }

    func testUnverifiedCaptureSoundsOnTheScheduleWithNoBannerAtAnyBeep() {
        let asker = Asker(origin: origin, onCall: true)
        asker.askEvery(60, through: 600 * 60, .unknown)
        let atShortInterval = minutes([10, 15, 20, 25, 30, 35, 40])
        let expected = atShortInterval + Array(stride(from: 70.0 * 60, through: 600 * 60, by: 30 * 60))
        XCTAssertEqual(asker.beeps, expected)
        XCTAssertTrue(asker.banners.isEmpty)
    }

    func testAVerifiedReadInBetweenRestartsTheBound() {
        let asker = Asker(origin: origin, onCall: true)
        asker.askEvery(60, through: 540, .unknown)
        asker.ask(.verified, at: 600)
        asker.ask(.unknown, at: 601)
        asker.ask(.unknown, at: 601 + 599)
        XCTAssertTrue(asker.beeps.isEmpty, "unknown again for 9:59 since the verified read")
        asker.ask(.unknown, at: 601 + 600)
        XCTAssertEqual(asker.beeps, [1201])
    }

    /// The bound counts a run of unknown reads, and any other health ends the
    /// run, an alarming one included.
    func testAChangeToAnythingElseAlsoRestartsTheBound() {
        let asker = Asker(origin: origin, onCall: true)
        asker.askEvery(60, through: 540, .unknown)
        asker.ask(degraded, at: 600)
        asker.ask(.unknown, at: 601)
        asker.ask(.unknown, at: 601 + 599)
        XCTAssertEqual(asker.beeps, [600], "only the degraded read's own beep")
        asker.ask(.unknown, at: 601 + 600)
        XCTAssertEqual(asker.beeps, [600, 1201])
    }

    /// Capture left unverified is a state of its own. A beep that sounded for
    /// another health a little before does not hold its first beep back, which
    /// is for repeats of one state.
    func testTheUnverifiedFaultSoundsOnItsOwnScheduleWhateverSoundedBeforeIt() {
        let asker = Asker(origin: origin, onCall: true)
        asker.ask(.verified, at: 0)
        asker.wake(at: 100)
        asker.ask(degraded, at: 105)
        asker.ask(.unknown, at: 110)
        asker.ask(.unknown, at: 110 + 119)
        XCTAssertEqual(asker.beeps, [105])
        XCTAssertTrue(asker.ask(.unknown, at: 110 + 120).beep, "125 seconds after a beep for another state")
    }

    func testUnknownAtLaunchForAMinuteWhileOnCallNeverSounds() {
        let asker = Asker(origin: origin, onCall: true)
        asker.askEvery(10, through: 60, .unknown)
        XCTAssertTrue(asker.beeps.isEmpty)
    }

    func testABlindOrDegradedReadAfterUnknownSoundsAtOnceAsBefore() {
        for alarming in [degraded, blind] {
            let asker = Asker(origin: origin, onCall: true)
            asker.askEvery(60, through: 300, .unknown)
            let decision = asker.ask(alarming, at: 360)
            XCTAssertTrue(decision.beep, "\(alarming)")
            XCTAssertTrue(decision.postBanner, "\(alarming)")
        }
    }

    /// A wake since health last read verified brings the bound down to two
    /// minutes, to the second; without one it is ten.
    func testWithAWakeSinceVerifiedTheBoundIsTwoMinutesToTheSecond() {
        let asker = Asker(origin: origin, onCall: true)
        asker.ask(.verified, at: 0)
        asker.wake(at: 100)
        asker.ask(.unknown, at: 110)
        asker.ask(.unknown, at: 110 + 119)
        XCTAssertTrue(asker.beeps.isEmpty)
        XCTAssertTrue(asker.ask(.unknown, at: 110 + 120).beep)
    }

    func testWithoutAWakeSinceVerifiedTheBoundIsTenMinutes() {
        let asker = Asker(origin: origin, onCall: true)
        asker.ask(.verified, at: 0)
        asker.ask(.unknown, at: 110)
        asker.ask(.unknown, at: 110 + 120)
        asker.ask(.unknown, at: 110 + 599)
        XCTAssertTrue(asker.beeps.isEmpty)
        XCTAssertTrue(asker.ask(.unknown, at: 110 + 600).beep)
    }

    /// A wake that came before the verified read is not one since it.
    func testAWakeBeforeTheLastVerifiedReadDoesNotShortenTheBound() {
        let asker = Asker(origin: origin, onCall: true)
        asker.wake(at: 50)
        asker.ask(.verified, at: 100)
        asker.ask(.unknown, at: 110)
        asker.ask(.unknown, at: 110 + 120)
        XCTAssertTrue(asker.beeps.isEmpty)
        XCTAssertTrue(asker.ask(.unknown, at: 110 + 600).beep)
    }

    /// A Mac that has never read verified and has woken is one that woke since
    /// it last read verified.
    func testAWakeWithNothingEverVerifiedShortensTheBound() {
        let asker = Asker(origin: origin, onCall: true)
        asker.wake(at: 5)
        asker.ask(.unknown, at: 10)
        XCTAssertFalse(asker.ask(.unknown, at: 10 + 119).beep)
        XCTAssertTrue(asker.ask(.unknown, at: 10 + 120).beep)
    }

    /// Capture left unverified before a sleep has not been left with nothing
    /// running for the hours the Mac was asleep, and a self-test runs on waking,
    /// so the two minutes count from the wake.
    func testTheTwoMinutesCountFromTheWakeAndNotFromBeforeTheSleep() {
        let asker = Asker(origin: origin, onCall: true)
        asker.ask(.verified, at: 0)
        asker.ask(.unknown, at: 400)
        // Asleep from 500 to 3600, with nothing asked.
        asker.wake(at: 3600)
        asker.ask(.unknown, at: 3605)
        XCTAssertTrue(asker.beeps.isEmpty, "unknown since 400, but only five seconds since the wake")
        XCTAssertFalse(asker.ask(.unknown, at: 3600 + 119).beep)
        XCTAssertTrue(asker.ask(.unknown, at: 3600 + 120).beep)
    }

    func testAWakeThatTheSelfTestVerifiedLeavesNothingToSound() {
        let asker = Asker(origin: origin, onCall: true)
        asker.ask(.verified, at: 0)
        asker.wake(at: 3600)
        asker.ask(.verified, at: 3606)
        asker.askEvery(60, from: 3666, through: 36_000, .verified)
        XCTAssertTrue(asker.beeps.isEmpty)
    }

    /// One failure after a wake is allowed on a healthy app, and is the one beep:
    /// a retry that verifies ends it.
    func testAHealthyAppAfterAWakeGivesAtMostTheOneDidNotCompleteBeep() {
        let asker = Asker(origin: origin, onCall: true)
        asker.ask(.verified, at: 0)
        asker.wake(at: 3600)
        asker.ask(.degraded([.selfTestInconclusive]), at: 3606)
        asker.ask(.verified, at: 3666)
        asker.askEvery(60, from: 3726, through: 36_000, .verified)
        XCTAssertEqual(asker.beeps, [3606])
    }

    // MARK: - One function for the beep and the icon

    private func state(unknownSince: TimeInterval? = nil, verified: TimeInterval? = nil,
                       woke: TimeInterval? = nil) -> Plan.State {
        Plan.State(lastReported: .unknown, unknownSince: unknownSince.map(at),
                   lastVerifiedAt: verified.map(at), lastWakeAt: woke.map(at))
    }

    func testTheFaultIsOnlyUnknownOnCallThatHasStoodForTheBound() {
        let standing = state(unknownSince: 0)
        XCTAssertFalse(Plan.isUnverifiedFault(onCall: true, health: .unknown, state: standing, now: at(599)))
        XCTAssertTrue(Plan.isUnverifiedFault(onCall: true, health: .unknown, state: standing, now: at(600)))
        XCTAssertTrue(Plan.isUnverifiedFault(onCall: true, health: .unknown, state: standing, now: at(36_000)))
        XCTAssertFalse(Plan.isUnverifiedFault(onCall: false, health: .unknown, state: standing, now: at(36_000)),
                       "never off call")
        for other in [CaptureHealth.verified, degraded, blind] {
            XCTAssertFalse(Plan.isUnverifiedFault(onCall: true, health: other, state: standing, now: at(36_000)),
                           "\(other) is not unknown")
        }
        XCTAssertFalse(Plan.isUnverifiedFault(onCall: true, health: .unknown, state: state(), now: at(36_000)),
                       "nothing says since when it was unknown")
    }

    func testTheFaultUsesTheWakeBoundOnlyWhenTheMacHasWokenSinceVerified() {
        let woke = state(unknownSince: 100, verified: 0, woke: 50)
        XCTAssertFalse(Plan.isUnverifiedFault(onCall: true, health: .unknown, state: woke, now: at(100 + 119)))
        XCTAssertTrue(Plan.isUnverifiedFault(onCall: true, health: .unknown, state: woke, now: at(100 + 120)))
        let wokeBefore = state(unknownSince: 100, verified: 80, woke: 50)
        XCTAssertFalse(Plan.isUnverifiedFault(onCall: true, health: .unknown, state: wokeBefore, now: at(100 + 599)))
        XCTAssertTrue(Plan.isUnverifiedFault(onCall: true, health: .unknown, state: wokeBefore, now: at(100 + 600)))
    }

    /// The icon asks this function for the state the alarm holds, so the two are
    /// the same moment: the first ask the beep sounds on is the first the
    /// function says is a fault, with or without a wake.
    func testTheBeepAndTheFunctionTheIconAsksAgreeToTheSecond() {
        for wokeAt in [nil, 30.0] as [TimeInterval?] {
            let asker = Asker(origin: origin, onCall: true)
            if let wokeAt { asker.wake(at: wokeAt) }
            var firstFault: TimeInterval?
            var firstBeep: TimeInterval?
            for seconds in stride(from: 40.0, through: 800, by: 1) {
                let decision = asker.ask(.unknown, at: seconds)
                if firstFault == nil,
                   Plan.isUnverifiedFault(onCall: true, health: .unknown, state: decision.state, now: at(seconds)) {
                    firstFault = seconds
                }
                if firstBeep == nil, decision.beep { firstBeep = seconds }
            }
            XCTAssertNotNil(firstBeep)
            XCTAssertEqual(firstFault, firstBeep, "wake at \(String(describing: wokeAt))")
        }
    }

    // MARK: - A clock set back

    /// A clock set back an hour would leave the time of the last beep in the
    /// future, and the alarm would wait for the clock to catch up before it
    /// sounded again. The wait begins again from the time the clock now gives.
    func testAClockSetBackAfterABeepRestartsTheWaitInsteadOfWaitingForTheClock() {
        let asker = Asker(origin: origin, onCall: true)
        asker.ask(degraded, at: 0)
        asker.ask(degraded, at: -3600)
        XCTAssertEqual(asker.beeps, [0], "no beep for being asked again at once")
        asker.ask(degraded, at: -3600 + 284)
        XCTAssertEqual(asker.beeps, [0])
        asker.ask(degraded, at: -3600 + 285)
        XCTAssertEqual(asker.beeps, [0, -3600 + 285])
    }

    func testAClockSetBackWhileUnverifiedRestartsTheBoundFromTheNewTime() {
        let asker = Asker(origin: origin, onCall: true)
        asker.ask(.unknown, at: 0)
        asker.ask(.unknown, at: -3600)
        asker.ask(.unknown, at: -3600 + 599)
        XCTAssertTrue(asker.beeps.isEmpty)
        XCTAssertTrue(asker.ask(.unknown, at: -3600 + 600).beep)
    }

    func testAClockSetBackPastTheLastVerifiedReadStillCountsAWakeAfterIt() {
        let asker = Asker(origin: origin, onCall: true)
        asker.ask(.verified, at: 0)
        asker.wake(at: -3000)
        asker.ask(.unknown, at: -3000 + 10)
        asker.ask(.unknown, at: -3000 + 10 + 119)
        XCTAssertTrue(asker.beeps.isEmpty)
        XCTAssertTrue(asker.ask(.unknown, at: -3000 + 10 + 120).beep, "the wake's bound, not the ten minutes")
    }

    func testAClockSetBackPastTheLastWakeStillCountsTheWake() {
        let asker = Asker(origin: origin, onCall: true)
        asker.ask(.verified, at: 0)
        asker.wake(at: 1000)
        asker.ask(.unknown, at: 1010)
        asker.ask(.unknown, at: -3600)
        asker.ask(.unknown, at: -3600 + 119)
        XCTAssertTrue(asker.beeps.isEmpty)
        XCTAssertTrue(asker.ask(.unknown, at: -3600 + 120).beep)
    }

    // MARK: - What it remembers

    func testItCountsItsBeepsForTheStateAndRemembersWhenItLastSounded() {
        let asker = Asker(origin: origin, onCall: true)
        asker.ask(degraded, at: 0)
        XCTAssertEqual(asker.state.soundedCount, 1)
        XCTAssertEqual(asker.state.lastSoundedAt, at(0))
        asker.ask(degraded, at: 100)
        XCTAssertEqual(asker.state.soundedCount, 1)
        asker.ask(degraded, at: 300)
        XCTAssertEqual(asker.state.soundedCount, 2)
        XCTAssertEqual(asker.state.lastSoundedAt, at(300))
        XCTAssertEqual(asker.state.lastReported, degraded)
        // Both belong to the state, and a change of health ends it.
        asker.ask(.verified, at: 400)
        XCTAssertEqual(asker.state.soundedCount, 0)
        XCTAssertNil(asker.state.lastSoundedAt)
        XCTAssertEqual(asker.state.lastReported, .verified)
    }

    func testItRemembersWhenHealthFirstReadUnknownAndLastReadVerified() {
        let asker = Asker(origin: origin, onCall: true)
        asker.ask(.verified, at: 10)
        asker.ask(.unknown, at: 20)
        asker.ask(.unknown, at: 30)
        XCTAssertEqual(asker.state.unknownSince, at(20), "from the first of the run")
        XCTAssertEqual(asker.state.lastVerifiedAt, at(10))
        asker.ask(.verified, at: 40)
        XCTAssertNil(asker.state.unknownSince)
        XCTAssertEqual(asker.state.lastVerifiedAt, at(40))
        asker.ask(degraded, at: 50)
        XCTAssertEqual(asker.state.lastVerifiedAt, at(40), "only a verified read moves it")
    }

    func testTellingItTheMacWokeRemembersWhenAndChangesNothingElse() {
        let before = Plan.State(lastReported: degraded, lastSoundedAt: at(5), soundedCount: 2,
                                unknownSince: at(1), lastVerifiedAt: at(2))
        var expected = before
        expected.lastWakeAt = at(100)
        XCTAssertEqual(before.recordingWake(at: at(100)), expected)
    }

    func testAWakeIsOneSinceVerifiedWhenItIsAtOrAfterTheVerifiedReadOrNothingWasVerified() {
        XCTAssertFalse(Plan.State().wokeSinceVerified, "no wake")
        XCTAssertFalse(Plan.State(lastVerifiedAt: at(10)).wokeSinceVerified, "no wake")
        XCTAssertTrue(Plan.State(lastWakeAt: at(10)).wokeSinceVerified, "nothing verified")
        XCTAssertTrue(Plan.State(lastVerifiedAt: at(10), lastWakeAt: at(11)).wokeSinceVerified)
        XCTAssertTrue(Plan.State(lastVerifiedAt: at(10), lastWakeAt: at(10)).wokeSinceVerified, "the same moment")
        XCTAssertFalse(Plan.State(lastVerifiedAt: at(11), lastWakeAt: at(10)).wokeSinceVerified)
    }
}
