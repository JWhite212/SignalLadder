// Sources/NotificationCore/PowerHold.swift
import Foundation

/// The app's two holds against the Mac idle-sleeping: what each is called in
/// what the system prints, and what each holds against (M5 plan, O7, Ruling 10).
///
/// Which reason goes with which options is a decision, so it is made here and
/// tested, and the app target only makes a hold from the case it is given. A
/// hold that took the other's reason would be listed by `pmset -g assertions`
/// under words that say the wrong thing, and one that held the display as well
/// would keep a Mac's screen lit for as long as on-call mode was on.
public enum PowerHold: CaseIterable, Equatable, Sendable {
    /// Taken while an escalation still has a tier to fire, and let go of when
    /// none has (M4 plan, Ruling 15).
    case escalation
    /// Taken for as long as on-call mode is on, so that an escalation ending
    /// does not release it.
    case onCall

    /// What the system shows for the hold.
    public var reason: String {
        switch self {
        case .escalation: return PowerHoldText.escalationReason
        case .onCall: return PowerHoldText.onCallReason
        }
    }

    /// What the hold holds against. On-call mode's is idle system sleep and
    /// nothing else: the display is not held, and a closed lid or a sleep
    /// chosen by hand still sleeps the Mac.
    public var options: ProcessInfo.ActivityOptions {
        switch self {
        case .escalation: return [.userInitiated]
        case .onCall: return [.idleSystemSleepDisabled]
        }
    }
}
