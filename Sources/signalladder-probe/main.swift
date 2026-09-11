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

// Banner animation fires kAXWindowMoved repeatedly for the SAME banner, so
// some collapsing is required. But text equality cannot distinguish that from
// two genuinely distinct notifications carrying identical text, so every
// suppression is REPORTED rather than silent — a probe that quietly loses
// evidence is worse than one that is noisy.
//
// Production dedupe must key on element identity instead of content. That
// needs identity plumbed through AccessibilityNode and belongs with the real
// pipeline, not this diagnostic.
var recentlySeen: [String: (first: Date, suppressed: Int)] = [:]
let dedupeWindow: TimeInterval = 1.5

let watcher = AXBannerWatcher { raw, textChildren in
    let now = raw.timestamp
    recentlySeen = recentlySeen.filter { now.timeIntervalSince($0.value.first) < dedupeWindow }

    if var seen = recentlySeen[raw.rawText] {
        seen.suppressed += 1
        recentlySeen[raw.rawText] = seen
        FileHandle.standardError.write(
            "[dedupe] suppressed repeat #\(seen.suppressed) within \(dedupeWindow)s — \(raw.rawText.debugDescription)\n"
                .data(using: .utf8)!
        )
        return
    }
    recentlySeen[raw.rawText] = (first: now, suppressed: 0)

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
