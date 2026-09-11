// Sources/NotificationCore/AccessibilityNode.swift
import Foundation

/// A node in an accessibility tree, reduced to only what banner location needs.
///
/// The real implementation wraps `AXUIElement`; tests use an in-memory fake.
/// Keeping this protocol free of ApplicationServices is what allows the whole
/// search algorithm to be tested without a TCC grant.
public protocol AccessibilityNode {
    var subrole: String? { get }
    var attributedDescription: String? { get }
    /// The element's AXValue as a string. Banner text children carry their
    /// text here, not in the description.
    var value: String? { get }
    var children: [AccessibilityNode] { get }
}
