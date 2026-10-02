import XCTest
@testable import NotificationCore

/// Whether the app's own beeps can be heard (M5 plan, Ruling 9). The app target
/// reads the preference and hands the value over; these are what the core makes
/// of it. Nothing here reads the preferences or sounds a beep.
final class BeepAudibilityTests: XCTestCase {
    func testANumberBelowTheThresholdIsSilentAndZeroAndANegativeOneAreIncluded() {
        for volume in [0, -0.5, -1, 0.01, 0.0199] as [Double] {
            XCTAssertTrue(BeepAudibility.isSilent(alertVolume: volume), "\(volume)")
        }
    }

    func testTheThresholdAndAboveAreNotSilent() {
        for volume in [0.02, 0.0201, 0.0625, 0.5, 1, 2] as [Double] {
            XCTAssertFalse(BeepAudibility.isSilent(alertVolume: volume), "\(volume)")
        }
        XCTAssertEqual(BeepAudibility.inaudibleBelow, 0.02)
    }

    /// Nothing read is nothing claimed.
    func testAValueThatCouldNotBeReadIsNotSilent() {
        XCTAssertFalse(BeepAudibility.isSilent(alertVolume: nil))
    }

    func testAValueThatIsNotFiniteIsReadAsNilAndIsNotSilent() {
        for volume in [Double.nan, .infinity, -.infinity] {
            XCTAssertFalse(BeepAudibility.isSilent(alertVolume: volume), "\(volume)")
            XCTAssertNil(BeepAudibility.alertVolume(fromStored: NSNumber(value: volume)), "\(volume)")
        }
    }

    func testTheVolumeIsReadFromWhateverThePreferencesGiveBack() {
        XCTAssertEqual(BeepAudibility.alertVolume(fromStored: NSNumber(value: 1.0)), 1)
        XCTAssertEqual(BeepAudibility.alertVolume(fromStored: 0.5 as Double), 0.5)
        XCTAssertEqual(BeepAudibility.alertVolume(fromStored: 0 as Int), 0)
        XCTAssertEqual(BeepAudibility.alertVolume(fromStored: NSNumber(value: Float(0.25))), 0.25)
        XCTAssertEqual(BeepAudibility.alertVolume(fromStored: -1 as Int), -1, "a negative number is a number, and silent")
    }

    /// A Boolean reads as 1 or 0 and would be taken for a volume nobody set.
    func testAnythingThatIsNotANumberReadsAsNil() {
        XCTAssertNil(BeepAudibility.alertVolume(fromStored: nil))
        XCTAssertNil(BeepAudibility.alertVolume(fromStored: true))
        XCTAssertNil(BeepAudibility.alertVolume(fromStored: false))
        XCTAssertNil(BeepAudibility.alertVolume(fromStored: NSNumber(value: false)))
        XCTAssertNil(BeepAudibility.alertVolume(fromStored: "0.5"))
        XCTAssertNil(BeepAudibility.alertVolume(fromStored: [0.5]))
        XCTAssertNil(BeepAudibility.alertVolume(fromStored: Date()))
    }

    func testTheValueReadFromAStoredZeroIsSilentAndFromAStoredOneIsNot() {
        XCTAssertTrue(BeepAudibility.isSilent(alertVolume: BeepAudibility.alertVolume(fromStored: 0 as Int)))
        XCTAssertFalse(BeepAudibility.isSilent(alertVolume: BeepAudibility.alertVolume(fromStored: 1 as Int)))
        XCTAssertFalse(BeepAudibility.isSilent(alertVolume: BeepAudibility.alertVolume(fromStored: true)))
    }

    /// The preference that holds Alert volume, in the global domain. It is read and
    /// never written.
    func testThePreferenceKeyIsTheGlobalAlertVolume() {
        XCTAssertEqual(BeepAudibility.preferenceKey, "com.apple.sound.beep.volume")
    }
}
