// Sources/SignalLadder/WaveformView.swift
import NotificationCore
import SwiftUI

/// Draws the sound as a waveform on the navy ground, with its selection and its playhead, and answers to the keyboard
/// and the pointer (sound editor plan, Ruling 13 and Task 7).
///
/// It is one focusable element. Space plays and stops, the arrows move the playhead, Shift with them selects, and
/// Home and End go to the ends: which key it was is all this says, and what it comes to is `WaveformKeys`'. To
/// VoiceOver it is one adjustable element that says where the playhead is and what is selected, with actions to
/// select all, play or stop, and clear.
///
/// **Nothing here depends on colour.** The selection is told by its tint and also by a bracket at each end, a line
/// with a tick across the top and the bottom, and a handle that is the size of the reach that can take hold of it. The
/// playhead is a line with a head. The lines are as wide as `DisplaySettings` says a line is, so that Increase
/// Contrast and Differentiate Without Colour make them heavier. The ground is opaque, so Reduce Transparency changes
/// nothing, and the playhead holds still only as the sound does, since it is where the sound is.
///
/// This file may hold no word of its own (the strict list in `ViewLiteralsTests`): every label is
/// `SoundEditorText`'s. The ground is navy whatever the system's appearance, so the colours of the waveform are the
/// palette's and the label colour is white, as the status popover's is.
struct WaveformView: View {
    @ObservedObject var model: SoundEditorModel

    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColour
    @FocusState private var isFocused: Bool
    @State private var isPointerDown = false

    private static let corner: CGFloat = 12

    private var settings: DisplaySettings {
        DisplaySettings(increaseContrast: contrast == .increased, reduceTransparency: reduceTransparency,
                        reduceMotion: reduceMotion, differentiateWithoutColour: differentiateWithoutColour)
    }

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                draw(in: &context, size: size)
            }
            .contentShape(Rectangle())
            .gesture(drag(width: geometry.size.width))
            .onAppear { model.setDrawingWidth(geometry.size.width) }
            .onChange(of: geometry.size.width) { _, width in model.setDrawingWidth(width) }
        }
        .background(NightWatchPalette.ground)
        .clipShape(RoundedRectangle(cornerRadius: Self.corner, style: .continuous))
        .overlay {
            // Navy against a dark window is not much of an edge, so for someone who asked for more contrast it has a
            // line.
            RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
                .strokeBorder(NightWatchPalette.outline, lineWidth: settings.increaseContrast ? settings.outlineWidth : 0)
        }
        .environment(\.colorScheme, .dark)
        .focusable()
        .focused($isFocused)
        // Space plays as soon as the window is open, and not only after a click on the waveform.
        .onAppear { isFocused = true }
        .onKeyPress(phases: [.down, .repeat]) { press in handle(press) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SoundEditorText.waveformLabel(model.displayName))
        .accessibilityValue(SoundEditorText.waveformValue(playhead: model.timeline.playhead,
                                                          selection: model.timeline.selection,
                                                          length: model.timeline.length))
        .accessibilityHint(SoundEditorText.waveformHint)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: model.press(.right, extending: false)
            case .decrement: model.press(.left, extending: false)
            @unknown default: break
            }
        }
        .accessibilityAction(named: SoundEditorText.Command.selectAll.title) { model.selectAll() }
        .accessibilityAction(named: model.controls.playCommand.title) { model.togglePlayback() }
        .accessibilityAction(named: SoundEditorText.Command.clearSelection.title) { model.clearSelection() }
    }

    // MARK: - The keyboard and the pointer

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        // A key with Command, Control or Option is a shortcut for someone else to answer.
        guard press.modifiers.isDisjoint(with: [.command, .control, .option]), let key = Self.key(of: press) else {
            return .ignored
        }
        model.press(key, extending: press.modifiers.contains(.shift))
        return .handled
    }

    private static func key(of press: KeyPress) -> WaveformKey? {
        switch press.key {
        case .space: return .space
        case .leftArrow: return .left
        case .rightArrow: return .right
        case .home: return .home
        case .end: return .end
        default: return nil
        }
    }

    private func drag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                isFocused = true
                if !isPointerDown {
                    isPointerDown = true
                    model.pointerDown(x: value.startLocation.x, width: width)
                }
                model.pointerMoved(x: value.location.x, width: width)
            }
            .onEnded { value in
                isPointerDown = false
                model.pointerUp(x: value.location.x, width: width)
            }
    }

    // MARK: - Drawing

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let viewport = model.viewport
        let timeline = model.timeline
        let line = settings.outlineWidth
        let reach = WaveformViewport.edgeReachPoints
        let middle = size.height / 2

        func place(_ frame: Int) -> CGFloat { CGFloat(viewport.x(of: frame, width: size.width)) }

        var selected: CGRect?
        if let selection = timeline.selection {
            let left = min(max(place(selection.lowerBound), 0), size.width)
            let right = min(max(place(selection.upperBound), 0), size.width)
            if right > left {
                let band = CGRect(x: left, y: 0, width: right - left, height: size.height)
                selected = band
                context.fill(Path(band), with: .color(NightWatchPalette.raised))
            }
        }

        // The waveform. A bar is at least a hairline tall, so a stretch of silence is still a line and not a gap.
        var trace = Path()
        for bar in model.columns?.bars(in: viewport, width: size.width) ?? [] {
            let top = middle - CGFloat(min(bar.high, 1)) * middle
            let bottom = middle - CGFloat(max(bar.low, -1)) * middle
            trace.addRect(CGRect(x: bar.x, y: top, width: max(bar.width, 1), height: max(bottom - top, 1)))
        }
        context.fill(trace, with: .color(NightWatchPalette.quietWords))
        if let selected {
            var inside = context
            inside.clip(to: Path(selected))
            inside.fill(trace, with: .color(NightWatchPalette.words))
        }

        // The selection's ends: a line with a tick across the top and the bottom turned inward, so that a bracket
        // says which side is selected, and a handle at the middle that is the size of the reach that takes hold of it.
        if let selection = timeline.selection {
            for (frame, inward) in [(selection.lowerBound, 1.0), (selection.upperBound, -1.0)] {
                let x = place(frame)
                guard x >= 0, x <= size.width else { continue }
                var bracket = Path()
                bracket.move(to: CGPoint(x: x, y: 0))
                bracket.addLine(to: CGPoint(x: x, y: size.height))
                bracket.move(to: CGPoint(x: x, y: line / 2))
                bracket.addLine(to: CGPoint(x: x + inward * reach, y: line / 2))
                bracket.move(to: CGPoint(x: x, y: size.height - line / 2))
                bracket.addLine(to: CGPoint(x: x + inward * reach, y: size.height - line / 2))
                context.stroke(bracket, with: .color(NightWatchPalette.words), lineWidth: line)
                let handle = CGRect(x: x - reach / 2, y: middle - reach, width: reach, height: reach * 2)
                context.fill(Path(roundedRect: handle, cornerRadius: reach / 2), with: .color(NightWatchPalette.words))
                context.stroke(Path(roundedRect: handle, cornerRadius: reach / 2), with: .color(NightWatchPalette.ground),
                               lineWidth: line / 2)
            }
        }

        // The playhead: a line with a head, so that it is told from a bracket by its shape and not by where it is.
        let at = place(timeline.playhead)
        if at >= 0, at <= size.width {
            var playhead = Path()
            playhead.move(to: CGPoint(x: at, y: 0))
            playhead.addLine(to: CGPoint(x: at, y: size.height))
            context.stroke(playhead, with: .color(NightWatchPalette.words), lineWidth: line)
            var head = Path()
            head.move(to: CGPoint(x: at - reach / 2, y: 0))
            head.addLine(to: CGPoint(x: at + reach / 2, y: 0))
            head.addLine(to: CGPoint(x: at, y: reach))
            head.closeSubpath()
            context.fill(head, with: .color(NightWatchPalette.words))
        }
    }
}
