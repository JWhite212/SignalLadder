// Sources/NotificationCore/AlertMenuText.swift
import Foundation

/// The menu's lines about alerts, worded here where they are tested.
///
/// Warnings come before the last match. A sound that could not play, or an
/// output that cannot be heard, is the most important thing the rules section
/// can say, and the menu is read from the top.
public enum AlertMenuText {
    public static let outputSilentWarning = "⚠︎ Sound output is muted or at zero volume — alerts will not be heard"

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
