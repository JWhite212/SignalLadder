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
    /// Every rule the file holds, including ones with problems. No file is an
    /// empty document.
    case editable([Rule])
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
        guard let data else { return .editable([]) }
        let entries: [RuleSetCodec.LenientRule]
        do {
            entries = try RuleSetCodec.read(data).entries
        } catch RuleSetCodec.FileError.unsupportedVersion(let version) {
            return .readOnly(.newerVersion(version))
        } catch RuleSetCodec.FileError.unreadable(let reason) {
            return .readOnly(.unreadable(reason))
        } catch {
            return .readOnly(.unreadable(RuleSetCodec.describe(error)))
        }

        var rules: [Rule] = []
        var undecodable: [RuleSetCodec.Problem] = []
        for (index, entry) in entries.enumerated() {
            switch entry.result {
            case .success(let rule): rules.append(rule)
            case .failure(let error):
                undecodable.append(RuleSetCodec.Problem(index: index, name: entry.name, reason: RuleSetCodec.describe(error)))
            }
        }
        return undecodable.isEmpty ? .editable(rules) : .readOnly(.undecodable(undecodable))
    }

    /// Everything wrong with a rule as it stands in the editor. The version
    /// gate does not apply: the editor writes whatever version the rules need.
    public static func problems(in rule: Rule, sounds: RuleSetCodec.SoundCheck) -> [String] {
        RuleSetCodec.reasons(for: rule, fileVersion: nil, sounds: sounds)
    }
}

/// What changed in the file on disk since the editor read it — said when a
/// save is refused, so the user decides knowing what they would overwrite.
///
/// Rules are compared by name, and a same-named rule by its JSON, with key
/// order ignored. Read with the plain JSON reader rather than the rule
/// decoder, so an entry the rule decoder would reject is still counted.
public struct RulesChange: Equatable, Sendable {
    public enum File: Equatable, Sendable {
        case unchanged, created, deleted, edited
        /// Edited into something that is no longer a rules file.
        case unreadable
    }

    public let file: File
    public let added: [String]
    public let removed: [String]
    public let changed: [String]

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
            let before = entries(loaded) ?? []
            return RulesChange(file: .edited,
                               added: subtract(names(after), names(before)),
                               removed: subtract(names(before), names(after)),
                               changed: changedNames(before, after))
        }
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
