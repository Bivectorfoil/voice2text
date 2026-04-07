import Foundation

/// LLM API configuration for text refinement.
struct LLMConfig: Codable, Equatable {
    /// Base URL for OpenAI-compatible API (e.g., "https://api.openai.com/v1").
    var baseURL: String

    /// API key for authentication.
    var apiKey: String

    /// Model name (e.g., "gpt-4o-mini").
    var model: String

    /// Default configuration using OpenAI official API.
    static let `default` = LLMConfig(
        baseURL: "https://api.openai.com/v1",
        apiKey: "",
        model: "gpt-4o-mini"
    )

    /// Check if configuration is valid for API calls.
    var isValid: Bool {
        !baseURL.isEmpty && !apiKey.isEmpty && !model.isEmpty
    }

    /// Full URL for chat completions endpoint.
    var chatCompletionsURL: URL? {
        var base = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: "\(base)/chat/completions")
    }
}