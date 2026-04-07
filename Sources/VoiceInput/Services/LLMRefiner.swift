import Foundation

/// LLM-based text refinement using OpenAI-compatible API.
final class LLMRefiner {
    /// LLM configuration.
    var config: LLMConfig

    /// System prompt for conservative error correction.
    private let systemPrompt = """
    You are a conservative speech-to-text error corrector for voice input transcription.
    Your ONLY job is to fix OBVIOUS recognition errors, not to improve or rewrite content.

    Rules:
    1. ONLY fix clear speech recognition mistakes:
       - Chinese homophone errors: "配森" → "Python", "杰森" → "JSON", "苏拉" → "SQL"
       - Technical term misrecognitions: "拆他" → "ChatGPT", "逼它" → "beta"
       - Common word confusions due to similar pronunciation

    2. NEVER do the following:
       - Change wording that seems correct
       - Polish or improve language style
       - Add punctuation that wasn't implied by pauses
       - Delete any content
       - Add new content
       - Change sentence structure

    3. If you're uncertain whether something is an error, leave it unchanged.

    4. Return ONLY the corrected text, no explanations or markers.

    Examples:
    Input: "我用配森写了一个杰森接口"
    Output: "我用Python写了一个JSON接口"

    Input: "今天天气很好，我想去公园散步" (correct)
    Output: "今天天气很好，我想去公园散步" (unchanged)

    Input: "这个bug很拆恼"
    Output: "这个bug很苦恼"
    """

    init(config: LLMConfig = .default) {
        self.config = config
    }

    /// Refine transcription text using LLM.
    func refine(text: String) async throws -> String {
        guard config.isValid else {
            throw LLMError.invalidConfiguration
        }

        guard !text.isEmpty else {
            return text
        }

        guard let url = config.chatCompletionsURL else {
            throw LLMError.invalidURL
        }

        // Build request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")

        // Build body
        let body: [String: Any] = [
            "model": config.model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text]
            ],
            "temperature": 0.1,  // Low temperature for consistent output
            "max_tokens": max(100, text.count * 2)  // Estimate output length
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        // Send request
        let (data, response) = try await URLSession.shared.data(for: request)

        // Check response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw LLMError.apiError(statusCode: httpResponse.statusCode, message: errorMessage)
        }

        // Parse response
        let result = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)

        guard let content = result.choices.first?.message.content else {
            throw LLMError.emptyResponse
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Test API connection with a simple request.
    func testConnection() async throws -> Bool {
        guard config.isValid else {
            return false
        }

        guard let url = config.chatCompletionsURL else {
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")

        // Simple test request
        let body: [String: Any] = [
            "model": config.model,
            "messages": [
                ["role": "user", "content": "Hello"]
            ],
            "max_tokens": 5
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }

        return httpResponse.statusCode == 200
    }
}

// MARK: - Response Models

private struct ChatCompletionResponse: Codable {
    let choices: [Choice]

    struct Choice: Codable {
        let message: Message
    }

    struct Message: Codable {
        let content: String
    }
}

// MARK: - Errors

enum LLMError: LocalizedError {
    case invalidConfiguration
    case invalidURL
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case emptyResponse
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "LLM configuration is incomplete or invalid"
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid response from API"
        case .apiError(let statusCode, let message):
            return "API error (\(statusCode)): \(message)"
        case .emptyResponse:
            return "Empty response from LLM"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}