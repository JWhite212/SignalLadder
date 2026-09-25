// Sources/SignalLadder/RuleStore.swift
import Foundation
import NotificationCore
import AlertAudio
import RuleStorage

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
    let file: RulesFile
    var fileURL: URL { file.url }

    /// What sound names a rule may use. Checked on every reload, so a sound the
    /// user adds is accepted without restarting, and a misspelt one is
    /// reported when the file loads rather than at the incident.
    let sounds: SoundLibrary

    /// Prepares each rule's sound as the rules load, so a file that cannot
    /// play is reported now, and an alert never waits on the disk.
    let player: AlertPlayer

    init(fileURL: URL = RuleStore.defaultFileURL, sounds: SoundLibrary, player: AlertPlayer) {
        self.file = RulesFile(url: fileURL)
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

        do {
            (rules, status) = RuleStoreStatus.load(try file.read().data, availableSounds: sounds.availableNames,
                                                   unplayable: unplayable)
        } catch {
            // Present but unopenable — reported, never treated as "no rules
            // file", which would read as the user simply not having written
            // any yet.
            rules = []
            status = .unreadable(String(describing: error))
        }
    }

    /// Writes the example file if, and only if, no file exists.
    @discardableResult
    func createExampleIfMissing() throws -> Bool {
        try file.createIfMissing(RuleSetCodec.encode([Rule.editingExample]))
    }
}
