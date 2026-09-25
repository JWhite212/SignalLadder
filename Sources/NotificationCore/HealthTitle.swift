import Foundation

/// The health line at the top of the menu, as a pure function.
///
/// Moved out of AppDelegate when it had to start saying how old its evidence
/// is. "Working — verified" with no age read, on 2026-09-25, as a statement
/// about the present while capture had been blind since 80 seconds after the
/// self-test it rested on.
public enum HealthTitle {
    /// - Parameter secondsSinceLastSuccessfulCanary: nil if no self-test has
    ///   ever succeeded.
    public static func text(for health: CaptureHealth,
                            secondsSinceLastSuccessfulCanary age: TimeInterval?) -> String {
        switch health {
        case .verified:
            guard let age else { return "Working — verified" }
            return "Working — verified \(ago(age))"
        case .unknown:
            // Unknown after a success means the evidence went stale. Saying
            // "Checking…" there would suggest a check is under way; none is.
            guard let age else { return "Checking…" }
            return "Unverified — last verified \(ago(age))"
        case .degraded:
            return "Cannot verify itself"
        case .blind:
            return "NOT capturing notifications"
        }
    }

    /// "just now", "3 min ago", "1 hr 5 min ago", "2 hr ago".
    public static func ago(_ seconds: TimeInterval) -> String {
        // A clock set backwards must not produce "-3 min ago".
        let minutes = Int(max(0, seconds)) / 60
        if minutes == 0 { return "just now" }
        if minutes < 60 { return "\(minutes) min ago" }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? "\(hours) hr ago" : "\(hours) hr \(rest) min ago"
    }
}
