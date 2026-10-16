import XCTest

final class PurityTests: XCTestCase {
    /// Every Swift file under `Sources/NotificationCore`, in its folders too: a
    /// file moved into a folder is held exactly as one beside the others is.
    /// Listing the folder's top level alone let such a file import anything.
    private func coreSources() throws -> [URL] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // NotificationCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // package root
            .appendingPathComponent("Sources/NotificationCore")
        let walker = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        let files = walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty, "Found no sources at \(root.path)")
        return files
    }

    /// NotificationCore must never import a framework that would make it
    /// untestable without a granted TCC permission.
    func testCoreHasNoForbiddenImports() throws {
        let forbidden = ["ApplicationServices", "AppKit", "Cocoa", "Carbon", "UserNotifications", "AVFoundation", "Speech",
                         "ServiceManagement"]
        for file in try coreSources() {
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
        for file in try coreSources() {
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
        for file in try coreSources() {
            let text = try String(contentsOf: file, encoding: .utf8)
            for symbol in forbidden {
                XCTAssertFalse(text.contains(symbol),
                               "\(file.lastPathComponent) references \(symbol) — content must never reach disk or network")
            }
        }
    }
}
