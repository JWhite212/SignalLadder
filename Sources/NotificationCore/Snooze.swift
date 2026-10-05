// Sources/NotificationCore/Snooze.swift
import Foundation

/// How long a snooze lasts (M5 plan, O8). Four choices and no indefinite one:
/// a snooze that never ran out is a rule that never sounds, and the app is
/// there so that a page is not lost.
public enum SnoozeDuration: CaseIterable, Equatable, Sendable {
    case fifteenMinutes
    case thirtyMinutes
    case oneHour
    case twoHours

    public var seconds: TimeInterval {
        switch self {
        case .fifteenMinutes: return 15 * 60
        case .thirtyMinutes: return 30 * 60
        case .oneHour: return 60 * 60
        case .twoHours: return 2 * 60 * 60
        }
    }

    /// The longest a snooze may be: 2 hours (O8). The controller holds every end
    /// to it, on request, on restore and at every read, so no saved value and no
    /// clock can make one longer (Ruling 12).
    public static let longest: TimeInterval = 2 * 60 * 60
}

/// What snoozes have held and the user has not yet dismissed (M5 plan, Ruling
/// 12, O9): how many matches each rule had held, when the first was held, and
/// how many are still to be announced.
///
/// It is counts and a time and nothing a notification said. A rule is known by
/// its id, and its name is looked up from the current rules when a line is
/// shown (`SnoozeText.summaryLine`), so no name, no app and no text is ever
/// saved. A count whose id is no longer among the rules is kept and is shown
/// under its own words (a rule removed, or one written without an id and
/// reloaded since).
///
/// It outlives the end of a snooze, a relaunch and a new snooze, which adds to
/// it, and only the user's Dismiss clears it, and that takes out what the line
/// beside it showed and no more (`dismiss(_:)`). A page held ten minutes into a
/// snooze must still be on the menu when the next one starts.
///
/// ## What is saved
///
/// Under `SnoozeController.heldKey`, one dictionary, and nothing else:
///
/// - `"counts"`: a dictionary from a rule's id, as the string `UUID` writes it,
///   to the whole number of matches held for it, 1 or more;
/// - `"since"`: the time of the first hold, as seconds since 1970 in a real
///   number; left out when it is not known;
/// - `"unannounced"`: the whole number of matches held and not yet announced;
/// - `"unreadable"`: the whole number 1, and only when a record that could not
///   be read was found earlier and has not been dismissed.
///
/// An empty summary saves nothing at all: the key is taken out.
///
/// ## What is read back
///
/// What is saved may be anything, since a preferences file can be edited, and a
/// record that cannot be read is never dropped in silence (Ruling 12): what can
/// be read of it is kept, and the summary says that some of it could not be.
///
/// - Absent is none.
/// - A value that is not a dictionary, or has no dictionary of counts, is
///   unreadable and holds nothing.
/// - In the counts, an entry whose key is not an id, or whose value is not a
///   whole number from 1 to `largestReadableCount`, is unreadable and is left
///   out. A Boolean is not a number here. The rest are kept.
/// - A time that is not a finite number, or is negative, is not known; one that
///   is read is never later than now. A time is not a page, so one that cannot
///   be read does not mark the record.
/// - An announcement count that cannot be read is taken to be everything held
///   that could be counted, so that the user is told once more and not none.
/// - The marker `"unreadable"`, present with any value, keeps the record
///   unreadable.
public struct HeldSummary: Equatable, Sendable {
    /// Matches held, by the id of the rule that would have alerted.
    public private(set) var counts: [UUID: Int]
    /// When the first of them was held, if that is known.
    public private(set) var firstHeldAt: Date?
    /// Matches held and not yet announced. Owed an announcement while no snooze
    /// is active and this is above zero (Ruling 12).
    public private(set) var unannounced: Int
    /// Whether a saved record was found that could not be read, wholly or in
    /// part, so that matches were held that are not in `counts`.
    public private(set) var recordUnreadable: Bool

    /// The largest count a saved record may give one rule and be read. A bigger
    /// number is not a count anyone made, and a bound keeps the sum of a damaged
    /// record from overflowing.
    public static let largestReadableCount = Int(Int32.max)

    public init(counts: [UUID: Int] = [:], firstHeldAt: Date? = nil, unannounced: Int = 0,
                recordUnreadable: Bool = false) {
        self.counts = counts.filter { $0.value > 0 }
        self.firstHeldAt = firstHeldAt
        self.unannounced = max(0, unannounced)
        self.recordUnreadable = recordUnreadable
    }

    /// Nothing held and nothing unread: there is no summary to show.
    public var isEmpty: Bool { counts.isEmpty && !recordUnreadable }

    /// How many matches are counted.
    public var total: Int { counts.values.reduce(0, +) }

    /// Reads what the preferences gave for `SnoozeController.heldKey`.
    public init(stored: Any?, now: Date) {
        guard let stored else {
            self.init()
            return
        }
        var counts: [UUID: Int] = [:]
        var unreadable = false
        var firstHeldAt: Date?
        var unannounced: Int?

        if let record = stored as? [String: Any], let entries = record[Key.counts] as? [String: Any] {
            for (key, value) in entries {
                if let id = UUID(uuidString: key), let count = Self.wholeNumber(value, in: 1...Self.largestReadableCount) {
                    counts[id, default: 0] += count
                } else {
                    unreadable = true
                }
            }
            if let seconds = Self.seconds(record[Key.since]) {
                firstHeldAt = min(Date(timeIntervalSince1970: seconds), now)
            }
            unannounced = Self.wholeNumber(record[Key.unannounced], in: 0...Self.largestReadableCount)
            if record[Key.unreadable] != nil { unreadable = true }
        } else {
            unreadable = true
        }
        let total = counts.values.reduce(0, +)
        self.init(counts: counts, firstHeldAt: firstHeldAt,
                  // With nothing held there is nothing to announce, and with a
                  // count that cannot be read, what was counted is announced.
                  unannounced: counts.isEmpty ? 0 : (unannounced ?? total),
                  recordUnreadable: unreadable)
    }

    /// What to save for this summary, or nil for none, which takes the key out.
    public var propertyList: [String: Any]? {
        guard !isEmpty else { return nil }
        var record: [String: Any] = [
            Key.counts: Dictionary(uniqueKeysWithValues: counts.map { ($0.key.uuidString, $0.value) }),
            Key.unannounced: unannounced,
        ]
        if let firstHeldAt { record[Key.since] = firstHeldAt.timeIntervalSince1970 }
        if recordUnreadable { record[Key.unreadable] = 1 }
        return record
    }

    /// One match held for the rule `id`, now.
    mutating func recordHold(of id: UUID, at now: Date) {
        // The time of the first is not made up for a record that has lost its own.
        if isEmpty { firstHeldAt = now }
        counts[id, default: 0] += 1
        unannounced += 1
    }

    /// What was held has been announced, or the user has ended the snooze that
    /// held it and is looking at it: nothing more is owed.
    mutating func settled() {
        unannounced = 0
    }

    /// The user has seen `shown`, which is the summary a line was made from, and
    /// has dismissed it: what it counted is taken out, rule by rule, and what
    /// was held since is left (M5 plan, Ruling 12, Ruling 22). The menu is not
    /// redrawn while it is open, so a match held in those seconds is counted and
    /// is not on the line in front of the user, and a click on Dismiss must not
    /// take it out unseen.
    ///
    /// - What is still to be announced falls by what `shown` was still to
    ///   announce, and never below zero; with nothing left held it is zero.
    /// - A record that could not be read is cleared only when `shown` said so.
    /// - The time of the first hold goes when anything is taken out: the first of
    ///   what is left was held later, and when is not kept, so it is not known and
    ///   not made up.
    /// - A `shown` that has nothing in common with this takes out nothing and
    ///   changes nothing.
    mutating func dismiss(_ shown: HeldSummary) {
        let (heldBefore, unreadableBefore) = (counts, recordUnreadable)
        for (id, seen) in shown.counts {
            guard let held = counts[id] else { continue }
            counts[id] = held > seen ? held - seen : nil
        }
        if shown.recordUnreadable { recordUnreadable = false }
        guard counts != heldBefore || recordUnreadable != unreadableBefore else { return }
        firstHeldAt = nil
        unannounced = counts.isEmpty ? 0 : max(0, unannounced - shown.unannounced)
    }

    private enum Key {
        static let counts = "counts"
        static let since = "since"
        static let unannounced = "unannounced"
        static let unreadable = "unreadable"
    }

    /// A whole number in `range` as the preferences hand one back, or as Swift
    /// boxes one. A Boolean is not a number here: it reads as 1 or 0. Infinity and
    /// not-a-number are outside every range.
    private static func wholeNumber(_ stored: Any?, in range: ClosedRange<Int>) -> Int? {
        guard let stored, let number = stored as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let value = number.doubleValue
        guard value == value.rounded(), value >= Double(range.lowerBound), value <= Double(range.upperBound) else { return nil }
        return Int(value)
    }

    /// A finite number of seconds, not negative.
    private static func seconds(_ stored: Any?) -> TimeInterval? {
        guard let stored, let number = stored as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let value = number.doubleValue
        return value.isFinite && value >= 0 ? value : nil
    }
}

/// A snooze for a meeting, and what it held (M5 plan, Task 4, Rulings 12 and 13,
/// O8 to O10).
///
/// A snooze quiets only a rule that says it may be (`Rule.snoozeMayHold`), for at
/// most 2 hours, and it never touches an escalation already running. It is
/// global: one end, no per-app snooze, no per-rule end.
///
/// A `@MainActor` class in the core, taking `EscalationScheduler` for both its
/// clocks and its one timer, so that every end is proven by moving a clock in a
/// test and never by waiting on one. The closures are the app's, none with a
/// default: `save` writes a value to the preferences, or takes the key out when
/// the value is nil; `changed` asks for a redraw; `announce` makes the one sound
/// that says a snooze ran out having held something, which the app makes
/// `NSSound.beep()`. Anything it calls out to may call back in, so every change
/// is made, and saved, before it calls out.
///
/// ## When a snooze ends
///
/// Never by a timer alone. A timer that never fired, because the Mac slept or
/// the app was napping, must not leave the app quiet, so `endsAt` and `isActive`
/// compare times each time they are asked (M4 plan, Ruling 14; M5 Ruling 12).
/// `endsAt` is the smallest of
///
/// - the end that was saved, which is wall clock time;
/// - 2 hours from now, so a wall clock stepped backwards cannot stretch a
///   snooze past 2 hours from now; and
/// - the awake-time deadline set when the snooze started, which is held in
///   memory and not saved, since awake time is counted from boot. A clock
///   stepped back an hour cannot stretch a 15-minute snooze to 75 minutes, and
///   a sleep, which stops awake time, is governed by the wall end.
///
/// and is nil once that is not after now. After a relaunch there is no awake
/// deadline, and only the wall end and the 2 hours apply. Once the end is
/// noticed, by the timer or by a read, the snooze is over for good: its saved
/// end is taken out, so that a clock set back and a relaunch cannot bring it
/// back.
///
/// ## What is saved
///
/// `snoozeUntil`, under `untilKey`: the end, as seconds since 1970 in a real
/// number. Absent is no snooze. What is read back is never trusted: a value that
/// is not a finite number, one that is in the past and one that is of any other
/// type give no snooze, and one further off than 2 hours gives 2 hours, which is
/// then saved in its place. A stored value that gives no snooze is taken out.
///
/// `snoozeHeld`, under `heldKey`: the held summary, in the shape `HeldSummary`
/// documents. Numbers, a time, and rule ids as strings, and no name.
///
/// ## What is announced
///
/// A snooze that ran out having held something says so aloud, once (O9): the
/// announcement is owed while no snooze is active and the number of matches held
/// and not yet announced is above zero. `settle()` makes the one call of
/// `announce` and zeroes the number. It is called when the timer fires, at every
/// read that finds the snooze over, when a snooze is started, and by the app at
/// launch, for a snooze that ended while it was not running, and on every wake
/// (`SelfTestPlan.WakeStep.settleSnooze`), which is how a Mac that slept through
/// the end announces on waking and does not wait for whatever reads it next.
/// Ending a snooze from the menu announces nothing, since the user is looking at
/// it, though what it held stays on the summary.
@MainActor
public final class SnoozeController {
    /// Where the end is saved. The app target reads and writes it and holds no
    /// word of its own for it.
    public static let untilKey = "snoozeUntil"
    /// Where what was held is saved.
    public static let heldKey = "snoozeHeld"

    /// Writes `value` to the preferences under `key`, or takes the key out when
    /// the value is nil.
    public typealias Save = (_ key: String, _ value: Any?) -> Void

    private let scheduler: EscalationScheduler
    private let save: Save
    private let changed: () -> Void
    private let announce: () -> Void

    /// The end that is saved: wall clock time, while a snooze is running.
    private var wallEnd: Date?
    /// The deadline in awake time, set when the snooze starts and never saved.
    private var awakeDeadline: TimeInterval?
    private var held: HeldSummary
    private var timer: EscalationTimerToken?
    /// Which timer is the current one, so that a timer cancelled and still on its
    /// way, or delivered twice, does nothing.
    private var timerTicket = 0

    /// - Parameters:
    ///   - storedUntil: what the preferences gave for `untilKey`, which may be anything.
    ///   - storedHeld: what the preferences gave for `heldKey`, which may be anything.
    ///   - save: writes to the preferences. It is also called from here, once, when what
    ///     was stored for `untilKey` gives no snooze, which takes it out, or gives one cut
    ///     back to 2 hours, which saves that in its place, and for no other reason.
    ///   - changed: the snooze or the summary has changed: draw the menu and the
    ///     icon again. It may be called from inside a read that finds a snooze over.
    ///   - announce: a snooze ran out having held something.
    public init(scheduler: EscalationScheduler,
                storedUntil: Any?,
                storedHeld: Any?,
                save: @escaping Save,
                changed: @escaping () -> Void,
                announce: @escaping () -> Void) {
        self.scheduler = scheduler
        self.save = save
        self.changed = changed
        self.announce = announce
        let now = scheduler.now()
        held = HeldSummary(stored: storedHeld, now: now)

        if let storedUntil {
            let end = Self.seconds(storedUntil).map { Date(timeIntervalSince1970: $0) }
            if let end, end > now {
                let capped = min(end, now + SnoozeDuration.longest)
                wallEnd = capped
                if capped != end { save(Self.untilKey, capped.timeIntervalSince1970) }
                armTimer(after: capped.timeIntervalSince(now))
            } else {
                save(Self.untilKey, nil)
            }
        }
    }

    // MARK: - What the pipeline, the menu and the icon read

    /// When the snooze ends, or nil when none is running. Reading it settles
    /// what is owed if the snooze is found to be over.
    public var endsAt: Date? {
        settle()
        return clockEnd()
    }

    /// Whether a snooze is running now, by the clocks.
    public var isActive: Bool { endsAt != nil }

    /// What has been held and not dismissed.
    public var summary: HeldSummary {
        settle()
        return held
    }

    /// The pipeline's verdict on a match of `rule`: true only when the rule's
    /// own `snoozeMayHold` says so and a snooze is active. Answering yes records
    /// the hold, a whole-number count for the rule's id, saved at once; any other
    /// answer records nothing, so a rule that has no tick, makes no sound or ends
    /// in a Shortcut is never held and never counted (Ruling 12).
    public func holds(_ rule: Rule) -> Bool {
        guard isActive, rule.snoozeMayHold else { return false }
        held.recordHold(of: rule.id, at: scheduler.now())
        save(Self.heldKey, held.propertyList)
        changed()
        return true
    }

    // MARK: - Starting, ending, dismissing

    /// Starts a snooze, or replaces the one running with this one, from now: the
    /// new end is not added to the old (O8). What was held stays and is added to.
    public func start(_ duration: SnoozeDuration) {
        // A snooze that ran out unnoticed is settled first, so that what it held
        // is announced and is not folded into this one.
        settle()
        let now = scheduler.now()
        let end = now + duration.seconds
        wallEnd = end
        awakeDeadline = scheduler.awakeTime() + duration.seconds
        armTimer(after: duration.seconds)
        save(Self.untilKey, end.timeIntervalSince1970)
        changed()
    }

    /// Ends the snooze at the user's word, which includes the switching on of
    /// on-call mode (O10). It announces nothing and keeps what was held.
    public func end() {
        let running = wallEnd != nil
        let owed = held.unannounced > 0
        disarmTimer()
        wallEnd = nil
        awakeDeadline = nil
        held.settled()
        if running { save(Self.untilKey, nil) }
        if owed { save(Self.heldKey, held.propertyList) }
        if running || owed { changed() }
    }

    /// The user has seen `shown` and has dismissed it, which is the only thing
    /// that clears what was held. Nothing more is owed an announcement for what
    /// `shown` counted either.
    ///
    /// `shown` is the summary the line beside the Dismiss item was made from,
    /// which the app keeps from when it built the menu, as the Acknowledge item
    /// keeps the escalations it listed (Ruling 22). The menu is not redrawn
    /// while it is open, so a match that was held in the seconds it was open is
    /// counted and saved and is not on that line; dismissing takes out what the
    /// line counted and leaves the rest, with its saved count and the
    /// announcement it is owed, for the next opening of the menu to show. Nothing
    /// that was never shown is lost to a click (Ruling 12).
    public func dismissSummary(shown: HeldSummary) {
        var remaining = held
        remaining.dismiss(shown)
        guard remaining != held else { return }
        held = remaining
        save(Self.heldKey, held.propertyList)
        changed()
    }

    // MARK: - Settling

    /// Finds out whether the snooze is over, and says so if it ran out having
    /// held something. Called when the timer fires, by every read, when a snooze
    /// starts, and by the app at launch and on every wake. A snooze found over is
    /// drawn again (`changed`), so the icon does not keep the moon, whoever found
    /// it. Calling it again does nothing: what it announces it zeroes first.
    public func settle() {
        var drawAgain = false
        if wallEnd != nil, clockEnd() == nil {
            wallEnd = nil
            awakeDeadline = nil
            disarmTimer()
            save(Self.untilKey, nil)
            drawAgain = true
        }
        var owed = false
        if wallEnd == nil, held.unannounced > 0 {
            held.settled()
            save(Self.heldKey, held.propertyList)
            owed = true
        }
        if owed { announce() }
        if drawAgain { changed() }
    }

    // MARK: - Time

    /// The end by the clocks, or nil when it is not after now, or when no
    /// snooze is running. Nothing is changed.
    private func clockEnd() -> Date? {
        guard let wallEnd else { return nil }
        let now = scheduler.now()
        var end = min(wallEnd, now + SnoozeDuration.longest)
        if let awakeDeadline {
            end = min(end, now + max(0, awakeDeadline - scheduler.awakeTime()))
        }
        return end > now ? end : nil
    }

    private func armTimer(after seconds: TimeInterval) {
        disarmTimer()
        let ticket = timerTicket
        timer = scheduler.schedule(after: max(0, seconds)) { [weak self] in
            self?.timerFired(ticket)
        }
    }

    private func disarmTimer() {
        if let timer { scheduler.cancel(timer) }
        timer = nil
        timerTicket += 1
    }

    /// The one timer only asks the app to redraw, and settles what is owed. A
    /// timer that fires with the clocks not yet at the end, as one does after the
    /// wall clock was set back, is set again for what is left.
    ///
    /// Whether the snooze is still running is what `settle()` has just found out,
    /// and it is not asked of the clocks a second time: an end that was a hair
    /// ahead for `settle()` and has passed by the next read would otherwise leave
    /// a snooze that is over by the clocks, with no timer to say so, until
    /// something read it (Ruling 12). A snooze that `settle()` left running is
    /// given a timer, for no time at all if its end has just gone by, and that
    /// timer settles it.
    private func timerFired(_ ticket: Int) {
        guard ticket == timerTicket else { return }
        timer = nil
        settle()
        guard wallEnd != nil else { return }
        armTimer(after: clockEnd().map { $0.timeIntervalSince(scheduler.now()) } ?? 0)
    }

    /// A finite number of seconds, as the preferences hand one back, or as Swift
    /// boxes one. A Boolean reads as 1 or 0 here, which is a time in 1970 and so
    /// in the past, and gives no snooze like any other time that has gone.
    private static func seconds(_ stored: Any) -> TimeInterval? {
        guard let number = stored as? NSNumber else { return nil }
        let seconds = number.doubleValue
        return seconds.isFinite ? seconds : nil
    }
}
