import AVFoundation
import XCTest
@testable import AlertAudio
import NotificationCore

/// The name of a sound that is saved is held to what a file's name can be in bytes as well as in
/// characters, as the editor's window holds it (`SoundSaveNaming`). A name of few characters can be
/// many bytes, and a sound set aside while it is replaced is hidden under a name that holds its own,
/// so a saved name past the limit could be saved and then never replaced. An added sound's name is
/// the file's own, which `SoundImportTests` holds as it was.
final class SoundInstallNameBytesTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("SoundInstallNameBytesTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("system"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("custom"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private var custom: URL { root.appendingPathComponent("custom") }

    private var installer: SoundInstall {
        SoundInstall(library: SoundLibrary(systemDirectory: root.appendingPathComponent("system"), customDirectory: custom))
    }

    private func staged(_ prefix: String) throws -> URL {
        try TestAudio.write(custom.appendingPathComponent("\(prefix)\(UUID().uuidString).wav"), seconds: 0.1)
    }

    func testTheLimitInBytesIsTheOneTheWindowApplies() {
        XCTAssertEqual(SoundInstall.longestNameBytes, SoundSaveNaming.longestNameBytes)
    }

    func testANameOfFewCharactersAndTooManyBytesIsNotOneToSaveUnder() {
        XCTAssertTrue(SoundInstall.isSafeToSave(name: String(repeating: "é", count: SoundSaveNaming.longestNameBytes / 2)))
        XCTAssertFalse(SoundInstall.isSafeToSave(name: String(repeating: "é", count: SoundSaveNaming.longestNameBytes / 2 + 1)))
        XCTAssertTrue(SoundInstall.isSafeToSave(name: String(repeating: "✓", count: SoundSaveNaming.longestNameBytes / 3)))
        XCTAssertFalse(SoundInstall.isSafeToSave(name: String(repeating: "✓", count: SoundSaveNaming.longestNameBytes / 3 + 1)))
    }

    func testTheWindowAndTheInstallAgreeOnEveryLengthOfANameOfThreeByteLetters() {
        for count in 1...SoundInstall.maximumNameLength {
            let name = String(repeating: "✓", count: count)
            let windowPasses: Bool
            switch SoundSaveNaming.verdict(for: name, ownSounds: [], macOSSounds: []) {
            case .free, .yours: windowPasses = true
            case .refused: windowPasses = false
            }
            XCTAssertEqual(SoundInstall.isSafeToSave(name: name), windowPasses, "\(count) letters, \(name.utf8.count) bytes")
        }
    }

    func testASavedSoundIsNotGivenANameThatIsTooManyBytesAndTheStagedFileGoes() throws {
        let tooMany = String(repeating: "é", count: SoundSaveNaming.longestNameBytes / 2 + 1)
        XCTAssertEqual(installer.install(try staged(SoundInstall.renderingPrefix), as: tooMany, replacing: false), .failure(.badName))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: custom.path), [])

        let longest = String(repeating: "é", count: SoundSaveNaming.longestNameBytes / 2)
        XCTAssertEqual(installer.install(try staged(SoundInstall.renderingPrefix), as: longest, replacing: false), .success(longest))
    }

    func testAnAddedSoundKeepsTheNameOfItsFileWhateverItsBytes() throws {
        let tooMany = String(repeating: "é", count: SoundSaveNaming.longestNameBytes / 2 + 1)
        XCTAssertEqual(installer.install(try staged(SoundInstall.addingPrefix), as: tooMany, replacing: false), .success(tooMany))
    }

    /// Three-byte letters, which the folder lists as they were written: a letter with an accent is listed
    /// in the decomposed form, a byte longer than the window counts it, and is not a name this holds.
    func testTheSoundThatHasTheLongestNameIsOneThatCanStillBeReplaced() throws {
        let longest = String(repeating: "✓", count: SoundSaveNaming.longestNameBytes / 3)
        XCTAssertEqual(installer.install(try staged(SoundInstall.renderingPrefix), as: longest, replacing: false), .success(longest))
        XCTAssertEqual(installer.install(try staged(SoundInstall.renderingPrefix), as: longest, replacing: true), .success(longest),
                       "the hidden name it is set aside under is a name a file may have")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: custom.path), ["\(longest).wav"])
    }
}
