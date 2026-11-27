import XCTest
@testable import NotificationCore

/// The words for a sound that could not be opened for editing or could not be saved (sound
/// editor plan, Task 5), held where they are made. A save that fails must never show the
/// words of adding a sound, and nothing a person reads is the code's own term.
final class SoundEditFailureTests: XCTestCase {
    private typealias Text = SoundEditorText

    private let everyOpenFailure: [SoundOpenFailure] = [
        .notFound("Alarm"), .tooLarge(limitMegabytes: 64), .tooLong(frames: 130 * 48_000), .unreadable("it is empty"),
    ]

    private let everySaveFailure: [SoundSaveFailure] = [
        .badName, .systemSound("Glass"), .alreadyExists("Alarm"), .cannotSetAside("Alarm"), .silent, .tooLong,
        .sourceChanged, .unreadable("the file is damaged"), .couldNotWrite(nil), .couldNotWrite("the disk is full"),
    ]

    /// Said by a switch with no default, so that a failure given a case without a test
    /// here is a build that fails and not a case that is never worded.
    private func isCovered(_ failure: SoundSaveFailure) -> Bool {
        switch failure {
        case .badName, .systemSound, .alreadyExists, .cannotSetAside, .silent, .tooLong, .sourceChanged, .unreadable,
             .couldNotWrite:
            return true
        }
    }

    private func isCovered(_ failure: SoundOpenFailure) -> Bool {
        switch failure {
        case .notFound, .tooLarge, .tooLong, .unreadable: return true
        }
    }

    private var everySaveSentence: [String] { everySaveFailure.map(Text.saveFailure) }
    private var everyOpenSentence: [String] { everyOpenFailure.map { Text.cannotOpen("Alarm", failure: $0) } }

    func testEveryFailureHasAWordOfItsOwn() {
        XCTAssertTrue(everySaveFailure.allSatisfy(isCovered) && everyOpenFailure.allSatisfy(isCovered))
        XCTAssertEqual(Set(everySaveSentence).count, everySaveSentence.count)
        XCTAssertEqual(Set(everyOpenSentence).count, everyOpenSentence.count)
        for word in everySaveSentence + everyOpenSentence + everyOpenFailure.map(Text.openReason) {
            XCTAssertFalse(word.isEmpty)
            XCTAssertEqual(word, word.trimmingCharacters(in: .whitespacesAndNewlines), word)
        }
    }

    func testNothingSaidIsTheCodesOwnTermOrTheWordsOfAddingASound() {
        let jargon = ["recipe", "frame", "segment", "sidecar", "digest", "render", "excerpt", "buffer", "dBFS", "nil", "Optional"]
        for word in everySaveSentence + everyOpenSentence {
            for term in jargon {
                XCTAssertFalse(word.lowercased().contains(term.lowercased()), "“\(word)” says “\(term)”")
            }
        }
        for word in everySaveSentence {
            XCTAssertFalse(word.contains("could not be added"), word)
            XCTAssertFalse(word.contains("Add Sound"), word)
        }
    }

    func testASaveFailureIsASentenceAndAnOpenReasonIsAPhraseForAfterAColon() {
        for sentence in everySaveSentence { XCTAssertTrue(sentence.hasSuffix("."), sentence) }
        for failure in everyOpenFailure {
            let reason = Text.openReason(failure)
            XCTAssertFalse(reason.hasSuffix("."), reason)
            XCTAssertEqual(reason.first.map(String.init), reason.first.map { String($0).lowercased() }, reason)
        }
        for sentence in everyOpenSentence {
            XCTAssertTrue(sentence.hasPrefix("“Alarm” could not be opened for editing: "), sentence)
            XCTAssertTrue(sentence.hasSuffix("."), sentence)
            XCTAssertFalse(sentence.hasSuffix(".."), sentence)
        }
    }

    // MARK: - What each says

    func testANameThatCannotBeASoundsSaysSo() {
        XCTAssertEqual(Text.saveFailure(.badName), "That name cannot be used for a sound. Choose another.")
    }

    func testAMacOSNameIsSaidAsTheNameCheckSaysIt() {
        XCTAssertEqual(Text.saveFailure(.systemSound("Glass")), Text.nameProblem(.macOSSound("Glass")))
    }

    func testANameYouAlreadyHaveSaysSoAndSaysWhatToDo() {
        let sentence = Text.saveFailure(.alreadyExists("Alarm"))
        XCTAssertEqual(sentence, "You already have a sound called “Alarm”. Choose another name, or save over it.")
    }

    func testASoundThatCannotBeReplacedSafelySaysWhichAndWhatToDo() {
        let sentence = Text.saveFailure(.cannotSetAside("Alarm"))
        XCTAssertTrue(sentence.contains("“Alarm”") && sentence.contains("too long a name"), sentence)
        XCTAssertTrue(sentence.contains("another name"), sentence)
    }

    func testASilentSoundAndALongOneSayWhatTheyAre() {
        XCTAssertTrue(Text.saveFailure(.silent).contains("nothing to hear"), Text.saveFailure(.silent))
        let long = Text.saveFailure(.tooLong)
        XCTAssertTrue(long.contains("\(SoundRecipe.savableFrames / SampleBuffer.sampleRate) seconds"), long)
    }

    func testASoundChangedUnderTheEditorSaysToOpenItAgain() {
        let sentence = Text.saveFailure(.sourceChanged)
        XCTAssertTrue(sentence.contains("outside the editor") && sentence.contains("open it again"), sentence)
    }

    func testAReasonTheSystemGaveIsKeptAndEndsTheSentenceOnce() {
        XCTAssertTrue(Text.saveFailure(.unreadable("the file is damaged")).contains("the file is damaged"))
        XCTAssertEqual(Text.saveFailure(.couldNotWrite("the disk is full")), "The sound could not be written: the disk is full.")
        XCTAssertEqual(Text.saveFailure(.couldNotWrite("The disk is full.")), "The sound could not be written: The disk is full.")
        XCTAssertEqual(Text.saveFailure(.couldNotWrite(nil)), "The sound could not be written.")
    }

    func testASaveFailureFitsWhereTheWindowGivesAReason() {
        XCTAssertEqual(Text.saveFailedDetail(Text.saveFailure(.silent)),
                       "\(Text.saveFailure(.silent))\n\nYour sounds are as they were, and your edits are still here.")
    }

    func testEachOpenFailureSaysWhatWasTheMatter() {
        XCTAssertEqual(Text.cannotOpen("Alarm", failure: .notFound("Alarm")),
                       "“Alarm” could not be opened for editing: there is no sound of that name.")
        XCTAssertEqual(Text.openReason(.tooLarge(limitMegabytes: 64)), "the file is larger than 64 MB")
        let long = Text.openReason(.tooLong(frames: 130 * 48_000))
        XCTAssertTrue(long.contains("130 seconds") && long.contains("120 seconds"), long)
        XCTAssertEqual(Text.openReason(.unreadable("it is empty")), "it could not be read as audio: it is empty")
        XCTAssertEqual(Text.cannotOpen("Alarm", failure: .unreadable("Something failed.")),
                       "“Alarm” could not be opened for editing: it could not be read as audio: Something failed.",
                       "a reason that ends a sentence is not given a second full stop")
    }
}
