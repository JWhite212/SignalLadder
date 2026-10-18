import XCTest

/// `AppSources.read` reads a file with its extension files, so the wiring tests can follow a
/// type split over files (#96).
final class SourceFamilyTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("SourceFamilyTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: folder)
    }

    private func write(_ name: String, _ text: String) throws {
        try text.write(to: folder.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    func testAFileIsReadWithItsExtensionFilesInOrderOfName() throws {
        try write("App.swift", "main")
        try write("App+Menu.swift", "menu")
        try write("App+Health.swift", "health")
        XCTAssertEqual(AppSources.read("App.swift", in: folder), "main\nhealth\nmenu")
    }

    func testOnlyItsOwnExtensionFilesAreRead() throws {
        try write("App.swift", "main")
        try write("AppModel.swift", "not a part")
        try write("Other+App.swift", "not a part")
        try write("App+Notes.txt", "not swift")
        XCTAssertEqual(AppSources.read("App.swift", in: folder), "main")
    }

    func testAFileThatIsNotThereIsNilWhateverItsPartsAre() throws {
        try write("App+Menu.swift", "menu")
        XCTAssertNil(AppSources.read("App.swift", in: folder))
    }
}
