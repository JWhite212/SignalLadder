import XCTest
@testable import NotificationCore

/// The minimum and maximum of each column of the drawing (sound editor plan,
/// Task 3).
final class WaveformPeaksTests: XCTestCase {
    private typealias S = SoundSignals

    func testAColumnHoldsTheLowestAndHighestSampleOfItsFramesInEitherChannel() {
        // Left rises from 0 to 0.999 and right falls from 0 to -0.999.
        let ramp = S.stereo(frames: 1000, left: { Float($0) / 1000 }, right: { -Float($0) / 1000 })
        let columns = WaveformPeaks.columns(of: ramp, frames: 0..<1000, count: 10)
        XCTAssertEqual(columns.count, 10)
        for (index, column) in columns.enumerated() {
            let last = Float(index * 100 + 99) / 1000
            XCTAssertEqual(column.minimum, -last, accuracy: 1e-6, "column \(index)")
            XCTAssertEqual(column.maximum, last, accuracy: 1e-6, "column \(index)")
        }
    }

    func testTheLowestAndHighestMayBeInDifferentChannels() {
        let wave = S.stereo(frames: 100, left: { $0 == 40 ? 0.7 : 0.1 }, right: { $0 == 60 ? -0.4 : 0.1 })
        let column = WaveformPeaks.columns(of: wave, frames: 0..<100, count: 1)[0]
        XCTAssertEqual(column.maximum, 0.7)
        XCTAssertEqual(column.minimum, -0.4)
    }

    func testASineIsAsLoudInEveryColumnWhenAColumnIsLongerThanAWave() {
        let wave = S.sine(frames: 48_000, hz: 440, amplitude: 0.5)
        let columns = WaveformPeaks.columns(of: wave, frames: 0..<48_000, count: 100)
        XCTAssertEqual(columns.count, 100)
        for column in columns {
            XCTAssertEqual(column.maximum, 0.5, accuracy: 0.005)
            XCTAssertEqual(column.minimum, -0.5, accuracy: 0.005)
        }
    }

    func testEveryFrameIsInExactlyOneColumn() {
        for frame in 0..<100 {
            let impulse = S.both(frames: 100) { $0 == frame ? 1 : 0 }
            let columns = WaveformPeaks.columns(of: impulse, frames: 0..<100, count: 7)
            XCTAssertEqual(columns.filter { $0.maximum == 1 }.count, 1, "frame \(frame)")
        }
    }

    func testAZoomedRangeIsDrawnAcrossTheColumns() {
        let ramp = S.both(frames: 1000) { Float($0) / 1000 }
        let columns = WaveformPeaks.columns(of: ramp, frames: 200..<400, count: 2)
        XCTAssertEqual(columns[0].minimum, 0.2, accuracy: 1e-6)
        XCTAssertEqual(columns[0].maximum, 0.299, accuracy: 1e-6)
        XCTAssertEqual(columns[1].minimum, 0.3, accuracy: 1e-6)
        XCTAssertEqual(columns[1].maximum, 0.399, accuracy: 1e-6)
    }

    func testMoreColumnsThanFramesGiveEachColumnTheFrameItStandsOn() {
        let wave = S.both(frames: 4) { [0.1, 0.2, 0.3, 0.4][$0] }
        let columns = WaveformPeaks.columns(of: wave, frames: 0..<4, count: 10)
        XCTAssertEqual(columns.map(\.maximum), [0.1, 0.1, 0.1, 0.2, 0.2, 0.3, 0.3, 0.3, 0.4, 0.4])
        XCTAssertEqual(columns.map(\.minimum), columns.map(\.maximum))
    }

    func testARangeBeyondTheSoundIsHeldToTheSound() {
        let ramp = S.both(frames: 1000) { Float($0) / 1000 }
        XCTAssertEqual(WaveformPeaks.columns(of: ramp, frames: -100..<5000, count: 10),
                       WaveformPeaks.columns(of: ramp, frames: 0..<1000, count: 10))
    }

    func testTheWholeSoundIsDrawnWhenNoRangeIsGiven() {
        let ramp = S.both(frames: 1000) { Float($0) / 1000 }
        XCTAssertEqual(WaveformPeaks.columns(of: ramp, count: 10), WaveformPeaks.columns(of: ramp, frames: 0..<1000, count: 10))
    }

    func testNoColumnsAreNoPeaksAndNothingToDrawIsFlat() {
        let ramp = S.both(frames: 1000) { Float($0) / 1000 }
        XCTAssertEqual(WaveformPeaks.columns(of: ramp, frames: 0..<1000, count: 0), [])
        XCTAssertEqual(WaveformPeaks.columns(of: ramp, frames: 0..<1000, count: -3), [])
        let flat = WaveformPeaks.columns(of: ramp, frames: 500..<500, count: 4)
        XCTAssertEqual(flat, Array(repeating: WaveformPeaks.Column(minimum: 0, maximum: 0), count: 4))
        XCTAssertEqual(WaveformPeaks.columns(of: ramp, frames: 2000..<3000, count: 2).count, 2)
    }

    func testASampleThatIsNotANumberIsPassedOver() {
        var left = [Float](repeating: 0.2, count: 20)
        left[3] = .nan
        left[4] = .infinity
        left[12] = -.infinity
        left[13] = -0.6
        let wave = SampleBuffer(channels: [left])!
        let columns = WaveformPeaks.columns(of: wave, frames: 0..<20, count: 2)
        XCTAssertEqual(columns[0].maximum, 0.2)
        XCTAssertEqual(columns[0].minimum, 0.2)
        XCTAssertEqual(columns[1].minimum, -0.6)
        let onlyBad = SampleBuffer(channels: [[.nan, .nan]])!
        XCTAssertEqual(WaveformPeaks.columns(of: onlyBad, frames: 0..<2, count: 1), [WaveformPeaks.Column(minimum: 0, maximum: 0)])
    }
}
