import AVFoundation
import XCTest
@testable import AlertAudio
import NotificationCore

/// Adding a sound is the one time the app writes into the user's sounds
/// folder. These hold what it will and will not put there, against real
/// folders and real audio files.
final class SoundImportTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("SoundImportTests-\(UUID().uuidString)")
        for folder in ["system", "elsewhere"] {
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

    private var importer: SoundImport { SoundImport(library: library) }

    /// A tone, or silence, written as a real audio file.
    @discardableResult
    private func audio(_ path: String, seconds: Double = 0.2, amplitude: Float = 0.5) throws -> URL {
        let url = root.appendingPathComponent(path)
        let format = AVAudioFormat(standardFormatWithSampleRate: 8_000, channels: 1)!
        let frames = AVAudioFrameCount(seconds * 8_000)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for i in 0..<Int(frames) { buffer.floatChannelData![0][i] = amplitude * sin(Float(i) * 0.3) }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }

    private func listing() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: custom.path)) ?? []).sorted()
    }

    func testASoundIsCopiedInUnderItsOwnNameAndTheFolderIsMade() throws {
        let source = try audio("elsewhere/Pager.wav")
        XCTAssertEqual(importer.add(source), .success("Pager"))
        XCTAssertEqual(listing(), ["Pager.wav"])
        XCTAssertEqual(library.availableNames, ["Pager"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path), "the chosen file is copied, not moved")
    }

    func testTheCopyIsAFileOfItsOwnAndNotALink() throws {
        let source = try audio("elsewhere/Pager.wav")
        let link = root.appendingPathComponent("elsewhere/Linked.wav")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
        XCTAssertEqual(importer.add(link), .success("Linked"), "the name is the one it was chosen under")
        let copy = custom.appendingPathComponent("Linked.wav")
        XCTAssertEqual(try copy.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink, false)
        try FileManager.default.removeItem(at: source)
        XCTAssertNotNil(try? AVAudioFile(forReading: copy), "it plays with the chosen file gone")
    }

    func testAFileThatIsNotAudioIsRefusedAndNothingIsLeft() throws {
        let fake = root.appendingPathComponent("elsewhere/Notes.wav")
        try Data("these are not samples".utf8).write(to: fake)
        guard case .failure(.unreadable) = importer.add(fake) else { return XCTFail("a text file was added") }
        XCTAssertEqual(listing(), [], "not even the staged copy")
    }

    func testAnEmptyFileIsRefused() throws {
        let empty = root.appendingPathComponent("elsewhere/Empty.wav")
        try Data().write(to: empty)
        guard case .failure(.unreadable) = importer.add(empty) else { return XCTFail("an empty file was added") }
        XCTAssertEqual(listing(), [])
    }

    func testASilentSoundIsRefused() throws {
        let source = try audio("elsewhere/Hush.wav", amplitude: 0)
        XCTAssertEqual(importer.add(source), .failure(.silent))
        XCTAssertEqual(listing(), [])
    }

    func testASoundLongerThanThirtySecondsIsRefused() throws {
        let source = try audio("elsewhere/Long.wav", seconds: 31)
        XCTAssertEqual(importer.add(source), .failure(.tooLong))
        XCTAssertEqual(listing(), [])
    }

    func testAFileOfAnotherTypeIsRefusedBeforeItIsRead() throws {
        let text = root.appendingPathComponent("elsewhere/Pager.txt")
        try Data("x".utf8).write(to: text)
        XCTAssertEqual(importer.add(text), .failure(.unsupportedType("txt")))
        XCTAssertFalse(FileManager.default.fileExists(atPath: custom.path), "the folder is not made for a refusal")
    }

    func testAFolderIsRefused() {
        XCTAssertEqual(importer.add(root.appendingPathComponent("elsewhere")), .failure(.notAFile))
    }

    func testANameMacOSHasIsRefusedWhateverItsCaseOrType() throws {
        try audio("system/Sosumi.aiff")
        let source = try audio("elsewhere/sosumi.wav")
        XCTAssertEqual(importer.add(source), .failure(.systemSound("Sosumi")))
        XCTAssertEqual(importer.add(source, replacing: true), .failure(.systemSound("Sosumi")),
                       "saying yes to replacing is not a yes to this")
        XCTAssertEqual(listing(), [])
    }

    func testASoundTheUserHasIsNotReplacedUntilTheySaySo() throws {
        let first = try audio("elsewhere/Alarm.wav", seconds: 0.1)
        XCTAssertEqual(importer.add(first), .success("Alarm"))
        let before = try Data(contentsOf: custom.appendingPathComponent("Alarm.wav"))

        try FileManager.default.createDirectory(at: root.appendingPathComponent("other"), withIntermediateDirectories: true)
        let second = try audio("other/ALARM.caf", seconds: 0.3)
        XCTAssertEqual(importer.add(second), .failure(.alreadyExists("Alarm")))
        XCTAssertEqual(listing(), ["Alarm.wav"])
        XCTAssertEqual(try Data(contentsOf: custom.appendingPathComponent("Alarm.wav")), before, "untouched")

        XCTAssertEqual(importer.add(second, replacing: true), .success("ALARM"))
        XCTAssertEqual(listing(), ["ALARM.caf"], "one file for the name, not two of different types")
        XCTAssertEqual(library.availableNames, ["ALARM"])
    }

    func testChoosingAFileAlreadyInTheFolderLeavesItAsItIs() throws {
        XCTAssertEqual(importer.add(try audio("elsewhere/Pager.wav")), .success("Pager"))
        let inFolder = custom.appendingPathComponent("Pager.wav")
        let before = try Data(contentsOf: inFolder)
        XCTAssertEqual(importer.add(inFolder), .success("Pager"))
        XCTAssertEqual(try Data(contentsOf: inFolder), before)
        XCTAssertEqual(listing(), ["Pager.wav"])
    }

    func testAReplacementThatIsRefusedLeavesTheOldSound() throws {
        XCTAssertEqual(importer.add(try audio("elsewhere/Alarm.wav")), .success("Alarm"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("other"), withIntermediateDirectories: true)
        let silent = try audio("other/Alarm.wav", amplitude: 0)
        XCTAssertEqual(importer.add(silent, replacing: true), .failure(.silent))
        XCTAssertEqual(listing(), ["Alarm.wav"])
        XCTAssertNotNil(library.url(for: "Alarm"))
    }

    func testAReplacementThatCannotBeGivenItsNamePutsTheOldSoundsBack() throws {
        XCTAssertEqual(importer.add(try audio("elsewhere/Alarm.wav", seconds: 0.1)), .success("Alarm"))
        // A second file of the name and another type, as one put there by hand.
        try FileManager.default.copyItem(at: try audio("elsewhere/alarm.caf", seconds: 0.1),
                                         to: custom.appendingPathComponent("alarm.caf"))
        let wav = try Data(contentsOf: custom.appendingPathComponent("Alarm.wav"))
        let caf = try Data(contentsOf: custom.appendingPathComponent("alarm.caf"))

        try FileManager.default.createDirectory(at: root.appendingPathComponent("other"), withIntermediateDirectories: true)
        var failing = importer
        failing.move = { _, _ in throw CocoaError(.fileWriteNoPermission) }
        guard case .failure(.couldNotCopy) = failing.add(try audio("other/Alarm.wav", seconds: 0.3), replacing: true) else {
            return XCTFail("the replacement did not fail")
        }
        XCTAssertEqual(listing(), ["Alarm.wav", "alarm.caf"], "both back, and nothing staged or set aside left")
        XCTAssertEqual(try Data(contentsOf: custom.appendingPathComponent("Alarm.wav")), wav)
        XCTAssertEqual(try Data(contentsOf: custom.appendingPathComponent("alarm.caf")), caf)
    }

    func testAFileOverTheSizeLimitIsRefusedUnread() throws {
        let big = root.appendingPathComponent("elsewhere/Big.wav")
        FileManager.default.createFile(atPath: big.path, contents: nil)
        let handle = try FileHandle(forWritingTo: big)
        try handle.truncate(atOffset: UInt64(SoundImport.maximumBytes) + 1)
        try handle.close()
        XCTAssertEqual(importer.add(big), .failure(.tooLarge))
        XCTAssertFalse(FileManager.default.fileExists(atPath: custom.path))
    }

    func testAnUnsafeNameIsRefusedAndATypeInCapitalsIsTaken() throws {
        XCTAssertEqual(importer.add(try audio("elsewhere/.Hidden.wav")), .failure(.badName))
        let source = try audio("elsewhere/Loud.wav")
        let capitals = root.appendingPathComponent("elsewhere/Shout.WAV")
        try FileManager.default.copyItem(at: source, to: capitals)
        XCTAssertEqual(importer.add(capitals), .success("Shout"))
        XCTAssertEqual(listing(), ["Shout.wav"])
    }

    func testAStagedCopyACrashLeftIsClearedOnceItIsOldAndNotBefore() throws {
        try FileManager.default.createDirectory(at: custom, withIntermediateDirectories: true)
        let left = try audio("custom/.adding-left-behind.wav")
        try audio("custom/Kept.wav")
        SoundImport.removeStaleStagedCopies(in: custom)
        XCTAssertTrue(FileManager.default.fileExists(atPath: left.path), "it may be an add under way")
        SoundImport.removeStaleStagedCopies(in: custom, now: Date().addingTimeInterval(SoundImport.staleAfter + 1))
        XCTAssertEqual(listing(), ["Kept.wav"])
    }

    func testTheChoosersWordsGiveTheLimitTheImportHolds() {
        XCTAssertTrue(EditorText.addSoundMessage.contains("up to \(Int(SoundImport.maximumSeconds)) seconds"))
    }

    func testNamesThatAreNotSafeFileNamesAreRefused() {
        for name in [".hidden.wav", " .wav", "a:b.wav", "a\\b.wav", "line\nbreak.wav",
                     String(repeating: "n", count: 101) + ".wav"] {
            XCTAssertNil(SoundImport.soundName(for: URL(fileURLWithPath: "/tmp").appendingPathComponent(name)), name)
        }
        XCTAssertEqual(SoundImport.soundName(for: URL(fileURLWithPath: "/tmp/ Night Pager .m4a")), "Night Pager")
        XCTAssertEqual(SoundImport.soundName(for: URL(fileURLWithPath: "/tmp/a.b.wav")), "a.b")
    }

    func testTheStagedCopyIsNeverListedAsASound() throws {
        try FileManager.default.createDirectory(at: custom, withIntermediateDirectories: true)
        try audio("custom/.adding-1234.wav")
        XCTAssertEqual(library.availableNames, [])
    }

    func testEveryRefusalSaysSomethingAndTheTypesAreTheLibrarys() {
        XCTAssertEqual(Set(SoundImport.fileExtensions), SoundLibrary.extensions)
        XCTAssertEqual(SoundImport.maximumSeconds, AlertPlayer.maximumSeconds)
        let refusals: [SoundImport.Refusal] = [.notAFile, .unsupportedType("txt"), .unsupportedType(""), .badName, .tooLarge,
                                               .unreadable("x"), .silent, .tooLong, .systemSound("Glass"),
                                               .alreadyExists("Alarm"), .couldNotCopy("x")]
        for refusal in refusals { XCTAssertFalse(refusal.description.isEmpty) }
        XCTAssertTrue(SoundImport.Refusal.unsupportedType("txt").description.contains(".aif, .aiff, .caf, .m4a, .mp3 or .wav"))
    }

    func testTheFolderIsMadeOnceAndAskingAgainIsNotAnError() throws {
        XCTAssertEqual(try importer.makeFolder().path, custom.path)
        XCTAssertEqual(try importer.makeFolder().path, custom.path)
    }
}
