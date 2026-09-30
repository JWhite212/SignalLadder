// Sources/SignalLadder/RunLoopEscalationScheduler.swift
import Foundation
import NotificationCore

/// The real clocks and timers an escalation runs on (M4 plan, ruling 4). Kept
/// out of the tested core on purpose: a real timer is what a test must never
/// wait on.
@MainActor
final class RunLoopEscalationScheduler: EscalationScheduler {
    private var timers: [EscalationTimerToken: Timer] = [:]

    func now() -> Date { Date() }

    /// Stops while the Mac sleeps and the wall clock does not, which is how a
    /// sleep is measured (ruling 14). Documented; first measured on a Mac
    /// that sleeps in Task 7.
    func awakeTime() -> TimeInterval { ProcessInfo.processInfo.systemUptime }

    func schedule(after seconds: TimeInterval, _ work: @escaping @MainActor () -> Void) -> EscalationTimerToken {
        let token = EscalationTimerToken()
        let timer = Timer(timeInterval: seconds, repeats: false) { [weak self] _ in
            // Run inside the timer's own callback, never through a hop to the
            // main actor (ruling 2): an invalidated timer then does not run,
            // and a running one finishes before an acknowledgement can start.
            // A timer on the main run loop fires on the main thread.
            MainActor.assumeIsolated {
                // Forgotten once fired: the coordinator cancels only tokens it
                // still holds, so nothing else would ever remove it.
                self?.timers[token] = nil
                work()
            }
        }
        // As the app-nap spike set it when it measured 3.5 ms of drift at
        // worst on a 30 s timer, through hours idle and locked.
        timer.tolerance = 0
        // Common modes, so a tier still fires while the menu is open.
        RunLoop.main.add(timer, forMode: .common)
        timers[token] = timer
        return token
    }

    func cancel(_ token: EscalationTimerToken) {
        timers.removeValue(forKey: token)?.invalidate()
    }
}
