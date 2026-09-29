import Foundation
import UserNotifications

public struct DeliveryStatus: Equatable, Sendable {
    public let authorized: Bool
    public let wouldDisplay: Bool

    public init(authorized: Bool, wouldDisplay: Bool) {
        self.authorized = authorized
        self.wouldDisplay = wouldDisplay
    }
}

/// Answers "would our own notification actually appear on screen?".
///
/// This is checked independently of, and before, any capture diagnosis. If the
/// banner would never be displayed then the Accessibility layer had nothing to
/// see, and blaming capture would send the user to re-grant a permission that
/// was never the problem.
public enum DeliveryStatusProbe {
    public static func current() async -> DeliveryStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()

        let authorized = settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional

        // alertSetting reports whether the app MAY alert; alertStyle reports
        // what the user actually chose. Banners switched off for the app — a
        // style of None before macOS 26, the Desktop checkbox since, which
        // this probe caught live on 2026-09-29 — leave alertSetting .enabled
        // while nothing is drawn on screen, so style is the decisive check.
        let styleShows = settings.alertStyle != .none
        let notFiltered = settings.notificationCenterSetting != .disabled

        // Scheduled Summary holds notifications for later, so nothing is drawn
        // now. Unlike a Focus, this one is visible to us — check it.
        let notSummarised = settings.scheduledDeliverySetting != .enabled

        return DeliveryStatus(
            authorized: authorized,
            wouldDisplay: authorized && styleShows && notFiltered && notSummarised
        )
    }
}
