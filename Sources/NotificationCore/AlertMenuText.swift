// Sources/NotificationCore/AlertMenuText.swift
import Foundation

/// The menu's lines about alerts, worded here where they are tested.
///
/// Warnings come before the last match. A sound that could not play, or an
/// output that cannot be heard, is the most important thing the rules section
/// can say, and the menu is read from the top.
public enum AlertMenuText {
    public static let outputSilentWarning = "⚠︎ Sound output is muted or at zero volume — alerts will not be heard"

    /// The menu's lines about escalations: a Shortcut that did not run first,
    /// since it is the one alert that may have been meant to reach someone
    /// away from the Mac, then how many are escalating and how many were
    /// missed while asleep. Never what arrived (ruling 17, extended to the
    /// menu, which already held to it for speech).
    ///
    /// - Parameter listed: the escalations the coordinator lists.
    public static func escalationLines(listed: [EscalationSummary],
                                       shortcutFailure: CapturePipeline.ShortcutFailure?,
                                       time: (Date) -> String) -> [String] {
        var lines: [String] = []
        if let failure = shortcutFailure {
            lines.append("⚠︎ \(failure.ruleName) at \(time(failure.at)): \(failure.reason)")
        }
        let escalating = listed.filter(\.status.isEscalating).count
        if escalating > 0 {
            lines.append("\(escalating) alert\(escalating == 1 ? "" : "s") escalating")
        }
        let missed = listed.filter(\.status.isUnseenMiss).count
        if missed > 0 {
            lines.append("\(missed) alert\(missed == 1 ? "" : "s") missed while asleep")
        }
        return lines
    }

    /// The menu item that acknowledges every listed escalation, as the hotkey
    /// does.
    public static func acknowledgeTitle(listed: Int) -> String {
        listed == 1 ? "Acknowledge" : "Acknowledge All (\(listed))"
    }

    /// Asked before quitting while anything is listed: quitting ends every
    /// escalation, and a Shortcut not yet run is never run. With only missed
    /// ones listed nothing is left to sound or run, and the detail says what
    /// quitting does lose instead.
    ///
    /// - Parameters:
    ///   - escalating: listed and still escalating, capped or not.
    ///   - missed: missed while asleep and not yet seen.
    public static func quitWarning(escalating: Int, missed: Int) -> (message: String, detail: String) {
        let listed = escalating + missed
        let alerts = listed == 1 ? "1 alert is" : "\(listed) alerts are"
        let detail = escalating > 0
            ? "Quitting stops every alert still escalating. Nothing more will sound or show, and a Shortcut not yet run will not run."
            : "Nothing is escalating now. Quitting forgets the \(missed == 1 ? "alert" : "alerts") missed while the Mac was asleep, and the menu will not list \(missed == 1 ? "it" : "them") again."
        return ("\(alerts) still waiting to be acknowledged. Quit anyway?", detail)
    }

    /// - Parameters:
    ///   - anyRulePlaysSound: whether an enabled rule has a sound. The output
    ///     warning is noise without one: silence is exactly what a user with
    ///     no sounding rules has chosen.
    ///   - outputSilent: whether the default output device reports itself
    ///     muted or at zero volume right now.
    ///   - time: how a moment is shown, e.g. "14:02".
    public static func lines(lastMatch: CapturePipeline.LastMatch?,
                             unresolvedFailure: CapturePipeline.LastMatch?,
                             anyRulePlaysSound: Bool,
                             outputSilent: Bool,
                             time: (Date) -> String) -> [String] {
        var lines: [String] = []

        // Said once. When the failure is also the last match, the last-match
        // line already carries it.
        if let failure = unresolvedFailure, failure != lastMatch {
            lines.append("⚠︎ \(failure.ruleName) at \(time(failure.at)): \(InspectorRowText.alert(failure.alert))")
        }
        if anyRulePlaysSound && outputSilent {
            lines.append(outputSilentWarning)
        }
        if let last = lastMatch {
            let warning = last.alert.needsAttention ? "⚠︎ " : ""
            lines.append("\(warning)Last match: \(last.ruleName) at \(time(last.at)) — \(InspectorRowText.alert(last.alert))")
        }
        return lines
    }
}
