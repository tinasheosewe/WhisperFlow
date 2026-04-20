import AVFoundation
import Foundation
import Observation
import Speech

@Observable
@MainActor
final class SessionManager {
    // MARK: - Observable State

    private(set) var isActive = false
    private(set) var latestEmission: Emission?
    private(set) var emissions: [Emission] = []
    private(set) var statusMessage = "Ready"
    private(set) var transcriptPreview = ""

    // MARK: - Dependencies

    private let makeSpeechRecognizer: () -> any SpeechRecognizer
    private let makeLLMService: (String) -> any LLMService
    private let apiKeyProvider: () -> String
    private let authorizeSpeech: () async -> Bool
    private let authorizeMicrophone: () async -> Bool

    // MARK: - Internal State

    private var orchestrator: PipelineOrchestrator?
    private var speechRecognizer: (any SpeechRecognizer)?
    private var checkTimer: Task<Void, Never>?
    private var sessionStartTime: Date?

    init(
        makeSpeechRecognizer: @escaping () -> any SpeechRecognizer = { AppleSpeechRecognizer() },
        makeLLMService: @escaping (String) -> any LLMService = { AnthropicLLMService(apiKey: $0) },
        apiKeyProvider: @escaping () -> String = { UserDefaults.standard.string(forKey: "anthropicAPIKey") ?? "" },
        authorizeSpeech: @escaping () async -> Bool = {
            await AppleSpeechRecognizer.requestAuthorization() == .authorized
        },
        authorizeMicrophone: @escaping () async -> Bool = {
            await AVAudioApplication.requestRecordPermission()
        }
    ) {
        self.makeSpeechRecognizer = makeSpeechRecognizer
        self.makeLLMService = makeLLMService
        self.apiKeyProvider = apiKeyProvider
        self.authorizeSpeech = authorizeSpeech
        self.authorizeMicrophone = authorizeMicrophone
    }

    // MARK: - Session Lifecycle

    func start() async {
        guard !isActive else { return }

        let apiKey = apiKeyProvider()
        guard !apiKey.isEmpty else {
            statusMessage = "Set API key in Settings"
            return
        }

        guard await authorizeSpeech() else {
            statusMessage = "Speech recognition not authorized"
            return
        }

        guard await authorizeMicrophone() else {
            statusMessage = "Microphone not authorized"
            return
        }

        let llmService = makeLLMService(apiKey)
        orchestrator = PipelineOrchestrator(llmService: llmService)
        emissions = []
        latestEmission = nil
        transcriptPreview = ""
        sessionStartTime = Date()

        let recognizer = makeSpeechRecognizer()
        speechRecognizer = recognizer

        do {
            try recognizer.start { [weak self] words in
                Task { @MainActor in
                    await self?.handleNewWords(words)
                }
            }
        } catch {
            statusMessage = "Failed to start: \(error.localizedDescription)"
            return
        }

        isActive = true
        statusMessage = "Listening…"
        startCheckTimer()
    }

    func stop() {
        isActive = false
        checkTimer?.cancel()
        checkTimer = nil
        speechRecognizer?.stop()
        speechRecognizer = nil
        orchestrator = nil
        sessionStartTime = nil
        statusMessage = "Session ended · \(emissions.count) angles whispered"
    }

    // MARK: - Private

    private func handleNewWords(_ words: [Word]) async {
        guard let orchestrator else { return }
        let text = await orchestrator.addWords(words)
        if text.count > 80 {
            transcriptPreview = "…" + String(text.suffix(80))
        } else {
            transcriptPreview = text
        }
    }

    private func startCheckTimer() {
        checkTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { break }
                await self?.onTick()
            }
        }
    }

    private func onTick() async {
        guard isActive, let orchestrator, let sessionStart = sessionStartTime else { return }
        let now = Date().timeIntervalSince(sessionStart)

        do {
            if let emission = try await orchestrator.tick(at: now) {
                emissions.append(emission)
                latestEmission = emission
            }
            if statusMessage.hasPrefix("Error") {
                statusMessage = "Listening…"
            }
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }
    }
}
