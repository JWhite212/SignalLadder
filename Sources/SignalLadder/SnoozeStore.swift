// Sources/SignalLadder/SnoozeStore.swift
import Foundation
import NotificationCore

/// The snooze's two saved values, and the only code that reads or writes them
/// (M5 plan, Task 4, Ruling 12).
///
/// It reads what the preferences hold once, when the controller is made, and
/// writes whatever the controller hands it, each time it asks, so that a snooze
/// and what it held outlive a relaunch. What the two values are, what is read
/// of one that cannot be read, and what a saved value may hold (a date and whole
/// numbers keyed by a rule's id, and never a name, an app or any text) are
/// `SnoozeController`'s and `HeldSummary`'s, in the core, where they are tested.
/// This only carries them to and from the preferences. It holds no key of its
/// own and no word.
///
/// - `SnoozeController.untilKey`: the end of a snooze, as seconds since 1970 in
///   a real number. Absent is no snooze.
/// - `SnoozeController.heldKey`: what was held and not yet dismissed, as the one
///   dictionary `HeldSummary` documents. Absent is nothing held.
///
/// A value is handed back as the preferences give it, which may be anything,
/// since the file can be edited: the controller reads it defensively.
@MainActor
final class SnoozeStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// What the preferences hold for the end of a snooze, as they hold it.
    var storedUntil: Any? { defaults.object(forKey: SnoozeController.untilKey) }

    /// What the preferences hold for what was held, as they hold it.
    var storedHeld: Any? { defaults.object(forKey: SnoozeController.heldKey) }

    /// Writes `value` under `key`, or takes the key out when the value is nil,
    /// which is the controller's `Save`. The values it hands over are property
    /// lists, numbers and dictionaries of numbers, which is what the core's tests
    /// hold them to.
    func save(_ key: String, _ value: Any?) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
