// Sources/NotificationCore/TierTone.swift
import Foundation

/// How loud a tier of the ladder looks (M7 plan, Stage 1).
///
/// The ladder has four tiers and the design has three tones, so that the two
/// tiers that mean "nobody has answered and it is still going" look alike:
/// tier 1 is the first alert, tier 2 the panel, and tiers 3 and 4 the repeats
/// and the final step.
///
/// A tone is a name and nothing else. The core may not name a colour, so the
/// app and the panel each turn a tone into one, and a test holds the two
/// palettes to the same values.
public enum TierTone: Equatable, Sendable, CaseIterable {
    /// Tier 1: the first alert.
    case first
    /// Tier 2: the panel is showing.
    case second
    /// Tiers 3 and 4: repeating, or at the final step.
    case upper

    /// The tone of a tier. An escalation's tier runs from 1 to 4. A number
    /// below 1 is read as tier 1 and a number above 4 as the top, on purpose,
    /// so that a number from anywhere has a tone and nothing is drawn with
    /// none. What has no tier at all, such as an alert the Mac slept through,
    /// is not given a tone: its caller draws it another way.
    ///
    /// The panel repeats these three lines in `PanelTone.init(tier:)`, since
    /// its target cannot name this type, and a test holds the two together.
    public init(tier: Int) {
        switch tier {
        case ...1: self = .first
        case 2: self = .second
        default: self = .upper
        }
    }
}
