// Sources/NotificationCore/UnreadBanners.swift
import Foundation

/// When banners were found that never had readable text, so that health can say how
/// many fell in the last half hour (1.1 plan, Ruling 17). A banner with no text could
/// match no rule, and the self-test, which reads only SignalLadder's own banner, would
/// go on reading verified. It keeps times and nothing else: no identity, no subrole,
/// no text.
public struct UnreadBanners: Equatable, Sendable {
    /// How far back a count reaches.
    public static let window: TimeInterval = 30 * 60
    /// At most this many times are kept, the newest. More than this in half an hour
    /// says the same thing as this many.
    public static let capacity = 64

    private var times: [Date] = []

    public init() {}

    /// `count` banners were found unread at `time`.
    public mutating func record(_ count: Int, at time: Date) {
        guard count > 0 else { return }
        times.append(contentsOf: repeatElement(time, count: count))
        if times.count > Self.capacity { times.removeFirst(times.count - Self.capacity) }
    }

    /// How many were recorded in the `window` before `now`.
    public func count(at now: Date) -> Int {
        times.filter { now.timeIntervalSince($0) < Self.window && $0 <= now }.count
    }
}
