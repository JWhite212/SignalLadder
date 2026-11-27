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

    /// How many rules would play `sound` once a save has put a new one in its place, counted over the rules in effect
    /// and the draft in the rule editor, each rule once whichever of the two it is in (sound editor plan, Ruling 9). A
    /// rule in effect plays it now, even if the draft has been changed to name another, and a rule that the draft has
    /// changed to name it will play it once the draft is saved.
    public static func count(naming sound: String, inSaved saved: [Rule], andDraft draft: [Rule]) -> Int {
        Set((rules(naming: sound, in: saved) + rules(naming: sound, in: draft)).map(\.id)).count
    }
}
