// Sources/SignalLadder/NightWatchPalette.swift
import NotificationCore
import SwiftUI

/// The colours of the Night watch design, for SwiftUI (M7 plan, Stage 1).
///
/// The escalation panel holds the same values for AppKit in `PanelPalette`,
/// since its target may import nothing of the app's, and `PanelPaletteTests`
/// holds the two to the same numbers.
///
/// Every colour is sRGB and opaque.
enum NightWatchPalette {
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
    static func block(_ tone: TierTone) -> Color {
        switch tone {
        case .first: return colour(0xFFC857)
        case .second: return colour(0xFF8A2B)
        case .upper: return colour(0xFF4D3D)
        }
    }

    private static func colour(_ rgb: Int) -> Color {
        Color(.sRGB,
              red: Double((rgb >> 16) & 0xFF) / 255,
              green: Double((rgb >> 8) & 0xFF) / 255,
              blue: Double(rgb & 0xFF) / 255,
              opacity: 1)
    }
}

extension Font {
    /// Fixed-width digits and letters at a text style's size, for a time or a
    /// count that changes in place and must not move what is beside it.
    static func mono(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .monospaced).weight(weight)
    }
}
