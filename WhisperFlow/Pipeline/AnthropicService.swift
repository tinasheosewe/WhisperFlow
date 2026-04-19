import Foundation

actor AnthropicService {
    private let apiKey: String
    private let gateModel = "claude-haiku-4-5-20251001"
    private let angleModel = "claude-sonnet-4-6"
    private let baseURL = URL(string: "https://api.anthropic.com/v1/messages")!

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    struct AngleResult: Sendable {
        let topic: String
        let angles: [String]
    }

    func tier2Gate(context: String) async throws -> Bool {
        let response = try await callAPI(
            model: gateModel,
            system: Prompts.tier2GateSystem,
            user: Prompts.formatGateUser(context: context),
            maxTokens: 3
        )
        return response.uppercased().contains("YES")
    }

    func generateAngles(context: String) async throws -> AngleResult {
        let response = try await callAPI(
            model: angleModel,
            system: Prompts.angleGeneratorSystem,
            user: Prompts.formatAngleUser(context: context),
            maxTokens: 100
        )

        guard let data = response.data(using: .utf8) else {
            throw ServiceError.invalidResponse
        }

        struct AngleJSON: Codable {
            let topic: String
            let angles: [String]
        }

        let parsed = try JSONDecoder().decode(AngleJSON.self, from: data)
        return AngleResult(topic: parsed.topic, angles: parsed.angles)
    }

    // MARK: - Private

    private struct APIResponse: Codable {
        struct Content: Codable {
            let text: String
        }
        let content: [Content]
    }

    private func callAPI(model: String, system: String, user: String, maxTokens: Int) async throws -> String {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": system,
            "messages": [
                ["role": "user", "content": user]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, httpResponse) = try await URLSession.shared.data(for: request)

        guard let http = httpResponse as? HTTPURLResponse, http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ServiceError.apiError(body)
        }

        let decoded = try JSONDecoder().decode(APIResponse.self, from: data)
        guard let text = decoded.content.first?.text else {
            throw ServiceError.invalidResponse
        }

        return text
    }

    enum ServiceError: LocalizedError {
        case invalidResponse
        case apiError(String)

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "Invalid API response"
            case .apiError(let detail):
                return "API error: \(detail)"
            }
        }
    }
}
