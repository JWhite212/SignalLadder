// Sources/SignalLadder/HotKeyController.swift
import Carbon.HIToolbox
import os

/// ⌃⌥⌘A, anywhere: acknowledges every listed escalation, as the menu's
/// Acknowledge does (M4 plan, ruling 16).
///
/// Best effort, never a dependency. Registered with Carbon's
/// `RegisterEventHotKey`, which a person found needs no Input Monitoring grant
/// on macOS 26.7 (findings, 2026-09-29); another version could behave
/// differently, so a failure to register is logged and otherwise ignored, and
/// the menu and the panel's buttons remain the ways that need no permission.
@MainActor
final class HotKeyController {
    private let onPress: () -> Void
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private static let log = Logger(subsystem: "com.jamiewhite.signalladder", category: "hotkey")

    init(onPress: @escaping () -> Void) {
        self.onPress = onPress
    }

    /// Registers the hotkey once. A non-zero status is logged, and then
    /// nothing else happens.
    func register() {
        guard hotKey == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return noErr }
            // A C callback with no actor of its own. Carbon delivers it on the
            // main thread, so the main actor is taken directly, never through
            // a hop an acknowledgement could arrive behind (ruling 2).
            MainActor.assumeIsolated {
                Unmanaged<HotKeyController>.fromOpaque(context).takeUnretainedValue().onPress()
            }
            return noErr
        }, 1, &spec, context, &handler)
        guard installed == noErr else {
            Self.log.error("the acknowledge hotkey's handler could not be installed: \(installed, privacy: .public)")
            return
        }
        let id = EventHotKeyID(signature: OSType(0x534C_4144), id: 1)  // "SLAD"
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_A), UInt32(controlKey | optionKey | cmdKey), id,
                                         GetApplicationEventTarget(), 0, &hotKey)
        if status != noErr {
            Self.log.error("the acknowledge hotkey ⌃⌥⌘A could not be registered: \(status, privacy: .public)")
        }
    }
}
