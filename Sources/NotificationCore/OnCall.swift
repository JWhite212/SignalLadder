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
        PreferenceValue.seconds(stored)
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
/// already running alone (Ruling 20) is a property of the type. Nor has any step
/// a way to clear what a snooze held or to announce it: the one step that
/// touches a snooze ends it, and only in the list for turning on (O10).
public enum OnCallSwitch {
    public enum Effect: CaseIterable, Equatable, Sendable {
        /// Save the new state, so that it outlives a relaunch.
        case save
        /// End the snooze that is running, which turning the mode on does and
        /// nothing else does (M5 plan, O10): someone who says they are on call
        /// is relying on being told, and a snooze is the opposite. It keeps what
        /// the snooze held and announces nothing, since the user has just acted
        /// and is looking at the menu, which says "Snooze ended — you are on
        /// call"; the summary stays until the user dismisses it
        /// (`SnoozeController.end()`). In the list only when a snooze is active.
        /// Straight after `save`, so that the first thing the menu and the icon
        /// can be drawn from has the mode on and no snooze, and before every
        /// effect that waits: ending a snooze makes the app louder and never
        /// quieter, and nothing after it needs to be done first.
        case endSnooze
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

    /// - Turning on: the state is saved, the snooze that is running, if one is,
    ///   ends, the timer is armed at the on-call interval, a pending retry goes,
    ///   the health alarm and the watch start afresh, the Mac is held awake, the
    ///   menu and the icon say so, and a self-test runs at once, which takes the
    ///   retry's place. When it returns, if the mode is still on, the check
    ///   window opens if a finding is urgent and the watch looks at the findings.
    /// - Turning off: the state is saved, the timer is armed at the steady
    ///   interval, the hold is let go, the watch is cleared and the menu and the
    ///   icon say so. A pending retry is kept and no self-test is run, so a
    ///   failed self-test's promise to retry in a minute still holds, and the
    ///   alarm's state is left alone (Ruling 8). A snooze is never touched, so a
    ///   user who started one while on call and then leaves the mode keeps it.
    ///
    /// - Parameter snoozeActive: whether a snooze is running as the switch begins,
    ///   which the app reads once. It has no default, so that a place that forgets
    ///   it does not compile (Ruling 10), and it changes the list for turning on
    ///   only.
    public static func effects(turningOn: Bool, snoozeActive: Bool) -> [Effect] {
        guard turningOn else {
            return [.save, .rearmSelfTestTimer, .releaseAwake, .resetWatch, .rebuildMenuAndIcon]
        }
        var list: [Effect] = [.save]
        if snoozeActive { list.append(.endSnooze) }
        list += [.rearmSelfTestTimer, .cancelPendingRetry, .resetHealthAlarm, .resetWatch, .holdAwake,
                 .rebuildMenuAndIcon, .runSelfTestNow, .openCheckWindowIfUrgent, .evaluateWatch]
        return list
    }

    /// What is carried out before the awaited effect returns, that effect last:
    /// the whole list when none is awaited. Derived from
    /// `effects(turningOn:snoozeActive:)`, so the two halves cannot disagree with
    /// it about what comes in which order.
    public static func effectsUntilSelfTestReturns(turningOn: Bool, snoozeActive: Bool) -> [Effect] {
        let all = effects(turningOn: turningOn, snoozeActive: snoozeActive)
        guard let awaited = all.firstIndex(where: \.isAwaited) else { return all }
        return Array(all[...awaited])
    }

    /// What waits for the awaited effect to return, given whether on-call mode is
    /// on at that moment, which is read after the wait and not before it: the
    /// self-test takes seconds, and the user can switch the mode off in them. A
    /// check window opened and a watch begun for a mode that is off again would
    /// be opened and begun for nothing the user asked for, so nothing that waited
    /// runs unless the mode is still on.
    ///
    /// It takes the `snoozeActive` the first part was asked with, so that the two
    /// are made from the one list and the one input: the snooze ends before the
    /// wait, so what follows it is the same either way.
    public static func effectsAfterSelfTestReturns(turningOn: Bool, snoozeActive: Bool, stillOn: Bool) -> [Effect] {
        guard stillOn else { return [] }
        let all = effects(turningOn: turningOn, snoozeActive: snoozeActive)
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
    public static let cadenceEnding = " — self-test every \(HealthEvaluator.onCallSelfTestMinutes) min"
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
    /// The same two, and a file whose every rule that is on was refused, when a reload kept the rules
    /// that were in effect (`RuleStoreStatus.reloaded`).
    public static let earlierRulesFileUnreadable =
        "The rules file is not in effect: it could not be read, so the earlier rules still are"
    public static let earlierRulesFileNewer =
        "The rules file is not in effect: it was written by a newer SignalLadder, so the earlier rules still are"
    public static let earlierRulesEveryRuleRefused =
        "The rules file is not in effect: every rule in it that is on was refused, so the earlier rules still are"
    public static let noRuleEnabled = "No rule is enabled, so nothing will alert you"
    /// ⌃⌥⌘A could not be registered, in the window and, shorter, in the menu.
    /// No literal here begins with the menu's acknowledge stem, which the harness finds the
    /// Acknowledge item by (`HarnessConstantsTests`).
    public static let hotkeyNotRegistered = "The acknowledge hotkey ⌃⌥⌘A could not be set up, so pressing it does nothing: "
        + "acknowledge from the panel or the menu instead. Another app may be using the same keys."
    public static let hotkeyNotRegisteredMenu = "⌃⌥⌘A does nothing: acknowledge from the panel or the menu"
    public static let noSoundOrShortcut = "No enabled rule makes a sound or runs a Shortcut, so a match will only show the panel"
    /// What stands first in the login finding, whichever way macOS reports the item
    /// (M5 plan, Ruling 9): that SignalLadder may not start again once the Mac
    /// restarts or the user logs out, which is what an item that is not enabled
    /// costs. It says "may", because what was read is only that macOS does not report
    /// the item as enabled. A Login Items entry the user added by hand reads enabled
    /// on macOS 26.7.1 (measured on 2026-10-05), so there the finding does not wait
    /// on one, but that it does on macOS 14 and 15 was not seen, and an entry the
    /// status does not show would start the app all the same. So the consequence is
    /// not said as a fact, and the finding says nothing of an entry added by hand.
    /// "Will not" waits on Task 9 measuring those two.
    public static let loginItemMayNotStart = "SignalLadder may not start again after a restart or log out."
    /// What was read, for an item that is off, or that was read in a way no other
    /// sentence names: the form `LaunchAtLoginText.menuLine` has, that macOS does not
    /// report it as enabled, which is true of every status but enabled and no more
    /// than that.
    public static let loginItemNotEnabled = "macOS does not report Launch at login as enabled."
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

    /// The login finding's sentence, worded from what was read: that SignalLadder may
    /// not start again, then what the system said (M5 plan, Ruling 9, O12).
    ///
    /// - An item that can be switched on reads as macOS not reporting it as enabled,
    ///   which is all a status that is not enabled says, whether or not the user had
    ///   switched it on.
    /// - An item the system has switched off, or that waits for the user's approval,
    ///   says so in the words Settings uses (`SettingsText.switchedOffSentence`).
    /// - A copy that cannot register gives its reason and the move that fixes it
    ///   (`LaunchAtLoginText.reason(for:)`), since the finding has no button there.
    /// - `nil` is a finding made with no state read, and `.on` cannot stand beside a
    ///   status that is not enabled; both say what is true of every such status.
    ///
    /// No state is named that was not read, and none says the item is on.
    public static func loginItemOff(for state: LaunchAtLogin.State?) -> String {
        let read: String
        switch state {
        case .unavailable(let why)?: read = LaunchAtLoginText.reason(for: why)
        case .switchedOffInSystemSettings?: read = SettingsText.switchedOffSentence
        case .off?, .on?, nil: read = loginItemNotEnabled
        }
        return "\(loginItemMayNotStart) \(read)"
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
