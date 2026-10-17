import XCTest
@testable import NotificationCore

/// A notification keeps its AXIdentifier when Notification Centre lays it out
/// again as a new element (#160). Measured on macOS 27.2 on 2026-10-17, with
/// persistent alerts from one app: expanding a stack of 36 gave 36 rows, of
/// which 33 were new elements and all 36 had the identifier they had before,
/// in the same order. The three newest rows were the elements the app had
/// captured. The stack's identifier is its newest alert's, and collapsing it
/// brought back the same element. Keyed on the element alone, each expansion
/// captured every older row again.
///
/// `BannerTracker` also remembers each captured notification by identifier, and
/// the last read of it, so a row laid out again with nothing new in it is not
/// captured, and one with new text still is. Fixtures are invented text (§10.1).
final class NotificationIdentifierTests: XCTestCase {
    /// `FakeNode` has no identifier, so these tests carry their own node.
    private final class Node: AccessibilityNode {
        let role: String?
        let subrole: String?
        let attributedDescription: String?
        let value: String?
        let identifier: String?
        private let kids: [Node]
        private let element: AnyHashable?

        var children: [AccessibilityNode] { kids }
        /// Unique to this node unless an `element` was given, so that two nodes
        /// built with the same `element` stand for two reads of one live element.
        var identity: AnyHashable { element ?? AnyHashable(ObjectIdentifier(self)) }
        var isGone = false
        var isFocused: Bool

        init(role: String? = nil, subrole: String? = nil, description: String? = nil, value: String? = nil,
             element: AnyHashable? = nil, identifier: String? = nil, focused: Bool = false, children: [Node] = []) {
            self.role = role
            self.subrole = subrole
            self.attributedDescription = description
            self.value = value
            self.element = element
            self.identifier = identifier
            self.isFocused = focused
            self.kids = children
        }
    }

    /// The identifier of the nth notification, in the shape macOS 27.2 gives.
    private func uuid(_ n: Int) -> String {
        String(format: "%08X-1F2E-4D3C-8B4A-0123456789AB", n)
    }

    /// An alert as macOS 27.2 draws one: the app, title and body joined in the
    /// description, and the title and body again as text children. A stack
    /// carries its newest alert's text and ends its description ", stacked".
    private func alert(_ element: String, _ n: Int?, _ title: String, body: String = "Body",
                       subrole: String = "AXNotificationCenterAlert", stacked: Bool = false) -> Node {
        Node(subrole: subrole,
             description: "Script Editor, \(title), \(body)" + (stacked ? ", stacked" : ""),
             element: element, identifier: n.map(uuid),
             children: [Node(value: title), Node(value: body)])
    }

    private func window(_ banners: Node...) -> Node {
        Node(subrole: "AXSystemDialog", children: [
            Node(subrole: "AXHostingView", children: [Node(children: [Node(children: banners)])])
        ])
    }

    private func titles(_ scan: BannerTracker.Scan) -> [String] {
        scan.new.compactMap(\.textChildren.first)
    }

    // MARK: - A row laid out again

    func testARowLaidOutAgainAsANewElementIsNotCapturedAgain() {
        let tracker = BannerTracker()
        XCTAssertEqual(tracker.scan(window(alert("first", 1, "Disk full"))).new.count, 1)
        let again = alert("second", 1, "Disk full")
        XCTAssertEqual(tracker.scan(window(again)).new, [])
        XCTAssertEqual(tracker.scan(window(again)).new, [], "and not at its next read either")
    }

    /// The measured expansion: five alerts arrive one after another, each the
    /// stack's newest and a new element. The oldest two elements go; the three
    /// newest are kept, and the stack's own element is its newest row, whose
    /// subrole changes. Expanded, then collapsed, then expanded again, the older
    /// rows are new elements each time, with the identifiers they had.
    func testExpandingAStackCapturesNoRowItHasCaptured() {
        let tracker = BannerTracker()
        var stacks: [Node] = []
        for n in 1...5 {
            stacks.append(alert("stack\(n)", n, "Alert \(n)", subrole: "AXNotificationCenterAlertStack", stacked: n > 1))
            if n > 3 { stacks[n - 4].isGone = true }
            XCTAssertEqual(tracker.scan(window(stacks[n - 1])).new.count, 1, "alert \(n) is captured as it arrives")
        }

        func expanded() -> [Node] {
            [alert("row1-\(UUID())", 1, "Alert 1"), alert("row2-\(UUID())", 2, "Alert 2"),
             alert("stack3", 3, "Alert 3"), alert("stack4", 4, "Alert 4"), alert("stack5", 5, "Alert 5")]
        }
        let first = expanded()
        XCTAssertEqual(titles(tracker.scan(window(first[0], first[1], first[2], first[3], first[4]))), [],
                       "the first expansion captures nothing it has captured")

        _ = tracker.scan(window(stacks[4]))
        first[0].isGone = true
        first[1].isGone = true
        let second = expanded()
        XCTAssertEqual(titles(tracker.scan(window(second[0], second[1], second[2], second[3], second[4]))), [],
                       "nor does the second")
    }

    /// A notification the app never captured, one lost in a burst, is still
    /// captured when its row is first laid out, and once.
    func testARowItNeverCapturedIsCapturedOnce() {
        let tracker = BannerTracker()
        XCTAssertEqual(tracker.scan(window(alert("stack", 5, "Heard", subrole: "AXNotificationCenterAlertStack"))).new.count, 1)
        let lost = alert("lost-row", 3, "Lost in a burst")
        let heard = alert("heard-row", 5, "Heard")
        XCTAssertEqual(titles(tracker.scan(window(lost, heard))), ["Lost in a burst"])
        lost.isGone = true
        let lostAgain = alert("lost-row-again", 3, "Lost in a burst")
        XCTAssertEqual(tracker.scan(window(lostAgain, heard)).new, [])
    }

    // MARK: - What still counts as new

    func testARowLaidOutAgainWithNewTextIsCaptured() {
        let tracker = BannerTracker()
        _ = tracker.scan(window(alert("one", 1, "Deploy", body: "Started")))
        let updated = alert("two", 1, "Deploy", body: "Failed")
        XCTAssertEqual(tracker.scan(window(updated)).new.map(\.textChildren), [["Deploy", "Failed"]])
    }

    /// Every read of another process can time out, and a timed-out child is
    /// simply missing from that read. Less text is not new, and does not replace
    /// what was remembered, or the full read after it would look new.
    func testARowLaidOutAgainThatLostAChildIsNotCapturedAndTheFullReadAfterItIsNot() {
        let tracker = BannerTracker()
        _ = tracker.scan(window(alert("one", 1, "Deploy")))
        let degraded = Node(subrole: "AXNotificationCenterAlert", description: "Script Editor, Deploy, Body",
                            element: "two", identifier: uuid(1), children: [Node(value: "Deploy")])
        XCTAssertEqual(tracker.scan(window(degraded)).new, [])
        XCTAssertEqual(tracker.scan(window(alert("three", 1, "Deploy"))).new, [])
    }

    /// The same text arriving again is a new notification, a repeated "Build
    /// failed", and has an identifier of its own.
    func testTheSameTextUnderAnotherIdentifierIsCaptured() {
        let tracker = BannerTracker()
        _ = tracker.scan(window(alert("first", 1, "Build failed")))
        XCTAssertEqual(tracker.scan(window(alert("repeat", 2, "Build failed"))).new.count, 1)
    }

    func testWithoutAnIdentifierAReplacementIsStillCapturedWhateverItsText() {
        let tracker = BannerTracker()
        _ = tracker.scan(window(alert("first", nil, "Build failed")))
        XCTAssertEqual(tracker.scan(window(alert("second", nil, "Build failed"))).new.count, 1)
    }

    /// Only the shape of a UUID is trusted. An identifier shared by several
    /// notifications would otherwise make a genuine repeat look like a row laid
    /// out again, and a missed page is the worse error.
    func testAnIdentifierThatIsNotAUUIDIsNotTrusted() {
        let tracker = BannerTracker()
        func same(_ element: String) -> Node {
            Node(subrole: "AXNotificationCenterBanner", description: "App, Build failed, Body", element: element,
                 identifier: "banner", children: [Node(value: "Build failed"), Node(value: "Body")])
        }
        XCTAssertEqual(tracker.scan(window(same("first"))).new.count, 1)
        XCTAssertEqual(tracker.scan(window(same("second"))).new.count, 1)
    }

    func testAnIdentifierIsTheSameNotificationInEitherCase() {
        let tracker = BannerTracker()
        _ = tracker.scan(window(alert("first", 1, "Disk full")))
        let lower = Node(subrole: "AXNotificationCenterAlert", description: "Script Editor, Disk full, Body",
                         element: "second", identifier: uuid(1).lowercased(),
                         children: [Node(value: "Disk full"), Node(value: "Body")])
        XCTAssertEqual(tracker.scan(window(lower)).new, [])
    }

    // MARK: - How long it is remembered

    /// The element is forgotten once it is destroyed, which is when the row is
    /// laid out again. The notification is not.
    func testTheIdentifierOutlivesItsElement() {
        let tracker = BannerTracker()
        let first = alert("first", 1, "Disk full")
        _ = tracker.scan(window(first))
        first.isGone = true
        _ = tracker.scan(window())
        XCTAssertEqual(tracker.scan(window(alert("second", 1, "Disk full"))).new, [])
    }

    /// A notification does not stop having been captured because Notification
    /// Centre restarted, and its persistent alerts are laid out again as new
    /// elements when it does.
    func testTheIdentifierOutlivesAReset() {
        let tracker = BannerTracker()
        _ = tracker.scan(window(alert("first", 1, "Disk full")))
        tracker.reset()
        XCTAssertEqual(tracker.scan(window(alert("second", 1, "Disk full"))).new, [])
    }

    /// The least recently seen identifier goes first, and a notification seen
    /// again, laid out again as a new element, counts as seen.
    func testOnlyTheLeastRecentlySeenIdentifiersAreForgottenBeyondCapacity() {
        let tracker = BannerTracker(identifierCapacity: 2)
        _ = tracker.scan(window(alert("a", 1, "One")))
        _ = tracker.scan(window(alert("b", 2, "Two")))
        XCTAssertEqual(tracker.scan(window(alert("a-again", 1, "One"))).new, [], "seen again")
        _ = tracker.scan(window(alert("c", 3, "Three")))
        XCTAssertEqual(tracker.scan(window(alert("a-third", 1, "One"))).new, [], "still remembered")
        XCTAssertEqual(tracker.scan(window(alert("b-again", 2, "Two"))).new.count, 1, "forgotten, so captured")
    }

    // MARK: - The read at once

    /// The watcher reads at once when a layout change names a banner no read has
    /// taken (#154, `isUnread`). Expanding a stack makes a layout change for
    /// every row it lays out again, and a row for a notification already captured
    /// has nothing to find.
    func testALayoutChangeNamingARowForACapturedNotificationAsksForNoRead() {
        let tracker = BannerTracker()
        _ = tracker.scan(window(alert("first", 1, "Disk full")))
        XCTAssertFalse(tracker.isUnread(alert("second", 1, "Disk full")))
    }

    func testALayoutChangeNamingARowThatNothingHasCapturedStillAsksForARead() {
        let tracker = BannerTracker()
        _ = tracker.scan(window(alert("first", 1, "Disk full")))
        XCTAssertTrue(tracker.isUnread(alert("second", 2, "Lost in a burst")), "another notification")
        XCTAssertTrue(tracker.isUnread(alert("third", nil, "No identifier")), "no identifier to go by")
        XCTAssertTrue(tracker.isUnread(Node(subrole: "AXNotificationCenterAlert", element: "fourth", identifier: "banner")),
                      "an identifier that is not a UUID")
    }

    // MARK: - Inside Notification Centre's list

    /// The window as measured: the list inside a scroll area, and, only while it
    /// is showing the panel, focus and the panel's own menu button.
    private func panelWindow(_ id: String, _ items: Node...) -> Node {
        Node(subrole: "AXSystemDialog", element: id, focused: true, children: [
            Node(subrole: "AXHostingView", children: [Node(children: [
                Node(role: "AXScrollArea", children: [Node(children: items), Node(role: "AXMenuButton")])
            ])])
        ])
    }

    private func at(_ seconds: TimeInterval) -> Date { Date(timeIntervalSinceReferenceDate: 1_000_000 + seconds) }
    private let later = BannerTracker.secondReadGap + 0.05

    /// An alert is heard, and long after, the panel is opened and its stack
    /// expanded. Its row is a new element with no time label, which looks like an
    /// arrival, and no twin was destroyed in the last two seconds to say it is
    /// the stack laid out again.
    func testAnExpandedRowInThePanelForAnAlertAlreadyHeardIsNotCaptured() {
        let tracker = BannerTracker()
        let live = alert("live", 1, "Heard on screen", subrole: "AXNotificationCenterAlertStack")
        XCTAssertEqual(tracker.scan(window(live), at: at(0)).new.count, 1)
        live.isGone = true
        _ = tracker.scan(window(), at: at(1))
        _ = tracker.scan(panelWindow("w"), at: at(10))

        let row = alert("row", 1, "Heard on screen")
        XCTAssertEqual(tracker.scan(panelWindow("w", row), at: at(11)).new, [])
        XCTAssertEqual(tracker.scan(panelWindow("w", row), at: at(11 + later)).new, [])
    }

    /// Whereas a row it never captured is, as before, taken for an arrival once
    /// a second read, past the time label's flicker, still finds no sign of age.
    func testAnExpandedRowInThePanelForAnAlertNeverHeardIsStillCaptured() {
        let tracker = BannerTracker()
        _ = tracker.scan(panelWindow("w"), at: at(0))
        let row = alert("row", 7, "Lost in a burst")
        XCTAssertEqual(tracker.scan(panelWindow("w", row), at: at(1)).new, [])
        XCTAssertEqual(titles(tracker.scan(panelWindow("w", row), at: at(1 + later))), ["Lost in a burst"])
        let again = alert("row-again", 7, "Lost in a burst")
        XCTAssertEqual(tracker.scan(panelWindow("w", again), at: at(5)).new, [])
        XCTAssertEqual(tracker.scan(panelWindow("w", again), at: at(5 + later)).new, [])
    }
}
