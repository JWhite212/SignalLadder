// Sources/SignalLadder/PowerAssertion.swift
import Foundation

/// Keeps the Mac from idle-sleeping while an escalation still has a tier to
/// fire, and no longer (M4 plan, ruling 15). The reason to hold it is not App
/// Nap, which never delayed a timer in 720 measured fires: `.userInitiated`
/// also prevents idle system sleep, and a Mac asleep fires nothing. Whether it
/// does that on a Mac that can sleep is checked in Task 7.
@MainActor
final class PowerAssertion {
    private var activity: NSObjectProtocol?

    /// Held at most once, however often it is asked for.
    func begin() {
        guard activity == nil else { return }
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated],
                                                         reason: "An alert is still escalating")
    }

    func end() {
        guard let activity else { return }
        ProcessInfo.processInfo.endActivity(activity)
        self.activity = nil
    }
}
