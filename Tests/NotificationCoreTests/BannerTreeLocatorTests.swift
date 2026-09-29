// Tests/NotificationCoreTests/BannerTreeLocatorTests.swift
import XCTest
@testable import NotificationCore

final class BannerTreeLocatorTests: XCTestCase {
    private let locator = BannerTreeLocator()

    func testFindsBannerAtTopLevel() {
        let banner = FakeNode(subrole: "AXNotificationCenterBanner", description: "App, Title\nBody")
        let found = locator.locate(in: FakeNode(children: [banner]))
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.attributedDescription, "App, Title\nBody")
    }

    /// macOS 26 wraps banners in an extra overlay window; the same search
    /// must still find them without any code change.
    func testFindsBannerNestedDeepBehindWrappers() {
        let banner = FakeNode(subrole: "AXNotificationCenterBanner", description: "App, Deep\nBody")
        let found = locator.locate(in: FakeNode.chain(depth: 9, leaf: banner))
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.attributedDescription, "App, Deep\nBody")
    }

    func testFindsAllAllowlistedSubroles() {
        for subrole in BannerSubrole.allowlist {
            let banner = FakeNode(subrole: subrole, description: "App, \(subrole)\nBody")
            let found = locator.locate(in: FakeNode(children: [banner]))
            XCTAssertEqual(found.count, 1, "Failed to find subrole \(subrole)")
        }
    }

    /// Two persistent alerts from one app stack into a single element that
    /// carries the newest one's text, as Teams alerts do.
    func testFindsAStackOfPersistentAlerts() {
        let stack = FakeNode(subrole: "AXNotificationCenterAlertStack",
                             description: "Microsoft Teams, Priya, Second message, stacked",
                             children: [FakeNode(value: "Priya"), FakeNode(value: "Second message")])
        let found = locator.locate(in: FakeNode.chain(depth: 5, leaf: stack))
        XCTAssertEqual(found.first?.attributedDescription, "Microsoft Teams, Priya, Second message, stacked")
    }

    func testFindsMultipleStackedBanners() {
        let a = FakeNode(subrole: "AXNotificationCenterBanner", description: "App, One\nBody")
        let b = FakeNode(subrole: "AXNotificationCenterBanner", description: "App, Two\nBody")
        let found = locator.locate(in: FakeNode(children: [a, b]))
        XCTAssertEqual(found.count, 2)
    }

    func testReturnsEmptyWhenNoBannerPresent() {
        let tree = FakeNode(children: [FakeNode(subrole: "AXGroup"), FakeNode(subrole: "AXButton")])
        XCTAssertTrue(locator.locate(in: tree).isEmpty)
    }

    func testDoesNotDescendBeyondMaxDepth() {
        let banner = FakeNode(subrole: "AXNotificationCenterBanner", description: "App, TooDeep\nBody")
        let found = locator.locate(in: FakeNode.chain(depth: 40, leaf: banner))
        XCTAssertTrue(found.isEmpty, "Search must stop at maxDepth")
    }

    func testRespectsVisitedBudget() {
        // The banner sits behind 300 siblings, exceeding the 256-node budget.
        let noise = (0..<300).map { _ in FakeNode(subrole: "AXGroup") }
        let banner = FakeNode(subrole: "AXNotificationCenterBanner", description: "App, Hidden\nBody")
        let tree = FakeNode(children: noise + [banner])

        let tight = BannerTreeLocator(maxDepth: 12, maxVisited: 256)
        XCTAssertTrue(tight.locate(in: tree).isEmpty,
                      "Budget must stop the search before reaching the banner")

        // Same tree, generous budget — proves the banner really is reachable
        // and that the empty result above came from the budget, not the shape.
        let generous = BannerTreeLocator(maxDepth: 12, maxVisited: 1000)
        XCTAssertEqual(generous.locate(in: tree).count, 1)
    }

    /// A banner that is itself the root must still be found.
    func testFindsBannerWhenRootIsTheBanner() {
        let banner = FakeNode(subrole: "AXNotificationCenterBanner", description: "App, Root\nBody")
        XCTAssertEqual(locator.locate(in: banner).count, 1)
    }

    /// A banner that contains banners must yield its children, not itself —
    /// otherwise a stack of notifications collapses to one unreadable node.
    func testStackContainingBannersYieldsTheChildrenNotTheStack() {
        let first = FakeNode(subrole: "AXNotificationCenterBanner", description: "App, One\nBody")
        let second = FakeNode(subrole: "AXNotificationCenterBanner", description: "App, Two\nBody")
        let stack = FakeNode(subrole: "AXNotificationCenterBannerStack", children: [first, second])

        let found = locator.locate(in: stack)

        XCTAssertEqual(found.count, 2)
        XCTAssertEqual(found.compactMap(\.attributedDescription).sorted(),
                       ["App, One\nBody", "App, Two\nBody"])
        XCTAssertFalse(found.contains { $0.subrole == "AXNotificationCenterBannerStack" })
    }

    func testFindsBannerExactlyAtMaxDepth() {
        let banner = FakeNode(subrole: "AXNotificationCenterBanner", description: "App, AtLimit\nBody")
        let found = locator.locate(in: FakeNode.chain(depth: 12, leaf: banner))
        XCTAssertEqual(found.count, 1, "A banner at exactly maxDepth must still be found")
    }

    func testDoesNotFindBannerOneBeyondMaxDepth() {
        let banner = FakeNode(subrole: "AXNotificationCenterBanner", description: "App, PastLimit\nBody")
        let found = locator.locate(in: FakeNode.chain(depth: 13, leaf: banner))
        XCTAssertTrue(found.isEmpty, "A banner one level past maxDepth must not be found")
    }
}
