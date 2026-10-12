// Sources/SignalLadder/InspectorWindowController.swift
import AppKit
import SwiftUI
import NotificationCore

/// Holds the Inspector window for a menu-bar-only app.
///
/// Two things here are load-bearing and both are easy to get wrong:
///
/// `isReleasedWhenClosed` defaults to `true` for a programmatically created
/// NSWindow. Left alone, closing the Inspector frees the window while this
/// controller still points at it, and reopening dereferences freed memory.
///
/// An `.accessory` app is never frontmost on its own, so ordering the window
/// front is not enough — without an explicit activate it opens behind whatever
/// the user was looking at, which reads as the menu item doing nothing.
@MainActor
final class InspectorWindowController {
    private var window: NSWindow?

    func show(model: InspectorModel) {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = WindowTitles.inspector
            window.contentView = NSHostingView(rootView: InspectorView(model: model))
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
