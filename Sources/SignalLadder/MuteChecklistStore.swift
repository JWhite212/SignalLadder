// Sources/SignalLadder/MuteChecklistStore.swift
import Foundation
import NotificationCore

/// The one copy of the mute checklist, and the only code that saves it (M5
/// plan, Ruling 16).
///
/// It reads the saved list once, when it is made, and saves the whole list
/// each time a confirmation is set. Whatever shows the checklist or asks
/// whether an app is confirmed is given this instance and reads it here. A
/// second instance over the same key would hold its own copy, read once and
/// never told of a tick made through the first, and would go on reporting
/// "not confirmed" for an app the user had confirmed.
///
/// What the list means, how names are matched and what is stored (a digest,
/// never a name) are `MuteChecklist`'s, in the core, where they are tested.
/// This only carries the list to and from the preferences, so that a
/// confirmation outlives a relaunch.
@MainActor
final class MuteChecklistStore {
    private let defaults: UserDefaults

    /// The checklist as it stands now. Read it for each question; a copy kept
    /// from before a tick is stale.
    private(set) var checklist: MuteChecklist

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // A value that is absent, or is not a list of strings, reads as nothing
        // confirmed, which is the direction that shows the warning.
        checklist = MuteChecklist(stored: defaults.stringArray(forKey: MuteChecklist.storageKey) ?? [])
    }

    func setConfirmed(_ app: String, _ isConfirmed: Bool) {
        checklist.setConfirmed(app, isConfirmed)
        defaults.set(checklist.stored, forKey: MuteChecklist.storageKey)
    }
}
