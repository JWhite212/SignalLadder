import XCTest
@testable import NotificationCore

/// The editor keeps the version the file declares, so that a rule the loader
/// refuses for it does not look clean in the editor, and Save can fix it (M5
/// ruling 2). Fixtures are invented text, never captured content (§10.1).
final class EditorFileVersionTests: XCTestCase {
    private let teams = #""condition": {"field": "app", "op": "equals", "value": "Microsoft Teams"}"#
    private let daniel = "com.apple.voice.compact.en-GB.Daniel"

    private func file(version: Int, _ rules: String) -> Data {
        Data("{\"version\": \(version), \"rules\": [\(rules)]}".utf8)
    }

    private var plain: String { #"{"name": "Plain", \#(teams)}"# }
    private var withAlert: String { #"{"name": "Alerting", \#(teams), "alert": {"sound": "Glass"}}"# }
    private var withSpeech: String { #"{"name": "Speaking", \#(teams), "alert": {"speak": {"voice": "\#(daniel)"}}}"# }
    private var withLadder: String {
        #"{"name": "Climbing", \#(teams), "alert": "silent", "escalation": {"tier2": {"delaySeconds": 10}}}"#
    }

    /// The loader's words for each gate, as they stand.
    private let alertGate = "alerts need \"version\": 2 — an older SignalLadder reading this file would silently drop every alert in it"
    private let speechGate = "speech needs \"version\": 3 — an older SignalLadder reading this file would reject the rule without saying why"
    private let ladderGate = "escalation needs \"version\": 4 — an older SignalLadder reading this file would reject the rule without saying why"

    /// Thrown, so that a test whose fixture did not load as one editable rule
    /// at least fails on its own, and does not index into an empty array.
    private struct NotEditable: Error {}

    private func document(_ data: Data?, file: StaticString = #filePath, line: UInt = #line) throws
        -> (rules: [Rule], version: Int?) {
        guard case .editable(let rules, let version) = RulesDocument.load(data), !rules.isEmpty else {
            XCTFail("expected an editable document holding a rule", file: file, line: line)
            throw NotEditable()
        }
        return (rules, version)
    }

    /// What the editor reports for each rule of a file, exactly as the model
    /// asks: judged by the file's version while a rule is as it was loaded.
    private func editorProblems(_ data: Data, sounds: RuleSetCodec.SoundCheck = .none) throws -> [[String]] {
        let (rules, version) = try document(data)
        return rules.map {
            RulesDocument.problems(in: $0, sounds: sounds,
                                   fileVersion: RulesDocument.keptVersion(for: $0, loaded: rules, fileVersion: version))
        }
    }

    // MARK: - What the editor reports for a rule unchanged since load

    func testAnUnchangedRuleIsReportedForEachGateInTheLoadersWords() throws {
        XCTAssertEqual(try editorProblems(file(version: 1, withAlert)), [[alertGate]])
        XCTAssertEqual(try editorProblems(file(version: 2, withSpeech)), [[speechGate]])
        XCTAssertEqual(try editorProblems(file(version: 3, withLadder)), [[ladderGate]])
    }

    func testARuleThatNeedsMoreThanOneVersionIsToldTheNewest() throws {
        // Speech and a ladder in a version 1 file: one message, naming 4.
        let both = #"{"name": "Both", \#(teams), "alert": {"speak": {"voice": "\#(daniel)"}}, "escalation": {"tier2": {}}}"#
        XCTAssertEqual(try editorProblems(file(version: 1, both)), [[ladderGate]])
    }

    func testAFileThatDeclaresEnoughReportsNoGate() throws {
        XCTAssertEqual(try editorProblems(file(version: 2, withAlert)), [[]])
        XCTAssertEqual(try editorProblems(file(version: 3, withSpeech)), [[]])
        XCTAssertEqual(try editorProblems(file(version: 4, withLadder)), [[]])
        XCTAssertEqual(try editorProblems(file(version: 1, plain)), [[]])
    }

    func testARuleTheDraftChangedOrAddedIsReportedNoGate() throws {
        // A save writes it at the version it needs.
        let (rules, version) = try document(file(version: 3, withLadder))
        var edited = rules[0]
        edited.name = "Climbing, renamed"
        let added = Rule(name: "Added", condition: .field(.app, .equals, "x"),
                         alert: .silent, escalation: Escalation(tier2: PanelAlert()))
        var copy = rules[0]
        copy.id = UUID()
        for rule in [edited, added, copy] {
            let kept = RulesDocument.keptVersion(for: rule, loaded: rules, fileVersion: version)
            XCTAssertNil(kept, rule.name)
            XCTAssertEqual(RulesDocument.problems(in: rule, sounds: .none, fileVersion: kept), [], rule.name)
        }
        XCTAssertEqual(RulesDocument.keptVersion(for: rules[0], loaded: rules, fileVersion: version), 3,
                       "the rule exactly as loaded keeps the file's")
    }

    func testWhatTheDraftChangedIsWrittenAtTheVersionItNeeds() throws {
        let (rules, _) = try document(file(version: 3, withLadder))
        var edited = rules
        edited[0].name = "Climbing, renamed"
        let written = try RuleSetCodec.encode(edited)
        let (loaded, status) = RuleStoreStatus.load(written, availableSounds: nil, unplayable: nil, availableVoices: nil)
        XCTAssertEqual(status, .loaded(enabled: 1, disabled: 0), "the loader accepts what the editor wrote")
        XCTAssertEqual(loaded, edited)
        XCTAssertEqual(try document(written).version, 4)
    }

    func testARuleThatIsEditedAndThenRevertedIsJudgedByTheFileAgain() throws {
        // Revert puts the loaded rules back with the version they came with, so
        // the gate returns for a rule that is as the file holds it.
        let (rules, version) = try document(file(version: 3, withLadder))
        var draft = rules
        draft[0].isEnabled = false
        XCTAssertNil(RulesDocument.keptVersion(for: draft[0], loaded: rules, fileVersion: version))
        draft = rules
        XCTAssertEqual(RulesDocument.keptVersion(for: draft[0], loaded: rules, fileVersion: version), 3)
        XCTAssertEqual(RulesDocument.problems(in: draft[0], sounds: .none, fileVersion: 3), [ladderGate])
    }

    // MARK: - The editor and the loader agree

    func testTheEditorAndTheLoaderAgreeOnEveryFileInATable() throws {
        let table: [(version: Int, rules: String)] = [
            (1, plain), (1, withAlert), (1, withSpeech), (1, withLadder), (1, "\(plain), \(withAlert), \(withLadder)"),
            (2, withAlert), (2, withSpeech), (2, withLadder), (2, "\(withAlert), \(withSpeech)"),
            (3, withAlert), (3, withSpeech), (3, withLadder), (3, "\(withSpeech), \(withLadder), \(plain)"),
            (4, withAlert), (4, withSpeech), (4, withLadder),
            // A gate beside a fault of another kind, and beside a clean rule.
            (1, #"{"name": "Loud", \#(teams), "alert": {"sound": "Glass", "gainDB": 100}}, \#(plain)"#),
            (3, #"{"name": "", \#(teams), "alert": "silent", "escalation": {"tier2": {"delaySeconds": 0}}}"#),
            (2, #"{"name": "Wrong sound", \#(teams), "alert": {"sound": "Glas"}}, \#(withLadder)"#),
        ]
        let sounds = RuleSetCodec.SoundCheck(available: ["Glass"], unplayable: nil, voices: [daniel], shortcuts: nil)
        var gated = 0
        for (version, rules) in table {
            let data = file(version: version, rules)
            let (_, status) = RuleStoreStatus.load(data, availableSounds: ["Glass"], unplayable: nil,
                                                   availableVoices: [daniel])
            let (loaded, _) = try document(data)
            let fromEditor = zip(loaded.indices, try editorProblems(data, sounds: sounds)).compactMap { index, problems in
                problems.isEmpty ? nil
                    : RuleSetCodec.Problem(index: index, name: loaded[index].name,
                                           reason: problems.joined(separator: "; ")).description
            }
            XCTAssertEqual(fromEditor, status.detail, "version \(version): \(rules)")
            if status.detail.contains(where: { $0.contains("need \"version\"") || $0.contains("needs \"version\"") }) {
                gated += 1
            }
        }
        XCTAssertGreaterThan(gated, 8, "the table does hold the gates it is meant to compare")
    }

    // MARK: - The version travels with the rules

    func testLoadingReturnsTheVersionItReadForAFileAtEachVersionAndNoneForNoFile() throws {
        // With an id, so that two loads of one file hold the same rule.
        let identified = #"{"id": "1E2F3A4B-5C6D-4E7F-8A9B-0C1D2E3F4A5B", "name": "Plain", \#(teams)}"#
        for version in 1...4 {
            let data = file(version: version, identified)
            XCTAssertEqual(RulesDocument.load(data), .editable(try document(data).rules, fileVersion: version))
            XCTAssertEqual(try document(data).version, version)
        }
        XCTAssertEqual(RulesDocument.load(nil), .editable([], fileVersion: nil))
        XCTAssertEqual(RulesDocument.load(file(version: 9, plain)), .readOnly(.newerVersion(9)),
                       "a file that cannot be edited carries no version")
    }

    func testAfterASaveTheKeptVersionIsTheVersionWrittenAndTheOldGateIsGone() throws {
        // What `didSave` does: encode the rules, read the file back.
        let (before, oldVersion) = try document(file(version: 3, withLadder))
        XCTAssertEqual(RulesDocument.problems(in: before[0], sounds: .none,
                                              fileVersion: RulesDocument.keptVersion(for: before[0], loaded: before, fileVersion: oldVersion)),
                       [ladderGate], "reported before the save")

        let (after, newVersion) = try document(try RuleSetCodec.encode(before))
        XCTAssertEqual(newVersion, 4)
        XCTAssertEqual(after, before)
        XCTAssertEqual(RulesDocument.problems(in: after[0], sounds: .none,
                                              fileVersion: RulesDocument.keptVersion(for: after[0], loaded: after, fileVersion: newVersion)),
                       [], "and by nothing once the file holds it at 4")
        XCTAssertEqual(RulesDocument.problems(in: after[0], sounds: .none, fileVersion: oldVersion), [ladderGate],
                       "a version left over from the old file would report a gate the file now satisfies")

        var edited = after[0]
        edited.name = "Edited after the save"
        XCTAssertNil(RulesDocument.keptVersion(for: edited, loaded: after, fileVersion: newVersion),
                     "a rule edited after that is judged as one the draft changed")
    }

    // MARK: - Save is reachable for it

    func testFileNeedsRewriting() throws {
        let (alerting, _) = try document(file(version: 1, withAlert))
        let (ladder, _) = try document(file(version: 3, withLadder))
        XCTAssertFalse(RulesDocument.fileNeedsRewriting(rules: ladder, fileVersion: nil), "no file version")
        XCTAssertFalse(RulesDocument.fileNeedsRewriting(rules: ladder, fileVersion: 4), "declares what the rules need")
        XCTAssertFalse(RulesDocument.fileNeedsRewriting(rules: alerting, fileVersion: 4), "declares more than they need")
        XCTAssertTrue(RulesDocument.fileNeedsRewriting(rules: ladder, fileVersion: 3), "a version 3 file holding a ladder")
        XCTAssertTrue(RulesDocument.fileNeedsRewriting(rules: alerting, fileVersion: 1))
        XCTAssertTrue(RulesDocument.fileNeedsRewriting(rules: ladder + alerting, fileVersion: 3))
        XCTAssertFalse(RulesDocument.fileNeedsRewriting(rules: [], fileVersion: 1))

        let (saved, version) = try document(try RuleSetCodec.encode(ladder))
        XCTAssertFalse(RulesDocument.fileNeedsRewriting(rules: saved, fileVersion: version),
                       "false for the same rules once they are encoded and loaded again")
    }

    func testARuleIsHeldBackByTheFileVersionOnlyWhenNothingElseIsWrongWithIt() throws {
        // Held back: the loader refuses it for what its file declares, and a
        // save, which writes the version the rules need, would put it into effect.
        let sounds = RuleSetCodec.SoundCheck(available: ["Glass"], unplayable: nil, voices: nil, shortcuts: nil)
        func heldBack(_ rule: Rule, loaded: [Rule], version: Int?) -> Bool {
            RulesDocument.isHeldBackByFileVersion(rule, loaded: loaded, fileVersion: version, sounds: sounds)
        }

        let (ladder, version) = try document(file(version: 3, withLadder))
        XCTAssertTrue(heldBack(ladder[0], loaded: ladder, version: version), "a ladder in a version 3 file")
        let (alerting, alertVersion) = try document(file(version: 1, withAlert))
        XCTAssertTrue(heldBack(alerting[0], loaded: alerting, version: alertVersion), "an alert in a version 1 file")

        XCTAssertFalse(heldBack(ladder[0], loaded: ladder, version: 4), "the file declares what it needs")
        XCTAssertFalse(heldBack(ladder[0], loaded: ladder, version: nil), "no file version")
        let (clean, cleanVersion) = try document(file(version: 3, plain))
        XCTAssertFalse(heldBack(clean[0], loaded: clean, version: cleanVersion), "a rule the file's version does not touch")

        var renamed = ladder[0]
        renamed.name = "Climbing, renamed"
        XCTAssertFalse(heldBack(renamed, loaded: ladder, version: version), "a save writes a changed rule at the version it needs")
        let added = Rule(name: "Added", condition: .field(.app, .equals, "x"),
                         alert: .silent, escalation: Escalation(tier2: PanelAlert()))
        XCTAssertFalse(heldBack(added, loaded: ladder, version: version), "and an added one")

        // A fault of another kind outlives the save, so the version is not all.
        let typo = #"{"name": "Typo", \#(teams), "alert": {"sound": "Glas"}, "escalation": {"tier2": {"delaySeconds": 10}}}"#
        let (typos, typoVersion) = try document(file(version: 3, typo))
        XCTAssertFalse(heldBack(typos[0], loaded: typos, version: typoVersion), "a sound that is not there as well")
        XCTAssertTrue(RulesDocument.isHeldBackByFileVersion(typos[0], loaded: typos, fileVersion: typoVersion, sounds: .none),
                      "which is a fault only when the sounds are checked")
    }

    func testSaveIsOfferedForAnEditAndForAFileThatDeclaresTooLittleAndOtherwiseNot() throws {
        let (rules, version) = try document(file(version: 3, withLadder))
        var edited = rules
        edited[0].name = "Edited"
        XCTAssertTrue(RulesDocument.canSave(draft: edited, loaded: rules, fileVersion: version), "an edit")
        XCTAssertTrue(RulesDocument.canSave(draft: rules, loaded: rules, fileVersion: version),
                      "an unedited rule in a file that declares too little")
        XCTAssertFalse(RulesDocument.canSave(draft: rules, loaded: rules, fileVersion: 4),
                       "an unedited rule in a file that declares enough")
        XCTAssertFalse(RulesDocument.canSave(draft: edited, loaded: edited, fileVersion: 4),
                       "a draft edited and then edited back to equality, in a file that declares enough")
        XCTAssertTrue(RulesDocument.canSave(draft: rules, loaded: rules, fileVersion: 3),
                      "edited and edited back, in a file that declares too little: still true")
        XCTAssertFalse(RulesDocument.canSave(draft: rules, loaded: rules, fileVersion: nil),
                       "no file version and nothing edited")
        XCTAssertTrue(RulesDocument.canSave(draft: edited, loaded: rules, fileVersion: nil), "no file, an edit")
    }

    func testTheSaveBarSaysWhatSaveWillWriteWithBothVersionsAndNoRulesName() throws {
        let (rules, version) = try document(file(version: 3, withLadder))
        let state = EditorText.saveState(draft: rules, saved: rules, fileIsInEffect: true, fileVersion: version,
                                         broken: { _ in true })
        XCTAssertEqual(state, .fileNeedsNewerVersion(declared: 3, needed: 4))
        let said = EditorText.saveState(state)
        XCTAssertEqual(said.text, "rules.json declares version 3 but holds a rule that needs 4, so that rule is not running — Save writes version 4 and puts it into effect")
        XCTAssertTrue(said.isWarning)

        // The numbers are the file's and the rules', whichever they are.
        let (alerting, alertVersion) = try document(file(version: 1, withAlert))
        XCTAssertEqual(EditorText.saveState(draft: alerting, saved: alerting, fileIsInEffect: true, fileVersion: alertVersion,
                                            broken: { _ in false }),
                       .fileNeedsNewerVersion(declared: 1, needed: 2))
    }

    func testTheSaveBarSaysWhatItAlwaysDidForEveryOtherCase() throws {
        let (rules, _) = try document(file(version: 4, withLadder))
        var edited = rules
        edited[0].name = "Edited"
        // Unsaved wins: the draft differs, and the sentence for that is true.
        let (old, oldVersion) = try document(file(version: 3, withLadder))
        XCTAssertEqual(EditorText.saveState(draft: edited, saved: old, fileIsInEffect: true, fileVersion: oldVersion,
                                            broken: { _ in true }), .unsaved)
        XCTAssertEqual(EditorText.saveState(draft: rules, saved: rules, fileIsInEffect: false, fileVersion: 4,
                                            broken: { _ in false }), .fileNotInEffect)
        XCTAssertEqual(EditorText.saveState(draft: rules, saved: rules, fileIsInEffect: true, fileVersion: 4,
                                            broken: { _ in true }), .inEffect(notRunning: 1))
        XCTAssertEqual(EditorText.saveState(draft: rules, saved: rules, fileIsInEffect: true, fileVersion: nil,
                                            broken: { _ in false }), .inEffect(notRunning: 0))
        XCTAssertEqual(EditorText.saveState(.unsaved).text, EditorText.unsavedChanges)
        XCTAssertEqual(EditorText.saveState(.inEffect(notRunning: 0)).text, "Saved and in effect")
    }

    func testAFileThatDeclaresTooLittleSaysSoBeforeSayingItIsOutOfEffect() throws {
        // A reload of that file would refuse the rule again, so Put into Effect
        // is not what the bar offers; Save is.
        let (rules, version) = try document(file(version: 3, withLadder))
        XCTAssertEqual(EditorText.saveState(draft: rules, saved: rules, fileIsInEffect: false, fileVersion: version,
                                            broken: { _ in true }),
                       .fileNeedsNewerVersion(declared: 3, needed: 4))
    }
}
