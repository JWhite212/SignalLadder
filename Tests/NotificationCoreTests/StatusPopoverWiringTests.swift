import XCTest
@testable import NotificationCore

/// How the app opens the popover and the menu from the status item (M7 plan,
/// Stage 5). The app target has no tests, so this reads its sources, as the
/// other wiring tests do, and opens no window.
final class StatusPopoverWiringTests: XCTestCase {
    private func squeezed(_ text: String) -> String {
        text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private func lines(_ lines: [String]) -> String { lines.joined(separator: "\n") }

    // MARK: - The press

    /// The item holds no menu, or a click would open it and never reach the app.
    /// It is given the menu only for as long as the menu is open.
    func testTheItemHoldsTheMenuOnlyWhileTheMenuIsOpen() throws {
        let app = try code("AppDelegate.swift")
        XCTAssertEqual(squeezed(try body(of: "private func showStatusMenu() {", in: app)), lines([
            "guard let item = statusItem, let menu = statusMenu else { return }",
            "item.menu = menu",
            "item.button?.performClick(nil)",
            "item.menu = nil",
        ]), "hung from the item, where the Accessibility API and the live check find it")
        XCTAssertEqual(count("item.menu", in: app), 2, "given and taken away, in that one place")
        XCTAssertEqual(count("statusItem?.menu", in: app), 0, "the menu is the app's to keep, not the item's")
    }

    func testWhatAPressOpensIsTheCoresToSay() throws {
        let app = try code("AppDelegate.swift")
        XCTAssertEqual(squeezed(try body(of: "@objc private func statusItemPressed() {", in: app)), lines([
            "let press = currentPress()",
            "if popover.isShown {",
            "popover.close()",
            "guard press.opens == .menu else { return }",
            "} else if press.opens == .popover, StatusItemPress.closedThePopover(sinceClosed: popover.sinceClosed) {",
            "return",
            "}",
            "switch press.opens {",
            "case .popover: showPopover()",
            "case .menu: showStatusMenu()",
            "}",
        ]), "a press while the popover is open closes it, and opens only the menu in its place")
        XCTAssertEqual(count("showPopover()", in: app), 2, "its declaration and the press")
        XCTAssertEqual(count("showStatusMenu()", in: app), 2, "its declaration and the press")
    }

    /// The Accessibility API's press brings no event of its own, so the app's
    /// current event is then an old one: its age is handed to the core, which
    /// says whether it is this press.
    func testThePressIsReadFromTheCurrentEventWithItsAge() throws {
        let press = try body(of: "private func currentPress() -> StatusItemPress {", in: try code("AppDelegate.swift"))
        XCTAssertEqual(count("guard let event = NSApp.currentEvent else { return .other }", in: press), 1)
        XCTAssertEqual(count("case .leftMouseUp: button = .left", in: press), 1)
        XCTAssertEqual(count("case .rightMouseUp: button = .right", in: press), 1)
        XCTAssertEqual(count("default: button = nil", in: press), 1)
        XCTAssertEqual(count("age: ProcessInfo.processInfo.systemUptime - event.timestamp,", in: press), 1)
        XCTAssertEqual(count("option: event.modifierFlags.contains(.option), control: event.modifierFlags.contains(.control))",
                             in: press), 1)
    }

    // MARK: - Opening and closing

    /// The popover's opening is the menu's: the same function, and then the
    /// facts, read once. Its closing is the menu's too, so what was held while
    /// it was open is rebuilt once.
    func testThePopoverOpensAsTheMenuDoesAndIsMadeOnceFromWhatWasReadThen() throws {
        let app = try code("AppDelegate.swift")
        XCTAssertEqual(squeezed(try body(of: "func menuNeedsUpdate(_ menu: NSMenu) {", in: app)), lines([
            "guard menu === statusMenu else { return }",
            "statusWillOpen()",
        ]))
        let opens = try body(of: "private func showPopover() {", in: app)
        let willOpen = try position(of: "let loginItemStatus = statusWillOpen()", in: opens)
        let listed = try position(of: "let rows = escalations.listedSummaries", in: opens)
        let kept = try position(of: "popoverListed = rows.map(ListedEscalation.init(row:))", in: opens)
        let made = try position(of: "StatusPopover.content(popoverFacts(listed: rows.map(\\.1), loginItemStatus: loginItemStatus),", in: opens)
        let shown = try position(of: "popover.show(content,", in: opens)
        XCTAssertLessThan(willOpen, listed, "the gate holds the rows before any is read")
        XCTAssertLessThan(listed, kept)
        XCTAssertLessThan(kept, made, "what Acknowledge acts on is what the blocks were drawn from")
        XCTAssertLessThan(made, shown)
        XCTAssertEqual(count("self.menuDidClose(menu)", in: opens), 1, "its closing is the menu's closing")
        XCTAssertEqual(count("statusWillOpen()", in: app), 3, "its declaration, the menu's opening and the popover's")
        XCTAssertEqual(count("StatusPopover.content(", in: app), 1, "made once, as it opens, and never while it is open")
        XCTAssertFalse(opens.contains("LoginItem.status"), "it is handed what the opening read (Ruling 15)")
    }

    /// Every fact is read where the menu's build reads it.
    func testThePopoversFactsAreTheMenus() throws {
        let facts = try body(
            of: "private func popoverFacts(listed: [EscalationSummary], loginItemStatus: LoginItemStatus?) -> StatusPopover.Facts {",
            in: try code("AppDelegate.swift"))
        for line in ["shortcutFailure: pipeline.unresolvedShortcutFailure,", "healthTitle: healthTitle,", "cause: firstCause,",
                     "setupNudge: setupNudgeLine,", "onCall: isOn,",
                     "onCallLines: isOn ? onCallLines(loginItemStatus: loginItemStatus) : [],", "snooze: snoozeMenu,",
                     "capturedLine: StatusMenuText.capturedLine(count: capture.captureCount),",
                     "ruleSummary: ruleStore.status.summary,", "ruleDetail: ruleStore.status.detail,",
                     "ruleWarnings: RuleWarnings.menuLines(for: ruleStore.warnings),",
                     "ruleLines: alertLines + [ruleMatchLine].compactMap { $0 },",
                     "launchAtLoginLine: launchAtLoginLine(loginItemStatus: loginItemStatus))"] {
            XCTAssertEqual(count(line, in: facts), 1, line)
        }
        for made in ["AlertMenuText.", "SnoozeText.", "SetupPlan.", "LaunchAtLogin.", "LoginItem.status", "OnCallCheck."] {
            XCTAssertFalse(facts.contains(made), "\(made) is asked in the one place the menu asks it")
        }
    }

    /// Each control goes by the door the menu's item uses.
    func testEachActionGoesByTheMenusDoor() throws {
        let app = try code("AppDelegate.swift")
        XCTAssertEqual(squeezed(try body(of: "private func perform(_ action: StatusPopover.Action) {", in: app)), lines([
            "switch action {",
            "case .acknowledgeListed: acknowledge(listed: popoverListed)",
            "case .openPane(let pane): openPaneForCause(pane)",
            "case .showSetupGuide: showSetupGuide()",
            "case .toggleOnCall: toggleOnCall()",
            "case .showOnCallCheck: showOnCallCheck()",
            "case .startSnooze(let duration): startSnooze(duration)",
            "case .endSnooze: endSnoozeFromMenu()",
            "case .dismissHeld(let shown): dismissHeld(shown)",
            "case .showInspector: showInspector()",
            "case .editRules: showRuleEditor()",
            "case .openRulesFile: openRulesFileInTextEditor()",
            "case .reloadRules: reloadRules()",
            "case .showSettings: showSettings()",
            "case .quit: NSApp.terminate(nil)",
            "}",
        ]))
    }

    // MARK: - The window

    /// It takes the keyboard and does not activate the app, and closes when the
    /// keyboard goes elsewhere, on Esc, and on a click in another app.
    func testThePanelTakesTheKeyboardWithoutActivatingTheAppAndClosesWhenItLosesIt() throws {
        let controller = try code("StatusPopoverController.swift")
        XCTAssertEqual(count("styleMask: [.borderless, .nonactivatingPanel],", in: controller), 1)
        XCTAssertEqual(count("override var canBecomeKey: Bool { true }", in: controller), 1)
        XCTAssertFalse(controller.contains("NSApp.activate"), "the app the user was in stays in front")
        XCTAssertFalse(controller.contains("NSPopover"), "a panel of its own, so its ground and its edge are navy")
        XCTAssertEqual(squeezed(try body(of: "func windowDidResignKey(_ notification: Notification) {", in: controller)), "close()")
        XCTAssertEqual(count("guard event.keyCode == Self.escape else { return super.keyDown(with: event) }", in: controller), 1)
        XCTAssertEqual(count("NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown])", in: controller), 1)
        XCTAssertEqual(count("NSEvent.removeMonitor(clickMonitor)", in: controller), 1, "and the watch ends when it closes")
    }

    /// It opens with no control holding the keyboard, as a menu opens with
    /// nothing chosen. With Keyboard navigation on, the window would give the
    /// keyboard to its first control as it took it: a ring round that control,
    /// and Space pressing it, which over an escalation is Acknowledge.
    func testThePopoverOpensWithNoControlHoldingTheKeyboard() throws {
        let controller = try code("StatusPopoverController.swift")
        XCTAssertEqual(count("panel.makeFirstResponder(nil)", in: controller), 1)
        XCTAssertLessThan(try position(of: "panel.makeKeyAndOrderFront(nil)", in: controller),
                          try position(of: "panel.makeFirstResponder(nil)", in: controller),
                          "after it takes the keyboard, which is when the window chooses a control")
        XCTAssertFalse(controller.contains("initialFirstResponder"), "no control is chosen for it")
        let view = try code("StatusPopoverView.swift")
        XCTAssertFalse(view.contains("focusEffectDisabled"), "the ring is still drawn for whoever moves with Tab")
        XCTAssertFalse(view.contains(".focusable(false)"), "and every control can still be reached with it")
    }

    /// Closing tells the app once, before any action is carried out, so the gate
    /// has let go before the action changes anything.
    func testAChosenControlClosesThePopoverBeforeItsActionRuns() throws {
        let controller = try code("StatusPopoverController.swift")
        let chosen = try position(of: "self?.close()", in: controller)
        XCTAssertLessThan(chosen, try position(of: "perform(action)", in: controller))
        let close = squeezed(try body(of: "func close() {", in: controller))
        XCTAssertTrue(close.hasPrefix("guard let panel else { return }\nself.panel = nil"), "a second close does nothing")
        XCTAssertTrue(close.hasSuffix("let closed = onClose\nonClose = nil\nclosed?()"), "told once")
    }

    /// The menu's keys work while the popover is open, by the core's answer, and
    /// only with Command alone.
    func testTheMenusKeysAreAnsweredByTheCore() throws {
        let controller = try code("StatusPopoverController.swift")
        XCTAssertEqual(count("guard let action = content.action(forCommandKey: character) else { return false }", in: controller), 1)
        XCTAssertEqual(count("if event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock) == .command,",
                             in: controller), 1, "with Caps Lock on too, as a menu's keys are")
    }

    // MARK: - The view

    func testTheViewDrawsWhatItIsGivenAndReturnAcknowledgesNothing() throws {
        let view = try code("StatusPopoverView.swift")
        XCTAssertEqual(count(".accessibilityLabel(waiting.row.line)", in: view), 1, "VoiceOver is told the panel's line for a block")
        XCTAssertEqual(count("Button { perform(.acknowledgeListed) } label: {", in: view), 1)
        XCTAssertFalse(view.contains("keyboardShortcut"),
                       "no control is the default: a stray Return must not silence a page the user has not read")
        XCTAssertEqual(count(".environment(\\.colorScheme, .dark)", in: view), 1, "navy whatever the system's appearance")
        XCTAssertEqual(count("NightWatchPalette.block(tone)", in: view), 1, "a tier's colour is the palette's")
        XCTAssertEqual(count(".faultOutlined()", in: view), 1, "a fault has the line every fault has")
        XCTAssertFalse(view.contains("Date("), "it reads no clock: nothing in it changes while it is open")
        XCTAssertFalse(view.contains("Timer"))
    }

    /// What VoiceOver is given beyond the words: headings, the tick's state, the
    /// symbols that say nothing left out, and whether the Snooze tile's choices are open.
    func testWhatVoiceOverIsToldOfTheView() throws {
        let view = try code("StatusPopoverView.swift")
        XCTAssertEqual(count(".accessibilityAddTraits(.isHeader)", in: view), 1)
        XCTAssertEqual(count(".accessibilityAddTraits(command.isOn == true ? .isSelected : [])", in: view), 1)
        XCTAssertEqual(count(".accessibilityHidden(true)", in: view), 2, "the tick and the chevron")
        XCTAssertEqual(count(".accessibilityLabel(tile.title)", in: view), 1)
        XCTAssertEqual(count("? (snoozeOpen ? StatusPopoverText.choicesShown : StatusPopoverText.choicesHidden) : \"\")", in: view), 1)
    }

    /// The app keeps the menu, so its rebuilds, the icon's among them, ask the
    /// app's own and not the item's, which holds none between openings.
    func testTheRebuildsAskForTheAppsMenuAndWhatWasListedIsSetOnce() throws {
        let app = try code("AppDelegate.swift")
        let rebuild = try body(of: "private func rebuildMenu(loginItemStatus: LoginItemStatus? = nil) {", in: app)
        XCTAssertTrue(squeezed(rebuild).hasPrefix("guard statusMenu != nil else { return }"))
        let items = try body(of: "private func rebuildMenuItems(loginItemStatus: LoginItemStatus?) {", in: app)
        XCTAssertTrue(squeezed(items).hasPrefix("guard let menu = statusMenu else { return }"))
        XCTAssertEqual(count("popoverListed", in: app), 3, "declared, set as the popover opens, and read by its Acknowledge")
    }
}
