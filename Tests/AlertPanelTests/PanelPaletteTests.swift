import XCTest
import AppKit
@testable import AlertPanel

/// The panel's colours and its glass guard (M7 plan, Stage 1). Nothing draws
/// with either yet, so what is held is the values: that the panel's copy and
/// the app's are the same, that words can be read on what they sit on, and
/// that the guard answers the same way twice.
@MainActor
final class PanelPaletteTests: XCTestCase {
    private let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // AlertPanelTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // package root

    override func setUp() {
        _ = NSApplication.shared
    }

    // MARK: - Two copies, one set of values

    private func source(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// Every place a pattern's two groups are found in a text, as name to value.
    private func pairs(_ pattern: String, in text: String) throws -> [String: String] {
        let expression = try NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
        var found: [String: String] = [:]
        for match in expression.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let name = Range(match.range(at: 1), in: text), let value = Range(match.range(at: 2), in: text) else {
                continue
            }
            found[String(text[name])] = String(text[value])
        }
        return found
    }

    /// What each name of a palette is set to, as the file writes it: a colour
    /// by its six hexadecimal digits, a tier's block by its tone, and a name
    /// that stands for another by that other's name.
    private func names(in path: String) throws -> [String: String] {
        let text = try source(path)
        let colours = try pairs(#"^\s*static let (\w+) = colour\((0x[0-9A-Fa-f]{6})\)$"#, in: text)
        let blocks = try pairs(#"^\s*case \.(\w+): return colour\((0x[0-9A-Fa-f]{6})\)$"#, in: text)
        let aliases = try pairs(#"^\s*static let (\w+) = ([a-z]\w*)$"#, in: text)
        var all = colours
        for (tone, value) in blocks { all["block." + tone] = value }
        for (name, other) in aliases { all[name] = "same as " + other }
        return all.mapValues { $0.uppercased() }
    }

    /// The app target has no tests, so its copy is read as text and held to the
    /// panel's name by name: a value moved to another name is caught, as a
    /// changed value is.
    func testThePanelsPaletteAndTheAppsGiveEachNameTheSameValue() throws {
        let panel = try names(in: "Sources/AlertPanel/PanelPalette.swift")
        let app = try names(in: "Sources/SignalLadder/NightWatchPalette.swift")
        XCTAssertEqual(panel, app, "the two palettes are copies, so what changes in one changes in the other")
        XCTAssertEqual(Set(panel.keys), ["ground", "raised", "words", "quietWords", "ink", "outline",
                                         "block.first", "block.second", "block.upper"])
        XCTAssertEqual(panel["ink"], "SAME AS GROUND")
        XCTAssertEqual(panel["outline"], "SAME AS WORDS")
    }

    /// What the file says is what the panel draws with: the text read above and
    /// the colours themselves agree, so the comparison with the app's copy is a
    /// comparison with real values.
    func testThePanelsSourceSaysWhatItsColoursAre() throws {
        let written = try names(in: "Sources/AlertPanel/PanelPalette.swift")
        XCTAssertEqual(written["ground"], "0X" + (try hex(PanelPalette.ground)))
        XCTAssertEqual(written["raised"], "0X" + (try hex(PanelPalette.raised)))
        XCTAssertEqual(written["words"], "0X" + (try hex(PanelPalette.words)))
        XCTAssertEqual(written["quietWords"], "0X" + (try hex(PanelPalette.quietWords)))
        XCTAssertEqual(written["block.first"], "0X" + (try hex(PanelPalette.block(.first))))
        XCTAssertEqual(written["block.second"], "0X" + (try hex(PanelPalette.block(.second))))
        XCTAssertEqual(written["block.upper"], "0X" + (try hex(PanelPalette.block(.upper))))
    }

    // MARK: - Two copies, one tier for each tone

    /// The lines that turn a tier into a tone, as a file writes them.
    private func toneLines(in path: String) throws -> [String] {
        try source(path).split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.contains(": self = .") }
    }

    /// The panel cannot name the core's `TierTone`, so it has the same three
    /// lines of its own, and they are held together here as text.
    func testThePanelAndTheCoreTurnATierIntoAToneByTheSameLines() throws {
        let panel = try toneLines(in: "Sources/AlertPanel/PanelPalette.swift")
        let core = try toneLines(in: "Sources/NotificationCore/TierTone.swift")
        XCTAssertEqual(panel, ["case ...1: self = .first", "case 2: self = .second", "default: self = .upper"])
        XCTAssertEqual(panel, core)
    }

    func testEachTierOfTheLadderHasItsTone() {
        XCTAssertEqual((1...4).map(PanelTone.init(tier:)), [.first, .second, .upper, .upper])
        XCTAssertEqual(PanelTone(tier: 0), .first)
        XCTAssertEqual(PanelTone(tier: 9), .upper)
    }

    // MARK: - The values

    private func components(_ colour: NSColor) throws -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        let srgb = try XCTUnwrap(colour.usingColorSpace(.sRGB))
        return (srgb.redComponent, srgb.greenComponent, srgb.blueComponent, srgb.alphaComponent)
    }

    private func hex(_ colour: NSColor) throws -> String {
        let parts = try components(colour)
        return String(format: "%02X%02X%02X", Int((parts.red * 255).rounded()), Int((parts.green * 255).rounded()),
                      Int((parts.blue * 255).rounded()))
    }

    func testEachColourIsTheDesignsValueAndOpaque() throws {
        XCTAssertEqual(try hex(PanelPalette.ground), "0C1224")
        XCTAssertEqual(try hex(PanelPalette.raised), "26335A")
        XCTAssertEqual(try hex(PanelPalette.words), "FFFFFF")
        XCTAssertEqual(try hex(PanelPalette.quietWords), "8C9CC4")
        XCTAssertEqual(try hex(PanelPalette.block(.first)), "FFC857")
        XCTAssertEqual(try hex(PanelPalette.block(.second)), "FF8A2B")
        XCTAssertEqual(try hex(PanelPalette.block(.upper)), "FF4D3D")
        let all = [PanelPalette.ground, PanelPalette.raised, PanelPalette.words, PanelPalette.quietWords,
                   PanelPalette.ink, PanelPalette.outline] + PanelTone.allCases.map(PanelPalette.block)
        for colour in all {
            XCTAssertEqual(try components(colour).alpha, 1)
        }
    }

    func testEachToneHasItsOwnColour() throws {
        let blocks = try PanelTone.allCases.map { try hex(PanelPalette.block($0)) }
        XCTAssertEqual(Set(blocks).count, PanelTone.allCases.count)
    }

    // MARK: - Words can be read

    /// WCAG 2's relative luminance.
    private func luminance(_ colour: NSColor) throws -> Double {
        let parts = try components(colour)
        func linear(_ channel: CGFloat) -> Double {
            let value = Double(channel)
            return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(parts.red) + 0.7152 * linear(parts.green) + 0.0722 * linear(parts.blue)
    }

    private func contrast(_ one: NSColor, _ other: NSColor) throws -> Double {
        let (first, second) = (try luminance(one), try luminance(other))
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    /// 4.5 to 1 is what WCAG asks of body text.
    func testWordsOnTheGroundAndInkOnEveryBlockReachFourAndAHalfToOne() throws {
        XCTAssertGreaterThanOrEqual(try contrast(PanelPalette.words, PanelPalette.ground), 4.5)
        XCTAssertGreaterThanOrEqual(try contrast(PanelPalette.quietWords, PanelPalette.ground), 4.5)
        for tone in PanelTone.allCases {
            XCTAssertGreaterThanOrEqual(try contrast(PanelPalette.ink, PanelPalette.block(tone)), 4.5, "\(tone)")
        }
    }

    /// Quiet words are for the ground. On a raised surface they reach the bar
    /// with almost nothing to spare (4.50 to 1), so `words` is the one to use
    /// there, and this holds both figures so a changed colour shows it.
    func testOnARaisedSurfaceWordsAreWellClearAndQuietWordsOnlyJust() throws {
        XCTAssertGreaterThanOrEqual(try contrast(PanelPalette.words, PanelPalette.raised), 7)
        let quiet = try contrast(PanelPalette.quietWords, PanelPalette.raised)
        XCTAssertGreaterThanOrEqual(quiet, 4.5)
        XCTAssertLessThan(quiet, 4.6)
    }

    /// The tiers must be told apart by more than hue: each block is darker
    /// than the tier below it.
    func testEachToneIsDarkerThanTheOneBefore() throws {
        let first = try luminance(PanelPalette.block(.first))
        let second = try luminance(PanelPalette.block(.second))
        let upper = try luminance(PanelPalette.block(.upper))
        XCTAssertGreaterThan(first, second)
        XCTAssertGreaterThan(second, upper)
    }

    // MARK: - Fixed-width figures

    func testTheMonoFontIsFixedWidthAtTheSizeAsked() {
        let font = PanelPalette.mono(size: 13, weight: .semibold)
        XCTAssertEqual(font.pointSize, 13)
        XCTAssertTrue(font.isFixedPitch)
    }

    // MARK: - Glass

    func testAGlassViewIsMadeExactlyWhereGlassIsAvailable() {
        XCTAssertEqual(PanelGround.makeGlass() != nil, PanelGround.glassIsAvailable)
    }

    /// A Mac older than macOS 26 has no glass. Where this runs with an older
    /// SDK, as on CI's macOS 15 job, it is the compile-time guard that answers,
    /// and on macOS 26 and later it asserts nothing: the case of a newer SDK
    /// on an older Mac is not one any test here can make.
    func testAMacOlderThanTwentySixHasNoGlass() {
        if ProcessInfo.processInfo.operatingSystemVersion.majorVersion < 26 {
            XCTAssertFalse(PanelGround.glassIsAvailable)
            XCTAssertNil(PanelGround.makeGlass())
        }
    }

    func testEachGlassViewIsANewOne() {
        if let one = PanelGround.makeGlass(), let other = PanelGround.makeGlass() {
            XCTAssertFalse(one === other)
        }
    }
}
