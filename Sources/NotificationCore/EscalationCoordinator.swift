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
    public var final: FinalOutcome?

    public init(ruleName: String, startedAt: Date, status: Status = .live, tierReached: Int = 1,
                repeatCount: Int = 0, repeatCap: Int? = nil, lastRepeat: AlertOutcome? = nil,
                final: FinalOutcome? = nil) {
        self.ruleName = ruleName
        self.startedAt = startedAt
        self.status = status
        self.tierReached = tierReached
        self.repeatCount = repeatCount
        self.repeatCap = repeatCap
        self.lastRepeat = lastRepeat
        self.final = final
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

    private enum Tier: Hashable { case panel, repeating, final }

    private struct Running {
        let entryID: UUID
        let ladder: Escalation
        let notification: CapturedNotification
        let order: Int
        var summary: EscalationSummary
        var panelShown = false
        var timers: [Tier: (token: EscalationTimerToken, ticket: Int)] = [:]
        var shortcutPending = false

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
                stalenessThreshold: TimeInterval = EscalationCoordinator.defaultStalenessThreshold) {
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
        lastWall = scheduler.now()
        lastAwake = scheduler.awakeTime()
    }

    // MARK: - What the menu and panel read

    /// How many escalations are held: for tests of forgetting, which keeps a
    /// copy of a notification only as long as its escalation needs it.
    var trackedCount: Int { escalations.count }

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
    @discardableResult
    public func begin(rule: Rule, notification: CapturedNotification, entryID: UUID) -> EscalationID? {
        guard let ladder = rule.escalation else { return nil }
        // Anything still running from before a sleep is dealt with first, and
        // the clocks are read afresh, so this one is measured from now.
        checkForSleep()

        let id = EscalationID()
        begun += 1
        escalations[id] = Running(
            entryID: entryID, ladder: ladder, notification: notification, order: begun,
            summary: EscalationSummary(ruleName: rule.name, startedAt: scheduler.now(),
                                       repeatCap: ladder.tier3?.maxRepeats))
        if let tier2 = ladder.tier2 { arm(.panel, for: id, after: tier2.delaySeconds) }
        if let tier3 = ladder.tier3 {
            if tier3.timeLimitAllowsRepeat(number: 1) {
                arm(.repeating, for: id, after: tier3.intervalSeconds)
            } else {
                // A time limit shorter than one interval allows no repeat.
                escalations[id]?.summary.status = .capped(at: scheduler.now())
            }
        }
        if let tier4 = ladder.tier4 { arm(.final, for: id, after: tier4.afterSeconds) }
        changed(id)
        return id
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
        let token = scheduler.schedule(after: seconds) { [weak self] in
            self?.fire(tier, of: id, ticket: ticket)
        }
        escalations[id]?.timers[tier] = (token, ticket)
    }

    private func cancelTimers(of running: inout Running) {
        for (token, _) in running.timers.values { scheduler.cancel(token) }
        running.timers = [:]
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
                running.shortcutPending = true
                escalations[id] = running
                changed(id)
                // Recorded when it reports, however late, even if the
                // escalation has ended since; nothing waits for it.
                runShortcut(name, running.notification) { [weak self] outcome in
                    self?.shortcutReported(outcome, for: id)
                }
                return
            }
        }
        changed(id)
    }

    private func shortcutReported(_ outcome: FinalOutcome, for id: EscalationID) {
        guard var running = escalations[id] else { return }
        running.shortcutPending = false
        running.summary.final = outcome
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
