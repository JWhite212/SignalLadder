import XCTest
import UserNotifications
@testable import NotificationCapture

/// The self-test's own bookkeeping. Notification Centre is never asked for
/// anything: a post is held open until the test lets it go, so a capture and a
/// second self-test can be ordered around it.
@MainActor
final class CanaryServiceTests: XCTestCase {
    /// Holds every post open until `releaseAll`, and keeps what was posted.
    private final class HeldPosts {
        var posted: [UNNotificationRequest] = []
        private var held: [CheckedContinuation<Void, Never>] = []

        func post(_ request: UNNotificationRequest) async {
            posted.append(request)
            await withCheckedContinuation { held.append($0) }
        }

        func releaseAll() {
            let released = held
            held = []
            released.forEach { $0.resume() }
        }
    }

    private func settle() async {
        for _ in 0..<50 { await Task.yield() }
    }

    private func words(_ result: Bool?) -> String {
        result.map { $0 ? "passed" : "failed" } ?? "did not run"
    }

    func testASelfTestWhoseBannerIsCapturedPasses() async {
        let posts = HeldPosts()
        let canary = CanaryService(post: { await posts.post($0) }, removeDelivered: { _ in })
        let run = Task { @MainActor in await canary.run(timeout: 2) }
        await settle()
        let marker = posts.posted.first?.content.body ?? ""
        XCTAssertTrue(canary.noteCapture(rawText: "", textChildren: ["SignalLadder Self-Test", marker]))
        posts.releaseAll()
        let result = await run.value
        XCTAssertEqual(words(result), "passed")
    }

    func testASelfTestWhoseBannerIsNeverCapturedFails() async {
        let posts = HeldPosts()
        let canary = CanaryService(post: { await posts.post($0) }, removeDelivered: { _ in })
        let run = Task { @MainActor in await canary.run(timeout: 0.2) }
        await settle()
        posts.releaseAll()
        let result = await run.value
        XCTAssertEqual(words(result), "failed")
    }

    /// A capture can come back while the post is still out, which clears the
    /// marker. A second self-test asked for then must not start: it reset what
    /// the first had seen, and the first never returned, or failed a capture
    /// that had worked (found on 2026-10-16).
    func testASecondSelfTestWhileTheFirstsPostIsOutDoesNotRun() async {
        let posts = HeldPosts()
        let canary = CanaryService(post: { await posts.post($0) }, removeDelivered: { _ in })
        var first = "still waiting", second = "still waiting"
        let firstDone = expectation(description: "the first self-test returns")
        let secondDone = expectation(description: "the second self-test returns")

        Task { @MainActor in first = self.words(await canary.run(timeout: 0.3)); firstDone.fulfill() }
        await settle()
        XCTAssertEqual(posts.posted.count, 1)
        let marker = posts.posted[0].content.body
        XCTAssertTrue(canary.noteCapture(rawText: marker))

        Task { @MainActor in second = self.words(await canary.run(timeout: 0.3)); secondDone.fulfill() }
        await settle()
        posts.releaseAll()
        await settle()
        posts.releaseAll()

        await fulfillment(of: [firstDone, secondDone], timeout: 3)
        XCTAssertEqual(first, "passed")
        XCTAssertEqual(second, "did not run")
        XCTAssertEqual(posts.posted.count, 1, "the second self-test posted a marker of its own")
    }

    /// Once a self-test has returned, the next one runs.
    func testASelfTestAfterOneHasReturnedRuns() async {
        let posts = HeldPosts()
        let canary = CanaryService(post: { await posts.post($0) }, removeDelivered: { _ in })
        let firstRun = Task { @MainActor in await canary.run(timeout: 0.2) }
        await settle()
        posts.releaseAll()
        _ = await firstRun.value
        let secondRun = Task { @MainActor in await canary.run(timeout: 0.2) }
        await settle()
        posts.releaseAll()
        let second = await secondRun.value
        XCTAssertEqual(words(second), "failed")
        XCTAssertEqual(posts.posted.count, 2)
    }
}
