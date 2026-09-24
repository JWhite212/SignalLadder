// Sources/NotificationCore/Glob.swift
import Foundation

/// Glob matching for the `matches` operator: `*` is any run of characters,
/// `?` is exactly one. Everything else is literal. There is no escape syntax,
/// so a literal `*` or `?` cannot be matched — the spec defines exactly these
/// two wildcards and nothing more (§5.11).
///
/// The match is anchored: `#prod-*` must match the whole field, not a
/// substring of it. That is what makes it different from `contains`, and what
/// lets a pattern say "starts with".
///
/// Linear two-pointer with a single backtrack point, so the worst case is
/// O(n·m) and a pathological pattern cannot blow up. That property is the
/// entire reason `matches` is glob rather than regex: a rule is evaluated
/// against every notification, on the main thread, and a pattern that could
/// hang would hang the capture pipeline with it.
public enum Glob {
    public static func matches(_ text: String, pattern: String) -> Bool {
        // Case- and diacritic-insensitive (§5.11): both sides are folded, so
        // "Équipe" matches "equipe*" and "STRASSE" matches "straße".
        //
        // Folding can LENGTHEN a character — ß folds to "ss", the ligature ﬁ
        // to "fi". Literals are unaffected, because both sides expand alike.
        // `?` is not: it is positional, and must consume one character of the
        // ORIGINAL text, not one folded character. An earlier version made
        // exactly that mistake and claimed in this comment that the length
        // change was harmless; "Stra?e" then silently failed to match
        // "Straße". `ends` records where each original character's folded
        // form stops, so `?` can jump to it.
        //
        // The pattern is folded the same way, one character at a time. Folding
        // a whole string and folding it character by character are not always
        // equal — they differ where invisible format characters or Cyrillic
        // combining marks share a character — so text and pattern must go
        // through one procedure, or an identical literal could fail to match.
        let (t, ends) = foldedWithBoundaries(text)
        let p = foldedWithBoundaries(pattern).chars

        var ti = 0, pi = 0
        var starAt = -1, resumeFrom = 0

        while ti < t.count {
            if pi < p.count, p[pi] == "?" {
                // One original character, however many folded ones it became.
                ti = ends[ti]
                pi += 1
            } else if pi < p.count, p[pi] != "*", p[pi] == t[ti] {
                ti += 1
                pi += 1
            } else if pi < p.count, p[pi] == "*" {
                // Record where the star is and where it began absorbing, then
                // first try letting it absorb nothing.
                starAt = pi
                resumeFrom = ti
                pi += 1
            } else if starAt >= 0 {
                // Mismatch after a star: let that star absorb one more
                // character and retry. Only the most recent star is ever
                // revisited, which is what bounds the work.
                pi = starAt + 1
                resumeFrom += 1
                ti = resumeFrom
            } else {
                return false
            }
        }

        // Text exhausted; only trailing stars may remain.
        while pi < p.count, p[pi] == "*" { pi += 1 }
        return pi == p.count
    }

    /// The folded characters of `s`, and for each one the index just past the
    /// original character it came from. Internal so the tests' exhaustive
    /// reference matcher can share the definition of what a character is.
    static func foldedWithBoundaries(_ s: String) -> (chars: [Character], ends: [Int]) {
        var chars: [Character] = []
        var ends: [Int] = []
        for original in s {
            let piece = Array(fold(String(original)))
            chars += piece
            ends += Array(repeating: chars.count, count: piece.count)
        }
        return (chars, ends)
    }

    static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
