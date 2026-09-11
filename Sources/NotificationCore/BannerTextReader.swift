// Sources/NotificationCore/BannerTextReader.swift
import Foundation

/// Collects a banner's visible text from its child elements.
///
/// Live capture on macOS 26.7 showed a banner's direct children are the
/// AXStaticText elements carrying title, subtitle and body, in display order,
/// with the text in AXValue rather than the description. Reading them is more
/// reliable than parsing the comma-joined description, which cannot
/// distinguish a comma inside a field from a field boundary.
///
/// Only direct children are read: nested text belongs to a sub-element and
/// would perturb field ordering.
public enum BannerTextReader {
    public static func textChildren(of banner: AccessibilityNode) -> [String] {
        banner.children.compactMap { child in
            guard let raw = child.value else { return nil }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }
}
