// Sources/NotificationCapture/AXBannerWatcher.swift
import Foundation
import ApplicationServices
import AppKit
import os
import NotificationCore

/// Owns the only AXObserver in the program.
///
/// Two facts from the spec shape this class. The system-wide AX element
/// cannot observe notifications (kAXErrorNotificationUnsupported), so the
/// observer is created against notificationcenterui's pid. And that process
/// restarts, so NSWorkspace launch/terminate observation drives re-attach —
/// without it the app dies silently the first time the process recycles.
public final class AXBannerWatcher {
    private let bundleID = "com.apple.notificationcenterui"
    private let tracker = BannerTracker()
    private let onCapture: (RawCapture, [String]) -> Void

    /// Fired after a successful attach. Re-attaching is precisely when capture
    /// most needs re-proving, since the process it observes has just restarted.
    public var onAttach: (() -> Void)?

    private var observer: AXObserver?
    private var appElement: AXUIElement?
    private var processSource: DispatchSourceProcess?
    private var pendingReattach: DispatchWorkItem?
    private var reattachDelay: TimeInterval = 1.0

    /// Events come in bursts — twenty or so as Notification Centre opens —
    /// and each burst is read once, this long after its first event. Reading
    /// whole windows, which telling the history panel from banners needs,
    /// would otherwise repeat for every event in it.
    private static let scanDelay: TimeInterval = 0.05
    private var scanScheduled = false

    /// How soon a row in Notification Centre's panel that needs a second read
    /// gets one — long enough for a flickering time label to come back.
    private static let secondReadDelay = BannerTracker.secondReadGap + 0.05

    /// A row awaiting its second read is decided only by another read. If
    /// reading the windows fails, that read is tried again, a few times at
    /// most, so a busy Notification Centre cannot strand it and a dead one
    /// cannot spin the main thread.
    private var secondReadOwed = false
    private var secondReadRetries = 0
    private static let secondReadRetryLimit = 5

    /// Whether an observer is currently registered. Feeds the health model —
    /// an unattached watcher captures nothing, whatever else is healthy.
    public var isAttached: Bool { observer != nil }

    /// Counts the window and element-destroyed events received, whether or not
    /// a banner was found in them. Deliberately NOT a count of captures, and
    /// deliberately leaves out layout changes, which were not part of the
    /// evidence below when it was established and have not been measured under
    /// Do Not Disturb.
    ///
    /// This is the app's only evidence about whether a notification was drawn
    /// at all. Notification Centre creates a window when it presents a banner,
    /// and that produces an event here even if locating or reading the banner
    /// then fails. When Do Not Disturb or a Focus routes a notification
    /// straight to history, no window is created and nothing arrives. So zero
    /// events across a self-test means the alert was never shown — which is a
    /// delivery fault — while events with no match means it was shown and
    /// missed, which is a capture fault. Nothing in notification settings
    /// distinguishes those two; this does.
    public private(set) var observerEventCount = 0

    public init(onCapture: @escaping (RawCapture, [String]) -> Void) {
        self.onCapture = onCapture
    }

    /// The observer's run-loop source outlives this object unless it is torn
    /// down explicitly, and the callback refcon is unretained — so a
    /// deallocated-but-still-attached watcher would hand freed memory to
    /// `takeUnretainedValue()`. Teardown targets the main run loop by name
    /// rather than the calling thread's, because `deinit` runs wherever the
    /// last reference is dropped. Callers are still expected to keep the
    /// watcher alive for the lifetime of the run loop.
    deinit {
        detach()
    }

    /// Must be called on the main queue: the observer's run-loop source is
    /// added to whatever run loop is current here, and every later attach /
    /// detach (workspace notifications, backoff retries) runs on main.
    public func start() {
        dispatchPrecondition(condition: .onQueue(.main))
        observeWorkspace()
        attach()
    }

    // MARK: - Attach

    private func attach() {
        detach()

        guard let app = NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == bundleID })
        else {
            log("notificationcenterui not running; retrying in \(reattachDelay)s")
            scheduleReattach()
            return
        }

        let pid = app.processIdentifier
        var created: AXObserver?

        let callback: AXObserverCallback = { _, _, notification, refcon in
            guard let refcon else { return }
            let watcher = Unmanaged<AXBannerWatcher>.fromOpaque(refcon).takeUnretainedValue()
            watcher.handle(notification: notification as String)
        }

        guard AXObserverCreate(pid, callback, &created) == .success, let created else {
            log("AXObserverCreate failed for pid \(pid)")
            scheduleReattach()
            return
        }

        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, 0.2)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        // The window notifications drive capture of a banner that opens a
        // window. A banner that replaces another while it is still on screen
        // opens none, and announces itself only as a layout change — so that
        // is registered too. It is optional, like destruction: an observer
        // without it still captures every banner that arrives on its own, and
        // failing to get it must not push the watcher into permanent backoff
        // with zero captures. Its absence is logged by name, since without it
        // a banner arriving during another is missed.
        let required = [
            kAXWindowCreatedNotification,
            kAXWindowMovedNotification,
        ]
        let optional = [
            kAXUIElementDestroyedNotification,
            kAXLayoutChangedNotification,
        ]

        var registrationFailed = false
        for name in required {
            let err = AXObserverAddNotification(created, element, name as CFString, refcon)
            if err != .success {
                log("required AXObserverAddNotification(\(name)) failed: \(err.rawValue)")
                registrationFailed = true
            }
        }
        for name in optional {
            let err = AXObserverAddNotification(created, element, name as CFString, refcon)
            if err != .success {
                let missed = name == kAXLayoutChangedNotification
                    ? "; a banner arriving while another is on screen will be missed" : ""
                log("optional AXObserverAddNotification(\(name)) failed: \(err.rawValue) — continuing\(missed)")
            }
        }

        // Registering only some of the notifications means running half-deaf:
        // certain banner events would never arrive and nothing would say why.
        // Discard the observer and retry rather than reporting a healthy attach.
        guard !registrationFailed else {
            log("partial notification registration; discarding observer and retrying")
            scheduleReattach()
            return
        }

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(created),
            .defaultMode
        )

        observer = created
        appElement = element
        // A new process has new elements; nothing read from the old one can
        // appear again.
        tracker.reset()
        secondReadOwed = false
        reattachDelay = 1.0
        pendingReattach?.cancel()
        pendingReattach = nil
        log("attached to notificationcenterui pid=\(pid)")
        onAttach?()

        // NSWorkspace notifications are NOT delivered to a non-GUI process.
        // Proven by live testing: notificationcenterui restarted (pid 8781 ->
        // 9587) and not one workspace event arrived for any app. Exit
        // detection therefore cannot depend on them — this watches the pid
        // directly, which works in any process type and stays event-driven.
        let source = DispatchSource.makeProcessSource(
            identifier: pid,
            eventMask: .exit,
            queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            self.log("notificationcenterui (pid \(pid)) exited; scheduling re-attach")
            self.scheduleReattach()
        }
        source.resume()
        processSource = source
    }

    private func detach() {
        // Cancelled before the guard: the process source can exist even when
        // the observer does not, and leaking it would leave a stale handler
        // firing re-attaches for a pid we no longer care about.
        processSource?.cancel()
        processSource = nil
        pendingReattach?.cancel()
        pendingReattach = nil

        guard let observer, let appElement else { return }
        for name in [kAXWindowCreatedNotification, kAXWindowMovedNotification,
                     kAXUIElementDestroyedNotification, kAXLayoutChangedNotification] {
            AXObserverRemoveNotification(observer, appElement, name as CFString)
        }
        CFRunLoopRemoveSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )
        self.observer = nil
        self.appElement = nil
    }

    /// Exponential backoff, capped, so a permanently-absent process does not
    /// spin.
    ///
    /// The guard matters more than it looks. A single restart of
    /// notificationcenterui fires up to three signals in a bundled app — pid
    /// exit, NSWorkspace terminate, NSWorkspace launch. Without the guard each
    /// one cancelled the pending retry and rescheduled with an already-doubled
    /// delay, so extra signals pushed recovery further away instead of closer.
    /// Backoff must grow once per failed ATTEMPT, not once per signal.
    private func scheduleReattach() {
        guard pendingReattach == nil else { return }

        let delay = reattachDelay
        reattachDelay = min(reattachDelay * 2, 30)

        let work = DispatchWorkItem { [weak self] in
            self?.pendingReattach = nil
            self?.attach()
        }
        pendingReattach = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func observeWorkspace() {
        // A SECONDARY signal. It does not fire in the CLI probe — verified by
        // live testing on macOS 26.7 — but does fire inside a bundled app.
        // Both paths route through scheduleReattach() so that when both are
        // live they coalesce on the same timer instead of racing.
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let self,
                      let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.bundleIdentifier == self.bundleID
                else { return }
                self.log("notificationcenterui lifecycle event; scheduling re-attach")
                self.scheduleReattach()
            }
        }
    }

    // MARK: - Capture

    private func handle(notification: String) {
        // Counted before any filtering, because the question this answers is
        // "did Notification Centre draw anything at all", not "did we
        // understand it".
        if notification != kAXLayoutChangedNotification {
            observerEventCount += 1
        }

        scheduleScan(after: Self.scanDelay)
    }

    private func scheduleScan(after delay: TimeInterval) {
        guard !scanScheduled else { return }
        scanScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.scanScheduled = false
            self.scanWindows()
        }
    }

    /// Reads every window Notification Centre has, whole. The callback carries
    /// no payload, so content must be read by walking the tree. A banner's
    /// text lives in its children's AXValue, not in its own description — so
    /// a banner is worth emitting if EITHER source has content.
    ///
    /// Requiring a description would drop a banner whose children are fully
    /// populated, and would make the partial-blindness case (banners present,
    /// descriptions empty) look identical to an idle system. That case is the
    /// one this whole project is built to detect, so it is logged loudly
    /// rather than skipped quietly.
    ///
    /// One banner produces many events — its window, its moves, its layout
    /// changes — and the tracker lets each through once.
    private func scanWindows() {
        var value: CFTypeRef?
        guard let appElement,
              AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement]
        else {
            if secondReadOwed, secondReadRetries < Self.secondReadRetryLimit {
                secondReadRetries += 1
                scheduleScan(after: Self.secondReadDelay)
            }
            return
        }

        var needsSecondRead = false
        for window in windows {
            let scan = tracker.scan(AXElementNode(window), at: Date())
            needsSecondRead = needsSecondRead || scan.needsSecondRead
            for subrole in scan.empty {
                log("matched banner subrole=\(subrole) with no description AND no text children — possible partial blindness")
            }
            for banner in scan.new {
                onCapture(
                    RawCapture(
                        timestamp: Date(),
                        rawText: banner.rawText,
                        subrole: banner.subrole
                    ),
                    banner.textChildren
                )
            }
        }
        secondReadOwed = needsSecondRead
        secondReadRetries = 0
        if needsSecondRead { scheduleScan(after: Self.secondReadDelay) }
    }

    /// Diagnostics go to the unified log, readable with:
    ///
    ///     /usr/bin/log show --last 30m --predicate 'subsystem == "com.jamiewhite.signalladder"'
    ///
    /// (`log` is a zsh builtin; the absolute path is required.)
    ///
    /// This used to write to stderr, on the assumption that a
    /// LaunchServices-started .app had its stderr captured by the unified log.
    /// It does not: a live run produced notification-subsystem entries for this
    /// app and not one line from here, so every diagnostic the watcher emitted
    /// went nowhere. Diagnosing the first real failure meant reading Apple's
    /// logs instead of ours.
    ///
    /// Messages are `%{public}s` so they are readable without a debug profile —
    /// which is safe only because notification content never passes through
    /// here. That constraint is now load-bearing rather than advisory: pass a
    /// pid, a subrole, or a count, never a notification's text.
    private func log(_ message: String) {
        os_log(.default, log: Self.logger, "%{public}s", message)
    }

    private static let logger = OSLog(subsystem: "com.jamiewhite.signalladder", category: "watcher")
}
