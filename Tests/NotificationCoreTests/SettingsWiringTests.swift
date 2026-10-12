import XCTest
@testable import NotificationCore

/// How the app target carries out what the core decides about Launch at login (M5
/// plan, Ruling 10, Ruling 15, O12): the adapter, the model, the window and the
/// menus.
///
/// The app target has no tests, and what the core cannot hold is the wiring: that
/// nothing registers but the user's own press, that the status is read afresh when
/// the window appears, on every activation and after every request and is never
/// kept, that what a request came to is read against the status read afterwards,
/// that what a press saves and how long a message stands are the core's, that the
/// menu's one line is made from one read, made as the menu opens, and from the
/// core's answer, and that the window and both menus open the same window. Swap
/// any of them and the app builds without a warning. So these tests read the app's
/// sources, as `OnCallWiringTests` and `ViewLiteralsTests` do, and hold each place
/// to what it is meant to say. They start nothing, call no system service, show no
/// window and read no preferences.
final class SettingsWiringTests: XCTestCase {
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

    // MARK: The adapter

    /// The core forbids `ServiceManagement`, and the app target keeps it to one file,
    /// so that every call of the system's login item is one place to read.
    func testOnlyTheAdapterNamesTheSystemsLoginItem() throws {
        var found: [String] = []
        for file in try AppSources.fileNames() {
            let source = try code(file)
            if source.contains("ServiceManagement") || source.contains("SMAppService") { found.append(file) }
        }
        XCTAssertEqual(found, ["LoginItem.swift"])
    }

    func testTheAdapterMapsEachStatusToTheCoreCaseOfTheSameNameAndAStatusItCannotNameToTheCoresReading() throws {
        let adapter = try code("LoginItem.swift")
        let status = trimmed(try body(of: "static var status: LoginItemStatus {", in: adapter))
        XCTAssertEqual(status, lines([
            "switch SMAppService.mainApp.status {",
            "case .notRegistered: return .notRegistered",
            "case .enabled: return .enabled",
            "case .requiresApproval: return .requiresApproval",
            "case .notFound: return .notFound",
            "@unknown default: return .whenUnrecognised",
            "}",
        ]))
    }

    /// Each request is made in its synchronous form: no error is what was asked, and
    /// an error is handed to the core as its domain and its code. The domain is the
    /// core's text to compare, so the adapter types none.
    func testEachRequestIsMadeSynchronouslyAndAnErrorIsHandedToTheCoreAsItsDomainAndCode() throws {
        let adapter = try code("LoginItem.swift")
        for name in ["register", "unregister"] {
            let made = trimmed(try body(of: "static func \(name)() -> LaunchAtLogin.Outcome {", in: adapter))
            XCTAssertEqual(made, lines([
                "do {",
                "try SMAppService.mainApp.\(name)()",
                "return .succeeded",
                "} catch {",
                "return outcome(of: .\(name), error)",
                "}",
            ]), name)
        }
        XCTAssertFalse(adapter.contains("await"), "the asynchronous overload can be ambiguous")
        XCTAssertFalse(adapter.contains("completionHandler"))
        XCTAssertFalse(adapter.contains("SMAppServiceErrorDomain"), "the domain is compared as the core's text")

        let hand = trimmed(try body(
            of: "private static func outcome(of request: LaunchAtLogin.Request, _ error: Error) -> LaunchAtLogin.Outcome {",
            in: adapter))
        XCTAssertEqual(hand, lines([
            "let failure = error as NSError",
            "log.error(\"Login item request failed, domain \\(failure.domain, privacy: .public), code \\(failure.code, privacy: .public)\")",
            "return LaunchAtLogin.outcome(ofRequest: request, domain: failure.domain, code: failure.code)",
        ]))
    }

    /// Only the domain and the code are logged, never what the error describes, which
    /// may name a path or a bundle.
    func testTheAdapterLogsTheDomainAndTheCodeAndNothingElse() throws {
        let adapter = try code("LoginItem.swift")
        XCTAssertEqual(count("log.", in: adapter), 1)
        XCTAssertEqual(count("Logger(subsystem: \"com.jamiewhite.signalladder\", category: \"loginitem\")", in: adapter), 1)
        for forbidden in ["localizedDescription", "userInfo", "debugDescription", "\\(error", "bundlePath"] {
            XCTAssertFalse(adapter.contains(forbidden), forbidden)
        }
    }

    func testTheAdapterOpensLoginItemsInSystemSettingsAndDoesNothingElseThere() throws {
        let adapter = try code("LoginItem.swift")
        let open = trimmed(try body(of: "static func openSystemSettingsLoginItems() {", in: adapter))
        XCTAssertEqual(open, "SMAppService.openSystemSettingsLoginItems()")
    }

    // MARK: Nothing registers but the user

    func testTheOnlyCallsOfRegisterAndUnregisterAreTheModelsRequestAndNothingCallsItButAPressOfTheUser() throws {
        var registers: [String] = []
        var unregisters: [String] = []
        for file in try AppSources.fileNames() {
            let source = try code(file)
            registers += Array(repeating: file, count: count("LoginItem.register()", in: source))
            unregisters += Array(repeating: file, count: count("LoginItem.unregister()", in: source))
        }
        XCTAssertEqual(registers, ["SettingsModel.swift"])
        XCTAssertEqual(unregisters, ["SettingsModel.swift"])

        // The request is made in one place, which two of the user's presses reach and
        // nothing else: the switch, and a button beside it.
        let model = try code("SettingsModel.swift")
        XCTAssertEqual(count("carryOut(", in: model), 3, "its declaration and the two presses")
        let turned = trimmed(try body(of: "func switchTurned(on: Bool) {", in: model))
        XCTAssertEqual(count("carryOut(", in: turned), 1)
        let performed = trimmed(try body(of: "func perform(_ action: LaunchAtLogin.Action) {", in: model))
        XCTAssertEqual(count("carryOut(", in: performed), 1)

        // And those two are reached from the view alone: the app delegate, which
        // builds the menu, the launch and every health refresh, asks neither.
        for file in try AppSources.fileNames() where file != "SettingsModel.swift" && file != "SettingsView.swift" {
            XCTAssertFalse(try code(file).contains(".switchTurned("), file)
        }
        // What the app delegate asks of the model is five things: what the user chose,
        // what Settings would show for a status it read, what the last request said (which
        // the check window shows beneath the finding's button), to carry out the on-call
        // finding's button, which is the press of a button that registers and which only
        // the user makes (`OnCallWiringTests`), and to be told of each read the model makes,
        // for the watch. It asks for nothing else, and the model's `perform` is called by
        // the view of Settings and by that press alone.
        let app = try code("AppDelegate.swift")
        XCTAssertEqual(count("settingsModel.", in: app),
                       count("settingsModel.wanted", in: app) + count("settingsModel.state(for:", in: app)
                           + count("settingsModel.perform(", in: app) + count("settingsModel.message", in: app)
                           + count("settingsModel.onStatusRead = ", in: app),
                       "the app delegate reads what the user chose, what a status shows and what a request said, is told of each read, and hands the model a press")
        XCTAssertEqual(count("settingsModel.perform(", in: app), 1)
        for file in try AppSources.fileNames() where file != "AppDelegate.swift" {
            XCTAssertFalse(try code(file).contains("settingsModel.perform("), file)
        }
        // The system's Login Items are opened from that one place as well.
        for file in try AppSources.fileNames() where file != "SettingsModel.swift" && file != "LoginItem.swift" {
            XCTAssertFalse(try code(file).contains("openSystemSettingsLoginItems"), file)
        }
        let view = try code("SettingsView.swift")
        XCTAssertEqual(count("model.switchTurned(on: $0)", in: view), 1)
        XCTAssertEqual(count("model.perform(button.action)", in: view), 1)
    }

    // MARK: The model

    func testTheSwitchSavesTheUsersChoiceUnderTheCoresKeyAndAsksForWhatTheCoreSays() throws {
        let model = try code("SettingsModel.swift")
        let turned = trimmed(try body(of: "func switchTurned(on: Bool) {", in: model))
        XCTAssertEqual(turned, lines([
            "saveChoice(on)",
            "carryOut(LaunchAtLogin.request(switchTurnedOn: on))",
        ]))
        let saved = trimmed(try body(of: "private func saveChoice(_ choice: Bool) {", in: model))
        XCTAssertEqual(saved, lines([
            "wanted = choice",
            "defaults.set(choice, forKey: LaunchAtLogin.wantedKey)",
        ]))
        XCTAssertEqual(count("defaults.set(", in: model), 1, "the choice is written in one place")
        XCTAssertEqual(count("saveChoice(", in: model), 3, "its declaration, the switch and the buttons: at the user's own press and at no other time")
        XCTAssertFalse(model.contains("removeObject"))
        // Read as the core reads a saved value, once, when the model is made.
        XCTAssertEqual(count("LaunchAtLogin.wanted(stored: defaults.object(forKey: LaunchAtLogin.wantedKey))", in: model), 1)
        XCTAssertEqual(count("wantedKey", in: model), 2, "read once, written once")
        // The menu reads the one copy and never the preference.
        for file in try AppSources.fileNames() where file != "SettingsModel.swift" {
            XCTAssertFalse(try code(file).contains("wantedKey"), file)
        }
    }

    /// What a button saves, if anything, and whether it asks the system to register,
    /// are what the core says of the action, and the model carries out both.
    func testAButtonSavesWhatTheCoreSaysAndAsksForWhatItSaysAndOneThatDoesNotOnlyOpensSystemSettings() throws {
        let model = try code("SettingsModel.swift")
        let performed = trimmed(try body(of: "func perform(_ action: LaunchAtLogin.Action) {", in: model))
        XCTAssertEqual(performed, lines([
            "if let choice = action.wantedAfterPress { saveChoice(choice) }",
            "if let request = action.request {",
            "carryOut(request)",
            "} else {",
            "LoginItem.openSystemSettingsLoginItems()",
            "}",
        ]))
    }

    /// Whatever the request said, the status is read again and is what is shown, and
    /// what the request came to is said against that read, in the core's words.
    func testARequestIsMadeTheStatusIsReadAgainAndWhatItCameToIsSaidAgainstThatRead() throws {
        let model = try code("SettingsModel.swift")
        let carried = trimmed(try body(of: "private func carryOut(_ request: LaunchAtLogin.Request) {", in: model))
        XCTAssertEqual(carried, lines([
            "let outcome: LaunchAtLogin.Outcome",
            "switch request {",
            "case .register: outcome = LoginItem.register()",
            "case .unregister: outcome = LoginItem.unregister()",
            "}",
            "read(after: LaunchAtLogin.Attempt(request: request, outcome: outcome))",
        ]))
    }

    /// Read when the model is made, when the window appears, on every activation and
    /// after every request, and in no other place: it is not kept past one of them,
    /// since the system gives no notice of a change. Each read but the first ends in
    /// the model telling whoever asked to be told, with the status it read and after
    /// everything it shows is assigned, which is how the watch is asked about every read
    /// (`OnCallWiringTests`) and why a message is the same in the window and here.
    func testTheStatusIsReadWhenTheWindowAppearsOnEveryActivationAndAfterEveryRequestAndNowhereElse() throws {
        let model = try code("SettingsModel.swift")
        XCTAssertEqual(count("LoginItem.status", in: model), 2, "when it is made, and in `read(after:)`")
        let read = trimmed(try body(of: "private func read(after attempt: LaunchAtLogin.Attempt?) {", in: model))
        XCTAssertEqual(read, lines([
            "status = LoginItem.status",
            "location = Self.currentLocation()",
            "versionLine = Self.currentVersionLine()",
            "message = LaunchAtLoginText.message(after: attempt, statusAfter: status)",
            "onStatusRead(status)",
        ]))
        XCTAssertEqual(count("var onStatusRead: (LoginItemStatus) -> Void = { _ in }", in: model), 1)
        XCTAssertEqual(count("onStatusRead", in: model), 2, "its declaration, and the one call that ends each read")
        let refresh = trimmed(try body(of: "func refresh() {", in: model))
        XCTAssertEqual(refresh, "read(after: nil)", "no request made it, so the core says nothing of one")
        // How long a message stands is the core's: the model assigns what it says, in the
        // one place, and clears nothing of its own.
        XCTAssertEqual(count("message =", in: model), 1)
        XCTAssertFalse(model.contains("message = nil"))
        XCTAssertEqual(count("read(after:", in: model), 2, "the refresh and the request, which are the two ways to a read")

        let made = try body(of: "init(defaults: UserDefaults = .standard) {", in: model)
        XCTAssertFalse(made.contains("onStatusRead"), "the read made when it is made is told to no one: nothing can ask yet")
        XCTAssertEqual(count("forName: NSApplication.didBecomeActiveNotification", in: made), 1)
        XCTAssertEqual(count("MainActor.assumeIsolated { self?.refresh() }", in: made), 1)

        let controller = try code("SettingsWindowController.swift")
        XCTAssertEqual(count("model.refresh()", in: controller), 1, "each time the window is shown")

        // Everywhere else in the app the status is read for the menu's one line.
        for file in try AppSources.fileNames() where !["SettingsModel.swift", "LoginItem.swift", "AppDelegate.swift"].contains(file) {
            XCTAssertFalse(try code(file).contains("LoginItem.status"), file)
        }
    }

    func testTheModelShowsWhatTheCoreSaysForTheStatusTheWordsAndTheBuild() throws {
        let model = try code("SettingsModel.swift")
        XCTAssertEqual(trimmed(try body(of: "var state: LaunchAtLogin.State {", in: model)),
                       "LaunchAtLogin.state(status: status, wanted: wanted, location: location)")
        // What the on-call check asks of it, for a status the caller read: the core's state
        // for that status, what the user wanted as saved now and where the copy runs from
        // as it is now, and nothing the model kept of an earlier read.
        XCTAssertEqual(trimmed(try body(of: "func state(for status: LoginItemStatus) -> LaunchAtLogin.State {", in: model)),
                       "LaunchAtLogin.state(status: status, wanted: wanted, location: Self.currentLocation())")
        XCTAssertEqual(count("var sentence: String { SettingsText.launchAtLoginSentence(for: state) }", in: model), 1)
        XCTAssertEqual(count("var buttons: [SettingsText.LoginButton] { SettingsText.launchAtLoginButtons(for: state) }", in: model), 1)
        XCTAssertEqual(trimmed(try body(of: "private static func currentLocation() -> AppLocation {", in: model)),
                       "AppLocation.classify(path: Bundle.main.bundlePath, home: NSHomeDirectory())")
        XCTAssertEqual(trimmed(try body(of: "private static func currentVersionLine() -> String {", in: model)), lines([
            "let formatter = SettingsText.dateFormatter(locale: .current, timeZone: .current)",
            "return SettingsText.version(BuildInfo(infoDictionary: Bundle.main.infoDictionary),",
            "date: { formatter.string(from: $0) })",
        ]))
    }

    // MARK: The window

    func testTheWindowIsOrdinaryTitledByWindowTitlesReadsTheStatusAndIsActivatedBeforeItIsOrderedFront() throws {
        let controller = try code("SettingsWindowController.swift")
        for word in ["runModal", "beginSheet", "NSAlert"] {
            XCTAssertFalse(controller.contains(word), word)
        }
        XCTAssertEqual(count("window.title = WindowTitles.settings", in: controller), 1)
        XCTAssertEqual(count("window.isReleasedWhenClosed = false", in: controller), 1)
        XCTAssertEqual(count("window.contentView = NSHostingView(rootView: SettingsView(model: model))", in: controller), 1)
        XCTAssertEqual(count("if window == nil {", in: controller), 1, "made once and held")
        XCTAssertEqual(count("self.window = window", in: controller), 1)
        let reads = try position(of: "model.refresh()", in: controller)
        let activates = try position(of: "NSApp.activate(ignoringOtherApps: true)", in: controller)
        let front = try position(of: "window?.makeKeyAndOrderFront(nil)", in: controller)
        XCTAssertLessThan(reads, activates)
        XCTAssertLessThan(activates, front)
        XCTAssertGreaterThan(reads, try position(of: "self.window = window", in: controller),
                             "the status is read whether the window was made now or before")
    }

    /// One group, with the switch, the state in words, the buttons the core gives
    /// and what a failed request said, in that order, and the version line at the
    /// foot. Nothing is drawn from a fact the view made up.
    func testTheViewShowsTheSwitchTheSentenceTheButtonsTheMessageAndTheVersionLineInThatOrder() throws {
        let view = try code("SettingsView.swift")
        XCTAssertEqual(count("GroupBox", in: view), 1, "one group: there is no Setup, Permissions or About group")
        XCTAssertEqual(count("Button(", in: view), 1, "no button but the core's, so none does nothing")
        XCTAssertEqual(count("Toggle(", in: view), 1)
        XCTAssertEqual(count("Toggle(SettingsText.launchAtLoginSwitch, isOn: Binding(", in: view), 1)
        XCTAssertEqual(count("get: { model.state.isOn },", in: view), 1, "the switch shows what the status read")
        XCTAssertEqual(count("set: { model.switchTurned(on: $0) }))", in: view), 1)
        XCTAssertEqual(count(".disabled(!model.state.switchIsEnabled)", in: view), 1)
        XCTAssertEqual(count("ForEach(model.buttons, id: \\.action) { button in", in: view), 1)
        XCTAssertEqual(count("Button(button.label) { model.perform(button.action) }", in: view), 1)

        let group = try body(of: "private var launchAtLogin: some View {", in: view)
        let inGroup = try [
            "Toggle(SettingsText.launchAtLoginSwitch,",
            "Text(model.sentence)",
            "ForEach(model.buttons,",
            "if let message = model.message {",
            "Text(message)",
        ].map { try position(of: $0, in: group) }
        XCTAssertEqual(inGroup, inGroup.sorted())

        let page = try body(of: "var body: some View {", in: view)
        XCTAssertLessThan(try position(of: "GroupBox {", in: page), try position(of: "launchAtLogin", in: page))
        XCTAssertLessThan(try position(of: "launchAtLogin", in: page), try position(of: "Text(model.versionLine)", in: page),
                          "the version line is at the foot")
    }

    func testTheVersionLineIsSecondaryTextAndSelectableSoItCanBeCopied() throws {
        let view = try code("SettingsView.swift")
        let line = try position(of: "Text(model.versionLine)", in: view)
        let tail = String(view[line...])
        let chain = tail.components(separatedBy: "\n").prefix(5).joined(separator: "\n")
        XCTAssertTrue(chain.contains(".foregroundStyle(.secondary)"), chain)
        XCTAssertTrue(chain.contains(".textSelection(.enabled)"), chain)
    }

    // MARK: The menus

    /// The status is read when the menu is about to be shown (Ruling 15), once, and
    /// the one value is what the one line is made from. A rebuild made while the menu
    /// is closed is never shown, since one is made as it opens before every showing,
    /// so it reads nothing and is handed none: rebuilds on every capture and health
    /// change would otherwise each cost a synchronous call on the main run loop that
    /// capture runs on.
    func testTheStatusMenuReadsTheStatusOnlyAsItOpensAndMakesItsOneLineFromThatValue() throws {
        let app = try code("AppDelegate.swift")
        let opens = try body(of: "func menuNeedsUpdate(_ menu: NSMenu) {", in: app)
        XCTAssertEqual(count("let loginItemStatus = LoginItem.status", in: opens), 1)
        XCTAssertLessThan(try position(of: "let loginItemStatus = LoginItem.status", in: opens),
                          try position(of: "rebuildMenu(", in: opens), "it is read before either build it makes")
        XCTAssertEqual(count("rebuildMenu(loginItemStatus: loginItemStatus)", in: opens), 2, "both builds are handed the one value")
        XCTAssertEqual(count("rebuildMenu(", in: opens), 2, "and it makes none without it")
        XCTAssertEqual(count("rebuildMenu(loginItemStatus: loginItemStatus)", in: app), 2,
                       "no build but those is handed a status: every other change rebuilds with none")

        let rebuild = try body(of: "private func rebuildMenu(loginItemStatus: LoginItemStatus? = nil) {", in: app)
        XCTAssertEqual(count("case .rebuildItems: rebuildMenuItems(loginItemStatus: loginItemStatus)", in: rebuild), 1)
        let items = try body(of: "private func rebuildMenuItems(loginItemStatus: LoginItemStatus?) {", in: app)
        XCTAssertFalse(items.contains("LoginItem.status"), "a rebuild reads nothing: it is handed what was read")
        XCTAssertEqual(count("addSettingsSection(to: menu, loginItemStatus: loginItemStatus)", in: items), 1)

        // Never kept: every mention of the type is a parameter it is handed down by.
        XCTAssertEqual(count("LoginItemStatus", in: app), 6,
                       "the six parameters (the three builds of the menu, the findings and the watch, which a pass hands down), and no property")
        XCTAssertFalse(app.contains("var loginItemStatus"))
        XCTAssertFalse(app.contains("let loginItemStatus:"))
        XCTAssertEqual(count("LaunchAtLogin.reconcile(", in: app), 1)
        for file in try AppSources.fileNames() where file != "AppDelegate.swift" {
            XCTAssertFalse(try code(file).contains("LaunchAtLogin.reconcile("), file)
        }
    }

    /// A status is read once for each pass that needs one and the pass shares it: the
    /// menu as it opens (for its one line, its on-call findings and the watch), the item
    /// that opens the check (for the window and the watch), the findings the switch makes
    /// to see whether one is urgent, and the watch that a reload, a health refresh, the
    /// switch and the check coming to the front ask. A request made through Settings'
    /// model has its own read, which the model shares with the watch. Nothing else reads
    /// it, no rebuild does, and what is read is passed down and never kept, so a pass that
    /// makes several things from it makes them all from the one value (Ruling 15).
    func testTheStatusIsReadOnceForEachPassThatNeedsOneAndTheOneValueIsWhatThePassMakesItsThingsFrom() throws {
        let app = try code("AppDelegate.swift")
        XCTAssertEqual(count("LoginItem.status", in: app),
                       4, "the findings, the watch, the menu as it opens and the item that opens the check")
        let findings = trimmed(try body(of: "private func currentFindings() -> [OnCallCheck.Finding] {", in: app))
        XCTAssertEqual(findings, "currentFindings(loginItemStatus: LoginItem.status)")
        let watch = trimmed(try body(of: "private func evaluateOnCallWatch() {", in: app))
        XCTAssertEqual(watch, "evaluateOnCallWatch(loginItemStatus: LoginItem.status)")
        let opens = try body(of: "func menuNeedsUpdate(_ menu: NSMenu) {", in: app)
        XCTAssertEqual(count("LoginItem.status", in: opens), 1)

        // The functions that take a status read none, and every build the menu makes is
        // handed the one value or none.
        for signature in ["private func currentFindings(loginItemStatus: LoginItemStatus?) -> [OnCallCheck.Finding] {",
                          "private func evaluateOnCallWatch(loginItemStatus: LoginItemStatus) {",
                          "private func rebuildMenuItems(loginItemStatus: LoginItemStatus?) {",
                          "private func addOnCallSection(to menu: NSMenu, loginItemStatus: LoginItemStatus?) {",
                          "private func addSettingsSection(to menu: NSMenu, loginItemStatus: LoginItemStatus?) {"] {
            XCTAssertFalse(try body(of: signature, in: app).contains("LoginItem.status"), signature)
        }
        // And nothing the menu makes asks for a pass that reads a status of its own, as
        // `currentFindings()` and `evaluateOnCallWatch()` do for the passes that have none
        // to share: that would be a second read in the one build.
        for signature in ["func menuNeedsUpdate(_ menu: NSMenu) {",
                          "private func rebuildMenuItems(loginItemStatus: LoginItemStatus?) {",
                          "private func addOnCallSection(to menu: NSMenu, loginItemStatus: LoginItemStatus?) {",
                          "private func addSettingsSection(to menu: NSMenu, loginItemStatus: LoginItemStatus?) {"] {
            let made = try body(of: signature, in: app)
            XCTAssertFalse(made.contains("currentFindings()"), signature)
            XCTAssertFalse(made.contains("evaluateOnCallWatch()"), signature)
        }
        XCTAssertEqual(count("currentFindings()", in: app), 2, "its declaration and the switch's one check, which the watch's ask follows")
        // The item that opens the check reads once, and the window and the watch are both
        // handed that value.
        let show = try body(of: "@objc private func showOnCallCheck() {", in: app)
        XCTAssertEqual(count("LoginItem.status", in: show), 1)
        XCTAssertEqual(count("loginItemStatus: loginItemStatus", in: show), 2, "the window's findings and the watch's ask")
        // Both the line and the on-call findings in one build of the menu are made from
        // the status that build was handed, which is the one value that was read.
        let items = try body(of: "private func rebuildMenuItems(loginItemStatus: LoginItemStatus?) {", in: app)
        XCTAssertEqual(count("loginItemStatus: loginItemStatus)", in: items), 2,
                       "the on-call section and the settings section")
        XCTAssertFalse(items.contains("currentFindings"), "the sections ask, and the build asks for nothing of its own")
    }

    func testTheLineIsAskedOfTheCoreAndSettingsIsAnItemOnCommandCommaBeforeQuit() throws {
        let app = try code("AppDelegate.swift")
        let section = trimmed(try body(
            of: "private func addSettingsSection(to menu: NSMenu, loginItemStatus: LoginItemStatus?) {", in: app))
        XCTAssertEqual(section, lines([
            "if LaunchAtLogin.reconcile(wanted: settingsModel.wanted, status: loginItemStatus, onCall: onCall.state.isOn) {",
            "menu.addItem(withTitle: LaunchAtLoginText.menuLine, action: nil, keyEquivalent: \"\")",
            "}",
            "let item = NSMenuItem(title: SettingsText.menuTitle, action: #selector(showSettings), keyEquivalent: \",\")",
            "item.target = self",
            "menu.addItem(item)",
        ]))
        let opens = trimmed(try body(of: "@objc private func showSettings() {", in: app))
        XCTAssertEqual(opens, "settingsWindow.show(model: settingsModel)")
    }

    /// Ruling 17's order: the rules section, Settings and Quit, with the line above
    /// Settings, and nothing of the login item above the rules.
    func testSettingsComesAfterTheRulesSectionAndBeforeQuit() throws {
        let app = try code("AppDelegate.swift")
        let items = try body(of: "private func rebuildMenuItems(loginItemStatus: LoginItemStatus?) {", in: app)
        let rules = try position(of: "addRulesSection(to: menu)", in: items)
        let settings = try position(of: "addSettingsSection(to: menu, loginItemStatus: loginItemStatus)", in: items)
        let quit = try position(of: "menu.addItem(NSMenuItem(title: \"Quit SignalLadder\",", in: items)
        XCTAssertLessThan(rules, settings)
        XCTAssertLessThan(settings, quit)
        guard rules < settings else { return }
        XCTAssertEqual(String(items[rules..<settings]), "addRulesSection(to: menu)\nmenu.addItem(.separator())\n",
                       "only a separator stands between the rules section and Settings")
    }

    /// The line changes no icon: the icon is `StatusGlyph`'s, from the facts it takes,
    /// and none of them is the login item.
    func testTheLoginItemChangesNoIcon() throws {
        let app = try code("AppDelegate.swift")
        let glyph = try body(of: "private func rebuildGlyph() {", in: app)
        for word in ["LoginItem", "LaunchAtLogin", "settings", "wanted"] {
            XCTAssertFalse(glyph.contains(word), word)
        }
        XCTAssertFalse(try code("SettingsModel.swift").contains("StatusGlyph"))
    }

    func testTheMainMenuHasSettingsOnCommandCommaInItsApplicationMenuAndStillNoQuit() throws {
        let menu = try code("MainMenu.swift")
        let made = try body(of: "static func make(settingsTarget: AnyObject, settingsAction: Selector) -> NSMenu {", in: menu)
        XCTAssertEqual(count("let settings = NSMenuItem(title: SettingsText.menuTitle, action: settingsAction, keyEquivalent: \",\")", in: made), 1)
        XCTAssertEqual(count("settings.target = settingsTarget", in: made), 1)
        XCTAssertEqual(count("appMenu.addItem(", in: made), 1, "Settings… and nothing else, so Edit is not taken for it")
        XCTAssertEqual(count("appMenu.addItem(settings)", in: made), 1)
        XCTAssertEqual(count("app.submenu = appMenu", in: made), 1)
        XCTAssertLessThan(try position(of: "main.addItem(app)", in: made), try position(of: "main.addItem(editItem)", in: made),
                          "AppKit takes the first item for the application menu")
        for word in ["terminate", "Quit", "keyEquivalent: \"q\""] {
            XCTAssertFalse(menu.contains(word), word)
        }

        let app = try code("AppDelegate.swift")
        XCTAssertEqual(count("NSApp.mainMenu = MainMenu.make(settingsTarget: self, settingsAction: #selector(showSettings))", in: app), 1)
    }

    func testTheStatusMenuAndTheMainMenuOpenTheOneWindowOfTheOneModel() throws {
        let app = try code("AppDelegate.swift")
        XCTAssertEqual(count("private let settingsWindow = SettingsWindowController()", in: app), 1)
        XCTAssertEqual(count("private let settingsModel = SettingsModel()", in: app), 1)
        XCTAssertEqual(count("settingsWindow.show(model: settingsModel)", in: app), 1)
        XCTAssertEqual(count("#selector(showSettings)", in: app), 2, "the status menu's item and the main menu's")
    }
}
