import Foundation

/// Why the pipeline might not be working, ordered by how actionable it is.
///
/// The split between delivery and capture matters more than it looks. If the
/// banner was never displayed, the Accessibility layer had nothing to see and
/// is not at fault — diagnosing that as "capture broken" sends the user to fix
/// the wrong thing, and would have them re-granting Accessibility to cure a
/// muted notification setting.
public enum HealthCause: Equatable, Sendable {
    // Delivery — the banner never appeared, so capture was never exercised.
    case notificationPermissionDenied
    case notificationsSuppressed      // alert style None, or a Focus/DND

    /// One self-test failed. Not yet evidence of blindness — a Focus, a
    /// transient system hiccup, or a wake from sleep all produce a single
    /// failure on a healthy app.
    case selfTestInconclusive

    /// A self-test failed and no accessibility event arrived during it at all.
    ///
    /// Genuinely ambiguous, and named so it cannot be mistaken for a diagnosis.
    /// Either the alert was never drawn — Do Not Disturb, a Focus, an alert
    /// style of None — or it was drawn and the app is not seeing banners. The
    /// evidence is identical in both cases: nothing happened. An earlier
    /// version of this reported suppression outright and was observed, live,
    /// telling the user their notifications were muted while it was in fact
    /// blind and Do Not Disturb was off.
    case selfTestAlertNeverSeen

    // Capture — the banner appeared and we failed to see it.
    case accessibilityNotTrusted
    case observerNotAttached
    case lazyAccessibilityTree        // the macOS 15.4-class bug

    /// Which settings pane to offer. Only `false` for faults we are confident
    /// lie on the capture side.
    ///
    /// `selfTestInconclusive` sits on the delivery side deliberately, despite
    /// naming no specific delivery fault. When the app cannot tell which half
    /// failed, offering Accessibility asserts that capture is at fault — and a
    /// live run proved how wrong that gets: Do Not Disturb suppressed the
    /// self-test's banner, and the app offered to take the user to re-grant
    /// Accessibility to cure it. Silence about the cause is honest; pointing at
    /// the innocent half is not.
    public var isDeliveryFault: Bool {
        switch self {
        case .notificationPermissionDenied, .notificationsSuppressed, .selfTestInconclusive: return true
        // Ambiguous. Routed to notification settings because its advice tells the
        // user to rule Do Not Disturb out first — it is the cheaper check, and
        // the far more common cause. The advice names the other possibility.
        case .selfTestAlertNeverSeen: return true
        case .accessibilityNotTrusted, .observerNotAttached, .lazyAccessibilityTree: return false
        }
    }

    /// Shown to the user. Says what to do, not merely what is wrong.
    public var advice: String {
        switch self {
        case .notificationPermissionDenied:
            return "Allow notifications for SignalLadder in System Settings — without it the app cannot verify it is working."
        case .notificationsSuppressed:
            return "Do Not Disturb, a Focus, or an alert style of None is suppressing SignalLadder's own alerts, so it cannot verify itself. Capture is unaffected while banners are still shown for other apps."
        case .selfTestAlertNeverSeen:
            return "SignalLadder's self-test alert was never seen. Either it was not shown — Do Not Disturb, a Focus, or an alert style of None — or SignalLadder is not seeing banners at all. Rule out Do Not Disturb first; if it is off, turn on Full Keyboard Access in System Settings › Keyboard, the known workaround for macOS not exposing notifications."
        case .selfTestInconclusive:
            return "A self-test did not complete, and SignalLadder cannot tell whether its alert was shown. It will retry in a minute."
        case .accessibilityNotTrusted:
            return "Grant Accessibility to SignalLadder in System Settings — without it no notifications can be read."
        case .observerNotAttached:
            return "Not attached to Notification Centre. It may be restarting; this usually recovers within seconds."
        case .lazyAccessibilityTree:
            return "macOS is not exposing notifications to assistive apps. Turning on Full Keyboard Access in System Settings › Keyboard is the known workaround."
        }
    }
}

public enum CaptureHealth: Equatable, Sendable {
    /// A canary round-tripped. The only state that is positive evidence.
    case verified
    /// Nothing is known yet — at launch, before the first canary.
    case unknown
    /// Working, but something reduces confidence.
    case degraded([HealthCause])
    /// Not capturing. Causes are ordered most-likely first.
    case blind([HealthCause])

    public var isAlarming: Bool {
        switch self {
        case .verified, .unknown: return false
        case .degraded, .blind: return true
        }
    }
}
