import XCTest
@testable import NotificationCore

/// What has to hold of the editing the sound editor's window does, read as text, since the app target has no tests and
/// a line that edits the sound the wrong way, or off the main actor's rules, builds cleanly (sound editor plan,
/// Task 8). What each edit comes to, where its edges go, what is on and what is off, and where the playhead goes
/// after it are the core's and are tested there (`SoundEditorEditingTests`, `SoundEditorEditControlsTests` and
/// `SoundEditorEditingTextTests`). These hold that the files hand on to them as they should: every edit is made by
/// `SoundEditHistory.commit` and by nothing else, a render follows each change and is started off the main actor, its
/// result is taken only if it is the newest, the shortcuts are the plan's seven and nothing else, a check's press is
/// shown only when it has a fix, and only the two checks that stop a save are drawn as a fault. They start nothing and
/// show no window.
final class SoundEditorEditingWiringTests: XCTestCase {
    private func model() throws -> String { try code("SoundEditorModel.swift") }
    private func view() throws -> String { try code("SoundEditorView.swift") }
    private func waveform() throws -> String { try code("WaveformView.swift") }
    private func controller() throws -> String { try code("SoundEditorWindowController.swift") }

    // MARK: - Every edit goes through the history's commit

    func testTheHistoryIsMadeOnceFromTheRecipeThatWasOpenedAndLetGoOfOnClose() throws {
        let model = try model()
        XCTAssertEqual(count("@Published private(set) var history: SoundEditHistory?", in: model), 1)
        XCTAssertEqual(count("history = SoundEditHistory(sound.recipe)", in: model), 1)
        XCTAssertEqual(count("history = nil", in: model), 1)
        XCTAssertEqual(count("history = ", in: model), 2, "set when opened and let go of when closed, and at no other place")
        XCTAssertEqual(count("private var recipe", in: model), 0, "the present recipe is the history's and no copy of it is kept")
    }

    func testEveryEditIsMadeByTheOneCallOfTheHistorysCommit() throws {
        let model = try model()
        XCTAssertEqual(count(".commit(", in: model), 1)
        XCTAssertEqual(count("history?.commit(edit)", in: model), 1)
        let commit = try body(of: "private func commit(_ edit: SoundEdit) throws -> Bool {", in: model)
        XCTAssertTrue(commit.contains("guard try history?.commit(edit) == true else { return false }"))
        XCTAssertLessThan(try position(of: "history?.commit(edit)", in: commit),
                          try position(of: "changed(placing: SoundEditPlacement.after(edit))", in: commit),
                          "a render and a placement follow an edit that changed something, and only that")
        // The edits it is handed are the plan's, the core's, and a check's own fix: the model makes none of its own.
        XCTAssertEqual(count("try commit(", in: model), 2, "an edit of a command, and a check's press")
        for made in ["SoundRecipe(", "SoundEdit.", ".applied(to", "SoundSegment", "SoundRender."] {
            XCTAssertEqual(count(made, in: model), 0, "the model builds no edit and applies none: \(made)")
        }
        for file in ["SoundEditorView.swift", "WaveformView.swift", "SoundEditorWindowController.swift"] {
            for made in [".commit(", ".applied(to", "SoundEditHistory", "history"] {
                XCTAssertEqual(count(made, in: try code(file)), 0, "\(file) reaches the history: \(made)")
            }
        }
    }

    func testUndoRedoAndResetAreTheHistorysOwnAndAreTheOnlyOtherWaysItChanges() throws {
        let model = try model()
        XCTAssertEqual(count("history?.undo()", in: model), 1)
        XCTAssertEqual(count("history?.redo()", in: model), 1)
        XCTAssertEqual(count("history?.reset()", in: model), 1)
        XCTAssertTrue(try body(of: "func undo() {", in: model).contains("if history?.undo() == true { changed(placing: .keep) }"))
        XCTAssertTrue(try body(of: "func redo() {", in: model).contains("if history?.redo() == true { changed(placing: .keep) }"))
        XCTAssertTrue(try body(of: "func resetToOriginal() {", in: model)
            .contains("if history?.reset() == true { changed(placing: .playhead(0)) }"))
    }

    func testEveryCommandIsHandledBySwitchWithNoDefaultSoThatANewOneCannotBeLeftOut() throws {
        let perform = try body(of: "func perform(_ command: SoundEditorText.Command) {", in: try model())
        XCTAssertTrue(trimmed(perform).hasPrefix("guard controls.canPerform(command) else { return }"), "nothing is done that is off")
        XCTAssertEqual(count("default:", in: perform), 0)
        for line in ["case .play, .stop: togglePlayback()", "case .loopSelection: setLoops(!loops)", "case .selectAll: selectAll()",
                     "case .clearSelection: clearSelection()", "case .zoomIn: zoomIn()", "case .zoomOut: zoomOut()",
                     "case .undo: undo()", "case .redo: redo()", "case .resetToOriginal: resetToOriginal()",
                     "case .trim, .delete, .cut, .copy, .paste, .duplicate, .fadeIn, .fadeOut, .gain, .repeatSelection: edit(command)"] {
            XCTAssertEqual(count(line, in: perform), 1, line)
        }
    }

    func testAnEditIsPlannedByTheCoreFromTheSelectionAndTheSamplesOfTheLastRenderAndFromNothingElse() throws {
        let edit = try body(of: "private func edit(_ command: SoundEditorText.Command) {", in: try model())
        XCTAssertEqual(count("SoundEditorEditing.plan(", in: try model()), 1)
        XCTAssertTrue(edit.contains("guard let rendered else { return }"))
        for argument in ["SoundEditorEditing.plan(command, selection: timeline.selection, playhead: timeline.playhead,",
                         "samples: rendered.samples, clipboard: clipboard, gainDB: gainDB, plays: repeatPlays,",
                         "gapSeconds: repeatGapSeconds)"] {
            XCTAssertEqual(count(argument, in: edit), 1, argument)
        }
        XCTAssertEqual(count("ZeroCrossing", in: try model()), 0, "the snapping is the core's, which the plan does")
    }

    func testACutIsOnTheClipboardOnlyOnceItIsMadeAndACopyIsMadeFromTheRecipeAsItWas() throws {
        let make = try body(of: "private func make(_ planned: SoundEditorEdit) throws {", in: try model())
        XCTAssertLessThan(try position(of: "try history?.present.excerpt(of: $0)", in: make),
                          try position(of: "guard try commit(edit) else { return }", in: make), "taken before the cut is made")
        XCTAssertLessThan(try position(of: "guard try commit(edit) else { return }", in: make),
                          try position(of: "if let copied { clipboard = copied }", in: make), "kept once the cut is made")
        XCTAssertEqual(count("clipboard = ", in: try model()), 2, "what was copied, and let go of when the window closes")
    }

    // MARK: - A refusal is said, in the text's words and to VoiceOver

    func testARefusedEditIsSaidInTheTextsWordsAndNothingElseIsShown() throws {
        let model = try model()
        let attempt = try body(of: "private func attempt(_ work: () throws -> Void) {", in: model)
        XCTAssertTrue(attempt.contains("} catch let refusal as SoundEditRefusal {"))
        XCTAssertTrue(attempt.contains("say(SoundEditorText.refusal(refusal))"))
        XCTAssertTrue(attempt.contains("} catch {"))
        XCTAssertTrue(attempt.contains("say(SoundEditorText.editFailed)"))
        XCTAssertLessThan(try position(of: "say(SoundEditorText.refusal(refusal))", in: attempt),
                          try position(of: "say(SoundEditorText.editFailed)", in: attempt))
        XCTAssertEqual(count("say(", in: model), 9,
                       "its own declaration, a refusal of the plan, the two of attempt, the three ways a preview does not play, "
                       + "and the two things a save can say (Task 9)")
        XCTAssertEqual(count("say(SoundEditorText.refusal(refusal))", in: model), 2)
        XCTAssertEqual(count("SoundEditorText.refusal(", in: model), 2)
        XCTAssertEqual(count("localizedDescription", in: model), 0)
    }

    func testAPreviewThatDidNotPlayIsSaidAndSoAnnouncedAndNeverOnlyDrawn() throws {
        let model = try model()
        let play = try body(of: "private func play(resumingAt frame: Int? = nil) {", in: model)
        for sentence in ["previewRefused", "previewFailed"] {
            XCTAssertTrue(play.contains("say(SoundEditorText.\(sentence))"), sentence)
            XCTAssertEqual(count("notice = SoundEditorText.\(sentence)", in: model), 0, "\(sentence) is said and not only drawn")
        }
        // A sound that would not be heard as an alert is told so when Space is pressed, and not left to do nothing.
        XCTAssertTrue(play.contains("guard let gain = rendered.previewGainDB else {"))
        XCTAssertTrue(play.contains("say(SoundEditorText.previewSilent)"))
        XCTAssertLessThan(try position(of: "guard let gain = rendered.previewGainDB else {", in: play),
                          try position(of: "say(SoundEditorText.previewSilent)", in: play))
        XCTAssertEqual(count("notice = SoundEditorText.", in: model), 0, "every word shown is said")
    }

    func testWhatIsSaidIsShownAndAnnouncedToVoiceOverSinceANoticeThatIsOnlyDrawnIsNotHeard() throws {
        let say = try body(of: "private func say(_ sentence: String) {", in: try model())
        XCTAssertTrue(say.contains("notice = sentence"))
        XCTAssertTrue(say.contains("AccessibilityNotification.Announcement(sentence).post()"))
        XCTAssertEqual(count("AccessibilityNotification", in: try model()), 1)
    }

    // MARK: - A render follows each change, off the main actor, and only the newest is taken

    func testEachChangeStopsAPreviewKeepsWhereToPutTheHeadAndAsksForARender() throws {
        let model = try model()
        let changed = try body(of: "private func changed(placing placement: SoundEditPlacement) {", in: model)
        XCTAssertLessThan(try position(of: "if isPreviewing { stop() }", in: changed),
                          try position(of: "pendingPlacement = placement", in: changed), "what plays is the sound as it was")
        XCTAssertLessThan(try position(of: "pendingPlacement = placement", in: changed),
                          try position(of: "requestRender()", in: changed))
        XCTAssertEqual(count("requestRender()", in: model), 3, "its declaration, when the sound is opened, and after a change")
        XCTAssertEqual(count("changed(placing:", in: model), 4, "an edit, undo, redo and reset")
    }

    func testARenderIsOfTheHistorysPresentRecipeTakenBeforeTheTaskIsDetached() throws {
        let render = try body(of: "private func requestRender() {", in: try model())
        XCTAssertTrue(render.contains("guard let source, let recipe = history?.present else { return }"))
        XCTAssertLessThan(try position(of: "guard let source, let recipe = history?.present else { return }", in: render),
                          try position(of: "await Task.detached(priority: .userInitiated) {", in: render),
                          "values are taken on the main actor and handed to the task, which touches none of its state")
    }

    func testAPlacementIsAppliedOnlyOnceTheRenderIsTakenAndAfterTheTimelineIsGivenItsNewLength() throws {
        let take = try body(of: "private func takeRender(_ made: SoundRendered, askedFor number: Int) {", in: try model())
        let accepted = try position(of: "renderTickets.accept(number)", in: take)
        let swapped = try position(of: "rendered = made", in: take)
        let length = try position(of: "timeline.setLength(made.samples.frameCount)", in: take)
        let placed = try position(of: "timeline.apply(placement)", in: take)
        XCTAssertLessThan(accepted, swapped)
        XCTAssertLessThan(swapped, length)
        XCTAssertLessThan(length, placed, "a selection is held to the new length before the edit says where it goes")
        XCTAssertTrue(take.contains("if let placement = pendingPlacement {"))
        XCTAssertTrue(take.contains("pendingPlacement = nil"))
        XCTAssertTrue(take.contains("viewport.reveal(timeline.playhead)"))
        XCTAssertEqual(count("timeline.apply(", in: try model()), 1)
    }

    func testNothingThatReadsAPositionIsDoneWhileTheLastRenderIsStillUnderWay() throws {
        let model = try model()
        XCTAssertTrue(try body(of: "var controls: SoundEditorControls {", in: model).contains("isCatchingUp: isCatchingUp"))
        XCTAssertTrue(try body(of: "func fix(_ finding: SoundFinding) {", in: model)
            .contains("guard let fix = finding.fix, controls.canPress(fix) else { return }"))
    }

    func testAChecksPressIsAnUndoOrAnEditAndNothingElseAndAnEditIsTheFindingsOwnAndNotMovedToAChangeOfSign() throws {
        let fix = try body(of: "func fix(_ finding: SoundFinding) {", in: try model())
        XCTAssertTrue(fix.contains("case .undo: undo()"))
        XCTAssertTrue(fix.contains("case .edit(let edit): attempt { _ = try commit(edit) }"))
        XCTAssertEqual(count("default:", in: fix), 0)
        XCTAssertEqual(count("SoundEditorEditing.snapped(", in: try model()), 0, "a fix is exact: the check chose its frames")
    }

    func testTheSettingsOfGainAndRepeatAreHeldToTheCoresRangesBeforeTheyAreKept() throws {
        let model = try model()
        XCTAssertTrue(try body(of: "func setGainDB(_ value: Double) {", in: model).contains("gainDB = SoundEditorEditing.clampedGainDB(value)"))
        XCTAssertTrue(try body(of: "func setRepeatPlays(_ value: Int) {", in: model).contains("repeatPlays = SoundEditorEditing.clampedPlays(value)"))
        XCTAssertTrue(try body(of: "func setRepeatGapSeconds(_ value: Double) {", in: model)
            .contains("repeatGapSeconds = SoundEditorEditing.clampedGapSeconds(value)"))
        XCTAssertEqual(count("gainDB = ", in: model), 2, "its declaration's value, and the one setter")
        XCTAssertEqual(count("@Published private(set) var gainDB = 0.0", in: model), 1)
    }

    func testClosingTheWindowLetsGoOfTheHistoryTheClipboardAndAPlacementNobodyWillTake() throws {
        let closed = try body(of: "func windowClosed() {", in: try model())
        for line in ["history = nil", "clipboard = nil", "pendingPlacement = nil"] {
            XCTAssertEqual(count(line, in: closed), 1, line)
        }
    }

    // MARK: - The controls

    func testEveryEditHasAButtonNamedFromTheTextThatAsksTheModelAndIsOnOnlyWhenTheCoreSaysSo() throws {
        let view = try view()
        let button = try body(of: "private func commandButton(_ command: SoundEditorText.Command) -> some View {", in: view)
        XCTAssertTrue(button.contains("Button(command.title) { model.perform(command) }"))
        XCTAssertTrue(button.contains(".disabled(!model.controls.canPerform(command))"))
        XCTAssertTrue(button.contains(".shortcut(of: command)"))
        for command in ["trim", "delete", "cut", "copy", "paste", "duplicate", "fadeIn", "fadeOut", "undo", "redo", "resetToOriginal"] {
            XCTAssertEqual(count("commandButton(.\(command))", in: view), 1, "\(command) has the one button")
        }
        XCTAssertEqual(count("model.perform(", in: view), 3, "a button of an edit, the gain's and the repeat's")
    }

    func testTheSevenShortcutsAreTheCommandsOwnAndAreSetInOnePlaceFromTheCore() throws {
        let view = try view()
        XCTAssertEqual(count(".keyboardShortcut(", in: view), 1)
        XCTAssertTrue(try body(of: "func shortcut(of command: SoundEditorText.Command) -> some View {", in: view)
            .contains("modifier(CommandShortcut(command: command))"))
        XCTAssertTrue(try body(of: "func body(content: Content) -> some View {", in: view)
            .contains("if let shortcut = command.shortcut, !typing {"),
                      "the command's own shortcut, and none while the name field has the keyboard (Task 9)")
        XCTAssertEqual(count(".keyboardShortcut(KeyEquivalent(shortcut.key), modifiers: shortcut.shift ? [.command, .shift] : .command)",
                             in: view), 1)
        XCTAssertEqual(count(".shortcut(of: .selectAll)", in: view), 1, "Select All is the one that is not made by commandButton")
        XCTAssertEqual(count(".shortcut(of:", in: view), 2)
        for file in ["SoundEditorModel.swift", "WaveformView.swift", "SoundEditorWindowController.swift"] {
            XCTAssertEqual(count("keyboardShortcut", in: try code(file)), 0, file)
        }
    }

    func testTheGainIsOfferedOnlyForAPartAndTheSentenceOfRulingSixteenIsBesideIt() throws {
        let gain = try body(of: "private var gain: some View {", in: try view())
        let offered = try position(of: "if model.controls.offersGain {", in: gain)
        let slider = try position(of: "Slider(value: Binding(get: { model.gainDB }, set: { model.setGainDB($0) }),", in: gain)
        let note = try position(of: "Text(SoundEditorText.gainNote)", in: gain)
        let otherwise = try position(of: "} else {", in: gain)
        let needs = try position(of: "Text(SoundEditorText.gainNeedsASelection)", in: gain)
        XCTAssertLessThan(offered, slider)
        XCTAssertLessThan(slider, note, "the sentence is beside the gain it is about")
        XCTAssertLessThan(note, otherwise)
        XCTAssertLessThan(otherwise, needs, "where it is not offered, what to do to have it offered")
        XCTAssertTrue(gain.contains("in: SoundEditorEditing.gainRangeDB, step: SoundEditorEditing.gainStepDB)"))
        XCTAssertTrue(gain.contains(".accessibilityLabel(SoundEditorText.gainLabel)"))
        XCTAssertTrue(gain.contains(".accessibilityValue(SoundEditorText.gainValue(model.gainDB))"))
        XCTAssertTrue(gain.contains("Button(SoundEditorText.Command.gain.title) { model.perform(.gain) }"))
        XCTAssertTrue(gain.contains(".disabled(!model.controls.canPerform(.gain))"))
        XCTAssertEqual(count("offersGain", in: try view()), 1)
    }

    func testTheRepeatsPlaysAndGapAreSteppedWithinTheCoresRangesAndSaidInTheTextsWords() throws {
        let repeats = try body(of: "private var repeats: some View {", in: try view())
        XCTAssertTrue(repeats.contains("Stepper(SoundEditorText.playsLabel, value: Binding(get: { model.repeatPlays }, set: { model.setRepeatPlays($0) }),"))
        XCTAssertTrue(repeats.contains("in: SoundEditorEditing.playsRange)"))
        XCTAssertTrue(repeats.contains("Stepper(SoundEditorText.gapLabel, value: Binding(get: { model.repeatGapSeconds }, set: { model.setRepeatGapSeconds($0) }),"))
        XCTAssertTrue(repeats.contains("in: SoundEditorEditing.gapRangeSeconds, step: SoundEditorEditing.gapStepSeconds)"))
        XCTAssertTrue(repeats.contains(".accessibilityValue(SoundEditorText.playsValue(model.repeatPlays))"))
        XCTAssertTrue(repeats.contains(".accessibilityValue(SoundEditorText.gapValue(model.repeatGapSeconds))"))
        XCTAssertTrue(repeats.contains("Button(SoundEditorText.Command.repeatSelection.title) { model.perform(.repeatSelection) }"))
        XCTAssertTrue(repeats.contains(".disabled(!model.controls.canPerform(.repeatSelection))"))
    }

    // MARK: - The checks' presses and the fault outline

    func testAPressIsShownOnlyForAFindingWhoseOwnFixIsThereAndIsOnWhenTheCoreSaysSo() throws {
        let view = try view()
        XCTAssertEqual(count("SoundEditorText.press(for: finding)", in: view), 1)
        XCTAssertEqual(count("pressLabel", in: view), 0, "the label is asked for through the finding, which has none without a fix")
        XCTAssertEqual(count("finding.fix", in: view), 1)
        XCTAssertTrue(view.contains("if let press = SoundEditorText.press(for: finding), let fix = finding.fix {"))
        XCTAssertTrue(view.contains("Button(press) { model.fix(finding) }"))
        XCTAssertTrue(view.contains(".disabled(!model.controls.canPress(fix))"))
        XCTAssertEqual(count("model.fix(", in: view), 1)
    }

    func testOnlyTheTwoChecksThatStopASaveAreOutlinedAsAFaultAndNothingElseInTheWindowIs() throws {
        let view = try view()
        XCTAssertEqual(count(".faultOutlined(", in: view), 1)
        XCTAssertEqual(count(".faultOutlined(when: finding.blocksSaving)", in: view), 1)
        XCTAssertEqual(count("faultOutlined", in: try waveform()), 0)
        XCTAssertEqual(count("faultOutlined", in: try model()), 0)
        XCTAssertEqual(count("faultOutlined", in: try controller()), 0)
        // The refusal of an edit is not a fault: it stops nothing that is saved or played.
        let notes = try body(of: "private var notes: some View {", in: view)
        XCTAssertEqual(count("faultOutlined", in: notes), 0)
        // And which checks stop a save is the core's to say, and is these two.
        for kind in SoundFinding.Kind.allCases {
            XCTAssertEqual(SoundFinding(kind: kind, frames: nil, fix: nil).blocksSaving, kind == .nothingToHear || kind == .tooLong)
        }
    }

    // MARK: - The window and the words

    func testTheGainAndRepeatAreNamedFromTheTextAndTheViewStillHoldsNoWordOfItsOwn() throws {
        let view = try view()
        for name in ["SoundEditorText.gainLabel", "SoundEditorText.playsLabel", "SoundEditorText.gapLabel"] {
            XCTAssertGreaterThanOrEqual(count(name, in: view), 1, name)
        }
        XCTAssertEqual(LiteralRules.violations(in: try XCTUnwrap(AppSources.read("SoundEditorView.swift")), policy: .strictView), [])
    }
}
