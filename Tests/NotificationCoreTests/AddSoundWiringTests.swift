import XCTest
@testable import NotificationCore

/// The app target has no tests, so what the sound row's Add Sound button does
/// is read from its source: that a file chosen or dropped goes through the one
/// import, that nothing is replaced unasked, and that the editor lists the
/// sounds again afterwards.
final class AddSoundWiringTests: XCTestCase {
    func testTheButtonAndADropAddThroughTheSameFunction() throws {
        let view = try code("AlertEditorView.swift")
        XCTAssertEqual(count("Button(EditorText.addSound) { chooseSound() }", in: view), 1)
        XCTAssertTrue(try body(of: "private func chooseSound() {", in: view).contains("addSound(file)"))
        XCTAssertEqual(count(".dropDestination(for: URL.self) { files, _ in", in: view), 1)
        XCTAssertEqual(count("addSound(file)", in: view), 2, "the chooser and the drop")
        XCTAssertEqual(count("return addSound(file)", in: view), 1, "a drop that is refused is not taken")
        XCTAssertEqual(count("model.addSound(from:", in: view), 1, "one way in")
    }

    func testTheChooserOffersOneFileOfTheTypesASoundMayBe() throws {
        let chooser = try body(of: "private func chooseSound() {", in: try code("AlertEditorView.swift"))
        XCTAssertTrue(chooser.contains("panel.allowedContentTypes = SoundImport.fileExtensions.compactMap"))
        XCTAssertTrue(chooser.contains("panel.allowsMultipleSelection = false"))
        XCTAssertTrue(chooser.contains("panel.canChooseDirectories = false"))
    }

    func testASoundTheUserHasIsAskedAboutAndOnlyAYesReplacesIt() throws {
        let view = try code("AlertEditorView.swift")
        let add = try body(of: "private func addSound(_ file: URL, replacing: Bool = false) -> Bool {", in: view)
        XCTAssertLessThan(try position(of: "case .failure(.alreadyExists(let existing)):", in: add),
                          try position(of: "soundToReplace = SoundToReplace(name: existing, file: file)", in: add))
        XCTAssertLessThan(try position(of: "soundToReplace = SoundToReplace(name: existing, file: file)", in: add),
                          try position(of: "case .failure(let refusal):", in: add), "asked, not shown as a failure")
        XCTAssertEqual(count("replacing: true", in: view), 1)
        XCTAssertTrue(try body(of: "Button(EditorText.replaceSound, role: .destructive) {", in: view).contains("replacing: true"))
    }

    func testAnAddedSoundIsChosenAndARefusalIsShownWhereAFailedTestIs() throws {
        let add = try body(of: "private func addSound(_ file: URL, replacing: Bool = false) -> Bool {",
                           in: try code("AlertEditorView.swift"))
        XCTAssertLessThan(try position(of: "case .success(let added):", in: add),
                          try position(of: "soundName.wrappedValue = added", in: add))
        XCTAssertLessThan(try position(of: "case .failure(let refusal):", in: add),
                          try position(of: "testMessage = refusal.description", in: add))
    }

    func testTheModelListsTheSoundsAgainAndForgetsWhatThePlayerRead() throws {
        let model = try code("RuleEditorModel.swift")
        let add = try body(of: "func addSound(from file: URL, replacing: Bool = false) -> Result<String, SoundImport.Refusal> {",
                           in: model)
        XCTAssertTrue(add.contains("SoundImport(library: store.sounds).add(file, replacing: replacing)"))
        XCTAssertLessThan(try position(of: "store.player.forgetPreparedSounds()", in: add),
                          try position(of: "refreshSounds()", in: add))
        XCTAssertTrue(add.contains("objectWillChange.send()"))
    }

    func testTheFolderButtonAsksTheModelWhichMakesTheFolderBeforeOpeningIt() throws {
        let view = try code("AlertEditorView.swift")
        XCTAssertEqual(count("Button(EditorText.showSoundsFolder) { testMessage = model.showSoundsFolder() }", in: view), 1)
        let show = try body(of: "func showSoundsFolder() -> String? {", in: try code("RuleEditorModel.swift"))
        XCTAssertTrue(show.contains("NSWorkspace.shared.open(try SoundImport(library: store.sounds).makeFolder())"))
        XCTAssertTrue(show.contains("return EditorText.soundsFolderNotOpened(error.localizedDescription)"))
    }

    func testTheWordsAreTheEditorsOwn() {
        XCTAssertEqual(EditorText.addSound, "Add Sound…")
        XCTAssertEqual(EditorText.showSoundsFolder, "Show Sounds Folder")
        XCTAssertEqual(EditorText.replaceSoundQuestion("Alarm"), "Replace your sound “Alarm”?")
    }
}
