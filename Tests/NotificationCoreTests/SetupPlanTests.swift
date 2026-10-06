import XCTest
@testable import NotificationCore

/// What the first run decides (M5 plan, Ruling 16, O13, Task 7): each step's state and what
/// it rests on, which step to show, whether the app is set up, when the guide opens and the
/// launch prompts are kept, the menu's nudge, and the last step's box. Nothing here reads
/// the real preferences, calls the system, shows a window or waits on a clock: each test
/// gives the facts as plain values and reads what the plan says. What it expects is typed
/// out in each test, and never taken from the plan's own functions, so that a rule changed
/// there is seen here.
final class SetupPlanTests: XCTestCase {
    typealias State = SetupPlan.State
    typealias Notifications = SetupFacts.Notifications
    typealias Box = SetupPlan.LoginItemBox

    // MARK: - Building facts

    /// A progress, built from what was recorded. The dismissal is recorded before the
    /// finish, so that a progress asked to be both holds both.
    private func progress(started: Bool = false, introduction: Bool = false, focus: Bool = false,
                          skipped: [SetupStep] = [], dismissed: Bool = false,
                          finished: Bool = false) -> SetupProgress {
        var result = SetupProgress()
        if started { result.recordStarted() }
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

    /// Facts for a configured upgrader with nothing stored, who is on the app's first
    /// second: health reads "Checking…", the login item is off, no app is named yet. Each
    /// test changes what it is about.
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

    /// Facts for a Mac that has nothing: Accessibility not granted, no probe answer, no
    /// rules file, nothing stored.
    private func freshInstall(notifications: Notifications? = nil, health: CaptureHealth = .unknown) -> SetupFacts {
        facts(trusted: false, notifications: notifications, health: health, ruleStatus: .noRulesFile,
              reach: noRuleReach)
    }

    /// A configured upgrader: Accessibility trusted, notifications allowed and shown, an
    /// enabled rule that alerts aloud, nothing stored (the human check "an upgrade shows
    /// neither" turned into facts).
    private func configuredUpgrader(health: CaptureHealth = .unknown,
                                    notifications: Notifications? = Notifications(permission: .allowed,
                                                                                  wouldDisplay: true)) -> SetupFacts {
        facts(notifications: notifications, health: health)
    }

    /// Everything done: every step reads done, and so the summary is next.
    private func everythingDone() -> SetupFacts {
        var checklist = MuteChecklist()
        checklist.setConfirmed("Teams", true)
        return facts(health: .verified, lastVerifiedAt: Date(timeIntervalSince1970: 1_000),
                     appsToMute: ["Teams"], checklist: checklist, loginItem: .on,
                     progress: progress(started: true, introduction: true, focus: true))
    }

    /// `base` with one step made to need attention and the rest left as they were, and
    /// made so that breaking two steps breaks both.
    private func breaking(_ step: SetupStep, in base: SetupFacts) -> SetupFacts {
        var broken = base
        switch step {
        case .howItWorks:
            broken.progress = progress(started: true, focus: base.progress.focusIsAttested)
        case .accessibility:
            broken.accessibilityTrusted = false
        case .notifications:
            broken.notifications = nil
        case .proveItCanRead:
            broken.health = .unknown
        case .firstRule:
            broken.ruleStatus = .noRulesFile
            broken.ruleReach = noRuleReach
        case .muteSourceApp:
            broken.muteChecklist = MuteChecklist()
        case .focus:
            broken.progress = progress(started: true, introduction: base.progress.hasSeenIntroduction)
        case .keepItRunning:
            broken.loginItem = .off(wanted: false)
        }
        return broken
    }

    private func state(_ step: SetupStep, _ facts: SetupFacts) -> State {
        SetupPlan.state(of: step, in: facts)
    }

    private let theEight: [SetupStep] = [.howItWorks, .accessibility, .notifications, .proveItCanRead,
                                         .firstRule, .muteSourceApp, .focus, .keepItRunning]

    // MARK: - The values the facts range over

    /// One row for each way the notification fact can read: not yet, and each permission
    /// with and without a banner that would display.
    private struct NotificationRow {
        let name: String
        let fact: Notifications?
        let state: State
    }

    /// What the notification step reads for a permission, typed out for each. No default
    /// arm, so a permission added later has to be placed here.
    private func expectedNotificationState(_ permission: NotificationPermission, wouldDisplay: Bool) -> State {
        switch permission {
        case .allowed: return wouldDisplay ? .done(.fact) : .outstanding
        case .notAsked: return .outstanding
        case .denied: return .outstanding
        }
    }

    private var notificationRows: [NotificationRow] {
        var rows: [NotificationRow] = [NotificationRow(name: "not probed yet", fact: nil, state: .unknown)]
        for permission in NotificationPermission.allCases {
            for display in [false, true] {
                rows.append(NotificationRow(
                    name: "\(permission), would display: \(display)",
                    fact: Notifications(permission: permission, wouldDisplay: display),
                    state: expectedNotificationState(permission, wouldDisplay: display)))
            }
        }
        return rows
    }

    /// One row for each shape health can have: verified, not read yet, and degraded and
    /// blind with causes and with none.
    private struct HealthRow {
        let name: String
        let health: CaptureHealth
        let isVerified: Bool
        let firstCause: HealthCause?
    }

    /// Whether a health is verified, typed out for each shape. No default arm.
    private func isVerified(_ health: CaptureHealth) -> Bool {
        switch health {
        case .verified: return true
        case .unknown: return false
        case .degraded: return false
        case .blind: return false
        }
    }

    private var healthRows: [HealthRow] {
        [
            HealthRow(name: "verified", health: .verified, isVerified: true, firstCause: nil),
            HealthRow(name: "unknown", health: .unknown, isVerified: false, firstCause: nil),
            HealthRow(name: "degraded, one cause", health: .degraded([.selfTestInconclusive]),
                      isVerified: false, firstCause: .selfTestInconclusive),
            HealthRow(name: "degraded, two causes",
                      health: .degraded([.ownAlertsNotShown, .notificationsSuppressed]),
                      isVerified: false, firstCause: .ownAlertsNotShown),
            HealthRow(name: "degraded, no cause", health: .degraded([]), isVerified: false, firstCause: nil),
            HealthRow(name: "blind, one cause", health: .blind([.accessibilityNotTrusted]),
                      isVerified: false, firstCause: .accessibilityNotTrusted),
            HealthRow(name: "blind, two causes",
                      health: .blind([.observerNotAttached, .lazyAccessibilityTree]),
                      isVerified: false, firstCause: .observerNotAttached),
            HealthRow(name: "blind, no cause", health: .blind([]), isVerified: false, firstCause: nil),
        ]
    }

    /// One row for each way the rules can read, with what the first-rule step makes of it.
    private struct RulesRow {
        let name: String
        let status: RuleStoreStatus
        let reach: RuleReach
        let readOnly: RulesDocument.ReadOnlyReason?
        let state: State
        /// A name for the status's case, so that a case no row has is found.
        let statusCase: String
    }

    /// The name of a status's case, typed out for each. No default arm, so a status added
    /// later has to be placed here and given a row.
    private func statusCase(_ status: RuleStoreStatus) -> String {
        switch status {
        case .noRulesFile: return "noRulesFile"
        case .loaded: return "loaded"
        case .loadedWithProblems: return "loadedWithProblems"
        case .unreadable: return "unreadable"
        case .unsupportedVersion: return "unsupportedVersion"
        }
    }

    private let everyStatusCase: Set<String> = ["noRulesFile", "loaded", "loadedWithProblems", "unreadable",
                                                "unsupportedVersion"]

    private var rulesRows: [RulesRow] {
        let silent = RuleReach(enabled: 1, alertingAloud: 0, withShortcut: 0)
        let shortcutOnly = RuleReach(enabled: 1, alertingAloud: 0, withShortcut: 1)
        let unreadable = RulesDocument.ReadOnlyReason.unreadable("not JSON")
        let newer = RulesDocument.ReadOnlyReason.newerVersion(9)
        let undecodable = RulesDocument.ReadOnlyReason.undecodable([problem()])
        let refused = RuleStoreStatus.loadedWithProblems(enabled: 1, disabled: 0, rejected: [problem()])
        let rows: [RulesRow] = [
            RulesRow(name: "no file", status: .noRulesFile, reach: noRuleReach, readOnly: nil,
                     state: .outstanding, statusCase: "noRulesFile"),
            RulesRow(name: "an enabled rule that alerts aloud", status: .loaded(enabled: 1, disabled: 0),
                     reach: oneRuleAlertsAloud, readOnly: nil, state: .done(.fact), statusCase: "loaded"),
            RulesRow(name: "an enabled rule that is silent", status: .loaded(enabled: 1, disabled: 0),
                     reach: silent, readOnly: nil, state: .outstanding, statusCase: "loaded"),
            RulesRow(name: "an enabled rule that only runs a Shortcut", status: .loaded(enabled: 1, disabled: 0),
                     reach: shortcutOnly, readOnly: nil, state: .outstanding, statusCase: "loaded"),
            RulesRow(name: "a rule that is switched off", status: .loaded(enabled: 0, disabled: 1),
                     reach: noRuleReach, readOnly: nil, state: .outstanding, statusCase: "loaded"),
            RulesRow(name: "another rule refused, one in effect that alerts aloud", status: refused,
                     reach: oneRuleAlertsAloud, readOnly: nil, state: .done(.fact),
                     statusCase: "loadedWithProblems"),
            RulesRow(name: "the one rule refused", status: refused, reach: noRuleReach, readOnly: nil,
                     state: .outstanding, statusCase: "loadedWithProblems"),
            RulesRow(name: "a rule that does not decode, so the file is read-only", status: refused,
                     reach: noRuleReach, readOnly: undecodable,
                     state: .blocked(.rulesFileReadOnly(undecodable)), statusCase: "loadedWithProblems"),
            RulesRow(name: "a file that could not be read", status: .unreadable("not JSON"), reach: noRuleReach,
                     readOnly: unreadable, state: .blocked(.rulesFileReadOnly(unreadable)),
                     statusCase: "unreadable"),
            RulesRow(name: "a file that could not be read, with only the status handed over",
                     status: .unreadable("not JSON"), reach: noRuleReach, readOnly: nil,
                     state: .blocked(.rulesFileReadOnly(unreadable)), statusCase: "unreadable"),
            RulesRow(name: "a file from a newer build", status: .unsupportedVersion(9), reach: noRuleReach,
                     readOnly: newer, state: .blocked(.rulesFileReadOnly(newer)), statusCase: "unsupportedVersion"),
            RulesRow(name: "a file from a newer build, with only the status handed over",
                     status: .unsupportedVersion(9), reach: noRuleReach, readOnly: nil,
                     state: .blocked(.rulesFileReadOnly(newer)), statusCase: "unsupportedVersion"),
            RulesRow(name: "a count beside a file that is not in effect", status: .unreadable("not JSON"),
                     reach: oneRuleAlertsAloud, readOnly: unreadable,
                     state: .blocked(.rulesFileReadOnly(unreadable)), statusCase: "unreadable"),
            RulesRow(name: "a count beside a file from a newer build", status: .unsupportedVersion(9),
                     reach: oneRuleAlertsAloud, readOnly: nil, state: .blocked(.rulesFileReadOnly(newer)),
                     statusCase: "unsupportedVersion"),
            RulesRow(name: "a rule that alerts aloud, in a file that cannot now be written",
                     status: .loaded(enabled: 1, disabled: 0), reach: oneRuleAlertsAloud, readOnly: unreadable,
                     state: .done(.fact), statusCase: "loaded"),
        ]
        return rows
    }

    /// Every state the login item can show, from every status in every place with and
    /// without the wish (`LaunchAtLoginTests` builds them the same way).
    private var everyLoginState: [LaunchAtLogin.State] {
        var found: [LaunchAtLogin.State] = []
        for status in LoginItemStatus.allCases {
            for location in AppLocation.allCases {
                for wanted in [false, true] {
                    let shown = LaunchAtLogin.state(status: status, wanted: wanted, location: location)
                    if !found.contains(shown) { found.append(shown) }
                }
            }
        }
        return found
    }

    // MARK: - The steps

    func testThereAreEightStepsInThePlansOrderAndEvaluateGivesEachOneReading() {
        XCTAssertEqual(SetupStep.allCases, theEight)
        for base in [freshInstall(), configuredUpgrader(), everythingDone()] {
            let readings = SetupPlan.evaluate(base)
            XCTAssertEqual(readings.map(\.step), theEight)
            for reading in readings {
                XCTAssertEqual(reading.state, state(reading.step, base), "\(reading.step)")
            }
        }
    }

    func testTheIntroductionIsDoneOnceSeenAndOnlyThen() {
        XCTAssertEqual(state(.howItWorks, facts()), .outstanding)
        XCTAssertEqual(state(.howItWorks, facts(progress: progress(introduction: true))), .done(.yourWord))
        let others: [(String, SetupProgress)] = [
            ("started", progress(started: true)),
            ("the Focus attested", progress(focus: true)),
            ("dismissed", progress(dismissed: true)),
            ("finished", progress(finished: true)),
            ("every step skipped", progress(skipped: theEight)),
        ]
        for (name, stored) in others {
            XCTAssertEqual(state(.howItWorks, facts(progress: stored)), .outstanding, name)
        }
    }

    func testAccessibilityIsDoneWhenGrantedAndRestsOnAFact() {
        XCTAssertEqual(state(.accessibility, facts(trusted: true)), .done(.fact))
        XCTAssertEqual(state(.accessibility, facts(trusted: false)), .outstanding)
    }

    func testNotificationsIsUnknownUntilProbedAndDoneOnlyForAllowedWithBannersThatWouldDisplay() {
        let rows = notificationRows
        XCTAssertEqual(rows.count, 1 + NotificationPermission.allCases.count * 2)
        for row in rows {
            XCTAssertEqual(state(.notifications, facts(notifications: row.fact)), row.state, row.name)
        }
        XCTAssertEqual(rows.filter { $0.state == .done(.fact) }.map(\.name), ["allowed, would display: true"])
        XCTAssertEqual(rows.filter { $0.state == .unknown }.map(\.name), ["not probed yet"])
    }

    func testNotificationsIsNeverDoneByABannerThatWouldDisplayForAnAppThatIsNotAllowed() {
        for permission in NotificationPermission.allCases where permission != .allowed {
            let contradiction = Notifications(permission: permission, wouldDisplay: true)
            XCTAssertEqual(state(.notifications, facts(notifications: contradiction)), .outstanding, "\(permission)")
            XCTAssertFalse(contradiction.isSetUp, "\(permission)")
        }
    }

    func testTheNotificationStepIsTheOnlyOneEverUnknown() {
        for base in [freshInstall(), configuredUpgrader(), everythingDone()] {
            for step in SetupStep.allCases where step != .notifications {
                XCTAssertNotEqual(state(step, base), .unknown, "\(step)")
            }
        }
        var probed = freshInstall()
        probed.notifications = Notifications(permission: .notAsked, wouldDisplay: false)
        XCTAssertNotEqual(state(.notifications, probed), .unknown)
    }

    func testProveItCanReadIsDoneOnlyForAVerifiedHealthAndOtherwiseOutstanding() {
        for row in healthRows {
            XCTAssertEqual(state(.proveItCanRead, facts(health: row.health)),
                           row.isVerified ? .done(.fact) : .outstanding, row.name)
            XCTAssertEqual(isVerified(row.health), row.isVerified, row.name)
        }
    }

    func testTheFirstRuleStepForEveryStatusOfTheRulesAndEveryCountBesideIt() {
        for row in rulesRows {
            let given = facts(ruleStatus: row.status, reach: row.reach, readOnly: row.readOnly)
            XCTAssertEqual(state(.firstRule, given), row.state, row.name)
            XCTAssertEqual(statusCase(row.status), row.statusCase, row.name)
        }
        XCTAssertEqual(Set(rulesRows.map(\.statusCase)), everyStatusCase, "every status has a row")
    }

    /// The name of a reason's case, typed out for each. No default arm, so a reason added
    /// later has to be placed here.
    private func readOnlyCase(_ reason: RulesDocument.ReadOnlyReason) -> String {
        switch reason {
        case .unreadable: return "unreadable"
        case .newerVersion: return "newerVersion"
        case .undecodable: return "undecodable"
        }
    }

    func testABlockedFirstRuleCarriesTheReasonTheFileCannotBeWritten() {
        let reasons: [RulesDocument.ReadOnlyReason] = [.unreadable("x"), .newerVersion(7), .undecodable([problem()])]
        XCTAssertEqual(Set(reasons.map(readOnlyCase)), ["unreadable", "newerVersion", "undecodable"],
                       "every reason is tried")
        for reason in reasons {
            let given = facts(ruleStatus: .noRulesFile, reach: noRuleReach, readOnly: reason)
            XCTAssertEqual(state(.firstRule, given), .blocked(.rulesFileReadOnly(reason)), "\(reason)")
        }
        // The reason handed over is the one shown, and not one made from the status beside it.
        let given = facts(ruleStatus: .unreadable("one"), reach: noRuleReach, readOnly: .newerVersion(3))
        XCTAssertEqual(state(.firstRule, given), .blocked(.rulesFileReadOnly(.newerVersion(3))))
    }

    func testAShortcutWarningIsNotAProblemForTheFirstRule() {
        // A rule whose Shortcut the Shortcuts app does not list stays in effect and sounds,
        // so it is in the count and the step is done (`RuleWarnings` says the rest).
        let given = facts(ruleStatus: .loaded(enabled: 1, disabled: 0),
                          reach: RuleReach(enabled: 1, alertingAloud: 1, withShortcut: 1))
        XCTAssertEqual(state(.firstRule, given), .done(.fact))
    }

    func testTheMuteStepIsNotApplicableUntilTheFirstRuleIsDoneAndThereIsAnAppToName() {
        var confirmed = MuteChecklist()
        confirmed.setConfirmed("Teams", true)
        // The first rule is not done: an app that sounded may be listed, and nothing is asked yet.
        let noRule = facts(ruleStatus: .noRulesFile, reach: noRuleReach, appsToMute: ["Teams"])
        XCTAssertEqual(state(.muteSourceApp, noRule), .notApplicable)
        let noRuleConfirmed = facts(ruleStatus: .noRulesFile, reach: noRuleReach, appsToMute: ["Teams"],
                                    checklist: confirmed)
        XCTAssertEqual(state(.muteSourceApp, noRuleConfirmed), .notApplicable)
        // Done, and no app to name: nothing is confirmed and nothing is claimed.
        XCTAssertEqual(state(.muteSourceApp, facts(appsToMute: [])), .notApplicable)
        // Done, with an app.
        XCTAssertEqual(state(.muteSourceApp, facts(appsToMute: ["Teams"])), .outstanding)
    }

    func testTheMuteStepIsDoneWhenEveryAppIsConfirmedAndItIsTheUsersWord() {
        var one = MuteChecklist()
        one.setConfirmed("Teams", true)
        var both = one
        both.setConfirmed("Slack", true)
        XCTAssertEqual(state(.muteSourceApp, facts(appsToMute: ["Teams"], checklist: one)), .done(.yourWord))
        XCTAssertEqual(state(.muteSourceApp, facts(appsToMute: ["Teams", "Slack"], checklist: one)), .outstanding,
                       "one of two")
        XCTAssertEqual(state(.muteSourceApp, facts(appsToMute: ["Teams", "Slack"], checklist: both)),
                       .done(.yourWord))
        XCTAssertEqual(state(.muteSourceApp, facts(appsToMute: ["Teams", "Slack"])), .outstanding, "neither")
        // A confirmation of an app that is not on the list confirms none that is.
        XCTAssertEqual(state(.muteSourceApp, facts(appsToMute: ["Slack"], checklist: one)), .outstanding)
    }

    func testTheFocusStepIsDoneOnlyWhenAttestedAndItIsTheUsersWord() {
        XCTAssertEqual(state(.focus, facts()), .outstanding)
        XCTAssertEqual(state(.focus, facts(progress: progress(focus: true))), .done(.yourWord))
        let others: [(String, SetupProgress)] = [
            ("started", progress(started: true)),
            ("the introduction seen", progress(introduction: true)),
            ("finished", progress(finished: true)),
            ("every step skipped", progress(skipped: theEight)),
        ]
        for (name, stored) in others {
            XCTAssertEqual(state(.focus, facts(progress: stored)), .outstanding, name)
        }
    }

    func testKeepItRunningIsDoneOnlyForALoginItemThatIsOnOrAStepSkippedAndOtherwiseOutstanding() {
        let skipped = progress(skipped: [.keepItRunning])
        for item in everyLoginState {
            let expectedWithout: State = item.isOn ? .done(.fact) : .outstanding
            let expectedWith: State = item.isOn ? .done(.fact) : .skipped
            XCTAssertEqual(state(.keepItRunning, facts(loginItem: item)), expectedWithout, "\(item)")
            XCTAssertEqual(state(.keepItRunning, facts(loginItem: item, progress: skipped)), expectedWith, "\(item)")
        }
        XCTAssertTrue(everyLoginState.contains(.on))
        XCTAssertTrue(everyLoginState.contains(.switchedOffInSystemSettings))
    }

    // MARK: - What a state is

    /// The name of a state's case, typed out for each. No default arm, so a state added
    /// later has to be placed here and in the table below.
    private func stateCase(_ state: State) -> String {
        switch state {
        case .done: return "done"
        case .outstanding: return "outstanding"
        case .unknown: return "unknown"
        case .notApplicable: return "notApplicable"
        case .blocked: return "blocked"
        case .skipped: return "skipped"
        }
    }

    func testWhatEachStateIsWhetherItNeedsAttentionAndWhetherItIsReadToBeOutstanding() {
        let blocked = State.blocked(.rulesFileReadOnly(.unreadable("x")))
        let table: [(state: State, isDone: Bool, needsAttention: Bool, isKnownOutstanding: Bool)] = [
            (.done(.fact), true, false, false),
            (.done(.yourWord), true, false, false),
            (.outstanding, false, true, true),
            (.unknown, false, true, false),
            (.notApplicable, false, false, false),
            (blocked, false, true, true),
            (.skipped, false, false, false),
        ]
        XCTAssertEqual(Set(table.map { stateCase($0.state) }),
                       ["done", "outstanding", "unknown", "notApplicable", "blocked", "skipped"],
                       "every state is in the table")
        for row in table {
            XCTAssertEqual(row.state.isDone, row.isDone, "\(row.state)")
            XCTAssertEqual(row.state.needsAttention, row.needsAttention, "\(row.state)")
            XCTAssertEqual(row.state.isKnownOutstanding, row.isKnownOutstanding, "\(row.state)")
        }
    }

    /// Whether a state has something for the user, typed out here and not read from the plan.
    private func needsAttention(_ state: State) -> Bool {
        switch state {
        case .outstanding, .unknown, .blocked: return true
        case .done, .notApplicable, .skipped: return false
        }
    }

    func testEveryCombinationOfTheNotificationFactTheHealthAndTheRulesGivesEachStepItsStateAndNoStepReadsAnother() {
        let stored = progress(started: true, introduction: true, focus: true)
        for notification in notificationRows {
            for health in healthRows {
                for rules in rulesRows {
                    let given = facts(notifications: notification.fact, health: health.health,
                                      ruleStatus: rules.status, reach: rules.reach, readOnly: rules.readOnly,
                                      appsToMute: ["Teams"], loginItem: .on, progress: stored)
                    var expected: [State] = []
                    expected.append(.done(.yourWord))                                        // 0
                    expected.append(.done(.fact))                                            // 1
                    expected.append(notification.state)                                      // 2
                    expected.append(health.isVerified ? .done(.fact) : .outstanding)         // 3
                    expected.append(rules.state)                                             // 4
                    // 5: "Teams" is not confirmed, and is asked of only once a rule is done.
                    expected.append(rules.state == .done(.fact) ? .outstanding : .notApplicable)
                    expected.append(.done(.yourWord))                                        // 6
                    expected.append(.done(.fact))                                            // 7
                    let label = "\(notification.name); \(health.name); \(rules.name)"
                    XCTAssertEqual(SetupPlan.evaluate(given).map(\.state), expected, label)
                    let first = expected.firstIndex(where: needsAttention)
                    XCTAssertEqual(SetupPlan.current(given), first.map { theEight[$0] }, label)
                }
            }
        }
    }

    // MARK: - Which steps may be skipped

    func testOnlyProveItCanReadAndKeepItRunningMayBeSkipped() {
        let expected: [(SetupStep, Bool)] = [
            (.howItWorks, false), (.accessibility, false), (.notifications, false), (.proveItCanRead, true),
            (.firstRule, false), (.muteSourceApp, false), (.focus, false), (.keepItRunning, true),
        ]
        XCTAssertEqual(expected.map { $0.0 }, SetupStep.allCases, "every step is placed")
        for (step, mayBeSkipped) in expected {
            XCTAssertEqual(step.mayBeSkipped, mayBeSkipped, "\(step)")
        }
    }

    func testTheRequiredStepsAreAccessibilityNotificationsAndTheFirstRule() {
        let expected: [(SetupStep, Bool)] = [
            (.howItWorks, false), (.accessibility, true), (.notifications, true), (.proveItCanRead, false),
            (.firstRule, true), (.muteSourceApp, false), (.focus, false), (.keepItRunning, false),
        ]
        XCTAssertEqual(expected.map { $0.0 }, SetupStep.allCases, "every step is placed")
        for (step, isRequired) in expected {
            XCTAssertEqual(step.isRequired, isRequired, "\(step)")
        }
        XCTAssertEqual(SetupPlan.requiredSteps, [.accessibility, .notifications, .firstRule])
        for step in SetupStep.allCases where step.isRequired {
            XCTAssertFalse(step.mayBeSkipped, "a required step cannot be skipped: \(step)")
        }
    }

    /// A spread of facts that differ in everything the plan reads.
    private var spreadOfFacts: [SetupFacts] {
        var spread: [SetupFacts] = []
        let checked: [Bool] = [true, false]
        for trusted in checked {
            for row in notificationRows {
                for health in [CaptureHealth.verified, CaptureHealth.unknown] {
                    for rules in rulesRows {
                        spread.append(facts(trusted: trusted, notifications: row.fact, health: health,
                                            ruleStatus: rules.status, reach: rules.reach, readOnly: rules.readOnly,
                                            appsToMute: ["Teams"]))
                    }
                }
            }
        }
        return spread
    }

    func testAStoredSkipForAStepThatMayNotBeSkippedChangesNothingAtAll() {
        for step in SetupStep.allCases where !step.mayBeSkipped {
            for base in spreadOfFacts {
                var withSkip = base
                withSkip.progress.recordSkipped(step)
                XCTAssertTrue(withSkip.progress.isSkipped(step), "\(step): the token is stored")
                XCTAssertEqual(SetupPlan.evaluate(withSkip), SetupPlan.evaluate(base), "\(step)")
                XCTAssertEqual(SetupPlan.current(withSkip), SetupPlan.current(base), "\(step)")
                XCTAssertEqual(SetupPlan.configuration(withSkip), SetupPlan.configuration(base), "\(step)")
                XCTAssertEqual(SetupPlan.opensAtLaunch(withSkip), SetupPlan.opensAtLaunch(base), "\(step)")
                XCTAssertEqual(SetupPlan.nudgeLine(withSkip, guideIsOpen: false),
                               SetupPlan.nudgeLine(base, guideIsOpen: false), "\(step)")
            }
        }
    }

    func testAStoredSkipNeverMakesAccessibilityNotificationsOrAFirstRuleDoneOrTheAppConfigured() {
        var stored = progress(started: true, introduction: true)
        for step in SetupPlan.requiredSteps { stored.recordSkipped(step) }
        let given = facts(trusted: false, notifications: Notifications(permission: .denied, wouldDisplay: false),
                          ruleStatus: .noRulesFile, reach: noRuleReach, progress: stored)
        for step in SetupPlan.requiredSteps {
            XCTAssertEqual(state(step, given), .outstanding, "\(step)")
        }
        XCTAssertEqual(SetupPlan.configuration(given), .notConfigured)
        XCTAssertEqual(SetupPlan.current(given), .accessibility)
        XCTAssertEqual(SetupPlan.nudgeLine(given, guideIsOpen: false),
                       "Setup is not finished — still to do: Accessibility, Notifications and a first rule")
    }

    func testAStoredSkipOfTheFirstRuleDoesNotUnblockItEither() {
        let reason = RulesDocument.ReadOnlyReason.unreadable("not JSON")
        let given = facts(ruleStatus: .noRulesFile, reach: noRuleReach, readOnly: reason,
                          progress: progress(skipped: [.firstRule]))
        XCTAssertEqual(state(.firstRule, given), .blocked(.rulesFileReadOnly(reason)))
    }

    func testAStoredSkipOfTheIntroductionTheMuteOrTheFocusIsNotThemDone() {
        var checklist = MuteChecklist()
        checklist.setConfirmed("Slack", true)
        let given = facts(appsToMute: ["Teams"], checklist: checklist,
                          progress: progress(skipped: [.howItWorks, .muteSourceApp, .focus]))
        XCTAssertEqual(state(.howItWorks, given), .outstanding)
        XCTAssertEqual(state(.muteSourceApp, given), .outstanding)
        XCTAssertEqual(state(.focus, given), .outstanding)
    }

    func testASkipOfAStepThatMayBeSkippedIsReadForThatStepAlone() {
        let onlyThree = facts(progress: progress(skipped: [.proveItCanRead]))
        XCTAssertEqual(state(.proveItCanRead, onlyThree), .skipped)
        XCTAssertEqual(state(.keepItRunning, onlyThree), .outstanding)
        let onlySeven = facts(progress: progress(skipped: [.keepItRunning]))
        XCTAssertEqual(state(.keepItRunning, onlySeven), .skipped)
        XCTAssertEqual(state(.proveItCanRead, onlySeven), .outstanding)
    }

    // MARK: - The order and which step to show

    func testCurrentIsTheFirstStepThatNeedsAttentionAndNilWhenTheSummaryIsNext() {
        let done = everythingDone()
        XCTAssertNil(SetupPlan.current(done), "everything done: the summary is next")
        for reading in SetupPlan.evaluate(done) {
            XCTAssertTrue(reading.state.isDone, "\(reading.step) in the facts that are all done")
            XCTAssertFalse(reading.state.needsAttention, "\(reading.step)")
        }
        for step in SetupStep.allCases {
            XCTAssertEqual(SetupPlan.current(breaking(step, in: done)), step, "only \(step) needs attention")
        }
    }

    func testCurrentIsTheEarlierOfAnyTwoStepsThatNeedAttention() {
        let done = everythingDone()
        let order = SetupStep.allCases
        for (offset, earlier) in order.enumerated() {
            for later in order[(offset + 1)...] {
                let both = breaking(later, in: breaking(earlier, in: done))
                XCTAssertEqual(SetupPlan.current(both), earlier, "\(earlier) and \(later)")
                let reversed = breaking(earlier, in: breaking(later, in: done))
                XCTAssertEqual(SetupPlan.current(reversed), earlier, "\(later) and \(earlier)")
            }
        }
    }

    func testCurrentWaitsOnTheNotificationStepWhileItIsUnknownAndOnABlockedFirstRule() {
        var waiting = everythingDone()
        waiting.notifications = nil
        XCTAssertEqual(SetupPlan.current(waiting), .notifications)
        var blocked = everythingDone()
        blocked.ruleStatus = .unreadable("not JSON")
        blocked.ruleReach = noRuleReach
        blocked.rulesFileReadOnly = .unreadable("not JSON")
        XCTAssertEqual(SetupPlan.current(blocked), .firstRule)
    }

    func testCurrentPassesOverAStepThatIsNotApplicable() {
        var noApps = everythingDone()
        noApps.appsToMute = []
        noApps.muteChecklist = MuteChecklist()
        XCTAssertEqual(state(.muteSourceApp, noApps), .notApplicable)
        XCTAssertNil(SetupPlan.current(noApps), "nothing to mute, nothing outstanding")
        // Focus not attested, with step 5 not applicable before it: the guide moves on to 6.
        var thenFocus = noApps
        thenFocus.progress = progress(started: true, introduction: true)
        XCTAssertEqual(SetupPlan.current(thenFocus), .focus)
    }

    // MARK: - The soft gate

    func testWhileHealthIsNotVerifiedTheStepIsOutstandingIsShownAndHasItsCause() {
        let upToThree = facts(health: .unknown, progress: progress(started: true, introduction: true))
        for row in healthRows where !row.isVerified {
            var given = upToThree
            given.health = row.health
            XCTAssertEqual(state(.proveItCanRead, given), .outstanding, row.name)
            XCTAssertEqual(SetupPlan.current(given), .proveItCanRead, row.name)
            XCTAssertEqual(SetupPlan.unverifiedCause(for: row.health), row.firstCause, row.name)
        }
        XCTAssertNil(SetupPlan.unverifiedCause(for: .verified))
        XCTAssertNil(SetupPlan.unverifiedCause(for: .unknown), "nothing has been read, so there is no cause")
    }

    func testNoCauseToNameIsNotNothingWrongForAProblemThatCarriesNone() {
        // nil is the answer for a health with no cause to name, and for a degraded or blind
        // one that carries none: the first is not a problem, the second is, and the health
        // tells them apart. Nothing reads nil as "still checking" for a problem.
        let upToThree = facts(health: .unknown, progress: progress(started: true, introduction: true))
        let noCauseButAProblem: [CaptureHealth] = [.degraded([]), .blind([])]
        for health in noCauseButAProblem {
            XCTAssertNil(SetupPlan.unverifiedCause(for: health), "\(health)")
            XCTAssertTrue(health.isAlarming, "\(health): a problem, whatever it names")
            var given = upToThree
            given.health = health
            XCTAssertEqual(state(.proveItCanRead, given), .outstanding, "\(health): not done, not still checking")
            XCTAssertEqual(SetupPlan.current(given), .proveItCanRead, "\(health)")
        }
        for health in [CaptureHealth.verified, .unknown] {
            XCTAssertNil(SetupPlan.unverifiedCause(for: health), "\(health)")
            XCTAssertFalse(health.isAlarming, "\(health): not a problem")
        }
    }

    func testContinuingWithoutVerifyingMovesOnAndDoesNotCallItVerified() {
        let verifiedAt = Date(timeIntervalSince1970: 50_000)
        let started = progress(started: true, introduction: true)
        for row in healthRows where !row.isVerified {
            var waiting = facts(health: row.health, lastVerifiedAt: verifiedAt, ruleStatus: .noRulesFile,
                                reach: noRuleReach, progress: started)
            XCTAssertEqual(SetupPlan.current(waiting), .proveItCanRead, row.name)

            waiting.progress.recordSkipped(.proveItCanRead)
            XCTAssertEqual(state(.proveItCanRead, waiting), .skipped, row.name)
            XCTAssertFalse(state(.proveItCanRead, waiting).isDone, "\(row.name): skipped is not done")
            XCTAssertNotEqual(state(.proveItCanRead, waiting), .done(.fact), row.name)
            XCTAssertEqual(SetupPlan.current(waiting), .firstRule, "\(row.name): the guide moves on")
            XCTAssertNil(SetupPlan.verifiedAt(waiting), "\(row.name): nothing is said to be verified")
        }
    }

    func testAVerifiedHealthIsDoneWhateverWasSkippedAndIsTheOnlyOneThatHasATime() {
        let verifiedAt = Date(timeIntervalSince1970: 50_000)
        let skipped = progress(skipped: [.proveItCanRead])
        for row in healthRows {
            let plain = facts(health: row.health, lastVerifiedAt: verifiedAt)
            let withSkip = facts(health: row.health, lastVerifiedAt: verifiedAt, progress: skipped)
            XCTAssertEqual(SetupPlan.verifiedAt(plain), row.isVerified ? verifiedAt : nil, row.name)
            XCTAssertEqual(SetupPlan.verifiedAt(withSkip), row.isVerified ? verifiedAt : nil, row.name)
            if row.isVerified {
                XCTAssertEqual(state(.proveItCanRead, withSkip), .done(.fact), "a fact beats a stored skip")
            }
        }
        XCTAssertNil(SetupPlan.verifiedAt(facts(health: .verified, lastVerifiedAt: nil)),
                     "verified, with no time known, says no time")
    }

    func testAnUnverifiedHealthDoesNotStopTheAppBeingConfiguredOrAnyOtherStep() {
        for row in healthRows {
            let given = configuredUpgrader(health: row.health)
            XCTAssertEqual(SetupPlan.configuration(given), .configured, row.name)
            XCTAssertEqual(state(.accessibility, given), .done(.fact), row.name)
            XCTAssertEqual(state(.firstRule, given), .done(.fact), row.name)
        }
    }

    // MARK: - Whether the app is set up

    func testConfiguredIsStepsOneTwoAndFourDoneAndNothingElse() {
        for row in healthRows {
            for item in everyLoginState {
                for stored in [progress(), progress(started: true, introduction: true, focus: true),
                               progress(skipped: theEight)] {
                    let given = facts(health: row.health, loginItem: item, progress: stored)
                    XCTAssertEqual(SetupPlan.configuration(given), .configured, "\(row.name), \(item)")
                }
            }
        }
    }

    func testConfigurationAcrossAccessibilityNotificationsAndTheRules() {
        for trusted in [true, false] {
            for notification in notificationRows {
                for rules in rulesRows {
                    let given = facts(trusted: trusted, notifications: notification.fact, ruleStatus: rules.status,
                                      reach: rules.reach, readOnly: rules.readOnly)
                    let ruleDone = rules.state == .done(.fact)
                    let expected: SetupPlan.Configuration
                    if !trusted || !ruleDone {
                        expected = .notConfigured
                    } else if notification.state == .unknown {
                        expected = .unknown
                    } else if notification.state == .done(.fact) {
                        expected = .configured
                    } else {
                        expected = .notConfigured
                    }
                    XCTAssertEqual(SetupPlan.configuration(given), expected,
                                   "trusted \(trusted), \(notification.name), \(rules.name)")
                }
            }
        }
    }

    func testBeforeTheFirstProbeAConfiguredUpgraderIsUnknownAndNotUnfinished() {
        let before = configuredUpgrader(notifications: nil)
        XCTAssertEqual(SetupPlan.configuration(before), .unknown)
        XCTAssertNotEqual(SetupPlan.configuration(before), .notConfigured)
        XCTAssertEqual(SetupPlan.configuration(configuredUpgrader()), .configured)
    }

    func testAKnownOutstandingStepSettlesTheConfigurationEvenBeforeTheFirstProbe() {
        XCTAssertEqual(SetupPlan.configuration(facts(trusted: false, notifications: nil)), .notConfigured)
        XCTAssertEqual(SetupPlan.configuration(facts(notifications: nil, ruleStatus: .noRulesFile, reach: noRuleReach)),
                       .notConfigured)
    }

    // MARK: - When the guide opens

    /// One progress, with what each of the two launch decisions is for it when Accessibility
    /// is granted and when it is not.
    private struct LaunchRow {
        let name: String
        let stored: SetupProgress
        let opensWhenTrusted: Bool
        let opensWhenNotTrusted: Bool
    }

    private var launchRows: [LaunchRow] {
        var rows: [LaunchRow] = [
            LaunchRow(name: "nothing stored", stored: progress(), opensWhenTrusted: false, opensWhenNotTrusted: true),
            LaunchRow(name: "only tokens a newer build knows", stored: SetupProgress(stored: ["somethingNew"]),
                      opensWhenTrusted: false, opensWhenNotTrusted: true),
            LaunchRow(name: "started", stored: progress(started: true),
                      opensWhenTrusted: true, opensWhenNotTrusted: true),
            LaunchRow(name: "started, with a token a newer build knows",
                      stored: SetupProgress(stored: ["started", "somethingNew"]),
                      opensWhenTrusted: true, opensWhenNotTrusted: true),
            LaunchRow(name: "started and the introduction seen", stored: progress(started: true, introduction: true),
                      opensWhenTrusted: true, opensWhenNotTrusted: true),
            LaunchRow(name: "started, everything skipped and the Focus attested",
                      stored: progress(started: true, introduction: true, focus: true, skipped: theEight),
                      opensWhenTrusted: true, opensWhenNotTrusted: true),
            LaunchRow(name: "dismissed", stored: progress(dismissed: true),
                      opensWhenTrusted: false, opensWhenNotTrusted: false),
            LaunchRow(name: "started and dismissed", stored: progress(started: true, dismissed: true),
                      opensWhenTrusted: false, opensWhenNotTrusted: false),
            LaunchRow(name: "finished", stored: progress(finished: true),
                      opensWhenTrusted: false, opensWhenNotTrusted: false),
            LaunchRow(name: "started and finished", stored: progress(started: true, finished: true),
                      opensWhenTrusted: false, opensWhenNotTrusted: false),
            LaunchRow(name: "dismissed and then finished", stored: progress(started: true, dismissed: true, finished: true),
                      opensWhenTrusted: false, opensWhenNotTrusted: false),
            // The progress has the pair as one token when finished comes first.
            LaunchRow(name: "finished and then dismissed", stored: {
                var finishedFirst = SetupProgress()
                finishedFirst.recordStarted()
                finishedFirst.recordFinished()
                finishedFirst.recordDismissed()
                return finishedFirst
            }(), opensWhenTrusted: false, opensWhenNotTrusted: false),
        ]
        // A progress with a token other than started and without started reads as started,
        // for each token that only the guide's buttons write and the plan reads: the introduction
        // seen, the Focus attested and a step that may be skipped, skipped.
        rows.append(LaunchRow(name: "only the introduction seen", stored: progress(introduction: true),
                              opensWhenTrusted: true, opensWhenNotTrusted: true))
        rows.append(LaunchRow(name: "only the Focus attested", stored: progress(focus: true),
                              opensWhenTrusted: true, opensWhenNotTrusted: true))
        // A skip of a step that may be skipped is the guide's own button. A skip of any other
        // step means nothing to the plan, so it reads as nothing stored.
        for step in SetupStep.allCases {
            rows.append(LaunchRow(name: "only \(step) skipped", stored: progress(skipped: [step]),
                                  opensWhenTrusted: step.mayBeSkipped, opensWhenNotTrusted: true))
        }
        return rows
    }

    func testOpensAtLaunchForEveryProgressAndWhetherAccessibilityIsGranted() {
        for row in launchRows {
            for trusted in [true, false] {
                for notification in notificationRows {
                    // Health can neither open the guide nor keep it shut, so the answer is the
                    // same for every shape it has.
                    for health in healthRows {
                        let given = facts(trusted: trusted, notifications: notification.fact,
                                          health: health.health, progress: row.stored)
                        XCTAssertEqual(SetupPlan.opensAtLaunch(given),
                                       trusted ? row.opensWhenTrusted : row.opensWhenNotTrusted,
                                       "\(row.name), trusted \(trusted), \(notification.name), health \(health.name)")
                    }
                }
            }
        }
    }

    func testPromptsAtLaunchAreKeptForEveryoneTheGuideDoesNotOpenForAndSkippedExactlyWhenItDoes() {
        for row in launchRows {
            for trusted in [true, false] {
                let opens = trusted ? row.opensWhenTrusted : row.opensWhenNotTrusted
                for health in healthRows {
                    let given = facts(trusted: trusted, health: health.health, progress: row.stored)
                    XCTAssertEqual(SetupPlan.promptsAtLaunch(given), !opens,
                                   "\(row.name), trusted \(trusted), health \(health.name)")
                }
            }
        }
    }

    func testAFreshInstallOpensTheGuideProbedOrNot() {
        XCTAssertTrue(SetupPlan.opensAtLaunch(freshInstall(notifications: nil)), "before the first probe")
        for permission in NotificationPermission.allCases {
            for display in [false, true] {
                let probed = freshInstall(notifications: Notifications(permission: permission, wouldDisplay: display))
                XCTAssertTrue(SetupPlan.opensAtLaunch(probed), "\(permission), \(display)")
                XCTAssertFalse(SetupPlan.promptsAtLaunch(probed), "the guide owns the launch prompts")
            }
        }
        XCTAssertFalse(SetupPlan.promptsAtLaunch(freshInstall(notifications: nil)))
    }

    func testAFreshInstallOpensTheGuideWhateverHealthReads() {
        for health in healthRows {
            for notification in notificationRows {
                let given = freshInstall(notifications: notification.fact, health: health.health)
                XCTAssertTrue(SetupPlan.opensAtLaunch(given), "\(health.name), \(notification.name)")
                XCTAssertFalse(SetupPlan.promptsAtLaunch(given),
                               "\(health.name), \(notification.name): the guide owns the launch prompts")
            }
        }
    }

    func testAGuideThatWasStartedAndNeitherFinishedNorDismissedResumes() {
        for trusted in [true, false] {
            for health in healthRows {
                // Even where every required step is done now, and whatever health reads: it
                // was begun, and not ended.
                let given = facts(trusted: trusted, health: health.health, progress: progress(started: true))
                XCTAssertTrue(SetupPlan.opensAtLaunch(given), "trusted \(trusted), health \(health.name)")
                XCTAssertFalse(SetupPlan.promptsAtLaunch(given), "trusted \(trusted), health \(health.name)")
            }
        }
    }

    func testAConfiguredUpgraderGetsNeitherTheGuideNorTheNudgeWhateverHealthReads() {
        for row in healthRows {
            let given = configuredUpgrader(health: row.health)
            XCTAssertFalse(SetupPlan.opensAtLaunch(given), row.name)
            XCTAssertTrue(SetupPlan.promptsAtLaunch(given), "\(row.name): the launch prompts are kept")
            XCTAssertNil(SetupPlan.nudgeLine(given, guideIsOpen: false), row.name)
            XCTAssertEqual(SetupPlan.configuration(given), .configured, row.name)
        }
    }

    func testTheSameUpgraderBeforeTheFirstProbeAlsoGetsNeitherTheGuideNorTheNudge() {
        for row in healthRows {
            let given = configuredUpgrader(health: row.health, notifications: nil)
            XCTAssertNil(given.notifications)
            XCTAssertFalse(SetupPlan.opensAtLaunch(given), row.name)
            XCTAssertTrue(SetupPlan.promptsAtLaunch(given), row.name)
            XCTAssertNil(SetupPlan.nudgeLine(given, guideIsOpen: false),
                         "\(row.name): a nudge that read nil as outstanding would flash at launch")
        }
    }

    func testAnUpgraderWithNoRuleGetsTheNudgeAndNotTheGuide() {
        let noRule = facts(ruleStatus: .noRulesFile, reach: noRuleReach)
        XCTAssertFalse(SetupPlan.opensAtLaunch(noRule))
        XCTAssertTrue(SetupPlan.promptsAtLaunch(noRule))
        XCTAssertEqual(SetupPlan.nudgeLine(noRule, guideIsOpen: false),
                       "Setup is not finished — still to do: a first rule")
        // Before the first probe the line is the same, and says nothing of notifications.
        var beforeProbe = noRule
        beforeProbe.notifications = nil
        XCTAssertFalse(SetupPlan.opensAtLaunch(beforeProbe))
        XCTAssertEqual(SetupPlan.nudgeLine(beforeProbe, guideIsOpen: false),
                       "Setup is not finished — still to do: a first rule")
    }

    func testAnUpgraderWhoseRulesFileIsReadOnlyGetsTheNudgeToo() {
        let blocked = facts(ruleStatus: .unreadable("not JSON"), reach: noRuleReach,
                            readOnly: .unreadable("not JSON"))
        XCTAssertFalse(SetupPlan.opensAtLaunch(blocked))
        XCTAssertEqual(SetupPlan.nudgeLine(blocked, guideIsOpen: false),
                       "Setup is not finished — still to do: a first rule")
    }

    func testAnUpgraderWhoseOnlyOutstandingStepIsAReadNotificationFactGetsTheNudge() {
        for permission in NotificationPermission.allCases where permission != .allowed {
            let given = facts(notifications: Notifications(permission: permission, wouldDisplay: false))
            XCTAssertFalse(SetupPlan.opensAtLaunch(given), "\(permission)")
            XCTAssertEqual(SetupPlan.nudgeLine(given, guideIsOpen: false),
                           "Setup is not finished — still to do: Notifications", "\(permission)")
        }
        let hidden = facts(notifications: Notifications(permission: .allowed, wouldDisplay: false))
        XCTAssertEqual(SetupPlan.nudgeLine(hidden, guideIsOpen: false),
                       "Setup is not finished — still to do: Notifications", "allowed, with banners that would not show")
    }

    func testAccessibilityRevokedAfterTheGuideWasFinishedDoesNotOpenItAgainOrBringTheNudge() {
        let revoked = facts(trusted: false, progress: progress(started: true, introduction: true, focus: true,
                                                                dismissed: false, finished: true))
        XCTAssertFalse(SetupPlan.opensAtLaunch(revoked))
        XCTAssertTrue(SetupPlan.promptsAtLaunch(revoked))
        XCTAssertNil(SetupPlan.nudgeLine(revoked, guideIsOpen: false),
                     "the health line, the alarm and the icon say it")
        // Whatever else is revoked, and with nothing but the finish stored.
        let everythingGone = facts(trusted: false, notifications: Notifications(permission: .denied, wouldDisplay: false),
                                   ruleStatus: .noRulesFile, reach: noRuleReach, progress: progress(finished: true))
        XCTAssertFalse(SetupPlan.opensAtLaunch(everythingGone))
        XCTAssertNil(SetupPlan.nudgeLine(everythingGone, guideIsOpen: false))
    }

    // MARK: - Closing the window is a dismissal

    /// A fresh install: the guide opens, is started, and is closed with a required step outstanding.
    func testAGuideClosedWhileARequiredStepIsOutstandingDoesNotReopenAndLeavesTheNudgeForAFreshInstall() {
        for notification in notificationRows {
            var given = freshInstall(notifications: notification.fact)
            XCTAssertTrue(SetupPlan.opensAtLaunch(given), "\(notification.name): it opens")
            XCTAssertNil(SetupPlan.nudgeLine(given, guideIsOpen: true), "\(notification.name): not while it is open")

            given.progress.recordStarted()
            XCTAssertTrue(SetupPlan.opensAtLaunch(given), "\(notification.name): started, it resumes")

            given.progress.recordDismissed()   // what both "Not now" and closing the window write
            XCTAssertFalse(SetupPlan.opensAtLaunch(given), "\(notification.name): closed, it does not reopen")
            XCTAssertTrue(SetupPlan.promptsAtLaunch(given), "\(notification.name): so the launch prompts are kept")
            let line = SetupPlan.nudgeLine(given, guideIsOpen: false)
            XCTAssertNotNil(line, "\(notification.name): the line is left")
            XCTAssertTrue(line?.contains("Accessibility") == true, "\(notification.name)")
            XCTAssertTrue(line?.contains("a first rule") == true, "\(notification.name)")
        }
    }

    /// An upgrader with no rule never met the guide; opening it from the menu and closing it
    /// is the same dismissal.
    func testAGuideClosedWhileARequiredStepIsOutstandingDoesNotReopenAndLeavesTheNudgeForAnUpgraderWithNoRule() {
        var given = facts(ruleStatus: .noRulesFile, reach: noRuleReach)
        XCTAssertFalse(SetupPlan.opensAtLaunch(given))
        XCTAssertNotNil(SetupPlan.nudgeLine(given, guideIsOpen: false), "the line is there before it is opened")
        XCTAssertNil(SetupPlan.nudgeLine(given, guideIsOpen: true), "and not while it is open")

        given.progress.recordStarted()
        XCTAssertTrue(SetupPlan.opensAtLaunch(given), "started from the menu and the app quit: it resumes")

        given.progress.recordDismissed()
        XCTAssertFalse(SetupPlan.opensAtLaunch(given), "closed: it does not reopen")
        XCTAssertTrue(SetupPlan.promptsAtLaunch(given))
        XCTAssertEqual(SetupPlan.nudgeLine(given, guideIsOpen: false),
                       "Setup is not finished — still to do: a first rule")
    }

    func testClosingTheGuideWithNothingRequiredOutstandingLeavesNoNudge() {
        var given = configuredUpgrader()
        given.progress.recordStarted()
        given.progress.recordDismissed()
        XCTAssertFalse(SetupPlan.opensAtLaunch(given))
        XCTAssertNil(SetupPlan.nudgeLine(given, guideIsOpen: false))
    }

    func testAFinishedGuideIsNotDismissedAndNeverNudgesOrOpensAgain() {
        for trusted in [true, false] {
            var given = facts(trusted: trusted, notifications: Notifications(permission: .denied, wouldDisplay: false),
                              ruleStatus: .noRulesFile, reach: noRuleReach)
            given.progress.recordStarted()
            given.progress.recordFinished()
            given.progress.recordDismissed()   // the window's close path calls it every time
            XCTAssertFalse(given.progress.isDismissed, "a finished guide is not dismissed")
            XCTAssertFalse(SetupPlan.opensAtLaunch(given))
            XCTAssertNil(SetupPlan.nudgeLine(given, guideIsOpen: false))
        }
    }

    // MARK: - The nudge

    /// What the nudge should say, from what is read, typed out here and not taken from the
    /// plan: the words of the steps that are known to be outstanding, in the plan's order.
    private func expectedNudge(trusted: Bool, notification: State, rule: State, finished: Bool,
                               guideIsOpen: Bool) -> String? {
        if finished || guideIsOpen { return nil }
        var words: [String] = []
        if !trusted { words.append("Accessibility") }
        if notification == .outstanding { words.append("Notifications") }
        if rule != .done(.fact) { words.append("a first rule") }
        guard !words.isEmpty else { return nil }
        let list: String
        switch words.count {
        case 1: list = words[0]
        case 2: list = "\(words[0]) and \(words[1])"
        default: list = "\(words[0]), \(words[1]) and \(words[2])"
        }
        return "Setup is not finished — still to do: \(list)"
    }

    func testTheNudgeForEveryCombinationOfWhatIsReadAndEveryProgress() {
        let stores: [(String, SetupProgress, Bool)] = [
            ("nothing stored", progress(), false),
            ("started", progress(started: true), false),
            ("dismissed", progress(started: true, dismissed: true), false),
            ("finished", progress(started: true, finished: true), true),
        ]
        for trusted in [true, false] {
            for notification in notificationRows {
                for rules in rulesRows {
                    for (storeName, stored, finished) in stores {
                        for guideIsOpen in [false, true] {
                            let given = facts(trusted: trusted, notifications: notification.fact,
                                              ruleStatus: rules.status, reach: rules.reach, readOnly: rules.readOnly,
                                              progress: stored)
                            let expected = expectedNudge(trusted: trusted, notification: notification.state,
                                                         rule: rules.state, finished: finished,
                                                         guideIsOpen: guideIsOpen)
                            XCTAssertEqual(SetupPlan.nudgeLine(given, guideIsOpen: guideIsOpen), expected,
                                           "trusted \(trusted), \(notification.name), \(rules.name), \(storeName), open \(guideIsOpen)")
                        }
                    }
                }
            }
        }
    }

    func testTheNudgeSaysEachCombinationOfTheThreeStepsInTheWordsTypedHere() {
        let stem = "Setup is not finished — still to do:"
        let cases: [([SetupStep], String?)] = [
            ([], nil),
            ([.accessibility], "\(stem) Accessibility"),
            ([.notifications], "\(stem) Notifications"),
            ([.firstRule], "\(stem) a first rule"),
            ([.accessibility, .notifications], "\(stem) Accessibility and Notifications"),
            ([.accessibility, .firstRule], "\(stem) Accessibility and a first rule"),
            ([.notifications, .firstRule], "\(stem) Notifications and a first rule"),
            ([.accessibility, .notifications, .firstRule], "\(stem) Accessibility, Notifications and a first rule"),
        ]
        for (steps, line) in cases {
            XCTAssertEqual(SetupText.nudgeLine(outstanding: steps), line, "\(steps)")
        }
        XCTAssertEqual(SetupText.nudgeStem, "Setup is not finished")
    }

    func testTheNudgeLineIsInThePlansOrderOnceEachAndCountsNoOtherStep() {
        XCTAssertEqual(SetupText.nudgeLine(outstanding: [.firstRule, .accessibility]),
                       "Setup is not finished — still to do: Accessibility and a first rule")
        XCTAssertEqual(SetupText.nudgeLine(outstanding: [.accessibility, .accessibility, .accessibility]),
                       "Setup is not finished — still to do: Accessibility")
        let others: [SetupStep] = [.howItWorks, .proveItCanRead, .muteSourceApp, .focus, .keepItRunning]
        XCTAssertNil(SetupText.nudgeLine(outstanding: others), "none of the other five is counted")
        XCTAssertEqual(SetupText.nudgeLine(outstanding: others + [.notifications]),
                       "Setup is not finished — still to do: Notifications")
    }

    func testEveryStepTheNudgeCountsHasAWordAndNoOtherHasOne() {
        for step in SetupStep.allCases {
            XCTAssertEqual(SetupText.nudgeWord(for: step) != nil, step.isRequired, "\(step)")
        }
    }

    /// The words that would say something about health, which the nudge never does: it is
    /// not derived from health, and the health line, the alarm and the icon say it.
    private let healthWords = try! NSRegularExpression(
        pattern: #"health|verif|capturing|capture|self-test|checking|blind|degraded|working|cannot read|not seeing"#,
        options: .caseInsensitive)

    func testTheNudgeNeverMentionsHealthAndIsTheSameForEveryHealth() {
        for trusted in [true, false] {
            for notification in notificationRows {
                for rules in rulesRows {
                    let reference = facts(trusted: trusted, notifications: notification.fact, health: .verified,
                                          ruleStatus: rules.status, reach: rules.reach, readOnly: rules.readOnly)
                    let referenceLine = SetupPlan.nudgeLine(reference, guideIsOpen: false)
                    for row in healthRows {
                        var given = reference
                        given.health = row.health
                        given.lastVerifiedAt = Date(timeIntervalSince1970: 9_000)
                        let line = SetupPlan.nudgeLine(given, guideIsOpen: false)
                        XCTAssertEqual(line, referenceLine,
                                       "health \(row.name) changed the line: \(trusted), \(notification.name), \(rules.name)")
                        if let line {
                            let whole = NSRange(line.startIndex..., in: line)
                            XCTAssertNil(healthWords.firstMatch(in: line, range: whole), line)
                        }
                    }
                }
            }
        }
    }

    func testTheHealthPatternMatchesTheWordsItIsMeantToCatch() {
        let said = ["Working — verified", "Checking…", "NOT capturing notifications", "Cannot verify itself",
                    "Unverified — last verified 3 min ago", "SignalLadder's self-test alert was never seen",
                    "capture is degraded", "The health line"]
        for text in said {
            let whole = NSRange(text.startIndex..., in: text)
            XCTAssertNotNil(healthWords.firstMatch(in: text, range: whole), text)
        }
        for text in ["Setup is not finished — still to do: Accessibility, Notifications and a first rule"] {
            let whole = NSRange(text.startIndex..., in: text)
            XCTAssertNil(healthWords.firstMatch(in: text, range: whole), text)
        }
    }

    func testTheNudgeNamesNoAppAndHoldsNothingANotificationSaid() {
        var given = facts(trusted: false, notifications: Notifications(permission: .denied, wouldDisplay: false),
                          ruleStatus: .noRulesFile, reach: noRuleReach, captured: true,
                          capturedApps: ["Teams", "A fragment of a title"], appsToMute: ["Teams"])
        given.progress.recordStarted()
        guard let line = SetupPlan.nudgeLine(given, guideIsOpen: false) else { return XCTFail("no line") }
        for name in ["Teams", "A fragment", "title"] {
            XCTAssertFalse(line.contains(name), line)
        }
    }

    // MARK: - The last step's box

    /// What the box is for a state, typed out for each. No default arm, so a state added
    /// later has to be placed here.
    private func expectedBox(_ state: LaunchAtLogin.State) -> Box {
        switch state {
        case .off: return .shown
        case .on: return .absent(.alreadyOn)
        case .switchedOffInSystemSettings: return .absent(.switchedOffInSystemSettings)
        case .unavailable(let why): return .absent(.unavailable(why))
        }
    }

    func testTheBoxIsShownAndStartsTickedOnlyForALoginItemThatIsOffAndRegistrable() {
        for item in everyLoginState {
            let box = SetupPlan.loginItemBox(for: item)
            XCTAssertEqual(box, expectedBox(item), "\(item)")
            let isOff: Bool
            if case .off = item { isOff = true } else { isOff = false }
            XCTAssertEqual(box.isShown, isOff, "\(item)")
            XCTAssertEqual(box.startsTicked, isOff, "\(item)")
        }
    }

    func testTheBoxForEachStateTheLoginItemCanBeIn() {
        XCTAssertEqual(SetupPlan.loginItemBox(for: .off(wanted: false)), .shown)
        XCTAssertEqual(SetupPlan.loginItemBox(for: .off(wanted: true)), .shown, "what the user wanted does not hide it")
        XCTAssertEqual(SetupPlan.loginItemBox(for: .on), .absent(.alreadyOn))
        XCTAssertEqual(SetupPlan.loginItemBox(for: .switchedOffInSystemSettings),
                       .absent(.switchedOffInSystemSettings))
        for why in LaunchAtLogin.Unavailable.allCases {
            XCTAssertEqual(SetupPlan.loginItemBox(for: .unavailable(why)), .absent(.unavailable(why)), "\(why)")
        }
        XCTAssertEqual(Set(everyLoginState.map { "\(SetupPlan.loginItemBox(for: $0))" }).count, 5,
                       "shown, on, switched off in System Settings, and the two reasons a copy cannot")
    }

    func testContinueRegistersOnlyWithTheBoxShownAndTicked() {
        for item in everyLoginState {
            let result = SetupPlan.pressing(.continueButton, state: item, boxTicked: true)
            if case .off = item {
                XCTAssertEqual(result.request, .register, "\(item)")
                XCTAssertFalse(result.recordsSkip, "\(item): the step is done when the status reads on")
            } else {
                XCTAssertNil(result.request, "no box is shown for \(item), so a tick the window still holds registers nothing")
            }
        }
    }

    func testAContinueThatRegistersSavesTheUsersChoiceAsSettingsDoesAndNoOtherPressSavesOne() {
        for item in everyLoginState {
            for press in [SetupPlan.KeepItRunningPress.continueButton, .skipButton] {
                for ticked in [true, false] {
                    let result = SetupPlan.pressing(press, state: item, boxTicked: ticked)
                    var isOff = false
                    if case .off = item { isOff = true }
                    let registers = press == .continueButton && isOff && ticked
                    let expected: Bool? = registers ? true : nil
                    XCTAssertEqual(result.wantedAfterPress, expected, "\(press), \(item), ticked \(ticked)")
                    XCTAssertEqual(result.request != nil, result.wantedAfterPress != nil,
                                   "\(press), \(item), ticked \(ticked): a choice is saved when, and only when, a request is made")
                }
            }
        }
        let result = SetupPlan.pressing(.continueButton, state: .off(wanted: false), boxTicked: true)
        XCTAssertEqual(result.wantedAfterPress, LaunchAtLogin.Action.turnOn.wantedAfterPress,
                       "what the finding's button saves in Settings")
        XCTAssertEqual(result.wantedAfterPress, true)
    }

    func testContinueWithTheBoxUntickedRegistersNothingAndMovesOnByRecordingTheSkip() {
        for item in [LaunchAtLogin.State.off(wanted: false), .off(wanted: true)] {
            let result = SetupPlan.pressing(.continueButton, state: item, boxTicked: false)
            XCTAssertNil(result.request, "\(item)")
            XCTAssertTrue(result.recordsSkip, "\(item)")
        }
    }

    func testSkipRegistersNothingWhateverTheBoxSaysAndRecordsTheSkipUnlessTheLoginItemIsOn() {
        for item in everyLoginState {
            for ticked in [true, false] {
                let result = SetupPlan.pressing(.skipButton, state: item, boxTicked: ticked)
                XCTAssertNil(result.request, "\(item), ticked \(ticked)")
                XCTAssertEqual(result.recordsSkip, !item.isOn, "\(item), ticked \(ticked)")
            }
        }
    }

    func testContinueWhereNoBoxIsShownMovesOnWithoutRegisteringAndWithoutHidingAnOnItem() {
        for item in everyLoginState {
            if case .off = item { continue }
            for ticked in [true, false] {
                let result = SetupPlan.pressing(.continueButton, state: item, boxTicked: ticked)
                XCTAssertNil(result.request, "\(item), ticked \(ticked)")
                XCTAssertEqual(result.recordsSkip, !item.isOn, "\(item), ticked \(ticked)")
            }
        }
        let on = SetupPlan.pressing(.continueButton, state: .on, boxTicked: true)
        XCTAssertEqual(on, SetupPlan.KeepItRunningResult(request: nil, wantedAfterPress: nil, recordsSkip: false))
    }

    func testTheRequestContinueMakesIsTheOneTheSettingsSwitchMakesWhenTurnedOn() {
        let result = SetupPlan.pressing(.continueButton, state: .off(wanted: false), boxTicked: true)
        XCTAssertEqual(result.request, LaunchAtLogin.request(switchTurnedOn: true))
        XCTAssertEqual(result.request, .register)
        XCTAssertNotEqual(result.request, .unregister)
    }

    // MARK: - A fresh install, start to finish

    func testAFreshInstallWalkedThroughTheGuide() {
        var given = freshInstall()
        // Opens, and the first launch prompts are the guide's.
        XCTAssertTrue(SetupPlan.opensAtLaunch(given))
        XCTAssertFalse(SetupPlan.promptsAtLaunch(given))
        given.progress.recordStarted()
        XCTAssertEqual(SetupPlan.current(given), .howItWorks)

        given.progress.recordIntroductionSeen()
        XCTAssertEqual(SetupPlan.current(given), .accessibility)

        given.accessibilityTrusted = true
        XCTAssertEqual(SetupPlan.current(given), .notifications, "waiting for the first probe")
        XCTAssertEqual(state(.notifications, given), .unknown)
        XCTAssertEqual(SetupPlan.configuration(given), .notConfigured, "no rule yet")

        given.notifications = Notifications(permission: .notAsked, wouldDisplay: false)
        XCTAssertEqual(SetupPlan.current(given), .notifications)
        XCTAssertEqual(state(.notifications, given), .outstanding)
        given.notifications = allowedAndShown
        XCTAssertEqual(SetupPlan.current(given), .proveItCanRead, "health still reads Checking…")

        given.progress.recordSkipped(.proveItCanRead)
        XCTAssertEqual(SetupPlan.current(given), .firstRule)
        XCTAssertEqual(state(.muteSourceApp, given), .notApplicable)

        given.ruleStatus = .loaded(enabled: 1, disabled: 0)
        given.ruleReach = oneRuleAlertsAloud
        given.appsToMute = ["Teams"]
        XCTAssertEqual(SetupPlan.configuration(given), .configured)
        XCTAssertEqual(SetupPlan.current(given), .muteSourceApp)

        given.muteChecklist.setConfirmed("Teams", true)
        XCTAssertEqual(SetupPlan.current(given), .focus)
        given.progress.recordFocusAttested()
        XCTAssertEqual(SetupPlan.current(given), .keepItRunning)

        // Continue with the box ticked asks for the registration, and the step is done when the status reads on.
        let press = SetupPlan.pressing(.continueButton, state: given.loginItem, boxTicked: true)
        XCTAssertEqual(press.request, .register)
        XCTAssertEqual(SetupPlan.current(given), .keepItRunning, "not done until the status says so")
        given.loginItem = .on
        XCTAssertNil(SetupPlan.current(given), "the summary is next")
        XCTAssertNil(SetupPlan.verifiedAt(given), "the proof was skipped, so nothing is said to be verified")
        XCTAssertEqual(state(.proveItCanRead, given), .skipped)
    }
}
