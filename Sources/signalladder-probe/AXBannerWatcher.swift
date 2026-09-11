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

        let notifications = [
            kAXWindowCreatedNotification,
            kAXWindowMovedNotification,
            kAXUIElementDestroyedNotification,
        ]

        var registrationFailed = false
        for name in notifications {
            let err = AXObserverAddNotification(created, element, name as CFString, refcon)
            if err != .success {
                log("AXObserverAddNotification(\(name)) failed: \(err.rawValue)")
                registrationFailed = true
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
    }

    private func detach() {
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
        // the tree from the element we were handed. The banner's text lives in
        // its children's AXValue, not in its own description.
        let banners = locator.locate(in: AXElementNode(element))
        for banner in banners {
            guard let text = banner.attributedDescription, !text.isEmpty else { continue }
            onCapture(
                RawCapture(
                    timestamp: Date(),
                    rawText: text,
                    subrole: banner.subrole ?? ""
                ),
                BannerTextReader.textChildren(of: banner)
            )
        }
    }

    private func log(_ message: String) {
        FileHandle.standardError.write("[watcher] \(message)\n".data(using: .utf8)!)
    }
}
