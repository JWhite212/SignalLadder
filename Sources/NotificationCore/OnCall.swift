// Sources/NotificationCore/OnCall.swift
import Foundation

/// Whether the user is on call, and since when (M5 plan, Ruling 7, O4).
///
/// The state is one saved date. A key that is there means on and one that is
/// not means off, so the state cannot disagree with itself as a Boolean beside
/// a date could, and it gives the menu an honest "since Mon 09:00". It never
/// expires: someone still on call at the end of a long shift is not switched
/// off by a timer.
///
/// What is saved may be anything, since a preferences file can be edited, and a
/// value that cannot be read as a time reads as on with no time known. The app
/// fails towards alerting, as it does elsewhere: a switch that may have been on
/// is not read as off.
public enum OnCallState: Equatable, Sendable {
    case off
    /// On. `since` is nil when something was saved and it could not be read as
    /// a time, which is on, since when is not known.
    case on(since: Date?)

    /// The key the date is saved under, in seconds since 1970. The app target
    /// reads and writes it and holds no word of its own for it.
    public static let storageKey = "onCallSince"

    /// Reads what the preferences gave for `storageKey`, which may be anything.
    ///
    /// - Absent is off.
    /// - A finite number, not negative, is on since that time, and never since
    ///   a time after `now`: a clock set back, or a value from the future,
    ///   reads as since now, so the menu cannot say the user went on call
    ///   tomorrow.
    /// - Anything else is on with no time known: a string, a Boolean, a date
    ///   or a list, and a number that is negative, infinite or not a number.
    public init(stored: Any?, now: Date) {
        guard let stored else {
            self = .off
            return
        }
        guard let seconds = Self.seconds(in: stored) else {
            self = .on(since: nil)
            return
        }
        self = .on(since: min(Date(timeIntervalSince1970: seconds), now))
    }

    /// A number as the preferences hand one back, or as Swift boxes one. A
    /// Boolean is not a number here: it reads as 1 or 0, which would be a time
    /// in the first second of 1970.
    private static func seconds(in stored: Any) -> TimeInterval? {
        guard let number = stored as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let seconds = number.doubleValue
        return seconds.isFinite && seconds >= 0 ? seconds : nil
    }

    public var isOn: Bool {
        if case .on = self { return true }
        return false
    }

    /// When it was switched on, if it is on and that is known.
    public var since: Date? {
        if case .on(let since) = self { return since }
        return nil
    }

    /// What saving this state does to the preferences.
    public enum Write: Equatable, Sendable {
        /// Take the key out, which is off. Off stores nothing.
        case remove
        /// Save the time, in seconds since 1970.
        case set(TimeInterval)
        /// Leave the key as it is. On with no time known has no time to save,
        /// and what is there is what made it on: removing it would switch the
        /// mode off, and a time made up for it would say what nobody knows.
        case keep
    }

    public var write: Write {
        switch self {
        case .off: return .remove
        case .on(let since?): return .set(since.timeIntervalSince1970)
        case .on(nil): return .keep
        }
    }
}

/// What the app does when the user switches on-call mode on or off, as an
/// ordered list the app carries out and decides nothing about (M5 plan,
/// Ruling 10). The list is the tested part: what comes in it, what does not,
/// and in what order.
///
/// The effects have no step that touches an escalation, so leaving the ones
/// already running alone (Ruling 20) is a property of the type.
public enum OnCallSwitch {
    public enum Effect: CaseIterable, Equatable, Sendable {
        /// Save the new state, so that it outlives a relaunch.
        case save
        /// Arm the self-test timer again, at the interval of the state just
        /// saved. Always after `save`: the interval is read from the state.
        case rearmSelfTestTimer
        /// Forget a retry that is waiting, and its back-off, because a
        /// self-test is run at once in its place (Ruling 8).
        case cancelPendingRetry
        /// Forget what the health alarm remembers, so that a fault already
        /// standing sounds for someone who has just said they are on call.
        /// Always before the self-test, whose report is the first to ask it.
        case resetHealthAlarm
        /// Hold the Mac awake against idle sleep, with the hold that on-call
        /// mode keeps for itself (O7). It is not the hold an escalation takes
        /// while a tier is to fire: that one ends with the escalation, and this
        /// one lasts as long as the mode. Asking for it again changes nothing.
        /// Always before the self-test, which is awaited, so that the hold does
        /// not wait on a banner.
        case holdAwake
        /// Let go of that hold, and of no other: what an escalation holds is
        /// its own, and is let go of when its last tier has fired.
        case releaseAwake
        /// Draw the menu and the icon from the state just saved, so that the switch
        /// shows at once. Turning on does it before the self-test, which is awaited
        /// and takes seconds in which the user would otherwise see a menu and an
        /// icon that say nothing happened; it comes after the hold, so that the menu
        /// says what is being held. Turning off does it last, after the hold is let
        /// go of, since no self-test is run to end in a rebuild.
        case rebuildMenuAndIcon
        /// Run a self-test now, with the follow-up two minutes later.
        case runSelfTestNow
        /// Forget what `OnCallWatch` remembers. Turning on does it so that a
        /// finding already standing sounds for someone who has just said they
        /// are on call, before the self-test whose report is the first to be
        /// watched; turning off does it so that switching on afterwards sounds
        /// for a finding that is still standing.
        case resetWatch
        /// Ask `OnCallCheck.shouldOpenWindow` and open the check window if it
        /// says yes. Once, and only after the self-test that turning on started
        /// has returned, and only if the mode is still on then: a check made
        /// before it would say that nothing had been verified, and one made for a
        /// mode switched off again in the meantime would open a window nobody
        /// asked for. After that the window is opened by `OnCallWatch`.
        case openCheckWindowIfUrgent
        /// Watch the findings, as every health refresh and every reload does,
        /// now that the self-test has told what it can, if the mode is still on.
        case evaluateWatch

        /// Whether carrying it out waits, so that the user can switch the mode
        /// again before it returns. Only the self-test does: it waits on a banner.
        public var isAwaited: Bool { self == .runSelfTestNow }
    }

    /// - Turning on: the state is saved, the timer is armed at the on-call
    ///   interval, a pending retry goes, the health alarm and the watch start
    ///   afresh, the Mac is held awake, the menu and the icon say so, and a
    ///   self-test runs at once, which takes the retry's place. When it returns,
    ///   if the mode is still on, the check window opens if a finding is urgent
    ///   and the watch looks at the findings.
    /// - Turning off: the state is saved, the timer is armed at the steady
    ///   interval, the hold is let go, the watch is cleared and the menu and the
    ///   icon say so. A pending retry is kept and no self-test is run, so a
    ///   failed self-test's promise to retry in a minute still holds, and the
    ///   alarm's state is left alone (Ruling 8).
    public static func effects(turningOn: Bool) -> [Effect] {
        turningOn
            ? [.save, .rearmSelfTestTimer, .cancelPendingRetry, .resetHealthAlarm, .resetWatch, .holdAwake,
               .rebuildMenuAndIcon, .runSelfTestNow, .openCheckWindowIfUrgent, .evaluateWatch]
            : [.save, .rearmSelfTestTimer, .releaseAwake, .resetWatch, .rebuildMenuAndIcon]
    }

    /// What is carried out before the awaited effect returns, that effect last:
    /// the whole list when none is awaited. Derived from `effects(turningOn:)`, so
    /// the two halves cannot disagree with it about what comes in which order.
    public static func effectsUntilSelfTestReturns(turningOn: Bool) -> [Effect] {
        let all = effects(turningOn: turningOn)
        guard let awaited = all.firstIndex(where: \.isAwaited) else { return all }
        return Array(all[...awaited])
    }

    /// What waits for the awaited effect to return, given whether on-call mode is
    /// on at that moment, which is read after the wait and not before it: the
    /// self-test takes seconds, and the user can switch the mode off in them. A
    /// check window opened and a watch begun for a mode that is off again would
    /// be opened and begun for nothing the user asked for, so nothing that waited
    /// runs unless the mode is still on.
    public static func effectsAfterSelfTestReturns(turningOn: Bool, stillOn: Bool) -> [Effect] {
        guard stillOn else { return [] }
        let all = effects(turningOn: turningOn)
        guard let awaited = all.firstIndex(where: \.isAwaited) else { return [] }
        return Array(all[(awaited + 1)...])
    }

    /// What the app does at launch with the state it restored, before capture
    /// starts. Nothing is saved, armed or run: the timer is first armed at the
    /// restored state's interval, and the self-test at launch is the one every
    /// launch makes. Only the hold is not already in place, since it is taken
    /// when the mode is switched on and nothing has switched it on in this run.
    public enum LaunchEffect: Equatable, Sendable {
        /// Hold the Mac awake, as `Effect.holdAwake` does.
        case holdAwake
    }

    /// A restored state that is on holds the Mac awake from launch, one whose
    /// time could not be read included: it reads as on (Ruling 7), and a Mac
    /// that idle-sleeps while someone is on call captures nothing. Off holds
    /// nothing.
    public static func launchEffects(restored: OnCallState) -> [LaunchEffect] {
        restored.isOn ? [.holdAwake] : []
    }
}

/// The words on-call mode puts on the menu, in one place where they are tested
/// (M5 plan, Ruling 18). Each constant is declared on one line, as
/// `public static let NAME = "TEXT"`, which is the shape the harness reads.
public enum OnCallText {
    /// The item that switches the mode, checked while it is on.
    public static let menuTitle = "On Call"
    /// The item that opens the check window while the mode is on.
    public static let checkItemTitle = "Show On-Call Check…"
    /// What the line under the On Call item begins with, whatever follows.
    public static let sinceStem = "On call since"
    /// In place of the moment when what was saved could not be read as one.
    public static let sinceUnknown = "a time that could not be read"
    /// Added to the line while self-tests are running.
    public static let cadenceEnding = " — self-test every 5 min"
    /// Added to the line while a self-test cannot run, which the health line
    /// says why.
    public static let pausedEnding = " — self-tests are paused, see the health line"
    /// Under the since-line while the hold against sleep is held (O7). It says
    /// what the hold costs, and what it does not do: a closed lid still sleeps the
    /// Mac. A menu line, short enough to sit beside the menu's others, so it does
    /// not say "while you are on call", which the line above it already has.
    public static let awakeLine = "Keeping this Mac awake: costs battery; a closed lid still sleeps it"

    // MARK: The check window

    /// The one button of the check window: it runs a self-test now and looks at
    /// everything again.
    public static let checkButton = "Check Now"
    /// Beneath the button, since a self-test is a banner on whatever the screen
    /// shows.
    public static let checkButtonNote = "Runs a self-test, which shows a banner, and checks everything again."
    /// The window's heading while no finding is urgent. The two advisories that
    /// always stand are listed beneath it, and are not urgent.
    public static let nothingUrgent = "Nothing urgent"
    public static let oneUrgent = "1 thing needs your attention"

    public static func manyUrgent(_ count: Int) -> String { "\(count) things need your attention" }

    // MARK: The findings

    /// The check asks whether the app is ready, and capture that no self-test has
    /// confirmed yet is not.
    public static let notVerifiedYet = "Capture has not been verified yet"
    /// SignalLadder's own beeps follow Alert volume, which is not the output's.
    public static let beepsInaudible = "SignalLadder's beeps cannot be heard: Alert volume is at zero. They follow Alert volume in System Settings › Sound, not the output volume"
    public static let noRulesFileUnreadable = "No rules are in effect: the rules file could not be read"
    public static let noRulesFileNewer = "No rules are in effect: the rules file was written by a newer SignalLadder"
    public static let noRuleEnabled = "No rule is enabled, so nothing will alert you"
    public static let noSoundOrShortcut = "No enabled rule makes a sound or runs a Shortcut, so a match will only show the panel"
    public static let loginItemOff = "SignalLadder will not start again after a restart or log out unless you added it to Login Items yourself, which it cannot check"
    public static let loginItemByHand = "SignalLadder cannot check that the Login Items entry you added is still there"
    /// What a Focus does and that it cannot be read, to which the workaround is
    /// added. The first sentence is the mute walkthrough's own, so the advice is
    /// written once.
    public static let focusCannotRead = "SignalLadder cannot read whether one is on."
    public static let focusWorkaround = "Allowing the source app to break through a Focus keeps its banners showing."
    public static let sleepAdvisory = "A Mac that sleeps, with its lid closed or put to sleep by hand, captures nothing, and SignalLadder cannot wake it"

    public static func rulesNotInEffect(count: Int) -> String {
        count == 1 ? "1 rule is not in effect, so it will not alert you"
            : "\(count) rules are not in effect, so they will not alert you"
    }

    /// A count and never a name: a name can be a fragment parsed out of a banner.
    public static func unconfirmedMuting(count: Int) -> String {
        count == 1 ? "1 app not confirmed muted" : "\(count) apps not confirmed muted"
    }

    // MARK: The menu's short forms

    /// The menu is read at a glance and has no room for a paragraph: the Focus
    /// advisory is about 1,420 points wide in the menu's font, where the menu's
    /// other lines are about 450 at most. So it shows these forms of the findings
    /// whose sentences are longer, and the check window keeps the sentences
    /// themselves. Each is one line, no wider than the widest line the menu already
    /// shows (a test measures it, and they are 420 points or fewer here), says what
    /// the sentence says that matters at a glance and no more than it, and ends in
    /// `pointToCheck`, written out in full as every constant here is, where the
    /// window says something the form does not.
    public static let pointToCheck = "see On-Call Check"
    public static let beepsInaudibleMenu = "Alert volume is zero, so beeps are silent — see On-Call Check"
    public static let noSoundOrShortcutMenu = "A match only shows the panel: no rule sounds or runs a Shortcut"
    public static let loginItemOffMenu = "May not start after a restart or log out — see On-Call Check"
    public static let loginItemByHandMenu = "Cannot check that your Login Items entry is still there"
    public static let focusMenu = "A Focus hides banners and cannot be read — see On-Call Check"
    public static let sleepMenu = "A Mac that sleeps captures nothing; SignalLadder cannot wake it"

    /// What marks an urgent finding in the menu, which shows it as a line of text.
    public static let urgentMark = "⚠︎ "
    /// What marks an urgent finding for VoiceOver in the check window.
    public static let urgentSpoken = "Urgent: "

    // MARK: The check window's symbols

    /// Beside an urgent finding, and in the heading while one stands.
    public static let urgentSymbol = "exclamationmark.triangle.fill"
    /// Beside a finding that is not urgent.
    public static let advisorySymbol = "info.circle"
    /// In the heading while nothing is urgent: a bell, and no tick. Nothing urgent
    /// is not "all is well" for an app that checks only what it can read.
    public static let nothingUrgentSymbol = "bell.badge"
}

/// What the rules in effect can do, as three counts and nothing else: never a
/// name, since a name belongs to the user's rules and is nothing the check says.
public struct RuleReach: Equatable, Sendable {
    /// Rules in effect that are switched on.
    public let enabled: Int
    /// Of those, the ones that make a sound or speak, on any step.
    public let alertingAloud: Int
    /// Of those, the ones whose last step is a Shortcut.
    public let withShortcut: Int

    public init(enabled: Int, alertingAloud: Int, withShortcut: Int) {
        self.enabled = enabled
        self.alertingAloud = alertingAloud
        self.withShortcut = withShortcut
    }

    /// - Parameter rules: the rules in effect.
    public init(rules: [Rule]) {
        enabled = rules.filter(\.isEnabled).count
        alertingAloud = rules.filter(\.alertsAloud).count
        withShortcut = rules.filter { $0.isEnabled && $0.escalation?.tier4?.action.shortcutName != nil }.count
    }
}

/// What the app can say about whether the user is ready to be reached, as a list
/// of findings (M5 plan, Ruling 9). The check window lists every one of them, the
/// menu lists those its standard lines do not already carry, and `OnCallWatch`
/// sounds for those the health alarm cannot see.
///
/// Limited to what the app can read. A Focus cannot be read, so no finding says
/// one is on or off, and the standing advisory says it cannot be read; a sleeping
/// Mac captures nothing, which needs no reading, and its advisory says what sleep
/// does and claims that none happened. Muting is the user's word, so it says "not
/// confirmed" and counts the apps and never names one. No finding holds what a
/// notification said, or the name of a rule: each is a sentence or a count.
public enum OnCallCheck {
    /// Everything the check reads, handed over by the app target, which reads each
    /// fact and decides nothing about it. None has a default, so a place that
    /// forgets one does not compile.
    public struct Inputs: Equatable, Sendable {
        /// The health, whose first cause is what the health finding says.
        public var health: CaptureHealth
        /// The apps on the mute checklist that are not yet confirmed
        /// (`MuteChecklist.unconfirmed(among:)`), which is names. The check
        /// reduces them to a count, so it is this function that never says one.
        public var unconfirmedMutedApps: [String]
        /// Whether the output reports itself muted or at zero volume now.
        public var outputSilent: Bool
        /// Alert volume, a number or nil when it could not be read.
        public var alertVolume: Double?
        /// What the rules in effect can do.
        public var reach: RuleReach
        /// What the loader made of the rules file, from which the check counts
        /// the rules it did not put in effect.
        public var ruleStatus: RuleStoreStatus
        /// The rules in effect that name a Shortcut the Shortcuts app does not
        /// list, reduced to a count.
        public var shortcutWarnings: [RuleWarning]
        /// Whether SignalLadder starts at login, nil when nothing has said. It is
        /// nil until the commit that adds the login item, so until then the app
        /// says nothing about either.
        public var startsAtLogin: Bool?
        /// Whether the user said they added it to Login Items themselves, nil
        /// when they have not been asked.
        public var loginItemByHand: Bool?

        public init(health: CaptureHealth, unconfirmedMutedApps: [String], outputSilent: Bool, alertVolume: Double?,
                    reach: RuleReach, ruleStatus: RuleStoreStatus, shortcutWarnings: [RuleWarning],
                    startsAtLogin: Bool?, loginItemByHand: Bool?) {
            self.health = health
            self.unconfirmedMutedApps = unconfirmedMutedApps
            self.outputSilent = outputSilent
            self.alertVolume = alertVolume
            self.reach = reach
            self.ruleStatus = ruleStatus
            self.shortcutWarnings = shortcutWarnings
            self.startsAtLogin = startsAtLogin
            self.loginItemByHand = loginItemByHand
        }
    }

    public struct Finding: Equatable, Sendable {
        /// What a finding is about, in the order they are listed.
        public enum Kind: CaseIterable, Hashable, Sendable {
            /// Capture is degraded or blind, in the words of its first cause.
            case health
            /// No self-test has confirmed capture.
            case notVerifiedYet
            /// The output is muted or at zero volume, and a rule sounds.
            case outputMuted
            /// Alert volume is at zero, so SignalLadder's own beeps are silent.
            case beepsInaudible
            /// Some rules were not put in effect, counted.
            case rulesNotInEffect
            /// The whole rules file is not in effect.
            case rulesFileNotInEffect
            /// No rule is enabled, and none was refused.
            case noRuleEnabled
            /// Rules are enabled and none makes a sound or runs a Shortcut.
            case noSoundOrShortcut
            /// Shortcut names the Shortcuts app does not list, counted.
            case shortcutNotFound
            /// SignalLadder does not start at login.
            case loginItemOff
            /// The user says they added it to Login Items; the app cannot check.
            case loginItemByHand
            /// Apps not confirmed muted, counted.
            case unconfirmedMuting
            /// A Focus hides banners and cannot be read.
            case focus
            /// A Mac that sleeps captures nothing.
            case sleep

            /// Urgent means a page may not arrive, or the check is asking whether
            /// the app is ready and it is not. The advisories are never urgent: a
            /// Focus and a sleep are not faults the app can see, and a login item
            /// the user says they added cannot be checked.
            public var isUrgent: Bool {
                switch self {
                case .health, .notVerifiedYet, .outputMuted, .beepsInaudible, .rulesNotInEffect,
                     .rulesFileNotInEffect, .noRuleEnabled, .shortcutNotFound, .loginItemOff, .unconfirmedMuting:
                    return true
                case .noSoundOrShortcut, .loginItemByHand, .focus, .sleep:
                    return false
                }
            }

            /// Whether the menu's own lines already say it, so that the menu does
            /// not say it twice: the health line and its cause, which includes
            /// "not verified yet" since that line reads Checking… or Unverified;
            /// the muted-output line, the rules status and its warnings, and the
            /// mute walkthrough's own line.
            var isAlreadyInTheMenu: Bool {
                switch self {
                case .health, .notVerifiedYet, .outputMuted, .rulesNotInEffect, .rulesFileNotInEffect,
                     .shortcutNotFound, .unconfirmedMuting:
                    return true
                case .beepsInaudible, .noRuleEnabled, .noSoundOrShortcut, .loginItemOff, .loginItemByHand,
                     .focus, .sleep:
                    return false
                }
            }
        }

        public let kind: Kind
        /// The words, without a mark.
        public let text: String
        /// How many, for the findings that are counted; nil for the rest.
        public let count: Int?

        public init(kind: Kind, text: String, count: Int? = nil) {
            self.kind = kind
            self.text = text
            self.count = count
        }

        public var isUrgent: Bool { kind.isUrgent }

        /// The words the menu shows for it: the short form of a finding whose
        /// sentence would make the menu far wider than its other lines, and the
        /// sentence itself for the rest. The check window shows `text`. No default
        /// arm, so a kind added later has to say which it is.
        public var menuText: String {
            switch kind {
            case .beepsInaudible: return OnCallText.beepsInaudibleMenu
            case .noSoundOrShortcut: return OnCallText.noSoundOrShortcutMenu
            case .loginItemOff: return OnCallText.loginItemOffMenu
            case .loginItemByHand: return OnCallText.loginItemByHandMenu
            case .focus: return OnCallText.focusMenu
            case .sleep: return OnCallText.sleepMenu
            case .health, .notVerifiedYet, .outputMuted, .rulesNotInEffect, .rulesFileNotInEffect, .noRuleEnabled,
                 .shortcutNotFound, .unconfirmedMuting:
                return text
            }
        }

        /// The line as the menu shows it: an urgent one carries the mark the
        /// menu's other warnings carry.
        public var menuTitle: String { isUrgent ? OnCallText.urgentMark + menuText : menuText }

        /// What VoiceOver reads for the line in the check window, where urgency is
        /// shown by an icon that VoiceOver does not read.
        public var spokenText: String { isUrgent ? OnCallText.urgentSpoken + text : text }

        /// The symbol beside the line in the check window.
        public var symbol: String { isUrgent ? OnCallText.urgentSymbol : OnCallText.advisorySymbol }
    }

    /// Every finding, in the order they are listed: health first, then the output,
    /// the beeps, the rules, the Shortcuts, the login item, the muting, and last
    /// the two standing advisories.
    public static func findings(_ inputs: Inputs) -> [Finding] {
        var found: [Finding] = []

        switch inputs.health {
        case .verified:
            break
        case .unknown:
            found.append(Finding(kind: .notVerifiedYet, text: OnCallText.notVerifiedYet))
        case .degraded(let causes), .blind(let causes):
            found.append(Finding(kind: .health, text: causes.first?.advice ?? SelfNotification.fallbackBody))
        }

        // A muted output is only a fault for someone with a rule that sounds:
        // silence is what a user with none has chosen.
        if inputs.reach.alertingAloud > 0, inputs.outputSilent {
            found.append(Finding(kind: .outputMuted, text: AlertMenuText.outputSilentSentence))
        }

        // The beeps are the app's own channel and not a rule's, so this is urgent
        // whether or not a rule sounds.
        if BeepAudibility.isSilent(alertVolume: inputs.alertVolume) {
            found.append(Finding(kind: .beepsInaudible, text: OnCallText.beepsInaudible))
        }

        switch inputs.ruleStatus {
        case .unreadable:
            found.append(Finding(kind: .rulesFileNotInEffect, text: OnCallText.noRulesFileUnreadable))
        case .unsupportedVersion:
            found.append(Finding(kind: .rulesFileNotInEffect, text: OnCallText.noRulesFileNewer))
        case .loadedWithProblems(_, _, let rejected):
            if !rejected.isEmpty {
                found.append(Finding(kind: .rulesNotInEffect, text: OnCallText.rulesNotInEffect(count: rejected.count),
                                     count: rejected.count))
            }
        case .noRulesFile, .loaded:
            break
        }
        if Self.noRuleIsEnabled(in: inputs.ruleStatus) {
            found.append(Finding(kind: .noRuleEnabled, text: OnCallText.noRuleEnabled))
        }
        if inputs.reach.enabled > 0, inputs.reach.alertingAloud == 0, inputs.reach.withShortcut == 0 {
            found.append(Finding(kind: .noSoundOrShortcut, text: OnCallText.noSoundOrShortcut))
        }

        let warned = inputs.shortcutWarnings.count
        if let sentence = RuleWarnings.summarySentence(count: warned) {
            found.append(Finding(kind: .shortcutNotFound, text: sentence, count: warned))
        }

        if inputs.startsAtLogin == false {
            if inputs.loginItemByHand == true {
                found.append(Finding(kind: .loginItemByHand, text: OnCallText.loginItemByHand))
            } else {
                found.append(Finding(kind: .loginItemOff, text: OnCallText.loginItemOff))
            }
        }

        let unconfirmed = inputs.unconfirmedMutedApps.count
        if unconfirmed > 0 {
            found.append(Finding(kind: .unconfirmedMuting, text: OnCallText.unconfirmedMuting(count: unconfirmed),
                                 count: unconfirmed))
        }

        found.append(Finding(kind: .focus, text: Self.focusAdvisory))
        found.append(Finding(kind: .sleep, text: OnCallText.sleepAdvisory))
        return found
    }

    /// Whether the rules file is in effect with nothing refused and no rule is
    /// enabled in it: no file, an empty one, or every rule off. A refused rule is
    /// the finding before it, and a file not in effect is another.
    private static func noRuleIsEnabled(in status: RuleStoreStatus) -> Bool {
        switch status {
        case .noRulesFile: return true
        case .loaded(let enabled, _): return enabled == 0
        case .loadedWithProblems, .unreadable, .unsupportedVersion: return false
        }
    }

    /// The Focus advisory: the mute walkthrough's own sentence about what a Focus
    /// does, so the advice is written once, then that it cannot be read, and the
    /// workaround the first findings note records.
    static var focusAdvisory: String {
        (Array(MuteWalkthroughText.focus.prefix(2)) + [OnCallText.focusCannotRead, OnCallText.focusWorkaround])
            .joined(separator: " ")
    }

    /// The findings the menu adds beneath the since-line. The menu's standard
    /// lines already carry the health line and its cause, the muted output, the
    /// rules status and its warnings, and the mute count, so those are dropped
    /// and nothing is said twice.
    public static func menuLines(_ findings: [Finding]) -> [Finding] {
        findings.filter { !$0.kind.isAlreadyInTheMenu }
    }

    /// Every finding, urgent ones first and each group in the order it was found.
    public static func windowLines(_ findings: [Finding]) -> [Finding] {
        findings.filter(\.isUrgent) + findings.filter { !$0.isUrgent }
    }

    /// Whether any finding is urgent. It is the one answer behind whether the
    /// window opens at switch-on and how the window's heading looks, so the two
    /// cannot disagree, and the app target asks it and decides nothing of its own.
    public static func hasUrgent(_ findings: [Finding]) -> Bool {
        findings.contains(where: \.isUrgent)
    }

    /// Whether switching on opens the check window: any finding is urgent. Asked
    /// once, when the self-test that switching on started has returned.
    public static func shouldOpenWindow(_ findings: [Finding]) -> Bool {
        hasUrgent(findings)
    }

    /// The symbol in the window's heading: the urgent one while any finding is
    /// urgent, and a bell without a tick while none is.
    public static func headingSymbol(hasUrgent: Bool) -> String {
        hasUrgent ? OnCallText.urgentSymbol : OnCallText.nothingUrgentSymbol
    }

    /// The window's heading.
    public static func summary(_ findings: [Finding]) -> String {
        switch findings.filter(\.isUrgent).count {
        case 0: return OnCallText.nothingUrgent
        case 1: return OnCallText.oneUrgent
        case let many: return OnCallText.manyUrgent(many)
        }
    }
}
