import Foundation

/// Collapses the repeated callbacks a single banner produces.
///
/// macOS fires kAXWindowMoved several times as a banner animates, so some
/// collapsing is required or one notification looks like many. Keying on
/// content within a time window cannot distinguish that from two genuinely
/// distinct notifications carrying identical text, so callers are expected to
/// SURFACE suppressions rather than drop them silently — see `Decision`.
///
/// Element identity now does most of this upstream: `BannerTracker` lets each
/// banner element through once, however many events it fires. What still
/// reaches here is a new element carrying text just seen — two notifications
/// with identical text, or a banner macOS rebuilt as a new element — and this
/// is where that is judged and counted.
///
/// The text compared is all a capture holds: its description and its text
/// children. The tracker also lets a banner through again when a read finds
/// text the last one did not, and such a read can keep the description and
/// gain only a child, because a read of another process can lose a child or
/// the description to a timeout. Keyed on the description alone, that fuller
/// read was a repeat, and never reached the rule it might match.
///
/// A read that is not a repeat but holds all of an earlier read's text, or all
/// of whose text an earlier read held, is taken for another read of the same
/// banner, and is told what that banner has already set off (`Decision.setOff`),
/// so that one banner never sets one rule off twice. Text tells reads of one
/// banner apart from a new notification, where the element cannot: a follow-up
/// from the same sender can arrive in the same element, the title kept and the
/// body replaced (M6 plan, Ruling 13), and neither of those reads holds the
/// other's text.
public final class CaptureDeduplicator {
    public struct Decision: Equatable {
        /// True when this was already seen inside the window.
        public let isRepeat: Bool
        /// How many repeats have been seen since the first sighting. 0 on first.
        public let repeatCount: Int
        /// The banner this capture was read from, as far as its text can tell,
        /// for `noteSetOff`: an earlier one's inside the window, or a new one.
        /// A number, and nothing a notification said. nil for a repeat, which
        /// reaches no rule.
        public let banner: Int?
        /// The rules, by id, that earlier reads of the same banner set off
        /// inside the window. Empty for a new banner and for a repeat.
        public let setOff: Set<UUID>
    }

    /// One capture's text: its description, and its text children in order.
    private struct Text: Hashable {
        let description: String
        let children: [String]
    }

    /// Reads taken for one banner, and the rules they set off.
    private struct Banner {
        let id: Int
        let first: Date
        /// Each read's words: the description's fields and the children.
        var reads: [Set<String>]
        var setOff: Set<UUID> = []
    }

    private var seen: [Text: (first: Date, repeats: Int)] = [:]
    private var banners: [Banner] = []
    private var lastBannerID = 0
    private let window: TimeInterval

    public init(window: TimeInterval = 1.5) {
        self.window = window
    }

    /// The window is anchored to FIRST sighting and deliberately not refreshed
    /// on a hit. A sliding window would let a source repeating faster than the
    /// interval suppress indefinitely, reintroducing the silent loss this
    /// exists to prevent. The cost is a duplicate once the window lapses:
    /// false positives, never omissions.
    ///
    /// A banner's window is anchored the same way, to its first read: later
    /// reads of it never lengthen it, so a banner read again and again cannot
    /// hold a rule back for ever. A read after it is a new banner, and may set a
    /// rule off again.
    public func admit(_ description: String, textChildren: [String] = [], at now: Date) -> Decision {
        seen = seen.filter { now.timeIntervalSince($0.value.first) < window }
        banners.removeAll { now.timeIntervalSince($0.first) >= window }

        let text = Text(description: description, children: textChildren)
        if var entry = seen[text] {
            entry.repeats += 1
            seen[text] = entry
            return Decision(isRepeat: true, repeatCount: entry.repeats, banner: nil, setOff: [])
        }
        seen[text] = (first: now, repeats: 0)

        let words = Self.words(of: text)
        if !words.isEmpty,
           let index = banners.lastIndex(where: { $0.reads.contains { words.isSubset(of: $0) || $0.isSubset(of: words) } }) {
            banners[index].reads.append(words)
            return Decision(isRepeat: false, repeatCount: 0, banner: banners[index].id, setOff: banners[index].setOff)
        }
        lastBannerID += 1
        banners.append(Banner(id: lastBannerID, first: now, reads: [words]))
        return Decision(isRepeat: false, repeatCount: 0, banner: lastBannerID, setOff: [])
    }

    /// Records that a read of `banner` set off `rule`, so that a later read of
    /// it inside the window is told so. Does nothing once the banner is
    /// forgotten.
    public func noteSetOff(_ rule: UUID, banner: Int) {
        guard let index = banners.firstIndex(where: { $0.id == banner }) else { return }
        banners[index].setOff.insert(rule)
    }

    /// A read's words: each field of its description, which joins the app's
    /// name and the fields with commas, and each text child. A field with a
    /// comma in it is split in the description and whole in its child, and
    /// both are kept, so that a read with only one of them is still held by a
    /// read with both.
    private static func words(of text: Text) -> Set<String> {
        let children = text.children.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return Set(NotificationCentreHistory.fields(of: text.description)).union(children)
    }
}
