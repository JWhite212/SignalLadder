// Sources/NotificationCore/NotificationCentreHistory.swift
import Foundation

/// Tells a notification in Notification Centre's history from a banner that
/// has just arrived.
///
/// Opening Notification Centre shows its history in the same window, under the
/// same subroles, as a live banner — and a notification that arrives while it
/// is open appears at the top of that same list. Without telling them apart,
/// every opening captured the history again as if it had just arrived, and a
/// rule that matched an old notification sounded again (measured on macOS
/// 26.7, 2026-09-29).
///
/// What differs is one text child. A history item ends with how long ago it
/// arrived — "1m ago", "10m ago" — which is not one of the fields of its
/// description. A live banner has only its title, subtitle and body, and the
/// last of them is always one of those fields.
///
/// Only once it is a minute old, though: a history item younger than that
/// shows no time at all. And the label comes and goes as the panel lays
/// itself out — read "19m ago", then nothing 17 ms later, then "19m ago"
/// again (2026-09-29). So the label is only a fallback. What `BannerTracker`
/// relies on is the panel itself: `isPanel` tells when a window is showing
/// it, and everything in it at that moment is history.
///
/// Errs one way, deliberately: when anything is uncertain the item is treated
/// as live. That repeats history, as before this existed; the other error
/// would miss an alert. So a time format it does not know (it knows English
/// ones only) is live, and so is an item whose description could not be read,
/// since an empty description proves nothing about what it holds.
public enum NotificationCentreHistory {
    public static func isHistoryItem(description: String, textChildren: [String]) -> Bool {
        let fields = self.fields(of: description)
        guard textChildren.count >= 2, let last = textChildren.last,
              isRelativeTime(last), !fields.isEmpty
        else { return false }
        return !fields.contains(last)
    }

    /// Whether `window` is showing Notification Centre's history panel.
    ///
    /// The panel opens in the same window banners use — a new one, or the
    /// banner window itself if a banner is on screen — and that window then
    /// has keyboard focus and holds the panel's own menu button. A window
    /// showing only banners has neither (measured 2026-09-29). A menu button
    /// inside a banner, as a persistent alert may have, does not count, so a
    /// live alert can never make its window look like the panel.
    public static func isPanel(_ window: AccessibilityNode) -> Bool {
        window.isFocused && holdsMenuButtonOutsideBanners(window, depth: 0)
    }

    private static func holdsMenuButtonOutsideBanners(_ node: AccessibilityNode, depth: Int) -> Bool {
        if node.role == "AXMenuButton" { return true }
        guard depth < 8, !BannerSubrole.isBanner(node.subrole) else { return false }
        return node.children.contains { holdsMenuButtonOutsideBanners($0, depth: depth + 1) }
    }

    /// A description is the fields joined with ", ". Matching whole fields,
    /// not substrings, keeps "now" from being found inside "Unknown".
    static func fields(of description: String) -> [String] {
        description
            .split(whereSeparator: { $0 == "," || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    static func isRelativeTime(_ text: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static let weekdays = "Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday"
    private static let pattern = #"^(now|\d+\s?(m|min|mins|h|hr|hrs|d|w)( ago)?|yesterday|"#
        + weekdays
        + #"|\d{1,2}:\d{2}(\s?[ap]m)?|\d{1,2}/\d{1,2}/\d{2,4})$"#
}
