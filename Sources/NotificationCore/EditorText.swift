// Sources/NotificationCore/EditorText.swift
import Foundation

/// Every sentence the rule editor shows, worded here where it is tested.
///
/// The editor is where it is easiest to believe you are protected when you
/// are not: a rule can look finished and be unsaved, switched off, or broken.
/// Every line says which.
public enum EditorText {
    // MARK: - The dry-run

    /// "In this draft: matches 3 of the last 50 notifications."
    public static func dryRunHeadline(_ run: DryRun) -> String {
        let total = run.rows.count
        guard total > 0 else { return "In this draft: no notifications captured yet to try this rule on." }
        let count = run.matchedCount
        let found = count == 0 ? "none" : "\(count)"
        let verb = run.ruleIsOff ? "would match" : "matches"
        let when = run.ruleIsOff ? " when switched on" : ""
        return "In this draft: \(verb) \(found) of the last \(total) notification\(total == 1 ? "" : "s")\(when)."
    }

    /// Said whenever notifications this rule matches go to a rule above it.
    public static func claimed(_ run: DryRun) -> String? {
        let count = run.claimedCount
        guard count > 0 else { return nil }
        let them = count == 1 ? "1 more is" : "\(count) more are"
        let claimers = run.claimers
        let by = claimers.count == 1 ? "“\(claimers[0].name)”, above it" : "\(claimers.count) rules above it"
        return "\(them) taken first by \(by)."
    }

    public static func moveAbove(_ name: String) -> String { "Move Above “\(name)”" }

    /// Why what the dry-run shows is not yet what happens, or nil when it is.
    /// The most serious reason wins: a broken rule will not run even once
    /// saved and switched on.
    public static func notInEffect(hasProblems: Bool, isOff: Bool, isUnsaved: Bool) -> String? {
        if hasProblems { return "Not in effect: this rule has problems, and will not run until they are fixed." }
        if isOff { return "Not in effect: this rule is switched off." }
        if isUnsaved { return "Not in effect until you save." }
        return nil
    }

    // MARK: - The builder

    public static func fieldName(_ field: Field) -> String {
        switch field {
        case .app: return "App"
        case .title: return "Title"
        case .subtitle: return "Subtitle"
        case .body: return "Body"
        case .raw: return "Any text"
        case .subrole: return "Banner kind"
        }
    }

    public static func operatorName(_ op: Operator) -> String {
        switch op {
        case .equals: return "is"
        case .notEquals: return "is not"
        case .contains: return "contains"
        case .matches: return "matches pattern"
        }
    }

    /// One condition in words, for a menu: "Title contains “All Hands”".
    /// A long value is shortened here only — the condition keeps all of it.
    public static func describe(_ condition: RuleCondition, limit: Int = 48) -> String {
        switch condition {
        case .field(let field, let op, let value):
            let shown = value.isEmpty ? "empty" : "“\(value.count > limit ? value.prefix(limit) + "…" : Substring(value))”"
            return "\(fieldName(field)) \(operatorName(op)) \(shown)"
        case .and(let children): return "All of \(children.count) conditions"
        case .or(let children): return "Any of \(children.count) conditions"
        case .not(let inner): return "Not: \(describe(inner, limit: limit))"
        }
    }

    /// What each kind of alert does, beside the choice.
    public static func alertMeaning(_ alert: AlertAction?) -> String {
        switch alert {
        case nil: return "Matching notifications are marked in the Inspector. Nothing plays."
        case .silent: return "Matching notifications are claimed and stay quiet: no rule below can sound for them."
        case .sound: return "Plays this sound when a notification matches."
        case .speak: return "Speaks a line built from the notification when one matches."
        case .soundAndSpeak: return "Plays this sound, then speaks a line built from the notification."
        }
    }

    public static let outputSilentNote = "The Mac's sound output is muted or at zero volume — you won't hear it."

    public static let speechTemplateHelp =
        "{app}, {title} and {body} are filled from the notification. Test Speech uses a made-up one."

    /// A gain beside its slider: "0 dB", "+6 dB", "−12 dB", with a true minus.
    public static func gainText(_ gainDB: Double) -> String {
        gainDB == 0 ? "0 dB" : "\(gainDB > 0 ? "+" : "−")\(Int(abs(gainDB))) dB"
    }

    // MARK: - The document

    public static let unsavedChanges = "Unsaved changes — not in effect until you save"

    /// Whether what the editor shows is what the app is running.
    public enum SaveState: Equatable, Sendable {
        /// The draft differs from the file.
        case unsaved
        /// The draft is the file, but the file is not what the app is
        /// running — it was edited by hand and not yet reloaded.
        case fileNotInEffect
        /// The draft is the file, and the file is what the app is running.
        /// `notRunning` counts saved rules that will not run because they
        /// have problems.
        case inEffect(notRunning: Int)
    }

    /// - Parameters:
    ///   - fileIsInEffect: whether the file the editor read is the one the
    ///     rules in effect were read from.
    ///   - broken: whether a rule has problems, and so will not run.
    public static func saveState(draft: [Rule], saved: [Rule], fileIsInEffect: Bool,
                                 broken: (Rule) -> Bool) -> SaveState {
        if draft != saved { return .unsaved }
        if !fileIsInEffect { return .fileNotInEffect }
        return .inEffect(notRunning: saved.filter { $0.isEnabled && broken($0) }.count)
    }

    public static func saveState(_ state: SaveState) -> (text: String, isWarning: Bool) {
        switch state {
        case .unsaved:
            return (unsavedChanges, true)
        case .fileNotInEffect:
            return ("rules.json has changed since it was put into effect — these rules are not running yet", true)
        case .inEffect(let notRunning) where notRunning > 0:
            let them = notRunning == 1 ? "1 rule has problems and does not run" : "\(notRunning) rules have problems and do not run"
            return ("Saved and in effect — except that \(them)", true)
        case .inEffect:
            return ("Saved and in effect", false)
        }
    }

    public static let putIntoEffect = "Put into Effect"

    public static let emptyState = "No rules yet. To make your first, open the Inspector and choose Make a Rule from This on a notification you want to hear about."

    /// Beside "Add Condition from This Notification": the text chosen becomes
    /// part of a rule, and rules are saved to disk.
    public static let savedTextCaption = "The text you add is saved in your rules file."

    public static func readOnly(_ reason: RulesDocument.ReadOnlyReason) -> (title: String, detail: [String]) {
        switch reason {
        case .unreadable(let why):
            return ("The rules file can't be read, so it can't be edited here.", [why])
        case .newerVersion(let version):
            return ("The rules file was written by a newer SignalLadder (format \(version)).",
                    ["Editing it here could lose what this version doesn't understand."])
        case .undecodable(let problems):
            let count = problems.count == 1 ? "1 rule" : "\(problems.count) rules"
            return ("\(count) in the file can't be read, so saving here would drop \(problems.count == 1 ? "it" : "them"). Fix \(problems.count == 1 ? "it" : "them") in a text editor.",
                    problems.map(\.description))
        }
    }

    /// A rule's alert in a word or two, for its row in the list.
    public static func alertSummary(_ alert: AlertAction?) -> String {
        switch alert {
        case nil: return "No alert"
        case .silent: return "Silent"
        case .sound(let name, let gainDB): return name + InspectorRowText.gainSuffix(gainDB)
        case .speak(let speech): return "Spoken" + InspectorRowText.gainSuffix(speech.gainDB)
        case .soundAndSpeak(let name, let gainDB, _): return name + InspectorRowText.gainSuffix(gainDB) + ", spoken"
        }
    }

    public static let closeTitle = "Save changes to your rules?"
    public static let closeDetail = "Changes are not in effect until you save them, and are lost if you don't."

    // MARK: - A save that was refused

    public static let conflictTitle = "rules.json changed since you opened it"

    /// What happened on disk, so the user knows what Save Anyway would replace.
    public static func conflictDetail(_ change: RulesChange) -> String {
        switch change.file {
        case .unchanged:
            return "Nothing has changed."
        case .deleted:
            return "It was deleted\(listed(" with", change.removed))."
        case .created:
            return "It was created\(listed(" with", change.added))."
        case .unreadable:
            return "It was edited into something that can no longer be read as rules."
        case .edited:
            let renames = change.renamed.map { "“\($0.from)” to “\($0.to)”" }.joined(separator: ", ")
            let parts = [part("Added", change.added), part("Removed", change.removed),
                         renames.isEmpty ? nil : "Renamed: \(renames).",
                         part("Changed", change.changed)]
                .compactMap { $0 }
            return parts.isEmpty ? "Only its formatting changed." : parts.joined(separator: " ")
        }
    }

    public static let conflictKeepNote = "Save Anyway keeps the version on disk as a dated copy beside rules.json."

    private static func part(_ label: String, _ names: [String]) -> String? {
        names.isEmpty ? nil : "\(label): \(quoted(names))."
    }

    private static func listed(_ prefix: String, _ names: [String]) -> String {
        names.isEmpty ? "" : "\(prefix) \(quoted(names))"
    }

    private static func quoted(_ names: [String]) -> String {
        names.map { "“\($0)”" }.joined(separator: ", ")
    }
}
