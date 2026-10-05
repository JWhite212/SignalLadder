import XCTest
@testable import NotificationCore

/// How the app target hands what tier 1 did from the pipeline to the escalation
/// (M5 plan, Task 5, Ruling 14): the first connection of burst handling, which
/// carries one value and decides nothing (Ruling 10).
///
/// The app target has no tests, and a value passed through it is the kind of thing
/// that can be swapped without a warning: pass `nil` for the outcome, or read it back
/// from the row, and the app builds, and a match that joins an escalation would play
/// its own alert for ever, or take silence from an outcome the pipeline never gave.
/// So this reads the app's sources, as `SnoozeWiringTests` does, and holds the two
/// places to what they are meant to say. It starts nothing and sounds nothing.
final class BurstWiringTests: XCTestCase {
    private func code(_ file: String) throws -> String {
        PowerHoldWiringTests.code(of: try XCTUnwrap(AppSources.read(file),
                                                    "\(file) cannot be read at \(AppSources.directory.path)"))
    }

    private func count(_ needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    func testTheAppGivesTheEscalationTheOutcomeThePipelineHandedOverAndReadsNoRowForIt() throws {
        let app = try code("AppDelegate.swift")
        let closure = [
            "}, beginEscalation: { [weak self] rule, notification, entryID, tier1 in",
            "guard let self else { return }",
            "self.playerOwnership.alertSetOff(tier1, byEscalation: true)",
            "self.escalations.begin(rule: rule, notification: notification, entryID: entryID, tier1Outcome: tier1)",
            "}, holdForSnooze: snooze.holds)",
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
}
