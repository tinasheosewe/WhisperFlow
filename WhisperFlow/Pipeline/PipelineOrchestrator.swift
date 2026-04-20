import Foundation

/// Pure pipeline logic — no I/O, no timers, no UI.
/// Owns the ContextRing, PauseDetector, and LLM coordination.
/// Fully testable: feed words via `addWords`, drive time via `tick(at:)`.
actor PipelineOrchestrator {
    private var contextRing: ContextRing
    private var pauseDetector: PauseDetector
    private let llmService: any LLMService
    private var isProcessing = false

    init(
        llmService: any LLMService,
        contextRing: ContextRing = ContextRing(),
        pauseDetector: PauseDetector = PauseDetector()
    ) {
        self.llmService = llmService
        self.contextRing = contextRing
        self.pauseDetector = pauseDetector
    }

    /// Current transcript text (for UI preview).
    var contextText: String { contextRing.text }

    /// Feed words from the speech recognizer. Returns current context text.
    @discardableResult
    func addWords(_ words: [Word]) -> String {
        for word in words { contextRing.add(word) }
        return contextRing.text
    }

    /// Check pause → emission gate → angle generation at the given timestamp.
    /// Returns an `Emission` if all checks pass, `nil` if suppressed, throws on LLM errors.
    func tick(at now: TimeInterval) async throws -> Emission? {
        guard !isProcessing else { return nil }

        guard pauseDetector.shouldFire(
            now: now,
            lastWordTime: contextRing.lastWordTime,
            wordCount: contextRing.totalWordsAdded
        ) else { return nil }

        // Commit the fire — prevents re-evaluation of the same moment
        pauseDetector.markFired(at: now, wordCount: contextRing.totalWordsAdded)
        isProcessing = true
        defer { isProcessing = false }

        let context = contextRing.text
        guard !context.isEmpty else { return nil }

        let shouldProceed = try await llmService.evaluateGate(context: context)
        guard shouldProceed else { return nil }

        let result = try await llmService.generateAngles(context: context)
        return Emission(
            timestamp: now,
            context: context,
            result: result
        )
    }

    /// Reset all state for a new session.
    func reset() {
        contextRing.clear()
        pauseDetector.reset()
        isProcessing = false
    }
}
