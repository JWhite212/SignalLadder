import XCTest
@testable import NotificationCore

/// How the app draws a fault (M7 plan, Stage 2).
///
/// Orange is a tier's colour in the Night watch design, so nothing that is not
/// a tier may be orange, or a failed Shortcut would read as tier 2. The app
/// target has no tests, and a view that named the colour again would build
/// cleanly, so this reads the app's sources, as `OnCallWiringTests` does, and
/// holds each place a fault is drawn to how it is meant to be drawn. It opens
/// no window.
final class FaultWiringTests: XCTestCase {
    /// No view of the app names orange. The palette holds a tier's colour by
    /// its value, not by the system's name for it.
    func testNoSourceOfTheAppNamesOrange() throws {
        let files = try AppSources.fileNames()
        XCTAssertFalse(files.isEmpty)
        for file in files {
            let source = try code(file)
            XCTAssertEqual(count(".orange", in: source), 0, "\(file) draws with the system's orange")
            XCTAssertEqual(count("systemOrange", in: source), 0, "\(file) draws with the system's orange")
        }
    }

    /// Each sentence that says an alert will not reach the user, or a rule will
    /// not run, has the line round it, and so do the two reports of a test that
    /// failed.
    func testEachFaultHasTheLineRoundIt() throws {
        let places = [
            ("DryRunView.swift", #"Label(note, systemImage: "info.circle").font(.callout).faultOutlined()"#),
            ("LadderEditorView.swift",
             #"Label(report.text, systemImage: "exclamationmark.triangle").font(.callout).faultOutlined()"#),
            ("AlertEditorView.swift",
             #"Label(testMessage, systemImage: "exclamationmark.triangle").font(.callout).faultOutlined()"#),
            ("AlertEditorView.swift",
             #"Label(EditorText.outputSilentNote, systemImage: "speaker.slash").font(.callout).faultOutlined()"#),
        ]
        for (file, line) in places {
            XCTAssertEqual(count(line, in: try code(file)), 1, "\(file): \(line)")
        }
        XCTAssertEqual(count(".faultOutlined()", in: try code("RuleDetailView.swift")), 1,
                       "a rule's problems, as one block")
        let ladder = try code("LadderEditorView.swift")
        XCTAssertEqual(count(".faultOutlined()", in: ladder), 3,
                       "the muted output, a test of a Shortcut that did not start, and a Shortcut that is not found")
        XCTAssertLessThan(try position(of: #"Label(EditorText.outputSilentNote, systemImage: "speaker.slash")"#, in: ladder),
                          try position(of: ".font(.callout).faultOutlined()", in: ladder))
        let advice = try position(of: #"Label(EditorText.shortcutNotFoundAdvice, systemImage: "exclamationmark.triangle")"#,
                                  in: ladder)
        XCTAssertNotNil(ladder[advice...].range(of: ".faultOutlined()"), "the Shortcut that is not found")
        XCTAssertEqual(count(".faultOutlined()", in: try code("AlertEditorView.swift")), 2)
        XCTAssertEqual(count(".faultOutlined()", in: try code("DryRunView.swift")), 1)
    }

    /// A rule's problems are one block with one line round it, not a line
    /// round each, and the line is outside the block's font.
    func testARulesProblemsAreOutlinedAsOneBlock() throws {
        let detail = try code("RuleDetailView.swift")
        let label = try position(of: #"Label(problem, systemImage: "exclamationmark.triangle.fill")"#, in: detail)
        let outline = try position(of: ".faultOutlined()", in: detail)
        let advice = try position(of: #"Label(warning, systemImage: "exclamationmark.triangle")"#, in: detail)
        XCTAssertLessThan(label, outline)
        XCTAssertLessThan(outline, advice, "advice is not a fault and has no line round it")
    }

    /// The modifier takes the line's width from the core, where every
    /// combination of the display settings is tested, and reads all four
    /// settings from the environment, so none is made up.
    func testTheLinesWidthIsTheCoresAndTheFourSettingsAreRead() throws {
        let outline = try code("FaultOutline.swift")
        XCTAssertEqual(count("lineWidth: settings.outlineWidth", in: outline), 1)
        for setting in ["\\.colorSchemeContrast", "\\.accessibilityReduceTransparency", "\\.accessibilityReduceMotion",
                        "\\.accessibilityDifferentiateWithoutColor"] {
            XCTAssertEqual(count("@Environment(\(setting))", in: outline), 1, setting)
        }
        XCTAssertEqual(count(".foregroundStyle(.primary)", in: outline), 1)
        XCTAssertEqual(count(".strokeBorder(.primary", in: outline), 1)
    }

    /// A row that is a fault only some of the time draws the same line, by the
    /// same modifier, and takes back at each side what the line stands off by,
    /// so its words begin where a row with no line has them.
    func testARowThatIsSometimesAFaultDrawsTheSameLineAndKeepsItsPlace() throws {
        let outline = try code("FaultOutline.swift")
        let sometimes = try body(of: "func faultOutlined(when isFault: Bool) -> some View {", in: outline)
        XCTAssertEqual(count("faultOutlined().padding(.horizontal, -FaultOutline.sideInset)", in: sometimes), 1)
        XCTAssertEqual(count("self", in: sometimes), 1, "a row that is no fault is drawn as it is")
        XCTAssertEqual(count("static let sideInset: CGFloat = 8", in: outline), 1)
        XCTAssertEqual(count(".padding(.horizontal, Self.sideInset)", in: outline), 1,
                       "what the row takes back is what the line stands off by")
    }

    /// A test of a Shortcut that started is said quietly, and only one that did
    /// not start has the line: the two are different lines, so the quiet one
    /// cannot be given it.
    func testATestOfAShortcutThatStartedHasNoLineRoundIt() throws {
        let ladder = try code("LadderEditorView.swift")
        XCTAssertEqual(count(#"Label(report.text, systemImage: "checkmark.circle").foregroundStyle(.secondary).font(.callout)"#,
                             in: ladder), 1)
    }

    /// "Not in effect" has the line only for a rule with problems. A rule that
    /// is off, or not saved yet, is as the user left it: heavier, with no line.
    func testNotInEffectHasTheLineOnlyForARuleWithProblems() throws {
        let dryRun = try code("DryRunView.swift")
        let asked = try position(of: "if run.ruleHasProblems {", in: dryRun)
        let outlined = try position(of: #"Label(note, systemImage: "info.circle").font(.callout).faultOutlined()"#, in: dryRun)
        let plain = try position(
            of: #"Label(note, systemImage: "info.circle").font(.callout.weight(.semibold)).foregroundStyle(.primary)"#,
            in: dryRun)
        XCTAssertLessThan(asked, outlined)
        XCTAssertLessThan(outlined, plain)
    }

    /// The three places that were orange and are now in the label colour with
    /// no line: the save bar when it warns, a rule's triangle in the list, and
    /// an empty group of conditions.
    func testTheSaveBarTheRulesTriangleAndAnEmptyGroupAreInTheLabelColour() throws {
        let editor = try code("RuleEditorView.swift")
        XCTAssertEqual(count(".foregroundStyle(said.isWarning ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))",
                             in: editor), 1)
        XCTAssertEqual(count(".font(said.isWarning ? .callout.weight(.semibold) : .callout)", in: editor), 1)
        let triangle = try position(of: #"Image(systemName: "exclamationmark.triangle.fill")"#, in: editor)
        let style = try XCTUnwrap(editor[triangle...].range(of: ".foregroundStyle("), "the triangle has no colour set")
        XCTAssertTrue(editor[style.lowerBound...].hasPrefix(".foregroundStyle(.primary)"),
                      "the first colour set after the triangle is the label colour")
        let conditions = try code("ConditionBuilderView.swift")
        let empty = try position(of: "Text(EditorText.emptyGroup)", in: conditions)
        XCTAssertNotNil(conditions[empty...].range(of: ".font(.callout.weight(.semibold))"))
        XCTAssertEqual(count("Label(EditorText.emptyGroup", in: conditions), 0, "it had no symbol and has none")
    }

    /// "Taken by a rule above" is neither a fault nor a tier, so its mark is
    /// in the quiet colour, as an alert that did not match is.
    func testARuleTakenByOneAboveIsMarkedInTheQuietColour() throws {
        let dryRun = try code("DryRunView.swift")
        XCTAssertEqual(count(#"Image(systemName: "arrow.up.circle").foregroundStyle(.secondary)"#, in: dryRun), 1)
        XCTAssertEqual(count(#"Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)"#, in: dryRun), 1)
    }

    /// An Inspector line that says the user was not alerted is in the label
    /// colour and heavier, where it was orange.
    func testAnInspectorLineThatNeedsAttentionIsHeavierAndInTheLabelColour() throws {
        let inspector = try code("InspectorView.swift")
        XCTAssertEqual(count(".font(alert.needsAttention ? .caption.weight(.semibold) : .caption)", in: inspector), 1)
        XCTAssertEqual(count(".foregroundStyle(alert.needsAttention ? Color.primary : Color.secondary)", in: inspector), 1)
        XCTAssertEqual(count(".font(escalation.needsAttention ? .caption.weight(.semibold) : .caption)", in: inspector), 1)
        // Its symbol changes too, since weight alone is a small difference at this size.
        XCTAssertEqual(count(#"systemImage: escalation.needsAttention ? "exclamationmark.triangle" : "bell.and.waves.left.and.right")"#,
                             in: inspector), 1)
        XCTAssertEqual(count(".foregroundStyle(escalation.needsAttention ? Color.primary : Color.secondary)",
                             in: inspector), 1)
    }

    // MARK: - The status item's capsule (M7 plan, Stage 4)

    /// The capsule keeps its colour and says its words: it is not a template,
    /// which the menu bar would tint, and VoiceOver's description is set on it.
    /// Its figures are fixed-width and its colours are the palette's.
    func testTheCapsuleIsNotATemplateAndCarriesItsDescription() throws {
        let capsule = try code("StatusCapsule.swift")
        XCTAssertEqual(count("image.isTemplate = false", in: capsule), 1)
        XCTAssertEqual(count("image.accessibilityDescription = description", in: capsule), 1)
        XCTAssertEqual(count("NSFont.monospacedSystemFont(", in: capsule), 1)
        XCTAssertEqual(count("NightWatchPalette.block(capsule.tone)", in: capsule), 1)
        XCTAssertEqual(count("NightWatchPalette.ink", in: capsule), 1)
        XCTAssertEqual(count("let (ground, figures) = capsule.dim ? (navy, tier) : (tier, navy)", in: capsule), 1,
                       "the pulse's other half is the same two colours exchanged, so its figures read on any menu bar")
        XCTAssertFalse(capsule.contains("withAlphaComponent"), "a fainter capsule's figures sank into a dark menu bar")

        // The pulse begins on its bright half: the first thing seen of an
        // escalation is the capsule in its tier's colour.
        let pulse = try body(of: "private func updateGlyphPulse() {", in: try code("AppDelegate.swift"))
        XCTAssertEqual(count("glyphPulse = true", in: pulse), 1)
        XCTAssertLessThan(try position(of: "glyphTimer = timer", in: pulse), try position(of: "glyphPulse = true", in: pulse))
        XCTAssertEqual(count("glyphPulse = false", in: pulse), 1, "and is put back when nothing is escalating")
    }
}
