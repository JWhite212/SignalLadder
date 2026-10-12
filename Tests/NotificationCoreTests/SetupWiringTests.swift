import XCTest
@testable import NotificationCore

/// How the app target gathers what the first run reads and carries out what its buttons say
/// (M5 plan, Task 8, Rulings 10, 16, 20 and 22): the store that saves its progress and the
/// coordinator that reads the facts and presses the buttons.
///
/// The app target has no tests, and what the core cannot hold is the wiring: that the one
/// list of tokens is written by one place and nothing else touches the key, that the start
/// is recorded before the window is handed anything, that "Not now" and a closed window both
/// come to the one dismissal, that the last step's choice is saved by Settings' own function
/// and not by a second copy of the key, that a permission is asked for only by the press of
/// its button, that the first rule is made by calling the rule editor, that the guide reads
/// no clock, starts no timer and shows no alert, and that it gives the health alarm no input
/// and holds nothing back. Swap any of them and the app builds without a warning. So these
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
    /// whether it is, so the check stays in the core, where it is tested.
    func testNotNowAndTheClosedWindowBothRecordTheDismissalThroughTheOneMethod() throws {
        let source = try coordinator()
        XCTAssertEqual(count("recordDismissed()", in: source), 1, "written in one place")
        let recorded = trimmed(try body(of: "private func recordDismissal() {", in: source))
        XCTAssertEqual(recorded, "progress.record { $0.recordDismissed() }")
        let closed = trimmed(try body(of: "func guideDidClose() {", in: source))
        XCTAssertEqual(closed, "recordDismissal()")
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
                          "func guideDidClose() {"] {
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
    /// after the press, for whichever the core names. No arm reads again of its own accord, so
    /// an arm added or changed cannot add a read the core did not decide, and Check again, whose
    /// whole act is the read, does nothing else.
    func testWhichPressesReadAgainIsTheCoresAndTheReadIsMadeOnceAfterThePress() throws {
        let source = try coordinator()
        XCTAssertEqual(trimmed(try press()), lines([
            "let sentence = await perform(action, on: step, app: app, boxTicked: boxTicked)",
            "if action.readsAgain { await sources.readAgain() }",
            "return sentence",
        ]))
        XCTAssertEqual(count("sources.readAgain()", in: source), 1, "one read, and it is the core's to ask for")
        XCTAssertEqual(count("readsAgain", in: source), 1)
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
        XCTAssertEqual(count("ruleEditor.show(", in: source), 1)
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
            "appliedFingerprint = snapshot.fingerprint",
            "(rules, status) = RuleStoreStatus.load(snapshot.data, availableSounds: check.available,",
            "unplayable: check.unplayable, availableVoices: check.voices)",
            "warnings = RuleWarnings.warnings(for: rules, sounds: check)",
            "readOnlyReason = RulesDocument.load(snapshot.data).readOnlyReason",
            "} catch {",
        ], in: reload), 1, "made from the snapshot the status was made from, as the editor reads a document")
        XCTAssertEqual(run([
            "} catch {",
            "appliedFingerprint = nil",
            "rules = []",
            "warnings = []",
            "readOnlyReason = .unreadable(String(describing: error))",
            "status = .unreadable(String(describing: error))",
            "}",
        ], in: reload), 1, "a file that cannot be opened is one the editor shows as unreadable")
        XCTAssertEqual(count("readOnlyReason =", in: store), 2, "assigned in these two places and nowhere else")
        XCTAssertEqual(count("RulesDocument.load(", in: store), 1)
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
    /// so a place that makes the sources and forgets one does not compile.
    func testTheSourcesAreSevenClosuresWithNoDefault() throws {
        let source = try coordinator()
        let sources = trimmed(try body(of: "struct Sources {", in: source))
        XCTAssertEqual(sources, lines([
            "var accessibilityTrusted: () -> Bool",
            "var delivery: () -> DeliveryStatus?",
            "var health: () -> CaptureHealth",
            "var lastVerifiedAt: () -> Date?",
            "var readAgain: () async -> Void",
            "var openRulesFile: () -> Error?",
            "var time: (Date) -> String",
        ]))
    }
}
