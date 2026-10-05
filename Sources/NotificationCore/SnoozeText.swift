// Sources/NotificationCore/SnoozeText.swift
import Foundation

/// The words of a snooze (M5 plan, Ruling 18, Task 4).
///
/// So far it holds what the held summary says. The menu's titles and its other
/// lines come with the menu. The app shows what is made here and types no word
/// of its own, so nothing in the menu can say more than the app has read.
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

    /// How many rules a summary line names before it says how many more there are.
    public static let namesShown = 3

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
