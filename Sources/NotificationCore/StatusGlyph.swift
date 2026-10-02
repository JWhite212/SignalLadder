// Sources/NotificationCore/StatusGlyph.swift
import Foundation

/// Which icon the status item shows, and what it says to VoiceOver and in its
/// tooltip, as one pure decision (M5 plan, Rulings 10, 17 and 18). The app target
/// has no tests, so it builds no boolean of its own: it hands over the facts it
/// has read and carries out the answer.
///
/// The precedence is problem, escalating, on call, normal. A broken pipeline is
/// the most important fact on screen (§7.1), so a problem outranks everything,
/// and a live escalation is never folded into it: a working ladder must not look
/// like a broken pipeline. On call is the standing state, and is shown while
/// nothing above it is.
///
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
/// Snooze, a held summary and the states that go with them are added by the
/// commits that build them, each with its place in the precedence.
public enum StatusGlyph {
    public enum State: CaseIterable, Equatable, Sendable {
        case problem
        case escalating
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
                    alertVolume: Double?, escalationLive: Bool, onCall: Bool, selfTestsRunning: Bool?) {
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

    public static func state(for facts: Facts) -> State {
        if isProblem(facts) { return .problem }
        if facts.escalationLive { return .escalating }
        if facts.onCall { return .onCall }
        return .normal
    }

    /// - Parameter pulse: which of the two escalating symbols to show. The pulse
    ///   alternates only while escalating, and is read for no other state.
    public static func appearance(for facts: Facts, pulse: Bool) -> Appearance {
        let state = state(for: facts)
        switch state {
        case .problem:
            return Appearance(state: state, symbol: StatusGlyphText.problemSymbol,
                              description: StatusGlyphText.problemDescription, tooltip: StatusGlyphText.problemTooltip)
        case .escalating:
            return Appearance(state: state,
                              symbol: pulse ? StatusGlyphText.escalatingSymbolBright : StatusGlyphText.escalatingSymbolDim,
                              description: StatusGlyphText.escalatingDescription,
                              tooltip: StatusGlyphText.escalatingTooltip)
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
    public static let onCallSymbol = "bell.badge.fill"
    public static let normalSymbol = "bell.badge"

    public static let normalDescription = "SignalLadder"
    public static let problemDescription = "SignalLadder — problem"
    public static let escalatingDescription = "SignalLadder — alert escalating"
    public static let problemTooltip = "SignalLadder — a problem needs attention. Open the menu to see what."
    public static let escalatingTooltip = "SignalLadder — an alert is escalating. Open the menu to acknowledge it."
    public static let onCallStem = "SignalLadder — on call"
    public static let onCallCadence = ", self-test every 5 minutes"

    /// "SignalLadder — on call", with the cadence added only while self-tests are
    /// running.
    public static func onCallDescription(selfTestsRunning: Bool) -> String {
        selfTestsRunning ? onCallStem + onCallCadence : onCallStem
    }
}
