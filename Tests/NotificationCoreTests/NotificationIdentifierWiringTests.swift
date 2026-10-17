import XCTest
@testable import NotificationCore

/// How the identifier reaches `BannerTracker` (#160). `AXElementNode` is the one
/// adapter from a live element to `AccessibilityNode`, and it needs a live
/// Notification Centre to run, so what it reads is held by reading its source, as
/// `ReadAtOnceWiringTests` does for the watcher.
final class NotificationIdentifierWiringTests: XCTestCase {
    private func code(_ path: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // NotificationCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // package root
            .appendingPathComponent(path)
        return PowerHoldWiringTests.code(of: try String(contentsOf: url, encoding: .utf8))
    }

    /// The live element's identifier is its AXIdentifier, read as a string like
    /// its other attributes.
    func testTheLiveNodeReadsTheElementsAXIdentifier() throws {
        let node = try code("Sources/NotificationCapture/AXElementNode.swift")
        let identifier = try XCTUnwrap(OnCallWiringTests.body(of: "var identifier: String? {", in: node),
                                       "identifier is not in AXElementNode exactly once, or is not closed")
        XCTAssertEqual(identifier, "\nSelf.stringAttribute(element, kAXIdentifierAttribute as String)\n")
    }

    /// A node that has none says so, so a test double or a node from before this
    /// property is not made to supply one.
    func testANodeWithoutAnIdentifierHasNone() {
        XCTAssertNil(FakeNode(subrole: "AXNotificationCenterAlert").identifier)
    }
}
