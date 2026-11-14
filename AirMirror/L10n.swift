import Foundation

enum L10n {
    static let preferenceKey = "appLanguage"
    static var language: AppLanguage {
        let chosen = AppLanguage(rawValue: UserDefaults.standard.string(forKey: preferenceKey) ?? "system") ?? .system
        return chosen == .system ? AppLanguage.resolve(preferredLanguages: AppLanguage.systemPreferredLanguages) : chosen
    }
    static var locale: Locale { Locale(identifier: language.rawValue) }
    private static let bundles: [AppLanguage: Bundle] = Dictionary(uniqueKeysWithValues: AppLanguage.supported.compactMap { language in
        guard let url = Bundle.main.url(forResource: language.rawValue, withExtension: "lproj"),
              let bundle = Bundle(url: url) else { return nil }
        return (language, bundle)
    })

    static func value(_ key: String, language: AppLanguage) -> String {
        let missing = "__AIRMIRROR_MISSING_TRANSLATION__"
        let text = bundles[language]?.localizedString(forKey: key, value: missing, table: "Localizable") ?? missing
        if text != missing { return text }
        return bundles[.english]?.localizedString(forKey: key, value: key, table: "Localizable") ?? key
    }

    static func tr(_ key: String, _ arguments: String...) -> String {
        let format = value(key, language: language)
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: locale, arguments: arguments)
    }
}
