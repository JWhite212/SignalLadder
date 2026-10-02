// Sources/NotificationCore/RulesDocument.swift
import Foundation

/// The rules file as the editor sees it: every rule, in order, or the reason
/// the editor must not touch it.
///
/// Loading for the menu drops a rule with problems so it cannot fire; the
/// editor keeps it, so it can be fixed. Its problems are never stored with it
/// — they are worked out from the rule as it stands, by the same checks the
/// loader uses, so the editor and the menu cannot disagree and a fix clears
/// its problem the moment it is made.
public enum RulesDocument: Equatable, Sendable {
    /// Every rule the file holds, including ones with problems, and the
    /// version the file declares, which the loader judges each rule by and
    /// the editor must too (M5 ruling 2). No file is an empty document, and
    /// has no version.
    case editable([Rule], fileVersion: Int?)
    /// A file the editor cannot represent in full. Saving it would have to
    /// drop what could not be read, so it is not offered.
    case readOnly(ReadOnlyReason)

    public enum ReadOnlyReason: Equatable, Sendable {
        /// Not JSON, or not the shape of a rules file.
        case unreadable(String)
        /// Written by a newer SignalLadder.
        case newerVersion(Int)
        /// Entries that do not decode as rules — an unknown key, a bad
        /// operator — which only a text editor can fix.
        case undecodable([RuleSetCodec.Problem])
    }

    public static func load(_ data: Data?) -> RulesDocument {
        guard let data else { return .editable([], fileVersion: nil) }
        let read: (version: Int, entries: [RuleSetCodec.LenientRule])
        do {
            read = try RuleSetCodec.read(data)
        } catch RuleSetCodec.FileError.unsupportedVersion(let version) {
            return .readOnly(.newerVersion(version))
        } catch RuleSetCodec.FileError.unreadable(let reason) {
            return .readOnly(.unreadable(reason))
        } catch {
            return .readOnly(.unreadable(RuleSetCodec.describe(error)))
        }

        var rules: [Rule] = []
        var undecodable: [RuleSetCodec.Problem] = []
        for (index, entry) in read.entries.enumerated() {
            switch entry.result {
            case .success(let rule): rules.append(rule)
            case .failure(let error):
                undecodable.append(RuleSetCodec.Problem(index: index, name: entry.name, reason: RuleSetCodec.describe(error)))
            }
        }
        return undecodable.isEmpty ? .editable(rules, fileVersion: read.version) : .readOnly(.undecodable(undecodable))
    }

    /// Everything wrong with a rule as it stands in the editor.
    ///
    /// - Parameter fileVersion: the version of the file the rule was read
    ///   from, for a rule exactly as that file holds it, so that a rule the
    ///   loader refuses for its file's version does not look clean here: that
    ///   is the direction that silences a rule that may page someone. nil for
    ///   a rule the draft has changed or added, which a save writes at the
    ///   version it needs. Not defaulted, so no caller can forget to say.
    public static func problems(in rule: Rule, sounds: RuleSetCodec.SoundCheck, fileVersion: Int?) -> [String] {
        RuleSetCodec.reasons(for: rule, fileVersion: fileVersion, sounds: sounds)
    }

    /// The version a rule in the editor is judged by: the file's, while the
    /// rule is exactly as the file holds it, and none once it has been
    /// changed, or added, since a save writes it at the version it needs.
    /// A rule is compared whole, its id included, so a copy is a new rule.
    public static func keptVersion(for rule: Rule, loaded: [Rule], fileVersion: Int?) -> Int? {
        loaded.contains(rule) ? fileVersion : nil
    }

    /// Whether the loader is refusing this rule for the version its file
    /// declares and for nothing else: the rule is exactly as the file holds
    /// it, the file declares less than it needs, and it has no other problem.
    /// A save writes the file at the version its rules need, so it puts such a
    /// rule into effect without any edit to it; a rule with another problem
    /// stays out of effect after one, and is not this.
    public static func isHeldBackByFileVersion(_ rule: Rule, loaded: [Rule], fileVersion: Int?,
                                               sounds: RuleSetCodec.SoundCheck) -> Bool {
        let kept = keptVersion(for: rule, loaded: loaded, fileVersion: fileVersion)
        return !problems(in: rule, sounds: sounds, fileVersion: kept).isEmpty
            && problems(in: rule, sounds: sounds, fileVersion: nil).isEmpty
    }

    /// Whether the file declares a version too low for the rules it holds, so
    /// that the loader refuses one of them: a file version is known, and the
    /// lowest version that holds the rules is higher. False for no file, for
    /// a file that declares what the rules need, and for one that declares
    /// more. After a save the file is written at the version its rules need,
    /// so it is false for the rules that were saved.
    public static func fileNeedsRewriting(rules: [Rule], fileVersion: Int?) -> Bool {
        guard let fileVersion else { return false }
        return RuleSetCodec.version(for: rules) > fileVersion
    }

    /// Whether Save is offered: the draft differs from what was loaded, or
    /// the file must be rewritten. A rule unchanged since load equals its
    /// loaded self, so without the second a rule the loader refuses for its
    /// file's version would be reported and could not be saved: toggling a
    /// field and back returns to equality.
    public static func canSave(draft: [Rule], loaded: [Rule], fileVersion: Int?) -> Bool {
        draft != loaded || fileNeedsRewriting(rules: draft, fileVersion: fileVersion)
    }
}

/// What changed in the file on disk since the editor read it — said when a
/// save is refused, so the user decides knowing what they would overwrite.
///
/// A rule that kept its "id" under a new name was renamed. Otherwise rules
/// are compared by name, and a same-named rule by its JSON, with key order
/// ignored. Read with the plain JSON reader rather than the rule decoder, so
/// an entry the rule decoder would reject is still counted.
public struct RulesChange: Equatable, Sendable {
    public enum File: Equatable, Sendable {
        case unchanged, created, deleted, edited
        /// Edited into something that is no longer a rules file.
        case unreadable
    }

    public struct Rename: Equatable, Sendable {
        public let from: String
        public let to: String

        public init(from: String, to: String) {
            self.from = from
            self.to = to
        }
    }

    public let file: File
    public let added: [String]
    public let removed: [String]
    public let changed: [String]
    public let renamed: [Rename]

    public init(file: File, added: [String], removed: [String], changed: [String], renamed: [Rename] = []) {
        self.file = file
        self.added = added
        self.removed = removed
        self.changed = changed
        self.renamed = renamed
    }

    public static func between(_ loaded: Data?, _ current: Data?) -> RulesChange {
        switch (loaded, current) {
        case (nil, nil): return RulesChange(file: .unchanged, added: [], removed: [], changed: [])
        case (nil, let current?):
            return RulesChange(file: .created, added: names(entries(current) ?? []), removed: [], changed: [])
        case (let loaded?, nil):
            return RulesChange(file: .deleted, added: [], removed: names(entries(loaded) ?? []), changed: [])
        case (let loaded?, let current?):
            if loaded == current { return RulesChange(file: .unchanged, added: [], removed: [], changed: []) }
            guard let after = entries(current) else {
                return RulesChange(file: .unreadable, added: [], removed: [], changed: [])
            }
            var before = entries(loaded) ?? []
            var rest = after
            let (renamed, renamedAndChanged) = takeRenames(&before, &rest)
            return RulesChange(file: .edited,
                               added: subtract(names(rest), names(before)),
                               removed: subtract(names(before), names(rest)),
                               changed: renamedAndChanged + changedNames(before, rest),
                               renamed: renamed)
        }
    }

    /// Pairs rules by "id" and takes out those whose name changed. Reported
    /// otherwise, on 2026-09-25, a rename by hand read as one rule removed and
    /// another added. A file written by hand may have no ids; its rules still
    /// compare by name. Each id pairs once, so a rule duplicated by hand along
    /// with its id counts as new.
    private static func takeRenames(_ before: inout [NSDictionary], _ after: inout [NSDictionary])
        -> (renamed: [Rename], changed: [String]) {
        var renamed: [Rename] = []
        var changed: [String] = []
        var i = 0
        while i < after.count {
            let entry = after[i]
            if let id = entry["id"] as? String,
               let j = before.firstIndex(where: { ($0["id"] as? String) == id }) {
                let old = before[j]
                if name(old) != name(entry) {
                    before.remove(at: j)
                    after.remove(at: i)
                    renamed.append(Rename(from: name(old), to: name(entry)))
                    if !sameApartFromName(old, entry) { changed.append(name(entry)) }
                    continue
                }
            }
            i += 1
        }
        return (renamed, changed)
    }

    private static func sameApartFromName(_ a: NSDictionary, _ b: NSDictionary) -> Bool {
        let x = NSMutableDictionary(dictionary: a)
        let y = NSMutableDictionary(dictionary: b)
        x.removeObject(forKey: "name")
        y.removeObject(forKey: "name")
        return x.isEqual(y)
    }

    // MARK: - Reading loosely

    private static func entries(_ data: Data) -> [NSDictionary]? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rules = object["rules"] as? [Any] else { return nil }
        return rules.map { ($0 as? [String: Any]).map { NSDictionary(dictionary: $0) } ?? NSDictionary() }
    }

    private static func name(_ entry: NSDictionary) -> String {
        (entry["name"] as? String).flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 } ?? "(unnamed)"
    }

    private static func names(_ entries: [NSDictionary]) -> [String] { entries.map(name) }

    /// Multiset difference, order kept: two rules sharing a name are two rules.
    private static func subtract(_ a: [String], _ b: [String]) -> [String] {
        var remaining = b
        return a.filter { name in
            if let i = remaining.firstIndex(of: name) {
                remaining.remove(at: i)
                return false
            }
            return true
        }
    }

    private static func changedNames(_ before: [NSDictionary], _ after: [NSDictionary]) -> [String] {
        var unmatched = before
        var changed: [String] = []
        for entry in after {
            let key = name(entry)
            if let same = unmatched.firstIndex(where: { $0.isEqual(entry) }) {
                unmatched.remove(at: same)
            } else if let sameName = unmatched.firstIndex(where: { name($0) == key }) {
                unmatched.remove(at: sameName)
                changed.append(key)
            }
        }
        return changed
    }
}
