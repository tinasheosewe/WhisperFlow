import Foundation

/// Abstraction for speech-to-text engines.
/// Conformers: `AppleSpeechRecognizer` (SFSpeech), future WhisperKit, etc.
protocol SpeechRecognizer: AnyObject {
    func start(onWords: @escaping @Sendable ([Word]) -> Void) throws
    func stop()
}
