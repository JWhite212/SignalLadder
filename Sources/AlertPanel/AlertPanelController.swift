// Sources/AlertPanel/AlertPanelController.swift
import AppKit

/// The escalation panel: one borderless window that stays over every app and
/// every Space until each escalation on it is acknowledged (§5.17, M4 plan
/// Task 4).
///
/// Its own target, on `AlertAudio`'s precedent (ruling 18), so the window it
/// builds is tested; the app target has no tests. It depends on nothing: its
/// rows are `PanelRow`s, an identifier, a tier's number and words already
/// written by `EscalationPanelText`, so it cannot name a notification or a
/// summary, and cannot show what arrived even by mistake (ruling 17).
///
/// Since 1.2 it is drawn in the Night watch design (M7 plan, Stage 3): a navy
/// ground whatever the system's appearance, and one block per escalation in
/// its tier's colour with the tier's number large beside the words. A row
/// whose alert did not reach the user has a line round it and no colour.
///
/// The panel never takes focus, so its buttons cannot be reached by Tab or
/// Full Keyboard Access. The keyboard's ways to acknowledge are the menu item
/// and the hotkey (ruling 16).
///
/// Laying rows out (`setRows`) is kept apart from putting the window on screen
/// (`present`). Tests lay rows out with no screen, which a test runner may not
/// have, and check showing and hiding on a panel that records being ordered
/// in and out instead of doing it.
@MainActor
public final class AlertPanelController: NSObject {
    public let panel: NSPanel
    private let content = NSStackView()
    private let heading: NSTextField
    /// Counts the rows left off when there are more than `maxRows`.
    private let overflow = NSTextField(wrappingLabelWithString: "")
    private let acknowledgeTitle: String
    private let overflowLine: (Int) -> String
    /// How wide the line round a fault is. The app reads it from the display
    /// settings each time rows are laid out; this target cannot ask the core.
    private let outlineWidth: @MainActor () -> CGFloat
    /// What the ground is drawn with: the navy, or the system's glass. The app
    /// decides it from the display settings each time rows are laid out, as it
    /// does the outline's width, since either setting can change while the
    /// panel is up.
    private let groundMaterial: @MainActor () -> PanelGround.Material
    private let ground = PanelGroundView(cornerRadius: AlertPanelController.cornerRadius)
    private var onAcknowledge: ((UUID) -> Void)?
    /// Each row's views, kept while its escalation stays listed, so an update
    /// changes a row's words in place rather than building it again: every
    /// tier-3 repeat updates the panel, and a button rebuilt under a press
    /// loses the click.
    private var rowViews: [UUID: Row] = [:]

    /// The screens there are, and where the pointer is. The real ones in the app;
    /// tests give their own, so placement is decided with no screen.
    private let screens: @MainActor () -> [ScreenArea]
    private let pointer: @MainActor () -> NSPoint

    /// A screen's whole frame, and its visible frame: the frame less the menu bar
    /// and the Dock, which is where the panel goes.
    struct ScreenArea: Equatable {
        let frame: NSRect
        let visible: NSRect
    }

    static func liveScreens() -> [ScreenArea] {
        NSScreen.screens.map { ScreenArea(frame: $0.frame, visible: $0.visibleFrame) }
    }

    /// The rows now laid out, in order, top first.
    public private(set) var rows: [PanelRow] = []
    /// How many rows are left off, and counted on the overflow line instead.
    public private(set) var hiddenCount = 0

    static let width: CGFloat = 420
    static let margin: CGFloat = 20
    static let insets = NSEdgeInsets(top: 14, left: 12, bottom: 12, right: 12)
    /// The panel's corners, and a block's, which is the panel's less the inset
    /// so that the two curves run together.
    static let cornerRadius: CGFloat = 26
    static let blockRadius: CGFloat = cornerRadius - insets.left
    /// The line round a fault where the app says nothing else.
    public static let defaultOutlineWidth: CGFloat = 1.5
    /// How much heavier than that the line round a fault's block is.
    static let faultBlockExtra: CGFloat = 1
    /// Rows beyond this are counted, not shown. The panel is pinned from the
    /// top, so without a limit the oldest rows and their buttons would sit
    /// below the screen's edge, unseen. Six blocks of one-line words and the
    /// heading are about 500 points, and six of the tallest, a two-line name
    /// over a three-line fault, about 690 (`AlertPanelControllerTests`). That
    /// is more than a small or scaled display has, so `setRows` also shows
    /// fewer when six do not fit the screen the panel is on.
    public static let maxRows = 6

    /// - Parameters:
    ///   - title: heads the panel; `EscalationPanelText.title` in the app.
    ///   - acknowledgeTitle: each row's button; `EscalationPanelText.acknowledge`.
    ///   - overflowLine: the line counting rows left off, given how many;
    ///     `EscalationPanelText.overflow` in the app.
    ///   - outlineWidth: how wide the line round a fault is now, in points.
    ///   - ground: what the ground is drawn with now. Glass is drawn only where
    ///     `PanelGround.glassIsAvailable`; asked for elsewhere, the ground is solid.
    public convenience init(title: String, acknowledgeTitle: String, overflowLine: @escaping (Int) -> String,
                            outlineWidth: @escaping @MainActor () -> CGFloat = { AlertPanelController.defaultOutlineWidth },
                            ground: @escaping @MainActor () -> PanelGround.Material = { .solid }) {
        self.init(title: title, acknowledgeTitle: acknowledgeTitle, overflowLine: overflowLine,
                  outlineWidth: outlineWidth, ground: ground) {
            NSPanel(contentRect: $0, styleMask: $1, backing: .buffered, defer: true)
        }
    }

    /// `makePanel` lets tests substitute a panel that records being ordered
    /// in and out, so showing and hiding are tested with no window on screen.
    /// The style is still this controller's. `screens` and `pointer` let them
    /// say which screens there are and where the pointer is.
    init(title: String, acknowledgeTitle: String, overflowLine: @escaping (Int) -> String,
         outlineWidth: @escaping @MainActor () -> CGFloat = { AlertPanelController.defaultOutlineWidth },
         ground: @escaping @MainActor () -> PanelGround.Material = { .solid },
         screens: @escaping @MainActor () -> [ScreenArea] = AlertPanelController.liveScreens,
         pointer: @escaping @MainActor () -> NSPoint = { NSEvent.mouseLocation },
         makePanel: (NSRect, NSWindow.StyleMask) -> NSPanel) {
        self.acknowledgeTitle = acknowledgeTitle
        self.overflowLine = overflowLine
        self.outlineWidth = outlineWidth
        groundMaterial = ground
        self.screens = screens
        self.pointer = pointer
        heading = NSTextField(labelWithString: title)
        panel = makePanel(NSRect(x: 0, y: 0, width: Self.width, height: 80), [.borderless, .nonactivatingPanel])
        super.init()

        // A display unplugged while the panel shows takes the panel's place with
        // it, and macOS does not move a borderless window at this level by itself
        // (measured on macOS 27.2, 2026-10-18, #104): the panel stayed on the
        // display that had gone for as long as it was watched. So it is placed
        // again whenever the screens change. Removed when the controller goes.
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged(_:)),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)

        // Order matters: setting `isFloatingPanel` resets the level to
        // `.floating`, silently undoing a `.statusBar` set before it (measured,
        // findings 2026-09-25). Read back by the tests, so a reordering fails.
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // An NSPanel hides whenever its app is not active, by default, and
        // this app is almost never the active one. One built non-activating,
        // as this is, already does not (measured on macOS 26.7.1,
        // 2026-09-30, findings); it is set anyway, so a later change of style
        // cannot quietly bring the hiding back.
        panel.hidesOnDeactivate = false
        // Otherwise the buttons stop answering while any of the app's own
        // modal alerts is up, such as the one that reports a failed save.
        panel.worksWhenModal = true
        panel.isReleasedWhenClosed = false
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // Never drawn, as the panel has no title bar; what VoiceOver names it.
        panel.title = title

        // The ground is navy whatever the system's appearance, so the panel's
        // controls are drawn for a dark ground, and its words are set to the
        // palette's and not to the system's label colours.
        panel.appearance = NSAppearance(named: .darkAqua)
        // It starts solid, and is glass from the first rows on where the app
        // asks for it and the system has it.
        panel.contentView = self.ground
        let background = self.ground.holder

        heading.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        heading.textColor = PanelPalette.words
        overflow.textColor = PanelPalette.quietWords
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 8
        content.edgeInsets = Self.insets
        content.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: background.topAnchor),
            content.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            content.widthAnchor.constraint(equalToConstant: Self.width),
        ])
        content.addArrangedSubview(heading)
    }

    /// Lays out one row per escalation, in the order given, newest first as
    /// the coordinator lists them, each with its own Acknowledge button, up to
    /// `maxRows`; any more are counted on a last line. Replaces whatever was
    /// there, reusing the views of rows that stay. Needs no screen.
    func setRows(_ rows: [PanelRow], onAcknowledge: @escaping (UUID) -> Void) {
        self.onAcknowledge = onAcknowledge
        // A block's height depends on its words: a long name takes two lines and
        // a fault's line can take three. So the rows shown are as many as fit the
        // screen, up to `maxRows`, and never fewer than one: the panel is pinned
        // from the top, and a button below the screen's edge cannot be pressed.
        var limit = min(rows.count, Self.maxRows)
        arrange(rows, showing: limit)
        if let room = roomForRows() {
            while limit > 1, panel.frame.height > room {
                limit -= 1
                arrange(rows, showing: limit)
            }
        }
    }

    /// How tall the panel may be on the screen it is on, or is about to be put
    /// on: that screen's visible height less the margin above and below. Nil
    /// with no screen, where nothing can be measured against.
    private func roomForRows() -> CGFloat? {
        let areas = screens()
        let holding = panel.isVisible ? areas.first { $0.frame.intersects(panel.frame) } : nil
        let at = pointer()
        guard let area = holding ?? areas.first(where: { NSMouseInRect(at, $0.frame, false) }) ?? areas.first else {
            return nil
        }
        return area.visible.height - 2 * Self.margin
    }

    private func arrange(_ rows: [PanelRow], showing limit: Int) {
        let shown = rows.prefix(limit)
        hiddenCount = rows.count - shown.count
        self.rows = Array(shown)

        let line = outlineWidth()
        let drawnWith = ground.material
        ground.use(groundMaterial())
        // The window's shadow follows what is opaque in it, which has changed.
        if ground.material != drawnWith { panel.invalidateShadow() }
        var kept: [UUID: Row] = [:]
        var views: [NSView] = [heading]
        for said in shown {
            let row = rowViews[said.id] ?? Row(id: said.id, title: acknowledgeTitle, target: self,
                                               action: #selector(acknowledged(_:)))
            row.show(said, acknowledgeTitle: acknowledgeTitle, outlineWidth: line)
            kept[said.id] = row
            views.append(row.block)
        }
        if hiddenCount > 0 {
            overflow.stringValue = overflowLine(hiddenCount)
            views.append(overflow)
        }
        for (id, row) in rowViews where kept[id] == nil {
            content.removeArrangedSubview(row.block)
            row.block.removeFromSuperview()
        }
        rowViews = kept

        // Rearranged only when the order changed, so a row whose words alone
        // changed is never taken out from under a press.
        if content.arrangedSubviews != views {
            for view in content.arrangedSubviews { content.removeArrangedSubview(view) }
            if hiddenCount == 0 { overflow.removeFromSuperview() }
            for view in views { content.addArrangedSubview(view) }
        }
        for row in kept.values where !row.pinned {
            // Each block the full width inside the insets, so its words take
            // the slack and the buttons line up at the right.
            row.block.widthAnchor.constraint(equalTo: content.widthAnchor,
                                             constant: -(Self.insets.left + Self.insets.right)).isActive = true
            row.pinned = true
        }
        content.layoutSubtreeIfNeeded()
        panel.setContentSize(NSSize(width: Self.width, height: content.fittingSize.height))
    }

    /// Puts the panel on screen, top right of the screen the pointer is on,
    /// without taking focus from the app in front.
    public func present() {
        placeOnThePointersScreen()
        panel.orderFrontRegardless()
    }

    /// Top right of the screen the pointer is on, or of the first screen when it
    /// is on none. With no screen at all the panel is left where it is: the
    /// spike's `NSScreen.main!` would have crashed there.
    private func placeOnThePointersScreen() {
        let areas = screens()
        let at = pointer()
        guard let area = areas.first(where: { NSMouseInRect(at, $0.frame, false) }) ?? areas.first else { return }
        panel.setFrameOrigin(Self.origin(for: panel.frame.size, in: area.visible))
    }

    @objc private func screensChanged(_ notification: Notification) {
        placeAgainIfOffScreen()
    }

    /// While the panel shows, puts it back on a screen if no screen there is now
    /// holds it whole, as after its display was unplugged. A panel still on a
    /// screen stays where it is, so a display added or rearranged elsewhere
    /// never moves it.
    func placeAgainIfOffScreen() {
        guard panel.isVisible, !Self.isOnAScreen(panel.frame, among: screens()) else { return }
        placeOnThePointersScreen()
    }

    /// Whether some screen holds `frame` whole.
    static func isOnAScreen(_ frame: NSRect, among areas: [ScreenArea]) -> Bool {
        areas.contains { $0.frame.contains(frame) }
    }

    /// Where the panel's origin goes to sit top right of `visible`, a
    /// screen's frame less the menu bar and Dock.
    static func origin(for size: NSSize, in visible: NSRect) -> NSPoint {
        NSPoint(x: visible.maxX - size.width - margin, y: visible.maxY - size.height - margin)
    }

    /// Lays the rows out and shows them; with none, hides the panel. What the
    /// app's `updatePanel` calls, on every change to any escalation. Put on
    /// screen only when it is not already there; while it is, its top edge
    /// stays put as rows come and go, rather than following the pointer to
    /// another screen at every repeat.
    public func show(rows: [PanelRow], onAcknowledge: @escaping (UUID) -> Void) {
        guard !rows.isEmpty else { return hide() }
        let top = panel.isVisible ? panel.frame.maxY : nil
        setRows(rows, onAcknowledge: onAcknowledge)
        if let top {
            panel.setFrameOrigin(NSPoint(x: panel.frame.minX, y: top - panel.frame.height))
        } else {
            present()
        }
    }

    public func hide() {
        panel.orderOut(nil)
    }

    // MARK: - Rows

    /// The buttons now laid out, top first. For tests, which press them.
    var buttons: [RowButton] {
        rows.compactMap { rowViews[$0.id]?.button }
    }

    /// The names now drawn, top first, read from the labels themselves. For
    /// tests.
    var drawnNames: [String] {
        rows.compactMap { rowViews[$0.id]?.name.stringValue }
    }

    /// The line under each name as drawn, top first. For tests.
    var drawnDetails: [NSAttributedString] {
        rows.compactMap { rowViews[$0.id]?.detail.attributedStringValue }
    }

    /// What stands at each row's leading edge as drawn: the tier's number, or
    /// nil where the fault's symbol is shown in its place. For tests.
    var drawnNumerals: [String?] {
        rows.compactMap { rowViews[$0.id] }.map { $0.numeral.isHidden ? nil : $0.numeral.stringValue }
    }

    /// Each row's block, top first. For tests, which read its colour and line.
    var blocks: [NSView] {
        rows.compactMap { rowViews[$0.id]?.block }
    }

    /// The overflow line as drawn, or nil when every row is shown. For tests.
    var drawnOverflow: String? {
        content.arrangedSubviews.contains(overflow) ? overflow.stringValue : nil
    }

    @objc private func acknowledged(_ sender: RowButton) {
        guard let id = sender.escalationID else { return }
        onAcknowledge?(id)
    }

    /// One row: a block holding its mark, its words, then its button.
    @MainActor
    private final class Row {
        let block = NSView()
        /// The tier's number, or hidden where `symbol` stands in its place.
        let numeral = NSTextField(labelWithString: "")
        /// The slashed bell of a fault.
        let symbol = NSImageView()
        let name = NSTextField(wrappingLabelWithString: "")
        let detail = NSTextField(wrappingLabelWithString: "")
        let button: RowButton
        var pinned = false
        private var shown: PanelRow?
        private var shownOutline: CGFloat = 0

        private static let markWidth: CGFloat = 26
        private static let padding = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)

        init(id: UUID, title: String, target: AnyObject, action: Selector) {
            button = RowButton(title: title, target: target, action: action)
            button.escalationID = id
            button.setContentHuggingPriority(.required, for: .horizontal)
            button.setContentCompressionResistancePriority(.required, for: .horizontal)

            numeral.font = PanelPalette.mono(size: 28, weight: .bold)
            numeral.alignment = .center
            // Read out with the button's label, which says the tier in words.
            numeral.setAccessibilityElement(false)
            symbol.image = NSImage(systemSymbolName: "bell.slash.fill", accessibilityDescription: nil)
            symbol.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 22, weight: .bold)
            symbol.setAccessibilityElement(false)
            let mark = NSStackView(views: [numeral, symbol])
            mark.orientation = .horizontal
            mark.alignment = .centerY
            mark.widthAnchor.constraint(equalToConstant: Self.markWidth).isActive = true

            name.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
            // A long name takes a second line before it is cut short: the name
            // is how one row is told from another.
            name.maximumNumberOfLines = 2
            name.cell?.truncatesLastVisibleLine = true
            name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            detail.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            let words = NSStackView(views: [name, detail])
            words.orientation = .vertical
            words.alignment = .leading
            words.spacing = 2
            words.setHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)

            let stack = NSStackView(views: [mark, words, button])
            stack.orientation = .horizontal
            stack.alignment = .centerY
            stack.spacing = 12
            stack.translatesAutoresizingMaskIntoConstraints = false

            block.wantsLayer = true
            block.layer?.cornerRadius = AlertPanelController.blockRadius
            block.translatesAutoresizingMaskIntoConstraints = false
            block.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.topAnchor.constraint(equalTo: block.topAnchor, constant: Self.padding.top),
                stack.bottomAnchor.constraint(equalTo: block.bottomAnchor, constant: -Self.padding.bottom),
                stack.leadingAnchor.constraint(equalTo: block.leadingAnchor, constant: Self.padding.left),
                stack.trailingAnchor.constraint(equalTo: block.trailingAnchor, constant: -Self.padding.right),
            ])
        }

        /// Draws the row as given. A row that stays is restyled in place, so a
        /// tier that rises changes the block's colour and never its views.
        func show(_ row: PanelRow, acknowledgeTitle: String, outlineWidth: CGFloat) {
            guard shown != row || shownOutline != outlineWidth else { return }
            shown = row
            shownOutline = outlineWidth

            let ink: NSColor
            switch row.mark {
            case .tier(let tier):
                ink = PanelPalette.ink
                block.layer?.backgroundColor = PanelPalette.block(PanelTone(tier: tier)).cgColor
                block.layer?.borderWidth = 0
                numeral.stringValue = String(tier)
                numeral.isHidden = false
                symbol.isHidden = true
                button.look(.filled, outlineWidth: outlineWidth)
            case .fault:
                ink = PanelPalette.words
                block.layer?.backgroundColor = PanelPalette.ground.cgColor
                block.layer?.borderColor = PanelPalette.outline.cgColor
                // A point heavier than the line round a fault elsewhere: beside a
                // filled red block a thin line recedes, and this is the row that
                // says a page did not go.
                block.layer?.borderWidth = outlineWidth + AlertPanelController.faultBlockExtra
                numeral.stringValue = ""
                numeral.isHidden = true
                symbol.isHidden = false
                symbol.contentTintColor = ink
                button.look(.outlined, outlineWidth: outlineWidth)
            }
            numeral.textColor = ink
            name.textColor = ink
            name.stringValue = row.name

            let size = NSFont.smallSystemFontSize + 1
            let text = NSMutableAttributedString()
            for part in row.detail {
                switch part {
                case .words(let said):
                    text.append(NSAttributedString(string: said, attributes: [
                        .font: NSFont.systemFont(ofSize: size, weight: .semibold), .foregroundColor: ink,
                    ]))
                case .figure(let said):
                    text.append(NSAttributedString(string: said, attributes: [
                        .font: PanelPalette.mono(size: size, weight: .semibold), .foregroundColor: ink,
                    ]))
                }
            }
            detail.attributedStringValue = text
            detail.isHidden = row.detail.isEmpty

            // Every button reads the same; VoiceOver is told which row each
            // acknowledges, in the row's whole line, which says the tier in
            // words. The line holds nothing that arrived (ruling 17).
            button.setAccessibilityLabel("\(acknowledgeTitle): \(row.spoken)")
        }
    }
}

/// A row's Acknowledge button, carrying the escalation it acknowledges.
///
/// Drawn as a capsule: navy on a tier's block, and a line with no fill on a
/// fault, where a navy capsule would not be seen against the navy ground.
final class RowButton: NSButton {
    var escalationID: UUID?

    enum Look: Equatable {
        case filled
        case outlined
    }

    private(set) var look: Look?

    func look(_ look: Look, outlineWidth: CGFloat) {
        self.look = look
        isBordered = false
        wantsLayer = true
        attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize + 1),
            .foregroundColor: PanelPalette.words,
        ])
        switch look {
        case .filled:
            layer?.backgroundColor = PanelPalette.ground.cgColor
            layer?.borderWidth = 0
        case .outlined:
            layer?.backgroundColor = NSColor.clear.cgColor
            layer?.borderColor = PanelPalette.outline.cgColor
            layer?.borderWidth = outlineWidth
        }
        invalidateIntrinsicContentSize()
    }

    /// A button with no bezel shows nothing when pressed, so it dims while the
    /// pointer is down on it.
    override var isHighlighted: Bool {
        didSet { layer?.opacity = isHighlighted ? 0.6 : 1 }
    }

    /// Room round the title, which a button with no bezel does not leave.
    override var intrinsicContentSize: NSSize {
        let title = super.intrinsicContentSize
        return NSSize(width: title.width + 24, height: max(title.height + 8, 26))
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
    }
}
