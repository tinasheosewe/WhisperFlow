import Foundation

/// Result from angle generation — shared between LLM implementations and the pipeline.
struct AngleResult: Sendable, Equatable {
    let topic: String
    let angles: [String]
}

/// Abstraction for the LLM backend powering the Tier 2 gate and angle generation.
/// Conformers: `AnthropicLLMService`, mock implementations for testing.
protocol LLMService: Sendable {
    func evaluateGate(context: String) async throws -> Bool
    func generateAngles(context: String) async throws -> AngleResult
}

enum LLMServiceError: LocalizedError {
    case invalidResponse
    case apiError(statusCode: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "Invalid API response"
        case .apiError(let code, let body):
            "API error (\(code)): \(body)"
        }
    }
}
