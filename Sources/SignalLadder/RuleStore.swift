// Sources/SignalLadder/RuleStore.swift
import Foundation
import NotificationCore
import AlertAudio

/// Reads the rules file. Never writes over it.
///
/// Everything that decides what the file MEANS lives in
/// `RuleStoreStatus.load`, in the tested core. This type only moves bytes,
/// because `NotificationCore` may not touch the file system.
///
/// It writes exactly once, ever: creating an example file when there is none,
/// and only when the user asks to edit their rules. It never overwrites. In
/// M3a the file is written by hand, and an app that "helpfully" rewrote a file
/// its user was editing — or replaced a damaged one with an empty one — would
/// destroy the only copy of their rules.
@MainActor
final class RuleStore {
    private(set) var rules: [Rule] = []
    private(set) var status: RuleStoreStatus = .noRulesFile
    let fileURL: URL

    /// What sound names a rule may use. Checked on every reload, so a sound the
    /// user adds is accepted without restarting, and a misspelt one is
    /// reported when the file loads rather than at the incident.
    let sounds: SoundLibrary

    /// Prepares each rule's sound as the rules load, so a file that cannot
    /// play is reported now, and an alert never waits on the disk.
    let player: AlertPlayer

    init(fileURL: URL = RuleStore.defaultFileURL, sounds: SoundLibrary, player: AlertPlayer) {
        self.fileURL = fileURL
        self.sounds = sounds
        self.player = player
    }

    // `nonisolated` because it is used as a default argument, which Swift
    // evaluates outside the actor. It reads nothing mutable.
    nonisolated static var defaultFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.jamiewhite.signalladder", isDirectory: true)
            .appendingPathComponent("rules.json")
    }

    func reload() {
        // Afresh every time: a sound file edited since the last load is read
        // again, and one no rule names any more is released.
        player.forgetPreparedSounds()
        let unplayable: (String) -> String? = { [player] name in
            do {
                try player.prepare(sound: name)
                return nil
            } catch {
                return String(describing: error)
            }
        }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            (rules, status) = RuleStoreStatus.load(nil, availableSounds: sounds.availableNames, unplayable: unplayable)
            return
        }
        do {
            (rules, status) = RuleStoreStatus.load(try Data(contentsOf: fileURL), availableSounds: sounds.availableNames,
                                                   unplayable: unplayable)
        } catch {
            // Present but unopenable — permissions, a directory in the way.
            // Reported, never treated as "no rules file", which would read as
            // the user simply not having written any yet.
            rules = []
            status = .unreadable("the file exists but could not be opened: \(error.localizedDescription)")
        }
    }

    /// Writes the example file if, and only if, no file exists.
    ///
    /// `.withoutOverwriting` makes that guarantee the operating system's rather
    /// than this method's: even if a file appeared between the existence check
    /// and the write, the write fails instead of replacing it.
    @discardableResult
    func createExampleIfMissing() throws -> Bool {
        guard !FileManager.default.fileExists(atPath: fileURL.path) else { return false }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try RuleSetCodec.encode([Rule.editingExample]).write(to: fileURL, options: .withoutOverwriting)
        return true
    }
}
