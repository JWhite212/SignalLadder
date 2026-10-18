// Sources/NotificationCore/SelfTestLedger.swift
import Foundation

/// What the self-tests have shown so far, and what each new result does to it (#98).
///
/// It was six fields of `AppDelegate`, decided in the untested target. The app keeps its
/// timers and carries out the one thing a result asks of them, a retry or its cancelling;
/// everything that decides is here. Health reads it through `HealthInputs`.
public struct SelfTestLedger: Equatable, Sendable {
    /// nil when no self-test has completed; 0 when the last one succeeded; otherwise the
    /// number of failures in a row.
    public private(set) var consecutiveFailures: Int?

    /// Whether the last failed self-test saw no accessibility events at all, meaning its
    /// banner was never drawn and capture was never exercised.
    public private(set) var failedWithNoBannerActivity = false

    /// The capture count when the last self-test ran. Real traffic arriving since then is
    /// positive evidence the capture path works, which is what lets a failed self-test be
    /// attributed rather than left ambiguous.
    public private(set) var captureCountAtLastRun = 0

    /// When a self-test last succeeded. Health says how old this is, and stops calling it
    /// "verified" once a self-test that should have run has not.
    public private(set) var lastSucceededAt: Date?

    /// How long the next retry of a failed self-test waits. It backs off towards the normal
    /// cadence, so a long Focus does not mean a self-test notification every minute all
    /// evening (`SelfTestPlan.nextRetryDelay`).
    public private(set) var retryDelay: TimeInterval = SelfTestPlan.firstRetryDelay

    public init() {}

    /// What a result asks of the app's retry timer.
    public enum Retry: Equatable, Sendable {
        /// Arm a retry, waiting `takeRetryDelay(onCall:)`.
        case schedule
        /// Cancel any retry, and start the back-off afresh (`retryCancelled()`).
        case cancel
    }

    /// The token a run hands back to `finish`, so a run that did not happen can put the
    /// count back as it was.
    public struct Run: Equatable, Sendable {
        let captureCountBefore: Int
    }

    /// A self-test is about to be asked for: the capture count is taken now, before the
    /// round trip, so captures during it count as traffic since it.
    public mutating func begin(captureCount: Int) -> Run {
        defer { captureCountAtLastRun = captureCount }
        return Run(captureCountBefore: captureCountAtLastRun)
    }

    /// What came of the run `begin` started.
    ///
    /// - nil: none ran. One was already under way, or posting failed. The one under way
    ///   set its own count, so this one must not move it, and a retry keeps a clearing
    ///   from being spent on nothing; if one was under way, its own result replaces the retry.
    /// - true: it succeeded, now. The retry is cancelled.
    /// - false: it failed, and `bannerActivity` says whether Notification Centre drew
    ///   anything during it; with none, the alert was suppressed and the failure says
    ///   nothing about capture. It is retried.
    public mutating func finish(_ run: Run, result: Bool?, bannerActivity: Bool, at now: Date) -> Retry {
        guard let succeeded = result else {
            captureCountAtLastRun = run.captureCountBefore
            return .schedule
        }
        consecutiveFailures = succeeded ? 0 : (consecutiveFailures ?? 0) + 1
        if succeeded { lastSucceededAt = now }
        failedWithNoBannerActivity = !succeeded && !bannerActivity
        return succeeded ? .cancel : .schedule
    }

    /// The wait for the retry being armed now, and the back-off moved on for the next one.
    public mutating func takeRetryDelay(onCall: Bool) -> TimeInterval {
        defer { retryDelay = SelfTestPlan.nextRetryDelay(after: retryDelay, onCall: onCall) }
        return retryDelay
    }

    /// The retry is cancelled, or a self-test follows a block: the back-off starts afresh.
    /// Only then: resetting on every run would retry a long Focus every minute.
    public mutating func retryCancelled() {
        retryDelay = SelfTestPlan.firstRetryDelay
    }

    /// How long ago a self-test last succeeded, or nil for never.
    public func secondsSinceLastSuccess(at now: Date) -> TimeInterval? {
        lastSucceededAt.map { now.timeIntervalSince($0) }
    }

    /// Captures since the last self-test was asked for.
    public func capturesSinceLastRun(captureCount: Int) -> Int {
        captureCount - captureCountAtLastRun
    }
}
