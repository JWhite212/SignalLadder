// Sources/SignalLadder/AppDelegate.swift
import AppKit
import ApplicationServices

/// Menu-bar-only controller. NSStatusItem rather than SwiftUI's MenuBarExtra:
/// the spec requires a dynamically-updating title and a swappable icon, which
/// MenuBarExtra has historically handled poorly. Revisit if that changes.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let capture = CaptureController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()

        guard AXIsProcessTrusted() else {
            // Full onboarding arrives in M2b. For now the menu states the
            // problem rather than the app pretending to work.
            updateMenu(trusted: false)
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
            return
        }

        capture.onChange = { [weak self] in self?.updateMenu(trusted: true) }
        capture.start()
        updateMenu(trusted: true)
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "bell.badge",
            accessibilityDescription: "SignalLadder"
        )
        item.menu = NSMenu()
        statusItem = item
    }

    private func updateMenu(trusted: Bool) {
        guard let menu = statusItem?.menu else { return }
        menu.removeAllItems()

        if trusted {
            let count = capture.captureCount
            menu.addItem(withTitle: "Captured \(count) notification\(count == 1 ? "" : "s")",
                         action: nil, keyEquivalent: "")
            if let last = capture.lastCaptureAt {
                let formatter = DateFormatter()
                formatter.timeStyle = .medium
                menu.addItem(withTitle: "Last at \(formatter.string(from: last))",
                             action: nil, keyEquivalent: "")
            }
        } else {
            let item = NSMenuItem(title: "Accessibility permission needed",
                                  action: #selector(openAccessibilitySettings),
                                  keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit SignalLadder",
                              action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        menu.addItem(quit)
    }

    @objc private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
