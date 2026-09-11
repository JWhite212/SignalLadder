import XCTest

final class PurityTests: XCTestCase {
    /// NotificationCore must never import a framework that would make it
    /// untestable without a granted TCC permission.
    func testCoreHasNoForbiddenImports() throws {
        let forbidden = ["ApplicationServices", "AppKit", "Cocoa", "Carbon", "UserNotifications"]
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // NotificationCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // package root
            .appendingPathComponent("Sources/NotificationCore")

        let files = try FileManager.default
            .contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }

        XCTAssertFalse(files.isEmpty, "Found no sources at \(root.path)")

        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for framework in forbidden {
                XCTAssertFalse(
                    text.contains("import \(framework)"),
                    "\(file.lastPathComponent) imports \(framework)"
                )
            }
        }
    }
}
