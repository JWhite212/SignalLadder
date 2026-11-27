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

    /// The names of the sounds macOS has, and of the user's own, each from its own folder and not combined: a user's
    /// file of a macOS name is in both. The sound editor tells what saving would do by them (sound editor plan,
    /// Ruling 9). Read fresh each time, as the rest are.
    public var systemSoundNames: Set<String> {
        Set(Self.sounds(in: systemDirectory).map(\.name))
    }

    public var customSoundNames: Set<String> {
        Set(Self.sounds(in: customDirectory)
            .filter { (try? $0.url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true }
            .map(\.name))
    }

    /// The file for a sound name, ignoring case; nil if there is none.
    public func url(for name: String) -> URL? {
        index()[name.lowercased()]?.url
    }

    /// The system sound called `name`, ignoring case, as macOS spells it; nil
    /// if there is none. A sound of the user's with that name would take its
    /// place, so nothing is added under one.
    func systemName(matching name: String) -> String? {
        Self.sounds(in: systemDirectory).first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.name
    }

    /// The user's own files called `name`, ignoring case and whatever their
    /// type: Alarm.wav and alarm.mp3 are one sound to a rule.
    func customFiles(named name: String) -> [URL] {
        Self.sounds(in: customDirectory).filter { $0.name.caseInsensitiveCompare(name) == .orderedSame }.map(\.url)
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true }
    }

    /// Read fresh each time rather than cached: the user may add a sound while
    /// the app runs, and a stale list would reject a rule naming it.
    private func index() -> [String: (name: String, url: URL)] {
        var byKey: [String: (name: String, url: URL)] = [:]
        // System first, then custom, so custom wins on a clash.
        for directory in [systemDirectory, customDirectory] {
            for sound in Self.sounds(in: directory) { byKey[sound.name.lowercased()] = sound }
        }
        return byKey
    }

    /// The audio files in one folder, in the order of their file names.
    private static func sounds(in directory: URL) -> [(name: String, url: URL)] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
            .filter { extensions.contains($0.pathExtension.lowercased()) }
            .map { ($0.deletingPathExtension().lastPathComponent, $0) }
    }
}
