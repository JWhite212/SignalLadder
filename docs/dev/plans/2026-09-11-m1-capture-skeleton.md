# M1 Capture Skeleton Implementation Plan

**Goal:** Prove that notification content can be captured from `com.apple.notificationcenterui` via the Accessibility API on this machine, and build the pure, tested parsing pipeline that consumes it.

**Architecture:** A Swift Package with two targets. `NotificationCore` holds all pure logic — an `AccessibilityNode` protocol, a bounded subrole-driven tree search, and a field extractor — none of which imports ApplicationServices, so every line is unit-testable with no Accessibility permission. `signalladder-probe` is a small executable that adapts real `AXUIElement`s to `AccessibilityNode`, owns the `AXObserver`, and prints captures to the console. All OS fragility lives in the executable target; all logic lives in the library.

**Tech Stack:** Swift 5.9+, Swift Package Manager, XCTest, ApplicationServices (AXUIElement/AXObserver), AppKit (NSWorkspace).

**Spec:** `docs/dev/specs/2026-09-11-macos-notification-router-design.md`

## Global Constraints

- **Minimum macOS: 14.0 Sonoma.** Package platform must be `.macOS(.v14)`. Must also run on macOS 15 and macOS 26.
- **No third-party dependencies.** `Package.swift` `dependencies` array stays empty.
- **Notification content is never written to disk** by the running program. Console output only. Fixtures are hand-redacted by the developer (spec §10.1).
- **`NotificationCore` must not import `ApplicationServices`, `AppKit`, or `Cocoa`.** This is enforced by a test in Task 3.
- **Tree search bounds (spec §5.3):** max depth 12, max visited nodes 256, `AXUIElementSetMessagingTimeout` 0.2s.
- **Banner subrole allowlist (spec §5.3):** `AXNotificationCenterBanner`, `AXNotificationCenterBannerStack`, `AXNotificationCenterAlert`, `AlertStack`.
- **Signing:** the probe binary is signed with a stable Developer ID identity so the Accessibility grant survives rebuilds (spec §8, TCC keys to the Designated Requirement).

---

## File Structure

```
Package.swift                                          Package manifest, two targets
Sources/NotificationCore/AccessibilityNode.swift       Protocol abstracting an AX element
Sources/NotificationCore/RawCapture.swift              Value type crossing the AX boundary
Sources/NotificationCore/CapturedNotification.swift    Parsed notification fields
Sources/NotificationCore/BannerSubrole.swift           The subrole allowlist
Sources/NotificationCore/BannerTreeLocator.swift       Bounded subrole-driven search
Sources/NotificationCore/NotificationFieldExtractor.swift  Pure string parsing
Sources/signalladder-probe/main.swift                  Entry point, permission gate, run loop
Sources/signalladder-probe/AXElementNode.swift         AXUIElement -> AccessibilityNode adapter
Sources/signalladder-probe/AXBannerWatcher.swift       AXObserver ownership and re-attach
Tests/NotificationCoreTests/FakeNode.swift             In-memory AccessibilityNode for tests
Tests/NotificationCoreTests/BannerTreeLocatorTests.swift
Tests/NotificationCoreTests/NotificationFieldExtractorTests.swift
Tests/NotificationCoreTests/PurityTests.swift          Asserts no framework imports
Fixtures/captures/README.md                            Redaction rules for recorded shapes
```

`NotificationCore` and `signalladder-probe` split by **testability boundary**, not by technical layer: everything that can be tested without a granted TCC permission lives in the library.

---

## Task 1: Package skeleton and signed probe

Creates the package and gets a signed, runnable binary that reports Accessibility trust. Signing is folded in here rather than deferred, because an unsigned binary re-prompts for Accessibility on every rebuild and would make every later task painful.

**Files:**

- Create: `Package.swift`
- Create: `Sources/NotificationCore/RawCapture.swift`
- Create: `Sources/signalladder-probe/main.swift`
- Create: `Tests/NotificationCoreTests/PurityTests.swift`

**Interfaces:**

- Consumes: nothing
- Produces: `struct RawCapture { let timestamp: Date; let rawText: String; let subrole: String }`; executable target named `signalladder-probe`

- [ ] **Step 1: Create the package manifest**

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SignalLadder",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "NotificationCore"),
        .executableTarget(
            name: "signalladder-probe",
            dependencies: ["NotificationCore"]
        ),
        .testTarget(
            name: "NotificationCoreTests",
            dependencies: ["NotificationCore"]
        ),
    ]
)
```

- [ ] **Step 2: Create the RawCapture value type**

```swift
// Sources/NotificationCore/RawCapture.swift
import Foundation

/// One banner observed at the Accessibility boundary, before any parsing.
public struct RawCapture: Equatable, Sendable {
    public let timestamp: Date
    public let rawText: String
    public let subrole: String

    public init(timestamp: Date, rawText: String, subrole: String) {
        self.timestamp = timestamp
        self.rawText = rawText
        self.subrole = subrole
    }
}
```

- [ ] **Step 3: Write the probe entry point**

This comes before any `swift` command: SPM refuses to load a package whose declared target directory does not exist, so `Sources/signalladder-probe/` must contain a source file before Step 5 runs the tests.

```swift
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
```

- [ ] **Step 4: Write the purity test**

This test enforces the Global Constraint that `NotificationCore` stays framework-free. It reads its own package sources from disk.

```swift
// Tests/NotificationCoreTests/PurityTests.swift
import XCTest

final class PurityTests: XCTestCase {
    /// NotificationCore must never import a framework that would make it
    /// untestable without a granted TCC permission.
    func testCoreHasNoForbiddenImports() throws {
        let forbidden = ["ApplicationServices", "AppKit", "Cocoa", "Carbon"]
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // NotificationCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // package root
            .appendingPathComponent("Sources/NotificationCore")

        let files = try FileManager.default
            .contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }

        XCTAssertFalse(files.isEmpty, "Found no sources at \(root.path)")

        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for framework in forbidden {
                XCTAssertFalse(
                    text.contains("import \(framework)"),
                    "\(file.lastPathComponent) imports \(framework)"
                )
            }
        }
    }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `swift test --filter PurityTests`
Expected: PASS. (`RawCapture.swift` imports only Foundation, which is allowed.)

- [ ] **Step 6: Build and run it**

```bash
swift build
.build/debug/signalladder-probe
```

Expected: prints `Accessibility trusted: false` and exits 1 on first run, having raised the system prompt.

- [ ] **Step 7: Sign the binary with a stable identity**

Find your Developer ID identity:

```bash
security find-identity -v -p codesigning
```

Sign, substituting your identity string:

```bash
codesign --force --options runtime \
  --identifier com.jamiewhite.signalladder.probe \
  --sign "Developer ID Application: Jamie White (RVVRP4WY6B)" \
  .build/debug/signalladder-probe
```

Verify the Designated Requirement is stable:

```bash
codesign -d -r- .build/debug/signalladder-probe
```

Expected: a requirement containing `anchor apple generic`, `identifier "com.jamiewhite.signalladder.probe"`, and your Team ID. Because the identifier and Team ID are fixed, re-signing a rebuilt binary yields the same DR and the Accessibility grant survives.

If you have no Developer ID certificate, substitute `--sign -` (ad-hoc) and accept re-granting Accessibility after each rebuild. Note this in your commit message so the cost is visible.

- [ ] **Step 8: Grant Accessibility and confirm it sticks**

Open System Settings › Privacy & Security › Accessibility, add `.build/debug/signalladder-probe`, enable it. Then:

```bash
.build/debug/signalladder-probe
swift build && codesign --force --options runtime --identifier com.jamiewhite.signalladder.probe --sign "Developer ID Application: Jamie White (RVVRP4WY6B)" .build/debug/signalladder-probe
.build/debug/signalladder-probe
```

Expected: `Accessibility trusted: true` both times. If the second run reports `false`, signing is not stable — stop and resolve before continuing, because every later task depends on this.

- [ ] **Step 9: Commit**

```bash
git add Package.swift Sources/ Tests/
git commit -m "feat: package skeleton with signed accessibility probe"
```

---

## Task 2: Raw tree dump — answer the feasibility question

The riskiest unknown in the whole project is whether notification banners are visible in the AX tree on this machine. This task answers it before any parsing logic is written, and produces the real strings that Task 5 is tested against.

**Files:**

- Modify: `Sources/signalladder-probe/main.swift`
- Create: `Fixtures/captures/README.md`

**Interfaces:**

- Consumes: signed probe from Task 1
- Produces: real `AXAttributedDescription` strings printed to console; a redaction policy for recording them

- [ ] **Step 1: Replace main.swift with a polling tree dumper**

Polling, not observing — this task only needs to know whether the elements exist. The observer arrives in Task 7.

```swift
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
```

- [ ] **Step 2: Build, sign and run**

```bash
swift build && codesign --force --options runtime --identifier com.jamiewhite.signalladder.probe --sign "Developer ID Application: Jamie White (RVVRP4WY6B)" .build/debug/signalladder-probe
.build/debug/signalladder-probe | tee /tmp/ax-dump.txt
```

- [ ] **Step 3: Trigger notifications and observe**

While it runs, trigger several real notifications. Aim for variety:

```bash
osascript -e 'display notification "Placeholder body" with title "Test Title" subtitle "Test Sub"'
```

Also trigger at least one from a real app you care about (Teams, Mail, Messages), including — if you can — one where you are @-mentioned.

**This is the project's go/no-go moment.** Record which of these you see:

| Observation                                                                              | Meaning                                                                                                        |
| ---------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| Elements with subrole `AXNotificationCenterBanner` or similar, carrying a `desc=` string | **Capture is viable.** Proceed                                                                                 |
| Windows appear but all descriptions are empty                                            | Partial. Try enabling System Settings › Keyboard › Keyboard navigation (Full Keyboard Access), re-run, compare |
| `kAXWindowsAttribute` always empty while banners are visible on screen                   | **The macOS 15.4-class blindness case (spec §3.1).** Stop and report before continuing                         |

- [ ] **Step 4: Write the fixture redaction policy**

```markdown
<!-- Fixtures/captures/README.md -->

# Capture fixtures

Recorded AX shapes used to test `NotificationFieldExtractor`.

## Redaction is mandatory

These files are committed to git and this project may be open-sourced.
Fixtures capture **structural shape only**. Before committing any recorded
string, replace every piece of human content with a synthetic placeholder:

- Real person names -> `Alex Example`, `Sam Placeholder`
- Real message bodies -> `Placeholder body text`
- Real channel or team names -> `General`, `Example Channel`
- App names are **kept verbatim** — they are not personal data and the
  parser's behaviour depends on them (e.g. names containing commas).

## Format

One file per observed shape, named `<os-version>-<app>-<variant>.txt`,
containing only the `AXAttributedDescription` string, with a leading
comment line recording where it came from.

    # macOS 26.7, Microsoft Teams, @-mention in a channel
    Microsoft Teams, Alex Example\nPlaceholder body text
```

- [ ] **Step 5: Record at least four redacted fixtures**

From `/tmp/ax-dump.txt`, extract the `desc=` strings and save redacted versions into `Fixtures/captures/`. You need at minimum:

1. A plain notification with app, title and body
2. One whose sender name contains a comma, if you can produce one
3. One with a long body that wraps across lines
4. One from `osascript` above (a known-shape control)

**Do not commit `/tmp/ax-dump.txt`** — it contains unredacted content.

- [ ] **Step 6: Commit**

```bash
git add Sources/signalladder-probe/main.swift Fixtures/
git commit -m "feat: raw AX tree dumper and redacted capture fixtures

Confirms notification banners are reachable in the accessibility tree
on macOS <your version>. Fixtures record observed string shapes with
all human content replaced by placeholders."
```

---

## Task 3: AccessibilityNode protocol and fake tree

Introduces the abstraction that makes tree searching testable. The spec calls for a replaceable capture layer (§5.2) but does not name this protocol; it is added here because `BannerTreeLocator` is otherwise untestable without a live AX tree.

**Files:**

- Create: `Sources/NotificationCore/AccessibilityNode.swift`
- Create: `Sources/NotificationCore/BannerSubrole.swift`
- Create: `Tests/NotificationCoreTests/FakeNode.swift`

**Interfaces:**

- Consumes: nothing
- Produces: `protocol AccessibilityNode { var subrole: String? { get }; var attributedDescription: String? { get }; var children: [AccessibilityNode] { get } }`; `enum BannerSubrole` with `static let allowlist: Set<String>` and `static func isBanner(_:) -> Bool`; `final class FakeNode: AccessibilityNode` for tests

- [ ] **Step 1: Write the protocol**

```swift
// Sources/NotificationCore/AccessibilityNode.swift
import Foundation

/// A node in an accessibility tree, reduced to only what banner location needs.
///
/// The real implementation wraps `AXUIElement`; tests use an in-memory fake.
/// Keeping this protocol free of ApplicationServices is what allows the whole
/// search algorithm to be tested without a TCC grant.
public protocol AccessibilityNode {
    var subrole: String? { get }
    var attributedDescription: String? { get }
    var children: [AccessibilityNode] { get }
}
```

- [ ] **Step 2: Write the subrole allowlist**

```swift
// Sources/NotificationCore/BannerSubrole.swift
import Foundation

/// Subroles macOS uses for notification banners.
///
/// `AXNotificationCenterAlert` and `AlertStack` cover persistent-style
/// notifications; macOS 26 introduced the wrapped-overlay arrangement that
/// makes a downward search necessary (spec section 5.3).
public enum BannerSubrole {
    public static let allowlist: Set<String> = [
        "AXNotificationCenterBanner",
        "AXNotificationCenterBannerStack",
        "AXNotificationCenterAlert",
        "AlertStack",
    ]

    public static func isBanner(_ subrole: String?) -> Bool {
        guard let subrole else { return false }
        return allowlist.contains(subrole)
    }
}
```

- [ ] **Step 3: Write the fake node**

```swift
// Tests/NotificationCoreTests/FakeNode.swift
import Foundation
@testable import NotificationCore

/// In-memory AccessibilityNode for building arbitrary test trees.
final class FakeNode: AccessibilityNode {
    let subrole: String?
    let attributedDescription: String?
    private let kids: [FakeNode]

    var children: [AccessibilityNode] { kids }

    init(subrole: String? = nil,
         description: String? = nil,
         children: [FakeNode] = []) {
        self.subrole = subrole
        self.attributedDescription = description
        self.kids = children
    }

    /// Builds a linear chain `depth` levels deep with `leaf` at the bottom.
    static func chain(depth: Int, leaf: FakeNode) -> FakeNode {
        var node = leaf
        for _ in 0..<depth {
            node = FakeNode(subrole: "AXGroup", children: [node])
        }
        return node
    }
}
```

- [ ] **Step 4: Run the purity test to confirm the new files are clean**

Run: `swift test --filter PurityTests`
Expected: PASS. Both new core files import only Foundation.

- [ ] **Step 5: Commit**

```bash
git add Sources/NotificationCore/AccessibilityNode.swift Sources/NotificationCore/BannerSubrole.swift Tests/NotificationCoreTests/FakeNode.swift
git commit -m "feat: AccessibilityNode protocol and banner subrole allowlist"
```

---

## Task 4: BannerTreeLocator

The bounded, subrole-driven search. This is the code that absorbs macOS restructuring the tree, so its bounds and its refusal to use index paths are the point.

**Files:**

- Create: `Sources/NotificationCore/BannerTreeLocator.swift`
- Create: `Tests/NotificationCoreTests/BannerTreeLocatorTests.swift`

**Interfaces:**

- Consumes: `AccessibilityNode`, `BannerSubrole`, `FakeNode`
- Produces: `struct BannerTreeLocator { init(maxDepth: Int = 12, maxVisited: Int = 256); func locate(in root: AccessibilityNode) -> [AccessibilityNode] }`

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/NotificationCoreTests/BannerTreeLocatorTests.swift
import XCTest
@testable import NotificationCore

final class BannerTreeLocatorTests: XCTestCase {
    private let locator = BannerTreeLocator()

    func testFindsBannerAtTopLevel() {
        let banner = FakeNode(subrole: "AXNotificationCenterBanner", description: "App, Title\nBody")
        let found = locator.locate(in: FakeNode(children: [banner]))
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.attributedDescription, "App, Title\nBody")
    }

    /// macOS 26 wraps banners in an extra overlay window; the same search
    /// must still find them without any code change.
    func testFindsBannerNestedDeepBehindWrappers() {
        let banner = FakeNode(subrole: "AXNotificationCenterBanner", description: "App, Deep\nBody")
        let found = locator.locate(in: FakeNode.chain(depth: 9, leaf: banner))
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.attributedDescription, "App, Deep\nBody")
    }

    func testFindsAllAllowlistedSubroles() {
        for subrole in BannerSubrole.allowlist {
            let banner = FakeNode(subrole: subrole, description: "App, \(subrole)\nBody")
            let found = locator.locate(in: FakeNode(children: [banner]))
            XCTAssertEqual(found.count, 1, "Failed to find subrole \(subrole)")
        }
    }

    func testFindsMultipleStackedBanners() {
        let a = FakeNode(subrole: "AXNotificationCenterBanner", description: "App, One\nBody")
        let b = FakeNode(subrole: "AXNotificationCenterBanner", description: "App, Two\nBody")
        let found = locator.locate(in: FakeNode(children: [a, b]))
        XCTAssertEqual(found.count, 2)
    }

    func testReturnsEmptyWhenNoBannerPresent() {
        let tree = FakeNode(children: [FakeNode(subrole: "AXGroup"), FakeNode(subrole: "AXButton")])
        XCTAssertTrue(locator.locate(in: tree).isEmpty)
    }

    func testDoesNotDescendBeyondMaxDepth() {
        let banner = FakeNode(subrole: "AXNotificationCenterBanner", description: "App, TooDeep\nBody")
        let found = locator.locate(in: FakeNode.chain(depth: 40, leaf: banner))
        XCTAssertTrue(found.isEmpty, "Search must stop at maxDepth")
    }

    func testRespectsVisitedBudget() {
        // The banner sits behind 300 siblings, exceeding the 256-node budget.
        let noise = (0..<300).map { _ in FakeNode(subrole: "AXGroup") }
        let banner = FakeNode(subrole: "AXNotificationCenterBanner", description: "App, Hidden\nBody")
        let tree = FakeNode(children: noise + [banner])

        let tight = BannerTreeLocator(maxDepth: 12, maxVisited: 256)
        XCTAssertTrue(tight.locate(in: tree).isEmpty,
                      "Budget must stop the search before reaching the banner")

        // Same tree, generous budget — proves the banner really is reachable
        // and that the empty result above came from the budget, not the shape.
        let generous = BannerTreeLocator(maxDepth: 12, maxVisited: 1000)
        XCTAssertEqual(generous.locate(in: tree).count, 1)
    }

    /// A banner that is itself the root must still be found.
    func testFindsBannerWhenRootIsTheBanner() {
        let banner = FakeNode(subrole: "AXNotificationCenterBanner", description: "App, Root\nBody")
        XCTAssertEqual(locator.locate(in: banner).count, 1)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter BannerTreeLocatorTests`
Expected: FAIL — `cannot find 'BannerTreeLocator' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// Sources/NotificationCore/BannerTreeLocator.swift
import Foundation

/// Finds notification banner elements inside an accessibility tree.
///
/// Deliberately breadth-first and subrole-driven. It never uses a
/// child-index path, because Apple restructures this tree between releases
/// (spec section 5.3) — matching on subrole survives extra wrapper levels,
/// a hard-coded path does not.
public struct BannerTreeLocator {
    public let maxDepth: Int
    public let maxVisited: Int

    public init(maxDepth: Int = 12, maxVisited: Int = 256) {
        self.maxDepth = maxDepth
        self.maxVisited = maxVisited
    }

    public func locate(in root: AccessibilityNode) -> [AccessibilityNode] {
        var found: [AccessibilityNode] = []
        var visited = 0
        var queue: [(node: AccessibilityNode, depth: Int)] = [(root, 0)]

        while !queue.isEmpty {
            let (node, depth) = queue.removeFirst()

            visited += 1
            if visited > maxVisited { break }

            if BannerSubrole.isBanner(node.subrole) {
                found.append(node)
                // Do not descend into a banner; nested banners are not a
                // thing, and its children are the banner's own text nodes.
                continue
            }

            if depth < maxDepth {
                for child in node.children {
                    queue.append((child, depth + 1))
                }
            }
        }

        return found
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter BannerTreeLocatorTests`
Expected: PASS, 8 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/NotificationCore/BannerTreeLocator.swift Tests/NotificationCoreTests/BannerTreeLocatorTests.swift
git commit -m "feat: bounded subrole-driven banner tree search"
```

---

## Task 5: NotificationFieldExtractor

Pure string parsing with every fallback from spec §5.4 made explicit and tested.

**Files:**

- Create: `Sources/NotificationCore/CapturedNotification.swift`
- Create: `Sources/NotificationCore/NotificationFieldExtractor.swift`
- Create: `Tests/NotificationCoreTests/NotificationFieldExtractorTests.swift`

**Interfaces:**

- Consumes: `RawCapture`
- Produces: `struct CapturedNotification` with `timestamp`, `appNameGuess`, `title`, `body`, `rawText`, `subrole`; `enum NotificationFieldExtractor { static func extract(_ raw: RawCapture) -> CapturedNotification }`

- [ ] **Step 1: Write the CapturedNotification type**

```swift
// Sources/NotificationCore/CapturedNotification.swift
import Foundation

/// A parsed notification. `appNameGuess` is named for what it is: the
/// result of a lossy heuristic over an undocumented format (spec 5.1).
public struct CapturedNotification: Equatable, Sendable {
    public let timestamp: Date
    public let appNameGuess: String
    public let title: String
    public let body: String
    public let rawText: String
    public let subrole: String

    public init(timestamp: Date,
                appNameGuess: String,
                title: String,
                body: String,
                rawText: String,
                subrole: String) {
        self.timestamp = timestamp
        self.appNameGuess = appNameGuess
        self.title = title
        self.body = body
        self.rawText = rawText
        self.subrole = subrole
    }
}
```

- [ ] **Step 2: Write the failing tests**

```swift
// Tests/NotificationCoreTests/NotificationFieldExtractorTests.swift
import XCTest
@testable import NotificationCore

final class NotificationFieldExtractorTests: XCTestCase {
    private let when = Date(timeIntervalSince1970: 1_757_000_000)

    private func extract(_ text: String) -> CapturedNotification {
        NotificationFieldExtractor.extract(
            RawCapture(timestamp: when, rawText: text, subrole: "AXNotificationCenterBanner")
        )
    }

    func testSplitsAppTitleAndBody() {
        let n = extract("Microsoft Teams, Alex Example\nPlaceholder body text")
        XCTAssertEqual(n.appNameGuess, "Microsoft Teams")
        XCTAssertEqual(n.title, "Alex Example")
        XCTAssertEqual(n.body, "Placeholder body text")
    }

    func testCommaButNoNewlineYieldsEmptyBody() {
        let n = extract("Weather, Rain expected at 3pm")
        XCTAssertEqual(n.appNameGuess, "Weather")
        XCTAssertEqual(n.title, "Rain expected at 3pm")
        XCTAssertEqual(n.body, "")
    }

    func testNoCommaPutsEverythingInTitle() {
        let n = extract("Some unparseable banner text")
        XCTAssertEqual(n.appNameGuess, "")
        XCTAssertEqual(n.title, "Some unparseable banner text")
        XCTAssertEqual(n.body, "")
    }

    func testEmptyStringYieldsEmptyFields() {
        let n = extract("")
        XCTAssertEqual(n.appNameGuess, "")
        XCTAssertEqual(n.title, "")
        XCTAssertEqual(n.body, "")
    }

    /// Splitting on the FIRST comma means a sender name containing a comma
    /// lands partly in the title. This is the known-lossy case from spec 5.4
    /// and is exactly why rawText is preserved.
    func testSenderNameContainingCommaMisparsesButPreservesRaw() {
        let text = "Microsoft Teams, Example, Alex\nPlaceholder body text"
        let n = extract(text)
        XCTAssertEqual(n.appNameGuess, "Microsoft Teams")
        XCTAssertEqual(n.title, "Example, Alex")
        XCTAssertEqual(n.body, "Placeholder body text")
        XCTAssertEqual(n.rawText, text, "rawText must survive untouched")
    }

    /// An app name containing a comma breaks the heuristic in the other
    /// direction. Documented, not fixed.
    func testAppNameContainingCommaIsTruncated() {
        let n = extract("Acme, Inc., Alex Example\nPlaceholder body text")
        XCTAssertEqual(n.appNameGuess, "Acme")
        XCTAssertEqual(n.title, "Inc., Alex Example")
    }

    func testMultiLineBodyKeepsAllLinesAfterFirstNewline() {
        let n = extract("App, Title\nLine one\nLine two\nLine three")
        XCTAssertEqual(n.body, "Line one\nLine two\nLine three")
    }

    func testTrimsWhitespaceAroundFields() {
        let n = extract("App ,  Title  \n  Body  ")
        XCTAssertEqual(n.appNameGuess, "App")
        XCTAssertEqual(n.title, "Title")
        XCTAssertEqual(n.body, "Body")
    }

    func testPreservesTimestampAndSubrole() {
        let n = extract("App, Title\nBody")
        XCTAssertEqual(n.timestamp, when)
        XCTAssertEqual(n.subrole, "AXNotificationCenterBanner")
    }

    /// Every recorded fixture must parse without crashing and must round-trip
    /// its raw text. Guards against a future format change going unnoticed.
    func testAllRecordedFixturesParse() throws {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/captures")

        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "txt" } ?? []

        XCTAssertFalse(files.isEmpty, "No fixtures found — Task 2 should have recorded some")

        for file in files {
            let contents = try String(contentsOf: file, encoding: .utf8)
            let payload = contents
                .split(separator: "\n", omittingEmptySubsequences: false)
                .drop { $0.hasPrefix("#") }
                .joined(separator: "\n")
            let n = extract(payload)
            XCTAssertEqual(n.rawText, payload, "rawText altered for \(file.lastPathComponent)")
        }
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `swift test --filter NotificationFieldExtractorTests`
Expected: FAIL — `cannot find 'NotificationFieldExtractor' in scope`.

- [ ] **Step 4: Write the implementation**

```swift
// Sources/NotificationCore/NotificationFieldExtractor.swift
import Foundation

/// Parses `AXAttributedDescription` into fields.
///
/// The format is undocumented and observed to be `"AppName, Title\nBody"`.
/// This heuristic is known to be lossy for names containing commas
/// (spec section 5.4); `rawText` is preserved on every result so a rule can
/// always fall back to matching the untouched string.
public enum NotificationFieldExtractor {
    public static func extract(_ raw: RawCapture) -> CapturedNotification {
        let text = raw.rawText

        var appNameGuess = ""
        var remainder = Substring(text)

        if let comma = text.firstIndex(of: ",") {
            appNameGuess = String(text[text.startIndex..<comma]).trimmed()
            remainder = text[text.index(after: comma)...]
        }

        var title = ""
        var body = ""

        if let newline = remainder.firstIndex(of: "\n") {
            title = String(remainder[remainder.startIndex..<newline]).trimmed()
            body = String(remainder[remainder.index(after: newline)...]).trimmed()
        } else {
            title = String(remainder).trimmed()
        }

        return CapturedNotification(
            timestamp: raw.timestamp,
            appNameGuess: appNameGuess,
            title: title,
            body: body,
            rawText: text,
            subrole: raw.subrole
        )
    }
}

private extension String {
    func trimmed() -> String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter NotificationFieldExtractorTests`
Expected: PASS, 10 tests.

If `testAllRecordedFixturesParse` fails with "No fixtures found", return to Task 2 Step 5 and record them.

- [ ] **Step 6: Run the whole suite**

Run: `swift test`
Expected: PASS, all tests across all three test classes.

- [ ] **Step 7: Commit**

```bash
git add Sources/NotificationCore/CapturedNotification.swift Sources/NotificationCore/NotificationFieldExtractor.swift Tests/NotificationCoreTests/NotificationFieldExtractorTests.swift
git commit -m "feat: notification field extractor with documented fallbacks"
```

---

## Task 6: AXUIElement adapter

Bridges real accessibility elements to the tested protocol. Small, and the only place `AXUIElement` attribute reads live.

**Files:**

- Create: `Sources/signalladder-probe/AXElementNode.swift`

**Interfaces:**

- Consumes: `AccessibilityNode` from Task 3
- Produces: `struct AXElementNode: AccessibilityNode { init(_ element: AXUIElement) }`

- [ ] **Step 1: Write the adapter**

```swift
// Sources/signalladder-probe/AXElementNode.swift
import Foundation
import ApplicationServices
import NotificationCore

/// Adapts a live `AXUIElement` to the pure `AccessibilityNode` protocol.
///
/// Every attribute read in the app funnels through here, so the messaging
/// timeout and the attributed-string unwrapping exist in exactly one place.
struct AXElementNode: AccessibilityNode {
    private let element: AXUIElement

    init(_ element: AXUIElement) {
        self.element = element
        AXUIElementSetMessagingTimeout(element, 0.2)
    }

    var subrole: String? {
        Self.stringAttribute(element, kAXSubroleAttribute as String)
    }

    var attributedDescription: String? {
        Self.stringAttribute(element, "AXAttributedDescription")
            ?? Self.stringAttribute(element, kAXDescriptionAttribute as String)
    }

    var children: [AccessibilityNode] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
              let elements = value as? [AXUIElement]
        else { return [] }
        return elements.map(AXElementNode.init)
    }

    /// Reads an attribute as a String, unwrapping NSAttributedString.
    /// macOS 15 moved notification text into an attributed string, which is
    /// why the plain-string path alone is not enough (spec section 3).
    private static func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success
        else { return nil }
        if let s = value as? String { return s }
        if let a = value as? NSAttributedString { return a.string }
        return nil
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build`
Expected: builds with no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/signalladder-probe/AXElementNode.swift
git commit -m "feat: AXUIElement adapter for AccessibilityNode"
```

---

## Task 7: AXBannerWatcher

The observer. Event-driven rather than polling, per the near-zero-idle-CPU constraint, with automatic re-attach when `notificationcenterui` restarts.

**Files:**

- Create: `Sources/signalladder-probe/AXBannerWatcher.swift`

**Interfaces:**

- Consumes: `AXElementNode`, `BannerTreeLocator`, `RawCapture` (the watcher emits raw captures; parsing happens downstream in Task 8)
- Produces: `final class AXBannerWatcher { init(onCapture: @escaping (RawCapture) -> Void); func start() }`

- [ ] **Step 1: Write the watcher**

```swift
// Sources/signalladder-probe/AXBannerWatcher.swift
import Foundation
import ApplicationServices
import AppKit
import NotificationCore

/// Owns the only AXObserver in the program.
///
/// Two facts from the spec shape this class. The system-wide AX element
/// cannot observe notifications (kAXErrorNotificationUnsupported), so the
/// observer is created against notificationcenterui's pid. And that process
/// restarts, so NSWorkspace launch/terminate observation drives re-attach —
/// without it the app dies silently the first time the process recycles.
final class AXBannerWatcher {
    private let bundleID = "com.apple.notificationcenterui"
    private let locator = BannerTreeLocator()
    private let onCapture: (RawCapture) -> Void

    private var observer: AXObserver?
    private var appElement: AXUIElement?
    private var reattachDelay: TimeInterval = 1.0

    init(onCapture: @escaping (RawCapture) -> Void) {
        self.onCapture = onCapture
    }

    func start() {
        observeWorkspace()
        attach()
    }

    // MARK: - Attach

    private func attach() {
        detach()

        guard let app = NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == bundleID })
        else {
            log("notificationcenterui not running; retrying in \(reattachDelay)s")
            scheduleReattach()
            return
        }

        let pid = app.processIdentifier
        var created: AXObserver?

        let callback: AXObserverCallback = { _, element, _, refcon in
            guard let refcon else { return }
            let watcher = Unmanaged<AXBannerWatcher>.fromOpaque(refcon).takeUnretainedValue()
            watcher.handle(element: element)
        }

        guard AXObserverCreate(pid, callback, &created) == .success, let created else {
            log("AXObserverCreate failed for pid \(pid)")
            scheduleReattach()
            return
        }

        let element = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        let notifications = [
            kAXWindowCreatedNotification,
            kAXWindowMovedNotification,
            kAXUIElementDestroyedNotification,
        ]

        for name in notifications {
            let err = AXObserverAddNotification(created, element, name as CFString, refcon)
            if err != .success {
                log("AXObserverAddNotification(\(name)) failed: \(err.rawValue)")
            }
        }

        CFRunLoopAddSource(
            CFRunLoopGetCurrent(),
            AXObserverGetRunLoopSource(created),
            .defaultMode
        )

        observer = created
        appElement = element
        reattachDelay = 1.0
        log("attached to notificationcenterui pid=\(pid)")
    }

    private func detach() {
        guard let observer, let appElement else { return }
        for name in [kAXWindowCreatedNotification, kAXWindowMovedNotification, kAXUIElementDestroyedNotification] {
            AXObserverRemoveNotification(observer, appElement, name as CFString)
        }
        CFRunLoopRemoveSource(
            CFRunLoopGetCurrent(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )
        self.observer = nil
        self.appElement = nil
    }

    /// Exponential backoff, capped, so a permanently-absent process does not spin.
    private func scheduleReattach() {
        let delay = reattachDelay
        reattachDelay = min(reattachDelay * 2, 30)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.attach()
        }
    }

    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let self,
                      let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.bundleIdentifier == self.bundleID
                else { return }
                self.log("notificationcenterui lifecycle event; re-attaching")
                self.attach()
            }
        }
    }

    // MARK: - Capture

    private func handle(element: AXUIElement) {
        // The callback carries no payload, so content must be read by walking
        // the tree from the element we were handed (spec section 3).
        let banners = locator.locate(in: AXElementNode(element))
        for banner in banners {
            guard let text = banner.attributedDescription, !text.isEmpty else { continue }
            onCapture(RawCapture(
                timestamp: Date(),
                rawText: text,
                subrole: banner.subrole ?? ""
            ))
        }
    }

    private func log(_ message: String) {
        FileHandle.standardError.write("[watcher] \(message)\n".data(using: .utf8)!)
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build`
Expected: builds with no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/signalladder-probe/AXBannerWatcher.swift
git commit -m "feat: event-driven AXObserver with automatic re-attach"
```

---

## Task 8: Wire the pipeline and verify end to end

Replaces the Task 2 polling dumper with the real event-driven pipeline, and confirms the whole chain works against live notifications.

**Files:**

- Modify: `Sources/signalladder-probe/main.swift`

**Interfaces:**

- Consumes: `AXBannerWatcher`, `NotificationFieldExtractor`
- Produces: a running probe printing parsed notifications

- [ ] **Step 1: Replace main.swift with the wired pipeline**

```swift
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

let watcher = AXBannerWatcher { raw in
    let now = raw.timestamp
    recentlySeen = recentlySeen.filter { now.timeIntervalSince($0.value) < dedupeWindow }
    if let last = recentlySeen[raw.rawText], now.timeIntervalSince(last) < dedupeWindow {
        return
    }
    recentlySeen[raw.rawText] = now

    let n = NotificationFieldExtractor.extract(raw)
    print("""
    ─────────────────────────────────────────
      app      \(n.appNameGuess.isEmpty ? "(none)" : n.appNameGuess)
      title    \(n.title)
      body     \(n.body.isEmpty ? "(none)" : n.body)
      subrole  \(n.subrole)
      raw      \(n.rawText.debugDescription)
    """)
}

watcher.start()
print("Watching for notifications. Ctrl-C to stop.\n")
CFRunLoopRun()
```

- [ ] **Step 2: Build, sign and run**

```bash
swift build && codesign --force --options runtime --identifier com.jamiewhite.signalladder.probe --sign "Developer ID Application: Jamie White (RVVRP4WY6B)" .build/debug/signalladder-probe
.build/debug/signalladder-probe
```

Expected: `[watcher] attached to notificationcenterui pid=NNNN` then `Watching for notifications.`

- [ ] **Step 3: Verify capture end to end**

```bash
osascript -e 'display notification "Placeholder body" with title "Test Title"'
```

Expected: a block printing `app`, `title`, `body`, `subrole` and `raw` within a second.

Then verify these specific cases and record the result of each:

| Check            | How                                                        | Expected                                    |
| ---------------- | ---------------------------------------------------------- | ------------------------------------------- |
| Real app capture | Trigger a Teams/Mail/Messages notification                 | Fields populate plausibly                   |
| No duplicates    | Trigger one notification                                   | Exactly one block printed                   |
| Re-attach works  | `killall NotificationCenter`, wait, trigger a notification | `re-attaching` logged, then capture resumes |
| Idle CPU         | Leave running 5 min, check Activity Monitor                | Near 0% when no notifications arrive        |

- [ ] **Step 4: Record any newly observed shapes as fixtures**

If any real notification produced a string shape not already in `Fixtures/captures/`, add it — **redacted per `Fixtures/captures/README.md`** — and re-run `swift test` to confirm it parses.

- [ ] **Step 5: Run the full suite**

Run: `swift test`
Expected: PASS, all tests.

- [ ] **Step 6: Commit**

```bash
git add Sources/signalladder-probe/main.swift Fixtures/
git commit -m "feat: wire capture pipeline end to end

Replaces the polling dumper with the AXObserver-driven pipeline:
watcher -> tree locator -> field extractor -> console. Includes
dedupe for the repeated move callbacks that fire during banner
animation."
```

- [ ] **Step 7: Write the milestone findings note**

Create `docs/dev/notes/2026-09-11-m1-findings.md` recording, for the machine and OS you tested on:

- macOS version tested
- Whether banners were reachable at all, and whether Full Keyboard Access was needed
- Which subroles actually appeared
- The observed depth of banners in the tree
- Any string shapes that broke the extractor
- Measured idle CPU
- Whether the Accessibility grant survived rebuild + re-sign

This note is the input to M2's health-monitor design, and the answer to the question the whole milestone exists to ask.

```bash
git add docs/dev/notes/
git commit -m "docs: record M1 capture findings"
```

---

## Done when

- `swift test` passes with all tests green.
- The probe prints correctly parsed fields for live notifications from at least two real applications.
- Re-attach after `killall NotificationCenter` is verified working.
- Idle CPU is near zero.
- The Accessibility grant survives a rebuild and re-sign.
- `docs/dev/notes/2026-09-11-m1-findings.md` exists and answers the blindness question for your machine.

## Not in this plan

Deferred to later milestones, each of which gets its own plan: the Inspector UI and ring buffer, notification-permission onboarding, the health canary and its delivery-vs-capture split (M2); the rule AST, engine, store, builder and Tier 1 actions (M3); the escalation ladder (M4); the text DSL and context conditions (M5); degraded-mode UX (M6).

The `INFocusStatusCenter` entitlement spike is M2 work and is **not** blocked by this plan.
