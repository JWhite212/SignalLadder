// Sources/NotificationCore/PowerHoldText.swift
import Foundation

/// What each of the app's two holds against idle sleep is called (M5 plan,
/// Ruling 18, O7).
///
/// `pmset -g assertions` prints a hold's reason beside the app's name, so a
/// person looking at why a Mac did not sleep, and the live check of the hold,
/// can read which of the two it was: one is taken while an escalation still has
/// a tier to fire, and one for as long as on-call mode is on. The two are
/// separate holds, each with its own reason, and the reasons are not alike. The
/// app target passes each to the hold it makes and holds no words of its own
/// for them.
public enum PowerHoldText {
    /// The hold an escalation takes while a tier is still to fire. These are the
    /// words it had before the second hold existed, and are unchanged.
    public static let escalationReason = "An alert is still escalating"
    /// The hold on-call mode takes, for as long as the mode is on.
    public static let onCallReason = "On-call mode is on"
}
