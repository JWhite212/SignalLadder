// Sources/SignalLadder/AppLocator.swift
import AppKit
import NotificationCore

/// Lists apps by every name a banner might use for them, for the mute
/// walkthrough's deep links (§8.2). Matching is done in the core, by
/// `BundleResolver`; this only gathers the candidates.
enum AppLocator {
    static func running() -> [AppCandidate] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard let id = app.bundleIdentifier, let name = app.localizedName else { return nil }
            return AppCandidate(bundleID: id, names: [name])
        }
    }

    /// Reads the application folders directly (ruling 11), one level deep so
    /// Utilities and vendor folders are included. Deterministic, needs no
    /// Spotlight index, and runs only when the user asks to open an app's
    /// settings — never on the capture path.
    static func installed() -> [AppCandidate] {
        let roots = ["/Applications", "/System/Applications", NSHomeDirectory() + "/Applications"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
        var bundles: [URL] = []
        for root in roots {
            for child in contents(of: root) {
                if child.pathExtension == "app" {
                    bundles.append(child)
                } else if (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    bundles += contents(of: child).filter { $0.pathExtension == "app" }
                }
            }
        }
        return bundles.compactMap(candidate)
    }

    private static func contents(of folder: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey],
                                                      options: .skipsHiddenFiles)) ?? []
    }

    /// Every name the app might appear under: its file name, the name Finder
    /// shows (localised — "Météo" for Weather in French), and the names its
    /// Info.plist declares. Read from the plist rather than through `Bundle`,
    /// which would keep an object for every app on the disk for the life of
    /// the process.
    private static func candidate(_ app: URL) -> AppCandidate? {
        guard let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
              let id = info["CFBundleIdentifier"] as? String else { return nil }
        var shown = FileManager.default.displayName(atPath: app.path)
        if shown.hasSuffix(".app") { shown.removeLast(4) }
        let declared = ["CFBundleDisplayName", "CFBundleName"].compactMap { info[$0] as? String }
        return AppCandidate(bundleID: id, names: [app.deletingPathExtension().lastPathComponent, shown] + declared)
    }
}
