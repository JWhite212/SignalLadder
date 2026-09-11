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
}
