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
/// there is one copy of it. `AppDelegate` also hands this the on-call finding's
/// button, which is a press of the same kind (`perform(_:)`), so that there is
/// one path that registers and one place the choice is saved, and asks it what
/// Settings would show for a status it read (`state(for:)`). The setup guide's
/// Continue on its last step is a third press of that kind (`perform(guidePress:)`),
/// which the guide's coordinator hands it, and it goes through the same two places.
///
/// **The Setup group** holds a line and a button (M5 plan, Task 8). The line is
/// `SetupText.settingsLine(_:)` for the facts the setup guide reads, which the app delegate
/// hands over (`takeSetupFacts(_:)`) whenever it reads them for the guide, and only after the
/// rules are loaded, since the rules fact has no "not read yet" (`SetupFacts.ruleStatus`).
/// This keeps the line and not the facts, and makes nothing of them: where the guide stands
/// and what it reads are the core's. The button shows the guide, through the closure the app
/// delegate sets (`openGuide`), which is the window's only door and the nudge's too.
///
/// **Each read is shared** with whoever is told of it (`onStatusRead`), which is
/// `AppDelegate`, which asks the on-call watch about the status just read (Ruling
/// 9: each time the login item's status is read). So a change made in System
/// Settings, which an activation reads, and a request made here or by the
/// finding's button are seen by the watch at once, from the one read, and not at the
/// next health refresh. What a request said (`message`) is assigned before it is
/// told, so that what the on-call check window shows beneath the finding's button
/// is the same message, and stands for as long as this one does.
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
    /// The Setup group's line: where the setup guide stands, in the core's words for the facts
    /// it was last handed. nil until it has been handed any, which is until the rules are
    /// first loaded at launch, and so before anyone can open this window.
    @Published private(set) var setupLine: String?

    /// Shows the setup guide, which the Setup group's button calls. Set by the app delegate,
    /// which holds the guide's window, and the one way the guide is shown: the menu's nudge
    /// and the launch decision go the same way.
    var openGuide: () -> Void = {}

    /// What is done with the status each read has just made, handed that status. Set
    /// by whoever needs every read, which is the app delegate, for the on-call watch.
    /// It is called after the model's own properties are assigned, and is not called
    /// for the read made when the model is made, which comes before anything can ask.
    var onStatusRead: (LoginItemStatus) -> Void = { _ in }

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

    /// What the window would show for a status read by whoever asks: the on-call
    /// check, which reads the status once for a pass and makes its login finding from
    /// that read and from nothing the model kept. What the user wanted is as saved
    /// now and where the copy runs from is read now, so the state is never older than
    /// the status it is made from.
    func state(for status: LoginItemStatus) -> LaunchAtLogin.State {
        LaunchAtLogin.state(status: status, wanted: wanted, location: Self.currentLocation())
    }

    /// The sentence under the switch.
    var sentence: String { SettingsText.launchAtLoginSentence(for: state) }

    /// The buttons beside the switch, which are none unless the system has the
    /// item switched off.
    var buttons: [SettingsText.LoginButton] { SettingsText.launchAtLoginButtons(for: state) }

    /// The Setup group's line for facts the app delegate has just gathered for the guide.
    /// They must be gathered after the rules are loaded (`SetupFacts.ruleStatus`), which the
    /// app delegate holds by gathering none before the first reload at launch. The line is
    /// `SetupText.settingsLine(_:)`'s and nothing here adds to it.
    func takeSetupFacts(_ facts: SetupFacts) {
        setupLine = SetupText.settingsLine(facts)
    }

    // MARK: - Reading

    /// Reads what the system says now, for when the window appears and for each
    /// activation of the app. No request made it, so it says nothing of one: a
    /// request's message was about the read that came after it.
    func refresh() {
        read(after: nil)
    }

    /// Reads what the system says now. `attempt` is the request this read follows
    /// and what it said, and nil when none made it. The core says what that comes
    /// to, against the status read. The read ends by telling `onStatusRead`.
    private func read(after attempt: LaunchAtLogin.Attempt?) {
        status = LoginItem.status
        location = Self.currentLocation()
        versionLine = Self.currentVersionLine()
        message = LaunchAtLoginText.message(after: attempt, statusAfter: status)
        onStatusRead(status)
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

    /// The user pressed Continue on the setup guide's last step, which `SetupPlan.pressing`
    /// has answered: what to save as the user's choice and what to ask the system for, each
    /// or neither (M5 plan, Task 8). It is the guide's press of the switch, so it goes
    /// through the same two places, `saveChoice` and `carryOut`, and no second copy of
    /// either exists: the choice is written under the one key by the one function, and the
    /// request reaches `LoginItem` by the one path. The status is read again afterwards.
    ///
    /// It hands back what the request came to, in the words the model keeps for it
    /// (`message`), which is nil when it succeeded, and nil when the press made no request
    /// and so has nothing to say: a message left by an earlier press is not this press's.
    /// A press that asks for nothing reads nothing and opens nothing; the guide records its
    /// skip itself.
    func perform(guidePress result: SetupPlan.KeepItRunningResult) -> String? {
        if let choice = result.wantedAfterPress { saveChoice(choice) }
        guard let request = result.request else { return nil }
        carryOut(request)
        return message
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
