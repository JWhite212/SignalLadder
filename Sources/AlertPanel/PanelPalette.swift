// Sources/AlertPanel/PanelPalette.swift
import AppKit

/// How loud a block of the panel looks: the panel's own copy of the core's
/// `TierTone`, since this target depends on nothing and so cannot name it
/// (M4 plan, Ruling 17). The panel is given a tier as a number and works the
/// tone out itself, by the same three lines as the core, and
/// `PanelPaletteTests` holds the two to the same lines.
enum PanelTone: Equatable, CaseIterable {
    case first
    case second
    case upper

    /// The tone of a tier, as `TierTone.init(tier:)` gives it.
    init(tier: Int) {
        switch tier {
        case ...1: self = .first
        case 2: self = .second
        default: self = .upper
        }
    }
}

/// The colours of the Night watch design, for AppKit (M7 plan, Stage 1).
///
/// The app target holds the same values for SwiftUI in `NightWatchPalette`.
/// There are two copies because this target depends on nothing of the app's,
/// and `PanelPaletteTests` holds them to the same numbers.
///
/// Every colour is sRGB and opaque. Nothing draws with them yet.
enum PanelPalette {
    /// The navy every surface is drawn on.
    static let ground = colour(0x0C1224)
    /// A surface raised above the ground.
    static let raised = colour(0x26335A)
    /// Words on the ground.
    static let words = colour(0xFFFFFF)
    /// Words on the ground that matter less.
    static let quietWords = colour(0x8C9CC4)
    /// Words on a tier's block, which is always light.
    static let ink = ground
    /// The line round a fault, which has no colour of its own.
    static let outline = words

    /// The colour of a tier's block.
    static func block(_ tone: PanelTone) -> NSColor {
        switch tone {
        case .first: return colour(0xFFC857)
        case .second: return colour(0xFF8A2B)
        case .upper: return colour(0xFF4D3D)
        }
    }

    /// Fixed-width digits and letters, for a time or a count that changes in
    /// place and must not move what is beside it.
    static func mono(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    }

    private static func colour(_ rgb: Int) -> NSColor {
        NSColor(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
                green: CGFloat((rgb >> 8) & 0xFF) / 255,
                blue: CGFloat(rgb & 0xFF) / 255,
                alpha: 1)
    }
}
