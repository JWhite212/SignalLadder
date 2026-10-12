// Sources/NotificationCore/AppLocation.swift
import Foundation

/// Where the running copy of the app is, as far as the login item needs to know
/// (M5 plan, Ruling 15).
///
/// A status of "not found" cannot tell a copy that cannot register from one that
/// has only never been registered: an unbundled program reads it, and so does a
/// signed bundle that was never registered, in /Applications and outside any
/// Applications folder (all three measured on macOS 26.7.1 on 2026-10-05; not
/// seen on macOS 14 or 15). So where the copy is running from is the only way to
/// tell an unavailable copy from a registrable one, and to give the user a reason
/// they can act on. It is kept only as far as that needs.
///
/// The app target hands `classify(path:home:)` the path of the bundle it runs
/// from and the user's home folder, which it reads. Nothing here reads the
/// environment or the disk, so a test gives both as text.
public enum AppLocation: Equatable, Sendable, CaseIterable {
    /// An app bundle directly inside `/Applications`.
    case applications
    /// An app bundle directly inside the user's own `Applications` folder.
    case userApplications
    /// A copy macOS runs from a path of its own choosing, which holds an
    /// `AppTranslocation` folder, for an app opened from where it was downloaded.
    /// Registering from one is reported to fail or to misread.
    case translocated
    /// Anywhere else: a `.build` folder, a mounted volume, a Downloads folder, a
    /// folder inside an Applications folder, and a program that is not in a
    /// bundle at all, whose path is the folder it sits in.
    case elsewhere

    /// The folder name macOS puts in the path of a translocated copy.
    public static let translocationFolder = "AppTranslocation"

    /// Says where `path`, the app's bundle, is.
    ///
    /// - It is an Applications folder's only for a bundle, a name ending in
    ///   `.app`, that sits directly in the folder, so a program that is not in a
    ///   bundle is never taken for one, and neither is a bundle in a folder inside
    ///   Applications, which was not measured.
    /// - A path that is not absolute, or holds a `.` or `..` part, is not one the
    ///   app can vouch for, and is elsewhere. The translocation folder is looked
    ///   for first, wherever it is in the path.
    /// - `home` is the user's home folder, such as `/Users/jamie`. One that is not
    ///   an absolute path names no `~/Applications`.
    public static func classify(path: String, home: String) -> AppLocation {
        let parts = Self.parts(of: path)
        if parts.contains(translocationFolder) { return .translocated }
        guard path.hasPrefix("/"), !parts.contains(where: { $0 == "." || $0 == ".." }),
              let name = parts.last, name.hasSuffix(".app"), name != ".app" else { return .elsewhere }

        let folder = Array(parts.dropLast())
        if folder == ["Applications"] { return .applications }
        if home.hasPrefix("/"), folder == Self.parts(of: home) + ["Applications"] { return .userApplications }
        return .elsewhere
    }

    /// Whether a bundle here is one the login item can be registered from: the
    /// two Applications folders.
    public var isInApplicationsFolder: Bool {
        switch self {
        case .applications, .userApplications: return true
        case .translocated, .elsewhere: return false
        }
    }

    /// The parts of a path, with no empty one, so a doubled or trailing slash
    /// changes nothing.
    private static func parts(of path: String) -> [String] {
        path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    }
}
