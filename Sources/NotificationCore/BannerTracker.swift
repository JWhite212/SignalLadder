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
/// first read could not. Dedupe lets it reach the rules even when only a child
/// is new, and does not let it set off again a rule its first read set off
/// (`CaptureDeduplicator`).
///
/// What a read is compared with is the last capture of its element, and a
/// capture replaces it, so that a capture made of a partial read is followed by
/// one of the full read. Its text is first its text children, the fields it
/// shows. The description joins those fields with the app's name, and with
/// words that describe how it is shown rather than what it says: a stack of
/// persistent alerts ends its description with ", stacked", which goes when a
/// click expands the stack into its alerts and comes back when it collapses,
/// on the same elements, whose children do not change (measured on macOS 26.7,
/// 2026-10-02, with a test app's persistent alerts). Each click used to capture
/// the alerts in it again, at the time of the click. So a description is new
/// text when it is the first one, because it is where the app's name is, or
/// when it has a field the last capture's description did not and the read has
/// fewer children than the last capture or none: then the description is the
/// only place new text can show. A read with every child the last capture had
/// takes nothing new from its description.
///
/// Opening Notification Centre shows its history in a window banners also
/// use, and nothing about a row says whether it is new — rows under a minute
/// old carry no time label, and older rows' labels come and go between reads.
/// So the window is what decides. When it becomes the panel, everything in it
/// is history, remembered by element. A row that appears after that is
/// history if it ends with a time label (scrolled into view), or if it
/// replaces a captured element with the same text destroyed moments before —
/// a stack laid out again as new elements, which once replayed three alerts.
/// That evidence is used once and expires in `relayoutWindow`, so a genuine
/// repeat of an alert, its twin still on screen or long gone, is captured.
/// Anything else has arrived while the panel is open, and is captured once a
/// second read, spaced past a label's flicker, still finds no evidence. That
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
/// The element is not all that stays the same. On macOS 27.2 a notification
/// keeps its AXIdentifier, its UUID, when Notification Centre lays it out again
/// as a new element, which expanding a stack does to every row but the three
/// newest (#160). So each captured notification is also remembered by
/// identifier, with the last read of it, and a banner whose element is new but
/// whose notification was captured is compared with that read as an element is:
/// it is new only if it has text the capture did not. The identifiers outlive
/// their elements and a `reset()`, are held to `identifierCapacity`, and only a
/// UUID is trusted. A notification that was never captured is still captured
/// when its row is first laid out.
///
/// Holds hashes of text, never the text itself: of each banner's while it is
/// on screen, and for a moment after it goes.
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
        /// What its last capture read.
        let read: Read
        /// Its text children as one hash, for recognising it laid out again.
        let key: Int?
        let order: Int
    }

    /// What the last capture of a notification read, and when it was last seen.
    private struct Remembered {
        let read: Read
        let order: Int
    }

    /// A window showing Notification Centre's history, and what is known about
    /// its rows.
    private struct Panel {
        let window: AccessibilityNode
        /// What the panel held when it opened.
        var baseline: [AccessibilityNode] = []
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
    private let identifierCapacity: Int
    private var seen: [AnyHashable: Seen] = [:]
    private var sightings = 0
    /// Captured notifications by identifier, which outlive their elements.
    private var rememberedNotifications: [String: Remembered] = [:]
    private var rememberings = 0
    private var panels: [AnyHashable: Panel] = [:]
    /// Captured banners just destroyed: their text children's hash, and when.
    private var destroyed: [(key: Int, at: Date)] = []

    /// How recently a captured banner must have gone for a new row with the
    /// same text to count as it laid out again.
    public static let relayoutWindow: TimeInterval = 2

    /// How long a panel row with no evidence either way waits before a second
    /// read decides it.
    public static let secondReadGap: TimeInterval = 0.25

    /// - Parameter capacity: the most banners remembered at once. Only a
    ///   backstop — each is forgotten when it is destroyed — kept small
    ///   because checking whether one is gone is a call into another process.
    public init(locator: BannerTreeLocator = BannerTreeLocator(), capacity: Int = 16, identifierCapacity: Int = 512) {
        self.locator = locator
        self.capacity = capacity
        self.identifierCapacity = identifierCapacity
    }

    /// The banners in `window` that have not been captured yet. Pass a whole
    /// window: whether it is showing Notification Centre's history can only
    /// be told from the window. Banners in other windows are neither read nor
    /// forgotten.
    public func scan(_ window: AccessibilityNode, at now: Date = Date()) -> Scan {
        forgetWhatHasGone(at: now)
        let banners = locator.locate(in: window)
        if notePanel(window, holding: banners) {
            // It has just become the panel: everything in it is history.
            return Scan(new: [], empty: [], needsSecondRead: false)
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
            let read = Read(description: text, children: children)
            if let prior = seen[id], !read.isNew(over: prior.read) { continue }

            let key = Self.contentKey(children)
            let notification = Self.notificationID(of: banner)
            if seen[id] == nil, let notification, let known = rememberedNotifications[notification],
               !read.isNew(over: known.read) {
                // A notification already captured, laid out again as a new
                // element. Its element is remembered with what the capture read,
                // so that the next read of it is not asked about again.
                remember(notification, read: known.read)
                sightings += 1
                seen[id] = Seen(node: banner, read: known.read, key: key, order: sightings)
                continue
            }
            if inPanel {
                let laidOutAgain = key.flatMap { key in destroyed.firstIndex { $0.key == key } }
                if let laidOutAgain { destroyed.remove(at: laidOutAgain) }
                if laidOutAgain != nil
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
            seen[id] = Seen(node: banner, read: read, key: key, order: sightings)
            if let notification { remember(notification, read: read) }
            new.append(Sighting(rawText: text, subrole: banner.subrole ?? "", textChildren: children))
        }

        forgetTheOldestBeyondCapacity(keeping: banners)
        return Scan(new: new, empty: empty, needsSecondRead: needsSecondRead)
    }

    /// Whether `element` is a banner that no read has captured or set aside,
    /// so that a read now may be the only one to find it.
    ///
    /// A layout change names the element it is about, and the watcher asks this
    /// of it. Measured on macOS 27.2 on 2026-10-17 (#154), alerts from one app
    /// 0.05 s apart each replaced the last in about 60 ms, a new element each
    /// time, and the layout change naming the new one came 15 to 20 ms after it
    /// appeared. A read 50 ms after that found the next one, and half of a burst
    /// of 12 was never read. So the watcher reads at once when this is true.
    ///
    /// Only a banner's subrole counts, since the window, its wrappers and the
    /// banner's own text are named by layout changes too. A banner captured, a
    /// row the panel opened with, a row awaiting its second read and a row for a
    /// notification already captured, laid out again as a new element by
    /// expanding its stack (#160), are not unread, so the layout changes that
    /// come again for them cost no read. A banner read with no text is, since it
    /// is not remembered.
    public func isUnread(_ element: AccessibilityNode) -> Bool {
        guard BannerSubrole.isBanner(element.subrole) else { return false }
        let id = element.identity
        guard seen[id] == nil else { return false }
        guard !panels.values.contains(where: { $0.history.contains(id) || $0.awaiting[id] != nil }) else { return false }
        guard let notification = Self.notificationID(of: element) else { return true }
        return rememberedNotifications[notification] == nil
    }

    /// The identifier of `banner`'s notification, when it has one worth trusting:
    /// a UUID, in one case. Anything else, such as one string shared by every
    /// banner, would make a genuine repeat look like a row laid out again.
    private static func notificationID(of banner: AccessibilityNode) -> String? {
        banner.identifier.flatMap { UUID(uuidString: $0)?.uuidString }
    }

    /// Notes that `notification` was captured, or seen again, with `read`. Past
    /// `identifierCapacity` the least recently seen go first.
    private func remember(_ notification: String, read: Read) {
        rememberings += 1
        rememberedNotifications[notification] = Remembered(read: read, order: rememberings)
        let excess = rememberedNotifications.count - identifierCapacity
        guard excess > 0 else { return }
        for (identifier, _) in rememberedNotifications.sorted(by: { $0.value.order < $1.value.order }).prefix(excess) {
            rememberedNotifications[identifier] = nil
        }
    }

    /// Forgets the banners that have been destroyed, keeping the text of each
    /// for `relayoutWindow` in case it is laid out again, and the panels whose
    /// window has gone.
    private func forgetWhatHasGone(at now: Date) {
        let gone = seen.filter { $0.value.node.isGone }
        for (identity, entry) in gone {
            seen[identity] = nil
            if let key = entry.key { destroyed.append((key, now)) }
        }
        destroyed.removeAll { now.timeIntervalSince($0.at) > Self.relayoutWindow }
        panels = panels.filter { !$0.value.window.isGone }
    }

    /// Keeps track of whether `window` is showing Notification Centre's list,
    /// and returns true when it has just become it, which the read that found
    /// it then reports nothing from.
    private func notePanel(_ window: AccessibilityNode, holding banners: [AccessibilityNode]) -> Bool {
        if NotificationCentreHistory.isPanel(window) {
            // Closed and opened again with only one read between: if every row
            // it opened with has gone, this is a new opening, not the old one.
            // A panel that opened empty has no row to have gone, so one miss,
            // which a timed-out read also gives, proves nothing about it: taking
            // it for a new opening made the next arrival history, never captured.
            if let panel = panels[window.identity], panel.misses > 0, !panel.baseline.isEmpty,
               panel.baseline.allSatisfy({ seen[$0.identity] != nil || $0.isGone }) {
                panels[window.identity] = nil
            }
            if panels[window.identity] == nil {
                // It has just become the panel. Everything in it is history,
                // including rows whose text has not loaded yet — except what
                // was already captured, which needs no remembering here.
                panels[window.identity] = Panel(window: window, baseline: banners,
                                                history: Set(banners.map(\.identity)))
                return true
            }
            panels[window.identity]?.misses = 0
        } else if panels[window.identity] != nil {
            panels[window.identity]?.misses += 1
            if panels[window.identity]!.misses >= 2 { panels[window.identity] = nil }
        }
        return false
    }

    /// Holds the banners remembered to `capacity`, forgetting the oldest first,
    /// and never one of `banners`, which are on screen now: forgetting one
    /// would capture it again at the next read, as an open panel full of
    /// arrivals would show.
    private func forgetTheOldestBeyondCapacity(keeping banners: [AccessibilityNode]) {
        guard seen.count > capacity else { return }
        let onScreen = Set(banners.map(\.identity))
        let oldest = seen.filter { !onScreen.contains($0.key) }
            .sorted { $0.value.order < $1.value.order }.prefix(max(0, seen.count - capacity))
        for (identity, _) in oldest { seen[identity] = nil }
    }

    /// A banner's text children, less a trailing time label, as one hash;
    /// nil with none, which identifies nothing.
    private static func contentKey(_ children: [String]) -> Int? {
        var shown = children
        if shown.count >= 2, let last = shown.last, NotificationCentreHistory.isRelativeTime(last) {
            shown.removeLast()
        }
        guard !shown.isEmpty else { return nil }
        var hasher = Hasher()
        hasher.combine(shown)
        return hasher.finalize()
    }

    /// What one read of a banner found, as hashes.
    private struct Read {
        let children: Set<Int>
        /// One per field of the description, or nil with no description.
        let fields: Set<Int>?

        init(description: String, children: [String]) {
            self.children = Set(children.map(BannerTracker.hash))
            self.fields = description.isEmpty
                ? nil : Set(NotificationCentreHistory.fields(of: description).map(BannerTracker.hash))
        }

        /// Whether it found text that `last`, its element's last capture, did
        /// not. See the type's comment.
        func isNew(over last: Read) -> Bool {
            if !children.isSubset(of: last.children) { return true }
            guard let fields else { return false }
            guard let known = last.fields else { return true }
            if children == last.children, !children.isEmpty { return false }
            return !fields.isSubset(of: known)
        }
    }

    private static func hash(_ text: String) -> Int {
        var hasher = Hasher()
        hasher.combine(text)
        return hasher.finalize()
    }

    /// Forgets every banner, for when the process being watched has changed
    /// and none of its elements can be seen again. The notifications captured
    /// are kept: they are the same notifications, and a restarted Notification
    /// Centre lays its persistent alerts out again as new elements.
    public func reset() {
        seen = [:]
        panels = [:]
        destroyed = []
    }
}
