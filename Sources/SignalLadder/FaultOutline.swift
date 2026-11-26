// Sources/SignalLadder/FaultOutline.swift
import NotificationCore
import SwiftUI

/// How a fault is drawn: its symbol and its sentence in the label colour, with
/// a line round them (M7 plan, Stage 2).
///
/// A fault is something that stops an alert reaching the user, or stops a rule
/// running. Until 1.3 it was orange. Orange is a tier's colour in the Night
/// watch design, so a fault has no hue: it is told by its symbol, its words
/// and this line, which no tier has.
///
/// The line is heavier for someone who has asked for more contrast or not to
/// be shown meaning by colour. That is decided by `DisplaySettings` in the
/// core; the four settings are read here from the environment, so the line
/// follows a change made while the window is open.
struct FaultOutline: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColour

    private var settings: DisplaySettings {
        DisplaySettings(increaseContrast: contrast == .increased, reduceTransparency: reduceTransparency,
                        reduceMotion: reduceMotion, differentiateWithoutColour: differentiateWithoutColour)
    }

    /// How far the line stands off the words at each side. A row that must
    /// keep its place among rows with no line takes this much back.
    static let sideInset: CGFloat = 8

    func body(content: Content) -> some View {
        content
            .foregroundStyle(.primary)
            .padding(.horizontal, Self.sideInset)
            .padding(.vertical, 6)
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.primary, lineWidth: settings.outlineWidth)
            }
    }
}

extension View {
    /// Draws this as a fault: in the label colour, with a line round it.
    func faultOutlined() -> some View {
        modifier(FaultOutline())
    }

    /// Draws this as a fault when it is one, and as it is when it is not, for
    /// a row that is a fault only for some of what it shows. The words keep
    /// their place either way: the line is drawn outside them, so a row with
    /// the line and a row without it begin at the same edge.
    @ViewBuilder
    func faultOutlined(when isFault: Bool) -> some View {
        if isFault {
            faultOutlined().padding(.horizontal, -FaultOutline.sideInset)
        } else {
            self
        }
    }
}
