// Sources/NotificationCore/StatusGlyph.swift
import Foundation

/// Which icon the status item shows, and what it says to VoiceOver and in its
/// tooltip, as one pure decision (M5 plan, Rulings 10, 17 and 18). The app target
/// has no tests, so it builds no boolean of its own: it hands over the facts it
/// has read and carries out the answer.
///
/// The precedence is problem, escalating, snoozed, held summary, on call, normal
/// (Ruling 17). A broken pipeline is the most important fact on screen (§7.1), so
/// a problem outranks everything, and a live escalation is never folded into it:
/// a working ladder must not look like a broken pipeline. A snooze is next, since
/// while one runs the user has chosen to be told less and the icon must say so,
/// and what a snooze held comes after it, shown until the user dismisses it, with
/// no snooze running or while one is. Both rank above on call, which is the
/// standing state and is shown while nothing above it is, so each says "on call"
/// too while the mode is on (O9, O10): the glyph never tells the user less than
/// the mode does. A snooze is never shown with the slashed bell, which means a
/// fault, and there is no countdown, which would need a timer of its own.
/// **A problem** is any of eight things. Five hold whether or not the app is on
/// call: capture is not working, or cannot be shown to be (health alarming); a
/// rule the user wrote is not in effect; a rule in effect names a Shortcut the
/// Shortcuts app does not list; the last alert could not play and none has since;
/// a Shortcut did not run and that Shortcut has not started since. Each leaves the
/// app as silent as a blind pipeline does. Three more hold only while on call,
/// since only then is the app's silence something the user is relying on to be
/// told: capture that has stayed unverified past the bound `HealthAlarmPlan`
/// sounds for, asked of the same function so that the icon and the beep cannot
/// disagree; a muted or zero-volume output while an enabled rule makes a sound;
/// and an Alert volume of zero, whether or not a rule sounds, since the beeps are
/// the app's own channel and not a rule's.
///
/// A summary that exists is any `HeldSummary` that is not empty, a record that
/// could not be read included: it is a page that may have been held, and the icon
/// does not stay silent about one.
public enum StatusGlyph {
    public enum State: CaseIterable, Equatable, Sendable {
        case problem
        case escalating
        case snoozed
        case heldSummary
        case onCall
        case normal
    }

    /// Everything the icon depends on, read by the app target and decided here.
    /// None has a default, so a place that forgets a fact does not compile.
    public struct Facts: Equatable, Sendable {
        /// The health, which is a problem when alarming, and which is unknown
        /// for the bound to be asked of.
        public var health: CaptureHealth
        /// What the health alarm remembers, for the bound.
        public var healthAlarmState: HealthAlarmPlan.State
        /// The time of the read, for the bound.
        public var now: Date
        /// Something the user wrote is not in effect (`RuleStoreStatus.isProblem`).
        public var ruleStatusProblem: Bool
        /// Rules in effect whose Shortcut was not found. Not a refusal, but a page
        /// that may not reach the phone, so above zero it is a problem.
        public var shortcutWarningCount: Int
        /// The last alert could not play, and no alert has played since.
        public var unresolvedAlertFailure: Bool
        /// A Shortcut did not run, and that Shortcut has not started since.
        public var unresolvedShortcutFailure: Bool
        /// The output reports itself muted or at zero volume.
        public var outputSilent: Bool
        /// An enabled rule makes a sound or speaks.
        public var anEnabledRuleSounds: Bool
        /// Alert volume, a number or nil when it could not be read.
        public var alertVolume: Double?
        /// Any escalation is live.
        public var escalationLive: Bool
        /// When the snooze ends, nil while none is running
        /// (`SnoozeController.endsAt`).
        public var snoozeEndsAt: Date?
        /// What snoozes have held and the user has not dismissed, which is empty
        /// when there is nothing to show (`SnoozeController.summary`).
        public var heldSummary: HeldSummary
        /// The app is on call.
        public var onCall: Bool
        /// Whether a self-test can run now (`SelfTestPlan.Conditions.allowsSelfTest`),
        /// nil before the first health check has said. The cadence is named only
        /// while self-tests are running, since saying it while one is blocked
        /// would say more than the app has established.
        public var selfTestsRunning: Bool?

        public init(health: CaptureHealth, healthAlarmState: HealthAlarmPlan.State, now: Date,
                    ruleStatusProblem: Bool, shortcutWarningCount: Int, unresolvedAlertFailure: Bool,
                    unresolvedShortcutFailure: Bool, outputSilent: Bool, anEnabledRuleSounds: Bool,
                    alertVolume: Double?, escalationLive: Bool, snoozeEndsAt: Date?, heldSummary: HeldSummary,
                    onCall: Bool, selfTestsRunning: Bool?) {
            self.health = health
            self.healthAlarmState = healthAlarmState
            self.now = now
            self.ruleStatusProblem = ruleStatusProblem
            self.shortcutWarningCount = shortcutWarningCount
            self.unresolvedAlertFailure = unresolvedAlertFailure
            self.unresolvedShortcutFailure = unresolvedShortcutFailure
            self.outputSilent = outputSilent
            self.anEnabledRuleSounds = anEnabledRuleSounds
            self.alertVolume = alertVolume
            self.escalationLive = escalationLive
            self.snoozeEndsAt = snoozeEndsAt
            self.heldSummary = heldSummary
            self.onCall = onCall
            self.selfTestsRunning = selfTestsRunning
        }
    }

    /// What the status item shows.
    public struct Appearance: Equatable, Sendable {
        public let state: State
        public let symbol: String
        /// What VoiceOver reads.
        public let description: String
        /// What the pointer shows after a moment.
        public let tooltip: String
    }

    /// The symbol of the normal state, which the app uses when the system does
    /// not know the one an appearance names: `NSImage(systemSymbolName:)` answers
    /// nil for an unknown name, and an item assigned nil is blank.
    public static let fallbackSymbol = StatusGlyphText.normalSymbol

    /// Whether the icon says problem.
    public static func isProblem(_ facts: Facts) -> Bool {
        if facts.health.isAlarming || facts.ruleStatusProblem || facts.shortcutWarningCount > 0
            || facts.unresolvedAlertFailure || facts.unresolvedShortcutFailure {
            return true
        }
        guard facts.onCall else { return false }
        return HealthAlarmPlan.isUnverifiedFault(onCall: true, health: facts.health, state: facts.healthAlarmState,
                                                 now: facts.now)
            || (facts.outputSilent && facts.anEnabledRuleSounds)
            || BeepAudibility.isSilent(alertVolume: facts.alertVolume)
    }

    /// The state, with what only that state needs: a snooze has an end. One
    /// place decides the order, so `state(for:)` and `appearance(for:pulse:time:)`
    /// cannot disagree about it.
    private enum Decision {
        case problem
        case escalating
        case snoozed(until: Date)
        case heldSummary
        case onCall
        case normal

        var state: State {
            switch self {
            case .problem: return .problem
            case .escalating: return .escalating
            case .snoozed: return .snoozed
            case .heldSummary: return .heldSummary
            case .onCall: return .onCall
            case .normal: return .normal
            }
        }
    }

    private static func decision(for facts: Facts) -> Decision {
        if isProblem(facts) { return .problem }
        if facts.escalationLive { return .escalating }
        if let end = facts.snoozeEndsAt { return .snoozed(until: end) }
        if !facts.heldSummary.isEmpty { return .heldSummary }
        if facts.onCall { return .onCall }
        return .normal
    }

    public static func state(for facts: Facts) -> State {
        decision(for: facts).state
    }

    /// - Parameters:
    ///   - pulse: which of the two escalating symbols to show. The pulse
    ///     alternates only while escalating, and is read for no other state.
    ///   - time: how a moment is shown, as the menu's other lines show one
    ///     ("15:30"), for the end of a snooze.
    public static func appearance(for facts: Facts, pulse: Bool, time: (Date) -> String) -> Appearance {
        let decision = decision(for: facts)
        let state = decision.state
        switch decision {
        case .problem:
            return Appearance(state: state, symbol: StatusGlyphText.problemSymbol,
                              description: StatusGlyphText.problemDescription, tooltip: StatusGlyphText.problemTooltip)
        case .escalating:
            return Appearance(state: state,
                              symbol: pulse ? StatusGlyphText.escalatingSymbolBright : StatusGlyphText.escalatingSymbolDim,
                              description: StatusGlyphText.escalatingDescription,
                              tooltip: StatusGlyphText.escalatingTooltip)
        case .snoozed(let end):
            let description = StatusGlyphText.snoozedDescription(until: time(end), held: facts.heldSummary,
                                                                 onCall: facts.onCall)
            return Appearance(state: state, symbol: StatusGlyphText.snoozedSymbol, description: description,
                              tooltip: description)
        case .heldSummary:
            let description = StatusGlyphText.heldDescription(facts.heldSummary, onCall: facts.onCall)
            return Appearance(state: state, symbol: StatusGlyphText.heldSymbol, description: description,
                              tooltip: description)
        case .onCall:
            let description = StatusGlyphText.onCallDescription(selfTestsRunning: facts.selfTestsRunning == true)
            return Appearance(state: state, symbol: StatusGlyphText.onCallSymbol, description: description,
                              tooltip: description)
        case .normal:
            return Appearance(state: state, symbol: StatusGlyphText.normalSymbol,
                              description: StatusGlyphText.normalDescription, tooltip: StatusGlyphText.normalDescription)
        }
    }
}

/// The icon's symbols and words, in one place where they are tested (M5 plan,
/// Ruling 18). Every symbol is older than the macOS 14 floor, by the availability
/// list in the system's glyph bundle.
public enum StatusGlyphText {
    public static let problemSymbol = "bell.slash.fill"
    public static let escalatingSymbolBright = "bell.and.waves.left.and.right.fill"
    public static let escalatingSymbolDim = "bell.and.waves.left.and.right"
    /// A snooze. Never the slashed bell, which means a fault.
    public static let snoozedSymbol = "moon.zzz.fill"
    /// A summary of what snoozes held, shown until it is dismissed.
    public static let heldSymbol = "tray.full.fill"
    public static let onCallSymbol = "bell.badge.fill"
    public static let normalSymbol = "bell.badge"

    public static let normalDescription = "SignalLadder"
    public static let problemDescription = "SignalLadder — problem"
    public static let escalatingDescription = "SignalLadder — alert escalating"
    public static let problemTooltip = "SignalLadder — a problem needs attention. Open the menu to see what."
    public static let escalatingTooltip = "SignalLadder — an alert is escalating. Open the menu to acknowledge it."
    public static let onCallStem = "SignalLadder — on call"
    public static let onCallCadence = ", self-test every 5 minutes"
    /// What a snooze's description says before the end, as a clock time.
    public static let snoozedStem = "SignalLadder — snoozed until"
    /// What follows the summary's words in the held description, and so in its
    /// tooltip, which is the same sentence.
    public static let openTheMenu = ". Open the menu."
    /// Added to the snoozed and the held descriptions, and to their tooltips,
    /// while the mode is on, since each outranks on call (O9, O10).
    public static let onCallClause = ", and you are on call"
    /// What follows the matches that could be counted when others were held and
    /// their record could not be read (Ruling 12).
    public static let someOthersUncounted = ", and some others whose record could not be read"
    /// The snoozed description, of a snooze that has held nothing.
    public static let noMatchesHeld = "no matches held"
    /// The snoozed description, when matches were held and none could be counted.
    public static let someMatchesHeldUncounted = "some matches held whose record could not be read"
    /// The held description, of a summary that has nothing in it. The icon never
    /// shows the state for one, and a sentence that is asked for is not left blank.
    public static let noMatchesWereHeld = "no matches were held while snoozed"
    /// The held description, when matches were held and none could be counted.
    public static let someMatchesWereHeldUncounted = "some matches were held while snoozed and their record could not be read"

    /// "SignalLadder — on call", with the cadence added only while self-tests are
    /// running.
    public static func onCallDescription(selfTestsRunning: Bool) -> String {
        selfTestsRunning ? onCallStem + onCallCadence : onCallStem
    }

    /// "SignalLadder — snoozed until 15:30, 3 matches held", and ", and you are
    /// on call" while the mode is on. The count is what the summary holds, which
    /// is what the menu's line counts, and it is not said to be this snooze's:
    /// the summary outlives a snooze and a new one adds to it (O9). `until` is
    /// the end as the menu shows a moment.
    public static func snoozedDescription(until: String, held: HeldSummary, onCall: Bool) -> String {
        let counted = held.counts.isEmpty ? nil : held.total == 1 ? "1 match held" : "\(held.total) matches held"
        let record = record(counted: counted, unreadable: held.recordUnreadable,
                            nothing: noMatchesHeld, uncountedOnly: someMatchesHeldUncounted)
        return "\(snoozedStem) \(until), \(record)" + (onCall ? onCallClause : "")
    }

    /// "SignalLadder — 3 matches were held while snoozed. Open the menu.", with
    /// ", and you are on call" before the full stop while the mode is on. For a
    /// summary that exists and no snooze running. A record that could not be read
    /// is said, as the menu's line says it.
    public static func heldDescription(_ held: HeldSummary, onCall: Bool) -> String {
        let counted = held.counts.isEmpty ? nil
            : held.total == 1 ? "1 match was \(SnoozeText.heldStem)" : "\(held.total) matches were \(SnoozeText.heldStem)"
        let record = record(counted: counted, unreadable: held.recordUnreadable,
                            nothing: noMatchesWereHeld, uncountedOnly: someMatchesWereHeldUncounted)
        return lead + record + (onCall ? onCallClause : "") + openTheMenu
    }

    /// The app's name and a dash, as the other descriptions begin.
    private static let lead = "SignalLadder — "

    /// What a summary comes to in words: what could be counted, and that some
    /// could not be, which is never left out.
    private static func record(counted: String?, unreadable: Bool, nothing: String, uncountedOnly: String) -> String {
        switch (counted, unreadable) {
        case (let counted?, false): return counted
        case (let counted?, true): return counted + someOthersUncounted
        case (nil, false): return nothing
        case (nil, true): return uncountedOnly
        }
    }
}
