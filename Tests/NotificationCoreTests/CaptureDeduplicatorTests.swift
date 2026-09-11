import XCTest
@testable import NotificationCore

final class CaptureDeduplicatorTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_757_000_000)

    func testFirstSightingIsNotARepeat() {
        let d = CaptureDeduplicator(window: 1.5)
        XCTAssertEqual(d.admit("a", at: t0), .init(isRepeat: false, repeatCount: 0))
    }

    func testSecondSightingInsideWindowIsARepeat() {
        let d = CaptureDeduplicator(window: 1.5)
        _ = d.admit("a", at: t0)
        XCTAssertEqual(d.admit("a", at: t0.addingTimeInterval(0.5)),
                       .init(isRepeat: true, repeatCount: 1))
    }

    func testRepeatCountIncrementsAcrossSuccessiveHits() {
        let d = CaptureDeduplicator(window: 1.5)
        _ = d.admit("a", at: t0)
        _ = d.admit("a", at: t0.addingTimeInterval(0.2))
        XCTAssertEqual(d.admit("a", at: t0.addingTimeInterval(0.4)).repeatCount, 2)
    }

    func testDistinctKeysDoNotCollide() {
        let d = CaptureDeduplicator(window: 1.5)
        _ = d.admit("a", at: t0)
        XCTAssertFalse(d.admit("b", at: t0.addingTimeInterval(0.1)).isRepeat)
    }

    func testSightingAfterWindowIsTreatedAsNew() {
        let d = CaptureDeduplicator(window: 1.5)
        _ = d.admit("a", at: t0)
        XCTAssertFalse(d.admit("a", at: t0.addingTimeInterval(2.0)).isRepeat)
    }

    /// The window is anchored to first sighting, not refreshed on each hit, so
    /// a source repeating faster than the window cannot suppress forever.
    func testWindowIsNotSlidingSoFastRepeatsCannotSuppressIndefinitely() {
        let d = CaptureDeduplicator(window: 1.5)
        _ = d.admit("a", at: t0)
        _ = d.admit("a", at: t0.addingTimeInterval(1.0))
        XCTAssertFalse(d.admit("a", at: t0.addingTimeInterval(1.6)).isRepeat,
                       "Repeats must not keep extending the window")
    }
}
