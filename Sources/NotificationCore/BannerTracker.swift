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
/// Opening Notification Centre shows its history in a window banners also
/// use. When a window becomes that panel, everything in it at that moment is
/// history: remembered by element, never captured, however its time label
/// comes and goes. Anything that appears in the panel after that has arrived
/// while it is open, and is captured — unless it carries a time label, which
/// an arrival never does. The rule errs towards capturing: a row that appears
/// later without its label yet (scrolled into view, say) is captured, which
/// repeats history, where the other error would miss an alert. What arrives at
/// the very moment the panel opens is taken for history.
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

    /// A window showing Notification Centre's history, and the banners in it
    /// that are history.
    private struct Panel {
        let window: AccessibilityNode
        var history: Set<AnyHashable>
        /// Consecutive reads that did not find the panel. One proves nothing —
        /// a timed-out read of focus or of the menu button looks the same — and
        /// dropping the record on it would take the next arrival for history.
        var misses = 0
    }

    private let locator: BannerTreeLocator
    private let capacity: Int
    private var seen: [AnyHashable: Seen] = [:]
    private var sightings = 0
    private var panels: [AnyHashable: Panel] = [:]
    /// History recognised by its time label in a window not known to be the
    /// panel — the fallback. Remembered, so a label that goes missing on a
    /// later read does not make it look new.
    private var labelledHistory: [AnyHashable: (node: AccessibilityNode, order: Int)] = [:]

    /// - Parameter capacity: the most banners remembered at once. Only a
    ///   backstop — each is forgotten when it is destroyed — kept small
    ///   because checking whether one is gone is a call into another process.
    public init(locator: BannerTreeLocator = BannerTreeLocator(), capacity: Int = 16) {
        self.locator = locator
        self.capacity = capacity
    }

    /// The banners in `window` that have not been captured yet. Pass a whole
    /// window: whether it is showing Notification Centre's history can only
    /// be told from the window. Banners in other windows are neither read nor
    /// forgotten.
    public func scan(_ window: AccessibilityNode) -> Scan {
        seen = seen.filter { !$0.value.node.isGone }
        panels = panels.filter { !$0.value.window.isGone }
        labelledHistory = labelledHistory.filter { !$0.value.node.isGone }

        let banners = locator.locate(in: window)
        let showsPanel = NotificationCentreHistory.isPanel(window)
        if showsPanel, panels[window.identity] == nil {
            // It has just become the panel. Everything in it is history,
            // including banners whose text has not loaded yet.
            panels[window.identity] = Panel(window: window, history: Set(banners.map(\.identity)))
            return Scan(new: [], empty: [])
        }
        if showsPanel {
            panels[window.identity]?.misses = 0
        } else if panels[window.identity] != nil {
            panels[window.identity]?.misses += 1
            if panels[window.identity]!.misses >= 2 { panels[window.identity] = nil }
        }
        let inPanel = panels[window.identity] != nil

        var new: [Sighting] = []
        var empty: [String] = []
        for banner in banners {
            if panels[window.identity]?.history.contains(banner.identity) == true
                || labelledHistory[banner.identity] != nil { continue }

            let text = banner.attributedDescription ?? ""
            let children = BannerTextReader.textChildren(of: banner)
            guard !text.isEmpty || !children.isEmpty else {
                empty.append(banner.subrole ?? "?")
                continue
            }
            if NotificationCentreHistory.isHistoryItem(description: text, textChildren: children) {
                if inPanel {
                    panels[window.identity]?.history.insert(banner.identity)
                } else {
                    sightings += 1
                    labelledHistory[banner.identity] = (banner, sightings)
                }
                continue
            }

            let parts = Self.parts(description: text, children: children)
            if let prior = seen[banner.identity], parts.isSubset(of: prior.parts) { continue }

            sightings += 1
            seen[banner.identity] = Seen(node: banner, parts: parts, order: sightings)
            new.append(Sighting(rawText: text, subrole: banner.subrole ?? "", textChildren: children))
        }

        if seen.count > capacity {
            // Never what is on screen now: forgetting it would capture it again
            // at the next read, as an open panel full of arrivals would show.
            let onScreen = Set(banners.map(\.identity))
            let oldest = seen.filter { !onScreen.contains($0.key) }
                .sorted { $0.value.order < $1.value.order }.prefix(max(0, seen.count - capacity))
            for (identity, _) in oldest { seen[identity] = nil }
        }
        if labelledHistory.count > capacity * 4 {
            let oldest = labelledHistory.sorted { $0.value.order < $1.value.order }
                .prefix(labelledHistory.count - capacity * 4)
            for (identity, _) in oldest { labelledHistory[identity] = nil }
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
        panels = [:]
        labelledHistory = [:]
    }
}
