// Sources/AlertPanel/PanelGround.swift
import AppKit

/// The system's glass, where this build and this Mac have it (M7 plan, Stage 1).
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
/// Nothing draws with it yet. It is here so that both toolchains have compiled
/// both branches before anything depends on them.
enum PanelGround {
    /// Whether `makeGlass()` returns a view.
    static var glassIsAvailable: Bool {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) { return true }
        #endif
        return false
    }

    /// A glass view to put content in, or nil where there is none to be had,
    /// in which case the caller draws a solid ground.
    static func makeGlass() -> NSView? {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) { return NSGlassEffectView() }
        #endif
        return nil
    }
}
