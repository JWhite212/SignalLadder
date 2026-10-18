// Sources/SignalLadder/SetupCoordinator.swift
import AppKit
import NotificationCore
import NotificationCapture

/// Gathers what the first run reads and carries out what its buttons say (M5 plan, Task 8,
/// Rulings 10, 16, 20 and 22).
///
/// **It decides almost nothing.** The app target has no tests, so every decision it carries
/// out is the core's and tested, but for two guards that refuse a press with no app picked or
/// no banner from it, in `SetupText.pickAnAppFirst`'s and `SetupText.noBannerFromThatApp`'s
/// words: each step's state and what it rests on (`SetupPlan`), every
/// word and which buttons a step has (`SetupText`), what is recorded and how a stored
/// value is read (`SetupProgress`), what Continue comes to on a step and what the last
/// step's buttons ask and save (`SetupPlan.continuing`, `SetupPlan.pressing`), which entry
/// an app the user picked leads back to (`SetupCapture`), and what a login item's state
/// is (`LaunchAtLogin`). Where this would have had to choose, the choice was moved to
/// one of those, with a test.
///
/// **Facts.** `facts()` reads each fact from where the app already holds it and hands
/// the plan all of them, none left out, since `SetupFacts` has no default and a fact
/// forgotten does not compile. What only the app delegate holds (whether Accessibility is
/// granted, what the notification probe last answered, what health reads and when a
/// self-test last succeeded) comes through `Sources`; the rest is read from the one copy
/// the app keeps: the rules in effect and the captures from `capture`, the rules' status
/// and the editor's reason for a file it must not write from `ruleStore`, the mute
/// checklist from the shared `MuteChecklistStore`, the login item from Settings' model, and
/// what has been recorded from the one `SetupProgressStore`. The notification fact is nil
/// until the first probe has answered, as `Sources.delivery` is. The rules have no such
/// "not read yet", so the facts must be gathered after the rules are loaded
/// (`SetupFacts.ruleStatus`).
///
/// **Words.** `words(for:facts:)` and `summary(_:)` hand the core's `SetupText` the facts
/// and the one formatter the menu's other lines use for a moment (`Sources.time`), and read
/// no clock of their own. Each is made from the facts it is given, so that one pass of the
/// window shows one reading.
///
/// **Buttons.** `press(_:on:app:boxTicked:)` carries out one `SetupText.ButtonAction`
/// exactly as the core says it, with no default arm, so an action added to the core has to
/// be placed here:
/// - A permission is asked for only when the user presses that step's button, and the
///   two panes of System Settings are opened by the helpers that already open them
///   (`OnboardingCoordinator`). Nothing prompts before.
/// - A mute is the user's word, recorded in the shared `MuteChecklistStore`, so the menu
///   and the guide cannot disagree.
/// - The first rule is made by calling the rule editor directly, with the newest entry
///   the app the user picked was read from. The Inspector's hook for it is assigned only
///   inside `showInspector()`, so the guide does not wait for that.
/// - The last step's Continue registers through Settings' model, by the one path its
///   switch uses, and saves the choice the core says to save, in the one place Settings
///   writes it (`SettingsModel.perform(guidePress:)`). This holds no key and calls nothing
///   of `ServiceManagement`.
/// - What stands where a modal alert stood in the menu (the lookup of an app's page, the
///   rules file that could not be got ready) is a sentence handed back to show beside the
///   button, and never an alert (Ruling 22). So is what stands where a press about an app
///   could do nothing, because none was picked or the banner it would be made from has
///   gone: the button is never one that does nothing and says nothing.
/// - Which presses are followed by a read of what the app reads from outside itself is the
///   core's (`SetupText.ButtonAction.readsAgain`), and is carried out once, after the press,
///   with whether that read first starts capture
///   (`SetupText.ButtonAction.startsCaptureIfTrusted`) and whether it asks for one
///   self-test (`SetupText.ButtonAction.runsSelfTest(on:)`), which are the core's too.
///
/// **Dismissal.** "Not now" and closing the window are one act (O13), and each calls
/// `SetupProgress.recordDismissed()` through `recordDismissal()`. The core records nothing
/// for a guide that is finished, so neither asks whether it is. The close that a quit makes
/// is not one of them, and the core says so (`SetupPlan.closeIsDismissal(appIsQuitting:)`).
///
/// **No timer, no clock, no alert.** The guide is refreshed when the app is activated,
/// when the menu opens, on Check again and from `syncInspector`, which are the caller's to
/// ask, and `facts()` is the same read each time (Ruling 20). This starts no timer and
/// reads no clock. It gives `HealthAlarmPlan` no input and holds nothing back: a beep that
/// sounds over the guide is the lesser fault (Ruling 10). `SetupWiringTests` holds each of
/// these to the source.
///
/// This file may hold no word of its own (the strict list in `ViewLiteralsTests`).
@MainActor
final class SetupCoordinator {
    /// What only the app delegate holds, or reads from the system, which the guide's facts
    /// are made from and which it is handed as it reads them. None has a default, so a
    /// place that makes one and forgets a source does not compile.
    struct Sources {
        /// Whether Accessibility is granted (`AXIsProcessTrusted()`).
        var accessibilityTrusted: () -> Bool
        /// What the notification probe last answered, **nil until the first probe has
        /// returned** (`AppDelegate`'s `delivery` starts as nil). The guide's notification
        /// fact is nil then, and neither the guide nor the nudge says anything on its
        /// account (Ruling 16).
        var delivery: () -> DeliveryStatus?
        /// What health reads now.
        var health: () -> CaptureHealth
        /// When a self-test last succeeded (`AppDelegate`'s `lastCanarySucceededAt`), nil
        /// when none has. The core reads it only beside a health that is verified now
        /// (`SetupPlan.verifiedAt(_:)`).
        var lastVerifiedAt: () -> Date?
        /// Reads again what the app reads from outside itself, for Check again, and after
        /// the request for notifications, which changes what the probe answers. It is
        /// told whether to start capture first, if it can
        /// (`SetupText.ButtonAction.startsCaptureIfTrusted`), and whether to ask for one
        /// self-test as well (`SetupText.ButtonAction.runsSelfTest(on:)`: Check again on
        /// "Prove it can read" and no other press), which the core says, and the
        /// coordinator hands both over as they are and decides nothing about either. What
        /// the rest of it reads is the app delegate's to say: whatever it reads, the facts
        /// are gathered afresh from the app's own copies when it returns.
        var readAgain: (_ startCapture: Bool, _ runSelfTest: Bool) async -> Void
        /// Gets the rules file ready and opens it in a text editor, and hands back the
        /// failure when it could not, which the guide shows beside its button as
        /// `SetupText.rulesFileNotOpened(_:)`. The menu's item shows its own failure as it
        /// did. nil when the file was opened.
        var openRulesFile: () -> Error?
        /// How a moment is shown, as the menu's other lines show one ("14:02"). The app
        /// delegate's own formatter, so that the guide and the menu cannot differ.
        var time: (Date) -> String
    }

    private let sources: Sources
    private let progress: SetupProgressStore
    private let muteChecklist: MuteChecklistStore
    private let settingsModel: SettingsModel
    private let ruleStore: RuleStore
    private let capture: CaptureController
    private let ruleEditor: RuleEditorWindowController

    /// - Parameters:
    ///   - progress: the one copy of what the first run has recorded, and the only code
    ///     that saves it.
    ///   - muteChecklist: the one shared checklist, which the menu and the on-call check
    ///     read too.
    ///   - settingsModel: Settings' model, which reads the login item and is the one path
    ///     that registers it.
    ///   - ruleStore: the rules as the loader read them, and the file's reason, if it has
    ///     one, for the editor to leave it alone.
    ///   - capture: the rules in effect and the banners captured so far.
    ///   - ruleEditor: the rule editor, which the first rule is made in.
    init(sources: Sources, progress: SetupProgressStore, muteChecklist: MuteChecklistStore,
         settingsModel: SettingsModel, ruleStore: RuleStore, capture: CaptureController,
         ruleEditor: RuleEditorWindowController) {
        self.sources = sources
        self.progress = progress
        self.muteChecklist = muteChecklist
        self.settingsModel = settingsModel
        self.ruleStore = ruleStore
        self.capture = capture
        self.ruleEditor = ruleEditor
    }

    // MARK: - What is read

    /// Every fact the plan reads, as the app holds it now. Gathered afresh for each call,
    /// and cheap: nothing here waits, probes, reads the disk or reads the login item's
    /// status, which Settings' model reads on its own schedule and this takes as it last
    /// read it.
    ///
    /// **The login item is the one fact that can be older than the menu's own line.** The
    /// status has no change notice, and Settings' model reads it when its window appears,
    /// on each activation of the app and after each request of its own (Ruling 15), while
    /// the menu reads it for itself as it opens. So a change made in System Settings shows
    /// in the menu at once and in the guide, on step 7 and in the summary's line on on-call
    /// mode, after the next activation. The guide does not read the status itself: this is
    /// asked for by every capture and health change while the guide is open (M5 plan, Task 8,
    /// "No timer, no modal"), and a read of the status is a synchronous call on the main
    /// thread (`LoginItem`: 2 to 21 milliseconds on macOS 26.7.1, not measured on 14 or 15),
    /// which a burst of banners should not each wait for. That the fact can lag the menu's
    /// line until the next activation is a decision beyond the plan, for the owner to
    /// confirm.
    func facts() -> SetupFacts {
        let rules = capture.pipeline.rules
        let entries = capture.history.entries
        return SetupFacts(
            accessibilityTrusted: sources.accessibilityTrusted(),
            notifications: sources.delivery().map {
                SetupFacts.Notifications(permission: $0.permission, wouldDisplay: $0.wouldDisplay)
            },
            health: sources.health(),
            lastVerifiedAt: sources.lastVerifiedAt(),
            ruleStatus: ruleStore.status,
            ruleReach: RuleReach(rules: rules),
            rulesFileReadOnly: ruleStore.readOnlyReason,
            anythingCaptured: SetupCapture.anythingCaptured(in: entries),
            capturedAppNames: SetupCapture.appNames(in: entries),
            appsToMute: MuteWalkthrough.appsToMute(rules: rules, alsoSounded: capture.pipeline.appsThatAlerted),
            muteChecklist: muteChecklist.checklist,
            loginItem: settingsModel.state,
            progress: progress.progress)
    }

    /// Everything a step shows, made from `facts`, with the menu's formatter for a moment.
    func words(for step: SetupStep, facts: SetupFacts) -> SetupText.StepWords {
        SetupText.words(for: step, facts: facts, time: sources.time)
    }

    /// The summary the guide ends on, made from `facts`.
    func summary(_ facts: SetupFacts) -> SetupText.Summary {
        SetupText.summary(facts, time: sources.time)
    }

    // MARK: - The guide opens and closes

    /// The guide is about to be shown. **The start is recorded before anything else**, and
    /// the facts the window is handed are gathered after it, so that what it shows already
    /// reads as begun. That is what keeps the launch decisions true: a guide that was shown
    /// and left, without this, would be a fresh install's again (`SetupPlan.opensAtLaunch`).
    func willShowGuide() -> SetupFacts {
        progress.record { $0.recordStarted() }
        return facts()
    }

    /// The guide's window closed, by its close box or by any way it can close. This is
    /// the same act as "Not now" (O13) and comes to the same record, except for the close a
    /// quit makes, which is not the user leaving the guide: the core says which is which
    /// (`SetupPlan.closeIsDismissal(appIsQuitting:)`).
    func guideDidClose(appIsQuitting: Bool) {
        if SetupPlan.closeIsDismissal(appIsQuitting: appIsQuitting) { recordDismissal() }
    }

    /// The one place a dismissal is recorded. It is `SetupProgress.recordDismissed()`, which
    /// records nothing for a guide that is finished, so "Not now", the close box and the
    /// close that follows Finish all call it and none asks whether the guide is finished.
    private func recordDismissal() {
        progress.record { $0.recordDismissed() }
    }

    // MARK: - What a button does

    /// Carries out one button of the guide, exactly as the core says, and hands back the
    /// sentence to show beside the button if the press came to one, and nil otherwise: the
    /// lookup of an app's page that did not find it, the rules file that was not opened,
    /// what the login item's request came to when it failed or changed nothing, and a
    /// press about an app that could do nothing, because none was picked or the banner it
    /// would be made from has gone (`SetupText.pickAnAppFirst`,
    /// `SetupText.noBannerFromThatApp`). A press that did what it says hands back nil. When
    /// the core says the press is followed by a read of what the app reads from outside
    /// itself (`SetupText.ButtonAction.readsAgain`), that read is made here, after the press
    /// and before this returns, and the window gathers the facts again afterwards. The read
    /// is told whether to start capture first and whether to ask for one self-test as well,
    /// as the core says (`SetupText.ButtonAction.startsCaptureIfTrusted` and
    /// `runsSelfTest(on:)`).
    ///
    /// Neither `app` nor `boxTicked` has a default, so a window that forgets to hand over
    /// what the user picked or ticked does not compile, and does not get a button that
    /// silently does the wrong thing.
    ///
    /// - Parameters:
    ///   - step: the step the button is on. Continue reads it (`SetupPlan.continuing`) and
    ///     so does the core's answer to whether the read that follows asks for a self-test.
    ///   - app: the app the user picked in the step's list, nil when none is picked. Read by
    ///     the three presses that are about an app (make a rule, confirm muted, open its
    ///     notification settings), and by no other.
    ///   - boxTicked: whether the last step's box is ticked. Read by Continue and Skip on
    ///     that step, and by no other press.
    @discardableResult
    func press(_ action: SetupText.ButtonAction, on step: SetupStep?, app: String?,
               boxTicked: Bool) async -> String? {
        let sentence = await perform(action, on: step, app: app, boxTicked: boxTicked)
        if action.readsAgain { await sources.readAgain(action.startsCaptureIfTrusted, action.runsSelfTest(on: step)) }
        return sentence
    }

    /// The press itself, one arm for each action of the core and no default.
    private func perform(_ action: SetupText.ButtonAction, on step: SetupStep?, app: String?,
                         boxTicked: Bool) async -> String? {
        switch action {
        case .continueOn:
            switch SetupPlan.continuing(from: step, loginItem: settingsModel.state, boxTicked: boxTicked) {
            case .introductionSeen:
                progress.record { $0.recordIntroductionSeen() }
                return nil
            case .keepItRunning(let result):
                return carryOut(result)
            case .movesOn:
                return nil
            }
        case .skip:
            return carryOut(SetupPlan.pressing(.skipButton, state: settingsModel.state, boxTicked: boxTicked))
        case .notNow:
            recordDismissal()
            return nil
        case .checkAgain:
            // The read is all it is, and the core says so (`readsAgain`).
            return nil
        case .continueWithoutVerifying:
            progress.record { $0.recordSkipped(.proveItCanRead) }
            return nil
        case .allowAccessibility:
            _ = OnboardingCoordinator.requestAccessibilityIfNeeded()
            return nil
        case .openAccessibilitySettings:
            OnboardingCoordinator.openAccessibilitySettings()
            return nil
        case .allowNotifications:
            _ = await OnboardingCoordinator.requestNotificationAuthorization()
            return nil
        case .openNotificationSettings:
            OnboardingCoordinator.openNotificationSettings()
            return nil
        case .openKeyboardSettings:
            OnboardingCoordinator.openKeyboardSettings()
            return nil
        case .editRules:
            ruleEditor.show()
            return nil
        case .makeRule:
            return makeRule(fromApp: app)
        case .openRulesFile:
            return sources.openRulesFile().map(SetupText.rulesFileNotOpened)
        case .confirmMuted:
            guard let app else { return SetupText.pickAnAppFirst }
            muteChecklist.setConfirmed(app, true)
            return nil
        case .openAppNotificationSettings:
            guard let app else { return SetupText.pickAnAppFirst }
            return openNotificationSettings(ofApp: app)
        case .openFocusSettings:
            NSWorkspace.shared.open(BundleResolver.focusSettingsURL)
            return nil
        case .confirmFocus:
            progress.record { $0.recordFocusAttested() }
            return nil
        case .openLoginItems:
            settingsModel.perform(.openLoginItems)
            return nil
        case .finish:
            progress.record { $0.recordFinished() }
            return nil
        }
    }

    /// The last step's Continue or Skip, as `SetupPlan.pressing` answered it: the skip is
    /// recorded when it says so, and the request and the choice are Settings' model's to
    /// carry out, by its own path. What a request came to is handed back as the model says
    /// it: nil when it succeeded, and when no request was made.
    private func carryOut(_ result: SetupPlan.KeepItRunningResult) -> String? {
        if result.recordsSkip { progress.record { $0.recordSkipped(.keepItRunning) } }
        return settingsModel.perform(guidePress: result)
    }

    /// Opens the rule editor on the newest banner the app the user picked was read from,
    /// which makes a rule from it. The editor is called directly, and its captures are
    /// brought up to date first, as the Inspector's path brings them. With no app picked, or
    /// none left to find (the buffer is a fixed size, and the app's newest may be gone),
    /// nothing is opened and the core's sentence for it is handed back to show beside the
    /// button; the list the user picked from is made again from what is there.
    private func makeRule(fromApp app: String?) -> String? {
        guard let app else { return SetupText.pickAnAppFirst }
        guard let entry = SetupCapture.newestEntry(forApp: app, in: capture.history.entries) else {
            return SetupText.noBannerFromThatApp
        }
        ruleEditor.model.refreshCaptures(from: capture.history)
        ruleEditor.show(makingRuleFrom: entry)
        return nil
    }

    /// Opens the page of System Settings for an app, as the mute walkthrough's menu does,
    /// and hands back what the core says to show where that menu shows an alert: nothing
    /// when the lookup found the one app, and the pane it opened instead, and the name to
    /// look for, when it did not. The folders of apps are read only now, when asked.
    private func openNotificationSettings(ofApp app: String) -> String? {
        let resolution = BundleResolver.resolve(app, running: AppLocator.running(), installed: AppLocator.installed)
        NSWorkspace.shared.open(BundleResolver.notificationSettingsURL(for: resolution))
        return SetupText.muteLookupMessage(for: app, resolution: resolution)
    }
}
