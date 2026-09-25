// docs/dev/spikes/alert-panel.swift — two of §11's M4 assumptions, in one small app:
//   1. A borderless, non-activating NSPanel with .canJoinAllSpaces and .fullScreenAuxiliary
//      follows the user across Spaces and shows over full-screen apps without taking focus (§5.17).
//   2. A global hotkey can acknowledge without an Input Monitoring grant (§11).
//
// Build as an accessory app (as app-nap-timers.swift describes), then run:
//   open -g AlertPanelSpike.app --args <out.jsonl>
// It measures what it can itself — whether showing the panel changed the frontmost app, whether
// the window server has it on screen and at what level, whether the hotkey registered — and
// leaves to a person what only a person can see: the panel over a full-screen app, on another
// Space, and whether pressing ⌃⌥⌘A asks for any permission. Quits after five minutes.
import AppKit
import Carbon.HIToolbox

let out = URL(fileURLWithPath: CommandLine.arguments[1])
FileManager.default.createFile(atPath: out.path, contents: nil)
let handle = try! FileHandle(forWritingTo: out)
func record(_ event: String, _ detail: String = "") {
    let line = "{\"t\":\"\(ISO8601DateFormatter().string(from: Date()))\",\"event\":\"\(event)\",\"detail\":\"\(detail)\"}\n"
    handle.write(Data(line.utf8))
}

final class Spike: NSObject, NSApplicationDelegate {
    var panel: NSPanel!
    var hotKey: EventHotKeyRef?

    func applicationDidFinishLaunching(_ note: Notification) {
        let before = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "none"

        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main!
        let size = NSSize(width: 420, height: 150)
        let origin = NSPoint(x: screen.visibleFrame.maxX - size.width - 20, y: screen.visibleFrame.maxY - size.height - 20)
        panel = NSPanel(contentRect: NSRect(origin: origin, size: size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .windowBackgroundColor
        panel.hasShadow = true

        let text = NSTextField(wrappingLabelWithString:
            "SignalLadder panel test. Does this appear over a full-screen app, and on every Space? "
            + "Press ⌃⌥⌘A, or click Acknowledge, to close it.")
        text.frame = NSRect(x: 16, y: 56, width: size.width - 32, height: 80)
        let button = NSButton(title: "Acknowledge", target: self, action: #selector(acknowledgedByClick))
        button.frame = NSRect(x: size.width - 136, y: 14, width: 120, height: 30)
        panel.contentView?.addSubview(text)
        panel.contentView?.addSubview(button)
        panel.orderFrontRegardless()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            let after = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "none"
            record("shown", "frontmost before=\(before) after=\(after) — unchanged means non-activating: \(before == after)")
            let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
            let mine = windows.filter { ($0[kCGWindowOwnerPID as String] as? Int32) == getpid() }
            record("window-server", "on screen: \(!mine.isEmpty), layer: \(mine.first?[kCGWindowLayer as String] ?? "none")")
        }

        registerHotKey()
        DispatchQueue.main.asyncAfter(deadline: .now() + 300) { record("quit", "five minutes passed"); NSApp.terminate(nil) }
    }

    /// Carbon's RegisterEventHotKey: a system-wide shortcut delivered to this app alone.
    func registerHotKey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            let me = Unmanaged<Spike>.fromOpaque(context!).takeUnretainedValue()
            me.acknowledged(by: "hotkey")
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)
        let id = EventHotKeyID(signature: OSType(0x534C4144), id: 1)   // "SLAD"
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_A), UInt32(controlKey | optionKey | cmdKey), id,
                                         GetApplicationEventTarget(), 0, &hotKey)
        record("hotkey-registered", "handler=\(installed) register=\(status) — 0 means success")
    }

    @objc func acknowledgedByClick() { acknowledged(by: "click") }

    func acknowledged(by how: String) {
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "none"
        record("acknowledged", "by \(how); frontmost now=\(front)")
        panel.orderOut(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { NSApp.terminate(nil) }
    }
}

let app = NSApplication.shared
let delegate = Spike()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
