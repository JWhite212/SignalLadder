// Sources/NotificationCore/OnCallWatch.swift
import Foundation

/// The second half of the on-call alarm: when to open the check window and sound
/// one beep for a finding the health alarm cannot see (M5 plan, Rulings 9 and
/// 10, O5 part 2).
///
/// `HealthAlarmPlan` sounds for health. It cannot see that a rule was refused
/// (a sound file removed, a voice uninstalled by an update, a hand edit, a file
/// from a newer build), that no rule is enabled, that a Shortcut's name was not
/// found, or that SignalLadder may not start again after a restart, and each of
/// those means a page may not arrive. Read once, at switch-on, they would be
/// told by the slashed bell alone to a Mac that came up at 3am with its rules
/// off. So the app asks this whenever its inputs are read while on call: at
/// launch when on-call mode was restored, after every reload and every save, at
/// every health refresh, when it is switched on, and each time the login item's
/// status is read (Ruling 15), which is when the menu opens, when the app is
/// activated, when Settings is shown, after every request made through Settings'
/// model, which the login finding's button is one of, and when the check window
/// comes to the front or is opened by its menu item. Each of those asks with the
/// status it read, so that what stands here is never older than the last read.
///
/// Asking again with what has not changed does nothing: the answer is a function
/// of the findings and of what the last answer left standing, so a second ask in
/// the same breath, as the menu opening beside a health refresh makes, sounds and
/// opens nothing.
///
/// It keeps what stands, as kinds and counts and never a name. A finding that is
/// new, or whose count has risen, opens the window and sounds one beep, once. One
/// that goes, or whose count falls, is recorded and is silent, so that its return
/// sounds again. Findings that have not changed do nothing. Off call it returns
/// nothing and forgets everything, so switching on afterwards sounds for a
/// finding that is still standing.
///
/// Two findings open the window and do not beep, because a beep cannot be heard
/// through either: an output that is muted, and an Alert volume of zero. Unconfirmed
/// muting and the advisories are the user's to fix and are shown and not sounded,
/// and health is `HealthAlarmPlan`'s. It shares the health alarm's channel,
/// `NSSound.beep()`, and none of its state.
public enum OnCallWatch {
    public typealias Kind = OnCallCheck.Finding.Kind

    /// What stands, as the kinds of finding being watched and how many each
    /// counts. Never a name: a rule's name, an app's name and a Shortcut's name
    /// are all things a banner or a user wrote.
    public struct State: Equatable, Sendable {
        public var standing: [Kind: Int]

        public init(standing: [Kind: Int] = [:]) {
            self.standing = standing
        }
    }

    public struct Decision: Equatable, Sendable {
        /// Whether to open the check window.
        public let openWindow: Bool
        /// Whether to sound one beep.
        public let beep: Bool
        /// What stands now.
        public let state: State

        public init(openWindow: Bool, beep: Bool, state: State) {
            self.openWindow = openWindow
            self.beep = beep
            self.state = state
        }
    }

    /// The findings this watches. Health is the alarm's, and the rest are the
    /// user's to fix and are shown and not sounded.
    public static func isWatched(_ kind: Kind) -> Bool {
        switch kind {
        case .rulesNotInEffect, .rulesFileNotInEffect, .noRuleEnabled, .shortcutNotFound, .loginItemOff,
             .outputMuted, .beepsInaudible:
            return true
        case .health, .notVerifiedYet, .noSoundOrShortcut, .unconfirmedMuting, .focus, .sleep:
            return false
        }
    }

    /// Whether a watched finding is sounded for. A muted output and a zero Alert
    /// volume are not: a beep could not be heard through either.
    public static func isSounded(_ kind: Kind) -> Bool {
        switch kind {
        case .outputMuted, .beepsInaudible: return false
        default: return isWatched(kind)
        }
    }

    /// - Parameters:
    ///   - onCall: whether the app is on call now.
    ///   - findings: what `OnCallCheck` has just produced.
    ///   - previous: what stood at the last evaluation; empty after a launch, so
    ///     a finding already standing then sounds once.
    public static func decide(onCall: Bool, findings: [OnCallCheck.Finding], previous: State) -> Decision {
        guard onCall else {
            return Decision(openWindow: false, beep: false, state: State())
        }
        var standing: [Kind: Int] = [:]
        for finding in findings where isWatched(finding.kind) {
            standing[finding.kind] = finding.count ?? 1
        }
        let appeared = standing.filter { kind, count in count > (previous.standing[kind] ?? 0) }.keys
        return Decision(openWindow: !appeared.isEmpty,
                        beep: appeared.contains(where: isSounded),
                        state: State(standing: standing))
    }
}
