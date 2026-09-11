// Sources/NotificationCore/InspectorEntry.swift
import Foundation

/// The outcome of evaluating a notification against the rules.
///
/// Its presence means evaluation happened. `ruleName == nil` therefore means
/// "evaluated, matched nothing" — which the spec calls the most common source
/// of confusion (§7.2) — and is deliberately distinguishable from an entry with
/// no annotation at all, meaning nothing has evaluated it yet.
public struct MatchAnnotation: Equatable, Sendable {
    public let ruleName: String?
    public let warnings: [String]

    public init(ruleName: String?, warnings: [String] = []) {
        self.ruleName = ruleName
        self.warnings = warnings
    }
}

/// One row of the Inspector.
///
/// Holds notification content, which lives in memory and nowhere else (§6).
/// Nothing in this type or its users may write it to disk, log it, or send it.
public struct InspectorEntry: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let captured: CapturedNotification
    public let context: ContextSnapshot

    /// How many further copies dedupe suppressed behind this one.
    ///
    /// Surfaced rather than silently dropped because we still do not know
    /// whether suppression is ever correct: dedupe keys on content within a
    /// short window, which cannot tell one banner re-firing during animation
    /// from two genuinely distinct alerts carrying identical text — and two
    /// identical alerts from a noisy channel is precisely the traffic this
    /// product exists to handle. M1 recorded that this path has never been
    /// observed firing in the wild. The Inspector is how that gets settled.
    public internal(set) var suppressedRepeatCount: Int

    /// Written after the fact by whatever evaluates the notification. `nil`
    /// until something does — in M2c, always.
    public var annotation: MatchAnnotation?

    public init(id: UUID = UUID(),
                captured: CapturedNotification,
                context: ContextSnapshot,
                suppressedRepeatCount: Int,
                annotation: MatchAnnotation? = nil) {
        self.id = id
        self.captured = captured
        self.context = context
        self.suppressedRepeatCount = suppressedRepeatCount
        self.annotation = annotation
    }
}

/// What the Inspector says when it has nothing to show.
///
/// An empty list means one of two opposite things: nothing arrived, or nothing
/// could arrive. They look identical and mean the reverse of each other, and
/// conflating them is the failure this product exists to prevent — a live run
/// on 2026-09-11 had Do Not Disturb silently suppressing everything while the
/// app looked idle. Pure and separately tested because getting it wrong is
/// invisible at runtime.
public enum InspectorEmptyState {
    /// Takes `CaptureHealth` whole rather than a pre-reduced Bool.
    ///
    /// It first took `isAlarming: Bool`, which looked equivalent and was not.
    /// `CaptureHealth.isAlarming` maps BOTH `.verified` and `.unknown` to
    /// `false` — correct for deciding whether to sound an alarm, and lossy for
    /// deciding what to claim. Reduced to that Bool, an app that had verified
    /// nothing was indistinguishable from one that had verified everything, and
    /// the empty state told the user capture was "verified working" on the
    /// strength of a test that had never run.
    ///
    /// The four-case enum exists precisely to keep "nothing is known yet" apart
    /// from "checked and fine". Any signature that collapses them puts the bug
    /// back, whatever the caller does.
    public static func message(isEmpty: Bool,
                               health: CaptureHealth,
                               healthSummary: String) -> String? {
        guard isEmpty else { return nil }
        switch health {
        case .verified:
            return "Nothing captured yet. Capture is verified working, so this is simply quiet."
        case .unknown:
            return "Nothing captured yet — and SignalLadder has not yet confirmed it can capture anything.\n\(healthSummary)"
        case .degraded, .blind:
            return "Nothing captured — and SignalLadder cannot confirm it is capturing.\n\(healthSummary)"
        }
    }
}
