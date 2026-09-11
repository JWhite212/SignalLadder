// Sources/NotificationCore/ContextSnapshot.swift
import Foundation

/// What was true around a capture, recorded so "why didn't my rule fire?" is
/// answerable after the fact (§7.2).
///
/// The spec's full snapshot also carries `onCall` and `screenLocked`. Both are
/// M5 features, and neither is present here: a field that always reads `false`
/// is not a reading, it is a placeholder the Inspector would display as fact
/// and M3's rules would match against. This project dropped `focusActive`
/// rather than ship a condition it could not read honestly; the same standard
/// applies to fields whose source does not exist yet.
public struct ContextSnapshot: Equatable, Sendable {
    /// Time of day and weekday — the basis of M5's time-window conditions.
    public let date: Date

    /// How many notifications from the same app fall inside the recent window.
    /// This is the alert-fatigue signal the product exists to serve: forty in
    /// an hour from one channel is the problem stated in the user's own words.
    public let recentCountForApp: Int

    /// True when the count is a floor rather than a total.
    ///
    /// The ring buffer holds a bounded number of entries, so a genuinely noisy
    /// app can overflow it inside the window — at which point the count is
    /// "at least this many", not "this many". Presenting a floor as a total
    /// would understate exactly the volume the user is trying to measure.
    public let recentCountIsUnderCounted: Bool

    public init(date: Date, recentCountForApp: Int, recentCountIsUnderCounted: Bool = false) {
        self.date = date
        self.recentCountForApp = recentCountForApp
        self.recentCountIsUnderCounted = recentCountIsUnderCounted
    }
}
