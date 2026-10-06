import XCTest
@testable import NotificationCore

/// The two things an Inspector row used to build for itself, now in the core
/// (M5 plan, Ruling 18): its context line and the symbol beside its alert line.
/// What each returns is what the view returned before it moved, which is what
/// these hold: the expected strings are the ones the view typed.
final class InspectorRowTextTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - The context line

    func testTheContextLineCountsTheNotificationsOfTheLastHour() {
        XCTAssertEqual(InspectorRowText.context(ContextSnapshot(date: t0, recentCountForApp: 3)), "3 in the last hour")
        XCTAssertEqual(InspectorRowText.context(ContextSnapshot(date: t0, recentCountForApp: 1)), "1 in the last hour")
        XCTAssertEqual(InspectorRowText.context(ContextSnapshot(date: t0, recentCountForApp: 40)), "40 in the last hour")
    }

    func testTheContextLineReadsAsAFloorWhenTheBufferOverflowed() {
        let overflowed = ContextSnapshot(date: t0, recentCountForApp: 3, recentCountIsUnderCounted: true)
        XCTAssertEqual(InspectorRowText.context(overflowed), "3+ in the last hour")
        XCTAssertEqual(InspectorRowText.context(ContextSnapshot(date: t0, recentCountForApp: 200,
                                                                recentCountIsUnderCounted: true)),
                       "200+ in the last hour")
    }

    // MARK: - The alert's symbol

    func testASoundThatPlayedWhereItCanBeHeardIsASpeaker() {
        XCTAssertEqual(InspectorRowText.symbol(.played(sound: "Glass", gainDB: 0, outputSilent: false)), "speaker.wave.2")
        XCTAssertEqual(InspectorRowText.symbol(.played(sound: "Glass", gainDB: 6, outputSilent: false)), "speaker.wave.2",
                       "the gain does not change it")
    }

    func testSpeechThatWasSaidWhereItCanBeHeardIsAWaveform() {
        XCTAssertEqual(InspectorRowText.symbol(.spoke(text: "x", voice: "Daniel", gainDB: 0, outputSilent: false)),
                       "waveform")
        XCTAssertEqual(InspectorRowText.symbol(.playedAndSpoke(sound: "Glass", soundGainDB: 0, text: "x", voice: "Daniel",
                                                               speechGainDB: 0, outputSilent: false)),
                       "waveform", "a sound and speech together read as speech")
    }

    func testAnyAlertIntoAnOutputNobodyCouldHearIsASlashedSpeaker() {
        XCTAssertEqual(InspectorRowText.symbol(.played(sound: "Glass", gainDB: 0, outputSilent: true)), "speaker.slash")
        XCTAssertEqual(InspectorRowText.symbol(.spoke(text: "x", voice: "Daniel", gainDB: 0, outputSilent: true)),
                       "speaker.slash")
        XCTAssertEqual(InspectorRowText.symbol(.playedAndSpoke(sound: "Glass", soundGainDB: 0, text: "x", voice: "Daniel",
                                                               speechGainDB: 0, outputSilent: true)),
                       "speaker.slash")
    }

    func testSilenceTheRuleChoseAndNoAlertAtAllHaveTheirOwnSymbols() {
        XCTAssertEqual(InspectorRowText.symbol(.silentByRule), "moon")
        XCTAssertEqual(InspectorRowText.symbol(.noAlertSet), "speaker")
    }

    func testAMatchASnoozeHeldIsAMoonWithSleepMarks() {
        XCTAssertEqual(InspectorRowText.symbol(.snoozed), "moon.zzz")
    }

    func testAMatchThatJoinedAnEscalationAndStayedSilentIsAMergingArrowWhateverItsNumber() {
        XCTAssertEqual(InspectorRowText.symbol(.joinedEscalation(matchNumber: 2)), "arrow.triangle.merge")
        XCTAssertEqual(InspectorRowText.symbol(.joinedEscalation(matchNumber: 40)), "arrow.triangle.merge")
    }

    func testTheSilentJoinTheHeldMatchSilenceByRuleNoAlertAFailureAndAPlayedAlertAreAllDrawnDifferently() {
        // The silent join and the held match are told apart at a glance, and
        // neither is mistaken for silence the rule chose or for a failure. One
        // outcome for each glyph `symbol(_:)` returns today, so no two of these
        // may share one. It does not say that no other two outcomes do: a
        // sound and speech together read as speech, and every failure is a
        // triangle, as the tests around it say.
        let symbols: [String] = [
            InspectorRowText.symbol(.joinedEscalation(matchNumber: 2)),
            InspectorRowText.symbol(.snoozed),
            InspectorRowText.symbol(.silentByRule),
            InspectorRowText.symbol(.noAlertSet),
            InspectorRowText.symbol(.failed("x")),
            InspectorRowText.symbol(.played(sound: "Glass", gainDB: 0, outputSilent: false)),
            InspectorRowText.symbol(.spoke(text: "x", voice: "Daniel", gainDB: 0, outputSilent: false)),
            InspectorRowText.symbol(.played(sound: "Glass", gainDB: 0, outputSilent: true)),
        ]
        XCTAssertEqual(Set(symbols).count, symbols.count, "\(symbols)")
    }

    func testEveryFailureIsAWarningTriangleWhateverTheOutputWas() {
        let failures: [AlertOutcome] = [
            .failed("sound was not found"),
            .couldNotSpeak("voice not installed"),
            .playedButNotSpoken(sound: "Glass", gainDB: 0, reason: "x", outputSilent: false),
            .playedButNotSpoken(sound: "Glass", gainDB: 0, reason: "x", outputSilent: true),
            .spokeButNotPlayed(text: "x", voice: "Daniel", gainDB: 0, reason: "x", outputSilent: false),
            .spokeButNotPlayed(text: "x", voice: "Daniel", gainDB: 0, reason: "x", outputSilent: true),
        ]
        for failure in failures {
            XCTAssertEqual(InspectorRowText.symbol(failure), "exclamationmark.triangle", "\(failure)")
        }
    }
}
