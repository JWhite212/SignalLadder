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
/// tried again, and one runs at the first health check that finds what
/// blocked it has cleared — a menu opening, or the recheck made every minute
/// while it is blocked.
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

        public var allowsSelfTest: Bool { accessibilityTrusted && ownAlertsDisplay && observerAttached }
    }

    public enum Decision: Equatable, Sendable {
        case run
        /// Blocked for now: look again later, in case what blocks it clears
        /// with nobody opening the menu.
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
        if current.allowsSelfTest { return .run }
        // Detached, attaching again runs a self-test of its own, so a retry
        // would only duplicate it.
        return current.observerAttached ? .retryLater : .nothing
    }

    /// The wait before the first retry of a self-test that failed, and the least
    /// any retry waits. A failed self-test promises "It will retry in a minute"
    /// (`HealthCause.selfTestInconclusive`), so this is the minute.
    public static let firstRetryDelay: TimeInterval = 60

    /// The wait after one that was just used: doubled, so that a long Focus does
    /// not mean a self-test banner every minute all evening, and never past the
    /// interval the steady cadence runs at, so a retry is never later than the
    /// next scheduled self-test would be (M5 plan, Ruling 8).
    ///
    /// Off call that is the rule the app has always used, the delay doubled and
    /// capped at 30 minutes: 60, 120, 240, 480, 960, then 1800 for as long as it
    /// goes on failing. On call it is 60, 120, 240, then 300.
    public static func nextRetryDelay(after current: TimeInterval, onCall: Bool) -> TimeInterval {
        min(max(current * 2, firstRetryDelay), HealthEvaluator.selfTestInterval(onCall: onCall))
    }
}
