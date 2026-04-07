import Foundation

/// Supported speech recognition languages.
enum Language: String, CaseIterable, Codable {
    case chineseSimplified = "zh-CN"
    case chineseTraditional = "zh-Hant"
    case english = "en-US"
    case japanese = "ja"
    case korean = "ko"

    /// Display name shown in menu.
    var displayName: String {
        switch self {
        case .chineseSimplified: return "简体中文"
        case .chineseTraditional: return "繁體中文"
        case .english: return "English"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        }
    }

    /// Locale for speech recognizer.
    var locale: Locale {
        Locale(identifier: rawValue)
    }

    /// Flag icon name (for future use).
    var flagIcon: String {
        switch self {
        case .chineseSimplified: return "🇨🇳"
        case .chineseTraditional: return "🇹🇼"
        case .english: return "🇺🇸"
        case .japanese: return "🇯🇵"
        case .korean: return "🇰🇷"
        }
    }
}