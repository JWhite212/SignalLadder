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
final class HealthAlarm {
    private var lastReported: CaptureHealth?

    /// - Parameter deliveryHealthy: whether our own notifications can actually
    ///   be displayed. Channel 3 is skipped when false, because it is useless
    ///   precisely when delivery is the problem.
    func report(_ health: CaptureHealth, deliveryHealthy: Bool) {
        guard health != lastReported else { return }   // do not nag
        lastReported = health
        guard health.isAlarming else { return }

        let causes: [HealthCause]
        switch health {
        case .blind(let c), .degraded(let c): causes = c
        case .verified, .unknown: return
        }

        // Channel 2 — audible, via AppKit only. Depends on neither the
        // Accessibility API nor the notification system, so it survives a
        // fault in either. (Channel 1 is the menu-bar glyph, always visible,
        // rebuilt on open in Task 5.)
        NSSound.beep()

        // Channel 3 — richer and clickable, but useless when delivery is the
        // fault, so only used when delivery is confirmed working.
        guard deliveryHealthy else { return }
        let content = UNMutableNotificationContent()
        content.title = health.isBlindState ? "SignalLadder is not capturing" : "SignalLadder cannot verify itself"
        content.body = causes.first?.advice ?? "Open the menu for details."
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "signalladder.health", content: content, trigger: nil)
        )
    }
}

private extension CaptureHealth {
    var isBlindState: Bool {
        if case .blind = self { return true }
        return false
    }
}
