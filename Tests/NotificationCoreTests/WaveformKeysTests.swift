import XCTest
@testable import NotificationCore

/// What each key does to the waveform (sound editor plan, Ruling 13): Space plays and stops, the arrows move the
/// playhead and Shift with them selects, and Home and End go to the ends. The view only says which key it was.
final class WaveformKeysTests: XCTestCase {
    private func apply(_ key: WaveformKey, extending: Bool = false, to timeline: inout SoundTimeline,
                       in viewport: inout WaveformViewport) -> WaveformKeyOutcome {
        WaveformKeys.apply(key, extending: extending, timeline: &timeline, viewport: &viewport)
    }

    func testSpacePlaysAndStopsAndMovesNothing() {
        var timeline = SoundTimeline(length: 10_000)
        timeline.select(100..<300)
        var viewport = WaveformViewport(length: 10_000)
        let before = (timeline, viewport)
        XCTAssertEqual(apply(.space, to: &timeline, in: &viewport), .togglePlayback)
        XCTAssertEqual(apply(.space, extending: true, to: &timeline, in: &viewport), .togglePlayback, "Shift does not change it")
        XCTAssertEqual(timeline, before.0)
        XCTAssertEqual(viewport, before.1)
    }

    func testTheArrowsMoveThePlayheadByAStepOfWhatIsShown() {
        var timeline = SoundTimeline(length: 10_000)
        var viewport = WaveformViewport(length: 10_000)
        XCTAssertEqual(viewport.stepFrames, 200)
        XCTAssertEqual(apply(.right, to: &timeline, in: &viewport), .moved)
        XCTAssertEqual(timeline.playhead, 200)
        XCTAssertEqual(apply(.right, to: &timeline, in: &viewport), .moved)
        XCTAssertEqual(timeline.playhead, 400)
        XCTAssertEqual(apply(.left, to: &timeline, in: &viewport), .moved)
        XCTAssertEqual(timeline.playhead, 200)
    }

    func testTheStepIsSmallerWhenZoomedIn() {
        var timeline = SoundTimeline(length: 10_000)
        var viewport = WaveformViewport(length: 10_000)
        viewport.zoomIn(around: 0)
        XCTAssertEqual(viewport.stepFrames, 100)
        _ = apply(.right, to: &timeline, in: &viewport)
        XCTAssertEqual(timeline.playhead, 100)
    }

    func testAnArrowStopsAtTheEnds() {
        var timeline = SoundTimeline(length: 10_000)
        var viewport = WaveformViewport(length: 10_000)
        _ = apply(.left, to: &timeline, in: &viewport)
        XCTAssertEqual(timeline.playhead, 0)
        timeline.place(9_900)
        _ = apply(.right, to: &timeline, in: &viewport)
        XCTAssertEqual(timeline.playhead, 10_000)
    }

    func testShiftWithAnArrowSelectsAndWithoutItClearsTheSelection() {
        var timeline = SoundTimeline(length: 10_000)
        var viewport = WaveformViewport(length: 10_000)
        timeline.place(1_000)
        _ = apply(.right, extending: true, to: &timeline, in: &viewport)
        _ = apply(.right, extending: true, to: &timeline, in: &viewport)
        XCTAssertEqual(timeline.selection, 1_000..<1_400)
        _ = apply(.right, to: &timeline, in: &viewport)
        XCTAssertNil(timeline.selection)
        XCTAssertEqual(timeline.playhead, 1_600)
    }

    func testHomeAndEndGoToTheEndsAndWithShiftSelectToThem() {
        var timeline = SoundTimeline(length: 10_000)
        var viewport = WaveformViewport(length: 10_000)
        timeline.place(4_000)
        XCTAssertEqual(apply(.end, to: &timeline, in: &viewport), .moved)
        XCTAssertEqual(timeline.playhead, 10_000)
        XCTAssertEqual(apply(.home, to: &timeline, in: &viewport), .moved)
        XCTAssertEqual(timeline.playhead, 0)
        timeline.place(4_000)
        _ = apply(.end, extending: true, to: &timeline, in: &viewport)
        XCTAssertEqual(timeline.selection, 4_000..<10_000)
        _ = apply(.home, extending: true, to: &timeline, in: &viewport)
        XCTAssertEqual(timeline.selection, 0..<4_000)
    }

    func testTheViewFollowsThePlayheadWhereItGoesOutOfView() {
        var timeline = SoundTimeline(length: 20_000)
        var viewport = WaveformViewport(length: 20_000)
        viewport.zoomIn(around: 0)
        viewport.zoomIn(around: 0)
        XCTAssertEqual(viewport.visible, 0..<5_000)
        _ = apply(.end, to: &timeline, in: &viewport)
        XCTAssertEqual(viewport.visible, 15_000..<20_000, "the end is in view")
        _ = apply(.home, to: &timeline, in: &viewport)
        XCTAssertEqual(viewport.visible, 0..<5_000)
        XCTAssertTrue(viewport.visible.contains(timeline.playhead))
    }
}
