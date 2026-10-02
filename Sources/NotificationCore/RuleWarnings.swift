// Sources/NotificationCore/RuleWarnings.swift
import Foundation

/// A rule that is in effect and may still fail where it matters: its last
/// step starts a Shortcut the Shortcuts app does not list.
public struct RuleWarning: Equatable, Sendable {
    public let ruleName: String
    public let shortcutName: String
    /// What is wrong, in the words the refusal used before this was a warning.
    public let sentence: String

    public init(ruleName: String, shortcutName: String, sentence: String) {
        self.ruleName = ruleName
        self.shortcutName = shortcutName
        self.sentence = sentence
    }

    /// One line of the menu: which rule, and what is wrong with it. A blank
    /// name is left out rather than shown as `""`, as a problem's is.
    public var detail: String {
        let named = ruleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : " \"\(ruleName)\""
        return "Rule\(named): \(sentence)"
    }
}

/// What the loader says about a rule it keeps (M5 ruling 21).
///
/// A Shortcut the Shortcuts app does not list used to refuse the whole rule,
/// first alert and repeats included. With names typed by a user, that
/// switches a rule off for a typo, a capital, or a Shortcut renamed weeks
/// later, and a Mac that logs in at 3am comes up with its paging rule off. So
/// the rule stays in effect, tier 4 still tries the name when it fires and
/// reports there if it fails (a held "Shortcut did not run"), and until then
/// every place that shows the rules says that the name was not found.
///
/// Pure: the rules and the check in, the warnings out. The Shortcuts are
/// listed through the one `SoundCheck`, once per load however many rules
/// name one, and not at all when no rule does.
public enum RuleWarnings {
    /// One warning for each enabled rule whose tier 4 names a Shortcut the
    /// Shortcuts app does not list, in the rules' order. A rule that is off
    /// is not in effect and is not warned about. A blank name is a refusal,
    /// from `RuleSetCodec.problems(in:)`, and is not warned about as well.
    ///
    /// - Parameter sounds: its `shortcuts` list is asked at most once, and
    ///   only when some enabled rule names a Shortcut; a list that cannot be
    ///   read, or none, warns about nothing, since a name is then found out
    ///   by running it.
    public static func warnings(for rules: [Rule], sounds: RuleSetCodec.SoundCheck) -> [RuleWarning] {
        rules.compactMap { rule in
            guard let name = missingShortcut(of: rule, sounds: sounds) else { return nil }
            return RuleWarning(ruleName: rule.name, shortcutName: name, sentence: sentence(forShortcut: name))
        }
    }

    /// The sentences for one rule, which is what the editor shows beside the
    /// name field: advice, and not a problem, since the rule is not refused.
    /// The same words the menu uses, and none for a rule that is off.
    public static func sentences(for rule: Rule, sounds: RuleSetCodec.SoundCheck) -> [String] {
        missingShortcut(of: rule, sounds: sounds).map { [sentence(forShortcut: $0)] } ?? []
    }

    /// Compared exactly, character for character. Whether `shortcuts run`
    /// forgives a difference in case was not measured — testing it would mean
    /// running someone's real Shortcut. An exact check can warn about a rule
    /// that would have worked, and says it is still in effect; the opposite
    /// error would stay silent until the incident.
    private static func missingShortcut(of rule: Rule, sounds: RuleSetCodec.SoundCheck) -> String? {
        guard rule.isEnabled,
              let name = rule.escalation?.tier4?.action.shortcutName,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let listed = sounds.listedShortcuts, !listed.contains(name) else { return nil }
        return name
    }

    private static func sentence(forShortcut name: String) -> String {
        RuleSetCodec.AlertOwner.tier4.bare
            + "Shortcut \"\(name)\" was not found in the Shortcuts app — the name must match one there exactly, "
            + "including capitals, spaces and punctuation"
    }

    /// The line under the rules summary in the menu, or nil when there is
    /// nothing to say. `count` is the number of warnings, one for each rule,
    /// and a warning is not a refusal: every rule it counts is still in effect.
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
}
