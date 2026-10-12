import Foundation
import NotificationCore
import UserNotifications

public struct DeliveryStatus: Equatable, Sendable {
    public let authorized: Bool
    public let wouldDisplay: Bool
    /// What the system's authorisation status says, which `authorized` cannot:
    /// whether the user was never asked or has said no (M5 plan, Ruling 16, O13).
    /// It is not optional, since a `DeliveryStatus` exists only once the probe has
    /// answered; the first run's own fact is nil until then.
    public let permission: NotificationPermission

    /// `permission` defaults to what `authorized` says
    /// (`NotificationPermission.derived(fromAuthorized:)`), so a caller that does not
    /// pass one compiles and behaves as it did, and the status cannot contradict
    /// itself. It is never `.notAsked` by default: only the probe, which reads the
    /// system's status, can say so. A caller that passes both is trusted to have read
    /// them from the same settings, as the probe does.
    public init(authorized: Bool, wouldDisplay: Bool, permission: NotificationPermission? = nil) {
        self.authorized = authorized
        self.wouldDisplay = wouldDisplay
        self.permission = permission ?? .derived(fromAuthorized: authorized)
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
            wouldDisplay: authorized && styleShows && notFiltered && notSummarised,
            // The same status as the core reads it: `.allowed` is exactly where
            // `authorized` is true, and the core says why the rest are not `.notAsked`
            // (M5 plan, Ruling 16).
            permission: NotificationPermission.reading(authorizationStatus: settings.authorizationStatus.rawValue)
        )
    }
}
