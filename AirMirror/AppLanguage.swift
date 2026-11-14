import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case english = "en"
    case japanese = "ja"
    case korean = "ko"
    case french = "fr"
    case german = "de"
    case spanish = "es"
    case portuguese = "pt-BR"
    case italian = "it"
    case russian = "ru"
    case arabic = "ar"
    case hindi = "hi"
    case indonesian = "id"

    var id: String { rawValue }
    static var supported: [Self] { allCases.filter { $0 != .system } }
    var isRightToLeft: Bool { self == .arabic }
    var nativeName: String {
        switch self {
        case .system: return L10n.tr("跟随系统")
        case .simplifiedChinese: return "简体中文"
        case .traditionalChinese: return "繁體中文"
        case .english: return "English"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        case .french: return "Français"
        case .german: return "Deutsch"
        case .spanish: return "Español"
        case .portuguese: return "Português (Brasil)"
        case .italian: return "Italiano"
        case .russian: return "Русский"
        case .arabic: return "العربية"
        case .hindi: return "हिन्दी"
        case .indonesian: return "Bahasa Indonesia"
        }
    }

    static var systemPreferredLanguages: [String] {
        Locale.preferredLanguages
    }

    static func resolve(preferredLanguages: [String]) -> Self {
        for raw in preferredLanguages {
            let tag = raw.replacingOccurrences(of: "_", with: "-").lowercased()
            if tag.hasPrefix("zh") {
                return tag.contains("hant") || tag.hasSuffix("-tw") || tag.hasSuffix("-hk") || tag.hasSuffix("-mo")
                    ? .traditionalChinese : .simplifiedChinese
            }
            if let match = supported.first(where: { tag == $0.rawValue.lowercased() }) { return match }
            let base = tag.split(separator: "-").first.map(String.init)
            if let match = supported.first(where: { $0.rawValue.lowercased().split(separator: "-").first.map(String.init) == base }) { return match }
        }
        return .english
    }
}

extension Notification.Name {
    static let appLanguageDidChange = Notification.Name("AirMirror.AppLanguageDidChange")
}
