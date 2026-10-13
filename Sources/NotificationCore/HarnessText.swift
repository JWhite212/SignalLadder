// Sources/NotificationCore/HarnessText.swift
import Foundation

/// The names, and the two ids, the live-verification harness gives what it puts into
/// the rules file for a run (M5 plan, Task 9, Ruling 18).
///
/// `--snooze` and `--escalation` of `Scripts/verify-live.sh` each put one rule
/// first in the rules file for as long as they run and take it out again: the
/// marker rule. It matches only the banners the harness posts under `markerTitle`,
/// so a real page is never counted as the marker's, and it is first so that no
/// rule of the owner's, a catch-all say, takes one of those banners before it
/// (the first enabled rule to match wins). The app says neither of these on
/// its own. While the rule is installed it shows the rule's name wherever it
/// names any rule, and while a marker banner is among the notifications it keeps
/// the Inspector lists its title, as it lists every captured banner's. The
/// harness's guards read the menu's lines that name the rule, so the name is
/// declared here, where `HarnessConstantsTests` holds it to the lines the app
/// builds from it, and the script reads it from this file, as it reads a window's
/// title.
///
/// Each constant is declared on one line as `public static let NAME = "TEXT"`,
/// the shape the harness's helper reads (Ruling 18). The names are plain words and
/// the ids are UUIDs: the script puts them into JSON, into AppleScript and into a
/// shell's arguments.
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

    /// The id of the marker rule `--escalation` installs. Each marker rule is written
    /// with an id that is the same in every run, so one left in the rules file by a run
    /// that was killed can be told from every rule of the owner's, which has an id of its
    /// own, and the harness will not add a second marker beside one that is there. The
    /// script reads the ids from this file and puts each into the rule it writes, and
    /// `HarnessConstantsTests` holds each to a UUID, the two apart, and the rules the
    /// script writes to the codec.
    public static let markerEscalationRuleID = "6F0B2A52-6C3F-4C2E-9D7A-0A1B2C3D4F02"

    /// The id of the marker rule `--snooze` installs. See `markerEscalationRuleID`.
    public static let markerSnoozeRuleID = "6F0B2A52-6C3F-4C2E-9D7A-0A1B2C3D4F01"
}
