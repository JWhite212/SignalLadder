// Sources/SignalLadder/DisplaySettingsReader.swift
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
}
