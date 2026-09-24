import XCTest
@testable import AlertAudio

final class SoundLibraryTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("SoundLibraryTests-\(UUID().uuidString)")
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

    func testNamesAreFileNamesWithoutExtensions() {
        touch("system/Glass.aiff")
        touch("system/Hero.aiff")
        XCTAssertEqual(library.availableNames, ["Glass", "Hero"])
    }

    func testLookupIgnoresCase() {
        touch("system/Glass.aiff")
        XCTAssertEqual(library.url(for: "glass")?.lastPathComponent, "Glass.aiff")
        XCTAssertEqual(library.url(for: "GLASS")?.lastPathComponent, "Glass.aiff")
    }

    func testTheUsersSoundOverridesASystemSoundOfTheSameName() {
        touch("system/Glass.aiff")
        touch("custom/Glass.wav")
        // Resolved on both sides: the temporary folder is reached through the
        // /var → /private/var symlink, and the listing returns the real path.
        XCTAssertEqual(library.url(for: "Glass")?.resolvingSymlinksInPath().path,
                       root.appendingPathComponent("custom/Glass.wav").resolvingSymlinksInPath().path)
        XCTAssertEqual(library.availableNames, ["Glass"], "one name, not two")
    }

    func testFilesThatAreNotAudioAreIgnored() {
        touch("custom/notes.txt")
        touch("custom/Alarm.m4a")
        XCTAssertEqual(library.availableNames, ["Alarm"])
    }

    func testAMissingCustomFolderIsNotAnError() {
        touch("system/Glass.aiff")
        let library = SoundLibrary(systemDirectory: root.appendingPathComponent("system"),
                                   customDirectory: root.appendingPathComponent("does-not-exist"))
        XCTAssertEqual(library.availableNames, ["Glass"])
    }

    func testASoundAddedWhileRunningIsFoundWithoutRestarting() {
        let library = self.library
        XCTAssertNil(library.url(for: "Late"))
        touch("custom/Late.aiff")
        XCTAssertNotNil(library.url(for: "Late"), "a stale list would reject a rule naming a sound the user just added")
    }

    func testTheRealSystemSoundsAreFound() {
        // The fourteen system sounds this app can use until a sound set is
        // chosen (§15). If macOS renames or removes them, this says so.
        let names = SoundLibrary(customDirectory: root.appendingPathComponent("none")).availableNames
        for expected in ["Basso", "Glass", "Hero", "Ping", "Sosumi", "Submarine"] {
            XCTAssertTrue(names.contains(expected), "\(expected) missing from /System/Library/Sounds")
        }
    }
}
