// Sources/NotificationCore/SetupPlan.swift
import Foundation

/// What the first run reads to decide what to show, when to open and whether to nudge
/// (M5 plan, Ruling 16, O13, Task 7).
///
/// The app target reads each fact and hands it over, and decides nothing about it
/// (Ruling 10): `SetupPlan` decides. None has a default, so a place that forgets one
/// does not compile.
///
/// **Every step's state is derived from these, and only what no fact can show is
/// stored** (`progress`). A permission taken away afterwards is therefore never hidden
/// by something saved.
///
/// There is no word for an entry the user added to Login Items by hand: it was not
/// built, because such an entry reads enabled on macOS 26.7.1 (measured on 2026-10-05;
/// not seen on macOS 14 or 15), so `loginItem` is on for one, as for any enabled item
/// (M5 plan, Task 6 notes).
public struct SetupFacts: Equatable, Sendable {
    /// What the notification step reads. It needs both, because an app that is allowed
    /// to post can still have its banners switched off, and the step is for a page that
    /// can be seen.
    public struct Notifications: Equatable, Sendable {
        /// What the system's authorisation says, and whether a request could still show
        /// its dialog (`NotificationPermission`).
        public let permission: NotificationPermission
        /// Whether a banner of the app's own would be drawn (`DeliveryStatus.wouldDisplay`).
        public let wouldDisplay: Bool

        public init(permission: NotificationPermission, wouldDisplay: Bool) {
            self.permission = permission
            self.wouldDisplay = wouldDisplay
        }

        /// The step's fact: allowed **and** a banner would display. Allowed alone is not
        /// enough, and neither is a banner that would display for an app that is not
        /// allowed, which a status read together cannot give and which is not taken for
        /// done.
        public var isSetUp: Bool { permission == .allowed && wouldDisplay }
    }

    /// Accessibility is granted (`AXIsProcessTrusted()`).
    public var accessibilityTrusted: Bool
    /// The notification fact, **nil until the first probe has answered**. The launch
    /// decisions and the first menu build run before `DeliveryStatusProbe.current()`
    /// returns, so a value that could not be "not read yet" would make the plan assert
    /// something in that window, and a configured upgrader would see a nudge flash at
    /// launch. nil is unknown and is never read as outstanding (Ruling 16).
    public var notifications: Notifications?
    /// What health reads now.
    public var health: CaptureHealth
    /// When a self-test last succeeded (`AppDelegate`'s `lastCanarySucceededAt`), nil when
    /// none has. It is read only beside a health that is verified
    /// (`SetupPlan.verifiedAt(_:)`), so an old time is never shown as a verification that
    /// no longer stands.
    public var lastVerifiedAt: Date?
    /// What the loader made of the rules file (`RuleStoreStatus`).
    ///
    /// **There is no "not read yet" for the rules**, which Ruling 16 gives to the
    /// notification fact alone, so the rules have to be loaded before any nudge is built
    /// or shown. A store that has not loaded reads `.noRulesFile` (`RuleStore.status`
    /// before `reload()`), which the plan takes for an upgrader with no rule, and a nudge
    /// made from it would say "a first rule" to a configured upgrader. The app builds its
    /// first menu in `setUpStatusItem()`, before `reloadRules()` runs in launch, and that
    /// is harmless only while nothing calls the plan and while the menu is rebuilt each
    /// time it opens (`menuNeedsUpdate`), after the rules are loaded.
    public var ruleStatus: RuleStoreStatus
    /// What the rules in effect can do (`RuleReach(rules:)`), the count `OnCallCheck`
    /// reads, so that "alerts aloud" is counted in one place (`Rule.alertsAloud`). A rule
    /// the loader did not put in effect is not among them, so a rule that is in this
    /// count has no problem of the kind the loader reports. It is none until the rules
    /// are loaded, as `ruleStatus` is `.noRulesFile` until then, and is read under the
    /// same condition (see there).
    public var ruleReach: RuleReach
    /// Why the file cannot be written, when it cannot (`RulesDocument.ReadOnlyReason`, as
    /// the editor reads it), and nil when it can, or when there is no file.
    public var rulesFileReadOnly: RulesDocument.ReadOnlyReason?
    /// Whether anything has been captured since the app started. The first-rule step
    /// is made from a real capture, and shows the practice line while nothing has
    /// arrived.
    public var anythingCaptured: Bool
    /// The names of the apps captured so far, for the first-rule step to offer. **App
    /// names only, never a title or a body.** A name can be a fragment parsed out of a
    /// banner (`MuteWalkthrough.swift`), so the step lists them for the user to choose
    /// from and nothing says one where a count would do.
    public var capturedAppNames: [String]
    /// The apps to mute (`MuteWalkthrough.appsToMute(rules:alsoSounded:)`).
    public var appsToMute: [String]
    /// The user's word on which of them they have muted. The one shared checklist, which
    /// the menu and the on-call check read too.
    public var muteChecklist: MuteChecklist
    /// What Settings shows for the login item (`LaunchAtLogin.state(status:wanted:location:)`).
    public var loginItem: LaunchAtLogin.State
    /// What the first run has stored, because nothing it can read would show it.
    public var progress: SetupProgress

    public init(accessibilityTrusted: Bool, notifications: Notifications?, health: CaptureHealth,
                lastVerifiedAt: Date?, ruleStatus: RuleStoreStatus, ruleReach: RuleReach,
                rulesFileReadOnly: RulesDocument.ReadOnlyReason?, anythingCaptured: Bool,
                capturedAppNames: [String], appsToMute: [String], muteChecklist: MuteChecklist,
                loginItem: LaunchAtLogin.State, progress: SetupProgress) {
        self.accessibilityTrusted = accessibilityTrusted
        self.notifications = notifications
        self.health = health
        self.lastVerifiedAt = lastVerifiedAt
        self.ruleStatus = ruleStatus
        self.ruleReach = ruleReach
        self.rulesFileReadOnly = rulesFileReadOnly
        self.anythingCaptured = anythingCaptured
        self.capturedAppNames = capturedAppNames
        self.appsToMute = appsToMute
        self.muteChecklist = muteChecklist
        self.loginItem = loginItem
        self.progress = progress
    }
}

extension SetupStep {
    /// Whether the plan lets the user move past this step without it being done.
    ///
    /// **Two may be**, and they are the two the plan names: "Prove it can read", whose soft
    /// gate has "Continue without verifying" (O13), and "Keep it running", which the plan
    /// says is done "when the login item is enabled, or skipped" (M5 plan, Task 7, step 7,
    /// and O12 for the box and its Skip). A user under a Focus must not be stranded at the
    /// first, and the second is a change to the user's login items that they may decline.
    /// Each of the others is done by a fact or by an act of the user's that is always open
    /// to them (the introduction seen, a mute confirmed, the Focus attested), so none needs
    /// a way past.
    ///
    /// **A "skipped:" token stored for any other step means nothing to the plan.** It is
    /// read as written (`SetupProgress.isSkipped(_:)`), and the plan does not look at it:
    /// it does not make Accessibility, Notifications or the first rule done, which are
    /// facts, and it never makes the app configured, or the nudge go quiet. Nor does it
    /// make the introduction seen, a mute confirmed or the Focus attested, and it does not
    /// say the guide was begun (`SetupPlan.opensAtLaunch(_:)`). A stale token, or one
    /// written by another build, can therefore hide no step that a page depends on.
    /// No `switch` here has a default arm, so a step added later has to be placed.
    public var mayBeSkipped: Bool {
        switch self {
        case .proveItCanRead, .keepItRunning: return true
        case .howItWorks, .accessibility, .notifications, .firstRule, .muteSourceApp, .focus: return false
        }
    }

    /// Whether the step is one of the three that are facts about setup: Accessibility,
    /// Notifications and a first rule. These are what "configured" means, what the nudge
    /// counts, and the steps a user cannot be allowed to lose without a line (O13). They
    /// are the steps that cannot be skipped and are not the user's word.
    public var isRequired: Bool {
        switch self {
        case .accessibility, .notifications, .firstRule: return true
        case .howItWorks, .proveItCanRead, .muteSourceApp, .focus, .keepItRunning: return false
        }
    }
}

/// What the first run decides (M5 plan, Ruling 16, O13, Task 7), from `SetupFacts`: each
/// step's state, which step to show, whether the app is set up, whether the guide opens at
/// launch and so whether the launch prompts are kept, the menu's nudge, and what the last
/// step's box is and does. Nothing here shows a window, reads the system or saves
/// anything: the plan has no caller until Task 8 builds the window, and nothing a user can
/// see changes with it.
///
/// ## The steps
///
/// | step | done when | otherwise |
/// | --- | --- | --- |
/// | 0 how it works | the introduction was seen (the user's act, stored) | outstanding |
/// | 1 Accessibility | Accessibility is granted (read) | outstanding |
/// | 2 Notifications | allowed and a banner would display (read) | outstanding; unknown while the fact is nil |
/// | 3 prove it can read | health is verified (read) | skipped if it was; else outstanding |
/// | 4 first rule | an enabled rule with no problems alerts aloud (read) | blocked if the file is read-only; else outstanding |
/// | 5 mute the source app | every app to mute is confirmed (the user's word) | not applicable until step 4 is done and there is an app; else outstanding |
/// | 6 Do Not Disturb and Focus | the Focus is attested (the user's word) | outstanding |
/// | 7 keep it running | the login item is on (read) | skipped if it was; else outstanding |
///
/// The order is the order of `SetupStep.allCases`, which is the plan's.
public enum SetupPlan {
    // MARK: - What a step is

    /// What a step is, and what it rests on.
    public enum State: Equatable, Sendable {
        /// Done, resting on a fact the app read or on the user's word.
        case done(Basis)
        /// Not done, and read to be so.
        case outstanding
        /// Not read yet. Only the notification step is ever this, and only while the
        /// first probe has not answered. It is neither done nor outstanding.
        case unknown
        /// Nothing to do yet: the mute step, until the first rule is done and there is an
        /// app to name.
        case notApplicable
        /// Not done, and the user cannot do it here, for the reason given.
        case blocked(Blocker)
        /// The user moved past it without it being done. It is the user's word, and it is
        /// never read as a fact: a skipped "Prove it can read" is not verified, and a
        /// skipped "Keep it running" is not a login item that is on. Only the steps that
        /// `mayBeSkipped` are ever this.
        ///
        /// **A departure from the plan's wording for the last step**, "done when the login
        /// item is enabled, or skipped" (M5 plan, Task 7, step 7): a skip is a state of its
        /// own here, and `isDone` is false for it. A caller that asks `isDone` whether the
        /// guide is complete, or that says a step is done, does not call a declined login
        /// item done. `current`, `configuration` and the nudge pass over a skip all the
        /// same.
        case skipped

        /// What a done step rests on.
        public enum Basis: Equatable, Sendable {
            /// A fact the app read: the permission, the health, the rules, the login item.
            case fact
            /// The user's word, which nothing can check: a mute confirmed, the Focus
            /// attested, and the introduction seen. The summary says so of each.
            case yourWord
        }

        /// What stops a step.
        public enum Blocker: Equatable, Sendable {
            /// The rules file cannot be written, so no rule can be made from the editor,
            /// and only a text editor can fix it (`RulesDocument.ReadOnlyReason`).
            case rulesFileReadOnly(RulesDocument.ReadOnlyReason)
        }

        /// Done, whatever it rests on.
        public var isDone: Bool {
            if case .done = self { return true }
            return false
        }

        /// Whether the guide has something for the user here: outstanding, blocked, or
        /// not known yet. Done, skipped and not applicable have not.
        public var needsAttention: Bool {
            switch self {
            case .outstanding, .unknown, .blocked: return true
            case .done, .notApplicable, .skipped: return false
            }
        }

        /// Whether the step is read to be not done: outstanding or blocked, and **not**
        /// unknown. It is what the nudge and `configuration(_:)` count.
        var isKnownOutstanding: Bool {
            switch self {
            case .outstanding, .blocked: return true
            case .done, .unknown, .notApplicable, .skipped: return false
            }
        }
    }

    /// A step and its state.
    public struct Reading: Equatable, Sendable {
        public let step: SetupStep
        public let state: State

        public init(step: SetupStep, state: State) {
            self.step = step
            self.state = state
        }
    }

    /// Each step's state and what it rests on, in the plan's order: one reading for each
    /// of the eight steps.
    public static func evaluate(_ facts: SetupFacts) -> [Reading] {
        SetupStep.allCases.map { Reading(step: $0, state: state(of: $0, in: facts)) }
    }

    /// One step's state. No `switch` here has a default arm, so a step added later has to
    /// say what it reads.
    public static func state(of step: SetupStep, in facts: SetupFacts) -> State {
        switch step {
        case .howItWorks:
            return facts.progress.hasSeenIntroduction ? .done(.yourWord) : .outstanding

        case .accessibility:
            return facts.accessibilityTrusted ? .done(.fact) : .outstanding

        case .notifications:
            guard let notifications = facts.notifications else { return .unknown }
            return notifications.isSetUp ? .done(.fact) : .outstanding

        case .proveItCanRead:
            // The soft gate (O13). Verified is done whatever was skipped, since it is a fact.
            // A skip moves the guide on and leaves the step not done and not verified.
            if facts.health == .verified { return .done(.fact) }
            return skipStands(.proveItCanRead, in: facts) ? .skipped : .outstanding

        case .firstRule:
            if aRuleAlertsAloud(facts) { return .done(.fact) }
            if let reason = readOnlyReason(facts) { return .blocked(.rulesFileReadOnly(reason)) }
            return .outstanding

        case .muteSourceApp:
            // The list is made from the rules, and from what sounded, so nothing can be
            // listed before a rule that sounds exists. With no app to name, nothing is
            // confirmed and nothing is claimed, so it is not done either.
            guard state(of: .firstRule, in: facts).isDone, !facts.appsToMute.isEmpty else { return .notApplicable }
            return facts.muteChecklist.unconfirmed(among: facts.appsToMute).isEmpty ? .done(.yourWord) : .outstanding

        case .focus:
            return facts.progress.focusIsAttested ? .done(.yourWord) : .outstanding

        case .keepItRunning:
            if facts.loginItem.isOn { return .done(.fact) }
            return skipStands(.keepItRunning, in: facts) ? .skipped : .outstanding
        }
    }

    /// Whether a stored skip stands in for the step. Only for a step that
    /// `mayBeSkipped`; for any other the stored token is not looked at.
    private static func skipStands(_ step: SetupStep, in facts: SetupFacts) -> Bool {
        step.mayBeSkipped && facts.progress.isSkipped(step)
    }

    /// Whether an enabled rule with no problems alerts aloud, which is what the first-rule
    /// step is done by. The count is `RuleReach`'s, as the on-call check reads it. A rule
    /// the loader refused is not in effect and is not in that count, and the status is
    /// read as well, so that a count beside a file that is not in effect is never taken
    /// for a rule that will page. A Shortcut warning (`RuleWarnings`) is not a problem
    /// here: that rule stays in effect and sounds.
    private static func aRuleAlertsAloud(_ facts: SetupFacts) -> Bool {
        switch facts.ruleStatus {
        case .loaded, .loadedWithProblems: return facts.ruleReach.alertingAloud > 0
        case .noRulesFile, .unreadable, .unsupportedVersion: return false
        }
    }

    /// Why the rules file cannot be written. What the editor read says so, and so does a
    /// status that says no rules could be loaded from it, so that the step is blocked and
    /// not left outstanding when the app target hands over only one of the two.
    private static func readOnlyReason(_ facts: SetupFacts) -> RulesDocument.ReadOnlyReason? {
        if let reason = facts.rulesFileReadOnly { return reason }
        switch facts.ruleStatus {
        case .unreadable(let why): return .unreadable(why)
        case .unsupportedVersion(let version): return .newerVersion(version)
        case .noRulesFile, .loaded, .loadedWithProblems: return nil
        }
    }

    // MARK: - Which step to show

    /// The step the guide shows: the first, in the plan's order, that has something for
    /// the user (outstanding, blocked, or not read yet), or nil when none has, which is
    /// when the summary is next.
    ///
    /// A step the user skipped, or has nothing to do yet, is passed over, and so is one
    /// that is done. The three required steps (Accessibility, Notifications and a first
    /// rule) cannot be skipped, so the summary is not reached with one of them still to
    /// do.
    public static func current(_ facts: SetupFacts) -> SetupStep? {
        evaluate(facts).first(where: { $0.state.needsAttention })?.step
    }

    /// The cause the "Prove it can read" step shows while health is not verified, in the
    /// order health gives them (most likely first): nil for a verified health, for which
    /// there is no cause, and for one that has not been read yet, which has none to name
    /// and which the words say is still being checked.
    ///
    /// **nil is not "nothing is wrong".** It is also nil for a degraded or blind health
    /// that carries no cause, which `HealthEvaluator` never builds and which is still a
    /// problem. Whoever reads nil tells the cases apart by the health itself: `isAlarming`
    /// is a problem, and "still checking" is said only for `.unknown`. A problem with no
    /// cause is given `SelfNotification.fallbackBody`, as the on-call check and the health
    /// alarm give it (`OnCallCheck.findings(_:)`).
    public static func unverifiedCause(for health: CaptureHealth) -> HealthCause? {
        switch health {
        case .verified, .unknown: return nil
        case .degraded(let causes), .blind(let causes): return causes.first
        }
    }

    /// When capture was verified, for the line "verified at 14:02", and nil unless health
    /// is verified now. A time left over from an earlier success, beside a health that has
    /// since gone stale or failed, is never said as a verification, and a step skipped
    /// without verifying never has one.
    public static func verifiedAt(_ facts: SetupFacts) -> Date? {
        facts.health == .verified ? facts.lastVerifiedAt : nil
    }

    // MARK: - Whether the app is set up

    /// What the three required steps say together.
    public enum Configuration: Equatable, Sendable {
        /// Accessibility, Notifications and a first rule are all done.
        case configured
        /// At least one of them is read to be outstanding, whatever the others read.
        case notConfigured
        /// None is read to be outstanding, and at least one is not read yet: the
        /// notification fact before the first probe has answered.
        case unknown
    }

    /// Whether the app is set up, which is true when steps 1, 2 and 4 are done, and
    /// **deliberately leaves health out**: it reads "Checking…" at every launch and under
    /// any Focus, so counting it would treat a fully configured upgrader as unfinished
    /// (Ruling 16). It is also blind to a skip, the introduction, the mute and the
    /// Focus, none of which is a fact about setup.
    ///
    /// The type says what a Bool would hide. While the notification fact is nil the
    /// answer is `.unknown` and not `.notConfigured`, so a configured upgrader before the
    /// first probe is not read as unfinished, and neither the guide nor the nudge acts on
    /// it. A step that is read to be outstanding settles it as `.notConfigured` all the
    /// same, since nothing the probe answers can make the app configured then.
    public static func configuration(_ facts: SetupFacts) -> Configuration {
        let states = SetupStep.allCases.filter(\.isRequired).map { state(of: $0, in: facts) }
        if states.contains(where: \.isKnownOutstanding) { return .notConfigured }
        return states.allSatisfy(\.isDone) ? .configured : .unknown
    }

    // MARK: - When the guide opens

    /// Whether the guide opens by itself at launch.
    ///
    /// | progress | opens |
    /// | --- | --- |
    /// | finished | no, for good |
    /// | dismissed | no: "Not now" and closing the window are one act (O13) |
    /// | begun: started, or anything else only the guide's own buttons write | yes: it was begun and not ended |
    /// | nothing the plan reads, Accessibility not granted | yes: a fresh install |
    /// | nothing the plan reads, Accessibility granted | no: an upgrader, whatever else is set up |
    ///
    /// A configured upgrader (Accessibility granted, notifications allowed, a rule that
    /// alerts aloud, nothing stored) therefore never meets the guide, whatever health
    /// reads and before the first probe has answered, and neither does an upgrader with no
    /// rule yet, who has the menu's nudge instead. Nothing here reads health or the
    /// notification fact, so neither can open the guide or keep it shut.
    ///
    /// **A progress that holds a token other than started, and not started, reads as
    /// begun.** The introduction seen, the Focus attested and a skip of a step that may be
    /// skipped are written only by the guide's own buttons, so a user who has one of them
    /// has been in the guide and not left it finished or dismissed, which is what "started
    /// and neither" means to them. The guide records the start before anything else, so
    /// such a progress is not one the app makes; it is what a preferences file edited by
    /// hand or a record cut short would leave, and the direction taken is the one that
    /// does not lose a page: the guide opens and the user answers it or dismisses it,
    /// rather than a half-finished setup being passed over in silence.
    ///
    /// **A skip of a step that may not be skipped is not one of them.** It means nothing
    /// to the plan (`SetupStep.mayBeSkipped`), so it neither opens the guide for an
    /// upgrader nor keeps it from a fresh install: such a progress reads as nothing stored.
    /// A list of tokens that only a newer build knows is a fresh install's too
    /// (`SetupProgress.isFresh`).
    ///
    /// A dismissal is not undone by a later start, so a guide that was dismissed and then
    /// opened again from Settings and left unfinished does not reopen at launch. The
    /// nudge is what is left for it.
    public static func opensAtLaunch(_ facts: SetupFacts) -> Bool {
        let progress = facts.progress
        if progress.isFinished || progress.isDismissed { return false }
        if guideWasBegun(progress) { return true }
        return !facts.accessibilityTrusted
    }

    /// Whether the progress shows that the guide was begun: started, or anything that only
    /// the guide's own buttons write and the plan reads. A skip counts only for a step that
    /// may be skipped.
    private static func guideWasBegun(_ progress: SetupProgress) -> Bool {
        progress.hasStarted || progress.hasSeenIntroduction || progress.focusIsAttested
            || SetupStep.allCases.contains { $0.mayBeSkipped && progress.isSkipped($0) }
    }

    /// Whether the app asks for Accessibility and for notification authorisation at
    /// launch (`AppDelegate`'s two launch prompts). They are kept for everyone the guide
    /// does not open for, and skipped exactly when it does, since the guide explains a
    /// permission before it asks and nothing prompts until the user presses its button
    /// (Ruling 16). The probe and the health refresh run either way.
    public static func promptsAtLaunch(_ facts: SetupFacts) -> Bool {
        !opensAtLaunch(facts)
    }

    // MARK: - The menu's nudge

    /// The steps the nudge counts, which are the required ones: facts about setup, and
    /// never health (Ruling 16).
    public static let requiredSteps: [SetupStep] = SetupStep.allCases.filter(\.isRequired)

    /// The menu's one line while setup is not finished, or nil.
    ///
    /// Shown while the guide's window is closed, the guide is not finished, and one of
    /// Accessibility, Notifications and a first rule is **read** to be outstanding. It is
    /// nil in these cases:
    ///
    /// - a configured upgrader, whatever health reads, since health is not a fact it
    ///   counts, and nothing it says mentions health;
    /// - a notification fact that is nil, which is not read as outstanding: a configured
    ///   upgrader before the first probe has answered gets no nudge, where one that read
    ///   nil as outstanding would flash it at launch, and an upgrader with no rule gets
    ///   the line without Notifications in it;
    /// - a guide that is finished, for good, since a permission revoked afterwards is
    ///   already said by the health line, the alarm and the icon;
    /// - the guide's window being open, which the app target reads and hands over.
    ///
    /// **It stays after "Not now" and after the window is closed**, which are one act and
    /// write one dismissal (O13): the guide does not open again by itself, and a required
    /// step that is still to do is not lost without the line. A blocked first rule is
    /// still to do, so it is counted. What the line says is `SetupText`'s.
    public static func nudgeLine(_ facts: SetupFacts, guideIsOpen: Bool) -> String? {
        guard !guideIsOpen, !facts.progress.isFinished else { return nil }
        let outstanding = requiredSteps.filter { state(of: $0, in: facts).isKnownOutstanding }
        return SetupText.nudgeLine(outstanding: outstanding)
    }

    // MARK: - The last step's box

    /// Whether the last step shows its box, "Launch at login". It is shown only where
    /// registering can succeed, which is Task 6's state of off and able to be switched on,
    /// and it starts ticked, so that pressing Continue registers what the user saw and
    /// pressed Continue on (O12). Everywhere else it is absent, and the reason is what the
    /// step says in its place.
    public enum LoginItemBox: Equatable, Sendable {
        /// Shown, and starting ticked.
        case shown
        /// Not shown, for this reason.
        case absent(Absence)

        /// Why there is no box.
        public enum Absence: Equatable, Sendable {
            /// The login item is on already, so there is nothing to ask.
            case alreadyOn
            /// The system has it switched off, or is waiting for the user's approval, in
            /// System Settings. Settings has two buttons for it, and the box is not one:
            /// whether a registration would turn it on again was not measured, and the
            /// guide asks for nothing it cannot say will work.
            case switchedOffInSystemSettings
            /// It cannot be registered from where this copy runs, for the reason, which
            /// the step gives in the box's place (`LaunchAtLoginText.reason(for:)`).
            case unavailable(LaunchAtLogin.Unavailable)
        }

        /// Whether the box is shown.
        public var isShown: Bool { self == .shown }

        /// Whether it starts ticked: only a box that is shown does, and it always does.
        public var startsTicked: Bool { self == .shown }
    }

    /// The box for the login item as read: shown, and ticked, only for `.off`, whatever
    /// the user had wanted; absent for every other state. No `switch` here has a default
    /// arm, so a state added later has to say whether it can be registered.
    public static func loginItemBox(for state: LaunchAtLogin.State) -> LoginItemBox {
        switch state {
        case .off: return .shown
        case .on: return .absent(.alreadyOn)
        case .switchedOffInSystemSettings: return .absent(.switchedOffInSystemSettings)
        case .unavailable(let why): return .absent(.unavailable(why))
        }
    }

    /// A button of the last step.
    public enum KeepItRunningPress: Equatable, Sendable {
        /// Continue.
        case continueButton
        /// Skip.
        case skipButton
    }

    /// What a press of the last step's button comes to, which the window carries out and
    /// does not decide (Ruling 10).
    public struct KeepItRunningResult: Equatable, Sendable {
        /// What to ask of the system: `.register`, the same request as turning Settings'
        /// switch on (`LaunchAtLogin.request(switchTurnedOn:)`), or nil to ask nothing.
        public let request: LaunchAtLogin.Request?
        /// What to save as the user's choice (`LaunchAtLogin.wantedKey`), or nil to save
        /// none: what a press that registers saves in Settings
        /// (`LaunchAtLogin.Action.wantedAfterPress`), so that the choice is kept on the
        /// guide's path as on that one. Without it a login item the user later switches off
        /// in System Settings would get no line in the menu, which is shown only for a
        /// choice the app saved (`LaunchAtLogin.reconcile(wanted:status:onCall:)`). The
        /// window saves what this says and chooses nothing (Ruling 10).
        public let wantedAfterPress: Bool?
        /// Whether to record that the step was skipped (`SetupProgress.recordSkipped(_:)`),
        /// which is how the guide moves on without a login item.
        public let recordsSkip: Bool

        public init(request: LaunchAtLogin.Request?, wantedAfterPress: Bool?, recordsSkip: Bool) {
            self.request = request
            self.wantedAfterPress = wantedAfterPress
            self.recordsSkip = recordsSkip
        }
    }

    /// What Continue and Skip do on the last step (O12, Ruling 16).
    ///
    /// - **Continue registers only when the box is shown and ticked**, which is the user's
    ///   own act, seen before it is done. The step is then done when the status read
    ///   afterwards says the item is on, and not before: a registration the system did not
    ///   enable leaves the step where it was, with what the system said, so that the user
    ///   chooses again, and records no skip. It saves the user's choice as Settings' switch
    ///   does, whatever the system then reads (`LaunchAtLogin.Action.turnOn`).
    /// - Continue registers nothing for an unticked box, and nothing where no box is shown,
    ///   whatever a tick the window still holds says. It moves on, by recording the skip,
    ///   since the step is done only by a fact or by a skip, and a user who declined or
    ///   could not be asked must not be held at it.
    /// - Skip registers nothing, whatever the box says, and records the skip. Neither it,
    ///   nor an unticked box, nor a state with no box saves a choice: nothing was asked of
    ///   the system, and a choice the user saved before is left as it was.
    /// - Where the login item is on already, nothing is registered and no skip is
    ///   recorded: the step is done, and a skip stored then would hide a later switch-off
    ///   as the user's choice.
    ///
    /// `boxTicked` is what the window holds for the tick. It is read only for a box that
    /// is shown.
    public static func pressing(_ press: KeepItRunningPress, state: LaunchAtLogin.State,
                                boxTicked: Bool) -> KeepItRunningResult {
        let registers = press == .continueButton && loginItemBox(for: state).isShown && boxTicked
        return KeepItRunningResult(request: registers ? LaunchAtLogin.request(switchTurnedOn: true) : nil,
                                   wantedAfterPress: registers ? LaunchAtLogin.Action.turnOn.wantedAfterPress : nil,
                                   recordsSkip: !registers && !state.isOn)
    }
}
