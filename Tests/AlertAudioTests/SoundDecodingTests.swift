import AVFoundation
import XCTest
@testable import AlertAudio
import NotificationCore

/// What the player and the sound editor share: a file read whole and brought to the player's
/// format. The player's own words for a file that cannot be read are held by `AlertPlayerTests`,
/// which are unchanged; these hold what the shared step gives and what the editor asks of it.
final class SoundDecodingTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("SoundDecodingTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func file(_ name: String) -> URL { root.appendingPathComponent(name) }

    func testAFileComesBackAs48kHzStereoAtTheLengthItHad() throws {
        let url = try TestAudio.write(file("a.wav"), seconds: 0.5, rate: 8_000, channels: 1, amplitude: 0.5)
        let samples = try SoundDecoding.samples(of: url, maximumSeconds: 30)
        XCTAssertEqual(samples.channelCount, 2)
        XCTAssertEqual(Double(samples.frameCount), 0.5 * 48_000, accuracy: 64)
        XCTAssertEqual(samples.channels[0], samples.channels[1], "a mono file is the same in both channels")
        XCTAssertEqual(samples.peak, 0.5, accuracy: 0.05)
    }

    func testTheSamplesAreTheBufferThePlayerPlays() throws {
        let url = try TestAudio.write(file("a.wav"), seconds: 0.2, rate: 44_100, channels: 2, amplitude: 0.4)
        let buffer = try SoundDecoding.decode(url, maximumSeconds: 30)
        let samples = try SoundDecoding.samples(of: url, maximumSeconds: 30)
        XCTAssertEqual(buffer.format, SoundDecoding.format)
        XCTAssertEqual(samples.frameCount, Int(buffer.frameLength))
        for channel in 0..<2 {
            XCTAssertEqual(samples.channels[channel], Array(UnsafeBufferPointer(start: buffer.floatChannelData![channel],
                                                                                 count: Int(buffer.frameLength))))
        }
    }

    func testAFileOverTheLimitIsRefusedWithItsOwnLengthBeforeAnyOfItIsRead() throws {
        let url = try TestAudio.write(file("long.wav"), seconds: 31, rate: 8_000)
        XCTAssertThrowsError(try SoundDecoding.decode(url, maximumSeconds: 30)) {
            XCTAssertEqual($0 as? SoundDecoding.Failure, .tooLong(seconds: 31))
        }
        XCTAssertNoThrow(try SoundDecoding.decode(url, maximumSeconds: 31))
        XCTAssertNoThrow(try SoundDecoding.decode(url, maximumSeconds: 120))
    }

    func testAFileThatIsNotAudioAndAnEmptyOneAreUnreadable() throws {
        let junk = file("junk.wav")
        try Data("not audio".utf8).write(to: junk)
        XCTAssertThrowsError(try SoundDecoding.decode(junk, maximumSeconds: 30)) {
            guard case .unreadable(let reason)? = $0 as? SoundDecoding.Failure else { return XCTFail("\($0)") }
            XCTAssertFalse(reason.isEmpty)
        }
        let empty = try TestAudio.write(file("empty.wav"), seconds: 0)
        XCTAssertThrowsError(try SoundDecoding.decode(empty, maximumSeconds: 30)) {
            guard case .unreadable(let reason)? = $0 as? SoundDecoding.Failure else { return XCTFail("\($0)") }
            XCTAssertFalse(reason.isEmpty, "a file with no audio in it is refused, in the system's words")
        }
    }

    func testTheEditorCanHoldWhatItWillDecodeToASize() throws {
        let url = try TestAudio.write(file("a.wav"), seconds: 1, rate: 8_000, channels: 1)
        // 8,000 frames of one channel of floats.
        XCTAssertNoThrow(try SoundDecoding.decode(url, maximumSeconds: 120, maximumDecodedBytes: 32_000))
        XCTAssertThrowsError(try SoundDecoding.decode(url, maximumSeconds: 120, maximumDecodedBytes: 31_999)) {
            XCTAssertEqual($0 as? SoundDecoding.Failure, .unreadable("it holds more audio than can be edited"))
        }
    }

    func testItCanBeCalledOffTheMainActor() async throws {
        let url = try TestAudio.write(file("a.wav"), seconds: 0.2)
        // A nonisolated task is a place a main-actor function could not be called from without
        // awaiting it, so this compiling is the proof.
        let samples = await Task.detached { try? SoundDecoding.samples(of: url, maximumSeconds: 30) }.value
        XCTAssertNotNil(samples)
    }
}
