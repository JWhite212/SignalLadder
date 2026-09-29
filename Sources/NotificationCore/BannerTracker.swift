// Sources/NotificationCore/BannerTracker.swift
import Foundation

/// Decides which banners in an accessibility tree are new, so that each banner
/// is captured once however many events it produces.
///
/// Notification Centre does not always open a window for a new banner. One
/// that arrives while another is still on screen replaces it inside the same
/// window, and the only events that follow are `AXLayoutChanged` and the old
/// banner's `AXUIElementDestroyed` — no window is created or moved (measured
/// on macOS 26.7, 2026-09-29). So capture has to read on layout changes too.
/// Layout changes also fire, repeatedly, for a banner already read: 1.6 s and
/// 2.2 s after it appeared in one run, past `CaptureDeduplicator`'s 1.5 s
/// window. What tells the two apart is the element, not the text: the
/// replacement is a new element, and a banner already read is the same one.
///
/// A banner is new if its element has not been read before, or if a read finds
/// text in it that was not there before. A read that finds less — a child or
/// the description lost to a timeout, which each read of another process can
/// suffer — is not new, and does not replace what was remembered. A read that
/// finds more is captured again, since the fuller text may match a rule the
/// first read could not.
///
/// Apart from a small capacity backstop, an element is forgotten only once it
/// is known to be gone: a read that fails or times out proves nothing, and
/// forgetting on one would capture the same banner again at its next layout
/// change.
///
/// Holds hashes of each banner's text, never the text itself, and only while
/// the banner is on screen.
public final class BannerTracker {
    /// A banner read for the first time, or read again with new text.
    public struct Sighting: Equatable {
        public let rawText: String
        public let subrole: String
        public let textChildren: [String]
    }

    public struct Scan: Equatable {
        /// The banners to capture, in tree order.
        public let new: [Sighting]
        /// Banners found with neither a description nor any text children,
        /// by subrole. Not remembered, so a later read that finds their text
        /// still captures them.
        public let empty: [String]
    }

    private struct Seen {
        let node: AccessibilityNode
        /// One hash per piece of text read: the description, and each child.
        let parts: Set<Int>
        let order: Int
    }

    private let locator: BannerTreeLocator
    private let capacity: Int
    private var seen: [AnyHashable: Seen] = [:]
    private var sightings = 0

    /// - Parameter capacity: the most banners remembered at once. Only a
    ///   backstop — each is forgotten when it is destroyed — kept small
    ///   because checking whether one is gone is a call into another process.
    public init(locator: BannerTreeLocator = BannerTreeLocator(), capacity: Int = 16) {
        self.locator = locator
        self.capacity = capacity
    }

    /// The banners under `root` that have not been captured yet. `root` may be
    /// any part of the tree: banners outside it are neither read nor forgotten.
    public func scan(_ root: AccessibilityNode) -> Scan {
        seen = seen.filter { !$0.value.node.isGone }

        var new: [Sighting] = []
        var empty: [String] = []
        for banner in locator.locate(in: root) {
            let text = banner.attributedDescription ?? ""
            let children = BannerTextReader.textChildren(of: banner)
            guard !text.isEmpty || !children.isEmpty else {
                empty.append(banner.subrole ?? "?")
                continue
            }
            // Old notifications, shown because Notification Centre was opened.
            // Nothing arrived.
            if NotificationCentreHistory.isHistoryItem(description: text, textChildren: children) { continue }

            let parts = Self.parts(description: text, children: children)
            if let prior = seen[banner.identity], parts.isSubset(of: prior.parts) { continue }

            sightings += 1
            seen[banner.identity] = Seen(node: banner, parts: parts, order: sightings)
            new.append(Sighting(rawText: text, subrole: banner.subrole ?? "", textChildren: children))
        }

        if seen.count > capacity {
            let oldest = seen.sorted { $0.value.order < $1.value.order }.prefix(seen.count - capacity)
            for (identity, _) in oldest { seen[identity] = nil }
        }
        return Scan(new: new, empty: empty)
    }

    /// Tagged, so a description that reads the same as a child is still a
    /// different piece of text.
    private static func parts(description: String, children: [String]) -> Set<Int> {
        var parts: Set<Int> = []
        if !description.isEmpty { parts.insert(hash("description", description)) }
        for child in children { parts.insert(hash("child", child)) }
        return parts
    }

    private static func hash(_ kind: String, _ text: String) -> Int {
        var hasher = Hasher()
        hasher.combine(kind)
        hasher.combine(text)
        return hasher.finalize()
    }

    /// Forgets every banner, for when the process being watched has changed
    /// and none of its elements can be seen again.
    public func reset() {
        seen = [:]
    }
}
