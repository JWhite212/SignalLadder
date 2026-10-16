// Sources/NotificationCore/HeldSummary.swift
import Foundation

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
        guard let value = PreferenceValue.number(stored), value == value.rounded(),
              value >= Double(range.lowerBound), value <= Double(range.upperBound) else { return nil }
        return Int(value)
    }

    /// A finite number of seconds, not negative.
    private static func seconds(_ stored: Any?) -> TimeInterval? {
        PreferenceValue.seconds(stored)
    }
}
