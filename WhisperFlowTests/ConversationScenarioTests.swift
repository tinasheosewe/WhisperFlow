@testable import WhisperFlow
import XCTest

/// Scenario tests that replay realistic conversation patterns through the pipeline.
/// Tests overall system behavior — robust to internal refactoring.
final class ConversationScenarioTests: XCTestCase {

    /// Simulates the Phase 0 sample conversation (~36s casual chat about relocating).
    /// Verifies that the pipeline fires at the right moments and produces appropriate emissions.
    func testRelocatingConversationScenario() async throws {
        // Gate: NO for greetings, YES for personal moments, NO for factual, YES for vulnerability, NO for wrap-up
        let llm = MockLLMService(
            gateResults: [false, true, false, true, false],
            angleResults: [
                AngleResult(topic: "starting over", angles: ["culture shock", "fresh start"]),
                AngleResult(topic: "loneliness", angles: ["homesick", "Austin roots"]),
            ]
        )
        let orchestrator = PipelineOrchestrator(llmService: llm)
        var emissions: [Emission] = []

        // Phase 1: Greetings (0–4s)
        await orchestrator.addWords(makeWords([
            ("Hey", 0, 0.3), ("how's", 0.3, 0.6), ("it", 0.6, 0.7), ("going", 0.7, 1.0),
        ]))
        if let e = try await orchestrator.tick(at: 4.0) { emissions.append(e) }

        // Phase 2: Personal share — "moved here last year, it's been a lot" (4.5–6.8s)
        await orchestrator.addWords(makeWords([
            ("Yeah", 4.5, 4.8), ("same", 4.8, 5.1), ("I", 5.1, 5.2),
            ("actually", 5.2, 5.6), ("just", 5.6, 5.8), ("moved", 5.8, 6.1),
            ("here", 6.1, 6.3), ("last", 6.3, 6.6), ("year", 6.6, 6.8),
        ]))
        if let e = try await orchestrator.tick(at: 8.5) { emissions.append(e) }

        // Phase 3: Details — "it's been a lot" (9–9.7s)
        await orchestrator.addWords(makeWords([
            ("it's", 9.0, 9.2), ("been", 9.2, 9.4), ("a", 9.4, 9.5), ("lot", 9.5, 9.7),
        ]))
        if let e = try await orchestrator.tick(at: 15.7) { emissions.append(e) }

        // Phase 4: Vulnerability — "hardest part is not knowing anyone" (16–17.7s)
        await orchestrator.addWords(makeWords([
            ("The", 16.0, 16.2), ("hardest", 16.2, 16.5), ("part", 16.5, 16.7),
            ("is", 16.7, 16.8), ("not", 16.8, 17.0), ("knowing", 17.0, 17.3),
            ("anyone", 17.3, 17.7),
        ]))
        if let e = try await orchestrator.tick(at: 22.7) { emissions.append(e) }

        // Phase 5: Work stress (23–23.9s)
        await orchestrator.addWords(makeWords([
            ("work", 23.0, 23.2), ("has", 23.2, 23.4),
            ("been", 23.4, 23.6), ("crazy", 23.6, 23.9),
        ]))
        if let e = try await orchestrator.tick(at: 31.2) { emissions.append(e) }

        // Verify: gate called at every pause detection point
        let gateCount = await llm.gateCallCount
        XCTAssertEqual(gateCount, 5, "Gate should evaluate at every pause point")

        // Verify: exactly 2 emissions (where gate returned YES)
        XCTAssertEqual(emissions.count, 2, "Should produce 2 emissions for 2 gate passes")

        // Verify: angles were generated only for passed gates
        let angleCount = await llm.angleCallCount
        XCTAssertEqual(angleCount, 2)

        // Verify: emission structure is correct
        XCTAssertEqual(emissions[0].topic, "starting over")
        XCTAssertEqual(emissions[0].angles, ["culture shock", "fresh start"])
        XCTAssertEqual(emissions[1].topic, "loneliness")
        XCTAssertEqual(emissions[1].angles, ["homesick", "Austin roots"])
    }

    /// Verifies continuous speech (no pauses) produces zero emissions.
    func testContinuousSpeechNoEmissions() async throws {
        let llm = MockLLMService()
        let orchestrator = PipelineOrchestrator(llmService: llm)

        // 20 words back-to-back, no gaps
        var words: [Word] = []
        for i in 0..<20 {
            let start = Double(i) * 0.3
            words.append(Word(text: "word\(i)", start: start, end: start + 0.25))
        }
        await orchestrator.addWords(words)

        // Tick right after last word — only 0.05s pause
        let emission = try await orchestrator.tick(at: 6.05)
        XCTAssertNil(emission)

        let gateCount = await llm.gateCallCount
        XCTAssertEqual(gateCount, 0, "LLM should never be called during continuous speech")
    }

    /// Silence with no words should not trigger anything.
    func testPureSilenceNoTrigger() async throws {
        let llm = MockLLMService()
        let orchestrator = PipelineOrchestrator(llmService: llm)

        let emission = try await orchestrator.tick(at: 30.0)
        XCTAssertNil(emission)
    }

    /// Short utterance (< 4 words) followed by a long pause should not trigger.
    func testTooFewWordsNoTrigger() async throws {
        let llm = MockLLMService()
        let orchestrator = PipelineOrchestrator(llmService: llm)

        await orchestrator.addWords(makeWords([
            ("Hi", 0, 0.2), ("there", 0.2, 0.5),
        ]))

        // Long pause but only 2 words
        let emission = try await orchestrator.tick(at: 5.0)
        XCTAssertNil(emission)
    }

    /// All gates reject — zero emissions even with many pauses.
    func testAllGatesRejectNoEmissions() async throws {
        let llm = MockLLMService(gateResults: [false])
        let orchestrator = PipelineOrchestrator(llmService: llm)

        // Three batches with pauses
        for batch in 0..<3 {
            let offset = Double(batch) * 5.0
            await orchestrator.addWords(makeWords([
                ("word1", offset, offset + 0.2), ("word2", offset + 0.2, offset + 0.4),
                ("word3", offset + 0.4, offset + 0.6), ("word4", offset + 0.6, offset + 0.8),
            ]))
            let emission = try await orchestrator.tick(at: offset + 2.0)
            XCTAssertNil(emission)
        }

        let gateCount = await llm.gateCallCount
        XCTAssertEqual(gateCount, 3, "Gate should be called at each pause")
        let angleCount = await llm.angleCallCount
        XCTAssertEqual(angleCount, 0, "No angles should be generated when gate always rejects")
    }

    /// Words trickle in one at a time (realistic STT behavior).
    func testIncrementalWordArrival() async throws {
        let llm = MockLLMService()
        let orchestrator = PipelineOrchestrator(llmService: llm)

        // Words arrive individually, not in batches
        let words = makeWords([
            ("I", 0, 0.2), ("just", 0.2, 0.4), ("moved", 0.4, 0.6),
            ("here", 0.6, 0.8), ("last", 0.8, 1.0), ("year", 1.0, 1.2),
        ])

        for word in words {
            await orchestrator.addWords([word])
        }

        let emission = try await orchestrator.tick(at: 2.2)
        XCTAssertNotNil(emission, "Pipeline should work with words arriving one at a time")
    }

    // MARK: - Helpers

    private func makeWords(_ data: [(String, Double, Double)]) -> [Word] {
        data.map { Word(text: $0.0, start: $0.1, end: $0.2) }
    }
}
