import XCTest
@testable import NotificationCore

/// What a render hands the window: the samples as the recipe makes them, what the checks say of them, the gain a
/// preview is played at and the columns the waveform is drawn from (sound editor plan, Rulings 6, 7 and 16, and
/// Task 7). It is everything the window learns from a render, made in one call over values only, so that it can be
/// made off the main actor and swapped in whole.
final class SoundEditorRenderingTests: XCTestCase {
    private typealias S = SoundSignals

    private func render(_ source: SampleBuffer, _ recipe: SoundRecipe? = nil, ruleGainDB: Double = 0,
                        visible: Range<Int>? = nil, columns: Int = 100) -> SoundRendered {
        SoundEditorRendering.render(source: source, recipe: recipe ?? SoundFixtures.whole(source.frameCount),
                                    ruleGainDB: ruleGainDB, visible: visible ?? 0..<source.frameCount, columnCount: columns)
    }

    // MARK: - What a render holds

    func testTheSamplesAreWhatTheRecipeRendersTo() {
        let source = S.sine(frames: 48_000, hz: 440, amplitude: 0.5)
        let recipe = SoundFixtures.recipe([SoundFixtures.clip(0, 12_000), SoundFixtures.clip(24_000, 48_000)], frames: 48_000)
        let rendered = render(source, recipe)
        XCTAssertEqual(rendered.samples, SoundRender.render(source: source, recipe: recipe))
        XCTAssertEqual(rendered.samples.frameCount, recipe.frameCount)
    }

    func testTheFindingsAreTheChecksOnTheRenderedSamplesAndNotOnTheSource() {
        let source = SoundFindingSamples.goodTone(frames: 96_000)
        XCTAssertEqual(render(source).findings, [], "a good tone has nothing to say of it")
        let short = SoundFixtures.recipe([SoundFixtures.clip(0, 9_600)], frames: 96_000)
        let rendered = render(source, short)
        XCTAssertEqual(rendered.findings, SoundChecks.findings(in: rendered.samples))
        XCTAssertTrue(rendered.findings.contains { $0.kind == .tooShort }, "the result is short though the source is not")
    }

    // MARK: - The gain a preview is played at

    func testThePreviewGainIsTheGainTheWholeResultWouldBeGivenAsAnAlert() {
        let source = S.sine(frames: 48_000, hz: 440, amplitude: 0.5)
        for rule in [0.0, 6, -9.5] {
            let rendered = render(source, ruleGainDB: rule)
            let expected = Loudness.appliedGainDB(forPeak: rendered.samples.peak, ruleGainDB: rule)
            XCTAssertEqual(rendered.previewGainDB, expected)
            XCTAssertNotNil(rendered.previewGainDB)
        }
        let at0 = render(source, ruleGainDB: 0).previewGainDB!
        let at6 = render(source, ruleGainDB: 6).previewGainDB!
        XCTAssertEqual(at6 - at0, 6, accuracy: 1e-9, "the rule's gain is added to the level-matching")
    }

    func testThePreviewGainComesFromThePeakOfTheWholeResultAndNotOfAPartOfIt() {
        // A loud half and a quiet half. The quiet half, played alone and level-matched on its own, would be
        // raised by 20 dB; played at the whole's gain it is as quiet as it is in the whole.
        let loud = S.sine(frames: 24_000, hz: 440, amplitude: 0.9)
        let quiet = S.sine(frames: 24_000, hz: 440, amplitude: 0.09)
        let source = SampleBuffer(channels: zip(loud.channels, quiet.channels).map { $0 + $1 })!
        let whole = render(source)
        XCTAssertEqual(whole.previewGainDB!, Loudness.appliedGainDB(forPeak: source.peak, ruleGainDB: 0)!, accuracy: 1e-9)
        let quietOnly = render(source, SoundFixtures.recipe([SoundFixtures.clip(24_000, 48_000)], frames: 48_000))
        XCTAssertEqual(quietOnly.previewGainDB! - whole.previewGainDB!, 20, accuracy: 0.3,
                       "a result of only the quiet half is a different sound, and is raised to match")
    }

    func testAResultBelowTheSilenceFloorHasNoPreviewGainAndCannotBeHeard() {
        let rendered = render(S.constant(0.0001, frames: 48_000))
        XCTAssertNil(rendered.previewGainDB)
        XCTAssertFalse(rendered.canBeHeard)
        XCTAssertTrue(rendered.findings.contains { $0.kind == .nothingToHear })
        XCTAssertTrue(render(S.sine(frames: 48_000, hz: 440)).canBeHeard)
    }

    // MARK: - The columns

    func testTheColumnsAreThoseOfTheVisibleFramesOfTheRenderedSamples() {
        let source = S.sine(frames: 48_000, hz: 440, amplitude: 0.5)
        let rendered = render(source, visible: 12_000..<36_000, columns: 80)
        XCTAssertEqual(rendered.columns.frames, 12_000..<36_000)
        XCTAssertEqual(rendered.columns.columns.count, 80)
        XCTAssertEqual(rendered.columns.columns, WaveformPeaks.columns(of: rendered.samples, frames: 12_000..<36_000, count: 80))
    }

    func testTheVisibleFramesAreHeldToTheRenderedSound() {
        let source = S.sine(frames: 48_000, hz: 440)
        let past = render(source, visible: 40_000..<90_000, columns: 10)
        XCTAssertEqual(past.columns.frames, 40_000..<48_000)
        let nowhere = render(source, visible: 60_000..<90_000, columns: 10)
        XCTAssertEqual(nowhere.columns.frames, 0..<48_000, "a view that is wholly outside the new sound shows all of it")
    }

    func testTheColumnsOfANewSoundAreMadeInTheSameCallAsItsSamples() {
        let source = S.constant(0.25, frames: 4_800)
        let rendered = render(source, columns: 4)
        XCTAssertEqual(rendered.columns.columns, Array(repeating: WaveformPeaks.Column(minimum: 0.25, maximum: 0.25), count: 4))
    }

    // MARK: - Drawing columns

    private func columns(over frames: Range<Int>, count: Int = 10) -> WaveformColumns {
        let samples = S.both(frames: frames.upperBound) { _ in 0.5 }
        return WaveformColumns.make(of: samples, frames: frames, count: count)
    }

    func testEachColumnIsABarAsWideAsItsFramesAreOfTheViewAndAsTallAsItsSamples() {
        let samples = S.stereo(frames: 1_000, left: { Float($0 / 100) / 20 }, right: { -Float($0 / 100) / 10 })
        let set = WaveformColumns.make(of: samples, frames: 0..<1_000, count: 10)
        let bars = set.bars(in: WaveformViewport(length: 1_000), width: 100)
        XCTAssertEqual(bars.count, 10)
        for (index, bar) in bars.enumerated() {
            XCTAssertEqual(bar.x, Double(index) * 10, accuracy: 1e-9)
            XCTAssertEqual(bar.width, 10, accuracy: 1e-9)
            XCTAssertEqual(bar.high, Float(index) / 20 + 0.0, accuracy: 1e-6)
            XCTAssertEqual(bar.low, -Float(index) / 10, accuracy: 1e-6)
        }
    }

    func testColumnsDrawnInAViewThatIsZoomedAreDrawnWhereTheirFramesAreAndClippedAtItsEdges() {
        let set = columns(over: 0..<1_000)
        var viewport = WaveformViewport(length: 1_000)
        viewport.zoomIn(around: 500)
        XCTAssertEqual(viewport.visible, 250..<750)
        let bars = set.bars(in: viewport, width: 100)
        // A column is 100 frames, which is 20 points here. Column 2 runs from -10 to 10 and column 7 from 90 to 110.
        XCTAssertEqual(bars.count, 6)
        XCTAssertEqual(bars.first?.x ?? -1, 0, accuracy: 1e-9)
        XCTAssertEqual(bars.first?.width ?? -1, 10, accuracy: 1e-9)
        XCTAssertEqual(bars.last?.x ?? -1, 90, accuracy: 1e-9)
        XCTAssertEqual(bars.last?.width ?? -1, 10, accuracy: 1e-9)
        for bar in bars {
            XCTAssertGreaterThanOrEqual(bar.x, 0)
            XCTAssertLessThanOrEqual(bar.x + bar.width, 100 + 1e-9)
            XCTAssertGreaterThan(bar.width, 0)
        }
    }

    func testAColumnSetThatCoversOnlyPartOfTheViewDrawsOnlyThatPart() {
        let set = columns(over: 200..<400, count: 2)
        let bars = set.bars(in: WaveformViewport(length: 1_000), width: 100)
        XCTAssertEqual(bars.map(\.x), [20, 30].map { Double($0) })
        XCTAssertEqual(bars.map(\.width), [10, 10])
    }

    func testNothingIsDrawnForNoWidthOrNoColumns() {
        XCTAssertEqual(columns(over: 0..<1_000).bars(in: WaveformViewport(length: 1_000), width: 0), [])
        XCTAssertEqual(columns(over: 0..<1_000, count: 10).bars(in: WaveformViewport(length: 0), width: 100), [])
        XCTAssertEqual(WaveformColumns.make(of: S.constant(0.5, frames: 1_000), frames: 0..<1_000, count: 0)
            .bars(in: WaveformViewport(length: 1_000), width: 100), [])
    }

    // MARK: - Whether the columns are fine enough

    func testColumnsAreEnoughWhenTheyCoverWhatIsShownAtAboutAColumnToAPoint() {
        let set = columns(over: 0..<1_000, count: 100)
        let whole = WaveformViewport(length: 1_000)
        XCTAssertTrue(set.isEnough(for: whole, width: 100))
        XCTAssertTrue(set.isEnough(for: whole, width: 130), "three quarters of a column to a point is as coarse as they go")
        XCTAssertFalse(set.isEnough(for: whole, width: 140))
        XCTAssertTrue(set.isEnough(for: whole, width: 20), "finer than needed is enough")
    }

    func testColumnsAreNotEnoughForAViewThatIsZoomedPastWhatTheyShow() {
        let set = columns(over: 0..<1_000, count: 100)
        var zoomed = WaveformViewport(length: 1_000)
        zoomed.zoomIn(around: 500)
        XCTAssertFalse(set.isEnough(for: zoomed, width: 100), "half of them are in view")
        XCTAssertTrue(set.isEnough(for: zoomed, width: 60))
    }

    func testColumnsAreNotEnoughForAViewTheyDoNotCover() {
        let set = columns(over: 0..<500, count: 100)
        XCTAssertFalse(set.isEnough(for: WaveformViewport(length: 1_000), width: 100))
        var scrolled = WaveformViewport(length: 1_000)
        scrolled.zoomIn(around: 0)
        scrolled.scroll(toStart: 400)
        XCTAssertFalse(set.isEnough(for: scrolled, width: 100))
    }

    func testNoColumnsAreEnoughForAViewOfSomethingAndAViewOfNothingNeedsNone() {
        let none = WaveformColumns.make(of: S.constant(0.5, frames: 1_000), frames: 0..<1_000, count: 0)
        XCTAssertFalse(none.isEnough(for: WaveformViewport(length: 1_000), width: 100))
        XCTAssertTrue(none.isEnough(for: WaveformViewport(length: 0), width: 100))
    }

    // MARK: - How many to ask for

    func testTheCountAskedForIsTheWidthUpToTheNextTwoHundredAndFiftySixAndIsHeld() {
        XCTAssertEqual(WaveformColumns.count(forWidth: 0), 256)
        XCTAssertEqual(WaveformColumns.count(forWidth: -3), 256)
        XCTAssertEqual(WaveformColumns.count(forWidth: 100), 256)
        XCTAssertEqual(WaveformColumns.count(forWidth: 256), 256)
        XCTAssertEqual(WaveformColumns.count(forWidth: 257), 512)
        XCTAssertEqual(WaveformColumns.count(forWidth: 700.5), 768)
        XCTAssertEqual(WaveformColumns.count(forWidth: 99_999), 4_096)
        XCTAssertEqual(WaveformColumns.count(forWidth: .nan), 256)
    }

    func testTheCountAskedForIsAlwaysEnoughForTheWidthItWasAskedFor() {
        let whole = WaveformViewport(length: 48_000)
        for width in stride(from: 1.0, through: 3_000, by: 37) {
            let set = WaveformColumns.make(of: S.constant(0.5, frames: 48_000), frames: 0..<48_000,
                                           count: WaveformColumns.count(forWidth: width))
            XCTAssertTrue(set.isEnough(for: whole, width: width), "width \(width)")
        }
    }
}
