import Foundation

/// Collapses the repeated callbacks a single banner produces.
///
/// macOS fires kAXWindowMoved several times as a banner animates, so some
/// collapsing is required or one notification looks like many. Keying on
/// content within a time window cannot distinguish that from two genuinely
/// distinct notifications carrying identical text, so callers are expected to
/// SURFACE suppressions rather than drop them silently — see `Decision`.
///
/// Keying on element identity would remove the ambiguity entirely and is the
/// intended replacement; this type exists so that change lands in one place.
public final class CaptureDeduplicator {
    public struct Decision: Equatable {
        /// True when this was already seen inside the window.
        public let isRepeat: Bool
        /// How many repeats have been seen since the first sighting. 0 on first.
        public let repeatCount: Int
    }

    private var seen: [String: (first: Date, repeats: Int)] = [:]
    private let window: TimeInterval

    public init(window: TimeInterval = 1.5) {
        self.window = window
    }

    /// The window is anchored to FIRST sighting and deliberately not refreshed
    /// on a hit. A sliding window would let a source repeating faster than the
    /// interval suppress indefinitely, reintroducing the silent loss this
    /// exists to prevent. The cost is a duplicate once the window lapses:
    /// false positives, never omissions.
    public func admit(_ key: String, at now: Date) -> Decision {
        seen = seen.filter { now.timeIntervalSince($0.value.first) < window }

        if var entry = seen[key] {
            entry.repeats += 1
            seen[key] = entry
            return Decision(isRepeat: true, repeatCount: entry.repeats)
        }

        seen[key] = (first: now, repeats: 0)
        return Decision(isRepeat: false, repeatCount: 0)
    }
}
