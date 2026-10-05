import XCTest
@testable import NotificationCore

/// How the app target carries out what the core decides about on-call mode (M5
/// plan, Ruling 10): the switch, the watch, the menu, the icon and the window.
///
/// The app target has no tests, and what the core cannot hold is the wiring: that
/// the watch is asked in every place its inputs are read, that each effect of the
/// switch does what it names, that the menu's lines come from the findings and not
/// from a fact the app made up, and that every fact the icon depends on is the one
/// read for it. Swap any of them and the app builds without a warning, and a refused
/// rule after a reload would go unsounded, or the icon would claim a state nothing
/// established. So these tests read the app's sources, as `PowerHoldWiringTests` and
/// `ViewLiteralsTests` do, and hold each place to what it is meant to say. They start
/// nothing, sound nothing and open no window.
final class OnCallWiringTests: XCTestCase {
    private func code(_ file: String) throws -> String {
        PowerHoldWiringTests.code(of: try XCTUnwrap(AppSources.read(file),
                                                    "\(file) cannot be read at \(AppSources.directory.path)"))
    }

    private func count(_ needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    /// Where each effect of the switch is carried out, one arm each.
    static let carryOut = "private func carryOut(_ effect: OnCallSwitch.Effect, turningOn: Bool) async {"

    /// The text between the braces of the body whose opening line is `signature`,
    /// which ends in its `{`. Strings in the functions read here hold no braces.
    static func body(of signature: String, in code: String) -> String? {
        guard code.components(separatedBy: signature).count == 2, let found = code.range(of: signature) else { return nil }
        var depth = 0
        var start: String.Index?
        var index = code.index(before: found.upperBound)
        while index < code.endIndex {
            switch code[index] {
            case "{":
                depth += 1
                if start == nil { start = code.index(after: index) }
            case "}":
                depth -= 1
                if depth == 0, let start { return String(code[start..<index]) }
            default: break
            }
            index = code.index(after: index)
        }
        return nil
    }

    private func body(of signature: String, in code: String) throws -> String {
        try XCTUnwrap(Self.body(of: signature, in: code), "\(signature) is not in the source exactly once, or is not closed")
    }

    private func position(of needle: String, in text: String) throws -> String.Index {
        try XCTUnwrap(text.range(of: needle), "\(needle) is not there").lowerBound
    }

    /// How many times these lines stand one directly after another, whole lines
    /// each, in `text`, which is code as `code(_:)` reads it. A line that merely
    /// begins or ends like one of them does not count.
    private func run(_ lines: [String], in text: String) -> Int {
        count("\n" + lines.joined(separator: "\n") + "\n", in: "\n" + text + "\n")
    }

    private func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func testTheBodyReaderFindsABodyByItsBracesAndOnlyWhenTheSignatureIsUnique() throws {
        let source = "func a() {\nif x { y() }\nz()\n}\nfunc b() {\nw()\n}"
        XCTAssertEqual(Self.body(of: "func a() {", in: source), "\nif x { y() }\nz()\n")
        XCTAssertEqual(Self.body(of: "func b() {", in: source), "\nw()\n")
        XCTAssertNil(Self.body(of: "func c() {", in: source))
        XCTAssertNil(Self.body(of: "func a() {", in: source + "\nfunc a() {\n}"), "two of them is not one")
    }

    // MARK: The watch is asked wherever its inputs are read

    /// O5 part 2: a finding the health alarm cannot see sounds after a relaunch that
    /// restored the mode, and after every reload and save, so each of those ends in
    /// the watch. A save and Reload Rules both end in `reloadRules()`, and so does
    /// launch.
    func testTheWatchIsAskedAfterEveryReloadAfterEveryHealthRefreshAtASwitchAndWhenTheCheckComesToTheFront() throws {
        let app = try code("AppDelegate.swift")

        let reload = try body(of: "private func reloadRules() {", in: app)
        XCTAssertLessThan(try position(of: "capture.pipeline.setRules(ruleStore.rules)", in: reload),
                          try position(of: "evaluateOnCallWatch()", in: reload),
                          "the watch looks at the rules now in effect, not the ones before")

        let refresh = try body(of: "private func refreshHealth(runCanary: Bool) async {", in: app)
        XCTAssertLessThan(try position(of: "health = HealthEvaluator.evaluate(healthInputs())", in: refresh),
                          try position(of: "evaluateOnCallWatch()", in: refresh),
                          "the watch looks at the health just read")

        let effect = try body(of: Self.carryOut, in: app)
        XCTAssertEqual(count("case .evaluateWatch: evaluateOnCallWatch()", in: effect), 1)

        // Its declaration and the four calls that read a status of their own, the
        // reload, the health refresh, the switch and the check window coming to the
        // front (`testComingToTheFrontAsksTheWatchWhichListsWhatTheWindowShowsAndRunsNoSelfTest`):
        // no other place asks without a status of its own, and none of these is
        // missing. The places that have read one share it, and are held in
        // `testEveryReadOfTheLoginItemsStatusIsFollowedByTheWatchBeingAskedAboutThatRead`.
        XCTAssertEqual(count("evaluateOnCallWatch()", in: app), 5)
        XCTAssertEqual(count("evaluateOnCallWatch()", in: reload), 1)
        XCTAssertEqual(count("evaluateOnCallWatch()", in: refresh), 1)
        XCTAssertEqual(count("evaluateOnCallWatch(loginItemStatus:", in: app), 6,
                       "its declaration, the call that reads the status, the menu's two builds, the item that opens the check and Settings' model's reads")
    }

    /// Ruling 9: the watch is asked each time the login item's status is read, and
    /// asked with that read, so that what it holds is never older than the last read
    /// and a finding that went and came back between two health refreshes sounds
    /// again. Every place that reads the status in the app delegate asks, or is
    /// followed directly by the effect that asks, and Settings' model, which reads it
    /// for an activation, for the window and for each request, hands every read it
    /// makes to the delegate, which asks.
    func testEveryReadOfTheLoginItemsStatusIsFollowedByTheWatchBeingAskedAboutThatRead() throws {
        let app = try code("AppDelegate.swift")

        // The four bodies that read the status, and what each does with it.
        XCTAssertEqual(count("LoginItem.status", in: app), 4)
        let asking = try body(of: "private func evaluateOnCallWatch() {", in: app)
        XCTAssertEqual(trimmed(asking), "evaluateOnCallWatch(loginItemStatus: LoginItem.status)")
        let menu = try body(of: "func menuNeedsUpdate(_ menu: NSMenu) {", in: app)
        XCTAssertEqual(count("LoginItem.status", in: menu), 1)
        XCTAssertEqual(count("evaluateOnCallWatch(loginItemStatus: loginItemStatus)", in: menu), 2)
        let show = try body(of: "@objc private func showOnCallCheck() {", in: app)
        XCTAssertEqual(count("LoginItem.status", in: show), 1)
        XCTAssertEqual(count("evaluateOnCallWatch(loginItemStatus: loginItemStatus)", in: show), 1)
        // The fourth is the switch's check for an urgent finding, which is not the
        // watch's: the effect listed straight after it is, and asks with its own read.
        let reading = try body(of: "private func currentFindings() -> [OnCallCheck.Finding] {", in: app)
        XCTAssertEqual(trimmed(reading), "currentFindings(loginItemStatus: LoginItem.status)")
        XCTAssertEqual(count("currentFindings()", in: app), 2, "its declaration and the switch's one check")
        let effect = try body(of: Self.carryOut, in: app)
        XCTAssertEqual(count("currentFindings()", in: effect), 1)
        XCTAssertEqual(OnCallSwitch.effectsAfterSelfTestReturns(turningOn: true, snoozeActive: false, stillOn: true),
                       [.openCheckWindowIfUrgent, .evaluateWatch], "the check for an urgent finding is followed by the ask")

        // Settings' model reads it for an activation, for the window and for each request,
        // and the delegate asks with every one: the hook is set once, at launch, to ask
        // with the status it is handed, before the first reload asks and before anything
        // is read that could need it.
        let launch = try body(of: "func applicationDidFinishLaunching(_ notification: Notification) {", in: app)
        let hook = "settingsModel.onStatusRead = { [weak self] status in self?.evaluateOnCallWatch(loginItemStatus: status) }"
        XCTAssertEqual(count(hook, in: app), 1)
        XCTAssertEqual(count(hook, in: launch), 1)
        XCTAssertLessThan(try position(of: hook, in: launch), try position(of: "reloadRules()", in: launch))
        XCTAssertEqual(count("onStatusRead", in: app), 1, "set once and never called by the delegate")
    }

    /// The menu is another place the watch is asked (Ruling 9: when the menu reads the
    /// login item). It is asked with the one status the menu read for its own lines, once
    /// for each of the two builds the menu makes, after the build, so that the menu is
    /// not made to wait on a window and the watch looks at the health it has just
    /// re-evaluated. Asking again beside a health refresh is idempotent
    /// (`OnCallWatchTests`).
    ///
    /// And the gate is told the menu is open between the build and the ask, in both: the
    /// watch can open the check window, which activates the app, and the window's coming to
    /// the front asks for a rebuild of the menu. Asked while the gate was shut that would
    /// empty the menu being shown and fill it again with no login item status, and the
    /// lines made from the one read would be gone. With the gate open the rebuild is held
    /// and made when the menu closes (`MenuRebuildGateTests`).
    func testTheMenuAsksTheWatchAsItOpensWithTheStatusItReadForItsOwnLinesAndOnlyOnceItsGateIsOpen() throws {
        let app = try code("AppDelegate.swift")
        let opens = try body(of: "func menuNeedsUpdate(_ menu: NSMenu) {", in: app)
        XCTAssertEqual(count("evaluateOnCallWatch(loginItemStatus: loginItemStatus)", in: opens), 2,
                       "one for each of its two builds, handed the status it read")
        XCTAssertEqual(count("evaluateOnCallWatch(", in: opens), 2, "and no ask that reads a status of its own")
        XCTAssertEqual(run(["rebuildMenu(loginItemStatus: loginItemStatus)",
                            "menuGate.menuOpened()",
                            "evaluateOnCallWatch(loginItemStatus: loginItemStatus)"], in: opens), 2,
                       "each after the build it follows, with the gate told the menu is open between the two")
        XCTAssertEqual(count("menuGate.menuOpened()", in: opens), 3, "before each ask, and the one every path out of the function makes")
        XCTAssertEqual(count("menuGate.menuClosed()", in: opens), 1, "once, before either build, so that they go ahead")
        XCTAssertLessThan(try position(of: "menuGate.menuClosed()", in: opens),
                          try position(of: "rebuildMenu(loginItemStatus: loginItemStatus)", in: opens))
        // The build made once nothing has been probed asks, with health still unknown, and
        // the one made after health is evaluated asks after that, so the watch never looks
        // at a health older than the build it follows.
        let evaluated = try XCTUnwrap(opens.range(of: "health = HealthEvaluator.evaluate(healthInputs())")).upperBound
        XCTAssertEqual(count("evaluateOnCallWatch(loginItemStatus: loginItemStatus)", in: String(opens[..<evaluated])), 1)
        XCTAssertEqual(count("evaluateOnCallWatch(loginItemStatus: loginItemStatus)", in: String(opens[evaluated...])), 1,
                       "the watch looks at the health just evaluated")
    }

    /// The app asks the watch with whether it is on call and what stood before, keeps
    /// the answer's state, and sounds and opens only as it says.
    func testTheWatchsAnswerIsCarriedOutAsItIsGiven() throws {
        let app = try code("AppDelegate.swift")
        let watch = try body(of: "private func evaluateOnCallWatch(loginItemStatus: LoginItemStatus) {", in: app)
        let expected = [
            "let findings = currentFindings(loginItemStatus: loginItemStatus)",
            "let decision = OnCallWatch.decide(onCall: onCall.state.isOn, findings: findings, previous: onCallWatchState)",
            "onCallWatchState = decision.state",
            "if decision.beep { NSSound.beep() }",
            "if decision.openWindow {\nonCallCheck.show(findings: findings)\n} else {\nonCallCheck.refresh(findings: findings)\n}",
        ].joined(separator: "\n")
        XCTAssertEqual(watch.trimmingCharacters(in: .whitespacesAndNewlines), expected)
        // The health alarm's own beep is in HealthAlarm, and this one is the watch's.
        XCTAssertEqual(count("NSSound.beep()", in: app), 1)
        // The ask that reads no status of its own reads one, once, and hands it down.
        let reading = try body(of: "private func evaluateOnCallWatch() {", in: app)
        XCTAssertEqual(trimmed(reading), "evaluateOnCallWatch(loginItemStatus: LoginItem.status)")
    }

    // MARK: The switch

    func testEachEffectThatOpensTheWindowOrWatchesDoesWhatItNames() throws {
        let app = try code("AppDelegate.swift")
        let turn = try body(of: Self.carryOut, in: app)
        XCTAssertEqual(count("case .resetWatch: onCallWatchState = OnCallWatch.State()", in: turn), 1)
        let open = [
            "case .openCheckWindowIfUrgent:",
            "let findings = currentFindings()",
            "if OnCallCheck.shouldOpenWindow(findings) { onCallCheck.show(findings: findings) }",
        ].joined(separator: "\n")
        XCTAssertEqual(count(open, in: turn), 1)
        XCTAssertEqual(count("OnCallCheck.shouldOpenWindow", in: app), 1, "asked once, at the switch")
        // Its declaration and the one arm: what the watch remembers is forgotten by
        // the switch alone, and by nothing else in the app.
        XCTAssertEqual(count("onCallWatchState = OnCallWatch.State()", in: app), 2)
    }

    /// The switch carries out what the core lists in two parts, and asks for the second
    /// after the first has returned, with whether the mode is on then and not whether it
    /// was when the switch began: the self-test is awaited, and the user can switch the
    /// mode off in the seconds it takes. Nothing else asks for the whole list, which
    /// would carry out the window and the watch whatever happened meanwhile.
    func testTheSwitchCarriesOutTheListInTwoPartsAndAsksAfterTheSelfTestWhetherTheModeIsStillOn() throws {
        let app = try code("AppDelegate.swift")
        let turn = try body(of: "private func switchOnCall(turningOn: Bool) async {", in: app)
        XCTAssertEqual(trimmed(turn), [
            "let snoozeActive = false",
            "for effect in OnCallSwitch.effectsUntilSelfTestReturns(turningOn: turningOn, snoozeActive: snoozeActive) {",
            "await carryOut(effect, turningOn: turningOn)",
            "}",
            "for effect in OnCallSwitch.effectsAfterSelfTestReturns(turningOn: turningOn, snoozeActive: snoozeActive,",
            "stillOn: onCall.state.isOn) {",
            "await carryOut(effect, turningOn: turningOn)",
            "}",
        ].joined(separator: "\n"))
        XCTAssertEqual(count("OnCallSwitch.effects(", in: app), 0, "the whole list is not carried out in one go")
        XCTAssertEqual(count("stillOn: onCall.state.isOn", in: app), 1, "read once, after the first part")
        XCTAssertEqual(count("carryOut(", in: app), 3, "its declaration and the two loops")
        XCTAssertLessThan(try position(of: "OnCallSwitch.effectsUntilSelfTestReturns", in: turn),
                          try position(of: "OnCallSwitch.effectsAfterSelfTestReturns", in: turn))
    }

    /// The menu and the icon are drawn by an effect of the list, once, where the list
    /// puts it, so that turning on shows at once and turning off, which runs no
    /// self-test to end in a rebuild, shows too. The switch draws nothing of its own.
    func testTheSwitchDrawsTheMenuAndTheIconOnlyWhereTheListSaysAndNowhereElse() throws {
        let app = try code("AppDelegate.swift")
        let turn = try body(of: "private func switchOnCall(turningOn: Bool) async {", in: app)
        XCTAssertFalse(turn.contains("rebuildMenu"), "an effect draws it, where the list puts it")
        let effect = try body(of: Self.carryOut, in: app)
        XCTAssertEqual(count("case .rebuildMenuAndIcon: rebuildMenu()", in: effect), 1)
        // Each arm is one effect, and the self-test is the one that waits.
        XCTAssertEqual(count("case .runSelfTestNow: await refreshHealthAndFollowUp()", in: effect), 1)
        XCTAssertEqual(count("await", in: effect), 1, "no other effect waits")
    }

    /// The app has no snooze to end yet, so the arm for the step that ends one does
    /// nothing and the switch says no snooze is running, and the two stand or fall
    /// together: an arm that did nothing beside a switch that said one runs would
    /// leave the user snoozed after they said they were on call, and a switch that
    /// said none runs beside an arm that ended one would never reach it. The commit
    /// that gives the app its controller changes both, and this is where it is told
    /// if it changes only one (M5 plan, Task 4, O10).
    func testTheStepThatEndsASnoozeDoesNothingExactlyWhileTheSwitchSaysNoneIsRunning() throws {
        let app = try code("AppDelegate.swift")
        let effect = try body(of: Self.carryOut, in: app)
        let turn = try body(of: "private func switchOnCall(turningOn: Bool) async {", in: app)
        XCTAssertEqual(count("case .endSnooze", in: effect), 1, "one arm for the step, and the switch has no other place for it")
        let armDoesNothing = count("case .endSnooze: break", in: effect) == 1
        let switchSaysNoneRuns = count("let snoozeActive = false", in: turn) == 1
        XCTAssertEqual(armDoesNothing, switchSaysNoneRuns,
                       "the arm and what the switch says a snooze is must change together")
        XCTAssertEqual(count("snoozeActive", in: turn), 5, "read once and handed, as it was, to both parts of the list")
    }

    func testTheMenuItemSwitchesTheModeToTheOppositeOfTheStateItWasChosenIn() throws {
        let app = try code("AppDelegate.swift")
        let toggle = try body(of: "@objc private func toggleOnCall() {", in: app)
        XCTAssertEqual(toggle.trimmingCharacters(in: .whitespacesAndNewlines),
                       "let turningOn = !onCall.state.isOn\nTask { @MainActor in await switchOnCall(turningOn: turningOn) }")
        XCTAssertEqual(count("switchOnCall(turningOn:", in: app), 2, "its declaration and the one item that calls it")
    }

    // MARK: The menu

    func testTheMenusOnCallLinesAreWordedByTheCoreAndShownOnlyWhileOnCall() throws {
        let app = try code("AppDelegate.swift")
        let section = try body(of: "private func addOnCallSection(to menu: NSMenu, loginItemStatus: LoginItemStatus?) {", in: app)

        XCTAssertEqual(count("toggle.state = isOn ? .on : .off", in: section), 1, "the item is checked while on")
        XCTAssertLessThan(try position(of: "menu.addItem(toggle)", in: section),
                          try position(of: "guard isOn else { return }", in: section), "the item is always there")
        let lines = try XCTUnwrap(section.range(of: "guard isOn else { return }")).upperBound
        let whileOn = String(section[lines...])

        XCTAssertEqual(count("AlertMenuText.onCallSinceLine(since: onCall.state.since,", in: whileOn), 1)
        XCTAssertEqual(count("allowsSelfTest: lastSelfTestConditions?.allowsSelfTest,", in: whileOn), 1,
                       "the cadence is said only as the health check has said self-tests can run")
        XCTAssertEqual(count("AlertMenuText.awakeLine(held: onCallPower.isHeld)", in: whileOn), 1)
        XCTAssertEqual(count("for finding in OnCallCheck.menuLines(currentFindings(loginItemStatus: loginItemStatus)) {", in: whileOn), 1,
                       "from the status this build was handed, and no read of its own")
        XCTAssertFalse(section.contains("LoginItem.status"), "a rebuild reads nothing: it is handed what was read")
        XCTAssertEqual(count("menu.addItem(withTitle: finding.menuTitle, action: nil, keyEquivalent: \"\")", in: whileOn), 1)
        XCTAssertEqual(count("let check = NSMenuItem(title: OnCallText.checkItemTitle, action: #selector(showOnCallCheck),", in: whileOn), 1)
        XCTAssertFalse(section.contains("OutputState"), "the menu reads no fact of its own")
    }

    /// The section is built beneath the health line and its cause, which is where
    /// Ruling 17 puts it, and above the capture count.
    func testTheOnCallSectionIsBeneathTheHealthLineAndItsCause() throws {
        let app = try code("AppDelegate.swift")
        let items = try body(of: "private func rebuildMenuItems(loginItemStatus: LoginItemStatus?) {", in: app)
        let health = try position(of: "menu.addItem(withTitle: healthTitle, action: nil, keyEquivalent: \"\")", in: items)
        let cause = try position(of: "advice.representedObject = cause.isDeliveryFault", in: items)
        let onCall = try position(of: "addOnCallSection(to: menu, loginItemStatus: loginItemStatus)", in: items)
        let captured = try position(of: "let count = capture.captureCount", in: items)
        XCTAssertLessThan(health, cause)
        XCTAssertLessThan(cause, onCall)
        XCTAssertLessThan(onCall, captured)
        XCTAssertLessThan(try position(of: "addEscalationSection(to: menu)", in: items), health)
    }

    /// The item lists the findings now, made from one read of the status, and asks the
    /// watch about that same read, so that what the user is shown and what the watch
    /// holds are from one read (Ruling 9).
    func testTheItemThatOpensTheCheckListsTheFindingsNowFromOneReadAndAsksTheWatchAboutIt() throws {
        let app = try code("AppDelegate.swift")
        let show = try body(of: "@objc private func showOnCallCheck() {", in: app)
        XCTAssertEqual(trimmed(show), [
            "let loginItemStatus = LoginItem.status",
            "onCallCheck.show(findings: currentFindings(loginItemStatus: loginItemStatus))",
            "evaluateOnCallWatch(loginItemStatus: loginItemStatus)",
        ].joined(separator: "\n"))
    }

    // MARK: What the findings read

    /// The check reads the login item from a status it is handed, as the core makes of
    /// it: whether the app starts at login, and what Settings would show for it, which
    /// is the model's, from the status and from nothing the check keeps. Nothing read
    /// is nothing said. The status is read in one place for a pass that asks, and a
    /// pass that has read one hands it down.
    func testTheFindingsAreMadeFromWhatTheStoresHoldAndTheLoginItemStatusTheyAreHanded() throws {
        let app = try code("AppDelegate.swift")
        let reading = try body(of: "private func currentFindings() -> [OnCallCheck.Finding] {", in: app)
        XCTAssertEqual(trimmed(reading), "currentFindings(loginItemStatus: LoginItem.status)")
        let findings = try body(of: "private func currentFindings(loginItemStatus: LoginItemStatus?) -> [OnCallCheck.Finding] {",
                                in: app)
        let expected = [
            "refreshAudibility()",
            "let pipeline = capture.pipeline",
            "let apps = MuteWalkthrough.appsToMute(rules: pipeline.rules, alsoSounded: pipeline.appsThatAlerted)",
            "return OnCallCheck.findings(OnCallCheck.Inputs(",
            "health: health,",
            "unconfirmedMutedApps: muteChecklist.checklist.unconfirmed(among: apps),",
            "outputSilent: outputSilent,",
            "alertVolume: alertVolume,",
            "reach: RuleReach(rules: pipeline.rules),",
            "ruleStatus: ruleStore.status,",
            "shortcutWarnings: ruleStore.warnings,",
            "startsAtLogin: loginItemStatus.map(LaunchAtLogin.startsAtLogin(status:)),",
            "loginItem: loginItemStatus.map(settingsModel.state(for:))))",
        ].joined(separator: "\n")
        XCTAssertEqual(findings.trimmingCharacters(in: .whitespacesAndNewlines), expected)
        XCTAssertFalse(app.contains("loginItemByHand"), "the by-hand word is not built (Ruling 15, Task 6)")
    }

    /// Alert volume is read from the preference the core names, as a number or
    /// nothing, and the app writes none.
    func testAlertVolumeIsReadFromTheCoresKeyAndTheOutputFromTheDevice() throws {
        let app = try code("AppDelegate.swift")
        let read = try body(of: "private func refreshAudibility() {", in: app)
        let expected = [
            "outputSilent = OutputState.current().isEffectivelySilent",
            "alertVolume = BeepAudibility.alertVolume(",
            "fromStored: UserDefaults.standard.object(forKey: BeepAudibility.preferenceKey))",
        ].joined(separator: "\n")
        XCTAssertEqual(read.trimmingCharacters(in: .whitespacesAndNewlines), expected)
        XCTAssertFalse(app.contains("com.apple.sound"), "the key is the core's")
        XCTAssertFalse(app.contains("beep.volume"))
    }

    func testTheOutputAndAlertVolumeAreReadAtEachHealthRefreshAndEachMenuBuildNotAtEachPulse() throws {
        let app = try code("AppDelegate.swift")
        // Through the findings the watch makes at each health refresh, and where the
        // menu is opened and where its items are rebuilt.
        let opened = try body(of: "func menuNeedsUpdate(_ menu: NSMenu) {", in: app)
        XCTAssertEqual(count("refreshAudibility()", in: opened), 1)
        let items = try body(of: "private func rebuildMenuItems(loginItemStatus: LoginItemStatus?) {", in: app)
        XCTAssertEqual(count("refreshAudibility()", in: items), 1)
        let glyph = try body(of: "private func rebuildGlyph() {", in: app)
        XCTAssertFalse(glyph.contains("refreshAudibility()"), "the icon uses what was last read")
        XCTAssertFalse(glyph.contains("OutputState"))
        XCTAssertFalse(glyph.contains("UserDefaults"))
    }

    // MARK: The icon

    func testTheIconIsWhatStatusGlyphSaysFromEveryFactTheAppHasRead() throws {
        let app = try code("AppDelegate.swift")
        let glyph = try body(of: "private func rebuildGlyph() {", in: app)
        let expected = [
            "guard let button = statusItem?.button else { return }",
            "let appearance = StatusGlyph.appearance(",
            "for: StatusGlyph.Facts(",
            "health: health,",
            "healthAlarmState: alarm.state,",
            "now: Date(),",
            "ruleStatusProblem: ruleStore.status.isProblem,",
            "shortcutWarningCount: ruleStore.warnings.count,",
            "unresolvedAlertFailure: capture.pipeline.unresolvedAlertFailure != nil,",
            "unresolvedShortcutFailure: capture.pipeline.unresolvedShortcutFailure != nil,",
            "outputSilent: outputSilent,",
            "anEnabledRuleSounds: capture.pipeline.rules.contains(where: \\.alertsAloud),",
            "alertVolume: alertVolume,",
            "escalationLive: escalations.hasLiveEscalations,",
            "snoozeEndsAt: nil,",
            "heldSummary: HeldSummary(),",
            "onCall: onCall.state.isOn,",
            "selfTestsRunning: lastSelfTestConditions?.allowsSelfTest),",
            "pulse: glyphPulse,",
            "time: Self.clock.string(from:))",
            "button.image = NSImage(systemSymbolName: appearance.symbol, accessibilityDescription: appearance.description)",
            "?? NSImage(systemSymbolName: StatusGlyph.fallbackSymbol, accessibilityDescription: appearance.description)",
            "button.toolTip = appearance.tooltip",
        ].joined(separator: "\n")
        XCTAssertEqual(glyph.trimmingCharacters(in: .whitespacesAndNewlines), expected)
    }

    // MARK: The check window

    /// The button runs one self-test and arms nothing after it. The follow-up two minutes
    /// later is the switch's and a waking's, where the plan names it, and the button's
    /// note says one banner: a second one nobody asked for would be a banner on a shared
    /// screen, and it would not be in the note.
    func testTheChecksButtonRunsOneSelfTestNowAndArmsNoFollowUpAndTheWindowIsMadeOnce() throws {
        let app = try code("AppDelegate.swift")
        let made = try body(of: "private lazy var onCallCheck: OnCallCheckWindowController = {", in: app)
        XCTAssertEqual(trimmed(made), [
            "let controller = OnCallCheckWindowController()",
            "controller.model.checkNow = { [weak self] in await self?.refreshHealth(runCanary: true) }",
            "controller.model.perform = { [weak self] action in self?.performLoginItemAction(action) }",
            "controller.model.messageOfLastPress = { [weak self] in self?.settingsModel.message }",
            "controller.onBecomeKey = { [weak self] in self?.refreshOnCallCheckFromWhatIsKnown() }",
            "return controller",
        ].joined(separator: "\n"))
        XCTAssertFalse(made.contains("FollowUp"))
        XCTAssertEqual(count("OnCallCheckWindowController()", in: app), 1)
    }

    /// Coming to the front brings what the window lists up to date, from what can be
    /// read at once, as opening the menu does, and never runs a self-test: looking at
    /// the window posts no banner. It is the window's delegate that says it came to
    /// the front, and the app that says what to read. It reads the login item's status,
    /// which asks the watch about that read (Ruling 9), and the watch lists the findings
    /// in the window, so a finding that came while the window was behind another is
    /// sounded for once, now, and not a second time at the next health refresh.
    func testComingToTheFrontAsksTheWatchWhichListsWhatTheWindowShowsAndRunsNoSelfTest() throws {
        let app = try code("AppDelegate.swift")
        let refresh = try body(of: "private func refreshOnCallCheckFromWhatIsKnown() {", in: app)
        XCTAssertEqual(trimmed(refresh), [
            "if delivery != nil { health = HealthEvaluator.evaluate(healthInputs()) }",
            "evaluateOnCallWatch()",
            "rebuildMenu()",
        ].joined(separator: "\n"))
        for forbidden in ["canary", "runCanary", "refreshHealth", "FollowUp", "await"] {
            XCTAssertFalse(refresh.contains(forbidden), "it runs no self-test: \(forbidden)")
        }
        XCTAssertEqual(count("refreshOnCallCheckFromWhatIsKnown()", in: app), 2, "its declaration and the window's hook")

        let controller = try code("OnCallCheckWindowController.swift")
        XCTAssertEqual(count("final class OnCallCheckWindowController: NSObject, NSWindowDelegate {", in: controller), 1)
        XCTAssertEqual(count("window.delegate = self", in: controller), 1)
        XCTAssertEqual(trimmed(try body(of: "func windowDidBecomeKey(_ notification: Notification) {", in: controller)),
                       "onBecomeKey()")
        XCTAssertEqual(count("var onBecomeKey: () -> Void = {}", in: controller), 1)
        // It lists nothing itself: the watch does, from the read it was asked with, and
        // asking again with what stands does nothing (`OnCallWatchTests`), so the window
        // opened by the watch, which comes to the front, asks for nothing twice.
        XCTAssertFalse(refresh.contains("onCallCheck."))
    }

    /// It is an ordinary window and never a modal (Ruling 22): capture goes on behind
    /// it, and nothing the app opens waits on the user. It takes its title from
    /// `WindowTitles` and is activated as the Inspector is.
    func testTheCheckWindowIsOrdinaryTitledByWindowTitlesAndActivatedBeforeItIsOrderedFront() throws {
        for file in ["OnCallCheckWindowController.swift", "OnCallCheckView.swift"] {
            let source = try code(file)
            XCTAssertFalse(source.contains("runModal"), "\(file) is never a modal")
            XCTAssertFalse(source.contains("beginSheet"), "\(file)")
            XCTAssertFalse(source.contains("NSAlert"), "\(file)")
        }
        let controller = try code("OnCallCheckWindowController.swift")
        XCTAssertEqual(count("window.title = WindowTitles.onCallCheck", in: controller), 1)
        XCTAssertEqual(count("window.isReleasedWhenClosed = false", in: controller), 1)
        XCTAssertLessThan(try position(of: "NSApp.activate(ignoringOtherApps: true)", in: controller),
                          try position(of: "window?.makeKeyAndOrderFront(nil)", in: controller))
    }

    // MARK: The check window's model, controller and view

    /// The window is given the findings before it is made or brought forward, so a
    /// window the watch opens, or the switch, or the menu, never opens empty with a
    /// heading that says nothing: all three end in `show`. It is made only when there
    /// is none, kept, and brought forward whether it was made now or before.
    func testShowGivesTheWindowTheFindingsFirstKeepsTheWindowItMakesAndBringsAnyWindowForward() throws {
        let controller = try code("OnCallCheckWindowController.swift")
        let show = trimmed(try body(of: "func show(findings: [OnCallCheck.Finding]) {", in: controller))
        XCTAssertEqual(count("model.update(findings: findings)", in: show), 1)
        XCTAssertTrue(show.hasPrefix("model.update(findings: findings)\nif window == nil {\nlet window = NSWindow("),
                      "the list is given before the window is made")
        XCTAssertEqual(count("window.contentView = NSHostingView(rootView: OnCallCheckView(model: model))", in: show), 1,
                       "the view is of the model that is updated")
        XCTAssertTrue(show.hasSuffix("self.window = window\n}\nNSApp.activate(ignoringOtherApps: true)\nwindow?.makeKeyAndOrderFront(nil)"),
                      "the window is kept, and a window that is there is brought forward too, outside the if")
    }

    /// A refresh keeps an open window up to date and never opens a closed one: the
    /// watch refreshes it at every health refresh, and a window that popped up for
    /// each would be one the user could not close.
    func testARefreshUpdatesAWindowThatIsThereAndOpensNone() throws {
        let controller = try code("OnCallCheckWindowController.swift")
        let refresh = trimmed(try body(of: "func refresh(findings: [OnCallCheck.Finding]) {", in: controller))
        XCTAssertEqual(refresh, "guard window != nil else { return }\nmodel.update(findings: findings)")
    }

    /// The model keeps what the core said, in the core's words, and runs the button
    /// once at a time: a check that has finished always leaves the button usable.
    func testTheModelKeepsWhatTheCoreSaidAndLeavesTheButtonUsableWhenACheckEnds() throws {
        let controller = try code("OnCallCheckWindowController.swift")
        let update = trimmed(try body(of: "func update(findings: [OnCallCheck.Finding]) {", in: controller))
        XCTAssertEqual(update, [
            "lines = OnCallCheck.windowLines(findings)",
            "summary = OnCallCheck.summary(findings)",
            "hasUrgent = OnCallCheck.hasUrgent(findings)",
            "message = messageOfLastPress()",
        ].joined(separator: "\n"))
        XCTAssertFalse(controller.contains("isUrgent"), "which finding is urgent is the core's answer, not the model's")
        XCTAssertFalse(controller.contains("anythingUrgent"))

        let check = trimmed(try body(of: "func runCheck() async {", in: controller))
        XCTAssertEqual(check, [
            "guard !isChecking else { return }",
            "isChecking = true",
            "await checkNow()",
            "isChecking = false",
        ].joined(separator: "\n"))
    }

    /// The view's symbols are the core's, so a symbol typed into it would be one
    /// nothing tests: neither file may name one, and each place a symbol is drawn
    /// takes it from the answer the core gave.
    func testNeitherCheckFileNamesASymbolAndTheHeadingAndEachRowDrawTheCoresAnswer() throws {
        for file in ["OnCallCheckView.swift", "OnCallCheckWindowController.swift"] {
            let source = try code(file)
            for label in ["systemName:", "systemImage:", "systemSymbolName:"] {
                XCTAssertFalse(source.contains(label + " \""), "\(file) names a symbol with \(label)")
            }
        }
        let view = try code("OnCallCheckView.swift")

        let header = try body(of: "private var header: some View {", in: view)
        XCTAssertEqual(count("Image(systemName: OnCallCheck.headingSymbol(hasUrgent: model.hasUrgent))", in: header), 1)
        XCTAssertEqual(count(".foregroundStyle(model.hasUrgent ? Color.orange : Color.secondary)", in: header), 1)
        XCTAssertEqual(count(".accessibilityHidden(true)", in: header), 1, "the icon is not read out; the heading is")
        XCTAssertEqual(count("Text(model.summary)", in: header), 1)
        XCTAssertLessThan(try position(of: "Image(systemName:", in: header), try position(of: "Text(model.summary)", in: header))

        let row = try body(of: "private func row(_ finding: OnCallCheck.Finding) -> some View {", in: view)
        XCTAssertEqual(count("Image(systemName: finding.symbol)", in: row), 1)
        XCTAssertEqual(count(".foregroundStyle(finding.isUrgent ? Color.orange : Color.secondary)", in: row), 1)
        XCTAssertEqual(count("Text(finding.text)", in: row), 1)
        XCTAssertEqual(count(".foregroundStyle(finding.isUrgent ? Color.primary : Color.secondary)", in: row), 1)
        XCTAssertEqual(count(".accessibilityHidden(true)", in: row), 1, "the icon is not read out; the line is")
        XCTAssertLessThan(try position(of: "Image(systemName:", in: row), try position(of: "Text(finding.text)", in: row))
    }

    /// Urgency is shown by an icon that VoiceOver does not read, so each line is one
    /// element and says what the core says it should, "Urgent:" first on an urgent one.
    func testEachRowIsOneElementThatVoiceOverReadsAsTheCoreWordsIt() throws {
        let view = try code("OnCallCheckView.swift")
        let row = try body(of: "private func row(_ finding: OnCallCheck.Finding) -> some View {", in: view)
        XCTAssertEqual(run([".accessibilityElement(children: .combine)", ".accessibilityLabel(finding.spokenText)"], in: row), 1)
        XCTAssertFalse(view.contains(".accessibilityLabel(finding.text)"))
    }

    /// The button runs a self-test and checks again, is not pressed twice while one
    /// runs, shows that one does, and is not the window's default: the window opens
    /// itself and activates the app, so a Return meant for what the user was typing
    /// would post a self-test banner.
    func testTheButtonRunsTheCheckIsDisabledWhileOneRunsShowsThatItDoesAndIsNotTheDefault() throws {
        let view = try code("OnCallCheckView.swift")
        let footer = try body(of: "private var footer: some View {", in: view)
        XCTAssertEqual(run(["Button(OnCallText.checkButton) {", "Task { await model.runCheck() }", "}"], in: footer), 1)
        XCTAssertEqual(count("Task {", in: view), 1)
        XCTAssertEqual(count(".disabled(model.isChecking)", in: footer), 1)
        XCTAssertFalse(view.contains("keyboardShortcut"), "no key runs a self-test: not Return, not any other")
        XCTAssertFalse(view.contains("defaultAction"))
        XCTAssertEqual(run(["if model.isChecking {", "ProgressView().controlSize(.small)", "}"], in: footer), 1)
        XCTAssertEqual(count("Text(OnCallText.checkButtonNote)", in: footer), 1)
        let button = try position(of: "Button(OnCallText.checkButton) {", in: footer)
        XCTAssertLessThan(button, try position(of: ".disabled(model.isChecking)", in: footer),
                          "the modifier is on the button")
        XCTAssertLessThan(try position(of: ".disabled(model.isChecking)", in: footer),
                          try position(of: "Text(OnCallText.checkButtonNote)", in: footer))
    }

    /// The view lists the model's lines, one row each, between the heading and the
    /// button, and holds no word, app name or notification content of its own.
    func testTheViewListsTheModelsLinesBetweenTheHeadingAndTheButtonAndNamesNoAppOrContent() throws {
        let view = try code("OnCallCheckView.swift")
        let content = try body(of: "var body: some View {", in: view)
        XCTAssertEqual(run(["header", "Divider()", "ScrollView {"], in: content), 1)
        XCTAssertEqual(run([#"ForEach(Array(model.lines.enumerated()), id: \.offset) { _, finding in"#,
                            "VStack(alignment: .leading, spacing: 6) {", "row(finding)", "if let action = finding.action {",
                            "actionButton(action)", "if let message = model.message {", "pressMessage(message)", "}",
                            "}", "}", "}"], in: content), 1,
                       "one row each, and beneath it the button its finding carries, when it carries one, and what a press of it came to")
        XCTAssertEqual(run(["Divider()", "footer", "}"], in: content), 1)
        XCTAssertEqual(count("Text(finding.text)", in: view), 1)
        XCTAssertEqual(count("Text(model.summary)", in: view), 1)
        XCTAssertEqual(count("Text(OnCallText.checkButtonNote)", in: view), 1)
    }

    // MARK: The login finding's button

    /// The button is the user's press, and the one path that registers is Settings' own:
    /// the model that saves the choice and reads the status afterwards carries out the
    /// action the core gave the finding. The status that model reads after the request is
    /// the one it hands to the delegate, which asks the watch about it and lists the
    /// findings made from it in the window, and the menu and the icon are drawn again
    /// (O12, Ruling 9). The press chooses nothing, registers nothing, saves nothing and
    /// reads nothing itself, so the status is read once for the press.
    func testTheLoginFindingsButtonIsCarriedOutByTheSettingsModelWhoseOneReadIsSharedAndThenTheMenuIsDrawnAgain() throws {
        let app = try code("AppDelegate.swift")
        let press = try body(of: "private func performLoginItemAction(_ action: LaunchAtLogin.Action) {", in: app)
        XCTAssertEqual(trimmed(press), ["settingsModel.perform(action)", "rebuildMenu()"].joined(separator: "\n"))
        XCTAssertFalse(press.contains("evaluateOnCallWatch"), "the read after the request is the model's, and it is shared")
        XCTAssertEqual(count("performLoginItemAction(", in: app), 2, "its declaration and the one hook the window's model is given")
        XCTAssertEqual(count("settingsModel.perform(", in: app), 1, "the one path that registers is Settings' own")
        for word in ["LoginItem.", "wantedKey", "defaults", "register", "NSAlert"] {
            XCTAssertFalse(press.contains(word), "the press carries out the model's answer and nothing of its own: \(word)")
        }
        // The press is reached from the window's button alone.
        for file in try AppSources.fileNames() where file != "AppDelegate.swift" {
            XCTAssertFalse(try code(file).contains("performLoginItemAction"), file)
        }
    }

    /// The window shows the finding's button where the core gave the finding one, beneath
    /// its row, in the core's words, and nowhere else. The button is its own element and
    /// not a part of the row's, which VoiceOver reads as one, so that it can be pressed.
    /// The model chooses nothing: it hands the core's action to whoever made it.
    func testTheCheckWindowShowsTheFindingsButtonWhereTheCoreGaveOneAndInTheCoresWords() throws {
        let view = try code("OnCallCheckView.swift")
        XCTAssertEqual(count("\nButton(", in: view), 2, "the check button and a finding's, and no other")
        XCTAssertEqual(count("if let action = finding.action {", in: view), 1)
        let button = try body(of: "private func actionButton(_ action: LaunchAtLogin.Action) -> some View {", in: view)
        XCTAssertEqual(run(["Button(LaunchAtLoginText.label(for: action)) { model.perform(action) }", ".padding(.leading, 28)"],
                           in: button), 1)
        XCTAssertEqual(count("model.perform(", in: view), 1)
        let row = try body(of: "private func row(_ finding: OnCallCheck.Finding) -> some View {", in: view)
        XCTAssertFalse(row.contains("Button"), "the row is one element that VoiceOver reads")
        XCTAssertFalse(row.contains("actionButton"))

        let controller = try code("OnCallCheckWindowController.swift")
        XCTAssertEqual(count("var perform: (LaunchAtLogin.Action) -> Void = { _ in }", in: controller), 1)
        for word in ["LoginItem", "register", "UserDefaults", "SettingsModel"] {
            XCTAssertFalse(controller.contains(word), "the model chooses and carries out nothing: \(word)")
        }
    }

    /// A press of the finding's button that failed or changed nothing is not silent: what
    /// it came to is shown beneath the button that was pressed, in the core's words, and
    /// there is none unless the press made one. The model asks for it at every update and
    /// keeps nothing of it, so how long it stands is the model's that carried out the press,
    /// which drops it at the next read that no request made (`LaunchAtLoginText.message`),
    /// and the window shows nothing at the update after. The view holds no word of its own.
    func testWhatAPressCameToIsShownBeneathItsButtonInTheCoresWordsAndOnlyWhileThereIsOne() throws {
        let view = try code("OnCallCheckView.swift")
        XCTAssertEqual(count("model.message", in: view), 1, "one place shows it")
        let message = try body(of: "private func pressMessage(_ message: String) -> some View {", in: view)
        XCTAssertEqual(trimmed(message), [
            "Text(message)",
            ".font(.callout)",
            ".fixedSize(horizontal: false, vertical: true)",
            ".padding(.leading, 28)",
        ].joined(separator: "\n"), "the words are the model's, in line with the button's")
        XCTAssertEqual(count("pressMessage(", in: view), 2, "its declaration and the one place that shows it")
        XCTAssertEqual(count("Text(message)", in: view), 1)
        XCTAssertFalse(message.contains("Text(\""), "no word of its own")
        let content = try body(of: "var body: some View {", in: view)
        XCTAssertLessThan(try position(of: "actionButton(action)", in: content),
                          try position(of: "pressMessage(message)", in: content), "beneath the button")

        let controller = try code("OnCallCheckWindowController.swift")
        XCTAssertEqual(count("@Published private(set) var message: String?", in: controller), 1)
        XCTAssertEqual(count("var messageOfLastPress: () -> String? = { nil }", in: controller), 1)
        XCTAssertEqual(count("message =", in: controller), 1, "assigned at each update, in the one place, and kept nowhere else")
        XCTAssertEqual(count("messageOfLastPress()", in: controller), 1)
        XCTAssertFalse(controller.contains("message = nil"), "how long it stands is not decided here")
        XCTAssertFalse(controller.contains("LaunchAtLoginText"), "the words are the model's and the core's, carried and not made")

        // The app hands it the one model's message, which is the core's words for the
        // read after the press, and nothing else of that model.
        let app = try code("AppDelegate.swift")
        XCTAssertEqual(count("self?.settingsModel.message", in: app), 1)
        XCTAssertEqual(count("settingsModel.message", in: app), 1)
    }

    // MARK: The editor

    func testTheLadderEditorSaysBesideThePresetThatItIsNotTheMode() throws {
        let editor = try code("LadderEditorView.swift")
        XCTAssertEqual(count("if let note = EditorText.onCallPresetNote(shown: EscalationEditing.shown(for: escalation)) {", in: editor), 1)
        XCTAssertEqual(count("Text(note)", in: editor), 1)
    }
}
