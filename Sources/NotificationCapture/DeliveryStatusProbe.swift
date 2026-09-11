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

        // A banner or alert must be enabled. Notification Centre delivery alone
        // is not enough: nothing is drawn on screen, so nothing is capturable.
        let styleShows = settings.alertSetting == .enabled
        let notFiltered = settings.notificationCenterSetting != .disabled

        return DeliveryStatus(
            authorized: authorized,
            wouldDisplay: authorized && styleShows && notFiltered
        )
    }
}
