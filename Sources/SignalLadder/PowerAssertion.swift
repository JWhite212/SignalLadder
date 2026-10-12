// Sources/SignalLadder/PowerAssertion.swift
import Foundation
import NotificationCore

/// A hold against the Mac idle-sleeping, which the app takes and lets go of on
/// instruction and decides nothing about. There are two, each its own instance
/// with its own activity, so that letting go of one never lets go of the other
/// (M5 plan, O7):
///
/// - An escalation's, held while one has a tier still to fire and no longer
///   (M4 plan, ruling 15). The reason to hold it is not App Nap, which never
///   delayed a timer in 720 measured fires: `.userInitiated` also prevents idle
///   system sleep, and a Mac asleep fires nothing.
/// - On-call mode's, held for as long as the mode is on, so that an escalation
///   ending does not release it. It is `.idleSystemSleepDisabled` alone: it
///   stops a Mac idle-sleeping and nothing else. A closed lid or a sleep chosen
///   by hand still sleeps the Mac, and the display is not held.
///
/// What each is called and what it holds against are `PowerHold`'s, in the
/// core, where they are tested: this class names no option and no reason of its
/// own. Whether either holds a Mac that can sleep awake has not been checked on
/// one.
@MainActor
final class PowerAssertion {
    private let hold: PowerHold
    private var activity: NSObjectProtocol?

    /// - Parameter hold: which of the two this is, and so what the system shows
    ///   for it and what it holds against.
    init(_ hold: PowerHold) {
        self.hold = hold
    }

    /// Whether the hold is held now. What the menu says of on-call mode's hold is
    /// said of this, and not of what the mode is meant to have done.
    var isHeld: Bool { activity != nil }

    /// Held at most once, however often it is asked for.
    func begin() {
        guard activity == nil else { return }
        activity = ProcessInfo.processInfo.beginActivity(options: hold.options, reason: hold.reason)
    }

    func end() {
        guard let activity else { return }
        ProcessInfo.processInfo.endActivity(activity)
        self.activity = nil
    }
}
