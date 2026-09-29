// Sources/NotificationCore/Escalation.swift
import Foundation

/// What a rule does after its first alert, until someone acknowledges it:
/// tiers 2 to 4 of §5.7's ladder. Tier 1 stays `Rule.alert`, unchanged, and
/// this sits beside it (M4 plan, ruling 1).
///
/// Each tier is optional, and each runs on its own timer from the moment the
/// ladder starts (ruling 9): tier 4 does not wait for tier 3 to finish.
public struct Escalation: Equatable, Sendable {
    /// Tier 2: a panel on screen that stays until acknowledged.
    public var tier2: PanelAlert?
    /// Tier 3: the alert again, every so often, up to a cap.
    public var tier3: RepeatAlert?
    /// Tier 4: one last alert, or a Shortcut, if nobody has answered.
    public var tier4: FinalAlert?

    public init(tier2: PanelAlert? = nil, tier3: RepeatAlert? = nil, tier4: FinalAlert? = nil) {
        self.tier2 = tier2
        self.tier3 = tier3
        self.tier4 = tier4
    }

    /// A ladder with no tiers would start and never climb.
    public var isEmpty: Bool { tier2 == nil && tier3 == nil && tier4 == nil }

    /// The alerts the later tiers set off, each with its tier, for checks that
    /// treat them as tier 1's alert is treated. A Shortcut is not an alert.
    public var alerts: [(tier: Int, action: AlertAction)] {
        var alerts: [(tier: Int, action: AlertAction)] = []
        if let tier3 { alerts.append((3, tier3.action)) }
        if let action = tier4?.action.alertAction { alerts.append((4, action)) }
        return alerts
    }
}

/// Tier 2. Called `PersistentAlert` in the plan's first draft; renamed because
/// "persistent alert" here already means macOS's own persistent-style
/// notification, which capture reads (`BannerSubrole`).
public struct PanelAlert: Equatable, Sendable {
    public var delaySeconds: Double

    /// Long enough that a glance at the banner suffices; short enough to
    /// catch you before you look away (§14).
    public static let defaultDelaySeconds: Double = 10

    public init(delaySeconds: Double = PanelAlert.defaultDelaySeconds) {
        self.delaySeconds = delaySeconds
    }
}

/// Tier 3. `nil` for a cap means no limit on that measure; whichever cap is
/// reached first stops the repeats (§5.12).
public struct RepeatAlert: Equatable, Sendable {
    public var action: AlertAction
    public var intervalSeconds: Double
    public var maxRepeats: Int?
    public var maxDurationSeconds: Double?

    /// Insistent without being frantic, and stopping after ten minutes rather
    /// than never (§14).
    public static let defaultIntervalSeconds: Double = 30
    public static let defaultMaxRepeats = 20
    public static let defaultMaxDurationSeconds: Double = 600

    public init(action: AlertAction, intervalSeconds: Double = RepeatAlert.defaultIntervalSeconds,
                maxRepeats: Int? = RepeatAlert.defaultMaxRepeats,
                maxDurationSeconds: Double? = RepeatAlert.defaultMaxDurationSeconds) {
        self.action = action
        self.intervalSeconds = intervalSeconds
        self.maxRepeats = maxRepeats
        self.maxDurationSeconds = maxDurationSeconds
    }
}

/// Tier 4.
public struct FinalAlert: Equatable, Sendable {
    public var afterSeconds: Double
    public var action: FinalAction

    /// Two minutes unanswered is a fair sign you are not at the Mac (§14).
    public static let defaultAfterSeconds: Double = 120

    public init(afterSeconds: Double = FinalAlert.defaultAfterSeconds, action: FinalAction) {
        self.afterSeconds = afterSeconds
        self.action = action
    }
}

/// Only tier 4 can run a Shortcut. §5.8 put `.shortcut` in `AlertAction`
/// itself, which would make it legal on tier 1 and reach `AlertPlayer`, which
/// has no business running a process (ruling 5).
public enum FinalAction: Equatable, Sendable {
    case alert(AlertAction)
    case shortcut(name: String)

    public var alertAction: AlertAction? {
        if case .alert(let action) = self { return action }
        return nil
    }

    public var shortcutName: String? {
        if case .shortcut(let name) = self { return name }
        return nil
    }
}

// MARK: - JSON shape

/// `"escalation": {"tier2": {…}, "tier3": {…}, "tier4": {…}}`, any tier left
/// out. Unknown keys are rejected at every level, as everywhere in the file.
extension Escalation: Codable {
    private enum Key: String, CodingKey, CaseIterable {
        case tier2, tier3, tier4
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownKeys(decoder, allowed: Key.allCases.map(\.rawValue), in: "\"escalation\"")
        let container = try decoder.container(keyedBy: Key.self)
        tier2 = try container.decodeIfPresent(PanelAlert.self, forKey: .tier2)
        tier3 = try container.decodeIfPresent(RepeatAlert.self, forKey: .tier3)
        tier4 = try container.decodeIfPresent(FinalAlert.self, forKey: .tier4)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        try container.encodeIfPresent(tier2, forKey: .tier2)
        try container.encodeIfPresent(tier3, forKey: .tier3)
        try container.encodeIfPresent(tier4, forKey: .tier4)
    }
}

/// `{"delaySeconds": 10}`, or `{}` for the default. The key differs from tier
/// 4's `afterSeconds` on purpose, so one written in the wrong tier is caught.
extension PanelAlert: Codable {
    private enum Key: String, CodingKey, CaseIterable {
        case delaySeconds
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownKeys(decoder, allowed: Key.allCases.map(\.rawValue), in: "\"tier2\"")
        let container = try decoder.container(keyedBy: Key.self)
        delaySeconds = try container.decodeIfPresent(Double.self, forKey: .delaySeconds) ?? Self.defaultDelaySeconds
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        try container.encode(delaySeconds, forKey: .delaySeconds)
    }
}

/// `{"action": {…}, "intervalSeconds": 30, "maxRepeats": 20, "maxDurationSeconds": 600}`.
/// Only `action` is required.
///
/// A cap left out is the default cap, never no cap: a hand-written repeat
/// that forgot its limits must stop, as §5.12 intends, not ring for ever. No
/// limit is spelled `null`, and only that way. `decodeIfPresent` reads a
/// missing key and `null` alike, so the two are told apart here, and every
/// key is written back, `null` included, so a file the app writes never
/// leans on a default and never changes meaning when read again.
extension RepeatAlert: Codable {
    private enum Key: String, CodingKey, CaseIterable {
        case action, intervalSeconds, maxRepeats, maxDurationSeconds
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownKeys(decoder, allowed: Key.allCases.map(\.rawValue), in: "\"tier3\"")
        let container = try decoder.container(keyedBy: Key.self)

        func cap<Value: Decodable>(_ key: Key, default value: Value) throws -> Value? {
            guard container.contains(key) else { return value }
            return try container.decodeNil(forKey: key) ? nil : container.decode(Value.self, forKey: key)
        }

        action = try container.decode(AlertAction.self, forKey: .action)
        intervalSeconds = try container.decodeIfPresent(Double.self, forKey: .intervalSeconds)
            ?? Self.defaultIntervalSeconds
        // Read as a number and then required to be whole, because decoding
        // 2.5 straight into an Int fails with an error that names neither the
        // key nor the value, and 2.5 is an easy slip to make by hand.
        if let repeats = try cap(.maxRepeats, default: Double(Self.defaultMaxRepeats)) {
            guard let whole = Int(exactly: repeats) else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: container.codingPath + [Key.maxRepeats],
                    debugDescription: "maxRepeats must be a whole number, or null for no limit — found \(repeats)"
                ))
            }
            maxRepeats = whole
        } else {
            maxRepeats = nil
        }
        maxDurationSeconds = try cap(.maxDurationSeconds, default: Self.defaultMaxDurationSeconds)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        try container.encode(action, forKey: .action)
        try container.encode(intervalSeconds, forKey: .intervalSeconds)
        if let maxRepeats {
            try container.encode(maxRepeats, forKey: .maxRepeats)
        } else {
            try container.encodeNil(forKey: .maxRepeats)
        }
        if let maxDurationSeconds {
            try container.encode(maxDurationSeconds, forKey: .maxDurationSeconds)
        } else {
            try container.encodeNil(forKey: .maxDurationSeconds)
        }
    }
}

/// `{"afterSeconds": 120, "action": {…}}` or `{"afterSeconds": 120, "shortcut": "Page me"}`:
/// exactly one of `action` and `shortcut`. The action is an alert in the same
/// shape as tier 1's, `"silent"` included.
extension FinalAlert: Codable {
    private enum Key: String, CodingKey, CaseIterable {
        case afterSeconds, action, shortcut
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownKeys(decoder, allowed: Key.allCases.map(\.rawValue), in: "\"tier4\"")
        let container = try decoder.container(keyedBy: Key.self)
        afterSeconds = try container.decodeIfPresent(Double.self, forKey: .afterSeconds) ?? Self.defaultAfterSeconds

        switch (container.contains(.action), container.contains(.shortcut)) {
        case (true, false):
            action = .alert(try container.decode(AlertAction.self, forKey: .action))
        case (false, true):
            action = .shortcut(name: try container.decode(String.self, forKey: .shortcut))
        case (true, true):
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "\"tier4\" has both \"action\" and \"shortcut\" — it does one or the other"
            ))
        case (false, false):
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "\"tier4\" needs \"action\" or \"shortcut\""
            ))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        try container.encode(afterSeconds, forKey: .afterSeconds)
        switch action {
        case .alert(let alert): try container.encode(alert, forKey: .action)
        case .shortcut(let name): try container.encode(name, forKey: .shortcut)
        }
    }
}
