// Sources/signalladder-probe/AXElementNode.swift
import Foundation
import ApplicationServices
import NotificationCore

/// Adapts a live `AXUIElement` to the pure `AccessibilityNode` protocol.
///
/// Every attribute read in the app funnels through here, so the messaging
/// timeout and the attributed-string unwrapping exist in exactly one place.
struct AXElementNode: AccessibilityNode {
    private let element: AXUIElement

    init(_ element: AXUIElement) {
        self.element = element
        AXUIElementSetMessagingTimeout(element, 0.2)
    }

    var subrole: String? {
        Self.stringAttribute(element, kAXSubroleAttribute as String)
    }

    var attributedDescription: String? {
        Self.stringAttribute(element, "AXAttributedDescription")
            ?? Self.stringAttribute(element, kAXDescriptionAttribute as String)
    }

    var children: [AccessibilityNode] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
              let elements = value as? [AXUIElement]
        else { return [] }
        return elements.map(AXElementNode.init)
    }

    /// Reads an attribute as a String, unwrapping NSAttributedString.
    /// macOS 15 moved notification text into an attributed string, which is
    /// why the plain-string path alone is not enough (spec section 3).
    private static func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success
        else { return nil }
        if let s = value as? String { return s }
        if let a = value as? NSAttributedString { return a.string }
        return nil
    }
}
