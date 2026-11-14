import AppKit
import Combine

@MainActor
final class LanguagePreferences: ObservableObject {
    static let shared = LanguagePreferences()
    @Published private(set) var selection: AppLanguage
    @Published private(set) var needsInitialChoice: Bool

    private init() {
        selection = AppLanguage(rawValue: UserDefaults.standard.string(forKey: L10n.preferenceKey) ?? "system") ?? .system
        needsInitialChoice = !UserDefaults.standard.bool(forKey: "languageSetupCompleted")
    }

    func select(_ language: AppLanguage) {
        guard selection != language else { return }
        UserDefaults.standard.set(language.rawValue, forKey: L10n.preferenceKey)
        selection = language
        NotificationCenter.default.post(name: .appLanguageDidChange, object: nil)
        DispatchQueue.main.async { NativeMenuLocalization.update() }
    }

    func completeSetup() {
        UserDefaults.standard.set(true, forKey: "languageSetupCompleted")
        needsInitialChoice = false
        AppState.shared.start()
        WindowPasteState.shared.start()
        NativeMenuLocalization.update()
    }
}
