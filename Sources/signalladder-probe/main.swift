// Sources/signalladder-probe/main.swift
import Foundation
import ApplicationServices
import AppKit

func attr(_ element: AXUIElement, _ name: String) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success
    else { return nil }
    if let s = value as? String { return s }
    if let a = value as? NSAttributedString { return a.string }
    return nil
}

func children(_ element: AXUIElement) -> [AXUIElement] {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
          let array = value as? [AXUIElement]
    else { return [] }
    return array
}

func dump(_ element: AXUIElement, depth: Int, budget: inout Int) {
    guard depth <= 12, budget > 0 else { return }
    budget -= 1

    let role = attr(element, kAXRoleAttribute as String) ?? "?"
    let subrole = attr(element, kAXSubroleAttribute as String) ?? "-"
    let desc = attr(element, "AXAttributedDescription")
        ?? attr(element, kAXDescriptionAttribute as String)
        ?? ""
    let title = attr(element, kAXTitleAttribute as String) ?? ""
    let value = attr(element, kAXValueAttribute as String) ?? ""

    let pad = String(repeating: "  ", count: depth)
    let parts = [
        "role=\(role)",
        subrole == "-" ? nil : "subrole=\(subrole)",
        desc.isEmpty ? nil : "desc=\(desc.debugDescription)",
        title.isEmpty ? nil : "title=\(title.debugDescription)",
        value.isEmpty ? nil : "value=\(value.debugDescription)",
    ].compactMap { $0 }
    print("\(pad)\(parts.joined(separator: " "))")

    for child in children(element) {
        dump(child, depth: depth + 1, budget: &budget)
    }
}

guard AXIsProcessTrusted() else {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
    _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    print("Not trusted. Grant Accessibility and re-run.")
    exit(1)
}

guard let app = NSWorkspace.shared.runningApplications.first(
    where: { $0.bundleIdentifier == "com.apple.notificationcenterui" }
) else {
    print("com.apple.notificationcenterui is not running.")
    exit(1)
}

print("Found notificationcenterui pid=\(app.processIdentifier)")
let root = AXUIElementCreateApplication(app.processIdentifier)
AXUIElementSetMessagingTimeout(root, 0.2)

print("Polling every 1s. Trigger a notification. Ctrl-C to stop.\n")
while true {
    var value: CFTypeRef?
    let err = AXUIElementCopyAttributeValue(root, kAXWindowsAttribute as CFString, &value)
    let windows = (value as? [AXUIElement]) ?? []
    if err != .success {
        print("[\(Date())] kAXWindowsAttribute error: \(err.rawValue)")
    } else if windows.isEmpty {
        // No banner on screen right now — expected when idle.
    } else {
        print("[\(Date())] \(windows.count) window(s):")
        for window in windows {
            var budget = 256
            dump(window, depth: 1, budget: &budget)
        }
        print("")
    }
    Thread.sleep(forTimeInterval: 1.0)
}
