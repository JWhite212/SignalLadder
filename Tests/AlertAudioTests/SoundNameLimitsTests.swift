import XCTest
@testable import AlertAudio
import NotificationCore

/// The core cannot see `SoundInstall`, so the rules for a sound's name that the editor's
/// window applies as the user types, and the name it suggests, are held here to the rules
/// the install applies when the sound is saved. A name the window passes and the install
/// refuses would be a save that fails after the user was told it would work.
final class SoundNameLimitsTests: XCTestCase {
    private let macOS: Set<String> = ["Glass", "Sosumi"]

    func testTheLongestNameIsTheOneTheInstallHoldsANameTo() {
        XCTAssertEqual(SoundSaveNaming.longestName, SoundInstall.maximumNameLength)
    }

    func testAnameTheWindowCallsFreeIsOneTheInstallAccepts() {
        let typed = ["Alarm", "  Alarm  ", "a b", String(repeating: "a", count: 100), String(repeating: "a", count: 101), "",
                     " ", ".hidden", "a/b", "a:b", "a\\b", "a\tb", "a\nb", "ünï cödé ✓", "Glass"]
        for name in typed {
            let verdict = SoundSaveNaming.verdict(for: name, ownSounds: [], macOSSounds: macOS)
            switch verdict {
            case .free(let accepted), .yours(let accepted):
                XCTAssertTrue(SoundInstall.isSafe(name: accepted), "the window passes “\(name)” and the install refuses it")
            case .refused(.macOSSound):
                break
            case .refused:
                XCTAssertFalse(SoundInstall.isSafe(name: name.trimmingCharacters(in: .whitespacesAndNewlines)),
                               "the window refuses “\(name)” and the install accepts it")
            }
        }
    }

    func testEverySuggestionIsAnAcceptedName() {
        for source in ["Glass", "Alarm 2", "", String(repeating: "a", count: 100), String(repeating: "word ", count: 30)] {
            let name = SoundSaveNaming.suggestedName(for: source, ownSounds: [], macOSSounds: macOS)
            XCTAssertTrue(SoundInstall.isSafe(name: name), "“\(name)” from “\(source)”")
        }
    }
}
