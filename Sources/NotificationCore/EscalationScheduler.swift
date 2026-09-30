// Sources/NotificationCore/EscalationScheduler.swift
import Foundation

/// The clocks and timers an escalation runs on, injected so that ladder timing
/// is proven by advancing a clock in a test, never by waiting on a real one
/// (M4 plan, ruling 4; §10: "injected clock").
///
/// Two clocks, because sleep is measured, not inferred (ruling 14): the wall
/// clock keeps going while the Mac sleeps, and the awake time stops. The
/// app's `RunLoopEscalationScheduler` supplies `ProcessInfo.systemUptime` for
/// the awake time, and real timers on the main run loop that run their work
/// inside their own callback (ruling 2). That the uptime stops during a sleep
/// is documented, not yet measured on a Mac that sleeps (Task 7).
@MainActor
public protocol EscalationScheduler: AnyObject {
    /// The wall clock.
    func now() -> Date
    /// Seconds the Mac has been awake, from any fixed point. Stops while it
    /// sleeps.
    func awakeTime() -> TimeInterval
    /// Runs `work` on the main actor after `seconds`, unless cancelled first.
    func schedule(after seconds: TimeInterval, _ work: @escaping @MainActor () -> Void) -> EscalationTimerToken
    func cancel(_ token: EscalationTimerToken)
}

/// Names one scheduled timer, to cancel it.
public struct EscalationTimerToken: Hashable, Sendable {
    public let id: UUID

    public init(id: UUID = UUID()) {
        self.id = id
    }
}
