import AVFoundation
import XCTest
@testable import AlertAudio
import NotificationCore

/// `SoundInstall` is the one step that can lose a sound the user has: adding a
/// sound and saving an edited one both go through it. These hold it on its own,
/// as the second of those will call it, with a staged file it did not make.
/// What it does for an added sound is held by `SoundImportTests`.
final class SoundInstallTests: XCTestCase {
    private var root: URL!
    private let attempt = "11111111-2222-3333-4444-555555555555"

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("SoundInstallTests-\(UUID().uuidString)")
        for folder in ["system", "custom"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private var custom: URL { root.appendingPathComponent("custom") }

    private var library: SoundLibrary {
        SoundLibrary(systemDirectory: root.appendingPathComponent("system"), customDirectory: custom)
    }

    private var installer: SoundInstall { SoundInstall(library: library) }

    /// A tone written as a real audio file, in the sounds folder unless the path says otherwise.
    @discardableResult
    private func audio(_ path: String, seconds: Double = 0.2) throws -> URL {
        let url = root.appendingPathComponent(path)
        let format = AVAudioFormat(standardFormatWithSampleRate: 8_000, channels: 1)!
        let frames = AVAudioFrameCount(seconds * 8_000)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for i in 0..<Int(frames) { buffer.floatChannelData![0][i] = 0.5 * sin(Float(i) * 0.3) }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }

    private func listing() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: custom.path)) ?? []).sorted()
    }

    private func bytes(_ name: String) throws -> Data {
        try Data(contentsOf: custom.appendingPathComponent(name))
    }

    /// A sound as saving would stage it: hidden, of the sounds folder, and named for its attempt.
    @discardableResult
    private func rendering(seconds: Double = 0.3, type: String = "wav") throws -> URL {
        try audio("custom/\(SoundInstall.renderingPrefix)\(attempt).\(type)", seconds: seconds)
    }

    // MARK: - A staged file that this type did not stage

    func testARenderedFileIsGivenItsNameAndNothingStagedIsLeft() throws {
        let staged = try rendering()
        XCTAssertEqual(installer.install(staged, as: "Pager 2", replacing: false), .success("Pager 2"))
        XCTAssertEqual(listing(), ["Pager 2.wav"])
        XCTAssertEqual(library.availableNames, ["Pager 2"])
    }

    func testASoundTheUserHasIsReplacedOnlyWhenTheCallerSaysSoAndTheStagedFileGoesEitherWay() throws {
        try audio("custom/Alarm.wav", seconds: 0.1)
        let old = try bytes("Alarm.wav")

        XCTAssertEqual(installer.install(try rendering(), as: "Alarm", replacing: false), .failure(.alreadyExists("Alarm")))
        XCTAssertEqual(listing(), ["Alarm.wav"], "the staged file is gone and the sound is as it was")
        XCTAssertEqual(try bytes("Alarm.wav"), old)

        XCTAssertEqual(installer.install(try rendering(), as: "Alarm", replacing: true), .success("Alarm"))
        XCTAssertEqual(listing(), ["Alarm.wav"], "nothing hidden is left")
        XCTAssertNotEqual(try bytes("Alarm.wav"), old)
    }

    func testARenameThatFailsPutsEveryOldSoundBackAndLeavesNothingHidden() throws {
        try audio("custom/Alarm.wav", seconds: 0.1)
        try audio("custom/alarm.caf", seconds: 0.1)
        let wav = try bytes("Alarm.wav")
        let caf = try bytes("alarm.caf")
        var failing = installer
        failing.move = { _, _ in throw CocoaError(.fileWriteNoPermission) }
        guard case .failure(.couldNotCopy) = failing.install(try rendering(), as: "Alarm", replacing: true) else {
            return XCTFail("the install did not fail")
        }
        XCTAssertEqual(listing(), ["Alarm.wav", "alarm.caf"])
        XCTAssertEqual(try bytes("Alarm.wav"), wav)
        XCTAssertEqual(try bytes("alarm.caf"), caf)
    }

    func testANameMacOSHasIsRefusedWhateverIsSaidOfReplacing() throws {
        try audio("system/Sosumi.aiff")
        XCTAssertEqual(installer.install(try rendering(), as: "sosumi", replacing: true), .failure(.systemSound("Sosumi")))
        XCTAssertEqual(listing(), [])
    }

    func testAnUnsafeNameIsRefusedAndTheStagedFileGoes() throws {
        for name in ["", ".hidden", "a/b", "a:b", " padded ", String(repeating: "n", count: 101)] {
            XCTAssertEqual(installer.install(try rendering(), as: name, replacing: true), .failure(.badName), name)
            XCTAssertEqual(listing(), [], name)
        }
    }

    func testAFileThatIsNotNamedAsAStagedSoundIsRefusedAndNotRemoved() throws {
        let stray = try audio("custom/Pager.wav")
        guard case .failure(.couldNotCopy) = installer.install(stray, as: "Other", replacing: true) else {
            return XCTFail("a file that was never staged was installed")
        }
        let notAType = try audio("custom/\(SoundInstall.renderingPrefix)\(attempt).txt")
        guard case .failure(.couldNotCopy) = installer.install(notAType, as: "Other", replacing: true) else {
            return XCTFail("a file of no sound's type was installed")
        }
        let noAttempt = try audio("custom/\(SoundInstall.renderingPrefix)not-an-attempt.wav")
        guard case .failure(.couldNotCopy) = installer.install(noAttempt, as: "Other", replacing: true) else {
            return XCTFail("a file that names no attempt was installed")
        }
        XCTAssertEqual(listing(), [noAttempt.lastPathComponent, notAType.lastPathComponent, "Pager.wav"].sorted(),
                       "not this type's to remove")
    }

    // MARK: - A save that was stopped in the middle

    func testASoundSetAsideForASavedSoundIsPutBackAndItsRenderingRemoved() throws {
        try audio("custom/Alarm.wav", seconds: 0.1)
        let old = try bytes("Alarm.wav")
        // Stopped after the old sound was set aside, before the rendering was named.
        try FileManager.default.moveItem(
            at: custom.appendingPathComponent("Alarm.wav"),
            to: custom.appendingPathComponent(SoundInstall.asideName(for: "Alarm.wav", attempt: attempt, newType: "wav")))
        try rendering()

        XCTAssertEqual(installer.recoverSetAsideSounds(), ["Alarm"])
        XCTAssertEqual(listing(), ["Alarm.wav"], "back, and the rendering that was to replace it gone")
        XCTAssertEqual(try bytes("Alarm.wav"), old)
    }

    func testARenderingStillStagedMeansTheReplaceWasNotFinishedEvenIfAFileHoldsTheName() throws {
        try audio("custom/Alarm.wav", seconds: 0.1)
        try FileManager.default.moveItem(
            at: custom.appendingPathComponent("Alarm.wav"),
            to: custom.appendingPathComponent(SoundInstall.asideName(for: "Alarm.wav", attempt: attempt, newType: "wav")))
        // The new sound's name and type are there, as when the rename happened,
        // but the staged file is too, so something else put that file there.
        try audio("custom/Alarm.wav", seconds: 0.1)
        try rendering()
        XCTAssertEqual(installer.recoverSetAsideSounds(), [])
        XCTAssertEqual(listing(), [SoundInstall.asideName(for: "Alarm.wav", attempt: attempt, newType: "wav"),
                                   SoundInstall.renderingPrefix + attempt + ".wav", "Alarm.wav"].sorted(),
                       "neither deleted nor moved on a guess")
    }

    // MARK: - The sweep of what a crash left

    func testEveryStagedNameSavingAddsIsSweptOnceItIsOldAndNotBefore() throws {
        let left = [try audio("custom/\(SoundInstall.addingPrefix)\(attempt).wav"),
                    try rendering(),
                    custom.appendingPathComponent("\(SoundInstall.recipePrefix)\(attempt).json")]
        try Data("{}".utf8).write(to: left[2])
        try audio("custom/Kept.wav")

        SoundInstall.removeStaleStagedCopies(in: custom)
        for file in left { XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "\(file.lastPathComponent) may be under way") }

        SoundInstall.removeStaleStagedCopies(in: custom, now: Date().addingTimeInterval(SoundInstall.staleAfter + 1))
        XCTAssertEqual(listing(), ["Kept.wav"])
    }

    func testTheSweepNeverTakesASetAsideSoundHoweverOld() throws {
        let hidden = SoundInstall.asideName(for: "Alarm.wav", attempt: attempt, newType: "wav")
        try audio("custom/\(hidden)")
        try audio("custom/Alarm.wav")
        let ancient = Date().addingTimeInterval(SoundInstall.staleAfter * 1_000)
        SoundInstall.removeStaleStagedCopies(in: custom, now: ancient)
        XCTAssertEqual(listing(), [hidden, "Alarm.wav"].sorted(), "it is the recovery's, which does not judge by age")
    }

    func testTheSweepLeavesWhatItDoesNotNameAlone() throws {
        try audio("custom/.something-else.wav")
        try Data("{}".utf8).write(to: custom.appendingPathComponent(".recipes-not-staged.json"))
        try audio("custom/Alarm.wav")
        SoundInstall.removeStaleStagedCopies(in: custom, now: Date().addingTimeInterval(SoundInstall.staleAfter * 1_000))
        XCTAssertEqual(listing(), [".recipes-not-staged.json", ".something-else.wav", "Alarm.wav"])
    }
}
