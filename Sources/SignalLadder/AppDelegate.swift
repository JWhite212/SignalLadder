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

    /// Retained between refreshes so the menu can re-evaluate health
    /// synchronously without spending a canary on every open.
    private var lastCanarySucceeded: Bool?

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
    @discardableResult
    private func startCaptureIfTrusted() -> Bool {
        guard AXIsProcessTrusted(), !capture.isRunning else { return false }
        capture.onChange = { [weak self] in self?.rebuildMenu() }
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

    private func refreshHealth(runCanary: Bool) async {
        delivery = await DeliveryStatusProbe.current()

        // Only a canary that actually ran carries information. A nil result
        // means none ran — discarding a previous verified state for that
        // would regress the display to "Checking…" for no reason.
        if runCanary, delivery.wouldDisplay, AXIsProcessTrusted(), capture.observerAttached {
            if let result = await canary.run() {
                lastCanarySucceeded = result
            }
        }

        health = HealthEvaluator.evaluate(
            HealthInputs(accessibilityTrusted: AXIsProcessTrusted(),
                         observerAttached: capture.observerAttached,
                         notificationsAuthorized: delivery.authorized,
                         notificationsWouldDisplay: delivery.wouldDisplay,
                         lastCanarySucceeded: lastCanarySucceeded)
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
        let justStarted = startCaptureIfTrusted()

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
                         lastCanarySucceeded: lastCanarySucceeded)
        )
        rebuildMenu()

        // Capture has only just begun, so nothing has been verified yet.
        // Prove it for real rather than leaving the user on an assumption.
        if justStarted {
            Task { @MainActor in await self.refreshHealth(runCanary: true) }
        }
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
