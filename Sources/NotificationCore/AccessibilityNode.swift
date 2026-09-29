// Sources/NotificationCore/AccessibilityNode.swift
import Foundation

/// A node in an accessibility tree, reduced to only what banner location needs.
///
/// The real implementation wraps `AXUIElement`; tests use an in-memory fake.
/// Keeping this protocol free of ApplicationServices is what allows the whole
/// search algorithm to be tested without a TCC grant.
public protocol AccessibilityNode {
    var role: String? { get }
    var subrole: String? { get }
    var attributedDescription: String? { get }
    /// The element's AXValue as a string. Banner text children carry their
    /// text here, not in the description.
    var value: String? { get }
    var children: [AccessibilityNode] { get }

    /// Whether the element has keyboard focus. Notification Centre's window
    /// has it while its history panel is open, and not while it shows only
    /// banners.
    var isFocused: Bool { get }

    /// Which element this is, equal across every read of the same element
    /// for as long as it exists. A banner that replaces another in place is a
    /// different element, so it has a different identity.
    var identity: AnyHashable { get }

    /// True only once the element is known to have been destroyed. A read
    /// that fails or times out is not proof of that, so it is false then.
    var isGone: Bool { get }
}
