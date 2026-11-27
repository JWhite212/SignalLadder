// Sources/NotificationCore/SoundUse.swift
import Foundation

/// Which rules name a sound, so that saving over one can say how many rules will
/// play the new one (sound editor plan, Ruling 9).
///
/// A rule names a sound in any alert it can set off: the first, a repeat, and a
/// final alert that is not a Shortcut. A rule that is switched off names it too,
/// since switching it on would play it. Names are compared ignoring case, as
/// `SoundLibrary` finds a file.
public enum SoundUse {
    /// The rules that name `sound`, in the order they are in, each once.
    public static func rules(naming sound: String, in rules: [Rule]) -> [Rule] {
        guard !sound.isEmpty else { return [] }
        return rules.filter { rule in
            rule.alertActions.contains { $0.soundName?.caseInsensitiveCompare(sound) == .orderedSame }
        }
    }

    public static func count(naming sound: String, in rules: [Rule]) -> Int {
        self.rules(naming: sound, in: rules).count
    }
}
