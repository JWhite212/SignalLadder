// Sources/NotificationCore/BurstText.swift
import Foundation

/// The words a burst adds to the panel, the menu and the Inspector (M5 plan,
/// Task 5, Ruling 14, Ruling 18): how many matches one escalation stands for,
/// and what an Inspector row says of a match that joined an escalation and played
/// its own alert. They are written once, here, so that the three places say the
/// same thing and are tested together.
///
/// A count is "matches", never "messages": capture can read one banner twice, and
/// what the app has read is that a rule matched, not what arrived. A count and a
/// number are not content (M4 Ruling 17), so they can stand where a rule's name
/// does, on the panel over every app and in the menu on a shared screen. Nothing
/// here names an app or says what a notification said.
public enum BurstText {
    /// "7 matches": how many matches an escalation stands for, or nil when it
    /// stands for one. A single match is what every escalation was before a burst
    /// could join one, and a line that says "1 match" says nothing the line does
    /// not, so the line stays as it was and the singular is never shown.
    public static func matches(_ count: Int) -> String? {
        count > 1 ? "\(count) matches" : nil
    }

    /// The end of an Inspector row's alert line for a match that joined an
    /// escalation and played its own alert, after that alert's own words: "Played
    /// Glass — joined an escalation (match 3)". `matchNumber` counts the match
    /// that began the escalation as 1, so the first to join is 2, and it agrees
    /// with the panel line's count. It does not say the escalation repeats, as the
    /// sentence for a silent join does, since a ladder with no repeat can be joined
    /// too.
    public static func joinedEscalation(matchNumber: Int) -> String {
        "joined an escalation (match \(matchNumber))"
    }
}
