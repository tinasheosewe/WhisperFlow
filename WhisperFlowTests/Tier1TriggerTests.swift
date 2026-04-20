@testable import WhisperFlow
import XCTest

final class Tier1TriggerTests: XCTestCase {

    func testDoesNotFireWithoutWords() {
        let trigger = Tier1Trigger()
        XCTAssertFalse(trigger.shouldFire(now: 5.0, lastWordTime: nil, wordCount: 0))
    }

    func testDoesNotFireDuringShortPause() {
        let trigger = Tier1Trigger()
        // 0.5s pause — needs >= 0.8s (minUserSilent)
        XCTAssertFalse(trigger.shouldFire(now: 5.0, lastWordTime: 4.5, wordCount: 5))
    }

    func testFiresAfterSufficientPauseAndWords() {
        let trigger = Tier1Trigger()
        // 1.0s pause, 5 new words (>= 4), no cooldown history
        XCTAssertTrue(trigger.shouldFire(now: 5.0, lastWordTime: 4.0, wordCount: 5))
    }

    func testCooldownPreventsRapidFiring() {
        var trigger = Tier1Trigger()
        XCTAssertTrue(trigger.shouldFire(now: 5.0, lastWordTime: 4.0, wordCount: 5))
        trigger.markFired(at: 5.0, wordCount: 5)

        // 1s later — within 3s cooldown
        XCTAssertFalse(trigger.shouldFire(now: 6.0, lastWordTime: 5.0, wordCount: 10))
    }

    func testFiresAgainAfterCooldown() {
        var trigger = Tier1Trigger()
        XCTAssertTrue(trigger.shouldFire(now: 5.0, lastWordTime: 4.0, wordCount: 5))
        trigger.markFired(at: 5.0, wordCount: 5)

        // 4s later (> 3s cooldown), 5 new words
        XCTAssertTrue(trigger.shouldFire(now: 9.0, lastWordTime: 8.0, wordCount: 10))
    }

    func testRequiresMinimumNewWords() {
        var trigger = Tier1Trigger()
        trigger.markFired(at: 2.0, wordCount: 5)

        // Enough time, long pause, but only 2 new words (< 4)
        XCTAssertFalse(trigger.shouldFire(now: 10.0, lastWordTime: 9.0, wordCount: 7))
    }

    func testCustomConfig() {
        let trigger = Tier1Trigger(config: .init(
            minPause: 1.0,
            minUserSilent: 2.0,
            cooldown: 5.0,
            minNewWords: 2
        ))

        // 1.5s pause — enough for minPause, not enough for minUserSilent
        XCTAssertFalse(trigger.shouldFire(now: 5.0, lastWordTime: 3.5, wordCount: 3))
        // 2.5s pause — enough for both
        XCTAssertTrue(trigger.shouldFire(now: 5.0, lastWordTime: 2.5, wordCount: 3))
    }

    func testReset() {
        var trigger = Tier1Trigger()
        trigger.markFired(at: 5.0, wordCount: 10)
        trigger.reset()

        // Should fire immediately after reset
        XCTAssertTrue(trigger.shouldFire(now: 6.0, lastWordTime: 5.0, wordCount: 4))
    }

    func testDefaultConfig() {
        let config = Tier1Trigger.Config.default
        XCTAssertEqual(config.minPause, 0.5)
        XCTAssertEqual(config.minUserSilent, 0.8)
        XCTAssertEqual(config.cooldown, 3.0)
        XCTAssertEqual(config.minNewWords, 4)
    }

    func testExactBoundaryMinPause() {
        let trigger = Tier1Trigger(config: .init(
            minPause: 0.5,
            minUserSilent: 0.5,
            cooldown: 0,
            minNewWords: 1
        ))
        // Exactly 0.5s pause — should fire (>= not >)
        XCTAssertTrue(trigger.shouldFire(now: 1.5, lastWordTime: 1.0, wordCount: 1))
    }
}
