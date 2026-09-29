// Sources/NotificationCore/BannerSubrole.swift
import Foundation

/// Subroles macOS uses for notification banners.
///
/// `AXNotificationCenterAlert` and `AlertStack` cover persistent-style
/// notifications; macOS 26 introduced the wrapped-overlay arrangement that
/// makes a downward search necessary (spec section 5.3).
///
/// A second persistent alert from the same app, arriving while the first is
/// still up, joins it in an `AXNotificationCenterAlertStack` carrying the
/// newest one's text (measured on macOS 26.7, 2026-09-29). Until that was
/// listed here, the stack was invisible, and every alert after the first in
/// it was missed — Teams alerts are persistent.
public enum BannerSubrole {
    public static let allowlist: Set<String> = [
        "AXNotificationCenterBanner",
        "AXNotificationCenterBannerStack",
        "AXNotificationCenterAlert",
        "AXNotificationCenterAlertStack",
        "AlertStack",
    ]

    public static func isBanner(_ subrole: String?) -> Bool {
        guard let subrole else { return false }
        return allowlist.contains(subrole)
    }
}
