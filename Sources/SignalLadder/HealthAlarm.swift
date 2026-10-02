// Sources/SignalLadder/HealthAlarm.swift
import AppKit
import UserNotifications
import NotificationCore

/// Reports failure through channels chosen so no single fault silences them all.
///
/// Three channels: the menu-bar glyph (Task 5, pure AppKit, always visible),
/// an audible alert (pure AppKit), and a system notification (only when
/// delivery is confirmed working).
///
/// This matters more than it appears. The canary posts through
/// UNUserNotificationCenter — so if the alarm also went through
/// UNUserNotificationCenter, revoking notification permission would break the
/// canary AND silence the alarm about it, in one step. Channels 1 and 2
/// therefore depend on neither the notification system nor Accessibility.
///
/// When to beep, and whether to post the banner, is `HealthAlarmPlan`'s to
/// decide and this only carries it out: off call once for each change into an
/// alarming state, as ever, and on call again at each interval while a fault
/// stands.
final class HealthAlarm {
    /// What the plan remembers between reports. Read by whatever must agree with
    /// the beep about capture that has stayed unverified.
    private(set) var state = HealthAlarmPlan.State()

    /// - Parameters:
    ///   - deliveryHealthy: whether our own notifications can actually be
    ///     displayed. Channel 3 is skipped when false, because it is useless
    ///     precisely when delivery is the problem.
    ///   - onCall: whether on-call mode is on now.
    func report(_ health: CaptureHealth, deliveryHealthy: Bool, onCall: Bool, now: Date = Date()) {
        let decision = HealthAlarmPlan.decide(health: health, deliveryHealthy: deliveryHealthy,
                                              onCall: onCall, now: now, state: state)
        state = decision.state
        guard decision.beep else { return }

        // Channel 2 — audible, via AppKit only. Depends on neither the
        // Accessibility API nor the notification system, so it survives a
        // fault in either. (Channel 1 is the menu-bar glyph, always visible,
        // rebuilt on open in Task 5.)
        NSSound.beep()

        // Channel 3 — richer and clickable, but useless when delivery is the
        // fault, so only used when delivery is confirmed working, and only for
        // a change of health, never for a repeat of the beep.
        guard decision.postBanner else { return }
        let causes: [HealthCause]
        switch health {
        case .blind(let c), .degraded(let c): causes = c
        case .verified, .unknown: return
        }
        let content = UNMutableNotificationContent()
        // Shared with the capture path, which must recognise this banner as
        // ours when it comes back round. See SelfNotification.
        content.title = health.isBlindState
            ? SelfNotification.blindTitle
            : SelfNotification.degradedTitle
        content.body = causes.first?.advice ?? SelfNotification.fallbackBody
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "signalladder.health", content: content, trigger: nil)
        )
    }

    /// The Mac woke: the plan's two-minute bound for capture that is not
    /// verified starts now.
    func macWoke(at now: Date = Date()) {
        state = state.recordingWake(at: now)
    }

    /// Forget everything, as the switch to on-call mode does, so that a fault
    /// already standing sounds again for someone who has just said they are on
    /// call.
    func reset() {
        state = HealthAlarmPlan.State()
    }
}

private extension CaptureHealth {
    var isBlindState: Bool {
        if case .blind = self { return true }
        return false
    }
}
