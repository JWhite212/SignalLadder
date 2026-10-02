import Foundation
import XCTest

// Holds the app target's words to the text enums in NotificationCore (M5 plan,
// Ruling 18). The app target has no tests, so a sentence typed into a view or a
// controller is a sentence nothing proves and nothing can say is wrong. This
// reads the app's sources, as PurityTests reads the core's, and refuses a string
// literal where a word would be.
//
// Three kinds of file are held, each by its own rule:
//
//  - a NEW view file (`LadderEditorView` and the later ones) may hold no literal
//    but the empty string and the argument of `systemName:` or `systemImage:`;
//  - a NEW controller or coordinator, and each of the three that exist today and
//    show no words, may hold no literal at the sites that show words: the
//    arguments `title:`, `withTitle:` and `accessibilityDescription:` and
//    assignments to `messageText`, `informativeText`, `toolTip`, `title` and
//    `body`;
//  - a file that EXISTS TODAY and shows words is held to a baseline: every
//    literal it holds now is written into this file as data, each once, and
//    nothing is ever added to that data. A new literal in such a file fails and
//    its words go to a text enum in the core; the data shrinks when a task moves
//    one out, and a listed literal the file no longer holds fails too, so the
//    data cannot keep slack that a literal could later be hidden in.
//
// The scanner is a small lexer, not a pattern for the initialisers to look for,
// so a `.help`, a `TextField`'s placeholder, a `Menu` or a `Text(verbatim:)` that
// holds words fails as a `Text("…")` does. It is itself tested, on canned source,
// below. The files it reads are the sources as they are, so the tests that read
// them are the ones that hold the words; the canned ones show the holding works.

// MARK: - The scanner

/// One string literal in a piece of Swift source, and where it stands.
struct SourceLiteral: Equatable {
    /// What is between the quotes, as written. An escape or an interpolation is
    /// left as it is typed, so `"\(n) alerts"` reads `\(n) alerts`, and a literal
    /// inside an interpolation is part of its text and not a literal of its own.
    let text: String
    /// The line of its opening quote, from 1.
    let line: Int
    /// The label of the argument it is directly in, however far into the
    /// argument it stands: `systemImage` for `Label(t, systemImage: c ? "a" : "b")`.
    /// nil for an argument with no label, and for a literal outside a call.
    let argumentLabel: String?
    /// The label of every argument it is inside, innermost first.
    let enclosingLabels: [String]
    /// The names assigned in the statement it is in: `title` for
    /// `window.title = c ? "A" : "B"`.
    let assignedNames: [String]
    /// Whether it is inside a `Logger` call, which is not words a user reads.
    let isLoggerArgument: Bool
}

struct SwiftLiteralScanner {
    static func literals(in source: String) -> [SourceLiteral] {
        var scanner = SwiftLiteralScanner(source: source)
        scanner.run()
        return scanner.found
    }

    /// Words that may come before `let` or `var` at the start of a declaration.
    private static let modifiers: Set<String> = [
        "private", "fileprivate", "internal", "public", "open", "static", "final", "lazy", "weak", "unowned",
        "override", "class", "required", "convenience", "nonisolated", "mutating", "indirect",
    ]

    /// The methods of a logger that take its message.
    private static let loggerLevels: Set<String> = [
        "trace", "debug", "info", "notice", "log", "warning", "error", "critical", "fault",
    ]

    private struct Frame {
        var kind: Unicode.Scalar
        var label: String?
        var argumentStarts: Bool
        var isLogger: Bool
    }

    private struct Assignment {
        var name: String
        var depth: Int
    }

    private enum Token: Equatable {
        case word(String)
        case symbol(Unicode.Scalar)
        case literal
        case number
    }

    private let s: [Unicode.Scalar]
    private let lineStarts: [Int]
    private var i = 0
    private var found: [SourceLiteral] = []
    private var frames = [Frame(kind: "{", label: nil, argumentStarts: false, isLogger: false)]
    private var tokens: [Token] = []
    private var assignments: [Assignment] = []
    /// The name a `let` or `var` that begins a statement declares: the target of
    /// its `=`, which a type annotation would otherwise hide.
    private var declaration: Assignment?
    /// The name an `if let`, `guard let` or `while let` binds, whose `=` is not
    /// an assignment of words.
    private var ignoredBinding: Assignment?
    private var statementStarts = true
    private var bindingStartsStatement = false

    private init(source: String) {
        s = Array(source.replacingOccurrences(of: "\r\n", with: "\n").unicodeScalars)
        var starts = [0]
        for (index, scalar) in s.enumerated() where scalar == "\n" { starts.append(index + 1) }
        lineStarts = starts
    }

    // MARK: Reading

    private mutating func run() {
        while i < s.count {
            let c = s[i]
            if c == "\n" {
                endLine()
                i += 1
            } else if c == " " || c == "\t" || c == "\r" {
                i += 1
            } else if c == "/", at(i + 1) == "/" {
                while i < s.count, s[i] != "\n" { i += 1 }
            } else if c == "/", at(i + 1) == "*" {
                skipBlockComment()
            } else if c == "\"" || (c == "#" && startsRawString(at: i)) {
                readLiteral()
            } else if isWordStart(c) {
                readWord()
            } else if isDigit(c) {
                readNumber()
            } else {
                readSymbol(c)
            }
        }
    }

    private mutating func skipBlockComment() {
        var depth = 0
        while i < s.count {
            if s[i] == "/", at(i + 1) == "*" {
                depth += 1
                i += 2
            } else if s[i] == "*", at(i + 1) == "/" {
                depth -= 1
                i += 2
                if depth == 0 { return }
            } else {
                i += 1
            }
        }
    }

    private mutating func readLiteral() {
        let parsed = parseString(at: i)
        let top = frames[frames.count - 1]
        found.append(SourceLiteral(
            text: parsed.text,
            line: line(at: i),
            argumentLabel: top.kind == "(" ? top.label : nil,
            enclosingLabels: frames.reversed().compactMap { $0.kind == "(" ? $0.label : nil },
            assignedNames: assignments.map(\.name),
            isLoggerArgument: frames.contains { $0.isLogger }))
        frames[frames.count - 1].argumentStarts = false
        statementStarts = false
        remember(.literal)
        i = parsed.end
    }

    private mutating func readWord() {
        let start = i
        while i < s.count, isWordPart(s[i]) { i += 1 }
        let word = String(String.UnicodeScalarView(s[start..<i]))
        let top = frames.count - 1
        if frames[top].kind == "(", frames[top].argumentStarts, isLabelColon(at: i) {
            frames[top].label = word
        }
        frames[top].argumentStarts = false
        if case .word(let previous)? = tokens.last, previous == "let" || previous == "var" {
            let binding = Assignment(name: word, depth: frames.count)
            if bindingStartsStatement { declaration = binding } else { ignoredBinding = binding }
        }
        if word == "let" || word == "var" { bindingStartsStatement = statementStarts }
        if !Self.modifiers.contains(word), tokens.last != .symbol("@") { statementStarts = false }
        remember(.word(word))
    }

    private mutating func readNumber() {
        while i < s.count, isWordPart(s[i]) { i += 1 }
        frames[frames.count - 1].argumentStarts = false
        statementStarts = false
        remember(.number)
    }

    private mutating func readSymbol(_ c: Unicode.Scalar) {
        switch c {
        case "(", "[", "{":
            open(c)
        case ")", "]", "}":
            close()
        case ",":
            let top = frames.count - 1
            frames[top].argumentStarts = frames[top].kind == "("
            frames[top].label = nil
            assignments.removeAll { $0.depth == frames.count }
            if declaration?.depth == frames.count { declaration = nil }
            if ignoredBinding?.depth == frames.count { ignoredBinding = nil }
            remember(.symbol(c))
            i += 1
        case ";":
            assignments.removeAll { $0.depth == frames.count }
            declaration = nil
            ignoredBinding = nil
            statementStarts = true
            remember(.symbol(c))
            i += 1
        case "=":
            equals()
        default:
            frames[frames.count - 1].argumentStarts = false
            if c != "@" { statementStarts = false }
            remember(.symbol(c))
            i += 1
        }
    }

    private mutating func open(_ c: Unicode.Scalar) {
        frames[frames.count - 1].argumentStarts = false
        var isLogger = false
        if c == "(", case .word(let callee)? = tokens.last {
            if callee == "Logger" {
                isLogger = true
            } else if Self.loggerLevels.contains(callee), tokens.count >= 3,
                      tokens[tokens.count - 2] == .symbol("."),
                      case .word(let receiver) = tokens[tokens.count - 3] {
                let name = receiver.lowercased()
                isLogger = name.hasSuffix("log") || name.hasSuffix("logger")
            }
        }
        frames.append(Frame(kind: c, label: nil, argumentStarts: c == "(", isLogger: isLogger))
        statementStarts = c == "{"
        ignoredBinding = nil
        remember(.symbol(c))
        i += 1
    }

    private mutating func close() {
        if frames.count > 1 { frames.removeLast() }
        assignments.removeAll { $0.depth > frames.count }
        if let declaration, declaration.depth > frames.count { self.declaration = nil }
        statementStarts = s[i] == "}"
        remember(.symbol(s[i]))
        i += 1
    }

    /// `=` as an assignment, compound ones (`+=`) included, and not as part of
    /// `==`, `!=`, `<=` or `>=`: the symbol before a compound one is an
    /// arithmetic or logical operator, which is skipped to find the name, and
    /// the symbol before a comparison is not one of those, so no name is found.
    private mutating func equals() {
        frames[frames.count - 1].argumentStarts = false
        if at(i + 1) == "=" {
            while at(i) == "=" { i += 1 }
            remember(.symbol("="))
            return
        }
        if let ignoredBinding, ignoredBinding.depth == frames.count {
            self.ignoredBinding = nil
            remember(.symbol("="))
            i += 1
            return
        }
        var j = tokens.count - 1
        while j >= 0, case .symbol(let op) = tokens[j], "+-*/%&|^?".unicodeScalars.contains(op) { j -= 1 }
        if let declaration, declaration.depth == frames.count {
            assignments.append(Assignment(name: declaration.name, depth: frames.count))
        } else if j >= 0, case .word(let name) = tokens[j] {
            assignments.append(Assignment(name: name, depth: frames.count))
        }
        remember(.symbol("="))
        i += 1
    }

    /// A statement ends at a line's end unless the line ends in an operator or
    /// the next one starts with one.
    private mutating func endLine() {
        if continuesPastLineEnd() { return }
        assignments.removeAll { $0.depth == frames.count }
        declaration = nil
        ignoredBinding = nil
        statementStarts = true
    }

    private func continuesPastLineEnd() -> Bool {
        if case .symbol(let last)? = tokens.last, "+-*/%&|^?:,=.~".unicodeScalars.contains(last) { return true }
        var j = i + 1
        while j < s.count {
            if s[j] == " " || s[j] == "\t" || s[j] == "\n" {
                j += 1
            } else if s[j] == "/", at(j + 1) == "/" {
                while j < s.count, s[j] != "\n" { j += 1 }
            } else if s[j] == "/", at(j + 1) == "*" {
                var depth = 0
                while j < s.count {
                    if s[j] == "/", at(j + 1) == "*" {
                        depth += 1
                        j += 2
                    } else if s[j] == "*", at(j + 1) == "/" {
                        depth -= 1
                        j += 2
                        if depth == 0 { break }
                    } else {
                        j += 1
                    }
                }
            } else {
                break
            }
        }
        return j < s.count && ".+-*/%&|?:".unicodeScalars.contains(s[j])
    }

    private mutating func remember(_ token: Token) {
        tokens.append(token)
        if tokens.count > 8 { tokens.removeFirst() }
    }

    // MARK: Strings

    /// Reads the literal that starts at `start` (a quote, or the hashes before
    /// one): its body as written, and where it ends. An unterminated one ends at
    /// the end of its line, so that a broken file cannot swallow the rest.
    private func parseString(at start: Int) -> (text: String, end: Int) {
        var hashes = 0
        var j = start
        while at(j) == "#" {
            hashes += 1
            j += 1
        }
        let multiline = at(j + 1) == "\"" && at(j + 2) == "\""
        j += multiline ? 3 : 1
        let bodyStart = j
        var bodyEnd = s.count
        var end = s.count
        scanning: while j < s.count {
            let c = s[j]
            if c == "\\", hashesFollow(at: j + 1, count: hashes) {
                let after = j + 1 + hashes
                j = at(after) == "(" ? endOfInterpolation(openingAt: after) : min(after + 1, s.count)
                continue
            }
            if c == "\"" {
                if multiline {
                    if at(j + 1) == "\"", at(j + 2) == "\"", hashesFollow(at: j + 3, count: hashes) {
                        bodyEnd = j
                        end = j + 3 + hashes
                        break scanning
                    }
                } else if hashesFollow(at: j + 1, count: hashes) {
                    bodyEnd = j
                    end = j + 1 + hashes
                    break scanning
                }
            }
            if c == "\n", !multiline {
                bodyEnd = j
                end = j
                break scanning
            }
            j += 1
        }
        let raw = String(String.UnicodeScalarView(s[bodyStart..<min(max(bodyEnd, bodyStart), s.count)]))
        return (multiline ? Self.withoutIndentation(raw) : raw, end)
    }

    /// The text of a multi-line literal: what lies between its delimiter lines,
    /// less the indentation of the closing delimiter.
    private static func withoutIndentation(_ raw: String) -> String {
        var lines = raw.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.count >= 2 else { return raw }
        lines.removeFirst()
        let indentation = lines.removeLast()
        return lines
            .map { $0.hasPrefix(indentation) ? String($0.dropFirst(indentation.count)) : $0 }
            .joined(separator: "\n")
    }

    /// The index after the `)` that closes the interpolation opened at `open`.
    private func endOfInterpolation(openingAt open: Int) -> Int {
        var depth = 0
        var j = open
        while j < s.count {
            let c = s[j]
            if c == "(" {
                depth += 1
            } else if c == ")" {
                depth -= 1
                if depth == 0 { return j + 1 }
            } else if c == "\"" || (c == "#" && startsRawString(at: j)) {
                j = parseString(at: j).end
                continue
            }
            j += 1
        }
        return s.count
    }

    // MARK: Small helpers

    private func at(_ index: Int) -> Unicode.Scalar? { index >= 0 && index < s.count ? s[index] : nil }

    private func hashesFollow(at index: Int, count: Int) -> Bool {
        (0..<count).allSatisfy { at(index + $0) == "#" }
    }

    private func startsRawString(at index: Int) -> Bool {
        var j = index
        while at(j) == "#" { j += 1 }
        return j > index && at(j) == "\""
    }

    private func isLabelColon(at index: Int) -> Bool {
        var j = index
        while at(j) == " " || at(j) == "\t" { j += 1 }
        return at(j) == ":" && at(j + 1) != ":"
    }

    private func isWordStart(_ c: Unicode.Scalar) -> Bool { c == "_" || c.properties.isAlphabetic }
    private func isDigit(_ c: Unicode.Scalar) -> Bool { c.value >= 48 && c.value <= 57 }
    private func isWordPart(_ c: Unicode.Scalar) -> Bool { isWordStart(c) || isDigit(c) }

    private func line(at index: Int) -> Int {
        var low = 0
        var high = lineStarts.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if lineStarts[middle] <= index { low = middle } else { high = middle - 1 }
        }
        return low + 1
    }
}

// MARK: - The rules

/// How a file is held.
enum LiteralPolicy {
    /// A new view file: no literal but the empty string and a symbol's name.
    case strictView
    /// A controller or coordinator that shows no words, new or not: no literal at
    /// a site that shows words.
    case strictController
    /// A file that exists today: the literals it holds, each once.
    case baseline([String])
}

struct LiteralViolation: Equatable {
    enum Kind: Equatable {
        /// A literal where a strict file allows none.
        case notAllowed
        /// A literal a baseline file does not list.
        case notInBaseline
        /// A literal a baseline lists and the file no longer holds.
        case goneFromFile
    }

    let kind: Kind
    let text: String
    /// 0 for a literal that is gone.
    let line: Int
}

enum LiteralRules {
    /// The only arguments a new view may give a literal to.
    static let symbolLabelsInNewViews: Set<String> = ["systemName", "systemImage"]
    /// What a baseline file's scanner skips besides comments and the empty
    /// string: symbol names and key equivalents, which are not words.
    static let labelsSkippedInBaselines: Set<String> = ["systemName", "systemImage", "systemSymbolName", "keyEquivalent"]
    /// The sites that show words, in a new controller (Ruling 18): arguments...
    static let wordLabelsInControllers: Set<String> = ["title", "withTitle", "accessibilityDescription"]
    /// ...and assignments. `title` and `body` are here because `window.title`
    /// and `content.title` and `content.body` are how the existing files show
    /// words.
    static let wordNamesInControllers: Set<String> = ["messageText", "informativeText", "toolTip", "title", "body"]

    static func violations(in source: String, policy: LiteralPolicy) -> [LiteralViolation] {
        let literals = SwiftLiteralScanner.literals(in: source).filter { !$0.text.isEmpty }
        switch policy {
        case .strictView:
            return literals
                .filter { !symbolLabelsInNewViews.contains($0.argumentLabel ?? "") }
                .map { LiteralViolation(kind: .notAllowed, text: $0.text, line: $0.line) }
        case .strictController:
            return literals
                .filter {
                    !wordLabelsInControllers.isDisjoint(with: $0.enclosingLabels)
                        || !wordNamesInControllers.isDisjoint(with: $0.assignedNames)
                }
                .map { LiteralViolation(kind: .notAllowed, text: $0.text, line: $0.line) }
        case .baseline(let listed):
            let known = Set(listed)
            var held = Set<String>()
            var violations: [LiteralViolation] = []
            for literal in literals where !isSkippedInBaselines(literal) {
                held.insert(literal.text)
                if !known.contains(literal.text) {
                    violations.append(LiteralViolation(kind: .notInBaseline, text: literal.text, line: literal.line))
                }
            }
            for text in listed where !held.contains(text) {
                violations.append(LiteralViolation(kind: .goneFromFile, text: text, line: 0))
            }
            return violations
        }
    }

    private static func isSkippedInBaselines(_ literal: SourceLiteral) -> Bool {
        literal.isLoggerArgument || labelsSkippedInBaselines.contains(literal.argumentLabel ?? "")
    }

    /// The failure message for a violation, which says what to do about it.
    static func message(_ violation: LiteralViolation, in file: String) -> String {
        switch violation.kind {
        case .notAllowed:
            return "\(file):\(violation.line) holds the literal \"\(violation.text)\" where this file may hold none. "
                + "Its words belong in a text enum in NotificationCore (Ruling 18)."
        case .notInBaseline:
            return "\(file):\(violation.line) holds the literal \"\(violation.text)\", which the file's baseline does "
                + "not list. Its words belong in a text enum in NotificationCore (Ruling 18); a baseline only shrinks."
        case .goneFromFile:
            return "\(file)'s baseline lists the literal \"\(violation.text)\", which the file no longer holds. "
                + "Take it out of the list: a baseline only shrinks, and slack in it hides a literal added later."
        }
    }
}

// MARK: - The app's sources, and how each is held

enum AppSources {
    static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // NotificationCoreTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // package root
        .appendingPathComponent("Sources/SignalLadder")

    /// A source file's text, or nil when there is no such file.
    static func read(_ name: String) -> String? {
        try? String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
    }

    static func fileNames() throws -> [String] {
        try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .map(\.lastPathComponent)
            .filter { $0.hasSuffix(".swift") }
            .sorted()
    }
}

enum HeldFiles {
    /// New view files. Each is named before it exists, so the day it is written
    /// it is already held; a name with no file is skipped, not failed.
    static let strictViews = [
        "LadderEditorView.swift",     // Task 1
        "OnCallCheckView.swift",      // Task 2
        "SettingsView.swift",         // Task 6
        "SetupView.swift",            // Task 8
    ]

    /// New controllers and coordinators, named before they exist as the views are.
    static let strictControllers = [
        "OnCallCheckWindowController.swift",   // Task 2
        "SettingsWindowController.swift",      // Task 6
        "SetupWindowController.swift",         // Task 8
        "SetupCoordinator.swift",              // Task 8
    ]

    /// View files that exist today and that a task changes, with the literals
    /// each holds today, written as they stand in the source (an interpolation
    /// as typed, a raw string so that a backslash is one). The lists are those of
    /// a207d0d, less what a task has since moved out. A symbol's name, a key
    /// equivalent, a logger's argument and the empty string are not listed, since
    /// the scanner does not count them. Nothing is added; a task that moves one
    /// out removes it.
    static let baselineViews: [(file: String, literals: [String])] = [
        ("AlertEditorView.swift", [
            #"x-apple.systempreferences:com.apple.Accessibility-Settings.extension?SpokenContent"#,
            #"No Alert"#,
            #"Silent"#,
            #"Sound"#,
            #"Speech"#,
            #"Also speak it"#,
            #"\(name) (not found)"#,
            #"Test Sound"#,
            #"Voice"#,
            #"\(speech.voiceIdentifier) (not installed)"#,
            #"\($0.name) — \($0.language)"#,
            #"More Voices…"#,
            #"Says"#,
            #"Test Speech"#,
            #"Rate"#,
            #"Pitch"#,
            #"Speech gain"#,
            #"Gain"#,
            #"%.2f"#,
        ]),
        ("RuleDetailView.swift", [
            #"Rule name"#,
            #"On"#,
            #"When a notification matches"#,
            #"Add Condition"#,
            #"Add Condition from This Notification"#,
            #"Then"#,
            #"Tried on recent notifications"#,
        ]),
        ("RuleEditorView.swift", [
            #"Revert"#,
            #"Save"#,
            #"s"#,
            #"Duplicate"#,
            #"Delete"#,
            #"Add a rule"#,
            #"Delete the selected rule"#,
            #"Top rule wins"#,
            #"Drag to change priority"#,
            #"On — switch off"#,
            #"Off — switch on"#,
            #"Unnamed rule"#,
            #"This rule has problems and will not run"#,
            #"Open Rules File in Text Editor"#,
            #"Select a rule to edit it."#,
            #"Add a Rule by Hand"#,
        ]),
        ("ConditionBuilderView.swift", [
            #"Not"#,
            #"Remove “Not”"#,
            #"All of these"#,
            #"Any of these"#,
            #"Add Condition"#,
            #"Add “Any of” Group"#,
            #"Add “All of” Group"#,
            #"Negate Group"#,
            #"Ungroup"#,
            #"Remove Group"#,
            #"Empty — add a condition."#,
            #"value"#,
            #"Negate"#,
            #"Group with “All of”"#,
            #"Group with “Any of”"#,
            #"Remove"#,
        ]),
        ("InspectorView.swift", [
            #"HH:mm:ss"#,
            #"(no app name)"#,
            #"Make a Rule from This…"#,
            #"\(entry.suppressedRepeatCount) suppressed"#,
            #"Said: “\(said)”"#,
            #"Raw"#,
            #"(empty description)"#,
        ]),
        ("DryRunView.swift", [
            #"HH:mm:ss"#,
            #"(unknown app)"#,
            #"— taken by “\(name)”"#,
        ]),
    ]

    /// Other files of the app target that show words, held the same way: the
    /// seven Ruling 18 names, and two that a search of the target's sources
    /// found, `InspectorModel` (the Inspector's first health line) and
    /// `PowerAssertion` (the reason the system shows for holding the Mac awake).
    /// What else the search found shows no words: `AppLocator` holds paths and
    /// property-list keys, `RuleStore` the folder's and the file's names, and
    /// `RunLoopEscalationScheduler` and `main` hold no literal; the three
    /// controllers among them are named below.
    static let baselineOthers: [(file: String, literals: [String])] = [
        ("AppDelegate.swift", [
            #"bell.slash.fill"#,
            #"SignalLadder — problem"#,
            #"bell.and.waves.left.and.right.fill"#,
            #"bell.and.waves.left.and.right"#,
            #"SignalLadder — alert escalating"#,
            #"bell.badge"#,
            #"SignalLadder"#,
            #"Captured \(count) notification\(count == 1 ? "" : "s")"#,
            #"Show Inspector…"#,
            #"Quit SignalLadder"#,
            #"Current rules match \(pipeline.currentRuleMatchCount) of the last \(pipeline.history.count)"#,
            #"Edit Rules…"#,
            #"Open Rules File in Text Editor…"#,
            #"Reload Rules"#,
            #"HH:mm"#,
        ]),
        ("HealthAlarm.swift", [
            #"signalladder.health"#,
        ]),
        ("MainMenu.swift", [
            #"Edit"#,
            #"Undo"#,
            #"undo:"#,
            #"Redo"#,
            #"redo:"#,
            #"Cut"#,
            #"Copy"#,
            #"Paste"#,
            #"Delete"#,
            #"Select All"#,
        ]),
        ("MuteWalkthroughMenu.swift", []),
        ("InspectorWindowController.swift", []),
        ("RuleEditorWindowController.swift", [
            #"\n\n"#,
            #"Reload from Disk"#,
            #"Save Anyway"#,
            #"Cancel"#,
            #"The rules could not be saved."#,
            #"\(reason)\n\nNothing was changed: rules.json is as it was, and your draft is still here."#,
            #"Save"#,
            #"Don't Save"#,
        ]),
        ("RuleEditorModel.swift", [
            #"New rule"#,
            #" (copy)"#,
            #"Glass"#,
        ]),
        ("InspectorModel.swift", [
            #"Checking…"#,
        ]),
        ("PowerAssertion.swift", [
            #"An alert is still escalating"#,
        ]),
    ]

    /// Controllers and coordinators that exist today and show no words: what
    /// literals they hold are property-list keys, paths, URLs and log messages.
    /// They are not held to a baseline, because a literal they hold is not a
    /// word, and a rule that nothing is added to them would be one for the wrong
    /// reason. They are held as a new controller is, so that an alert's title or
    /// message, a menu title or a tooltip added to one of them fails: each file
    /// is read under `.strictController`, and each value says why it holds none
    /// today.
    static let strictControllersToday: [String: String] = [
        "CaptureController.swift": "holds the property-list keys of the app's own name",
        "HotKeyController.swift": "holds a logger's subsystem and messages",
        "OnboardingCoordinator.swift": "holds the URLs of two System Settings panes",
    ]
}

// MARK: - Tests

final class ViewLiteralsTests: XCTestCase {
    // MARK: Reading source

    private func texts(_ source: String) -> [String] {
        SwiftLiteralScanner.literals(in: source).map(\.text)
    }

    /// The constructors and modifiers that show words in a SwiftUI view, each
    /// with a literal in it, and the literals the scanner should read from it.
    private let wordsInViews: [(name: String, source: String, literals: [String])] = [
        ("Text", #"Text("Hello")"#, ["Hello"]),
        ("Button", #"Button("Save") { save() }"#, ["Save"]),
        ("Label", #"Label("Rules", systemImage: "list.bullet")"#, ["Rules", "list.bullet"]),
        ("Toggle", #"Toggle("On", isOn: $isOn)"#, ["On"]),
        ("Picker", #"Picker("Sound", selection: $sound) { Text(name).tag(name) }"#, ["Sound"]),
        ("Section", #"Section("Then") { content }"#, ["Then"]),
        ("TextField", #"TextField("Rule name", text: $name)"#, ["Rule name"]),
        ("DisclosureGroup", #"DisclosureGroup("Raw", isExpanded: $open) { raw }"#, ["Raw"]),
        ("Menu", #"Menu("Add Condition from This Notification") { items }"#, ["Add Condition from This Notification"]),
        ("LabeledContent", #"LabeledContent("Interval", value: text)"#, ["Interval"]),
        (".help", #"Image(systemName: "plus").help("Add a rule")"#, ["plus", "Add a rule"]),
        (".accessibilityLabel", #"row.accessibilityLabel("Repeat limit")"#, ["Repeat limit"]),
        (".accessibilityHint", #"row.accessibilityHint("Double-tap to change it")"#, ["Double-tap to change it"]),
        ("Text(verbatim:)", #"Text(verbatim: "Plain words")"#, ["Plain words"]),
    ]

    func testTheScannerFindsALiteralInEveryConstructorThatShowsWords() {
        for (name, source, literals) in wordsInViews {
            XCTAssertEqual(texts(source), literals, "\(name): \(source)")
        }
    }

    func testTheScannerFindsAnInterpolatedLiteralWhole() {
        XCTAssertEqual(texts(#"Text("\(count) alerts")"#), [#"\(count) alerts"#])
        XCTAssertEqual(texts(#"Text("a \(b) c \(d)")"#), [#"a \(b) c \(d)"#])
        // A literal inside the interpolation is part of the one that holds it,
        // and its quotes and parentheses do not end it early.
        XCTAssertEqual(texts(#"Text("Captured \(n) notification\(n == 1 ? "" : "s")")"#),
                       [#"Captured \(n) notification\(n == 1 ? "" : "s")"#])
        XCTAssertEqual(texts(#"Text("\(f("(")) then more")"#), [#"\(f("(")) then more"#])
        XCTAssertEqual(texts(#"Text("a") ; Text("b")"#), ["a", "b"], "the next literal is still found")
    }

    func testTheScannerFindsAMultiLineLiteral() {
        let source = """
        let help = Text(\"\"\"
            First line
              indented \\(name) and a "quote"
            Last line
            \"\"\")
        let after = "next"
        """
        XCTAssertEqual(texts(source), ["First line\n  indented \\(name) and a \"quote\"\nLast line", "next"])
        XCTAssertEqual(SwiftLiteralScanner.literals(in: source).map(\.line), [1, 6],
                       "a literal's line is the line of its opening quotes")
    }

    func testTheScannerReadsRawStringsAndEscapedQuotes() {
        XCTAssertEqual(texts(#"Text("say \"hi\" now")"#), [#"say \"hi\" now"#], "an escaped quote does not end it")
        XCTAssertEqual(texts(##"Text(#"a "quoted" \#(x) word"#)"##), [##"a "quoted" \#(x) word"##])
        XCTAssertEqual(texts(##"Text(#"\n is not an escape here"#); Text("b")"##),
                       [#"\n is not an escape here"#, "b"])
        XCTAssertEqual(texts(#"Text("back\\") ; Text("c")"#), [#"back\\"#, "c"], "an escaped backslash ends cleanly")
    }

    func testTheScannerSkipsComments() {
        let source = """
        // Text("in a line comment")
        /// Text("in a doc comment")
        /* Text("in a block comment") */
        /* outer /* Text("in a nested one") */ still a comment: Text("here too") */
        Text("held") // Text("after it")
        /* one
           Text("across lines") */ Text("then another")
        """
        XCTAssertEqual(texts(source), ["held", "then another"])
    }

    func testAnythingThatLooksLikeACommentInsideALiteralIsPartOfIt() {
        XCTAssertEqual(texts(#"let url = "http://example.com/a"; let b = "/* not a comment */""#),
                       ["http://example.com/a", "/* not a comment */"])
        XCTAssertEqual(texts(#"Text("a") // "b""#), ["a"], "a quote inside a comment opens nothing")
    }

    func testTheScannerReportsTheLineOfEachLiteral() {
        let source = "let a = \"one\"\n\nText(\n    \"two\"\n)\nlet c = \"three\" /* \"four\" */\n"
        XCTAssertEqual(SwiftLiteralScanner.literals(in: source).map(\.line), [1, 4, 6])
    }

    func testAnUnterminatedLiteralDoesNotSwallowTheRestOfTheFile() {
        XCTAssertEqual(texts("let a = \"never closed\nText(\"next\")\n"), ["never closed", "next"])
        XCTAssertEqual(texts("Text(\"\\(x"), [#"\(x"#], "an interpolation that never closes ends at the end of the file")
    }

    // MARK: Where a literal stands

    func testALiteralKnowsTheLabelOfTheArgumentItIsIn() {
        func labels(_ source: String) -> [String?] { SwiftLiteralScanner.literals(in: source).map(\.argumentLabel) }
        XCTAssertEqual(labels(#"Label("Rules", systemImage: "list")"#), [nil, "systemImage"])
        XCTAssertEqual(labels(#"Label(title, systemImage: ok ? "a" : "b")"#), ["systemImage", "systemImage"],
                       "both branches of a conditional are in the argument")
        XCTAssertEqual(labels(#"Image(systemName: "bell")"#), ["systemName"])
        XCTAssertEqual(labels("Label(\n    t,\n    systemImage: \"bell\"\n)"), ["systemImage"])
        XCTAssertEqual(labels(#"menu.addItem(withTitle: "Quit", action: nil, keyEquivalent: "q")"#),
                       ["withTitle", "keyEquivalent"])
        XCTAssertEqual(labels(#"let x = "plain""#), [nil])
        XCTAssertEqual(labels(#"Button("Go", action: { f(systemName: "inner") })"#), [nil, "systemName"])
        XCTAssertEqual(labels(#"Rule(name: "a", c: .blank)"#), ["name"])
        XCTAssertEqual(labels(#"Picker("", selection: b) { Text("x") }"#), [nil, nil],
                       "a label belongs to its own argument, not to the call's closure")
        XCTAssertEqual(labels(#"f(a: "one", "two")"#), ["a", nil], "a comma ends the argument and its label")
        XCTAssertEqual(labels(#"f(x == y ? "a" : "b")"#), [nil, nil], "a conditional's colon is not a label")
    }

    func testALiteralKnowsEveryLabelItIsInside() {
        let literal = SwiftLiteralScanner.literals(in: #"NSMenuItem(title: pick(index, "x"), action: nil)"#)
        XCTAssertEqual(literal.map(\.text), ["x"])
        XCTAssertEqual(literal.first?.enclosingLabels, ["title"], "an argument of a call inside `title:` is at that site")
        XCTAssertNil(literal.first?.argumentLabel)
    }

    func testALiteralKnowsWhatItsStatementAssigns() {
        func assigned(_ source: String) -> [[String]] { SwiftLiteralScanner.literals(in: source).map(\.assignedNames) }
        XCTAssertEqual(assigned(#"window.title = "Rules""#), [["title"]])
        XCTAssertEqual(assigned(#"alert.informativeText = ok ? "A" : "B""#), [["informativeText"], ["informativeText"]])
        XCTAssertEqual(assigned(#"content.body = advice ?? "Open the menu""#), [["body"]])
        XCTAssertEqual(assigned(#"alert.informativeText = detail(change) + "\n\n" + note"#), [["informativeText"]])
        XCTAssertEqual(assigned(#"button.toolTip += "more""#), [["toolTip"]], "a compound assignment is an assignment")
        XCTAssertEqual(assigned(#"let title = "x""#), [["title"]])
        XCTAssertEqual(assigned(#"var title: String = "x""#), [["title"]], "the name, not the type")
        XCTAssertEqual(assigned(#"if title == "x" { }"#), [[]], "a comparison assigns nothing")
        XCTAssertEqual(assigned(#"if a != "x" || b <= "y" || c >= "z" { }"#), [[], [], []])
        XCTAssertEqual(assigned(#"f(title: "x")"#), [[]], "an argument is not an assignment")
        XCTAssertEqual(assigned("window.title = \"A\"\nlet other = \"B\"\nf(\"C\")"), [["title"], ["other"], []],
                       "a statement ends at the end of its line")
        XCTAssertEqual(assigned("alert.messageText = first\n    + \"A\"\n    + \"B\"\nf(\"C\")"), [["messageText"], ["messageText"], []],
                       "a line that starts with an operator continues the statement")
        XCTAssertEqual(assigned("alert.messageText = first +\n    \"A\"\nf(\"C\")"), [["messageText"], []],
                       "a line that ends in an operator continues it")
        XCTAssertEqual(assigned("alert.messageText = text(\n    \"A\",\n    b: \"B\"\n)\nf(\"C\")"),
                       [["messageText"], ["messageText"], []], "a call spread over lines is one statement")
        XCTAssertEqual(assigned(#"let a = "x", b = "y""#), [["a"], ["b"]], "a comma ends an assignment")
        XCTAssertEqual(assigned(#"a.title = "x"; f("y")"#), [["title"], []], "so does a semicolon")
        XCTAssertEqual(assigned(#"private static let title = "x""#), [["title"]], "a modifier does not hide the declaration")
        XCTAssertEqual(assigned(#"@Published var body: String = "x""#), [["body"]], "nor does an attribute")
        XCTAssertEqual(assigned(#"if let title = info.title { f("x") }"#), [[]], "a binding in a condition is not an assignment")
        XCTAssertEqual(assigned(#"guard let body = note.body else { return "fallback" }"#), [[]])
        XCTAssertEqual(assigned(#"if ok, let title = info.title, let body = info.body { f("x") }"#), [[]])
        XCTAssertEqual(assigned("if let title = info.title {\n    f(\"x\")\n}\nwindow.title = \"y\""), [[], ["title"]],
                       "the assignment after the block is still one")
    }

    func testALiteralKnowsWhetherItIsALoggerArgument() {
        func logger(_ source: String) -> [Bool] { SwiftLiteralScanner.literals(in: source).map(\.isLoggerArgument) }
        XCTAssertEqual(logger(#"static let log = Logger(subsystem: "com.example", category: "hotkey")"#), [true, true])
        XCTAssertEqual(logger(#"Self.log.error("could not register \(status, privacy: .public)")"#), [true])
        XCTAssertEqual(logger(#"logger.info("started"); log.debug("again")"#), [true, true])
        XCTAssertEqual(logger(#"alert.error("not a logger"); title.error("nor this")"#), [false, false],
                       "a method called error on something that is not a log is not a logger call")
        XCTAssertEqual(logger(#"Self.log.error("a"); Text("b")"#), [true, false], "the call ends where it closes")
    }

    // MARK: Strict mode: a new view

    private func strictView(_ source: String) -> [String] {
        LiteralRules.violations(in: source, policy: .strictView).map(\.text)
    }

    func testStrictModeAcceptsASymbolAndTheEmptyString() {
        XCTAssertEqual(strictView(#"Image(systemName: "bell")"#), [])
        XCTAssertEqual(strictView(#"Label(title, systemImage: "bell")"#), [])
        XCTAssertEqual(strictView(#"Label(title, systemImage: ok ? "bell" : "bell.slash")"#), [])
        XCTAssertEqual(strictView(#"Picker("", selection: $kind) { content }"#), [])
        XCTAssertEqual(strictView(#"Toggle("", isOn: $on)"#), [])
        XCTAssertEqual(strictView("let none = \"\"\n"), [])
    }

    func testStrictModeRefusesEveryOtherLiteral() {
        for (name, source, literals) in wordsInViews {
            let words = literals.filter { !["list.bullet", "plus"].contains($0) }
            XCTAssertEqual(strictView(source), words, "\(name): \(source)")
        }
        XCTAssertEqual(strictView(#"Text("\(count) alerts")"#), [#"\(count) alerts"#], "an interpolated one")
        XCTAssertEqual(strictView("Text(\"\"\"\n    two\n    lines\n    \"\"\")"), ["two\nlines"], "a multi-line one")
        XCTAssertEqual(strictView(#"Text(ok ? "Yes" : "No")"#), ["Yes", "No"], "a conditional of words")
        XCTAssertEqual(strictView(#"Text(name + " (copy)")"#), [" (copy)"], "a fragment of words")
        XCTAssertEqual(strictView(#"let title = "Rules""#), ["Rules"], "a constant that holds words")
        XCTAssertEqual(strictView(#"Image("photo")"#), ["photo"], "an image by name is not a symbol")
        XCTAssertEqual(strictView(#"Image(systemName: "bell").help("Alerts")"#), ["Alerts"], "a symbol beside words")
        XCTAssertEqual(strictView(#"f(systemNames: "x")"#), ["x"], "only the two labels are allowed, whole")
        XCTAssertEqual(strictView(#"Image(systemName: icon("words"))"#), ["words"], "a literal beside a symbol, not in it")
        XCTAssertEqual(strictView(#"Button("Go", action: { Image(systemName: "bell") })"#), ["Go"])
        XCTAssertEqual(strictView(#"Text("a") // Text("b")"#), ["a"], "a comment is skipped")
    }

    // MARK: Baseline mode

    func testBaselineRefusesALiteralThatIsNotListedAndAcceptsEachThatIs() {
        let source = #"""
        Text("Rules")
        Button("Save") { }
        Text("Rules")
        let none = ""
        """#
        let both = LiteralRules.violations(in: source, policy: .baseline(["Rules", "Save"]))
        XCTAssertEqual(both, [], "a listed literal is accepted wherever it stands, however often")

        XCTAssertEqual(LiteralRules.violations(in: source, policy: .baseline(["Rules"])),
                       [LiteralViolation(kind: .notInBaseline, text: "Save", line: 2)])
        XCTAssertEqual(LiteralRules.violations(in: source, policy: .baseline(["Save"])),
                       [LiteralViolation(kind: .notInBaseline, text: "Rules", line: 1),
                        LiteralViolation(kind: .notInBaseline, text: "Rules", line: 3)])
        XCTAssertEqual(LiteralRules.violations(in: source + "\nText(\"New words\")", policy: .baseline(["Rules", "Save"])),
                       [LiteralViolation(kind: .notInBaseline, text: "New words", line: 5)])
        XCTAssertEqual(LiteralRules.violations(in: "", policy: .baseline([])), [])
    }

    func testBaselineRefusesAListedLiteralThatTheFileNoLongerHolds() {
        XCTAssertEqual(LiteralRules.violations(in: #"Text("Rules")"#, policy: .baseline(["Rules", "Gone"])),
                       [LiteralViolation(kind: .goneFromFile, text: "Gone", line: 0)])
        // One that is held only where baselines skip is not held.
        XCTAssertEqual(LiteralRules.violations(in: #"Image(systemName: "bell")"#, policy: .baseline(["bell"])),
                       [LiteralViolation(kind: .goneFromFile, text: "bell", line: 0)])
    }

    func testBaselineSkipsCommentsSymbolNamesKeyEquivalentsAndLoggerArguments() {
        let source = #"""
        // Text("in a comment")
        Image(systemName: "bell")
        Label(title, systemImage: ok ? "a.fill" : "b.fill")
        NSImage(systemSymbolName: "bell.slash", accessibilityDescription: description)
        menu.addItem(withTitle: line, action: nil, keyEquivalent: ",")
        static let log = Logger(subsystem: "com.example", category: "capture")
        Self.log.error("the hotkey could not be registered: \(status, privacy: .public)")
        let empty = ""
        """#
        XCTAssertEqual(LiteralRules.violations(in: source, policy: .baseline([])), [])
    }

    func testBaselineReadsEveryOtherLiteralWhateverItIsFor() {
        let source = #"""
        let key = "confirmedMutedAppDigests"
        window.title = "SignalLadder Inspector"
        (symbol, description) = ("bell.slash.fill", "SignalLadder — problem")
        menu.addItem(withTitle: "Quit", action: nil, keyEquivalent: "q")
        let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!
        """#
        XCTAssertEqual(
            LiteralRules.violations(in: source, policy: .baseline([])).map(\.text),
            ["confirmedMutedAppDigests", "SignalLadder Inspector", "bell.slash.fill", "SignalLadder — problem", "Quit",
             "x-apple.systempreferences:com.apple.Notifications-Settings.extension"])
    }

    // MARK: Strict mode: a new controller or coordinator

    private func strictController(_ source: String) -> [String] {
        LiteralRules.violations(in: source, policy: .strictController).map(\.text)
    }

    /// Each site of Ruling 18 that shows words in a controller, with a statement
    /// that puts one literal there.
    private let sitesThatShowWords: [(site: String, source: String)] = [
        ("title:", #"NSMenuItem(title: "Quit", action: nil, keyEquivalent: "")"#),
        ("withTitle:", #"menu.addItem(withTitle: "Quit", action: nil, keyEquivalent: "")"#),
        ("withTitle: on a button", #"alert.addButton(withTitle: "Cancel")"#),
        ("accessibilityDescription:", #"NSImage(systemSymbolName: s, accessibilityDescription: "Alert")"#),
        ("messageText", #"alert.messageText = "Quit while on call?""#),
        ("informativeText", #"alert.informativeText = "Alerts stop.""#),
        ("toolTip", #"item.button?.toolTip = "SignalLadder""#),
        ("title", #"window.title = "SignalLadder Settings""#),
        ("body", #"content.body = "Open the menu.""#),
    ]

    func testStrictModeRefusesALiteralAtEachSiteThatShowsWordsInAController() {
        for (site, source) in sitesThatShowWords {
            XCTAssertEqual(strictController(source).count, 1, "\(site): \(source)")
        }
        XCTAssertEqual(strictController(#"content.body = advice ?? "Open the menu for details.""#),
                       ["Open the menu for details."], "a fallback is at the site too")
        XCTAssertEqual(strictController(#"alert.informativeText = detail(change) + "\n\n" + note"#), [#"\n\n"#])
        XCTAssertEqual(strictController(#"alert.messageText = ok ? "A" : "B""#), ["A", "B"])
        XCTAssertEqual(strictController(#"menu.addItem(withTitle: pick(count, "s"), action: nil, keyEquivalent: "")"#),
                       ["s"], "a literal in an argument of a call that is itself the title")
        XCTAssertEqual(strictController(#"alert.messageText = "\(count) alerts""#), [#"\(count) alerts"#])
        XCTAssertEqual(strictController("alert.messageText = QuitPolicy.title\nalert.informativeText = QuitPolicy.detail"), [],
                       "words from a text enum are what a controller shows")
    }

    func testStrictModeLeavesAControllerFreeToHoldLiteralsThatAreNotWords() {
        let source = #"""
        static let key = "snoozeUntil"
        let identifier = "signalladder.health"
        menu.addItem(withTitle: text.title, action: nil, keyEquivalent: ",")
        NSImage(systemSymbolName: "bell", accessibilityDescription: text.description)
        static let log = Logger(subsystem: "com.example", category: "capture")
        Self.log.error("could not register")
        alert.messageText = ""
        window.title = ""
        defaults.set(true, forKey: "wanted")
        // window.title = "in a comment"
        """#
        XCTAssertEqual(strictController(source), [])
    }

    // MARK: The controllers that exist today

    func testTheControllersThatShowNoWordsAreHeldAsANewControllerIs() {
        XCTAssertFalse(HeldFiles.strictControllersToday.isEmpty)
        for file in HeldFiles.strictControllersToday.keys.sorted() {
            check(file, policy: .strictController)
        }
        XCTAssertTrue(Set(HeldFiles.strictControllersToday.keys).isDisjoint(with: HeldFiles.strictControllers),
                      "a file is held by one controller list and not two")
    }

    func testAWordAddedToAControllerThatShowsNoneIsRefusedAtEachSite() throws {
        for file in HeldFiles.strictControllersToday.keys.sorted() {
            let source = try XCTUnwrap(AppSources.read(file), file)
            XCTAssertEqual(LiteralRules.violations(in: source, policy: .strictController), [], "\(file) as it is")
            for (site, added) in sitesThatShowWords {
                XCTAssertEqual(
                    LiteralRules.violations(in: source + "\n" + added, policy: .strictController).count, 1,
                    "\(file) with a literal added at \(site)")
            }
            // A literal that is not words is still free, in the files as they stand.
            let key = source + "\ndefaults.set(true, forKey: \"addedLater\")\n"
            XCTAssertEqual(LiteralRules.violations(in: key, policy: .strictController), [], "\(file) with a key added")
        }
    }

    // MARK: The files themselves

    private func check(_ file: String, policy: LiteralPolicy, filePath: StaticString = #filePath, line: UInt = #line) {
        guard let source = AppSources.read(file) else {
            return XCTFail("\(file) is held and cannot be read at \(AppSources.directory.path)", file: filePath, line: line)
        }
        for violation in LiteralRules.violations(in: source, policy: policy) {
            XCTFail(LiteralRules.message(violation, in: file), file: filePath, line: line)
        }
    }

    func testTheAppSourcesAreFound() throws {
        XCTAssertGreaterThan(try AppSources.fileNames().count, 10, "found no sources at \(AppSources.directory.path)")
    }

    func testTheViewFilesHoldTheLiteralsTheirBaselinesList() {
        XCTAssertFalse(HeldFiles.baselineViews.isEmpty)
        for (file, literals) in HeldFiles.baselineViews {
            check(file, policy: .baseline(literals))
        }
    }

    func testTheAppTargetsOtherFilesHoldTheLiteralsTheirBaselinesList() {
        XCTAssertFalse(HeldFiles.baselineOthers.isEmpty)
        for (file, literals) in HeldFiles.baselineOthers {
            check(file, policy: .baseline(literals))
        }
    }

    func testEveryBaselineListsEachLiteralOnceAndNoneThatIsEmpty() {
        for (file, literals) in HeldFiles.baselineViews + HeldFiles.baselineOthers {
            XCTAssertEqual(literals.count, Set(literals).count, "\(file)'s baseline lists a literal twice")
            XCTAssertFalse(literals.contains(""), "\(file)'s baseline lists the empty string, which is never held")
        }
        let files = (HeldFiles.baselineViews + HeldFiles.baselineOthers).map(\.file)
        XCTAssertEqual(files.count, Set(files).count, "a file has two baselines")
    }

    func testTheNewFilesAreHeldWhenTheyExistAndSkippedWhenTheyDoNot() {
        let held = HeldFiles.strictViews + HeldFiles.strictControllers
        XCTAssertEqual(held.count, Set(held).count)
        for file in HeldFiles.strictViews { checkIfPresent(file, policy: .strictView) }
        for file in HeldFiles.strictControllers { checkIfPresent(file, policy: .strictController) }

        // A name with no file fails nothing; the same name with a file that holds
        // words fails.
        XCTAssertNil(AppSources.read("NoSuchViewAnywhere.swift"))
        XCTAssertEqual(violationsIfPresent(nil, policy: .strictView), [])
        XCTAssertEqual(violationsIfPresent(#"Text("Words")"#, policy: .strictView).map(\.text), ["Words"])
    }

    func testTheStrictListsNameTheNewViewsAndControllersTheMilestoneAdds() {
        XCTAssertTrue(HeldFiles.strictViews.contains("LadderEditorView.swift"))
        for view in ["OnCallCheckView.swift", "SettingsView.swift", "SetupView.swift"] {
            XCTAssertTrue(HeldFiles.strictViews.contains(view), view)
        }
        for controller in ["OnCallCheckWindowController.swift", "SettingsWindowController.swift",
                           "SetupWindowController.swift", "SetupCoordinator.swift"] {
            XCTAssertTrue(HeldFiles.strictControllers.contains(controller), controller)
        }
    }

    private func violationsIfPresent(_ source: String?, policy: LiteralPolicy) -> [LiteralViolation] {
        guard let source else { return [] }
        return LiteralRules.violations(in: source, policy: policy)
    }

    private func checkIfPresent(_ file: String, policy: LiteralPolicy, filePath: StaticString = #filePath, line: UInt = #line) {
        for violation in violationsIfPresent(AppSources.read(file), policy: policy) {
            XCTFail(LiteralRules.message(violation, in: file), file: filePath, line: line)
        }
    }

    func testEveryViewAndControllerOfTheAppIsHeldByOneRuleOrOther() throws {
        var heldBy: [String: String] = [:]
        for file in HeldFiles.strictViews { heldBy[file] = "a strict view" }
        for file in HeldFiles.strictControllers { heldBy[file] = "a strict controller" }
        for held in HeldFiles.baselineViews { heldBy[held.file] = "a baseline" }
        for held in HeldFiles.baselineOthers { heldBy[held.file] = "a baseline" }
        for file in HeldFiles.strictControllersToday.keys { heldBy[file] = "a strict controller" }
        for file in try AppSources.fileNames() where Self.isViewOrController(file) {
            XCTAssertNotNil(heldBy[file],
                            "\(file) is a view or a controller and no list in HeldFiles holds it: a new one belongs "
                                + "in strictViews or strictControllers (Ruling 18)")
        }
        let files = Set(try AppSources.fileNames())
        for file in HeldFiles.strictControllersToday.keys {
            XCTAssertTrue(files.contains(file), "\(file) is listed as a controller that shows no words, and is gone")
        }
        for file in HeldFiles.baselineViews.map(\.file) + HeldFiles.baselineOthers.map(\.file) {
            XCTAssertTrue(files.contains(file), "\(file) has a baseline and is gone: take its baseline out")
        }
    }

    private static func isViewOrController(_ file: String) -> Bool {
        ["View.swift", "Controller.swift", "Coordinator.swift"].contains { file.hasSuffix($0) }
    }

    // MARK: Adding a literal is seen to fail

    private func baseline(of file: String) -> [String] {
        (HeldFiles.baselineViews + HeldFiles.baselineOthers).first { $0.file == file }?.literals ?? []
    }

    func testAddingALiteralToAnyBaselineFileIsRefused() throws {
        let files = (HeldFiles.baselineViews + HeldFiles.baselineOthers).map(\.file)
        XCTAssertFalse(files.isEmpty)
        for file in files {
            let source = try XCTUnwrap(AppSources.read(file), file)
            let listed = baseline(of: file)
            XCTAssertEqual(LiteralRules.violations(in: source, policy: .baseline(listed)), [], "\(file) as it is")

            let added = source + "\nlet addedLater = Text(\"Words added after the baseline\")\n"
            XCTAssertEqual(LiteralRules.violations(in: added, policy: .baseline(listed)).map(\.text),
                           ["Words added after the baseline"], "\(file) with a literal added")
        }
    }

    func testAMenuTitleAddedToTheAppDelegateIsRefused() throws {
        let source = try XCTUnwrap(AppSources.read("AppDelegate.swift"))
        let listed = baseline(of: "AppDelegate.swift")
        XCTAssertFalse(listed.isEmpty, "the AppDelegate is held to a baseline")

        let anchor = "menu.addItem(NSMenuItem(title: \"Quit SignalLadder\","
        XCTAssertTrue(source.contains(anchor), "the quit item is where this test adds a neighbour")
        let added = source.replacingOccurrences(
            of: anchor,
            with: "menu.addItem(withTitle: \"Snooze\", action: nil, keyEquivalent: \"\")\n        " + anchor)
        XCTAssertEqual(LiteralRules.violations(in: added, policy: .baseline(listed)).map(\.text), ["Snooze"])
    }

    func testTheQuitPromptsWordsTypedBackIntoTheAppDelegateAreRefused() throws {
        // The alert's two buttons and its sentences are QuitPolicy's. The
        // baseline lost "Cancel" and "Quit" when they moved there, so typing
        // either back, or a sentence beside them, fails.
        let source = try XCTUnwrap(AppSources.read("AppDelegate.swift"))
        let listed = baseline(of: "AppDelegate.swift")
        XCTAssertFalse(listed.contains("Cancel"))
        XCTAssertFalse(listed.contains("Quit"))

        let buttons = "for title in QuitPolicy.buttonTitles { ask.addButton(withTitle: title) }"
        XCTAssertTrue(source.contains(buttons), "the buttons are added from QuitPolicy's titles")
        let typedBack = source.replacingOccurrences(
            of: buttons,
            with: "ask.addButton(withTitle: \"Cancel\")\n        ask.addButton(withTitle: \"Quit\")")
        XCTAssertEqual(LiteralRules.violations(in: typedBack, policy: .baseline(listed)).map(\.text), ["Cancel", "Quit"])

        let sentence = "ask.messageText = prompt.message"
        XCTAssertTrue(source.contains(sentence), "the alert's sentence is the prompt's")
        let typedSentence = source.replacingOccurrences(of: sentence, with: "ask.messageText = \"You are on call. Quit anyway?\"")
        XCTAssertEqual(LiteralRules.violations(in: typedSentence, policy: .baseline(listed)).map(\.text),
                       ["You are on call. Quit anyway?"])
    }

    func testALiteralAddedToTheLadderEditorViewIsRefusedAsSoonAsThereIsOne() {
        XCTAssertTrue(HeldFiles.strictViews.contains("LadderEditorView.swift"))
        let clean = #"""
        struct LadderEditorView: View {
            var body: some View {
                Label(EditorText.customise, systemImage: "slider.horizontal.3")
                Toggle("", isOn: $on)
            }
        }
        """#
        XCTAssertEqual(violationsIfPresent(clean, policy: .strictView), [])
        let added = clean.replacingOccurrences(of: "Toggle(\"\", isOn: $on)", with: "Toggle(\"Tier 2\", isOn: $on)")
        XCTAssertEqual(violationsIfPresent(added, policy: .strictView).map(\.text), ["Tier 2"])
    }
}
