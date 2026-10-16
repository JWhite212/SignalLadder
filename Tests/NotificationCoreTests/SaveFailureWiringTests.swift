import XCTest
@testable import NotificationCore

/// The rule editor's two saves report a failure in the words `EditorText.saveFailureReason`
/// gives, and never as `String(describing:)`. The app target has no tests, so this reads
/// its source, as `SetupWiringTests` does.
final class SaveFailureWiringTests: XCTestCase {
    private func model() throws -> String {
        PowerHoldWiringTests.code(of: try XCTUnwrap(AppSources.read("RuleEditorModel.swift"),
                                                    "RuleEditorModel.swift cannot be read at \(AppSources.directory.path)"))
    }

    private func count(_ needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    func testBothSavesGiveTheReasonInTheErrorsOwnWords() throws {
        let source = try model()
        for signature in ["func save() -> SaveResult {", "func saveReplacingDisk() -> SaveResult {"] {
            let body = try XCTUnwrap(OnCallWiringTests.body(of: signature, in: source), signature)
            XCTAssertEqual(count("return .failed(EditorText.saveFailureReason(error))", in: body), 1, signature)
            XCTAssertEqual(count("String(describing:", in: body), 0, signature)
        }
    }
}
