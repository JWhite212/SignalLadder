// Sources/NotificationCore/SoundSaveNaming.swift
import Foundation

/// The name an edited sound is saved under (sound editor plan, Ruling 9).
///
/// The suggestion is the source's name with the next number that is free, so the
/// sound a rule names is never taken from it without asking. It is never a name
/// macOS has, which a file of the user's would take the place of for every rule
/// that names it, and never a name the user already has: saving over one of the
/// user's own sounds is a different answer, asked for by typing its name, and
/// the window asks before it does it.
///
/// The core cannot read the folders, so the names that are taken are handed in.
/// Names are compared ignoring case, as `SoundLibrary` compares them.
public enum SoundSaveNaming {
    /// The longest name a sound may have. The same limit `SoundInstall` holds a
    /// name to, which a test in `AlertAudioTests` keeps equal.
    public static let longestName = 100
    /// The longest a name may be in bytes, which is not the same limit: a file's name is held to
    /// bytes, and a letter can take up to four. It is what is left of the 255 a file's name may have
    /// when a sound that is being replaced is set aside under a name that holds its own and more
    /// (`SoundInstall.asideName`), so that every name the window passes can be saved over, and a test
    /// in `AlertAudioTests` keeps it equal to that.
    public static let longestNameBytes = 197

    /// What is wrong with a name that was typed.
    public enum Problem: Equatable, Sendable {
        case blank
        /// More than `longestName` characters.
        case tooLong
        /// Within the limit in characters, and still too many bytes to be a file's name.
        case tooLongAsAFileName
        /// A name that begins with a dot is hidden, and the library would not list it.
        case startsWithDot
        /// A slash, a colon, a backslash, or a line break or other control character.
        case unsafeCharacter
        /// macOS has a sound of this name, spelt as given here.
        case macOSSound(String)
    }

    /// What saving under a typed name would do.
    public enum Verdict: Equatable, Sendable {
        /// Nothing has the name: a new sound, under the name with its spaces taken off.
        case free(String)
        /// One of the user's own sounds has it, spelt as given here: saving would
        /// replace it, and the window asks first.
        case yours(String)
        case refused(Problem)
    }

    /// The name offered for the sound edited from `source`: its name with the next
    /// number that no sound of the user's and no macOS sound has. "Alarm" is
    /// offered as "Alarm 2", and "Alarm 2" as "Alarm 3", so that saving again and
    /// again counts up and does not pile numbers on. A number is a counter only when
    /// it is one to three digits after a space, so "Alarm 2024" becomes "Alarm 2024 2".
    public static func suggestedName(for source: String, ownSounds: Set<String>, macOSSounds: Set<String>) -> String {
        let taken = Set((ownSounds.union(macOSSounds)).map { $0.lowercased() })
        let name = source.trimmingCharacters(in: .whitespacesAndNewlines)
        var base = name
        var number = 2
        if let space = name.lastIndex(of: " ") {
            let digits = name[name.index(after: space)...]
            let rest = name[..<space].trimmingCharacters(in: .whitespaces)
            if (1...3).contains(digits.count), digits.allSatisfy({ $0.isASCII && $0.isNumber }),
               !rest.isEmpty, let counted = Int(digits) {
                base = rest
                number = max(counted + 1, 2)
            }
        }
        if base.isEmpty { base = SoundEditorText.untitledSoundName }
        while true {
            let suffix = " \(number)"
            // Cut so that the number fits, in characters and in bytes, whole letters at a time, and not
            // at a space, which would leave two. A letter that is itself too many bytes is cut away
            // with the rest, and the name that is left is the plain one.
            var head = String(base.prefix(longestName - suffix.count))
            while !head.isEmpty, head.utf8.count + suffix.utf8.count > longestNameBytes { head.removeLast() }
            head = head.trimmingCharacters(in: .whitespaces)
            if head.isEmpty { head = SoundEditorText.untitledSoundName }
            let candidate = head + suffix
            if !taken.contains(candidate.lowercased()) { return candidate }
            number += 1
        }
    }

    /// What saving under `typed` would do. A macOS name is refused even when the
    /// user has a sound of that name, because the install refuses it.
    public static func verdict(for typed: String, ownSounds: Set<String>, macOSSounds: Set<String>) -> Verdict {
        let name = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return .refused(.blank) }
        guard name.count <= longestName else { return .refused(.tooLong) }
        guard name.utf8.count <= longestNameBytes else { return .refused(.tooLongAsAFileName) }
        guard !name.hasPrefix(".") else { return .refused(.startsWithDot) }
        let unsafe = CharacterSet(charactersIn: "/:\\").union(.controlCharacters).union(.newlines)
        guard name.unicodeScalars.allSatisfy({ !unsafe.contains($0) }) else { return .refused(.unsafeCharacter) }
        if let system = spelling(of: name, in: macOSSounds) { return .refused(.macOSSound(system)) }
        if let own = spelling(of: name, in: ownSounds) { return .yours(own) }
        return .free(name)
    }

    /// Whether `name` is a sound that can be saved over: one of the user's own that
    /// macOS does not also have a sound of the name of. A macOS sound is always
    /// saved as a copy under a new name.
    public static func canSaveOver(_ name: String, ownSounds: Set<String>, macOSSounds: Set<String>) -> Bool {
        spelling(of: name, in: ownSounds) != nil && spelling(of: name, in: macOSSounds) == nil
    }

    /// The spelling `names` has of `name`. Two sounds can differ only by case on a volume that tells
    /// case apart, and a set has no order, so the first of them in order is the one given: the same
    /// whatever the set holds them in.
    private static func spelling(of name: String, in names: Set<String>) -> String? {
        names.filter { $0.caseInsensitiveCompare(name) == .orderedSame }.min()
    }
}
