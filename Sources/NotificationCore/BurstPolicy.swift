// Sources/NotificationCore/BurstPolicy.swift
import Foundation

/// The three timings that decide what one burst of matches is, kept in one
/// value so that a test can move them and nothing else holds a copy (M5 plan,
/// Ruling 14, O11).
///
/// There is no default but `standard`: the initialiser takes all three, so a
/// caller that wants other timings says so, and none can be built that
/// forgets one.
public struct BurstPolicy: Equatable, Sendable {
    /// How long after an escalation's previous match another still joins it,
    /// for a ladder with no repeating step, measured from that match, so the
    /// gap rolls. A ladder that repeats needs none: while its repeat is
    /// going the ladder itself is the burst (O11a).
    public let quietGap: TimeInterval

    /// How near the next repeat must be, at most, for a joined match to stay
    /// silent in its favour. The smaller of this and one interval is the
    /// measure, so a ladder that repeats every 15 seconds is judged by 15.
    public let silentJoinWindow: TimeInterval

    /// How long after a Shortcut run started a joined match may run it again.
    /// A match that joins sooner is owed a page, which is sent once this much
    /// time has passed since that run started (O11b).
    public let repageTime: TimeInterval

    public init(quietGap: TimeInterval, silentJoinWindow: TimeInterval, repageTime: TimeInterval) {
        self.quietGap = quietGap
        self.silentJoinWindow = silentJoinWindow
        self.repageTime = repageTime
    }

    /// What the plan decided: a quiet gap of 60 seconds, a silent-join window
    /// of 60 seconds and a re-page time of 10 minutes (O11, at its defaults).
    public static let standard = BurstPolicy(quietGap: 60, silentJoinWindow: 60, repageTime: 600)
}
