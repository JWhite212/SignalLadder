// Sources/SignalLadder/SoundEditorModel.swift
import AlertAudio
import Combine
import Foundation
import NotificationCore

/// What the sound editor's window shows and does (sound editor plan, Rulings 5, 6, 7 and 13, and Task 7). Read-only
/// for now: the sound is opened, rendered, drawn, checked and played, and nothing is edited.
///
/// **It decides nothing.** The app target has no tests, so what can be decided in the core is. Where the playhead and
/// the selection are, and what a key or the pointer does to them, is `SoundTimeline` and `WaveformKeys`; which stretch
/// is shown and what a place on the drawing is, `WaveformViewport`; what a press of Play asks the player for,
/// `SoundPreviewPlan`; what is on and what is off, `SoundEditorControls`; which render's result is taken,
/// `SoundRenderTickets`; and what a render makes, `SoundEditorRendering`. This reads, hands on and shows.
///
/// **Nothing slow runs on the main actor** (Ruling 6). Opening reads and decodes a whole file, a render is a loop over
/// at most 30 seconds of samples and a zoomed waveform's columns are another, so each is done in a detached task over
/// values only and comes back under the number it was asked for. Only the newest is taken. While a newer render is
/// under way the window goes on with the last it took, plays that, and says it is catching up.
///
/// **A preview is a test, and never an alert** (Ruling 7). It is played through `AlertPlayer.testBuffer`, at the gain
/// the whole of the result would be given as an alert, worked out once with each render. The player refuses it while
/// an alert plays and an alert's start ends it, which this finds when it next asks where the preview has got to. It is
/// recorded nowhere, and what is said of one that did not play is `SoundEditorText`'s and never the player's own
/// description of the failure.
@MainActor
final class SoundEditorModel: ObservableObject {
    /// What the window is showing in place of the editor, or the editor.
    enum Phase: Equatable {
        /// The sound is being read and its first render is under way.
        case opening
        /// The sound is open and drawn.
        case ready
        /// The sound could not be opened: the sentence that says so.
        case failed(String)
    }

    /// The name the sound was asked for by, which is the rule's.
    let soundName: String
    /// The gain of the rule the sound is for, in decibels, which a preview is played with.
    let ruleGainDB: Double
    /// Told the name a saved sound was given. Nothing saves yet (Task 9), so nothing calls it.
    let onSaved: (String) -> Void

    private let library: SoundLibrary
    private let player: AlertPlayer

    @Published private(set) var phase: Phase = .opening
    /// The sound's name as its file spells it, once it is open.
    @Published private(set) var displayName: String
    /// The last render that finished, which is what is checked, drawn and played.
    @Published private(set) var rendered: SoundRendered?
    /// What the waveform is drawn from. Made with each render, and again when a zoom, a scroll or a wider window needs
    /// finer columns than these.
    @Published private(set) var columns: WaveformColumns?
    @Published private(set) var timeline = SoundTimeline(length: 0)
    @Published private(set) var viewport = WaveformViewport(length: 0)
    @Published private(set) var loops = false
    @Published private(set) var isPreviewing = false
    /// A preview was refused or could not be played: the sentence that says so.
    @Published private(set) var notice: String?
    /// The Mac's output was muted or at zero when the preview began.
    @Published private(set) var outputIsSilent = false
    /// A newer render is under way, so what is shown is the last that finished.
    @Published private(set) var isCatchingUp = false

    private var source: SampleBuffer?
    private var recipe: SoundRecipe?
    private var renderTickets = SoundRenderTickets()
    private var columnTickets = SoundRenderTickets()
    private var drawingWidth = 0.0
    private var previewReturnsTo: Int?
    private var ticker: Task<Void, Never>?
    private var isClosed = false

    /// How often the playhead is read from the player while a preview plays.
    private static let tick = Duration.milliseconds(33)

    init(soundName: String, ruleGainDB: Double, library: SoundLibrary, player: AlertPlayer,
         onSaved: @escaping (String) -> Void) {
        self.soundName = soundName
        self.ruleGainDB = ruleGainDB
        self.library = library
        self.player = player
        self.onSaved = onSaved
        displayName = soundName
    }

    // MARK: - What the window asks of it

    var controls: SoundEditorControls {
        SoundEditorControls(isReady: phase == .ready, length: timeline.length, canBeHeard: rendered?.canBeHeard ?? false,
                            isPreviewing: isPreviewing, selection: timeline.selection, viewport: viewport, loops: loops)
    }

    var findings: [SoundFinding] { rendered?.findings ?? [] }

    // MARK: - Opening and rendering

    /// Reads the sound and draws it. Decoding is done off the main actor, and a sound that cannot be opened is said so
    /// in the window, in the words of `SoundEditorText`.
    func open() async {
        let name = soundName
        let library = library
        let opened = await Task.detached(priority: .userInitiated) {
            SoundEditStore(library: library).open(name)
        }.value
        guard !isClosed else { return }
        switch opened {
        case .failure(let failure):
            phase = .failed(SoundEditorText.cannotOpen(name, failure: failure))
        case .success(let sound):
            displayName = sound.name
            source = sound.source
            recipe = sound.recipe
            timeline = SoundTimeline(length: sound.recipe.frameCount)
            viewport = WaveformViewport(length: sound.recipe.frameCount)
            requestRender()
        }
    }

    /// Renders the recipe off the main actor, under the next number. What comes back is taken only if no newer render
    /// has been asked for since.
    private func requestRender() {
        guard let source, let recipe else { return }
        let number = renderTickets.request()
        isCatchingUp = renderTickets.isCatchingUp
        let rule = ruleGainDB
        let visible = viewport.visible
        let count = WaveformColumns.count(forWidth: drawingWidth)
        Task { [weak self] in
            let made = await Task.detached(priority: .userInitiated) {
                SoundEditorRendering.render(source: source, recipe: recipe, ruleGainDB: rule, visible: visible,
                                            columnCount: count)
            }.value
            self?.takeRender(made, askedFor: number)
        }
    }

    private func takeRender(_ made: SoundRendered, askedFor number: Int) {
        let taken = !isClosed && renderTickets.accept(number)
        isCatchingUp = renderTickets.isCatchingUp
        guard taken else { return }
        rendered = made
        columns = made.columns
        timeline.setLength(made.samples.frameCount)
        viewport = viewport.resized(toLength: made.samples.frameCount)
        phase = .ready
        refreshColumnsIfNeeded()
    }

    // MARK: - The drawing's columns

    /// The drawing is `width` points wide. Told by the view as it is laid out.
    func setDrawingWidth(_ width: Double) {
        guard width.isFinite, width != drawingWidth else { return }
        drawingWidth = width
        refreshColumnsIfNeeded()
    }

    /// Asks for new columns off the main actor when what is held is not enough for what is shown. Columns that are
    /// still being waited for are drawn from the old ones, in the places their own frames are.
    private func refreshColumnsIfNeeded() {
        guard let samples = rendered?.samples, drawingWidth > 0 else { return }
        if let columns, columns.isEnough(for: viewport, width: drawingWidth) { return }
        let number = columnTickets.request()
        let frames = viewport.visible
        let count = WaveformColumns.count(forWidth: drawingWidth)
        Task { [weak self] in
            let made = await Task.detached(priority: .userInitiated) {
                WaveformColumns.make(of: samples, frames: frames, count: count)
            }.value
            self?.takeColumns(made, askedFor: number)
        }
    }

    private func takeColumns(_ made: WaveformColumns, askedFor number: Int) {
        guard !isClosed, columnTickets.accept(number) else { return }
        columns = made
        // Asked for again if the view has moved off what these cover since they were asked for, and not because
        // they are still too coarse, which a very wide window can make them whatever is done.
        let visible = viewport.visible
        if made.frames.lowerBound > visible.lowerBound || made.frames.upperBound < visible.upperBound {
            refreshColumnsIfNeeded()
        }
    }

    // MARK: - Zoom and selection

    func zoomIn() {
        guard controls.canZoomIn else { return }
        viewport.zoomIn(around: timeline.focus)
        refreshColumnsIfNeeded()
    }

    func zoomOut() {
        guard controls.canZoomOut else { return }
        viewport.zoomOut(around: timeline.focus)
        refreshColumnsIfNeeded()
    }

    func scroll(toFraction fraction: Double) {
        viewport.scroll(toFraction: fraction)
        refreshColumnsIfNeeded()
    }

    func selectAll() {
        guard controls.canSelectAll else { return }
        timeline.selectAll()
        viewport.reveal(timeline.playhead)
        refreshColumnsIfNeeded()
        restartIfPreviewing()
    }

    func clearSelection() {
        guard controls.canClearSelection else { return }
        timeline.clearSelection()
        restartIfPreviewing()
    }

    func setLoops(_ on: Bool) {
        loops = on
        restartIfPreviewing()
    }

    // MARK: - The keyboard and the pointer

    /// A key of the waveform, with whether Shift was held. Everything a key does is `WaveformKeys`'.
    func press(_ key: WaveformKey, extending: Bool) {
        switch WaveformKeys.apply(key, extending: extending, timeline: &timeline, viewport: &viewport) {
        case .togglePlayback:
            togglePlayback()
        case .moved:
            refreshColumnsIfNeeded()
            restartIfPreviewing(at: timeline.playhead)
        }
    }

    func pointerDown(x: Double, width: Double) {
        let reach = viewport.frames(spanning: WaveformViewport.edgeReachPoints, width: width)
        timeline.pointerDown(at: viewport.frame(atX: x, width: width), edgeReach: reach)
    }

    func pointerMoved(x: Double, width: Double) {
        let slop = viewport.frames(spanning: WaveformViewport.clickSlopPoints, width: width)
        timeline.pointerMoved(to: viewport.frame(atX: x, width: width), slop: slop)
    }

    func pointerUp(x: Double, width: Double) {
        let before = timeline
        timeline.pointerUp(at: viewport.frame(atX: x, width: width))
        // A press that took hold of an edge and let go changed nothing, and a preview is not made to jump for it.
        if timeline != before { restartIfPreviewing(at: timeline.playhead) }
    }

    // MARK: - Playing

    func togglePlayback() {
        if isPreviewing { stop() } else { play() }
    }

    /// Plays the last render that finished (Ruling 7), at the gain its whole would be given as an alert, through the
    /// player's test path and never as an alert. `frame` is where a preview that is already playing carries on from.
    private func play(resumingAt frame: Int? = nil) {
        guard let rendered, let gain = rendered.previewGainDB,
              let plan = SoundPreviewPlan.make(length: rendered.samples.frameCount, playhead: timeline.playhead,
                                               selection: timeline.selection, loops: loops, resumingAt: frame) else { return }
        do {
            let output = try player.testBuffer(rendered.samples, gainDB: gain, from: plan.start, loop: plan.loop)
            notice = nil
            outputIsSilent = output.isEffectivelySilent
            previewReturnsTo = previewReturnsTo ?? plan.returnsTo
            timeline.followPreview(plan.start)
            isPreviewing = true
            startTicker()
        } catch AlertPlayer.Failure.alertPlaying {
            notice = SoundEditorText.previewRefused
        } catch {
            notice = SoundEditorText.previewFailed
        }
    }

    /// Stops the preview and leaves the playhead where it had got to.
    func stop() {
        let frame = player.previewFrame
        player.stopTest()
        if let frame { timeline.followPreview(frame) }
        endPreview()
    }

    /// A change to what is selected, a loop turned on or off, or a move of the playhead, while a preview plays,
    /// plays it again as the new plan says: from `frame` when it is a move of the playhead, which is a seek, and
    /// otherwise from where the preview has got to.
    private func restartIfPreviewing(at frame: Int? = nil) {
        guard isPreviewing else { return }
        play(resumingAt: frame ?? player.previewFrame ?? timeline.playhead)
    }

    private func endPreview() {
        isPreviewing = false
        previewReturnsTo = nil
        ticker?.cancel()
        ticker = nil
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.follow() else { return }
                try? await Task.sleep(for: Self.tick)
            }
        }
    }

    /// Reads where the preview has got to. Whether it goes on: it has ended when the player says it is not playing,
    /// which is when it ran out, when an alert began, or when it was stopped from somewhere else.
    private func follow() -> Bool {
        if let frame = player.previewFrame {
            timeline.followPreview(frame)
            viewport.reveal(frame)
            refreshColumnsIfNeeded()
            return true
        }
        if let back = previewReturnsTo { timeline.previewEnded(returningTo: back) }
        endPreview()
        return false
    }

    // MARK: - Closing

    /// The window closed: a preview stops, nothing that is under way is taken, and nothing more is asked for.
    func windowClosed() {
        isClosed = true
        if isPreviewing { player.stopTest() }
        endPreview()
        renderTickets.cancelAll()
        columnTickets.cancelAll()
        isCatchingUp = false
    }
}
