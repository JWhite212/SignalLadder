// Sources/NotificationCore/OnCallCheck.swift
import Foundation

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
        /// What the loader warns about rules in effect: a Shortcut the Shortcuts
        /// app does not list, or a sound or voice that cannot be played. Each kind
        /// is reduced to a count of its own.
        public var ruleWarnings: [RuleWarning]
        /// Whether SignalLadder starts at login (`LaunchAtLogin.startsAtLogin(status:)`:
        /// true only for a status of enabled), nil when no status was read, as for a
        /// build of the menu that is never shown. The login finding appears when this
        /// is false, and for no other value.
        public var startsAtLogin: Bool?
        /// What Settings would show for the login item, made from the same status read
        /// as `startsAtLogin`: the finding takes its words and its button from it, and
        /// from nothing else (`OnCallText.loginItemOff(for:)`,
        /// `LaunchAtLogin.findingAction(for:)`). nil when no status was read.
        public var loginItem: LaunchAtLogin.State?

        /// Whether ⌃⌥⌘A was registered at launch. True by default, since only the app reads
        /// it, and a registration that failed is the one thing it adds (2026-10-16).
        public let acknowledgeHotkeyRegistered: Bool

        public init(health: CaptureHealth, unconfirmedMutedApps: [String], outputSilent: Bool, alertVolume: Double?,
                    reach: RuleReach, ruleStatus: RuleStoreStatus, ruleWarnings: [RuleWarning],
                    startsAtLogin: Bool?, loginItem: LaunchAtLogin.State?, acknowledgeHotkeyRegistered: Bool = true) {
            self.acknowledgeHotkeyRegistered = acknowledgeHotkeyRegistered
            self.health = health
            self.unconfirmedMutedApps = unconfirmedMutedApps
            self.outputSilent = outputSilent
            self.alertVolume = alertVolume
            self.reach = reach
            self.ruleStatus = ruleStatus
            self.ruleWarnings = ruleWarnings
            self.startsAtLogin = startsAtLogin
            self.loginItem = loginItem
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
            /// Rules with a sound or voice that cannot be played, counted. Each is
            /// in effect, and an alert of one that would make no sound plays the
            /// fallback sound, which may not be known for that rule's.
            case alertCannotPlay
            /// macOS does not report the login item as enabled, so nothing starts
            /// SignalLadder again after a restart or a log out. It carries the button
            /// the status allows, or the reason there is none (`Finding.action`).
            case loginItemOff
            /// Apps not confirmed muted, counted.
            case unconfirmedMuting
            /// ⌃⌥⌘A could not be registered, so it does nothing. An advisory: the panel and
            /// the menu still acknowledge.
            case hotkeyNotRegistered
            /// A Focus hides banners and cannot be read.
            case focus
            /// A Mac that sleeps captures nothing.
            case sleep

            /// Urgent means a page may not arrive, or the check is asking whether
            /// the app is ready and it is not. The advisories are never urgent: a
            /// Focus and a sleep are not faults the app can see.
            public var isUrgent: Bool {
                switch self {
                case .health, .notVerifiedYet, .outputMuted, .beepsInaudible, .rulesNotInEffect,
                     .rulesFileNotInEffect, .noRuleEnabled, .shortcutNotFound, .alertCannotPlay, .loginItemOff,
                     .unconfirmedMuting:
                    return true
                case .noSoundOrShortcut, .focus, .sleep, .hotkeyNotRegistered:
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
                     .shortcutNotFound, .alertCannotPlay, .unconfirmedMuting:
                    return true
                case .beepsInaudible, .noRuleEnabled, .noSoundOrShortcut, .loginItemOff, .focus, .sleep, .hotkeyNotRegistered:
                    return false
                }
            }
        }

        public let kind: Kind
        /// The words, without a mark.
        public let text: String
        /// How many, for the findings that are counted; nil for the rest.
        public let count: Int?
        /// The button the finding carries, which the user presses so that acting on it
        /// is one click and nothing is switched on silently (M5 plan, O12); nil for
        /// every finding that has none, which is every one but the login finding where
        /// the status allows something to press (`LaunchAtLogin.findingAction(for:)`).
        /// The check window shows it and the menu does not.
        public let action: LaunchAtLogin.Action?
        /// Where the finding's other button takes the user, for every finding but one that
        /// acts (`OnCallCheck.Destination`); nil where there is nowhere to send them.
        public let destination: Destination?

        public init(kind: Kind, text: String, count: Int? = nil, action: LaunchAtLogin.Action? = nil,
                    destination: Destination? = nil) {
            self.kind = kind
            self.text = text
            self.count = count
            self.action = action
            self.destination = destination
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
            case .focus: return OnCallText.focusMenu
            case .sleep: return OnCallText.sleepMenu
            case .hotkeyNotRegistered: return OnCallText.hotkeyNotRegisteredMenu
            case .health, .notVerifiedYet, .outputMuted, .rulesNotInEffect, .rulesFileNotInEffect, .noRuleEnabled,
                 .shortcutNotFound, .alertCannotPlay, .unconfirmedMuting:
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

    /// Every finding, in the order they are listed: health first, then the output
    /// and the beeps, the rules, the rule warnings, the login item, the muting, the
    /// acknowledge hotkey, and last the two standing advisories. Each step below is
    /// asked in that order, and every finding that does not act is then given the
    /// place it is fixed.
    public static func findings(_ inputs: Inputs) -> [Finding] {
        let found = healthFindings(inputs) + audibilityFindings(inputs) + ruleFindings(inputs)
            + ruleWarningFindings(inputs) + loginItemFindings(inputs) + mutingFindings(inputs)
            + hotkeyFindings(inputs) + standingAdvisories
        // One that acts keeps its own button alone.
        return found.map { finding in
            Finding(kind: finding.kind, text: finding.text, count: finding.count, action: finding.action,
                    destination: finding.action == nil ? Self.destination(of: finding.kind, health: inputs.health) : nil)
        }
    }

    private static func healthFindings(_ inputs: Inputs) -> [Finding] {
        switch inputs.health {
        case .verified:
            return []
        case .unknown:
            return [Finding(kind: .notVerifiedYet, text: OnCallText.notVerifiedYet)]
        case .degraded, .blind:
            // Never nil for a health that is a problem, a cause or none.
            return inputs.health.leadingAdvice.map { [Finding(kind: .health, text: $0)] } ?? []
        }
    }

    private static func audibilityFindings(_ inputs: Inputs) -> [Finding] {
        var found: [Finding] = []
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
        return found
    }

    private static func ruleFindings(_ inputs: Inputs) -> [Finding] {
        var found: [Finding] = []
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
        case .notReloaded(_, _, .unreadable):
            found.append(Finding(kind: .rulesFileNotInEffect, text: OnCallText.earlierRulesFileUnreadable))
        case .notReloaded(_, _, .unsupportedVersion):
            found.append(Finding(kind: .rulesFileNotInEffect, text: OnCallText.earlierRulesFileNewer))
        case .noRulesFile, .loaded:
            break
        }
        if Self.noRuleIsEnabled(in: inputs.ruleStatus) {
            found.append(Finding(kind: .noRuleEnabled, text: OnCallText.noRuleEnabled))
        }
        if inputs.reach.enabled > 0, inputs.reach.alertingAloud == 0, inputs.reach.withShortcut == 0 {
            found.append(Finding(kind: .noSoundOrShortcut, text: OnCallText.noSoundOrShortcut))
        }
        return found
    }

    private static func ruleWarningFindings(_ inputs: Inputs) -> [Finding] {
        var found: [Finding] = []
        let warned = inputs.ruleWarnings.filter { $0.shortcutName != nil }.count
        if let sentence = RuleWarnings.summarySentence(count: warned) {
            found.append(Finding(kind: .shortcutNotFound, text: sentence, count: warned))
        }
        let cannotPlay = inputs.ruleWarnings.filter { $0.kind == .cannotPlay }.count
        if let sentence = RuleWarnings.alertSummarySentence(count: cannotPlay) {
            found.append(Finding(kind: .alertCannotPlay, text: sentence, count: cannotPlay))
        }
        return found
    }

    /// Only a status that was read and is not enabled. What it says is worded from
    /// the state read beside it, and its button is the one that state allows: turn
    /// on where the item can be registered, Open Login Items for one the system has
    /// switched off, and none where it is not offered, where the sentence gives the
    /// reason instead.
    private static func loginItemFindings(_ inputs: Inputs) -> [Finding] {
        guard inputs.startsAtLogin == false else { return [] }
        return [Finding(kind: .loginItemOff, text: OnCallText.loginItemOff(for: inputs.loginItem),
                        action: inputs.loginItem.flatMap(LaunchAtLogin.findingAction(for:)))]
    }

    private static func mutingFindings(_ inputs: Inputs) -> [Finding] {
        let unconfirmed = inputs.unconfirmedMutedApps.count
        guard unconfirmed > 0 else { return [] }
        return [Finding(kind: .unconfirmedMuting, text: OnCallText.unconfirmedMuting(count: unconfirmed),
                        count: unconfirmed)]
    }

    /// An advisory: the panel and the menu still acknowledge, so a page is as likely to
    /// be answered, and the user learns it here rather than by pressing it in an incident.
    private static func hotkeyFindings(_ inputs: Inputs) -> [Finding] {
        inputs.acknowledgeHotkeyRegistered ? [] : [Finding(kind: .hotkeyNotRegistered, text: OnCallText.hotkeyNotRegistered)]
    }

    private static var standingAdvisories: [Finding] {
        [Finding(kind: .focus, text: Self.focusAdvisory), Finding(kind: .sleep, text: OnCallText.sleepAdvisory)]
    }

    /// Whether the rules file is in effect with nothing refused and no rule is
    /// enabled in it: no file, an empty one, or every rule off. A refused rule is
    /// the finding before it, and a file not in effect is another.
    private static func noRuleIsEnabled(in status: RuleStoreStatus) -> Bool {
        switch status {
        case .noRulesFile: return true
        case .loaded(let enabled, _): return enabled == 0
        case .loadedWithProblems, .unreadable, .unsupportedVersion, .notReloaded: return false
        }
    }

    /// The Focus advisory: the mute walkthrough's own sentence about what a Focus
    /// does, so the advice is written once, then that it cannot be read, and the
    /// workaround the first findings note records.
    static var focusAdvisory: String {
        (MuteWalkthroughText.focusLimitLines + [OnCallText.focusCannotRead, OnCallText.focusWorkaround])
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

extension OnCallCheck {
    /// Where a finding's button takes the user, for every finding but the login item's,
    /// whose button acts (`Finding.action`). Each only opens a pane of System Settings or one
    /// of the app's windows, and switches nothing on, so O12 is kept (2026-10-16, workflow
    /// audit finding 4). Before, only the login finding had a button, so the window that
    /// opens itself with a beep named a problem and left the user to find where to fix it.
    public enum Destination: Equatable, Sendable {
        /// The pane that fixes a health cause (`HealthCause.pane`).
        case pane(HealthCause.Pane)
        /// System Settings › Sound, which holds the output and Alert volume.
        case soundSettings
        /// System Settings › Focus.
        case focusSettings
        /// The rule editor, where every finding about the rules is fixed.
        case ruleEditor
        /// The Setup Guide, whose mute step is where an app is confirmed muted.
        case setupGuide
    }

    /// Each kind's destination, typed out with no default arm, so a kind added later has to
    /// say. The health finding's is the pane its first cause names, and none where no pane
    /// fixes it. Not verified yet has Check Now beneath it; the login item has its own button
    /// that acts; and a Mac that sleeps has nothing to open.
    static func destination(of kind: Finding.Kind, health: CaptureHealth) -> Destination? {
        switch kind {
        case .health:
            return health.firstCause?.pane.map(Destination.pane)
        case .notVerifiedYet, .loginItemOff, .sleep, .hotkeyNotRegistered:
            return nil
        case .outputMuted, .beepsInaudible:
            return .soundSettings
        case .rulesNotInEffect, .rulesFileNotInEffect, .noRuleEnabled, .noSoundOrShortcut, .shortcutNotFound,
             .alertCannotPlay:
            return .ruleEditor
        case .unconfirmedMuting:
            return .setupGuide
        case .focus:
            return .focusSettings
        }
    }
}

extension OnCallText {
    /// A destination's button, in the words the app already gives that place.
    public static func label(for destination: OnCallCheck.Destination) -> String {
        switch destination {
        case .pane(.notifications): return SetupText.label(for: .openNotificationSettings)
        case .pane(.accessibility): return SetupText.label(for: .openAccessibilitySettings)
        case .pane(.keyboard): return SetupText.label(for: .openKeyboardSettings)
        case .soundSettings: return "Open Sound Settings…"
        case .focusSettings: return MuteWalkthroughText.openFocusSettings
        case .ruleEditor: return StatusMenuText.editRulesTitle
        case .setupGuide: return SetupText.openGuideButton
        }
    }
}
