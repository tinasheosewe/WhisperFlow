@testable import WhisperFlow
import XCTest

/// Integration tests for PipelineOrchestrator — verifies the Tier1 → Tier2 → Emission
/// pipeline with mock LLM. Tests behavior, not implementation details.
final class PipelineOrchestratorTests: XCTestCase {

    // MARK: - Basic Pipeline Behavior

    func testNoEmissionWithoutWords() async throws {
        let orchestrator = PipelineOrchestrator(llmService: MockLLMService())

        let emission = try await orchestrator.tick(at: 5.0)
        XCTAssertNil(emission)
    }

    func testEmissionAfterWordsAndPause() async throws {
        let llm = MockLLMService(
            angleResults: [AngleResult(topic: "relocation", angles: ["culture shock", "fresh start"])]
        )
        let orchestrator = PipelineOrchestrator(llmService: llm)

        await orchestrator.addWords([
            Word(text: "I", start: 0, end: 0.2),
            Word(text: "just", start: 0.2, end: 0.4),
            Word(text: "moved", start: 0.4, end: 0.6),
            Word(text: "here", start: 0.6, end: 0.8),
        ])

        // 1.0s after last word — sufficient pause
        let emission = try await orchestrator.tick(at: 1.8)
        XCTAssertNotNil(emission)
        XCTAssertEqual(emission?.topic, "relocation")
        XCTAssertEqual(emission?.angles, ["culture shock", "fresh start"])
    }

    func testGateRejectionProducesNoEmission() async throws {
        let llm = MockLLMService(gateResults: [false])
        let orchestrator = PipelineOrchestrator(llmService: llm)

        await orchestrator.addWords(fourWords(startingAt: 0))

        let emission = try await orchestrator.tick(at: 1.8)
        XCTAssertNil(emission)

        // Gate was called but angles were not
        let gateCount = await llm.gateCallCount
        let angleCount = await llm.angleCallCount
        XCTAssertEqual(gateCount, 1)
        XCTAssertEqual(angleCount, 0)
    }

    func testNoEmissionDuringContinuousSpeech() async throws {
        let llm = MockLLMService()
        let orchestrator = PipelineOrchestrator(llmService: llm)

        // Words with no gap
        await orchestrator.addWords([
            Word(text: "just", start: 0, end: 0.3),
            Word(text: "talking", start: 0.3, end: 0.6),
            Word(text: "nonstop", start: 0.6, end: 0.9),
            Word(text: "here", start: 0.9, end: 1.2),
        ])

        // Only 0.3s since last word — insufficient pause
        let emission = try await orchestrator.tick(at: 1.5)
        XCTAssertNil(emission)

        let gateCount = await llm.gateCallCount
        XCTAssertEqual(gateCount, 0, "LLM should not be called when Tier 1 doesn't fire")
    }

    // MARK: - Cooldown & Multiple Emissions

    func testCooldownPreventsRapidEmissions() async throws {
        let llm = MockLLMService()
        let orchestrator = PipelineOrchestrator(llmService: llm)

        await orchestrator.addWords(fourWords(startingAt: 0))
        let first = try await orchestrator.tick(at: 1.8)
        XCTAssertNotNil(first)

        // More words right after
        await orchestrator.addWords(fourWords(startingAt: 2.0))

        // Only 2s after first fire — cooldown (3s) not met
        let second = try await orchestrator.tick(at: 3.8)
        XCTAssertNil(second)
    }

    func testMultipleEmissionsAfterCooldown() async throws {
        let llm = MockLLMService(
            angleResults: [
                AngleResult(topic: "first", angles: ["a1", "a2"]),
                AngleResult(topic: "second", angles: ["b1", "b2"]),
            ]
        )
        let orchestrator = PipelineOrchestrator(llmService: llm)

        // First batch
        await orchestrator.addWords(fourWords(startingAt: 0))
        let first = try await orchestrator.tick(at: 1.8)
        XCTAssertNotNil(first)
        XCTAssertEqual(first?.topic, "first")

        // Second batch after cooldown
        await orchestrator.addWords(fourWords(startingAt: 5.0))
        let second = try await orchestrator.tick(at: 6.8)
        XCTAssertNotNil(second)
        XCTAssertEqual(second?.topic, "second")
    }

    // MARK: - Context Tracking

    func testContextTextReflectsAddedWords() async {
        let orchestrator = PipelineOrchestrator(llmService: MockLLMService())

        let text = await orchestrator.addWords([
            Word(text: "hello", start: 0, end: 0.3),
            Word(text: "world", start: 0.3, end: 0.6),
        ])

        XCTAssertEqual(text, "hello world")
    }

    func testContextPassedToLLMContainsWords() async throws {
        let llm = MockLLMService()
        let orchestrator = PipelineOrchestrator(llmService: llm)

        await orchestrator.addWords([
            Word(text: "I", start: 0, end: 0.2),
            Word(text: "moved", start: 0.2, end: 0.4),
            Word(text: "to", start: 0.4, end: 0.5),
            Word(text: "Chicago", start: 0.5, end: 0.8),
        ])

        _ = try await orchestrator.tick(at: 1.8)

        let contexts = await llm.gateContexts
        XCTAssertEqual(contexts.count, 1)
        XCTAssertTrue(contexts[0].contains("Chicago"))
    }

    // MARK: - Error Handling

    func testLLMErrorPropagates() async {
        struct TestError: Error {}
        let llm = MockLLMService(errorToThrow: TestError())
        let orchestrator = PipelineOrchestrator(llmService: llm)

        await orchestrator.addWords(fourWords(startingAt: 0))

        do {
            _ = try await orchestrator.tick(at: 1.8)
            XCTFail("Expected error to propagate")
        } catch {
            XCTAssertTrue(error is TestError)
        }
    }

    // MARK: - Reset

    func testResetClearsState() async {
        let orchestrator = PipelineOrchestrator(llmService: MockLLMService())

        await orchestrator.addWords(fourWords(startingAt: 0))
        await orchestrator.reset()

        let text = await orchestrator.contextText
        XCTAssertEqual(text, "")
    }

    func testCanEmitAgainAfterReset() async throws {
        let llm = MockLLMService()
        let orchestrator = PipelineOrchestrator(llmService: llm)

        await orchestrator.addWords(fourWords(startingAt: 0))
        _ = try await orchestrator.tick(at: 1.8)

        await orchestrator.reset()

        await orchestrator.addWords(fourWords(startingAt: 10))
        let emission = try await orchestrator.tick(at: 11.8)
        XCTAssertNotNil(emission)
    }

    // MARK: - Helpers

    private func fourWords(startingAt t: TimeInterval) -> [Word] {
        [
            Word(text: "word1", start: t, end: t + 0.2),
            Word(text: "word2", start: t + 0.2, end: t + 0.4),
            Word(text: "word3", start: t + 0.4, end: t + 0.6),
            Word(text: "word4", start: t + 0.6, end: t + 0.8),
        ]
    }
}
