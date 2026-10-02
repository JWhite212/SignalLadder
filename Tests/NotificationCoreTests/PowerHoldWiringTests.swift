import XCTest
@testable import NotificationCore

/// How the app target makes its two holds against idle sleep and carries out
/// what the core says about them (M5 plan, O7, Ruling 10).
///
/// The app target has no tests, and the pairing of each hold with the places
/// that begin and end it is wiring that nothing but the code itself decides:
/// the coordinator's closures use the escalation's hold, on-call mode's hold is
/// taken at launch and at a switch and let go of at a switch, and neither ever
/// ends the other's. Swap any of them and the app builds without a warning, and
/// an escalation ending would let a Mac that is on call go to sleep, or
/// switching off would leave it held. So these tests read the app's sources, as
/// `ViewLiteralsTests` does, and hold each place to what it is meant to say.
/// They start nothing and take no hold.
///
/// Which reason and which options each hold has are `PowerHold`'s, and are
/// tested in `PowerHoldTests`; what is held here is only that the app makes its
/// holds from them and from nothing of its own.
final class PowerHoldWiringTests: XCTestCase {
    /// A source file's code: no comments, each line's spacing collapsed to single
    /// spaces and the lines that are left empty gone. A comment may name a call
    /// to explain it and is not a place the app makes one. A `//` inside a string
    /// would cut its line short, which is harmless for the lines read here, since
    /// none holds one.
    static func code(of source: String) -> String {
        source.components(separatedBy: "\n")
            .map { line -> String in
                let code = line.range(of: "//").map { String(line[..<$0.lowerBound]) } ?? line
                return code.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private func code(_ file: String) throws -> String {
        Self.code(of: try XCTUnwrap(AppSources.read(file), "\(file) cannot be read at \(AppSources.directory.path)"))
    }

    private func count(_ needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    func testTheCodeReaderDropsCommentsAndSpacingAndNothingElse() {
        let source = [
            "/// A doc comment that names escalationPower.begin()",
            "let held = PowerAssertion(.onCall)   // a trailing one, naming onCallPower.end()",
            "",
            "    case .releaseAwake:   onCallPower.end()",
            "   // a line of its own",
        ].joined(separator: "\n")
        XCTAssertEqual(Self.code(of: source),
                       "let held = PowerAssertion(.onCall)\ncase .releaseAwake: onCallPower.end()")
    }

    // MARK: The two holds the app makes

    func testTheAppMakesTwoHoldsEachFromOneOfTheCoresCasesAndNoOtherAnywhere() throws {
        var constructions = 0
        for file in try AppSources.fileNames() {
            constructions += count("PowerAssertion(", in: try code(file))
        }
        XCTAssertEqual(constructions, 2, "the app makes the escalation's hold and on-call mode's, and no third")

        let app = try code("AppDelegate.swift")
        XCTAssertEqual(count("private let escalationPower = PowerAssertion(.escalation)", in: app), 1)
        XCTAssertEqual(count("private let onCallPower = PowerAssertion(.onCall)", in: app), 1)
    }

    /// Nothing in the app target begins an activity but `PowerAssertion`, and
    /// nothing in it names the options of one: they are `PowerHold`'s.
    func testNoHoldIsTakenButByPowerAssertionAndNoneNamesOptionsOfItsOwn() throws {
        var begun = 0
        for file in try AppSources.fileNames() {
            let source = try code(file)
            begun += count("beginActivity(", in: source)
            XCTAssertFalse(source.contains("ActivityOptions"), "\(file) names options of its own for a hold")
        }
        XCTAssertEqual(begun, 1, "a hold is begun in PowerAssertion and nowhere else")

        let assertion = try code("PowerAssertion.swift")
        XCTAssertEqual(
            count("ProcessInfo.processInfo.beginActivity(options: hold.options, reason: hold.reason)", in: assertion), 1)
        for name in ["userInitiated", "idleSystemSleepDisabled", "idleDisplaySleepDisabled"] {
            XCTAssertFalse(assertion.contains(name), "PowerAssertion names \(name) where the hold's options are PowerHold's")
        }
    }

    /// Each instance has an activity of its own, and ends that one and forgets it.
    /// One shared between them would make an escalation ending let go of the
    /// hold on-call mode keeps.
    func testEachHoldHasAnActivityOfItsOwnAndEndsThatOne() throws {
        let assertion = try code("PowerAssertion.swift")
        XCTAssertEqual(count("private var activity: NSObjectProtocol?", in: assertion), 1)
        XCTAssertFalse(assertion.contains("static"), "a shared activity would tie one hold's end to the other's")
        XCTAssertEqual(count("ProcessInfo.processInfo.endActivity(activity)", in: assertion), 1)
        XCTAssertEqual(count("self.activity = nil", in: assertion), 1)
    }

    // MARK: Who begins and ends each

    func testTheCoordinatorsClosuresBeginAndEndTheEscalationsHoldAndNothingElseUsesIt() throws {
        let app = try code("AppDelegate.swift")
        XCTAssertEqual(
            count("beginPowerAssertion: { [weak self] in self?.escalationPower.begin() },", in: app), 1)
        XCTAssertEqual(
            count("endPowerAssertion: { [weak self] in self?.escalationPower.end() },", in: app), 1)
        // Its declaration and those two closures: an escalation's hold is begun and
        // ended by the coordinator and by nothing a switch of on-call mode does.
        XCTAssertEqual(count("escalationPower", in: app), 3)
    }

    func testOnCallModesHoldIsTakenAtLaunchAndAtASwitchAndLetGoOfAtASwitchAlone() throws {
        let app = try code("AppDelegate.swift")

        let launch = [
            "for effect in OnCallSwitch.launchEffects(restored: onCall.state) {",
            "switch effect {",
            "case .holdAwake: onCallPower.begin()",
        ].joined(separator: "\n")
        XCTAssertEqual(count(launch, in: app), 1, "launch takes on-call mode's hold for the state it restored")

        let inSwitch = try XCTUnwrap(OnCallWiringTests.body(of: OnCallWiringTests.carryOut, in: app),
                                     "the switch's effects are carried out in one place")
        XCTAssertTrue(inSwitch.contains("case .holdAwake: onCallPower.begin()"), "a switch takes on-call mode's hold")
        XCTAssertTrue(inSwitch.contains("case .releaseAwake: onCallPower.end()"), "a switch lets go of on-call mode's hold")

        // Those are all of them, so that no other arm takes or lets go of a hold, and
        // neither the escalation's nor on-call mode's is ended by the other's effect.
        XCTAssertEqual(count("case .holdAwake: onCallPower.begin()", in: app), 2)
        XCTAssertEqual(count("case .releaseAwake: onCallPower.end()", in: app), 1)
        XCTAssertEqual(count(".holdAwake", in: app), 2)
        XCTAssertEqual(count(".releaseAwake", in: app), 1)
        // Its declaration, those three, and the one reading of whether it is held,
        // which the menu's line about the hold is said from.
        XCTAssertEqual(count("onCallPower", in: app), 5)
        XCTAssertEqual(count("onCallPower.isHeld", in: app), 1)
    }

    /// The menu says the Mac is being held awake of what the hold itself reports,
    /// and not of the mode being on: a hold that was never taken would otherwise
    /// be claimed.
    func testTheMenusLineAboutTheHoldIsSaidOfTheHoldAndNotOfTheMode() throws {
        let app = try code("AppDelegate.swift")
        XCTAssertEqual(count("if let awake = AlertMenuText.awakeLine(held: onCallPower.isHeld) {", in: app), 1)
        let assertion = try code("PowerAssertion.swift")
        XCTAssertEqual(count("var isHeld: Bool { activity != nil }", in: assertion), 1)
    }
}
