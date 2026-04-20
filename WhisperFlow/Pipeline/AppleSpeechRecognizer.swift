import AVFoundation
import Speech

/// SFSpeechRecognizer-based implementation of `SpeechRecognizer`.
/// Uses on-device recognition when available.
final class AppleSpeechRecognizer: SpeechRecognizer {
    private let audioEngine = AVAudioEngine()
    private let speechRecognizer: SFSpeechRecognizer
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var processedSegmentCount = 0
    private var onWords: (@Sendable ([Word]) -> Void)?

    init(locale: Locale = Locale(identifier: "en-US")) {
        speechRecognizer = SFSpeechRecognizer(locale: locale)!
    }

    func start(onWords: @escaping @Sendable ([Word]) -> Void) throws {
        self.onWords = onWords

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .default,
            options: [.defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP]
        )
        try session.setActive(true)

        processedSegmentCount = 0
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else { return }

        request.shouldReportPartialResults = true
        if speechRecognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        request.addsPunctuation = true

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, _ in
            if let result { self?.processResult(result) }
        }

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
    }

    func stop() {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        onWords = nil
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    // MARK: - Authorization (platform-specific, not part of protocol)

    static func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    // MARK: - Private

    private func processResult(_ result: SFSpeechRecognitionResult) {
        let segments = result.bestTranscription.segments
        guard segments.count > processedSegmentCount else { return }

        let newSegments = segments[processedSegmentCount...]
        processedSegmentCount = segments.count

        let words = newSegments.map { segment in
            Word(
                text: segment.substring,
                start: segment.timestamp,
                end: segment.timestamp + segment.duration,
                speaker: .unknown
            )
        }

        if !words.isEmpty {
            onWords?(words)
        }
    }
}
