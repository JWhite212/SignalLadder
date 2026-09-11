// Sources/SignalLadder/main.swift
import AppKit

// Explicit NSApplication bootstrap rather than @main: the watcher's
// dispatchPrecondition requires attach to happen on the main queue with a
// running main run loop, and this makes that ordering obvious.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // menu-bar only, no Dock icon
app.run()
