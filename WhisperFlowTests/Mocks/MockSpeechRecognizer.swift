@testable import WhisperFlow
import Foundation

final class MockSpeechRecognizer: SpeechRecognizer {
    private var onWords: (@Sendable ([Word]) -> Void)?
    private(set) var isStarted = false
    var shouldThrowOnStart = false

    func start(onWords: @escaping @Sendable ([Word]) -> Void) throws {
        if shouldThrowOnStart {
            throw NSError(domain: "MockSpeech", code: 1, userInfo: [NSLocalizedDescriptionKey: "Mock start error"])
        }
        self.onWords = onWords
        isStarted = true
    }

    func stop() {
        onWords = nil
        isStarted = false
    }

    /// Test helper: simulate words arriving from the speech recognizer.
    func simulateWords(_ words: [Word]) {
        onWords?(words)
    }
}
