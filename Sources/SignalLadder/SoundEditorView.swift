// Sources/SignalLadder/SoundEditorView.swift
import NotificationCore
import SwiftUI

/// What the sound editor says: the sound as a waveform with where the playhead is and what is selected, the buttons
/// that play it, loop a selection and zoom, the buttons that edit it, and what the checks have to say of it, each
/// with the press that mends it where it has one (sound editor plan, Tasks 7 and 8).
///
/// The two checks that stop a save are drawn as a fault is, with a line round them, and the others, which only
/// advise, are not (Ruling 12). Gain is offered only for a part of the sound and not for all of it, with the sentence
/// that says why beside it (Ruling 16). The seven shortcuts are each command's own, from `SoundEditorText`.
///
/// Under the checks are the name a sound is saved under, **Save as New**, which is the default, and **Save**, which is
/// offered only for a sound of the user's own and replaces it (Ruling 9, and Task 9). What each is on for, the verdict
/// on the name typed and what Save asks first are `SoundSaveControls`'; what pressing one does is the window
/// controller's, which asks over the window and shows a failure.
///
/// Thin by design, and held to it: this file may hold no word of its own (the strict list in `ViewLiteralsTests`), so
/// every label and sentence is `SoundEditorText`'s, and what is on and what is off is `SoundEditorControls`'. The
/// window follows the system's light or dark, as the rule editor does, and the waveform is the one place that is navy.
struct SoundEditorView: View {
    @ObservedObject var model: SoundEditorModel
    let actions: SoundEditorActions
    @FocusState private var nameIsFocused: Bool

    var body: some View {
        Group {
            switch model.phase {
            case .opening:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(SoundEditorText.opening(model.displayName)).foregroundStyle(.secondary)
                }
            case .failed(let sentence):
                Label(sentence, systemImage: "exclamationmark.triangle")
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            case .ready:
                editor
            }
        }
        .padding(20)
        .frame(minWidth: 560, idealWidth: 760, maxWidth: .infinity,
               minHeight: 600, idealHeight: 700, maxHeight: .infinity, alignment: .topLeading)
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(SoundEditorText.heading(model.displayName)).font(.headline)
            WaveformView(model: model)
                .frame(minHeight: 160, idealHeight: 220)
            readouts
            if !model.viewport.isWhole { scroller }
            transport
            edits
            gain
            repeats
            notes
            checks
            saving
            Spacer(minLength: 0)
        }
        .environment(\.nameFieldIsFocused, nameIsFocused)
    }

    // MARK: - Where it is

    private var readouts: some View {
        HStack {
            // What the waveform says to VoiceOver is its own value, so this is not read twice.
            Text(SoundEditorText.waveformValue(playhead: model.timeline.playhead, selection: model.timeline.selection,
                                               length: model.timeline.length))
                .font(.mono(.callout))
                .accessibilityHidden(true)
            Spacer()
            Text(SoundEditorText.lengthReadout(frames: model.timeline.length))
                .font(.mono(.callout))
        }
        .foregroundStyle(.secondary)
    }

    private var scroller: some View {
        Slider(value: Binding(get: { model.viewport.scrollFraction }, set: { model.scroll(toFraction: $0) }), in: 0...1)
            .accessibilityLabel(SoundEditorText.visiblePartLabel)
    }

    // MARK: - Playing, looping and zooming

    private var transport: some View {
        let controls = model.controls
        return HStack(spacing: 12) {
            Button { model.togglePlayback() } label: {
                Label(controls.playCommand.title, systemImage: model.isPreviewing ? "stop.fill" : "play.fill")
            }
            .disabled(!controls.canPlayOrStop)
            Toggle(SoundEditorText.Command.loopSelection.title,
                   isOn: Binding(get: { controls.loopIsOn }, set: { model.setLoops($0) }))
                .toggleStyle(.checkbox)
                .disabled(!controls.canLoop)
            Spacer()
            Button { model.selectAll() } label: { Text(SoundEditorText.Command.selectAll.title) }
                .disabled(!controls.canSelectAll)
                .shortcut(of: .selectAll)
            Button { model.clearSelection() } label: { Text(SoundEditorText.Command.clearSelection.title) }
                .disabled(!controls.canClearSelection)
            Button { model.zoomOut() } label: {
                Label(SoundEditorText.Command.zoomOut.title, systemImage: "minus.magnifyingglass")
            }
            .labelStyle(.iconOnly)
            .help(SoundEditorText.Command.zoomOut.title)
            .disabled(!controls.canZoomOut)
            Button { model.zoomIn() } label: {
                Label(SoundEditorText.Command.zoomIn.title, systemImage: "plus.magnifyingglass")
            }
            .labelStyle(.iconOnly)
            .help(SoundEditorText.Command.zoomIn.title)
            .disabled(!controls.canZoomIn)
        }
    }

    // MARK: - Editing

    /// The buttons that edit the sound. Each asks the model for its command, is off when the core says it would do
    /// nothing, and has the shortcut its command has.
    private var edits: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                commandButton(.trim)
                commandButton(.delete)
                commandButton(.cut)
                commandButton(.copy)
                commandButton(.paste)
                commandButton(.duplicate)
            }
            HStack(spacing: 8) {
                commandButton(.fadeIn)
                commandButton(.fadeOut)
                Spacer()
                commandButton(.undo)
                commandButton(.redo)
                commandButton(.resetToOriginal)
            }
        }
    }

    private func commandButton(_ command: SoundEditorText.Command) -> some View {
        Button(command.title) { model.perform(command) }
            .disabled(!model.controls.canPerform(command))
            .shortcut(of: command)
    }

    /// Gain on the selection, offered only for a part of the sound and never for all of it, since the player brings
    /// every sound to the same peak when it plays and a gain on all of one would change nothing anyone hears
    /// (Ruling 16). Where it is offered the sentence that says so is beside it, and where it is not, what to do to
    /// have it.
    private var gain: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.controls.offersGain {
                HStack(spacing: 10) {
                    Text(SoundEditorText.gainLabel)
                    Slider(value: Binding(get: { model.gainDB }, set: { model.setGainDB($0) }),
                           in: SoundEditorEditing.gainRangeDB, step: SoundEditorEditing.gainStepDB)
                        .frame(maxWidth: 260)
                        .accessibilityLabel(SoundEditorText.gainLabel)
                        .accessibilityValue(SoundEditorText.gainValue(model.gainDB))
                    Text(SoundEditorText.gainValue(model.gainDB))
                        .monospacedDigit()
                        .frame(width: 56, alignment: .trailing)
                    Button(SoundEditorText.Command.gain.title) { model.perform(.gain) }
                        .disabled(!model.controls.canPerform(.gain))
                }
                Text(SoundEditorText.gainNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(SoundEditorText.gainNeedsASelection)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// How many times the selection is played, and how long the gap between plays is, with the button that makes it.
    /// A stepper says its value to VoiceOver as a bare number, so each is given its value in its unit.
    private var repeats: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Stepper(SoundEditorText.playsLabel, value: Binding(get: { model.repeatPlays }, set: { model.setRepeatPlays($0) }),
                        in: SoundEditorEditing.playsRange)
                    .accessibilityValue(SoundEditorText.playsValue(model.repeatPlays))
                Text(SoundEditorText.playsValue(model.repeatPlays))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Stepper(SoundEditorText.gapLabel, value: Binding(get: { model.repeatGapSeconds }, set: { model.setRepeatGapSeconds($0) }),
                        in: SoundEditorEditing.gapRangeSeconds, step: SoundEditorEditing.gapStepSeconds)
                    .accessibilityValue(SoundEditorText.gapValue(model.repeatGapSeconds))
                Text(SoundEditorText.gapValue(model.repeatGapSeconds))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Spacer()
                Button(SoundEditorText.Command.repeatSelection.title) { model.perform(.repeatSelection) }
                    .disabled(!model.controls.canPerform(.repeatSelection))
            }
        }
    }

    // MARK: - What is being waited for, and what did not play

    @ViewBuilder
    private var notes: some View {
        if model.isCatchingUp {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(SoundEditorText.catchingUp).foregroundStyle(.secondary)
            }
        }
        if let notice = model.notice {
            Label(notice, systemImage: "exclamationmark.circle").font(.callout)
        }
        if model.isPreviewing && model.outputIsSilent {
            Label(EditorText.outputSilentNote, systemImage: "speaker.slash").font(.callout)
        }
    }

    // MARK: - The checks

    private var checks: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(SoundEditorText.checksHeading).font(.subheadline.weight(.semibold))
            if model.findings.isEmpty {
                Label(SoundEditorText.noFindings, systemImage: "checkmark.circle").foregroundStyle(.secondary)
            } else {
                ForEach(model.findings, id: \.kind) { finding in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        // Only what stops a save is drawn as a fault. The rest advise.
                        Label(SoundEditorText.sentence(for: finding),
                              systemImage: finding.blocksSaving ? "exclamationmark.triangle" : "info.circle")
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                            .faultOutlined(when: finding.blocksSaving)
                        Spacer(minLength: 0)
                        // Shown only for a finding whose own fix is there: the text has no label for one without.
                        if let press = SoundEditorText.press(for: finding), let fix = finding.fix {
                            Button(press) { model.fix(finding) }
                                .disabled(!model.controls.canPress(fix))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Saving

    /// The name the sound is saved under, and the two ways to save it. Return in the name field is Save as New, which is
    /// what the window defaults to. Each button is on only when the core says so, and the sentences beside the name say
    /// what is wrong with it, or that a macOS sound is only copied.
    private var saving: some View {
        let save = model.saveControls
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(SoundEditorText.nameLabel)
                    .accessibilityHidden(true)
                TextField(SoundEditorText.nameLabel, text: Binding(get: { model.typedName }, set: { model.setTypedName($0) }))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)
                    .accessibilityLabel(SoundEditorText.nameLabel)
                    .focused($nameIsFocused)
                    .onSubmit { actions.saveAsNew() }
                Button(model.isSaving ? SoundEditorText.saving : SoundEditorText.saveAsNew) { actions.saveAsNew() }
                    .disabled(!save.canSaveAsNew)
                if save.offersSave {
                    Button(SoundEditorText.save) { actions.save() }
                        .disabled(!save.canSave)
                }
            }
            ForEach(save.notes, id: \.self) { sentence in
                Text(sentence)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Whether the name field has the keyboard, which the commands' shortcuts are told so that they give way.
private struct NameFieldIsFocusedKey: EnvironmentKey {
    static let defaultValue = false
}

private extension EnvironmentValues {
    var nameFieldIsFocused: Bool {
        get { self[NameFieldIsFocusedKey.self] }
        set { self[NameFieldIsFocusedKey.self] = newValue }
    }
}

/// A command's shortcut on its button, which is the one the core gives it and none while a name is being typed. A
/// button's shortcut is met before the text field's own, so Command-A, -C, -V, -X and -Z would otherwise select, copy,
/// paste, cut and undo in the sound and not in the name.
private struct CommandShortcut: ViewModifier {
    let command: SoundEditorText.Command
    @Environment(\.nameFieldIsFocused) private var typing

    @ViewBuilder
    func body(content: Content) -> some View {
        if let shortcut = command.shortcut, !typing {
            content.keyboardShortcut(KeyEquivalent(shortcut.key), modifiers: shortcut.shift ? [.command, .shift] : .command)
        } else {
            content
        }
    }
}

private extension View {
    /// This view's shortcut: the one `command` has, which is Command with its key and with Shift for Redo, and none
    /// for a command that has none. The keys are the text's, so that the window types none.
    func shortcut(of command: SoundEditorText.Command) -> some View {
        modifier(CommandShortcut(command: command))
    }
}
