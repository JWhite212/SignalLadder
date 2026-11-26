import XCTest
@testable import NotificationCore

/// The app target has no tests, so what the sound row's Add Sound button does
/// is read from its source: that a file chosen or dropped goes through the one
/// import, that nothing is replaced unasked, and that the editor lists the
/// sounds again afterwards.
final class AddSoundWiringTests: XCTestCase {
    func testTheButtonAndADropAddThroughTheSameFunction() throws {
        let view = try code("AlertEditorView.swift")
        XCTAssertEqual(count("Button(model.isAddingSound ? EditorText.addingSound : EditorText.addSound) { chooseSound() }", in: view), 1)
        XCTAssertEqual(count(".disabled(model.isAddingSound)", in: view), 1, "a second is not begun while one is being read")
        XCTAssertTrue(try body(of: "private func chooseSound() {", in: view).contains("addSound(file)"))
        XCTAssertEqual(count(".dropDestination(for: URL.self) { files, _ in", in: view), 1)
        XCTAssertEqual(count("addSound(file)", in: view), 2, "the chooser and the drop")
        XCTAssertEqual(count("guard let file = files.first, !model.isAddingSound else { return false }", in: view), 1,
                       "any file is taken, so one that cannot be a sound is told why, and none while one is being added")
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
        let add = try body(of: "private func addSound(_ file: URL, replacing: Bool = false) {", in: view)
        XCTAssertLessThan(try position(of: "case .failure(.alreadyExists(let existing)):", in: add),
                          try position(of: "soundToReplace = SoundToReplace(name: existing, file: file)", in: add))
        XCTAssertLessThan(try position(of: "soundToReplace = SoundToReplace(name: existing, file: file)", in: add),
                          try position(of: "case .failure(let refusal):", in: add), "asked, not shown as a failure")
        XCTAssertEqual(count("replacing: true", in: view), 1)
        XCTAssertTrue(try body(of: "Button(EditorText.replaceSound, role: .destructive) {", in: view).contains("replacing: true"))
    }

    func testAnAddedSoundIsChosenAndARefusalIsShownWhereAFailedTestIs() throws {
        let add = try body(of: "private func addSound(_ file: URL, replacing: Bool = false) {",
                           in: try code("AlertEditorView.swift"))
        XCTAssertLessThan(try position(of: "case .success(let added):", in: add),
                          try position(of: "soundName.wrappedValue = added", in: add))
        XCTAssertLessThan(try position(of: "case .failure(let refusal):", in: add),
                          try position(of: "testMessage = refusal.description", in: add))
    }

    func testTheSlowHalfOfAnAddIsOffTheMainActorAndTheNamingIsOnIt() throws {
        let model = try code("RuleEditorModel.swift")
        let add = try body(of: "func addSound(from file: URL, replacing: Bool = false) async -> Result<String, SoundImport.Refusal> {",
                           in: model)
        let detached = try position(of: "await Task.detached(priority: .userInitiated) {", in: add)
        let stage = try position(of: "SoundImport(library: library).stage(file, replacing: replacing)", in: add)
        let ended = try position(of: "}.value", in: add)
        let install = try position(of: "SoundImport(library: library).install(staging, replacing: replacing)", in: add)
        XCTAssertLessThan(detached, stage)
        XCTAssertLessThan(stage, ended, "the reading, copying and decoding are inside the detached task")
        XCTAssertLessThan(ended, install, "and the renames are after it, where the rules are loaded")
        XCTAssertEqual(count(".add(file", in: add), 0, "never the whole add in one call here: that would decode where alerts are set off")
        XCTAssertLessThan(try position(of: "isAddingSound = true", in: add), detached)
        XCTAssertTrue(add.contains("defer { isAddingSound = false }"))
    }

    func testAReplacedSoundIsDecodedAgainAtOnceAndAnAddedOneLeavesThePlayerAlone() throws {
        let add = try body(of: "func addSound(from file: URL, replacing: Bool = false) async -> Result<String, SoundImport.Refusal> {",
                           in: try code("RuleEditorModel.swift"))
        XCTAssertEqual(count("onSoundAdded?(replacing)", in: add), 1)
        XCTAssertEqual(count("forgetPreparedSounds", in: add), 0, "a new sound is not one the player holds")
        XCTAssertLessThan(try position(of: "onSoundAdded?(replacing)", in: add), try position(of: "refreshSounds()", in: add))
        let delegate = try code("AppDelegate.swift")
        let told = try body(of: "model.onSoundAdded = { [weak self] replaced in", in: delegate)
        XCTAssertLessThan(try position(of: "if replaced { ruleStore.player.forgetPreparedSounds() }", in: told),
                          try position(of: "recheckRuleWarnings()", in: told),
                          "forgotten only when one was replaced, then the warnings again either way, now and not at the next alert")
    }

    func testTheFolderButtonAsksTheModelWhichMakesTheFolderBeforeOpeningIt() throws {
        let view = try code("AlertEditorView.swift")
        XCTAssertEqual(count("Button(EditorText.showSoundsFolder) { testMessage = model.showSoundsFolder() }", in: view), 1)
        let show = try body(of: "func showSoundsFolder() -> String? {", in: try code("RuleEditorModel.swift"))
        XCTAssertTrue(show.contains("NSWorkspace.shared.open(try SoundImport(library: store.sounds).makeFolder())"))
        XCTAssertTrue(show.contains("return EditorText.soundsFolderNotOpened(error.localizedDescription)"))
    }

    func testEveryLoadOfTheRulesFirstPutsBackASoundAStoppedReplaceLeftSetAside() throws {
        let reload = try body(of: "func reload() {", in: try code("RuleStore.swift"))
        XCTAssertLessThan(try position(of: "SoundImport(library: sounds).recoverSetAsideSounds()", in: reload),
                          try position(of: "player.forgetPreparedSounds()", in: reload))
        XCTAssertLessThan(try position(of: "SoundImport(library: sounds).recoverSetAsideSounds()", in: reload),
                          try position(of: "let check = soundCheck", in: reload), "before the sounds are listed for the rules")
    }

    func testTheWordsAreTheEditorsOwn() {
        XCTAssertEqual(EditorText.addSound, "Add Sound…")
        XCTAssertEqual(EditorText.addingSound, "Adding…")
        XCTAssertEqual(EditorText.showSoundsFolder, "Show Sounds Folder")
        XCTAssertEqual(EditorText.replaceSoundQuestion("Alarm"), "Replace your sound “Alarm”?")
    }
}
