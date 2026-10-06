// Sources/NotificationCore/SetupText.swift
import Foundation

/// The words of the first run (M5 plan, Ruling 16, Ruling 18, Task 7): the menu's nudge,
/// every step's title, reason, state, detail and buttons, and the summary. The window of
/// Task 8 only shows what is made here, so nothing it says can be more than the app has
/// established.
///
/// **Each line says no more than was established.**
/// - "Verified" is said only of a health that is verified, and only in the "Prove it can
///   read" step and the summary's line for it, with the time the facts give. A step that
///   was not proven says what was not read, and never that capture is verified.
/// - Muting and the Focus are the user's word, and say so. A Focus cannot be read, so no
///   line says one is on or was on: the advice that a Focus hides banners is
///   `MuteWalkthroughText.focus`, which is conditional, reused and not written again.
/// - The "Prove it can read" step says SignalLadder can read its own test banner, and
///   says nothing of whether the user's notifications will be captured.
/// - A line never holds what a notification said or a rule's name. App names, which can
///   be a fragment parsed out of a banner, are held only in `StepWords.apps`, as the
///   list the user chooses from or acts on in steps 4 and 5 (names only, never a title or
///   a body), and in no sentence, where a count says what is needed. The one exception is
///   `practiceCaution`, which names the fixed app the practice banner arrives as, so that
///   the user knows where to look; that name is a constant and is not read from a banner.
///
/// Where a sentence already exists it is reused and not written a second time:
/// `MuteWalkthroughText.focus` and its buttons, `OnCallText`'s Focus sentences and its
/// login sentence, `SettingsText`'s and `LaunchAtLoginText`'s sentences for the login
/// item, `EditorText`'s read-only reason and its "If I don't acknowledge", `HealthCause`'s
/// advice, `HealthTitle`'s words for a health that is a problem and
/// `SelfNotification.fallbackBody`.
///
/// The constants the harness reads are each on one line as
/// `public static let NAME = "TEXT"`, the shape it reads (Ruling 18).
public enum SetupText {
    // MARK: - The menu's nudge

    /// How the menu's setup line begins, and what the harness looks for to know
    /// that a Mac's menu carries none (Task 9). It stays on one line as
    /// `public static let NAME = "TEXT"`, the shape the harness reads (Ruling 18).
    public static let nudgeStem = "Setup is not finished"

    /// What the nudge calls a step that is still to do. Only the three steps the
    /// nudge counts have a word (`SetupPlan.requiredSteps`), so another step is
    /// said as nothing. The words are nouns, so that a list of them reads on one
    /// line, and none says why the step is outstanding, since the nudge has read no
    /// more than that it is.
    static func nudgeWord(for step: SetupStep) -> String? {
        switch step {
        case .accessibility: return "Accessibility"
        case .notifications: return "Notifications"
        case .firstRule: return "a first rule"
        case .howItWorks, .proveItCanRead, .muteSourceApp, .focus, .keepItRunning: return nil
        }
    }

    /// The menu's one line while setup is not finished, or nil when none of the
    /// steps it counts is outstanding.
    ///
    /// `outstanding` is what the plan has read to be so: a step whose state is not
    /// known yet is not in it (`SetupPlan.nudgeLine(_:guideIsOpen:)`), so the line
    /// says which step is outstanding only as far as that was read. The steps are
    /// said in the plan's order whatever order they come in, once each, and a step
    /// the nudge does not count is left out. The line never mentions health: the
    /// health line, the alarm and the icon say that, and a nudge that did would show
    /// at every launch, when health reads "Checking…" (Ruling 16).
    public static func nudgeLine(outstanding: [SetupStep]) -> String? {
        let words = SetupStep.allCases.filter { outstanding.contains($0) }.compactMap { nudgeWord(for: $0) }
        guard !words.isEmpty else { return nil }
        return "\(nudgeStem) — still to do: \(MuteWalkthroughText.list(words))"
    }

    // MARK: - The buttons

    /// What a press of a button asks of the window. The window carries each out and
    /// decides none (Ruling 10); `SetupPlan.pressing(_:state:boxTicked:)` says what
    /// Continue and Skip come to on the last step.
    public enum ButtonAction: CaseIterable, Equatable, Sendable {
        /// Moves on, once the step is done, or records that the user has seen the
        /// introduction, or registers the login item when its box is ticked.
        case continueOn
        /// Moves past the last step without registering the login item.
        case skip
        /// Closes the guide and records one dismissal, as closing its window does (O13).
        case notNow
        /// Reads the step's facts again, which the guide does when the app is activated
        /// and the menu opens too (Ruling 20): no timer.
        case checkAgain
        /// The soft gate's way past "Prove it can read" (O13).
        case continueWithoutVerifying
        /// Asks macOS for Accessibility, which is the only press that shows its prompt.
        case allowAccessibility
        /// Opens the Accessibility pane of System Settings.
        case openAccessibilitySettings
        /// Asks for permission to show notifications, which macOS may answer with its
        /// own prompt.
        case allowNotifications
        /// Opens SignalLadder's own notification settings.
        case openNotificationSettings
        /// Opens the rule editor on a notification that was read, which is how the first
        /// rule is made (`ruleEditor.show(makingRuleFrom:)`).
        case makeRule
        /// Opens the rules file in a text editor, which the first rule's step offers
        /// where the file cannot be written from the editor.
        case openRulesFile
        /// Records that the user has turned off an app's own sound: their word.
        case confirmMuted
        /// Opens the notification settings of an app the guide lists.
        case openAppNotificationSettings
        /// Opens Focus in System Settings (`MuteWalkthroughText.openFocusSettings`).
        case openFocusSettings
        /// Records that the user has looked at their Focus settings: their word.
        case confirmFocus
        /// Opens Login Items in System Settings (`LaunchAtLogin.Action.openLoginItems`),
        /// which the last step offers for a login item the system has switched off or is
        /// holding for approval, where the user decides. It registers nothing and saves
        /// nothing. The other button Settings has for that state, which asks to register
        /// again, is not offered here: what that answers was not measured (O12).
        case openLoginItems
        /// Ends the guide from the summary, which records it finished.
        case finish
    }

    /// The label of a button. The verb is the one its step needs, and a button that
    /// opens a pane of System Settings, or that asks macOS for a prompt, ends in an
    /// ellipsis, as the menu's items do. The rules file's button is worded as the editor
    /// words it, with none. No `switch` here has a default arm, so an action added later
    /// has to say its words.
    public static func label(for action: ButtonAction) -> String {
        switch action {
        case .continueOn: return "Continue"
        case .skip: return "Skip"
        case .notNow: return "Not now"
        case .checkAgain: return "Check again"
        case .continueWithoutVerifying: return "Continue without verifying"
        case .allowAccessibility: return "Allow Accessibility…"
        case .openAccessibilitySettings: return "Open Accessibility Settings…"
        case .allowNotifications: return "Allow Notifications…"
        case .openNotificationSettings: return "Open Notification Settings…"
        case .makeRule: return "Make a Rule from This…"
        // The rules file's button as the editor shows it. The menu's item is the same
        // words with an ellipsis, in `AppDelegate`, which has no constant for it, so this
        // one is new and is the one to use (Task 8 may move those two to it).
        case .openRulesFile: return "Open Rules File in Text Editor"
        case .confirmMuted: return MuteWalkthroughText.confirm
        // Distinct from `.openNotificationSettings`, which is SignalLadder's own.
        case .openAppNotificationSettings: return "Open Its Notification Settings…"
        case .openFocusSettings: return MuteWalkthroughText.openFocusSettings
        case .confirmFocus: return "I've Checked My Focus Settings"
        // Settings' and the on-call finding's own words for it.
        case .openLoginItems: return LaunchAtLoginText.openLoginItems
        case .finish: return "Finish"
        }
    }

    /// A button as the step shows it.
    public struct StepButton: Equatable, Sendable {
        public let action: ButtonAction
        public let label: String
    }

    // MARK: - Titles

    /// The title of a step, which is the one the plan's order names (M5 plan, Task 7,
    /// "The steps"). No `switch` here has a default arm, so a step added later has to be
    /// named.
    public static func title(for step: SetupStep) -> String {
        switch step {
        case .howItWorks: return "How it works"
        case .accessibility: return "Accessibility"
        case .notifications: return "Notifications"
        case .proveItCanRead: return "Prove it can read"
        case .firstRule: return "First rule"
        case .muteSourceApp: return "Mute the source app"
        case .focus: return "Do Not Disturb and Focus"
        case .keepItRunning: return "Keep it running"
        }
    }

    // MARK: - What a step says before it asks

    /// The replacement model (spec §1.1): SignalLadder is meant to replace the source app's
    /// own sound and not to add to it. That holds only once the user has turned the app's
    /// sound off, and until then every alert plays on top of the app's own ping, as the pages
    /// say (`docs/getting-started.md`, `docs/troubleshooting.md`). So the first sentence says
    /// what it is meant to do, and not that it does; the second says what is so until the
    /// sound is off; and the third says what is so after, that SignalLadder is its only voice.
    public static let replacementModel = "SignalLadder is meant to replace an app's notification sound, not to add to it. Until you turn the source app's sound off in System Settings, every alert plays on top of the app's own ping. Turn it off, and SignalLadder becomes its only voice: silent by default, and sounding only when a rule earns it."
    /// Leads the three limits.
    public static let limitsLead = "Three limits, said plainly:"
    /// The first limit, and the caveat the Accessibility step carries (`docs/privacy.md`).
    /// It says the grant is broader than its use and that only SignalLadder's own code
    /// holds it to Notification Centre, which is what the privacy page says.
    public static let accessibilityLimit = "The Accessibility permission is broader than SignalLadder's use of it. macOS has no grant that means “notifications only”, so only SignalLadder's own code holds it to Notification Centre."
    /// The second limit: SignalLadder cannot turn the source app's sound off for the user.
    public static let ownSoundLimit = "SignalLadder cannot silence the source app's own sound. Only you can turn it off, in System Settings, and a later step helps with that."
    /// The third limit, in the mute walkthrough's own words, which are conditional and
    /// so claim no Focus is on: the first two lines of `MuteWalkthroughText.focus`.
    static var focusLimit: String { MuteWalkthroughText.focus.prefix(2).joined(separator: " ") }

    /// What the Accessibility step says SignalLadder does with the permission.
    public static let accessibilityReads = "SignalLadder reads notification banners through macOS Accessibility, from Notification Centre only. It only reads: it never clicks, dismisses, replies or types."
    /// Said under the two steps that ask macOS for something: nothing is asked until the
    /// button is pressed (Ruling 16).
    public static let askedOnlyOnPress = "macOS shows its own prompt only when you press the button, and not before."

    /// Why the notification step is there: the self-test is a banner SignalLadder shows
    /// itself, and the next step needs it drawn.
    public static let notificationsWhy = "SignalLadder shows itself a test banner to prove it can read banners, which is the next step. So it needs your permission to show notifications, and its own banners have to be switched on."

    /// What the "Prove it can read" step does.
    public static let proveWhy = "SignalLadder shows itself a test banner and checks that it can read it."
    /// What it shows, and what it does not: its own test banner, and nothing about the
    /// user's other apps (O13). It never says the user's notifications will be captured.
    public static let proveLimit = "That shows that it can read its own test banner, and no more: it says nothing about the banners of your other apps."

    /// Why the first rule is made from a real notification.
    public static let firstRuleWhy = "A rule says which notifications should make SignalLadder sound. You make your first from a real one it has read, so that it matches what the app really sends."
    /// What the step is done by, in the words the on-call check and the menu use for a
    /// rule that makes a noise.
    public static let firstRuleDone = "This step is done when a rule that is switched on makes a sound or speaks."
    /// Where the ladder is chosen: in the editor, under the heading the editor shows.
    static var ladderWhere: String { "In the editor, choose how it escalates under “\(EditorText.ifIDontAcknowledge)”." }

    /// What to do while nothing has arrived: a practice notification from a terminal
    /// window (`docs/getting-started.md`), which SignalLadder neither runs nor copies,
    /// since it runs no scripts and never writes to the clipboard (Ruling 16). It names no
    /// app: the one the practice banner arrives as is named in `practiceCaution`, which is
    /// said with it.
    public static let practiceLead = "Nothing has arrived yet. To see a banner straight away, post a practice notification from a terminal window. SignalLadder does not run this line and does not copy it: select it and paste it yourself."
    /// The practice line itself, as text to select. Every word of it is fixed here.
    public static let practiceCommand = #"osascript -e 'display notification "Placeholder body" with title "Test title" subtitle "Test subtitle"'"#
    /// Said with the practice line, because a rule made from the practice banner reads as a
    /// first rule that is in effect and matches none of the user's real notifications, which
    /// is the silent failure Ruling 20 names. It says what the pages say
    /// (`docs/getting-started.md`, `docs/troubleshooting.md`): the practice banner arrives as
    /// Script Editor, so a banner that is not drawn is Script Editor's own notification
    /// setting to look at, and a rule made from it is for practice. The name is a fixed
    /// constant, the app `osascript` posts as, and not one parsed out of a banner, so the
    /// Global Constraints' rule against naming an app where a count would do does not reach
    /// it (a count cannot say where to look). It is the one sentence that names an app, and
    /// the test that none does allows this one line and no other.
    public static let practiceCaution = "The practice banner arrives as Script Editor, so if none is drawn, check that Script Editor is allowed to show notifications in System Settings › Notifications. A rule made from it is for practice only: it will not match your real notifications. Make your first real rule from a real notification, and delete the practice rule afterwards."
    /// What the first rule is made from, said after what was read: a notification the user
    /// wants to be paged for, and not a practice banner (`practiceCaution`). It does not say
    /// "make a rule from it", which read as an instruction to use the practice banner when
    /// that was the only one read.
    public static let ruleFromARealOne = "Make a rule from a notification you want to be paged for, and not from a practice banner."
    /// When banners were read and none gave an app name.
    public static let bannersWithoutNames = "SignalLadder has read banners, and none of them gave an app name. \(ruleFromARealOne)"

    /// "SignalLadder has read banners from 3 apps." A count, so that the sentence names no
    /// app: the names are in `StepWords.apps`, for the user to choose from.
    public static func appsReadLine(count: Int) -> String {
        "SignalLadder has read banners from \(count) \(count == 1 ? "app" : "apps"). \(ruleFromARealOne)"
    }

    /// Why an app's sound is turned off, and that only the sound is: banners have to stay
    /// on, because SignalLadder reads banners (O5).
    public static let muteWhy = "Turn off the notification sound of each app listed, in System Settings, so that SignalLadder is its only voice. Turn off only the sound: leave banners on, because SignalLadder reads banners."
    /// Muting is the user's word.
    public static let muteYourWord = "SignalLadder cannot check that an app is muted. Your tick is your word, and nothing else backs it."

    /// What the Focus step says of the user's tick, after the advice and after it has said
    /// that a Focus cannot be read.
    public static let focusYourWord = "Your tick is your word, and nothing else backs it."

    /// What the last step says first: on-call mode needs the app running.
    public static let keepRunningWhy = "On-call mode works only while SignalLadder is running."
    /// What Launch at login does, and that it is the user's choice.
    public static let loginItemWhy = "Launch at login starts SignalLadder when you log in, and it is your choice whether it does."
    /// Said with the box, which starts ticked for the user (O12): what Continue and Skip
    /// come to, so that what is switched on is what the user saw (`SetupPlan.pressing`). It
    /// says nothing of where the box sits, which is the window's to decide (Task 8).
    public static let boxExplanation = "Launch at login starts ticked. Continue with it ticked switches it on. Skip, or Continue with it unticked, switches nothing on."

    /// What a step says before it asks anything: why it is there, and what it will do.
    /// Said whatever state the step is in. The words that depend on what was read are
    /// `status(for:facts:time:)` and `detail(for:facts:)`.
    public static func why(for step: SetupStep) -> [String] {
        switch step {
        case .howItWorks:
            return [replacementModel, limitsLead, accessibilityLimit, ownSoundLimit, focusLimit]
        case .accessibility:
            return [accessibilityReads, accessibilityLimit, askedOnlyOnPress]
        case .notifications:
            return [notificationsWhy]
        case .proveItCanRead:
            return [proveWhy, proveLimit]
        case .firstRule:
            return [firstRuleWhy, ladderWhere, firstRuleDone]
        case .muteSourceApp:
            return [muteWhy, muteYourWord]
        case .focus:
            return [MuteWalkthroughText.focus.joined(separator: " "),
                    "\(OnCallText.focusCannotRead) \(OnCallText.focusWorkaround)",
                    focusYourWord]
        case .keepItRunning:
            return [keepRunningWhy, loginItemWhy]
        }
    }

    // MARK: - What a step says it rests on

    /// Said beside a step that is done on a fact the app read.
    public static let basisRead = "Read by SignalLadder"
    /// Said beside a step that is done on the user's word, which nothing can check.
    public static let basisYourWord = "Your word, which SignalLadder cannot check"

    /// What a done step rests on, in words, and nil for a step that is not done.
    public static func basis(of state: SetupPlan.State) -> String? {
        switch state {
        case .done(.fact): return basisRead
        case .done(.yourWord): return basisYourWord
        case .outstanding, .unknown, .notApplicable, .blocked, .skipped: return nil
        }
    }

    // MARK: - What a step says it has read

    /// Said of a notification fact that is nil: the first probe has not answered.
    public static let notificationsUnknown = "SignalLadder has not found out yet whether it may show notifications."
    /// Said of a permission that was never asked for, which a request can still put a
    /// dialog in front of.
    public static let notificationsNotAsked = "SignalLadder has not asked for permission to show notifications yet. Pressing the button asks, and macOS may show its own prompt."
    /// Said of a permission that is not allowed, in the form the other sentences use: what
    /// macOS reported, and not why.
    public static let notificationsDenied = "macOS does not report notifications as allowed for SignalLadder."
    /// Said when SignalLadder may post and its own banners would not be drawn.
    public static let notificationsNotShown = "macOS allows SignalLadder to post notifications, but its own banners would not be drawn."
    /// What to look at when the banners would not be drawn: the three settings the probe
    /// reads (`DeliveryStatusProbe`: the alert style, Notification Centre, and the Scheduled
    /// Summary), in the words `docs/getting-started.md` and `docs/troubleshooting.md` use.
    /// Deliver Quietly is said only as a way for the banners to be off, as the pages say it,
    /// and not as a fourth setting. The first setting is the Desktop checkbox on macOS 26 and
    /// an alert style other than None before it, and macOS 14 and 15 are the floor, so both
    /// are said.
    public static let notificationsBannerAdvice = "In System Settings › Notifications › SignalLadder, its banners need to be switched on (the Desktop checkbox on macOS 26, an alert style other than None before it, and not Deliver Quietly), Notification Centre needs to be switched on, and a Scheduled Summary must not be holding its notifications."
    /// Said when it may, and its own banners would be drawn: the fact the step is done by.
    public static let notificationsReady = "macOS reports that SignalLadder may show notifications, and its own banners would be drawn."

    /// Said of a health that has not read a test banner yet. It does not say a check is
    /// under way.
    public static let proveNotYetRead = "SignalLadder has not read a test banner of its own yet."
    /// Said after a skipped "Prove it can read", so that the summary never reads as proof.
    public static let proveContinuedWithout = "You continued without it."

    /// Said of an Accessibility permission that macOS does not report as allowed.
    public static let accessibilityNotAllowed = "macOS does not report Accessibility as allowed for SignalLadder."
    /// Said of one that is.
    public static let accessibilityAllowed = "macOS reports that Accessibility is allowed for SignalLadder."

    /// Said of the introduction.
    public static let introductionNotRead = "You have not been through this yet."
    public static let introductionRead = "You have read this."

    /// Said of the first rule.
    public static let firstRuleNone = "No rule that is switched on and makes a sound or speaks is in effect."
    public static let firstRuleInEffect = "A rule that is switched on and makes a sound or speaks is in effect."

    /// Said of the mute step, which is the user's word, while it has nothing to confirm.
    /// It has nothing for one of two reasons, and each is said as itself: no rule that
    /// sounds is in effect yet, or one is and SignalLadder has no app to name, which is
    /// what a rule that matches by pattern gives until something sounds
    /// (`MuteWalkthrough.appsToMute`). The second must not read as nothing to do: no app
    /// is confirmed muted, and the source app's own sound is neither checked nor covered.
    public static let muteWaitsForRule = "Nothing to confirm yet: this step opens once your first rule is made."
    public static let muteNoAppToName = "SignalLadder has no app to name yet, so nothing is confirmed muted. It neither checks nor silences the source app's own sound, so turning that off is still up to you."
    public static let muteConfirmed = "You said you turned off the sound of every app listed."

    /// Said of the Focus step, which is the user's word.
    public static let focusNotAttested = "You have not said that you checked your Focus settings."
    public static let focusAttested = "You said you checked your Focus settings."

    /// Said when a step the plan does not let be skipped is nonetheless skipped, or a
    /// state the plan gives only one step is another's. The plan gives neither, so these
    /// are not shown; they are here so that no `switch` has a default arm.
    static let skippedGeneric = "You moved past this without it being done."
    static let notReadGeneric = "SignalLadder has not read this yet."

    /// What the step says it has read, or the user said, for the state it is in: the one
    /// line the window shows beside the step, and the summary's line for it.
    ///
    /// Each line says what was established and no more. For "Prove it can read" it is
    /// "verified" only for a health that is verified, with the time the facts give, and
    /// for any other health it says what was not read: a health that is a problem says
    /// what the health line says (`HealthTitle`), and one that has not been read yet says
    /// so, with the time of the last test banner it did read, if any, which is not given
    /// as a verification. For the last step it is the login item's sentence in Settings.
    ///
    /// - Parameter time: how a moment is shown, as the menu's other lines show one
    ///   ("14:02").
    public static func status(for step: SetupStep, facts: SetupFacts, time: (Date) -> String) -> String {
        switch SetupPlan.state(of: step, in: facts) {
        case .done: return doneStatus(step, facts: facts, time: time)
        case .outstanding: return outstandingStatus(step, facts: facts, time: time)
        case .unknown: return step == .notifications ? notificationsUnknown : notReadGeneric
        case .notApplicable: return step == .muteSourceApp ? muteNothingToConfirm(facts) : notReadGeneric
        case .blocked(.rulesFileReadOnly(let reason)): return EditorText.readOnly(reason).title
        case .skipped: return skippedStatus(step, facts: facts, time: time)
        }
    }

    /// What the mute step says while it has nothing to confirm: that it waits for the first
    /// rule, or, once that rule is done, that SignalLadder has no app to name.
    private static func muteNothingToConfirm(_ facts: SetupFacts) -> String {
        SetupPlan.state(of: .firstRule, in: facts).isDone ? muteNoAppToName : muteWaitsForRule
    }

    private static func doneStatus(_ step: SetupStep, facts: SetupFacts, time: (Date) -> String) -> String {
        switch step {
        case .howItWorks: return introductionRead
        case .accessibility: return accessibilityAllowed
        case .notifications: return notificationsReady
        case .proveItCanRead: return verifiedLine(facts, time: time)
        case .firstRule: return firstRuleInEffect
        case .muteSourceApp: return muteConfirmed
        case .focus: return focusAttested
        case .keepItRunning: return SettingsText.launchAtLoginSentence(for: facts.loginItem)
        }
    }

    private static func outstandingStatus(_ step: SetupStep, facts: SetupFacts, time: (Date) -> String) -> String {
        switch step {
        case .howItWorks: return introductionNotRead
        case .accessibility: return accessibilityNotAllowed
        case .notifications: return notificationsStatus(facts.notifications)
        case .proveItCanRead: return notProvenStatus(facts, time: time)
        case .firstRule: return firstRuleNone
        case .muteSourceApp:
            return OnCallText.unconfirmedMuting(count: facts.muteChecklist.unconfirmed(among: facts.appsToMute).count)
        case .focus: return focusNotAttested
        case .keepItRunning: return SettingsText.launchAtLoginSentence(for: facts.loginItem)
        }
    }

    private static func skippedStatus(_ step: SetupStep, facts: SetupFacts, time: (Date) -> String) -> String {
        switch step {
        case .proveItCanRead:
            // The health line's words end without a stop, and the sentence after them needs one.
            let said = notProvenStatus(facts, time: time)
            return "\(said)\(said.hasSuffix(".") ? "" : ".") \(proveContinuedWithout)"
        case .keepItRunning: return "Skipped. \(SettingsText.launchAtLoginSentence(for: facts.loginItem))"
        case .howItWorks, .accessibility, .notifications, .firstRule, .muteSourceApp, .focus: return skippedGeneric
        }
    }

    /// What the notification step has read, for a fact that is not set up.
    private static func notificationsStatus(_ notifications: SetupFacts.Notifications?) -> String {
        guard let notifications else { return notificationsUnknown }
        switch notifications.permission {
        case .notAsked: return notificationsNotAsked
        case .denied: return notificationsDenied
        case .allowed: return notifications.wouldDisplay ? notificationsReady : notificationsNotShown
        }
    }

    /// "SignalLadder read its own test banner: verified at 14:02." Said only of a health
    /// that is verified, and the time is the facts' when health is verified now
    /// (`SetupPlan.verifiedAt(_:)`), and is left out when none was kept.
    private static func verifiedLine(_ facts: SetupFacts, time: (Date) -> String) -> String {
        guard facts.health == .verified, let at = SetupPlan.verifiedAt(facts) else {
            return "SignalLadder read its own test banner: verified."
        }
        return "SignalLadder read its own test banner: verified at \(time(at))."
    }

    /// What "Prove it can read" has read when health is not verified. It never says
    /// "verified", and it never gives the time of an earlier success as one.
    private static func notProvenStatus(_ facts: SetupFacts, time: (Date) -> String) -> String {
        switch facts.health {
        case .verified:
            // Not reached: a verified health is done. Said as the words say it, so that a
            // caller that asks anyway gets the truth.
            return verifiedLine(facts, time: time)
        case .unknown:
            guard let last = facts.lastVerifiedAt else { return proveNotYetRead }
            return "SignalLadder last read a test banner of its own at \(time(last)), and has no newer one."
        case .degraded, .blind:
            // What the health line says, in its words. Neither depends on an age, which
            // only a verified or an unread health does.
            return HealthTitle.text(for: facts.health, secondsSinceLastSuccessfulCanary: nil)
        }
    }

    // MARK: - What a step shows besides

    /// The lines a step shows under its status, for the state it is in.
    ///
    /// - **Prove it can read**, while not done: the first cause health gives and its
    ///   advice, which is what the health line carries and is not written again
    ///   (`HealthCause.advice`); and for a health that is a problem and names no cause,
    ///   the body the health banner gives it (`SelfNotification.fallbackBody`), never
    ///   "still checking", which is said only of a health that has not been read.
    /// - **Notifications**: what to do, for the fact read.
    /// - **First rule**: the practice notification while nothing has arrived, with the caution
    ///   that a rule made from it is for practice only (`practiceCaution`), or how many apps
    ///   banners were read from and what to make the rule from. The names are in
    ///   `StepWords.apps`.
    /// - **Keep it running**: what the box does where it is shown, and, while the item is
    ///   not on, that SignalLadder may not start again after a restart or log out, in the
    ///   words the on-call finding uses (`OnCallText.loginItemMayNotStart`). It does not
    ///   say that a restart ends on-call mode as a fact, since what was read is only that
    ///   macOS does not report the item as enabled.
    public static func detail(for step: SetupStep, facts: SetupFacts) -> [String] {
        let state = SetupPlan.state(of: step, in: facts)
        switch step {
        case .notifications:
            guard state == .outstanding else { return [] }
            return notificationsDetail(facts.notifications)
        case .proveItCanRead:
            guard state == .outstanding || state == .skipped else { return [] }
            if let cause = SetupPlan.unverifiedCause(for: facts.health) { return [cause.advice] }
            return facts.health.isAlarming ? [SelfNotification.fallbackBody] : []
        case .firstRule:
            guard state == .outstanding else { return [] }
            return firstRuleDetail(facts)
        case .keepItRunning:
            guard state != .done(.fact) else { return [] }
            var lines: [String] = []
            if SetupPlan.loginItemBox(for: facts.loginItem).isShown { lines.append(boxExplanation) }
            if !facts.loginItem.isOn { lines.append(OnCallText.loginItemMayNotStart) }
            return lines
        case .howItWorks, .accessibility, .muteSourceApp, .focus:
            return []
        }
    }

    private static func notificationsDetail(_ notifications: SetupFacts.Notifications?) -> [String] {
        guard let notifications else { return [] }
        switch notifications.permission {
        case .notAsked: return [askedOnlyOnPress]
        case .denied: return [HealthCause.notificationPermissionDenied.advice]
        case .allowed: return notifications.wouldDisplay ? [] : [notificationsBannerAdvice]
        }
    }

    private static func firstRuleDetail(_ facts: SetupFacts) -> [String] {
        guard facts.anythingCaptured else { return [practiceLead, practiceCaution] }
        let names = appNames(facts.capturedAppNames)
        return [names.isEmpty ? bannersWithoutNames : appsReadLine(count: names.count)]
    }

    /// The apps a step lists: each once, ignoring case and accents as rules compare them,
    /// in the order they were first seen, and none blank. Names only, never a title or a
    /// body.
    static func appNames(_ names: [String]) -> [String] {
        MuteWalkthrough.unique(names)
    }

    // MARK: - A step's buttons

    /// The buttons a step shows, in the order they are shown, for the state it is in.
    ///
    /// A step that is done, or has nothing to do yet, has Continue. A step that is
    /// outstanding has what it needs: Accessibility asks, opens its pane and checks again;
    /// notifications ask where a request can still show a dialog, and otherwise open
    /// SignalLadder's notification settings; "Prove it can read" checks again, opens the
    /// pane its cause points to, and offers "Continue without verifying"; the first rule
    /// is made from a notification, or its file is opened in a text editor where it
    /// cannot be written here; muting and the Focus are confirmed by the user; and the last
    /// step has Continue and Skip, and for a login item the system has switched off, a
    /// button that opens Login Items before them. Every step has at least one in every
    /// state it can be in.
    public static func buttons(for step: SetupStep, facts: SetupFacts) -> [StepButton] {
        actions(for: step, facts: facts).map { StepButton(action: $0, label: label(for: $0)) }
    }

    private static func actions(for step: SetupStep, facts: SetupFacts) -> [ButtonAction] {
        switch SetupPlan.state(of: step, in: facts) {
        case .done, .notApplicable: return [.continueOn]
        case .unknown: return [.checkAgain]
        case .blocked: return [.openRulesFile, .checkAgain]
        case .skipped: return step == .proveItCanRead ? [.checkAgain, .continueOn] : outstandingActions(step, facts: facts)
        case .outstanding: return outstandingActions(step, facts: facts)
        }
    }

    private static func outstandingActions(_ step: SetupStep, facts: SetupFacts) -> [ButtonAction] {
        switch step {
        case .howItWorks:
            return [.continueOn]
        case .accessibility:
            return [.allowAccessibility, .openAccessibilitySettings, .checkAgain]
        case .notifications:
            if facts.notifications?.permission == .notAsked { return [.allowNotifications, .checkAgain] }
            return [.openNotificationSettings, .checkAgain]
        case .proveItCanRead:
            // The pane the cause points to, as the menu's advice line opens it: delivery
            // faults to the notification settings, capture faults to Accessibility.
            var actions: [ButtonAction] = [.checkAgain]
            if let cause = SetupPlan.unverifiedCause(for: facts.health) {
                actions.append(cause.isDeliveryFault ? .openNotificationSettings : .openAccessibilitySettings)
            }
            actions.append(.continueWithoutVerifying)
            return actions
        case .firstRule:
            return facts.anythingCaptured ? [.makeRule] : [.checkAgain]
        case .muteSourceApp:
            return [.confirmMuted, .openAppNotificationSettings]
        case .focus:
            return [.openFocusSettings, .confirmFocus]
        case .keepItRunning:
            // For an item the system has switched off, the place it is switched back on: the
            // button Settings and the on-call finding carry for it, which only opens a pane.
            if facts.loginItem == .switchedOffInSystemSettings { return [.openLoginItems, .continueOn, .skip] }
            return [.continueOn, .skip]
        }
    }

    // MARK: - A whole step

    /// Everything a step shows, made from the facts, so that the window decides none of
    /// it (Ruling 10) and a test can read every line a step can show.
    public struct StepWords: Equatable, Sendable {
        public let step: SetupStep
        public let title: String
        /// What the step says before it asks (`why(for:)`).
        public let why: [String]
        /// What a step that is done rests on, in words (`basis(of:)`), and nil otherwise.
        public let basis: String?
        /// What it says it has read, or the user said (`status(for:facts:time:)`).
        public let status: String
        /// The lines under the status (`detail(for:facts:)`).
        public let detail: [String]
        /// Text for the user to select, and never to run or copy: the practice line, shown
        /// by the first rule's step while nothing has arrived.
        public let selectable: String?
        /// The app names the step lists, for the user to choose from or act on, and in no
        /// sentence: the apps banners were read from while nothing is made of them, in
        /// step 4, and the apps to mute, in step 5. Names only, never a title or a body.
        public let apps: [String]
        /// The label of the last step's box, only where the plan shows it
        /// (`SetupPlan.loginItemBox(for:)`), ticked to start with.
        public let tickBox: String?
        public let buttons: [StepButton]

        /// Every line of words the step holds, each one for scanning: the title, what it
        /// says before it asks, what it rests on, its status, its detail, what it gives to
        /// select, the label of its box and its buttons. The app names in `apps` are the
        /// one thing left out, since they are data and not words the step says.
        public var lines: [String] {
            var result: [String] = [title]
            result += why
            if let basis { result.append(basis) }
            result.append(status)
            result += detail
            if let selectable { result.append(selectable) }
            if let tickBox { result.append(tickBox) }
            result += buttons.map(\.label)
            return result
        }
    }

    /// Everything the step shows now.
    ///
    /// - Parameter time: how a moment is shown, as the menu's other lines show one
    ///   ("14:02").
    public static func words(for step: SetupStep, facts: SetupFacts, time: (Date) -> String) -> StepWords {
        let state = SetupPlan.state(of: step, in: facts)
        var selectable: String?
        var apps: [String] = []
        switch step {
        case .firstRule:
            if state == .outstanding {
                if facts.anythingCaptured { apps = appNames(facts.capturedAppNames) } else { selectable = practiceCommand }
            }
        case .muteSourceApp:
            if state != .notApplicable { apps = appNames(facts.appsToMute) }
        case .howItWorks, .accessibility, .notifications, .proveItCanRead, .focus, .keepItRunning:
            break
        }
        let box = step == .keepItRunning && SetupPlan.loginItemBox(for: facts.loginItem).isShown
        return StepWords(step: step, title: title(for: step), why: why(for: step), basis: basis(of: state),
                         status: status(for: step, facts: facts, time: time),
                         detail: detail(for: step, facts: facts), selectable: selectable, apps: apps,
                         tickBox: box ? SettingsText.launchAtLoginSwitch : nil,
                         buttons: buttons(for: step, facts: facts))
    }

    // MARK: - The summary

    /// Heads the summary.
    public static let summaryTitle = "Where setup stands"
    /// Heads what SignalLadder read.
    public static let summaryReadHeading = "What SignalLadder read"
    /// Heads what is the user's word.
    public static let summaryWordHeading = basisYourWord

    /// The steps whose lines the summary gives as read, and the two it gives as the
    /// user's word. The introduction is in neither: it is not something the app knows.
    static let readSteps: [SetupStep] = [.accessibility, .notifications, .proveItCanRead, .firstRule, .keepItRunning]
    static let wordSteps: [SetupStep] = [.muteSourceApp, .focus]

    /// The summary's line on on-call mode, with Launch at login on or off exactly as the
    /// fact says: on only for an item the system reports enabled
    /// (`LaunchAtLogin.State.isOn`), and off for every other state. Where it is off the
    /// line adds that SignalLadder may not start again after a restart or log out, which
    /// is what the on-call finding says (Ruling 9, `OnCallText.loginItemMayNotStart`).
    public static func onCallLine(loginItem: LaunchAtLogin.State) -> String {
        let line = "When your shift starts: \(OnCallText.menuTitle) in the menu. It works only while SignalLadder is running, and \(SettingsText.launchAtLoginSwitch) is \(loginItem.isOn ? "on" : "off")."
        return loginItem.isOn ? line : "\(line) \(OnCallText.loginItemMayNotStart)"
    }

    /// The summary's line on snooze.
    public static let snoozeLine = "Before a meeting: \(SnoozeText.menuTitle) in the menu; it quiets only the rules you have ticked."

    /// The summary the guide ends on (M5 plan, Ruling 16): what SignalLadder read, kept
    /// apart from what is the user's word (muting and the Focus), then one line each on
    /// on-call mode and on snooze.
    public struct Summary: Equatable, Sendable {
        public let title: String
        public let readHeading: String
        /// The lines SignalLadder read, in the plan's order.
        public let read: [String]
        public let wordHeading: String
        /// The lines that are the user's word, which nothing can check.
        public let word: [String]
        public let onCall: String
        public let snooze: String
        public let buttons: [StepButton]

        /// Every line of words the summary holds, for scanning.
        public var lines: [String] {
            var result: [String] = [title, readHeading]
            result += read
            result.append(wordHeading)
            result += word
            result += [onCall, snooze]
            result += buttons.map(\.label)
            return result
        }
    }

    /// The summary for the facts.
    ///
    /// - Parameter time: how a moment is shown, as the menu's other lines show one
    ///   ("14:02").
    public static func summary(_ facts: SetupFacts, time: (Date) -> String) -> Summary {
        Summary(title: summaryTitle, readHeading: summaryReadHeading,
                read: readSteps.map { status(for: $0, facts: facts, time: time) },
                wordHeading: summaryWordHeading,
                word: wordSteps.map { status(for: $0, facts: facts, time: time) },
                onCall: onCallLine(loginItem: facts.loginItem), snooze: snoozeLine,
                buttons: [StepButton(action: .finish, label: label(for: .finish))])
    }
}
