import XCTest
@testable import AlertAudio

/// The names of the two folders told apart, which the sound editor needs to say what saving would do: a name macOS has is
/// never saved over, and a name the user has is asked about (sound editor plan, Ruling 9).
final class SoundLibraryNamesTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("SoundLibraryNamesTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("system"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("custom"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func touch(_ path: String) {
        FileManager.default.createFile(atPath: root.appendingPathComponent(path).path, contents: Data())
    }

    private var library: SoundLibrary {
        SoundLibrary(systemDirectory: root.appendingPathComponent("system"),
                     customDirectory: root.appendingPathComponent("custom"))
    }

    func testEachFolderListsItsOwnNamesAndNotTheOthers() {
        touch("system/Glass.aiff")
        touch("system/Ping.aiff")
        touch("custom/Alarm.wav")
        XCTAssertEqual(library.systemSoundNames, ["Glass", "Ping"])
        XCTAssertEqual(library.customSoundNames, ["Alarm"])
    }

    func testASoundOfTheUsersWithAMacOSNameIsInBothSoThatItIsNeverSavedOver() {
        touch("system/Glass.aiff")
        touch("custom/Glass.wav")
        XCTAssertEqual(library.systemSoundNames, ["Glass"])
        XCTAssertEqual(library.customSoundNames, ["Glass"])
    }

    func testHiddenFilesFoldersAndFilesThatAreNotAudioAreNotSounds() throws {
        touch("custom/.adding-1.wav")
        touch("custom/notes.txt")
        touch("custom/Alarm.m4a")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("custom/Folder.wav"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("custom/.edits"), withIntermediateDirectories: true)
        XCTAssertEqual(library.customSoundNames, ["Alarm"])
    }

    func testAMissingFolderHasNoNamesAndIsNotAnError() {
        let library = SoundLibrary(systemDirectory: root.appendingPathComponent("none"),
                                   customDirectory: root.appendingPathComponent("also-none"))
        XCTAssertEqual(library.systemSoundNames, [])
        XCTAssertEqual(library.customSoundNames, [])
    }

    func testTheNamesAreReadFreshEachTime() {
        let library = self.library
        XCTAssertEqual(library.customSoundNames, [])
        touch("custom/Late.aiff")
        XCTAssertEqual(library.customSoundNames, ["Late"])
    }
}
