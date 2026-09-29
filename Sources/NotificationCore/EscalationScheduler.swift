// Sources/NotificationCore/EscalationScheduler.swift
import Foundation

/// The clocks and timers an escalation runs on, injected so that ladder timing
/// is proven by advancing a clock in a test, never by waiting on a real one
/// (M4 plan, ruling 4; §10: "injected clock").
///
/// Two clocks, because sleep is measured, not inferred (ruling 14): the wall
/// clock keeps going while the Mac sleeps, and the awake time stops. In the
/// app the awake time is `ProcessInfo.systemUptime`, and the timers are real
/// `Timer`s on the main run loop.
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
