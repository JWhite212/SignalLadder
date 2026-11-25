import XCTest
@testable import NotificationCore

/// The tone of each tier (M7 plan, Stage 1).
final class TierToneTests: XCTestCase {
    func testEachTierOfTheLadderHasItsTone() {
        XCTAssertEqual(TierTone(tier: 1), .first)
        XCTAssertEqual(TierTone(tier: 2), .second)
        XCTAssertEqual(TierTone(tier: 3), .upper)
        XCTAssertEqual(TierTone(tier: 4), .upper)
    }

    /// Tier 2 is the first tier the panel shows, so it must not look like the
    /// first alert, nor like the repeats above it.
    func testTheThreeTonesAreDistinctAcrossTheLadder() {
        let tones = (1...4).map(TierTone.init(tier:))
        XCTAssertEqual(Set(tones.map { "\($0)" }).count, 3)
        XCTAssertNotEqual(tones[0], tones[1])
        XCTAssertNotEqual(tones[1], tones[2])
    }

    func testANumberThatIsNoTierStillHasATone() {
        XCTAssertEqual(TierTone(tier: 0), .first)
        XCTAssertEqual(TierTone(tier: -3), .first)
        XCTAssertEqual(TierTone(tier: 5), .upper)
        XCTAssertEqual(TierTone(tier: .max), .upper)
        XCTAssertEqual(TierTone(tier: .min), .first)
    }

    /// The palettes switch over every case, so a fourth would have to be given a colour.
    func testThereAreThreeTones() {
        XCTAssertEqual(TierTone.allCases, [.first, .second, .upper])
    }
}
