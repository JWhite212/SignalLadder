import XCTest
@testable import NotificationCore

final class CaptureRingBufferTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_757_000_000)

    func note(_ app: String, _ title: String = "t", at offset: TimeInterval = 0) -> CapturedNotification {
        CapturedNotification(
            timestamp: t0.addingTimeInterval(offset),
            appNameGuess: app,
            title: title,
            subtitle: "",
            body: "b",
            rawText: "\(app), \(title), b",
            subrole: "AXNotificationCenterBanner"
        )
    }

    // MARK: - Task 1

    func testAnEntryIsNotEvaluatedUntilSomethingAnnotatesIt() {
        // "Not evaluated" and "matched no rule" must never look the same. The
        // spec names matching nothing as the most common confusion (§7.2), and
        // an unevaluated row claiming "no match" would manufacture exactly it.
        let entry = InspectorEntry(captured: note("Teams"),
                                   context: ContextSnapshot(date: t0, recentCountForApp: 1),
                                   suppressedRepeatCount: 0)
        XCTAssertNil(entry.annotation)
    }

    func testAnEntryCanBeAnnotatedAfterCreation() {
        // M3's RuleEngine annotates rows that already exist in the buffer.
        var entry = InspectorEntry(captured: note("Teams"),
                                   context: ContextSnapshot(date: t0, recentCountForApp: 1),
                                   suppressedRepeatCount: 0)
        entry.annotation = MatchAnnotation(ruleName: "On-call mentions", warnings: [])
        XCTAssertEqual(entry.annotation?.ruleName, "On-call mentions")
    }

    func testAnAnnotationWithNoRuleNameMeansEvaluatedAndMatchedNothing() {
        var entry = InspectorEntry(captured: note("Weather"),
                                   context: ContextSnapshot(date: t0, recentCountForApp: 1),
                                   suppressedRepeatCount: 0)
        entry.annotation = MatchAnnotation(ruleName: nil, warnings: [])
        XCTAssertNotNil(entry.annotation, "evaluated")
        XCTAssertNil(entry.annotation?.ruleName, "matched nothing")
    }

    func testUnderCountingDefaultsToFalse() {
        let context = ContextSnapshot(date: t0, recentCountForApp: 3)
        XCTAssertFalse(context.recentCountIsUnderCounted)
    }

    // MARK: - Task 2

    func testEntriesComeBackNewestFirst() {
        let buffer = CaptureRingBuffer()
        buffer.record(note("A", "first", at: 0), suppressedRepeatCount: 0)
        buffer.record(note("B", "second", at: 10), suppressedRepeatCount: 0)
        XCTAssertEqual(buffer.entries.map(\.captured.title), ["second", "first"])
    }

    func testOldestEntriesAreEvictedAtCapacity() {
        let buffer = CaptureRingBuffer(capacity: 3)
        for i in 0..<5 {
            buffer.record(note("A", "n\(i)", at: TimeInterval(i)), suppressedRepeatCount: 0)
        }
        XCTAssertEqual(buffer.count, 3)
        XCTAssertEqual(buffer.entries.map(\.captured.title), ["n4", "n3", "n2"])
    }

    func testRecentCountCountsOnlyTheSameApp() {
        let buffer = CaptureRingBuffer()
        buffer.record(note("Teams", at: 0), suppressedRepeatCount: 0)
        buffer.record(note("Weather", at: 1), suppressedRepeatCount: 0)
        let entry = buffer.record(note("Teams", at: 2), suppressedRepeatCount: 0)
        XCTAssertEqual(entry.context.recentCountForApp, 2, "the two Teams notifications, not the Weather one")
    }

    func testRecentCountExcludesAnythingOlderThanTheWindow() {
        let buffer = CaptureRingBuffer(recentWindow: 3600)
        buffer.record(note("Teams", at: 0), suppressedRepeatCount: 0)
        let entry = buffer.record(note("Teams", at: 7200), suppressedRepeatCount: 0)
        XCTAssertEqual(entry.context.recentCountForApp, 1, "two hours later, the first is out of the window")
    }

    func testRecentCountIncludesTheNotificationBeingRecorded() {
        let buffer = CaptureRingBuffer()
        let entry = buffer.record(note("Teams", at: 0), suppressedRepeatCount: 0)
        XCTAssertEqual(entry.context.recentCountForApp, 1)
    }

    func testRecentCountIsFlaggedAsAFloorWhenTheBufferOverflowsInsideTheWindow() {
        // A noisy channel can overflow the buffer inside the hour. The count is
        // then "at least this many" — and reporting a floor as a total would
        // understate exactly the volume the user is trying to see.
        let buffer = CaptureRingBuffer(capacity: 3, recentWindow: 3600)
        for i in 0..<4 {
            buffer.record(note("Teams", at: TimeInterval(i)), suppressedRepeatCount: 0)
        }
        XCTAssertTrue(buffer.entries.first!.context.recentCountIsUnderCounted)
    }

    func testRecentCountIsNotFlaggedWhenTheOldestEntryPredatesTheWindow() {
        // Full buffer, but the evicted entries were outside the window anyway,
        // so nothing countable was lost and the total is exact.
        let buffer = CaptureRingBuffer(capacity: 3, recentWindow: 60)
        for i in 0..<4 {
            buffer.record(note("Teams", at: TimeInterval(i) * 1000), suppressedRepeatCount: 0)
        }
        XCTAssertFalse(buffer.entries.first!.context.recentCountIsUnderCounted)
    }

    func testEvictingAnotherAppsEntryDoesNotMakeThisAppsCountAFloor() {
        // The gap that let the bug through: every overflow test used a single
        // app, so nothing exercised eviction across apps. With a full buffer
        // SOME app's oldest entry is nearly always inside the window, so a flag
        // that ignores which app was evicted is permanently on — and a hedge
        // that never varies tells the user nothing.
        let buffer = CaptureRingBuffer(capacity: 3, recentWindow: 3600)
        buffer.record(note("Weather", at: 0), suppressedRepeatCount: 0)
        buffer.record(note("Teams", at: 1), suppressedRepeatCount: 0)
        buffer.record(note("Teams", at: 2), suppressedRepeatCount: 0)

        // Full buffer. This evicts the Weather entry, so no Teams history is
        // lost and the Teams count is exact.
        let entry = buffer.record(note("Teams", at: 3), suppressedRepeatCount: 0)

        XCTAssertEqual(entry.context.recentCountForApp, 3)
        XCTAssertFalse(entry.context.recentCountIsUnderCounted,
                       "nothing countable was lost — the evicted entry was a different app")
    }

    func testEvictingThisAppsOwnEntryStillMakesTheCountAFloor() {
        // The complement, so the fix cannot be "always false".
        let buffer = CaptureRingBuffer(capacity: 3, recentWindow: 3600)
        buffer.record(note("Teams", at: 0), suppressedRepeatCount: 0)
        buffer.record(note("Weather", at: 1), suppressedRepeatCount: 0)
        buffer.record(note("Teams", at: 2), suppressedRepeatCount: 0)

        let entry = buffer.record(note("Teams", at: 3), suppressedRepeatCount: 0)

        XCTAssertTrue(entry.context.recentCountIsUnderCounted,
                      "a Teams entry inside the window was evicted, so the count is a floor")
    }

    func testSuppressedRepeatsAreRecordedOnTheEntry() {
        let buffer = CaptureRingBuffer()
        let entry = buffer.record(note("Teams"), suppressedRepeatCount: 4)
        XCTAssertEqual(entry.suppressedRepeatCount, 4)
    }

    func testAnnotatingFindsTheRowByIdentity() {
        let buffer = CaptureRingBuffer()
        let first = buffer.record(note("A", "first", at: 0), suppressedRepeatCount: 0)
        buffer.record(note("B", "second", at: 1), suppressedRepeatCount: 0)

        buffer.annotate(id: first.id, with: MatchAnnotation(ruleName: "Rule X"))

        XCTAssertEqual(buffer.entries.last?.annotation?.ruleName, "Rule X")
        XCTAssertNil(buffer.entries.first?.annotation, "the other row is untouched")
    }

    func testAnnotatingAnEvictedRowIsHarmless() {
        // A slow evaluator can return after its row has aged out. Dropping the
        // annotation is correct; crashing or annotating the wrong row is not.
        let buffer = CaptureRingBuffer(capacity: 1)
        let first = buffer.record(note("A", at: 0), suppressedRepeatCount: 0)
        buffer.record(note("B", at: 1), suppressedRepeatCount: 0)

        buffer.annotate(id: first.id, with: MatchAnnotation(ruleName: "Rule X"))

        XCTAssertNil(buffer.entries.first?.annotation)
    }

    // MARK: - Task 4 — empty-state wording

    func testEmptyAndHealthySaysItIsSimplyQuiet() {
        // `?? ""` rather than force-unwrap: if the function ever regressed to
        // returning nil here, an empty string still fails these assertions
        // instead of crashing the test run.
        let message = InspectorEmptyState.message(isEmpty: true, health: .verified, healthSummary: "Working — verified") ?? ""
        XCTAssertTrue(message.contains("quiet"), message)
        XCTAssertFalse(message.contains("cannot"), message)
    }

    func testEmptyAndUnverifiedDoesNotClaimCaptureIsWorking() {
        // The reason this function takes CaptureHealth and not a Bool.
        // `isAlarming` maps .unknown and .verified both to false, so reduced to
        // that Bool an app that had verified nothing read as one that had
        // verified everything — and the window said so in as many words.
        let message = InspectorEmptyState.message(isEmpty: true, health: .unknown, healthSummary: "Checking…") ?? ""
        XCTAssertFalse(message.contains("quiet"),
                       "an unverified app must not tell the user things are simply quiet: \(message)")
        XCTAssertFalse(message.contains("verified working"), message)
        XCTAssertTrue(message.contains("no recent confirmation"), message)
    }

    func testEmptyWithStaleEvidenceStaysTrueAboutThePast() {
        // Unknown also means a self-test once passed and its evidence has aged
        // out. The message must not deny that one ever did.
        let message = InspectorEmptyState.message(
            isEmpty: true, health: .unknown,
            healthSummary: "Unverified — last verified 34 min ago") ?? ""
        XCTAssertFalse(message.contains("not yet"), message)
        XCTAssertFalse(message.contains("quiet"), message)
        XCTAssertTrue(message.contains("last verified 34 min ago"), message)
    }

    func testAnAlarmingEmptyStateNamesTheCauseAndNotJustTheState() {
        // The window is meant to be self-sufficient about WHY. Without the
        // advice it said "cannot confirm it is capturing / Cannot verify
        // itself" for a Focus, a revoked permission and a blind accessibility
        // path alike — identical words for opposite problems, while the app
        // held the specific cause the whole time.
        let message = InspectorEmptyState.message(
            isEmpty: true,
            health: .degraded([.selfTestAlertNeverSeen]),
            healthSummary: "Cannot verify itself",
            advice: HealthCause.selfTestAlertNeverSeen.advice
        ) ?? ""
        XCTAssertTrue(message.contains("Do Not Disturb"), message)
        XCTAssertTrue(message.contains("Full Keyboard Access"), message)
    }

    func testTwoDifferentCausesDoNotProduceTheSameEmptyState() {
        let suppressed = InspectorEmptyState.message(
            isEmpty: true, health: .degraded([.notificationsSuppressed]),
            healthSummary: "Cannot verify itself",
            advice: HealthCause.notificationsSuppressed.advice)
        let denied = InspectorEmptyState.message(
            isEmpty: true, health: .degraded([.notificationPermissionDenied]),
            healthSummary: "Cannot verify itself",
            advice: HealthCause.notificationPermissionDenied.advice)
        XCTAssertNotEqual(suppressed, denied,
                          "two different faults must not read identically")
    }

    func testTheThreeEmptyStatesAreAllDifferent() {
        // Guards against a future edit collapsing two branches back together.
        let verified = InspectorEmptyState.message(isEmpty: true, health: .verified, healthSummary: "s")
        let unknown = InspectorEmptyState.message(isEmpty: true, health: .unknown, healthSummary: "s")
        let blind = InspectorEmptyState.message(isEmpty: true, health: .blind([.observerNotAttached]), healthSummary: "s")
        XCTAssertNotEqual(verified, unknown)
        XCTAssertNotEqual(unknown, blind)
        XCTAssertNotEqual(verified, blind)
    }

    func testEmptyAndAlarmingSaysCaptureIsUnproven() {
        // The whole point. An empty list under Do Not Disturb looks exactly
        // like an idle Tuesday, and M2b's live run proved the app meets that
        // situation in practice.
        let message = InspectorEmptyState.message(isEmpty: true,
                                                  health: .degraded([.notificationsSuppressed]),
                                                  healthSummary: "Cannot verify itself") ?? ""
        XCTAssertTrue(message.contains("Cannot verify itself"), message)
        XCTAssertFalse(message.contains("quiet"), message)
    }

    func testNonEmptyHasNoEmptyStateMessage() {
        XCTAssertNil(InspectorEmptyState.message(isEmpty: false, health: .blind([.observerNotAttached]), healthSummary: "x"))
    }

    // MARK: - Suppressed repeats land on the row they duplicate

    func testASuppressedRepeatIsCountedOnTheRowItDuplicates() {
        let buffer = CaptureRingBuffer()
        buffer.record(note("Teams", "ping", at: 0), suppressedRepeatCount: 0)

        XCTAssertTrue(buffer.noteSuppressedRepeat(matching: note("Teams", "ping").rawText))
        XCTAssertTrue(buffer.noteSuppressedRepeat(matching: note("Teams", "ping").rawText))

        XCTAssertEqual(buffer.entries.first?.suppressedRepeatCount, 2)
    }

    func testASuppressedRepeatNeverLandsOnAnUnrelatedNotification() {
        // The misattribution this replaced: a single controller-wide counter
        // with no key, attached to whatever arrived next — so one app's repeat
        // storm could be reported against another app's notification.
        let buffer = CaptureRingBuffer()
        buffer.record(note("Teams", "ping", at: 0), suppressedRepeatCount: 0)
        buffer.record(note("Weather", "rain", at: 1), suppressedRepeatCount: 0)

        buffer.noteSuppressedRepeat(matching: note("Teams", "ping").rawText)

        XCTAssertEqual(buffer.entries.first?.captured.appNameGuess, "Weather")
        XCTAssertEqual(buffer.entries.first?.suppressedRepeatCount, 0, "Weather did not repeat")
        XCTAssertEqual(buffer.entries.last?.suppressedRepeatCount, 1, "Teams did")
    }

    func testASuppressedRepeatWithNoSurvivingRowReportsFailureRatherThanGuessing() {
        let buffer = CaptureRingBuffer(capacity: 1)
        buffer.record(note("Teams", "ping", at: 0), suppressedRepeatCount: 0)
        buffer.record(note("Weather", "rain", at: 1), suppressedRepeatCount: 0)   // evicts Teams

        XCTAssertFalse(buffer.noteSuppressedRepeat(matching: note("Teams", "ping").rawText),
                       "the duplicated row is gone; say so rather than attributing it elsewhere")
        XCTAssertEqual(buffer.entries.first?.suppressedRepeatCount, 0)
    }

    func testTheMostRecentMatchingRowIsTheOneCounted() {
        // Identical text can legitimately appear twice in the buffer once the
        // dedupe window has lapsed between them. The repeat belongs to the
        // sighting it actually followed.
        let buffer = CaptureRingBuffer()
        buffer.record(note("Teams", "ping", at: 0), suppressedRepeatCount: 0)
        buffer.record(note("Teams", "ping", at: 600), suppressedRepeatCount: 0)

        buffer.noteSuppressedRepeat(matching: note("Teams", "ping").rawText)

        XCTAssertEqual(buffer.entries.first?.suppressedRepeatCount, 1, "newest")
        XCTAssertEqual(buffer.entries.last?.suppressedRepeatCount, 0, "older sighting untouched")
    }

    // MARK: - Row wording for rules

    private func entry(annotation: MatchAnnotation? = nil, preview: MatchAnnotation? = nil) -> InspectorEntry {
        InspectorEntry(captured: note("Teams"), context: ContextSnapshot(date: t0, recentCountForApp: 1),
                       suppressedRepeatCount: 0, annotation: annotation, preview: preview)
    }

    func testRowOutcomeDistinguishesNeverEvaluatedFromArrivedWithoutRules() {
        XCTAssertEqual(InspectorRowText.outcome(entry()), "Not evaluated — no rules loaded")
        XCTAssertEqual(InspectorRowText.outcome(entry(preview: MatchAnnotation(ruleName: "X"))),
                       "Arrived while no rules were loaded")
    }

    func testRowOutcomeReportsWhatHappenedNotWhatWouldHappenNow() {
        let row = entry(annotation: MatchAnnotation(ruleName: nil), preview: MatchAnnotation(ruleName: "X"))
        XCTAssertEqual(InspectorRowText.outcome(row), "Matched no rule")
        XCTAssertEqual(InspectorRowText.preview(row), "Current rules would match X")
    }

    func testAPreviewThatAgreesWithWhatHappenedIsNotRepeated() {
        let same = MatchAnnotation(ruleName: "X")
        XCTAssertNil(InspectorRowText.preview(entry(annotation: same, preview: same)))
    }

    func testAPreviewOfNothingIsStatedNotOmitted() {
        let row = entry(annotation: MatchAnnotation(ruleName: "X"), preview: MatchAnnotation(ruleName: nil))
        XCTAssertEqual(InspectorRowText.preview(row), "Current rules would match nothing",
                       "a rule that stopped matching is exactly what someone editing rules needs to see")
    }

    // MARK: - An escalation's trail (M4 Task 3)

    func testAnEscalationIsRecordedOnItsRowAgainAndAgain() {
        // The one record of what was done that changes after the fact.
        let buffer = CaptureRingBuffer()
        let entry = buffer.record(note("Teams"), suppressedRepeatCount: 0)
        var summary = EscalationSummary(ruleName: "On-call mentions", startedAt: t0)
        buffer.setEscalation(id: entry.id, summary)
        summary.repeatCount = 3
        summary.status = .capped(at: t0.addingTimeInterval(90))
        buffer.setEscalation(id: entry.id, summary)
        XCTAssertEqual(buffer.entries.first?.escalation, summary)
        XCTAssertNil(buffer.entries.first?.alertOutcome, "kept apart from the tier 1 outcome")
    }

    func testAnEscalationOnARowThatHasAgedOutIsDropped() {
        let buffer = CaptureRingBuffer(capacity: 1)
        let old = buffer.record(note("Teams"), suppressedRepeatCount: 0)
        buffer.record(note("Weather"), suppressedRepeatCount: 0)
        buffer.setEscalation(id: old.id, EscalationSummary(ruleName: "a", startedAt: t0))
        XCTAssertNil(buffer.entries.first?.escalation)
    }

    func testAnEscalationIsWrittenToItsOwnRowNotTheNewest() {
        // Found by identity, not position: positions shift with every capture.
        let buffer = CaptureRingBuffer()
        let older = buffer.record(note("Teams"), suppressedRepeatCount: 0)
        buffer.record(note("Weather"), suppressedRepeatCount: 0)
        let summary = EscalationSummary(ruleName: "On-call mentions", startedAt: t0)
        buffer.setEscalation(id: older.id, summary)
        XCTAssertNil(buffer.entries[0].escalation)
        XCTAssertEqual(buffer.entries[1].escalation, summary)
    }

    // MARK: - A match that joined an escalation (M5 Task 5)

    func testARowHasJoinedNothingUntilItIsToldItJoinedAnEscalation() {
        let buffer = CaptureRingBuffer()
        let entry = buffer.record(note("Teams"), suppressedRepeatCount: 0)
        XCTAssertNil(entry.joinedMatch)
        buffer.setJoined(id: entry.id, matchNumber: 3)
        XCTAssertEqual(buffer.entries.first?.joinedMatch, 3, "the match's place in the escalation, counting the first as 1")
        XCTAssertNil(buffer.entries.first?.alertOutcome, "kept apart from what the match did")
        XCTAssertNil(buffer.entries.first?.escalation, "and from the escalation's own trail")
    }

    func testTheNumberIsWrittenToItsOwnRowNotTheNewest() {
        let buffer = CaptureRingBuffer()
        let older = buffer.record(note("Teams"), suppressedRepeatCount: 0)
        buffer.record(note("Weather"), suppressedRepeatCount: 0)
        buffer.setJoined(id: older.id, matchNumber: 2)
        XCTAssertNil(buffer.entries[0].joinedMatch)
        XCTAssertEqual(buffer.entries[1].joinedMatch, 2)
    }

    func testTheNumberOfARowThatHasAgedOutIsDropped() {
        let buffer = CaptureRingBuffer(capacity: 1)
        let old = buffer.record(note("Teams"), suppressedRepeatCount: 0)
        buffer.record(note("Weather"), suppressedRepeatCount: 0)
        buffer.setJoined(id: old.id, matchNumber: 2)
        XCTAssertNil(buffer.entries.first?.joinedMatch)
        XCTAssertEqual(buffer.count, 1)
    }
}
