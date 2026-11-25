import XCTest
@testable import NotificationCore

/// How the rule editor draws the ladder as four capsules with the selected
/// tier's settings beneath (M7 plan, Stage 6b). The app target has no tests, so
/// this reads its sources, as the other wiring tests do, and opens no window.
final class LadderCapsulesWiringTests: XCTestCase {
    private func squeezed(_ text: String) -> String {
        text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    // MARK: - The capsules

    /// Which tiers a rule has is the core's reading of it, the same one the
    /// list's strip is drawn from, so the two cannot differ.
    func testTheCapsulesAreTheCoresReadingOfTheRule() throws {
        let capsules = try body(of: "private func capsules(usable: Bool) -> some View {", in: try code("LadderEditorView.swift"))
        XCTAssertEqual(count("ForEach(LadderStrip(for: rule).segments, id: \\.tier) { segment in", in: capsules), 1)
        XCTAssertEqual(count("Text(EditorText.tierHeading(segment.tier))", in: capsules), 1)
        XCTAssertEqual(count("Self.capsule.fill(NightWatchPalette.block(segment.tone))", in: capsules), 1,
                       "a tier the rule has, in its colour")
        XCTAssertEqual(count("Self.capsule.strokeBorder(.secondary, lineWidth: 1.5)", in: capsules), 1,
                       "one it has not is an outline, so the two differ by more than colour")
        XCTAssertEqual(count("if isSelected { Self.capsule.strokeBorder(.primary, lineWidth: 2) }", in: capsules), 1)
        XCTAssertEqual(count("Button { select(segment.tier) } label: {", in: capsules), 1)
    }

    /// Choosing a tier takes the keyboard from the field that had it, so a
    /// number half typed is settled and no key reaches a field out of sight.
    func testChoosingATierSettlesTheFieldThatHadTheKeyboard() throws {
        let select = try body(of: "private func select(_ tier: Int) {", in: try code("LadderEditorView.swift"))
        XCTAssertEqual(squeezed(select), "NSApp.keyWindow?.makeFirstResponder(nil)\nselectedTier = tier")
    }

    /// A Shortcut that is not found is said in tier 4's settings, and marked on
    /// tier 4's capsule, which is in view whichever tier is selected.
    func testAShortcutThatIsNotFoundMarksTierFoursCapsule() throws {
        let editor = try code("LadderEditorView.swift")
        let capsules = try body(of: "private func capsules(usable: Bool) -> some View {", in: editor)
        XCTAssertEqual(count("if segment.tier == Self.finalTier, hasShortcutWarning {", in: capsules), 1)
        XCTAssertEqual(count(".accessibilityValue(segment.tier == Self.finalTier && hasShortcutWarning ? EditorText.shortcutNotFoundAdvice : \"\")",
                             in: capsules), 1)
        XCTAssertEqual(squeezed(try body(of: "private var hasShortcutWarning: Bool {", in: editor)),
                       "rule.escalation?.tier4?.action.shortcutName != nil && !model.warnings(in: rule).isEmpty")
    }

    func testACapsuleSaysItsTierAndWhetherItIsOnAndWhetherItIsSelected() throws {
        let capsules = try body(of: "private func capsules(usable: Bool) -> some View {", in: try code("LadderEditorView.swift"))
        XCTAssertEqual(count(".accessibilityLabel(EditorText.tierCapsule(segment.tier, isOn: segment.isOn))", in: capsules), 1)
        XCTAssertEqual(count(".accessibilityAddTraits(isSelected ? .isSelected : [])", in: capsules), 1)
    }

    /// While the rule has no alert the ladder cannot be used, as the presets
    /// cannot: tiers 2 to 4 cannot be chosen, and tier 1, where the alert is
    /// chosen, always can.
    func testTheFirstTierCanAlwaysBeChosenAndTheOthersOnlyWhileTheLadderCanBeUsed() throws {
        let editor = try code("LadderEditorView.swift")
        let capsules = try body(of: "private func capsules(usable: Bool) -> some View {", in: editor)
        XCTAssertEqual(count(".disabled(segment.tier != LadderStrip.firstTier && !usable)", in: capsules), 1)
        XCTAssertEqual(count("let usable = EscalationEditing.isPickerEnabled(for: escalation, alert: rule.alert)", in: editor), 1)
        XCTAssertEqual(count("capsules(usable: usable)", in: editor), 1)
        XCTAssertEqual(count("tiers(usable: usable)", in: editor), 1)
    }

    // MARK: - The settings

    /// All four stay in the view, so what was typed into one is there on coming
    /// back to it; the three not shown have no height, cannot be reached and are
    /// not read out.
    func testAllFourTiersSettingsStayInTheViewAndOneIsShown() throws {
        let editor = try code("LadderEditorView.swift")
        let tiers = try body(of: "private func tiers(usable: Bool) -> some View {", in: editor)
        XCTAssertEqual(count("ForEach(LadderStrip(for: rule).segments, id: \\.tier) { segment in", in: tiers), 1)
        XCTAssertEqual(count("let isShown = segment.tier == selectedTier", in: tiers), 1)
        XCTAssertEqual(count("settings(of: segment.tier)", in: tiers), 1)
        XCTAssertFalse(tiers.contains("if isShown"), "none is taken out of the view: that would lose what it holds")
        XCTAssertEqual(count(".frame(height: isShown ? nil : 0, alignment: .top)", in: tiers), 1)
        XCTAssertEqual(count(".clipped()", in: tiers), 1)
        XCTAssertEqual(count(".opacity(isShown ? 1 : 0)", in: tiers), 1)
        XCTAssertEqual(count(".disabled(!isShown || (segment.tier != LadderStrip.firstTier && !usable))", in: tiers), 1)
        XCTAssertEqual(count(".accessibilityHidden(!isShown)", in: tiers), 1)
        XCTAssertEqual(squeezed(try body(of: "private func settings(of tier: Int) -> some View {", in: editor)),
                       ["switch tier {", "case 2: tier2", "case 3: tier3", "case 4: tier4", "default: tier1", "}"]
                           .joined(separator: "\n"))
        XCTAssertFalse(editor.contains("DisclosureGroup"), "nothing of the ladder is behind a disclosure")
    }

    /// Tier 1 is the rule's first alert, edited by the editor every alert has,
    /// with what it set aside kept by the rule's pane, as before.
    func testTierOneIsTheFirstAlertsEditor() throws {
        let editor = try code("LadderEditorView.swift")
        let tier1 = try body(of: "private var tier1: some View {", in: editor)
        XCTAssertEqual(count("AlertEditorView(model: model, action: $rule.alert, setAside: $firstAlertSetAside,", in: tier1), 1)
        XCTAssertEqual(count("kinds: AlertEditing.offeredKinds(for: .first), role: .first,", in: tier1), 1)
        XCTAssertEqual(count("showsMutedOutputNote: false)", in: tier1), 1,
                       "the note that the output is muted is above the capsules, in view whichever tier is selected")
        XCTAssertEqual(count("if EscalationEditing.mutedOutputNoteSite(firstAlert: rule.alert, escalation: escalation) != nil,", in: editor), 1,
                       "shown once for the rule, whichever alert it is about")
        XCTAssertLessThan(try position(of: "Label(EditorText.outputSilentNote, systemImage: \"speaker.slash\")", in: editor),
                          try position(of: "capsules(usable: usable)", in: editor))
        XCTAssertEqual(count("Text(EditorText.tierSummary(LadderStrip.firstTier))", in: tier1), 1)
        XCTAssertFalse(tier1.contains("Toggle"), "it has no switch: None is one of its kinds")
        let detail = try code("RuleDetailView.swift")
        XCTAssertEqual(count("LadderEditorView(model: model, rule: rule, firstAlertSetAside: $alertSetAside)", in: detail), 1)
        XCTAssertEqual(count("AlertEditorView(", in: detail), 0, "the first alert is edited in one place")
        XCTAssertEqual(count("role: .first", in: editor), 1)
    }

    // MARK: - The selection

    /// It starts at the first alert, and after a preset is chosen, or Off is
    /// answered, the core says where it is, of the rule as the edit leaves it.
    func testThePresetsMoveTheSelectionAsTheCoreSays() throws {
        let editor = try code("LadderEditorView.swift")
        XCTAssertEqual(count("@State private var selectedTier = LadderStrip.firstTier", in: editor), 1)
        XCTAssertEqual(squeezed(try body(of: "private func reselect(after edit: EscalationEditing.Edit) {", in: editor)),
                       ["var edited = rule", "edited.escalation = edit.escalation",
                        "selectedTier = LadderStrip(for: edited).selection(afterPreset: selectedTier)"].joined(separator: "\n"))
        XCTAssertEqual(count("reselect(after: edit)", in: editor), 2, "a preset that changes the ladder, and the answer to Off")
        let choose = try body(of: "private func choose(_ shown: EscalationEditing.Shown) {", in: editor)
        XCTAssertLessThan(try position(of: "apply(edit)", in: choose), try position(of: "reselect(after: edit)", in: choose))
        // A tier's own switch does not move it: turning a tier off leaves its switch in view to turn it on again.
        for tier in ["private var tier2: some View {", "private var tier3: some View {", "private var tier4: some View {"] {
            XCTAssertFalse(try body(of: tier, in: editor).contains("reselect"), tier)
        }
    }
}
