import XCTest
@testable import NotificationCore

/// How the app target gathers what the first run reads, carries out what its buttons say, and
/// shows it (M5 plan, Task 8, Rulings 10, 16, 20 and 22): the store that saves its progress, the
/// coordinator that reads the facts and presses the buttons, and the window, its model and its
/// view, which show what they are handed and decide nothing.
///
/// The app target has no tests, and what the core cannot hold is the wiring: that the one
/// list of tokens is written by one place and nothing else touches the key, that the start
/// is recorded before the window is handed anything, that "Not now" and a closed window both
/// come to the one dismissal, that the last step's choice is saved by Settings' own function
/// and not by a second copy of the key, that a permission is asked for only by the press of
/// its button, that the first rule is made by calling the rule editor, that the guide reads
/// no clock, starts no timer and shows no alert, and that it gives the health alarm no input
/// and holds nothing back; and, of the window, that showing it records the start before
/// anything else, that every way it closes is a dismissal, that the rail shows and does not
/// act, that each line a step shows is the core's, in the core's order, and that the practice
/// line is never run or copied. Swap any of them and the app builds without a warning. So these
/// tests read the app's sources, as `SettingsWiringTests` and `ViewLiteralsTests` do, and
/// hold each place to what it is meant to say. They start nothing, call no system service,
/// show no window and read no preferences.
final class SetupWiringTests: XCTestCase {
    private func code(_ file: String) throws -> String {
        PowerHoldWiringTests.code(of: try XCTUnwrap(AppSources.read(file),
                                                    "\(file) cannot be read at \(AppSources.directory.path)"))
    }

    private func count(_ needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    private func body(of signature: String, in code: String) throws -> String {
        try XCTUnwrap(OnCallWiringTests.body(of: signature, in: code),
                      "\(signature) is not in the source exactly once, or is not closed")
    }

    private func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The text of every string literal a source holds, comments skipped: what the first run's
    /// files are held to none of.
    private func literals(in source: String) -> [String] {
        SwiftLiteralScanner.literals(in: source).map(\.text)
    }

    private func lines(_ lines: [String]) -> String {
        lines.joined(separator: "\n")
    }

    /// How many times these lines stand one directly after another, whole lines each, in
    /// `text`, which is code as `code(_:)` reads it.
    private func run(_ lines: [String], in text: String) -> Int {
        count("\n" + lines.joined(separator: "\n") + "\n", in: "\n" + text + "\n")
    }

    private let coordinatorFile = "SetupCoordinator.swift"
    private let storeFile = "SetupProgressStore.swift"

    private func coordinator() throws -> String { try code(coordinatorFile) }

    /// The signature of `press`, as the code reader leaves it: wrapped over two lines, and
    /// with no default for what the user picked or ticked, so a window that forgets to hand
    /// either over does not compile.
    private let pressSignature = [
        "func press(_ action: SetupText.ButtonAction, on step: SetupStep, app: String?,",
        "boxTicked: Bool) async -> String? {",
    ].joined(separator: "\n")

    /// The signature of the press itself, the one `switch` over the core's actions.
    private let performSignature = [
        "private func perform(_ action: SetupText.ButtonAction, on step: SetupStep, app: String?,",
        "boxTicked: Bool) async -> String? {",
    ].joined(separator: "\n")

    /// What `press` does around the press itself.
    private func press() throws -> String { try body(of: pressSignature, in: try coordinator()) }

    /// The arms of the press: one `case` for each of the core's actions.
    private func arms() throws -> String { try body(of: performSignature, in: try coordinator()) }

    // MARK: The files are there, and are held

    /// Both are named in the strict lists before they exist, so renaming one would take it
    /// out of every check without a failure. The coordinator is held as a new controller
    /// is, at the sites that show words, and here as well it holds no string literal at all:
    /// a sentence returned or stored is not a site the strict list looks at, and the
    /// coordinator says nothing of its own. The store holds none either; its key is the
    /// core's.
    func testTheCoordinatorAndTheStoreExistAndHoldNoWordAndNoLiteralOfTheirOwn() throws {
        XCTAssertTrue(HeldFiles.strictControllers.contains(coordinatorFile))
        for file in [coordinatorFile, storeFile] {
            let source = try XCTUnwrap(AppSources.read(file), "\(file) is gone")
            XCTAssertEqual(LiteralRules.violations(in: source, policy: .strictController), [], file)
            XCTAssertEqual(literals(in: source), [], "\(file) holds a string literal")
        }
    }

    /// The check above is what refuses a sentence typed into the coordinator and returned
    /// from it, which the strict list does not look at (it holds the sites that show words,
    /// and a returned sentence is not one). So the check itself is shown to refuse one: the
    /// coordinator as it is holds none, and the same source with a sentence typed where it
    /// hands back the rules file's failure holds that sentence, which the check above would
    /// report.
    func testAWordTypedIntoTheCoordinatorIsRefusedByTheCheckThatHoldsItToNone() throws {
        let source = try XCTUnwrap(AppSources.read(coordinatorFile))
        let anchor = "return sources.openRulesFile().map(SetupText.rulesFileNotOpened)"
        XCTAssertTrue(source.contains(anchor), "\(anchor) is where this test types a word")
        let typed = source.replacingOccurrences(of: anchor, with: "return \"The rules file did not open\"")
        XCTAssertNotEqual(typed, source)
        XCTAssertEqual(literals(in: source), [])
        XCTAssertEqual(literals(in: typed), ["The rules file did not open"])
    }

    // MARK: The key is written by one place

    /// The core's key names the one preferences value the first run keeps (Global
    /// Constraints), and only the store reads it or writes it. No other file names the key
    /// or the word it is saved under, and no file but the store holds the preferences for
    /// this.
    func testOnlyTheStoreNamesTheKeyTheTokensAreSavedUnder() throws {
        var found: [String] = []
        for file in try AppSources.fileNames() {
            let source = try code(file)
            if source.contains("SetupProgress.storageKey") || source.contains("setupProgress") { found.append(file) }
        }
        XCTAssertEqual(found, [storeFile])
        let store = try code(storeFile)
        XCTAssertEqual(count("SetupProgress.storageKey", in: store), 2, "read once, written once")
        XCTAssertFalse(store.contains("setupProgress"), "the word is the core's, and is not typed here")
    }

    func testTheStoreWritesTheWholeListInOnePlaceAndReadsTheValueAsItIs() throws {
        let store = try code(storeFile)
        let recorded = trimmed(try body(of: "func record(_ change: (inout SetupProgress) -> Void) {", in: store))
        XCTAssertEqual(recorded, lines([
            "change(&progress)",
            "defaults.set(progress.stored, forKey: SetupProgress.storageKey)",
        ]))
        XCTAssertEqual(count("defaults.set(", in: store), 1, "the tokens are written in one place")
        XCTAssertFalse(store.contains("removeObject"))
        XCTAssertFalse(store.contains("stringArray"), "a value that is not a list of strings is the core's to read")
        // Read once, when the store is made, as the core reads a value (`SetupProgress.init(storedValue:)`).
        XCTAssertEqual(count("SetupProgress(storedValue: defaults.object(forKey: SetupProgress.storageKey))", in: store), 1)
        XCTAssertEqual(count("SetupProgress(", in: store), 1)
        // What is recorded is the core's own methods, handed in by the caller, and not a
        // token typed here: the store names none.
        for word in ["started", "dismissed", "finished", "introductionSeen", "focusAttested", "skipped"] {
            XCTAssertFalse(store.contains(word), word)
        }
    }

    /// The one copy: nothing but the app delegate makes a store, and the coordinator is
    /// handed the one it records on.
    func testTheCoordinatorIsGivenTheOneStoreAndMakesNoneOfItsOwn() throws {
        for file in try AppSources.fileNames() where file != "AppDelegate.swift" {
            XCTAssertFalse(try code(file).contains("SetupProgressStore("), file)
        }
        XCTAssertLessThanOrEqual(count("SetupProgressStore(", in: try code("AppDelegate.swift")), 1)
        let source = try coordinator()
        XCTAssertEqual(count("private let progress: SetupProgressStore", in: source), 1)
        for word in ["UserDefaults", "defaults", "storageKey"] {
            XCTAssertFalse(source.contains(word), word)
        }
    }

    // MARK: The start is recorded first

    /// Recorded before anything else, and the facts the window is handed are gathered
    /// after it, so that what it shows already reads as begun. Nothing else records it.
    func testTheStartIsRecordedFirstOfAllWhenTheGuideIsShown() throws {
        let source = try coordinator()
        let shown = trimmed(try body(of: "func willShowGuide() -> SetupFacts {", in: source))
        XCTAssertEqual(shown, lines([
            "progress.record { $0.recordStarted() }",
            "return facts()",
        ]))
        XCTAssertEqual(count("recordStarted()", in: source), 1)
        for file in try AppSources.fileNames() where file != coordinatorFile {
            XCTAssertFalse(try code(file).contains("recordStarted"), file)
        }
    }

    // MARK: A dismissal

    /// "Not now" and closing the window are one act (O13), and each is the core's
    /// `recordDismissed()`, which records nothing for a guide that is finished. Neither asks
    /// whether it is, so the check stays in the core, where it is tested. The close that a quit
    /// makes is the core's to refuse (`SetupPlan.closeIsDismissal(appIsQuitting:)`), and the
    /// coordinator only carries out its answer.
    func testNotNowAndTheClosedWindowBothRecordTheDismissalThroughTheOneMethod() throws {
        let source = try coordinator()
        XCTAssertEqual(count("recordDismissed()", in: source), 1, "written in one place")
        let recorded = trimmed(try body(of: "private func recordDismissal() {", in: source))
        XCTAssertEqual(recorded, "progress.record { $0.recordDismissed() }")
        let closed = trimmed(try body(of: "func guideDidClose(appIsQuitting: Bool) {", in: source))
        XCTAssertEqual(closed, "if SetupPlan.closeIsDismissal(appIsQuitting: appIsQuitting) { recordDismissal() }")
        XCTAssertEqual(count("SetupPlan.closeIsDismissal(", in: source), 1, "the core says which closes are dismissals")
        XCTAssertEqual(run(["case .notNow:", "recordDismissal()", "return nil"], in: try arms()), 1)
        XCTAssertEqual(count("recordDismissal()", in: source), 3, "its declaration, the close and Not now")
        for file in try AppSources.fileNames() where file != coordinatorFile {
            XCTAssertFalse(try code(file).contains("recordDismissed"), file)
        }
    }

    func testNeitherADismissalNorAnythingElseAsksWhetherTheGuideIsFinished() throws {
        let source = try coordinator()
        for word in ["isFinished", "SetupPlan.standing", "hasStarted", "isDismissed", "opensAtLaunch", "Standing"] {
            XCTAssertFalse(source.contains(word), "\(word): what the progress means is the core's")
        }
        XCTAssertEqual(run(["case .finish:", "progress.record { $0.recordFinished() }", "return nil"], in: try arms()), 1)
        XCTAssertEqual(count("recordFinished()", in: source), 1)
    }

    // MARK: Each button

    /// Every action the core names has its own arm, and there is no default, so one added
    /// to the core has to be placed here, and one that is not placed does not compile.
    func testEveryButtonActionHasOneArmAndThereIsNoDefault() throws {
        let pressed = try arms()
        XCTAssertFalse(pressed.contains("default:"))
        XCTAssertFalse(pressed.contains("@unknown"))
        for action in SetupText.ButtonAction.allCases {
            XCTAssertEqual(count("\ncase .\(action):\n", in: "\n" + pressed + "\n"), 1, "\(action)")
        }
    }

    /// The records a button makes of its own are the core's methods, each for the one thing
    /// it says: the Focus is the user's word, and so is passing "Prove it can read".
    func testTheRecordsAButtonMakesAreTheCoresOwnMethodsForTheOneThingItSays() throws {
        let pressed = try arms()
        XCTAssertEqual(run(["case .confirmFocus:", "progress.record { $0.recordFocusAttested() }", "return nil"],
                           in: pressed), 1)
        XCTAssertEqual(run(["case .continueWithoutVerifying:", "progress.record { $0.recordSkipped(.proveItCanRead) }",
                            "return nil"], in: pressed), 1)
        XCTAssertEqual(run(["case .introductionSeen:", "progress.record { $0.recordIntroductionSeen() }", "return nil"],
                           in: pressed), 1)
        let source = try coordinator()
        XCTAssertEqual(count("recordFocusAttested()", in: source), 1)
        XCTAssertEqual(count("recordIntroductionSeen()", in: source), 1)
        XCTAssertEqual(count("recordSkipped(", in: source), 2, "passing the soft gate, and the last step's skip")
    }

    /// Continue is the core's: what it comes to by the step is `SetupPlan.continuing`, which
    /// the app reads and does not choose among, and Skip is what `SetupPlan.pressing` says.
    func testContinueAndSkipAreWhatTheCoreSaysTheyComeTo() throws {
        let pressed = try arms()
        XCTAssertEqual(run([
            "case .continueOn:",
            "switch SetupPlan.continuing(from: step, loginItem: settingsModel.state, boxTicked: boxTicked) {",
            "case .introductionSeen:",
            "progress.record { $0.recordIntroductionSeen() }",
            "return nil",
            "case .keepItRunning(let result):",
            "return carryOut(result)",
            "case .movesOn:",
            "return nil",
            "}",
            "case .skip:",
            "return carryOut(SetupPlan.pressing(.skipButton, state: settingsModel.state, boxTicked: boxTicked))",
        ], in: pressed), 1)
        let source = try coordinator()
        XCTAssertEqual(count("SetupPlan.continuing(", in: source), 1)
        XCTAssertEqual(count("SetupPlan.pressing(", in: source), 1)
        XCTAssertFalse(source.contains(".keepItRunning:"), "no case of the app's own for a step: the core says which")
        XCTAssertFalse(source.contains("switch step"))
    }

    // MARK: The last step

    /// What the last step's button saves, and what it asks the system for, are what
    /// `SetupPlan.pressing` answered, and Settings' model carries both out, by the one
    /// function that writes the choice and the one path that registers. The coordinator
    /// holds no key, no login item and no registration of its own.
    func testTheLastStepSavesAndRegistersThroughSettingsModelAndNoSecondCopyOfEither() throws {
        let source = try coordinator()
        let carried = trimmed(try body(of: "private func carryOut(_ result: SetupPlan.KeepItRunningResult) -> String? {",
                                       in: source))
        XCTAssertEqual(carried, lines([
            "if result.recordsSkip { progress.record { $0.recordSkipped(.keepItRunning) } }",
            "return settingsModel.perform(guidePress: result)",
        ]))
        for word in ["wantedKey", "launchAtLoginWanted", "wantedAfterPress", "saveChoice", "LoginItem.", "SMAppService",
                     "ServiceManagement", "register(", "LaunchAtLogin.request"] {
            XCTAssertFalse(source.contains(word), word)
        }
        // The Login Items pane is opened by Settings' own press.
        XCTAssertEqual(run(["case .openLoginItems:", "settingsModel.perform(.openLoginItems)", "return nil"],
                           in: try arms()), 1)
        // And the login item the facts show is what Settings shows.
        let facts = try body(of: "func facts() -> SetupFacts {", in: source)
        XCTAssertEqual(count("loginItem: settingsModel.state,", in: facts), 1)
    }

    // MARK: Permissions are asked for by their buttons only

    func testAPermissionIsAskedForOnlyByThePressOfItsButton() throws {
        let source = try coordinator()
        XCTAssertEqual(count("requestAccessibilityIfNeeded", in: source), 1)
        XCTAssertEqual(count("requestNotificationAuthorization", in: source), 1)
        let pressed = try arms()
        XCTAssertEqual(run(["case .allowAccessibility:", "_ = OnboardingCoordinator.requestAccessibilityIfNeeded()",
                            "return nil"], in: pressed), 1)
        XCTAssertEqual(run(["case .allowNotifications:", "_ = await OnboardingCoordinator.requestNotificationAuthorization()",
                            "return nil"], in: pressed), 1)
        // Not by gathering the facts, not by showing the guide, and not by anything but the press.
        for signature in ["func facts() -> SetupFacts {", "func willShowGuide() -> SetupFacts {",
                          "func guideDidClose(appIsQuitting: Bool) {"] {
            let made = try body(of: signature, in: source)
            XCTAssertFalse(made.contains("request"), signature)
            XCTAssertFalse(made.contains("OnboardingCoordinator"), signature)
        }
        XCTAssertFalse(source.contains("AXIsProcessTrustedWithOptions"))
        XCTAssertFalse(source.contains("kAXTrustedCheckOptionPrompt"))
        XCTAssertFalse(source.contains("UNUserNotificationCenter"))
        XCTAssertFalse(try code(storeFile).contains("OnboardingCoordinator"))
    }

    func testThePanesOfSystemSettingsAreOpenedByTheHelpersThatAlreadyOpenThem() throws {
        let pressed = try arms()
        XCTAssertEqual(run(["case .openAccessibilitySettings:", "OnboardingCoordinator.openAccessibilitySettings()",
                            "return nil"], in: pressed), 1)
        XCTAssertEqual(run(["case .openNotificationSettings:", "OnboardingCoordinator.openNotificationSettings()",
                            "return nil"], in: pressed), 1)
        XCTAssertEqual(run(["case .openKeyboardSettings:", "OnboardingCoordinator.openKeyboardSettings()",
                            "return nil"], in: pressed), 1)
        XCTAssertEqual(run(["case .openFocusSettings:", "NSWorkspace.shared.open(BundleResolver.focusSettingsURL)",
                            "return nil"], in: pressed), 1)
        // No address of the coordinator's own.
        let source = try coordinator()
        XCTAssertFalse(source.contains("URL(string"))
        XCTAssertFalse(source.contains("x-apple.systempreferences"))
    }

    // MARK: Checking again, and what is read

    /// Which presses are followed by a read of what the app reads from outside itself is the
    /// core's to say (`ButtonAction.readsAgain`, Ruling 10), and the coordinator reads it once,
    /// after the press, for whichever the core names. Whether that read first starts capture
    /// (`ButtonAction.startsCaptureIfTrusted`) and whether it asks for one self-test
    /// (`ButtonAction.runsSelfTest(on:)`: Check again on "Prove it can read") are the core's
    /// too, and the coordinator hands both answers to the read as they are. No arm reads again,
    /// starts capture or asks for a self-test of its own accord, so an arm added or changed
    /// cannot add a read, a start or a self-test the core did not decide, and Check again, whose
    /// whole act is the read, does nothing else.
    func testWhichPressesReadAgainStartCaptureAndAskForASelfTestIsTheCoresAndTheReadIsMadeOnceAfterThePress() throws {
        let source = try coordinator()
        XCTAssertEqual(trimmed(try press()), lines([
            "let sentence = await perform(action, on: step, app: app, boxTicked: boxTicked)",
            "if action.readsAgain { await sources.readAgain(action.startsCaptureIfTrusted, action.runsSelfTest(on: step)) }",
            "return sentence",
        ]))
        XCTAssertEqual(count("sources.readAgain(", in: source), 1, "one read, and it is the core's to ask for")
        XCTAssertEqual(count("readsAgain", in: source), 1)
        XCTAssertEqual(count("startsCaptureIfTrusted", in: source), 1, "the core's answer, handed over once")
        XCTAssertEqual(count("runsSelfTest(on: step)", in: source), 1, "the core's answer, handed over once")
        XCTAssertFalse(try arms().contains("runsSelfTest"), "no arm decides to run a self-test of its own accord")
        XCTAssertFalse(try arms().contains("startsCapture"), "no arm decides to start capture of its own accord")
        XCTAssertFalse(try arms().contains("startCapture"), "no arm decides to start capture of its own accord")
        for word in ["canary", "Canary", "refreshHealth", "capture.start", "startCaptureIfTrusted()"] {
            XCTAssertFalse(source.contains(word), "capture and the self-test are the app delegate's to run: \(word)")
        }
        XCTAssertFalse(try arms().contains("readAgain"), "no arm decides to read again of its own accord")
        XCTAssertEqual(run(["case .checkAgain:", "return nil"], in: try arms()), 1)
        XCTAssertEqual(count("perform(action,", in: source), 1, "the press is made once, by `press`")
    }

    /// Every fact the plan reads is read from the one place the app keeps it, once, and
    /// nothing is made up: the app delegate's four through `Sources`, the rules and the
    /// captures from the capture controller, the rules' status and the editor's reason from
    /// the rule store, the checklist from the shared store, the login item from Settings'
    /// model and what was recorded from the store of the tokens.
    func testEveryFactIsReadFromTheOnePlaceTheAppKeepsIt() throws {
        let source = try coordinator()
        let made = trimmed(try body(of: "func facts() -> SetupFacts {", in: source))
        XCTAssertEqual(made, lines([
            "let rules = capture.pipeline.rules",
            "let entries = capture.history.entries",
            "return SetupFacts(",
            "accessibilityTrusted: sources.accessibilityTrusted(),",
            "notifications: sources.delivery().map {",
            "SetupFacts.Notifications(permission: $0.permission, wouldDisplay: $0.wouldDisplay)",
            "},",
            "health: sources.health(),",
            "lastVerifiedAt: sources.lastVerifiedAt(),",
            "ruleStatus: ruleStore.status,",
            "ruleReach: RuleReach(rules: rules),",
            "rulesFileReadOnly: ruleStore.readOnlyReason,",
            "anythingCaptured: SetupCapture.anythingCaptured(in: entries),",
            "capturedAppNames: SetupCapture.appNames(in: entries),",
            "appsToMute: MuteWalkthrough.appsToMute(rules: rules, alsoSounded: capture.pipeline.appsThatAlerted),",
            "muteChecklist: muteChecklist.checklist,",
            "loginItem: settingsModel.state,",
            "progress: progress.progress)",
        ]))
        // The facts are gathered when asked and never kept: a copy would be stale.
        XCTAssertFalse(source.contains("private var"))
        XCTAssertFalse(source.contains("@Published"))
        XCTAssertFalse(source.contains("ObservableObject"))
    }

    /// The notification fact is nil until the first probe has answered, which is how the
    /// app delegate's own starts, and it is read as the probe answered: the coordinator
    /// does not give it a value of its own.
    func testTheNotificationFactIsNilUntilTheProbeAnsweredAndIsReadAsItAnswered() throws {
        let source = try coordinator()
        XCTAssertEqual(count("var delivery: () -> DeliveryStatus?", in: source), 1)
        XCTAssertEqual(count(".delivery()", in: source), 1)
        let app = try code("AppDelegate.swift")
        XCTAssertEqual(run(["private var delivery: DeliveryStatus?"], in: app), 1, "the app delegate's starts as nil")
    }

    /// The same checklist the menu and the on-call check read, never a second one.
    func testTheMuteIsRecordedInTheSharedChecklistAndTheCoordinatorMakesNoOtherCopy() throws {
        let source = try coordinator()
        XCTAssertEqual(run(["case .confirmMuted:", "guard let app else { return SetupText.pickAnAppFirst }",
                            "muteChecklist.setConfirmed(app, true)", "return nil"], in: try arms()), 1)
        XCTAssertEqual(count("private let muteChecklist: MuteChecklistStore", in: source), 1)
        for file in try AppSources.fileNames() where file != "AppDelegate.swift" {
            XCTAssertFalse(try code(file).contains("MuteChecklistStore("), file)
        }
        XCTAssertFalse(source.contains("MuteChecklist("), "a second checklist would be read once and never told of a tick")
        XCTAssertFalse(source.contains("MuteChecklist.storageKey"))
    }

    func testTheLookupOfAnAppsPageIsTheMenusAndItsSentenceIsHandedBackAndNeverAnAlert() throws {
        let source = try coordinator()
        XCTAssertEqual(run(["case .openAppNotificationSettings:", "guard let app else { return SetupText.pickAnAppFirst }",
                            "return openNotificationSettings(ofApp: app)"], in: try arms()), 1)
        let opened = trimmed(try body(of: "private func openNotificationSettings(ofApp app: String) -> String? {", in: source))
        XCTAssertEqual(opened, lines([
            "let resolution = BundleResolver.resolve(app, running: AppLocator.running(), installed: AppLocator.installed)",
            "NSWorkspace.shared.open(BundleResolver.notificationSettingsURL(for: resolution))",
            "return SetupText.muteLookupMessage(for: app, resolution: resolution)",
        ]))
    }

    func testTheRulesFileFailureIsHandedBackAsTheCoresSentenceAndTheCoordinatorOpensNoFileItself() throws {
        let source = try coordinator()
        XCTAssertEqual(run(["case .openRulesFile:", "return sources.openRulesFile().map(SetupText.rulesFileNotOpened)"],
                           in: try arms()), 1)
        for word in ["createExampleIfMissing", "activateFileViewerSelecting", "fileURL", "NSWorkspace.shared.open(ruleStore"] {
            XCTAssertFalse(source.contains(word), word)
        }
    }

    // MARK: The first rule

    /// The editor is called directly: the Inspector's hook for it is assigned only inside
    /// `showInspector()`, so the guide does not wait for that. The entry is the newest one
    /// the app the user picked was read from, which is the core's to find.
    func testTheFirstRuleIsMadeByCallingTheRuleEditorWithTheNewestEntryOfTheAppPicked() throws {
        let source = try coordinator()
        XCTAssertEqual(run(["case .makeRule:", "return makeRule(fromApp: app)"], in: try arms()), 1)
        let made = trimmed(try body(of: "private func makeRule(fromApp app: String?) -> String? {", in: source))
        XCTAssertEqual(made, lines([
            "guard let app else { return SetupText.pickAnAppFirst }",
            "guard let entry = SetupCapture.newestEntry(forApp: app, in: capture.history.entries) else {",
            "return SetupText.noBannerFromThatApp",
            "}",
            "ruleEditor.model.refreshCaptures(from: capture.history)",
            "ruleEditor.show(makingRuleFrom: entry)",
            "return nil",
        ]))
        XCTAssertEqual(count("ruleEditor.show(", in: source), 2, "the first rule's, and Edit Rules…'s (`FirstRuleWayOnWiringTests`)")
        for word in ["onMakeRule", "showInspector", "inspectorModel", "InspectorModel", "syncInspector"] {
            XCTAssertFalse(source.contains(word), word)
        }
        // And the hook is still assigned only where it was.
        let app = try code("AppDelegate.swift")
        XCTAssertEqual(count("inspectorModel.onMakeRule = ", in: app), 1)
        let inspector = try body(of: "@objc private func showInspector() {", in: app)
        XCTAssertEqual(count("inspectorModel.onMakeRule = ", in: inspector), 1)
    }

    /// A press about an app that can do nothing is not a press that did what it says, and is
    /// not handed back as one: it says so, in the core's words, beside the button (Ruling 22).
    /// What the user picked is handed in each time, with no default, so a window that forgets
    /// it gets a sentence and not a button that does nothing.
    func testAPressAboutAnAppThatCanDoNothingSaysSoInTheCoresWordsAndIsNeverSilent() throws {
        let source = try coordinator()
        XCTAssertEqual(count("SetupText.pickAnAppFirst", in: source), 3, "make a rule, confirm muted, open its settings")
        XCTAssertEqual(count("SetupText.noBannerFromThatApp", in: source), 1, "the banner has gone")
        XCTAssertFalse(source.contains("else { return }"), "a guard that gives up without a word")
        XCTAssertFalse(source.contains("if let app {"), "an act done only if an app was picked, and quiet if not")
        XCTAssertEqual(count(pressSignature, in: source), 1)
        XCTAssertEqual(count(performSignature, in: source), 1)
        XCTAssertFalse(source.contains("app: String? ="), "a default for the pick is a button that does nothing when it is forgotten")
        XCTAssertFalse(source.contains("boxTicked: Bool ="), "a default for the tick is a Continue that registers nothing when it is forgotten")
        // Said as the core says them, and made from nothing the app typed.
        XCTAssertEqual(literals(in: source), [])
    }

    // MARK: The rule store

    /// The first rule's step is blocked by the reason the editor would show, and the rule store
    /// makes it from the one read it has made of the file, with the status. If the success path
    /// lost its assignment, a file the editor must not touch would read as outstanding and the
    /// step would offer a button that does nothing; if it read the file again, the reason and
    /// the status could be from different files; and if the failure path lost its own, a file
    /// that cannot be opened would read as one the editor can edit.
    func testTheRuleStoreReadsTheEditorsReasonFromTheSameReadAsItsStatus() throws {
        let store = try code("RuleStore.swift")
        let reload = try body(of: "func reload() {", in: store)
        XCTAssertEqual(count("file.read()", in: reload), 1, "one read of the file, which the reason shares")
        XCTAssertEqual(run([
            "let snapshot = try file.read()",
            "fingerprint = snapshot.fingerprint",
            "read = RuleStoreStatus.load(snapshot.data, availableSounds: check.available,",
            "unplayable: check.unplayable, availableVoices: check.voices)",
            "readOnlyReason = RulesDocument.load(snapshot.data).readOnlyReason",
            "} catch {",
        ], in: reload), 1, "made from the snapshot the status was made from, as the editor reads a document")
        XCTAssertEqual(run([
            "} catch {",
            "fingerprint = nil",
            "read = ([], .unreadable(String(describing: error)))",
            "readOnlyReason = .unreadable(String(describing: error))",
            "}",
        ], in: reload), 1, "a file that cannot be opened is one the editor shows as unreadable")
        XCTAssertEqual(count("readOnlyReason =", in: store), 2, "assigned in these two places and nowhere else")
        XCTAssertEqual(count("RulesDocument.load(", in: store), 1)
    }

    /// What the app runs on after a reload is decided in the core, from what was read and
    /// what was running, so a file that cannot be used keeps the rules in effect
    /// (`RuleStoreStatus.reloaded`). The fingerprint stays the one the kept rules were read
    /// from, so the editor does not call the file it shows "in effect" when it is not, and
    /// the warnings are for the rules that run, which prepares their sounds again.
    func testTheRuleStoreKeepsTheRulesInEffectWhenTheFileCannotBeUsed() throws {
        let store = try code("RuleStore.swift")
        let reload = try body(of: "func reload() {", in: store)
        XCTAssertEqual(run([
            "(rules, status) = RuleStoreStatus.reloaded(read, replacing: rules)",
            "if !status.keepsEarlierRules { appliedFingerprint = fingerprint }",
            "warnings = RuleWarnings.warnings(for: rules, sounds: check)",
            "warmVoices()",
        ], in: reload), 1, "the rules, the status, the fingerprint and the warnings, in that order")
        XCTAssertTrue(trimmed(reload).hasSuffix("warmVoices()"), "and last, so nothing after them undoes them")
        XCTAssertEqual(count("(rules, status) =", in: store), 1, "the rules in effect are set in this one place")
        XCTAssertEqual(count("appliedFingerprint =", in: store), 1, "and the fingerprint beside them")
        XCTAssertEqual(count("warnings =", in: store), 1)
        XCTAssertEqual(count("status =", in: store), 0, "the status is set only with the rules")
    }

    // MARK: Words

    /// A moment is shown as the menu's other lines show one: the formatter is the app
    /// delegate's, handed over, and the coordinator makes none and reads no clock.
    func testTheWordsAreMadeFromTheFactsWithTheFormatterTheMenuUses() throws {
        let source = try coordinator()
        let words = trimmed(try body(of: "func words(for step: SetupStep, facts: SetupFacts) -> SetupText.StepWords {", in: source))
        XCTAssertEqual(words, "SetupText.words(for: step, facts: facts, time: sources.time)")
        let summary = trimmed(try body(of: "func summary(_ facts: SetupFacts) -> SetupText.Summary {", in: source))
        XCTAssertEqual(summary, "SetupText.summary(facts, time: sources.time)")
        XCTAssertEqual(count("sources.time", in: source), 2)
        XCTAssertFalse(source.contains("DateFormatter"))
        XCTAssertFalse(source.contains("dateFormat"))
        XCTAssertFalse(source.contains("ISO8601"))
        XCTAssertFalse(source.contains(".string(from"))
    }

    // MARK: No timer, no clock, no modal, and the alarm is not touched

    /// The guide is refreshed when the app is activated, when the menu opens, on Check
    /// again and from `syncInspector` (Ruling 20), which the caller asks. Nothing here
    /// waits, polls or reads the time, and no alert is shown or run (Ruling 22).
    func testTheCoordinatorAndTheStoreReadNoClockStartNoTimerAndShowNoAlert() throws {
        for file in [coordinatorFile, storeFile] {
            let source = try code(file)
            for word in ["Date()", "Date.now", "NSDate", "Calendar", "TimeZone", "DispatchTime", "CFAbsoluteTime",
                         "ProcessInfo", "systemUptime", "awakeTime", "Timer", "scheduledTimer", "RunLoop",
                         "DispatchQueue", "asyncAfter", "DispatchSource", "Task {", "Task(", "Task.sleep", "sleep(",
                         "NSAlert", "runModal", "beginSheetModal", "beginSheet", "NSApp.activate", "modalResponse",
                         "NSPanel", "NSOpenPanel", "NSSavePanel", "NSSound", "NSSound.beep"] {
                XCTAssertFalse(source.contains(word), "\(file): \(word)")
            }
        }
    }

    /// A beep that sounds over the first-run explanation is the lesser fault: the guide
    /// gives `HealthAlarmPlan` no input and holds nothing back (Ruling 10).
    func testTheGuideGivesTheHealthAlarmNoInputAndHoldsNothingBack() throws {
        for file in [coordinatorFile, storeFile] {
            let source = try code(file)
            for word in ["HealthAlarm", "alarm", "Alarm", "macWoke", "OnCallWatch", "OnCallCheck", "StatusGlyph",
                         "SnoozeController", "snooze", "escalations", "EscalationCoordinator", "PlayerOwnership"] {
                XCTAssertFalse(source.contains(word), "\(file): \(word)")
            }
        }
        // The health alarm is still given what it was: nothing of the guide.
        let alarm = try code("HealthAlarm.swift")
        for word in ["Setup", "guide", "Guide"] {
            XCTAssertFalse(alarm.contains(word), word)
        }
    }

    /// The coordinator is handed the app's one copy of each thing it reads and makes none
    /// of its own, so it cannot read a copy that is stale.
    func testTheCoordinatorIsHandedTheAppsOwnCopiesAndMakesNone() throws {
        let source = try coordinator()
        for word in ["CaptureController(", "RuleStore(", "SettingsModel(", "RuleEditorWindowController(",
                     "RuleEditorModel(", "MuteChecklistStore(", "SetupProgressStore(", "CanaryService",
                     "DeliveryStatusProbe", "HealthEvaluator", "AXIsProcessTrusted"] {
            XCTAssertFalse(source.contains(word), word)
        }
        for property in ["private let sources: Sources", "private let progress: SetupProgressStore",
                         "private let muteChecklist: MuteChecklistStore", "private let settingsModel: SettingsModel",
                         "private let ruleStore: RuleStore", "private let capture: CaptureController",
                         "private let ruleEditor: RuleEditorWindowController"] {
            XCTAssertEqual(count(property, in: source), 1, property)
        }
    }

    /// What only the app delegate holds comes through seven closures, none with a default,
    /// so a place that makes the sources and forgets one does not compile. The read-again
    /// closure is told whether to start capture first and whether to ask for one self-test,
    /// as the core says.
    func testTheSourcesAreSevenClosuresWithNoDefault() throws {
        let source = try coordinator()
        let sources = trimmed(try body(of: "struct Sources {", in: source))
        XCTAssertEqual(sources, lines([
            "var accessibilityTrusted: () -> Bool",
            "var delivery: () -> DeliveryStatus?",
            "var health: () -> CaptureHealth",
            "var lastVerifiedAt: () -> Date?",
            "var readAgain: (_ startCapture: Bool, _ runSelfTest: Bool) async -> Void",
            "var openRulesFile: () -> Error?",
            "var time: (Date) -> String",
        ]))
    }

    // MARK: - The window, its model and its view (commit 3 of Task 8)

    private let modelFile = "SetupModel.swift"
    private let viewFile = "SetupView.swift"
    private let controllerFile = "SetupWindowController.swift"

    private func model() throws -> String { try code(modelFile) }
    private func view() throws -> String { try code(viewFile) }
    private func controller() throws -> String { try code(controllerFile) }

    private func position(of needle: String, in text: String) throws -> String.Index {
        try XCTUnwrap(text.range(of: needle), "\(needle) is not there").lowerBound
    }

    /// Whether `text` writes `token` as a name of its own: not as the end of a longer one
    /// (`.accessibilityLabel(` is not a `Label(`) and not as the start of one (`.accessibilityHidden`
    /// is not the step `.accessibility`).
    private func names(_ token: String, in text: String) -> Bool {
        let pieces = text.components(separatedBy: token)
        func isNameCharacter(_ character: Character?) -> Bool {
            guard let character else { return false }
            return character.isLetter || character.isNumber || character == "_"
        }
        for index in pieces.indices.dropLast() {
            let before = pieces[index].last
            let after = pieces[index + 1].first
            let startsAName = token.first.map { $0.isLetter || $0.isNumber } ?? false
            let endsAName = token.last.map { $0.isLetter || $0.isNumber } ?? false
            if startsAName && isNameCharacter(before) { continue }
            if endsAName && isNameCharacter(after) { continue }
            return true
        }
        return false
    }

    /// The three files are named in the strict lists before they exist, so that renaming one
    /// would take it out of every check without a failure: here they are required. The view and
    /// the controller are held at the sites that show words, the model by a baseline of nothing,
    /// as Settings' model is, and each holds no string literal at all: a symbol is the core's
    /// (`SetupText.stateSymbol(for:)`) and so is the title, and a sentence handed back or stored is
    /// not a site the strict lists look at.
    func testTheWindowTheModelAndTheViewExistAreHeldAndHoldNoStringLiteralAtAll() throws {
        XCTAssertTrue(HeldFiles.strictViews.contains(viewFile))
        XCTAssertTrue(HeldFiles.strictControllers.contains(controllerFile))
        XCTAssertEqual(HeldFiles.baselineOthers.first { $0.file == modelFile }?.literals, [],
                       "the model is held by a baseline of nothing, as Settings' is")
        for file in [modelFile, viewFile, controllerFile] {
            let source = try XCTUnwrap(AppSources.read(file), "\(file) is gone")
            XCTAssertEqual(literals(in: source), [], "\(file) holds a string literal")
        }
        let view = try XCTUnwrap(AppSources.read(viewFile))
        let controller = try XCTUnwrap(AppSources.read(controllerFile))
        let model = try XCTUnwrap(AppSources.read(modelFile))
        XCTAssertEqual(LiteralRules.violations(in: view, policy: .strictView), [])
        XCTAssertEqual(LiteralRules.violations(in: controller, policy: .strictController), [])
        XCTAssertEqual(LiteralRules.violations(in: model, policy: .baseline([])), [])
    }

    /// The check above is what refuses a symbol typed into the view, which the strict list
    /// allows, and a sentence returned or stored in the model, which neither list looks at. It
    /// is shown to: each file as it is holds none, and the same source with one typed where the
    /// core's answer stands holds it.
    func testAWordOrASymbolTypedIntoAnyOfThemIsRefused() throws {
        let view = try XCTUnwrap(AppSources.read(viewFile))
        for (anchor, typed, word) in [
            ("Text(words.title)", "Text(\"A title of its own\")", "A title of its own"),
            ("Button(SetupText.label(for: .notNow))", "Button(\"Not now\")", "Not now"),
            ("Text(SetupText.stepPosition(of: words.step))", "Text(\"Step 3 of 8\")", "Step 3 of 8"),
            ("Image(systemName: SetupText.stateSymbol(for: reading.state))", "Image(systemName: \"checkmark\")", "checkmark"),
        ] {
            XCTAssertTrue(view.contains(anchor), "\(anchor) is where this test types a word")
            let added = view.replacingOccurrences(of: anchor, with: typed)
            XCTAssertEqual(literals(in: added), [word], word)
            if word != "checkmark" {
                XCTAssertEqual(LiteralRules.violations(in: added, policy: .strictView).map(\.text), [word], word)
            }
        }
        let controller = try XCTUnwrap(AppSources.read(controllerFile))
        let title = "window.title = WindowTitles.setupGuide"
        XCTAssertTrue(controller.contains(title))
        let typedTitle = controller.replacingOccurrences(of: title, with: "window.title = \"SignalLadder Setup Guide\"")
        XCTAssertEqual(LiteralRules.violations(in: typedTitle, policy: .strictController).map(\.text), ["SignalLadder Setup Guide"])
        let model = try XCTUnwrap(AppSources.read(modelFile))
        let assigned = "message = sentence"
        XCTAssertTrue(model.contains(assigned))
        let typedMessage = model.replacingOccurrences(of: assigned, with: "message = \"Nothing happened\"")
        XCTAssertEqual(LiteralRules.violations(in: typedMessage, policy: .baseline([])).map(\.text), ["Nothing happened"])
        XCTAssertEqual(literals(in: typedMessage), ["Nothing happened"])
    }

    // MARK: The window

    /// The start is recorded before anything else, and the facts the model is refreshed from are
    /// those the coordinator hands back after it, so that the first thing the window shows
    /// already reads as begun. The controller records nothing itself: the start is the
    /// coordinator's, once.
    func testShowingTheWindowRecordsTheStartBeforeAnythingElseAndRefreshesTheModelFromWhatThatReturns() throws {
        let source = try controller()
        let shown = trimmed(try body(of: "func show() {", in: source))
        XCTAssertTrue(shown.hasPrefix(lines([
            "let facts = coordinator.willShowGuide()",
            "model.refresh(from: facts)",
            "if window == nil {",
        ])), "the first statement of show() is the start being recorded")
        XCTAssertEqual(count("willShowGuide()", in: source), 1)
        XCTAssertEqual(count("model.refresh(from: facts)", in: shown), 1)
        XCTAssertFalse(shown.contains("coordinator.facts()"), "show() reads the facts the start returned, and none of its own")
        let started = try position(of: "coordinator.willShowGuide()", in: shown)
        let refreshed = try position(of: "model.refresh(from: facts)", in: shown)
        let made = try position(of: "if window == nil {", in: shown)
        let activated = try position(of: "NSApp.activate(ignoringOtherApps: true)", in: shown)
        let front = try position(of: "window?.makeKeyAndOrderFront(nil)", in: shown)
        XCTAssertLessThan(started, refreshed)
        XCTAssertLessThan(refreshed, made)
        XCTAssertLessThan(made, activated)
        XCTAssertLessThan(activated, front)
        for word in ["recordStarted", "recordDismissed", "progress", "UserDefaults", "defaults"] {
            XCTAssertFalse(source.contains(word), word)
        }
    }

    /// The window closes in every way through the one delegate call, and that call is the
    /// coordinator's `guideDidClose(appIsQuitting:)`, which is the dismissal "Not now" records
    /// unless the app is quitting, which the core says (`SetupPlan.closeIsDismissal`) and the
    /// controller only hands over. The close is never vetoed and the window is never merely
    /// ordered out, which would skip the call and lose the dismissal. Any close ends the visit,
    /// so the sentence a press handed back in it goes with it.
    func testEveryWayTheWindowClosesCallsTheCoordinatorsDismissalAndNoneAsksWhetherTheGuideIsFinished() throws {
        let source = try controller()
        XCTAssertEqual(count("final class SetupWindowController: NSObject, NSWindowDelegate {", in: source), 1)
        XCTAssertEqual(trimmed(try body(of: "func windowWillClose(_ notification: Notification) {", in: source)), lines([
            "coordinator.guideDidClose(appIsQuitting: appIsQuitting)",
            "model.windowDidClose()",
            "didClose()",
        ]))
        XCTAssertEqual(count("guideDidClose(", in: source), 1)
        XCTAssertEqual(count("windowDidClose()", in: source), 1)
        // Told after the record and the model's drop, and chosen from by no one here: the app delegate
        // reads Settings' line again, which a close changes.
        XCTAssertEqual(count("var didClose: () -> Void = {}", in: source), 1)
        XCTAssertEqual(count("didClose()", in: source), 1)
        XCTAssertEqual(count("windowWillClose", in: source), 1)
        XCTAssertEqual(count("window.delegate = self", in: source), 1)
        for word in ["windowShouldClose", "orderOut", "performClose", "isFinished", "SetupPlan.standing", "Standing"] {
            XCTAssertFalse(source.contains(word), "\(word): the close is the core's record and is not vetoed or skipped")
        }
        // The model closes it by the plain close, which sends the same call.
        XCTAssertEqual(count("model.closeWindow = { [weak self] in self?.window?.close() }", in: source), 1)
    }

    /// A quit closes every window AppKit still has open, after the notice that the app will
    /// terminate (measured on macOS 26.7.1, in a scratch program). The controller notes the
    /// notice and hands the coordinator whether the app is quitting, and chooses nothing of
    /// what that comes to: it never sets the flag any other way, and never reads it but to hand
    /// it over. The notice is heard with no queue, so that it has been heard before the close.
    func testTheQuitIsNotedBeforeTheWindowsAreClosedAndHandedOverAndNothingIsChosenFromIt() throws {
        let source = try controller()
        XCTAssertEqual(count("private var appIsQuitting = false", in: source), 1)
        XCTAssertEqual(count("appIsQuitting = true", in: source), 1, "set in the one place the notice is heard")
        XCTAssertEqual(count("appIsQuitting", in: source), 4, "its declaration, the notice, and the one hand-over: its name twice")
        XCTAssertEqual(run([
            "terminationObserver = NotificationCenter.default.addObserver(",
            "forName: NSApplication.willTerminateNotification, object: nil, queue: nil) { [weak self] _ in",
            "MainActor.assumeIsolated { self?.appIsQuitting = true }",
            "}",
        ], in: try body(of: "init(coordinator: SetupCoordinator) {", in: source)), 1)
        XCTAssertEqual(count("NotificationCenter", in: source), 1)
        XCTAssertEqual(count(".willTerminateNotification", in: source), 1)
        // The decision is the core's, and the app delegate has none of it to make.
        XCTAssertFalse(source.contains("closeIsDismissal"))
        XCTAssertFalse(source.contains("!appIsQuitting"))
        XCTAssertFalse(source.contains("if appIsQuitting"))
    }

    func testTheWindowIsOrdinaryTitledByWindowTitlesHeldOnceAndActivatedBeforeItIsOrderedFront() throws {
        let source = try controller()
        XCTAssertEqual(count("window.title = WindowTitles.setupGuide", in: source), 1)
        XCTAssertEqual(count("window.isReleasedWhenClosed = false", in: source), 1)
        XCTAssertEqual(count("window.contentView = NSHostingView(rootView: SetupView(model: model))", in: source), 1)
        XCTAssertEqual(count("if window == nil {", in: source), 1, "made once and held")
        XCTAssertEqual(count("self.window = window", in: source), 1)
        XCTAssertEqual(count("private var window: NSWindow?", in: source), 1)
        XCTAssertEqual(count("NSApp.activate(ignoringOtherApps: true)", in: source), 1, "an explicit activation, when shown")
        XCTAssertEqual(count("if window?.isMiniaturized == true { window?.deminiaturize(nil) }", in: source), 1)
        // The title is the core's, and one of the harness's constants.
        XCTAssertEqual(WindowTitles.setupGuide, "SignalLadder Setup Guide")
        // One window, and so one instance: the model is the controller's, made once, and the app
        // delegate makes at most the one controller.
        XCTAssertEqual(count("model = SetupModel(coordinator: coordinator)", in: source), 1)
        for file in try AppSources.fileNames() where file != controllerFile {
            XCTAssertFalse(try code(file).contains("SetupModel("), file)
        }
        XCTAssertLessThanOrEqual(count("SetupWindowController(", in: try code("AppDelegate.swift")), 1)
        for file in try AppSources.fileNames() where !["AppDelegate.swift", controllerFile].contains(file) {
            XCTAssertFalse(try code(file).contains("SetupWindowController("), file)
        }
    }

    /// What the window reports of itself, whether it is visible and whether it is minimised, is
    /// handed to the core, which says whether the nudge may count the guide as open (not while it
    /// is on the Dock, so that the line which leads back to it stays) and whether the window is
    /// worth keeping up to date (while it is minimised too). The controller combines the two
    /// facts in no way of its own. A read is made while it is kept up to date and never opens
    /// the window or records a start; it is made when the window comes to the front, which is how
    /// a grant made in System Settings, or a rule made in the editor, is seen when the user comes
    /// back, and when the app delegate asks.
    func testTheWindowIsReadAgainOnlyWhileKeptUpToDateAndWhenItComesToTheFront() throws {
        let source = try controller()
        XCTAssertEqual(trimmed(try body(of: "private var presence: SetupPlan.WindowPresence {", in: source)), lines([
            "SetupPlan.WindowPresence(isVisible: window?.isVisible ?? false,",
            "isMinimised: window?.isMiniaturized ?? false)",
        ]))
        XCTAssertEqual(count("var isOpenForTheNudge: Bool { presence.isOpenForTheNudge }", in: source), 1)
        XCTAssertEqual(count("isVisible", in: source), 2, "the window's report, and the core's name for it")
        XCTAssertEqual(count("isMiniaturized", in: source), 2, "the window's report, and the bringing forward of a window on the Dock")
        for word in ["isVisible ||", "isVisible &&", "isMiniaturized ||", "isMiniaturized &&", "!window", "var isOpen:"] {
            XCTAssertFalse(source.contains(word), "the core combines the two: \(word)")
        }
        XCTAssertEqual(trimmed(try body(of: "func refresh() {", in: source)), "refresh(from: coordinator.facts())")
        XCTAssertEqual(trimmed(try body(of: "func refresh(from facts: SetupFacts) {", in: source)), lines([
            "guard presence.isKeptUpToDate else { return }",
            "model.refresh(from: facts)",
        ]))
        XCTAssertEqual(trimmed(try body(of: "func windowDidBecomeKey(_ notification: Notification) {", in: source)), "refresh()")
        XCTAssertEqual(count("coordinator.facts()", in: source), 1, "facts are gathered in one place, and show() has its own from the start")
        for signature in ["func refresh() {", "func refresh(from facts: SetupFacts) {"] {
            let refreshed = try body(of: signature, in: source)
            for word in ["willShowGuide", "makeKeyAndOrderFront", "NSApp.activate", "NSWindow("] {
                XCTAssertFalse(refreshed.contains(word), "a read of a closed window opens nothing: \(word)")
            }
        }
    }

    /// No alert, no modal and no sheet, no timer and no clock, in any of the three files
    /// (Rulings 20 and 22): the guide's dialogs are text in its window, it is refreshed when asked,
    /// and it holds nothing back from the user and nothing from the alarm.
    func testNoneOfTheThreeFilesShowsAnAlertAModalOrASheetStartsATimerOrReadsAClock() throws {
        for file in [modelFile, viewFile, controllerFile] {
            let source = try code(file)
            for word in ["runModal", "NSAlert", "beginSheetModal", "beginSheet", "modalResponse", "NSPanel", "NSOpenPanel",
                         "NSSavePanel", ".alert(", ".sheet(", ".confirmationDialog(", ".popover(", ".fullScreenCover(",
                         "Timer", "scheduledTimer", "RunLoop", "DispatchQueue", "DispatchSource", "DispatchTime", "asyncAfter",
                         "Task.sleep", "sleep(", "Date()", "Date.now", "NSDate", "Calendar", "ProcessInfo", "systemUptime",
                         "NSSound", "AVAudio"] {
                XCTAssertFalse(source.contains(word), "\(file): \(word)")
            }
            // The guide gives the health alarm no input and holds nothing back (Ruling 10), and touches
            // nothing of on-call mode, snooze or the escalations.
            for word in ["HealthAlarm", "alarm", "Alarm", "OnCallWatch", "OnCallCheck", "StatusGlyph", "SnoozeController",
                         "EscalationCoordinator", "PlayerOwnership"] {
                XCTAssertFalse(source.contains(word), "\(file): \(word)")
            }
        }
    }

    // MARK: The model

    /// The model is made of the core's answers: the rail from the plan's evaluation, the step from
    /// the plan's choice (none is the summary), the words from the coordinator, which hands the
    /// core the facts and the menu's formatter, the box's tick from the core's rule for a read.
    /// It makes no decision of its own, and these lines are all of it that reads the facts.
    func testTheModelIsMadeOfTheCoresAnswersFromTheFactsItIsHanded() throws {
        let source = try model()
        XCTAssertEqual(trimmed(try body(of: "func refresh(from facts: SetupFacts) {", in: source)), lines([
            "let step = SetupPlan.current(facts)",
            "if step != current { message = nil }",
            "readings = SetupPlan.evaluate(facts)",
            "current = step",
            "words = step.map { coordinator.words(for: $0, facts: facts) }",
            "summary = step == nil ? coordinator.summary(facts) : nil",
            "muteChecklist = facts.muteChecklist",
            "let box = SetupPlan.loginItemBox(for: facts.loginItem)",
            "boxTicked = box.tickedAfterReading(wasShown: boxWasShown, wasTicked: boxTicked)",
            "boxWasShown = box.isShown",
        ]))
        for call in ["SetupPlan.current(", "SetupPlan.evaluate(", "SetupPlan.loginItemBox(", "SetupText.listedApp("] {
            XCTAssertEqual(count(call, in: source), 1, call)
        }
        // The rest of what it names of the plan and the core is a type its state is held in.
        XCTAssertEqual(count("SetupPlan.", in: source), 4, "the plan's choice, its evaluation and its box, and the type of the rail")
        XCTAssertEqual(count("SetupText.", in: source), 4, "the check of a pick, and the types of the words and of a press")
        XCTAssertFalse(source.contains("currentState"), "the state of the step shown is the rail's, and nothing reads it beside the title")
        XCTAssertEqual(trimmed(try body(of: "func isConfirmed(_ app: String) -> Bool {", in: source)),
                       "muteChecklist.isConfirmed(app)")
        // The facts are handed in and never kept, and the model reads nothing of the app itself.
        XCTAssertEqual(count("private let coordinator: SetupCoordinator", in: source), 1)
        XCTAssertFalse(source.contains("SetupCoordinator("))
        XCTAssertEqual(count("SetupFacts", in: source), 1, "named once, as the parameter of the read: the facts are handed in and never kept")
        for word in ["UserDefaults", "defaults", "SetupProgress", "recordDismissed", "recordFinished", "recordSkipped",
                     "SetupPlan.pressing", "SetupPlan.continuing", "LaunchAtLogin", "LoginItem", "settingsModel", "SettingsModel",
                     "OnboardingCoordinator", "NSWorkspace", "ruleEditor", "MuteChecklistStore", "setConfirmed", "CaptureController",
                     "AXIsProcessTrusted", "DeliveryStatus", "HealthEvaluator", "RuleStore"] {
            XCTAssertFalse(source.contains(word), word)
        }
    }

    /// The app the user picked is one of the step's list, checked against it each time it is used
    /// (`SetupText.listedApp`), so a press about an app is never about a name the list has lost.
    /// The pick is kept for each step, so one made in a step is not carried into another.
    func testAPickIsKeptForTheStepItWasMadeInAndCheckedAgainstTheListWhenUsed() throws {
        let source = try model()
        XCTAssertEqual(trimmed(try body(of: "var pickedApp: String? {", in: source)), lines([
            "guard let current else { return nil }",
            "return SetupText.listedApp(picks[current], among: words?.apps ?? [])",
        ]))
        XCTAssertEqual(trimmed(try body(of: "func pick(_ app: String?) {", in: source)), lines([
            "guard let current else { return }",
            "if picks[current] != app { message = nil }",
            "picks[current] = app",
        ]), "a different pick takes away the sentence that was about the one before")
        XCTAssertEqual(count("picks[", in: source), 3)
        // The picks outlast a close, as they outlast any read: a name no longer listed is no pick.
        XCTAssertEqual(trimmed(try body(of: "func windowDidClose() {", in: source)), "message = nil",
                       "a close ends the visit, and with it the sentence a press handed back in it; the picks stay")
        XCTAssertEqual(count("@Published private var picks: [SetupStep: String] = [:]", in: source), 1)
        XCTAssertEqual(count("SetupText.listedApp(", in: source), 1)
        XCTAssertEqual(count("app: pickedApp,", in: source), 1, "a press is handed the checked pick and no other")
    }

    /// A press is carried out once at a time, by the coordinator, with what the user picked and
    /// ticked, and is followed by a read of what is so. The window closes when the core says so, and
    /// not otherwise. The sentence it handed back is shown, and the step it was said on is the one
    /// it stands on.
    func testAPressIsCarriedOutOnceAtATimeByTheCoordinatorAndFollowedByAReadOfWhatIsSo() throws {
        let source = try model()
        XCTAssertEqual(trimmed(try body(of: "func press(_ action: SetupText.ButtonAction) async {", in: source)), lines([
            "guard !isPressing else { return }",
            "isPressing = true",
            "let sentence = await coordinator.press(action, on: current ?? .keepItRunning, app: pickedApp,",
            "boxTicked: boxTicked)",
            "isPressing = false",
            "message = sentence",
            "refresh(from: coordinator.facts())",
            "if action.closesWindow { closeWindow() }",
        ]))
        XCTAssertEqual(count("coordinator.press(", in: source), 1)
        XCTAssertEqual(count("coordinator.facts()", in: source), 1, "the facts are asked for after a press, and nowhere else")
        XCTAssertEqual(count("closeWindow()", in: source), 1)
        XCTAssertEqual(count("var closeWindow: () -> Void = {}", in: source), 1)
        XCTAssertEqual(count("message =", in: source), 4,
                       "what the press handed back, and its going when the step changes, the pick does or the window closes")
        // The summary follows the last step and has one button, Finish, which is asked of no step.
        XCTAssertEqual(SetupStep.allCases.last, .keepItRunning)
        XCTAssertEqual(count(".keepItRunning", in: source), 1)
    }

    // MARK: The view

    /// A step is shown in the order the core gives it: its place and title, what it says before it
    /// asks, what it rests on, what it has read, the lines under that, the practice line to select,
    /// the apps to pick from, the last step's box and its buttons, with the sentence the last press
    /// handed back beside them. The view makes none of these and shows what it is handed.
    func testAStepIsShownInTheOrderTheCoreGivesItAndTheSummaryReplacesIt() throws {
        let source = try view()
        let step = try body(of: "private func stepView(_ words: SetupText.StepWords) -> some View {", in: source)
        let inOrder = try [
            "Text(SetupText.stepPosition(of: words.step))",
            "Text(words.title)",
            "paragraphs(words.why)",
            "Text(words.status)",
            "paragraphs(words.detail)",
            "if let line = words.selectable {",
            "practiceLine(line)",
            "if !words.apps.isEmpty {",
            "appList(words)",
            "if let label = words.tickBox {",
            "Toggle(label, isOn: $model.boxTicked)",
            "buttons(words.buttons)",
            "pressMessage",
        ].map { try position(of: $0, in: step) }
        XCTAssertEqual(inOrder, inOrder.sorted())
        XCTAssertEqual(run(["buttons(words.buttons)", "pressMessage"], in: step), 1)
        // The step shown is never a done one (`SetupPlan.current` passes over those), so it has no basis to
        // say: a done step says what it rests on in the rail's label and to VoiceOver, and the summary under
        // its headings, and a line here could never be drawn.
        XCTAssertFalse(source.contains("basis"), "what a done step rests on is not the large step's to say")
        // The summary takes the step's place, with no row of its own in the rail: it is shown when the
        // model holds no words, and the rail lists the plan's readings alone.
        XCTAssertEqual(trimmed(try body(of: "private var content: some View {", in: source)), lines([
            "if let words = model.words {",
            "stepView(words)",
            "} else if let summary = model.summary {",
            "summaryView(summary)",
            "}",
        ]))
        let summary = try body(of: "private func summaryView(_ summary: SetupText.Summary) -> some View {", in: source)
        let summaryOrder = try [
            "Text(summary.title)", "Text(summary.readHeading)", "paragraphs(summary.read)", "Text(summary.wordHeading)",
            "paragraphs(summary.word)", "paragraphs([summary.onCall, summary.snooze])", "buttons(summary.buttons)", "pressMessage",
        ].map { try position(of: $0, in: summary) }
        XCTAssertEqual(summaryOrder, summaryOrder.sorted())
        XCTAssertEqual(run(["buttons(summary.buttons)", "pressMessage"], in: summary), 1)
        let rail = try body(of: "private var rail: some View {", in: source)
        XCTAssertFalse(rail.contains("summary"))
        XCTAssertEqual(count("ForEach(model.readings, id: \\.step) { reading in", in: rail), 1)
    }

    /// The rail shows where the user is and does nothing: no row is a button or takes a tap, a
    /// hover or a gesture, and nothing in the view navigates. A row is read by VoiceOver as its place
    /// and title with its state as the value, since its symbol is not read.
    func testTheRailShowsEachStepsStateAndIsNotClickable() throws {
        let source = try view()
        let rail = try body(of: "private var rail: some View {", in: source)
        let row = try body(of: "private func railRow(_ reading: SetupPlan.Reading) -> some View {", in: source)
        for part in [rail, row] {
            for word in ["Button(", "onTapGesture", "onHover", "gesture", "Gesture", "NavigationLink", "onSelect", "selection:",
                         "onChange", "Task", "model.press", "model.pick"] {
                XCTAssertFalse(part.contains(word), word)
            }
        }
        for word in ["onTapGesture", "NavigationLink", "onSelect"] {
            XCTAssertFalse(source.contains(word), word)
        }
        XCTAssertEqual(count("Image(systemName: SetupText.stateSymbol(for: reading.state))", in: row), 1)
        XCTAssertEqual(count(".accessibilityHidden(true)", in: row), 1, "the symbol is not read out; the row is")
        XCTAssertEqual(count("Text(SetupText.title(for: reading.step))", in: row), 1)
        XCTAssertEqual(count("Text(SetupText.stateLabel(for: reading.state))", in: row), 1, "the state is also said in words")
        XCTAssertEqual(count(".accessibilityLabel(SetupText.railRowLabel(for: reading.step))", in: row), 1)
        XCTAssertEqual(count(".accessibilityValue(SetupText.stateDescription(for: reading.state))", in: row), 1)
        XCTAssertEqual(count("let isCurrent = reading.step == model.current", in: row), 1, "it is marked where the plan has the user")
        XCTAssertEqual(count("Text(SetupText.railHeading)", in: rail), 1)
        XCTAssertEqual(count(".accessibilityLabel(SetupText.railHeading)", in: rail), 1, "the list is called what the heading says")
        XCTAssertEqual(count("Image(systemName:", in: source), 1, "the one symbol the view draws, and it is the core's")
        XCTAssertFalse(source.contains("systemImage:"))
        XCTAssertFalse(names("Label(", in: source), "a Label carries a symbol and words of its own")
    }

    /// "Not now" is the window's own button and is shown where the core says: on every step, and not
    /// on the summary, where Finish is. The view names neither Finish nor any step's button of its
    /// own, and "Not now" only in the footer, whose press is the model's like any other.
    func testNotNowIsShownWhereTheCoreSaysAndFinishIsTheSummarysOwnButton() throws {
        let source = try view()
        XCTAssertEqual(count("SetupText.windowShowsNotNow(on: model.current)", in: source), 1)
        XCTAssertEqual(run(["if SetupText.windowShowsNotNow(on: model.current) {", "Divider()", "footer", "}"], in: source), 1)
        XCTAssertEqual(trimmed(try body(of: "private var footer: some View {", in: source)), lines([
            "HStack {",
            "Spacer()",
            "Button(SetupText.label(for: .notNow)) {",
            "Task { await model.press(.notNow) }",
            "}",
            ".disabled(model.isPressing)",
            "}",
            ".padding(12)",
        ]))
        XCTAssertEqual(count(".notNow", in: source), 2, "its label and its press, both in the footer")
        XCTAssertFalse(source.contains(".finish"), "Finish is the summary's button, and the core's")
        XCTAssertEqual(count("Button(", in: source), 2, "the core's buttons and \"Not now\", so none does nothing")
        XCTAssertFalse(source.contains(".continueOn"))
        XCTAssertFalse(source.contains(".skip"))
        XCTAssertFalse(source.contains(".checkAgain"))
    }

    /// The buttons are the core's, in the core's order, and each press is the model's. All are off
    /// while one is being carried out, with a spinner beside them, so a second cannot start beside it.
    /// None is the window's default button: the window opens by itself, and a Return meant for
    /// something else must not ask macOS for a permission or change the user's login items.
    func testTheButtonsAreTheCoresInTheCoresOrderAndAPressIsTheModels() throws {
        let source = try view()
        XCTAssertEqual(trimmed(try body(of: "private func buttonRow(_ buttons: [SetupText.StepButton]) -> some View {", in: source)),
                       lines([
                        "ForEach(buttons, id: \\.action) { button in",
                        "Button(button.label) {",
                        "Task { await model.press(button.action) }",
                        "}",
                        "}",
                        "if model.isPressing {",
                        "ProgressView().controlSize(.small)",
                        "}",
                       ]))
        XCTAssertEqual(count(".disabled(model.isPressing)", in: source), 2, "the buttons and \"Not now\"")
        XCTAssertEqual(count("buttonRow(buttons)", in: source), 2, "on a line if they fit and one above the other if not")
        for word in ["keyboardShortcut", "defaultAction", "cancelAction", "borderedProminent"] {
            XCTAssertFalse(source.contains(word), word)
        }
        XCTAssertEqual(count("model.press(", in: source), 2)
    }

    /// The practice line is text to select, and the app neither runs it nor copies it (Ruling 16):
    /// there is no button for either, no pasteboard and no script in any of the three files.
    func testThePracticeLineIsTextToSelectAndNeverRunOrCopied() throws {
        let source = try view()
        XCTAssertEqual(trimmed(try body(of: "private func practiceLine(_ line: String) -> some View {", in: source)), lines([
            "Text(line)",
            ".font(.system(.body, design: .monospaced))",
            ".textSelection(.enabled)",
            ".fixedSize(horizontal: false, vertical: true)",
            ".padding(10)",
            ".frame(maxWidth: .infinity, alignment: .leading)",
            ".background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))",
            ".accessibilityLabel(SetupText.practiceCommandLabel)",
            ".accessibilityValue(line)",
        ]))
        XCTAssertEqual(count(".textSelection(.enabled)", in: source), 1)
        for file in [modelFile, viewFile, controllerFile] {
            let all = try code(file)
            for word in ["NSPasteboard", "setString", "declareTypes", "writeObjects", "copy(", "Process", "NSTask", "NSAppleScript",
                         "osascript", "/usr/bin", "contextMenu", "ShareLink", "Pasteboard"] {
                XCTAssertFalse(all.contains(word), "\(file): \(word)")
            }
        }
    }

    /// A step's apps are a list to pick one from, and its buttons act on the pick. Each row is the
    /// core's, worded for the step it is in (`SetupText.appRow`): the view hands over the step and
    /// whether the user has confirmed the app, shows the text and gives VoiceOver the label, and
    /// names no step of its own, so which wording a step's rows have is not decided here.
    func testTheAppListIsAPickOneListWhoseRowsAreReadAsTheCoreSays() throws {
        let source = try view()
        XCTAssertEqual(count("List(words.apps, id: \\.self, selection: Binding(get: { model.pickedApp }, set: { model.pick($0) })) { app in",
                             in: source), 1)
        XCTAssertEqual(count("Text(heading)", in: try body(of: "private func appList(_ words: SetupText.StepWords) -> some View {", in: source)), 1)
        XCTAssertEqual(count("SetupText.appListHeading(for: words.step)", in: source), 1)
        XCTAssertEqual(trimmed(try body(of: "private func appRow(_ app: String, on step: SetupStep) -> some View {", in: source)), lines([
            "let row = SetupText.appRow(app, on: step, confirmed: model.isConfirmed(app))",
            "return Text(row.text)",
            ".accessibilityLabel(row.voiceOver)",
        ]))
        XCTAssertEqual(count("SetupText.appRow(", in: source), 1)
        XCTAssertEqual(count("appRow(app, on: words.step)", in: source), 1, "the step is handed over as a value")
        // No step is named, the mute step's included: what each step is, says and offers is the core's.
        for step in SetupStep.allCases {
            XCTAssertFalse(names(".\(step.rawValue)", in: source), "\(step)")
        }
        for word in ["ruleAppRowLabel", "muteAppRowLabel", "== .", "!= ."] {
            XCTAssertFalse(source.contains(word), "the choice of wording is the core's: \(word)")
        }
    }

    /// The last step's box is shown where the core says (the words hold a label for it only then),
    /// and its tick is the model's.
    func testTheBoxIsShownOnlyWhereTheWordsHoldItsLabelAndItsTickIsTheModels() throws {
        let source = try view()
        XCTAssertEqual(run(["if let label = words.tickBox {", "Toggle(label, isOn: $model.boxTicked)", "}"], in: source), 1)
        XCTAssertEqual(count("Toggle(", in: source), 1)
    }

    /// What the last press handed back stands beside the buttons it came from, on a step and on the
    /// summary alike, and is shown as it was given.
    func testWhatThePressHandedBackIsShownBesideTheButtonsAsItWasGiven() throws {
        let source = try view()
        XCTAssertEqual(trimmed(try body(of: "private var pressMessage: some View {", in: source)), lines([
            "if let message = model.message {",
            "Text(message)",
            ".font(.callout)",
            ".fixedSize(horizontal: false, vertical: true)",
            "}",
        ]))
        XCTAssertEqual(count("pressMessage", in: source), 3, "its declaration, a step's and the summary's")
        // The coordinator hands back the core's sentence for each of the four it can, which is why the
        // scan of the labels looks for them there (`SetupTextTests`).
        let handedBack = try coordinator()
        for reference in ["SetupText.muteLookupMessage(", "SetupText.rulesFileNotOpened", "SetupText.pickAnAppFirst",
                          "SetupText.noBannerFromThatApp"] {
            XCTAssertTrue(handedBack.contains(reference), reference)
        }
    }

    /// The view and the model take what they show from the coordinator and the core. Nothing but the
    /// controller makes the view, and nothing but the app delegate will make the controller.
    func testTheViewIsMadeByTheControllerAloneAndNamesNoFactOfTheApp() throws {
        for file in try AppSources.fileNames() where !["SetupWindowController.swift", viewFile].contains(file) {
            XCTAssertFalse(try code(file).contains("SetupView("), file)
        }
        let source = try view()
        XCTAssertEqual(count("@ObservedObject var model: SetupModel", in: source), 1)
        for word in ["SetupFacts", "SetupCoordinator", "UserDefaults", "AXIsProcessTrusted", "DeliveryStatus", "RuleStore",
                     "MuteChecklistStore", "NSWorkspace", "OnboardingCoordinator", "LaunchAtLogin", "SetupProgress"] {
            XCTAssertFalse(source.contains(word), word)
        }
    }

    // MARK: - The app delegate (commit 4 of Task 8)

    private func app() throws -> String { try code("AppDelegate.swift") }

    private func launch() throws -> String {
        try body(of: "func applicationDidFinishLaunching(_ notification: Notification) {", in: try app())
    }

    /// The guide is made once, by the app delegate, from the app's own copy of each thing: one store of
    /// the tokens, one coordinator whose sources are the delegate's own state read when asked, and one
    /// window. Each source is handed as a closure with no default, so a source forgotten does not
    /// compile (`testTheSourcesAreSevenClosuresWithNoDefault`), and these are the seven, as they are
    /// read: Accessibility live, the probe's last answer (nil until it has answered), health, when a
    /// self-test last succeeded, the read for Check again, the rules file's opener that hands its
    /// failure back, and the menu's own clock. When the window closes the delegate is told.
    func testTheAppDelegateMakesTheStoreTheCoordinatorAndTheWindowOnceFromItsOwnState() throws {
        let source = try app()
        for made in ["SetupProgressStore(", "SetupCoordinator(", "SetupCoordinator.Sources(", "SetupWindowController("] {
            XCTAssertEqual(count(made, in: source), 1, made)
        }
        XCTAssertEqual(count("private let setupStore = SetupProgressStore()", in: source), 1)
        XCTAssertEqual(run([
            "private lazy var setupCoordinator: SetupCoordinator = SetupCoordinator(",
            "sources: SetupCoordinator.Sources(",
            "accessibilityTrusted: { AXIsProcessTrusted() },",
            "delivery: { [weak self] in self?.delivery },",
            "health: { [weak self] in self?.health ?? .unknown },",
            "lastVerifiedAt: { [weak self] in self?.lastCanarySucceededAt },",
            "readAgain: { [weak self] startCapture, runSelfTest in",
            "await self?.readAgain(startCapture: startCapture, runSelfTest: runSelfTest)",
            "},",
            "openRulesFile: { [weak self] in self?.openRulesFile() },",
            "time: { AppDelegate.clock.string(from: $0) }),",
            "progress: setupStore, muteChecklist: muteChecklist, settingsModel: settingsModel,",
            "ruleStore: ruleStore, capture: capture, ruleEditor: ruleEditor)",
        ], in: source), 1)
        XCTAssertEqual(run([
            "private lazy var setupWindow: SetupWindowController = {",
            "let controller = SetupWindowController(coordinator: setupCoordinator)",
            "controller.didClose = { [weak self] in self?.refreshSetup() }",
            "return controller",
            "}()",
        ], in: source), 1)
        // The copies it is handed are the app's one copy of each, which the rest of the app reads.
        for once in ["MuteChecklistStore(", "SettingsModel(", "RuleStore(", "CaptureController(", "RuleEditorWindowController("] {
            XCTAssertEqual(count(once, in: source), 1, once)
        }
        // The clock is the menu's own, and the delegate makes no second one for the guide.
        XCTAssertEqual(count("DateFormatter()", in: source), 1)
        // Nothing but the delegate reaches the store, the coordinator or the window.
        for file in try AppSources.fileNames() where file != "AppDelegate.swift" {
            let other = try code(file)
            XCTAssertFalse(other.contains("setupCoordinator"), file)
            XCTAssertFalse(other.contains("setupWindow"), file)
            XCTAssertFalse(other.contains("setupStore"), file)
        }
    }

    /// The plan reads the rules and has no "not read yet" for them (`SetupFacts.ruleStatus`), so nothing
    /// may build a menu, gather a fact or ask the plan until `reloadRules()` has run once at launch, or
    /// a configured upgrader would be shown a nudge that says a first rule is still to do. Making the
    /// status item builds no menu: the first is the one `reloadRules()` ends in, once the rules it has
    /// loaded are in effect. Launch itself builds none, calls nothing of the guide before the reload, and
    /// gathers the facts it asks the plan about after it. Everything else that reaches a build before
    /// the reload is a closure that capture, a timer or the main queue runs, none of which runs until
    /// launch has returned.
    func testTheRulesAreLoadedBeforeAnythingBuildsAMenuGathersAFactOrAsksThePlan() throws {
        let source = try app()
        let launch = try launch()
        XCTAssertEqual(trimmed(try body(of: "private func setUpStatusItem() {", in: source)), lines([
            "let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)",
            "let menu = NSMenu()",
            "menu.delegate = self",
            "item.menu = menu",
            "statusItem = item",
        ]), "makes the item and its menu, and builds nothing in it")
        XCTAssertFalse(launch.contains("rebuildMenu"), "launch builds no menu of its own")
        XCTAssertFalse(launch.contains("syncInspector"))
        XCTAssertFalse(launch.contains("refreshSetup"))
        XCTAssertFalse(launch.contains("takeSetupFacts"), "Settings' line is first made by the reload's own rebuild, from loaded rules")

        let reload = try body(of: "private func reloadRules() {", in: source)
        XCTAssertEqual(run(["ruleStore.reload()", "capture.pipeline.setRules(ruleStore.rules)"], in: reload), 1,
                       "the rules are in effect before anything is built from them")
        XCTAssertTrue(trimmed(reload).hasSuffix("rebuildMenu()"), "and the first menu is the last thing the reload does")
        XCTAssertLessThan(try position(of: "ruleStore.reload()", in: reload), try position(of: "rebuildMenu()", in: reload))

        let item = try position(of: "setUpStatusItem()", in: launch)
        let loaded = try position(of: "reloadRules()", in: launch)
        XCTAssertLessThan(item, loaded)
        let between = String(launch[item..<loaded])
        for word in ["setupCoordinator", "setupWindow", "showSetupGuide", "SetupPlan", "facts", "nudge", "Nudge"] {
            XCTAssertFalse(between.contains(word), "nothing of the guide is touched between the status item and the reload: \(word)")
        }
        // The facts launch asks the plan about are gathered once, after the reload, and nothing of the
        // guide is shown before they are.
        XCTAssertEqual(count("setupCoordinator.facts()", in: launch), 1)
        XCTAssertLessThan(loaded, try position(of: "setupCoordinator.facts()", in: launch))
        XCTAssertEqual(count("showSetupGuide()", in: launch), 2, "the Setup group's door, set before the reload and not called, and the launch decision, after it")
        XCTAssertLessThan(try position(of: "settingsModel.openGuide = ", in: launch), loaded,
                          "set before the reload, where nothing yet calls it: only the user's press of the button does")
        XCTAssertLessThan(loaded, try position(of: "if opensAtLaunch { showSetupGuide() }", in: launch))

        // The three places that gather facts: launch, after the reload; the nudge, in a menu build; and the
        // refresh, which every moment but launch's own calls.
        XCTAssertEqual(count("setupCoordinator.facts()", in: source), 4, "and the reopen's choice of window")
        // Capture and the main queue are what reach a build before the reload could, and both are
        // closures: starting capture assigns them and starts the watcher, and a change to the snooze asks
        // for its redraw on the next turn of the main queue.
        let started = try body(of: "private func startCaptureIfTrusted() -> Bool {", in: source)
        XCTAssertEqual(count("capture.onChange = { [weak self] in self?.rebuildMenu() }", in: started), 1)
        XCTAssertEqual(count("rebuildMenu(", in: started), 1, "only in that closure")
        XCTAssertEqual(trimmed(try body(of: "private func snoozeChanged() {", in: source)), lines([
            "DispatchQueue.main.async { [weak self] in",
            "MainActor.assumeIsolated { self?.rebuildMenu() }",
            "}",
        ]))
    }

    /// The plan is asked whether the guide opens and whether the launch prompts are kept, before either
    /// prompt, and each prompt is called under the answer for both and under nothing else: Accessibility
    /// at launch and the request for notifications in the task that follows. When the guide opens it
    /// owns both. The probe and the health refresh are not under the answer, and run either way, and the
    /// notification fact is nil until the first probe has answered.
    func testTheLaunchDecisionsAreAskedBeforeThePromptsAndEachPromptIsCalledOnlyUnderTheAnswer() throws {
        let source = try app()
        let launch = try launch()
        XCTAssertEqual(run([
            "let launchFacts = setupCoordinator.facts()",
            "let promptsAtLaunch = SetupPlan.promptsAtLaunch(launchFacts)",
            "let opensAtLaunch = SetupPlan.opensAtLaunch(launchFacts)",
            "if promptsAtLaunch { _ = OnboardingCoordinator.requestAccessibilityIfNeeded() }",
            "if opensAtLaunch { showSetupGuide() }",
        ], in: launch), 1)
        XCTAssertEqual(run([
            "Task { @MainActor in",
            "if promptsAtLaunch { _ = await OnboardingCoordinator.requestNotificationAuthorization() }",
            "startCaptureIfTrusted()",
            "await refreshHealthAndFollowUp()",
            "}",
        ], in: launch), 1, "the prompt is under the answer; the capture and the health refresh are not")
        // Each prompt is called once in the whole delegate, there, and the plan's two answers are asked once.
        XCTAssertEqual(count("OnboardingCoordinator.requestAccessibilityIfNeeded()", in: source), 1)
        XCTAssertEqual(count("OnboardingCoordinator.requestNotificationAuthorization()", in: source), 1)
        XCTAssertEqual(count("SetupPlan.promptsAtLaunch(", in: source), 1)
        XCTAssertEqual(count("SetupPlan.opensAtLaunch(", in: source), 1)
        XCTAssertEqual(count("OnboardingCoordinator.", in: source), 3, "the two prompts, and the cause line's pane, by the cause")
        // Before either prompt, and the decisions are the plan's: the delegate combines nothing of its own.
        let facts = try position(of: "let launchFacts = setupCoordinator.facts()", in: launch)
        XCTAssertLessThan(facts, try position(of: "OnboardingCoordinator.requestAccessibilityIfNeeded()", in: launch))
        XCTAssertLessThan(facts, try position(of: "OnboardingCoordinator.requestNotificationAuthorization()", in: launch))
        for word in ["!promptsAtLaunch", "!opensAtLaunch", "promptsAtLaunch &&", "promptsAtLaunch ||", "opensAtLaunch &&",
                     "opensAtLaunch ||", "AXIsProcessTrusted", "isFresh", "SetupPlan.standing", "configuration", "nudgeLine"] {
            XCTAssertFalse(launch.contains(word), word)
        }
        // The probe is not asked by the guide's decision; the first answer is the health refresh's, and the
        // delegate's copy of it starts as nil (`testTheNotificationFactIsNilUntilTheProbeAnsweredAndIsReadAsItAnswered`).
        XCTAssertEqual(count("delivery = await DeliveryStatusProbe.current()", in: source), 1)
        XCTAssertEqual(trimmed(try body(of: "private func refreshHealth(runCanary: Bool) async {", in: source)).components(separatedBy: "\n").first,
                       "delivery = await DeliveryStatusProbe.current()")
    }

    /// One item, below the health line and its cause and above On Call (Ruling 17), shown only when the
    /// plan gives a line, with whether the guide's window is open from the window, which reports it and
    /// whose report the core answers. Choosing it shows the guide. It is built like every other item, by
    /// the one build of the items that the gate makes, so a menu that is open does not move under the
    /// pointer, and it is built from rules that are loaded (`testTheRulesAreLoaded...`).
    func testTheNudgeIsOneItemAfterTheHealthLineAndItsCauseAndBeforeOnCallAndChoosingItShowsTheGuide() throws {
        let source = try app()
        let nudge = try body(of: "private func addSetupNudge(to menu: NSMenu) {", in: source)
        XCTAssertEqual(trimmed(nudge), lines([
            "guard let line = SetupPlan.nudgeLine(setupCoordinator.facts(), guideIsOpen: setupWindow.isOpenForTheNudge) else {",
            "return",
            "}",
            "let nudge = NSMenuItem(title: line, action: #selector(showSetupGuide), keyEquivalent: \"\")",
            "nudge.target = self",
            "menu.addItem(nudge)",
        ]))
        XCTAssertEqual(count("SetupPlan.nudgeLine(", in: source), 1)
        XCTAssertEqual(count("setupWindow.isOpenForTheNudge", in: source), 1)
        XCTAssertEqual(count("addSetupNudge(", in: source), 2, "its declaration, and one call, which is the build of the items")
        XCTAssertEqual(count("#selector(showSetupGuide)", in: source), 1, "the nudge's action")

        let items = try body(of: "private func rebuildMenuItems(loginItemStatus: LoginItemStatus?) {", in: source)
        XCTAssertEqual(count("addSetupNudge(to: menu)", in: items), 1, "built with the rest of the items, through the gate")
        let health = try position(of: "menu.addItem(withTitle: healthTitle, action: nil, keyEquivalent: \"\")", in: items)
        let cause = try position(of: "advice.representedObject = cause.pane?.rawValue", in: items)
        let line = try position(of: "addSetupNudge(to: menu)", in: items)
        let onCall = try position(of: "addOnCallSection(to: menu, loginItemStatus: loginItemStatus)", in: items)
        XCTAssertLessThan(try position(of: "addEscalationSection(to: menu)", in: items), health)
        XCTAssertLessThan(health, cause)
        XCTAssertLessThan(cause, line)
        XCTAssertLessThan(line, onCall)
        XCTAssertEqual(run(["addSetupNudge(to: menu)", "menu.addItem(.separator())", "addOnCallSection(to: menu, loginItemStatus: loginItemStatus)"],
                           in: items), 1, "nothing stands between the line and On Call but the separator")
        // Through the gate like every other item: the items are made in the one place the gate lets them be.
        XCTAssertEqual(count("case .rebuildItems: rebuildMenuItems(loginItemStatus: loginItemStatus)", in: source), 1)
        XCTAssertEqual(count("rebuildMenuItems(", in: source), 2, "its declaration and the gate's step")
        // It says what the plan says and nothing of its own; it reads no health.
        XCTAssertFalse(nudge.contains("health"))
        XCTAssertFalse(nudge.contains("HealthTitle"))
        XCTAssertEqual(literals(in: nudge).filter { !$0.isEmpty }, [], "no word typed in the item that shows one")
    }

    /// The guide is shown by one door, `showSetupGuide()`, which the launch decision, the menu's nudge and
    /// Settings' button all come through. Showing it records the start before anything else (the
    /// controller's first statement) and reads Settings' line again afterwards, since the start changes
    /// where the guide stands.
    func testTheGuideIsShownByOneDoorAndEveryWayToItComesThroughIt() throws {
        let source = try app()
        XCTAssertEqual(trimmed(try body(of: "@objc private func showSetupGuide() {", in: source)), lines([
            "setupWindow.show()",
            "refreshSetup()",
        ]))
        XCTAssertEqual(count("setupWindow.show()", in: source), 1)
        XCTAssertEqual(count("showSetupGuide", in: source), 5,
                       "its declaration, the launch decision, the Setup group's button, the nudge's action and the reopen")
        XCTAssertEqual(count("if opensAtLaunch { showSetupGuide() }", in: source), 1)
        XCTAssertEqual(count("settingsModel.openGuide = { [weak self] in self?.showSetupGuide() }", in: source), 1)
        XCTAssertEqual(count("#selector(showSetupGuide)", in: source), 1)
        for file in try AppSources.fileNames() where file != "AppDelegate.swift" {
            XCTAssertFalse(try code(file).contains("showSetupGuide"), file)
        }
        XCTAssertEqual(count("setupWindow.", in: source), 3, "show, and the nudge's report of whether it is open, and the refresh")
    }

    /// The guide is read again at four moments and when its window closes, and at no other, with no
    /// timer (Ruling 20): the app's activation, the opening of the menu, after Check again, and
    /// `syncInspector`, which every capture and health change takes. One set of facts is gathered and
    /// handed to the window, which keeps itself up to date only while it is on screen or minimised, and
    /// to Settings' model for its line. Activation reaches it through `syncInspector`, by the rebuild it
    /// ends in, and does not read it a second time.
    func testTheGuideIsReadAgainWhenTheAppIsActivatedTheMenuOpensCheckAgainAndOnSyncInspectorAndNowhereElse() throws {
        let source = try app()
        XCTAssertEqual(trimmed(try body(of: "private func refreshSetup() {", in: source)), lines([
            "let facts = setupCoordinator.facts()",
            "setupWindow.refresh(from: facts)",
            "settingsModel.takeSetupFacts(facts)",
        ]))
        // Activation evaluates health again from what can be read at once, as the menu's opening and the
        // on-call check window's coming to the front do, so that "Prove it can read" does not go on giving a
        // cause the first step has been seen to have cleared, and then draws again what is made from health,
        // as those two do (`rebuildMenu()`), so that the icon and the Inspector's health line do not go on
        // showing the older value beside a guide that shows the new one (Ruling 16). The guide is read by
        // that rebuild. It asks the probe nothing and runs no self-test: those wait for Check again, the
        // request for notifications and the menu's opening, as `ButtonAction.readsAgain` says.
        let activation = try body(of: "func applicationDidBecomeActive(_ notification: Notification) {", in: source)
        XCTAssertEqual(trimmed(activation), lines([
            "if delivery != nil { health = HealthEvaluator.evaluate(healthInputs()) }",
            "rebuildMenu()",
        ]), "activation: health first, then what is drawn from it")
        XCTAssertEqual(count("if delivery != nil { health = HealthEvaluator.evaluate(healthInputs()) }", in: source), 2,
                       "the check window's coming to the front, and activation")
        XCTAssertEqual(count("health = HealthEvaluator.evaluate(healthInputs())", in: source), 4,
                       "the health refresh, the menu's opening, the check window's coming to the front and activation")
        for word in ["DeliveryStatusProbe", "refreshHealth", "canary", "reloadRules", "startCapture", "evaluateOnCallWatch",
                     "refreshSetup", "alarm", "LoginItem"] {
            XCTAssertFalse(activation.contains(word), "activation reads what is known and does nothing else: \(word)")
        }
        // What reads the guide is the rebuild's Inspector sync, which every rebuild makes, whether the menu is
        // held open or not, and which ends in the read; so activation reads the guide once, and a rebuild
        // that left the sync out, or a gate that left it out of a held menu's answer, would show here.
        XCTAssertEqual(count("case .syncInspector: syncInspector()", in: source), 1)
        var gate = MenuRebuildGate()
        XCTAssertTrue(gate.request().contains(.syncInspector), "a menu that is closed")
        gate.menuOpened()
        XCTAssertTrue(gate.request().contains(.syncInspector), "a menu that is held open")
        let opens = try body(of: "func menuNeedsUpdate(_ menu: NSMenu) {", in: source)
        XCTAssertEqual(count("refreshSetup()", in: opens), 2, "once on each of the menu's two builds, after the watch is asked")
        XCTAssertEqual(run(["evaluateOnCallWatch(loginItemStatus: loginItemStatus)", "refreshSetup()", "return"], in: opens), 1)
        XCTAssertEqual(run(["evaluateOnCallWatch(loginItemStatus: loginItemStatus)", "refreshSetup()", "if justStarted {"], in: opens), 1)
        let again = try body(of: "private func readAgain(startCapture: Bool, runSelfTest: Bool) async {", in: source)
        XCTAssertTrue(trimmed(again).hasSuffix("refreshSetup()"), "after Check again")
        XCTAssertTrue(trimmed(try body(of: "private func syncInspector() {", in: source)).hasSuffix("refreshSetup()"), "syncInspector")
        // And when the window closes, which changes where the guide stands, and when it is shown.
        XCTAssertEqual(count("controller.didClose = { [weak self] in self?.refreshSetup() }", in: source), 1)
        XCTAssertEqual(trimmed(try body(of: "@objc private func showSetupGuide() {", in: source)).components(separatedBy: "\n").last,
                       "refreshSetup()")
        // Those are all: the declaration, the menu twice, Check again, syncInspector, the window's close and
        // the door; activation is the rebuild's, through syncInspector.
        XCTAssertEqual(count("refreshSetup()", in: source), 7)
        // Activation is the delegate's own, so there is no observer of it for the guide to hold or to forget.
        XCTAssertEqual(count("DidBecomeActive", in: source), 1)
        // The window and Settings' model are given facts by this, and by nothing else.
        XCTAssertEqual(count("setupWindow.refresh(from: ", in: source), 1)
        XCTAssertEqual(count("settingsModel.takeSetupFacts(", in: source), 1)
        // No timer, no sleep, no delayed call in any of them.
        for part in [try body(of: "private func refreshSetup() {", in: source), again,
                     try body(of: "func applicationDidBecomeActive(_ notification: Notification) {", in: source)] {
            for word in ["Timer", "asyncAfter", "Task", "sleep", "RunLoop", "DispatchQueue"] {
                XCTAssertFalse(part.contains(word), word)
            }
        }
    }

    /// Whatever writes `health` goes on, in the same function, to draw what is made from it: the icon, the
    /// Inspector's health line and the menu are all `rebuildMenu()`'s. A write that does not leaves them
    /// showing the older value beside a guide, and Settings' line, that show the new one, and the icon is
    /// the one thing that shows a fault when no window is open (Ruling 16). Activation was such a write
    /// once. These are the five writes there are; a sixth, anywhere, has to be added here, and so be seen.
    func testEveryWriteOfHealthIsFollowedByARedrawInTheSameFunction() throws {
        let source = try app()
        XCTAssertEqual(count("health = ", in: source), 5, "the writes of health there are, the declaration not being one")
        let writers = [
            "func applicationDidBecomeActive(_ notification: Notification) {",
            "private func refreshOnCallCheckFromWhatIsKnown() {",
            "private func refreshHealth(runCanary: Bool) async {",
            "func menuNeedsUpdate(_ menu: NSMenu) {",
        ]
        var written = 0
        for signature in writers {
            let function = try body(of: signature, in: source)
            var from = function.startIndex
            while let write = function.range(of: "health = ", range: from..<function.endIndex) {
                written += 1
                // The next thing drawn comes before the function can return, so that a path out between the
                // two, which draws a later write's rebuild and not this one's, is not mistaken for it.
                if let redraw = function.range(of: "rebuildMenu(", range: write.upperBound..<function.endIndex) {
                    XCTAssertFalse(function[write.upperBound..<redraw.lowerBound].contains("return"),
                                   "\(signature) can return after writing health and before drawing from it")
                } else {
                    XCTFail("\(signature) writes health and then draws nothing from it")
                }
                from = write.upperBound
            }
        }
        XCTAssertEqual(written, 5, "every write is in one of the four")
        // And the icon is drawn by that rebuild, as one of the three steps the gate answers for every change.
        XCTAssertEqual(count("case .refreshGlyph: rebuildGlyph()", in: source), 1)
        XCTAssertTrue(MenuRebuildGate.everyChange.contains(.refreshGlyph))
    }

    /// Check again, and the read after the request for notifications, read again what the app reads from
    /// outside itself, which the core says (`readsAgain`): capture is started first where the core says
    /// (`startsCaptureIfTrusted`), and only if Accessibility has been granted since launch and it is not
    /// running, as the menu does as it opens, so that there is something to prove; the rules are loaded
    /// again, so that a file that was edited stops reading as blocked; the probe is asked again and health
    /// is evaluated again, by the health refresh; and one self-test is asked for only where the core says
    /// (`runsSelfTest(on:)`), as the on-call check's Check Now asks for one, with the core's answer handed
    /// to the health refresh as it is and no follow-up called for by the read itself.
    ///
    /// **What this does not hold is that no other self-test follows**, and the test says what does. Capture
    /// that the read starts attaches, and the one place capture's attach is wired asks for a self-test and
    /// arms the follow-up (the launch's own call), as at launch and when the menu's opening starts it; and
    /// the one place a self-test is decided, `SelfTestPlan.decide`, runs one for a block that has cleared
    /// even when none was asked for. Both are the app's own and are held here as they are, so a change to
    /// either shows as a change to what the guide's presses can cause.
    func testTheReadStartsCaptureWhereTheCoreSaysReloadsTheRulesAsksTheProbeAndAsksForASelfTestOnlyWhereTheCoreSays() throws {
        let source = try app()
        let again = try body(of: "private func readAgain(startCapture: Bool, runSelfTest: Bool) async {", in: source)
        XCTAssertEqual(trimmed(again), lines([
            "if startCapture { startCaptureIfTrusted() }",
            "reloadRules()",
            "await refreshHealth(runCanary: runSelfTest)",
            "refreshSetup()",
        ]))
        XCTAssertEqual(count("refreshHealth(runCanary: runSelfTest)", in: source), 1, "the core's answer, handed over once")
        XCTAssertEqual(count("startCaptureIfTrusted() }", in: again), 1, "under the core's answer and nowhere else")
        XCTAssertEqual(count("readAgain(", in: source), 2, "its declaration, and the call the source makes")
        XCTAssertEqual(count("canary.run()", in: source), 1, "the self-test is run in the one place it was, by the health refresh")
        // The same call the on-call check's Check Now makes, and not the launch's, which arms a follow-up.
        XCTAssertEqual(count("controller.model.checkNow = { [weak self] in await self?.refreshHealth(runCanary: true) }", in: source), 1)
        XCTAssertFalse(again.contains("FollowUp"), "the read itself calls for no follow-up")
        XCTAssertFalse(again.contains("canary"))
        // The probe is asked again by the health refresh, as its first act.
        let refresh = try body(of: "private func refreshHealth(runCanary: Bool) async {", in: source)
        XCTAssertTrue(trimmed(refresh).hasPrefix("delivery = await DeliveryStatusProbe.current()"))
        // Capture is started by one function, which is the one place capture's attach is wired, and an
        // attach asks for a self-test and arms the follow-up. The read starts capture through it, so a read
        // that does start capture causes both, as the launch and the menu's opening do.
        let started = try body(of: "private func startCaptureIfTrusted() -> Bool {", in: source)
        XCTAssertEqual(count("capture.onAttach = ", in: source), 1)
        XCTAssertEqual(count("capture.onAttach = ", in: started), 1)
        XCTAssertEqual(count("await self?.refreshHealthAndFollowUp()", in: started), 1)
        XCTAssertEqual(count("capture.start()", in: source), 1)
        XCTAssertEqual(count("capture.start()", in: started), 1)
        // And the health refresh decides a self-test by `SelfTestPlan`, in the one place, from whether one was
        // requested and whether what blocked one has cleared, so a read that asked for none can still run one.
        XCTAssertEqual(count("SelfTestPlan.decide(", in: source), 1)
        XCTAssertEqual(count("let plan = SelfTestPlan.decide(requested: runCanary, previous: lastSelfTestConditions, current: conditions)",
                             in: refresh), 1)
        // The coordinator hands the core's answers to the source, and chooses none.
        XCTAssertEqual(count("sources.readAgain(action.startsCaptureIfTrusted, action.runsSelfTest(on: step))", in: try coordinator()), 1)
    }

    /// The guide is read from the login item as Settings' model last read it, because reading it is a
    /// synchronous call that a burst of banners should not each wait for. For an activation that read is
    /// the one made for the same notice, and first: the model is made with the delegate, before `main.swift`
    /// sets the delegate that AppKit then registers for the notice, and its observer is a block on the main
    /// queue, which Foundation runs at once for a notice posted on the main thread (measured in a scratch
    /// program, not in this app). So the guide that activation reads is not one activation behind. This
    /// holds the three places that order rests on, so that making the model lazy, or setting the delegate
    /// first, or giving the model another queue, shows here.
    func testSettingsModelReadsTheLoginItemForAnActivationBeforeTheDelegateReadsTheGuide() throws {
        let source = try app()
        XCTAssertEqual(count("private let settingsModel = SettingsModel()", in: source), 1, "made with the delegate, not lazily")
        XCTAssertEqual(count("lazy var settingsModel", in: source), 0)
        let main = try code("main.swift")
        XCTAssertLessThan(try position(of: "let delegate = AppDelegate()", in: main),
                          try position(of: "app.delegate = delegate", in: main))
        let made = try body(of: "init(defaults: UserDefaults = .standard) {", in: try code("SettingsModel.swift"))
        XCTAssertEqual(count("forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main)", in: made), 1)
        XCTAssertEqual(count("MainActor.assumeIsolated { self?.refresh() }", in: made), 1)
        // And the delegate reads the guide in the method AppKit sends it for the notice, and in no observer of
        // its own that could be registered earlier.
        XCTAssertEqual(count("DidBecomeActive", in: source), 1)
        XCTAssertEqual(count("addObserver", in: source), 1, "the wake notice, as before")
    }

    /// Opening the rules file hands its failure back, and shows nothing: the guide shows the core's
    /// sentence beside its button, and the menu's item keeps the alert it has always shown. The rule
    /// editor's button reaches the alert too. Neither the delegate's act nor the guide adds a modal.
    func testOpeningTheRulesFileHandsItsFailureBackTheMenuKeepsItsAlertAndTheGuideShowsASentence() throws {
        let source = try app()
        XCTAssertEqual(trimmed(try body(of: "private func openRulesFile() -> Error? {", in: source)), lines([
            "do {",
            "try ruleStore.createExampleIfMissing()",
            "} catch {",
            "return error",
            "}",
            "if !NSWorkspace.shared.open(ruleStore.fileURL) {",
            "NSWorkspace.shared.activateFileViewerSelecting([ruleStore.fileURL])",
            "}",
            "reloadRules()",
            "return nil",
        ]))
        XCTAssertEqual(trimmed(try body(of: "@objc private func openRulesFileInTextEditor() {", in: source)), lines([
            "guard let error = openRulesFile() else { return }",
            "NSApp.activate(ignoringOtherApps: true)",
            "NSAlert(error: error).runModal()",
        ]))
        XCTAssertEqual(count("openRulesFile()", in: source), 3, "its declaration, the menu's act and the guide's source")
        XCTAssertEqual(count("createExampleIfMissing()", in: source), 1)
        // The menu's item and the editor's button are the alert's; the guide's source is the failure.
        XCTAssertEqual(run(["let text = NSMenuItem(title: SetupText.rulesFileMenuTitle, action: #selector(openRulesFileInTextEditor),",
                            "keyEquivalent: \"\")"], in: source), 1)
        XCTAssertEqual(count("editor.openInTextEditor = { [weak self] in self?.openRulesFileInTextEditor() }", in: source), 1)
        XCTAssertEqual(count("openRulesFile: { [weak self] in self?.openRulesFile() },", in: source), 1)
        // The alert is in one place, as it was, and the act has none.
        XCTAssertEqual(count("NSAlert(error: error).runModal()", in: source), 1)
        XCTAssertFalse(try body(of: "private func openRulesFile() -> Error? {", in: source).contains("NSAlert"))
        XCTAssertFalse(try body(of: "private func openRulesFile() -> Error? {", in: source).contains("runModal"))
        // The mute lookup's alert stays in the menu's walkthrough, and the guide has a sentence of its own.
        let walkthrough = try code("MuteWalkthroughMenu.swift")
        XCTAssertEqual(count("alert.runModal()", in: walkthrough), 1)
        XCTAssertEqual(count("MuteWalkthroughText.lookupFallback(app, resolution)", in: walkthrough), 1)
        for file in try AppSources.fileNames() where file.hasPrefix("Setup") {
            XCTAssertFalse(try code(file).contains("MuteWalkthroughMenu"), file)
        }
    }

    /// Nothing the guide adds to the delegate shows a modal, starts a timer or reaches the health alarm:
    /// the delegate holds the same number of each as before, and the functions this commit adds hold none.
    /// A beep that sounds over the guide is the lesser fault (Ruling 10), so the alarm is given no input
    /// and holds nothing back, and the places that ask it are the places that asked it.
    func testNothingTheGuideAddsToTheDelegateShowsAModalStartsATimerOrTouchesTheAlarm() throws {
        let source = try app()
        XCTAssertEqual(count("runModal", in: source), 2, "the quit prompt and the menu's alert for the rules file, as before")
        XCTAssertEqual(count("NSAlert", in: source), 3, "the quit prompt's property and its alert, and the rules file's, as before")
        XCTAssertEqual(count("Timer(", in: source), 5, "as before: the self-tests, their retry, the blocked check, the follow-up and the icon")
        XCTAssertEqual(count("scheduledTimer", in: source), 0)
        XCTAssertEqual(count("asyncAfter", in: source), 0)
        XCTAssertEqual(count("alarm", in: source), 5, "as before: its declaration, wake, reset, report, and the icon's state")
        XCTAssertEqual(count("NSSound", in: source), 2, "as before: the watch's beep and the snooze's end")
        XCTAssertEqual(count("alarm.report(health, deliveryHealthy: delivery?.wouldDisplay == true, onCall: onCall.state.isOn)", in: source), 1,
                       "the alarm is given what it was given")
        let mine = [
            try body(of: "@objc private func showSetupGuide() {", in: source),
            try body(of: "private func refreshSetup() {", in: source),
            try body(of: "private func readAgain(startCapture: Bool, runSelfTest: Bool) async {", in: source),
            try body(of: "private func addSetupNudge(to menu: NSMenu) {", in: source),
            try body(of: "func applicationDidBecomeActive(_ notification: Notification) {", in: source),
            try body(of: "private func openRulesFile() -> Error? {", in: source),
        ]
        for part in mine {
            for word in ["runModal", "NSAlert", "beginSheet", "Timer", "alarm", "HealthAlarm", "NSSound", "beep", "OnCallWatch",
                         "StatusGlyph", "snooze", "escalations", "PlayerOwnership"] {
                XCTAssertFalse(part.contains(word), "\(word) in \(part)")
            }
        }
        // The setup guide's launch decision is no input to the alarm either.
        let launch = try launch()
        XCTAssertFalse(launch.contains("alarm"))
    }

    /// The words of the status menu's item for the rules file are the core's, in the words it had, and
    /// the delegate no longer holds them: typing them back is refused by the delegate's baseline.
    func testTheRulesFileMenuItemsWordsAreTheCoresAndTypedBackIntoTheDelegateTheyAreRefused() throws {
        let source = try XCTUnwrap(AppSources.read("AppDelegate.swift"))
        XCTAssertEqual(SetupText.rulesFileMenuTitle, "Open Rules File in Text Editor\u{2026}")
        let anchor = "NSMenuItem(title: SetupText.rulesFileMenuTitle, action: #selector(openRulesFileInTextEditor),"
        XCTAssertTrue(source.contains(anchor), "the item's title is the core's")
        XCTAssertFalse(literals(in: source).contains("Open Rules File in Text Editor\u{2026}"))
        XCTAssertFalse(HeldFiles.baselineOthers.first { $0.file == "AppDelegate.swift" }?.literals
            .contains("Open Rules File in Text Editor\u{2026}") ?? true, "the baseline shrank when the literal moved")
        let typedBack = source.replacingOccurrences(
            of: anchor, with: "NSMenuItem(title: \"Open Rules File in Text Editor\u{2026}\", action: #selector(openRulesFileInTextEditor),")
        let listed = HeldFiles.baselineOthers.first { $0.file == "AppDelegate.swift" }?.literals ?? []
        XCTAssertEqual(LiteralRules.violations(in: typedBack, policy: .baseline(listed)).map(\.text),
                       ["Open Rules File in Text Editor\u{2026}"])
    }
}
