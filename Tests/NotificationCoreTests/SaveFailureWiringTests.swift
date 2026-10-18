import XCTest
@testable import NotificationCore

/// The rule editor's two saves report a failure in the words `EditorText.saveFailureReason`
/// gives, and never as `String(describing:)`. The app target has no tests, so this reads
/// its source, as `SetupWiringTests` does.
final class SaveFailureWiringTests: XCTestCase {
    private func model() throws -> String {
        SourceCode.code(of: try XCTUnwrap(AppSources.read("RuleEditorModel.swift"),
                                                    "RuleEditorModel.swift cannot be read at \(AppSources.directory.path)"))
    }

    func testBothSavesGiveTheReasonInTheErrorsOwnWords() throws {
        let source = try model()
        for signature in ["func save() -> SaveResult {", "func saveReplacingDisk() -> SaveResult {"] {
            let body = try XCTUnwrap(SourceCode.body(of: signature, in: source), signature)
            XCTAssertEqual(count("return .failed(EditorText.saveFailureReason(error))", in: body), 1, signature)
            XCTAssertEqual(count("String(describing:", in: body), 0, signature)
        }
    }
}
