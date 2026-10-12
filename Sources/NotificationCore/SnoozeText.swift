// Sources/NotificationCore/SnoozeText.swift
import Foundation

/// The words of a snooze (M5 plan, Ruling 18, Task 4): what the held summary
/// says, and the menu's titles and lines, which `menu(...)` puts together as one
/// value. The app shows what is made here and types no word of its own, so
/// nothing in the menu can say more than the app has read.
///
/// A count is "matches", never "messages": the app has read that a rule matched,
/// and not what the notification was. Nothing here names an app or says what a
/// notification said; what is shown of a match is the name of the rule the user
/// wrote, and how many matches it had.
///
/// The constants the harness reads are each on one line as
/// `public static let NAME = "TEXT"`, which is the shape it reads (Ruling 18).
public enum SnoozeText {
    /// What follows the count in every summary line: "6 matches held while
    /// snoozed". The harness reads it from this file.
    public static let heldStem = "held while snoozed"
    /// The whole stem of the summary line for one match, which the harness's
    /// summary guard compares. The line is this, then ": ", the rule's name and
    /// " ×1".
    public static let heldOneMatchStem = "1 match held while snoozed"
    /// All there is to say when the saved record of what was held cannot be read:
    /// that some matches were held, and that is all that is known (Ruling 12). It
    /// is the line, and it is never left out.
    public static let unreadableSentence = "Some matches were held while snoozed and their record could not be read"
    /// The same, added to the line of the matches that could be counted.
    public static let unreadableEnding = " — and some other matches were held and their record could not be read"
    /// What stands for a rule whose id is not among the current rules: it was
    /// removed, or it was written without an id and the rules have been reloaded
    /// since, which gives it a new one. Its count is kept and shown, and only
    /// its name cannot be.
    public static let ruleNotFound = "a rule that cannot be found by its id"

    /// How many rules a line names before it says how many more there are.
    public static let namesShown = 3

    // MARK: The menu's titles and lines

    /// The menu's Snooze item, which opens the submenu of durations. The harness
    /// reads it from this file.
    public static let menuTitle = "Snooze"
    /// The submenu's item that ends a snooze.
    public static let endTitle = "End Snooze"
    /// The item beside the summary line, which clears it.
    public static let dismissTitle = "Dismiss"
    /// What the line about a running snooze begins with, whatever follows: "Snoozed
    /// until 15:30 — quiets 3 of 5 rules". The harness reads it from this file.
    public static let activeStem = "Snoozed until"
    /// What the line of the rules a snooze does not quiet begins with: "Still
    /// alerting: On-call mentions".
    public static let stillAlertingStem = "Still alerting"
    /// The label of the editor's box, which the line that says no rule is ticked
    /// asks the user to tick, so that the two say the same words.
    public static let ruleSwitchLabel = "Stay quiet while I have snoozed"
    /// The Snooze submenu's first line while on call (O10). Starting a snooze
    /// while on call is allowed, and this says what it does. O10's own words were
    /// "quiets every rule you ticked", which is not so: a ticked rule that makes
    /// no sound, or whose last step is a Shortcut, is never held (O8, Ruling 12),
    /// and an on-call user told otherwise could believe their phone page is quiet.
    /// So it names the two conditions, in the words `quietsNoRules` uses.
    public static let onCallNote =
        "You are on call. A snooze quiets only the rules you ticked that make a sound and do not run a Shortcut."
    /// The line that says switching on-call mode ended a snooze (O10).
    public static let endedByOnCall = "Snooze ended — you are on call"
    /// The line that says a snooze would do nothing, and what to do about it. It
    /// stands whether or not a snooze is running, so that one that does nothing
    /// says so.
    public static let quietsNoRules = "Snooze quiets no rules yet — tick “" + ruleSwitchLabel
        + "” on a rule that makes a sound and does not run a Shortcut"

    /// How long the line that says on-call mode ended a snooze stands: as long as
    /// a snooze can run (`SnoozeDuration.longest`), counted from when it ended,
    /// and not after the app is relaunched, since the moment is not saved. By
    /// then the snooze it reports would have run out whatever its length, so the
    /// line has nothing left to say and goes.
    ///
    /// The line is not shown, whatever the time, while a snooze runs (that one is
    /// the news), while on-call mode is off (it says "you are on call"), or when
    /// the moment is from before the mode was last switched on, so that switching
    /// it off and on again with no snooze to end does not bring back a notice for
    /// one that ended earlier. The core decides those, in `menu(...)`. What it
    /// cannot see is a snooze the user starts and ends after the moment, which
    /// leaves nothing in what it is given: the app clears the moment where it
    /// starts a snooze (Ruling 18, O10).
    public static let endedNoticeLifetime: TimeInterval = SnoozeDuration.longest

    /// The title of a duration in the Snooze submenu: "For 15 minutes", "For 30
    /// minutes", "For 1 hour", "For 2 hours".
    public static func durationTitle(_ duration: SnoozeDuration) -> String {
        switch duration {
        case .fifteenMinutes: return "For 15 minutes"
        case .thirtyMinutes: return "For 30 minutes"
        case .oneHour: return "For 1 hour"
        case .twoHours: return "For 2 hours"
        }
    }

    /// "Snoozed until 15:30 — quiets 3 of 5 rules". The 5 is the enabled rules
    /// that alert aloud and the 3 those a snooze may hold, so a rule that was
    /// never going to sound is in neither.
    ///
    /// - Parameter time: how a moment is shown, as the menu's other lines show
    ///   one ("15:30").
    public static func activeLine(endsAt: Date, quieting: Int, of alerting: Int, time: (Date) -> String) -> String {
        "\(activeStem) \(time(endsAt)) — quiets \(quieting) of \(alerting) \(alerting == 1 ? "rule" : "rules")"
    }

    /// "Still alerting: On-call mentions": the rules' names, three at most and
    /// then "and 2 more", in the order the names are given. nil when there are
    /// none, since a line with nothing after it says nothing.
    public static func stillAlertingLine(_ names: [String]) -> String? {
        guard !names.isEmpty else { return nil }
        let shown = names.prefix(namesShown)
        let more = names.count - shown.count
        return "\(stillAlertingStem): " + shown.joined(separator: ", ") + (more > 0 ? " and \(more) more" : "")
    }

    /// The name of each rule by its id, for `summaryLine`. Two rules that carry
    /// the same id, which a hand-written file can do, give the first one's name,
    /// as the first match wins everywhere else.
    public static func names(of rules: [Rule]) -> [UUID: String] {
        Dictionary(rules.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    }

    /// The menu's line for what was held, or nil when there is nothing to say.
    ///
    /// "6 matches held while snoozed: On-call mentions ×2, Team chatter ×4". The
    /// names are looked up in `names`, which is built from the current rules, and
    /// an id that is not there reads `ruleNotFound`. They are in alphabetical
    /// order and those not found are last, and after three the rest are counted:
    /// "A ×1, B ×2, C ×3 and 2 more". The count at the front is every match
    /// counted, whether or not its rule is named.
    ///
    /// A record that could not be read is said, whether or not anything could be
    /// counted from it.
    public static func summaryLine(_ summary: HeldSummary, names: [UUID: String]) -> String? {
        guard !summary.counts.isEmpty else {
            return summary.recordUnreadable ? unreadableSentence : nil
        }
        let entries = summary.counts
            .map { (name: names[$0.key], count: $0.value) }
            .sorted(by: isBefore)
        let shown = entries.prefix(namesShown).map { "\($0.name ?? ruleNotFound) ×\($0.count)" }
        let more = entries.count - shown.count
        let count = summary.total == 1 ? heldOneMatchStem : "\(summary.total) matches \(heldStem)"
        return count + ": " + shown.joined(separator: ", ")
            + (more > 0 ? " and \(more) more" : "")
            + (summary.recordUnreadable ? unreadableEnding : "")
    }

    // MARK: The menu

    /// What the status menu shows of a snooze, as the one value the app renders
    /// (M5 plan, Ruling 17, O8 to O10). The lines, their order and which are
    /// top-level items are decided and tested here, and the app adds each item as
    /// it is given, in order, and decides nothing.
    ///
    /// - Parameters:
    ///   - rules: the rules in effect, in the order they were written. What a
    ///     snooze quiets and what it does not are counted over the enabled rules
    ///     that alert aloud (`Rule.alertsAloud`), the quieted ones being those a
    ///     snooze may hold (`Rule.snoozeMayHold`), so a rule that is ticked and
    ///     ends in a Shortcut is among those still alerting, and a rule that was
    ///     never going to sound is in neither list. The names are the user's own.
    ///   - onCall: the on-call state, whether the mode is on and since when. The
    ///     submenu says so while it is on, and the line that says the mode ended a
    ///     snooze is shown only for a snooze that ended in the run of the mode that
    ///     is on now: `endedByOnCallAt` must not be before `since`, and a `since`
    ///     that could not be read ties it to nothing, so the line is not shown.
    ///   - snoozeEndsAt: `SnoozeController.endsAt`, nil while no snooze is
    ///     running.
    ///   - summary: `SnoozeController.summary`, which stands before, during and
    ///     after a snooze until the user dismisses it.
    ///   - endedByOnCallAt: when switching on-call mode on ended a snooze, nil if
    ///     it has not. The app notes the moment as it carries out
    ///     `OnCallSwitch.Effect.endSnooze`, which comes after `save`, so it is not
    ///     before `since`, and does not save it: it is a notice for this run. The
    ///     app also clears it where it starts a snooze, since the core is not told
    ///     of a snooze that starts and ends after the moment, and without that the
    ///     line would come back for it within the lifetime and say on-call mode
    ///     ended a snooze that the user chose to end or let run out. Switching the
    ///     mode off and on again needs no clearing: the new `since` is after it.
    ///   - now: the moment the menu is built.
    ///   - time: how a moment is shown, as the menu's other lines show one.
    public static func menu(rules: [Rule], onCall: OnCallState, snoozeEndsAt: Date?, summary: HeldSummary,
                            endedByOnCallAt: Date?, now: Date, time: (Date) -> String) -> SnoozeMenu {
        let alerting = rules.filter(\.alertsAloud)
        let quieted = alerting.filter(\.snoozeMayHold)
        let notQuieted = alerting.filter { !$0.snoozeMayHold }

        var submenu: [SnoozeMenu.SubmenuItem] = []
        if onCall.isOn { submenu.append(.line(onCallNote)) }
        submenu += SnoozeDuration.allCases.map { .start($0, title: durationTitle($0)) }
        if snoozeEndsAt != nil { submenu.append(.end(title: endTitle)) }

        var items: [SnoozeMenu.Item] = [.snooze(title: menuTitle, submenu: submenu)]
        if let end = snoozeEndsAt {
            items.append(.line(activeLine(endsAt: end, quieting: quieted.count, of: alerting.count, time: time)))
            if let still = stillAlertingLine(notQuieted.map(\.name)) { items.append(.line(still)) }
        } else if let ended = endedByOnCallAt, endedNoticeStands(endedAt: ended, onCall: onCall, now: now) {
            items.append(.line(endedByOnCall))
        }
        if quieted.isEmpty { items.append(.line(quietsNoRules)) }
        if let line = summaryLine(summary, names: names(of: rules)) {
            items.append(.line(line))
            items.append(.dismiss(title: dismissTitle, shown: summary))
        }
        return SnoozeMenu(items: items)
    }

    /// Whether the line that says on-call mode ended a snooze stands, while no
    /// snooze runs: the mode is on and since a time that is known, the snooze ended
    /// in that run of it and not before, and it ended no later than now and less
    /// than `endedNoticeLifetime` ago. A moment later than now is a clock that was
    /// set back, and says nothing.
    private static func endedNoticeStands(endedAt: Date, onCall: OnCallState, now: Date) -> Bool {
        guard let since = onCall.since, endedAt >= since else { return false }
        return endedAt <= now && now.timeIntervalSince(endedAt) < endedNoticeLifetime
    }

    private typealias Entry = (name: String?, count: Int)

    /// Named rules first, by name without regard to case, then by the name as
    /// written, then the larger count; rules that cannot be found after them, the
    /// larger count first. Two entries that this leaves level read alike, so the
    /// line is the same each time it is made.
    private static func isBefore(_ a: Entry, _ b: Entry) -> Bool {
        switch (a.name, b.name) {
        case (let x?, let y?):
            let (lx, ly) = (x.lowercased(), y.lowercased())
            if lx != ly { return lx < ly }
            if x != y { return x < y }
        case (_?, nil): return true
        case (nil, _?): return false
        case (nil, nil): break
        }
        return a.count > b.count
    }
}

/// The snooze's part of the status menu, in the order it is shown (M5 plan,
/// Ruling 17, O8 to O10), made by `SnoozeText.menu(...)`.
///
/// **Where it sits in the whole menu.** Top to bottom: the escalation section,
/// with Acknowledge first while anything is listed; the health line and its
/// cause; the setup nudge while a required step is outstanding; On Call and its
/// lines; then these `items`, in order; then the capture count, the Inspector,
/// the rules section, Settings and Quit. The app places them after the last of
/// the On Call lines and before the separator that comes ahead of the capture
/// count.
///
/// **What is top-level.** Every item here is. The harness reads the menu's
/// top-level items, and a line that must be opened to be read is where a missed
/// page hides, so the active line, the line of the rules still alerting, the
/// ended line, the line that says no rule is ticked, the summary line and Dismiss
/// are none of them in the submenu. The submenu holds the on-call line of O10,
/// the four durations and End Snooze, and nothing else.
///
/// **What it makes no sound for.** Showing a line or Dismiss makes none: the one
/// sound a snooze makes is the announcement `SnoozeController` owes when a snooze
/// runs out having held something.
public struct SnoozeMenu: Equatable, Sendable {
    /// A top-level item. A line is words that do nothing when chosen.
    public enum Item: Equatable, Sendable {
        /// The Snooze item, which opens `submenu`.
        case snooze(title: String, submenu: [SubmenuItem])
        /// A line of words.
        case line(String)
        /// The item that dismisses the summary beside it. `shown` is the summary
        /// that line was made from, which the app keeps from when it built the
        /// menu and hands to `SnoozeController.dismissSummary(shown:)`, so that a
        /// match held while the menu was open is not taken out unseen (Ruling 22).
        case dismiss(title: String, shown: HeldSummary)
    }

    /// An item of the Snooze submenu.
    public enum SubmenuItem: Equatable, Sendable {
        /// A line of words, which is all the on-call line is.
        case line(String)
        /// Starts a snooze of this length, replacing the one that runs.
        case start(SnoozeDuration, title: String)
        /// Ends the snooze that runs. Only while one does.
        case end(title: String)
    }

    /// The items, first to last.
    public let items: [Item]
}
