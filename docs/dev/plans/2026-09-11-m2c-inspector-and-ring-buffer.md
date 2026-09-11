# M2c: Inspector and Ring Buffer Implementation Plan

**Goal:** Give the app a window showing every notification it has captured, newest first, so a misparse is visible rather than mysterious — and so an empty list can be told apart from a broken pipeline.

**Architecture:** A pure, capacity-bounded `CaptureRingBuffer` in `NotificationCore` holds the last 50 captures in memory and never touches disk. `CaptureController` records into it after dedupe. A SwiftUI `InspectorView`, hosted in an AppKit window opened from the menu bar, renders it. The buffer is designed for annotation after insert, because M3's `RuleEngine` must write the matched rule back onto rows that already exist.

**Tech Stack:** Swift 5.9, SwiftUI (new to this project), AppKit for the window shell, XCTest.

**Spec:** `docs/dev/specs/2026-09-11-macos-notification-router-design.md` — §5.1 core data types, §6 storage table, §7.2 Inspector, §7.3 authoring loop, §12 milestone M2.

## Global Constraints

Copied verbatim from the spec and the project's standing rules. Every task's requirements implicitly include this section.

- **Notification content must never be written to disk, never logged, and never transmitted.** M2c is the first milestone that retains content at all. It lives in memory only and dies with the process (§6).
- Ring buffer capacity is **~50 entries** (§6).
- The Inspector is **in-memory only** (§7.2). No database. "At personal-tool scale it is a liability, not an asset" (§6).
- `NotificationCore` must import no framework that would make it untestable without a granted TCC permission. Enforced by `PurityTests`.
- macOS 14.0 floor; `LSUIElement` — menu-bar only, no Dock icon, no main window (§7.1).
- `appNameGuess` keeps its name. It is heuristic and code reading it should not forget that (§5.1).
- Build and test with the sandbox override: `swift build` / `swift test` fail under the default Bash sandbox.

## Rulings made while writing this plan

Recorded here so the executor does not relitigate them.

**1. `ContextSnapshot` ships with only the fields we can honestly fill.**
The spec (§5.1) defines it as `date`, `onCall`, `screenLocked`, `recentCountForApp`. The on-call toggle and screen-lock condition are **M5**. Shipping them now as constant `false` would put a value in the Inspector that is not a reading of anything, and M3's rules would match against it. This project has already dropped one condition (`focusActive`) rather than ship an unreliable one. `onCall` and `screenLocked` are therefore **absent from the struct** until the features that produce them exist.

**2. `CaptureDeduplicator` is not changed in M2c.**
Keying on element identity instead of content is a known open defect (M2 handover, issue 2), and a review lens confirmed a single banner re-emitted after the 1.5s window can be double-counted. It is still not fixed here, because M1's findings record that _the suppression path has never fired in the wild_ — we do not know which failure mode actually occurs. M2c instead makes suppressed repeats **visible in the Inspector**, which is the instrument that answers the question. Build the instrument before changing the thing it measures; the Focus spike cost two invalid readings for want of exactly that.

**3. The Inspector's empty state is a first-class feature, not a placeholder.**
An empty list under Do Not Disturb looks identical to an idle Tuesday. That ambiguity is the failure this whole product exists to prevent, and M2b's live run proved the app will meet it in practice. The empty state must state which one it is.

**4. `InspectorEntry` is mutable after insert.**
The spec requires the ring buffer be "annotated with the match result after `RuleEngine` returns" (§4). Designing the entry for annotation now avoids changing a type every layer holds when M3 lands. M2c always leaves the annotation `nil` and renders it as _not evaluated_, which is deliberately distinct from _matched nothing_ — the spec names matching nothing as "the most common confusion" (§7.2).

---

## File structure

| File                                                       | Responsibility                                        |
| ---------------------------------------------------------- | ----------------------------------------------------- |
| `Sources/NotificationCore/ContextSnapshot.swift`           | What was true around a capture, as plain values       |
| `Sources/NotificationCore/InspectorEntry.swift`            | One Inspector row: capture + context + annotation     |
| `Sources/NotificationCore/CaptureRingBuffer.swift`         | Bounded newest-first history, recent-count derivation |
| `Sources/SignalLadder/InspectorModel.swift`                | `ObservableObject` bridge; keeps SwiftUI out of Core  |
| `Sources/SignalLadder/InspectorView.swift`                 | The SwiftUI list and row                              |
| `Sources/SignalLadder/InspectorWindowController.swift`     | AppKit window shell for an `LSUIElement` app          |
| `Sources/SignalLadder/CaptureController.swift`             | Modified: records into the buffer                     |
| `Sources/SignalLadder/AppDelegate.swift`                   | Modified: menu item, health text for the empty state  |
| `Tests/NotificationCoreTests/CaptureRingBufferTests.swift` | Capacity, ordering, eviction, recent counts           |
| `Tests/NotificationCoreTests/PurityTests.swift`            | Modified: forbid SwiftUI and Combine in Core          |

---

## Task 1: Context snapshot and Inspector entry

**Files:**

- Create: `Sources/NotificationCore/ContextSnapshot.swift`
- Create: `Sources/NotificationCore/InspectorEntry.swift`
- Test: `Tests/NotificationCoreTests/CaptureRingBufferTests.swift` (created here, extended in Task 2)

**Interfaces:**

- Consumes: `CapturedNotification` from `Sources/NotificationCore/CapturedNotification.swift`
- Produces: `ContextSnapshot(date:recentCountForApp:recentCountIsUnderCounted:)`, `InspectorEntry(captured:context:suppressedRepeatCount:)` with `var annotation: MatchAnnotation?`, and `MatchAnnotation(ruleName:warnings:)`

- [ ] **Step 1: Write the failing test**

Create `Tests/NotificationCoreTests/CaptureRingBufferTests.swift`:

```swift
import XCTest
@testable import NotificationCore

final class CaptureRingBufferTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_757_000_000)

    func note(_ app: String, _ title: String = "t", at offset: TimeInterval = 0) -> CapturedNotification {
        CapturedNotification(
            timestamp: t0.addingTimeInterval(offset),
            appNameGuess: app,
            title: title,
            subtitle: "",
            body: "b",
            rawText: "\(app), \(title), b",
            subrole: "AXNotificationCenterBanner"
        )
    }

    // MARK: - Task 1

    func testAnEntryIsNotEvaluatedUntilSomethingAnnotatesIt() {
        // "Not evaluated" and "matched no rule" must never look the same. The
        // spec names matching nothing as the most common confusion (§7.2), and
        // an unevaluated row claiming "no match" would manufacture exactly it.
        let entry = InspectorEntry(captured: note("Teams"),
                                   context: ContextSnapshot(date: t0, recentCountForApp: 1),
                                   suppressedRepeatCount: 0)
        XCTAssertNil(entry.annotation)
    }

    func testAnEntryCanBeAnnotatedAfterCreation() {
        // M3's RuleEngine annotates rows that already exist in the buffer.
        var entry = InspectorEntry(captured: note("Teams"),
                                   context: ContextSnapshot(date: t0, recentCountForApp: 1),
                                   suppressedRepeatCount: 0)
        entry.annotation = MatchAnnotation(ruleName: "On-call mentions", warnings: [])
        XCTAssertEqual(entry.annotation?.ruleName, "On-call mentions")
    }

    func testAnAnnotationWithNoRuleNameMeansEvaluatedAndMatchedNothing() {
        var entry = InspectorEntry(captured: note("Weather"),
                                   context: ContextSnapshot(date: t0, recentCountForApp: 1),
                                   suppressedRepeatCount: 0)
        entry.annotation = MatchAnnotation(ruleName: nil, warnings: [])
        XCTAssertNotNil(entry.annotation, "evaluated")
        XCTAssertNil(entry.annotation?.ruleName, "matched nothing")
    }

    func testUnderCountingDefaultsToFalse() {
        let context = ContextSnapshot(date: t0, recentCountForApp: 3)
        XCTAssertFalse(context.recentCountIsUnderCounted)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter CaptureRingBufferTests`
Expected: FAIL — `cannot find 'InspectorEntry' in scope`, `cannot find 'ContextSnapshot' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Sources/NotificationCore/ContextSnapshot.swift`:

```swift
// Sources/NotificationCore/ContextSnapshot.swift
import Foundation

/// What was true around a capture, recorded so "why didn't my rule fire?" is
/// answerable after the fact (§7.2).
///
/// The spec's full snapshot also carries `onCall` and `screenLocked`. Both are
/// M5 features, and neither is present here: a field that always reads `false`
/// is not a reading, it is a placeholder the Inspector would display as fact
/// and M3's rules would match against. This project dropped `focusActive`
/// rather than ship a condition it could not read honestly; the same standard
/// applies to fields whose source does not exist yet.
public struct ContextSnapshot: Equatable, Sendable {
    /// Time of day and weekday — the basis of M5's time-window conditions.
    public let date: Date

    /// How many notifications from the same app fall inside the recent window.
    /// This is the alert-fatigue signal the product exists to serve: forty in
    /// an hour from one channel is the problem stated in the user's own words.
    public let recentCountForApp: Int

    /// True when the count is a floor rather than a total.
    ///
    /// The ring buffer holds a bounded number of entries, so a genuinely noisy
    /// app can overflow it inside the window — at which point the count is
    /// "at least this many", not "this many". Presenting a floor as a total
    /// would understate exactly the volume the user is trying to measure.
    public let recentCountIsUnderCounted: Bool

    public init(date: Date, recentCountForApp: Int, recentCountIsUnderCounted: Bool = false) {
        self.date = date
        self.recentCountForApp = recentCountForApp
        self.recentCountIsUnderCounted = recentCountIsUnderCounted
    }
}
```

Create `Sources/NotificationCore/InspectorEntry.swift`:

```swift
// Sources/NotificationCore/InspectorEntry.swift
import Foundation

/// The outcome of evaluating a notification against the rules.
///
/// Its presence means evaluation happened. `ruleName == nil` therefore means
/// "evaluated, matched nothing" — which the spec calls the most common source
/// of confusion (§7.2) — and is deliberately distinguishable from an entry with
/// no annotation at all, meaning nothing has evaluated it yet.
public struct MatchAnnotation: Equatable, Sendable {
    public let ruleName: String?
    public let warnings: [String]

    public init(ruleName: String?, warnings: [String] = []) {
        self.ruleName = ruleName
        self.warnings = warnings
    }
}

/// One row of the Inspector.
///
/// Holds notification content, which lives in memory and nowhere else (§6).
/// Nothing in this type or its users may write it to disk, log it, or send it.
public struct InspectorEntry: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let captured: CapturedNotification
    public let context: ContextSnapshot

    /// How many further copies dedupe suppressed behind this one.
    ///
    /// Surfaced rather than silently dropped because we still do not know
    /// whether suppression is ever correct: dedupe keys on content within a
    /// short window, which cannot tell one banner re-firing during animation
    /// from two genuinely distinct alerts carrying identical text — and two
    /// identical alerts from a noisy channel is precisely the traffic this
    /// product exists to handle. M1 recorded that this path has never been
    /// observed firing in the wild. The Inspector is how that gets settled.
    public let suppressedRepeatCount: Int

    /// Written after the fact by whatever evaluates the notification. `nil`
    /// until something does — in M2c, always.
    public var annotation: MatchAnnotation?

    public init(id: UUID = UUID(),
                captured: CapturedNotification,
                context: ContextSnapshot,
                suppressedRepeatCount: Int,
                annotation: MatchAnnotation? = nil) {
        self.id = id
        self.captured = captured
        self.context = context
        self.suppressedRepeatCount = suppressedRepeatCount
        self.annotation = annotation
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter CaptureRingBufferTests`
Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/NotificationCore/ContextSnapshot.swift Sources/NotificationCore/InspectorEntry.swift Tests/NotificationCoreTests/CaptureRingBufferTests.swift
git commit -m "feat: the row type the Inspector renders, annotatable after the fact"
```

---

## Task 2: The ring buffer

**Files:**

- Create: `Sources/NotificationCore/CaptureRingBuffer.swift`
- Modify: `Tests/NotificationCoreTests/CaptureRingBufferTests.swift`

**Interfaces:**

- Consumes: `InspectorEntry`, `ContextSnapshot`, `CapturedNotification` from Task 1
- Produces: `CaptureRingBuffer(capacity:recentWindow:)`, `@discardableResult func record(_ notification: CapturedNotification, suppressedRepeatCount: Int) -> InspectorEntry`, `var entries: [InspectorEntry]` (newest first), `var count: Int`, `func annotate(id: UUID, with: MatchAnnotation)`

- [ ] **Step 1: Write the failing tests**

Append to `Tests/NotificationCoreTests/CaptureRingBufferTests.swift`, inside the class:

```swift
    // MARK: - Task 2

    func testEntriesComeBackNewestFirst() {
        let buffer = CaptureRingBuffer()
        buffer.record(note("A", "first", at: 0), suppressedRepeatCount: 0)
        buffer.record(note("B", "second", at: 10), suppressedRepeatCount: 0)
        XCTAssertEqual(buffer.entries.map(\.captured.title), ["second", "first"])
    }

    func testOldestEntriesAreEvictedAtCapacity() {
        let buffer = CaptureRingBuffer(capacity: 3)
        for i in 0..<5 {
            buffer.record(note("A", "n\(i)", at: TimeInterval(i)), suppressedRepeatCount: 0)
        }
        XCTAssertEqual(buffer.count, 3)
        XCTAssertEqual(buffer.entries.map(\.captured.title), ["n4", "n3", "n2"])
    }

    func testRecentCountCountsOnlyTheSameApp() {
        let buffer = CaptureRingBuffer()
        buffer.record(note("Teams", at: 0), suppressedRepeatCount: 0)
        buffer.record(note("Weather", at: 1), suppressedRepeatCount: 0)
        let entry = buffer.record(note("Teams", at: 2), suppressedRepeatCount: 0)
        XCTAssertEqual(entry.context.recentCountForApp, 2, "the two Teams notifications, not the Weather one")
    }

    func testRecentCountExcludesAnythingOlderThanTheWindow() {
        let buffer = CaptureRingBuffer(recentWindow: 3600)
        buffer.record(note("Teams", at: 0), suppressedRepeatCount: 0)
        let entry = buffer.record(note("Teams", at: 7200), suppressedRepeatCount: 0)
        XCTAssertEqual(entry.context.recentCountForApp, 1, "two hours later, the first is out of the window")
    }

    func testRecentCountIncludesTheNotificationBeingRecorded() {
        let buffer = CaptureRingBuffer()
        let entry = buffer.record(note("Teams", at: 0), suppressedRepeatCount: 0)
        XCTAssertEqual(entry.context.recentCountForApp, 1)
    }

    func testRecentCountIsFlaggedAsAFloorWhenTheBufferOverflowsInsideTheWindow() {
        // A noisy channel can overflow the buffer inside the hour. The count is
        // then "at least this many" — and reporting a floor as a total would
        // understate exactly the volume the user is trying to see.
        let buffer = CaptureRingBuffer(capacity: 3, recentWindow: 3600)
        for i in 0..<4 {
            buffer.record(note("Teams", at: TimeInterval(i)), suppressedRepeatCount: 0)
        }
        XCTAssertTrue(buffer.entries.first!.context.recentCountIsUnderCounted)
    }

    func testRecentCountIsNotFlaggedWhenTheOldestEntryPredatesTheWindow() {
        // Full buffer, but the evicted entries were outside the window anyway,
        // so nothing countable was lost and the total is exact.
        let buffer = CaptureRingBuffer(capacity: 3, recentWindow: 60)
        for i in 0..<4 {
            buffer.record(note("Teams", at: TimeInterval(i) * 1000), suppressedRepeatCount: 0)
        }
        XCTAssertFalse(buffer.entries.first!.context.recentCountIsUnderCounted)
    }

    func testSuppressedRepeatsAreRecordedOnTheEntry() {
        let buffer = CaptureRingBuffer()
        let entry = buffer.record(note("Teams"), suppressedRepeatCount: 4)
        XCTAssertEqual(entry.suppressedRepeatCount, 4)
    }

    func testAnnotatingFindsTheRowByIdentity() {
        let buffer = CaptureRingBuffer()
        let first = buffer.record(note("A", "first", at: 0), suppressedRepeatCount: 0)
        buffer.record(note("B", "second", at: 1), suppressedRepeatCount: 0)

        buffer.annotate(id: first.id, with: MatchAnnotation(ruleName: "Rule X"))

        XCTAssertEqual(buffer.entries.last?.annotation?.ruleName, "Rule X")
        XCTAssertNil(buffer.entries.first?.annotation, "the other row is untouched")
    }

    func testAnnotatingAnEvictedRowIsHarmless() {
        // A slow evaluator can return after its row has aged out. Dropping the
        // annotation is correct; crashing or annotating the wrong row is not.
        let buffer = CaptureRingBuffer(capacity: 1)
        let first = buffer.record(note("A", at: 0), suppressedRepeatCount: 0)
        buffer.record(note("B", at: 1), suppressedRepeatCount: 0)

        buffer.annotate(id: first.id, with: MatchAnnotation(ruleName: "Rule X"))

        XCTAssertNil(buffer.entries.first?.annotation)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter CaptureRingBufferTests`
Expected: FAIL — `cannot find 'CaptureRingBuffer' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Sources/NotificationCore/CaptureRingBuffer.swift`:

```swift
// Sources/NotificationCore/CaptureRingBuffer.swift
import Foundation

/// The last N captures, in memory and nowhere else.
///
/// This is the first place in the project that retains notification content at
/// all — every earlier stage read it, used it, and dropped it. The spec permits
/// exactly this and no more: in-memory, bounded, dying with the process (§6).
/// There is deliberately no persistence, no export, and no logging path out of
/// this type. Adding one would need a decision about content leaving the
/// machine, which the project has already made in the negative.
///
/// Not thread-safe by design. Callers are main-actor isolated, and adding a
/// lock would suggest otherwise.
public final class CaptureRingBuffer {
    private var storage: [InspectorEntry] = []
    private let capacity: Int
    private let recentWindow: TimeInterval

    /// - Parameters:
    ///   - capacity: rows retained. ~50 per §6.
    ///   - recentWindow: how far back `recentCountForApp` looks.
    public init(capacity: Int = 50, recentWindow: TimeInterval = 3600) {
        self.capacity = max(1, capacity)
        self.recentWindow = recentWindow
    }

    /// Newest first, as the Inspector displays them (§7.2).
    public var entries: [InspectorEntry] { storage.reversed() }

    public var count: Int { storage.count }

    public var isEmpty: Bool { storage.isEmpty }

    /// Records a capture and returns the entry created for it.
    ///
    /// - Parameter suppressedRepeatCount: copies dedupe collapsed into this
    ///   one. Carried through rather than discarded so the Inspector can show
    ///   that suppression happened at all.
    @discardableResult
    public func record(_ notification: CapturedNotification,
                       suppressedRepeatCount: Int) -> InspectorEntry {
        let context = makeContext(for: notification)
        let entry = InspectorEntry(captured: notification,
                                   context: context,
                                   suppressedRepeatCount: suppressedRepeatCount)
        storage.append(entry)
        if storage.count > capacity {
            storage.removeFirst(storage.count - capacity)
        }
        return entry
    }

    /// Attaches an evaluation result to a row that already exists.
    ///
    /// Silently does nothing when the row has aged out — a slow evaluator
    /// returning after eviction is expected, and dropping its result is the
    /// correct outcome. Matching on identity rather than position is what makes
    /// that safe: positions shift on every eviction.
    public func annotate(id: UUID, with annotation: MatchAnnotation) {
        guard let index = storage.firstIndex(where: { $0.id == id }) else { return }
        storage[index].annotation = annotation
    }

    /// Counts recent notifications from the same app, including the one being
    /// recorded, and reports whether that count is a total or a floor.
    private func makeContext(for notification: CapturedNotification) -> ContextSnapshot {
        let cutoff = notification.timestamp.addingTimeInterval(-recentWindow)

        let priorFromSameApp = storage.filter {
            $0.captured.appNameGuess == notification.appNameGuess && $0.captured.timestamp >= cutoff
        }.count

        // The count can only be short if the buffer was already full AND the
        // entry about to fall off was itself inside the window — otherwise
        // nothing countable was lost.
        let willEvict = storage.count >= capacity
        let evictedWasInsideWindow = storage.first.map { $0.captured.timestamp >= cutoff } ?? false

        return ContextSnapshot(date: notification.timestamp,
                               recentCountForApp: priorFromSameApp + 1,
                               recentCountIsUnderCounted: willEvict && evictedWasInsideWindow)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter CaptureRingBufferTests`
Expected: PASS, 14 tests.

- [ ] **Step 5: Run the whole suite**

Run: `swift test`
Expected: PASS, 79 tests.

- [ ] **Step 6: Commit**

```bash
git add Sources/NotificationCore/CaptureRingBuffer.swift Tests/NotificationCoreTests/CaptureRingBufferTests.swift
git commit -m "feat: bounded in-memory history of what was captured"
```

---

## Task 3: Record captures into the buffer

**Files:**

- Modify: `Sources/SignalLadder/CaptureController.swift`
- Modify: `Tests/NotificationCoreTests/PurityTests.swift`

**Interfaces:**

- Consumes: `CaptureRingBuffer.record(_:suppressedRepeatCount:)` from Task 2
- Produces: `CaptureController.history: CaptureRingBuffer` (read-only access for the Inspector), `CaptureController.onChange` still fires after every recorded capture

**Context the implementer needs:** `CaptureController.start()` currently ends its capture closure with a comment reading `// Content is intentionally dropped here, not stored.` That comment is now wrong and must go — this task is precisely the reversal it describes. `CaptureDeduplicator.admit` returns a `Decision` carrying `isRepeat` and `repeatCount`; the current code discards the decision when `isRepeat` is true. Keep that suppression, but carry the count onto the next admitted entry so suppression is visible rather than silent.

- [ ] **Step 1: Write the failing test**

Add to `Tests/NotificationCoreTests/PurityTests.swift`, inside the existing class:

```swift
    /// NotificationCore holds notification content now. Keeping UI frameworks
    /// out of it keeps the rule "content never leaves memory" auditable in one
    /// module rather than wherever a view happened to be written.
    func testCoreHasNoUIFrameworkImports() throws {
        let forbidden = ["SwiftUI", "Combine"]
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/NotificationCore")

        let files = try FileManager.default
            .contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }

        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for framework in forbidden {
                XCTAssertFalse(text.contains("import \(framework)"),
                               "\(file.lastPathComponent) imports \(framework)")
            }
        }
    }

    /// The ring buffer is the only place content lives. Nothing in Core may
    /// open a file handle or a URL — a regression here is a privacy breach, not
    /// a bug, and it would produce no symptom at runtime.
    func testCoreWritesNothingAnywhere() throws {
        let forbidden = ["FileManager", "FileHandle", "URLSession", "Data(contentsOf", "write(to"]
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/NotificationCore")

        let files = try FileManager.default
            .contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }

        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for symbol in forbidden {
                XCTAssertFalse(text.contains(symbol),
                               "\(file.lastPathComponent) references \(symbol) — content must never reach disk or network")
            }
        }
    }
```

- [ ] **Step 2: Run tests to verify they pass or fail honestly**

Run: `swift test --filter PurityTests`
Expected: PASS — Core currently imports nothing forbidden. These are regression guards, so passing immediately is correct. If either fails, stop and report: something already violates the content constraint.

- [ ] **Step 3: Wire the buffer into the controller**

In `Sources/SignalLadder/CaptureController.swift`, add the property near `captureCount`:

```swift
    /// Everything captured, newest first, for the Inspector. In memory only.
    let history = CaptureRingBuffer()
```

Replace the tail of the capture closure in `start()` — the block beginning `let decision = self.dedupe.admit(...)` — with:

```swift
            let decision = self.dedupe.admit(notification.rawText, at: notification.timestamp)
            if decision.isRepeat {
                // Held rather than dropped, and attached to the next admitted
                // capture. Dedupe keys on content within a short window, which
                // cannot tell one banner re-firing during animation from two
                // genuinely distinct alerts carrying identical text — and a
                // noisy channel produces exactly the latter. Showing the count
                // is how we find out which is happening, since M1 recorded that
                // this path has never been observed firing in the wild.
                self.pendingSuppressedRepeats += 1
                self.onChange?()
                return
            }

            self.captureCount += 1
            self.history.record(notification, suppressedRepeatCount: self.pendingSuppressedRepeats)
            self.pendingSuppressedRepeats = 0
            self.onChange?()
```

Add the backing property beside `history`:

```swift
    private var pendingSuppressedRepeats = 0
```

- [ ] **Step 4: Build and run the whole suite**

Run: `swift build && swift test`
Expected: build clean with zero warnings; PASS, 81 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/SignalLadder/CaptureController.swift Tests/NotificationCoreTests/PurityTests.swift
git commit -m "feat: keep what was captured, in memory, where the Inspector can read it"
```

---

## Task 4: The Inspector view

**Files:**

- Create: `Sources/SignalLadder/InspectorModel.swift`
- Create: `Sources/SignalLadder/InspectorView.swift`

**Interfaces:**

- Consumes: `InspectorEntry`, `MatchAnnotation`, `CaptureRingBuffer` from Tasks 1–2
- Produces: `InspectorModel` (`@Published var entries: [InspectorEntry]`, `@Published var emptyStateMessage: String`, `func refresh(from:)`, `func setHealth(summary:health:)`), `InspectorView(model:)`

**Context the implementer needs:** SwiftUI is new to this project; there is no existing view code to pattern-match against. Keep SwiftUI entirely inside the `SignalLadder` target — `PurityTests` now fails the build if it reaches `NotificationCore`. `InspectorModel` exists specifically so the pure buffer never has to conform to `ObservableObject`.

There is no unit test for the view itself. SwiftUI view bodies are not meaningfully assertable without snapshot infrastructure this project does not have and does not need; the model's message selection is where the logic lives, and that is tested.

- [ ] **Step 1: Write the failing test**

The model lives in the `SignalLadder` executable target, which has no test target of its own. Rather than leave the one piece of real logic untested, put the message selection in `NotificationCore` as a pure function and test it there — the model then only forwards to it.

Append to `Tests/NotificationCoreTests/CaptureRingBufferTests.swift`, inside the class:

```swift
    // MARK: - Task 4 — empty-state wording

    func testEmptyAndHealthySaysItIsSimplyQuiet() {
        let message = InspectorEmptyState.message(isEmpty: true, isAlarming: false, healthSummary: "Working — verified")
        XCTAssertTrue(message.contains("quiet"), message)
        XCTAssertFalse(message.contains("cannot"), message)
    }

    func testEmptyAndAlarmingSaysCaptureIsUnproven() {
        // The whole point. An empty list under Do Not Disturb looks exactly
        // like an idle Tuesday, and M2b's live run proved the app meets that
        // situation in practice.
        let message = InspectorEmptyState.message(isEmpty: true, isAlarming: true, healthSummary: "Cannot verify itself")
        XCTAssertTrue(message.contains("Cannot verify itself"), message)
        XCTAssertFalse(message.contains("quiet"), message)
    }

    func testNonEmptyHasNoEmptyStateMessage() {
        XCTAssertNil(InspectorEmptyState.message(isEmpty: false, isAlarming: true, healthSummary: "x"))
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter CaptureRingBufferTests`
Expected: FAIL — `cannot find 'InspectorEmptyState' in scope`.

- [ ] **Step 3: Write the pure empty-state logic**

Append to `Sources/NotificationCore/InspectorEntry.swift`:

```swift
/// What the Inspector says when it has nothing to show.
///
/// An empty list means one of two opposite things: nothing arrived, or nothing
/// could arrive. They look identical and mean the reverse of each other, and
/// conflating them is the failure this product exists to prevent — a live run
/// on 2026-09-11 had Do Not Disturb silently suppressing everything while the
/// app looked idle. Pure and separately tested because getting it wrong is
/// invisible at runtime.
public enum InspectorEmptyState {
    public static func message(isEmpty: Bool,
                               isAlarming: Bool,
                               healthSummary: String) -> String? {
        guard isEmpty else { return nil }
        if isAlarming {
            return "Nothing captured — and SignalLadder cannot confirm it is capturing.\n\(healthSummary)"
        }
        return "Nothing captured yet. Capture is verified working, so this is simply quiet."
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter CaptureRingBufferTests`
Expected: PASS, 17 tests.

- [ ] **Step 5: Write the model**

Create `Sources/SignalLadder/InspectorModel.swift`:

```swift
// Sources/SignalLadder/InspectorModel.swift
import Foundation
import Combine
import NotificationCore

/// Bridges the pure ring buffer to SwiftUI.
///
/// Exists so `CaptureRingBuffer` never has to conform to `ObservableObject`:
/// the buffer holds notification content, and keeping it free of UI frameworks
/// keeps "content never leaves memory" auditable in one module. PurityTests
/// enforces that.
@MainActor
final class InspectorModel: ObservableObject {
    @Published private(set) var entries: [InspectorEntry] = []
    @Published private(set) var emptyStateMessage: String?

    private var healthSummary = "Checking…"
    private var health: CaptureHealth = .unknown

    func refresh(from buffer: CaptureRingBuffer) {
        entries = buffer.entries
        recomputeEmptyState()
    }

    func setHealth(summary: String, health: CaptureHealth) {
        healthSummary = summary
        self.health = health
        recomputeEmptyState()
    }

    private func recomputeEmptyState() {
        emptyStateMessage = InspectorEmptyState.message(isEmpty: entries.isEmpty,
                                                        health: health,
                                                        healthSummary: healthSummary)
    }
}
```

- [ ] **Step 6: Write the view**

Create `Sources/SignalLadder/InspectorView.swift`:

```swift
// Sources/SignalLadder/InspectorView.swift
import SwiftUI
import NotificationCore

struct InspectorView: View {
    @ObservedObject var model: InspectorModel

    var body: some View {
        Group {
            if let message = model.emptyStateMessage {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text(message)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .padding(40)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.entries) { entry in
                    InspectorRow(entry: entry)
                }
            }
        }
        .frame(minWidth: 560, minHeight: 380)
    }
}

private struct InspectorRow: View {
    let entry: InspectorEntry
    @State private var showsRaw = false

    private static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.captured.appNameGuess.isEmpty ? "(no app name)" : entry.captured.appNameGuess)
                    .font(.headline)
                Spacer()
                Text(Self.time.string(from: entry.captured.timestamp))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text(entry.captured.title).font(.body)
            if !entry.captured.subtitle.isEmpty {
                Text(entry.captured.subtitle).font(.callout).foregroundStyle(.secondary)
            }
            if !entry.captured.body.isEmpty {
                Text(entry.captured.body).font(.callout).foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                // The subrole is shown because it is a matchable field, and
                // users cannot write rules against fields they have never seen.
                Label(entry.captured.subrole, systemImage: "tag")
                Label(recentText, systemImage: "chart.bar")
                if entry.suppressedRepeatCount > 0 {
                    Label("\(entry.suppressedRepeatCount) suppressed", systemImage: "square.on.square")
                }
                Label(matchText, systemImage: "line.3.horizontal.decrease.circle")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            // §7.2 item 6. Always empty in M2c — nothing evaluates yet — but a
            // warning raised during evaluation and then not shown would be a
            // silent failure in the one window built to make failures visible.
            ForEach(entry.annotation?.warnings ?? [], id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            DisclosureGroup("Raw", isExpanded: $showsRaw) {
                Text(entry.captured.rawText.isEmpty ? "(empty description)" : entry.captured.rawText)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
    }

    /// Reads as a floor when the buffer overflowed inside the window, because
    /// that is what the number is.
    private var recentText: String {
        let n = entry.context.recentCountForApp
        return entry.context.recentCountIsUnderCounted ? "\(n)+ in the last hour" : "\(n) in the last hour"
    }

    /// Three distinct states, deliberately. "Not evaluated" is not "matched
    /// nothing" — the spec calls matching nothing the most common confusion.
    private var matchText: String {
        guard let annotation = entry.annotation else { return "Not evaluated — no rules yet" }
        return annotation.ruleName.map { "Matched \($0)" } ?? "Matched no rule"
    }
}
```

- [ ] **Step 7: Build**

Run: `swift build`
Expected: clean, zero warnings. The view is not yet reachable — Task 5 opens it.

- [ ] **Step 8: Commit**

```bash
git add Sources/SignalLadder/InspectorModel.swift Sources/SignalLadder/InspectorView.swift Sources/NotificationCore/InspectorEntry.swift Tests/NotificationCoreTests/CaptureRingBufferTests.swift
git commit -m "feat: the Inspector, and an empty state that says which kind of empty"
```

---

## Task 5: Window and menu item

**Files:**

- Create: `Sources/SignalLadder/InspectorWindowController.swift`
- Modify: `Sources/SignalLadder/AppDelegate.swift`

**Interfaces:**

- Consumes: `InspectorView`, `InspectorModel` from Task 4; `CaptureController.history` from Task 3
- Produces: `InspectorWindowController.show(model:)`

**Context the implementer needs:** the app is `LSUIElement` with activation policy `.accessory`, so it has no Dock icon and does not become frontmost on its own. A window opened from a menu-bar app must be ordered front _and_ the app activated explicitly, or it appears behind whatever the user was using. `main.swift`'s top-level `let delegate` is what roots the object graph — `NSApplication.delegate` is a weak reference — so preserve that structure. `AppDelegate.rebuildMenu()` clears and rebuilds every item on each menu open; the new item goes in with the others.

- [ ] **Step 1: Write the window controller**

Create `Sources/SignalLadder/InspectorWindowController.swift`:

```swift
// Sources/SignalLadder/InspectorWindowController.swift
import AppKit
import SwiftUI

/// Holds the Inspector window for a menu-bar-only app.
///
/// Two things here are load-bearing and both are easy to get wrong:
///
/// `isReleasedWhenClosed` defaults to `true` for a programmatically created
/// NSWindow. Left alone, closing the Inspector frees the window while this
/// controller still points at it, and reopening dereferences freed memory.
///
/// An `.accessory` app is never frontmost on its own, so ordering the window
/// front is not enough — without an explicit activate it opens behind whatever
/// the user was looking at, which reads as the menu item doing nothing.
@MainActor
final class InspectorWindowController {
    private var window: NSWindow?

    func show(model: InspectorModel) {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "SignalLadder Inspector"
            window.contentView = NSHostingView(rootView: InspectorView(model: model))
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
```

- [ ] **Step 2: Wire it into the delegate**

In `Sources/SignalLadder/AppDelegate.swift`, add beside the other stored properties:

```swift
    private let inspector = InspectorWindowController()
    private let inspectorModel = InspectorModel()
```

In `rebuildMenu()`, immediately after the `"Captured \(count) notification…"` item and before the separator that precedes Quit, add:

```swift
        let inspect = NSMenuItem(title: "Show Inspector…",
                                 action: #selector(showInspector),
                                 keyEquivalent: "i")
        inspect.target = self
        menu.addItem(inspect)
```

Add the action and the model sync near the other `@objc` handlers:

```swift
    @objc private func showInspector() {
        syncInspector()
        inspector.show(model: inspectorModel)
    }

    /// The model is refreshed from the buffer rather than subscribing to it,
    /// because the buffer is a plain value type by design and the app has
    /// exactly two moments when the Inspector can be stale: a new capture, and
    /// a health change. Both call here.
    private func syncInspector() {
        inspectorModel.refresh(from: capture.history)
        inspectorModel.setHealth(summary: healthTitle, health: health)
    }
```

Call `syncInspector()` from `rebuildMenu()`'s first line, so the window tracks captures while it is open:

```swift
    private func rebuildMenu() {
        guard let item = statusItem, let menu = item.menu else { return }
        syncInspector()
```

- [ ] **Step 3: Build and run the suite**

Run: `swift build && swift test`
Expected: build clean with zero warnings; PASS, 92 tests.

- [ ] **Step 4: Assemble and launch**

Run: `./Scripts/make-app.sh && open build/SignalLadder.app`
Expected: `Built build/SignalLadder.app`, app appears in the menu bar.

- [ ] **Step 5: Commit**

```bash
git add Sources/SignalLadder/InspectorWindowController.swift Sources/SignalLadder/AppDelegate.swift
git commit -m "feat: open the Inspector from the menu bar"
```

---

## Task 6: Live verification

**Files:**

- Modify: `Scripts/verify-live.sh`
- Modify: `docs/dev/notes/2026-09-11-m1-findings.md`

**Context the implementer needs:** `Scripts/verify-live.sh` already reads the menu over the Accessibility API with `osascript`, posts a test notification, and asserts the capture count moves. Its `read_menu` helper opens the status item, collects `name of every menu item`, and presses Escape. Extend it; do not rewrite it. Note that `log` is a zsh builtin — the script uses `/usr/bin/log` throughout and must continue to.

- [ ] **Step 1: Assert the Inspector menu item exists**

In `Scripts/verify-live.sh`, in the "Menu state" section after the `CAUSE` block, add:

```bash
if printf '%s' "$MENU" | grep -q "Show Inspector"; then
    ok "Inspector is reachable from the menu"
else
    bad "no Inspector item in the menu"
fi
```

- [ ] **Step 2: Assert the Inspector window can open and is titled**

Add a new section before "Resource cost":

```bash
head_ "Inspector"

INSPECTOR=$(osascript <<'APPLESCRIPT' 2>/dev/null
tell application "System Events"
  tell process "SignalLadder"
    set itm to menu bar item 1 of menu bar 1
    perform action "AXPress" of itm
    delay 1.0
    try
      click menu item "Show Inspector…" of menu 1 of itm
    on error
      key code 53
      return "could not click"
    end try
    delay 1.5
    set names to name of every window
    set AppleScript's text item delimiters to linefeed
    return names as text
  end tell
end tell
APPLESCRIPT
)

if printf '%s' "$INSPECTOR" | grep -q "SignalLadder Inspector"; then
    ok "Inspector window opened"
else
    bad "Inspector window did not open (got: ${INSPECTOR:-nothing})"
fi
```

- [ ] **Step 3: Run the harness**

Run: `./Scripts/make-app.sh && open build/SignalLadder.app && sleep 12 && ./Scripts/verify-live.sh`
Expected: every check passes, exit 0. If the Inspector check fails with "could not click", the menu item title in the script must match `AppDelegate` exactly, ellipsis character included.

- [ ] **Step 4: Human verification — these need a person**

Run the app and confirm by eye, because no script can assert that a layout reads well:

- [ ] Trigger a notification from another app. It appears in the Inspector as the top row, with app, title and body in the right fields.
- [ ] Expand **Raw**. The unparsed string is shown and is selectable.
- [ ] The subrole is visible on the row.
- [ ] Send several notifications quickly from the same app. The "in the last hour" count rises.
- [ ] Every row reads **Not evaluated — no rules yet**, never "matched no rule".
- [ ] Quit and relaunch. The Inspector is empty — content died with the process, as §6 requires.
- [ ] With capture healthy and no notifications, the empty state says it is simply quiet.
- [ ] Turn on Do Not Disturb, wait for a failed self-test, and reopen the Inspector. The empty state now says capture cannot be confirmed and names the cause. **This is the check the milestone exists for.**

- [ ] **Step 5: Record the results**

Append an "M2c verification" section to `docs/dev/notes/2026-09-11-m1-findings.md` covering: whether suppressed repeats were ever observed (settling the question M1 left open), measured idle CPU with the Inspector open, and whether the under-counted flag was ever seen in real traffic.

- [ ] **Step 6: Commit**

```bash
git add Scripts/verify-live.sh docs/dev/notes/2026-09-11-m1-findings.md
git commit -m "test: cover the Inspector in the live harness"
```

---

## Done when

- `swift test` passes at 92 tests.
- The Inspector opens from the menu bar and lists captures newest first.
- Each row shows parsed fields, expandable raw text, subrole, recent count, and an explicit _not evaluated_ state.
- An empty Inspector states whether nothing arrived or nothing could arrive.
- Notification content exists only in memory and is gone after a relaunch.
- `PurityTests` fails the build if anything in `NotificationCore` imports a UI framework or references a file or network API.

## Not in this plan

`RuleEngine` and rule matching are M3 — the annotation column stays empty here by design. The authoring loop (§7.3), including "Make a rule from this" and dry-running a rule against the ring buffer, is M3; M2c builds the buffer that loop depends on. `onCall` and `screenLocked` are M5, and are deliberately absent from `ContextSnapshot` rather than stubbed.

Two known defects remain open and are **not** addressed here: `AXElementNode` conflating "attribute absent" with "read failed", and `CaptureDeduplicator` keying on content rather than element identity. The second is now _observable_ through the Inspector's suppressed-repeat count, which is the evidence needed to fix it correctly rather than by guess.
