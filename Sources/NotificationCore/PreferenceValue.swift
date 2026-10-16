// Sources/NotificationCore/PreferenceValue.swift
import Foundation

/// A number read back from the app's preferences, which hand back whatever was
/// saved under a key, or nothing, or something a person wrote there by hand.
enum PreferenceValue {
    /// The number the preferences hand back, or that Swift boxes, and nil for
    /// anything else. A Boolean is not a number here: it reads as 1 or 0, and
    /// would be taken for a value nobody set. Infinity and not-a-number are
    /// numbers, and each caller says what it accepts.
    static func number(_ stored: Any?) -> Double? {
        guard let number = stored as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return number.doubleValue
    }

    /// A finite number of seconds, not negative.
    static func seconds(_ stored: Any?) -> TimeInterval? {
        guard let seconds = number(stored), seconds.isFinite, seconds >= 0 else { return nil }
        return seconds
    }
}
