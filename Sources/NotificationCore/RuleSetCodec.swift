// Sources/NotificationCore/RuleSetCodec.swift
import Foundation

/// Reads and writes the rules file format: `{"version": 3, "rules": [ ... ]}`.
///
/// Version 2 added alerts. Version 1 files still load; a version 1 file that
/// CONTAINS an alert does not, because the build that wrote version 1 would
/// read it and drop every alert without a word — the version number is what
/// makes an older build refuse a file instead of misreading it.
///
/// Version 3 added speech, on the same principle. A version 2 build would
/// reject a rule that speaks as an unknown key, which is safe but says
/// nothing useful; seeing version 3, it says instead that the file needs a
/// newer SignalLadder.
///
/// Pure — bytes in, rules out. The file itself is read and written by the app
/// target, because `NotificationCore` may not touch the file system
/// (`PurityTests`). Everything that decides what a file MEANS is here, where it
/// can be tested.
public enum RuleSetCodec {
    public static let currentVersion = 3

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
        try decodeIndexed(data)
    }

    /// As `decode`, with a check of each rule's sound. Its reason joins the
    /// rule's other reasons, so a rule with two faults reports both at once
    /// rather than one per edit.
    static func decodeIndexed(_ data: Data, sounds: SoundCheck = .none) throws -> (rules: [Rule], problems: [Problem]) {
        let (version, entries) = try read(data)
        var rules: [Rule] = []
        var problems: [Problem] = []
        for (index, entry) in entries.enumerated() {
            switch entry.result {
            case .success(let rule):
                let reasons = Self.reasons(for: rule, fileVersion: version, sounds: sounds)
                if reasons.isEmpty {
                    rules.append(rule)
                } else {
                    problems.append(Problem(index: index, name: rule.name, reason: reasons.joined(separator: "; ")))
                }
            case .failure(let error):
                problems.append(Problem(index: index, name: entry.name, reason: describe(error)))
            }
        }
        return (rules, problems)
    }

    /// Everything wrong with one rule that decoded: its shape, its alert, its
    /// sound — and, when it came from a file, whether that file's version can
    /// hold it. One function for loading and for the editor, so the menu and
    /// the editor can never disagree about a rule.
    ///
    /// - Parameter fileVersion: the version of the file the rule was read
    ///   from, or nil for a rule in the editor, which is written at whatever
    ///   version it needs.
    static func reasons(for rule: Rule, fileVersion: Int?, sounds: SoundCheck) -> [String] {
        var reasons = Self.problems(in: rule)
        // One version message, naming the version the rule actually needs.
        if let fileVersion, fileVersion < 3, rule.alert?.speech != nil {
            reasons.append("speech needs \"version\": 3 — an older SignalLadder reading this file would reject the rule without saying why")
        } else if let fileVersion, fileVersion < 2, rule.alert != nil {
            reasons.append("alerts need \"version\": 2 — an older SignalLadder reading this file would silently drop every alert in it")
        }
        // Read from whichever case carries them: a match on `.sound` alone
        // would wave through a misspelt sound on a rule that also speaks.
        // A blank name or voice is already reported by `problems(in:)`.
        if let name = rule.alert?.soundName,
           !name.trimmingCharacters(in: .whitespaces).isEmpty,
           let reason = sounds.problem(with: name) {
            reasons.append(reason)
        }
        if let voice = rule.alert?.speech?.voiceIdentifier,
           !voice.trimmingCharacters(in: .whitespaces).isEmpty,
           let reason = sounds.voiceProblem(with: voice) {
            reasons.append(reason)
        }
        return reasons
    }

    /// Whether the sounds rules name can be played — first that they exist,
    /// then that they decode, are audible and are short enough — and whether
    /// the voices they name are installed.
    ///
    /// Named for sounds, which came first. Voices are part of the same check
    /// rather than a parallel one so that every place that checks a rule
    /// checks both; `voices` has no default, so none can forget it.
    public struct SoundCheck {
        /// The names that exist, compared ignoring case. nil skips the check.
        public let available: Set<String>?
        /// For a sound that exists, why it cannot be played, or nil if it can.
        public let unplayable: ((String) -> String?)?
        /// The identifiers of the installed voices. nil skips the check. An
        /// installed voice has no failure to find by trying it: none failed to
        /// render in any measured trial, so membership is the whole check.
        public let voices: Set<String>?

        public init(available: Set<String>?, unplayable: ((String) -> String?)?, voices: Set<String>?) {
            self.available = available
            self.unplayable = unplayable
            self.voices = voices
        }

        public static let none = SoundCheck(available: nil, unplayable: nil, voices: nil)

        func voiceProblem(with identifier: String) -> String? {
            guard let voices, !voices.contains(identifier) else { return nil }
            return "voice \"\(identifier)\" is not installed — choose another in the rule editor, or add it in System Settings › Accessibility › Spoken Content"
        }

        func problem(with name: String) -> String? {
            if let available, !available.contains(where: { $0.lowercased() == name.lowercased() }) {
                let listed = available.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                    .joined(separator: ", ")
                return "sound \"\(name)\" was not found — available: \(listed)"
            }
            return unplayable?(name)
        }
    }

    /// The version and every entry of a file, each decoded or not.
    ///
    /// The version is checked before any rule is decoded. A future format may
    /// shape rules differently, and decoding it with today's rules would
    /// report a list of misleading per-rule errors instead of the one true
    /// fact: this file is newer than this app.
    static func read(_ data: Data) throws -> (version: Int, entries: [LenientRule]) {
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

        do {
            return (version, try decoder.decode(Envelope.self, from: data).rules)
        } catch {
            throw FileError.unreadable(describe(error))
        }
    }

    /// Stable output: sorted keys and pretty printing, so a file the app writes
    /// diffs cleanly against the one the user wrote.
    ///
    /// Written at the lowest version that can hold the rules — 1 unless one
    /// has an alert — so an older build is never refused a file it could read.
    public static func encode(_ rules: [Rule]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(Envelope.Out(version: version(for: rules), rules: rules))
    }

    /// Every rule counts, including one with a problem: writing an alert into
    /// a version 1 file would make that rule a problem when read back.
    static func version(for rules: [Rule]) -> Int {
        if rules.contains(where: { $0.alert?.speech != nil }) { return 3 }
        return rules.contains { $0.alert != nil } ? 2 : 1
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

        func checkSound(_ name: String, _ gainDB: Double) {
            if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                reasons.append("its alert names no sound")
            }
            if !AlertAction.gainRange.contains(gainDB) {
                reasons.append("gainDB \(Self.format(gainDB)) is outside \(Self.gainRangeText)")
            }
        }

        func checkSpeech(_ speech: SpeechAction) {
            if speech.voiceIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                reasons.append("its spoken alert names no voice")
            }
            if speech.template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                reasons.append("its spoken template is empty")
            }
            for name in speech.unknownPlaceholders {
                reasons.append("its spoken template has {\(name)}, which is not a placeholder — use {app}, {title} or {body}")
            }
            if !SpeechAction.rateRange.contains(speech.rate) {
                reasons.append("speech rate \(Self.format(Double(speech.rate))) is outside 0…1")
            }
            if !SpeechAction.pitchRange.contains(speech.pitchMultiplier) {
                reasons.append("speech pitch \(Self.format(Double(speech.pitchMultiplier))) is outside 0.5…2")
            }
            if !AlertAction.gainRange.contains(speech.gainDB) {
                reasons.append("speech gainDB \(Self.format(speech.gainDB)) is outside \(Self.gainRangeText)")
            }
        }

        switch rule.alert {
        case .sound(let name, let gainDB):
            checkSound(name, gainDB)
        case .speak(let speech):
            checkSpeech(speech)
        case .soundAndSpeak(let name, let gainDB, let speech):
            checkSound(name, gainDB)
            checkSpeech(speech)
        case .silent, .none:
            break
        }
        return reasons
    }

    private static let gainRangeText =
        "\(format(AlertAction.gainRange.lowerBound))…+\(format(AlertAction.gainRange.upperBound)) dB"

    /// "12", "2.5", "1e+300". Whole numbers are shown without a decimal
    /// point only while they fit an Int: a hand-written file can hold any
    /// number, and converting one that does not fit traps.
    private static func format(_ value: Double) -> String {
        value == value.rounded() && abs(value) < 1e15 ? String(Int(value)) : String(value)
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
    struct LenientRule: Decodable {
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
    /// Both sound checks run here, when the file loads, so a rule whose sound
    /// cannot play is reported by name now rather than staying silent at the
    /// incident it was written for (ruling 6). Neither has a default, so the
    /// app cannot skip them; `nil` skips one, for tests.
    ///
    /// - Parameters:
    ///   - availableSounds: the sound names that exist, compared ignoring case.
    ///   - unplayable: for a sound that exists, why it cannot be played — it
    ///     does not decode, is silent, is too long — or nil when it can.
    ///   - availableVoices: the identifiers of the installed voices.
    public static func load(_ data: Data?, availableSounds: Set<String>?,
                            unplayable: ((String) -> String?)?,
                            availableVoices: Set<String>?) -> (rules: [Rule], status: RuleStoreStatus) {
        guard let data else { return ([], .noRulesFile) }
        do {
            let (rules, problems) = try RuleSetCodec.decodeIndexed(
                data, sounds: RuleSetCodec.SoundCheck(available: availableSounds, unplayable: unplayable,
                                                      voices: availableVoices))
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
