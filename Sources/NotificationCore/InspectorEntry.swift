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

    /// What the rules loaded NOW would do with this notification. Set only
    /// when the rules change, never at capture.
    ///
    /// Kept apart from `annotation` on purpose. `annotation` records what
    /// happened when the notification arrived — and from M3b, that means
    /// whether an alert sounded. Re-evaluating a row under new rules and
    /// writing the result into `annotation` would rewrite that history: a row
    /// saying "Matched On-call mentions" for a notification that, at the time,
    /// matched nothing and alerted no one.
    public var preview: MatchAnnotation?

    public init(id: UUID = UUID(),
                captured: CapturedNotification,
                context: ContextSnapshot,
                suppressedRepeatCount: Int,
                annotation: MatchAnnotation? = nil,
                preview: MatchAnnotation? = nil) {
        self.id = id
        self.captured = captured
        self.context = context
        self.suppressedRepeatCount = suppressedRepeatCount
        self.annotation = annotation
        self.preview = preview
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
    /// - Parameter advice: what to DO about it, from the leading cause. The
    ///   window must not stop at naming a state.
    ///
    ///   Without this the empty state read "Nothing captured — and SignalLadder
    ///   cannot confirm it is capturing. Cannot verify itself" for every
    ///   alarming cause alike: a Focus, a revoked permission, a blind
    ///   accessibility path. All the same words, none of them actionable, while
    ///   the app held the specific cause the whole time and showed it in the
    ///   menu one click away. A screen that says less than it knows is the
    ///   quiet form of the failure this window exists to prevent.
    public static func message(isEmpty: Bool,
                               health: CaptureHealth,
                               healthSummary: String,
                               advice: String? = nil) -> String? {
        guard isEmpty else { return nil }

        let detail = [healthSummary, advice].compactMap { $0 }.joined(separator: "\n\n")

        switch health {
        case .verified:
            return "Nothing captured yet. Capture is verified working, so this is simply quiet."
        case .unknown:
            return "Nothing captured yet — and SignalLadder has not yet confirmed it can capture anything.\n\(detail)"
        case .degraded, .blind:
            return "Nothing captured — and SignalLadder cannot confirm it is capturing.\n\(detail)"
        }
    }
}

/// What an Inspector row says about rules, as pure functions.
///
/// Kept out of the SwiftUI view because wording is where this app has
/// repeatedly misled: an empty state that claimed "verified" on a self-test
/// that never ran, and one that named no cause while holding it. Both lived in
/// untested UI code. This does not.
public enum InspectorRowText {
    /// What happened when the notification arrived. Never rewritten by a
    /// preview.
    public static func outcome(_ entry: InspectorEntry) -> String {
        guard let annotation = entry.annotation else {
            // A preview exists only when rules are loaded now, so a row with
            // one but no annotation arrived before any rules did.
            return entry.preview == nil ? "Not evaluated — no rules yet" : "Arrived before any rules were loaded"
        }
        return annotation.ruleName.map { "Matched \($0)" } ?? "Matched no rule"
    }

    /// What the rules loaded now would do — shown only when it differs from
    /// what happened, so the row reads as a dry run rather than as history.
    public static func preview(_ entry: InspectorEntry) -> String? {
        guard let preview = entry.preview else { return nil }
        if let annotation = entry.annotation, annotation.ruleName == preview.ruleName { return nil }
        return preview.ruleName.map { "Current rules would match \($0)" } ?? "Current rules would match nothing"
    }
}
