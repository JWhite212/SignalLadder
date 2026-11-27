import XCTest
@testable import NotificationCore

/// What has to hold of the files that open and save a sound, read as text, since the lines that carry a
/// decision to the disk are what a test of behaviour cannot tell are the only ones: that the player and
/// the editor decode alike, that a saved sound gets its name from the one step that can lose a sound and
/// from nowhere else, and that the work of opening and saving belongs to no actor (sound editor plan,
/// Task 5). The behaviour is held by `SoundEditStoreTests` and `SoundDecodingTests`, against real folders.
final class SoundEditStoreWiringTests: XCTestCase {
    func testThePlayerReadsEverySoundThroughTheDecodingTheEditorUses() throws {
        let player = try packageCode("Sources/AlertAudio/AlertPlayer.swift")
        let load = try body(of: "private func load(_ url: URL, as name: String) throws -> (buffer: AVAudioPCMBuffer, peak: Float) {",
                            in: player)
        XCTAssertTrue(load.contains("try SoundDecoding.decode(url, maximumSeconds: Self.maximumSeconds)"))
        XCTAssertEqual(count("AVAudioFile(forReading", in: player), 0, "the player opens no file of its own")
        XCTAssertEqual(count("AVAudioConverter(", in: player), 0, "and converts nothing of its own")
        XCTAssertTrue(player.contains("static let format = SoundDecoding.format"), "its graph is connected to the format the editor edits in")

        let editor = try packageCode("Sources/AlertAudio/SoundEditStore.swift")
        XCTAssertEqual(count("try SoundDecoding.samples(of:", in: editor), 1)
        XCTAssertEqual(count("AVAudioFile(forReading", in: editor), 0)
    }

    func testTheWordsOfThePlayersFailuresAreMadeFromTheDecodingsFailuresAndNotChanged() throws {
        let player = try packageCode("Sources/AlertAudio/AlertPlayer.swift")
        let load = try body(of: "private func load(_ url: URL, as name: String) throws -> (buffer: AVAudioPCMBuffer, peak: Float) {",
                            in: player)
        XCTAssertTrue(load.contains("catch SoundDecoding.Failure.tooLong {"))
        XCTAssertTrue(load.contains("throw Failure.tooLong(name)"))
        XCTAssertTrue(load.contains("catch SoundDecoding.Failure.unreadable(let reason) {"))
        XCTAssertTrue(load.contains("throw Failure.unreadable(sound: name, reason: reason)"))
    }

    func testASavedSoundIsGivenItsNameBySoundInstallAndByNothingElseInTheStore() throws {
        let store = try packageCode("Sources/AlertAudio/SoundEditStore.swift")
        XCTAssertEqual(count("installer.install(stagedSound, as: name, replacing: replacing)", in: store), 1)
        XCTAssertEqual(count("installer.move = move", in: store), 1, "the seam a test makes fail is the one the rename goes through")
        XCTAssertEqual(count(".moveItem(", in: store), 1, "only the seam's own default: no sound is set aside, named or put back here")
        XCTAssertEqual(count("try move(staged, target)", in: store), 1, "and the recipe goes in through the seam too")
        XCTAssertEqual(count("recoverSetAsideSounds()", in: store), 1)
    }

    func testWhatIsWrittenIsCheckedAsAnAddedSoundIsBeforeItHasANameAndTheRecipeComesLast() throws {
        let store = try packageCode("Sources/AlertAudio/SoundEditStore.swift")
        let save = try body(of: "public func save(_ recipe: SoundRecipe, of opened: Opened, as name: String, replacing: Bool) -> Result<Saved, SoundSaveFailure> {",
                            in: store)
        let steps = ["try Self.write(rendered, to: stagedSound)", "try SoundImport.check(stagedSound)",
                     "installer.install(stagedSound, as: name, replacing: replacing)", "guard keepRecipe(stagedRecipe, in: sidecar, source: recipe.source.name)"]
        var last = save.startIndex
        for step in steps {
            let at = try position(of: step, in: save)
            XCTAssertGreaterThan(at, last, "\(step) is out of order")
            last = at
        }
        XCTAssertTrue(save.contains("SoundInstall.renderingPrefix"), "staged under the names the sweep knows")
        XCTAssertTrue(save.contains("SoundInstall.recipePrefix"))
    }

    func testTheStoreAndTheDecodingBelongToNoActorSoTheEditorCanCallThemFromATaskOfItsOwn() throws {
        for file in ["SoundEditStore", "SoundDecoding"] {
            let code = try packageCode("Sources/AlertAudio/\(file).swift")
            XCTAssertFalse(code.contains("@MainActor"), file)
            XCTAssertFalse(code.contains("MainActor.run"), file)
        }
    }

    func testTheSweepOfSidecarsIsMadeWhereTheStagedLeavingsAreSweptWhenASoundIsAddedAndWhenOneIsSaved() throws {
        let call = "SoundEditStore.removeOrphanedSidecars(library: library)"
        let importer = try packageCode("Sources/AlertAudio/SoundImport.swift")
        XCTAssertEqual(count(call, in: importer), 1)
        XCTAssertLessThan(try position(of: "Self.removeStaleStagedCopies(in: folder)", in: importer),
                          try position(of: call, in: importer), "beside it")
        let store = try packageCode("Sources/AlertAudio/SoundEditStore.swift")
        XCTAssertEqual(count("Self.removeOrphanedSidecars(library: library)", in: store), 1)
        XCTAssertEqual(count("SoundInstall.removeStaleStagedCopies(in: folder)", in: store), 1)
    }

    func testNoWordTheWindowShowsIsWrittenInTheStore() throws {
        let store = try packageCode("Sources/AlertAudio/SoundEditStore.swift")
        for words in ["could not be added", "The sound could not", "Add Sound"] {
            XCTAssertFalse(store.contains(words), words)
        }
    }
}
