// Sources/NotificationCore/RuleWarnings.swift
import Foundation

/// A rule that is in effect and may still fail where it matters: its last
/// step starts a Shortcut the Shortcuts app does not list, or one of its alerts
/// names a sound or a voice that cannot be played.
public struct RuleWarning: Equatable, Sendable {
    /// Which of the two it is.
    public enum Kind: Equatable, Sendable {
        /// Its last step names this Shortcut, which the Shortcuts app does not
        /// list (M5 ruling 21).
        case shortcutNotFound(String)
        /// One or more of its alerts names a sound that cannot be found or
        /// played, or a voice that is not installed. An alert that would then
        /// make no sound at all plays `AlertActionRunner.fallbackSound`.
        case cannotPlay
    }

    public let ruleName: String
    public let kind: Kind
    /// What is wrong, in the words the refusal used before this was a warning.
    public let sentence: String

    public init(ruleName: String, kind: Kind, sentence: String) {
        self.ruleName = ruleName
        self.kind = kind
        self.sentence = sentence
    }

    /// A warning about a Shortcut that was not found.
    public init(ruleName: String, shortcutName: String, sentence: String) {
        self.init(ruleName: ruleName, kind: .shortcutNotFound(shortcutName), sentence: sentence)
    }

    /// The Shortcut a warning is about, or nil for one about a sound or a voice.
    public var shortcutName: String? {
        if case .shortcutNotFound(let name) = kind { return name }
        return nil
    }

    /// One line of the menu: which rule, and what is wrong with it. A blank
    /// name is left out rather than shown as `""`, as a problem's is.
    public var detail: String {
        let named = ruleName.isBlank ? "" : " \"\(ruleName)\""
        return "Rule\(named): \(sentence)"
    }
}

/// What the loader says about a rule it keeps (M5 ruling 21, and the finding
/// of 2026-10-16 for sounds and voices).
///
/// A Shortcut the Shortcuts app does not list used to refuse the whole rule,
/// first alert and repeats included. With names typed by a user, that
/// switches a rule off for a typo, a capital, or a Shortcut renamed weeks
/// later, and a Mac that logs in at 3am comes up with its paging rule off. So
/// the rule stays in effect, tier 4 still tries the name when it fires and
/// reports there if it fails (a held "Shortcut did not run"), and until then
/// every place that shows the rules says that the name was not found.
///
/// A sound that cannot be found or played, or a voice that is not installed,
/// used to refuse the whole rule too, and with it its panel and its Shortcut.
/// First match wins, so its matches went to the rules below it, and a silent
/// catch-all beneath it, as in the README's own example, kept the page quiet.
/// A custom sound moved, or a voice an update removed, was enough. So the rule
/// stays in effect as well, an alert that would make no sound at all plays the
/// fallback sound in its place and says so on its row
/// (`AlertActionRunner.fallbackSound`), and every place that shows the rules
/// says which sound or voice cannot be played.
///
/// Pure: the rules and the check in, the warnings out. The Shortcuts are
/// listed through the one `SoundCheck`, once per load however many rules
/// name one, and not at all when no rule does.
public enum RuleWarnings {
    /// For each enabled rule, in the rules' order, one warning if any of its
    /// alerts names a sound or a voice that cannot be played, and then one if
    /// its tier 4 names a Shortcut the Shortcuts app does not list. A rule
    /// that is off is not in effect and is not warned about. A blank name is a
    /// refusal, from `RuleSetCodec.problems(in:)`, and is not warned about as
    /// well.
    ///
    /// - Parameter sounds: its `shortcuts` list is asked at most once, and
    ///   only when some enabled rule names a Shortcut; a list that cannot be
    ///   read, or none, warns about nothing, since a name is then found out
    ///   by running it.
    public static func warnings(for rules: [Rule], sounds: RuleSetCodec.SoundCheck) -> [RuleWarning] {
        rules.flatMap { rule -> [RuleWarning] in
            var warnings: [RuleWarning] = []
            if let sentence = alertSentence(for: rule, sounds: sounds) {
                warnings.append(RuleWarning(ruleName: rule.name, kind: .cannotPlay, sentence: sentence))
            }
            if let name = missingShortcut(of: rule, sounds: sounds) {
                warnings.append(RuleWarning(ruleName: rule.name, shortcutName: name, sentence: sentence(forShortcut: name)))
            }
            return warnings
        }
    }

    /// The sentences for one rule's Shortcut, which is what the editor shows
    /// beside the name field: advice, and not a problem, since the rule is not
    /// refused. The same words the menu uses, and none for a rule that is off.
    public static func sentences(for rule: Rule, sounds: RuleSetCodec.SoundCheck) -> [String] {
        missingShortcut(of: rule, sounds: sounds).map { [sentence(forShortcut: $0)] } ?? []
    }

    /// The sentence for one rule's sounds and voices, which the editor shows
    /// beneath the rule's name, as advice and not a problem: the words the menu
    /// uses, and none for a rule that is off or whose alerts can all be played.
    public static func alertSentences(for rule: Rule, sounds: RuleSetCodec.SoundCheck) -> [String] {
        alertSentence(for: rule, sounds: sounds).map { [$0] } ?? []
    }

    /// Every sound and voice of an enabled rule that cannot be played, in its
    /// tiers' order and in the words the refusal used, joined as a refused
    /// rule's reasons are, or nil when there is none. Read from whichever case
    /// carries them, so a misspelt sound on a rule that also speaks is not waved
    /// through, and a later tier names itself, so a rule failing on both does
    /// not read one sentence twice. A blank name or voice is a refusal, from
    /// `RuleSetCodec.problems(in:)`, and is not warned about as well: blank as
    /// the refusal counts it, with line breaks, or a name of "\n" was both.
    private static func alertSentence(for rule: Rule, sounds: RuleSetCodec.SoundCheck) -> String? {
        guard rule.isEnabled else { return nil }
        var reasons: [String] = []
        for (owner, alert) in RuleSetCodec.alerts(of: rule) {
            if let name = alert.soundName, !name.isBlank,
               let reason = sounds.problem(with: name) {
                reasons.append(owner.bare + reason)
            }
            if let voice = alert.speech?.voiceIdentifier, !voice.isBlank,
               let reason = sounds.voiceProblem(with: voice) {
                reasons.append(owner.bare + reason)
            }
        }
        return reasons.isEmpty ? nil : reasons.joined(separator: "; ")
    }

    /// Compared exactly, character for character. Whether `shortcuts run`
    /// forgives a difference in case was not measured — testing it would mean
    /// running someone's real Shortcut. An exact check can warn about a rule
    /// that would have worked, and says it is still in effect; the opposite
    /// error would stay silent until the incident.
    private static func missingShortcut(of rule: Rule, sounds: RuleSetCodec.SoundCheck) -> String? {
        guard rule.isEnabled,
              let name = rule.escalation?.tier4?.action.shortcutName,
              !name.isBlank,
              let listed = sounds.listedShortcuts, !listed.contains(name) else { return nil }
        return name
    }

    private static func sentence(forShortcut name: String) -> String {
        RuleSetCodec.AlertOwner.tier4.bare
            + "Shortcut \"\(name)\" was not found in the Shortcuts app — the name must match one there exactly, "
            + "including capitals, spaces and punctuation"
    }

    /// One line of the menu's rules section.
    public struct MenuLine: Equatable, Sendable {
        public let text: String
        /// A rule's own line, beneath the summary it belongs to.
        public let indented: Bool

        public init(text: String, indented: Bool) {
            self.text = text
            self.indented = indented
        }
    }

    /// What the menu shows beneath the rules' status: for each kind of warning
    /// there is, its summary and then a line for each rule it counts, Shortcuts
    /// first. A warning is not a refusal, so these are not part of the status,
    /// whose lines are the rules that are not in effect.
    public static func menuLines(for warnings: [RuleWarning]) -> [MenuLine] {
        let shortcuts = warnings.filter { $0.shortcutName != nil }
        let alerts = warnings.filter { $0.kind == .cannotPlay }
        var lines: [MenuLine] = []
        for (summary, ofKind) in [(summaryLine(count: shortcuts.count), shortcuts),
                                  (alertSummaryLine(count: alerts.count), alerts)] {
            guard let summary else { continue }
            lines.append(MenuLine(text: summary, indented: false))
            lines += ofKind.map { MenuLine(text: $0.detail, indented: true) }
        }
        return lines
    }

    /// The line under the rules summary in the menu for Shortcuts that were not
    /// found, or nil when there is nothing to say. `count` is the number of
    /// those warnings, one for each rule, and a warning is not a refusal: every
    /// rule it counts is still in effect.
    public static func summaryLine(count: Int) -> String? {
        summarySentence(count: count).map { "⚠︎ \($0)" }
    }

    /// What the summary line says without its mark, for a place that marks an
    /// urgent line its own way (the on-call check), so the sentence is written
    /// once.
    public static func summarySentence(count: Int) -> String? {
        switch count {
        case ..<1: return nil
        case 1: return "1 Shortcut name was not found — the rule using it is still in effect"
        default: return "\(count) Shortcut names were not found — the rules using them are still in effect"
        }
    }

    /// The menu's line for the rules with a sound or a voice that cannot be
    /// played, or nil when there are none. `count` is the number of those
    /// warnings, one for each rule, and every rule it counts is still in effect.
    public static func alertSummaryLine(count: Int) -> String? {
        alertSummarySentence(count: count).map { "⚠︎ \($0)" }
    }

    /// What that line says without its mark, for the on-call check, so the
    /// sentence is written once.
    public static func alertSummarySentence(count: Int) -> String? {
        switch count {
        case ..<1: return nil
        case 1: return "1 rule has a sound or voice that cannot be played — it is still in effect"
        default: return "\(count) rules have a sound or voice that cannot be played — they are still in effect"
        }
    }
}
