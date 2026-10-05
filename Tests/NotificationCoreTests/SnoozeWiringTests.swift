import XCTest
@testable import NotificationCore

/// How the app target connects the snooze and carries out what the core decides
/// about it (M5 plan, Task 4, Rulings 10, 12, 13, 17, 18 and 22): the store, the
/// controller, the gate in the pipeline, the menu, the icon, Dismiss, the switch of
/// on-call mode and the one sound.
///
/// The app target has no tests, and what the core cannot hold is the wiring: that
/// the controller is made once, from what the preferences hold, on the one scheduler;
/// that it is asked to settle once at launch; that the pipeline is given its verdict;
/// that a change redraws the menu on the next turn and not on the spot; that the menu
/// is drawn from the value `SnoozeText` makes, in the place Ruling 17 gives it, with
/// no word and no decision of the app's own; that Dismiss hands back the summary its
/// line was made from; and that the only sound is the controller's announcement. Swap
/// any of them and the app builds without a warning, and a snooze would hold nothing,
/// or the menu would be emptied in the middle of being filled, or a page held in the
/// seconds a menu was open would be dismissed unseen. So these tests read the app's
/// sources, as `OnCallWiringTests` and `ViewLiteralsTests` do, and hold each place to
/// what it is meant to say. They start nothing, sound nothing, open no window and read
/// no preferences.
final class SnoozeWiringTests: XCTestCase {
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

    private func position(of needle: String, in text: String) throws -> String.Index {
        try XCTUnwrap(text.range(of: needle), "\(needle) is not there").lowerBound
    }

    private func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func lines(_ lines: [String]) -> String {
        lines.joined(separator: "\n")
    }

    /// How many times these lines stand one directly after another, whole lines each.
    private func run(_ lines: [String], in text: String) -> Int {
        count("\n" + lines.joined(separator: "\n") + "\n", in: "\n" + text + "\n")
    }

    private static let sections = [
        "private func addSnoozeSection(to menu: NSMenu) {",
        "@objc private func startSnoozeFromMenu(_ sender: NSMenuItem) {",
        "@objc private func endSnoozeFromMenu() {",
        "@objc private func dismissHeldFromMenu(_ sender: NSMenuItem) {",
        "private func snoozeChanged() {",
    ]

    // MARK: The store

    /// The store is the only place the two saved values are read or written, it holds
    /// the core's keys and no key or word of its own, and a value goes to the
    /// preferences as the controller hands it, or the key is taken out for none. What a
    /// value may hold is the controller's, and `SnoozeControllerTests` holds it.
    func testTheStoreReadsAndWritesTheCoresTwoKeysAndNothingElseAndHoldsNoLiteral() throws {
        let store = try code("SnoozeStore.swift")
        XCTAssertEqual(count("@MainActor\nfinal class SnoozeStore {", in: store), 1)
        XCTAssertEqual(count("init(defaults: UserDefaults = .standard) {", in: store), 1,
                       "the defaults are injected, as OnCallStore's and the mute checklist's are")
        XCTAssertEqual(count("var storedUntil: Any? { defaults.object(forKey: SnoozeController.untilKey) }", in: store), 1)
        XCTAssertEqual(count("var storedHeld: Any? { defaults.object(forKey: SnoozeController.heldKey) }", in: store), 1)
        XCTAssertEqual(trimmed(try body(of: "func save(_ key: String, _ value: Any?) {", in: store)), lines([
            "if let value {",
            "defaults.set(value, forKey: key)",
            "} else {",
            "defaults.removeObject(forKey: key)",
            "}",
        ]))
        XCTAssertEqual(count("forKey:", in: store), 4, "two reads, a write and a removal, and no other access")
        XCTAssertEqual(count("forKey: SnoozeController.", in: store), 2, "the reads are of the core's keys")
        XCTAssertEqual(SwiftLiteralScanner.literals(in: try XCTUnwrap(AppSources.read("SnoozeStore.swift"))).map(\.text), [],
                       "no key and no word is typed into the store")
    }

    /// Nothing else in the target reads or writes the two values, names the keys or makes
    /// a second store, so what the controller restored from is what it saved to.
    func testNothingButTheStoreTouchesTheTwoValuesAndTheStoreIsMadeOnce() throws {
        for file in try AppSources.fileNames() where file != "SnoozeStore.swift" {
            let source = try code(file)
            for word in ["untilKey", "heldKey", "snoozeUntil", "snoozeHeld"] {
                XCTAssertFalse(source.contains(word), "\(file) names \(word)")
            }
            if file != "AppDelegate.swift" { XCTAssertFalse(source.contains("SnoozeStore"), file) }
        }
        let app = try code("AppDelegate.swift")
        XCTAssertEqual(count("SnoozeStore(", in: app), 1)
        XCTAssertEqual(count("private let snoozeStore = SnoozeStore()", in: app), 1)
        XCTAssertEqual(count("snoozeStore.", in: app), 3, "two reads at the making of the controller, and its save")
    }

    /// A word typed into the store is refused as one typed into the Settings model is:
    /// it holds none, and neither does it name a key.
    func testAWordOrAKeyTypedIntoTheStoreIsRefused() throws {
        XCTAssertTrue(HeldFiles.baselineOthers.contains { $0.file == "SnoozeStore.swift" && $0.literals.isEmpty },
                      "the store is held, to no literal at all")
        let source = try XCTUnwrap(AppSources.read("SnoozeStore.swift"))
        XCTAssertEqual(LiteralRules.violations(in: source, policy: .baseline([])), [])
        let anchor = "defaults.removeObject(forKey: key)"
        XCTAssertTrue(source.contains(anchor), "\(anchor) is where this test types a word")
        let typed = source.replacingOccurrences(of: anchor, with: "defaults.removeObject(forKey: \"snoozeUntil\")")
        XCTAssertEqual(LiteralRules.violations(in: typed, policy: .baseline([])).map(\.text), ["snoozeUntil"])
    }

    // MARK: The controller

    /// One controller, from what the store holds, on the scheduler the escalations and the
    /// quit notice already use, and each closure does the one thing it is for: save to the
    /// store, ask for a redraw, and beep. The scheduler is shared and not doubled: it keeps
    /// each timer under its own token, so one instance is one clock for all of them.
    func testTheSnoozeIsBuiltOnceFromTheStoreOnTheOneSchedulerAndEachClosureDoesOneThing() throws {
        let app = try code("AppDelegate.swift")
        XCTAssertEqual(count("SnoozeController(", in: app), 1)
        let declaration = lines([
            "private lazy var snooze: SnoozeController = SnoozeController(",
            "scheduler: escalationScheduler,",
            "storedUntil: snoozeStore.storedUntil,",
            "storedHeld: snoozeStore.storedHeld,",
            "save: { [snoozeStore] key, value in snoozeStore.save(key, value) },",
            "changed: { [weak self] in self?.snoozeChanged() },",
            "announce: { NSSound.beep() })",
        ])
        XCTAssertEqual(count(declaration, in: app), 1)

        var schedulers = 0
        for file in try AppSources.fileNames() { schedulers += count("RunLoopEscalationScheduler(", in: try code(file)) }
        XCTAssertEqual(schedulers, 1, "one scheduler for the ladders, the quit notice and the snooze")
        XCTAssertEqual(count("private let escalationScheduler = RunLoopEscalationScheduler()", in: app), 1)
        XCTAssertEqual(count("scheduler: escalationScheduler", in: app), 2, "the coordinator's, and the snooze's")
    }

    /// The controller restores itself from the preferences as it is made, and what it owes
    /// is settled once, here, before the menu is drawn, before capture can ask it and
    /// before the rules are loaded. The timer's own settling is the controller's, and
    /// nothing else in the app settles but the wake's one step (below): a call from the
    /// menu or the icon would be a second place that could announce, and the controller
    /// announces once whichever finds the end first.
    func testTheSnoozeIsRestoredAndSettledOnceAtLaunchBeforeTheMenuCaptureAndTheRules() throws {
        let app = try code("AppDelegate.swift")
        let launch = try body(of: "func applicationDidFinishLaunching(_ notification: Notification) {", in: app)
        XCTAssertEqual(count("snooze.settle()", in: launch), 1)
        XCTAssertEqual(count("settle()", in: app), 2, "once at launch, and once as the wake's step, and nowhere else in the app")
        XCTAssertEqual(try position(of: "snooze", in: launch), try position(of: "snooze.settle()", in: launch),
                       "the first use of the controller is the settle, which is what restores it")
        for later in ["setUpStatusItem()", "startCaptureIfTrusted()", "reloadRules()"] {
            XCTAssertLessThan(try position(of: "snooze.settle()", in: launch), try position(of: later, in: launch), later)
        }
        XCTAssertEqual(count("snooze.", in: launch), 1, "launch does nothing to the snooze but settle it")
    }

    /// A Mac that slept through the end announces on waking (Ruling 12, O9): the timer is
    /// not relied on across a sleep, and off call nothing else reads the snooze on a wake.
    /// The step is the core's (`SelfTestPlan.wakeSteps`, held in `SelfTestPlanTests`), and
    /// the app carries it out with the controller's own `settle()` and does nothing more to
    /// the snooze: the redraw that stops the icon keeping the moon is the controller's,
    /// asked for when it finds the snooze over, and goes through the gate as every other
    /// does. Every step has its own arm and none has a default, so a step the core adds
    /// cannot be left undone.
    func testAWakeSettlesTheSnoozeAsTheCoresStepSaysAndDoesNothingElseToItAndDrawsNothingItself() throws {
        let app = try code("AppDelegate.swift")
        let wake = try body(of: "private func macDidWake() {", in: app)
        XCTAssertEqual(count("case .settleSnooze: snooze.settle()", in: wake), 1)
        XCTAssertEqual(count("snooze.", in: wake), 1, "the wake does nothing to the snooze but settle it")
        XCTAssertEqual(count("for step in SelfTestPlan.wakeSteps(onCall: onCall.state.isOn) {", in: wake), 1)
        for step in ["checkForSleep", "settleSnooze", "tellHealthAlarmItWoke", "runSelfTest"] {
            XCTAssertEqual(count("case .\(step):", in: wake), 1, step)
        }
        XCTAssertFalse(wake.contains("default:"), "a step the core adds must be an arm the app cannot leave out")
        for redraw in ["rebuildMenu", "rebuildGlyph", "snoozeChanged"] {
            XCTAssertFalse(wake.contains(redraw), "\(redraw): the controller asks for the redraw itself")
        }
        XCTAssertEqual(count("macDidWake()", in: app), 2, "its declaration and the one observer of the system's wake")
    }

    // MARK: The pipeline

    func testThePipelineIsGivenTheControllersVerdictAndNothingHoldsAMatchButThat() throws {
        let app = try code("AppDelegate.swift")
        XCTAssertEqual(count("CaptureController(", in: app), 1)
        XCTAssertEqual(count("}, holdForSnooze: snooze.holds)", in: app), 1)
        XCTAssertEqual(count("snooze.holds", in: app), 1, "handed over, and never asked by the app itself")

        let capture = try code("CaptureController.swift")
        XCTAssertEqual(count("holdForSnooze: @escaping (Rule) -> Bool) {", in: capture), 1, "no default")
        XCTAssertEqual(count("holdForSnooze: holdForSnooze)", in: capture), 1, "handed to the pipeline as it is given")
        XCTAssertEqual(count("CapturePipeline(", in: capture), 1)
        for file in try AppSources.fileNames() {
            let source = try code(file)
            XCTAssertFalse(source.contains("holdForSnooze: { _ in"), "\(file) gives the pipeline a gate that decides alone")
            XCTAssertFalse(source.contains("{ _ in false }"), file)
        }
    }

    // MARK: A change redraws on the next turn

    /// The controller asks for a redraw from inside a read that finds the snooze over, and
    /// from inside the pipeline while a match is being recorded. The redraw reads the
    /// snooze, empties the menu and fills it again, so one made on the spot would empty the
    /// menu it is in the middle of filling, and would draw a match that is not yet
    /// recorded. The next turn of the main queue does it, through the gate, so an open
    /// menu holds still (Ruling 22).
    func testAChangeAsksForARedrawOnTheNextTurnThroughTheGateAndNeverOnTheSpot() throws {
        let app = try code("AppDelegate.swift")
        XCTAssertEqual(trimmed(try body(of: "private func snoozeChanged() {", in: app)), lines([
            "DispatchQueue.main.async { [weak self] in",
            "MainActor.assumeIsolated { self?.rebuildMenu() }",
            "}",
        ]))
        XCTAssertEqual(count("snoozeChanged()", in: app), 2, "its declaration and the controller's one closure")
        // The gate is what `rebuildMenu` asks: the items are not rebuilt while the menu is open.
        XCTAssertEqual(count("case .rebuildItems: rebuildMenuItems(loginItemStatus: loginItemStatus)", in: app), 1)
        XCTAssertEqual(count("rebuildMenuItems(", in: app), 2, "its declaration and the gate's step, so no redraw goes round it")
        let rebuild = try body(of: "private func rebuildMenu(loginItemStatus: LoginItemStatus? = nil) {", in: app)
        XCTAssertTrue(rebuild.contains("menuGate.request()"))
        // None of the controller's closures reads the controller or draws.
        let from = try position(of: "private lazy var snooze: SnoozeController = SnoozeController(", in: app)
        let to = try XCTUnwrap(app.range(of: "announce: { NSSound.beep() })")).upperBound
        let declaration = String(app[from..<to])
        XCTAssertFalse(declaration.contains("rebuild"))
        XCTAssertEqual(count("snooze.", in: declaration), 0)
    }

    // MARK: The menu

    /// Ruling 17: after the last of the On Call lines, before the capture count's
    /// separator, which is where `SnoozeMenu`'s doc comment says the app puts them, and
    /// below the escalation section, the health line and its cause, above the rules.
    func testTheSnoozeItemsAreAddedAfterTheOnCallLinesAndBeforeTheSeparatorAheadOfTheCaptureCount() throws {
        let app = try code("AppDelegate.swift")
        let items = try body(of: "private func rebuildMenuItems(loginItemStatus: LoginItemStatus?) {", in: app)
        XCTAssertEqual(run(["addOnCallSection(to: menu, loginItemStatus: loginItemStatus)",
                            "addSnoozeSection(to: menu)",
                            "menu.addItem(.separator())",
                            "let count = capture.captureCount"], in: items), 1)
        XCTAssertEqual(count("addSnoozeSection(to: menu)", in: app), 1)
        XCTAssertLessThan(try position(of: "addEscalationSection(to: menu)", in: items),
                          try position(of: "menu.addItem(withTitle: healthTitle, action: nil, keyEquivalent: \"\")", in: items))
        XCTAssertLessThan(try position(of: "advice.representedObject = cause.isDeliveryFault", in: items),
                          try position(of: "addSnoozeSection(to: menu)", in: items))
        XCTAssertLessThan(try position(of: "addSnoozeSection(to: menu)", in: items),
                          try position(of: "addRulesSection(to: menu)", in: items))
    }

    /// The menu is made from the one value `SnoozeText.menu` makes, from the facts the
    /// app has read and nothing it made up, and the app adds each item as it is given:
    /// no title, no order, no condition and no length of its own.
    func testTheMenuIsMadeFromTheCoresValueAndTheAppAddsEachItemAsItIsGivenAndDecidesNothing() throws {
        let app = try code("AppDelegate.swift")
        let section = try body(of: "private func addSnoozeSection(to menu: NSMenu) {", in: app)
        XCTAssertTrue(trimmed(section).hasPrefix(lines([
            "let snoozeMenu = SnoozeText.menu(rules: capture.pipeline.rules, onCall: onCall.state,",
            "snoozeEndsAt: snooze.endsAt, summary: snooze.summary,",
            "endedByOnCallAt: snoozeEndedByOnCallAt, now: Date(),",
            "time: Self.clock.string(from:))",
            "for item in snoozeMenu.items {",
        ])), "the rules in effect, the on-call state and not a Boolean, when it ends, what was held, the moment on-call ended one, and the menu's own clock")
        XCTAssertEqual(count("SnoozeText.", in: section), 1, "the value, and none of its constants")
        XCTAssertEqual(count("snooze.", in: section), 2, "when it ends and what it held, read once each")
        XCTAssertEqual(count("snoozeMenu.items", in: section), 1)

        // Each case is an item, in the order given, with the title the value carries.
        XCTAssertEqual(count("case .snooze(let title, let choices):", in: section), 1)
        XCTAssertEqual(count("case .line(let line):", in: section), 2, "one in the submenu and one at the top")
        XCTAssertEqual(count("case .start(let duration, let title):", in: section), 1)
        XCTAssertEqual(count("case .end(let title):", in: section), 1)
        XCTAssertEqual(count("case .dismiss(let title, let shown):", in: section), 1)
        XCTAssertEqual(count("for choice in choices {", in: section), 1)
        XCTAssertFalse(section.contains("default"), "every case is an arm, so a new one is a build error and not a silent gap")
        for decision in ["if ", "guard ", "?", ".filter", ".sorted", ".reversed", ".first", ".last", ".isEmpty", ".contains",
                         "SnoozeDuration", "allCases", ".onCall", ".isOn", ".since", "NSSound"] {
            XCTAssertFalse(section.contains(decision), "the app decides nothing here: \(decision)")
        }

        // Every title the section gives an item is the value's: a bare name the case bound.
        let titles = try NSRegularExpression(pattern: #"(?:withTitle|title): ([^,)]+)"#)
        let found = titles.matches(in: section, range: NSRange(section.startIndex..., in: section))
            .compactMap { Range($0.range(at: 1), in: section).map { String(section[$0]) } }
        XCTAssertEqual(found.count, 7, "one for each item and the submenu, and the two lines")
        XCTAssertEqual(Set(found), ["title", "line"], "no title is anything but one the value carries")

        // The submenu, the line, and the two items that do something.
        XCTAssertEqual(count("let snoozeItem = NSMenuItem(title: title, action: nil, keyEquivalent: \"\")", in: section), 1)
        XCTAssertEqual(count("let submenu = NSMenu(title: title)", in: section), 1)
        XCTAssertEqual(count("submenu.addItem(withTitle: line, action: nil, keyEquivalent: \"\")", in: section), 1)
        XCTAssertEqual(count("snoozeItem.submenu = submenu", in: section), 1)
        XCTAssertEqual(count("menu.addItem(snoozeItem)", in: section), 1)
        XCTAssertEqual(count("\nmenu.addItem(withTitle: line, action: nil, keyEquivalent: \"\")", in: "\n" + section), 1,
                       "the lines are top-level items, and not inside the submenu")
        XCTAssertEqual(count("NSMenuItem(", in: section), 4, "the Snooze item, a length, End Snooze and Dismiss")
        XCTAssertEqual(count("let start = NSMenuItem(title: title, action: #selector(startSnoozeFromMenu(_:)), keyEquivalent: \"\")",
                             in: section), 1)
        XCTAssertEqual(count("start.representedObject = duration", in: section), 1, "the choice carries the length it starts")
        XCTAssertEqual(count("let end = NSMenuItem(title: title, action: #selector(endSnoozeFromMenu), keyEquivalent: \"\")",
                             in: section), 1)
        XCTAssertEqual(count("let dismiss = NSMenuItem(title: title, action: #selector(dismissHeldFromMenu(_:)), keyEquivalent: \"\")",
                             in: section), 1)
        XCTAssertEqual(count("start.target = self", in: section), 1)
        XCTAssertEqual(count("end.target = self", in: section), 1)
        XCTAssertEqual(count("dismiss.target = self", in: section), 1)
    }

    /// The clock is the one the menu's other times are shown with, so a time reads alike
    /// in every line, and the section builds none of its own.
    func testTheMenusClockIsTheOneTheOtherLinesUse() throws {
        let app = try code("AppDelegate.swift")
        XCTAssertEqual(count("private static let clock: DateFormatter = {", in: app), 1)
        XCTAssertEqual(count("DateFormatter(", in: app), 1, "one formatter in the app, and the snooze's lines share it")
        let section = try body(of: "private func addSnoozeSection(to menu: NSMenu) {", in: app)
        XCTAssertEqual(count("Self.clock.string(from:)", in: section), 1)
        XCTAssertFalse(section.contains("DateFormatter"))
        XCTAssertFalse(section.contains("dateFormat"))
    }

    // MARK: Dismiss, and the two choices

    /// Dismiss hands the controller the summary its own line was made from, which the item
    /// carries from when the menu was built, and not the one held now: a match held while
    /// the menu was open is not on the line the user saw, and a Dismiss that read the
    /// summary at the click would take it out unseen (Ruling 22). An item that carries
    /// nothing dismisses nothing.
    func testDismissPassesTheSummaryItsOwnLineWasMadeFromAndReadsNoOtherAtTheClick() throws {
        let app = try code("AppDelegate.swift")
        XCTAssertEqual(trimmed(try body(of: "@objc private func dismissHeldFromMenu(_ sender: NSMenuItem) {", in: app)), lines([
            "guard let shown = sender.representedObject as? HeldSummary else { return }",
            "snooze.dismissSummary(shown: shown)",
        ]))
        XCTAssertEqual(count("dismissSummary(", in: app), 1, "no other place dismisses")
        XCTAssertEqual(count("dismiss.representedObject = shown", in: app), 1)
        XCTAssertEqual(count("shown", in: try body(of: "private func addSnoozeSection(to menu: NSMenu) {", in: app)), 2,
                       "bound by the case and carried by the item, and nothing else")
    }

    /// A snooze is started in one place, with the length the chosen item carries, and the
    /// moment on-call mode ended one is cleared first, which the core cannot do for itself:
    /// it is not told of a snooze that starts and ends after the moment, and the line would
    /// come back for it. The moment is in memory, set by the one arm that ends a snooze for
    /// on-call mode, cleared where one starts and handed to the menu, and kept nowhere.
    func testASnoozeIsStartedInOnePlaceAndClearsTheMomentOnCallEndedOne() throws {
        let app = try code("AppDelegate.swift")
        XCTAssertEqual(trimmed(try body(of: "@objc private func startSnoozeFromMenu(_ sender: NSMenuItem) {", in: app)), lines([
            "guard let duration = sender.representedObject as? SnoozeDuration else { return }",
            "snoozeEndedByOnCallAt = nil",
            "snooze.start(duration)",
        ]))
        XCTAssertEqual(count("snooze.start(", in: app), 1)
        XCTAssertEqual(count("private var snoozeEndedByOnCallAt: Date?", in: app), 1)
        XCTAssertEqual(count("snoozeEndedByOnCallAt = nil", in: app), 1)
        XCTAssertEqual(count("snoozeEndedByOnCallAt = Date()", in: app), 1, "set by the arm for the step, and by nothing else")
        XCTAssertEqual(count("endedByOnCallAt: snoozeEndedByOnCallAt,", in: app), 1)
        XCTAssertEqual(count("snoozeEndedByOnCallAt", in: app), 4, "declared, set, cleared and handed to the menu")
        for file in try AppSources.fileNames() where file != "AppDelegate.swift" {
            XCTAssertFalse(try code(file).contains("snoozeEndedByOnCallAt"), "\(file): it is not saved")
        }
    }

    /// Ending from the menu is the user's word, and it announces nothing: the end is the
    /// controller's `end()`, called from the menu's item and from the arm of the on-call
    /// switch, and from nowhere else.
    func testASnoozeIsEndedInTwoPlacesTheItemAndTheOnCallArmAndNeitherSoundsAnything() throws {
        let app = try code("AppDelegate.swift")
        XCTAssertEqual(trimmed(try body(of: "@objc private func endSnoozeFromMenu() {", in: app)), "snooze.end()")
        XCTAssertEqual(count("snooze.end()", in: app), 2, "the item, and the arm that carries out the step of the on-call switch")
        XCTAssertEqual(count("#selector(endSnoozeFromMenu)", in: app), 1)
    }

    // MARK: The icon

    func testTheIconReadsTheSnoozeForItsTwoFactsAndNothingElse() throws {
        let app = try code("AppDelegate.swift")
        let glyph = try body(of: "private func rebuildGlyph() {", in: app)
        XCTAssertEqual(count("snooze.", in: glyph), 2)
        XCTAssertEqual(count("snoozeEndsAt: snooze.endsAt,", in: glyph), 1)
        XCTAssertEqual(count("heldSummary: snooze.summary,", in: glyph), 1)
        XCTAssertEqual(count("snooze.endsAt", in: app), 2, "the icon's, and the menu's")
        XCTAssertEqual(count("snooze.summary", in: app), 2, "the icon's, and the menu's")
        XCTAssertFalse(glyph.contains("snoozeEndedByOnCallAt"), "the line that says on-call ended one is the menu's")
    }

    // MARK: The one sound, and no word

    /// A snooze that ran out having held something says so with the beep, which follows
    /// Alert volume (Ruling 12), and nothing else of the snooze makes a sound: not the
    /// redraw, not Dismiss, not a choice, not ending it, and not the arm of the switch.
    func testTheBeepIsTheControllersAnnouncementAndNoOtherPlaceOfTheSnoozeSoundsAnything() throws {
        let app = try code("AppDelegate.swift")
        XCTAssertEqual(count("announce:", in: app), 1)
        XCTAssertEqual(count("announce: { NSSound.beep() })", in: app), 1)
        XCTAssertEqual(count("NSSound.beep()", in: app), 2, "the watch's, and the announcement")
        for signature in Self.sections {
            XCTAssertFalse(try body(of: signature, in: app).contains("NSSound"), signature)
        }
        XCTAssertFalse(try body(of: OnCallWiringTests.carryOut, in: app).contains("NSSound"))
        for file in try AppSources.fileNames() where !["AppDelegate.swift", "HealthAlarm.swift"].contains(file) {
            XCTAssertFalse(try code(file).contains("NSSound"), "\(file) makes a sound of its own")
        }
        for word in ["NSSound", "beep", "play(", "speak("] {
            XCTAssertFalse(try code("SnoozeStore.swift").contains(word), word)
        }
    }

    /// The words of the snooze's menu and summary, taken from the core's constants and not
    /// typed here: every whole sentence, and the stems that no other line of the app holds.
    private static let whole = [SnoozeText.menuTitle, SnoozeText.endTitle, SnoozeText.dismissTitle,
                                SnoozeText.activeStem, SnoozeText.stillAlertingStem, SnoozeText.heldStem,
                                SnoozeText.heldOneMatchStem, SnoozeText.ruleSwitchLabel, SnoozeText.onCallNote,
                                SnoozeText.endedByOnCall, SnoozeText.quietsNoRules, SnoozeText.unreadableSentence,
                                SnoozeText.unreadableEnding, SnoozeText.ruleNotFound]
        + SnoozeDuration.allCases.map(SnoozeText.durationTitle)
    private static let stems = ["snooze", "dismiss", "held while", "still alerting", "quiets "]

    /// Every literal in `source` that holds one of the snooze's whole sentences or one of its
    /// stems, in any case, comments aside.
    private func typedSnoozeWords(in source: String) -> [String] {
        SwiftLiteralScanner.literals(in: source).map(\.text).filter { text in
            !text.isEmpty && (Self.whole.contains { text.contains($0) } || Self.stems.contains { text.lowercased().contains($0) })
        }
    }

    /// Every title and line the snooze shows is a `SnoozeText` constant or function, and
    /// the app types none: no literal in any file of the target holds a snooze word, and
    /// none holds one of the core's whole sentences back (Ruling 18).
    func testNoFileOfTheAppTypesAWordOfTheSnoozesMenuOrSummary() throws {
        for file in try AppSources.fileNames() {
            XCTAssertEqual(typedSnoozeWords(in: try XCTUnwrap(AppSources.read(file), file)), [], file)
        }
    }

    /// The test above can fail: each way of typing a snooze word into a file of the app is
    /// found by the same reading, and a line that has none is not.
    func testTheReadingThatRefusesATypedSnoozeWordFindsEachWayOfTypingOne() {
        let typed = [
            (#"menu.addItem(withTitle: "Snoozed until 15:30", action: nil, keyEquivalent: "")"#, "Snoozed until 15:30"),
            (#"let dismiss = NSMenuItem(title: "Dismiss", action: nil, keyEquivalent: "")"#, "Dismiss"),
            (#"submenu.addItem(withTitle: "For 15 minutes", action: nil, keyEquivalent: "")"#, "For 15 minutes"),
            (#"item.toolTip = "6 matches held while snoozed""#, "6 matches held while snoozed"),
            (#"let end = "End Snooze""#, "End Snooze"),
            (#"let still = "Still alerting: On-call mentions""#, "Still alerting: On-call mentions"),
            (#"let none = "Snooze quiets no rules yet""#, "Snooze quiets no rules yet"),
        ]
        for (source, word) in typed {
            XCTAssertEqual(typedSnoozeWords(in: source), [word], source)
        }
        XCTAssertEqual(typedSnoozeWords(in: #"menu.addItem(withTitle: "Reload Rules", action: nil, keyEquivalent: "")"#), [])
        XCTAssertEqual(typedSnoozeWords(in: "// menu.addItem(withTitle: \"Dismiss\")"), [], "a comment is not a word shown")
    }
}
