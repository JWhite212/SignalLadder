// Sources/SignalLadder/RuleStore.swift
import AVFoundation
import Foundation
import NotificationCore
import AlertAudio
import RuleStorage
import ShortcutRunner

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
    /// The rules in effect that name a Shortcut the Shortcuts app does not
    /// list. Beside `status`, and not part of it: those rules are in effect,
    /// and tier 4 still tries the name when it fires (M5 ruling 21).
    private(set) var warnings: [RuleWarning] = []
    /// Why the editor must not touch the file as it was last read, when it must not
    /// (`RulesDocument.readOnlyReason`), made from the same read as `status`, so the two
    /// cannot be from different files. nil for a file the editor can edit and for no
    /// file. The first run's step for the first rule reads it, as the editor reads the
    /// same document when it opens (M5 plan, Task 8).
    private(set) var readOnlyReason: RulesDocument.ReadOnlyReason?
    /// The fingerprint of the file the rules in effect were read from — nil
    /// when it could not be read, and the earlier file's while a reload that
    /// could not use it keeps that file's rules. The editor compares it with
    /// the file it shows, so it never calls a hand edit that was not reloaded
    /// "in effect".
    private(set) var appliedFingerprint: RulesFile.Fingerprint?
    let file: RulesFile
    var fileURL: URL { file.url }

    /// What sound names a rule may use. Checked on every reload, so a sound the
    /// user adds is accepted without restarting, and a misspelt one is
    /// reported when the file loads rather than at the incident.
    let sounds: SoundLibrary

    /// Prepares each rule's sound as the rules load, so a file that cannot
    /// play is reported now, and an alert never waits on the disk.
    let player: AlertPlayer

    /// Runs a tier 4 Shortcut. Held here beside the player so the rule editor
    /// reaches it the way it reaches the player, to try one (M4 Task 6).
    let shortcuts: ShortcutRunner

    init(fileURL: URL = RuleStore.defaultFileURL, sounds: SoundLibrary, player: AlertPlayer,
         shortcuts: ShortcutRunner) {
        self.file = RulesFile(url: fileURL)
        self.sounds = sounds
        self.player = player
        self.shortcuts = shortcuts
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
    /// user adds is found without restarting, and asks for the installed
    /// voices afresh, so one added in System Settings is too, and lists the
    /// user's Shortcuts afresh, so a tier 4 naming one that is not there is
    /// warned about now, not found out when it is needed to page someone (M4
    /// plan, ruling 11; M5 ruling 21). Listing runs `shortcuts list`, about 10
    /// ms, only once a rule names a Shortcut, and at most once per check; it
    /// gives up after a second, and the check is then skipped.
    var soundCheck: RuleSetCodec.SoundCheck {
        RuleSetCodec.SoundCheck(available: sounds.availableNames, unplayable: { [player] name in
            do {
                try player.prepare(sound: name)
                return nil
            } catch {
                return String(describing: error)
            }
        }, voices: Set(AVSpeechSynthesisVoice.speechVoices().map(\.identifier)),
        shortcuts: { ShortcutRunner.installedShortcuts() })
    }

    /// Works out the warnings again from the rules in effect, as `reload()` does
    /// from the rules it has just read, and says whether they changed (1.1 plan,
    /// Ruling 15). It reads no file and leaves the rules, the status, the
    /// prepared sounds and the warmed voices as they are: a reload stays the one
    /// thing that changes those. Asked at each self-test, on waking and when on
    /// call begins, so that a Shortcut renamed or a sound moved since the last
    /// load is told before tier 4 needs it.
    func recheckWarnings() -> Bool {
        let fresh = RuleWarnings.warnings(for: rules, sounds: soundCheck)
        guard fresh != warnings else { return false }
        warnings = fresh
        return true
    }

    func reload() {
        // Afresh every time: a sound file edited since the last load is read
        // again, and one no rule names any more is released.
        player.forgetPreparedSounds()
        let check = soundCheck

        let read: (rules: [Rule], status: RuleStoreStatus)
        let fingerprint: RulesFile.Fingerprint?
        do {
            let snapshot = try file.read()
            fingerprint = snapshot.fingerprint
            read = RuleStoreStatus.load(snapshot.data)
            readOnlyReason = RulesDocument.load(snapshot.data).readOnlyReason
        } catch {
            fingerprint = nil
            // Present but unopenable — reported, never treated as "no rules
            // file", which would read as the user simply not having written
            // any yet.
            read = ([], .unreadable(String(describing: error)))
            // As the editor reads a file it cannot open (`RuleEditorModel.reloadFromDisk`).
            readOnlyReason = .unreadable(String(describing: error))
        }
        // A file that cannot be used does not take away rules that were
        // working: they stay in effect, and the status says the file is not.
        (rules, status) = RuleStoreStatus.reloaded(read, replacing: rules)
        // While they are kept, the file they were read from is the earlier one.
        if !status.keepsEarlierRules { appliedFingerprint = fingerprint }
        // With the same check, so the Shortcuts are listed once per load, and
        // the sounds of rules that were kept are prepared again.
        warnings = RuleWarnings.warnings(for: rules, sounds: check)
        warmVoices()
    }

    /// Measures every voice a rule speaks with, on any tier, in the
    /// background, so its first alert is heard within tens of milliseconds
    /// rather than the seconds a cold start takes, and at its measured level.
    /// `reload` does not wait for it: it runs at launch, on Reload Rules and
    /// on every save.
    private func warmVoices() {
        var seen = Set<String>()
        let alerts = rules.flatMap(\.alertActions)
        let voices = alerts.compactMap { $0.speech?.voiceIdentifier }.filter { seen.insert($0).inserted }
        guard !voices.isEmpty else { return }
        Task { [player] in
            for voice in voices { try? await player.prepareSpeech(voiceIdentifier: voice) }
        }
    }

    /// Writes the example file if, and only if, no file exists.
    @discardableResult
    func createExampleIfMissing() throws -> Bool {
        try file.createIfMissing(RuleSetCodec.encode([Rule.editingExample]))
    }
}
