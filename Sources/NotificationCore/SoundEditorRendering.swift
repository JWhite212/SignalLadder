// Sources/NotificationCore/SoundEditorRendering.swift
import Foundation

/// The columns of the waveform for a stretch of the sound, and the arithmetic of drawing them (sound editor plan,
/// Task 7).
///
/// The columns are kept with the frames they were made for, so that columns that are not for what is in view now,
/// because a zoom or a render is still being waited for, are still drawn where their own frames are and not
/// stretched across a view they are not of.
public struct WaveformColumns: Equatable, Sendable {
    /// One column of the drawing, in points of the drawing it is drawn in.
    public struct Bar: Equatable, Sendable {
        /// How far across it begins and how wide it is, cut to the drawing.
        public let x: Double
        public let width: Double
        public let low: Float
        public let high: Float
    }

    /// The frames the columns are of.
    public let frames: Range<Int>
    public let columns: [WaveformPeaks.Column]

    /// How many columns to the point are enough: fewer than this and a drawing would be coarse enough to see.
    public static let enoughPerPoint = 0.75
    /// A request is for a whole number of these, so that a window made a little wider does not ask for new columns.
    public static let countStep = 256
    public static let mostColumns = 4_096

    /// `count` columns across `frames` of `samples`.
    public static func make(of samples: SampleBuffer, frames: Range<Int>, count: Int) -> WaveformColumns {
        WaveformColumns(frames: frames, columns: WaveformPeaks.columns(of: samples, frames: frames, count: count))
    }

    /// How many columns to ask for a drawing `width` points wide: its width up to the next step, and at least one
    /// step.
    public static func count(forWidth width: Double) -> Int {
        guard width.isFinite, width > 0 else { return countStep }
        let steps = Int((min(width, Double(mostColumns)) / Double(countStep)).rounded(.up))
        return max(steps, 1) * countStep
    }

    /// The bars of the columns that are in `viewport`, across a drawing `width` points wide, cut to its edges.
    public func bars(in viewport: WaveformViewport, width: Double) -> [Bar] {
        guard width > 0, !columns.isEmpty, !viewport.visible.isEmpty else { return [] }
        let span = frames.count
        var bars: [Bar] = []
        for (index, column) in columns.enumerated() {
            let first = frames.lowerBound + index * span / columns.count
            let last = frames.lowerBound + (index + 1) * span / columns.count
            let left = max(viewport.x(of: first, width: width), 0)
            let right = min(viewport.x(of: last, width: width), width)
            guard right > left else { continue }
            bars.append(Bar(x: left, width: right - left, low: column.minimum, high: column.maximum))
        }
        return bars
    }

    /// Whether these columns draw `viewport` well: they cover all of what is shown, and have about a column to a
    /// point of it. A view of nothing needs none.
    public func isEnough(for viewport: WaveformViewport, width: Double) -> Bool {
        guard !viewport.visible.isEmpty else { return true }
        guard frames.lowerBound <= viewport.visible.lowerBound, frames.upperBound >= viewport.visible.upperBound,
              !frames.isEmpty else { return false }
        let inView = Double(columns.count) * Double(viewport.visible.count) / Double(frames.count)
        return inView >= Self.enoughPerPoint * max(width, 0)
    }
}

/// What a render hands the window: the samples as the recipe makes them, what the checks say of them, the gain a
/// preview is played at and the columns the waveform is drawn from (sound editor plan, Rulings 6, 7 and 16).
public struct SoundRendered: Equatable, Sendable {
    public let samples: SampleBuffer
    public let findings: [SoundFinding]
    /// The gain the whole result is given as an alert, with the rule's own gain in it, which a preview of any part
    /// is played at (Ruling 7). nil when the result is below the silence floor and no alert of it would be heard.
    public let previewGainDB: Double?
    public let columns: WaveformColumns

    public var canBeHeard: Bool { previewGainDB != nil }
}

/// The one call a render is, made over values only, so that it can run off the main actor and be swapped in whole
/// (Ruling 6).
public enum SoundEditorRendering {
    /// Renders `recipe` of `source`, and works out from the result, once and from all of it, what is said of it,
    /// what a preview is played at, and the columns of `visible`, held to the result.
    public static func render(source: SampleBuffer, recipe: SoundRecipe, ruleGainDB: Double, visible: Range<Int>,
                              columnCount: Int) -> SoundRendered {
        let samples = SoundRender.render(source: source, recipe: recipe)
        let shown = WaveformViewport(length: samples.frameCount, visible: visible).visible
        return SoundRendered(samples: samples,
                             findings: SoundChecks.findings(in: samples),
                             previewGainDB: Loudness.appliedGainDB(forPeak: samples.peak, ruleGainDB: ruleGainDB),
                             columns: WaveformColumns.make(of: samples, frames: shown, count: columnCount))
    }
}
