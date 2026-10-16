import Foundation
import XCTest
@testable import NotificationCore

/// What the rule editor says when a save fails. Before, the reason was
/// `String(describing: error)`, which for a Cocoa write error is a dump such as
/// `Error Domain=NSCocoaErrorDomain Code=513 "…" UserInfo={…}` (workflow audit,
/// 2026-10-16, finding 14). It is now the error's own message, which every error
/// the save can throw has: Cocoa's file errors, the codec's, and the rules file's
/// own (`RulesFile.ReadError`, a `LocalizedError`).
final class SaveFailureTextTests: XCTestCase {
    private struct Described: LocalizedError {
        var errorDescription: String? { "the disk is full" }
    }

    func testACocoaWriteErrorIsGivenInItsOwnWordsWithNoDump() {
        let error = CocoaError(.fileWriteNoPermission, userInfo: [NSFilePathErrorKey: "/Users/x/rules.json"])
        let reason = EditorText.saveFailureReason(error)
        XCTAssertFalse(reason.contains("Error Domain"), reason)
        XCTAssertFalse(reason.contains("UserInfo"), reason)
        XCTAssertFalse(reason.contains("Code="), reason)
        XCTAssertTrue(reason.localizedCaseInsensitiveContains("permission"), reason)
    }

    func testAnErrorThatDescribesItselfIsGivenInThoseWords() {
        XCTAssertEqual(EditorText.saveFailureReason(Described()), "the disk is full")
    }
}
