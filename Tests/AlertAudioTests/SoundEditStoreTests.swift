import AVFoundation
import CryptoKit
import XCTest
@testable import AlertAudio
import NotificationCore

/// Opening and saving an edited sound, against real folders and real audio files (sound editor plan,
/// Task 5). What is held is what can cost a user a sound: a failed save leaves every file as it was, a
/// recipe is trusted only for the file it made, a render that cannot be heard or is too long is never
/// given a name, and nothing is left hidden but the edits themselves.
final class SoundEditStoreTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("SoundEditStoreTests-\(UUID().uuidString)")
        for folder in ["system", "custom"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private var custom: URL { root.appendingPathComponent("custom") }
    private var edits: URL { custom.appendingPathComponent(".edits") }

    private var library: SoundLibrary {
        SoundLibrary(systemDirectory: root.appendingPathComponent("system"), customDirectory: custom)
    }

    private var store: SoundEditStore { SoundEditStore(library: library) }

    @discardableResult
    private func tone(_ path: String, seconds: Double = 0.5, amplitude: Float = 0.5, step: Float = 0.3) throws -> URL {
        try TestAudio.write(root.appendingPathComponent(path), seconds: seconds, rate: 8_000, channels: 1,
                            amplitude: amplitude, step: step)
    }

    private func opened(_ name: String, using store: SoundEditStore? = nil, file: StaticString = #filePath,
                        line: UInt = #line) throws -> SoundEditStore.Opened {
        switch (store ?? self.store).open(name) {
        case .success(let opened): return opened
        case .failure(let failure):
            XCTFail("\(name) did not open: \(failure)", file: file, line: line)
            throw failure
        }
    }

    private func listing(_ folder: URL? = nil) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: (folder ?? custom).path)) ?? []).sorted()
    }

    private func bytes(_ path: String) throws -> Data {
        try Data(contentsOf: root.appendingPathComponent(path))
    }

    private func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Every file and folder under the sounds folder, with its bytes: the whole of what a save may change.
    private func snapshot() -> [String: Data?] {
        var found: [String: Data?] = [:]
        let walk = FileManager.default.enumerator(at: custom, includingPropertiesForKeys: [.isDirectoryKey], options: [])!
        for case let url as URL in walk {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            found[url.path.replacingOccurrences(of: custom.path + "/", with: "")] = isDirectory ? .some(nil) : try? Data(contentsOf: url)
        }
        return found
    }

    /// A recipe of `opened`'s sound with a gain on its first tenth, which is an edit that cannot make it silent.
    private func louder(_ opened: SoundEditStore.Opened, by dB: Double = 6) throws -> SoundRecipe {
        try SoundEdit.gain(0..<(opened.source.frameCount / 10), dB: dB).applied(to: opened.recipe)
    }

    private func saved(_ recipe: SoundRecipe, of opened: SoundEditStore.Opened, as name: String, replacing: Bool = false,
                       using store: SoundEditStore? = nil) -> Result<SoundEditStore.Saved, SoundSaveFailure> {
        (store ?? self.store).save(recipe, of: opened, as: name, replacing: replacing)
    }

    private func sidecar(_ name: String) -> URL { edits.appendingPathComponent("\(name).edit") }

    // MARK: - Opening

    func testAPlainSoundOpensAsTheWholeOfItselfWithTheDigestOfItsBytes() throws {
        let file = try tone("custom/Alarm.wav")
        let opened = try opened("alarm")
        XCTAssertEqual(opened.name, "Alarm", "spelt as the file is")
        XCTAssertFalse(opened.hasEdits)
        XCTAssertTrue(opened.recipe.isOriginal)
        XCTAssertEqual(opened.recipe.frameCount, opened.source.frameCount)
        XCTAssertEqual(Double(opened.source.frameCount), 0.5 * 48_000, accuracy: 64)
        XCTAssertEqual(opened.source.channelCount, 2)
        XCTAssertEqual(opened.recipe.source.frames, opened.source.frameCount)
        XCTAssertEqual(opened.recipe.source.digest, digest(try Data(contentsOf: file)))
        XCTAssertTrue(opened.recipe.source.name.hasPrefix("source-") && opened.recipe.source.name.hasSuffix(".wav"),
                      opened.recipe.source.name)
        XCTAssertEqual(opened.sourceFile.resolvingSymlinksInPath(), file.resolvingSymlinksInPath())
        XCTAssertEqual(listing(), ["Alarm.wav"], "opening writes nothing")
    }

    func testAMacOSSoundOpensAsAPlainSoundUnderTheNameMacOSSpellsIt() throws {
        try TestAudio.write(root.appendingPathComponent("system/Glass.aiff"))
        let opened = try opened("glass")
        XCTAssertEqual(opened.name, "Glass")
        XCTAssertFalse(opened.hasEdits)
        XCTAssertTrue(opened.recipe.source.name.hasSuffix(".aiff"), opened.recipe.source.name)
        XCTAssertEqual(listing(), [])
    }

    func testASoundThatIsNotThereAndOneThatIsNotAudioAreRefusedInWords() throws {
        XCTAssertEqual(store.open("Nope"), .failure(.notFound("Nope")))
        try Data("not audio".utf8).write(to: custom.appendingPathComponent("Junk.wav"))
        guard case .failure(.unreadable(let reason)) = store.open("Junk") else { return XCTFail("a file of text opened") }
        XCTAssertFalse(reason.isEmpty)
        try TestAudio.write(custom.appendingPathComponent("Empty.wav"), seconds: 0)
        guard case .failure(.unreadable) = store.open("Empty") else { return XCTFail("a file with no audio in it opened") }
    }

    func testAFileOverTheSizeAnAddedSoundMayBeIsRefusedUnread() throws {
        let big = custom.appendingPathComponent("Big.wav")
        FileManager.default.createFile(atPath: big.path, contents: nil)
        let handle = try FileHandle(forWritingTo: big)
        try handle.truncate(atOffset: UInt64(SoundImport.maximumBytes + 1))
        try handle.close()
        XCTAssertEqual(store.open("Big"), .failure(.tooLarge(limitMegabytes: SoundImport.maximumBytes / 1_048_576)))
    }

    func testASoundOverOneHundredTwentySecondsIsRefusedWithItsLength() throws {
        try tone("custom/Long.wav", seconds: 121)
        XCTAssertEqual(store.open("Long"), .failure(.tooLong(frames: 121 * SampleBuffer.sampleRate)))
    }

    func testASoundOpensOffTheMainActor() async throws {
        try tone("custom/Alarm.wav")
        let library = self.library
        let result = await Task.detached { SoundEditStore(library: library).open("Alarm") }.value
        guard case .success = result else { return XCTFail("\(result)") }
    }

    // MARK: - Saving

    func testASaveAsNewMakesTheSoundAndItsEditsAndNothingElseIsLeft() throws {
        let original = try tone("custom/Alarm.wav")
        let source = try opened("Alarm")
        let recipe = try louder(source)

        XCTAssertEqual(saved(recipe, of: source, as: "Alarm 2"), .success(.saved("Alarm 2")))

        XCTAssertEqual(listing(), [".edits", "Alarm 2.wav", "Alarm.wav"], "no staged file is left")
        XCTAssertEqual(library.availableNames, ["Alarm", "Alarm 2"], "the library lists the sounds and nothing else")
        XCTAssertEqual(listing(sidecar("Alarm 2")), ["recipe.json", source.recipe.source.name].sorted())
        XCTAssertEqual(try Data(contentsOf: sidecar("Alarm 2").appendingPathComponent(source.recipe.source.name)),
                       try Data(contentsOf: original), "the copy of what it was made from")
        XCTAssertEqual(listing(edits), ["Alarm 2.edit"])
    }

    func testTheFileIs48kHzStereoFloatAndKeepsALevelOverFullScale() throws {
        try tone("custom/Alarm.wav", amplitude: 0.8)
        let source = try opened("Alarm")
        let recipe = try SoundEdit.gain(0..<source.source.frameCount, dB: 6).applied(to: source.recipe)
        XCTAssertEqual(saved(recipe, of: source, as: "Loud"), .success(.saved("Loud")))

        let file = try AVAudioFile(forReading: custom.appendingPathComponent("Loud.wav"))
        XCTAssertEqual(file.fileFormat.sampleRate, 48_000)
        XCTAssertEqual(file.fileFormat.channelCount, 2)
        XCTAssertEqual(file.fileFormat.commonFormat, .pcmFormatFloat32)
        XCTAssertEqual(Int(file.length), recipe.frameCount)
        let read = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: read)
        let rendered = SoundRender.render(source: source.source, recipe: recipe)
        XCTAssertGreaterThan(rendered.peak, 1.5)
        for channel in 0..<2 {
            XCTAssertEqual(Array(UnsafeBufferPointer(start: read.floatChannelData![channel], count: Int(read.frameLength))),
                           rendered.channels[channel], "what was heard in the window is what is kept, above full scale and all")
        }
    }

    func testAMacOSSoundIsSavedAsACopyAndItsSourceIsKeptBesideIt() throws {
        let glass = try TestAudio.write(root.appendingPathComponent("system/Glass.aiff"))
        try FileManager.default.removeItem(at: custom)
        let source = try opened("Glass")
        let recipe = try louder(source)

        XCTAssertEqual(saved(recipe, of: source, as: "Glass", replacing: true), .failure(.systemSound("Glass")))
        XCTAssertEqual(saved(recipe, of: source, as: "glass", replacing: true), .failure(.systemSound("Glass")))
        XCTAssertFalse(FileManager.default.fileExists(atPath: custom.path), "a refused save makes nothing, not even the folder")

        XCTAssertEqual(saved(recipe, of: source, as: "Glass 2"), .success(.saved("Glass 2")))
        XCTAssertEqual(listing(), [".edits", "Glass 2.wav"])
        XCTAssertEqual(try Data(contentsOf: sidecar("Glass 2").appendingPathComponent(source.recipe.source.name)),
                       try Data(contentsOf: glass))
        XCTAssertEqual(library.availableNames, ["Glass", "Glass 2"])
    }

    func testASoundTheUserHasIsReplacedOnlyWhenAskedAndRefusedWithEverythingAsItWas() throws {
        try tone("custom/Alarm.wav")
        try tone("custom/Bell.wav", step: 0.7)
        let source = try opened("Bell")
        let before = snapshot()

        XCTAssertEqual(saved(try louder(source), of: source, as: "alarm"), .failure(.alreadyExists("Alarm")))
        XCTAssertEqual(snapshot(), before)
    }

    func testASaveOverASoundReplacesItAndItsEditsOpenAgainAndAgain() throws {
        let original = try tone("custom/Alarm.wav")
        let originalBytes = try Data(contentsOf: original)
        let plain = try opened("Alarm")
        let first = try louder(plain)

        XCTAssertEqual(saved(first, of: plain, as: "Alarm", replacing: true), .success(.saved("Alarm")))
        XCTAssertNotEqual(try Data(contentsOf: original), originalBytes)
        XCTAssertEqual(listing(), [".edits", "Alarm.wav"])

        let again = try opened("Alarm")
        XCTAssertTrue(again.hasEdits)
        XCTAssertEqual(again.recipe, first)
        XCTAssertEqual(again.source, plain.source, "the source is what the sound was before, kept beside it")
        XCTAssertEqual(again.sourceFile.resolvingSymlinksInPath().deletingLastPathComponent(),
                       sidecar("Alarm").resolvingSymlinksInPath())

        let second = try SoundEdit.fadeOut(0..<4_800).applied(to: first)
        XCTAssertEqual(saved(second, of: again, as: "Alarm", replacing: true), .success(.saved("Alarm")))
        XCTAssertEqual(listing(), [".edits", "Alarm.wav"])
        XCTAssertEqual(listing(sidecar("Alarm")), ["recipe.json", plain.recipe.source.name].sorted(), "one recipe and one source")
        let third = try opened("Alarm")
        XCTAssertTrue(third.hasEdits)
        XCTAssertEqual(third.recipe, second)
        XCTAssertEqual(try Data(contentsOf: sidecar("Alarm").appendingPathComponent(plain.recipe.source.name)), originalBytes)
    }

    func testAPlainSoundOpenedOnceCanBeSavedOverAndThenSavedAgainAsNewAndOverAgain() throws {
        let original = try tone("custom/Alarm.wav")
        let originalBytes = try Data(contentsOf: original)
        let plain = try opened("Alarm")
        let first = try louder(plain)
        XCTAssertEqual(saved(first, of: plain, as: "Alarm", replacing: true), .success(.saved("Alarm")))

        // The file the window opened is now the sound it saved, and nothing was changed outside the editor.
        let second = try SoundEdit.fadeOut(0..<4_800).applied(to: first)
        XCTAssertEqual(saved(second, of: plain, as: "Alarm 2"), .success(.saved("Alarm 2")))
        XCTAssertEqual(saved(second, of: plain, as: "Alarm", replacing: true), .success(.saved("Alarm")))

        XCTAssertEqual(listing(), [".edits", "Alarm 2.wav", "Alarm.wav"])
        for name in ["Alarm", "Alarm 2"] {
            let again = try opened(name)
            XCTAssertTrue(again.hasEdits, name)
            XCTAssertEqual(again.recipe, second, name)
            XCTAssertEqual(again.source, plain.source, name)
            XCTAssertEqual(try Data(contentsOf: sidecar(name).appendingPathComponent(plain.recipe.source.name)), originalBytes, name)
        }
    }

    func testAnEditedSoundOpenedOnceCanBeSavedOverAgainAndAgain() throws {
        try tone("custom/Alarm.wav")
        let plain = try opened("Alarm")
        XCTAssertEqual(saved(try louder(plain), of: plain, as: "Alarm", replacing: true), .success(.saved("Alarm")))
        let edited = try opened("Alarm")
        let second = try SoundEdit.fadeOut(0..<4_800).applied(to: edited.recipe)
        let third = try SoundEdit.fadeIn(0..<2_400).applied(to: second)

        XCTAssertEqual(saved(second, of: edited, as: "Alarm", replacing: true), .success(.saved("Alarm")))
        XCTAssertEqual(saved(third, of: edited, as: "Alarm", replacing: true), .success(.saved("Alarm")))
        XCTAssertEqual(try opened("Alarm").recipe, third)
        XCTAssertEqual(listing(), [".edits", "Alarm.wav"])
    }

    func testAnEditedSoundReplacedOutsideTheEditorSinceItWasOpenedIsNotSavedOver() throws {
        try tone("custom/Alarm.wav")
        let plain = try opened("Alarm")
        XCTAssertEqual(saved(try louder(plain), of: plain, as: "Alarm", replacing: true), .success(.saved("Alarm")))
        let edited = try opened("Alarm")
        let recipe = try SoundEdit.fadeIn(0..<2_400).applied(to: edited.recipe)

        // A recording the user cares about is put in its place, in the Finder, while the window is open.
        let theirs = try tone("custom/Alarm.wav", seconds: 0.25, step: 0.9)
        let theirBytes = try Data(contentsOf: theirs)
        let before = snapshot()
        XCTAssertEqual(saved(recipe, of: edited, as: "Alarm", replacing: true), .failure(.sourceChanged))
        XCTAssertEqual(snapshot(), before, "it is neither set aside nor deleted")
        XCTAssertEqual(try Data(contentsOf: theirs), theirBytes)

        XCTAssertEqual(saved(recipe, of: edited, as: "Alarm 2"), .success(.saved("Alarm 2")), "a copy takes nothing from it")
    }

    /// Alarm, made by the editor from one sound, and Bell, a plain sound of another: saving Bell's edits over Alarm
    /// is a save over a sound whose folder holds a source the new edits do not use.
    private func alarmFromOneSourceAndBellFromAnother() throws -> (alarmSource: String, bell: SoundEditStore.Opened) {
        try tone("custom/Alarm.wav")
        let plain = try opened("Alarm")
        XCTAssertEqual(saved(try louder(plain), of: plain, as: "Alarm", replacing: true), .success(.saved("Alarm")))
        try tone("custom/Bell.wav", step: 0.7)
        return (plain.recipe.source.name, try opened("Bell"))
    }

    func testASaveOverASoundMadeFromAnotherSourceTakesAwayTheSourceItNoLongerUses() throws {
        let (alarmSource, bell) = try alarmFromOneSourceAndBellFromAnother()
        XCTAssertNotEqual(alarmSource, bell.recipe.source.name)
        XCTAssertEqual(saved(try louder(bell), of: bell, as: "Alarm", replacing: true), .success(.saved("Alarm")))
        XCTAssertEqual(listing(sidecar("Alarm")), ["recipe.json", bell.recipe.source.name].sorted(),
                       "what the sound it replaced was made from is not kept for nothing")
        XCTAssertTrue(try opened("Alarm").hasEdits)
    }

    func testASaveOverASoundMadeFromAnotherSourceThatFailsLeavesItsSourceAndTakesBackTheNewOne() throws {
        let (_, bell) = try alarmFromOneSourceAndBellFromAnother()
        let before = snapshot()
        var failing = store
        failing.move = { _, _ in throw CocoaError(.fileWriteNoPermission) }
        guard case .failure(.couldNotWrite) = saved(try louder(bell), of: bell, as: "Alarm", replacing: true, using: failing) else {
            return XCTFail("the save did not fail")
        }
        XCTAssertEqual(snapshot(), before)
        XCTAssertTrue(try opened("Alarm").hasEdits)
    }

    func testASaveAsNewFromAnEditedSoundGivesTheNewSoundASourceOfItsOwn() throws {
        try tone("custom/Alarm.wav")
        let plain = try opened("Alarm")
        let recipe = try louder(plain)
        XCTAssertEqual(saved(recipe, of: plain, as: "Alarm", replacing: true), .success(.saved("Alarm")))
        let edited = try opened("Alarm")
        let alarmRecipe = try bytes("custom/.edits/Alarm.edit/recipe.json")

        XCTAssertEqual(saved(try SoundEdit.fadeIn(0..<2_400).applied(to: edited.recipe), of: edited, as: "Alarm 2"),
                       .success(.saved("Alarm 2")))
        XCTAssertEqual(try bytes("custom/.edits/Alarm.edit/recipe.json"), alarmRecipe, "the sound it came from is as it was")

        try FileManager.default.removeItem(at: sidecar("Alarm"))
        let second = try opened("Alarm 2")
        XCTAssertTrue(second.hasEdits, "it does not lean on the other sound's folder")
        XCTAssertEqual(second.source, plain.source)
    }

    func testARenderThatCannotBeHeardNeverGetsANameAndNothingIsLeft() throws {
        try tone("custom/Alarm.wav", amplitude: 0.5)
        let source = try opened("Alarm")
        let silent = try SoundEdit.gain(0..<source.source.frameCount, dB: -60).applied(to: source.recipe)
        let before = snapshot()
        XCTAssertEqual(saved(silent, of: source, as: "Quiet"), .failure(.silent))
        XCTAssertEqual(saved(silent, of: source, as: "Alarm", replacing: true), .failure(.silent))
        XCTAssertEqual(snapshot(), before)
    }

    func testARenderOverThirtySecondsNeverGetsANameAndNothingIsLeft() throws {
        try tone("custom/Long.wav", seconds: 31)
        let source = try opened("Long")
        XCTAssertFalse(source.recipe.canBeSaved)
        let before = snapshot()
        XCTAssertEqual(saved(source.recipe, of: source, as: "Long 2"), .failure(.tooLong))
        XCTAssertEqual(snapshot(), before)
    }

    func testAFailedRenameOfTheSoundPutsTheOldSoundAndItsEditsBack() throws {
        try tone("custom/Alarm.wav")
        let plain = try opened("Alarm")
        XCTAssertEqual(saved(try louder(plain), of: plain, as: "Alarm", replacing: true), .success(.saved("Alarm")))
        let edited = try opened("Alarm")
        let before = snapshot()

        var failing = store
        failing.move = { _, _ in throw CocoaError(.fileWriteNoPermission) }
        guard case .failure(.couldNotWrite(let reason)) = saved(try SoundEdit.fadeIn(0..<2_400).applied(to: edited.recipe),
                                                                of: edited, as: "Alarm", replacing: true, using: failing) else {
            return XCTFail("the save did not fail")
        }
        XCTAssertNotNil(reason)
        XCTAssertEqual(snapshot(), before, "every file, the sound and its recipe and its source and nothing hidden, as it was")
        XCTAssertTrue(try opened("Alarm").hasEdits)
    }

    func testAFailedRenameOfANewSoundLeavesNothingAtAll() throws {
        try tone("custom/Alarm.wav")
        let plain = try opened("Alarm")
        let before = snapshot()
        var failing = store
        failing.move = { _, _ in throw CocoaError(.fileWriteNoPermission) }
        guard case .failure(.couldNotWrite) = saved(try louder(plain), of: plain, as: "Alarm 2", using: failing) else {
            return XCTFail("the save did not fail")
        }
        XCTAssertEqual(snapshot(), before, "not even the sidecar the first save would have made")
    }

    func testARecipeThatCannotBeNamedAfterTheSoundWasSavesAPlainSoundAndSaysSo() throws {
        try tone("custom/Alarm.wav")
        let source = try opened("Alarm")
        var failing = store
        failing.move = { from, to in
            if to.lastPathComponent == "recipe.json" { throw CocoaError(.fileWriteNoPermission) }
            try FileManager.default.moveItem(at: from, to: to)
        }
        let recipe = try louder(source)
        XCTAssertEqual(saved(recipe, of: source, as: "Alarm 2", using: failing), .success(.savedWithoutEdits("Alarm 2")))

        XCTAssertEqual(listing(), ["Alarm 2.wav", "Alarm.wav"], "the sound is kept, and nothing is left of edits that cannot be reopened")
        let file = try AVAudioFile(forReading: custom.appendingPathComponent("Alarm 2.wav"))
        XCTAssertEqual(Int(file.length), recipe.frameCount)
        let plain = try opened("Alarm 2")
        XCTAssertFalse(plain.hasEdits)
        XCTAssertTrue(plain.recipe.isOriginal)
    }

    func testAReplacedSoundWhoseNewRecipeCannotBeNamedIsPlainAndKeepsNoStaleEdits() throws {
        try tone("custom/Alarm.wav")
        let plain = try opened("Alarm")
        XCTAssertEqual(saved(try louder(plain), of: plain, as: "Alarm", replacing: true), .success(.saved("Alarm")))
        let edited = try opened("Alarm")
        var failing = store
        failing.move = { from, to in
            if to.lastPathComponent == "recipe.json" { throw CocoaError(.fileWriteNoPermission) }
            try FileManager.default.moveItem(at: from, to: to)
        }
        XCTAssertEqual(saved(try SoundEdit.fadeIn(0..<2_400).applied(to: edited.recipe), of: edited, as: "Alarm", replacing: true,
                             using: failing), .success(.savedWithoutEdits("Alarm")))
        XCTAssertEqual(listing(), ["Alarm.wav"])
        XCTAssertFalse(try opened("Alarm").hasEdits)
    }

    func testASoundChangedSinceItWasOpenedIsNotSavedFromAndNothingIsLeft() throws {
        try tone("custom/Alarm.wav")
        let source = try opened("Alarm")
        let recipe = try louder(source)
        try tone("custom/Alarm.wav", step: 0.9)
        let before = snapshot()
        XCTAssertEqual(saved(recipe, of: source, as: "Alarm 2"), .failure(.sourceChanged))
        XCTAssertEqual(snapshot(), before)
    }

    func testARecipeOfAnotherSoundIsNotSavedAsThisOne() throws {
        try tone("custom/Alarm.wav")
        try tone("custom/Bell.wav", step: 0.9)
        let alarm = try opened("Alarm")
        let bell = try opened("Bell")
        let before = snapshot()
        XCTAssertEqual(saved(try louder(bell), of: alarm, as: "Alarm 2"), .failure(.sourceChanged))
        XCTAssertEqual(snapshot(), before)
    }

    func testANameThatCannotBeASoundsIsRefusedAndNothingIsLeft() throws {
        try tone("custom/Alarm.wav")
        let source = try opened("Alarm")
        let before = snapshot()
        for name in ["", ".hidden", "a/b", " padded "] {
            XCTAssertEqual(saved(try louder(source), of: source, as: name, replacing: true), .failure(.badName), name)
        }
        XCTAssertEqual(snapshot(), before)
    }

    func testASoundThatAStoppedReplaceLeftSetAsideIsPutBackBeforeTheSaveLooksAtTheFolder() throws {
        try tone("custom/Alarm.wav")
        let source = try opened("Alarm")
        let attempt = "11111111-2222-3333-4444-555555555555"
        try FileManager.default.moveItem(
            at: custom.appendingPathComponent("Alarm.wav"),
            to: custom.appendingPathComponent(SoundInstall.asideName(for: "Alarm.wav", attempt: attempt, newType: "wav")))
        try tone("custom/\(SoundInstall.renderingPrefix)\(attempt).wav")
        XCTAssertEqual(saved(try louder(source), of: source, as: "Alarm"), .failure(.alreadyExists("Alarm")),
                       "it is asked about as the sound it is, which the stopped replace had hidden")
        XCTAssertEqual(listing(), ["Alarm.wav"])
    }

    // MARK: - A recipe is trusted only for the file it made

    private func savedAlarm() throws -> SoundRecipe {
        try tone("custom/Alarm.wav")
        let plain = try opened("Alarm")
        let recipe = try louder(plain)
        XCTAssertEqual(saved(recipe, of: plain, as: "Alarm 2"), .success(.saved("Alarm 2")))
        return recipe
    }

    func testASoundReplacedOutsideTheEditorOpensAsAPlainSoundAndItsEditsAreLeftAlone() throws {
        _ = try savedAlarm()
        let stored = try bytes("custom/.edits/Alarm 2.edit/recipe.json")
        try tone("custom/Alarm 2.wav", seconds: 0.25, step: 0.9)

        let opened = try opened("Alarm 2")
        XCTAssertFalse(opened.hasEdits)
        XCTAssertTrue(opened.recipe.isOriginal)
        XCTAssertEqual(Double(opened.source.frameCount), 0.25 * 48_000, accuracy: 64, "the file that is there is the source now")
        XCTAssertEqual(try bytes("custom/.edits/Alarm 2.edit/recipe.json"), stored, "opening changes nothing")
    }

    func testARecipeThatCannotBeReadOrIsNewerOrWhoseSourceIsGoneOrChangedOpensAsAPlainSound() throws {
        let recipe = try savedAlarm()
        let sidecar = self.sidecar("Alarm 2")
        let recipeFile = sidecar.appendingPathComponent("recipe.json")
        let good = try Data(contentsOf: recipeFile)
        let sourceFile = sidecar.appendingPathComponent(try opened("Alarm").recipe.source.name)
        let goodSource = try Data(contentsOf: sourceFile)
        XCTAssertEqual(try opened("Alarm 2").recipe, recipe, "to begin with it is trusted")

        let spoiled: [(String, () throws -> Void)] = [
            ("not a recipe", { try Data("garbage".utf8).write(to: recipeFile) }),
            ("a newer version", {
                try Data(String(decoding: good, as: UTF8.self).replacingOccurrences(of: "\"version\" : 1", with: "\"version\" : 2").utf8)
                    .write(to: recipeFile)
            }),
            ("no recipe", { try FileManager.default.removeItem(at: recipeFile) }),
            ("no source", { try FileManager.default.removeItem(at: sourceFile) }),
            ("a changed source", { try Data("changed".utf8).write(to: sourceFile) }),
        ]
        for (what, spoil) in spoiled {
            try good.write(to: recipeFile)
            try goodSource.write(to: sourceFile)
            try spoil()
            let opened = try opened("Alarm 2")
            XCTAssertFalse(opened.hasEdits, what)
            XCTAssertTrue(opened.recipe.isOriginal, what)
        }
    }

    func testARecipeThatNamesASourceOutsideItsOwnFolderIsNotFollowed() throws {
        _ = try savedAlarm()
        let sidecar = self.sidecar("Alarm 2")
        let recipeFile = sidecar.appendingPathComponent("recipe.json")
        let name = try opened("Alarm").recipe.source.name
        try FileManager.default.copyItem(at: sidecar.appendingPathComponent(name), to: edits.appendingPathComponent("outside.wav"))
        let spoiled = String(decoding: try Data(contentsOf: recipeFile), as: UTF8.self)
            .replacingOccurrences(of: "\"\(name)\"", with: "\"../outside.wav\"")
        XCTAssertNotEqual(spoiled, String(decoding: try Data(contentsOf: recipeFile), as: UTF8.self))
        try Data(spoiled.utf8).write(to: recipeFile)
        XCTAssertFalse(try opened("Alarm 2").hasEdits)
    }

    // MARK: - What a refusal of giving a sound its name is called

    func testEveryRefusalOfGivingASoundItsNameIsAFailureOfSavingWithWordsOfItsOwn() {
        let refusals: [SoundImport.Refusal] = [
            .notAFile, .unsupportedType("txt"), .badName, .tooLarge, .unreadable("it is damaged"), .silent, .tooLong,
            .systemSound("Glass"), .alreadyExists("Alarm"), .cannotSetAside("Alarm"), .couldNotCopy("the disk is full"),
        ]
        // A switch with no default: a refusal that is given a case is a build that fails until it is mapped here.
        for refusal in refusals {
            switch refusal {
            case .notAFile, .unsupportedType, .badName, .tooLarge, .unreadable, .silent, .tooLong, .systemSound, .alreadyExists,
                 .cannotSetAside, .couldNotCopy:
                break
            }
        }
        XCTAssertEqual(SoundSaveFailure(.badName), .badName)
        XCTAssertEqual(SoundSaveFailure(.silent), .silent)
        XCTAssertEqual(SoundSaveFailure(.tooLong), .tooLong)
        XCTAssertEqual(SoundSaveFailure(.tooLarge), .tooLong, "more audio than a sound may hold is a sound that is too long")
        XCTAssertEqual(SoundSaveFailure(.systemSound("Glass")), .systemSound("Glass"))
        XCTAssertEqual(SoundSaveFailure(.alreadyExists("Alarm")), .alreadyExists("Alarm"))
        XCTAssertEqual(SoundSaveFailure(.cannotSetAside("Alarm")), .cannotSetAside("Alarm"))
        XCTAssertEqual(SoundSaveFailure(.unreadable("it is damaged")), .unreadable("it is damaged"))
        XCTAssertEqual(SoundSaveFailure(.couldNotCopy("the disk is full")), .couldNotWrite("the disk is full"))
        XCTAssertEqual(SoundSaveFailure(.notAFile), .couldNotWrite(nil))
        XCTAssertEqual(SoundSaveFailure(.unsupportedType("txt")), .couldNotWrite(nil))
        for refusal in refusals {
            let words = SoundEditorText.saveFailure(SoundSaveFailure(refusal))
            XCTAssertFalse(words.contains("could not be added"), "\(refusal): \(words)")
            XCTAssertNotEqual(words, refusal.description)
        }
    }

    // MARK: - The sweep of sidecars whose sound is gone

    /// A sidecar for `name`, as a save made it, with every date in it `age` seconds ago.
    @discardableResult
    private func sidecarOf(_ name: String, age: TimeInterval) throws -> URL {
        let folder = sidecar(name)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: folder.appendingPathComponent("recipe.json"))
        try Data("source".utf8).write(to: folder.appendingPathComponent("source-1.wav"))
        let then = Date().addingTimeInterval(-age)
        for url in [folder.appendingPathComponent("recipe.json"), folder.appendingPathComponent("source-1.wav"), folder] {
            try FileManager.default.setAttributes([.modificationDate: then], ofItemAtPath: url.path)
        }
        return folder
    }

    func testASidecarWhoseSoundIsGoneIsRemovedOnceItIsOldAndNotBefore() throws {
        let young = try sidecarOf("Young", age: 10)
        let old = try sidecarOf("Gone", age: SoundInstall.staleAfter + 60)
        SoundEditStore.removeOrphanedSidecars(library: library)
        XCTAssertTrue(FileManager.default.fileExists(atPath: young.path), "it may be one that a save is making")
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
        SoundEditStore.removeOrphanedSidecars(library: library, now: Date().addingTimeInterval(SoundInstall.staleAfter + 60))
        XCTAssertFalse(FileManager.default.fileExists(atPath: edits.path), "or the folder of them, once there is none: not left empty")
    }

    func testASidecarWhoseSoundIsThereIsNeverRemovedHoweverOld() throws {
        try tone("custom/Alarm.wav")
        try tone("custom/bell.caf")
        let alarm = try sidecarOf("Alarm", age: SoundInstall.staleAfter * 1_000)
        let bell = try sidecarOf("Bell", age: SoundInstall.staleAfter * 1_000)
        SoundEditStore.removeOrphanedSidecars(library: library, now: Date().addingTimeInterval(SoundInstall.staleAfter * 10_000))
        XCTAssertTrue(FileManager.default.fileExists(atPath: alarm.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: bell.path), "whatever its case and its type")
    }

    func testASidecarIsOldOnlyWhenEverythingInItIs() throws {
        let folder = try sidecarOf("Gone", age: SoundInstall.staleAfter * 10)
        try FileManager.default.setAttributes([.modificationDate: Date()],
                                              ofItemAtPath: folder.appendingPathComponent("recipe.json").path)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-SoundInstall.staleAfter * 10)],
                                              ofItemAtPath: folder.path)
        SoundEditStore.removeOrphanedSidecars(library: library)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path), "a recipe just written is a save just made")
    }

    func testTheSweepLeavesWhatIsNotASidecarAlone() throws {
        try FileManager.default.createDirectory(at: edits.appendingPathComponent("Other"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: edits.appendingPathComponent("note.edit"))
        try Data("x".utf8).write(to: edits.appendingPathComponent(".edit"))
        let ancient = Date().addingTimeInterval(-SoundInstall.staleAfter * 1_000)
        for entry in listing(edits) {
            try FileManager.default.setAttributes([.modificationDate: ancient], ofItemAtPath: edits.appendingPathComponent(entry).path)
        }
        SoundEditStore.removeOrphanedSidecars(library: library)
        XCTAssertEqual(listing(edits), [".edit", "Other", "note.edit"])
    }

    func testTheSweepDoesNothingWhenThereAreNoEditsOrNoSoundsFolder() throws {
        SoundEditStore.removeOrphanedSidecars(library: library)
        XCTAssertEqual(listing(), [])
        try FileManager.default.removeItem(at: custom)
        SoundEditStore.removeOrphanedSidecars(library: library)
        XCTAssertFalse(FileManager.default.fileExists(atPath: custom.path))
    }

    func testTheSweepDoesNotTakeASoundForGoneWhileItIsBeingReplacedByAnother() throws {
        try tone("custom/Alarm.caf")
        let edits = try sidecarOf("Alarm", age: SoundInstall.staleAfter + 60)
        let staged = try tone("custom/\(SoundInstall.renderingPrefix)\(UUID().uuidString).wav")
        let held = HeldRename()
        var holding = SoundInstall(library: library)
        holding.move = held.move
        let installing = holding
        let result = Slot<Result<String, SoundImport.Refusal>>()
        let installed = DispatchGroup()
        DispatchQueue.global().async(group: installed) { result.value = installing.install(staged, as: "Alarm", replacing: true) }
        XCTAssertTrue(held.waitUntilHeld(), "the rename was never reached")

        // Alarm.caf is set aside and Alarm.wav is not yet there: no file of the name, for a moment.
        let sounds = library
        let swept = DispatchGroup()
        DispatchQueue.global().async(group: swept) { SoundEditStore.removeOrphanedSidecars(library: sounds) }
        let sweepFinishedWhileHeld = swept.wait(timeout: .now() + 0.5) == .success
        held.letGo()
        installed.wait()
        swept.wait()

        XCTAssertFalse(sweepFinishedWhileHeld, "the sweep waits for the sound to have its name")
        XCTAssertEqual(result.value, .success("Alarm"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: edits.path), "the edits of a sound being replaced are not those of one that is gone")
    }

    func testAddingASoundSweepsOldSidecarsWhoseSoundIsGone() throws {
        let old = try sidecarOf("Gone", age: SoundInstall.staleAfter + 60)
        let young = try sidecarOf("Young", age: 10)
        let chosen = try tone("Chosen.wav")
        XCTAssertEqual(SoundImport(library: library).add(chosen), .success("Chosen"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: young.path))
    }

    func testSavingSweepsOldSidecarsAndStagedLeavingsAsAddingDoes() throws {
        let old = try sidecarOf("Gone", age: SoundInstall.staleAfter + 60)
        let young = try sidecarOf("Young", age: 10)
        let leaving = custom.appendingPathComponent("\(SoundInstall.recipePrefix)\(UUID().uuidString).json")
        try Data("{}".utf8).write(to: leaving)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-SoundInstall.staleAfter - 60)],
                                              ofItemAtPath: leaving.path)
        try tone("custom/Alarm.wav")
        let source = try opened("Alarm")
        XCTAssertEqual(saved(try louder(source), of: source, as: "Alarm 2"), .success(.saved("Alarm 2")))
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: young.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: leaving.path))
    }
}
