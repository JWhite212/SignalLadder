// Sources/signalladder-probe/main.swift
import Foundation
import ApplicationServices
import AppKit
import NotificationCore

guard AXIsProcessTrusted() else {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
    _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    print("Not trusted. Grant Accessibility to this binary and re-run.")
    exit(1)
}

// Deduplicates the repeat callbacks that fire as a banner animates in
// (kAXWindowMovedNotification arrives several times per notification).
var recentlySeen: [String: Date] = [:]
let dedupeWindow: TimeInterval = 5.0

let watcher = AXBannerWatcher { raw, textChildren in
    let now = raw.timestamp
    recentlySeen = recentlySeen.filter { now.timeIntervalSince($0.value) < dedupeWindow }
    if let last = recentlySeen[raw.rawText], now.timeIntervalSince(last) < dedupeWindow {
        return
    }
    recentlySeen[raw.rawText] = now

    let n = NotificationFieldExtractor.extract(raw, textChildren: textChildren)
    print("""
    ─────────────────────────────────────────
      app       \(n.appNameGuess.isEmpty ? "(none)" : n.appNameGuess)
      title     \(n.title)
      subtitle  \(n.subtitle.isEmpty ? "(none)" : n.subtitle)
      body      \(n.body.isEmpty ? "(none)" : n.body)
      subrole   \(n.subrole)
      children  \(textChildren.count)
      raw       \(n.rawText.debugDescription)
    """)
}

watcher.start()
print("Watching for notifications. Ctrl-C to stop.\n")
CFRunLoopRun()
