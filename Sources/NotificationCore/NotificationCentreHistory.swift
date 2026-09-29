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
/// arrived — "1m ago", "10m ago" — which is not part of its description. A
/// live banner has only its title, subtitle and body, all of which are.
///
/// Recognising the time is English-only, and deliberately errs one way: a
/// format it does not know leaves the item treated as live. That repeats
/// history, as before this existed; the other error would miss an alert.
public enum NotificationCentreHistory {
    public static func isHistoryItem(description: String, textChildren: [String]) -> Bool {
        guard textChildren.count >= 2, let last = textChildren.last,
              isRelativeTime(last), !description.contains(last)
        else { return false }
        return true
    }

    static func isRelativeTime(_ text: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static let weekdays = "Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday"
    private static let pattern = #"^(now|\d+\s?(m|min|mins|h|hr|hrs|d|w)( ago)?|yesterday|"#
        + weekdays
        + #"|\d{1,2}:\d{2}(\s?[ap]m)?|\d{1,2}/\d{1,2}/\d{2,4})$"#
}
