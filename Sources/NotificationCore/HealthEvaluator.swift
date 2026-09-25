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

    /// Real notifications captured since the last self-test ran.
    ///
    /// Positive evidence, and the only kind the app gets for free. A self-test
    /// proves the round trip; captured traffic proves the half of it the user
    /// actually depends on. When a self-test fails but traffic is arriving, the
    /// two together say something neither says alone: capture works, and the
    /// self-test itself is what is broken.
    public var capturesSinceLastCanary: Int

    /// Seconds since a self-test last succeeded; nil if none ever has.
    ///
    /// A passed self-test proves capture worked at one moment, and only then.
    /// On 2026-09-25 capture went blind about 80 seconds after one passed, and
    /// health went on reading "verified" for as long as the app ran. Wall-clock
    /// time, sleep included, on purpose: nothing is captured while the Mac is
    /// asleep, so evidence from before a long sleep really is that old.
    public var secondsSinceLastSuccessfulCanary: TimeInterval?

    /// How often self-tests are scheduled. Evidence older than this, plus
    /// `HealthEvaluator.freshnessGrace`, means a self-test that should have
    /// run has not.
    public var selfTestInterval: TimeInterval

    public init(accessibilityTrusted: Bool,
                observerAttached: Bool,
                notificationsAuthorized: Bool,
                notificationsWouldDisplay: Bool,
                consecutiveCanaryFailures: Int?,
                canaryFailedWithNoBannerActivity: Bool = false,
                capturesSinceLastCanary: Int = 0,
                secondsSinceLastSuccessfulCanary: TimeInterval? = nil,
                selfTestInterval: TimeInterval = HealthEvaluator.selfTestInterval) {
        self.accessibilityTrusted = accessibilityTrusted
        self.observerAttached = observerAttached
        self.notificationsAuthorized = notificationsAuthorized
        self.notificationsWouldDisplay = notificationsWouldDisplay
        self.consecutiveCanaryFailures = consecutiveCanaryFailures
        self.canaryFailedWithNoBannerActivity = canaryFailedWithNoBannerActivity
        self.capturesSinceLastCanary = capturesSinceLastCanary
        self.secondsSinceLastSuccessfulCanary = secondsSinceLastSuccessfulCanary
        self.selfTestInterval = selfTestInterval
    }
}

public enum HealthEvaluator {
    /// The self-test cadence when not on call (§14).
    public static let selfTestInterval: TimeInterval = 30 * 60

    /// Slack for a scheduled self-test that starts a little late, so a healthy
    /// app does not flicker to "unverified" at every interval boundary. Fixed,
    /// not a fraction of the interval: timer lateness does not scale with it.
    public static let freshnessGrace: TimeInterval = 60

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

        // A self-test that failed with no accessibility event at all is
        // AMBIGUOUS, and must be reported as such.
        //
        // This first read `.notificationsSuppressed` — asserting the alert was
        // never drawn. That inference only holds if the accessibility path is
        // healthy, and it is exactly the path in doubt. A live run on
        // 2026-09-11 settled it: with Do Not Disturb off and banners
        // demonstrably being drawn, the app received no events and announced
        // that notifications were being suppressed. It was blind and blaming
        // Notification Centre — the mirror image of the bug this branch was
        // added to fix, and the same error one step to the left.
        //
        // Two causes produce identical evidence and the app cannot tell them
        // apart, so it names both. Still degraded rather than blind: escalating
        // would accuse Accessibility of a fault that may belong to a Focus, and
        // would do it louder every half hour of a quiet evening.
        if let failures = i.consecutiveCanaryFailures, failures > 0 {
            // Real traffic arriving settles the ambiguity the self-test cannot.
            // The capture path is provably alive, so a self-test that never
            // appeared was not shown — the fault is this app's own delivery.
            // Reported without this, the app sat on "either of two opposite
            // causes" while holding the evidence that ruled one of them out.
            if i.capturesSinceLastCanary > 0 {
                return .degraded([.ownAlertsNotShown])
            }
            if i.canaryFailedWithNoBannerActivity {
                return .degraded([.selfTestAlertNeverSeen])
            }
        }

        switch i.consecutiveCanaryFailures {
        case .none:       return .unknown
        case .some(0):
            // Old evidence is no evidence. Unknown, not alarming: nothing has
            // been seen to fail, a self-test is simply overdue — but nor may
            // the app go on claiming what it last proved half an hour ago.
            if let age = i.secondsSinceLastSuccessfulCanary,
               age > i.selfTestInterval + freshnessGrace {
                return .unknown
            }
            return .verified
        case .some(1):    return .degraded([.selfTestInconclusive])
        default:          return .blind([.lazyAccessibilityTree])
        }
    }
}
