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

    /// NotificationCore holds notification content now. Keeping UI frameworks
    /// out of it keeps the rule "content never leaves memory" auditable in one
    /// module rather than wherever a view happened to be written.
    func testCoreHasNoUIFrameworkImports() throws {
        let forbidden = ["SwiftUI", "Combine"]
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/NotificationCore")

        let files = try FileManager.default
            .contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }

        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for framework in forbidden {
                XCTAssertFalse(text.contains("import \(framework)"),
                               "\(file.lastPathComponent) imports \(framework)")
            }
        }
    }

    /// The ring buffer is the only place content lives. Nothing in Core may
    /// open a file handle or a URL — a regression here is a privacy breach, not
    /// a bug, and it would produce no symptom at runtime.
    func testCoreWritesNothingAnywhere() throws {
        let forbidden = ["FileManager", "FileHandle", "URLSession", "Data(contentsOf", "write(to"]
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/NotificationCore")

        let files = try FileManager.default
            .contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }

        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for symbol in forbidden {
                XCTAssertFalse(text.contains(symbol),
                               "\(file.lastPathComponent) references \(symbol) — content must never reach disk or network")
            }
        }
    }
}
