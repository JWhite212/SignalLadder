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
        // Folded identically on both sides, so the comparison is case- and
        // diacritic-insensitive (§5.11) — "Équipe" matches "equipe*". Folding
        // can change length (ß folds to ss), which is harmless precisely
        // because both strings go through the same transform before any
        // characters are compared.
        let t = Array(fold(text))
        let p = Array(fold(pattern))

        var ti = 0, pi = 0
        var starAt = -1, resumeFrom = 0

        while ti < t.count {
            if pi < p.count, p[pi] == "?" || p[pi] == t[ti] {
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

    private static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
