import XCTest
@testable import NotificationCore

/// The Inspector, empty while health is a problem, gives the leading cause's advice, such as
/// "Grant Accessibility to SignalLadder in System Settings…", and had no button for it: the
/// way on was the menu's advice line (workflow audit, 2026-10-16, finding 13). It now has the
/// button that opens the pane the cause names (`HealthCause.pane`), in the words the Setup
/// Guide gives that pane, and none where no pane fixes the cause.
final class InspectorEmptyStateButtonTests: XCTestCase {
    private typealias Button = InspectorEmptyState.Button

    func testAnEmptyInspectorWithAProblemOffersThePaneItsCauseNames() {
        XCTAssertEqual(InspectorEmptyState.button(isEmpty: true, health: .blind([.accessibilityNotTrusted])),
                       Button(pane: .accessibility, label: "Open Accessibility Settings…"))
        XCTAssertEqual(InspectorEmptyState.button(isEmpty: true, health: .degraded([.notificationsSuppressed, .lazyAccessibilityTree])),
                       Button(pane: .notifications, label: "Open Notification Settings…"), "the leading cause's")
        XCTAssertEqual(InspectorEmptyState.button(isEmpty: true, health: .degraded([.lazyAccessibilityTree])),
                       Button(pane: .keyboard, label: "Open Keyboard Settings…"))
    }

    func testThereIsNoButtonWhereThereIsNothingToFix() {
        XCTAssertNil(InspectorEmptyState.button(isEmpty: true, health: .blind([.observerNotAttached])), "no pane fixes it")
        XCTAssertNil(InspectorEmptyState.button(isEmpty: true, health: .blind([])), "no cause")
        XCTAssertNil(InspectorEmptyState.button(isEmpty: true, health: .verified))
        XCTAssertNil(InspectorEmptyState.button(isEmpty: true, health: .unknown))
        XCTAssertNil(InspectorEmptyState.button(isEmpty: false, health: .blind([.accessibilityNotTrusted])),
                     "rows are shown, not the empty state")
    }

    /// The Setup Guide's button for each pane, which the Prove step and this share.
    func testEachPaneHasTheGuidesButton() {
        XCTAssertEqual(SetupText.ButtonAction.opening(.notifications), .openNotificationSettings)
        XCTAssertEqual(SetupText.ButtonAction.opening(.accessibility), .openAccessibilitySettings)
        XCTAssertEqual(SetupText.ButtonAction.opening(.keyboard), .openKeyboardSettings)
    }
}

/// How the Inspector shows that button and the app opens the pane. The app target has no
/// tests, so this reads its sources.
final class InspectorEmptyStateButtonWiringTests: XCTestCase {
    func testTheModelWorksOutTheButtonWithTheMessageAndTheViewShowsItBeneath() throws {
        let model = try code("InspectorModel.swift")
        XCTAssertEqual(count("emptyStateButton = InspectorEmptyState.button(isEmpty: entries.isEmpty, health: health)", in: model), 1)
        XCTAssertEqual(count("var openPane: (HealthCause.Pane) -> Void = { _ in }", in: model), 1)
        let view = try code("InspectorView.swift")
        XCTAssertEqual(count("if let button = model.emptyStateButton {", in: view), 1)
        XCTAssertEqual(count("Button(button.label) { model.openPane(button.pane) }", in: view), 1)
        XCTAssertLessThan(try XCTUnwrap(view.range(of: "Text(message)")).lowerBound,
                          try XCTUnwrap(view.range(of: "if let button = model.emptyStateButton {")).lowerBound,
                          "beneath the advice")
    }

    func testTheAppOpensThePaneThroughTheDoorTheAdviceLineUses() throws {
        let app = try code("AppDelegate.swift")
        XCTAssertEqual(count("inspectorModel.openPane = { pane in OnboardingCoordinator.open(pane) }", in: app), 1)
    }
}
