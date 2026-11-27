import XCTest
@testable import NotificationCore

/// Which stretch of the sound the waveform shows, and the arithmetic between a place on the drawing and a
/// frame of the sound (sound editor plan, Task 7).
final class WaveformViewportTests: XCTestCase {
    private let second = SampleBuffer.sampleRate

    func testAViewportBeginsAsTheWholeSound() {
        let viewport = WaveformViewport(length: 4 * second)
        XCTAssertEqual(viewport.visible, 0..<(4 * second))
        XCTAssertTrue(viewport.isWhole)
        XCTAssertFalse(viewport.canZoomOut)
        XCTAssertTrue(viewport.canZoomIn)
    }

    func testZoomingInHalvesWhatIsShownAndKeepsTheFrameAroundWhichItZoomedWhereItWas() {
        var viewport = WaveformViewport(length: 4_000)
        viewport.zoomIn(around: 1_000)
        // 1000 was a quarter of the way across and still is.
        XCTAssertEqual(viewport.visible.count, 2_000)
        XCTAssertEqual(viewport.visible, 500..<2_500)
        let before = WaveformViewport(length: 4_000).x(of: 1_000, width: 400)
        XCTAssertEqual(before, 100, accuracy: 1e-9)
        XCTAssertEqual(viewport.x(of: 1_000, width: 400), 100, accuracy: 1e-9)
    }

    func testZoomingStaysInsideTheSoundWhateverFrameItIsGiven() {
        var near = WaveformViewport(length: 4_000)
        near.zoomIn(around: 0)
        XCTAssertEqual(near.visible, 0..<2_000)
        var far = WaveformViewport(length: 4_000)
        far.zoomIn(around: 4_000)
        XCTAssertEqual(far.visible, 2_000..<4_000)
        var past = WaveformViewport(length: 4_000)
        past.zoomIn(around: 90_000)
        XCTAssertEqual(past.visible, 2_000..<4_000, "a frame past the end is the end")
        var before = WaveformViewport(length: 4_000)
        before.zoomIn(around: -5)
        XCTAssertEqual(before.visible, 0..<2_000)
    }

    func testZoomingOutDoublesWhatIsShownAndIsHeldToTheWholeSound() {
        var viewport = WaveformViewport(length: 8_000)
        viewport.zoomIn(around: 4_000)
        viewport.zoomIn(around: 4_000)
        XCTAssertEqual(viewport.visible.count, 2_000)
        viewport.zoomOut(around: 4_000)
        XCTAssertEqual(viewport.visible.count, 4_000)
        viewport.zoomOut(around: 4_000)
        XCTAssertTrue(viewport.isWhole)
        viewport.zoomOut(around: 4_000)
        XCTAssertTrue(viewport.isWhole, "no further")
    }

    func testZoomingOutAtAnEdgeStaysAtThatEdge() {
        var viewport = WaveformViewport(length: 8_000)
        viewport.zoomIn(around: 0)
        viewport.zoomIn(around: 0)
        XCTAssertEqual(viewport.visible, 0..<2_000)
        viewport.zoomOut(around: 0)
        XCTAssertEqual(viewport.visible, 0..<4_000)
    }

    func testItCannotZoomInPastTenMillisecondsOrPastTheWholeOfAShorterSound() {
        var viewport = WaveformViewport(length: 10 * second)
        var steps = 0
        while viewport.canZoomIn {
            viewport.zoomIn(around: 5 * second)
            steps += 1
            XCTAssertLessThan(steps, 100)
        }
        XCTAssertEqual(viewport.visible.count, SampleBuffer.frames(seconds: 0.01))
        viewport.zoomIn(around: 5 * second)
        XCTAssertEqual(viewport.visible.count, SampleBuffer.frames(seconds: 0.01), "asking again changes nothing")

        // A sound shorter than that is already as close as it can be.
        let tiny = WaveformViewport(length: 100)
        XCTAssertFalse(tiny.canZoomIn)
        XCTAssertFalse(tiny.canZoomOut)
    }

    func testAZoomedViewportScrollsAndIsHeldInsideTheSound() {
        var viewport = WaveformViewport(length: 8_000)
        viewport.zoomIn(around: 0)
        viewport.scroll(toStart: 1_500)
        XCTAssertEqual(viewport.visible, 1_500..<5_500)
        viewport.scroll(toStart: 99_999)
        XCTAssertEqual(viewport.visible, 4_000..<8_000)
        viewport.scroll(toStart: -3)
        XCTAssertEqual(viewport.visible, 0..<4_000)
    }

    func testTheScrollFractionIsWhereTheVisibleStretchStandsAmongTheWaysItCouldStand() {
        var viewport = WaveformViewport(length: 8_000)
        XCTAssertEqual(viewport.scrollFraction, 0, "the whole sound has nowhere to scroll")
        viewport.zoomIn(around: 0)
        XCTAssertEqual(viewport.scrollFraction, 0)
        viewport.scroll(toFraction: 0.5)
        XCTAssertEqual(viewport.visible, 2_000..<6_000)
        XCTAssertEqual(viewport.scrollFraction, 0.5, accuracy: 1e-9)
        viewport.scroll(toFraction: 1)
        XCTAssertEqual(viewport.visible, 4_000..<8_000)
        viewport.scroll(toFraction: 7)
        XCTAssertEqual(viewport.visible, 4_000..<8_000, "a fraction past the end is the end")
        viewport.scroll(toFraction: -1)
        XCTAssertEqual(viewport.visible, 0..<4_000)
        viewport.scroll(toFraction: .nan)
        XCTAssertEqual(viewport.visible, 0..<4_000, "not a number moves nothing")
    }

    func testAFrameThatIsInViewIsLeftWhereItIs() {
        var viewport = WaveformViewport(length: 8_000)
        viewport.zoomIn(around: 0)
        viewport.reveal(0)
        viewport.reveal(2_000)
        viewport.reveal(4_000)
        XCTAssertEqual(viewport.visible, 0..<4_000, "the end of what is shown is in view")
    }

    func testAFrameAheadOfTheViewIsBroughtIntoItNearTheLeftAndOneBehindNearTheRight() {
        var viewport = WaveformViewport(length: 20_000)
        viewport.zoomIn(around: 0)
        viewport.zoomIn(around: 0)
        XCTAssertEqual(viewport.visible, 0..<5_000)
        viewport.reveal(7_000)
        XCTAssertTrue(viewport.visible.contains(7_000))
        XCTAssertEqual(viewport.visible.count, 5_000, "what is shown is as wide as it was")
        XCTAssertEqual(viewport.visible.lowerBound, 7_000 - 500, "a tenth of the way in")
        viewport.scroll(toStart: 10_000)
        viewport.reveal(8_000)
        XCTAssertTrue(viewport.visible.contains(8_000))
        XCTAssertEqual(viewport.visible.count, 5_000)
        XCTAssertEqual(viewport.visible.upperBound, 8_000 + 500, "a tenth from the right")
    }

    func testRevealingNeverLeavesTheSound() {
        var viewport = WaveformViewport(length: 20_000)
        viewport.zoomIn(around: 0)
        viewport.zoomIn(around: 0)
        viewport.reveal(20_000)
        XCTAssertEqual(viewport.visible, 15_000..<20_000)
        viewport.reveal(0)
        XCTAssertEqual(viewport.visible, 0..<5_000)
    }

    func testAnArrowsStepIsAFiftiethOfWhatIsShownAndAtLeastOneFrame() {
        var viewport = WaveformViewport(length: 10 * second)
        XCTAssertEqual(viewport.stepFrames, 10 * second / 50)
        while viewport.canZoomIn { viewport.zoomIn(around: 0) }
        XCTAssertEqual(viewport.stepFrames, SampleBuffer.frames(seconds: 0.01) / 50)
        XCTAssertEqual(WaveformViewport(length: 10).stepFrames, 1)
    }

    func testAPlaceOnTheDrawingIsTheNearestFrameAndIsHeldToTheSound() {
        var viewport = WaveformViewport(length: 1_000)
        XCTAssertEqual(viewport.frame(atX: 0, width: 500), 0)
        XCTAssertEqual(viewport.frame(atX: 250, width: 500), 500)
        XCTAssertEqual(viewport.frame(atX: 500, width: 500), 1_000)
        XCTAssertEqual(viewport.frame(atX: 0.9, width: 500), 2, "1.8 frames across is the frame nearest it")
        XCTAssertEqual(viewport.frame(atX: -40, width: 500), 0)
        XCTAssertEqual(viewport.frame(atX: 900, width: 500), 1_000)
        viewport.zoomIn(around: 500)
        XCTAssertEqual(viewport.visible, 250..<750)
        XCTAssertEqual(viewport.frame(atX: 0, width: 500), 250)
        XCTAssertEqual(viewport.frame(atX: 500, width: 500), 750)
        XCTAssertEqual(viewport.frame(atX: -9_999, width: 500), 0, "outside the drawing is outside the view, and held to the sound")
        XCTAssertEqual(viewport.frame(atX: 10, width: 0), 250, "a drawing with no width has nothing to point at")
    }

    func testAFramesPlaceOnTheDrawingIsWhereItWouldBePointedAt() {
        var viewport = WaveformViewport(length: 1_000)
        viewport.zoomIn(around: 500)
        for frame in [250, 400, 500, 750] {
            let x = viewport.x(of: frame, width: 500)
            XCTAssertEqual(viewport.frame(atX: x, width: 500), frame)
        }
        XCTAssertLessThan(viewport.x(of: 100, width: 500), 0, "a frame before the view is left of it")
        XCTAssertGreaterThan(viewport.x(of: 900, width: 500), 500, "a frame after it is right of it")
    }

    func testAReachInPointsIsHowManyFramesItSpansAtThisZoomAndIsNeverLessThanOne() {
        var viewport = WaveformViewport(length: 10_000)
        XCTAssertEqual(viewport.frames(spanning: 8, width: 1_000), 80)
        XCTAssertEqual(viewport.frames(spanning: 3, width: 1_000), 30)
        XCTAssertEqual(viewport.frames(spanning: 8, width: 3_000), 27, "26.7 rounds up, so that the reach drawn is the reach hit")
        viewport.zoomIn(around: 0)
        XCTAssertEqual(viewport.frames(spanning: 8, width: 1_000), 40)
        while viewport.canZoomIn { viewport.zoomIn(around: 0) }
        XCTAssertEqual(viewport.frames(spanning: 0.01, width: 1_000), 1)
        XCTAssertEqual(viewport.frames(spanning: 8, width: 0), 1)
        XCTAssertEqual(viewport.frames(spanning: .nan, width: 100), 1)
    }

    func testTheReachAndTheSlopArePointsAHandIsSureOf() {
        XCTAssertEqual(WaveformViewport.edgeReachPoints, 8)
        XCTAssertEqual(WaveformViewport.clickSlopPoints, 3)
        XCTAssertLessThan(WaveformViewport.clickSlopPoints, WaveformViewport.edgeReachPoints,
                          "a press that is a click must not be able to be a grab of an edge it is within reach of")
    }

    func testANewLengthKeepsWhatIsShownWhereItCanAndIsHeldToTheNewSound() {
        var viewport = WaveformViewport(length: 8_000)
        viewport.zoomIn(around: 4_000)
        XCTAssertEqual(viewport.visible, 2_000..<6_000)
        XCTAssertEqual(viewport.resized(toLength: 8_000), viewport, "the same length changes nothing")
        XCTAssertEqual(viewport.resized(toLength: 5_000).visible, 1_000..<5_000, "shorter: pulled back inside")
        XCTAssertEqual(viewport.resized(toLength: 3_000).visible, 0..<3_000, "shorter than what was shown: the whole")
        XCTAssertEqual(viewport.resized(toLength: 20_000).visible, 2_000..<6_000, "longer: what was shown is still shown")
        XCTAssertTrue(WaveformViewport(length: 8_000).resized(toLength: 12_000).isWhole, "the whole stays the whole")
    }

    func testASoundOfNoLengthIsAViewportOfNothingAndNothingMovesIt() {
        var viewport = WaveformViewport(length: 0)
        XCTAssertEqual(viewport.visible, 0..<0)
        viewport.zoomIn(around: 5)
        viewport.zoomOut(around: 5)
        viewport.reveal(5)
        viewport.scroll(toStart: 5)
        XCTAssertEqual(viewport.visible, 0..<0)
        XCTAssertEqual(viewport.frame(atX: 3, width: 10), 0)
        XCTAssertFalse(viewport.canZoomIn)
    }
}
