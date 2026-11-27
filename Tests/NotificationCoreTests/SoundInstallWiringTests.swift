import XCTest
@testable import NotificationCore

/// `SoundImport` is read as text, since what has to hold of it is where the
/// step that can lose a sound lives: in `SoundInstall`, once, so that adding a
/// sound and saving an edited one cannot differ in how they set a sound aside
/// or put it back.
final class SoundInstallWiringTests: XCTestCase {
    func testSoundImportInstallsThroughSoundInstallAndHasNoRenamingOfItsOwn() throws {
        let importer = try packageCode("Sources/AlertAudio/SoundImport.swift")
        let install = try body(of: "public func install(_ staging: Staging, replacing: Bool = false) -> Result<String, Refusal> {",
                               in: importer)
        XCTAssertTrue(install.contains("var installer = SoundInstall(library: library)"))
        XCTAssertTrue(install.contains("installer.move = move"), "its move seam is the one the rename is made through")
        XCTAssertTrue(install.contains("return installer.install(staged.file, as: staged.name, replacing: replacing)"))
        XCTAssertEqual(count(".moveItem(", in: importer), 1, "only the seam's default: no sound is set aside, named or put back here")
        XCTAssertEqual(count("contentsOfDirectory(", in: importer), 0, "and no look at the folder for one left set aside")

        let recover = try body(of: "public func recoverSetAsideSounds() -> [String] {", in: importer)
        XCTAssertEqual(trimmed(recover), "SoundInstall(library: library).recoverSetAsideSounds()")
    }

    func testTheOneInstallIsWhereASoundIsSetAsideAndPutBack() throws {
        let installer = try packageCode("Sources/AlertAudio/SoundInstall.swift")
        XCTAssertEqual(count("asideName(for: old.lastPathComponent", in: installer), 2, "asked of every sound, then set aside")
        XCTAssertEqual(count("public func recoverSetAsideSounds() -> [String] {", in: installer), 1)
    }
}
