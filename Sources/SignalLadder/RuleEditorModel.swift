// Sources/SignalLadder/RuleEditorModel.swift
import AVFoundation
import Foundation
import Combine
import NotificationCore
import AlertAudio
import RuleStorage
import ShortcutRunner

/// The rule editor's state: the draft, the file it was made from, and the
/// notifications held in memory to try it on.
///
/// Thin by design. What the file means, what a rule's problems are, what the
/// dry-run says and how a condition is edited are all tested functions in
/// `NotificationCore`; how the file is written is `RulesFile`. This holds the
/// draft and calls them.
///
/// An unsaved draft never governs a real alert: nothing here reaches the
/// pipeline until a save succeeds, and then `onSaved` applies it at once.
@MainActor
final class RuleEditorModel: ObservableObject {
    /// The draft: every rule, in priority order.
    @Published var rules: [Rule] = []
    @Published var selection: Rule.ID?
    /// Why the file cannot be edited here, or nil when it can.
    @Published private(set) var readOnly: RulesDocument.ReadOnlyReason?
    /// The notifications held in memory, newest first — the dry-run's ground.
    @Published private(set) var captures: [InspectorEntry] = []
    /// The notification the editor was last opened from, offered for
    /// "Add Condition from This Notification".
    @Published private(set) var source: CapturedNotification?

    /// Puts the rules in rules.json into effect — after a save, or when the
    /// file was edited by hand and not yet reloaded.
    var onApply: (() -> Void)?

    /// Told the Shortcut's name when a test of it from the editor has started
    /// it, so a held failure of that Shortcut can go.
    var onShortcutStarted: ((String) -> Void)?

    /// How the last Shortcut test ended, with the name it was for. Held here
    /// and not in a view, so switching rules while a test runs is safe, and
    /// shown only beside a field that still holds that name.
    @Published private(set) var shortcutTest: ShortcutTest.Report?
    /// Whether a test is running, so a second press cannot page twice.
    @Published private(set) var isTestingShortcut = false

    /// The rules the file holds and the version it declares, which only
    /// `show(_:)` sets, and in one assignment, so the two cannot part: a
    /// version kept from another file would report an old gate problem
    /// against a file that now satisfies it, or none against one that does not.
    private struct LoadedDocument {
        var rules: [Rule] = []
        /// nil for no file, and for one that could not be shown.
        var fileVersion: Int?
    }

    private var loadedDocument = LoadedDocument()
    var loadedRules: [Rule] { loadedDocument.rules }
    private var loaded = RulesFile.Snapshot(data: nil)
    private let store: RuleStore
    private var sounds = RuleSetCodec.SoundCheck.none
    /// Whether each sound can play, remembered for the session so typing does
    /// not re-read the sound folders on every keystroke. Cleared on reload.
    private var playability: [String: String?] = [:]

    init(store: RuleStore) {
        self.store = store
    }

    /// Whether the draft differs from the file. What Revert follows.
    var hasUnsavedChanges: Bool { readOnly == nil && rules != loadedRules }

    /// Whether Save is offered: an edit, or a file that declares too little
    /// for a rule it holds, which no edit would otherwise let the user fix
    /// (M5 ruling 2). Decided in `RulesDocument`, where it is tested.
    var canSave: Bool {
        readOnly == nil
            && RulesDocument.canSave(draft: rules, loaded: loadedRules, fileVersion: loadedDocument.fileVersion)
    }

    /// Whether what the editor shows is what the app is running.
    var saveState: EditorText.SaveState {
        EditorText.saveState(draft: rules, saved: loadedRules,
                                    fileIsInEffect: loaded.fingerprint == store.appliedFingerprint,
                                    fileVersion: loadedDocument.fileVersion,
                                    broken: { [unowned self] in !self.problems(in: $0).isEmpty })
    }

    func putIntoEffect() {
        onApply?()
    }
    var isEditable: Bool { readOnly == nil }
    var selectedIndex: Int? { rules.firstIndex { $0.id == selection } }

    // MARK: - Loading

    /// Reads the file afresh and discards the draft.
    func reloadFromDisk() {
        refreshSounds()
        do {
            loaded = try store.file.read()
        } catch {
            show(.readOnly(.unreadable(String(describing: error))))
            return
        }
        show(RulesDocument.load(loaded.data))
    }

    func refreshCaptures(from buffer: CaptureRingBuffer) {
        captures = buffer.entries
    }

    private func show(_ document: RulesDocument) {
        switch document {
        case .editable(let rules, let fileVersion):
            readOnly = nil
            self.rules = rules
            loadedDocument = LoadedDocument(rules: rules, fileVersion: fileVersion)
        case .readOnly(let reason):
            readOnly = reason
            rules = []
            loadedDocument = LoadedDocument()
        }
        if selectedIndex == nil { selection = rules.first?.id }
    }

    private func refreshSounds() {
        let base = store.soundCheck
        playability = [:]
        sounds = RuleSetCodec.SoundCheck(available: base.available, unplayable: { [weak self] name in
            let key = name.lowercased()
            if let known = self?.playability[key] { return known }
            let result = base.unplayable?(name)
            self?.playability[key] = result
            return result
        }, voices: base.voices, shortcuts: base.shortcuts)
    }

    // MARK: - Saving

    enum SaveResult {
        case saved
        /// The file changed since it was read; nothing was written.
        case conflict(RulesChange)
        case failed(String)
    }

    func save() -> SaveResult {
        do {
            switch try store.file.save(try RuleSetCodec.encode(rules), expecting: loaded.fingerprint) {
            case .saved:
                didSave()
                return .saved
            case .changedOnDisk(let current):
                return .conflict(RulesChange.between(loaded.data, current.data))
            }
        } catch {
            return .failed(String(describing: error))
        }
    }

    /// The answer to a conflict: overwrite what is on disk now. It is kept
    /// under its own dated name.
    func saveReplacingDisk() -> SaveResult {
        do {
            try store.file.saveReplacing(try RuleSetCodec.encode(rules), at: Date())
            didSave()
            return .saved
        } catch {
            return .failed(String(describing: error))
        }
    }

    private func didSave() {
        // Read back what was written, so the draft, the fingerprint and the
        // ids the save wrote into the file all agree.
        reloadFromDisk()
        onApply?()
    }

    func revert() {
        rules = loadedRules
        if selectedIndex == nil { selection = rules.first?.id }
    }

    // MARK: - The list

    func addRule() {
        let rule = Rule(name: "New rule", condition: .blank, isEnabled: false)
        rules.insert(rule, at: (selectedIndex.map { $0 + 1 }) ?? rules.count)
        selection = rule.id
    }

    /// A copy starts switched off: it is new, and unproven.
    func duplicate(_ id: Rule.ID) {
        guard let index = rules.firstIndex(where: { $0.id == id }) else { return }
        var copy = rules[index]
        copy.id = UUID()
        copy.name += " (copy)"
        copy.isEnabled = false
        rules.insert(copy, at: index + 1)
        selection = copy.id
    }

    func delete(_ id: Rule.ID) {
        guard let index = rules.firstIndex(where: { $0.id == id }) else { return }
        rules.remove(at: index)
        if selection == id { selection = rules.indices.contains(index) ? rules[index].id : rules.last?.id }
    }

    func move(from source: IndexSet, to destination: Int) {
        rules.move(fromOffsets: source, toOffset: destination)
    }

    /// Moves a rule to `index`, for "Move above".
    func move(_ id: Rule.ID, to index: Int) {
        guard let from = rules.firstIndex(where: { $0.id == id }), rules.indices.contains(index) else { return }
        rules.insert(rules.remove(at: from), at: index)
    }

    /// A new rule from a real notification (§7.3), placed so it is not born
    /// shadowed. Only into an editable document: a read-only one says why.
    func makeRule(from entry: InspectorEntry) {
        source = entry.captured
        guard isEditable else { return }
        let rule = RuleSeed.rule(from: entry.captured)
        rules.insert(rule, at: RuleSeed.insertionIndex(for: entry.captured, in: rules, sounds: sounds))
        selection = rule.id
    }

    // MARK: - What the tested core says

    /// A rule exactly as the file holds it is judged by the file's version,
    /// as the loader judges it; one the draft has changed or added is not,
    /// since a save writes it at the version it needs.
    func problems(in rule: Rule) -> [String] {
        let version = RulesDocument.keptVersion(for: rule, loaded: loadedRules, fileVersion: loadedDocument.fileVersion)
        return RulesDocument.problems(in: rule, sounds: sounds, fileVersion: version)
    }

    /// What the loader warns about a rule that stays in effect, as advice
    /// beside the field it is about, and never as a problem (M5 ruling 21).
    func warnings(in rule: Rule) -> [String] {
        RuleWarnings.sentences(for: rule, sounds: sounds)
    }

    func dryRun(for id: Rule.ID) -> DryRun? {
        guard let index = rules.firstIndex(where: { $0.id == id }) else { return nil }
        return DryRun.report(forRuleAt: index, in: rules, over: captures, sounds: sounds)
    }

    /// Whether this rule's dry-run describes something not yet saved,
    /// including a move made with the dry-run's own Move Above, and a rule the
    /// loader is refusing for the version its file declares, which a save fixes.
    func isUnsaved(_ id: Rule.ID) -> Bool {
        DryRun.isUnsaved(id, draft: rules, saved: loadedRules, fileVersion: loadedDocument.fileVersion, sounds: sounds)
    }

    /// Lets go of the notification the editor was opened from. Called when
    /// the window closes, so its text is held no longer than it is useful.
    func forgetSource() {
        source = nil
    }

    var availableSounds: [String] {
        (sounds.available ?? []).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    // MARK: - Trying a sound

    /// Plays the rule's sound at the rule's gain. Returns why it could not,
    /// or nil when it played.
    func testSound(_ name: String, gainDB: Double) -> String? {
        do {
            try store.player.testSound(name, ruleGainDB: gainDB)
            return nil
        } catch {
            return String(describing: error)
        }
    }

    var outputIsSilent: Bool { OutputState.current().isEffectivelySilent }

    /// The sound a new sound alert starts with.
    var defaultSound: String {
        availableSounds.first { $0.caseInsensitiveCompare("Glass") == .orderedSame } ?? availableSounds.first ?? "Glass"
    }

    // MARK: - Trying a Shortcut

    /// Runs the Shortcut named `name` with a plainly marked test notification
    /// of its own, which really runs it, and publishes how it ended with the
    /// name it was for. A start also tells `onShortcutStarted`, since a launch
    /// of that Shortcut is what clears a held failure of it. Does nothing when
    /// the button would not have been offered. It never touches the audio
    /// graph, so it is not refused while an alert plays.
    func testShortcut(name: String) {
        guard ShortcutTest.canRun(name: name, pending: isTestingShortcut) else { return }
        isTestingShortcut = true
        store.shortcuts.run(name: name, fields: ShortcutRunner.Fields(AlertEditing.shortcutTestNotification)) {
            [weak self] outcome in
            guard let self else { return }
            // Listed again after any result, since the list is remembered per
            // check: a Shortcut made while the editor was open would read
            // "not found" until Reload Rules, and with no menu of Shortcuts
            // this is how a fixed name stops being reported.
            refreshSounds()
            switch outcome {
            case .launched:
                shortcutTest = ShortcutTest.Report(name: name, outcome: .started)
                onShortcutStarted?(name)
            case .failed(let reason):
                shortcutTest = ShortcutTest.Report(name: name, outcome: .failed(reason))
            }
            isTestingShortcut = false
        }
    }

    // MARK: - Voices

    /// An installed voice, as the picker lists it. Enhanced voices say so in
    /// their own name.
    struct Voice: Hashable, Identifiable {
        let id: String
        let name: String
        let language: String
    }

    /// Every installed voice (§5.9). `speechVoices()` never returns a Siri
    /// voice, so none is offered. Not filtered by language: a notification's
    /// text is in whatever language its app wrote it. The Mac's own language
    /// comes first.
    var availableVoices: [Voice] {
        let own = AVSpeechSynthesisVoice.currentLanguageCode()
        return AVSpeechSynthesisVoice.speechVoices()
            .map { Voice(id: $0.identifier, name: $0.name, language: $0.language) }
            .sorted {
                if ($0.language == own) != ($1.language == own) { return $0.language == own }
                if $0.language != $1.language { return $0.language < $1.language }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    /// The voice new speech starts with: the Mac's own default, else the first
    /// installed. Never empty while any voice is installed, since an empty
    /// voice is a problem at load.
    var defaultVoice: String {
        let installed = availableVoices
        if let own = AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())?.identifier,
           installed.contains(where: { $0.id == own }) {
            return own
        }
        return installed.first?.id ?? ""
    }

    /// Warms and measures a voice when it is chosen, so Test Speech usually
    /// finds it ready.
    func prepareVoice(_ identifier: String) {
        Task { [player = store.player] in try? await player.prepareSpeech(voiceIdentifier: identifier) }
    }

    /// Says the rule's template, filled from a made-up notification, at the
    /// rule's voice, rate, pitch and gain. Returns why it could not, or nil.
    func testSpeech(_ speech: SpeechAction) -> String? {
        do {
            try store.player.testSpeech(speech.rendered(for: AlertEditing.sampleNotification),
                                        voiceIdentifier: speech.voiceIdentifier, rate: speech.rate,
                                        pitchMultiplier: speech.pitchMultiplier, ruleGainDB: speech.gainDB)
            return nil
        } catch {
            return String(describing: error)
        }
    }
}
