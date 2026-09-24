// Sources/NotificationCore/RuleSetCodec.swift
import Foundation

/// Reads and writes the rules file format: `{"version": 2, "rules": [ ... ]}`.
///
/// Version 2 added alerts. Version 1 files still load; a version 1 file that
/// CONTAINS an alert does not, because the build that wrote version 1 would
/// read it and drop every alert without a word — the version number is what
/// makes an older build refuse a file instead of misreading it.
///
/// Pure — bytes in, rules out. The file itself is read and written by the app
/// target, because `NotificationCore` may not touch the file system
/// (`PurityTests`). Everything that decides what a file MEANS is here, where it
/// can be tested.
public enum RuleSetCodec {
    public static let currentVersion = 2

    /// A rule that was present in the file but is not in effect.
    public struct Problem: Equatable, Sendable, CustomStringConvertible {
        /// Zero-based position in the file's `rules` array.
        public let index: Int
        /// When it could be recovered — a rule too malformed to decode may
        /// still have a readable name, and naming it is most of what makes the
        /// report useful.
        public let name: String?
        public let reason: String

        public init(index: Int, name: String?, reason: String) {
            self.index = index
            self.name = name
            self.reason = reason
        }

        public var description: String {
            // A blank name is omitted rather than shown as `(" ")`, which
            // reads as a rendering glitch instead of the actual fault.
            let shown = name.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
            return "Rule \(index + 1)\(shown.map { " (\"\($0)\")" } ?? ""): \(reason)"
        }
    }

    /// Failures that leave NO rule in effect.
    public enum FileError: Error, Equatable, Sendable {
        case unreadable(String)
        case unsupportedVersion(Int)
    }

    /// Decodes every rule it can and reports every one it cannot.
    ///
    /// One malformed rule does not take the rest down: for an on-call tool that
    /// would turn a typo into total silence. Nor is a rejected rule dropped
    /// quietly — it comes back as a `Problem`, because a rule the user wrote
    /// that silently never runs is the failure this app exists to prevent.
    /// Only a file that cannot be understood at all — not JSON, the wrong
    /// shape, or a format version from a newer build — loads nothing.
    public static func decode(_ data: Data) throws -> (rules: [Rule], problems: [Problem]) {
        let (indexed, problems) = try decodeIndexed(data)
        return (indexed.map(\.rule), problems)
    }

    /// As `decode`, keeping each accepted rule's position in the file, so a
    /// problem found later — a sound that does not exist — can say which rule
    /// it is by number, as every other problem does.
    static func decodeIndexed(_ data: Data) throws -> (rules: [(index: Int, rule: Rule)], problems: [Problem]) {
        let decoder = JSONDecoder()

        // The version is checked before any rule is decoded. A future format
        // may shape rules differently, and decoding it with today's rules
        // would report a list of misleading per-rule errors instead of the
        // one true fact: this file is newer than this app.
        let version: Int
        do {
            version = try decoder.decode(VersionProbe.self, from: data).version
        } catch {
            throw FileError.unreadable(describe(error))
        }
        guard version <= currentVersion else { throw FileError.unsupportedVersion(version) }
        guard version >= 1 else { throw FileError.unreadable("\"version\" must be 1 or higher, found \(version)") }

        let envelope: Envelope
        do {
            envelope = try decoder.decode(Envelope.self, from: data)
        } catch {
            throw FileError.unreadable(describe(error))
        }

        var rules: [(index: Int, rule: Rule)] = []
        var problems: [Problem] = []
        for (index, entry) in envelope.rules.enumerated() {
            switch entry.result {
            case .success(let rule):
                var reasons = Self.problems(in: rule)
                if version < 2, rule.alert != nil {
                    reasons.append("alerts need \"version\": 2 — an older SignalLadder reading this file would silently drop every alert in it")
                }
                if reasons.isEmpty {
                    rules.append((index, rule))
                } else {
                    problems.append(Problem(index: index, name: rule.name, reason: reasons.joined(separator: "; ")))
                }
            case .failure(let error):
                problems.append(Problem(index: index, name: entry.name, reason: describe(error)))
            }
        }
        return (rules, problems)
    }

    /// Stable output: sorted keys and pretty printing, so a file the app writes
    /// diffs cleanly against the one the user wrote.
    public static func encode(_ rules: [Rule]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(Envelope.Out(version: currentVersion, rules: rules))
    }

    /// Rules that decode cleanly but cannot mean what their author intended.
    public static func problems(in rule: Rule) -> [String] {
        var reasons: [String] = []
        if rule.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            reasons.append("it has no name, so nothing could say which rule matched")
        }

        func walk(_ condition: RuleCondition) {
            switch condition {
            case .and(let conditions):
                // Vacuously true: a half-written rule would match every
                // notification the app ever sees.
                if conditions.isEmpty { reasons.append("an \"and\" group is empty, so it would match everything") }
                conditions.forEach(walk)
            case .or(let conditions):
                // Vacuously false: the rule could never fire.
                if conditions.isEmpty { reasons.append("an \"or\" group is empty, so it could never match") }
                conditions.forEach(walk)
            case .not(let inner):
                walk(inner)
            case .field(let field, let op, let value):
                // `equals ""` is meaningful — "has no subtitle". An empty
                // `contains` or `matches` is not: it either never fires or
                // matches only empty fields, and neither is what anyone meant.
                if value.isEmpty, op == .contains || op == .matches {
                    reasons.append("\"\(field.rawValue) \(op.rawValue)\" has an empty value")
                }
            }
        }
        walk(rule.condition)

        switch rule.alert {
        case .sound(let name, let gainDB):
            if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                reasons.append("its alert names no sound")
            }
            if !AlertAction.gainRange.contains(gainDB) {
                reasons.append("gainDB \(Self.format(gainDB)) is outside \(Self.format(AlertAction.gainRange.lowerBound))…+\(Self.format(AlertAction.gainRange.upperBound)) dB")
            }
        case .silent, .none:
            break
        }
        return reasons
    }

    private static func format(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }

    /// Turns a decoding failure into a sentence someone editing JSON by hand
    /// can act on, including where in the file it went wrong.
    public static func describe(_ error: Error) -> String {
        guard let error = error as? DecodingError else { return error.localizedDescription }

        func location(_ path: [CodingKey]) -> String {
            let rendered = path.reduce(into: "") { out, key in
                if let index = key.intValue {
                    out += "[\(index)]"
                } else {
                    out += out.isEmpty ? key.stringValue : ".\(key.stringValue)"
                }
            }
            return rendered.isEmpty ? "" : " at \(rendered)"
        }

        switch error {
        case .keyNotFound(let key, let context):
            return "missing \"\(key.stringValue)\"\(location(context.codingPath))"
        case .typeMismatch(_, let context), .valueNotFound(_, let context):
            return "\(context.debugDescription)\(location(context.codingPath))"
        case .dataCorrupted(let context):
            // Syntax errors carry the useful detail — line and column — in
            // the underlying error rather than the context.
            if let underlying = context.underlyingError as NSError?,
               let detail = underlying.userInfo[NSDebugDescriptionErrorKey] as? String {
                return "not valid JSON: \(detail)"
            }
            return "\(context.debugDescription)\(location(context.codingPath))"
        @unknown default:
            return String(describing: error)
        }
    }

    // MARK: - Envelope

    private struct VersionProbe: Decodable {
        let version: Int
    }

    private struct Envelope: Decodable {
        let rules: [LenientRule]

        struct Out: Encodable {
            let version: Int
            let rules: [Rule]
        }
    }

    /// Decodes one array element without letting its failure abort the array.
    private struct LenientRule: Decodable {
        let result: Result<Rule, Error>
        let name: String?

        private enum NameKey: String, CodingKey { case name }

        init(from decoder: Decoder) throws {
            result = Result { try Rule(from: decoder) }
            name = try? decoder.container(keyedBy: NameKey.self).decode(String.self, forKey: .name)
        }
    }
}

/// What the rules file currently means for the user, as one value the menu can
/// render and the status glyph can alarm on.
public enum RuleStoreStatus: Equatable, Sendable {
    case noRulesFile
    case loaded(enabled: Int, disabled: Int)
    case loadedWithProblems(enabled: Int, disabled: Int, rejected: [RuleSetCodec.Problem])
    case unreadable(String)
    case unsupportedVersion(Int)

    /// The whole load decision, pure. `nil` means no file exists.
    ///
    /// Kept here rather than in the app so that every outcome — including the
    /// ones only a damaged file produces — is reachable in a test.
    ///
    /// - Parameter availableSounds: the sound names that exist, compared
    ///   ignoring case. A rule whose sound is not among them is reported here,
    ///   when the file loads, rather than failing to play when the incident it
    ///   was written for arrives. `nil` skips the check; the app always passes
    ///   a set.
    public static func load(_ data: Data?, availableSounds: Set<String>?) -> (rules: [Rule], status: RuleStoreStatus) {
        guard let data else { return ([], .noRulesFile) }
        do {
            var (indexed, problems) = try RuleSetCodec.decodeIndexed(data)
            if let availableSounds {
                let known = Set(availableSounds.map { $0.lowercased() })
                let listed = availableSounds.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }.joined(separator: ", ")
                indexed = indexed.filter { entry in
                    guard case .sound(let name, _)? = entry.rule.alert, !known.contains(name.lowercased()) else { return true }
                    problems.append(RuleSetCodec.Problem(
                        index: entry.index, name: entry.rule.name,
                        reason: "sound \"\(name)\" was not found — available: \(listed)"))
                    return false
                }
                // Reported in file order, however they were found.
                problems.sort { $0.index < $1.index }
            }
            let rules = indexed.map(\.rule)
            let enabled = rules.filter(\.isEnabled).count
            let disabled = rules.count - enabled
            let status: RuleStoreStatus = problems.isEmpty
                ? .loaded(enabled: enabled, disabled: disabled)
                : .loadedWithProblems(enabled: enabled, disabled: disabled, rejected: problems)
            return (rules, status)
        } catch RuleSetCodec.FileError.unsupportedVersion(let version) {
            return ([], .unsupportedVersion(version))
        } catch RuleSetCodec.FileError.unreadable(let reason) {
            return ([], .unreadable(reason))
        } catch {
            return ([], .unreadable(RuleSetCodec.describe(error)))
        }
    }

    /// True whenever something the user wrote is not in effect.
    ///
    /// Drives the same warning glyph as a capture fault. An on-call tool whose
    /// rules did not load is exactly as silent as one that cannot see banners,
    /// and deserves exactly as much of the user's attention.
    public var isProblem: Bool {
        switch self {
        case .noRulesFile, .loaded: return false
        case .loadedWithProblems, .unreadable, .unsupportedVersion: return true
        }
    }

    public var summary: String {
        switch self {
        case .noRulesFile:
            return "Rules: none yet"
        case .loaded(let enabled, let disabled):
            return "Rules: \(Self.active(enabled, disabled))"
        case .loadedWithProblems(let enabled, let disabled, let rejected):
            return "⚠︎ Rules: \(Self.active(enabled, disabled)) — \(rejected.count) could not be used"
        case .unreadable:
            return "⚠︎ Rules file could not be read — no rules are active"
        case .unsupportedVersion(let version):
            return "⚠︎ Rules file needs a newer SignalLadder (format \(version)) — no rules are active"
        }
    }

    /// The specifics, when there are any. Shown beneath the summary so the
    /// user can fix the file without guessing.
    public var detail: [String] {
        switch self {
        case .noRulesFile, .loaded, .unsupportedVersion:
            return []
        case .loadedWithProblems(_, _, let rejected):
            return rejected.map(\.description)
        case .unreadable(let reason):
            return [reason]
        }
    }

    private static func active(_ enabled: Int, _ disabled: Int) -> String {
        let base = enabled == 0 ? "none active" : "\(enabled) active"
        return disabled == 0 ? base : "\(base), \(disabled) off"
    }
}
