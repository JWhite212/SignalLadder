// Sources/NotificationCore/EscalationPanelText.swift
import Foundation

/// The escalation panel's words, worded here where they are tested.
///
/// A line names the rule and the ladder's own state, never what arrived: the
/// panel is drawn over every app and every Space, in meetings and on shared
/// screens, a larger version of the surface M3d kept a spoken line out of
/// (M4 plan, ruling 17). Only the Inspector shows what arrived. A summary can
/// carry notification text, in a spoken outcome, and nothing here reads it.
///
/// The start time is there because one rule can have more than one escalation
/// listed, a match that comes when the first is not to be joined beginning its
/// own: two rows alike but for when they started can then be told apart.
///
/// A burst is one row. The count after the start time says how many matches
/// that row stands for, from 2: one escalation is one row however many matches
/// joined it, and the count is how the panel says more than one came (M5 plan,
/// Ruling 14). It is a number and not what any match said.
public enum EscalationPanelText {
    /// Heads the panel.
    public static let title = "SignalLadder: waiting for you to acknowledge"

    /// Each row's button.
    public static let acknowledge = "Acknowledge"

    /// Counts the rows the panel leaves off, when there are more than it
    /// shows, and says how to acknowledge them.
    public static func overflow(_ count: Int) -> String {
        "and \(count) more: acknowledge all from the menu, or press ⌃⌥⌘A"
    }

    /// "On-call mentions — since 10:42 — 7 matches — tier 3, repeat 3 of 20". The
    /// count is left out at 1, so a line for an escalation no match has joined
    /// reads as it always did, and "1 match" is never said (`BurstText.matches`).
    ///
    /// - Parameter time: how a moment is shown, e.g. "10:42", as the menu
    ///   shows its own.
    public static func line(for summary: EscalationSummary, time: (Date) -> String) -> String {
        let matches = BurstText.matches(summary.matchCount).map { " — \($0)" } ?? ""
        return "\(summary.ruleName) — \(since)\(time(summary.startedAt))\(matches) — \(state(of: summary))"
    }

    private static let since = "since "
    private static let missed = "missed while asleep"
    private static let stopped = "no longer repeating"
    private static let shortcutFailed = "its Shortcut failed"
    private static let repeatWord = "repeat "
    private static func tier(_ number: Int) -> String { "tier \(number)" }

    // MARK: - A row, in parts

    /// What the panel draws for one escalation since 1.2, where a row is a block
    /// in its tier's colour and not one line of text (M7 plan, Stage 3).
    ///
    /// It says the same things as `line(for:time:)` and nothing more: the rule's
    /// name, when it began, how many matches, the tier and the repeats, and the
    /// three endings. So it too holds nothing that arrived (M4 plan, Ruling 17).
    /// The line itself is kept as `line`, which is what VoiceOver is given.
    public struct Row: Equatable, Sendable {
        /// What stands at the row's leading edge and decides how it is drawn.
        public enum Mark: Equatable, Sendable {
            /// An escalation at this tier: its number, large, on the tier's colour.
            case tier(Int)
            /// One whose alert did not reach the user as the ladder meant: its
            /// Shortcut failed, or the Mac slept through it. Drawn with no
            /// colour, so that it is never taken for a tier.
            case fault
        }

        /// A piece of the line under the name.
        public enum Part: Equatable, Sendable {
            case words(String)
            /// A time or a count, drawn in fixed-width figures so that a number
            /// changing in place does not move what is beside it.
            case figure(String)
        }

        public let name: String
        public let detail: [Part]
        /// The whole line, as `line(for:time:)` gives it.
        public let line: String
        public let mark: Mark

        /// The detail as one run of text.
        public var detailText: String {
            detail.map { part -> String in
                switch part {
                case .words(let text), .figure(let text): return text
                }
            }.joined()
        }
    }

    /// The row for a summary: "On-call mentions", then "since 10:42 — 7 matches —
    /// repeat 03/20" on tier 3's colour. A row whose Shortcut failed says its
    /// tier in words, since it has no numeral: "since 10:42 — tier 4, repeat
    /// 20/20 — its Shortcut failed".
    public static func row(for summary: EscalationSummary, time: (Date) -> String) -> Row {
        var detail: [Row.Part] = [.words(since), .figure(time(summary.startedAt))]
        if let matches = BurstText.matches(summary.matchCount) {
            detail.append(.words(" — \(matches)"))
        }
        let mark: Row.Mark
        switch summary.status {
        case .missedWhileAsleep:
            mark = .fault
            detail.append(.words(" — \(missed)"))
        case .acknowledged:
            // Never listed, so never on the panel; here for the switch.
            mark = .tier(summary.tierReached)
        case .live, .capped:
            var failed = false
            if case .shortcutFailed = summary.final { failed = true }
            mark = failed ? .fault : .tier(summary.tierReached)
            if failed {
                detail.append(.words(" — \(tier(summary.tierReached))"))
            }
            if summary.repeatCount > 0 {
                detail.append(.words((failed ? ", " : " — ") + repeatWord))
                detail.append(.figure(repeatFigure(summary.repeatCount, of: summary.repeatCap)))
            }
            if case .capped = summary.status {
                detail.append(.words((failed || summary.repeatCount > 0 ? ", " : " — ") + stopped))
            }
            if failed {
                detail.append(.words(" — \(shortcutFailed)"))
            }
        }
        return Row(name: summary.ruleName, detail: detail, line: line(for: summary, time: time), mark: mark)
    }

    /// "03/20", or "3" with no limit. Both numbers are as wide as the limit and
    /// at least two figures, so the count does not grow wider as it passes 9.
    static func repeatFigure(_ count: Int, of cap: Int?) -> String {
        guard let cap else { return "\(count)" }
        let width = max(2, "\(cap)".count)
        func padded(_ number: Int) -> String {
            let text = "\(number)"
            return String(repeating: "0", count: max(0, width - text.count)) + text
        }
        return "\(padded(count))/\(padded(cap))"
    }

    private static func state(of summary: EscalationSummary) -> String {
        switch summary.status {
        case .missedWhileAsleep:
            // Reached only from a measured sleep (ruling 14), so it needs no
            // hedged second wording. A Shortcut that failed before the sleep
            // is on the menu and in the Inspector, not here: the line says
            // only what is still to do, which is to see it.
            return missed
        case .acknowledged:
            // Never listed, so never on the panel; here for the switch.
            return "acknowledged"
        case .live, .capped:
            var parts = [tier(summary.tierReached)]
            if summary.repeatCount > 0 {
                parts.append(repeatWord + summary.repeatProgress)
            }
            if case .capped = summary.status {
                parts.append(stopped)
            }
            if case .shortcutFailed = summary.final {
                // A failure to page someone must be seen where the alert is,
                // not only in the Inspector. The reason stays there. "Failed"
                // and not "did not run": one that started and then stopped
                // with an error is reported the same way.
                parts.append(shortcutFailed)
            }
            return parts.joined(separator: ", ")
        }
    }
}
