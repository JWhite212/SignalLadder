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
        guard total > 0 else { return "No notifications captured yet to try this rule on." }
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

    // MARK: - The document

    public static let unsavedChanges = "Unsaved changes — not in effect until you save"

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
            let parts = [part("Added", change.added), part("Removed", change.removed), part("Changed", change.changed)]
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
