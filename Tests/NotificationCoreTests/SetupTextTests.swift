import XCTest
@testable import NotificationCore

/// Reading a line of words by its place.
private extension Array where Element == String {
    /// The line at `index`, or "" with a failure recorded when there is none, so that a test
    /// that reads a line by its place fails at that line and does not stop the run.
    func at(_ index: Int, file: StaticString = #filePath, line: UInt = #line) -> String {
        guard indices.contains(index) else {
            XCTFail("no line \(index) in \(self)", file: file, line: line)
            return ""
        }
        return self[index]
    }
}

/// The words of the first run (M5 plan, Ruling 16, Ruling 18, Task 7): every step's title,
/// reason, state, detail and buttons, and the summary. Nothing here reads the real
/// preferences, calls the system, shows a window or waits on a clock: each test gives the
/// facts as plain values and reads what the words say. What a sentence says is typed out in
/// the test, except where the test is that an existing sentence is reused, which is then
/// held to the existing constant. App names here are invented (§10.1).
final class SetupTextTests: XCTestCase {
    typealias Notifications = SetupFacts.Notifications
    typealias Words = SetupText.StepWords
    typealias Action = SetupText.ButtonAction

    // MARK: - Building facts

    private func progress(introduction: Bool = false, focus: Bool = false, skipped: [SetupStep] = [],
                          dismissed: Bool = false, finished: Bool = false) -> SetupProgress {
        var result = SetupProgress()
        if introduction { result.recordIntroductionSeen() }
        if focus { result.recordFocusAttested() }
        for step in skipped { result.recordSkipped(step) }
        if dismissed { result.recordDismissed() }
        if finished { result.recordFinished() }
        return result
    }

    private let allowedAndShown = Notifications(permission: .allowed, wouldDisplay: true)
    private let oneRuleAlertsAloud = RuleReach(enabled: 1, alertingAloud: 1, withShortcut: 0)
    private let noRuleReach = RuleReach(enabled: 0, alertingAloud: 0, withShortcut: 0)

    private func problem() -> RuleSetCodec.Problem {
        RuleSetCodec.Problem(index: 0, name: nil, reason: "not a rule")
    }

    /// A configured upgrader with nothing stored, on the app's first second: health reads
    /// "Checking…", the login item is off, no app is named yet. Each test changes what it
    /// is about. In it the introduction is outstanding, Accessibility and Notifications
    /// are done, "Prove it can read" is outstanding, the first rule is done, muting is not
    /// applicable, the Focus is outstanding and so is the login item.
    private func facts(trusted: Bool = true,
                       notifications: Notifications? = Notifications(permission: .allowed, wouldDisplay: true),
                       health: CaptureHealth = .unknown,
                       lastVerifiedAt: Date? = nil,
                       ruleStatus: RuleStoreStatus = .loaded(enabled: 1, disabled: 0),
                       reach: RuleReach = RuleReach(enabled: 1, alertingAloud: 1, withShortcut: 0),
                       readOnly: RulesDocument.ReadOnlyReason? = nil,
                       captured: Bool = false,
                       capturedApps: [String] = [],
                       appsToMute: [String] = [],
                       checklist: MuteChecklist = MuteChecklist(),
                       loginItem: LaunchAtLogin.State = .off(wanted: false),
                       progress: SetupProgress = SetupProgress()) -> SetupFacts {
        SetupFacts(accessibilityTrusted: trusted, notifications: notifications, health: health,
                   lastVerifiedAt: lastVerifiedAt, ruleStatus: ruleStatus, ruleReach: reach,
                   rulesFileReadOnly: readOnly, anythingCaptured: captured, capturedAppNames: capturedApps,
                   appsToMute: appsToMute, muteChecklist: checklist, loginItem: loginItem, progress: progress)
    }

    private func confirmed(_ apps: [String]) -> MuteChecklist {
        var checklist = MuteChecklist()
        for app in apps { checklist.setConfirmed(app, true) }
        return checklist
    }

    /// 2026-10-06 at the given time of day, in UTC.
    private func at(_ hour: Int, _ minute: Int) -> Date {
        var parts = DateComponents()
        parts.year = 2026
        parts.month = 10
        parts.day = 6
        parts.hour = hour
        parts.minute = minute
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: parts)!
    }

    /// How the menu shows a moment: the hour and minute, "14:02".
    private func clock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func words(_ step: SetupStep, _ facts: SetupFacts) -> Words {
        SetupText.words(for: step, facts: facts, time: clock)
    }

    private func labels(_ step: SetupStep, _ facts: SetupFacts) -> [String] {
        SetupText.buttons(for: step, facts: facts).map(\.label)
    }

    private func summary(_ facts: SetupFacts) -> SetupText.Summary {
        SetupText.summary(facts, time: clock)
    }

    /// The lines of several parts, one after the other, joined without a chain of operators for
    /// the compiler to solve (CI's older compiler infers a long one differently).
    private func joined(_ parts: [String]...) -> [String] {
        var all: [String] = []
        for part in parts { all += part }
        return all
    }

    // MARK: - Every state a step can be in

    private let causes: [HealthCause] = [
        .notificationPermissionDenied, .notificationsSuppressed, .selfTestInconclusive, .selfTestAlertNeverSeen,
        .ownAlertsNotShown, .accessibilityNotTrusted, .observerNotAttached, .lazyAccessibilityTree,
    ]

    /// Every shape of health: verified, unread, and a problem that names each cause, or
    /// several, or none (which `HealthEvaluator` never builds, and which is still a
    /// problem).
    private var healths: [CaptureHealth] {
        var all: [CaptureHealth] = [.verified, .unknown, .degraded([]), .blind([])]
        for cause in causes {
            all.append(.degraded([cause]))
            all.append(.blind([cause]))
        }
        all.append(.degraded([.selfTestAlertNeverSeen, .notificationsSuppressed]))
        return all
    }

    private var notificationFacts: [Notifications?] {
        var all: [Notifications?] = [nil]
        all.append(Notifications(permission: .notAsked, wouldDisplay: false))
        all.append(Notifications(permission: .denied, wouldDisplay: false))
        all.append(Notifications(permission: .allowed, wouldDisplay: false))
        all.append(Notifications(permission: .allowed, wouldDisplay: true))
        all.append(Notifications(permission: .denied, wouldDisplay: true))
        return all
    }

    private let everyLoginItem: [LaunchAtLogin.State] = [
        .on, .off(wanted: false), .off(wanted: true), .switchedOffInSystemSettings,
        .unavailable(.translocated), .unavailable(.elsewhere),
    ]

    private struct RulesCase {
        let status: RuleStoreStatus
        let reach: RuleReach
        let readOnly: RulesDocument.ReadOnlyReason?
    }

    private struct CaptureCase {
        let captured: Bool
        let names: [String]
    }

    private struct MuteCase {
        let apps: [String]
        let checklist: MuteChecklist
    }

    /// Facts that between them put every step into every state it can be in, crossed in
    /// three groups, since a step's words depend on its own facts: health with the time of
    /// the last success, the notification fact and a skip; the rules, what was captured
    /// and the mute checklist; and the login item with what is stored and Accessibility.
    private var spread: [SetupFacts] {
        var all: [SetupFacts] = []
        let stamps: [Date?] = [nil, at(14, 2)]
        for health in healths {
            for stamp in stamps {
                for notification in notificationFacts {
                    for kept in [SetupProgress(), progress(skipped: [.proveItCanRead])] {
                        all.append(facts(notifications: notification, health: health, lastVerifiedAt: stamp,
                                         progress: kept))
                    }
                }
            }
        }

        var rules: [RulesCase] = []
        rules.append(RulesCase(status: .noRulesFile, reach: noRuleReach, readOnly: nil))
        rules.append(RulesCase(status: .loaded(enabled: 1, disabled: 0), reach: oneRuleAlertsAloud, readOnly: nil))
        rules.append(RulesCase(status: .loaded(enabled: 1, disabled: 0),
                               reach: RuleReach(enabled: 1, alertingAloud: 0, withShortcut: 1), readOnly: nil))
        rules.append(RulesCase(status: .unreadable("not json"), reach: noRuleReach, readOnly: nil))
        rules.append(RulesCase(status: .unsupportedVersion(9), reach: noRuleReach, readOnly: nil))
        rules.append(RulesCase(status: .loaded(enabled: 0, disabled: 1), reach: noRuleReach,
                               readOnly: .undecodable([problem()])))

        var captures: [CaptureCase] = []
        captures.append(CaptureCase(captured: false, names: []))
        captures.append(CaptureCase(captured: true, names: []))
        captures.append(CaptureCase(captured: true, names: ["Alpha App", "alpha app", " ", "Beta App"]))

        let two = ["Alpha App", "Beta App"]
        var mutes: [MuteCase] = []
        mutes.append(MuteCase(apps: [], checklist: MuteChecklist()))
        mutes.append(MuteCase(apps: two, checklist: MuteChecklist()))
        mutes.append(MuteCase(apps: two, checklist: confirmed(["Alpha App"])))
        mutes.append(MuteCase(apps: two, checklist: confirmed(two)))

        var stored: [SetupProgress] = [SetupProgress()]
        stored.append(progress(introduction: true, focus: true))
        stored.append(progress(skipped: [.keepItRunning]))

        for rule in rules {
            for capture in captures {
                for mute in mutes {
                    for kept in stored {
                        all.append(facts(ruleStatus: rule.status, reach: rule.reach, readOnly: rule.readOnly,
                                         captured: capture.captured, capturedApps: capture.names,
                                         appsToMute: mute.apps, checklist: mute.checklist, progress: kept))
                    }
                }
            }
        }

        for item in everyLoginItem {
            for kept in [SetupProgress(), progress(skipped: [.keepItRunning]), progress(introduction: true),
                         progress(finished: true)] {
                for trusted in [true, false] {
                    all.append(facts(trusted: trusted, loginItem: item, progress: kept))
                }
            }
        }
        return all
    }

    /// Every line of words the facts give: each step's lines and the summary's.
    private func everyLine(_ facts: SetupFacts) -> [String] {
        SetupStep.allCases.flatMap { words($0, facts).lines } + summary(facts).lines
    }

    private func kind(_ state: SetupPlan.State) -> String {
        switch state {
        case .done: return "done"
        case .outstanding: return "outstanding"
        case .unknown: return "unknown"
        case .notApplicable: return "notApplicable"
        case .blocked: return "blocked"
        case .skipped: return "skipped"
        }
    }

    func testTheFactsHereDoPutEveryStepIntoEveryStateItCanBeIn() {
        var seen = Set<String>()
        for facts in spread {
            for step in SetupStep.allCases { seen.insert("\(step)/\(kind(SetupPlan.state(of: step, in: facts)))") }
        }
        let expected: Set<String> = [
            "howItWorks/outstanding", "howItWorks/done",
            "accessibility/outstanding", "accessibility/done",
            "notifications/outstanding", "notifications/done", "notifications/unknown",
            "proveItCanRead/outstanding", "proveItCanRead/done", "proveItCanRead/skipped",
            "firstRule/outstanding", "firstRule/done", "firstRule/blocked",
            "muteSourceApp/outstanding", "muteSourceApp/done", "muteSourceApp/notApplicable",
            "focus/outstanding", "focus/done",
            "keepItRunning/outstanding", "keepItRunning/done", "keepItRunning/skipped",
        ]
        XCTAssertEqual(seen, expected)
    }

    // MARK: - Titles, reasons and actions

    func testEachTitleIsTheOneThePlansOrderNames() {
        XCTAssertEqual(SetupStep.allCases.map(SetupText.title(for:)),
                       ["How it works", "Accessibility", "Notifications", "Prove it can read", "First rule",
                        "Mute the source app", "Do Not Disturb and Focus", "Keep it running"])
        XCTAssertEqual(Set(SetupStep.allCases.map(SetupText.title(for:))).count, 8, "none is another's")
    }

    func testEveryStepHasATitleAReasonAStatusAndAnActionInEveryStateItCanBeIn() {
        for facts in spread {
            for step in SetupStep.allCases {
                let shown = words(step, facts)
                XCTAssertEqual(shown.title, SetupText.title(for: step))
                XCTAssertFalse(shown.why.isEmpty, "\(step): a reason")
                XCTAssertFalse(shown.buttons.isEmpty, "\(step) in \(kind(SetupPlan.state(of: step, in: facts))): an action")
                for line in shown.lines {
                    XCTAssertFalse(line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(step): a blank line")
                }
                XCTAssertEqual(shown.why, SetupText.why(for: step), "what a step says before it asks does not depend on facts")
            }
        }
    }

    func testEveryStepOfThePlanIsInTheSummaryAsReadOrAsTheUsersWordOrIsTheIntroduction() {
        let said = SetupText.readSteps + SetupText.wordSteps + [.howItWorks]
        XCTAssertEqual(said.count, SetupStep.allCases.count)
        XCTAssertEqual(Set(said), Set(SetupStep.allCases))
        XCTAssertEqual(SetupText.readSteps, [.accessibility, .notifications, .proveItCanRead, .firstRule, .keepItRunning])
        XCTAssertEqual(SetupText.wordSteps, [.muteSourceApp, .focus])
    }

    // MARK: - The buttons

    /// Each action's label as the plan words it, typed out. No default arm, so an action
    /// added later has to be given its words here as well.
    private func expectedLabel(_ action: Action) -> String {
        switch action {
        case .continueOn: return "Continue"
        case .skip: return "Skip"
        case .notNow: return "Not now"
        case .checkAgain: return "Check again"
        case .continueWithoutVerifying: return "Continue without verifying"
        case .allowAccessibility: return "Allow Accessibility…"
        case .openAccessibilitySettings: return "Open Accessibility Settings…"
        case .allowNotifications: return "Allow Notifications…"
        case .openNotificationSettings: return "Open Notification Settings…"
        case .makeRule: return "Make a Rule from This…"
        case .openRulesFile: return "Open Rules File in Text Editor"
        case .confirmMuted: return "I've Turned Its Sound Off"
        case .openAppNotificationSettings: return "Open Its Notification Settings…"
        case .openFocusSettings: return "Open Focus Settings…"
        case .confirmFocus: return "I've Checked My Focus Settings"
        case .openLoginItems: return "Open Login Items…"
        case .finish: return "Finish"
        }
    }

    func testEachButtonCarriesTheVerbItsStepNeeds() {
        XCTAssertEqual(Action.allCases.count, 17)
        for action in Action.allCases { XCTAssertEqual(SetupText.label(for: action), expectedLabel(action), "\(action)") }
        XCTAssertEqual(Set(Action.allCases.map(SetupText.label(for:))).count, Action.allCases.count,
                       "no two buttons are labelled alike")
        // The first word is the verb the step needs.
        let verbs: [Action: String] = [.allowAccessibility: "Allow", .allowNotifications: "Allow",
                                       .openAccessibilitySettings: "Open", .openNotificationSettings: "Open",
                                       .openRulesFile: "Open", .openFocusSettings: "Open",
                                       .openAppNotificationSettings: "Open", .openLoginItems: "Open", .makeRule: "Make",
                                       .checkAgain: "Check", .continueOn: "Continue",
                                       .continueWithoutVerifying: "Continue"]
        for (action, verb) in verbs {
            XCTAssertTrue(SetupText.label(for: action).hasPrefix(verb + " ") || SetupText.label(for: action) == verb,
                          "\(action)")
        }
    }

    func testTheButtonsAreTheExistingOnesWhereOneExists() {
        XCTAssertEqual(SetupText.label(for: .confirmMuted), MuteWalkthroughText.confirm)
        XCTAssertEqual(SetupText.label(for: .openFocusSettings), MuteWalkthroughText.openFocusSettings)
        XCTAssertEqual(SetupText.label(for: .openLoginItems), LaunchAtLoginText.openLoginItems)
        XCTAssertEqual(SetupText.label(for: .openLoginItems), LaunchAtLoginText.label(for: .openLoginItems))
    }

    func testTheButtonsOfEachStepInEachStateItCanBeIn() {
        let base = facts()
        // 0
        XCTAssertEqual(labels(.howItWorks, base), ["Continue"])
        XCTAssertEqual(labels(.howItWorks, facts(progress: progress(introduction: true))), ["Continue"])
        // 1: asks, opens its pane, checks again; done moves on
        XCTAssertEqual(labels(.accessibility, facts(trusted: false)),
                       ["Allow Accessibility…", "Open Accessibility Settings…", "Check again"])
        XCTAssertEqual(labels(.accessibility, base), ["Continue"])
        // 2: a request where one can still show a dialog, the settings otherwise
        XCTAssertEqual(labels(.notifications, facts(notifications: Notifications(permission: .notAsked, wouldDisplay: false))),
                       ["Allow Notifications…", "Check again"])
        XCTAssertEqual(labels(.notifications, facts(notifications: Notifications(permission: .denied, wouldDisplay: false))),
                       ["Open Notification Settings…", "Check again"])
        XCTAssertEqual(labels(.notifications, facts(notifications: Notifications(permission: .allowed, wouldDisplay: false))),
                       ["Open Notification Settings…", "Check again"])
        XCTAssertEqual(labels(.notifications, facts(notifications: nil)), ["Check again"])
        XCTAssertEqual(labels(.notifications, base), ["Continue"])
        // 3
        XCTAssertEqual(labels(.proveItCanRead, base), ["Check again", "Continue without verifying"])
        XCTAssertEqual(labels(.proveItCanRead, facts(health: .verified)), ["Continue"])
        XCTAssertEqual(labels(.proveItCanRead, facts(progress: progress(skipped: [.proveItCanRead]))),
                       ["Check again", "Continue"])
        // 4
        XCTAssertEqual(labels(.firstRule, facts(ruleStatus: .noRulesFile, reach: noRuleReach)), ["Check again"])
        XCTAssertEqual(labels(.firstRule, facts(ruleStatus: .noRulesFile, reach: noRuleReach, captured: true,
                                                capturedApps: ["Alpha App"])), ["Make a Rule from This…"])
        XCTAssertEqual(labels(.firstRule, facts(ruleStatus: .unreadable("x"), reach: noRuleReach)),
                       ["Open Rules File in Text Editor", "Check again"])
        XCTAssertEqual(labels(.firstRule, base), ["Continue"])
        // 5
        let apps = ["Alpha App", "Beta App"]
        XCTAssertEqual(labels(.muteSourceApp, facts(appsToMute: apps)),
                       ["I've Turned Its Sound Off", "Open Its Notification Settings…"])
        XCTAssertEqual(labels(.muteSourceApp, facts(appsToMute: apps, checklist: confirmed(apps))), ["Continue"])
        XCTAssertEqual(labels(.muteSourceApp, base), ["Continue"], "nothing to confirm yet")
        // 6
        XCTAssertEqual(labels(.focus, base), ["Open Focus Settings…", "I've Checked My Focus Settings"])
        XCTAssertEqual(labels(.focus, facts(progress: progress(focus: true))), ["Continue"])
        // 7
        XCTAssertEqual(labels(.keepItRunning, base), ["Continue", "Skip"])
        XCTAssertEqual(labels(.keepItRunning, facts(loginItem: .on)), ["Continue"])
        XCTAssertEqual(labels(.keepItRunning, facts(progress: progress(skipped: [.keepItRunning]))), ["Continue", "Skip"])
        // switched off in System Settings, or waiting for approval there: the way to Login Items first
        XCTAssertEqual(labels(.keepItRunning, facts(loginItem: .switchedOffInSystemSettings)),
                       ["Open Login Items…", "Continue", "Skip"])
        XCTAssertEqual(labels(.keepItRunning, facts(loginItem: .switchedOffInSystemSettings,
                                                    progress: progress(skipped: [.keepItRunning]))),
                       ["Open Login Items…", "Continue", "Skip"])
        // the summary
        XCTAssertEqual(summary(base).buttons.map(\.label), ["Finish"])
        XCTAssertEqual(summary(base).buttons.map(\.action), [.finish])
    }

    /// A login item the system has switched off, or holds for approval, is switched on in
    /// System Settings, so the last step offers the way there, and only for that. It opens a
    /// pane and asks for nothing: no button here registers again, whose answer was not measured.
    func testTheWayToLoginItemsIsOfferedOnlyForAnItemTheSystemHasSwitchedOff() {
        for facts in spread {
            for step in SetupStep.allCases {
                let offered = SetupText.buttons(for: step, facts: facts).contains { $0.action == .openLoginItems }
                let state = SetupPlan.state(of: step, in: facts)
                let expected = step == .keepItRunning && facts.loginItem == .switchedOffInSystemSettings && !state.isDone
                XCTAssertEqual(offered, expected, "\(step) in \(kind(state)) with \(facts.loginItem)")
            }
            XCTAssertFalse(summary(facts).buttons.contains { $0.action == .openLoginItems })
        }
        // The spread does include the state, so that the first half was run where it is offered.
        XCTAssertTrue(spread.contains { $0.loginItem == .switchedOffInSystemSettings })
        for state in everyLoginItem where state != .switchedOffInSystemSettings {
            XCTAssertFalse(SetupText.buttons(for: .keepItRunning, facts: facts(loginItem: state)).contains { $0.action == .openLoginItems },
                           "\(state)")
        }
        // Nothing here asks the system to register again: the same Settings button is not carried over.
        XCTAssertFalse(Action.allCases.map(SetupText.label(for:)).contains(LaunchAtLoginText.switchOnAgain))
    }

    func testAButtonIsMadeOfItsActionAndItsLabel() {
        for facts in spread {
            for step in SetupStep.allCases {
                for button in SetupText.buttons(for: step, facts: facts) {
                    XCTAssertEqual(button.label, SetupText.label(for: button.action))
                }
            }
        }
    }

    // MARK: - Step 0, how it works

    func testTheIntroductionSaysTheReplacementModelAndTheThreeLimitsPlainly() {
        let why = SetupText.why(for: .howItWorks)
        XCTAssertEqual(why.count, 5)
        // Spec §1.1: meant to replace the source app's sound and not to add to it. Until that is
        // turned off every alert plays on top of the app's own ping, as the pages say, and then
        // SignalLadder is its only voice. It never says that it adds no sound on top.
        XCTAssertTrue(why.at(0).contains("is meant to replace an app's notification sound, not to add to it"), why.at(0))
        XCTAssertTrue(why.at(0).contains("Until you turn the source app's sound off in System Settings, every alert plays on top of the app's own ping"), why.at(0))
        XCTAssertFalse(why.at(0).contains("does not add sound on top"), "true only once the source app is muted: \(why.at(0))")
        XCTAssertTrue(why.at(0).contains("Turn it off, and SignalLadder becomes its only voice"), why.at(0))
        let onTop = why.at(0).range(of: "plays on top")
        let onlyVoice = why.at(0).range(of: "its only voice")
        XCTAssertNotNil(onTop)
        XCTAssertNotNil(onlyVoice)
        if let onTop, let onlyVoice { XCTAssertLessThan(onTop.lowerBound, onlyVoice.lowerBound, "the condition comes before the result") }
        XCTAssertTrue(why.at(0).contains("silent by default"), why.at(0))
        XCTAssertTrue(why.at(0).contains("sounding only when a rule earns it"), why.at(0))
        XCTAssertEqual(why.at(1), "Three limits, said plainly:")
        // The Accessibility grant is broader than its use.
        XCTAssertTrue(why.at(2).contains("Accessibility permission is broader than SignalLadder's use of it"), why.at(2))
        // SignalLadder cannot silence the source app's own sound.
        XCTAssertTrue(why.at(3).contains("cannot silence the source app's own sound"), why.at(3))
        // A Focus hides banners, in the walkthrough's own words.
        XCTAssertEqual(why.at(4), "Do Not Disturb and other Focus modes hide banners, so nothing can be captured while one is on.")
        XCTAssertEqual(why.at(4), MuteWalkthroughText.focus.prefix(2).joined(separator: " "))
    }

    func testTheIntroductionRestsOnTheUsersWordOnceItIsRead() {
        let outstanding = words(.howItWorks, facts())
        XCTAssertNil(outstanding.basis)
        XCTAssertEqual(outstanding.status, "You have not been through this yet.")
        XCTAssertEqual(outstanding.detail, [])
        let read = words(.howItWorks, facts(progress: progress(introduction: true)))
        XCTAssertEqual(read.status, "You have read this.")
        XCTAssertEqual(read.basis, "Your word, which SignalLadder cannot check")
    }

    // MARK: - Step 1, Accessibility

    func testAccessibilityIsExplainedBeforeItIsAskedAndTheGrantsCaveatIsSaidWithIt() {
        let why = SetupText.why(for: .accessibility)
        XCTAssertEqual(why.count, 3)
        XCTAssertTrue(why.at(0).contains("reads notification banners through macOS Accessibility"), why.at(0))
        XCTAssertTrue(why.at(0).contains("only reads: it never clicks, dismisses, replies or types"), why.at(0))
        // The caveat in docs/privacy.md: the grant is broader than its use, and only the app's code holds it.
        XCTAssertTrue(why.at(1).contains("broader than SignalLadder's use of it"), why.at(1))
        XCTAssertTrue(why.at(1).contains("no grant that means “notifications only”"), why.at(1))
        XCTAssertTrue(why.at(1).contains("only SignalLadder's own code holds it to Notification Centre"), why.at(1))
        // Nothing is asked until the button is pressed.
        XCTAssertEqual(why.at(2), "macOS shows its own prompt only when you press the button, and not before.")
    }

    func testAccessibilityStatesWhatWasReadAndNoMore() {
        XCTAssertEqual(words(.accessibility, facts(trusted: false)).status,
                       "macOS does not report Accessibility as allowed for SignalLadder.")
        let done = words(.accessibility, facts())
        XCTAssertEqual(done.status, "macOS reports that Accessibility is allowed for SignalLadder.")
        XCTAssertEqual(done.basis, "Read by SignalLadder")
    }

    // MARK: - Step 2, Notifications

    func testNotificationsSaysNothingIsKnownYetWhileTheFactIsNil() {
        let unknown = words(.notifications, facts(notifications: nil))
        XCTAssertEqual(unknown.status, "SignalLadder has not found out yet whether it may show notifications.")
        XCTAssertEqual(unknown.detail, [])
        XCTAssertNil(unknown.basis)
        XCTAssertEqual(unknown.buttons.map(\.action), [.checkAgain])
    }

    func testNotificationsOffersARequestOnlyWhereOneCanStillShowADialog() {
        let asked = words(.notifications, facts(notifications: Notifications(permission: .notAsked, wouldDisplay: false)))
        XCTAssertEqual(asked.status, "SignalLadder has not asked for permission to show notifications yet. Pressing the button asks, and macOS may show its own prompt.")
        XCTAssertEqual(asked.detail, ["macOS shows its own prompt only when you press the button, and not before."])
        XCTAssertEqual(asked.buttons.map(\.action), [.allowNotifications, .checkAgain])
    }

    func testNotificationsDeniedOffersTheSettingsAndSaysWhatMacOSReportedAndNoMore() {
        let denied = words(.notifications, facts(notifications: Notifications(permission: .denied, wouldDisplay: false)))
        XCTAssertEqual(denied.status, "macOS does not report notifications as allowed for SignalLadder.")
        XCTAssertEqual(denied.detail, [HealthCause.notificationPermissionDenied.advice], "the health line's own advice, not written again")
        XCTAssertEqual(denied.buttons.map(\.action), [.openNotificationSettings, .checkAgain])
        XCTAssertFalse(denied.buttons.contains { $0.action == .allowNotifications }, "a request may show no dialog")
    }

    func testNotificationsThatMayPostButWouldNotBeDrawnSaysSoAndWhatToLookAt() {
        let hidden = words(.notifications, facts(notifications: Notifications(permission: .allowed, wouldDisplay: false)))
        XCTAssertEqual(hidden.status, "macOS allows SignalLadder to post notifications, but its own banners would not be drawn.")
        XCTAssertEqual(hidden.detail,
                       ["In System Settings › Notifications › SignalLadder, its banners need to be switched on (the Desktop checkbox on macOS 26, an alert style other than None before it, and not Deliver Quietly), Notification Centre needs to be switched on, and a Scheduled Summary must not be holding its notifications."])
        XCTAssertEqual(hidden.buttons.map(\.action), [.openNotificationSettings, .checkAgain])
    }

    /// The advice is the three settings `DeliveryStatusProbe` reads to decide a banner would not be
    /// drawn: the alert style, Notification Centre and the Scheduled Summary. A user whose only
    /// fault is one of them is told to look at that one, and macOS 14 and 15 are told what to look
    /// at for the first as macOS 26 is. Deliver Quietly is a gloss on the first, not a fourth.
    func testTheAdviceForBannersThatWouldNotBeDrawnNamesEachOfTheThreeSettingsTheProbeReads() {
        let advice = SetupText.notificationsBannerAdvice
        XCTAssertEqual(words(.notifications, facts(notifications: Notifications(permission: .allowed, wouldDisplay: false))).detail,
                       [advice], "it is what the step shows for this reading")
        // The alert style: the Desktop checkbox on macOS 26, an alert style other than None before it.
        XCTAssertTrue(advice.contains("banners need to be switched on"), advice)
        XCTAssertTrue(advice.contains("the Desktop checkbox on macOS 26"), advice)
        XCTAssertTrue(advice.contains("an alert style other than None before it"), advice)
        // Notification Centre, which the probe reads and the sentence once left out.
        XCTAssertTrue(advice.contains("Notification Centre needs to be switched on"), advice)
        // The Scheduled Summary.
        XCTAssertTrue(advice.contains("a Scheduled Summary must not be holding its notifications"), advice)
        // Deliver Quietly is said inside the account of the banners, and nowhere else.
        let quietly = advice.range(of: "Deliver Quietly")
        let closing = advice.range(of: ")")
        let centre = advice.range(of: "Notification Centre")
        XCTAssertNotNil(quietly)
        if let quietly, let closing, let centre {
            XCTAssertLessThan(quietly.lowerBound, closing.lowerBound, "inside the brackets that gloss the banners")
            XCTAssertLessThan(closing.lowerBound, centre.lowerBound)
        } else {
            XCTFail("no closing bracket or no Notification Centre in: \(advice)")
        }
        let mentions = advice.components(separatedBy: "Deliver Quietly").count - 1
        XCTAssertEqual(mentions, 1)
        // It is said only for a permission that is allowed and banners that would not show.
        for facts in spread {
            let shown = words(.notifications, facts)
            let hidden = facts.notifications == Notifications(permission: .allowed, wouldDisplay: false)
            XCTAssertEqual(shown.detail.contains(advice), hidden, "\(String(describing: facts.notifications))")
        }
    }

    func testNotificationsDoneIsWhatMacOSReportedAndNoMoreThanThat() {
        let done = words(.notifications, facts())
        XCTAssertEqual(done.status, "macOS reports that SignalLadder may show notifications, and its own banners would be drawn.")
        XCTAssertEqual(done.detail, [])
        XCTAssertEqual(done.basis, "Read by SignalLadder")
        XCTAssertEqual(done.buttons.map(\.action), [.continueOn])
        // Allowed alone is not done, and a banner that would display for an app that is not allowed is not done.
        XCTAssertEqual(SetupPlan.state(of: .notifications, in: facts(notifications: Notifications(permission: .denied, wouldDisplay: true))), .outstanding)
        XCTAssertEqual(words(.notifications, facts(notifications: Notifications(permission: .denied, wouldDisplay: true))).status,
                       "macOS does not report notifications as allowed for SignalLadder.")
    }

    // MARK: - Step 3, prove it can read

    func testProvingItCanReadSaysItCanReadItsOwnTestBannerAndNothingOfTheUsersOtherApps() {
        let why = SetupText.why(for: .proveItCanRead)
        XCTAssertEqual(why.count, 2)
        XCTAssertTrue(why.at(0).contains("shows itself a test banner and checks that it can read it"), why.at(0))
        XCTAssertTrue(why.at(1).contains("it can read its own test banner, and no more"), why.at(1))
        XCTAssertTrue(why.at(1).contains("says nothing about the banners of your other apps"), why.at(1))
        // Never that the user's notifications will be captured, in any state.
        for facts in spread {
            for line in words(.proveItCanRead, facts).lines {
                let lower = line.lowercased()
                XCTAssertFalse(lower.contains("will be captured"), line)
                XCTAssertFalse(lower.contains("will be read"), line)
                XCTAssertFalse(lower.contains("your notifications"), line)
            }
        }
    }

    func testAVerifiedHealthIsVerifiedAtTheTimeTheFactsGiveInTheMenusFormat() {
        let verified = facts(health: .verified, lastVerifiedAt: at(14, 2))
        let shown = words(.proveItCanRead, verified)
        XCTAssertEqual(shown.status, "SignalLadder read its own test banner: verified at 14:02.")
        XCTAssertEqual(shown.basis, "Read by SignalLadder")
        XCTAssertEqual(shown.detail, [])
        XCTAssertEqual(shown.buttons.map(\.action), [.continueOn])
        // The time is shown as the closure shows it.
        XCTAssertEqual(SetupText.status(for: .proveItCanRead, facts: verified, time: { _ in "two o'clock" }),
                       "SignalLadder read its own test banner: verified at two o'clock.")
        // No time kept: no time said.
        XCTAssertEqual(words(.proveItCanRead, facts(health: .verified, lastVerifiedAt: nil)).status,
                       "SignalLadder read its own test banner: verified.")
    }

    func testAnUnreadHealthSaysNothingWasReadAndGivesTheTimeOfTheLastReadOnlyAsThat() {
        let none = words(.proveItCanRead, facts(health: .unknown))
        XCTAssertEqual(none.status, "SignalLadder has not read a test banner of its own yet.")
        XCTAssertEqual(none.detail, [], "no cause is given, since none was found")
        XCTAssertNil(none.basis)
        // An old success beside a health that has gone stale is the time of a read, and is not verified.
        let stale = words(.proveItCanRead, facts(health: .unknown, lastVerifiedAt: at(14, 2)))
        XCTAssertEqual(stale.status, "SignalLadder last read a test banner of its own at 14:02, and has no newer one.")
        XCTAssertFalse(stale.lines.joined(separator: " ").lowercased().contains("verified"))
        XCTAssertEqual(stale.detail, [])
    }

    private func expectedPane(_ cause: HealthCause) -> Action {
        switch cause {
        case .notificationPermissionDenied, .notificationsSuppressed, .selfTestInconclusive,
             .selfTestAlertNeverSeen, .ownAlertsNotShown:
            return .openNotificationSettings
        case .accessibilityNotTrusted, .observerNotAttached, .lazyAccessibilityTree:
            return .openAccessibilitySettings
        }
    }

    func testAProblemShowsTheCauseHealthGivesItsAdviceAndTheLinkTheMenusAdviceLineOpens() {
        for cause in causes {
            for health in [CaptureHealth.degraded([cause]), CaptureHealth.blind([cause])] {
                let shown = words(.proveItCanRead, facts(health: health))
                XCTAssertEqual(shown.detail, [cause.advice], "the advice the health line carries, once: \(cause)")
                XCTAssertEqual(shown.status, HealthTitle.text(for: health, secondsSinceLastSuccessfulCanary: nil))
                XCTAssertEqual(shown.buttons.map(\.action), [.checkAgain, expectedPane(cause), .continueWithoutVerifying],
                               "\(cause)")
                XCTAssertNil(shown.basis)
            }
        }
        XCTAssertEqual(words(.proveItCanRead, facts(health: .degraded([.selfTestInconclusive]))).status, "Cannot verify itself")
        XCTAssertEqual(words(.proveItCanRead, facts(health: .blind([.accessibilityNotTrusted]))).status,
                       "NOT capturing notifications")
    }

    func testOnlyTheFirstCauseIsShownWhenHealthGivesSeveral() {
        let shown = words(.proveItCanRead,
                          facts(health: .degraded([.selfTestAlertNeverSeen, .notificationsSuppressed])))
        XCTAssertEqual(shown.detail, [HealthCause.selfTestAlertNeverSeen.advice])
        XCTAssertEqual(shown.buttons.map(\.action), [.checkAgain, .openNotificationSettings, .continueWithoutVerifying])
    }

    func testAProblemThatNamesNoCauseIsStillAProblemAndIsGivenTheBannersFallbackBody() {
        for health in [CaptureHealth.degraded([]), CaptureHealth.blind([])] {
            let shown = words(.proveItCanRead, facts(health: health))
            XCTAssertEqual(shown.detail, ["Open the menu for details."], "\(health)")
            XCTAssertEqual(shown.detail, [SelfNotification.fallbackBody])
            XCTAssertEqual(shown.status, HealthTitle.text(for: health, secondsSinceLastSuccessfulCanary: nil))
            // Never "still checking", which is said only of a health that has not been read.
            for line in shown.lines {
                XCTAssertFalse(line.lowercased().contains("checking"), line)
                XCTAssertFalse(line.lowercased().contains("not read"), line)
            }
            XCTAssertEqual(shown.buttons.map(\.action), [.checkAgain, .continueWithoutVerifying], "no pane is named for no cause")
        }
    }

    func testContinuingWithoutVerifyingMovesOnAndTheStepIsNotThenSaidToBeProven() {
        let skipped = facts(health: .blind([.lazyAccessibilityTree]), progress: progress(skipped: [.proveItCanRead]))
        let shown = words(.proveItCanRead, skipped)
        XCTAssertEqual(shown.status, "NOT capturing notifications. You continued without it.")
        XCTAssertEqual(shown.detail, [HealthCause.lazyAccessibilityTree.advice], "the cause and its advice stand")
        XCTAssertNil(shown.basis)
        XCTAssertEqual(shown.buttons.map(\.action), [.checkAgain, .continueOn])
        let unread = words(.proveItCanRead, facts(progress: progress(skipped: [.proveItCanRead])))
        XCTAssertEqual(unread.status, "SignalLadder has not read a test banner of its own yet. You continued without it.")
        // A fact beats a stored skip: verified is verified whatever was skipped.
        let beaten = words(.proveItCanRead, facts(health: .verified, lastVerifiedAt: at(9, 30),
                                                  progress: progress(skipped: [.proveItCanRead])))
        XCTAssertEqual(beaten.status, "SignalLadder read its own test banner: verified at 09:30.")
    }

    // MARK: - Step 4, the first rule

    func testTheFirstRuleSaysWhereTheLadderIsChosenInTheWordsTheEditorUses() {
        let why = SetupText.why(for: .firstRule)
        XCTAssertEqual(why.count, 3)
        XCTAssertTrue(why.at(0).contains("from a real one it has read"), why.at(0))
        XCTAssertEqual(why.at(1), "In the editor, choose how it escalates under “If I don't acknowledge”.")
        XCTAssertTrue(why.at(1).contains(EditorText.ifIDontAcknowledge), "the editor's own heading")
        XCTAssertEqual(why.at(2), "This step is done when a rule that is switched on makes a sound or speaks.")
    }

    func testWhileNothingHasArrivedTheFirstRuleShowsThePracticeLineAsTextToSelect() {
        let quiet = words(.firstRule, facts(ruleStatus: .noRulesFile, reach: noRuleReach))
        XCTAssertEqual(quiet.selectable,
                       #"osascript -e 'display notification "Placeholder body" with title "Test title" subtitle "Test subtitle"'"#,
                       "the line in docs/getting-started.md")
        XCTAssertEqual(quiet.detail,
                       ["Nothing has arrived yet. To see a banner straight away, post a practice notification from a terminal window. SignalLadder does not run this line and does not copy it: select it and paste it yourself.",
                        "The practice banner arrives as Script Editor, so if none is drawn, check that Script Editor is allowed to show notifications in System Settings › Notifications. A rule made from it is for practice only: it will not match your real notifications. Make your first real rule from a real notification, and delete the practice rule afterwards."])
        XCTAssertEqual(quiet.apps, [])
        XCTAssertEqual(quiet.status, "No rule that is switched on and makes a sound or speaks is in effect.")
        XCTAssertNil(quiet.basis)
        // The words say the app neither runs nor copies it, and offer nothing that does.
        XCTAssertTrue(quiet.detail.at(0).contains("does not run this line and does not copy it"))
        XCTAssertFalse(quiet.buttons.contains { [.makeRule, .openRulesFile].contains($0.action) })
        // It is shown only while nothing has arrived, and only while the step is outstanding.
        let arrived = words(.firstRule, facts(ruleStatus: .noRulesFile, reach: noRuleReach, captured: true,
                                              capturedApps: ["Alpha App"]))
        XCTAssertNil(arrived.selectable)
        XCTAssertNil(words(.firstRule, facts()).selectable)
        XCTAssertNil(words(.firstRule, facts(ruleStatus: .unreadable("x"), reach: noRuleReach)).selectable)
        XCTAssertTrue(quiet.lines.contains(SetupText.practiceCommand), "it is among what the step shows, for scanning")
    }

    func testOnceBannersHaveArrivedTheFirstRuleListsAppNamesOnlyAndSaysHowManyInWords() {
        let some = words(.firstRule, facts(ruleStatus: .noRulesFile, reach: noRuleReach, captured: true,
                                           capturedApps: ["Alpha App", "alpha app", "  ", "Beta App", "Alpha App"]))
        XCTAssertEqual(some.apps, ["Alpha App", "Beta App"], "each once, as first seen, none blank")
        XCTAssertEqual(some.detail, ["SignalLadder has read banners from 2 apps. Make a rule from a notification you want to be paged for, and not from a practice banner."])
        XCTAssertEqual(some.buttons.map(\.label), ["Make a Rule from This…"])
        XCTAssertNil(some.selectable)
        let one = words(.firstRule, facts(ruleStatus: .noRulesFile, reach: noRuleReach, captured: true,
                                          capturedApps: ["Alpha App"]))
        XCTAssertEqual(one.detail, ["SignalLadder has read banners from 1 app. Make a rule from a notification you want to be paged for, and not from a practice banner."])
        let nameless = words(.firstRule, facts(ruleStatus: .noRulesFile, reach: noRuleReach, captured: true,
                                               capturedApps: [" "]))
        XCTAssertEqual(nameless.apps, [])
        XCTAssertEqual(nameless.detail, ["SignalLadder has read banners, and none of them gave an app name. Make a rule from a notification you want to be paged for, and not from a practice banner."])
        for shown in [some, one, nameless] {
            for line in shown.lines { XCTAssertFalse(line.contains("Alpha App") || line.contains("Beta App"), line) }
        }
    }

    func testABlockedFirstRuleGivesTheEditorsReasonAndOffersTheRulesFileInATextEditor() {
        let reasons: [RulesDocument.ReadOnlyReason] = [
            .unreadable("not json"), .newerVersion(9), .undecodable([problem()]),
        ]
        for reason in reasons {
            let shown = words(.firstRule, facts(ruleStatus: .noRulesFile, reach: noRuleReach, readOnly: reason))
            XCTAssertEqual(shown.status, EditorText.readOnly(reason).title, "the editor's own words for it")
            XCTAssertEqual(shown.buttons.map(\.label), ["Open Rules File in Text Editor", "Check again"])
            XCTAssertEqual(shown.detail, [])
            XCTAssertNil(shown.selectable)
            XCTAssertEqual(shown.apps, [])
        }
        XCTAssertEqual(words(.firstRule, facts(ruleStatus: .noRulesFile, reach: noRuleReach, readOnly: .newerVersion(9))).status,
                       "The rules file was written by a newer SignalLadder (format 9).")
        // The reason is the editor's title, which holds a count or a format and not a rule's name.
        XCTAssertEqual(words(.firstRule, facts(ruleStatus: .unreadable("not json"), reach: noRuleReach)).status,
                       "The rules file can't be read, so it can't be edited here.")
    }

    func testAFirstRuleThatIsInEffectIsDoneOnWhatWasRead() {
        let done = words(.firstRule, facts())
        XCTAssertEqual(done.status, "A rule that is switched on and makes a sound or speaks is in effect.")
        XCTAssertEqual(done.basis, "Read by SignalLadder")
        XCTAssertEqual(done.detail, [])
        XCTAssertEqual(done.buttons.map(\.action), [.continueOn])
    }

    // MARK: - Step 5, mute the source app

    func testMutingIsTheUsersWordAndOnlyTheSoundIsTurnedOffWhileBannersStayOn() {
        let why = SetupText.why(for: .muteSourceApp)
        XCTAssertEqual(why.count, 2)
        XCTAssertTrue(why.at(0).contains("Turn off the notification sound of each app listed"), why.at(0))
        XCTAssertTrue(why.at(0).contains("its only voice"), why.at(0))
        XCTAssertTrue(why.at(0).contains("Turn off only the sound: leave banners on"), why.at(0))
        XCTAssertTrue(why.at(0).contains("because SignalLadder reads banners"), why.at(0))
        XCTAssertEqual(why.at(1), "SignalLadder cannot check that an app is muted. Your tick is your word, and nothing else backs it.")
    }

    func testMutingStatesHowManyAreNotConfirmedWithoutNamingThemAndListsTheNamesApart() {
        let apps = ["Alpha App", "Beta App"]
        let two = words(.muteSourceApp, facts(appsToMute: apps))
        XCTAssertEqual(two.status, "2 apps not confirmed muted", "the on-call check's own count")
        XCTAssertEqual(two.status, OnCallText.unconfirmedMuting(count: 2))
        XCTAssertEqual(two.apps, apps)
        XCTAssertNil(two.basis)
        let one = words(.muteSourceApp, facts(appsToMute: apps, checklist: confirmed(["Alpha App"])))
        XCTAssertEqual(one.status, "1 app not confirmed muted")
        XCTAssertEqual(one.apps, apps, "the apps stay listed, each as it was")
        for shown in [two, one] {
            for line in shown.lines { XCTAssertFalse(line.contains("Alpha App") || line.contains("Beta App"), line) }
        }
    }

    func testMutingConfirmedIsSaidToBeTheUsersWordAndNotAReading() {
        let apps = ["Alpha App", "Beta App"]
        let done = words(.muteSourceApp, facts(appsToMute: apps, checklist: confirmed(apps)))
        XCTAssertEqual(done.status, "You said you turned off the sound of every app listed.")
        XCTAssertEqual(done.basis, "Your word, which SignalLadder cannot check")
        XCTAssertEqual(done.apps, apps)
    }

    func testMutingBeforeTheFirstRuleSaysItWaitsForTheRule() {
        let noRule = words(.muteSourceApp, facts(ruleStatus: .noRulesFile, reach: noRuleReach, appsToMute: ["Alpha App"]))
        XCTAssertEqual(noRule.status, "Nothing to confirm yet: this step opens once your first rule is made.")
        XCTAssertEqual(noRule.apps, [], "no app is named before a rule that sounds exists")
        XCTAssertEqual(noRule.buttons.map(\.action), [.continueOn])
        XCTAssertNil(noRule.basis)
        // No rule and no app to name: the rule is what is waited for.
        XCTAssertEqual(words(.muteSourceApp, facts(ruleStatus: .noRulesFile, reach: noRuleReach)).status, noRule.status)
    }

    /// A rule that matches by pattern names no app until something sounds, so the step has none
    /// to list although the first rule is done. That is not "nothing to do": nothing is confirmed
    /// muted, and the source app's own sound is neither checked nor silenced by SignalLadder.
    func testMutingWithARuleAndNoAppToNameSaysSoAndNeverThatThereIsNothingToDo() {
        let noApp = words(.muteSourceApp, facts())
        XCTAssertEqual(SetupPlan.state(of: .firstRule, in: facts()), .done(.fact), "the rule is in effect")
        XCTAssertEqual(SetupPlan.state(of: .muteSourceApp, in: facts()), .notApplicable)
        XCTAssertEqual(noApp.status, "SignalLadder has no app to name yet, so nothing is confirmed muted. It neither checks nor silences the source app's own sound, so turning that off is still up to you.")
        XCTAssertEqual(noApp.apps, [])
        XCTAssertEqual(noApp.buttons.map(\.action), [.continueOn])
        XCTAssertNil(noApp.basis, "nothing is done, so nothing rests on anything")
        XCTAssertNotEqual(noApp.status, words(.muteSourceApp, facts(ruleStatus: .noRulesFile, reach: noRuleReach)).status,
                          "a rule that exists is not a rule that is waited for")
        // It does not say the step waits for a rule that is already made, or that nothing is needed.
        XCTAssertFalse(noApp.status.contains("first rule"), noApp.status)
        XCTAssertFalse(noApp.status.contains("Nothing to confirm"), noApp.status)
        XCTAssertFalse(noApp.status.lowercased().contains("nothing to do"), noApp.status)
        // The same whether the guide was met before or the Focus was attested: it follows the two facts.
        XCTAssertEqual(words(.muteSourceApp, facts(progress: progress(introduction: true, focus: true))).status, noApp.status)
        // A pattern rule that has sounded gives an app to name, and then the step has something to confirm.
        XCTAssertEqual(words(.muteSourceApp, facts(appsToMute: ["Alpha App"])).status, "1 app not confirmed muted")
    }

    // MARK: - Step 6, Do Not Disturb and Focus

    func testTheFocusStepReusesTheWalkthroughsAdviceTheWorkaroundAndSaysItIsTheUsersWord() {
        let why = SetupText.why(for: .focus)
        XCTAssertEqual(why.count, 3)
        XCTAssertEqual(why.at(0), MuteWalkthroughText.focus.joined(separator: " "), "the walkthrough's own advice, once")
        XCTAssertEqual(why.at(0), "Do Not Disturb and other Focus modes hide banners, so nothing can be captured while one is on. Check whether one turns on when your screen locks.")
        // That a Focus cannot be read, and the workaround the findings note records.
        XCTAssertEqual(why.at(1), "SignalLadder cannot read whether one is on. Allowing the source app to break through a Focus keeps its banners showing.")
        XCTAssertEqual(why.at(1), OnCallText.focusCannotRead + " " + OnCallText.focusWorkaround)
        XCTAssertEqual(why.at(2), "Your tick is your word, and nothing else backs it.")
    }

    func testTheFocusStepOffersTheSettingsAndTheUsersWordAndRestsOnItOnceGiven() {
        let outstanding = words(.focus, facts())
        XCTAssertEqual(outstanding.status, "You have not said that you checked your Focus settings.")
        XCTAssertEqual(outstanding.buttons.map(\.label), ["Open Focus Settings…", "I've Checked My Focus Settings"])
        XCTAssertNil(outstanding.basis)
        let done = words(.focus, facts(progress: progress(focus: true)))
        XCTAssertEqual(done.status, "You said you checked your Focus settings.")
        XCTAssertEqual(done.basis, "Your word, which SignalLadder cannot check")
        XCTAssertEqual(done.buttons.map(\.action), [.continueOn])
    }

    // MARK: - Step 7, keep it running

    func testKeepingItRunningSaysOnCallModeWorksOnlyWhileTheAppIsRunning() {
        let why = SetupText.why(for: .keepItRunning)
        XCTAssertEqual(why, ["On-call mode works only while SignalLadder is running.",
                             "Launch at login starts SignalLadder when you log in, and it is your choice whether it does."])
    }

    func testWhileTheLoginItemIsOffTheStepSaysSignalLadderMayNotStartAgainAndNothingOfAnEntryAddedByHand() {
        let off = words(.keepItRunning, facts(loginItem: .off(wanted: false)))
        XCTAssertEqual(off.status, "macOS does not report SignalLadder as set to start when you log in.")
        XCTAssertEqual(off.status, SettingsText.offSentence, "Settings' own sentence")
        XCTAssertEqual(off.detail, ["Launch at login starts ticked. Continue with it ticked switches it on. Skip, or Continue with it unticked, switches nothing on.",
                                    "SignalLadder may not start again after a restart or log out."])
        // Where the box sits is the window's to decide, so no line says where.
        for facts in spread {
            for line in words(.keepItRunning, facts).lines {
                for place in ["below", "above", "beside", "next to"] { XCTAssertFalse(line.lowercased().contains(place), line) }
            }
        }
        XCTAssertEqual(off.detail.at(1), OnCallText.loginItemMayNotStart, "the on-call finding's own, hedged, sentence")
        XCTAssertEqual(off.tickBox, "Launch at login")
        XCTAssertTrue(off.lines.contains("Launch at login"), "the box's label is among what the step shows")
        XCTAssertEqual(off.buttons.map(\.label), ["Continue", "Skip"])
        for facts in spread {
            for line in words(.keepItRunning, facts).lines + summary(facts).lines {
                XCTAssertFalse(line.lowercased().contains("by hand"), line)
                XCTAssertFalse(line.lowercased().contains("unless"), line)
            }
        }
    }

    func testTheBoxIsShownOnlyForALoginItemThatIsOffAndEachStateIsSaidInSettingsWords() {
        let wanted = words(.keepItRunning, facts(loginItem: .off(wanted: true)))
        XCTAssertEqual(wanted.status, SettingsText.offButWantedSentence)
        XCTAssertEqual(wanted.tickBox, "Launch at login", "whatever the user had wanted")

        let on = words(.keepItRunning, facts(loginItem: .on))
        XCTAssertEqual(on.status, SettingsText.onSentence)
        XCTAssertEqual(on.status, "macOS reports that SignalLadder is set to start when you log in.")
        XCTAssertEqual(on.basis, "Read by SignalLadder")
        XCTAssertNil(on.tickBox)
        XCTAssertEqual(on.detail, [], "an item that is on has no restart to warn of")
        XCTAssertEqual(on.buttons.map(\.label), ["Continue"])

        let switchedOff = words(.keepItRunning, facts(loginItem: .switchedOffInSystemSettings))
        XCTAssertEqual(switchedOff.status, SettingsText.switchedOffSentence)
        XCTAssertNil(switchedOff.tickBox)
        XCTAssertEqual(switchedOff.detail, ["SignalLadder may not start again after a restart or log out."], "no box, so nothing about it")
        XCTAssertEqual(switchedOff.buttons.map(\.label), ["Open Login Items…", "Continue", "Skip"], "the way to where the user decides")

        for why in LaunchAtLogin.Unavailable.allCases {
            let unavailable = words(.keepItRunning, facts(loginItem: .unavailable(why)))
            XCTAssertEqual(unavailable.status, LaunchAtLoginText.reason(for: why), "the reason, with the move that fixes it")
            XCTAssertNil(unavailable.tickBox)
            XCTAssertEqual(unavailable.detail, ["SignalLadder may not start again after a restart or log out."])
            XCTAssertEqual(unavailable.buttons.map(\.label), ["Continue", "Skip"])
        }
    }

    func testASkippedLoginItemSaysItWasSkippedAndWhatMacOSReports() {
        let skipped = words(.keepItRunning, facts(loginItem: .off(wanted: false), progress: progress(skipped: [.keepItRunning])))
        XCTAssertEqual(skipped.status, "Skipped. macOS does not report SignalLadder as set to start when you log in.")
        XCTAssertNil(skipped.basis, "a skip is not a login item that is on")
        XCTAssertEqual(skipped.buttons.map(\.label), ["Continue", "Skip"])
        XCTAssertEqual(skipped.tickBox, "Launch at login", "it can still be ticked")
    }

    // MARK: - The summary

    func testTheSummarySeparatesWhatWasReadFromWhatIsTheUsersWord() {
        let everything = facts(health: .verified, lastVerifiedAt: at(14, 2),
                               appsToMute: ["Alpha App"], checklist: confirmed(["Alpha App"]),
                               loginItem: .on,
                               progress: progress(introduction: true, focus: true))
        let shown = summary(everything)
        XCTAssertEqual(shown.title, "Where setup stands")
        XCTAssertEqual(shown.readHeading, "What SignalLadder read")
        XCTAssertEqual(shown.read, [
            "macOS reports that Accessibility is allowed for SignalLadder.",
            "macOS reports that SignalLadder may show notifications, and its own banners would be drawn.",
            "SignalLadder read its own test banner: verified at 14:02.",
            "A rule that is switched on and makes a sound or speaks is in effect.",
            "macOS reports that SignalLadder is set to start when you log in.",
        ])
        XCTAssertEqual(shown.wordHeading, "Your word, which SignalLadder cannot check")
        XCTAssertEqual(shown.word, [
            "You said you turned off the sound of every app listed.",
            "You said you checked your Focus settings.",
        ])
        // What was read is never the user's word, and the word is never a reading.
        for line in shown.read { XCTAssertFalse(line.lowercased().contains("you said"), line) }
        for line in shown.word { XCTAssertFalse(line.lowercased().contains("macos reports"), line) }
        XCTAssertEqual(shown.buttons.map(\.label), ["Finish"])
        // Every line of words it holds, for scanning: the headings, both groups, the two lines and the button.
        XCTAssertEqual(shown.lines, joined([shown.title, shown.readHeading], shown.read, [shown.wordHeading], shown.word,
                                           [shown.onCall, shown.snooze, "Finish"]))
        XCTAssertEqual(shown.lines.count, 13)
    }

    func testTheSummaryDoesNotSayItIsVerifiedForAStepThatWasSkippedOrAHealthThatIsNot() {
        let skipped = summary(facts(health: .degraded([.selfTestInconclusive]), lastVerifiedAt: at(14, 2),
                                    progress: progress(skipped: [.proveItCanRead])))
        XCTAssertEqual(skipped.read.at(2), "Cannot verify itself. You continued without it.")
        let unread = summary(facts(health: .unknown, progress: progress(skipped: [.proveItCanRead])))
        XCTAssertEqual(unread.read.at(2), "SignalLadder has not read a test banner of its own yet. You continued without it.")
        let verified = summary(facts(health: .verified, lastVerifiedAt: nil, progress: progress(skipped: [.proveItCanRead])))
        XCTAssertEqual(verified.read.at(2), "SignalLadder read its own test banner: verified.", "a fact beats a skip, and no time is made up")
    }

    func testTheSummaryGivesWhatIsOutstandingAsOutstandingAndNotAsDone() {
        let unfinished = summary(facts(trusted: false, notifications: nil, ruleStatus: .noRulesFile, reach: noRuleReach))
        XCTAssertEqual(unfinished.read.at(0), "macOS does not report Accessibility as allowed for SignalLadder.")
        XCTAssertEqual(unfinished.read.at(1), "SignalLadder has not found out yet whether it may show notifications.")
        XCTAssertEqual(unfinished.read.at(3), "No rule that is switched on and makes a sound or speaks is in effect.")
        XCTAssertEqual(unfinished.word.at(0), "Nothing to confirm yet: this step opens once your first rule is made.")
        XCTAssertEqual(unfinished.word.at(1), "You have not said that you checked your Focus settings.")
        // With the rule made and no app to name, the summary does not read as nothing to do.
        let noApp = summary(facts())
        XCTAssertEqual(noApp.word.at(0), "SignalLadder has no app to name yet, so nothing is confirmed muted. It neither checks nor silences the source app's own sound, so turning that off is still up to you.")
        XCTAssertEqual(noApp.word.at(1), "You have not said that you checked your Focus settings.")
    }

    func testTheSummarysTwoLinesSayWhenToUseOnCallModeAndSnooze() {
        let shown = summary(facts(loginItem: .on))
        XCTAssertEqual(shown.onCall, "When your shift starts: On Call in the menu. It works only while SignalLadder is running, and Launch at login is on.")
        XCTAssertEqual(shown.snooze, "Before a meeting: Snooze in the menu; it quiets only the rules you have ticked.")
        XCTAssertEqual(SetupText.snoozeLine, shown.snooze)
        // The menu's own words for the two items.
        XCTAssertTrue(shown.onCall.contains(OnCallText.menuTitle))
        XCTAssertTrue(shown.snooze.contains(SnoozeText.menuTitle))
        XCTAssertTrue(shown.onCall.contains(SettingsText.launchAtLoginSwitch))
    }

    func testTheOnCallLineSaysItWorksOnlyWhileTheAppIsRunningAndLaunchAtLoginOnOrOffExactlyAsTheFactSays() {
        for state in everyLoginItem {
            let line = summary(facts(loginItem: state)).onCall
            XCTAssertEqual(line, SetupText.onCallLine(loginItem: state))
            XCTAssertTrue(line.contains("It works only while SignalLadder is running"), "\(state): \(line)")
            XCTAssertTrue(line.hasPrefix("When your shift starts: On Call in the menu."), line)
            if state == .on {
                XCTAssertTrue(line.contains("Launch at login is on"), "\(state): \(line)")
                XCTAssertFalse(line.contains("Launch at login is off"), "\(state): \(line)")
                XCTAssertFalse(line.contains("may not start again"), "an item that is on is not warned of")
            } else {
                XCTAssertTrue(line.contains("Launch at login is off"), "\(state): \(line)")
                XCTAssertFalse(line.contains("Launch at login is on"), "\(state): \(line)")
                XCTAssertTrue(line.hasSuffix(" SignalLadder may not start again after a restart or log out."), line)
            }
        }
    }

    func testTheSummaryTakesTheTimeFromTheFactsAndSaysItAsTheClosureSaysIt() {
        let verified = facts(health: .verified, lastVerifiedAt: at(23, 59))
        XCTAssertEqual(SetupText.summary(verified, time: clock).read.at(2), "SignalLadder read its own test banner: verified at 23:59.")
        XCTAssertEqual(SetupText.summary(verified, time: { _ in "T" }).read.at(2), "SignalLadder read its own test banner: verified at T.")
        // A time beside a health that is not verified is never said as a verification.
        for health in [CaptureHealth.unknown, .degraded([]), .blind([.observerNotAttached])] {
            let line = SetupText.summary(facts(health: health, lastVerifiedAt: at(23, 59)), time: clock).read.at(2)
            XCTAssertFalse(line.lowercased().contains("verified"), line)
        }
    }

    // MARK: - What the words may claim

    /// No line says "verified" unless health is verified, and then only the lines about
    /// "Prove it can read": its status, and the summary's line for it.
    func testNoLineSaysVerifiedUnlessHealthIsVerified() {
        for facts in spread {
            let saying = everyLine(facts).filter { $0.lowercased().contains("verified") }
            if facts.health != .verified {
                XCTAssertEqual(saying, [], "\(facts.health) with \(String(describing: facts.lastVerifiedAt))")
                continue
            }
            // Verified: those two lines, and no other.
            let status = words(.proveItCanRead, facts).status
            XCTAssertEqual(saying, [status, summary(facts).read.at(2)])
            for step in SetupStep.allCases where step != .proveItCanRead {
                XCTAssertEqual(words(step, facts).lines.filter { $0.lowercased().contains("verified") }, [], "\(step)")
            }
        }
        // The spread does include a verified health, so that the second half was run.
        XCTAssertTrue(spread.contains { $0.health == .verified })
    }

    func testStepsThatRestOnTheUsersWordSayAndNoOtherStepDoes() {
        for facts in spread {
            for step in SetupStep.allCases {
                let shown = words(step, facts)
                let state = SetupPlan.state(of: step, in: facts)
                switch state {
                case .done(.yourWord):
                    XCTAssertEqual(shown.basis, "Your word, which SignalLadder cannot check", "\(step)")
                    XCTAssertTrue([SetupStep.howItWorks, .muteSourceApp, .focus].contains(step), "\(step)")
                case .done(.fact):
                    XCTAssertEqual(shown.basis, "Read by SignalLadder", "\(step)")
                    XCTAssertFalse([SetupStep.howItWorks, .muteSourceApp, .focus].contains(step), "\(step)")
                case .outstanding, .unknown, .notApplicable, .blocked, .skipped:
                    XCTAssertNil(shown.basis, "\(step)")
                }
            }
            // The two steps that are the user's word say so in what they say before they ask, and in their status once done.
            XCTAssertTrue(words(.muteSourceApp, facts).why.contains { $0.contains("your word") })
            XCTAssertTrue(words(.focus, facts).why.contains { $0.contains("your word") })
        }
        // A reading never calls itself the user's word.
        for facts in spread {
            for step in [SetupStep.accessibility, .notifications, .proveItCanRead, .firstRule, .keepItRunning] {
                for line in words(step, facts).lines {
                    XCTAssertFalse(line.lowercased().contains("your word"), "\(step): \(line)")
                }
            }
        }
    }

    func testThePatternForAFocusClaimMatchesWhatItForbids() {
        XCTAssertTrue(FocusClaim.isMade(by: "Your Focus is currently active"))
        XCTAssertTrue(FocusClaim.isMade(by: "Do Not Disturb is on"))
        XCTAssertTrue(FocusClaim.isMade(by: "Focus mode has been switched on"))
        XCTAssertTrue(FocusClaim.isMade(by: "do not disturb mode is now enabled"))
        XCTAssertTrue(FocusClaim.isMade(by: "A Focus was on at 14:02"))
        // The sentence the guide reuses is conditional, and says no Focus is on.
        XCTAssertFalse(FocusClaim.isMade(by: "so nothing can be captured while one is on."))
        XCTAssertFalse(FocusClaim.isMade(by: MuteWalkthroughText.focus.joined(separator: " ")))
        XCTAssertFalse(FocusClaim.isMade(by: SetupText.why(for: .focus).joined(separator: " ")))
    }

    func testNoLineSaysAFocusIsOnOrWasOn() {
        var lines: [String] = []
        for facts in spread { lines += everyLine(facts) }
        XCTAssertFalse(lines.isEmpty)
        // The reused sentence is among them, so that the pattern is run over what it must let pass.
        XCTAssertTrue(lines.contains(MuteWalkthroughText.focus.joined(separator: " ")))
        for line in Set(lines) { XCTAssertFalse(FocusClaim.isMade(by: line), line) }
        // And the constants, which no facts reach.
        for line in SetupStep.allCases.flatMap(SetupText.why(for:)) { XCTAssertFalse(FocusClaim.isMade(by: line), line) }
        for action in Action.allCases { XCTAssertFalse(FocusClaim.isMade(by: SetupText.label(for: action))) }
    }

    /// What a notification said, a rule's name and an app's name reach no line of words:
    /// each is given a marker no sentence holds, and what is listed (apps, in two steps) is
    /// the one place a name is.
    func testNoLineHoldsNotificationTextOrARulesNameAndAnAppIsNamedOnlyInTheListOfApps() {
        let marker = "CANARY-7f3a"
        let apps = ["\(marker) one", "\(marker) two", "\(marker) three", "\(marker) four"]
        let problems = [RuleSetCodec.Problem(index: 0, name: "\(marker) rule", reason: "bad \(marker)")]
        let reasons: [RulesDocument.ReadOnlyReason] = [
            .unreadable("not json \(marker)"), .newerVersion(9), .undecodable(problems),
        ]
        var all: [SetupFacts] = []
        for reason in reasons {
            all.append(facts(ruleStatus: .unreadable("\(marker) why"), reach: noRuleReach, readOnly: reason,
                             captured: true, capturedApps: apps, appsToMute: apps))
        }
        all.append(facts(ruleStatus: .loadedWithProblems(enabled: 1, disabled: 0, rejected: problems),
                         captured: true, capturedApps: apps, appsToMute: apps, checklist: confirmed([apps[0]])))
        all.append(facts(ruleStatus: .noRulesFile, reach: noRuleReach, captured: true, capturedApps: apps, appsToMute: apps))
        all.append(facts(captured: true, capturedApps: apps, appsToMute: apps, checklist: confirmed(apps),
                         progress: progress(introduction: true, focus: true)))
        all.append(facts(captured: true, capturedApps: apps, appsToMute: apps))

        var listed = Set<SetupStep>()
        for facts in all {
            for line in everyLine(facts) { XCTAssertFalse(line.contains(marker), line) }
            for step in SetupStep.allCases {
                let shown = words(step, facts)
                if !shown.apps.isEmpty {
                    listed.insert(step)
                    XCTAssertTrue(shown.apps.allSatisfy { $0.contains(marker) }, "\(step)")
                }
            }
        }
        XCTAssertEqual(listed, [.firstRule, .muteSourceApp], "the list is in two steps, and in no other")
        // Where a count would do, the line is a count: and says how many without saying which.
        XCTAssertEqual(SetupText.appsReadLine(count: 4), "SignalLadder has read banners from 4 apps. Make a rule from a notification you want to be paged for, and not from a practice banner.")
        XCTAssertEqual(OnCallText.unconfirmedMuting(count: 4), "4 apps not confirmed muted")
    }

    func testNoLineNamesAnAppOfItsOwnAndTheStepsNameOnlyTheListsTheFactsGave() {
        let names = ["Alpha App", "Beta App", "Microsoft Teams", "Slack", "Script Editor", "Terminal", "Outlook", "Mail"]
        var constants = SetupStep.allCases.flatMap(SetupText.why(for:))
        constants += SetupStep.allCases.map(SetupText.title(for:))
        constants += Action.allCases.map(SetupText.label(for:))
        constants += [SetupText.snoozeLine, SetupText.onCallLine(loginItem: .on), SetupText.onCallLine(loginItem: .off(wanted: false))]
        for facts in spread { constants += everyLine(facts) }
        // One line names an app of its own: the caution said with the practice line, which names the
        // fixed app the practice banner arrives as (a constant, and not read from a banner). It is
        // exempt from this check and from nothing else, and the test after this one holds it to that.
        for line in Set(constants) where line != SetupText.practiceCaution {
            for name in names { XCTAssertFalse(line.contains(name), "\(name) in: \(line)") }
        }
    }

    /// The practice banner arrives as Script Editor (`docs/getting-started.md`), and a rule made from
    /// it matches none of the user's real notifications, which reads as a first rule that is in effect
    /// and is the silent failure Ruling 20 names. So the practice line is never said alone: the
    /// caution comes with it and says where the banner arrives from, the one place to look if none is
    /// drawn, that a rule made from it is for practice only, and what to do instead. It names that
    /// one app and no other, and it is the only line that names any app of its own.
    func testThePracticeLineIsSaidWithItsCautionThatARuleMadeFromTheBannerIsForPracticeOnly() {
        let quiet = words(.firstRule, facts(ruleStatus: .noRulesFile, reach: noRuleReach))
        XCTAssertEqual(quiet.detail.count, 2)
        XCTAssertEqual(quiet.detail.at(0), SetupText.practiceLead)
        let caution = quiet.detail.at(1)
        XCTAssertEqual(caution, SetupText.practiceCaution)
        // Where the banner arrives from, and the one place to look if none is drawn.
        XCTAssertTrue(caution.hasPrefix("The practice banner arrives as Script Editor"), caution)
        XCTAssertTrue(caution.contains("if none is drawn, check that Script Editor is allowed to show notifications in System Settings › Notifications"), caution)
        // A rule made from it is for practice, matches no real notification, and is replaced.
        XCTAssertTrue(caution.contains("A rule made from it is for practice only: it will not match your real notifications"), caution)
        XCTAssertTrue(caution.contains("Make your first real rule from a real notification, and delete the practice rule afterwards"), caution)
        // It is said straight after the practice line, with the command to select beside them.
        let leadAt = quiet.lines.firstIndex(of: SetupText.practiceLead)
        let cautionAt = quiet.lines.firstIndex(of: SetupText.practiceCaution)
        XCTAssertNotNil(leadAt)
        if let leadAt { XCTAssertEqual(cautionAt, leadAt + 1) }
        XCTAssertEqual(quiet.selectable, SetupText.practiceCommand)
        // It names that app and no other.
        for other in ["Alpha App", "Beta App", "Microsoft Teams", "Slack", "Terminal", "Outlook", "Mail"] {
            XCTAssertFalse(caution.contains(other), "\(other) in: \(caution)")
        }
        // It is said only while nothing has arrived and the step is outstanding: once banners have
        // arrived, the line asks for a rule from a real notification, and in no other state is it said.
        var saying = 0
        for facts in spread {
            let shown = words(.firstRule, facts)
            let said = shown.detail.contains(SetupText.practiceCaution)
            XCTAssertEqual(said, shown.selectable != nil, "said exactly where the practice line is: \(shown.lines)")
            if said { saying += 1 }
            for step in SetupStep.allCases where step != .firstRule {
                XCTAssertFalse(words(step, facts).lines.contains(SetupText.practiceCaution), "\(step)")
            }
        }
        XCTAssertGreaterThan(saying, 0, "the spread does reach it")
        // The only line, anywhere, that names Script Editor, or any app, of its own.
        var naming = Set<String>()
        for facts in spread {
            for line in everyLine(facts) where line.contains("Script Editor") { naming.insert(line) }
        }
        XCTAssertEqual(naming, [SetupText.practiceCaution])
    }

    /// After banners have arrived the first rule's line used to say "Make a rule from it", which read
    /// as an instruction to use the practice banner when that was the only one read. It asks for a
    /// rule from a notification to be paged for, and says a practice banner is not that.
    func testOnceBannersHaveArrivedNoLineAsksForARuleFromTheBannerThatWasRead() {
        let read = "Make a rule from a notification you want to be paged for, and not from a practice banner."
        XCTAssertEqual(SetupText.ruleFromARealOne, read)
        for count in [1, 2, 7] {
            let line = SetupText.appsReadLine(count: count)
            XCTAssertTrue(line.hasPrefix("SignalLadder has read banners from \(count) \(count == 1 ? "app" : "apps"). "), line)
            XCTAssertTrue(line.hasSuffix(read), line)
            XCTAssertFalse(line.contains("Make a rule from it"), line)
            XCTAssertFalse(line.contains("Make a rule from one of them"), line)
        }
        XCTAssertTrue(SetupText.bannersWithoutNames.hasSuffix(read), SetupText.bannersWithoutNames)
        XCTAssertFalse(SetupText.bannersWithoutNames.contains("Make a rule from one of them"), SetupText.bannersWithoutNames)
        // Said for what the step shows once something arrived, whatever the apps were called.
        for captured in [["Alpha App"], ["Alpha App", "Beta App"], [" "]] {
            let shown = words(.firstRule, facts(ruleStatus: .noRulesFile, reach: noRuleReach, captured: true, capturedApps: captured))
            XCTAssertEqual(shown.detail.count, 1)
            XCTAssertTrue(shown.detail.at(0).hasSuffix(read), shown.detail.at(0))
            XCTAssertFalse(shown.lines.contains(SetupText.practiceCaution), "the practice line is for while nothing has arrived")
        }
    }

    /// The words read no clock of their own: the only moment the closure is ever given is
    /// the one the facts hold (`lastVerifiedAt`), and it is not asked for any where the facts
    /// hold none. The closure records what it is given and answers differently at each call,
    /// so a line that reached for the real time, or kept a moment between calls, would show.
    func testTheWordsReadNoClockAndAskForNoMomentTheFactsDoNotHold() {
        var asked: [Date] = []
        var calls = 0
        let recording: (Date) -> String = { moment in
            asked.append(moment)
            calls += 1
            return "moment \(calls)"
        }
        var total = 0
        for facts in spread {
            asked = []
            for step in SetupStep.allCases { _ = SetupText.words(for: step, facts: facts, time: recording) }
            _ = SetupText.summary(facts, time: recording)
            for moment in asked {
                XCTAssertEqual(moment, facts.lastVerifiedAt, "\(facts.health): only the moment the facts hold")
            }
            if facts.lastVerifiedAt == nil { XCTAssertEqual(asked, [], "\(facts.health): none held, none asked for") }
            total += asked.count
        }
        XCTAssertGreaterThan(total, 0, "the spread does reach the lines that show a moment")
    }

    /// What a step holds, for scanning, is everything it shows and in the order it shows it: the
    /// title, what it says before it asks, what it rests on, its status, its detail, the text to
    /// select, the label of its box and its buttons, with each part that is nil left out.
    func testAStepsLinesAreEverythingItShowsInTheOrderItShowsIt() {
        let introduction = words(.howItWorks, facts(progress: progress(introduction: true)))
        XCTAssertEqual(introduction.lines,
                       joined(["How it works"], SetupText.why(for: .howItWorks),
                              ["Your word, which SignalLadder cannot check", "You have read this.", "Continue"]))
        let quiet = words(.firstRule, facts(ruleStatus: .noRulesFile, reach: noRuleReach))
        XCTAssertEqual(quiet.lines,
                       joined(["First rule"], SetupText.why(for: .firstRule),
                              ["No rule that is switched on and makes a sound or speaks is in effect.",
                               SetupText.practiceLead, SetupText.practiceCaution, SetupText.practiceCommand,
                               "Check again"]))
        let off = words(.keepItRunning, facts(loginItem: .off(wanted: false)))
        XCTAssertEqual(off.lines,
                       joined(["Keep it running"], SetupText.why(for: .keepItRunning),
                              [SettingsText.offSentence, SetupText.boxExplanation, OnCallText.loginItemMayNotStart,
                               "Launch at login", "Continue", "Skip"]))
        let verified = words(.proveItCanRead, facts(health: .verified, lastVerifiedAt: at(14, 2)))
        XCTAssertEqual(verified.lines,
                       joined(["Prove it can read"], SetupText.why(for: .proveItCanRead),
                              ["Read by SignalLadder", "SignalLadder read its own test banner: verified at 14:02.", "Continue"]))
    }

    /// No step's words change with another's facts.
    func testAStepsWordsFollowItsOwnFactsAndNoOthers() {
        let a = facts(trusted: false)
        let b = facts(trusted: true)
        for step in SetupStep.allCases where step != .accessibility {
            XCTAssertEqual(words(step, a), words(step, b), "\(step)")
        }
        XCTAssertNotEqual(words(.accessibility, a), words(.accessibility, b))
    }

    // MARK: - The window's own labels

    private typealias WindowLabel = SetupText.WindowLabel

    /// The texts the list holds under one reference.
    private func windowLabelTexts(_ reference: String) -> [String] {
        SetupText.windowLabels.filter { $0.reference == reference }.map(\.text)
    }

    /// Names that no label of the window may hold of its own, and a marker no sentence holds.
    private let invented = ["Alpha App", "Beta App", "Microsoft Teams", "Slack", "Script Editor", "Terminal", "Outlook", "Mail"]
    private let marker = "CANARY-7f3a"

    func testTheWindowLabelsAreTheseAndNoOthers() {
        XCTAssertEqual(windowLabelTexts("SetupText.railHeading"), ["Setup steps"])
        XCTAssertEqual(windowLabelTexts("SetupText.stepPosition("), (1...8).map { "Step \($0) of 8" })
        XCTAssertEqual(windowLabelTexts("SetupText.railRowLabel("),
                       ["Step 1 of 8: How it works", "Step 2 of 8: Accessibility", "Step 3 of 8: Notifications",
                        "Step 4 of 8: Prove it can read", "Step 5 of 8: First rule", "Step 6 of 8: Mute the source app",
                        "Step 7 of 8: Do Not Disturb and Focus", "Step 8 of 8: Keep it running"])
        XCTAssertEqual(windowLabelTexts("SetupText.stateDescription("),
                       ["Done. Read by SignalLadder", "Done. Your word, which SignalLadder cannot check", "Still to do",
                        "Not known yet: SignalLadder has not read this", "Not available yet", "Blocked, so not done",
                        "Skipped, so not done"])
        XCTAssertEqual(windowLabelTexts("SetupText.stateLabel("), ["Done", "To do", "Not known yet", "Not yet", "Blocked", "Skipped"])
        XCTAssertEqual(windowLabelTexts("SetupText.label(for: .notNow)"), ["Not now"])
        XCTAssertEqual(windowLabelTexts("SetupText.appListHeading("), ["Apps SignalLadder has read banners from", "Apps to mute"])
        XCTAssertEqual(windowLabelTexts("SetupText.ruleAppRowLabel("), ["the app, an app to make a rule from"])
        XCTAssertEqual(windowLabelTexts("SetupText.muteAppRowLabel("), ["the app — not confirmed muted", "the app — confirmed muted"])
        XCTAssertEqual(windowLabelTexts("SetupText.practiceCommandLabel"), ["Practice command, text to select"])
        XCTAssertEqual(windowLabelTexts("SetupText.muteLookupMessage("),
                       ["SignalLadder couldn't find “the app” among your apps. System Settings was asked to open at Notifications and not at an app's page. Find “the app” in the list and turn its sound off.",
                        "More than one app is called “the app”. System Settings was asked to open at Notifications and not at an app's page. Find “the app” in the list and turn its sound off. Found: first.example, second.example."])
        XCTAssertEqual(windowLabelTexts("SetupText.rulesFileNotOpened("),
                       ["SignalLadder could not get its rules file ready, so no text editor was opened."])

        // No label has a reference that is not listed here, and the kinds are the ones each is.
        let kinds: [String: WindowLabel.Kind] = [
            "SetupText.railHeading": .heading, "SetupText.stepPosition(": .caption,
            "SetupText.railRowLabel(": .description, "SetupText.stateDescription(": .description,
            "SetupText.stateLabel(": .caption, "SetupText.label(for: .notNow)": .button,
            "SetupText.appListHeading(": .heading, "SetupText.ruleAppRowLabel(": .description,
            "SetupText.muteAppRowLabel(": .description, "SetupText.practiceCommandLabel": .description,
            "SetupText.muteLookupMessage(": .message, "SetupText.rulesFileNotOpened(": .message,
        ]
        XCTAssertEqual(Set(SetupText.windowLabels.map(\.reference)), Set(kinds.keys))
        for label in SetupText.windowLabels { XCTAssertEqual(label.kind, kinds[label.reference], label.reference) }
        // 1 heading, 8 positions, 8 rows, 7 spoken states, 6 short ones, the button, 2 list headings, 1 row for the
        // first rule, 2 for muting, the practice line and 3 sentences.
        XCTAssertEqual(SetupText.windowLabels.count, 40)
    }

    /// Each label reads differently from every other, so that neither a person nor VoiceOver has
    /// two to tell apart by their place, and from every word a step or the summary holds, over
    /// every state those can be in. The one button the window has of its own is the one no step
    /// holds.
    func testEveryWindowLabelIsDistinctFromEveryOtherAndFromWhatAStepSays() {
        let all = SetupText.windowLabels
        XCTAssertEqual(Set(all.map(\.text)).count, all.count)
        for label in all {
            XCTAssertFalse(label.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, label.reference)
            XCTAssertTrue(label.reference.hasPrefix("SetupText."), label.reference)
        }
        var said = Set<String>()
        for facts in spread { said.formUnion(everyLine(facts)) }
        for label in all { XCTAssertFalse(said.contains(label.text), "\(label.text) is also said by a step or the summary") }
        for step in SetupStep.allCases { XCTAssertFalse(all.map(\.text).contains(SetupText.title(for: step)), "\(step)") }
        // The window's button is the one no step holds: every step's buttons are the steps', and
        // "Not now" is in none of them.
        XCTAssertFalse(said.contains(SetupText.label(for: .notNow)))
        for facts in spread {
            for step in SetupStep.allCases {
                XCTAssertFalse(SetupText.buttons(for: step, facts: facts).contains { $0.action == .notNow }, "\(step)")
            }
        }
    }

    /// The window has one button of its own, and it is the plan's word (O13). Any other button
    /// the list ever holds has to open with the verb it needs, as every step's does.
    func testEachButtonTheWindowHasOfItsOwnCarriesItsVerb() {
        let buttons = SetupText.windowLabels.filter { $0.kind == .button }
        XCTAssertEqual(buttons.map(\.text), ["Not now"], "the only button the window has of its own")
        XCTAssertEqual(buttons.map(\.text), [SetupText.label(for: .notNow)])
        for button in buttons where button.text != "Not now" {
            let verb = button.text.components(separatedBy: " ").first ?? ""
            XCTAssertTrue(["Open", "Make", "Check", "Continue", "Allow", "Skip", "Finish"].contains(verb), button.text)
        }
        // And it is not a label the steps already use for another act.
        XCTAssertEqual(Action.allCases.filter { SetupText.label(for: $0) == "Not now" }, [.notNow])
    }

    func testTheRailNamesEachStepByItsPlaceAndItsTitle() {
        XCTAssertEqual(SetupStep.allCases.map(SetupText.stepPosition(of:)),
                       ["Step 1 of 8", "Step 2 of 8", "Step 3 of 8", "Step 4 of 8", "Step 5 of 8", "Step 6 of 8",
                        "Step 7 of 8", "Step 8 of 8"], "counted from one, as a person counts")
        for step in SetupStep.allCases {
            XCTAssertEqual(SetupText.railRowLabel(for: step), "\(SetupText.stepPosition(of: step)): \(SetupText.title(for: step))")
        }
        XCTAssertEqual(Set(SetupStep.allCases.map(SetupText.railRowLabel(for:))).count, 8)
        XCTAssertEqual(SetupText.railHeading, "Setup steps")
    }

    // MARK: States

    func testEachStateHasAShortLabelAndAWayToBeReadAloud() {
        typealias S = SetupPlan.State
        let cases: [(state: S, label: String, spoken: String)] = [
            (.done(.fact), "Done", "Done. Read by SignalLadder"),
            (.done(.yourWord), "Done", "Done. Your word, which SignalLadder cannot check"),
            (.outstanding, "To do", "Still to do"),
            (.unknown, "Not known yet", "Not known yet: SignalLadder has not read this"),
            (.notApplicable, "Not yet", "Not available yet"),
            (.blocked(.rulesFileReadOnly(.unreadable("not json"))), "Blocked", "Blocked, so not done"),
            (.blocked(.rulesFileReadOnly(.newerVersion(9))), "Blocked", "Blocked, so not done"),
            (.skipped, "Skipped", "Skipped, so not done"),
        ]
        for row in cases {
            XCTAssertEqual(SetupText.stateLabel(for: row.state), row.label, "\(row.state)")
            XCTAssertEqual(SetupText.stateDescription(for: row.state), row.spoken, "\(row.state)")
        }
        XCTAssertEqual(SetupText.everyState.count, 7, "the list of every state holds one of each, and both bases of a step that is done")
        XCTAssertEqual(Set(SetupText.everyState.map { kind($0) }),
                       ["done", "outstanding", "unknown", "notApplicable", "blocked", "skipped"])
    }

    /// Over everything the facts can make of a step: a state says "Done" if and only if it is
    /// done, a done step says what it rests on in the words the step itself uses, and a step that
    /// is skipped or blocked is said not to be done.
    func testAStateIsSaidDoneOnlyWhenItIsDoneAndRestsOnWhatTheStepSays() {
        var seen = Set<String>()
        for facts in spread {
            for reading in SetupPlan.evaluate(facts) {
                let state = reading.state
                let label = SetupText.stateLabel(for: state)
                let spoken = SetupText.stateDescription(for: state)
                seen.insert(kind(state))
                XCTAssertEqual(label == "Done", state.isDone, "\(reading.step): \(label)")
                XCTAssertEqual(spoken.hasPrefix("Done"), state.isDone, "\(reading.step): \(spoken)")
                if let basis = SetupText.basis(of: state) {
                    XCTAssertTrue(spoken.hasSuffix(basis), "\(reading.step): \(spoken) does not end in \(basis)")
                    XCTAssertEqual(basis, words(reading.step, facts).basis, "the step shows the same basis")
                } else {
                    XCTAssertFalse(spoken.contains("Read by SignalLadder") || spoken.contains("Your word"), spoken)
                }
                if case .skipped = state { XCTAssertTrue(spoken.hasSuffix("not done"), spoken) }
                if case .blocked = state { XCTAssertTrue(spoken.hasSuffix("not done"), spoken) }
            }
        }
        XCTAssertEqual(seen, ["done", "outstanding", "unknown", "notApplicable", "blocked", "skipped"])
    }

    /// Only the mute step is not applicable, and for two reasons, one of which leaves the user
    /// the sound to turn off. So neither the label nor the spoken description may say there is
    /// nothing to do, or nothing to confirm, for the step that has no app to name.
    func testANotApplicableStepIsNeverSaidToNeedNothing() {
        for text in [SetupText.stateLabel(for: .notApplicable), SetupText.stateDescription(for: .notApplicable)] {
            for phrase in ["nothing", "no need", "not needed", "not required", "optional", "all set"] {
                XCTAssertFalse(text.lowercased().contains(phrase), "\(text): \(phrase)")
            }
        }
        // The state is only ever the mute step's, with a rule or without one.
        for facts in spread {
            for reading in SetupPlan.evaluate(facts) where reading.state == .notApplicable {
                XCTAssertEqual(reading.step, .muteSourceApp)
            }
        }
        XCTAssertEqual(SetupPlan.state(of: .muteSourceApp, in: facts()), .notApplicable, "a rule is made, and no app to name")
        XCTAssertEqual(SetupPlan.state(of: .muteSourceApp, in: facts(ruleStatus: .noRulesFile, reach: noRuleReach)),
                       .notApplicable, "no rule yet")
    }

    // MARK: The lists of apps

    func testTheTwoStepsThatListAppsHaveAHeadingForTheListAndNoOtherStepDoes() {
        XCTAssertEqual(SetupText.appListHeading(for: .firstRule), "Apps SignalLadder has read banners from")
        XCTAssertEqual(SetupText.appListHeading(for: .muteSourceApp), "Apps to mute")
        let with = SetupStep.allCases.filter { SetupText.appListHeading(for: $0) != nil }
        XCTAssertEqual(with, [.firstRule, .muteSourceApp])
        // They are the steps whose words ever hold a list of apps, and every such step has one.
        var listing = Set<SetupStep>()
        for facts in spread {
            for step in SetupStep.allCases where !words(step, facts).apps.isEmpty { listing.insert(step) }
        }
        XCTAssertEqual(listing, Set(with))
        // A heading says what the list is, and names none of its apps.
        for step in with {
            let heading = SetupText.appListHeading(for: step) ?? ""
            for name in invented { XCTAssertFalse(heading.contains(name), heading) }
        }
    }

    func testTheLabelsOfAnAppsRowAreFunctionsOfItsNameAndSayNothingMoreThanWhatPickingOrTickingItMeans() {
        for app in ["Alpha App", "Beta App", "\(marker) one"] {
            XCTAssertEqual(SetupText.ruleAppRowLabel(for: app), "\(app), an app to make a rule from")
            XCTAssertEqual(SetupText.muteAppRowLabel(for: app, confirmed: false), "\(app) — not confirmed muted")
            XCTAssertEqual(SetupText.muteAppRowLabel(for: app, confirmed: true), "\(app) — confirmed muted")
            // The menu's own words for an app, reused and not written again.
            XCTAssertEqual(SetupText.muteAppRowLabel(for: app, confirmed: true), MuteWalkthroughText.appItem(app, confirmed: true))
            XCTAssertEqual(SetupText.muteAppRowLabel(for: app, confirmed: false), MuteWalkthroughText.appItem(app, confirmed: false))
        }
        // Only the name varies: swapping it for another gives the other's label, so nothing
        // else in the label depends on what was read.
        let a = "\(marker) one"
        let b = "\(marker) two"
        XCTAssertEqual(SetupText.ruleAppRowLabel(for: a).replacingOccurrences(of: a, with: b), SetupText.ruleAppRowLabel(for: b))
        for confirmed in [false, true] {
            XCTAssertEqual(SetupText.muteAppRowLabel(for: a, confirmed: confirmed).replacingOccurrences(of: a, with: b),
                           SetupText.muteAppRowLabel(for: b, confirmed: confirmed))
        }
        // An unconfirmed app is said "not confirmed", and a confirmed one "confirmed", which are the
        // user's word and not a reading, as the menu's are.
        XCTAssertTrue(SetupText.muteAppRowLabel(for: a, confirmed: false).hasSuffix("— not confirmed muted"))
        XCTAssertTrue(SetupText.muteAppRowLabel(for: a, confirmed: true).hasSuffix("— confirmed muted"))
        XCTAssertFalse(SetupText.muteAppRowLabel(for: a, confirmed: true).contains("not"))
        XCTAssertEqual(SetupText.practiceCommandLabel, "Practice command, text to select")
        XCTAssertFalse(SetupText.practiceCommandLabel.lowercased().contains("copy"), "the app never copies it")
        XCTAssertFalse(SetupText.practiceCommandLabel.lowercased().contains("run"), "the app never runs it")
    }

    // MARK: Every label is shown

    /// The references of `windowLabels` that a source does not write in its code, so that a label
    /// nobody shows fails (M5 plan, Task 8, Tests). Comments are dropped, as the wiring tests drop
    /// them, because a comment may name a label and shows none. A source that does not exist yet
    /// holds nothing, as `ViewLiteralsTests` names `SetupView.swift` before it is written and skips
    /// a name with no file.
    private func unreferencedWindowLabels(in source: String?) -> [String] {
        guard let source else { return [] }
        let code = PowerHoldWiringTests.code(of: source)
        return Set(SetupText.windowLabels.map(\.reference)).filter { !code.contains($0) }.sorted()
    }

    /// The scan the window's view is held to. It passes while the view is not written, and the
    /// day it is written it fails for each label the view leaves out, or writes differently from
    /// the reference in `windowLabels`, which the view's commit changes if the view needs it so.
    func testEveryWindowLabelIsWrittenInTheViewOnceTheViewExists() {
        XCTAssertEqual(unreferencedWindowLabels(in: AppSources.read("SetupView.swift")), [],
                       "SetupView.swift does not write these labels, so nobody shows them")
    }

    func testTheScanOfTheViewFindsALabelNobodyShowsAndSkipsAViewThatIsNotWrittenYet() {
        XCTAssertEqual(unreferencedWindowLabels(in: nil), [], "no view yet, so nothing to hold")
        let references = Set(SetupText.windowLabels.map(\.reference)).sorted()
        XCTAssertGreaterThan(references.count, 10)
        let everyOne = references.joined(separator: "\n")
        XCTAssertEqual(unreferencedWindowLabels(in: everyOne), [])
        // A reference left out is the one found, and only that one.
        let left = "SetupText.railRowLabel("
        XCTAssertTrue(references.contains(left))
        XCTAssertEqual(unreferencedWindowLabels(in: everyOne.replacingOccurrences(of: left, with: "")), [left])
        // A label named in a comment is not shown.
        XCTAssertEqual(unreferencedWindowLabels(in: references.map { "// \($0)" }.joined(separator: "\n")), references)
        XCTAssertEqual(unreferencedWindowLabels(in: references.map { "/// \($0)" }.joined(separator: "\n")), references)
    }

    // MARK: What the labels may claim

    /// Every text the window can show of its own, with the per-app ones made from a marker.
    private var everyWindowText: [String] {
        var all = SetupText.windowLabels.map(\.text)
        all += SetupText.everyState.map(SetupText.stateDescription(for:))
        all += SetupText.everyState.map(SetupText.stateLabel(for:))
        all.append(SetupText.ruleAppRowLabel(for: "\(marker) one"))
        all.append(SetupText.muteAppRowLabel(for: "\(marker) one", confirmed: false))
        all.append(SetupText.muteAppRowLabel(for: "\(marker) one", confirmed: true))
        for resolution in [BundleResolution.notFound, .ambiguous(["a.b", "c.d"])] {
            if let message = SetupText.muteLookupMessage(for: "\(marker) one", resolution: resolution) { all.append(message) }
        }
        all.append(SetupText.rulesFileNotOpened(StubError(description: "")))
        all.append(SetupText.rulesFileNotOpened(StubError(description: "the file is a link to a file that cannot be found")))
        return all
    }

    func testNoWindowLabelClaimsAFocusIsOnOrSaysAnythingIsVerified() {
        for text in everyWindowText {
            XCTAssertFalse(FocusClaim.isMade(by: text), text)
            // "Verified" is a health's word, said by the one step and the one line of the summary
            // that are about it; nothing the window adds says it, whatever health reads.
            XCTAssertFalse(text.lowercased().contains("verif"), text)
        }
        XCTAssertGreaterThan(everyWindowText.count, SetupText.windowLabels.count)
    }

    /// An app's name is in a label only where the label is made from a name, and then it is the
    /// name it was given, once or twice for the two sentences that say where to look. No label of
    /// the static list names an app.
    func testNoWindowLabelNamesAnAppOfItsOwnAndAnAppIsNamedOnlyWhereTheLabelIsMadeFromItsName() {
        for label in SetupText.windowLabels {
            for name in invented { XCTAssertFalse(label.text.contains(name), "\(name) in: \(label.text)") }
            XCTAssertFalse(label.text.contains(marker), label.text)
        }
        let sample = SetupText.sampleApp
        for label in SetupText.windowLabels where label.text.contains(sample) {
            XCTAssertTrue(["SetupText.ruleAppRowLabel(", "SetupText.muteAppRowLabel(", "SetupText.muteLookupMessage("]
                .contains(label.reference), label.reference)
        }
        // The functions that take no name cannot hold one.
        var nameless: [String] = []
        for step in SetupStep.allCases {
            nameless.append(SetupText.stepPosition(of: step))
            nameless.append(SetupText.railRowLabel(for: step))
            nameless.append(SetupText.appListHeading(for: step) ?? "")
        }
        for state in SetupText.everyState {
            nameless.append(SetupText.stateDescription(for: state))
            nameless.append(SetupText.stateLabel(for: state))
        }
        for text in nameless {
            XCTAssertFalse(text.contains(marker), text)
            for name in invented { XCTAssertFalse(text.contains(name), text) }
        }
        // And the ones made from a name hold the marker and nothing else that is data.
        for text in everyWindowText where text.contains(marker) {
            let rest = text.replacingOccurrences(of: "\(marker) one", with: "")
            XCTAssertFalse(rest.contains(marker), text)
        }
    }

    // MARK: Where a modal alert used to stand

    func testTheLookupMessageIsTextBesideTheButtonThatNamesTheAppAndSaysWhatWasFoundAndNoMore() {
        XCTAssertNil(SetupText.muteLookupMessage(for: "Alpha App", resolution: .unique("com.example.alpha")),
                     "a unique match opens the app's own page, and there is nothing to say")
        XCTAssertEqual(SetupText.muteLookupMessage(for: "Alpha App", resolution: .notFound),
                       "SignalLadder couldn't find “Alpha App” among your apps. System Settings was asked to open at Notifications and not at an app's page. Find “Alpha App” in the list and turn its sound off.")
        XCTAssertEqual(SetupText.muteLookupMessage(for: "Alpha App", resolution: .ambiguous(["a.b", "c.d"])),
                       "More than one app is called “Alpha App”. System Settings was asked to open at Notifications and not at an app's page. Find “Alpha App” in the list and turn its sound off. Found: a.b, c.d.")
    }

    /// It begins with the alert's own title and says the alert's own sentence about where to look,
    /// which the menu still shows, so that the two cannot come to differ. It is in the past, since
    /// the guide has no alert before the pane opens (Ruling 22): the alert's "will open" is not
    /// said, and neither is a claim that the pane did open.
    func testTheLookupMessageReusesTheAlertsTitleAndItsSentenceAboutWhereToLook() {
        for resolution in [BundleResolution.notFound, .ambiguous(["a.b", "c.d"])] {
            let alert = MuteWalkthroughText.lookupFallback("Alpha App", resolution)
            let message = SetupText.muteLookupMessage(for: "Alpha App", resolution: resolution)
            XCTAssertNotNil(alert)
            XCTAssertTrue(message?.hasPrefix(alert?.title ?? "?") == true, "\(String(describing: message))")
            XCTAssertTrue(message?.contains(MuteWalkthroughText.findInList("Alpha App")) == true)
            XCTAssertTrue(alert?.body.contains(MuteWalkthroughText.findInList("Alpha App")) == true)
            XCTAssertFalse(message?.contains("will open") == true, "the guide has not opened the pane before it says")
            XCTAssertTrue(message?.contains("was asked to open") == true)
            XCTAssertFalse(message?.lowercased().contains("opened at") == true, "it does not say the pane did open")
        }
        // Only an ambiguous match lists what matched.
        XCTAssertFalse(SetupText.muteLookupMessage(for: "Alpha App", resolution: .notFound)?.contains("Found:") == true)
        XCTAssertTrue(SetupText.muteLookupMessage(for: "Alpha App", resolution: .ambiguous(["a.b"]))?.contains("Found: a.b.") == true)
    }

    func testTheLookupMessageHoldsTheNameItWasGivenAndTheIdentifiersAndNothingElseThatIsData() {
        let name = "\(marker) one"
        let ids = ["first.id", "second.id"]
        for resolution in [BundleResolution.notFound, .ambiguous(ids)] {
            let message = SetupText.muteLookupMessage(for: name, resolution: resolution) ?? ""
            var rest = message.replacingOccurrences(of: name, with: "")
            if case .ambiguous = resolution { for id in ids { rest = rest.replacingOccurrences(of: id, with: "") } }
            XCTAssertFalse(rest.contains(marker), rest)
            XCTAssertEqual(message.components(separatedBy: name).count - 1, 2, "the name, in the title and where to look")
        }
    }

    private struct StubError: Error, CustomStringConvertible {
        let description: String
    }

    func testTheRulesFileFailureSaysNoEditorWasOpenedAndGivesTheReasonInTheErrorsOwnWords() {
        let lead = "SignalLadder could not get its rules file ready, so no text editor was opened."
        XCTAssertEqual(SetupText.rulesFileNotReady, lead)
        // A Cocoa error: its own localised sentence, which names the file and the folder.
        let cocoa = NSError(domain: NSCocoaErrorDomain, code: 513,
                            userInfo: [NSLocalizedDescriptionKey: "You don’t have permission to save the file “rules.json” in the folder “signalladder”."])
        XCTAssertEqual(SetupText.rulesFileNotOpened(cocoa),
                       lead + " The reason given was: You don’t have permission to save the file “rules.json” in the folder “signalladder”.")
        // A POSIX error, with a full stop added where the sentence has none.
        let posix = NSError(domain: NSPOSIXErrorDomain, code: 13, userInfo: [NSLocalizedDescriptionKey: "Permission denied"])
        XCTAssertEqual(SetupText.rulesFileNotOpened(posix), lead + " The reason given was: Permission denied.")
        // The rules file's own error is a description and not a localised line.
        let broken = StubError(description: "the file exists but could not be opened: it is a link to /Volumes/x/rules.json, which cannot be found")
        XCTAssertEqual(SetupText.rulesFileNotOpened(broken),
                       lead + " The reason given was: the file exists but could not be opened: it is a link to /Volumes/x/rules.json, which cannot be found.")
        // A real Cocoa error says what the system says of it, and none of its debugging form.
        let real = CocoaError(.fileWriteNoPermission)
        let said = SetupText.rulesFileNotOpened(real)
        XCTAssertTrue(said.hasPrefix(lead), said)
        XCTAssertTrue(said.contains(real.localizedDescription), said)
        for text in [SetupText.rulesFileNotOpened(cocoa), SetupText.rulesFileNotOpened(posix), said] {
            XCTAssertFalse(text.contains("Error Domain"), text)
            XCTAssertFalse(text.contains("UserInfo"), text)
        }
    }

    /// The error that reaches the sentence is not always a failed attempt to make a file.
    /// `RulesFile.createIfMissing` refuses a `rules.json` that is a link to a file that cannot
    /// be found before it makes anything, and the rules behind the link are the user's real ones,
    /// so a lead that said a file "could not be created" would claim an attempt that was never
    /// made, beside a reason that says the file exists. The lead says only that the file was not
    /// made ready and that no editor was opened, and the reason says which it was.
    func testTheRulesFileFailureDoesNotSayAFileWasToBeMadeWhenTheErrorIsALinkRefusedFirst() {
        let lead = SetupText.rulesFileNotReady
        XCTAssertFalse(lead.lowercased().contains("creat"), lead)
        XCTAssertFalse(lead.lowercased().contains("example"), "a file that exists is not the example: \(lead)")
        // The wording of `RulesFile.ReadError.unopenable`'s description for a link, which this target
        // cannot import: RuleStorage is its own module.
        let link = StubError(description: "the file exists but could not be opened: it is a link to /Volumes/x/rules.json, which cannot be found")
        let said = SetupText.rulesFileNotOpened(link)
        XCTAssertTrue(said.hasPrefix(lead), said)
        XCTAssertFalse(said.lowercased().contains("creat"), said)
        XCTAssertTrue(said.contains("it is a link to /Volumes/x/rules.json, which cannot be found"), "the reason says which it was")
        // A failure to make a folder or write the file reads the same lead, and the reason is the system's.
        let denied = NSError(domain: NSCocoaErrorDomain, code: 513,
                             userInfo: [NSLocalizedDescriptionKey: "You don’t have permission to save the file “rules.json”."])
        XCTAssertTrue(SetupText.rulesFileNotOpened(denied).hasPrefix(lead))
        XCTAssertFalse(SetupText.rulesFileNotOpened(denied).lowercased().contains("could not create"))
    }

    func testTheRulesFileFailureLeavesOutAReasonThatIsBlankAndTrimsOneThatIsSpaced() {
        let lead = SetupText.rulesFileNotReady
        XCTAssertEqual(SetupText.rulesFileNotOpened(StubError(description: "")), lead)
        XCTAssertEqual(SetupText.rulesFileNotOpened(StubError(description: "  \n ")), lead)
        XCTAssertEqual(SetupText.rulesFileNotOpened(StubError(description: "  spaced out \n")),
                       lead + " The reason given was: spaced out.")
        XCTAssertEqual(SetupText.rulesFileNotOpened(StubError(description: "ends in a stop.")),
                       lead + " The reason given was: ends in a stop.", "no second full stop")
        XCTAssertFalse(lead.lowercased().contains("verified"))
        XCTAssertTrue(lead.contains("no text editor was opened"), "what was read: nothing was opened")
    }

    // MARK: - Settings' Setup group

    func testTheSettingsButtonOpensTheGuideAndCarriesItsVerb() {
        XCTAssertEqual(SetupText.openGuideButton, "Open the Setup Guide…")
        XCTAssertTrue(SetupText.openGuideButton.hasPrefix("Open "))
        XCTAssertTrue(SetupText.openGuideButton.hasSuffix("\u{2026}"), "one ellipsis character, as the menu's items have")
        XCTAssertFalse(Action.allCases.map(SetupText.label(for:)).contains(SetupText.openGuideButton))
        XCTAssertFalse(SetupText.windowLabels.map(\.text).contains(SetupText.openGuideButton))
        XCTAssertTrue(SetupText.openGuideButton.contains(String(WindowTitles.setupGuide.dropFirst("SignalLadder ".count))),
                      "the window it opens is called by the name on the button")
    }

    /// Every combination of what a progress can hold that the plan reads or ignores: the five flags,
    /// a skip of each of the two steps that may be skipped, a skip of one that may not, and a token
    /// only a newer build knows. What each stands for is typed out here, and not taken from the plan.
    private func everyProgress() -> [(stored: SetupProgress, standing: String)] {
        var rows: [(stored: SetupProgress, standing: String)] = []
        for mask in 0..<(1 << 9) {
            let on = { (bit: Int) -> Bool in mask & (1 << bit) != 0 }
            var built = SetupProgress()
            if on(0) { built.recordStarted() }
            if on(1) { built.recordIntroductionSeen() }
            if on(2) { built.recordFocusAttested() }
            if on(5) { built.recordSkipped(.proveItCanRead) }
            if on(6) { built.recordSkipped(.keepItRunning) }
            if on(7) { built.recordSkipped(.accessibility) }
            if on(3) { built.recordDismissed() }
            if on(4) { built.recordFinished() }
            let stored = on(8) ? SetupProgress(stored: built.stored + ["somethingNew"]) : built
            let begun = on(0) || on(1) || on(2) || on(5) || on(6)
            let standing: String
            if on(4) {
                standing = "finished"
            } else if on(3) {
                standing = "closed"
            } else {
                standing = begun ? "inProgress" : "notStarted"
            }
            rows.append((stored: stored, standing: standing))
        }
        return rows
    }

    private let everyConfiguration: [SetupPlan.Configuration] = [.configured, .notConfigured, .unknown]

    private func name(_ configuration: SetupPlan.Configuration) -> String {
        switch configuration {
        case .configured: return "configured"
        case .notConfigured: return "notConfigured"
        case .unknown: return "unknown"
        }
    }

    func testTheSettingsLineForEveryProgressAndEveryConfiguration() {
        let required = "Accessibility, Notifications and a first rule"
        let said: [String: String] = [
            "notStarted/configured": "The Setup Guide has not been started. \(required) are done.",
            "notStarted/notConfigured": "The Setup Guide has not been started. At least one of \(required) is still to do.",
            "notStarted/unknown": "The Setup Guide has not been started.",
            "inProgress": "The Setup Guide was started and has not been finished.",
            "closed/configured": "You closed the Setup Guide before finishing it. \(required) are done.",
            "closed/notConfigured": "You closed the Setup Guide before finishing it. At least one of \(required) is still to do.",
            "closed/unknown": "You closed the Setup Guide before finishing it.",
            "finished": "You finished the Setup Guide.",
        ]
        let rows = everyProgress()
        XCTAssertEqual(rows.count, 512)
        var used = Set<String>()
        for row in rows {
            for configuration in everyConfiguration {
                let key = ["inProgress", "finished"].contains(row.standing) ? row.standing : "\(row.standing)/\(name(configuration))"
                used.insert(key)
                XCTAssertEqual(SetupText.settingsLine(progress: row.stored, configuration: configuration), said[key],
                               "\(row.stored.stored) with \(configuration)")
            }
        }
        XCTAssertEqual(used, Set(said.keys), "the combinations do reach every line")
        XCTAssertEqual(Set(said.values).count, 8, "and the eight lines are not alike")
    }

    func testAFinishedGuideIsSaidFinishedWhateverTheConfigurationReadsAndAGuideInProgressSaysNothingOfIt() {
        for row in everyProgress() where row.standing == "finished" {
            for configuration in everyConfiguration {
                XCTAssertEqual(SetupText.settingsLine(progress: row.stored, configuration: configuration), "You finished the Setup Guide.")
            }
        }
        for row in everyProgress() where row.standing == "inProgress" {
            for configuration in everyConfiguration {
                let line = SetupText.settingsLine(progress: row.stored, configuration: configuration)
                XCTAssertEqual(line, "The Setup Guide was started and has not been finished.")
                XCTAssertFalse(line.contains("Accessibility"), line)
            }
        }
    }

    /// A line that is about the steps the plan counts names them in the nudge's own words and
    /// order, so that Settings and the menu say one thing of them.
    func testTheStepsTheLineNamesAreTheOnesTheNudgeCounts() {
        let nudge = SetupText.nudgeLine(outstanding: [.accessibility, .notifications, .firstRule]) ?? ""
        XCTAssertEqual(nudge, "Setup is not finished — still to do: Accessibility, Notifications and a first rule")
        let list = "Accessibility, Notifications and a first rule"
        XCTAssertTrue(nudge.hasSuffix(list))
        XCTAssertEqual(SetupPlan.requiredSteps, [.accessibility, .notifications, .firstRule])
        for configuration in [SetupPlan.Configuration.configured, .notConfigured] {
            for stored in [SetupProgress(), progress(dismissed: true)] {
                XCTAssertTrue(SetupText.settingsLine(progress: stored, configuration: configuration).contains(list))
            }
        }
        // With no configuration to add, each line is its first sentence alone.
        XCTAssertEqual(SetupText.settingsLine(progress: SetupProgress(), configuration: .unknown), SetupText.guideNotStarted)
        XCTAssertEqual(SetupText.settingsLine(progress: progress(dismissed: true), configuration: .unknown), SetupText.guideClosed)
    }

    /// A Mac that was set up before the guide existed reads as not started with the three steps
    /// done, and the line does not say how it was set up, because the plan does not know. Nor does
    /// it say anything of health, a login item or a Focus, which are not what the plan establishes
    /// of the guide.
    func testTheSettingsLineSaysNothingThePlanDidNotEstablish() {
        let forbidden = ["before the guide", "already", "earlier", "upgrad", "install", "since", "verif", "health", "Launch at login",
                         "Focus", "Do Not Disturb", "checking", "Checking", "may not start", "muted", "mute"]
        for row in everyProgress() {
            for configuration in everyConfiguration {
                let line = SetupText.settingsLine(progress: row.stored, configuration: configuration)
                XCTAssertFalse(FocusClaim.isMade(by: line), line)
                for word in forbidden { XCTAssertFalse(line.contains(word), "\(word) in: \(line)") }
                for name in invented { XCTAssertFalse(line.contains(name), line) }
            }
        }
    }

    func testTheSettingsLineFollowsTheFactsThroughThePlansOwnConfiguration() {
        var seen = Set<String>()
        for given in spread {
            let configuration = SetupPlan.configuration(given)
            seen.insert(name(configuration))
            XCTAssertEqual(SetupText.settingsLine(given),
                           SetupText.settingsLine(progress: given.progress, configuration: configuration))
        }
        XCTAssertEqual(seen, ["configured", "notConfigured", "unknown"], "the spread does reach all three")

        let required = "Accessibility, Notifications and a first rule"
        // A configured upgrader who has never met the guide: not started, with the three steps done.
        XCTAssertEqual(SetupText.settingsLine(facts()), "The Setup Guide has not been started. \(required) are done.")
        // The same, whatever health reads, since the plan leaves health out.
        for health in healths {
            XCTAssertEqual(SetupText.settingsLine(facts(health: health)), SetupText.settingsLine(facts()))
        }
        // Before the first probe has answered the notification fact is not known, and the line says nothing of the steps.
        XCTAssertEqual(SetupText.settingsLine(facts(notifications: nil)), "The Setup Guide has not been started.")
        // A fresh install: not started, and at least one step to do.
        XCTAssertEqual(SetupText.settingsLine(facts(trusted: false, notifications: nil, ruleStatus: .noRulesFile, reach: noRuleReach)),
                       "The Setup Guide has not been started. At least one of \(required) is still to do.")
        // A guide closed with a required step outstanding, and one closed with none.
        XCTAssertEqual(SetupText.settingsLine(facts(ruleStatus: .noRulesFile, reach: noRuleReach, progress: progress(dismissed: true))),
                       "You closed the Setup Guide before finishing it. At least one of \(required) is still to do.")
        XCTAssertEqual(SetupText.settingsLine(facts(progress: progress(dismissed: true))),
                       "You closed the Setup Guide before finishing it. \(required) are done.")
    }

    /// What a notification said, a rule's name and an app's name reach no Settings line: the line
    /// is made from the progress and one three-way value, and the facts that hold names are not
    /// read. Each is given a marker, and none reaches it.
    func testNoSettingsLineHoldsNotificationTextOrANameOfAnApp() {
        let apps = ["\(marker) one", "\(marker) two"]
        let problems = [RuleSetCodec.Problem(index: 0, name: "\(marker) rule", reason: "bad \(marker)")]
        let given = [
            facts(ruleStatus: .unreadable("\(marker) why"), reach: noRuleReach, readOnly: .undecodable(problems),
                  captured: true, capturedApps: apps, appsToMute: apps),
            facts(ruleStatus: .loadedWithProblems(enabled: 1, disabled: 0, rejected: problems), captured: true,
                  capturedApps: apps, appsToMute: apps, checklist: confirmed(apps), progress: progress(dismissed: true)),
            facts(captured: true, capturedApps: apps, appsToMute: apps, progress: progress(finished: true)),
        ]
        for facts in given { XCTAssertFalse(SetupText.settingsLine(facts).contains(marker), SetupText.settingsLine(facts)) }
    }
}
