// Sources/SignalLadder/main.swift
import AppKit

// Explicit NSApplication bootstrap rather than @main: the watcher's
// dispatchPrecondition requires attach to happen on the main queue with a
// running main run loop, and this makes that ordering obvious.
//
// main.swift's top-level code always runs on the main thread before any run
// loop starts, so asserting main-actor isolation here (needed now that
// AppDelegate is @MainActor) is safe rather than merely convenient.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)   // menu-bar only, no Dock icon
    app.run()
}
