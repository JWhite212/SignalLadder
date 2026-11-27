import AVFoundation
import XCTest
@testable import AlertAudio

/// An alert looks a sound up in the sounds folder, and a save that replaces a sound renames it away and then renames
/// the new one into its place. Between the two renames nothing has the sound's name, so an alert that arrived then
/// found no sound and played nothing. The alert looks under the folder's lock, as the renames are made under it, so
/// it waits the few renames out and finds the new sound.
@MainActor
final class AlertPlayerFolderLockTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("AlertPlayerFolderLockTests-\(UUID().uuidString)")
        for folder in ["system", "custom"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private var custom: URL { root.appendingPathComponent("custom") }

    private var library: SoundLibrary {
        SoundLibrary(systemDirectory: root.appendingPathComponent("system"), customDirectory: custom)
    }

    private func player() -> AlertPlayer {
        AlertPlayer(library: library, readOutput: { OutputState(muted: false, volume: 0.5) }, mode: .offline)
    }

    /// The old sound is 0.1 s and the one that replaces it 0.2 s, so which one was found is what its length says.
    private func startReplacing(holding held: HeldRename) throws -> DispatchGroup {
        try TestAudio.write(custom.appendingPathComponent("Alarm.wav"), seconds: 0.1)
        let staged = try TestAudio.write(
            custom.appendingPathComponent("\(SoundInstall.renderingPrefix)\(UUID().uuidString).wav"), seconds: 0.2)
        var installer = SoundInstall(library: library)
        installer.move = held.move
        nonisolated(unsafe) let installing = installer
        let installed = DispatchGroup()
        DispatchQueue.global().async(group: installed) { _ = installing.install(staged, as: "Alarm", replacing: true) }
        XCTAssertTrue(held.waitUntilHeld(), "the rename was never reached")
        return installed
    }

    func testAnAlertThatArrivesBetweenTheRenamesOfAReplaceWaitsForThemAndFindsTheNewSound() throws {
        let held = HeldRename()
        let installed = try startReplacing(holding: held)
        XCTAssertNil(library.url(for: "Alarm"), "the gap is there: the old sound is set aside and the new one has no name yet")

        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { held.letGo() }
        let started = Date()
        let sound = try player().resolve("Alarm", ruleGainDB: 0)
        let waited = Date().timeIntervalSince(started)
        installed.wait()

        XCTAssertGreaterThanOrEqual(waited, 0.25, "it waited for the second rename")
        XCTAssertEqual(sound.displayName, "Alarm")
        XCTAssertEqual(Double(sound.buffer.frameLength), 0.2 * 48_000, accuracy: 200, "the sound that replaced the old one")
    }

    func testPreparingASoundWaitsForAReplaceAsPlayingDoes() throws {
        let held = HeldRename()
        let installed = try startReplacing(holding: held)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { held.letGo() }
        XCTAssertNoThrow(try player().prepare(sound: "Alarm"))
        installed.wait()
    }

    func testASoundThatIsNotThereIsStillSaidNotToBeThere() {
        XCTAssertThrowsError(try player().resolve("Nothing", ruleGainDB: 0)) {
            XCTAssertEqual($0 as? AlertPlayer.Failure, .soundNotFound("Nothing"))
        }
    }

    /// The lock is taken again by the same thread, as giving a name does to finish a stopped replace: an alert that is
    /// resolved from inside a step that holds it must not wait on itself.
    func testAnAlertResolvedByAThreadThatAlreadyHoldsTheLockDoesNotWaitOnItself() throws {
        try TestAudio.write(custom.appendingPathComponent("Alarm.wav"), seconds: 0.1)
        let p = player()
        let sound = try SoundInstall.whileTheFolderIsUntouched { try p.resolve("Alarm", ruleGainDB: 0) }
        XCTAssertEqual(sound.displayName, "Alarm")
    }
}
