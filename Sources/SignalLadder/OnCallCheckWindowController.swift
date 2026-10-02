// Sources/SignalLadder/OnCallCheckWindowController.swift
import AppKit
import SwiftUI
import NotificationCore

/// What the check window shows and does: the findings, in the order and the
/// words `OnCallCheck` gave them, whether any is urgent as `OnCallCheck` says,
/// whether a check is running, and what pressing the button runs. It decides
/// nothing, and `OnCallWiringTests` holds each of its lines.
@MainActor
final class OnCallCheckModel: ObservableObject {
    @Published private(set) var lines: [OnCallCheck.Finding] = []
    @Published private(set) var summary = ""
    @Published private(set) var hasUrgent = false
    @Published private(set) var isChecking = false

    /// What the button runs: a self-test now, which ends in the findings being
    /// read again and handed to `update`. Set by whoever makes the window.
    var checkNow: () async -> Void = {}

    func update(findings: [OnCallCheck.Finding]) {
        lines = OnCallCheck.windowLines(findings)
        summary = OnCallCheck.summary(findings)
        hasUrgent = OnCallCheck.hasUrgent(findings)
    }

    func runCheck() async {
        guard !isChecking else { return }
        isChecking = true
        await checkNow()
        isChecking = false
    }
}

/// Holds the on-call check window for a menu-bar-only app.
///
/// An ordinary window, never a modal (M5 plan, Ruling 22): nothing the app opens
/// waits on the user, and capture goes on behind it. It is held and activated as
/// the Inspector is, for the reasons that controller gives: a programmatic
/// window is released on close unless told otherwise, and an `.accessory` app is
/// never frontmost on its own, so without an explicit activate it opens behind
/// whatever the user was looking at, which reads as nothing having happened.
///
/// This file may hold no word of its own (the strict list in `ViewLiteralsTests`):
/// the title is `WindowTitles`'.
@MainActor
final class OnCallCheckWindowController: NSObject, NSWindowDelegate {
    let model = OnCallCheckModel()
    private var window: NSWindow?

    /// What is done when the window comes to the front, to bring what it lists up
    /// to date with what can be read at once. It runs no self-test: whoever sets
    /// it says what it reads, and the window only asks.
    var onBecomeKey: () -> Void = {}

    /// Lists `findings` and brings the window forward, making it first if it is
    /// not there.
    func show(findings: [OnCallCheck.Finding]) {
        model.update(findings: findings)
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = WindowTitles.onCallCheck
            window.contentView = NSHostingView(rootView: OnCallCheckView(model: model))
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// A fixed problem should not stand in a window the user comes back to, so
    /// coming to the front asks for what it lists again. The window opened by
    /// `show` asks too, which lists the same findings it was just given again.
    func windowDidBecomeKey(_ notification: Notification) {
        onBecomeKey()
    }

    /// Brings what the window lists up to date while it exists, and does nothing
    /// to the window: an open one refreshes itself, and a closed one is not
    /// opened by this.
    func refresh(findings: [OnCallCheck.Finding]) {
        guard window != nil else { return }
        model.update(findings: findings)
    }
}
