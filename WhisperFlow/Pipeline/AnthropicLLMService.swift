import Foundation

/// Anthropic Claude implementation of `LLMService`.
/// Uses claude-haiku for the fast gate and claude-sonnet for angle generation.
actor AnthropicLLMService: LLMService {
    private let apiKey: String
    private let gateModel: String
    private let angleModel: String
    private let baseURL: URL
    private let session: URLSession

    init(
        apiKey: String,
        gateModel: String = "claude-haiku-4-5-20251001",
        angleModel: String = "claude-sonnet-4-6",
        baseURL: URL = URL(string: "https://api.anthropic.com/v1/messages")!,
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.gateModel = gateModel
        self.angleModel = angleModel
        self.baseURL = baseURL
        self.session = session
    }

    func evaluateGate(context: String) async throws -> Bool {
        let response = try await callAPI(
            model: gateModel,
            system: Prompts.emissionGateSystem,
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
            throw LLMServiceError.invalidResponse
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

        let (data, httpResponse) = try await session.data(for: request)

        guard let http = httpResponse as? HTTPURLResponse, http.statusCode == 200 else {
            let statusCode = (httpResponse as? HTTPURLResponse)?.statusCode ?? 0
            let responseBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw LLMServiceError.apiError(statusCode: statusCode, body: responseBody)
        }

        let decoded = try JSONDecoder().decode(APIResponse.self, from: data)
        guard let text = decoded.content.first?.text else {
            throw LLMServiceError.invalidResponse
        }

        return text
    }
}
