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
/// again (2026-09-29), and on one later read most rows, hours old, showed
/// none. So the label is only supporting evidence. `BannerTracker` relies
/// first on `isPanel`: whatever the panel holds when it opens is history.
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
    /// has keyboard focus, and its scroll area holds the panel's own menu
    /// button directly, beside the list (measured 2026-09-29). A window
    /// showing only banners had neither. Focus alone is not enough: it was
    /// seen to stay on after the panel closed. And the menu button must be
    /// that one, a direct child of the scroll area: a button a live alert
    /// carries sits inside the alert, so an alert can never make its window
    /// look like the panel.
    ///
    /// Or beside the scroll area: on macOS 27.2, while a group is expanded in
    /// the list, the menu button leaves the scroll area and sits beside it, in
    /// the group that holds it, until Show Less puts it back (#162). Missing it
    /// there, the tracker forgot the list two reads after a group was expanded,
    /// and a row the list opened with was captured as an arrival. A stack
    /// expanded on screen, the list closed, had no menu button anywhere.
    public static func isPanel(_ window: AccessibilityNode) -> Bool {
        window.isFocused && holdsPanelMenuButton(window, depth: 0)
    }

    /// Reads each child's role once: the walk passes every row of the list,
    /// and each read is a call into Notification Centre.
    private static func holdsPanelMenuButton(_ node: AccessibilityNode, depth: Int) -> Bool {
        guard depth < 6, !BannerSubrole.isBanner(node.subrole) else { return false }
        let children = node.children.map { (node: $0, role: $0.role) }
        if children.contains(where: { $0.role == "AXScrollArea" }),
           children.contains(where: { $0.role == "AXMenuButton" }) {
            return true
        }
        return children.contains { child in
            child.role == "AXScrollArea"
                ? child.node.children.contains { $0.role == "AXMenuButton" }
                : holdsPanelMenuButton(child.node, depth: depth + 1)
        }
    }

    /// A description is the fields joined with ", ". Matching whole fields,
    /// not substrings, keeps "now" from being found inside "Unknown".
    static func fields(of description: String) -> [String] {
        description
            .split(whereSeparator: { $0 == "," || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    public static func isRelativeTime(_ text: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static let weekdays = "Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday"
    private static let pattern = #"^(now|\d+\s?(m|min|mins|h|hr|hrs|d|w)( ago)?|yesterday|"#
        + weekdays
        + #"|\d{1,2}:\d{2}(\s?[ap]m)?|\d{1,2}/\d{1,2}/\d{2,4})$"#
}
