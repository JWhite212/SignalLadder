// Sources/signalladder-probe/main.swift
import Foundation
import ApplicationServices
import NotificationCore
import NotificationCapture

guard AXIsProcessTrusted() else {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
    _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    print("Not trusted. Grant Accessibility to this binary and re-run.")
    exit(1)
}

// Notification text is not printed unless asked for.
//
// The spec's privacy rule (§2.1) is written about the running app, and this is
// a developer tool — but its output is a terminal, and terminals get scrolled
// back, pasted into bug reports and redirected to files. Printing every
// notification's text by default made this the one place in the project where
// content routinely left memory without anyone deciding it should.
//
// The app name and subrole are shown regardless: they are metadata, and the
// probe's job — seeing what shape a banner arrives in — needs them.
let showContent = CommandLine.arguments.contains("--show-content")

func shown(_ text: String) -> String {
    if showContent { return text.debugDescription }
    return text.isEmpty ? "(empty)" : "<\(text.count) characters>"
}

// Banner animation fires kAXWindowMoved repeatedly for the SAME banner, so
// some collapsing is required. But text equality cannot distinguish that from
// two genuinely distinct notifications carrying identical text, so every
// suppression is REPORTED rather than silent — a probe that quietly loses
// evidence is worse than one that is noisy.
let dedupe = CaptureDeduplicator()

let watcher = AXBannerWatcher { raw, textChildren in
    let decision = dedupe.admit(raw.rawText, at: raw.timestamp)
    if decision.isRepeat {
        FileHandle.standardError.write(
            "[dedupe] suppressed repeat #\(decision.repeatCount) — \(shown(raw.rawText))\n"
                .data(using: .utf8)!
        )
        return
    }

    let n = NotificationFieldExtractor.extract(raw, textChildren: textChildren)
    print("""
    ─────────────────────────────────────────
      app       \(n.appNameGuess.isEmpty ? "(none)" : n.appNameGuess)
      title     \(shown(n.title))
      subtitle  \(shown(n.subtitle))
      body      \(shown(n.body))
      subrole   \(n.subrole)
      children  \(textChildren.count)
      raw       \(shown(n.rawText))
    """)
}

watcher.start()
print("Watching for notifications. Ctrl-C to stop.")
print(showContent
      ? "Showing notification text (--show-content).\n"
      : "Notification text is hidden; pass --show-content to print it.\n")
CFRunLoopRun()
