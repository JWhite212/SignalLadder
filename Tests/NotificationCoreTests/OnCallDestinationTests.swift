import XCTest
@testable import NotificationCore

/// Where each On-Call Check finding's button takes the user (workflow audit, 2026-10-16,
/// finding 4). The window opens itself with a beep when a finding turns up, and before this
/// only the login finding had a button: every other finding named a problem and left the user
/// to find where it is fixed. Each destination only opens a pane or a window and switches
/// nothing on, so O12 is kept. The login finding keeps its own button, which acts
/// (`Finding.action`), and no finding has both.
final class OnCallDestinationTests: XCTestCase {
    private let sounds = RuleReach(enabled: 1, alertingAloud: 1, withShortcut: 0)

    private func inputs(health: CaptureHealth = .verified, apps: [String] = [], outputSilent: Bool = false,
                        alertVolume: Double? = 1, reach: RuleReach? = nil,
                        status: RuleStoreStatus = .loaded(enabled: 1, disabled: 0), warnings: [RuleWarning] = [],
                        loginItem: LaunchAtLogin.State? = nil) -> OnCallCheck.Inputs {
        OnCallCheck.Inputs(health: health, unconfirmedMutedApps: apps, outputSilent: outputSilent, alertVolume: alertVolume,
                           reach: reach ?? sounds, ruleStatus: status, ruleWarnings: warnings,
                           loginItem: loginItem, acknowledgeHotkeyRegistered: true)
    }

    private func destination(of kind: OnCallCheck.Finding.Kind, in given: OnCallCheck.Inputs,
                             file: StaticString = #filePath, line: UInt = #line) throws -> OnCallCheck.Destination? {
        try XCTUnwrap(OnCallCheck.findings(given).first { $0.kind == kind }, "no \(kind) finding", file: file, line: line)
            .destination
    }

    func testAHealthFindingOpensThePaneItsCauseNames() throws {
        XCTAssertEqual(try destination(of: .health, in: inputs(health: .blind([.accessibilityNotTrusted]))), .pane(.accessibility))
        XCTAssertEqual(try destination(of: .health, in: inputs(health: .degraded([.lazyAccessibilityTree]))), .pane(.keyboard))
        XCTAssertEqual(try destination(of: .health, in: inputs(health: .degraded([.selfTestAlertNeverSeen]))), .pane(.notifications))
        XCTAssertNil(try destination(of: .health, in: inputs(health: .blind([.observerNotAttached]))), "no pane fixes it")
        XCTAssertNil(try destination(of: .health, in: inputs(health: .degraded([]))), "no cause, no pane")
        XCTAssertNil(try destination(of: .notVerifiedYet, in: inputs(health: .unknown)), "Check Now is beneath it")
    }

    func testASilentOutputAndASilentAlertVolumeOpenSound() throws {
        XCTAssertEqual(try destination(of: .outputMuted, in: inputs(outputSilent: true)), .soundSettings)
        XCTAssertEqual(try destination(of: .beepsInaudible, in: inputs(alertVolume: 0)), .soundSettings)
    }

    func testEveryFindingAboutTheRulesOpensTheRuleEditor() throws {
        let problem = RuleSetCodec.Problem(index: 0, name: "Pager", reason: "no alert")
        XCTAssertEqual(try destination(of: .rulesNotInEffect,
                                       in: inputs(status: .loadedWithProblems(enabled: 1, disabled: 0, rejected: [problem]))), .ruleEditor)
        XCTAssertEqual(try destination(of: .rulesFileNotInEffect, in: inputs(status: .unreadable("not JSON"))), .ruleEditor)
        XCTAssertEqual(try destination(of: .noRuleEnabled,
                                       in: inputs(reach: RuleReach(enabled: 0, alertingAloud: 0, withShortcut: 0),
                                                  status: .noRulesFile)), .ruleEditor)
        XCTAssertEqual(try destination(of: .noSoundOrShortcut,
                                       in: inputs(reach: RuleReach(enabled: 2, alertingAloud: 0, withShortcut: 0))), .ruleEditor)
        XCTAssertEqual(try destination(of: .shortcutNotFound,
                                       in: inputs(warnings: [RuleWarning(ruleName: "Pager", shortcutName: "Page me", sentence: "x")])),
                       .ruleEditor)
        XCTAssertEqual(try destination(of: .alertCannotPlay,
                                       in: inputs(warnings: [RuleWarning(ruleName: "Pager", kind: .cannotPlay, sentence: "x")])),
                       .ruleEditor)
    }

    func testUnconfirmedMutingOpensTheGuideAndTheAdvisoriesOpenFocusOrNothing() throws {
        XCTAssertEqual(try destination(of: .unconfirmedMuting, in: inputs(apps: ["Microsoft Teams"])), .setupGuide)
        XCTAssertEqual(try destination(of: .focus, in: inputs()), .focusSettings)
        XCTAssertNil(try destination(of: .sleep, in: inputs()))
    }

    /// The login finding keeps the button that acts, and no finding has both.
    func testTheLoginFindingActsAndNoFindingBothActsAndOpens() throws {
        let given = inputs(health: .blind([.accessibilityNotTrusted]), apps: ["Teams"], outputSilent: true, alertVolume: 0,
                           loginItem: .off(wanted: false))
        let login = try XCTUnwrap(OnCallCheck.findings(given).first { $0.kind == .loginItemOff })
        XCTAssertNotNil(login.action)
        XCTAssertNil(login.destination)
        for finding in OnCallCheck.findings(given) {
            XCTAssertFalse(finding.action != nil && finding.destination != nil, "\(finding.kind)")
        }
    }

    /// Each button reads as the place it opens is named elsewhere in the app.
    func testEachDestinationsButtonInTheWordsTheAppUsesForThatPlace() {
        XCTAssertEqual(OnCallText.label(for: .pane(.notifications)), SetupText.label(for: .openNotificationSettings))
        XCTAssertEqual(OnCallText.label(for: .pane(.accessibility)), SetupText.label(for: .openAccessibilitySettings))
        XCTAssertEqual(OnCallText.label(for: .pane(.keyboard)), SetupText.label(for: .openKeyboardSettings))
        XCTAssertEqual(OnCallText.label(for: .soundSettings), "Open Sound Settings…")
        XCTAssertEqual(OnCallText.label(for: .focusSettings), MuteWalkthroughText.openFocusSettings)
        XCTAssertEqual(OnCallText.label(for: .ruleEditor), StatusMenuText.editRulesTitle)
        XCTAssertEqual(OnCallText.label(for: .setupGuide), SetupText.openGuideButton)
    }

    /// Measured on macOS 27.2 on 2026-10-16: this opened System Settings › Sound, which
    /// shows Alert volume and the output.
    func testTheSoundPanesAddress() {
        XCTAssertEqual(BundleResolver.soundSettingsURL.absoluteString, "x-apple.systempreferences:com.apple.Sound-Settings.extension")
    }
}

/// How the check window shows those buttons and the app carries them out. The app target has
/// no tests, so this reads its sources.
final class OnCallDestinationWiringTests: XCTestCase {
    func testTheWindowShowsAButtonForADestinationWhereAFindingHasNoAction() throws {
        let view = try code("OnCallCheckView.swift")
        XCTAssertEqual(count("} else if let destination = finding.destination {", in: view), 1)
        XCTAssertEqual(count("Button(OnCallText.label(for: destination)) { model.open(destination) }", in: view), 1)
        let controller = try code("OnCallCheckWindowController.swift")
        XCTAssertEqual(count("var open: (OnCallCheck.Destination) -> Void = { _ in }", in: controller), 1)
    }

    func testTheAppOpensEachDestinationThroughTheDoorThatAlreadyOpensIt() throws {
        let app = try code("AppDelegate.swift")
        XCTAssertEqual(count("controller.model.open = { [weak self] destination in self?.open(destination) }", in: app), 1)
        let open = try XCTUnwrap(SourceCode.body(of: "private func open(_ destination: OnCallCheck.Destination) {", in: app))
        XCTAssertEqual(open.trimmingCharacters(in: .whitespacesAndNewlines), [
            "switch destination {",
            "case .pane(let pane): OnboardingCoordinator.open(pane)",
            "case .soundSettings: NSWorkspace.shared.open(BundleResolver.soundSettingsURL)",
            "case .focusSettings: NSWorkspace.shared.open(BundleResolver.focusSettingsURL)",
            "case .ruleEditor: showRuleEditor()",
            "case .setupGuide: showSetupGuide()",
            "}",
        ].joined(separator: "\n"))
    }
}
