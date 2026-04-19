import AVFoundation
import Foundation
import Observation
import Speech

@Observable
@MainActor
final class SessionManager {
    private(set) var isActive = false
    private(set) var contextRing = ContextRing()
    private(set) var latestEmission: Emission?
    private(set) var emissions: [Emission] = []
    private(set) var statusMessage = "Ready"
    private(set) var transcriptPreview = ""

    private var tier1Trigger = Tier1Trigger()
    private var pipeline: AudioSpeechPipeline?
    private var anthropicService: AnthropicService?
    private var checkTimer: Task<Void, Never>?
    private var sessionStartTime: Date?
    private var isProcessingTier2 = false

    var apiKey: String {
        UserDefaults.standard.string(forKey: "anthropicAPIKey") ?? ""
    }

    // MARK: - Session Lifecycle

    func start() async {
        guard !isActive else { return }
        guard !apiKey.isEmpty else {
            statusMessage = "Set API key in Settings"
            return
        }

        // Request speech recognition permission
        let speechStatus = await AudioSpeechPipeline.requestAuthorization()
        guard speechStatus == .authorized else {
            statusMessage = "Speech recognition not authorized"
            return
        }

        // Request microphone permission
        let micAuthorized = await AVAudioApplication.requestRecordPermission()
        guard micAuthorized else {
            statusMessage = "Microphone not authorized"
            return
        }

        // Initialize components
        anthropicService = AnthropicService(apiKey: apiKey)
        contextRing = ContextRing()
        tier1Trigger = Tier1Trigger()
        emissions = []
        latestEmission = nil
        transcriptPreview = ""
        sessionStartTime = Date()
        isProcessingTier2 = false

        // Wire up audio → speech → words
        pipeline = AudioSpeechPipeline()
        pipeline?.onNewWords = { [weak self] words in
            Task { @MainActor in
                self?.handleNewWords(words)
            }
        }

        do {
            try pipeline?.start()
        } catch {
            statusMessage = "Failed to start: \(error.localizedDescription)"
            return
        }

        isActive = true
        statusMessage = "Listening…"
        startTier1Timer()
    }

    func stop() {
        isActive = false
        checkTimer?.cancel()
        checkTimer = nil
        pipeline?.stop()
        pipeline = nil
        anthropicService = nil
        sessionStartTime = nil
        isProcessingTier2 = false
        statusMessage = "Session ended · \(emissions.count) angles whispered"
    }

    // MARK: - Word Handling

    private func handleNewWords(_ words: [Word]) {
        for word in words {
            contextRing.add(word)
        }
        // Show last ~80 chars of transcript
        let full = contextRing.text
        if full.count > 80 {
            transcriptPreview = "…" + String(full.suffix(80))
        } else {
            transcriptPreview = full
        }
    }

    // MARK: - Tier 1 Timer

    private func startTier1Timer() {
        checkTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { break }
                await self?.checkTier1()
            }
        }
    }

    private func checkTier1() async {
        guard isActive, !isProcessingTier2, let sessionStart = sessionStartTime else { return }

        let now = Date().timeIntervalSince(sessionStart)

        if tier1Trigger.shouldFire(
            now: now,
            lastWordTime: contextRing.lastWordTime,
            wordCount: contextRing.wordCount
        ) {
            tier1Trigger.markFired(at: now, wordCount: contextRing.wordCount)
            await runTier2(at: now)
        }
    }

    // MARK: - Tier 2 Gate + Angle Generation

    private func runTier2(at timestamp: TimeInterval) async {
        guard let service = anthropicService else { return }

        let context = contextRing.text
        guard !context.isEmpty else { return }

        isProcessingTier2 = true
        statusMessage = "Evaluating…"

        do {
            let shouldProceed = try await service.tier2Gate(context: context)
            guard shouldProceed else {
                statusMessage = "Listening…"
                isProcessingTier2 = false
                return
            }

            statusMessage = "Generating angles…"
            let result = try await service.generateAngles(context: context)

            let emission = Emission(
                timestamp: timestamp,
                context: context,
                topic: result.topic,
                angles: result.angles
            )

            emissions.append(emission)
            latestEmission = emission
            statusMessage = "Listening…"
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }

        isProcessingTier2 = false
    }
}
