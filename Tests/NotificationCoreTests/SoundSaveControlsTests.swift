import XCTest
@testable import NotificationCore

/// What the sound editor's save controls offer and what pressing them comes to (sound editor plan, Rulings 9, 11 and 12,
/// and Task 9): Save as New is the default and never replaces a sound, Save replaces the sound being edited only when it
/// is one of the user's own and asks first when a rule uses it, a macOS sound is always a copy, and nothing saves while
/// a check that stops a save stands.
final class SoundSaveControlsTests: XCTestCase {
    private let own: Set<String> = ["Alarm", "Klaxon", "Glass"]
    private let system: Set<String> = ["Glass", "Ping", "Basso"]

    private func controls(edited: String = "Alarm", typed: String = "Alarm 2", own: Set<String>? = nil,
                          system: Set<String>? = nil, isReady: Bool = true, isCatchingUp: Bool = false,
                          isSaving: Bool = false, isBlocked: Bool = false) -> SoundSaveControls {
        SoundSaveControls(editedName: edited, typedName: typed, ownSounds: own ?? self.own, macOSSounds: system ?? self.system,
                          isReady: isReady, isCatchingUp: isCatchingUp, isSaving: isSaving, isBlocked: isBlocked)
    }

    func testSaveIsNotOfferedForASoundWhoseNameIsTooLongToBeSetAsideWhileItIsReplaced() {
        // An added sound keeps its file's name, which may be more bytes than a saved one's: 66 accented letters
        // are 198 bytes as the folder stores them, one past the limit.
        let tooLong = String(repeating: "e\u{301}", count: SoundSaveNaming.longestNameBytes / 3 + 1)
        let fits = String(repeating: "e\u{301}", count: SoundSaveNaming.longestNameBytes / 3)
        let c = controls(edited: tooLong, typed: "Other", own: [tooLong, fits])
        XCTAssertFalse(c.offersSave)
        XCTAssertFalse(c.canSave)
        XCTAssertNil(c.saveStep(ruleCount: 0))
        XCTAssertFalse(c.allows(SoundSaveRequest(name: tooLong, replacing: true)))
        XCTAssertTrue(controls(edited: fits, typed: "Other", own: [tooLong, fits]).offersSave)
        XCTAssertFalse(SoundSaveNaming.canSaveOver(String(repeating: "\u{e9}", count: 66), ownSounds: [String(repeating: "\u{e9}", count: 66)], macOSSounds: []),
                       "typed as one letter each, 132 bytes, and stored as 198")
    }

    // MARK: - Save as New

    func testASoundIsSavedAsNewUnderANameNothingHas() {
        let c = controls(typed: "Alarm 2")
        XCTAssertTrue(c.canSaveAsNew)
        XCTAssertEqual(c.saveAsNewRequest, SoundSaveRequest(name: "Alarm 2", replacing: false))
        XCTAssertNil(c.nameNote, "a name that is free needs no word")
    }

    func testTheNameIsSavedWithItsSpacesTakenOffAsTheVerdictSaysAndNeverReplaces() {
        XCTAssertEqual(controls(typed: "  Night Bell  ").saveAsNewRequest, SoundSaveRequest(name: "Night Bell", replacing: false))
    }

    func testAnameOfASoundTheUserHasIsNotSavedAsNewAndSaysWhy() {
        let c = controls(typed: "klaxon")
        XCTAssertFalse(c.canSaveAsNew, "Save as New never takes the place of a sound")
        XCTAssertNil(c.saveAsNewRequest)
        XCTAssertEqual(c.nameNote, SoundEditorText.nameInUse("Klaxon", replaceable: false))
    }

    func testTheNameOfTheSoundBeingEditedPointsToSaveWhenItCanReplaceIt() {
        let c = controls(typed: "alarm")
        XCTAssertFalse(c.canSaveAsNew)
        XCTAssertEqual(c.nameNote, SoundEditorText.nameInUse("Alarm", replaceable: true))
    }

    func testTheNameOfTheSoundBeingEditedDoesNotPointToSaveWhenItCannotBeReplaced() {
        let c = controls(edited: "Ping", typed: "ping")
        XCTAssertEqual(c.nameNote, SoundEditorText.nameProblem(.macOSSound("Ping")), "macOS has it, so the name is refused")
        XCTAssertFalse(c.canSaveAsNew)
    }

    func testAMacOSNameIsRefusedEvenWhenTheUserHasASoundOfThatName() {
        let c = controls(typed: "Glass")
        XCTAssertFalse(c.canSaveAsNew)
        XCTAssertEqual(c.nameNote, SoundEditorText.nameProblem(.macOSSound("Glass")))
    }

    func testEveryProblemWithATypedNameIsSaidAndSavesNothing() {
        for (typed, problem) in [("", SoundSaveNaming.Problem.blank), ("   ", .blank), (".hidden", .startsWithDot),
                                 ("a/b", .unsafeCharacter), (String(repeating: "x", count: 101), .tooLong)] {
            let c = controls(typed: typed)
            XCTAssertFalse(c.canSaveAsNew, typed)
            XCTAssertNil(c.saveAsNewRequest, typed)
            XCTAssertEqual(c.nameNote, SoundEditorText.nameProblem(problem), typed)
        }
    }

    // MARK: - Save

    func testASoundOfTheUsersOwnCanBeSavedOver() {
        let c = controls(edited: "Alarm")
        XCTAssertTrue(c.offersSave)
        XCTAssertTrue(c.canSave)
    }

    func testAMacOSSoundIsNeverSavedOverAndIsToldItIsSavedAsACopy() {
        let c = controls(edited: "Ping", typed: "Ping 2")
        XCTAssertFalse(c.offersSave)
        XCTAssertFalse(c.canSave)
        XCTAssertNil(c.saveStep(ruleCount: 5))
        XCTAssertTrue(c.isMacOSSound)
        XCTAssertEqual(c.macOSNote, SoundEditorText.macOSCopyNote("Ping"))
        XCTAssertTrue(c.canSaveAsNew, "a copy is always possible")
    }

    func testASoundOfTheUsersThatMacOSAlsoHasIsNotSavedOver() {
        let c = controls(edited: "Glass", typed: "Glass 2")
        XCTAssertFalse(c.offersSave, "saving over it would take the place of macOS's for every rule that names it")
        XCTAssertTrue(c.isMacOSSound)
    }

    func testASoundThatIsNoLongerInTheFolderIsNotOfferedASaveOver() {
        let c = controls(edited: "Gone", typed: "Gone 2")
        XCTAssertFalse(c.offersSave)
        XCTAssertFalse(c.isMacOSSound)
        XCTAssertNil(c.macOSNote)
        XCTAssertNil(c.saveStep(ruleCount: 0))
    }

    func testAnOwnSoundNoRuleUsesIsSavedOverAtOnce() {
        XCTAssertEqual(controls(edited: "Alarm").saveStep(ruleCount: 0),
                       .save(SoundSaveRequest(name: "Alarm", replacing: true)))
    }

    func testAnOwnSoundARuleUsesIsAskedAboutFirstSayingHowManyRules() throws {
        let step = try XCTUnwrap(controls(edited: "Alarm").saveStep(ruleCount: 2))
        XCTAssertEqual(step, .ask(SoundSaveRequest(name: "Alarm", replacing: true),
                                  SoundEditorText.saveOverConfirmation("Alarm", ruleCount: 2)))
        guard case .ask(_, let confirmation) = step else { return XCTFail("asks") }
        XCTAssertTrue(confirmation.detail.hasPrefix("2 rules use it"), confirmation.detail)
        XCTAssertEqual(confirmation.buttons.first, EditorText.cancel, "Return keeps the sound")
        XCTAssertEqual(confirmation.proceed, SoundEditorText.saveOver)
    }

    func testOneRuleIsEnoughToAsk() {
        guard case .ask? = controls(edited: "Alarm").saveStep(ruleCount: 1) else { return XCTFail("asks") }
    }

    // MARK: - Nothing saves

    func testNothingSavesWhileAnythingStandsInTheWay() {
        let cases: [(String, SoundSaveControls)] = [
            ("not open", controls(isReady: false)),
            ("a save is under way", controls(isSaving: true)),
            ("a render is under way, so the checks are of the sound before", controls(isCatchingUp: true)),
            ("a check that stops a save stands", controls(isBlocked: true)),
        ]
        for (why, c) in cases {
            XCTAssertFalse(c.canSaveAsNew, why)
            XCTAssertFalse(c.canSave, why)
            XCTAssertNil(c.saveAsNewRequest, why)
            XCTAssertNil(c.saveStep(ruleCount: 0), why)
            XCTAssertFalse(c.mayBeSaved, why)
        }
        XCTAssertTrue(controls().mayBeSaved)
    }

    // MARK: - The name suggested

    func testTheNameSuggestedIsTheSoundsOwnWithTheNextNumberNothingHas() {
        XCTAssertEqual(SoundSaveControls.suggestedName(editing: "Alarm", ownSounds: own, macOSSounds: system), "Alarm 2")
        XCTAssertEqual(SoundSaveControls.suggestedName(editing: "Ping", ownSounds: own, macOSSounds: system), "Ping 2")
        XCTAssertEqual(SoundSaveControls.suggestedName(editing: "Alarm", ownSounds: own.union(["Alarm 2"]), macOSSounds: system), "Alarm 3")
    }

    func testTheSuggestedNameCanBeSavedAsNew() {
        for edited in ["Alarm", "Ping", "Glass", "Gone"] {
            let typed = SoundSaveControls.suggestedName(editing: edited, ownSounds: own, macOSSounds: system)
            XCTAssertTrue(controls(edited: edited, typed: typed).canSaveAsNew, edited)
        }
    }
}

/// What closing the sound editor's window with edits that are not saved asks (sound editor plan, Task 9), asked as the rule
/// editor's is: the choice that saves first when it can be made, Don't Save, and Cancel, which keeps the work.
final class SoundCloseQuestionTests: XCTestCase {
    func testWhenItCanBeSavedTheFirstButtonSavesAsNewThenDontSaveThenCancel() {
        XCTAssertEqual(SoundCloseQuestion.choices(canSaveAsNew: true), [.saveAsNew, .dontSave, .cancel])
        XCTAssertEqual(SoundCloseQuestion.titles(canSaveAsNew: true),
                       [SoundEditorText.saveAsNew, EditorText.dontSave, EditorText.cancel])
    }

    func testWhenItCannotBeSavedCancelIsFirstSoReturnKeepsTheWork() {
        XCTAssertEqual(SoundCloseQuestion.choices(canSaveAsNew: false), [.cancel, .dontSave])
        XCTAssertEqual(SoundCloseQuestion.titles(canSaveAsNew: false), [EditorText.cancel, EditorText.dontSave])
    }

    func testAButtonIsTheChoiceAtItsPlaceAndNoneBeyondTheLast() {
        XCTAssertEqual(SoundCloseQuestion.choice(atButton: 0, canSaveAsNew: true), .saveAsNew)
        XCTAssertEqual(SoundCloseQuestion.choice(atButton: 1, canSaveAsNew: true), .dontSave)
        XCTAssertEqual(SoundCloseQuestion.choice(atButton: 2, canSaveAsNew: true), .cancel)
        XCTAssertEqual(SoundCloseQuestion.choice(atButton: 0, canSaveAsNew: false), .cancel)
        XCTAssertEqual(SoundCloseQuestion.choice(atButton: 1, canSaveAsNew: false), .dontSave)
        XCTAssertNil(SoundCloseQuestion.choice(atButton: 2, canSaveAsNew: false))
        XCTAssertNil(SoundCloseQuestion.choice(atButton: -1, canSaveAsNew: true))
        XCTAssertNil(SoundCloseQuestion.choice(atButton: 3, canSaveAsNew: true))
    }

    func testASaveUnderWayIsWaitedForAndNotAskedAbout() {
        XCTAssertEqual(SoundCloseQuestion.step(hasUnsavedEdits: true, isSaving: true), .wait,
                       "its edits are not marked as saved until it ends, and it is saving them")
        XCTAssertEqual(SoundCloseQuestion.step(hasUnsavedEdits: false, isSaving: true), .wait,
                       "it still gives the sound its name and changes the rule being edited")
        XCTAssertEqual(SoundCloseQuestion.step(hasUnsavedEdits: true, isSaving: false), .ask)
        XCTAssertEqual(SoundCloseQuestion.step(hasUnsavedEdits: false, isSaving: false), .proceed)
    }

    func testOnlyDontSaveLosesTheWork() {
        XCTAssertTrue(SoundCloseQuestion.discards(.dontSave))
        XCTAssertFalse(SoundCloseQuestion.discards(.saveAsNew))
        XCTAssertFalse(SoundCloseQuestion.discards(.cancel))
    }
}

/// Which requests the save controls will carry out, and what they say beside the name.
final class SoundSaveRequestsTests: XCTestCase {
    private func controls(edited: String = "Alarm", typed: String = "Alarm 2", isBlocked: Bool = false, isSaving: Bool = false)
        -> SoundSaveControls {
        SoundSaveControls(editedName: edited, typedName: typed, ownSounds: ["Alarm", "Klaxon"], macOSSounds: ["Ping"],
                          isReady: true, isCatchingUp: false, isSaving: isSaving, isBlocked: isBlocked)
    }

    func testTheRequestsTheControlsMakeAreAllowedAndNoOthers() {
        let c = controls()
        XCTAssertTrue(c.allows(SoundSaveRequest(name: "Alarm 2", replacing: false)))
        XCTAssertTrue(c.allows(SoundSaveRequest(name: "Alarm", replacing: true)))
        XCTAssertFalse(c.allows(SoundSaveRequest(name: "Alarm 2", replacing: true)), "a name that is free is not replaced")
        XCTAssertFalse(c.allows(SoundSaveRequest(name: "Klaxon", replacing: true)), "only the sound being edited is saved over")
        XCTAssertFalse(c.allows(SoundSaveRequest(name: "Klaxon", replacing: false)), "and a sound is not taken the place of unasked")
        XCTAssertFalse(c.allows(SoundSaveRequest(name: "Alarm", replacing: false)))
        XCTAssertFalse(c.allows(SoundSaveRequest(name: "Ping", replacing: true)))
    }

    func testARequestMadeBeforeACheckThatStopsASaveStoodIsNotAllowedAfter() {
        for c in [controls(isBlocked: true), controls(isSaving: true)] {
            XCTAssertFalse(c.allows(SoundSaveRequest(name: "Alarm 2", replacing: false)))
            XCTAssertFalse(c.allows(SoundSaveRequest(name: "Alarm", replacing: true)))
        }
    }

    func testTheNotesAreWhatIsWrongWithTheNameThenThatAMacOSSoundIsCopied() {
        XCTAssertEqual(controls().notes, [])
        XCTAssertEqual(controls(typed: "Klaxon").notes, [SoundEditorText.nameInUse("Klaxon", replaceable: false)])
        XCTAssertEqual(controls(edited: "Ping", typed: "Ping 2").notes, [SoundEditorText.macOSCopyNote("Ping")])
        XCTAssertEqual(controls(edited: "Ping", typed: "").notes,
                       [SoundEditorText.nameProblem(.blank), SoundEditorText.macOSCopyNote("Ping")])
    }
}
