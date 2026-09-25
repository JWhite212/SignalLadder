// Sources/SignalLadder/RuleStore.swift
import Foundation
import NotificationCore
import AlertAudio
import RuleStorage

/// Reads the rules file, and holds what the app is running on.
///
/// Everything that decides what the file MEANS lives in
/// `RuleStoreStatus.load`, in the tested core; everything that decides how it
/// is written lives in `RulesFile`, in its own tested target. This type only
/// connects them.
///
/// The app writes the file in exactly two cases: creating an example when
/// there is none and the user asks to edit it, and when the user presses Save
/// in the rule editor. Never on load, never to tidy it, never to replace a
/// damaged one. A save keeps the version it replaces as
/// `rules.previous.json`, and is refused if the file changed since the editor
/// read it — so a hand edit is never silently overwritten.
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

    /// The checks every rule's sound must pass, for the loader and the
    /// editor alike. Each call reads the sound folders afresh, so a sound the
    /// user adds is found without restarting.
    var soundCheck: RuleSetCodec.SoundCheck {
        RuleSetCodec.SoundCheck(available: sounds.availableNames, unplayable: { [player] name in
            do {
                try player.prepare(sound: name)
                return nil
            } catch {
                return String(describing: error)
            }
        })
    }

    func reload() {
        // Afresh every time: a sound file edited since the last load is read
        // again, and one no rule names any more is released.
        player.forgetPreparedSounds()
        let check = soundCheck

        do {
            (rules, status) = RuleStoreStatus.load(try file.read().data, availableSounds: check.available,
                                                   unplayable: check.unplayable)
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
