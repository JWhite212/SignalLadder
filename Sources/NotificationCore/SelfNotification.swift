// Sources/NotificationCore/SelfNotification.swift
import Foundation

/// The notifications this app posts about itself, and the test for recognising
/// one once it comes back through capture.
///
/// The app's own alarms travel the same pipeline as real traffic, so they must
/// be excluded from the capture count or the app inflates a number the user
/// reads as notifications they received.
///
/// The exclusion is deliberately narrow. Matching on app name alone would be a
/// silent-loss path: another app whose banner carries the same name would have
/// its genuine notifications dropped without trace, which is the exact failure
/// this product exists to prevent. Requiring the title too means a banner must
/// carry both our name and our wording to be discarded. An inflated count is
/// visible and correctable; a dropped notification is neither.
///
/// The titles live here, beside the test that matches them, so the code that
/// posts an alarm and the code that recognises one cannot drift apart.
/// The canary needs no entry: it is excluded earlier by its per-run marker.
public enum SelfNotification {
    public static let blindTitle = "SignalLadder is not capturing"
    public static let degradedTitle = "SignalLadder cannot verify itself"

    private static let alarmTitles: Set<String> = [blindTitle, degradedTitle]

    /// True when this banner is an alarm the app posted about itself.
    ///
    /// `ownAppName` is nil when the bundle declares no name at all — an
    /// unbundled or malformed build. Excluding nothing is the safe failure.
    public static func isOwnAlarm(_ notification: CapturedNotification,
                                  ownAppName: String?) -> Bool {
        guard let ownAppName, !ownAppName.isEmpty else { return false }
        guard notification.appNameGuess == ownAppName else { return false }
        return alarmTitles.contains(notification.title)
    }
}
