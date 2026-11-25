// Sources/SignalLadder/StatusPopoverView.swift
import NotificationCore
import SwiftUI

/// Draws the status item's popover in the Night watch design (M7 plan, Stage 5).
///
/// What it shows is `StatusPopover.Content`, made once as the popover opens, so
/// nothing here moves while it is open. This draws it and decides nothing, and
/// holds no word of its own. The one thing it keeps is whether the Snooze
/// tile's choices are open, which the user opens with the tile.
struct StatusPopoverView: View {
    let content: StatusPopover.Content
    /// Whether the rows scroll, which the controller asks for when the screen
    /// has less room under the menu bar than they need.
    var scrolls = false
    let perform: (StatusPopover.Action) -> Void

    @State private var snoozeOpen = false

    static let width: CGFloat = 340
    static let corner: CGFloat = 26
    private static let blockCorner: CGFloat = 16
    private static let tileCorner: CGFloat = 14

    var body: some View {
        Group {
            if scrolls {
                ScrollView { rows }
            } else {
                rows.fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(width: Self.width)
        .background(NightWatchPalette.ground)
        .clipShape(RoundedRectangle(cornerRadius: Self.corner, style: .continuous))
        // The ground is navy whatever the system's appearance, so the label
        // colour is white here, and a fault's outline with it.
        .environment(\.colorScheme, .dark)
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !content.waiting.isEmpty || content.acknowledgeTitle != nil {
                waiting
            }
            if !content.escalationLines.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(content.escalationLines.enumerated()), id: \.offset) { line($0.element) }
                }
            }
            ForEach(Array(content.sections.enumerated()), id: \.offset) { section($0.element) }
            tiles
            if snoozeOpen {
                inset {
                    ForEach(Array(content.snoozeChoices.enumerated()), id: \.offset) { line($0.element) }
                }
            }
            commands
        }
        .padding(14)
    }

    // MARK: - What waits

    private var waiting: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(content.waiting.enumerated()), id: \.offset) { block($0.element) }
            if let more = content.moreWaiting {
                Text(more).font(.callout).foregroundStyle(NightWatchPalette.quietWords)
            }
            if let title = content.acknowledgeTitle {
                Button { perform(.acknowledgeListed) } label: {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(NightWatchPalette.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(NightWatchPalette.words, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// One escalation: the tier's colour under navy words, the count large at
    /// the edge. A fault has a line round it and no colour.
    private func block(_ waiting: StatusPopover.Waiting) -> some View {
        let words = waiting.tone == nil ? NightWatchPalette.words : NightWatchPalette.ink
        return HStack(alignment: .center, spacing: 10) {
            if waiting.tone == nil {
                Image(systemName: "bell.slash").font(.title2)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(waiting.row.name).font(.headline).lineLimit(2)
                detail(waiting.row.detail).font(.callout).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if let figure = waiting.figure {
                Text(figure).font(.system(size: 26, weight: .bold, design: .monospaced))
            }
        }
        .foregroundStyle(words)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if let tone = waiting.tone {
                RoundedRectangle(cornerRadius: Self.blockCorner, style: .continuous).fill(NightWatchPalette.block(tone))
            } else {
                RoundedRectangle(cornerRadius: Self.blockCorner, style: .continuous)
                    .strokeBorder(NightWatchPalette.outline, lineWidth: 1.5)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(waiting.row.line)
    }

    /// The line under the name, its times and counts in fixed-width figures.
    private func detail(_ parts: [EscalationPanelText.Row.Part]) -> Text {
        parts.reduce(Text(verbatim: "")) { text, part in
            switch part {
            case .words(let words): return text + Text(words)
            case .figure(let figure): return text + Text(figure).font(.mono(.callout, weight: .semibold))
            }
        }
    }

    // MARK: - The lines

    private func section(_ section: StatusPopover.Section) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(section.heading)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(NightWatchPalette.quietWords)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(section.lines.enumerated()), id: \.offset) { line($0.element) }
        }
    }

    @ViewBuilder
    private func line(_ line: StatusPopover.Line) -> some View {
        if let action = line.action {
            Button { perform(action) } label: {
                HStack(spacing: 6) {
                    words(line)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(NightWatchPalette.quietWords)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            words(line)
        }
    }

    @ViewBuilder
    private func words(_ line: StatusPopover.Line) -> some View {
        let text = Text(line.text)
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        switch line.mark {
        case .plain: text.foregroundStyle(NightWatchPalette.words)
        case .indented: text.foregroundStyle(NightWatchPalette.quietWords).padding(.leading, 12)
        case .fault: text.faultOutlined()
        }
    }

    // MARK: - Tiles

    private var tiles: some View {
        HStack(spacing: 8) {
            ForEach(Array(content.tiles.enumerated()), id: \.offset) { tile($0.element) }
        }
    }

    private func tile(_ tile: StatusPopover.Tile) -> some View {
        Button {
            if let action = tile.action { perform(action) } else { snoozeOpen.toggle() }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: tile.kind.symbol).font(.title3).frame(height: 22)
                Text(tile.title).font(.callout.weight(.medium))
                // A tile with no key keeps the line, so the three are one height.
                Text(tile.key ?? "").font(.mono(.caption)).foregroundStyle(NightWatchPalette.quietWords)
            }
            .foregroundStyle(NightWatchPalette.words)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(NightWatchPalette.raised, in: RoundedRectangle(cornerRadius: Self.tileCorner, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tile.title)
    }

    // MARK: - Commands

    private var commands: some View {
        inset {
            ForEach(Array(content.commands.enumerated()), id: \.offset) { command($0.element) }
        }
    }

    private func command(_ command: StatusPopover.Command) -> some View {
        Button { perform(command.action) } label: {
            HStack(spacing: 6) {
                if let isOn = command.isOn {
                    Image(systemName: "checkmark").font(.caption.weight(.bold)).opacity(isOn ? 1 : 0)
                        .accessibilityHidden(true)
                }
                Text(command.title).font(.callout)
                Spacer(minLength: 0)
                if let key = command.key {
                    Text(key).font(.mono(.callout)).foregroundStyle(NightWatchPalette.quietWords)
                }
            }
            .foregroundStyle(NightWatchPalette.words)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(command.isOn == true ? .isSelected : [])
    }

    /// A block a shade above the ground, for the rows that are commands.
    private func inset<Rows: View>(@ViewBuilder _ rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: 9) { rows() }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NightWatchPalette.raised.opacity(0.55),
                        in: RoundedRectangle(cornerRadius: Self.tileCorner, style: .continuous))
    }
}
