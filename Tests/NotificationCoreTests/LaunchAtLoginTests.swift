import AppKit
import XCTest
@testable import NotificationCore

/// What it takes for a sentence about the login item to say that it is on: the
/// forms a line would take to claim the app starts at login, or that the system
/// has it enabled. The tests below hold every line to say so only where the
/// status was read as enabled. It is a pattern and not a list of the lines, so a
/// sentence written later is held to it too, and `LaunchAtLoginTests` shows that
/// it matches what it should and not what it should not.
enum LoginItemClaim {
    static let pattern = try! NSRegularExpression(
        pattern: #"\b(is|are|was|has been)\s+(now\s+)?(set to start|on|enabled|switched on|turned on)\b|\bstarts\s+(when|at|again)\b|\bwill\s+(start|launch)\b"#,
        options: .caseInsensitive)

    static func isMadeBy(_ text: String) -> Bool {
        pattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}

/// The login item, decided from what was read (M5 plan, Ruling 15, O12). The
/// system is never called: each test gives the status, where the copy runs and
/// what the user wanted as plain values, and reads what the core says to show.
final class LaunchAtLoginTests: XCTestCase {
    typealias State = LaunchAtLogin.State

    private let domain = "SMAppServiceErrorDomain"

    private func state(_ status: LoginItemStatus, _ location: AppLocation, wanted: Bool = false) -> State {
        LaunchAtLogin.state(status: status, wanted: wanted, location: location)
    }

    /// Every state any input can give.
    private var everyState: [State] {
        var found: [State] = []
        for status in LoginItemStatus.allCases {
            for location in AppLocation.allCases {
                for wanted in [false, true] where !found.contains(state(status, location, wanted: wanted)) {
                    found.append(state(status, location, wanted: wanted))
                }
            }
        }
        return found
    }

    // MARK: - What Settings shows

    func testEveryStatusAgainstEveryLocation() {
        let off = State.off(wanted: false)
        let approval = State.switchedOffInSystemSettings
        let table: [(status: LoginItemStatus, expected: [AppLocation: State])] = [
            (.enabled, [.applications: .on, .userApplications: .on, .translocated: .on, .elsewhere: .on]),
            (.notRegistered, [.applications: off, .userApplications: off,
                              .translocated: .unavailable(.translocated), .elsewhere: off]),
            (.requiresApproval, [.applications: approval, .userApplications: approval,
                                 .translocated: .unavailable(.translocated), .elsewhere: approval]),
            (.notFound, [.applications: off, .userApplications: off,
                         .translocated: .unavailable(.translocated), .elsewhere: .unavailable(.elsewhere)]),
        ]
        XCTAssertEqual(Set(table.map(\.status)), Set(LoginItemStatus.allCases), "every status is in the table")
        for row in table {
            XCTAssertEqual(Set(row.expected.keys), Set(AppLocation.allCases), "\(row.status) has every location")
            for (location, expected) in row.expected {
                XCTAssertEqual(state(row.status, location), expected, "\(row.status) from \(location)")
            }
        }
    }

    /// A bundle never registered reads not found, in /Applications and outside
    /// any Applications folder, and so does an unbundled program (all three
    /// measured on macOS 26.7.1, 2026-10-05; not seen on macOS 14 or 15): the place
    /// is all that tells them apart.
    func testNotFoundIsOffOnlyFromAnApplicationsFolderAndNotOfferedFromAnywhereElse() {
        XCTAssertEqual(state(.notFound, .applications), .off(wanted: false))
        XCTAssertEqual(state(.notFound, .userApplications), .off(wanted: false))
        XCTAssertEqual(state(.notFound, .elsewhere), .unavailable(.elsewhere), "a build folder, a volume, or no bundle")
        XCTAssertEqual(state(.notFound, .translocated), .unavailable(.translocated))
    }

    /// Registering from a translocated copy is reported to fail or to misread, so a
    /// translocated copy is offered nothing that asks the system to register,
    /// whatever the status says, and the one status that is shown from there is the
    /// one that asks for nothing. That includes the buttons of a needs-approval
    /// item, one of which registers.
    func testATranslocatedCopyIsOfferedNothingThatRegistersWhateverTheStatusSays() {
        for status in LoginItemStatus.allCases where status != .enabled {
            for wanted in [false, true] {
                let shown = state(status, .translocated, wanted: wanted)
                XCTAssertEqual(shown, .unavailable(.translocated), "\(status), wanted \(wanted)")
                XCTAssertNil(LaunchAtLogin.findingAction(for: shown), "\(status)")
                XCTAssertEqual(LaunchAtLogin.settingsActions(for: shown), [], "\(status)")
                XCTAssertFalse(shown.switchIsEnabled, "\(status)")
            }
        }
        XCTAssertEqual(state(.enabled, .translocated), .on, "an enabled status is shown as read")
        // Each place that is not translocated gives a needs-approval item its two buttons, one of which registers.
        for location in AppLocation.allCases where location != .translocated {
            let actions = LaunchAtLogin.settingsActions(for: state(.requiresApproval, location))
            XCTAssertEqual(actions.compactMap(\.request), [.register], "\(location)")
        }
    }

    /// A Login Items entry added by hand in System Settings reads enabled on macOS
    /// 26.7.1 (measured on 2026-10-05; not seen on macOS 14 or 15), so it is shown
    /// as on like any enabled status, and nothing about it is a state of its own.
    func testAnEnabledStatusIsOnWhereverTheCopyIsAndWhateverTheUserWanted() {
        for location in AppLocation.allCases {
            XCTAssertEqual(state(.enabled, location, wanted: false), .on, "\(location)")
            XCTAssertEqual(state(.enabled, location, wanted: true), .on, "\(location)")
        }
    }

    func testNoStatusButEnabledGivesOn() {
        for status in LoginItemStatus.allCases where status != .enabled {
            for location in AppLocation.allCases {
                for wanted in [false, true] {
                    XCTAssertNotEqual(state(status, location, wanted: wanted), .on, "\(status), \(location), wanted \(wanted)")
                }
            }
        }
    }

    /// What the user wanted changes what an off item says, which is that they had
    /// switched it on, and nothing else: it is never a reason to read as on, to
    /// offer a button, or to say a place is not offered.
    func testWhatTheUserWantedChangesOnlyAnOffItem() {
        for status in LoginItemStatus.allCases {
            for location in AppLocation.allCases {
                let asked = state(status, location, wanted: true)
                let notAsked = state(status, location, wanted: false)
                if case .off = notAsked {
                    XCTAssertEqual(notAsked, .off(wanted: false))
                    XCTAssertEqual(asked, .off(wanted: true), "\(status) from \(location)")
                } else {
                    XCTAssertEqual(asked, notAsked, "\(status) from \(location)")
                }
            }
        }
    }

    func testTheSwitchReadsOnOnlyForAnItemThatIsOn() {
        XCTAssertTrue(State.on.isOn)
        XCTAssertFalse(State.off(wanted: false).isOn)
        XCTAssertFalse(State.off(wanted: true).isOn)
        XCTAssertFalse(State.switchedOffInSystemSettings.isOn)
        XCTAssertFalse(State.unavailable(.translocated).isOn)
        XCTAssertFalse(State.unavailable(.elsewhere).isOn)
    }

    /// The system's two buttons are the way for an item it has switched off, and
    /// where it is not offered there is nothing to press.
    func testTheSwitchCanBePressedWhileItIsOnOrOffAndNotOtherwise() {
        XCTAssertTrue(State.on.switchIsEnabled)
        XCTAssertTrue(State.off(wanted: false).switchIsEnabled)
        XCTAssertTrue(State.off(wanted: true).switchIsEnabled)
        XCTAssertFalse(State.switchedOffInSystemSettings.switchIsEnabled)
        XCTAssertFalse(State.unavailable(.translocated).switchIsEnabled)
        XCTAssertFalse(State.unavailable(.elsewhere).switchIsEnabled)
    }

    // MARK: - The login item starts, only if the system says so

    func testTheAppStartsAtLoginForAnEnabledStatusAndForNoOther() {
        XCTAssertTrue(LaunchAtLogin.startsAtLogin(status: .enabled))
        XCTAssertFalse(LaunchAtLogin.startsAtLogin(status: .notRegistered))
        XCTAssertFalse(LaunchAtLogin.startsAtLogin(status: .requiresApproval))
        XCTAssertFalse(LaunchAtLogin.startsAtLogin(status: .notFound))
        XCTAssertEqual(LoginItemStatus.allCases.filter(LaunchAtLogin.startsAtLogin(status:)), [.enabled])
    }

    /// What on-call mode reads and what Settings shows are one answer: the item
    /// starts at login when it is on, and not when it is any other state.
    func testWhatOnCallReadsAndWhatSettingsShowsAgree() {
        for status in LoginItemStatus.allCases {
            for location in AppLocation.allCases {
                XCTAssertEqual(LaunchAtLogin.startsAtLogin(status: status), state(status, location).isOn,
                               "\(status) from \(location)")
            }
        }
    }

    // MARK: - The menu's one line

    func testTheMenuSaysSoWhenTheUserWantedItAndTheSystemDoesNotShowItEnabled() {
        for status in LoginItemStatus.allCases where status != .enabled {
            XCTAssertTrue(LaunchAtLogin.reconcile(wanted: true, status: status, onCall: false), "\(status)")
        }
    }

    func testTheMenuSaysNothingWhenTheSystemShowsItEnabled() {
        XCTAssertFalse(LaunchAtLogin.reconcile(wanted: true, status: .enabled, onCall: false))
        XCTAssertFalse(LaunchAtLogin.reconcile(wanted: false, status: .enabled, onCall: false))
    }

    func testTheMenuSaysNothingWhenTheUserDidNotWantIt() {
        for status in LoginItemStatus.allCases {
            XCTAssertFalse(LaunchAtLogin.reconcile(wanted: false, status: status, onCall: false), "\(status)")
        }
    }

    /// While on call the on-call finding says the same and more, so the menu
    /// does not say it twice.
    func testTheMenuGivesWayToTheOnCallFindingWhileOnCall() {
        for status in LoginItemStatus.allCases {
            for wanted in [false, true] {
                XCTAssertFalse(LaunchAtLogin.reconcile(wanted: wanted, status: status, onCall: true),
                               "\(status), wanted \(wanted)")
            }
        }
    }

    /// The line is no wider than the menu's widest, in the menu's own font and in
    /// the same run. It is held to that line's sentence, which has no mark, as well
    /// as to the line with it: the mark is set from a fallback font, so what a
    /// release makes of it could decide a close result, while the sentence is plain
    /// text in the menu's own font. Where this was written the line is 418 points
    /// wide, the sentence 428 and the line with its mark 446.
    func testTheLineIsOneShortLineThatPointsToSettings() {
        let line = LaunchAtLoginText.menuLine
        XCTAssertFalse(line.contains("\n"))
        XCTAssertLessThanOrEqual(line.count, 70, "the longest line the menu shows from the check is 67")
        func width(_ text: String) -> CGFloat {
            (text as NSString).size(withAttributes: [.font: NSFont.menuFont(ofSize: 0)]).width
        }
        XCTAssertLessThanOrEqual(width(line), width(AlertMenuText.outputSilentSentence),
                                 "\(line) is \(width(line)) points wide")
        XCTAssertLessThanOrEqual(width(line), width(AlertMenuText.outputSilentWarning), "\(line) is \(width(line)) points wide")
        XCTAssertTrue(line.hasSuffix("see Settings"), line)
        XCTAssertTrue(SettingsText.menuTitle.hasPrefix("Settings"), "the line names the window the menu opens")
    }

    func testTheLineSaysWhatWasReadAndNotThatTheItemIsOn() {
        XCTAssertTrue(LaunchAtLoginText.menuLine.contains("not enabled"))
        XCTAssertFalse(LoginItemClaim.isMadeBy(LaunchAtLoginText.menuLine), LaunchAtLoginText.menuLine)
    }

    // MARK: - What the on-call finding offers

    func testTheFindingOffersTurnOnWhereTheItemCanBeRegistered() {
        XCTAssertEqual(LaunchAtLogin.findingAction(for: state(.notRegistered, .applications)), .turnOn)
        XCTAssertEqual(LaunchAtLogin.findingAction(for: state(.notFound, .applications)), .turnOn)
        XCTAssertEqual(LaunchAtLogin.findingAction(for: state(.notFound, .userApplications)), .turnOn)
        XCTAssertEqual(LaunchAtLogin.findingAction(for: state(.notRegistered, .elsewhere)), .turnOn)
        XCTAssertEqual(LaunchAtLogin.findingAction(for: .off(wanted: false)), .turnOn)
        XCTAssertEqual(LaunchAtLogin.findingAction(for: .off(wanted: true)), .turnOn)
    }

    func testTheFindingOffersOpenLoginItemsWhereTheSystemHasItSwitchedOff() {
        for location in AppLocation.allCases where location != .translocated {
            XCTAssertEqual(LaunchAtLogin.findingAction(for: state(.requiresApproval, location)), .openLoginItems, "\(location)")
        }
    }

    /// Where it is not offered the finding has no button, and gives the reason.
    func testTheFindingOffersNothingWhereItIsNotOffered() {
        XCTAssertNil(LaunchAtLogin.findingAction(for: state(.notFound, .elsewhere)))
        XCTAssertNil(LaunchAtLogin.findingAction(for: state(.notFound, .translocated)))
        XCTAssertNil(LaunchAtLogin.findingAction(for: state(.notRegistered, .translocated)))
        XCTAssertNil(LaunchAtLogin.findingAction(for: state(.requiresApproval, .translocated)))
        for why in LaunchAtLogin.Unavailable.allCases {
            XCTAssertNil(LaunchAtLogin.findingAction(for: .unavailable(why)), "\(why)")
            XCTAssertFalse(LaunchAtLoginText.reason(for: why).isEmpty, "the finding gives the reason of \(why) instead")
        }
    }

    /// An item that is on is no finding, so it has no action to carry.
    func testAnItemThatIsOnHasNoActionToOffer() {
        XCTAssertNil(LaunchAtLogin.findingAction(for: .on))
        for location in AppLocation.allCases {
            XCTAssertNil(LaunchAtLogin.findingAction(for: state(.enabled, location)), "\(location)")
        }
    }

    func testEveryStatusAgainstEveryLocationGivesTheActionItsStateNames() {
        for status in LoginItemStatus.allCases {
            for location in AppLocation.allCases {
                let action = LaunchAtLogin.findingAction(for: state(status, location))
                switch status {
                case .enabled: XCTAssertNil(action, "\(location)")
                case .requiresApproval where location == .translocated: XCTAssertNil(action)
                case .requiresApproval: XCTAssertEqual(action, .openLoginItems, "\(location)")
                case .notRegistered where location == .translocated: XCTAssertNil(action)
                case .notRegistered: XCTAssertEqual(action, .turnOn, "\(location)")
                case .notFound where location.isInApplicationsFolder: XCTAssertEqual(action, .turnOn, "\(location)")
                case .notFound: XCTAssertNil(action, "\(location)")
                }
            }
        }
    }

    func testTheButtonsBesideTheSwitchAreForAnItemTheSystemHasSwitchedOffAlone() {
        XCTAssertEqual(LaunchAtLogin.settingsActions(for: .switchedOffInSystemSettings), [.openLoginItems, .switchOnAgain])
        for state in everyState where state != .switchedOffInSystemSettings {
            XCTAssertEqual(LaunchAtLogin.settingsActions(for: state), [], "\(state)")
        }
    }

    /// The app target does what an action says and chooses nothing: two of the
    /// three ask the system to register, and one only opens System Settings.
    func testTwoActionsRegisterAndOneOnlyOpensSystemSettings() {
        XCTAssertEqual(LaunchAtLogin.Action.turnOn.request, .register)
        XCTAssertEqual(LaunchAtLogin.Action.switchOnAgain.request, .register)
        XCTAssertNil(LaunchAtLogin.Action.openLoginItems.request)
        XCTAssertEqual(LaunchAtLogin.Action.allCases.count, 3)
    }

    /// The app target carries out what is decided and chooses nothing, so which of
    /// the two requests a press of the switch makes is decided here: turning it on
    /// registers, as the finding's Turn on button does, and turning it off
    /// unregisters, which no button does.
    func testTheSwitchRegistersWhenTurnedOnAndUnregistersWhenTurnedOff() {
        XCTAssertEqual(LaunchAtLogin.request(switchTurnedOn: true), .register)
        XCTAssertEqual(LaunchAtLogin.request(switchTurnedOn: false), .unregister)
        XCTAssertEqual(LaunchAtLogin.request(switchTurnedOn: true), LaunchAtLogin.Action.turnOn.request,
                       "the switch and the finding's button ask for the same thing")
        let requests = LaunchAtLogin.Action.allCases.compactMap(\.request)
        XCTAssertFalse(requests.contains(.unregister), "no button unregisters, so only the switch can")
    }

    func testTheButtonsHaveTheWordsThePlanGivesThem() {
        XCTAssertEqual(LaunchAtLoginText.label(for: .turnOn), "Turn on Launch at login")
        XCTAssertEqual(LaunchAtLoginText.label(for: .openLoginItems), "Open Login Items…")
        XCTAssertEqual(LaunchAtLoginText.label(for: .switchOnAgain), "Switch on again")
        let labels = LaunchAtLogin.Action.allCases.map(LaunchAtLoginText.label(for:))
        XCTAssertEqual(Set(labels).count, labels.count, "two buttons with one label cannot be told apart")
    }

    /// The words the finding already says (`OnCallText`) and the buttons agree on
    /// what the place is called, so the user is not sent to one name by one and
    /// another by the other.
    func testTheButtonsAndTheOnCallFindingNameTheSamePlace() {
        XCTAssertTrue(OnCallText.loginItemOff.contains("Login Items"))
        XCTAssertTrue(LaunchAtLoginText.openLoginItems.contains("Login Items"))
        XCTAssertTrue(LaunchAtLoginText.turnOn.contains(SettingsText.launchAtLoginSwitch),
                      "the button names the setting the switch is labelled with")
    }

    // MARK: - Every state has its reason

    func testEveryStateHasASentenceAndNoTwoStatesShareOneUnlessTheyAreTheSameState() {
        var sentences: [String: State] = [:]
        for state in everyState {
            let sentence = SettingsText.launchAtLoginSentence(for: state)
            XCTAssertFalse(sentence.trimmingCharacters(in: .whitespaces).isEmpty, "\(state)")
            XCTAssertFalse(sentence.contains("\n"), "\(state)")
            if let other = sentences[sentence] {
                XCTAssertEqual(other, state, "\(other) and \(state) say the same")
            }
            sentences[sentence] = state
        }
        XCTAssertEqual(sentences.count, 6, "on, off, off and wanted, switched off, and the two that are not offered")
    }

    func testAnUnavailableStateSaysWhyAndWhatToDoAboutIt() {
        for why in LaunchAtLogin.Unavailable.allCases {
            let reason = LaunchAtLoginText.reason(for: why)
            XCTAssertTrue(reason.contains("Move SignalLadder to Applications, then open that copy"), reason)
            XCTAssertEqual(SettingsText.launchAtLoginSentence(for: .unavailable(why)), reason,
                           "Settings and the finding say it in the same words")
        }
        XCTAssertNotEqual(LaunchAtLoginText.reason(for: .translocated), LaunchAtLoginText.reason(for: .elsewhere))
        XCTAssertTrue(LaunchAtLoginText.reason(for: .translocated).contains("temporary location"))
        XCTAssertFalse(LaunchAtLoginText.reason(for: .elsewhere).contains("temporary"),
                       "a copy that is not translocated is not said to be")
    }

    /// No line says the item is on unless the status is enabled: not the sentence
    /// of a state, the menu's line, a fix's button, nor what a failed request says.
    func testNoLineSaysOnWhenTheStatusIsNotEnabled() {
        for status in LoginItemStatus.allCases where status != .enabled {
            for location in AppLocation.allCases {
                for wanted in [false, true] {
                    let shown = state(status, location, wanted: wanted)
                    var lines = [SettingsText.launchAtLoginSentence(for: shown)]
                    lines += LaunchAtLogin.settingsActions(for: shown).map(LaunchAtLoginText.label(for:))
                    if let action = LaunchAtLogin.findingAction(for: shown) { lines.append(LaunchAtLoginText.label(for: action)) }
                    for line in lines {
                        XCTAssertFalse(LoginItemClaim.isMadeBy(line), "\(status) from \(location): \(line)")
                    }
                }
            }
        }
        XCTAssertFalse(LoginItemClaim.isMadeBy(LaunchAtLoginText.menuLine))
        for action in LaunchAtLogin.Action.allCases {
            XCTAssertFalse(LoginItemClaim.isMadeBy(LaunchAtLoginText.label(for: action)), "\(action)")
        }
    }

    func testOnlyAnEnabledStatusIsSaidToBeOn() {
        XCTAssertTrue(LoginItemClaim.isMadeBy(SettingsText.launchAtLoginSentence(for: state(.enabled, .applications))))
        for status in LoginItemStatus.allCases where status != .enabled {
            for location in AppLocation.allCases {
                XCTAssertFalse(LoginItemClaim.isMadeBy(SettingsText.launchAtLoginSentence(for: state(status, location))),
                               "\(status) from \(location)")
            }
        }
    }

    /// The test above is only as good as its pattern, so the pattern is held to
    /// what it is for: it matches the ways to say an item is on, and none of the
    /// ways to say it is not.
    func testThePatternForAClaimThatTheItemIsOnMatchesWhatItForbidsAndNotWhatItAllows() {
        for claim in ["Launch at login is on.", "It is enabled.", "macOS says it has been switched on", "SignalLadder will start at login",
                      "It starts when you log in", "SignalLadder is set to start when you log in", "Launch at login is now on",
                      "SignalLadder will launch at login", "it starts again after a restart",
                      "Starts when you log in", "Will start at login", "Is enabled"] {
            XCTAssertTrue(LoginItemClaim.isMadeBy(claim), claim)
        }
        for fine in ["Launch at login is not enabled", "it is not on", "You switched this on, but macOS does not report it as enabled",
                     "macOS does not report SignalLadder as set to start when you log in",
                     "before SignalLadder can start at login", "Turn on Launch at login", "Switch on again"] {
            XCTAssertFalse(LoginItemClaim.isMadeBy(fine), fine)
        }
    }

    // MARK: - A failed request

    func testTheDomainIsTheStringTheSystemGaveOnMacOS26() {
        XCTAssertEqual(LaunchAtLogin.errorDomain, "SMAppServiceErrorDomain")
    }

    /// A second `register()` raised no error on macOS 26.7.1 (measured on
    /// 2026-10-05; not seen on macOS 14 or 15), so 12 was not seen there. It is kept
    /// as so, the safe reading where it does occur, since the status is read again.
    func testRegisteringWhenItAlreadyIsIsASuccess() {
        XCTAssertEqual(LaunchAtLogin.outcome(ofRequest: .register, domain: domain, code: 12), .succeeded)
    }

    /// A second `unregister()` raised no error on macOS 26.7.1 (measured on
    /// 2026-10-05; not seen on macOS 14 or 15), so 6 was not seen there. It is kept
    /// as so, the safe reading where it does occur.
    func testUnregisteringWhenThereIsNothingToRemoveIsASuccess() {
        XCTAssertEqual(LaunchAtLogin.outcome(ofRequest: .unregister, domain: domain, code: 6), .succeeded)
    }

    func testARegistrationThatNeedsApprovalNeedsIt() {
        XCTAssertEqual(LaunchAtLogin.outcome(ofRequest: .register, domain: domain, code: 11), .needsApproval)
    }

    func testARegistrationOfACopyWithoutAGoodSignatureIsAnUnsignedCopy() {
        XCTAssertEqual(LaunchAtLogin.outcome(ofRequest: .register, domain: domain, code: 3), .unsignedCopy)
    }

    func testAnyOtherCodeIsAFailureWithItsCodeForEitherRequest() {
        for code in [0, 1, 2, 4, 5, 7, 8, 9, 10, 13, 14, 15, 100, 1000, -1, -3, Int.max, Int.min] {
            XCTAssertEqual(LaunchAtLogin.outcome(ofRequest: .register, domain: domain, code: code), .failed(.register, code: code), "\(code)")
            XCTAssertEqual(LaunchAtLogin.outcome(ofRequest: .unregister, domain: domain, code: code), .failed(.unregister, code: code), "\(code)")
        }
    }

    /// A code means what it means in the system's own domain. In another, or in a
    /// spelling the system does not give, it is only a number, and is shown as a
    /// failure and not read as a success, an approval or a signature.
    func testAKnownCodeFromAnotherDomainIsAFailure() {
        let others = ["NSCocoaErrorDomain", "NSPOSIXErrorDomain", "NSOSStatusErrorDomain", "com.apple.ServiceManagement.error",
                      "", " ", "smappserviceerrordomain", "SMAppServiceErrorDomain ", "SMAppServiceErrorDomain.", "SMAppService"]
        for other in others {
            for (request, code) in [(LaunchAtLogin.Request.register, 12), (.register, 11), (.register, 3), (.unregister, 6)] {
                XCTAssertEqual(LaunchAtLogin.outcome(ofRequest: request, domain: other, code: code), .failed(request, code: code),
                               "\(code) in '\(other)'")
            }
        }
    }

    /// The plan gives each code for the request that raises it. A code in the
    /// other request is not one the system is documented to give, so it is a
    /// failure in the app's own words, the safe way to be wrong.
    func testAKnownCodeInTheOtherRequestIsAFailure() {
        XCTAssertEqual(LaunchAtLogin.outcome(ofRequest: .unregister, domain: domain, code: 12), .failed(.unregister, code: 12))
        XCTAssertEqual(LaunchAtLogin.outcome(ofRequest: .register, domain: domain, code: 6), .failed(.register, code: 6))
        XCTAssertEqual(LaunchAtLogin.outcome(ofRequest: .unregister, domain: domain, code: 11), .failed(.unregister, code: 11))
        XCTAssertEqual(LaunchAtLogin.outcome(ofRequest: .unregister, domain: domain, code: 3), .failed(.unregister, code: 3))
    }

    func testTheCodesAreTheOnesTheSDKGives() {
        XCTAssertEqual(LaunchAtLogin.invalidSignatureCode, 3)
        XCTAssertEqual(LaunchAtLogin.jobNotFoundCode, 6)
        XCTAssertEqual(LaunchAtLogin.launchDeniedCode, 11)
        XCTAssertEqual(LaunchAtLogin.alreadyRegisteredCode, 12)
    }

    func testAnOutcomeThatCameToWhatWasAskedHasNothingToSayAndEveryOtherHasSomething() {
        XCTAssertNil(LaunchAtLoginText.message(for: .succeeded))
        XCTAssertNotNil(LaunchAtLoginText.message(for: .needsApproval))
        XCTAssertNotNil(LaunchAtLoginText.message(for: .unsignedCopy))
        XCTAssertNotNil(LaunchAtLoginText.message(for: .notEnabled))
        XCTAssertNotNil(LaunchAtLoginText.message(for: .failed(.register, code: 7)))
        XCTAssertNotNil(LaunchAtLoginText.message(for: .failed(.unregister, code: 7)))
    }

    // MARK: - A request that changed nothing

    /// The SDK says a needs-approval item has been registered, so pressing "Switch
    /// on again" may come back as a success with the item still not enabled: as 12,
    /// which is read as so, or as no error, which is what a second registration of
    /// an enabled item gave on macOS 26.7.1 (measured on 2026-10-05). What it gives
    /// for an item that needs approval was not measured. Nothing said would leave a
    /// button with no result.
    func testARegistrationThatCameToWhatWasAskedButLeavesTheItemNotEnabledIsSaid() {
        let succeeded = LaunchAtLogin.outcome(ofRequest: .register, domain: domain, code: 12)
        XCTAssertEqual(succeeded, .succeeded, "what Switch on again may answer for an item that needs approval")
        func after(_ status: LoginItemStatus) -> LaunchAtLogin.Outcome {
            LaunchAtLogin.outcomeAfterReading(succeeded, ofRequest: .register, statusAfter: status)
        }
        XCTAssertEqual(after(.requiresApproval), .needsApproval, "the status says it needs approval")
        XCTAssertEqual(after(.notRegistered), .notEnabled)
        XCTAssertEqual(after(.notFound), .notEnabled)
        XCTAssertEqual(after(.enabled), .succeeded, "enabled is what was asked, and nothing is said")
        XCTAssertNil(LaunchAtLoginText.message(for: after(.enabled)))
        for status in LoginItemStatus.allCases where status != .enabled {
            XCTAssertNotNil(LaunchAtLoginText.message(for: after(status)), "\(status) leaves a button with no result")
        }
    }

    /// Only a registration that came to what was asked is read against the status
    /// after it: a failure is already said, and an unregistration is left to the
    /// status shown after it.
    func testNothingElseIsChangedByTheStatusReadAfterwards() {
        let others: [(LaunchAtLogin.Request, LaunchAtLogin.Outcome)] = [
            (.register, .needsApproval), (.register, .unsignedCopy), (.register, .notEnabled),
            (.register, .failed(.register, code: 7)), (.unregister, .succeeded), (.unregister, .failed(.unregister, code: 7)),
        ]
        for (request, outcome) in others {
            for status in LoginItemStatus.allCases {
                XCTAssertEqual(LaunchAtLogin.outcomeAfterReading(outcome, ofRequest: request, statusAfter: status), outcome,
                               "\(request) \(outcome) read as \(status)")
            }
        }
    }

    func testARegistrationThatLeavesTheItemNotEnabledSaysSoAndSaysNoMoreThanWasRead() throws {
        let message = try XCTUnwrap(LaunchAtLoginText.message(for: .notEnabled))
        XCTAssertEqual(message, "macOS still does not report Launch at login as enabled. You can look in Login Items, in System Settings.")
        XCTAssertFalse(LoginItemClaim.isMadeBy(message), message)
        XCTAssertFalse(message.contains("approval"), "it does not name a state the status did not read")
        XCTAssertFalse(message.contains("signature"), message)
        XCTAssertFalse(message.contains("error"), "no code was given")
        XCTAssertNotEqual(message, LaunchAtLoginText.needsApproval)
    }

    func testAnUnknownFailureSaysWhichRequestFailedAndTheCodeAndNothingElse() throws {
        let on = try XCTUnwrap(LaunchAtLoginText.message(for: .failed(.register, code: 7)))
        let off = try XCTUnwrap(LaunchAtLoginText.message(for: .failed(.unregister, code: 7)))
        XCTAssertEqual(on, "Launch at login could not be switched on. macOS gave error 7.")
        XCTAssertEqual(off, "Launch at login could not be switched off. macOS gave error 7.")
        XCTAssertTrue(try XCTUnwrap(LaunchAtLoginText.message(for: .failed(.register, code: -1))).contains("error -1"))
        // The domain is logged by the adapter and never shown, nor is any text of the error.
        XCTAssertFalse(on.contains("Domain") || on.contains("SMAppService"), on)
    }

    func testEachKindOfFailureHasItsOwnWords() throws {
        let approval = try XCTUnwrap(LaunchAtLoginText.message(for: .needsApproval))
        let unsigned = try XCTUnwrap(LaunchAtLoginText.message(for: .unsignedCopy))
        let switchOn = try XCTUnwrap(LaunchAtLoginText.message(for: .failed(.register, code: 7)))
        let switchOff = try XCTUnwrap(LaunchAtLoginText.message(for: .failed(.unregister, code: 7)))
        let notEnabled = try XCTUnwrap(LaunchAtLoginText.message(for: .notEnabled))
        XCTAssertEqual(Set([approval, unsigned, switchOn, switchOff, notEnabled]).count, 5, "two failures read alike")
        XCTAssertTrue(unsigned.contains("signature"), unsigned)
        XCTAssertFalse(approval.contains("signature"), approval)
        XCTAssertFalse(unsigned.contains("approval"), unsigned)
    }

    func testNoFailureSaysTheItemIsOn() {
        let outcomes: [LaunchAtLogin.Outcome] = [.needsApproval, .unsignedCopy, .notEnabled,
                                                  .failed(.register, code: 7), .failed(.unregister, code: 7)]
        for outcome in outcomes {
            let message = LaunchAtLoginText.message(for: outcome) ?? ""
            XCTAssertFalse(LoginItemClaim.isMadeBy(message), message)
        }
    }

    func testAnApprovalFailureSendsTheUserToLoginItemsAndOnlyThatPlace() throws {
        let message = try XCTUnwrap(LaunchAtLoginText.message(for: .needsApproval))
        XCTAssertTrue(message.contains("approval"))
        XCTAssertTrue(message.contains("Login Items"))
        XCTAssertFalse(message.contains(LaunchAtLoginText.openLoginItems),
                       "a button's words are not said where no such button is shown")
    }
}
