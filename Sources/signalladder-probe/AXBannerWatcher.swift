// Sources/signalladder-probe/AXBannerWatcher.swift
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
final class AXBannerWatcher {
    private let bundleID = "com.apple.notificationcenterui"
    private let locator = BannerTreeLocator()
    private let onCapture: (RawCapture, [String]) -> Void

    private var observer: AXObserver?
    private var appElement: AXUIElement?
    private var processSource: DispatchSourceProcess?
    private var reattachDelay: TimeInterval = 1.0

    init(onCapture: @escaping (RawCapture, [String]) -> Void) {
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
    func start() {
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
        log("attached to notificationcenterui pid=\(pid)")

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

    /// Exponential backoff, capped, so a permanently-absent process does not spin.
    private func scheduleReattach() {
        let delay = reattachDelay
        reattachDelay = min(reattachDelay * 2, 30)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.attach()
        }
    }

    private func observeWorkspace() {
        // Kept as a SECONDARY signal only. It does not fire in this CLI probe
        // — verified by live testing — but will work once this runs inside a
        // real .app bundle, and costs nothing meanwhile. The DispatchSource in
        // attach() is the primary, process-type-independent detector. Two
        // independent paths, neither trusted alone.
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let self,
                      let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.bundleIdentifier == self.bundleID
                else { return }
                self.log("notificationcenterui lifecycle event; re-attaching")
                self.attach()
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

    private func log(_ message: String) {
        FileHandle.standardError.write("[watcher] \(message)\n".data(using: .utf8)!)
    }
}
