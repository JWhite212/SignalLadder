import XCTest
@testable import NotificationCore

/// Every word the sound editor's window shows or says (sound editor plan, Task 4), held
/// where the words are made: what each says, that nothing in it is the code's own jargon,
/// and that a sentence about a number is the number the checks use.
final class SoundEditorTextTests: XCTestCase {
    private typealias Text = SoundEditorText
    private typealias Limits = SoundChecks.Limits

    private let oneOfEachRefusal: [SoundEditRefusal] = [
        .sourceTooLong(frames: 130 * 48_000), .tooLong(frames: 125 * 48_000), .wouldLeaveNothing, .emptySelection,
        .selectionOutsideSound, .tooManyPieces, .excerptFromAnotherSound, .gainOutOfRange, .playsOutOfRange, .gapOutOfRange,
    ]

    private let everyProblem: [SoundSaveNaming.Problem] = [.blank, .tooLong, .startsWithDot, .unsafeCharacter,
                                                           .macOSSound("Glass")]

    /// A finding of each kind as the checks make it from a sound set off by that kind, so that its press
    /// is the one it has. Made once: the long sound is a minute of samples.
    private static let findings: [SoundFinding.Kind: SoundFinding] = Dictionary(uniqueKeysWithValues:
        SoundFinding.Kind.allCases.map { kind in
            (kind, SoundChecks.findings(in: SoundFindingSamples.setting(off: kind)).first { $0.kind == kind }!)
        })

    private func finding(_ kind: SoundFinding.Kind) throws -> SoundFinding {
        try XCTUnwrap(Self.findings[kind])
    }

    /// Every sentence and label the window can show, with the arguments it can be given.
    private func everyWord() throws -> [String] {
        var words: [String] = Text.Command.allCases.map(\.title)
        words += [Text.gainLabel, Text.gainNote, Text.gainNeedsASelection, Text.playsLabel, Text.gapLabel, Text.waveformHint,
                  Text.catchingUp, Text.checksHeading, Text.noFindings, Text.previewRefused, Text.nameLabel, Text.saveAsNew,
                  Text.save, Text.saveOver, Text.saveFailedTitle, Text.editsCannotBeReopened, Text.closeDetail]
        words += [Text.heading("Alarm"), Text.lengthReadout(frames: 100_000), Text.waveformLabel("Alarm"),
                  Text.waveformValue(playhead: 24_000, selection: nil, length: 96_000),
                  Text.waveformValue(playhead: 24_000, selection: 12_000..<48_000, length: 96_000),
                  Text.saveOverQuestion("Alarm"), Text.macOSCopyNote("Glass"), Text.saved("Alarm 2"),
                  Text.saveFailedDetail("the disk is full"), Text.cannotOpen("Alarm", reason: "it is not audio"),
                  Text.closeQuestion("Alarm")]
        words += (0...3).map { Text.saveOverDetail(ruleCount: $0) }
        words += oneOfEachRefusal.map(Text.refusal)
        words += everyProblem.map(Text.nameProblem)
        for kind in SoundFinding.Kind.allCases {
            words.append(Text.sentence(for: try finding(kind)))
            if let press = Text.pressLabel(for: kind) { words.append(press) }
        }
        return words
    }

    // MARK: - All of it

    func testNoWordIsEmptyOrHasSpacesAtItsEnds() throws {
        for word in try everyWord() {
            XCTAssertFalse(word.isEmpty)
            XCTAssertEqual(word, word.trimmingCharacters(in: .whitespacesAndNewlines), word)
        }
    }

    func testNoWordUsesTheCodesOwnTermsForWhatThePersonSees() throws {
        let jargon = ["recipe", "frame", "segment", "sidecar", "digest", "render", "excerpt", "buffer", "dBFS", "SoundEdit"]
        for word in try everyWord() {
            for term in jargon {
                XCTAssertFalse(word.lowercased().contains(term.lowercased()), "“\(word)” says “\(term)”")
            }
        }
    }

    func testTheCommandsAreLabelsAndEverythingElseIsASentenceOrAQuestion() throws {
        for command in Text.Command.allCases {
            XCTAssertFalse(command.title.hasSuffix("."), command.title)
        }
        for kind in SoundFinding.Kind.allCases {
            XCTAssertTrue(Text.sentence(for: try finding(kind)).hasSuffix("."), "\(kind)")
            XCTAssertFalse((Text.pressLabel(for: kind) ?? "").hasSuffix("."), "\(kind)")
        }
        for refusal in oneOfEachRefusal { XCTAssertTrue(Text.refusal(refusal).hasSuffix("."), "\(refusal)") }
        for problem in everyProblem { XCTAssertTrue(Text.nameProblem(problem).hasSuffix("."), "\(problem)") }
    }

    // MARK: - The window and its controls

    func testTheHeadingNamesTheSoundBetweenQuotes() {
        XCTAssertEqual(Text.heading("Night Alarm"), "Editing “Night Alarm”")
    }

    func testEveryCommandHasATitleAndNoTwoAreAlike() {
        let titles = Text.Command.allCases.map(\.title)
        XCTAssertEqual(Set(titles).count, titles.count)
        XCTAssertEqual(Text.Command.allCases.count, 20)
    }

    func testTheCommandsAreCalledWhatThePlanCallsThem() {
        XCTAssertEqual(Text.Command.resetToOriginal.title, "Reset to Original")
        XCTAssertEqual(Text.Command.fadeIn.title, "Fade In")
        XCTAssertEqual(Text.Command.fadeOut.title, "Fade Out")
        XCTAssertEqual(Text.Command.trim.title, "Trim")
        XCTAssertEqual(Text.Command.delete.title, "Delete")
        XCTAssertEqual(Text.Command.repeatSelection.title, "Repeat")
        XCTAssertEqual(Text.Command.gain.title, "Gain")
        XCTAssertEqual(Text.Command.loopSelection.title, "Loop Selection")
        XCTAssertEqual(Text.saveAsNew, "Save as New")
        XCTAssertEqual(Text.save, "Save")
    }

    func testTheGainSaysItChangesThePartAgainstTheRestAndNotHowLoudTheWholePlays() {
        XCTAssertTrue(Text.gainNote.contains("against the rest of the sound"), Text.gainNote)
        XCTAssertTrue(Text.gainNote.contains("nothing you can hear"), Text.gainNote)
        XCTAssertTrue(Text.gainNeedsASelection.contains("part of the sound"), Text.gainNeedsASelection)
    }

    func testTheLengthIsInSeconds() {
        XCTAssertEqual(Text.lengthReadout(frames: 115_200), "Length: 2.4 seconds")
        XCTAssertEqual(Text.lengthReadout(frames: 48_000), "Length: 1 second")
        XCTAssertEqual(Text.lengthReadout(frames: 2_400), "Length: 0.05 seconds")
    }

    // MARK: - VoiceOver

    func testTheWaveformIsNamedAfterTheSoundAndSaysWhereTheplayheadIsAndWhatIsSelected() {
        XCTAssertEqual(Text.waveformLabel("Alarm"), "Waveform of “Alarm”")
        XCTAssertEqual(Text.waveformValue(playhead: 72_000, selection: nil, length: 144_000),
                       "Playhead at 1.5 of 3 seconds. Nothing selected.")
        XCTAssertEqual(Text.waveformValue(playhead: 0, selection: 24_000..<52_800, length: 48_000),
                       "Playhead at 0 of 1 second. Selected from 0.5 to 1.1 seconds.")
    }

    func testTheHintSaysTheKeysThatWork() {
        for key in ["Space", "arrow", "Shift", "Home", "End"] {
            XCTAssertTrue(Text.waveformHint.contains(key), "\(key): \(Text.waveformHint)")
        }
    }

    // MARK: - What the checks found

    func testEachFindingHasASentenceOfItsOwn() throws {
        let sentences = try SoundFinding.Kind.allCases.map { Text.sentence(for: try finding($0)) }
        XCTAssertEqual(Set(sentences).count, sentences.count)
    }

    func testOnlyAFindingWithAPressHasAPressLabelAndNoTwoLabelsAreAlike() throws {
        var labels: [String] = []
        for kind in SoundFinding.Kind.allCases {
            let found = try finding(kind)
            let label = Text.pressLabel(for: kind)
            XCTAssertEqual(label != nil, found.fix != nil, "\(kind)")
            if let label { labels.append(label) }
        }
        XCTAssertEqual(labels.count, SoundFinding.Kind.allCases.count - 1, "all but clipping")
        XCTAssertEqual(Set(labels).count, labels.count)
        XCTAssertNil(Text.pressLabel(for: .clipping))
    }

    func testTheTwoThatStopASaveSaySavingIsOffAndTheOthersDoNot() throws {
        for kind in SoundFinding.Kind.allCases {
            let found = try finding(kind)
            XCTAssertEqual(Text.sentence(for: found).contains("Saving is off"), found.blocksSaving, "\(kind)")
        }
    }

    func testTheSentencesSayTheNumbersTheChecksUse() throws {
        let abrupt = Text.sentence(for: try finding(.startsAbruptly))
        XCTAssertTrue(abrupt.contains("within 10 milliseconds"), abrupt)
        XCTAssertTrue(abrupt.contains("half"), abrupt)
        let short = Text.sentence(for: try finding(.tooShort))
        XCTAssertTrue(short.contains("0.2 seconds"), "its own length: \(short)")
        XCTAssertTrue(short.contains("0.5 seconds"), "the length it asks for: \(short)")
        let long = Text.sentence(for: try finding(.tooLong))
        XCTAssertTrue(long.contains("30 seconds"), long)
        // One frame over is never written as the limit it is over: a length too long is rounded up.
        XCTAssertTrue(long.hasPrefix("It is 30.01 seconds long"), long)
    }

    func testTheSilenceSentencesSayHowLongTheSilenceIs() {
        let start = SoundFinding(kind: .silenceAtStart, frames: 14_400, fix: nil)
        XCTAssertEqual(Text.sentence(for: start), "It begins with 0.3 seconds of silence, so the alert would seem to come late.")
        let end = SoundFinding(kind: .silenceAtEnd, frames: 48_000, fix: nil)
        XCTAssertEqual(Text.sentence(for: end), "It ends with 1 second of silence, so it takes longer to finish than it needs to.")
    }

    func testASentenceStillReadsWellWhenTheFindingCarriesNoLength() {
        for kind in [SoundFinding.Kind.tooShort, .tooLong, .silenceAtStart, .silenceAtEnd] {
            let sentence = Text.sentence(for: SoundFinding(kind: kind, frames: nil, fix: nil))
            XCTAssertFalse(sentence.contains("nil"), sentence)
            XCTAssertFalse(sentence.contains("  "), sentence)
        }
    }

    func testThePressLabelsSayWhatEachDoes() {
        XCTAssertEqual(Text.pressLabel(for: .nothingToHear), "Undo")
        XCTAssertEqual(Text.pressLabel(for: .tooLong), "Keep the First 30 Seconds")
        XCTAssertEqual(Text.pressLabel(for: .tooShort), "Repeat It 3 Times")
        XCTAssertEqual(Text.pressLabel(for: .startsAbruptly), "Fade In the Start")
        XCTAssertEqual(Text.pressLabel(for: .silenceAtStart), "Trim the Silence at the Start")
        XCTAssertEqual(Text.pressLabel(for: .silenceAtEnd), "Trim the Silence at the End")
    }

    func testClippingSaysToStartFromACleanerCopy() throws {
        let sentence = Text.sentence(for: try finding(.clipping))
        XCTAssertTrue(sentence.contains("cleaner copy"), sentence)
    }

    // MARK: - Why an edit was not made

    func testEveryRefusalHasASentenceOfItsOwn() {
        let sentences = oneOfEachRefusal.map(Text.refusal)
        XCTAssertEqual(Set(sentences).count, sentences.count)
    }

    func testARefusalForALengthSaysTheLengthAndTheLimit() {
        let source = Text.refusal(.sourceTooLong(frames: 130 * 48_000))
        XCTAssertTrue(source.contains("130 seconds") && source.contains("120 seconds"), source)
        let result = Text.refusal(.tooLong(frames: 125 * 48_000))
        XCTAssertTrue(result.contains("125 seconds") && result.contains("120 seconds") && result.contains("30"), result)
    }

    func testTheRefusalsThatNameALimitNameTheOneTheEditsUse() {
        XCTAssertTrue(Text.refusal(.gainOutOfRange).contains("\(Int(SoundRecipe.maximumGainDB)) dB"), Text.refusal(.gainOutOfRange))
        XCTAssertTrue(Text.refusal(.playsOutOfRange).contains("2 to \(SoundEdit.mostPlays) times"), Text.refusal(.playsOutOfRange))
        XCTAssertTrue(Text.refusal(.gapOutOfRange).contains("\(SoundRecipe.maximumFrames / SampleBuffer.sampleRate) seconds"),
                      Text.refusal(.gapOutOfRange))
    }

    func testAnEditThatWouldLeaveNothingSaysSoAndSaysItWasNotDone() {
        XCTAssertEqual(Text.refusal(.wouldLeaveNothing), "That would leave nothing of the sound, so it was not done.")
    }

    // MARK: - Saving

    func testSavingOverNamesTheSoundAndSaysHowManyRulesPlayTheNewOne() {
        XCTAssertEqual(Text.saveOverQuestion("Alarm"), "Save over your sound “Alarm”?")
        XCTAssertTrue(Text.saveOverDetail(ruleCount: 0).hasPrefix("No rule uses it"), Text.saveOverDetail(ruleCount: 0))
        XCTAssertTrue(Text.saveOverDetail(ruleCount: 1).hasPrefix("1 rule uses it, and will play the new sound."),
                      Text.saveOverDetail(ruleCount: 1))
        XCTAssertTrue(Text.saveOverDetail(ruleCount: 3).hasPrefix("3 rules use it, and all of them will play the new sound."),
                      Text.saveOverDetail(ruleCount: 3))
        for count in 0...3 {
            XCTAssertTrue(Text.saveOverDetail(ruleCount: count).hasSuffix("The sound it replaces is not kept."), "\(count)")
        }
    }

    func testAMacOSSoundIsSavedAsACopyAndTheNoteSaysSo() {
        XCTAssertEqual(Text.macOSCopyNote("Glass"),
                       "“Glass” is a macOS sound and cannot be changed, so this is saved as a copy under a new name.")
    }

    func testEachNameProblemSaysWhatIsWrongWithTheName() {
        XCTAssertEqual(Text.nameProblem(.blank), "Give the sound a name.")
        XCTAssertEqual(Text.nameProblem(.tooLong), "A name can be at most \(SoundSaveNaming.longestName) characters.")
        XCTAssertEqual(Text.nameProblem(.startsWithDot), "A name cannot begin with a dot.")
        XCTAssertTrue(Text.nameProblem(.unsafeCharacter).contains("/"), Text.nameProblem(.unsafeCharacter))
        XCTAssertEqual(Text.nameProblem(.macOSSound("Glass")), "macOS already has a sound called “Glass”. Choose another name.")
        let sentences = everyProblem.map(Text.nameProblem)
        XCTAssertEqual(Set(sentences).count, sentences.count)
    }

    func testAFailedSaveSaysThatTheSoundsAreAsTheyWereAndTheEditsAreStillThere() {
        XCTAssertEqual(Text.saveFailedTitle, "The sound could not be saved.")
        XCTAssertEqual(Text.saveFailedDetail("the disk is full"),
                       "the disk is full\n\nYour sounds are as they were, and your edits are still here.")
    }

    func testASaveWhoseEditsCouldNotBeKeptSaysTheSoundPlaysAsItShould() {
        XCTAssertTrue(Text.editsCannotBeReopened.hasPrefix("The sound was saved and plays as it should"), Text.editsCannotBeReopened)
    }

    func testClosingWithEditsNotSavedAsksAboutTheSound() {
        XCTAssertEqual(Text.closeQuestion("Alarm"), "Save the changes to “Alarm”?")
        XCTAssertTrue(Text.closeDetail.contains("lost"), Text.closeDetail)
    }

    func testAPreviewRefusedBecauseAnAlertIsSoundingSaysSo() {
        XCTAssertEqual(Text.previewRefused, "An alert is sounding, so the preview did not play.")
    }
}
