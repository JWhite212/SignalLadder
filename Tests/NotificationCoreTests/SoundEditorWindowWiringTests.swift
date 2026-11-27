import XCTest
@testable import NotificationCore

/// What has to hold of the files of the sound editor's window, read as text, since the app target has no tests and a
/// line that plays a sound the wrong way, or says a word of its own, builds cleanly (sound editor plan, Task 7). The
/// decisions are the core's and are tested there (`SoundTimelineTests`, `WaveformKeysTests`, `SoundPreviewPlanTests`,
/// `SoundEditorControlsTests`, `SoundRenderTicketsTests` and `SoundEditorRenderingTests`). These hold that the files
/// hand on to them and to the player as they should: a preview is played through `testBuffer` and never as an alert,
/// nothing slow runs on the main actor, Space is the waveform's, every control is named from the text, and nothing in
/// the app can open the window yet. They start nothing and show no window.
final class SoundEditorWindowWiringTests: XCTestCase {
    private let ownFiles = ["SoundEditorModel.swift", "SoundEditorView.swift", "SoundEditorWindowController.swift",
                            "WaveformView.swift"]

    private func model() throws -> String { try code("SoundEditorModel.swift") }
    private func view() throws -> String { try code("SoundEditorView.swift") }
    private func waveform() throws -> String { try code("WaveformView.swift") }
    private func controller() throws -> String { try code("SoundEditorWindowController.swift") }

    /// The first argument of each call of `name`, as written, where `name` is not the end of a longer name.
    private func firstArguments(of name: String, in code: String) -> [String] {
        var found: [String] = []
        var from = code.startIndex
        while let range = code.range(of: name + "(", range: from..<code.endIndex) {
            from = range.upperBound
            if let before = code[..<range.lowerBound].last, before.isLetter || before.isNumber || before == "_" || before == "." {
                continue
            }
            var depth = 0
            var argument = ""
            scan: for character in code[range.upperBound...] {
                switch character {
                case "(", "[", "{": depth += 1
                case ")", "]", "}":
                    if depth == 0 { break scan }
                    depth -= 1
                case ",": if depth == 0 { break scan }
                default: break
                }
                argument.append(character)
            }
            found.append(argument.split(whereSeparator: \.isWhitespace).joined(separator: " "))
        }
        return found
    }

    // MARK: - The files hold no word of their own

    func testTheFilesAreHeldToTheTextEnumsAsEveryNewFileIs() throws {
        XCTAssertTrue(HeldFiles.strictViews.contains("SoundEditorView.swift"))
        XCTAssertTrue(HeldFiles.strictViews.contains("WaveformView.swift"))
        XCTAssertTrue(HeldFiles.strictControllers.contains("SoundEditorWindowController.swift"))
        XCTAssertTrue(HeldFiles.baselineOthers.contains { $0.file == "SoundEditorModel.swift" && $0.literals.isEmpty })
        for file in ["SoundEditorView.swift", "WaveformView.swift"] {
            XCTAssertEqual(LiteralRules.violations(in: try XCTUnwrap(AppSources.read(file), file), policy: .strictView), [], file)
        }
        XCTAssertEqual(LiteralRules.violations(in: try XCTUnwrap(AppSources.read("SoundEditorWindowController.swift")),
                                               policy: .strictController), [])
        XCTAssertEqual(LiteralRules.violations(in: try XCTUnwrap(AppSources.read("SoundEditorModel.swift")),
                                               policy: .baseline([])), [])
    }

    func testAWordTypedIntoAnyOfTheFilesIsRefused() throws {
        for (file, anchor, typed, word) in [
            ("SoundEditorView.swift", "Text(SoundEditorText.checksHeading)", #"Text("Checks")"#, "Checks"),
            ("SoundEditorView.swift", "Toggle(SoundEditorText.Command.loopSelection.title,", #"Toggle("Loop",""#, "Loop"),
            ("WaveformView.swift", ".accessibilityHint(SoundEditorText.waveformHint)", #".accessibilityHint("Press space")"#,
             "Press space"),
            ("SoundEditorWindowController.swift", "window.title = WindowTitles.soundEditor", #"window.title = "Sound Editor""#,
             "Sound Editor"),
            ("SoundEditorModel.swift", "say(SoundEditorText.previewFailed)", #"say("It did not play")"#,
             "It did not play"),
        ] {
            let source = try XCTUnwrap(AppSources.read(file), file)
            XCTAssertTrue(source.contains(anchor), "\(anchor) is where this test types a word")
            let added = source.replacingOccurrences(of: anchor, with: typed)
            let policy: LiteralPolicy = file.hasSuffix("View.swift") ? .strictView
                : file.hasSuffix("Controller.swift") ? .strictController : .baseline([])
            XCTAssertEqual(LiteralRules.violations(in: added, policy: policy).map(\.text), [word], "\(file): \(word)")
        }
    }

    func testEveryTextAndLabelAndButtonOfTheViewsTakesItsWordsFromTheTextEnumsOrFromWordsTheModelHolds() throws {
        let allowed = ["SoundEditorText.", "EditorText."]
        let fromTheModel: Set<String> = ["sentence", "notice", "controls.playCommand.title"]
        var seen = 0
        for source in [try view(), try waveform()] {
            for name in ["Text", "Label", "Toggle", "Button", "Slider", "ProgressView"] {
                for argument in firstArguments(of: name, in: source) where !argument.isEmpty {
                    seen += 1
                    if name == "Button" || name == "Slider" || name == "ProgressView" { continue }
                    XCTAssertTrue(allowed.contains { argument.hasPrefix($0) } || fromTheModel.contains(argument),
                                  "\(name)(\(argument) … is not from SoundEditorText or EditorText")
                }
            }
        }
        XCTAssertGreaterThan(seen, 10, "the scan finds the calls it is meant to hold")
        XCTAssertEqual(firstArguments(of: "Text", in: "let x = Text(\"a\")\nSoundEditorText(\"b\")\nfoo.Text(\"c\")"), [#""a""#],
                       "the scan reads a call and not the end of a longer name")
    }

    func testTheWordsTheModelHoldsAreTheTextsAndNothingElse() throws {
        let model = try model()
        XCTAssertEqual(count("notice = ", in: model), 3, "cleared by a preview and by an edit, and said, which is how every sentence is shown")
        XCTAssertEqual(count("notice = nil", in: model), 2)
        XCTAssertEqual(count("notice = sentence", in: model), 1, "the one sentence an edit's refusal is shown with (Task 8)")
        XCTAssertEqual(count("say(SoundEditorText.previewRefused)", in: model), 1)
        XCTAssertEqual(count("say(SoundEditorText.previewFailed)", in: model), 1)
        XCTAssertEqual(count("say(SoundEditorText.previewSilent)", in: model), 1)
        XCTAssertEqual(count("phase = .failed(SoundEditorText.cannotOpen(name, failure: failure))", in: model), 1)
        XCTAssertEqual(count(".failed(", in: model), 1, "the one sentence a failed open is shown with")
    }

    func testNeitherAFailureOfThePlayersNorOfTheSystemIsShownInItsOwnWords() throws {
        for source in [try model(), try view(), try waveform(), try controller()] {
            XCTAssertEqual(count("description", in: source), 0, "no failure's own description is shown or kept")
            XCTAssertEqual(count("localizedDescription", in: source), 0)
            XCTAssertEqual(count("$0.reason", in: source), 0)
        }
    }

    // MARK: - A preview is a test and never an alert

    func testThePreviewIsPlayedThroughTestBufferAtTheGainTheWholeResultWouldBeGivenAndByNothingElse() throws {
        let model = try model()
        XCTAssertEqual(count("player.testBuffer(", in: model), 1)
        XCTAssertEqual(count("try player.testBuffer(rendered.samples, gainDB: gain, from: plan.start, loop: plan.loop)", in: model), 1)
        let play = try body(of: "private func play(resumingAt frame: Int? = nil) {", in: model)
        XCTAssertLessThan(try position(of: "guard let gain = rendered.previewGainDB else {", in: play),
                          try position(of: "player.testBuffer(", in: play),
                          "the last render that finished, at the gain it was given when it was made")
        XCTAssertTrue(play.contains("SoundPreviewPlan.make("))
        XCTAssertEqual(count("Loudness.", in: model), 0, "the gain is worked out once, with the render, from all of the result")
        XCTAssertEqual(count("peak", in: model), 0)
        XCTAssertEqual(count("ruleGainDB: rule", in: model), 1, "and the rule's own gain goes into the render and nowhere else")
    }

    func testNoFileOfTheWindowPlaysAnAlertSilencesOneOrCallsAnyOtherWayOfPlaying() throws {
        for file in ownFiles {
            let source = try code(file)
            for call in [".play(sound", ".testSound(", ".playAndSpeak(", ".speak(", ".testSpeech(", ".silence()", ".prepare(",
                         ".outcome(of", "alertSetOff", "forgetPreparedSounds", "isPlayingAlert"] {
                XCTAssertEqual(count(call, in: source), 0, "\(file) calls \(call)")
            }
        }
    }

    func testNothingElseInTheAppCallsTestBuffer() throws {
        var callers: [String] = []
        for file in try AppSources.fileNames() where try code(file).contains("testBuffer(") { callers.append(file) }
        XCTAssertEqual(callers, ["SoundEditorModel.swift"])
    }

    func testAPreviewThatDidNotPlayIsToldAnAlertIsSoundingOnlyWhenOneIsAndOtherwiseThatItCouldNotPlay() throws {
        let play = try body(of: "private func play(resumingAt frame: Int? = nil) {", in: try model())
        XCTAssertLessThan(try position(of: "} catch AlertPlayer.Failure.alertPlaying {", in: play),
                          try position(of: "say(SoundEditorText.previewRefused)", in: play))
        XCTAssertLessThan(try position(of: "say(SoundEditorText.previewRefused)", in: play),
                          try position(of: "} catch {", in: play))
        XCTAssertLessThan(try position(of: "} catch {", in: play),
                          try position(of: "say(SoundEditorText.previewFailed)", in: play))
    }

    func testStoppingIsStopTestAndNothingElseAndTheWindowClosingStopsOnlyAPreviewOfItsOwn() throws {
        let model = try model()
        XCTAssertEqual(count("player.stopTest()", in: model), 2, "Stop, and the window closing")
        let stop = try body(of: "func stop() {", in: model)
        XCTAssertLessThan(try position(of: "let frame = player.previewFrame", in: stop),
                          try position(of: "player.stopTest()", in: stop), "where it had got to is read before it is stopped")
        let closed = try body(of: "func windowClosed() {", in: model)
        XCTAssertTrue(closed.contains("if isPreviewing { player.stopTest() }"))
        XCTAssertTrue(closed.contains("renderTickets.cancelAll()"))
        XCTAssertTrue(closed.contains("columnTickets.cancelAll()"))
        XCTAssertEqual(try controller().components(separatedBy: "model?.windowClosed()").count - 1, 2,
                       "when the window closes, and when it is given another sound")
        XCTAssertEqual(count("func windowWillClose(_ notification: Notification) {", in: try controller()), 1)
    }

    func testThePlayheadIsReadFromThePlayersOwnPositionAndTheEndOfAPreviewIsFoundByItsGoingNil() throws {
        let model = try model()
        let follow = try body(of: "private func follow() -> Bool {", in: model)
        XCTAssertTrue(follow.contains("if let frame = player.previewFrame {"))
        XCTAssertTrue(follow.contains("timeline.followPreview(frame)"))
        XCTAssertTrue(follow.contains("viewport.reveal(frame)"))
        XCTAssertTrue(follow.contains("timeline.previewEnded(returningTo: back)"))
        let ticker = try body(of: "private func startTicker() {", in: model)
        XCTAssertTrue(ticker.contains("guard let self, self.follow() else { return }"))
        XCTAssertTrue(ticker.contains("try? await Task.sleep(for: Self.tick)"))
        XCTAssertEqual(count("Timer", in: model), 0, "no run loop timer: a task that is cancelled with the preview")
    }

    // MARK: - Nothing slow runs on the main actor

    func testOpeningDecodesInADetachedTaskAndAFailureIsSaidInTheTextsWords() throws {
        let open = try body(of: "func open() async {", in: try model())
        let detached = try position(of: "await Task.detached(priority: .userInitiated) {", in: open)
        let read = try position(of: "SoundEditStore(library: library).open(name)", in: open)
        let ended = try position(of: "}.value", in: open)
        XCTAssertLessThan(detached, read)
        XCTAssertLessThan(read, ended, "the reading and decoding are inside the detached task")
        XCTAssertLessThan(ended, try position(of: "case .failure(let failure):", in: open))
        XCTAssertTrue(open.contains("phase = .failed(SoundEditorText.cannotOpen(name, failure: failure))"))
        XCTAssertEqual(count("SoundEditStore(", in: try model()), 1, "opened nowhere else, and never saved here")
        XCTAssertEqual(count(".save(", in: try model()), 0, "nothing is saved yet")
    }

    func testARenderAndTheDrawingsColumnsAreMadeInDetachedTasksAndTheirOwnersAreOnlyHandedValues() throws {
        let model = try model()
        XCTAssertEqual(count("Task.detached(", in: model), 3, "opening, a render and a zoom's columns")
        for (call, request) in [("SoundEditorRendering.render(", "private func requestRender() {"),
                                ("WaveformColumns.make(", "private func refreshColumnsIfNeeded() {")] {
            XCTAssertEqual(count(call, in: model), 1, call)
            let asked = try body(of: request, in: model)
            let detached = try position(of: "await Task.detached(priority: .userInitiated) {", in: asked)
            XCTAssertLessThan(detached, try position(of: call, in: asked), "\(call) is inside the detached task")
            XCTAssertLessThan(try position(of: call, in: asked), try position(of: "}.value", in: asked))
        }
        for work in ["SoundRender.render(", "SoundChecks.", "WaveformPeaks.", "SoundDecoding.", "AVAudio"] {
            XCTAssertEqual(count(work, in: model), 0, "\(work) is not the main actor's to do")
        }
    }

    func testOnlyTheNewestResultIsTakenAndTheOldOneIsKeptWhileAnotherIsUnderWay() throws {
        let model = try model()
        let render = try body(of: "private func requestRender() {", in: model)
        XCTAssertTrue(render.contains("let number = renderTickets.request()"))
        XCTAssertTrue(render.contains("isCatchingUp = renderTickets.isCatchingUp"))
        let take = try body(of: "private func takeRender(_ made: SoundRendered, askedFor number: Int) {", in: model)
        XCTAssertLessThan(try position(of: "renderTickets.accept(number)", in: take), try position(of: "rendered = made", in: take),
                          "the result is checked against the newest request before it is swapped in")
        XCTAssertTrue(take.contains("guard taken else { return }"))
        XCTAssertEqual(count("rendered = made", in: model), 1, "the one place the last finished render is replaced")
        let columns = try body(of: "private func takeColumns(_ made: WaveformColumns, askedFor number: Int) {", in: model)
        XCTAssertTrue(columns.contains("columnTickets.accept(number)"))
        XCTAssertLessThan(try position(of: "columnTickets.accept(number)", in: columns), try position(of: "columns = made", in: columns))
    }

    func testSpacePlaysTheLastRenderThatFinishedAndTheWindowSaysItIsCatchingUp() throws {
        let model = try model()
        XCTAssertTrue(try body(of: "private func play(resumingAt frame: Int? = nil) {", in: model)
            .contains("guard let rendered else { return }"), "`rendered` is only what takeRender swapped in")
        XCTAssertEqual(count("@Published private(set) var isCatchingUp = false", in: model), 1)
        let view = try view()
        XCTAssertEqual(count("if model.isCatchingUp {", in: view), 1)
        XCTAssertLessThan(try position(of: "if model.isCatchingUp {", in: view), try position(of: "Text(SoundEditorText.catchingUp)", in: view))
    }

    // MARK: - Space is the waveform's

    func testTheWaveformIsOneFocusableElementThatTakesTheKeysAndNamesTheKeyAndNothingElse() throws {
        let waveform = try waveform()
        for line in [".focusable()", ".focused($isFocused)", ".onKeyPress(phases: [.down, .repeat]) { press in handle(press) }",
                     "case .space: return .space", "case .leftArrow: return .left", "case .rightArrow: return .right",
                     "case .home: return .home", "case .end: return .end"] {
            XCTAssertEqual(count(line, in: waveform), 1, line)
        }
        let handle = try body(of: "private func handle(_ press: KeyPress) -> KeyPress.Result {", in: waveform)
        XCTAssertTrue(handle.contains("press.modifiers.isDisjoint(with: [.command, .control, .option])"),
                      "a shortcut is for someone else to answer")
        XCTAssertTrue(handle.contains("model.press(key, extending: press.modifiers.contains(.shift))"))
        XCTAssertEqual(count("model.press(", in: waveform), 3, "the key, and the two steps VoiceOver adjusts by")
    }

    func testNoOtherFileHandlesAKeyAndSpaceIsNotAShortcutOfAButton() throws {
        for file in ownFiles where file != "WaveformView.swift" {
            let source = try code(file)
            XCTAssertEqual(count(".onKeyPress", in: source), 0, file)
            XCTAssertEqual(count(".keyboardShortcut(", in: source), file == "SoundEditorView.swift" ? 1 : 0,
                           "\(file): the seven shortcuts of the edits are set in the one place of the view (Task 8)")
            XCTAssertEqual(count("NSEvent", in: source), 0, file)
        }
        XCTAssertEqual(count(".keyboardShortcut(", in: try waveform()), 0)
    }

    func testAKeyIsHandedToTheCoresKeysAndPlayingIsTheModelsAnswerToSpace() throws {
        let press = try body(of: "func press(_ key: WaveformKey, extending: Bool) {", in: try model())
        XCTAssertTrue(press.contains("switch WaveformKeys.apply(key, extending: extending, timeline: &timeline, viewport: &viewport) {"))
        XCTAssertTrue(press.contains("case .togglePlayback:"))
        XCTAssertTrue(press.contains("togglePlayback()"))
        XCTAssertEqual(count("WaveformKeys.apply(", in: try model()), 1)
    }

    func testThePointerIsHandedToTheCoresTimelineAtTheReachAndTheSlopTheCoreGives() throws {
        let model = try model()
        XCTAssertTrue(try body(of: "func pointerDown(x: Double, width: Double) {", in: model)
            .contains("viewport.frames(spanning: WaveformViewport.edgeReachPoints, width: width)"))
        XCTAssertTrue(try body(of: "func pointerMoved(x: Double, width: Double) {", in: model)
            .contains("viewport.frames(spanning: WaveformViewport.clickSlopPoints, width: width)"))
        let waveform = try waveform()
        XCTAssertEqual(count("DragGesture(minimumDistance: 0)", in: waveform), 1)
        XCTAssertEqual(count("model.pointerDown(x: value.startLocation.x, width: width)", in: waveform), 1)
        XCTAssertEqual(count("model.pointerMoved(x: value.location.x, width: width)", in: waveform), 1)
        XCTAssertEqual(count("model.pointerUp(x: value.location.x, width: width)", in: waveform), 1)
    }

    // MARK: - Every control has a label from the text

    func testEveryControlIsNamedFromTheTextAndIsOnOnlyWhenTheCoreSaysSo() throws {
        let view = try view()
        XCTAssertEqual(count("Button {", in: view), 5, "play and stop in one, select all, clear, and the two zooms")
        XCTAssertEqual(count("Toggle(", in: view), 1)
        XCTAssertEqual(count("Slider(", in: view), 2, "the scroller, and the gain's (Task 8)")
        for named in ["Label(controls.playCommand.title, systemImage: model.isPreviewing ? \"stop.fill\" : \"play.fill\")",
                      "Toggle(SoundEditorText.Command.loopSelection.title,",
                      "Text(SoundEditorText.Command.selectAll.title)", "Text(SoundEditorText.Command.clearSelection.title)",
                      "Label(SoundEditorText.Command.zoomOut.title, systemImage: \"minus.magnifyingglass\")",
                      "Label(SoundEditorText.Command.zoomIn.title, systemImage: \"plus.magnifyingglass\")",
                      ".accessibilityLabel(SoundEditorText.visiblePartLabel)"] {
            XCTAssertEqual(count(named, in: view), 1, named)
        }
        XCTAssertEqual(count(".help(SoundEditorText.Command.zoomOut.title)", in: view), 1, "an icon is named to the pointer too")
        XCTAssertEqual(count(".help(SoundEditorText.Command.zoomIn.title)", in: view), 1)
        XCTAssertEqual(count(".labelStyle(.iconOnly)", in: view), 2)
        for off in [".disabled(!controls.canPlayOrStop)", ".disabled(!controls.canLoop)", ".disabled(!controls.canSelectAll)",
                    ".disabled(!controls.canClearSelection)", ".disabled(!controls.canZoomOut)", ".disabled(!controls.canZoomIn)"] {
            XCTAssertEqual(count(off, in: view), 1, off)
        }
        XCTAssertEqual(count("let controls = model.controls", in: view), 1)
        XCTAssertEqual(count("var controls: SoundEditorControls {", in: try model()), 1)
    }

    func testTheWaveformIsOneAdjustableElementThatSaysWhereItIsAndWhatIsSelectedAndOffersThreeActions() throws {
        let waveform = try waveform()
        XCTAssertEqual(count(".accessibilityElement(children: .ignore)", in: waveform), 1)
        XCTAssertEqual(count(".accessibilityLabel(SoundEditorText.waveformLabel(model.displayName))", in: waveform), 1)
        XCTAssertEqual(count(".accessibilityValue(SoundEditorText.waveformValue(playhead: model.timeline.playhead,", in: waveform), 1)
        XCTAssertEqual(count("selection: model.timeline.selection,", in: waveform), 1)
        XCTAssertEqual(count("length: model.timeline.length))", in: waveform), 1)
        XCTAssertEqual(count(".accessibilityHint(SoundEditorText.waveformHint)", in: waveform), 1)
        XCTAssertEqual(count(".accessibilityAdjustableAction { direction in", in: waveform), 1)
        for action in [".accessibilityAction(named: SoundEditorText.Command.selectAll.title) { model.selectAll() }",
                       ".accessibilityAction(named: model.controls.playCommand.title) { model.togglePlayback() }",
                       ".accessibilityAction(named: SoundEditorText.Command.clearSelection.title) { model.clearSelection() }"] {
            XCTAssertEqual(count(action, in: waveform), 1, action)
        }
        XCTAssertEqual(count("case .increment: model.press(.right, extending: false)", in: waveform), 1)
        XCTAssertEqual(count("case .decrement: model.press(.left, extending: false)", in: waveform), 1)
    }

    // MARK: - The drawing

    func testTheSelectionIsToldByMoreThanItsTintAndItsLinesAreAsWideAsTheDisplaySettingsSay() throws {
        let waveform = try waveform()
        for four in ["@Environment(\\.colorSchemeContrast) private var contrast",
                     "@Environment(\\.accessibilityReduceTransparency) private var reduceTransparency",
                     "@Environment(\\.accessibilityReduceMotion) private var reduceMotion",
                     "@Environment(\\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColour"] {
            XCTAssertEqual(count(four, in: waveform), 1, four)
        }
        XCTAssertEqual(count("DisplaySettings(increaseContrast: contrast == .increased, reduceTransparency: reduceTransparency,", in: waveform), 1)
        XCTAssertTrue(waveform.contains("reduceMotion: reduceMotion, differentiateWithoutColour: differentiateWithoutColour)"))
        XCTAssertEqual(count("let line = settings.outlineWidth", in: waveform), 1)
        XCTAssertEqual(count("context.fill(Path(band), with: .color(NightWatchPalette.raised))", in: waveform), 1, "the tint")
        XCTAssertGreaterThanOrEqual(count("lineWidth: line", in: waveform), 3, "the brackets, the handles' edges and the playhead")
        XCTAssertEqual(count("bracket.addLine(to: CGPoint(x: x + inward * reach", in: waveform), 2, "a tick at the top and one at the bottom")
        XCTAssertEqual(count("let handle = CGRect(x: x - reach / 2,", in: waveform), 1, "a handle at each end")
        XCTAssertEqual(count("head.closeSubpath()", in: waveform), 1, "the playhead has a head")
        XCTAssertEqual(count("WaveformViewport.edgeReachPoints", in: waveform), 1, "what is drawn is the reach that can be grabbed")
    }

    func testTheWaveformIsOnTheNavyGroundInThePalettesColoursAndInventsNone() throws {
        let waveform = try waveform()
        XCTAssertEqual(count(".background(NightWatchPalette.ground)", in: waveform), 1)
        XCTAssertEqual(count(".environment(\\.colorScheme, .dark)", in: waveform), 1, "navy whatever the system's appearance")
        for invented in ["Color(", "NSColor", ".opacity(", "Color.red", "Color.blue", ".orange", "systemOrange", ".glassEffect("] {
            XCTAssertEqual(count(invented, in: waveform), 0, invented)
            XCTAssertEqual(count(invented, in: try view()), 0, invented)
        }
        XCTAssertGreaterThanOrEqual(count("NightWatchPalette.", in: waveform), 8)
    }

    func testTheWaveformIsDrawnFromTheCoresBarsAndAPlayheadMovingDoesNotMakeNewOnes() throws {
        let waveform = try waveform()
        XCTAssertEqual(count("model.columns?.bars(in: viewport, width: size.width) ?? []", in: waveform), 1)
        XCTAssertEqual(count("viewport.x(of: frame, width: size.width)", in: waveform), 1)
        XCTAssertEqual(count("WaveformPeaks", in: waveform), 0, "the columns are not made while drawing")
    }

    // MARK: - The checks

    func testTheChecksAreListedWithTheirSentenceAndTheirPressWhereTheyHaveOne() throws {
        let view = try view()
        XCTAssertEqual(count("ForEach(model.findings, id: \\.kind) { finding in", in: view), 1)
        XCTAssertEqual(count("SoundEditorText.sentence(for: finding)", in: view), 1)
        XCTAssertEqual(count("pressLabel", in: view), 0, "the label is asked for through the finding: SoundEditorText.press(for:)")
        XCTAssertEqual(count("finding.fix", in: view), 1, "a press is shown only for a finding whose own fix is not nil (Task 8)")
        XCTAssertEqual(count("SoundFix", in: view), 0)
        XCTAssertEqual(count("var findings: [SoundFinding] { rendered?.findings ?? [] }", in: try model()), 1)
    }

    func testOnlyTheChecksThatStopASaveAreDrawnAsAFault() throws {
        let view = try view()
        XCTAssertEqual(count(".faultOutlined(", in: view), 1)
        XCTAssertEqual(count(".faultOutlined(when: finding.blocksSaving)", in: view), 1)
        XCTAssertEqual(count(".faultOutlined(", in: try waveform()), 0)
        XCTAssertLessThan(try position(of: "SoundEditorText.sentence(for: finding)", in: view),
                          try position(of: ".faultOutlined(when: finding.blocksSaving)", in: view))
    }

    // MARK: - The window

    func testTheWindowIsBuiltAndKeptAsTheRuleEditorsIs() throws {
        let controller = try controller()
        for line in ["styleMask: [.titled, .closable, .resizable, .miniaturizable],", "window.title = WindowTitles.soundEditor",
                     "window.isReleasedWhenClosed = false", "window.delegate = self", "window.center()",
                     "final class SoundEditorWindowController: NSObject, NSWindowDelegate {",
                     "NSApp.activate(ignoringOtherApps: true)", "if window?.isMiniaturized == true { window?.deminiaturize(nil) }",
                     "window?.makeKeyAndOrderFront(nil)"] {
            XCTAssertEqual(count(line, in: controller), 1, line)
        }
        XCTAssertEqual(count("NSWindow(", in: controller), 1)
        XCTAssertTrue(controller.contains("if window == nil {"), "made once and kept")
        XCTAssertEqual(count("window?.contentView = NSHostingView(rootView: SoundEditorView(model: model))", in: controller), 1)
    }

    func testTheEntryPointTakesASoundsNameTheRulesGainAndACallbackForASavedName() throws {
        let controller = try controller()
        XCTAssertEqual(count("func show(sound name: String, ruleGainDB: Double, saved: @escaping (String) -> Void) {", in: controller), 1)
        XCTAssertEqual(count("init(player: AlertPlayer, library: SoundLibrary) {", in: controller), 1)
        XCTAssertTrue(controller.contains("SoundEditorModel(soundName: name, ruleGainDB: ruleGainDB, library: library, player: player,"))
        XCTAssertTrue(controller.contains("onSaved: saved)"))
        XCTAssertTrue(controller.contains("Task { await model.open() }"))
        XCTAssertLessThan(try position(of: "window?.contentView = NSHostingView(", in: controller),
                          try position(of: "Task { await model.open() }", in: controller), "shown, then opened")
        XCTAssertEqual(count("@MainActor", in: controller), 1)
        XCTAssertEqual(count("@MainActor", in: try model()), 1)
    }

    func testTheModelHoldsWhatTheCoreDecidesAndMakesNoDecisionOfItsOwn() throws {
        let model = try model()
        for core in ["SoundTimeline(", "WaveformViewport(", "SoundRenderTickets()", "SoundEditorControls(", "SoundPreviewPlan.make(",
                     "WaveformKeys.apply(", "SoundEditorRendering.render(", "WaveformColumns.count(forWidth:"] {
            XCTAssertGreaterThanOrEqual(count(core, in: model), 1, core)
        }
        XCTAssertEqual(count("SoundRecipe(", in: model), 0, "no recipe is made or changed by the window: the history does it")
        XCTAssertEqual(count("SoundEditHistory(", in: model), 1, "the one history, made when the sound is opened (Task 8)")
        XCTAssertEqual(count("SoundEdit.", in: model), 0)
    }

    // MARK: - What a held key, a seek and a close come to

    func testAKeyThatRepeatsIsAnsweredOnlyWhereTheCoreSaysItTakesARepeat() throws {
        let handle = try body(of: "private func handle(_ press: KeyPress) -> KeyPress.Result {", in: try waveform())
        XCTAssertTrue(handle.contains("guard press.phase != .repeat || WaveformKeys.takesRepeat(key) else { return .handled }"),
                      "a repeat of Space is taken and does nothing, so it does not sound the alert beep either")
        XCTAssertLessThan(try position(of: "WaveformKeys.takesRepeat(key)", in: handle),
                          try position(of: "model.press(key", in: handle), "asked before the key is acted on")
    }

    func testLettingGoOfThePointerRestartsAPreviewOnlyWhenTheTimelineSaysThePressChangedSomething() throws {
        let up = try body(of: "func pointerUp(x: Double, width: Double) {", in: try model())
        XCTAssertTrue(up.contains("if timeline.pointerUp(at: viewport.frame(atX: x, width: width)) {"))
        XCTAssertTrue(up.contains("restartIfPreviewing(at: timeline.playhead)"))
        XCTAssertEqual(count("!=", in: up), 0, "a timeline held up to its own copy is never equal, for the press it ends is in it")
        XCTAssertEqual(count("let before", in: up), 0)
    }

    func testASeekToTheEndOfAPlayingPreviewEndsItThereAndOnlyTheCoreSaysWhenThatIs() throws {
        let restart = try body(of: "private func restartIfPreviewing(at frame: Int? = nil) {", in: try model())
        XCTAssertTrue(restart.contains("SoundPreviewPlan.endsPreview("))
        XCTAssertTrue(restart.contains("seekingTo: frame"))
        let ends = try position(of: "SoundPreviewPlan.endsPreview(", in: restart)
        XCTAssertLessThan(ends, try position(of: "play(resumingAt:", in: restart), "asked before it is played again")
        XCTAssertLessThan(try position(of: "stop()", in: restart), try position(of: "timeline.followPreview(frame)", in: restart),
                          "stopping leaves the playhead where the preview had got to, and the seek had put it at the end")
        XCTAssertEqual(count("player.stopTest()", in: try model()), 2, "stopping is still the one way")
    }

    func testClosingTheWindowLetsGoOfTheSoundAndWhatWasMadeOfIt() throws {
        let closed = try body(of: "func windowClosed() {", in: try model())
        for line in ["source = nil", "history = nil", "rendered = nil", "columns = nil"] {
            XCTAssertEqual(count(line, in: closed), 1, "\(line): the controller keeps the model after the window is closed")
        }
    }

    // MARK: - Nothing reaches it yet

    func testNothingInTheAppOpensTheWindowYetAndNoButtonOrMenuItemIsAddedForIt() throws {
        for file in try AppSources.fileNames() where !ownFiles.contains(file) {
            let source = try code(file)
            for name in ["SoundEditorWindowController", "SoundEditorModel", "SoundEditorView", "WaveformView",
                         "SoundEditorText", "WindowTitles.soundEditor"] {
                XCTAssertEqual(count(name, in: source), 0, "\(file) reaches \(name), which the way in (Task 9) adds")
            }
        }
    }
}
