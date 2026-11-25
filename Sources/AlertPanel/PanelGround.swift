// Sources/AlertPanel/PanelGround.swift
import AppKit

/// The system's glass, where this build and this Mac have it (M7 plan, Stages
/// 1 and 7).
///
/// Glass arrived with macOS 26 and the package's floor is macOS 14, so two
/// guards are needed and neither does the other's work:
///
/// - `#if compiler(>=6.2)` keeps the name out of a build made with an SDK that
///   has no such class. CI builds with Xcode 16.4, whose SDK is macOS 15's, and
///   `#available` alone does not compile there.
/// - `#available(macOS 26.0, *)` keeps a build made with a newer SDK from
///   calling it on an older Mac.
///
/// The class is named nowhere but here, so the rest of the app compiles the
/// same with either toolchain.
public enum PanelGround {
    /// What a ground is drawn with. The core has the same two cases in
    /// `GroundMaterial` and decides between them; this target depends on
    /// nothing and so cannot name it, and the app copies one into the other.
    public enum Material: Equatable, Sendable {
        /// The design's navy, opaque.
        case solid
        /// The system's glass, tinted towards the navy.
        case glass
    }

    /// Whether this build, on this Mac, has glass to draw with.
    public static var glassIsAvailable: Bool {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) { return true }
        #endif
        return false
    }

    /// How much of the navy is laid over the glass. The glass's own tint does
    /// not make it navy (seen on macOS 27.3: with a navy tint it stayed a
    /// neutral grey), and navy put behind the glass is lightened by it: over a
    /// white window the pale blue words then measured about 3.2 to 1 against
    /// the ground. So the navy is a wash over the glass, thin enough that what
    /// is behind the window still shows and thick enough that the white and
    /// pale blue words on it are read whatever that is: at 0.75 over a white
    /// window they measured about 5.5 to 1 (captured on macOS 27.3 with Reduce
    /// transparency and Increase contrast off, 2026-11-25).
    static let washAlpha: CGFloat = 0.75

    /// A glass view with nothing in it, or nil where there is no glass to be
    /// had, in which case the caller draws a solid ground.
    @MainActor
    static func makeGlass(cornerRadius: CGFloat) -> NSView? {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = cornerRadius
            return glass
        }
        #endif
        return nil
    }

    /// The corner radius `makeGlass` set on a glass view, for tests. Nil for a
    /// view that is not glass.
    @MainActor
    static func cornerRadius(of glass: NSView) -> CGFloat? {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *), let glass = glass as? NSGlassEffectView { return glass.cornerRadius }
        #endif
        return nil
    }
}

/// The ground of a window that floats over other apps: the escalation panel's
/// and the status popover's (M7 plan, Stage 7).
///
/// It is the design's navy, opaque, with rounded corners, until it is asked for
/// glass and there is glass to be had. Then the system's glass is drawn
/// behind a thinner wash of the same navy, so the desktop shows through and
/// the ground is still navy.
///
/// It is drawn for a dark appearance whatever the system's. Glass follows the
/// appearance of the view it is in, and in a light one it is pale (seen on
/// macOS 27.3: the ground came out near white, under white words), so the
/// ground says dark for itself and does not leave it to each window.
///
/// What the window shows goes in `holder`, which lies over the ground and is
/// never moved, so a control in it is not built again under a press. It is
/// over the glass and the wash and not inside the glass, so nothing the glass
/// does to its own content reaches a tier's colour, which is what says which
/// tier it is: the blocks, which whoever fills the holder draws, measured the
/// same colours on either ground.
public final class PanelGroundView: NSView {
    /// What the window shows goes in here. It fills the ground.
    public let holder = NSView()
    /// What the ground is drawn with now. Solid after `use(.glass)` where
    /// there is no glass.
    public private(set) var material: PanelGround.Material = .solid

    private let cornerRadius: CGFloat
    private var glass: NSView?
    /// The navy laid over the glass, under what the window shows.
    private let wash = NSView()

    public init(cornerRadius: CGFloat) {
        self.cornerRadius = cornerRadius
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.masksToBounds = true
        // The curve of the popover's own clip, so the ground's edge is the
        // edge that was drawn before the ground was this view.
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = PanelPalette.ground.cgColor
        appearance = NSAppearance(named: .darkAqua)
        fill(with: holder, below: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("not made from a nib")
    }

    /// Draws the ground with `wanted`, or with the solid navy where glass was
    /// asked for and there is none. Asking for what it already is does nothing.
    public func use(_ wanted: PanelGround.Material) {
        guard wanted != material else { return }
        switch wanted {
        case .glass:
            guard let made = PanelGround.makeGlass(cornerRadius: cornerRadius) else { return }
            fill(with: made, below: holder)
            glass = made
            layer?.backgroundColor = NSColor.clear.cgColor
            wash.wantsLayer = true
            wash.layer?.backgroundColor = PanelPalette.ground.withAlphaComponent(PanelGround.washAlpha).cgColor
            fill(with: wash, below: holder)
            material = .glass
        case .solid:
            glass?.removeFromSuperview()
            glass = nil
            wash.removeFromSuperview()
            layer?.backgroundColor = PanelPalette.ground.cgColor
            material = .solid
        }
    }

    /// The glass view while the ground is glass. For tests.
    var glassView: NSView? { glass }
    /// The navy over the glass while the ground is glass. For tests.
    var washView: NSView? { glass == nil ? nil : wash }

    private func fill(with view: NSView, below other: NSView?) {
        view.translatesAutoresizingMaskIntoConstraints = true
        view.frame = bounds
        view.autoresizingMask = [.width, .height]
        addSubview(view, positioned: other == nil ? .above : .below, relativeTo: other)
    }
}
