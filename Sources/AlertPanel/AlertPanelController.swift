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
/// Laying rows out (`setRows`) is kept apart from putting the window on screen
/// (`present`). Tests call only the first: it needs no screen, which a test
/// runner may not have.
@MainActor
public final class AlertPanelController: NSObject {
    public let panel: NSPanel
    private let content = NSStackView()
    private let heading: NSTextField
    private let acknowledgeTitle: String
    private var onAcknowledge: ((UUID) -> Void)?

    /// The rows now laid out, in order, top first.
    public private(set) var rows: [(id: UUID, line: String)] = []

    static let width: CGFloat = 420
    static let margin: CGFloat = 20

    /// - Parameters:
    ///   - title: heads the panel; `EscalationPanelText.title` in the app.
    ///   - acknowledgeTitle: each row's button; `EscalationPanelText.acknowledge`.
    public init(title: String, acknowledgeTitle: String) {
        self.acknowledgeTitle = acknowledgeTitle
        heading = NSTextField(labelWithString: title)
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 80),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
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
        // 2026-09-30); it is set anyway, so a later change of style cannot
        // quietly bring the hiding back.
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear

        let background = NSVisualEffectView()
        background.material = .popover
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        background.layer?.masksToBounds = true
        panel.contentView = background

        heading.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 10
        content.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        content.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: background.topAnchor),
            content.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            content.widthAnchor.constraint(equalToConstant: Self.width),
        ])
    }

    /// Lays out one row per escalation, in the order given, newest first as
    /// the coordinator lists them, each with its own Acknowledge button.
    /// Replaces whatever was there. Needs no screen.
    public func setRows(_ rows: [(UUID, String)], onAcknowledge: @escaping (UUID) -> Void) {
        self.rows = rows.map { (id: $0.0, line: $0.1) }
        self.onAcknowledge = onAcknowledge
        for view in content.arrangedSubviews {
            content.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        content.addArrangedSubview(heading)
        for (id, line) in rows { content.addArrangedSubview(row(id: id, line: line)) }
        content.layoutSubtreeIfNeeded()
        panel.setContentSize(NSSize(width: Self.width, height: content.fittingSize.height))
    }

    /// Puts the panel on screen, top right of the screen the pointer is on,
    /// without taking focus from the app in front. Never called by tests.
    public func present() {
        let pointer = NSEvent.mouseLocation
        // With no screen at all the panel is left where it is: the spike's
        // `NSScreen.main!` would have crashed there.
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) }) ?? NSScreen.main {
            let visible = screen.visibleFrame
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: visible.maxX - size.width - Self.margin,
                                         y: visible.maxY - size.height - Self.margin))
        }
        panel.orderFrontRegardless()
    }

    /// Lays the rows out and shows them; with none, hides the panel. What the
    /// app's `updatePanel` calls.
    public func show(rows: [(UUID, String)], onAcknowledge: @escaping (UUID) -> Void) {
        guard !rows.isEmpty else { return hide() }
        setRows(rows, onAcknowledge: onAcknowledge)
        present()
    }

    public func hide() {
        panel.orderOut(nil)
    }

    // MARK: - Rows

    /// The buttons now laid out, top first. For tests, which press them.
    var buttons: [RowButton] {
        content.arrangedSubviews.compactMap { ($0 as? NSStackView)?.arrangedSubviews.last as? RowButton }
    }

    private func row(id: UUID, line: String) -> NSStackView {
        let label = NSTextField(wrappingLabelWithString: line)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let button = RowButton(title: acknowledgeTitle, target: self, action: #selector(acknowledged(_:)))
        button.escalationID = id
        button.setContentHuggingPriority(.required, for: .horizontal)
        let row = NSStackView(views: [label, button])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        return row
    }

    @objc private func acknowledged(_ sender: RowButton) {
        guard let id = sender.escalationID else { return }
        onAcknowledge?(id)
    }
}

/// A row's Acknowledge button, carrying the escalation it acknowledges.
final class RowButton: NSButton {
    var escalationID: UUID?
}
