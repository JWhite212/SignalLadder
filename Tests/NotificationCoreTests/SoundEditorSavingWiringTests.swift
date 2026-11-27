import XCTest
@testable import NotificationCore

/// What has to hold of the files that let a sound be edited from a rule and saved, read as text, since the app target has
/// no tests and a line that replaces a sound unasked, saves on the main actor or forgets to tell the player builds cleanly
/// (sound editor plan, Task 9). The decisions are the core's and are tested there (`SoundSaveControlsTests`,
/// `SoundEditHistoryTests`, `EditSoundTests`, `SoundUseDraftTests`, `SoundSavingTextTests`); these hold that the files hand
/// on to them as they should. They start nothing and show no window.
final class SoundEditorSavingWiringTests: XCTestCase {
    private func model() throws -> String { try code("SoundEditorModel.swift") }
    private func view() throws -> String { try code("SoundEditorView.swift") }
    private func controller() throws -> String { try code("SoundEditorWindowController.swift") }
    private func alertView() throws -> String { try code("AlertEditorView.swift") }
    private func ruleModel() throws -> String { try code("RuleEditorModel.swift") }
    private func delegate() throws -> String { try code("AppDelegate.swift") }

    // MARK: - The way in

    func testEditSoundIsBesideAddSoundAndIsOffWhenTheSoundIsNotFound() throws {
        let view = try alertView()
        let add = try position(of: "Button(model.isAddingSound ? EditorText.addingSound : EditorText.addSound) { chooseSound() }", in: view)
        let edit = try position(of: "Button(EditorText.editSound) { editSound(name) }", in: view)
        let off = try position(of: ".disabled(!AlertEditing.canEditSound(named: name, among: model.availableSounds))", in: view)
        let folder = try position(of: "Button(EditorText.showSoundsFolder)", in: view)
        XCTAssertLessThan(add, edit, "beside the button that adds one")
        XCTAssertLessThan(edit, off, "off when the sound is not found, which the core decides")
        XCTAssertLessThan(off, folder, "in the same row")
        XCTAssertEqual(count("Button(EditorText.editSound)", in: view), 1)
        XCTAssertEqual(count("AlertEditing.canEditSound(", in: view), 1)
    }

    func testTheAlertNamesTheNewSoundOnlyWhileItStillNamesTheOneItWasOpenedFromAndAsAChangeToTheDraft() throws {
        let edit = try body(of: "private func editSound(_ name: String) {", in: try alertView())
        XCTAssertTrue(edit.contains("model.editSound(name, gainDB: soundGain.wrappedValue) { saved in"),
                      "opened with the alert's own gain")
        XCTAssertTrue(edit.contains("action = AlertEditing.naming(saved: saved, in: action, replacing: named)"),
                      "set through the alert's binding, which is the draft, and guarded by the core")
        XCTAssertTrue(edit.contains("named = saved"), "a second Save as New is made of the alert as the first left it")
        XCTAssertEqual(count("AlertEditing.naming(", in: try alertView()), 1)
        XCTAssertEqual(count("model.editSound(", in: try alertView()), 1, "one way in")
    }

    func testTheModelHandsTheSoundOnAndTheAppDelegateOwnsTheWindow() throws {
        let ruleModel = try ruleModel()
        XCTAssertEqual(count("var onEditSound: ((_ name: String, _ ruleGainDB: Double, _ saved: @escaping (String) -> Void) -> Void)?", in: ruleModel), 1)
        XCTAssertTrue(try body(of: "func editSound(_ name: String, gainDB: Double, saved: @escaping (String) -> Void) {", in: ruleModel)
            .contains("onEditSound?(name, gainDB, saved)"))
        let delegate = try delegate()
        XCTAssertEqual(count("private lazy var soundEditor = SoundEditorWindowController(", in: delegate), 1)
        XCTAssertTrue(delegate.contains("player: alertPlayer, library: sounds,"), "the one player and the one library")
        XCTAssertTrue(delegate.contains("self?.soundEditor.show(sound: name, ruleGainDB: gainDB, saved: saved)"))
    }

    // MARK: - Save as New, Save and what is asked

    func testTheNameIsTypedInAFieldAndReturnInItIsSaveAsNew() throws {
        let view = try view()
        XCTAssertEqual(count("TextField(SoundEditorText.nameLabel, text: Binding(get: { model.typedName }, set: { model.setTypedName($0) }))", in: view), 1)
        XCTAssertEqual(count(".onSubmit { actions.saveAsNew() }", in: view), 1)
        XCTAssertEqual(count("Button(model.isSaving ? SoundEditorText.saving : SoundEditorText.saveAsNew) { actions.saveAsNew() }", in: view), 1)
        XCTAssertTrue(try body(of: "func setTypedName(_ name: String) {", in: try model()).contains("typedName = name"))
    }

    func testSaveIsShownOnlyForASoundThatCanBeSavedOverAndEachButtonIsOnOnlyWhenTheCoreSaysSo() throws {
        let view = try view()
        let saving = try body(of: "private var saving: some View {", in: view)
        XCTAssertTrue(saving.contains("let save = model.saveControls"))
        XCTAssertTrue(saving.contains(".disabled(!save.canSaveAsNew)"))
        XCTAssertTrue(saving.contains("if save.offersSave {"))
        XCTAssertTrue(saving.contains("Button(SoundEditorText.save) { actions.save() }"))
        XCTAssertTrue(saving.contains(".disabled(!save.canSave)"))
        XCTAssertLessThan(try position(of: "if save.offersSave {", in: saving),
                          try position(of: "Button(SoundEditorText.save) { actions.save() }", in: saving),
                          "a macOS sound is never offered a Save, only a copy")
        XCTAssertEqual(count("var saveControls: SoundSaveControls {", in: try model()), 1)
    }

    func testTheVerdictOnTheNameAndTheMacOSNoteAreShownAsTheCoreWordsThem() throws {
        let saving = try body(of: "private var saving: some View {", in: try view())
        XCTAssertTrue(saving.contains("ForEach(save.notes, id: \\.self) { sentence in"))
        XCTAssertTrue(saving.contains("Text(sentence)"))
    }

    func testSaveOverAsksOnlyThroughTheCoresStepWithTheRulesThatNameTheSoundAndNothingIsReplacedBeforeTheAnswer() throws {
        let save = try body(of: "func save() {", in: try controller())
        XCTAssertTrue(save.contains("model.saveControls.saveStep(ruleCount: rulesNaming(model.displayName))"),
                      "how many rules play the sound being edited, asked when it is pressed")
        let step = try position(of: "switch step {", in: save)
        let saveNow = try position(of: "case .save(let request):", in: save)
        let ask = try position(of: "case .ask(let request, let confirmation):", in: save)
        XCTAssertLessThan(step, saveNow)
        XCTAssertLessThan(saveNow, ask)
        XCTAssertEqual(count("run(request)", in: save), 2, "at once, and after the answer")
        XCTAssertLessThan(try position(of: "ask(confirmation) {", in: save), try position(of: "self?.run(request)", in: save),
                          "the second is inside the answer")
        let asked = try body(of: "private func ask(_ confirmation: EditorText.Confirmation, then proceed: @escaping () -> Void) {",
                             in: try controller())
        XCTAssertTrue(asked.contains("alert.addButton(withTitle: title).hasDestructiveAction = confirmation.proceeds(atButton: index)"))
        XCTAssertTrue(asked.contains("if confirmation.proceeds(atButton: response.rawValue - first) { proceed() }"),
                      "only the button that goes ahead goes ahead; Cancel is first, so Return keeps the sound")
    }

    func testSaveAsNewIsMadeOnlyOfTheRequestTheCoreMakesAndNeverReplaces() throws {
        let controller = try controller()
        let saveAsNew = try body(of: "func saveAsNew(then done: @escaping (Bool) -> Void = { _ in }) {", in: controller)
        XCTAssertTrue(saveAsNew.contains("let request = model.saveControls.saveAsNewRequest"))
        XCTAssertEqual(count("replacing: true", in: controller), 0, "the controller makes no request of its own")
        XCTAssertEqual(count("replacing: false", in: controller), 0)
        XCTAssertEqual(count("SoundSaveRequest(", in: controller), 0)
        XCTAssertEqual(count("SoundSaveRequest(", in: try model()), 0)
        XCTAssertEqual(count("SoundSaveRequest(", in: try view()), 0)
    }

    func testTheModelBeginsOnlyARequestTheControlsWouldMakeNow() throws {
        let save = try body(of: "func save(_ request: SoundSaveRequest) async -> SaveOutcome {", in: try model())
        XCTAssertTrue(save.contains("guard let opened, let recipe = history?.present, saveControls.allows(request) else { return .notBegun }"))
        XCTAssertLessThan(try position(of: "saveControls.allows(request)", in: save), try position(of: "isSaving = true", in: save))
    }

    func testNothingIsSavedWhileACheckThatStopsASaveStandsOrARenderIsUnderWay() throws {
        let model = try model()
        let controls = try body(of: "var saveControls: SoundSaveControls {", in: model)
        XCTAssertTrue(controls.contains("isBlocked: findings.contains { $0.blocksSaving }"))
        XCTAssertTrue(controls.contains("isCatchingUp: isCatchingUp, isSaving: isSaving"))
        XCTAssertTrue(controls.contains("isReady: phase == .ready"))
        XCTAssertTrue(try body(of: "var controls: SoundEditorControls {", in: model).contains("isSaving: isSaving"),
                      "nothing is edited under a save that is writing the recipe as it was")
    }

    // MARK: - The save is the store's, off the main actor

    func testTheSaveIsMadeByTheStoreInADetachedTaskAndTheMainActorOnlyTakesTheResult() throws {
        let save = try body(of: "func save(_ request: SoundSaveRequest) async -> SaveOutcome {", in: try model())
        let detached = try position(of: "await Task.detached(priority: .userInitiated) {", in: save)
        let store = try position(of: "SoundEditStore(library: library).save(recipe, of: opened, as: request.name, replacing: request.replacing)", in: save)
        let ended = try position(of: "}.value", in: save)
        XCTAssertLessThan(detached, store)
        XCTAssertLessThan(store, ended, "rendering and writing are inside the detached task")
        XCTAssertLessThan(ended, try position(of: "switch made.result {", in: save))
        XCTAssertLessThan(try position(of: "isSaving = true", in: save), detached)
        XCTAssertTrue(save.contains("defer { isSaving = false }"))
        for work in ["SoundRender.render(", "SoundDecoding.", "AVAudio", "SoundInstall", "FileManager"] {
            XCTAssertEqual(count(work, in: try model()), 0, "\(work) is not the main actor's to do")
        }
        XCTAssertEqual(count(".save(", in: try model()), 1)
    }

    func testTheRecipeThatIsMarkedSavedIsTheOneThatWasWrittenAndNotTheOneThatIsPresentWhenTheSaveEnds() throws {
        let model = try model()
        let after = try body(of: "private func afterSave(_ saved: SoundEditStore.Saved, of recipe: SoundRecipe, own: Set<String>, macOS: Set<String>) {", in: model)
        XCTAssertTrue(after.contains("history?.markSaved(recipe)"))
        XCTAssertEqual(count("markSaved(", in: model), 1)
        XCTAssertTrue(try body(of: "func save(_ request: SoundSaveRequest) async -> SaveOutcome {", in: model)
            .contains("afterSave(saved, of: recipe, own: made.own, macOS: made.macOS)"), "the recipe the save was given")
    }

    func testASoundSavedWithoutItsEditsSaysTheyCannotBeReopenedAndASavedOneSaysItWasAndBothAreAnnounced() throws {
        let model = try model()
        let after = try body(of: "private func afterSave(_ saved: SoundEditStore.Saved, of recipe: SoundRecipe, own: Set<String>, macOS: Set<String>) {", in: model)
        XCTAssertTrue(after.contains("case .saved(let name): say(SoundEditorText.saved(name))"))
        XCTAssertTrue(after.contains("case .savedWithoutEdits: say(SoundEditorText.editsCannotBeReopened)"),
                      "said, since the sound is saved and plays, and `say` is the one place a sentence is shown and announced")
        XCTAssertEqual(count("AccessibilityNotification", in: model), 1)
    }

    func testAFailedSaveIsSaidInTheTextsWordsOverTheWindowAndLeavesTheEditsWhereTheyWere() throws {
        let controller = try controller()
        let show = try body(of: "private func showFailure(_ failure: SoundSaveFailure) {", in: controller)
        XCTAssertTrue(show.contains("alert.messageText = SoundEditorText.saveFailedTitle"))
        XCTAssertTrue(show.contains("alert.informativeText = SoundEditorText.saveFailedDetail(SoundEditorText.saveFailure(failure))"))
        let model = try model()
        XCTAssertTrue(try body(of: "func save(_ request: SoundSaveRequest) async -> SaveOutcome {", in: model)
            .contains("case .failure(let failure):\nreturn .refused(failure)"), "nothing of the window is changed by a failure")
        XCTAssertEqual(count("markSaved(", in: model), 1, "and only a save that succeeded says anything is saved")
    }

    // MARK: - After a save

    func testAfterASaveThePlayerForgetsAndTheEditorListsTheSoundsAgainAndOnlyAfterThatTheAlertNamesTheNewOne() throws {
        let save = try body(of: "func save(_ request: SoundSaveRequest) async -> SaveOutcome {", in: try model())
        let changed = try position(of: "onSoundsChanged(saved.name)", in: save)
        let named = try position(of: "if !request.replacing { onSaved(saved.name) }", in: save)
        XCTAssertLessThan(changed, named, "the picker has the sound before the alert is given its name")
        XCTAssertLessThan(try position(of: "case .success(let saved):", in: save), changed)
        XCTAssertLessThan(named, try position(of: "if !isClosed { afterSave(", in: save),
                          "told whatever the window has done since, so a window closed during the save loses no sound")

        let soundSaved = try body(of: "func soundSaved(_ name: String) {", in: try ruleModel())
        XCTAssertLessThan(try position(of: "onSoundAdded?(true)", in: soundSaved), try position(of: "refreshSounds()", in: soundSaved))
        XCTAssertTrue(soundSaved.contains("objectWillChange.send()"))

        let controller = try controller()
        XCTAssertTrue(controller.contains("onSaved: saved, onSoundsChanged: soundsChanged)"))
        let delegate = try delegate()
        XCTAssertTrue(delegate.contains("soundsChanged: { [weak self] name in self?.ruleEditor.model.soundSaved(name) })"))
        XCTAssertEqual(count("if replaced { ruleStore.player.forgetPreparedSounds() }", in: delegate), 1,
                       "the one place the player is told to forget what it decoded for a sound added or saved")
        XCTAssertEqual(count("forgetPreparedSounds", in: controller + (try model()) + (try view())), 0, "the window never calls the player for it")
    }

    func testTheRulesThatPlayTheSoundAreCountedOverTheRulesInEffectAndTheDraft() throws {
        XCTAssertTrue(try body(of: "func rulesNaming(_ sound: String) -> Int {", in: try ruleModel())
            .contains("SoundUse.count(naming: sound, inSaved: loadedRules, andDraft: rules)"))
        XCTAssertTrue(try delegate().contains("rulesNaming: { [weak self] name in self?.ruleEditor.model.rulesNaming(name) ?? 0 },"))
    }

    // MARK: - Closing asks

    func testClosingWithEditsThatAreNotSavedAnswersNotYetAsksAndClosesOnlyAfterTheAnswerHasBeenCarriedOut() throws {
        let controller = try controller()
        let should = try body(of: "func windowShouldClose(_ sender: NSWindow) -> Bool {", in: controller)
        XCTAssertTrue(should.contains("guard model?.hasUnsavedEdits == true, !closingAnswered else { return true }"))
        XCTAssertTrue(should.contains("askAboutUnsavedEdits { [weak self] proceed in if proceed { self?.close(sender) } }"))
        XCTAssertLessThan(try position(of: "askAboutUnsavedEdits {", in: should), try position(of: "return false", in: should))
        let close = try body(of: "private func close(_ window: NSWindow) {", in: controller)
        for line in ["closingAnswered = true", "window.close()", "closingAnswered = false"] {
            XCTAssertEqual(count(line, in: close), 1, line)
        }
    }

    func testTheQuestionIsTheCoresInTheTextsWordsAndSaveAsNewIsTheOnlyWayItSaves() throws {
        let ask = try body(of: "private func askAboutUnsavedEdits(then: @escaping (Bool) -> Void) {", in: try controller())
        XCTAssertTrue(ask.contains("let canSaveAsNew = model.saveControls.canSaveAsNew"))
        XCTAssertTrue(ask.contains("alert.messageText = SoundEditorText.closeQuestion(model.displayName)"))
        XCTAssertTrue(ask.contains("alert.informativeText = SoundEditorText.closeDetail"))
        XCTAssertTrue(ask.contains("for choice in SoundCloseQuestion.choices(canSaveAsNew: canSaveAsNew) {"))
        XCTAssertTrue(ask.contains("alert.addButton(withTitle: SoundCloseQuestion.title(of: choice)).hasDestructiveAction = SoundCloseQuestion.discards(choice)"))
        XCTAssertTrue(ask.contains("switch SoundCloseQuestion.choice(atButton: response.rawValue - first, canSaveAsNew: canSaveAsNew) {"))
        XCTAssertTrue(ask.contains("case .saveAsNew: self.saveAsNew(then: then)"), "saved before the window is let go")
        XCTAssertTrue(ask.contains("case .dontSave: then(true)"))
        XCTAssertTrue(ask.contains("case .cancel, nil: then(false)"))
        XCTAssertTrue(ask.contains("guard let model, model.hasUnsavedEdits else { return then(true) }"))
    }

    func testAnotherSoundIsNotOpenedOverEditsThatAreNotSavedWithoutAsking() throws {
        let show = try body(of: "func show(sound name: String, ruleGainDB: Double, saved: @escaping (String) -> Void) {", in: try controller())
        XCTAssertTrue(show.contains("if isOpen, model?.hasUnsavedEdits == true {"))
        XCTAssertLessThan(try position(of: "askAboutUnsavedEdits {", in: show), try position(of: "self?.replace(with:", in: show),
                          "the replacing is the answer's")
    }

    func testTheWindowIsClosedOnlyOnceTheModelHasLetGoOfTheSoundAndTheSaveHasTold() throws {
        let closed = try body(of: "func windowClosed() {", in: try model())
        XCTAssertEqual(count("opened = nil", in: closed), 1, "the sound the saves are made from is let go with the rest")
    }

    // MARK: - Words

    func testEveryNewControlIsNamedFromTheTextsAndTheFilesHoldNoWordOfTheirOwn() throws {
        let view = try view()
        for named in ["Text(SoundEditorText.nameLabel)", "SoundEditorText.saving", "SoundEditorText.saveAsNew", "SoundEditorText.save)"] {
            XCTAssertGreaterThanOrEqual(count(named, in: view), 1, named)
        }
        for file in ["SoundEditorView.swift", "SoundEditorWindowController.swift"] {
            let policy: LiteralPolicy = file.hasSuffix("View.swift") ? .strictView : .strictController
            XCTAssertEqual(LiteralRules.violations(in: try XCTUnwrap(AppSources.read(file), file), policy: policy), [], file)
        }
        XCTAssertEqual(LiteralRules.violations(in: try XCTUnwrap(AppSources.read("SoundEditorModel.swift")), policy: .baseline([])), [])
        XCTAssertEqual(count("EditorText.editSound", in: try alertView()), 1)
    }
}

/// A button's shortcut is met before a text field's own, so the name field must have the keyboard to itself.
final class SoundEditorNameFieldWiringTests: XCTestCase {
    func testTheCommandsShortcutsGiveWayWhileTheNameFieldHasTheKeyboard() throws {
        let view = try code("SoundEditorView.swift")
        XCTAssertEqual(count("@FocusState private var nameIsFocused: Bool", in: view), 1)
        XCTAssertEqual(count(".focused($nameIsFocused)", in: view), 1, "the one field")
        XCTAssertEqual(count(".environment(\\.nameFieldIsFocused, nameIsFocused)", in: view), 1)
        XCTAssertTrue(try body(of: "func body(content: Content) -> some View {", in: view).contains("!typing"))
        XCTAssertLessThan(try position(of: ".environment(\\.nameFieldIsFocused, nameIsFocused)", in: view),
                          try position(of: "private var transport: some View {", in: view),
                          "told to the whole of the editor, the buttons that carry a shortcut among it")
        XCTAssertEqual(count("@Environment(\\.nameFieldIsFocused) private var typing", in: view), 1)
    }
}
