// Sources/NotificationCore/CapturePipeline.swift
import Foundation

/// Every decision made about a captured banner, in order, in one testable
/// place.
///
/// This logic used to live in a closure inside `CaptureController`, in a target
/// with no tests. Two consecutive reviews named it the riskiest uncovered path
/// in the app — and it is where the rule engine attaches, so it had to become
/// testable before anything was added to it. `CaptureController` now only
/// feeds banners in from the Accessibility observer.
///
/// Main-actor isolated, and the compiler holds everyone to it: the capture
/// callback arrives on the main run loop, and the sound it may set off plays
/// through an engine that is only ever touched from there. A lock would imply
/// callers on other threads; this rules them out.
@MainActor
public final class CapturePipeline {
    public enum Outcome: Equatable, Sendable {
        /// The app's own self-test. Never recorded, never counted.
        case selfTest
        /// An alarm or self-test the app posted, caught by the backstop.
        case ownNotification
        /// A repeat dedupe collapsed onto the row it duplicates.
        case suppressedRepeat
        /// A new row. `matchedRule` is nil when nothing matched or when no
        /// rules are loaded; the row's annotation says which.
        case recorded(matchedRule: String?)

        /// Whether this outcome changes anything the user can see. The app's
        /// own traffic never does: a self-test or alarm must not count, list,
        /// or refresh anything. Decided here, where it is tested, rather than
        /// in the switch that calls the UI, which has no tests.
        public var changesWhatTheUserSees: Bool {
            switch self {
            case .selfTest, .ownNotification: return false
            case .suppressedRepeat, .recorded: return true
            }
        }
    }

    /// A live match and what was done about it. Not updated by previews: a
    /// preview is what WOULD happen under new rules, and reporting it as a
    /// match would claim an event that never occurred.
    public struct LastMatch: Equatable, Sendable {
        public let ruleName: String
        public let at: Date
        public let alert: AlertOutcome
    }

    /// A tier 4 Shortcut that did not run. Held apart from a sound's failure:
    /// folded in with those, tier 3's next repeat, playing thirty seconds
    /// later, would clear a failure to page someone's phone.
    public struct ShortcutFailure: Equatable, Sendable {
        public let ruleName: String
        /// The Shortcut that did not run, as the rule names it. A launch of
        /// this one clears the failure, and a launch of any other does not.
        public let shortcutName: String
        public let at: Date
        /// Built by the app, never the Shortcut's own output (ruling 19).
        public let reason: String
    }

    /// Plays a named sound at a rule's gain, and says what happened: `.played`
    /// or `.failed`. Injected, like `isSelfTest`, because playback needs
    /// AVFoundation, which cannot live in this module.
    public typealias SoundPlayer = (_ name: String, _ gainDB: Double) -> AlertOutcome

    /// Speaks a rendered line with a rule's voice, rate, pitch and gain, and
    /// says what happened: `.spoke` or `.couldNotSpeak`.
    public typealias SpeechPlayer = (_ text: String, _ speech: SpeechAction) -> AlertOutcome

    /// A sound, then a spoken line, as one alert — never two alerts in a row,
    /// which would each cut the other off.
    public typealias SoundAndSpeechPlayer = (_ soundName: String, _ soundGainDB: Double,
                                             _ text: String, _ speech: SpeechAction) -> AlertOutcome

    public let history: CaptureRingBuffer
    public private(set) var captureCount = 0
    public private(set) var rules: [Rule] = []
    public private(set) var lastMatch: LastMatch?

    /// The most recent match whose sound could not play, held until a later
    /// sound plays. A rule that should have made a noise and did not is the
    /// failure this app exists to prevent, so it is not allowed to scroll out
    /// of view behind a quieter match that happened to come after it.
    ///
    /// Only a sound actually playing clears it. Reloading rules does not: a
    /// file that exists but cannot be decoded passes every check made at load,
    /// and clearing on reload would announce a fix nobody had made.
    public private(set) var unresolvedAlertFailure: LastMatch?

    /// The most recent Shortcut that did not run, held until that same
    /// Shortcut launches, from an escalation or from a test in the editor.
    ///
    /// The discipline is the alert failure's: only the thing that failed,
    /// working, is evidence that it is fixed. A launch of another Shortcut says
    /// nothing about this one, and a reload does not clear it either: a rename
    /// that fixes the rule leaves this held until the old name launches or the
    /// app quits, which is the price of never letting a record of a page that
    /// did not reach the phone go without a success.
    public private(set) var unresolvedShortcutFailure: ShortcutFailure?

    /// Every app that set off a rule that alerts aloud this session, first
    /// spelling kept. Feeds the mute walkthrough the apps a rule reached by
    /// pattern, which reading the rules alone cannot name. Speech counts:
    /// the source app's own sound plays over it otherwise.
    public private(set) var appsThatAlerted: [String] = []

    private let dedupe: CaptureDeduplicator
    private let ownAppName: String?
    private let isSelfTest: (String, [String]) -> Bool
    private let playSound: SoundPlayer
    private let speak: SpeechPlayer
    private let playAndSpeak: SoundAndSpeechPlayer
    private let beginEscalation: (Rule, CapturedNotification, UUID) -> Void
    private let holdForSnooze: (Rule) -> Bool
    private var pendingSuppressedRepeats = 0

    /// Per row, how many repeats and whether a final outcome have already
    /// been folded into the failures above, so a summary recorded again — on
    /// a cap or an acknowledgement, still carrying its last repeat — never
    /// sets a failure a later repeat had cleared. Kept until the escalation
    /// is retired, not while its row is: a busy channel can push a row out
    /// of the history while its ladder still runs.
    private var foldedRepeats: [UUID: Int] = [:]
    private var foldedFinal: Set<UUID> = []

    /// - Parameters:
    ///   - isSelfTest: given a banner's description and text children,
    ///     whether it is the canary. Injected rather than taking a
    ///     `CanaryService`, which posts through UserNotifications and so cannot
    ///     live in this module.
    ///   - playSound, speak, playAndSpeak: none has a default, so no caller
    ///     can forget to connect one and leave every such rule quietly mute.
    ///   - beginEscalation: starts the rest of a rule's ladder, from the row
    ///     just recorded, once its tier 1 has been set off. No default either.
    ///   - holdForSnooze: given the rule a live match came under, whether a
    ///     snooze holds this match, so that it sounds nothing and begins no
    ///     ladder (M5 plan, Ruling 13). The app gives the snooze's own verdict,
    ///     which also counts what it holds. No default either, so no caller can
    ///     forget to connect one and leave a snooze that holds nothing.
    public init(ownAppName: String?,
                isSelfTest: @escaping (String, [String]) -> Bool,
                playSound: @escaping SoundPlayer,
                speak: @escaping SpeechPlayer,
                playAndSpeak: @escaping SoundAndSpeechPlayer,
                beginEscalation: @escaping (Rule, CapturedNotification, UUID) -> Void,
                holdForSnooze: @escaping (Rule) -> Bool,
                history: CaptureRingBuffer = CaptureRingBuffer(),
                dedupe: CaptureDeduplicator = CaptureDeduplicator()) {
        self.ownAppName = ownAppName
        self.isSelfTest = isSelfTest
        self.playSound = playSound
        self.speak = speak
        self.playAndSpeak = playAndSpeak
        self.beginEscalation = beginEscalation
        self.holdForSnooze = holdForSnooze
        self.history = history
        self.dedupe = dedupe
    }

    @discardableResult
    public func process(_ raw: RawCapture, textChildren: [String]) -> Outcome {
        let notification = NotificationFieldExtractor.extract(raw, textChildren: textChildren)

        // The canary is the app talking to itself. Recognised BEFORE dedupe,
        // so its text never enters the dedupe window — otherwise a real
        // notification that happened to match it inside 1.5s would be
        // suppressed as a repeat of a self-test.
        //
        // Both text sources are offered: the description the marker was
        // historically matched against is allowed to be empty, so a
        // description-only check can miss a canary that was captured.
        if isSelfTest(notification.rawText, textChildren) { return .selfTest }

        // Backstop for everything this app posts — alarms, which carry no
        // marker, and a self-test whose marker match failed for any reason.
        // Name alone would be too loose a net: it would silently drop a real
        // notification from any app sharing our name. SelfNotification
        // requires our wording as well.
        if SelfNotification.isOwnNotification(notification, ownAppName: ownAppName) { return .ownNotification }

        let decision = dedupe.admit(notification.rawText, at: notification.timestamp)
        if decision.isRepeat {
            // Recorded on the row it duplicates. Dedupe keys on content within
            // a short window, which cannot tell one banner re-firing during
            // animation from two genuinely distinct alerts carrying identical
            // text — and a noisy channel produces exactly the latter. Showing
            // the count is how we find out which is happening.
            //
            // Repeats never reach the rule engine. Dedupe exists to stop one
            // banner's animation producing several events; evaluating each
            // would sound the same alert several times.
            //
            // The fallback covers a row already evicted, which needs ~50
            // distinct captures inside dedupe's 1.5s window. Holding the count
            // for the next admission can attribute it to an unrelated app, but
            // is better than discarding evidence silently.
            if !history.noteSuppressedRepeat(matching: notification.rawText) {
                pendingSuppressedRepeats += 1
            }
            return .suppressedRepeat
        }

        captureCount += 1
        let entry = history.record(notification, suppressedRepeatCount: pendingSuppressedRepeats)
        pendingSuppressedRepeats = 0

        let (annotation, match) = evaluate(notification)
        if let annotation {
            history.annotate(id: entry.id, with: annotation)
        }
        if let match {
            if match.alertsAloud {
                appsThatAlerted = MuteWalkthrough.unique(appsThatAlerted + [notification.appNameGuess])
            }
            // The snooze gate (M5 plan, Ruling 13). It sits here, after the row
            // is annotated "Matched X" and after the app is noted for the mute
            // walkthrough, so a held match still reads as a match, and before
            // tier 1, so a held match plays nothing. It is asked once, of a
            // live match on a new row, and of nothing else: the self-test, the
            // app's own traffic and a repeat have returned above, and a preview
            // never comes through here.
            let held = holdForSnooze(match)
            let alert = held ? AlertOutcome.snoozed : act(on: match.alert, for: notification)
            history.setAlertOutcome(id: entry.id, alert)
            let record = LastMatch(ruleName: match.name, at: notification.timestamp, alert: alert)
            lastMatch = record
            fold(alert, as: record)
            // After tier 1 and its outcome are recorded, so the row, the last
            // match and the glyph are complete before the ladder starts: it
            // records and redraws as it begins. Tiers 2 to 4 are set off
            // later, by the coordinator, reachable only from here. A held
            // match never begins one, and never joins one: a snooze is for
            // what has not begun, and a ladder already running is not its to
            // touch (Ruling 13).
            if !held, match.escalation != nil {
                beginEscalation(match, notification, entry.id)
            }
        }
        return .recorded(matchedRule: match?.name)
    }

    /// A failure sets the unresolved failure; only a sound or line that
    /// actually played clears it. A match a snooze held did neither, so it
    /// leaves the failure as it was: it neither sets one nor says one is fixed.
    private func fold(_ alert: AlertOutcome, as record: LastMatch) {
        switch alert {
        case .played, .spoke, .playedAndSpoke: unresolvedAlertFailure = nil
        case .failed, .couldNotSpeak, .playedButNotSpoken, .spokeButNotPlayed: unresolvedAlertFailure = record
        case .silentByRule, .noAlertSet, .snoozed: break
        }
    }

    /// Where a row's escalation has got to: written onto the row, and a later
    /// tier's outcome folded into the failures the menu and glyph show, by
    /// tier 1's rules (§5.16: "a warning on the Inspector row and a
    /// status-item badge"). Each repeat and the final outcome are folded once.
    /// A repeat never changes `lastMatch`, which stays the notification that
    /// matched.
    public func recordEscalation(entryID: UUID, _ summary: EscalationSummary, at now: Date) {
        history.setEscalation(id: entryID, summary)
        if let outcome = summary.lastRepeat, summary.repeatCount > foldedRepeats[entryID, default: 0] {
            foldedRepeats[entryID] = summary.repeatCount
            fold(outcome, as: LastMatch(ruleName: summary.ruleName, at: now, alert: outcome))
        }
        if let final = summary.final, !foldedFinal.contains(entryID) {
            foldedFinal.insert(entryID)
            switch final {
            case .alerted(let outcome):
                fold(outcome, as: LastMatch(ruleName: summary.ruleName, at: now, alert: outcome))
            case .shortcutLaunched(let name):
                shortcutLaunched(named: name)
            case .shortcutFailed(let name, let reason):
                unresolvedShortcutFailure = ShortcutFailure(ruleName: summary.ruleName, shortcutName: name,
                                                            at: now, reason: reason)
            }
        }
    }

    /// A test of a Shortcut from the editor started it. Clears the held
    /// failure when it is that Shortcut's, as a real launch of it does, and
    /// otherwise changes nothing, so a test of one Shortcut never tells the
    /// menu that another is fixed. A test that fails is never reported here:
    /// it may be a typo in a draft not yet saved, and the editor shows it
    /// beside the button.
    public func shortcutStartedInTest(named name: String) {
        shortcutLaunched(named: name)
    }

    /// Only a launch of the Shortcut that failed clears its failure.
    private func shortcutLaunched(named name: String) {
        guard unresolvedShortcutFailure?.shortcutName == name else { return }
        unresolvedShortcutFailure = nil
    }

    /// A row's escalation is finished: nothing more will be recorded for it,
    /// so what was folded from it is forgotten.
    public func escalationRetired(entryID: UUID) {
        foldedRepeats[entryID] = nil
        foldedFinal.remove(entryID)
    }

    /// The only place tier 1 is set off. Reached solely from a live match on
    /// a newly recorded row that no snooze held — never from a preview, a
    /// repeat, or the app's own traffic, all of which return before this, nor
    /// from a match the gate held. Tier 1 is the only tier whose alert can be
    /// missing; every other case goes the way later tiers' do.
    private func act(on alert: AlertAction?, for notification: CapturedNotification) -> AlertOutcome {
        guard let alert else { return .noAlertSet }
        return AlertActionRunner.run(alert, for: notification, playSound: playSound, speak: speak,
                                     playAndSpeak: playAndSpeak)
    }

    /// Replaces the rules, and previews them against every retained row — a
    /// dry run of the new rules over real recent traffic, which the spec calls
    /// essential (§7.3): "writing a rule blind and waiting for the next
    /// incident to discover it was wrong is the failure mode that causes tools
    /// like this to be abandoned."
    ///
    /// Previews are written to `preview`, never `annotation`, and never update
    /// `lastMatch`. They describe what would happen, not what did.
    ///
    /// - Returns: how many retained rows the new rules match.
    @discardableResult
    public func setRules(_ newRules: [Rule]) -> Int {
        rules = newRules
        var matching = 0
        for entry in history.entries {
            let preview = evaluate(entry.captured).annotation
            history.setPreview(id: entry.id, preview)
            if preview?.ruleName != nil { matching += 1 }
        }
        return matching
    }

    /// How many retained rows the rules loaded NOW would match.
    ///
    /// Rows captured before the last `setRules` carry a preview from these
    /// rules; rows captured since carry a live annotation from these same
    /// rules. Together they are the current rules' verdict on everything
    /// retained — the "would have matched 3 of the last 50" of §7.3.
    ///
    /// Zero with no rules loaded, because then any annotation left on a row
    /// came from rules that no longer exist, and counting it would report a
    /// verdict nobody's current rules gave.
    public var currentRuleMatchCount: Int {
        guard !rules.isEmpty else { return 0 }
        return history.entries.filter { ($0.preview ?? $0.annotation)?.ruleName != nil }.count
    }

    /// The first enabled rule the notification matches, and the annotation
    /// that says so.
    ///
    /// The annotation is nil when there are no rules at all: with nothing to
    /// evaluate against, a row has not been evaluated, which is different from
    /// — and must never be shown as — "matched no rule". The spec calls
    /// matching nothing the most common source of confusion (§7.2);
    /// manufacturing it would be worse.
    private func evaluate(_ notification: CapturedNotification) -> (annotation: MatchAnnotation?, match: Rule?) {
        guard !rules.isEmpty else { return (nil, nil) }
        let match = RuleEngine.firstMatch(for: notification, in: rules)
        return (MatchAnnotation(ruleName: match?.name), match)
    }
}
