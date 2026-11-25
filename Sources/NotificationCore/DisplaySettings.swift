// Sources/NotificationCore/DisplaySettings.swift
import Foundation

/// The four display settings of System Settings, Accessibility, that change
/// how a coloured or translucent surface must be drawn (M7 plan, Stage 1).
///
/// The app reads them from the system and passes them in, so that every
/// combination is tested here with no system to ask. None has a default: a
/// caller that forgot one would draw as if it were off.
public struct DisplaySettings: Equatable, Sendable {
    /// Increase contrast.
    public var increaseContrast: Bool
    /// Reduce transparency.
    public var reduceTransparency: Bool
    /// Reduce motion.
    public var reduceMotion: Bool
    /// Differentiate without colour.
    public var differentiateWithoutColour: Bool

    public init(increaseContrast: Bool, reduceTransparency: Bool, reduceMotion: Bool,
                differentiateWithoutColour: Bool) {
        self.increaseContrast = increaseContrast
        self.reduceTransparency = reduceTransparency
        self.reduceMotion = reduceMotion
        self.differentiateWithoutColour = differentiateWithoutColour
    }

    /// Every setting off, which is how macOS ships.
    public static let allOff = DisplaySettings(increaseContrast: false, reduceTransparency: false,
                                               reduceMotion: false, differentiateWithoutColour: false)

    /// Whether an outline must be drawn heavier. An outline is how a fault is
    /// told from a tier, so it is strengthened both for someone who asked for
    /// more contrast and for someone who asked not to be shown meaning by
    /// colour.
    public var strengthensOutlines: Bool { increaseContrast || differentiateWithoutColour }

    /// Whether what would move or pulse holds still.
    public var holdsStill: Bool { reduceMotion }
}

/// What a surface that floats over other windows is drawn on.
public enum GroundMaterial: Equatable, Sendable {
    /// One opaque colour.
    case solid
    /// The system's glass, with the desktop showing through.
    case glass

    /// The ground to draw. Glass is used only where the system has it and the
    /// user has asked for neither less transparency nor more contrast: either
    /// request means the text must not sit over whatever is behind the window.
    public static func choose(glassAvailable: Bool, settings: DisplaySettings) -> GroundMaterial {
        guard glassAvailable, !settings.reduceTransparency, !settings.increaseContrast else { return .solid }
        return .glass
    }
}
