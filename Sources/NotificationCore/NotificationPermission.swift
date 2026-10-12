// Sources/NotificationCore/NotificationPermission.swift
import Foundation

/// Whether the app may show notifications, and whether asking could still put the
/// system's dialog in front of the user (M5 plan, Ruling 16, O13).
///
/// `DeliveryStatus` has said only whether the app is authorised, and that cannot
/// tell "never asked" from "denied". The first is answered by a request, which
/// shows the dialog, and the second only by the user, in System Settings, so the
/// first run's notification step offers a different button for each.
///
/// There are three cases and none for "not read yet". Nothing is known before the
/// first probe has answered, and the guide holds that as the absence of a value of
/// this type, so that no case here can be taken for an answer that was never given.
public enum NotificationPermission: CaseIterable, Equatable, Sendable {
    /// The user has not been asked, so a request can still show the dialog. The
    /// only case that says so, and only the system's own "not determined" gives it.
    case notAsked
    /// Not allowed, and nothing the app has read says a request could change that:
    /// the way offered is the user's, in System Settings. It is also what a status
    /// the app cannot place reads as (`reading(authorizationStatus:)`), and for
    /// those nothing is established about whether a request could show a dialog, so
    /// none is offered.
    case denied
    /// The system says the app may post: authorised, or provisional, which delivers
    /// without interrupting. The probe counts both as authorised. It does not say a
    /// banner would be drawn, which is a separate fact that
    /// `DeliveryStatus.wouldDisplay` carries, and the notification step needs both.
    case allowed

    /// What the system's authorisation status reads as, from its raw value, so that
    /// the core needs no import of `UserNotifications`.
    ///
    /// | raw | `UNAuthorizationStatus` | reads as |
    /// |---|---|---|
    /// | 0 | not determined | `.notAsked` |
    /// | 1 | denied | `.denied` |
    /// | 2 | authorized | `.allowed` |
    /// | 3 | provisional | `.allowed` |
    /// | 4 | ephemeral | `.denied` |
    /// | any other, negative or not yet known | | `.denied` |
    ///
    /// **`.allowed` is exactly 2 and 3**, which is what `DeliveryStatusProbe` counts
    /// as authorised (authorized or provisional), so the guide and the health line
    /// cannot disagree about whether the app may post.
    ///
    /// **Ephemeral and a status this build has not heard of are neither `.allowed`
    /// nor `.notAsked`.** Ephemeral is for App Clips, which the macOS SDK marks
    /// unavailable (`UNNotificationSettings.h`, read in the macOS 26.5 SDK), and a
    /// value past the list is one nobody has seen. Both are decided under the Global
    /// Constraints' first rule, which takes the behaviour that cannot lose or silence
    /// a page:
    ///
    /// - Read as `.allowed`, they would tick the notification step for a status the
    ///   probe does not count as authorised, so the guide would say a page can arrive
    ///   while the health line, which reads the same status as not authorised, names a
    ///   denied permission.
    /// - Read as `.notAsked`, they would offer a request that may show no dialog, so
    ///   the button might do nothing and nothing would say why.
    ///
    /// `.denied` is what the health line already reads for them, leaves the step
    /// outstanding, and offers the way to Notification Settings, which the user can
    /// always act on. If a later macOS adds a status that is a form of allowed, the
    /// cost is a step that will not tick, and not a page the guide called covered.
    public static func reading(authorizationStatus rawValue: Int) -> NotificationPermission {
        switch rawValue {
        case 0: return .notAsked
        case 2, 3: return .allowed
        default: return .denied
        }
    }

    /// What a `DeliveryStatus` made with only `authorized` reads as: `.allowed` for
    /// an authorised app, and `.denied` otherwise.
    ///
    /// It is never `.notAsked`. Only a read of the system's status can say that a
    /// request could still show a dialog, and a caller that knows only whether the
    /// app is authorised has not read it, so it is not told so: the step then offers
    /// the way to Notification Settings, and not a request that may show nothing.
    /// The default agrees with `authorized` for every value, so a status made
    /// without a permission cannot contradict itself.
    public static func derived(fromAuthorized authorized: Bool) -> NotificationPermission {
        authorized ? .allowed : .denied
    }
}
