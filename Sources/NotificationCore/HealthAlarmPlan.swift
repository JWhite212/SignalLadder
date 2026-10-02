// Sources/NotificationCore/HealthAlarmPlan.swift
import Foundation

/// When the health alarm beeps, and whether it posts its banner (M5 plan,
/// Rulings 9 and 10, O5).
///
/// The alarm is the one channel that depends on neither Accessibility nor the
/// notification system (`HealthAlarm`), so it is the one that tells someone on
/// call that the app can no longer tell them anything. Whether it sounds is
/// decided here, as a pure function of the health read, the time and what it
/// did last, and `HealthAlarm` only carries the answer out.
///
/// **Off call** it is what the app has always done: one beep for each change of
/// health into an alarming state, and the banner with it when the app's own
/// notifications can be shown. A fault that stands all night is told once.
///
/// **On call** it does not go quiet while a fault stands. After the first beep
/// of one unresolved state it beeps again six times, each an on-call interval
/// (five minutes) after the one before, so seven beeps in the first half hour,
/// and then every 30 minutes for as long as the state stands, so that the beep
/// never stops while a fault does. A change of health begins a state afresh and
/// sounds at once. The banner is still only for a change, and only when
/// delivery is healthy: under a Focus it is swallowed while delivery reads
/// healthy, so repeating it would repeat nothing anyone sees.
///
/// **Capture that stays unverified is a fault on call.** `.unknown` is not an
/// alarming health, `HealthAlarm` returned silently for it, and a self-test that
/// could not post or was overlapped records no failure, so capture that stayed
/// unverified for hours while on call would have been told by the menu line
/// alone. On call it is a fault once it has stood for two intervals, or for two
/// minutes when the Mac has woken since health last read verified, since a
/// self-test runs on waking and that is long enough for it. It sounds on the
/// same schedule and posts no banner, since there is no cause to put in one. Off
/// call it never sounds, however long it stands.
public enum HealthAlarmPlan {
    // MARK: - The schedule

    /// How many repeats of the first beep of one unresolved state come an on-call
    /// interval after the beep before, ahead of those every `longRepeatInterval`.
    /// Six, so seven beeps in the first half hour, at 0, 5, 10, 15, 20, 25 and 30
    /// minutes, and the eighth an hour in. The plan's "the first six" can also be
    /// read as six beeps in all, which would leave the one at 30 minutes out;
    /// where a choice is between one alert too many and one too few, it is one
    /// too many.
    public static let repeatsAtShortInterval = 6

    /// The wait after each of the first `repeatsAtShortInterval` beeps: the
    /// on-call self-test interval, so the alarm asks again as often as health is
    /// checked.
    public static let shortRepeatInterval: TimeInterval = HealthEvaluator.onCallSelfTestInterval

    /// The wait after every beep from then on, for as long as the state stands.
    public static let longRepeatInterval: TimeInterval = 30 * 60

    /// How much sooner than its interval a beep may sound, 15 seconds, which is
    /// three times the self-test's 5-second timeout (`CanaryService.run`).
    ///
    /// The asks come from a 300-second timer and from retry timers that each
    /// wait for a self-test, so a beep recorded 5.01 seconds after one timer and
    /// the next ask made 5.00 seconds after the following one are 299.99 seconds
    /// apart. Compared exactly, that ask would be skipped and the next beep would
    /// wait a whole cycle.
    public static let beepSlack: TimeInterval = 15

    /// The wait after the beep that is number `count` in its state: five minutes
    /// after each of the first six, and half an hour after the seventh and every
    /// one from then on.
    public static func repeatInterval(afterBeeps count: Int) -> TimeInterval {
        count <= repeatsAtShortInterval ? shortRepeatInterval : longRepeatInterval
    }

    // MARK: - Capture that stays unverified

    /// How long `.unknown` must have stood, on call, to be a fault: two
    /// self-test intervals.
    public static let unverifiedBound: TimeInterval = 2 * HealthEvaluator.onCallSelfTestInterval

    /// The same when the Mac has woken since health last read verified. A
    /// self-test runs on waking, so capture that is still not verified two
    /// minutes after is not waiting for one.
    public static let unverifiedBoundAfterWake: TimeInterval = 120

    /// The bound that applies, which is the wake's when the Mac has woken since
    /// health last read verified.
    public static func unverifiedBound(afterWake: Bool) -> TimeInterval {
        afterWake ? unverifiedBoundAfterWake : unverifiedBound
    }

    // MARK: - What the alarm remembers

    /// What the alarm needs to remember between asks, as plain values.
    public struct State: Equatable, Sendable {
        /// The last health it was asked about, so a change can be told.
        public var lastReported: CaptureHealth?
        /// When it last sounded for the state it is in, and how many times it has
        /// for it. Both are cleared by a change of health.
        public var lastSoundedAt: Date?
        public var soundedCount: Int
        /// When health first read unknown, in the run of unknown reads that it
        /// is in now; nil when the last read was anything else.
        public var unknownSince: Date?
        /// When health last read verified.
        public var lastVerifiedAt: Date?
        /// When the Mac last woke.
        public var lastWakeAt: Date?

        public init(lastReported: CaptureHealth? = nil,
                    lastSoundedAt: Date? = nil,
                    soundedCount: Int = 0,
                    unknownSince: Date? = nil,
                    lastVerifiedAt: Date? = nil,
                    lastWakeAt: Date? = nil) {
            self.lastReported = lastReported
            self.lastSoundedAt = lastSoundedAt
            self.soundedCount = soundedCount
            self.unknownSince = unknownSince
            self.lastVerifiedAt = lastVerifiedAt
            self.lastWakeAt = lastWakeAt
        }

        /// Whether the Mac has woken since health last read verified, or since
        /// ever, when it never has. A wake at the very moment of a verification
        /// counts, since the clock cannot say which came first and the shorter
        /// bound is the one that alerts sooner.
        public var wokeSinceVerified: Bool {
            guard let woke = lastWakeAt else { return false }
            guard let verified = lastVerifiedAt else { return true }
            return woke >= verified
        }

        /// This state with every time it holds taken back to `now` if it is
        /// after it. A clock set back would otherwise leave each of them in the
        /// future, and the alarm would wait for the clock to catch up before it
        /// sounded again: silent, for as long as the clock was set back. Read
        /// this way each wait begins again from the time the clock now gives.
        func clamped(to now: Date) -> State {
            var state = self
            state.lastSoundedAt = lastSoundedAt.map { min($0, now) }
            state.unknownSince = unknownSince.map { min($0, now) }
            state.lastVerifiedAt = lastVerifiedAt.map { min($0, now) }
            state.lastWakeAt = lastWakeAt.map { min($0, now) }
            return state
        }

        /// This state told that the Mac woke at `now`, which is when the
        /// two-minute bound starts.
        public func recordingWake(at now: Date) -> State {
            var state = clamped(to: now)
            state.lastWakeAt = now
            return state
        }
    }

    /// Whether capture that has stayed unverified is a fault, on call.
    ///
    /// The one function the alarm and the status icon both ask, so that the beep
    /// and the icon cannot disagree about it. It holds only for `.unknown` on
    /// call that has been read as unknown for the bound, counted from the later
    /// of the first unknown read and the Mac's last wake: time spent asleep is
    /// not time capture was left unverified with nothing running, and a self-test
    /// runs on waking.
    public static func isUnverifiedFault(onCall: Bool, health: CaptureHealth, state: State, now: Date) -> Bool {
        guard onCall, health == .unknown else { return false }
        let state = state.clamped(to: now)
        guard let since = state.unknownSince else { return false }
        let standingSince = max(since, state.lastWakeAt ?? since)
        return now.timeIntervalSince(standingSince) >= unverifiedBound(afterWake: state.wokeSinceVerified)
    }

    // MARK: - The decision

    public struct Decision: Equatable, Sendable {
        /// Whether to sound the beep.
        public let beep: Bool
        /// Whether to post the banner. Only ever with a beep, for a change into
        /// an alarming state, and when the app's own notifications can be shown.
        public let postBanner: Bool
        /// What the alarm remembers now.
        public let state: State

        public init(beep: Bool, postBanner: Bool, state: State) {
            self.beep = beep
            self.postBanner = postBanner
            self.state = state
        }
    }

    /// What to do about a health just read, and what to remember.
    ///
    /// - Parameters:
    ///   - deliveryHealthy: whether the app's own notifications can be shown.
    ///     The banner is skipped when it cannot, since it is useless exactly
    ///     when delivery is the fault.
    ///   - onCall: whether the user is on call now.
    ///   - now: the time of the read.
    ///   - state: what the alarm remembered from the last one.
    public static func decide(health: CaptureHealth,
                              deliveryHealthy: Bool,
                              onCall: Bool,
                              now: Date,
                              state previous: State) -> Decision {
        var state = previous.clamped(to: now)

        let changed = health != state.lastReported
        state.lastReported = health
        if changed {
            // A change of health begins a state afresh, on call or off.
            state.lastSoundedAt = nil
            state.soundedCount = 0
        }

        switch health {
        case .unknown:
            state.unknownSince = state.unknownSince ?? now
        case .verified:
            state.unknownSince = nil
            state.lastVerifiedAt = now
        case .degraded, .blind:
            state.unknownSince = nil
        }

        let beep: Bool
        if changed && health.isAlarming {
            // The one rule off call, and the first beep of a state on call.
            beep = true
        } else if onCall && !changed {
            beep = isRepeatDue(health: health, state: state, now: now)
        } else {
            beep = false
        }

        if beep {
            state.lastSoundedAt = now
            state.soundedCount += 1
        }
        return Decision(beep: beep,
                        postBanner: beep && changed && health.isAlarming && deliveryHealthy,
                        state: state)
    }

    /// Whether a state that has not changed since the last ask is one to sound
    /// for again, on call: it is a fault, and it is time.
    private static func isRepeatDue(health: CaptureHealth, state: State, now: Date) -> Bool {
        guard health.isAlarming || isUnverifiedFault(onCall: true, health: health, state: state, now: now) else {
            return false
        }
        // A fault that has not sounded yet, as capture that has just stayed
        // unverified too long has not, sounds now.
        guard let last = state.lastSoundedAt else { return true }
        let wait = repeatInterval(afterBeeps: state.soundedCount) - beepSlack
        return now.timeIntervalSince(last) >= wait
    }
}
