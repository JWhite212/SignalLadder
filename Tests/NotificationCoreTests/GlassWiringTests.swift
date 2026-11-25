import XCTest
@testable import NotificationCore

/// How the app decides a floating window's ground and hands it to the panel
/// and the popover (M7 plan, Stage 7). The app target has no tests, so this
/// reads its sources, as the other wiring tests do, and opens no window.
final class GlassWiringTests: XCTestCase {
    private func squeezed(_ text: String) -> String {
        text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    /// The choice is the core's, made from whether this Mac has glass and the
    /// display settings as they are, in one place.
    func testTheGroundIsTheCoresChoiceMadeInOnePlace() throws {
        let reader = try code("DisplaySettingsReader.swift")
        XCTAssertEqual(squeezed(try body(of: "static func ground(_ workspace: NSWorkspace = .shared) -> GroundMaterial {", in: reader)),
                       "GroundMaterial.choose(glassAvailable: PanelGround.glassIsAvailable, settings: current(workspace))")
        var choices = 0
        var asksForGlass = 0
        for file in try AppSources.fileNames() {
            let source = try code(file)
            choices += count("GroundMaterial.choose(", in: source)
            asksForGlass += count("glassIsAvailable", in: source)
            XCTAssertEqual(count("accessibilityDisplayShouldReduceTransparency", in: source),
                           file == "DisplaySettingsReader.swift" ? 1 : 0, file)
        }
        XCTAssertEqual(choices, 1)
        XCTAssertEqual(asksForGlass, 1)
    }

    /// The panel asks each time it lays rows out, so it is given a closure and
    /// not a value read once at launch.
    func testThePanelIsGivenTheGroundAsAQuestion() throws {
        let app = try code("AppDelegate.swift")
        XCTAssertEqual(count("ground: { PanelGround.Material(DisplaySettingsReader.ground()) })", in: app), 1)
        XCTAssertLessThan(try position(of: "private lazy var panel = AlertPanelController(", in: app),
                          try position(of: "ground: { PanelGround.Material(DisplaySettingsReader.ground()) })", in: app))
        XCTAssertLessThan(try position(of: "ground: { PanelGround.Material(DisplaySettingsReader.ground()) })", in: app),
                          try position(of: "private lazy var hotKey", in: app))
    }

    /// The popover is built again each time it opens, and is told the ground as
    /// it opens.
    func testThePopoverIsToldTheGroundAsItOpens() throws {
        let app = try code("AppDelegate.swift")
        let show = try body(of: "private func showPopover() {", in: app)
        XCTAssertEqual(count("ground: PanelGround.Material(DisplaySettingsReader.ground()),", in: show), 1)
        XCTAssertEqual(count("DisplaySettingsReader.ground()", in: app), 2, "the panel and the popover")
    }

    /// The popover's window has the panel's ground, and its view is told what
    /// that ground came to be, which is solid where glass could not be made.
    func testThePopoversWindowHasThePanelsGroundAndTellsItsView() throws {
        let controller = try code("StatusPopoverController.swift")
        let made = try position(of: "let ground = PanelGroundView(cornerRadius: StatusPopoverView.corner)", in: controller)
        let used = try position(of: "ground.use(wanted)", in: controller)
        let told = try position(of: "ground: GroundMaterial(ground.material), perform: chosen))", in: controller)
        let held = try position(of: "ground.holder.addSubview(host)", in: controller)
        let content = try position(of: "panel.contentView = ground", in: controller)
        XCTAssertLessThan(made, used)
        XCTAssertLessThan(used, told)
        XCTAssertLessThan(told, held)
        XCTAssertLessThan(held, content)
        XCTAssertEqual(count("panel.contentView =", in: controller), 1)
        XCTAssertEqual(count("ground wanted: PanelGround.Material = .solid,", in: controller), 1)
    }

    /// On glass the view draws no ground of its own, and it is navy unless told.
    func testThePopoversViewDrawsNoGroundOnGlass() throws {
        let view = try code("StatusPopoverView.swift")
        XCTAssertEqual(count("var ground: GroundMaterial = .solid", in: view), 1)
        XCTAssertEqual(count(".background(ground == .glass ? Color.clear : NightWatchPalette.ground)", in: view), 1)
        XCTAssertEqual(count(".background(NightWatchPalette.ground)", in: view), 0)
        XCTAssertEqual(count("ground ==", in: view), 1, "nothing else in it changes with the ground")
    }

    /// The two targets cannot name each other's type, so the app copies one
    /// into the other, case for case, both ways.
    func testTheGroundIsCopiedCaseForCase() throws {
        let reader = try code("DisplaySettingsReader.swift")
        XCTAssertEqual(squeezed(try body(of: "init(_ chosen: GroundMaterial) {", in: reader)),
                       "switch chosen {\ncase .solid: self = .solid\ncase .glass: self = .glass\n}")
        XCTAssertEqual(squeezed(try body(of: "init(_ drawn: PanelGround.Material) {", in: reader)),
                       "switch drawn {\ncase .solid: self = .solid\ncase .glass: self = .glass\n}")
    }

    /// No source of the app names a material of the system's: the ground is
    /// the panel target's to draw.
    func testNoSourceOfTheAppNamesASystemMaterial() throws {
        for file in try AppSources.fileNames() {
            let source = try code(file)
            XCTAssertEqual(count("NSGlassEffect", in: source), 0, file)
            XCTAssertEqual(count("NSVisualEffectView", in: source), 0, file)
            XCTAssertEqual(count(".glassEffect(", in: source), 0, file)
        }
    }
}
