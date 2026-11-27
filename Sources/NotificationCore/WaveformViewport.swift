// Sources/NotificationCore/WaveformViewport.swift
import Foundation

/// Which stretch of the sound the waveform shows, and the arithmetic between a place on the drawing and a frame of
/// the sound (sound editor plan, Task 7).
///
/// It is all whole frames of the result, so that two reads of one place cannot differ by rounding, and none of it
/// leaves the sound: a stretch that is asked for beyond an end is the stretch that fits. The window's view only
/// says where a pointer is and how wide the drawing is.
public struct WaveformViewport: Equatable, Sendable {
    /// The least that is shown when zoomed in, as many frames as ten milliseconds, so that a few waves are
    /// always on screen and a column of the drawing is never less than a frame. A sound shorter than that is
    /// always shown whole.
    public static let narrowestFrames = SampleBuffer.frames(seconds: 0.01)

    /// How many frames of the sound there are, which is the end of the whole.
    public let length: Int
    /// The frames shown, held inside `0..<length`.
    public private(set) var visible: Range<Int>

    /// The whole sound.
    public init(length: Int) {
        self.length = max(length, 0)
        visible = 0..<self.length
    }

    /// `visible` of a sound `length` frames long, moved and cut to fit inside it. Nothing visible is the whole
    /// sound.
    public init(length: Int, visible: Range<Int>) {
        self.length = max(length, 0)
        let lower = min(max(visible.lowerBound, 0), self.length)
        let upper = min(max(visible.upperBound, lower), self.length)
        self.visible = lower < upper ? lower..<upper : 0..<self.length
    }

    /// How far from an edge of the selection, in points, a press still takes hold of it. The handles and the
    /// brackets are drawn this big, so that what can be grabbed is what is seen.
    public static let edgeReachPoints = 8.0
    /// How far a press may move, in points, and still be a click.
    public static let clickSlopPoints = 3.0

    private var narrowest: Int { min(Self.narrowestFrames, length) }

    public var isWhole: Bool { visible == 0..<length }
    public var canZoomIn: Bool { visible.count > narrowest }
    public var canZoomOut: Bool { !isWhole }

    // MARK: - Zooming and scrolling

    /// Shows half as much, keeping `frame` at the same place across the drawing, so that what is being looked at
    /// stays where the eye is.
    public mutating func zoomIn(around frame: Int) {
        guard length > 0 else { return }
        resize(to: max(narrowest, visible.count / 2), around: frame)
    }

    /// Shows twice as much, as far as the whole sound.
    public mutating func zoomOut(around frame: Int) {
        guard length > 0 else { return }
        resize(to: min(length, visible.count * 2), around: frame)
    }

    private mutating func resize(to count: Int, around frame: Int) {
        let anchor = min(max(frame, visible.lowerBound), visible.upperBound)
        let share = Double(anchor - visible.lowerBound) / Double(visible.count)
        move(toStart: anchor - Int((share * Double(count)).rounded()), count: count)
    }

    /// Moves the stretch to begin at `start` as far as the sound lets it, keeping how much is shown.
    public mutating func scroll(toStart start: Int) {
        move(toStart: start, count: visible.count)
    }

    private mutating func move(toStart start: Int, count: Int) {
        let first = min(max(start, 0), length - count)
        visible = first..<(first + count)
    }

    /// Where the stretch stands among the places it could stand, 0 at the start of the sound and 1 at the end.
    /// 0 when all of the sound is shown.
    public var scrollFraction: Double {
        let room = length - visible.count
        return room > 0 ? Double(visible.lowerBound) / Double(room) : 0
    }

    /// Moves the stretch to where `fraction` of the way along the places it could stand. Not a number moves
    /// nothing.
    public mutating func scroll(toFraction fraction: Double) {
        guard fraction.isFinite else { return }
        let room = length - visible.count
        scroll(toStart: Int((min(max(fraction, 0), 1) * Double(room)).rounded()))
    }

    /// Brings `frame` into view when it is not, by the least that puts it near the side it went out of: a tenth
    /// of the way in from the left for one ahead of the view, and a tenth from the right for one behind it, so
    /// that a playhead that walks off the right shows what is to come and not the edge. The end of what is shown
    /// is in view.
    public mutating func reveal(_ frame: Int) {
        guard length > 0 else { return }
        if frame < visible.lowerBound {
            scroll(toStart: frame - visible.count * 9 / 10)
        } else if frame > visible.upperBound {
            scroll(toStart: frame - visible.count / 10)
        }
    }

    /// How far an arrow key moves the playhead: a fiftieth of what is shown, so that the same press covers about
    /// the same stretch of the drawing at any zoom, and never less than a frame.
    public var stepFrames: Int { max(1, visible.count / 50) }

    // MARK: - Between a place on the drawing and a frame

    /// The frame nearest a place `x` points across a drawing `width` points wide, held to the sound. A drawing
    /// with no width has nothing to point at, and gives where the view begins.
    public func frame(atX x: Double, width: Double) -> Int {
        guard width > 0, x.isFinite else { return min(max(visible.lowerBound, 0), length) }
        let across = (x / width * Double(visible.count)).rounded()
        // Far enough outside the drawing to overflow is just outside it.
        let frame = Double(visible.lowerBound) + min(max(across, -1e15), 1e15)
        return Int(min(max(frame, 0), Double(length)))
    }

    /// How many frames `points` come to across a drawing `width` points wide, which is at least one, so that a
    /// reach that is drawn is always a reach that can be hit.
    public func frames(spanning points: Double, width: Double) -> Int {
        guard width > 0, points.isFinite else { return 1 }
        return max(1, Int(min((points * Double(visible.count) / width).rounded(.up), 1e15)))
    }

    /// How many points across a drawing `width` points wide `frame` is, which is outside it for a frame that is
    /// not in view.
    public func x(of frame: Int, width: Double) -> Double {
        guard !visible.isEmpty else { return 0 }
        return Double(frame - visible.lowerBound) / Double(visible.count) * width
    }

    // MARK: - A new sound

    /// The viewport for the same window once the sound is `newLength` frames long, as it is after a render. All of
    /// it shown stays all of it, and what was shown stays shown as far as the new sound has it: a stretch kept
    /// where it was, or pulled back from the end, or the whole when the sound is now shorter than the stretch.
    public func resized(toLength newLength: Int) -> WaveformViewport {
        let newLength = max(newLength, 0)
        guard newLength != length else { return self }
        if isWhole || visible.count > newLength { return WaveformViewport(length: newLength) }
        var moved = WaveformViewport(length: newLength)
        moved.visible = 0..<visible.count
        moved.scroll(toStart: visible.lowerBound)
        return moved
    }
}
