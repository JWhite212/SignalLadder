// Sources/SignalLadder/SoundEditorView.swift
import NotificationCore
import SwiftUI

/// What the sound editor says: the sound as a waveform with where the playhead is and what is selected, the buttons
/// that play it, loop a selection and zoom, and what the checks have to say of it (sound editor plan, Task 7).
///
/// Read-only for now. No edit has a button yet, and a check is listed with its sentence and not its press. The two
/// checks that would stop a save are drawn as a fault is, with a line round them, and the others, which only advise,
/// are not (Ruling 12).
///
/// Thin by design, and held to it: this file may hold no word of its own (the strict list in `ViewLiteralsTests`), so
/// every label and sentence is `SoundEditorText`'s, and what is on and what is off is `SoundEditorControls`'. The
/// window follows the system's light or dark, as the rule editor does, and the waveform is the one place that is navy.
struct SoundEditorView: View {
    @ObservedObject var model: SoundEditorModel

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
               minHeight: 440, idealHeight: 560, maxHeight: .infinity, alignment: .topLeading)
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(SoundEditorText.heading(model.displayName)).font(.headline)
            WaveformView(model: model)
                .frame(minHeight: 160, idealHeight: 220)
            readouts
            if !model.viewport.isWhole { scroller }
            transport
            notes
            checks
            Spacer(minLength: 0)
        }
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
                    // Only what stops a save is drawn as a fault. The rest advise.
                    Label(SoundEditorText.sentence(for: finding),
                          systemImage: finding.blocksSaving ? "exclamationmark.triangle" : "info.circle")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                        .faultOutlined(when: finding.blocksSaving)
                }
            }
        }
    }
}
