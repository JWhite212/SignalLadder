// Sources/SignalLadder/SetupWindowController.swift
import AppKit
import SwiftUI
import NotificationCore

/// Holds the Setup Guide's window for a menu-bar-only app (M5 plan, Task 8, Ruling 16,
/// O13).
///
/// An ordinary window, never a modal (Ruling 22): nothing the app opens waits on the user,
/// and capture goes on behind it. It is held and activated as the Inspector is, for the
/// reasons that controller gives: a programmatic window is released on close unless told
/// otherwise, so `isReleasedWhenClosed` is false and reopening shows the same window, and an
/// `.accessory` app is never frontmost on its own, so without an explicit activate it opens
/// behind whatever the user was looking at, which reads as the menu item doing nothing.
/// There is one instance, held by the app delegate, and so one window.
///
/// **Showing it records the start before anything else.** `SetupCoordinator.willShowGuide()`
/// records that the guide was started and hands back the facts gathered after it, which the
/// model is refreshed from, so that what the window first shows already reads as begun.
/// That is what keeps the launch decisions true: a guide shown and left, without it, would
/// be a fresh install's again.
///
/// **Closing it is a dismissal.** `windowWillClose(_:)` calls the coordinator's
/// `guideDidClose(appIsQuitting:)`, and so the close box, "Not now" and Finish all come to
/// the one act and the one record (O13). There is no ⌘W: the main menu has no Close item
/// (`MainMenu`), so no key closes the window, as none closes the Inspector or Settings. The
/// core records nothing for a guide that is finished (`SetupProgress.recordDismissed()`), so
/// this does not ask whether it is. Closing ends the visit, and the model drops the sentence
/// a press handed back in it (`SetupModel.windowDidClose()`); then the app delegate is told
/// (`didClose`), so that Settings' line, which says where the guide stands, is read again.
///
/// **A quit is not a dismissal.** AppKit closes every window still open when the app quits,
/// after it has told the app it will terminate, and sends each delegate `windowWillClose(_:)`
/// as for any other close (measured on macOS 26.7.1, in a scratch program: the notice, then
/// the close, from `NSApplication.terminate(_:)`; not seen on 14 or 15). That close is not the
/// user leaving the guide, and recording it would turn a guide left open at a quit into one
/// the user dismissed, so a fresh install that quit part-way through would not meet it again
/// (O13: it opens when it "was started and not finished"). So the controller notes the
/// notice, which is posted before the windows close and is heard where it is posted, with no
/// queue, and hands the coordinator whether the app is quitting. Whether that close is a
/// dismissal is the core's (`SetupPlan.closeIsDismissal(appIsQuitting:)`). A guide left open
/// at a quit is then started and not dismissed, and `SetupPlan.opensAtLaunch` reads it as in
/// progress: it opens at the next launch, for a configured upgrader who opened it from
/// Settings as for a fresh install (the direction that cannot lose a page; for the owner to
/// confirm).
///
/// **It is refreshed, not polled** (Ruling 20): when it is shown, when it comes to the
/// front, which is how a grant made in System Settings or a rule made in the editor is
/// noticed when the user comes back, and when the app delegate hands it facts it has
/// gathered (`refresh(from:)`), which it does when the app is activated, when the menu opens,
/// after Check again and from `syncInspector`. Coming to the front reads the facts as the app
/// holds them (`refresh()`), health as it last evaluated it. What is asked of the system is
/// the delegate's: the notification probe is asked again by Check again, by the request for
/// notifications and by the menu's opening, and not by coming to the front. Nothing here
/// starts a timer.
///
/// **Whether it counts as open is the core's.** The window reports whether it is visible and
/// whether it is minimised, and `SetupPlan.WindowPresence` answers both questions it is asked:
/// `isOpenForTheNudge` is what the menu's nudge is handed
/// (`SetupPlan.nudgeLine(_:guideIsOpen:)`), and it is false for a window on the Dock, so that
/// the line which leads back to it stays; and a minimised window is still kept up to date.
///
/// This file may hold no word of its own (the strict list in `ViewLiteralsTests`): the title
/// is `WindowTitles`'.
@MainActor
final class SetupWindowController: NSObject, NSWindowDelegate {
    private let coordinator: SetupCoordinator
    private let model: SetupModel
    private var window: NSWindow?
    /// Whether the app has begun to quit, which is the notice that comes before AppKit closes
    /// the windows (`windowWillClose(_:)`).
    private var appIsQuitting = false
    private var terminationObserver: NSObjectProtocol?

    /// Told that the window has closed, once the close has been recorded and the model has
    /// dropped the visit's sentence. The app delegate sets it, to read the setup facts again
    /// for the one reader the window does not feed, Settings' line, which says where the guide
    /// stands and which a close changes (M5 plan, Task 8). It chooses nothing from the close.
    var didClose: () -> Void = {}

    init(coordinator: SetupCoordinator) {
        self.coordinator = coordinator
        model = SetupModel(coordinator: coordinator)
        super.init()
        model.closeWindow = { [weak self] in self?.window?.close() }
        // Held for as long as the app runs, which is as long as this does. Heard where it is
        // posted, with no queue, so that it has been heard before the windows are closed.
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: nil) { [weak self] _ in
            MainActor.assumeIsolated { self?.appIsQuitting = true }
        }
    }

    /// What the window reports of itself, which the core makes its answers from.
    private var presence: SetupPlan.WindowPresence {
        SetupPlan.WindowPresence(isVisible: window?.isVisible ?? false,
                                 isMinimised: window?.isMiniaturized ?? false)
    }

    /// What the menu's nudge is handed as whether the guide's window is open: true only
    /// while it is on screen, and not while it is minimised or closed.
    var isOpenForTheNudge: Bool { presence.isOpenForTheNudge }

    /// Records the start, reads the facts after it, and brings the window forward, making it
    /// first if it is not there.
    func show() {
        let facts = coordinator.willShowGuide()
        model.refresh(from: facts)
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 900, height: 640),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = WindowTitles.setupGuide
            window.contentView = NSHostingView(rootView: SetupView(model: model))
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }

        NSApp.activate(ignoringOtherApps: true)
        if window?.isMiniaturized == true { window?.deminiaturize(nil) }
        window?.makeKeyAndOrderFront(nil)
    }

    /// Brings what the window shows up to date with what the app holds now, while it is open,
    /// and does nothing to the window: a closed one is not opened by this, and records no
    /// start.
    func refresh() {
        refresh(from: coordinator.facts())
    }

    /// The same, from facts the caller has gathered already, for the app delegate when it has
    /// made them for another purpose (the menu's nudge) and one pass should read one set of
    /// them. They must be gathered after the rules are loaded (`SetupFacts.ruleStatus`).
    func refresh(from facts: SetupFacts) {
        guard presence.isKeptUpToDate else { return }
        model.refresh(from: facts)
    }

    /// Coming to the front reads again, because it is how the user is seen to come back from
    /// System Settings after granting Accessibility, or from the rule editor after making a
    /// rule. Showing the window comes to the front too, and reads the same facts again.
    func windowDidBecomeKey(_ notification: Notification) {
        refresh()
    }

    /// Every way the user closes the window is a dismissal, and the quit's close is not (the
    /// core says which, `SetupPlan.closeIsDismissal(appIsQuitting:)`). Any close ends the visit.
    func windowWillClose(_ notification: Notification) {
        coordinator.guideDidClose(appIsQuitting: appIsQuitting)
        model.windowDidClose()
        didClose()
    }
}
