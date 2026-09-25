// Sources/NotificationCore/SpeechAction.swift
import Foundation

/// A line spoken when a rule matches (§5.8, §5.9): which voice, what to say,
/// how fast, at what pitch, and at what gain relative to its level-matched
/// loudness.
///
/// The words come from the notification, so a rendered line is exactly as
/// sensitive as the notification itself: it lives in memory and is never
/// written or logged (§2.1). Only the template is saved.
public struct SpeechAction: Equatable, Sendable {
    /// An `AVSpeechSynthesisVoice` identifier, checked against the installed
    /// voices when rules load.
    public var voiceIdentifier: String
    public var template: String
    public var rate: Float
    public var pitchMultiplier: Float
    public var gainDB: Double

    /// Bodies are often long, and "a 40-second recitation of a Teams thread is
    /// not an alert" (§5.9, §14).
    public static let defaultTemplate = "{app}: {title}"
    public static let rateRange: ClosedRange<Float> = 0...1
    public static let pitchRange: ClosedRange<Float> = 0.5...2
    public static let placeholders = ["app", "title", "body"]

    /// The longest line that is spoken. A template can name `{body}`, and a
    /// title is not guaranteed short, so the default template alone does not
    /// keep an alert from becoming a recitation. Chosen for proportion, not
    /// measured against spoken duration.
    public static let maximumLength = 240

    public init(voiceIdentifier: String, template: String = SpeechAction.defaultTemplate,
                rate: Float = 0.5, pitchMultiplier: Float = 1, gainDB: Double = 0) {
        self.voiceIdentifier = voiceIdentifier
        self.template = template
        self.rate = rate
        self.pitchMultiplier = pitchMultiplier
        self.gainDB = gainDB
    }

    /// The line to say for this notification. One pass over the template, so
    /// text from the notification is never itself read as a template: a title
    /// containing "{body}" is said as written. A token that is not a
    /// placeholder is left as written; rules with one are refused at load.
    public func rendered(for notification: CapturedNotification) -> String {
        let values = ["app": notification.appNameGuess, "title": notification.title, "body": notification.body]
        var line = ""
        var rest = template[...]
        while let open = rest.firstIndex(of: "{") {
            line += rest[..<open]
            guard let close = rest[open...].firstIndex(of: "}") else {
                rest = rest[open...]
                break
            }
            let name = String(rest[rest.index(after: open)..<close])
            line += values[name] ?? String(rest[open...close])
            rest = rest[rest.index(after: close)...]
        }
        line += rest
        guard line.count > Self.maximumLength else { return line }
        return String(line.prefix(Self.maximumLength - 1)) + "…"
    }

    /// Whether a `{` is never closed. Said as written, but most likely a
    /// placeholder missing its brace, so rules with one are refused at load.
    public var hasUnclosedBrace: Bool {
        guard let lastOpen = template.lastIndex(of: "{") else { return false }
        return !template[lastOpen...].contains("}")
    }

    /// Every `{token}` in the template that is not a placeholder, in order.
    public var unknownPlaceholders: [String] {
        var found: [String] = []
        var rest = template[...]
        while let open = rest.firstIndex(of: "{"), let close = rest[open...].firstIndex(of: "}") {
            let name = String(rest[rest.index(after: open)..<close])
            if !Self.placeholders.contains(name) { found.append(name) }
            rest = rest[rest.index(after: close)...]
        }
        return found
    }
}

/// `{"voice": "com.apple.voice.compact.en-GB.Daniel", "template": "{app}: {title}",
/// "rate": 0.5, "pitch": 1, "gainDB": 0}` — every key but `voice` may be left
/// out for its default. Unknown keys are rejected, as everywhere in the file.
extension SpeechAction: Codable {
    enum Key: String, CodingKey, CaseIterable {
        case voice, template, rate, pitch, gainDB
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownKeys(decoder, allowed: Key.allCases.map(\.rawValue), in: "a spoken alert")
        let container = try decoder.container(keyedBy: Key.self)
        self.init(voiceIdentifier: try container.decode(String.self, forKey: .voice),
                  template: try container.decodeIfPresent(String.self, forKey: .template) ?? Self.defaultTemplate,
                  rate: try container.decodeIfPresent(Float.self, forKey: .rate) ?? 0.5,
                  pitchMultiplier: try container.decodeIfPresent(Float.self, forKey: .pitch) ?? 1,
                  gainDB: try container.decodeIfPresent(Double.self, forKey: .gainDB) ?? 0)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        try container.encode(voiceIdentifier, forKey: .voice)
        try container.encode(template, forKey: .template)
        try container.encode(rate, forKey: .rate)
        try container.encode(pitchMultiplier, forKey: .pitch)
        try container.encode(gainDB, forKey: .gainDB)
    }
}
