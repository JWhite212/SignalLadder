import XCTest
@testable import NotificationCore

/// How many rules play a sound that is saved over, counted over the rules in effect and the draft in the rule editor, which
/// may name it before it is saved (sound editor plan, Ruling 9).
final class SoundUseDraftTests: XCTestCase {
    private func rule(id: UUID = UUID(), _ sound: String?) -> Rule {
        Rule(id: id, name: "R", condition: .field(.app, .equals, "x"), isEnabled: true,
             alert: sound.map { .sound(name: $0, gainDB: 0) })
    }

    func testARuleInBothTheSavedRulesAndTheDraftIsCountedOnce() {
        let shared = UUID()
        XCTAssertEqual(SoundUse.count(naming: "Alarm", inSaved: [rule(id: shared, "Alarm")], andDraft: [rule(id: shared, "Alarm")]), 1)
    }

    func testARuleTheDraftHasChangedToNameItIsCountedBecauseSavingWouldPlayIt() {
        let id = UUID()
        XCTAssertEqual(SoundUse.count(naming: "Alarm", inSaved: [rule(id: id, "Glass")], andDraft: [rule(id: id, "Alarm")]), 1)
    }

    func testARuleInEffectThatTheDraftHasChangedToNameAnotherSoundIsStillCountedBecauseItPlaysItNow() {
        let id = UUID()
        XCTAssertEqual(SoundUse.count(naming: "Alarm", inSaved: [rule(id: id, "Alarm")], andDraft: [rule(id: id, "Glass")]), 1)
    }

    func testARuleOnlyInTheDraftAndARuleOnlyInEffectAreBothCounted() {
        XCTAssertEqual(SoundUse.count(naming: "Alarm", inSaved: [rule("Alarm")], andDraft: [rule("Alarm")]), 2)
    }

    func testNoRulesNameNothing() {
        XCTAssertEqual(SoundUse.count(naming: "Alarm", inSaved: [], andDraft: []), 0)
        XCTAssertEqual(SoundUse.count(naming: "Alarm", inSaved: [rule("Glass")], andDraft: [rule(nil)]), 0)
    }
}
