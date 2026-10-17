import XCTest
@testable import NotificationCore

/// The rules' warnings are worked out again while the app runs (1.1 plan, Ruling 15): at
/// each self-test the canary timer runs, on waking and when on call begins. These read
/// the app target's sources, which has no tests of its own, and show the lines are
/// there, not that they run.
final class WarningsRecheckWiringTests: XCTestCase {
    private func code(_ file: String) throws -> String {
        PowerHoldWiringTests.code(of: try XCTUnwrap(AppSources.read(file),
                                                    "\(file) cannot be read at \(AppSources.directory.path)"))
    }

    private func body(of signature: String, in code: String) throws -> String {
        try XCTUnwrap(OnCallWiringTests.body(of: signature, in: code), "no single \(signature)")
    }

    private func count(_ needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    private func offset(of needle: String, in text: String) throws -> Int {
        let range = try XCTUnwrap(text.range(of: needle), "\(needle) is not there")
        return text.distance(from: text.startIndex, to: range.lowerBound)
    }

    func testTheCanaryTimersTickRechecksTheWarningsBeforeTheSelfTest() throws {
        let canary = try body(of: "private func scheduleCanary() {", in: try code("AppDelegate.swift"))
        XCTAssertEqual(count("recheckRuleWarnings()", in: canary), 1)
        XCTAssertEqual(count("refreshHealth(runCanary: true)", in: canary), 1)
        XCTAssertLessThan(try offset(of: "recheckRuleWarnings()", in: canary),
                          try offset(of: "refreshHealth(runCanary: true)", in: canary),
                          "the self-test's run of the watch sees the warnings as they are now")
    }

    func testAWakeAndTheSwitchCarryOutTheCoresStep() throws {
        let app = try code("AppDelegate.swift")
        let wake = try body(of: "private func macDidWake() {", in: app)
        XCTAssertEqual(count("case .recheckRuleWarnings: recheckRuleWarnings()", in: wake), 1)
        let effect = try body(of: OnCallWiringTests.carryOut, in: app)
        XCTAssertEqual(count("case .recheckRuleWarnings: recheckRuleWarnings()", in: effect), 1)
        XCTAssertEqual(count("recheckRuleWarnings()", in: app), 4,
                       "its declaration, the canary's tick, the wake's step and the switch's effect")
    }

    /// A change is what the watch and the menu are told about; no change, nothing.
    func testARecheckThatChangedSomethingAsksTheWatchAndRebuildsTheMenu() throws {
        let recheck = try body(of: "private func recheckRuleWarnings() {", in: try code("AppDelegate.swift"))
        XCTAssertTrue(recheck.contains("guard ruleStore.recheckWarnings() else { return }"))
        XCTAssertLessThan(try offset(of: "guard ruleStore.recheckWarnings()", in: recheck),
                          try offset(of: "evaluateOnCallWatch()", in: recheck))
        XCTAssertLessThan(try offset(of: "evaluateOnCallWatch()", in: recheck),
                          try offset(of: "rebuildMenu()", in: recheck))
    }

    /// A reload stays the one thing that reads the file and changes the rules, the
    /// status, the prepared sounds and the warmed voices.
    func testARecheckReadsNoFileAndForgetsNoSound() throws {
        let recheck = try body(of: "func recheckWarnings() -> Bool {", in: try code("RuleStore.swift"))
        for forbidden in ["file.read()", "forgetPreparedSounds", "status =", "rules =", "warmVoices", "appliedFingerprint"] {
            XCTAssertFalse(recheck.contains(forbidden), forbidden)
        }
        XCTAssertTrue(recheck.contains("RuleWarnings.warnings(for: rules, sounds: soundCheck)"))
    }
}
