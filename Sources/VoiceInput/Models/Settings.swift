import Foundation

/// Application settings stored in UserDefaults.
@MainActor
final class Settings: ObservableObject {
    static let shared = Settings()

    // UserDefaults keys
    private enum Key: String {
        case selectedLanguage = "selectedLanguage"
        case llmEnabled = "llmEnabled"
        case llmConfig = "llmConfig"
    }

    // Published properties for SwiftUI binding
    @Published var selectedLanguage: String {
        didSet { defaults.set(selectedLanguage, forKey: Key.selectedLanguage.rawValue) }
    }

    @Published var llmEnabled: Bool {
        didSet { defaults.set(llmEnabled, forKey: Key.llmEnabled.rawValue) }
    }

    @Published var llmConfig: LLMConfig {
        didSet {
            if let data = try? JSONEncoder().encode(llmConfig),
               let string = String(data: data, encoding: .utf8) {
                defaults.set(string, forKey: Key.llmConfig.rawValue)
            }
        }
    }

    private let defaults = UserDefaults.standard

    private init() {
        // Initialize all stored properties first
        let lang = defaults.string(forKey: Key.selectedLanguage.rawValue) ?? "zh-CN"
        selectedLanguage = lang

        llmEnabled = defaults.bool(forKey: Key.llmEnabled.rawValue)

        if let configString = defaults.string(forKey: Key.llmConfig.rawValue),
           let data = configString.data(using: .utf8),
           let config = try? JSONDecoder().decode(LLMConfig.self, from: data) {
            llmConfig = config
        } else {
            llmConfig = .default
        }
    }

    // MARK: - Convenience

    var language: Language? {
        Language(rawValue: selectedLanguage)
    }

    // MARK: - Reset

    func resetLLMConfig() {
        llmConfig = .default
    }
}