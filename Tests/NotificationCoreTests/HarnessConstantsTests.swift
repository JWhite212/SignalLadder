import CryptoKit
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
//  - that holds for every script under Scripts/ and every use of the helper in
//    them, so a call written in a shape the scan cannot read is a failure and not
//    a reference left unheld, and every definition of the helper reads the shape
//    the declarations have (the scan is held on canned text as well, so that a
//    spelling it misses shows here and not in a script);
//  - the script reads the window titles and the On Call item's title through
//    the helper, and its cause reading steps over the On Call item;
//  - the window titles are distinct and each begins with the app's name;
//  - no script types, as a lookup of its own (in quotes, against a glob or an
//    anchor, as a `case` arm, a `grep`'s argument or an operand), the text of a
//    constant it reads;
//  - the wordings the script takes for a health line, in `is_health_line` and in
//    each `case "$HEALTH"`, are the ones `HealthTitle` gives it, and no other line
//    the menu can hold;
//  - the words the harness of the plan's Task 9 reads are declared in that shape too,
//    and the lines the app builds from them begin with them or are the lines the
//    harness's guards compare. `Scripts/harness-guards.sh` reads some of them now, and
//    `verify-live.sh` reads the others when it sources that file and gains its flags;
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

    /// Every shell script under Scripts/, by its path from there, whatever folder it
    /// is in, so that a script added beside the fixtures is held as one beside the
    /// harness.
    static func scriptNames() throws -> [String] {
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: scripts, includingPropertiesForKeys: nil))
        let base = scripts.path + "/"
        return enumerator.compactMap { ($0 as? URL)?.path }
            .filter { $0.hasSuffix(".sh") && $0.hasPrefix(base) }
            .map { String($0.dropFirst(base.count)) }
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

    /// Every call of the helper with a file and a name in `code`. The name ends where a
    /// shell word does (a space, `;`, `|`, `&`, `)` or the end), so a name built with a
    /// variable (`inspector$SUFFIX`) is no call the scan reads, and is a failure in the
    /// count below and not a reference to `inspector`.
    static func references(in code: String) throws -> [(file: String, name: String)] {
        let call = try NSRegularExpression(
            pattern: #"\b\#(helper)[ \t]+([A-Za-z][A-Za-z0-9]*\.swift)[ \t]+([A-Za-z][A-Za-z0-9]*)(?=[ \t\n;|&)]|\z)"#)
        return call.matches(in: code, range: NSRange(code.startIndex..., in: code)).map { match in
            (file: String(code[Range(match.range(at: 1), in: code)!]),
             name: String(code[Range(match.range(at: 2), in: code)!]))
        }
    }

    /// Every call of the helper with a file and a name, in the scripts that make
    /// any. The helper's own definition has no file argument and is not one.
    static func references() throws -> [ConstantReference] {
        var found: [ConstantReference] = []
        for script in try scriptNames() {
            let code = codeLines(try Harness.script(script)).joined(separator: "\n")
            found += try references(in: code).map { ConstantReference(script: script, file: $0.file, name: $0.name) }
        }
        return found
    }

    /// How many times the code of a script names the helper, other than in the line
    /// that opens a definition of it as `core_constant() {` (see `helperDefinitions`).
    /// Each is a call the scan above has to read as a reference, or it is a reference
    /// nothing holds. A definition written in any other spelling (`core_constant () {`,
    /// `core_constant(){`, `function core_constant {`) is counted here, has no
    /// reference, and fails the count, since its `sed` would be held by nothing.
    static func helperUses(in code: String) throws -> Int {
        let mention = try NSRegularExpression(pattern: #"\b\#(helper)\b"#)
        let mentions = mention.numberOfMatches(in: code, range: NSRange(code.startIndex..., in: code))
        return mentions - helperDefinitions(in: code).count
    }

    /// The `sed` the helper reads a declaration with, which is the one place the
    /// shape `public static let NAME = "TEXT"` is spelt in a script. `$1` is the
    /// file and `$2` the name.
    static let helperSed = #"sed -n 's/^[[:space:]]*public static let '"$2"' = "\(.*\)"[[:space:]]*$/\1/p'"#

    /// The body of each definition of the helper in a script that opens as
    /// `core_constant() {` at the start of a line, the one spelling these tests hold:
    /// from that line to the first line that is a closing brace on its own.
    static func helperDefinitions(in text: String) -> [String] {
        let lines = text.components(separatedBy: "\n")
        var found: [String] = []
        for (index, line) in lines.enumerated() where line.hasPrefix("\(helper)() {") {
            let rest = lines[index...]
            let end = rest.firstIndex { $0 == "}" } ?? lines.endIndex - 1
            found.append(lines[index...end].joined(separator: "\n"))
        }
        return found
    }

    /// Whether a line of a script's code types `text` as a lookup of its own, as the
    /// app's word being looked for and not read from the core: in quotes (`"TEXT"`,
    /// `'TEXT'`), against a glob or an anchor (`TEXT*`, `*TEXT*`, `^TEXT`, `TEXT$`), as
    /// an arm of a `case` (`TEXT)`, `A|TEXT)`), as the argument of a `grep` (`grep -q
    /// TEXT`) or as the operand of a comparison or an assignment (`= TEXT`, `==TEXT`,
    /// `=~ TEXT`, `NAME=TEXT`). The same letters inside a longer sentence, such as a
    /// message the script prints, are not a lookup and are not found; nor is a word that
    /// differs in case, since a flag or a variable is named in lower case.
    static func typesAsLookup(_ text: String, in line: String) throws -> Bool {
        if line.contains("\"\(text)\"") || line.contains("'\(text)'") { return true }
        let word = NSRegularExpression.escapedPattern(for: text)
        let spellings = [
            #"[*^]\#(word)"#,
            #"\#(word)[*$]"#,
            #"(^|[|(])[ \t]*\#(word)[ \t]*[|)]"#,
            #"\bgrep\b([ \t]+-[A-Za-z-]+)*[ \t]+\#(word)(?![A-Za-z0-9])"#,
            #"(==?|!=|=~)[ \t]*\#(word)(?![A-Za-z0-9])"#,
        ]
        return try spellings.contains { spelling in
            try NSRegularExpression(pattern: spelling).firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
        }
    }

    /// The text of the one-line declaration of `name` in `file` of NotificationCore,
    /// as the helper would read it.
    static func declaredText(_ file: String, _ name: String) throws -> String {
        let source = try read(core.appendingPathComponent(file))
        let found = try declarations(in: source).filter { $0.name == name }
        XCTAssertEqual(found.count, 1, "\(file) must declare \(name) once, on one line, as `public static let \(name) = \"TEXT\"`")
        return try XCTUnwrap(found.first?.text, "\(file) does not declare \(name)")
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

/// What the guards' tests read: their fixtures, and the functions of a shell script.
private extension Harness {
    static let fixtures = scripts.appendingPathComponent("fixtures")

    static func fixture(_ name: String) throws -> String {
        try read(fixtures.appendingPathComponent(name))
    }

    static func fixtureData(_ name: String) throws -> Data {
        try Data(contentsOf: fixtures.appendingPathComponent(name))
    }

    /// The lines of a menu fixture, as the harness holds a menu: one item to a line.
    static func menu(_ name: String) throws -> [String] {
        try fixture("menu-\(name).txt").components(separatedBy: "\n").filter { !$0.isEmpty }
    }

    /// Every function a script defines, opened at the start of a line as `name() {`, with its text
    /// down to the first line that is a closing brace on its own.
    static func functions(in text: String) throws -> [(name: String, body: String)] {
        let lines = text.components(separatedBy: "\n")
        let open = try NSRegularExpression(pattern: #"^([A-Za-z_][A-Za-z0-9_]*)\(\) \{"#)
        var found: [(name: String, body: String)] = []
        for (index, line) in lines.enumerated() {
            guard let match = open.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let name = Range(match.range(at: 1), in: line) else { continue }
            let end = lines[index...].firstIndex { $0 == "}" } ?? lines.endIndex - 1
            found.append((name: String(line[name]), body: lines[index...end].joined(separator: "\n")))
        }
        return found
    }

    /// The lines of a script that are not blank, not a comment and not inside a function, which
    /// are the lines sourcing the script would run.
    static func linesOutsideFunctions(in text: String) throws -> [String] {
        let open = try NSRegularExpression(pattern: #"^[A-Za-z_][A-Za-z0-9_]*\(\) \{"#)
        var inside = false
        var outside: [String] = []
        for line in text.components(separatedBy: "\n") {
            if inside {
                if line == "}" { inside = false }
                continue
            }
            if line.trimmingCharacters(in: .whitespaces).isEmpty || line.hasPrefix("#") { continue }
            if open.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil {
                inside = !line.hasSuffix("}")
                continue
            }
            outside.append(line)
        }
        return outside
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
            // Typed as a lookup of its own, in quotes, against a glob or an anchor, as a
            // `case` arm, a `grep`'s argument or an AppleScript name would hold it. The
            // same letters inside a longer sentence are not a lookup.
            let typed = try code.contains { try Harness.typesAsLookup(text, in: $0) }
            XCTAssertFalse(typed,
                           "\(reference.script) has \"\(text)\" typed into it, and reads it as \(reference.name) as well: "
                               + "one of the two would be left behind by a change")
        }
    }

    /// A call the scan cannot read, such as one with the file quoted or the name held
    /// in a variable or run into one, would be a reference nothing here holds. So every
    /// use of the helper in any script under Scripts/ is one of the references the scan
    /// found, and a script that writes one another way fails here, with its name. A
    /// definition is held only when it opens a line as `core_constant() {`; one spelt
    /// any other way is a use with no reference, and fails here too.
    func testEveryUseOfTheHelperInAnyScriptIsACallTheScanReads() throws {
        let references = try Harness.references()
        for script in try Harness.scriptNames() {
            let code = Harness.codeLines(try Harness.script(script)).joined(separator: "\n")
            let uses = try Harness.helperUses(in: code)
            let held = references.filter { $0.script == script }.count
            XCTAssertEqual(uses, held,
                           "\(script) uses \(Harness.helper) \(uses) time(s), and \(held) are written as "
                               + "`\(Harness.helper) FILE.swift NAME`, the one form these tests hold; a definition "
                               + "must open a line as `\(Harness.helper)() {`")
        }
    }

    /// The shape these tests hold the declarations to is the shape the helper reads
    /// them in, so a script that defines the helper defines one that reads exactly
    /// it, and a looser or a different one is a failure here.
    func testEveryDefinitionOfTheHelperReadsTheShapeTheDeclarationsHave() throws {
        var definitions = 0
        for script in try Harness.scriptNames() {
            for body in Harness.helperDefinitions(in: try Harness.script(script)) {
                definitions += 1
                XCTAssertTrue(body.contains(Harness.helperSed),
                              "the definition of \(Harness.helper) in \(script) does not read declarations with `\(Harness.helperSed)`")
            }
        }
        XCTAssertGreaterThan(definitions, 0, "no script defines \(Harness.helper), so nothing here shows what it reads")
    }

    /// The scan is itself held, on canned text: it reads each call written the way the
    /// scripts write one, and it counts every other way of naming the helper as a use it
    /// cannot read, so that none is a reference left unheld. These are the spellings a
    /// script could drift to.
    func testTheScanReadsTheCallsItIsMeantToAndFailsEveryOtherSpellingOfAUseOrADefinition() throws {
        let read = [
            "X=$(\(Harness.helper) WindowTitles.swift inspector)",
            "\(Harness.helper) OnCall.swift menuTitle",
            "echo \"$(\(Harness.helper) OnCall.swift menuTitle)\"",
            "\(Harness.helper) OnCall.swift menuTitle | head -1",
            "\(Harness.helper) OnCall.swift menuTitle; true",
            "\(Harness.helper) OnCall.swift menuTitle && true",
            "[ -n \"$(\(Harness.helper) OnCall.swift menuTitle)\" ]",
            "\(Harness.helper) OnCall.swift menuTitle 2>/dev/null",
        ]
        for code in read {
            XCTAssertEqual(try Harness.references(in: code).count, 1, code)
            XCTAssertEqual(try Harness.helperUses(in: code), 1, code)
        }

        // Each of these names the helper and is not a call the scan reads, so there is
        // more than one use to every reference, and the count test above fails on it.
        let notRead = [
            "X=$(\(Harness.helper) WindowTitles.swift inspector$SUFFIX)",
            "X=$(\(Harness.helper) WindowTitles.swift inspector-title)",
            "X=$(\(Harness.helper) WindowTitles.swift \"inspector\")",
            "X=$(\(Harness.helper) \"WindowTitles.swift\" inspector)",
            "X=$(\(Harness.helper) $FILE inspector)",
            "X=$(\(Harness.helper) WindowTitles.swift $NAME)",
            "X=$(\(Harness.helper) WindowTitles.swift)",
            "X=`\(Harness.helper) WindowTitles.swift inspector`",
            "\(Harness.helper) () {",
            "\(Harness.helper)(){",
            " \(Harness.helper)() {",
            "function \(Harness.helper) {",
            "function \(Harness.helper)() {",
        ]
        for code in notRead {
            XCTAssertGreaterThan(try Harness.helperUses(in: code), try Harness.references(in: code).count, code)
        }

        // The definition held is the one that opens a line as `core_constant() {`. It is
        // no use of the helper, and its body is the one place the shape is spelt.
        let held = "\(Harness.helper)() {\n    \(Harness.helperSed) \\\n        \"$REPO_ROOT/$1\" | head -1\n}\nY=$(\(Harness.helper) OnCall.swift menuTitle)"
        XCTAssertEqual(try Harness.helperUses(in: held), 1)
        XCTAssertEqual(try Harness.references(in: held).count, 1)
        let bodies = Harness.helperDefinitions(in: held)
        XCTAssertEqual(bodies.count, 1)
        XCTAssertTrue(bodies.allSatisfy { $0.contains(Harness.helperSed) })
        let looser = "\(Harness.helper)() {\n    sed -n 's/.*public static let '\"$2\"' = \"\\(.*\\)\".*/\\1/p' \"$1\"\n}"
        XCTAssertEqual(Harness.helperDefinitions(in: looser).count, 1)
        XCTAssertFalse(Harness.helperDefinitions(in: looser).contains { $0.contains(Harness.helperSed) },
                       "a looser sed is not the one the declarations are held to")
    }

    /// The scan for a constant's text typed into a script is itself held, on canned
    /// lines: it finds each spelling of a lookup, quoted or bare, and it leaves a word
    /// inside a sentence the script prints, and a lower-case flag or variable, alone.
    func testTheScanForTypedWordsFindsEverySpellingOfALookupAndNotAWordInASentence() throws {
        let typed: [(text: String, line: String)] = [
            ("Acknowledge", #"grep -q "Acknowledge""#),
            ("Acknowledge", "grep -q 'Acknowledge'"),
            ("Acknowledge", #"grep -q "^Acknowledge""#),
            ("Acknowledge", "grep -q ^Acknowledge"),
            ("Acknowledge", "    Acknowledge*) found=1 ;;"),
            ("Acknowledge", "    *Acknowledge*) found=1 ;;"),
            ("Acknowledge", "    Acknowledge) found=1 ;;"),
            ("Acknowledge", "    Dismiss|Acknowledge) found=1 ;;"),
            ("Acknowledge", "    (Acknowledge) found=1 ;;"),
            ("Acknowledge", "grep -q Acknowledge"),
            ("Acknowledge", "grep -qF -- Acknowledge"),
            ("Acknowledge", #"[ "$ITEM" = Acknowledge ]"#),
            ("Acknowledge", "[[ $ITEM == Acknowledge ]]"),
            ("Acknowledge", "[[ $ITEM =~ Acknowledge ]]"),
            ("Acknowledge", "ITEM=Acknowledge"),
            ("escalating", "    *escalating*) refuse ;;"),
            ("escalating", #"printf '%s' "$MENU" | grep -c escalating"#),
            ("On call since", #"grep -q "On call since""#),
            ("1 alert escalating", #"    "1 alert escalating"*) ;;"#),
            ("Settings\u{2026}", #"click menu item "Settings…" of menu 1 of itm"#),
        ]
        for (text, line) in typed {
            XCTAssertTrue(try Harness.typesAsLookup(text, in: line), "\"\(text)\" typed in `\(line)` is not found")
        }
        let notTyped: [(text: String, line: String)] = [
            ("Acknowledge", #"note "there is no Acknowledge item on the menu""#),
            ("escalating", #"bad "an alert is escalating, so the run stops""#),
            ("Acknowledge", "ACK=$(core_constant AlertMenuText.swift acknowledgeOneTitle)"),
            ("Acknowledge", #"grep -q "$ACK_STEM""#),
            ("Acknowledge", #"case "$line" in "$ACK_STEM"*) ;; esac"#),
            ("escalating", "MODE=escalation"),
            ("escalating", "escalating_count=3"),
            ("Snooze", "    --snooze) MODE=snooze ;;"),
            ("Dismiss", #"printf '%s\n' "$DISMISS""#),
        ]
        for (text, line) in notTyped {
            XCTAssertFalse(try Harness.typesAsLookup(text, in: line), "\"\(text)\" is taken for a lookup in `\(line)`")
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

    // MARK: - The Settings window's words

    /// What the harness will look for of the Settings window: the title of the
    /// window and of the menu's item that opens it. Nothing in `verify-live.sh`
    /// reads them yet; when it does, it reads them through the helper, so each is
    /// held now to the one shape the helper's `sed` reads, and no script types the
    /// words of its own in the meantime, which a change to either would leave
    /// behind.
    private let settingsConstants: [(file: String, name: String, text: String)] = [
        ("WindowTitles.swift", "settings", "SignalLadder Settings"),
        ("SettingsText.swift", "menuTitle", "Settings\u{2026}"),
    ]

    func testTheSettingsTitleAndMenuTitleAreDeclaredOnOneLineInTheShapeTheHelperReads() throws {
        for constant in settingsConstants {
            let source = try Harness.read(Harness.core.appendingPathComponent(constant.file))
            let strict = try Harness.declarations(in: source).filter { $0.name == constant.name }
            XCTAssertEqual(strict.count, 1,
                           "\(constant.file) must declare \(constant.name) once, on one line, as "
                               + "`public static let \(constant.name) = \"TEXT\"`")
            XCTAssertEqual(strict.first?.text, constant.text, "\(constant.name) in \(constant.file)")
            XCTAssertEqual(Harness.declarationLines(of: constant.name, in: source).count, strict.count,
                           "\(constant.file) declares \(constant.name) in a shape the helper does not read as well")
        }
    }

    func testNoScriptTypesTheWordsOfTheSettingsTitleOrItsMenuItem() throws {
        for script in try Harness.scriptNames() {
            let code = Harness.codeLines(try Harness.script(script))
            for constant in settingsConstants {
                let typed = try code.contains { try Harness.typesAsLookup(constant.text, in: $0) }
                XCTAssertFalse(typed, "\(script) has \"\(constant.text)\" typed into it: read \(constant.name) through the helper")
            }
        }
    }

    // MARK: - The setup guide's title

    /// What the harness will look for of the setup guide's window: its title. Nothing in
    /// `verify-live.sh` reads it yet (the check for the guide is the plan's Task 9); when it
    /// does, it reads it through the helper, so it is held now to the one shape the helper's
    /// `sed` reads, and no script types the words of its own in the meantime, which a change
    /// to either would leave behind.
    private let setupGuideConstants: [(file: String, name: String, text: String)] = [
        ("WindowTitles.swift", "setupGuide", "SignalLadder Setup Guide"),
    ]

    func testTheSetupGuidesTitleIsDeclaredOnOneLineInTheShapeTheHelperReads() throws {
        for constant in setupGuideConstants {
            let source = try Harness.read(Harness.core.appendingPathComponent(constant.file))
            let strict = try Harness.declarations(in: source).filter { $0.name == constant.name }
            XCTAssertEqual(strict.count, 1,
                           "\(constant.file) must declare \(constant.name) once, on one line, as "
                               + "`public static let \(constant.name) = \"TEXT\"`")
            XCTAssertEqual(strict.first?.text, constant.text, "\(constant.name) in \(constant.file)")
            XCTAssertEqual(Harness.declarationLines(of: constant.name, in: source).count, strict.count,
                           "\(constant.file) declares \(constant.name) in a shape the helper does not read as well")
        }
    }

    func testNoScriptTypesTheWordsOfTheSetupGuidesTitle() throws {
        for script in try Harness.scriptNames() {
            let code = Harness.codeLines(try Harness.script(script))
            for constant in setupGuideConstants {
                let typed = try code.contains { try Harness.typesAsLookup(constant.text, in: $0) }
                XCTAssertFalse(typed, "\(script) has \"\(constant.text)\" typed into it: read \(constant.name) through the helper")
            }
        }
    }

    // MARK: - The snooze menu's words

    /// What the harness looks for in the menu's snooze items: the stem of the
    /// held-summary line for one match, the words that end every stem, the Snooze
    /// item's title, End Snooze, Dismiss and the stem of the active line.
    /// `Scripts/harness-guards.sh` reads three of them (the stem for one match, the
    /// Snooze item's title and the stem of the active line); `verify-live.sh` reads
    /// the others when it gains its flags. A script that reads one reads it through
    /// the helper, so each is held to the one shape the helper's `sed` reads, and no
    /// script types the words of its own, which a change to either would leave behind.
    private let snoozeConstants: [(file: String, name: String, text: String)] = [
        ("SnoozeText.swift", "heldOneMatchStem", "1 match held while snoozed"),
        ("SnoozeText.swift", "heldStem", "held while snoozed"),
        // The menu's own titles and the stem of its active line, which the harness
        // looks for among the top-level items.
        ("SnoozeText.swift", "menuTitle", "Snooze"),
        ("SnoozeText.swift", "endTitle", "End Snooze"),
        ("SnoozeText.swift", "dismissTitle", "Dismiss"),
        ("SnoozeText.swift", "activeStem", "Snoozed until"),
    ]

    func testTheSnoozeMenusTitlesAndStemsAreDeclaredOnOneLineInTheShapeTheHelperReads() throws {
        for constant in snoozeConstants {
            let source = try Harness.read(Harness.core.appendingPathComponent(constant.file))
            let strict = try Harness.declarations(in: source).filter { $0.name == constant.name }
            XCTAssertEqual(strict.count, 1,
                           "\(constant.file) must declare \(constant.name) once, on one line, as "
                               + "`public static let \(constant.name) = \"TEXT\"`")
            XCTAssertEqual(strict.first?.text, constant.text, "\(constant.name) in \(constant.file)")
            XCTAssertEqual(Harness.declarationLines(of: constant.name, in: source).count, strict.count,
                           "\(constant.file) declares \(constant.name) in a shape the helper does not read as well")
        }
    }

    func testNoScriptTypesTheWordsOfTheSnoozeMenusTitlesAndStems() throws {
        for script in try Harness.scriptNames() {
            let code = Harness.codeLines(try Harness.script(script))
            for constant in snoozeConstants {
                let typed = try code.contains { try Harness.typesAsLookup(constant.text, in: $0) }
                XCTAssertFalse(typed, "\(script) has \"\(constant.text)\" typed into it: read \(constant.name) through the helper")
            }
        }
    }

    // MARK: - The escalation menu's words

    /// What the harness will look for in the menu's line about escalations: the
    /// stem of the line for one escalation, which a count of matches follows when
    /// more than one joined it ("1 alert escalating (7 matches)"), so the harness
    /// looks for the line by this stem and not by the whole of it. The marker-only
    /// guard of `Scripts/harness-guards.sh` reads it through the helper, and
    /// `verify-live.sh` will when it gains its flags, so it is held to the one shape
    /// the helper's `sed` reads, and no script types the words of its own, which a
    /// change to either would leave behind.
    private let escalationConstants: [(file: String, name: String, text: String)] = [
        ("AlertMenuText.swift", "singleEscalatingStem", "1 alert escalating"),
    ]

    func testTheEscalationMenusStemIsDeclaredOnOneLineInTheShapeTheHelperReads() throws {
        for constant in escalationConstants {
            let source = try Harness.read(Harness.core.appendingPathComponent(constant.file))
            let strict = try Harness.declarations(in: source).filter { $0.name == constant.name }
            XCTAssertEqual(strict.count, 1,
                           "\(constant.file) must declare \(constant.name) once, on one line, as "
                               + "`public static let \(constant.name) = \"TEXT\"`")
            XCTAssertEqual(strict.first?.text, constant.text, "\(constant.name) in \(constant.file)")
            XCTAssertEqual(Harness.declarationLines(of: constant.name, in: source).count, strict.count,
                           "\(constant.file) declares \(constant.name) in a shape the helper does not read as well")
        }
    }

    func testNoScriptTypesTheWordsOfTheEscalationMenusStem() throws {
        for script in try Harness.scriptNames() {
            let code = Harness.codeLines(try Harness.script(script))
            for constant in escalationConstants {
                let typed = try code.contains { try Harness.typesAsLookup(constant.text, in: $0) }
                XCTAssertFalse(typed, "\(script) has \"\(constant.text)\" typed into it: read \(constant.name) through the helper")
            }
        }
    }

    /// The line the harness looks for is the one the menu builds, and the line for a
    /// burst is that stem with a count after it, so a stem found in front is the
    /// line. Held here beside the shape, since the shape can be right and the line
    /// built from something else.
    func testTheMenusLineForOneEscalationBeginsWithTheStemTheHarnessReads() throws {
        let source = try Harness.read(Harness.core.appendingPathComponent("AlertMenuText.swift"))
        let declared = try XCTUnwrap(try Harness.declarations(in: source).first { $0.name == "singleEscalatingStem" })
        let one = EscalationSummary(ruleName: "On-call mentions", startedAt: Date(timeIntervalSince1970: 1_790_000_000))
        let burst = EscalationSummary(ruleName: "On-call mentions", startedAt: Date(timeIntervalSince1970: 1_790_000_000),
                                      matchCount: 7)
        for summary in [one, burst] {
            let lines = AlertMenuText.escalationLines(listed: [summary], shortcutFailure: nil, time: { _ in "10:42" })
            XCTAssertEqual(lines.count, 1)
            XCTAssertTrue(lines[0].hasPrefix(declared.text), "\(lines[0]) does not begin with \"\(declared.text)\"")
        }
    }

    // MARK: - The words the harness of Task 9 reads

    /// What the harness of the plan's Task 9 looks for or writes that the core
    /// declares: the marker rule's name and the title of its banners, the setup
    /// nudge's stem, the on-call line's stem and the key on-call mode saves, the key
    /// a snooze's end is saved under, the Snooze submenu's 15-minute item, the titles
    /// the menu's Acknowledge item has, the word that ends every line about what is
    /// escalating, and the on-call check window's title. `Scripts/harness-guards.sh`
    /// reads four of them (the marker rule's name, the on-call line's stem, the title of
    /// the Acknowledge item and the word that ends every line about what is escalating);
    /// `verify-live.sh` reads the others when it gains its flags. Each script that reads
    /// one reads it through the helper, so each is held to the one shape the helper's
    /// `sed` reads, and no script types the words of its own, which a change to either
    /// would leave behind. A script that reads one is held to it again by the tests
    /// above, whether or not it is listed here.
    private let harnessConstants: [(file: String, name: String, text: String)] = [
        ("HarnessText.swift", "markerRuleName", "SignalLadder harness marker"),
        ("HarnessText.swift", "markerTitle", "SignalLadder harness marker banner"),
        ("SetupText.swift", "nudgeStem", "Setup is not finished"),
        ("OnCall.swift", "sinceStem", "On call since"),
        ("OnCall.swift", "storageKey", "onCallSince"),
        ("Snooze.swift", "untilKey", "snoozeUntil"),
        ("SnoozeText.swift", "fifteenMinutesTitle", "For 15 minutes"),
        ("AlertMenuText.swift", "acknowledgeOneTitle", "Acknowledge"),
        ("AlertMenuText.swift", "acknowledgeAllStem", "Acknowledge All"),
        ("AlertMenuText.swift", "escalatingWord", "escalating"),
        ("WindowTitles.swift", "onCallCheck", "SignalLadder On-Call Check"),
    ]

    func testTheWordsTheHarnessReadsAreDeclaredOnOneLineInTheShapeTheHelperReads() throws {
        for constant in harnessConstants {
            let source = try Harness.read(Harness.core.appendingPathComponent(constant.file))
            let strict = try Harness.declarations(in: source).filter { $0.name == constant.name }
            XCTAssertEqual(strict.count, 1,
                           "\(constant.file) must declare \(constant.name) once, on one line, as "
                               + "`public static let \(constant.name) = \"TEXT\"`")
            XCTAssertEqual(strict.first?.text, constant.text, "\(constant.name) in \(constant.file)")
            XCTAssertEqual(Harness.declarationLines(of: constant.name, in: source).count, strict.count,
                           "\(constant.file) declares \(constant.name) in a shape the helper does not read as well")
        }
    }

    func testNoScriptTypesTheWordsTheHarnessReads() throws {
        for script in try Harness.scriptNames() {
            let code = Harness.codeLines(try Harness.script(script))
            for constant in harnessConstants {
                let typed = try code.contains { try Harness.typesAsLookup(constant.text, in: $0) }
                XCTAssertFalse(typed, "\(script) has \"\(constant.text)\" typed into it: read \(constant.name) through the helper")
            }
        }
    }

    /// The marker rule's name and the title of its banners are the harness's own
    /// words, and the script puts them into JSON, into AppleScript and into a shell's
    /// arguments, so each is plain words and cannot carry a quote or a character a
    /// shell or a `sed` would read as its own. Each says it is the harness's, so
    /// neither can be taken for a rule or a banner of the owner's, and the two differ,
    /// so that a rule is not taken for a banner.
    func testTheMarkersNameAndTitleAreDistinctPlainWordsThatSayWhoseTheyAre() throws {
        let name = try Harness.declaredText("HarnessText.swift", "markerRuleName")
        let title = try Harness.declaredText("HarnessText.swift", "markerTitle")
        XCTAssertEqual(name, HarnessText.markerRuleName)
        XCTAssertEqual(title, HarnessText.markerTitle)
        XCTAssertNotEqual(name, title)
        for text in [name, title] {
            XCTAssertTrue(text.hasPrefix("SignalLadder harness"), "\"\(text)\" does not say it is the harness's")
            XCTAssertTrue(text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == " ") },
                          "\"\(text)\" holds a character a shell, a sed, JSON or AppleScript would read as its own")
        }
    }

    /// The setup nudge is found by its stem (the plan's Task 8 note on the nudge). The
    /// line the menu builds begins with the stem the harness reads, whichever steps are
    /// outstanding, and there is none to find when none is. That the script's cause
    /// reading steps over the line by that stem is for the commit that changes
    /// `health_and_cause`, which holds it there; this holds the stem, and
    /// `testTheHarnessDoesNotTakeAnyOtherLineOfTheMenuForTheHealthLine` holds that the
    /// nudge is not taken for a health line.
    func testTheNudgeLineBeginsWithTheStemTheHarnessReads() throws {
        let stem = try Harness.declaredText("SetupText.swift", "nudgeStem")
        let outstanding: [[SetupStep]] = [
            [.accessibility], [.notifications], [.firstRule], [.accessibility, .notifications, .firstRule],
        ]
        for steps in outstanding {
            let line = try XCTUnwrap(SetupText.nudgeLine(outstanding: steps), "\(steps) gave no nudge")
            XCTAssertTrue(line.hasPrefix(stem), "\"\(line)\" does not begin with \"\(stem)\"")
        }
        XCTAssertNil(SetupText.nudgeLine(outstanding: []), "a menu with nothing outstanding carries a line that begins with the stem")
    }

    /// The since-line is found by its stem, and it is the stem whatever the line
    /// goes on to say of the moment and of the self-tests.
    func testTheOnCallSinceLineBeginsWithTheStemTheHarnessReadsInEveryState() throws {
        let stem = try Harness.declaredText("OnCall.swift", "sinceStem")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let known: [Date?] = [Date(timeIntervalSince1970: 1_790_000_000), nil]
        let selfTests: [Bool?] = [nil, true, false]
        for since in known {
            for allows in selfTests {
                let line = AlertMenuText.onCallSinceLine(since: since, allowsSelfTest: allows, calendar: calendar,
                                                         time: { _ in "10:42" })
                XCTAssertTrue(line.hasPrefix(stem), "\"\(line)\" does not begin with \"\(stem)\"")
            }
        }
    }

    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func snoozeMenu(running: Bool, summary: HeldSummary = HeldSummary(), rules: [Rule] = []) -> SnoozeMenu {
        SnoozeText.menu(rules: rules, onCall: .off, snoozeEndsAt: running ? now.addingTimeInterval(900) : nil,
                        summary: summary, endedByOnCallAt: nil, now: now, time: { _ in "10:42" })
    }

    /// The running snooze's line is found by its stem, and is a top-level line of the
    /// menu, which is where the harness looks.
    func testTheSnoozeLineBeginsWithTheStemTheHarnessReadsAndIsATopLevelLine() throws {
        let stem = try Harness.declaredText("SnoozeText.swift", "activeStem")
        let line = SnoozeText.activeLine(endsAt: now.addingTimeInterval(900), quieting: 1, of: 2, time: { _ in "10:42" })
        XCTAssertTrue(line.hasPrefix(stem), "\"\(line)\" does not begin with \"\(stem)\"")
        let top: [String] = snoozeMenu(running: true).items.compactMap { item in
            if case .line(let text) = item { return text }
            return nil
        }
        XCTAssertTrue(top.contains { $0.hasPrefix(stem) }, "the menu of a running snooze has no top-level line that begins with the stem")
        let idle: [String] = snoozeMenu(running: false).items.compactMap { item in
            if case .line(let text) = item { return text }
            return nil
        }
        XCTAssertFalse(idle.contains { $0.hasPrefix(stem) }, "a menu with no snooze running carries the stem")
    }

    /// The harness chooses a 15-minute snooze by its title and ends it by End
    /// Snooze, both in the Snooze item's submenu, which the Snooze item opens.
    func testTheSnoozeSubmenuHasTheFifteenMinuteItemAndEndSnoozeUnderTheTitlesTheHarnessReads() throws {
        let fifteen = try Harness.declaredText("SnoozeText.swift", "fifteenMinutesTitle")
        let end = try Harness.declaredText("SnoozeText.swift", "endTitle")
        let title = try Harness.declaredText("SnoozeText.swift", "menuTitle")
        XCTAssertEqual(SnoozeText.durationTitle(.fifteenMinutes), fifteen)
        for running in [false, true] {
            guard case .snooze(let itemTitle, let submenu)? = snoozeMenu(running: running).items.first else {
                return XCTFail("the first item of the snooze's menu is not the Snooze item")
            }
            XCTAssertEqual(itemTitle, title)
            XCTAssertTrue(submenu.contains(.start(.fifteenMinutes, title: fifteen)),
                          "the submenu has no item \"\(fifteen)\" that starts the 15-minute snooze")
            XCTAssertEqual(submenu.contains(.end(title: end)), running,
                           running ? "the submenu of a running snooze has no \"\(end)\"" : "the submenu of no snooze has \"\(end)\"")
        }
    }

    /// The summary guard dismisses a held summary only when its line is the stem of
    /// one match, then ": ", the marker rule's name and " ×1". That whole line is
    /// what the app makes of one match of the marker's, and nothing else the app can
    /// say of what a snooze held is it, so a real match of the owner's is never
    /// dismissed with the marker's. The Dismiss item stands directly after the line.
    func testTheHeldSummaryOfTheMarkersOneMatchIsTheLineTheSummaryGuardCompares() throws {
        let stem = try Harness.declaredText("SnoozeText.swift", "heldOneMatchStem")
        let name = try Harness.declaredText("HarnessText.swift", "markerRuleName")
        let dismiss = try Harness.declaredText("SnoozeText.swift", "dismissTitle")
        let expected = "\(stem): \(name) \u{D7}1"
        let marker = UUID(), other = UUID()
        func line(_ summary: HeldSummary) -> String? {
            SnoozeText.summaryLine(summary, names: [marker: name, other: "On-call mentions"])
        }

        let alone = HeldSummary(counts: [marker: 1])
        XCTAssertEqual(line(alone), expected)

        // Each of these is something else that was held, and is not that line.
        let elsewhere: [(String, HeldSummary)] = [
            ("two matches of the marker's", HeldSummary(counts: [marker: 2])),
            ("the marker's and another rule's", HeldSummary(counts: [marker: 1, other: 1])),
            ("another rule's, alone", HeldSummary(counts: [other: 1])),
            ("a rule that cannot be found, alone", HeldSummary(counts: [UUID(): 1])),
            ("the marker's, with a record that could not be read", HeldSummary(counts: [marker: 1], recordUnreadable: true)),
            ("a record that could not be read, alone", HeldSummary(counts: [:], recordUnreadable: true)),
        ]
        for (what, summary) in elsewhere {
            XCTAssertNotEqual(line(summary), expected, what)
        }
        // More than one match does not even begin with the stem of one.
        for summary in [HeldSummary(counts: [marker: 2]), HeldSummary(counts: [marker: 1, other: 1])] {
            let many = try XCTUnwrap(line(summary))
            XCTAssertFalse(many.hasPrefix(stem), many)
        }

        // The rule the harness installs for `--snooze`, as the menu names it: a rule
        // that a snooze may hold, with the marker's name, matching the marker's title.
        let installed = Rule(id: marker, name: name, condition: .field(.title, .equals, HarnessText.markerTitle),
                             alert: .sound(name: "Glass", gainDB: 0), quietWhenSnoozed: true)
        let items = snoozeMenu(running: false, summary: alone, rules: [installed]).items
        let at = try XCTUnwrap(items.firstIndex(of: .line(expected)), "the menu does not carry the marker's summary line")
        guard items.indices.contains(at + 1), case .dismiss(let title, _) = items[at + 1] else {
            return XCTFail("the Dismiss item does not stand directly after the summary line")
        }
        XCTAssertEqual(title, dismiss)
    }

    /// The marker-only guard reads the escalating line as the stem and then the end
    /// of the line or " (N matches)". The line for the marker's one escalation is
    /// that, with a count once matches joined it; the line for more than one is
    /// another and does not begin with the stem. The refuse guard looks for the word
    /// the stem ends in: every line about what is escalating has it, and the line
    /// about what was missed while asleep does not.
    func testTheEscalatingLineIsTheStemThenTheEndOrACountOfMatches() throws {
        let stem = try Harness.declaredText("AlertMenuText.swift", "singleEscalatingStem")
        let word = try Harness.declaredText("AlertMenuText.swift", "escalatingWord")
        XCTAssertTrue(stem.hasSuffix(word), "the stem \"\(stem)\" does not end in \"\(word)\"")
        func lines(_ summaries: [EscalationSummary]) -> [String] {
            AlertMenuText.escalationLines(listed: summaries, shortcutFailure: nil, time: { _ in "10:42" })
        }
        func escalation(matches: Int) -> EscalationSummary {
            EscalationSummary(ruleName: "On-call mentions", startedAt: now, matchCount: matches)
        }

        XCTAssertEqual(lines([escalation(matches: 1)]), [stem])
        for count in [2, 5, 7, 12] {
            XCTAssertEqual(lines([escalation(matches: count)]), ["\(stem) (\(count) matches)"])
        }
        XCTAssertEqual(lines([escalation(matches: 1), escalation(matches: 1)]), ["2 alerts \(word)"])
        let two = lines([escalation(matches: 3), escalation(matches: 3)])
        XCTAssertEqual(two, ["2 alerts \(word) (6 matches)"])
        XCTAssertFalse(two[0].hasPrefix(stem), "the line for two escalations begins with the stem of one")

        // What was missed while asleep is another line, and says nothing of escalating.
        let missed = EscalationSummary(ruleName: "On-call mentions", startedAt: now,
                                       status: .missedWhileAsleep(convertedAt: now, acknowledgedAt: nil))
        XCTAssertEqual(lines([missed]), ["1 alert missed while asleep"])
        XCTAssertFalse(lines([missed]).joined().contains(word))
    }

    /// The harness takes any menu line that begins with the stem for an Acknowledge
    /// item, to know that one is there, and clicks only the item whose title is exactly
    /// the stem, which is on the menu when one alert is listed. Every title the app gives
    /// the item begins with the stem, and no other line of the menu does: the lines the
    /// core makes that are listed here do not, and no other string in the app's sources
    /// begins with it, apart from the three that are not lines of the menu (below).
    func testEveryAcknowledgeTitleBeginsWithTheStemTheHarnessReadsAndNoOtherLineOfTheMenuDoes() throws {
        let one = try Harness.declaredText("AlertMenuText.swift", "acknowledgeOneTitle")
        let all = try Harness.declaredText("AlertMenuText.swift", "acknowledgeAllStem")
        XCTAssertEqual(AlertMenuText.acknowledgeTitle(listed: 1), one)
        XCTAssertTrue(all.hasPrefix(one))
        for listed in [2, 3, 12] {
            let title = AlertMenuText.acknowledgeTitle(listed: listed)
            XCTAssertEqual(title, "\(all) (\(listed))")
            XCTAssertTrue(title.hasPrefix(one))
        }

        let failure = CapturePipeline.ShortcutFailure(ruleName: "On-call mentions", shortcutName: "Page me", at: now,
                                                      reason: "the Shortcut \"Page me\" is not installed")
        let missed = EscalationSummary(ruleName: "On-call mentions", startedAt: now,
                                       status: .missedWhileAsleep(convertedAt: now, acknowledgedAt: nil))
        let burst = EscalationSummary(ruleName: "On-call mentions", startedAt: now, matchCount: 5)
        var others = AlertMenuText.escalationLines(listed: [burst, burst, missed], shortcutFailure: failure,
                                                   time: { _ in "10:42" })
        others += healthLines
        others += [SetupText.nudgeLine(outstanding: [.accessibility]) ?? "",
                   SnoozeText.activeLine(endsAt: now, quieting: 1, of: 1, time: { _ in "10:42" })]
        for line in others {
            XCTAssertFalse(line.hasPrefix(one), "\"\(line)\" would be taken for the Acknowledge item")
        }

        // An escalation listed beside an alert missed while asleep: the menu lists both
        // (the app counts both in `listed`), and its item is "Acknowledge All (2)", which
        // is not the title the harness clicks. A click on it would acknowledge the miss
        // unseen, and it is not found by looking for the exact title.
        let escalating = EscalationSummary(ruleName: "On-call mentions", startedAt: now)
        let beside = AlertMenuText.escalationLines(listed: [escalating, missed], shortcutFailure: nil, time: { _ in "10:42" })
        XCTAssertEqual(beside, [try Harness.declaredText("AlertMenuText.swift", "singleEscalatingStem"), "1 alert missed while asleep"])
        let besideTitle = AlertMenuText.acknowledgeTitle(listed: [escalating, missed].count)
        XCTAssertEqual(besideTitle, "\(all) (2)")
        XCTAssertNotEqual(besideTitle, one, "the item beside a missed alert has the exact title of the item for one")
    }

    /// The harness takes a line that begins with the stem for the Acknowledge item, so a
    /// string that began with it and was shown on the menu would be taken for the item.
    /// Nothing in the app's sources does but these: the two constants above, the escalation
    /// panel's button (the panel, not the menu) and the Inspector's "Acknowledged at" row.
    /// A new string that begins with it is either not a line of the menu, and is added
    /// here with why, or is one, and is worded another way.
    func testNoStringInTheAppsSourcesBeginsWithTheAcknowledgeStemExceptTheThreeThatAreNotLinesOfTheMenu() throws {
        let one = try Harness.declaredText("AlertMenuText.swift", "acknowledgeOneTitle")
        let sources = Harness.root.appendingPathComponent("Sources")
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        let base = sources.path + "/"
        var found: [String: Int] = [:]
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let count = Harness.swiftCodeLines(try Harness.read(url)).reduce(0) { total, line in
                total + line.components(separatedBy: "\"\(one)").count - 1
            }
            if count > 0 { found[String(url.path.dropFirst(base.count))] = count }
        }
        let expected = [
            "NotificationCore/AlertMenuText.swift": 2,       // acknowledgeOneTitle and acknowledgeAllStem
            "NotificationCore/EscalationPanelText.swift": 1, // the button on the panel
            "NotificationCore/InspectorEntry.swift": 1,      // "Acknowledged at", a row of the Inspector
        ]
        XCTAssertEqual(found, expected, "a string beginning with \"\(one)\" is new, or has gone, in the sources")
    }

    // MARK: - The rules file's version

    /// The harness refuses to append to a file that declares a version above the
    /// one the codec reads. The number is not a quoted text, so the helper's shape
    /// does not read it; a script that reads it from the source reads this one line,
    /// and this holds the line to the one shape such a read can take, and to the
    /// value the codec has.
    func testTheRulesFilesCurrentVersionIsDeclaredOnOneLineAsANumber() throws {
        let source = try Harness.read(Harness.core.appendingPathComponent("RuleSetCodec.swift"))
        let shape = try NSRegularExpression(pattern: #"^[ \t]*public static let currentVersion = ([0-9]+)[ \t]*$"#,
                                            options: .anchorsMatchLines)
        let found = shape.matches(in: source, range: NSRange(source.startIndex..., in: source))
        XCTAssertEqual(found.count, 1, "RuleSetCodec.swift must declare currentVersion once, on one line, as `public static let currentVersion = N`")
        XCTAssertEqual(Harness.declarationLines(of: "currentVersion", in: source).count, found.count,
                       "RuleSetCodec.swift declares currentVersion in a shape a script does not read as well")
        let number = found.first.flatMap { Range($0.range(at: 1), in: source) }.flatMap { Int(source[$0]) }
        XCTAssertEqual(number, RuleSetCodec.currentVersion)
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
            // The menu's setup line comes directly after the health line and its
            // cause, and is neither (the plan's Task 8 note on the nudge).
            SetupText.nudgeLine(outstanding: [.accessibility]) ?? "",
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

    // MARK: - The health line's wordings, declared

    /// The wordings of the health line, each declared on one line in the shape the
    /// helper reads. The script types them still, as the arms of `is_health_line` and
    /// of each `case "$HEALTH"`, so nothing here says no script types them; the tests
    /// above hold what `is_health_line` types to what `HealthTitle` gives, and the last
    /// two below hold what it types there, and in the cases, to these.
    private let healthConstants: [(name: String, text: String)] = [
        ("verifiedStem", "Working \u{2014} verified"),
        ("checkingLine", "Checking\u{2026}"),
        ("unverifiedStem", "Unverified"),
        ("cannotVerifyLine", "Cannot verify itself"),
        ("notCapturingLine", "NOT capturing notifications"),
    ]

    func testTheHealthLinesWordingsAreDeclaredOnOneLineInTheShapeTheHelperReads() throws {
        let source = try Harness.read(Harness.core.appendingPathComponent("HealthTitle.swift"))
        for constant in healthConstants {
            let strict = try Harness.declarations(in: source).filter { $0.name == constant.name }
            XCTAssertEqual(strict.count, 1,
                           "HealthTitle.swift must declare \(constant.name) once, on one line, as "
                               + "`public static let \(constant.name) = \"TEXT\"`")
            XCTAssertEqual(strict.first?.text, constant.text, "\(constant.name) in HealthTitle.swift")
            XCTAssertEqual(Harness.declarationLines(of: constant.name, in: source).count, strict.count,
                           "HealthTitle.swift declares \(constant.name) in a shape the helper does not read as well")
        }
    }

    /// `HealthTitle.text` makes every line from the declared wordings: the two stems
    /// are followed by what makes the line (an age), the other three are the lines.
    /// No wording begins with another, so a `case` arm for one cannot take the line
    /// of another.
    func testHealthTitleMakesEachLineFromTheWordingsTheHarnessWillRead() throws {
        func declared(_ name: String) throws -> String { try Harness.declaredText("HealthTitle.swift", name) }
        let verified = try declared("verifiedStem"), checking = try declared("checkingLine")
        let unverified = try declared("unverifiedStem"), cannotVerify = try declared("cannotVerifyLine")
        let notCapturing = try declared("notCapturingLine")

        XCTAssertEqual(HealthTitle.text(for: .verified, secondsSinceLastSuccessfulCanary: nil), verified)
        for age: TimeInterval in [5, 22 * 60 + 40, 3 * 3600] {
            let line = HealthTitle.text(for: .verified, secondsSinceLastSuccessfulCanary: age)
            XCTAssertTrue(line.hasPrefix(verified + " "), line)
        }
        XCTAssertEqual(HealthTitle.text(for: .unknown, secondsSinceLastSuccessfulCanary: nil), checking)
        for age: TimeInterval in [0, 34 * 60, 3 * 3600] {
            let line = HealthTitle.text(for: .unknown, secondsSinceLastSuccessfulCanary: age)
            XCTAssertTrue(line.hasPrefix(unverified + " "), line)
        }
        XCTAssertEqual(HealthTitle.text(for: .degraded([.selfTestInconclusive]), secondsSinceLastSuccessfulCanary: 60), cannotVerify)
        XCTAssertEqual(HealthTitle.text(for: .blind([.lazyAccessibilityTree]), secondsSinceLastSuccessfulCanary: 60), notCapturing)

        let all = [verified, checking, unverified, cannotVerify, notCapturing]
        for a in all {
            for b in all where a != b {
                XCTAssertFalse(a.hasPrefix(b), "\"\(a)\" begins with \"\(b)\", so one would take the other's line")
            }
        }
    }

    func testTheWordingsTheScriptTypesForTheHealthLineAreTheOnesHealthTitleDeclares() throws {
        let typed = Set(try healthPatterns().map(\.text))
        let declared = Set(healthConstants.map(\.text))
        XCTAssertEqual(typed, declared, "is_health_line types \(typed.sorted()), and HealthTitle declares \(declared.sorted())")
    }

    /// The quoted patterns on the arms of each `case "$HEALTH" in` in the script, a
    /// block to an array: the one that gives the verdict, and the one that decides
    /// whether a live capture can contradict the health line. An arm's pattern is what
    /// stands before the first `)` that no quote encloses; the empty pattern and `*` name
    /// no wording.
    private func healthCaseBlocks() throws -> [[(text: String, isPrefix: Bool)]] {
        let lines = try Harness.script("verify-live.sh").components(separatedBy: "\n")
        let quoted = try NSRegularExpression(pattern: #""([^"]*)"(\*)?"#)
        func pattern(of arm: String) -> String? {
            var inQuote = false
            for index in arm.indices {
                if arm[index] == "\"" { inQuote.toggle() }
                if arm[index] == ")" && !inQuote { return String(arm[..<index]) }
            }
            return nil
        }
        var blocks: [[(text: String, isPrefix: Bool)]] = []
        for (start, line) in lines.enumerated() where line.hasPrefix("case \"$HEALTH\" in") {
            let end = try XCTUnwrap(lines[start...].firstIndex { $0 == "esac" }, "a case on $HEALTH is not closed")
            var block: [(text: String, isPrefix: Bool)] = []
            for arm in lines[(start + 1)..<end] {
                guard let part = pattern(of: arm) else { continue }
                for match in quoted.matches(in: part, range: NSRange(part.startIndex..., in: part)) {
                    let text = String(part[Range(match.range(at: 1), in: part)!])
                    if !text.isEmpty { block.append((text: text, isPrefix: match.range(at: 2).location != NSNotFound)) }
                }
            }
            blocks.append(block)
        }
        return blocks
    }

    /// The script types the wordings again in its `case "$HEALTH"` blocks, so those are
    /// held as `is_health_line`'s arms are: every wording is one `HealthTitle` declares,
    /// the two stems are patterns that end in `*` (the age follows them) and the other
    /// three are exact, and the block that gives the verdict names all five, so that a
    /// line the app can give is never "unrecognised". A block that decides something else
    /// need not name them all.
    func testTheWordingsTheScriptTypesInItsCasesOnTheHealthLineAreTheOnesHealthTitleDeclares() throws {
        let declared = Set(healthConstants.map(\.text))
        let stems = Set(healthConstants.filter { $0.name.hasSuffix("Stem") }.map(\.text))
        XCTAssertEqual(stems.count, 2, "two of the wordings are stems, which an age follows")
        let blocks = try healthCaseBlocks()
        XCTAssertFalse(blocks.isEmpty, "verify-live.sh has no case on $HEALTH, so nothing here is held")
        for block in blocks {
            for pattern in block {
                XCTAssertTrue(declared.contains(pattern.text),
                              "a case on $HEALTH types \"\(pattern.text)\", which HealthTitle does not declare")
                XCTAssertEqual(pattern.isPrefix, stems.contains(pattern.text),
                               "a case on $HEALTH takes \"\(pattern.text)\" "
                                   + (pattern.isPrefix ? "as a prefix, and the line is exact" : "exactly, and the line has an age after it"))
            }
        }
        XCTAssertTrue(blocks.contains { Set($0.map(\.text)) == declared },
                      "no case on $HEALTH names all of \(declared.sorted()), so a health line the app gives could be unrecognised")
    }

    // MARK: - The guards' functions, their fixtures and their CI step (M5 plan, Task 9)

    /// `Scripts/harness-guards.sh` holds functions and nothing else: sourcing it defines them and
    /// runs nothing, sets nothing and touches nothing, so a script can source it and the guards'
    /// own script test can prove that it does. Here that is read off the text: outside a function
    /// there is only blank lines, comments and the line that opens the next one.
    func testTheGuardsFileHoldsFunctionsAndNothingElse() throws {
        let text = try Harness.script("harness-guards.sh")
        XCTAssertEqual(try Harness.linesOutsideFunctions(in: text), [],
                       "harness-guards.sh has code outside a function, which sourcing it would run")
        let names = try Harness.functions(in: text).map(\.name)
        for guardName in ["harness_refuse_guard", "harness_marker_only_guard", "harness_summary_guard",
                          "harness_backup_guard", "harness_install_marker", "harness_backup_path",
                          "harness_digest", "harness_current_version", Harness.helper] {
            XCTAssertTrue(names.contains(guardName), "harness-guards.sh does not define \(guardName)")
        }
        XCTAssertEqual(Set(names).count, names.count, "harness-guards.sh defines a function twice")
        // The scan is held on canned text: a line of code between two functions is found, a
        // function whose body has lines at the start of a line that are not its closing brace is
        // not mistaken for code outside it.
        XCTAssertEqual(try Harness.linesOutsideFunctions(in: "f() {\n    a\n}\n# c\n\nb=1\ng() {\n    h\n}"), ["b=1"])
        XCTAssertEqual(try Harness.linesOutsideFunctions(in: "#!/bin/bash\n# c\nf() {  # note\n    x\n}\n"), [])
        XCTAssertEqual(try Harness.linesOutsideFunctions(in: "set -e\nf() {\n}"), ["set -e"])
        XCTAssertEqual(try Harness.linesOutsideFunctions(in: "f() {\n}\nf"), ["f"])
        XCTAssertEqual(try Harness.linesOutsideFunctions(in: "f() { x; }\nb=1"), ["b=1"])
    }

    /// The guards read every word they compare from the file that declares it, in the functions
    /// that use it, so a guard that stopped reading one, or read the wrong one, is found here
    /// whatever else in the script still reads it.
    func testEachGuardReadsTheWordsItComparesThroughTheHelper() throws {
        let text = try Harness.script("harness-guards.sh")
        let bodies = Dictionary(uniqueKeysWithValues: try Harness.functions(in: text).map { ($0.name, $0.body) })
        let expected: [String: [(file: String, name: String)]] = [
            // The titles of the On Call item and the Snooze item, which every menu has and a text
            // that is not a menu lacks, the stems of the on-call line and of a running snooze's
            // line, and the Acknowledge item's title. The word "escalating" is read by the
            // function that builds the pattern.
            "harness_refuse_guard": [("OnCall.swift", "menuTitle"), ("SnoozeText.swift", "menuTitle"),
                                     ("OnCall.swift", "sinceStem"), ("SnoozeText.swift", "activeStem"),
                                     ("AlertMenuText.swift", "acknowledgeOneTitle")],
            "_harness_escalating_pattern": [("AlertMenuText.swift", "escalatingWord")],
            "harness_marker_only_guard": [("AlertMenuText.swift", "singleEscalatingStem"),
                                          ("AlertMenuText.swift", "acknowledgeOneTitle")],
            "harness_summary_guard": [("SnoozeText.swift", "heldOneMatchStem"), ("HarnessText.swift", "markerRuleName")],
        ]
        for (function, wanted) in expected.sorted(by: { $0.key < $1.key }) {
            let body = try XCTUnwrap(bodies[function], "harness-guards.sh does not define \(function)")
            let code = Harness.codeLines(body).joined(separator: "\n")
            let found = try Harness.references(in: code).map { "\($0.file) \($0.name)" }
            XCTAssertEqual(Set(found), Set(wanted.map { "\($0.file) \($0.name)" }),
                           "\(function) reads \(found.sorted()), and should read \(wanted.map { "\($0.file) \($0.name)" }.sorted())")
        }
        // The functions that call the pattern builder do, and the builder is the only reader of
        // the word, so the refuse guard and the marker-only guard cannot disagree about it.
        for function in ["harness_refuse_guard", "harness_marker_only_guard"] {
            XCTAssertTrue(try XCTUnwrap(bodies[function]).contains("_harness_escalating_pattern"),
                          "\(function) does not build its pattern for an escalating line with the shared function")
        }
        // The helper is defined once in the file, in the shape the declarations have.
        XCTAssertEqual(Harness.helperDefinitions(in: text).count, 1)
    }

    /// The rules version a script reads is a number and not a quoted text, so the helper's
    /// `sed` does not read it. The writer reads it with a `sed` of its own, and that `sed` is the
    /// one the declaration is held to in the test above.
    func testTheGuardsReadTheRulesVersionWithTheSedItsDeclarationIsHeldTo() throws {
        let versionSed = #"sed -n 's/^[[:space:]]*public static let currentVersion = \([0-9][0-9]*\)[[:space:]]*$/\1/p'"#
        let text = try Harness.script("harness-guards.sh")
        let body = try XCTUnwrap(try Harness.functions(in: text).first { $0.name == "harness_current_version" }?.body)
        XCTAssertTrue(body.contains(versionSed), "harness_current_version does not read the version with `\(versionSed)`")
        XCTAssertTrue(body.contains("RuleSetCodec.swift"), "harness_current_version does not read RuleSetCodec.swift")
    }

    /// The lines the guards compare a menu's lines to are built in the script out of the constants
    /// and a little punctuation, and the punctuation is the app's: the count after the stem, the
    /// colon and the multiplication sign. Held here on the script's text and on what the app builds.
    func testThePunctuationTheGuardsAddToTheStemsIsTheAppsOwn() throws {
        let text = try Harness.script("harness-guards.sh")
        let code = Harness.codeLines(text).joined(separator: "\n")
        let stem = try Harness.declaredText("AlertMenuText.swift", "singleEscalatingStem")
        let word = try Harness.declaredText("AlertMenuText.swift", "escalatingWord")

        // The marker-only guard's expected line is the stem for one escalation when the count is
        // 1, and the stem then " (N matches)" otherwise.
        XCTAssertTrue(code.contains(#"expected="$stem ($count matches)""#), "the marker-only guard does not build its expected line that way")
        XCTAssertTrue(code.contains(#"if [ "$count" -eq 1 ]; then"#))
        let then = EscalationSummary(ruleName: "On-call mentions", startedAt: now)
        XCTAssertEqual(AlertMenuText.escalationLines(listed: [then], shortcutFailure: nil, time: { _ in "10:42" }), [stem])
        for count in 2...30 {
            let burst = EscalationSummary(ruleName: "On-call mentions", startedAt: now, matchCount: count)
            XCTAssertEqual(AlertMenuText.escalationLines(listed: [burst], shortcutFailure: nil, time: { _ in "10:42" }),
                           ["\(stem) (\(count) matches)"], "a burst of \(count) matches")
        }

        // The summary guard's expected line is the stem, ": ", the name and " ×1".
        XCTAssertTrue(code.contains("expected=\"$stem: $name \u{D7}1\""), "the summary guard does not build its expected line that way")

        // The pattern for a line that says something is escalating is a count, one word, the word
        // and then a space or the end of the line. It takes the app's lines about escalating and
        // none of its other lines: not the one about what was missed, nor the last-match line of a
        // rule named for the word, nor a held summary of one.
        XCTAssertTrue(code.contains(#""^[0-9]+ [^ ]+ $(_harness_ere_escape "$word")( |\$)""#), "the pattern for an escalating line is not the one tested here")
        let pattern = try NSRegularExpression(pattern: "^[0-9]+ [^ ]+ \(NSRegularExpression.escapedPattern(for: word))( |$)")
        func says(_ line: String) -> Bool { pattern.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil }
        let escalating = EscalationSummary(ruleName: "On-call mentions", startedAt: now, matchCount: 3)
        let missed = EscalationSummary(ruleName: "On-call mentions", startedAt: now,
                                       status: .missedWhileAsleep(convertedAt: now, acknowledgedAt: nil))
        for listed in [[escalating], [escalating, escalating], [escalating, escalating, escalating, escalating]] {
            let line = try XCTUnwrap(AlertMenuText.escalationLines(listed: listed, shortcutFailure: nil, time: { _ in "10:42" }).first)
            XCTAssertTrue(says(line), "\"\(line)\" is not taken for a line that says something is escalating")
        }
        for line in AlertMenuText.escalationLines(listed: [missed], shortcutFailure: nil, time: { _ in "10:42" })
            + AlertMenuText.lines(lastMatch: CapturePipeline.LastMatch(ruleName: "On-call \(word) pages", at: now,
                                                                       alert: .played(sound: "Hero", gainDB: 0, outputSilent: false)),
                                  unresolvedFailure: nil, anyRulePlaysSound: true, outputSilent: false, time: { _ in "10:42" })
            + ["6 matches \(SnoozeText.heldStem): On-call \(word) pages \u{D7}6", "Rules: 3 active"] {
            XCTAssertFalse(says(line), "\"\(line)\" is taken for a line that says something is escalating")
        }
    }

    // MARK: Fixture menus

    private func utcCalendar() throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        calendar.locale = Locale(identifier: "en_GB")
        return calendar
    }

    private func clock(_ text: String) -> (Date) -> String { { _ in text } }

    /// The lines of a snooze's menu, whichever kind of item each is.
    private func lines(of menu: SnoozeMenu) -> [String] {
        menu.items.map { item in
            switch item {
            case .snooze(let title, _): return title
            case .line(let text): return text
            case .dismiss(let title, _): return title
            }
        }
    }

    /// Whether the core makes a line of this kind: the app's words for a health line, an escalation,
    /// an Acknowledge item, the on-call lines, the snooze lines, the last match and the rules
    /// summary, or the titles of the items the core names.
    private func isMadeByTheCore(_ line: String) throws -> Bool {
        let titles: Set<String> = [OnCallText.menuTitle, SnoozeText.menuTitle, SnoozeText.dismissTitle,
                                   OnCallText.checkItemTitle, OnCallText.awakeLine, SetupText.rulesFileMenuTitle,
                                   SettingsText.menuTitle]
        let stems = [AlertMenuText.acknowledgeOneTitle, OnCallText.sinceStem, SnoozeText.activeStem,
                     SnoozeText.stillAlertingStem, "Last match:", "Rules:", HealthTitle.verifiedStem,
                     HealthTitle.checkingLine, HealthTitle.unverifiedStem, HealthTitle.cannotVerifyLine,
                     HealthTitle.notCapturingLine]
        let counted = try NSRegularExpression(
            pattern: "^[0-9]+ (alerts? (\(AlertMenuText.escalatingWord)|missed while asleep)|match(es)? \(SnoozeText.heldStem))")
        return titles.contains(line) || stems.contains { line.hasPrefix($0) }
            || counted.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
    }

    /// The few lines of the menu the app target types itself and the core does not make: the
    /// capture count, the Inspector, the line about how many of the last captures the rules match,
    /// and the editor, reload and quit items. They hold a count and a title and nothing else.
    private func isTypedByTheApp(_ line: String) throws -> Bool {
        let shapes = [#"^Captured [0-9]+ notifications?$"#, #"^Show Inspector…$"#,
                      #"^Current rules match [0-9]+ of the last [0-9]+$"#, #"^Edit Rules…$"#, #"^Reload Rules$"#,
                      #"^Quit SignalLadder$"#]
        return try shapes.contains { shape in
            try NSRegularExpression(pattern: shape).firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
        }
    }

    /// Each fixture menu is the lines the core builds for the case its name gives, in the order the
    /// menu has them (M5 plan, Ruling 17), and every other line of it is one of the few the app
    /// types, so a fixture cannot say what the app does not, hold the name of anything but a rule or
    /// carry anything a banner said. The core's functions are called with the fixture's counts and
    /// names, and the lines they give are compared with the fixture's, line for line.
    func testEachFixtureMenuIsWhatTheCoreBuildsForTheCaseItNames() throws {
        let calendar = try utcCalendar()
        let monday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 9)))
        let health = HealthTitle.text(for: .verified, secondsSinceLastSuccessfulCanary: 3 * 60 + 5)
        let onCall = OnCallText.menuTitle

        let weather = Rule(name: "Weather stays quiet", condition: .field(.app, .equals, "Weather"), alert: .silent)
        let prod = Rule(name: "Prod and incident channels", condition: .field(.title, .matches, "#prod-*"),
                        alert: .sound(name: "Glass", gainDB: 6), quietWhenSnoozed: true)
        let mentions = Rule(name: "On-call mentions", condition: .field(.app, .equals, "Example Chat"),
                            alert: .sound(name: "Hero", gainDB: 0),
                            escalation: Escalation(tier4: FinalAlert(action: .shortcut(name: "Page the on-call phone"))))
        let marker = Rule(name: HarnessText.markerRuleName, condition: .field(.title, .equals, HarnessText.markerTitle),
                          alert: .sound(name: "Glass", gainDB: 0), quietWhenSnoozed: true)

        func tail(rules active: Int, lastMatch: [String] = []) -> [String] {
            [RuleStoreStatus.loaded(enabled: active, disabled: 0).summary] + lastMatch
                + [SetupText.rulesFileMenuTitle, SettingsText.menuTitle]
        }
        func lastMatch(_ name: String, _ alert: AlertOutcome, at time: String) -> [String] {
            AlertMenuText.lines(lastMatch: CapturePipeline.LastMatch(ruleName: name, at: now, alert: alert),
                                unresolvedFailure: nil, anyRulePlaysSound: true, outputSilent: false, time: clock(time))
        }
        func escalation(_ listed: [EscalationSummary]) -> [String] {
            [AlertMenuText.acknowledgeTitle(listed: listed.count)]
                + AlertMenuText.escalationLines(listed: listed, shortcutFailure: nil, time: clock("10:42"))
        }
        func snoozed(_ rules: [Rule], endsAt: Date? = nil, held: HeldSummary = HeldSummary()) -> [String] {
            lines(of: SnoozeText.menu(rules: rules, onCall: .off, snoozeEndsAt: endsAt, summary: held, endedByOnCallAt: nil,
                                      now: now, time: clock("15:30")))
        }
        let one = EscalationSummary(ruleName: "On-call mentions", startedAt: now)
        func burst(_ count: Int) -> EscalationSummary {
            EscalationSummary(ruleName: HarnessText.markerRuleName, startedAt: now, matchCount: count)
        }
        let missed = EscalationSummary(ruleName: "On-call mentions", startedAt: now,
                                       status: .missedWhileAsleep(convertedAt: now, acknowledgedAt: nil))
        let threeRules = [weather, prod, mentions]
        let fourRules = threeRules + [marker]
        let quietHead = [health, onCall] + snoozed(threeRules)

        let fixtures: [(file: String, core: [String])] = [
            ("quiet", quietHead + tail(rules: 3)),
            ("on-call", [health, onCall,
                         AlertMenuText.onCallSinceLine(since: monday, allowsSelfTest: true, calendar: calendar, time: clock("09:00")),
                         try XCTUnwrap(AlertMenuText.awakeLine(held: true)), OnCallText.checkItemTitle]
                + snoozed(threeRules) + tail(rules: 3)),
            // Prod's rule is ticked and sounds, and the mentions rule ends in a Shortcut, so a snooze
            // quiets one of the two rules that sound and the other is still alerting.
            ("snoozed", [health, onCall] + snoozed(threeRules, endsAt: now.addingTimeInterval(900)) + tail(rules: 3)),
            ("held-summary-marker", [health, onCall]
                + snoozed(fourRules, held: HeldSummary(counts: [marker.id: 1]))
                + tail(rules: 4, lastMatch: lastMatch(marker.name, .snoozed, at: "10:42"))),
            ("held-summary-other", [health, onCall]
                + snoozed(fourRules, held: HeldSummary(counts: [prod.id: 3]))
                + tail(rules: 4, lastMatch: lastMatch(prod.name, .snoozed, at: "10:44"))),
            ("held-summary-mixed", [health, onCall]
                + snoozed(fourRules, held: HeldSummary(counts: [prod.id: 1, marker.id: 1]))
                + tail(rules: 4, lastMatch: lastMatch(marker.name, .snoozed, at: "10:44"))),
            ("escalating-one", escalation([one]) + quietHead + tail(rules: 3)),
            ("escalating-burst", escalation([burst(5)]) + quietHead + tail(rules: 3)),
            ("escalating-burst-four", escalation([burst(4)]) + quietHead + tail(rules: 3)),
            ("escalating-two", escalation([burst(3), burst(3)]) + quietHead + tail(rules: 3)),
            ("escalating-beside-missed", escalation([one, missed]) + quietHead + tail(rules: 3)),
            ("missed-alone", escalation([missed]) + quietHead + tail(rules: 3)),
            ("quiet-rule-named-escalating", quietHead + tail(rules: 3, lastMatch: lastMatch(
                "On-call \(AlertMenuText.escalatingWord) pages", .played(sound: "Hero", gainDB: 0, outputSilent: false), at: "09:41"))),
        ]

        let found = try FileManager.default.contentsOfDirectory(atPath: Harness.fixtures.path)
            .filter { $0.hasPrefix("menu-") && $0.hasSuffix(".txt") }.sorted()
        XCTAssertEqual(found, fixtures.map { "menu-\($0.file).txt" }.sorted(),
                       "a menu fixture has no case here, or a case has no fixture")

        for fixture in fixtures {
            let lines = try Harness.menu(fixture.file)
            XCTAssertEqual(try lines.filter(isMadeByTheCore), fixture.core, "menu-\(fixture.file).txt")
            for line in lines where !(try isMadeByTheCore(line)) {
                XCTAssertTrue(try isTypedByTheApp(line),
                              "menu-\(fixture.file).txt holds \"\(line)\", which is neither a line the core builds nor one the app types")
            }
        }
    }

    /// The fixtures hold what the guards' cases say they do. The Acknowledge titles of the cases
    /// are the ones the guards were written for: one alert listed gives the exact title the harness
    /// clicks, and an escalation beside a miss does not.
    func testTheFixtureMenusGiveTheGuardsTheCasesTheyWereWrittenFor() throws {
        let exact = try Harness.declaredText("AlertMenuText.swift", "acknowledgeOneTitle")
        let first = { (file: String) throws -> String? in try Harness.menu(file).first }
        XCTAssertEqual(try first("escalating-one"), exact)
        XCTAssertEqual(try first("escalating-burst"), exact)
        XCTAssertEqual(try first("escalating-burst-four"), exact)
        XCTAssertEqual(try first("missed-alone"), exact)
        XCTAssertNotEqual(try first("escalating-two"), exact)
        XCTAssertNotEqual(try first("escalating-beside-missed"), exact)
        // The menus that say nothing is waiting have no Acknowledge item.
        for file in ["quiet", "on-call", "snoozed", "held-summary-marker", "held-summary-other", "held-summary-mixed",
                     "quiet-rule-named-escalating"] {
            XCTAssertFalse(try Harness.menu(file).contains { $0.hasPrefix(exact) }, "menu-\(file).txt has an Acknowledge item")
        }
        // Only the menus of a running state have its line.
        let onCall = try Harness.declaredText("OnCall.swift", "sinceStem")
        let snoozeStem = try Harness.declaredText("SnoozeText.swift", "activeStem")
        for file in ["quiet", "held-summary-marker", "escalating-one", "quiet-rule-named-escalating"] {
            XCTAssertFalse(try Harness.menu(file).contains { $0.hasPrefix(onCall) || $0.hasPrefix(snoozeStem) },
                           "menu-\(file).txt shows a state that belongs to a real shift")
        }
        XCTAssertTrue(try Harness.menu("on-call").contains { $0.hasPrefix(onCall) })
        XCTAssertTrue(try Harness.menu("snoozed").contains { $0.hasPrefix(snoozeStem) })

        // And every one of them holds the On Call item and the Snooze item, each as a line of its own,
        // which the refuse guard needs of a text before it takes it for a menu it can judge.
        let items = [try Harness.declaredText("OnCall.swift", "menuTitle"), try Harness.declaredText("SnoozeText.swift", "menuTitle")]
        let names = try FileManager.default.contentsOfDirectory(atPath: Harness.fixtures.path)
            .filter { $0.hasPrefix("menu-") && $0.hasSuffix(".txt") }
            .map { String($0.dropFirst("menu-".count).dropLast(".txt".count)) }.sorted()
        XCTAssertFalse(names.isEmpty)
        for name in names {
            let lines = try Harness.menu(name)
            for item in items {
                XCTAssertEqual(lines.filter { $0 == item }.count, 1, "menu-\(name).txt does not hold the \"\(item)\" item once")
            }
        }
    }

    /// The refuse guard takes a text for a menu only when it holds the On Call item and the Snooze
    /// item, since a text without them, such as the word the harness gets when it finds no status
    /// item, or a read cut short, cannot say that the Mac is not on a shift. That holds of every menu
    /// the app builds only if both are added whatever the state: `rebuildMenuItems` adds each section
    /// at the top of the function and not under a condition, the On Call item comes before the
    /// guard on the mode that ends its section, and the Snooze section's first item is the Snooze
    /// item whether or not a snooze runs
    /// (`testTheSnoozeSubmenuHasTheFifteenMinuteItemAndEndSnoozeUnderTheTitlesTheHarnessReads`).
    /// Were either made conditional, the harness would refuse every run in that state, and this
    /// finds it before a person does.
    func testEveryMenuTheAppBuildsHasTheOnCallItemAndTheSnoozeItemTheRefuseGuardLooksFor() throws {
        let source = try XCTUnwrap(AppSources.read("AppDelegate.swift"), "AppDelegate.swift is gone")
        let lines = source.components(separatedBy: "\n")
        func body(of header: String) throws -> [String] {
            let start = try XCTUnwrap(lines.firstIndex { $0.hasPrefix(header) }, "AppDelegate.swift has no \(header)")
            let end = try XCTUnwrap(lines[start...].firstIndex { $0 == "    }" }, "\(header) is not closed")
            return Array(lines[start..<end])
        }
        let build = try body(of: "    private func rebuildMenuItems(")
        for call in ["addOnCallSection(to: menu, loginItemStatus: loginItemStatus)", "addSnoozeSection(to: menu)"] {
            XCTAssertTrue(build.contains("        \(call)"), "rebuildMenuItems does not add `\(call)` at the top of its body, whatever the state")
        }

        let onCall = try body(of: "    private func addOnCallSection(")
        let add = try XCTUnwrap(onCall.firstIndex { $0 == "        menu.addItem(toggle)" }, "addOnCallSection does not add the On Call item")
        let ends = try XCTUnwrap(onCall.firstIndex { $0 == "        guard isOn else { return }" }, "addOnCallSection no longer ends its section on the mode")
        XCTAssertLessThan(add, ends, "the On Call item is added only while the mode is on")
        XCTAssertTrue(onCall.contains { $0.contains("NSMenuItem(title: OnCallText.menuTitle,") }, "the On Call item is not titled by OnCallText.menuTitle")

        let snooze = try body(of: "    private func addSnoozeSection(")
        XCTAssertTrue(snooze.contains { $0.contains("for item in snoozeMenu.items {") }, "addSnoozeSection does not add every item the snooze's menu gives")
    }

    // MARK: Fixture rules files

    private func json(_ text: String) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// The rules file shaped as the owner's are: the layout the app writes (keys sorted, one space
    /// either side of each colon, no newline after the last brace), at version 3, with three rules,
    /// one of which escalates. Its text is what `RuleSetCodec.encode` writes for those rules but for
    /// the version, which it writes as 4 for a rule that escalates. A version 3 file that holds an
    /// escalation is one the codec calls a problem, so this is a file for the writer's cases, which
    /// read no rule of it, and the version is 3 so that a marker that needs 4 or 5 raises it.
    func testTheOwnerShapedRulesFixtureIsTheAppsLayoutAtVersionThreeWithOneEscalation() throws {
        let text = try Harness.fixture("rules-owner.json")
        XCTAssertFalse(text.hasSuffix("\n"), "the app writes no newline after the last brace, and the digests beside the fixtures are of these bytes")
        let file = try json(text)
        XCTAssertEqual(file["version"] as? Int, 3)
        let rules = try XCTUnwrap(file["rules"] as? [[String: Any]])
        XCTAssertEqual(rules.count, 3)
        XCTAssertEqual(rules.filter { $0["escalation"] != nil }.count, 1)
        let have = try XCTUnwrap(file["version"] as? Int)
        for (marker, version) in [("marker-rule-escalation.json", 4), ("marker-rule-snooze.json", 5)] {
            XCTAssertLessThan(have, RuleSetCodec.version(for: [try markerRule(marker, atVersion: version)]),
                              "the file's version must be below the one \(marker) needs, so that the writer raises it")
        }

        func id(_ ending: String) throws -> UUID { try XCTUnwrap(UUID(uuidString: "6F0B2A52-6C3F-4C2E-9D7A-0A1B2C3D4E\(ending)")) }
        let rebuilt = [
            Rule(id: try id("01"), name: "Weather stays quiet", condition: .field(.app, .equals, "Weather"), alert: .silent),
            Rule(id: try id("02"), name: "Prod and incident channels",
                 condition: .or([.field(.title, .matches, "#prod-*"), .field(.title, .matches, "#incident-*")]),
                 alert: .sound(name: "Glass", gainDB: 6)),
            Rule(id: try id("03"), name: "On-call mentions",
                 condition: .and([.field(.app, .equals, "Example Chat"), .field(.body, .contains, "on-call")]),
                 alert: .sound(name: "Hero", gainDB: 0),
                 escalation: Escalation(tier2: PanelAlert(delaySeconds: 10),
                                        tier3: RepeatAlert(action: .sound(name: "Hero", gainDB: 0), intervalSeconds: 30,
                                                           maxRepeats: 20, maxDurationSeconds: 600),
                                        tier4: FinalAlert(afterSeconds: 120, action: .shortcut(name: "Page the on-call phone")))),
        ]
        let written = String(decoding: try RuleSetCodec.encode(rebuilt), as: UTF8.self)
        XCTAssertEqual(written.replacingOccurrences(of: "\"version\" : 4", with: "\"version\" : 3"), text,
                       "the fixture is no longer what the app writes for these rules")
    }

    /// The two files the writer must refuse are what they say: one the codec cannot read and one it
    /// reads as newer than itself. The third kind, a file that cannot be read, cannot be committed,
    /// and the script's test makes it.
    func testTheRefusedRulesFixturesAreWhatTheCodecRefuses() throws {
        let notJSON = try Harness.fixtureData("rules-not-json.json")
        XCTAssertThrowsError(try JSONSerialization.jsonObject(with: notJSON), "rules-not-json.json is JSON")
        let (rules, status) = RuleStoreStatus.load(notJSON, availableSounds: nil, unplayable: nil, availableVoices: nil)
        XCTAssertEqual(rules, [])
        guard case .unreadable = status else { return XCTFail("the codec does not call rules-not-json.json unreadable: \(status)") }

        let tooNew = try Harness.fixtureData("rules-too-new.json")
        let file = try XCTUnwrap(try JSONSerialization.jsonObject(with: tooNew) as? [String: Any], "rules-too-new.json is not JSON")
        let version = try XCTUnwrap(file["version"] as? Int)
        XCTAssertGreaterThan(version, RuleSetCodec.currentVersion, "rules-too-new.json is not newer than the codec")
        XCTAssertEqual(RuleStoreStatus.load(tooNew, availableSounds: nil, unplayable: nil, availableVoices: nil).status,
                       .unsupportedVersion(version))
        // And it is otherwise the owner's file, so that nothing but the version is what is refused.
        let owner = try json(try Harness.fixture("rules-owner.json"))
        XCTAssertEqual((file["rules"] as? [Any])?.count, (owner["rules"] as? [Any])?.count)
    }

    /// A marker rule fixture, as the codec loads it in a file at `version`.
    private func markerRule(_ file: String, atVersion version: Int) throws -> Rule {
        let text = try Harness.fixture(file)
        let data = Data("{\"version\": \(version), \"rules\": [\(text)]}".utf8)
        let (rules, status) = RuleStoreStatus.load(data, availableSounds: nil, unplayable: nil, availableVoices: nil)
        XCTAssertEqual(status, .loaded(enabled: 1, disabled: 0), "\(file) at version \(version)")
        return try XCTUnwrap(rules.first, "\(file) loads no rule")
    }

    /// The marker rules the writer's cases append are rules the codec accepts, at the version each
    /// is told to need: the escalation marker is a rule with an escalation, which needs 4, and the
    /// snooze marker is a rule a snooze may hold, which needs 5. Each matches only the marker's
    /// banner and bears the marker's name.
    func testTheMarkerRuleFixturesAreRulesTheCodecAcceptsAtTheVersionsTheyNeed() throws {
        let escalation = try markerRule("marker-rule-escalation.json", atVersion: 4)
        let snooze = try markerRule("marker-rule-snooze.json", atVersion: 5)
        for rule in [escalation, snooze] {
            XCTAssertEqual(rule.name, HarnessText.markerRuleName)
            XCTAssertEqual(rule.condition, .field(.title, .equals, HarnessText.markerTitle))
            XCTAssertTrue(rule.isEnabled)
        }
        XCTAssertEqual(RuleSetCodec.version(for: [escalation]), 4, "the escalation marker needs version 4 and the script's cases say 4")
        XCTAssertEqual(RuleSetCodec.version(for: [snooze]), 5, "the snooze marker needs version 5 and the script's cases say 5")
        XCTAssertEqual(escalation.alert, .silent)
        let tier3 = try XCTUnwrap(escalation.escalation?.tier3)
        XCTAssertEqual(tier3.action, .sound(name: "Hero", gainDB: AlertAction.gainRange.lowerBound))
        XCTAssertEqual(tier3.intervalSeconds, 30)
        XCTAssertEqual(tier3.maxRepeats, 2)
        XCTAssertNil(escalation.escalation?.tier4, "the escalation marker runs no Shortcut")
        XCTAssertTrue(snooze.quietWhenSnoozed)
        XCTAssertTrue(snooze.snoozeMayHold, "a snooze would not hold the snooze marker")
        // The escalation marker is refused at the version before: that is why the writer raises it.
        let before = Data("{\"version\": 3, \"rules\": [\(try Harness.fixture("marker-rule-escalation.json"))]}".utf8)
        if case .loaded = RuleStoreStatus.load(before, availableSounds: nil, unplayable: nil, availableVoices: nil).status {
            XCTFail("the escalation marker loads at version 3, so the version it needs is not 4")
        }
    }

    /// The leftover states: a backup beside the file a run wrote with the digest of that file, the
    /// same with the file edited since, a backup with no digest beside a file that differs and one
    /// beside a file equal to it, and the record of a run that found no rules file and made one.
    /// The digests are the SHA-256 of the bytes the fixtures hold, and the names are the ones the
    /// script's `harness_backup_path` gives.
    func testTheBackupStatesHoldWhatTheirNamesSay() throws {
        let states = Harness.fixtures.appendingPathComponent("backup-states")
        func data(_ state: String, _ name: String) throws -> Data { try Data(contentsOf: states.appendingPathComponent("\(state)/\(name)")) }
        func has(_ state: String, _ name: String) -> Bool {
            FileManager.default.fileExists(atPath: states.appendingPathComponent("\(state)/\(name)").path)
        }
        func digest(_ state: String) throws -> String {
            String(decoding: try data(state, "rules.json.harness-backup.sha256"), as: UTF8.self)
        }
        let owner = try Harness.fixtureData("rules-owner.json")
        let backup = "rules.json.harness-backup"

        // Not the hidden files a folder can hold, such as the .DS_Store a Finder window leaves
        // (git ignores it), which are nothing of the fixtures'.
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: states.path).filter { !$0.hasPrefix(".") }.sorted(),
                       ["absent-written", "edited", "no-digest-differs", "no-digest-equal", "written"])
        for state in ["written", "edited", "no-digest-differs", "no-digest-equal"] {
            XCTAssertEqual(try data(state, backup), owner, "\(state): the backup is not the owner's file")
        }
        for state in ["no-digest-differs", "no-digest-equal"] {
            XCTAssertFalse(has(state, "\(backup).sha256"), "\(state) has a digest")
        }
        XCTAssertEqual(try data("no-digest-equal", "rules.json"), owner)
        XCTAssertNotEqual(try data("no-digest-differs", "rules.json"), owner)
        XCTAssertEqual(try data("no-digest-differs", "rules.json"), try data("written", "rules.json"))

        // The file a run wrote: the owner's three rules, then the marker's, at version 4.
        let written = try json(String(decoding: try data("written", "rules.json"), as: UTF8.self))
        XCTAssertEqual(written["version"] as? Int, 4)
        let ownerRules = try XCTUnwrap(try json(String(decoding: owner, as: UTF8.self))["rules"] as? [NSDictionary])
        let writtenRules = try XCTUnwrap(written["rules"] as? [NSDictionary])
        XCTAssertEqual(Array(writtenRules.prefix(3)), ownerRules)
        let marker = try json(try Harness.fixture("marker-rule-escalation.json")) as NSDictionary
        XCTAssertEqual(writtenRules.count, 4)
        XCTAssertEqual(writtenRules.last, marker)

        // Its digest is recorded, and so is the one the edited state still holds: the file edited
        // since is not the file the digest is of.
        let wrote = sha256(try data("written", "rules.json"))
        XCTAssertEqual(try digest("written"), wrote + "\n")
        XCTAssertEqual(try digest("edited"), wrote + "\n")
        XCTAssertNotEqual(sha256(try data("edited", "rules.json")), wrote)
        let edited = try XCTUnwrap(try json(String(decoding: try data("edited", "rules.json"), as: UTF8.self))["rules"] as? [NSDictionary])
        XCTAssertEqual(edited.count, 4)
        XCTAssertEqual(edited[1]["enabled"] as? Bool, false, "the owner switched the second rule off")

        // The run that found no rules file: the record, the digest of what it made, and the file.
        XCTAssertTrue(has("absent-written", "\(backup).absent"))
        XCTAssertFalse(has("absent-written", backup))
        XCTAssertEqual(try digest("absent-written"), sha256(try data("absent-written", "rules.json")) + "\n")
        let made = try json(String(decoding: try data("absent-written", "rules.json"), as: UTF8.self))
        XCTAssertEqual((made["rules"] as? [NSDictionary])?.count, 1)
        XCTAssertEqual((made["rules"] as? [NSDictionary])?.first, marker)
        XCTAssertEqual(made["version"] as? Int, 4)
    }

    // MARK: The CI step

    /// CI runs the guards' script test as a step of its own, after the tests, on both toolchains. The
    /// matrix of the job has the two, so a step of the job runs on both. The script is run by its
    /// path, which takes its shebang, the macOS system bash 3.2 that the guards are written for, so
    /// it must be executable and name that shell.
    func testCIRunsTheGuardsScriptTestAsAStepOfItsOwnAfterTheTests() throws {
        let ci = try Harness.read(Harness.root.appendingPathComponent(".github/workflows/ci.yml"))
        let lines = ci.components(separatedBy: "\n")
        let test = try XCTUnwrap(lines.firstIndex { $0.contains("run: swift test --skip-build") }, "ci.yml no longer runs the tests")
        let guards = try XCTUnwrap(lines.firstIndex { $0.contains("run: Scripts/harness-guards-test.sh") },
                                   "ci.yml does not run Scripts/harness-guards-test.sh")
        XCTAssertGreaterThan(guards, test, "the guards' test runs before the tests")
        XCTAssertTrue(lines[guards - 1].trimmingCharacters(in: .whitespaces).hasPrefix("- name:"),
                      "the guards' test is not a step of its own, with a name")
        XCTAssertEqual(lines.filter { $0.contains("harness-guards-test.sh") }.count, 1, "the script is run twice")
        XCTAssertEqual(lines[guards].trimmingCharacters(in: .whitespaces), "run: Scripts/harness-guards-test.sh",
                       "the step runs the script with something else beside it")
        XCTAssertTrue(lines.contains { $0.contains("runner: macos-26") })
        XCTAssertTrue(lines.contains { $0.contains("runner: macos-15") })
        XCTAssertFalse(ci.contains("continue-on-error"), "a step of ci.yml may fail without failing the run")

        let script = Harness.scripts.appendingPathComponent("harness-guards-test.sh")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: script.path), "harness-guards-test.sh is not executable, and CI runs it by its path")
        XCTAssertEqual(try Harness.read(script).components(separatedBy: "\n").first, "#!/bin/bash")
    }
}
