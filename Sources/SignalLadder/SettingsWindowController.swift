// Sources/SignalLadder/SettingsWindowController.swift
import AppKit
import SwiftUI
import NotificationCore

/// Holds the Settings window for a menu-bar-only app (M5 plan, O12).
///
/// An ordinary window, never a modal (Ruling 22). It is held and activated as the
/// Inspector is, for the reasons that controller gives: a programmatic window is
/// released on close unless told otherwise, so `isReleasedWhenClosed` is false and
/// reopening shows the same window, and an `.accessory` app is never frontmost on
/// its own, so without an explicit activate it opens behind whatever the user was
/// looking at, which reads as the menu item doing nothing.
///
/// Showing the window reads the status afresh, so what it says is what macOS says
/// now and not what was read when it was last open.
///
/// This file may hold no word of its own (the strict list in `ViewLiteralsTests`):
/// the title is `WindowTitles`'.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    func show(model: SettingsModel) {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 300),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = WindowTitles.settings
            window.contentView = NSHostingView(rootView: SettingsView(model: model))
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }

        model.refresh()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
