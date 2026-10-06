import XCTest
@testable import NotificationCore

/// How the app target connects burst handling (M5 plan, Task 5, Rulings 14 and 22):
/// what tier 1 did, handed from the pipeline to the escalation; the coordinator's
/// answer to whether a match joins one already running, handed to the pipeline; the
/// Inspector's line for a row that joined; what the status menu's Acknowledge acts
/// on; and what the quit prompt reads. Each carries a value or a verdict and decides
/// nothing (Ruling 10).
///
/// The app target has no tests, and a value passed through it is the kind of thing
/// that can be swapped without a warning: pass `nil` for the outcome, or read it back
/// from the row, and the app builds, and a match that joins an escalation would play
/// its own alert for ever, or take silence from an outcome the pipeline never gave. Give
/// the pipeline an answer of `nil` for the join, which is what it was given until this
/// was connected, and the app builds and every match of a burst sounds and pages for
/// itself. Let the menu's Acknowledge forget the counts it listed, and a match that
/// joined while the menu was open is ended unseen, with the page it was owed. So this
/// reads the app's sources, as `SnoozeWiringTests` does, and holds the places to what
/// they are meant to say. It starts nothing and sounds nothing.
final class BurstWiringTests: XCTestCase {
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

    func testTheAppGivesTheEscalationTheOutcomeThePipelineHandedOverAndReadsNoRowForIt() throws {
        let app = try code("AppDelegate.swift")
        let closure = [
            "}, beginEscalation: { [weak self] rule, notification, entryID, tier1 in",
            "guard let self else { return }",
            "self.playerOwnership.alertSetOff(tier1, byEscalation: true)",
            "self.escalations.begin(rule: rule, notification: notification, entryID: entryID, tier1Outcome: tier1)",
            "}, holdForSnooze: snooze.holds, joinEscalation: { [weak self] rule, notification in",
        ].joined(separator: "\n")
        XCTAssertEqual(count("\n" + closure + "\n", in: "\n" + app + "\n"), 1,
                       "the one closure, and the outcome goes to the player's ownership and to `begin` as it was given")
        XCTAssertEqual(count(".begin(rule:", in: app), 1, "no other place begins a ladder")
        XCTAssertEqual(count("tier1Outcome: nil", in: app), 0, "none says that nothing was heard")
        XCTAssertFalse(app.contains(".alertOutcome"), "and the app reads no row to find out what tier 1 did")
    }

    func testTheControllerHandsTheClosureToThePipelineAsItIsGivenWithTheOutcomeInItsShape() throws {
        let capture = try code("CaptureController.swift")
        XCTAssertEqual(count("beginEscalation: @escaping (Rule, CapturedNotification, UUID, AlertOutcome) -> Void,",
                             in: capture), 1, "no default, and the outcome is not optional: the pipeline always has one")
        XCTAssertEqual(count("beginEscalation: beginEscalation,", in: capture), 1, "handed over as it is given")
        XCTAssertEqual(count("CapturePipeline(", in: capture), 1)
    }

    // MARK: The join

    func testTheAppGivesThePipelineTheCoordinatorsJoinAndNoPlaceAnswersForIt() throws {
        let app = try code("AppDelegate.swift")
        let closure = [
            "}, holdForSnooze: snooze.holds, joinEscalation: { [weak self] rule, notification in",
            "self?.escalations.join(rule: rule, notification: notification)",
            "})",
        ].joined(separator: "\n")
        XCTAssertEqual(count("\n" + closure + "\n", in: "\n" + app + "\n"), 1,
                       "the one closure, which asks the coordinator and answers nothing itself")
        XCTAssertEqual(count(".join(rule:", in: app), 1, "no other place asks whether a match joins")
        XCTAssertEqual(count("CaptureController(", in: app), 1)

        // The transitional answer of nil, in any spelling, is nowhere: the argument
        // is given where the app builds the controller and where the controller builds
        // the pipeline, and in no other place.
        for file in try AppSources.fileNames() {
            let expected = ["AppDelegate.swift": 1, "CaptureController.swift": 2][file] ?? 0
            XCTAssertEqual(count("joinEscalation:", in: try code(file)), expected, file)
        }
    }

    func testTheControllerHandsTheJoinToThePipelineAsItIsGivenWithNoDefault() throws {
        let capture = try code("CaptureController.swift")
        XCTAssertEqual(count("joinEscalation: @escaping (Rule, CapturedNotification) -> EscalationJoin?) {", in: capture), 1,
                       "no default, and it may answer nil, which is a match that begins its own ladder")
        XCTAssertEqual(count("holdForSnooze: holdForSnooze, joinEscalation: joinEscalation)", in: capture), 1,
                       "handed to the pipeline as it is given, after the gate")
        XCTAssertEqual(count("CapturePipeline(", in: capture), 1)
    }

    // MARK: What is shown

    /// A row that joined an escalation and played its own alert says what the alert did and
    /// then which match it was, in the core's own line for the entry. The view that drew
    /// the outcome's line alone would leave the number recorded on the row and never shown.
    func testTheInspectorDrawsTheEntrysAlertLineAndNotTheOutcomesSoAJoinedRowSaysItsNumber() throws {
        let view = try code("InspectorView.swift")
        XCTAssertEqual(count("if let alert = entry.alertOutcome, let line = InspectorRowText.alert(entry) {", in: view), 1)
        XCTAssertEqual(count("Label(line, systemImage: InspectorRowText.symbol(alert))", in: view), 1)
        XCTAssertEqual(count("InspectorRowText.alert(", in: view), 1, "the one line, and the outcome's own is drawn nowhere")
    }

    // MARK: What the menu's Acknowledge acts on

    func testTheMenusAcknowledgeCarriesWhatItListedAsItListedItAndActsOnThatAlone() throws {
        let app = try code("AppDelegate.swift")
        let action = try body(of: "@objc private func acknowledgeListedFromMenu(_ sender: NSMenuItem) {", in: app)
        XCTAssertEqual(action.trimmingCharacters(in: .whitespacesAndNewlines), [
            "guard let listed = sender.representedObject as? ListedEscalations else { return }",
            "escalations.acknowledge(listed: listed.escalations)",
        ].joined(separator: "\n"), "the click acts on what the item carries and on nothing it reads then")
        XCTAssertEqual(count("acknowledge.representedObject = ListedEscalations(escalations: rows.map(ListedEscalation.init(row:)))",
                             in: app), 1, "built from the rows the menu was drawn from, each with the count it stood for")
        XCTAssertEqual(count("acknowledge(listed:", in: app), 1, "no other place acknowledges what a menu listed")
        XCTAssertEqual(count("acknowledge(ids:", in: app), 0, "and none by ids alone, which would end a match that joined unseen")
        XCTAssertEqual(count("acknowledgeAll()", in: app), 1, "the hotkey's, which acts on what is listed now")
    }

    // MARK: What the quit prompt reads

    /// The prompt is asked again while more stands than it named, and a match that joins an
    /// escalation it listed raises neither the escalations nor the missed ones: only the
    /// matches. The summaries carry them and the statuses do not, so a `Standing` built from the
    /// statuses alone, as it was before a match could join, builds and quits the match away
    /// unseen. The app has no tests, so this holds the one place it is made.
    func testTheQuitPromptReadsTheListedSummariesSoAMatchThatJoinedIsAskedAbout() throws {
        let app = try code("AppDelegate.swift")
        let quit = try body(of: "func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {", in: app)
        XCTAssertEqual(count("QuitPolicy.Standing(listed: self.escalations.listedSummaries.map(\\.1), onCall: self.onCall.state.isOn)",
                             in: quit), 1, "what stands is read afresh, from the summaries with their counts, whenever the policy asks")
        XCTAssertEqual(count("Standing(", in: app), 1, "no other place makes one, and none with a count it chose")
        XCTAssertEqual(count("\\.1.status", in: app), 0, "and none from the statuses alone")
        XCTAssertEqual(count("QuitPolicy.mayQuit(", in: app), 1)
    }
}
