// Sources/NotificationCore/SettingsText.swift
import Foundation

/// The words of the Settings window (M5 plan, Ruling 18, Task 6).
///
/// It holds the menu's title for the window, what the window says of Launch at
/// login, and the version line. The window's other labels come with the window.
/// The view shows what is made here and types no word of its own, so nothing in
/// the window can say more than the app has read.
public enum SettingsText {
    // MARK: - The menu item

    /// The status menu's item that opens the window, and the main menu's, which
    /// ⌘, also reaches. The harness reads it from this file, so it stays on one
    /// line as `public static let NAME = "TEXT"` (Ruling 18).
    public static let menuTitle = "Settings…"

    // MARK: - Launch at login

    /// The label of the switch.
    public static let launchAtLoginSwitch = "Launch at login"
    /// Under the switch while the system says the item is enabled, and the only
    /// sentence that says it is: every other state is said in words that do not.
    public static let onSentence = "macOS reports that SignalLadder is set to start when you log in."
    /// Under the switch while it is not enabled and can be switched on. It says
    /// what the status says and no more, and nothing of an entry added to Login
    /// Items by hand: such an entry reads enabled on macOS 26.7.1 (measured on
    /// 2026-10-05; not seen on macOS 14 or 15), where it is shown as on like any
    /// enabled item (Ruling 15).
    public static let offSentence = "macOS does not report SignalLadder as set to start when you log in."
    /// The same, for a user who had switched it on: the system does not show it
    /// enabled, and the app does not switch it back on itself.
    public static let offButWantedSentence = "You switched this on, but macOS does not report it as enabled. SignalLadder does not switch it back on by itself."
    /// Under the switch while the status says it needs approval, which is where a
    /// switch turned off in System Settings reads, and where a first request
    /// waiting for the user reads too.
    public static let switchedOffSentence = "Launch at login is switched off in System Settings, or is waiting for your approval there."

    /// The sentence under the switch for a state.
    public static func launchAtLoginSentence(for state: LaunchAtLogin.State) -> String {
        switch state {
        case .on: return onSentence
        case .off(let wanted): return wanted ? offButWantedSentence : offSentence
        case .switchedOffInSystemSettings: return switchedOffSentence
        case .unavailable(let why): return LaunchAtLoginText.reason(for: why)
        }
    }

    /// A button beside the switch, with what it does and its words.
    public struct LoginButton: Equatable, Sendable {
        public let action: LaunchAtLogin.Action
        public let label: String
    }

    /// The buttons beside the switch for a state, in the order they are shown,
    /// which are the system's two for an item it has switched off and none
    /// otherwise.
    public static func launchAtLoginButtons(for state: LaunchAtLogin.State) -> [LoginButton] {
        LaunchAtLogin.settingsActions(for: state).map {
            LoginButton(action: $0, label: LaunchAtLoginText.label(for: $0))
        }
    }

    // MARK: - The version line

    /// Every version line begins with this and then names the version, or says it
    /// was not recorded.
    public static let versionStem = "Version"
    /// What stands where the release number would, when the bundle has none.
    public static let versionNotRecorded = "not recorded"
    /// The word before a build number that has no release number beside it.
    public static let buildWord = "build"
    /// Said after the commit of a build whose stamp says that files git tracks
    /// had changes that were not committed.
    public static let localChanges = "with local changes"
    /// The whole sentence for a build with no commit, which is what `swift run`
    /// makes and a source archive has: there is no stamp to read.
    public static let commitNotRecorded = "The commit it was built from was not recorded."
    /// The sentence for a build that has a commit and no date the app could read.
    public static let dateNotRecorded = "The date it was built was not recorded."

    /// The line at the foot of Settings that says which build is running, so a
    /// stale copy can be told from a new one (O12).
    ///
    /// - "Version 0.1.0 (1), built from d5937c0 on 2 Oct 2026"
    /// - "Version 0.1.0 (1), built from d5937c0 with local changes on 2 Oct 2026"
    /// - "Version 0.1.0 (1). The commit it was built from was not recorded."
    ///
    /// **Each part is said only when it was read.** With a commit and no date
    /// that could be read, the commit is named and the date is said not to be
    /// recorded; with a date and no commit, the date is named and the commit is
    /// said not to be. With neither, the line is the third above. "With local
    /// changes" follows a commit and is said only when the stamp says it, and a
    /// build with no commit says nothing about changes. Its absence is no claim
    /// that the build is exactly that commit: a stamp that says nothing about
    /// changes reads the same as one that says there were none, and a new file
    /// git did not yet track is not counted by the stamp at all.
    ///
    /// A bundle with no release number reads "Version not recorded", and one with
    /// a build number and no release number reads "Version not recorded (build
    /// 1)"; one with a release number and no build number reads "Version 0.1.0".
    /// So every line names the version or says it was not recorded, and no line
    /// is ever "nil".
    ///
    /// - Parameter date: how the build's date is shown, in the user's locale.
    ///   `dateFormatter(locale:timeZone:)` makes the one the app uses. It is asked
    ///   only when there is a date.
    public static func version(_ info: BuildInfo, date: (Date) -> String) -> String {
        var line = "\(versionStem) \(info.version ?? versionNotRecorded)"
        if let number = info.buildNumber {
            line += info.version == nil ? " (\(buildWord) \(number))" : " (\(number))"
        }

        var built = ""
        if let commit = info.commit {
            built = "built from \(commit)"
            if info.modified == true { built += " \(localChanges)" }
            if let when = info.date { built += " on \(date(when))" }
        } else if let when = info.date {
            built = "built on \(date(when))"
        }
        if !built.isEmpty { line += ", \(built)" }

        if info.commit == nil {
            line += ". \(commitNotRecorded)"
        } else if info.date == nil {
            line += ". \(dateNotRecorded)"
        }
        return line
    }

    /// How the build's date is shown: the locale's own medium date, which is
    /// "2 Oct 2026" in British English and "Oct 2, 2026" in American, with no
    /// time. The locale and the time zone are passed in, so a test fixes both and
    /// the app passes the user's.
    public static func dateFormatter(locale: Locale, timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }
}
