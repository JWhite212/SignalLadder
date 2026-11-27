import XCTest
@testable import NotificationCore

/// The recipe file (sound editor plan, Task 2, Rulings 1 and 10). Modelled on the
/// rules file's codec: versioned, unknown keys refused, a newer version said to
/// need a newer SignalLadder.
final class SoundRecipeCodecTests: XCTestCase {
    private typealias F = SoundFixtures

    private let valid = """
    {"version":1,"source":{"name":"source.wav","frames":1000,"digest":"abc"},\
    "segments":[{"type":"clip","start":0,"end":1000,"gainDB":0,"fades":[]}],\
    "rendered":{"frames":1000,"digest":"def"}}
    """

    private func decode(_ json: String) throws -> SoundRecipeCodec.Stored {
        try SoundRecipeCodec.decode(Data(json.utf8))
    }

    private func error(of json: String, file: StaticString = #filePath, line: UInt = #line) -> SoundRecipeCodec.FileError? {
        do {
            _ = try decode(json)
            return nil
        } catch let error as SoundRecipeCodec.FileError {
            return error
        } catch {
            XCTFail("\(error)", file: file, line: line)
            return nil
        }
    }

    private func reason(of json: String, file: StaticString = #filePath, line: UInt = #line) -> String {
        guard case .unreadable(let reason)? = error(of: json, file: file, line: line) else {
            XCTFail("expected an unreadable file", file: file, line: line)
            return ""
        }
        return reason
    }

    private func roundTrip(_ recipe: SoundRecipe, file: StaticString = #filePath, line: UInt = #line) throws {
        let stored = SoundRecipeCodec.Stored(recipe: recipe, renderedDigest: "rendered-digest")
        let back = try SoundRecipeCodec.decode(SoundRecipeCodec.encode(stored))
        XCTAssertEqual(back, stored, file: file, line: line)
    }

    // MARK: - Reading

    func testAValidFileIsRead() throws {
        let stored = try decode(valid)
        XCTAssertEqual(stored.recipe.source, F.source(1000, digest: "abc"))
        XCTAssertEqual(stored.recipe.segments, [F.clip(0, 1000)])
        XCTAssertEqual(stored.renderedDigest, "def")
        XCTAssertEqual(stored.renderedFrames, 1000)
    }

    func testTheVersionWrittenIsOne() throws {
        XCTAssertEqual(SoundRecipeCodec.currentVersion, 1)
        let data = try SoundRecipeCodec.encode(.init(recipe: F.whole(), renderedDigest: "d"))
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(text.contains("\"version\" : 1"), text)
    }

    func testANewerVersionIsReportedAsNeedingANewerSignalLadder() {
        XCTAssertEqual(error(of: valid.replacingOccurrences(of: "\"version\":1", with: "\"version\":2")),
                       .unsupportedVersion(2))
    }

    func testANewerVersionIsReportedWhateverElseItHoldsAndNoUnknownKeyIsMistakenForTheFault() {
        let newer = #"{"version":9,"layers":[],"source":42}"#
        XCTAssertEqual(error(of: newer), .unsupportedVersion(9))
    }

    func testAVersionBelowOneIsUnreadable() {
        XCTAssertTrue(reason(of: valid.replacingOccurrences(of: "\"version\":1", with: "\"version\":0"))
            .contains("\"version\" must be 1 or higher"))
    }

    func testSomethingThatIsNotJSONIsUnreadable() {
        XCTAssertFalse(reason(of: "not json").isEmpty)
        XCTAssertFalse(reason(of: "").isEmpty)
    }

    func testAFileWithNoVersionIsUnreadable() {
        XCTAssertTrue(reason(of: valid.replacingOccurrences(of: "\"version\":1,", with: "")).contains("version"))
    }

    // MARK: - Unknown keys

    func testAnUnknownKeyIsRefusedAtEveryLevel() {
        let cases = [
            valid.replacingOccurrences(of: "\"version\":1,", with: "\"version\":1,\"extra\":1,"),
            valid.replacingOccurrences(of: "\"name\":", with: "\"extra\":1,\"name\":"),
            valid.replacingOccurrences(of: "\"type\":\"clip\",", with: "\"type\":\"clip\",\"extra\":1,"),
            valid.replacingOccurrences(of: "\"rendered\":{", with: "\"rendered\":{\"extra\":1,"),
            valid.replacingOccurrences(of: "\"fades\":[]", with:
                #""fades":[{"kind":"in","frames":10,"into":0,"extra":1}]"#),
        ]
        for json in cases {
            XCTAssertTrue(reason(of: json).contains("unknown key \"extra\""), json)
        }
    }

    func testAnUnknownKeyInASilenceIsRefused() {
        let json = valid.replacingOccurrences(
            of: #"{"type":"clip","start":0,"end":1000,"gainDB":0,"fades":[]}"#,
            with: #"{"type":"clip","start":0,"end":500,"gainDB":0,"fades":[]},{"type":"silence","frames":500,"gainDB":1}"#)
        XCTAssertTrue(reason(of: json).contains("unknown key \"gainDB\""))
    }

    func testAClipCannotCarryASilencesKey() {
        let json = valid.replacingOccurrences(of: "\"fades\":[]", with: "\"fades\":[],\"frames\":5")
        XCTAssertTrue(reason(of: json).contains("unknown key \"frames\""))
    }

    func testAPieceOfAnUnknownTypeIsRefused() {
        XCTAssertTrue(reason(of: valid.replacingOccurrences(of: "\"clip\"", with: "\"tone\"")).contains("unknown piece type \"tone\""))
    }

    func testAFadeOfAnUnknownKindIsRefused() {
        let json = valid.replacingOccurrences(of: "\"fades\":[]", with: #""fades":[{"kind":"wobble","frames":10,"into":0}]"#)
        XCTAssertTrue(reason(of: json).contains("unknown fade kind \"wobble\""))
    }

    func testAMissingKeyIsNamed() {
        XCTAssertTrue(reason(of: valid.replacingOccurrences(of: ",\"digest\":\"abc\"", with: "")).contains("missing \"digest\""))
        XCTAssertTrue(reason(of: valid.replacingOccurrences(of: "\"gainDB\":0,", with: "")).contains("missing \"gainDB\""))
    }

    func testAFrameCountThatIsNotAWholeNumberIsRefused() {
        XCTAssertFalse(reason(of: valid.replacingOccurrences(of: "\"end\":1000", with: "\"end\":999.5")).isEmpty)
    }

    // MARK: - What a recipe may not be

    func testAFileWhosePiecesBreakTheRecipeIsUnreadableAndSaysHow() {
        XCTAssertTrue(reason(of: valid.replacingOccurrences(of: "\"end\":1000", with: "\"end\":1001"))
            .contains("piece 1 is not inside the source"))
        XCTAssertTrue(reason(of: valid.replacingOccurrences(of: "\"end\":1000", with: "\"end\":0")).contains("piece 1 is empty"))
        XCTAssertTrue(reason(of: valid.replacingOccurrences(of: "\"segments\":[{\"type\":\"clip\",\"start\":0,\"end\":1000,\"gainDB\":0,\"fades\":[]}]",
                                                            with: "\"segments\":[]")).contains("no pieces"))
        XCTAssertTrue(reason(of: valid.replacingOccurrences(of: "\"gainDB\":0", with: "\"gainDB\":61")).contains("gain"))
    }

    func testASourceWithNoNameDigestOrFramesIsUnreadable() {
        XCTAssertTrue(reason(of: valid.replacingOccurrences(of: "\"source.wav\"", with: "\"\"")).contains("source"))
        XCTAssertTrue(reason(of: valid.replacingOccurrences(of: "\"digest\":\"abc\"", with: "\"digest\":\" \"")).contains("source"))
        XCTAssertTrue(reason(of: valid.replacingOccurrences(of: "\"frames\":1000,\"digest\":\"abc\"", with: "\"frames\":0,\"digest\":\"abc\""))
            .contains("source"))
    }

    func testASourceOverOneHundredTwentySecondsIsUnreadable() {
        let json = valid.replacingOccurrences(of: "\"frames\":1000,\"digest\":\"abc\"", with: "\"frames\":5760001,\"digest\":\"abc\"")
        XCTAssertTrue(reason(of: json).contains("source is 5760001 frames"))
    }

    func testARenderedLengthThatIsNotThePiecesLengthIsUnreadable() {
        let json = valid.replacingOccurrences(of: "\"rendered\":{\"frames\":1000", with: "\"rendered\":{\"frames\":999")
        XCTAssertTrue(reason(of: json).contains("999 frames long, but its pieces make 1000"))
    }

    func testARenderedFileWithNoDigestIsUnreadable() {
        let json = valid.replacingOccurrences(of: "\"digest\":\"def\"", with: "\"digest\":\"\"")
        XCTAssertTrue(reason(of: json).contains("no digest"))
    }

    func testPiecesThatAreOnePieceCutInTwoAreReadAsOne() throws {
        let json = valid.replacingOccurrences(
            of: #"{"type":"clip","start":0,"end":1000,"gainDB":0,"fades":[]}"#,
            with: #"{"type":"clip","start":0,"end":400,"gainDB":0,"fades":[]},{"type":"clip","start":400,"end":1000,"gainDB":0,"fades":[]}"#)
        XCTAssertEqual(try decode(json).recipe.segments, [F.clip(0, 1000)])
    }

    // MARK: - Round trips

    func testAnUntouchedRecipeRoundTrips() throws {
        try roundTrip(F.whole())
    }

    func testEveryEditRoundTrips() throws {
        let base = F.recipe([F.clip(0, 300), F.clip(1000, 1300), .silence(frames: 50), F.clip(2000, 2200, gain: 3.5)])
        let copied = try base.excerpt(of: 100..<400)
        let edits: [SoundEdit] = [
            .trim(100..<500), .delete(100..<500), .cut(100..<500), .paste(copied, replacing: 600..<600),
            .paste(copied, replacing: 100..<200), .duplicate(250..<450), .fadeIn(0..<600), .fadeOut(200..<700),
            .gain(300..<650, dB: -4.25), .repeatSelection(100..<400, times: 3, gapFrames: 480),
            .repeatSelection(0..<base.frameCount, times: 2, gapFrames: 0),
        ]
        for edit in edits {
            try roundTrip(edit.applied(to: base))
        }
    }

    func testARecipeWithEveryKindOfPieceFadeAndGainRoundTrips() throws {
        var recipe = F.recipe([F.clip(0, 300), .silence(frames: 100), F.clip(1000, 1300)])
        for edit in [SoundEdit.fadeIn(0..<500), .fadeOut(100..<700), .gain(50..<150, dB: 0.07), .gain(0..<700, dB: -12.34)] {
            recipe = try edit.applied(to: recipe)
        }
        XCTAssertTrue(recipe.segments.contains { if case .silence = $0 { return true } else { return false } })
        try roundTrip(recipe)
    }

    func testAnEncodedFileIsSortedAndPrettyPrintedSoItDiffsCleanly() throws {
        let stored = SoundRecipeCodec.Stored(recipe: F.whole(), renderedDigest: "d")
        let first = try SoundRecipeCodec.encode(stored)
        XCTAssertEqual(first, try SoundRecipeCodec.encode(stored))
        let text = try XCTUnwrap(String(data: first, encoding: .utf8))
        XCTAssertTrue(text.contains("\n"))
        let rendered = try XCTUnwrap(text.range(of: "\"rendered\""))
        let segments = try XCTUnwrap(text.range(of: "\"segments\""))
        let source = try XCTUnwrap(text.range(of: "\"source\""))
        XCTAssertLessThan(rendered.lowerBound, segments.lowerBound)
        XCTAssertLessThan(segments.lowerBound, source.lowerBound)
    }

    func testTheRenderedLengthIsWrittenAsTheRecipesOwn() throws {
        let recipe = try SoundEdit.trim(100..<400).applied(to: F.whole())
        let data = try SoundRecipeCodec.encode(.init(recipe: recipe, renderedDigest: "d"))
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(text.contains("\"frames\" : 300"), text)
    }
}
