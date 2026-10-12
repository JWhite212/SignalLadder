// Sources/SignalLadder/OnCallStore.swift
import Foundation
import NotificationCore

/// The one copy of the on-call state, and the only code that saves it (M5 plan,
/// Ruling 7).
///
/// It reads the saved date when it is made, which is before capture starts, so
/// that the first schedule of self-tests is the right one, and it writes the
/// date, or takes it out, each time the state is set, so that on-call mode
/// outlives a relaunch. Nothing in the app makes it start again after a quit or
/// a restart: a saved date keeps the mode and covers nobody while the app is not
/// running.
///
/// What a stored value means, which values are read as on with no time known,
/// and what saving a state does to the key are `OnCallState`'s, in the core,
/// where they are tested. This only carries the date to and from the
/// preferences.
@MainActor
final class OnCallStore {
    private let defaults: UserDefaults

    /// The state as it stands now. Read it for each question; a copy kept from
    /// before a switch is stale.
    private(set) var state: OnCallState

    /// - Parameter now: the moment a saved date is read against, so that one
    ///   from the future reads as since now.
    init(defaults: UserDefaults = .standard, now: Date = Date()) {
        self.defaults = defaults
        state = OnCallState(stored: defaults.object(forKey: OnCallState.storageKey), now: now)
    }

    func set(_ newState: OnCallState) {
        state = newState
        switch newState.write {
        case .remove: defaults.removeObject(forKey: OnCallState.storageKey)
        case .set(let seconds): defaults.set(seconds, forKey: OnCallState.storageKey)
        case .keep: break
        }
    }
}
