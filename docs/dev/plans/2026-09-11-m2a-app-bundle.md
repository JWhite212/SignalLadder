# M2a App Bundle Implementation Plan

**Goal:** Turn the CLI probe into a signed, menu-bar-only `.app` bundle that captures notifications, and fix the two dormant re-attach defects that activate the moment it becomes a bundled app.

**Architecture:** The capture layer moves out of the probe target into a shared `NotificationCapture` target, so both the CLI probe and the new app consume it. A hand-written `Scripts/make-app.sh` assembles `SignalLadder.app` from the SPM-built binary, writes `Info.plist`, and signs with the Developer ID identity. No `.xcodeproj` — `Package.swift` stays the single source of truth, and Xcode can still open it for editing and SwiftUI previews.

**Tech Stack:** Swift 5.9+, Swift Package Manager, XCTest, AppKit (`NSStatusItem`, `NSApplication`), ApplicationServices.

**Spec:** `docs/dev/specs/2026-09-11-macos-notification-router-design.md`
**Prior milestone:** `docs/dev/notes/2026-09-11-m1-findings.md`, `docs/dev/notes/2026-09-11-m2-handover.md`

## Global Constraints

- **Minimum macOS: 14.0 Sonoma.** `Package.swift` declares `.macOS(.v14)`; `Info.plist` declares `LSMinimumSystemVersion` 14.0. Must also run on macOS 15 and 26.
- **No third-party dependencies.** `Package.swift` `dependencies` array stays empty.
- **Notification content is never written to disk** by the running program.
- **`NotificationCore` must not import `ApplicationServices`, `AppKit`, `Cocoa`, or `Carbon`.** Enforced by `PurityTests`.
- **Menu-bar only:** `LSUIElement` is `true`. No Dock icon, no main window.
- **Event-driven, never polling.** Near-zero idle CPU.
- **Bundle identifier: `com.jamiewhite.signalladder`.** Signing identity: `Developer ID Application: Jamie White (RVVRP4WY6B)`, SHA-1 `0C46A31C354444B7CC472CD29DE37303A090E844`.
- **Hardened Runtime enabled** (`--options runtime`), sandbox **off**.

---

## File Structure

```
Package.swift                                       +2 targets: NotificationCapture, SignalLadder
Sources/NotificationCore/…                          unchanged (pure)
Sources/NotificationCapture/AXElementNode.swift      MOVED from signalladder-probe
Sources/NotificationCapture/AXBannerWatcher.swift    MOVED from signalladder-probe
Sources/signalladder-probe/main.swift                now a thin client of NotificationCapture
Sources/SignalLadder/main.swift                      app entry, NSApplication bootstrap
Sources/SignalLadder/AppDelegate.swift               NSStatusItem, menu, lifecycle
Sources/SignalLadder/CaptureController.swift         owns the watcher, exposes capture count
Resources/Info.plist                                 bundle metadata, LSUIElement
Scripts/make-app.sh                                  bundle assembly + signing
Tests/NotificationCoreTests/…                        unchanged
```

The probe is **kept**, not retired. It stays the fastest way to see raw capture output without launching a UI, and it is the only consumer that proves `NotificationCapture` works without AppKit app infrastructure.

---

## Task 1: Extract the capture layer into a shared target

Moves the two AX files so both the probe and the app can use them. Pure restructuring — no behaviour change, and the probe must still work identically afterwards.

**Files:**

- Modify: `Package.swift`
- Move: `Sources/signalladder-probe/AXElementNode.swift` → `Sources/NotificationCapture/AXElementNode.swift`
- Move: `Sources/signalladder-probe/AXBannerWatcher.swift` → `Sources/NotificationCapture/AXBannerWatcher.swift`
- Modify: `Sources/signalladder-probe/main.swift`

**Interfaces:**

- Consumes: `NotificationCore` (`RawCapture`, `BannerTreeLocator`, `BannerTextReader`, `AccessibilityNode`)
- Produces: target `NotificationCapture` exporting `AXElementNode` and `AXBannerWatcher` as **public** API

- [ ] **Step 1: Add the target to Package.swift**

Replace the `targets:` array with:

```swift
    targets: [
        .target(name: "NotificationCore"),
        .target(
            name: "NotificationCapture",
            dependencies: ["NotificationCore"]
        ),
        .executableTarget(
            name: "signalladder-probe",
            dependencies: ["NotificationCore", "NotificationCapture"]
        ),
        .testTarget(
            name: "NotificationCoreTests",
            dependencies: ["NotificationCore"]
        ),
    ]
```

- [ ] **Step 2: Move the two files**

Plain `mv`, not `git mv` — the implementer has no git access, and the controller's staging detects the rename anyway.

```bash
mkdir -p Sources/NotificationCapture
mv Sources/signalladder-probe/AXElementNode.swift Sources/NotificationCapture/AXElementNode.swift
mv Sources/signalladder-probe/AXBannerWatcher.swift Sources/NotificationCapture/AXBannerWatcher.swift
```

Update the `// Sources/…` path comment at the top of each moved file to its new location.

- [ ] **Step 3: Make the moved types public**

Both were internal because they lived in the same target as their only consumer. They now cross a module boundary.

In `AXElementNode.swift`, change `struct AXElementNode: AccessibilityNode {` to `public struct AXElementNode: AccessibilityNode {`, and mark `public` : the `init(_ element: AXUIElement)`, and the `subrole`, `attributedDescription`, `value` and `children` properties. Leave `stringAttribute` private.

In `AXBannerWatcher.swift`, change `final class AXBannerWatcher {` to `public final class AXBannerWatcher {`, and mark `public` : `init(onCapture:)` and `start()`. Everything else stays private.

Add `import NotificationCore` to both files if not already present.

- [ ] **Step 4: Add the import to the probe**

At the top of `Sources/signalladder-probe/main.swift`, add `import NotificationCapture` beneath the existing `import NotificationCore`.

- [ ] **Step 5: Build and test**

Run: `swift build` then `swift test`
Expected: build clean with zero warnings; 32 tests, 0 failures.

If the build reports "initializer is inaccessible" or similar, a member was missed in Step 3 — make it `public`, do not work around it by relocating code.

- [ ] **Step 6: Verify the probe is unchanged**

```bash
swift build && codesign --force --options runtime --identifier com.jamiewhite.signalladder.probe --sign 0C46A31C354444B7CC472CD29DE37303A090E844 .build/debug/signalladder-probe
```

Expected: builds and signs. Running it is a human step — the controller will ask.

- [ ] **Step 7: Commit**

```bash
git add Package.swift Sources/
git commit -m "refactor: extract capture layer into a shared target"
```

---

## Task 2: Fix the two re-attach defects that activate on bundling

Both are dormant only because `NSWorkspace` notifications never fire in a CLI process. In a bundled app they will, so both must be fixed before the app exists — not after they produce mystery flakes.

**Files:**

- Modify: `Sources/NotificationCapture/AXBannerWatcher.swift`

**Interfaces:**

- Consumes: nothing new
- Produces: no API change

- [ ] **Step 1: Route the NSWorkspace handler through the backoff**

The process-exit handler calls `scheduleReattach()` and respects backoff; the `NSWorkspace` handler calls `attach()` directly and bypasses it. Once both fire, that produces one immediate attach plus one delayed attach that tears down a freshly-healthy observer.

In `observeWorkspace()`, change `self.attach()` to `self.scheduleReattach()`, and update the log line:

```swift
                self.log("notificationcenterui lifecycle event; scheduling re-attach")
                self.scheduleReattach()
```

Also update the method's doc comment: it currently says the observer is inert. Replace that comment with:

```swift
        // A SECONDARY signal. It does not fire in the CLI probe — verified by
        // live testing on macOS 26.7 — but does fire inside a bundled app.
        // Both paths route through scheduleReattach() so that when both are
        // live they coalesce on the same timer instead of racing.
```

- [ ] **Step 2: Add a cancellation token for pending retries**

A stale retry can fire after a successful attach and tear down a healthy observer. With two signals now feeding `scheduleReattach()`, this stops being theoretical.

Add the stored property beside `processSource`:

```swift
    private var pendingReattach: DispatchWorkItem?
```

Replace `scheduleReattach()` entirely with:

```swift
    /// Exponential backoff, capped, so a permanently-absent process does not
    /// spin. Any pending retry is cancelled first: with two independent
    /// re-attach signals, a stale timer would otherwise fire after a
    /// successful attach and tear down a healthy observer to rebuild it.
    private func scheduleReattach() {
        pendingReattach?.cancel()

        let delay = reattachDelay
        reattachDelay = min(reattachDelay * 2, 30)

        let work = DispatchWorkItem { [weak self] in
            self?.pendingReattach = nil
            self?.attach()
        }
        pendingReattach = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
```

- [ ] **Step 3: Cancel pending retries on successful attach**

In `attach()`, immediately after the line `reattachDelay = 1.0`, add:

```swift
        pendingReattach?.cancel()
        pendingReattach = nil
```

- [ ] **Step 4: Cancel on teardown**

In `detach()`, alongside the existing `processSource` cancellation at the top, add:

```swift
        pendingReattach?.cancel()
        pendingReattach = nil
```

- [ ] **Step 5: Build and test**

Run: `swift build` then `swift test`
Expected: build clean with zero warnings; 32 tests, 0 failures. This task adds no tests — the behaviour needs a live process restart, which is verified in Task 5.

- [ ] **Step 6: Commit**

```bash
git add Sources/NotificationCapture/AXBannerWatcher.swift
git commit -m "fix: coalesce the two re-attach signals before bundling activates both"
```

---

## Task 3: The app target

A menu-bar-only AppKit app that owns the capture pipeline and shows a status item.

**Files:**

- Modify: `Package.swift`
- Create: `Sources/SignalLadder/main.swift`
- Create: `Sources/SignalLadder/AppDelegate.swift`
- Create: `Sources/SignalLadder/CaptureController.swift`

**Interfaces:**

- Consumes: `NotificationCore`, `NotificationCapture`
- Produces: executable product `SignalLadder`

- [ ] **Step 1: Add the target and product**

In `Package.swift`, add a `products:` array between `platforms:` and `targets:`:

```swift
    products: [
        .executable(name: "SignalLadder", targets: ["SignalLadder"]),
    ],
```

and add to `targets:`:

```swift
        .executableTarget(
            name: "SignalLadder",
            dependencies: ["NotificationCore", "NotificationCapture"]
        ),
```

- [ ] **Step 2: Write the capture controller**

```swift
// Sources/SignalLadder/CaptureController.swift
import Foundation
import NotificationCore
import NotificationCapture

/// Owns the capture pipeline and exposes just enough state for the UI.
///
/// Deliberately does not retain notification content: M2a only needs to prove
/// the app captures at all. The Inspector's ring buffer arrives in a later
/// milestone, and keeping content out until then means there is nothing to
/// accidentally persist.
final class CaptureController {
    private(set) var captureCount = 0
    private(set) var lastCaptureAt: Date?

    /// Called on the main queue whenever the counters change.
    var onChange: (() -> Void)?

    private var watcher: AXBannerWatcher?

    func start() {
        let watcher = AXBannerWatcher { [weak self] raw, textChildren in
            guard let self else { return }
            let notification = NotificationFieldExtractor.extract(raw, textChildren: textChildren)
            self.captureCount += 1
            self.lastCaptureAt = notification.timestamp
            // Content is intentionally dropped here, not stored.
            self.onChange?()
        }
        watcher.start()
        self.watcher = watcher
    }
}
```

- [ ] **Step 3: Write the app delegate**

```swift
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
```

- [ ] **Step 4: Write the entry point**

```swift
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
```

- [ ] **Step 5: Build**

Run: `swift build`
Expected: builds clean with zero warnings.

Do **not** run the binary directly — an unbundled AppKit binary has no bundle identity, which is the very problem this milestone exists to solve. It runs only from the assembled bundle in Task 4.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources/SignalLadder/
git commit -m "feat: menu-bar app target owning the capture pipeline"
```

---

## Task 4: Bundle assembly and signing

**Files:**

- Create: `Resources/Info.plist`
- Create: `Scripts/make-app.sh`
- Modify: `.gitignore`

**Interfaces:**

- Consumes: the `SignalLadder` executable product
- Produces: `build/SignalLadder.app`, signed

- [ ] **Step 1: Write Info.plist**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>SignalLadder</string>
    <key>CFBundleDisplayName</key>
    <string>SignalLadder</string>
    <key>CFBundleIdentifier</key>
    <string>com.jamiewhite.signalladder</string>
    <key>CFBundleExecutable</key>
    <string>SignalLadder</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 Jamie White. All rights reserved.</string>
</dict>
</plist>
```

`LSUIElement` is what makes it menu-bar-only. Without it the app takes a Dock icon and a menu bar of its own.

- [ ] **Step 2: Write the assembly script**

```bash
#!/usr/bin/env bash
# Scripts/make-app.sh — assemble and sign SignalLadder.app from the SPM build.
#
# There is no .xcodeproj by design: Package.swift is the single source of
# truth, and this script is the only thing that knows about bundle layout.
set -euo pipefail

CONFIG="${1:-debug}"
IDENTITY="${SIGNALLADDER_IDENTITY:-0C46A31C354444B7CC472CD29DE37303A090E844}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP="build/SignalLadder.app"
BIN=".build/${CONFIG}/SignalLadder"

echo "==> Building (${CONFIG})"
swift build -c "$CONFIG" --product SignalLadder

[ -f "$BIN" ] || { echo "error: $BIN not found after build" >&2; exit 1; }

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/SignalLadder"
cp Resources/Info.plist "$APP/Contents/Info.plist"

echo "==> Signing with $IDENTITY"
codesign --force --options runtime \
         --identifier com.jamiewhite.signalladder \
         --sign "$IDENTITY" \
         "$APP"

echo "==> Verifying"
codesign --verify --deep --strict "$APP"
echo "Built $APP"
echo
echo "Note: the Designated Requirement is deliberately NOT read here."
echo "codesign -d has been observed to hang on this machine; run it yourself if needed:"
echo "  codesign -d -r- $APP"
```

Make it executable: `chmod +x Scripts/make-app.sh`

- [ ] **Step 3: Ignore the build output**

Append to `.gitignore`:

```
build/
```

- [ ] **Step 4: Run the script**

Run: `./Scripts/make-app.sh`
Expected: builds, assembles, signs, and prints `Built build/SignalLadder.app`.

If signing fails with `errSecInternalComponent`, the login keychain has locked — that is a human step, not a code failure. Report it rather than falling back to ad-hoc signing, which silently drops `--identifier` and degrades the Designated Requirement to a cdhash that changes every build.

- [ ] **Step 5: Verify the bundle is well-formed**

```bash
plutil -lint build/SignalLadder.app/Contents/Info.plist
ls -R build/SignalLadder.app | head -20
```

Expected: `OK` from plutil, and a `Contents/{Info.plist,MacOS/SignalLadder,Resources,_CodeSignature}` layout.

- [ ] **Step 6: Commit**

```bash
git add Resources/Info.plist Scripts/make-app.sh .gitignore
git commit -m "feat: assemble and sign the app bundle from the SPM build"
```

---

## Task 5: Live verification _(requires a human)_

The app has to be granted Accessibility in its own right — the bundle is a different TCC subject from the CLI probe, so the probe's existing grant does not carry over. That is expected, and is the first real test of whether a bundled app holds its own grant.

- [ ] **Step 1: Launch the app**

```bash
open build/SignalLadder.app
```

A menu-bar icon appears with no Dock icon. On first launch it will show "Accessibility permission needed" and raise the system prompt.

- [ ] **Step 2: Grant Accessibility to the app**

In System Settings › Privacy & Security › Accessibility, add `build/SignalLadder.app`. Quit the app from its menu and relaunch it.

- [ ] **Step 3: Verify capture**

Trigger a Teams notification. The menu should show an incrementing capture count and a timestamp.

- [ ] **Step 4: Verify re-attach in a bundled app**

This is the check M2a exists for: both re-attach signals are now live.

```bash
killall NotificationCenter
```

Trigger another notification. The count must continue incrementing. Repeat two or three times — the count should keep rising with no restart of the app.

- [ ] **Step 5: Record the results**

Append to `docs/dev/notes/2026-09-11-m1-findings.md` under a new "M2a verification" heading: whether the bundled app holds its own Accessibility grant (versus the probe's), whether re-attach survived repeated restarts, and measured idle CPU from Activity Monitor.

The idle-CPU figure has been outstanding since M1 and this is the first build where measuring it is meaningful, since the app is the thing that will actually run all day.

---

## Done when

- `swift test` passes at 32 tests.
- `./Scripts/make-app.sh` produces a signed `build/SignalLadder.app` with no manual steps.
- The app runs menu-bar-only, with no Dock icon.
- It captures notifications and the count increments.
- Capture survives `killall NotificationCenter`, repeatedly.
- Idle CPU is measured and recorded.

## Not in this plan

The `INFocusStatusCenter` spike runs next, inside this app. Notification-permission onboarding, the canary and the health alarms are M2b. The Inspector window and ring buffer are M2c — which is why `CaptureController` deliberately counts captures without retaining their content.

Also unchanged here: `AXElementNode` still conflates "attribute absent" with "read failed" (M2 handover, issue 1), and dedupe still keys on content rather than element identity (issue 2). Both are M2b work, alongside the canary they interact with.
