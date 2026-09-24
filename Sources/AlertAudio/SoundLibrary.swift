// Sources/AlertAudio/SoundLibrary.swift
import Foundation

/// The sounds a rule may name, and where each one lives.
///
/// Two folders: the system's sounds, and the user's own in Application
/// Support. A user's file overrides a system sound of the same name — the
/// user's file is the user's intent. Names are the file name without its
/// extension and are compared ignoring case, so a rule saying "glass" plays
/// Glass.aiff.
///
/// This is also what the rules file is validated against when it loads, so a
/// misspelt sound is reported by rule name then — not discovered as silence
/// during the incident the rule was written for.
public struct SoundLibrary: Sendable {
    public let systemDirectory: URL
    public let customDirectory: URL

    /// Formats AVAudioFile reads. Anything else in the folders is ignored.
    static let extensions: Set<String> = ["aiff", "aif", "wav", "caf", "mp3", "m4a"]

    public init(systemDirectory: URL = URL(fileURLWithPath: "/System/Library/Sounds", isDirectory: true),
                customDirectory: URL = SoundLibrary.defaultCustomDirectory) {
        self.systemDirectory = systemDirectory
        self.customDirectory = customDirectory
    }

    public static var defaultCustomDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.jamiewhite.signalladder", isDirectory: true)
            .appendingPathComponent("Sounds", isDirectory: true)
    }

    /// Every available sound, by display name.
    public var availableNames: Set<String> {
        Set(index().values.map(\.name))
    }

    /// The file for a sound name, ignoring case; nil if there is none.
    public func url(for name: String) -> URL? {
        index()[name.lowercased()]?.url
    }

    /// Read fresh each time rather than cached: the user may add a sound while
    /// the app runs, and a stale list would reject a rule naming it.
    private func index() -> [String: (name: String, url: URL)] {
        var byKey: [String: (name: String, url: URL)] = [:]
        // System first, then custom, so custom wins on a clash.
        for directory in [systemDirectory, customDirectory] {
            let files = (try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
            where Self.extensions.contains(file.pathExtension.lowercased()) {
                let name = file.deletingPathExtension().lastPathComponent
                byKey[name.lowercased()] = (name, file)
            }
        }
        return byKey
    }
}
