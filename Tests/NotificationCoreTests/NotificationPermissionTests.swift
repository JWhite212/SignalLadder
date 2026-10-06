import XCTest
import UserNotifications
@testable import NotificationCore

/// What the system's notification authorisation reads as (M5 plan, Ruling 16, O13,
/// Task 7). The probe hands over the status's raw value and the core says which of
/// three things it is. Nothing here asks the system, shows a dialog or reads a
/// preference: each test gives a number and reads what the core makes of it. The
/// numbers for the four statuses macOS has are read off `UNAuthorizationStatus`'s
/// own constants, which asks nothing of the system, so that the core's table is held
/// to the numbers the SDK gives and not to ones typed here.
final class NotificationPermissionTests: XCTestCase {
    /// The raw values `UNAuthorizationStatus` has in the SDK the tests are built against
    /// (`UNNotificationSettings.h`): not determined, denied, authorized, provisional and
    /// ephemeral, in that order from 0. The first four are read from the SDK itself.
    private let notDetermined = UNAuthorizationStatus.notDetermined.rawValue
    private let denied = UNAuthorizationStatus.denied.rawValue
    private let authorized = UNAuthorizationStatus.authorized.rawValue
    private let provisional = UNAuthorizationStatus.provisional.rawValue
    /// Ephemeral is for App Clips, and the SDK marks it unavailable on macOS, so the
    /// compiler refuses to name it here. Its 4 is the header's word, and nothing in the
    /// build holds it.
    private let ephemeral = 4

    /// `DeliveryStatusProbe`'s own rule for `authorized`, stated for a raw value: the
    /// status is authorized or provisional, and nothing else is. The permission is
    /// held to this below, so that the guide and the health line, which is made from
    /// `authorized`, cannot disagree about whether the app may post.
    private func probeCountsAsAuthorised(_ raw: Int) -> Bool {
        raw == authorized || raw == provisional
    }

    /// The five known values, a spread either side of them, and the ends of the
    /// range, so that a rule tested over it is not only a rule about five numbers.
    private var spread: [Int] {
        let around: [Int] = Array(-5...12)
        let far: [Int] = [100, 255, 1_000, Int(Int32.max), Int(Int32.min), Int.max, Int.min]
        return around + far
    }

    // MARK: - The cases

    func testTheCasesAreExactlyNotAskedDeniedAndAllowed() {
        XCTAssertEqual(NotificationPermission.allCases.count, 3)
        XCTAssertEqual(Set(NotificationPermission.allCases), [.notAsked, .denied, .allowed])
    }

    // MARK: - The mapping

    func testEachKnownRawValueReadsAsTheTableSaysItDoes() {
        let table: [(raw: Int, status: String, expected: NotificationPermission)] = [
            (notDetermined, "not determined", .notAsked),
            (denied, "denied", .denied),
            (authorized, "authorized", .allowed),
            (provisional, "provisional", .allowed),
            (ephemeral, "ephemeral", .denied),
        ]
        XCTAssertEqual(table.map(\.raw), [0, 1, 2, 3, 4],
                       "the table is the five numbers the core's doc comment lists, in order")
        for row in table {
            XCTAssertEqual(NotificationPermission.reading(authorizationStatus: row.raw), row.expected,
                           "\(row.raw), \(row.status)")
        }
    }

    /// A status a later macOS adds reads as denied: not allowed, since the probe does
    /// not count it as authorised, and not "never asked", since no request is known
    /// to be able to show a dialog for it. The safe direction (Global Constraints,
    /// the first rule).
    func testAValuePastTheKnownRangeIsDeniedAndNeitherAllowedNorNotAsked() {
        for raw in [5, 6, 7, 99, 255, 1_000, Int(Int32.max), Int.max] as [Int] {
            let permission = NotificationPermission.reading(authorizationStatus: raw)
            XCTAssertEqual(permission, .denied, "\(raw)")
            XCTAssertNotEqual(permission, .allowed, "\(raw)")
            XCTAssertNotEqual(permission, .notAsked, "\(raw)")
        }
    }

    func testANegativeValueIsDeniedAndNeitherAllowedNorNotAsked() {
        for raw in [-1, -2, -1_000, Int(Int32.min), Int.min] as [Int] {
            let permission = NotificationPermission.reading(authorizationStatus: raw)
            XCTAssertEqual(permission, .denied, "\(raw)")
            XCTAssertNotEqual(permission, .allowed, "\(raw)")
            XCTAssertNotEqual(permission, .notAsked, "\(raw)")
        }
    }

    /// Ephemeral is for App Clips and is unavailable on macOS, so it is a value the
    /// app is not expected to meet. If it ever arrives it must not be allowed, and it
    /// must not offer a request that may show no dialog.
    func testEphemeralIsNeitherAllowedNorNotAsked() {
        let permission = NotificationPermission.reading(authorizationStatus: ephemeral)
        XCTAssertNotEqual(permission, .allowed)
        XCTAssertNotEqual(permission, .notAsked)
    }

    /// The rule, and not only the table: a raw value reads as allowed exactly where the
    /// probe's `authorized` is true for it. Where the two differ, the guide would tick
    /// Notifications for a status the health line calls denied, or the reverse.
    func testAllowedHoldsExactlyWhereTheProbeCountsTheStatusAsAuthorised() {
        for raw in spread {
            XCTAssertEqual(NotificationPermission.reading(authorizationStatus: raw) == .allowed,
                           probeCountsAsAuthorised(raw), "\(raw)")
        }
        XCTAssertEqual(spread.filter(probeCountsAsAuthorised), [2, 3], "the rule is true of 2 and 3 and nothing else")
    }

    /// A request can show the dialog only for a status of not determined, which is the
    /// one the system says is the user not having chosen yet. Nothing else is read as
    /// never asked.
    func testNotAskedIsOnlyWhatTheSystemCallsNotDetermined() {
        for raw in spread {
            XCTAssertEqual(NotificationPermission.reading(authorizationStatus: raw) == .notAsked,
                           raw == notDetermined, "\(raw)")
        }
    }

    // MARK: - The SDK's numbers

    /// The core takes a raw value so that it needs no import of `UserNotifications`,
    /// and its table rests on the numbers the system gives its statuses. This holds
    /// those numbers to the SDK the tests are built against, for the four statuses
    /// macOS has, and so holds `probeCountsAsAuthorised` to the probe's `.authorized`
    /// and `.provisional`, which the source test below pins by name. Ephemeral is not
    /// one of the four: macOS marks it unavailable, so its 4 is not held here.
    func testTheRawValuesTheCoreReadsAreTheOnesTheSDKGivesItsStatuses() {
        XCTAssertEqual(UNAuthorizationStatus.notDetermined.rawValue, 0, "not determined")
        XCTAssertEqual(UNAuthorizationStatus.denied.rawValue, 1, "denied")
        XCTAssertEqual(UNAuthorizationStatus.authorized.rawValue, 2, "authorized")
        XCTAssertEqual(UNAuthorizationStatus.provisional.rawValue, 3, "provisional")
    }

    // MARK: - What a status made without a permission reads as

    func testAStatusKnownOnlyAsAuthorisedReadsAsAllowedAndOtherwiseAsDenied() {
        XCTAssertEqual(NotificationPermission.derived(fromAuthorized: true), .allowed)
        XCTAssertEqual(NotificationPermission.derived(fromAuthorized: false), .denied)
    }

    /// Only a read of the system's status can say a request could still show a dialog,
    /// and a caller that knows only `authorized` has not made one.
    func testAStatusKnownOnlyAsAuthorisedIsNeverNotAsked() {
        for authorised in [false, true] {
            XCTAssertNotEqual(NotificationPermission.derived(fromAuthorized: authorised), .notAsked)
        }
    }

    /// The default and the reading agree on every value but one: the reading says not
    /// asked for not determined, which `authorized` cannot say, and the default says
    /// denied there. It never says allowed where the reading does not, or the reverse.
    func testTheDefaultAgreesWithTheReadingExceptWhereTheReadingSaysNotAsked() {
        for raw in spread {
            let read = NotificationPermission.reading(authorizationStatus: raw)
            let derived = NotificationPermission.derived(fromAuthorized: probeCountsAsAuthorised(raw))
            XCTAssertEqual(derived, read == .notAsked ? .denied : read, "\(raw)")
        }
    }

    // MARK: - The probe

    /// `NotificationCapture` has no test target, so what the probe does with this is
    /// held by reading its source, as the wiring tests do for the app's. The rule the
    /// tests above state is about the probe's `authorized`; these hold the probe to it.
    private func probeCode() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // NotificationCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // package root
            .appendingPathComponent("Sources/NotificationCapture/DeliveryStatusProbe.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        return PowerHoldWiringTests.code(of: source).replacingOccurrences(of: "\n", with: " ")
    }

    /// The probe still counts exactly authorized and provisional as authorised, which is
    /// the rule `probeCountsAsAuthorised` states, and hands the status's raw value to
    /// the core to read, as the `permission` of what it returns.
    func testTheProbeCountsAuthorizedAndProvisionalAndHandsTheRawStatusToTheCore() throws {
        let code = try probeCode()
        XCTAssertTrue(code.contains("let authorized = settings.authorizationStatus == .authorized "
                                    + "|| settings.authorizationStatus == .provisional "),
                      "the probe's rule for authorized is not the one these tests state")
        XCTAssertTrue(code.contains("permission: NotificationPermission.reading("
                                    + "authorizationStatus: settings.authorizationStatus.rawValue)"),
                      "the probe does not give the core the status's raw value for the permission")
        XCTAssertEqual(code.components(separatedBy: "settings.authorizationStatus").count - 1, 3,
                       "the status is read in three places: the two it counts, and the raw value")
    }

    /// A status made with no permission derives it from `authorized`, in the core, and
    /// never holds a fixed value that could contradict it.
    func testADeliveryStatusMadeWithoutAPermissionDerivesItFromAuthorized() throws {
        let code = try probeCode()
        XCTAssertTrue(code.contains("permission: NotificationPermission? = nil"))
        XCTAssertTrue(code.contains("self.permission = permission ?? .derived(fromAuthorized: authorized)"))
    }
}
