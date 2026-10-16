import Foundation
import XCTest
@testable import NotificationCore

/// Every word the rule editor's text offers is used by some source other than its own
/// declaration. A sentence nothing shows can be tested and kept in step with the rules for
/// years while no user ever reads it, and it misleads whoever reads the code: the preset
/// sentence `presetMeaning` was one, superseded by the ladder's own sentence and kept alive
/// only by its tests (workflow audit, 2026-10-16, finding 16). This reads every source under
/// `Sources`, as `PurityTests` and the wiring tests read theirs.
final class EditorWordsInUseTests: XCTestCase {
    private var sourcesDirectory: URL { AppSources.directory.deletingLastPathComponent() }

    private func swiftFiles() throws -> [URL] {
        let walker = try XCTUnwrap(FileManager.default.enumerator(at: sourcesDirectory, includingPropertiesForKeys: nil))
        return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    private func occurrences(of name: String, in text: String) throws -> Int {
        let pattern = try NSRegularExpression(pattern: "\\b\(NSRegularExpression.escapedPattern(for: name))\\b")
        return pattern.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    func testEveryPublicWordOfTheEditorIsUsedBySomeSource() throws {
        let files = try swiftFiles()
        let editor = try XCTUnwrap(files.first { $0.lastPathComponent == "EditorText.swift" }, "EditorText.swift is gone")
        let declared = try String(contentsOf: editor, encoding: .utf8)
        let declaration = try NSRegularExpression(pattern: "public static (?:func|let|var) ([A-Za-z_][A-Za-z0-9_]*)")
        let names = Set(declaration.matches(in: declared, range: NSRange(declared.startIndex..., in: declared)).compactMap {
            Range($0.range(at: 1), in: declared).map { String(declared[$0]) }
        })
        XCTAssertGreaterThan(names.count, 50, "the declarations are found")
        let texts = try files.map { try String(contentsOf: $0, encoding: .utf8) }
        for name in names.sorted() {
            let uses = try texts.reduce(0) { $0 + (try occurrences(of: name, in: $1)) } - 1
            XCTAssertGreaterThan(uses, 0, "EditorText.\(name) is used by no source: show it, or delete it and its tests")
        }
    }
}
