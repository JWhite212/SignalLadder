// Sources/NotificationCore/EscalationCoordinator.swift
import Foundation

public typealias EscalationID = UUID

/// Where one escalation has got to: what the panel, the menu and the Inspector
/// show of it. Enough to render "On-call mentions — since 10:42 — tier 2,
/// repeat 3 of 20", and to record what each later tier did, without composing
/// a sentence ahead of time.
public struct EscalationSummary: Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        case live
        case acknowledged(at: Date)
        /// Tier 3 has stopped repeating. Not the end: tier 4, if the ladder
        /// has one and it has not yet fired, still fires, and the escalation
        /// stays listed until acknowledged (ruling 10).
        case capped(at: Date)
        /// Ended because the wall clock ran on past the awake time by more
        /// than the staleness threshold: a sleep, in practice, and also what a
        /// large forward step of the clock would look like (ruling 14).
        /// Acknowledging it keeps this status and records when, so its
        /// Inspector row still says it was missed.
        case missedWhileAsleep(convertedAt: Date, acknowledgedAt: Date?)
    }

    public let ruleName: String
    public let startedAt: Date
    public var status: Status
    /// The highest tier that has fired so far, 1 to 4.
    public var tierReached: Int
    public var repeatCount: Int
    /// Mirrors `RepeatAlert.maxRepeats`, for display; nil for no limit.
    public var repeatCap: Int?
    public var lastRepeat: AlertOutcome?
    /// What tier 4 did, or the latest Shortcut run to have reported: a later
    /// run's report replaces an earlier one, so this always describes the
    /// latest run that has reported. Each time an outcome is set, `finalCount`
    /// rises; taking it away does not count as one.
    public var final: FinalOutcome? {
        didSet { if final != nil { finalCount += 1 } }
    }
    /// How many matches this escalation stands for: 1 for the one that began
    /// it. A count of matches and nothing more, which is not what any of them
    /// said (M5 plan, Ruling 14; M4 Ruling 17).
    public var matchCount: Int
    /// How many times `final` was set. A Shortcut can be run more than once in
    /// one escalation, and each run's report is a new outcome that the pipeline
    /// folds into the failures it holds exactly once, so what it needs to know
    /// is not whether there is an outcome but how many have come. Set by
    /// `final` alone, so no place that sets it can forget to count it.
    public private(set) var finalCount: Int

    /// `matchCount` and `finalCount` come last, with defaults, so a summary
    /// built without them is a one-match escalation. One built with a `final`
    /// has had it set at least once, whatever count it is given, since a count
    /// of 0 beside an outcome would say it was never set.
    public init(ruleName: String, startedAt: Date, status: Status = .live, tierReached: Int = 1,
                repeatCount: Int = 0, repeatCap: Int? = nil, lastRepeat: AlertOutcome? = nil,
                final: FinalOutcome? = nil, matchCount: Int = 1, finalCount: Int = 0) {
        self.ruleName = ruleName
        self.startedAt = startedAt
        self.status = status
        self.tierReached = tierReached
        self.repeatCount = repeatCount
        self.repeatCap = repeatCap
        self.lastRepeat = lastRepeat
        self.final = final
        self.matchCount = matchCount
        self.finalCount = max(finalCount, final == nil ? 0 : 1)
    }
}

extension EscalationSummary {
    /// Whether the Inspector's line for it warns: a later tier's alert that
    /// could not sound, or sounded into a muted output, or a Shortcut that
    /// did not run. The same test `InspectorRowText.escalation` uses to say
    /// so, so what is coloured and what is written cannot drift apart. A
    /// missed escalation is not a failure of anything, and does not warn.
    public var needsAttention: Bool {
        if lastRepeat?.needsAttention == true { return true }
        switch final {
        case .alerted(let outcome): return outcome.needsAttention
        case .shortcutFailed: return true
        case .shortcutLaunched, nil: return false
        }
    }
}

extension EscalationSummary.Status {
    /// Live or capped: still escalating, and able to fire a tier.
    public var isEscalating: Bool {
        switch self {
        case .live, .capped: return true
        case .acknowledged, .missedWhileAsleep: return false
        }
    }

    /// Missed while asleep and not yet acknowledged: still to be seen.
    public var isUnseenMiss: Bool {
        if case .missedWhileAsleep(_, nil) = self { return true }
        return false
    }
}

/// What tier 4 did. A Shortcut's failure carries a reason the app wrote, never
/// the Shortcut's own output (ruling 19).
public enum FinalOutcome: Equatable, Sendable {
    case alerted(AlertOutcome)
    case shortcutLaunched(name: String)
    case shortcutFailed(name: String, reason: String)
}

/// What a match that joined an escalation already running for its rule is told
/// (M5 plan, Ruling 14, O11). It carries a number, whether the Shortcut was run
/// again, and what the match's own first alert did. The number and the flag say
/// no word a notification said (M4 Ruling 17). The alert's outcome, like any
/// `AlertOutcome`, can hold the spoken line rendered from the joining
/// notification, which is for the Inspector's row alone and never for the menu,
/// a file or a log: the coordinator keeps none of it, and whoever records this
/// keeps it on the row and nowhere else.
public struct EscalationJoin: Equatable, Sendable {
    /// This match's place in the escalation, which counts the one that began
    /// it as 1: the first to join is 2. What the summary's `matchCount` stood
    /// at when this match was counted, so a row that says "match 3" and a panel
    /// line that says "3 matches" agree.
    public let matchNumber: Int
    /// What the match's own first alert did, played through the sound closures
    /// tier 3 uses so that the player's ownership is the escalation's. nil
    /// when it stayed silent because a repeat about to sound stands in for it
    /// (O11a): then nothing was played and no line was spoken.
    public let alert: AlertOutcome?
    /// Whether this match ran the Shortcut again (O11b): tier 4's, which had
    /// already run, with this match's own fields.
    public let ranShortcut: Bool

    public init(matchNumber: Int, alert: AlertOutcome?, ranShortcut: Bool) {
        self.matchNumber = matchNumber
        self.alert = alert
        self.ranShortcut = ranShortcut
    }
}

/// Runs every escalation's tiers 2 to 4 after tier 1 has sounded, until each
/// is acknowledged, capped and finished, or missed while the Mac slept.
///
/// A `@MainActor` class, not the spec's actor (ruling 2): `acknowledge` is
/// called on the main actor, and the scheduler must run each timer's work
/// there too, inside the timer's own callback rather than through a hop, so
/// there is one queue and no race, as for `CapturePipeline` and `AlertPlayer`.
///
/// Anything it calls out to — a sound, a record, a Shortcut's report — may
/// call back in, to acknowledge say. So every change is written back before
/// it calls out, and read again after.
///
/// Every decision is here, where an injected clock proves it; the app target
/// only supplies the real timers, sound, panel, Shortcut runner and power
/// assertion through the closures below, none of which has a default.
@MainActor
public final class EscalationCoordinator {
    /// Runs the named Shortcut with a notification's fields and reports once,
    /// on the main actor, without making anyone wait for it (ruling 19).
    public typealias ShortcutRun = (_ name: String, _ notification: CapturedNotification,
                                    _ completion: @escaping (FinalOutcome) -> Void) -> Void

    /// How long the Mac must have slept for an escalation to count as missed
    /// rather than resume (§14).
    public nonisolated static let defaultStalenessThreshold: TimeInterval = 300

    /// `repage` is not a tier of the ladder: it is the one timer a join may
    /// arm, to send the page a match was owed (M5 plan, Ruling 14, O11b). A join
    /// arms it, and its own look at a run that is still pending arms it again
    /// for a few seconds on; it is fired, cancelled and counted as pending as the
    /// others are.
    private enum Tier: Hashable { case panel, repeating, final, repage }

    /// How soon a re-page that finds a run still pending looks again (M5 plan,
    /// Ruling 14). The runner reports within its one-second check, so a page
    /// that is owed waits only a few seconds behind a run that has not yet
    /// reported.
    private static let pendingRunRetry: TimeInterval = 5

    /// A moment noted on both clocks at once, so that how long ago it was does
    /// not rest on the wall clock alone. The wall clock counts a sleep that the
    /// awake clock does not, and it can be set back, by a person or by a time
    /// sync, which the awake clock does not feel. `elapsed` is the longer of
    /// what the two say and never less than nothing, so whatever happens to the
    /// wall clock, the moment looks older or as old as it is, and never nearer:
    /// the direction that begins a new escalation and pages again, and not one
    /// that holds a page back behind a clock that has gone wrong. A moment kept
    /// in the future by a clock set back an hour would otherwise delay what is
    /// measured from it by an hour. `Snooze` ends at the earlier of its two
    /// deadlines, and `HealthAlarmPlan` takes a time in the future back to now,
    /// for the same reason (M5 plan, Ruling 14).
    struct Stamp: Equatable {
        let wall: Date
        let awake: TimeInterval

        func elapsed(wall nowWall: Date, awake nowAwake: TimeInterval) -> TimeInterval {
            max(0.0, nowWall.timeIntervalSince(wall), nowAwake - awake)
        }
    }

    private struct Running {
        let entryID: UUID
        /// The rule it was begun for, which a later match of the same rule is
        /// matched to: by id, since a name is not unique (Ruling 14).
        let ruleID: UUID
        let ladder: Escalation
        let notification: CapturedNotification
        /// What tier 1 did for the match that began it, as the pipeline gave
        /// it. nil is not proof that anything was heard, and is what a caller
        /// that does not know says.
        let tier1Outcome: AlertOutcome?
        let order: Int
        var summary: EscalationSummary
        var panelShown = false
        /// Each pending timer's token and ticket, and when it is due on the
        /// awake clock, recorded with the token where `arm` makes it so that
        /// the two cannot part: a timer that fires, is re-armed or is
        /// cancelled takes its due time with it.
        var timers: [Tier: (token: EscalationTimerToken, ticket: Int, due: TimeInterval)] = [:]
        var shortcutPending = false
        /// When the latest match for this escalation arrived, noted on both
        /// clocks (see `Stamp`): a sleep too short to convert it, which only
        /// the wall clock counts, still counts against a quiet gap, and a wall
        /// clock set back does not make the match look recent. At first, when
        /// the match that began it did.
        var lastMatchAt: Stamp
        /// When the latest Shortcut run started, noted the same way for the
        /// same reasons: a clock set back must not delay a page that is owed.
        /// nil until tier 4 has started one.
        var lastShortcutRunAt: Stamp?
        /// The newest match that was owed a page and has not had it, kept in
        /// memory until the page is sent or the escalation is acknowledged,
        /// converted or retired, and replaced by a newer one that is owed. It
        /// is the only notification the coordinator may keep beside the one
        /// that began the escalation (M5 plan, Ruling 14). Set only with the
        /// `.repage` timer that will send it, and cleared with it, so a page
        /// is owed exactly while that timer is armed.
        var owedPage: CapturedNotification?

        /// When tier 3's next repeat is due on the awake clock, which is the
        /// clock the timers fall due by; nil when none is armed, because the
        /// ladder has no tier 3, or it has capped, or it has ended. The awake
        /// clock and not the wall's, so that a short sleep, which the wall
        /// clock counts and the timer does not, cannot make a repeat look
        /// nearer than it is.
        var repeatDue: TimeInterval? { timers[.repeating]?.due }

        var isEscalating: Bool { summary.status.isEscalating }

        /// On the menu until acknowledged: escalating, or missed and not yet
        /// seen.
        var isListed: Bool { summary.status.isEscalating || summary.status.isUnseenMiss }
    }

    private let scheduler: EscalationScheduler
    private let playSound: CapturePipeline.SoundPlayer
    private let speak: CapturePipeline.SpeechPlayer
    private let playAndSpeak: CapturePipeline.SoundAndSpeechPlayer
    private let runShortcut: ShortcutRun
    private let updatePanel: ([(EscalationID, EscalationSummary)]) -> Void
    private let recordSummary: (UUID, EscalationSummary) -> Void
    private let retired: (UUID) -> Void
    private let beginPowerAssertion: () -> Void
    private let endPowerAssertion: () -> Void
    private let silenceIfIdle: () -> Void
    private let stalenessThreshold: TimeInterval
    private let burst: BurstPolicy

    private var escalations: [EscalationID: Running] = [:]
    private var begun = 0
    private var tickets = 0
    private var assertionHeld = false
    /// Where both clocks stood at the last check, to measure a sleep between.
    private var lastWall: Date
    private var lastAwake: TimeInterval

    public init(scheduler: EscalationScheduler,
                playSound: @escaping CapturePipeline.SoundPlayer,
                speak: @escaping CapturePipeline.SpeechPlayer,
                playAndSpeak: @escaping CapturePipeline.SoundAndSpeechPlayer,
                runShortcut: @escaping ShortcutRun,
                updatePanel: @escaping ([(EscalationID, EscalationSummary)]) -> Void,
                recordSummary: @escaping (UUID, EscalationSummary) -> Void,
                retired: @escaping (UUID) -> Void,
                beginPowerAssertion: @escaping () -> Void,
                endPowerAssertion: @escaping () -> Void,
                silenceIfIdle: @escaping () -> Void,
                stalenessThreshold: TimeInterval = EscalationCoordinator.defaultStalenessThreshold,
                burstPolicy: BurstPolicy = .standard) {
        self.scheduler = scheduler
        self.playSound = playSound
        self.speak = speak
        self.playAndSpeak = playAndSpeak
        self.runShortcut = runShortcut
        self.updatePanel = updatePanel
        self.recordSummary = recordSummary
        self.retired = retired
        self.beginPowerAssertion = beginPowerAssertion
        self.endPowerAssertion = endPowerAssertion
        self.silenceIfIdle = silenceIfIdle
        self.stalenessThreshold = stalenessThreshold
        self.burst = burstPolicy
        lastWall = scheduler.now()
        lastAwake = scheduler.awakeTime()
    }

    // MARK: - What the menu and panel read

    /// How many escalations are held: for tests of forgetting, which keeps a
    /// copy of a notification only as long as its escalation needs it.
    var trackedCount: Int { escalations.count }

    /// What the coordinator keeps of one escalation beside its summary, for
    /// tests of that record before any decision reads it (M5 plan, Task 5).
    /// Internal and read-only: nothing outside the core asks, because what a
    /// match that joins is told is decided here.
    struct Bookkeeping: Equatable {
        let ruleID: UUID
        let tier1Outcome: AlertOutcome?
        /// Noted on both clocks: see `Stamp`.
        let lastMatchAt: Stamp
        let lastShortcutRunAt: Stamp?
        /// On the awake clock: see `Running.repeatDue`.
        let repeatDue: TimeInterval?
        let owedPage: CapturedNotification?
    }

    /// nil for an escalation that is not held: one never begun, and one
    /// retired.
    func bookkeeping(of id: EscalationID) -> Bookkeeping? {
        guard let running = escalations[id] else { return nil }
        return Bookkeeping(ruleID: running.ruleID, tier1Outcome: running.tier1Outcome,
                           lastMatchAt: running.lastMatchAt, lastShortcutRunAt: running.lastShortcutRunAt,
                           repeatDue: running.repeatDue, owedPage: running.owedPage)
    }

    /// Live or capped: something is still escalating.
    public var hasLiveEscalations: Bool { escalations.values.contains { $0.isEscalating } }

    /// Whether any escalation still has a tier to fire, which is all the
    /// power assertion exists to protect (ruling 15).
    public var hasPendingTiers: Bool {
        escalations.values.contains { $0.isEscalating && !$0.timers.isEmpty }
    }

    /// Live, capped, and missed but not yet acknowledged, newest first: what
    /// the menu lists. Its Acknowledge item ends exactly the ones it listed,
    /// through `acknowledge(ids:)`.
    public var listedSummaries: [(EscalationID, EscalationSummary)] {
        escalations.filter { $0.value.isListed }
            .sorted { $0.value.order > $1.value.order }
            .map { ($0.key, $0.value.summary) }
    }

    // MARK: - Starting

    /// Starts the ladder of a rule whose tier 1 has just sounded, from the
    /// Inspector row `entryID`. Each tier's timer runs from now, independently
    /// of the others (ruling 9). Returns nil for a rule with no ladder.
    ///
    /// - Parameter tier1Outcome: what tier 1 did, which a match that joins
    ///   this escalation will need to know to judge whether anything audible
    ///   has been heard from it (M5 plan, Ruling 14). It has no default, so no
    ///   caller can forget it, and nil says the caller cannot show that
    ///   anything was heard, which is read as nothing having been.
    @discardableResult
    public func begin(rule: Rule, notification: CapturedNotification, entryID: UUID,
                      tier1Outcome: AlertOutcome?) -> EscalationID? {
        guard let ladder = rule.escalation else { return nil }
        // Anything still running from before a sleep is dealt with first, and
        // the clocks are read afresh, so this one is measured from now.
        checkForSleep()

        let id = EscalationID()
        let now = scheduler.now()
        begun += 1
        escalations[id] = Running(
            entryID: entryID, ruleID: rule.id, ladder: ladder, notification: notification,
            tier1Outcome: tier1Outcome, order: begun,
            summary: EscalationSummary(ruleName: rule.name, startedAt: now, repeatCap: ladder.tier3?.maxRepeats),
            lastMatchAt: stamp(at: now))
        if let tier2 = ladder.tier2 { arm(.panel, for: id, after: tier2.delaySeconds) }
        if let tier3 = ladder.tier3 {
            if tier3.timeLimitAllowsRepeat(number: 1) {
                arm(.repeating, for: id, after: tier3.intervalSeconds)
            } else {
                // A time limit shorter than one interval allows no repeat.
                escalations[id]?.summary.status = .capped(at: now)
            }
        }
        if let tier4 = ladder.tier4 { arm(.final, for: id, after: tier4.afterSeconds) }
        changed(id)
        return id
    }

    // MARK: - Joining

    /// Whether a match for `rule` joins an escalation already running for it, so
    /// that a burst is one escalation (M5 plan, Ruling 14, O11). It is asked
    /// before tier 1 and only of a match no snooze held, and nil means "begin an
    /// escalation, as a match always did": the caller then plays tier 1 and
    /// calls `begin`. A value means the match is counted and this has dealt
    /// with it, and the caller plays nothing of its own and begins nothing.
    ///
    /// *What joins.* The newest escalation of this rule, by its id (a name is
    /// not unique), that is live, whose frozen ladder equals the rule's ladder
    /// as it stands now, and that either has its repeat armed, so that the
    /// ladder is itself the burst, or has no tier 3 and was last matched no
    /// longer ago than the quiet gap, which rolls from that match. Never one
    /// that is capped, acknowledged or missed while asleep, never one whose
    /// tier 3 is not armed, and never for a rule with no ladder.
    ///
    /// *What is heard.* The match plays the rule's own first alert, its spoken
    /// line included, through the sound closures tier 3 uses, so that the
    /// player's ownership is the escalation's and Acknowledge All stops it.
    /// It stays silent, and its words are not voiced at all, only when all
    /// four hold: tier 3's next repeat is due within the smaller of one
    /// interval and the silent-join window; that repeat is not the last the
    /// ladder will make, by its repeat limit or its time limit; that repeat
    /// is not itself silent, which a Custom ladder can make it and which is
    /// known to be inaudible; and something audible has been heard from this
    /// escalation without a fault, which the last repeat's outcome says if
    /// there has been one, and otherwise tier 1's (`AlertOutcome.wasHeard`).
    /// Silence needs proof that something audible is about to happen, and the
    /// absence of a failure is not proof (O11a).
    ///
    /// *What is paged.* When tier 4 is a Shortcut that has already run, no run
    /// is pending, and the last run failed or started at least the re-page
    /// time ago, the match runs it again with its own fields, and a page owed
    /// to an older match is no longer owed (O11b). Otherwise it is owed a page:
    /// its notification is kept, replacing an older one, and one `.repage`
    /// timer sends it once the re-page time has passed since the last run
    /// started. A match before tier 4 has run, and any for a ladder whose tier
    /// 4 is an alert, is owed nothing.
    ///
    /// It touches no tier's timer but that one, which it arms only if none is
    /// and cancels when the join itself runs the Shortcut. Anything it calls
    /// out to may call back in, so the count and the time of the match are
    /// written back before the alert sounds, and what is read after it is read
    /// afresh. A match that joined from inside the alert has decided for itself,
    /// and is the newer, so this one then decides nothing about the Shortcut: it
    /// would otherwise be owed a page over the newer match's, with the older
    /// match's fields.
    public func join(rule: Rule, notification: CapturedNotification) -> EscalationJoin? {
        checkForSleep()
        guard let ladder = rule.escalation, let id = joinable(ruleID: rule.id, ladder: ladder),
              var running = escalations[id] else { return nil }

        running.summary.matchCount += 1
        running.lastMatchAt = stamp(at: scheduler.now())
        let matchNumber = running.summary.matchCount
        let staysSilent = aRepeatStandsInForTheAlert(of: running)
        escalations[id] = running

        var alert: AlertOutcome?
        if !staysSilent {
            alert = rule.alert.map { run($0, for: notification) } ?? .noAlertSet
        }

        // The alert may have been the moment someone acknowledged it. What the
        // escalation is now, and whether it is still held, is read again.
        guard var current = escalations[id] else {
            publish()
            return EscalationJoin(matchNumber: matchNumber, alert: alert, ranShortcut: false)
        }
        var ranShortcut = false
        var shortcutToRun: String?
        // A later match that joined during the alert has already run the
        // Shortcut or been owed a page, with its own fields, which are the
        // newest: this one is covered by it, and owes nothing (Ruling 14).
        if current.isEscalating, current.summary.matchCount == matchNumber,
           let name = current.ladder.tier4?.action.shortcutName,
           let lastRun = current.lastShortcutRunAt {
            if mayRunTheShortcutAgain(current) {
                // This match's page is the newest, so a page owed to an older
                // match is no longer owed: the Shortcut is about to be run for
                // one that came after it.
                cancelRepage(of: &current)
                beginRun(of: &current)
                escalations[id] = current
                shortcutToRun = name
                ranShortcut = true
            } else {
                // Tier 4 has run, and this match may not run it again, because
                // a run is pending or the last started less than the re-page
                // time ago and did not fail: it is owed a page (O11b). Kept in
                // memory, replacing an older one, and sent when the re-page
                // time is up, so the last incident of a burst is never left
                // unpaged however long nothing matches after it. The one timer
                // is armed if none is, from when the last run started, or at
                // once if that was long enough ago, as with a run still
                // pending.
                current.owedPage = notification
                escalations[id] = current
                if current.timers[.repage] == nil {
                    let sinceRun = lastRun.elapsed(wall: scheduler.now(), awake: scheduler.awakeTime())
                    arm(.repage, for: id, after: max(0.0, burst.repageTime - sinceRun))
                }
            }
        }
        changed(id)
        if let name = shortcutToRun {
            // Recorded when it reports, however late, as tier 4's run is.
            startShortcut(name, for: notification, of: id)
        }
        return EscalationJoin(matchNumber: matchNumber, alert: alert, ranShortcut: ranShortcut)
    }

    /// The newest escalation a match for this rule joins, if any.
    private func joinable(ruleID: UUID, ladder: Escalation) -> EscalationID? {
        let wall = scheduler.now()
        let awake = scheduler.awakeTime()
        return escalations.filter { entry in
            let running = entry.value
            guard running.ruleID == ruleID, running.summary.status == .live, running.ladder == ladder else {
                return false
            }
            if running.timers[.repeating] != nil { return true }
            return running.ladder.tier3 == nil
                && running.lastMatchAt.elapsed(wall: wall, awake: awake) <= burst.quietGap
        }.max { $0.value.order < $1.value.order }?.key
    }

    /// Whether tier 3's next repeat stands in for the alert of a match that
    /// joins now: due soon, not the last, not silent, and something audible
    /// was heard without a fault. All four, or the match plays its own (O11a).
    private func aRepeatStandsInForTheAlert(of running: Running) -> Bool {
        guard let tier3 = running.ladder.tier3, let due = running.repeatDue else { return false }
        // A silent repeat repeats nothing. Before the first has fired, tier 1's
        // outcome is all there is to judge by, and it says nothing of this.
        guard tier3.action != .silent else { return false }
        // The awake clock, which the due time is on.
        guard due - scheduler.awakeTime() <= min(tier3.intervalSeconds, burst.silentJoinWindow) else { return false }
        // The next repeat is the one after those that have fired. After the last,
        // nothing would sound for this match: by the count, and by the time.
        let next = running.summary.repeatCount + 1
        if let limit = tier3.maxRepeats, next >= limit { return false }
        guard tier3.timeLimitAllowsRepeat(number: next + 1) else { return false }
        return (running.summary.lastRepeat ?? running.tier1Outcome)?.wasHeard == true
    }

    /// Whether a match that joins now runs the Shortcut again: tier 4 has
    /// already run it, no run is pending, and the last run failed, which a match
    /// retries at once so that a page that did not go does not wait for the
    /// re-page time, or it started at least the re-page time ago. When it is
    /// not allowed to, and tier 4 has run, the match is owed a page instead.
    private func mayRunTheShortcutAgain(_ running: Running) -> Bool {
        guard !running.shortcutPending, let lastRun = running.lastShortcutRunAt else { return false }
        if case .shortcutFailed = running.summary.final { return true }
        return lastRun.elapsed(wall: scheduler.now(), awake: scheduler.awakeTime()) >= burst.repageTime
    }

    // MARK: - Acknowledging

    /// Ends one escalation: its remaining tiers are cancelled and its row
    /// leaves the panel. Sound already playing is stopped only once nothing
    /// else is escalating, because the player cannot tell whose sound it is
    /// (ruling 8). That is not the same as nothing else playing: a rule with
    /// no ladder sounds through the same player, and the coordinator cannot
    /// see it, so the app decides whether a stop would cut one off (Task 5).
    /// A missed escalation is only marked seen: it has no sound of its own,
    /// so stopping one could only cut off something later.
    public func acknowledge(_ id: EscalationID) {
        guard let wasEscalating = acknowledgeOne(id) else { return }
        publish()
        if wasEscalating, !hasLiveEscalations { silenceIfIdle() }
    }

    /// Ends every listed escalation, missed ones included, and then stops the
    /// sound playing: the hotkey's gesture that ends every escalation at once,
    /// one begun after a menu was opened included (rulings 8 and 16). The
    /// menu's Acknowledge item ends only what it listed. With nothing listed
    /// it does nothing, so a stray press of the hotkey never cuts off an
    /// ordinary alert.
    public func acknowledgeAll() {
        let listed = listedSummaries.map(\.0)
        guard !listed.isEmpty else { return }
        for id in listed { _ = acknowledgeOne(id) }
        publish()
        silenceIfIdle()
    }

    /// Ends the escalations named, and nothing that began since they were
    /// listed (M5 plan, Ruling 22): what a menu held open acts on, since capture
    /// runs while it is open and an escalation can begin in the seconds it is
    /// held. Its item still reads Acknowledge All (N) for the set it listed, and
    /// ending one the user never saw, which under a silent first tier has not
    /// even been heard, is what that click must not do. The one that began later
    /// keeps its timers, its sound and its place in the listing.
    ///
    /// Each id is handled as `acknowledge(_:)` handles it: one already
    /// acknowledged and one this does not know do nothing, and a missed
    /// escalation is only marked seen. The sound playing is stopped only when
    /// one of those ended was still escalating and none is left live, as it is
    /// for a single id and for `acknowledgeAll()`, which is unchanged and is
    /// for the hotkey: the panel shows what it acts on.
    public func acknowledge(ids: Set<EscalationID>) {
        // Newest first, as `acknowledgeAll()` ends them, whatever order the
        // set holds.
        let known = ids.compactMap { id in escalations[id].map { (id, $0.order) } }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
        var acknowledgedOne = false
        var endedOneEscalating = false
        for id in known {
            guard let wasEscalating = acknowledgeOne(id) else { continue }
            acknowledgedOne = true
            endedOneEscalating = endedOneEscalating || wasEscalating
        }
        guard acknowledgedOne else { return }
        publish()
        if endedOneEscalating, !hasLiveEscalations { silenceIfIdle() }
    }

    /// Returns whether it was still escalating, or nil if there was nothing
    /// to acknowledge. Records, but leaves the panel and power to the caller.
    private func acknowledgeOne(_ id: EscalationID) -> Bool? {
        guard var running = escalations[id] else { return nil }
        let now = scheduler.now()
        let wasEscalating: Bool
        switch running.summary.status {
        case .live, .capped:
            cancelTimers(of: &running)
            running.summary.status = .acknowledged(at: now)
            wasEscalating = true
        case .missedWhileAsleep(let convertedAt, nil):
            running.summary.status = .missedWhileAsleep(convertedAt: convertedAt, acknowledgedAt: now)
            wasEscalating = false
        case .acknowledged, .missedWhileAsleep:
            return nil
        }
        escalations[id] = running
        recordSummary(running.entryID, running.summary)
        retireIfDone(id)
        return wasEscalating
    }

    // MARK: - Sleep

    /// How long the Mac slept since the last check is the wall time elapsed
    /// less the awake time elapsed. Past the threshold, every escalation still
    /// going is ended as missed while asleep, rather than resumed on waking
    /// with alarms hours stale (ruling 14). A stall of the main thread is not
    /// a sleep: both clocks move together, and nothing converts.
    ///
    /// Called first by every tier's timer, and by the app when the system
    /// wakes — the system, not the display, which sleeps on its own.
    public func checkForSleep() {
        let wall = scheduler.now()
        let awake = scheduler.awakeTime()
        let slept = wall.timeIntervalSince(lastWall) - (awake - lastAwake)
        lastWall = wall
        lastAwake = awake
        guard slept > stalenessThreshold else { return }

        var converted = false
        for id in Array(escalations.keys) {
            // Read afresh each time: recording one may have changed another.
            guard var running = escalations[id], running.isEscalating else { continue }
            cancelTimers(of: &running)
            running.summary.status = .missedWhileAsleep(convertedAt: wall, acknowledgedAt: nil)
            escalations[id] = running
            recordSummary(running.entryID, running.summary)
            converted = true
        }
        if converted { publish() }
    }

    // MARK: - The tiers

    private func arm(_ tier: Tier, for id: EscalationID, after seconds: TimeInterval) {
        tickets += 1
        let ticket = tickets
        // Taken before the timer is made, so it is the time the timer counts from.
        let due = scheduler.awakeTime() + seconds
        let token = scheduler.schedule(after: seconds) { [weak self] in
            self?.fire(tier, of: id, ticket: ticket)
        }
        escalations[id]?.timers[tier] = (token, ticket, due)
    }

    /// `now`, which the caller has read, with the awake clock beside it.
    private func stamp(at now: Date) -> Stamp {
        Stamp(wall: now, awake: scheduler.awakeTime())
    }

    /// Every timer, the re-page's with the rest, and the page it would have
    /// sent: an escalation that is acknowledged or converted owes nothing.
    private func cancelTimers(of running: inout Running) {
        for (token, _, _) in running.timers.values { scheduler.cancel(token) }
        running.timers = [:]
        running.owedPage = nil
    }

    /// The re-page timer alone, and the page it would have sent: the others go
    /// on. Used where the Shortcut is run for a match that is no longer owed a
    /// page: a newer match's, in a join, or the owed page itself after a run has
    /// failed, in `shortcutReported`.
    private func cancelRepage(of running: inout Running) {
        if let timer = running.timers[.repage] { scheduler.cancel(timer.token) }
        running.timers[.repage] = nil
        running.owedPage = nil
    }

    /// A Shortcut run is starting: one is pending until it reports, and when it
    /// started is what a re-page time is counted from.
    private func beginRun(of running: inout Running) {
        running.shortcutPending = true
        running.lastShortcutRunAt = stamp(at: scheduler.now())
    }

    /// Runs the Shortcut with a notification's fields. Recorded when it reports,
    /// however late, even if the escalation has ended since; nothing waits for it.
    private func startShortcut(_ name: String, for notification: CapturedNotification, of id: EscalationID) {
        runShortcut(name, notification) { [weak self] outcome in
            self?.shortcutReported(outcome, for: id)
        }
    }

    /// Every tier starts the same way: a sleep is looked for first, and the
    /// tier acts only if its escalation is still going and this is still the
    /// timer it is waiting on. A cancelled timer does not run, but one already
    /// on its way when an acknowledgement came would; this check is what
    /// keeps it quiet, in case the timers are ever reached through a hop
    /// (ruling 2).
    private func fire(_ tier: Tier, of id: EscalationID, ticket: Int) {
        checkForSleep()
        guard var running = escalations[id], running.isEscalating,
              running.timers[tier]?.ticket == ticket else { return }
        running.timers[tier] = nil
        let now = scheduler.now()

        switch tier {
        case .panel:
            running.panelShown = true
            running.summary.tierReached = max(running.summary.tierReached, 2)
            escalations[id] = running

        case .repeating:
            guard let tier3 = running.ladder.tier3 else { break }
            running.summary.repeatCount += 1
            running.summary.tierReached = max(running.summary.tierReached, 3)
            let count = running.summary.repeatCount
            escalations[id] = running
            let outcome = run(tier3.action, for: running.notification)
            // The sound may have been the moment someone acknowledged it.
            guard escalations[id] != nil else { return publish() }
            escalations[id]?.summary.lastRepeat = outcome
            guard escalations[id]?.isEscalating == true else { break }
            if let cap = tier3.maxRepeats, count >= cap {
                escalations[id]?.summary.status = .capped(at: now)
            } else if tier3.timeLimitAllowsRepeat(number: count + 1) {
                arm(.repeating, for: id, after: tier3.intervalSeconds)
            } else {
                escalations[id]?.summary.status = .capped(at: now)
            }

        case .final:
            guard let tier4 = running.ladder.tier4 else { break }
            running.summary.tierReached = 4
            switch tier4.action {
            case .alert(let alert):
                escalations[id] = running
                let outcome = run(alert, for: running.notification)
                guard escalations[id] != nil else { return publish() }
                escalations[id]?.summary.final = .alerted(outcome)
            case .shortcut(let name):
                beginRun(of: &running)
                escalations[id] = running
                changed(id)
                startShortcut(name, for: running.notification, of: id)
                return
            }

        case .repage:
            // Armed with the page it sends, and cleared with it. Every way out
            // writes the escalation back first: what follows calls out, and
            // reads again after.
            guard let owed = running.owedPage, let name = running.ladder.tier4?.action.shortcutName else {
                escalations[id] = running
                break
            }
            if running.shortcutPending {
                // A run is still out, and a second is never started beside it:
                // look again shortly, until it has reported.
                escalations[id] = running
                arm(.repage, for: id, after: Self.pendingRunRetry)
                break
            }
            running.owedPage = nil
            beginRun(of: &running)
            escalations[id] = running
            changed(id)
            startShortcut(name, for: owed, of: id)
            return
        }
        changed(id)
    }

    /// A run has reported. Its outcome replaces the last, and when it is a
    /// failure and a page is owed, that page is run at once, once, rather than
    /// when the re-page time is up: a page that did not go is not made to wait
    /// behind one that has failed (M5 plan, Ruling 14, O11b). The runner has
    /// reported by now, so nothing is pending beside it. As it decides, it
    /// looks for a sleep first, as a join and every timer do: a report that
    /// lands after the Mac has slept, before the app's wake step has converted
    /// the escalation, finds it converted and a page that is no longer owed, and
    /// only records the outcome.
    private func shortcutReported(_ outcome: FinalOutcome, for id: EscalationID) {
        checkForSleep()
        guard var running = escalations[id] else { return }
        running.shortcutPending = false
        running.summary.final = outcome
        if case .shortcutFailed = outcome, let owed = running.owedPage,
           let name = running.ladder.tier4?.action.shortcutName {
            cancelRepage(of: &running)
            beginRun(of: &running)
            escalations[id] = running
            changed(id)
            startShortcut(name, for: owed, of: id)
            return
        }
        escalations[id] = running
        changed(id)
    }

    private func run(_ alert: AlertAction, for notification: CapturedNotification) -> AlertOutcome {
        AlertActionRunner.run(alert, for: notification, playSound: playSound, speak: speak,
                              playAndSpeak: playAndSpeak)
    }

    // MARK: - Telling the app

    /// One escalation changed: its Inspector row, then the panel and power.
    private func changed(_ id: EscalationID) {
        if let running = escalations[id] { recordSummary(running.entryID, running.summary) }
        retireIfDone(id)
        publish()
    }

    /// The panel lists what is listed and has shown its tier 2, newest first;
    /// an empty list hides it. The power assertion is held exactly while a
    /// tier is still to fire.
    private func publish() {
        updatePanel(escalations.filter { $0.value.isListed && $0.value.panelShown }
            .sorted { $0.value.order > $1.value.order }
            .map { ($0.key, $0.value.summary) })

        let pending = hasPendingTiers
        if pending, !assertionHeld {
            assertionHeld = true
            beginPowerAssertion()
        } else if !pending, assertionHeld {
            assertionHeld = false
            endPowerAssertion()
        }
    }

    /// Forgets an escalation nobody can see or act on any more, once a
    /// Shortcut it started has reported, so a long-running app does not keep
    /// every escalation it ever ran. Nothing more is recorded for its row
    /// after, which the app is told.
    private func retireIfDone(_ id: EscalationID) {
        guard let running = escalations[id], !running.isListed, !running.shortcutPending else { return }
        escalations[id] = nil
        retired(running.entryID)
    }
}
