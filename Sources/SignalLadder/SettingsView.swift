// Sources/SignalLadder/SettingsView.swift
import SwiftUI
import NotificationCore

/// What Settings says: one group, Launch at login, and at the foot the line that
/// says which build is running (M5 plan, O12, Ruling 15).
///
/// The group is the switch, the state in words, the buttons the core gives an item
/// the system has switched off, and what a request that failed said. There is no
/// Setup group yet, so no button here does nothing, and no Permissions or About
/// group.
///
/// Thin by design, and held to it: this file may hold no word of its own (the
/// strict list in `ViewLiteralsTests`), so every label and sentence is
/// `SettingsText`'s or `LaunchAtLoginText`'s and what is shown for a status is
/// `LaunchAtLogin`'s. The window says no more than the app has read, so it says
/// the item is on only where macOS reports it enabled. The version line is
/// secondary text and selectable, so it can be copied into a bug report.
struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox {
                launchAtLogin
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
            Text(model.versionLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(minWidth: 420, idealWidth: 480, maxWidth: .infinity,
               minHeight: 240, idealHeight: 300, maxHeight: .infinity, alignment: .topLeading)
    }

    private var launchAtLogin: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(SettingsText.launchAtLoginSwitch, isOn: Binding(
                get: { model.state.isOn },
                set: { model.switchTurned(on: $0) }))
                .disabled(!model.state.switchIsEnabled)
            Text(model.sentence)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !model.buttons.isEmpty {
                HStack(spacing: 10) {
                    ForEach(model.buttons, id: \.action) { button in
                        Button(button.label) { model.perform(button.action) }
                    }
                }
            }
            if let message = model.message {
                Text(message)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
