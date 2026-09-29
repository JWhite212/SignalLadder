// Sources/NotificationCore/SelfTestPlan.swift
import Foundation

/// Whether to run a self-test now, and what to do when one cannot run.
///
/// Two live checks on 2026-09-29 found health waiting on the next scheduled
/// self-test, up to 30 minutes away, after whatever had stopped the last one
/// had cleared. Launched with its own banners switched off, the app rightly
/// skipped its self-test and then scheduled nothing, so it read "Checking…"
/// with no check under way. With Accessibility granted again, capture carried
/// on but nothing re-verified it, and the menu quoted a self-test from before
/// the outage. Both want the same two rules: a self-test that cannot run is
/// tried again, and one runs as soon as the thing that blocked it clears.
public enum SelfTestPlan {
    /// What has to hold for a self-test to mean anything.
    public struct Conditions: Equatable, Sendable {
        public let accessibilityTrusted: Bool
        /// Whether the app's own notifications would be drawn as banners.
        public let ownAlertsDisplay: Bool
        public let observerAttached: Bool

        public init(accessibilityTrusted: Bool, ownAlertsDisplay: Bool, observerAttached: Bool) {
            self.accessibilityTrusted = accessibilityTrusted
            self.ownAlertsDisplay = ownAlertsDisplay
            self.observerAttached = observerAttached
        }

        var allowSelfTest: Bool { accessibilityTrusted && ownAlertsDisplay && observerAttached }
    }

    public enum Decision: Equatable, Sendable {
        case run
        /// Blocked for now: look again later, backing off as a failed
        /// self-test does.
        case retryLater
        case nothing
    }

    /// - Parameters:
    ///   - requested: whether a self-test was asked for — at launch, on the
    ///     schedule, or as a retry. A health check made only to refresh the
    ///     menu asks for none.
    ///   - previous: the conditions at the last health check; nil before the
    ///     first.
    public static func decide(requested: Bool, previous: Conditions?, current: Conditions) -> Decision {
        let cleared = previous.map {
            (!$0.accessibilityTrusted && current.accessibilityTrusted)
                || (!$0.ownAlertsDisplay && current.ownAlertsDisplay)
        } ?? false
        guard requested || cleared else { return .nothing }
        if current.allowSelfTest { return .run }
        // Detached, attaching again runs a self-test of its own, so a retry
        // would only duplicate it.
        return current.observerAttached ? .retryLater : .nothing
    }
}
