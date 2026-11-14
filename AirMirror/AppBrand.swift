import Foundation

enum AppBrand {
    static var name: String { name(for: [L10n.language.rawValue]) }

    static func name(for preferredLanguages: [String]) -> String {
        let language = AppLanguage.resolve(preferredLanguages: preferredLanguages)
        if language == .simplifiedChinese { return "镜投" }
        if language == .traditionalChinese { return "鏡投" }
        return "AirMirror"
    }
}
