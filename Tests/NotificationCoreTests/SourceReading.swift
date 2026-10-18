import Foundation
import XCTest

// How the tests that read the package's own files find and read them (#95). The
// app target has no tests, so the wiring suites hold its sources to what they
// are meant to say, and `PurityTests`, `NoNetworkTests` and the harness tests
// read the core, the probe and the scripts the same way. Each helper was once
// copied into every suite that used it, as many as 24 times; it is written here
// once, and a suite that needs another way to read keeps that one to itself.

/// The package's root, found from this file's own path.
enum PackageRoot {
    static let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // NotificationCoreTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // package root
}

enum SourceCode {
    /// A source file's code: no comments, each line's spacing collapsed to single
    /// spaces and the lines that are left empty gone. A comment may name a call
    /// to explain it and is not a place the app makes one. A `//` inside a string
    /// would cut its line short, which is harmless for the lines read here, since
    /// none holds one.
    static func code(of source: String) -> String {
        source.components(separatedBy: "\n")
            .map { line -> String in
                let code = line.range(of: "//").map { String(line[..<$0.lowerBound]) } ?? line
                return code.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    /// The text between the braces of the body whose opening line is `signature`,
    /// which ends in its `{`. Strings in the functions read here hold no braces.
    static func body(of signature: String, in code: String) -> String? {
        guard code.components(separatedBy: signature).count == 2, let found = code.range(of: signature) else { return nil }
        var depth = 0
        var start: String.Index?
        var index = code.index(before: found.upperBound)
        while index < code.endIndex {
            switch code[index] {
            case "{":
                depth += 1
                if start == nil { start = code.index(after: index) }
            case "}":
                depth -= 1
                if depth == 0, let start { return String(code[start..<index]) }
            default: break
            }
            index = code.index(after: index)
        }
        return nil
    }
}

/// An app source file's code, as `SourceCode.code(of:)` reads it, by its path
/// from `Sources/SignalLadder`.
func code(_ file: String) throws -> String {
    SourceCode.code(of: try XCTUnwrap(AppSources.read(file), "\(file) cannot be read at \(AppSources.directory.path)"))
}

/// Any source file's code, as `SourceCode.code(of:)` reads it, by its path from
/// the package root.
func packageCode(_ path: String) throws -> String {
    SourceCode.code(of: try String(contentsOf: PackageRoot.url.appendingPathComponent(path), encoding: .utf8))
}

/// How many times `needle` stands in `text`.
func count(_ needle: String, in text: String) -> Int {
    text.components(separatedBy: needle).count - 1
}

/// The body whose opening line is `signature`, which fails the test when the
/// signature is not there exactly once or its body is not closed.
func body(of signature: String, in code: String) throws -> String {
    try XCTUnwrap(SourceCode.body(of: signature, in: code),
                  "\(signature) is not in the source exactly once, or is not closed")
}

/// Where `needle` first stands in `text`, which fails the test when it is not there.
func position(of needle: String, in text: String) throws -> String.Index {
    try XCTUnwrap(text.range(of: needle), "\(needle) is not there").lowerBound
}

func trimmed(_ text: String) -> String {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
}
