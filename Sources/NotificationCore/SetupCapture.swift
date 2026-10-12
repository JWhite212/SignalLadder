// Sources/NotificationCore/SetupCapture.swift
import Foundation

/// What the first run reads of the banners captured so far, and how an app the user picked
/// leads back to the banner it was read from (M5 plan, Task 8, Ruling 10, Ruling 16).
///
/// The first rule's step offers app names to choose from, and never a title or a body
/// (`SetupFacts.capturedAppNames`). "Make a Rule from This…" then needs a notification, and
/// the rule editor takes an entry (`RuleEditorWindowController.show(makingRuleFrom:)`), so
/// the name has to be mapped back to one. Which entry that is, and how names are compared,
/// are decisions, so they are made here and tested, and the app target, which has no tests,
/// carries them out.
///
/// Every function reads **`entries` as `CaptureRingBuffer.entries` gives them, newest
/// first.** The buffer holds banners of other apps only: the self-test and SignalLadder's
/// own notifications are dropped before a banner is recorded (`CapturePipeline.process`).
/// Nothing here keeps an entry, reads a title or a body, or stores anything.
public enum SetupCapture {
    /// Whether anything has been captured: whether there is an entry. The first rule's step
    /// shows the practice line while nothing has arrived, and is made from a real capture
    /// once something has.
    public static func anythingCaptured(in entries: [InspectorEntry]) -> Bool {
        !entries.isEmpty
    }

    /// The app name of each entry, newest first, as the rules read it
    /// (`CapturedNotification.value(of:)`, `Field.app`), so that the name the step lists is the
    /// one a rule made from the entry will match. **App names only.** It repeats a name
    /// that several entries share, and includes one that is blank: the step lists each app
    /// once, in the order first seen, and none that is blank (`SetupText.StepWords.apps`), so
    /// the spelling it shows is the newest entry's. A banner that gave no app name is
    /// therefore no choice: where every name is blank the step lists none and offers no
    /// "Make a Rule from This…", which would have no entry to find, and says where the rule
    /// is made instead (`SetupText.bannersWithoutNames`).
    public static func appNames(in entries: [InspectorEntry]) -> [String] {
        entries.map { $0.captured.value(of: .app) }
    }

    /// The newest entry that `name` was read from, or nil when there is none: the entry
    /// "Make a Rule from This…" makes the rule from, for the app the user picked.
    ///
    /// Names are compared as rules and the mute checklist compare them, ignoring case,
    /// accents and surrounding spaces (`MuteWalkthrough.key`), so the name the step showed,
    /// which is one spelling of an app, finds the entry whatever spelling that entry has. A
    /// blank name finds nothing, as the step lists none. nil is a real answer, not only a
    /// missing one: the buffer holds a fixed number of entries, and the newest of an app can
    /// have gone by the time the user presses the button.
    public static func newestEntry(forApp name: String, in entries: [InspectorEntry]) -> InspectorEntry? {
        let key = MuteWalkthrough.key(name)
        guard !key.isEmpty else { return nil }
        return entries.first { MuteWalkthrough.key($0.captured.value(of: .app)) == key }
    }
}
