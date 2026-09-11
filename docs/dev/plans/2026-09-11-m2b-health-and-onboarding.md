# M2b Health and Onboarding Implementation Plan

**Goal:** Make the app prove it can still see notifications, and say so loudly when it cannot — through alarm channels that cannot be silenced by the same fault they exist to report.

**Architecture:** A pure `HealthEvaluator` in `NotificationCore` turns four independent inputs into a health state and an ordered list of likely causes — testable with no permissions and no OS. A `DeliveryStatusProbe` in `NotificationCapture` reads `UNUserNotificationCenter` settings so "the banner never displayed" is diagnosed separately from "we failed to capture it". A `CanaryService` posts the app's own notification and asserts the production pipeline captures it back. Three alarm channels report failure, two of which depend on neither the notification system nor the Accessibility API.

**Tech Stack:** Swift 5.9+, SPM, XCTest, UserNotifications, AppKit, ApplicationServices.

**Spec:** `docs/dev/specs/2026-09-11-macos-notification-router-design.md` — §9 in particular.
**Prior:** `docs/dev/notes/2026-09-11-m1-findings.md`, `docs/dev/notes/2026-09-11-m2-handover.md`

## Global Constraints

- **Minimum macOS 14.0**; `.macOS(.v14)`; Swift tools version 5.9 exactly.
- **No third-party dependencies.**
- **Notification content is never written to disk.** Note `AXBannerWatcher.log()` writes to stderr, which in a bundled app is captured by the unified log and **persisted** — never pass content through it.
- **`NotificationCore` must not import `ApplicationServices`, `AppKit`, `Cocoa`, `Carbon`, or `UserNotifications`.** Enforced by `PurityTests`, which must be extended to cover the new framework.
- **Event-driven, never polling**, except the canary's deliberate interval.
- Menu-bar only; bundle id `com.jamiewhite.signalladder`; Hardened Runtime; sandbox off.

## Why this milestone exists

M1 shipped a re-attach mechanism that was structurally broken and passed three code reviews. An `AXObserver` on a dead process emits no error — it goes quiet. **This class of failure is undetectable by inspection; only an active check finds it.**

The design rule that follows, and which every task here serves: **an alarm must not share a failure mode with the thing it reports on.** The canary posts through `UNUserNotificationCenter`; so if the alarm _also_ went through `UNUserNotificationCenter`, revoking notification permission would break the canary and silence the alarm simultaneously.

---

## File Structure

```
Sources/NotificationCore/CaptureHealth.swift          State + cause model (pure)
Sources/NotificationCore/HealthEvaluator.swift        Inputs -> state + causes (pure)
Sources/NotificationCapture/DeliveryStatusProbe.swift Reads UN settings
Sources/NotificationCapture/CanaryService.swift       Posts and awaits round-trip
Sources/SignalLadder/HealthAlarm.swift                Three independent channels
Sources/SignalLadder/OnboardingCoordinator.swift      Permission sequence
Sources/SignalLadder/AppDelegate.swift                Wiring, live trust recovery
Tests/NotificationCoreTests/HealthEvaluatorTests.swift
Tests/NotificationCoreTests/PurityTests.swift         Extended: + UserNotifications
```

---

## Task 1: The health model

Pure, therefore testable without permissions or an OS. This is spec §9.2's delivery-versus-capture split made explicit.

**Files:**

- Create: `Sources/NotificationCore/CaptureHealth.swift`
- Create: `Sources/NotificationCore/HealthEvaluator.swift`
- Create: `Tests/NotificationCoreTests/HealthEvaluatorTests.swift`
- Modify: `Tests/NotificationCoreTests/PurityTests.swift`

**Interfaces:**

- Consumes: nothing
- Produces: `enum CaptureHealth`, `enum HealthCause`, `struct HealthInputs`, `enum HealthEvaluator { static func evaluate(_:) -> CaptureHealth }`

- [ ] **Step 1: Write the model**

```swift
// Sources/NotificationCore/CaptureHealth.swift
import Foundation

/// Why the pipeline might not be working, ordered by how actionable it is.
///
/// The split between delivery and capture matters more than it looks. If the
/// banner was never displayed, the Accessibility layer had nothing to see and
/// is not at fault — diagnosing that as "capture broken" sends the user to fix
/// the wrong thing, and would have them re-granting Accessibility to cure a
/// muted notification setting.
public enum HealthCause: Equatable, Sendable {
    // Delivery — the banner never appeared, so capture was never exercised.
    case notificationPermissionDenied
    case notificationsSuppressed      // alert style None, or a Focus/DND

    // Capture — the banner appeared and we failed to see it.
    case accessibilityNotTrusted
    case observerNotAttached
    case lazyAccessibilityTree        // the macOS 15.4-class bug

    public var isDeliveryFault: Bool {
        switch self {
        case .notificationPermissionDenied, .notificationsSuppressed: return true
        case .accessibilityNotTrusted, .observerNotAttached, .lazyAccessibilityTree: return false
        }
    }

    /// Shown to the user. Says what to do, not merely what is wrong.
    public var advice: String {
        switch self {
        case .notificationPermissionDenied:
            return "Allow notifications for SignalLadder in System Settings — without it the app cannot verify it is working."
        case .notificationsSuppressed:
            return "SignalLadder's own alerts are suppressed (alert style set to None, or a Focus is active), so it cannot verify itself."
        case .accessibilityNotTrusted:
            return "Grant Accessibility to SignalLadder in System Settings — without it no notifications can be read."
        case .observerNotAttached:
            return "Not attached to Notification Centre. It may be restarting; this usually recovers within seconds."
        case .lazyAccessibilityTree:
            return "macOS is not exposing notifications to assistive apps. Turning on Full Keyboard Access in System Settings › Keyboard is the known workaround."
        }
    }
}

public enum CaptureHealth: Equatable, Sendable {
    /// A canary round-tripped. The only state that is positive evidence.
    case verified
    /// Nothing is known yet — at launch, before the first canary.
    case unknown
    /// Working, but something reduces confidence.
    case degraded([HealthCause])
    /// Not capturing. Causes are ordered most-likely first.
    case blind([HealthCause])

    public var isAlarming: Bool {
        switch self {
        case .verified, .unknown: return false
        case .degraded, .blind: return true
        }
    }
}
```

```swift
// Sources/NotificationCore/HealthEvaluator.swift
import Foundation

/// Everything the evaluator needs, as plain values — so every combination is
/// reachable in a test without an OS, a permission, or a real notification.
public struct HealthInputs: Equatable, Sendable {
    public var accessibilityTrusted: Bool
    public var observerAttached: Bool
    public var notificationsAuthorized: Bool
    public var notificationsWouldDisplay: Bool
    /// nil when no canary has completed yet.
    public var lastCanarySucceeded: Bool?

    public init(accessibilityTrusted: Bool,
                observerAttached: Bool,
                notificationsAuthorized: Bool,
                notificationsWouldDisplay: Bool,
                lastCanarySucceeded: Bool?) {
        self.accessibilityTrusted = accessibilityTrusted
        self.observerAttached = observerAttached
        self.notificationsAuthorized = notificationsAuthorized
        self.notificationsWouldDisplay = notificationsWouldDisplay
        self.lastCanarySucceeded = lastCanarySucceeded
    }
}

public enum HealthEvaluator {
    /// Delivery is judged BEFORE capture, deliberately. A failed canary with
    /// notifications suppressed says nothing about whether capture works — the
    /// banner never appeared — so reporting "blind" there would be a lie that
    /// sends the user to re-grant Accessibility for no reason.
    public static func evaluate(_ i: HealthInputs) -> CaptureHealth {
        // Capture faults are definite regardless of the canary: without trust
        // or an observer, nothing can be captured, canary or not.
        if !i.accessibilityTrusted {
            return .blind([.accessibilityNotTrusted])
        }
        if !i.observerAttached {
            return .blind([.observerNotAttached])
        }

        // Delivery faults degrade rather than blind: capture may be perfectly
        // healthy, we simply cannot PROVE it, because our own test notification
        // cannot be displayed.
        var deliveryFaults: [HealthCause] = []
        if !i.notificationsAuthorized { deliveryFaults.append(.notificationPermissionDenied) }
        if !i.notificationsWouldDisplay { deliveryFaults.append(.notificationsSuppressed) }
        if !deliveryFaults.isEmpty {
            return .degraded(deliveryFaults)
        }

        switch i.lastCanarySucceeded {
        case .none:  return .unknown
        case .some(true): return .verified
        // Delivery is confirmed healthy and capture is nominally configured,
        // yet the round trip failed. The lazy-tree bug is what remains.
        case .some(false): return .blind([.lazyAccessibilityTree])
        }
    }
}
```

- [ ] **Step 2: Write the failing tests**

```swift
// Tests/NotificationCoreTests/HealthEvaluatorTests.swift
import XCTest
@testable import NotificationCore

final class HealthEvaluatorTests: XCTestCase {
    private func inputs(trusted: Bool = true,
                        attached: Bool = true,
                        authorized: Bool = true,
                        wouldDisplay: Bool = true,
                        canary: Bool? = true) -> HealthInputs {
        HealthInputs(accessibilityTrusted: trusted,
                     observerAttached: attached,
                     notificationsAuthorized: authorized,
                     notificationsWouldDisplay: wouldDisplay,
                     lastCanarySucceeded: canary)
    }

    func testEverythingHealthyAndCanaryPassedIsVerified() {
        XCTAssertEqual(HealthEvaluator.evaluate(inputs()), .verified)
    }

    func testNoCanaryYetIsUnknownNotVerified() {
        XCTAssertEqual(HealthEvaluator.evaluate(inputs(canary: nil)), .unknown)
    }

    func testUntrustedIsBlindRegardlessOfEverythingElse() {
        XCTAssertEqual(HealthEvaluator.evaluate(inputs(trusted: false)),
                       .blind([.accessibilityNotTrusted]))
    }

    func testDetachedObserverIsBlind() {
        XCTAssertEqual(HealthEvaluator.evaluate(inputs(attached: false)),
                       .blind([.observerNotAttached]))
    }

    /// The central rule: a failed canary with notifications suppressed must
    /// NOT be reported as a capture fault. The banner never appeared, so
    /// capture was never tested.
    func testSuppressedNotificationsDegradeRatherThanBlind() {
        let health = HealthEvaluator.evaluate(inputs(wouldDisplay: false, canary: false))
        XCTAssertEqual(health, .degraded([.notificationsSuppressed]))
    }

    func testDeniedNotificationPermissionDegradesRatherThanBlinds() {
        let health = HealthEvaluator.evaluate(inputs(authorized: false, canary: false))
        XCTAssertEqual(health, .degraded([.notificationPermissionDenied]))
    }

    func testBothDeliveryFaultsAreReportedTogether() {
        let health = HealthEvaluator.evaluate(inputs(authorized: false, wouldDisplay: false, canary: false))
        XCTAssertEqual(health, .degraded([.notificationPermissionDenied, .notificationsSuppressed]))
    }

    /// Delivery confirmed working, capture configured, and the round trip
    /// still failed — this is the macOS 15.4 lazy-tree signature.
    func testFailedCanaryWithHealthyDeliveryIsBlindOnTheLazyTree() {
        XCTAssertEqual(HealthEvaluator.evaluate(inputs(canary: false)),
                       .blind([.lazyAccessibilityTree]))
    }

    func testCaptureFaultsOutrankDeliveryFaults() {
        // Untrusted AND suppressed: the capture fault is the actionable one.
        let health = HealthEvaluator.evaluate(inputs(trusted: false, wouldDisplay: false, canary: false))
        XCTAssertEqual(health, .blind([.accessibilityNotTrusted]))
    }

    func testDeliveryAndCaptureFaultsAreCorrectlyClassified() {
        XCTAssertTrue(HealthCause.notificationPermissionDenied.isDeliveryFault)
        XCTAssertTrue(HealthCause.notificationsSuppressed.isDeliveryFault)
        XCTAssertFalse(HealthCause.accessibilityNotTrusted.isDeliveryFault)
        XCTAssertFalse(HealthCause.observerNotAttached.isDeliveryFault)
        XCTAssertFalse(HealthCause.lazyAccessibilityTree.isDeliveryFault)
    }

    func testOnlyVerifiedAndUnknownAreNonAlarming() {
        XCTAssertFalse(CaptureHealth.verified.isAlarming)
        XCTAssertFalse(CaptureHealth.unknown.isAlarming)
        XCTAssertTrue(CaptureHealth.degraded([.notificationsSuppressed]).isAlarming)
        XCTAssertTrue(CaptureHealth.blind([.lazyAccessibilityTree]).isAlarming)
    }

    func testEveryCauseHasAdviceThatIsNotEmpty() {
        let all: [HealthCause] = [.notificationPermissionDenied, .notificationsSuppressed,
                                  .accessibilityNotTrusted, .observerNotAttached,
                                  .lazyAccessibilityTree]
        for cause in all {
            XCTAssertFalse(cause.advice.isEmpty, "\(cause) has no advice")
        }
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `swift test --filter HealthEvaluatorTests`
Expected: FAIL — `cannot find 'HealthEvaluator' in scope`.

- [ ] **Step 4: Run them again to verify they pass**

Run: `swift test --filter HealthEvaluatorTests`
Expected: PASS, 11 tests.

- [ ] **Step 5: Extend PurityTests to cover UserNotifications**

`NotificationCore` must not gain a dependency on the notification system. In `PurityTests.swift`, change the forbidden list to:

```swift
        let forbidden = ["ApplicationServices", "AppKit", "Cocoa", "Carbon", "UserNotifications"]
```

- [ ] **Step 6: Run the full suite**

Run: `swift test`
Expected: PASS — 49 tests (38 existing + 11 new).

- [ ] **Step 7: Commit**

```bash
git add Sources/NotificationCore/ Tests/NotificationCoreTests/
git commit -m "feat: health model splitting delivery faults from capture faults"
```

---

## Task 2: Delivery status probe

Reads whether the app's own notifications would actually be displayed. Without this, a failed canary is ambiguous.

**Files:**

- Create: `Sources/NotificationCapture/DeliveryStatusProbe.swift`

**Interfaces:**

- Consumes: `UNUserNotificationCenter`
- Produces: `public struct DeliveryStatus`, `public enum DeliveryStatusProbe { static func current() async -> DeliveryStatus }`

- [ ] **Step 1: Write the probe**

```swift
// Sources/NotificationCapture/DeliveryStatusProbe.swift
import Foundation
import UserNotifications

public struct DeliveryStatus: Equatable, Sendable {
    public let authorized: Bool
    public let wouldDisplay: Bool

    public init(authorized: Bool, wouldDisplay: Bool) {
        self.authorized = authorized
        self.wouldDisplay = wouldDisplay
    }
}

/// Answers "would our own notification actually appear on screen?".
///
/// This is checked independently of, and before, any capture diagnosis. If the
/// banner would never be displayed then the Accessibility layer had nothing to
/// see, and blaming capture would send the user to re-grant a permission that
/// was never the problem.
public enum DeliveryStatusProbe {
    public static func current() async -> DeliveryStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()

        let authorized = settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional

        // A banner or alert must be enabled. Notification Centre delivery alone
        // is not enough: nothing is drawn on screen, so nothing is capturable.
        let styleShows = settings.alertSetting == .enabled
        let notFiltered = settings.notificationCenterSetting != .disabled

        return DeliveryStatus(
            authorized: authorized,
            wouldDisplay: authorized && styleShows && notFiltered
        )
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: clean, zero warnings.

- [ ] **Step 3: Run the suite**

Run: `swift test`
Expected: 49 tests, 0 failures. `PurityTests` must still pass — `UserNotifications` is imported in `NotificationCapture`, never in `NotificationCore`.

- [ ] **Step 4: Commit**

```bash
git add Sources/NotificationCapture/DeliveryStatusProbe.swift
git commit -m "feat: probe whether our own notifications would be displayed"
```

---

## Task 3: The canary

Posts the app's own notification carrying a unique marker and asserts the production pipeline captures it back.

**Files:**

- Create: `Sources/NotificationCapture/CanaryService.swift`

**Interfaces:**

- Consumes: `UNUserNotificationCenter`, capture events
- Produces: `public final class CanaryService` with `func run(timeout:) async -> Bool`, `func noteCapture(rawText:) -> Bool`

- [ ] **Step 1: Write the service**

```swift
// Sources/NotificationCapture/CanaryService.swift
import Foundation
import UserNotifications

/// Proves the pipeline is alive by sending a notification through it.
///
/// Absence of notifications proves nothing — it may simply be quiet. A failed
/// round trip proves something. This is the only positive evidence the app
/// ever has that capture works.
///
/// Main-actor isolated: `pendingMarker` and `continuation` are touched both by
/// the timeout Task and by the capture callback, and a race there would either
/// resume the continuation twice (a crash) or leave it hanging forever.
@MainActor
public final class CanaryService {
    /// Recognisable, and unlikely to occur in real traffic.
    private static let markerPrefix = "SignalLadder canary "

    private var pendingMarker: String?
    private var continuation: CheckedContinuation<Bool, Never>?

    public init() {}

    /// True if a captured notification was ours. Callers MUST consult this and
    /// exclude matches from user-visible counts and history — the canary is
    /// the app talking to itself, not a notification the user received.
    public func noteCapture(rawText: String) -> Bool {
        guard let marker = pendingMarker, rawText.contains(marker) else { return false }
        pendingMarker = nil
        continuation?.resume(returning: true)
        continuation = nil
        return true
    }

    public func run(timeout: TimeInterval = 5.0) async -> Bool {
        let marker = Self.markerPrefix + UUID().uuidString
        pendingMarker = marker

        let content = UNMutableNotificationContent()
        content.title = "SignalLadder self-test"
        content.body = marker

        let request = UNNotificationRequest(
            identifier: marker,
            content: content,
            trigger: nil   // deliver immediately
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            pendingMarker = nil
            return false
        }

        let captured = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            self.continuation = c
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if self.pendingMarker == marker {
                    self.pendingMarker = nil
                    self.continuation?.resume(returning: false)
                    self.continuation = nil
                }
            }
        }

        // Do not leave our own test notification sitting in Notification Centre.
        UNUserNotificationCenter.current()
            .removeDeliveredNotifications(withIdentifiers: [marker])

        return captured
    }
}
```

- [ ] **Step 2: Build and test**

Run: `swift build` then `swift test`
Expected: clean build, zero warnings; 49 tests, 0 failures.

- [ ] **Step 3: Commit**

```bash
git add Sources/NotificationCapture/CanaryService.swift
git commit -m "feat: canary proving the capture pipeline round-trips"
```

---

## Task 4: Three independent alarm channels

**Files:**

- Create: `Sources/SignalLadder/HealthAlarm.swift`

**Interfaces:**

- Consumes: `CaptureHealth`
- Produces: `final class HealthAlarm` with `func report(_ health: CaptureHealth, deliveryHealthy: Bool)`

- [ ] **Step 1: Write the alarm**

```swift
// Sources/SignalLadder/HealthAlarm.swift
import AppKit
import UserNotifications
import NotificationCore

/// Reports failure through channels chosen so no single fault silences them all.
///
/// Three channels: the menu-bar glyph (Task 5, pure AppKit, always visible),
/// an audible alert (pure AppKit), and a system notification (only when
/// delivery is confirmed working).
///
/// This matters more than it appears. The canary posts through
/// UNUserNotificationCenter — so if the alarm also went through
/// UNUserNotificationCenter, revoking notification permission would break the
/// canary AND silence the alarm about it, in one step. Channels 1 and 2
/// therefore depend on neither the notification system nor Accessibility.
final class HealthAlarm {
    private var lastReported: CaptureHealth?

    /// - Parameter deliveryHealthy: whether our own notifications can actually
    ///   be displayed. Channel 3 is skipped when false, because it is useless
    ///   precisely when delivery is the problem.
    func report(_ health: CaptureHealth, deliveryHealthy: Bool) {
        guard health != lastReported else { return }   // do not nag
        lastReported = health
        guard health.isAlarming else { return }

        let causes: [HealthCause]
        switch health {
        case .blind(let c), .degraded(let c): causes = c
        case .verified, .unknown: return
        }

        // Channel 2 — audible, via AppKit only. Depends on neither the
        // Accessibility API nor the notification system, so it survives a
        // fault in either. (Channel 1 is the menu-bar glyph, always visible,
        // rebuilt on open in Task 5.)
        NSSound.beep()

        // Channel 3 — richer and clickable, but useless when delivery is the
        // fault, so only used when delivery is confirmed working.
        guard deliveryHealthy else { return }
        let content = UNMutableNotificationContent()
        content.title = health.isBlindState ? "SignalLadder is not capturing" : "SignalLadder cannot verify itself"
        content.body = causes.first?.advice ?? "Open the menu for details."
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "signalladder.health", content: content, trigger: nil)
        )
    }
}

private extension CaptureHealth {
    var isBlindState: Bool {
        if case .blind = self { return true }
        return false
    }
}
```

Channel 1, the status-item glyph, lives in Task 5 because it is a property of the menu rather than an event — it is always visible rather than fired once, and the menu is rebuilt on open.

- [ ] **Step 2: Build and test**

Run: `swift build` then `swift test`
Expected: clean, 49 tests passing.

- [ ] **Step 3: Commit**

```bash
git add Sources/SignalLadder/HealthAlarm.swift
git commit -m "feat: alarm channels that a single fault cannot silence"
```

---

## Task 5: Onboarding and live wiring

Requests permissions in order, wires health into the menu, and makes the menu rebuild on open so granting Accessibility no longer needs a relaunch.

**One detail decides whether the canary works at all.** By default macOS does not display an app's own notification while that app is active, so `UNUserNotificationCenterDelegate.userNotificationCenter(_:willPresent:)` must explicitly return `.banner`. Without it the canary's notification is never drawn, the round trip always fails, and the app reports a capture fault when capture is perfectly healthy. It is included in the `AppDelegate` rewrite below.

**Files:**

- Create: `Sources/SignalLadder/OnboardingCoordinator.swift`
- Modify: `Sources/SignalLadder/AppDelegate.swift`
- Modify: `Sources/SignalLadder/CaptureController.swift`
- Modify: `Resources/Info.plist`

**Interfaces:**

- Consumes: everything above
- Produces: a menu showing live health, and permission requests at first run

- [ ] **Step 1: Add the usage description**

In `Resources/Info.plist`, before `NSHumanReadableCopyright`:

```xml
    <key>NSUserNotificationsUsageDescription</key>
    <string>SignalLadder sends itself a silent test notification to verify it can still read your notifications. It never sends you alerts you did not configure.</string>
```

- [ ] **Step 2: Write the onboarding coordinator**

```swift
// Sources/SignalLadder/OnboardingCoordinator.swift
import AppKit
import ApplicationServices
import UserNotifications

/// Requests the permissions the app needs, in the order that makes them
/// explicable.
///
/// Accessibility first, because it is the one that sounds alarming and needs
/// justifying. Notifications second, framed as how the app proves it is
/// working — which is true, and is why the request is not optional.
enum OnboardingCoordinator {
    static func requestNotificationAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert])
        } catch {
            return false
        }
    }

    static func requestAccessibilityIfNeeded() -> Bool {
        if AXIsProcessTrusted() { return true }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    static func openNotificationSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!
        NSWorkspace.shared.open(url)
    }
}
```

- [ ] **Step 3: Expose whether the observer is attached**

`HealthInputs.observerAttached` has no source yet. In `Sources/NotificationCapture/AXBannerWatcher.swift`, add a public read-only property beside the existing stored properties:

```swift
    /// Whether an observer is currently registered. Feeds the health model —
    /// an unattached watcher captures nothing, whatever else is healthy.
    public var isAttached: Bool { observer != nil }
```

- [ ] **Step 4: Expose it through the capture controller**

Replace `Sources/SignalLadder/CaptureController.swift` entirely:

```swift
// Sources/SignalLadder/CaptureController.swift
import Foundation
import NotificationCore
import NotificationCapture

@MainActor
final class CaptureController {
    private(set) var captureCount = 0
    private(set) var lastCaptureAt: Date?

    var onChange: (() -> Void)?

    private var watcher: AXBannerWatcher?
    private let dedupe = CaptureDeduplicator()
    private let canary: CanaryService

    /// False whenever the watcher is absent or detached — either way nothing
    /// can be captured, which the health model needs to know.
    var observerAttached: Bool { watcher?.isAttached ?? false }

    init(canary: CanaryService) {
        self.canary = canary
    }

    func start() {
        let watcher = AXBannerWatcher { [weak self] raw, textChildren in
            guard let self else { return }
            let notification = NotificationFieldExtractor.extract(raw, textChildren: textChildren)

            // The canary is the app talking to itself. It must be recognised
            // BEFORE dedupe and excluded from the count, or self-tests would
            // inflate a number the user reads as real traffic.
            if self.canary.noteCapture(rawText: notification.rawText) { return }

            let decision = self.dedupe.admit(notification.rawText, at: notification.timestamp)
            guard !decision.isRepeat else { return }

            self.captureCount += 1
            self.lastCaptureAt = notification.timestamp
            // Content is intentionally dropped here, not stored.
            self.onChange?()
        }
        watcher.start()
        self.watcher = watcher
    }

    var isRunning: Bool { watcher != nil }
}
```

- [ ] **Step 5: Rewrite AppDelegate to wire health, onboarding and live recovery**

Replace `Sources/SignalLadder/AppDelegate.swift` entirely:

```swift
// Sources/SignalLadder/AppDelegate.swift
import AppKit
import ApplicationServices
import UserNotifications
import NotificationCore
import NotificationCapture

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let canary = CanaryService()
    private lazy var capture = CaptureController(canary: canary)
    private let alarm = HealthAlarm()

    private var health: CaptureHealth = .unknown
    private var delivery = DeliveryStatus(authorized: false, wouldDisplay: false)
    private var canaryTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        setUpStatusItem()

        Task { @MainActor in
            _ = OnboardingCoordinator.requestAccessibilityIfNeeded()
            _ = await OnboardingCoordinator.requestNotificationAuthorization()
            startCaptureIfTrusted()
            await refreshHealth(runCanary: true)
            scheduleCanary()
        }
    }

    // MARK: - Capture

    /// Called both at launch and on every menu open, which is what removes
    /// M2a's relaunch requirement: granting Accessibility while the app runs
    /// now takes effect the next time the menu is opened.
    private func startCaptureIfTrusted() {
        guard AXIsProcessTrusted(), !capture.isRunning else { return }
        capture.onChange = { [weak self] in self?.rebuildMenu() }
        capture.start()
    }

    // MARK: - Health

    private func scheduleCanary() {
        canaryTimer?.invalidate()
        // The one deliberate exception to "never poll". Absence of traffic is
        // not evidence of health, so health has to be asked for.
        let timer = Timer(timeInterval: 30 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshHealth(runCanary: true) }
        }
        RunLoop.main.add(timer, forMode: .common)
        canaryTimer = timer
    }

    private func refreshHealth(runCanary: Bool) async {
        delivery = await DeliveryStatusProbe.current()

        // Only spend a canary when it could actually succeed. Posting one that
        // cannot be displayed would fail for a delivery reason and risk being
        // read as a capture fault.
        var canaryResult: Bool? = nil
        if runCanary, delivery.wouldDisplay, AXIsProcessTrusted(), capture.observerAttached {
            canaryResult = await canary.run()
        }

        health = HealthEvaluator.evaluate(
            HealthInputs(accessibilityTrusted: AXIsProcessTrusted(),
                         observerAttached: capture.observerAttached,
                         notificationsAuthorized: delivery.authorized,
                         notificationsWouldDisplay: delivery.wouldDisplay,
                         lastCanarySucceeded: canaryResult)
        )

        alarm.report(health, deliveryHealthy: delivery.wouldDisplay)
        rebuildMenu()
    }

    // MARK: - Menu

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        rebuildMenu()
    }

    /// Rebuilding on open is what makes every value in the menu live. Without
    /// it NSMenu content is frozen at build time — a mistake that invalidated
    /// two rounds of the Focus spike.
    func menuNeedsUpdate(_ menu: NSMenu) {
        startCaptureIfTrusted()
        rebuildMenu()
    }

    private func rebuildMenu() {
        guard let item = statusItem, let menu = item.menu else { return }

        item.button?.image = NSImage(
            systemSymbolName: health.isAlarming ? "bell.slash.fill" : "bell.badge",
            accessibilityDescription: health.isAlarming ? "SignalLadder — problem" : "SignalLadder"
        )

        menu.removeAllItems()
        menu.addItem(withTitle: healthTitle, action: nil, keyEquivalent: "")

        if let cause = firstCause {
            let advice = NSMenuItem(title: cause.advice, action: #selector(openSettingsForCause), keyEquivalent: "")
            advice.target = self
            advice.representedObject = cause.isDeliveryFault
            menu.addItem(advice)
        }

        menu.addItem(.separator())
        let count = capture.captureCount
        menu.addItem(withTitle: "Captured \(count) notification\(count == 1 ? "" : "s")",
                     action: nil, keyEquivalent: "")

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit SignalLadder",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
    }

    private var healthTitle: String {
        switch health {
        case .verified:  return "Working — verified"
        case .unknown:   return "Checking…"
        case .degraded:  return "Cannot verify itself"
        case .blind:     return "NOT capturing notifications"
        }
    }

    private var firstCause: HealthCause? {
        switch health {
        case .blind(let c), .degraded(let c): return c.first
        case .verified, .unknown: return nil
        }
    }

    @objc private func openSettingsForCause(_ sender: NSMenuItem) {
        if sender.representedObject as? Bool == true {
            OnboardingCoordinator.openNotificationSettings()
        } else {
            OnboardingCoordinator.openAccessibilitySettings()
        }
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    // Without this the canary's own notification may never be drawn, and the
    // canary would report capture failure when capture is fine.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner]
    }
}
```

- [ ] **Step 6: Build and test**

Run: `swift build` then `swift test`
Expected: clean, zero warnings; 49 tests, 0 failures.

- [ ] **Step 7: Commit**

```bash
git add Sources/ Resources/Info.plist
git commit -m "feat: onboarding, live health in the menu, scheduled canary"
```

---

## Task 6: Live verification _(requires a human)_

- [ ] **Step 1: Build, sign and launch**

```bash
./Scripts/make-app.sh && open build/SignalLadder.app
```

- [ ] **Step 2: Verify the permission sequence**

Expect an Accessibility prompt and a notification-permission prompt. Grant both. The menu must now show a health line — and after the first canary, `verified`.

- [ ] **Step 3: Verify live recovery (M2a's known limitation)**

Quit. Revoke Accessibility in System Settings. Launch. The menu should say Accessibility is needed. **Without quitting**, re-grant it and reopen the menu — the app must recover and begin capturing with no relaunch.

- [ ] **Step 4: Verify delivery faults are not misreported as capture faults**

This is the check the milestone exists for. With everything working, set SignalLadder's notification style to **None** in System Settings › Notifications, then wait for the next canary or relaunch.

The app must report **degraded / cannot verify**, naming suppressed notifications — **not** blind, and **not** anything suggesting Accessibility is at fault.

- [ ] **Step 5: Verify the alarm survives its own failure mode**

With notification style still None, confirm an audible alert and the menu-bar glyph still report the problem. If the only signal were a system notification, there would be none — that is the failure this design exists to prevent.

- [ ] **Step 6: Confirm the canary is excluded from counts**

Watch the capture count across several canary cycles with no real notifications. It must not increase.

- [ ] **Step 7: Record results**

Append an "M2b verification" section to `docs/dev/notes/2026-09-11-m1-findings.md`, including measured idle CPU with the canary running.

---

## Done when

- `swift test` passes at 49 tests.
- The app requests both permissions on first run and explains why.
- The menu shows live health and recovers from a permission grant without relaunching.
- Suppressed notifications are reported as _cannot verify_, never as _not capturing_.
- Alarms still fire when the notification system is the thing that is broken.
- The canary does not inflate the capture count.

## Not in this plan

The Inspector window and ring buffer are M2c. Two known defects remain open and are **not** addressed here: `AXElementNode` conflating "attribute absent" with "read failed" (the canary does not catch it — it drops individual reads while health reads green), and content-keyed rather than identity-keyed deduplication. Both are recorded in the M2 handover.
