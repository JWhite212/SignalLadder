// Sources/NotificationCore/BeepAudibility.swift
import Foundation

/// Whether the app's own beeps can be heard (M5 plan, Ruling 9).
///
/// Every cue the app gives when a rule cannot speak for it is `NSSound.beep()`:
/// the health alarm's, `OnCallWatch`'s, the on-call repeat and the end of a
/// snooze. That sound is reported to play at the Mac's Alert volume, in System
/// Settings › Sound, which is a setting of its own and apart from the output's
/// mute and volume that `OutputState` reads. That was not heard here. With Alert
/// volume at zero and the output audible, every one of those cues is silent and
/// nothing on screen would say so.
///
/// The app target reads the preference and hands the value over, and what it
/// means is decided here. A value it could not read is not silent: the app has
/// then read nothing, and claims nothing.
public enum BeepAudibility {
    /// The preference that holds Alert volume, in the global domain. It is a
    /// number between 0 and 1, and reads 1 on the Mac this was written on; that
    /// the slider writes it is what developers report and was not seen. It is
    /// read and never written.
    public static let preferenceKey = "com.apple.sound.beep.volume"

    /// Below this a beep is treated as silent: the threshold `OutputState` uses
    /// for an output, which is a little under the lowest step of the slider.
    public static let inaudibleBelow = 0.02

    /// Alert volume as the preferences hand it back, which may be anything, or
    /// nil when it is absent or not a finite number.
    ///
    /// A Boolean is not a number here: it reads as 1 or 0, and would be taken for
    /// a volume that nobody set. A negative number is a number, and silent.
    public static func alertVolume(fromStored stored: Any?) -> Double? {
        guard let number = stored as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let value = number.doubleValue
        return value.isFinite ? value : nil
    }

    /// True only for a number below `inaudibleBelow`: 0 and a negative one
    /// included. nil is not silent, and neither is a value that is not finite,
    /// which reads as nil.
    public static func isSilent(alertVolume: Double?) -> Bool {
        guard let alertVolume, alertVolume.isFinite else { return false }
        return alertVolume < inaudibleBelow
    }
}
