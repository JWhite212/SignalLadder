import XCTest
@testable import RuleStorage

/// The rules file is the one thing this app can destroy. Every guarantee is
/// tested against a real folder on disk, including the failures in between.
final class RulesFileTests: XCTestCase {
    private var folder: URL!
    private var url: URL { folder.appendingPathComponent("rules.json") }
    private var previous: URL { folder.appendingPathComponent(RulesFile.previousName) }
    private let date = Date(timeIntervalSince1970: 1_790_000_000)

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("RulesFileTests-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func bytes(_ s: String) -> Data { Data(s.utf8) }
    private func contents(_ u: URL) -> String? { (try? Data(contentsOf: u)).map { String(decoding: $0, as: UTF8.self) } }

    /// A writer that fails for one destination and writes the rest for real.
    private func failing(at doomed: String) -> RulesFile.Writer {
        { data, destination in
            if destination.lastPathComponent == doomed { throw CocoaError(.fileWriteOutOfSpace) }
            try data.write(to: destination, options: .atomic)
        }
    }

    // MARK: - Reading

    func testNoFileIsAStateWithItsOwnFingerprint() throws {
        let snapshot = try RulesFile(url: url).read()
        XCTAssertNil(snapshot.data)
        XCTAssertEqual(snapshot.fingerprint, .noFile)
    }

    func testTheFingerprintFollowsTheBytes() {
        XCTAssertEqual(RulesFile.Fingerprint(bytes("a")), RulesFile.Fingerprint(bytes("a")))
        XCTAssertNotEqual(RulesFile.Fingerprint(bytes("a")), RulesFile.Fingerprint(bytes("a ")))
        XCTAssertNotEqual(RulesFile.Fingerprint(Data()), .noFile, "an empty file is not a missing one")
    }

    func testAFileThatCannotBeOpenedIsReportedNotTreatedAsMissing() throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        XCTAssertThrowsError(try RulesFile(url: url).read()) {
            guard case RulesFile.ReadError.unopenable? = $0 as? RulesFile.ReadError else { return XCTFail("\($0)") }
        }
    }

    // MARK: - Saving

    func testASaveWritesTheFileAndKeepsTheVersionItReplaced() throws {
        try bytes("A").write(to: url)
        let file = RulesFile(url: url)
        let loaded = try file.read()

        XCTAssertEqual(try file.save(bytes("B"), expecting: loaded.fingerprint), .saved)
        XCTAssertEqual(contents(url), "B")
        XCTAssertEqual(contents(previous), "A")
    }

    func testTheFirstSaveWhenThereWasNoFileKeepsNoBackup() throws {
        XCTAssertEqual(try RulesFile(url: url).save(bytes("B"), expecting: .noFile), .saved)
        XCTAssertEqual(contents(url), "B")
        XCTAssertFalse(FileManager.default.fileExists(atPath: previous.path))
    }

    func testAFileEditedSinceItWasReadIsNotOverwritten() throws {
        try bytes("A").write(to: url)
        let file = RulesFile(url: url)
        let loaded = try file.read()
        try bytes("A, edited by hand").write(to: url)

        XCTAssertEqual(try file.save(bytes("B"), expecting: loaded.fingerprint),
                       .changedOnDisk(RulesFile.Snapshot(data: bytes("A, edited by hand"))))
        XCTAssertEqual(contents(url), "A, edited by hand")
        XCTAssertFalse(FileManager.default.fileExists(atPath: previous.path), "a refused save touches nothing")
    }

    func testAFileThatAppearedSinceItWasReadIsNotOverwritten() throws {
        let file = RulesFile(url: url)
        try bytes("written elsewhere").write(to: url)
        XCTAssertEqual(try file.save(bytes("B"), expecting: .noFile),
                       .changedOnDisk(RulesFile.Snapshot(data: bytes("written elsewhere"))))
        XCTAssertEqual(contents(url), "written elsewhere")
    }

    func testAFileDeletedSinceItWasReadIsNotSilentlyRecreated() throws {
        try bytes("A").write(to: url)
        let file = RulesFile(url: url)
        let loaded = try file.read()
        try FileManager.default.removeItem(at: url)

        XCTAssertEqual(try file.save(bytes("B"), expecting: loaded.fingerprint), .changedOnDisk(RulesFile.Snapshot(data: nil)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    // MARK: - Failures in between

    func testWhenTheFinalWriteFailsTheOriginalIsWhole() throws {
        try bytes("A").write(to: url)
        let file = RulesFile(url: url, writer: failing(at: "rules.json"))
        let loaded = try file.read()

        XCTAssertThrowsError(try file.save(bytes("B"), expecting: loaded.fingerprint))
        XCTAssertEqual(contents(url), "A", "rules.json must never be missing or half-written")
        XCTAssertEqual(contents(previous), "A")
    }

    func testWhenTheBackupFailsNothingIsWritten() throws {
        try bytes("A").write(to: url)
        let file = RulesFile(url: url, writer: failing(at: RulesFile.previousName))
        let loaded = try file.read()

        XCTAssertThrowsError(try file.save(bytes("B"), expecting: loaded.fingerprint))
        XCTAssertEqual(contents(url), "A", "no backup, no write")
    }

    func testASaveLeavesNoTemporaryFilesBehind() throws {
        try bytes("A").write(to: url)
        let file = RulesFile(url: url)
        _ = try file.save(bytes("B"), expecting: try file.read().fingerprint)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted(),
                       ["rules.json", RulesFile.previousName])
    }

    // MARK: - Where it lives

    func testASymlinkedFileIsWrittenThroughAndTheLinkSurvives() throws {
        let elsewhere = folder.appendingPathComponent("synced", isDirectory: true)
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        let target = elsewhere.appendingPathComponent("my-rules.json")
        try bytes("A").write(to: target)
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: target)
        let file = RulesFile(url: url)

        XCTAssertEqual(try file.save(bytes("B"), expecting: try file.read().fingerprint), .saved)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: url.path), target.path,
                       "replacing the link with a plain file would silently cut the user's arrangement")
        XCTAssertEqual(contents(target), "B")
        XCTAssertEqual(contents(previous), "A")
    }

    func testALinkWhoseTargetIsMissingIsReportedNotTreatedAsNoFile() throws {
        // An unmounted drive, or a sync client that has not fetched the file
        // yet. Reading it as "no file" would let a save replace the link with
        // a new file holding only the new rules — the real ones orphaned.
        let target = folder.appendingPathComponent("unmounted/my-rules.json")
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: target)
        let file = RulesFile(url: url)

        XCTAssertThrowsError(try file.read()) {
            guard case RulesFile.ReadError.unopenable(let reason)? = $0 as? RulesFile.ReadError else { return XCTFail("\($0)") }
            XCTAssertTrue(reason.contains(target.path), reason)
        }
        XCTAssertThrowsError(try file.save(bytes("B"), expecting: .noFile))
        XCTAssertThrowsError(try file.saveReplacing(bytes("B"), at: date))
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: url.path), target.path,
                       "the link survives, still pointing where the user set it")
    }

    func testARelativeLinkIsFollowedWhenItsTargetExistsAndRefusedWhenItDoesNot() throws {
        let synced = folder.appendingPathComponent("synced", isDirectory: true)
        try FileManager.default.createDirectory(at: synced, withIntermediateDirectories: true)
        try bytes("A").write(to: synced.appendingPathComponent("rules.json"))
        try FileManager.default.createSymbolicLink(atPath: url.path, withDestinationPath: "synced/rules.json")
        let file = RulesFile(url: url)

        XCTAssertEqual(try file.save(bytes("B"), expecting: try file.read().fingerprint), .saved)
        XCTAssertEqual(contents(synced.appendingPathComponent("rules.json")), "B")
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: url.path), "synced/rules.json")

        try FileManager.default.removeItem(at: synced)
        XCTAssertThrowsError(try file.read())
        XCTAssertThrowsError(try file.save(bytes("C"), expecting: .noFile))
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: url.path), "synced/rules.json")
    }

    func testAMissingFolderIsRecreated() throws {
        let nested = folder.appendingPathComponent("gone/rules.json")
        XCTAssertEqual(try RulesFile(url: nested).save(bytes("B"), expecting: .noFile), .saved)
        XCTAssertEqual(contents(nested), "B")
    }

    // MARK: - Save Anyway

    func testSaveAnywayKeepsWhatItReplacedUnderItsOwnName() throws {
        try bytes("P").write(to: previous)
        try bytes("A, edited by hand").write(to: url)

        let kept = try XCTUnwrap(try RulesFile(url: url).saveReplacing(bytes("B"), at: date))
        XCTAssertTrue(kept.lastPathComponent.hasPrefix("rules.replaced-") && kept.lastPathComponent.hasSuffix(".json"),
                      kept.lastPathComponent)
        XCTAssertEqual(contents(kept), "A, edited by hand")
        XCTAssertEqual(contents(url), "B")
        XCTAssertEqual(contents(previous), "P", "the rotating slot is not where a conflict's loser is kept")
    }

    func testTwoReplacementsInTheSameSecondKeepBoth() throws {
        let file = RulesFile(url: url)
        try bytes("first").write(to: url)
        let a = try XCTUnwrap(try file.saveReplacing(bytes("second"), at: date))
        let b = try XCTUnwrap(try file.saveReplacing(bytes("third"), at: date))
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(contents(a), "first")
        XCTAssertEqual(contents(b), "second")
    }

    func testSaveAnywayWithNoFileKeepsNothing() throws {
        XCTAssertNil(try RulesFile(url: url).saveReplacing(bytes("B"), at: date))
        XCTAssertEqual(contents(url), "B")
    }

    // MARK: - Creating

    func testCreatingNeverReplacesAFile() throws {
        let file = RulesFile(url: url)
        XCTAssertTrue(try file.createIfMissing(bytes("example")))
        XCTAssertFalse(try file.createIfMissing(bytes("another")))
        XCTAssertEqual(contents(url), "example")
    }
}
