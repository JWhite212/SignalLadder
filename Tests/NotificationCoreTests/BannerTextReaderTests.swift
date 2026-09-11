// Tests/NotificationCoreTests/BannerTextReaderTests.swift
import XCTest
@testable import NotificationCore

final class BannerTextReaderTests: XCTestCase {
    /// Real shape from macOS 26.7: the banner's direct children are the
    /// static text elements, in display order.
    func testReadsDirectChildValuesInOrder() {
        let banner = FakeNode(
            subrole: "AXNotificationCenterBanner",
            description: "Script Editor, Test Title, Test Sub, Placeholder body",
            children: [
                FakeNode(value: "Test Title"),
                FakeNode(value: "Test Sub"),
                FakeNode(value: "Placeholder body"),
            ]
        )
        XCTAssertEqual(BannerTextReader.textChildren(of: banner),
                       ["Test Title", "Test Sub", "Placeholder body"])
    }

    func testSkipsChildrenWithNoValue() {
        let banner = FakeNode(children: [
            FakeNode(value: "Title"),
            FakeNode(subrole: "AXImage"),
            FakeNode(value: "Body"),
        ])
        XCTAssertEqual(BannerTextReader.textChildren(of: banner), ["Title", "Body"])
    }

    func testSkipsWhitespaceOnlyValuesAndTrimsTheRest() {
        let banner = FakeNode(children: [
            FakeNode(value: "  Title  "),
            FakeNode(value: "   "),
            FakeNode(value: "\n"),
        ])
        XCTAssertEqual(BannerTextReader.textChildren(of: banner), ["Title"])
    }

    func testReturnsEmptyForChildlessBanner() {
        XCTAssertTrue(BannerTextReader.textChildren(of: FakeNode()).isEmpty)
    }

    /// Only direct children are read. Nested text belongs to a sub-element
    /// and would change field ordering unpredictably if included.
    func testDoesNotDescendIntoGrandchildren() {
        let banner = FakeNode(children: [
            FakeNode(value: "Title"),
            FakeNode(children: [FakeNode(value: "Nested")]),
        ])
        XCTAssertEqual(BannerTextReader.textChildren(of: banner), ["Title"])
    }
}
