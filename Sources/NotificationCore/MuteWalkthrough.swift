// Sources/NotificationCore/MuteWalkthrough.swift
import Foundation
import CryptoKit

/// Which apps must be muted for SignalLadder to be their only voice, and how
/// far the user has got (§1.1, §8.2).
///
/// Muting is the mechanism, not a side-feature: until the source app's own
/// sound is off, every alert plays on top of it. And it cannot be verified —
/// the live notification settings are protected, and the readable copy is a
/// year stale (measured) — so what this tracks is the user's word, and it says
/// so wherever it is shown.
public enum MuteWalkthrough {
    /// Apps whose own sound would play alongside a rule's: every app an
    /// enabled sounding rule names exactly, then every app that set one off
    /// this session. The second catches what the first cannot see — a rule
    /// matching an app by pattern, or not naming an app at all.
    ///
    /// Case and accents are ignored when combining; the first spelling seen is
    /// the one shown.
    public static func appsToMute(rules: [Rule], alsoSounded sounded: [String]) -> [String] {
        let named = rules.filter(\.alertsAloud).flatMap { appsNamed(by: $0.condition) }
        return unique(named + sounded)
    }

    /// Only positive, exact names. "not app equals Teams" names every app
    /// except Teams; a pattern names no app in particular.
    static func appsNamed(by condition: RuleCondition) -> [String] {
        switch condition {
        case .field(.app, .equals, let name): return [name]
        case .field, .not: return []
        case .and(let conditions), .or(let conditions): return conditions.flatMap(appsNamed)
        }
    }

    static func unique(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.filter { name in
            let key = key(name)
            return !key.isEmpty && seen.insert(key).inserted
        }
    }

    /// How app names are compared everywhere here: ignoring case, accents and
    /// surrounding spaces, as rules compare them.
    static func key(_ name: String) -> String {
        Glob.fold(name.trimmingCharacters(in: .whitespaces))
    }
}

/// The apps the user has said they muted. Their word, persisted — nothing can
/// check it — and matched ignoring case and accents, as rules are.
///
/// What is stored is a digest of each name, never the name. Some names come
/// from captured banners: `appNameGuess` is parsed out of the banner's own
/// text, and a banner that parses oddly could hand it a fragment of the
/// message. The privacy rule (§2.1) allows no captured content on disk in any
/// form. A digest of the folded name answers "did the user confirm this app?"
/// and nothing else.
public struct MuteChecklist: Equatable, Sendable {
    /// SHA-256 of each confirmed name, as the key it is compared by.
    public private(set) var stored: [String]

    public init(stored: [String] = []) {
        var seen = Set<String>()
        self.stored = stored.filter { seen.insert($0).inserted }
    }

    public func isConfirmed(_ app: String) -> Bool {
        stored.contains(Self.digest(app))
    }

    public mutating func setConfirmed(_ app: String, _ isConfirmed: Bool) {
        guard !MuteWalkthrough.key(app).isEmpty else { return }
        let digest = Self.digest(app)
        stored.removeAll { $0 == digest }
        if isConfirmed { stored.append(digest) }
    }

    /// The apps not yet confirmed, in the order given.
    public func unconfirmed(among apps: [String]) -> [String] {
        apps.filter { !isConfirmed($0) }
    }

    static func digest(_ app: String) -> String {
        SHA256.hash(data: Data(MuteWalkthrough.key(app).utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// An installed or running app, by every name a banner might call it.
public struct AppCandidate: Equatable, Sendable {
    public let bundleID: String
    public let names: [String]

    public init(bundleID: String, names: [String]) {
        self.bundleID = bundleID
        self.names = names
    }
}

public enum BundleResolution: Equatable, Sendable {
    case unique(String)
    case notFound
    /// Every bundle ID the name matched. The user picks; a guess here would
    /// send them to the wrong app's settings with no sign anything was wrong.
    case ambiguous([String])
}

/// Turns a banner's app name into the bundle ID a deep link needs (§8.2).
///
/// A banner carries a display name, not a bundle ID, so this is a lookup by
/// name: bounded, best-effort, and supervised — the user sees where the link
/// lands. It is never used to decide anything automatically.
public enum BundleResolver {
    /// Running apps are consulted first. The app posting banners is almost
    /// always running, and when an old and a new version are both installed
    /// under one name, the running one is the one that matters.
    ///
    /// - Parameter installed: called only when the running apps do not
    ///   settle it, because it reads the disk.
    public static func resolve(_ appName: String, running: [AppCandidate],
                               installed: () -> [AppCandidate]) -> BundleResolution {
        let amongRunning = bundleIDs(named: appName, in: running)
        if !amongRunning.isEmpty { return resolution(amongRunning) }
        return resolution(bundleIDs(named: appName, in: installed()))
    }

    private static func resolution(_ ids: [String]) -> BundleResolution {
        switch ids.count {
        case 0: return .notFound
        case 1: return .unique(ids[0])
        default: return .ambiguous(ids)
        }
    }

    /// Distinct bundle IDs, compared ignoring case as the system does, so one
    /// app found under two of its names is still one app.
    private static func bundleIDs(named appName: String, in candidates: [AppCandidate]) -> [String] {
        let key = MuteWalkthrough.key(appName)
        guard !key.isEmpty else { return [] }
        var seen = Set<String>()
        return candidates
            .filter { $0.names.contains { MuteWalkthrough.key($0) == key } }
            .map(\.bundleID)
            .filter { seen.insert($0.lowercased()).inserted }
    }

    /// Where "open this app's notification settings" goes. On anything but a
    /// unique match, the Notifications pane itself, and the caller shows the
    /// app's name so the user can find it (§8.2).
    ///
    /// `com.apple.preference.notifications` is the pane's legacy identifier;
    /// macOS 26 still registers it (measured, from the settings extension's
    /// Info.plist).
    public static func notificationSettingsURL(for resolution: BundleResolution) -> URL {
        let pane = "x-apple.systempreferences:com.apple.preference.notifications"
        guard case .unique(let bundleID) = resolution,
              let id = bundleID.addingPercentEncoding(withAllowedCharacters: bundleIDCharacters) else {
            return URL(string: pane)!
        }
        return URL(string: "\(pane)?id=\(id)")!
    }

    public static let focusSettingsURL = URL(string: "x-apple.systempreferences:com.apple.Focus-Settings.extension")!

    private static let bundleIDCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-."))
}

/// The walkthrough's words, tested here because "muted" is a claim the app
/// cannot check, and every line must say whose claim it is.
public enum MuteWalkthroughText {
    /// The menu item that opens the walkthrough. Names the apps still
    /// outstanding (ruling 10: unconfirmed apps are named, not hidden).
    public static func title(apps: [String], checklist: MuteChecklist) -> String {
        let outstanding = checklist.unconfirmed(among: apps)
        if outstanding.isEmpty {
            return "Confirmed muted: \(list(apps))"
        }
        return "⚠︎ Not confirmed muted: \(list(outstanding))"
    }

    public static func appItem(_ app: String, confirmed: Bool) -> String {
        confirmed ? "\(app) — confirmed muted" : "\(app) — not confirmed muted"
    }

    public static let explanation = [
        "Turn off each app's own notification sound in System Settings,",
        "so your rules are its only voice. Nothing can check this for you:",
        "tick each app here once it is done.",
    ]

    public static func openSettings(_ app: String) -> String {
        "Open Notification Settings for \(app)…"
    }

    public static let confirm = "I've Turned Its Sound Off"

    /// Shown before the general Notifications pane opens, so the name the user
    /// must look for is on screen (§8.2). nil when the link goes straight to
    /// the app.
    public static func lookupFallback(_ app: String, _ resolution: BundleResolution) -> (title: String, body: String)? {
        let find = "System Settings will open at Notifications. Find “\(app)” in the list and turn its sound off."
        switch resolution {
        case .unique:
            return nil
        case .notFound:
            return ("SignalLadder couldn't find “\(app)” among your apps.", find)
        case .ambiguous(let ids):
            return ("More than one app is called “\(app)”.", find + "\n\nFound: \(ids.joined(separator: ", ")).")
        }
    }

    /// Measured in M2b: Do Not Disturb switched on when the screen locked,
    /// and while it is on banners are never drawn, so nothing can be captured.
    public static let focus = [
        "Do Not Disturb and other Focus modes hide banners,",
        "so nothing can be captured while one is on.",
        "Check whether one turns on when your screen locks.",
    ]

    public static let openFocusSettings = "Open Focus Settings…"

    /// "A", "A and B", "A, B and C", "A, B, C and 2 more".
    static func list(_ names: [String], limit: Int = 3) -> String {
        guard names.count > 1 else { return names.first ?? "" }
        if names.count > limit {
            return names.prefix(limit).joined(separator: ", ") + " and \(names.count - limit) more"
        }
        return names.dropLast().joined(separator: ", ") + " and " + names.last!
    }
}
