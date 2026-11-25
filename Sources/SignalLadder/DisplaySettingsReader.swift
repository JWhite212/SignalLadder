// Sources/SignalLadder/DisplaySettingsReader.swift
import AlertPanel
import AppKit
import NotificationCore

/// Reads the four display settings from the system (M7 plan, Stage 1).
///
/// The reading is all this does. What each setting changes is decided by
/// `DisplaySettings` in the core, where every combination is tested.
enum DisplaySettingsReader {
    /// The settings as they are now. They can change while the app runs, so
    /// this is read when something is drawn and not kept.
    static func current(_ workspace: NSWorkspace = .shared) -> DisplaySettings {
        DisplaySettings(increaseContrast: workspace.accessibilityDisplayShouldIncreaseContrast,
                        reduceTransparency: workspace.accessibilityDisplayShouldReduceTransparency,
                        reduceMotion: workspace.accessibilityDisplayShouldReduceMotion,
                        differentiateWithoutColour: workspace.accessibilityDisplayShouldDifferentiateWithoutColor)
    }

    /// What a floating window's ground is drawn with now (M7 plan, Stage 7):
    /// the core's choice, given whether this Mac has glass and the settings as
    /// they are. Read when a window is drawn and not kept, as the settings are.
    static func ground(_ workspace: NSWorkspace = .shared) -> GroundMaterial {
        GroundMaterial.choose(glassAvailable: PanelGround.glassIsAvailable, settings: current(workspace))
    }
}

/// Carries the core's choice of ground to the panel's own type, case for case.
/// The two targets cannot name each other's, as with a row (`PanelRowMapping`).
extension PanelGround.Material {
    init(_ chosen: GroundMaterial) {
        switch chosen {
        case .solid: self = .solid
        case .glass: self = .glass
        }
    }
}

extension GroundMaterial {
    /// What a ground came to be drawn with, which is solid where glass was
    /// asked for and could not be made.
    init(_ drawn: PanelGround.Material) {
        switch drawn {
        case .solid: self = .solid
        case .glass: self = .glass
        }
    }
}
