import XCTest
@testable import NotificationCore

/// The numbers a sound crosses into the core as (sound editor plan, Task 2).
final class SampleBufferTests: XCTestCase {
    func testChannelsOfDifferentLengthsAreRefused() {
        XCTAssertNil(SampleBuffer(channels: [[0, 0, 0], [0, 0]]))
    }

    func testNoChannelsIsRefused() {
        XCTAssertNil(SampleBuffer(channels: []))
    }

    func testAnEmptyBufferIsAllowedAndIsEmpty() throws {
        let buffer = try XCTUnwrap(SampleBuffer(channels: [[], []]))
        XCTAssertTrue(buffer.isEmpty)
        XCTAssertEqual(buffer.frameCount, 0)
        XCTAssertEqual(buffer.channelCount, 2)
        XCTAssertEqual(buffer.peak, 0)
    }

    func testFramesAndChannelsAreCountedFromTheSamples() throws {
        let buffer = try XCTUnwrap(SampleBuffer(channels: [[0.1, 0.2, 0.3], [0, 0, 0]]))
        XCTAssertEqual(buffer.frameCount, 3)
        XCTAssertEqual(buffer.channelCount, 2)
        XCTAssertFalse(buffer.isEmpty)
    }

    func testSilenceIsStereoUnlessAskedAndAllZero() {
        let silence = SampleBuffer.silence(frames: 10)
        XCTAssertEqual(silence.channelCount, 2)
        XCTAssertEqual(silence.frameCount, 10)
        XCTAssertEqual(silence.peak, 0)
        XCTAssertEqual(SampleBuffer.silence(frames: 4, channelCount: 1).channelCount, 1)
    }

    func testThePeakIsTheLargestAbsoluteSampleInAnyChannel() throws {
        let buffer = try XCTUnwrap(SampleBuffer(channels: [[0.1, -0.2, 0.3], [0.0, 0.5, -0.9]]))
        XCTAssertEqual(buffer.peak, 0.9)
    }

    func testThePeakPassesOverASampleThatIsNotANumber() throws {
        let buffer = try XCTUnwrap(SampleBuffer(channels: [[0.25, .nan, .infinity]]))
        XCTAssertEqual(buffer.peak, 0.25)
    }

    func testATimeBecomesWholeFramesAtFortyEightKilohertz() {
        XCTAssertEqual(SampleBuffer.sampleRate, 48_000)
        XCTAssertEqual(SampleBuffer.frames(seconds: 1), 48_000)
        XCTAssertEqual(SampleBuffer.frames(seconds: 0.005), 240)
        XCTAssertEqual(SampleBuffer.frames(seconds: 0.0000104), 0, "half a frame or less rounds down")
        XCTAssertEqual(SampleBuffer.frames(seconds: 0.0000105), 1)
        XCTAssertEqual(SampleBuffer.frames(seconds: -1), 0)
        XCTAssertEqual(SampleBuffer.frames(seconds: .nan), 0)
        XCTAssertEqual(SampleBuffer.frames(seconds: .infinity), 0)
        XCTAssertEqual(SampleBuffer.seconds(frames: 24_000), 0.5)
    }

    func testATimeTooLongToCountIsAVeryLongTimeAndNotACrash() {
        XCTAssertGreaterThan(SampleBuffer.frames(seconds: 1e300), 1_000_000_000)
        XCTAssertGreaterThan(SampleBuffer.frames(seconds: Double.greatestFiniteMagnitude), 1_000_000_000)
    }

    func testTheDurationIsTheFramesOverTheRate() {
        XCTAssertEqual(SampleBuffer.silence(frames: 96_000).duration, 2)
    }
}
