import XCTest
@testable import NotificationCore

/// What the four display settings decide (M7 plan, Stage 1). Every combination
/// of the four is tried, since there are only sixteen.
final class DisplaySettingsTests: XCTestCase {
    private var everyCombination: [DisplaySettings] {
        let both = [false, true]
        return both.flatMap { contrast in
            both.flatMap { transparency in
                both.flatMap { motion in
                    both.map { colour in
                        DisplaySettings(increaseContrast: contrast, reduceTransparency: transparency,
                                        reduceMotion: motion, differentiateWithoutColour: colour)
                    }
                }
            }
        }
    }

    func testThereAreSixteenCombinationsAndAllOffIsOneOfThem() {
        XCTAssertEqual(everyCombination.count, 16)
        XCTAssertEqual(everyCombination.filter { $0 == .allOff }.count, 1)
        XCTAssertFalse(DisplaySettings.allOff.increaseContrast)
        XCTAssertFalse(DisplaySettings.allOff.reduceTransparency)
        XCTAssertFalse(DisplaySettings.allOff.reduceMotion)
        XCTAssertFalse(DisplaySettings.allOff.differentiateWithoutColour)
    }

    // MARK: - Outlines

    func testOutlinesAreStrengthenedForMoreContrastAndForNoMeaningByColour() {
        for settings in everyCombination {
            XCTAssertEqual(settings.strengthensOutlines,
                           settings.increaseContrast || settings.differentiateWithoutColour, "\(settings)")
        }
    }

    func testNeitherTransparencyNorMotionStrengthensAnOutline() {
        var settings = DisplaySettings.allOff
        settings.reduceTransparency = true
        settings.reduceMotion = true
        XCTAssertFalse(settings.strengthensOutlines)
    }

    /// The line round a fault: a point heavier where outlines are strengthened,
    /// and never thinner than a point and a half, which is still seen on a
    /// display that draws one point as one pixel.
    func testTheLineRoundAFaultIsHeavierWhereOutlinesAreStrengthened() {
        XCTAssertEqual(DisplaySettings.allOff.outlineWidth, 1.5)
        for settings in everyCombination {
            XCTAssertEqual(settings.outlineWidth, settings.strengthensOutlines ? 2.5 : 1.5, "\(settings)")
            XCTAssertGreaterThanOrEqual(settings.outlineWidth, 1.5)
        }
    }

    // MARK: - Motion

    func testReduceMotionAloneHoldsThingsStill() {
        var motion = DisplaySettings.allOff
        motion.reduceMotion = true
        XCTAssertTrue(motion.holdsStill)
    }

    func testTheOtherThreeTogetherLeaveThingsMoving() {
        let others = DisplaySettings(increaseContrast: true, reduceTransparency: true, reduceMotion: false,
                                     differentiateWithoutColour: true)
        XCTAssertFalse(others.holdsStill)
        XCTAssertFalse(DisplaySettings.allOff.holdsStill)
    }

    // MARK: - The ground

    func testWithNoGlassTheGroundIsSolidWhateverTheSettings() {
        for settings in everyCombination {
            XCTAssertEqual(GroundMaterial.choose(glassAvailable: false, settings: settings), .solid, "\(settings)")
        }
    }

    func testGlassIsDrawnOnlyWhenNeitherLessTransparencyNorMoreContrastIsAskedFor() {
        for settings in everyCombination {
            let expected: GroundMaterial = settings.reduceTransparency || settings.increaseContrast ? .solid : .glass
            XCTAssertEqual(GroundMaterial.choose(glassAvailable: true, settings: settings), expected, "\(settings)")
        }
    }

    func testReduceMotionAndNoMeaningByColourLeaveTheGlassAlone() {
        var settings = DisplaySettings.allOff
        settings.reduceMotion = true
        settings.differentiateWithoutColour = true
        XCTAssertEqual(GroundMaterial.choose(glassAvailable: true, settings: settings), .glass)
    }

    func testEachOfTheTwoThatRefuseGlassDoesSoAlone() {
        var lessTransparency = DisplaySettings.allOff
        lessTransparency.reduceTransparency = true
        XCTAssertEqual(GroundMaterial.choose(glassAvailable: true, settings: lessTransparency), .solid)

        var moreContrast = DisplaySettings.allOff
        moreContrast.increaseContrast = true
        XCTAssertEqual(GroundMaterial.choose(glassAvailable: true, settings: moreContrast), .solid)
    }
}
