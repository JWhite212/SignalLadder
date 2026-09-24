// Sources/SignalLadder/AppDelegate.swift
import AppKit
import ApplicationServices
import UserNotifications
import NotificationCore
import NotificationCapture
import AlertAudio

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let canary = CanaryService()
    private let alarm = HealthAlarm()
    private let inspector = InspectorWindowController()
    private let inspectorModel = InspectorModel()
    private let muteWalkthrough = MuteWalkthroughMenu()

    /// One library for both: the names rules are checked against at load are
    /// the names the player can find at the incident.
    private let sounds = SoundLibrary()
    private lazy var ruleStore = RuleStore(sounds: sounds, player: alertPlayer)
    private lazy var alertPlayer = AlertPlayer(library: sounds)
    private lazy var capture = CaptureController(canary: canary, playSound: { [alertPlayer] name, gainDB in
        alertPlayer.outcome(ofPlaying: name, ruleGainDB: gainDB)
    })

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

    /// Capture count when the last self-test ran. Real traffic arriving since
    /// then is positive evidence the capture path works, which is what lets a
    /// failed self-test be attributed rather than left ambiguous.
    private var captureCountAtLastCanary = 0

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
        reloadRules()

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
            captureCountAtLastCanary = capture.captureCount
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
                         canaryFailedWithNoBannerActivity: canaryFailedWithNoBannerActivity,
                         capturesSinceLastCanary: capture.captureCount - captureCountAtLastCanary)
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
                         canaryFailedWithNoBannerActivity: canaryFailedWithNoBannerActivity,
                         capturesSinceLastCanary: capture.captureCount - captureCountAtLastCanary)
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
        syncInspector()

        // Rules that did not load, or an alert that could not sound, leave
        // the app as silent as a blind pipeline does, so they claim the same
        // glyph (§7.1: a broken pipeline is the most important fact on screen,
        // and an alert that cannot sound is a broken pipeline).
        let alarming = health.isAlarming || ruleStore.status.isProblem
            || capture.pipeline.unresolvedAlertFailure != nil
        item.button?.image = NSImage(
            systemSymbolName: alarming ? "bell.slash.fill" : "bell.badge",
            accessibilityDescription: alarming ? "SignalLadder — problem" : "SignalLadder"
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

        let inspect = NSMenuItem(title: "Show Inspector…",
                                 action: #selector(showInspector),
                                 keyEquivalent: "i")
        inspect.target = self
        menu.addItem(inspect)

        addRulesSection(to: menu)

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

    // MARK: - Rules

    /// Rereads the file and previews the result against everything already
    /// captured, so a rule is tested on real traffic the moment it is saved.
    private func reloadRules() {
        ruleStore.reload()
        capture.pipeline.setRules(ruleStore.rules)
        rebuildMenu()
    }

    @objc private func reloadRulesFromMenu() {
        reloadRules()
    }

    @objc private func editRules() {
        do {
            try ruleStore.createExampleIfMissing()
        } catch {
            // An explicit request that failed deserves an explicit answer; a
            // menu item that silently does nothing reads as broken.
            NSApp.activate(ignoringOtherApps: true)
            NSAlert(error: error).runModal()
            return
        }
        // Falls back to revealing the file when nothing is registered to open
        // JSON, rather than failing silently.
        if !NSWorkspace.shared.open(ruleStore.fileURL) {
            NSWorkspace.shared.activateFileViewerSelecting([ruleStore.fileURL])
        }
        reloadRules()
    }

    private func addRulesSection(to menu: NSMenu) {
        menu.addItem(.separator())
        menu.addItem(withTitle: ruleStore.status.summary, action: nil, keyEquivalent: "")
        for line in ruleStore.status.detail {
            let item = NSMenuItem(title: line, action: nil, keyEquivalent: "")
            item.indentationLevel = 1
            menu.addItem(item)
        }

        let pipeline = capture.pipeline
        let anyRulePlaysSound = pipeline.rules.contains(where: \.playsSound)
        let alertLines = AlertMenuText.lines(
            lastMatch: pipeline.lastMatch,
            unresolvedFailure: pipeline.unresolvedAlertFailure,
            anyRulePlaysSound: anyRulePlaysSound,
            // Read on every rebuild, never cached: the user mutes and unmutes
            // at will, and a stale warning either way is a false report.
            outputSilent: anyRulePlaysSound && OutputState.current().isEffectivelySilent,
            time: Self.clock.string(from:))
        for line in alertLines {
            menu.addItem(withTitle: line, action: nil, keyEquivalent: "")
        }
        muteWalkthrough.add(to: menu, apps: MuteWalkthrough.appsToMute(rules: pipeline.rules,
                                                                       alsoSounded: pipeline.appsThatSounded))
        if !pipeline.rules.isEmpty, !pipeline.history.isEmpty {
            menu.addItem(withTitle: "Current rules match \(pipeline.currentRuleMatchCount) of the last \(pipeline.history.count)",
                         action: nil, keyEquivalent: "")
        }

        let edit = NSMenuItem(title: "Edit Rules File…", action: #selector(editRules), keyEquivalent: "e")
        edit.target = self
        menu.addItem(edit)
        let reload = NSMenuItem(title: "Reload Rules", action: #selector(reloadRulesFromMenu), keyEquivalent: "r")
        reload.target = self
        menu.addItem(reload)
    }

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

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
        inspectorModel.setHealth(summary: healthTitle, advice: firstCause?.advice, health: health)
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
