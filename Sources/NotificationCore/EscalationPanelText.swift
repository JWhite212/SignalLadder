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
        return "\(summary.ruleName) — since \(time(summary.startedAt))\(matches) — \(state(of: summary))"
    }

    private static func state(of summary: EscalationSummary) -> String {
        switch summary.status {
        case .missedWhileAsleep:
            // Reached only from a measured sleep (ruling 14), so it needs no
            // hedged second wording. A Shortcut that failed before the sleep
            // is on the menu and in the Inspector, not here: the line says
            // only what is still to do, which is to see it.
            return "missed while asleep"
        case .acknowledged:
            // Never listed, so never on the panel; here for the switch.
            return "acknowledged"
        case .live, .capped:
            var parts = ["tier \(summary.tierReached)"]
            if summary.repeatCount > 0 {
                let cap = summary.repeatCap.map { " of \($0)" } ?? ""
                parts.append("repeat \(summary.repeatCount)\(cap)")
            }
            if case .capped = summary.status {
                parts.append("no longer repeating")
            }
            if case .shortcutFailed = summary.final {
                // A failure to page someone must be seen where the alert is,
                // not only in the Inspector. The reason stays there. "Failed"
                // and not "did not run": one that started and then stopped
                // with an error is reported the same way.
                parts.append("its Shortcut failed")
            }
            return parts.joined(separator: ", ")
        }
    }
}
