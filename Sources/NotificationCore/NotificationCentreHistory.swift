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
/// Only once it is a minute old, though. A history item younger than that
/// shows no time at all, so it looks exactly like a live banner and is still
/// captured again when Notification Centre is opened. Telling those apart
/// needs something other than the item itself.
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
