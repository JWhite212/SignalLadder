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
    private var delivery: DeliveryStatus?
    private var canaryTimer: Timer?

    /// Retained between refreshes so the menu can re-evaluate health
    /// synchronously without spending a canary on every open. nil when no
    /// self-test has completed; 0 when the last one succeeded; otherwise the
    /// number of consecutive failures.
    private var consecutiveCanaryFailures: Int?

    /// Whether the last failed self-test saw no accessibility events at all,
    /// meaning its banner was never drawn and capture was never exercised.
    private var canaryFailedWithNoBannerActivity = false

    private var retryTimer: Timer?
    private var retryDelay: TimeInterval = 60

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        setUpStatusItem()

        // Capture and the self-test schedule are established BEFORE any await.
        // requestAuthorization does not return until the user answers the
        // system dialog, so anything sequenced after it is hostage to whether
        // they ever do — and an app that captures nothing while reporting
        // "Checking…" would never complain about its own paralysis.
        _ = OnboardingCoordinator.requestAccessibilityIfNeeded()
        startCaptureIfTrusted()
        scheduleCanary()

        Task { @MainActor in
            _ = await OnboardingCoordinator.requestNotificationAuthorization()
            startCaptureIfTrusted()   // trust may have been granted meanwhile
            await refreshHealth(runCanary: true)
        }
    }

    // MARK: - Capture

    /// Called both at launch and on every menu open, which is what removes
    /// M2a's relaunch requirement: granting Accessibility while the app runs
    /// now takes effect the next time the menu is opened.
    @discardableResult
    private func startCaptureIfTrusted() -> Bool {
        guard AXIsProcessTrusted(), !capture.isRunning else { return false }
        capture.onChange = { [weak self] in self?.rebuildMenu() }
        capture.onAttach = { [weak self] in
            Task { @MainActor in await self?.refreshHealth(runCanary: true) }
        }
        capture.start()
        return true
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

    /// The advice tells the user the app will retry within the minute. Before
    /// this it did not: the next self-test was up to 30 minutes away, and a
    /// live run showed the app still claiming "cannot verify itself" fourteen
    /// minutes after the Do Not Disturb that caused it had been switched off —
    /// while capturing notifications perfectly well the whole time.
    ///
    /// Backs off towards the normal cadence so a long Focus does not mean a
    /// self-test notification every minute all evening.
    private func scheduleCanaryRetry() {
        retryTimer?.invalidate()
        let timer = Timer(timeInterval: retryDelay, repeats: false) { [weak self] _ in
            Task { @MainActor in await self?.refreshHealth(runCanary: true) }
        }
        RunLoop.main.add(timer, forMode: .common)
        retryTimer = timer
        retryDelay = min(retryDelay * 2, 30 * 60)
    }

    private func cancelCanaryRetry() {
        retryTimer?.invalidate()
        retryTimer = nil
        retryDelay = 60
    }

    private func refreshHealth(runCanary: Bool) async {
        delivery = await DeliveryStatusProbe.current()

        // Only a canary that actually ran carries information. A nil result
        // means none ran — discarding a previous verified state for that
        // would regress the display to "Checking…" for no reason.
        if runCanary, delivery?.wouldDisplay == true, AXIsProcessTrusted(), capture.observerAttached {
            // Snapshotted across the whole round trip. If Notification Centre
            // drew nothing in that window, the alert was suppressed and the
            // failure says nothing about capture.
            let eventsBefore = capture.observerEventCount
            if let succeeded = await canary.run() {
                consecutiveCanaryFailures = succeeded ? 0 : (consecutiveCanaryFailures ?? 0) + 1
                canaryFailedWithNoBannerActivity =
                    !succeeded && capture.observerEventCount == eventsBefore
                succeeded ? cancelCanaryRetry() : scheduleCanaryRetry()
            }
        }

        health = HealthEvaluator.evaluate(
            HealthInputs(accessibilityTrusted: AXIsProcessTrusted(),
                         observerAttached: capture.observerAttached,
                         notificationsAuthorized: delivery?.authorized ?? false,
                         notificationsWouldDisplay: delivery?.wouldDisplay ?? false,
                         consecutiveCanaryFailures: consecutiveCanaryFailures,
                         canaryFailedWithNoBannerActivity: canaryFailedWithNoBannerActivity)
        )

        alarm.report(health, deliveryHealthy: delivery?.wouldDisplay == true)
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
        let justStarted = startCaptureIfTrusted()

        // Nothing has been probed yet, so there is nothing honest to report.
        guard let delivery else {
            health = .unknown
            rebuildMenu()
            return
        }

        // Re-evaluate synchronously from what can be read without awaiting,
        // reusing the last known delivery status. rebuildMenu renders from
        // `health`, so without this the menu would keep reporting a problem
        // that has already been fixed — a false alarm lasting until the next
        // scheduled canary.
        health = HealthEvaluator.evaluate(
            HealthInputs(accessibilityTrusted: AXIsProcessTrusted(),
                         observerAttached: capture.observerAttached,
                         notificationsAuthorized: delivery.authorized,
                         notificationsWouldDisplay: delivery.wouldDisplay,
                         consecutiveCanaryFailures: consecutiveCanaryFailures,
                         canaryFailedWithNoBannerActivity: canaryFailedWithNoBannerActivity)
        )
        rebuildMenu()

        // Capture has only just begun, so nothing has been verified yet.
        // Prove it for real rather than leaving the user on an assumption.
        if justStarted {
            Task { @MainActor in await self.refreshHealth(runCanary: true) }
        }

        // The synchronous pass above reuses last-known delivery, which goes
        // stale in both directions. Re-probe without spending a self-test so
        // the next open is accurate.
        Task { @MainActor in await self.refreshHealth(runCanary: false) }
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
