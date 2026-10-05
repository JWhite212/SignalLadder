import XCTest
@testable import NotificationCore

/// Where the running copy is, as far as the login item needs it (M5 plan, Ruling
/// 15). The path and the home folder are given as text, so nothing here reads the
/// environment or the disk, and the user's own `~/Applications` is a folder of
/// this test's making.
final class AppLocationTests: XCTestCase {
    private let home = "/Users/ada"

    private func classify(_ path: String, home: String? = nil) -> AppLocation {
        AppLocation.classify(path: path, home: home ?? self.home)
    }

    // MARK: - The five places the plan names

    func testTheApplicationsFolderIsApplications() {
        XCTAssertEqual(classify("/Applications/SignalLadder.app"), .applications)
    }

    func testACopyInTheUsersApplicationsFolderIsTheUsers() {
        XCTAssertEqual(classify("/Users/ada/Applications/SignalLadder.app"), .userApplications)
        XCTAssertEqual(classify("/Users/ada/Applications/SignalLadder.app", home: "/Users/ada/"), .userApplications,
                       "a home folder given with a trailing slash is the same folder")
    }

    func testTheUsersApplicationsFolderIsFoundFromTheHomeGivenAndNotFromTheEnvironment() {
        // The same path is the user's under one home and nobody's under another,
        // which only a home that is passed in can do.
        let path = "/Users/ada/Applications/SignalLadder.app"
        XCTAssertEqual(classify(path, home: "/Users/ada"), .userApplications)
        XCTAssertEqual(classify(path, home: "/Users/grace"), .elsewhere)
        XCTAssertEqual(classify("/Users/grace/Applications/SignalLadder.app", home: "/Users/ada"), .elsewhere,
                       "another user's Applications folder is not this user's")
    }

    func testATranslocatedPathIsTranslocated() {
        let path = "/private/var/folders/zz/abc123def456/T/AppTranslocation/6B2F8A10-3C4D-4E5F-8A9B-0C1D2E3F4A5B/d/SignalLadder.app"
        XCTAssertEqual(classify(path), .translocated)
    }

    func testABuildFolderIsElsewhere() {
        XCTAssertEqual(classify("/Users/ada/src/signalladder/.build/arm64-apple-macosx/debug/SignalLadder.app"), .elsewhere)
        XCTAssertEqual(classify("/Users/ada/src/signalladder/build/SignalLadder.app"), .elsewhere)
    }

    func testAMountedVolumeIsElsewhere() {
        XCTAssertEqual(classify("/Volumes/SignalLadder 0.1.0/SignalLadder.app"), .elsewhere)
        XCTAssertEqual(classify("/Volumes/Applications/SignalLadder.app"), .elsewhere,
                       "a volume with the name of the folder is not the folder")
    }

    // MARK: - Anything else is elsewhere

    func testADownloadsFolderAndTheDesktopAreElsewhere() {
        XCTAssertEqual(classify("/Users/ada/Downloads/SignalLadder.app"), .elsewhere)
        XCTAssertEqual(classify("/Users/ada/Desktop/SignalLadder.app"), .elsewhere)
    }

    /// An unbundled program reads its folder as its bundle's path, which is no
    /// app, so it is never taken for one in Applications, even if it sits there.
    func testAProgramThatIsNotInABundleIsElsewhereEvenInApplications() {
        XCTAssertEqual(classify("/Users/ada/src/signalladder/.build/arm64-apple-macosx/debug"), .elsewhere)
        XCTAssertEqual(classify("/Applications"), .elsewhere, "the folder a loose program sits in")
        XCTAssertEqual(classify("/Applications/SignalLadder"), .elsewhere)
        XCTAssertEqual(classify("/Users/ada/Applications"), .elsewhere)
        XCTAssertEqual(classify("/Applications/.app"), .elsewhere, "a bundle with no name")
        XCTAssertEqual(classify("/Applications/SignalLadder.app.zip"), .elsewhere)
    }

    /// The plan names the two folders, and a folder inside one was not measured.
    func testAFolderInsideApplicationsIsElsewhere() {
        XCTAssertEqual(classify("/Applications/Utilities/SignalLadder.app"), .elsewhere)
        XCTAssertEqual(classify("/Users/ada/Applications/Tools/SignalLadder.app"), .elsewhere)
        XCTAssertEqual(classify("/Applications/SignalLadder.app/Contents/MacOS/SignalLadder"), .elsewhere,
                       "a path inside a bundle is not the bundle")
    }

    func testAFolderThatOnlyHasApplicationsInItsNameIsElsewhere() {
        XCTAssertEqual(classify("/Applications Old/SignalLadder.app"), .elsewhere)
        XCTAssertEqual(classify("/Users/ada/MyApplications/SignalLadder.app"), .elsewhere)
        XCTAssertEqual(classify("/Users/ada/Applications Backup/SignalLadder.app"), .elsewhere)
        XCTAssertEqual(classify("/Library/Applications/SignalLadder.app"), .elsewhere)
        XCTAssertEqual(classify("/System/Applications/SignalLadder.app"), .elsewhere)
    }

    // MARK: - What a path can be

    func testATranslocatedPathIsTranslocatedWhereverTheFolderIsAndWhateverItEndsIn() {
        XCTAssertEqual(classify("/AppTranslocation/x/d/SignalLadder.app"), .translocated)
        XCTAssertEqual(classify("/private/var/folders/T/AppTranslocation/x/d/SignalLadder"), .translocated,
                       "a program in one is as translocated as a bundle")
        // The translocation folder is looked for before Applications is: a path that
        // is in both reads as the one the system chose.
        XCTAssertEqual(classify("/Applications/AppTranslocation/x/SignalLadder.app"), .translocated)
        // But it is a whole folder name, and not a few letters in one.
        XCTAssertEqual(classify("/Applications/MyAppTranslocation/SignalLadder.app"), .elsewhere)
        XCTAssertEqual(classify("/Applications/AppTranslocationNotes/SignalLadder.app"), .elsewhere)
    }

    func testADoubledOrTrailingSlashChangesNothing() {
        XCTAssertEqual(classify("/Applications/SignalLadder.app/"), .applications)
        XCTAssertEqual(classify("//Applications//SignalLadder.app"), .applications)
        XCTAssertEqual(classify("/Users/ada//Applications/SignalLadder.app"), .userApplications)
    }

    /// A path the app cannot vouch for is not one an Applications folder holds.
    func testAPathThatIsNotAbsoluteOrIsNotWrittenOutInFullIsElsewhere() {
        XCTAssertEqual(classify("Applications/SignalLadder.app"), .elsewhere)
        XCTAssertEqual(classify("SignalLadder.app"), .elsewhere)
        XCTAssertEqual(classify(""), .elsewhere)
        XCTAssertEqual(classify("/"), .elsewhere)
        XCTAssertEqual(classify("/Applications/../Users/ada/Downloads/SignalLadder.app"), .elsewhere)
        XCTAssertEqual(classify("/Users/ada/Downloads/../../../Applications/SignalLadder.app"), .elsewhere)
        XCTAssertEqual(classify("/Applications/./SignalLadder.app"), .elsewhere)
        // A home that was not written out in full does not make a path the user's:
        // a folder that is only the same one by way of a `..` is not named by what
        // the app was given.
        XCTAssertEqual(classify("/Users/ada/../Applications/SignalLadder.app", home: "/Users/ada/.."), .elsewhere)
        XCTAssertEqual(classify("/Users/ada/./Applications/SignalLadder.app", home: "/Users/ada/."), .elsewhere)
    }

    func testAHomeThatCannotBeAFolderNamesNoUsersApplications() {
        XCTAssertEqual(classify("/Applications/SignalLadder.app", home: ""), .applications, "the system's folder needs no home")
        XCTAssertEqual(classify("/Users/ada/Applications/SignalLadder.app", home: ""), .elsewhere)
        XCTAssertEqual(classify("/Users/ada/Applications/SignalLadder.app", home: "Users/ada"), .elsewhere,
                       "a home that is not an absolute path names no folder")
        // A root home would make `/Applications` the user's, which it is not: it
        // is the system's, and is read as that whatever the home is.
        XCTAssertEqual(classify("/Applications/SignalLadder.app", home: "/"), .applications)
    }

    // MARK: - What each place allows

    func testOnlyTheTwoApplicationsFoldersAreAnApplicationsFolder() {
        XCTAssertTrue(AppLocation.applications.isInApplicationsFolder)
        XCTAssertTrue(AppLocation.userApplications.isInApplicationsFolder)
        XCTAssertFalse(AppLocation.translocated.isInApplicationsFolder)
        XCTAssertFalse(AppLocation.elsewhere.isInApplicationsFolder)
        XCTAssertEqual(AppLocation.allCases.count, 4)
    }

    func testTheTranslocationFolderIsTheNameTheSystemGives() {
        XCTAssertEqual(AppLocation.translocationFolder, "AppTranslocation")
    }
}
