// Sources/SignalLadder/MuteWalkthroughMenu.swift
import AppKit
import NotificationCore

/// The mute walkthrough in the menu (§8.2): each app a sounding rule reaches,
/// a link to that app's notification settings, and the user's confirmation
/// that its own sound is off — kept by `MuteChecklistStore`, because it is the
/// only record there is (as digests: see `MuteChecklist`), and shown as the
/// user's word because nothing can check it.
///
/// Ships with the first sound (§12): without it, every alert plays on top of
/// the source app's own ping and the app feels broken.
@MainActor
final class MuteWalkthroughMenu: NSObject {
    private let store: MuteChecklistStore

    init(store: MuteChecklistStore) {
        self.store = store
    }

    /// Adds nothing when no app needs muting: with no sounding rule, there is
    /// no sound for the source app's own to double.
    func add(to menu: NSMenu, apps: [String]) {
        guard !apps.isEmpty else { return }
        let walkthrough = NSMenu()

        for line in MuteWalkthroughText.explanation {
            walkthrough.addItem(withTitle: line, action: nil, keyEquivalent: "")
        }
        walkthrough.addItem(.separator())
        for app in apps {
            walkthrough.addItem(item(for: app))
        }

        walkthrough.addItem(.separator())
        for line in MuteWalkthroughText.focus {
            walkthrough.addItem(withTitle: line, action: nil, keyEquivalent: "")
        }
        let focus = NSMenuItem(title: MuteWalkthroughText.openFocusSettings,
                               action: #selector(openFocusSettings), keyEquivalent: "")
        focus.target = self
        walkthrough.addItem(focus)

        let top = NSMenuItem(title: MuteWalkthroughText.title(apps: apps, checklist: store.checklist),
                             action: nil, keyEquivalent: "")
        top.submenu = walkthrough
        menu.addItem(top)
    }

    private func item(for app: String) -> NSMenuItem {
        let confirmed = store.checklist.isConfirmed(app)
        let actions = NSMenu()

        let open = NSMenuItem(title: MuteWalkthroughText.openSettings(app),
                              action: #selector(openSettings(_:)), keyEquivalent: "")
        open.target = self
        open.representedObject = app
        actions.addItem(open)

        let confirm = NSMenuItem(title: MuteWalkthroughText.confirm,
                                 action: #selector(toggleConfirmed(_:)), keyEquivalent: "")
        confirm.target = self
        confirm.representedObject = app
        confirm.state = confirmed ? .on : .off
        actions.addItem(confirm)

        let item = NSMenuItem(title: MuteWalkthroughText.appItem(app, confirmed: confirmed),
                              action: nil, keyEquivalent: "")
        item.submenu = actions
        return item
    }

    /// Resolves the bundle ID only now, when asked: the folder scan reads the
    /// disk, and nothing else needs it.
    @objc private func openSettings(_ sender: NSMenuItem) {
        guard let app = sender.representedObject as? String else { return }
        let resolution = BundleResolver.resolve(app, running: AppLocator.running(), installed: AppLocator.installed)

        // No unique match: the pane opens at its top, so the name the user
        // must look for goes on screen first (§8.2).
        if let fallback = MuteWalkthroughText.lookupFallback(app, resolution) {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = fallback.title
            alert.informativeText = fallback.body
            alert.runModal()
        }
        NSWorkspace.shared.open(BundleResolver.notificationSettingsURL(for: resolution))
    }

    @objc private func toggleConfirmed(_ sender: NSMenuItem) {
        guard let app = sender.representedObject as? String else { return }
        store.setConfirmed(app, !store.checklist.isConfirmed(app))
    }

    @objc private func openFocusSettings() {
        NSWorkspace.shared.open(BundleResolver.focusSettingsURL)
    }
}
