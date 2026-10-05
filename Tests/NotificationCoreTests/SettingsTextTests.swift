import XCTest
@testable import NotificationCore

/// What the Settings window says of Launch at login (M5 plan, Ruling 18, Ruling
/// 15, O12). The version line has its own suite, `BuildInfoTests`. Every test
/// goes over every status, place and wish, so a wording that claims more than the
/// app read is found whatever state it is in.
final class SettingsTextTests: XCTestCase {
    private func state(_ status: LoginItemStatus, _ location: AppLocation, wanted: Bool = false) -> LaunchAtLogin.State {
        LaunchAtLogin.state(status: status, wanted: wanted, location: location)
    }

    /// Everything the window shows beside the switch for one reading: the sentence
    /// and each button's words, so that one list can be searched.
    private func everythingShown(_ status: LoginItemStatus, _ location: AppLocation, wanted: Bool) -> [String] {
        let shown = state(status, location, wanted: wanted)
        var lines = [SettingsText.launchAtLoginSentence(for: shown)]
        lines += SettingsText.launchAtLoginButtons(for: shown).map(\.label)
        return lines
    }

    private func forEveryReading(_ body: (LoginItemStatus, AppLocation, Bool) -> Void) {
        for status in LoginItemStatus.allCases {
            for location in AppLocation.allCases {
                for wanted in [false, true] { body(status, location, wanted) }
            }
        }
    }

    // MARK: - The menu and the switch

    func testTheMenuItemIsSettingsWithAnEllipsis() {
        XCTAssertEqual(SettingsText.menuTitle, "Settings…")
        XCTAssertTrue(SettingsText.menuTitle.hasSuffix("\u{2026}"), "one ellipsis character, as the menu's other items have")
    }

    func testTheSwitchIsLabelledWithTheNameOfTheSetting() {
        XCTAssertEqual(SettingsText.launchAtLoginSwitch, "Launch at login")
    }

    // MARK: - Only an enabled status is said to be on

    func testTheWordingSaysTheLoginItemIsOnForAnEnabledStatusAlone() {
        forEveryReading { status, location, wanted in
            let said = everythingShown(status, location, wanted: wanted).contains(where: LoginItemClaim.isMadeBy)
            XCTAssertEqual(said, status == .enabled, "\(status) from \(location), wanted \(wanted)")
        }
    }

    func testTheOneSentenceThatSaysItIsOnSaysWhoSaidSo() {
        XCTAssertEqual(SettingsText.launchAtLoginSentence(for: .on),
                       "macOS reports that SignalLadder is set to start when you log in.")
        XCTAssertTrue(SettingsText.onSentence.hasPrefix("macOS reports"),
                      "it is the system's word, and not the app's, that the item is on")
    }

    /// An item the user switched on and the system does not show is said so in
    /// words that are not "on", so the sentence cannot be read as a claim.
    func testAnItemTheUserSwitchedOnThatTheSystemDoesNotShowIsNotSaidToBeOn() {
        let sentence = SettingsText.launchAtLoginSentence(for: .off(wanted: true))
        XCTAssertTrue(sentence.contains("You switched this on"), sentence)
        XCTAssertTrue(sentence.contains("does not report it as enabled"), sentence)
        XCTAssertFalse(LoginItemClaim.isMadeBy(sentence), sentence)
        XCTAssertNotEqual(sentence, SettingsText.launchAtLoginSentence(for: .off(wanted: false)))
    }

    // MARK: - No state the app has not read

    /// The words of a state are the words of what was read. System Settings and
    /// approval are the status of an item that needs approval, and nothing else
    /// says them; a temporary location is the place of a translocated copy; and
    /// no line says that the app will or will not start, nor that Login Items
    /// holds or lacks an entry, which the app does not read, nor speaks of an entry
    /// the user added by hand (`testNoWordingSpeaksOfAnEntryAddedByHand`).
    func testNoWordingNamesAStateTheAppHasNotRead() {
        forEveryReading { status, location, wanted in
            let text = everythingShown(status, location, wanted: wanted).joined(separator: "\n")
            let context = "\(status) from \(location), wanted \(wanted)"
            let shown = state(status, location, wanted: wanted)
            if shown != .switchedOffInSystemSettings {
                XCTAssertFalse(text.contains("System Settings"), "System Settings is named for \(context)")
                XCTAssertFalse(text.contains("approval"), "approval is named for \(context)")
            }
            if shown != .unavailable(.translocated) {
                XCTAssertFalse(text.contains("temporary"), "a temporary location is named for \(context)")
            }
            if case .unavailable = shown {} else {
                XCTAssertFalse(text.contains("not offered"), "\(context)")
            }
            if case .off(wanted: true) = shown {} else {
                XCTAssertFalse(text.contains("You switched"), "the user's wish is named for \(context)")
            }
            for phrase in ["will not start", "will start", "won't start", "does not start", "not in Login Items",
                           "not in your Login Items", "no Login Items entry", "no entry", "yourself", "by hand"] {
                XCTAssertFalse(text.contains(phrase), "'\(phrase)' is said for \(context)")
            }
        }
    }

    /// An off item says what the status says, as the system's word and not the
    /// app's, and no more.
    func testAnOffItemSaysWhatTheStatusSaysAndNoMore() {
        let sentence = SettingsText.launchAtLoginSentence(for: .off(wanted: false))
        XCTAssertEqual(sentence, "macOS does not report SignalLadder as set to start when you log in.")
        XCTAssertTrue(sentence.hasPrefix("macOS does not report"), "what the system says, and not that it is off")
    }

    func testEachStateGivesItsOwnSentenceAndAUnavailableOneSaysWhatToDo() {
        XCTAssertEqual(SettingsText.launchAtLoginSentence(for: .switchedOffInSystemSettings),
                       "Launch at login is switched off in System Settings, or is waiting for your approval there.")
        XCTAssertEqual(SettingsText.launchAtLoginSentence(for: .unavailable(.translocated)),
                       LaunchAtLoginText.reason(for: .translocated))
        XCTAssertTrue(SettingsText.launchAtLoginSentence(for: .unavailable(.translocated))
            .hasSuffix("Move SignalLadder to Applications, then open that copy."))
        XCTAssertTrue(SettingsText.launchAtLoginSentence(for: .unavailable(.elsewhere))
            .hasSuffix("Move SignalLadder to Applications, then open that copy."))
    }

    // MARK: - A hand-made entry

    /// A Login Items entry added by hand in System Settings reads enabled on macOS
    /// 26.7.1 (measured on 2026-10-05, not seen on macOS 14 or 15), and switching
    /// the item off removes it. So the window shows what the status says for it and
    /// says nothing of one: no advice beside the switch, no word that the app may
    /// not see it, no warning of two copies. What was seen, and on which macOS, is
    /// the pages' to say and not the window's.
    func testNoWordingSpeaksOfAnEntryAddedByHand() {
        var lines = [SettingsText.onSentence, SettingsText.offSentence, SettingsText.offButWantedSentence,
                     SettingsText.switchedOffSentence, LaunchAtLoginText.menuLine, LaunchAtLoginText.needsApproval,
                     LaunchAtLoginText.unsignedCopy, LaunchAtLoginText.notEnabled, LaunchAtLoginText.moveToApplications,
                     LaunchAtLoginText.translocatedReason, LaunchAtLoginText.elsewhereReason]
        lines += LaunchAtLogin.Action.allCases.map(LaunchAtLoginText.label(for:))
        lines += LaunchAtLogin.Unavailable.allCases.map(LaunchAtLoginText.reason(for:))
        lines += [LaunchAtLogin.Outcome.failed(.register, code: 7), .failed(.unregister, code: 7)]
            .compactMap(LaunchAtLoginText.message(for:))
        forEveryReading { status, location, wanted in lines += everythingShown(status, location, wanted: wanted) }
        XCTAssertGreaterThan(lines.count, 30, "every line was gathered")
        for line in lines {
            for phrase in ["yourself", "by hand", "added", "entry", "two copies", "two registrations", "remove that"] {
                XCTAssertFalse(line.contains(phrase), "'\(phrase)' is said: \(line)")
            }
        }
    }

    // MARK: - The fix buttons

    /// Switch on again registers, and a translocated copy is offered no registration
    /// (`LaunchAtLogin.state`), so a needs-approval status shows the two buttons
    /// from every place but a translocated copy, which is told where to move to.
    func testOpenLoginItemsAndSwitchOnAgainAreShownForARequiresApprovalStatusAndNoOther() {
        forEveryReading { status, location, wanted in
            let labels = SettingsText.launchAtLoginButtons(for: state(status, location, wanted: wanted)).map(\.label)
            let context = "\(status) from \(location), wanted \(wanted)"
            if status == .requiresApproval && location != .translocated {
                XCTAssertEqual(labels, ["Open Login Items…", "Switch on again"], context)
            } else {
                XCTAssertEqual(labels, [], context)
            }
        }
    }

    /// Neither label is said anywhere else in the window, in a sentence, since a
    /// word for a button that is not there is a button that does nothing.
    func testNeitherLabelIsSaidInAnySentence() {
        forEveryReading { status, location, wanted in
            let line = SettingsText.launchAtLoginSentence(for: state(status, location, wanted: wanted))
            XCTAssertFalse(line.contains("Open Login Items"), line)
            XCTAssertFalse(line.contains("Switch on again"), line)
        }
    }

    func testEachButtonCarriesTheActionItDoesAndTheWordsOfThatAction() {
        let buttons = SettingsText.launchAtLoginButtons(for: .switchedOffInSystemSettings)
        XCTAssertEqual(buttons.map(\.action), [.openLoginItems, .switchOnAgain])
        for button in buttons {
            XCTAssertEqual(button.label, LaunchAtLoginText.label(for: button.action))
        }
        XCTAssertEqual(buttons, [
            SettingsText.LoginButton(action: .openLoginItems, label: "Open Login Items…"),
            SettingsText.LoginButton(action: .switchOnAgain, label: "Switch on again"),
        ])
    }

    /// Where the plan departs: O12 and Ruling 15 have the finding and Settings each
    /// carry a Turn on Launch at login button. Settings has the switch, which is the
    /// one click that asks for it, so a button of the same name beside it would be
    /// two controls for one act, and the finding's button is not repeated there. If
    /// the owner wants it in Settings too, this test is the one that changes.
    func testTheFindingsTurnOnButtonIsNotAButtonBesideTheSwitch() {
        forEveryReading { status, location, wanted in
            let actions = SettingsText.launchAtLoginButtons(for: state(status, location, wanted: wanted)).map(\.action)
            XCTAssertFalse(actions.contains(.turnOn), "\(status) from \(location)")
        }
    }

    // MARK: - The words are the app's own

    func testNoWordingInTheWindowHoldsAPathOrAnEmailAddress() {
        var lines = [SettingsText.menuTitle, SettingsText.launchAtLoginSwitch,
                     SettingsText.onSentence, SettingsText.offSentence, SettingsText.offButWantedSentence,
                     SettingsText.switchedOffSentence]
        forEveryReading { status, location, wanted in lines += everythingShown(status, location, wanted: wanted) }
        for line in lines {
            XCTAssertFalse(line.contains("@"), line)
            XCTAssertFalse(line.contains("/Users"), line)
            XCTAssertFalse(line.contains("/Applications"), "a sentence names the folder and not a path: \(line)")
            XCTAssertFalse(line.contains("\n"), line)
            XCTAssertEqual(line, line.trimmingCharacters(in: .whitespacesAndNewlines), line)
        }
    }
}
