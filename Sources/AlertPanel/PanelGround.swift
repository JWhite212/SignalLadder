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
    /// neutral grey), so the navy is a wash over it, thin enough that what is
    /// behind the window still shows and thick enough that the white and pale
    /// blue words on it are read whatever that is. Over a white window the
    /// pale blue words measured about 4.5 to 1 against the ground at 0.6 and
    /// 4.9 to 1 at 0.8 (captured on macOS 27.3, 2026-11-25).
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
/// glass and there is glass to be had. Then the system's glass is drawn behind
/// a thinner wash of the same navy, so the desktop shows through and the
/// ground is still navy.
///
/// What the window shows goes in `holder`, which lies over the ground and is
/// never moved, so a control in it is not built again under a press. It is
/// beside the glass and not inside it: glass changes the colours of what is
/// put in it (seen on macOS 27.3: the tiles came out a brighter blue), and a
/// tier's colour is what says which tier it is. So the blocks, which whoever
/// fills the holder draws, are the same opaque colours on either ground.
public final class PanelGroundView: NSView {
    /// What the window shows goes in here. It fills the ground.
    public let holder = NSView()
    /// What the ground is drawn with now. Solid after `use(.glass)` where
    /// there is no glass.
    public private(set) var material: PanelGround.Material = .solid

    private let cornerRadius: CGFloat
    private var glass: NSView?

    public init(cornerRadius: CGFloat) {
        self.cornerRadius = cornerRadius
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.masksToBounds = true
        layer?.backgroundColor = PanelPalette.ground.cgColor
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
            layer?.backgroundColor = PanelPalette.ground.withAlphaComponent(PanelGround.washAlpha).cgColor
            material = .glass
        case .solid:
            glass?.removeFromSuperview()
            glass = nil
            layer?.backgroundColor = PanelPalette.ground.cgColor
            material = .solid
        }
    }

    /// The glass view while the ground is glass. For tests.
    var glassView: NSView? { glass }

    private func fill(with view: NSView, below other: NSView?) {
        view.translatesAutoresizingMaskIntoConstraints = true
        view.frame = bounds
        view.autoresizingMask = [.width, .height]
        addSubview(view, positioned: other == nil ? .above : .below, relativeTo: other)
    }
}
