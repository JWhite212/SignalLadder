// Sources/signalladder-probe/main.swift
import Foundation
import ApplicationServices

let trusted = AXIsProcessTrusted()
FileHandle.standardError.write(
    "signalladder-probe — Accessibility trusted: \(trusted)\n".data(using: .utf8)!
)

if !trusted {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
    _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    FileHandle.standardError.write(
        "Grant Accessibility to this binary, then re-run.\n".data(using: .utf8)!
    )
    exit(1)
}

FileHandle.standardError.write("Trusted. Exiting (no watcher yet).\n".data(using: .utf8)!)
