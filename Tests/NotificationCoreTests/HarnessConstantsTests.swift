import Foundation
import XCTest
@testable import NotificationCore

// Holds the live-verification script to the text the app shows (M5 plan,
// Ruling 18). `Scripts/verify-live.sh` looks for words the app also shows: the
// titles of its windows, the title of the menu's On Call item, and the wordings
// of the health line. A word the script typed for itself would go on passing
// after the app changed it, or fail with no reason a person could find. So the
// script reads each such word out of the file in NotificationCore that declares
// it, through one helper, `core_constant FILE NAME`, and these tests read the
// scripts as PurityTests reads the sources:
//
//  - every reference a script makes names a declaration that exists, once, in
//    the one shape the helper's `sed` can read: `public static let NAME = "TEXT"`;
//  - the script reads the window titles and the On Call item's title through
//    the helper, and its cause reading steps over the On Call item;
//  - the window titles are distinct and each begins with the app's name;
//  - no script types, as a quoted word of its own, the text of a constant it reads;
//  - the wordings the script takes for a health line are the ones `HealthTitle`
//    gives it, and no other line the menu can hold.
//
// These tests start no process and run no script. They read text.

/// A reference to a constant: the helper called with a file and a name.
private struct ConstantReference: Hashable {
    let script: String
    let file: String
    let name: String
}

private enum Harness {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // NotificationCoreTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // package root
    static let scripts = root.appendingPathComponent("Scripts")
    static let core = root.appendingPathComponent("Sources/NotificationCore")

    /// The helper's name, as a script calls it.
    static let helper = "core_constant"

    static func scriptNames() throws -> [String] {
        try FileManager.default.contentsOfDirectory(at: scripts, includingPropertiesForKeys: nil)
            .map(\.lastPathComponent)
            .filter { $0.hasSuffix(".sh") }
            .sorted()
    }

    static func read(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    static func script(_ name: String) throws -> String {
        try read(scripts.appendingPathComponent(name))
    }

    /// The lines of a script that are not shell comments. A comment may quote a
    /// word to explain it, and is not a place the script looks for one.
    static func codeLines(_ text: String) -> [String] {
        text.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
    }

    /// Every call of the helper with a file and a name, in the scripts that make
    /// any. The helper's own definition has no file argument and is not one.
    static func references() throws -> [ConstantReference] {
        let call = try NSRegularExpression(pattern: #"\#(helper)[ \t]+([A-Za-z][A-Za-z0-9]*\.swift)[ \t]+([A-Za-z][A-Za-z0-9]*)\b"#)
        var found: [ConstantReference] = []
        for script in try scriptNames() {
            let code = codeLines(try Harness.script(script)).joined(separator: "\n")
            for match in call.matches(in: code, range: NSRange(code.startIndex..., in: code)) {
                let file = String(code[Range(match.range(at: 1), in: code)!])
                let name = String(code[Range(match.range(at: 2), in: code)!])
                found.append(ConstantReference(script: script, file: file, name: name))
            }
        }
        return found
    }

    /// The declarations in the shape the helper reads, one to a line.
    static func declarations(in source: String) throws -> [(name: String, text: String)] {
        let shape = try NSRegularExpression(
            pattern: #"^[ \t]*public static let ([A-Za-z][A-Za-z0-9]*) = "([^"\\]*)"[ \t]*$"#,
            options: .anchorsMatchLines)
        return shape.matches(in: source, range: NSRange(source.startIndex..., in: source)).map { match in
            (name: String(source[Range(match.range(at: 1), in: source)!]),
             text: String(source[Range(match.range(at: 2), in: source)!]))
        }
    }

    /// The lines of Swift source that are not `//` comments.
    static func swiftCodeLines(_ source: String) -> [String] {
        source.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
    }

    /// Lines that declare `name` as a static constant in any shape at all.
    static func declarationLines(of name: String, in source: String) -> [String] {
        swiftCodeLines(source).filter {
            $0.range(of: #"\bstatic let \#(name)\b"#, options: .regularExpression) != nil
        }
    }
}

final class HarnessConstantsTests: XCTestCase {
    // MARK: - What the scripts read

    func testTheHarnessReadsTheTitlesItLooksForThroughTheHelper() throws {
        let verify = try Harness.script("verify-live.sh")
        XCTAssertTrue(verify.contains("\(Harness.helper)() {"), "verify-live.sh defines the helper it reads through")

        let references = try Harness.references().filter { $0.script == "verify-live.sh" }
        let titles: [(file: String, name: String)] = [
            ("WindowTitles.swift", "inspector"),
            ("WindowTitles.swift", "ruleEditor"),
            // The menu's On Call item: the cause reading steps over it, since
            // the line after the health line is this item whenever there is no cause.
            ("OnCall.swift", "menuTitle"),
        ]
        for title in titles {
            XCTAssertTrue(references.contains(ConstantReference(script: "verify-live.sh", file: title.file, name: title.name)),
                          "verify-live.sh does not read \(title.file)'s \(title.name) through \(Harness.helper)")
        }

        // And the cause reading uses it: without that, the On Call item is
        // printed as the health line's cause on every run that finds no cause.
        let lines = verify.components(separatedBy: "\n")
        let start = try XCTUnwrap(lines.firstIndex { $0.hasPrefix("health_and_cause() {") }, "verify-live.sh has no health_and_cause")
        let end = try XCTUnwrap(lines[start...].firstIndex { $0 == "}" }, "health_and_cause is not closed")
        XCTAssertTrue(lines[start..<end].contains { $0.contains("$ON_CALL_ITEM") },
                      "health_and_cause does not step over the On Call item, and would take it for the health line's cause")
        XCTAssertTrue(lines.contains { $0.hasPrefix("ON_CALL_ITEM=$(\(Harness.helper) OnCall.swift menuTitle)") },
                      "verify-live.sh does not set ON_CALL_ITEM from OnCallText.menuTitle")
    }

    func testEveryConstantAScriptReadsIsDeclaredOnOneLineInTheFileItNames() throws {
        let references = try Harness.references()
        XCTAssertFalse(references.isEmpty, "no script reads a constant, so nothing here is held")
        for reference in references {
            let url = Harness.core.appendingPathComponent(reference.file)
            guard let source = try? Harness.read(url) else {
                XCTFail("\(reference.script) reads \(reference.name) from \(reference.file), which is not in NotificationCore")
                continue
            }
            let strict = try Harness.declarations(in: source).filter { $0.name == reference.name }
            XCTAssertEqual(strict.count, 1,
                           "\(reference.script) reads \(reference.name) from \(reference.file), which must declare it once, on one line, "
                               + "as `public static let \(reference.name) = \"TEXT\"`")
            XCTAssertEqual(Harness.declarationLines(of: reference.name, in: source).count, strict.count,
                           "\(reference.file) declares \(reference.name) in a shape the helper does not read as well")
            if let text = strict.first?.text {
                XCTAssertFalse(text.isEmpty,
                               "\(reference.name) in \(reference.file) is empty, and a script that looks for it would find any line")
            }
        }
    }

    func testNoScriptTypesTheTextOfAConstantItReads() throws {
        for reference in try Harness.references() {
            let source = try Harness.read(Harness.core.appendingPathComponent(reference.file))
            guard let text = try Harness.declarations(in: source).first(where: { $0.name == reference.name })?.text,
                  !text.isEmpty else { continue }
            let code = Harness.codeLines(try Harness.script(reference.script))
            // Typed as a word of its own, in double or single quotes, as a
            // `grep`, a `case` arm or an AppleScript name would hold it. The same
            // letters inside a longer sentence are not a lookup.
            let typed = code.contains { $0.contains("\"\(text)\"") || $0.contains("'\(text)'") }
            XCTAssertFalse(typed,
                           "\(reference.script) has \"\(text)\" typed into it, and reads it as \(reference.name) as well: "
                               + "one of the two would be left behind by a change")
        }
    }

    // MARK: - The window titles

    func testTheWindowTitlesAreDistinctAndEachBeginsWithTheAppsName() throws {
        let source = try Harness.read(Harness.core.appendingPathComponent("WindowTitles.swift"))
        let titles = try Harness.declarations(in: source)
        XCTAssertGreaterThanOrEqual(titles.count, 2, "WindowTitles declares the Inspector's title and the rule editor's")
        XCTAssertEqual(Set(titles.map(\.text)).count, titles.count, "two windows share a title")
        XCTAssertEqual(Set(titles.map(\.name)).count, titles.count, "a name is declared twice")
        for title in titles {
            XCTAssertTrue(title.text.hasPrefix("SignalLadder"), "\(title.name) is \"\(title.text)\"")
        }
        // Every constant in the file is one the checks above can see, so a title
        // written in another shape cannot sit there unheld.
        let declared = Harness.swiftCodeLines(source).filter { $0.contains("static let ") }
        XCTAssertEqual(declared.count, titles.count, "WindowTitles holds a constant that is not `public static let NAME = \"TEXT\"`")
    }

    // MARK: - The health line

    /// The wordings the script takes for a health line: the quoted patterns on
    /// the arms of `is_health_line`'s `case`, each exact or, with a trailing `*`,
    /// a prefix, as `case` reads them.
    private func healthPatterns() throws -> [(text: String, isPrefix: Bool)] {
        let lines = try Harness.script("verify-live.sh").components(separatedBy: "\n")
        let start = try XCTUnwrap(lines.firstIndex { $0.hasPrefix("is_health_line() {") }, "verify-live.sh has no is_health_line")
        let end = try XCTUnwrap(lines[start...].firstIndex { $0 == "}" }, "is_health_line is not closed")
        let arms = lines[start..<end].filter { $0.contains(") return 0") }
        XCTAssertEqual(arms.count, 1, "is_health_line accepts its wordings on one arm")
        let quoted = try NSRegularExpression(pattern: #""([^"]*)"(\*)?"#)
        var patterns: [(text: String, isPrefix: Bool)] = []
        for arm in arms {
            let patternPart = String(arm[..<arm.range(of: ") return 0")!.lowerBound])
            for match in quoted.matches(in: patternPart, range: NSRange(patternPart.startIndex..., in: patternPart)) {
                patterns.append((text: String(patternPart[Range(match.range(at: 1), in: patternPart)!]),
                                 isPrefix: match.range(at: 2).location != NSNotFound))
            }
        }
        return patterns
    }

    private func recognised(_ line: String, by patterns: [(text: String, isPrefix: Bool)]) -> Bool {
        patterns.contains { $0.isPrefix ? line.hasPrefix($0.text) : line == $0.text }
    }

    /// Every health line `HealthTitle` can give, with the ages that change its words.
    private var healthLines: [String] {
        [
            HealthTitle.text(for: .verified, secondsSinceLastSuccessfulCanary: nil),
            HealthTitle.text(for: .verified, secondsSinceLastSuccessfulCanary: 5),
            HealthTitle.text(for: .verified, secondsSinceLastSuccessfulCanary: 22 * 60 + 40),
            HealthTitle.text(for: .verified, secondsSinceLastSuccessfulCanary: 3 * 3600),
            HealthTitle.text(for: .unknown, secondsSinceLastSuccessfulCanary: nil),
            HealthTitle.text(for: .unknown, secondsSinceLastSuccessfulCanary: 34 * 60),
            HealthTitle.text(for: .degraded([.selfTestInconclusive]), secondsSinceLastSuccessfulCanary: 60),
            HealthTitle.text(for: .blind([.lazyAccessibilityTree]), secondsSinceLastSuccessfulCanary: 60),
        ]
    }

    func testTheHarnessTakesEveryHealthLineHealthTitleGivesForOne() throws {
        let patterns = try healthPatterns()
        XCTAssertFalse(patterns.isEmpty)
        for line in healthLines {
            XCTAssertTrue(recognised(line, by: patterns), "the health line \"\(line)\" is not one verify-live.sh looks for")
        }
    }

    func testTheHarnessLooksForNoWordingTheHealthLineDoesNotHave() throws {
        let patterns = try healthPatterns()
        for pattern in patterns {
            XCTAssertTrue(healthLines.contains { recognised($0, by: [pattern]) },
                          "verify-live.sh looks for \"\(pattern.text)\", which HealthTitle never gives")
        }
    }

    func testTheHarnessDoesNotTakeAnyOtherLineOfTheMenuForTheHealthLine() throws {
        let patterns = try healthPatterns()
        let others: [String] = [
            "Captured 12 notifications",
            "Show Inspector…",
            "Rules: 2 enabled",
            "Last match: Working — verified at 09:00",
            AlertMenuText.acknowledgeTitle(listed: 2),
            HealthCause.notificationPermissionDenied.advice,
            HealthCause.notificationsSuppressed.advice,
            HealthCause.selfTestInconclusive.advice,
            HealthCause.selfTestAlertNeverSeen.advice,
            HealthCause.ownAlertsNotShown.advice,
            HealthCause.accessibilityNotTrusted.advice,
            HealthCause.observerNotAttached.advice,
            HealthCause.lazyAccessibilityTree.advice,
        ]
        for line in others {
            XCTAssertFalse(recognised(line, by: patterns), "\"\(line)\" would be taken for the health line")
        }
    }
}
