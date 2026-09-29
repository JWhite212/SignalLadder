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
/// use, and nothing about a row says whether it is new — rows under a minute
/// old carry no time label, and older rows' labels come and go between reads.
/// So the window is what decides. When it becomes the panel, everything in it
/// is history, remembered by element. A row that appears after that is
/// history if its text was captured before (a stack laid out again as new
/// elements) or it ends with a time label (scrolled into view); anything else
/// has arrived while the panel is open, and is captured once a second read,
/// spaced past a label's flicker, still finds no evidence otherwise. That
/// errs towards capturing: a replay is the lesser error.
///
/// Outside the panel nothing is ever set aside: history appears only there,
/// and a live calendar reminder can end with something that looks like a time.
///
/// Apart from a small capacity backstop, an element is forgotten only once it
/// is known to be gone: a read that fails or times out proves nothing, and
/// forgetting on one would capture the same banner again at its next layout
/// change.
///
/// Holds hashes of text, never the text itself: of each banner's while it is
/// on screen, and of the last few hundred captured, for recognising history.
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
        /// Whether a row is waiting on a second read; the caller should read
        /// the window again shortly, or it may never be decided.
        public let needsSecondRead: Bool
    }

    private struct Seen {
        let node: AccessibilityNode
        /// One hash per piece of text read: the description, and each child.
        let parts: Set<Int>
        let order: Int
    }

    /// A window showing Notification Centre's history, and what is known about
    /// its rows.
    private struct Panel {
        let window: AccessibilityNode
        /// Rows judged history, by element, so a label that goes missing on a
        /// later read does not reopen the question.
        var history: Set<AnyHashable> = []
        /// Rows read with no evidence either way, and when first read. A label
        /// was measured missing for about 220 ms, so the second read that
        /// decides must come at least `secondReadGap` after the first.
        var awaiting: [AnyHashable: Date] = [:]
        /// Consecutive reads that did not find the panel. One proves nothing —
        /// a timed-out read of focus or of the menu button looks the same.
        var misses = 0
    }

    private let locator: BannerTreeLocator
    private let capacity: Int
    private var seen: [AnyHashable: Seen] = [:]
    private var sightings = 0
    private var panels: [AnyHashable: Panel] = [:]
    /// What was captured recently, as hashes of text children, oldest first.
    private var captured: [Int] = []
    private var capturedSet: Set<Int> = []
    private static let capturedMemory = 256

    /// How long a panel row with no evidence either way waits before a second
    /// read decides it.
    public static let secondReadGap: TimeInterval = 0.25

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
    public func scan(_ window: AccessibilityNode, at now: Date = Date()) -> Scan {
        seen = seen.filter { !$0.value.node.isGone }
        panels = panels.filter { !$0.value.window.isGone }

        let banners = locator.locate(in: window)
        if NotificationCentreHistory.isPanel(window) {
            if panels[window.identity] == nil {
                // It has just become the panel. Everything in it is history,
                // including rows whose text has not loaded yet — except what
                // was already captured, which needs no remembering here.
                panels[window.identity] = Panel(window: window, history: Set(banners.map(\.identity)))
                return Scan(new: [], empty: [], needsSecondRead: false)
            }
            panels[window.identity]?.misses = 0
        } else if panels[window.identity] != nil {
            panels[window.identity]?.misses += 1
            if panels[window.identity]!.misses >= 2 { panels[window.identity] = nil }
        }
        let inPanel = panels[window.identity] != nil

        var new: [Sighting] = []
        var empty: [String] = []
        var needsSecondRead = false
        for banner in banners {
            let id = banner.identity
            if panels[window.identity]?.history.contains(id) == true { continue }

            let text = banner.attributedDescription ?? ""
            let children = BannerTextReader.textChildren(of: banner)
            guard !text.isEmpty || !children.isEmpty else {
                empty.append(banner.subrole ?? "?")
                continue
            }
            let parts = Self.parts(description: text, children: children)
            if let prior = seen[id], parts.isSubset(of: prior.parts) { continue }

            if inPanel {
                if capturedSet.contains(Self.contentKey(children))
                    || NotificationCentreHistory.isHistoryItem(description: text, textChildren: children) {
                    panels[window.identity]?.history.insert(id)
                    panels[window.identity]?.awaiting[id] = nil
                    continue
                }
                let firstRead = panels[window.identity]?.awaiting[id] ?? now
                if now.timeIntervalSince(firstRead) < Self.secondReadGap {
                    panels[window.identity]?.awaiting[id] = firstRead
                    needsSecondRead = true
                    continue
                }
                panels[window.identity]?.awaiting[id] = nil
            }

            sightings += 1
            seen[id] = Seen(node: banner, parts: parts, order: sightings)
            remember(Self.contentKey(children))
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
        return Scan(new: new, empty: empty, needsSecondRead: needsSecondRead)
    }

    private func remember(_ key: Int) {
        guard capturedSet.insert(key).inserted else { return }
        captured.append(key)
        if captured.count > Self.capturedMemory {
            capturedSet.remove(captured.removeFirst())
        }
    }

    /// A notification's text children, less a trailing time label, so that
    /// its row in Notification Centre's history matches the banner captured
    /// when it arrived.
    private static func contentKey(_ children: [String]) -> Int {
        var shown = children
        if shown.count >= 2, let last = shown.last, NotificationCentreHistory.isRelativeTime(last) {
            shown.removeLast()
        }
        var hasher = Hasher()
        hasher.combine(shown)
        return hasher.finalize()
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
        captured = []
        capturedSet = []
    }
}
