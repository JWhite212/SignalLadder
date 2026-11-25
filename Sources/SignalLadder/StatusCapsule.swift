// Sources/SignalLadder/StatusCapsule.swift
import AppKit
import NotificationCore
import SwiftUI

/// Draws the capsule the status item shows while an alert escalates (M7 plan,
/// Stage 4): the tier and the repeats in fixed-width figures, on the tier's
/// colour.
///
/// What it says is decided by `StatusGlyph` in the core. This draws it and
/// decides nothing. It is an image and not a template, since a template is
/// tinted by the menu bar and would lose the colour that says the tier, so the
/// words VoiceOver needs are set on it as its description.
enum StatusCapsule {
    /// The menu bar is 22 points high and its items leave a little above and
    /// below, as the system's own do.
    private static let height: CGFloat = 18
    private static let padding: CGFloat = 7
    private static let fontSize: CGFloat = 11.5

    static func image(_ capsule: StatusGlyph.Capsule, description: String) -> NSImage {
        let tier = NSColor(NightWatchPalette.block(capsule.tone))
        let navy = NSColor(NightWatchPalette.ink)
        // The two halves of the pulse are the same capsule with its colours
        // exchanged: the tier's colour under navy figures, then navy under
        // figures in the tier's colour with a line of it round the edge. Both
        // read on a light menu bar and on a dark one, which a capsule made
        // fainter did not: its figures sank into a dark bar. It stays the same
        // size, so nothing in the menu bar moves.
        let (ground, figures) = capsule.dim ? (navy, tier) : (tier, navy)
        let text = NSAttributedString(string: capsule.text, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: figures,
        ])
        let words = text.size()
        let size = NSSize(width: ceil(words.width) + 2 * padding, height: height)
        let image = NSImage(size: size, flipped: false) { bounds in
            let edge = bounds.insetBy(dx: 0.75, dy: 0.75)
            let shape = NSBezierPath(roundedRect: edge, xRadius: edge.height / 2, yRadius: edge.height / 2)
            ground.setFill()
            shape.fill()
            tier.setStroke()
            shape.lineWidth = 1.5
            shape.stroke()
            text.draw(at: NSPoint(x: (bounds.width - words.width) / 2, y: (bounds.height - words.height) / 2))
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = description
        return image
    }
}
