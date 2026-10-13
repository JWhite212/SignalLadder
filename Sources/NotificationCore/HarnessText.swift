// Sources/NotificationCore/HarnessText.swift
import Foundation

/// The two names the live-verification harness gives what it puts into the rules
/// file for a run (M5 plan, Task 9, Ruling 18).
///
/// `--snooze` and `--escalation` of `Scripts/verify-live.sh` each append one rule
/// to the rules file for as long as they run and take it out again: the marker
/// rule. It matches only the banners the harness posts under `markerTitle`, so a
/// real page is never counted as the marker's. The app says neither of these on
/// its own. While the rule is installed it shows the rule's name wherever it
/// names any rule, and while a marker banner is among the notifications it keeps
/// the Inspector lists its title, as it lists every captured banner's. The
/// harness's guards read the menu's lines that name the rule, so the name is
/// declared here, where `HarnessConstantsTests` holds it to the lines the app
/// builds from it, and the script reads it from this file, as it reads a window's
/// title.
///
/// Each constant is declared on one line as `public static let NAME = "TEXT"`,
/// the shape the harness's helper reads (Ruling 18). Both are plain words: the
/// script puts them into JSON, into AppleScript and into a shell's arguments.
public enum HarnessText {
    /// The marker rule's name. The menu says it in the summary line of what a
    /// snooze held ("1 match held while snoozed: SignalLadder harness marker ×1")
    /// and in the last-match line, and the app says it nowhere unless the harness
    /// has installed the rule. The harness's summary guard dismisses a held summary
    /// only when it is that one line, so a real match of the owner's is never
    /// dismissed with it.
    public static let markerRuleName = "SignalLadder harness marker"

    /// The title of the marker banners, and all the marker rule matches. The
    /// harness posts the marker and the banners of a burst under this title, each
    /// with a body of its own. The menu never shows it, since a notification's
    /// title is what it said and the menu never says that. The Inspector does
    /// list it, like the title of any captured banner, for as long as the banner
    /// is among the last 50 notifications the app keeps in memory.
    public static let markerTitle = "SignalLadder harness marker banner"
}
