// Sources/NotificationCore/NotificationFieldExtractor.swift
import Foundation

/// Parses a captured banner into fields.
///
/// Live capture on macOS 26.7 showed the accessibility description is
/// comma-joined across up to four fields — app, title, subtitle, body — with
/// no newline anywhere. Crucially, the banner's AXStaticText children expose
/// those fields already separated, so reading the children is both simpler and
/// strictly more reliable than parsing the concatenation.
///
/// The app name is the exception: it appears only as the description's first
/// comma-delimited segment and has no child of its own.
public enum NotificationFieldExtractor {
    public static func extract(_ raw: RawCapture,
                               textChildren: [String]) -> CapturedNotification {
        let segments = raw.rawText
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmed() }

        let appNameGuess = segments.count >= 2 ? segments[0] : ""

        let children = textChildren.map { $0.trimmed() }.filter { !$0.isEmpty }
        let (title, subtitle, body) = children.isEmpty
            ? fieldsFromSegments(segments, hasAppName: !appNameGuess.isEmpty)
            : fieldsFromChildren(children)

        return CapturedNotification(
            timestamp: raw.timestamp,
            appNameGuess: appNameGuess,
            title: title,
            subtitle: subtitle,
            body: body,
            rawText: raw.rawText,
            subrole: raw.subrole
        )
    }

    /// Primary path. macOS renders a banner's text as ordered child elements,
    /// so their count tells us which fields are present.
    private static func fieldsFromChildren(_ c: [String]) -> (String, String, String) {
        switch c.count {
        case 1:  return (c[0], "", "")
        case 2:  return (c[0], "", c[1])
        case 3:  return (c[0], c[1], c[2])
        default: return (c[0], c[1], c[2...].joined(separator: " "))
        }
    }

    /// Fallback for banners with no text children. Lossy by construction: a
    /// comma inside a field is indistinguishable from a field boundary, and
    /// unlike the original design there is no newline to disambiguate.
    private static func fieldsFromSegments(_ s: [String],
                                           hasAppName: Bool) -> (String, String, String) {
        let rest = hasAppName ? Array(s.dropFirst()) : s
        switch rest.count {
        // Unreachable today: splitting even an empty string yields [""], so
        // `rest` always holds at least one element. Kept as a guard because
        // every arm below subscripts rest[0].
        case 0:  return ("", "", "")
        case 1:  return (rest[0], "", "")
        case 2:  return (rest[0], "", rest[1])
        case 3:  return (rest[0], rest[1], rest[2])
        default: return (rest[0], rest[1], rest[2...].joined(separator: ", "))
        }
    }
}

private extension StringProtocol {
    func trimmed() -> String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
