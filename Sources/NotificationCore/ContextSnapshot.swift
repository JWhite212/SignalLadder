// Sources/NotificationCore/ContextSnapshot.swift
import Foundation

/// What was true around a capture, recorded so "why didn't my rule fire?" is
/// answerable after the fact (§7.2).
///
/// The spec's full snapshot also carries `onCall`, which is not here: on-call
/// mode, a switch since 1.0, is not a condition a rule can name (M5 plan,
/// Ruling 1, O14), so nothing would read it. A field that always reads `false`
/// is not a reading, it is a placeholder the Inspector would display as fact
/// and the rules would match against. This project dropped `focusActive`
/// rather than ship a condition it could not read honestly. The screen lock
/// is held as it was read, in `facts`, and is nil when it could not be.
public struct ContextSnapshot: Equatable, Sendable {
    public let date: Date

    /// What a rule's time, screen-lock and send-rate conditions are asked
    /// about for this capture: read once, when it was captured.
    public let facts: MatchFacts

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

    public init(date: Date, recentCountForApp: Int, recentCountIsUnderCounted: Bool = false,
                screenLocked: Bool? = nil, earlierSendAges: [TimeInterval] = [], calendar: Calendar = .current) {
        self.date = date
        self.facts = MatchFacts(date: date, calendar: calendar, screenLocked: screenLocked,
                                earlierSendAges: earlierSendAges)
        self.recentCountForApp = recentCountForApp
        self.recentCountIsUnderCounted = recentCountIsUnderCounted
    }
}
