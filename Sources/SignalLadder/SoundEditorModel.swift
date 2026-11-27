// Sources/SignalLadder/SoundEditorModel.swift
import AlertAudio
import Combine
import Foundation
import NotificationCore
import SwiftUI

/// What the sound editor's window shows and does (sound editor plan, Rulings 2, 4, 5, 6, 7, 13 and 16, and Tasks 7 and
/// 8): the sound is opened, rendered, drawn, checked, played and edited.
///
/// **It decides nothing.** The app target has no tests, so what can be decided in the core is. Where the playhead and
/// the selection are, and what a key or the pointer does to them, is `SoundTimeline` and `WaveformKeys`; which stretch
/// is shown and what a place on the drawing is, `WaveformViewport`; what a press of Play asks the player for,
/// `SoundPreviewPlan`; what is on and what is off, `SoundEditorControls`; which render's result is taken,
/// `SoundRenderTickets`; what a render makes, `SoundEditorRendering`; what an edit command comes to, on which edges,
/// and where the playhead goes after it, `SoundEditorEditing`; and what is said of a refusal, `SoundEditorText`. This
/// reads, hands on and shows.
///
/// **Every edit is made by `SoundEditHistory.commit`** and by nothing else (Ruling 2): a command, and the press of a
/// check, come to a `SoundEdit` that goes through the one `commit` here, which asks for a render of what it made. Undo,
/// redo and reset are the history's own. The edit is made to the history's present recipe and the selection it is made
/// on is of the result as last rendered, which is why nothing that reads a position is done while a render is still
/// under way (`SoundEditorControls`).
///
/// **Nothing slow runs on the main actor** (Ruling 6). Opening reads and decodes a whole file, a render is a loop over
/// at most 30 seconds of samples and a zoomed waveform's columns are another, so each is done in a detached task over
/// values only and comes back under the number it was asked for. Only the newest is taken. While a newer render is
/// under way the window goes on with the last it took, plays that, and says it is catching up. The main actor swaps
/// in the finished samples, peaks and findings, and puts the playhead and the selection where the edit said, and
/// does nothing else with them.
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
    /// The recipe as it is, and the ones before and after it, once the sound is open. The only thing that is edited.
    @Published private(set) var history: SoundEditHistory?
    /// What Cut or Copy last kept, to be pasted.
    @Published private(set) var clipboard: SoundExcerpt?
    /// What the gain control is set to, in decibels, and what the repeat controls are set to.
    @Published private(set) var gainDB = 0.0
    @Published private(set) var repeatPlays = SoundEditorEditing.defaultPlays
    @Published private(set) var repeatGapSeconds = SoundEditorEditing.defaultGapSeconds
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
    /// Where the edit that was last made says the playhead and the selection go, held until its render is taken.
    private var pendingPlacement: SoundEditPlacement?
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
                            isPreviewing: isPreviewing, selection: timeline.selection, viewport: viewport, loops: loops,
                            canUndo: history?.canUndo ?? false, canRedo: history?.canRedo ?? false,
                            canReset: !(history?.present.isOriginal ?? true), hasClipboard: clipboard != nil,
                            isCatchingUp: isCatchingUp, gainDB: gainDB)
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
            history = SoundEditHistory(sound.recipe)
            timeline = SoundTimeline(length: sound.recipe.frameCount)
            viewport = WaveformViewport(length: sound.recipe.frameCount)
            requestRender()
        }
    }

    /// Renders the recipe off the main actor, under the next number. What comes back is taken only if no newer render
    /// has been asked for since.
    private func requestRender() {
        guard let source, let recipe = history?.present else { return }
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
        // Where the edit that was asked for says the playhead and the selection go, now that there is a result for them
        // to be held to. Only the render that is taken gets here, so a placement is never put on a sound it is not of.
        if let placement = pendingPlacement {
            timeline.apply(placement)
            viewport.reveal(timeline.playhead)
            pendingPlacement = nil
        }
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

    // MARK: - Commands

    /// One command of the window, from a button, a shortcut or VoiceOver. Nothing is done that is off.
    func perform(_ command: SoundEditorText.Command) {
        guard controls.canPerform(command) else { return }
        switch command {
        case .play, .stop: togglePlayback()
        case .loopSelection: setLoops(!loops)
        case .selectAll: selectAll()
        case .clearSelection: clearSelection()
        case .zoomIn: zoomIn()
        case .zoomOut: zoomOut()
        case .undo: undo()
        case .redo: redo()
        case .resetToOriginal: resetToOriginal()
        case .trim, .delete, .cut, .copy, .paste, .duplicate, .fadeIn, .fadeOut, .gain, .repeatSelection: edit(command)
        }
    }

    // MARK: - Editing

    /// What the gain and repeat controls are set to, held to what the core offers.
    func setGainDB(_ value: Double) { gainDB = SoundEditorEditing.clampedGainDB(value) }
    func setRepeatPlays(_ value: Int) { repeatPlays = SoundEditorEditing.clampedPlays(value) }
    func setRepeatGapSeconds(_ value: Double) { repeatGapSeconds = SoundEditorEditing.clampedGapSeconds(value) }

    func undo() { if history?.undo() == true { changed(placing: .keep) } }
    func redo() { if history?.redo() == true { changed(placing: .keep) } }
    func resetToOriginal() { if history?.reset() == true { changed(placing: .playhead(0)) } }

    /// The press of a check: its own fix, which is an edit like any other, or going back.
    func fix(_ finding: SoundFinding) {
        guard let fix = finding.fix, controls.canPress(fix) else { return }
        switch fix {
        case .undo: undo()
        case .edit(let edit): attempt { _ = try commit(edit) }
        }
    }

    /// An edit command, from the selection and the samples of the last render: the core says what it comes to, with the
    /// edges moved to a quiet point of those samples (Ruling 4), and the history makes it.
    private func edit(_ command: SoundEditorText.Command) {
        guard let rendered else { return }
        let planned = SoundEditorEditing.plan(command, selection: timeline.selection, playhead: timeline.playhead,
                                              samples: rendered.samples, clipboard: clipboard, gainDB: gainDB, plays: repeatPlays,
                                              gapSeconds: repeatGapSeconds)
        switch planned {
        case .success(let planned)?: attempt { try make(planned) }
        case .failure(let refusal)?: say(SoundEditorText.refusal(refusal))
        case nil: break
        }
    }

    /// What a planned edit comes to: the copy it keeps, taken from the recipe as it is before the edit, and the edit.
    /// What was copied is kept once the edit has been made, so that a cut that was refused keeps nothing.
    private func make(_ planned: SoundEditorEdit) throws {
        let copied = try planned.copying.flatMap { try history?.present.excerpt(of: $0) }
        if let edit = planned.edit {
            guard try commit(edit) else { return }
        }
        if let copied { clipboard = copied }
    }

    /// The one place an edit is made (Ruling 2). It changes the recipe only through the history, which refuses what
    /// would break it and adds nothing to the past for an edit that left it as it was.
    ///
    /// - Returns: whether the recipe changed.
    private func commit(_ edit: SoundEdit) throws -> Bool {
        guard try history?.commit(edit) == true else { return false }
        changed(placing: SoundEditPlacement.after(edit))
        return true
    }

    /// The recipe has changed, by an edit, an undo, a redo or a reset: what plays is the sound as it was and so
    /// stops, the playhead and the selection are told where to go once the new sound is rendered, and the render is
    /// asked for.
    private func changed(placing placement: SoundEditPlacement) {
        if isPreviewing { stop() }
        pendingPlacement = placement
        notice = nil
        requestRender()
    }

    /// Runs something that makes an edit, and says in the text's words why it was not made when it was refused.
    private func attempt(_ work: () throws -> Void) {
        do {
            try work()
        } catch let refusal as SoundEditRefusal {
            say(SoundEditorText.refusal(refusal))
        } catch {
            say(SoundEditorText.editFailed)
        }
    }

    /// Shows a sentence in the window, and tells VoiceOver, which does not read what is only drawn.
    private func say(_ sentence: String) {
        notice = sentence
        AccessibilityNotification.Announcement(sentence).post()
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
        // A press that took hold of an edge and let go changed nothing, and a preview is not made to jump for it. The
        // timeline says which it was: a copy of it made before the press ended would never be equal to it after.
        if timeline.pointerUp(at: viewport.frame(atX: x, width: width)) { restartIfPreviewing(at: timeline.playhead) }
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
    /// otherwise from where the preview has got to. A move to the end of the sound ends the preview there, and does not
    /// play it again from the start (`SoundPreviewPlan.endsPreview`).
    private func restartIfPreviewing(at frame: Int? = nil) {
        guard isPreviewing else { return }
        if let frame, let rendered,
           SoundPreviewPlan.endsPreview(seekingTo: frame, length: rendered.samples.frameCount, selection: timeline.selection,
                                        loops: loops) {
            stop()
            timeline.followPreview(frame)
            return
        }
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
        // The controller keeps the model, and the closed window's view keeps it too, so the sound and what was made of
        // it are let go here: a long sound is some tens of megabytes twice over.
        source = nil
        history = nil
        clipboard = nil
        pendingPlacement = nil
        rendered = nil
        columns = nil
    }
}
