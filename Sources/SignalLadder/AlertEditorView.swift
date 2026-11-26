// Sources/SignalLadder/AlertEditorView.swift
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import AlertAudio
import NotificationCore

/// One alert of a rule: nothing, stay quiet on purpose, play a sound, speak a
/// line, or play a sound and then speak — each at a chosen gain, and each with
/// a way to try it as the alert will play it, which never cuts off a real
/// alert.
///
/// It edits the alert it is bound to and nothing else of the rule, so the same
/// view serves every step of a ladder. Which kinds it offers, which step its
/// wording is for and whether it shows the muted-output note are the mounting
/// view's to say.
///
/// How the choices change the alert is `AlertEditing`, tested in the core; the
/// view only shows it.
struct AlertEditorView: View {
    @ObservedObject var model: RuleEditorModel
    @Binding var action: AlertAction?
    /// Speech or a sound set aside by a choice, restored by choosing back.
    /// Kept by the mounting view, so each alert has a set-aside of its own and
    /// one never restores into another.
    @Binding var setAside: AlertEditing.SetAside
    /// The kinds the picker offers.
    let kinds: [AlertEditing.Kind]
    /// Which alert of a rule this editor is for. Its wording follows the role.
    let role: AlertEditing.Role
    /// Whether to say that the Mac's sound output is muted. Said once for all
    /// the alerts of a rule, by whichever view mounts them.
    let showsMutedOutputNote: Bool
    /// Why the last test did not play, shown until the next try.
    @State private var testMessage: String?
    /// The sound the user already has that an added file would replace, while
    /// they are being asked.
    @State private var soundToReplace: SoundToReplace?

    /// Read & Speak (Spoken Content before macOS 26), where voices are added.
    private static let voiceSettings = URL(string: "x-apple.systempreferences:com.apple.Accessibility-Settings.extension?SpokenContent")!

    /// The kinds shown: those offered, and the one the alert already is, so that
    /// whatever is selected has a segment. Decided by `AlertEditing`.
    private var shownKinds: [AlertEditing.Kind] {
        AlertEditing.shownKinds(offering: kinds, for: action)
    }

    private static func label(for kind: AlertEditing.Kind) -> String {
        switch kind {
        case .none: return EditorText.noAlert
        case .silent: return EditorText.silentKind
        case .sound: return EditorText.soundKind
        case .speech: return EditorText.speechKind
        }
    }

    private var kind: Binding<AlertEditing.Kind> {
        Binding(
            get: { AlertEditing.kind(of: action) },
            set: { kind in
                let (alert, kept) = AlertEditing.choosing(kind, from: action, setAside: setAside,
                                                          defaultSound: model.defaultSound, defaultVoice: model.defaultVoice)
                action = alert
                setAside = kept
                if let voice = alert?.speech?.voiceIdentifier { model.prepareVoice(voice) }
            })
    }

    private var alsoSpeak: Binding<Bool> {
        Binding(
            get: { if case .soundAndSpeak = action { return true }; return false },
            set: { on in
                let (alert, kept) = AlertEditing.settingAlsoSpeak(on, on: action, setAside: setAside,
                                                                  defaultVoice: model.defaultVoice)
                action = alert
                setAside = kept
                if on, let voice = alert?.speech?.voiceIdentifier { model.prepareVoice(voice) }
            })
    }

    private var soundName: Binding<String> {
        Binding(
            // Shown with the library's own spelling: sound names match
            // ignoring case, but a picker only selects an exact tag.
            get: {
                guard let name = action?.soundName else { return "" }
                return model.availableSounds.first { $0.caseInsensitiveCompare(name) == .orderedSame } ?? name
            },
            set: { action = AlertEditing.replacingSound(in: action, name: $0) })
    }

    private var soundGain: Binding<Double> {
        Binding(
            get: {
                switch action {
                case .sound(_, let gain)?, .soundAndSpeak(_, let gain, _)?: return gain
                default: return 0
                }
            },
            set: { action = AlertEditing.replacingSound(in: action, gainDB: $0.rounded()) })
    }

    /// One field of the alert's speech.
    private func speech<Value>(_ keyPath: WritableKeyPath<SpeechAction, Value>, default fallback: Value) -> Binding<Value> {
        Binding(
            get: { action?.speech?[keyPath: keyPath] ?? fallback },
            set: { value in
                guard var speech = action?.speech else { return }
                speech[keyPath: keyPath] = value
                action = AlertEditing.replacingSpeech(in: action, with: speech)
            })
    }

    private var voice: Binding<String> {
        Binding(
            get: { action?.speech?.voiceIdentifier ?? "" },
            set: { identifier in
                speech(\.voiceIdentifier, default: "").wrappedValue = identifier
                model.prepareVoice(identifier)
            })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("", selection: kind) {
                ForEach(shownKinds, id: \.self) { Text(Self.label(for: $0)).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            // The picker has no words of its own, and says which alert it is
            // for, since a rule's ladder has up to three of them.
            .accessibilityLabel(EditorText.alertPickerLabel(for: role))

            // What each kind does, worded for the step the alert is.
            Text(EditorText.alertMeaning(action, role: role))
                .font(.callout)
                .foregroundStyle(.secondary)

            if let name = action?.soundName {
                soundControls(name: name)
                Toggle(EditorText.alsoSpeakIt, isOn: alsoSpeak)
            }
            if let speech = action?.speech {
                speechControls(speech)
            }
            if action?.makesNoise == true {
                if let testMessage {
                    Label(testMessage, systemImage: "exclamationmark.triangle").font(.callout).faultOutlined()
                }
                if showsMutedOutputNote && model.outputIsSilent {
                    Label(EditorText.outputSilentNote, systemImage: "speaker.slash").font(.callout).faultOutlined()
                }
            }
        }
        .onChange(of: action) { _, _ in testMessage = nil }
    }

    @ViewBuilder
    private func soundControls(name: String) -> some View {
        HStack(spacing: 10) {
            Picker(EditorText.soundKind, selection: soundName) {
                // A sound the rule names but that cannot be found is still
                // listed, so the choice shows what the rule says.
                if !model.availableSounds.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
                    Text(EditorText.soundNotFound(name)).tag(name)
                }
                ForEach(model.availableSounds, id: \.self) { Text($0).tag($0) }
            }
            .fixedSize()
            Button(EditorText.testSound) {
                testMessage = model.testSound(name, gainDB: soundGain.wrappedValue)
            }
        }
        // A sound file dropped on the row is added as the button adds one.
        .dropDestination(for: URL.self) { files, _ in
            guard let file = files.first else { return false }
            addSound(file)
            return true
        }
        HStack(spacing: 10) {
            Button(EditorText.addSound) { chooseSound() }
            Button(EditorText.showSoundsFolder) { testMessage = model.showSoundsFolder() }
                .buttonStyle(.link)
        }
        .confirmationDialog(EditorText.replaceSoundQuestion(replaceName), isPresented: askingToReplace,
                            titleVisibility: .visible) {
            Button(EditorText.replaceSound, role: .destructive) {
                if let file = soundToReplace?.file { addSound(file, replacing: true) }
            }
            Button(EditorText.keepSound, role: .cancel) {}
        } message: {
            Text(EditorText.replaceSoundDetail)
        }
        gainRow(soundGain)
    }

    private var replaceName: String { soundToReplace?.name ?? "" }

    private var askingToReplace: Binding<Bool> {
        Binding(get: { soundToReplace != nil }, set: { if !$0 { soundToReplace = nil } })
    }

    /// Asks for one sound file, of the types a sound may be.
    private func chooseSound() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = SoundImport.fileExtensions.compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = EditorText.addSoundMessage
        panel.prompt = EditorText.addSoundPrompt
        guard panel.runModal() == .OK, let file = panel.url else { return }
        addSound(file)
    }

    /// Adds the file and chooses it for this alert. A file refused says why
    /// where a sound that will not play does, and one that would take the
    /// place of a sound the user has is asked about first.
    private func addSound(_ file: URL, replacing: Bool = false) {
        switch model.addSound(from: file, replacing: replacing) {
        case .success(let added):
            soundName.wrappedValue = added
            testMessage = nil
        case .failure(.alreadyExists(let existing)):
            soundToReplace = SoundToReplace(name: existing, file: file)
        case .failure(let refusal):
            testMessage = refusal.description
        }
    }

    private struct SoundToReplace {
        let name: String
        let file: URL
    }

    @ViewBuilder
    private func speechControls(_ speech: SpeechAction) -> some View {
        let voices = model.availableVoices
        HStack(spacing: 10) {
            Picker(EditorText.voice, selection: voice) {
                // As for sounds: a voice the rule names that is not installed
                // is still shown, so the choice shows what the rule says.
                if !voices.contains(where: { $0.id == speech.voiceIdentifier }) {
                    Text(EditorText.voiceNotInstalled(speech.voiceIdentifier)).tag(speech.voiceIdentifier)
                }
                ForEach(voices) { Text(EditorText.voiceChoice(name: $0.name, language: $0.language)).tag($0.id) }
            }
            .fixedSize()
            Button(EditorText.moreVoices) { NSWorkspace.shared.open(Self.voiceSettings) }
                .buttonStyle(.link)
        }
        HStack(spacing: 10) {
            Text(EditorText.says)
            TextField(SpeechAction.defaultTemplate, text: self.speech(\.template, default: SpeechAction.defaultTemplate))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 320)
            Button(EditorText.testSpeech) {
                testMessage = model.testSpeech(speech)
            }
        }
        Text(EditorText.speechTemplateHelp)
            .font(.caption)
            .foregroundStyle(.secondary)
        sliderRow(EditorText.rate, value: self.speech(\.rate, default: 0.5), in: SpeechAction.rateRange, step: 0.05)
        sliderRow(EditorText.pitch, value: self.speech(\.pitchMultiplier, default: 1), in: SpeechAction.pitchRange, step: 0.05)
        gainRow(self.speech(\.gainDB, default: 0), label: EditorText.speechGain)
    }

    private func gainRow(_ gain: Binding<Double>, label: String = EditorText.gain) -> some View {
        HStack(spacing: 10) {
            Text(label)
            // The Text beside a slider is not its label, so a screen reader
            // is given the name, and the value in its unit, not a bare number.
            Slider(value: gain, in: AlertAction.gainRange, step: 1)
                .frame(maxWidth: 260)
                .accessibilityLabel(label)
                .accessibilityValue(EditorText.gainText(gain.wrappedValue))
            Text(EditorText.gainText(gain.wrappedValue))
                .monospacedDigit()
                .frame(width: 56, alignment: .trailing)
        }
    }

    /// Rate and pitch in their own units, shown as numbers: no friendlier
    /// unit is established for either.
    private func sliderRow(_ label: String, value: Binding<Float>, in range: ClosedRange<Float>, step: Float) -> some View {
        HStack(spacing: 10) {
            Text(label)
            Slider(value: value, in: range, step: step)
                .frame(maxWidth: 260)
                .accessibilityLabel(label)
                .accessibilityValue(EditorText.decimalText(value.wrappedValue))
            Text(EditorText.decimalText(value.wrappedValue))
                .monospacedDigit()
                .frame(width: 56, alignment: .trailing)
        }
    }
}
