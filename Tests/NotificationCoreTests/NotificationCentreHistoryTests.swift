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

    /// A description that could not be read says nothing about whether the
    /// time is part of it, so the banner stays live.
    func testAnUnreadDescriptionLeavesTheBannerLive() {
        XCTAssertFalse(NotificationCentreHistory.isHistoryItem(
            description: "", textChildren: ["Standup", "10:30"]))
    }

    /// "now" is inside "Unknown", but it is not one of its fields.
    func testATimeFoundOnlyInsideAWordIsStillHistory() {
        XCTAssertTrue(NotificationCentreHistory.isHistoryItem(
            description: "App, Unknown host, body",
            textChildren: ["Unknown host", "body", "now"]))
    }

    // MARK: - The panel

    private func window(focused: Bool, children: [FakeNode]) -> FakeNode {
        FakeNode(subrole: "AXSystemDialog", focused: focused, children: [
            FakeNode(subrole: "AXHostingView", children: [FakeNode(children: [FakeNode(role: "AXScrollArea", children: children)])])
        ])
    }

    /// As measured with the panel open: focused, with its own menu button
    /// beside the list.
    func testAFocusedWindowHoldingTheMenuButtonIsThePanel() {
        XCTAssertTrue(NotificationCentreHistory.isPanel(window(focused: true, children: [
            FakeNode(children: [FakeNode(subrole: "AXNotificationCenterBanner")]), FakeNode(role: "AXMenuButton"),
        ])))
    }

    /// As measured with only a banner on screen: neither.
    func testAWindowShowingOnlyBannersIsNotThePanel() {
        XCTAssertFalse(NotificationCentreHistory.isPanel(window(focused: false, children: [
            FakeNode(subrole: "AXNotificationCenterBanner"),
        ])))
    }

    func testFocusAloneIsNotThePanel() {
        XCTAssertFalse(NotificationCentreHistory.isPanel(window(focused: true, children: [
            FakeNode(subrole: "AXNotificationCenterBanner"),
        ])))
    }

    func testTheMenuButtonWithoutFocusIsNotThePanel() {
        XCTAssertFalse(NotificationCentreHistory.isPanel(window(focused: false, children: [
            FakeNode(role: "AXMenuButton"),
        ])))
    }

    /// Only the panel's own button counts: directly in the scroll area.
    func testAMenuButtonElsewhereInTheWindowDoesNotMakeThePanel() {
        XCTAssertFalse(NotificationCentreHistory.isPanel(FakeNode(subrole: "AXSystemDialog", focused: true, children: [
            FakeNode(role: "AXGroup", children: [FakeNode(role: "AXMenuButton")]),
            FakeNode(role: "AXScrollArea", children: [FakeNode(subrole: "AXNotificationCenterBanner")]),
        ])))
    }

    /// A persistent alert can carry buttons of its own. It must never make its
    /// window look like the panel: that would take a live alert for history.
    func testAMenuButtonInsideAnAlertDoesNotMakeThePanel() {
        XCTAssertFalse(NotificationCentreHistory.isPanel(window(focused: true, children: [
            FakeNode(subrole: "AXNotificationCenterAlert", children: [FakeNode(value: "Title"), FakeNode(role: "AXMenuButton")]),
        ])))
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
