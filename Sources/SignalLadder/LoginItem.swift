// Sources/SignalLadder/LoginItem.swift
import Foundation
import ServiceManagement
import os
import NotificationCore

/// The one place the app calls the system's login item, and the only file that
/// imports `ServiceManagement` (M5 plan, Ruling 15).
///
/// It reads the system's status and hands the core the case that matches, makes
/// the two requests, and hands the core the domain and the code of an error and
/// nothing else of it. What a status or an error comes to is
/// `LaunchAtLogin`'s, in the core, where it is tested. Nothing here calls
/// `register()` or `unregister()` but at the user's own press, of Settings' switch
/// or of a button, which includes the one the on-call check's login finding carries:
/// Settings' model carries that press out, so there is one path that registers.
///
/// Nothing is kept: the status has no change notification, so it is read afresh
/// each time it is wanted. A read is synchronous and was measured at 10 to 21
/// milliseconds when reads were spread out and 2 to 3 back to back, on macOS
/// 26.7.1 on 2026-10-05 (not on macOS 14 or 15), so it stays on the main thread.
enum LoginItem {
    private static let log = Logger(subsystem: "com.jamiewhite.signalladder", category: "loginitem")

    /// What the system says now. A status this build has no case for is the
    /// core's to read (`LoginItemStatus.whenUnrecognised`).
    static var status: LoginItemStatus {
        switch SMAppService.mainApp.status {
        case .notRegistered: return .notRegistered
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notFound: return .notFound
        @unknown default: return .whenUnrecognised
        }
    }

    /// Registers the app. No error is what was asked.
    static func register() -> LaunchAtLogin.Outcome {
        do {
            try SMAppService.mainApp.register()
            return .succeeded
        } catch {
            return outcome(of: .register, error)
        }
    }

    /// Unregisters the app, in the synchronous form, since the asynchronous
    /// overload can be ambiguous. It leaves a running app running.
    static func unregister() -> LaunchAtLogin.Outcome {
        do {
            try SMAppService.mainApp.unregister()
            return .succeeded
        } catch {
            return outcome(of: .unregister, error)
        }
    }

    /// Opens Login Items in System Settings, where the user decides.
    static func openSystemSettingsLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// The domain is compared as text by the core, since the system's constant for
    /// it is macOS 15 and later. Only the domain and the code are logged: never a
    /// description, which may hold a name or a path.
    private static func outcome(of request: LaunchAtLogin.Request, _ error: Error) -> LaunchAtLogin.Outcome {
        let failure = error as NSError
        log.error("Login item request failed, domain \(failure.domain, privacy: .public), code \(failure.code, privacy: .public)")
        return LaunchAtLogin.outcome(ofRequest: request, domain: failure.domain, code: failure.code)
    }
}
