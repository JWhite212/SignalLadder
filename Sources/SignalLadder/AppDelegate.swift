// Sources/SignalLadder/AppDelegate.swift
import AppKit
import ApplicationServices
import UserNotifications
import NotificationCore
import NotificationCapture
import AlertAudio
import AlertPanel
import ShortcutRunner

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let canary = CanaryService()
    private let alarm = HealthAlarm()
    private let inspector = InspectorWindowController()
    private let inspectorModel = InspectorModel()
    /// The one copy of the mute checklist. Whatever reads it is given this
    /// instance, so a tick made in the menu is the tick every reader sees.
    private let muteChecklist = MuteChecklistStore()
    private lazy var muteWalkthrough = MuteWalkthroughMenu(store: muteChecklist)
    /// The one copy of the on-call state, restored from the preferences when it
    /// is made, which is before capture starts: the first schedule of
    /// self-tests, and every interval after it, is read from this.
    private let onCall = OnCallStore()
    private lazy var ruleEditor: RuleEditorWindowController = {
        let model = RuleEditorModel(store: ruleStore)
        // A save takes effect at once, through the same path as Reload Rules.
        model.onApply = { [weak self] in self?.reloadRules() }
        // A test of a Shortcut that started it clears a held failure of that
        // Shortcut, as a real launch of it does.
        model.onShortcutStarted = { [weak self] name in self?.capture.shortcutStartedInTest(named: name) }
        let editor = RuleEditorWindowController(model: model)
        editor.openInTextEditor = { [weak self] in self?.openRulesFileInTextEditor() }
        return editor
    }()

    /// One library for both: the names rules are checked against at load are
    /// the names the player can find at the incident.
    private let sounds = SoundLibrary()
    private lazy var ruleStore = RuleStore(sounds: sounds, player: alertPlayer, shortcuts: shortcuts)
    private lazy var alertPlayer = AlertPlayer(library: sounds)

    /// Tier 1, for every rule. Each alert that reaches the player is taken
    /// as an ordinary rule's, until `beginEscalation` says otherwise.
    private lazy var capture: CaptureController = CaptureController(canary: canary, playSound: { [weak self, alertPlayer] name, gainDB in
        let outcome = alertPlayer.outcome(ofPlaying: name, ruleGainDB: gainDB)
        self?.playerOwnership.alertSetOff(outcome, byEscalation: false)
        return outcome
    }, speak: { [weak self, alertPlayer] text, speech in
        let outcome = alertPlayer.outcome(ofSpeaking: text, speech: speech)
        self?.playerOwnership.alertSetOff(outcome, byEscalation: false)
        return outcome
    }, playAndSpeak: { [weak self, alertPlayer] name, gainDB, text, speech in
        let outcome = alertPlayer.outcome(ofPlaying: name, ruleGainDB: gainDB, thenSpeaking: text, speech: speech)
        self?.playerOwnership.alertSetOff(outcome, byEscalation: false)
        return outcome
    }, beginEscalation: { [weak self] rule, notification, entryID in
        guard let self else { return }
        // Tier 1 has just been set off and recorded on its row. If it reached
        // the player, what is playing is now this escalation's.
        if let tier1 = self.capture.history.entries.first(where: { $0.id == entryID })?.alertOutcome {
            self.playerOwnership.alertSetOff(tier1, byEscalation: true)
        }
        self.escalations.begin(rule: rule, notification: notification, entryID: entryID)
    })

    /// Whether what is playing is an escalation's, for `silenceIfIdle`.
    private var playerOwnership = PlayerOwnership()

    /// Runs tiers 2 to 4. Built on first use, like `capture`; each reaches
    /// the other only when called, so neither is needed to build the other.
    private lazy var escalations: EscalationCoordinator = EscalationCoordinator(
        scheduler: RunLoopEscalationScheduler(),
        playSound: { [weak self, alertPlayer] name, gainDB in
            let outcome = alertPlayer.outcome(ofPlaying: name, ruleGainDB: gainDB)
            self?.playerOwnership.alertSetOff(outcome, byEscalation: true)
            return outcome
        },
        speak: { [weak self, alertPlayer] text, speech in
            let outcome = alertPlayer.outcome(ofSpeaking: text, speech: speech)
            self?.playerOwnership.alertSetOff(outcome, byEscalation: true)
            return outcome
        },
        playAndSpeak: { [weak self, alertPlayer] name, gainDB, text, speech in
            let outcome = alertPlayer.outcome(ofPlaying: name, ruleGainDB: gainDB, thenSpeaking: text, speech: speech)
            self?.playerOwnership.alertSetOff(outcome, byEscalation: true)
            return outcome
        },
        runShortcut: { [weak self] name, notification, report in
            self?.shortcuts.run(name: name, fields: ShortcutRunner.Fields(notification)) { outcome in
                switch outcome {
                case .launched: report(.shortcutLaunched(name: name))
                case .failed(let reason): report(.shortcutFailed(name: name, reason: reason))
                }
            }
        },
        updatePanel: { [weak self] rows in self?.showPanel(rows) },
        recordSummary: { [weak self] entryID, summary in self?.capture.recordEscalation(entryID: entryID, summary) },
        retired: { [weak self] entryID in self?.capture.escalationRetired(entryID: entryID) },
        beginPowerAssertion: { [weak self] in self?.power.begin() },
        endPowerAssertion: { [weak self] in self?.power.end() },
        silenceIfIdle: { [weak self] in
            guard let self, self.playerOwnership.escalationOwnsIt else { return }
            self.alertPlayer.silence()
        })

    /// Created at launch, when anything a crash or quit left is swept (§5.16).
    private let shortcuts = ShortcutRunner()
    private let power = PowerAssertion()
    private lazy var panel = AlertPanelController(title: EscalationPanelText.title,
                                                  acknowledgeTitle: EscalationPanelText.acknowledge,
                                                  overflowLine: EscalationPanelText.overflow)
    private lazy var hotKey = HotKeyController { [weak self] in self?.escalations.acknowledgeAll() }
    private var wakeObserver: NSObjectProtocol?

    /// Swaps the status item's glyph while anything is escalating, so a live
    /// ladder is visible at a glance. Runs only then.
    private var glyphTimer: Timer?
    private var glyphPulse = false

    /// Says whether the status menu's items may be rebuilt now. Capture and the
    /// timers run while the menu is open, and a rebuild would move its rows
    /// under the pointer (`MenuRebuildGate`).
    private var menuGate = MenuRebuildGate()

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

    /// When a self-test last succeeded. Health says how old this is, and stops
    /// calling it "verified" once a self-test that should have run has not.
    private var lastCanarySucceededAt: Date?

    private var secondsSinceLastSuccessfulCanary: TimeInterval? {
        lastCanarySucceededAt.map { Date().timeIntervalSince($0) }
    }

    /// A second self-test this long after a launch, a re-attach, or capture
    /// starting. Both known capture outages began soon after a relaunch. On
    /// 2026-09-25 a self-test at launch passed, capture went blind about 80
    /// seconds later, and nothing would have looked again for 30 minutes.
    /// This looks again after two, at the cost of one banner on an event that
    /// is rare.
    private static let followUpDelay: TimeInterval = 120
    private var followUpTimer: Timer?

    private var retryTimer: Timer?
    private var retryDelay: TimeInterval = SelfTestPlan.firstRetryDelay

    /// What held at the last health check, so a self-test can run the moment
    /// something that blocked one clears (`SelfTestPlan`).
    private var lastSelfTestConditions: SelfTestPlan.Conditions?

    /// While a self-test is blocked, a check every minute for the block
    /// clearing. Kept apart from `retryTimer` so that time spent blocked does
    /// not stretch the back-off a failed self-test is retried on: the advice
    /// for one promises a retry within the minute. It only reads settings, so
    /// a permanent block costs nothing the user can see.
    private var blockedRecheckTimer: Timer?
    private static let blockedRecheckInterval: TimeInterval = 60

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        NSApp.mainMenu = MainMenu.make()
        // Before any escalation can make a new one.
        shortcuts.sweep()
        setUpStatusItem()

        // Capture and the self-test schedule are established BEFORE any await.
        // requestAuthorization does not return until the user answers the
        // system dialog, so anything sequenced after it is hostage to whether
        // they ever do — and an app that captures nothing while reporting
        // "Checking…" would never complain about its own paralysis.
        _ = OnboardingCoordinator.requestAccessibilityIfNeeded()
        hotKey.register()
        // The system waking, not the display: the display sleeps on its own
        // while the system never does, on this very Mac (ruling 14).
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.escalations.checkForSleep() }
        }
        startCaptureIfTrusted()
        // At the cadence of the state the store restored.
        scheduleCanary()
        reloadRules()

        Task { @MainActor in
            _ = await OnboardingCoordinator.requestNotificationAuthorization()
            startCaptureIfTrusted()   // trust may have been granted meanwhile
            await refreshHealthAndFollowUp()
        }
    }

    /// Quitting never asks the editor's window whether it may close, so an
    /// unsaved draft is asked about here — or it would vanish without a word.
    /// So is an escalation still listed: quitting ends it, and a Shortcut not
    /// yet run never runs. Ending alerting should be chosen on purpose, which
    /// is also why the app's main menu has no Quit item (`MainMenu`).
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let listed = escalations.listedSummaries.map(\.1.status)
        if !listed.isEmpty {
            let warning = AlertMenuText.quitWarning(escalating: listed.filter(\.isEscalating).count,
                                                    missed: listed.filter(\.isUnseenMiss).count)
            let ask = NSAlert()
            ask.messageText = warning.message
            ask.informativeText = warning.detail
            ask.addButton(withTitle: "Cancel")
            ask.addButton(withTitle: "Quit")
            NSApp.activate(ignoringOtherApps: true)
            guard ask.runModal() == .alertSecondButtonReturn else { return .terminateCancel }
        }
        guard ruleEditor.model.hasUnsavedChanges else { return .terminateNow }
        ruleEditor.confirmDiscardingDraft { proceed in
            NSApp.reply(toApplicationShouldTerminate: proceed)
        }
        return .terminateLater
    }

    /// Removes the per-run temp folder at quit as well as at launch, so a
    /// Shortcut's input never outlives the app (§5.16).
    func applicationWillTerminate(_ notification: Notification) {
        shortcuts.sweep()
    }

    // MARK: - Escalation

    /// The panel lists what the coordinator gives it, each line written by
    /// `EscalationPanelText`, so the panel never holds what arrived (ruling
    /// 17); none hides it.
    private func showPanel(_ rows: [(EscalationID, EscalationSummary)]) {
        guard !rows.isEmpty else { return panel.hide() }
        panel.show(rows: rows.map { ($0.0, EscalationPanelText.line(for: $0.1, time: Self.clock.string(from:))) },
                   onAcknowledge: { [weak self] id in self?.escalations.acknowledge(id) })
    }

    /// Acts on the escalations the menu listed when it was built, and on no
    /// other: capture runs while the menu is open, and one that began in the
    /// seconds it was held is one the user was never shown (`acknowledge(ids:)`).
    /// An item that does not say what it listed ends nothing.
    @objc private func acknowledgeListedFromMenu(_ sender: NSMenuItem) {
        guard let listed = sender.representedObject as? ListedEscalations else { return }
        escalations.acknowledge(ids: listed.ids)
    }

    /// Starts or stops the glyph's swap to follow whether anything is live.
    private func updateGlyphPulse() {
        if escalations.hasLiveEscalations {
            guard glyphTimer == nil else { return }
            let timer = Timer(timeInterval: 0.8, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.glyphPulse.toggle()
                    self.rebuildGlyph()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            glyphTimer = timer
        } else {
            glyphTimer?.invalidate()
            glyphTimer = nil
            glyphPulse = false
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
            Task { @MainActor in await self?.refreshHealthAndFollowUp() }
        }
        capture.start()
        return true
    }

    // MARK: - Health

    private func scheduleCanary() {
        canaryTimer?.invalidate()
        // The one deliberate exception to "never poll". Absence of traffic is
        // not evidence of health, so health has to be asked for.
        let timer = Timer(timeInterval: HealthEvaluator.selfTestInterval(onCall: onCall.state.isOn),
                          repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshHealth(runCanary: true) }
        }
        // Left to the system's coalescing, a fire that came late against the
        // freshness grace could turn "verified" into "Unverified" with nothing
        // wrong. The escalation scheduler's timers are armed the same way.
        timer.tolerance = 0
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
        retryDelay = SelfTestPlan.nextRetryDelay(after: retryDelay, onCall: onCall.state.isOn)
    }

    /// Replaces any recheck already pending, so two health checks in a row
    /// (as at launch) arm one recheck, not two.
    private func scheduleBlockedRecheck() {
        blockedRecheckTimer?.invalidate()
        let timer = Timer(timeInterval: Self.blockedRecheckInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in await self?.refreshHealth(runCanary: true) }
        }
        RunLoop.main.add(timer, forMode: .common)
        blockedRecheckTimer = timer
    }

    private func cancelCanaryRetry() {
        retryTimer?.invalidate()
        retryTimer = nil
        retryDelay = SelfTestPlan.firstRetryDelay
    }

    /// A self-test now and, if it passes, another shortly after: the moments
    /// right after a launch, a re-attach, or capture starting are when capture
    /// has been seen to fail. A failure needs no follow-up here; the retry
    /// already looks again within a minute.
    private func refreshHealthAndFollowUp() async {
        await refreshHealth(runCanary: true)
        guard consecutiveCanaryFailures == 0 else { return }
        followUpTimer?.invalidate()
        let timer = Timer(timeInterval: Self.followUpDelay, repeats: false) { [weak self] _ in
            Task { @MainActor in await self?.refreshHealth(runCanary: true) }
        }
        RunLoop.main.add(timer, forMode: .common)
        followUpTimer = timer
    }

    /// Everything health is judged from, read now. The one place it is put
    /// together, so that the interval evidence ages by is the one the timer runs
    /// at, in whichever state the app is in. Delivery is the last one probed.
    private func healthInputs() -> HealthInputs {
        HealthInputs(accessibilityTrusted: AXIsProcessTrusted(),
                     observerAttached: capture.observerAttached,
                     notificationsAuthorized: delivery?.authorized ?? false,
                     notificationsWouldDisplay: delivery?.wouldDisplay ?? false,
                     consecutiveCanaryFailures: consecutiveCanaryFailures,
                     canaryFailedWithNoBannerActivity: canaryFailedWithNoBannerActivity,
                     capturesSinceLastCanary: capture.captureCount - captureCountAtLastCanary,
                     secondsSinceLastSuccessfulCanary: secondsSinceLastSuccessfulCanary,
                     selfTestInterval: HealthEvaluator.selfTestInterval(onCall: onCall.state.isOn))
    }

    /// Switches on-call mode on or off by carrying out, in order, what
    /// `OnCallSwitch` says. Nothing calls it yet: the menu item that does comes
    /// with the commit that gives the user the switch. Running escalations are
    /// not touched, since no effect names one.
    private func switchOnCall(turningOn: Bool) async {
        for effect in OnCallSwitch.effects(turningOn: turningOn) {
            switch effect {
            case .save: onCall.set(turningOn ? .on(since: Date()) : .off)
            case .rearmSelfTestTimer: scheduleCanary()
            case .cancelPendingRetry: cancelCanaryRetry()
            case .runSelfTestNow: await refreshHealthAndFollowUp()
            }
        }
    }

    private func refreshHealth(runCanary: Bool) async {
        delivery = await DeliveryStatusProbe.current()

        let conditions = SelfTestPlan.Conditions(accessibilityTrusted: AXIsProcessTrusted(),
                                                 ownAlertsDisplay: delivery?.wouldDisplay == true,
                                                 observerAttached: capture.observerAttached)
        let plan = SelfTestPlan.decide(requested: runCanary, previous: lastSelfTestConditions, current: conditions)
        let followsBlock = lastSelfTestConditions.map { !$0.allowsSelfTest } ?? false
        lastSelfTestConditions = conditions
        if plan == .retryLater {
            scheduleBlockedRecheck()
        } else {
            blockedRecheckTimer?.invalidate()
            blockedRecheckTimer = nil
        }
        // A self-test after a block starts the failure back-off afresh. Only
        // then: resetting on every run would retry a long Focus every minute.
        if plan == .run, followsBlock { retryDelay = SelfTestPlan.firstRetryDelay }

        // Only a canary that actually ran carries information. A nil result
        // means none ran — discarding a previous verified state for that
        // would regress the display to "Checking…" for no reason.
        if plan == .run {
            // Snapshotted across the whole round trip. If Notification Centre
            // drew nothing in that window, the alert was suppressed and the
            // failure says nothing about capture.
            let eventsBefore = capture.observerEventCount
            let countBefore = captureCountAtLastCanary
            captureCountAtLastCanary = capture.captureCount
            let result = await canary.run()
            if result == nil {
                // None ran: one was already under way, or posting failed. The
                // one under way set its own count; this call must not move it.
                // A retry keeps a clearing from being spent on nothing — and
                // if one was under way, its own result replaces the retry.
                captureCountAtLastCanary = countBefore
                scheduleCanaryRetry()
            }
            if let succeeded = result {
                consecutiveCanaryFailures = succeeded ? 0 : (consecutiveCanaryFailures ?? 0) + 1
                if succeeded { lastCanarySucceededAt = Date() }
                canaryFailedWithNoBannerActivity =
                    !succeeded && capture.observerEventCount == eventsBefore
                succeeded ? cancelCanaryRetry() : scheduleCanaryRetry()
            }
        }

        health = HealthEvaluator.evaluate(healthInputs())

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
        guard menu === statusItem?.menu else { return }
        // The menu is about to be shown, so the rebuild made here goes ahead,
        // and it is the one a held menu was owed. From here until it closes,
        // every path out of this function leaves the gate open.
        menuGate.menuClosed()
        defer { menuGate.menuOpened() }

        let justStarted = startCaptureIfTrusted()

        // Nothing has been probed yet, so there is nothing honest to report.
        guard delivery != nil else {
            health = .unknown
            rebuildMenu()
            return
        }

        // Re-evaluate synchronously from what can be read without awaiting,
        // reusing the last known delivery status. rebuildMenu renders from
        // `health`, so without this the menu would keep reporting a problem
        // that has already been fixed — a false alarm lasting until the next
        // scheduled canary.
        health = HealthEvaluator.evaluate(healthInputs())
        rebuildMenu()

        // Capture has only just begun, so nothing has been verified yet.
        // Prove it for real rather than leaving the user on an assumption.
        if justStarted {
            Task { @MainActor in await self.refreshHealthAndFollowUp() }
        }

        // The synchronous pass above reuses last-known delivery, which goes
        // stale in both directions. Re-probe without spending a self-test so
        // the next open is accurate.
        Task { @MainActor in await self.refreshHealth(runCanary: false) }
    }

    /// A held menu is rebuilt once, when it closes, however many changes came
    /// while it was open. Not here: this is reported to arrive before the action
    /// of the item that was chosen, and emptying the menu now would take that
    /// item away before its action ran. So it is the next turn of the main queue
    /// that rebuilds, and it asks the gate again, so that a menu opened again in
    /// between is still held.
    func menuDidClose(_ menu: NSMenu) {
        guard menu === statusItem?.menu else { return }
        guard !menuGate.menuClosed().isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.rebuildMenu() }
        }
    }

    /// Rules that did not load, a Shortcut that cannot be found, or an alert or
    /// Shortcut that could not run, leave the app as silent as a blind
    /// pipeline does, so they claim the same glyph (§7.1: a broken pipeline is
    /// the most important fact on screen). A live escalation comes next, and
    /// is never folded into it: a working ladder must not look like a broken
    /// pipeline.
    private func rebuildGlyph() {
        guard let button = statusItem?.button else { return }
        let alarming = StatusProblem.isProblem(healthAlarming: health.isAlarming,
                                               ruleStatusProblem: ruleStore.status.isProblem,
                                               warningCount: ruleStore.warnings.count,
                                               unresolvedAlertFailure: capture.pipeline.unresolvedAlertFailure != nil,
                                               unresolvedShortcutFailure: capture.pipeline.unresolvedShortcutFailure != nil)
        let (symbol, description): (String, String)
        if alarming {
            (symbol, description) = ("bell.slash.fill", "SignalLadder — problem")
        } else if escalations.hasLiveEscalations {
            (symbol, description) = (glyphPulse ? "bell.and.waves.left.and.right.fill" : "bell.and.waves.left.and.right",
                                     "SignalLadder — alert escalating")
        } else {
            (symbol, description) = ("bell.badge", "SignalLadder")
        }
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)
    }

    /// Every change ends here. The gate says what of it is done now: the sync
    /// of the Inspector, the pulse and the icon on every change, and the menu's
    /// items only while the menu is closed.
    private func rebuildMenu() {
        guard statusItem?.menu != nil else { return }
        for step in menuGate.request() {
            switch step {
            case .syncInspector: syncInspector()
            case .updatePulse: updateGlyphPulse()
            case .refreshGlyph: rebuildGlyph()
            case .rebuildItems: rebuildMenuItems()
            }
        }
    }

    private func rebuildMenuItems() {
        guard let menu = statusItem?.menu else { return }
        menu.removeAllItems()
        addEscalationSection(to: menu)
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

    /// At the top, while anything is listed or a Shortcut has failed: the
    /// one thing the user may need to do now.
    private func addEscalationSection(to menu: NSMenu) {
        let rows = escalations.listedSummaries
        let listed = rows.map(\.1)
        let lines = AlertMenuText.escalationLines(listed: listed,
                                                  shortcutFailure: capture.pipeline.unresolvedShortcutFailure,
                                                  time: Self.clock.string(from:))
        guard !listed.isEmpty || !lines.isEmpty else { return }
        if !listed.isEmpty {
            let acknowledge = NSMenuItem(title: AlertMenuText.acknowledgeTitle(listed: listed.count),
                                         action: #selector(acknowledgeListedFromMenu(_:)), keyEquivalent: "")
            acknowledge.target = self
            acknowledge.representedObject = ListedEscalations(ids: Set(rows.map(\.0)))
            menu.addItem(acknowledge)
        }
        for line in lines { menu.addItem(withTitle: line, action: nil, keyEquivalent: "") }
        menu.addItem(.separator())
    }

    private var healthTitle: String {
        HealthTitle.text(for: health, secondsSinceLastSuccessfulCanary: secondsSinceLastSuccessfulCanary)
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
        // An open editor holding no draft follows the file, so it never shows
        // rules that are no longer the ones in effect. A draft is left alone:
        // its save will notice the change and ask.
        if ruleEditor.isOpen, !ruleEditor.model.hasUnsavedChanges {
            ruleEditor.model.reloadFromDisk()
        }
        rebuildMenu()
    }

    @objc private func showRuleEditor() {
        syncInspector()
        ruleEditor.show()
    }

    @objc private func reloadRulesFromMenu() {
        reloadRules()
    }

    @objc private func openRulesFileInTextEditor() {
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
        // A Shortcut that was not found leaves its rule in effect, so it is
        // a warning here and not part of the rules' status above.
        if let summary = RuleWarnings.summaryLine(count: ruleStore.warnings.count) {
            menu.addItem(withTitle: summary, action: nil, keyEquivalent: "")
            for warning in ruleStore.warnings {
                let item = NSMenuItem(title: warning.detail, action: nil, keyEquivalent: "")
                item.indentationLevel = 1
                menu.addItem(item)
            }
        }

        let pipeline = capture.pipeline
        let anyRulePlaysSound = pipeline.rules.contains(where: \.alertsAloud)
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
                                                                       alsoSounded: pipeline.appsThatAlerted))
        if !pipeline.rules.isEmpty, !pipeline.history.isEmpty {
            menu.addItem(withTitle: "Current rules match \(pipeline.currentRuleMatchCount) of the last \(pipeline.history.count)",
                         action: nil, keyEquivalent: "")
        }

        let edit = NSMenuItem(title: "Edit Rules…", action: #selector(showRuleEditor), keyEquivalent: "e")
        edit.target = self
        menu.addItem(edit)
        let text = NSMenuItem(title: "Open Rules File in Text Editor…", action: #selector(openRulesFileInTextEditor),
                              keyEquivalent: "")
        text.target = self
        menu.addItem(text)
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
        inspectorModel.onMakeRule = { [weak self] entry in
            guard let self else { return }
            self.syncInspector()
            self.ruleEditor.show(makingRuleFrom: entry)
        }
        inspector.show(model: inspectorModel)
    }

    /// The model is refreshed from the buffer rather than subscribing to it,
    /// because the buffer is a plain value type by design and the app has
    /// exactly two moments when the Inspector can be stale: a new capture, and
    /// a health change. Both call here. The rule editor's dry-run reads the
    /// same buffer, so it is refreshed with it — a notification arriving while
    /// a rule is being written joins the dry-run at once.
    private func syncInspector() {
        inspectorModel.refresh(from: capture.history)
        inspectorModel.setHealth(summary: healthTitle, advice: firstCause?.advice, health: health)
        ruleEditor.model.refreshCaptures(from: capture.history)
    }
}

/// The escalations the status menu listed when it was built, carried by its
/// Acknowledge item so that a click acts on those and not on whatever is
/// listed when it lands.
private final class ListedEscalations {
    let ids: Set<EscalationID>

    init(ids: Set<EscalationID>) {
        self.ids = ids
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
