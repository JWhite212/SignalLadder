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

    public init(accessibilityTrusted: Bool,
                observerAttached: Bool,
                notificationsAuthorized: Bool,
                notificationsWouldDisplay: Bool,
                consecutiveCanaryFailures: Int?) {
        self.accessibilityTrusted = accessibilityTrusted
        self.observerAttached = observerAttached
        self.notificationsAuthorized = notificationsAuthorized
        self.notificationsWouldDisplay = notificationsWouldDisplay
        self.consecutiveCanaryFailures = consecutiveCanaryFailures
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

        switch i.consecutiveCanaryFailures {
        case .none:       return .unknown
        case .some(0):    return .verified
        case .some(1):    return .degraded([.selfTestInconclusive])
        default:          return .blind([.lazyAccessibilityTree])
        }
    }
}
