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

    // Capture — the banner appeared and we failed to see it.
    case accessibilityNotTrusted
    case observerNotAttached
    case lazyAccessibilityTree        // the macOS 15.4-class bug

    public var isDeliveryFault: Bool {
        switch self {
        case .notificationPermissionDenied, .notificationsSuppressed: return true
        case .accessibilityNotTrusted, .observerNotAttached, .lazyAccessibilityTree: return false
        }
    }

    /// Shown to the user. Says what to do, not merely what is wrong.
    public var advice: String {
        switch self {
        case .notificationPermissionDenied:
            return "Allow notifications for SignalLadder in System Settings — without it the app cannot verify it is working."
        case .notificationsSuppressed:
            return "SignalLadder's own alerts are suppressed (alert style set to None, or a Focus is active), so it cannot verify itself."
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
