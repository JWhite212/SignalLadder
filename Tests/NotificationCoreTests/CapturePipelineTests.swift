import XCTest
@testable import NotificationCore

/// The first tests of the capture decision path. Until now it lived in a
/// closure in a target with no tests; the first half of this file pins what
/// it already did, so moving it could not change it unnoticed.
final class CapturePipelineTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_757_000_000)
    private let marker = "SignalLadder canary TEST-MARKER"

    private func pipeline() -> CapturePipeline {
        CapturePipeline(ownAppName: "SignalLadder",
                        isSelfTest: { [marker] raw, children in
                            raw.contains(marker) || children.contains { $0.contains(marker) }
                        })
    }

    /// A banner as the watcher delivers it: comma-joined description plus the
    /// text children that carry the fields separately (M1 finding).
    private func banner(_ app: String, _ title: String, _ body: String = "body",
                        at offset: TimeInterval = 0) -> (RawCapture, [String]) {
        (RawCapture(timestamp: t0.addingTimeInterval(offset),
                    rawText: "\(app), \(title), \(body)",
                    subrole: "AXNotificationCenterBanner"),
         [title, body])
    }

    @discardableResult
    private func feed(_ p: CapturePipeline, _ b: (RawCapture, [String])) -> CapturePipeline.Outcome {
        p.process(b.0, textChildren: b.1)
    }

    // MARK: - Pinned behaviour (moved, not changed)

    func testADistinctCaptureIsRecordedAndCounted() {
        let p = pipeline()
        XCTAssertEqual(feed(p, banner("Weather", "Rain")), .recorded(matchedRule: nil))
        XCTAssertEqual(p.captureCount, 1)
        XCTAssertEqual(p.history.entries.first?.captured.appNameGuess, "Weather")
    }

    func testTheSelfTestIsNeitherRecordedNorCounted() {
        let p = pipeline()
        XCTAssertEqual(feed(p, banner("SignalLadder", "SignalLadder self-test", marker)), .selfTest)
        XCTAssertEqual(p.captureCount, 0)
        XCTAssertTrue(p.history.isEmpty)
    }

    func testTheSelfTestIsFoundInTheChildrenWhenTheDescriptionIsEmpty() {
        let p = pipeline()
        let raw = RawCapture(timestamp: t0, rawText: "", subrole: "AXNotificationCenterBanner")
        XCTAssertEqual(p.process(raw, textChildren: ["SignalLadder self-test", marker]), .selfTest)
    }

    func testTheAppsOwnAlarmIsNeitherRecordedNorCounted() {
        let p = pipeline()
        XCTAssertEqual(feed(p, banner("SignalLadder", SelfNotification.blindTitle)), .ownNotification)
        XCTAssertEqual(p.captureCount, 0)
    }

    func testTheSelfTestNeverEntersTheDedupeWindow() {
        // Recognised once and then forgotten, exactly as CanaryService clears
        // its marker after the first match.
        var recognised = false
        let p = CapturePipeline(ownAppName: "SignalLadder", isSelfTest: { _, _ in
            defer { recognised = true }
            return !recognised
        })

        XCTAssertEqual(feed(p, banner("Weather", "Rain")), .selfTest)

        // Identical text inside dedupe's 1.5s window. Had the self-test been
        // admitted to dedupe, this would be suppressed as a repeat of it and
        // never recorded at all.
        XCTAssertEqual(feed(p, banner("Weather", "Rain", at: 0.5)), .recorded(matchedRule: nil))
    }

    func testARepeatLandsOnTheRowItDuplicatesAndIsNotRecordedAgain() {
        let p = pipeline()
        feed(p, banner("Teams", "ping", at: 0))
        feed(p, banner("Weather", "Rain", at: 0.2))
        XCTAssertEqual(feed(p, banner("Teams", "ping", at: 0.4)), .suppressedRepeat)

        XCTAssertEqual(p.captureCount, 2)
        XCTAssertEqual(p.history.entries.last?.captured.appNameGuess, "Teams")
        XCTAssertEqual(p.history.entries.last?.suppressedRepeatCount, 1)
        XCTAssertEqual(p.history.entries.first?.suppressedRepeatCount, 0, "Weather did not repeat")
    }
}
