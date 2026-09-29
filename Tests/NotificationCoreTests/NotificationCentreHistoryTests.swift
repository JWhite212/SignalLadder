// Tests/NotificationCoreTests/NotificationCentreHistoryTests.swift
import XCTest
@testable import NotificationCore

final class NotificationCentreHistoryTests: XCTestCase {
    /// As Notification Centre showed a stack of Script Editor notifications,
    /// opened a minute after the newest arrived.
    func testAStackInTheHistoryIsHistory() {
        XCTAssertTrue(NotificationCentreHistory.isHistoryItem(
            description: "Script Editor, SL-E burst 3, SL-E body, stacked",
            textChildren: ["SL-E burst 3", "SL-E body", "1m ago"]))
    }

    func testASingleNotificationInTheHistoryIsHistory() {
        XCTAssertTrue(NotificationCentreHistory.isHistoryItem(
            description: "Teams, Priya, Can you look at this?",
            textChildren: ["Priya", "Can you look at this?", "10m ago"]))
    }

    /// Arrived while Notification Centre was open: at the top of the same list,
    /// with no time.
    func testABannerArrivingWhileItIsOpenIsNotHistory() {
        XCTAssertFalse(NotificationCentreHistory.isHistoryItem(
            description: "Script Editor, SL-while open, SL-open body",
            textChildren: ["SL-while open", "SL-open body"]))
    }

    func testABannerWithASubtitleIsNotHistory() {
        XCTAssertFalse(NotificationCentreHistory.isHistoryItem(
            description: "App, Title, Subtitle, Body",
            textChildren: ["Title", "Subtitle", "Body"]))
    }

    /// A live notification whose body happens to read like a time says so in
    /// its description too, which a history item's time never does.
    func testALiveBannerWhoseBodyLooksLikeATimeIsNotHistory() {
        XCTAssertFalse(NotificationCentreHistory.isHistoryItem(
            description: "Build, Finished, 2m ago",
            textChildren: ["Finished", "2m ago"]))
    }

    /// Unknown formats fall back to live: history repeats, as it did before,
    /// rather than an alert being missed.
    func testATimeInAnotherLanguageIsTreatedAsLive() {
        XCTAssertFalse(NotificationCentreHistory.isHistoryItem(
            description: "App, Titel, Text",
            textChildren: ["Titel", "Text", "vor 1 Min."]))
    }

    func testRecognisesTheTimesNotificationCentreShows() {
        for time in ["now", "Now", "1m ago", "10m ago", "3h ago", "2d ago", "1w ago", "Yesterday",
                     "Monday", "09:58", "9:58 am", "26/09/2026"] {
            XCTAssertTrue(NotificationCentreHistory.isRelativeTime(time), time)
        }
    }

    func testDoesNotMistakeOrdinaryTextForATime() {
        for text in ["Nowhere", "1m ago today", "ago", "Mondays", "Deploy in 5m", ""] {
            XCTAssertFalse(NotificationCentreHistory.isRelativeTime(text), text)
        }
    }
}
