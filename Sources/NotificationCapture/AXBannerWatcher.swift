// Sources/NotificationCapture/AXBannerWatcher.swift
import Foundation
import ApplicationServices
import AppKit
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
    private let locator = BannerTreeLocator()
    private let onCapture: (RawCapture, [String]) -> Void

    /// Fired after a successful attach. Re-attaching is precisely when capture
    /// most needs re-proving, since the process it observes has just restarted.
    public var onAttach: (() -> Void)?

    private var observer: AXObserver?
    private var appElement: AXUIElement?
    private var processSource: DispatchSourceProcess?
    private var pendingReattach: DispatchWorkItem?
    private var reattachDelay: TimeInterval = 1.0

    /// Whether an observer is currently registered. Feeds the health model —
    /// an unattached watcher captures nothing, whatever else is healthy.
    public var isAttached: Bool { observer != nil }

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

        let callback: AXObserverCallback = { _, element, _, refcon in
            guard let refcon else { return }
            let watcher = Unmanaged<AXBannerWatcher>.fromOpaque(refcon).takeUnretainedValue()
            watcher.handle(element: element)
        }

        guard AXObserverCreate(pid, callback, &created) == .success, let created else {
            log("AXObserverCreate failed for pid \(pid)")
            scheduleReattach()
            return
        }

        let element = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        // Only the window notifications actually drive capture. Destruction is
        // registered opportunistically for future use, so failing to get it
        // must not push the watcher into permanent backoff with zero captures.
        let required = [
            kAXWindowCreatedNotification,
            kAXWindowMovedNotification,
        ]
        let optional = [
            kAXUIElementDestroyedNotification,
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
                log("optional AXObserverAddNotification(\(name)) failed: \(err.rawValue) — continuing")
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
        for name in [kAXWindowCreatedNotification, kAXWindowMovedNotification, kAXUIElementDestroyedNotification] {
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

    private func handle(element: AXUIElement) {
        // The callback carries no payload, so content must be read by walking
        // the tree from the element we were handed. A banner's text lives in
        // its children's AXValue, not in its own description — so a banner is
        // worth emitting if EITHER source has content.
        //
        // Requiring a description would drop a banner whose children are fully
        // populated, and would make the partial-blindness case (banners
        // present, descriptions empty) look identical to an idle system. That
        // case is the one this whole project is built to detect, so it is
        // logged loudly rather than skipped quietly.
        let banners = locator.locate(in: AXElementNode(element))
        for banner in banners {
            let text = banner.attributedDescription ?? ""
            let children = BannerTextReader.textChildren(of: banner)

            guard !text.isEmpty || !children.isEmpty else {
                log("matched banner subrole=\(banner.subrole ?? "?") with no description AND no text children — possible partial blindness")
                continue
            }

            onCapture(
                RawCapture(
                    timestamp: Date(),
                    rawText: text,
                    subrole: banner.subrole ?? ""
                ),
                children
            )
        }
    }

    /// Writes to stderr. In a LaunchServices-started .app this is captured by
    /// the unified log and PERSISTED TO DISK — unlike the CLI probe, where it
    /// is ephemeral. Never pass notification content through here.
    private func log(_ message: String) {
        FileHandle.standardError.write("[watcher] \(message)\n".data(using: .utf8)!)
    }
}
