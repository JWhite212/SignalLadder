import XCTest
@testable import NotificationCore

/// On-call state is one saved date (M5 plan, Ruling 7, O4). What is saved may be
/// anything, so every kind of value the preferences could hand back is read here,
/// and each that is not a time reads as on, never as off.
final class OnCallStateTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let earlier = Date(timeIntervalSince1970: 1_789_900_000)

    private func read(_ stored: Any?) -> OnCallState {
        OnCallState(stored: stored, now: now)
    }

    // MARK: - Reading

    func testNothingSavedIsOff() {
        XCTAssertEqual(read(nil), .off)
        XCTAssertFalse(read(nil).isOn)
        XCTAssertNil(read(nil).since)
    }

    func testASavedDateIsOnSinceThatDate() {
        let state = read(earlier.timeIntervalSince1970)
        XCTAssertEqual(state, .on(since: earlier))
        XCTAssertTrue(state.isOn)
        XCTAssertEqual(state.since, earlier)
    }

    /// The preferences hand a number back as an `NSNumber`, whatever it was
    /// written as, and a whole number written by hand is one as well.
    func testANumberIsReadWhateverKindItArrivesAs() {
        XCTAssertEqual(read(NSNumber(value: earlier.timeIntervalSince1970)), .on(since: earlier))
        XCTAssertEqual(read(NSNumber(value: 1_789_900_000)), .on(since: earlier))
        XCTAssertEqual(read(1_789_900_000), .on(since: earlier))
    }

    /// A clock set back, or a value from the future, must not have the menu say
    /// the user went on call tomorrow.
    func testADateAfterNowReadsAsSinceNow() {
        XCTAssertEqual(read(now.timeIntervalSince1970 + 3600), .on(since: now))
        XCTAssertEqual(read(now.timeIntervalSince1970 + 0.5), .on(since: now))
        XCTAssertEqual(read(1e300), .on(since: now))
    }

    func testADateExactlyNowIsSinceNowAndOneBeforeIsKept() {
        XCTAssertEqual(read(now.timeIntervalSince1970), .on(since: now))
        let justBefore = now.addingTimeInterval(-1)
        XCTAssertEqual(read(justBefore.timeIntervalSince1970), .on(since: justBefore))
    }

    func testANumberThatIsNotAUsableTimeReadsAsOnWithNoTimeKnown() {
        for number in [Double.infinity, -Double.infinity, Double.nan, -1, -0.5, -1_789_900_000] {
            XCTAssertEqual(read(number), .on(since: nil), "\(number)")
        }
    }

    /// The least a time can be is the start of 1970; below it is not one.
    func testZeroIsTheEarliestTimeThatReads() {
        XCTAssertEqual(read(0.0), .on(since: Date(timeIntervalSince1970: 0)))
        XCTAssertEqual(read(-0.001), .on(since: nil))
    }

    func testAValueThatIsNotANumberReadsAsOnWithNoTimeKnown() {
        let values: [(name: String, value: Any)] = [
            ("a string", "Mon 09:00"),
            ("a number written as a string", "1789900000"),
            ("an empty string", ""),
            ("a date", earlier),
            ("data", Data([1, 2, 3])),
            ("a list", [earlier.timeIntervalSince1970]),
            ("a dictionary", ["since": earlier.timeIntervalSince1970]),
            ("null", NSNull()),
        ]
        for (name, value) in values {
            XCTAssertEqual(read(value), .on(since: nil), name)
        }
    }

    /// A Boolean reads as the number 1 or 0, which would put the switch at the
    /// first second of 1970. It is on, since when is not known.
    func testABooleanReadsAsOnWithNoTimeKnownAndNotAsATimeIn1970() {
        XCTAssertEqual(read(true), .on(since: nil))
        XCTAssertEqual(read(false), .on(since: nil))
        XCTAssertEqual(read(NSNumber(value: true)), .on(since: nil))
        XCTAssertEqual(read(NSNumber(value: false)), .on(since: nil))
    }

    // MARK: - Saving

    func testTheKeyIsTheOneThePlanNames() {
        XCTAssertEqual(OnCallState.storageKey, "onCallSince")
    }

    func testOffStoresNothing() {
        XCTAssertEqual(OnCallState.off.write, .remove)
    }

    func testOnSavesTheTimeInSecondsSince1970() {
        XCTAssertEqual(OnCallState.on(since: earlier).write, .set(1_789_900_000))
    }

    /// There is no time to save, and what is saved is what made it on.
    func testOnWithNoTimeKnownLeavesWhatIsSaved() {
        XCTAssertEqual(OnCallState.on(since: nil).write, .keep)
    }

    /// Applies a write to a stored value as the app's store does to the
    /// preferences.
    private func apply(_ write: OnCallState.Write, to stored: Any?) -> Any? {
        switch write {
        case .remove: return nil
        case .set(let seconds): return seconds
        case .keep: return stored
        }
    }

    func testAStateSavedIsReadBackAsItWas() {
        for state in [OnCallState.off, .on(since: earlier), .on(since: Date(timeIntervalSince1970: 1_700_000_000.25))] {
            let saved = apply(state.write, to: "left over from before")
            XCTAssertEqual(read(saved), state, "\(state)")
        }
    }

    func testSavingOffAfterOnLeavesNothingForTheNextLaunchToRestore() {
        let saved = apply(OnCallState.on(since: earlier).write, to: nil)
        XCTAssertEqual(read(saved), .on(since: earlier))
        XCTAssertEqual(read(apply(OnCallState.off.write, to: saved)), .off)
    }

    func testAStateWithNoTimeKnownIsStillOnAfterItIsSavedAgain() {
        let saved = apply(OnCallState.on(since: nil).write, to: "unreadable")
        XCTAssertEqual(read(saved), .on(since: nil))
    }
}
