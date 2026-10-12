// Sources/SignalLadder/SetupProgressStore.swift
import Foundation
import NotificationCore

/// The one copy of what the first run remembers, and the only code that reads or writes it
/// (M5 plan, Task 8, Ruling 16).
///
/// It reads the preferences' value for `SetupProgress.storageKey` once, when it is made,
/// and saves the whole list each time something is recorded, as `MuteChecklistStore` does
/// its key, so that the guide's answers outlive a relaunch. Whatever asks what has been
/// recorded is given this instance and reads `progress` here: a second instance over the
/// same key would hold a copy read once and never told of a record made through the first,
/// and the launch decision, the nudge and Settings' line would come to disagree with the
/// guide. **Nothing else writes the key** (`SetupWiringTests`).
///
/// What a value that is not a list of strings comes to, which tokens there are, how an
/// unknown one is kept and what a record of a dismissal after a finish comes to are
/// `SetupProgress`'s, in the core, where they are tested. This only carries the list to
/// and from the preferences. What it holds is a list of short fixed words: never a
/// notification's text, an app's name or a rule's name.
@MainActor
final class SetupProgressStore {
    private let defaults: UserDefaults

    /// What has been recorded, as it stands now. Read it for each question; a copy kept
    /// from before a record is stale.
    private(set) var progress: SetupProgress

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // The value as the preferences give it, which may be anything; the core says what
        // it comes to.
        progress = SetupProgress(storedValue: defaults.object(forKey: SetupProgress.storageKey))
    }

    /// Records something and saves the list, in the one place it is written. `change` is
    /// one of `SetupProgress`'s own recording methods, so which tokens exist and what
    /// recording one comes to are the core's. The list is saved whether or not the record
    /// changed it, as the mute checklist is, which also replaces a value that was not a
    /// list.
    func record(_ change: (inout SetupProgress) -> Void) {
        change(&progress)
        defaults.set(progress.stored, forKey: SetupProgress.storageKey)
    }
}
