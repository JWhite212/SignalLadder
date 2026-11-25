// Sources/SignalLadder/StatusPopoverController.swift
import AlertPanel
import AppKit
import NotificationCore
import SwiftUI

/// Shows the status item's popover and closes it (M7 plan, Stage 5).
///
/// The popover is a panel of its own beneath the item, and not an `NSPopover`,
/// whose arrow and edge are the system's and would not be navy. It takes the
/// keyboard, so that Esc, Tab and the menu's keys work in it, and does not
/// activate the app, so the app the user was in stays in front, as it does
/// behind a menu.
///
/// It closes on Esc, on a second click of the item, when a control in it is
/// chosen, and when the keyboard goes elsewhere, which is what a click outside
/// it and another app coming forward both do. A click in another app is
/// watched for as well, since that app's window need not take the keyboard.
///
/// Its ground is the panel's: the navy, or the system's glass where the app
/// asks for it and this Mac has it (M7 plan, Stage 7). It is built again each
/// time it opens, so it is drawn with whatever was asked for then.
///
/// What it shows is made by the core and handed over whole. This decides
/// nothing about it and holds no word.
@MainActor
final class StatusPopoverController: NSObject, NSWindowDelegate {
    private var panel: Panel?
    private var onClose: (() -> Void)?
    private var clickMonitor: Any?

    private static let gap: CGFloat = 6
    private static let margin: CGFloat = 8

    var isShown: Bool { panel != nil }

    /// When the popover last closed, by the system's uptime, which is the clock
    /// an event's own time is on.
    private var closedAt: TimeInterval?

    /// How long ago it closed, nil when it has not closed since it was last shown.
    var sinceClosed: TimeInterval? {
        closedAt.map { ProcessInfo.processInfo.systemUptime - $0 }
    }

    /// - Parameters:
    ///   - title: what VoiceOver calls the window.
    ///   - button: the status item's button, which the popover hangs beneath.
    ///   - ground: what the ground is drawn with; solid where glass cannot be made.
    ///   - perform: carries out a control's action, after the popover has closed.
    ///   - onClose: told once, however it closed, before any action is carried out.
    func show(_ content: StatusPopover.Content, title: String, below button: NSView,
              ground wanted: PanelGround.Material = .solid,
              perform: @escaping (StatusPopover.Action) -> Void, onClose: @escaping () -> Void) {
        close()
        let chosen: (StatusPopover.Action) -> Void = { [weak self] action in
            self?.close()
            perform(action)
        }
        // Measured at its own width with no limit on its height; if the screen
        // has less room than that, the rows scroll in the room there is.
        let needed = NSHostingController(rootView: StatusPopoverView(content: content, perform: chosen))
            .sizeThatFits(in: NSSize(width: StatusPopoverView.width, height: .greatestFiniteMagnitude))
        let frame = Self.frame(fitting: needed, below: button.window)
        let ground = PanelGroundView(cornerRadius: StatusPopoverView.corner)
        ground.use(wanted)
        let host = NSHostingView(rootView: StatusPopoverView(content: content, scrolls: frame.height < needed.height,
                                                             ground: GroundMaterial(ground.material), perform: chosen))
        host.frame = ground.holder.bounds
        host.autoresizingMask = [.width, .height]
        ground.holder.addSubview(host)
        let panel = Panel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                          backing: .buffered, defer: true)
        panel.title = title
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary, .moveToActiveSpace]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.contentView = ground
        panel.onCancel = { [weak self] in self?.close() }
        panel.onCommandKey = { character in
            guard let action = content.action(forCommandKey: character) else { return false }
            chosen(action)
            return true
        }
        panel.setFrame(frame, display: false)
        panel.delegate = self
        self.panel = panel
        self.onClose = onClose
        closedAt = nil
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
        panel.makeKeyAndOrderFront(nil)
        // With Keyboard navigation on, a window that takes the keyboard gives
        // it to its first control, which would open the popover with a ring
        // round that control and Space pressing it. A menu opens with nothing
        // chosen, and so does this: the window holds the keyboard itself until
        // Tab is pressed, which goes to the first control as it would have.
        panel.makeFirstResponder(nil)
        panel.invalidateShadow()
    }

    func close() {
        guard let panel else { return }
        self.panel = nil
        closedAt = ProcessInfo.processInfo.systemUptime
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
        panel.delegate = nil
        panel.orderOut(nil)
        let closed = onClose
        onClose = nil
        closed?()
    }

    func windowDidResignKey(_ notification: Notification) {
        close()
    }

    /// Beneath the item, centred on it, and kept on its screen: no wider than
    /// the screen's edge allows and no taller than the room under the menu bar,
    /// where the view scrolls what does not fit.
    private static func frame(fitting size: NSSize, below anchor: NSWindow?) -> NSRect {
        guard let anchor, let screen = anchor.screen ?? NSScreen.main else {
            return NSRect(origin: .zero, size: size)
        }
        let visible = screen.visibleFrame
        let top = min(anchor.frame.minY, visible.maxY) - gap
        let height = min(size.height, max(0, top - visible.minY - margin))
        let x = min(max(anchor.frame.midX - size.width / 2, visible.minX + margin), visible.maxX - size.width - margin)
        return NSRect(x: x, y: top - height, width: size.width, height: height)
    }

    /// A borderless panel does not take the keyboard unless it says it can.
    private final class Panel: NSPanel {
        var onCancel: (() -> Void)?
        var onCommandKey: ((String) -> Bool)?

        private static let escape: UInt16 = 53

        override var canBecomeKey: Bool { true }

        override func cancelOperation(_ sender: Any?) {
            onCancel?()
        }

        override func keyDown(with event: NSEvent) {
            guard event.keyCode == Self.escape else { return super.keyDown(with: event) }
            onCancel?()
        }

        /// The menu's keys, which the menu no longer answers while it is not open.
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            // Caps Lock is no part of a key, as it is none of a menu's.
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock) == .command,
               let character = event.charactersIgnoringModifiers, onCommandKey?(character) == true {
                return true
            }
            return super.performKeyEquivalent(with: event)
        }
    }
}
