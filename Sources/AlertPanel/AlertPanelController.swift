// Sources/AlertPanel/AlertPanelController.swift
import AppKit

/// The escalation panel: one borderless window that stays over every app and
/// every Space until each escalation on it is acknowledged (§5.17, M4 plan
/// Task 4).
///
/// Its own target, on `AlertAudio`'s precedent (ruling 18), so the window it
/// builds is tested; the app target has no tests. It depends on nothing: its
/// rows are an identifier and a line already written by
/// `EscalationPanelText`, so it cannot name a notification or a summary, and
/// cannot show what arrived even by mistake (ruling 17).
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
    private var onAcknowledge: ((UUID) -> Void)?
    /// Each row's views, kept while its escalation stays listed, so an update
    /// changes a row's words in place rather than building it again: every
    /// tier-3 repeat updates the panel, and a button rebuilt under a press
    /// loses the click.
    private var rowViews: [UUID: Row] = [:]

    /// The rows now laid out, in order, top first.
    public private(set) var rows: [(id: UUID, line: String)] = []
    /// How many rows are left off, and counted on the overflow line instead.
    public private(set) var hiddenCount = 0

    static let width: CGFloat = 420
    static let margin: CGFloat = 20
    static let insets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
    /// Rows beyond this are counted, not shown. About 22 typical rows are
    /// taller than a 1080p screen (measured offscreen, 2026-09-30), and the
    /// panel is pinned from the top, so without a limit the oldest rows and
    /// their buttons would sit below the screen's edge, unseen.
    public static let maxRows = 6

    /// - Parameters:
    ///   - title: heads the panel; `EscalationPanelText.title` in the app.
    ///   - acknowledgeTitle: each row's button; `EscalationPanelText.acknowledge`.
    ///   - overflowLine: the line counting rows left off, given how many;
    ///     `EscalationPanelText.overflow` in the app.
    public convenience init(title: String, acknowledgeTitle: String, overflowLine: @escaping (Int) -> String) {
        self.init(title: title, acknowledgeTitle: acknowledgeTitle, overflowLine: overflowLine) {
            NSPanel(contentRect: $0, styleMask: $1, backing: .buffered, defer: true)
        }
    }

    /// `makePanel` lets tests substitute a panel that records being ordered
    /// in and out, so showing and hiding are tested with no window on screen.
    /// The style is still this controller's.
    init(title: String, acknowledgeTitle: String, overflowLine: @escaping (Int) -> String,
         makePanel: (NSRect, NSWindow.StyleMask) -> NSPanel) {
        self.acknowledgeTitle = acknowledgeTitle
        self.overflowLine = overflowLine
        heading = NSTextField(labelWithString: title)
        panel = makePanel(NSRect(x: 0, y: 0, width: Self.width, height: 80), [.borderless, .nonactivatingPanel])
        super.init()

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

        let background = NSVisualEffectView()
        background.material = .popover
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        background.layer?.masksToBounds = true
        panel.contentView = background

        heading.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        overflow.textColor = .secondaryLabelColor
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 10
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
    func setRows(_ rows: [(UUID, String)], onAcknowledge: @escaping (UUID) -> Void) {
        self.onAcknowledge = onAcknowledge
        let shown = rows.prefix(Self.maxRows)
        hiddenCount = rows.count - shown.count
        self.rows = shown.map { (id: $0.0, line: $0.1) }

        var kept: [UUID: Row] = [:]
        var views: [NSView] = [heading]
        for (id, line) in shown {
            let row = rowViews[id] ?? Row(id: id, title: acknowledgeTitle, target: self,
                                          action: #selector(acknowledged(_:)))
            row.show(line, acknowledgeTitle: acknowledgeTitle)
            kept[id] = row
            views.append(row.stack)
        }
        if hiddenCount > 0 {
            overflow.stringValue = overflowLine(hiddenCount)
            views.append(overflow)
        }
        for (id, row) in rowViews where kept[id] == nil {
            content.removeArrangedSubview(row.stack)
            row.stack.removeFromSuperview()
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
            // Each row the full width inside the insets, so its line takes the
            // slack and the buttons line up at the right.
            row.stack.widthAnchor.constraint(equalTo: content.widthAnchor,
                                             constant: -(Self.insets.left + Self.insets.right)).isActive = true
            row.pinned = true
        }
        content.layoutSubtreeIfNeeded()
        panel.setContentSize(NSSize(width: Self.width, height: content.fittingSize.height))
    }

    /// Puts the panel on screen, top right of the screen the pointer is on,
    /// without taking focus from the app in front.
    public func present() {
        let pointer = NSEvent.mouseLocation
        // With no screen at all the panel is left where it is: the spike's
        // `NSScreen.main!` would have crashed there.
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) }) ?? NSScreen.main {
            panel.setFrameOrigin(Self.origin(for: panel.frame.size, in: screen.visibleFrame))
        }
        panel.orderFrontRegardless()
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
    public func show(rows: [(UUID, String)], onAcknowledge: @escaping (UUID) -> Void) {
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
        content.arrangedSubviews.compactMap { ($0 as? NSStackView)?.arrangedSubviews.last as? RowButton }
    }

    /// The lines now drawn, top first, read from the labels themselves. For
    /// tests.
    var drawnLines: [String] {
        content.arrangedSubviews.compactMap { ($0 as? NSStackView)?.arrangedSubviews.first as? NSTextField }
            .map(\.stringValue)
    }

    /// The overflow line as drawn, or nil when every row is shown. For tests.
    var drawnOverflow: String? {
        content.arrangedSubviews.contains(overflow) ? overflow.stringValue : nil
    }

    @objc private func acknowledged(_ sender: RowButton) {
        guard let id = sender.escalationID else { return }
        onAcknowledge?(id)
    }

    /// One row: its line, then its button.
    @MainActor
    private final class Row {
        let stack: NSStackView
        let label: NSTextField
        let button: RowButton
        var pinned = false

        init(id: UUID, title: String, target: AnyObject, action: Selector) {
            label = NSTextField(wrappingLabelWithString: "")
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            label.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
            button = RowButton(title: title, target: target, action: action)
            button.escalationID = id
            button.setContentHuggingPriority(.required, for: .horizontal)
            stack = NSStackView(views: [label, button])
            stack.orientation = .horizontal
            stack.alignment = .centerY
            stack.spacing = 12
            stack.translatesAutoresizingMaskIntoConstraints = false
        }

        func show(_ line: String, acknowledgeTitle: String) {
            guard label.stringValue != line else { return }
            label.stringValue = line
            // Every button reads the same; VoiceOver is told which row each
            // acknowledges. The line holds nothing that arrived (ruling 17).
            button.setAccessibilityLabel("\(acknowledgeTitle): \(line)")
        }
    }
}

/// A row's Acknowledge button, carrying the escalation it acknowledges.
final class RowButton: NSButton {
    var escalationID: UUID?
}
