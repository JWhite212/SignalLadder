// Sources/NotificationCore/Rule.swift
import Foundation

/// A named condition over a captured notification, and what to do when it
/// matches.
public struct Rule: Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var condition: RuleCondition
    public var isEnabled: Bool

    /// nil when no alert is set: the rule matches, claims the notification,
    /// and stays quiet — how every rule behaved before alerts existed, so an
    /// upgrade makes nothing noisy by surprise. Distinct from `.silent`, which
    /// is a deliberate choice; the Inspector says which.
    public var alert: AlertAction?

    public init(id: UUID = UUID(), name: String, condition: RuleCondition,
                isEnabled: Bool = true, alert: AlertAction? = nil) {
        self.id = id
        self.name = name
        self.condition = condition
        self.isEnabled = isEnabled
        self.alert = alert
    }
}

/// What a rule does when it matches (§5.8). Speech and Shortcuts join this
/// later; each needs machinery that does not exist yet.
public enum AlertAction: Equatable, Sendable {
    /// A named sound at a gain relative to its level-matched loudness. 0 dB is
    /// the same perceived level for every sound (§5.16, measured).
    case sound(name: String, gainDB: Double)

    /// Match and stay quiet — deliberately. First match wins, so a silent rule
    /// placed first is how "Weather should never interrupt me" is written.
    case silent

    /// The EQ stage applies whatever gain it is given — +40 dB was measured
    /// working despite its documented +24 dB ceiling — so the bound is ours to
    /// enforce. +12 dB is already four times the amplitude of a level-matched
    /// sound, with the limiter holding it under full scale.
    public static let gainRange: ClosedRange<Double> = -40...12
}

/// The spec's second organising principle: this one type is the engine's
/// input, the text language's parse target (M5) and the builder's view model
/// (M3c). There is no second representation for the editors to drift from.
///
/// Scoped to what can be evaluated today. The spec also defines `timeWindow`,
/// `onCall`, `screenLocked` and `frequencyAtLeast`; each arrives in M5 with the
/// context that feeds it. A condition over data the app does not yet collect
/// would always be evaluated against a placeholder — the reason
/// `ContextSnapshot` omits `onCall`, applied one layer up.
public indirect enum RuleCondition: Equatable, Sendable {
    case and([RuleCondition])
    case or([RuleCondition])
    case not(RuleCondition)
    case field(Field, Operator, String)
}

public enum Field: String, CaseIterable, Codable, Sendable {
    case app, title, subtitle, body, raw, subrole
}

/// `regex` is specified (§5.11) and deliberately absent. `NSRegularExpression`
/// has no timeout, so the operator is only safe alongside a save-time lint, a
/// subject-length cap and a wall-clock budget. It ships with all three in M5,
/// not before them.
public enum Operator: String, CaseIterable, Codable, Sendable {
    case equals, notEquals, contains, matches
}

extension Rule {
    /// What a new rules file contains: one rule showing the shape, switched
    /// off. Creating the file therefore changes nothing until the user decides
    /// it should, and the placeholder value is something no real banner holds.
    ///
    /// Defined here rather than beside the code that writes it so a test can
    /// prove it loads cleanly — a starter file that opened with a warning
    /// would be the rules feature's first impression.
    public static let editingExample = Rule(
        name: "Example — Teams messages mentioning you (edit, then set enabled to true)",
        condition: .and([
            .field(.app, .equals, "Microsoft Teams"),
            .field(.raw, .contains, "@your-name"),
        ]),
        isEnabled: false,
        alert: .sound(name: "Glass", gainDB: 0)
    )
}

// MARK: - JSON shape

/// Hand-written rather than synthesised, because people write this JSON by
/// hand until the rule editor exists.
///
/// Synthesised `Codable` renders `.field(.title, .contains, "x")` as
/// `{"field":{"_0":"title","_1":"contains","_2":"x"}}` — positional,
/// unreadable, and silently broken by reordering the enum's associated values.
/// The shape here mirrors the M5 text language instead:
///
///     {"and": [ ... ]}   {"or": [ ... ]}   {"not": { ... }}
///     {"field": "title", "op": "contains", "value": "#prod"}
extension RuleCondition: Codable {
    private enum Key: String, CodingKey {
        case and, or, not, field, op, value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        let present = [Key.and, .or, .not, .field].filter { container.contains($0) }

        guard present.count == 1 else {
            let found = present.isEmpty ? "none" : present.map { "\"\($0.rawValue)\"" }.joined(separator: " and ")
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "a condition needs exactly one of \"and\", \"or\", \"not\" or \"field\" — found \(found)"
            ))
        }

        // Unknown keys are rejected, not ignored. An ignored key is a silent
        // change of meaning: a misspelt "vlaue" beside a correct "value" would
        // go unnoticed while the author believed it had been read.
        try rejectUnknownKeys(decoder, allowed: present[0] == .field ? ["field", "op", "value"] : [present[0].rawValue],
                              in: "a condition")

        switch present[0] {
        case .and:
            self = .and(try container.decode([RuleCondition].self, forKey: .and))
        case .or:
            self = .or(try container.decode([RuleCondition].self, forKey: .or))
        case .not:
            self = .not(try container.decode(RuleCondition.self, forKey: .not))
        default:
            self = .field(try container.decode(Field.self, forKey: .field),
                          try container.decode(Operator.self, forKey: .op),
                          try container.decode(String.self, forKey: .value))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        switch self {
        case .and(let conditions):
            try container.encode(conditions, forKey: .and)
        case .or(let conditions):
            try container.encode(conditions, forKey: .or)
        case .not(let condition):
            try container.encode(condition, forKey: .not)
        case .field(let field, let op, let value):
            try container.encode(field, forKey: .field)
            try container.encode(op, forKey: .op)
            try container.encode(value, forKey: .value)
        }
    }
}

/// `id` may be omitted, because nobody hand-writing a rule should have to mint
/// a UUID. `enabled` may be omitted and defaults to on: a rule someone took the
/// trouble to write, silently not running because a key was left out, is the
/// failure this app exists to prevent.
///
/// Unknown keys are rejected. With alerts optional, an ignored key is the most
/// dangerous kind of typo there is: `"alrt": {…}` would decode into a rule that
/// is quietly silent, and `"enabeld": false` into one that is quietly on.
extension Rule: Codable {
    private enum Key: String, CodingKey, CaseIterable {
        case id, name, enabled, condition, alert
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownKeys(decoder, allowed: Key.allCases.map(\.rawValue), in: "a rule")
        let container = try decoder.container(keyedBy: Key.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        condition = try container.decode(RuleCondition.self, forKey: .condition)
        alert = try container.decodeIfPresent(AlertAction.self, forKey: .alert)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(isEnabled, forKey: .enabled)
        try container.encode(condition, forKey: .condition)
        try container.encodeIfPresent(alert, forKey: .alert)
    }
}

/// `"alert": "silent"` or `"alert": {"sound": "Glass", "gainDB": 6}`, where
/// `gainDB` may be omitted for 0.
extension AlertAction: Codable {
    private enum Key: String, CodingKey, CaseIterable {
        case sound, gainDB
    }

    public init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let word = try? single.decode(String.self) {
            guard word == "silent" else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: decoder.codingPath,
                    debugDescription: "an alert is \"silent\" or {\"sound\": …} — found \"\(word)\""
                ))
            }
            self = .silent
            return
        }
        try rejectUnknownKeys(decoder, allowed: Key.allCases.map(\.rawValue), in: "an alert")
        let container = try decoder.container(keyedBy: Key.self)
        self = .sound(name: try container.decode(String.self, forKey: .sound),
                      gainDB: try container.decodeIfPresent(Double.self, forKey: .gainDB) ?? 0)
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .silent:
            var single = encoder.singleValueContainer()
            try single.encode("silent")
        case .sound(let name, let gainDB):
            var container = encoder.container(keyedBy: Key.self)
            try container.encode(name, forKey: .sound)
            try container.encode(gainDB, forKey: .gainDB)
        }
    }
}

/// Any key a JSON object holds, so the keys it should NOT hold can be named.
private struct AnyKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

private func rejectUnknownKeys(_ decoder: Decoder, allowed: [String], in what: String) throws {
    let present = try decoder.container(keyedBy: AnyKey.self).allKeys.map(\.stringValue)
    if let unknown = present.sorted().first(where: { !allowed.contains($0) }) {
        let expected = allowed.map { "\"\($0)\"" }.joined(separator: ", ")
        throw DecodingError.dataCorrupted(.init(
            codingPath: decoder.codingPath,
            debugDescription: "unknown key \"\(unknown)\" in \(what) — expected \(expected)"
        ))
    }
}
