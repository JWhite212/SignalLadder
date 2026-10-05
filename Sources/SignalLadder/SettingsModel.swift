// Sources/SignalLadder/SettingsModel.swift
import AppKit
import Combine
import NotificationCore

/// What the Settings window shows and does about Launch at login, and the one
/// copy of what the user chose (M5 plan, Ruling 15, O12).
///
/// It decides nothing (Ruling 10). What the window shows for a status, where the
/// copy runs from and what the user wanted is `LaunchAtLogin.state`; the
/// sentence and the buttons beside the switch are `SettingsText`'s; what a
/// press of the switch asks the system for is `LaunchAtLogin.request`, and what
/// a press of a button asks for and saves is `LaunchAtLogin.Action`'s; what a
/// failed request comes to, what it says and how long it stands are
/// `LaunchAtLogin.outcome`, `outcomeAfterReading` and
/// `LaunchAtLoginText.message(after:statusAfter:)`. This reads, calls and shows.
///
/// **The status is never cached.** The system gives no notice of a change, so it
/// is read when the window appears, on every activation of the app, which is how
/// a change made in System Settings is seen when the user comes back, and again
/// after every request, whatever the request said. What is shown is what the last
/// read said. Nothing here registers by itself: only the user's own press of the
/// switch or of a button does, and the app never switches the item back on.
///
/// **What the user chose** is saved under `LaunchAtLogin.wantedKey`, read when
/// this is made and written only at the user's own press, whatever the system
/// then reads: when they turn the switch, to the position they turned it to, and
/// when they press a button that `LaunchAtLogin.Action.wantedAfterPress` says
/// saves it. It is read through the injected defaults as the other stores read
/// theirs, and `AppDelegate` reads `wanted` for the menu's one line, so that
/// there is one copy of it.
@MainActor
final class SettingsModel: ObservableObject {
    private let defaults: UserDefaults
    private var activationObserver: NSObjectProtocol?

    /// What the system said when it was last read.
    @Published private(set) var status: LoginItemStatus
    /// Whether the user switched Launch at login on, as saved.
    @Published private(set) var wanted: Bool
    /// Where the running copy is, as the core classifies its path.
    @Published private(set) var location: AppLocation
    /// What the last request said, when it failed or changed nothing, which is the
    /// core's to say, and to stop saying at the next read that no request made
    /// (`LaunchAtLoginText.message(after:statusAfter:)`).
    @Published private(set) var message: String?
    /// Which build is running, at the foot of the window.
    @Published private(set) var versionLine: String

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        wanted = LaunchAtLogin.wanted(stored: defaults.object(forKey: LaunchAtLogin.wantedKey))
        status = LoginItem.status
        location = Self.currentLocation()
        versionLine = Self.currentVersionLine()
        // Held for as long as the app runs, which is as long as this does.
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    // MARK: - What is shown

    /// What the window shows for the login item.
    var state: LaunchAtLogin.State {
        LaunchAtLogin.state(status: status, wanted: wanted, location: location)
    }

    /// The sentence under the switch.
    var sentence: String { SettingsText.launchAtLoginSentence(for: state) }

    /// The buttons beside the switch, which are none unless the system has the
    /// item switched off.
    var buttons: [SettingsText.LoginButton] { SettingsText.launchAtLoginButtons(for: state) }

    // MARK: - Reading

    /// Reads what the system says now, for when the window appears and for each
    /// activation of the app. No request made it, so it says nothing of one: a
    /// request's message was about the read that came after it.
    func refresh() {
        read(after: nil)
    }

    /// Reads what the system says now. `attempt` is the request this read follows
    /// and what it said, and nil when none made it. The core says what that comes
    /// to, against the status read.
    private func read(after attempt: LaunchAtLogin.Attempt?) {
        status = LoginItem.status
        location = Self.currentLocation()
        versionLine = Self.currentVersionLine()
        message = LaunchAtLoginText.message(after: attempt, statusAfter: status)
    }

    // MARK: - What the user does

    /// The user turned the switch. It is saved as the user's choice, whatever the
    /// system then says.
    func switchTurned(on: Bool) {
        saveChoice(on)
        carryOut(LaunchAtLogin.request(switchTurnedOn: on))
    }

    /// The user pressed a button beside the switch. The core says what it saves
    /// as the user's choice, and whether it asks the system to register; one
    /// that does not only opens System Settings.
    func perform(_ action: LaunchAtLogin.Action) {
        if let choice = action.wantedAfterPress { saveChoice(choice) }
        if let request = action.request {
            carryOut(request)
        } else {
            LoginItem.openSystemSettingsLoginItems()
        }
    }

    /// Saves what the user chose, in the one place it is written.
    private func saveChoice(_ choice: Bool) {
        wanted = choice
        defaults.set(choice, forKey: LaunchAtLogin.wantedKey)
    }

    /// Makes the request, reads the status again, and says what it came to against
    /// that read. Whatever the request said, the status shown is the one read
    /// afterwards. Every request assigns the status, even to the value it had, so
    /// that a switch the user moved is asked to show the status again.
    private func carryOut(_ request: LaunchAtLogin.Request) {
        let outcome: LaunchAtLogin.Outcome
        switch request {
        case .register: outcome = LoginItem.register()
        case .unregister: outcome = LoginItem.unregister()
        }
        read(after: LaunchAtLogin.Attempt(request: request, outcome: outcome))
    }

    // MARK: - What the system and the bundle say

    /// Where this copy runs from: the bundle's path and the user's home folder,
    /// which the core classifies.
    private static func currentLocation() -> AppLocation {
        AppLocation.classify(path: Bundle.main.bundlePath, home: NSHomeDirectory())
    }

    /// The version line, with the build's date in the user's locale and time zone
    /// as they are now.
    private static func currentVersionLine() -> String {
        let formatter = SettingsText.dateFormatter(locale: .current, timeZone: .current)
        return SettingsText.version(BuildInfo(infoDictionary: Bundle.main.infoDictionary),
                                    date: { formatter.string(from: $0) })
    }
}
