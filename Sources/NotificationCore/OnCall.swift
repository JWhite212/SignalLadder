// Sources/NotificationCore/OnCall.swift
import Foundation

/// Whether the user is on call, and since when (M5 plan, Ruling 7, O4).
///
/// The state is one saved date. A key that is there means on and one that is
/// not means off, so the state cannot disagree with itself as a Boolean beside
/// a date could, and it gives the menu an honest "since Mon 09:00". It never
/// expires: someone still on call at the end of a long shift is not switched
/// off by a timer.
///
/// What is saved may be anything, since a preferences file can be edited, and a
/// value that cannot be read as a time reads as on with no time known. The app
/// fails towards alerting, as it does elsewhere: a switch that may have been on
/// is not read as off.
public enum OnCallState: Equatable, Sendable {
    case off
    /// On. `since` is nil when something was saved and it could not be read as
    /// a time, which is on, since when is not known.
    case on(since: Date?)

    /// The key the date is saved under, in seconds since 1970. The app target
    /// reads and writes it and holds no word of its own for it.
    public static let storageKey = "onCallSince"

    /// Reads what the preferences gave for `storageKey`, which may be anything.
    ///
    /// - Absent is off.
    /// - A finite number, not negative, is on since that time, and never since
    ///   a time after `now`: a clock set back, or a value from the future,
    ///   reads as since now, so the menu cannot say the user went on call
    ///   tomorrow.
    /// - Anything else is on with no time known: a string, a Boolean, a date
    ///   or a list, and a number that is negative, infinite or not a number.
    public init(stored: Any?, now: Date) {
        guard let stored else {
            self = .off
            return
        }
        guard let seconds = Self.seconds(in: stored) else {
            self = .on(since: nil)
            return
        }
        self = .on(since: min(Date(timeIntervalSince1970: seconds), now))
    }

    /// A number as the preferences hand one back, or as Swift boxes one. A
    /// Boolean is not a number here: it reads as 1 or 0, which would be a time
    /// in the first second of 1970.
    private static func seconds(in stored: Any) -> TimeInterval? {
        guard let number = stored as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let seconds = number.doubleValue
        return seconds.isFinite && seconds >= 0 ? seconds : nil
    }

    public var isOn: Bool {
        if case .on = self { return true }
        return false
    }

    /// When it was switched on, if it is on and that is known.
    public var since: Date? {
        if case .on(let since) = self { return since }
        return nil
    }

    /// What saving this state does to the preferences.
    public enum Write: Equatable, Sendable {
        /// Take the key out, which is off. Off stores nothing.
        case remove
        /// Save the time, in seconds since 1970.
        case set(TimeInterval)
        /// Leave the key as it is. On with no time known has no time to save,
        /// and what is there is what made it on: removing it would switch the
        /// mode off, and a time made up for it would say what nobody knows.
        case keep
    }

    public var write: Write {
        switch self {
        case .off: return .remove
        case .on(let since?): return .set(since.timeIntervalSince1970)
        case .on(nil): return .keep
        }
    }
}

/// What the app does when the user switches on-call mode on or off, as an
/// ordered list the app carries out and decides nothing about (M5 plan,
/// Ruling 10). The list is the tested part: what comes in it, what does not,
/// and in what order.
///
/// The effects have no step that touches an escalation, so leaving the ones
/// already running alone (Ruling 20) is a property of the type. Later commits
/// of the milestone add to these lists: resetting the watch, and opening the
/// check window.
public enum OnCallSwitch {
    public enum Effect: Equatable, Sendable {
        /// Save the new state, so that it outlives a relaunch.
        case save
        /// Arm the self-test timer again, at the interval of the state just
        /// saved. Always after `save`: the interval is read from the state.
        case rearmSelfTestTimer
        /// Forget a retry that is waiting, and its back-off, because a
        /// self-test is run at once in its place (Ruling 8).
        case cancelPendingRetry
        /// Forget what the health alarm remembers, so that a fault already
        /// standing sounds for someone who has just said they are on call.
        /// Always before the self-test, whose report is the first to ask it.
        case resetHealthAlarm
        /// Hold the Mac awake against idle sleep, with the hold that on-call
        /// mode keeps for itself (O7). It is not the hold an escalation takes
        /// while a tier is to fire: that one ends with the escalation, and this
        /// one lasts as long as the mode. Asking for it again changes nothing.
        /// Always before the self-test, which is awaited, so that the hold does
        /// not wait on a banner.
        case holdAwake
        /// Let go of that hold, and of no other: what an escalation holds is
        /// its own, and is let go of when its last tier has fired.
        case releaseAwake
        /// Run a self-test now, with the follow-up two minutes later.
        case runSelfTestNow
    }

    /// - Turning on: the state is saved, the timer is armed at the on-call
    ///   interval, a pending retry goes, the health alarm starts afresh, the
    ///   Mac is held awake and a self-test runs at once, which takes the
    ///   retry's place.
    /// - Turning off: the state is saved, the timer is armed at the steady
    ///   interval and the hold is let go. A pending retry is kept and no
    ///   self-test is run, so a failed self-test's promise to retry in a minute
    ///   still holds, and the alarm's state is left alone (Ruling 8).
    public static func effects(turningOn: Bool) -> [Effect] {
        turningOn
            ? [.save, .rearmSelfTestTimer, .cancelPendingRetry, .resetHealthAlarm, .holdAwake, .runSelfTestNow]
            : [.save, .rearmSelfTestTimer, .releaseAwake]
    }

    /// What the app does at launch with the state it restored, before capture
    /// starts. Nothing is saved, armed or run: the timer is first armed at the
    /// restored state's interval, and the self-test at launch is the one every
    /// launch makes. Only the hold is not already in place, since it is taken
    /// when the mode is switched on and nothing has switched it on in this run.
    public enum LaunchEffect: Equatable, Sendable {
        /// Hold the Mac awake, as `Effect.holdAwake` does.
        case holdAwake
    }

    /// A restored state that is on holds the Mac awake from launch, one whose
    /// time could not be read included: it reads as on (Ruling 7), and a Mac
    /// that idle-sleeps while someone is on call captures nothing. Off holds
    /// nothing.
    public static func launchEffects(restored: OnCallState) -> [LaunchEffect] {
        restored.isOn ? [.holdAwake] : []
    }
}

/// The words on-call mode puts on the menu, in one place where they are tested
/// (M5 plan, Ruling 18). Each constant is declared on one line, as
/// `public static let NAME = "TEXT"`, which is the shape the harness reads.
public enum OnCallText {
    /// What the line under the On Call item begins with, whatever follows.
    public static let sinceStem = "On call since"
    /// In place of the moment when what was saved could not be read as one.
    public static let sinceUnknown = "a time that could not be read"
    /// Added to the line while self-tests are running.
    public static let cadenceEnding = " — self-test every 5 min"
    /// Added to the line while a self-test cannot run, which the health line
    /// says why.
    public static let pausedEnding = " — self-tests are paused, see the health line"
}
