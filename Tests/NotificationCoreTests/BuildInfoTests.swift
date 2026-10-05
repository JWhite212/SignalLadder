import Foundation
import XCTest
@testable import NotificationCore

/// The version line (M5 plan, O12, Task 6): which build is running, read from the
/// bundle's property list, and the sentence the Settings window shows for it.
/// Nothing here reads a bundle or the user's locale: the dictionary is built in
/// the test and the date's formatter is given a locale and a time zone.
final class BuildInfoTests: XCTestCase {
    // MARK: - Helpers

    /// The stamp `Scripts/make-app.sh` writes, with the three keys it adds.
    private func stamp(version: String? = "0.1.0", build: String? = "1", commit: String? = "d5937c0",
                       date: String? = "2026-10-02T09:15:00Z", modified: Any? = false) -> [String: Any] {
        var info: [String: Any] = [:]
        if let version { info[BuildInfo.versionKey] = version }
        if let build { info[BuildInfo.buildNumberKey] = build }
        if let commit { info[BuildInfo.commitKey] = commit }
        if let date { info[BuildInfo.dateKey] = date }
        if let modified { info[BuildInfo.modifiedKey] = modified }
        return info
    }

    private func moment(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text)!
    }

    private func formatter(locale: String = "en_GB", timeZone: String = "UTC") -> DateFormatter {
        SettingsText.dateFormatter(locale: Locale(identifier: locale), timeZone: TimeZone(identifier: timeZone)!)
    }

    /// The line the window would show for a dictionary.
    private func line(_ info: [String: Any]?, locale: String = "en_GB", timeZone: String = "UTC") -> String {
        let shown = formatter(locale: locale, timeZone: timeZone)
        return SettingsText.version(BuildInfo(infoDictionary: info), date: shown.string(from:))
    }

    private func info(version: String? = "0.1.0", buildNumber: String? = "1", commit: String? = "d5937c0",
                      date: Date? = Date(timeIntervalSince1970: 1_790_932_500), modified: Bool? = false) -> BuildInfo {
        BuildInfo(version: version, buildNumber: buildNumber, commit: commit, date: date, modified: modified)
    }

    // MARK: - A full stamp

    func testAFullStampIsReadAndShownWithTheCommitAndTheDate() {
        let read = BuildInfo(infoDictionary: stamp())
        XCTAssertEqual(read, BuildInfo(version: "0.1.0", buildNumber: "1", commit: "d5937c0",
                                       date: moment("2026-10-02T09:15:00Z"), modified: false))
        XCTAssertEqual(line(stamp()), "Version 0.1.0 (1), built from d5937c0 on 2 Oct 2026")
    }

    /// A signed bundle's dictionary holds keys of its own, and the Boolean comes
    /// back from the plist as a number the system calls a Boolean.
    func testTheKeysAreReadFromAMixedDictionaryAndTheRestIsIgnored() {
        var dictionary = stamp(modified: NSNumber(value: true))
        dictionary["CFBundleIdentifier"] = "com.example.app"
        dictionary["LSUIElement"] = true
        dictionary["NSHumanReadableCopyright"] = "Copyright"
        XCTAssertEqual(BuildInfo(infoDictionary: dictionary),
                       BuildInfo(version: "0.1.0", buildNumber: "1", commit: "d5937c0",
                                 date: moment("2026-10-02T09:15:00Z"), modified: true))
    }

    func testTheFiveKeysAreTheOnesTheBundleAndTheScriptUse() {
        XCTAssertEqual(BuildInfo.versionKey, "CFBundleShortVersionString")
        XCTAssertEqual(BuildInfo.buildNumberKey, "CFBundleVersion")
        XCTAssertEqual(BuildInfo.commitKey, "SLBuildCommit")
        XCTAssertEqual(BuildInfo.dateKey, "SLBuildDate")
        XCTAssertEqual(BuildInfo.modifiedKey, "SLBuildModified")
    }

    // MARK: - A modified tree

    func testAModifiedTreeSaysSoAfterTheCommit() {
        XCTAssertEqual(line(stamp(modified: true)),
                       "Version 0.1.0 (1), built from d5937c0 with local changes on 2 Oct 2026")
    }

    func testAModifiedTreeWithNoDateKeepsTheWordsAfterTheCommit() {
        XCTAssertEqual(line(stamp(date: nil, modified: true)),
                       "Version 0.1.0 (1), built from d5937c0 with local changes. The date it was built was not recorded.")
    }

    // MARK: - No commit

    func testABuildWithNoStampSaysTheCommitWasNotRecorded() {
        let bare: [String: Any] = [BuildInfo.versionKey: "0.1.0", BuildInfo.buildNumberKey: "1"]
        XCTAssertEqual(line(bare), "Version 0.1.0 (1). The commit it was built from was not recorded.")
    }

    /// A commit that is empty, spaces alone or not text is no commit.
    func testACommitThatIsEmptyOrNotTextReadsAsNone() {
        for commit in ["", "   ", "\n"] as [String] {
            XCTAssertEqual(line(stamp(commit: commit, date: nil)),
                           "Version 0.1.0 (1). The commit it was built from was not recorded.", "[\(commit)]")
        }
        var dictionary = stamp(date: nil)
        dictionary[BuildInfo.commitKey] = 1_234_567
        XCTAssertNil(BuildInfo(infoDictionary: dictionary).commit)
        dictionary[BuildInfo.commitKey] = true
        XCTAssertNil(BuildInfo(infoDictionary: dictionary).commit)
    }

    /// The script writes all three or none, so this is a stamp that was edited:
    /// what was read is named, and what was not is said not to be recorded.
    func testADateWithNoCommitIsNamedAndTheCommitIsSaidNotToBeRecorded() {
        XCTAssertEqual(line(stamp(commit: nil)),
                       "Version 0.1.0 (1), built on 2 Oct 2026. The commit it was built from was not recorded.")
    }

    /// With no commit there is no tree the app can say anything about.
    func testABuildWithNoCommitSaysNothingAboutLocalChanges() {
        XCTAssertEqual(line(stamp(commit: nil, date: nil, modified: true)),
                       "Version 0.1.0 (1). The commit it was built from was not recorded.")
        XCTAssertEqual(line(stamp(commit: nil, modified: true)),
                       "Version 0.1.0 (1), built on 2 Oct 2026. The commit it was built from was not recorded.")
    }

    // MARK: - No version

    func testNoVersionIsSaidNotToBeRecorded() {
        XCTAssertEqual(line(stamp(version: nil, build: nil)),
                       "Version not recorded, built from d5937c0 on 2 Oct 2026")
        XCTAssertEqual(line(stamp(version: nil, build: nil, commit: nil, date: nil)),
                       "Version not recorded. The commit it was built from was not recorded.")
    }

    func testABuildNumberWithNoVersionIsNamedAsABuild() {
        XCTAssertEqual(line(stamp(version: nil)),
                       "Version not recorded (build 1), built from d5937c0 on 2 Oct 2026")
    }

    func testAVersionWithNoBuildNumberIsNamedAlone() {
        XCTAssertEqual(line(stamp(build: nil)), "Version 0.1.0, built from d5937c0 on 2 Oct 2026")
    }

    func testAVersionOfSpacesOrNotTextReadsAsNone() {
        for version in ["", "  ", "\t"] {
            XCTAssertEqual(line(stamp(version: version, build: nil)),
                           "Version not recorded, built from d5937c0 on 2 Oct 2026", "[\(version)]")
        }
        var dictionary = stamp()
        dictionary[BuildInfo.versionKey] = 0.1
        dictionary[BuildInfo.buildNumberKey] = ["1"]
        XCTAssertNil(BuildInfo(infoDictionary: dictionary).version)
        XCTAssertNil(BuildInfo(infoDictionary: dictionary).buildNumber)
    }

    func testNoDictionaryAtAllReadsAsNothingRecordedAndIsNotACrash() {
        XCTAssertEqual(BuildInfo(infoDictionary: nil),
                       BuildInfo(version: nil, buildNumber: nil, commit: nil, date: nil, modified: nil))
        XCTAssertEqual(line(nil), "Version not recorded. The commit it was built from was not recorded.")
        XCTAssertEqual(line([:]), line(nil))
    }

    func testSpacesAroundAValueAreNotPartOfIt() {
        let read = BuildInfo(infoDictionary: stamp(version: " 0.1.0 ", build: "1\n", commit: "\td5937c0 "))
        XCTAssertEqual(read.version, "0.1.0")
        XCTAssertEqual(read.buildNumber, "1")
        XCTAssertEqual(read.commit, "d5937c0")
    }

    // MARK: - A date that does not parse

    /// Each of these reads as no date, so the line says the date was not
    /// recorded and names none. A day or an hour that does not exist is one: the
    /// system's reader would carry the 30th of February over to March, and show a
    /// day the stamp never named.
    func testADateThatDoesNotParseReadsAsNotRecorded() {
        let bad = ["", " ", "yesterday", "2026-10-05", "2026-10-05T10:51:08", "2026-02-30T10:00:00Z",
                   "2026-13-01T10:00:00Z", "2026-10-05T25:00:00Z", "2026-10-05T10:61:00Z",
                   "2026-10-05T10:51:08Zjunk", " 2026-10-05T10:51:08Z", "2026-10-05T10:51:08Z\n",
                   "2026-10-05T10:51:08.123Z", "20261005T105108Z", "05/10/2026", "1791197468"]
        for text in bad {
            XCTAssertNil(BuildInfo.date(fromStamp: text), "[\(text)]")
            XCTAssertNil(BuildInfo(infoDictionary: stamp(date: text)).date, "[\(text)]")
            XCTAssertEqual(line(stamp(date: text)),
                           "Version 0.1.0 (1), built from d5937c0. The date it was built was not recorded.", "[\(text)]")
        }
    }

    func testADateThatIsNotTextReadsAsNotRecorded() {
        for value in [1_791_197_468, true, 2.5, Date(), ["2026-10-05T10:51:08Z"]] as [Any] {
            var dictionary = stamp(date: nil)
            dictionary[BuildInfo.dateKey] = value
            XCTAssertNil(BuildInfo(infoDictionary: dictionary).date, "\(value)")
            XCTAssertEqual(line(dictionary), "Version 0.1.0 (1), built from d5937c0. The date it was built was not recorded.",
                           "\(value)")
        }
        XCTAssertNil(BuildInfo.date(fromStamp: nil))
    }

    func testTheShapeTheScriptWritesIsRead() {
        XCTAssertEqual(BuildInfo.date(fromStamp: "2026-10-05T10:51:08Z"), moment("2026-10-05T10:51:08Z"))
        XCTAssertEqual(BuildInfo.date(fromStamp: "2026-12-31T23:59:59Z"), moment("2026-12-31T23:59:59Z"))
        XCTAssertEqual(BuildInfo.date(fromStamp: "2028-02-29T00:00:00Z"), moment("2028-02-29T00:00:00Z"))
        XCTAssertNil(BuildInfo.date(fromStamp: "2026-02-29T00:00:00Z"), "2026 is not a leap year")
    }

    // MARK: - "With local changes" only when the key is true

    func testWithLocalChangesIsSaidOnlyWhenTheKeyIsTrue() {
        let said = SettingsText.localChanges
        XCTAssertTrue(line(stamp(modified: true)).contains(said))
        XCTAssertTrue(line(stamp(modified: NSNumber(value: true))).contains(said))

        let notTrue: [Any?] = [false, NSNumber(value: false), nil, "true", "yes", "YES", "1", 1, NSNumber(value: 1),
                               1.0, NSNull(), [true], Date()]
        for value in notTrue {
            XCTAssertFalse(line(stamp(modified: value)).contains(said), "\(String(describing: value))")
        }
        XCTAssertEqual(SettingsText.localChanges, "with local changes")
    }

    /// A stamp that says the tracked files were unchanged is not the same as a
    /// stamp that says nothing: the first is false and the second is nil, which
    /// is how a value that is not a Boolean, and a key that is not there, read.
    /// The line is the same for both, since neither says there were changes.
    func testTheModifiedKeyIsReadAsTrueFalseOrNothingAtAll() {
        func read(_ value: Any?) -> Bool? { BuildInfo(infoDictionary: stamp(modified: value)).modified }
        XCTAssertEqual(read(true), true)
        XCTAssertEqual(read(NSNumber(value: true)), true)
        XCTAssertEqual(read(false), false)
        XCTAssertEqual(read(NSNumber(value: false)), false)

        let saysNothing: [Any?] = [nil, "true", "false", "yes", "1", 1, 0, NSNumber(value: 1), NSNumber(value: 0),
                                   1.0, NSNull(), [true], Date()]
        for value in saysNothing {
            XCTAssertNil(read(value), "\(String(describing: value))")
            XCTAssertEqual(line(stamp(modified: value)), line(stamp(modified: false)), "\(String(describing: value))")
        }
        XCTAssertNil(BuildInfo(infoDictionary: nil).modified)
        XCTAssertNil(BuildInfo(infoDictionary: [:]).modified)
        XCTAssertNil(BuildInfo.flag(nil))
        XCTAssertEqual(BuildInfo.flag(NSNumber(value: false)), false)
    }

    // MARK: - Every line names the version

    /// Every combination of what a stamp can hold and lack: a line always begins
    /// with the stem, names the version or says it was not recorded, never prints
    /// an optional, and is made of words and not of gaps.
    func testEveryLineNamesTheVersion() {
        let versions: [String?] = ["0.1.0", nil]
        let builds: [String?] = ["1", nil]
        let commits: [String?] = ["d5937c0", nil]
        let dates: [Date?] = [Date(timeIntervalSince1970: 1_790_932_500), nil]
        var seen = Set<String>()
        for version in versions {
            for build in builds {
                for commit in commits {
                    for date in dates {
                        for modified in [nil, false, true] as [Bool?] {
                            let text = SettingsText.version(info(version: version, buildNumber: build, commit: commit,
                                                                 date: date, modified: modified),
                                                            date: formatter().string(from:))
                            seen.insert(text)
                            XCTAssertTrue(text.hasPrefix(SettingsText.versionStem + " "), text)
                            XCTAssertTrue(text.hasPrefix("\(SettingsText.versionStem) \(version ?? SettingsText.versionNotRecorded)"),
                                          text)
                            for fragment in ["nil", "Optional", "  ", " ,", ",,", ". .", " .", "()"] {
                                XCTAssertFalse(text.contains(fragment), "[\(fragment)] in \(text)")
                            }
                            XCTAssertEqual(text, text.trimmingCharacters(in: .whitespaces), text)
                            XCTAssertEqual(text.contains(SettingsText.commitNotRecorded), commit == nil, text)
                            XCTAssertEqual(text.contains(SettingsText.dateNotRecorded), commit != nil && date == nil, text)
                            XCTAssertEqual(text.contains(SettingsText.localChanges), commit != nil && modified == true, text)
                            if let commit { XCTAssertTrue(text.contains(commit), text) }
                        }
                    }
                }
            }
        }
        // Eight with no commit, where changes are not said, and sixteen with one: a
        // stamp that says nothing about changes reads as one that says there were none.
        XCTAssertEqual(seen.count, 24, "each combination that can differ makes a line of its own")
    }

    func testTheWordsAreTheOnesThePlanGives() {
        XCTAssertEqual(SettingsText.versionStem, "Version")
        XCTAssertEqual(SettingsText.versionNotRecorded, "not recorded")
        XCTAssertEqual(SettingsText.commitNotRecorded, "The commit it was built from was not recorded.")
        XCTAssertEqual(SettingsText.dateNotRecorded, "The date it was built was not recorded.")
    }

    // MARK: - The date is shown in the locale it is given

    func testTheDateIsShownInTheLocaleAndTimeZoneItIsGiven() {
        XCTAssertEqual(line(stamp(), locale: "en_GB"), "Version 0.1.0 (1), built from d5937c0 on 2 Oct 2026")
        XCTAssertEqual(line(stamp(), locale: "en_US"), "Version 0.1.0 (1), built from d5937c0 on Oct 2, 2026")

        let lateInTheDay = stamp(date: "2026-10-02T23:30:00Z")
        XCTAssertEqual(line(lateInTheDay, timeZone: "UTC"), "Version 0.1.0 (1), built from d5937c0 on 2 Oct 2026")
        XCTAssertEqual(line(lateInTheDay, timeZone: "Pacific/Auckland"),
                       "Version 0.1.0 (1), built from d5937c0 on 3 Oct 2026")
        XCTAssertEqual(line(lateInTheDay, timeZone: "America/Los_Angeles"),
                       "Version 0.1.0 (1), built from d5937c0 on 2 Oct 2026")
    }

    func testTheFormatterShowsADateAndNoTime() {
        let shown = formatter().string(from: moment("2026-10-02T09:15:00Z"))
        XCTAssertEqual(shown, "2 Oct 2026")
        XCTAssertFalse(shown.contains(":"))
    }

    /// The formatter is asked for a date that was read and for no other.
    func testTheFormatterIsAskedOnlyWhenThereIsADate() {
        var asked: [Date] = []
        let withDate = SettingsText.version(info()) { asked.append($0); return "THE DATE" }
        XCTAssertEqual(withDate, "Version 0.1.0 (1), built from d5937c0 on THE DATE")
        XCTAssertEqual(asked, [Date(timeIntervalSince1970: 1_790_932_500)])

        asked = []
        _ = SettingsText.version(info(date: nil)) { asked.append($0); return "x" }
        _ = SettingsText.version(info(commit: nil, date: nil)) { asked.append($0); return "x" }
        XCTAssertEqual(asked, [])
    }

    // MARK: - The script writes what the core reads

    private var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // NotificationCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // package root
    }

    /// The lines of a script that are not shell comments.
    private func codeLines(of script: String) throws -> [String] {
        try String(contentsOf: root.appendingPathComponent(script), encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
    }

    /// The core reads three keys and the script writes them, in two languages,
    /// so a name changed in one place would leave every build looking
    /// unstamped. And they go in before the signature, which seals the file:
    /// after it they would break the bundle.
    func testTheBuildScriptWritesTheThreeKeysTheCoreReadsBeforeItSigns() throws {
        let code = try codeLines(of: "Scripts/make-app.sh")
        func index(of fragment: String) -> Int? { code.firstIndex { $0.contains(fragment) } }

        let signing = try XCTUnwrap(index(of: "codesign --force"), "the script no longer signs")
        for key in [BuildInfo.commitKey, BuildInfo.dateKey, BuildInfo.modifiedKey] {
            let written = try XCTUnwrap(index(of: ":\(key) "), "the script does not write \(key)")
            XCTAssertLessThan(written, signing, "\(key) is written after the signature seals the file")
        }
        let copy = try XCTUnwrap(index(of: "Contents/Info.plist"))
        let firstKey = try XCTUnwrap(index(of: ":\(BuildInfo.commitKey) "))
        XCTAssertLessThan(copy, firstKey, "the keys go into the staged copy")
        XCTAssertNotNil(index(of: "+%Y-%m-%dT%H:%M:%SZ"), "the date is written in the shape the core reads")
        XCTAssertTrue(code.contains { $0.contains("date -u") }, "the date is written in UTC")
        XCTAssertTrue(code.contains { $0.contains(":\(BuildInfo.modifiedKey) bool") }, "the modified key is a Boolean")
    }

    /// A build that is not stamped says why, and says it differently for each
    /// way it can happen, since one sentence for all of them was wrong for most:
    /// a folder inside another repository, a refusal by git and a failed status
    /// are not "no checkout". The keys are written only when none was recorded.
    func testTheBuildScriptSaysWhyItDidNotStamp() throws {
        let code = try codeLines(of: "Scripts/make-app.sh")
        let marker = "STAMP_SKIP=\""
        let reasons: [String] = code.compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(marker), trimmed.hasSuffix("\""), trimmed != "\(marker)\"" else { return nil }
            return String(trimmed.dropFirst(marker.count).dropLast())
        }
        XCTAssertEqual(reasons.count, 4, "one reason for each way of not stamping")
        XCTAssertEqual(Set(reasons).count, reasons.count, "no two ways of not stamping share a sentence")
        for fragment in ["no git checkout", "inside another repository", "no commit", "git status failed"] {
            XCTAssertEqual(reasons.filter { $0.contains(fragment) }.count, 1, "[\(fragment)]")
        }

        let said = try XCTUnwrap(code.first { $0.contains("Not stamping the build") }, "the script no longer says so")
        XCTAssertTrue(said.contains("$STAMP_SKIP"), "the message does not give the reason")
        XCTAssertFalse(code.contains { $0.contains("no git checkout with a commit here") },
                       "the one sentence that was wrong for most of them is back")

        let guardLine = try XCTUnwrap(code.firstIndex { $0.contains("if [ -z \"$STAMP_SKIP\" ]") },
                                      "the keys are not held back by a reason")
        let firstKey = try XCTUnwrap(code.firstIndex { $0.contains(":\(BuildInfo.commitKey) ") })
        XCTAssertLessThan(guardLine, firstKey, "a key is written whatever the reason")
    }

    /// The check that decides the modified key is the plan's, and counts files
    /// git tracks. A new file it does not track yet is not counted, though the
    /// build compiles it, which is why the words say "tracked" and the line says
    /// nothing when it does not say "with local changes".
    func testTheModifiedKeyIsDecidedByTheTrackedFilesAlone() throws {
        let code = try codeLines(of: "Scripts/make-app.sh")
        XCTAssertTrue(code.contains { $0.contains("git status --porcelain --untracked-files=no") },
                      "the script no longer asks git for the tracked files alone")
        XCTAssertFalse(code.contains { $0.contains("git status") && $0.contains("--untracked-files=all") })
    }

    /// The repository holds no build's details: they are made at build time.
    func testTheRepositorysOwnPropertyListHoldsNoStamp() throws {
        let plist = try String(contentsOf: root.appendingPathComponent("Resources/Info.plist"), encoding: .utf8)
        for key in [BuildInfo.commitKey, BuildInfo.dateKey, BuildInfo.modifiedKey] {
            XCTAssertFalse(plist.contains(key), "\(key) is in Resources/Info.plist")
        }
        XCTAssertTrue(plist.contains(BuildInfo.versionKey))
        XCTAssertTrue(plist.contains(BuildInfo.buildNumberKey))
    }
}
