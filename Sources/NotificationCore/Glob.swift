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
        // to "fi". A literal run may therefore cover a character through its
        // folded form: "strasse" matches "Straße". But a wildcard, and the
        // point where a literal run hands over to one, may never fall INSIDE a
        // character. `?` is exactly one character of the original text and
        // `*` absorbs whole characters. Getting this wrong took three
        // attempts, each found by review:
        //
        //   1. `?` consumed one FOLDED character, so "Stra?e" missed "Straße".
        //   2. Folding the pattern differently from the text made some
        //      identical strings fail to match themselves.
        //   3. A literal could stop half-way through a folded character and
        //      let a wildcard take the rest, so "s?" matched "ß" and "f*"
        //      matched "ﬁre" — `?` matching half a character, contradicting
        //      the one thing its contract says.
        //
        // `ends` records where each original character's folded form stops;
        // every wildcard checks it.
        let (t, ends) = foldedWithBoundaries(text)
        let p = tokens(pattern)

        func atBoundary(_ i: Int) -> Bool { i == 0 || ends[i - 1] == i }

        var ti = 0, pi = 0
        var starAt = -1, resumeFrom = 0

        while ti < t.count {
            if pi < p.count, p[pi] == .anyOne, atBoundary(ti) {
                // One whole original character, however many folded ones.
                ti = ends[ti]
                pi += 1
            } else if pi < p.count, case .literal(let c) = p[pi], c == t[ti] {
                ti += 1
                pi += 1
            } else if pi < p.count, p[pi] == .anyRun, atBoundary(ti) {
                // Record where the star is and where it began absorbing, then
                // first try letting it absorb nothing.
                starAt = pi
                resumeFrom = ti
                pi += 1
            } else if starAt >= 0 {
                // Mismatch after a star: let that star absorb one more whole
                // character and retry. Only the most recent star is ever
                // revisited, which is what bounds the work.
                pi = starAt + 1
                resumeFrom = ends[resumeFrom]
                ti = resumeFrom
            } else {
                return false
            }
        }

        // Text exhausted; only trailing stars may remain.
        while pi < p.count, p[pi] == .anyRun { pi += 1 }
        return pi == p.count
    }

    /// A pattern element. Wildcards are exactly the `*` and `?` the user
    /// typed — decided before folding, so no character can fold INTO a
    /// wildcard (an asterisk carrying a combining accent folds to a plain
    /// `*`, and must stay the literal it was written as).
    enum Token: Equatable {
        case literal(Character)
        case anyRun
        case anyOne
    }

    static func tokens(_ pattern: String) -> [Token] {
        var out: [Token] = []
        for character in pattern {
            switch character {
            case "*": out.append(.anyRun)
            case "?": out.append(.anyOne)
            default: out += fold(String(character)).map(Token.literal)
            }
        }
        return out
    }

    /// The folded characters of `s`, one original character at a time, and
    /// for each folded character the index just past the original character
    /// it came from. Folding a whole string and folding it character by
    /// character are not always equal (invisible format characters beside
    /// Cyrillic combining marks), so the text is always folded this way —
    /// the same way `tokens` folds the pattern.
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
