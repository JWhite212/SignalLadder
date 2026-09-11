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
    public let suppressedRepeatCount: Int

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
