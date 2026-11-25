import XCTest
import AppKit
@testable import AlertPanel

/// The ground of the panel and the popover (M7 plan, Stage 7): navy, or the
/// system's glass under a wash of navy where the Mac has glass. No window is
/// put on screen; the views are built and read back. Where these run on a Mac
/// or with an SDK that has no glass, as on CI's macOS 15 job, the glass half
/// of each test asserts that the ground stayed solid.
@MainActor
final class PanelGroundTests: XCTestCase {
    override func setUp() {
        _ = NSApplication.shared
    }

    private func hex(_ colour: CGColor?) throws -> String {
        let srgb = try XCTUnwrap(NSColor(cgColor: try XCTUnwrap(colour))?.usingColorSpace(.sRGB))
        return String(format: "%02X%02X%02X", Int((srgb.redComponent * 255).rounded()),
                      Int((srgb.greenComponent * 255).rounded()), Int((srgb.blueComponent * 255).rounded()))
    }

    private func ground() -> PanelGroundView {
        let view = PanelGroundView(cornerRadius: 26)
        view.frame = NSRect(x: 0, y: 0, width: 340, height: 300)
        view.layoutSubtreeIfNeeded()
        return view
    }

    // MARK: - The glass itself

    func testAGlassViewIsMadeExactlyWhereGlassIsAvailable() {
        XCTAssertEqual(PanelGround.makeGlass(cornerRadius: 26) != nil, PanelGround.glassIsAvailable)
    }

    /// A Mac older than macOS 26 has no glass. Where this runs with an older
    /// SDK, as on CI's macOS 15 job, it is the compile-time guard that answers,
    /// and on macOS 26 and later it asserts nothing: the case of a newer SDK
    /// on an older Mac is not one any test here can make.
    func testAMacOlderThanTwentySixHasNoGlass() {
        if ProcessInfo.processInfo.operatingSystemVersion.majorVersion < 26 {
            XCTAssertFalse(PanelGround.glassIsAvailable)
            XCTAssertNil(PanelGround.makeGlass(cornerRadius: 26))
        }
    }

    func testEachGlassViewIsANewOneWithTheCornersAsked() {
        if let one = PanelGround.makeGlass(cornerRadius: 26), let other = PanelGround.makeGlass(cornerRadius: 12) {
            XCTAssertFalse(one === other)
            XCTAssertEqual(PanelGround.cornerRadius(of: one), 26)
            XCTAssertEqual(PanelGround.cornerRadius(of: other), 12)
        }
        XCTAssertNil(PanelGround.cornerRadius(of: NSView()), "a view that is not glass has none to give")
    }

    /// The wash is thin enough that the glass shows and thick enough that the
    /// quiet words are read over a white window, where they measured about
    /// 4.5 to 1 at 0.6 and 4.9 to 1 at 0.8.
    func testTheWashIsBetweenWhatWasMeasured() {
        XCTAssertEqual(PanelGround.washAlpha, 0.75)
        XCTAssertGreaterThan(PanelGround.washAlpha, 0.6)
        XCTAssertLessThan(PanelGround.washAlpha, 1)
    }

    // MARK: - The ground

    func testAGroundStartsSolidNavyWithItsCornersAndNothingButTheHolder() throws {
        let view = ground()
        XCTAssertEqual(view.material, .solid)
        XCTAssertEqual(try hex(view.layer?.backgroundColor), "0C1224")
        XCTAssertEqual(view.layer?.backgroundColor?.alpha, 1)
        XCTAssertEqual(view.layer?.cornerRadius, 26)
        XCTAssertEqual(view.layer?.masksToBounds, true)
        XCTAssertEqual(view.subviews, [view.holder])
        XCTAssertNil(view.glassView)
        XCTAssertEqual(view.holder.frame, view.bounds)
    }

    func testAskedForGlassItIsGlassUnderAWashOfNavyWhereThereIsGlass() throws {
        let view = ground()
        view.use(.glass)
        view.layoutSubtreeIfNeeded()
        guard PanelGround.glassIsAvailable else {
            XCTAssertEqual(view.material, .solid)
            XCTAssertEqual(view.layer?.backgroundColor?.alpha, 1)
            XCTAssertEqual(view.subviews, [view.holder])
            XCTAssertNil(view.glassView)
            return
        }
        XCTAssertEqual(view.material, .glass)
        let glass = try XCTUnwrap(view.glassView)
        XCTAssertEqual(view.subviews, [glass, view.holder], "the glass is behind what the window shows")
        XCTAssertEqual(glass.frame, view.bounds)
        XCTAssertEqual(PanelGround.cornerRadius(of: glass), 26)
        XCTAssertEqual(try hex(view.layer?.backgroundColor), "0C1224", "still navy")
        XCTAssertEqual(try XCTUnwrap(view.layer?.backgroundColor?.alpha), PanelGround.washAlpha, accuracy: 0.001)
        XCTAssertEqual(view.layer?.cornerRadius, 26)
        XCTAssertEqual(view.layer?.masksToBounds, true)
    }

    /// Glass changes the colours of what is put in it, and a tier's colour is
    /// what says which tier it is, so the holder lies over the glass and is
    /// never inside it.
    func testWhatTheWindowShowsIsNeverInsideTheGlass() {
        let view = ground()
        let shown = NSView()
        view.holder.addSubview(shown)
        for material in [PanelGround.Material.glass, .solid, .glass] {
            view.use(material)
            XCTAssertTrue(view.holder.superview === view, "\(material)")
            XCTAssertTrue(shown.superview === view.holder, "\(material)")
            XCTAssertTrue(view.subviews.last === view.holder, "\(material): the holder is on top")
        }
    }

    func testBackToSolidTheGlassIsGoneAndTheNavyIsOpaque() throws {
        let view = ground()
        view.use(.glass)
        view.use(.solid)
        XCTAssertEqual(view.material, .solid)
        XCTAssertNil(view.glassView)
        XCTAssertEqual(view.subviews, [view.holder])
        XCTAssertEqual(try hex(view.layer?.backgroundColor), "0C1224")
        XCTAssertEqual(view.layer?.backgroundColor?.alpha, 1)
    }

    func testAskingForWhatItIsMakesNoSecondGlass() {
        let view = ground()
        view.use(.glass)
        let first = view.glassView
        view.use(.glass)
        XCTAssertTrue(view.glassView === first)
        XCTAssertEqual(view.subviews.count, PanelGround.glassIsAvailable ? 2 : 1)
        view.use(.solid)
        view.use(.solid)
        XCTAssertEqual(view.subviews, [view.holder])
    }

    func testTheHolderAndTheGlassFollowTheGroundsSize() {
        let view = ground()
        view.use(.glass)
        view.setFrameSize(NSSize(width: 340, height: 520))
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(view.holder.frame, view.bounds)
        if let glass = view.glassView { XCTAssertEqual(glass.frame, view.bounds) }
        view.use(.solid)
        view.setFrameSize(NSSize(width: 340, height: 200))
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(view.holder.frame, view.bounds)
    }

    /// Glass is named in one file, behind both guards, so every other file
    /// compiles the same with an SDK that has no such class.
    func testGlassIsNamedOnlyBehindBothGuards() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources")
        var naming: [String] = []
        let files = try XCTUnwrap(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        for case let file as URL in files where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            let code = text.components(separatedBy: "\n")
                .map { line in line.range(of: "//").map { String(line[..<$0.lowerBound]) } ?? line }
            if code.contains(where: { $0.contains("NSGlassEffect") }) { naming.append(file.lastPathComponent) }
        }
        XCTAssertEqual(naming, ["PanelGround.swift"])

        let ground = try String(contentsOf: sources.appendingPathComponent("AlertPanel/PanelGround.swift"), encoding: .utf8)
        var guarded = false
        var available = false
        var named = 0
        for line in ground.components(separatedBy: "\n") {
            let code = (line.range(of: "//").map { String(line[..<$0.lowerBound]) } ?? line)
                .trimmingCharacters(in: .whitespaces)
            if code == "#if compiler(>=6.2)" { guarded = true }
            if code.hasPrefix("if #available(macOS 26.0, *)") { available = true }
            if code.contains("NSGlassEffect") {
                named += 1
                XCTAssertTrue(guarded && available, "named outside the guards: \(code)")
            }
            if code == "#endif" { guarded = false; available = false }
        }
        XCTAssertEqual(named, 2, "where one is made, and where a test reads its corners")
    }
}
