import XCTest
@testable import NotificationCore

final class LoudnessTests: XCTestCase {
    private func amplitude(_ dBFS: Double) -> Float { Float(pow(10, dBFS / 20)) }

    func testEverySoundsPeakLandsAtTheSameLevelAtGainZero() throws {
        // The measured system-sound peaks: Frog −15.26, Glass −14.06, Hero −5.43.
        for peakDB in [-15.26, -14.06, -5.43, -1.0] {
            let gain = try XCTUnwrap(Loudness.appliedGainDB(forPeak: amplitude(peakDB), ruleGainDB: 0))
            XCTAssertEqual(peakDB + gain, Loudness.targetPeakDBFS, accuracy: 0.001, "peak \(peakDB)")
        }
    }

    func testTheRulesGainAppliesOnTopOfLevelMatching() throws {
        let frog = amplitude(-15.26)
        let atZero = try XCTUnwrap(Loudness.appliedGainDB(forPeak: frog, ruleGainDB: 0))
        let atSix = try XCTUnwrap(Loudness.appliedGainDB(forPeak: frog, ruleGainDB: 6))
        let atMinusTwenty = try XCTUnwrap(Loudness.appliedGainDB(forPeak: frog, ruleGainDB: -20))
        XCTAssertEqual(atSix - atZero, 6, accuracy: 0.001)
        XCTAssertEqual(atMinusTwenty - atZero, -20, accuracy: 0.001)
    }

    func testAFileAlreadyAtFullScaleIsTurnedDown() throws {
        let gain = try XCTUnwrap(Loudness.appliedGainDB(forPeak: 1.0, ruleGainDB: 0))
        XCTAssertEqual(gain, -1, accuracy: 0.001, "normalisation lowers as well as raises")
    }

    func testASilentFileCannotBePlayed() {
        // "Played" for a file nobody could hear would be a false report.
        XCTAssertNil(Loudness.appliedGainDB(forPeak: 0, ruleGainDB: 0))
        XCTAssertNil(Loudness.appliedGainDB(forPeak: amplitude(-70), ruleGainDB: 12))
        XCTAssertFalse(Loudness.isAudible(peak: amplitude(-60.5)))
        XCTAssertTrue(Loudness.isAudible(peak: amplitude(-59.5)))
    }

    func testAMeasurementThatIsNotARealNumberCannotBePlayed() {
        XCTAssertNil(Loudness.appliedGainDB(forPeak: .nan, ruleGainDB: 0))
        XCTAssertNil(Loudness.appliedGainDB(forPeak: .infinity, ruleGainDB: 0))
        XCTAssertNil(Loudness.appliedGainDB(forPeak: -0.5, ruleGainDB: 0))
    }

    func testAVeryQuietFileIsBoostedOnlySoFar() throws {
        // −45 dBFS would need +44 dB; capped at +24 it stays quieter rather
        // than turning its own noise floor into the alert.
        let gain = try XCTUnwrap(Loudness.appliedGainDB(forPeak: amplitude(-45), ruleGainDB: 0))
        XCTAssertEqual(gain, Loudness.maximumBoostDB, accuracy: 0.001)
    }
}
