// Sources/NotificationCore/BannerSubrole.swift
import Foundation

/// Subroles macOS uses for notification banners.
///
/// `AXNotificationCenterAlert` and `AlertStack` cover persistent-style
/// notifications; macOS 26 introduced the wrapped-overlay arrangement that
/// makes a downward search necessary (spec section 5.3).
public enum BannerSubrole {
    public static let allowlist: Set<String> = [
        "AXNotificationCenterBanner",
        "AXNotificationCenterBannerStack",
        "AXNotificationCenterAlert",
        "AlertStack",
    ]

    public static func isBanner(_ subrole: String?) -> Bool {
        guard let subrole else { return false }
        return allowlist.contains(subrole)
    }
}
