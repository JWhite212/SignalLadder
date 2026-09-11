import Foundation

/// Everything the evaluator needs, as plain values — so every combination is
/// reachable in a test without an OS, a permission, or a real notification.
public struct HealthInputs: Equatable, Sendable {
    public var accessibilityTrusted: Bool
    public var observerAttached: Bool
    public var notificationsAuthorized: Bool
    public var notificationsWouldDisplay: Bool
    /// nil when no self-test has completed. 0 when the last one succeeded.
    /// Otherwise the number of consecutive failures — one failure is not
    /// evidence of blindness, repeated failure is.
    public var consecutiveCanaryFailures: Int?

    /// True when the last failed self-test saw NO banner activity at all —
    /// Notification Centre created no window for the whole wait.
    ///
    /// This is how the app tells a suppressed notification from a missed one
    /// without any entitlement. A banner that is drawn produces an accessibility
    /// window event even if reading it then fails; a banner that Do Not Disturb
    /// or a Focus silently routes to history produces nothing at all. Settings
    /// cannot reveal that difference — `alertStyle` reads the same either way —
    /// but the absence of the event does.
    public var canaryFailedWithNoBannerActivity: Bool

    public init(accessibilityTrusted: Bool,
                observerAttached: Bool,
                notificationsAuthorized: Bool,
                notificationsWouldDisplay: Bool,
                consecutiveCanaryFailures: Int?,
                canaryFailedWithNoBannerActivity: Bool = false) {
        self.accessibilityTrusted = accessibilityTrusted
        self.observerAttached = observerAttached
        self.notificationsAuthorized = notificationsAuthorized
        self.notificationsWouldDisplay = notificationsWouldDisplay
        self.consecutiveCanaryFailures = consecutiveCanaryFailures
        self.canaryFailedWithNoBannerActivity = canaryFailedWithNoBannerActivity
    }
}

public enum HealthEvaluator {
    /// Delivery is judged BEFORE capture, deliberately. A failed canary with
    /// notifications suppressed says nothing about whether capture works — the
    /// banner never appeared — so reporting "blind" there would be a lie that
    /// sends the user to re-grant Accessibility for no reason.
    public static func evaluate(_ i: HealthInputs) -> CaptureHealth {
        // Capture faults are definite regardless of the canary: without trust
        // or an observer, nothing can be captured, canary or not.
        if !i.accessibilityTrusted {
            return .blind([.accessibilityNotTrusted])
        }
        if !i.observerAttached {
            return .blind([.observerNotAttached])
        }

        // Delivery faults degrade rather than blind: capture may be perfectly
        // healthy, we simply cannot PROVE it, because our own test notification
        // cannot be displayed.
        var deliveryFaults: [HealthCause] = []
        if !i.notificationsAuthorized { deliveryFaults.append(.notificationPermissionDenied) }
        if !i.notificationsWouldDisplay { deliveryFaults.append(.notificationsSuppressed) }
        if !deliveryFaults.isEmpty {
            return .degraded(deliveryFaults)
        }

        // A self-test that failed without Notification Centre drawing anything
        // was never delivered, so it says nothing about capture — no matter how
        // many times it repeats. Escalating that to "blind" would accuse the
        // Accessibility layer of a fault that belongs to Do Not Disturb, and
        // would do it louder every half hour of a quiet evening.
        if i.canaryFailedWithNoBannerActivity, let failures = i.consecutiveCanaryFailures, failures > 0 {
            return .degraded([.notificationsSuppressed])
        }

        switch i.consecutiveCanaryFailures {
        case .none:       return .unknown
        case .some(0):    return .verified
        case .some(1):    return .degraded([.selfTestInconclusive])
        default:          return .blind([.lazyAccessibilityTree])
        }
    }
}
