// Sources/NotificationCore/LaunchAtLogin.swift
import Foundation

/// What macOS says about the app's login item, as the four values the system's
/// service-management status has (M5 plan, Ruling 15).
///
/// The core imports no framework that names them, so the app target reads the
/// system's status and hands over the case that matches. Nothing here is
/// remembered: the status has no change notification, so it is read afresh each
/// time it is wanted, and what is shown is what the last read said.
public enum LoginItemStatus: CaseIterable, Equatable, Sendable {
    /// Nothing is registered for this app.
    case notRegistered
    /// The system says it is registered and enabled. The only status that says
    /// the app starts at login. A Login Items entry the user added by hand in
    /// System Settings reads this on macOS 26.7.1 (measured on 2026-10-05), so it
    /// is shown as on like any other, and switching it off removes that entry
    /// (`LaunchAtLogin.Request`). That macOS 14 and 15 read the same was not seen.
    case enabled
    /// Registered, but the system says it needs the user's approval, which is
    /// where a switch the user turned off in System Settings reads.
    case requiresApproval
    /// The system cannot find a registration for this copy. An unbundled program
    /// reads this, and so does a signed bundle that was never registered, in
    /// /Applications and outside any Applications folder (all three measured on
    /// macOS 26.7.1 on 2026-10-05), so it cannot tell a copy that cannot register
    /// from one that has not (`AppLocation`). That macOS 14 and 15 read the same
    /// was not seen.
    case notFound
}

/// What the login item shows, offers and reports (M5 plan, Ruling 15, O12).
///
/// **The user's, and never assumed.** The app never switches Launch at login on
/// by itself, and never again once the user has switched it off in System
/// Settings, since registering is reported to overwrite a choice made there,
/// which was not tested. Only the user's own press asks for it. Every function
/// here is a decision about words and buttons, made from what was read, and none
/// calls the system. The app target reads the status, the place the app runs from
/// and the saved wish, asks these what to show, and carries out what the user
/// presses. Whatever a request answers, the status is read again afterwards, and
/// that is what is shown.
public enum LaunchAtLogin {
    // MARK: - What Settings shows

    /// What the Settings window shows for the login item.
    public enum State: Equatable, Sendable {
        /// The system says it is enabled.
        case on
        /// Not enabled, and it can be switched on from here. `wanted` is whether
        /// the user had switched it on, which the system now does not show.
        case off(wanted: Bool)
        /// Registered, and the system says it needs approval, which is where a
        /// switch turned off in System Settings reads.
        case switchedOffInSystemSettings
        /// Not offered, and the reason why.
        case unavailable(Unavailable)

        /// Whether the switch reads on.
        public var isOn: Bool { self == .on }

        /// Whether the user can press the switch. Where the system has the item
        /// switched off in System Settings, its two buttons are the way, and
        /// where it is not offered there is nothing to press.
        public var switchIsEnabled: Bool {
            switch self {
            case .on, .off: return true
            case .switchedOffInSystemSettings, .unavailable: return false
            }
        }
    }

    /// Why Launch at login is not offered, which is a reason the user can act on.
    public enum Unavailable: Equatable, Sendable, CaseIterable {
        /// macOS runs this copy from a temporary place of its own.
        case translocated
        /// This copy is somewhere the app does not register from: a folder that
        /// is not Applications, a mounted volume, or no bundle at all.
        case elsewhere
    }

    /// What Settings shows for a status read, the user's saved wish and where the
    /// app runs from.
    ///
    /// | status | in Applications | translocated | elsewhere |
    /// | --- | --- | --- | --- |
    /// | enabled | on | on | on |
    /// | not registered | off | not offered | off |
    /// | needs approval | switched off in System Settings | not offered | switched off in System Settings |
    /// | not found | off | not offered | not offered |
    ///
    /// - An enabled status is on wherever the app is, since it is what the system
    ///   read and is shown as it was read.
    /// - A copy macOS runs from a translocated path is offered no registration,
    ///   whatever the system reads for it. Registering from one is reported to fail
    ///   or to misread, so neither a status of not registered nor of not found is
    ///   offered a switch there, and a status of needs approval is not offered its
    ///   buttons, one of which registers. The way out is the move the reason gives,
    ///   after which the copy in Applications reads its own status. Only an enabled
    ///   status is shown from there, since showing it asks for nothing.
    /// - Not found is the status a never-registered bundle reads, in /Applications
    ///   and outside it (measured on macOS 26.7.1 on 2026-10-05), so it is off and
    ///   registrable only from an Applications folder, and from anywhere else it
    ///   is not offered, since nothing else can tell that copy from one that
    ///   cannot register (`AppLocation`). A status of not registered says that the
    ///   system looked, so it is off wherever the copy is, a translocated one apart.
    /// - A needs-approval status is the system's own, so it is shown as it was read
    ///   from anywhere a registration can be asked for.
    /// - `wanted` changes only what an off item says: that the user had switched
    ///   it on and the system does not show it. It is never a reason to say it is
    ///   on.
    public static func state(status: LoginItemStatus, wanted: Bool, location: AppLocation) -> State {
        if location == .translocated && status != .enabled { return .unavailable(.translocated) }
        switch status {
        case .enabled:
            return .on
        case .requiresApproval:
            return .switchedOffInSystemSettings
        case .notRegistered:
            return .off(wanted: wanted)
        case .notFound:
            return location.isInApplicationsFolder ? .off(wanted: wanted) : .unavailable(.elsewhere)
        }
    }

    // MARK: - What the buttons do

    /// What a press of a button asks the app to do.
    public enum Action: CaseIterable, Equatable, Sendable {
        /// Registers the login item: the finding's button. The Settings switch asks
        /// for the same when it is turned on (`request(switchTurnedOn:)`).
        case turnOn
        /// Registers it again, for an item the system has switched off. What
        /// `register()` answers for such an item was not measured. A second
        /// registration of an enabled item raised no error on macOS 26.7.1
        /// (`Request`), and where one answers already registered it is read as so.
        /// Either way the item may still not be enabled, so what the user is told
        /// comes from the status read again afterwards
        /// (`outcomeAfterReading(_:ofRequest:statusAfter:)`).
        case switchOnAgain
        /// Opens System Settings at Login Items, where the user decides.
        case openLoginItems

        /// The request this makes of the system, or nil when it makes none and
        /// only opens System Settings. The app target does what this says and
        /// chooses nothing.
        public var request: Request? {
            switch self {
            case .turnOn, .switchOnAgain: return .register
            case .openLoginItems: return nil
            }
        }
    }

    /// What the app asks of the system for the login item.
    ///
    /// Measured on macOS 26.7.1 on 2026-10-05, with a signed copy in /Applications
    /// and its own bundle identifier: `register()` gave enabled and one Login Items
    /// entry, and a second `register()` raised no error (12 was not seen) and made
    /// no second entry. `unregister()`, called synchronously, removed an entry the
    /// owner had added by hand in System Settings, after which the status read not
    /// registered, and a second `unregister()` raised no error (6 was not seen).
    /// None of it was seen on macOS 14 or 15.
    public enum Request: Equatable, Sendable {
        case register
        case unregister
    }

    /// The button the on-call finding about the login item carries, which the
    /// user presses so that acting on it is one click and nothing is switched on
    /// silently (O12): turn on when it can be registered, open Login Items when
    /// the system has it switched off, and none when it is not offered, where the
    /// finding gives the reason instead (`LaunchAtLoginText.reason(for:)`). An item
    /// that is on is no finding and has none.
    public static func findingAction(for state: State) -> Action? {
        switch state {
        case .off: return .turnOn
        case .switchedOffInSystemSettings: return .openLoginItems
        case .on, .unavailable: return nil
        }
    }

    /// The buttons Settings shows beside the switch: for an item the system has
    /// switched off, a way to the place it can be switched back on and a way to
    /// ask again. For any other state the switch is all there is, or nothing is
    /// offered, and no button does nothing. A translocated copy is never in the
    /// state that has them (`state(status:wanted:location:)`), so it is not offered
    /// the one that registers.
    ///
    /// **There is no Turn on button here for an item that is off.** The plan has the
    /// finding and Settings each carry one (O12, Ruling 15). In Settings the switch
    /// is the one click that asks for it, so a button beside a switch of the same
    /// name would be two controls for one act, and the button is the finding's
    /// alone (`findingAction(for:)`). If the owner wants it in Settings too, it is
    /// one arm here.
    public static func settingsActions(for state: State) -> [Action] {
        state == .switchedOffInSystemSettings ? [.openLoginItems, .switchOnAgain] : []
    }

    /// What a press of the Settings switch asks of the system: to register when it
    /// was turned on, which is what the finding's Turn on button asks too, and to
    /// unregister when it was turned off. It is the one choice between the two, so
    /// the app target makes none (Ruling 10).
    public static func request(switchTurnedOn: Bool) -> Request {
        switchTurnedOn ? .register : .unregister
    }

    // MARK: - What the rest of the app asks

    /// Whether the app starts at login: true only for an enabled status, and what
    /// on-call mode reads. Every other status is false, so the on-call finding
    /// never claims a login item the app has not read.
    public static func startsAtLogin(status: LoginItemStatus) -> Bool {
        status == .enabled
    }

    /// Whether the menu's one line about the login item appears: the user
    /// switched it on, and the system does not show it enabled. It gives way
    /// while on call to the on-call finding, which says the same and more, and
    /// the icon does not change either way (O12). Nothing is re-registered
    /// because of it.
    public static func reconcile(wanted: Bool, status: LoginItemStatus, onCall: Bool) -> Bool {
        wanted && !startsAtLogin(status: status) && !onCall
    }

    // MARK: - A request that failed

    /// The domain a failed request's error carries, read on macOS 26.7.1 on
    /// 2026-09-30. The system's own constant for it is only there from macOS 15,
    /// and the floor is 14, so it is compared as text. That macOS 14 and 15 give
    /// the same text was not seen, so a request whose domain is any other is a
    /// failure in the app's own words, which is the safe way to be wrong.
    public static let errorDomain = "SMAppServiceErrorDomain"
    /// Registering from a copy whose signature the system did not accept
    /// (`kSMErrorInvalidSignature`).
    public static let invalidSignatureCode = 3
    /// Unregistering when there is nothing to remove (`kSMErrorJobNotFound`). A
    /// second `unregister()` raised no error on macOS 26.7.1 (2026-10-05), so it was
    /// not seen there; it is kept as so where it does occur (`outcome(ofRequest:domain:code:)`).
    public static let jobNotFoundCode = 6
    /// Registering when the user has not approved it (`kSMErrorLaunchDeniedByUser`).
    public static let launchDeniedCode = 11
    /// Registering when it already is (`kSMErrorAlreadyRegistered`). A second
    /// `register()` raised no error on macOS 26.7.1 (2026-10-05), so it was not
    /// seen there; it is kept as so where it does occur (`outcome(ofRequest:domain:code:)`).
    public static let alreadyRegisteredCode = 12

    /// What a failed request comes to.
    public enum Outcome: Equatable, Sendable {
        /// What was asked is so: the request raised no error, which is what a second
        /// registration and a second unregistration gave on macOS 26.7.1 (measured
        /// on 2026-10-05), or it was already registered, or there was nothing to
        /// remove, which are the two codes that were not seen there and are kept as
        /// so where they do occur. The status is read again and
        /// shown, as it is after any request, and for a registration it is compared
        /// with what was asked (`outcomeAfterReading(_:ofRequest:statusAfter:)`).
        case succeeded
        /// The system needs the user's approval before it will start the app at
        /// login.
        case needsApproval
        /// A registration the system did not refuse, after which the status read
        /// again still does not show the item enabled.
        case notEnabled
        /// The system did not accept this copy's signature.
        case unsignedCopy
        /// Anything else, with the system's code.
        case failed(Request, code: Int)
    }

    /// Reads the error a request failed with.
    ///
    /// Each code is read only for the request that raises it, and only in the
    /// domain it comes from: registering gives 12 (already registered, so
    /// what was asked is so), 11 (the user has not approved) and 3 (the signature
    /// was not accepted); unregistering gives 6 (nothing to remove, which is so).
    /// A second registration and a second unregistration raised neither 12 nor 6
    /// on macOS 26.7.1 (measured on 2026-10-05; not seen on macOS 14 or 15), so
    /// those two are read as so only where they do occur, which is the safe
    /// reading, since the status is read again and is what is shown.
    /// Any other code, a known one in the wrong request, and a known one from any
    /// other domain, is a failure with its code, in the app's own words.
    public static func outcome(ofRequest request: Request, domain: String, code: Int) -> Outcome {
        guard domain == errorDomain else { return .failed(request, code: code) }
        switch (request, code) {
        case (.register, alreadyRegisteredCode), (.unregister, jobNotFoundCode): return .succeeded
        case (.register, launchDeniedCode): return .needsApproval
        case (.register, invalidSignatureCode): return .unsignedCopy
        default: return .failed(request, code: code)
        }
    }

    /// What a request came to, once the status has been read again afterwards.
    ///
    /// A registration the system did not refuse can leave the item not enabled. The
    /// SDK says an item that needs approval has been registered, so "Switch on
    /// again", for an item the system has switched off, may come back as a success
    /// that changes nothing: as 12, which `outcome(ofRequest:domain:code:)` reads
    /// as so, or as no error, which is what a second registration of an enabled
    /// item gave on macOS 26.7.1 (measured on 2026-10-05). What `register()`
    /// answers for an item that needs approval was not measured. With nothing said
    /// the user would press a button and see no result. A registration that came to
    /// what was asked, with a status that does not read enabled, is therefore
    /// said: as needing approval when that is what the status reads, and as still
    /// not enabled otherwise.
    /// Anything else is as it was: a failure is already said, an enabled status is
    /// what was asked, and an unregistration is left to the status shown after it.
    public static func outcomeAfterReading(_ outcome: Outcome, ofRequest request: Request,
                                           statusAfter: LoginItemStatus) -> Outcome {
        guard request == .register, outcome == .succeeded else { return outcome }
        switch statusAfter {
        case .enabled: return .succeeded
        case .requiresApproval: return .needsApproval
        case .notRegistered, .notFound: return .notEnabled
        }
    }
}
