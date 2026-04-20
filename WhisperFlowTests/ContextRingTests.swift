@testable import WhisperFlow
import XCTest

final class ContextRingTests: XCTestCase {

    func testAddWordAccumulatesText() {
        var ring = ContextRing()
        ring.add(Word(text: "hello", start: 0, end: 0.3))
        ring.add(Word(text: "world", start: 0.3, end: 0.6))
        XCTAssertEqual(ring.text, "hello world")
        XCTAssertEqual(ring.wordCount, 2)
    }

    func testWindowTrimsOldWords() {
        var ring = ContextRing(windowSize: 5.0)
        ring.add(Word(text: "old", start: 0, end: 0.5))
        ring.add(Word(text: "new", start: 10, end: 10.5))

        XCTAssertEqual(ring.text, "new")
        XCTAssertEqual(ring.wordCount, 1)
    }

    func testLastWordTimeReturnsLatest() {
        var ring = ContextRing()
        XCTAssertNil(ring.lastWordTime)

        ring.add(Word(text: "first", start: 0, end: 0.3))
        ring.add(Word(text: "second", start: 1, end: 1.5))

        XCTAssertEqual(ring.lastWordTime, 1.5)
    }

    func testLastOtherUtteranceFiltersBySpeaker() {
        var ring = ContextRing()
        ring.add(Word(text: "I", start: 0, end: 0.2, speaker: .selfSpeaker))
        ring.add(Word(text: "hey", start: 0.5, end: 0.8, speaker: .other))
        ring.add(Word(text: "yeah", start: 1, end: 1.2, speaker: .selfSpeaker))

        XCTAssertEqual(ring.lastOtherUtterance(), 0.8)
    }

    func testLastOtherUtteranceNilWithoutOtherSpeaker() {
        var ring = ContextRing()
        ring.add(Word(text: "hello", start: 0, end: 0.3, speaker: .selfSpeaker))
        XCTAssertNil(ring.lastOtherUtterance())
    }

    func testClearRemovesAllWords() {
        var ring = ContextRing()
        ring.add(Word(text: "hello", start: 0, end: 0.3))
        ring.clear()

        XCTAssertEqual(ring.wordCount, 0)
        XCTAssertEqual(ring.text, "")
        XCTAssertNil(ring.lastWordTime)
    }

    func testCustomWindowSize() {
        var ring = ContextRing(windowSize: 2.0)
        ring.add(Word(text: "a", start: 0, end: 0.5))
        ring.add(Word(text: "b", start: 1, end: 1.5))
        ring.add(Word(text: "c", start: 3, end: 3.5))

        // cutoff = 3.5 - 2.0 = 1.5; "a" (end 0.5) removed, "b" (end 1.5) kept
        XCTAssertEqual(ring.text, "b c")
    }

    func testAllWordsWithinWindowRetained() {
        var ring = ContextRing(windowSize: 20.0)
        for i in 0..<10 {
            let t = Double(i) * 0.5
            ring.add(Word(text: "w\(i)", start: t, end: t + 0.3))
        }
        XCTAssertEqual(ring.wordCount, 10)
    }

    func testDefaultWindowSizeIs20Seconds() {
        let ring = ContextRing()
        XCTAssertEqual(ring.windowSize, 20.0)
    }

    func testEmptyRingHasEmptyText() {
        let ring = ContextRing()
        XCTAssertEqual(ring.text, "")
        XCTAssertEqual(ring.wordCount, 0)
    }
}
