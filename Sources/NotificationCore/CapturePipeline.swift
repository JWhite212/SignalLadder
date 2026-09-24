// Sources/NotificationCore/CapturePipeline.swift
import Foundation

/// Every decision made about a captured banner, in order, in one testable
/// place.
///
/// This logic used to live in a closure inside `CaptureController`, in a target
/// with no tests. Two consecutive reviews named it the riskiest uncovered path
/// in the app — and it is where the rule engine attaches, so it had to become
/// testable before anything was added to it. `CaptureController` now only
/// feeds banners in from the Accessibility observer.
///
/// Not thread-safe by design, like `CaptureRingBuffer` it owns: every caller is
/// on the main actor, and a lock here would imply otherwise.
public final class CapturePipeline {
    public enum Outcome: Equatable, Sendable {
        /// The app's own self-test. Never recorded, never counted.
        case selfTest
        /// An alarm or self-test the app posted, caught by the backstop.
        case ownNotification
        /// A repeat dedupe collapsed onto the row it duplicates.
        case suppressedRepeat
        /// A new row. `matchedRule` names the rule it matched once rules are
        /// evaluated here; until then it is always nil.
        case recorded(matchedRule: String?)
    }

    public let history: CaptureRingBuffer
    public private(set) var captureCount = 0

    private let dedupe: CaptureDeduplicator
    private let ownAppName: String?
    private let isSelfTest: (String, [String]) -> Bool
    private var pendingSuppressedRepeats = 0

    /// - Parameter isSelfTest: given a banner's description and text children,
    ///   whether it is the canary. Injected rather than taking a
    ///   `CanaryService`, which posts through UserNotifications and so cannot
    ///   live in this module.
    public init(ownAppName: String?,
                isSelfTest: @escaping (String, [String]) -> Bool,
                history: CaptureRingBuffer = CaptureRingBuffer(),
                dedupe: CaptureDeduplicator = CaptureDeduplicator()) {
        self.ownAppName = ownAppName
        self.isSelfTest = isSelfTest
        self.history = history
        self.dedupe = dedupe
    }

    @discardableResult
    public func process(_ raw: RawCapture, textChildren: [String]) -> Outcome {
        let notification = NotificationFieldExtractor.extract(raw, textChildren: textChildren)

        // The canary is the app talking to itself. Recognised BEFORE dedupe,
        // so its text never enters the dedupe window — otherwise a real
        // notification that happened to match it inside 1.5s would be
        // suppressed as a repeat of a self-test.
        //
        // Both text sources are offered: the description the marker was
        // historically matched against is allowed to be empty, so a
        // description-only check can miss a canary that was captured.
        if isSelfTest(notification.rawText, textChildren) { return .selfTest }

        // Backstop for everything this app posts — alarms, which carry no
        // marker, and a self-test whose marker match failed for any reason.
        // Name alone would be too loose a net: it would silently drop a real
        // notification from any app sharing our name. SelfNotification
        // requires our wording as well.
        if SelfNotification.isOwnNotification(notification, ownAppName: ownAppName) { return .ownNotification }

        let decision = dedupe.admit(notification.rawText, at: notification.timestamp)
        if decision.isRepeat {
            // Recorded on the row it duplicates. Dedupe keys on content within
            // a short window, which cannot tell one banner re-firing during
            // animation from two genuinely distinct alerts carrying identical
            // text — and a noisy channel produces exactly the latter. Showing
            // the count is how we find out which is happening.
            //
            // The fallback covers a row already evicted, which needs ~50
            // distinct captures inside dedupe's 1.5s window. Holding the count
            // for the next admission can attribute it to an unrelated app, but
            // is better than discarding evidence silently.
            if !history.noteSuppressedRepeat(matching: notification.rawText) {
                pendingSuppressedRepeats += 1
            }
            return .suppressedRepeat
        }

        captureCount += 1
        history.record(notification, suppressedRepeatCount: pendingSuppressedRepeats)
        pendingSuppressedRepeats = 0

        return .recorded(matchedRule: nil)
    }
}
