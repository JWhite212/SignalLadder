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
    /// Kept apart from `annotation` on purpose. `annotation` records which
    /// rule matched when the notification arrived — the fact M3b will act on.
    /// Re-evaluating a row under new rules and writing the result there would
    /// rewrite that history: a row saying "Matched On-call mentions" for a
    /// notification that, at the time, matched nothing.
    ///
    /// Note that a match is not the same as an alert. The spec allows a rule
    /// whose first tier is silent, and snooze suppresses alerts outright, so
    /// whether anything was actually heard is a separate fact M3b must record
    /// for itself — never inferred from `annotation`.
    public var preview: MatchAnnotation?

    /// What the app did about the match, set once, by whatever acted on it.
    /// nil until then — and for every row that matched nothing, and every
    /// preview, which by design never acts.
    public var alertOutcome: AlertOutcome?

    /// What the rest of the ladder has done, for a rule that escalates. Unlike
    /// `alertOutcome`, this is written again and again, by design: as tiers
    /// fire, when the repeats are capped, and when the escalation is
    /// acknowledged or found to have been missed while asleep. It is the one
    /// record of what the app did that changes after the fact (M4 plan,
    /// ruling 13).
    public var escalation: EscalationSummary?

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
        self.alertOutcome = nil
        self.escalation = nil
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
            // True both before the first self-test and after evidence goes
            // stale. "Has not yet confirmed" was false in the second case.
            return "Nothing captured yet — and SignalLadder has no recent confirmation that it can capture anything.\n\(detail)"
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
            // No annotation means no rules were loaded when this arrived — and
            // that is ALL it means. It says nothing about earlier: rules can be
            // loaded, emptied by a broken file, and loaded again, and a row
            // that arrived in the gap must not claim to predate them. This read
            // "no rules yet" and "arrived before any rules were loaded" until
            // review showed both were false after exactly that sequence.
            //
            // A preview exists only while rules are loaded, so its presence
            // says what is true NOW; it can never say what was true before.
            return entry.preview == nil ? "Not evaluated — no rules loaded" : "Arrived while no rules were loaded"
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

/// What happened when a match's alert was acted on.
///
/// Records what the app did, never what the user experienced. "Played" does not
/// mean "heard": the output may have been muted, and when the device said so,
/// that is recorded too.
public enum AlertOutcome: Equatable, Sendable {
    /// The sound played. `gainDB` is the rule's own gain as written, not the
    /// level-matching underneath it — the number the user chose.
    case played(sound: String, gainDB: Double, outputSilent: Bool)
    /// The rule's alert is deliberately silent.
    case silentByRule
    /// The rule has no alert at all.
    case noAlertSet
    /// A sound was meant to play and could not.
    case failed(String)

    /// Speech was asked for. `text` is what was said: notification content,
    /// held in memory with the rest of the row, shown in the Inspector and
    /// nowhere else — never in the menu, never written or logged (§2.1).
    case spoke(text: String, voice: String, gainDB: Double, outputSilent: Bool)
    /// A sound, then speech, as one alert.
    case playedAndSpoke(sound: String, soundGainDB: Double, text: String, voice: String, speechGainDB: Double,
                        outputSilent: Bool)
    /// Speech was meant to be said and could not.
    case couldNotSpeak(String)
    /// The sound played; the speech after it could not be said.
    case playedButNotSpoken(sound: String, gainDB: Double, reason: String, outputSilent: Bool)
    /// The speech was said; the sound before it could not play.
    case spokeButNotPlayed(text: String, voice: String, gainDB: Double, reason: String, outputSilent: Bool)

    /// An alert that could not sound, wholly or in part, or sounded into an
    /// output nobody could hear. Each means the user was not alerted as a rule
    /// said they should be, so each is shown as a warning rather than routine.
    public var needsAttention: Bool {
        switch self {
        case .failed, .couldNotSpeak, .playedButNotSpoken, .spokeButNotPlayed: return true
        case .played(_, _, let silent), .spoke(_, _, _, let silent), .playedAndSpoke(_, _, _, _, _, let silent):
            return silent
        case .silentByRule, .noAlertSet: return false
        }
    }

    /// The spoken line, for the Inspector alone.
    public var spokenText: String? {
        switch self {
        case .spoke(let text, _, _, _), .playedAndSpoke(_, _, let text, _, _, _), .spokeButNotPlayed(let text, _, _, _, _):
            return text
        case .played, .silentByRule, .noAlertSet, .failed, .couldNotSpeak, .playedButNotSpoken:
            return nil
        }
    }
}

extension InspectorRowText {
    /// The alert line for a row, or nil when nothing was acted on.
    public static func alert(_ entry: InspectorEntry) -> String? {
        entry.alertOutcome.map(alert)
    }

    /// Never includes what was spoken: this line is also the menu's, and the
    /// menu is seen at a glance, in meetings, on shared screens.
    public static func alert(_ outcome: AlertOutcome) -> String {
        switch outcome {
        case .played(let sound, let gainDB, let silent):
            return "Played \(sound)\(gainSuffix(gainDB))" + mutedNote(silent)
        case .spoke(_, let voice, let gainDB, let silent):
            return "Spoke (\(voiceAndGain(voice, gainDB)))" + mutedNote(silent)
        case .playedAndSpoke(let sound, let soundGainDB, _, let voice, let speechGainDB, let silent):
            return "Played \(sound)\(gainSuffix(soundGainDB)) and spoke (\(voiceAndGain(voice, speechGainDB)))" + mutedNote(silent)
        case .silentByRule:
            return "Silent by rule"
        case .noAlertSet:
            return "Silent — this rule has no alert"
        case .failed(let reason):
            return "Could not play: \(reason)"
        case .couldNotSpeak(let reason):
            return "Could not speak: \(reason)"
        case .playedButNotSpoken(let sound, let gainDB, let reason, let silent):
            return "Played \(sound)\(gainSuffix(gainDB)), but could not speak: \(reason)" + mutedNote(silent)
        case .spokeButNotPlayed(_, let voice, let gainDB, let reason, let silent):
            return "Spoke (\(voiceAndGain(voice, gainDB))), but could not play: \(reason)" + mutedNote(silent)
        }
    }

    private static func mutedNote(_ outputSilent: Bool) -> String {
        outputSilent ? " — but the Mac's sound output was muted or at zero volume" : ""
    }

    /// "Daniel", or "Daniel, −3 dB" when the gain is not the default.
    private static func voiceAndGain(_ voice: String, _ gainDB: Double) -> String {
        let gain = gainSuffix(gainDB)
        return gain.isEmpty ? voice : "\(voice), \(gain.dropFirst(2).dropLast())"
    }

    /// The rule's own gain, shown only when it is not the default: "+6 dB",
    /// "−3.5 dB", with a true minus sign.
    static func gainSuffix(_ gainDB: Double) -> String {
        guard gainDB != 0 else { return "" }
        let magnitude = abs(gainDB)
        let digits = magnitude.rounded() == magnitude ? String(format: "%.0f", magnitude) : String(magnitude)
        return " (\(gainDB > 0 ? "+" : "−")\(digits) dB)"
    }
}
