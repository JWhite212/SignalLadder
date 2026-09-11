// Sources/SignalLadder/OnboardingCoordinator.swift
import AppKit
import ApplicationServices
import UserNotifications

/// Requests the permissions the app needs, in the order that makes them
/// explicable.
///
/// Accessibility first, because it is the one that sounds alarming and needs
/// justifying. Notifications second, framed as how the app proves it is
/// working — which is true, and is why the request is not optional.
enum OnboardingCoordinator {
    static func requestNotificationAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert])
        } catch {
            return false
        }
    }

    static func requestAccessibilityIfNeeded() -> Bool {
        if AXIsProcessTrusted() { return true }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    static func openNotificationSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!
        NSWorkspace.shared.open(url)
    }
}
