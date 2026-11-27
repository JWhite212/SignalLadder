import XCTest
@testable import NotificationCore

/// The name an edited sound is saved under (sound editor plan, Ruling 9): the next free
/// "Name 2", never a macOS sound's name, never one that is in use unless saving over it
/// was asked for, and saving over offered only for a sound of the user's own.
final class SoundSaveNamingTests: XCTestCase {
    /// The sounds macOS ships, as /System/Library/Sounds lists them.
    private let macOS: Set<String> = ["Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero", "Morse", "Ping", "Pop",
                                      "Purr", "Sosumi", "Submarine", "Tink"]

    private func suggestion(_ source: String, own: Set<String> = [], macOS: Set<String>? = nil) -> String {
        SoundSaveNaming.suggestedName(for: source, ownSounds: own, macOSSounds: macOS ?? self.macOS)
    }

    // MARK: - The suggestion

    func testTheSuggestionIsTheSourcesNameWithTheNextNumberFree() {
        XCTAssertEqual(suggestion("Glass"), "Glass 2")
        XCTAssertEqual(suggestion("Alarm", own: ["Alarm"]), "Alarm 2")
        XCTAssertEqual(suggestion("Alarm", own: ["Alarm", "Alarm 2"]), "Alarm 3")
        XCTAssertEqual(suggestion("Alarm", own: ["Alarm", "Alarm 2", "Alarm 3", "Alarm 5"]), "Alarm 4")
    }

    func testANumberAlreadyOnTheSourceIsContinuedAndNotAddedTo() {
        XCTAssertEqual(suggestion("Alarm 2", own: ["Alarm 2"]), "Alarm 3")
        XCTAssertEqual(suggestion("Alarm 5", own: ["Alarm 5", "Alarm 6"]), "Alarm 7")
        XCTAssertEqual(suggestion("Alarm 0"), "Alarm 2")
    }

    func testANumberThatIsPartOfTheNameIsNotACounter() {
        XCTAssertEqual(suggestion("Alarm 2024"), "Alarm 2024 2")
        XCTAssertEqual(suggestion("Beep440"), "Beep440 2")
        XCTAssertEqual(suggestion("2"), "2 2")
        XCTAssertEqual(suggestion(" 7"), "7 2")
    }

    func testNamesAreComparedIgnoringCaseAsTheLibraryComparesThem() {
        XCTAssertEqual(suggestion("Alarm", own: ["alarm 2"]), "Alarm 3")
        XCTAssertEqual(suggestion("Foo", own: [], macOS: ["FOO 2"]), "Foo 3")
    }

    func testASuggestionIsNeverAMacOSSoundsNameNorOneInUse() {
        // Every macOS sound as the source, with every number up to 30 taken in every way a name can be.
        var own: Set<String> = []
        for number in 2...30 { own.insert("Glass \(number)") }
        for source in macOS.sorted() + ["Glass 2", "glass", "Sosumi 3"] {
            let name = suggestion(source, own: own)
            XCTAssertFalse(macOS.contains { $0.caseInsensitiveCompare(name) == .orderedSame }, "\(source) -> \(name)")
            XCTAssertFalse(own.contains { $0.caseInsensitiveCompare(name) == .orderedSame }, "\(source) -> \(name)")
        }
        XCTAssertEqual(suggestion("Glass", own: own), "Glass 31")
    }

    func testAMacOSNameWithANumberIsSkippedLikeAnyTakenName() {
        XCTAssertEqual(suggestion("Tink", macOS: ["Tink", "Tink 2", "Tink 3"]), "Tink 4")
    }

    func testTheSourcesSpacesAreNotKept() {
        XCTAssertEqual(suggestion("  Alarm  "), "Alarm 2")
        XCTAssertEqual(suggestion(" Alarm 3 "), "Alarm 4")
    }

    func testASourceWithNoNameGetsOneThatIsNotBlank() {
        // The word is the window's, held in `SoundEditorText` where every word is tested.
        XCTAssertEqual(suggestion(""), "\(SoundEditorText.untitledSoundName) 2")
        XCTAssertEqual(suggestion("   "), "\(SoundEditorText.untitledSoundName) 2")
    }

    func testASuggestionFitsTheLongestNameAndKeepsItsNumber() {
        let long = String(repeating: "a", count: SoundSaveNaming.longestName)
        let name = suggestion(long)
        XCTAssertEqual(name.count, SoundSaveNaming.longestName)
        XCTAssertTrue(name.hasSuffix(" 2"), name)
        XCTAssertEqual(suggestion(long, own: [name]).count, SoundSaveNaming.longestName)
        XCTAssertNotEqual(suggestion(long, own: [name]), name)
        // Cut short at a space, the base does not end in one.
        XCTAssertEqual(suggestion(String(repeating: "x", count: 97) + " yyyy"), String(repeating: "x", count: 97) + " 2")
    }

    func testASuggestionFromALongNameOfLettersThatTakeSeveralBytesFitsAFileNameAndKeepsItsNumber() {
        // 100 characters of three bytes each: within the limit in characters, and 300 bytes, which no file name can be.
        let long = String(repeating: "✓", count: SoundSaveNaming.longestName)
        let name = suggestion(long)
        XCTAssertLessThanOrEqual(name.utf8.count, SoundSaveNaming.longestNameBytes)
        XCTAssertTrue(name.hasSuffix(" 2"), name)
        XCTAssertEqual(verdict(name), .free(name))
        // Cut to whole letters, and the next number is still found when that one is taken.
        let again = suggestion(long, own: [name])
        XCTAssertNotEqual(again, name)
        XCTAssertTrue(again.hasSuffix(" 3"), again)
        XCTAssertLessThanOrEqual(again.utf8.count, SoundSaveNaming.longestNameBytes)
    }

    func testASuggestionFromOneLetterThatIsTooManyBytesToKeepIsGivenAnAnonymousName() {
        // One character to Swift: a letter with 300 accents on it, which is 600 bytes.
        let heap = "e" + String(repeating: "\u{301}", count: 300)
        XCTAssertEqual(heap.count, 1)
        XCTAssertEqual(suggestion(heap), "\(SoundEditorText.untitledSoundName) 2")
    }

    // MARK: - Saving over

    func testOnlyASoundOfTheUsersOwnCanBeSavedOver() {
        XCTAssertTrue(SoundSaveNaming.canSaveOver("Alarm", ownSounds: ["Alarm"], macOSSounds: macOS))
        XCTAssertTrue(SoundSaveNaming.canSaveOver("alarm", ownSounds: ["Alarm"], macOSSounds: macOS))
        XCTAssertFalse(SoundSaveNaming.canSaveOver("Glass", ownSounds: [], macOSSounds: macOS))
        XCTAssertFalse(SoundSaveNaming.canSaveOver("Missing", ownSounds: ["Alarm"], macOSSounds: macOS))
    }

    func testASoundOfTheUsersWithAMacOSNameIsNotOneToSaveOverBecauseTheInstallRefusesIt() {
        XCTAssertFalse(SoundSaveNaming.canSaveOver("Glass", ownSounds: ["Glass"], macOSSounds: macOS))
        XCTAssertFalse(SoundSaveNaming.canSaveOver("glass", ownSounds: ["Glass"], macOSSounds: macOS))
    }

    // MARK: - A name typed in

    private func verdict(_ typed: String, own: Set<String> = [], macOS: Set<String>? = nil) -> SoundSaveNaming.Verdict {
        SoundSaveNaming.verdict(for: typed, ownSounds: own, macOSSounds: macOS ?? self.macOS)
    }

    func testAFreeNameIsFreeAndKeepsItsSpellingButNotItsSpaces() {
        XCTAssertEqual(verdict("Night Alarm"), .free("Night Alarm"))
        XCTAssertEqual(verdict("  Night Alarm \n"), .free("Night Alarm"))
    }

    func testTheNameOfOneOfTheUsersSoundsIsSayingTheyWantToSaveOverItAndGivesItsOwnSpelling() {
        XCTAssertEqual(verdict("alarm", own: ["Alarm"]), .yours("Alarm"))
        XCTAssertEqual(verdict(" ALARM ", own: ["Alarm", "Other"]), .yours("Alarm"))
    }

    func testAMacOSNameIsRefusedWhateverItsCaseAndEvenWhenTheUserHasASoundOfThatName() {
        XCTAssertEqual(verdict("Glass"), .refused(.macOSSound("Glass")))
        XCTAssertEqual(verdict("glass"), .refused(.macOSSound("Glass")))
        XCTAssertEqual(verdict("GLASS", own: ["Glass"]), .refused(.macOSSound("Glass")))
    }

    func testANameThatCannotBeAFileNameIsRefusedForTheReasonItCannot() {
        XCTAssertEqual(verdict(""), .refused(.blank))
        XCTAssertEqual(verdict("  \n "), .refused(.blank))
        XCTAssertEqual(verdict(String(repeating: "a", count: SoundSaveNaming.longestName + 1)), .refused(.tooLong))
        XCTAssertEqual(verdict(".hidden"), .refused(.startsWithDot))
        for bad in ["a/b", "a:b", "a\\b", "a\tb", "a\nb"] {
            XCTAssertEqual(verdict(bad), .refused(.unsafeCharacter), bad.debugDescription)
        }
        XCTAssertEqual(verdict(String(repeating: "a", count: SoundSaveNaming.longestName)),
                       .free(String(repeating: "a", count: SoundSaveNaming.longestName)))
    }

    func testANameThatTakesTooManyBytesToBeAFileNameIsRefusedHoweverFewLettersItHas() {
        // The most that fit are the same limit for letters of one byte or of three.
        let fits = String(repeating: "✓", count: SoundSaveNaming.longestNameBytes / 3)
        XCTAssertLessThanOrEqual(fits.count, SoundSaveNaming.longestName)
        XCTAssertEqual(verdict(fits), .free(fits))
        XCTAssertEqual(verdict(fits + "✓"), .refused(.tooLongAsAFileName))
        // 100 letters is 100 characters, and 300 bytes.
        XCTAssertEqual(verdict(String(repeating: "✓", count: SoundSaveNaming.longestName)), .refused(.tooLongAsAFileName))
        // Counted in characters first: 101 of one byte is too many letters, not too many bytes.
        XCTAssertEqual(verdict(String(repeating: "a", count: SoundSaveNaming.longestName + 1)), .refused(.tooLong))
        // The one letter of 600 bytes.
        XCTAssertEqual(verdict("e" + String(repeating: "\u{301}", count: 300)), .refused(.tooLongAsAFileName))
    }

    /// Every way of spelling "alarm" in capitals and small letters: on a volume that tells them apart,
    /// the folder can hold them all.
    private let everyCaseOfAlarm: Set<String> = Set((0..<32).map { bits in
        String("alarm".enumerated().map { bits & (1 << $0.offset) == 0 ? Character($0.element.lowercased()) : Character($0.element.uppercased()) })
    })

    func testTheSpellingGivenBackForANameThatSeveralSoundsHaveDoesNotDependOnTheOrderOfASet() {
        XCTAssertEqual(everyCaseOfAlarm.count, 32)
        // The first in order, whichever order the set happens to hold them in.
        XCTAssertEqual(verdict("alarm", own: everyCaseOfAlarm), .yours("ALARM"))
        XCTAssertEqual(verdict("Alarm", own: [], macOS: everyCaseOfAlarm), .refused(.macOSSound("ALARM")))
    }

    func testEverySuggestionIsAFreeNameAsTheVerdictReadsIt() {
        for source in ["Glass", "Alarm 2", "", String(repeating: "x", count: 100), "Beep"] {
            let name = suggestion(source, own: ["Alarm 3"])
            XCTAssertEqual(verdict(name, own: ["Alarm 3"]), .free(name), source)
        }
    }
}
