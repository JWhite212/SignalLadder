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
}
