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
//  - `verify-live.sh` sources the file that defines the helper and keeps no copy of it,
//    reads every word it looks for through it into a variable that is checked not to
//    be empty and is used, and its cause reading steps over the On Call item and the
//    setup line;
//  - the window titles are distinct and each begins with the app's name;
//  - no script types, as a lookup of its own (in quotes, against a glob or an
//    anchor, as a `case` arm, a `grep`'s argument or an operand), the text of a
//    constant it reads;
//  - the wordings the script takes for a health line, in `is_health_line` and in
//    each `case "$HEALTH"`, are read from the five constants `HealthTitle` declares,
//    and they are the ones it gives a health line, and no other line the menu can hold;
//  - the words the harness of the plan's Task 9 reads are declared in that shape too,
//    and the lines the app builds from them begin with them or are the lines the
//    harness's guards compare;
//  - the flags of `verify-live.sh` stand on the guards: each begins with the backup
//    guard, is refused on the first menu it reads before any default check posts or
//    opens anything, and runs the refuse guard again on a fresh menu before it acts;
//    the traps are set before anything is written, the restore checks the digest and
//    the signals are ignored before the run is marked as undone, the click on
//    Acknowledge and the dismissal of the summary wait for their guards, `--snooze`
//    is refused beside a held summary and checks the marker's match by the summary
//    guard, and nothing in the script reads what a notification said;
//  - the marker rules the script writes are rules the codec accepts, at the version the
//    writer is told they need;
//  - the marker goes FIRST in the rules file (the owner's decision of 2026-10-13, which
//    departs from the plan's "only appends"): the marked fixtures are the owner's file
//    with the marker in front of its first rule and nothing else changed but the version,
//    they decode under the codec with the marker as rules[0], and the engine, which takes the
//    first enabled rule to match, gives a banner with the marker's title to the marker
//    whatever rule of the owner's could also match it;

// These tests start no process and run no script. They read text.

/// A reference to a constant: the helper called with a file and a name.
private struct ConstantReference: Hashable {
    let script: String
    let file: String
    let name: String
}

private enum Harness {
    static let root = PackageRoot.url
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
    /// TEXT`, or a quoted pattern that begins with it, `grep -o 'TEXT [0-9]*'`) or as the
    /// operand of a comparison or an assignment (`= TEXT`, `==TEXT`, `=~ TEXT`,
    /// `NAME=TEXT`). The same letters inside a longer sentence, such as a
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
            #"\bgrep\b[^\n]*["']\#(word)"#,
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

    /// Every line of a script that reads one constant into a variable, as `VARIABLE=$(core_constant
    /// FILE.swift NAME)`, which is the one form the harness reads a word in.
    static func assignments(in code: String) throws -> [(variable: String, file: String, name: String)] {
        let shape = try NSRegularExpression(
            pattern: #"^([A-Z][A-Z0-9_]*)=\$\(\#(helper) ([A-Za-z][A-Za-z0-9]*\.swift) ([A-Za-z][A-Za-z0-9]*)\)$"#,
            options: .anchorsMatchLines)
        return shape.matches(in: code, range: NSRange(code.startIndex..., in: code)).map { match in
            (variable: String(code[Range(match.range(at: 1), in: code)!]),
             file: String(code[Range(match.range(at: 2), in: code)!]),
             name: String(code[Range(match.range(at: 3), in: code)!]))
        }
    }

    /// The code lines (no comment lines) of the one function of that name in a script.
    static func body(of name: String, in text: String) throws -> [String] {
        let found = try functions(in: text).filter { $0.name == name }
        XCTAssertEqual(found.count, 1, "the script must define \(name) once")
        return codeLines(try XCTUnwrap(found.first?.body, "the script does not define \(name)"))
    }

    /// The index of the first line that contains `needle`, or a failure that names it.
    static func first(_ needle: String, in lines: [String], after start: Int = 0, _ what: String = "") throws -> Int {
        try XCTUnwrap(lines.indices.first { $0 >= start && lines[$0].contains(needle) },
                      "\(what.isEmpty ? "the script" : what) has no line with \(needle) after line \(start)")
    }
}

final class HarnessConstantsTests: XCTestCase {
    // MARK: - What the scripts read

    /// Every word `verify-live.sh` looks for or chooses, by the variable it keeps it in and the
    /// constant it is read from. The script reads these through the helper and no others: a read
    /// that is not listed here, or one listed here that the script no longer makes, fails.
    private let verifyReads: [(variable: String, file: String, name: String)] = [
        ("INSPECTOR_TITLE", "WindowTitles.swift", "inspector"),
        ("RULE_EDITOR_TITLE", "WindowTitles.swift", "ruleEditor"),
        ("SETTINGS_TITLE", "WindowTitles.swift", "settings"),
        ("ON_CALL_CHECK_TITLE", "WindowTitles.swift", "onCallCheck"),
        ("INSPECTOR_ITEM", "StatusMenuText.swift", "showInspectorTitle"),
        ("EDIT_RULES_ITEM", "StatusMenuText.swift", "editRulesTitle"),
        ("RELOAD_RULES_ITEM", "StatusMenuText.swift", "reloadRulesTitle"),
        ("SETTINGS_ITEM", "SettingsText.swift", "menuTitle"),
        ("ON_CALL_ITEM", "OnCall.swift", "menuTitle"),
        ("SNOOZE_ITEM", "SnoozeText.swift", "menuTitle"),
        ("SNOOZE_FIFTEEN_ITEM", "SnoozeText.swift", "fifteenMinutesTitle"),
        ("SNOOZE_END_ITEM", "SnoozeText.swift", "endTitle"),
        ("DISMISS_ITEM", "SnoozeText.swift", "dismissTitle"),
        ("ACKNOWLEDGE_ITEM", "AlertMenuText.swift", "acknowledgeOneTitle"),
        ("CAPTURED_STEM", "StatusMenuText.swift", "capturedStem"),
        ("RULES_STEM", "RuleSetCodec.swift", "summaryStem"),
        ("LAST_MATCH_STEM", "AlertMenuText.swift", "lastMatchStem"),
        ("NUDGE_STEM", "SetupText.swift", "nudgeStem"),
        ("ON_CALL_SINCE_STEM", "OnCall.swift", "sinceStem"),
        ("ESCALATING_STEM", "AlertMenuText.swift", "singleEscalatingStem"),
        ("SNOOZE_ACTIVE_STEM", "SnoozeText.swift", "activeStem"),
        ("OUTPUT_SILENT", "AlertMenuText.swift", "outputSilentSentence"),
        ("MUTE_CONFIRMED_STEM", "MuteWalkthrough.swift", "confirmedStem"),
        ("MUTE_NOT_CONFIRMED_STEM", "MuteWalkthrough.swift", "notConfirmedStem"),
        ("FAIL_PLAY", "InspectorEntry.swift", "couldNotPlay"),
        ("FAIL_SPEAK", "InspectorEntry.swift", "couldNotSpeak"),
        ("FAIL_PLAYED_NOT_SPOKEN", "InspectorEntry.swift", "butCouldNotSpeak"),
        ("FAIL_SPOKE_NOT_PLAYED", "InspectorEntry.swift", "butCouldNotPlay"),
        ("HEALTH_VERIFIED", "HealthTitle.swift", "verifiedStem"),
        ("HEALTH_CHECKING", "HealthTitle.swift", "checkingLine"),
        ("HEALTH_UNVERIFIED", "HealthTitle.swift", "unverifiedStem"),
        ("HEALTH_CANNOT_VERIFY", "HealthTitle.swift", "cannotVerifyLine"),
        ("HEALTH_NOT_CAPTURING", "HealthTitle.swift", "notCapturingLine"),
        ("HEALTH_SOME_UNREAD", "HealthTitle.swift", "someBannersUnreadLine"),
        ("MARKER_NAME", "HarnessText.swift", "markerRuleName"),
        ("MARKER_TITLE", "HarnessText.swift", "markerTitle"),
        ("MARKER_ESCALATION_ID", "HarnessText.swift", "markerEscalationRuleID"),
        ("MARKER_SNOOZE_ID", "HarnessText.swift", "markerSnoozeRuleID"),
        ("ON_CALL_KEY", "OnCall.swift", "storageKey"),
    ]

    /// `verify-live.sh` sources the file that defines the helper, before it makes its first
    /// read, and defines no helper of its own: the guards' script test proves the one
    /// definition, and a second would be a copy nothing held to the shape.
    func testTheHarnessSourcesTheGuardsFileAndKeepsNoCopyOfTheHelper() throws {
        let verify = try Harness.script("verify-live.sh")
        XCTAssertFalse(verify.contains("\(Harness.helper)() {"), "verify-live.sh defines a helper of its own")
        XCTAssertFalse(verify.contains("function \(Harness.helper)"), "verify-live.sh defines a helper of its own")
        let guards = try Harness.script("harness-guards.sh")
        XCTAssertEqual(Harness.helperDefinitions(in: guards).count, 1, "harness-guards.sh must define the helper once")

        let code = Harness.codeLines(verify)
        let path = try Harness.first(#"GUARDS="$REPO_ROOT/Scripts/harness-guards.sh""#, in: code)
        let sourced = try Harness.first(#". "$GUARDS""#, in: code, after: path)
        let firstRead = try Harness.first("$(\(Harness.helper) ", in: code)
        XCTAssertLessThan(sourced, firstRead, "verify-live.sh reads a word before it has sourced the helper")
        XCTAssertTrue(code.contains(#"REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"#),
                      "the helper finds the app's files from the REPO_ROOT the script sets")
        XCTAssertLessThan(try Harness.first("REPO_ROOT=$(cd", in: code), sourced, "REPO_ROOT is set after the file is sourced")
    }

    func testEveryWordTheHarnessLooksForIsReadThroughTheHelperIntoAVariableThatIsCheckedAndUsed() throws {
        let verify = try Harness.script("verify-live.sh")
        let lines = Harness.codeLines(verify)
        let code = lines.joined(separator: "\n")
        let read = try Harness.assignments(in: code).map { "\($0.variable)=\($0.file):\($0.name)" }
        let wanted = verifyReads.map { "\($0.variable)=\($0.file):\($0.name)" }
        XCTAssertEqual(read.count, Set(read).count, "a word is read twice")
        XCTAssertEqual(Set(read).subtracting(wanted).sorted(), [], "verify-live.sh reads a word this test does not list")
        XCTAssertEqual(Set(wanted).subtracting(read).sorted(), [], "this test lists a word verify-live.sh no longer reads")
        // And those are all the reads it makes: none is written another way.
        let references = try Harness.references().filter { $0.script == "verify-live.sh" }
        XCTAssertEqual(references.count, verifyReads.count)

        // Each is checked not to be empty, by the one loop that names them all, and a script
        // that cannot read a word does not run.
        let start = try Harness.first("for name in ", in: lines)
        var list = ""
        var at = start
        while at < lines.count {
            list += lines[at].replacingOccurrences(of: "\\", with: " ").replacingOccurrences(of: ";", with: " ") + " "
            if lines[at].contains("; do") { break }
            at += 1
        }
        let named = Set(list.split(whereSeparator: { $0 == " " }).map(String.init).filter {
            $0.range(of: #"^[A-Z][A-Z0-9_]*$"#, options: .regularExpression) != nil
        })
        XCTAssertEqual(named, Set(verifyReads.map(\.variable)), "the loop that refuses an empty word does not name each word read")
        let check = try Harness.first(#"if [ -z "${!name}" ]; then UNREAD="$UNREAD $name"; fi"#, in: lines, after: at)
        let refuse = try Harness.first(#"if [ -n "$UNREAD" ]; then"#, in: lines, after: check)
        XCTAssertTrue(lines[refuse...(refuse + 3)].contains { $0.contains("exit 2") }, "a word that cannot be read does not stop the run")

        // And each is used: a word read and never looked for would be a read nothing needs.
        for entry in verifyReads {
            let use = try NSRegularExpression(pattern: #"\$\{?\#(entry.variable)(?![A-Z0-9_])"#)
            XCTAssertNotNil(use.firstMatch(in: code, range: NSRange(code.startIndex..., in: code)),
                            "verify-live.sh reads \(entry.variable) and never uses it")
        }
    }

    /// The cause reading steps over the On Call item and the setup line, and the setup line is
    /// found by the stem the core declares (the plan's Task 8 note on the nudge).
    func testTheCauseReadingStepsOverTheOnCallItemAndTheSetupLine() throws {
        let verify = try Harness.script("verify-live.sh")
        let body = try Harness.body(of: "health_and_cause", in: verify)
        XCTAssertTrue(body.contains { $0.contains(#"[ "$line" != "$ON_CALL_ITEM" ]"#) },
                      "health_and_cause does not step over the On Call item, and would take it for the health line's cause")
        XCTAssertTrue(body.contains { $0.contains(#""$NUDGE_STEM"*) ;;"#) },
                      "health_and_cause does not step over the setup line, and would take it for the health line's cause")
        // The setup line comes after the cause and before the On Call item, and the check that
        // none is on the menu looks for the same stem.
        let code = Harness.codeLines(verify).joined(separator: "\n")
        XCTAssertTrue(code.contains(#"menu_has_stem "$MENU" "$NUDGE_STEM""#), "the default run does not check that no setup line is on the menu")
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
            ("Captured", "grep -o 'Captured [0-9]*' <<< \"$1\""),
            ("Could not play", #"grep -qF -e "Could not play: " -e "x""#),
            ("Rules", #"grep -E "Rules: [0-9]+" <<< "$MENU""#),
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
            ("Captured", #"grep -o "$CAPTURED_STEM [0-9]*" <<< "$1""#),
            ("Rules", #"grep -E "^[^A-Za-z]*$RULES_STEM" <<< "$1" | head -1"#),
            ("Rules", #"note "the rules file has a problem — the menu lists it""#),
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

    /// What the harness of the plan's Task 9 looks for, chooses or writes that the core
    /// declares: the marker rule's name, its two ids and the title of its banners, the setup
    /// nudge's stem, the on-call line's stem and the key on-call mode saves, the key a snooze's
    /// end is saved under, the Snooze submenu's 15-minute item, the titles the menu's Acknowledge
    /// item has, the word that ends every line about what is escalating, the on-call check
    /// window's title, the status menu's capture count and the items that open the Inspector,
    /// open the editor and reload the rules, the lines about the last match, the rules, the mute
    /// walkthrough and an alert that failed, and the sentence about muted output. The health
    /// line's five wordings are in their own table below. `verify-live.sh` and
    /// `Scripts/harness-guards.sh` read these through the helper, so each is held to the one
    /// shape the helper's `sed` reads, and no script types the words of its own, which a change
    /// to either would leave behind. A script that reads one is held to it again by the tests
    /// above, whether or not it is listed here.
    private let harnessConstants: [(file: String, name: String, text: String)] = [
        ("HarnessText.swift", "markerRuleName", "SignalLadder harness marker"),
        ("HarnessText.swift", "markerTitle", "SignalLadder harness marker banner"),
        ("HarnessText.swift", "markerEscalationRuleID", "6F0B2A52-6C3F-4C2E-9D7A-0A1B2C3D4F02"),
        ("HarnessText.swift", "markerSnoozeRuleID", "6F0B2A52-6C3F-4C2E-9D7A-0A1B2C3D4F01"),
        ("SetupText.swift", "nudgeStem", "Setup is not finished"),
        ("OnCall.swift", "sinceStem", "On call since"),
        ("OnCall.swift", "storageKey", "onCallSince"),
        ("Snooze.swift", "untilKey", "snoozeUntil"),
        ("SnoozeText.swift", "fifteenMinutesTitle", "For 15 minutes"),
        ("AlertMenuText.swift", "acknowledgeOneTitle", "Acknowledge"),
        ("AlertMenuText.swift", "acknowledgeAllStem", "Acknowledge All"),
        ("AlertMenuText.swift", "escalatingWord", "escalating"),
        ("AlertMenuText.swift", "lastMatchStem", "Last match:"),
        ("AlertMenuText.swift", "outputSilentSentence", "Sound output is muted or at zero volume \u{2014} alerts will not be heard"),
        ("WindowTitles.swift", "onCallCheck", "SignalLadder On-Call Check"),
        ("StatusMenuText.swift", "capturedStem", "Captured"),
        ("StatusMenuText.swift", "showInspectorTitle", "Show Inspector\u{2026}"),
        ("StatusMenuText.swift", "editRulesTitle", "Edit Rules\u{2026}"),
        ("StatusMenuText.swift", "reloadRulesTitle", "Reload Rules"),
        ("RuleSetCodec.swift", "summaryStem", "Rules"),
        ("MuteWalkthrough.swift", "confirmedStem", "Confirmed muted"),
        ("MuteWalkthrough.swift", "notConfirmedStem", "Not confirmed muted"),
        ("InspectorEntry.swift", "couldNotPlay", "Could not play"),
        ("InspectorEntry.swift", "couldNotSpeak", "Could not speak"),
        ("InspectorEntry.swift", "butCouldNotSpeak", ", but could not speak"),
        ("InspectorEntry.swift", "butCouldNotPlay", ", but could not play"),
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

    /// The four stems of a failed alert are typed in a form the scan above cannot tell from a sentence
    /// the script prints, such as `"Could not play: "` in a grep, since the colon and the space follow the
    /// stem inside the quotes. So none of them is found in the code of any script at all, and the
    /// statement that looks for a failed alert is built from the variables the script reads them into.
    func testNoScriptTypesAFailureStemInAnyForm() throws {
        let stems = try ["couldNotPlay", "couldNotSpeak", "butCouldNotSpeak", "butCouldNotPlay"]
            .map { try Harness.declaredText("InspectorEntry.swift", $0) }
        for script in try Harness.scriptNames() {
            let code = Harness.codeLines(try Harness.script(script)).joined(separator: "\n")
            for stem in stems {
                XCTAssertFalse(code.contains(stem), "\(script) has \"\(stem)\" typed into it: read it through the helper")
            }
        }
        let verify = Harness.codeLines(try Harness.script("verify-live.sh")).joined(separator: "\n")
        XCTAssertTrue(verify.contains(#"grep -qF -e "$FAIL_PLAY: " -e "$FAIL_SPEAK: " -e "$FAIL_PLAYED_NOT_SPOKEN: " -e "$FAIL_SPOKE_NOT_PLAYED: " <<< "$MENU""#),
                      "verify-live.sh does not look for a failed alert with the four stems it reads")
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

    /// The harness refuses to mark a file that declares a version above the
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

    /// What each `HEALTH_*` variable of the script holds: the text of the `HealthTitle` constant
    /// the script reads it from, through the helper.
    private func healthVariables() throws -> [String: String] {
        let code = Harness.codeLines(try Harness.script("verify-live.sh")).joined(separator: "\n")
        var found: [String: String] = [:]
        for read in try Harness.assignments(in: code) where read.file == "HealthTitle.swift" {
            found[read.variable] = try Harness.declaredText(read.file, read.name)
        }
        return found
    }

    /// The patterns in the part of a `case` arm that stands before its `)`. Each is the
    /// variable of a wording, quoted, `"$HEALTH_VERIFIED"` for the whole line or
    /// `"$HEALTH_VERIFIED"*` for a prefix, as `case` reads them, and it is resolved to the
    /// text of the constant the variable is read from. Nothing is typed there: a pattern
    /// that is a wording written out fails, and so does one that names a variable the
    /// script does not read from `HealthTitle`. The empty pattern and `*` name no wording.
    private func healthPatterns(in part: String, variables: [String: String]) throws -> [(text: String, isPrefix: Bool)] {
        let trimmed = part.trimmingCharacters(in: .whitespaces)
        if trimmed == "\"\"" || trimmed == "*" { return [] }
        let token = try NSRegularExpression(pattern: #""\$([A-Z][A-Z0-9_]*)"(\*)?"#)
        let range = NSRange(part.startIndex..., in: part)
        var patterns: [(text: String, isPrefix: Bool)] = []
        for match in token.matches(in: part, range: range) {
            let name = String(part[Range(match.range(at: 1), in: part)!])
            let text = try XCTUnwrap(variables[name], "a case names \(name), which the script does not read from HealthTitle")
            patterns.append((text: text, isPrefix: match.range(at: 2).location != NSNotFound))
        }
        let rest = token.stringByReplacingMatches(in: part, range: range, withTemplate: "")
            .filter { !"| \t".contains($0) }
        XCTAssertEqual(rest, "", "`\(trimmed)` has a pattern that is typed and not read through the helper")
        return patterns
    }

    /// The wordings the script takes for a health line: the patterns on the arms of
    /// `is_health_line`'s `case`, each exact or, with a trailing `*`, a prefix, as `case`
    /// reads them, resolved to the constants they are read from.
    private func healthPatterns() throws -> [(text: String, isPrefix: Bool)] {
        let variables = try healthVariables()
        let body = try Harness.body(of: "is_health_line", in: try Harness.script("verify-live.sh"))
        let arms = body.filter { $0.contains(") return 0") }
        XCTAssertFalse(arms.isEmpty, "is_health_line accepts no wording")
        var patterns: [(text: String, isPrefix: Bool)] = []
        for arm in arms {
            let part = String(arm[..<arm.range(of: ") return 0")!.lowerBound])
            patterns += try healthPatterns(in: part, variables: variables)
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
            HealthTitle.text(for: .degraded([.bannersUnreadable]), secondsSinceLastSuccessfulCanary: 60),
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
            HealthCause.bannersUnreadable.advice,
        ]
        for line in others {
            XCTAssertFalse(recognised(line, by: patterns), "\"\(line)\" would be taken for the health line")
        }
    }

    // MARK: - The health line's wordings, declared

    /// The wordings of the health line, each declared on one line in the shape the
    /// helper reads, and the variable of `verify-live.sh` that holds it. The script reads
    /// all five through the helper and types none: the arms of `is_health_line` and of
    /// each `case "$HEALTH"` are these variables, which the tests above and below resolve
    /// to the constants and hold to what `HealthTitle` gives, and the last of them holds
    /// that no script types one.
    private let healthConstants: [(name: String, text: String, variable: String)] = [
        ("verifiedStem", "Working \u{2014} verified", "HEALTH_VERIFIED"),
        ("checkingLine", "Checking\u{2026}", "HEALTH_CHECKING"),
        ("unverifiedStem", "Unverified", "HEALTH_UNVERIFIED"),
        ("cannotVerifyLine", "Cannot verify itself", "HEALTH_CANNOT_VERIFY"),
        ("notCapturingLine", "NOT capturing notifications", "HEALTH_NOT_CAPTURING"),
        ("someBannersUnreadLine", "Could not read some banners", "HEALTH_SOME_UNREAD"),
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

    /// The script reads each of the five through the helper, into the variable that is its name
    /// here and nowhere else, so that a wording of the health line cannot change in the app and
    /// be left behind in the script (Ruling 18).
    func testTheScriptReadsEachWordingOfTheHealthLineFromHealthTitleAndTypesNone() throws {
        let variables = try healthVariables()
        XCTAssertEqual(variables, Dictionary(uniqueKeysWithValues: healthConstants.map { ($0.variable, $0.text) }),
                       "verify-live.sh does not read the five wordings of the health line into HEALTH_* variables")
        let code = Harness.codeLines(try Harness.script("verify-live.sh")).joined(separator: "\n")
        for constant in healthConstants {
            XCTAssertTrue(code.contains("\(constant.variable)=$(\(Harness.helper) HealthTitle.swift \(constant.name))"),
                          "\(constant.variable) is not read from HealthTitle's \(constant.name)")
        }
        // The wordings is_health_line takes are the five, the two stems as prefixes and the
        // others exact, whichever arm each is on.
        let patterns = try healthPatterns()
        XCTAssertEqual(Set(patterns.map(\.text)), Set(healthConstants.map(\.text)),
                       "is_health_line takes \(patterns.map(\.text).sorted())")
        XCTAssertEqual(patterns.count, healthConstants.count, "is_health_line names a wording twice")
        for pattern in patterns {
            XCTAssertEqual(pattern.isPrefix, healthConstants.first { $0.text == pattern.text }?.name.hasSuffix("Stem"),
                           "is_health_line takes \"\(pattern.text)\" as " + (pattern.isPrefix ? "a prefix, and the line is exact" : "the whole line, and it has an age after it"))
        }
    }

    func testNoScriptTypesTheWordingsOfTheHealthLine() throws {
        for script in try Harness.scriptNames() {
            let code = Harness.codeLines(try Harness.script(script))
            for constant in healthConstants {
                let typed = try code.contains { try Harness.typesAsLookup(constant.text, in: $0) }
                XCTAssertFalse(typed, "\(script) has \"\(constant.text)\" typed into it: read \(constant.name) through the helper")
            }
        }
    }

    /// The patterns on the arms of each `case "$HEALTH" in` in the script, a block to an
    /// array: the one that gives the verdict, and the one that decides whether a live
    /// capture can contradict the health line. An arm's pattern is what stands before the
    /// first `)` that no quote encloses, read as `is_health_line`'s are, and resolved to the
    /// constants the variables are read from.
    private func healthCaseBlocks() throws -> [[(text: String, isPrefix: Bool)]] {
        let lines = try Harness.script("verify-live.sh").components(separatedBy: "\n")
        let variables = try healthVariables()
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
                block += try healthPatterns(in: part, variables: variables)
            }
            blocks.append(block)
        }
        return blocks
    }

    /// The script's `case "$HEALTH"` blocks are held as `is_health_line`'s arms are: every
    /// wording is one `HealthTitle` declares, read through the helper, the two stems are
    /// patterns that end in `*` (the age follows them) and the other three are exact, and the
    /// block that gives the verdict names all five, so that a line the app can give is never
    /// "unrecognised". A block that decides something else need not name them all.
    func testTheWordingsTheScriptReadsInItsCasesOnTheHealthLineAreTheOnesHealthTitleDeclares() throws {
        let declared = Set(healthConstants.map(\.text))
        let stems = Set(healthConstants.filter { $0.name.hasSuffix("Stem") }.map(\.text))
        XCTAssertEqual(stems.count, 2, "two of the wordings are stems, which an age follows")
        let blocks = try healthCaseBlocks()
        XCTAssertFalse(blocks.isEmpty, "verify-live.sh has no case on $HEALTH, so nothing here is held")
        for block in blocks {
            for pattern in block {
                XCTAssertTrue(declared.contains(pattern.text),
                              "a case on $HEALTH reads \"\(pattern.text)\", which HealthTitle does not declare")
                XCTAssertEqual(pattern.isPrefix, stems.contains(pattern.text),
                               "a case on $HEALTH takes \"\(pattern.text)\" "
                                   + (pattern.isPrefix ? "as a prefix, and the line is exact" : "exactly, and the line has an age after it"))
            }
        }
        XCTAssertTrue(blocks.contains { Set($0.map(\.text)) == declared },
                      "no case on $HEALTH names all of \(declared.sorted()), so a health line the app gives could be unrecognised")
    }

    // MARK: - The lines the app builds from the words the harness reads (M5 plan, Task 9)

    /// The capture count's line is the stem, a space and the number, which is how the script
    /// reads the number out of it, and it is built from the constant.
    func testTheCaptureCountsLineBeginsWithTheStemAndTheNumberTheScriptReads() throws {
        let stem = try Harness.declaredText("StatusMenuText.swift", "capturedStem")
        XCTAssertEqual(StatusMenuText.capturedLine(count: 0), "Captured 0 notifications")
        XCTAssertEqual(StatusMenuText.capturedLine(count: 1), "Captured 1 notification")
        XCTAssertEqual(StatusMenuText.capturedLine(count: 212), "Captured 212 notifications")
        for count in [0, 1, 2, 9, 212, 4_000] {
            let line = StatusMenuText.capturedLine(count: count)
            let read = line.range(of: "\(stem) [0-9]*", options: .regularExpression).map { String(line[$0]) }
            XCTAssertEqual(read, "\(stem) \(count)", line)
        }
    }

    /// The app target builds the status menu's items from the constants, and types none of the words
    /// (`ViewLiteralsTests` refuses a literal typed back; this holds that the constant is what is used).
    func testTheStatusMenuIsBuiltFromTheTitlesTheHarnessReads() throws {
        let source = try XCTUnwrap(AppSources.read("AppDelegate.swift"), "AppDelegate.swift is gone")
        for use in ["menu.addItem(withTitle: StatusMenuText.capturedLine(count: count),",
                    "NSMenuItem(title: StatusMenuText.showInspectorTitle,",
                    "NSMenuItem(title: StatusMenuText.editRulesTitle,",
                    "NSMenuItem(title: StatusMenuText.reloadRulesTitle,"] {
            XCTAssertTrue(source.contains(use), "AppDelegate.swift does not build its item with `\(use)`")
        }
    }

    /// The script finds the rules line by the stem after any warning mark, and the capture count's line by
    /// its stem, so no other title of the menu may begin with either. The titles of the items the harness
    /// chooses are distinct, since it chooses each by its title.
    func testNoOtherTitleOfTheMenuBeginsWithTheRulesStemOrTheCapturedStem() throws {
        let rules = try Harness.declaredText("RuleSetCodec.swift", "summaryStem")
        let captured = try Harness.declaredText("StatusMenuText.swift", "capturedStem")
        let others = [StatusMenuText.showInspectorTitle, StatusMenuText.editRulesTitle, StatusMenuText.reloadRulesTitle,
                      SetupText.rulesFileMenuTitle, SettingsText.menuTitle, OnCallText.menuTitle, OnCallText.checkItemTitle,
                      SnoozeText.menuTitle, SnoozeText.dismissTitle, "Current rules match 2 of the last 50", "Quit SignalLadder",
                      AlertMenuText.acknowledgeOneTitle, AlertMenuText.lastMatchStem, HealthTitle.verifiedStem]
        for title in others {
            XCTAssertFalse(title.hasPrefix(rules), "\"\(title)\" would be taken for the rules line")
            XCTAssertFalse(title.hasPrefix(captured), "\"\(title)\" would be taken for the capture count's line")
        }
        let chosen = [StatusMenuText.showInspectorTitle, StatusMenuText.editRulesTitle, StatusMenuText.reloadRulesTitle,
                      SettingsText.menuTitle, OnCallText.menuTitle, SnoozeText.menuTitle, SnoozeText.fifteenMinutesTitle,
                      SnoozeText.endTitle, SnoozeText.dismissTitle, AlertMenuText.acknowledgeOneTitle]
        XCTAssertEqual(Set(chosen).count, chosen.count, "two of the titles the harness chooses are the same")
        // Every one of the stems the script puts into a pattern is plain words and a colon, so that
        // none is read as a pattern of its own.
        for stem in [captured, rules, AlertMenuText.lastMatchStem, MuteWalkthroughText.confirmedStem,
                     MuteWalkthroughText.notConfirmedStem] {
            XCTAssertTrue(stem.allSatisfy { $0.isASCII && ($0.isLetter || $0 == " " || $0 == ":") }, "\"\(stem)\" holds a character a grep reads as its own")
        }
    }

    /// The last-match line begins with the stem, after its warning mark when the alert needs attention.
    func testTheLastMatchLineBeginsWithTheStemAfterItsWarningMark() throws {
        let stem = try Harness.declaredText("AlertMenuText.swift", "lastMatchStem")
        func line(_ alert: AlertOutcome) throws -> String {
            let last = CapturePipeline.LastMatch(ruleName: "On-call mentions", at: now, alert: alert)
            let lines = AlertMenuText.lines(lastMatch: last, unresolvedFailure: nil, anyRulePlaysSound: true,
                                            outputSilent: false, time: { _ in "10:42" })
            return try XCTUnwrap(lines.last)
        }
        XCTAssertTrue(try line(.played(sound: "Hero", gainDB: 0, outputSilent: false)).hasPrefix("\(stem) On-call mentions"))
        XCTAssertTrue(try line(.silentByRule).hasPrefix("\(stem) "))
        XCTAssertTrue(try line(.failed("no such sound")).hasPrefix("\u{26A0}\u{FE0E} \(stem) On-call mentions"))
        XCTAssertTrue(try line(.snoozed).hasPrefix("\(stem) "))
    }

    /// Every line about the rules begins with the stem after its warning mark, and the marked ones are
    /// exactly the ones that report a problem, which is how the script tells a healthy load from the rest.
    func testTheRulesLineBeginsWithTheStemAndOnlyAProblemHasAMarkBeforeIt() throws {
        let stem = try Harness.declaredText("RuleSetCodec.swift", "summaryStem")
        let mark = "\u{26A0}\u{FE0E} "
        let problem = RuleSetCodec.Problem(index: 0, name: "Pager", reason: "no alert")
        let statuses: [RuleStoreStatus] = [
            .noRulesFile, .loaded(enabled: 3, disabled: 0), .loaded(enabled: 0, disabled: 2), .loaded(enabled: 2, disabled: 1),
            .loadedWithProblems(enabled: 1, disabled: 0, rejected: [problem]),
            .unreadable("not JSON"), .unsupportedVersion(9),
            .notReloaded(enabled: 2, disabled: 1, because: .unreadable("not JSON")),
            .notReloaded(enabled: 1, disabled: 0, because: .unsupportedVersion(9)),
        ]
        for status in statuses {
            XCTAssertEqual(status.summary.hasPrefix(mark + stem), status.isProblem, status.summary)
            XCTAssertTrue(status.summary.hasPrefix(stem) || status.summary.hasPrefix(mark + stem), status.summary)
            XCTAssertEqual(status.summary.hasPrefix(stem), !status.isProblem, status.summary)
        }
        XCTAssertEqual(RuleStoreStatus.loaded(enabled: 3, disabled: 0).summary, "Rules: 3 active")
    }

    /// The walkthrough's item begins with the confirmed stem, or with a mark and the not-confirmed stem
    /// while an app is outstanding, and the script tells them apart by those.
    func testTheMuteWalkthroughsItemBeginsWithOneOfTheTwoStems() throws {
        let confirmed = try Harness.declaredText("MuteWalkthrough.swift", "confirmedStem")
        let notConfirmed = try Harness.declaredText("MuteWalkthrough.swift", "notConfirmedStem")
        XCTAssertFalse(confirmed.contains(notConfirmed) || notConfirmed.hasPrefix(confirmed), "one stem is taken for the other")
        let title = MuteWalkthroughText.title(apps: ["Example Chat"], checklist: MuteChecklist())
        XCTAssertTrue(title.hasPrefix("\u{26A0}\u{FE0E} \(notConfirmed): "), title)
        let done = MuteWalkthroughText.title(apps: [], checklist: MuteChecklist())
        XCTAssertTrue(done.hasPrefix("\(confirmed): "), done)
    }

    /// Every outcome that says part of an alert did not happen says it as one of the four stems, a colon, a
    /// space and the reason, and no other outcome's line has any of the four.
    func testAnAlertThatFailedSaysSoWithOneOfTheFourStemsAndNoOtherAlertDoes() throws {
        let play = try Harness.declaredText("InspectorEntry.swift", "couldNotPlay")
        let speak = try Harness.declaredText("InspectorEntry.swift", "couldNotSpeak")
        let butSpeak = try Harness.declaredText("InspectorEntry.swift", "butCouldNotSpeak")
        let butPlay = try Harness.declaredText("InspectorEntry.swift", "butCouldNotPlay")
        let reason = "the sound could not be found"
        let failures: [(AlertOutcome, String)] = [
            (.failed(reason), play),
            (.couldNotSpeak(reason), speak),
            (.playedButNotSpoken(sound: "Glass", gainDB: 0, reason: reason, outputSilent: false), butSpeak),
            (.spokeButNotPlayed(text: "x", voice: "Daniel", gainDB: 0, reason: reason, outputSilent: false), butPlay),
            (.playedFallback(sound: "Sosumi", gainDB: 0, reason: reason, couldNotSpeak: false, outputSilent: false), play),
            (.playedFallback(sound: "Sosumi", gainDB: 0, reason: reason, couldNotSpeak: true, outputSilent: false), speak),
        ]
        for (outcome, stem) in failures {
            let line = InspectorRowText.alert(outcome)
            XCTAssertTrue(line.contains("\(stem): \(reason)"), line)
            XCTAssertTrue(outcome.needsAttention, "\(line) does not need attention")
        }
        let stems = [play, speak, butSpeak, butPlay].map { "\($0): " }
        let fine: [AlertOutcome] = [
            .played(sound: "Glass", gainDB: 0, outputSilent: false), .played(sound: "Glass", gainDB: 6, outputSilent: true),
            .spoke(text: "x", voice: "Daniel", gainDB: 0, outputSilent: false),
            .playedAndSpoke(sound: "Glass", soundGainDB: 0, text: "x", voice: "Daniel", speechGainDB: 0, outputSilent: false),
            .silentByRule, .noAlertSet, .snoozed, .joinedEscalation(matchNumber: 2), .alreadySetOff,
        ]
        for outcome in fine {
            let line = InspectorRowText.alert(outcome)
            XCTAssertFalse(stems.contains { line.contains($0) }, "\"\(line)\" is taken for a failed alert")
        }
    }

    /// The marker rules' ids are UUIDs, the two are apart, and they are the ones the fixtures carry, so
    /// the leftover marker the writer's cases use is the leftover marker the script looks for.
    func testTheMarkerRulesIdsAreDistinctUUIDsThatTheFixturesCarry() throws {
        let escalation = try Harness.declaredText("HarnessText.swift", "markerEscalationRuleID")
        let snooze = try Harness.declaredText("HarnessText.swift", "markerSnoozeRuleID")
        XCTAssertEqual(escalation, HarnessText.markerEscalationRuleID)
        XCTAssertEqual(snooze, HarnessText.markerSnoozeRuleID)
        XCTAssertNotEqual(escalation, snooze)
        for id in [escalation, snooze] {
            XCTAssertNotNil(UUID(uuidString: id), "\"\(id)\" is not a UUID")
            XCTAssertEqual(UUID(uuidString: id)?.uuidString, id, "\"\(id)\" is not written as the codec writes an id")
        }
        XCTAssertEqual(try json(try Harness.fixture("marker-rule-escalation.json"))["id"] as? String, escalation)
        XCTAssertEqual(try json(try Harness.fixture("marker-rule-snooze.json"))["id"] as? String, snooze)
    }

    // MARK: - The flags stand on the guards (M5 plan, Task 9)

    /// The code lines of `verify-live.sh`, comments left out.
    private func verifyCode() throws -> [String] {
        Harness.codeLines(try Harness.script("verify-live.sh"))
    }

    /// The statements of a script's code lines, a statement being the lines a trailing backslash joins.
    private func statements(of lines: [String]) -> [String] {
        var found: [String] = []
        var current = ""
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasSuffix("\\") {
                current += String(trimmed.dropLast()) + " "
            } else {
                found.append(current + trimmed)
                current = ""
            }
        }
        return found
    }

    /// The flags of `verify-live.sh` are the three modes the refuse guard knows, one to a run, and
    /// the flag without its dashes is the mode the guard is given.
    func testTheFlagsAreExactlyTheModesTheRefuseGuardKnows() throws {
        let code = try verifyCode()
        let arm = try XCTUnwrap(code.first { $0.contains("--escalation|") }, "verify-live.sh has no arm for its flags")
        let flags = arm.trimmingCharacters(in: CharacterSet(charactersIn: " )")).split(separator: "|").map(String.init)
        XCTAssertEqual(Set(flags), ["--escalation", "--on-call", "--snooze"])
        XCTAssertTrue(code.contains { $0.contains("MODE=${arg#--} ;;") }, "the mode is not the flag without its dashes")

        let guardBody = try Harness.body(of: "harness_refuse_guard", in: try Harness.script("harness-guards.sh"))
        let known = try XCTUnwrap(guardBody.first { $0.contains("on-call|snooze|escalation)") }, "the refuse guard names no modes")
        let modes = known.trimmingCharacters(in: .whitespaces).components(separatedBy: ")")[0].split(separator: "|").map(String.init)
        XCTAssertEqual(Set(modes), Set(flags.map { String($0.dropFirst(2)) }), "a flag is not a mode the refuse guard knows, or the reverse")

        let joined = code.joined(separator: "\n")
        XCTAssertTrue(joined.contains("Only one flag to a run"), "more than one flag to a run is not refused")
        XCTAssertTrue(joined.contains("Unknown argument"), "an unknown argument is not refused")
    }

    /// Each flag's run begins, before any other check and before anything is written, with the backup
    /// guard, which says what it did and refuses (exit 2) to go on over a file it must not touch, and
    /// sets its traps after the guard and before the first write.
    func testEachFlagBeginsWithTheBackupGuardAndSetsItsTrapsBeforeAnythingIsWritten() throws {
        let verify = try Harness.script("verify-live.sh")
        let begin = try Harness.body(of: "begin_flag", in: verify)
        let guardAt = try Harness.first(#"out=$(harness_backup_guard "$RULES_FILE" "$BACKUP"); rc=$?"#, in: begin, "begin_flag")
        let refuseAt = try Harness.first("exit 2", in: begin, after: guardAt, "begin_flag")
        XCTAssertTrue(begin[guardAt..<refuseAt].contains { $0.contains(#"[ "$rc" -ne 0 ]"#) }, "the guard's refusal does not stop the run")
        let says = try Harness.first(#"ok "$out""#, in: begin, after: refuseAt, "begin_flag")
        XCTAssertTrue(begin[says...].contains { $0.contains("no backup of the rules file was left") }, "the guard says nothing when it finds nothing")
        let signals = try ["trap 'on_signal 129' HUP", "trap 'on_signal 130' INT", "trap 'on_signal 143' TERM", "trap on_exit EXIT"]
            .map { try Harness.first($0, in: begin, after: says, "begin_flag") }
        let digest = try Harness.first("RULES_DIGEST_START=$(rules_digest)", in: begin, after: signals.max()!, "begin_flag")
        XCTAssertGreaterThan(digest, signals.max()!)

        // It is called before anything else is done, for every flag, and every run of a flag comes after it.
        let outside = try Harness.linesOutsideFunctions(in: verify)
        let call = try Harness.first(#"begin_flag "$MODE""#, in: outside)
        XCTAssertEqual(outside[call - 1], #"if [ -n "$MODE" ]; then"#)
        XCTAssertLessThan(call, try Harness.first(#"head_ "Process""#, in: outside), "a check is made before the flag's guard has run")
        for run in ["run_escalation", "run_on_call", "run_snooze"] {
            XCTAssertLessThan(call, try Harness.first("\(run) ;;", in: outside), "\(run) is called before the traps are set")
        }
        let before = outside[..<call].joined(separator: "\n")
        for write in ["choose_menu_item", "choose_submenu_item", "post_marker_banner", "install_marker", "reload_rules",
                      "osascript", "defaults ", "harness_install_marker", "harness_backup_guard"] {
            XCTAssertFalse(before.contains(write), "\(write) is used before the backup guard has run and the traps are set")
        }
    }

    /// The refuse guard runs on a menu read afresh, before anything a flag does, and a refusal is exit 2.
    func testEachFlagRunsTheRefuseGuardOnAFreshMenuBeforeItActs() throws {
        let verify = try Harness.script("verify-live.sh")
        let refuse = try Harness.body(of: "refuse_or_go", in: verify)
        let read = try Harness.first("menu=$(read_menu_retry)", in: refuse, "refuse_or_go")
        let judged = try Harness.first(#"refuse_on_shift "$menu""#, in: refuse, after: read, "refuse_or_go")
        // And the state it finds the Mac in is kept, to tell what the run leaves from what it found.
        XCTAssertTrue(refuse[judged...].contains { $0.contains("START_SNOOZED=1") })
        XCTAssertTrue(refuse[judged...].contains { $0.contains("START_ON_CALL=1") })

        let judge = try Harness.body(of: "refuse_on_shift", in: verify)
        let guardAt = try Harness.first(#"why=$(harness_refuse_guard "$MODE" "$1"); rc=$?"#, in: judge, "refuse_on_shift")
        let stops = try Harness.first("exit 2", in: judge, after: guardAt, "refuse_on_shift")
        XCTAssertTrue(judge[guardAt..<stops].contains { $0.contains(#"[ "$rc" -ne 0 ]"#) })

        for run in ["run_escalation", "run_on_call", "run_snooze"] {
            let body = try Harness.body(of: run, in: verify)
            let guardCall = try Harness.first("refuse_or_go", in: body, after: 1, run)
            XCTAssertTrue(body[1..<guardCall].allSatisfy { $0.trimmingCharacters(in: .whitespaces).hasPrefix("local ") },
                          "\(run) does something before it has run the refuse guard")
            for action in ["install_marker", "choose_menu_item", "choose_submenu_item", "post_marker_banner", "reload_rules",
                           "load_marker", "end_snooze_if_running", "switch_on_call_off_if_on", "RULES_TOUCHED=1",
                           "ON_CALL_SWITCHED=1", "SNOOZE_STARTED=1", "MARKER_POSTED=1"] {
                for (index, line) in body.enumerated() where line.contains(action) {
                    XCTAssertGreaterThan(index, guardCall, "\(run) has `\(action)` before the refuse guard")
                }
            }
        }
    }

    /// The refuse guard also runs on the menu the run first reads, before the default checks post a
    /// banner or open a window, so that a flag run on a Mac that belongs to a real shift is refused
    /// before the run has done anything to it; and what the run says of the menu is what the menu showed.
    func testAFlagIsRefusedOnTheMenuTheRunFirstReadsBeforeTheDefaultChecksDoAnything() throws {
        let verify = try Harness.script("verify-live.sh")
        let outside = try Harness.linesOutsideFunctions(in: verify)
        let read = try Harness.first("MENU=$(read_menu)", in: outside)
        let refuse = try Harness.first(#"refuse_on_shift "$MENU""#, in: outside, after: read)
        XCTAssertEqual(outside[refuse - 1], #"if [ -n "$MODE" ]; then"#, "the early refusal is not for the flags")
        XCTAssertEqual(outside[refuse + 1], "fi")
        // After the menu is known to be readable, and before the first check that posts or opens anything.
        XCTAssertGreaterThan(refuse, try Harness.first(#"if [ -z "$MENU" ]; then"#, in: outside, after: read))
        XCTAssertLessThan(refuse, try Harness.first(#"head_ "Alerts""#, in: outside))
        XCTAssertLessThan(refuse, try Harness.first(#"head_ "Live capture""#, in: outside))
        let before = outside[..<refuse].joined(separator: "\n")
        for action in ["display notification", "post_marker_banner", "open_and_close_window", "install_marker", "choose_menu_item"] {
            XCTAssertFalse(before.contains(action), "`\(action)` comes before the refuse guard has run on the first read of the menu")
        }
        // The run reads the menu again before it acts: the guard is not left to the first read.
        for run in ["run_escalation", "run_on_call", "run_snooze"] {
            XCTAssertTrue(try Harness.body(of: run, in: verify).contains { $0.trimmingCharacters(in: .whitespaces) == "refuse_or_go" })
        }

        // The line it prints that nothing belongs to a real shift is printed only when neither a snooze
        // nor on-call mode was found: --escalation goes on beside either, and says which it found.
        let judge = try Harness.body(of: "refuse_on_shift", in: verify)
        let onCall = try Harness.first(#"if menu_has_stem "$1" "$ON_CALL_SINCE_STEM"; then"#, in: judge, "refuse_on_shift")
        let snoozed = try Harness.first(#"if menu_has_stem "$1" "$SNOOZE_ACTIVE_STEM"; then"#, in: judge, after: onCall, "refuse_on_shift")
        let nothing = try Harness.first(#"if [ "$found" -eq 0 ]; then"#, in: judge, after: snoozed, "refuse_on_shift")
        for (what, found) in [("on-call mode", judge[onCall..<snoozed]), ("a snooze", judge[snoozed..<nothing])] {
            XCTAssertTrue(found.contains { $0.contains("note ") }, "\(what), found, is not said")
            XCTAssertTrue(found.contains { $0.contains("found=1") }, "\(what), found, does not count against the line that nothing was found")
        }
        let nothingLines = judge.indices.filter { judge[$0].contains(#"ok "the menu shows nothing that belongs to a real shift"#) }
        XCTAssertEqual(nothingLines.count, 1, "the line is printed from more than one place")
        XCTAssertGreaterThan(nothingLines.first ?? 0, nothing, "the line is printed whatever the menu showed")
    }

    /// A held summary already on the menu is a refusal for --snooze, found by its Dismiss item, which the
    /// menu has exactly when it has the summary; and the check that the marker's match was held is the
    /// summary guard's, on the marker's one match, and not a stem every held match has.
    func testSnoozeRefusesAHeldSummaryAndChecksTheMarkersOwnMatchWasHeld() throws {
        let verify = try Harness.script("verify-live.sh")
        let judge = try Harness.body(of: "refuse_on_shift", in: verify)
        let guardAt = try Harness.first(#"harness_refuse_guard "$MODE" "$1""#, in: judge)
        let summary = try Harness.first(#"if [ "$MODE" = snooze ] && menu_has_item "$1" "$DISMISS_ITEM"; then"#, in: judge, after: guardAt, "refuse_on_shift")
        let stops = try Harness.first("exit 2", in: judge, after: summary, "refuse_on_shift")
        XCTAssertTrue(judge[summary..<stops].contains { $0.contains("bad ") }, "a held summary is refused with no word said")
        // Before the line that says the Mac is not in a shift, and before anything is found to go on beside.
        XCTAssertLessThan(stops, try Harness.first(#"if menu_has_stem "$1" "$ON_CALL_SINCE_STEM"; then"#, in: judge))
        // The menu has a Dismiss item exactly when it has the summary line.
        for menu in ["held-summary-marker", "held-summary-mixed", "held-summary-other"] {
            XCTAssertTrue(try Harness.menu(menu).contains(SnoozeText.dismissTitle), "\(menu) has no \(SnoozeText.dismissTitle) item")
        }
        for menu in ["quiet", "snoozed", "on-call", "escalating-one", "missed-alone"] {
            XCTAssertFalse(try Harness.menu(menu).contains(SnoozeText.dismissTitle), "\(menu) has a \(SnoozeText.dismissTitle) item")
        }

        let body = try Harness.body(of: "run_snooze", in: verify)
        XCTAssertFalse(body.contains { $0.contains("HELD_STEM") }, "a stem that any held match has is looked for")
        let post = try Harness.first(#"post_marker_banner "Snooze check""#, in: body)
        let poll = try Harness.first(#"if harness_summary_guard "$menu" >/dev/null; then break; fi"#, in: body, after: post)
        let asserted = try Harness.first(#"if harness_summary_guard "$menu" >/dev/null; then"#, in: body, after: poll + 1)
        XCTAssertTrue(body[asserted...].prefix(4).contains { $0.contains("ok ") && $0.contains("one match was held") })
        let failed = try Harness.first("bad ", in: body, after: asserted)
        XCTAssertTrue(body[failed].contains("one match held while snoozed"))
        XCTAssertLessThan(asserted, try Harness.first("end_snooze_if_running", in: body, after: post), "the snooze ends before the check")
    }

    /// The state that tells the undoing what a step started is recorded before the step, so a run
    /// interrupted in the middle of a step is undone as though it had finished it.
    func testEachStepIsRecordedBeforeItIsTaken() throws {
        let verify = try Harness.script("verify-live.sh")
        func order(_ function: String, _ earlier: [String], before later: String) throws {
            let body = try Harness.body(of: function, in: verify)
            let step = try Harness.first(later, in: body, function)
            for record in earlier {
                XCTAssertLessThan(try Harness.first(record, in: body, function), step, "\(function) takes `\(later)` before `\(record)`")
            }
        }
        try order("install_marker", ["RULES_TOUCHED=1"], before: "harness_install_marker")
        try order("run_on_call", ["RULES_WATCHED=1", "ON_CALL_SWITCHED=1"], before: #"choose_menu_item "$ON_CALL_ITEM""#)
        try order("run_snooze", ["SNOOZE_STARTED=1"], before: #"choose_submenu_item "$SNOOZE_ITEM" "$SNOOZE_FIFTEEN_ITEM""#)
        try order("run_snooze", ["MARKER_POSTED=1", "MARKER_SUMMARY=pending"], before: "post_marker_banner")
        try order("run_escalation", ["MARKER_POSTED=1", "ESCALATION_OPEN=1"], before: "post_marker_banner")
    }

    /// Everything that changes the Mac is done from one place each, and every place is a step that is
    /// recorded or undone, so nothing is changed that the undoing does not know of.
    func testEachChangeToTheMacIsMadeFromTheOnePlaceThatRecordsOrUndoesIt() throws {
        let verify = try Harness.script("verify-live.sh")
        let all = try Harness.functions(in: verify)
        func callers(of needle: String) -> Set<String> {
            // A function written on one line is read by `functions(in:)` to the next closing brace, which
            // is not its end, so it is left out; none of the changes is made from one.
            Set(all.filter { function in
                !(function.body.components(separatedBy: "\n").first?.hasSuffix("}") ?? false)
                    && Harness.codeLines(function.body).dropFirst().contains { $0.contains(needle) }
            }.map(\.name))
        }
        XCTAssertEqual(callers(of: "harness_install_marker"), ["install_marker"])
        XCTAssertEqual(callers(of: "install_marker escalation"), ["run_escalation"])
        XCTAssertEqual(callers(of: "install_marker snooze"), ["run_snooze"])
        XCTAssertEqual(callers(of: #"choose_menu_item "$ON_CALL_ITEM""#), ["run_on_call", "switch_on_call_off_if_on"])
        XCTAssertEqual(callers(of: #"choose_submenu_item "$SNOOZE_ITEM" "$SNOOZE_FIFTEEN_ITEM""#), ["run_snooze"])
        XCTAssertEqual(callers(of: #"choose_submenu_item "$SNOOZE_ITEM" "$SNOOZE_END_ITEM""#), ["end_snooze_if_running"])
        XCTAssertEqual(callers(of: #"choose_menu_item "$ACKNOWLEDGE_ITEM""#), ["run_escalation"])
        XCTAssertEqual(callers(of: #"choose_menu_item "$DISMISS_ITEM""#), ["dismiss_marker_summary"])
        XCTAssertEqual(callers(of: "post_marker_banner "), ["run_escalation", "run_snooze"])
        XCTAssertEqual(callers(of: "reload_rules"), ["cleanup_run", "load_marker"])
        XCTAssertEqual(callers(of: #"choose_menu_item "$RELOAD_RULES_ITEM""#), ["reload_rules"])
        // The rules file itself is written by the writer and put back by the guard, and nowhere else.
        let code = try verifyCode().joined(separator: "\n")
        XCTAssertFalse(code.contains("> \"$RULES_FILE\""), "verify-live.sh writes to the rules file itself")
        XCTAssertNil(code.range(of: #"\b(rm|mv|cp|tee)\b[^\n]*RULES_FILE"#, options: .regularExpression),
                     "verify-live.sh removes, moves, copies or writes the rules file itself")
        // Outside a function, the only call of any of these is the owed reload.
        let outside = try Harness.linesOutsideFunctions(in: try Harness.script("verify-live.sh")).joined(separator: "\n")
        for change in ["choose_menu_item", "choose_submenu_item", "post_marker_banner", "install_marker"] {
            XCTAssertFalse(outside.contains(change), "\(change) is used outside a function")
        }
    }

    /// The restore checks the digest, and the undoing is in the order each step needs: the snooze, then
    /// the held summary while the marker rule still names it, then on-call mode and its window, then
    /// rules.json, put back by the guard, which puts back only a file that still has the digest recorded,
    /// read again, and compared byte for byte with the file the run began with. The same code runs when
    /// the run ends normally, on INT, TERM and HUP and when it exits any other way.
    func testTheCleanupUndoesWhatTheRunStartedInOrderAndChecksTheRestoreByDigest() throws {
        let verify = try Harness.script("verify-live.sh")
        let cleanup = try Harness.body(of: "cleanup_run", in: verify)
        func at(_ needle: String, after: Int = 0) throws -> Int { try Harness.first(needle, in: cleanup, after: after, "cleanup_run") }
        let ignore = try at("trap '' INT TERM HUP PIPE")
        let snooze = try at("end_snooze_if_running", after: ignore)
        let summary = try at("dismiss_marker_summary", after: snooze)
        let onCall = try at("switch_on_call_off_if_on", after: summary)
        let window = try at("close_check_window_if_run_opened", after: onCall)
        let restore = try at(#"harness_backup_guard "$RULES_FILE" "$BACKUP""#, after: window)
        let reload = try at("reload_rules", after: restore)
        let digest = try at(#"[ "$out" = "$RULES_DIGEST_START" ]"#, after: reload)
        let menu = try at("if menu=$(read_menu_retry); then", after: digest)
        for needle in ["SNOOZE_ACTIVE_STEM", "ON_CALL_SINCE_STEM", "START_SNOOZED", "START_ON_CALL"] {
            XCTAssertTrue(cleanup[menu...].contains { $0.contains(needle) }, "the last check of the menu does not use \(needle)")
        }
        XCTAssertTrue(cleanup[restore..<reload].contains { $0.contains("bad ") }, "a guard that did not restore does not fail the run")
        // The backup it puts back is the run's own, and the guard is told so, to say so.
        XCTAssertTrue(cleanup[restore].contains(#""$BACKUP" "this run")"#), "the cleanup's guard calls the run's own backup an earlier run's")
        XCTAssertTrue(cleanup[digest..<(digest + 4)].contains { $0.contains("bad ") && $0.contains("RULES_DIGEST_START") },
                      "a file that is not the one the run began with does not fail the run")
        let compared = try at("out=$(rules_digest)", after: reload)
        XCTAssertTrue(cleanup[compared - 1].contains("RULES_TOUCHED") && cleanup[compared - 1].contains("RULES_WATCHED"),
                      "a flag that writes nothing is not checked against the digest")

        // The restore runs on a normal exit, and on every other exit, through the same function,
        // once; and the signals end the run through an exit, which runs it.
        let finish = try Harness.body(of: "finish", in: verify)
        XCTAssertLessThan(try Harness.first("cleanup_run", in: finish, "finish"), try Harness.first(#"head_ "Result""#, in: finish, "finish"))
        XCTAssertTrue(try Harness.body(of: "on_exit", in: verify).contains { $0.contains("cleanup_run") })
        XCTAssertTrue(try Harness.body(of: "on_signal", in: verify).contains { $0.contains(#"exit "$1""#) })
        XCTAssertEqual(cleanup[1...3].filter { $0.contains(#"[ "$CLEANED" -eq 0 ] || return 0"#) }.count, 1)
        XCTAssertTrue(cleanup.contains { $0.contains("CLEANED=1") })

        // The signals are ignored BEFORE the run is marked as undone, and only after the return for a run
        // that changed nothing. A signal between the two would run on_signal, whose exit runs this again,
        // and this would return at once, as undone, having undone nothing.
        let nothingToUndo = try at("return 0", after: 3)
        let marked = try at("CLEANED=1")
        XCTAssertLessThan(nothingToUndo, ignore, "a run that changed nothing is not left with its signals ignored")
        XCTAssertLessThan(ignore, marked, "the run is marked as undone before the signals are ignored")
        XCTAssertEqual(cleanup.filter { $0.contains("CLEANED=1") }.count, 1, "the run is marked as undone from more than one place")
        XCTAssertLessThan(marked, try at(#"head_ "Putting back what the run changed""#), "the run is marked as undone after the undoing has begun")
        // And the EXIT trap that calls it ignores them first, so that a signal that arrives as it begins
        // cannot end it, through a trap that exits, before the run is undone.
        let onExit = try Harness.body(of: "on_exit", in: verify)
        XCTAssertLessThan(try Harness.first("trap '' INT TERM HUP PIPE", in: onExit, "on_exit"), try Harness.first("cleanup_run", in: onExit, "on_exit"))

        // What the run did not start is not undone: each undoing reads the menu first.
        let end = try Harness.body(of: "end_snooze_if_running", in: verify)
        XCTAssertLessThan(try Harness.first("read_menu_retry", in: end), try Harness.first(#"choose_submenu_item "$SNOOZE_ITEM" "$SNOOZE_END_ITEM""#, in: end))
        XCTAssertTrue(end.contains { $0.contains(#"if menu_has_stem "$menu" "$SNOOZE_ACTIVE_STEM"; then"#) })
        // The window is closed only when it was not open as the run began.
        let closeWindow = try Harness.body(of: "close_check_window_if_run_opened", in: verify)
        XCTAssertTrue(closeWindow.contains { $0.contains(#"[ "$CHECK_WINDOW_AT_START" -eq 0 ] || return 0"#) })
        XCTAssertTrue(closeWindow.contains { $0.contains("ON_CALL_CHECK_TITLE") })
    }

    /// The On Call item is one item for both directions, so it is chosen to switch the mode off only
    /// after the menu has shown that the mode is on, and never on a menu that could not be read.
    func testOnCallIsChosenToSwitchItOffOnlyAfterTheMenuHasShownItIsOn() throws {
        let verify = try Harness.script("verify-live.sh")
        let body = try Harness.body(of: "switch_on_call_off_if_on", in: verify)
        let read = try Harness.first("read_menu_retry", in: body)
        let giveUp = try Harness.first("return 1", in: body, after: read)
        let shown = try Harness.first(#"if menu_has_stem "$menu" "$ON_CALL_SINCE_STEM"; then"#, in: body, after: giveUp)
        let click = try Harness.first(#"choose_menu_item "$ON_CALL_ITEM""#, in: body, after: shown)
        XCTAssertLessThan(read, giveUp)
        XCTAssertLessThan(shown, click)
        XCTAssertTrue(body[shown..<click].allSatisfy { !$0.contains("else") }, "the click is not under the check that the mode is on")
        XCTAssertTrue(body[click...].contains { $0.contains("else") }, "a menu that does not show the mode on is not left alone")
        let code = try verifyCode().joined(separator: "\n")
        XCTAssertEqual(code.components(separatedBy: #"choose_menu_item "$ON_CALL_ITEM""#).count - 1, 2,
                       "On Call is chosen once to switch on and once to switch off")
    }

    /// Acknowledge is clicked once, by its exact title, and only after the marker-only guard has passed
    /// for the count the run asserted a moment before; with no count asserted, or a guard that fails,
    /// the run touches nothing and says the marker's row stays until it is acknowledged by hand.
    func testAcknowledgeIsClickedOnlyAfterTheMarkerOnlyGuardPassesForTheCountThatWasAsserted() throws {
        let verify = try Harness.script("verify-live.sh")
        let body = try Harness.body(of: "run_escalation", in: verify)
        let found = try Harness.first(#"if harness_marker_only_guard "$n" "$menu" >/dev/null; then found=$n; break; fi"#, in: body)
        let noCount = try Harness.first(#"if [ -z "$found" ]; then"#, in: body, after: found)
        XCTAssertTrue(body[noCount...(noCount + 3)].contains { $0.contains("return 0") }, "no count asserted does not stop the run")
        let fresh = try Harness.first("menu=$(read_menu_retry)", in: body, after: noCount)
        let guardAt = try Harness.first(#"if ! why=$(harness_marker_only_guard "$found" "$menu"); then"#, in: body, after: fresh)
        let giveUp = try Harness.first("return 0", in: body, after: guardAt)
        let click = try Harness.first(#"choose_menu_item "$ACKNOWLEDGE_ITEM""#, in: body, after: giveUp)
        XCTAssertTrue(body[guardAt..<giveUp].contains { $0.contains("bad ") && $0.contains("acknowledge it by hand") },
                      "a guard that fails does not say that the marker's row stays until it is acknowledged by hand")
        XCTAssertTrue(body[noCount..<fresh].contains { $0.contains("acknowledge it by hand") })
        let after = try Harness.first(#"harness_refuse_guard escalation "$menu""#, in: body, after: click)
        XCTAssertGreaterThan(after, click)

        let code = try verifyCode().joined(separator: "\n")
        XCTAssertEqual(code.components(separatedBy: #"choose_menu_item "$ACKNOWLEDGE_ITEM""#).count - 1, 1, "Acknowledge is chosen from more than one place")
        // By its exact title, which the menu gives only while one alert is listed, and never by the stem of the item
        // for several.
        let reads = try Harness.references().filter { $0.script == "verify-live.sh" }
        XCTAssertFalse(reads.contains { $0.name == "acknowledgeAllStem" }, "verify-live.sh reads the stem of Acknowledge All")
        XCTAssertTrue(try Harness.assignments(in: code).contains { $0.variable == "ACKNOWLEDGE_ITEM" && $0.name == "acknowledgeOneTitle" })
    }

    /// The run posts five banners, each with a body of its own, the first and then four more at two
    /// seconds apart, and asserts the menu's count against the banners the log says the harness's own
    /// poster had presented, in the range the check of two banners allows.
    func testTheBurstIsFiveBannersEachWithItsOwnTextCountedAgainstTheLogWithinTheRangeOfTheCheckOfTwo() throws {
        let verify = try Harness.script("verify-live.sh")
        let body = try Harness.body(of: "run_escalation", in: verify)
        let posts = body.filter { $0.contains("post_marker_banner ") }
        XCTAssertEqual(posts.map { $0.trimmingCharacters(in: .whitespaces) },
                       [#"post_marker_banner "Escalation check, banner 1 of 5""#, #"post_marker_banner "Escalation check, banner $i of 5""#])
        // The four more are a loop, and each is posted two seconds after the one before: a sleep of two
        // seconds elsewhere in the function, such as the one after Acknowledge, is not the gap.
        let loop = try Harness.first("for i in 2 3 4 5; do", in: body, "run_escalation")
        let loopEnd = try XCTUnwrap(body.indices.first { $0 > loop && body[$0].trimmingCharacters(in: .whitespaces) == "done" },
                                    "the burst's loop does not end")
        let gap = try Harness.first("sleep 2", in: body, after: loop, "run_escalation")
        let post = try Harness.first("post_marker_banner ", in: body, after: loop, "run_escalation")
        XCTAssertLessThan(gap, loopEnd, "the banners are posted with no gap between them")
        XCTAssertLessThan(gap, post, "a banner of the burst is posted before the gap that comes before it")
        XCTAssertLessThan(post, loopEnd)
        // None of the four more is posted until the marker-only guard has passed on the menu the first
        // banner made, which includes its last match naming the marker rule. The marker is the first rule,
        // so what could still have taken the first banner (a rules file edited during the run, say) is
        // then run once and no more, and the run stops with its reason.
        let firstGuard = try Harness.first(#"if ! why=$(harness_marker_only_guard 1 "$menu"); then"#, in: body, "run_escalation")
        let stop = try Harness.first("return 0", in: body, after: firstGuard, "run_escalation")
        XCTAssertLessThan(stop, loop, "a first banner the guard does not pass does not stop the run before the four more")
        XCTAssertTrue(body[firstGuard..<stop].contains { $0.contains("bad ") && $0.contains("$why") },
                      "a first banner the guard does not pass stops the run without the guard's reason")

        let code = try verifyCode().joined(separator: "\n")
        // The range is the pair check's: up to three seconds ago at least, so far at most.
        XCTAssertTrue(code.contains(#"SETTLED=$(date -v-3S '+%Y-%m-%d %H:%M:%S')"#))
        XCTAssertTrue(body.contains { $0.contains(#"settled=$(date -v-3S '+%Y-%m-%d %H:%M:%S')"#) })
        XCTAssertTrue(body.contains { $0.contains(#"shown_min=$(presented_from_poster_since "$burst_start" "$settled")"#) })
        XCTAssertTrue(body.contains { $0.contains(#"shown_max=$(presented_from_poster_since "$burst_start")"#) })
        XCTAssertTrue(code.contains("POSTER_APP=com.apple.ScriptEditor2"))
        let counted = try Harness.body(of: "presented_from_poster_since", in: verify)
        XCTAssertTrue(counted.contains { $0.contains(#"grep -c "Presenting <NotificationRecord app:\"$POSTER_APP\"""#) })
        // And it is the poster the log check of the test banner reads, matched whatever its case:
        // NotificationCenter names it in lower case on macOS 27.2 (2026-10-13).
        XCTAssertTrue(code.contains(#"grep -iF -- "$POSTER_APP" | grep -c "canDisplayWhileCenterIsClosed: true""#),
                      "the drawn check does not match the poster whatever its case")
        XCTAssertFalse(code.contains(#"grep "$POSTER_APP" | grep -c "canDisplayWhileCenterIsClosed"#),
                       "the drawn check matches the poster's case again")
    }

    /// The summary is dismissed once, only when the summary guard passes, and otherwise left where it is
    /// with the guard's reason said.
    func testTheSummaryIsDismissedOnlyWhenTheSummaryGuardPasses() throws {
        let verify = try Harness.script("verify-live.sh")
        let body = try Harness.body(of: "dismiss_marker_summary", in: verify)
        let guardAt = try Harness.first(#"if why=$(harness_summary_guard "$menu"); then"#, in: body)
        let click = try Harness.first(#"choose_menu_item "$DISMISS_ITEM""#, in: body, after: guardAt)
        let otherwise = try Harness.first("else", in: body, after: click)
        XCTAssertTrue(body[otherwise...].contains { $0.contains(#"note "$why""#) }, "a summary that is not the marker's is left with no word said")
        XCTAssertTrue(body[otherwise...].allSatisfy { !$0.contains("choose_menu_item") })
        let code = try verifyCode().joined(separator: "\n")
        XCTAssertEqual(code.components(separatedBy: #"choose_menu_item "$DISMISS_ITEM""#).count - 1, 1, "Dismiss is chosen from more than one place")
        // The summary is dismissed while the marker rule still names it: before rules.json is put back.
        let cleanup = try Harness.body(of: "cleanup_run", in: verify)
        XCTAssertLessThan(try Harness.first("dismiss_marker_summary", in: cleanup), try Harness.first("harness_backup_guard", in: cleanup))
        let snooze = try Harness.body(of: "run_snooze", in: verify)
        XCTAssertLessThan(try Harness.first("end_snooze_if_running", in: snooze), try Harness.first("dismiss_marker_summary", in: snooze),
                          "the summary is dismissed while the snooze is still running")
    }

    /// The harness reads only the menu, its own saved key and the rules file, and counts the log, and
    /// never reads what a notification said: it opens no window of Notification Centre, reads no text of
    /// any window, reads one key of the preferences, prints no line of the log, and posts banners that say
    /// words of its own.
    func testNoFlagReadsANotificationsContent() throws {
        let lines = try verifyCode()
        let code = lines.joined(separator: "\n")
        for line in lines where line.contains("tell process ") {
            XCTAssertTrue(line.contains(#"tell process "SignalLadder""#), "`\(line)` reads a process that is not the app's")
        }
        for forbidden in ["AXValue", "AXDescription", "AXAttributedDescription", "AXTitle", "AXPlaceholder", "static text", "text field",
                          "description of", "value of", "entire contents", "UI elements", "scroll area", "NSPasteboard", "pbpaste"] {
            XCTAssertFalse(code.contains(forbidden), "verify-live.sh reads `\(forbidden)`, which can hold what a notification said")
        }
        // The one key.
        let reads = lines.filter { $0.range(of: #"\bdefaults\b"#, options: .regularExpression) != nil }
        XCTAssertFalse(reads.isEmpty)
        for line in reads {
            XCTAssertEqual(line.trimmingCharacters(in: .whitespaces), #"defaults read "$APP_DOMAIN" "$ON_CALL_KEY" >/dev/null 2>&1"#)
        }
        XCTAssertEqual(try Harness.references().filter { $0.script == "verify-live.sh" && $0.name == "storageKey" }.map(\.file), ["OnCall.swift"])
        // The log is counted, and its lines are not kept, but for the state of Do Not Disturb, which is
        // a word of the system's own.
        let logs = statements(of: lines).filter { $0.contains("log show") }
        XCTAssertGreaterThanOrEqual(logs.count, 5)
        for statement in logs {
            let counts = statement.range(of: #"grep -v?c "(\\.|[^"\\])*"\)?$"#, options: .regularExpression) != nil
            XCTAssertTrue(counts || statement.contains("donotdisturb"), "`\(statement)` reads the log and does not count it")
        }
        // The banners it posts say words of its own: a title from the core, and a body that is plain words.
        for line in lines where line.contains("post_marker_banner ") && !line.contains("post_marker_banner()") {
            XCTAssertNotNil(line.range(of: #"post_marker_banner "[A-Za-z0-9 ,$]*"$"#, options: .regularExpression), line)
        }
        XCTAssertTrue(code.contains(#"osascript - "$MARKER_TITLE" "$1" >/dev/null 2>&1 <<'APPLESCRIPT'"#))
        // And it says so at its head.
        let header = try Harness.script("verify-live.sh").components(separatedBy: "\n").prefix { $0.hasPrefix("#") }
            .map { String($0.dropFirst()) }.joined(separator: " ").split(separator: " ").joined(separator: " ")
        XCTAssertTrue(header.contains("never reads notification content"))
    }

    /// The header says what each flag does to a real Mac, that all three are run off shift, and that the
    /// marker rule goes first in the rules file and why.
    func testTheHeaderSaysWhatEachFlagDoesToARealMacAndThatAllThreeRunOffShift() throws {
        let header = try Harness.script("verify-live.sh").components(separatedBy: "\n").prefix { $0.hasPrefix("#") }
            .map { String($0.dropFirst()) }.joined(separator: " ").split(separator: " ").joined(separator: " ")
        for needle in ["--escalation", "--on-call", "--snooze", "OFF SHIFT", "quiets YOUR OWN rules", "your real on-call state",
                       "refuses to run (exit 2)", "acknowledge it by hand", "Scripts/harness-guards-test.sh",
                       "before the default checks post a banner or open a window", "already shows a held summary",
                       "puts a leftover backup back only over a file that is still the one the run wrote",
                       "a last match that names the marker rule", "posts no more banners and acknowledges nothing",
                       "first in the rules array, before every rule of yours", "the first rule to match wins",
                       "The last match is the second line of defence"] {
            XCTAssertTrue(header.contains(needle), "the header of verify-live.sh does not say `\(needle)`")
        }
    }

    /// The marker rules the script writes are one line of JSON each, with the id, the name and the
    /// title left as three `%s`, and each is a rule the codec accepts, at the version the script tells the
    /// writer the rule needs, and not at the one before.
    func testTheMarkerRulesTheScriptWritesAreRulesTheCodecAcceptsAtTheVersionTheWriterRaisesTo() throws {
        let verify = try Harness.script("verify-live.sh")
        let code = Harness.codeLines(verify)
        let name = HarnessText.markerRuleName, title = HarnessText.markerTitle
        func filled(_ variable: String, id: String) throws -> String {
            let prefix = "\(variable)='"
            let line = try XCTUnwrap(code.first { $0.hasPrefix(prefix) && $0.hasSuffix("'") }, "verify-live.sh has no \(variable)")
            let shape = String(line.dropFirst(prefix.count).dropLast())
            let parts = shape.components(separatedBy: "%s")
            XCTAssertEqual(parts.count, 4, "\(variable) must have three %s, for the id, the name and the title")
            XCTAssertFalse(parts.joined().contains("%"), "\(variable) has a % that is not a %s")
            XCTAssertTrue(parts[0].hasSuffix(#""id":""#) && parts[1].hasSuffix(#""name":""#) && parts[2].hasSuffix(#""value":""#),
                          "\(variable) does not take the id, the name and the title in that order")
            return parts[0] + id + parts[1] + name + parts[2] + title + parts[3]
        }
        let function = try Harness.body(of: "marker_rule_json", in: verify).map { $0.split(separator: " ").joined(separator: " ") }
        XCTAssertTrue(function.contains("escalation) id=$MARKER_ESCALATION_ID; shape=$MARKER_RULE_ESCALATION ;;"))
        XCTAssertTrue(function.contains("snooze) id=$MARKER_SNOOZE_ID; shape=$MARKER_RULE_SNOOZE ;;"))
        XCTAssertTrue(function.contains(#"printf "$shape" "$id" "$MARKER_NAME" "$MARKER_TITLE""#))

        // The version each is told it needs.
        let calls = try Harness.body(of: "run_escalation", in: verify) + Harness.body(of: "run_snooze", in: verify)
        let needs = calls.compactMap { line -> (String, Int)? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("install_marker "), let version = Int(trimmed.split(separator: " ").last ?? "") else { return nil }
            return (String(trimmed.split(separator: " ")[1]), version)
        }
        XCTAssertEqual(needs.map { "\($0.0) \($0.1)" }, ["escalation 4", "snooze 5"])

        let escalationText = try filled("MARKER_RULE_ESCALATION", id: HarnessText.markerEscalationRuleID)
        let snoozeText = try filled("MARKER_RULE_SNOOZE", id: HarnessText.markerSnoozeRuleID)
        func decode(_ text: String, atVersion version: Int) throws -> (rules: [Rule], status: RuleStoreStatus) {
            XCTAssertNotNil(try? JSONSerialization.jsonObject(with: Data(text.utf8)), "the rule is not JSON: \(text)")
            let data = rulesFile(version: version, text)
            let (rules, status) = RuleStoreStatus.load(data)
            return (rules, status)
        }
        for (kind, version) in needs {
            let text = kind == "escalation" ? escalationText : snoozeText
            let loaded = try decode(text, atVersion: version)
            XCTAssertEqual(loaded.status, .loaded(enabled: 1, disabled: 0), "the \(kind) marker at version \(version)")
            let rule = try XCTUnwrap(loaded.rules.first)
            XCTAssertEqual(RuleSetCodec.version(for: [rule]), version, "the \(kind) marker needs the version the script says")
            XCTAssertNotEqual(try decode(text, atVersion: version - 1).status, .loaded(enabled: 1, disabled: 0),
                              "the \(kind) marker loads whole at version \(version - 1), so the version it is told it needs is too high")
            XCTAssertEqual(rule.name, HarnessText.markerRuleName)
            XCTAssertEqual(rule.condition, .field(.title, .equals, HarnessText.markerTitle))
            XCTAssertTrue(rule.isEnabled)
        }

        let escalation = try XCTUnwrap(try decode(escalationText, atVersion: 4).rules.first)
        XCTAssertEqual(escalation.id, UUID(uuidString: HarnessText.markerEscalationRuleID))
        XCTAssertEqual(escalation.alert, .silent)
        XCTAssertEqual(escalation.escalation?.tier2?.delaySeconds, 10)
        let tier3 = try XCTUnwrap(escalation.escalation?.tier3)
        XCTAssertEqual(tier3.action, .sound(name: "Hero", gainDB: AlertAction.gainRange.lowerBound))
        XCTAssertEqual(tier3.intervalSeconds, 30)
        XCTAssertEqual(tier3.maxRepeats, 2)
        XCTAssertNil(escalation.escalation?.tier4, "the escalation marker runs a Shortcut")
        XCTAssertFalse(escalation.quietWhenSnoozed)

        let snooze = try XCTUnwrap(try decode(snoozeText, atVersion: 5).rules.first)
        XCTAssertEqual(snooze.id, UUID(uuidString: HarnessText.markerSnoozeRuleID))
        XCTAssertEqual(snooze.alert, .sound(name: "Glass", gainDB: AlertAction.gainRange.lowerBound))
        XCTAssertNil(snooze.escalation)
        XCTAssertTrue(snooze.quietWhenSnoozed)
        XCTAssertTrue(snooze.alertsAloud)
        XCTAssertTrue(snooze.snoozeMayHold, "a snooze would not hold the snooze marker")
        XCTAssertNotEqual(escalation.id, snooze.id)
    }

    /// A marker left in rules.json is found by its id, and the script does not run a flag that writes one
    /// beside it.
    func testALeftoverMarkerIsFoundByItsIdBeforeAnotherIsWritten() throws {
        let verify = try Harness.script("verify-live.sh")
        let find = try Harness.body(of: "marker_in_rules", in: verify)
        XCTAssertTrue(find.contains { $0.contains(#"for id in "$MARKER_ESCALATION_ID" "$MARKER_SNOOZE_ID"; do"#) })
        XCTAssertTrue(find.contains { $0.contains(#"grep -qiF -- "$id" "$RULES_FILE""#) })
        let install = try Harness.body(of: "install_marker", in: verify)
        let found = try Harness.first("marker_in_rules", in: install)
        XCTAssertLessThan(found, try Harness.first("RULES_TOUCHED=1", in: install))
        XCTAssertLessThan(found, try Harness.first("harness_install_marker", in: install))
        XCTAssertTrue(install[found...(found + 3)].contains { $0.contains("exit 2") }, "a leftover marker does not stop the run")
        // The writer's refusal stops it too, and leaves nothing to put back.
        XCTAssertTrue(install.contains { $0.contains(#"if [ "$rc" -eq 2 ]; then RULES_TOUCHED=0; fi"#) })
    }

    /// The default run finds the setup line and the Settings window by what the core says, and closes the
    /// Settings window it opened.
    func testTheDefaultRunChecksThatNoSetupLineIsOnTheMenuAndThatSettingsOpensItsWindow() throws {
        let code = try verifyCode().joined(separator: "\n")
        XCTAssertTrue(code.contains(#"open_and_close_window "$SETTINGS_ITEM" "$SETTINGS_TITLE""#))
        XCTAssertTrue(code.contains(#"grep -qF -- "$SETTINGS_TITLE" <<< "$SETTINGS_WINDOW""#))
        XCTAssertTrue(code.contains(#"grep -q "STILL_OPEN=true" <<< "$SETTINGS_WINDOW""#), "a Settings window that stays open is not a failure")
        XCTAssertTrue(code.contains(#"open_and_close_window "$EDIT_RULES_ITEM" "$RULE_EDITOR_TITLE""#))
        // The menu items are chosen by argument, so the AppleScript types none of the app's words.
        let script = try Harness.script("verify-live.sh")
        for word in [StatusMenuText.showInspectorTitle, StatusMenuText.editRulesTitle, SettingsText.menuTitle,
                     StatusMenuText.reloadRulesTitle, OnCallText.menuTitle, SnoozeText.endTitle] {
            XCTAssertFalse(script.contains("\"\(word)\""), "\"\(word)\" is typed in verify-live.sh")
        }
    }

    /// The default run closes the Inspector it opened, as it closes the editor and Settings, and leaves an
    /// Inspector that was open before the run as it was. Every run against a signed build left the
    /// Inspector open until 2026-10-13.
    func testTheDefaultRunClosesTheInspectorItOpenedAndLeavesOneThatWasOpenBeforeIt() throws {
        let code = try verifyCode()
        let asked = try XCTUnwrap(code.firstIndex { $0.contains(#"if window_titles | grep -qxF -- "$INSPECTOR_TITLE"; then"#) },
                                  "the run does not ask whether the Inspector was open before it")
        let left = try XCTUnwrap(code.firstIndex { $0.contains(#"INSPECTOR=$(read_inspector_windows "$INSPECTOR_ITEM")"#) })
        let elseLine = try XCTUnwrap(code[left...].firstIndex { $0.trimmingCharacters(in: .whitespaces) == "else" })
        let closed = try XCTUnwrap(code.firstIndex { $0.contains(#"INSPECTOR=$(open_and_close_window "$INSPECTOR_ITEM" "$INSPECTOR_TITLE")"#) },
                                   "the run does not close the Inspector it opened")
        XCTAssertLessThan(asked, left, "an Inspector open before the run is not the one only read")
        XCTAssertLessThan(left, elseLine)
        XCTAssertLessThan(elseLine, closed, "the window the run opened is not the one it closes")
        let defined = try XCTUnwrap(code.firstIndex { $0.contains("open_and_close_window() {") })
        XCTAssertLessThan(defined, closed, "the helper is used before bash has read its definition")
        XCTAssertTrue(code.contains { $0.contains(#"elif grep -q "STILL_OPEN=true" <<< "$INSPECTOR"; then"#) },
                      "an Inspector the run opened and could not close is not said")
    }

    /// The check that the test banner was drawn reads the log from the moment the banner was posted, and
    /// reads it again for a while, since the entry can reach the log after the banner is on screen. (Its
    /// inconclusive result on the first runs against a signed build, on 2026-10-13, was not the timing:
    /// the poster's name is in lower case in that log line on macOS 27.2, which the match of the poster
    /// now allows for, and which the test of the burst's log reads holds.)
    func testTheDrawnCheckReadsTheLogFromThePostAndWaitsForTheEntry() throws {
        let code = try verifyCode()
        let start = try XCTUnwrap(code.firstIndex { $0.contains(#"DRAWN_START=$(date '+%Y-%m-%d %H:%M:%S')"#) })
        let post = try XCTUnwrap(code.firstIndex { $0.contains(#"display notification "Automated capture check""#) })
        let loop = try XCTUnwrap(code[post...].firstIndex { $0.contains("for _ in 1 2 3 4 5 6; do") })
        let read = try XCTUnwrap(code[loop...].firstIndex { $0.contains(#"/usr/bin/log show --start "$DRAWN_START""#) })
        let done = try XCTUnwrap(code[read...].firstIndex { $0.contains(#"[ "${DRAWN:-0}" -gt 0 ] && break"#) })
        let end = try XCTUnwrap(code[done...].firstIndex { $0.trimmingCharacters(in: .whitespaces) == "done" })
        XCTAssertLessThan(start, post, "the log is not read from before the post")
        XCTAssertTrue(code[loop..<read].contains { $0.contains("sleep 2") }, "the reads are not spaced")
        XCTAssertLessThan(done, end)
        XCTAssertFalse(code.contains { $0.contains("DRAWN=") && $0.contains("--last 1m") },
                       "the one read of the last minute is back")
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
            // The stem of the one escalation line and the Acknowledge item's title, and the two words
            // that say whose escalation it is: the stem of the last-match line and the marker rule's name.
            "harness_marker_only_guard": [("AlertMenuText.swift", "singleEscalatingStem"),
                                          ("AlertMenuText.swift", "acknowledgeOneTitle"),
                                          ("AlertMenuText.swift", "lastMatchStem"),
                                          ("HarnessText.swift", "markerRuleName")],
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

        // The marker-only guard finds a last-match line by its stem once any warning mark is skipped,
        // and the marker's by the stem, a space, the rule's name and " at ", which is how the app
        // builds the line. The two expressions are written in the script and read here, and they take
        // the line the app builds for the marker rule whatever its alert came to, with the mark the
        // app puts before a line that needs attention or without it, and take no line the app builds
        // for another rule, nor one whose rule is named with the marker's name and more.
        let lastStem = try Harness.declaredText("AlertMenuText.swift", "lastMatchStem")
        let markerName = HarnessText.markerRuleName
        XCTAssertTrue(code.contains(#"last_any="^[^A-Za-z]*$(_harness_ere_escape "$last_stem")""#), "the marker-only guard does not find a last-match line that way")
        XCTAssertTrue(code.contains(#"last_marker="$last_any $(_harness_ere_escape "$marker") at ""#), "the marker-only guard does not find the marker's last-match line that way")
        let escaped = NSRegularExpression.escapedPattern(for:)
        let anyLastMatch = try NSRegularExpression(pattern: "^[^A-Za-z]*\(escaped(lastStem))")
        let markersLastMatch = try NSRegularExpression(pattern: "^[^A-Za-z]*\(escaped(lastStem)) \(escaped(markerName)) at ")
        func found(_ expression: NSRegularExpression, in line: String) -> Bool {
            expression.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
        }
        func lastMatchLines(_ name: String, _ alert: AlertOutcome) -> [String] {
            AlertMenuText.lines(lastMatch: CapturePipeline.LastMatch(ruleName: name, at: now, alert: alert),
                                unresolvedFailure: nil, anyRulePlaysSound: false, outputSilent: false, time: { _ in "10:42" })
        }
        let outcomes: [AlertOutcome] = [.silentByRule, .noAlertSet, .snoozed, .joinedEscalation(matchNumber: 5),
                                        .played(sound: "Hero", gainDB: -40, outputSilent: false),
                                        .played(sound: "Hero", gainDB: -40, outputSilent: true),
                                        .failed("no such sound"), .couldNotSpeak("no voice")]
        var marked = 0
        for outcome in outcomes {
            let own = lastMatchLines(markerName, outcome)
            XCTAssertEqual(own.count, 1, "the app builds one line for a last match")
            for line in own {
                XCTAssertTrue(found(anyLastMatch, in: line) && found(markersLastMatch, in: line), "\"\(line)\" is not taken for the marker's last match")
                if !line.hasPrefix(AlertMenuText.lastMatchStem) { marked += 1 }
            }
            for name in ["On-call mentions", "\(markerName) two", "Not \(markerName)", String(markerName.dropLast())] {
                for line in lastMatchLines(name, outcome) {
                    XCTAssertTrue(found(anyLastMatch, in: line), "\"\(line)\" is not taken for a last-match line")
                    XCTAssertFalse(found(markersLastMatch, in: line), "\"\(line)\" is taken for the marker's last match")
                }
            }
        }
        XCTAssertGreaterThan(marked, 0, "no outcome gave a line with a warning mark before the stem, and the guard's allowance for one is not tried")
        for line in ["1 alert escalating", "Rules: 3 active", "\(SnoozeText.heldOneMatchStem): \(markerName) \u{D7}1", "Acknowledge"] {
            XCTAssertFalse(found(anyLastMatch, in: line), "\"\(line)\" is taken for a last-match line")
        }

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
                                   SettingsText.menuTitle, StatusMenuText.showInspectorTitle,
                                   StatusMenuText.editRulesTitle, StatusMenuText.reloadRulesTitle]
        let stems = [AlertMenuText.acknowledgeOneTitle, OnCallText.sinceStem, SnoozeText.activeStem,
                     SnoozeText.stillAlertingStem, AlertMenuText.lastMatchStem, "\(RuleStoreStatus.summaryStem):",
                     StatusMenuText.capturedStem, HealthTitle.verifiedStem,
                     HealthTitle.checkingLine, HealthTitle.unverifiedStem, HealthTitle.cannotVerifyLine,
                     HealthTitle.notCapturingLine, HealthTitle.someBannersUnreadLine]
        let counted = try NSRegularExpression(
            pattern: "^[0-9]+ (alerts? (\(AlertMenuText.escalatingWord)|missed while asleep)|match(es)? \(SnoozeText.heldStem))")
        return titles.contains(line) || stems.contains { line.hasPrefix($0) }
            || counted.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
    }

    /// The few lines of the menu the app target types itself and the core does not make: the line
    /// about how many of the last captures the rules match, and the quit item. They hold a count
    /// and a title and nothing else. The capture count's line and the items that open the
    /// Inspector and the editor and reload the rules were typed here until Task 9 moved them to
    /// `StatusMenuText`, which the harness reads them from.
    private func isTypedByTheApp(_ line: String) throws -> Bool {
        let shapes = [#"^Current rules match [0-9]+ of the last [0-9]+$"#, #"^Quit SignalLadder$"#]
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

        /// The menu from the capture count down, in the order the menu has it, but for the two lines
        /// the app types still: the count, the Inspector, the rules summary, the last match, the
        /// editor, the rules file in a text editor, Reload Rules and Settings.
        func tail(rules active: Int, lastMatch: [String] = [], captured: Int = 212) -> [String] {
            [StatusMenuText.capturedLine(count: captured), StatusMenuText.showInspectorTitle,
             RuleStoreStatus.loaded(enabled: active, disabled: 0).summary] + lastMatch
                + [StatusMenuText.editRulesTitle, SetupText.rulesFileMenuTitle, StatusMenuText.reloadRulesTitle,
                   SettingsText.menuTitle]
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
                + tail(rules: 4, lastMatch: lastMatch(marker.name, .snoozed, at: "10:42"), captured: 213)),
            ("held-summary-other", [health, onCall]
                + snoozed(fourRules, held: HeldSummary(counts: [prod.id: 3]))
                + tail(rules: 4, lastMatch: lastMatch(prod.name, .snoozed, at: "10:44"), captured: 215)),
            ("held-summary-mixed", [health, onCall]
                + snoozed(fourRules, held: HeldSummary(counts: [prod.id: 1, marker.id: 1]))
                + tail(rules: 4, lastMatch: lastMatch(marker.name, .snoozed, at: "10:44"), captured: 214)),
            // The marker's own escalations name the marker rule as the last match, because its match
            // is the last one made. The two named for another rule are the menus a real page makes when
            // it comes in after the banners (or a rule of the owner's makes if the marker were no longer
            // first): the same escalation line, the same Acknowledge item and a last match that names
            // that rule, and a real page's rule alone is the same menu with the count of one.
            ("escalating-one", escalation([burst(1)]) + quietHead
                + tail(rules: 3, lastMatch: lastMatch(marker.name, .silentByRule, at: "10:42"))),
            ("escalating-one-other-rule", escalation([one]) + quietHead
                + tail(rules: 3, lastMatch: lastMatch(mentions.name, .played(sound: "Hero", gainDB: 0, outputSilent: false), at: "10:42"))),
            ("escalating-burst", escalation([burst(5)]) + quietHead
                + tail(rules: 3, lastMatch: lastMatch(marker.name, .joinedEscalation(matchNumber: 5), at: "10:42"))),
            ("escalating-burst-four", escalation([burst(4)]) + quietHead
                + tail(rules: 3, lastMatch: lastMatch(marker.name, .joinedEscalation(matchNumber: 4), at: "10:42"))),
            ("escalating-burst-other-rule", escalation([EscalationSummary(ruleName: mentions.name, startedAt: now, matchCount: 5)]) + quietHead
                + tail(rules: 3, lastMatch: lastMatch(mentions.name, .joinedEscalation(matchNumber: 5), at: "10:42"))),
            ("escalating-two", escalation([burst(3), burst(3)]) + quietHead
                + tail(rules: 3, lastMatch: lastMatch(marker.name, .joinedEscalation(matchNumber: 3), at: "10:42"))),
            ("escalating-beside-missed", escalation([burst(1), missed]) + quietHead
                + tail(rules: 3, lastMatch: lastMatch(marker.name, .silentByRule, at: "10:42"))),
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
        XCTAssertEqual(try first("escalating-one-other-rule"), exact)
        XCTAssertEqual(try first("escalating-burst"), exact)
        XCTAssertEqual(try first("escalating-burst-four"), exact)
        XCTAssertEqual(try first("escalating-burst-other-rule"), exact)
        XCTAssertEqual(try first("missed-alone"), exact)
        XCTAssertNotEqual(try first("escalating-two"), exact)
        XCTAssertNotEqual(try first("escalating-beside-missed"), exact)
        // Whose the last match is. Every menu of the marker's own escalation names the marker rule, so
        // that each of the marker-only guard's other checks is the one that refuses a menu written for
        // it, and the two that stand for a real page's rule taking the last banner are those menus
        // but for the rule the one last-match line names.
        let lastMatchStem = try Harness.declaredText("AlertMenuText.swift", "lastMatchStem")
        let markerName = HarnessText.markerRuleName
        let lastMatches = { (file: String) throws -> [String] in try Harness.menu(file).filter { $0.hasPrefix(lastMatchStem) } }
        for file in ["escalating-one", "escalating-burst", "escalating-burst-four", "escalating-two", "escalating-beside-missed"] {
            XCTAssertEqual(try lastMatches(file).count, 1, "menu-\(file).txt does not hold one last-match line")
            XCTAssertTrue(try lastMatches(file).allSatisfy { $0.hasPrefix("\(lastMatchStem) \(markerName) at ") },
                          "menu-\(file).txt does not name the marker rule as its last match")
        }
        for (own, other) in [("escalating-one", "escalating-one-other-rule"), ("escalating-burst", "escalating-burst-other-rule")] {
            XCTAssertEqual(try lastMatches(other).count, 1, "menu-\(other).txt does not hold one last-match line")
            XCTAssertFalse(try Harness.menu(other).contains { $0.contains(markerName) }, "menu-\(other).txt names the marker rule")
            XCTAssertEqual(try Harness.menu(other).filter { !$0.hasPrefix(lastMatchStem) },
                           try Harness.menu(own).filter { !$0.hasPrefix(lastMatchStem) },
                           "menu-\(other).txt is not menu-\(own).txt but for its last match")
        }
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
        let (rules, status) = RuleStoreStatus.load(notJSON)
        XCTAssertEqual(rules, [])
        guard case .unreadable = status else { return XCTFail("the codec does not call rules-not-json.json unreadable: \(status)") }

        let tooNew = try Harness.fixtureData("rules-too-new.json")
        let file = try XCTUnwrap(try JSONSerialization.jsonObject(with: tooNew) as? [String: Any], "rules-too-new.json is not JSON")
        let version = try XCTUnwrap(file["version"] as? Int)
        XCTAssertGreaterThan(version, RuleSetCodec.currentVersion, "rules-too-new.json is not newer than the codec")
        XCTAssertEqual(RuleStoreStatus.load(tooNew).status,
                       .unsupportedVersion(version))
        // And it is otherwise the owner's file, so that nothing but the version is what is refused.
        let owner = try json(try Harness.fixture("rules-owner.json"))
        XCTAssertEqual((file["rules"] as? [Any])?.count, (owner["rules"] as? [Any])?.count)
    }

    /// A marker rule fixture, as the codec loads it in a file at `version`.
    private func markerRule(_ file: String, atVersion version: Int) throws -> Rule {
        let text = try Harness.fixture(file)
        let data = rulesFile(version: version, text)
        let (rules, status) = RuleStoreStatus.load(data)
        XCTAssertEqual(status, .loaded(enabled: 1, disabled: 0), "\(file) at version \(version)")
        return try XCTUnwrap(rules.first, "\(file) loads no rule")
    }

    /// The marker rules the writer's cases put into the owner's file are rules the codec accepts, at the version each
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
        if case .loaded = RuleStoreStatus.load(before).status {
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

        // The file a run wrote: the marker's rule FIRST, then the owner's three, at version 4. The
        // marker goes first because the first enabled rule to match wins (the owner's decision of
        // 2026-10-13), and the owner's rules follow it in the order they were in.
        let writtenText = String(decoding: try data("written", "rules.json"), as: UTF8.self)
        let written = try json(writtenText)
        XCTAssertEqual(written["version"] as? Int, 4)
        let ownerText = String(decoding: owner, as: UTF8.self)
        let ownerRules = try XCTUnwrap(try json(ownerText)["rules"] as? [NSDictionary])
        let writtenRules = try XCTUnwrap(written["rules"] as? [NSDictionary])
        let marker = try json(try Harness.fixture("marker-rule-escalation.json")) as NSDictionary
        XCTAssertEqual(writtenRules.count, 4)
        XCTAssertEqual(writtenRules.first, marker)
        XCTAssertEqual(Array(writtenRules.dropFirst()), ownerRules)
        // And at the level of the bytes: the written file opens as the owner's does, up to its first
        // rule, and ends as the owner's does from that rule on, but for the digit of the version. What is
        // between is the marker, a comma and the whitespace that stood in front of the first rule.
        let opening = try XCTUnwrap(ownerText.range(of: "\"rules\" : [\n    "), "the owner's fixture has no rules array opening that way")
        XCTAssertTrue(writtenText.hasPrefix(String(ownerText[..<opening.upperBound])),
                      "the written file does not open as the owner's does, up to the first rule")
        XCTAssertTrue(writtenText.hasSuffix(ownerText[opening.upperBound...].replacingOccurrences(of: "\"version\" : 3", with: "\"version\" : 4")),
                      "the written file does not end with the owner's rules, byte for byte, from the first rule on")
        let between = writtenText.dropFirst(ownerText.distance(from: ownerText.startIndex, to: opening.upperBound))
        XCTAssertTrue(between.hasPrefix("{\n      \"alert\": \"silent\","), "the marker is not the first thing after the opening")
        XCTAssertTrue(between.contains("\"name\": \"\(HarnessText.markerRuleName)\"\n    },\n    {\n      \"alert\" : \"silent\","),
                      "the marker is not followed by a comma and the owner's first rule at the owner's indentation")

        // Its digest is recorded, and so is the one the edited state still holds: the file edited
        // since is not the file the digest is of.
        let wrote = sha256(try data("written", "rules.json"))
        XCTAssertEqual(try digest("written"), wrote + "\n")
        XCTAssertEqual(try digest("edited"), wrote + "\n")
        XCTAssertNotEqual(sha256(try data("edited", "rules.json")), wrote)
        let edited = try XCTUnwrap(try json(String(decoding: try data("edited", "rules.json"), as: UTF8.self))["rules"] as? [NSDictionary])
        XCTAssertEqual(edited.count, 4)
        XCTAssertEqual(edited.first, marker, "the marker is first in the edited file too")
        XCTAssertEqual(edited[2]["name"] as? String, "Prod and incident channels")
        XCTAssertEqual(edited[2]["enabled"] as? Bool, false, "the owner switched off the rule that was second before the marker went in front of it")

        // The run that found no rules file: the record, the digest of what it made, and the file.
        XCTAssertTrue(has("absent-written", "\(backup).absent"))
        XCTAssertFalse(has("absent-written", backup))
        XCTAssertEqual(try digest("absent-written"), sha256(try data("absent-written", "rules.json")) + "\n")
        let made = try json(String(decoding: try data("absent-written", "rules.json"), as: UTF8.self))
        XCTAssertEqual((made["rules"] as? [NSDictionary])?.count, 1)
        XCTAssertEqual((made["rules"] as? [NSDictionary])?.first, marker)
        XCTAssertEqual(made["version"] as? Int, 4)
    }

    /// The file a run wrote decodes under the codec with the marker as `rules[0]`, and the owner's three after
    /// it in their order. The reason the marker is first (the owner's decision of 2026-10-13) is the engine's:
    /// it gives a banner to the first enabled rule that matches it, so a rule of the owner's that matches a
    /// banner with the marker's title (a catch-all, a rule for Script Editor, a rule for every app but some)
    /// takes it if it is before the marker, as it would be were the marker appended, and cannot take it if the
    /// marker is first, where the writer puts it. Each of the three is tried in front of where the marker
    /// would have been, and after the marker where it is.
    func testTheMarkedFixtureDecodesWithTheMarkerFirstAndTakesItsBannersBeforeAnyRuleOfTheOwners() throws {
        let states = Harness.fixtures.appendingPathComponent("backup-states")
        for state in ["written", "edited", "no-digest-differs"] {
            let data = try Data(contentsOf: states.appendingPathComponent("\(state)/rules.json"))
            let (rules, status) = RuleStoreStatus.load(data)
            XCTAssertEqual(status, .loaded(enabled: state == "edited" ? 3 : 4, disabled: state == "edited" ? 1 : 0), state)
            XCTAssertEqual(rules.map(\.name), [HarnessText.markerRuleName, "Weather stays quiet", "Prod and incident channels", "On-call mentions"], state)
            XCTAssertEqual(rules.first?.id, UUID(uuidString: HarnessText.markerEscalationRuleID), "\(state): rules[0] is not the escalation marker")
            XCTAssertEqual(rules.first?.condition, .field(.title, .equals, HarnessText.markerTitle), state)
        }
        let data = try Data(contentsOf: states.appendingPathComponent("written/rules.json"))
        let rules = RuleStoreStatus.load(data).rules
        let marker = try XCTUnwrap(rules.first)
        let owners = Array(rules.dropFirst())
        XCTAssertEqual(owners.count, 3)
        XCTAssertFalse(owners.contains { $0.id == marker.id }, "the marker is in the file twice")

        let banner = CapturedNotification(timestamp: Date(timeIntervalSince1970: 1_757_000_000), appNameGuess: "Script Editor",
                                          title: HarnessText.markerTitle, subtitle: "", body: "Escalation check, banner 1 of 5",
                                          rawText: "Script Editor, \(HarnessText.markerTitle), Escalation check, banner 1 of 5",
                                          subrole: "AXNotificationCenterBanner")
        XCTAssertEqual(RuleEngine.firstMatch(for: banner, in: rules)?.id, marker.id, "the marker does not take its own banner")
        let wouldTake: [Rule] = [
            Rule(name: "Catch-all", condition: .field(.title, .matches, "*"), alert: .sound(name: "Glass", gainDB: 0)),
            Rule(name: "Script Editor practice", condition: .field(.app, .equals, "Script Editor"), alert: .sound(name: "Hero", gainDB: 0)),
            Rule(name: "Not these apps", condition: .not(.field(.app, .equals, "Mail")), alert: .silent),
        ]
        for earlier in wouldTake {
            XCTAssertEqual(RuleEngine.firstMatch(for: banner, in: [earlier] + owners + [marker])?.name, earlier.name,
                           "\(earlier.name) does not match the marker's banner, so it is not a rule the marker has to go in front of")
            XCTAssertEqual(RuleEngine.firstMatch(for: banner, in: [marker, earlier] + owners)?.id, marker.id,
                           "\(earlier.name) takes the marker's banner although the marker is first")
            XCTAssertEqual(RuleEngine.firstMatch(for: banner, in: [marker] + owners + [earlier])?.id, marker.id,
                           "\(earlier.name), after the owner's rules, takes the marker's banner although the marker is first")
        }
        // A real page is still the owner's: the marker matches only its own title.
        let page = CapturedNotification(timestamp: banner.timestamp, appNameGuess: "Example Chat", title: "#incident-42",
                                        subtitle: "", body: "on-call: db is down", rawText: "Example Chat, #incident-42, on-call: db is down",
                                        subrole: "AXNotificationCenterBanner")
        XCTAssertEqual(RuleEngine.firstMatch(for: page, in: rules)?.name, "Prod and incident channels")
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
