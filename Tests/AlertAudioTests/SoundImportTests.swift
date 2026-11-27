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

    func testAddingSweepsTheStagedNamesSavingLeavesAsWellOnceTheyAreOld() throws {
        try FileManager.default.createDirectory(at: custom, withIntermediateDirectories: true)
        let old = Date().addingTimeInterval(-SoundImport.staleAfter * 10)
        let staleSound = try audio("custom/\(SoundInstall.renderingPrefix)11111111-2222-3333-4444-555555555555.wav")
        let staleRecipe = custom.appendingPathComponent("\(SoundInstall.recipePrefix)11111111-2222-3333-4444-555555555555.json")
        try Data("{}".utf8).write(to: staleRecipe)
        for file in [staleSound, staleRecipe] {
            try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: file.path)
        }
        let underWay = try audio("custom/\(SoundInstall.renderingPrefix)66666666-7777-8888-9999-000000000000.wav")

        XCTAssertEqual(importer.add(try audio("elsewhere/Pager.wav")), .success("Pager"))
        XCTAssertEqual(listing(), [underWay.lastPathComponent, "Pager.wav"].sorted(),
                       "the old leavings went with the add, and one that may be a save under way did not")
    }

    func testTheSweepSoundImportKeepsSweepsEveryStagedNameAndNoSetAsideOne() throws {
        try FileManager.default.createDirectory(at: custom, withIntermediateDirectories: true)
        let attempt = "11111111-2222-3333-4444-555555555555"
        try audio("custom/\(SoundInstall.addingPrefix)\(attempt).wav")
        try audio("custom/\(SoundInstall.renderingPrefix)\(attempt).wav")
        try Data("{}".utf8).write(to: custom.appendingPathComponent("\(SoundInstall.recipePrefix)\(attempt).json"))
        let hidden = SoundImport.asideName(for: "Alarm.wav", attempt: attempt, newType: "wav")
        try audio("custom/\(hidden)")
        SoundImport.removeStaleStagedCopies(in: custom, now: Date().addingTimeInterval(SoundImport.staleAfter + 1))
        XCTAssertEqual(listing(), [hidden])
    }

    func testTheChoosersWordsGiveTheLimitTheImportHolds() {
        XCTAssertTrue(EditorText.addSoundMessage.contains("up to \(Int(SoundImport.maximumSeconds)) seconds"))
    }

    // MARK: - The two halves of an add

    func testStagingGivesNothingANameAndMovesNothingARuleCanName() throws {
        XCTAssertEqual(importer.add(try audio("elsewhere/Alarm.wav", seconds: 0.1)), .success("Alarm"))
        let before = try Data(contentsOf: custom.appendingPathComponent("Alarm.wav"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("other"), withIntermediateDirectories: true)
        guard case .success(.staged(let staged)) = importer.stage(try audio("other/Alarm.wav", seconds: 0.3), replacing: true) else {
            return XCTFail("it was not staged")
        }
        XCTAssertEqual(staged.name, "Alarm")
        XCTAssertEqual(staged.type, "wav")
        XCTAssertEqual(staged.file.lastPathComponent, "\(SoundImport.stagedPrefix)\(staged.attempt).wav")
        XCTAssertEqual(listing(), [staged.file.lastPathComponent, "Alarm.wav"], "the old sound is where it was, under its name")
        XCTAssertEqual(try Data(contentsOf: custom.appendingPathComponent("Alarm.wav")), before)
        XCTAssertEqual(library.availableNames, ["Alarm"], "and the copy is not a sound yet")
        // A look at the folder while it waits, as a reload of the rules makes.
        XCTAssertEqual(importer.recoverSetAsideSounds(), [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: staged.file.path), "which leaves the waiting copy alone")

        XCTAssertEqual(importer.install(.staged(staged), replacing: true), .success("Alarm"))
        XCTAssertEqual(listing(), ["Alarm.wav"])
        XCTAssertNotEqual(try Data(contentsOf: custom.appendingPathComponent("Alarm.wav")), before)
    }

    func testAFileRefusedWhileStagingLeavesNothingBehind() throws {
        XCTAssertEqual(importer.stage(try audio("elsewhere/Hush.wav", amplitude: 0)), .failure(.silent))
        XCTAssertEqual(listing(), [])
        let fake = root.appendingPathComponent("elsewhere/Notes.wav")
        try Data("not samples".utf8).write(to: fake)
        guard case .failure(.unreadable) = importer.stage(fake) else { return XCTFail("a text file was staged") }
        XCTAssertEqual(listing(), [])
    }

    func testTheQuestionOfReplacingIsAskedBeforeTheFileIsReadAndAgainBeforeItIsNamed() throws {
        XCTAssertEqual(importer.add(try audio("elsewhere/Alarm.wav", seconds: 0.1)), .success("Alarm"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("other"), withIntermediateDirectories: true)
        let second = try audio("other/Alarm.wav", seconds: 0.3)
        XCTAssertEqual(importer.stage(second), .failure(.alreadyExists("Alarm")))
        XCTAssertEqual(listing(), ["Alarm.wav"], "refused before a copy was made")

        // A sound of the name arrives in the folder while another is staged.
        guard case .success(let staging) = importer.stage(try audio("elsewhere/Bell.wav", seconds: 0.2)) else { return XCTFail("not staged") }
        try FileManager.default.copyItem(at: second, to: custom.appendingPathComponent("Bell.caf"))
        XCTAssertEqual(importer.install(staging), .failure(.alreadyExists("Bell")))
        XCTAssertEqual(listing(), ["Alarm.wav", "Bell.caf"], "not replaced unasked, and the staged copy gone")
    }

    func testAFileAlreadyInTheFolderIsSaidToBeThereAndNotStaged() throws {
        XCTAssertEqual(importer.add(try audio("elsewhere/Pager.wav")), .success("Pager"))
        let staging = importer.stage(custom.appendingPathComponent("Pager.wav"))
        XCTAssertEqual(staging, .success(.alreadyThere("Pager")))
        XCTAssertEqual(importer.install(.alreadyThere("Pager")), .success("Pager"))
        XCTAssertEqual(listing(), ["Pager.wav"])
    }

    func testAnInstallThatFailsLeavesNoStagedCopy() throws {
        try FileManager.default.createDirectory(at: root.appendingPathComponent("other"), withIntermediateDirectories: true)
        guard case .success(let staging) = importer.stage(try audio("other/Alarm.wav", seconds: 0.3)) else { return XCTFail("not staged") }
        var failing = importer
        failing.move = { _, _ in throw CocoaError(.fileWriteNoPermission) }
        guard case .failure(.couldNotCopy) = failing.install(staging) else { return XCTFail("the install did not fail") }
        XCTAssertEqual(listing(), [])
    }

    // MARK: - A replace that was stopped in the middle

    private let attempt = "11111111-2222-3333-4444-555555555555"

    /// The folder as a replace leaves it when the app stops after setting the
    /// old sounds aside: each under its hidden name, and the copy that was to
    /// replace them still staged unless `renamed`.
    private func stopReplace(of old: [String], stagedAs staged: String?, attempt: String? = nil, newType: String = "wav") throws {
        let attempt = attempt ?? self.attempt
        try FileManager.default.createDirectory(at: custom, withIntermediateDirectories: true)
        for name in old {
            try FileManager.default.moveItem(at: custom.appendingPathComponent(name),
                                             to: custom.appendingPathComponent(SoundImport.asideName(for: name, attempt: attempt, newType: newType)))
        }
        if let staged { try audio("custom/\(SoundImport.stagedPrefix)\(attempt).\(staged)", seconds: 0.3) }
    }

    func testASoundSetAsideBeforeTheRenameIsPutBackUnderItsName() throws {
        XCTAssertEqual(importer.add(try audio("elsewhere/Alarm.wav", seconds: 0.1)), .success("Alarm"))
        let before = try Data(contentsOf: custom.appendingPathComponent("Alarm.wav"))
        try stopReplace(of: ["Alarm.wav"], stagedAs: "wav")
        XCTAssertNil(library.url(for: "Alarm"), "as the stop leaves it: a rule naming it finds nothing")

        XCTAssertEqual(importer.recoverSetAsideSounds(), ["Alarm"])
        XCTAssertEqual(listing(), ["Alarm.wav"], "back, and the copy that was to replace it gone")
        XCTAssertEqual(try Data(contentsOf: custom.appendingPathComponent("Alarm.wav")), before, "the old sound, not the new")
        XCTAssertEqual(importer.recoverSetAsideSounds(), [], "and asking again does nothing")
    }

    func testEverySoundOfANameSetAsideIsPutBackAndNotOnlyTheFirst() throws {
        XCTAssertEqual(importer.add(try audio("elsewhere/Alarm.wav", seconds: 0.1)), .success("Alarm"))
        try FileManager.default.copyItem(at: try audio("elsewhere/alarm.caf", seconds: 0.1), to: custom.appendingPathComponent("alarm.caf"))
        // Stopped with the staged copy already swept or lost, the worst case:
        // nothing says the replace was not finished but the free names.
        try stopReplace(of: ["Alarm.wav", "alarm.caf"], stagedAs: nil)
        XCTAssertEqual(importer.recoverSetAsideSounds().sorted(), ["Alarm", "alarm"])
        XCTAssertEqual(listing(), ["Alarm.wav", "alarm.caf"])
    }

    func testASoundSetAsideAfterTheRenameIsDeletedAndTheNewOneStays() throws {
        XCTAssertEqual(importer.add(try audio("elsewhere/Alarm.wav", seconds: 0.1)), .success("Alarm"))
        try stopReplace(of: ["Alarm.wav"], stagedAs: nil, newType: "caf")
        // The rename happened: the new sound has the name, of the type the
        // set-aside name says it would.
        try audio("custom/Alarm.caf", seconds: 0.3)
        let new = try Data(contentsOf: custom.appendingPathComponent("Alarm.caf"))
        XCTAssertEqual(importer.recoverSetAsideSounds(), [])
        XCTAssertEqual(listing(), ["Alarm.caf"])
        XCTAssertEqual(try Data(contentsOf: custom.appendingPathComponent("Alarm.caf")), new)
    }

    func testAnAddAfterAStoppedReplaceSeesTheOldSoundAndAsksBeforeReplacingIt() throws {
        XCTAssertEqual(importer.add(try audio("elsewhere/Alarm.wav", seconds: 0.1)), .success("Alarm"))
        try stopReplace(of: ["Alarm.wav"], stagedAs: "wav")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("other"), withIntermediateDirectories: true)
        XCTAssertEqual(importer.add(try audio("other/Alarm.wav", seconds: 0.2)), .failure(.alreadyExists("Alarm")),
                       "it is put back first, so it is not replaced unasked")
        XCTAssertEqual(listing(), ["Alarm.wav"])
    }

    func testAReplaceSetsTheOldSoundAsideUnderANameThatSaysWhatItWas() throws {
        XCTAssertEqual(importer.add(try audio("elsewhere/Night Pager.wav", seconds: 0.1)), .success("Night Pager"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("other"), withIntermediateDirectories: true)
        var seen: [String] = []
        var stagedName = ""
        var watching = importer
        watching.move = { [custom] from, to in
            stagedName = from.lastPathComponent
            seen = ((try? FileManager.default.contentsOfDirectory(atPath: custom.path)) ?? []).filter { $0.hasPrefix(SoundImport.asidePrefix) }
            try FileManager.default.moveItem(at: from, to: to)
        }
        XCTAssertEqual(watching.add(try audio("other/Night Pager.wav", seconds: 0.3), replacing: true), .success("Night Pager"))
        XCTAssertEqual(seen.count, 1)
        let held = try XCTUnwrap(SoundImport.setAside(seen[0]))
        XCTAssertEqual(held.fileName, "Night Pager.wav")
        XCTAssertEqual(held.newType, "wav")
        XCTAssertEqual(stagedName, "\(SoundImport.stagedPrefix)\(held.attempt).wav",
                       "the staged copy and the set-aside sound are of one attempt, which is how a stopped replace is finished")
        XCTAssertEqual(listing(), ["Night Pager.wav"], "and nothing hidden is left when it finishes")
    }

    func testAnUndoingThatCouldNotPutOneBackIsNotTakenForAFinishedReplace() throws {
        // Two files of the name were set aside, the rename failed, and the
        // undoing put one back and not the other. No staged copy is left, and
        // a file holds the name: but not the new sound, which never arrived.
        XCTAssertEqual(importer.add(try audio("elsewhere/Alarm.wav", seconds: 0.1)), .success("Alarm"))
        let old = try Data(contentsOf: custom.appendingPathComponent("Alarm.wav"))
        try FileManager.default.copyItem(at: try audio("elsewhere/alarm.caf", seconds: 0.1), to: custom.appendingPathComponent("alarm.caf"))
        try stopReplace(of: ["Alarm.wav"], stagedAs: nil, newType: "m4a")
        XCTAssertEqual(importer.recoverSetAsideSounds(), ["Alarm"])
        XCTAssertEqual(listing(), ["Alarm.wav", "alarm.caf"])
        XCTAssertEqual(try Data(contentsOf: custom.appendingPathComponent("Alarm.wav")), old)
    }

    func testAFileOfTheNameThatIsNotTheNewSoundDoesNotGetTheOldOneDeleted() throws {
        // Put there by hand while the old one was hidden, and of another type
        // than the sound that was to replace it.
        XCTAssertEqual(importer.add(try audio("elsewhere/Alarm.wav", seconds: 0.1)), .success("Alarm"))
        try stopReplace(of: ["Alarm.wav"], stagedAs: nil, newType: "caf")
        try audio("custom/Alarm.mp3.wav", seconds: 0.1)
        try FileManager.default.moveItem(at: custom.appendingPathComponent("Alarm.mp3.wav"), to: custom.appendingPathComponent("Alarm.aiff"))
        XCTAssertEqual(importer.recoverSetAsideSounds(), ["Alarm"])
        XCTAssertEqual(listing(), ["Alarm.aiff", "Alarm.wav"], "both there, and nothing deleted")
    }

    func testAStopPartWayThroughDeletingTheOldOnesFinishesTheDeleting() throws {
        XCTAssertEqual(importer.add(try audio("elsewhere/Alarm.wav", seconds: 0.1)), .success("Alarm"))
        try FileManager.default.copyItem(at: try audio("elsewhere/alarm.caf", seconds: 0.1), to: custom.appendingPathComponent("alarm.caf"))
        try stopReplace(of: ["Alarm.wav", "alarm.caf"], stagedAs: nil, newType: "m4a")
        // The new sound arrived, and the first of the two old ones was deleted.
        try FileManager.default.removeItem(at: custom.appendingPathComponent(
            SoundImport.asideName(for: "Alarm.wav", attempt: attempt, newType: "m4a")))
        try FileManager.default.copyItem(at: try audio("elsewhere/New.wav", seconds: 0.3), to: custom.appendingPathComponent("Alarm.m4a"))
        XCTAssertEqual(importer.recoverSetAsideSounds(), [])
        XCTAssertEqual(listing(), ["Alarm.m4a"])
    }

    func testAStopAfterOnlyTheFirstWasSetAsidePutsItBackAndLeavesTheOther() throws {
        XCTAssertEqual(importer.add(try audio("elsewhere/Alarm.wav", seconds: 0.1)), .success("Alarm"))
        try FileManager.default.copyItem(at: try audio("elsewhere/alarm.caf", seconds: 0.1), to: custom.appendingPathComponent("alarm.caf"))
        try stopReplace(of: ["Alarm.wav"], stagedAs: "wav")
        XCTAssertEqual(importer.recoverSetAsideSounds(), ["Alarm"])
        XCTAssertEqual(listing(), ["Alarm.wav", "alarm.caf"])
    }

    func testASetAsideSoundWhoseOwnFileNameIsTakenIsLeftHiddenAndNotDeleted() throws {
        XCTAssertEqual(importer.add(try audio("elsewhere/Alarm.wav", seconds: 0.1)), .success("Alarm"))
        try stopReplace(of: ["Alarm.wav"], stagedAs: nil, newType: "caf")
        try audio("custom/Alarm.wav", seconds: 0.2)
        XCTAssertEqual(importer.recoverSetAsideSounds(), [])
        XCTAssertEqual(listing(), [SoundImport.asideName(for: "Alarm.wav", attempt: attempt, newType: "caf"), "Alarm.wav"],
                       "neither proved replaced nor able to go back: kept")
    }

    func testASoundWhoseNameIsTooLongToSetAsideIsNotReplacedAndStaysAsItWas() throws {
        // 70 characters of three bytes each: a name a file may have, and too
        // long once the hidden name's own part is put before it.
        let long = String(repeating: "警", count: 70)
        try FileManager.default.createDirectory(at: custom, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: try audio("elsewhere/Seed.wav", seconds: 0.1), to: custom.appendingPathComponent("\(long).wav"))
        let before = listing()
        try FileManager.default.createDirectory(at: root.appendingPathComponent("other"), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: try audio("elsewhere/New2.wav", seconds: 0.3), to: root.appendingPathComponent("other/\(long).wav"))
        XCTAssertEqual(importer.add(root.appendingPathComponent("other/\(long).wav"), replacing: true), .failure(.cannotSetAside(long)))
        XCTAssertEqual(listing(), before, "untouched, and nothing staged left")
    }

    func testOnlyNamesThisMakesAreReadAsSetAside() {
        XCTAssertNil(SoundImport.setAside(".replacing-not-a-uuid-Alarm.wav"))
        XCTAssertNil(SoundImport.setAside(".replacing-\(attempt).wav"), "the name 1.3's first builds gave, which says no name: left alone")
        XCTAssertNil(SoundImport.setAside(".replacing-\(attempt)-"))
        XCTAssertNil(SoundImport.setAside(".replacing-\(attempt)-wav-"))
        XCTAssertNil(SoundImport.setAside(".replacing-\(attempt)-wav-.hidden.wav"))
        XCTAssertNil(SoundImport.setAside(".replacing-\(attempt)-txt-Alarm.wav"), "no sound is of that type")
        XCTAssertNil(SoundImport.setAside(".replacing-\(attempt)-wav-Alarm.txt"))
        XCTAssertNil(SoundImport.setAside(".replacing-\(attempt)-Alarm.wav"), "with no type for the new sound")
        XCTAssertNil(SoundImport.setAside(".adding-\(attempt).wav"))
        XCTAssertNil(SoundImport.setAside("Alarm.wav"))
        let read = SoundImport.setAside(SoundImport.asideName(for: "a-b - c.d.wav", attempt: attempt, newType: "m4a"))
        XCTAssertEqual(read?.fileName, "a-b - c.d.wav")
        XCTAssertEqual(read?.newType, "m4a")
        XCTAssertEqual(read?.attempt, attempt)
    }

    func testAHiddenFileThatIsNotOneOfTheseIsLeftAsItIs() throws {
        try FileManager.default.createDirectory(at: custom, withIntermediateDirectories: true)
        try audio("custom/.replacing-\(attempt).wav")
        try audio("custom/.something-else.wav")
        XCTAssertEqual(importer.recoverSetAsideSounds(), [])
        XCTAssertEqual(listing(), [".replacing-\(attempt).wav", ".something-else.wav"])
    }

    func testTwoStoppedReplacesAreEachFinishedByTheirOwnStagedCopy() throws {
        XCTAssertEqual(importer.add(try audio("elsewhere/Alarm.wav", seconds: 0.1)), .success("Alarm"))
        XCTAssertEqual(importer.add(try audio("elsewhere/Bell.wav", seconds: 0.1)), .success("Bell"))
        let other = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        try stopReplace(of: ["Alarm.wav"], stagedAs: "wav")
        try stopReplace(of: ["Bell.wav"], stagedAs: nil, attempt: other, newType: "caf")
        try audio("custom/Bell.caf", seconds: 0.3)
        XCTAssertEqual(importer.recoverSetAsideSounds(), ["Alarm"])
        XCTAssertEqual(listing(), ["Alarm.wav", "Bell.caf"])
    }

    func testWithNoSoundsFolderThereIsNothingToPutBack() {
        XCTAssertEqual(importer.recoverSetAsideSounds(), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: custom.path), "and the folder is not made to look")
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
                                               .alreadyExists("Alarm"), .cannotSetAside("Alarm"), .couldNotCopy("x")]
        for refusal in refusals { XCTAssertFalse(refusal.description.isEmpty) }
        XCTAssertTrue(SoundImport.Refusal.unsupportedType("txt").description.contains(".aif, .aiff, .caf, .m4a, .mp3 or .wav"))
    }

    func testTheFolderIsMadeOnceAndAskingAgainIsNotAnError() throws {
        XCTAssertEqual(try importer.makeFolder().path, custom.path)
        XCTAssertEqual(try importer.makeFolder().path, custom.path)
    }
}
