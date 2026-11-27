import XCTest
@testable import NotificationCore

/// Moving the edge of a selection to a quiet point (sound editor plan, Task 3,
/// Ruling 4).
final class ZeroCrossingTests: XCTestCase {
    private typealias S = SoundSignals

    /// Whether the sound changes sign between frame `edge - 1` and frame `edge`,
    /// the channels added: what a cut made there leaves no step across.
    private func changesSign(at edge: Int, in buffer: SampleBuffer) -> Bool {
        guard edge >= 1, edge < buffer.frameCount else { return false }
        let before = buffer.channels.reduce(Float(0)) { $0 + $1[edge - 1] }
        let after = buffer.channels.reduce(Float(0)) { $0 + $1[edge] }
        return before * after <= 0
    }

    func testTheWindowIsFiveMilliseconds() {
        XCTAssertEqual(ZeroCrossing.windowFrames, 240)
    }

    func testASnapLandsOnAChangeOfSignAndNeverFurtherThanTheWindow() {
        // 100 Hz crosses every 240 frames, so there is always one within 120 of any frame.
        let wave = S.sine(frames: 20_000, hz: 100, amplitude: 0.5)
        for frame in stride(from: 1000, to: 6000, by: 37) {
            let snapped = ZeroCrossing.nearest(to: frame, in: wave)
            XCTAssertLessThanOrEqual(abs(snapped - frame), ZeroCrossing.windowFrames, "from \(frame)")
            XCTAssertTrue(changesSign(at: snapped, in: wave), "from \(frame) to \(snapped)")
        }
    }

    func testASnapLandsOnTheNearestChangeOfSign() {
        let wave = S.sine(frames: 20_000, hz: 100, amplitude: 0.5)
        for frame in stride(from: 1000, to: 6000, by: 37) {
            let snapped = ZeroCrossing.nearest(to: frame, in: wave)
            for distance in 0..<abs(snapped - frame) {
                XCTAssertFalse(changesSign(at: frame - distance, in: wave), "\(frame - distance) is nearer to \(frame) than \(snapped)")
                XCTAssertFalse(changesSign(at: frame + distance, in: wave), "\(frame + distance) is nearer to \(frame) than \(snapped)")
            }
        }
    }

    func testAnEdgeAlreadyOnAChangeOfSignStaysAndOneBesideItMovesToIt() {
        let step = S.both(frames: 1000) { $0 < 500 ? 0.5 : -0.5 }
        XCTAssertEqual(ZeroCrossing.nearest(to: 500, in: step), 500)
        XCTAssertEqual(ZeroCrossing.nearest(to: 480, in: step), 500)
        XCTAssertEqual(ZeroCrossing.nearest(to: 520, in: step), 500)
    }

    func testTheChannelsAreAddedBeforeAChangeIsLookedFor() {
        // The left channel changes sign at 100, but the right is large enough that the two together
        // do not until 300.
        let wave = S.stereo(frames: 600, left: { $0 < 100 ? 1 : -1 }, right: { $0 < 300 ? 1.5 : -3 })
        XCTAssertEqual(ZeroCrossing.nearest(to: 120, in: wave), 300)
    }

    func testWithNoChangeOfSignInTheWindowTheQuietestFrameIsTaken() {
        // Always above zero, with a trough at 1100.
        let trough = S.both(frames: 3000) { 0.1 + 0.0005 * Float(abs($0 - 1100)) }
        XCTAssertEqual(ZeroCrossing.nearest(to: 1000, in: trough), 1100)
    }

    func testAChangeOfSignBeyondTheWindowIsNotReachedAndOneInsideIsTaken() {
        // Rises from 0.1, and goes negative at 2000.
        let wave = S.both(frames: 4000) { $0 < 2000 ? 0.1 + 0.0001 * Float($0) : -0.5 }
        let farFrame = 1500
        let snapped = ZeroCrossing.nearest(to: farFrame, in: wave)
        XCTAssertLessThanOrEqual(abs(snapped - farFrame), ZeroCrossing.windowFrames)
        XCTAssertEqual(snapped, farFrame - ZeroCrossing.windowFrames, "the quietest frame the window holds is its low end")
        XCTAssertEqual(ZeroCrossing.nearest(to: 1900, in: wave), 2000)
    }

    func testAWindowCanBeGiven() {
        let wave = S.sine(frames: 20_000, hz: 100, amplitude: 0.5)
        for frame in stride(from: 1000, to: 3000, by: 41) {
            let snapped = ZeroCrossing.nearest(to: frame, in: wave, within: 10)
            XCTAssertLessThanOrEqual(abs(snapped - frame), 10)
            // Mostly there is no change of sign so near, and the quietest frame of the ten either side is taken.
            let quietest = ((frame - 10)...(frame + 10)).map { abs(wave.channels[0][$0] + wave.channels[1][$0]) }.min()!
            XCTAssertTrue(changesSign(at: snapped, in: wave) || abs(wave.channels[0][snapped] + wave.channels[1][snapped]) == quietest,
                          "from \(frame) to \(snapped)")
        }
        XCTAssertEqual(ZeroCrossing.nearest(to: 700, in: wave, within: 0), 700)
    }

    func testTheEndsOfTheSoundStayWhereTheyAreAndAFrameOutsideIsBroughtIn() {
        let loud = S.both(frames: 1000) { _ in 0.9 }
        XCTAssertEqual(ZeroCrossing.nearest(to: 0, in: loud), 0)
        XCTAssertEqual(ZeroCrossing.nearest(to: 1000, in: loud), 1000)
        XCTAssertEqual(ZeroCrossing.nearest(to: -50, in: loud), 0)
        XCTAssertEqual(ZeroCrossing.nearest(to: 5000, in: loud), 1000)
    }

    func testDigitalSilenceStaysWhereItIsAndNothingIsNothing() {
        XCTAssertEqual(ZeroCrossing.nearest(to: 321, in: SampleBuffer.silence(frames: 1000)), 321)
        XCTAssertEqual(ZeroCrossing.nearest(to: 5, in: SampleBuffer.silence(frames: 0)), 0)
    }

    func testASampleThatIsNotANumberIsNeverChosenAsQuiet() {
        var left = [Float](repeating: 0.5, count: 1000)
        left[500] = .nan
        left[501] = 0.3
        let wave = SampleBuffer(channels: [left])!
        let snapped = ZeroCrossing.nearest(to: 500, in: wave)
        XCTAssertEqual(snapped, 501)
    }
}
