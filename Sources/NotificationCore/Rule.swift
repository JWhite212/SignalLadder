// Sources/NotificationCore/Rule.swift
import Foundation

/// A named condition over a captured notification.
///
/// In M3a a rule's only effect is to annotate the Inspector row it matches.
/// Alert actions arrive in M3b and extend this type then; until a rule can
/// make a sound, it has no business carrying the fields that would describe
/// one.
public struct Rule: Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var condition: RuleCondition
    public var isEnabled: Bool

    public init(id: UUID = UUID(), name: String, condition: RuleCondition, isEnabled: Bool = true) {
        self.id = id
        self.name = name
        self.condition = condition
        self.isEnabled = isEnabled
    }
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
        isEnabled: false
    )
}

// MARK: - JSON shape

/// Hand-written rather than synthesised, because in M3a people write this JSON
/// by hand.
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
extension Rule: Codable {
    private enum Key: String, CodingKey {
        case id, name, enabled, condition
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        condition = try container.decode(RuleCondition.self, forKey: .condition)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(isEnabled, forKey: .enabled)
        try container.encode(condition, forKey: .condition)
    }
}
